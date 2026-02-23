# akashic-http-headers — HTTP Header Vocabulary for KDOS / Megapad-64

An HTTP header builder and parser for KDOS Forth.
Constructs well-formed HTTP/1.1 request headers into a buffer and parses
response headers — status codes, Content-Length, chunked detection,
arbitrary header lookup — all with case-insensitive matching.

```forth
REQUIRE headers.f
```

`PROVIDED akashic-http-headers` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Header Building](#header-building)
  - [Lifecycle](#lifecycle)
  - [Request Line](#request-line)
  - [Common Headers](#common-headers)
  - [Completing the Request](#completing-the-request)
- [Header Parsing](#header-parsing)
  - [Status Line](#status-line)
  - [Header/Body Boundary](#headerbody-boundary)
  - [Content-Length](#content-length)
  - [Generic Lookup](#generic-lookup)
  - [Convenience Parsers](#convenience-parsers)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Single buffer** | All building words append to one internal 4096-byte buffer (or a caller-provided buffer via `HDR-SET-OUTPUT`). |
| **Case-insensitive parsing** | All parse words (`HDR-FIND`, `HDR-PARSE-CLEN`, `HDR-CHUNKED?`, etc.) use case-insensitive prefix matching via `_CI-PREFIX`. |
| **No hidden allocations** | One 4096-byte static buffer and a handful of `VARIABLE`s. |
| **Composable** | Build words chain freely: `HDR-RESET` → method → headers → `HDR-END` → optional `HDR-BODY` → `HDR-RESULT`. |

---

## Error Handling

### Variables

| Word | Stack | Purpose |
|---|---|---|
| `HDR-ERR` | VARIABLE | Last error code (0 = no error) |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `HDR-E-OVERFLOW` | 1 | Output buffer full |
| `HDR-E-MALFORMED` | 2 | Malformed header data |

### Words

```forth
HDR-FAIL       ( code -- )   \ Store error code
HDR-OK?        ( -- flag )   \ True if no error pending
HDR-CLEAR-ERR  ( -- )        \ Reset error state
```

---

## Header Building

### Lifecycle

```forth
HDR-RESET       ( -- )            \ Clear buffer, reset to internal 4096-byte buf
HDR-SET-OUTPUT  ( addr max -- )   \ Use external buffer instead
HDR-RESULT      ( -- addr len )   \ Get completed request (addr + byte count)
```

### Request Line

```forth
HDR-METHOD   ( method-a method-u path-a path-u -- )
```

Append `METHOD /path HTTP/1.1\r\n`.

Convenience shorthand:

```forth
HDR-GET      ( path-a path-u -- )   \ GET /path HTTP/1.1\r\n
HDR-POST     ( path-a path-u -- )   \ POST /path HTTP/1.1\r\n
HDR-PUT      ( path-a path-u -- )   \ PUT /path HTTP/1.1\r\n
HDR-DELETE   ( path-a path-u -- )   \ DELETE /path HTTP/1.1\r\n
```

### Common Headers

```forth
HDR-ADD              ( name-a name-u val-a val-u -- )  \ Name: Value\r\n
HDR-HOST             ( host-a host-u -- )              \ Host: ...\r\n
HDR-AUTH-BEARER      ( token-a token-u -- )            \ Authorization: Bearer ...\r\n
HDR-CONTENT-TYPE     ( ct-a ct-u -- )                  \ Content-Type: ...\r\n
HDR-CONTENT-JSON     ( -- )                            \ Content-Type: application/json\r\n
HDR-CONTENT-FORM     ( -- )       \ Content-Type: application/x-www-form-urlencoded\r\n
HDR-CONTENT-LENGTH   ( n -- )                          \ Content-Length: <n>\r\n
HDR-CONNECTION-CLOSE ( -- )                            \ Connection: close\r\n
HDR-ACCEPT           ( type-a type-u -- )              \ Accept: ...\r\n
HDR-USER-AGENT       ( ua-a ua-u -- )                  \ User-Agent: ...\r\n
```

### Completing the Request

```forth
HDR-END    ( -- )                  \ Append blank CRLF (end of headers)
HDR-BODY   ( body-a body-u -- )    \ Append raw body data after headers
HDR-RESULT ( -- addr len )         \ Retrieve the complete request
```

---

## Header Parsing

### Header/Body Boundary

```forth
HDR-FIND-HEND  ( addr len -- offset | 0 )
```

Scan for the `\r\n\r\n` or `\n\n` double-newline that separates
headers from body.  Returns the offset past the boundary (i.e.,
where the body starts), or 0 if not found.

### Status Line

```forth
HDR-PARSE-STATUS  ( addr len -- code )
```

Extract the 3-digit HTTP status code from byte offset 9 of the
response (assumes `HTTP/1.x NNN ...` format).

### Content-Length

```forth
HDR-PARSE-CLEN  ( hdr-addr hdr-len -- n | -1 )
```

Search headers (case-insensitive) for `Content-Length:` and parse
its decimal value.  Returns -1 if not found.

### Generic Lookup

```forth
HDR-FIND  ( hdr-a hdr-u name-a name-u -- val-a val-u flag )
```

Search response headers for a header by name (case-insensitive).
Returns the value string and true if found, or dummy values and false.
The returned value is trimmed of leading whitespace.

### Convenience Parsers

```forth
HDR-CHUNKED?    ( hdr-a hdr-u -- flag )
```

True if `Transfer-Encoding: chunked` is present (case-insensitive
substring match).

```forth
HDR-LOCATION    ( hdr-a hdr-u -- url-a url-u flag )
```

Extract the `Location` header value (for redirects).

```forth
HDR-SET-COOKIE  ( hdr-a hdr-u -- val-a val-u flag )
```

Extract the `Set-Cookie` header value.

---

## Quick Reference

### Building

| Word | Stack |
|---|---|
| `HDR-RESET` | `( -- )` |
| `HDR-SET-OUTPUT` | `( addr max -- )` |
| `HDR-METHOD` | `( method-a method-u path-a path-u -- )` |
| `HDR-GET` | `( path-a path-u -- )` |
| `HDR-POST` | `( path-a path-u -- )` |
| `HDR-PUT` | `( path-a path-u -- )` |
| `HDR-DELETE` | `( path-a path-u -- )` |
| `HDR-ADD` | `( name-a name-u val-a val-u -- )` |
| `HDR-HOST` | `( host-a host-u -- )` |
| `HDR-AUTH-BEARER` | `( token-a token-u -- )` |
| `HDR-CONTENT-TYPE` | `( ct-a ct-u -- )` |
| `HDR-CONTENT-JSON` | `( -- )` |
| `HDR-CONTENT-FORM` | `( -- )` |
| `HDR-CONTENT-LENGTH` | `( n -- )` |
| `HDR-CONNECTION-CLOSE` | `( -- )` |
| `HDR-ACCEPT` | `( type-a type-u -- )` |
| `HDR-USER-AGENT` | `( ua-a ua-u -- )` |
| `HDR-END` | `( -- )` |
| `HDR-BODY` | `( body-a body-u -- )` |
| `HDR-RESULT` | `( -- addr len )` |

### Parsing

| Word | Stack |
|---|---|
| `HDR-FIND-HEND` | `( addr len -- offset \| 0 )` |
| `HDR-PARSE-STATUS` | `( addr len -- code )` |
| `HDR-PARSE-CLEN` | `( hdr-addr hdr-len -- n \| -1 )` |
| `HDR-FIND` | `( hdr-a hdr-u name-a name-u -- val-a val-u flag )` |
| `HDR-CHUNKED?` | `( hdr-a hdr-u -- flag )` |
| `HDR-LOCATION` | `( hdr-a hdr-u -- url-a url-u flag )` |
| `HDR-SET-COOKIE` | `( hdr-a hdr-u -- val-a val-u flag )` |

---

## Internal Words

These are not part of the public API but may be useful for debugging
or extension:

| Word | Stack | Purpose |
|---|---|---|
| `_CI-LOWER` | `( c -- c' )` | ASCII to lowercase |
| `_CI-EQ` | `( c1 c2 -- flag )` | Case-insensitive char compare |
| `_CI-PREFIX` | `( src match len -- flag )` | Case-insensitive prefix match |
| `_HDR-APPEND` | `( addr len -- )` | Append bytes to output |
| `_HDR-CHAR` | `( c -- )` | Append single byte |
| `_HDR-CRLF` | `( -- )` | Append `\r\n` |

---

## Cookbook

### Build a GET request

```forth
HDR-RESET
S" /api/users" HDR-GET
S" api.example.com" HDR-HOST
HDR-CONNECTION-CLOSE
S" KDOS/1.1" HDR-USER-AGENT
HDR-END
HDR-RESULT TYPE
\ GET /api/users HTTP/1.1\r\n
\ Host: api.example.com\r\n
\ Connection: close\r\n
\ User-Agent: KDOS/1.1\r\n
\ \r\n
```

### Build a POST with JSON body

```forth
HDR-RESET
S" /api/data" HDR-POST
S" api.example.com" HDR-HOST
S" {\"key\":42}" DUP HDR-CONTENT-LENGTH
HDR-CONTENT-JSON
HDR-CONNECTION-CLOSE
HDR-END
HDR-BODY
HDR-RESULT  \ → complete request with body
```

### Parse a response

```forth
\ Assuming response is in buf/len:
buf len HDR-PARSE-STATUS .        \ 200
buf len HDR-FIND-HEND             \ offset past headers
buf len S" Content-Type" HDR-FIND
IF TYPE ELSE 2DROP ." none" THEN
buf len HDR-CHUNKED? IF ." chunked" THEN
```

### Use an external buffer

```forth
CREATE _MY-BUF 8192 ALLOT
_MY-BUF 8192 HDR-SET-OUTPUT
HDR-RESET
\ ... build headers into _MY-BUF instead of internal buffer
```
