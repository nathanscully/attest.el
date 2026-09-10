;;; attest-loadpath.el --- Resolve attest's own source directories -*- lexical-binding: t; -*-

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

;; A source checkout keeps the core, the backends and the consumers in
;; subdirectories of this one, so requiring any of them needs those
;; directories on `load-path' first.  Every file that starts a require
;; chain requires this one before anything else, so putting the directory
;; holding `attest.el' on `load-path' is enough:
;;
;;   (add-to-list 'load-path "/path/to/attest/lisp")
;;   (require 'attest-all)   ; or attest, for the core alone
;;
;; Either of those resolves the rest, so a later (require 'attest-node) or
;; a consumer's minor mode needs nothing more.  A backend or consumer
;; cannot be the very first feature required from a source checkout,
;; because Emacs has to find its file before the file can add its own
;; directory; require `attest' or `attest-all' first.
;;
;; An installed package is flat and already on `load-path', where adding
;; these directories finds nothing and does nothing.

;;; Code:

(defconst attest-source-directories
  '("core" "backends/shared" "backends/node" "backends/vitest"
    "backends/cargo" "backends/pytest" "consumers")
  "Subdirectories holding attest\\='s sources in a source checkout.
An installed package has none of them and needs none.")

(defun attest-add-source-directories ()
  "Put this file\\='s sibling source directories on `load-path'.
Skips the directories an installed package does not have, and returns the
ones it added."
  (let ((root (file-name-directory (or load-file-name buffer-file-name
                                       (locate-library "attest-loadpath"))))
        added)
    (dolist (directory attest-source-directories)
      (let ((path (expand-file-name directory root)))
        (when (and (file-directory-p path) (not (member path load-path)))
          (add-to-list 'load-path path)
          (push path added))))
    (nreverse added)))

(attest-add-source-directories)

(provide 'attest-loadpath)
;;; attest-loadpath.el ends here
