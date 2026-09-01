;;; neotest-node.el --- node --test backend for neotest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/emacs-neotest

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Runs tests with Node's built-in runner (`node --test').  Two
;; reporters run at once: `spec' writes human-readable output to stdout
;; for the output buffer, and the bundled neotest-node-reporter.mjs
;; writes one `neotest:test' JSON event per finished test to stderr.
;; The reporter tracks suite nesting and flattens the error's cause so
;; the event already carries the full name path, a state and a message;
;; neotest-vitest-reporter.mjs emits the same shape, and neotest-vitest.el
;; reuses `neotest-node--parse-line'.

;;; Code:

(require 'neotest)
(require 'url-util)

(defgroup neotest-node nil
  "Node test runner backend for neotest."
  :group 'neotest
  :prefix "neotest-node-")

(defcustom neotest-node-executable "node"
  "Node program that runs `node --test'."
  :type 'string
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-node-extra-args nil
  "Arguments inserted after `--test'."
  :type '(repeat string)
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-node-env '("FORCE_COLOR=1")
  "Environment entries added when running tests."
  :type '(repeat string)
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-node-test-file-regexp
  "\\(?:[._-]test\\|[._-]spec\\)\\.[cm]?[jt]sx?\\'"
  "Regexp matching test file names."
  :type 'regexp
  :package-version '(neotest . "0.1.0"))

(defconst neotest-node--reporter
  (expand-file-name "neotest-node-reporter.mjs"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Absolute path of the bundled JSON-lines reporter.")

(defconst neotest-node--query
  '(((call_expression
      function: (identifier) @fn
      arguments: (arguments :anchor (_) @namespace.name))
     @namespace.definition
     (:match "\\`\\(?:describe\\|suite\\)\\'" @fn))
    ((call_expression
      function: (member_expression
                 object: (identifier) @fn
                 property: (property_identifier) @mod)
      arguments: (arguments :anchor (_) @namespace.name))
     @namespace.definition
     (:match "\\`\\(?:describe\\|suite\\)\\'" @fn)
     (:match "\\`\\(?:skip\\|todo\\|only\\)\\'" @mod))
    ((call_expression
      function: (identifier) @fn
      arguments: (arguments :anchor (_) @test.name))
     @test.definition
     (:match "\\`\\(?:test\\|it\\)\\'" @fn))
    ((call_expression
      function: (member_expression
                 object: (identifier) @fn
                 property: (property_identifier) @mod)
      arguments: (arguments :anchor (_) @test.name))
     @test.definition
     (:match "\\`\\(?:test\\|it\\)\\'" @fn)
     (:match "\\`\\(?:skip\\|todo\\|only\\)\\'" @mod)))
  "Query matching node:test declarations in JavaScript and TypeScript.")

(defun neotest-node-root (file)
  "Return the nearest directory above FILE holding a package.json.
Falls back to the `project-current' root."
  (or (locate-dominating-file file "package.json")
      (when-let* ((project (project-current nil (file-name-directory file))))
        (expand-file-name (project-root project)))))

(defun neotest-node-test-file-p (file)
  "Return non-nil when FILE looks like a node test file."
  (and (string-match-p neotest-node-test-file-regexp file)
       (not (string-match-p "/node_modules/" file))))

(defun neotest-node--buffer-p ()
  "Return non-nil when the current buffer is a JavaScript or TypeScript test."
  (and buffer-file-name
       (derived-mode-p 'typescript-ts-mode 'tsx-ts-mode 'js-ts-mode 'js-mode)
       (neotest-node-test-file-p buffer-file-name)))

(defun neotest-node--query (file)
  "Return the discovery query for FILE's language."
  (cons (pcase (file-name-extension file)
          ("tsx" 'tsx)
          ((or "ts" "mts" "cts") 'typescript)
          (_ 'javascript))
        neotest-node--query))

(defun neotest-node-regexp-quote (string)
  "Return STRING escaped for use in a JavaScript regular expression.
Used for `--test-name-pattern' here and for `-t' in neotest-vitest.el."
  (replace-regexp-in-string "[][.*+?^${}()|\\\\/]" "\\\\\\&" string))

