;;; 
;;; fetch.lisp
;;; 
;;; Created: 2004-04-18 by Zach Beane <xach@xach.com>
;;; 
;;; **PURPOSE**
;;; 
;;; 
;;; $Id: fetch.lisp,v 1.5 2004/07/20 21:16:45 xach Exp $

(in-package :newscluster)

(defun make-fetcher (channel)
  "Create a fetcher for the given channel"
  (cond ((string= (source channel) "python")
         (lambda ()
           (handler-case
               (newscluster-fetcher:fetch-channel
                (feed-url channel)
                (native-filename (path channel))
                (name channel))
             (error (e)
               (format *debug-io* "; fetch of ~A failed: ~A~%"
                       (feed-url channel) e)
               nil))))))

(defun native-filename (pathname)
  "Convert a pathname to a native filename string"
  (let ((directory (pathname-directory pathname))
        (name (pathname-name pathname))
        (type (pathname-type pathname)))
    (with-output-to-string (s nil :element-type 'base-char)
      (etypecase directory
        (string (write-string directory s))
        (list
         (when (eq (car directory) :absolute)
           (write-char #\/ s))
         (dolist (piece (cdr directory))
           (etypecase piece
             (string (write-string piece s) (write-char #\/ s))))))
      (etypecase name
        (null)
        (string (write-string name s)))
      (etypecase type
        (null)
        (string (write-char #\. s) (write-string type s))))))
