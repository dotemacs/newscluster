;;;
;;; tests.lisp - Test definitions for newscluster
;;;
;;; This file contains all test definitions.
;;; Load this file to define tests, then call the test functions.
;;;

(defpackage :newscluster-tests
  (:use :cl)
  (:export #:run-all-tests
           #:run-fetcher-tests
           #:run-core-tests
           #:run-single-fetcher-test
           #:test-planet-creation
           #:test-channel-creation
           #:test-item-creation
           #:test-integration
           #:*test-feeds*))

(in-package :newscluster-tests)

;;;
;;; Test Data
;;;

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
    <link>http://example.com")

    ("rss-with-categories"
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
  <channel>
    <title>Feed with Categories</title>
    <link>http://example.com</link>
    <description>Testing category filtering</description>
    <item>
      <title>Lisp Programming Post</title>
      <link>http://example.com/lisp-post</link>
      <description>A post about Lisp</description>
      <category>lisp</category>
      <category>programming</category>
      <guid>http://example.com/lisp-post</guid>
    </item>
    <item>
      <title>Python Post</title>
      <link>http://example.com/python-post</link>
      <description>A post about Python</description>
      <category>python</category>
      <category>programming</category>
      <guid>http://example.com/python-post</guid>
    </item>
  </channel>
</rss>"))
  "Test feed definitions")

;;;
;;; Utility Functions
;;;

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

;;;
;;; Fetcher Tests
;;;

(defun run-single-fetcher-test (test-name &optional feed-content)
  "Run a single fetcher test. If feed-content not provided, uses predefined test."
  (let ((test-data (or feed-content
                       (second (assoc test-name *test-feeds* :test #'string=)))))
    (unless test-data
      (error "No test found with name ~A" test-name))

    (format t "~&  Testing: ~A~%" test-name)

    (let* ((test-dir "/tmp/newscluster-test/")
           (output-dir (merge-pathnames (format nil "~A/" test-name) test-dir))
           (feed-file (merge-pathnames (format nil "~A.xml" test-name) test-dir))
           (success nil))

      ;; Setup
      (ensure-directories-exist test-dir)
      (ensure-clean-directory output-dir)

      ;; Write feed file
      (with-open-file (stream feed-file :direction :output :if-exists :supersede)
        (write-string test-data stream))

      ;; Run fetcher
      (handler-case
          (progn
            (newscluster-fetcher:fetch-channel (namestring feed-file)
                                               (namestring output-dir)
                                               test-name)
            (setf success t))
        (error (e)
          (format t "      Error: ~A~%" e)))

      ;; Check results
      (when success
        (let ((channel-info (read-sexp-file (merge-pathnames "channel-info.sexp" output-dir)))
              (items (directory (merge-pathnames "items/*.sexp" output-dir))))

          ;; Validate channel info structure
          (when channel-info
            (let ((channel-symbol (first channel-info)))
              (unless (or (eq channel-symbol 'newscluster::channel)
                          (eq channel-symbol 'channel)
                          (and (symbolp channel-symbol)
                               (string= (symbol-name channel-symbol) "CHANNEL")))
                (format t "      Invalid channel info structure: ~A~%" channel-symbol)
                (setf success nil)))
            (unless (getf (rest channel-info) :name)
              (format t "      Missing channel name~%")
              (setf success nil)))

          ;; For non-empty feeds, check that items were created
          (when (and (not (search "empty" test-name))
                     (not (search "malformed" test-name))
                     (zerop (length items)))
            (format t "      Expected items but found none~%")
            (setf success nil))))

      (if success
          (progn (format t "       PASSED~%") :passed)
          (progn (format t "       FAILED~%") :failed)))))

(defun run-fetcher-tests ()
  "Run all fetcher tests"
  (format t "~%FETCHER TESTS:~%")
  (format t "----------------------------------------~%")
  (let ((results '()))
    (dolist (test *test-feeds*)
      (let ((test-name (first test)))
        (push (cons (format nil "fetcher/~A" test-name)
                    (run-single-fetcher-test test-name))
              results)))
    (reverse results)))

;;;
;;; Core Tests
;;;

(defun test-planet-creation ()
  "Test planet creation and basic operations"
  (format t "~&  Testing: Planet creation~%")
  (handler-case
      (let* ((test-dir #p"/tmp/newscluster-core-test/")
             (planet (make-instance 'newscluster::planet
                                    :name "Test Planet"
                                    :template-path #p"templates/"
                                    :html-path (merge-pathnames "html/" test-dir)
                                    :site-url "http://test.example.com/")))
        (setf (newscluster::path planet) test-dir)
        (ensure-directories-exist test-dir)

        ;; Test saving planet
        (newscluster::save-object planet (newscluster::info-file planet))

        ;; Test loading planet
        (let ((loaded (newscluster::load-object (newscluster::info-file planet))))
          (if (and loaded
                   (string= (newscluster::name loaded) "Test Planet")
                   (string= (newscluster::site-url loaded) "http://test.example.com/"))
              (progn (format t "       PASSED~%") :passed)
              (progn (format t "       FAILED: Planet save/load mismatch~%") :failed))))
    (error (e)
      (format t "       FAILED: ~A~%" e)
      :failed)))

(defun test-channel-creation ()
  "Test channel creation and operations"
  (format t "~&  Testing: Channel creation~%")
  (handler-case
      (let* ((test-dir #p"/tmp/newscluster-core-test/test-channel/")
             (channel (make-instance 'newscluster::channel
                                     :name "test-channel"
                                     :title "Test Channel"
                                     :description "A test channel"
                                     :feed-url "http://example.com/feed.xml"
                                     :url "http://example.com")))
        (setf (newscluster::path channel) test-dir)
        (ensure-directories-exist test-dir)

        ;; Test saving channel
        (newscluster::save-object channel (newscluster::info-file channel))

        ;; Test loading channel
        (let ((loaded (newscluster::load-object (newscluster::info-file channel))))
          (if (and loaded
                   (string= (newscluster::name loaded) "test-channel")
                   (string= (newscluster::feed-url loaded) "http://example.com/feed.xml"))
              (progn (format t "       PASSED~%") :passed)
              (progn (format t "       FAILED: Channel save/load mismatch~%") :failed))))
    (error (e)
      (format t "       FAILED: ~A~%" e)
      :failed)))

(defun test-item-creation ()
  "Test item creation and operations"
  (format t "~&  Testing: Item creation~%")
  (handler-case
      (let* ((test-dir #p"/tmp/newscluster-core-test/")
             (item (make-instance 'newscluster::item
                                  :id "test-item-123"
                                  :title "Test Item"
                                  :author-name "Test Author"
                                  :description "This is a test item"
                                  :date (get-universal-time)
                                  :link "http://example.com/item")))
        (ensure-directories-exist test-dir)

        ;; Test saving item
        (let ((item-file (merge-pathnames "test-item.sexp" test-dir)))
          (newscluster::save-object item item-file)

          ;; Test loading item
          (let ((loaded (newscluster::load-object item-file)))
            (if (and loaded
                     (string= (newscluster::id loaded) "test-item-123")
                     (string= (newscluster::title loaded) "Test Item"))
                (progn (format t "       PASSED~%") :passed)
                (progn (format t "       FAILED: Item save/load mismatch~%") :failed)))))
    (error (e)
      (format t "       FAILED: ~A~%" e)
      :failed)))

(defun test-integration ()
  "Test integration between planet, channels, and items"
  (format t "~&  Testing: Integration~%")
  (handler-case
      (let* ((test-dir #p"/tmp/newscluster-integration-test/")
             (planet (make-instance 'newscluster::planet
                                    :name "Integration Test"
                                    :html-path (merge-pathnames "html/" test-dir)
                                    :site-url "http://test.example.com/"))
             (channel (make-instance 'newscluster::channel
                                     :name "test-channel"
                                     :title "Test Channel"
                                     :description "Test"
                                     :feed-url "http://example.com/feed.xml"
                                     :url "http://example.com")))
        (setf (newscluster::path planet) test-dir)
        (setf (newscluster::path channel) (merge-pathnames "test-channel/" test-dir))

        ;; Add channel to planet
        (newscluster::add-channel planet channel)

        (if (and (= 1 (length (newscluster::channels planet)))
                 (eq channel (aref (newscluster::channels planet) 0)))
            (progn (format t "       PASSED~%") :passed)
            (progn (format t "       FAILED: Channel not added to planet~%") :failed)))
    (error (e)
      (format t "       FAILED: ~A~%" e)
      :failed)))

(defun run-core-tests ()
  "Run all core tests"
  (format t "~%CORE TESTS:~%")
  (format t "----------------------------------------~%")
  (list
   (cons "core/planet" (test-planet-creation))
   (cons "core/channel" (test-channel-creation))
   (cons "core/item" (test-item-creation))
   (cons "core/integration" (test-integration))))

;;;
;;; Main Test Runner
;;;

(defun run-all-tests ()
  "Run all test suites and return (values passed failed)"
  (format t "~&========================================~%")
  (format t "  NEWSCLUSTER TEST SUITE~%")
  (format t "========================================~%")

  (let ((all-results '()))

    ;; Run fetcher tests
    (setf all-results (append all-results (run-fetcher-tests)))

    ;; Run core tests
    (setf all-results (append all-results (run-core-tests)))

    ;; Summary
    (format t "~&~%========================================~%")
    (format t "  SUMMARY~%")
    (format t "========================================~%")

    (let ((passed (count :passed all-results :key #'cdr))
          (failed (count :failed all-results :key #'cdr)))

      (format t "~%  Test Results:~%")
      (dolist (result all-results)
        (format t "    ~A: ~A~%"
                (car result)
                (if (eq (cdr result) :passed)
                    " PASSED"
                    " FAILED")))

      (format t "~%  Total: ~D passed, ~D failed~%" passed failed)

      (when (zerop failed)
        (format t "~%  All tests passed!~%"))

      (values passed failed))))
