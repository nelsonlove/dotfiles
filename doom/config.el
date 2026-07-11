;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(setq org-directory "/Users/nelson/Documents/00-09 System/02 Notes")

(setq user-full-name "Nelson Love"
      user-mail-address "nelson@nelson.love")

(setq doom-theme 'doom-one)

(setq display-line-numbers-type t)

(setq doom-font
      (font-spec
       :family "IosevkaTerm Nerd Font Mono"
       :size 14
       :weight 'light)
      doom-variable-pitch-font
      (font-spec
       :family "Iosevka Aile"
       :size 14
       :weight 'light)
      doom-big-font
      (font-spec
       :family "IosevkaTerm Nerd Font Mono"
       :size 20
       :weight 'light)
      doom-serif-font
      (font-spec
       :family "Iosevka"
       :weight 'light)
      doom-symbol-font
      (font-spec
       :family "Symbola"))

(setq window-combination-resize t)

(after! which-key
  (setq which-key-use-C-h-commands t)
  (setq which-key-idle-delay 0.1)
  (setq which-key-sort-order 'which-key-local-then-key-order))

(display-battery-mode 1)
(display-time-mode 1)

(blink-cursor-mode 1)

(repeat-mode 1)

(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)

(map! "s-d" #'duplicate-line)

(setq auto-revert-use-notify t)

(when (modulep! :ui popup)
  (set-popup-rule! "^\\*doom:\\(?:v?term\\|e?shell\\)-popup"
    :size 80 :side 'right :vslot -5 :select t :quit nil :ttl nil))

(after! gptel
  (setq gptel-backend
        (gptel-make-ollama "Ollama"
          :host "localhost:11434"
          :stream t
          :models '("qwen2.5:14b"))
        gptel-model "qwen2.5:14b"))

(use-package! claude-code-ide
  :commands (claude-code-ide claude-code-ide-resume
             claude-code-ide-stop claude-code-ide-switch-to-buffer
             claude-code-ide-continue)
  :config
  ;; Clear CLAUDECODE so nested sessions aren't rejected — tmux often
  ;; carries a stale CLAUDECODE=1 from the parent session.
  (setenv "CLAUDECODE")
  (setq claude-code-ide-terminal-backend 'vterm
        claude-code-ide-cli-extra-flags "--dangerously-skip-permissions")
  (map! :leader
        (:prefix ("c" . "claude")
         :desc "Start Claude"      "c" #'claude-code-ide
         :desc "Resume"            "r" #'claude-code-ide-resume
         :desc "Stop"              "s" #'claude-code-ide-stop
         :desc "Switch to buffer"  "b" #'claude-code-ide-switch-to-buffer
         :desc "Continue"          "n" #'claude-code-ide-continue)))

(add-hook! emacs-lisp-mode-hook #'aggressive-indent-mode)

(setq org-element-use-cache nil)

(defun +org-lint-flymake (report-fn &rest _)
  "Flymake backend that runs `org-lint' on the current buffer."
  (let ((diags '()))
    (dolist (entry (org-lint))
      (let* ((vec (cadr entry))           ; [LINE TRUST DESCRIPTION CHECKER]
             (line-str (aref vec 0))
             (trust (aref vec 1))
             (msg (aref vec 2))
             (pos (get-text-property 0 'org-lint-marker line-str))
             (line (string-to-number line-str))
             (type (if (string= trust "high") :warning :note))
             (region (flymake-diag-region (current-buffer) line)))
        (push (flymake-make-diagnostic (current-buffer)
                                       (car region) (cdr region)
                                       type msg)
              diags)))
    (funcall report-fn (nreverse diags))))

(defun +org-lint-flymake-setup ()
  "Add `+org-lint-flymake' to flymake diagnostic functions."
  (add-hook 'flymake-diagnostic-functions #'+org-lint-flymake nil t))

(add-hook 'org-mode-hook #'+org-lint-flymake-setup)

(defun +org/format-buffer ()
  "Normalize whitespace in the current org buffer."
  (interactive)
  (when (derived-mode-p 'org-mode)
    (let ((inhibit-modification-hooks t)
          (save-silently t))
      (save-excursion
        (save-restriction
          (widen)
          ;; Strip trailing whitespace
          (delete-trailing-whitespace)
          ;; Collapse 3+ consecutive blank lines to 2
          (goto-char (point-min))
          (while (re-search-forward "\n\\{4,\\}" nil t)
            (replace-match "\n\n\n"))
          ;; Blank line before blocks (#+begin_...)
          (goto-char (point-min))
          (while (re-search-forward
                  "\\([^\n]\\)\n\\(#\\+begin_\\)" nil t)
            (replace-match "\\1\n\n\\2"))
          ;; Blank line after blocks (#+end_...)
          (goto-char (point-min))
          (while (re-search-forward
                  "\\(#\\+end_[^\n]*\\)\n\\([^\n#]\\)" nil t)
            (replace-match "\\1\n\n\\2"))
          ;; Two blank lines before top-level headings
          (goto-char (point-min))
          (while (re-search-forward "\\([^\n]\\)\n\\(\\* [^\n]\\)" nil t)
            (replace-match "\\1\n\n\n\\2"))
          ;; One blank line before deeper headings
          (goto-char (point-min))
          (while (re-search-forward
                  "\\([^\n]\\)\n\\(\\*\\{2,\\} [^\n]\\)" nil t)
            (replace-match "\\1\n\n\\2"))
          ;; One blank line after heading lines (but not before
          ;; :PROPERTIES: drawers or planning lines which must follow
          ;; headings immediately)
          (goto-char (point-min))
          (while (re-search-forward
                  "\\(^\\*+ [^\n]*\\)\n\\([^\n*:]\\)" nil t)
            (unless (save-excursion
                      (goto-char (match-beginning 2))
                      (looking-at "\\(DEADLINE\\|SCHEDULED\\|CLOSED\\)"))
              (replace-match "\\1\n\n\\2")))
          ;; Fix list indentation (org-indent-region mishandles
          ;; property drawers, so only apply to list items)
          (goto-char (point-min))
          (while (re-search-forward "^[ \t]*[-+*] \\|^[ \t]*[0-9]+[.)]] " nil t)
            (org-indent-region
             (line-beginning-position)
             (save-excursion (org-end-of-item-list) (point))))
          ;; Single newline at EOF
          (goto-char (point-max))
          (delete-blank-lines)
          (unless (bolp) (insert "\n")))))))

(add-hook 'org-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'+org/format-buffer nil t)))

(set-eglot-client! '(python-mode python-ts-mode)
  '("ruff" "server"))

(with-eval-after-load 'python
  (set-formatter! 'ruff :modes '(python-mode python-ts-mode)))
