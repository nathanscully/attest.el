;;; neotest-pytest-test.el --- Tests for the pytest backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests replay fixtures/py-events.jsonl.  Discovery runs on
;; fixtures/py/test_demo.py.  The integration test needs pytest on PATH.

;;; Code:

(require 'test-helper)
(require 'neotest)
(require 'neotest-pytest)

(defconst neotest-pytest-test--root (neotest-test-fixture "py/"))
(defconst neotest-pytest-test--file (neotest-test-fixture "py/test_demo.py"))

(defun neotest-pytest-test--results ()
  "Replay the recorded events and return the results."
  (let ((run (list :backend 'pytest :scope 'file :root neotest-pytest-test--root
                   :directory neotest-pytest-test--root :state nil)))
    (delq nil (mapcar (lambda (l) (neotest-pytest--parse-line run l))
                      (neotest-test-fixture-lines "py-events.jsonl")))))

(ert-deftest neotest-pytest-parses-outcomes ()
  (let ((results (neotest-pytest-test--results)))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("test_adds" "test_fails_on_purpose" "test_skipped" "test_param[1]"
                     "test_param[2]" "test_counts" "test_raises")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed failed skipped passed passed passed failed)))
    (should (cl-every (lambda (r) (equal (plist-get r :file) neotest-pytest-test--file)) results))))

(ert-deftest neotest-pytest-ids-strip-parameters-and-keep-classes ()
  (let* ((results (neotest-pytest-test--results))
         (ids (mapcar (lambda (r) (plist-get r :id)) results))
         (f neotest-pytest-test--file))
    (should (= (cl-count (neotest-make-id f "test_param") ids :test #'equal) 2))
    (should (member (neotest-make-id f "TestScanner" "test_raises") ids))))

(ert-deftest neotest-pytest-failure-location-and-message ()
  (let* ((results (neotest-pytest-test--results))
         (fail (seq-find (lambda (r) (equal (plist-get r :name) "test_fails_on_purpose")) results))
         (raises (seq-find (lambda (r) (equal (plist-get r :name) "test_raises")) results))
         (skipped (seq-find (lambda (r) (equal (plist-get r :name) "test_skipped")) results)))
    (should (equal (plist-get fail :line) 12))
    (should (equal (plist-get fail :location) '(14)))
    (should (string-prefix-p "AssertionError: x should be three" (plist-get fail :message)))
    (should (equal (plist-get raises :location) '(32)))
    (should (equal (plist-get raises :message) "RuntimeError: boom"))
    (should-not (plist-get skipped :message))))

(ert-deftest neotest-pytest-discovery-matches-runner-ids ()
  (skip-unless (treesit-language-available-p 'python))
  (with-temp-buffer
    (insert-file-contents neotest-pytest-test--file)
    (setq buffer-file-name neotest-pytest-test--file)
    (python-ts-mode)
    (let* ((positions (neotest-positions))
           (discovered (mapcar (lambda (p) (plist-get p :id)) positions))
           (reported (delete-dups (mapcar (lambda (r) (plist-get r :id))
                                          (neotest-pytest-test--results)))))
      (should (equal (mapcar (lambda (p) (plist-get p :type)) positions)
                     '(test test test test namespace test test)))
      (should (equal (mapcar (lambda (p) (plist-get p :line)) positions)
                     '(8 12 18 23 27 28 31)))
      (should (equal (sort (seq-filter (lambda (id) (member id reported)) discovered) #'string<)
                     (sort reported #'string<)))
      (should (= (length reported) 6)))))

(ert-deftest neotest-pytest-command-for-scopes ()
  (let* ((base (list :backend 'pytest :root neotest-pytest-test--root :file neotest-pytest-test--file))
         (argv (lambda (props) (plist-get (neotest-pytest--command (append base props)) :command))))
    (should (equal (last (funcall argv '(:scope file))) '("test_demo.py")))
    (should (equal (last (funcall argv (list :scope 'targets
                                             :targets (list (list :id (neotest-make-id neotest-pytest-test--file "TestScanner" "test_raises")
                                                                  :file neotest-pytest-test--file :type 'test)))))
                   '("test_demo.py::TestScanner::test_raises")))
    (should (member "neotest_pytest" (funcall argv '(:scope file))))
    (should (seq-find (lambda (e) (string-prefix-p "PYTHONPATH=" e))
                      (plist-get (neotest-pytest--command (append base '(:scope file))) :env)))))

(ert-deftest neotest-pytest-integration-runs-fixture-file ()
  (skip-unless (executable-find (car neotest-pytest-command)))
  (let* ((neotest-save-before-run nil)
         (neotest-display-output nil)
         (results nil) (finished nil)
         (neotest-result-functions (list (lambda (_run r) (push r results))))
         (neotest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (setq buffer-file-name neotest-pytest-test--file)
      (setq default-directory neotest-pytest-test--root)
      (python-ts-mode)
      (neotest-run 'file))
    (with-timeout (60 (ert-fail "pytest did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (= (length results) 7))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "test_fails_on_purpose")) results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :file) neotest-pytest-test--file))
      (should (equal (plist-get fail :location) '(14))))
    (delete-directory (expand-file-name ".pytest_cache" neotest-pytest-test--root) t)
    (delete-directory (expand-file-name "__pycache__" neotest-pytest-test--root) t)))

(provide 'neotest-pytest-test)
;;; neotest-pytest-test.el ends here
