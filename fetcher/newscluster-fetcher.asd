;;;
;;; newscluster-fetcher.asd - ASDF system definition
;;;

(defsystem #:newscluster-fetcher
  :description "Common Lisp replacement for Python feed fetcher"
  :author "newscluster"
  :depends-on (#:drakma           ; HTTP client
               #:cxml             ; XML parsing
               #:cxml-dom         ; DOM interface
               #:cl-ppcre         ; Regular expressions
               #:ironclad         ; Cryptography (MD5)
               #:flexi-streams    ; Character encoding
               #:sb-posix)        ; POSIX functions
  :components ((:file "package")
               (:file "xml-parser" :depends-on ("package"))
               (:file "fetcher" :depends-on ("package" "xml-parser"))))