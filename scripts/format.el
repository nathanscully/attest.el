;;; format.el --- Indent Elisp the way Emacs does -*- lexical-binding: t; -*-

;;; Commentary:

;; treefmt ships no Elisp formatter, so this applies the indentation Emacs
;; itself would, in place, for the files named on the command line.  Only
;; leading whitespace changes; nothing is reflowed or reordered.

;;; Code:

(defun attest-format--file (file)
  "Reindent FILE in place, returning non-nil when it changed."
  (with-temp-buffer
    (let ((indent-tabs-mode nil)
          (inhibit-message t))
      (insert-file-contents file)
      (emacs-lisp-mode)
      (let ((before (buffer-string)))
        (indent-region (point-min) (point-max))
        (unless (string= before (buffer-string))
          (write-region (point-min) (point-max) file nil 'silent)
          t)))))

(dolist (file command-line-args-left)
  (attest-format--file file))
(setq command-line-args-left nil)

;;; format.el ends here
