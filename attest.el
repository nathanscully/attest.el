;;; attest.el --- Language-agnostic test runner with pluggable backends -*- lexical-binding: t; -*-

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

;; attest runs tests at point, in the current file, or across the
;; project through a per-language backend, and streams structured
;; results to consumers.  Core depends only on Emacs built-ins and
;; requires an Emacs built with tree-sitter.
;;
;; A backend is registered with `attest-register-backend' and supplies:
;;   :predicate   a function saying whether it owns the current buffer
;;   :test-file-p how to recognise a test file path
;;   :project-p   optional; non-nil when the buffer sits in this
;;                backend's project, whether or not it is a test file
;;   :query       a tree-sitter query that finds tests and groups
;;   :command     how to turn a run spec into a process command
;;   :parse-line  how to turn one line of runner output into results
;;
;; Core discovers positions with the query, indexes them per run, and
;; fills each result's :line, :column and :type from the matching
;; position, so backends only have to produce ids and statuses.
;;
;; Consumers subscribe with `attest-run-started-functions',
;; `attest-result-functions' and `attest-run-finished-functions'.
;; attest-flymake.el, attest-status.el and attest-list.el are the
;; consumers shipped with the package; none of them is required.

;;; Code:

(eval-when-compile (require 'subr-x))
(require 'project)
(require 'compile)
(require 'ansi-color)
(require 'treesit)

(unless (treesit-available-p)
  (error "Attest requires an Emacs built with tree-sitter support"))

(defgroup attest nil
  "Language-agnostic test runner."
  :group 'tools
  :prefix "attest-")

(defcustom attest-output-buffer-name "*attest*"
  "Name of the buffer receiving raw runner output."
  :type 'string
  :package-version '(attest . "0.1.0"))

(defcustom attest-display-output 'on-failure
  "When to display the output buffer after a run.
nil never displays it, t always does, and `on-failure' displays it
only when at least one test failed or the runner exited abnormally."
  :type '(choice
          (const :tag "Never" nil)
          (const :tag "After every run" t)
          (const :tag "Only after failures" on-failure))
  :package-version '(attest . "0.1.0"))

(defcustom attest-save-before-run t
  "Save modified buffers under the project root before running."
  :type 'boolean
  :package-version '(attest . "0.1.0"))

(defcustom attest-project-skip-directories
  '("node_modules" ".git" "target" "dist" "build" ".venv" "__pycache__")
  "Directory names skipped when walking a project root for test files.
Only consulted for a root `project-current' knows nothing about; a
project supplies its own file list."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defvar attest-run-started-functions nil
  "Abnormal hook called with the run plist when a test process starts.
Consumers such as `attest-status-mode' use it to mark known tests as
running.  Also see `attest-run-finished-functions'.

Called from the run's own command, so a function here must be fast and
must not call `attest-run', which would kill the run about to start.")

(defvar attest-result-functions nil
  "Abnormal hook called with RUN and RESULT as each result arrives.
RESULT is already stored, so `attest-result' returns it.  Also see
`attest-run-finished-functions'.

Called from the process filter, so a function here must be fast: slow
work blocks reading the runner\='s output.  It must not call
`attest-run', which would kill the run being reported.")

(defvar attest-run-finished-functions nil
  "Abnormal hook called with the run plist when the test process exits.
The run\='s :status is `finished', `killed' or `error' by then, and
`attest-run-results' returns everything it recorded.

A function here may start work of its own, as `attest-flymake-mode'
does, but must not call `attest-run' unconditionally: that reruns on
every finish and never terminates.")

;;;; Backends

(defvar attest--backends nil
  "Alist of (NAME . PROPS) registered backends, most recent first.")

(defun attest-register-backend (name &rest props)
  "Register backend NAME with PROPS.
PROPS is a plist with these keys:

:predicate    Function of no arguments returning non-nil when the
              backend owns the current buffer.
:test-file-p  Function of a file name returning non-nil for test files.
:project-p    Optional function of no arguments returning non-nil when
              the current buffer sits in this backend\='s project, test
              file or not.  Used to resolve a `project' run; falls back
              to :predicate.
:query        Cons (LANGUAGE . QUERY), or a function of a file name
              returning one.  QUERY is a tree-sitter query whose captures
              are @test.definition, @test.name, @namespace.definition
              and @namespace.name; see `attest-file-positions'.
:command      Function of a run plist returning a plist with :command
              \(argv list), :directory and optionally :env (list of
              \"VAR=VALUE\" strings) and :parse-stream (`stdout' or
              `stderr', default `stdout').
:parse-line   Function of RUN and one output LINE from the parse
              stream, returning a result plist, a list of them, or nil.
:root         Optional function of a file returning the project root."
  (setf (alist-get name attest--backends) props)
  name)

(defun attest-backend-props (name)
  "Return the props plist of backend NAME."
  (or (alist-get name attest--backends)
      (error "Attest: no backend named `%s'" name)))

(defun attest-backend-for-buffer (&optional buffer)
  "Return the name of the backend owning BUFFER, or nil."
  (with-current-buffer (or buffer (current-buffer))
    (car (seq-find (lambda (entry)
                     (funcall (plist-get (cdr entry) :predicate)))
                   attest--backends))))

(defun attest-backend-for-file (file)
  "Return the name of the first backend whose :test-file-p accepts FILE."
  (car (seq-find (lambda (entry)
                   (when-let* ((pred (plist-get (cdr entry) :test-file-p)))
                     (funcall pred file)))
                 attest--backends)))

(defun attest-backend-for-project (&optional buffer)
  "Return the backend owning BUFFER\='s project, or nil.
A project run starts from any file in the project, not only a test file,
so this asks each backend whether it claims the project rather than the
buffer.  A backend without :project-p is asked about the buffer."
  (with-current-buffer (or buffer (current-buffer))
    (car (seq-find (lambda (entry)
                     (if-let* ((claims (plist-get (cdr entry) :project-p)))
                         (funcall claims)
                       (funcall (plist-get (cdr entry) :predicate))))
                   attest--backends))))

(defun attest--require-backend (&optional scope)
  "Return the backend for the current buffer or signal a user error.
A `project' SCOPE resolves through `attest-backend-for-project'."
  (or (if (eq scope 'project)
          (attest-backend-for-project)
        (attest-backend-for-buffer))
      (user-error "Attest: no backend for `%s'" (buffer-name))))

;;;; Ids and positions

(defconst attest-id-separator "::"
  "Separator between the file and the names in a position id.")

(defun attest-make-id (file &rest names)
  "Return the id for the test at FILE nested under NAMES."
  (string-join (cons file names) attest-id-separator))

(defun attest-id-file (id)
  "Return the file component of ID."
  (car (split-string id attest-id-separator)))

(defun attest-id-names (id)
  "Return the list of names in ID, outermost first."
  (cdr (split-string id attest-id-separator)))

(defun attest-project-root (&optional file backend)
  "Return the project root for FILE, defaulting to the current buffer\='s.
BACKEND names the backend whose :root locates it, defaulting to the one
owning the current buffer."
  (let* ((file (or file buffer-file-name default-directory))
         (backend (or backend (attest-backend-for-buffer)))
         (root-fn (and backend (plist-get (attest-backend-props backend) :root))))
    (file-name-as-directory
     (expand-file-name
      (or (and root-fn (funcall root-fn file))
          (when-let* ((project (project-current nil (file-name-directory file))))
            (project-root project))
          (file-name-directory file))))))

(defun attest--ensure-language (language)
  "Make sure the grammar for LANGUAGE is installed, or signal a user error."
  (unless (if (fboundp 'treesit-ensure-installed)
              (treesit-ensure-installed language)
            (treesit-language-available-p language))
    (user-error "Attest: no tree-sitter grammar for %s; run `treesit-install-language-grammar'"
                language)))

(defun attest--query (backend file)
  "Return the (LANGUAGE . QUERY) of BACKEND for FILE."
  (let ((query (plist-get (attest-backend-props backend) :query)))
    (unless query (error "Attest: backend `%s' has no :query" backend))
    (if (functionp query) (funcall query file) query)))

(defun attest--unescape (text)
  "Return the character sequence the escape TEXT stands for.
Backslash escapes in JavaScript and Python string literals are close
enough to Lisp's that the Lisp reader decodes them; TEXT is returned
as is when it cannot."
  (condition-case nil
      (car (read-from-string (concat "\"" text "\"")))
    (error text)))

(defun attest--name-text (node)
  "Return the test name expressed by NODE.
String literals lose their quotes and decode their escapes; template
strings are concatenated; anything else is returned as source text."
  (pcase (treesit-node-type node)
    ("string"
     (mapconcat (lambda (child)
                  (if (equal (treesit-node-type child) "escape_sequence")
                      (attest--unescape (treesit-node-text child t))
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

(defun attest--node-position (kind definition name file)
  "Return an unlinked position plist of KIND for DEFINITION in FILE.
NAME is the node holding the test's name."
  (list :type kind
        :name (attest--name-text name)
        :file file
        :line (line-number-at-pos (treesit-node-start definition) t)
        :column (1+ (save-excursion
                      (goto-char (treesit-node-start definition))
                      (current-column)))
        :beg (treesit-node-start definition)
        :end (treesit-node-end definition)))

(defun attest--capture-entry (name node)
  "Return the pairing-sweep entry for capture NAME on NODE, or nil.
Only the definition and name captures participate in pairing;
auxiliary captures used by query predicates are dropped."
  (when-let* ((kind (cond ((memq name '(test.definition test.name)) 'test)
                          ((memq name '(namespace.definition namespace.name)) 'namespace))))
    (list (treesit-node-start node) (treesit-node-end node) kind
          (if (memq name '(test.definition namespace.definition)) 'definition 'name)
          node)))

(defun attest--capture-entry< (a b)
  "Return non-nil when capture entry A sorts before B in the sweep.
Entries order by start position; at the same start a definition
precedes a name and a wider node precedes a narrower one."
  (cond ((/= (nth 0 a) (nth 0 b)) (< (nth 0 a) (nth 0 b)))
        ((not (eq (nth 3 a) (nth 3 b))) (eq (nth 3 a) 'definition))
        (t (> (nth 1 a) (nth 1 b)))))

(defun attest--capture-positions (captures file)
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
      (when-let* ((entry (attest--capture-entry name node)))
        (push entry entries)))
    (dolist (entry (sort (nreverse entries) #'attest--capture-entry<))
      (unless (equal (take 4 entry) (and previous (take 4 previous)))
        (pcase-let* ((`(,beg ,_end ,kind ,role ,node) entry)
                     (stack (assq kind stacks)))
          (while (and (cdr stack) (<= (treesit-node-end (cadr stack)) beg))
            (setcdr stack (cddr stack)))
          (if (eq role 'definition)
              (setcdr stack (cons node (cdr stack)))
            (when (cdr stack)
              (push (attest--node-position kind (cadr stack) node file) positions)))))
      (setq previous entry))
    (nreverse positions)))

(defun attest--link-positions (positions file)
  "Assign :parent-id and :id to POSITIONS from FILE by range containment.
POSITIONS must be sorted by :beg ascending."
  (let ((names (make-hash-table :test 'eq))
        stack)
    (dolist (pos positions)
      (while (and stack
                  (>= (plist-get pos :beg) (plist-get (car stack) :end)))
        (pop stack))
      (let* ((parent (car stack))
             (path (append (and parent (gethash parent names))
                           (list (plist-get pos :name)))))
        (puthash pos path names)
        (plist-put pos :parent-id (and parent (plist-get parent :id)))
        (plist-put pos :id (apply #'attest-make-id file path))
        (when (eq (plist-get pos :type) 'namespace)
          (push pos stack))))
    positions))

(defun attest--buffer-positions (file language query)
  "Return the positions QUERY for LANGUAGE finds in the current buffer.
FILE names the buffer's file in the resulting ids."
  (attest--ensure-language language)
  (let* ((root (treesit-parser-root-node (treesit-parser-create language)))
         (positions (attest--capture-positions
                     (treesit-query-capture root query) file)))
    (attest--link-positions
     (sort positions (lambda (a b) (< (plist-get a :beg) (plist-get b :beg))))
     file)))

(defun attest-positions (&optional buffer)
  "Return the test positions discovered in BUFFER.
Each position is a plist with :id, :type (`test' or `namespace'),
:name, :file, :line, :column, :beg, :end and :parent-id."
  (with-current-buffer (or buffer (current-buffer))
    (let* ((backend (attest--require-backend))
           (file (or (and buffer-file-name (expand-file-name buffer-file-name))
                     (buffer-name)))
           (query (attest--query backend file)))
      (attest--buffer-positions file (car query) (cdr query)))))

(defun attest-file-positions (file &optional backend)
  "Return the positions in FILE using BACKEND's query.
BACKEND defaults to the first whose :test-file-p accepts FILE.  A live
buffer visiting FILE is used when there is one; otherwise the file is
parsed in a temporary buffer.  Returns nil when FILE cannot be read."
  (let* ((file (expand-file-name file))
         (backend (or backend (attest-backend-for-file file)
                      (user-error "Attest: no backend for `%s'" file)))
         (query (attest--query backend file)))
    (cond
     ((find-buffer-visiting file)
      (with-current-buffer (find-buffer-visiting file)
        (attest--buffer-positions file (car query) (cdr query))))
     ((file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (attest--buffer-positions file (car query) (cdr query)))))))

(defun attest--run-file-index (run file)
  "Return (POSITIONS . BY-ID) for FILE in RUN, parsing FILE at most once.
POSITIONS keeps discovery order, which `attest--link-positions' relies
on; BY-ID maps each id to its position so a lookup does not scan."
  (let ((index (or (plist-get run :index)
                   (let ((table (make-hash-table :test 'equal)))
                     (plist-put run :index table)
                     table)))
        (file (expand-file-name file)))
    (let ((cached (gethash file index 'missing)))
      (if (not (eq cached 'missing))
          cached
        (let ((positions (attest-file-positions file (plist-get run :backend)))
              (by-id (make-hash-table :test 'equal)))
          (dolist (pos positions)
            (puthash (plist-get pos :id) pos by-id))
          (puthash file (cons positions by-id) index))))))

(defun attest-run-file-positions (run file)
  "Return the positions of FILE for RUN, parsing FILE at most once per run."
  (car (attest--run-file-index run file)))

(defun attest-run-files (run)
  "Return the files RUN covers.
A `project' run lists its :files, a `targets' run the files of its
:targets, and a `file' run its :file."
  (pcase (plist-get run :scope)
    ('project (plist-get run :files))
    ('targets (delete-dups (mapcar (lambda (target) (plist-get target :file))
                                   (plist-get run :targets))))
    (_ (list (plist-get run :file)))))

(defun attest-run-positions (run)
  "Return every position in the files RUN covers."
  (mapcan (lambda (file) (copy-sequence (attest-run-file-positions run file)))
          (attest-run-files run)))

(defun attest-run-position-table (run file)
  "Return a hash of id to position for FILE in RUN, built once per file."
  (cdr (attest--run-file-index run file)))

(defun attest-run-position (run id)
  "Return the position with ID discovered for RUN, or nil."
  (gethash id (attest-run-position-table run (attest-id-file id))))

(defun attest-position-at-point (&optional positions)
  "Return the innermost position in POSITIONS containing point.
Tests win over namespaces of equal extent.  POSITIONS defaults to
`attest-positions'."
  (let ((pt (point))
        best)
    (dolist (pos (or positions (attest-positions)))
      (when (and (<= (plist-get pos :beg) pt)
                 (<= pt (plist-get pos :end))
                 (or (null best)
                     (> (plist-get pos :beg) (plist-get best :beg))
                     (and (= (plist-get pos :beg) (plist-get best :beg))
                          (eq (plist-get pos :type) 'test))))
        (setq best pos)))
    best))

;;;; Results

(defvar attest--results (make-hash-table :test 'equal)
  "Latest known result for every test id.")

(defvar attest--last-run nil
  "The most recent run plist.")

(defvar attest--results-by-file (make-hash-table :test 'equal)
  "Ids of the results recorded for each file, keyed by true name.
Lets a consumer ask for one file\='s results without walking every id
in `attest--results'.")

(defun attest--file-key (file)
  "Return the cache key for FILE.
True names, so a symlinked or /var against /private/var spelling of the
same file lands on one entry."
  (and file (file-truename (expand-file-name file))))

(defun attest--file-ids (file)
  "Return the table of result ids recorded for FILE, creating it if needed."
  (let ((key (attest--file-key file)))
    (or (gethash key attest--results-by-file)
        (puthash key (make-hash-table :test 'equal) attest--results-by-file))))

(defun attest-cache-result (result)
  "Store RESULT in the cache and its file index, outside any run.
`attest--record' is the path a runner takes; this is for a caller that
has a result already, such as a test seeding known state."
  (let ((id (plist-get result :id)))
    (unless id (error "Attest: result without :id: %S" result))
    (puthash id result attest--results)
    (puthash id t (attest--file-ids (plist-get result :file)))
    result))

(defun attest--forget-result (id)
  "Drop ID from the result cache and from its file\='s index."
  (when-let* ((result (gethash id attest--results)))
    (when-let* ((key (attest--file-key (plist-get result :file))))
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
(defun attest-clear-results (&optional file)
  "Forget every cached result, or only those recorded for FILE.
Interactively with a prefix argument, clear the current buffer\='s file."
  (interactive (list (and current-prefix-arg buffer-file-name)))
  (if file
      (dolist (result (attest-results-for-file file))
        (attest--forget-result (plist-get result :id)))
    (clrhash attest--results)
    (clrhash attest--results-by-file))
  (run-hook-with-args 'attest-run-finished-functions attest--last-run))

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

(defun attest-run-failed-results (run)
  "Return the failed results of RUN."
  (seq-filter (lambda (result) (eq (plist-get result :status) 'failed))
              (attest-run-results run)))

(defun attest--record (run result)
  "Store RESULT from RUN and notify consumers.
When discovery knows the test, its :line, :column and :type come from
the position, so the runner's own notion of where a test lives is only
a fallback."
  (let ((id (plist-get result :id)))
    (unless id (error "Attest: result without :id: %S" result))
    (when-let* ((pos (and (plist-get run :backend) (attest-run-position run id))))
      (plist-put result :line (plist-get pos :line))
      (plist-put result :column (plist-get pos :column))
      (unless (plist-get result :type)
        (plist-put result :type (plist-get pos :type))))
    (unless (plist-get result :type) (plist-put result :type 'test))
    (let ((previous (gethash id attest--results)))
      (when (and previous (not (equal (attest--file-key (plist-get previous :file))
                                      (attest--file-key (plist-get result :file)))))
        (attest--forget-result id)))
    (puthash id result attest--results)
    (puthash id t (attest--file-ids (plist-get result :file)))
    (let ((table (or (plist-get run :results)
                     (let ((new (make-hash-table :test 'equal)))
                       (plist-put run :results new)
                       new))))
      (puthash id result table))
    (plist-put run :result-ids (cons id (plist-get run :result-ids)))
    (run-hook-with-args 'attest-result-functions run result)))

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

(defvar attest--progress-timer nil
  "Timer refreshing the mode line while a run is in flight.")

(defvar-local attest--progress nil
  "Mode line construct shown while a run covering this buffer is active.")

(defun attest--progress-buffers (run)
  "Return the live buffers RUN covers."
  (let ((files (attest-run-files run)))
    (seq-filter (lambda (buffer)
                  (with-current-buffer buffer
                    (and buffer-file-name (member buffer-file-name files))))
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
  "Show that RUN has started, in the echo area and the mode line."
  (message "attest: running %s..." (attest-run-description run))
  (dolist (buffer (attest--progress-buffers run))
    (with-current-buffer buffer
      (unless (memq 'attest--progress mode-line-process)
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
      (when (consp mode-line-process)
        (setq-local mode-line-process
                    (remq 'attest--progress mode-line-process)))))
  (force-mode-line-update t))

(defun attest-target-result-p (run result)
  "Return non-nil when RESULT belongs to RUN\='s targets.
Always true for a run without targets.  A namespace target claims every
result below it.  Runners select targets by name, so a `targets' run
over several files can execute a same-named test in another file; this
keeps those out of the cache."
  (or (not (eq (plist-get run :scope) 'targets))
      (let ((id (plist-get result :id)))
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
read failure never clears results."
  (let ((file (expand-file-name file)))
    (when (or (find-buffer-visiting file) (file-readable-p file))
      (let ((known (attest-run-position-table run file))
            (stale nil))
        (dolist (result (attest-results-for-file file))
          (let ((id (plist-get result :id)))
            (unless (gethash id known)
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
         (root (attest-project-root file backend)))
    (append (list :backend backend
                  :scope scope
                  :file file
                  :root root
                  :buffer (current-buffer)
                  :status 'pending
                  :result-ids nil
                  :results nil
                  :state nil)
            props)))

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
  (setq-local ansi-color-context nil)
  (compilation-minor-mode 1))

(defun attest-append-output (run string)
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
            (let ((start (point)))
              (insert string)
              (ansi-color-apply-on-region start (point))))
          (when at-end (goto-char (point-max))))))))

(defun attest-parse-json-line (run line &optional array-type)
  "Return the JSON object LINE holds, or nil, sending other lines to output.
A runner interleaves its own human-readable output with the structured
events attest reads, so a line that is not JSON belongs in RUN\='s output
buffer.  ARRAY-TYPE is passed to `json-parse-string'; objects come back
as alists with null and false read as nil."
  (if (string-prefix-p "{" line)
      (ignore-errors
        (json-parse-string line :object-type 'alist
                           :array-type (or array-type 'array)
                           :null-object nil :false-object nil))
    (attest-append-output run (concat line "\n"))
    nil))

(defun attest--feed-lines (run key string)
  "Split STRING into lines, buffering a partial line under KEY in RUN.
Complete lines go to the backend\='s :parse-line.  A carriage return
before the newline is dropped so a runner emitting CRLF still parses."
  (let* ((pending (concat (plist-get run key) string))
         (lines (mapcar (lambda (line) (string-remove-suffix "\r" line))
                        (split-string pending "\n")))
         (parse (plist-get (attest-backend-props (plist-get run :backend))
                           :parse-line)))
    (plist-put run key (car (last lines)))
    (dolist (line (butlast lines))
      (attest--parse-line run parse line))))

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
    (error (message "Attest: %s backend failed on %S: %s"
                    (plist-get run :backend) line (error-message-string err)))))

(defun attest--flush-lines (run key)
  "Parse a trailing partial line buffered under KEY in RUN."
  (let ((rest (plist-get run key)))
    (when (and rest (not (string-empty-p rest)))
      (plist-put run key "")
      (attest--parse-line
       run (plist-get (attest-backend-props (plist-get run :backend)) :parse-line)
       rest))))

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
  (attest--flush-lines run :partial-stdout)
  (attest--flush-lines run :partial-stderr)
  (plist-put run :status status)
  (plist-put run :end-time (float-time))
  (attest--progress-stop run)
  (run-hook-with-args 'attest-run-finished-functions run)
  (let* ((results (seq-filter (lambda (r) (eq (plist-get r :type) 'test))
                              (attest-run-results run)))
         (failed (seq-count (lambda (r) (eq (plist-get r :status) 'failed)) results))
         (passed (seq-count (lambda (r) (eq (plist-get r :status) 'passed)) results))
         (skipped (- (length results) failed passed)))
    (message "attest: %d passed, %d failed, %d skipped (%s in %.1fs)"
             passed failed skipped status
             (- (plist-get run :end-time) (plist-get run :start-time)))
    (when (or (eq attest-display-output t)
              (and (eq attest-display-output 'on-failure)
                   (or (> failed 0) (eq status 'error))))
      (display-buffer (plist-get run :output-buffer)))))

(defun attest--drain (run)
  "Read whatever RUN\='s stderr pipe still holds.
One `accept-process-output' can return a partial final batch, so read
until the pipe has nothing left."
  (when-let* ((stderr (plist-get run :stderr-process)))
    (while (and (process-live-p stderr)
                (accept-process-output stderr 0.1)))))

(defun attest--sentinel (run)
  "Return a process sentinel for RUN."
  (lambda (process event)
    (unless (process-live-p process)
      (attest--drain run)
      (attest--finish
       run
       (cond ((eq (process-status process) 'signal) 'killed)
             ((or (string-prefix-p "finished" event)
                  (plist-get run :result-ids))
              'finished)
             (t 'error))))))

(defun attest--start (run)
  "Start the process for RUN according to its backend."
  (let* ((props (attest-backend-props (plist-get run :backend)))
         (spec (funcall (plist-get props :command) run))
         (command (plist-get spec :command))
         (directory (or (plist-get spec :directory) (plist-get run :root)))
         (parse-stream (or (plist-get spec :parse-stream) 'stdout))
         (process-environment (append (plist-get spec :env) process-environment)))
    (unless command (error "Attest: backend `%s' produced no command" (plist-get run :backend)))
    (plist-put run :command command)
    (plist-put run :directory directory)
    (plist-put run :partial-stdout "")
    (plist-put run :partial-stderr "")
    (plist-put run :start-time (float-time))
    (plist-put run :status 'running)
    (plist-put run :output-buffer (attest--output-buffer run))
    (when attest-save-before-run
      (let ((root (plist-get run :root)))
        (save-some-buffers
         t (lambda ()
             (and buffer-file-name
                  (file-in-directory-p buffer-file-name root))))))
    (setq attest--last-run run)
    (attest--prune-run-scope run)
    (attest--progress-start run)
    (run-hook-with-args 'attest-run-started-functions run)
    (condition-case err
        (attest--spawn run command directory parse-stream)
      (error
       (attest-append-output run (format "\n%s\n" (error-message-string err)))
       (attest--finish run 'error)
       (user-error "Attest: %s" (error-message-string err))))))

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
                  :sentinel #'ignore))
         (process (make-process
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
    (plist-put run :stderr-process stderr)
    run))

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
    (attest--start run)))

(defun attest--restart (run &rest props)
  "Start a fresh copy of RUN with PROPS merged in.
Recorded results, backend state and the position index are dropped so
the copy behaves like a first run.  A project run rescans its root, so
a rerun picks up test files added or deleted since."
  (attest-kill)
  (let ((copy (copy-sequence run)))
    (dolist (key '(:result-ids :results :state :index))
      (plist-put copy key nil))
    (while props
      (plist-put copy (pop props) (pop props)))
    (when (eq (plist-get copy :scope) 'project)
      (plist-put copy :files (attest--project-test-files
                              (plist-get copy :backend) (plist-get copy :root))))
    (attest--start copy)))

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
         (failed (seq-filter (lambda (r) (eq (plist-get r :type) 'test))
                             (attest-run-failed-results last))))
    (unless failed (user-error "Attest: no failed tests in last run"))
    (attest--restart last :scope 'targets :targets failed)))

;;;###autoload
(defun attest-kill ()
  "Kill the running test process, if any."
  (interactive)
  (when-let* ((run attest--last-run)
              (process (plist-get run :process)))
    (when (process-live-p process)
      (set-process-sentinel process #'ignore)
      (delete-process process)
      (attest--drain run)
      (attest--finish run 'killed)
      (when-let* ((stderr (plist-get run :stderr-process)))
        (when (process-live-p stderr)
          (delete-process stderr))))))

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
