;;; attest-pytest-test.el --- Tests for the pytest backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests replay fixtures/py-events.jsonl.  Discovery runs on
;; fixtures/py/test_demo.py.  The integration test needs pytest on PATH.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-pytest)

(defconst attest-pytest-test--root (attest-test-fixture "py/"))
(defconst attest-pytest-test--file (attest-test-fixture "py/test_demo.py"))

(defun attest-pytest-test--results ()
  "Replay the recorded events and return the results."
  (let ((run (list :backend 'pytest :scope 'file :root attest-pytest-test--root
                   :directory attest-pytest-test--root :state nil)))
    (delq nil (mapcar (lambda (l) (attest-pytest--parse-line run l))
                      (attest-test-fixture-lines "py-events.jsonl")))))

(ert-deftest attest-pytest-parses-outcomes ()
  (let ((results (attest-pytest-test--results)))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("test_adds" "test_fails_on_purpose" "test_skipped" "test_param[1]"
                     "test_param[2]" "test_counts" "test_raises" "test_teardown_fails"
                     "test_teardown_fails")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed failed skipped passed passed passed failed passed failed)))
    (should (cl-every (lambda (r) (equal (plist-get r :file) attest-pytest-test--file)) results))))

(ert-deftest attest-pytest-teardown-failure-overrides-passed-call ()
  (let* ((results (attest-pytest-test--results))
         (teardown (car (last (seq-filter (lambda (r) (equal (plist-get r :name) "test_teardown_fails"))
                                          results)))))
    (should (eq (plist-get teardown :status) 'failed))
    (should (equal (plist-get teardown :message) "RuntimeError: teardown boom"))))

(ert-deftest attest-pytest-ids-strip-parameters-and-keep-classes ()
  (let* ((results (attest-pytest-test--results))
         (ids (mapcar (lambda (r) (plist-get r :id)) results))
         (f attest-pytest-test--file))
    (should (= (cl-count (attest-make-id f "test_param") ids :test #'equal) 2))
    (should (member (attest-make-id f "TestScanner" "test_raises") ids))))

(ert-deftest attest-pytest-failure-location-and-message ()
  (let* ((results (attest-pytest-test--results))
         (fail (seq-find (lambda (r) (equal (plist-get r :name) "test_fails_on_purpose")) results))
         (raises (seq-find (lambda (r) (equal (plist-get r :name) "test_raises")) results))
         (skipped (seq-find (lambda (r) (equal (plist-get r :name) "test_skipped")) results)))
    (should (equal (plist-get fail :line) 12))
    (should (equal (plist-get fail :location) '(14)))
    (should (string-prefix-p "AssertionError: x should be three" (plist-get fail :message)))
    (should (equal (plist-get raises :location) '(32)))
    (should (equal (plist-get raises :message) "RuntimeError: boom"))
    (should-not (plist-get skipped :message))))

(ert-deftest attest-pytest-discovery-matches-runner-ids ()
  (skip-unless (treesit-language-available-p 'python))
  (with-temp-buffer
    (insert-file-contents attest-pytest-test--file)
    (setq buffer-file-name attest-pytest-test--file)
    (python-ts-mode)
    (let* ((positions (attest-positions))
           (discovered (mapcar (lambda (p) (plist-get p :id)) positions))
           (reported (delete-dups (mapcar (lambda (r) (plist-get r :id))
                                          (attest-pytest-test--results)))))
      (should (equal (mapcar (lambda (p) (plist-get p :type)) positions)
                     '(test test test test namespace test test test)))
      (should (equal (mapcar (lambda (p) (plist-get p :line)) positions)
                     '(8 12 18 23 27 28 31 41)))
      (should (equal (sort (seq-filter (lambda (id) (member id reported)) discovered) #'string<)
                     (sort reported #'string<)))
      (should (= (length reported) 7)))))

(ert-deftest attest-pytest-command-for-scopes ()
  (let* ((base (list :backend 'pytest :root attest-pytest-test--root :file attest-pytest-test--file))
         (argv (lambda (props) (plist-get (attest-pytest--command (append base props)) :command))))
    (should (equal (last (funcall argv '(:scope file))) '("test_demo.py")))
    (should (equal (last (funcall argv (list :scope 'targets
                                             :targets (list (list :id (attest-make-id attest-pytest-test--file "TestScanner" "test_raises")
                                                                  :file attest-pytest-test--file :type 'test)))))
                   '("test_demo.py::TestScanner::test_raises")))
    (should (member "attest_pytest" (funcall argv '(:scope file))))
    (should (seq-find (lambda (e) (string-prefix-p "PYTHONPATH=" e))
                      (plist-get (attest-pytest--command (append base '(:scope file))) :env)))))

(ert-deftest attest-pytest-integration-runs-fixture-file ()
  (skip-unless (executable-find (car attest-pytest-command)))
  (let* ((attest-save-before-run nil)
         (attest-display-output nil)
         (results nil) (finished nil)
         (attest-result-functions (list (lambda (_run r) (push r results))))
         (attest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (setq buffer-file-name attest-pytest-test--file)
      (setq default-directory attest-pytest-test--root)
      (python-ts-mode)
      (attest-run 'file))
    (with-timeout (60 (ert-fail "pytest did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (= (length results) 9))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "test_fails_on_purpose")) results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :file) attest-pytest-test--file))
      (should (equal (plist-get fail :location) '(14))))
    (let ((teardown (seq-find (lambda (r) (equal (plist-get r :name) "test_teardown_fails")) results)))
      (should (eq (plist-get teardown :status) 'failed)))
    (delete-directory (expand-file-name ".pytest_cache" attest-pytest-test--root) t)
    (delete-directory (expand-file-name "__pycache__" attest-pytest-test--root) t)))

(provide 'attest-pytest-test)
;;; attest-pytest-test.el ends here
