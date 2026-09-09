;;; package-smoke.el --- Verify the installed artifact -*- lexical-binding: t; -*-

;;; Commentary:

;; Installs the local archive without adding the source checkout to load-path.

;;; Code:

(require 'package)
(setq package-user-dir (make-temp-file "attest-package-" t))
(package-initialize)
(package-install-file (expand-file-name (pop command-line-args-left)))
(unless (commandp 'attest-run-file)
  (error "Missing installed command"))
(require 'attest-all)
(dolist (backend '(node vitest rust pytest))
  (unless (assq backend attest--backends) (error "Missing backend %s" backend)))
(dolist (file (list attest-node--reporter attest-vitest--reporter
                   (expand-file-name "attest_pytest.py" attest-pytest--plugin-dir)))
  (unless (and (file-readable-p file) (file-in-directory-p file package-user-dir))
    (error "Missing installed asset %s" file)))
(message "Installed package smoke test passed")

;;; package-smoke.el ends here
