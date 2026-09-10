;;; attest-run.el --- Run lifecycle and process transport -*- lexical-binding: t; -*-

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

;; Run lifecycle and process transport.

;;; Code:

(require 'attest-results)
(require 'compile)
(require 'ansi-color)
(declare-function attest-kill "attest" ())
(declare-function attest-rerun-last "attest" ())
;;;; Runs

(defun attest--project-test-files (backend root)
  "Return the test files under ROOT accepted by BACKEND.
ROOT is the backend\='s root, which can be a package inside a larger
`project-current' checkout; files outside ROOT are dropped.  A root
under no version control still has test files, so when `project-current'
knows nothing about ROOT the directory is walked instead."
  (let ((pred (plist-get (attest-backend-props backend) :test-file-p))
        (project (project-current nil root)))
    (unless pred (error "Attest: backend `%s' has no :test-file-p" backend))
    (seq-filter (lambda (file) (and (file-in-directory-p file root)
                                    (funcall pred file)))
                (if project
                    (project-files project)
                  (directory-files-recursively
                   root "" nil
                   (lambda (dir)
                     (not (member (file-name-nondirectory
                                   (directory-file-name dir))
                                  attest-project-skip-directories))))))))

(defun attest-run-description (run)
  "Return a short human description of what RUN covers."
  (pcase (plist-get run :scope)
    ('project (format "%d files in %s"
                      (length (plist-get run :files))
                      (file-name-nondirectory
                       (directory-file-name (plist-get run :root)))))
    ('targets (let ((targets (plist-get run :targets)))
                (if (= (length targets) 1)
                    (plist-get (car targets) :name)
                  (format "%d targets" (length targets)))))
    (_ (file-name-nondirectory (or (plist-get run :file) "")))))

(defun attest-run-active-p (run)
  "Return non-nil when RUN may still receive asynchronous callbacks.
Preparation continuations and process filters use this identity check so
a cancelled run cannot launch work for its replacement."
  (and (eq run attest--last-run)
       (eq (plist-get run :status) 'running)
       (null (plist-get run :end-time))))

(defvar attest--progress-timer nil
  "Timer refreshing the mode line while a run is in flight.")

(defvar-local attest--progress-mode-line nil
  "The buffer\='s `mode-line-process' before attest appended to it.
Restored on stop, so a string value comes back as a string rather than
the one-element list appending would leave.")

(defvar-local attest--progress nil
  "Mode line construct shown while a run covering this buffer is active.")

(defun attest--progress-buffers (run)
  "Return the live buffers RUN covers.
Compared by true name, so a buffer visiting the same file under another
spelling still shows the indicator."
  (let ((keys (delq nil (mapcar #'attest--file-key (attest-run-files run)))))
    (seq-filter (lambda (buffer)
                  (with-current-buffer buffer
                    (and buffer-file-name
                         (member (attest--file-key buffer-file-name) keys))))
                (buffer-list))))

(defun attest--progress-update (run)
  "Refresh the mode line indicator for RUN."
  (if (not (eq (plist-get run :status) 'running))
      (attest--progress-stop run)
    (let ((text (format " [attest %ds]"
                        (truncate (- (float-time) (plist-get run :start-time))))))
      (dolist (buffer (attest--progress-buffers run))
        (with-current-buffer buffer
          (setq attest--progress text)))
      (force-mode-line-update t))))

(defun attest--progress-start (run)
  "Show that RUN has started, in the echo area and the mode line.
Called before discovery, which parses every file in scope on the Emacs
thread and takes hundreds of milliseconds on a large project.  Emacs is
unresponsive for that stretch, so it must not also be silent."
  (message "attest: running %s..." (attest-run-description run))
  (dolist (buffer (attest--progress-buffers run))
    (with-current-buffer buffer
      (unless (and (listp mode-line-process)
                   (memq 'attest--progress mode-line-process))
        (setq-local attest--progress-mode-line mode-line-process)
        (setq-local mode-line-process
                    (append (if (listp mode-line-process)
                                (copy-sequence mode-line-process)
                              (list mode-line-process))
                            (list 'attest--progress))))))
  (attest--progress-update run)
  (when attest--progress-timer (cancel-timer attest--progress-timer))
  (setq attest--progress-timer
        (run-at-time 1 1 #'attest--progress-update run)))

(defun attest--progress-stop (run)
  "Clear the mode line indicator left by RUN."
  (when attest--progress-timer
    (cancel-timer attest--progress-timer)
    (setq attest--progress-timer nil))
  (dolist (buffer (attest--progress-buffers run))
    (with-current-buffer buffer
      (setq attest--progress nil)
      (when (and (listp mode-line-process)
                 (memq 'attest--progress mode-line-process))
        (setq-local mode-line-process attest--progress-mode-line))
      (kill-local-variable 'attest--progress-mode-line)))
  (force-mode-line-update t))

(defun attest-target-result-p (run result)
  "Return non-nil when RESULT belongs to RUN\='s targets.
Always true for a run without targets.  A namespace target claims every
result below it.  Runners select targets by name, so a `targets' run
over several files can execute a same-named test in another file; this
keeps those out of the cache."
  (or (not (eq (plist-get run :scope) 'targets))
      (let ((id (attest-result-case-id result)))
        (seq-some (lambda (target)
                    (let ((target-id (plist-get target :id)))
                      (if (eq (plist-get target :type) 'namespace)
                          (string-prefix-p (concat target-id attest-id-separator) id)
                        (equal target-id id))))
                  (plist-get run :targets)))))

(defun attest--prune-file (run file)
  "Drop cached results for FILE that RUN\='s discovery no longer lists.
Discovery is authoritative: a test deleted or renamed since the last run
keeps no stale status.  Unreadable files are left alone so a transient
read failure never clears results, and so are files discovery skips for
size: no positions there means nothing was discovered, not that the
tests are gone."
  (let ((file (expand-file-name file)))
    (when (and (or (find-buffer-visiting file) (file-readable-p file))
               (or (find-buffer-visiting file)
                   (attest--parseable-size-p file)))
      (let ((known (attest-run-position-table run file))
            (stale nil))
        (dolist (result (attest-results-for-file file))
          (let ((id (attest-result-case-id result)))
            (unless (gethash (attest-result-definition-id result) known)
              (push id stale))))
        (dolist (id stale) (attest--forget-result id))
        stale))))

(defun attest--prune-run-scope (run)
  "Drop cached results RUN's files no longer contain."
  (dolist (file (attest-run-files run))
    (attest--prune-file run file)))

(defun attest--make-run (scope &rest props)
  "Build a run plist for SCOPE from the current buffer, merging PROPS."
  (let* ((backend (attest--require-backend scope))
         (file (and buffer-file-name (expand-file-name buffer-file-name)))
         (root (attest-project-root file backend))
         (run (append (list :backend backend
                            :scope scope
                            :file file
                            :root root
                            :buffer (current-buffer)
                            :status 'pending
                            :result-ids nil
                            :results nil
                            :state nil)
                      props)))
    (plist-put run :request (attest--request-for-run run))
    run))

(defun attest--request-for-run (run)
  "Build an immutable-by-convention request snapshot from RUN."
  (attest-request-create
   :backend (plist-get run :backend)
   :scope (plist-get run :scope)
   :file (plist-get run :file)
   :root (plist-get run :root)
   :buffer (plist-get run :buffer)
   :targets (mapcar #'copy-sequence (plist-get run :targets))
   :files (copy-sequence (plist-get run :files))))

(defun attest-run-request (run)
  "Return RUN's request snapshot, or nil for an older run plist."
  (or (plist-get run :request)
      (and run (attest--request-for-run run))))

(defun attest--output-buffer (run)
  "Return the output buffer for RUN, resetting its contents."
  (let ((buffer (get-buffer-create attest-output-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (unless (derived-mode-p 'attest-output-mode)
          (attest-output-mode))
        (setq default-directory (plist-get run :directory))
        (insert (propertize
                 (format "%s\n\n" (string-join (plist-get run :command) " "))
                 'face 'shadow))))
    buffer))

(defvar attest-output-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "g" #'attest-rerun-last)
    map)
  "Keymap for `attest-output-mode'.
Rebinds g, which `special-mode' gives to `revert-buffer', to rerun.")

(define-derived-mode attest-output-mode special-mode "attest-out"
  "Major mode for raw attest runner output."
  (add-to-list 'compilation-error-regexp-alist-alist
               '(attest-file-url
                 "(?\\(?:file://\\)?\\(/[^:()[:space:]]+\\):\\([0-9]+\\):\\([0-9]+\\))?"
                 1 2 3))
  (setq-local compilation-error-regexp-alist
              (cons 'attest-file-url compilation-error-regexp-alist))
  (setq-local ansi-color-context-region nil)
  (compilation-minor-mode 1))

(defun attest--trim-output ()
  "Drop the oldest output in the current buffer past `attest-max-output'."
  (when attest-max-output
    (let ((excess (- (buffer-size) attest-max-output)))
      (when (> excess 0)
        (save-excursion
          (goto-char (point-min))
          (forward-char excess)
          (forward-line 1)
          (delete-region (point-min) (point))
          (goto-char (point-min))
          (insert (propertize "[earlier output dropped]\n" 'face 'shadow)))))))

(defun attest-append-output (run string)
  "Append STRING to RUN\='s output buffer.
Backends whose runner embeds human-readable output inside structured
events call this to surface it.  The oldest output is dropped once the
buffer passes `attest-max-output', so a runner that never stops talking
cannot exhaust memory."
  (when-let* ((buffer (plist-get run :output-buffer)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (at-end (= (point) (point-max))))
          (save-excursion
            (goto-char (point-max))
            (let ((start (point)))
              (insert string)
              (ansi-color-apply-on-region start (point))))
          (attest--trim-output)
          (when at-end (goto-char (point-max))))))))

(defun attest-parse-json-line (run line &optional array-type)
  "Return the JSON object LINE holds, or nil, sending other lines to output.
A runner interleaves its own human-readable output with the structured
events attest reads, so a line that is not JSON belongs in RUN\='s output
buffer.  ARRAY-TYPE is passed to `json-parse-string'; objects come back
as alists with null and false read as nil."
  (if (string-prefix-p "{" line)
      (condition-case err
          (json-parse-string line :object-type 'alist
                             :array-type (or array-type 'array)
                             :null-object nil :false-object nil)
        (error (attest-report-error run (error-message-string err)) nil))
    (attest-append-output run (concat line "\n"))
    nil))

(defun attest--feed-lines (run key string)
  "Split STRING into lines, buffering a partial line under KEY in RUN.
Complete lines go to the backend\='s :parse-line.  A carriage return
before the newline is dropped so a runner emitting CRLF still parses."
  (let ((frame (plist-get run key)) (start 0) newline)
    (unless (attest-frame-p frame)
      (setq frame (attest-frame-create))
      (plist-put run key frame))
    (while (< start (length string))
      (setq newline (string-match "\n" string start))
      (unless (attest-frame-discarding frame)
        (let ((chunk (substring string start newline)))
          (cl-incf (attest-frame-bytes frame) (string-bytes chunk))
          (if (> (attest-frame-bytes frame) attest-max-event-size)
              (progn
                (setf (attest-frame-chunks frame) nil
                      (attest-frame-discarding frame) t)
                (attest-report-error run "Structured event exceeds attest-max-event-size"))
            (push chunk (attest-frame-chunks frame)))))
      (when newline
        (attest--emit-frame run frame)
        (setf (attest-frame-discarding frame) nil))
      (setq start (if newline (1+ newline) (length string))))))

(defun attest--emit-frame (run frame)
  "Parse a completed FRAME for RUN and release its retained chunks."
  (unless (attest-frame-discarding frame)
    (attest--parse-line
     run (plist-get (attest-backend-props (plist-get run :backend)) :parse-line)
     (string-remove-suffix "\r" (apply #'concat (nreverse (attest-frame-chunks frame))))))
  (setf (attest-frame-chunks frame) nil (attest-frame-bytes frame) 0))

(defun attest--parse-line (run parse line)
  "Feed LINE to PARSE for RUN and record whatever it returns.
A backend error is reported and the line dropped, so one bad line
cannot stop the run."
  (condition-case err
      (let ((results (funcall parse run line)))
        (when (and results (keywordp (car results)))
          (setq results (list results)))
        (dolist (result results)
          (attest--record run result)))
    (error (attest-report-error run
                                (format "%s parser failed: %s"
                                        (plist-get run :backend)
                                        (error-message-string err))))))

(defun attest--flush-lines (run key)
  "Parse a trailing partial line buffered under KEY in RUN."
  (let ((rest (plist-get run key)))
    (when (and (attest-frame-p rest) (attest-frame-chunks rest))
      (attest--emit-frame run rest))))

(defun attest--make-filter (run key parse-p)
  "Return a process filter for RUN.
KEY names the partial-line slot.  When PARSE-P, lines are parsed;
otherwise they only go to the output buffer.  Output arriving after RUN
stopped is dropped, so a late chunk from a killed process cannot reach
the cache of whatever run replaced it."
  (lambda (_process string)
    (when (eq (plist-get run :status) 'running)
      (if parse-p
          (attest--feed-lines run key string)
        (attest-append-output run string)))))

(defun attest--finish (run status)
  "Mark RUN finished with STATUS, notify consumers and report a summary."
  (unless (plist-get run :end-time)
    (when-let* ((timer (plist-get run :preparation-timer)))
      (cancel-timer timer)
      (plist-put run :preparation-timer nil))
    (attest--flush-lines run :partial-stdout)
    (attest--flush-lines run :partial-stderr)
    (plist-put run :status status)
    (plist-put run :end-time (float-time))
    (attest--progress-stop run)
    (when-let* ((stderr (plist-get run :stderr-process)))
      (when (process-live-p stderr) (delete-process stderr)))
    (attest--notify 'attest-run-finished-functions run)
    (let ((summary (attest-run-summary run)))
      (message "attest: %d passed, %d failed, %d skipped (%s in %.1fs)"
               (plist-get summary :passed)
               (plist-get summary :failed)
               (+ (plist-get summary :skipped)
                  (plist-get summary :todo))
               status
               (- (plist-get run :end-time) (plist-get run :start-time)))
      (when (or (eq attest-display-output t)
                (and (eq attest-display-output 'on-failure)
                     (memq (plist-get summary :outcome) '(failed error))))
        (when-let* ((buffer (plist-get run :output-buffer)))
          (display-buffer buffer))))))

(defun attest--drain (run)
  "Read whatever RUN\='s stderr pipe still holds.
One `accept-process-output' can return a partial final batch, so read
until the pipe has nothing left."
  (let ((deadline (+ (float-time) 1)))
    (when-let* ((stderr (plist-get run :stderr-process)))
      (while (and (process-live-p stderr)
                  (< (float-time) deadline)
                  (accept-process-output stderr 0.05))))))

(defun attest--exit-status (run process)
  "Classify PROCESS exit using RUN's backend failure-exit contract."
  (let* ((code (process-exit-status process))
         (props (attest-backend-props (plist-get run :backend)))
         (failed (seq-some (lambda (id)
                             (eq (attest-result-status
                                  (attest-run-result run id)) 'failed))
                           (plist-get run :active-result-ids))))
    (plist-put run :exit-code code)
    (plist-put run :exit-codes (cons code (plist-get run :exit-codes)))
    (cond ((eq (process-status process) 'signal) 'killed)
          ((plist-get run :errors) 'error)
          ((zerop code) 'finished)
          ((and failed (memq code (plist-get props :test-failure-exit-codes))) 'finished)
          (t (attest-report-error run (format "Runner exited %d" code)) 'error))))

(defun attest--sentinel (run)
  "Return a process sentinel for RUN."
  (lambda (process _event)
    (when (and (not (process-live-p process))
               (eq process (plist-get run :process))
               (not (plist-get run :end-time)))
      (attest--drain run)
      (attest--flush-lines run :partial-stdout)
      (attest--flush-lines run :partial-stderr)
      (let ((status (attest--exit-status run process))
            (invocation (plist-get run :invocation)))
        (when invocation
          (setf (attest-invocation-status invocation) status
                (attest-invocation-exit-code invocation) (process-exit-status process)))
        (when-let* ((stderr (plist-get run :stderr-process)))
          (when (process-live-p stderr) (delete-process stderr)))
        (if (and (eq status 'finished) (plist-get run :pending-invocations))
            (condition-case err
                (attest--next-invocation run)
              (error (attest-report-error run (error-message-string err))
                     (attest--finish run 'error)))
          (attest--finish run status))))))

(defun attest--next-invocation (run)
  "Start the next invocation owned by RUN with fresh stream and parser state."
  (let* ((pending (plist-get run :pending-invocations))
         (spec (car pending))
         (state (plist-get spec :state))
         (target (or (plist-get spec :execution-target)
                     (and (listp state)
                          (plist-get state :execution-target))))
         (invocation (attest-invocation-create
                      :spec spec :status 'running :state state
                      :execution-target target))
         (directory (or (plist-get spec :directory) (plist-get run :root)))
         (process-environment (append (plist-get spec :env) process-environment)))
    (plist-put run :pending-invocations (cdr pending))
    (plist-put run :invocation invocation)
    (plist-put run :invocations (cons invocation (plist-get run :invocations)))
    (plist-put run :state state)
    (plist-put run :active-result-ids nil)
    (plist-put run :partial-stdout "")
    (plist-put run :partial-stderr "")
    (plist-put run :directory directory)
    (attest-append-output run (format "\nInvocation: %s\n" (string-join (plist-get spec :command) " ")))
    (attest--spawn run (plist-get spec :command) directory
                   (or (plist-get spec :parse-stream) 'stdout))
    (setf (attest-invocation-process invocation) (plist-get run :process)
          (attest-invocation-stderr invocation) (plist-get run :stderr-process))
    run))

(defconst attest--run-required-keys '(:backend :scope :status)
  "Keys a run plist must already hold before `attest--start' mutates it.
`plist-put' extends a plist in place only when it is non-empty, so a run
missing these would silently lose every key set during the run.")

(defun attest--check-run (run)
  "Signal unless RUN is a plist `attest--start' can safely mutate."
  (unless (and run (plistp run))
    (error "Attest: run must be a non-empty plist, got %S" run))
  (dolist (key attest--run-required-keys)
    (unless (plist-member run key)
      (error "Attest: run is missing %s: %S" key run))))

(defun attest--start (run)
  "Start the process for RUN according to its backend."
  (attest--check-run run)
  (plist-put run :partial-stdout "")
  (plist-put run :partial-stderr "")
  (plist-put run :invocations nil)
  (plist-put run :pending-invocations nil)
  (plist-put run :exit-codes nil)
  (plist-put run :plan-launched nil)
  (plist-put run :start-time (float-time))
  (plist-put run :end-time nil)
  (plist-put run :status 'running)
  (setq attest--last-run run)
  (condition-case err
      (attest--prepare run)
    ((error quit)
     (attest-append-output run (format "\n%s\n" (error-message-string err)))
     (attest--finish run (if (eq (car err) 'quit) 'killed 'error))
     (if (eq (car err) 'quit)
         (signal (car err) (cdr err))
       (user-error "Attest: %s" (error-message-string err))))))

(defun attest--prepare (run)
  "Prepare and spawn RUN inside its exception-safe lifecycle."
  (plist-put run :phase 'preparing)
  (when attest-preparation-timeout
    (plist-put run :preparation-timer
               (run-at-time attest-preparation-timeout nil
                            #'attest--preparation-timeout run)))
  (attest--progress-start run)
  (when attest-save-before-run
    (let ((root (plist-get run :root)))
      (save-some-buffers
       t (lambda ()
           (and buffer-file-name
                (file-in-directory-p buffer-file-name root))))))
  (let ((props (attest-backend-props (plist-get run :backend))))
    (if-let* ((planner (plist-get props :plan)))
        (funcall planner run
                 (lambda (plan)
                   (when (attest-run-active-p run)
                     (attest--launch-plan run plan))))
      (attest--launch-plan run (funcall (plist-get props :command) run)))))

(defun attest--preparation-timeout (run)
  "Fail RUN when backend preparation exceeds its configured timeout."
  (when (and (attest-run-active-p run)
             (eq (plist-get run :phase) 'preparing))
    (attest-report-error run
                         (format "Preparation timed out after %gs"
                                 attest-preparation-timeout))
    (when-let* ((process (plist-get run :process)))
      (when (process-live-p process)
        (set-process-sentinel process #'ignore)
        (delete-process process)))
    (attest--finish run 'error)))

(defun attest--launch-plan (run plan)
  "Launch PLAN's invocations after RUN has completed preparation."
  (when (and (attest-run-active-p run)
             (not (plist-get run :plan-launched)))
    (let* ((specs (attest-validate-invocation-plan plan))
           (spec (car specs))
           (command (plist-get spec :command))
           (directory (or (plist-get spec :directory) (plist-get run :root))))
      (plist-put run :plan-launched t)
      (plist-put run :phase 'running)
      (plist-put run :command command)
      (plist-put run :directory directory)
      (plist-put run :output-buffer (attest--output-buffer run))
      (unless (plist-member spec :state)
        (plist-put spec :state (plist-get run :state)))
      (plist-put run :pending-invocations specs)
      (attest--prune-run-scope run)
      (attest--notify 'attest-run-started-functions run)
      (attest--next-invocation run))))

(defun attest-prepare-command (run command continuation)
  "Run preparation COMMAND for RUN and pass its stdout to CONTINUATION.
The process is owned by RUN and cancellation suppresses its callback."
  (let* ((default-directory (plist-get run :root))
         (stderr (make-pipe-process :name "attest-prepare-stderr" :noquery t
                                    :coding 'utf-8 :sentinel #'ignore
                                    :filter (lambda (_ text) (attest-append-output run text))))
         (chunks nil))
    (plist-put run :stderr-process stderr)
    (plist-put
     run :process
     (make-process
      :name "attest-prepare" :command command :noquery t :coding 'utf-8
      :connection-type 'pipe :stderr stderr
      :filter (lambda (_ text)
                (when (attest-run-active-p run)
                  (push text chunks)))
      :sentinel
      (lambda (process _event)
        (when (and (not (process-live-p process))
                   (not (plist-get run :end-time)))
          (when (process-live-p stderr) (delete-process stderr))
          (when (attest-run-active-p run)
            (condition-case err
                (if (zerop (process-exit-status process))
                    (funcall continuation (apply #'concat (nreverse chunks)))
                  (error "Preparation exited %d" (process-exit-status process)))
              (error (attest-report-error run (error-message-string err))
                     (attest--finish run 'error))))))))
    run))

(defun attest--spawn (run command directory parse-stream)
  "Start COMMAND in DIRECTORY for RUN, parsing PARSE-STREAM.
Stderr gets its own pipe process so the two streams never interleave."
  (let* ((default-directory directory)
         (process-adaptive-read-buffering nil)
         (stderr (make-pipe-process
                  :name "attest-stderr"
                  :noquery t
                  :coding 'utf-8
                  :filter (attest--make-filter run :partial-stderr
                                               (eq parse-stream 'stderr))
                  :sentinel #'ignore)))
    (plist-put run :stderr-process stderr)
    (let ((process (make-process
                    :name "attest"
                    :command command
                    :noquery t
                    :connection-type 'pipe
                    :coding 'utf-8
                    :stderr stderr
                    :filter (attest--make-filter run :partial-stdout
                                                 (eq parse-stream 'stdout))
                    :sentinel (attest--sentinel run))))
      (plist-put run :process process)
      run)))

(defun attest-run (scope &rest props)
  "Run tests for SCOPE in the current buffer's backend.
SCOPE is `file', `project' or `targets'.  PROPS are merged into the
run plist; `targets' expects :targets, a list of position plists each
carrying :id, :type and :file.  Results qualify as targets too."
  (attest-kill)
  (let ((run (apply #'attest--make-run scope props)))
    (when (eq scope 'project)
      (plist-put run :files (attest--project-test-files
                             (plist-get run :backend) (plist-get run :root))))
    (setf (attest-request-files (plist-get run :request))
          (plist-get run :files))
    (attest--start run)))

(defun attest--restart (run &rest props)
  "Start a fresh copy of RUN with PROPS merged in.
Recorded results, backend state and the position index are dropped so
the copy behaves like a first run.  A project run rescans its root, so
a rerun picks up test files added or deleted since."
  (attest-kill)
  (let ((copy (list :status 'pending)))
    (dolist (key '(:backend :scope :file :root :buffer :targets :files))
      (plist-put copy key
                 (if (memq key '(:targets :files))
                     (if (eq key :targets)
                         (mapcar #'copy-sequence (plist-get run key))
                       (copy-sequence (plist-get run key)))
                   (plist-get run key))))
    (while props
      (plist-put copy (pop props) (pop props)))
    (when (eq (plist-get copy :scope) 'project)
      (plist-put copy :files (attest--project-test-files
                              (plist-get copy :backend) (plist-get copy :root))))
    (plist-put copy :request (attest--request-for-run copy))
    (attest--start copy)))

(provide 'attest-run)
;;; attest-run.el ends here
