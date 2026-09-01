;;; neotest-node-test.el --- Tests for the node backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests run against recorded reporter output in fixtures/, never
;; against a live node process.  The integration test at the bottom does
;; spawn node and is skipped when node is not installed.

;;; Code:

(require 'test-helper)
(require 'neotest)
(require 'neotest-node)

(defconst neotest-node-test--file
  "/private/tmp/claude-501/-Users-nathanscully-projects-emacs-neotest/d70bf539-2ac7-420f-8fb6-13c0b2c819ad/scratchpad/probe/demo/src/demo.test.ts"
  "File path recorded inside demo-events.jsonl.")

(defun neotest-node-test--parse-fixture (name)
  "Feed fixture NAME through the parser and return the results in order."
  (neotest-test-with-run run
    (let (results)
      (dolist (line (neotest-test-fixture-lines name))
        (let ((r (neotest-node--parse-line run line)))
          (when r (push r results))))
      (nreverse results))))

(ert-deftest neotest-node-parses-every-test-and-suite ()
  (let ((results (neotest-node-test--parse-fixture "demo-events.jsonl")))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("adds" "fails on purpose" "deep passes" "skipped one"
                     "todo one" "nested" "math" "top level passes" "throws")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed failed passed skipped todo passed failed passed failed)))))

(ert-deftest neotest-node-ids-encode-nesting ()
  (let* ((results (neotest-node-test--parse-fixture "demo-events.jsonl"))
         (ids (mapcar (lambda (r) (plist-get r :id)) results))
         (f neotest-node-test--file))
    (should (member (neotest-make-id f "math" "adds") ids))
    (should (member (neotest-make-id f "math" "nested" "deep passes") ids))
    (should (member (neotest-make-id f "math" "nested") ids))
    (should (member (neotest-make-id f "throws") ids))
    (should-not (member (neotest-make-id f "nested" "deep passes") ids))))

