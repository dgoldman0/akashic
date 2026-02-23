# akashic-base64 — Base64 Vocabulary for KDOS / Megapad-64

RFC 4648 Base64 encoding and decoding for KDOS Forth.
Supports both standard (`+/=`) and URL-safe (`-_`) alphabets.
All operations work on caller-provided `(src dst)` buffer pairs —
no hidden allocations.

```forth
REQUIRE base64.f
```

`PROVIDED akashic-base64` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Handling](#error-handling)
- [Length Calculations](#length-calculations)
- [Encoding](#encoding)
- [Decoding](#decoding)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Dual alphabet** | Standard Base64 (`+/=` padding) and URL-safe (`-_`, no padding) share a single core encoder parameterised by lookup table and pad flag. |
| **Buffer-based** | All words take `( src slen dst dmax -- written )` — caller owns both buffers. |
| **No hidden allocations** | Two 64-byte lookup tables and a handful of `VARIABLE`s are the only static storage. |
| **Variable-based state** | Internal encode/decode loops use `VARIABLE`-based accumulators instead of deep stack manipulation. |

---

## Error Handling

### Variables

| Word | Stack | Purpose |
|---|---|---|
| `B64-ERR` | VARIABLE | Last error code (0 = no error) |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `B64-E-INVALID` | 1 | Invalid Base64 character encountered |
| `B64-E-OVERFLOW` | 2 | Output buffer too small |

### Words

```forth
B64-FAIL       ( code -- )   \ Store error code
B64-OK?        ( -- flag )   \ True if no error pending
B64-CLEAR-ERR  ( -- )        \ Reset error state
```

---

## Length Calculations

```forth
B64-ENCODED-LEN  ( n -- m )
```

Calculate the Base64-encoded length for `n` input bytes.  Always a
multiple of 4: $m = \lceil (n + 2) / 3 \rceil \times 4$.

```forth
B64-DECODED-LEN  ( n -- m )
```

Estimate the maximum decoded length for `n` Base64 characters:
$m = \lfloor n / 4 \rfloor \times 3$.  Actual output may be 1–2 bytes shorter
due to padding.

---

## Encoding

### B64-ENCODE

```forth
B64-ENCODE  ( src slen dst dmax -- written )
```

Encode `slen` bytes from `src` into standard Base64 at `dst`.
Uses the `A-Za-z0-9+/` alphabet with `=` padding.  Returns number
of bytes written.

### B64-ENCODE-URL

```forth
B64-ENCODE-URL  ( src slen dst dmax -- written )
```

Encode into URL-safe Base64: `A-Za-z0-9-_` alphabet, no `=` padding.
Same interface as `B64-ENCODE`.

---

## Decoding

### B64-DECODE

```forth
B64-DECODE  ( src slen dst dmax -- written )
```

Decode standard Base64 from `src` into raw bytes at `dst`.  Handles
`=` padding.  Sets `B64-E-INVALID` if an illegal character is found.
Returns number of bytes written.

### B64-DECODE-URL

```forth
B64-DECODE-URL  ( src slen dst dmax -- written )
```

Decode URL-safe Base64.  Same interface as `B64-DECODE`, handles
the `-_` alphabet and missing padding.

---

## Quick Reference

| Word | Stack | Purpose |
|---|---|---|
| `B64-ENCODE` | `( src slen dst dmax -- written )` | Standard Base64 encode |
| `B64-ENCODE-URL` | `( src slen dst dmax -- written )` | URL-safe Base64 encode |
| `B64-DECODE` | `( src slen dst dmax -- written )` | Standard Base64 decode |
| `B64-DECODE-URL` | `( src slen dst dmax -- written )` | URL-safe Base64 decode |
| `B64-ENCODED-LEN` | `( n -- m )` | Calculate encoded output size |
| `B64-DECODED-LEN` | `( n -- m )` | Estimate decoded output size |
| `B64-ERR` | VARIABLE | Error state |
| `B64-FAIL` | `( code -- )` | Set error |
| `B64-OK?` | `( -- flag )` | Check error state |
| `B64-CLEAR-ERR` | `( -- )` | Clear error |

---

## Cookbook

### Encode a string

```forth
CREATE _ENC 64 ALLOT
S" Hello, World!" _ENC 64 B64-ENCODE
_ENC SWAP TYPE
\ prints: SGVsbG8sIFdvcmxkIQ==
```

### Decode Base64

```forth
CREATE _DEC 64 ALLOT
S" SGVsbG8=" _DEC 64 B64-DECODE
_DEC SWAP TYPE
\ prints: Hello
```

### URL-safe round-trip

```forth
CREATE _BUF 64 ALLOT
CREATE _OUT 48 ALLOT
S" binary\x00data" _BUF 64 B64-ENCODE-URL  ( written )
_BUF OVER _OUT 48 B64-DECODE-URL           ( original-len )
```

### Check buffer size before encoding

```forth
S" test data" NIP B64-ENCODED-LEN .  \ prints: 16
```
