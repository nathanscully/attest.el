;;; attest-node.el --- node --test backend for attest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/attest.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Runs tests with Node's built-in runner (`node --test').  Two
;; reporters run at once: `spec' writes human-readable output to stdout
;; for the output buffer, and the bundled attest-node-reporter.mjs
;; writes one `attest:test' JSON event per finished test to stderr.
;; The reporter tracks suite nesting and flattens the error's cause so
;; the event already carries the full name path, a state and a message;
;; attest-vitest-reporter.mjs emits the same shape, and attest-vitest.el
;; reuses `attest-node--parse-line'.

;;; Code:

(require 'attest)
(require 'url-util)

(defgroup attest-node nil
  "Node test runner backend for attest."
  :group 'attest
  :prefix "attest-node-")

(defcustom attest-node-executable "node"
  "Node program that runs `node --test'."
  :type 'string
  :package-version '(attest . "0.1.0"))

(defcustom attest-node-extra-args nil
  "Arguments inserted after `--test'."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defcustom attest-node-env '("FORCE_COLOR=1")
  "Environment entries added when running tests."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defcustom attest-node-test-file-regexp
  "\\(?:[._-]test\\|[._-]spec\\)\\.[cm]?[jt]sx?\\'"
  "Regexp matching test file names."
  :type 'regexp
  :package-version '(attest . "0.1.0"))

(defconst attest-node--reporter
  (expand-file-name "attest-node-reporter.mjs"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Absolute path of the bundled JSON-lines reporter.")

(defconst attest-node--query
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

(defun attest-node-root (file)
  "Return the nearest directory above FILE holding a package.json.
Falls back to the `project-current' root."
  (or (locate-dominating-file file "package.json")
      (when-let* ((project (project-current nil (file-name-directory file))))
        (expand-file-name (project-root project)))))

(defun attest-node-test-file-p (file)
  "Return non-nil when FILE looks like a node test file."
  (and (string-match-p attest-node-test-file-regexp file)
       (not (string-match-p "/node_modules/" file))))

(defun attest-node--buffer-p ()
  "Return non-nil when the current buffer is a JavaScript or TypeScript test."
  (and buffer-file-name
       (derived-mode-p 'typescript-ts-mode 'tsx-ts-mode 'js-ts-mode 'js-mode)
       (attest-node-test-file-p buffer-file-name)))

(defun attest-node--query (file)
  "Return the discovery query for FILE's language."
  (cons (pcase (file-name-extension file)
          ("tsx" 'tsx)
          ((or "ts" "mts" "cts") 'typescript)
          (_ 'javascript))
        attest-node--query))

(defun attest-node-regexp-quote (string)
  "Return STRING escaped for use in a JavaScript regular expression.
Used for `--test-name-pattern' here and for `-t' in attest-vitest.el."
  (replace-regexp-in-string "[][.*+?^${}()|\\\\/]" "\\\\\\&" string))

(defun attest-node--name-pattern (target)
  "Return a --test-name-pattern argument selecting TARGET.
A test matches exactly; a namespace also matches every test below it."
  (let ((name (attest-node-regexp-quote
               (string-join (attest-id-names (plist-get target :id)) " "))))
    (format "--test-name-pattern=^%s%s" name
            (if (eq (plist-get target :type) 'namespace) "( |$)" "$"))))

(defun attest-node--command (run)
  "Return the process spec for RUN."
  (let* ((scope (plist-get run :scope))
         (root (plist-get run :root))
         (files (attest-run-files run))
         (patterns (and (eq scope 'targets)
                        (mapcar #'attest-node--name-pattern
                                (plist-get run :targets)))))
    (when (and (eq scope 'project) (null files))
      (user-error "Attest: no test files found under %s" root))
    (list :command (append (list attest-node-executable "--test")
                           attest-node-extra-args
                           (list "--test-reporter=spec"
                                 "--test-reporter-destination=stdout"
                                 (concat "--test-reporter=" attest-node--reporter)
                                 "--test-reporter-destination=stderr")
                           patterns
                           (mapcar (lambda (f) (file-relative-name f root)) files))
          :directory root
          :env attest-node-env
          :parse-stream 'stderr)))

(defun attest-node--frame-in-file (stack file)
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

(defun attest-node--result (event)
  "Return a result plist for a `attest:test' EVENT.
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
    (append (list :id (apply #'attest-make-id file names)
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
                    :location (attest-node--frame-in-file stack file))))))

(defun attest-node--parse-line (run line)
  "Parse one reporter LINE from RUN into a result or nil.
Lines that are not JSON, such as syntax errors, go to the output."
  (if (string-prefix-p "{" line)
      (when-let* ((event (ignore-errors
                           (json-parse-string line :object-type 'alist
                                              :null-object nil :false-object nil))))
        (when (equal (alist-get 'type event) "attest:test")
          (attest-node--result event)))
    (attest-append-output run (concat line "\n"))
    nil))

(attest-register-backend 'node
  :predicate #'attest-node--buffer-p
  :test-file-p #'attest-node-test-file-p
  :root #'attest-node-root
  :query #'attest-node--query
  :command #'attest-node--command
  :parse-line #'attest-node--parse-line)

(provide 'attest-node)
;;; attest-node.el ends here
