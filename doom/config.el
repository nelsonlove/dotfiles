;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(setq user-full-name "Nelson Love"
      user-mail-address "nelson@nelson.love")

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

(setq doom-theme 'doom-one)

(setq display-line-numbers-type t)

(setq org-directory "/Users/nelson/Documents/00-09 System/02 Notes")

(repeat-mode 1)

(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)

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
  (setq claude-code-ide-terminal-backend 'eat)
  (map! :leader
        (:prefix ("c" . "claude")
         :desc "Start Claude"      "c" #'claude-code-ide
         :desc "Resume"            "r" #'claude-code-ide-resume
         :desc "Stop"              "s" #'claude-code-ide-stop
         :desc "Switch to buffer"  "b" #'claude-code-ide-switch-to-buffer
         :desc "Continue"          "n" #'claude-code-ide-continue)))

(after! good-scroll
  (advice-remove #'scroll-up #'good-scroll--scroll-up)
  (advice-remove #'scroll-down #'good-scroll--scroll-down)
  (defadvice! +good-scroll-up-gui-only-a (fn &optional arg)
    :around #'scroll-up
    (if (and good-scroll-mode (display-graphic-p))
        (good-scroll-move (good-scroll--convert-line-to-step arg))
      (funcall fn arg)))
  (defadvice! +good-scroll-down-gui-only-a (fn &optional arg)
    :around #'scroll-down
    (if (and good-scroll-mode (display-graphic-p))
        (good-scroll-move (- (good-scroll--convert-line-to-step arg)))
      (funcall fn arg))))
