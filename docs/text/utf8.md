# akashic-utf8 — UTF-8 Codec

Decode and encode Unicode codepoints in the standard `( addr len )`
byte-buffer model used throughout Akashic.  Handles all valid UTF-8
sequences (1–4 bytes) and rejects overlong encodings, surrogates,
and out-of-range codepoints with U+FFFD replacement.

```forth
REQUIRE text/utf8.f
```

`PROVIDED akashic-utf8` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Decode](#decode)
- [Encode](#encode)
- [Length](#length)
- [Validation](#validation)
- [Nth Codepoint](#nth-codepoint)
- [Error Handling](#error-handling)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Standard buffer model** | All APIs use `( addr len )` byte buffers. |
| **Streaming decode** | `UTF8-DECODE` consumes one codepoint and returns the remaining buffer. |
| **Error recovery** | Invalid bytes produce U+FFFD and advance by 1 — never gets stuck. |
| **Zero allocation** | No heap usage; scratch `VARIABLE`s only. |
| **Prefix convention** | Public: `UTF8-`. Internal: `_UTF8-`. |
| **Not reentrant** | Shared scratch `VARIABLE`s; call from one task only. |

---

## Constants

### UTF8-REPLACEMENT

```
( -- 65533 )
```

The Unicode replacement character U+FFFD.  Returned by `UTF8-DECODE`
for any invalid or undecodable byte sequence.

---

## Decode

### UTF8-DECODE

```
( addr len -- cp addr' len' )
```

Consume one UTF-8 character from the front of the buffer.  Returns
the decoded codepoint and the remaining buffer (address advanced,
length reduced).

- 1-byte (ASCII): `0x00`–`0x7F`
- 2-byte: `0xC2`–`0xDF` + 1 continuation
- 3-byte: `0xE0`–`0xEF` + 2 continuations
- 4-byte: `0xF0`–`0xF4` + 3 continuations

On error (bare continuation, truncated sequence, overlong encoding,
surrogate, or out-of-range codepoint), returns `UTF8-REPLACEMENT`
(U+FFFD) and advances by 1 byte.

```forth
\ Decode "Aé" (41 C3 A9)
CREATE buf  3 ALLOT
65 buf C!  195 buf 1 + C!  169 buf 2 + C!

buf 3 UTF8-DECODE    \ → 65 (addr+1) 2     — 'A'
     UTF8-DECODE     \ → 233 (addr+3) 0    — 'é'
2DROP
```

---

## Encode

### UTF8-ENCODE

```
( cp buf -- buf' )
```

Write one codepoint as UTF-8 into `buf`.  The buffer must have at
least 4 bytes available.  Returns the address past the last byte
written.

```forth
CREATE out  4 ALLOT

233 out UTF8-ENCODE out -    \ → 2  (wrote C3 A9)
128512 out UTF8-ENCODE out - \ → 4  (wrote F0 9F 98 80)
```

---

## Length

### UTF8-LEN

```
( addr len -- n )
```

Count the number of codepoints in a UTF-8 buffer.  Invalid sequences
count as one codepoint each (the replacement character).

```forth
buf 6 UTF8-LEN   \ "Aé☺" → 3
```

---

## Validation

### UTF8-VALID?

```
( addr len -- flag )
```

Returns `-1` (true) if the entire buffer is valid UTF-8, or `0`
(false) if any byte sequence would produce a replacement character.
An empty buffer is considered valid.

```forth
buf 3 UTF8-VALID?    \ valid "Aé" → -1
bad 1 UTF8-VALID?    \ bare 0x80  → 0
```

---

## Nth Codepoint

### UTF8-NTH

```
( addr len n -- cp )
```

Return the nth codepoint (0-based) from the buffer.  Returns
`UTF8-REPLACEMENT` if `n` is past the end.

```forth
buf 6 0 UTF8-NTH   \ → 65   ('A')
buf 6 1 UTF8-NTH   \ → 233  ('é')
buf 6 2 UTF8-NTH   \ → 9786 ('☺')
buf 6 5 UTF8-NTH   \ → 65533 (U+FFFD, out of range)
```

---

## Error Handling

All decode errors produce `UTF8-REPLACEMENT` (U+FFFD = 65533) and
advance the buffer position by exactly 1 byte.  This guarantees:

- **No infinite loops** — the buffer always shrinks.
- **Graceful degradation** — corrupted text renders with replacement
  characters rather than crashing.

Error conditions:

| Condition | Example | Result |
|-----------|---------|--------|
| Bare continuation byte | `0x80` | U+FFFD, skip 1 |
| Truncated sequence | `0xC3` at end of buffer | U+FFFD, skip 1 |
| Overlong encoding | `0xC1 0x81` for U+0041 | U+FFFD, skip 1 |
| Surrogate codepoint | `0xED 0xA0 0x80` (U+D800) | U+FFFD, skip 1 |
| Out of range | > U+10FFFF | U+FFFD, skip 1 |
| Empty buffer | `( 0 0 )` | U+FFFD, no advance |

---

## Quick Reference

| Word | Stack | Short |
|------|-------|-------|
| `UTF8-DECODE` | `( addr len -- cp addr' len' )` | Decode one codepoint |
| `UTF8-ENCODE` | `( cp buf -- buf' )` | Encode one codepoint |
| `UTF8-LEN` | `( addr len -- n )` | Count codepoints |
| `UTF8-VALID?` | `( addr len -- flag )` | Check validity |
| `UTF8-NTH` | `( addr len n -- cp )` | Get nth codepoint |
| `UTF8-REPLACEMENT` | `( -- 65533 )` | U+FFFD constant |
