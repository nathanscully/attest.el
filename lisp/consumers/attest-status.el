;;; attest-status.el --- Fringe pass/fail markers for attest -*- lexical-binding: t; -*-

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

;; Marks each test's first line in the left fringe with its latest
;; status.  Markers update as results stream in and are restored from
;; the result cache when a test file is revisited.
;;
;; Enable with `attest-status-mode' or `global-attest-status-mode'.

;;; Code:

(require 'attest-loadpath)
(require 'attest)
(require 'cl-lib)

(defvar attest-status-mode)
(defvar global-attest-status-mode)

(defvar attest-status--global-buffers nil
  "Buffers whose status mode was enabled by the global status mode.")

(defface attest-status-passed
  '((t (:inherit success :background unspecified)))
  "Fringe face for passed tests."
  :group 'attest
  :package-version '(attest . "0.1.0"))

(defface attest-status-failed
  '((t (:inherit error :background unspecified)))
  "Fringe face for failed tests."
  :group 'attest
  :package-version '(attest . "0.1.0"))

(defface attest-status-skipped
  '((t (:inherit shadow :background unspecified)))
  "Fringe face for skipped and todo tests."
  :group 'attest
  :package-version '(attest . "0.1.0"))

(defface attest-status-running
  '((t (:inherit warning :background unspecified)))
  "Fringe face for tests in the current run."
  :group 'attest
  :package-version '(attest . "0.1.0"))

(when (fboundp 'define-fringe-bitmap)
  (define-fringe-bitmap 'attest-status-dot
    [#b00000000
     #b00111000
     #b01111100
     #b11111110
     #b11111110
     #b11111110
     #b01111100
     #b00111000]
    nil nil 'center))

(defun attest-status--face (status)
  "Return the fringe face for STATUS."
  (pcase status
    ('passed 'attest-status-passed)
    ('failed 'attest-status-failed)
    ('running 'attest-status-running)
    (_ 'attest-status-skipped)))

(defun attest-status--clear ()
  "Remove every status overlay in the current buffer."
  (save-restriction
    (widen)
    (remove-overlays (point-min) (point-max) 'attest-status t)))

(defun attest-status--place (result status)
  "Put a STATUS marker on the line of RESULT in the current buffer."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (forward-line (1- (or (plist-get result :line) 1)))
      (let* ((beg (line-beginning-position))
             (existing (seq-find (lambda (o) (overlay-get o 'attest-status))
                                 (overlays-in beg (1+ beg))))
             (overlay (or existing (make-overlay beg (min (1+ beg) (point-max))))))
        (overlay-put overlay 'attest-status t)
        (overlay-put overlay 'evaporate nil)
        (overlay-put overlay 'help-echo
                     (format "%s: %s" (attest-result-name result) status))
        (overlay-put overlay 'before-string
                     (propertize " " 'display
                                 (list 'left-fringe 'attest-status-dot
                                       (attest-status--face status))))))))

(defun attest-status--render-buffer ()
  "Rebuild the markers of the current buffer from the result cache."
  (attest-status--clear)
  (when buffer-file-name
    (dolist (result (attest-results-for-file buffer-file-name))
      (attest-status--place result (attest-result-status result)))))

(defun attest-status--results-changed (files)
  "Rebuild markers in the buffers visiting FILES, or in every buffer.
FILES is nil when the whole cache changed."
  (let ((keys (and files (mapcar #'attest--file-key files))))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and attest-status-mode buffer-file-name
                   (or (null keys)
                       (member (attest--file-key buffer-file-name) keys)))
          (attest-status--render-buffer))))))

(defun attest-status--on-result (_run result)
  "Mark RESULT in the buffer visiting its file, if any."
  (when-let* ((file (attest-result-file result))
              (buffer (find-buffer-visiting file)))
    (with-current-buffer buffer
      (when attest-status-mode
        (attest-status--place result (attest-result-status result))))))

(defun attest-status--on-start (run)
  "Mark previously known tests in RUN\='s scope as running.
Markers are rebuilt rather than repainted, so a test deleted since the
last run leaves no overlay behind."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and attest-status-mode buffer-file-name
                 (seq-some (lambda (f) (file-equal-p f buffer-file-name))
                           (attest-run-files run)))
        (attest-status--clear)
        (dolist (result (attest-results-for-file buffer-file-name))
          (attest-status--place
           result (if (and (attest-target-result-p run result)
                           (attest-run-position run (attest-result-definition-id result)))
                      'running
                    (attest-result-status result))))))))

(defun attest-status--on-finish (run)
  "Reconcile pending markers in every file touched by RUN."
  (attest-status--results-changed (attest-run-files run)))

;;;###autoload
(define-minor-mode attest-status-mode
  "Show attest results in the left fringe of this buffer."
  :lighter nil
  (if attest-status-mode
      (attest-status--render-buffer)
    (attest-status--clear)))

(defun attest-status--maybe-enable ()
  "Enable `attest-status-mode' when a backend owns the buffer."
  (when (and global-attest-status-mode
             buffer-file-name
             (attest-backend-for-buffer)
             (not attest-status-mode))
    (cl-pushnew (current-buffer) attest-status--global-buffers)
    (attest-status-mode 1)))

;;;###autoload
(define-minor-mode global-attest-status-mode
  "Enable `attest-status-mode' in buffers owned by an attest backend.
This explicit global mode avoids the private hook variables generated by
`define-globalized-minor-mode', whose implementation changed in Emacs 31."
  :global t
  :group 'attest
  (if global-attest-status-mode
      (progn
        (add-hook 'after-change-major-mode-hook #'attest-status--maybe-enable)
        (dolist (buffer (buffer-list))
          (with-current-buffer buffer
            (attest-status--maybe-enable))))
    (remove-hook 'after-change-major-mode-hook #'attest-status--maybe-enable)
    (dolist (buffer attest-status--global-buffers)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when attest-status-mode
            (attest-status-mode -1)))))
    (setq attest-status--global-buffers nil)))

(add-hook 'attest-result-functions #'attest-status--on-result)
(add-hook 'attest-run-started-functions #'attest-status--on-start)
(add-hook 'attest-run-finished-functions #'attest-status--on-finish)
(add-hook 'attest-results-changed-functions #'attest-status--results-changed)

(provide 'attest-status)
;;; attest-status.el ends here
