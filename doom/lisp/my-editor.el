;;; my-editor.el --- Editor utilities -*- lexical-binding: t; -*-

(defun my/duplicate-line ()
  "Duplicate line at point."
  (interactive)
  (let ((line (thing-at-point 'line t)))
    (save-excursion
      (forward-line 1)
      (insert line))))

(keymap-global-set "s-d" #'my/duplicate-line)

(defun my/fill-or-unfill-paragraph (&optional unfill region)
  "Fill paragraph (or REGION).
With prefix argument UNFILL, unfill it instead."
  (interactive (progn
                 (barf-if-buffer-read-only)
                 (list (if current-prefix-arg 'unfill) t)))
  (let ((fill-column (if unfill (point-max) fill-column)))
    (fill-paragraph nil region)))

(keymap-global-set "<remap> <fill-paragraph>" #'my/fill-or-unfill-paragraph)

(defun my/arrayify (&optional single region)
  "Turn strings on newlines in REGION into a quoted list.
With prefix arg SINGLE, use single quotes."
  (interactive (progn
                 (barf-if-buffer-read-only)
                 (list (if current-prefix-arg 'single) t)))
  (let* ((quote (if single "'" "\""))
         (insertion
          (mapconcat
           (lambda (item) (format "%s%s%s" quote item quote))
           (split-string (buffer-substring
                          (region-beginning)
                          (region-end))) ", ")))
    (call-interactively #'delete-region)
    (insert insertion)))

(provide 'my-editor)
;;; my-editor.el ends here
