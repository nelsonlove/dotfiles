;;; my-org.el --- Org-mode customizations -*- lexical-binding: t; -*-

(with-eval-after-load 'org

  ;; Appearance
  (setq org-ellipsis "…"
        org-startup-folded 'show2levels
        org-log-into-drawer t
        org-list-demote-modify-bullet
        '(("A)" . "1)")
          ("1)" . "A.")
          ("A." . "1.")
          ("1." . "a.")
          ("a." . "+")
          ("+"  . "-")
          ("*"  . "-")))

  ;; TODO keywords
  (setq org-todo-keywords
        '((sequence "TODO(t/!)" "STRT(s/!)" "|" "DONE(d/!)")
          (sequence "HOLD(h@/!)" "WAIT(w@/!)" "|" "CANC(x@/!)")
          (sequence "APPT(m/!)" "|"))
        org-todo-keyword-faces
        '(("TODO" . "orange red")
          ("STRT" . "yellow")
          ("HOLD" . "orange")
          ("WAIT" . "LightSkyBlue2")
          ("APPT" . "dark orange")
          ("DONE" . "YellowGreen")
          ("CANC" . "white"))
        org-tag-alist
        '(("FLAGGED" . ?!)
          ("emacs" . ?e)
          ("personal" . ?p)
          ("test" . ?t)
          ("bug" . ?b)
          ("people" . ?@)
          ("appt" . ?A)))

  ;; Agenda
  (setq org-agenda-block-separator ?─
        org-agenda-time-grid
        '((daily today require-timed)
          (800 1000 1200 1400 1600 1800 2000)
          " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄")
        org-agenda-current-time-string
        "⭠ now ─────────────────────────────────────────────────"
        org-agenda-tags-todo-honor-ignore-options t
        org-agenda-skip-deadline-if-done t
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-timestamp-if-done t)

  ;; Capture templates
  (setq org-capture-templates
        '(("t" "Todo" entry (file "inbox.org")
           "* TODO %?\n%U\n%a" :clock-in t :clock-resume t :prepend t)
          ("n" "Note" entry (file "inbox.org")
           "* %?\n%U\n%a" :clock-in t :clock-resume t :prepend t)
          ("s" "Someday/Maybe" entry (file "someday.org")
           "* TODO %?\n%U\n%a" :clock-in t :clock-resume t :prepend t)
          ("e" "Emacs todo" entry (file "someday.org")
           "* TODO %? :emacs:\n%U\n%a" :clock-in t :clock-resume t :prepend t)))

  ;; Refile
  (setq org-refile-targets
        '((nil :maxlevel . 9)
          (org-agenda-files :maxlevel . 9))
        org-refile-allow-creating-parent-nodes 'confirm
        org-refile-target-verify-function
        (lambda () (not (member (nth 2 (org-heading-components))
                                org-done-keywords))))

  ;; Editing behavior
  (setq org-special-ctrl-k t
        org-yank-adjusted-subtrees t
        org-M-RET-may-split-line t
        org-insert-heading-respect-content nil
        org-treat-S-cursor-todo-selection-as-state-change nil
        org-use-speed-commands t
        org-fast-tag-selection-single-key t
        org-fold-catch-invisible-edits 'error
        org-read-date-prefer-future 'time
        org-cycle-separator-lines 0
        org-blank-before-new-entry '((heading) (plain-list-item . auto)))

  ;; Export
  (setq org-html-use-unicode-chars t
        org-export-with-smart-quotes nil
        org-export-with-timestamps nil)

  ;; Babel defaults
  (setq org-babel-results-keyword "results"
        org-babel-default-header-args:sh     '((:results . "output replace"))
        org-babel-default-header-args:bash   '((:results . "output replace"))
        org-babel-default-header-args:python '((:results . "output replace")))

  ;; Structure templates
  (dolist (tmpl '(("sh" . "src sh")
                  ("py" . "src python")))
    (add-to-list 'org-structure-template-alist tmpl))

  ;; Crypt
  (require 'org-crypt)
  (setq org-crypt-disable-auto-save 'encrypt)
  (add-to-list 'org-tag-alist '("crypt" . ?k))

  ;; Archive
  (setq org-archive-mark-done nil
        org-archive-location
        (expand-file-name "archive/%s_archive::* Archived Tasks" org-directory))
  (add-to-list 'auto-mode-alist '("\\.org_archive\\'" . org-mode))

  ;; ID links
  (setq org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id)

  ;; Custom link face for internal links
  (defface my/org-link-id
    `((t (:inherit org-link
          :foreground ,(face-foreground 'diary))))
    "Face for internal org id/roam links."
    :group 'org-faces)
  (org-link-set-parameters "id" :face 'my/org-link-id)

  ;; Reset checkboxes on DONE
  (add-to-list 'org-modules 'org-checklist)

  ;; Auto-save org buffers hourly
  (run-at-time "00:59" 3600 'org-save-all-org-buffers)

  ;; Toggle link display
  (define-key org-mode-map (kbd "C-c t C-l") #'org-toggle-link-display))

(provide 'my-org)
;;; my-org.el ends here
