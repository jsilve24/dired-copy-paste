# dired-copy-paste

dired-copy-paste.el enables you to cut/copy/paste files and directories in Emacs Dired.

## Install

Using straight.el and use-package:

```emacs-lisp
(use-package dired-copy-paste
  :straight (dired-copy-paste :type git :host github :repo "jsilve24/dired-copy-paste")
  :custom
  ;; Set to nil to disable automatic rsync, or choose another byte threshold.
  (dired-copy-paste-rsync-threshold (* 10 1024 1024)))
```

## Remote rsync copies

The ordinary copy/paste workflow also works between local and TRAMP Dired
buffers:

1. Mark one or more files in the source Dired buffer.
2. Run `dired-copy-paste-do-copy` (for example, `; y` below).
3. Open the destination Dired buffer and run `dired-copy-paste-do-paste`
   (for example, `; p`).

The paste command automatically uses asynchronous `rsync` when exactly one
side is remote and either:

- the marked regular files total at least
  `dired-copy-paste-rsync-threshold` bytes (10 MiB by default), or
- at least one marked source is a directory.

Directory size is not scanned recursively through TRAMP. Directories go
straight to rsync, avoiding many remote metadata round trips. The transfer
runs in a `*dired-copy-paste-rsync*` comint buffer, which shows progress and
accepts interactive SSH password or MFA input. After a successful transfer,
the destination Dired buffer is refreshed automatically.

Automatic rsync requires the local `rsync` executable and a supported
SSH-style TRAMP method (`ssh`, `sshx`, `scp`, `scpx`, or `rsync`). `rsync`
must also be available on the remote host. Small remote copies, local-to-local
copies, cuts, remote-to-remote copies, multi-hop connections, and connections
with an explicit TRAMP port continue to use Dired's normal file operations.

Set the threshold to another byte count, or disable automatic rsync entirely:

```emacs-lisp
;; Use rsync at 50 MiB.
(setq dired-copy-paste-rsync-threshold (* 50 1024 1024))

;; Always use the normal Dired/TRAMP copy implementation.
(setq dired-copy-paste-rsync-threshold nil)
```

For a manual terminal command, `M-x dired-copy-paste-copy-rsync-path` copies
the current Dired entry or visited file as `user@host:/path`. The underlying
`dired-copy-paste-rsync-path` conversion does not open a remote connection.

## Ideas for configuration

Emacs bindings:

```emacs-lisp
(define-key dired-mode-map "\C-c\C-x" 'dired-copy-paste-do-cut)
(define-key dired-mode-map "\C-c\C-c" 'dired-copy-paste-do-copy)
(define-key dired-mode-map "\C-c\C-v" 'dired-copy-paste-do-paste)
```

Evil bindings using General:

```emacs-lisp
(general-define-key
     :states 'normal
     :keymaps 'dired-mode-map
      ";"  #'(:ignore t)
     ";d" #'dired-copy-paste-do-cut
     ";y" #'dired-copy-paste-do-copy
     ";p" #'dired-copy-paste-do-paste)
```

## Recent changes

### Version 0.3

- Automatically use interactive, asynchronous rsync for large local-to-remote
  and remote-to-local copies.
- Copy TRAMP paths in rsync syntax for use in terminal commands.

### Version 0.2

- Updated to allow recursive copy-pasting or cut-pasting of directories.
- 12/26/21 — jsilve24 is now maintaining this package.
