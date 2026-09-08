;;; attest-rust-test.el --- Tests for the cargo backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Parser tests replay fixtures/rs-events.jsonl against positions
;; discovered in fixtures/rs.  The integration test spawns cargo.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-rust)

(defconst attest-rust-test--root (attest-test-fixture "rs/"))
(defconst attest-rust-test--lib (attest-test-fixture "rs/src/lib.rs"))
(defconst attest-rust-test--scanner (attest-test-fixture "rs/src/scanner.rs"))

(defun attest-rust-test--project-run ()
  "Return a project-scope run over the fixture crate with its index built."
  (let ((run (list :backend 'rust :scope 'project :root attest-rust-test--root
                   :directory attest-rust-test--root :state nil :result-ids nil
                   :files (list attest-rust-test--lib attest-rust-test--scanner))))
    (attest-rust--command run)
    run))

(ert-deftest attest-rust-module-prefix ()
  (let ((root "/crate/"))
    (should (equal (attest-rust-module-prefix "/crate/src/lib.rs" root) ""))
    (should (equal (attest-rust-module-prefix "/crate/src/main.rs" root) ""))
    (should (equal (attest-rust-module-prefix "/crate/src/scanner.rs" root) "scanner"))
    (should (equal (attest-rust-module-prefix "/crate/src/a/mod.rs" root) "a"))
    (should (equal (attest-rust-module-prefix "/crate/src/a/b.rs" root) "a::b"))
    (should (equal (attest-rust-module-prefix "/crate/tests/it.rs" root) ""))))

