;;; neotest-treesit.el --- Tree-sitter test discovery for neotest -*- lexical-binding: t; -*-

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Turns a tree-sitter query into neotest positions.  A backend supplies
;; a query whose captures follow the neotest.nvim convention:
;;
;;   @test.definition       the whole test node
;;   @test.name             the node holding the test name
;;   @namespace.definition  the whole grouping node (describe, suite)
;;   @namespace.name        the node holding the group name
;;
;; Nesting is derived from range containment, so the query does not
;; need to express it.  Ids are built with `neotest-make-id' from the
;; file and the chain of names, which is the same shape the runner
;; backends produce.

;;; Code:

(require 'treesit)
(require 'neotest)

(defun neotest-treesit--name-text (node)
  "Return the test name expressed by NODE.
String literals lose their quotes; template strings are concatenated
verbatim; anything else is returned as source text."
  (pcase (treesit-node-type node)
    ("string"
     (mapconcat (lambda (child) (treesit-node-text child t))
                (treesit-filter-child
                 node (lambda (child)
                        (member (treesit-node-type child)
                                '("string_fragment" "escape_sequence"))))
                ""))
    ("template_string"
     (mapconcat (lambda (child) (treesit-node-text child t))
                (treesit-filter-child node (lambda (child) (treesit-node-check child 'named)))
                ""))
    (_ (treesit-node-text node t))))

(defun neotest-treesit--match-position (match file)
  "Return an unlinked position plist for MATCH in FILE, or nil.
MATCH is one grouped result of `treesit-query-capture'."
  (let* ((kind (cond ((alist-get 'test.definition match) 'test)
                     ((alist-get 'namespace.definition match) 'namespace)))
         (definition (and kind (alist-get (intern (format "%s.definition" kind)) match)))
         (name-node (and kind (alist-get (intern (format "%s.name" kind)) match))))
    (when (and definition name-node)
      (list :type kind
            :name (neotest-treesit--name-text name-node)
            :file file
            :line (line-number-at-pos (treesit-node-start definition) t)
            :column (1+ (save-excursion
                          (goto-char (treesit-node-start definition))
                          (current-column)))
            :beg (treesit-node-start definition)
            :end (treesit-node-end definition)))))

(defun neotest-treesit--link (positions file)
  "Assign :parent-id and :id to POSITIONS from FILE by range containment.
POSITIONS must be sorted by :beg ascending."
  (let (stack)
    (dolist (pos positions)
      (while (and stack
                  (>= (plist-get pos :beg) (plist-get (car stack) :end)))
        (pop stack))
      (let* ((parent (car stack))
             (names (append (and parent (plist-get parent :names))
                            (list (plist-get pos :name)))))
        (plist-put pos :parent-id (and parent (plist-get parent :id)))
        (plist-put pos :names names)
        (plist-put pos :id (apply #'neotest-make-id file names))
        (when (eq (plist-get pos :type) 'namespace)
          (push pos stack))))
    positions))

(defun neotest-treesit-positions (buffer language query)
  "Return the positions in BUFFER found by QUERY for LANGUAGE.
QUERY is a tree-sitter query in sexp or string form using the
captures documented at the top of this file."
  (with-current-buffer buffer
    (unless (treesit-language-available-p language)
      (user-error "Neotest: tree-sitter grammar for %s is not available" language))
    (let* ((file (or (and buffer-file-name (expand-file-name buffer-file-name))
                     (buffer-name)))
           (parser (treesit-parser-create language))
           (root (treesit-parser-root-node parser))
           (matches (treesit-query-capture root query nil nil nil t))
           (positions (delq nil (mapcar (lambda (match)
                                          (neotest-treesit--match-position match file))
                                        matches))))
      (neotest-treesit--link
       (sort positions (lambda (a b) (< (plist-get a :beg) (plist-get b :beg))))
       file))))

(provide 'neotest-treesit)
;;; neotest-treesit.el ends here
