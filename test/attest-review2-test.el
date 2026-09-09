;;; attest-review2-test.el --- Follow-up review fixes -*- lexical-binding: t; -*-

;;; Commentary:

;; Covers the second round of review findings: path spelling in the
;; progress and position lookups, the cache-changed hook, per-file
;; `.only' scoping, output trim marking and mode-line restoration.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-flymake)
(require 'attest-status)
(require 'attest-list)

(defmacro attest-review2--with-cache (&rest body)
  "Evaluate BODY against an empty result cache."
  (declare (indent 0))
  `(unwind-protect (progn (clrhash attest--results)
                          (clrhash attest--results-by-file)
                          ,@body)
     (clrhash attest--results)
     (clrhash attest--results-by-file)))

(defmacro attest-review2--with-linked-file (real link &rest body)
  "Bind REAL and LINK to a temp file and a symlink to it, then run BODY."
  (declare (indent 2))
  `(let* ((dir (make-temp-file "attest-review2" t))
          (,real (expand-file-name "real.test.js" dir))
          (,link (expand-file-name "link.test.js" dir)))
     (unwind-protect
         (progn (write-region "test('one', () => {});\n" nil ,real nil 'silent)
                (make-symbolic-link ,real ,link t)
                ,@body)
       (delete-directory dir t))))

(ert-deftest attest-progress-buffers-ignore-path-spelling ()
  "A buffer visiting the file under another name still gets the indicator."
  (attest-review2--with-linked-file real link
    (let ((buffer (find-file-noselect link)))
      (unwind-protect
          (let ((run (list :backend 'node :scope 'file :file real)))
            (should (memq buffer (attest--progress-buffers run))))
        (kill-buffer buffer)))))

(ert-deftest attest-run-position-ignores-path-spelling ()
  "A result naming the file differently still finds its position.
`expand-file-name' already reconciles a symlink in the same directory,
so this drives the case it does not: an id built from a path discovery
never saw."
  (require 'attest-node)
  (attest-review2--with-linked-file real link
    (let* ((run (list :backend 'node :scope 'file :file real))
           (elsewhere (attest-make-id
                       (expand-file-name "real.test.js" "/other/root/")
                       "one")))
      (should (attest-run-position run (attest-make-id real "one")))
      (should (attest-run-position run (attest-make-id link "one")))
      (should-not (attest-run-position run elsewhere)))))

(ert-deftest attest-clear-results-tells-the-consumers ()
  "Clearing fires the cache hook with the files it cleared."
  (attest-review2--with-cache
    (let* ((seen 'unset)
           (attest-results-changed-functions
            (list (lambda (files) (setq seen files)))))
      (attest-cache-result (list :id "a::one" :type 'test :name "one"
                                 :status 'failed :file "/tmp/a.js"))
      (attest-clear-results "/tmp/a.js")
      (should (equal seen (list "/tmp/a.js")))
      (setq seen 'unset)
      (attest-clear-results)
      (should (null seen)))))

(ert-deftest attest-status-redraws-when-results-are-cleared ()
  "Clearing a file's results removes its fringe markers."
  (attest-review2--with-cache
    (let* ((file (attest-test-fixture "demo.test.ts"))
           (buffer (find-file-noselect file)))
      (unwind-protect
          (with-current-buffer buffer
            (attest-status-mode 1)
            (attest-cache-result (list :id (attest-make-id file "ghost")
                                       :type 'test :name "ghost"
                                       :status 'failed :file file :line 1))
            (attest-status--render-buffer)
            (should (seq-find (lambda (o) (overlay-get o 'attest-status))
                              (overlays-in (point-min) (point-max))))
            (attest-clear-results file)
            (should-not (seq-find (lambda (o) (overlay-get o 'attest-status))
                                  (overlays-in (point-min) (point-max)))))
        (kill-buffer buffer)))))

(ert-deftest attest-cache-result-moves-an-id-between-files ()
  "Re-caching an id under a new file leaves no ghost in the old one."
  (attest-review2--with-cache
    (attest-cache-result (list :id "m::one" :type 'test :name "one"
                               :status 'passed :file "/tmp/old.js"))
    (attest-cache-result (list :id "m::one" :type 'test :name "one"
                               :status 'failed :file "/tmp/new.js"))
    (should-not (attest-results-for-file "/tmp/old.js"))
    (should (= 1 (length (attest-results-for-file "/tmp/new.js"))))))

(ert-deftest attest-output-trim-marks-the-cut-once ()
  "Repeated trimming leaves one marker, not a run of them."
  (with-temp-buffer
    (let ((run (list :backend 'node :output-buffer (current-buffer)))
          (attest-max-output 500))
      (dotimes (i 200)
        (attest-append-output run (format "line %03d padded to some width\n" i)))
      (should (= 1 (cl-count "[earlier output dropped]"
                             (split-string (buffer-string) "\n")
                             :test #'string-prefix-p))))))

(ert-deftest attest-progress-restores-a-string-mode-line ()
  "A string `mode-line-process' comes back as a string, not a list."
  (let* ((file (make-temp-file "attest-ml" nil ".test.js"))
         (buffer (find-file-noselect file)))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local mode-line-process ":%s")
          (let ((run (list :backend 'node :scope 'file :file file
                           :files (list file) :buffer buffer
                           :status 'running :start-time (float-time))))
            (attest--progress-start run)
            (should (memq 'attest--progress mode-line-process))
            (attest--progress-stop run)
            (should (equal mode-line-process ":%s"))))
      (kill-buffer buffer)
      (delete-file file))))

(provide 'attest-review2-test)
;;; attest-review2-test.el ends here
