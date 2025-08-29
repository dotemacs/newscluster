# Newscluster Feed Fetcher

A Common Lisp library for fetching and parsing RSS/Atom feeds, integrated into the newscluster system.

## Features

- Full RSS 2.0 and Atom 1.0 support
- Conditional GET with If-Modified-Since headers
- Tag-based filtering
- Unicode character translation
- MD5-based item identification
- Failure tracking and retry logic
- S-expression output format

## Dependencies

The fetcher requires the following Common Lisp libraries:

- `drakma` - HTTP client
- `cxml` - XML parsing
- `cl-ppcre` - Regular expressions
- `ironclad` - Cryptography (MD5 hashing)
- `flexi-streams` - Character encoding
- `sb-posix` - POSIX functions (SBCL-specific)

These are automatically loaded when the newscluster system is loaded.

## Usage

The fetcher is integrated into newscluster and is automatically used when fetching feeds.

### Direct Library Usage

```lisp
;; Load the system
(asdf:load-system :newscluster-fetcher)

;; Fetch a feed
(newscluster-fetcher:fetch-channel 
  "http://example.com/feed.xml"    ; Feed URL or local file path
  "/path/to/channel/directory/"    ; Output directory
  "channel-name")                   ; Channel name
```

### Integration with Newscluster

The fetcher is automatically loaded as a dependency of the main newscluster system. When a channel with `source = "python"` is processed, it uses this fetcher.

## File Structure

The fetcher creates the following structure in the target directory:

```
directory/
├── channel-info.sexp      # Channel metadata
├── items/                  # Individual feed items
│   ├── [hash1].sexp
│   ├── [hash2].sexp
│   └── ...
├── required-tags          # Optional: tag filter list
└── failure-count          # Failure tracking
```

## Output Format

### channel-info.sexp
```lisp
(channel :name "feed-name"
         :title "Feed Title"
         :description "Feed description"
         :url "http://example.com"
         :feed-url "http://example.com/feed.xml"
         :source "python"
         :current-item-files (#p"hash1.sexp" #p"hash2.sexp")
         :last-fetch-time 3912192000)
```

### items/[hash].sexp
```lisp
(item :id "http://example.com/post1"
      :title "Post Title"
      :author-name "Author Name"
      :description "Post content..."
      :date 3912192000
      :link "http://example.com/post1")
```

## Testing

Run the test suite to verify functionality:

```bash
./run-tests.lisp
```

The test suite includes tests for:
- RSS 2.0 feeds
- Atom 1.0 feeds
- Empty feeds
- CDATA handling
- Malformed XML handling

## Architecture

The fetcher consists of three main components:

1. **xml-parser.lisp** - XML parsing and feed format detection
2. **fetcher.lisp** - Main fetching logic, HTTP handling, and file I/O
3. **package.lisp** - Package definition and exports

## API

### Main Function

`(fetch-channel url directory name)`

Fetches a feed from URL and saves it to DIRECTORY with the given NAME.

- **url**: Feed URL (http/https) or local file path
- **directory**: Output directory path (will be created if needed)
- **name**: Channel name for identification
- **Returns**: T on success, NIL on failure

## License

Same as newscluster project.