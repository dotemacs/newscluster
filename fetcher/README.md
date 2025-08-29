# Newscluster Feed Fetcher

A Common Lisp library for fetching and parsing RSS/Atom feeds, integrated into the newscluster system.

## Features

- Dual parser support: `feeder` library (primary) with `cl-feedparser` fallback
- RSS 2.0 and Atom 1.0 support
- Category/tag filtering support (feeder parser only)
- HTTP fetching with automatic fallback between parsers
- Local file parsing
- Unicode character translation
- MD5-based item identification
- S-expression output format compatible with newscluster
- Robust handling of malformed feeds and XML issues
- Automatic retry mechanism with alternative parser

## Dependencies

The fetcher requires the following Common Lisp libraries:

**Primary parser dependencies:**
- `feeder` - RSS/Atom feed parsing with category support
- `plump` - HTML/XML manipulation (used by feeder)

**Fallback parser dependencies:**
- `cl-feedparser` - Alternative RSS/Atom parser

**Shared dependencies:**
- `drakma` - HTTP client
- `cl-ppcre` - Regular expressions
- `ironclad` - Cryptography (MD5 hashing)
- `flexi-streams` - Character encoding
- `local-time` - Time manipulation
- `alexandria` - Utility functions
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

The fetcher is automatically loaded as a dependency of the main newscluster system and is used for all feed fetching operations.

## File Structure

The fetcher creates the following structure in the target directory:

```
directory/
├── channel-info.sexp      # Channel metadata
├── items/                  # Individual feed items
│   ├── [hash1].sexp
│   ├── [hash2].sexp
│   └── ...
├── required-tags          # Optional: tag filter list (one tag per line)
└── failure-count          # Failure tracking
```

### Tag Filtering

If a `required-tags` file exists in the channel directory, only feed items that have at least one matching category/tag will be saved. This allows filtering feeds to specific topics.

**Note:** Tag filtering is only supported when using the primary `feeder` parser. The `cl-feedparser` fallback does not support category filtering.

For example, to only fetch Lisp-related posts, create a `required-tags` file with:

```
lisp
common-lisp
scheme
clojure
```

## Output Format

### channel-info.sexp
```lisp
(channel :name "feed-name"
         :title "Feed Title"
         :description "Feed description"
         :url "http://example.com"
         :feed-url "http://example.com/feed.xml"
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

The fetcher is tested as part of the main newscluster test suite:

```bash
# Run all tests from command line
./cli-tests.lisp

# Or test in the REPL
sbcl
(load "repl-tests.lisp")
(newscluster-tests:run-fetcher-tests)

# Test a single feed type
(newscluster-tests:run-single-fetcher-test "rss-basic")
```

The test suite includes tests for:
- RSS 2.0 feeds
- Atom 1.0 feeds
- Empty feeds
- CDATA handling
- Malformed XML handling
- Category/tag filtering

## Architecture

The fetcher consists of four main components:

1. **fetcher.lisp** - Main fetching logic with dual parser support and HTTP handling
2. **fetcher-feedparser.lisp** - Alternative parser implementation using `cl-feedparser`
3. **package.lisp** - Package definition and exports
4. **newscluster-fetcher.asd** - ASDF system definition with dependencies

### Key Implementation Details

- **Dual parser architecture**: Primary `feeder` library with `cl-feedparser` fallback
- **Automatic fallback**: If the primary parser fails, automatically retries with the alternative parser
- **Shared utilities**: Common HTTP fetching, file I/O, and string processing functions
- **Parser-specific handling**: Different data extraction methods for each parser library
- **Robust error handling**: Gracefully handles malformed feeds, missing data, and parser failures
- Handles both string IDs and `feeder:link` objects for feed item identification
- Automatically converts between Unix time and Universal time for compatibility
- Supports both HTTP URLs and local file paths as input
- XML preprocessing to fix common malformed feed issues (e.g., Blogspot timestamp formats)

## API

### Main Function

`(fetch-channel url directory name)`

Fetches a feed from URL and saves it to DIRECTORY with the given NAME. Automatically tries the primary `feeder` parser first, then falls back to `cl-feedparser` if needed.

- **url**: Feed URL (http/https) or local file path
- **directory**: Output directory path (will be created if needed)
- **name**: Channel name for identification
- **Returns**: T on success, NIL if both parsers fail

### Parser-Specific Functions

`(fetch-channel-original url directory name)` - Uses `feeder` parser only
`(fetch-channel-feedparser url directory name)` - Uses `cl-feedparser` only

## License

Same as newscluster project.
