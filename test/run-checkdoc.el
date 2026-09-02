;;; run-checkdoc.el --- Batch checkdoc runner -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs checkdoc over the files named on the command line and exits
;; non-zero when any produced a diagnostic.  The experimental verb
;; check is off: it flags nouns such as "tests", and its default
;; differs between Emacs versions.

;;; Code:

(require 'checkdoc)

(let ((checkdoc-diagnostic-buffer "*neotest-checkdoc*")
      (checkdoc-verb-check-experimental-flag nil))
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
