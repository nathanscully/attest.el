;;; neotest-flymake.el --- Show test failures through flymake -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/emacs-neotest

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A flymake backend that reports the latest failed tests as :error
;; diagnostics at the failing assertion, so they show inline, in
;; `flymake-show-buffer-diagnostics' and in
;; `flymake-show-project-diagnostics'.  Failures in files without a
;; buffer go to `flymake-list-only-diagnostics', which the project
;; listing also reads.
;;
;; Enable with `neotest-flymake-mode' in test buffers, or globally with
;; `global-neotest-flymake-mode'.

;;; Code:

(require 'flymake)
(require 'neotest)

(defvar neotest-flymake-mode)

(defun neotest-flymake--region (result)
  "Return the (BEG . END) buffer region RESULT should highlight."
  (let* ((location (plist-get result :location))
         (line (or (car location) (plist-get result :line) 1))
         (column (and location (cdr location))))
    (or (flymake-diag-region (current-buffer) line column)
        (save-excursion
          (goto-char (point-min))
          (forward-line (1- line))
          (cons (line-beginning-position) (line-end-position))))))

(defun neotest-flymake--message (result)
  "Return the diagnostic text for RESULT."
  (format "%s: %s"
          (string-join (neotest-id-names (plist-get result :id)) " > ")
          (string-trim (or (plist-get result :message) "failed"))))

(defun neotest-flymake--failures (file)
  "Return the failed test results recorded for FILE."
  (seq-filter (lambda (r) (and (eq (plist-get r :status) 'failed)
                               (eq (plist-get r :type) 'test)))
              (neotest-results-for-file file)))

(defun neotest-flymake--buffer-diagnostics ()
  "Return flymake diagnostics for the current buffer's failed tests."
  (when buffer-file-name
    (mapcar (lambda (result)
              (let ((region (neotest-flymake--region result)))
                (flymake-make-diagnostic (current-buffer) (car region) (cdr region)
                                         :error
                                         (neotest-flymake--message result)
                                         result)))
            (neotest-flymake--failures buffer-file-name))))

(defvar neotest-flymake--clearing nil
  "Non-nil while the backend must report no diagnostics.
Bound when the mode turns off, so flymake drops this backend's
diagnostics before the hook is removed; Emacs 30 keeps the
diagnostics of a backend that merely stops running.")

(defun neotest-flymake-backend (report-fn &rest _args)
  "Report the current buffer's failed tests to REPORT-FN."
  (funcall report-fn (unless neotest-flymake--clearing
                       (neotest-flymake--buffer-diagnostics))))

(defun neotest-flymake--list-only-diagnostic (result)
  "Return a file-locus diagnostic for RESULT, for unvisited files."
  (let ((location (plist-get result :location)))
    (flymake-make-diagnostic (plist-get result :file)
                             (cons (or (car location) (plist-get result :line) 1)
                                   (cdr location))
                             nil
                             :error
                             (neotest-flymake--message result)
                             result)))

(defun neotest-flymake--refresh (run)
  "Republish diagnostics for every file touched by RUN."
  (let ((files (delete-dups (mapcar (lambda (r) (plist-get r :file))
                                    (neotest-run-results run)))))
    (dolist (file files)
      (setf (alist-get file flymake-list-only-diagnostics nil 'remove #'string=) nil)
      (if-let* ((buffer (find-buffer-visiting file)))
          (with-current-buffer buffer
            (when (and neotest-flymake-mode flymake-mode)
              (flymake-start nil t)))
        (when-let* ((diags (mapcar #'neotest-flymake--list-only-diagnostic
                                   (neotest-flymake--failures file))))
          (push (cons file diags) flymake-list-only-diagnostics))))))

;;;###autoload
(define-minor-mode neotest-flymake-mode
  "Show neotest failures as flymake diagnostics in this buffer."
  :lighter nil
  (if neotest-flymake-mode
      (progn
        (add-hook 'flymake-diagnostic-functions #'neotest-flymake-backend nil t)
        (add-hook 'neotest-run-finished-functions #'neotest-flymake--refresh)
        (when flymake-mode (flymake-start nil t)))
    (let ((neotest-flymake--clearing t))
      (when flymake-mode (flymake-start nil t)))
    (remove-hook 'flymake-diagnostic-functions #'neotest-flymake-backend t)))

(defun neotest-flymake--maybe-enable ()
  "Enable `neotest-flymake-mode' when a backend owns the buffer."
  (when (and buffer-file-name (neotest-backend-for-buffer))
    (neotest-flymake-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-neotest-flymake-mode
  neotest-flymake-mode neotest-flymake--maybe-enable
  :group 'neotest)

(provide 'neotest-flymake)
;;; neotest-flymake.el ends here
