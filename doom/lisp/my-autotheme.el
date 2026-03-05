;;; my-autotheme.el --- Automatic light/dark theme switching -*- lexical-binding: t; -*-

(defcustom my/autotheme-light-theme 'modus-operandi
  "Preferred light theme."
  :type 'symbol :group 'my-autotheme)

(defcustom my/autotheme-dark-theme 'modus-vivendi
  "Preferred dark theme."
  :type 'symbol :group 'my-autotheme)

(defcustom my/autotheme-mode 'macos
  "Theme switching mode.
`light' or `dark' for fixed theme. `native' for solar-based switching.
`macos' for macOS appearance hooks (falls back to native)."
  :type '(choice (const light) (const dark) (const native) (const macos))
  :group 'my-autotheme)

;;; Solar-based switching

(defun my/autotheme--sunrise-sunset ()
  "Return (sunrise sunset) in minutes for today."
  (require 'solar)
  (let ((hours (solar-sunrise-sunset (calendar-current-date))))
    (mapcar (lambda (s) (* 60 s))
            (list (caar hours) (caadr hours)))))

(defun my/autotheme--now-minutes ()
  "Return current time in minutes since midnight."
  (let ((ct (decode-time)))
    (+ (* 60 (decoded-time-hour ct))
       (decoded-time-minute ct))))

(defun my/autotheme--day-p ()
  "Return t if the sun has risen."
  (let ((ss (my/autotheme--sunrise-sunset)))
    (<= (car ss) (my/autotheme--now-minutes) (cadr ss))))

;;; macOS appearance detection

(defun my/autotheme--emacs-mac-p ()
  "Return t if using railwaycat's emacs-mac build."
  (and (eq system-type 'darwin) (featurep 'mac-win)))

(defun my/autotheme--effective-mode ()
  "Return the effective mode after system detection."
  (if (and (eq my/autotheme-mode 'macos) (not (my/autotheme--emacs-mac-p)))
      'native
    my/autotheme-mode))

(defun my/autotheme--dark-or-light ()
  "Return `dark' or `light' based on mode."
  (let ((mode (my/autotheme--effective-mode)))
    (cond ((memq mode '(dark light)) mode)
          ((eq mode 'macos)
           (let ((appearance (plist-get (mac-application-state) :appearance)))
             (if (string= appearance "NSAppearanceNameDarkAqua") 'dark 'light)))
          ((eq mode 'native)
           (if (my/autotheme--day-p) 'light 'dark)))))

(defun my/autotheme--preferred-theme ()
  "Return the preferred theme."
  (if (eq (my/autotheme--dark-or-light) 'light)
      my/autotheme-light-theme
    my/autotheme-dark-theme))

;;; Theme loading

(defun my/autotheme-load (&optional theme)
  "Load THEME or the preferred theme. Animate on macOS if available."
  (let ((theme (or theme (my/autotheme--preferred-theme))))
    (unless (equal (car custom-enabled-themes) theme)
      (when (fboundp 'mac-start-animation)
        (mac-start-animation nil :type 'dissolve :duration 0.5))
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme theme t))))

(defun my/autotheme-toggle ()
  "Toggle between light and dark themes."
  (interactive)
  (my/autotheme-load
   (if (equal (car custom-enabled-themes) my/autotheme-dark-theme)
       my/autotheme-light-theme
     my/autotheme-dark-theme)))

;;; Initialization

(defvar my/autotheme--timer nil)

(defun my/autotheme-init ()
  "Load preferred theme and set up automatic switching."
  (my/autotheme-load)
  (let ((mode (my/autotheme--effective-mode)))
    (cond ((eq mode 'native)
           ;; Check every 5 minutes
           (setq my/autotheme--timer
                 (run-with-timer 300 300 #'my/autotheme-load)))
          ((eq mode 'macos)
           (add-hook 'mac-effective-appearance-change-hook
                     #'my/autotheme-load)))))

(provide 'my-autotheme)
;;; my-autotheme.el ends here
