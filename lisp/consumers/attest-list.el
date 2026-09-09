;;; attest-list.el --- Tabulated results view for attest -*- lexical-binding: t; -*-

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

;; `attest-list' shows the results of the last run in a
;; `tabulated-list-mode' buffer.  RET visits the failing line, `o'
;; shows the failure message, `f' toggles failures-only, `x' reruns the
;; failed tests and `r' reruns everything.

;;; Code:

(require 'tabulated-list)
(require 'attest)

(defcustom attest-list-buffer-name "*attest results*"
  "Name of the buffer showing the results of the last run."
  :type 'string
  :group 'attest
  :package-version '(attest . "0.1.0"))

(defvar-local attest-list--failures-only nil
  "Non-nil when only failed results are listed.")

(defun attest-list--status-string (status)
  "Return STATUS as a propertized column string."
  (propertize (symbol-name status)
              'face (pcase status
                      ('passed 'success)
                      ('failed 'error)
                      (_ 'shadow))))

(defun attest-list--entry (result)
  "Return the tabulated-list entry for RESULT."
  (let* ((location (plist-get result :location))
         (line (or (car location) (plist-get result :line))))
    (list result
          (vector (attest-list--status-string (attest-result-status result))
                  (if-let* ((ms (plist-get result :duration)))
                      (format "%.1fms" ms)
                    "")
                  (string-join (attest-id-names (attest-result-case-id result)) " > ")
                  (format "%s:%s"
                          (file-name-nondirectory (attest-result-file result))
                          line)))))

(defun attest-list--entries ()
  "Return the entries for the last run, honouring the failure filter.
A result the cache no longer holds is dropped, so clearing results
empties the list rather than leaving the last run on screen."
  (when-let* ((run (attest-last-run)))
    (mapcar #'attest-list--entry
            (seq-filter (lambda (r)
                          (and (eq (attest-result-type r) 'test)
                               (attest-result (attest-result-case-id r))
                               (or (not attest-list--failures-only)
                                   (eq (attest-result-status r) 'failed))))
                        (attest-run-results run)))))

(defun attest-list--result-at-point ()
  "Return the result on the current line or signal a user error."
  (or (tabulated-list-get-id) (user-error "No result on this line")))

(defun attest-list-visit ()
  "Visit the failing line, or the test, of the result at point."
  (interactive)
  (let* ((result (attest-list--result-at-point))
         (location (plist-get result :location))
         (line (or (car location) (plist-get result :line) 1))
         (column (cdr location)))
    (pop-to-buffer (find-file-noselect (attest-result-file result)))
    (goto-char (point-min))
    (forward-line (1- line))
    (when column
      (forward-char (min (1- column)
                         (- (line-end-position) (point)))))))

(defun attest-list-show-message ()
  "Show the failure message of the result at point."
  (interactive)
  (let ((result (attest-list--result-at-point)))
    (message "%s" (or (plist-get result :message)
                      (format "%s: %s" (attest-result-name result)
                              (attest-result-status result))))))

(defun attest-list-toggle-failures ()
  "Toggle between listing every result and failed results only."
  (interactive)
  (setq attest-list--failures-only (not attest-list--failures-only))
  (tabulated-list-revert))

(defvar-keymap attest-list-mode-map
  :parent tabulated-list-mode-map
  "RET" #'attest-list-visit
  "o" #'attest-list-show-message
  "f" #'attest-list-toggle-failures
  "x" #'attest-rerun-failed
  "r" #'attest-rerun-last)

(define-derived-mode attest-list-mode tabulated-list-mode "attest"
  "Major mode listing the results of the last attest run."
  (setq tabulated-list-format
        [("Status" 8 t) ("Time" 9 nil) ("Test" 50 t) ("Location" 24 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-entries #'attest-list--entries)
  (tabulated-list-init-header))

(defun attest-list--refresh (_run)
  "Redraw the results buffer after a run, if it is live."
  (when-let* ((buffer (get-buffer attest-list-buffer-name)))
    (with-current-buffer buffer
      (tabulated-list-revert))))

(defun attest-list--results-changed (_files)
  "Redraw the results buffer when the cache changed outside a run."
  (attest-list--refresh nil))

;;;###autoload
(defun attest-list ()
  "Show the results of the last run."
  (interactive)
  (let ((buffer (get-buffer-create attest-list-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'attest-list-mode)
        (attest-list-mode))
      (add-hook 'attest-run-finished-functions #'attest-list--refresh)
      (add-hook 'attest-results-changed-functions #'attest-list--results-changed)
      (tabulated-list-revert))
    (pop-to-buffer buffer)))

(provide 'attest-list)
;;; attest-list.el ends here
