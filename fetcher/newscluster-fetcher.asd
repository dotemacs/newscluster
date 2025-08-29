;;;
;;; newscluster-fetcher.asd - ASDF system definition
;;;

(defsystem #:newscluster-fetcher
  :description "Common Lisp feed fetcher using feeder library"
  :author "newscluster"
  :depends-on (#:feeder           ; RSS/Atom parsing with category support
               #:cl-feedparser    ; Alternative RSS/Atom parser
               #:plump            ; HTML/XML manipulation (used by feeder)
               #:drakma           ; HTTP client
               #:cl-ppcre         ; Regular expressions
               #:ironclad         ; Cryptography (MD5)
               #:flexi-streams    ; Character encoding
               #:local-time       ; Time manipulation
               #:alexandria       ; Utility functions
               #:sb-posix)        ; POSIX functions
  :components ((:file "package")
               (:file "fetcher" :depends-on ("package"))
               (:file "fetcher-feedparser" :depends-on ("package" "fetcher"))))