;;; attest-consumers-test.el --- Tests for the shipped consumers -*- lexical-binding: t; -*-

;;; Commentary:

;; Feeds recorded results into the result cache and checks what the
;; flymake, fringe and list consumers make of them.  No node process.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-node)
(require 'attest-flymake)
(require 'attest-status)
(require 'attest-list)

(defun attest-consumers-test--load-run ()
  "Record the fixture results under fixtures/demo.test.ts and return the run."
  (clrhash attest--results)
  (let ((file (attest-test-fixture "demo.test.ts"))
        (run (list :backend 'node :scope 'file :state nil :result-ids nil
                   :status 'finished :start-time 0.0 :end-time 1.0)))
    (dolist (line (attest-test-fixture-lines "demo-events.jsonl"))
      (when-let* ((r (attest-node--parse-line run line)))
        (plist-put r :file file)
        (plist-put r :id (apply #'attest-make-id file (attest-id-names (plist-get r :id))))
        (attest--record (append (list :file file) run) r)))
    (setq attest--last-run run)
    run))

(defmacro attest-consumers-test--with-fixture-buffer (&rest body)
  "Evaluate BODY in a buffer visiting fixtures/demo.test.ts."
  `(let ((buffer (find-file-noselect (attest-test-fixture "demo.test.ts"))))
     (unwind-protect
         (with-current-buffer buffer ,@body)
       (kill-buffer buffer))))

(ert-deftest attest-flymake-reports-failures-at-assertion-lines ()
  (attest-consumers-test--load-run)
  (attest-consumers-test--with-fixture-buffer
   (let ((diags (attest-flymake--buffer-diagnostics)))
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

(ert-deftest attest-flymake-mode-publishes-through-flymake ()
  (attest-consumers-test--load-run)
  (attest-consumers-test--with-fixture-buffer
   (setq-local flymake-diagnostic-functions nil)
   (flymake-mode 1)
   (attest-flymake-mode 1)
   (flymake-start nil t)
   (with-timeout (5 (ert-fail "flymake never reported"))
     (while (null (flymake-diagnostics)) (accept-process-output nil 0.05)))
   (let ((diags (flymake-diagnostics)))
     (should (= (length diags) 2))
     (should (equal (mapcar #'flymake-diagnostic-backend diags)
                    (list #'attest-flymake-backend #'attest-flymake-backend))))
   (attest-flymake-mode -1)
   (should-not (memq #'attest-flymake-backend flymake-diagnostic-functions))
   (should (= (length (flymake-diagnostics)) 0))))

(ert-deftest attest-flymake-lists-unvisited-files ()
  (let ((run (attest-consumers-test--load-run))
        (flymake-list-only-diagnostics nil)
        (file (attest-test-fixture "demo.test.ts")))
    (should-not (find-buffer-visiting file))
    (attest-flymake--refresh run)
    (let ((entry (assoc file flymake-list-only-diagnostics)))
      (should entry)
      (should (= (length (cdr entry)) 2))
      (should (equal (sort (mapcar #'flymake-diagnostic-beg (cdr entry))
                           (lambda (a b) (< (car a) (car b))))
                     '((10 . 5) (21 . 9)))))))

(ert-deftest attest-status-places-fringe-markers ()
  (attest-consumers-test--load-run)
  (attest-consumers-test--with-fixture-buffer
   (attest-status-mode 1)
   (let ((overlays (seq-filter (lambda (o) (overlay-get o 'attest-status))
                               (overlays-in (point-min) (point-max)))))
     (should (= (length overlays) 9))
     (let ((by-line (mapcar (lambda (o)
                             (cons (line-number-at-pos (overlay-start o))
                                   (nth 2 (get-text-property
                                           0 'display (overlay-get o 'before-string)))))
                           overlays)))
       (should (eq (alist-get 8 by-line) 'attest-status-failed))
       (should (eq (alist-get 5 by-line) 'attest-status-passed))
       (should (eq (alist-get 14 by-line) 'attest-status-skipped))))
   (attest-status-mode -1)
   (should-not (seq-filter (lambda (o) (overlay-get o 'attest-status))
                           (overlays-in (point-min) (point-max))))))

(ert-deftest attest-list-shows-tests-and-filters-failures ()
  (attest-consumers-test--load-run)
  (with-current-buffer (get-buffer-create attest-list-buffer-name)
    (attest-list-mode)
    (tabulated-list-revert)
    (should (= (length (attest-list--entries)) 7))
    (attest-list-toggle-failures)
    (should (= (length (attest-list--entries)) 2))
    (goto-char (point-min))
    (should (equal (plist-get (tabulated-list-get-id) :name) "fails on purpose"))
    (kill-buffer)))

(ert-deftest attest-rerun-failed-selects-failed-tests-only ()
  (let ((run (attest-consumers-test--load-run)))
    (should (equal (mapcar (lambda (r) (plist-get r :name))
                           (seq-filter (lambda (r) (eq (plist-get r :type) 'test))
                                       (attest-run-failed-results run)))
                   '("fails on purpose" "throws")))))

(provide 'attest-consumers-test)
;;; attest-consumers-test.el ends here
