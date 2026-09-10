;;; package.el --- Stage a standalone attest package -*- lexical-binding: t; -*-

;;; Commentary:

;; Flattens the explicit source manifest and generates package metadata.
;; The version comes from lisp/attest.el's own header, so nothing outside
;; the sources needs to know it; the staged directory name is printed on
;; stdout for the caller to archive.

;;; Code:

(require 'loaddefs-gen)
(require 'package)
(require 'lisp-mnt)

(defconst attest-package--summary "Extensible test runner"
  "One-line summary recorded in the generated package description.")

(defun attest-package--version (file)
  "Return the package version declared in FILE\='s headers."
  (with-temp-buffer
    (insert-file-contents file)
    (or (lm-header "version")
        (error "No Version header in %s" file))))

(defun attest-package--write-description (directory)
  "Write DIRECTORY\='s package description from the headers of attest.el.
`package-generate-description-file' owns the format, which still emits
`define-package' on Emacs 30 but marks the result `no-byte-compile', so
the obsolete call is never compiled."
  (let ((description
         (with-temp-buffer
           (insert-file-contents (expand-file-name "attest.el" directory))
           (package-buffer-info))))
    (setf (package-desc-summary description) attest-package--summary)
    (package-generate-description-file
     description (expand-file-name "attest-pkg.el" directory))))

(let* ((sources command-line-args-left)
       (main (or (seq-find (lambda (f)
                             (equal (file-name-nondirectory f) "attest.el"))
                           sources)
                 (error "Source manifest does not include attest.el")))
       (name (concat "attest-" (attest-package--version main)))
       (directory (expand-file-name (concat "build/" name "/")))
       (names (make-hash-table :test 'equal)))
  (make-directory directory t)
  (dolist (file sources)
    (let ((member (file-name-nondirectory file)))
      (when (gethash member names) (error "Duplicate package member: %s" member))
      (puthash member t names)
      (copy-file file (expand-file-name member directory) t)))
  (copy-file "LICENSE" (expand-file-name "LICENSE" directory) t)
  (attest-package--write-description directory)
  (loaddefs-generate
   directory (expand-file-name "attest-autoloads.el" directory) nil
   "(add-to-list 'load-path (directory-file-name (file-name-directory (or load-file-name buffer-file-name))))\n"
   nil t)
  (setq command-line-args-left nil)
  (princ (concat name "\n")))

;;; package.el ends here
