;;; neotest-node.el --- node --test backend for neotest -*- lexical-binding: t; -*-

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Runs tests with Node's built-in runner (`node --test').  Two
;; reporters run at once: `spec' writes human-readable output to stdout
;; for the output buffer, and the bundled neotest-node-reporter.mjs
;; writes one JSON event per line to stderr for parsing.  The reporter
;; exists only because JSON.stringify drops an Error's message and
;; stack; it adds nothing else.

;;; Code:

(require 'neotest)
(require 'json)
(require 'url-util)

(defgroup neotest-node nil
  "Node test runner backend for neotest."
  :group 'neotest
  :prefix "neotest-node-")

(defcustom neotest-node-executable "node"
  "Program used to run tests."
  :type 'string)

(defcustom neotest-node-extra-args nil
  "Arguments inserted after `--test'."
  :type '(repeat string))

(defcustom neotest-node-env '("FORCE_COLOR=1")
  "Environment entries added when running tests."
  :type '(repeat string))

(defcustom neotest-node-test-file-regexp
  "\\(?:[._-]test\\|[._-]spec\\)\\.[cm]?[jt]sx?\\'"
  "Regexp matching test file names."
  :type 'regexp)

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

(defun neotest-node--query ()
  "Return the discovery query for the current buffer's language."
  (cons (cond ((derived-mode-p 'tsx-ts-mode) 'tsx)
              ((derived-mode-p 'typescript-ts-mode) 'typescript)
              (t 'javascript))
        neotest-node--query))

(defun neotest-node-regexp-quote (string)
  "Return STRING escaped for use in a JavaScript regular expression."
  (replace-regexp-in-string "[][.*+?^${}()|\\\\/]" "\\\\\\&" string))

(defun neotest-node--name-pattern (id type)
  "Return a --test-name-pattern argument selecting ID of TYPE."
  (let ((name (neotest-node-regexp-quote
               (string-join (neotest-id-names id) " "))))
    (format "--test-name-pattern=^%s%s" name
            (if (eq type 'test) "$" "( |$)"))))

(defun neotest-node--command (run)
  "Return the process spec for RUN."
  (let* ((scope (plist-get run :scope))
         (root (plist-get run :root))
         (position (plist-get run :position))
         (files (pcase scope
                  ('project (plist-get run :files))
                  ('results (delete-dups
                             (mapcar (lambda (r) (plist-get r :file))
                                     (plist-get run :results))))
                  (_ (list (plist-get run :file)))))
         (patterns (pcase scope
                     ((or 'test 'namespace)
                      (list (neotest-node--name-pattern
                             (plist-get position :id) (plist-get position :type))))
                     ('results
                      (mapcar (lambda (r)
                                (neotest-node--name-pattern (plist-get r :id) 'test))
                              (plist-get run :results))))))
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

(defun neotest-node--set-active (run nesting name)
  "Record NAME as the running test at NESTING for RUN, dropping deeper levels."
  (let ((active (seq-filter (lambda (entry) (< (car entry) nesting))
                            (plist-get (plist-get run :state) :active))))
    (plist-put run :state
               (plist-put (plist-get run :state) :active
                          (cons (cons nesting name) active)))))

(defun neotest-node--names (run nesting name)
  "Return the ancestor names above NESTING in RUN followed by NAME."
  (let ((active (plist-get (plist-get run :state) :active)))
    (append (mapcar #'cdr (sort (seq-filter (lambda (e) (< (car e) nesting)) active)
                                (lambda (a b) (< (car a) (car b)))))
            (list name))))

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

(defun neotest-node--failure (error file)
  "Return (:message MESSAGE :location (LINE . COLUMN)) for ERROR in FILE."
  (let* ((cause (alist-get 'cause error))
         (inner (if (consp cause) cause error))
         (message (or (alist-get 'message inner)
                      (and (stringp cause) cause)
                      (alist-get 'message error)
                      "test failed"))
         (stack (or (alist-get 'stack inner) "")))
    (list :message message
          :stack stack
          :location (neotest-node--frame-in-file stack file))))

(defun neotest-node--result (run type data)
  "Return a result plist for a TYPE event carrying DATA in RUN."
  (let* ((name (alist-get 'name data))
         (file (alist-get 'file data))
         (nesting (or (alist-get 'nesting data) 0))
         (details (alist-get 'details data))
         (kind (if (equal (alist-get 'type details) "suite") 'namespace 'test))
         (names (neotest-node--names run nesting name))
         (status (cond ((alist-get 'skip data) 'skipped)
                       ((alist-get 'todo data) 'todo)
                       ((string= type "test:fail") 'failed)
                       (t 'passed)))
         (failure (and (eq status 'failed)
                       (neotest-node--failure (alist-get 'error details) file))))
    (append (list :id (apply #'neotest-make-id file names)
                  :type kind
                  :name name
                  :status status
                  :file file
                  :line (alist-get 'line data)
                  :column (alist-get 'column data)
                  :duration (alist-get 'duration_ms details))
            failure)))

(defun neotest-node--parse-line (run line)
  "Parse one JSON event LINE from RUN's reporter into a result or nil.
Lines that are not events, such as syntax errors, go to the output."
  (unless (string-prefix-p "{" line)
    (neotest-append-output run (concat line "\n")))
  (when (string-prefix-p "{" line)
    (let* ((event (ignore-errors
                    (json-parse-string line :object-type 'alist
                                       :null-object nil :false-object nil)))
           (type (alist-get 'type event))
           (data (alist-get 'data event))
           (name (alist-get 'name data))
           (file (alist-get 'file data)))
      (pcase type
        ("test:start"
         (neotest-node--set-active run (or (alist-get 'nesting data) 0) name)
         nil)
        ((or "test:pass" "test:fail")
         (when (and file name (not (string-suffix-p name file)))
           (neotest-node--result run type data)))))))

(neotest-register-backend 'node
  :predicate #'neotest-node--buffer-p
  :test-file-p #'neotest-node-test-file-p
  :root #'neotest-node-root
  :query #'neotest-node--query
  :command #'neotest-node--command
  :parse-line #'neotest-node--parse-line)

(provide 'neotest-node)
;;; neotest-node.el ends here
