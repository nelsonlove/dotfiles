;;; my-macos.el --- macOS tweaks for emacs-mac port -*- lexical-binding: t; -*-

(when (eq system-type 'darwin)

  ;; Smooth scrolling with mouse wheel
  (when (boundp 'mac-mouse-wheel-smooth-scroll)
    (setq mac-mouse-wheel-smooth-scroll t))

  (setq ns-use-native-fullscreen t)

  ;; Animation control for railwaycat's emacs-mac
  (defvar my/mac-use-animation t
    "When non-nil, use Mac animations.")

  (when (fboundp 'mac-start-animation)
    (advice-add 'mac-start-animation :before-while
                (lambda (frame-or-window &rest _properties)
                  my/mac-use-animation)))

  ;; Smart fullscreen toggle (native vs emacs)
  (defun my/toggle-fullscreen (&optional frame)
    "Toggle fullscreen, preferring native macOS fullscreen."
    (interactive)
    (if (and ns-use-native-fullscreen (fboundp 'toggle-frame-ns-fullscreen))
        (toggle-frame-ns-fullscreen frame)
      (toggle-frame-fullscreen frame)))

  (keymap-global-set "<remap> <toggle-frame-fullscreen>" #'my/toggle-fullscreen)

  ;; Open terminal at current directory
  (defun my/open-in-alacritty (&optional path)
    "Open Alacritty in PATH or current directory."
    (interactive (list default-directory))
    (let ((path (expand-file-name
                 (or path (if (derived-mode-p 'dired-mode)
                              (dired-get-file-for-visit)
                            default-directory)))))
      (start-process "alacritty" nil "alacritty"
                     "--working-directory" path))))

(provide 'my-macos)
;;; my-macos.el ends here
