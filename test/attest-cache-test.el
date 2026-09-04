;;; attest-cache-test.el --- Tests for the result cache -*- lexical-binding: t; -*-

;;; Commentary:

;; Covers the per-file result index: what it returns, that it survives a
;; test moving between files, that clearing works, and that a file named
;; two ways resolves to one entry.

;;; Code:

(require 'test-helper)
(require 'attest)

(defmacro attest-cache-test--with-cache (&rest body)
  "Evaluate BODY against an empty result cache."
  (declare (indent 0))
  `(let ((attest--last-run nil))
     (unwind-protect (progn (clrhash attest--results)
                            (clrhash attest--results-by-file)
                            ,@body)
       (clrhash attest--results)
       (clrhash attest--results-by-file))))

(defun attest-cache-test--put (id file &optional status)
  "Record a result ID living in FILE with STATUS, defaulting to passed."
  (attest-cache-result (list :id id :type 'test :name id
                             :status (or status 'passed) :file file)))

(ert-deftest attest-results-for-file-returns-only-that-file ()
  "The index does not leak results recorded for other files."
  (attest-cache-test--with-cache
    (attest-cache-test--put "a::one" "/tmp/a.js")
    (attest-cache-test--put "a::two" "/tmp/a.js")
    (attest-cache-test--put "b::one" "/tmp/b.js")
    (should (equal (sort (mapcar (lambda (r) (plist-get r :id))
                                 (attest-results-for-file "/tmp/a.js"))
                         #'string<)
                   '("a::one" "a::two")))
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (attest-results-for-file "/tmp/b.js"))
                   '("b::one")))))

(ert-deftest attest-results-for-file-matches-a-full-scan ()
  "The index agrees with walking every result in the cache."
  (attest-cache-test--with-cache
    (dotimes (f 5)
      (dotimes (n 4)
        (attest-cache-test--put (format "f%d::t%d" f n) (format "/tmp/f%d.js" f))))
    (dotimes (f 5)
      (let* ((file (format "/tmp/f%d.js" f))
             (scanned nil))
        (maphash (lambda (_id result)
                   (when (equal (plist-get result :file) file)
                     (push (plist-get result :id) scanned)))
                 attest--results)
        (should (equal (sort scanned #'string<)
                       (sort (mapcar (lambda (r) (plist-get r :id))
                                     (attest-results-for-file file))
                             #'string<)))))))

(ert-deftest attest-results-for-file-ignores-path-spelling ()
  "A file named through a symlink resolves to the same entry."
  (attest-cache-test--with-cache
    (let* ((dir (make-temp-file "attest-cache" t))
           (real (expand-file-name "real.js" dir))
           (link (expand-file-name "link.js" dir)))
      (unwind-protect
          (progn
            (write-region "" nil real nil 'silent)
            (make-symbolic-link real link t)
            (attest-cache-test--put "x::one" real)
            (should (= 1 (length (attest-results-for-file link)))))
        (delete-directory dir t)))))

(ert-deftest attest-recording-a-moved-test-leaves-no-ghost ()
  "A test that changes file is indexed under the new file only."
  (attest-cache-test--with-cache
    (let ((run (list :backend nil :result-ids nil :results nil)))
      (attest--record run (list :id "m::one" :type 'test :name "one"
                                :status 'passed :file "/tmp/old.js"))
      (attest--record run (list :id "m::one" :type 'test :name "one"
                                :status 'failed :file "/tmp/new.js"))
      (should-not (attest-results-for-file "/tmp/old.js"))
      (should (= 1 (length (attest-results-for-file "/tmp/new.js")))))))

(ert-deftest attest-clear-results-empties-the-index ()
  "Clearing drops the ids and the per-file index together."
  (attest-cache-test--with-cache
    (attest-cache-test--put "a::one" "/tmp/a.js")
    (attest-cache-test--put "b::one" "/tmp/b.js")
    (attest-clear-results "/tmp/a.js")
    (should-not (attest-results-for-file "/tmp/a.js"))
    (should (attest-results-for-file "/tmp/b.js"))
    (attest-clear-results)
    (should (zerop (hash-table-count attest--results)))
    (should (zerop (hash-table-count attest--results-by-file)))))

(provide 'attest-cache-test)
;;; attest-cache-test.el ends here
