;;; attest-node-test.el --- Tests for the node backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests run against recorded reporter output in fixtures/, never
;; against a live node process.  The integration test at the bottom does
;; spawn node and is skipped when node is not installed.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-node)

(defconst attest-node-test--file (attest-test-fixture "demo.test.ts")
  "File path recorded inside demo-events.jsonl.")

(defun attest-node-test--parse-fixture (name)
  "Feed fixture NAME through the parser and return the results in order."
  (attest-test-with-run run
                        (let (results)
                          (dolist (line (attest-test-fixture-lines name))
                            (let ((r (attest-node--parse-line run line)))
                              (when r (push r results))))
                          (nreverse results))))

(ert-deftest attest-node-parses-every-test-and-suite ()
  (let ((results (attest-node-test--parse-fixture "demo-events.jsonl")))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("adds" "fails on purpose" "deep passes" "skipped one"
                     "todo one" "nested" "math" "top level passes" "throws")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed failed passed skipped todo passed failed passed failed)))))

(ert-deftest attest-node-ids-encode-nesting ()
  (let* ((results (attest-node-test--parse-fixture "demo-events.jsonl"))
         (ids (mapcar (lambda (r) (plist-get r :id)) results))
         (f attest-node-test--file))
    (should (member (attest-make-id f "math" "adds") ids))
    (should (member (attest-make-id f "math" "nested" "deep passes") ids))
    (should (member (attest-make-id f "math" "nested") ids))
    (should (member (attest-make-id f "throws") ids))
    (should-not (member (attest-make-id f "nested" "deep passes") ids))))

