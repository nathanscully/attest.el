;;; attest.el --- Public testing commands -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, convenience
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

;; Public testing commands.

;;; Code:

(require 'attest-run)
;;;; Commands

;;;###autoload
(defun attest-run-at-point ()
  "Run the test or namespace at point."
  (interactive)
  (let ((pos (or (attest-position-at-point)
                 (user-error "Attest: no test at point"))))
    (attest-run 'targets :targets (list pos))))

;;;###autoload
(defun attest-run-file ()
  "Run every test in the current file."
  (interactive)
  (unless buffer-file-name (user-error "Attest: buffer has no file"))
  (attest-run 'file))

;;;###autoload
(defun attest-run-project ()
  "Run every test file in the current project."
  (interactive)
  (attest-run 'project))

;;;###autoload
(defun attest-rerun-last ()
  "Run the previous run again."
  (interactive)
  (attest--restart
   (or attest--last-run (user-error "Attest: nothing to rerun"))))

;;;###autoload
(defun attest-rerun-failed ()
  "Run only the tests that failed in the previous run."
  (interactive)
  (let* ((last (or attest--last-run (user-error "Attest: nothing to rerun")))
         (failed (seq-filter (lambda (r) (eq (attest-result-type r) 'test))
                             (attest-run-failed-results last))))
    (unless failed (user-error "Attest: no failed tests in last run"))
    (attest--restart last :scope 'targets :targets failed)))

;;;###autoload
(defun attest-kill ()
  "Kill the running test process, if any.
Attest tracks one run at a time, so this kills whichever run is current
whatever project it belongs to.  Starting a run kills the previous one
for the same reason."
  (interactive)
  (when-let* ((run attest--last-run))
    (when (and (eq (plist-get run :status) 'running)
               (not (plist-get run :end-time)))
      (when-let* ((process (plist-get run :process)))
        (when (process-live-p process)
          (set-process-sentinel process #'ignore)
          (delete-process process)))
      (attest--finish run 'killed))))

;;;###autoload
(defun attest-show-output ()
  "Display the raw output of the last run."
  (interactive)
  (if-let* ((buffer (get-buffer attest-output-buffer-name)))
      (pop-to-buffer buffer)
    (user-error "Attest: no output yet")))

(defvar-keymap attest-prefix-map
  :doc "Keymap for attest commands.
Attest binds no global keys.  Bind this map to a prefix of your own,
for example (keymap-global-set \"C-c t\" attest-prefix-map)."
  "t" #'attest-run-at-point
  "f" #'attest-run-file
  "p" #'attest-run-project
  "r" #'attest-rerun-last
  "x" #'attest-rerun-failed
  "k" #'attest-kill
  "o" #'attest-show-output)

(provide 'attest)
;;; attest.el ends here
