;;; attest-backend.el --- Backend registration and resolution -*- lexical-binding: t; -*-

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

;; Backend registration and resolution.

;;; Code:

(require 'attest-model)
(require 'project)
;;;; Backends

(defvar attest--backends nil
  "Alist of (NAME . PROPS) registered backends, most recent first.")

(defvar attest--backend-revisions (make-hash-table :test 'eq)
  "Registration revision for each backend name.
Discovery includes this revision in cache keys, so replacing a backend
query or provider cannot reuse an old snapshot accidentally.")

(defconst attest-backend-required-properties
  '(:predicate :test-file-p :query :command :parse-line)
  "Properties every backend must provide.")

(defconst attest-backend-function-properties
  '(:predicate :project-p :test-file-p :root :command :parse-line :plan)
  "Backend properties whose values must be callable when present.")

(defun attest-backend-names ()
  "Return the names of all registered backends, most recent first."
  (mapcar #'car attest--backends))

(defun attest--backend-callable-p (value)
  "Return non-nil when VALUE can be called as an Emacs Lisp function."
  (or (functionp value)
      (and (symbolp value) (fboundp value))))

(defun attest--backend-query-p (value)
  "Return non-nil when VALUE is a backend query or query provider.
A query pairs a language symbol with a `treesit-query-capture' pattern,
which that function accepts as either a string or an s-expression."
  (or (attest--backend-callable-p value)
      (and (consp value)
           (symbolp (car value))
           (car value)
           (or (stringp (cdr value)) (listp (cdr value))))))

(defun attest--validate-backend-props (name props)
  "Validate backend NAME's registration PROPS, or signal an error."
  (unless (and (proper-list-p props) (zerop (% (length props) 2)))
    (error "Attest: backend `%s` props must be an even plist" name))
  (let ((rest props))
    (while rest
      (let ((key (pop rest)))
        (unless (keywordp key)
          (error "Attest: backend `%s` has non-keyword property `%s`"
                 name key))
        (pop rest))))
  (dolist (key attest-backend-required-properties)
    (unless (plist-member props key)
      (error "Attest: backend `%s` is missing `%s`" name key))
    (unless (if (eq key :query)
                (attest--backend-query-p (plist-get props key))
              (attest--backend-callable-p (plist-get props key)))
      (error "Attest: backend `%s` property `%s` has an invalid value"
             name key)))
  (dolist (key attest-backend-function-properties)
    (when (and (plist-member props key)
               (plist-get props key)
               (not (attest--backend-callable-p (plist-get props key))))
      (error "Attest: backend `%s` property `%s` must be callable"
             name key)))
  (let ((query (plist-get props :query)))
    (unless (attest--backend-query-p query)
      (error "Attest: backend `%s` property `:query` is invalid" name)))
  (when (plist-member props :test-failure-exit-codes)
    (let ((codes (plist-get props :test-failure-exit-codes)))
      (unless (and (listp codes) (seq-every-p #'integerp codes))
        (error "Attest: backend `%s` property `:test-failure-exit-codes` is invalid"
               name))))
  t)

(defun attest-validate-backend (name)
  "Validate the registered backend NAME and return NAME.
Signals an error naming the first missing or malformed contract field."
  (unless (symbolp name)
    (error "Attest: backend name must be a symbol, got `%s`" name))
  (let ((props (alist-get name attest--backends)))
    (unless props
      (error "Attest: no backend named `%s`" name))
    (attest--validate-backend-props name props)
    name))

(defun attest-validate-backends ()
  "Validate every registered backend and return their names.
This is useful for package tests and extension loaders after registration."
  (mapcar #'attest-validate-backend (attest-backend-names)))

(defun attest--validate-plist (kind value)
  "Validate that VALUE is a property list for object KIND."
  (unless (and (proper-list-p value) (zerop (% (length value) 2)))
    (error "Attest: %s must be an even property list" kind))
  (let ((rest value))
    (while rest
      (let ((key (pop rest)))
        (unless (keywordp key)
          (error "Attest: %s has non-keyword property `%s`" kind key))
        (pop rest))))
  value)

(defun attest-validate-invocation-spec (spec)
  "Validate one runner invocation SPEC and return it.
The command is a non-empty argv list; optional directory, environment and
parse-stream properties use the shapes documented by the backend contract."
  (attest--validate-plist "invocation spec" spec)
  (let ((command (plist-get spec :command))
        (directory (plist-get spec :directory))
        (environment (plist-get spec :env))
        (parse-stream (plist-get spec :parse-stream)))
    (unless (and (consp command)
                 (proper-list-p command)
                 (seq-every-p #'stringp command))
      (error "Attest: invocation spec `:command` must be a non-empty argv list"))
    (when (and directory (not (stringp directory)))
      (error "Attest: invocation spec `:directory` must be a directory string"))
    (unless (and (proper-list-p environment) (seq-every-p #'stringp environment))
      (error "Attest: invocation spec `:env` must be a list of strings"))
    (when (and parse-stream (not (memq parse-stream '(stdout stderr))))
      (error "Attest: invocation spec `:parse-stream` must be `stdout` or `stderr`")))
  spec)

(defun attest-validate-invocation-plan (plan)
  "Validate invocation PLAN and return its list of invocation specs.
PLAN is either one invocation spec or a plist with `:invocations`."
  (let ((specs (if (and (proper-list-p plan) (plist-member plan :invocations))
                   (plist-get plan :invocations)
                 (list plan))))
    (unless (and (consp specs) (proper-list-p specs))
      (error "Attest: invocation plan must contain one or more specs"))
    (mapcar #'attest-validate-invocation-spec specs)))

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
:root         Optional function of a file returning the project root.
:plan         Optional function of RUN and a continuation.  It performs
              asynchronous preparation and calls the continuation with one
              invocation specification or a :invocations plist.  It must
              call the continuation at most once and stop work when RUN is
              no longer active; `attest-prepare-command' supplies the
              cancellable process path.
:test-failure-exit-codes
              Optional list of non-zero exit codes that mean tests failed
              rather than the runner itself failing."
  (unless (symbolp name)
    (error "Attest: backend name must be a symbol, got `%s`" name))
  (attest--validate-backend-props name props)
  (setf (alist-get name attest--backends) props)
  (puthash name (1+ (attest-backend-revision name)) attest--backend-revisions)
  name)

(defun attest-backend-props (name)
  "Return the props plist of backend NAME."
  (or (alist-get name attest--backends)
      (error "Attest: no backend named `%s'" name)))

(defun attest-backend-revision (name)
  "Return the registration revision of backend NAME."
  (gethash name attest--backend-revisions 0))

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
  (or (and attest-backend
           (progn (attest-backend-props attest-backend) attest-backend))
      (if (eq scope 'project)
          (attest-backend-for-project)
        (attest-backend-for-buffer))
      (user-error "Attest: no backend for `%s'" (buffer-name))))

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

(provide 'attest-backend)
;;; attest-backend.el ends here
