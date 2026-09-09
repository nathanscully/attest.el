;;; attest-vitest.el --- vitest backend for attest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/attest.el

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Runs vitest with the bundled attest-vitest-reporter.mjs alongside
;; the default reporter.  The custom reporter writes one `attest:test'
;; JSON line per test case to stderr, the same shape the node reporter
;; emits, so parsing is `attest-node-parse-scoped-line'; vitest's own
;; output stays on stdout.
;;
;; Discovery reuses the node backend's query: vitest and node:test
;; declare tests the same way.  This file requires attest-node so it
;; registers after it, and both its predicate and its :test-file-p only
;; claim files whose package has a vitest binary, so plain node:test
;; projects still go to the node backend.

;;; Code:

(require 'attest)
(require 'attest-javascript)

(defgroup attest-vitest nil
  "Vitest backend for attest."
  :group 'attest
  :prefix "attest-vitest-")

(defcustom attest-vitest-command nil
  "Program and leading arguments used to run vitest.
When nil, the nearest node_modules/.bin/vitest above the file is used."
  :type '(choice
          (const :tag "Nearest node_modules/.bin/vitest" nil)
          (repeat :tag "Program and arguments" string))
  :package-version '(attest . "0.1.0"))

(defcustom attest-vitest-extra-args nil
  "Arguments inserted after `vitest run'."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defconst attest-vitest--reporter
  (expand-file-name "attest-vitest-reporter.mjs"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Absolute path of the bundled reporter.")

(defun attest-vitest--bin-dir (file)
  "Return the nearest directory above FILE holding node_modules/.bin/vitest."
  (locate-dominating-file
   file (lambda (dir)
          (file-executable-p (expand-file-name "node_modules/.bin/vitest" dir)))))

(defun attest-vitest-root (file)
  "Return the nearest package directory above FILE, preferring one with vitest."
  (when-let* ((dir (or (locate-dominating-file file "package.json")
                       (attest-vitest--bin-dir file))))
    (expand-file-name dir)))

(defun attest-vitest-test-file-p (file)
  "Return non-nil when FILE is a test file in a package that has vitest.
Node and vitest declare tests identically, so the name alone cannot
tell them apart; only the presence of a vitest binary above FILE can.
Without this, file dispatch would hand every node:test file to vitest,
because vitest registers after node and `attest-backend-for-file'
takes the first backend that claims the file."
  (and (attest-node-test-file-p file)
       (attest-vitest--bin-dir file)
       t))

(defun attest-vitest--available-p (file)
  "Return non-nil when a vitest binary sits above FILE."
  (and (attest-vitest--bin-dir file) t))

(defun attest-vitest--project-p ()
  "Return non-nil when the current buffer sits in a vitest package."
  (and buffer-file-name
       (apply #'derived-mode-p attest-node--modes)
       (attest-vitest--available-p buffer-file-name)
       t))

(defun attest-vitest--buffer-p ()
  "Return non-nil for a JavaScript or TypeScript test buffer in a vitest package."
  (and (attest-node--buffer-p)
       (attest-vitest-test-file-p buffer-file-name)))

(defun attest-vitest--program (root)
  "Return the vitest command list for a run rooted at ROOT."
  (or attest-vitest-command
      (when-let* ((dir (attest-vitest--bin-dir root)))
        (list (expand-file-name "node_modules/.bin/vitest" dir)))
      (user-error "Attest: no vitest binary found above %s" root)))

(defun attest-vitest--name-pattern (targets)
  "Return a -t regexp selecting TARGETS.
A test target matches exactly; a namespace target also matches every
test below it."
  (let ((pieces (mapcar (lambda (target)
                          (concat (attest-node-regexp-quote
                                   (string-join (attest-id-names (plist-get target :id)) " "))
                                  (if (eq (plist-get target :type) 'namespace) "( |$)" "$")))
                        targets)))
    (if (cdr pieces)
        (format "^(?:%s)" (string-join pieces "|"))
      (concat "^" (car pieces)))))

(defun attest-vitest--command (run)
  "Return the process spec for RUN."
  (let* ((root (plist-get run :root))
         (scope (plist-get run :scope))
         (files (and (not (eq scope 'project)) (attest-run-files run)))
         (pattern (and (eq scope 'targets)
                       (attest-vitest--name-pattern (plist-get run :targets)))))
    (list :command (append (attest-vitest--program root)
                           (list "run" "--reporter=default"
                                 (concat "--reporter=" attest-vitest--reporter)
                                 "--includeTaskLocation")
                           attest-vitest-extra-args
                           (and pattern (list "-t" pattern))
                           (mapcar (lambda (f) (file-relative-name f root)) files))
          :directory root
          :env (attest-node-env)
          :parse-stream 'stderr)))

(defconst attest-vitest--only-regexp
  "\\_<\\(?:describe\\|suite\\|test\\|it\\)\\.only\\_>"
  "Regexp matching a `.only\=' declaration in a JavaScript or TypeScript file.")

(defun attest-vitest--only-file-p (file)
  "Return non-nil when FILE declares a test or suite with `.only\='."
  (let ((buffer (find-buffer-visiting file)))
    (cond
     (buffer (with-current-buffer buffer
               (attest-vitest--only-buffer-p file)))
     ((file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (attest-vitest--only-buffer-p file))))))

(defun attest-vitest--only-buffer-p (file)
  "Return non-nil for an exclusive declaration in the buffer visiting FILE."
  (save-restriction
    (widen)
    (let ((language (car (attest-node--query file))))
      (attest--ensure-language language)
      (treesit-query-capture
       (treesit-parser-root-node (treesit-parser-create language))
       '(((call_expression
          function: (member_expression
                     object: (identifier) @fn
                     property: (property_identifier) @mod))
         (:match "\\`\\(?:test\\|it\\|describe\\|suite\\)\\'" @fn)
         (:equal @mod "only")))))))

(defun attest-vitest--file-has-only-p (run file)
  "Return non-nil when FILE declares `.only\=', caching the answer in RUN.
Asked per file rather than per run: `.only\=' in one file excludes tests
only in that file, and vitest still reports genuine `test.skip\=' in every
other file of the run."
  (let ((table (or (plist-get run :vitest-only)
                   (let ((new (make-hash-table :test 'equal)))
                     (plist-put run :vitest-only new)
                     new)))
        (key (and file (expand-file-name file))))
    (when key
      (let ((cached (gethash key table 'missing)))
        (if (eq cached 'missing)
            (puthash key (attest-vitest--only-file-p key) table)
          cached)))))

(defun attest-vitest-parse-line (run line)
  "Parse one reporter LINE from RUN into a result or nil.
Drops results outside RUN\='s targets, and drops skipped results from a
file that declares `.only\='.  vitest rewrites the mode of every
test `.only\=' excludes to `skip\=' before any reporter sees it, so an
excluded test is indistinguishable from one the author wrote as
`test.skip\='.  Recording those would overwrite the cached status of
tests that did not run; leaving them out keeps the last real status."
  (when-let* ((result (attest-node-parse-scoped-line run line)))
    (unless (and (memq (attest-result-status result) '(skipped todo))
                 (attest-vitest--file-has-only-p run (attest-result-file result)))
      result)))

(attest-register-backend 'vitest
  :test-failure-exit-codes '(1)
  :predicate #'attest-vitest--buffer-p
  :project-p #'attest-vitest--project-p
  :test-file-p #'attest-vitest-test-file-p
  :root #'attest-vitest-root
  :query #'attest-node--query
  :command #'attest-vitest--command
  :parse-line #'attest-vitest-parse-line)

(provide 'attest-vitest)
;;; attest-vitest.el ends here
