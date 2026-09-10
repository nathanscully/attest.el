;;; attest-pytest.el --- pytest backend for attest -*- lexical-binding: t; -*-

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

;; Runs pytest with the bundled plugin attest_pytest.py loaded through
;; `-p', which writes one JSON event per test to stderr.  pytest's own
;; output stays on stdout for the output buffer.  Node ids
;; (`tests/test_x.py::TestA::test_b') already have the shape of attest
;; ids, so mapping is direct.

;;; Code:

(require 'attest-loadpath)
(require 'attest)

(defgroup attest-pytest nil
  "Pytest backend for attest."
  :group 'attest
  :prefix "attest-pytest-")

(defcustom attest-pytest-command '("pytest")
  "Program and leading arguments used to run pytest."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defcustom attest-pytest-extra-args nil
  "Arguments appended before the test selection."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defcustom attest-pytest-test-file-regexp "\\(?:\\`\\|/\\)\\(?:test_[^/]*\\|[^/]*_test\\)\\.py\\'"
  "Regexp matching pytest test files."
  :type 'regexp
  :package-version '(attest . "0.1.0"))

(defconst attest-pytest--plugin-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding attest_pytest.py.")

(defconst attest-pytest--query
  '(((class_definition name: (identifier) @namespace.name) @namespace.definition
     (:match "\\`Test" @namespace.name))
    ((module (function_definition name: (identifier) @test.name) @test.definition)
     (:match "\\`test" @test.name))
    ((module (decorated_definition
              (function_definition name: (identifier) @test.name) @test.definition))
     (:match "\\`test" @test.name))
    ((class_definition
      name: (identifier) @class
      body: (block (function_definition name: (identifier) @test.name) @test.definition))
     (:match "\\`Test" @class)
     (:match "\\`test" @test.name))
    ((class_definition
      name: (identifier) @class
      body: (block (decorated_definition
                    (function_definition name: (identifier) @test.name) @test.definition)))
     (:match "\\`Test" @class)
     (:match "\\`test" @test.name)))
  "Query matching pytest test classes and the functions pytest collects.
A test function is either at module level or directly inside a class
whose name starts with Test, so helpers nested in other functions or in
plain classes are not tests.")

(defun attest-pytest-root (file)
  "Return the directory of the nearest pytest configuration above FILE."
  (when-let* ((dir (locate-dominating-file
                    file (lambda (d)
                           (seq-some (lambda (name) (file-exists-p (expand-file-name name d)))
                                     '("pytest.ini" "pyproject.toml" "setup.cfg" "tox.ini"))))))
    (expand-file-name dir)))

(defun attest-pytest-test-file-p (file)
  "Return non-nil when FILE looks like a pytest test file."
  (and (string-match-p attest-pytest-test-file-regexp file)
       (not (string-match-p "/\\(?:\\.venv\\|site-packages\\)/" file))))

(defun attest-pytest--buffer-p ()
  "Return non-nil when the current buffer is a Python test file."
  (and buffer-file-name
       (derived-mode-p 'python-ts-mode 'python-mode)
       (attest-pytest-test-file-p buffer-file-name)))

(defun attest-pytest--project-p ()
  "Return non-nil when the current buffer sits in a Python project.
Any Python file qualifies, so a project run can start from source
rather than only from a test file."
  (and buffer-file-name
       (derived-mode-p 'python-ts-mode 'python-mode)
       (attest-pytest-root buffer-file-name)
       t))

(defun attest-pytest--nodeid (id root)
  "Return the pytest node id for attest ID relative to ROOT."
  (string-join (cons (file-relative-name (attest-id-file id) root)
                     (attest-id-names id))
               "::"))

(defun attest-pytest--command (run)
  "Return the process spec for RUN."
  (let* ((root (plist-get run :root))
         (selection
          (pcase (plist-get run :scope)
            ('targets (mapcar (lambda (target)
                                (or (plist-get target :runner-name)
                                    (attest-pytest--nodeid (plist-get target :id) root)))
                              (plist-get run :targets)))
            (_ (mapcar (lambda (f) (file-relative-name f root)) (attest-run-files run))))))
    (list :command (append attest-pytest-command
                           (list "-p" "attest_pytest")
                           attest-pytest-extra-args
                           selection)
          :directory root
          :env (list (concat "PYTHONPATH=" attest-pytest--plugin-dir
                             (when-let* ((existing (getenv "PYTHONPATH")))
                               (concat path-separator existing))))
          :parse-stream 'stderr)))

(defun attest-pytest--strip-params (name)
  "Return NAME without a trailing parametrize suffix."
  (replace-regexp-in-string "\\[.*\\]\\'" "" name))

(defun attest-pytest--result (run event)
  "Return a result for a pytest EVENT in RUN."
  (let* ((rootdir (or (alist-get 'rootdir event) (plist-get run :directory)))
         (nodeid (alist-get 'nodeid event))
         (parameter-start (string-match "\\[" nodeid))
         (parts (split-string (if parameter-start (substring nodeid 0 parameter-start) nodeid) "::"))
         (file (expand-file-name (car parts) rootdir))
         (names (cdr parts))
         (case-names (append (butlast names)
                             (list (concat (car (last names))
                                           (and parameter-start (substring nodeid parameter-start))))))
         (location (alist-get 'location event))
         (crash (alist-get 'crash event))
         (status (pcase (alist-get 'outcome event)
                   ("passed" 'passed)
                   ("failed" 'failed)
                   (_ 'skipped)))
         (crash-file (and crash (expand-file-name (alist-get 'path crash) rootdir))))
    (append (list :id (apply #'attest-make-id file case-names)
                  :definition-id (apply #'attest-make-id file names)
                  :runner-name nodeid
                  :phase (alist-get 'when event)
                  :type 'test
                  :name (car (last case-names))
                  :status status
                  :file file
                  :line (1+ (or (nth 1 location) 0))
                  :column 1
                  :duration (when-let* ((s (alist-get 'duration event))) (* 1000 s)))
            (when (eq status 'failed)
              (list :message (or (alist-get 'message crash) (alist-get 'message event) "failed")
                    :location (and crash (string= crash-file file)
                                   (cons (alist-get 'lineno crash) nil)))))))

(defun attest-pytest--parse-line (run line)
  "Parse one plugin JSON LINE from RUN into a result or nil.
Other stderr lines go to the output buffer."
  (when-let* ((event (attest-parse-json-line run line 'list)))
    (when (alist-get 'nodeid event)
      (attest-pytest--result run event))))

(attest-register-backend 'pytest
                         :test-failure-exit-codes '(1)
                         :predicate #'attest-pytest--buffer-p
                         :project-p #'attest-pytest--project-p
                         :test-file-p #'attest-pytest-test-file-p
                         :root #'attest-pytest-root
                         :query (cons 'python attest-pytest--query)
                         :command #'attest-pytest--command
                         :parse-line #'attest-pytest--parse-line)

(provide 'attest-pytest)
;;; attest-pytest.el ends here
