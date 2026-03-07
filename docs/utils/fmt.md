# akashic-fmt — Formatting Utilities

Hex printing and formatting primitives for Megapad-64.  Provides a
canonical set of words so individual modules do not need to define
their own private nibble/hex routines.

```forth
REQUIRE ../utils/fmt.f
```

`PROVIDED akashic-fmt` — no dependencies (pure KDOS).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Nibble / Byte Primitives](#nibble--byte-primitives)
- [Multi-byte Hex Display](#multi-byte-hex-display)
- [Hex String Builder](#hex-string-builder)
- [Hex Decoding](#hex-decoding)
- [Cell-as-Hex Display](#cell-as-hex-display)
- [Hex Dump](#hex-dump)
- [Usage Examples](#usage-examples)
- [Quick Reference](#quick-reference)
- [Internals](#internals)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Single source of truth** | One module provides hex formatting; others `REQUIRE` it instead of rolling their own |
| **Zero dependencies** | Works with bare KDOS — no crypto, no string library needed |
| **Lookup table** | Nibble-to-char uses a 16-byte table, not branching arithmetic |
| **Both emit and buffer** | `FMT-.HEX` emits to UART; `FMT->HEX` writes to a memory buffer |
| **Bidirectional** | `FMT->HEX` encodes binary→hex; `FMT-HEX-DECODE` decodes hex→binary |
| **Not reentrant** | Uses module-level VARIABLEs for scratch state |

---

## Nibble / Byte Primitives

### FMT-NIB>C

```forth
FMT-NIB>C  ( n -- c )
```

Convert a nibble (0–15) to its lowercase ASCII hex character.
Only the low 4 bits are used.

### FMT-.NIB

```forth
FMT-.NIB  ( n -- )
```

Emit one hex nibble to UART.

### FMT-.BYTE

```forth
FMT-.BYTE  ( b -- )
```

Emit one byte as two lowercase hex characters (high nibble first).

```forth
0xAB FMT-.BYTE   \ emits "ab"
```

---

## Multi-byte Hex Display

### FMT-.HEX

```forth
FMT-.HEX  ( addr n -- )
```

Emit `n` bytes starting at `addr` as lowercase hex.  Zero-length is
safe (no output).

```forth
my-hash 32 FMT-.HEX   \ prints 64 hex chars
```

---

## Hex String Builder

### FMT->HEX

```forth
FMT->HEX  ( src n dst -- n*2 )
```

Write `n` bytes from `src` as lowercase hex characters into the buffer
at `dst`.  Returns the number of characters written (always `n * 2`).
Does **not** null-terminate.  Does **not** emit anything.

```forth
CREATE hex-str 64 ALLOT
my-hash 32 hex-str FMT->HEX   ( -- 64 )
hex-str 64 TYPE                \ prints the hex string
```

---

## Hex Decoding

### FMT-C>NIB

```forth
FMT-C>NIB  ( c -- n )
```

Convert an ASCII hex character (`0`–`9`, `a`–`f`, `A`–`F`) to its
nibble value (0–15).  Returns 0 for invalid characters.

```forth
[CHAR] a FMT-C>NIB .   \ prints 10
[CHAR] F FMT-C>NIB .   \ prints 15
```

### FMT-HEX-DECODE

```forth
FMT-HEX-DECODE  ( hex-a hex-u dst -- n )
```

Decode a hex string into binary bytes.  Reads `hex-u` characters from
`hex-a` (must be even), writes `hex-u / 2` bytes to `dst`.  Returns
the number of bytes decoded.

```forth
CREATE raw 32 ALLOT
S" deadbeef" raw FMT-HEX-DECODE   ( -- 4 )  \ raw contains DE AD BE EF
```

This is the inverse of `FMT->HEX`.

---

## Cell-as-Hex Display

### FMT-U.H

```forth
FMT-U.H  ( u -- )
```

Emit a full 64-bit cell as 16 lowercase hex characters, most
significant byte first.

```forth
0xFF FMT-U.H   \ emits "00000000000000ff"
```

### FMT-U.H4

```forth
FMT-U.H4  ( u -- )
```

Emit the low 32 bits of a cell as 8 lowercase hex characters.

```forth
0xDEAD FMT-U.H4   \ emits "0000dead"
```

---

## Hex Dump

### FMT-.HEXDUMP

```forth
FMT-.HEXDUMP  ( addr n -- )
```

Print a classic hex dump: 16 bytes per line with an ASCII sidebar.
Bytes outside the printable range (0x20–0x7E) are shown as `.` in the
sidebar.  Bytes beyond `n` are shown as `..` in the hex columns.

```
00000000  48 65 6c 6c 6f 20 57 6f  72 6c 64 00 .. .. .. ..  |Hello World.....|
00000010  41 42 43 44 .. .. .. ..  .. .. .. .. .. .. .. ..  |ABCD............|
```

Line offsets are 0-based (relative to the start of the dump, not
absolute memory addresses).

---

## Usage Examples

### Print a SHA3-256 hash

```forth
my-buf 64 SHA3-256-HASH
my-hash 32 FMT-.HEX CR
```

### Convert hash to hex string for comparison

```forth
CREATE hex-a 64 ALLOT
CREATE hex-b 64 ALLOT
hash-a 32 hex-a FMT->HEX DROP
hash-b 32 hex-b FMT->HEX DROP
hex-a 64 hex-b 64 STR-STR=   ( -- flag )
```

### Debug dump of a CBOR buffer

```forth
my-cbor-buf encoded-len FMT-.HEXDUMP
```

---

## Quick Reference

```
FMT-NIB>C       ( n -- c )            nibble → hex char
FMT-.NIB        ( n -- )              emit one hex nibble
FMT-.BYTE       ( b -- )              emit byte as 2 hex chars
FMT-.HEX        ( addr n -- )         emit n bytes as hex
FMT->HEX        ( src n dst -- n*2 )  write n bytes as hex to buffer
FMT-U.H         ( u -- )              emit cell as 16 hex chars
FMT-U.H4        ( u -- )              emit low 32 bits as 8 hex chars
FMT-C>NIB       ( c -- n )            hex char → nibble (0-15)
FMT-HEX-DECODE  ( hex-a hex-u dst -- n ) hex string → binary bytes
FMT-.HEXDUMP    ( addr n -- )         16-byte/line hex dump + ASCII
```

---

## Internals

### Lookup Table

`_FMT-HEX` is a 16-byte table containing `"0123456789abcdef"` compiled
with `C,`.  `FMT-NIB>C` indexes into it after masking the low 4 bits.
This avoids branching (`IF/ELSE/THEN`) in the hot path.

### VARIABLE-based Loops

`FMT-.HEXDUMP` uses `BEGIN/WHILE/REPEAT` with VARIABLEs for row and
column tracking rather than nested `DO/LOOP`.  This avoids
interference with `FMT-U.H4`'s own internal `DO` loop, which would
corrupt `J` indices in a nested-`DO` design.

### Migration Path

Modules that currently define their own private hex routines (sha3.f,
crc.f, field.f, random.f, sha256.f, sha512.f) can optionally be
migrated to use fmt.f.  Their private copies still work; new modules
should use fmt.f from the start.

### Not Reentrant

`FMT->HEX` uses `_FMT-DST` (a VARIABLE) for the output pointer.
`FMT-HEX-DECODE` uses `_FMT-SRC` for the input pointer.
`FMT-.HEXDUMP` uses four VARIABLEs for base, length, offset, and
column.  Do not call these from interrupt context.
