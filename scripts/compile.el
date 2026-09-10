;;; compile.el --- Byte-compile attest as a lint -*- lexical-binding: t; -*-

;;; Commentary:

;; Compiles every source file with warnings as errors and throws the
;; bytecode away.  Emacs loads attest from source, so the only value here
;; is the diagnostics; keeping the .elc files would invite a stale one to
;; shadow an edited source and report a false pass.

;;; Code:

(require 'bytecomp)

(defvar attest-compile--directory
  (file-name-as-directory (make-temp-file "attest-compile-" t))
  "Throwaway directory holding the bytecode this lint produces.")

(defun attest-compile--dest-file (file)
  "Return the discarded bytecode path for FILE."
  (expand-file-name (concat (file-name-nondirectory file) "c")
                    attest-compile--directory))

(let ((byte-compile-dest-file-function #'attest-compile--dest-file)
      (byte-compile-error-on-warn t)
      (failed nil))
  (unwind-protect
      (dolist (file command-line-args-left)
        (unless (byte-compile-file file)
          (setq failed t)))
    (delete-directory attest-compile--directory t))
  (setq command-line-args-left nil)
  (when failed (kill-emacs 1))
  (message "compile: clean"))

;;; compile.el ends here