(ert-deftest attest-rust-discovers-attributed-functions ()
  (skip-unless (treesit-language-available-p 'rust))
  (let ((positions (attest-file-positions attest-rust-test--lib 'rust)))
    (should (equal (mapcar (lambda (p) (attest-id-names (plist-get p :id))) positions)
                   '(("tests") ("tests" "adds") ("tests" "fails_on_purpose")
                     ("tests" "ignored_one") ("tests" "panics"))))
    (should (equal (mapcar (lambda (p) (plist-get p :line)) positions) '(8 12 17 24 28)))))

(ert-deftest attest-rust-results-resolve-to-files-and-lines ()
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((run (attest-rust-test--project-run))
         (attest-result-functions nil)
         (results (delq nil (mapcar (lambda (l)
                                      (when-let* ((r (attest-rust--parse-line run l)))
                                        (attest--record run r)
                                        r))
                                    (attest-test-fixture-lines "rs-events.jsonl")))))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) results)
                   '("counts_words" "adds" "ignored_one" "panics" "fails_on_purpose")))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) results)
                   '(passed passed skipped passed failed)))
    (let ((words (car results))
          (fail (car (last results))))
      (should (equal (plist-get words :file) attest-rust-test--scanner))
      (should (equal (plist-get words :id) (attest-make-id attest-rust-test--scanner "tests" "counts_words")))
      (should (equal (plist-get words :line) 8))
      (should (equal (plist-get fail :file) attest-rust-test--lib))
      (should (equal (plist-get fail :line) 17))
      (should (equal (plist-get fail :location) '(19 . 9)))
      (should (string-match-p "x should be three" (plist-get fail :message))))))

(ert-deftest attest-rust-drops-doc-tests ()
  (skip-unless (treesit-language-available-p 'rust))
  (let ((run (list :backend 'rust :scope 'file :root attest-rust-test--root
                   :file attest-rust-test--lib)))
    (attest-rust--command run)
    (should-not (attest-rust--parse-line
                 run "{\"type\":\"test\",\"event\":\"ok\",\"name\":\"src/lib.rs - add (line 7)\"}"))
    (should (attest-rust--parse-line
             run "{\"type\":\"test\",\"event\":\"ok\",\"name\":\"tests::adds\"}"))))

(ert-deftest attest-rust-command-for-scopes ()
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((base (list :backend 'rust :root attest-rust-test--root :file attest-rust-test--scanner))
         (argv (lambda (props) (plist-get (attest-rust--command (append base props)) :command))))
    (should (member "scanner::" (funcall argv '(:scope file))))
    (should-not (member "src" (funcall argv (list :scope 'file :file attest-rust-test--lib))))
    (let ((cmd (funcall argv (list :scope 'targets
                                   :targets (list (list :id (attest-make-id attest-rust-test--scanner "tests" "counts_words")
                                                        :file attest-rust-test--scanner :type 'test))))))
      (should (equal (seq-drop-while (lambda (a) (not (equal a "--"))) cmd)
                     '("--" "--exact" "scanner::tests::counts_words" "-Z" "unstable-options" "--format=json" "--report-time"))))
    (let ((cmd (funcall argv (list :scope 'targets
                                   :targets (list (list :id (attest-make-id attest-rust-test--scanner "tests")
                                                        :file attest-rust-test--scanner :type 'namespace))))))
      (should (equal (seq-take (seq-drop-while (lambda (a) (not (equal a "--"))) cmd) 2)
                     '("--" "scanner::tests"))))
    (should (equal (plist-get (attest-rust--command (append base '(:scope file))) :env)
                   attest-rust-environment))))

(ert-deftest attest-rust-file-scope-filters-by-module-with-separator ()
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((run (list :backend 'rust :scope 'file :root attest-rust-test--root
                    :file attest-rust-test--scanner))
         (filters (attest-rust--file-filters
                   attest-rust-test--scanner attest-rust-test--root
                   (attest-rust--index run))))
    (should (equal filters '("scanner::")))
    (should-not (member "scanner" filters))))

(ert-deftest attest-rust-file-scope-selects-cargo-target ()
  (let ((root "/crate/"))
    (should (equal (attest-rust--file-selector "/crate/src/lib.rs" root) '("--lib" "--bins")))
    (should (equal (attest-rust--file-selector "/crate/src/main.rs" root) '("--lib" "--bins")))
    (should (equal (attest-rust--file-selector "/crate/src/scanner.rs" root) '("--lib" "--bins")))
    (should (equal (attest-rust--file-selector "/crate/tests/it.rs" root) '("--test" "it")))))

(ert-deftest attest-rust-crate-root-file-scope-narrows-to-lib-and-bins ()
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((run (list :backend 'rust :scope 'file :root attest-rust-test--root
                    :file attest-rust-test--lib))
         (cmd (plist-get (attest-rust--command run) :command)))
    (should (member "--lib" cmd))
    (should (member "--bins" cmd))
    (should (member "--exact" cmd))
    (let ((filters (seq-take-while
                    (lambda (a) (not (equal a "-Z")))
                    (cdr (seq-drop-while (lambda (a) (not (equal a "--"))) cmd)))))
      (should (equal filters
                     '("--exact" "tests::adds" "tests::fails_on_purpose"
                       "tests::ignored_one" "tests::panics"))))))

(ert-deftest attest-rust-crate-root-file-scope-excludes-sibling-modules ()
  "A crate root run names its own tests, so cargo skips other modules."
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((run (list :backend 'rust :scope 'file :root attest-rust-test--root
                    :file attest-rust-test--lib))
         (cmd (plist-get (attest-rust--command run) :command)))
    (should-not (seq-find (lambda (a) (string-prefix-p "scanner" a)) cmd))))

(ert-deftest attest-rust-drops-events-outside-the-run-index ()
  (skip-unless (treesit-language-available-p 'rust))
  (let ((run (list :backend 'rust :scope 'file :root attest-rust-test--root
                   :file attest-rust-test--lib)))
    (attest-rust--command run)
    (should (attest-rust--parse-line
             run "{\"type\":\"test\",\"event\":\"ok\",\"name\":\"tests::adds\"}"))
    (should-not (attest-rust--parse-line
                 run "{\"type\":\"test\",\"event\":\"ok\",\"name\":\"scanner::tests::counts_words\"}"))))

(ert-deftest attest-rust-integration-runs-fixture-crate ()
  (skip-unless (executable-find attest-rust-cargo-executable))
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((attest-save-before-run nil)
         (attest-display-output nil)
         (results nil) (finished nil)
         (attest-result-functions (list (lambda (_run r) (push r results))))
         (attest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (insert-file-contents attest-rust-test--lib)
      (setq buffer-file-name attest-rust-test--lib)
      (setq default-directory attest-rust-test--root)
      (rust-ts-mode)
      (attest-run 'file))
    (with-timeout (120 (ert-fail "cargo did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (equal (sort (mapcar (lambda (r) (plist-get r :name)) results) #'string<)
                   '("adds" "fails_on_purpose" "ignored_one" "panics")))
    (dolist (r results)
      (should (equal (plist-get r :file) attest-rust-test--lib)))
    (let ((fail (seq-find (lambda (r) (equal (plist-get r :name) "fails_on_purpose")) results)))
      (should (eq (plist-get fail :status) 'failed))
      (should (equal (plist-get fail :file) attest-rust-test--lib))
      (should (equal (plist-get fail :location) '(19 . 9))))
    (with-current-buffer attest-output-buffer-name
      (should (string-match-p "panicked at src/lib.rs:19:9" (buffer-string))))))

(ert-deftest attest-rust-integration-file-scope-excludes-sibling-module ()
  (skip-unless (executable-find attest-rust-cargo-executable))
  (skip-unless (treesit-language-available-p 'rust))
  (let* ((attest-save-before-run nil)
         (attest-display-output nil)
         (results nil) (finished nil)
         (attest-result-functions (list (lambda (_run r) (push r results))))
         (attest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (with-temp-buffer
      (insert-file-contents attest-rust-test--scanner)
      (setq buffer-file-name attest-rust-test--scanner)
      (setq default-directory attest-rust-test--root)
      (rust-ts-mode)
      (attest-run 'file))
    (with-timeout (120 (ert-fail "cargo did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (should (equal (mapcar (lambda (r) (plist-get r :id)) results)
                   (list (attest-make-id attest-rust-test--scanner "tests" "counts_words"))))
    (should-not (member "scanner" (plist-get (attest-last-run) :command)))))

(provide 'attest-rust-test)
;;; attest-rust-test.el ends here
