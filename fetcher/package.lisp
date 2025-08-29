;;;
;;; package.lisp - Package definition for newscluster-fetcher
;;;

(defpackage #:newscluster-fetcher
  (:use #:cl)
  (:local-nicknames (#:feeder #:org.shirakumo.feeder))
  (:export #:fetch-channel))

(in-package #:newscluster-fetcher)