;;; attest-model.el --- Shared values and configuration -*- lexical-binding: t; -*-

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

;; Shared values and configuration.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(defgroup attest nil
  "Language-agnostic test runner."
  :group 'tools
  :prefix "attest-")

(cl-defstruct (attest-request (:constructor attest-request-create))
              "The selection and origin of a run, independent of mutable execution state."
              backend scope file root buffer targets files)

(cl-defstruct (attest-invocation (:constructor attest-invocation-create))
              "One owned runner process and its terminal outcome.
STATE is parser state for this invocation and EXECUTION-TARGET identifies
the runner context when a backend has more than one target."
              spec process stderr exit-code status state execution-target)

(cl-defstruct (attest-frame (:constructor attest-frame-create))
              "Bounded incremental framing state for one runner stream."
              chunks (bytes 0) discarding)

(defcustom attest-backend nil
  "Explicit backend for the current project, or nil for automatic detection."
  :type '(choice (const :tag "Automatic" nil) symbol)
  :safe #'symbolp
  :package-version '(attest . "0.1.0"))

(defcustom attest-max-event-size (* 4 1024 1024)
  "Maximum bytes retained for one structured runner event."
  :type 'natnum
  :package-version '(attest . "0.1.0"))

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

(defcustom attest-max-output (* 2 1024 1024)
  "Keep at most this many characters in the run output buffer.
The oldest output is dropped past this point, so a runner that produces
output without bound cannot exhaust memory during one run.  Set to nil
to keep everything."
  :type '(choice (const :tag "No limit" nil) integer)
  :package-version '(attest . "0.1.0"))

(defcustom attest-max-file-size (* 512 1024)
  "Skip files larger than this many bytes during discovery.
Discovery parses every file a run covers before the runner starts, so a
generated or minified file can stall it.  A file already open in a
buffer is parsed whatever its size.  Set to nil to parse everything."
  :type '(choice (const :tag "No limit" nil) integer)
  :package-version '(attest . "0.1.0"))

(defcustom attest-preparation-timeout 60
  "Maximum seconds a run may spend waiting for backend preparation.
When nil, a backend may prepare without a deadline.  A timeout is a run
error and cancels the preparation process if one is still owned by the
run."
  :type '(choice (const :tag "No limit" nil) number)
  :package-version '(attest . "0.1.0"))

(defcustom attest-max-position-cache-entries 256
  "Maximum number of files retained in the discovery position cache.
Set to nil to retain every entry.  Per-run indexes remain independent, so
evicting a shared entry cannot change a run already in progress."
  :type '(choice (const :tag "No limit" nil) natnum)
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

(defvar attest-results-changed-functions nil
  "Abnormal hook called with a list of files whose cached results changed.
A nil list means every file.  Fired when the cache is edited outside a
run, as `attest-clear-results' does; consumers redraw the files named.
A run reports through `attest-result-functions' and
`attest-run-finished-functions' instead.")

(defvar attest-run-finished-functions nil
  "Abnormal hook called with the run plist when the test process exits.
The run\='s :status is `finished', `killed' or `error' by then, and
`attest-run-results' returns everything it recorded.

A function here may start work of its own, as `attest-flymake-mode'
does, but must not call `attest-run' unconditionally: that reruns on
every finish and never terminates.")

(defconst attest-id-separator "::"
  "Separator between the file and the names in a position id.")

(defun attest-result-case-id (result)
  "Return RESULT's runtime-case identity.
The legacy `:id' field remains the wire representation; this accessor
gives consumers a stable name while the model distinguishes cases from
source definitions."
  (or (plist-get result :case-id)
      (plist-get result :id)))

(defun attest-result-definition-id (result)
  "Return RESULT's source-definition identity, or its case id.
Backends use `:definition-id' when a runtime case such as a parameterized
test maps back to a static definition."
  (or (plist-get result :definition-id)
      (attest-result-case-id result)))

(defun attest-result-status (result)
  "Return RESULT's status symbol."
  (plist-get result :status))

(defun attest-result-type (result)
  "Return RESULT's `test' or `namespace' type."
  (plist-get result :type))

(defun attest-result-name (result)
  "Return RESULT's display name."
  (plist-get result :name))

(defun attest-result-file (result)
  "Return the source file associated with RESULT."
  (plist-get result :file))

(defun attest-make-id (file &rest names)
  "Return the id for the test at FILE nested under NAMES."
  (string-join (mapcar #'attest--encode-id-part
                       (cons (attest--file-key file) names))
               attest-id-separator))

(defun attest--encode-id-part (text)
  "Encode separator characters and percent signs in identity component TEXT."
  (string-replace ":" "%3A" (string-replace "%" "%25" text)))

(defun attest--decode-id-part (text)
  "Decode the identity component TEXT without changing literal escape text."
  (string-replace "%25" "%" (string-replace "%3A" ":" text)))

(defun attest-id-file (id)
  "Return the file component of ID."
  (attest--decode-id-part (car (split-string id attest-id-separator))))

(defun attest-id-names (id)
  "Return the list of names in ID, outermost first."
  (mapcar #'attest--decode-id-part (cdr (split-string id attest-id-separator))))

(defun attest--file-key (file)
  "Return the cache key for FILE.
True names, so a symlinked or /var against /private/var spelling of the
same file lands on one entry."
  (and file (file-truename (expand-file-name file))))

(defun attest--notify (hook &rest args)
  "Call each subscriber to HOOK with ARGS, isolating subscriber errors."
  (run-hook-wrapped
   hook (lambda (function)
          (condition-case err
              (apply function args)
            (error (message "Attest: subscriber %S failed: %s"
                            function (error-message-string err))))
          nil)))

(provide 'attest-model)
;;; attest-model.el ends here
