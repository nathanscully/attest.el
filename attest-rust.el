;;; attest-rust.el --- cargo test backend for attest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
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

;; Runs `cargo test' and reads libtest's JSON event stream.  The stream
;; is behind `-Z unstable-options', which stable rustc accepts when
;; RUSTC_BOOTSTRAP=1 is set; cargo2junit and similar tools rely on the
;; same switch.
;;
;; libtest names tests by module path (`scanner::tests::adds') and never
;; mentions files or lines.  The backend maps each name to a position
;; from core's index of the run's files, which gives the id; core then
;; fills line and column from the same position.  Doc tests have no
;; position, since discovery does not read doc comments, and are dropped.

;;; Code:

(require 'attest)

(defgroup attest-rust nil
  "Cargo test backend for attest."
  :group 'attest
  :prefix "attest-rust-")

(defcustom attest-rust-cargo-executable "cargo"
  "Cargo program that runs `cargo test'."
  :type 'string
  :package-version '(attest . "0.1.0"))

(defcustom attest-rust-cargo-args nil
  "Arguments inserted after `cargo test'."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defcustom attest-rust-environment '("RUSTC_BOOTSTRAP=1")
  "Environment entries added to `cargo test'.
The libtest JSON stream this backend reads sits behind
`-Z unstable-options', which a stable rustc only accepts when
RUSTC_BOOTSTRAP=1 is set.  That variable unlocks every unstable rustc
feature for the crate being built, not just this one, and some
organisations ban it outright.  On a nightly toolchain the switch needs
no such override, so set this to nil and put the toolchain selection in
`attest-rust-cargo-args', for example \='(\"+nightly\")."
  :type '(repeat string)
  :package-version '(attest . "0.1.0"))

(defconst attest-rust--query
  '(((mod_item name: (identifier) @namespace.name body: (declaration_list)) @namespace.definition)
    ((attribute_item (attribute) @attr)
     :anchor
     (attribute_item) :*
     :anchor
     (function_item name: (identifier) @test.name) @test.definition
     (:match "\\`\\(?:[a-z_]+::\\)?test\\(?:\\'\\|(\\)" @attr)))
  "Query matching `mod' blocks and functions carrying a test attribute.
The attribute may be namespaced and may carry arguments, so both
`tokio::test' and `tokio::test(flavor = \"multi_thread\")' match.")

(defun attest-rust-root (file)
  "Return the directory of the nearest Cargo.toml at or above FILE."
  (when-let* ((dir (locate-dominating-file file "Cargo.toml")))
    (expand-file-name dir)))

(defun attest-rust-test-file-p (file)
  "Return non-nil when FILE is a Rust source under src/ or tests/."
  (and (string-suffix-p ".rs" file)
       (string-match-p "/\\(?:src\\|tests\\)/" file)
       (not (string-match-p "/target/" file))))

(defun attest-rust--buffer-p ()
  "Return non-nil when the current buffer is a Rust source file."
  (and buffer-file-name
       (derived-mode-p 'rust-ts-mode 'rust-mode)
       (string-suffix-p ".rs" buffer-file-name)))

(defun attest-rust--project-p ()
  "Return non-nil when the current buffer sits in a cargo project.
Requires a rust mode, as the other backends require theirs, so a stray
`.rs' file opened in fundamental mode does not claim the project."
  (and buffer-file-name
       (derived-mode-p 'rust-ts-mode 'rust-mode)
       (attest-rust-root buffer-file-name)
       t))

(defun attest-rust-module-prefix (file root)
  "Return the libtest module path of FILE relative to crate ROOT.
Crate roots and integration test files map to the empty string."
  (let* ((rel (file-relative-name file root))
         (parts (split-string (file-name-sans-extension rel) "/" t)))
    (pcase parts
      (`("src" ,(or "lib" "main")) "")
      (`("tests" ,_) "")
      (`("src" . ,rest)
       (string-join (if (equal (car (last rest)) "mod") (butlast rest) rest) "::"))
      (_ ""))))

(defun attest-rust--position-names (position)
  "Return the module path names of POSITION relative to its file."
  (attest-id-names (plist-get position :id)))

(defun attest-rust--full-name (position root)
  "Return the libtest name of POSITION in the crate at ROOT."
  (let ((prefix (attest-rust-module-prefix (plist-get position :file) root))
        (names (string-join (attest-rust--position-names position) "::")))
    (if (string-empty-p prefix) names (concat prefix "::" names))))

