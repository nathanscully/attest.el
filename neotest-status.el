;;; neotest-status.el --- Fringe pass/fail markers for neotest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/emacs-neotest

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Marks each test's first line in the left fringe with its latest
;; status.  Markers update as results stream in and are restored from
;; the result cache when a test file is revisited.
;;
;; Enable with `neotest-status-mode' or `global-neotest-status-mode'.

;;; Code:

(require 'neotest)

(defvar neotest-status-mode)

(defface neotest-status-passed
  '((t :inherit success))
  "Fringe face for passed tests."
  :group 'neotest
  :package-version '(neotest . "0.1.0"))

(defface neotest-status-failed
  '((t :inherit error))
  "Fringe face for failed tests."
  :group 'neotest
  :package-version '(neotest . "0.1.0"))

(defface neotest-status-skipped
  '((t :inherit shadow))
  "Fringe face for skipped and todo tests."
  :group 'neotest
  :package-version '(neotest . "0.1.0"))

(defface neotest-status-running
  '((t :inherit warning))
  "Fringe face for tests in the current run."
  :group 'neotest
  :package-version '(neotest . "0.1.0"))

(when (fboundp 'define-fringe-bitmap)
  (define-fringe-bitmap 'neotest-status-dot
    [#b00000000
     #b00111000
     #b01111100
     #b11111110
     #b11111110
     #b11111110
     #b01111100
     #b00111000]
    nil nil 'center))

(defun neotest-status--face (status)
  "Return the fringe face for STATUS."
  (pcase status
    ('passed 'neotest-status-passed)
    ('failed 'neotest-status-failed)
    ('running 'neotest-status-running)
    (_ 'neotest-status-skipped)))

(defun neotest-status--clear ()
  "Remove every status overlay in the current buffer."
  (remove-overlays (point-min) (point-max) 'neotest-status t))

(defun neotest-status--place (result status)
  "Put a STATUS marker on the line of RESULT in the current buffer."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (forward-line (1- (or (plist-get result :line) 1)))
      (let* ((beg (line-beginning-position))
             (existing (seq-find (lambda (o) (overlay-get o 'neotest-status))
                                 (overlays-in beg (1+ beg))))
             (overlay (or existing (make-overlay beg (min (1+ beg) (point-max))))))
        (overlay-put overlay 'neotest-status t)
        (overlay-put overlay 'evaporate nil)
        (overlay-put overlay 'help-echo
                     (format "%s: %s" (plist-get result :name) status))
        (overlay-put overlay 'before-string
                     (propertize " " 'display
                                 (list 'left-fringe 'neotest-status-dot
                                       (neotest-status--face status))))))))

(defun neotest-status--render-buffer ()
  "Rebuild the markers of the current buffer from the result cache."
  (neotest-status--clear)
  (when buffer-file-name
    (dolist (result (neotest-results-for-file buffer-file-name))
      (neotest-status--place result (plist-get result :status)))))

(defun neotest-status--on-result (_run result)
  "Mark RESULT in the buffer visiting its file, if any."
  (when-let* ((buffer (find-buffer-visiting (plist-get result :file))))
    (with-current-buffer buffer
      (when neotest-status-mode
        (neotest-status--place result (plist-get result :status))))))

(defun neotest-status--on-start (run)
  "Mark previously known tests in RUN's scope as running."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and neotest-status-mode buffer-file-name
                 (member buffer-file-name (neotest-run-files run)))
        (dolist (result (neotest-results-for-file buffer-file-name))
          (neotest-status--place result 'running))))))

;;;###autoload
(define-minor-mode neotest-status-mode
  "Show neotest results in the left fringe of this buffer."
  :lighter nil
  (if neotest-status-mode
      (progn
        (add-hook 'neotest-result-functions #'neotest-status--on-result)
        (add-hook 'neotest-run-started-functions #'neotest-status--on-start)
        (neotest-status--render-buffer))
    (neotest-status--clear)))

(defun neotest-status--maybe-enable ()
  "Enable `neotest-status-mode' when a backend owns the buffer."
  (when (and buffer-file-name (neotest-backend-for-buffer))
    (neotest-status-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-neotest-status-mode
  neotest-status-mode neotest-status--maybe-enable
  :group 'neotest)

(provide 'neotest-status)
;;; neotest-status.el ends here
