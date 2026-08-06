;;; dired-copy-paste.el --- cut/copy/paste files and directories in Dired -*- lexical-binding: t; -*-

;; Copyrigth (C) 2011 Hidaka Uchida

;; Author: Hidaka Uchida <hidaka.uchida@gmail.com>
;; Maintainer: Justin Silverman <justinsilverman@psu.edu> (as of December 26, 2021)
;; Version: 0.3
;; Created: Jan 8 2011
;; Last Updated: 2026-08-06
;; Keywords; dired, cut, copy, paste

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to the
;; Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.


;;; Commentary:
;;
;; dired-copy-paste.el enables you to cut/copy/paste files and directries in dired-mode.

;;; Install:
;;
;; Put this file into your load-path and add the
;; following expression to your ~/.emacs.
;;
;; (require 'dired-copy-paste)

;;; Usage:
;;
;; In dired-mode,
;;
;;  M-x dired-copy-paste-do-cut   <C-c C-w>: Cut a file/dir on current line or all marked file/dir(s).
;;  M-x dired-copy-paste-do-copy  <C-c C-c>: Copy a file/dir on current line or all marked file/dir(s).
;;  M-x dired-copy-paste-do-paste <C-c C-y>: Paste cut/copied file/dir(s) into current directory.
;;
;; You can customize default key bindings as follows.
;;
;; (define-key dired-mode-map "\C-c\C-x" 'dired-copy-paste-do-cut)
;; (define-key dired-mode-map "\C-c\C-c" 'dired-copy-paste-do-copy)
;; (define-key dired-mode-map "\C-c\C-v" 'dired-copy-paste-do-paste)

;;; Code:

(require 'cl-lib)
(require 'dired)

(defgroup dired-copy-paste nil
  "Clipboard-style file operations for Dired."
  :group 'dired)

(defcustom dired-copy-paste-rsync-threshold (* 10 1024 1024)
  "Minimum combined source size in bytes for an automatic rsync transfer.

This applies only to copy operations with exactly one remote endpoint.
Directories are always eligible because calculating their total size through
TRAMP would be more expensive than starting rsync.  Set this to nil to disable
automatic rsync transfers."
  :type '(choice (const :tag "Disable automatic rsync" nil)
                 (natnum :tag "Bytes"))
  :group 'dired-copy-paste)

(defcustom dired-copy-paste-rsync-options
  '("--archive" "--human-readable" "--info=progress2" "--protect-args")
  "Options passed to rsync for automatic remote copies."
  :type '(repeat string)
  :group 'dired-copy-paste)

(defcustom dired-copy-paste-rsync-remote-methods
  '("ssh" "sshx" "scp" "scpx" "rsync")
  "TRAMP methods that can be represented as an rsync-over-SSH endpoint.

Multi-hop connections and hosts with an explicit TRAMP port are not converted;
those transfers continue to use the normal Dired/TRAMP copy implementation."
  :type '(repeat string)
  :group 'dired-copy-paste)

(define-key dired-mode-map "\C-c\C-w" 'dired-copy-paste-do-cut)
(define-key dired-mode-map "\C-c\C-c" 'dired-copy-paste-do-copy)
(define-key dired-mode-map "\C-c\C-y" 'dired-copy-paste-do-paste)

(defvar dired-copy-paste-func nil)
(defvar dired-copy-paste-stored-file-list nil)

(defun dired-copy-paste--rsync-remote-supported-p (file)
  "Return non-nil when FILE can be expressed as an rsync endpoint."
  (or (not (file-remote-p file))
      (let ((host (file-remote-p file 'host)))
        (and (member (file-remote-p file 'method)
                     dired-copy-paste-rsync-remote-methods)
             (not (file-remote-p file 'hop))
             ;; In TRAMP syntax HOST#PORT denotes an explicit port.  Passing
             ;; that directly to rsync would silently address the wrong host.
             (not (string-match-p "#" host))))))

(defun dired-copy-paste--single-remote-endpoint-p (sources destination)
  "Return non-nil when SOURCES and DESTINATION have one remote endpoint."
  (when sources
    (let ((source-remote (file-remote-p (car sources)))
          (destination-remote (file-remote-p destination)))
      (and (not (eq (and source-remote t) (and destination-remote t)))
           (cl-every
            (lambda (source)
              (equal (file-remote-p source) source-remote))
            sources)
           (cl-every #'dired-copy-paste--rsync-remote-supported-p
                     (cons destination sources))))))

(defun dired-copy-paste--large-source-p (sources)
  "Return non-nil when SOURCES warrant an rsync transfer.

The threshold applies to their combined size.  A directory qualifies without
a recursive size scan."
  (let ((remaining dired-copy-paste-rsync-threshold)
        large)
    (while (and sources (not large))
      (let* ((attributes (file-attributes (car sources) 'string))
             (type (and attributes (file-attribute-type attributes)))
             (size (and attributes (file-attribute-size attributes))))
        (cond
         ((eq type t)
          (setq large t))
         ((and (integerp size) (>= size remaining))
          (setq large t))
         ((integerp size)
          (setq remaining (- remaining size)))))
      (setq sources (cdr sources)))
    large))

(defun dired-copy-paste--use-rsync-p (sources destination)
  "Return non-nil when copying SOURCES to DESTINATION should use rsync."
  (and (eq dired-copy-paste-func 'dired-copy-file)
       (numberp dired-copy-paste-rsync-threshold)
       (executable-find "rsync")
       (dired-copy-paste--single-remote-endpoint-p sources destination)
       (or (zerop dired-copy-paste-rsync-threshold)
           (dired-copy-paste--large-source-p sources))))

(defun dired-copy-paste-rsync-path (file)
  "Convert FILE from TRAMP syntax to an rsync-compatible path.

Local paths are returned expanded.  This function does not contact the remote
host.  Callers should first check that FILE satisfies
`dired-copy-paste--rsync-remote-supported-p'."
  (if (not (file-remote-p file))
      (expand-file-name file)
    (let* ((user (file-remote-p file 'user))
           (host (file-remote-p file 'host))
           (localname (file-remote-p file 'localname))
           (host (if (and (string-match-p ":" host)
                          (not (string-prefix-p "[" host)))
                     (format "[%s]" host)
                   host)))
      (format "%s%s:%s"
              (if (and user (not (string= user "")))
                  (concat user "@")
                "")
              host localname))))

;;;###autoload
(defun dired-copy-paste-copy-rsync-path (&optional file)
  "Copy FILE in rsync syntax to the kill ring.

Interactively, use the entry at point in Dired or the file visited by the
current buffer.  Return the copied path without contacting a remote host."
  (interactive)
  (let ((file (or file
                  (if (derived-mode-p 'dired-mode)
                      (dired-get-file-for-visit)
                    buffer-file-name))))
    (unless file
      (user-error "The current buffer is not visiting a file"))
    (unless (dired-copy-paste--rsync-remote-supported-p file)
      (user-error "Cannot express this TRAMP path as an rsync endpoint"))
    (let ((path (dired-copy-paste-rsync-path file)))
      (kill-new path)
      (message "Copied rsync path: %s" path)
      path)))

(defun dired-copy-paste--rsync-sentinel (process event)
  "Handle completion of an rsync PROCESS described by EVENT."
  (let ((original-sentinel
         (process-get process 'dired-copy-paste-original-sentinel)))
    (when original-sentinel
      (funcall original-sentinel process event)))
  (when (and (memq (process-status process) '(exit signal))
             (not (process-get process 'dired-copy-paste-finished)))
    (process-put process 'dired-copy-paste-finished t)
    (let ((destination-buffer
           (process-get process 'dired-copy-paste-destination-buffer))
          (count (process-get process 'dired-copy-paste-file-count)))
      (if (and (eq (process-status process) 'exit)
               (zerop (process-exit-status process)))
          (progn
            (when (buffer-live-p destination-buffer)
              (with-current-buffer destination-buffer
                (revert-buffer)))
            (message "rsync pasted %d file/dir(s)" count))
        (message "rsync paste failed; see %s"
                 (buffer-name (process-buffer process)))))))

(defun dired-copy-paste--start-rsync (sources destination destination-buffer)
  "Start an interactive rsync from SOURCES to DESTINATION.

DESTINATION-BUFFER is reverted after a successful transfer."
  (require 'comint)
  (let* ((program (executable-find "rsync"))
         (arguments
          (append dired-copy-paste-rsync-options
                  (list "--")
                  (mapcar #'dired-copy-paste-rsync-path sources)
                  (list (dired-copy-paste-rsync-path destination))))
         (buffer (generate-new-buffer "*dired-copy-paste-rsync*"))
         process)
    (with-current-buffer buffer
      (insert "$ " program " "
              (mapconcat #'shell-quote-argument arguments " ") "\n"))
    (apply #'make-comint-in-buffer
           "dired-copy-paste-rsync" buffer program nil arguments)
    (setq process (get-buffer-process buffer))
    (process-put process 'dired-copy-paste-original-sentinel
                 (process-sentinel process))
    (process-put process 'dired-copy-paste-destination-buffer
                 destination-buffer)
    (process-put process 'dired-copy-paste-file-count (length sources))
    (set-process-sentinel process #'dired-copy-paste--rsync-sentinel)
    (set-process-query-on-exit-flag process nil)
    ;; A comint buffer allows password or MFA input when SSH cannot authenticate
    ;; noninteractively.  Display it without taking focus from the Dired target.
    (display-buffer buffer)
    (message "Started rsync for %d file/dir(s); use %s if SSH requests input"
             (length sources) (buffer-name buffer))
    process))

(defun dired-copy-paste-parse-files-for-directories (fns)
    "Add slashes to the end of files that are directories."
    (mapcar (lambda (fn)
	      (if (file-directory-p fn)
		  (concat fn "/")
		fn))
	    fns))


(defun dired-copy-paste-do-cut ()
  "In dired-mode, cut a file/dir on current line or all marked file/dir(s)."
  (interactive)
  (setq dired-copy-paste-stored-file-list (dired-copy-paste-parse-files-for-directories
					   (dired-get-marked-files))
        dired-copy-paste-func 'rename-file)
  (message
   (format "%S is/are cut."dired-copy-paste-stored-file-list)))


(defun dired-copy-paste-do-copy ()
  "In dired-mode, copy a file/dir on current line or all marked file/dir(s)."
  (interactive)
  (setq dired-copy-paste-stored-file-list (dired-get-marked-files)
        dired-copy-paste-func 'dired-copy-file)
  (message
   (format "%S is/are copied."dired-copy-paste-stored-file-list)))


(defun dired-copy-paste-do-paste ()
  "In dired-mode, paste cut/copied file/dir(s) into current directory."
  (interactive)
  (unless (and dired-copy-paste-func dired-copy-paste-stored-file-list)
    (user-error "No copied or cut files to paste"))
  (let ((destination (dired-current-directory)))
    (if (dired-copy-paste--use-rsync-p
         dired-copy-paste-stored-file-list destination)
        (dired-copy-paste--start-rsync
         dired-copy-paste-stored-file-list destination (current-buffer))
      (let ((stored-file-list nil))
        (dolist (stored-file dired-copy-paste-stored-file-list)
          (funcall dired-copy-paste-func stored-file destination 1)
          (push stored-file stored-file-list))
        (when (eq dired-copy-paste-func 'rename-file)
          (setq dired-copy-paste-stored-file-list nil
                dired-copy-paste-func nil))
        (revert-buffer)
        (message "%d file/dir(s) pasted into current directory."
                 (length stored-file-list))))))


(provide 'dired-copy-paste)
