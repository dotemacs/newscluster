#!/usr/bin/env sbcl --script
;;;
;;; cli-tests.lisp - Command-line test runner for newscluster
;;;
;;; Usage: ./cli-tests.lisp
;;;

(require :asdf)

;; Load Quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;; Setup ASDF paths
(push (pathname (directory-namestring *load-pathname*)) asdf:*central-registry*)
(push (merge-pathnames "fetcher/" (pathname (directory-namestring *load-pathname*)))
      asdf:*central-registry*)

;; Load systems
(format t "~&Loading systems...~%")
(ql:quickload '(:newscluster-fetcher :newscluster) :silent t)

;; Load test definitions
(load (merge-pathnames "tests.lisp" (pathname (directory-namestring *load-pathname*))))

;; Run tests and exit with appropriate code
(handler-case
    (multiple-value-bind (passed failed)
        (newscluster-tests:run-all-tests)
      (declare (ignore passed))
      (sb-ext:exit :code (if (zerop failed) 0 1)))
  (error (e)
    (format *error-output* "~&Error: ~A~%" e)
    (sb-ext:exit :code 1)))