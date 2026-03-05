;;; config.el -*- lexical-binding: t; -*-

;;;; ========================================================================
;;;; Package Management
;;;; ========================================================================

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; All packages in one place
(setq package-selected-packages
      '(;; Completion framework
        vertico
        consult
        embark
        embark-consult
        marginalia
        orderless
        corfu
        corfu-terminal
        cape
        ;; UI
        all-the-icons
        nerd-icons
        helpful
        elisp-demos
        breadcrumb
        doom-themes
        doom-modeline
        dashboard
        which-key
        ;; Navigation & projects
        avy
        projectile
        ace-window
        ;; Git
        magit
        diff-hl
        ;; Editing
        yasnippet
        yasnippet-snippets
        ;; Apps
        obsidian
        docker
        gptel
))

;; Install missing packages
(when (seq-remove #'package-installed-p package-selected-packages)
  (package-refresh-contents)
  (package-install-selected-packages :noconfirm))

;;;; ========================================================================
;;;; Defaults
;;;; ========================================================================

;;; Mouse in terminal
(unless (display-graphic-p)
  (xterm-mouse-mode 1))

;;; Buffers
(customize-set-variable 'global-auto-revert-non-file-buffers t)
(global-auto-revert-mode 1)

;; Smart dired
(customize-set-variable 'dired-dwim-target t)
(customize-set-variable 'dired-auto-revert-buffer t)

;; Eshell scroll to bottom on input
(customize-set-variable 'eshell-scroll-to-bottom-on-input 'this)

;; Better buffer switching
(customize-set-variable 'switch-to-buffer-in-dedicated-window 'pop)
(customize-set-variable 'switch-to-buffer-obey-display-actions t)

;; ibuffer replaces default buffer list
(keymap-global-set "<remap> <list-buffers>" #'ibuffer-list-buffers)
(customize-set-variable 'ibuffer-movement-cycle nil)
(customize-set-variable 'ibuffer-old-time 24)

;;; Completion basics
(customize-set-variable 'tab-always-indent 'complete)
(customize-set-variable 'completion-cycle-threshold 3)
(customize-set-variable 'completion-category-overrides
                        '((file (styles . (partial-completion)))))
(customize-set-variable 'completions-detailed t)
(customize-set-variable 'xref-show-definitions-function
                        #'xref-show-definitions-completing-read)

;;; Editing
(delete-selection-mode)
(setq-default indent-tabs-mode nil)
(customize-set-variable 'kill-do-not-save-duplicates t)

;; Long lines
(setq-default bidi-paragraph-direction 'left-to-right)
(setq-default bidi-inhibit-bpa t)
(global-so-long-mode 1)

;; Dictionary
(keymap-set global-map "M-#" #'dictionary-lookup-definition)
(add-to-list 'display-buffer-alist
             '("^\\*Dictionary\\*"
               (display-buffer-in-side-window)
               (side . left)
               (window-width . 70)))

;; Spell checking
(with-eval-after-load 'ispell
  (when (executable-find ispell-program-name)
    (add-hook 'text-mode-hook #'flyspell-mode)
    (add-hook 'prog-mode-hook #'flyspell-prog-mode)))

;; Parens and pairs
(show-paren-mode 1)
(electric-pair-mode 1)

;;; Persistence
(add-hook 'after-init-hook #'recentf-mode)
(savehist-mode 1)
(save-place-mode 1)
(customize-set-variable 'bookmark-save-flag 1)

;;; Window management
(winner-mode 1)

(define-prefix-command 'my/windows-key-map)
(keymap-set 'my/windows-key-map "u" 'winner-undo)
(keymap-set 'my/windows-key-map "r" 'winner-redo)
(keymap-set 'my/windows-key-map "n" 'windmove-down)
(keymap-set 'my/windows-key-map "p" 'windmove-up)
(keymap-set 'my/windows-key-map "b" 'windmove-left)
(keymap-set 'my/windows-key-map "f" 'windmove-right)
(keymap-global-set "C-c w" 'my/windows-key-map)

;; Scrolling
(setq auto-window-vscroll nil)
(customize-set-variable 'fast-but-imprecise-scrolling t)
(customize-set-variable 'scroll-conservatively 101)
(customize-set-variable 'scroll-margin 0)
(customize-set-variable 'scroll-preserve-screen-position t)

;; Help and man pages
(customize-set-variable 'Man-notify-method 'aggressive)
(customize-set-variable 'ediff-window-setup-function 'ediff-setup-windows-plain)

;; Window display rules
(add-to-list 'display-buffer-alist
             '("\\*Help\\*"
               (display-buffer-reuse-window display-buffer-pop-up-window)))
(add-to-list 'display-buffer-alist
             '("\\*Completions\\*"
               (display-buffer-reuse-window display-buffer-pop-up-window)
               (inhibit-same-window . t)
               (window-height . 10)))

;;; Miscellaneous
(customize-set-variable 'load-prefer-newer t)
(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)
(repeat-mode 1)

;;;; ========================================================================
;;;; Completion Framework
;;;; ========================================================================

;;; Vertico — vertical minibuffer completion
(when (require 'vertico nil :noerror)
  (require 'vertico-directory)
  (customize-set-variable 'vertico-cycle t)
  (vertico-mode 1))

;;; Marginalia — annotations in minibuffer
(when (require 'marginalia nil :noerror)
  (marginalia-mode 1))

;;; Consult — enhanced search and navigation
(when (locate-library "consult")
  (keymap-global-set "C-s" 'consult-line)
  (keymap-set minibuffer-local-map "C-r" 'consult-history)
  (setq completion-in-region-function #'consult-completion-in-region))

;;; Orderless — fuzzy matching
(when (require 'orderless nil :noerror)
  (customize-set-variable 'completion-styles '(orderless basic))
  (customize-set-variable 'completion-category-overrides
                          '((file (styles . (partial-completion))))))

;;; Embark — context actions
(when (require 'embark nil :noerror)
  (keymap-global-set "<remap> <describe-bindings>" #'embark-bindings)
  (keymap-global-set "C-." 'embark-act)
  (setq prefix-help-command #'embark-prefix-help-command)
  (when (require 'embark-consult nil :noerror)
    (with-eval-after-load 'embark-consult
      (add-hook 'embark-collect-mode-hook #'consult-preview-at-point-mode))))

;;; Corfu — in-buffer completion popup
(when (require 'corfu nil :noerror)
  (unless (display-graphic-p)
    (when (require 'corfu-terminal nil :noerror)
      (corfu-terminal-mode +1)))
  (customize-set-variable 'corfu-cycle t)
  (customize-set-variable 'corfu-auto t)
  (customize-set-variable 'corfu-auto-prefix 2)
  (global-corfu-mode 1)
  (when (require 'corfu-popupinfo nil :noerror)
    (corfu-popupinfo-mode 1)
    (eldoc-add-command #'corfu-insert)
    (keymap-set corfu-map "M-p" #'corfu-popupinfo-scroll-down)
    (keymap-set corfu-map "M-n" #'corfu-popupinfo-scroll-up)
    (keymap-set corfu-map "M-d" #'corfu-popupinfo-toggle)))

;;; Cape — extra completion sources
(when (require 'cape nil :noerror)
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (advice-add 'pcomplete-completions-at-point :around #'cape-wrap-silent)
  ;; Sane corfu behavior in eshell
  (defun my/corfu-eshell ()
    "Corfu settings for eshell."
    (setq-local corfu-quit-at-boundary t
                corfu-quit-no-match t
                corfu-auto nil)
    (corfu-mode))
  (add-hook 'eshell-mode-hook #'my/corfu-eshell))

;;;; ========================================================================
;;;; UI
;;;; ========================================================================

;;; Helpful — better describe-* buffers
(when (require 'helpful nil :noerror)
  (keymap-set helpful-mode-map "<remap> <revert-buffer>" #'helpful-update)
  (keymap-global-set "<remap> <describe-command>"  #'helpful-command)
  (keymap-global-set "<remap> <describe-function>" #'helpful-callable)
  (keymap-global-set "<remap> <describe-key>"      #'helpful-key)
  (keymap-global-set "<remap> <describe-symbol>"   #'helpful-symbol)
  (keymap-global-set "<remap> <describe-variable>" #'helpful-variable)
  (keymap-global-set "C-h F"                       #'helpful-function))

(keymap-global-set "C-h K" #'describe-keymap)

;;; Line numbers — prog-mode and conf-mode, not org-mode
(dolist (mode '(conf-mode prog-mode))
  (add-hook (intern (format "%s-hook" mode)) #'display-line-numbers-mode))
(add-hook 'org-mode-hook (lambda () (display-line-numbers-mode -1)))
(setq-default display-line-numbers-grow-only t
              display-line-numbers-type t
              display-line-numbers-width 2)

;;; Elisp-demos — add examples to help buffers
(when (require 'elisp-demos nil :noerror)
  (advice-add 'helpful-update :after #'elisp-demos-advice-helpful-update))

;;; Pulse line — visual flash on scroll/window switch
(defun my/pulse-line (&rest _)
  "Pulse the current line."
  (pulse-momentary-highlight-one-line (point)))
(dolist (command '(scroll-up-command scroll-down-command
                   recenter-top-bottom other-window))
  (advice-add command :after #'my/pulse-line))

;;; Breadcrumb — show current function in header line
(when (require 'breadcrumb nil :noerror)
  (breadcrumb-mode))

;;;; ========================================================================
;;;; Appearance
;;;; ========================================================================

;; Theme
(require 'doom-themes)
(setq doom-themes-enable-bold t
      doom-themes-enable-italic t)
(load-theme 'doom-one :no-confirm)
(doom-themes-org-config)

;; Modeline
(require 'doom-modeline)
(setq doom-modeline-height 30
      doom-modeline-icon t
      doom-modeline-buffer-file-name-style 'truncate-upto-project)
(doom-modeline-mode 1)

;; Font
(when (display-graphic-p)
  (set-face-attribute 'default nil
                      :font "FantasqueSansM Nerd Font Mono"
                      :height 160))

;; Line spacing
(setq-default line-spacing 3)

;;;; ========================================================================
;;;; macOS
;;;; ========================================================================

(when (eq system-type 'darwin)
  (setq mac-option-modifier 'meta
        mac-command-modifier 'super
        mac-right-option-modifier 'none))

;;;; ========================================================================
;;;; Which-key
;;;; ========================================================================

(require 'which-key)
(setq which-key-idle-delay 0.3)
(which-key-mode 1)

;;;; ========================================================================
;;;; Personal
;;;; ========================================================================

(setq user-full-name "Nelson"
      user-mail-address "nelson@nelson.love")

;;;; ========================================================================
;;;; Navigation & Projects
;;;; ========================================================================

;; Avy — jump to visible text
(require 'avy)
(global-set-key (kbd "C-;") 'avy-goto-char-timer)
(global-set-key (kbd "M-g g") 'avy-goto-line)
(global-set-key (kbd "M-g w") 'avy-goto-word-1)
(setq avy-timeout-seconds 0.3)

;; Projectile — project management
(require 'projectile)
(setq projectile-project-search-path '("~/Repositories")
      projectile-indexing-method 'alien
      projectile-sort-order 'recentf)
(define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)
(projectile-mode 1)

;; Ace-window — quick window switching
(require 'ace-window)
(global-set-key (kbd "M-o") 'ace-window)
(setq aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l))

;;;; ========================================================================
;;;; Git
;;;; ========================================================================

;; Magit
(global-set-key (kbd "C-c g") 'magit-status)

;; diff-hl — git gutter markers
(require 'diff-hl)
(global-diff-hl-mode 1)
(add-hook 'magit-pre-refresh-hook 'diff-hl-magit-pre-refresh)
(add-hook 'magit-post-refresh-hook 'diff-hl-magit-post-refresh)

;;;; ========================================================================
;;;; Editing
;;;; ========================================================================

;; Yasnippet
(require 'yasnippet)
(yas-global-mode 1)

;; Eglot — LSP support (built-in)
(add-hook 'prog-mode-hook 'eglot-ensure)

;;;; ========================================================================
;;;; Apps
;;;; ========================================================================

;; Obsidian
(require 'obsidian)
(setq obsidian-directory "~/Library/Mobile Documents/iCloud~md~obsidian/Documents")
(global-obsidian-mode t)
(define-key obsidian-mode-map (kbd "C-c C-n") 'obsidian-capture)
(define-key obsidian-mode-map (kbd "C-c C-l") 'obsidian-insert-link)
(define-key obsidian-mode-map (kbd "C-c C-o") 'obsidian-follow-link-at-point)
(define-key obsidian-mode-map (kbd "C-c C-p") 'obsidian-jump)
(define-key obsidian-mode-map (kbd "C-c C-b") 'obsidian-backlinks)

;; Docker
(global-set-key (kbd "C-c d") 'docker)

;; gptel — LLM chat
(require 'gptel)
(setq gptel-model "qwen2.5:14b"
      gptel-backend (gptel-make-ollama "Ollama"
                      :host "localhost:11434"
                      :stream t
                      :models '("qwen2.5:14b")))
(setq gptel-directives
      '((default . "You are a helpful assistant. Always respond in English.")))
(global-set-key (kbd "C-c l") 'gptel-send)
(global-set-key (kbd "C-c L") 'gptel)
(add-hook 'gptel-post-stream-hook 'gptel-auto-scroll)
(add-hook 'gptel-post-response-functions 'gptel-end-of-response)

;;;; ========================================================================
;;;; Dashboard
;;;; ========================================================================

(require 'dashboard)
(setq dashboard-startup-banner 'logo
      dashboard-center-content t
      dashboard-items '((recents . 8)
                        (projects . 5)
                        (bookmarks . 5)))
(dashboard-setup-startup-hook)

;;;; ========================================================================
;;;; Server
;;;; ========================================================================

(require 'server)
(unless (server-running-p)
  (server-start))


;;;; ========================================================================
;;;; straight.el — packages not on MELPA
;;;; ========================================================================

(add-to-list 'warning-suppress-types '(straight))
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el"
                         (or (bound-and-true-p straight-base-dir) user-emacs-directory)))
      (bootstrap-version 6))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Claude Code IDE
(straight-use-package 'websocket)
(straight-use-package 'transient)
(straight-use-package 'web-server)
(straight-use-package
 '(claude-code-ide :type git :host github :repo "manzaltu/claude-code-ide.el"))

(when (require 'claude-code-ide nil t)
  (setq claude-code-ide-terminal-backend 'eat)
  (global-set-key (kbd "C-c c c") 'claude-code-ide)
  (global-set-key (kbd "C-c c r") 'claude-code-ide-resume)
  (global-set-key (kbd "C-c c s") 'claude-code-ide-stop)
  (global-set-key (kbd "C-c c b") 'claude-code-ide-switch-to-buffer)
  (global-set-key (kbd "C-c c n") 'claude-code-ide-continue))

;; Eat terminal emulator
(straight-use-package 'eat)

;; Ultra-scroll — smooth scrolling for emacs-mac
(straight-use-package '(ultra-scroll :type git :host github :repo "jdtsmith/ultra-scroll"))
(when (require 'ultra-scroll nil t)
  (ultra-scroll-mode 1))

(provide 'config)
;;; config.el ends here
