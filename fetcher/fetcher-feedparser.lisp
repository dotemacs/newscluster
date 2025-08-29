;;;
;;; fetcher-feedparser.lisp - Alternative fetcher using cl-feedparser
;;;

(in-package #:newscluster-fetcher)

(defun fetch-feed-feedparser (url)
  "Fetch and parse feed using cl-feedparser instead of feeder"
  (handler-case
      (multiple-value-bind (content status headers uri)
          (drakma:http-request url
                               :user-agent *user-agent*
                               :force-binary t
                               :connection-timeout 10
                               :redirect t
                               :preserve-uri t)
        ;; Only process content if we got a successful response
        (cond
          ((= status 404)
           (format *error-output* "~&Feed not found (404): ~A~%" url)
           nil)
          ((>= status 400)
           (format *error-output* "~&HTTP error ~A for ~A~%" status url)
           nil)
          ((= status 200)
           ;; Success - process the content
           (let ((text (flexi-streams:octets-to-string content :external-format :utf-8)))
             ;; Check if we got HTML instead of a feed
             (when (html-content-p text)
               (format *error-output* "~&URL ~A returned HTML instead of feed~%" url)
               (return-from fetch-feed-feedparser nil))
             ;; Fix common XML issues
             (setf text (fix-malformed-xml text))
             ;; Parse with feedparser
             (feedparser:parse-feed text)))
          (t
           ;; Unexpected status code
           (format *error-output* "~&Unexpected status ~A for ~A~%" status url)
           nil)))
    (error (e)
      (format *error-output* "~&Error fetching ~A: ~A~%" url e)
      nil)))

(defun fetch-channel-feedparser (url directory name)
  "Fetch a feed using cl-feedparser and save in newscluster format"
  (let* ((directory (pathname directory))
         (channel-file (merge-pathnames "channel-info.sexp" directory))
         (channel-tmp (merge-pathnames "channel-info.sexp.tmp" directory))
         (required-tags (load-required-tags directory))
         (feed-files '()))

    (ensure-directories directory)

    (let* ((url-string (if (pathnamep url) (namestring url) url))
           ;; Check if it's a URL (has ://) or a local file
           (url-p (search "://" url-string))
           (feed (if url-p
                     ;; Remote URL
                     (fetch-feed-feedparser url-string)
                     ;; Local file
                     (handler-case
                         (let ((content (alexandria:read-file-into-string url-string)))
                           (setf content (fix-malformed-xml content))
                           (feedparser:parse-feed content))
                       (error (e)
                         (format *error-output* "~&Error parsing ~A: ~A~%" url-string e)
                         nil)))))

      (unless feed
        (format *error-output* "~&Failed to parse feed from ~A~%" url)
        (return-from fetch-channel-feedparser nil))

      ;; Get feed metadata from hash table
      (let* ((feed-title (clean-string (or (gethash :title feed) "")))
             (feed-description (clean-string (or (gethash :description feed)
                                                 (gethash :subtitle feed) "")))
             (feed-link (or (gethash :link feed) ""))
             ;; cl-feedparser uses :entries for Atom feeds, :items for RSS
             (items (or (gethash :entries feed) (gethash :items feed))))

        ;; Process items
        (when items
          (loop for item in items
                do (let* ((item-id (or (gethash :id item)
                                       (gethash :guid item)
                                       (gethash :link item)
                                       (format nil "~A-~A"
                                               (gethash :title item)
                                               (get-universal-time))))
                          (item-title (clean-string (or (gethash :title item) "")))
                          ;; Handle content which may be a list
                          (content-val (gethash :content item))
                          (item-description (clean-string
                                             (cond
                                               ((and content-val (listp content-val))
                                                (or (gethash :value (first content-val)) ""))
                                               ((stringp content-val) content-val)
                                               (t (or (gethash :description item)
                                                      (gethash :summary item) "")))))
                          (item-link (or (gethash :link item) ""))
                          (item-author (clean-string (or (gethash :author item) "")))
                          ;; cl-feedparser provides parsed dates as unix timestamps
                          (item-date (or (gethash :published-parsed item)
                                         (gethash :updated-parsed item)
                                         (get-universal-time)))
                          (hash (md5-hash item-id))
                          (item-file (format nil "~A.sexp" hash))
                          (item-path (merge-pathnames (format nil "items/~A" item-file) directory))
                          (item-tmp (merge-pathnames (format nil "items/~A.tmp" item-file) directory)))

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

;; Export for use
(export '(fetch-channel-feedparser fetch-feed-feedparser))
