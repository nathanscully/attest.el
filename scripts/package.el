;;; package.el --- Stage a standalone attest package -*- lexical-binding: t; -*-

;;; Commentary:

;; Flattens the explicit source manifest and generates package metadata.

;;; Code:

(require 'loaddefs-gen)
(require 'package)

(defun attest-package--write-description (directory)
  "Write DIRECTORY\='s package description from the headers of attest.el.
`package-generate-description-file' owns the format, which still emits
`define-package' on Emacs 30 but marks the result `no-byte-compile', so
the obsolete call is never compiled."
  (let ((description
         (with-temp-buffer
           (insert-file-contents (expand-file-name "attest.el" directory))
           (package-buffer-info))))
    (setf (package-desc-summary description) "Extensible test runner")
    (package-generate-description-file
     description (expand-file-name "attest-pkg.el" directory))))

(let ((directory (expand-file-name "build/attest-0.1.0/"))
      (names (make-hash-table :test 'equal)))
  (make-directory directory t)
  (dolist (file command-line-args-left)
    (let ((name (file-name-nondirectory file)))
      (when (gethash name names) (error "Duplicate package member: %s" name))
      (puthash name t names)
      (copy-file file (expand-file-name name directory) t)))
  (copy-file "LICENSE" (expand-file-name "LICENSE" directory) t)
  (attest-package--write-description directory)
  (loaddefs-generate
   directory (expand-file-name "attest-autoloads.el" directory) nil
   "(add-to-list 'load-path (directory-file-name (file-name-directory (or load-file-name buffer-file-name))))\n"
   nil t)
  (setq command-line-args-left nil))

;;; package.el ends here
