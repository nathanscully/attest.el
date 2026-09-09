;;; attest-model-test.el --- Tests for stable result model accessors -*- lexical-binding: t; -*-

;;; Commentary:

;; Result plists remain the wire format for now, while consumers use the
;; explicit case/definition vocabulary exposed by the model accessors.

;;; Code:

(require 'test-helper)
(require 'attest)

(ert-deftest attest-result-accessors-separate-case-and-definition ()
  "Parameterized results expose runtime and source identities separately."
  (let ((result '(:id "case-id"
                  :definition-id "definition-id"
                  :status failed
                  :type test
                  :name "case [1]"
                  :file "/tmp/test.py")))
    (should (equal "case-id" (attest-result-case-id result)))
    (should (equal "definition-id" (attest-result-definition-id result)))
    (should (eq 'failed (attest-result-status result)))
    (should (eq 'test (attest-result-type result)))
    (should (equal "case [1]" (attest-result-name result)))
    (should (equal "/tmp/test.py" (attest-result-file result)))))

(ert-deftest attest-result-accessors-support-legacy-results ()
  "Results without a definition id continue to use their case id."
  (let ((result '(:id "legacy-id" :status passed)))
    (should (equal "legacy-id" (attest-result-case-id result)))
    (should (equal "legacy-id" (attest-result-definition-id result)))))

(ert-deftest attest-invocation-record-keeps-parser-state-and-target ()
  "Invocation records retain state independently of the run plist."
  (let ((state '(:execution-target "crate/lib" :index table))
        (record (attest-invocation-create
                 :status 'running
                 :state '(:execution-target "crate/lib" :index table)
                 :execution-target "crate/lib")))
    (should (equal state (attest-invocation-state record)))
    (should (equal "crate/lib" (attest-invocation-execution-target record)))))

(ert-deftest attest-run-request-captures-selection-fields ()
  "A run exposes its selection through an `attest-request' snapshot."
  (let* ((targets '((:id "test-id" :type test)))
         (files '("/tmp/test.js"))
         (run (list :backend 'node :scope 'targets :file "/tmp/test.js"
                    :root "/tmp/" :buffer (current-buffer)
                    :targets targets :files files))
         (request (attest--request-for-run run)))
    (should (eq 'node (attest-request-backend request)))
    (should (eq 'targets (attest-request-scope request)))
    (should (equal targets (attest-request-targets request)))
    (should (equal '("/tmp/test.js") (attest-request-files request)))
    (setcar files "/tmp/changed.js")
    (setcar (car targets) :changed)
    (should (equal '("/tmp/test.js") (attest-request-files request)))
    (should (equal '((:id "test-id" :type test))
                   (attest-request-targets request)))
    (should (eq request (attest-run-request (plist-put run :request request))))))

(provide 'attest-model-test)
;;; attest-model-test.el ends here
