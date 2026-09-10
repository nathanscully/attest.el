;;; attest-reliability-test.el --- Lifecycle regression tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Exercises discovery authority and failure isolation at extension boundaries.

;;; Code:

(require 'test-helper)
(require 'attest-node)
(require 'attest-vitest)
(require 'attest-status)
(require 'attest-pytest)
(require 'attest-rust)
(require 'attest-process-test)

(ert-deftest attest-discovery-preserves-buffer-restriction ()
  "Narrowing must not change whole-file discovery or its identities."
  (let ((file (attest-test-fixture "demo.test.ts")))
    (with-temp-buffer
      (insert-file-contents file)
      (setq buffer-file-name file)
      (let* ((positions (attest-file-positions file 'node))
             (test (cadr positions)))
        (narrow-to-region (plist-get test :beg) (plist-get test :end))
        (let ((beg (point-min)) (end (point-max)))
          (should (equal positions (attest-file-positions file 'node)))
          (should (= beg (point-min)))
          (should (= end (point-max))))))))

(ert-deftest attest-discovery-cache-isolates-providers ()
  "An unchanged file must not reuse another provider's positions."
  (let ((attest--position-cache (make-hash-table :test 'equal))
        (attest--backends (copy-tree attest--backends))
        (file (attest-test-fixture "demo.test.ts")))
    (attest-register-backend
     'empty
     :predicate #'ignore
     :test-file-p #'ignore
     :query '(typescript ((identifier) @ignored))
     :command #'ignore
     :parse-line #'ignore)
    (should (attest-file-positions file 'node))
    (should-not (attest-file-positions file 'empty))
    (attest-invalidate-positions file)
    (should (= 0 (hash-table-count attest--position-cache)))))

(ert-deftest attest-startup-errors-always-finish ()
  "Invalid commands must finish once and release their progress timer."
  (let ((finished 0))
    (attest-process-test--with-run run nil
                                   (let ((attest-run-finished-functions
                                          (list (lambda (_) (cl-incf finished)))))
                                     (should-error (attest--start run))
                                     (should (eq (plist-get run :status) 'error))
                                     (should (plist-get run :end-time))
                                     (should-not attest--progress-timer)
                                     (should (= finished 1))))))

(ert-deftest attest-preparation-callback-after-kill-is-ignored ()
  "A late preparation callback cannot launch a cancelled run."
  (let (continuation)
    (attest-process-test--with-run run nil
                                   (cl-letf (((symbol-function 'attest-backend-props)
                                              (lambda (_backend)
                                                (list :plan (lambda (_run callback)
                                                              (setq continuation callback))))))
                                            (attest--start run)
                                            (should (functionp continuation))
                                            (attest-kill)
                                            (funcall continuation '(:command ("true")))
                                            (should (eq 'killed (plist-get run :status)))
                                            (should-not (plist-get run :plan-launched))))))

(ert-deftest attest-preparation-timeout-finishes-and-cleans-up ()
  "A preparation process that exceeds its deadline becomes a run error."
  (let ((attest-preparation-timeout 0.05))
    (attest-process-test--with-run run nil
                                   (cl-letf (((symbol-function 'attest-backend-props)
                                              (lambda (_backend)
                                                (list :plan
                                                      (lambda (current callback)
                                                        (attest-prepare-command
                                                         current '("sh" "-c" "sleep 5") callback))))))
                                            (attest--start run)
                                            (attest-process-test--wait run 1)
                                            (should (eq 'error (plist-get run :status)))
                                            (should (seq-some (lambda (message)
                                                                (string-match-p "Preparation timed out" message))
                                                              (plist-get run :errors)))
                                            (should-not (process-live-p (plist-get run :process)))
                                            (should-not (process-live-p (plist-get run :stderr-process)))))))

(ert-deftest attest-spawn-error-closes-every-process ()
  "A failed executable must not leak its already allocated stderr pipe."
  (let ((before (process-list)))
    (attest-process-test--with-run run
                                   '(:command ("attest-no-such-executable-exists"))
                                   (should-error (attest--start run))
                                   (should-not (seq-difference (process-list) before)))))

(ert-deftest attest-consumer-error-preserves-result-batch ()
  "One subscriber cannot discard later records or suppress other subscribers."
  (let* ((seen nil)
         (run (list :backend nil :result-ids nil))
         (attest--results (make-hash-table :test 'equal))
         (attest--results-by-file (make-hash-table :test 'equal))
         (attest-result-functions
          (list (lambda (&rest _) (error "broken consumer"))
                (lambda (_ result) (push (plist-get result :id) seen)))))
    (attest--parse-line
     run (lambda (&rest _) '((:id "first" :status passed)
                             (:id "second" :status failed))) "batch")
    (should (equal seen '("second" "first")))
    (should (= 2 (length (attest-run-results run))))))

(ert-deftest attest-restart-drops-extension-state ()
  "A rerun inherits request fields but never arbitrary execution state."
  (let* ((old (list :backend 'node :scope 'file :status 'finished
                    :file "/tmp/x.js" :root "/tmp/"
                    :vitest-only (make-hash-table) :future-cache '(stale)))
         (copy (cl-letf (((symbol-function 'attest-kill) #'ignore)
                         ((symbol-function 'attest--start) #'identity))
                        (attest--restart old))))
    (should (equal (plist-get copy :file) (plist-get old :file)))
    (should-not (plist-get copy :vitest-only))
    (should-not (plist-get copy :future-cache))))

(ert-deftest attest-vitest-only-ignores-comments-and-strings ()
  "Only real declarations influence skipped-result accounting."
  (with-temp-buffer
    (setq buffer-file-name "/tmp/attest-only.test.js")
    (insert "// remove test.only\nconst hint = 'test.only';\n")
    (should-not (attest-vitest--only-file-p buffer-file-name))
    (insert "test . only('real', () => {});\n")
    (should (attest-vitest--only-file-p buffer-file-name))))

(ert-deftest attest-status-targets-and-finish-reconcile ()
  "Unselected tests retain status, and cancellation clears pending markers."
  (let ((attest--results (make-hash-table :test 'equal))
        (attest--results-by-file (make-hash-table :test 'equal))
        (file (attest-test-fixture "demo.test.ts")))
    (with-temp-buffer
      (insert-file-contents file)
      (setq buffer-file-name file)
      (attest-status-mode 1)
      (let* ((positions (attest-file-positions file 'node))
             (a (cadr positions)) (b (caddr positions))
             (run (list :backend 'node :scope 'targets :targets (list a))))
        (dolist (pos (list a b))
          (attest-cache-result (append (list :status 'passed) pos)))
        (attest-status--on-start run)
        (let ((labels (mapcar (lambda (o) (overlay-get o 'help-echo))
                              (overlays-in (point-min) (point-max)))))
          (should (member (concat (plist-get a :name) ": running") labels))
          (should (member (concat (plist-get b :name) ": passed") labels)))
        (run-hook-with-args 'attest-run-finished-functions run)
        (should-not
         (seq-some (lambda (o) (string-suffix-p ": running" (overlay-get o 'help-echo)))
                   (overlays-in (point-min) (point-max))))))))

(ert-deftest attest-id-components-round-trip ()
  "Separators, percent escapes and aliases must preserve identity."
  (let* ((file (attest-test-fixture "demo.test.ts"))
         (names '("a::b" "%3A" "" "unicodé"))
         (id (apply #'attest-make-id file names)))
    (should (equal names (attest-id-names id)))
    (should (equal file (attest-id-file id)))
    (should-not (equal (attest-make-id file "a::b") (attest-make-id file "a" "b")))
    (should (equal id (apply #'attest-make-id
                             (concat (file-name-directory file) "./demo.test.ts") names)))))

(ert-deftest attest-nonzero-exit-after-passing-result-is-error ()
  "A partial passing result must not mask a runner failure."
  (attest-process-test--with-run run
                                 '(:command ("sh" "-c" "printf 'T one\\n'; exit 2"))
                                 (attest--start run)
                                 (attest-process-test--wait run)
                                 (should (eq (plist-get run :status) 'error))
                                 (should (= (plist-get run :exit-code) 2))
                                 (should (= 1 (length (attest-run-results run))))))

(ert-deftest attest-framing-bounds-and-recovers ()
  "An oversized event is bounded and later valid events still arrive."
  (attest-process-test--with-run run '(:command ("true"))
                                 (let ((attest-max-event-size 32))
                                   (dotimes (_ 100) (attest--feed-lines run :partial-stdout (make-string 8 ?x)))
                                   (let ((frame (plist-get run :partial-stdout)))
                                     (should (attest-frame-discarding frame))
                                     (should-not (attest-frame-chunks frame)))
                                   (attest--feed-lines run :partial-stdout "\nT recovered\n")
                                   (should (plist-get run :errors))
                                   (should (attest-run-result run "stub::recovered")))))

(ert-deftest attest-cargo-collisions-preserve-failure ()
  "Identical libtest names in different executables must stay independent."
  (skip-unless (executable-find attest-rust-cargo-executable))
  (let* ((run (attest-test-run-and-wait
               (attest-test-fixture "reliability/cargo/src/lib.rs") #'rust-ts-mode 'project))
         (results (attest-run-results run)))
    (should (eq (plist-get run :status) 'finished))
    (should (= 2 (length results)))
    (should (= 1 (length (attest-run-failed-results run))))
    (should (= 2 (length (plist-get run :invocations))))
    (let ((failed (car (attest-run-failed-results run))))
      (let ((targeted (attest-test-run-and-wait
                       (plist-get failed :file) #'rust-ts-mode 'targets :targets (list failed))))
        (should (= 1 (length (attest-run-results targeted))))
        (should (= 1 (length (attest-run-failed-results targeted))))
        (should (equal (attest-result-case-id (car (attest-run-results targeted)))
                       (attest-result-case-id failed)))
        (should (= 1 (length (attest-results-for-file (plist-get failed :file)))))))))

(ert-deftest attest-cargo-binary-only-file-runs ()
  "A binary-only crate must not require a library target."
  (skip-unless (executable-find attest-rust-cargo-executable))
  (let ((run (attest-test-run-and-wait
              (attest-test-fixture "reliability/binary/src/main.rs") #'rust-ts-mode 'file)))
    (should (eq (plist-get run :status) 'finished))
    (should (= 1 (length (attest-run-results run))))))

(ert-deftest attest-pytest-mixed-parameters-preserve-failure ()
  "A later passing parameter must not overwrite an earlier failure."
  (skip-unless (executable-find (car attest-pytest-command)))
  (let ((run (attest-test-run-and-wait
              (attest-test-fixture "reliability/pytest/test_cases.py") #'python-ts-mode 'file)))
    (should (= 2 (length (attest-run-results run))))
    (should (= 1 (length (attest-run-failed-results run))))
    (should (string-suffix-p "[bad::case]"
                             (plist-get (car (attest-run-failed-results run)) :runner-name)))))

(ert-deftest attest-node-suffix-names-are-real-tests ()
  "A name matching the end of the filename must not be discarded."
  (skip-unless (executable-find attest-node-executable))
  (let ((run (attest-test-run-and-wait
              (attest-test-fixture "reliability/suffix.test.mjs") #'js-mode 'file)))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) (attest-run-results run))
                   '("mjs" "a::b")))))

(provide 'attest-reliability-test)
;;; attest-reliability-test.el ends here
