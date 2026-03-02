;;; early-init.el -*- lexical-binding: t; -*-

;; Increase startup speed by reducing garbage collection
(setq gc-cons-threshold (* 50 1000 1000))

;; Prevent package.el from loading before we configure it
(setq package-enable-at-startup nil)

;; Disable UI chrome early (prevents flash on startup)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; Silence native-comp warnings
(when (and (fboundp 'native-comp-available-p)
           (native-comp-available-p))
  (setq native-comp-async-report-warnings-errors nil))

;; Native compilation cache in XDG cache dir
(when (featurep 'native-compile)
  (startup-redirect-eln-cache
   (expand-file-name "emacs/eln-cache/"
                     (or (getenv "XDG_CACHE_HOME") "~/.cache"))))

(provide 'early-init)
;;; early-init.el ends here
