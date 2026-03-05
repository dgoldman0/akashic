# akashic-web-middleware — Before/After Hooks for KDOS / Megapad-64

Middleware wraps the router dispatch with pre- and post-processing.
Each middleware receives a `next-xt` on the stack, calls it to
continue the chain, and can short-circuit by not calling it.

Chain is built at startup via `MW-USE`, executed per-request
via `MW-RUN`.  Innermost "next" is `ROUTE-DISPATCH`.

```forth
REQUIRE web/middleware.f
```

`PROVIDED akashic-web-middleware` — safe to include multiple times.

### Dependencies

```
web/middleware.f
├── web/request.f    (akashic-web-request)
├── web/response.f   (akashic-web-response)
├── web/router.f     (akashic-web-router)
├── utils/datetime.f (akashic-datetime)
├── utils/string.f   (akashic-string)
└── net/base64.f     (akashic-base64)
```

---

## Table of Contents

- [Design Principles](#design-principles)
- [Middleware Signature](#middleware-signature)
- [Layer 0 — Middleware Chain](#layer-0--middleware-chain)
  - [MW-USE](#mw-use)
  - [MW-CLEAR](#mw-clear)
  - [MW-RUN](#mw-run)
- [Layer 1 — Built-in Middleware](#layer-1--built-in-middleware)
  - [MW-LOG](#mw-log)
  - [MW-CORS](#mw-cors)
  - [MW-JSON-BODY](#mw-json-body)
- [Layer 2 — Built-in Middleware](#layer-2--built-in-middleware)
  - [MW-BASIC-AUTH](#mw-basic-auth)
  - [MW-STATIC](#mw-static)
- [Integration with server.f](#integration-with-serverf)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **next-xt pattern** | Each middleware is `( next-xt -- )`.  Call `EXECUTE` on next-xt to pass control down.  Don't call it to short-circuit (e.g., return 401). |
| **FIFO ordering** | Middleware executes in registration order.  First registered = outermost wrapper. |
| **Static chain** | The chain is built at startup, not per-request.  Up to 16 middleware slots. |
| **Composable** | Middleware can set headers, modify state, validate input, log, and delegate normally — all using existing `REQ-*` and `RESP-*` words. |

---

## Middleware Signature

Every middleware word has the same stack effect:

```
( next-xt -- )
```

The middleware does pre-processing, calls `next-xt` via `EXECUTE`,
then does post-processing.  To short-circuit (e.g., error response),
simply `DROP` the next-xt and send a response directly.

```forth
: my-auth  ( next-xt -- )
    REQ-AUTH NIP 0= IF
        DROP                        \ don't call next
        401 RESP-ERROR              \ send 401 directly
    ELSE
        EXECUTE                     \ continue chain
    THEN ;
```

---

## Layer 0 — Middleware Chain

### MW-USE

```
MW-USE ( xt -- )
```

Add a middleware to the chain.  Middleware executes in
registration order (FIFO).  Maximum 16 entries.

```forth
' MW-LOG  MW-USE    \ first to run (outermost)
' MW-CORS MW-USE    \ second to run
' my-auth MW-USE    \ third to run (innermost before dispatch)
```

### MW-CLEAR

```
MW-CLEAR ( -- )
```

Remove all middleware from the chain.

### MW-RUN

```
MW-RUN ( -- )
```

Execute the full middleware chain, ending with `ROUTE-DISPATCH`
as the innermost "next".  If no middleware is registered,
calls `ROUTE-DISPATCH` directly.

**This is the word you pass to `SRV-SET-DISPATCH`:**

```forth
' MW-RUN SRV-SET-DISPATCH
```

---

## Layer 1 — Built-in Middleware

### MW-LOG

```
MW-LOG ( next-xt -- )
```

Timestamped request logging.  Prints after the handler completes:

```
[1772043151] GET /api/status -> 200 (4 ms)
```

Records `DT-NOW-MS` before calling next, computes elapsed time after.
Uses `_RESP-CODE @` to read the response status code.

### MW-CORS

```
MW-CORS ( next-xt -- )
```

Permissive CORS headers.  Two behaviors:

| Request | Action |
|---|---|
| `OPTIONS` (preflight) | Drop next-xt, send 204 with CORS headers, skip handler. |
| Any other method | Add CORS headers via `RESP-CORS`, then call next. |

Headers added:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

### MW-JSON-BODY

```
MW-JSON-BODY ( next-xt -- )
```

Content-Type enforcement for JSON endpoints:

| Condition | Action |
|---|---|
| No Content-Type header | Call next (pass through). |
| Content-Type starts with `application/json` but body is empty | Drop next-xt, send 400 Bad Request. |
| Content-Type starts with `application/json` and body present | Call next. |
| Content-Type is something else | Call next (pass through). |

---

## Layer 2 — Built-in Middleware

### MW-BASIC-AUTH

HTTP Basic Authentication (RFC 7617).

#### MW-BASIC-AUTH-SET

```
MW-BASIC-AUTH-SET ( user-a user-u pass-a pass-u -- )
```

Store the expected username and password.  Must be called before
registering `MW-BASIC-AUTH` via `MW-USE`.

```forth
S" admin" S" secret" MW-BASIC-AUTH-SET
```

#### MW-BASIC-AUTH

```
MW-BASIC-AUTH ( next-xt -- )
```

Validates the `Authorization` header against stored credentials:

| Condition | Action |
|---|---|
| No `Authorization` header | 401 Unauthorized + `WWW-Authenticate: Basic realm="Akashic"` |
| Scheme is not `Basic` | 403 Forbidden |
| Credentials decode but don't match | 403 Forbidden |
| Credentials match | Call next (authenticated) |

**Decoding flow:** strips `Basic ` prefix → Base64-decodes →
splits on `:` → compares username and password via `STR-STR=`.

```forth
\ Setup
S" admin" S" secret" MW-BASIC-AUTH-SET
' MW-BASIC-AUTH MW-USE
```

**Tip:** Place `MW-CORS` before `MW-BASIC-AUTH` so that `OPTIONS`
preflight requests bypass authentication:

```forth
' MW-CORS       MW-USE    \ handles OPTIONS → 204
' MW-BASIC-AUTH MW-USE    \ checks credentials for other methods
```

### MW-STATIC

Serve static files from the KDOS filesystem.

#### MW-STATIC-SET

```
MW-STATIC-SET ( pfx-a pfx-u -- )
```

Set the URL prefix that triggers static file serving.

```forth
S" /static/" MW-STATIC-SET
```

#### MW-STATIC

```
MW-STATIC ( next-xt -- )
```

If the request path starts with the configured prefix, strip the
prefix, look up the remaining filename in the KDOS filesystem,
detect MIME type from the file extension, and serve the content.

| Condition | Action |
|---|---|
| Not configured (`MW-STATIC-SET` not called) | Call next |
| Path doesn't start with prefix | Call next |
| Filename empty after stripping prefix | Call next |
| File not found in FS (or FS not loaded) | Call next |
| File found | 200 + detected Content-Type + file body |

**MIME type detection** via `_MW-STATIC-MIME`:

| Extension | Content-Type |
|---|---|
| `html`, `htm` | `text/html` |
| `css` | `text/css` |
| `js` | `application/javascript` |
| `json` | `application/json` |
| `txt` | `text/plain` |
| `png` | `image/png` |
| Unknown | `application/octet-stream` |

**Requires** `FS-LOAD` to have been called (filesystem mounted).
Maximum file read per request: 4096 bytes.

```forth
S" /static/" MW-STATIC-SET
' MW-STATIC MW-USE
```

---

## Integration with server.f

By default, `server.f` dispatches directly to `ROUTE-DISPATCH`.
To enable middleware, replace the dispatch hook:

```forth
\ Register middleware
MW-CLEAR
' MW-LOG  MW-USE
' MW-CORS MW-USE

\ Wire into server
' MW-RUN SRV-SET-DISPATCH

\ Start server
8080 SERVE
```

The execution flow becomes:

```
SRV-HANDLE
  └─ _SRV-DISPATCH-XT @ EXECUTE   (= MW-RUN)
       └─ MW-LOG
            └─ MW-CORS
                 └─ ROUTE-DISPATCH
                      └─ handler xt
```

---

## Quick Reference

| Word | Stack | Purpose |
|---|---|---|
| `MW-USE` | `( xt -- )` | Add middleware to chain |
| `MW-CLEAR` | `( -- )` | Remove all middleware |
| `MW-RUN` | `( -- )` | Execute chain → `ROUTE-DISPATCH` |
| `MW-LOG` | `( next-xt -- )` | Timestamped request logging |
| `MW-CORS` | `( next-xt -- )` | Permissive CORS headers |
| `MW-JSON-BODY` | `( next-xt -- )` | JSON Content-Type enforcement |
| `MW-BASIC-AUTH-SET` | `( user-a user-u pass-a pass-u -- )` | Store auth credentials |
| `MW-BASIC-AUTH` | `( next-xt -- )` | HTTP Basic authentication |
| `MW-STATIC-SET` | `( pfx-a pfx-u -- )` | Set static-file URL prefix |
| `MW-STATIC` | `( next-xt -- )` | Serve static files from FS |

---

## Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `_MW-CHAIN` | CREATE 128 | Array of 16 middleware xts (16 × 8 bytes) |
| `_MW-COUNT` | VARIABLE | Number of registered middleware |
| `_MW-MAX` | CONSTANT 16 | Maximum middleware slots |
| `_MW-NEXT-IDX` | VARIABLE | Current chain index (for `_MW-NEXT`) |
| `_MW-NEXT` | `( -- )` | Trampoline: calls `_MW-RUN-FROM` with next index |
| `_MW-RUN-FROM` | `( idx -- )` | Execute chain from index; falls through to `ROUTE-DISPATCH` |
| `_MW-RUN-FROM-XT` | VARIABLE | Vectored reference to `_MW-RUN-FROM` (breaks forward ref cycle) |
| `_MW-LOG-T0` | VARIABLE | Start time for `MW-LOG` elapsed calculation |
| `_MW-CT-JSON` | CREATE 16 | Byte array for `"application/json"` string |
| `_MW-AUTH-USER-A/U` | VARIABLE × 2 | Expected username (addr, len) |
| `_MW-AUTH-PASS-A/U` | VARIABLE × 2 | Expected password (addr, len) |
| `_MW-AUTH-DEC-BUF` | CREATE 256 | Decoded Base64 buffer |
| `_MW-AUTH-PFX` | CREATE 6 | Byte array `"Basic "` |
| `_MW-AUTH-REALM` | CREATE 22 | Byte array `Basic realm="Akashic"` |
| `_MW-AUTH-CHECK` | `( auth-a auth-u -- flag )` | Decode + compare credentials |
| `_MW-STATIC-PFX-A/U` | VARIABLE × 2 | URL prefix (addr, len) |
| `_MW-STATIC-READ-BUF` | CREATE 4096 | File read buffer |
| `_MW-SOPEN` | `( addr len -- fdesc \| 0 )` | Stack-based file open via NAMEBUF |
| `_MW-STATIC-EXT` | `( path-a path-u -- ext-a ext-u )` | Extract file extension |
| `_MW-STATIC-MIME` | `( ext-a ext-u -- mime-a mime-u )` | Extension → MIME type |

---

## Cookbook

### Basic logging + CORS setup

```forth
REQUIRE web/middleware.f

MW-CLEAR
' MW-LOG  MW-USE
' MW-CORS MW-USE
' MW-RUN SRV-SET-DISPATCH

8080 SERVE
```

### Custom authentication middleware

```forth
: mw-api-key  ( next-xt -- )
    S" X-Api-Key" REQ-HEADER NIP 0= IF
        DROP
        401 RESP-ERROR
    ELSE
        EXECUTE
    THEN ;

' mw-api-key MW-USE
```

### Rate-aware middleware (conceptual)

```forth
: mw-slow-down  ( next-xt -- )
    \ Add a delay header for visibility
    S" X-Handled-By" S" Megapad-64" RESP-HEADER
    EXECUTE ;

' mw-slow-down MW-USE
```

### Short-circuit with redirect

```forth
: mw-force-login  ( next-xt -- )
    REQ-PATH S" /login" STR-STR= IF
        EXECUTE                           \ let /login through
    ELSE
        REQ-COOKIE NIP 0= IF
            DROP                          \ skip handler
            302 S" /login" RESP-REDIRECT  \ redirect
        ELSE
            EXECUTE                       \ authenticated
        THEN
    THEN ;
```

### Ordering matters

```forth
\ MW-LOG should be outermost to capture the final status code
' MW-LOG      MW-USE    \ 1st: logs everything including auth failures
' MW-CORS     MW-USE    \ 2nd: adds CORS before auth check
' mw-api-key  MW-USE    \ 3rd: rejects before handler runs

\ Execution order: LOG → CORS → API-KEY → ROUTE-DISPATCH → handler
\ Return order:    handler → API-KEY → CORS → LOG (logs status)
```

### Protected API with Basic auth

```forth
S" admin" S" secret" MW-BASIC-AUTH-SET

MW-CLEAR
' MW-LOG        MW-USE
' MW-CORS       MW-USE    \ OPTIONS preflight bypasses auth
' MW-BASIC-AUTH MW-USE
' MW-RUN SRV-SET-DISPATCH

8080 SERVE
```

### Static files + API routes

```forth
S" /static/" MW-STATIC-SET

MW-CLEAR
' MW-LOG    MW-USE
' MW-CORS   MW-USE
' MW-STATIC MW-USE    \ serves /static/style.css, /static/app.js, etc.
' MW-RUN SRV-SET-DISPATCH

\ API routes
S" GET" S" /api/status" ['] handle-status ROUTE
8080 SERVE
```

### Full stack: logging + CORS + auth + static files

```forth
S" admin" S" secret" MW-BASIC-AUTH-SET
S" /public/" MW-STATIC-SET

MW-CLEAR
' MW-LOG        MW-USE    \ outermost: logs every request
' MW-CORS       MW-USE    \ CORS headers + preflight
' MW-STATIC     MW-USE    \ /public/* served without auth
' MW-BASIC-AUTH MW-USE    \ everything else requires auth
' MW-RUN SRV-SET-DISPATCH

\ Execution order:
\   LOG → CORS → STATIC → BASIC-AUTH → ROUTE-DISPATCH
```
