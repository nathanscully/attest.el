;;; neotest-rust-test.el --- Tests for the cargo backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests replay fixtures/rs-events.jsonl against positions
;; discovered in fixtures/rs.  The integration test spawns cargo.

;;; Code:

(require 'test-helper)
(require 'neotest)
(require 'neotest-rust)

(defconst neotest-rust-test--root (neotest-test-fixture "rs/"))
(defconst neotest-rust-test--lib (neotest-test-fixture "rs/src/lib.rs"))
(defconst neotest-rust-test--scanner (neotest-test-fixture "rs/src/scanner.rs"))

(defun neotest-rust-test--project-run ()
  "Return a project-scope run over the fixture crate with its index built."
  (let ((run (list :backend 'rust :scope 'project :root neotest-rust-test--root
                   :directory neotest-rust-test--root :state nil :result-ids nil
                   :files (list neotest-rust-test--lib neotest-rust-test--scanner))))
    (neotest-rust--command run)
    run))

(ert-deftest neotest-rust-module-prefix ()
  (let ((root "/crate/"))
    (should (equal (neotest-rust-module-prefix "/crate/src/lib.rs" root) ""))
    (should (equal (neotest-rust-module-prefix "/crate/src/main.rs" root) ""))
    (should (equal (neotest-rust-module-prefix "/crate/src/scanner.rs" root) "scanner"))
    (should (equal (neotest-rust-module-prefix "/crate/src/a/mod.rs" root) "a"))
    (should (equal (neotest-rust-module-prefix "/crate/src/a/b.rs" root) "a::b"))
    (should (equal (neotest-rust-module-prefix "/crate/tests/it.rs" root) ""))))

(ert-deftest neotest-rust-discovers-attributed-functions ()
  (skip-unless (treesit-language-available-p 'rust))
  (let ((positions (neotest-file-positions neotest-rust-test--lib 'rust)))
    (should (equal (mapcar (lambda (p) (neotest-id-names (plist-get p :id))) positions)
                   '(("tests") ("tests" "adds") ("tests" "fails_on_purpose")
                     ("tests" "ignored_one") ("tests" "panics"))))
    (should (equal (mapcar (lambda (p) (plist-get p :line)) positions) '(8 12 17 24 28)))))

(ert-deftest neotest-rust-results-resolve-to-files-and-lines ()
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((run (neotest-rust-test--project-run))
         (neotest-result-hook nil)
         (results (delq nil (mapcar (lambda (l)
                                      (when-let* ((r (neotest-rust--parse-line run l)))
                                        (neotest--record run r)
                                        r))
                                    (neotest-test-fixture-lines "rs-events.jsonl")))))
    (should (equal (mapcar (lambda (r) (plist-get r :runner-name)) results)
                   '("scanner::tests::counts_words" "tests::adds" "tests::ignored_one"
                     "tests::panics" "tests::fails_on_purpose")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed passed skipped passed failed)))
    (let ((words (car results))
          (fail (car (last results))))
      (should (equal (plist-get words :file) neotest-rust-test--scanner))
      (should (equal (plist-get words :id) (neotest-make-id neotest-rust-test--scanner "tests" "counts_words")))
      (should (equal (plist-get words :line) 8))
      (should (equal (plist-get fail :file) neotest-rust-test--lib))
      (should (equal (plist-get fail :line) 17))
      (should (equal (plist-get fail :location) '(19 . 9)))
      (should (string-match-p "x should be three" (plist-get fail :message))))))

(ert-deftest neotest-rust-command-for-scopes ()
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((base (list :backend 'rust :root neotest-rust-test--root :file neotest-rust-test--scanner))
         (argv (lambda (props) (plist-get (neotest-rust--command (append base props)) :command))))
    (should (member "scanner" (funcall argv '(:scope file))))
    (should-not (member "src" (funcall argv (list :scope 'file :file neotest-rust-test--lib))))
    (let ((cmd (funcall argv (list :scope 'test
                                   :position (list :id (neotest-make-id neotest-rust-test--scanner "tests" "counts_words")
                                                   :file neotest-rust-test--scanner :type 'test)))))
      (should (equal (seq-drop-while (lambda (a) (not (equal a "--"))) cmd)
                     '("--" "--exact" "scanner::tests::counts_words" "-Z" "unstable-options" "--format=json" "--report-time"))))
    (should (member "RUSTC_BOOTSTRAP=1" (plist-get (neotest-rust--command (append base '(:scope file))) :env)))))

(ert-deftest neotest-rust-integration-runs-fixture-crate ()
  (skip-unless (executable-find neotest-rust-cargo-executable))
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((neotest-save-before-run nil)
         (neotest-display-output nil)
         (results nil) (finished nil)
         (neotest-result-hook (list (lambda (_run r) (push r results))))
         (neotest-run-finished-hook (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (setq buffer-file-name neotest-rust-test--lib)
      (setq default-directory neotest-rust-test--root)
      (rust-ts-mode)
      (neotest-run 'file))
    (with-timeout (120 (ert-fail "cargo did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (= (length results) 5))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "fails_on_purpose")) results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :file) neotest-rust-test--lib))
      (should (equal (plist-get fail :location) '(19 . 9))))
    (with-current-buffer neotest-output-buffer-name
      (should (string-match-p "panicked at src/lib.rs:19:9" (buffer-string))))))

(provide 'neotest-rust-test)
;;; neotest-rust-test.el ends here
