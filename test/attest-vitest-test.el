;;; attest-vitest-test.el --- Tests for the vitest backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests replay fixtures/vitest-events.jsonl.  Discovery on
;; fixtures/vitest/src/demo.test.ts must yield the same ids.  The
;; integration test needs fixtures/vitest/node_modules to be installed.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-vitest)

(defconst attest-vitest-test--root (attest-test-fixture "vitest/"))
(defconst attest-vitest-test--file (attest-test-fixture "vitest/src/demo.test.ts"))

(defun attest-vitest-test--results ()
  "Replay the recorded reporter events."
  (let ((run (list :backend 'vitest :scope 'file :root attest-vitest-test--root
                   :directory attest-vitest-test--root :state nil)))
    (delq nil (mapcar (lambda (l) (attest-vitest--parse-line run l))
                      (attest-test-fixture-lines "vitest-events.jsonl")))))

(ert-deftest attest-vitest-parses-states ()
  (let ((results (attest-vitest-test--results)))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("adds" "fails on purpose" "deep passes" "skipped one" "todo one"
                     "top level passes" "throws")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed failed passed skipped todo passed failed)))
    (should (equal (mapcar (lambda (r) (plist-get r :line)) results) '(4 7 12 13 14 18 19)))))

(ert-deftest attest-vitest-failures-carry-assertion-frames ()
  (let* ((results (attest-vitest-test--results))
         (fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose")) results))
         (throws (seq-find (lambda (r) (equal (plist-get r :name) "throws")) results)))
    (should (equal (plist-get fail :id) (attest-make-id attest-vitest-test--file "math" "fails on purpose")))
    (should (equal (plist-get fail :location) '(9 . 15)))
    (should (string-prefix-p "expected 2 to be 3" (plist-get fail :message)))
    (should (equal (plist-get throws :location) '(20 . 9)))))

(ert-deftest attest-vitest-discovery-matches-runner-ids ()
  (skip-unless (treesit-language-available-p 'typescript))
  (with-temp-buffer
    (insert-file-contents attest-vitest-test--file)
    (setq buffer-file-name attest-vitest-test--file)
    (typescript-ts-mode)
    (let* ((positions (attest-file-positions attest-vitest-test--file 'vitest))
           (tests (mapcar (lambda (p) (plist-get p :id))
                          (seq-filter (lambda (p) (eq (plist-get p :type) 'test)) positions)))
           (reported (mapcar (lambda (r) (plist-get r :id)) (attest-vitest-test--results))))
      (should (equal (sort tests #'string<) (sort reported #'string<))))))

(ert-deftest attest-vitest-scoped-runs-drop-filtered-tests ()
  (let* ((target (attest-make-id attest-vitest-test--file "math" "adds"))
         (run (list :backend 'vitest :scope 'targets :root attest-vitest-test--root
                    :targets (list (list :id target :type 'test))))
         (results (delq nil (mapcar (lambda (l) (attest-vitest--parse-line run l))
                                    (attest-test-fixture-lines "vitest-events.jsonl")))))
    (should (equal (mapcar (lambda (r) (plist-get r :id)) results) (list target))))
  (let* ((ns (attest-make-id attest-vitest-test--file "math" "nested"))
         (run (list :backend 'vitest :scope 'targets :root attest-vitest-test--root
                    :targets (list (list :id ns :type 'namespace))))
         (results (delq nil (mapcar (lambda (l) (attest-vitest--parse-line run l))
                                    (attest-test-fixture-lines "vitest-events.jsonl")))))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("deep passes" "skipped one" "todo one")))))

(ert-deftest attest-vitest-name-patterns ()
  (should (equal (attest-vitest--name-pattern (list (list :id "/f::math::adds" :type 'test))) "^math adds$"))
  (should (equal (attest-vitest--name-pattern (list (list :id "/f::math::nested" :type 'namespace))) "^math nested( |$)"))
  (should (equal (attest-vitest--name-pattern (list (list :id "/f::math::adds" :type 'test)
                                                     (list :id "/f::throws" :type 'test)))
                 "^(?:math adds$|throws$)")))

(ert-deftest attest-vitest-command-uses-local-binary ()
  (skip-unless (file-executable-p (expand-file-name "node_modules/.bin/vitest" attest-vitest-test--root)))
  (let* ((spec (attest-vitest--command
                (list :backend 'vitest :scope 'targets :root attest-vitest-test--root
                      :file attest-vitest-test--file
                      :targets (list (list :id (attest-make-id attest-vitest-test--file "math" "adds")
                                           :file attest-vitest-test--file :type 'test)))))
         (cmd (plist-get spec :command)))
    (should (string-suffix-p "node_modules/.bin/vitest" (car cmd)))
    (should (equal (last cmd 3) '("-t" "^math adds$" "src/demo.test.ts")))
    (should (eq (plist-get spec :parse-stream) 'stderr))))

(ert-deftest attest-vitest-predicate-needs-vitest-binary ()
  (skip-unless (file-executable-p (expand-file-name "node_modules/.bin/vitest" attest-vitest-test--root)))
  (with-temp-buffer
    (setq buffer-file-name attest-vitest-test--file)
    (typescript-ts-mode)
    (should (eq (attest-backend-for-buffer) 'vitest)))
  (with-temp-buffer
    (setq buffer-file-name (attest-test-fixture "demo.test.ts"))
    (typescript-ts-mode)
    (should (eq (attest-backend-for-buffer) 'node))))

(ert-deftest attest-vitest-integration-runs-fixture-file ()
  (skip-unless (file-executable-p (expand-file-name "node_modules/.bin/vitest" attest-vitest-test--root)))
  (let* ((attest-save-before-run nil)
         (attest-display-output nil)
         (results nil) (finished nil)
         (attest-result-functions (list (lambda (_run r) (push r results))))
         (attest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (setq buffer-file-name attest-vitest-test--file)
      (setq default-directory attest-vitest-test--root)
      (typescript-ts-mode)
      (attest-run 'file))
    (with-timeout (60 (ert-fail "vitest did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (= (length results) 7))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose")) results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :location) '(9 . 15))))
    (with-current-buffer attest-output-buffer-name
      (should (string-match-p "Failed Tests 2" (buffer-string))))))

(provide 'attest-vitest-test)
;;; attest-vitest-test.el ends here
