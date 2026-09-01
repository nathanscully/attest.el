;;; run-checkdoc.el --- Batch checkdoc runner -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs checkdoc over the files named on the command line and exits
;; non-zero when any produced a diagnostic.

;;; Code:

(require 'checkdoc)

(let ((checkdoc-diagnostic-buffer "*neotest-checkdoc*"))
  (dolist (file command-line-args-left)
    (checkdoc-file file))
  (let ((text (mapconcat (lambda (name)
                           (if-let* ((buffer (get-buffer name)))
                               (with-current-buffer buffer (buffer-string))
                             ""))
                         (list checkdoc-diagnostic-buffer "*Warnings*")
                         "\n")))
    (if (string-match-p "^[^*\n].*:[0-9]+: " text)
        (progn (princ text) (kill-emacs 1))
      (princ "checkdoc: clean\n"))))

;;; run-checkdoc.el ends here
