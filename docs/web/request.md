# akashic-web-request — HTTP Request Parser for KDOS / Megapad-64

Parses incoming HTTP/1.1 requests from a raw receive buffer into
structured fields.  Zero-copy — all results are `(addr len)` pointers
into the caller's receive buffer.

```forth
REQUIRE web/request.f
```

`PROVIDED akashic-web-request` — safe to include multiple times.

### Dependencies

```
web/request.f
├── net/headers.f   (akashic-http-headers)
├── net/url.f       (akashic-url)
└── utils/string.f  (akashic-string)
```

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Layer 0 — Request Line](#layer-0--request-line)
- [Layer 1 — Header Parsing](#layer-1--header-parsing)
  - [REQ-HEADER](#req-header)
  - [Shortcut Accessors](#shortcut-accessors)
- [Layer 2 — Body](#layer-2--body)
  - [REQ-JSON-BODY / REQ-FORM-BODY](#req-json-body--req-form-body)
- [Layer 3 — Full Parse](#layer-3--full-parse)
- [Layer 4 — Query Parameter Access](#layer-4--query-parameter-access)
- [Layer 5 — Method Checks](#layer-5--method-checks)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | All returned `(addr len)` pairs point directly into the original receive buffer.  No copying, no hidden allocations. |
| **Variable-based state** | All parsed fields stored in module-level `VARIABLE`s.  No `PICK`, `ROLL`, or deep stack gymnastics. |
| **Layered** | Each layer is independently usable and testable.  `REQ-PARSE-LINE` works without `REQ-PARSE-HEADERS`. |
| **Reuses headers.f + url.f** | Header lookup delegates to `HDR-FIND` (case-insensitive).  Query parameter access delegates to `URL-QUERY-FIND` / `URL-QUERY-NEXT`. |
| **Server-side complement** | Uses the `REQ-` prefix to avoid collision with the `HTTP-` client library.  Both can coexist — a handler can call `HTTP-GET` to proxy a backend request. |

---

## Error Handling

### Variables

| Word | Stack | Purpose |
|---|---|---|
| `REQ-ERR` | VARIABLE | Last error code (0 = no error) |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `REQ-E-MALFORMED` | 1 | Request line not parseable (missing spaces) |
| `REQ-E-NO-CRLF` | 2 | No CRLF (or LF) found in request line |
| `REQ-E-TOO-LONG` | 3 | Request exceeds buffer |

### Words

```forth
REQ-FAIL       ( code -- )   \ Store error code
REQ-OK?        ( -- flag )   \ True if no error pending
REQ-CLEAR-ERR  ( -- )        \ Reset error state
```

---

## Layer 0 — Request Line

Parses the first line of an HTTP request:

```
METHOD SP REQUEST-TARGET SP HTTP-VERSION CRLF
```

If the request target contains `?`, it is split into path and query
string components.

### REQ-PARSE-LINE

```forth
REQ-PARSE-LINE  ( addr len -- )
```

Parse the request line from a raw buffer.  On success, populates:

| Accessor | Stack | Example value |
|---|---|---|
| `REQ-METHOD` | `( -- a u )` | `"GET"`, `"POST"`, `"PUT"`, etc. |
| `REQ-PATH` | `( -- a u )` | `"/api/users"` |
| `REQ-QUERY` | `( -- a u )` | `"page=2&sort=name"` (empty if no `?`) |
| `REQ-VERSION` | `( -- a u )` | `"HTTP/1.1"` |

On failure, sets `REQ-ERR` to `REQ-E-MALFORMED` or `REQ-E-NO-CRLF`.

### Examples

```forth
\ Given buffer containing "GET /search?q=hello HTTP/1.1\r\n..."
buf len REQ-PARSE-LINE
REQ-METHOD TYPE   \ → GET
REQ-PATH TYPE     \ → /search
REQ-QUERY TYPE    \ → q=hello
```

---

## Layer 1 — Header Parsing

Locates the header block between the request line (first CRLF) and
the blank line (CRLFCRLF).  Supports both `\r\n` and bare `\n`.

### REQ-PARSE-HEADERS

```forth
REQ-PARSE-HEADERS  ( addr len -- )
```

Find and store the header region from the full request buffer.
Must be called after `REQ-PARSE-LINE` (or use `REQ-PARSE` which
calls both).

### REQ-HEADER

```forth
REQ-HEADER  ( name-a name-u -- val-a val-u flag )
```

Look up a header by name (case-insensitive).  Returns the value
string and `-1` (true) if found, or `0 0 0` if not found.

Delegates to `HDR-FIND` from `headers.f`.

```forth
S" Content-Type" REQ-HEADER
IF TYPE CR ELSE 2DROP ." not found" THEN
```

### Shortcut Accessors

Convenience words that wrap `REQ-HEADER` for common headers.
Return `(addr len)` or `(0 0)` if absent.

| Word | Stack | Header looked up |
|---|---|---|
| `REQ-CONTENT-TYPE` | `( -- a u )` | `Content-Type` |
| `REQ-HOST` | `( -- a u )` | `Host` |
| `REQ-ACCEPT` | `( -- a u )` | `Accept` |
| `REQ-AUTH` | `( -- a u )` | `Authorization` |
| `REQ-COOKIE` | `( -- a u )` | `Cookie` |

### REQ-CONTENT-LENGTH

```forth
REQ-CONTENT-LENGTH  ( -- n )
```

Parse the `Content-Length` header to an integer.  Returns `-1` if
the header is absent.  Delegates to `HDR-PARSE-CLEN` from `headers.f`.

---

## Layer 2 — Body

### REQ-PARSE-BODY

```forth
REQ-PARSE-BODY  ( addr len -- )
```

Locate the body after the blank line (`\r\n\r\n`).  Sets
`REQ-BODY` to point into the receive buffer.  If no blank line
is found, body length is 0.

### REQ-BODY

```forth
REQ-BODY  ( -- a u )
```

Return the request body as `(addr len)`.

### REQ-JSON-BODY / REQ-FORM-BODY

```forth
REQ-JSON-BODY  ( -- a u )
REQ-FORM-BODY  ( -- a u )
```

Return the body only if the `Content-Type` matches:

| Word | Required Content-Type |
|---|---|
| `REQ-JSON-BODY` | `application/json` (case-insensitive prefix) |
| `REQ-FORM-BODY` | `application/x-www-form-urlencoded` (case-insensitive prefix) |

If the content type doesn't match, returns `(0 0)`.  If no
`Content-Type` header is present, falls back to returning the raw body.

> **Tip:** `REQ-FORM-BODY` returns data in `key=value&key2=value2`
> format — the same format as URL query strings.  Use
> `URL-QUERY-FIND` / `URL-QUERY-NEXT` from `url.f` to iterate it.

---

## Layer 3 — Full Parse

### REQ-PARSE

```forth
REQ-PARSE  ( addr len -- )
```

One-call full request parse:

1. `REQ-CLEAR` — reset all state
2. `REQ-PARSE-LINE` — extract method, path, query, version
3. `REQ-PARSE-HEADERS` — locate header block
4. `REQ-PARSE-BODY` — locate body

If `REQ-PARSE-LINE` fails, parsing stops early and `REQ-OK?`
returns false.

### REQ-CLEAR

```forth
REQ-CLEAR  ( -- )
```

Reset all request state (all fields to `0 0`, clear error).
Called automatically by `REQ-PARSE`.

---

## Layer 4 — Query Parameter Access

Thin wrappers over `URL-QUERY-FIND` / `URL-QUERY-NEXT` from `url.f`,
operating on the query string extracted by `REQ-PARSE-LINE`.

### REQ-PARAM-FIND

```forth
REQ-PARAM-FIND  ( key-a key-u -- val-a val-u flag )
```

Find a query parameter by key name.  Returns value and `-1` if found,
or `0 0 0` if not found.

```forth
\ Given request: GET /search?q=hello&page=2 HTTP/1.1
S" q" REQ-PARAM-FIND IF TYPE THEN    \ → hello
S" page" REQ-PARAM-FIND IF TYPE THEN \ → 2
```

### REQ-PARAM?

```forth
REQ-PARAM?  ( key-a key-u -- flag )
```

Test whether a query parameter exists (discards the value).

### REQ-PARAM-NEXT

```forth
REQ-PARAM-NEXT  ( a u -- a' u' key-a key-u val-a val-u flag )
```

Iterate query parameters from a cursor.  Same interface as
`URL-QUERY-NEXT`.  Pass `REQ-QUERY` as the initial cursor.

---

## Layer 5 — Method Checks

Convenience words for testing the request method in handlers.
Each returns `-1` (true) or `0` (false).

| Word | Stack | Method |
|---|---|---|
| `REQ-GET?` | `( -- flag )` | GET |
| `REQ-POST?` | `( -- flag )` | POST |
| `REQ-PUT?` | `( -- flag )` | PUT |
| `REQ-DELETE?` | `( -- flag )` | DELETE |
| `REQ-HEAD?` | `( -- flag )` | HEAD |
| `REQ-OPTIONS?` | `( -- flag )` | OPTIONS |
| `REQ-PATCH?` | `( -- flag )` | PATCH |

```forth
REQ-GET? IF
    ." handling GET" CR
ELSE REQ-POST? IF
    ." handling POST" CR
THEN THEN
```

---

## Quick Reference

| Word | Stack | Layer |
|---|---|---|
| `REQ-PARSE` | `( addr len -- )` | 3 |
| `REQ-CLEAR` | `( -- )` | 3 |
| `REQ-PARSE-LINE` | `( addr len -- )` | 0 |
| `REQ-METHOD` | `( -- a u )` | 0 |
| `REQ-PATH` | `( -- a u )` | 0 |
| `REQ-QUERY` | `( -- a u )` | 0 |
| `REQ-VERSION` | `( -- a u )` | 0 |
| `REQ-PARSE-HEADERS` | `( addr len -- )` | 1 |
| `REQ-HEADER` | `( name-a name-u -- val-a val-u flag )` | 1 |
| `REQ-CONTENT-TYPE` | `( -- a u )` | 1 |
| `REQ-CONTENT-LENGTH` | `( -- n )` | 1 |
| `REQ-HOST` | `( -- a u )` | 1 |
| `REQ-ACCEPT` | `( -- a u )` | 1 |
| `REQ-AUTH` | `( -- a u )` | 1 |
| `REQ-COOKIE` | `( -- a u )` | 1 |
| `REQ-PARSE-BODY` | `( addr len -- )` | 2 |
| `REQ-BODY` | `( -- a u )` | 2 |
| `REQ-JSON-BODY` | `( -- a u )` | 2 |
| `REQ-FORM-BODY` | `( -- a u )` | 2 |
| `REQ-PARAM-FIND` | `( key-a key-u -- val-a val-u flag )` | 4 |
| `REQ-PARAM?` | `( key-a key-u -- flag )` | 4 |
| `REQ-PARAM-NEXT` | `( a u -- a' u' key-a key-u val-a val-u flag )` | 4 |
| `REQ-GET?` | `( -- flag )` | 5 |
| `REQ-POST?` | `( -- flag )` | 5 |
| `REQ-PUT?` | `( -- flag )` | 5 |
| `REQ-DELETE?` | `( -- flag )` | 5 |
| `REQ-HEAD?` | `( -- flag )` | 5 |
| `REQ-OPTIONS?` | `( -- flag )` | 5 |
| `REQ-PATCH?` | `( -- flag )` | 5 |

---

## Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `_REQ-FIND-SP` | `( addr len -- idx \| -1 )` | Find first space character |
| `_REQ-FIND-CRLF` | `( addr len -- idx \| -1 )` | Find first CRLF pair (returns index of CR) |
| `_REQ-METHOD-A/U` | VARIABLE pair | Method string pointer |
| `_REQ-PATH-A/U` | VARIABLE pair | Path string pointer |
| `_REQ-QUERY-A/U` | VARIABLE pair | Query string pointer |
| `_REQ-VERSION-A/U` | VARIABLE pair | Version string pointer |
| `_REQ-HDR-A/U` | VARIABLE pair | Header block pointer |
| `_REQ-BODY-A/U` | VARIABLE pair | Body pointer |

---

## Cookbook

### Parse a GET request

```forth
\ buf contains the raw bytes from RECV
buf len REQ-PARSE
REQ-OK? IF
    REQ-METHOD TYPE ."  " REQ-PATH TYPE CR   \ → GET /hello
ELSE
    ." Bad request" CR
THEN
```

### Access query parameters

```forth
buf len REQ-PARSE
S" page" REQ-PARAM-FIND IF
    STR>NUM IF
        ." Page number: " . CR
    ELSE
        DROP ." Invalid page" CR
    THEN
ELSE
    2DROP ." No page param" CR
THEN
```

### Parse JSON body from a POST

```forth
buf len REQ-PARSE
REQ-POST? IF
    REQ-JSON-BODY DUP IF
        \ Use json.f to navigate the body
        S" name" JSON-KEY DUP IF
            JSON-GET-STRING TYPE CR
        ELSE
            2DROP ." missing name" CR
        THEN
    ELSE
        2DROP ." Not JSON or no body" CR
    THEN
THEN
```

### Parse form-urlencoded body

```forth
buf len REQ-PARSE
REQ-POST? IF
    REQ-FORM-BODY DUP IF
        S" username" URL-QUERY-FIND IF
            ." User: " TYPE CR
        ELSE
            2DROP ." no username" CR
        THEN
    ELSE
        2DROP ." Not form data" CR
    THEN
THEN
```

### Check method and route manually

```forth
buf len REQ-PARSE
REQ-GET? IF
    REQ-PATH S" /health" STR-STR= IF
        ." OK" CR
    THEN
THEN
```
