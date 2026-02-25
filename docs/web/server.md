# akashic-web-server — HTTP Server Accept Loop for KDOS / Megapad-64

Accept loop, connection handling, and request→dispatch→response
lifecycle.  Ties together `request.f`, `response.f`, and `router.f`
into a runnable HTTP server.

All socket operations are vectored via XT variables so tests can
mock them without real network I/O.

```forth
REQUIRE web/server.f
```

`PROVIDED akashic-web-server` — safe to include multiple times.

### Dependencies

```
web/server.f
├── web/request.f    (akashic-web-request)
├── web/response.f   (akashic-web-response)
├── web/router.f     (akashic-web-router)
├── utils/datetime.f (akashic-datetime)
└── utils/string.f   (akashic-string)
```

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Server State](#server-state)
- [Layer 0 — Vectored Socket Operations](#layer-0--vectored-socket-operations)
- [Layer 1 — Logging](#layer-1--logging)
- [Layer 2 — Socket Setup](#layer-2--socket-setup)
- [Layer 3 — Connection Handling](#layer-3--connection-handling)
- [Layer 4 — Accept Loop](#layer-4--accept-loop)
- [Layer 5 — Lifecycle](#layer-5--lifecycle)
- [Layer 6 — Direct Handle (Testing)](#layer-6--direct-handle-testing)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Vectored I/O** | Every socket call (`SOCKET`, `BIND`, `LISTEN`, `SOCK-ACCEPT`, `RECV`, `CLOSE`, `TCP-POLL`, `NET-IDLE`) goes through an XT variable.  Tests swap in mocks — no network required. |
| **Poll-before-recv** | `RECV` is non-blocking in KDOS.  `SRV-HANDLE` calls `TCP-POLL` in a retry loop before `RECV` to ensure incoming segments are processed. |
| **CATCH around handlers** | Every dispatched handler is wrapped in `CATCH`.  If it throws, the server sends 500 Internal Server Error and continues accepting connections. |
| **Pluggable dispatch** | `_SRV-DISPATCH-XT` defaults to `ROUTE-DISPATCH` but can be replaced with `MW-RUN` (middleware.f) via `SRV-SET-DISPATCH`. |
| **Sequential connections** | Phase 1–3 handles one connection at a time.  With dynamic TCB counts (4–64), keep-alive and multicore dispatch are future options. |

---

## Error Handling

### Variables

| Word | Stack | Purpose |
|---|---|---|
| `SRV-ERR` | VARIABLE | Last error code (0 = no error) |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `SRV-E-SOCKET` | 1 | `SOCKET` call failed |
| `SRV-E-BIND` | 2 | `BIND` failed |
| `SRV-E-LISTEN` | 3 | `LISTEN` failed |
| `SRV-E-RECV` | 4 | `RECV` returned 0 or error |

### Words

```forth
SRV-FAIL       ( code -- )   \ Store error code
SRV-OK?        ( -- flag )   \ True if no error pending
SRV-CLEAR-ERR  ( -- )        \ Reset error state
```

---

## Server State

| Word | Type | Purpose |
|---|---|---|
| `_SRV-SD` | VARIABLE | Listener socket descriptor |
| `_SRV-PORT` | VARIABLE | Listening port number |
| `_SRV-RUNNING` | VARIABLE | Server running flag (−1 = running, 0 = stop) |
| `_SRV-CONN-SD` | VARIABLE | Current accepted connection socket |
| `_SRV-RECV-BUF` | CREATE 8192 | Receive buffer |
| `_SRV-RECV-LEN` | VARIABLE | Bytes received |
| `SRV-MAX-REQUEST` | CONSTANT 8192 | Maximum request size |
| `SRV-TIMEOUT` | CONSTANT 5000 | Receive timeout in ms (future use) |
| `SRV-KEEP-ALIVE?` | VARIABLE | Keep-alive flag (future, default 0) |
| `SRV-LOG-ENABLED` | VARIABLE | Logging flag (default −1 = enabled) |

---

## Layer 0 — Vectored Socket Operations

Each KDOS socket primitive is called through an XT variable.
The default implementation calls the real word; tests override the XT.

| Wrapper | XT Variable | Default | Stack |
|---|---|---|---|
| `_SRV-SOCKET` | `_SRV-SOCKET-XT` | `SOCKET` | `( type -- sd \| -1 )` |
| `_SRV-BIND` | `_SRV-BIND-XT` | `BIND` | `( sd port -- ior )` |
| `_SRV-LISTEN` | `_SRV-LISTEN-XT` | `LISTEN` | `( sd -- ior )` |
| `_SRV-ACCEPT` | `_SRV-ACCEPT-XT` | `SOCK-ACCEPT` | `( sd -- new-sd \| -1 )` |
| `_SRV-RECV` | `_SRV-RECV-XT` | `RECV` | `( sd addr maxlen -- actual )` |
| `_SRV-CLOSE` | `_SRV-CLOSE-XT` | `CLOSE` | `( sd -- )` |
| `_SRV-POLL` | `_SRV-POLL-XT` | `TCP-POLL` | `( -- )` |
| `_SRV-IDLE` | `_SRV-IDLE-XT` | `NET-IDLE` | `( -- )` |

### Overriding for Tests

```forth
\ Mock SOCKET to return a fake sd
: mock-socket  ( type -- sd )  DROP 42 ;
' mock-socket _SRV-SOCKET-XT !
```

---

## Layer 1 — Logging

### SRV-LOG

```
SRV-LOG ( a u -- )
```

Print a timestamped log line to the console.  Respects `SRV-LOG-ENABLED`.

```forth
S" Starting up" SRV-LOG
\ → [2026-02-25T12:34:56] Starting up
```

### SRV-LOG-REQUEST

```
SRV-LOG-REQUEST ( -- )
```

Log the current request method and path.  Called automatically by `SRV-HANDLE`.

```
[2026-02-25T12:34:56] GET /api/status
```

---

## Layer 2 — Socket Setup

### SRV-INIT

```
SRV-INIT ( port -- )
```

Create a TCP listening socket, bind to `port`, start listening.
Sets `_SRV-RUNNING` to −1 on success.  On failure, sets the
appropriate error code and returns.

```forth
8080 SRV-INIT
SRV-OK? IF ." Ready!" ELSE ." Failed." THEN
```

---

## Layer 3 — Connection Handling

### SRV-HANDLE

```
SRV-HANDLE ( sd -- )
```

Handle one accepted connection:

1. Store `sd` in `_SRV-CONN-SD`, reset `REQ-CLEAR` and `RESP-CLEAR`.
2. Set response socket via `RESP-SET-SD`.
3. **Poll-before-recv loop**: call `_SRV-POLL` then `_SRV-RECV` up to
   100 times with `_SRV-IDLE` between attempts.  `RECV` is non-blocking
   in KDOS — this ensures `TCP-POLL` has ingested the data segment
   before reading.
4. `REQ-PARSE` the received data.  On failure → 400 Bad Request.
5. `SRV-LOG-REQUEST`.
6. `_SRV-DISPATCH-XT @ CATCH` — run the handler.  If it throws → 500.
7. `CLOSE` the accepted socket.

### SRV-SET-DISPATCH

```
SRV-SET-DISPATCH ( xt -- )
```

Replace the dispatch hook.  Default is `ROUTE-DISPATCH`.
Set to `MW-RUN` when using middleware:

```forth
' MW-RUN SRV-SET-DISPATCH
```

---

## Layer 4 — Accept Loop

### SRV-LOOP

```
SRV-LOOP ( -- )
```

Main accept loop.  Runs until `_SRV-RUNNING` is cleared (by `SERVE-STOP`).
Each iteration calls `_SRV-ACCEPT` on the listener socket, dispatches
to `SRV-HANDLE` if a connection is accepted, then calls `_SRV-POLL`
and `_SRV-IDLE`.

---

## Layer 5 — Lifecycle

### SERVE

```
SERVE ( port -- )
```

Top-level entry point.  Calls `SRV-INIT`, `SRV-LOOP`, `SRV-CLEANUP`.

```forth
8080 SERVE
\ Listening on :8080
\ (blocks, handling requests until SERVE-STOP is called)
\ Server stopped.
```

### SERVE-STOP

```
SERVE-STOP ( -- )
```

Signal the accept loop to stop.  Can be called from any handler:

```forth
: handle-shutdown  ( -- )
    200 RESP-STATUS S" Shutting down" RESP-TEXT RESP-SEND
    SERVE-STOP ;
S" POST" S" /shutdown" ['] handle-shutdown ROUTE
```

### SRV-CLEANUP

```
SRV-CLEANUP ( -- )
```

Close the listener socket, print "Server stopped." via `SRV-LOG`.

---

## Layer 6 — Direct Handle (Testing)

### SRV-HANDLE-BUF

```
SRV-HANDLE-BUF ( addr len -- )
```

Process a request from a pre-filled buffer.  No socket I/O — useful
for testing the full pipeline (parse → dispatch → response):

```forth
\ Override _RESP-SEND-XT to capture output
: mock-send ( addr len -- ) captured-buf SWAP CMOVE ;
' mock-send _RESP-SEND-XT !

S" GET /hello HTTP/1.1\r\nHost: test\r\n\r\n" SRV-HANDLE-BUF
```

---

## Quick Reference

| Word | Stack | Purpose |
|---|---|---|
| `SERVE` | `( port -- )` | Start server on port (blocks) |
| `SERVE-STOP` | `( -- )` | Signal shutdown |
| `SRV-INIT` | `( port -- )` | Create listener socket |
| `SRV-LOOP` | `( -- )` | Run accept loop |
| `SRV-HANDLE` | `( sd -- )` | Handle one connection |
| `SRV-HANDLE-BUF` | `( a u -- )` | Handle from buffer (testing) |
| `SRV-CLEANUP` | `( -- )` | Close listener, log shutdown |
| `SRV-SET-DISPATCH` | `( xt -- )` | Set dispatch hook |
| `SRV-LOG` | `( a u -- )` | Timestamped log line |
| `SRV-LOG-REQUEST` | `( -- )` | Log current request |
| `SRV-OK?` | `( -- flag )` | Check for errors |
| `SRV-FAIL` | `( code -- )` | Store error code |
| `SRV-CLEAR-ERR` | `( -- )` | Clear error state |

---

## Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `_SRV-SOCKET` | `( type -- sd \| -1 )` | Vectored SOCKET call |
| `_SRV-BIND` | `( sd port -- ior )` | Vectored BIND call |
| `_SRV-LISTEN` | `( sd -- ior )` | Vectored LISTEN call |
| `_SRV-ACCEPT` | `( sd -- new-sd \| -1 )` | Vectored SOCK-ACCEPT call |
| `_SRV-RECV` | `( sd a max -- actual )` | Vectored RECV call |
| `_SRV-CLOSE` | `( sd -- )` | Vectored CLOSE call |
| `_SRV-POLL` | `( -- )` | Vectored TCP-POLL call |
| `_SRV-IDLE` | `( -- )` | Vectored NET-IDLE call |
| `_SRV-SD` | VARIABLE | Listener socket descriptor |
| `_SRV-PORT` | VARIABLE | Listening port |
| `_SRV-RUNNING` | VARIABLE | Running flag |
| `_SRV-CONN-SD` | VARIABLE | Current connection sd |
| `_SRV-RECV-BUF` | CREATE 8192 | Receive buffer |
| `_SRV-RECV-LEN` | VARIABLE | Bytes received |
| `_SRV-DISPATCH-XT` | VARIABLE | Dispatch hook xt |

---

## Cookbook

### Minimal server

```forth
REQUIRE web/server.f
REQUIRE web/router.f
REQUIRE web/response.f

: handle-index  ( -- )
    200 RESP-STATUS S" Hello!" RESP-TEXT RESP-SEND ;

S" GET" S" /" ['] handle-index ROUTE
8080 SERVE
```

### Server with middleware

```forth
REQUIRE web/server.f
REQUIRE web/middleware.f

: handle-api  ( -- )
    200 RESP-STATUS
    S" application/json" RESP-CONTENT-TYPE
    S" {}" RESP-BODY
    RESP-SEND ;

S" GET" S" /api" ['] handle-api ROUTE

' MW-LOG  MW-USE
' MW-CORS MW-USE
' MW-RUN SRV-SET-DISPATCH

8080 SERVE
```

### Graceful shutdown from a handler

```forth
: handle-stop  ( -- )
    200 RESP-STATUS S" Bye" RESP-TEXT RESP-SEND
    SERVE-STOP ;

S" POST" S" /admin/shutdown" ['] handle-stop ROUTE
```

### Testing without network

```forth
\ Set up mock send to capture response
CREATE out-buf 8192 ALLOT
VARIABLE out-len
: mock-send  ( addr len -- )
    DUP out-len +!
    out-buf out-len @ + SWAP - SWAP CMOVE ;
' mock-send _RESP-SEND-XT !

\ Process a fake request
S" GET / HTTP/1.1\r\nHost: test\r\n\r\n" SRV-HANDLE-BUF

\ out-buf now contains the full HTTP response
```
