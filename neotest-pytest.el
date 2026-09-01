;;; neotest-pytest.el --- pytest backend for neotest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/emacs-neotest

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Runs pytest with the bundled plugin neotest_pytest.py loaded through
;; `-p', which writes one JSON event per test to stderr.  pytest's own
;; output stays on stdout for the output buffer.  Node ids
;; (`tests/test_x.py::TestA::test_b') already have the shape of neotest
;; ids, so mapping is direct.

;;; Code:

(require 'neotest)

(defgroup neotest-pytest nil
  "Pytest backend for neotest."
  :group 'neotest
  :prefix "neotest-pytest-")

(defcustom neotest-pytest-command '("pytest")
  "Program and leading arguments used to run pytest."
  :type '(repeat string)
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-pytest-extra-args nil
  "Arguments appended before the test selection."
  :type '(repeat string)
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-pytest-test-file-regexp "\\(?:\\`\\|/\\)\\(?:test_[^/]*\\|[^/]*_test\\)\\.py\\'"
  "Regexp matching pytest test files."
  :type 'regexp
  :package-version '(neotest . "0.1.0"))

(defconst neotest-pytest--plugin-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding neotest_pytest.py.")

(defconst neotest-pytest--query
  '(((class_definition name: (identifier) @namespace.name) @namespace.definition
     (:match "\\`Test" @namespace.name))
    ((function_definition name: (identifier) @test.name) @test.definition
     (:match "\\`test" @test.name)))
  "Query matching pytest test classes and functions.")

(defun neotest-pytest-root (file)
  "Return the directory of the nearest pytest configuration above FILE."
  (when-let* ((dir (locate-dominating-file
                    file (lambda (d)
                           (seq-some (lambda (name) (file-exists-p (expand-file-name name d)))
                                     '("pytest.ini" "pyproject.toml" "setup.cfg" "tox.ini"))))))
    (expand-file-name dir)))

(defun neotest-pytest-test-file-p (file)
  "Return non-nil when FILE looks like a pytest test file."
  (and (string-match-p neotest-pytest-test-file-regexp file)
       (not (string-match-p "/\\(?:\\.venv\\|site-packages\\)/" file))))

(defun neotest-pytest--buffer-p ()
  "Return non-nil when the current buffer is a Python test file."
  (and buffer-file-name
       (derived-mode-p 'python-ts-mode 'python-mode)
       (neotest-pytest-test-file-p buffer-file-name)))

(defun neotest-pytest--nodeid (id root)
  "Return the pytest node id for neotest ID relative to ROOT."
  (string-join (cons (file-relative-name (neotest-id-file id) root)
                     (neotest-id-names id))
               "::"))

(defun neotest-pytest--command (run)
  "Return the process spec for RUN."
  (let* ((root (plist-get run :root))
         (scope (plist-get run :scope))
         (position (plist-get run :position))
         (selection
          (pcase scope
            ((or 'test 'namespace) (list (neotest-pytest--nodeid (plist-get position :id) root)))
            ('file (list (file-relative-name (plist-get run :file) root)))
            ('project (mapcar (lambda (f) (file-relative-name f root)) (plist-get run :files)))
            ('results (mapcar (lambda (r) (plist-get r :runner-name)) (plist-get run :results))))))
    (list :command (append neotest-pytest-command
                           (list "-p" "neotest_pytest")
                           neotest-pytest-extra-args
                           selection)
          :directory root
          :env (list (concat "PYTHONPATH=" neotest-pytest--plugin-dir
                             (when-let* ((existing (getenv "PYTHONPATH")))
                               (concat path-separator existing))))
          :parse-stream 'stderr)))

(defun neotest-pytest--strip-params (name)
  "Return NAME without a trailing parametrize suffix."
  (replace-regexp-in-string "\\[.*\\]\\'" "" name))

(defun neotest-pytest--result (run event)
  "Return a result for a pytest EVENT in RUN."
  (let* ((rootdir (or (alist-get 'rootdir event) (plist-get run :directory)))
         (parts (split-string (alist-get 'nodeid event) "::"))
         (file (expand-file-name (car parts) rootdir))
         (names (cdr parts))
         (id-names (append (butlast names)
                           (list (neotest-pytest--strip-params (car (last names))))))
         (location (alist-get 'location event))
         (crash (alist-get 'crash event))
         (status (pcase (alist-get 'outcome event)
                   ("passed" 'passed)
                   ("failed" 'failed)
                   (_ 'skipped)))
         (crash-file (and crash (expand-file-name (alist-get 'path crash) rootdir))))
    (append (list :id (apply #'neotest-make-id file id-names)
                  :type 'test
                  :name (car (last names))
                  :runner-name (alist-get 'nodeid event)
                  :status status
                  :file file
                  :line (1+ (or (nth 1 location) 0))
                  :column 1
                  :duration (when-let* ((s (alist-get 'duration event))) (* 1000 s)))
            (when (eq status 'failed)
              (list :message (or (alist-get 'message crash) (alist-get 'message event) "failed")
                    :location (and crash (string= crash-file file)
                                   (cons (alist-get 'lineno crash) nil)))))))

(defun neotest-pytest--parse-line (run line)
  "Parse one plugin JSON LINE from RUN into a result or nil.
Other stderr lines go to the output buffer."
  (unless (string-prefix-p "{" line)
    (neotest-append-output run (concat line "\n")))
  (when (string-prefix-p "{" line)
    (when-let* ((event (ignore-errors
                         (json-parse-string line :object-type 'alist :array-type 'list
                                            :null-object nil :false-object nil))))
      (when (alist-get 'nodeid event)
        (neotest-pytest--result run event)))))

(neotest-register-backend 'pytest
  :predicate #'neotest-pytest--buffer-p
  :test-file-p #'neotest-pytest-test-file-p
  :root #'neotest-pytest-root
  :query (cons 'python neotest-pytest--query)
  :command #'neotest-pytest--command
  :parse-line #'neotest-pytest--parse-line)

(provide 'neotest-pytest)
;;; neotest-pytest.el ends here
