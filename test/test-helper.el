;;; test-helper.el --- Shared setup for attest tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded before every test file.  Points treesit at the grammars named
;; by EMACS_TREE_SITTER_GRAMMARS so discovery tests can run in batch.

;;; Code:

(require 'ert)
(require 'treesit)

(when-let* ((dir (getenv "EMACS_TREE_SITTER_GRAMMARS")))
  (add-to-list 'treesit-extra-load-path dir))

(defconst attest-test-fixtures
  (expand-file-name "fixtures/" (file-name-directory
                                 (or load-file-name buffer-file-name)))
  "Directory holding recorded runner output and sample sources.")

(defun attest-test-fixture (name)
  "Return the absolute path of fixture NAME."
  (expand-file-name name attest-test-fixtures))

(defun attest-test-fixture-lines (name)
  "Return the lines of fixture NAME.
The placeholder __FIXTURES__/ in a recorded line stands for the
fixtures directory, so replayed events carry this checkout's paths."
  (with-temp-buffer
    (insert-file-contents (attest-test-fixture name))
    (split-string (string-replace "__FIXTURES__/" attest-test-fixtures
                                  (buffer-string))
                  "\n" t)))

(defmacro attest-test-with-run (var &rest body)
  "Bind VAR to a fresh node run plist and evaluate BODY."
  (declare (indent 1))
  `(let ((,var (list :backend 'node :scope 'file :state nil :result-ids nil
                     :root attest-test-fixtures)))
     ,@body))

(provide 'test-helper)
;;; test-helper.el ends here
