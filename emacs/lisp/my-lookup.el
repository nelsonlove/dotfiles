;;; my-lookup.el --- Lookup utilities -*- lexical-binding: t; -*-

(defun my/ascii-lookup (str)
  "Display ASCII values for each character in STR."
  (interactive "MString: ")
  (message "%s" (string-to-list str)))

(defun my/key-lookup (key-sequence)
  "Find all keymaps where KEY-SEQUENCE is bound."
  (interactive
   (list (read-key-sequence "Press key: ")))
  (let ((result))
    (mapatoms
     (lambda (ob)
       (when (and (boundp ob) (keymapp (symbol-value ob)))
         (let ((m (lookup-key (symbol-value ob) key-sequence)))
           (when (and m (or (functionp m)
                            (symbolp m)
                            (keymapp m)))
             (push ob result)))))
     obarray)
    (message "Key sequence %s is bound in: %s"
             (key-description key-sequence)
             (if result
                 (mapconcat #'symbol-name result ", ")
               "nothing"))))

(provide 'my-lookup)
;;; my-lookup.el ends here
