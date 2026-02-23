# akashic-url — URL Vocabulary for KDOS / Megapad-64

A URL parsing, encoding, and query-string library for KDOS Forth.
Parses URLs into components (scheme, host, port, path, query, fragment),
provides RFC 3986 percent-encoding/decoding, and builds URLs from parts —
all using `(addr len)` string pairs with no hidden allocations.

```forth
REQUIRE url.f
```

`PROVIDED akashic-url` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Layer 0 — Percent Encoding](#layer-0--percent-encoding)
- [Layer 1 — URL Parsing](#layer-1--url-parsing)
  - [Scheme Constants](#scheme-constants)
  - [Parsed Component Storage](#parsed-component-storage)
  - [URL-PARSE](#url-parse)
  - [URL-DEFAULT-PORT](#url-default-port)
- [Layer 2 — Query Strings](#layer-2--query-strings)
- [Layer 3 — URL Building](#layer-3--url-building)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Buffer-based** | All encode/decode words take `( src slen dst dmax )` — caller provides both input and output buffers. |
| **No hidden allocations** | The library uses only a handful of `VARIABLE`s and fixed-size `CREATE`/`ALLOT` buffers for parsed components. |
| **13 schemes** | Built-in recognition for HTTP, HTTPS, FTP, FTPS, TFTP, Gopher, Rabbit, IRC, IRCS, SMTP, NTP, WS, and WSS. |
| **Default ports** | `URL-DEFAULT-PORT` maps every known scheme to its well-known port number, used by `URL-PARSE` and `URL-BUILD`. |
| **Round-trip** | Parse a URL with `URL-PARSE`, modify components, then rebuild with `URL-BUILD-*` — the library preserves all parts. |
| **Variable-based state** | Internal parsers use `VARIABLE`-based scanning instead of deep stack manipulation, avoiding the PICK/ROLL patterns that are fragile on KDOS. |

---

## Error Handling

### Variables

| Word | Stack | Purpose |
|---|---|---|
| `URL-ERR` | VARIABLE | Last error code (0 = no error) |
| `URL-ABORT-ON-ERROR` | VARIABLE | If true (default: false), abort on error |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `URL-E-MALFORMED` | 1 | URL structure is invalid |
| `URL-E-UNKNOWN-SCHEME` | 2 | Scheme not recognised |
| `URL-E-OVERFLOW` | 3 | Output buffer too small |

### Words

```forth
URL-FAIL       ( err-code -- )   \ Store error, optionally abort
URL-OK?        ( -- flag )       \ True if no error pending
URL-CLEAR-ERR  ( -- )            \ Reset error state
```

---

## Layer 0 — Percent Encoding

RFC 3986 percent-encoding for URLs.

### URL-UNRESERVED?

```forth
URL-UNRESERVED?  ( c -- flag )
```

Returns true if `c` is an unreserved character (A–Z, a–z, 0–9, `-`, `.`,
`_`, `~`).  Unreserved characters are never percent-encoded.

### URL-ENCODE

```forth
URL-ENCODE  ( src slen dst dmax -- written )
```

Percent-encode `src` into `dst`.  Unreserved characters pass through;
all others become `%XX`.  Returns number of bytes written.  Sets
`URL-E-OVERFLOW` if the output buffer is too small.

### URL-ENCODE-COMPONENT

```forth
URL-ENCODE-COMPONENT  ( src slen dst dmax -- written )
```

Like `URL-ENCODE` but uses URI-component rules — additionally allows
`/`, `@`, `:`, and a few other characters through un-encoded.  Use for
encoding path segments and query values.

### URL-DECODE

```forth
URL-DECODE  ( src slen dst dmax -- written )
```

Decode `%XX` sequences in `src` into raw bytes in `dst`.  Also converts
`+` to space (query-string convention).  Returns bytes written.

---

## Layer 1 — URL Parsing

### Scheme Constants

| Constant | Value | Protocol | Default Port |
|---|---|---|---|
| `URL-S-HTTP` | 0 | HTTP | 80 |
| `URL-S-HTTPS` | 1 | HTTPS | 443 |
| `URL-S-FTP` | 2 | FTP | 21 |
| `URL-S-FTPS` | 3 | FTP over TLS | 990 |
| `URL-S-TFTP` | 4 | TFTP | 69 |
| `URL-S-GOPHER` | 5 | Gopher | 70 |
| `URL-S-RABBIT` | 6 | Rabbit | 7443 |
| `URL-S-IRC` | 7 | IRC | 6667 |
| `URL-S-IRCS` | 8 | IRC over TLS | 6697 |
| `URL-S-SMTP` | 9 | SMTP | 25 |
| `URL-S-NTP` | 10 | NTP | 123 |
| `URL-S-WS` | 11 | WebSocket | 80 |
| `URL-S-WSS` | 12 | WebSocket Secure | 443 |

### Parsed Component Storage

After a successful `URL-PARSE`, the following variables and buffers
contain the parsed components:

| Word | Type | Max Size | Contents |
|---|---|---|---|
| `URL-SCHEME` | VARIABLE | — | Scheme constant (`URL-S-HTTP`, etc.) |
| `URL-HOST` | CREATE/ALLOT | 64 bytes | Hostname string |
| `URL-HOST-LEN` | VARIABLE | — | Hostname length |
| `URL-PORT` | VARIABLE | — | Port number (filled from URL or default) |
| `URL-PATH` | CREATE/ALLOT | 256 bytes | Path string |
| `URL-PATH-LEN` | VARIABLE | — | Path length |
| `URL-QUERY-BUF` | CREATE/ALLOT | 256 bytes | Query string (without `?`) |
| `URL-QUERY-LEN` | VARIABLE | — | Query string length |
| `URL-FRAG` | CREATE/ALLOT | 64 bytes | Fragment (without `#`) |
| `URL-FRAG-LEN` | VARIABLE | — | Fragment length |
| `URL-USERINFO` | CREATE/ALLOT | 64 bytes | User info (user:pass) |
| `URL-USER-LEN` | VARIABLE | — | User info length |

### URL-PARSE

```forth
URL-PARSE  ( addr len -- ior )
```

Parse a complete URL string.  Extracts scheme, optional userinfo,
host, optional port, path, optional query string, and optional fragment
into the component storage above.  If no port is given, fills
`URL-PORT` from `URL-DEFAULT-PORT`.  If no path is given, sets path
to `"/"`.

Returns 0 on success, non-zero on error.

```forth
S" https://api.example.com:8080/v1/data?fmt=json#top" URL-PARSE
\ URL-SCHEME @  → URL-S-HTTPS (1)
\ URL-HOST      → "api.example.com"   URL-HOST-LEN @ → 15
\ URL-PORT @    → 8080
\ URL-PATH      → "/v1/data"          URL-PATH-LEN @ → 8
\ URL-QUERY-BUF → "fmt=json"          URL-QUERY-LEN @ → 8
\ URL-FRAG      → "top"               URL-FRAG-LEN @ → 3
```

### URL-DEFAULT-PORT

```forth
URL-DEFAULT-PORT  ( scheme -- port )
```

Return the well-known port number for a scheme constant.

---

## Layer 2 — Query Strings

### URL-QUERY-NEXT

```forth
URL-QUERY-NEXT  ( a u -- a' u' key-a key-u val-a val-u flag )
```

Iterate key=value pairs from a query string.  `a u` is the remaining
query string; returns the next key, value, and a flag (true if a pair
was found).  The cursor `a' u'` advances past the consumed pair.

```forth
S" name=Alice&age=30" URL-QUERY-NEXT
\ key = "name", val = "Alice", flag = true
\ a' u' points to "age=30"
```

### URL-QUERY-FIND

```forth
URL-QUERY-FIND  ( a u key-a key-u -- val-a val-u flag )
```

Search a query string for a specific key.  Returns its value and true,
or a dummy value and false if not found.

### URL-QUERY-BUILD / URL-QUERY-ADD / URL-QUERY-RESULT

```forth
URL-QUERY-BUILD   ( dst max -- )                   \ Start building
URL-QUERY-ADD     ( key-a key-u val-a val-u -- )   \ Add key=value
URL-QUERY-RESULT  ( -- addr len )                  \ Get result
```

Incrementally build a query string: `&`-separated, percent-encoded
key=value pairs.

---

## Layer 3 — URL Building

Construct a URL string from components into a caller-provided buffer.

```forth
URL-BUILD          ( dst max -- )           \ Start builder
URL-BUILD-SCHEME   ( scheme-id -- )         \ Append "scheme://"
URL-BUILD-HOST     ( host-a host-u -- )     \ Append hostname
URL-BUILD-PORT     ( port -- )              \ Append ":port" (omits if default)
URL-BUILD-PATH     ( path-a path-u -- )     \ Append path
URL-BUILD-QUERY    ( query-a query-u -- )   \ Append "?query"
URL-BUILD-FRAG     ( frag-a frag-u -- )     \ Append "#fragment"
URL-BUILD-RESULT   ( -- addr len )          \ Get built URL
```

```forth
\ Build: https://example.com/api?q=test
CREATE _BUF 256 ALLOT
_BUF 256 URL-BUILD
URL-S-HTTPS URL-BUILD-SCHEME
S" example.com" URL-BUILD-HOST
443 URL-BUILD-PORT                \ omitted — matches default for HTTPS
S" /api" URL-BUILD-PATH
S" q=test" URL-BUILD-QUERY
URL-BUILD-RESULT TYPE
```

---

## Quick Reference

| Word | Stack | Layer |
|---|---|---|
| `URL-ENCODE` | `( src slen dst dmax -- written )` | 0 |
| `URL-ENCODE-COMPONENT` | `( src slen dst dmax -- written )` | 0 |
| `URL-DECODE` | `( src slen dst dmax -- written )` | 0 |
| `URL-UNRESERVED?` | `( c -- flag )` | 0 |
| `URL-PARSE` | `( addr len -- ior )` | 1 |
| `URL-DEFAULT-PORT` | `( scheme -- port )` | 1 |
| `URL-QUERY-NEXT` | `( a u -- a' u' key val flag )` | 2 |
| `URL-QUERY-FIND` | `( a u key-a key-u -- val-a val-u flag )` | 2 |
| `URL-QUERY-BUILD` | `( dst max -- )` | 2 |
| `URL-QUERY-ADD` | `( key-a key-u val-a val-u -- )` | 2 |
| `URL-QUERY-RESULT` | `( -- addr len )` | 2 |
| `URL-BUILD` | `( dst max -- )` | 3 |
| `URL-BUILD-SCHEME` | `( scheme-id -- )` | 3 |
| `URL-BUILD-HOST` | `( host-a host-u -- )` | 3 |
| `URL-BUILD-PORT` | `( port -- )` | 3 |
| `URL-BUILD-PATH` | `( path-a path-u -- )` | 3 |
| `URL-BUILD-QUERY` | `( query-a query-u -- )` | 3 |
| `URL-BUILD-FRAG` | `( frag-a frag-u -- )` | 3 |
| `URL-BUILD-RESULT` | `( -- addr len )` | 3 |

---

## Cookbook

### Parse and inspect a URL

```forth
S" http://user:pass@host.com:8080/path?q=1#frag" URL-PARSE
URL-SCHEME @ .            \ 0 (HTTP)
URL-HOST URL-HOST-LEN @ TYPE  \ host.com
URL-PORT @ .               \ 8080
URL-PATH URL-PATH-LEN @ TYPE  \ /path
URL-QUERY-BUF URL-QUERY-LEN @ TYPE  \ q=1
URL-FRAG URL-FRAG-LEN @ TYPE  \ frag
URL-USERINFO URL-USER-LEN @ TYPE  \ user:pass
```

### Search query parameters

```forth
S" https://search.com/?q=forth&lang=en" URL-PARSE
URL-QUERY-BUF URL-QUERY-LEN @
S" lang" URL-QUERY-FIND IF TYPE ELSE 2DROP ." not found" THEN
\ prints: en
```

### Percent-encode user input

```forth
CREATE _ENC 128 ALLOT
S" hello world & stuff" _ENC 128 URL-ENCODE-COMPONENT
_ENC SWAP TYPE
\ prints: hello%20world%20%26%20stuff
```

### Round-trip: parse → modify → rebuild

```forth
S" http://old.com/page" URL-PARSE
CREATE _OUT 256 ALLOT
_OUT 256 URL-BUILD
URL-S-HTTPS URL-BUILD-SCHEME       \ upgrade to HTTPS
S" new.com" URL-BUILD-HOST         \ change host
443 URL-BUILD-PORT
S" /page" URL-BUILD-PATH
URL-BUILD-RESULT TYPE
\ prints: https://new.com/page
```
