;;; my-buffers.el --- Buffer management utilities -*- lexical-binding: t; -*-

(setq dired-kill-when-opening-new-dired-buffer t)

(defvar my/buffer-old-time 6
  "Number of hours before a buffer is considered old.")

(defun my/buffer-old-p (buf)
  "Return non-nil if BUF hasn't been viewed in `my/buffer-old-time' hours."
  (with-current-buffer buf
    (when buffer-display-time
      (time-less-p
       (* 60 60 my/buffer-old-time)
       (time-since buffer-display-time)))))

(defun my/buffer-dissociated-p (buf)
  "Return non-nil if BUF visits a file/dir that no longer exists."
  (with-current-buffer buf
    (or
     (and buffer-file-name
          (not (file-exists-p buffer-file-name)))
     (and (eq major-mode 'dired-mode)
          (boundp 'dired-directory)
          (stringp dired-directory)
          (not (file-exists-p (file-name-directory dired-directory)))))))

(defun my/ibuffer-mark-stale-buffers (arg)
  "Mark old unmodified buffers and buffers visiting deleted files.
With prefix ARG, mark all saved buffers regardless of age."
  (interactive "P")
  (ibuffer-mark-on-buffer
   (lambda (buf) (or (my/buffer-dissociated-p buf)
                     (and (buffer-file-name buf)
                          (not (buffer-modified-p buf))
                          (if arg t (my/buffer-old-p buf)))))))

(with-eval-after-load 'ibuffer
  (define-key ibuffer-mode-map "* t" #'my/ibuffer-mark-stale-buffers))

(provide 'my-buffers)
;;; my-buffers.el ends here
