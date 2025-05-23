;;; cider-selector.el --- Buffer selection command inspired by SLIME's selector -*- lexical-binding: t -*-

;; Copyright © 2012-2025 Tim King, Phil Hagelberg, Bozhidar Batsov
;; Copyright © 2013-2025 Bozhidar Batsov, Artur Malabarba and CIDER contributors
;;
;; Author: Tim King <kingtim@gmail.com>
;;         Phil Hagelberg <technomancy@gmail.com>
;;         Bozhidar Batsov <bozhidar@batsov.dev>
;;         Artur Malabarba <bruce.connor.am@gmail.com>
;;         Hugo Duncan <hugo@hugoduncan.org>
;;         Steve Purcell <steve@sanityinc.com>

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Buffer selection command inspired by SLIME's selector.

;;; Code:

(require 'cider-client)
(require 'cider-eval)
(require 'cider-scratch)
(require 'cider-profile)

(defconst cider-selector-help-buffer "*CIDER Selector Help*"
  "The name of the selector's help buffer.")

(defvar cider-selector-methods nil
  "List of buffer-selection methods for the `cider-selector' command.
Each element is a list (KEY DESCRIPTION FUNCTION).
DESCRIPTION is a one-line description of what the key selects.")

(defvar cider-selector-other-window nil
  "If non-nil use `switch-to-buffer-other-window'.
Not meant to be set by users.  It's used internally
by `cider-selector'.")

(defun cider-selector--recently-visited-buffer (modes &optional consider-visible-p)
  "Return the most recently visited buffer, deriving its `major-mode' from MODES.
MODES may be a symbol for a single mode, or a list of mode symbols.
CONSIDER-VISIBLE-P will allow handling of visible windows as well.
First pass only considers buffers that are not already visible.
Second pass will attempt one of visible ones for scenarios where the window
is visible, but not focused."
  (cl-loop for buffer in (buffer-list)
           when (and (with-current-buffer buffer
                       (apply #'derived-mode-p (if (listp modes)
                                                   modes
                                                 (list modes))))
                     ;; names starting with space are considered hidden by Emacs
                     (not (string-match-p "^ " (buffer-name buffer)))
                     (or consider-visible-p
                         (null (get-buffer-window buffer 'visible))))
           return buffer
           finally (if consider-visible-p
                       (error "Can't find unshown buffer in %S" modes)
                     (cider-selector--recently-visited-buffer modes t))))

;;;###autoload
(defun cider-selector (&optional other-window)
  "Select a new buffer by type, indicated by a single character.
The user is prompted for a single character indicating the method by
which to choose a new buffer.  The `?' character describes the
available methods.  OTHER-WINDOW provides an optional target.
See `def-cider-selector-method' for defining new methods."
  (interactive)
  (message "Select [%s]: "
           (apply #'string (mapcar #'car cider-selector-methods)))
  (let* ((cider-selector-other-window other-window)
         (ch (save-window-excursion
               (select-window (minibuffer-window))
               (read-char)))
         (method (cl-find ch cider-selector-methods :key #'car)))
    (cond (method
           (funcall (cl-caddr method)))
          (t
           (message "No method for character: ?\\%c" ch)
           (ding)
           (sleep-for 1)
           (discard-input)
           (cider-selector)))))

(defmacro def-cider-selector-method (key description &rest body)
  "Define a new `cider-select' buffer selection method.
KEY is the key the user will enter to choose this method.

DESCRIPTION is a one-line sentence describing how the method
selects a buffer.

BODY is a series of forms which are evaluated when the selector
is chosen.  The returned buffer is selected with
`switch-to-buffer'."
  (declare (indent 1))
  (let ((method `(lambda ()
                   (let ((buffer (progn ,@body)))
                     (cond ((not (and buffer (get-buffer buffer)))
                            (message "No such buffer: %S" buffer)
                            (ding))
                           ((get-buffer-window buffer)
                            (select-window (get-buffer-window buffer)))
                           (cider-selector-other-window
                            (switch-to-buffer-other-window buffer))
                           (t
                            (switch-to-buffer buffer)))))))
    `(setq cider-selector-methods
           (cl-sort (cons (list ,key ,description ,method)
                          (cl-remove ,key cider-selector-methods :key #'car))
                    #'< :key #'car))))

(def-cider-selector-method ?? "Selector help buffer."
  (ignore-errors (kill-buffer cider-selector-help-buffer))
  (with-current-buffer (get-buffer-create cider-selector-help-buffer)
    (insert "CIDER Selector Methods:\n\n")
    (cl-loop for (key line nil) in cider-selector-methods
             do (insert (format "%c:\t%s\n" key line)))
    (goto-char (point-min))
    (help-mode)
    (display-buffer (current-buffer) t))
  (cider-selector)
  (current-buffer))

(cl-pushnew (list ?4 "Select in other window" (lambda () (cider-selector t)))
            cider-selector-methods :key #'car)

(def-cider-selector-method ?c
  "Most recently visited clojure-mode buffer."
  (cider-selector--recently-visited-buffer '(clojure-mode clojure-ts-mode)))

(def-cider-selector-method ?e
  "Most recently visited emacs-lisp-mode buffer."
  (cider-selector--recently-visited-buffer 'emacs-lisp-mode))

(def-cider-selector-method ?q
  "Abort."
  (top-level))

(def-cider-selector-method ?r
  "Current REPL buffer or as a fallback, the most recently
visited cider-repl-mode buffer."
  (or (cider-current-repl)
      (cider-selector--recently-visited-buffer 'cider-repl-mode)))

(def-cider-selector-method ?m
  "Current connection's *nrepl-messages* buffer."
  (nrepl-messages-buffer (cider-current-repl)))

(def-cider-selector-method ?x
  "*cider-error* buffer."
  cider-error-buffer)

(def-cider-selector-method ?p
  "*cider-profile* buffer."
  cider-profile-buffer)

(def-cider-selector-method ?d
  "*cider-doc* buffer."
  cider-doc-buffer)

(def-cider-selector-method ?s
  "*cider-scratch* buffer."
  (cider-scratch-find-or-create-buffer))

(provide 'cider-selector)

;;; cider-selector.el ends here
