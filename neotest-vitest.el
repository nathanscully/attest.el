;;; neotest-vitest.el --- vitest backend for neotest -*- lexical-binding: t; -*-

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Runs vitest with the bundled neotest-vitest-reporter.mjs alongside
;; the default reporter.  The custom reporter writes one JSON line per
;; test case to stderr; vitest's own output stays on stdout.
;;
;; Discovery reuses the node backend's query: vitest and node:test
;; declare tests the same way.  This file requires neotest-node so it
;; registers after it, and its predicate only claims buffers whose
;; package has a vitest binary, so plain node:test projects still go to
;; the node backend.

;;; Code:

(require 'neotest)
(require 'neotest-node)
(require 'json)

(defgroup neotest-vitest nil
  "Vitest backend for neotest."
  :group 'neotest
  :prefix "neotest-vitest-")

(defcustom neotest-vitest-command nil
  "Program and leading arguments used to run vitest.
When nil, the nearest node_modules/.bin/vitest above the file is used."
  :type '(choice (const nil) (repeat string)))

(defcustom neotest-vitest-extra-args nil
  "Arguments inserted after `vitest run'."
  :type '(repeat string))

(defconst neotest-vitest--reporter
  (expand-file-name "neotest-vitest-reporter.mjs"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Absolute path of the bundled reporter.")

(defun neotest-vitest--bin-dir (file)
  "Return the nearest directory above FILE holding node_modules/.bin/vitest."
  (locate-dominating-file
   file (lambda (dir)
          (file-executable-p (expand-file-name "node_modules/.bin/vitest" dir)))))

(defun neotest-vitest-root (file)
  "Return the nearest package directory above FILE, preferring one with vitest."
  (when-let* ((dir (or (locate-dominating-file file "package.json")
                       (neotest-vitest--bin-dir file))))
    (expand-file-name dir)))

(defun neotest-vitest--buffer-p ()
  "Return non-nil for a JavaScript or TypeScript test buffer in a vitest package."
  (and (neotest-node--buffer-p)
       (neotest-vitest--bin-dir buffer-file-name)))

(defun neotest-vitest--program (root)
  "Return the vitest command list for a run rooted at ROOT."
  (or neotest-vitest-command
      (when-let* ((dir (neotest-vitest--bin-dir root)))
        (list (expand-file-name "node_modules/.bin/vitest" dir)))
      (user-error "Neotest: no vitest binary found above %s" root)))

(defun neotest-vitest--name-pattern (results-or-position)
  "Return a -t regexp selecting RESULTS-OR-POSITION.
A single position plist selects that test or namespace; a list of
result plists selects each of them exactly."
  (if (keywordp (car results-or-position))
      (let ((name (neotest-node-regexp-quote
                   (string-join (neotest-id-names (plist-get results-or-position :id)) " "))))
        (if (eq (plist-get results-or-position :type) 'test)
            (format "^%s$" name)
          (format "^%s( |$)" name)))
    (format "^(%s)$"
            (mapconcat (lambda (r)
                         (neotest-node-regexp-quote
                          (string-join (neotest-id-names (plist-get r :id)) " ")))
                       results-or-position "|"))))

(defun neotest-vitest--command (run)
  "Return the process spec for RUN."
  (let* ((root (plist-get run :root))
         (scope (plist-get run :scope))
         (files (pcase scope
                  ('project nil)
                  ('results (delete-dups (mapcar (lambda (r) (plist-get r :file))
                                                 (plist-get run :results))))
                  (_ (list (plist-get run :file)))))
         (pattern (pcase scope
                    ((or 'test 'namespace) (neotest-vitest--name-pattern (plist-get run :position)))
                    ('results (neotest-vitest--name-pattern (plist-get run :results))))))
    (list :command (append (neotest-vitest--program root)
                           (list "run" "--reporter=default"
                                 (concat "--reporter=" neotest-vitest--reporter)
                                 "--includeTaskLocation")
                           neotest-vitest-extra-args
                           (and pattern (list "-t" pattern))
                           (mapcar (lambda (f) (file-relative-name f root)) files))
          :directory root
          :env neotest-node-env
          :parse-stream 'stderr)))

(defun neotest-vitest--result (event)
  "Return a result for a reporter EVENT."
  (let* ((names (append (alist-get 'names event) nil))
         (file (alist-get 'file event))
         (location (alist-get 'location event))
         (state (alist-get 'state event))
         (status (pcase state
                   ("passed" 'passed)
                   ("failed" 'failed)
                   (_ (if (equal (alist-get 'mode event) "todo") 'todo 'skipped))))
         (error (car (append (alist-get 'errors event) nil))))
    (append (list :id (apply #'neotest-make-id file names)
                  :type 'test
                  :name (car (last names))
                  :status status
                  :file file
                  :line (alist-get 'line location)
                  :column (alist-get 'column location)
                  :duration (alist-get 'duration event))
            (when (eq status 'failed)
              (list :message (or (alist-get 'message error) "failed")
                    :stack (alist-get 'stack error)
                    :location (neotest-node--frame-in-file
                               (or (alist-get 'stack error) "") file))))))

(defun neotest-vitest--wanted-p (run result)
  "Return non-nil when RESULT was selected by RUN's scope.
vitest reports tests excluded by -t as skipped; those must not
overwrite the cached status of tests that did not run."
  (let ((id (plist-get result :id)))
    (pcase (plist-get run :scope)
      ('test (equal id (plist-get (plist-get run :position) :id)))
      ('namespace (string-prefix-p (concat (plist-get (plist-get run :position) :id)
                                           neotest-id-separator)
                                   id))
      ('results (seq-some (lambda (r) (equal (plist-get r :id) id))
                          (plist-get run :results)))
      (_ t))))

(defun neotest-vitest--parse-line (run line)
  "Parse one reporter LINE from RUN, echoing anything else to the output."
  (if (string-prefix-p "{" line)
      (when-let* ((event (ignore-errors
                           (json-parse-string line :object-type 'alist
                                              :null-object nil :false-object nil))))
        (when (equal (alist-get 'type event) "neotest:test")
          (let ((result (neotest-vitest--result event)))
            (and (neotest-vitest--wanted-p run result) result))))
    (neotest-append-output run (concat line "\n"))
    nil))

(neotest-register-backend 'vitest
  :predicate #'neotest-vitest--buffer-p
  :test-file-p #'neotest-node-test-file-p
  :root #'neotest-vitest-root
  :query #'neotest-node--query
  :command #'neotest-vitest--command
  :parse-line #'neotest-vitest--parse-line)

(provide 'neotest-vitest)
;;; neotest-vitest.el ends here
