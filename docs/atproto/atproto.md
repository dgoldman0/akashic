# akashic-atproto — AT Protocol Primitives for KDOS / Megapad-64

AT Protocol identity, record-addressing, XRPC client, session
management, and repository CRUD.  Foundation layer for Bluesky and
any AT Protocol application.

```forth
REQUIRE aturi.f    \ AT URI parser + builder
REQUIRE did.f      \ DID validation + method extraction
REQUIRE tid.f      \ TID generation + comparison
REQUIRE xrpc.f     \ XRPC client (GET/POST) + pagination
REQUIRE session.f  \ Session auth (login/refresh/bearer)
REQUIRE repo.f     \ Record CRUD (get/create/put/delete)
```

`PROVIDED akashic-aturi` / `akashic-did` / `akashic-tid` /
`akashic-xrpc` / `akashic-session` / `akashic-repo` — safe to
include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [AT URI — aturi.f](#at-uri--aturif)
- [DID — did.f](#did--didf)
- [TID — tid.f](#tid--tidf)
- [XRPC Client — xrpc.f](#xrpc-client--xrpcf)
- [Session — session.f](#session--sessionf)
- [Repository — repo.f](#repository--repof)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Six independent files** | Each file is independently `REQUIRE`-able with its own `PROVIDED` guard. |
| **Buffer-based** | Parsed components are copied into fixed-size static buffers. |
| **AT Protocol spec** | Follows the AT Protocol specification for URI syntax, DID validation, TID encoding, XRPC, and session management. |
| **Variable-based state** | All internal loops use `VARIABLE`s to avoid KDOS R-stack conflicts. |
| **ASCII codes for JSON** | Manual JSON building uses numeric char codes (34 for `"`, 123 for `{`, etc.) since KDOS has no `S\"` word. |

---

## AT URI — aturi.f

AT URIs follow the format `at://authority/collection/rkey`.

### Storage

Parsed components are copied into static buffers:

| Buffer | Size | Length Variable | Component |
|---|---|---|---|
| `ATURI-AUTHORITY` | 64 bytes | `ATURI-AUTH-LEN` | DID or handle |
| `ATURI-COLLECTION` | 64 bytes | `ATURI-COLL-LEN` | NSID (e.g. `app.bsky.feed.post`) |
| `ATURI-RKEY` | 32 bytes | `ATURI-RKEY-LEN` | Record key |

A length of `0` means the component is absent.

### ATURI-PARSE

```forth
ATURI-PARSE  ( addr len -- ior )
```

Parse an AT URI string.  Returns `0` on success, `-1` on failure.

Validates:
- Scheme must be `at`
- Authority must be non-empty
- Collection and rkey are optional

Internally delegates to `URI-PARSE` from `uri.f`, then verifies the
scheme and splits the path into collection and rkey on `/`.

### ATURI-BUILD

```forth
ATURI-BUILD  ( auth-a auth-u coll-a coll-u rkey-a rkey-u dst max -- written )
```

Build an AT URI from components.  Pass `0 0` for collection and/or
rkey to omit them.  Returns bytes written to `dst`.

---

## DID — did.f

Decentralized Identifiers (DIDs) used in the AT Protocol.

### DID-VALID?

```forth
DID-VALID?  ( addr len -- flag )
```

Returns `-1` if the string is a valid DID with a recognized method
prefix (`did:plc:` or `did:web:`).  Minimum length check: 8 characters.
Returns `0` otherwise.

### DID-METHOD

```forth
DID-METHOD  ( addr len -- method-a method-u )
```

Extract the method portion from a DID string.  Returns a pointer into
the original input.

Examples:
- `"did:plc:abc123"` → `"plc"` (length 3)
- `"did:web:example.com"` → `"web"` (length 3)
- `"did"` → zero-length result

---

## TID — tid.f

Timestamp Identifiers (TIDs) are 13-character, base32-sort-encoded
64-bit values used as record keys in the AT Protocol.

### Bit Layout

```
Bit 63:     0 (reserved, must be zero)
Bits 62–10: Microsecond timestamp (53 bits)
Bits 9–0:   Clock ID (10 bits, 0–1023)
```

### Base32-Sort Alphabet

```
234567abcdefghijklmnopqrstuvwxyz
```

Index 0 = `2`, index 31 = `z`.  Characters sort lexicographically
in timestamp order.

### TID-NOW

```forth
TID-NOW  ( dst -- )
```

Generate a 13-character TID at `dst`.  Uses `EPOCH@` (milliseconds)
multiplied by 1000 for approximate microsecond resolution.  Clock ID
auto-increments on each call and wraps at 1023.

### TID-COMPARE

```forth
TID-COMPARE  ( tid1 tid2 -- n )
```

Lexicographic comparison of two 13-byte TIDs.

Returns:
- `-1` if tid1 < tid2
- `0` if equal
- `1` if tid1 > tid2

---

## XRPC Client — xrpc.f

XRPC (Cross-RPC) wraps HTTP GET/POST calls to the AT Protocol lexicon
endpoint format: `https://<host>/xrpc/<nsid>`.

### Host Configuration

```forth
XRPC-SET-HOST  ( addr len -- )
```

Set the PDS hostname (max 63 chars).  Default: `bsky.social`.

### URL Building

Internally builds `https://<host>/xrpc/<nsid>?<params>&cursor=<val>`
into a 512-byte buffer.  Query parameters and cursor are appended
automatically when present.

### Cursor / Pagination

```forth
XRPC-SET-CURSOR       ( addr len -- )
XRPC-CLEAR-CURSOR     ( -- )
XRPC-HAS-CURSOR?      ( -- flag )
XRPC-EXTRACT-CURSOR   ( json-a json-u -- )
```

Pagination cursor management.  `XRPC-EXTRACT-CURSOR` parses a JSON
response and stores the `"cursor"` field value into the cursor buffer.
If no cursor key is found, clears the cursor (no more pages).

### XRPC-QUERY (GET)

```forth
XRPC-QUERY  ( nsid-a nsid-u params-a params-u -- body-a body-u ior )
```

Execute a GET request to `<host>/xrpc/<nsid>?<params>[&cursor=<val>]`.
Returns response body and `ior` (0 = success).

### XRPC-PROCEDURE (POST)

```forth
XRPC-PROCEDURE  ( nsid-a nsid-u body-a body-u -- resp-a resp-u ior )
```

Execute a POST request with JSON body.  Returns response body and `ior`.

---

## Session — session.f

Manages authentication with an AT Protocol PDS via `createSession`
and `refreshSession` XRPC procedures.  Stores access + refresh JWT
tokens and the session DID.

### Token Storage

| Buffer | Size | Purpose |
|---|---|---|
| `_SES-ACCESS` | 512 bytes | Access JWT |
| `_SES-REFRESH` | 512 bytes | Refresh JWT |
| `_SES-DID` | 128 bytes | Session DID |

### SESS-LOGIN

```forth
SESS-LOGIN  ( handle-a handle-u pass-a pass-u -- ior )
```

Authenticate with a PDS.  Builds `{"identifier":"...","password":"..."}`
and calls `com.atproto.server.createSession`.  On success, stores
JWTs, DID, and sets the HTTP bearer token for subsequent requests.

### SESS-REFRESH

```forth
SESS-REFRESH  ( -- ior )
```

Refresh the session using the stored refresh JWT.  Sends the refresh
token as a Bearer header (per AT Protocol spec) and calls
`com.atproto.server.refreshSession`.  Updates tokens on success.

### SESS-ACTIVE? / SESS-DID

```forth
SESS-ACTIVE?  ( -- flag )
SESS-DID      ( -- addr len )
```

Check if a session is active (access token stored) and retrieve
the session DID.

---

## Repository — repo.f

CRUD operations on AT Protocol records via XRPC.  All operations
require an active session (`SESS-ACTIVE?`).

### JSON Building

Uses manual string concatenation with ASCII char codes for JSON
construction (34 for `"`, 123/125 for `{}`), since KDOS has no `S\"`
word.  Record values are embedded raw (unquoted) to support
pre-built JSON records.

### REPO-GET

```forth
REPO-GET  ( aturi-a aturi-u -- json-a json-u ior )
```

Fetch a record by AT URI.  Parses the URI, builds query params
(`repo=<did>&collection=<nsid>[&rkey=<rkey>]`), and calls
`com.atproto.repo.getRecord`.

### REPO-CREATE

```forth
REPO-CREATE  ( coll-a coll-u json-a json-u -- uri-a uri-u ior )
```

Create a new record.  Builds
`{"repo":"<did>","collection":"<coll>","record":<json>}` and calls
`com.atproto.repo.createRecord`.  Returns the AT URI of the created
record.

### REPO-PUT

```forth
REPO-PUT  ( aturi-a aturi-u json-a json-u -- ior )
```

Overwrite a record at the given AT URI.  Builds
`{"repo":"<did>","collection":"<coll>","rkey":"<rkey>","record":<json>}`.

### REPO-DELETE

```forth
REPO-DELETE  ( aturi-a aturi-u -- ior )
```

Delete a record at the given AT URI.  Builds
`{"repo":"<did>","collection":"<coll>","rkey":"<rkey>"}`.

---

## Quick Reference

### aturi.f

| Word | Stack | Purpose |
|---|---|---|
| `ATURI-PARSE` | `( addr len -- ior )` | Parse AT URI |
| `ATURI-BUILD` | `( auth coll rkey dst max -- written )` | Build AT URI |
| `ATURI-AUTHORITY` | CREATE | 64-byte authority buffer |
| `ATURI-AUTH-LEN` | VARIABLE | Authority length |
| `ATURI-COLLECTION` | CREATE | 64-byte collection buffer |
| `ATURI-COLL-LEN` | VARIABLE | Collection length |
| `ATURI-RKEY` | CREATE | 32-byte rkey buffer |
| `ATURI-RKEY-LEN` | VARIABLE | Rkey length |

### did.f

| Word | Stack | Purpose |
|---|---|---|
| `DID-VALID?` | `( addr len -- flag )` | Validate DID format |
| `DID-METHOD` | `( addr len -- method-a method-u )` | Extract method |

### tid.f

| Word | Stack | Purpose |
|---|---|---|
| `TID-NOW` | `( dst -- )` | Generate 13-char TID |
| `TID-COMPARE` | `( tid1 tid2 -- n )` | Compare two TIDs |

### xrpc.f

| Word | Stack | Purpose |
|---|---|---|
| `XRPC-SET-HOST` | `( addr len -- )` | Set PDS hostname |
| `XRPC-QUERY` | `( nsid params -- body ior )` | XRPC GET request |
| `XRPC-PROCEDURE` | `( nsid body -- resp ior )` | XRPC POST request |
| `XRPC-SET-CURSOR` | `( addr len -- )` | Set pagination cursor |
| `XRPC-CLEAR-CURSOR` | `( -- )` | Clear cursor |
| `XRPC-HAS-CURSOR?` | `( -- flag )` | Check if cursor set |
| `XRPC-EXTRACT-CURSOR` | `( json-a json-u -- )` | Extract cursor from JSON |
| `XRPC-HOST` | CREATE | 64-byte hostname buffer |
| `XRPC-CURSOR` | CREATE | 128-byte cursor buffer |

### session.f

| Word | Stack | Purpose |
|---|---|---|
| `SESS-LOGIN` | `( handle pass -- ior )` | Authenticate with PDS |
| `SESS-REFRESH` | `( -- ior )` | Refresh session tokens |
| `SESS-ACTIVE?` | `( -- flag )` | Check if session active |
| `SESS-DID` | `( -- addr len )` | Get session DID |

### repo.f

| Word | Stack | Purpose |
|---|---|---|
| `REPO-GET` | `( aturi -- json ior )` | Fetch record by AT URI |
| `REPO-CREATE` | `( coll json -- uri ior )` | Create new record |
| `REPO-PUT` | `( aturi json -- ior )` | Overwrite record |
| `REPO-DELETE` | `( aturi -- ior )` | Delete record |

---

## Cookbook

### Parse an AT URI

```forth
S" at://did:plc:abc/app.bsky.feed.post/3k2la" ATURI-PARSE DROP
ATURI-AUTHORITY ATURI-AUTH-LEN @ TYPE   \ → did:plc:abc
ATURI-COLLECTION ATURI-COLL-LEN @ TYPE \ → app.bsky.feed.post
ATURI-RKEY ATURI-RKEY-LEN @ TYPE       \ → 3k2la
```

### Build an AT URI

```forth
CREATE _BUF 128 ALLOT
S" did:plc:test" S" app.bsky.feed.post" S" 3k2la"
_BUF 128 ATURI-BUILD
_BUF SWAP TYPE
\ → at://did:plc:test/app.bsky.feed.post/3k2la
```

### Round-trip

```forth
S" at://did:plc:round/trip.test.ns/rk42" ATURI-PARSE DROP
ATURI-AUTHORITY ATURI-AUTH-LEN @
ATURI-COLLECTION ATURI-COLL-LEN @
ATURI-RKEY ATURI-RKEY-LEN @
_BUF 128 ATURI-BUILD
_BUF SWAP TYPE
\ → at://did:plc:round/trip.test.ns/rk42
```

### Validate a DID

```forth
S" did:plc:abc123" DID-VALID? .    \ → -1 (valid)
S" did:key:z6Mk" DID-VALID? .     \ → 0  (unknown method)
S" hello" DID-VALID? .            \ → 0  (not a DID)
```

### Extract DID method

```forth
S" did:web:example.com" DID-METHOD TYPE   \ → web
```

### Generate and compare TIDs

```forth
CREATE _T1 16 ALLOT
CREATE _T2 16 ALLOT
_T1 TID-NOW
_T2 TID-NOW
_T1 13 TYPE              \ → e.g. 3kfg7h2abc222
_T1 _T2 TID-COMPARE .    \ → -1 (T1 < T2, generated earlier)
```

### XRPC: Paginated query

```forth
S" pds.example.com" XRPC-SET-HOST
XRPC-CLEAR-CURSOR
BEGIN
  S" app.bsky.feed.getTimeline"
  S" limit=25"
  XRPC-QUERY                   ( body-a body-u ior )
  0= WHILE
    \ process body...
    2DUP XRPC-EXTRACT-CURSOR
    2DROP
  XRPC-HAS-CURSOR? 0= UNTIL THEN ;
```

### Login and create a post

```forth
S" pds.example.com" XRPC-SET-HOST
S" handle.example.com" S" password"
SESS-LOGIN 0= IF
  S" app.bsky.feed.post"
  S" {\"text\":\"Hello from KDOS!\"}"
  REPO-CREATE                   ( uri-a uri-u ior )
  0= IF  TYPE CR  THEN          \ print AT URI
THEN
```

### Delete a record

```forth
S" at://did:plc:abc/app.bsky.feed.post/rk42" REPO-DELETE
0= IF ." Deleted" ELSE ." Failed" THEN
```

---

## Dependencies

- **aturi.f** — requires `uri.f` (generic URI parser) and `string.f`
  (for `STR-INDEX`).
- **did.f** — standalone, no dependencies.
- **tid.f** — standalone, uses BIOS `EPOCH@` for timestamps.
- **xrpc.f** — requires `http.f`, `string.f`, `json.f`.
- **session.f** — requires `xrpc.f`, `json.f`, `http.f`.
- **repo.f** — requires `session.f`, `xrpc.f`, `json.f`, `aturi.f`.

Full dependency chain for `repo.f`:
```
repo.f → session.f → xrpc.f → http.f → headers.f → url.f → string.f
                                      → json.f
                   → aturi.f → uri.f
```

## Internal State

### aturi.f — prefixed `_ATU-`

- `_ATU-PA` / `_ATU-PL` — path splitting state
- `_ATU-BPOS` / `_ATU-BDST` / `_ATU-BMAX` — builder cursor
- `_ATU-RK-A/L`, `_ATU-CO-A/L` — deep stack stash for builder

### did.f — prefixed `_DID-` / `_DM-`

- `_DID-PTR` / `_DID-LEN` — prefix match state
- `_DM-SRC` / `_DM-LEN` / `_DM-I` — method extraction

### tid.f — prefixed `_TID-`

- `_TID-ALPHA` — 32-byte base32-sort lookup table
- `_TID-VAL` — 64-bit value being encoded
- `_TID-CLK` — clock ID counter (wraps at 1023)

### xrpc.f — prefixed `_XR-`

- `_XR-URL` — 512-byte URL build buffer
- `_XR-POS` — URL write position
- `XRPC-HOST` / `XRPC-HOST-LEN` — PDS hostname (default `bsky.social`)
- `XRPC-CURSOR` / `XRPC-CURSOR-LEN` — pagination cursor buffer

### session.f — prefixed `_SES-`

- `_SES-ACCESS` / `_SES-ACCESS-LEN` — access JWT (512 bytes)
- `_SES-REFRESH` / `_SES-REFRESH-LEN` — refresh JWT (512 bytes)
- `_SES-DID` / `_SES-DID-LEN` — session DID (128 bytes)
- `_SES-JBUF` — 512-byte JSON build buffer for login
- `_SES-EX-DST/MAX/LEN` — key extraction state
- `_SES-HA/HL/PA/PL` — login build stash

### repo.f — prefixed `_REP-`

- `_REP-JBUF` — 2048-byte JSON body buffer
- `_REP-PBUF` — 256-byte query params buffer
- `_REP-URI` / `_REP-URI-LEN` — result URI buffer (256 bytes)
- `_REP-JP` / `_REP-PP` — write positions for JSON/params
- `_REP-V1A/L`, `_REP-V2A/L` — deep stack stash slots
