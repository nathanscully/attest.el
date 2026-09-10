;;; attest-all.el --- Load attest with every bundled backend -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/nathanscully/attest.el

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; One entry point that loads the core, every bundled backend and every
;; consumer.  Putting this file's own directory on `load-path' is enough:
;;
;;   (add-to-list 'load-path "/path/to/attest/lisp")
;;   (require 'attest-all)
;;   (global-attest-flymake-mode 1)
;;   (global-attest-status-mode 1)
;;
;; A source checkout keeps the core, the backends and the consumers in
;; subdirectories, so this file adds its own before requiring anything.  An
;; installed package is flat and already on `load-path', where that is a
;; no-op.  Either way a consumer never hand-writes the directory list, which
;; would otherwise break whenever a backend is added.
;;
;; Backends register on load and are chosen per buffer, so loading one
;; whose runner is absent costs nothing but the load.

;;; Code:

(defconst attest-all-source-directories
  '("core" "backends/shared" "backends/node" "backends/vitest"
    "backends/cargo" "backends/pytest" "consumers")
  "Subdirectories holding attest\='s sources in a source checkout.
Empty in an installed package, whose files sit beside this one.")

(defun attest-all--add-source-directories ()
  "Put this file\='s sibling source directories on `load-path'.
Does nothing for the directories an installed package does not have."
  (when-let* ((file (or load-file-name buffer-file-name))
              (root (file-name-directory file)))
    (dolist (directory attest-all-source-directories)
      (let ((path (expand-file-name directory root)))
        (when (file-directory-p path)
          (add-to-list 'load-path path))))))

(attest-all--add-source-directories)

;;;###autoload
(defun attest-all-load ()
  "Load the core, every bundled backend and every consumer.
Requiring this file does the same; this exists so the autoloads name an
entry point a user can call before anything else is loaded."
  (require 'attest-all))

(require 'attest)
(require 'attest-node)
(require 'attest-vitest)
(require 'attest-rust)
(require 'attest-pytest)
(require 'attest-flymake)
(require 'attest-status)
(require 'attest-list)

(provide 'attest-all)
;;; attest-all.el ends here
