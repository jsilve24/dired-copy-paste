;;; dired-copy-paste-test.el --- Tests for dired-copy-paste -*- lexical-binding: t; -*-

(require 'ert)
(require 'dired-copy-paste)

(ert-deftest dired-copy-paste-rsync-path-converts-tramp-name ()
  (should
   (equal (dired-copy-paste-rsync-path
           "/ssh:jds6696@submit.hpc.psu.edu:~/work/results.dat")
          "jds6696@submit.hpc.psu.edu:~/work/results.dat")))

(ert-deftest dired-copy-paste-copy-rsync-path-uses-current-file ()
  (with-temp-buffer
    (setq buffer-file-name
          "/ssh:jds6696@submit.hpc.psu.edu:~/work/results.dat")
    (let (copied)
      (cl-letf (((symbol-function 'kill-new)
                 (lambda (text &optional _replace) (setq copied text))))
        (should
         (equal (dired-copy-paste-copy-rsync-path)
                "jds6696@submit.hpc.psu.edu:~/work/results.dat"))
        (should (equal copied
                       "jds6696@submit.hpc.psu.edu:~/work/results.dat"))))))

(ert-deftest dired-copy-paste-rsync-requires-one-remote-endpoint ()
  (should
   (dired-copy-paste--single-remote-endpoint-p
    '("/tmp/source") "/ssh:user@example.org:/tmp/target/"))
  (should-not
   (dired-copy-paste--single-remote-endpoint-p
    '("/ssh:user@example.org:/tmp/source")
    "/ssh:user@example.org:/tmp/target/"))
  (should-not
   (dired-copy-paste--single-remote-endpoint-p
    '("/tmp/source") "/tmp/target/")))

(ert-deftest dired-copy-paste-rsync-requires-one-remote-source-host ()
  (should-not
   (dired-copy-paste--single-remote-endpoint-p
    '("/ssh:user@one.example.org:/tmp/source"
      "/ssh:user@two.example.org:/tmp/source")
    "/tmp/target/")))

(ert-deftest dired-copy-paste-rsync-rejects-multihop-and-explicit-port ()
  (should-not
   (dired-copy-paste--rsync-remote-supported-p
    "/ssh:user@jump|ssh:user@example.org:/tmp/source"))
  (should-not
   (dired-copy-paste--rsync-remote-supported-p
    "/ssh:user@example.org#2222:/tmp/source")))

(ert-deftest dired-copy-paste-rsync-threshold-combines-file-sizes ()
  (let ((dired-copy-paste-rsync-threshold 100))
    (cl-letf (((symbol-function 'file-attributes)
               (lambda (file &optional _id-format)
                 (list nil 1 1 1 nil nil nil
                       (if (string-suffix-p "one" file) 60 40)
                       nil nil nil nil))))
      (should (dired-copy-paste--large-source-p '("one" "two"))))))

(ert-deftest dired-copy-paste-rsync-always-uses-directories ()
  (let ((dired-copy-paste-rsync-threshold 1000000))
    (cl-letf (((symbol-function 'file-attributes)
               (lambda (&rest _args)
                 (list t 1 1 1 nil nil nil 0 nil nil nil nil))))
      (should (dired-copy-paste--large-source-p '("directory"))))))

(ert-deftest dired-copy-paste-rsync-policy-does-not-change-cut-semantics ()
  (let ((dired-copy-paste-rsync-threshold 1)
        (dired-copy-paste-func 'dired-copy-file))
    (cl-letf (((symbol-function 'executable-find) (lambda (_program) "rsync"))
              ((symbol-function 'dired-copy-paste--large-source-p)
               (lambda (_sources) t)))
      (should
       (dired-copy-paste--use-rsync-p
        '("/tmp/source") "/ssh:user@example.org:/tmp/target/"))
      (setq dired-copy-paste-func 'rename-file)
      (should-not
       (dired-copy-paste--use-rsync-p
        '("/tmp/source") "/ssh:user@example.org:/tmp/target/")))))

(provide 'dired-copy-paste-test)
;;; dired-copy-paste-test.el ends here
