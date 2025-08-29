;;;
;;; fetcher.lisp - Feed fetching
;;;

(in-package #:newscluster-fetcher)

(defparameter *user-agent*
  "newscluster-fetcher/1.0 (Common Lisp)")

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

(defun unix-to-universal-time (unix-time)
  "Convert Unix time to Universal time"
  (+ unix-time 2208988800))

(defun universal-to-unix-time (universal-time)
  "Convert Universal time to Unix time"
  (- universal-time 2208988800))

(defun md5-hash (string)
  "Generate MD5 hash of a string"
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :md5
                            (flexi-streams:string-to-octets string :external-format :utf-8))))

(defun clean-string (string)
  "Clean and translate Unicode characters in string"
  (if (null string)
      ""
      (with-output-to-string (out)
        (loop for char across string
              for code = (char-code char)
              for translation = (assoc code *unicode-translations*)
              do (if translation
                     (write-string (cdr translation) out)
                     (write-char char out))))))

(defun timestamp-to-unix (timestamp)
  "Convert a local-time timestamp to Unix time, or return 0 if nil"
  (if timestamp
      (universal-to-unix-time
       (local-time:timestamp-to-universal timestamp))
      0))

(defun write-sexp (stream label &rest args)
  "Write an S-expression to stream"
  (write-char #\( stream)
  (princ label stream)
  (loop for (key value) on args by #'cddr
        do (format stream " :~A " (string-downcase (string key)))
           (if (stringp value)
               (prin1 (clean-string value) stream)
               (prin1 value stream)))
  (write-char #\) stream)
  (terpri stream))

(defun ensure-directories (directory)
  "Ensure directory and items subdirectory exist"
  (ensure-directories-exist directory)
  (ensure-directories-exist (merge-pathnames "items/" directory)))

(defun load-required-tags (directory)
  "Load required tags from file"
  (let ((tags-file (merge-pathnames "required-tags" directory)))
    (when (probe-file tags-file)
      (with-open-file (stream tags-file)
        (loop for line = (read-line stream nil)
              while line
              for tag = (string-trim '(#\Space #\Tab #\Newline #\Return) line)
              when (> (length tag) 0)
              collect (string-downcase tag))))))

(defun item-has-required-tag-p (item required-tags)
  "Check if item has at least one required tag"
  (if (null required-tags)
      t  ; No filter, accept all
      (let ((item-categories (mapcar #'string-downcase
                                     (feeder:categories item))))
        ;; Check if any required tag matches any item category
        (some (lambda (required-tag)
                (member required-tag item-categories :test #'string=))
              required-tags))))

(defun get-item-id (entry)
  "Get a unique ID for an entry"
  (let ((id (feeder:id entry)))
    (cond
      ;; If we have an ID and it's a string, use it
      ((and id (stringp id)) id)
      ;; If we have an ID that's a link object, get its URL
      ((and id (typep id 'feeder:link)) (feeder:url id))
      ;; Otherwise try the link
      (t (let ((link-obj (feeder:link entry)))
           (if link-obj
               (feeder:url link-obj)
               ;; Generate a unique ID if neither exists
               (format nil "~A-~A"
                       (feeder:title entry)
                       (get-universal-time))))))))

(defun get-item-author (entry)
  "Get the author name from an entry"
  (let ((authors (feeder:authors entry)))
    (if (and authors (> (length authors) 0))
        (let ((first-author (first authors)))
          (typecase first-author
            (feeder:person (feeder:name first-author))
            (string first-author)
            (t "")))
        "")))

(defun fetch-feed-from-url (url)
  "Fetch and parse feed from URL"
  (handler-case
      (let* ((content (drakma:http-request url
                                           :user-agent *user-agent*
                                           :force-binary t))
             (text (flexi-streams:octets-to-string content :external-format :utf-8)))
        (first (feeder:parse-feed text t)))
    (error (e)
      (format *error-output* "~&Error fetching ~A: ~A~%" url e)
      nil)))

(defun fetch-feed-from-file (file-path)
  "Parse feed from local file"
  (handler-case
      (let ((content (alexandria:read-file-into-string file-path)))
        (first (feeder:parse-feed content t)))
    (error (e)
      (format *error-output* "~&Error parsing ~A: ~A~%" file-path e)
      nil)))

(defun fetch-channel (url directory name)
  "Fetch a feed and save it in newscluster format"
  (let* ((directory (pathname directory))
         (channel-file (merge-pathnames "channel-info.sexp" directory))
         (channel-tmp (merge-pathnames "channel-info.sexp.tmp" directory))
         (required-tags (load-required-tags directory))
         (feed-files '()))

    ;; Ensure directories exist
    (ensure-directories directory)

    ;; Parse the feed
    (let* ((url-string (if (pathnamep url) (namestring url) url))
           (feed (if (or (probe-file url-string)
                         (not (find #\: url-string :test #'char=)))
                     (fetch-feed-from-file url-string)
                     (fetch-feed-from-url url-string))))

      (unless feed
        (format *error-output* "~&Failed to parse feed from ~A~%" url)
        (return-from fetch-channel nil))

      ;; Get feed metadata
      (let* ((feed-title (clean-string (or (feeder:title feed) "")))
             (feed-summary (feeder:summary feed))
             (feed-description (clean-string
                                (if (stringp feed-summary)
                                    feed-summary
                                    (or (and feed-summary
                                             (plump:text feed-summary))
                                        ""))))
             (feed-link-obj (feeder:link feed))
             (feed-link (if feed-link-obj
                            (feeder:url feed-link-obj)
                            "")))

        ;; Process entries
        (dolist (entry (feeder:content feed))
          ;; Check if entry passes tag filter
          (when (item-has-required-tag-p entry required-tags)
            (let* ((item-id (get-item-id entry))
                   (item-title (clean-string (or (feeder:title entry) "")))
                   (item-content (feeder:content entry))
                   (item-summary (feeder:summary entry))
                   (item-description (clean-string
                                      (cond
                                        ((and item-content (stringp item-content)) item-content)
                                        ((and item-summary (stringp item-summary)) item-summary)
                                        (item-content (plump:text item-content))
                                        (item-summary (plump:text item-summary))
                                        (t ""))))
                   (item-link-obj (feeder:link entry))
                   (item-link (if item-link-obj
                                  (feeder:url item-link-obj)
                                  ""))
                   (item-author (clean-string (get-item-author entry)))
                   (item-published (feeder:published-on entry))
                   (item-updated (feeder:updated-on entry))
                   (item-date (timestamp-to-unix (or item-published item-updated)))
                   (hash (md5-hash item-id))
                   (item-file (format nil "~A.sexp" hash))
                   (item-path (merge-pathnames (format nil "items/~A" item-file) directory))
                   (item-tmp (merge-pathnames (format nil "items/~A.tmp" item-file) directory)))

              ;; Debug: show categories for items
              (when (and required-tags (feeder:categories entry))
                (format *error-output* "~&Item '~A' has categories: ~S~%"
                        item-title (feeder:categories entry)))

              ;; Write item file
              (with-open-file (stream item-tmp :direction :output
                                               :if-exists :supersede
                                               :external-format :utf-8)
                (write-sexp stream 'item
                            'id item-id
                            'title item-title
                            'author-name item-author
                            'description item-description
                            'date (unix-to-universal-time item-date)
                            'link item-link))

              ;; Rename temp file to final
              (rename-file item-tmp item-path)

              ;; Set file modification time if we have a date
              (when (> item-date 0)
                (handler-case
                    (sb-posix:utime (namestring item-path) item-date item-date)
                  (error () nil)))

              ;; Add to file list
              (push (pathname item-file) feed-files))))

        ;; Write channel info
        (with-open-file (stream channel-tmp :direction :output
                                            :if-exists :supersede
                                            :external-format :utf-8)
          (write-sexp stream 'channel
                      'name name
                      'title feed-title
                      'description feed-description
                      'url feed-link
                      'feed-url url
                      'current-item-files (nreverse feed-files)
                      'last-fetch-time (unix-to-universal-time
                                        (universal-to-unix-time
                                         (get-universal-time)))))

        ;; Rename temp file to final
        (rename-file channel-tmp channel-file)
        t))))