(defun attest-rust--index (run)
  "Return a hash table from libtest name to position for RUN's files."
  (let ((root (plist-get run :root))
        (table (make-hash-table :test 'equal)))
    (dolist (pos (attest-run-positions run))
      (when (eq (plist-get pos :type) 'test)
        (puthash (attest-rust--full-name pos root) pos table)))
    table))

(defun attest-rust--file-selector (file root)
  "Return the cargo target arguments building the tests in FILE at ROOT.
A crate root or module file compiles into the library and the binaries;
a file under tests/ is an integration test target of its own name."
  (let ((parts (split-string (file-name-sans-extension (file-relative-name file root)) "/" t)))
    (pcase parts
      (`("tests" ,name) (list "--test" name))
      (`("src" . ,_) (list "--lib" "--bins"))
      (_ nil))))

(defun attest-rust--file-filters (file root index)
  "Return libtest filter arguments selecting the tests of FILE at ROOT.
A module file is selected by its module path with a trailing separator,
so a module named `scanner\=' does not also match `scanner_other\='.  A
crate root has no module prefix, so its own test names are passed with
--exact, taken from INDEX; without them cargo would run every test the
target builds and the parser would throw the rest away."
  (let ((prefix (attest-rust-module-prefix file root)))
    (if (not (string-empty-p prefix))
        (list (concat prefix "::"))
      (let (names)
        (maphash (lambda (name pos)
                   (when (equal (plist-get pos :file) file)
                     (push name names)))
                 index)
        (when names (cons "--exact" (sort names #'string<)))))))

(defun attest-rust--target-filters (targets root)
  "Return libtest filter arguments selecting TARGETS in the crate at ROOT.
Tests are matched with --exact.  libtest applies --exact to every
filter, so when TARGETS includes a namespace the filters are prefixes
and may select more tests than asked for."
  (let ((names (mapcar (lambda (target) (attest-rust--full-name target root)) targets)))
    (if (seq-some (lambda (target) (eq (plist-get target :type) 'namespace)) targets)
        names
      (cons "--exact" names))))

(defun attest-rust--command (run)
  "Return the process spec for RUN, indexing its positions on the way."
  (let* ((root (plist-get run :root))
         (scope (plist-get run :scope))
         (index (attest-rust--index run))
         (file (plist-get run :file))
         (selector (and (eq scope 'file) (attest-rust--file-selector file root)))
         (filters
          (pcase scope
            ('targets (attest-rust--target-filters (plist-get run :targets) root))
            ('file (attest-rust--file-filters file root index)))))
    (plist-put run :state (list :index index))
    (list :command (append (list attest-rust-cargo-executable "test" "-q" "--no-fail-fast")
                           selector
                           attest-rust-cargo-args
                           (list "--")
                           filters
                           (list "-Z" "unstable-options" "--format=json" "--report-time"))
          :directory root
          :env attest-rust-environment
          :parse-stream 'stdout)))

(defun attest-rust--panic-location (stdout run file)
  "Return (LINE . COLUMN) of the panic in STDOUT when it happened in FILE.
Paths in STDOUT are relative to RUN's directory."
  (when (and stdout
             (string-match "panicked at \\([^:\n]+\\):\\([0-9]+\\):\\([0-9]+\\)" stdout))
    (when (string= (expand-file-name (match-string 1 stdout) (plist-get run :directory))
                   file)
      (cons (string-to-number (match-string 2 stdout))
            (string-to-number (match-string 3 stdout))))))

(defun attest-rust--result (run event)
  "Return a result for a libtest test EVENT in RUN.
Returns nil when the run\='s index does not know the test, since cargo
selects tests by name over whole targets and reports names this run did
not ask for."
  (let* ((name (alist-get 'name event))
         (position (gethash name (plist-get (plist-get run :state) :index)))
         (file (plist-get position :file))
         (names (and position (attest-rust--position-names position)))
         (status (pcase (alist-get 'event event)
                   ("ok" 'passed)
                   ("failed" 'failed)
                   (_ 'skipped)))
         (stdout (alist-get 'stdout event)))
    (when (and stdout (not (string-empty-p stdout)))
      (attest-append-output run (concat stdout "\n")))
    (when position
      (append (list :id (apply #'attest-make-id file names)
                    :type 'test
                    :name (car (last names))
                    :status status
                    :file file
                    :duration (when-let* ((s (alist-get 'exec_time event))) (* 1000 s)))
              (when (eq status 'failed)
                (list :message (or (and stdout (string-trim stdout)) "test failed")
                      :location (attest-rust--panic-location stdout run file)))))))

(defun attest-rust--doctest-p (name)
  "Return non-nil when libtest NAME denotes a doc test.
Doc tests are named `PATH - ITEM (line N)' by rustdoc."
  (string-match-p "\\` *[^ ]+ - .*(line [0-9]+)\\'" name))

(defun attest-rust--parse-line (run line)
  "Parse one libtest JSON LINE from RUN into a result or nil.
Other stdout lines go to the output buffer."
  (when-let* ((event (attest-parse-json-line run line)))
    (when (and (equal (alist-get 'type event) "test")
               (member (alist-get 'event event) '("ok" "failed" "ignored"))
               (not (attest-rust--doctest-p (alist-get 'name event))))
      (attest-rust--result run event))))

(attest-register-backend 'rust
  :predicate #'attest-rust--buffer-p
  :project-p #'attest-rust--project-p
  :test-file-p #'attest-rust-test-file-p
  :root #'attest-rust-root
  :query (cons 'rust attest-rust--query)
  :command #'attest-rust--command
  :parse-line #'attest-rust--parse-line)

(provide 'attest-rust)
;;; attest-rust.el ends here
