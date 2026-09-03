;;; attest-rust.el --- cargo test backend for attest -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nathan Scully

;; Author: Nathan Scully
;; Maintainer: Nathan Scully
;; URL: https://github.com/nathanscully/attest.el

;; This file is not part of GNU Emacs.

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

(defconst attest-rust--query
  '(((mod_item name: (identifier) @namespace.name body: (declaration_list)) @namespace.definition)
    ((attribute_item (attribute) @attr)
     :anchor
     (attribute_item) :*
     :anchor
     (function_item name: (identifier) @test.name) @test.definition
     (:match "\\`\\(?:[a-z_]+::\\)?test\\'" @attr)))
  "Query matching `mod' blocks and functions carrying a test attribute.")

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
         (filters
          (pcase scope
            ('targets (attest-rust--target-filters (plist-get run :targets) root))
            ('file (let ((prefix (attest-rust-module-prefix (plist-get run :file) root)))
                     (and (not (string-empty-p prefix)) (list prefix)))))))
    (plist-put run :state (list :index index))
    (list :command (append (list attest-rust-cargo-executable "test" "-q" "--no-fail-fast")
                           attest-rust-cargo-args
                           (list "--")
                           filters
                           (list "-Z" "unstable-options" "--format=json" "--report-time"))
          :directory root
          :env '("RUSTC_BOOTSTRAP=1")
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
  "Return a result for a libtest test EVENT in RUN."
  (let* ((name (alist-get 'name event))
         (position (gethash name (plist-get (plist-get run :state) :index)))
         (file (or (plist-get position :file) (plist-get run :file)))
         (names (if position
                    (attest-rust--position-names position)
                  (split-string name "::")))
         (status (pcase (alist-get 'event event)
                   ("ok" 'passed)
                   ("failed" 'failed)
                   (_ 'skipped)))
         (stdout (alist-get 'stdout event)))
    (when (and stdout (not (string-empty-p stdout)))
      (attest-append-output run (concat stdout "\n")))
    (append (list :id (apply #'attest-make-id file names)
                  :type 'test
                  :name (car (last names))
                  :status status
                  :file file
                  :duration (when-let* ((s (alist-get 'exec_time event))) (* 1000 s)))
            (when (eq status 'failed)
              (list :message (or (and stdout (string-trim stdout)) "test failed")
                    :location (attest-rust--panic-location stdout run file))))))

(defun attest-rust--doctest-p (name)
  "Return non-nil when libtest NAME denotes a doc test.
Doc tests are named `PATH - ITEM (line N)' by rustdoc."
  (string-match-p "\\` *[^ ]+ - .*(line [0-9]+)\\'" name))

(defun attest-rust--parse-line (run line)
  "Parse one libtest JSON LINE from RUN into a result or nil.
Other stdout lines go to the output buffer."
  (unless (string-prefix-p "{" line)
    (attest-append-output run (concat line "\n")))
  (when (string-prefix-p "{" line)
    (when-let* ((event (ignore-errors
                         (json-parse-string line :object-type 'alist
                                            :null-object nil :false-object nil))))
      (when (and (equal (alist-get 'type event) "test")
                 (member (alist-get 'event event) '("ok" "failed" "ignored"))
                 (not (attest-rust--doctest-p (alist-get 'name event))))
        (attest-rust--result run event)))))

(attest-register-backend 'rust
  :predicate #'attest-rust--buffer-p
  :test-file-p #'attest-rust-test-file-p
  :root #'attest-rust-root
  :query (cons 'rust attest-rust--query)
  :command #'attest-rust--command
  :parse-line #'attest-rust--parse-line)

(provide 'attest-rust)
;;; attest-rust.el ends here
