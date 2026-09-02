;;; neotest.el --- Language-agnostic test runner with pluggable backends -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/nathanscully/emacs-neotest

;; This file is not part of GNU Emacs.

;;; Commentary:

;; neotest runs tests at point, in the current file, or across the
;; project through a per-language backend, and streams structured
;; results to consumers.  Core depends only on Emacs built-ins and
;; requires an Emacs built with tree-sitter.
;;
;; A backend is registered with `neotest-register-backend' and supplies:
;;   :predicate   a function saying whether it owns the current buffer
;;   :test-file-p how to recognise a test file path
;;   :query       a tree-sitter query that finds tests and groups
;;   :command     how to turn a run spec into a process command
;;   :parse-line  how to turn one line of runner output into results
;;
;; Core discovers positions with the query, indexes them per run, and
;; fills each result's :line, :column and :type from the matching
;; position, so backends only have to produce ids and statuses.
;;
;; Consumers subscribe with `neotest-run-started-functions',
;; `neotest-result-functions' and `neotest-run-finished-functions'.
;; neotest-flymake.el, neotest-status.el and neotest-list.el are the
;; consumers shipped with the package; none of them is required.

;;; Code:

(eval-when-compile (require 'subr-x))
(require 'project)
(require 'compile)
(require 'ansi-color)
(require 'treesit)

(unless (treesit-available-p)
  (error "Neotest requires an Emacs built with tree-sitter support"))

(defgroup neotest nil
  "Language-agnostic test runner."
  :group 'tools
  :prefix "neotest-")

(defcustom neotest-output-buffer-name "*neotest*"
  "Name of the buffer receiving raw runner output."
  :type 'string
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-display-output 'on-failure
  "When to display the output buffer after a run.
nil never displays it, t always does, and `on-failure' displays it
only when at least one test failed or the runner exited abnormally."
  :type '(choice
          (const :tag "Never" nil)
          (const :tag "After every run" t)
          (const :tag "Only after failures" on-failure))
  :package-version '(neotest . "0.1.0"))

(defcustom neotest-save-before-run t
  "Save modified buffers under the project root before running."
  :type 'boolean
  :package-version '(neotest . "0.1.0"))

(defvar neotest-run-started-functions nil
  "Abnormal hook called with the run plist when a test process starts.
Consumers such as `neotest-status-mode' use it to mark known tests as
running.  Also see `neotest-run-finished-functions'.")

(defvar neotest-result-functions nil
  "Abnormal hook called with RUN and RESULT as each result arrives.
RESULT is already stored, so `neotest-result' returns it.  Also see
`neotest-run-finished-functions'.")

(defvar neotest-run-finished-functions nil
  "Abnormal hook called with the run plist when the test process exits.
The run's :status is `finished', `killed' or `error' by then, and
`neotest-run-results' returns everything it recorded.")

;;;; Backends

(defvar neotest--backends nil
  "Alist of (NAME . PROPS) registered backends, most recent first.")

(defun neotest-register-backend (name &rest props)
  "Register backend NAME with PROPS.
PROPS is a plist with these keys:

:predicate    Function of no arguments returning non-nil when the
              backend owns the current buffer.
:test-file-p  Function of a file name returning non-nil for test files.
:query        Cons (LANGUAGE . QUERY), or a function of a file name
              returning one.  QUERY is a tree-sitter query whose captures
              are @test.definition, @test.name, @namespace.definition
              and @namespace.name; see `neotest-file-positions'.
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
      (error "Neotest: no backend named `%s'" name)))

(defun neotest-backend-for-buffer (&optional buffer)
  "Return the name of the backend owning BUFFER, or nil."
  (with-current-buffer (or buffer (current-buffer))
    (car (seq-find (lambda (entry)
                     (funcall (plist-get (cdr entry) :predicate)))
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
      (user-error "Neotest: no backend for `%s'" (buffer-name))))

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

(defun neotest--ensure-language (language)
  "Make sure the grammar for LANGUAGE is installed, or signal a user error."
  (unless (if (fboundp 'treesit-ensure-installed)
              (treesit-ensure-installed language)
            (treesit-language-available-p language))
    (user-error "Neotest: no tree-sitter grammar for %s; run `treesit-install-language-grammar'"
                language)))

(defun neotest--query (backend file)
  "Return the (LANGUAGE . QUERY) of BACKEND for FILE."
  (let ((query (plist-get (neotest-backend-props backend) :query)))
    (unless query (error "Neotest: backend `%s' has no :query" backend))
    (if (functionp query) (funcall query file) query)))

(defun neotest--unescape (text)
  "Return the character sequence the escape TEXT stands for.
Backslash escapes in JavaScript and Python string literals are close
enough to Lisp's that the Lisp reader decodes them; TEXT is returned
as is when it cannot."
  (condition-case nil
      (car (read-from-string (concat "\"" text "\"")))
    (error text)))

(defun neotest--name-text (node)
  "Return the test name expressed by NODE.
String literals lose their quotes and decode their escapes; template
strings are concatenated; anything else is returned as source text."
  (pcase (treesit-node-type node)
    ("string"
     (mapconcat (lambda (child)
                  (if (equal (treesit-node-type child) "escape_sequence")
                      (neotest--unescape (treesit-node-text child t))
                    (treesit-node-text child t)))
                (treesit-filter-child
                 node (lambda (child)
                        (member (treesit-node-type child)
                                '("string_fragment" "escape_sequence"))))
                ""))
    ("template_string"
     (mapconcat (lambda (child) (treesit-node-text child t))
                (treesit-filter-child node (lambda (child) (treesit-node-check child 'named)))
                ""))
    (_ (treesit-node-text node t))))

(defun neotest--node-position (kind definition name file)
  "Return an unlinked position plist of KIND for DEFINITION in FILE.
NAME is the node holding the test's name."
  (list :type kind
        :name (neotest--name-text name)
        :file file
        :line (line-number-at-pos (treesit-node-start definition) t)
        :column (1+ (save-excursion
                      (goto-char (treesit-node-start definition))
                      (current-column)))
        :beg (treesit-node-start definition)
        :end (treesit-node-end definition)))

(defun neotest--capture-entry (name node)
  "Return the pairing-sweep entry for capture NAME on NODE, or nil.
Only the definition and name captures participate in pairing;
auxiliary captures used by query predicates are dropped."
  (when-let* ((kind (cond ((memq name '(test.definition test.name)) 'test)
                          ((memq name '(namespace.definition namespace.name)) 'namespace))))
    (list (treesit-node-start node) (treesit-node-end node) kind
          (if (memq name '(test.definition namespace.definition)) 'definition 'name)
          node)))

(defun neotest--capture-entry< (a b)
  "Return non-nil when capture entry A sorts before B in the sweep.
Entries order by start position; at the same start a definition
precedes a name and a wider node precedes a narrower one."
  (cond ((/= (nth 0 a) (nth 0 b)) (< (nth 0 a) (nth 0 b)))
        ((not (eq (nth 3 a) (nth 3 b))) (eq (nth 3 a) 'definition))
        (t (> (nth 1 a) (nth 1 b)))))

(defun neotest--capture-positions (captures file)
  "Return unlinked position plists for CAPTURES in FILE.
CAPTURES is the flat list `treesit-query-capture' returns.  A
position pairs each name capture with the innermost definition
capture of the same kind whose range contains it, so discovery does
not depend on the grouped results Emacs 31 added.  Overlapping
patterns can capture one node several times; duplicate entries
collapse into a single position."
  (let ((entries nil)
        (positions nil)
        (previous nil)
        (stacks (list (cons 'test nil) (cons 'namespace nil))))
    (pcase-dolist (`(,name . ,node) captures)
      (when-let* ((entry (neotest--capture-entry name node)))
        (push entry entries)))
    (dolist (entry (sort (nreverse entries) #'neotest--capture-entry<))
      (unless (equal (take 4 entry) (and previous (take 4 previous)))
        (pcase-let* ((`(,beg ,_end ,kind ,role ,node) entry)
                     (stack (assq kind stacks)))
          (while (and (cdr stack) (<= (treesit-node-end (cadr stack)) beg))
            (setcdr stack (cddr stack)))
          (if (eq role 'definition)
              (setcdr stack (cons node (cdr stack)))
            (when (cdr stack)
              (push (neotest--node-position kind (cadr stack) node file) positions)))))
      (setq previous entry))
    (nreverse positions)))

(defun neotest--link-positions (positions file)
  "Assign :parent-id and :id to POSITIONS from FILE by range containment.
POSITIONS must be sorted by :beg ascending."
  (let (stack)
    (dolist (pos positions)
      (while (and stack
                  (>= (plist-get pos :beg) (plist-get (car stack) :end)))
        (pop stack))
      (let* ((parent (car stack))
             (names (append (and parent (plist-get parent :names))
                            (list (plist-get pos :name)))))
        (plist-put pos :parent-id (and parent (plist-get parent :id)))
        (plist-put pos :names names)
        (plist-put pos :id (apply #'neotest-make-id file names))
        (when (eq (plist-get pos :type) 'namespace)
          (push pos stack))))
    positions))

(defun neotest--buffer-positions (file language query)
  "Return the positions QUERY for LANGUAGE finds in the current buffer.
FILE names the buffer's file in the resulting ids."
  (neotest--ensure-language language)
  (let* ((root (treesit-parser-root-node (treesit-parser-create language)))
         (positions (neotest--capture-positions
                     (treesit-query-capture root query) file)))
    (neotest--link-positions
     (sort positions (lambda (a b) (< (plist-get a :beg) (plist-get b :beg))))
     file)))

(defun neotest-positions (&optional buffer)
  "Return the test positions discovered in BUFFER.
Each position is a plist with :id, :type (`test' or `namespace'),
:name, :file, :line, :column, :beg, :end and :parent-id."
  (with-current-buffer (or buffer (current-buffer))
    (let* ((backend (neotest--require-backend))
           (file (or (and buffer-file-name (expand-file-name buffer-file-name))
                     (buffer-name)))
           (query (neotest--query backend file)))
      (neotest--buffer-positions file (car query) (cdr query)))))

(defun neotest-file-positions (file &optional backend)
  "Return the positions in FILE using BACKEND's query.
BACKEND defaults to the first whose :test-file-p accepts FILE.  A live
buffer visiting FILE is used when there is one; otherwise the file is
parsed in a temporary buffer.  Returns nil when FILE cannot be read."
  (let* ((file (expand-file-name file))
         (backend (or backend (neotest-backend-for-file file)
                      (user-error "Neotest: no backend for `%s'" file)))
         (query (neotest--query backend file)))
    (cond
     ((find-buffer-visiting file)
      (with-current-buffer (find-buffer-visiting file)
        (neotest--buffer-positions file (car query) (cdr query))))
     ((file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (neotest--buffer-positions file (car query) (cdr query)))))))

(defun neotest-run-file-positions (run file)
  "Return the positions of FILE for RUN, parsing FILE at most once per run."
  (let ((index (or (plist-get run :index)
                   (let ((table (make-hash-table :test 'equal)))
                     (plist-put run :index table)
                     table)))
        (file (expand-file-name file)))
    (let ((cached (gethash file index 'missing)))
      (if (eq cached 'missing)
          (puthash file (neotest-file-positions file (plist-get run :backend)) index)
        cached))))

(defun neotest-run-files (run)
  "Return the files RUN covers.
A `project' run lists its :files, a `targets' run the files of its
:targets, and a `file' run its :file."
  (pcase (plist-get run :scope)
    ('project (plist-get run :files))
    ('targets (delete-dups (mapcar (lambda (target) (plist-get target :file))
                                   (plist-get run :targets))))
    (_ (list (plist-get run :file)))))

(defun neotest-run-positions (run)
  "Return every position in the files RUN covers."
  (mapcan (lambda (file) (copy-sequence (neotest-run-file-positions run file)))
          (neotest-run-files run)))

(defun neotest-run-position (run id)
  "Return the position with ID discovered for RUN, or nil."
  (seq-find (lambda (pos) (equal (plist-get pos :id) id))
            (neotest-run-file-positions run (neotest-id-file id))))

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
  "Return the results recorded during RUN, in arrival order.
Ids reported more than once, such as parametrized cases, appear once."
  (mapcar #'neotest-result (delete-dups (reverse (plist-get run :result-ids)))))

(defun neotest-run-failed-results (run)
  "Return the failed results of RUN."
  (seq-filter (lambda (result) (eq (plist-get result :status) 'failed))
              (neotest-run-results run)))

(defun neotest--record (run result)
  "Store RESULT from RUN and notify consumers.
When discovery knows the test, its :line, :column and :type come from
the position, so the runner's own notion of where a test lives is only
a fallback."
  (let ((id (plist-get result :id)))
    (unless id (error "Neotest: result without :id: %S" result))
    (when-let* ((pos (and (plist-get run :backend) (neotest-run-position run id))))
      (plist-put result :line (plist-get pos :line))
      (plist-put result :column (plist-get pos :column))
      (unless (plist-get result :type)
        (plist-put result :type (plist-get pos :type))))
    (unless (plist-get result :type) (plist-put result :type 'test))
    (puthash id result neotest--results)
    (plist-put run :result-ids (cons id (plist-get run :result-ids)))
    (run-hook-with-args 'neotest-result-functions run result)))

;;;; Runs

(defun neotest--project-test-files (backend root)
  "Return the test files under ROOT accepted by BACKEND.
ROOT is the backend's root, which can be a package inside a larger
`project-current' checkout; files outside ROOT are dropped."
  (let ((pred (plist-get (neotest-backend-props backend) :test-file-p))
        (project (project-current nil root)))
    (unless pred (error "Neotest: backend `%s' has no :test-file-p" backend))
    (seq-filter (lambda (file)
                  (and (string-prefix-p root (expand-file-name file))
                       (funcall pred file)))
                (if project (project-files project) nil))))

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
  (run-hook-with-args 'neotest-run-finished-functions run)
  (let* ((results (neotest-run-results run))
         (failed (length (neotest-run-failed-results run)))
         (passed (seq-count (lambda (r) (eq (plist-get r :status) 'passed)) results))
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
    (unless command (error "Neotest: backend `%s' produced no command" (plist-get run :backend)))
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
    (run-hook-with-args 'neotest-run-started-functions run)
    (condition-case err
        (neotest--spawn run command directory parse-stream)
      (error
       (neotest-append-output run (format "\n%s\n" (error-message-string err)))
       (neotest--finish run 'error)
       (signal (car err) (cdr err))))))

(defun neotest--spawn (run command directory parse-stream)
  "Start COMMAND in DIRECTORY for RUN, parsing PARSE-STREAM.
Stderr gets its own pipe process so the two streams never interleave."
  (let* ((default-directory directory)
         (process-adaptive-read-buffering nil)
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
    run))

(defun neotest-run (scope &rest props)
  "Run tests for SCOPE in the current buffer's backend.
SCOPE is `file', `project' or `targets'.  PROPS are merged into the
run plist; `targets' expects :targets, a list of position plists each
carrying :id, :type and :file.  Results qualify as targets too."
  (neotest-kill)
  (let ((run (apply #'neotest--make-run scope props)))
    (when (eq scope 'project)
      (plist-put run :files (neotest--project-test-files
                             (plist-get run :backend) (plist-get run :root))))
    (neotest--start run)))

(defun neotest--restart (run &rest props)
  "Start a fresh copy of RUN with PROPS merged in.
Recorded results, backend state and the position index are dropped so
the copy behaves like a first run."
  (neotest-kill)
  (let ((copy (copy-sequence run)))
    (dolist (key '(:result-ids :state :index))
      (plist-put copy key nil))
    (while props
      (plist-put copy (pop props) (pop props)))
    (neotest--start copy)))

;;;; Commands

;;;###autoload
(defun neotest-run-at-point ()
  "Run the test or namespace at point."
  (interactive)
  (let ((pos (or (neotest-position-at-point)
                 (user-error "Neotest: no test at point"))))
    (neotest-run 'targets :targets (list pos))))

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
  (neotest--restart
   (or neotest--last-run (user-error "Neotest: nothing to rerun"))))

;;;###autoload
(defun neotest-rerun-failed ()
  "Run only the tests that failed in the previous run."
  (interactive)
  (let* ((last (or neotest--last-run (user-error "Neotest: nothing to rerun")))
         (failed (seq-filter (lambda (r) (eq (plist-get r :type) 'test))
                             (neotest-run-failed-results last))))
    (unless failed (user-error "Neotest: no failed tests in last run"))
    (neotest--restart last :scope 'targets :targets failed)))

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

(defvar-keymap neotest-prefix-map
  :doc "Keymap for neotest commands.
Neotest binds no global keys.  Bind this map to a prefix of your own,
for example (keymap-global-set \"C-c t\" neotest-prefix-map)."
  "t" #'neotest-run-at-point
  "f" #'neotest-run-file
  "p" #'neotest-run-project
  "r" #'neotest-rerun-last
  "x" #'neotest-rerun-failed
  "k" #'neotest-kill
  "o" #'neotest-show-output)

(provide 'neotest)
;;; neotest.el ends here
