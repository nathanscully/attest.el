;;; attest-flymake.el --- Show test failures through flymake -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/attest.el

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

(require 'attest-loadpath)
(require 'flymake)
(require 'attest)

(defcustom attest-flymake-auto-enable-flymake t
  "Turn on `flymake-mode' when `attest-flymake-mode' is enabled.
Attest reports through flymake, so without `flymake-mode' nothing is
shown.  Set to nil to manage `flymake-mode' yourself."
  :type 'boolean
  :group 'attest
  :package-version '(attest . "0.1.0"))

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
          (string-join (attest-id-names (attest-result-case-id result)) " > ")
          (string-trim (or (plist-get result :message) "failed"))))

(defun attest-flymake--failures (file)
  "Return the failed test results recorded for FILE."
  (seq-filter (lambda (r) (and (eq (attest-result-status r) 'failed)
                               (eq (attest-result-type r) 'test)))
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
    (flymake-make-diagnostic (attest-result-file result)
                             (cons (or (car location) (plist-get result :line) 1)
                                   (cdr location))
                             nil
                             :error
                             (attest-flymake--message result)
                             result)))

(defun attest-flymake--own-diagnostic-p (diagnostic)
  "Return non-nil when DIAGNOSTIC came from attest.
Attest passes the result plist as the diagnostic data, so its own
entries carry an :id."
  (let ((data (flymake-diagnostic-data diagnostic)))
    (and (listp data) (attest-result-case-id data) t)))

(defun attest-flymake--drop-list-only (file)
  "Remove only attest\='s list-only diagnostics for FILE.
`flymake-list-only-diagnostics' is shared, so the entry can hold another
backend\='s diagnostics; those are put back."
  (when-let* ((entry (assoc file flymake-list-only-diagnostics)))
    (let ((keep (seq-remove #'attest-flymake--own-diagnostic-p (cdr entry))))
      (if keep
          (setcdr entry keep)
        (setq flymake-list-only-diagnostics
              (delq entry flymake-list-only-diagnostics))))))

(defun attest-flymake--refresh (run)
  "Republish diagnostics for every file touched by RUN."
  (let ((files (delete-dups
                (delq nil (append (attest-run-files run)
                                  (mapcar #'attest-result-file
                                          (attest-run-results run)))))))
    (dolist (file files)
      (attest-flymake--drop-list-only file)
      (if-let* ((buffer (find-buffer-visiting file)))
          (with-current-buffer buffer
            (when (and attest-flymake-mode flymake-mode)
              (flymake-start nil t)))
        (when-let* ((diags (mapcar #'attest-flymake--list-only-diagnostic
                                   (attest-flymake--failures file))))
          (push (cons file diags) flymake-list-only-diagnostics))))))

;;;###autoload
(define-minor-mode attest-flymake-mode
  "Show attest failures as flymake diagnostics in this buffer.
Diagnostics need `flymake-mode' too, which this turns on unless
`attest-flymake-auto-enable-flymake' is nil."
  :lighter nil
  (if attest-flymake-mode
      (progn
        (add-hook 'flymake-diagnostic-functions #'attest-flymake-backend nil t)
        (when (and attest-flymake-auto-enable-flymake (not flymake-mode))
          (flymake-mode 1))
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

(defun attest-flymake--results-changed (files)
  "Republish diagnostics for FILES, or drop them all.
FILES is nil when the whole cache changed, which leaves nothing to
report: every list-only entry attest owns goes, and every live buffer
running this backend rechecks."
  (if files
      (dolist (file files)
        (attest-flymake--drop-list-only file)
        (when-let* ((buffer (find-buffer-visiting file)))
          (with-current-buffer buffer
            (when (and attest-flymake-mode flymake-mode)
              (flymake-start nil t)))))
    (dolist (entry (copy-sequence flymake-list-only-diagnostics))
      (attest-flymake--drop-list-only (car entry)))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and attest-flymake-mode flymake-mode)
          (flymake-start nil t))))))

(add-hook 'attest-run-finished-functions #'attest-flymake--refresh)
(add-hook 'attest-results-changed-functions #'attest-flymake--results-changed)

(provide 'attest-flymake)
;;; attest-flymake.el ends here
