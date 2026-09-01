;;; neotest-treesit-test.el --- Tests for treesit discovery -*- lexical-binding: t; -*-

;;; Commentary:

;; Discovery must produce the same ids the node reporter produces, so
;; the fixture source is the file the recorded events came from.

;;; Code:

(require 'test-helper)
(require 'neotest)
(require 'neotest-node)
(require 'neotest-treesit)

(defmacro neotest-treesit-test--with-fixture (&rest body)
  "Evaluate BODY in a typescript buffer visiting fixtures/demo.test.ts."
  `(progn
     (skip-unless (treesit-language-available-p 'typescript))
     (with-temp-buffer
       (insert-file-contents (neotest-test-fixture "demo.test.ts"))
       (setq buffer-file-name (neotest-test-fixture "demo.test.ts"))
       (typescript-ts-mode)
       ,@body)))

(ert-deftest neotest-treesit-discovers-tests-and-namespaces ()
  (neotest-treesit-test--with-fixture
   (let* ((positions (neotest-positions))
          (f (neotest-test-fixture "demo.test.ts")))
     (should (equal (mapcar (lambda (p) (plist-get p :id)) positions)
                    (list (neotest-make-id f "math")
                          (neotest-make-id f "math" "adds")
                          (neotest-make-id f "math" "fails on purpose")
                          (neotest-make-id f "math" "nested")
                          (neotest-make-id f "math" "nested" "deep passes")
                          (neotest-make-id f "math" "nested" "skipped one")
                          (neotest-make-id f "math" "nested" "todo one")
                          (neotest-make-id f "top level passes")
                          (neotest-make-id f "throws"))))
     (should (equal (mapcar (lambda (p) (plist-get p :line)) positions)
                    '(4 5 8 12 13 14 15 19 20)))
     (should (equal (mapcar (lambda (p) (plist-get p :type)) positions)
                    '(namespace test test namespace test test test test test))))))

(ert-deftest neotest-treesit-ids-match-runner-ids ()
  "Every runner result id must be discoverable and vice versa."
  (neotest-treesit-test--with-fixture
   (let* ((discovered (mapcar (lambda (p) (neotest-id-names (plist-get p :id)))
                              (neotest-positions)))
          (run (list :backend 'node :state nil))
          (reported (delq nil
                          (mapcar (lambda (line)
                                    (when-let* ((r (neotest-node--parse-line run line)))
                                      (neotest-id-names (plist-get r :id))))
                                  (neotest-test-fixture-lines "demo-events.jsonl")))))
     (should (equal (sort discovered :key #'prin1-to-string :lessp #'string<)
                    (sort reported :key #'prin1-to-string :lessp #'string<))))))

(ert-deftest neotest-treesit-position-at-point-prefers-innermost ()
  (neotest-treesit-test--with-fixture
   (goto-char (point-min))
   (search-forward "strictEqual(x, 3)")
   (should (equal (plist-get (neotest-position-at-point) :name) "fails on purpose"))
   (goto-char (point-min))
   (search-forward "describe(\"nested\"")
   (should (equal (plist-get (neotest-position-at-point) :name) "nested"))
   (goto-char (point-min))
   (search-forward "import")
   (should-not (neotest-position-at-point))))

(ert-deftest neotest-treesit-name-text-handles-quotes-and-templates ()
  (skip-unless (treesit-language-available-p 'typescript))
  (with-temp-buffer
    (insert "test('single', () => {});\ntest(`tpl ${x}`, () => {});\ntest(name, () => {});\n")
    (setq buffer-file-name "/tmp/x.test.ts")
    (typescript-ts-mode)
    (should (equal (mapcar (lambda (p) (plist-get p :name)) (neotest-positions))
                   '("single" "tpl ${x}" "name")))))

(provide 'neotest-treesit-test)
;;; neotest-treesit-test.el ends here
