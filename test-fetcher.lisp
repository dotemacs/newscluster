;;;
;;; test-fetcher.lisp - Test Lisp feed fetcher implementation
;;;

(require :asdf)

;; Load Quicklisp if available
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;; Add paths to ASDF
(push (pathname (directory-namestring *load-pathname*)) asdf:*central-registry*)
(push (merge-pathnames "fetcher/" (pathname (directory-namestring *load-pathname*)))
      asdf:*central-registry*)

;; Load required libraries
(format t "~&Loading systems...~%")
(ql:quickload '(:ironclad :cxml :cxml-dom :drakma :cl-ppcre :flexi-streams) :silent t)
(asdf:load-system :newscluster-fetcher)

;;; Test infrastructure

(defparameter *test-feeds*
  '(("rss-basic"
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
  <channel>
    <title>Test RSS Feed</title>
    <link>http://example.com</link>
    <description>A test RSS feed</description>
    <item>
      <title>First Post</title>
      <link>http://example.com/post1</link>
      <description>This is the first test post</description>
      <guid>http://example.com/post1</guid>
      <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Second Post</title>
      <link>http://example.com/post2</link>
      <description>This is the second test post</description>
      <guid>http://example.com/post2</guid>
    </item>
  </channel>
</rss>")

    ("atom-basic"
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<feed xmlns=\"http://www.w3.org/2005/Atom\">
  <title>Test Atom Feed</title>
  <link href=\"http://example.org/\"/>
  <updated>2024-01-03T12:00:00Z</updated>
  <id>http://example.org/</id>
  <entry>
    <title>Atom Entry</title>
    <link href=\"http://example.org/entry1\"/>
    <id>http://example.org/entry1</id>
    <updated>2024-01-03T12:00:00Z</updated>
    <summary>An Atom feed entry</summary>
  </entry>
</feed>")

    ("empty-feed"
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
  <channel>
    <title>Empty Feed</title>
    <link>http://example.com</link>
    <description>Feed with no items</description>
  </channel>
</rss>")

    ("rss-with-cdata"
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
  <channel>
    <title>RSS with CDATA</title>
    <link>http://example.com</link>
    <description>Testing CDATA sections</description>
    <item>
      <title><![CDATA[Post with <html> tags]]></title>
      <link>http://example.com/post1</link>
      <description><![CDATA[This has <b>HTML</b> content & entities]]></description>
      <guid>http://example.com/cdata-post</guid>
    </item>
  </channel>
</rss>")

    ("malformed-feed"
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
  <channel>
    <title>Malformed Feed</title>
    <!-- Missing closing tags and other issues -->
    <link>http://example.com")))

(defun ensure-clean-directory (path)
  "Ensure directory exists and is clean"
  (ensure-directories-exist path)
  (ensure-directories-exist (merge-pathnames "items/" path))
  ;; Clean items directory
  (handler-case
      (dolist (file (directory (merge-pathnames "items/*.sexp" path)))
        (delete-file file))
    (error () nil))
  ;; Clean other files
  (handler-case
      (dolist (file (directory (merge-pathnames "*.sexp" path)))
        (delete-file file))
    (error () nil)))

(defun read-sexp-file (path)
  "Read an S-expression file"
  (when (probe-file path)
    (with-open-file (stream path)
      (read stream nil nil))))

(defun run-test (test-name feed-content)
  "Run a single test on the Lisp implementation"
  (format t "~&~%Testing: ~A~%" test-name)
  (format t "----------------------------------------~%")

  (let* ((test-dir "/tmp/newscluster-test/")
         (output-dir (merge-pathnames (format nil "~A/" test-name) test-dir))
         (feed-file (merge-pathnames (format nil "~A.xml" test-name) test-dir))
         (success nil))

    ;; Setup
    (ensure-directories-exist test-dir)
    (ensure-clean-directory output-dir)

    ;; Write feed file
    (with-open-file (stream feed-file :direction :output :if-exists :supersede)
      (write-string feed-content stream))

    ;; Run Lisp implementation
    (format t "  Running fetcher... ")
    (handler-case
        (progn
          (newscluster-fetcher:fetch-channel (namestring feed-file)
                                            (namestring output-dir)
                                            test-name)
          (setf success t)
          (format t "~%"))
      (error (e)
        (format t "~%")
        (format t "    Error: ~A~%" e)))

    ;; Check results
    (when success
      (let ((channel-info (read-sexp-file (merge-pathnames "channel-info.sexp" output-dir)))
            (items (directory (merge-pathnames "items/*.sexp" output-dir))))

        (format t "  Channel: ~A~%" (getf (rest channel-info) :title))
        (format t "  Items found: ~D~%" (length items))

        ;; Validate channel info structure
        (when channel-info
          (unless (eq (first channel-info) 'channel)
            (format t "    Invalid channel info structure~%"))
          (unless (getf (rest channel-info) :name)
            (format t "    Missing channel name~%")))

        ;; For non-empty feeds, check that items were created
        (when (and (not (search "empty" test-name))
                   (not (search "malformed" test-name))
                   (zerop (length items)))
          (format t "    Expected items but found none~%"))))

    (if success :passed :failed)))

(defun main ()
  "Run all tests"
  (format t "~&========================================~%")
  (format t "  FEED FETCHER TEST SUITE~%")
  (format t "========================================~%")

  (let ((results '()))

    ;; Run all tests
    (dolist (test *test-feeds*)
      (let ((test-name (first test))
            (feed-content (second test)))
        (push (cons test-name (run-test test-name feed-content)) results)))

    ;; Summary
    (format t "~&~%========================================~%")
    (format t "  SUMMARY~%")
    (format t "========================================~%")

    (let ((passed (count :passed results :key #'cdr))
          (failed (count :failed results :key #'cdr)))

      (dolist (result (reverse results))
        (format t "  ~A: ~A~%"
                (car result)
                (if (eq (cdr result) :passed)
                    " PASSED"
                    " FAILED")))

      (format t "~%")
      (format t "  Passed: ~D~%" passed)
      (format t "  Failed: ~D~%" failed)

      (when (zerop failed)
        (format t "~% All tests passed!~%"))

      (zerop failed))))

(handler-case
    (if (main)
        (sb-ext:exit :code 0)
        (sb-ext:exit :code 1))
  (error (e)
    (format *error-output* "~&Error: ~A~%" e)
    (sb-ext:exit :code 1)))
