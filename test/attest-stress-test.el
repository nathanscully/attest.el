;;; attest-stress-test.el --- Live stress suite for every backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs each backend against the projects under stress/ and checks what
;; the small fixtures cannot: id parity between discovery and the runner
;; over many files, single-target precision, namespace subtrees, volume
;; and discovery timing.  Every test spawns the real runner and skips
;; when its toolchain is missing.  Run with the `stress' command; the
;; `ert' command does not load this file.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-node)
(require 'attest-vitest)
(require 'attest-rust)
(require 'attest-pytest)

(defconst attest-stress-dir
  (expand-file-name "../stress/" (file-name-directory
                                  (or load-file-name buffer-file-name)))
  "Directory holding one project per runner.")

(defconst attest-stress-timeout 600
  "Seconds to wait for a runner before failing the test.")

(defconst attest-stress-discovery-budget-ms 60
  "Upper bound on the mean discovery cost per file.")

(defun attest-stress--file (path)
  "Return the absolute path of PATH under `attest-stress-dir'."
  (expand-file-name path attest-stress-dir))

(defun attest-stress--run (file mode scope &rest props)
  "Run SCOPE with PROPS from a buffer visiting FILE in MODE and wait.
Returns the finished run plist."
  (let ((attest-test-run-timeout attest-stress-timeout))
    (apply #'attest-test-run-and-wait file mode scope props)))

(defun attest-stress--test-ids (results)
  "Return the ids of the test results in RESULTS."
  (mapcar (lambda (r)
            (replace-regexp-in-string
             "\\[.*\\]\\'" ""
             (or (plist-get r :definition-id) (plist-get r :id))))
          (seq-filter (lambda (r) (eq (plist-get r :type) 'test)) results)))

(defun attest-stress--discovered-ids (run)
  "Return the ids of every test position in the files RUN covers."
  (mapcan (lambda (file)
            (attest-stress--test-ids (attest-run-file-positions run file)))
          (attest-run-files run)))

(defun attest-stress--static-p (id)
  "Return non-nil unless ID lives in a file of runtime-generated names."
  (not (string-match-p "dynamic" (attest-id-file id))))

(defun attest-stress--position (file backend id)
  "Return the position with ID discovered in FILE by BACKEND."
  (or (seq-find (lambda (p) (equal (plist-get p :id) id))
                (attest-file-positions file backend))
      (ert-fail (format "Discovery did not find %s" id))))

(defun attest-stress--check-parity (run &optional unreported)
  "Assert that RUN reported exactly the static tests discovery found.
UNREPORTED lists ids discovery finds but the runner never reports,
such as tests inside a suite the runner skips wholesale."
  (should (eq (plist-get run :status) 'finished))
  (let ((reported (seq-filter #'attest-stress--static-p
                              (delete-dups (attest-stress--test-ids
                                            (attest-run-results run)))))
        (discovered (seq-filter #'attest-stress--static-p
                                (attest-stress--discovered-ids run))))
    (should (> (length reported) 500))
    (should (equal (seq-difference reported discovered) nil))
    (should (equal (seq-difference discovered reported) unreported))))

(defun attest-stress--check-dynamic-mismatch (run)
  "Assert that RUN's dynamically named tests do not all match discovery.
This documents the known gap; the test carrying it expects failure."
  (let ((reported (seq-remove #'attest-stress--static-p
                              (delete-dups (attest-stress--test-ids
                                            (attest-run-results run)))))
        (discovered (seq-remove #'attest-stress--static-p
                                (attest-stress--discovered-ids run))))
    (should (equal (seq-difference reported discovered) nil))
    (should (equal (seq-difference discovered reported) nil))))

(defun attest-stress--check-many (run file)
  "Assert that RUN reported all 500 tests of FILE."
  (should (= 500 (length (delete-dups
                          (seq-filter (lambda (id) (equal (attest-id-file id) file))
                                      (attest-stress--test-ids
                                       (attest-run-results run))))))))

(defun attest-stress--check-single-target (file mode backend id)
  "Run the test ID from FILE in MODE with BACKEND and expect only it back."
  (let* ((pos (attest-stress--position file backend id))
         (run (attest-stress--run file mode 'targets :targets (list pos))))
    (should (eq (plist-get run :status) 'finished))
    (should (equal (delete-dups (attest-stress--test-ids (attest-run-results run)))
                   (list id)))))

(defun attest-stress--check-namespace-target (file mode backend id)
  "Run namespace ID from FILE in MODE with BACKEND; expect its subtree."
  (let* ((pos (attest-stress--position file backend id))
         (run (attest-stress--run file mode 'targets :targets (list pos)))
         (prefix (concat id attest-id-separator))
         (expected (seq-filter (lambda (test-id) (string-prefix-p prefix test-id))
                               (attest-stress--test-ids
                                (attest-file-positions file backend))))
         (reported (delete-dups (attest-stress--test-ids (attest-run-results run)))))
    (should (eq (plist-get run :status) 'finished))
    (should (> (length expected) 1))
    (should (equal (sort reported #'string<) (sort expected #'string<)))))

(defun attest-stress--check-rerun-failed (run)
  "Rerun the failures of RUN and expect exactly those ids back."
  (let* ((failed (delete-dups (attest-stress--test-ids
                               (attest-run-failed-results run))))
         (finished nil)
         (attest-save-before-run nil)
         (attest-display-output nil)
         (attest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (should (> (length failed) 5))
    (attest-rerun-failed)
    (with-timeout (attest-stress-timeout (ert-fail "Rerun did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (let ((rerun (attest-last-run)))
      (should (eq (plist-get rerun :scope) 'targets))
      (should (equal (sort (delete-dups (attest-stress--test-ids
                                         (attest-run-results rerun)))
                           #'string<)
                     (sort (copy-sequence failed) #'string<))))))

(defun attest-stress--check-discovery-timing (backend root)
  "Parse every test file of BACKEND under ROOT once and check the mean cost."
  (let* ((files (attest--project-test-files backend root))
         (seconds (car (benchmark-run 1
                         (dolist (file files)
                           (attest-file-positions file backend)))))
         (per-file (/ (* 1000 seconds) (float (length files)))))
    (should (> (length files) 30))
    (message "%s discovery: %d files, %.1f ms per file" backend (length files) per-file)
    (should (< per-file attest-stress-discovery-budget-ms))))

;;;; node

(defconst attest-stress-node-root (attest-stress--file "node/"))
(defconst attest-stress-node-many (attest-stress--file "node/src/many.test.ts"))

(defun attest-stress-node--available-p ()
  "Return non-nil when node and the TypeScript grammar are usable."
  (and (executable-find attest-node-executable)
       (treesit-language-available-p 'typescript)))

(defconst attest-stress-node-unreported
  (let ((naming (attest-stress--file "node/src/naming.test.ts"))
        (skipping (attest-stress--file "node/src/skipping.test.ts")))
    (list (attest-make-id naming "skipped suite" "never runs")
          (attest-make-id skipping "outer skipped suite" "direct child never runs")
          (attest-make-id skipping "outer skipped suite"
                          "nested under a skipped suite" "grandchild never runs")
          (attest-make-id skipping "suite around a skipped suite"
                          "inner skipped suite" "inner child never runs")))
  "Ids discovery finds that `node --test' never reports.
Node emits one skipped event for a `describe.skip' suite and nothing
for the tests inside it, so discovery lists them and the runner does
not.  Sorted the way `attest-stress--check-parity' compares.")

(ert-deftest attest-stress-node-project-parity ()
  (skip-unless (attest-stress-node--available-p))
  (let ((run (attest-stress--run attest-stress-node-many #'typescript-ts-mode 'project)))
    (attest-stress--check-parity run attest-stress-node-unreported)
    (attest-stress--check-many run attest-stress-node-many)
    (attest-stress--check-rerun-failed run)))

(ert-deftest attest-stress-node-collects-test-directory ()
  "A project run covers `test/' files that carry no test suffix.
`node --test' collects everything under `test/' whatever it is called,
so discovery must claim those files too."
  (skip-unless (attest-stress-node--available-p))
  (let* ((plain (attest-stress--file "node/test/plain.js"))
         (deeper (attest-stress--file "node/test/nested/deeper.js"))
         (files (attest--project-test-files 'node attest-stress-node-root)))
    (should (member plain files))
    (should (member deeper files))
    (let* ((run (attest-stress--run attest-stress-node-many #'typescript-ts-mode 'project))
           (ids (attest-stress--test-ids (attest-run-results run))))
      (should (member (attest-make-id plain "directory collected by name"
                                      "passes without a test suffix")
                      ids))
      (should (member (attest-make-id deeper "nested under the test directory"
                                      "still collected")
                      ids)))))

(ert-deftest attest-stress-node-dynamic-names ()
  :expected-result :failed
  (skip-unless (attest-stress-node--available-p))
  (attest-stress--check-dynamic-mismatch
   (attest-stress--run (attest-stress--file "node/src/dynamic.test.ts")
                       #'typescript-ts-mode 'file)))

(ert-deftest attest-stress-node-single-target ()
  (skip-unless (attest-stress-node--available-p))
  (attest-stress--check-single-target
   attest-stress-node-many #'typescript-ts-mode 'node
   (attest-make-id attest-stress-node-many "group 03" "case 017")))

(ert-deftest attest-stress-node-namespace-target ()
  (skip-unless (attest-stress-node--available-p))
  (attest-stress--check-namespace-target
   attest-stress-node-many #'typescript-ts-mode 'node
   (attest-make-id attest-stress-node-many "group 03")))

(ert-deftest attest-stress-node-discovery-timing ()
  (skip-unless (treesit-language-available-p 'typescript))
  (attest-stress--check-discovery-timing 'node attest-stress-node-root))

;;;; vitest

(defconst attest-stress-vitest-root (attest-stress--file "vitest/packages/alpha/"))
(defconst attest-stress-vitest-many
  (attest-stress--file "vitest/packages/alpha/src/many.test.ts"))
(defconst attest-stress-vitest-beta
  (attest-stress--file "vitest/packages/beta/src/beta.test.ts"))

(defun attest-stress-vitest--available-p ()
  "Return non-nil when the workspace has vitest installed."
  (and (file-executable-p (expand-file-name "node_modules/.bin/vitest"
                                            attest-stress-vitest-root))
       (treesit-language-available-p 'typescript)))

(ert-deftest attest-stress-vitest-project-parity ()
  (skip-unless (attest-stress-vitest--available-p))
  (let ((run (attest-stress--run attest-stress-vitest-many #'typescript-ts-mode 'project)))
    (should (equal (plist-get run :root) attest-stress-vitest-root))
    (attest-stress--check-parity run)
    (attest-stress--check-many run attest-stress-vitest-many)
    (attest-stress--check-rerun-failed run)))

(ert-deftest attest-stress-vitest-dynamic-names ()
  :expected-result :failed
  (skip-unless (attest-stress-vitest--available-p))
  (attest-stress--check-dynamic-mismatch
   (attest-stress--run (attest-stress--file "vitest/packages/alpha/src/dynamic.test.ts")
                       #'typescript-ts-mode 'file)))

(ert-deftest attest-stress-vitest-single-target ()
  (skip-unless (attest-stress-vitest--available-p))
  (attest-stress--check-single-target
   attest-stress-vitest-many #'typescript-ts-mode 'vitest
   (attest-make-id attest-stress-vitest-many "group 03" "case 017")))

(ert-deftest attest-stress-vitest-namespace-target ()
  (skip-unless (attest-stress-vitest--available-p))
  (attest-stress--check-namespace-target
   attest-stress-vitest-many #'typescript-ts-mode 'vitest
   (attest-make-id attest-stress-vitest-many "group 03")))

(ert-deftest attest-stress-vitest-workspace-member-root ()
  (skip-unless (attest-stress-vitest--available-p))
  (let ((run (attest-stress--run attest-stress-vitest-beta #'typescript-ts-mode 'file)))
    (should (equal (plist-get run :root) (file-name-directory
                                          (directory-file-name
                                           (file-name-directory attest-stress-vitest-beta)))))
    (should (equal (sort (attest-stress--test-ids (attest-run-results run)) #'string<)
                   (list (attest-make-id attest-stress-vitest-beta "beta" "beta fails")
                         (attest-make-id attest-stress-vitest-beta "beta" "same"))))))

;;;; cargo

(defconst attest-stress-cargo-root (attest-stress--file "cargo/crates/alpha/"))
(defconst attest-stress-cargo-many (attest-stress--file "cargo/crates/alpha/src/many.rs"))

(defun attest-stress-cargo--available-p ()
  "Return non-nil when cargo and the Rust grammar are usable."
  (and (executable-find attest-rust-cargo-executable)
       (treesit-language-available-p 'rust)))

(ert-deftest attest-stress-cargo-project-parity ()
  (skip-unless (attest-stress-cargo--available-p))
  (let ((run (attest-stress--run attest-stress-cargo-many #'rust-ts-mode 'project)))
    (should (equal (plist-get run :root) attest-stress-cargo-root))
    (attest-stress--check-parity run)
    (attest-stress--check-many run attest-stress-cargo-many)
    (attest-stress--check-rerun-failed run)))

(ert-deftest attest-stress-cargo-single-target ()
  (skip-unless (attest-stress-cargo--available-p))
  (attest-stress--check-single-target
   attest-stress-cargo-many #'rust-ts-mode 'rust
   (attest-make-id attest-stress-cargo-many "tests" "group_03" "case_017")))

(ert-deftest attest-stress-cargo-namespace-target ()
  (skip-unless (attest-stress-cargo--available-p))
  (attest-stress--check-namespace-target
   attest-stress-cargo-many #'rust-ts-mode 'rust
   (attest-make-id attest-stress-cargo-many "tests" "group_03")))

(ert-deftest attest-stress-cargo-discovery-timing ()
  (skip-unless (treesit-language-available-p 'rust))
  (attest-stress--check-discovery-timing 'rust attest-stress-cargo-root))

;;;; pytest

(defconst attest-stress-pytest-root (attest-stress--file "pytest/"))
(defconst attest-stress-pytest-many (attest-stress--file "pytest/tests/test_many.py"))

(defun attest-stress-pytest--available-p ()
  "Return non-nil when pytest and the Python grammar are usable."
  (and (executable-find (car attest-pytest-command))
       (treesit-language-available-p 'python)))

(ert-deftest attest-stress-pytest-project-parity ()
  (skip-unless (attest-stress-pytest--available-p))
  (let ((run (attest-stress--run attest-stress-pytest-many #'python-ts-mode 'project)))
    (should (equal (plist-get run :root) attest-stress-pytest-root))
    (attest-stress--check-parity run)
    (attest-stress--check-many run attest-stress-pytest-many)
    (attest-stress--check-rerun-failed run)))

(ert-deftest attest-stress-pytest-dynamic-names ()
  :expected-result :failed
  (skip-unless (attest-stress-pytest--available-p))
  (attest-stress--check-dynamic-mismatch
   (attest-stress--run (attest-stress--file "pytest/tests/test_dynamic.py")
                       #'python-ts-mode 'file)))

(ert-deftest attest-stress-pytest-single-target ()
  (skip-unless (attest-stress-pytest--available-p))
  (attest-stress--check-single-target
   attest-stress-pytest-many #'python-ts-mode 'pytest
   (attest-make-id attest-stress-pytest-many "TestGroup03" "test_case_017")))

(ert-deftest attest-stress-pytest-namespace-target ()
  (skip-unless (attest-stress-pytest--available-p))
  (attest-stress--check-namespace-target
   attest-stress-pytest-many #'python-ts-mode 'pytest
   (attest-make-id attest-stress-pytest-many "TestGroup03")))

(ert-deftest attest-stress-pytest-discovery-timing ()
  (skip-unless (treesit-language-available-p 'python))
  (attest-stress--check-discovery-timing 'pytest attest-stress-pytest-root))

(provide 'attest-stress-test)
;;; attest-stress-test.el ends here
