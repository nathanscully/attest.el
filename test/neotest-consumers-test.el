;;; neotest-consumers-test.el --- Tests for the shipped consumers -*- lexical-binding: t; -*-

;;; Commentary:

;; Feeds recorded results into the result cache and checks what the
;; flymake, fringe and list consumers make of them.  No node process.

;;; Code:

(require 'test-helper)
(require 'neotest)
(require 'neotest-node)
(require 'neotest-flymake)
(require 'neotest-status)
(require 'neotest-list)

(defun neotest-consumers-test--load-run ()
  "Record the fixture results under fixtures/demo.test.ts and return the run."
  (clrhash neotest--results)
  (let ((file (neotest-test-fixture "demo.test.ts"))
        (run (list :backend 'node :scope 'file :state nil :result-ids nil
                   :status 'finished :start-time 0.0 :end-time 1.0)))
    (dolist (line (neotest-test-fixture-lines "demo-events.jsonl"))
      (when-let* ((r (neotest-node--parse-line run line)))
        (plist-put r :file file)
        (plist-put r :id (apply #'neotest-make-id file (neotest-id-names (plist-get r :id))))
        (neotest--record (append (list :file file) run) r)))
    (setq neotest--last-run run)
    run))

(defmacro neotest-consumers-test--with-fixture-buffer (&rest body)
  "Evaluate BODY in a buffer visiting fixtures/demo.test.ts."
  `(let ((buffer (find-file-noselect (neotest-test-fixture "demo.test.ts"))))
     (unwind-protect
         (with-current-buffer buffer ,@body)
       (kill-buffer buffer))))

(ert-deftest neotest-flymake-reports-failures-at-assertion-lines ()
  (neotest-consumers-test--load-run)
  (neotest-consumers-test--with-fixture-buffer
   (let ((diags (neotest-flymake--buffer-diagnostics)))
     (should (= (length diags) 2))
     (should (equal (sort (mapcar (lambda (d) (line-number-at-pos (flymake-diagnostic-beg d)))
                                  diags)
                          #'<)
                    '(10 21)))
     (should (cl-every (lambda (d) (eq (flymake-diagnostic-type d) :error)) diags))
     (let ((texts (mapcar #'flymake-diagnostic-text diags)))
       (should (seq-find (lambda (s) (string-match-p "math > fails on purpose: Expected" s))
                         texts))
       (should (seq-find (lambda (s) (string-match-p "throws: boom" s)) texts))))))

(ert-deftest neotest-flymake-mode-publishes-through-flymake ()
  (neotest-consumers-test--load-run)
  (neotest-consumers-test--with-fixture-buffer
   (setq-local flymake-diagnostic-functions nil)
   (flymake-mode 1)
   (neotest-flymake-mode 1)
   (flymake-start nil t)
   (with-timeout (5 (ert-fail "flymake never reported"))
     (while (null (flymake-diagnostics)) (accept-process-output nil 0.05)))
   (let ((diags (flymake-diagnostics)))
     (should (= (length diags) 2))
     (should (equal (mapcar #'flymake-diagnostic-backend diags)
                    (list #'neotest-flymake-backend #'neotest-flymake-backend))))
   (neotest-flymake-mode -1)
   (should-not (memq #'neotest-flymake-backend flymake-diagnostic-functions))
   (should (= (length (flymake-diagnostics)) 0))))

(ert-deftest neotest-flymake-lists-unvisited-files ()
  (let ((run (neotest-consumers-test--load-run))
        (flymake-list-only-diagnostics nil)
        (file (neotest-test-fixture "demo.test.ts")))
    (should-not (find-buffer-visiting file))
    (neotest-flymake--refresh run)
    (let ((entry (assoc file flymake-list-only-diagnostics)))
      (should entry)
      (should (= (length (cdr entry)) 2))
      (should (equal (sort (mapcar #'flymake-diagnostic-beg (cdr entry))
                           (lambda (a b) (< (car a) (car b))))
                     '((10 . 5) (21 . 9)))))))

(ert-deftest neotest-status-places-fringe-markers ()
  (neotest-consumers-test--load-run)
  (neotest-consumers-test--with-fixture-buffer
   (neotest-status-mode 1)
   (let ((overlays (seq-filter (lambda (o) (overlay-get o 'neotest-status))
                               (overlays-in (point-min) (point-max)))))
     (should (= (length overlays) 9))
     (let ((by-line (mapcar (lambda (o)
                             (cons (line-number-at-pos (overlay-start o))
                                   (nth 2 (get-text-property
                                           0 'display (overlay-get o 'before-string)))))
                           overlays)))
       (should (eq (alist-get 8 by-line) 'neotest-status-failed))
       (should (eq (alist-get 5 by-line) 'neotest-status-passed))
       (should (eq (alist-get 14 by-line) 'neotest-status-skipped))))
   (neotest-status-mode -1)
   (should-not (seq-filter (lambda (o) (overlay-get o 'neotest-status))
                           (overlays-in (point-min) (point-max))))))

(ert-deftest neotest-list-shows-tests-and-filters-failures ()
  (neotest-consumers-test--load-run)
  (with-current-buffer (get-buffer-create neotest-list-buffer-name)
    (neotest-list-mode)
    (tabulated-list-revert)
    (should (= (length (neotest-list--entries)) 7))
    (neotest-list-toggle-failures)
    (should (= (length (neotest-list--entries)) 2))
    (goto-char (point-min))
    (should (equal (plist-get (tabulated-list-get-id) :name) "fails on purpose"))
    (kill-buffer)))

(ert-deftest neotest-rerun-failed-selects-failed-tests-only ()
  (let ((run (neotest-consumers-test--load-run)))
    (should (equal (mapcar (lambda (r) (plist-get r :name))
                           (seq-filter (lambda (r) (eq (plist-get r :type) 'test))
                                       (neotest-run-failed-results run)))
                   '("fails on purpose" "throws")))))

(provide 'neotest-consumers-test)
;;; neotest-consumers-test.el ends here
