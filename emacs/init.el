;;; init.el -*- lexical-binding: t; -*-

;; XDG directory layout
(defvar my/data-dir
  (expand-file-name "emacs/" (or (getenv "XDG_DATA_HOME") "~/.local/share"))
  "Where packages and persistent data live.")

(defvar my/cache-dir
  (expand-file-name "emacs/" (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Where cache and throwaway files live.")

;; Route package.el and straight.el to data dir
(setq package-user-dir (expand-file-name "elpa" my/data-dir))
(setq straight-base-dir my/data-dir)

;; Route persistent state files to data dir
(setq savehist-file (expand-file-name "history" my/data-dir))
(setq recentf-save-file (expand-file-name "recentf" my/data-dir))
(setq save-place-file (expand-file-name "places" my/data-dir))
(setq bookmark-default-file (expand-file-name "bookmarks" my/data-dir))
(setq project-list-file (expand-file-name "projects" my/data-dir))
(setq projectile-known-projects-file (expand-file-name "projectile-bookmarks.eld" my/data-dir))
(setq projectile-cache-file (expand-file-name "projectile.cache" my/cache-dir))

;; Route cache files
(setq auto-save-list-file-prefix (expand-file-name "auto-save-list/.saves-" my/cache-dir))
(setq url-cache-directory (expand-file-name "url-cache" my/cache-dir))
(setq transient-history-file (expand-file-name "transient/history.el" my/cache-dir))
(setq transient-levels-file (expand-file-name "transient/levels.el" my/cache-dir))
(setq transient-values-file (expand-file-name "transient/values.el" my/cache-dir))

;; Custom file
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file nil :nomessage))

;; Load the main config
(load (expand-file-name "config.el" user-emacs-directory) nil :nomessage)

;; Restore normal garbage collection after startup
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 2 1000 1000))))

(provide 'init)
;;; init.el ends here
