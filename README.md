# dired-copy-paste
dired-copy-paste.el enables you to cut/copy/paste files and directries in emacs dired-mode.

# Install 

Using straight and use-package 
```
(use-package dired-copy-paste
  :straight (dired-copy-paste :type git :host github :repo "jsilve24/dired-copy-paste"))
```

## Ideas for Configuration

Emacs bindings:
```
(define-key dired-mode-map "\C-c\C-x" 'dired-copy-paste-do-cut)
(define-key dired-mode-map "\C-c\C-c" 'dired-copy-paste-do-copy)
(define-key dired-mode-map "\C-c\C-v" 'dired-copy-paste-do-paste)
```

Evil Bindings using General
```
(general-define-key
     :states 'normal
     :keymaps 'dired-mode-map
      ";"  #'(:ignore t)
     ";d" #'dired-copy-paste-do-cut
     ";y" #'dired-copy-paste-do-copy
     ";p" #'dired-copy-paste-do-paste)
```

# Recent Changes/News

Version 0.2 
* Updated to allow recursive copy-pasting or cut-pasting of directories
* 12/26/21 -- jsilve24 is now maintaining this package
