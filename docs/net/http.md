# akashic-http — HTTP/1.1 Client for KDOS / Megapad-64

A full HTTP/1.1 client for KDOS Forth.  Abstracts TCP/TLS connections,
provides a receive loop, parses responses (including chunked transfer
decoding), executes GET/POST requests, manages persistent session
headers, caches DNS lookups, and detects redirects.

```forth
REQUIRE http.f
```

`PROVIDED akashic-http` — safe to include multiple times.

### Dependencies

```
http.f
├── url.f       (akashic-url)
└── headers.f   (akashic-http-headers)
```

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Layer 0 — Connection Abstraction](#layer-0--connection-abstraction)
- [Layer 1 — Receive Loop](#layer-1--receive-loop)
- [Layer 2 — Response Processing](#layer-2--response-processing)
  - [HTTP-PARSE](#http-parse)
  - [HTTP-DECHUNK](#http-dechunk)
  - [HTTP-HEADER](#http-header)
- [Layer 3 — Request Execution](#layer-3--request-execution)
  - [HTTP-REQUEST](#http-request)
  - [HTTP-GET](#http-get)
  - [HTTP-POST / HTTP-POST-JSON](#http-post--http-post-json)
- [Layer 4 — Session Headers](#layer-4--session-headers)
- [Layer 5 — DNS Cache](#layer-5--dns-cache)
- [Layer 6 — Redirect Detection](#layer-6--redirect-detection)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **TCP/TLS dispatch** | A single `_HTTP-TLS` flag selects between `TCP-*` and `TLS-*` KDOS syscalls.  TLS connections automatically set SNI hostname. |
| **Connection: close** | All requests send `Connection: close` — avoids chunked-by-default responses and keeps the state machine simple. |
| **Variable-based state** | All multi-step operations use `VARIABLE`-based accumulators.  No `PICK`, `ROLL`, or deep return-stack gymnastics. |
| **Layered** | Each layer is independently testable: Layers 2 and 4–6 work without network hardware (tested in emulator with 52 unit tests). |
| **Reuses url.f + headers.f** | URL parsing, header building, and header parsing are delegated to the lower libraries. |
| **Ephemeral ports** | Local ports auto-increment from 12345 via `_HTTP-NEXT-PORT`, avoiding TCB reuse collisions. |

---

## Error Handling

### Variables

| Word | Stack | Purpose |
|---|---|---|
| `HTTP-ERR` | VARIABLE | Last error code (0 = no error) |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `HTTP-E-DNS` | 1 | DNS resolution failed |
| `HTTP-E-CONNECT` | 2 | TCP/TLS connect returned 0 |
| `HTTP-E-SEND` | 3 | Send returned 0 bytes |
| `HTTP-E-TIMEOUT` | 4 | Empty response (recv loop timed out) |
| `HTTP-E-PARSE` | 5 | Response headers malformed |
| `HTTP-E-OVERFLOW` | 6 | Buffer overflow |
| `HTTP-E-TLS` | 7 | TLS decrypt error (recv returned -1) |
| `HTTP-E-REDIRECT` | 8 | Too many redirects |

### Words

```forth
HTTP-FAIL       ( code -- )   \ Store error code
HTTP-OK?        ( -- flag )   \ True if no error pending
HTTP-CLEAR-ERR  ( -- )        \ Reset error state
```

---

## Layer 0 — Connection Abstraction

Dispatches to `TCP-*` or `TLS-*` KDOS syscalls based on a `tls?` flag.
TLS connections copy the hostname to `TLS-SNI-HOST` / `TLS-SNI-LEN`
before calling `TLS-CONNECT`.

### HTTP-CONNECT

```forth
HTTP-CONNECT  ( host-a host-u port tls? -- ctx | 0 )
```

1. Saves `tls?` in `_HTTP-TLS`
2. Resolves hostname via `DNS-RESOLVE` → `HTTP-E-DNS` on failure
3. Calls `TCP-CONNECT` or `TLS-CONNECT` (with SNI setup)
4. For plaintext TCP, polls 200× for handshake completion
5. Returns connection context (stored in `_HTTP-CTX`) or 0

### HTTP-DISCONNECT

```forth
HTTP-DISCONNECT  ( -- )
```

Close the active connection via `TCP-CLOSE` or `TLS-CLOSE`.

### HTTP-SEND / HTTP-RECV

```forth
HTTP-SEND  ( buf len -- flag )
HTTP-RECV  ( buf max -- n )
```

Send/receive through the active connection.  Dispatch to
`TCP-SEND`/`TCP-RECV` or `TLS-SEND`/`TLS-RECV` based on `_HTTP-TLS`.

---

## Layer 1 — Receive Loop

### HTTP-USE-STATIC

```forth
HTTP-USE-STATIC  ( addr max -- )
```

Set the receive buffer.  `addr` is the buffer address, `max` is its
capacity.  Also resets `HTTP-RECV-LEN` to 0.

### HTTP-RECV-LOOP

```forth
HTTP-RECV-LOOP  ( -- )
```

Receive the full response into `HTTP-RECV-BUF`:

1. Polls up to 500 iterations with `TCP-POLL` + `NET-IDLE`
2. Each iteration calls `HTTP-RECV` into the buffer tail
3. Stops when buffer is full, 10 consecutive empty reads occur,
   or a TLS decrypt error (-1) is returned

After completion, `HTTP-RECV-LEN` holds the total bytes received.

### Variables

| Word | Purpose |
|---|---|
| `HTTP-RECV-BUF` | Pointer to receive buffer |
| `HTTP-RECV-LEN` | Bytes received so far |
| `HTTP-RECV-MAX` | Buffer capacity |

---

## Layer 2 — Response Processing

### HTTP-PARSE

```forth
HTTP-PARSE  ( -- ior )
```

Parse the received response in `HTTP-RECV-BUF`:

1. Extract status code → `HTTP-STATUS`
2. Find header/body boundary (`\r\n\r\n`) → `_HTTP-HEND-OFF`
3. Set `HTTP-BODY-ADDR` / `HTTP-BODY-LEN`
4. If `Content-Length` is present, clamp body length

Returns 0 on success, -1 on error (sets `HTTP-ERR`).

### Result Variables

| Word | Purpose |
|---|---|
| `HTTP-STATUS` | 3-digit HTTP status code |
| `HTTP-BODY-ADDR` | Address of response body |
| `HTTP-BODY-LEN` | Length of response body |

### HTTP-DECHUNK

```forth
HTTP-DECHUNK  ( addr len -- addr' len' )
```

Decode HTTP chunked transfer encoding **in place**.  Reads
`<hex-size>\r\n<data>\r\n` frames and compacts data into the front
of the same buffer.  Returns the address and length of the
dechunked result.

Handles:
- Hex sizes with uppercase (A–F) and lowercase (a–f) digits
- Multi-digit sizes (e.g., `1F` = 31 bytes)
- Final `0\r\n\r\n` terminator
- Empty body (`0\r\n\r\n` → 0 bytes)

### HTTP-HEADER

```forth
HTTP-HEADER  ( name-a name-u -- val-a val-u flag )
```

Look up a response header by name (case-insensitive) from the last
parsed response.  Delegates to `HDR-FIND` over the header portion of
`HTTP-RECV-BUF`.

---

## Layer 3 — Request Execution

### HTTP-REQUEST

```forth
HTTP-REQUEST  ( method-a method-u url-a url-u -- ior )
```

Full request cycle:

1. `URL-PARSE` the URL
2. `HTTP-CONNECT` (TLS if scheme is HTTPS, FTPS, or WSS)
3. Build request headers: method + path + Host + Connection: close + User-Agent
4. `HTTP-SEND` the request
5. `HTTP-RECV-LOOP` to receive the response
6. `HTTP-DISCONNECT`
7. `HTTP-PARSE` the response

Returns 0 on success.  After success, `HTTP-STATUS`, `HTTP-BODY-ADDR`,
and `HTTP-BODY-LEN` are set.

### HTTP-GET

```forth
HTTP-GET  ( url-a url-u -- body-a body-u | 0 0 )
```

Convenience wrapper: perform a GET request and return the response body
(or `0 0` on failure).

```forth
S" http://example.com/data" HTTP-GET
DUP IF TYPE ELSE 2DROP ." failed" THEN
```

### HTTP-POST / HTTP-POST-JSON

```forth
HTTP-POST       ( url-a url-u body-a body-u ct-a ct-u -- resp-a resp-u | 0 0 )
HTTP-POST-JSON  ( url-a url-u json-a json-u -- resp-a resp-u | 0 0 )
```

POST with an explicit Content-Type, or with `application/json`.
Sends Content-Length, the body, and returns the response body.

```forth
S" https://api.example.com/v1/items"
S" {\"name\":\"test\"}"
HTTP-POST-JSON
DUP IF TYPE ELSE 2DROP ." failed" THEN
```

---

## Layer 4 — Session Headers

Persistent headers that are applied to every request when
`HTTP-APPLY-SESSION` is called during request building.

### HTTP-SET-BEARER / HTTP-CLEAR-BEARER

```forth
HTTP-SET-BEARER    ( token-a token-u -- )   \ Store bearer token (max 255 chars)
HTTP-CLEAR-BEARER  ( -- )                   \ Clear stored token
```

### HTTP-SET-UA

```forth
HTTP-SET-UA  ( ua-a ua-u -- )   \ Store custom User-Agent (max 63 chars)
```

### HTTP-APPLY-SESSION

```forth
HTTP-APPLY-SESSION  ( -- )
```

Append stored session headers (bearer token, user-agent) to the
current header build.  Call between `HDR-RESET`/method and `HDR-END`.

---

## Layer 5 — DNS Cache

An 8-slot hostname → IP cache to avoid repeated DNS lookups.

### HTTP-DNS-LOOKUP

```forth
HTTP-DNS-LOOKUP  ( host-a host-u -- ip | 0 )
```

Check the cache first.  On miss, call `DNS-RESOLVE` and store the
result in slot 0.  Returns the IP address or 0 on failure.

### HTTP-DNS-FLUSH

```forth
HTTP-DNS-FLUSH  ( -- )
```

Clear all 8 cache slots.

---

## Layer 6 — Redirect Detection

### Variables

| Word | Default | Purpose |
|---|---|---|
| `HTTP-MAX-REDIRECTS` | 5 | Maximum redirect hops |
| `HTTP-FOLLOW?` | -1 (true) | Whether to follow redirects |

### _HTTP-REDIRECT?

```forth
_HTTP-REDIRECT?  ( -- flag )
```

Returns true if `HTTP-STATUS` is 301, 302, 307, or 308.

> **Note:** Automatic redirect following is not yet implemented in
> `HTTP-REQUEST`.  Callers can check `_HTTP-REDIRECT?` after a request
> and re-issue with the `Location` header value.

---

## Quick Reference

| Word | Stack | Layer |
|---|---|---|
| `HTTP-CONNECT` | `( host-a host-u port tls? -- ctx \| 0 )` | 0 |
| `HTTP-DISCONNECT` | `( -- )` | 0 |
| `HTTP-SEND` | `( buf len -- flag )` | 0 |
| `HTTP-RECV` | `( buf max -- n )` | 0 |
| `HTTP-USE-STATIC` | `( addr max -- )` | 1 |
| `HTTP-RECV-LOOP` | `( -- )` | 1 |
| `HTTP-PARSE` | `( -- ior )` | 2 |
| `HTTP-DECHUNK` | `( addr len -- addr' len' )` | 2 |
| `HTTP-HEADER` | `( name-a name-u -- val-a val-u flag )` | 2 |
| `HTTP-REQUEST` | `( method-a method-u url-a url-u -- ior )` | 3 |
| `HTTP-GET` | `( url-a url-u -- body-a body-u )` | 3 |
| `HTTP-POST` | `( url-a url-u body-a body-u ct-a ct-u -- resp )` | 3 |
| `HTTP-POST-JSON` | `( url-a url-u json-a json-u -- resp )` | 3 |
| `HTTP-SET-BEARER` | `( token-a token-u -- )` | 4 |
| `HTTP-CLEAR-BEARER` | `( -- )` | 4 |
| `HTTP-SET-UA` | `( ua-a ua-u -- )` | 4 |
| `HTTP-APPLY-SESSION` | `( -- )` | 4 |
| `HTTP-DNS-LOOKUP` | `( host-a host-u -- ip \| 0 )` | 5 |
| `HTTP-DNS-FLUSH` | `( -- )` | 5 |
| `HTTP-MAX-REDIRECTS` | VARIABLE (default: 5) | 6 |
| `HTTP-FOLLOW?` | VARIABLE (default: true) | 6 |

---

## Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `_HTTP-CTX` | VARIABLE | Active connection handle |
| `_HTTP-TLS` | VARIABLE | TLS flag (-1 or 0) |
| `_HTTP-LPORT` | VARIABLE | Local port counter |
| `_HTTP-NEXT-PORT` | `( -- port )` | Allocate next ephemeral port |
| `_HTTP-HEND-OFF` | VARIABLE | Header/body boundary offset |
| `_HTTP-REDIRECT?` | `( -- flag )` | Check if status is 3xx redirect |
| `_HDC-HEX` | `( -- n )` | Parse hex chunk size |
| `_DNS-MATCH?` | `( host-a host-u slot -- flag )` | Compare host to cache slot |
| `_DNS-SLOT-HOST` | `( n -- addr )` | Address of cache slot's host buffer |

---

## Cookbook

### Simple GET request

```forth
CREATE _BUF 32768 ALLOT
_BUF 32768 HTTP-USE-STATIC
S" http://example.com/" HTTP-GET
DUP IF TYPE ELSE 2DROP ." request failed" THEN
```

### POST JSON to an API

```forth
_BUF 32768 HTTP-USE-STATIC
S" https://api.example.com/items"
S" {\"name\":\"widget\",\"qty\":5}"
HTTP-POST-JSON
DUP IF
    ." Response: " TYPE CR
ELSE
    2DROP ." POST failed, error: " HTTP-ERR @ . CR
THEN
```

### Parse and dechunk a response manually

```forth
_BUF 32768 HTTP-USE-STATIC
S" GET" S" http://example.com/chunked" HTTP-REQUEST DROP
HTTP-STATUS @ . CR                       \ 200
HTTP-RECV-BUF @ HTTP-RECV-LEN @
HDR-CHUNKED? IF
    HTTP-BODY-ADDR @ HTTP-BODY-LEN @
    HTTP-DECHUNK TYPE                    \ print dechunked body
ELSE
    HTTP-BODY-ADDR @ HTTP-BODY-LEN @ TYPE
THEN
```

### Use session headers

```forth
S" eyJhbGciOiJIUzI1NiJ9..." HTTP-SET-BEARER
S" KDOS-Bot/1.0" HTTP-SET-UA

HDR-RESET
S" /api/me" HDR-GET
S" api.example.com" HDR-HOST
HTTP-APPLY-SESSION        \ adds Authorization + User-Agent
HDR-CONNECTION-CLOSE
HDR-END
HDR-RESULT TYPE
```

### Check for redirects

```forth
_BUF 32768 HTTP-USE-STATIC
S" GET" S" http://example.com/old" HTTP-REQUEST DROP
_HTTP-REDIRECT? IF
    ." Redirected to: "
    S" Location" HTTP-HEADER IF TYPE CR ELSE 2DROP THEN
THEN
```
