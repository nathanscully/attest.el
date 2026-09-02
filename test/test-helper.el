;;; test-helper.el --- Shared setup for neotest tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded before every test file.  Points treesit at the grammars named
;; by EMACS_TREE_SITTER_GRAMMARS so discovery tests can run in batch.

;;; Code:

(require 'ert)
(require 'treesit)

(when-let* ((dir (getenv "EMACS_TREE_SITTER_GRAMMARS")))
  (add-to-list 'treesit-extra-load-path dir))

(defconst neotest-test-fixtures
  (expand-file-name "fixtures/" (file-name-directory
                                 (or load-file-name buffer-file-name)))
  "Directory holding recorded runner output and sample sources.")

(defun neotest-test-fixture (name)
  "Return the absolute path of fixture NAME."
  (expand-file-name name neotest-test-fixtures))

(defun neotest-test-fixture-lines (name)
  "Return the lines of fixture NAME.
The placeholder __FIXTURES__/ in a recorded line stands for the
fixtures directory, so replayed events carry this checkout's paths."
  (with-temp-buffer
    (insert-file-contents (neotest-test-fixture name))
    (split-string (string-replace "__FIXTURES__/" neotest-test-fixtures
                                  (buffer-string))
                  "\n" t)))

(defmacro neotest-test-with-run (var &rest body)
  "Bind VAR to a fresh node run plist and evaluate BODY."
  (declare (indent 1))
  `(let ((,var (list :backend 'node :scope 'file :state nil :result-ids nil
                     :root neotest-test-fixtures)))
     ,@body))

(provide 'test-helper)
;;; test-helper.el ends here
