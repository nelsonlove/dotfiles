;;; vanilla-config.el -*- lexical-binding: t; -*-
;;; Remaining items not yet migrated to Doom config.

;;; Mouse in terminal
(unless (display-graphic-p)
  (xterm-mouse-mode 1))

;;; Dictionary — side window lookup
(keymap-set global-map "M-#" #'dictionary-lookup-definition)
(add-to-list 'display-buffer-alist
             '("^\\*Dictionary\\*"
               (display-buffer-in-side-window)
               (side . left)
               (window-width . 70)))

;;; Scrolling
(setq auto-window-vscroll nil)
(customize-set-variable 'fast-but-imprecise-scrolling t)
(customize-set-variable 'scroll-conservatively 101)
(customize-set-variable 'scroll-margin 0)
(customize-set-variable 'scroll-preserve-screen-position t)

;;; Pulse line — visual flash on scroll/window switch
(defun my/pulse-line (&rest _)
  "Pulse the current line."
  (pulse-momentary-highlight-one-line (point)))
(dolist (command '(scroll-up-command scroll-down-command
                   recenter-top-bottom other-window))
  (advice-add command :after #'my/pulse-line))

;;; Obsidian
(require 'obsidian)
(setq obsidian-directory "~/Library/Mobile Documents/iCloud~md~obsidian/Documents")
(global-obsidian-mode t)
(define-key obsidian-mode-map (kbd "C-c C-n") 'obsidian-capture)
(define-key obsidian-mode-map (kbd "C-c C-l") 'obsidian-insert-link)
(define-key obsidian-mode-map (kbd "C-c C-o") 'obsidian-follow-link-at-point)
(define-key obsidian-mode-map (kbd "C-c C-p") 'obsidian-jump)
(define-key obsidian-mode-map (kbd "C-c C-b") 'obsidian-backlinks)

;;; Docker
(global-set-key (kbd "C-c d") 'docker)

;;; vanilla-config.el ends here
