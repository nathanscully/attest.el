;;; attest-process-test.el --- Tests for the run process lifecycle -*- lexical-binding: t; -*-

;;; Commentary:

;; Spawns short-lived shell processes through a stub backend to cover
;; killing a live run, a command that cannot start, and the parsing of
;; output that arrives as CRLF or after the run stopped.

;;; Code:

(require 'test-helper)
(require 'attest)

(defvar attest-process-test--command nil
  "Command spec the stub backend returns for the next run.")

(attest-register-backend 'process-test
  :predicate #'ignore
  :test-file-p #'ignore
  :root (lambda () temporary-file-directory)
  :query (lambda (_file) (cons 'javascript '((identifier) @name)))
  :command (lambda (_run) attest-process-test--command)
  :parse-line
  (lambda (_run line)
    (when (string-prefix-p "T " line)
      (list :id (concat "stub::" (substring line 2))
            :type 'test :name (substring line 2)
            :status 'passed :file "/stub/file.js")))
  :positions #'ignore)

(defmacro attest-process-test--with-run (var command &rest body)
  "Bind VAR to a started run of COMMAND and evaluate BODY.
The run is killed and the result cache cleared afterwards."
  (declare (indent 2))
  `(let ((attest-process-test--command ,command)
         (attest-save-before-run nil)
         (attest-display-output nil)
         (attest--last-run nil))
     (clrhash attest--results)
     (unwind-protect
         (let ((,var (list :backend 'process-test :scope 'file
                           :file "/stub/file.js" :root temporary-file-directory
                           :buffer (current-buffer) :status 'pending
                           :result-ids nil :results nil :state nil)))
           (setq attest--last-run ,var)
           ,@body)
       (attest-kill)
       (clrhash attest--results))))

(defun attest-process-test--wait (run &optional seconds)
  "Pump the event loop until RUN stops or SECONDS elapse."
  (let ((deadline (+ (float-time) (or seconds 5))))
    (while (and (eq (plist-get run :status) 'running)
                (< (float-time) deadline))
      (accept-process-output nil 0.05))))

(ert-deftest attest-kill-closes-the-stderr-pipe ()
  "Killing a run leaves no live pipe holding a filter over it."
  (attest-process-test--with-run run
      (list :command (list "sh" "-c" "sleep 5") :parse-stream 'stderr)
    (attest--start run)
    (should (process-live-p (plist-get run :stderr-process)))
    (attest-kill)
    (should (eq (plist-get run :status) 'killed))
    (should-not (process-live-p (plist-get run :stderr-process)))))

(ert-deftest attest-stopped-runs-record-nothing ()
  "A filter firing after its run stopped adds nothing to the cache."
  (attest-process-test--with-run run
      (list :command (list "sh" "-c" "sleep 5") :parse-stream 'stderr)
    (attest--start run)
    (let ((filter (process-filter (plist-get run :stderr-process))))
      (attest-kill)
      (funcall filter (plist-get run :stderr-process) "T ghost\n")
      (should-not (gethash "stub::ghost" attest--results)))))

(ert-deftest attest-failed-spawn-finishes-without-signalling ()
  "A command that cannot start ends the run as an error, not a debugger."
  (attest-process-test--with-run run
      (list :command (list "attest-no-such-executable-exists")
            :parse-stream 'stdout)
    (should-error (attest--start run) :type 'user-error)
    (should (eq (plist-get run :status) 'error))))

(ert-deftest attest-crlf-output-still-parses ()
  "Lines ending in CRLF reach the backend without their carriage return."
  (attest-process-test--with-run run
      (list :command (list "sh" "-c" "printf 'T one\\r\\nT two\\r\\n' 1>&2")
            :parse-stream 'stderr)
    (attest--start run)
    (attest-process-test--wait run)
    (should (gethash "stub::one" attest--results))
    (should (gethash "stub::two" attest--results))))

(ert-deftest attest-summary-counts-tests-not-namespaces ()
  "The finish summary ignores namespace results."
  (attest-process-test--with-run run
      (list :command (list "sh" "-c" "true") :parse-stream 'stdout)
    (plist-put run :status 'running)
    (plist-put run :start-time (float-time))
    (plist-put run :output-buffer nil)
    (attest--record run (list :id "s::ns" :type 'namespace :name "ns"
                              :status 'failed :file "/stub/file.js"))
    (attest--record run (list :id "s::ns::a" :type 'test :name "a"
                              :status 'passed :file "/stub/file.js"))
    (let ((summary nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (setq summary (apply #'format fmt args)))))
        (attest--finish run 'finished))
      (should (string-match-p "1 passed, 0 failed, 0 skipped" summary)))))

(ert-deftest attest-start-rejects-a-run-it-cannot-mutate ()
  "A run that plist-put cannot extend in place is refused before it runs.
`plist-put' on nil discards the write, so such a run would lose its
process, status and results silently.  The check must reject it rather
than let a later missing key be the thing that fails."
  (let ((attest-process-test--command
         (list :command (list "sh" "-c" "true") :parse-stream 'stdout))
        (attest-save-before-run nil)
        (attest-display-output nil)
        (spawned nil))
    (cl-letf (((symbol-function 'attest--spawn)
               (lambda (&rest _) (setq spawned t) nil)))
      (dolist (run (list nil
                         (list :scope 'file :status 'pending)
                         (list :backend 'process-test :scope 'file)))
        (let ((err (should-error (attest--start run))))
          (should (string-prefix-p "Attest: run " (cadr err)))))
      (should-not spawned))))

(ert-deftest attest-output-buffer-stays-bounded ()
  "Output past `attest-max-output' drops the oldest lines, not the newest."
  (with-temp-buffer
    (let ((run (list :backend 'process-test :output-buffer (current-buffer)))
          (attest-max-output 2000))
      (dotimes (i 400)
        (attest-append-output run (format "line %03d padded out to some length\n" i)))
      (should (<= (buffer-size) 2200))
      (should (string-match-p "line 399" (buffer-string)))
      (should-not (string-match-p "line 000" (buffer-string)))
      (should (string-match-p "earlier output dropped" (buffer-string))))))

(ert-deftest attest-output-buffer-keeps-everything-when-unlimited ()
  "A nil limit keeps the whole run."
  (with-temp-buffer
    (let ((run (list :backend 'process-test :output-buffer (current-buffer)))
          (attest-max-output nil))
      (dotimes (i 200)
        (attest-append-output run (format "line %03d\n" i)))
      (should (string-match-p "line 000" (buffer-string)))
      (should (string-match-p "line 199" (buffer-string))))))

(provide 'attest-process-test)
;;; attest-process-test.el ends here