(defun neotest-node--name-pattern (target)
  "Return a --test-name-pattern argument selecting TARGET.
A test matches exactly; a namespace also matches every test below it."
  (let ((name (neotest-node-regexp-quote
               (string-join (neotest-id-names (plist-get target :id)) " "))))
    (format "--test-name-pattern=^%s%s" name
            (if (eq (plist-get target :type) 'namespace) "( |$)" "$"))))

(defun neotest-node--command (run)
  "Return the process spec for RUN."
  (let* ((scope (plist-get run :scope))
         (root (plist-get run :root))
         (files (neotest-run-files run))
         (patterns (and (eq scope 'targets)
                        (mapcar #'neotest-node--name-pattern
                                (plist-get run :targets)))))
    (when (and (eq scope 'project) (null files))
      (user-error "Neotest: no test files found under %s" root))
    (list :command (append (list neotest-node-executable "--test")
                           neotest-node-extra-args
                           (list "--test-reporter=spec"
                                 "--test-reporter-destination=stdout"
                                 (concat "--test-reporter=" neotest-node--reporter)
                                 "--test-reporter-destination=stderr")
                           patterns
                           (mapcar (lambda (f) (file-relative-name f root)) files))
          :directory root
          :env neotest-node-env
          :parse-stream 'stderr)))

(defun neotest-node--frame-in-file (stack file)
  "Return (LINE . COLUMN) of the first frame of STACK located in FILE."
  (let ((start 0) found)
    (while (and (not found)
                (string-match "\\(?:file://\\)?\\(/[^:()[:space:]]+\\):\\([0-9]+\\):\\([0-9]+\\)"
                              stack start))
      (setq start (match-end 0))
      (when (string= (url-unhex-string (match-string 1 stack)) file)
        (setq found (cons (string-to-number (match-string 2 stack))
                          (string-to-number (match-string 3 stack))))))
    found))

(defun neotest-node--result (event)
  "Return a result plist for a `neotest:test' EVENT.
EVENT carries `names' outermost first, `file', `location', `state',
`duration' and `errors'.  Both bundled reporters emit this shape."
  (let* ((names (append (alist-get 'names event) nil))
         (file (alist-get 'file event))
         (location (alist-get 'location event))
         (error (car (append (alist-get 'errors event) nil)))
         (stack (or (alist-get 'stack error) ""))
         (status (pcase (alist-get 'state event)
                   ("passed" 'passed)
                   ("failed" 'failed)
                   ("todo" 'todo)
                   (_ (if (equal (alist-get 'mode event) "todo") 'todo 'skipped)))))
    (append (list :id (apply #'neotest-make-id file names)
                  :type (if (equal (alist-get 'kind event) "namespace") 'namespace 'test)
                  :name (car (last names))
                  :status status
                  :file file
                  :line (alist-get 'line location)
                  :column (alist-get 'column location)
                  :duration (alist-get 'duration event))
            (when (eq status 'failed)
              (list :message (or (alist-get 'message error) "test failed")
                    :stack stack
                    :location (neotest-node--frame-in-file stack file))))))

(defun neotest-node--parse-line (run line)
  "Parse one reporter LINE from RUN into a result or nil.
Lines that are not JSON, such as syntax errors, go to the output."
  (if (string-prefix-p "{" line)
      (when-let* ((event (ignore-errors
                           (json-parse-string line :object-type 'alist
                                              :null-object nil :false-object nil))))
        (when (equal (alist-get 'type event) "neotest:test")
          (neotest-node--result event)))
    (neotest-append-output run (concat line "\n"))
    nil))

(neotest-register-backend 'node
  :predicate #'neotest-node--buffer-p
  :test-file-p #'neotest-node-test-file-p
  :root #'neotest-node-root
  :query #'neotest-node--query
  :command #'neotest-node--command
  :parse-line #'neotest-node--parse-line)

(provide 'neotest-node)
;;; neotest-node.el ends here
