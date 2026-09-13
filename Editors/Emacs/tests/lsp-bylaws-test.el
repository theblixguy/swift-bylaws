;;; lsp-bylaws-test.el --- Tests for lsp-bylaws -*- lexical-binding: t; -*-

(require 'ert)

(defvar lsp-bylaws-test-client nil)

(defun lsp-register-client (client)
  (setq lsp-bylaws-test-client client))

(defun make-lsp-client (&rest properties)
  properties)

(defun lsp-stdio-connection (command)
  command)

(defun lsp-activate-on (&rest language-ids)
  language-ids)

(provide 'lsp-mode)

(load (expand-file-name "../lsp-bylaws.el"
                        (file-name-directory load-file-name))
      nil
      t)

(ert-deftest lsp-bylaws-registers-a-swift-add-on ()
  (should (equal (plist-get lsp-bylaws-test-client :activation-fn)
                 '("swift")))
  (should (eq (plist-get lsp-bylaws-test-client :server-id) 'bylaws))
  (should (eq (plist-get lsp-bylaws-test-client :add-on?) t)))

(ert-deftest lsp-bylaws-uses-the-configured-command ()
  (let ((lsp-bylaws-server-command "/usr/local/bin/bylaws-lsp"))
    (should (equal
             (funcall (plist-get lsp-bylaws-test-client :new-connection))
             "/usr/local/bin/bylaws-lsp"))))

(ert-deftest lsp-bylaws-sends-no-option-without-a-value ()
  (let ((lsp-bylaws-rules nil)
        (lsp-bylaws-only nil)
        (lsp-bylaws-skip nil)
        (lsp-bylaws-baseline nil)
        (lsp-bylaws-refresh-delay-milliseconds 0))
    (should (null (lsp-bylaws--initialization-options)))))

(ert-deftest lsp-bylaws-sends-the-configured-options ()
  (let* ((lsp-bylaws-rules '("Rules/Bylaws.swift"))
         (lsp-bylaws-only '("final-classes"))
         (lsp-bylaws-skip '("public-protocol-docs"))
         (lsp-bylaws-baseline "Bylaws.baseline.swift")
         (lsp-bylaws-refresh-delay-milliseconds 300)
         (options (lsp-bylaws--initialization-options)))
    (should (equal (plist-get options :rules) ["Rules/Bylaws.swift"]))
    (should (equal (plist-get options :only) ["final-classes"]))
    (should (equal (plist-get options :skip) ["public-protocol-docs"]))
    (should (equal (plist-get options :baseline) "Bylaws.baseline.swift"))
    (should (equal (plist-get options :refreshDelayMilliseconds) 300))))

(ert-deftest lsp-bylaws-drops-a-path-without-text ()
  (let* ((lsp-bylaws-rules '("  " "" " Rules/Bylaws.swift "))
         (lsp-bylaws-baseline "   ")
         (options (lsp-bylaws--initialization-options)))
    (should (equal (plist-get options :rules) ["Rules/Bylaws.swift"]))
    (should (null (plist-member options :baseline)))))

(ert-deftest lsp-bylaws-drops-a-value-of-the-wrong-type ()
  (let ((lsp-bylaws-rules 7)
        (lsp-bylaws-only '(7 "final-classes"))
        (lsp-bylaws-baseline 7)
        (lsp-bylaws-refresh-delay-milliseconds "300"))
    (let ((options (lsp-bylaws--initialization-options)))
      (should (null (plist-member options :rules)))
      (should (equal (plist-get options :only) ["final-classes"]))
      (should (null (plist-member options :baseline)))
      (should (null (plist-member options :refreshDelayMilliseconds))))))

(ert-deftest lsp-bylaws-drops-a-delay-of-zero-or-below ()
  (let ((lsp-bylaws-refresh-delay-milliseconds -1))
    (should (null (plist-member (lsp-bylaws--initialization-options)
                                :refreshDelayMilliseconds)))))

(ert-deftest lsp-bylaws-registers-the-options-function ()
  (should (eq (plist-get lsp-bylaws-test-client :initialization-options)
              #'lsp-bylaws--initialization-options)))

(ert-run-tests-batch-and-exit)
;;; lsp-bylaws-test.el ends here
