;;; attest-node.el --- node --test backend for attest -*- lexical-binding: t; -*-

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
(require 'attest-javascript)

(defcustom attest-node-executable "node"
  "Node program that runs `node --test'."
  :type 'string
  :group 'attest-node
  :package-version '(attest . "0.1.0"))

(defcustom attest-node-extra-args nil
  "Arguments inserted after `--test'."
  :type '(repeat string)
  :group 'attest-node
  :package-version '(attest . "0.1.0"))

(defconst attest-node--reporter
  (expand-file-name "attest-node-reporter.mjs"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Absolute path of the bundled JSON-lines reporter.")

(defun attest-node--project-p ()
  "Return non-nil when the current buffer sits in a node package.
Any file in the package qualifies, so a project run can start from
source rather than only from a test file.  Vitest registers later and is
asked first, so a vitest package is claimed there."
  (and buffer-file-name
       (apply #'derived-mode-p attest-node--modes)
       (attest-node-root buffer-file-name)
       t))

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
          :env (attest-node-env)
          :parse-stream 'stderr)))

(attest-register-backend 'node
                         :test-failure-exit-codes '(1)
                         :predicate #'attest-node--buffer-p
                         :project-p #'attest-node--project-p
                         :test-file-p #'attest-node-test-file-p
                         :root #'attest-node-root
                         :query #'attest-node--query
                         :command #'attest-node--command
                         :parse-line #'attest-node-parse-scoped-line)

(provide 'attest-node)
;;; attest-node.el ends here
