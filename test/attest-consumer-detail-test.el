;;; attest-consumer-detail-test.el --- Consumer edge cases -*- lexical-binding: t; -*-

;;; Commentary:

;; Covers what the shipped consumers do at the edges: fringe markers for
;; a deleted test, another backend's flymake list-only entries, column
;; navigation over a tab, and the mode line after a run.

;;; Code:

(require 'test-helper)
(require 'attest)
(require 'attest-flymake)
(require 'attest-status)
(require 'attest-list)

(defmacro attest-detail-test--with-cache (&rest body)
  "Evaluate BODY against an empty result cache."
  (declare (indent 0))
  `(unwind-protect (progn (clrhash attest--results)
                          (clrhash attest--results-by-file)
                          ,@body)
     (clrhash attest--results)
     (clrhash attest--results-by-file)))

(ert-deftest attest-status-start-drops-markers-for-deleted-tests ()
  "A test gone from the file leaves no fringe marker when a run starts."
  (attest-detail-test--with-cache
    (let* ((file (attest-test-fixture "demo.test.ts"))
           (ghost (attest-make-id file "gone")))
      (attest-cache-result (list :id ghost :name "gone" :type 'test
                                 :status 'failed :file file :line 1))
      (let ((buffer (find-file-noselect file)))
        (unwind-protect
            (with-current-buffer buffer
              (attest-status-mode 1)
              (attest-status--render-buffer)
              (should (seq-find (lambda (o) (overlay-get o 'attest-status))
                                (overlays-in (point-min) (point-max))))
              (clrhash attest--results)
              (clrhash attest--results-by-file)
              (attest-status--on-start
               (list :backend 'node :scope 'file :file file :files (list file)))
              (should-not (seq-find (lambda (o) (overlay-get o 'attest-status))
                                    (overlays-in (point-min) (point-max)))))
          (kill-buffer buffer))))))

(ert-deftest attest-flymake-keeps-other-backends-list-entries ()
  "Refreshing drops attest's list-only diagnostics and nobody else's."
  (attest-detail-test--with-cache
    (let* ((file (attest-test-fixture "demo.test.ts"))
           (foreign (flymake-make-diagnostic file (cons 1 nil) nil :warning
                                             "from another backend" 'not-attest))
           (mine (flymake-make-diagnostic file (cons 2 nil) nil :error
                                          "from attest" (list :id "x::y")))
           (flymake-list-only-diagnostics (list (cons file (list foreign mine)))))
      (attest-flymake--drop-list-only file)
      (should (equal (cdr (assoc file flymake-list-only-diagnostics))
                     (list foreign))))))

(ert-deftest attest-flymake-drops-its-own-entry-entirely ()
  "An entry holding only attest diagnostics is removed, not left empty."
  (attest-detail-test--with-cache
    (let* ((file (attest-test-fixture "demo.test.ts"))
           (mine (flymake-make-diagnostic file (cons 2 nil) nil :error
                                          "from attest" (list :id "x::y")))
           (flymake-list-only-diagnostics (list (cons file (list mine)))))
      (attest-flymake--drop-list-only file)
      (should-not (assoc file flymake-list-only-diagnostics)))))

(ert-deftest attest-list-visit-counts-characters-not-columns ()
  "A column lands on the character offset even when the line has tabs."
  (let ((file (make-temp-file "attest-visit" nil ".js")))
    (unwind-protect
        (progn
          (write-region "\t\tconst x = 1;\n" nil file nil 'silent)
          (attest-detail-test--with-cache
            (let* ((result (list :id "v::one" :name "one" :type 'test
                                 :status 'failed :file file :line 1
                                 :location (cons 1 3)))
                   (buffer nil))
              (cl-letf (((symbol-function 'attest-list--result-at-point)
                         (lambda () result))
                        ((symbol-function 'pop-to-buffer)
                         (lambda (b &rest _) (setq buffer b) (set-buffer b))))
                (attest-list-visit)
                (with-current-buffer buffer
                  (should (= (point) 3)))
                (kill-buffer buffer)))))
      (delete-file file))))

(ert-deftest attest-progress-leaves-the-mode-line-as-it-found-it ()
  "Stopping removes the indicator symbol, not only its value."
  (let* ((file (make-temp-file "attest-modeline" nil ".js"))
         (buffer (find-file-noselect file)))
    (unwind-protect
        (with-current-buffer buffer
          (let ((run (list :backend 'node :scope 'file :file file
                           :files (list file) :buffer buffer
                           :status 'running :start-time (float-time)))
                (before mode-line-process))
            (attest--progress-start run)
            (should (memq 'attest--progress mode-line-process))
            (attest--progress-stop run)
            (should-not (memq 'attest--progress mode-line-process))
            (should (equal mode-line-process before))))
      (kill-buffer buffer)
      (delete-file file))))

(provide 'attest-consumer-detail-test)
;;; attest-consumer-detail-test.el ends here