(ert-deftest attest-node-suites-are-namespaces ()
  (let* ((results (attest-node-test--parse-fixture "demo-events.jsonl"))
         (math (seq-find (lambda (r) (equal (plist-get r :name) "math")) results))
         (adds (seq-find (lambda (r) (equal (plist-get r :name) "adds")) results)))
    (should (eq (plist-get math :type) 'namespace))
    (should (eq (plist-get adds :type) 'test))
    (should (equal (plist-get math :line) 4))
    (should (equal (plist-get adds :line) 5))))

(ert-deftest attest-node-failure-carries-message-and-assertion-line ()
  (let* ((results (attest-node-test--parse-fixture "demo-events.jsonl"))
         (fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose"))
                         results))
         (throws (seq-find (lambda (r) (equal (plist-get r :name) "throws")) results)))
    (should (string-prefix-p "Expected values to be strictly equal"
                             (plist-get fail :message)))
    (should (equal (plist-get fail :location) '(10 . 5)))
    (should (equal (plist-get throws :message) "boom"))
    (should (equal (plist-get throws :location) '(21 . 9)))))

(ert-deftest attest-node-suite-failure-has-no-location ()
  (let* ((results (attest-node-test--parse-fixture "demo-events.jsonl"))
         (math (seq-find (lambda (r) (equal (plist-get r :name) "math")) results)))
    (should (eq (plist-get math :status) 'failed))
    (should (equal (plist-get math :message) "1 subtest failed"))
    (should-not (plist-get math :location))))

(ert-deftest attest-node-ignores-noise-lines ()
  (attest-test-with-run run
                        (should-not (attest-node--parse-line run ""))
                        (should-not (attest-node--parse-line run "not json"))
                        (should-not (attest-node--parse-line run "{\"type\":\"test:diagnostic\",\"data\":{}}"))
                        (should-not (attest-node--parse-line run "{broken"))))

(ert-deftest attest-node-name-pattern-anchors-tests-and-namespaces ()
  (should (equal (attest-node--name-pattern (list :id "/f.ts::math::adds" :type 'test))
                 "--test-name-pattern=^math adds$"))
  (should (equal (attest-node--name-pattern (list :id "/f.ts::math::nested" :type 'namespace))
                 "--test-name-pattern=^math nested( |$)"))
  (should (equal (attest-node--name-pattern (list :id "/f.ts::a (b) [c]? $1.0" :type 'test))
                 "--test-name-pattern=^a \\(b\\) \\[c\\]\\? \\$1\\.0$")))

(ert-deftest attest-node-command-for-scopes ()
  (let* ((root "/repo/")
         (base (list :backend 'node :root root :file "/repo/src/a.test.ts"))
         (argv (lambda (run) (plist-get (attest-node--command run) :command))))
    (should (equal (last (funcall argv (append base '(:scope file))))
                   '("src/a.test.ts")))
    (should (member "--test-name-pattern=^math adds$"
                    (funcall argv (append base (list :scope 'targets
                                                     :targets (list (list :id "/repo/src/a.test.ts::math::adds"
                                                                          :file "/repo/src/a.test.ts"
                                                                          :type 'test)))))))
    (should (equal (last (funcall argv (append base (list :scope 'project
                                                          :files '("/repo/src/a.test.ts"
                                                                   "/repo/src/b.test.ts"))))
                         2)
                   '("src/a.test.ts" "src/b.test.ts")))
    (let ((cmd (funcall argv (append base (list :scope 'targets
                                                :targets (list (list :id "/repo/src/a.test.ts::x" :file "/repo/src/a.test.ts" :type 'test)
                                                               (list :id "/repo/src/b.test.ts::y" :file "/repo/src/b.test.ts" :type 'test)))))))
      (should (member "--test-name-pattern=^x$" cmd))
      (should (member "--test-name-pattern=^y$" cmd))
      (should (equal (last cmd 2) '("src/a.test.ts" "src/b.test.ts"))))
    (should (eq (plist-get (attest-node--command (append base '(:scope file))) :parse-stream)
                'stderr))))

(ert-deftest attest-node-root-prefers-package-json ()
  (let* ((dir (make-temp-file "attest-root" t))
         (pkg (expand-file-name "pkg/" dir))
         (file (expand-file-name "src/a.test.ts" pkg)))
    (make-directory (file-name-directory file) t)
    (write-region "" nil (expand-file-name "package.json" pkg))
    (should (equal (file-truename (attest-node-root file)) (file-truename pkg)))
    (with-temp-buffer
      (setq buffer-file-name file)
      (typescript-ts-mode)
      (should (string-prefix-p "/" (attest-project-root)))
      (should (equal (file-truename (attest-project-root)) (file-truename pkg))))
    (delete-directory dir t)))

(ert-deftest attest-node-test-file-p ()
  (should (attest-node-test-file-p "/p/src/scanner.test.ts"))
  (should (attest-node-test-file-p "/p/src/a.spec.js"))
  (should (attest-node-test-file-p "/p/src/a_test.mjs"))
  (should-not (attest-node-test-file-p "/p/src/scanner.ts"))
  (should-not (attest-node-test-file-p "/p/node_modules/x/a.test.ts")))

(ert-deftest attest-node-integration-runs-fixture-file ()
  "Spawn node on fixtures/demo.test.ts and check the streamed results."
  (skip-unless (executable-find attest-node-executable))
  (let* ((file (attest-test-fixture "demo.test.ts"))
         (attest-save-before-run nil)
         (attest-display-output nil)
         (results nil)
         (finished nil)
         (attest-result-functions (list (lambda (_run r) (push r results))))
         (attest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (setq buffer-file-name file)
      (setq default-directory attest-test-fixtures)
      (typescript-ts-mode)
      (attest-run 'file))
    (with-timeout (30 (ert-fail "node did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (= (length results) 9))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose"))
                          results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :file) file))
      (should (equal (plist-get fail :location) '(10 . 5))))
    (should (eq (plist-get (attest-last-run) :status) 'finished))
    (with-current-buffer attest-output-buffer-name
      (should (string-match-p "fails on purpose" (buffer-string))))))

(ert-deftest attest-node-integration-prunes-stale-results ()
  "Starting a run drops cached results the file no longer contains."
  (skip-unless (executable-find attest-node-executable))
  (let* ((file (attest-test-fixture "demo.test.ts"))
         (ghost (attest-make-id file "test removed since last run"))
         (attest-save-before-run nil)
         (attest-display-output nil)
         (finished nil)
         (attest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (clrhash attest--results)
    (attest-cache-result (list :id ghost :name "test removed since last run"
                               :status 'failed :type 'test :file file))
    (with-temp-buffer
      (setq buffer-file-name file)
      (setq default-directory attest-test-fixtures)
      (typescript-ts-mode)
      (attest-run 'file))
    (with-timeout (30 (ert-fail "node did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should-not (attest-result ghost))))

(ert-deftest attest-node-targets-drop-same-name-in-other-files ()
  "A targets run keeps only results from the files it targeted.
`--test-name-pattern' matches by name, so a same-named test in another
file of the same run must not reach the cache."
  (let* ((wanted (attest-test-fixture "demo.test.ts"))
         (other (attest-test-fixture "other.test.ts"))
         (run (list :backend 'node :scope 'targets
                    :targets (list (list :id (attest-make-id wanted "throws")
                                         :type 'test :file wanted)))))
    (should (attest-target-result-p
             run (list :id (attest-make-id wanted "throws"))))
    (should-not (attest-target-result-p
                 run (list :id (attest-make-id other "throws"))))))

(ert-deftest attest-node-namespace-target-claims-its-subtree ()
  "A namespace target keeps its own tests and nothing from other files."
  (let* ((wanted (attest-test-fixture "demo.test.ts"))
         (other (attest-test-fixture "other.test.ts"))
         (run (list :backend 'node :scope 'targets
                    :targets (list (list :id (attest-make-id wanted "math")
                                         :type 'namespace :file wanted)))))
    (should (attest-target-result-p
             run (list :id (attest-make-id wanted "math" "adds"))))
    (should-not (attest-target-result-p
                 run (list :id (attest-make-id other "math" "adds"))))
    (should-not (attest-target-result-p
                 run (list :id (attest-make-id wanted "other test"))))))

(ert-deftest attest-node-non-target-runs-keep-every-result ()
  "File and project runs record everything the runner reports."
  (let ((run (list :backend 'node :scope 'file
                   :file (attest-test-fixture "demo.test.ts"))))
    (should (attest-target-result-p
             run (list :id (attest-make-id "/anywhere.test.ts" "anything"))))))

(ert-deftest attest-node-backend-filters-results-by-target ()
  "The registered node parser drops results outside the run's targets."
  (let* ((wanted (attest-test-fixture "demo.test.ts"))
         (other (attest-test-fixture "other.test.ts"))
         (parse (plist-get (attest-backend-props 'node) :parse-line))
         (run (list :backend 'node :scope 'targets
                    :targets (list (list :id (attest-make-id wanted "throws")
                                         :type 'test :file wanted))))
         (line (lambda (file)
                 (json-serialize
                  (list :type "attest:test" :kind "test"
                        :names (vector "throws") :file file
                        :location (list :line 20 :column 1)
                        :state "passed" :errors [])))))
    (should (funcall parse run (funcall line wanted)))
    (should-not (funcall parse run (funcall line other)))))

(defconst attest-node-test--concurrent-dir
  (attest-test-fixture "concurrent/")
  "Directory holding the two files of the concurrency fixture.")

(defun attest-node-test--replay-reporter (reporter)
  "Return the events the reporter at REPORTER emits for the concurrent stream.
The raw node events of two test files, recorded one file at a time and
then interleaved, are piped through REPORTER by replay.mjs.  This is
the stream a parent reporter sees when `node --test' runs files
concurrently, without depending on how a given node version schedules
them."
  (let ((raw (string-join (attest-test-fixture-lines "concurrent-raw-events.jsonl")
                          "\n")))
    (with-temp-buffer
      (insert raw "\n")
      (let* ((process-environment
              (seq-remove (lambda (v) (string-prefix-p "NODE_OPTIONS=" v))
                          process-environment))
             (status (call-process-region
                      (point-min) (point-max) attest-node-executable
                      t t nil
                      (expand-file-name "replay.mjs" attest-node-test--concurrent-dir)
                      reporter)))
        (unless (eq status 0)
          (ert-fail (format "replay.mjs exited %S: %s" status (buffer-string)))))
      (split-string (buffer-string) "\n" t))))

(ert-deftest attest-node-reporter-keeps-one-suite-stack-per-file ()
  "Interleaved events from two files must not share a suite stack.
`node --test' runs files concurrently and one reporter sees them all,
so a stack keyed only by nesting depth gives a test the ancestry of
whichever file started a suite last."
  (skip-unless (executable-find attest-node-executable))
  (let* ((alpha (expand-file-name "alpha.test.mjs" attest-node-test--concurrent-dir))
         (beta (expand-file-name "beta.test.mjs" attest-node-test--concurrent-dir))
         (ids (attest-test-with-run run
                                    (mapcar (lambda (r) (plist-get r :id))
                                            (delq nil (mapcar (lambda (l) (attest-node--parse-line run l))
                                                              (attest-node-test--replay-reporter
                                                               attest-node--reporter)))))))
    (should (member (attest-make-id alpha "alpha suite" "alpha inner" "alpha deep") ids))
    (should (member (attest-make-id alpha "alpha suite" "alpha shallow") ids))
    (should (member (attest-make-id beta "beta suite" "beta inner" "beta deep") ids))
    (should (member (attest-make-id beta "beta suite" "beta shallow") ids))
    (should-not (seq-find (lambda (id)
                            (or (and (equal (attest-id-file id) alpha)
                                     (member "beta suite" (attest-id-names id)))
                                (and (equal (attest-id-file id) beta)
                                     (member "alpha suite" (attest-id-names id)))))
                          ids))))

(ert-deftest attest-node-test-file-p-covers-node-default-glob ()
  "Discovery claims every file `node --test' collects by default.
Node collects `test/' recursively whatever the files are called, plus
the `test\=' and `spec\=' name forms, and nothing under node_modules."
  (dolist (file '("/p/src/a.test.js" "/p/src/a.test.ts" "/p/src/a.spec.tsx"
                  "/p/src/c_test.js" "/p/src/d-test.js" "/p/src/test-b.js"
                  "/p/test.js" "/p/test/foo.js" "/p/test/sub/bar.js"
                  "/p/tests/baz.ts"))
    (should (attest-node-test-file-p file)))
  (dolist (file '("/p/src/plain.js" "/p/src/latest.js" "/p/src/contest.js"
                  "/p/src/protest.ts" "/p/src/testing.js" "/p/src/manifest.js"
                  "/p/attest.js" "/p/src/a.md"
                  "/p/node_modules/x/a.test.js" "/p/node_modules/x/test/y.js"))
    (should-not (attest-node-test-file-p file))))

(ert-deftest attest-node-command-unsets-node-options ()
  "The node command spec removes NODE_OPTIONS from the child environment.
A NODE_OPTIONS inherited from the user\='s shell can break `node --test\='."
  (let* ((spec (attest-node--command (list :backend 'node :scope 'file :root "/repo/"
                                           :file "/repo/src/a.test.ts")))
         (process-environment (append (plist-get spec :env)
                                      (list "NODE_OPTIONS=--require=/breaks/it"))))
    (should (member "NODE_OPTIONS" (plist-get spec :env)))
    (should-not (getenv "NODE_OPTIONS"))))

(provide 'attest-node-test)
;;; attest-node-test.el ends here
