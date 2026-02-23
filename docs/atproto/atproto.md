# akashic-atproto — AT Protocol Primitives for KDOS / Megapad-64

AT Protocol identity and record-addressing primitives: AT URIs, DIDs,
and TIDs.  Foundation layer for Bluesky and any AT Protocol application.

```forth
REQUIRE aturi.f    \ AT URI parser + builder
REQUIRE did.f      \ DID validation + method extraction
REQUIRE tid.f      \ TID generation + comparison
```

`PROVIDED akashic-aturi` / `akashic-did` / `akashic-tid` — safe to
include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [AT URI — aturi.f](#at-uri--aturif)
- [DID — did.f](#did--didf)
- [TID — tid.f](#tid--tidf)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Three independent files** | Each file is independently `REQUIRE`-able with its own `PROVIDED` guard. |
| **Buffer-based** | Parsed components are copied into fixed-size static buffers. |
| **AT Protocol spec** | Follows the AT Protocol specification for URI syntax, DID validation, and TID encoding. |
| **Variable-based state** | All internal loops use `VARIABLE`s to avoid KDOS R-stack conflicts. |

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

---

## Dependencies

- **aturi.f** — requires `uri.f` (generic URI parser) and `string.f`
  (for `STR-INDEX`).
- **did.f** — standalone, no dependencies.
- **tid.f** — standalone, uses BIOS `EPOCH@` for timestamps.

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
