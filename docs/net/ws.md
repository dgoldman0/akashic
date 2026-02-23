# akashic-websocket — WebSocket Client for KDOS / Megapad-64

A WebSocket client implementing RFC 6455 for real-time bidirectional
communication.  Uses HTTP for the upgrade handshake, then switches to
framed mode with masking, fragment reassembly, and auto-pong.

```forth
REQUIRE ws.f
```

`PROVIDED akashic-websocket` — safe to include multiple times.

### Dependencies

```
ws.f
├── http.f      (akashic-http)
│   ├── url.f       (akashic-url)
│   └── headers.f   (akashic-http-headers)
└── base64.f    (akashic-base64)   [via http.f chain]
```

The SHA-1 implementation is self-contained within ws.f (KDOS only
provides SHA-256 and SHA-3; RFC 6455 mandates SHA-1 for
`Sec-WebSocket-Accept` validation).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Opcode Constants](#opcode-constants)
- [Connection State](#connection-state)
- [SHA-1 (Internal)](#sha-1-internal)
- [Layer 0 — Handshake](#layer-0--handshake)
  - [WS-CONNECT](#ws-connect)
  - [WS-DISCONNECT](#ws-disconnect)
- [Layer 1 — Frame Encoding/Decoding](#layer-1--frame-encodingdecoding)
  - [WS-FRAME-SEND](#ws-frame-send)
  - [WS-FRAME-RECV](#ws-frame-recv)
- [Layer 2 — High-Level API](#layer-2--high-level-api)
  - [WS-SEND-TEXT / WS-SEND-BINARY](#ws-send-text--ws-send-binary)
  - [WS-RECV](#ws-recv)
  - [WS-PING / WS-PONG](#ws-ping--ws-pong)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Layered** | Layer 0 (handshake) → Layer 1 (framing) → Layer 2 (high-level API).  Each layer is independently testable. |
| **Always masked** | Client-to-server frames are always masked per RFC 6455 §5.3. |
| **Auto-pong** | Incoming PING frames are automatically answered with PONG by default (`WS-AUTO-PONG`). |
| **Variable-based state** | All multi-step operations use `VARIABLE` accumulators.  No deep stack gymnastics. |
| **Reuses http.f** | TCP/TLS connection, header building, and send/recv all delegate to `akashic-http`. |
| **Minimal SHA-1** | A 2-block SHA-1 implementation is included (≤ 119 bytes input) — only used for handshake validation. |

---

## Error Handling

### Variables

| Word | Stack | Purpose |
|---|---|---|
| `WS-ERR` | VARIABLE | Last error code (0 = no error) |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `WS-E-CONNECT` | 1 | URL parse failed or TCP/TLS connect returned 0 |
| `WS-E-HANDSHAKE` | 2 | Upgrade request failed, non-101 response, or bad `Sec-WebSocket-Accept` |
| `WS-E-OVERFLOW` | 3 | Buffer overflow |
| `WS-E-FRAME` | 4 | Malformed frame |
| `WS-E-CLOSED` | 5 | Connection already closed |
| `WS-E-PROTOCOL` | 6 | Protocol violation |

### Words

```forth
WS-FAIL       ( code -- )   \ Store error code
WS-OK?        ( -- flag )   \ True if no error pending
WS-CLEAR-ERR  ( -- )        \ Reset error state
```

---

## Opcode Constants

| Constant | Value | Meaning |
|---|---|---|
| `WS-OP-CONT` | 0 | Continuation frame |
| `WS-OP-TEXT` | 1 | Text frame (UTF-8) |
| `WS-OP-BINARY` | 2 | Binary frame |
| `WS-OP-CLOSE` | 8 | Close frame |
| `WS-OP-PING` | 9 | Ping frame |
| `WS-OP-PONG` | 10 | Pong frame |

---

## Connection State

| Word | Type | Purpose |
|---|---|---|
| `_WS-CTX` | VARIABLE | Underlying TCP/TLS connection context |
| `_WS-TLS` | VARIABLE | -1 if TLS, 0 if plain TCP |
| `_WS-OPEN` | VARIABLE | -1 if connected, 0 if closed |
| `WS-AUTO-PONG` | VARIABLE | -1 = auto-reply to pings (default) |

---

## SHA-1 (Internal)

A minimal SHA-1 implementation (RFC 3174) included for the sole purpose
of computing `Sec-WebSocket-Accept = Base64(SHA-1(key + GUID))`.

Supports inputs up to 119 bytes (2 × 64-byte blocks).  Not intended for
general cryptographic use.

### Key Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `SHA1` | `( src len dst -- )` | Hash `len` bytes at `src`, write 20-byte digest to `dst` |
| `_SHA1-ROTL` | `( x n -- x' )` | 32-bit left rotate (masked for 64-bit cells) |
| `_SHA1-BE@` | `( addr -- u32 )` | Load big-endian 32-bit word |
| `_SHA1-BE!` | `( u32 addr -- )` | Store big-endian 32-bit word |
| `_SHA1-BLOCK` | `( blk-addr -- )` | Process one 64-byte block through 80 rounds |
| `_SHA1-F` | `( t b c d -- result )` | Round function f(t, b, c, d) |
| `_SHA1-K` | `( t -- k )` | Round constant K(t) |

---

## Layer 0 — Handshake

### WS-CONNECT

```forth
WS-CONNECT  ( url-a url-u -- ctx | 0 )
```

Full WebSocket connection sequence:

1. `URL-PARSE` — expects `ws://` or `wss://` scheme
2. `HTTP-CONNECT` — TCP (port 80) or TLS (port 443)
3. Generates 16-byte random nonce → Base64 `Sec-WebSocket-Key`
4. Sends HTTP Upgrade request with required headers:
   - `Upgrade: websocket`
   - `Connection: Upgrade`
   - `Sec-WebSocket-Version: 13`
   - `Sec-WebSocket-Key: <base64-key>`
5. Receives response, verifies HTTP 101 status
6. Validates `Sec-WebSocket-Accept` header via SHA-1 + Base64
7. Returns connection context or 0 on failure (sets `WS-ERR`)

### WS-DISCONNECT

```forth
WS-DISCONNECT  ( ctx -- )
```

Sends a close frame (opcode 8, empty payload), clears `_WS-OPEN`,
then calls `HTTP-DISCONNECT` to tear down the TCP/TLS connection.

---

## Layer 1 — Frame Encoding/Decoding

### WS-FRAME-SEND

```forth
WS-FRAME-SEND  ( ctx opcode payload-a payload-u -- )
```

Build and send one WebSocket frame:

- Sets FIN bit (all frames are final by default)
- Client frames are always masked (RFC 6455 §5.3)
- Generates a random 4-byte mask key via `RANDOM`
- Supports 7-bit, 16-bit (126), and 64-bit (127) length encodings
- Masks payload in place, then sends via `HTTP-SEND`

### WS-FRAME-RECV

```forth
WS-FRAME-RECV  ( ctx buf max -- opcode payload-a payload-u | -1 0 0 )
```

Receive and decode one frame:

- Reads 2-byte header, determines opcode and FIN flag
- Handles extended length (16-bit and 64-bit)
- Reads optional mask key, reads payload into caller's buffer
- Unmasks payload if server sent masked frames
- Auto-pong: if opcode is PING and `WS-AUTO-PONG` is set, automatically
  sends a PONG with the same payload
- Returns -1 on error/closed connection

### _WS-MASK

```forth
_WS-MASK  ( data-a data-u mask -- )
```

XOR-mask data in place with a 4-byte rotating key.  Mask bytes are in
network byte order (MSB first): `byte[i] XOR key>>(24 - 8*(i%4))`.

---

## Layer 2 — High-Level API

### WS-SEND-TEXT / WS-SEND-BINARY

```forth
WS-SEND-TEXT    ( ctx text-a text-u -- )
WS-SEND-BINARY  ( ctx data-a data-u -- )
```

Send a complete text or binary message (single frame, FIN=1).

### WS-RECV

```forth
WS-RECV  ( ctx buf max -- opcode len )
```

Receive the next complete message, reassembling continuation frames:

1. Receives first frame, records opcode
2. If FIN is set, returns immediately
3. Otherwise loops on continuation frames, appending to buffer
4. Returns opcode (1=text, 2=binary) and total length
5. Returns -1 on close frame or error

### WS-PING / WS-PONG

```forth
WS-PING  ( ctx -- )
WS-PONG  ( ctx payload-a payload-u -- )
```

`WS-PING` sends a ping frame with empty payload.
`WS-PONG` sends a pong frame echoing the given payload.

---

## Quick Reference

| Word | Stack Effect | Layer |
|---|---|---|
| `WS-ERR` | VARIABLE | Error |
| `WS-FAIL` | `( code -- )` | Error |
| `WS-OK?` | `( -- flag )` | Error |
| `WS-CLEAR-ERR` | `( -- )` | Error |
| `WS-CONNECT` | `( url-a url-u -- ctx \| 0 )` | 0 |
| `WS-DISCONNECT` | `( ctx -- )` | 0 |
| `WS-FRAME-SEND` | `( ctx opcode payload-a payload-u -- )` | 1 |
| `WS-FRAME-RECV` | `( ctx buf max -- op addr u \| -1 0 0 )` | 1 |
| `WS-SEND-TEXT` | `( ctx text-a text-u -- )` | 2 |
| `WS-SEND-BINARY` | `( ctx data-a data-u -- )` | 2 |
| `WS-RECV` | `( ctx buf max -- opcode len )` | 2 |
| `WS-PING` | `( ctx -- )` | 2 |
| `WS-PONG` | `( ctx payload-a payload-u -- )` | 2 |
| `WS-AUTO-PONG` | VARIABLE (default: -1) | Config |

---

## Internal Words

| Word | Stack Effect | Purpose |
|---|---|---|
| `_WS-CTX` | VARIABLE | TCP/TLS context handle |
| `_WS-TLS` | VARIABLE | TLS flag |
| `_WS-OPEN` | VARIABLE | Connection open flag |
| `_WS-MAKE-KEY` | `( -- addr len )` | Generate Base64-encoded 16-byte random key |
| `_WS-VALIDATE` | `( hdr-a hdr-u key-a key-u -- flag )` | Validate `Sec-WebSocket-Accept` |
| `_WS-MASK` | `( data-a data-u mask -- )` | XOR-mask in place |
| `_WS-RECV-BYTES` | `( buf max -- n )` | Blocking receive of exactly `max` bytes |
| `SHA1` | `( src len dst -- )` | SHA-1 hash (≤ 119 bytes input) |
| `_SHA1-ROTL` | `( x n -- x' )` | 32-bit left rotate |
| `_SHA1-BE@` | `( addr -- u32 )` | Big-endian 32-bit load |
| `_SHA1-BE!` | `( u32 addr -- )` | Big-endian 32-bit store |
| `_SHA1-BLOCK` | `( blk-addr -- )` | Process one SHA-1 block |

---

## Cookbook

### Connect and send a text message

```forth
S" wss://echo.websocket.org/" WS-CONNECT
DUP 0<> IF
    DUP S" Hello, WebSocket!" WS-SEND-TEXT
    DUP PAD 4096 WS-RECV        \ ( opcode len )
    SWAP 1 = IF
        PAD SWAP TYPE CR         \ print echoed text
    ELSE
        DROP ." binary or error" CR
    THEN
    WS-DISCONNECT
ELSE
    ." connect failed: " WS-ERR @ . CR
THEN
```

### Manual ping

```forth
ctx WS-PING
\ wait for pong (or let WS-AUTO-PONG handle server pings)
```

### Disable auto-pong

```forth
0 WS-AUTO-PONG !
\ Now you must handle WS-OP-PING in your recv loop:
ctx PAD 4096 WS-FRAME-RECV
ROT DUP WS-OP-PING = IF
    DROP ctx ROT ROT WS-PONG
ELSE
    \ handle other opcodes
THEN
```

### Check connection state

```forth
_WS-OPEN @ IF ." connected" ELSE ." closed" THEN CR
```
