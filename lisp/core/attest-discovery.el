;;; attest-discovery.el --- Discovery snapshots and position lookup -*- lexical-binding: t; -*-

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

;; Discovery snapshots and position lookup.

;;; Code:

(require 'attest-backend)
(require 'treesit)
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
  (save-restriction
    (widen)
    (let* ((root (treesit-parser-root-node (treesit-parser-create language)))
           (positions (attest--capture-positions
                       (treesit-query-capture root query) file)))
      (attest--link-positions
       (sort positions (lambda (a b) (< (plist-get a :beg) (plist-get b :beg))))
       file))))

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

(defvar attest--position-cache (make-hash-table :test 'equal)
  "Cached discovery keyed by true name, holding (STAMP . POSITIONS).")

(defvar attest--position-cache-used (make-hash-table :test 'equal)
  "Logical access time for entries in `attest--position-cache'.")

(defvar attest--position-cache-clock 0
  "Monotonic access counter for the discovery position cache.")

(defun attest--position-cache-touch (key)
  "Mark discovery cache KEY as recently used."
  (puthash key (cl-incf attest--position-cache-clock)
           attest--position-cache-used))

(defun attest--position-cache-evict ()
  "Evict least-recently-used discovery entries past the configured bound."
  (when attest-max-position-cache-entries
    (catch 'attest-position-cache-eviction-done
      (while (> (hash-table-count attest--position-cache)
                attest-max-position-cache-entries)
        (let (old-key old-use)
          (maphash (lambda (key use)
                     (when (or (null old-use) (< use old-use))
                       (setq old-key key old-use use)))
                   attest--position-cache-used)
          (if old-key
              (progn
                (remhash old-key attest--position-cache)
                (remhash old-key attest--position-cache-used))
            (throw 'attest-position-cache-eviction-done nil)))))))

(defun attest--position-cache-store (key stamp positions)
  "Store discovery POSITIONS for KEY and STAMP, respecting the cache bound."
  (puthash key (cons stamp positions) attest--position-cache)
  (attest--position-cache-touch key)
  (attest--position-cache-evict))

(defun attest--file-stamp (file)
  "Return a value identifying FILE\='s current contents, or nil.
Modification time and size together, which is what the parse cache
compares to decide whether a file must be read again."
  (when-let* ((attrs (file-attributes file)))
    (cons (file-attribute-modification-time attrs)
          (file-attribute-size attrs))))

(defun attest-invalidate-positions (&optional file)
  "Drop cached discovery for FILE, or for every file.
Discovery is keyed by modification time and size, so this is only needed
when a file changes without either moving."
  (interactive)
  (if file
      (let ((key (attest--file-key file)))
        (remhash key attest--position-cache)
        (remhash key attest--position-cache-used))
    (clrhash attest--position-cache)
    (clrhash attest--position-cache-used)))

(defun attest--parseable-size-p (file)
  "Return non-nil unless FILE is too large to parse during a run.
Discovery parses every file in scope on the Emacs thread, so one
generated or minified file would otherwise stall the whole run.  A
buffer already visiting FILE is parsed whatever its size, since the user
asked for it."
  (or (null attest-max-file-size)
      (let ((size (file-attribute-size (file-attributes file))))
        (or (null size) (<= size attest-max-file-size)))))

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
     ((and (file-readable-p file) (attest--parseable-size-p file))
      (let* ((key (attest--file-key file))
             (stamp (list backend (attest-backend-revision backend)
                          query (attest--file-stamp file)))
             (cached (gethash key attest--position-cache)))
        (if (and cached stamp (equal (car cached) stamp))
            (progn
              (attest--position-cache-touch key)
              (cdr cached))
          (let ((positions (with-temp-buffer
                             (insert-file-contents file)
                             (attest--buffer-positions
                              file (car query) (cdr query)))))
            (when stamp
              (attest--position-cache-store key stamp positions))
            positions)))))))

(defun attest--run-file-index (run file)
  "Return (POSITIONS . BY-ID) for FILE in RUN, parsing FILE at most once.
POSITIONS keeps discovery order, which `attest--link-positions' relies
on; BY-ID maps each id to its position so a lookup does not scan."
  (let ((index (or (plist-get run :index)
                   (let ((table (make-hash-table :test 'equal)))
                     (plist-put run :index table)
                     table)))
        (key (attest--file-key file)))
    (let ((cached (gethash key index 'missing)))
      (if (not (eq cached 'missing))
          cached
        (let ((positions (attest-file-positions file (plist-get run :backend)))
              (by-id (make-hash-table :test 'equal)))
          (dolist (pos positions)
            (puthash (plist-get pos :id) pos by-id))
          (puthash key (cons positions by-id) index))))))

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
  "Return the position with ID discovered for RUN, or nil.
A runner may name a file differently from discovery, so when the id does
not match directly the file\='s positions are searched by name."
  (let ((file (attest-id-file id)))
    (gethash (apply #'attest-make-id file (attest-id-names id))
             (attest-run-position-table run file))))

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

(provide 'attest-discovery)
;;; attest-discovery.el ends here
