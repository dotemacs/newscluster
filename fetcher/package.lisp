;;;
;;; package.lisp - Package definition for newscluster-fetcher
;;;

(defpackage :newscluster-fetcher
  (:use :cl)
  (:export #:fetch-channel
           #:*user-agent*))

(in-package :newscluster-fetcher)