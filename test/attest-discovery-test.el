;;; attest-discovery-test.el --- Tests for tree-sitter discovery in core -*- lexical-binding: t; -*-

;;; Commentary:

;; Discovery must produce the same ids the node reporter produces, so
;; the fixture source is the file the recorded events came from.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-node)

(defmacro attest-discovery-test--with-fixture (&rest body)
  "Evaluate BODY in a typescript buffer visiting fixtures/demo.test.ts."
  `(progn
     (skip-unless (treesit-language-available-p 'typescript))
     (with-temp-buffer
       (insert-file-contents (attest-test-fixture "demo.test.ts"))
       (setq buffer-file-name (attest-test-fixture "demo.test.ts"))
       (typescript-ts-mode)
       ,@body)))

(ert-deftest attest-discovery-discovers-tests-and-namespaces ()
  (attest-discovery-test--with-fixture
   (let* ((positions (attest-positions))
          (f (attest-test-fixture "demo.test.ts")))
     (should (equal (mapcar (lambda (p) (plist-get p :id)) positions)
                    (list (attest-make-id f "math")
                          (attest-make-id f "math" "adds")
                          (attest-make-id f "math" "fails on purpose")
                          (attest-make-id f "math" "nested")
                          (attest-make-id f "math" "nested" "deep passes")
                          (attest-make-id f "math" "nested" "skipped one")
                          (attest-make-id f "math" "nested" "todo one")
                          (attest-make-id f "top level passes")
                          (attest-make-id f "throws"))))
     (should (equal (mapcar (lambda (p) (plist-get p :line)) positions)
                    '(4 5 8 12 13 14 15 19 20)))
     (should (equal (mapcar (lambda (p) (plist-get p :type)) positions)
                    '(namespace test test namespace test test test test test))))))

(ert-deftest attest-discovery-ids-match-runner-ids ()
  "Every runner result id must be discoverable and vice versa."
  (attest-discovery-test--with-fixture
   (let* ((discovered (mapcar (lambda (p) (attest-id-names (plist-get p :id)))
                              (attest-positions)))
          (run (list :backend 'node :state nil))
          (reported (delq nil
                          (mapcar (lambda (line)
                                    (when-let* ((r (attest-node--parse-line run line)))
                                      (attest-id-names (plist-get r :id))))
                                  (attest-test-fixture-lines "demo-events.jsonl")))))
     (should (equal (sort discovered :key #'prin1-to-string :lessp #'string<)
                    (sort reported :key #'prin1-to-string :lessp #'string<))))))

(ert-deftest attest-discovery-position-at-point-prefers-innermost ()
  (attest-discovery-test--with-fixture
   (goto-char (point-min))
   (search-forward "strictEqual(x, 3)")
   (should (equal (plist-get (attest-position-at-point) :name) "fails on purpose"))
   (goto-char (point-min))
   (search-forward "describe(\"nested\"")
   (should (equal (plist-get (attest-position-at-point) :name) "nested"))
   (goto-char (point-min))
   (search-forward "import")
   (should-not (attest-position-at-point))))

(ert-deftest attest-discovery-name-text-handles-quotes-and-templates ()
  (skip-unless (treesit-language-available-p 'typescript))
  (with-temp-buffer
    (insert "test('single', () => {});\ntest(`tpl ${x}`, () => {});\ntest(name, () => {});\n"
            "test(\"back\\\\slash \\\"quoted\\\" \\u0041 tab\\tend\", () => {});\n")
    (setq buffer-file-name "/tmp/x.test.ts")
    (typescript-ts-mode)
    (should (equal (mapcar (lambda (p) (plist-get p :name)) (attest-positions))
                   '("single" "tpl ${x}" "name" "back\\slash \"quoted\" A tab\tend")))))

(ert-deftest attest-discovery-file-positions-without-a-buffer ()
  (skip-unless (treesit-language-available-p 'typescript))
  (let ((file (attest-test-fixture "demo.test.ts")))
    (should-not (find-buffer-visiting file))
    (should (= (length (attest-file-positions file)) 9))
    (should (equal (plist-get (car (attest-file-positions file 'node)) :name) "math"))
    (should-not (attest-file-positions "/nonexistent/x.test.ts" 'node))))

(ert-deftest attest-discovery-run-index-parses-each-file-once ()
  (skip-unless (treesit-language-available-p 'typescript))
  (let* ((file (attest-test-fixture "demo.test.ts"))
         (run (list :backend 'node :scope 'file :file file))
         (calls 0))
    (cl-letf* ((orig (symbol-function 'attest-file-positions))
               ((symbol-function 'attest-file-positions)
                (lambda (&rest args) (cl-incf calls) (apply orig args))))
      (should (attest-run-position run (attest-make-id file "math" "adds")))
      (should (attest-run-position run (attest-make-id file "throws")))
      (should-not (attest-run-position run (attest-make-id file "nope")))
      (should (= calls 1))
      (should (= (length (attest-run-positions run)) 9)))))

(ert-deftest attest-discovery-record-fills-line-from-position ()
  (skip-unless (treesit-language-available-p 'python))
  (let* ((file (attest-test-fixture "py/test_demo.py"))
         (run (list :backend 'pytest :scope 'file :file file :result-ids nil))
         (attest-result-functions nil)
         (result (list :id (attest-make-id file "test_skipped") :status 'skipped
                       :file file :line 17)))
    (require 'attest-pytest)
    (attest--record run result)
    (should (equal (plist-get result :line) 18))
    (should (eq (plist-get result :type) 'test))))

(provide 'attest-discovery-test)
;;; attest-discovery-test.el ends here
