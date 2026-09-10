;;; attest-contract-test.el --- Tests for the backend extension contract -*- lexical-binding: t; -*-

;;; Commentary:

;; Registration is the public boundary for language backends.  These tests
;; keep malformed definitions from becoming delayed runtime failures.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-all)

(ert-deftest attest-contract-validates-bundled-backends ()
  "Every bundled backend satisfies the required registration contract."
  (dolist (name '(node vitest rust pytest))
    (should (eq name (attest-validate-backend name))))
  (should (equal (sort (mapcar #'symbol-name (attest-validate-backends)) #'string<)
                 (sort (mapcar #'symbol-name (attest-backend-names)) #'string<))))

(ert-deftest attest-contract-rejects-malformed-registration ()
  "Registration rejects invalid names, plists and required properties."
  (should-error
   (attest-register-backend "not-a-symbol") :type 'error)
  (should-error
   (attest-register-backend 'odd
                            :predicate #'ignore
                            :test-file-p)
   :type 'error)
  (should-error
   (attest-register-backend 'missing
                            :predicate #'ignore
                            :test-file-p #'ignore
                            :query '(javascript ((identifier) @name))
                            :command #'ignore)
   :type 'error)
  (should-not (alist-get 'odd attest--backends))
  (should-not (alist-get 'missing attest--backends)))

(ert-deftest attest-contract-validates-optional-properties ()
  "Optional backend properties have the documented types."
  (let ((attest--backends (copy-tree attest--backends)))
    (should (eq 'custom
                (attest-register-backend
                 'custom
                 :predicate #'ignore
                 :test-file-p #'ignore
                 :query '(javascript ((identifier) @name))
                 :command #'ignore
                 :parse-line #'ignore
                 :plan #'ignore
                 :test-failure-exit-codes '(1 101))))
    (should (eq 'custom (attest-validate-backend 'custom)))
    (should-error
     (attest-register-backend
      'bad-plan
      :predicate #'ignore
      :test-file-p #'ignore
      :query '(javascript ((identifier) @name))
      :command #'ignore
      :parse-line #'ignore
      :plan "not-callable")
     :type 'error)
    (should-error
     (attest-register-backend
      'bad-query
      :predicate #'ignore
      :test-file-p #'ignore
      :query '(javascript . malformed)
      :command #'ignore
      :parse-line #'ignore)
     :type 'error)
    (should-error
     (attest-register-backend
      'bad-exit-codes
      :predicate #'ignore
      :test-file-p #'ignore
      :query '(javascript ((identifier) @name))
      :command #'ignore
      :parse-line #'ignore
      :test-failure-exit-codes '(1 "101"))
     :type 'error)))

(ert-deftest attest-contract-validates-invocation-specs ()
  "Invocation plans reject malformed process specifications early."
  (let ((spec '(:command ("node" "--test")
                         :directory "/tmp"
                         :env ("NODE_ENV=test")
                         :parse-stream stderr)))
    (should (eq spec (attest-validate-invocation-spec spec)))
    (should (equal (list spec)
                   (attest-validate-invocation-plan spec)))
    (should (equal (list spec)
                   (attest-validate-invocation-plan
                    (list :invocations (list spec))))))
  (dolist (spec '((:command ())
                  (:command ("node") :env (42))
                  (:command ("node") :parse-stream both)
                  (:command ("node") :directory 42)))
    (should-error (attest-validate-invocation-spec spec) :type 'error))
  (should-error (attest-validate-invocation-plan '(:invocations nil))
                :type 'error))

(ert-deftest attest-contract-accepts-a-string-query ()
  "The contract documents `(LANG . QUERY)\=', and `treesit-query-capture\='
takes a string pattern as readily as an s-expression, so registration
must accept both spellings."
  (let ((attest--backends nil)
        (attest--backend-revisions (make-hash-table :test 'eq)))
    (attest-register-backend
     'string-query
     :predicate #'ignore
     :test-file-p #'ignore
     :query '(javascript . "((identifier) @name)")
     :command #'ignore
     :parse-line #'ignore)
    (should (eq (attest-validate-backend 'string-query) 'string-query))
    (should-error
     (attest-register-backend
      'nil-language
      :predicate #'ignore
      :test-file-p #'ignore
      :query '(nil . "((identifier) @name)")
      :command #'ignore
      :parse-line #'ignore)
     :type 'error)))

(ert-deftest attest-source-directories-cover-every-source ()
  "Every source directory must be one `attest-all\=' puts on `load-path\='.
The README tells a consumer to add `lisp/\=' and require `attest-all\=',
so a backend added in a new subdirectory has to be listed here or that
recipe silently stops working."
  (let* ((root (file-name-directory (locate-library "attest-all")))
         (sources (directory-files-recursively root "\\.el\\'"))
         (missing nil))
    (dolist (file sources)
      (let ((directory (directory-file-name
                        (file-relative-name (file-name-directory file) root))))
        (unless (or (equal directory ".")
                    (member directory attest-source-directories))
          (push directory missing))))
    (should-not (delete-dups missing))))

(ert-deftest attest-lisp-features-load-from-one-load-path-entry ()
  "Each feature in `lisp/\=' must load with only that directory on `load-path\='.
`(use-package attest ...)\=' requires `attest\=' first, which pulled
`attest-run\=' from `core/\=' before anything had added it."
  (let* ((root (file-name-directory (locate-library "attest-loadpath")))
         (emacs (expand-file-name invocation-name invocation-directory)))
    (dolist (feature '("attest" "attest-all"))
      (let ((status (call-process
                     emacs nil nil nil "-Q" "--batch"
                     "--eval" (format "(add-to-list 'load-path %S)" root)
                     "--eval" (format "(require '%s)" feature))))
        (should (equal (cons feature status) (cons feature 0)))))))

(provide 'attest-contract-test)
;;; attest-contract-test.el ends here
