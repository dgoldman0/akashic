# akashic-cbor — CBOR Codec for KDOS / Megapad-64

RFC 8949 CBOR (Concise Binary Object Representation) encoding and
decoding.  Integer-only subset — no floating point.  Includes a
DAG-CBOR extension for AT Protocol / IPLD CID links and map key
ordering.

```forth
REQUIRE cbor.f
REQUIRE dag-cbor.f   \ optional — loads DCBOR-* words
```

`PROVIDED akashic-cbor` / `PROVIDED akashic-dag-cbor` — safe to include
multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Major Types](#major-types)
- [Encoding](#encoding)
- [Decoding](#decoding)
- [DAG-CBOR Extension](#dag-cbor-extension)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Buffer-based** | Encoder writes to a caller-provided `(dst max)` buffer. Decoder reads from a caller-provided `(addr len)` buffer. |
| **No heap** | All state in `VARIABLE`s — no dynamic allocation. |
| **Zero-copy decode** | `CBOR-NEXT-BSTR` / `CBOR-NEXT-TSTR` return pointers into the input buffer. |
| **Big-endian wire** | Multi-byte integers emitted/read in network byte order per RFC 8949. |
| **Integer-only** | No IEEE 754 float support. Simple values limited to true, false, null. |

---

## Major Types

| Constant | Value | CBOR Type |
|---|---|---|
| `CBOR-MT-UINT` | 0 | Unsigned integer |
| `CBOR-MT-NINT` | 1 | Negative integer |
| `CBOR-MT-BSTR` | 2 | Byte string |
| `CBOR-MT-TSTR` | 3 | Text string |
| `CBOR-MT-ARRAY` | 4 | Array |
| `CBOR-MT-MAP` | 5 | Map |
| `CBOR-MT-TAG` | 6 | Semantic tag |
| `CBOR-MT-SIMPLE` | 7 | Simple / float |

---

## Encoding

### Setup

```forth
CBOR-RESET  ( dst max -- )
```

Set the output buffer.  Must be called before any encoding words.
Resets the write position to 0.

### Data Items

```forth
CBOR-UINT    ( n -- )         \ Unsigned integer (major 0)
CBOR-NINT    ( n -- )         \ Negative integer (major 1): represents -(1+n)
CBOR-BSTR    ( addr len -- )  \ Byte string (major 2)
CBOR-TSTR    ( addr len -- )  \ Text string (major 3)
CBOR-ARRAY   ( n -- )         \ Array header with n items (major 4)
CBOR-MAP     ( n -- )         \ Map header with n key-value pairs (major 5)
CBOR-TAG     ( n -- )         \ Semantic tag (major 6)
CBOR-TRUE    ( -- )           \ Simple value true  (0xF5)
CBOR-FALSE   ( -- )           \ Simple value false (0xF4)
CBOR-NULL    ( -- )           \ Simple value null  (0xF6)
```

Containers (`CBOR-ARRAY`, `CBOR-MAP`) only write the header.  The
caller must encode exactly `n` items (or `2*n` for maps) after the
header.

### Result

```forth
CBOR-RESULT  ( -- addr len )
```

Return the encoded bytes so far.  `addr` is the buffer start, `len`
is the bytes written.

### Argument Encoding

The encoder automatically chooses the most compact representation:

| Value Range | Extra Bytes | Additional Info |
|---|---|---|
| 0–23 | 0 | Value in initial byte |
| 24–255 | 1 | Additional info = 24 |
| 256–65535 | 2 | Additional info = 25 |
| 65536–4294967295 | 4 | Additional info = 26 |
| > 4294967295 | 8 | Additional info = 27 |

---

## Decoding

### Setup

```forth
CBOR-PARSE  ( addr len -- ior )
```

Set the input cursor.  Returns `0` on success.

### Inspection

```forth
CBOR-TYPE   ( -- major-type )   \ Peek at next item's major type (0-7, or -1 at end)
CBOR-DONE?  ( -- flag )         \ True (-1) if input is exhausted
```

### Reading Items

```forth
CBOR-NEXT-UINT   ( -- n )          \ Decode unsigned integer
CBOR-NEXT-NINT   ( -- n )          \ Decode negative integer argument
CBOR-NEXT-BSTR   ( -- addr len )   \ Decode byte string (pointer into input)
CBOR-NEXT-TSTR   ( -- addr len )   \ Decode text string (pointer into input)
CBOR-NEXT-ARRAY  ( -- n )          \ Decode array header, return item count
CBOR-NEXT-MAP    ( -- n )          \ Decode map header, return pair count
CBOR-NEXT-TAG    ( -- n )          \ Decode tag number
CBOR-NEXT-BOOL   ( -- flag )       \ Decode boolean (-1 = true, 0 = false)
```

### Skipping

```forth
CBOR-SKIP  ( -- )
```

Skip one complete CBOR data item, including nested arrays, maps,
and tagged items.  Handles recursive structures.

---

## DAG-CBOR Extension

DAG-CBOR is a restricted CBOR subset used by IPLD and the AT Protocol.

### CID Links

```forth
DCBOR-CID  ( addr len -- )
```

Encode a CID (Content Identifier) link.  Wraps the CID bytes in
tag 42 + byte string with a `0x00` identity multibase prefix:

Wire format: `D8 2A <bstr-head> 00 <cid-bytes...>`

### Map Key Validation

```forth
DCBOR-SORT-MAP  ( -- flag )
```

Validate that the next map in the decoder stream has keys in
DAG-CBOR canonical order.  The caller must have called `CBOR-PARSE`
first.

DAG-CBOR key ordering rules:
1. Shorter keys sort before longer keys
2. Keys of equal length sort lexicographically
3. Duplicate keys are not allowed

Returns `-1` if valid, `0` if invalid.

---

## Quick Reference

### Encoder

| Word | Stack | Purpose |
|---|---|---|
| `CBOR-RESET` | `( dst max -- )` | Set output buffer |
| `CBOR-UINT` | `( n -- )` | Encode unsigned int |
| `CBOR-NINT` | `( n -- )` | Encode negative int |
| `CBOR-BSTR` | `( addr len -- )` | Encode byte string |
| `CBOR-TSTR` | `( addr len -- )` | Encode text string |
| `CBOR-ARRAY` | `( n -- )` | Array header |
| `CBOR-MAP` | `( n -- )` | Map header |
| `CBOR-TAG` | `( n -- )` | Semantic tag |
| `CBOR-TRUE` | `( -- )` | Encode true |
| `CBOR-FALSE` | `( -- )` | Encode false |
| `CBOR-NULL` | `( -- )` | Encode null |
| `CBOR-RESULT` | `( -- addr len )` | Get encoded bytes |

### Decoder

| Word | Stack | Purpose |
|---|---|---|
| `CBOR-PARSE` | `( addr len -- ior )` | Set input buffer |
| `CBOR-TYPE` | `( -- major-type )` | Peek next type |
| `CBOR-DONE?` | `( -- flag )` | Input exhausted? |
| `CBOR-NEXT-UINT` | `( -- n )` | Read unsigned int |
| `CBOR-NEXT-NINT` | `( -- n )` | Read negative int argument |
| `CBOR-NEXT-BSTR` | `( -- addr len )` | Read byte string |
| `CBOR-NEXT-TSTR` | `( -- addr len )` | Read text string |
| `CBOR-NEXT-ARRAY` | `( -- n )` | Read array header |
| `CBOR-NEXT-MAP` | `( -- n )` | Read map header |
| `CBOR-NEXT-TAG` | `( -- n )` | Read tag number |
| `CBOR-NEXT-BOOL` | `( -- flag )` | Read boolean |
| `CBOR-SKIP` | `( -- )` | Skip one item |

### DAG-CBOR

| Word | Stack | Purpose |
|---|---|---|
| `DCBOR-CID` | `( addr len -- )` | Encode CID link |
| `DCBOR-SORT-MAP` | `( -- flag )` | Validate map key order |

---

## Cookbook

### Encode a simple map

```forth
CREATE _OB 256 ALLOT
_OB 256 CBOR-RESET
2 CBOR-MAP                    \ map with 2 entries
  S" name" CBOR-TSTR          \ key
  S" Alice" CBOR-TSTR         \ value
  S" age" CBOR-TSTR           \ key
  25 CBOR-UINT                \ value
CBOR-RESULT                   \ → addr len (encoded CBOR)
```

### Decode a CBOR buffer

```forth
CBOR-PARSE DROP
CBOR-TYPE .                    \ → 5 (map)
CBOR-NEXT-MAP .                \ → 2 (pairs)
CBOR-NEXT-TSTR TYPE            \ → name
CBOR-NEXT-TSTR TYPE            \ → Alice
CBOR-NEXT-TSTR TYPE            \ → age
CBOR-NEXT-UINT .               \ → 25
```

### Encode a CID link (DAG-CBOR)

```forth
_OB 256 CBOR-RESET
CREATE _CID 32 ALLOT    \ assume 32-byte CID hash
_CID 32 DCBOR-CID
CBOR-RESULT              \ → tag(42) + bstr(0x00 + 32 bytes)
```

### Validate DAG-CBOR map ordering

```forth
\ Given a buffer with an encoded map:
buf len CBOR-PARSE DROP
DCBOR-SORT-MAP .         \ → -1 (keys are sorted) or 0 (not sorted)
```

---

## Dependencies

- **cbor.f** — standalone, no dependencies.
- **dag-cbor.f** — requires `cbor.f` (uses `CBOR-TAG`, `_CB-ARG`,
  `_CB-EMIT`, `_CB-EMITCPY`, `CBOR-NEXT-MAP`, `CBOR-NEXT-TSTR`,
  `CBOR-SKIP`).

## Internal State

Encoder variables prefixed `_CB-`:
- `_CB-DST` / `_CB-MAX` / `_CB-POS` — output buffer state
- `_CB-MT` — scratch for major type in `_CB-ARG`

Decoder variables prefixed `_CB-`:
- `_CB-SRC` / `_CB-END` / `_CB-PTR` — input buffer state
- `_CB-SKIP-N` — recursion counter for `CBOR-SKIP`

DAG-CBOR variables prefixed `_DCB-`:
- `_DCB-CID-LEN` — scratch for CID encoding
- `_DCB-A1/L1/A2/L2` — key comparison
- `_DCB-PREV-A/L`, `_DCB-CUR-A/L` — sort validation
- `_DCB-PAIRS`, `_DCB-OK` — map validation state