(ert-deftest neotest-node-suites-are-namespaces ()
  (let* ((results (neotest-node-test--parse-fixture "demo-events.jsonl"))
         (math (seq-find (lambda (r) (equal (plist-get r :name) "math")) results))
         (adds (seq-find (lambda (r) (equal (plist-get r :name) "adds")) results)))
    (should (eq (plist-get math :type) 'namespace))
    (should (eq (plist-get adds :type) 'test))
    (should (equal (plist-get math :line) 4))
    (should (equal (plist-get adds :line) 5))))

(ert-deftest neotest-node-failure-carries-message-and-assertion-line ()
  (let* ((results (neotest-node-test--parse-fixture "demo-events.jsonl"))
         (fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose"))
                         results))
         (throws (seq-find (lambda (r) (equal (plist-get r :name) "throws")) results)))
    (should (string-prefix-p "Expected values to be strictly equal"
                             (plist-get fail :message)))
    (should (equal (plist-get fail :location) '(10 . 5)))
    (should (equal (plist-get throws :message) "boom"))
    (should (equal (plist-get throws :location) '(21 . 9)))))

(ert-deftest neotest-node-suite-failure-has-no-location ()
  (let* ((results (neotest-node-test--parse-fixture "demo-events.jsonl"))
         (math (seq-find (lambda (r) (equal (plist-get r :name) "math")) results)))
    (should (eq (plist-get math :status) 'failed))
    (should (equal (plist-get math :message) "1 subtest failed"))
    (should-not (plist-get math :location))))

(ert-deftest neotest-node-ignores-noise-lines ()
  (neotest-test-with-run run
    (should-not (neotest-node--parse-line run ""))
    (should-not (neotest-node--parse-line run "not json"))
    (should-not (neotest-node--parse-line run "{\"type\":\"test:diagnostic\",\"data\":{}}"))
    (should-not (neotest-node--parse-line run "{broken"))))

(ert-deftest neotest-node-name-pattern-anchors-tests-and-namespaces ()
  (should (equal (neotest-node--name-pattern "/f.ts::math::adds" 'test)
                 "--test-name-pattern=^math adds$"))
  (should (equal (neotest-node--name-pattern "/f.ts::math::nested" 'namespace)
                 "--test-name-pattern=^math nested( |$)"))
  (should (equal (neotest-node--name-pattern "/f.ts::a (b) [c]? $1.0" 'test)
                 "--test-name-pattern=^a \\(b\\) \\[c\\]\\? \\$1\\.0$")))

(ert-deftest neotest-node-command-for-scopes ()
  (let* ((root "/repo/")
         (base (list :backend 'node :root root :file "/repo/src/a.test.ts"))
         (argv (lambda (run) (plist-get (neotest-node--command run) :command))))
    (should (equal (last (funcall argv (append base '(:scope file))))
                   '("src/a.test.ts")))
    (should (member "--test-name-pattern=^math adds$"
                    (funcall argv (append base (list :scope 'test
                                                     :position (list :id "/repo/src/a.test.ts::math::adds"
                                                                     :type 'test))))))
    (should (equal (last (funcall argv (append base (list :scope 'project
                                                          :files '("/repo/src/a.test.ts"
                                                                   "/repo/src/b.test.ts"))))
                         2)
                   '("src/a.test.ts" "src/b.test.ts")))
    (let ((cmd (funcall argv (append base (list :scope 'results
                                                :results (list (list :id "/repo/src/a.test.ts::x" :file "/repo/src/a.test.ts")
                                                               (list :id "/repo/src/b.test.ts::y" :file "/repo/src/b.test.ts")))))))
      (should (member "--test-name-pattern=^x$" cmd))
      (should (member "--test-name-pattern=^y$" cmd))
      (should (equal (last cmd 2) '("src/a.test.ts" "src/b.test.ts"))))
    (should (eq (plist-get (neotest-node--command (append base '(:scope file))) :parse-stream)
                'stderr))))

(ert-deftest neotest-node-root-prefers-package-json ()
  (let* ((dir (make-temp-file "neotest-root" t))
         (pkg (expand-file-name "pkg/" dir))
         (file (expand-file-name "src/a.test.ts" pkg)))
    (make-directory (file-name-directory file) t)
    (write-region "" nil (expand-file-name "package.json" pkg))
    (should (equal (file-truename (neotest-node-root file)) (file-truename pkg)))
    (with-temp-buffer
      (setq buffer-file-name file)
      (typescript-ts-mode)
      (should (string-prefix-p "/" (neotest-project-root)))
      (should (equal (file-truename (neotest-project-root)) (file-truename pkg))))
    (delete-directory dir t)))

(ert-deftest neotest-node-test-file-p ()
  (should (neotest-node-test-file-p "/p/src/scanner.test.ts"))
  (should (neotest-node-test-file-p "/p/src/a.spec.js"))
  (should (neotest-node-test-file-p "/p/src/a_test.mjs"))
  (should-not (neotest-node-test-file-p "/p/src/scanner.ts"))
  (should-not (neotest-node-test-file-p "/p/node_modules/x/a.test.ts")))

(ert-deftest neotest-node-integration-runs-fixture-file ()
  "Spawn node on fixtures/demo.test.ts and check the streamed results."
  (skip-unless (executable-find neotest-node-executable))
  (let* ((file (neotest-test-fixture "demo.test.ts"))
         (neotest-save-before-run nil)
         (neotest-display-output nil)
         (results nil)
         (finished nil)
         (neotest-result-functions (list (lambda (_run r) (push r results))))
         (neotest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (setq buffer-file-name file)
      (setq default-directory neotest-test-fixtures)
      (typescript-ts-mode)
      (neotest-run 'file))
    (with-timeout (30 (ert-fail "node did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (= (length results) 9))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose"))
                          results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :file) file))
      (should (equal (plist-get fail :location) '(10 . 5))))
    (should (eq (plist-get (neotest-last-run) :status) 'finished))
    (with-current-buffer neotest-output-buffer-name
      (should (string-match-p "fails on purpose" (buffer-string))))))

(provide 'neotest-node-test)
;;; neotest-node-test.el ends here
