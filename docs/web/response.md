# akashic-web-response — HTTP Response Builder for KDOS / Megapad-64

Builds HTTP/1.1 responses into staging buffers, then sends via
`SEND` on the accepted socket descriptor.  Reuses `headers.f` builder
(`HDR-SET-OUTPUT`, `HDR-ADD`, `HDR-RESULT`) for header construction.

```forth
REQUIRE web/response.f
```

`PROVIDED akashic-web-response` — safe to include multiple times.

### Dependencies

```
web/response.f
├── net/headers.f     (akashic-http-headers)
├── utils/string.f    (akashic-string)
└── utils/datetime.f  (akashic-datetime)
```

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Layer 0 — Status Code](#layer-0--status-code)
- [Layer 1 — Headers](#layer-1--headers)
- [Layer 2 — Body (Buffer Mode)](#layer-2--body-buffer-mode)
- [Layer 3 — Sending](#layer-3--sending)
- [Layer 4 — JSON Convenience](#layer-4--json-convenience)
- [Layer 5 — Streaming (Chunked)](#layer-5--streaming-chunked)
- [Layer 6 — Common Responses](#layer-6--common-responses)
- [RESP-CLEAR](#resp-clear)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Buffered** | Status, headers, and body staged in memory buffers before sending.  One `RESP-SEND` call emits the complete response. |
| **Reuses headers.f** | `HDR-SET-OUTPUT` points the header builder at an internal buffer.  All `HDR-ADD`, `HDR-CONTENT-TYPE`, etc. work directly. |
| **Vectored send** | `_RESP-SEND-XT` variable holds the send hook xt.  Default calls `SEND` on the socket descriptor.  Tests can swap in a mock. |
| **Auto Content-Length** | `RESP-SEND` auto-computes `Content-Length` from body buffer length unless the user set it explicitly. |
| **Streaming mode** | `RESP-STREAM-START` / `RESP-CHUNK` / `RESP-STREAM-END` for chunked transfer-encoding. |

---

## Error Handling

| Word | Stack | Purpose |
|---|---|---|
| `RESP-ERR` | `( -- addr )` | Variable holding current error code (0 = none). |
| `RESP-E-SEND` | `( -- 1 )` | Error code: SEND failed. |
| `RESP-E-OVERFLOW` | `( -- 2 )` | Error code: body exceeds buffer. |
| `RESP-FAIL` | `( code -- )` | Set error code. |
| `RESP-OK?` | `( -- flag )` | `-1` if no error, `0` if error set. |
| `RESP-CLEAR-ERR` | `( -- )` | Reset error to 0. |

---

## Layer 0 — Status Code

### RESP-STATUS

```forth
RESP-STATUS  ( code -- )
```

Set the HTTP status code for the response.  Default is `200`.

```forth
404 RESP-STATUS
```

### _RESP-REASON

```forth
_RESP-REASON  ( code -- addr len )
```

Internal word.  Returns the reason phrase string for a status code.

Supported codes: 200, 201, 204, 301, 302, 304, 307, 400, 401, 403,
404, 405, 413, 500, 502, 503.  Unknown codes return `"Unknown"`.

---

## Layer 1 — Headers

All header words delegate to the `headers.f` builder pointed at
an internal 4096-byte staging buffer.

### RESP-HEADER

```forth
RESP-HEADER  ( name-a name-u val-a val-u -- )
```

Add an arbitrary response header.

```forth
S" X-Request-Id" S" abc123" RESP-HEADER
```

### Convenience Headers

| Word | Stack | Effect |
|---|---|---|
| `RESP-CONTENT-TYPE` | `( a u -- )` | Set `Content-Type` header. |
| `RESP-CONTENT-LENGTH` | `( n -- )` | Manually set `Content-Length`.  Disables auto-compute. |
| `RESP-LOCATION` | `( a u -- )` | Set `Location` header (for redirects). |
| `RESP-SET-COOKIE` | `( a u -- )` | Add `Set-Cookie` header. |
| `RESP-CORS` | `( -- )` | Add `Access-Control-Allow-Origin: *` and related headers. |
| `RESP-DATE` | `( -- )` | Add `Date` header with current UTC time (ISO 8601). |
| `RESP-CACHE` | `( seconds -- )` | Add `Cache-Control: max-age=N`. |
| `RESP-NO-CACHE` | `( -- )` | Add `Cache-Control: no-store, no-cache`. |

---

## Layer 2 — Body (Buffer Mode)

Body data is appended to an 8192-byte internal buffer.

### RESP-BODY

```forth
RESP-BODY  ( a u -- )
```

Append raw bytes to the body buffer.  Can be called multiple times.

### RESP-TEXT

```forth
RESP-TEXT  ( a u -- )
```

Shortcut: sets `Content-Type: text/plain` and appends body.

### RESP-HTML

```forth
RESP-HTML  ( a u -- )
```

Shortcut: sets `Content-Type: text/html; charset=utf-8` and appends body.

---

## Layer 3 — Sending

### RESP-SEND

```forth
RESP-SEND  ( -- )
```

Finalize and send the complete HTTP response:

1. Auto-compute `Content-Length` from body buffer (unless manually set).
2. Send status line: `HTTP/1.1 NNN Reason\r\n`.
3. Send accumulated headers.
4. Send blank line `\r\n`.
5. Send body (if non-empty).

```forth
RESP-CLEAR
200 RESP-STATUS
S" text/plain" RESP-CONTENT-TYPE
S" Hello, world!" RESP-BODY
RESP-SEND
```

### RESP-SET-SD

```forth
RESP-SET-SD  ( sd -- )
```

Set the socket descriptor for sending.  Called by `server.f` after
`SOCK-ACCEPT`.

---

## Layer 4 — JSON Convenience

### RESP-JSON

```forth
RESP-JSON  ( a u -- )
```

Sets `Content-Type: application/json` and appends the given string
as the response body.  Call `RESP-SEND` afterwards.

```forth
RESP-CLEAR
S\" {\"status\":\"ok\"}" RESP-JSON
RESP-SEND
```

---

## Layer 5 — Streaming (Chunked)

For responses where the total size is unknown at the start.

### RESP-STREAM-START

```forth
RESP-STREAM-START  ( -- )
```

Send status line + headers with `Transfer-Encoding: chunked`
immediately.  No `Content-Length`.

### RESP-CHUNK

```forth
RESP-CHUNK  ( a u -- )
```

Send one HTTP chunk: hex-length + CRLF + data + CRLF.

### RESP-STREAM-END

```forth
RESP-STREAM-END  ( -- )
```

Send terminal chunk `0\r\n\r\n` and clear streaming mode.

```forth
RESP-CLEAR
200 RESP-STATUS
S" text/plain" RESP-CONTENT-TYPE
RESP-STREAM-START
S" Hello " RESP-CHUNK
S" World!" RESP-CHUNK
RESP-STREAM-END
```

---

## Layer 6 — Common Responses

### RESP-ERROR

```forth
RESP-ERROR  ( code -- )
```

Send a complete error response with JSON body:
```json
{"error":404,"message":"Not Found"}
```

### RESP-REDIRECT

```forth
RESP-REDIRECT  ( code url-a url-u -- )
```

Send redirect with `Location` header and empty body.

```forth
302 S" /login" RESP-REDIRECT
```

### Shortcuts

| Word | Stack | Effect |
|---|---|---|
| `RESP-NOT-FOUND` | `( -- )` | `404 RESP-ERROR` |
| `RESP-METHOD-NOT-ALLOWED` | `( -- )` | `405 RESP-ERROR` |
| `RESP-INTERNAL-ERROR` | `( -- )` | `500 RESP-ERROR` |

---

## RESP-CLEAR

```forth
RESP-CLEAR  ( -- )
```

Reset all response state for a new connection:
- Error flag → 0
- Status code → 200
- Body buffer → empty
- Content-Length flag → unset
- Streaming flag → off
- Re-initialize header builder

Call this before building each response.

---

## Quick Reference

| Word | Stack Effect | Layer |
|---|---|---|
| `RESP-ERR` | `( -- addr )` | Error |
| `RESP-E-SEND` | `( -- 1 )` | Error |
| `RESP-E-OVERFLOW` | `( -- 2 )` | Error |
| `RESP-FAIL` | `( code -- )` | Error |
| `RESP-OK?` | `( -- flag )` | Error |
| `RESP-CLEAR-ERR` | `( -- )` | Error |
| `RESP-STATUS` | `( code -- )` | 0 |
| `RESP-HEADER` | `( na nu va vu -- )` | 1 |
| `RESP-CONTENT-TYPE` | `( a u -- )` | 1 |
| `RESP-CONTENT-LENGTH` | `( n -- )` | 1 |
| `RESP-LOCATION` | `( a u -- )` | 1 |
| `RESP-SET-COOKIE` | `( a u -- )` | 1 |
| `RESP-CORS` | `( -- )` | 1 |
| `RESP-DATE` | `( -- )` | 1 |
| `RESP-CACHE` | `( seconds -- )` | 1 |
| `RESP-NO-CACHE` | `( -- )` | 1 |
| `RESP-BODY` | `( a u -- )` | 2 |
| `RESP-TEXT` | `( a u -- )` | 2 |
| `RESP-HTML` | `( a u -- )` | 2 |
| `RESP-SEND` | `( -- )` | 3 |
| `RESP-SET-SD` | `( sd -- )` | 3 |
| `RESP-JSON` | `( a u -- )` | 4 |
| `RESP-STREAM-START` | `( -- )` | 5 |
| `RESP-CHUNK` | `( a u -- )` | 5 |
| `RESP-STREAM-END` | `( -- )` | 5 |
| `RESP-ERROR` | `( code -- )` | 6 |
| `RESP-REDIRECT` | `( code ua uu -- )` | 6 |
| `RESP-NOT-FOUND` | `( -- )` | 6 |
| `RESP-METHOD-NOT-ALLOWED` | `( -- )` | 6 |
| `RESP-INTERNAL-ERROR` | `( -- )` | 6 |
| `RESP-CLEAR` | `( -- )` | — |

---

## Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `_RESP-CODE` | `( -- addr )` | Status code variable. |
| `_RESP-SD` | `( -- addr )` | Socket descriptor variable. |
| `_RESP-STREAMING` | `( -- addr )` | Streaming mode flag. |
| `_RESP-HDR-BUF` | `( -- addr )` | 4096-byte header staging buffer. |
| `_RESP-BODY-BUF` | `( -- addr )` | 8192-byte body staging buffer. |
| `_RESP-BODY-LEN` | `( -- addr )` | Current body length variable. |
| `_RESP-CLEN-SET` | `( -- addr )` | Content-Length manually set flag. |
| `_RESP-SEND-XT` | `( -- addr )` | Vectored send hook (xt variable). |
| `_RESP-SEND-DEFAULT` | `( a u -- )` | Default send: `SEND` on socket. |
| `_RESP-SEND-RAW` | `( a u -- )` | Send via current hook. |
| `_RESP-REASON` | `( code -- a u )` | Status code → reason phrase. |
| `_RESP-BUILD-STATUS` | `( -- a u )` | Build status line in scratch buffer. |
| `_RESP-SL-BUF` | `( -- addr )` | 64-byte status line scratch buffer. |
| `_RESP-SL-LEN` | `( -- addr )` | Status line length variable. |
| `_RESP-SL-CHAR` | `( c -- )` | Append char to status line buffer. |
| `_RESP-SL-STR` | `( a u -- )` | Append string to status line buffer. |
| `_RESP-HDR-INIT` | `( -- )` | Point header builder at response buffer. |
| `_RESP-BODY-APPEND` | `( a u -- )` | Append to body buffer with overflow check. |
| `_RESP-BODY-CHAR` | `( c -- )` | Append one char to body buffer. |
| `_RESP-NUM>HEX` | `( n -- a u )` | Number to lowercase hex string. |
| `_RESP-NIBBLE` | `( n -- c )` | 4-bit value to hex ASCII char. |
| `_RESP-CRLF` | `( -- addr )` | 2-byte `\r\n` constant. |
| `_RESP-TERM-CHUNK` | `( -- addr )` | 5-byte `0\r\n\r\n` constant. |

---

## Cookbook

### Simple text response

```forth
RESP-CLEAR
S" Hello, world!" RESP-TEXT
RESP-SEND
```

### JSON API response

```forth
RESP-CLEAR
200 RESP-STATUS
S\" {\"users\":[1,2,3]}" RESP-JSON
RESP-SEND
```

### Redirect

```forth
RESP-CLEAR
302 S" /dashboard" RESP-REDIRECT
```

### 404 with JSON body

```forth
RESP-CLEAR
RESP-NOT-FOUND
\ Sends: HTTP/1.1 404 Not Found
\        Content-Type: application/json
\        Content-Length: 38
\        {"error":404,"message":"Not Found"}
```

### Streaming response

```forth
RESP-CLEAR
200 RESP-STATUS
S" text/event-stream" RESP-CONTENT-TYPE
RESP-STREAM-START
S" data: hello\n\n" RESP-CHUNK
S" data: world\n\n" RESP-CHUNK
RESP-STREAM-END
```
