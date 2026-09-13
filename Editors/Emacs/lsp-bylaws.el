;;; lsp-bylaws.el --- Bylaws diagnostics for Swift -*- lexical-binding: t; -*-

;; Copyright (c) 2026 Suyash Srijan

;; Author: Suyash Srijan
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (lsp-mode "10.0.1"))
;; Keywords: languages, tools
;; URL: https://github.com/theblixguy/swift-bylaws
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Bylaws runs as an lsp-mode add-on client for Swift buffers.
;; SourceKit-LSP remains the main Swift language server.

;;; Code:

(require 'subr-x)

(defgroup lsp-bylaws nil
  "Bylaws architecture rule diagnostics."
  :group 'lsp-mode
  :link '(url-link "https://github.com/theblixguy/swift-bylaws"))

;;;###autoload
(defcustom lsp-bylaws-server-command "bylaws-lsp"
  "Command that starts Bylaws Language Server."
  :group 'lsp-bylaws
  :risky t
  :type 'string)

;;;###autoload
(defcustom lsp-bylaws-rules nil
  "Rules files to load, as paths relative to the workspace folder.
An empty list discovers the `Bylaws.swift' files."
  :group 'lsp-bylaws
  :type '(repeat string))

;;;###autoload
(defcustom lsp-bylaws-only nil
  "IDs of the rules to run.  An empty list runs every rule."
  :group 'lsp-bylaws
  :type '(repeat string))

;;;###autoload
(defcustom lsp-bylaws-skip nil
  "IDs of the rules to skip."
  :group 'lsp-bylaws
  :type '(repeat string))

;;;###autoload
(defcustom lsp-bylaws-baseline nil
  "Recorded baseline file, as a path relative to the workspace folder.
An empty value discovers the `Bylaws.baseline.swift' files."
  :group 'lsp-bylaws
  :type '(choice (const :tag "Discover the baseline files" nil) string))

;;;###autoload
(defcustom lsp-bylaws-refresh-delay-milliseconds 0
  "Time to wait after the last keystroke before the rules run again.
Raise it on a codebase where a run for each keystroke costs too much."
  :group 'lsp-bylaws
  :type 'integer)

(defun lsp-bylaws--text (value)
  "Return VALUE without its surrounding space, or nil when it holds no text."
  (when (stringp value)
    (let ((text (string-trim value)))
      (unless (string-empty-p text) text))))

(defun lsp-bylaws--texts (values)
  "Return VALUES as a vector, without the entries that hold no text."
  (when (sequencep values)
    (let ((texts (delq nil (mapcar #'lsp-bylaws--text values))))
      (when texts (vconcat texts)))))

(defun lsp-bylaws--initialization-options ()
  "Return the options Bylaws Language Server reads when it starts.
An option with no value stays out, so the server keeps its own default."
  (let ((options '())
        (rules (lsp-bylaws--texts lsp-bylaws-rules))
        (only (lsp-bylaws--texts lsp-bylaws-only))
        (skip (lsp-bylaws--texts lsp-bylaws-skip))
        (baseline (lsp-bylaws--text lsp-bylaws-baseline))
        (delay lsp-bylaws-refresh-delay-milliseconds))
    (when rules (setq options (plist-put options :rules rules)))
    (when only (setq options (plist-put options :only only)))
    (when skip (setq options (plist-put options :skip skip)))
    (when baseline (setq options (plist-put options :baseline baseline)))
    (when (and (integerp delay) (> delay 0))
      (setq options (plist-put options :refreshDelayMilliseconds delay)))
    options))

(declare-function lsp-activate-on "lsp-mode")
(declare-function lsp-register-client "lsp-mode")
(declare-function lsp-stdio-connection "lsp-mode")
(declare-function make-lsp-client "lsp-mode")

;;;###autoload
(with-eval-after-load 'lsp-mode
  (lsp-register-client
   (make-lsp-client
    :new-connection
    (lsp-stdio-connection (lambda () lsp-bylaws-server-command))
    :activation-fn (lsp-activate-on "swift")
    :initialization-options #'lsp-bylaws--initialization-options
    :server-id 'bylaws
    :add-on? t)))

(provide 'lsp-bylaws)
;;; lsp-bylaws.el ends here
