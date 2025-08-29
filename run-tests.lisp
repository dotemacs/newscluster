#!/usr/bin/env sbcl --script
;;;
;;; run-tests.lisp - Run fetcher tests
;;;

;; Just run the test-fetcher.lisp script
(load (merge-pathnames "test-fetcher.lisp" 
                       (pathname (directory-namestring *load-pathname*))))