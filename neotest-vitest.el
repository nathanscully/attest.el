;;; neotest-vitest.el --- vitest backend for neotest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/emacs-neotest

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Runs vitest with the bundled neotest-vitest-reporter.mjs alongside
;; the default reporter.  The custom reporter writes one `neotest:test'
;; JSON line per test case to stderr, the same shape the node reporter
;; emits, so parsing is `neotest-node--parse-line'; vitest's own output
;; stays on stdout.
;;
;; Discovery reuses the node backend's query: vitest and node:test
;; declare tests the same way.  This file requires neotest-node so it
;; registers after it, and its predicate only claims buffers whose
;; package has a vitest binary, so plain node:test projects still go to
;; the node backend.

;;; Code:

(require 'neotest)
(require 'neotest-node)

(defgroup neotest-vitest nil
  "Vitest backend for neotest."
  :group 'neotest
  :prefix "neotest-vitest-")

(defcustom neotest-vitest-command nil
  "Program and leading arguments used to run vitest.
When nil, the nearest node_modules/.bin/vitest above the file is used."
  :type '(choice
          (const :tag "Nearest node_modules/.bin/vitest" nil)
          (repeat :tag "Program and arguments" string))
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-vitest-extra-args nil
  "Arguments inserted after `vitest run'."
  :type '(repeat string)
  :package-version '(neotest . "0.1.0"))

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

(defun neotest-vitest--name-pattern (targets)
  "Return a -t regexp selecting TARGETS.
A test target matches exactly; a namespace target also matches every
test below it."
  (let ((pieces (mapcar (lambda (target)
                          (concat (neotest-node-regexp-quote
                                   (string-join (neotest-id-names (plist-get target :id)) " "))
                                  (if (eq (plist-get target :type) 'namespace) "( |$)" "$")))
                        targets)))
    (if (cdr pieces)
        (format "^(?:%s)" (string-join pieces "|"))
      (concat "^" (car pieces)))))

(defun neotest-vitest--command (run)
  "Return the process spec for RUN."
  (let* ((root (plist-get run :root))
         (scope (plist-get run :scope))
         (files (and (not (eq scope 'project)) (neotest-run-files run)))
         (pattern (and (eq scope 'targets)
                       (neotest-vitest--name-pattern (plist-get run :targets)))))
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

(defun neotest-vitest--wanted-p (run result)
  "Return non-nil when RESULT is one of RUN's targets, or RUN has none.
vitest reports tests excluded by -t as skipped; those must not
overwrite the cached status of tests that did not run."
  (or (not (eq (plist-get run :scope) 'targets))
      (let ((id (plist-get result :id)))
        (seq-some (lambda (target)
                    (let ((target-id (plist-get target :id)))
                      (if (eq (plist-get target :type) 'namespace)
                          (string-prefix-p (concat target-id neotest-id-separator) id)
                        (equal target-id id))))
                  (plist-get run :targets)))))

(defun neotest-vitest--parse-line (run line)
  "Parse one reporter LINE from RUN, dropping results outside its targets."
  (when-let* ((result (neotest-node--parse-line run line)))
    (and (neotest-vitest--wanted-p run result) result)))

(neotest-register-backend 'vitest
  :predicate #'neotest-vitest--buffer-p
  :test-file-p #'neotest-node-test-file-p
  :root #'neotest-vitest-root
  :query #'neotest-node--query
  :command #'neotest-vitest--command
  :parse-line #'neotest-vitest--parse-line)

(provide 'neotest-vitest)
;;; neotest-vitest.el ends here
