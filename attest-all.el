;;; attest-all.el --- Load attest with every bundled backend -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/nathanscully/attest.el

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

;;; Commentary:

;; One entry point that loads the core, every bundled backend and every
;; consumer.  Equivalent to requiring the eight files by hand.
;;
;;   (require 'attest-all)
;;   (global-attest-flymake-mode 1)
;;   (global-attest-status-mode 1)
;;
;; Backends register on load and are chosen per buffer, so loading one
;; whose runner is absent costs nothing but the load.

;;; Code:

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
