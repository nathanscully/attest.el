;;; neotest.el --- Language-agnostic test runner with pluggable backends -*- lexical-binding: t; -*-

;; Author: Nathan Scully
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/nathanscully/emacs-neotest

;; This file is not part of GNU Emacs.

;;; Commentary:

;; neotest runs tests at point, in the current file, or across the
;; project through a per-language backend, and streams structured
;; results to consumers.  Core depends only on Emacs built-ins.
;;
;; A backend is registered with `neotest-register-backend' and supplies:
;;   :predicate   how to recognise a buffer it owns
;;   :test-file-p how to recognise a test file path
;;   :query       a treesit query for test discovery (see neotest-treesit.el)
;;   :command     how to turn a run spec into a process command
;;   :parse-line  how to turn one line of runner output into results
;;
;; Consumers subscribe with `neotest-run-started-hook',
;; `neotest-result-hook' and `neotest-run-finished-hook'.
;; neotest-flymake.el, neotest-status.el and neotest-list.el are the
;; consumers shipped with the package; none of them is required.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'project)
(require 'compile)
(require 'ansi-color)

(defgroup neotest nil
  "Language-agnostic test runner."
  :group 'tools
  :prefix "neotest-")

(defcustom neotest-output-buffer-name "*neotest*"
  "Name of the buffer receiving raw runner output."
  :type 'string)

(defcustom neotest-display-output 'on-failure
  "When to display the output buffer after a run.
nil never displays it, t always does, and `on-failure' displays it
only when at least one test failed."
  :type '(choice (const nil) (const t) (const on-failure)))

(defcustom neotest-save-before-run t
  "Save modified buffers under the project root before running."
  :type 'boolean)

(defvar neotest-run-started-hook nil
  "Hook run with the run plist when a test process starts.")

(defvar neotest-result-hook nil
  "Hook run with RUN and RESULT as each result arrives.")

(defvar neotest-run-finished-hook nil
  "Hook run with the run plist when the test process exits.")

;;;; Backends

(defvar neotest--backends nil
  "Alist of (NAME . PROPS) registered backends, most recent first.")

(defun neotest-register-backend (name &rest props)
  "Register backend NAME with PROPS.
PROPS is a plist with these keys:

:predicate    A major-mode symbol matched with `derived-mode-p', a
              regexp matched against the buffer file name, or a
              function of no arguments returning non-nil in buffers the
              backend owns.
:test-file-p  Function of a file name returning non-nil for test files.
:query        Cons (LANGUAGE . QUERY) for `neotest-treesit-positions',
              or a function of no arguments returning such a cons.
:positions    Optional function of a buffer returning positions, used
              instead of :query.
:command      Function of a run plist returning a plist with :command
              \(argv list), :directory and optionally :env (list of
              \"VAR=VALUE\" strings) and :parse-stream (`stdout' or
              `stderr', default `stdout').
:parse-line   Function of RUN and one output LINE from the parse
              stream, returning a result plist, a list of them, or nil.
:root         Optional function of a file returning the project root."
  (setf (alist-get name neotest--backends) props)
  name)

(defun neotest-backend-props (name)
  "Return the props plist of backend NAME."
  (or (alist-get name neotest--backends)
      (error "Neotest: no backend named %s" name)))

(defun neotest--predicate-matches-p (predicate)
  "Return non-nil when PREDICATE matches the current buffer."
  (cond
   ((functionp predicate) (funcall predicate))
   ((symbolp predicate) (derived-mode-p predicate))
   ((stringp predicate) (and buffer-file-name
                             (string-match-p predicate buffer-file-name)))
   (t (error "Neotest: invalid predicate %S" predicate))))

(defun neotest-backend-for-buffer (&optional buffer)
  "Return the name of the backend owning BUFFER, or nil."
  (with-current-buffer (or buffer (current-buffer))
    (car (seq-find (lambda (entry)
                     (neotest--predicate-matches-p
                      (plist-get (cdr entry) :predicate)))
                   neotest--backends))))

(defun neotest-backend-for-file (file)
  "Return the name of the first backend whose :test-file-p accepts FILE."
  (car (seq-find (lambda (entry)
                   (when-let* ((pred (plist-get (cdr entry) :test-file-p)))
                     (funcall pred file)))
                 neotest--backends)))

(defun neotest--require-backend ()
  "Return the backend for the current buffer or signal a user error."
  (or (neotest-backend-for-buffer)
      (user-error "Neotest: no backend for %s" (buffer-name))))

;;;; Ids and positions

(defconst neotest-id-separator "::"
  "Separator between the file and the names in a position id.")

(defun neotest-make-id (file &rest names)
  "Return the id for the test at FILE nested under NAMES."
  (string-join (cons file names) neotest-id-separator))

(defun neotest-id-file (id)
  "Return the file component of ID."
  (car (split-string id neotest-id-separator)))

(defun neotest-id-names (id)
  "Return the list of names in ID, outermost first."
  (cdr (split-string id neotest-id-separator)))

(defun neotest-project-root (&optional file)
  "Return the project root for FILE, defaulting to the current buffer's."
  (let* ((file (or file buffer-file-name default-directory))
         (backend (neotest-backend-for-buffer))
         (root-fn (and backend (plist-get (neotest-backend-props backend) :root))))
    (file-name-as-directory
     (expand-file-name
      (or (and root-fn (funcall root-fn file))
          (when-let* ((project (project-current nil (file-name-directory file))))
            (project-root project))
          (file-name-directory file))))))

(defun neotest-positions (&optional buffer)
  "Return the test positions discovered in BUFFER.
Each position is a plist with :id, :type (`test' or `namespace'),
:name, :file, :line, :column, :beg, :end and :parent-id."
  (with-current-buffer (or buffer (current-buffer))
    (let* ((backend (neotest--require-backend))
           (props (neotest-backend-props backend)))
      (cond
       ((plist-get props :positions)
        (funcall (plist-get props :positions) (current-buffer)))
       ((plist-get props :query)
        (require 'neotest-treesit)
        (let ((query (plist-get props :query)))
          (when (functionp query) (setq query (funcall query)))
          (neotest-treesit-positions (current-buffer) (car query) (cdr query))))
       (t (user-error "Neotest: backend %s cannot discover tests" backend))))))

(declare-function neotest-treesit-positions "neotest-treesit")

(defun neotest-position-at-point (&optional positions)
  "Return the innermost position in POSITIONS containing point.
Tests win over namespaces of equal extent.  POSITIONS defaults to
`neotest-positions'."
  (let ((pt (point))
        best)
    (dolist (pos (or positions (neotest-positions)))
      (when (and (<= (plist-get pos :beg) pt)
                 (<= pt (plist-get pos :end))
                 (or (null best)
                     (> (plist-get pos :beg) (plist-get best :beg))
                     (and (= (plist-get pos :beg) (plist-get best :beg))
                          (eq (plist-get pos :type) 'test))))
        (setq best pos)))
    best))

;;;; Results

(defvar neotest--results (make-hash-table :test 'equal)
  "Latest known result for every test id.")

(defvar neotest--last-run nil
  "The most recent run plist.")

(defun neotest-result (id)
  "Return the latest result recorded for ID."
  (gethash id neotest--results))

(defun neotest-results-for-file (file)
  "Return the latest results whose test lives in FILE."
  (let ((file (expand-file-name file))
        acc)
    (maphash (lambda (_id result)
               (when-let* ((result-file (plist-get result :file)))
                 (when (string= (expand-file-name result-file) file)
                   (push result acc))))
             neotest--results)
    (nreverse acc)))

(defun neotest-last-run ()
  "Return the most recent run plist."
  neotest--last-run)

(defun neotest-run-results (run)
  "Return the results recorded during RUN, in arrival order."
  (mapcar #'neotest-result (reverse (plist-get run :result-ids))))

(defun neotest-run-failed-results (run)
  "Return the failed results of RUN."
  (seq-filter (lambda (result) (eq (plist-get result :status) 'failed))
              (neotest-run-results run)))

(defun neotest--record (run result)
  "Store RESULT from RUN and notify consumers."
  (let ((id (plist-get result :id)))
    (unless id (error "Neotest: result without :id: %S" result))
    (puthash id result neotest--results)
    (plist-put run :result-ids (cons id (plist-get run :result-ids)))
    (run-hook-with-args 'neotest-result-hook run result)))

;;;; Runs

(defun neotest--project-test-files (backend root)
  "Return the test files under ROOT accepted by BACKEND."
  (let ((pred (plist-get (neotest-backend-props backend) :test-file-p))
        (project (project-current nil root)))
    (unless pred (user-error "Neotest: backend %s has no :test-file-p" backend))
    (seq-filter pred (if project (project-files project) nil))))

(defun neotest--make-run (scope &rest props)
  "Build a run plist for SCOPE from the current buffer, merging PROPS."
  (let* ((backend (neotest--require-backend))
         (file (and buffer-file-name (expand-file-name buffer-file-name)))
         (root (neotest-project-root file)))
    (append (list :backend backend
                  :scope scope
                  :file file
                  :root root
                  :buffer (current-buffer)
                  :status 'pending
                  :result-ids nil
                  :state nil)
            props)))

(defun neotest--output-buffer (run)
  "Return the output buffer for RUN, resetting its contents."
  (let ((buffer (get-buffer-create neotest-output-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (unless (derived-mode-p 'neotest-output-mode)
          (neotest-output-mode))
        (setq default-directory (plist-get run :directory))
        (insert (propertize
                 (format "%s\n\n" (string-join (plist-get run :command) " "))
                 'face 'shadow))))
    buffer))

(define-derived-mode neotest-output-mode special-mode "neotest-out"
  "Major mode for raw neotest runner output."
  (setq-local compilation-error-regexp-alist
              (cons 'neotest-file-url compilation-error-regexp-alist))
  (compilation-minor-mode 1))

(add-to-list 'compilation-error-regexp-alist-alist
             '(neotest-file-url
               "(?\\(?:file://\\)?\\(/[^:()[:space:]]+\\):\\([0-9]+\\):\\([0-9]+\\))?"
               1 2 3))

(defun neotest-append-output (run string)
  "Append STRING to RUN's output buffer.
Backends whose runner embeds human-readable output inside structured
events call this to surface it."
  (when-let* ((buffer (plist-get run :output-buffer)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (at-end (= (point) (point-max))))
          (save-excursion
            (goto-char (point-max))
            (insert (ansi-color-apply string)))
          (when at-end (goto-char (point-max))))))))

(defun neotest--feed-lines (run key string)
  "Split STRING into lines, buffering a partial line under KEY in RUN.
Complete lines go to the backend's :parse-line."
  (let* ((pending (concat (plist-get run key) string))
         (lines (split-string pending "\n"))
         (parse (plist-get (neotest-backend-props (plist-get run :backend))
                           :parse-line)))
    (plist-put run key (car (last lines)))
    (dolist (line (butlast lines))
      (neotest--parse-line run parse line))))

(defun neotest--parse-line (run parse line)
  "Feed LINE to PARSE for RUN and record whatever it returns.
A backend error is reported and the line dropped, so one bad line
cannot stop the run."
  (condition-case err
      (let ((results (funcall parse run line)))
        (when (and results (keywordp (car results)))
          (setq results (list results)))
        (dolist (result results)
          (neotest--record run result)))
    (error (message "Neotest: %s backend failed on %S: %s"
                    (plist-get run :backend) line (error-message-string err)))))

(defun neotest--flush-lines (run key)
  "Parse a trailing partial line buffered under KEY in RUN."
  (let ((rest (plist-get run key)))
    (when (and rest (not (string-empty-p rest)))
      (plist-put run key "")
      (neotest--parse-line
       run (plist-get (neotest-backend-props (plist-get run :backend)) :parse-line)
       rest))))

(defun neotest--make-filter (run key parse-p)
  "Return a process filter for RUN.
KEY names the partial-line slot.  When PARSE-P, lines are parsed;
otherwise they only go to the output buffer."
  (lambda (_process string)
    (if parse-p
        (neotest--feed-lines run key string)
      (neotest-append-output run string))))

(defun neotest--finish (run status)
  "Mark RUN finished with STATUS, notify consumers and report a summary."
  (neotest--flush-lines run :partial-stdout)
  (neotest--flush-lines run :partial-stderr)
  (plist-put run :status status)
  (plist-put run :end-time (float-time))
  (run-hook-with-args 'neotest-run-finished-hook run)
  (let* ((results (neotest-run-results run))
         (failed (length (neotest-run-failed-results run)))
         (passed (cl-count 'passed results :key (lambda (r) (plist-get r :status))))
         (skipped (- (length results) failed passed)))
    (message "neotest: %d passed, %d failed, %d skipped (%s in %.1fs)"
             passed failed skipped status
             (- (plist-get run :end-time) (plist-get run :start-time)))
    (when (or (eq neotest-display-output t)
              (and (eq neotest-display-output 'on-failure)
                   (or (> failed 0) (eq status 'error))))
      (display-buffer (plist-get run :output-buffer)))))

(defun neotest--sentinel (run)
  "Return a process sentinel for RUN."
  (lambda (process event)
    (unless (process-live-p process)
      (let ((stderr (plist-get run :stderr-process)))
        (when (and stderr (process-live-p stderr))
          (accept-process-output stderr 0.1)))
      (neotest--finish
       run
       (cond ((eq (process-status process) 'signal) 'killed)
             ((or (string-prefix-p "finished" event)
                  (plist-get run :result-ids))
              'finished)
             (t 'error))))))

(defun neotest--start (run)
  "Start the process for RUN according to its backend."
  (let* ((props (neotest-backend-props (plist-get run :backend)))
         (spec (funcall (plist-get props :command) run))
         (command (plist-get spec :command))
         (directory (or (plist-get spec :directory) (plist-get run :root)))
         (parse-stream (or (plist-get spec :parse-stream) 'stdout))
         (process-environment (append (plist-get spec :env) process-environment)))
    (unless command (user-error "Neotest: backend produced no command"))
    (plist-put run :command command)
    (plist-put run :directory directory)
    (plist-put run :partial-stdout "")
    (plist-put run :partial-stderr "")
    (plist-put run :start-time (float-time))
    (plist-put run :status 'running)
    (plist-put run :output-buffer (neotest--output-buffer run))
    (when neotest-save-before-run
      (let ((root (plist-get run :root)))
        (save-some-buffers
         t (lambda ()
             (and buffer-file-name
                  (string-prefix-p root (expand-file-name buffer-file-name)))))))
    (setq neotest--last-run run)
    (run-hook-with-args 'neotest-run-started-hook run)
    (condition-case err
        (neotest--spawn run command directory parse-stream)
      (error
       (neotest-append-output run (format "\n%s\n" (error-message-string err)))
       (neotest--finish run 'error)
       (signal (car err) (cdr err))))))

(defun neotest--spawn (run command directory parse-stream)
  "Start COMMAND in DIRECTORY for RUN, parsing PARSE-STREAM."
  (progn
    (let* ((default-directory directory)
           (stderr (make-pipe-process
                    :name "neotest-stderr"
                    :noquery t
                    :filter (neotest--make-filter run :partial-stderr
                                                  (eq parse-stream 'stderr))
                    :sentinel #'ignore))
           (process (make-process
                     :name "neotest"
                     :command command
                     :noquery t
                     :connection-type 'pipe
                     :stderr stderr
                     :filter (neotest--make-filter run :partial-stdout
                                                   (eq parse-stream 'stdout))
                     :sentinel (neotest--sentinel run))))
      (plist-put run :process process)
      (plist-put run :stderr-process stderr)
      (message "neotest: %s" (string-join command " "))
      run)))

(defun neotest-run (scope &rest props)
  "Run tests for SCOPE in the current buffer's backend.
SCOPE is `test', `namespace', `file', `project' or `results'.  PROPS
are merged into the run plist; `test' and `namespace' expect
:position, `results' expects :results."
  (neotest-kill)
  (let ((run (apply #'neotest--make-run scope props)))
    (when (eq scope 'project)
      (plist-put run :files (neotest--project-test-files
                             (plist-get run :backend) (plist-get run :root))))
    (neotest--start run)))

;;;; Commands

;;;###autoload
(defun neotest-run-at-point ()
  "Run the test or namespace at point."
  (interactive)
  (let ((pos (or (neotest-position-at-point)
                 (user-error "Neotest: no test at point"))))
    (neotest-run (plist-get pos :type) :position pos)))

;;;###autoload
(defun neotest-run-file ()
  "Run every test in the current file."
  (interactive)
  (unless buffer-file-name (user-error "Neotest: buffer has no file"))
  (neotest-run 'file))

;;;###autoload
(defun neotest-run-project ()
  "Run every test file in the current project."
  (interactive)
  (neotest-run 'project))

;;;###autoload
(defun neotest-rerun-last ()
  "Run the previous run again."
  (interactive)
  (let ((last (or neotest--last-run (user-error "Neotest: nothing to rerun"))))
    (neotest-kill)
    (let ((run (copy-sequence last)))
      (plist-put run :result-ids nil)
      (plist-put run :state nil)
      (neotest--start run))))

;;;###autoload
(defun neotest-rerun-failed ()
  "Run only the tests that failed in the previous run."
  (interactive)
  (let* ((last (or neotest--last-run (user-error "Neotest: nothing to rerun")))
         (failed (seq-filter (lambda (r) (eq (plist-get r :type) 'test))
                             (neotest-run-failed-results last))))
    (unless failed (user-error "Neotest: no failed tests in last run"))
    (neotest-kill)
    (let ((run (copy-sequence last)))
      (plist-put run :scope 'results)
      (plist-put run :results failed)
      (plist-put run :result-ids nil)
      (plist-put run :state nil)
      (neotest--start run))))

;;;###autoload
(defun neotest-kill ()
  "Kill the running test process, if any."
  (interactive)
  (when-let* ((run neotest--last-run)
              (process (plist-get run :process)))
    (when (process-live-p process)
      (set-process-sentinel process #'ignore)
      (delete-process process)
      (neotest--finish run 'killed))))

;;;###autoload
(defun neotest-show-output ()
  "Display the raw output of the last run."
  (interactive)
  (if-let* ((buffer (get-buffer neotest-output-buffer-name)))
      (pop-to-buffer buffer)
    (user-error "Neotest: no output yet")))

(defvar-keymap neotest-command-map
  :doc "Keymap for neotest commands; bind it to a prefix."
  "t" #'neotest-run-at-point
  "f" #'neotest-run-file
  "p" #'neotest-run-project
  "r" #'neotest-rerun-last
  "x" #'neotest-rerun-failed
  "k" #'neotest-kill
  "o" #'neotest-show-output)

(provide 'neotest)
;;; neotest.el ends here
