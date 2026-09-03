;;; attest-flymake.el --- Show test failures through flymake -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/attest.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A flymake backend that reports the latest failed tests as :error
;; diagnostics at the failing assertion, so they show inline, in
;; `flymake-show-buffer-diagnostics' and in
;; `flymake-show-project-diagnostics'.  Failures in files without a
;; buffer go to `flymake-list-only-diagnostics', which the project
;; listing also reads.
;;
;; Enable with `attest-flymake-mode' in test buffers, or globally with
;; `global-attest-flymake-mode'.

;;; Code:

(require 'flymake)
(require 'attest)

(defvar attest-flymake-mode)

(defun attest-flymake--region (result)
  "Return the (BEG . END) buffer region RESULT should highlight."
  (let* ((location (plist-get result :location))
         (line (or (car location) (plist-get result :line) 1))
         (column (and location (cdr location))))
    (or (flymake-diag-region (current-buffer) line column)
        (save-excursion
          (goto-char (point-min))
          (forward-line (1- line))
          (cons (line-beginning-position) (line-end-position))))))

(defun attest-flymake--message (result)
  "Return the diagnostic text for RESULT."
  (format "%s: %s"
          (string-join (attest-id-names (plist-get result :id)) " > ")
          (string-trim (or (plist-get result :message) "failed"))))

(defun attest-flymake--failures (file)
  "Return the failed test results recorded for FILE."
  (seq-filter (lambda (r) (and (eq (plist-get r :status) 'failed)
                               (eq (plist-get r :type) 'test)))
              (attest-results-for-file file)))

(defun attest-flymake--buffer-diagnostics ()
  "Return flymake diagnostics for the current buffer's failed tests."
  (when buffer-file-name
    (mapcar (lambda (result)
              (let ((region (attest-flymake--region result)))
                (flymake-make-diagnostic (current-buffer) (car region) (cdr region)
                                         :error
                                         (attest-flymake--message result)
                                         result)))
            (attest-flymake--failures buffer-file-name))))

(defvar attest-flymake--clearing nil
  "Non-nil while the backend must report no diagnostics.
Bound when the mode turns off, so flymake drops this backend's
diagnostics before the hook is removed; Emacs 30 keeps the
diagnostics of a backend that merely stops running.")

(defun attest-flymake-backend (report-fn &rest _args)
  "Report the current buffer's failed tests to REPORT-FN."
  (funcall report-fn (unless attest-flymake--clearing
                       (attest-flymake--buffer-diagnostics))))

(defun attest-flymake--list-only-diagnostic (result)
  "Return a file-locus diagnostic for RESULT, for unvisited files."
  (let ((location (plist-get result :location)))
    (flymake-make-diagnostic (plist-get result :file)
                             (cons (or (car location) (plist-get result :line) 1)
                                   (cdr location))
                             nil
                             :error
                             (attest-flymake--message result)
                             result)))

(defun attest-flymake--refresh (run)
  "Republish diagnostics for every file touched by RUN."
  (let ((files (delete-dups (mapcar (lambda (r) (plist-get r :file))
                                    (attest-run-results run)))))
    (dolist (file files)
      (setf (alist-get file flymake-list-only-diagnostics nil 'remove #'string=) nil)
      (if-let* ((buffer (find-buffer-visiting file)))
          (with-current-buffer buffer
            (when (and attest-flymake-mode flymake-mode)
              (flymake-start nil t)))
        (when-let* ((diags (mapcar #'attest-flymake--list-only-diagnostic
                                   (attest-flymake--failures file))))
          (push (cons file diags) flymake-list-only-diagnostics))))))

;;;###autoload
(define-minor-mode attest-flymake-mode
  "Show attest failures as flymake diagnostics in this buffer."
  :lighter nil
  (if attest-flymake-mode
      (progn
        (add-hook 'flymake-diagnostic-functions #'attest-flymake-backend nil t)
        (add-hook 'attest-run-finished-functions #'attest-flymake--refresh)
        (when flymake-mode (flymake-start nil t)))
    (let ((attest-flymake--clearing t))
      (when flymake-mode (flymake-start nil t)))
    (remove-hook 'flymake-diagnostic-functions #'attest-flymake-backend t)))

(defun attest-flymake--maybe-enable ()
  "Enable `attest-flymake-mode' when a backend owns the buffer."
  (when (and buffer-file-name (attest-backend-for-buffer))
    (attest-flymake-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-attest-flymake-mode
  attest-flymake-mode attest-flymake--maybe-enable
  :group 'attest)

(provide 'attest-flymake)
;;; attest-flymake.el ends here
