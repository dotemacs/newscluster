;;;
;;; fetcher.lisp - Main feed fetching logic
;;;

(in-package :newscluster-fetcher)

(defparameter *user-agent* 
  "newscluster-fetcher/1.0 (Common Lisp implementation)")

(defparameter *unicode-translations*
  '((#x2018 . "'")
    (#x00A0 . "&nbsp;")
    (#x2019 . "'")
    (#x201C . "\"")
    (#x201D . "\"")
    (#x2010 . "-")
    (#x2013 . "-")
    (#x2014 . "&mdash;")
    (#x2022 . "&middot;")
    (#x2026 . "...")))

(defun file-exists-p (path)
  "Check if file exists"
  (probe-file path))

(defun directory-empty-p (path)
  "Check if directory is empty"
  (null (directory (merge-pathnames "*.*" path))))

(defun load-required-tags (filename)
  "Load required tags from file"
  (when (probe-file filename)
    (with-open-file (stream filename)
      (loop for line = (read-line stream nil)
            while line
            collect (string-trim '(#\Space #\Tab #\Newline #\Return) line)))))

(defun load-failure-count (directory)
  "Load failure count from file"
  (let ((failure-file (merge-pathnames "failure-count" directory)))
    (if (probe-file failure-file)
        (with-open-file (stream failure-file)
          (handler-case
              (parse-integer (read-line stream))
            (error () 0)))
        0)))

(defun increment-failure-count (directory)
  "Increment and save failure count"
  (let* ((failure-file (merge-pathnames "failure-count" directory))
         (count (1+ (load-failure-count directory))))
    (with-open-file (stream failure-file :direction :output 
                           :if-exists :supersede)
      (format stream "~D~%" count))
    count))

(defun clear-failure-count (directory)
  "Clear failure count"
  (let ((failure-file (merge-pathnames "failure-count" directory)))
    (when (probe-file failure-file)
      (delete-file failure-file))))

(defun has-tag-p (required-tags item-tags)
  "Check if item has any required tag"
  (some (lambda (rtag)
          (member rtag item-tags :test #'string=))
        required-tags))

(defun compute-item-hash (id)
  "Compute MD5 hash of item ID"
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :md5 
                            (ironclad:ascii-string-to-byte-array id))))

(defun unix-to-universal-time (unix-time)
  "Convert Unix time to universal time"
  (+ unix-time 2208988800))

(defun universal-to-unix-time (universal-time)
  "Convert universal time to Unix time"
  (when universal-time
    (- universal-time 2208988800)))

(defun translate-unicode (string)
  "Translate Unicode characters to HTML entities"
  (with-output-to-string (out)
    (loop for char across string
          for code = (char-code char)
          for translation = (cdr (assoc code *unicode-translations*))
          do (cond
               (translation
                (write-string translation out))
               ((or (> code 255)
                    (= code #xA0)
                    (and (< code 20) (not (member code '(9 10 13)))))
                (format out "&#~D;" code))
               ((member char '(#\\ #\"))
                (write-char #\\ out)
                (write-char char out))
               (t
                (write-char char out))))))

(defun write-string-readably (stream string)
  "Write string in Lisp-readable format"
  (write-char #\" stream)
  (write-string (translate-unicode string) stream)
  (write-char #\" stream))

(defun write-sexp (stream operator &rest args)
  "Write S-expression to stream"
  (write-char #\( stream)
  (write-string (string-downcase (string operator)) stream)
  (loop for (key value) on args by #'cddr
        do (format stream " :~A " (string-downcase (string key)))
           (typecase value
             (string (write-string-readably stream value))
             (number (format stream "~D" value))
             (list 
              (write-char #\( stream)
              (loop for (item . rest) on value
                    do (format stream "#p\"~A\"" item)
                       (when rest (write-char #\Space stream)))
              (write-char #\) stream))
             (t (princ value stream))))
  (write-char #\) stream)
  (terpri stream))

(defun fetch-url (url &key modified-since user-agent)
  "Fetch URL content with conditional GET support"
  (handler-case
      (multiple-value-bind (body status-code headers)
          (drakma:http-request url
                              :user-agent (or user-agent *user-agent*)
                              :if-modified-since modified-since
                              :want-stream nil)
        (values (when body
                  (if (stringp body)
                      body
                      (flexi-streams:octets-to-string body :external-format :utf-8)))
                status-code
                headers))
    (error (e)
      (format *error-output* "~&; Error fetching ~A: ~A~%" url e)
      (values nil 999 nil))))

(defun fetch-local-file (path)
  "Fetch content from local file (for testing)"
  (handler-case
      (with-open-file (stream path :external-format :utf-8)
        (let ((content (make-string (file-length stream))))
          (read-sequence content stream)
          (values content 200 nil)))
    (error (e)
      (format *error-output* "~&; Error reading ~A: ~A~%" path e)
      (values nil 404 nil))))

(defun fetch-content (url &key modified-since)
  "Fetch content from URL or local file"
  (if (or (cl-ppcre:scan "^https?://" url)
          (cl-ppcre:scan "^ftp://" url))
      (fetch-url url :modified-since modified-since :user-agent *user-agent*)
      (fetch-local-file url)))

(defun write-item-file (directory item feed-url new-channel-p)
  "Write item to file"
  (let* ((item-id (feed-item-id item))
         (hash (compute-item-hash item-id))
         (filename (format nil "~A.sexp" hash))
         (filepath (merge-pathnames (format nil "items/~A" filename) directory))
         (tmppath (merge-pathnames (format nil "items/~A.tmp" filename) directory))
         (unix-time (or (universal-to-unix-time (feed-item-date item))
                       (if new-channel-p
                           0
                           (if (probe-file filepath)
                               (universal-to-unix-time 
                                (file-write-date filepath))
                               (universal-to-unix-time 
                                (get-universal-time)))))))
    
    (with-open-file (stream tmppath :direction :output 
                           :if-exists :supersede
                           :external-format :utf-8)
      (write-sexp stream 'item
                  'id item-id
                  'title (feed-item-title item)
                  'author-name (or (feed-item-author-name item) "")
                  'description (feed-item-description item)
                  'date (unix-to-universal-time unix-time)
                  'link (feed-item-link item)))
    
    (rename-file tmppath filepath)
    
    ;; Set file modification time
    (when unix-time
      (sb-posix:utime (namestring filepath) unix-time unix-time))
    
    filename))

(defun get-existing-files (directory)
  "Get hash table of existing item files"
  (let ((table (make-hash-table :test 'equal)))
    (dolist (file (directory (merge-pathnames "items/*.sexp" directory)))
      (setf (gethash (namestring file) table) t))
    table))

(defun fetch-channel (url directory name)
  "Main entry point - fetch channel and write files"
  (let* ((directory (pathname directory))
         (channel-file (merge-pathnames "channel-info.sexp" directory))
         (channel-tmp (merge-pathnames "channel-info.sexp.tmp" directory))
         (items-dir (merge-pathnames "items/" directory))
         (required-tags-file (merge-pathnames "required-tags" directory))
         (modified-since nil))
    
    ;; Ensure directories exist
    (ensure-directories-exist items-dir)
    
    ;; Get modification time for conditional GET
    (when (and (probe-file channel-file)
               (not (directory-empty-p items-dir)))
      (setf modified-since (file-write-date channel-file)))
    
    ;; Fetch feed
    (multiple-value-bind (content status-code headers)
        (fetch-content url :modified-since modified-since)
      
      (declare (ignore headers))
      
      ;; Handle non-200 responses
      (when (and modified-since (not (member status-code '(200 304))))
        (let ((failures (increment-failure-count directory)))
          (format t "~&>> ~A status ~D (failure #~D)~%" url status-code failures)))
      
      (unless (= status-code 200)
        (return-from fetch-channel t))
      
      (clear-failure-count directory)
      
      ;; Parse feed
      (let ((feed (parse-feed content)))
        (unless feed
          (format *error-output* "~&; Failed to parse feed from ~A~%" url)
          (return-from fetch-channel nil))
        
        ;; Load required tags if any
        (let ((required-tags (load-required-tags required-tags-file))
              (new-channel-p (directory-empty-p items-dir))
              (old-files (get-existing-files directory))
              (feed-files '()))
          
          ;; Process items
          (dolist (item (feed-info-items feed))
            ;; Check tag filter
            (when (or (null required-tags)
                     (has-tag-p required-tags (feed-item-categories item)))
              (let ((filename (write-item-file directory item url new-channel-p)))
                (push filename feed-files)
                (remhash (namestring (merge-pathnames 
                                     (format nil "items/~A" filename) 
                                     directory))
                        old-files))))
          
          ;; Write channel info
          (with-open-file (stream channel-tmp :direction :output
                                 :if-exists :supersede
                                 :external-format :utf-8)
            (write-sexp stream 'channel
                        'name name
                        'title (feed-info-title feed)
                        'description (feed-info-description feed)
                        'url (feed-info-link feed)
                        'feed-url url
                        'source "python"  
                        'current-item-files (nreverse feed-files)
                        'last-fetch-time (unix-to-universal-time 
                                        (universal-to-unix-time 
                                         (get-universal-time)))))
          
          (rename-file channel-tmp channel-file)
          t)))))