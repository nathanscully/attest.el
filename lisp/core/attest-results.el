;;; attest-results.el --- Result recording and indexed caches -*- lexical-binding: t; -*-

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

;; Result recording and indexed caches.

;;; Code:

(require 'attest-discovery)
;;;; Results

(defvar attest--results (make-hash-table :test 'equal)
  "Latest known result for every test id.")

(defvar attest--last-run nil
  "The most recent run plist.
Attest deliberately tracks a single run: starting one kills the one
before it, and `attest-kill' stops whichever is current.  Two projects
cannot run at the same time.")

(defvar attest--results-by-file (make-hash-table :test 'equal)
  "Ids of the results recorded for each file, keyed by true name.
Lets a consumer ask for one file\='s results without walking every id
in `attest--results'.")

(defun attest--file-ids (file)
  "Return the table of result ids recorded for FILE, creating it if needed."
  (let ((key (attest--file-key file)))
    (or (gethash key attest--results-by-file)
        (puthash key (make-hash-table :test 'equal) attest--results-by-file))))

(defun attest-cache-result (result)
  "Store RESULT in the cache and its file index, outside any run.
`attest--record' is the path a runner takes; this is for a caller that
has a result already, such as a test seeding known state.  An id already
cached under another file is moved, so the old file keeps no ghost."
  (let ((id (attest-result-case-id result)))
    (unless id (error "Attest: result without :id or :case-id: %S" result))
    (attest--forget-stale-file id (attest-result-file result))
    (puthash id result attest--results)
    (puthash id t (attest--file-ids (attest-result-file result)))
    result))

(defun attest--forget-result (id)
  "Drop ID from the result cache and from its file\='s index."
  (when-let* ((result (gethash id attest--results)))
    (when-let* ((key (attest--file-key (attest-result-file result))))
      (when-let* ((ids (gethash key attest--results-by-file)))
        (remhash id ids)
        (when (zerop (hash-table-count ids))
          (remhash key attest--results-by-file)))))
  (remhash id attest--results))

(defun attest-result (id)
  "Return the latest result recorded for ID."
  (gethash id attest--results))

(defun attest-results-for-file (file)
  "Return the latest results whose test lives in FILE.
Read from the per-file index, so the cost is the number of results in
FILE rather than the number of results known."
  (let (acc)
    (when-let* ((ids (gethash (attest--file-key file) attest--results-by-file)))
      (maphash (lambda (id _t)
                 (when-let* ((result (gethash id attest--results)))
                   (push result acc)))
               ids))
    (nreverse acc)))

;;;###autoload
(defun attest--forget-stale-file (id file)
  "Drop ID from its old file index when FILE is not where it was cached."
  (when-let* ((previous (gethash id attest--results)))
    (unless (equal (attest--file-key (attest-result-file previous))
                   (attest--file-key file))
      (attest--forget-result id))))

(defun attest-clear-results (&optional file)
  "Forget every cached result, or only those recorded for FILE.
Interactively with a prefix argument, clear the current buffer\='s file."
  (interactive (list (and current-prefix-arg buffer-file-name)))
  (if file
      (dolist (result (attest-results-for-file file))
        (attest--forget-result (attest-result-case-id result)))
    (clrhash attest--results)
    (clrhash attest--results-by-file))
  (run-hook-with-args 'attest-results-changed-functions
                      (and file (list (expand-file-name file)))))

(defun attest-last-run ()
  "Return the most recent run plist."
  attest--last-run)

(defun attest-run-result (run id)
  "Return the result RUN recorded for ID, or nil.
Unlike `attest-result' this is fixed once recorded, so a later run
reporting the same id does not change what RUN returns."
  (when-let* ((table (plist-get run :results)))
    (gethash id table)))

(defun attest-run-results (run)
  "Return the results recorded during RUN, in arrival order.
Ids reported more than once, such as parametrized cases, appear once.
The results are RUN's own, unaffected by later runs."
  (mapcar (lambda (id) (attest-run-result run id))
          (delete-dups (reverse (plist-get run :result-ids)))))

(defun attest-run-invocations (run)
  "Return RUN's invocations in execution order.
Each invocation is an `attest-invocation' record owned by RUN; the
returned list is a fresh list and its records are not copied."
  (reverse (copy-sequence (plist-get run :invocations))))

(defun attest-run-exit-codes (run)
  "Return RUN's invocation exit codes in execution order.
The legacy `:exit-code' field remains the most recent code; this accessor
preserves every code when a plan contains multiple invocations."
  (reverse (copy-sequence (plist-get run :exit-codes))))

(defun attest-run-failed-results (run)
  "Return the failed results of RUN."
  (seq-filter (lambda (result) (eq (attest-result-status result) 'failed))
              (attest-run-results run)))

(defun attest-run-complete-p (run)
  "Return non-nil when RUN reached a trustworthy terminal state.
A finished run with parser, protocol or infrastructure errors is not
complete even when the process exited successfully."
  (and (eq (plist-get run :status) 'finished)
       (null (plist-get run :errors))))

(defun attest--run-outcome (run results)
  "Return RUN's outcome using already materialized RESULTS."
  (cond ((eq (plist-get run :status) 'killed) 'cancelled)
        ((not (attest-run-complete-p run))
         (if (eq (plist-get run :status) 'error) 'error 'incomplete))
        ((seq-some (lambda (result)
                     (eq (attest-result-status result) 'failed))
                   results)
         'failed)
        ((null (seq-filter (lambda (result)
                             (eq (attest-result-type result) 'test))
                           results))
         'empty)
        (t 'passed)))

(defun attest-run-outcome (run)
  "Return RUN's test outcome independently of its lifecycle status.
Possible outcomes are `passed', `failed', `empty', `error',
`cancelled' and `incomplete'."
  (attest--run-outcome run (attest-run-results run)))

(defun attest-run-summary (run)
  "Return a fresh summary plist for RUN.
Counts include test results only; namespace results remain available from
`attest-run-results' but do not affect the test totals."
  (let* ((all-results (attest-run-results run))
         (results (seq-filter (lambda (result)
                                (eq (attest-result-type result) 'test))
                              all-results))
         (passed (seq-count (lambda (result)
                              (eq (attest-result-status result) 'passed))
                            results))
         (failed (seq-count (lambda (result)
                              (eq (attest-result-status result) 'failed))
                            results))
         (skipped (seq-count (lambda (result)
                               (eq (attest-result-status result) 'skipped))
                             results))
         (todo (seq-count (lambda (result)
                            (eq (attest-result-status result) 'todo))
                          results)))
    (list :status (plist-get run :status)
          :outcome (attest--run-outcome run all-results)
          :complete-p (attest-run-complete-p run)
          :tests (length results)
         :results (length all-results)
          :invocations (length (attest-run-invocations run))
          :pending-invocations (length (plist-get run :pending-invocations))
          :exit-codes (attest-run-exit-codes run)
          :passed passed
          :failed failed
          :skipped skipped
          :todo todo
          :errors (copy-sequence (plist-get run :errors))
          :exit-code (plist-get run :exit-code))))

(defun attest--record (run result)
  "Store RESULT from RUN and notify consumers.
When discovery knows the test, its :line, :column and :type come from
the position, so the runner's own notion of where a test lives is only
a fallback."
  (let ((id (attest-result-case-id result)))
    (unless id (error "Attest: result without :id or :case-id: %S" result))
    (when-let* ((pos (and (plist-get run :backend)
                          (attest-run-position
                           run (attest-result-definition-id result)))))
      (plist-put result :line (plist-get pos :line))
      (plist-put result :column (plist-get pos :column))
      (unless (attest-result-type result)
        (plist-put result :type (plist-get pos :type))))
    (unless (attest-result-type result) (plist-put result :type 'test))
    (when-let* ((previous (attest-run-result run id)))
      (when (and (eq (attest-result-status previous) 'failed)
                 (not (eq (attest-result-status result) 'failed)))
        (setq result previous)))
    (attest--forget-stale-file id (attest-result-file result))
    (puthash id result attest--results)
    (puthash id t (attest--file-ids (attest-result-file result)))
    (let ((table (or (plist-get run :results)
                     (let ((new (make-hash-table :test 'equal)))
                       (plist-put run :results new)
                       new))))
      (puthash id result table))
    (plist-put run :result-ids (cons id (plist-get run :result-ids)))
    (plist-put run :active-result-ids (cons id (plist-get run :active-result-ids)))
    (attest--notify 'attest-result-functions run result)))

(defun attest-report-error (run message)
  "Record a runner or protocol error MESSAGE on RUN without losing results."
  (plist-put run :errors (cons message (plist-get run :errors)))
  (message "Attest: %s" message))

(provide 'attest-results)
;;; attest-results.el ends here
