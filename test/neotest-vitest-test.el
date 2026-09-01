;;; neotest-vitest-test.el --- Tests for the vitest backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests replay fixtures/vitest-events.jsonl.  Discovery on
;; fixtures/vitest/src/demo.test.ts must yield the same ids.  The
;; integration test needs fixtures/vitest/node_modules to be installed.

;;; Code:

(require 'test-helper)
(require 'neotest)
(require 'neotest-vitest)
(require 'neotest-treesit)

(defconst neotest-vitest-test--root (neotest-test-fixture "vitest/"))
(defconst neotest-vitest-test--file (neotest-test-fixture "vitest/src/demo.test.ts"))

(defun neotest-vitest-test--results ()
  "Replay the recorded reporter events."
  (let ((run (list :backend 'vitest :scope 'file :root neotest-vitest-test--root
                   :directory neotest-vitest-test--root :state nil)))
    (delq nil (mapcar (lambda (l) (neotest-vitest--parse-line run l))
                      (neotest-test-fixture-lines "vitest-events.jsonl")))))

(ert-deftest neotest-vitest-parses-states ()
  (let ((results (neotest-vitest-test--results)))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("adds" "fails on purpose" "deep passes" "skipped one" "todo one"
                     "top level passes" "throws")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed failed passed skipped todo passed failed)))
    (should (equal (mapcar (lambda (r) (plist-get r :line)) results) '(4 7 12 13 14 18 19)))))

(ert-deftest neotest-vitest-failures-carry-assertion-frames ()
  (let* ((results (neotest-vitest-test--results))
         (fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose")) results))
         (throws (seq-find (lambda (r) (equal (plist-get r :name) "throws")) results)))
    (should (equal (plist-get fail :id) (neotest-make-id neotest-vitest-test--file "math" "fails on purpose")))
    (should (equal (plist-get fail :location) '(9 . 15)))
    (should (string-prefix-p "expected 2 to be 3" (plist-get fail :message)))
    (should (equal (plist-get throws :location) '(20 . 9)))))

(ert-deftest neotest-vitest-discovery-matches-runner-ids ()
  (skip-unless (treesit-language-available-p 'typescript))
  (with-temp-buffer
    (insert-file-contents neotest-vitest-test--file)
    (setq buffer-file-name neotest-vitest-test--file)
    (typescript-ts-mode)
    (let* ((query (neotest-node--query))
           (positions (neotest-treesit-positions (current-buffer) (car query) (cdr query)))
           (tests (mapcar (lambda (p) (plist-get p :id))
                          (seq-filter (lambda (p) (eq (plist-get p :type) 'test)) positions)))
           (reported (mapcar (lambda (r) (plist-get r :id)) (neotest-vitest-test--results))))
      (should (equal (sort tests #'string<) (sort reported #'string<))))))

(ert-deftest neotest-vitest-scoped-runs-drop-filtered-tests ()
  (let* ((target (neotest-make-id neotest-vitest-test--file "math" "adds"))
         (run (list :backend 'vitest :scope 'test :root neotest-vitest-test--root
                    :position (list :id target :type 'test)))
         (results (delq nil (mapcar (lambda (l) (neotest-vitest--parse-line run l))
                                    (neotest-test-fixture-lines "vitest-events.jsonl")))))
    (should (equal (mapcar (lambda (r) (plist-get r :id)) results) (list target))))
  (let* ((ns (neotest-make-id neotest-vitest-test--file "math" "nested"))
         (run (list :backend 'vitest :scope 'namespace :root neotest-vitest-test--root
                    :position (list :id ns :type 'namespace)))
         (results (delq nil (mapcar (lambda (l) (neotest-vitest--parse-line run l))
                                    (neotest-test-fixture-lines "vitest-events.jsonl")))))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("deep passes" "skipped one" "todo one")))))

(ert-deftest neotest-vitest-name-patterns ()
  (should (equal (neotest-vitest--name-pattern (list :id "/f::math::adds" :type 'test)) "^math adds$"))
  (should (equal (neotest-vitest--name-pattern (list :id "/f::math::nested" :type 'namespace)) "^math nested( |$)"))
  (should (equal (neotest-vitest--name-pattern (list (list :id "/f::math::adds") (list :id "/f::throws")))
                 "^(math adds|throws)$")))

(ert-deftest neotest-vitest-command-uses-local-binary ()
  (skip-unless (file-executable-p (expand-file-name "node_modules/.bin/vitest" neotest-vitest-test--root)))
  (let* ((spec (neotest-vitest--command
                (list :backend 'vitest :scope 'test :root neotest-vitest-test--root
                      :file neotest-vitest-test--file
                      :position (list :id (neotest-make-id neotest-vitest-test--file "math" "adds") :type 'test))))
         (cmd (plist-get spec :command)))
    (should (string-suffix-p "node_modules/.bin/vitest" (car cmd)))
    (should (equal (last cmd 3) '("-t" "^math adds$" "src/demo.test.ts")))
    (should (eq (plist-get spec :parse-stream) 'stderr))))

(ert-deftest neotest-vitest-predicate-needs-vitest-binary ()
  (skip-unless (file-executable-p (expand-file-name "node_modules/.bin/vitest" neotest-vitest-test--root)))
  (with-temp-buffer
    (setq buffer-file-name neotest-vitest-test--file)
    (typescript-ts-mode)
    (should (eq (neotest-backend-for-buffer) 'vitest)))
  (with-temp-buffer
    (setq buffer-file-name (neotest-test-fixture "demo.test.ts"))
    (typescript-ts-mode)
    (should (eq (neotest-backend-for-buffer) 'node))))

(ert-deftest neotest-vitest-integration-runs-fixture-file ()
  (skip-unless (file-executable-p (expand-file-name "node_modules/.bin/vitest" neotest-vitest-test--root)))
  (let* ((neotest-save-before-run nil)
         (neotest-display-output nil)
         (results nil) (finished nil)
         (neotest-result-hook (list (lambda (_run r) (push r results))))
         (neotest-run-finished-hook (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (setq buffer-file-name neotest-vitest-test--file)
      (setq default-directory neotest-vitest-test--root)
      (typescript-ts-mode)
      (neotest-run 'file))
    (with-timeout (60 (ert-fail "vitest did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (= (length results) 7))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "fails on purpose")) results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :location) '(9 . 15))))
    (with-current-buffer neotest-output-buffer-name
      (should (string-match-p "Failed Tests 2" (buffer-string))))))

(provide 'neotest-vitest-test)
;;; neotest-vitest-test.el ends here
