;;;
;;; xml-parser.lisp - XML/RSS/Atom feed parsing
;;;

(in-package :newscluster-fetcher)

(defun parse-xml-string (xml-string)
  "Parse XML string into a DOM structure"
  (cxml:parse xml-string (cxml-dom:make-dom-builder)))

(defun get-elements-by-tag-name (node tag-name)
  "Get all child elements with given tag name"
  (when node
    (let ((children (dom:get-elements-by-tag-name node tag-name)))
      (loop for i from 0 below (dom:length children)
            collect (dom:item children i)))))

(defun get-element-text (element)
  "Get text content of an element"
  (when element
    (let ((text-nodes (dom:child-nodes element)))
      (when (and text-nodes (> (dom:length text-nodes) 0))
        (let ((texts '()))
          (loop for i from 0 below (dom:length text-nodes)
                for node = (dom:item text-nodes i)
                when (eq (dom:node-type node) :text)
                  do (push (dom:node-value node) texts))
          (when texts
            (apply #'concatenate 'string (nreverse texts))))))))

(defun get-first-element-by-tag (parent tag-name)
  "Get first child element with tag name"
  (let ((elements (get-elements-by-tag-name parent tag-name)))
    (first elements)))

(defun get-first-element-text (parent tag-name)
  "Get text of first element with tag name"
  (get-element-text (get-first-element-by-tag parent tag-name)))

(defun parse-rfc822-date (date-string)
  "Parse RFC822 date to universal time"
  (handler-case
      (let* ((months '(("Jan" . 1) ("Feb" . 2) ("Mar" . 3) ("Apr" . 4)
                       ("May" . 5) ("Jun" . 6) ("Jul" . 7) ("Aug" . 8)
                       ("Sep" . 9) ("Oct" . 10) ("Nov" . 11) ("Dec" . 12)))
             (parts (cl-ppcre:split "\\s+" (string-trim '(#\Space #\Tab) date-string)))
             (day (parse-integer (second parts)))
             (month-name (third parts))
             (month (cdr (assoc month-name months :test #'string=)))
             (year (parse-integer (fourth parts)))
             (time-parts (cl-ppcre:split ":" (fifth parts)))
             (hour (parse-integer (first time-parts)))
             (minute (parse-integer (second time-parts)))
             (second (parse-integer (third time-parts))))
        (encode-universal-time second minute hour day month year 0))
    (error () nil)))

(defun parse-iso8601-date (date-string)
  "Parse ISO8601 date to universal time"
  (handler-case
      (let* ((clean-date (cl-ppcre:regex-replace "T" date-string " "))
             (clean-date (cl-ppcre:regex-replace "Z$" clean-date ""))
             (parts (cl-ppcre:split "[- :]" clean-date))
             (year (parse-integer (first parts)))
             (month (parse-integer (second parts)))
             (day (parse-integer (third parts)))
             (hour (if (fourth parts) (parse-integer (fourth parts)) 0))
             (minute (if (fifth parts) (parse-integer (fifth parts)) 0))
             (second (if (sixth parts) (parse-integer (sixth parts)) 0)))
        (encode-universal-time second minute hour day month year 0))
    (error () nil)))

(defun parse-date (date-string)
  "Parse various date formats"
  (when date-string
    (or (parse-rfc822-date date-string)
        (parse-iso8601-date date-string))))

(defstruct feed-info
  title
  description
  link
  items)

(defstruct feed-item
  id
  title
  link
  description
  author-name
  date
  categories)

(defun parse-rss-item (item-element)
  "Parse an RSS item element"
  (make-feed-item
   :id (or (get-first-element-text item-element "guid")
           (get-first-element-text item-element "link")
           "")
   :title (or (get-first-element-text item-element "title") "")
   :link (or (get-first-element-text item-element "link") "")
   :description (or (get-first-element-text item-element "description")
                    (get-first-element-text item-element "summary")
                    "")
   :author-name (let ((author (get-first-element-text item-element "author")))
                  (if (and author (cl-ppcre:scan "\\(.*\\)" author))
                      (cl-ppcre:regex-replace "^.*\\((.*)\\).*$" author "\\1")
                      (or author "")))
   :date (parse-date (or (get-first-element-text item-element "pubDate")
                         (get-first-element-text item-element "dc:date")))
   :categories (mapcar #'get-element-text
                       (get-elements-by-tag-name item-element "category"))))

(defun parse-atom-entry (entry-element)
  "Parse an Atom entry element"
  (make-feed-item
   :id (or (get-first-element-text entry-element "id")
           (get-first-element-text entry-element "link")
           "")
   :title (or (get-first-element-text entry-element "title") "")
   :link (let ((link-elem (get-first-element-by-tag entry-element "link")))
           (when link-elem
             (or (dom:get-attribute link-elem "href") "")))
   :description (or (get-first-element-text entry-element "content")
                    (get-first-element-text entry-element "summary")
                    "")
   :author-name (let ((author-elem (get-first-element-by-tag entry-element "author")))
                  (when author-elem
                    (get-first-element-text author-elem "name")))
   :date (parse-date (or (get-first-element-text entry-element "updated")
                         (get-first-element-text entry-element "published")))
   :categories (mapcar (lambda (elem)
                         (dom:get-attribute elem "term"))
                       (get-elements-by-tag-name entry-element "category"))))

(defun parse-rss-feed (document)
  "Parse RSS feed document"
  (let* ((channel (get-first-element-by-tag document "channel"))
         (items (when channel
                  (mapcar #'parse-rss-item
                          (get-elements-by-tag-name channel "item")))))
    (when channel
      (make-feed-info
       :title (or (get-first-element-text channel "title") "")
       :description (or (get-first-element-text channel "description") "")
       :link (or (get-first-element-text channel "link") "")
       :items items))))

(defun parse-atom-feed (document)
  "Parse Atom feed document"
  (let* ((feed (dom:document-element document))
         (entries (mapcar #'parse-atom-entry
                          (get-elements-by-tag-name feed "entry"))))
    (make-feed-info
     :title (or (get-first-element-text feed "title") "")
     :description (or (get-first-element-text feed "subtitle") "")
     :link (let ((link-elem (get-first-element-by-tag feed "link")))
             (if link-elem
                 (or (dom:get-attribute link-elem "href") "")
                 ""))
     :items entries)))

(defun parse-feed (xml-string)
  "Parse RSS or Atom feed from XML string"
  (handler-case
      (let ((document (parse-xml-string xml-string)))
        (cond
          ((get-first-element-by-tag document "channel")
           (parse-rss-feed document))
          ((string= (dom:tag-name (dom:document-element document)) "feed")
           (parse-atom-feed document))
          (t nil)))
    (error (e)
      (format *error-output* "~&; Error parsing feed: ~A~%" e)
      nil)))
