;;; neotest-stress-test.el --- Live stress suite for every backend -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs each backend against the projects under stress/ and checks what
;; the small fixtures cannot: id parity between discovery and the runner
;; over many files, single-target precision, namespace subtrees, volume
;; and discovery timing.  Every test spawns the real runner and skips
;; when its toolchain is missing.  Run with `make stress'; `make test'
;; does not load this file.

;;; Code:

(require 'test-helper)
(require 'neotest)
(require 'neotest-node)
(require 'neotest-vitest)
(require 'neotest-rust)
(require 'neotest-pytest)

(defconst neotest-stress-dir
  (expand-file-name "../stress/" (file-name-directory
                                  (or load-file-name buffer-file-name)))
  "Directory holding one project per runner.")

(defconst neotest-stress-timeout 600
  "Seconds to wait for a runner before failing the test.")

(defconst neotest-stress-discovery-budget-ms 60
  "Upper bound on the mean discovery cost per file.")

(defun neotest-stress--file (path)
  "Return the absolute path of PATH under `neotest-stress-dir'."
  (expand-file-name path neotest-stress-dir))

(defun neotest-stress--run (file mode scope &rest props)
  "Run SCOPE with PROPS from a buffer visiting FILE in MODE and wait.
Returns the finished run plist."
  (let ((neotest-save-before-run nil)
        (neotest-display-output nil)
        (finished nil))
    (with-temp-buffer
      (insert-file-contents file)
      (setq buffer-file-name file)
      (setq default-directory (file-name-directory file))
      (funcall mode)
      (let ((neotest-run-finished-functions
             (list (lambda (_run) (setq finished t)))))
        (apply #'neotest-run scope props)
        (with-timeout (neotest-stress-timeout
                       (ert-fail (format "Runner did not finish for %s" file)))
          (while (not finished) (accept-process-output nil 0.1)))))
    (neotest-last-run)))

(defun neotest-stress--test-ids (results)
  "Return the ids of the test results in RESULTS."
  (mapcar (lambda (r) (plist-get r :id))
          (seq-filter (lambda (r) (eq (plist-get r :type) 'test)) results)))

(defun neotest-stress--discovered-ids (run)
  "Return the ids of every test position in the files RUN covers."
  (mapcan (lambda (file)
            (neotest-stress--test-ids (neotest-run-file-positions run file)))
          (neotest-run-files run)))

(defun neotest-stress--static-p (id)
  "Return non-nil unless ID lives in a file of runtime-generated names."
  (not (string-match-p "dynamic" (neotest-id-file id))))

(defun neotest-stress--position (file backend id)
  "Return the position with ID discovered in FILE by BACKEND."
  (or (seq-find (lambda (p) (equal (plist-get p :id) id))
                (neotest-file-positions file backend))
      (ert-fail (format "Discovery did not find %s" id))))

(defun neotest-stress--check-parity (run &optional unreported)
  "Assert that RUN reported exactly the static tests discovery found.
UNREPORTED lists ids discovery finds but the runner never reports,
such as tests inside a suite the runner skips wholesale."
  (should (eq (plist-get run :status) 'finished))
  (let ((reported (seq-filter #'neotest-stress--static-p
                              (delete-dups (neotest-stress--test-ids
                                            (neotest-run-results run)))))
        (discovered (seq-filter #'neotest-stress--static-p
                                (neotest-stress--discovered-ids run))))
    (should (> (length reported) 500))
    (should (equal (seq-difference reported discovered) nil))
    (should (equal (seq-difference discovered reported) unreported))))

(defun neotest-stress--check-dynamic-mismatch (run)
  "Assert that RUN's dynamically named tests do not all match discovery.
This documents the known gap; the test carrying it expects failure."
  (let ((reported (seq-remove #'neotest-stress--static-p
                              (delete-dups (neotest-stress--test-ids
                                            (neotest-run-results run)))))
        (discovered (seq-remove #'neotest-stress--static-p
                                (neotest-stress--discovered-ids run))))
    (should (equal (seq-difference reported discovered) nil))
    (should (equal (seq-difference discovered reported) nil))))

(defun neotest-stress--check-many (run file)
  "Assert that RUN reported all 500 tests of FILE."
  (should (= 500 (length (delete-dups
                          (seq-filter (lambda (id) (equal (neotest-id-file id) file))
                                      (neotest-stress--test-ids
                                       (neotest-run-results run))))))))

(defun neotest-stress--check-single-target (file mode backend id)
  "Run the test ID from FILE in MODE with BACKEND and expect only it back."
  (let* ((pos (neotest-stress--position file backend id))
         (run (neotest-stress--run file mode 'targets :targets (list pos))))
    (should (eq (plist-get run :status) 'finished))
    (should (equal (delete-dups (neotest-stress--test-ids (neotest-run-results run)))
                   (list id)))))

(defun neotest-stress--check-namespace-target (file mode backend id)
  "Run namespace ID from FILE in MODE with BACKEND; expect its subtree."
  (let* ((pos (neotest-stress--position file backend id))
         (run (neotest-stress--run file mode 'targets :targets (list pos)))
         (prefix (concat id neotest-id-separator))
         (expected (seq-filter (lambda (test-id) (string-prefix-p prefix test-id))
                               (neotest-stress--test-ids
                                (neotest-file-positions file backend))))
         (reported (delete-dups (neotest-stress--test-ids (neotest-run-results run)))))
    (should (eq (plist-get run :status) 'finished))
    (should (> (length expected) 1))
    (should (equal (sort reported #'string<) (sort expected #'string<)))))

(defun neotest-stress--check-rerun-failed (run)
  "Rerun the failures of RUN and expect exactly those ids back."
  (let* ((failed (delete-dups (neotest-stress--test-ids
                               (neotest-run-failed-results run))))
         (finished nil)
         (neotest-save-before-run nil)
         (neotest-display-output nil)
         (neotest-run-finished-functions (list (lambda (_run) (setq finished t)))))
    (should (> (length failed) 5))
    (neotest-rerun-failed)
    (with-timeout (neotest-stress-timeout (ert-fail "Rerun did not finish"))
      (while (not finished) (accept-process-output nil 0.1)))
    (let ((rerun (neotest-last-run)))
      (should (eq (plist-get rerun :scope) 'targets))
      (should (equal (sort (delete-dups (neotest-stress--test-ids
                                         (neotest-run-results rerun)))
                           #'string<)
                     (sort (copy-sequence failed) #'string<))))))

(defun neotest-stress--check-discovery-timing (backend root)
  "Parse every test file of BACKEND under ROOT once and check the mean cost."
  (let* ((files (neotest--project-test-files backend root))
         (seconds (car (benchmark-run 1
                         (dolist (file files)
                           (neotest-file-positions file backend)))))
         (per-file (/ (* 1000 seconds) (float (length files)))))
    (should (> (length files) 30))
    (message "%s discovery: %d files, %.1f ms per file" backend (length files) per-file)
    (should (< per-file neotest-stress-discovery-budget-ms))))

;;;; node

(defconst neotest-stress-node-root (neotest-stress--file "node/"))
(defconst neotest-stress-node-many (neotest-stress--file "node/src/many.test.ts"))

(defun neotest-stress-node--available-p ()
  "Return non-nil when node and the TypeScript grammar are usable."
  (and (executable-find neotest-node-executable)
       (treesit-language-available-p 'typescript)))

(ert-deftest neotest-stress-node-project-parity ()
  (skip-unless (neotest-stress-node--available-p))
  (let ((run (neotest-stress--run neotest-stress-node-many #'typescript-ts-mode 'project)))
    (neotest-stress--check-parity
     run (list (neotest-make-id (neotest-stress--file "node/src/naming.test.ts")
                                "skipped suite" "never runs")))
    (neotest-stress--check-many run neotest-stress-node-many)
    (neotest-stress--check-rerun-failed run)))

(ert-deftest neotest-stress-node-dynamic-names ()
  :expected-result :failed
  (skip-unless (neotest-stress-node--available-p))
  (neotest-stress--check-dynamic-mismatch
   (neotest-stress--run (neotest-stress--file "node/src/dynamic.test.ts")
                        #'typescript-ts-mode 'file)))

(ert-deftest neotest-stress-node-single-target ()
  (skip-unless (neotest-stress-node--available-p))
  (neotest-stress--check-single-target
   neotest-stress-node-many #'typescript-ts-mode 'node
   (neotest-make-id neotest-stress-node-many "group 03" "case 017")))

(ert-deftest neotest-stress-node-namespace-target ()
  (skip-unless (neotest-stress-node--available-p))
  (neotest-stress--check-namespace-target
   neotest-stress-node-many #'typescript-ts-mode 'node
   (neotest-make-id neotest-stress-node-many "group 03")))

(ert-deftest neotest-stress-node-discovery-timing ()
  (skip-unless (treesit-language-available-p 'typescript))
  (neotest-stress--check-discovery-timing 'node neotest-stress-node-root))

;;;; vitest

(defconst neotest-stress-vitest-root (neotest-stress--file "vitest/packages/alpha/"))
(defconst neotest-stress-vitest-many
  (neotest-stress--file "vitest/packages/alpha/src/many.test.ts"))
(defconst neotest-stress-vitest-beta
  (neotest-stress--file "vitest/packages/beta/src/beta.test.ts"))

(defun neotest-stress-vitest--available-p ()
  "Return non-nil when the workspace has vitest installed."
  (and (file-executable-p (expand-file-name "node_modules/.bin/vitest"
                                            neotest-stress-vitest-root))
       (treesit-language-available-p 'typescript)))

(ert-deftest neotest-stress-vitest-project-parity ()
  (skip-unless (neotest-stress-vitest--available-p))
  (let ((run (neotest-stress--run neotest-stress-vitest-many #'typescript-ts-mode 'project)))
    (should (equal (plist-get run :root) neotest-stress-vitest-root))
    (neotest-stress--check-parity run)
    (neotest-stress--check-many run neotest-stress-vitest-many)
    (neotest-stress--check-rerun-failed run)))

(ert-deftest neotest-stress-vitest-dynamic-names ()
  :expected-result :failed
  (skip-unless (neotest-stress-vitest--available-p))
  (neotest-stress--check-dynamic-mismatch
   (neotest-stress--run (neotest-stress--file "vitest/packages/alpha/src/dynamic.test.ts")
                        #'typescript-ts-mode 'file)))

(ert-deftest neotest-stress-vitest-single-target ()
  (skip-unless (neotest-stress-vitest--available-p))
  (neotest-stress--check-single-target
   neotest-stress-vitest-many #'typescript-ts-mode 'vitest
   (neotest-make-id neotest-stress-vitest-many "group 03" "case 017")))

(ert-deftest neotest-stress-vitest-namespace-target ()
  (skip-unless (neotest-stress-vitest--available-p))
  (neotest-stress--check-namespace-target
   neotest-stress-vitest-many #'typescript-ts-mode 'vitest
   (neotest-make-id neotest-stress-vitest-many "group 03")))

(ert-deftest neotest-stress-vitest-workspace-member-root ()
  (skip-unless (neotest-stress-vitest--available-p))
  (let ((run (neotest-stress--run neotest-stress-vitest-beta #'typescript-ts-mode 'file)))
    (should (equal (plist-get run :root) (file-name-directory
                                          (directory-file-name
                                           (file-name-directory neotest-stress-vitest-beta)))))
    (should (equal (sort (neotest-stress--test-ids (neotest-run-results run)) #'string<)
                   (list (neotest-make-id neotest-stress-vitest-beta "beta" "beta fails")
                         (neotest-make-id neotest-stress-vitest-beta "beta" "same"))))))

;;;; cargo

(defconst neotest-stress-cargo-root (neotest-stress--file "cargo/crates/alpha/"))
(defconst neotest-stress-cargo-many (neotest-stress--file "cargo/crates/alpha/src/many.rs"))

(defun neotest-stress-cargo--available-p ()
  "Return non-nil when cargo and the Rust grammar are usable."
  (and (executable-find neotest-rust-cargo-executable)
       (treesit-language-available-p 'rust)))

(ert-deftest neotest-stress-cargo-project-parity ()
  (skip-unless (neotest-stress-cargo--available-p))
  (let ((run (neotest-stress--run neotest-stress-cargo-many #'rust-ts-mode 'project)))
    (should (equal (plist-get run :root) neotest-stress-cargo-root))
    (neotest-stress--check-parity run)
    (neotest-stress--check-many run neotest-stress-cargo-many)
    (neotest-stress--check-rerun-failed run)))

(ert-deftest neotest-stress-cargo-single-target ()
  (skip-unless (neotest-stress-cargo--available-p))
  (neotest-stress--check-single-target
   neotest-stress-cargo-many #'rust-ts-mode 'rust
   (neotest-make-id neotest-stress-cargo-many "tests" "group_03" "case_017")))

(ert-deftest neotest-stress-cargo-namespace-target ()
  (skip-unless (neotest-stress-cargo--available-p))
  (neotest-stress--check-namespace-target
   neotest-stress-cargo-many #'rust-ts-mode 'rust
   (neotest-make-id neotest-stress-cargo-many "tests" "group_03")))

(ert-deftest neotest-stress-cargo-discovery-timing ()
  (skip-unless (treesit-language-available-p 'rust))
  (neotest-stress--check-discovery-timing 'rust neotest-stress-cargo-root))

;;;; pytest

(defconst neotest-stress-pytest-root (neotest-stress--file "pytest/"))
(defconst neotest-stress-pytest-many (neotest-stress--file "pytest/tests/test_many.py"))

(defun neotest-stress-pytest--available-p ()
  "Return non-nil when pytest and the Python grammar are usable."
  (and (executable-find (car neotest-pytest-command))
       (treesit-language-available-p 'python)))

(ert-deftest neotest-stress-pytest-project-parity ()
  (skip-unless (neotest-stress-pytest--available-p))
  (let ((run (neotest-stress--run neotest-stress-pytest-many #'python-ts-mode 'project)))
    (should (equal (plist-get run :root) neotest-stress-pytest-root))
    (neotest-stress--check-parity run)
    (neotest-stress--check-many run neotest-stress-pytest-many)
    (neotest-stress--check-rerun-failed run)))

(ert-deftest neotest-stress-pytest-dynamic-names ()
  :expected-result :failed
  (skip-unless (neotest-stress-pytest--available-p))
  (neotest-stress--check-dynamic-mismatch
   (neotest-stress--run (neotest-stress--file "pytest/tests/test_dynamic.py")
                        #'python-ts-mode 'file)))

(ert-deftest neotest-stress-pytest-single-target ()
  (skip-unless (neotest-stress-pytest--available-p))
  (neotest-stress--check-single-target
   neotest-stress-pytest-many #'python-ts-mode 'pytest
   (neotest-make-id neotest-stress-pytest-many "TestGroup03" "test_case_017")))

(ert-deftest neotest-stress-pytest-namespace-target ()
  (skip-unless (neotest-stress-pytest--available-p))
  (neotest-stress--check-namespace-target
   neotest-stress-pytest-many #'python-ts-mode 'pytest
   (neotest-make-id neotest-stress-pytest-many "TestGroup03")))

(ert-deftest neotest-stress-pytest-discovery-timing ()
  (skip-unless (treesit-language-available-p 'python))
  (neotest-stress--check-discovery-timing 'pytest neotest-stress-pytest-root))

(provide 'neotest-stress-test)
;;; neotest-stress-test.el ends here
