;;; attest-outcome-test.el --- Tests for run outcome reduction -*- lexical-binding: t; -*-

;;; Commentary:

;; Lifecycle status and test outcome are deliberately separate.  These tests
;; cover clean, failed, empty, cancelled and incomplete attempts.

;;; Code:

(require 'test-helper)
(require 'attest)

(defun attest-outcome-test--run (status &optional results errors)
  "Build a RUN with STATUS, RESULTS and ERRORS for outcome tests."
  (let ((run (list :status status :result-ids nil :results nil :errors errors))
        (table (make-hash-table :test 'equal)))
    (dolist (result results)
      (let ((id (attest-result-case-id result)))
        (puthash id result table)
        (plist-put run :result-ids
                   (cons id (plist-get run :result-ids)))))
    (plist-put run :results table)
    run))

(ert-deftest attest-run-outcome-passes-clean-results ()
  "A finished run with passing tests is complete and passed."
  (let* ((run (attest-outcome-test--run
               'finished
               '((:id "one" :type test :status passed))))
         (summary (attest-run-summary run)))
    (should (attest-run-complete-p run))
    (should (eq 'passed (attest-run-outcome run)))
    (should (= 1 (plist-get summary :passed)))
    (should (= 1 (plist-get summary :tests)))
    (should (plist-get summary :complete-p))))

(ert-deftest attest-run-outcome-fails-on-test-failure ()
  "A complete run with a failed test has failed outcome."
  (let ((run (attest-outcome-test--run
              'finished
              '((:id "one" :type test :status failed)))))
    (should (attest-run-complete-p run))
    (should (eq 'failed (attest-run-outcome run)))
    (should (= 1 (plist-get (attest-run-summary run) :failed)))))

(ert-deftest attest-run-outcome-marks-zero-tests-explicitly ()
  "A clean run with no test results is empty, not passed."
  (let ((run (attest-outcome-test--run 'finished)))
    (should (attest-run-complete-p run))
    (should (eq 'empty (attest-run-outcome run)))
    (should (= 0 (plist-get (attest-run-summary run) :tests)))))

(ert-deftest attest-run-outcome-separates-errors-and-cancellation ()
  "Errors are incomplete while killed runs are cancelled."
  (let ((error-run (attest-outcome-test--run
                    'finished
                    '((:id "one" :type test :status passed))
                    '("malformed event")))
        (failed-run (attest-outcome-test--run 'error))
        (killed-run (attest-outcome-test--run 'killed)))
    (should-not (attest-run-complete-p error-run))
    (should (eq 'incomplete (attest-run-outcome error-run)))
    (should (eq 'error (attest-run-outcome failed-run)))
    (should (eq 'cancelled (attest-run-outcome killed-run)))
    (should (equal '("malformed event")
                   (plist-get (attest-run-summary error-run) :errors)))))

(provide 'attest-outcome-test)
;;; attest-outcome-test.el ends here
