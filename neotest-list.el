;;; neotest-list.el --- Tabulated results view for neotest -*- lexical-binding: t; -*-

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `neotest-list' shows the results of the last run in a
;; `tabulated-list-mode' buffer.  RET visits the failing line, `o'
;; shows the failure message, `f' toggles failures-only, `x' reruns the
;; failed tests and `r' reruns everything.

;;; Code:

(require 'tabulated-list)
(require 'neotest)

(defvar neotest-list-buffer-name "*neotest results*"
  "Name of the results buffer.")

(defvar-local neotest-list--failures-only nil
  "Non-nil when only failed results are listed.")

(defun neotest-list--status-string (status)
  "Return STATUS as a propertized column string."
  (propertize (symbol-name status)
              'face (pcase status
                      ('passed 'success)
                      ('failed 'error)
                      (_ 'shadow))))

(defun neotest-list--entry (result)
  "Return the tabulated-list entry for RESULT."
  (let* ((location (plist-get result :location))
         (line (or (car location) (plist-get result :line))))
    (list result
          (vector (neotest-list--status-string (plist-get result :status))
                  (if-let* ((ms (plist-get result :duration)))
                      (format "%.1fms" ms)
                    "")
                  (string-join (neotest-id-names (plist-get result :id)) " > ")
                  (format "%s:%s"
                          (file-name-nondirectory (plist-get result :file))
                          line)))))

(defun neotest-list--entries ()
  "Return the entries for the last run, honouring the failure filter."
  (when-let* ((run (neotest-last-run)))
    (mapcar #'neotest-list--entry
            (seq-filter (lambda (r)
                          (and (eq (plist-get r :type) 'test)
                               (or (not neotest-list--failures-only)
                                   (eq (plist-get r :status) 'failed))))
                        (neotest-run-results run)))))

(defun neotest-list--result-at-point ()
  "Return the result on the current line or signal a user error."
  (or (tabulated-list-get-id) (user-error "No result on this line")))

(defun neotest-list-visit ()
  "Visit the failing line, or the test, of the result at point."
  (interactive)
  (let* ((result (neotest-list--result-at-point))
         (location (plist-get result :location))
         (line (or (car location) (plist-get result :line) 1))
         (column (cdr location)))
    (pop-to-buffer (find-file-noselect (plist-get result :file)))
    (goto-char (point-min))
    (forward-line (1- line))
    (when column (move-to-column (1- column)))))

(defun neotest-list-show-message ()
  "Show the failure message of the result at point."
  (interactive)
  (let ((result (neotest-list--result-at-point)))
    (message "%s" (or (plist-get result :message)
                      (format "%s: %s" (plist-get result :name)
                              (plist-get result :status))))))

(defun neotest-list-toggle-failures ()
  "Toggle between listing every result and failed results only."
  (interactive)
  (setq neotest-list--failures-only (not neotest-list--failures-only))
  (tabulated-list-revert))

(defvar-keymap neotest-list-mode-map
  :parent tabulated-list-mode-map
  "RET" #'neotest-list-visit
  "o" #'neotest-list-show-message
  "f" #'neotest-list-toggle-failures
  "x" #'neotest-rerun-failed
  "r" #'neotest-rerun-last)

(define-derived-mode neotest-list-mode tabulated-list-mode "neotest"
  "Major mode listing the results of the last neotest run."
  (setq tabulated-list-format
        [("Status" 8 t) ("Time" 9 nil) ("Test" 50 t) ("Location" 24 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-entries #'neotest-list--entries)
  (tabulated-list-init-header))

(defun neotest-list--refresh (_run)
  "Redraw the results buffer after a run, if it is live."
  (when-let* ((buffer (get-buffer neotest-list-buffer-name)))
    (with-current-buffer buffer
      (tabulated-list-revert))))

;;;###autoload
(defun neotest-list ()
  "Show the results of the last run."
  (interactive)
  (let ((buffer (get-buffer-create neotest-list-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'neotest-list-mode)
        (neotest-list-mode))
      (add-hook 'neotest-run-finished-hook #'neotest-list--refresh)
      (tabulated-list-revert))
    (pop-to-buffer buffer)))

(provide 'neotest-list)
;;; neotest-list.el ends here
