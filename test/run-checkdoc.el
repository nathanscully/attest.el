;;; run-checkdoc.el --- Batch checkdoc runner -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs checkdoc over the files named on the command line and exits
;; non-zero when any produced a diagnostic.

;;; Code:

(require 'checkdoc)

(let ((checkdoc-diagnostic-buffer "*neotest-checkdoc*"))
  (dolist (file command-line-args-left)
    (checkdoc-file file))
  (with-current-buffer (get-buffer-create checkdoc-diagnostic-buffer)
    (goto-char (point-min))
    (if (re-search-forward "^[^*\n].*:[0-9]+: " nil t)
        (progn (princ (buffer-string)) (kill-emacs 1))
      (princ "checkdoc: clean\n"))))

;;; run-checkdoc.el ends here
