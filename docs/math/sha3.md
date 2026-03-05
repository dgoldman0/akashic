# akashic-sha3 — SHA-3 / SHAKE Cryptographic Hash

Hardware-accelerated SHA-3 (FIPS 202) wrapper.  Delegates all
computation to the BIOS SHA-3 / Keccak coprocessor at MMIO
`0xFFFF_FF00_0000_0780`.

```forth
REQUIRE sha3.f
```

`PROVIDED akashic-sha3` — no additional dependencies.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [One-Shot Hashing](#one-shot-hashing)
- [SHAKE Extendable-Output Functions](#shake-extendable-output-functions)
- [Streaming API](#streaming-api)
- [HMAC-SHA3-256](#hmac-sha3-256)
- [Hex Conversion & Display](#hex-conversion--display)
- [Comparison](#comparison)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Hardware-accelerated** | All Keccak permutation and padding is performed by the C++ SHA-3 coprocessor — zero software round logic. |
| **Four modes** | SHA3-256, SHA3-512, SHAKE-128, SHAKE-256 — same hardware, selectable via `SHA3-MODE!`. |
| **Multi-squeeze SHAKE** | For output lengths > 32 bytes, SHAKE words iterate `SHA3-SQUEEZE-NEXT` + `SHA3-DOUT@` in 32-byte blocks. |
| **Streaming** | `SHA3-256-BEGIN` / `SHA3-256-ADD` / `SHA3-256-END` (and SHA3-512 equivalents) allow incremental hashing. |
| **HMAC** | `SHA3-256-HMAC` implements HMAC-SHA3-256 (RFC 2104, block size = 136). |
| **Constant-time comparison** | `SHA3-256-COMPARE` / `SHA3-512-COMPARE` use OR-accumulation with no early exit. |
| **Mode safety** | SHA3-512, SHAKE-128, and SHAKE-256 words restore SHA3-256-MODE before returning. |
| **Not re-entrant** | Module-scoped VARIABLEs for HMAC pads and hex pointer.  One hash at a time. |

---

## Constants

### SHA3-256-LEN

```forth
SHA3-256-LEN  ( -- 32 )
```

SHA3-256 hash length in bytes.

### SHA3-256-HEX-LEN

```forth
SHA3-256-HEX-LEN  ( -- 64 )
```

SHA3-256 hex-encoded length in characters.

### SHA3-512-LEN

```forth
SHA3-512-LEN  ( -- 64 )
```

SHA3-512 hash length in bytes.

### SHA3-512-HEX-LEN

```forth
SHA3-512-HEX-LEN  ( -- 128 )
```

SHA3-512 hex-encoded length in characters.

---

## One-Shot Hashing

### SHA3-256-HASH

```forth
SHA3-256-HASH  ( src len dst -- )
```

Hash *len* bytes starting at *src* and write the 32-byte SHA3-256
digest to *dst*.

```forth
CREATE msg 3 ALLOT  97 msg C!  98 msg 1+ C!  99 msg 2 + C!
CREATE out 32 ALLOT
msg 3 out SHA3-256-HASH
\ out now contains SHA3-256("abc") = 3a985da7...
```

### SHA3-512-HASH

```forth
SHA3-512-HASH  ( src len dst -- )
```

Hash *len* bytes and write the 64-byte SHA3-512 digest to *dst*.
Restores SHA3-256 mode after completion.

---

## SHAKE Extendable-Output Functions

### SHAKE-128

```forth
SHAKE-128  ( src len dst dlen -- )
```

Compute SHAKE-128 XOF of *len* bytes at *src*, writing *dlen*
output bytes to *dst*.  For *dlen* ≤ 32, uses the initial squeeze.
For *dlen* > 32, iterates `SHA3-SQUEEZE-NEXT` in 32-byte blocks.
Restores SHA3-256 mode.

### SHAKE-256

```forth
SHAKE-256  ( src len dst dlen -- )
```

Compute SHAKE-256 XOF of *len* bytes at *src*, writing *dlen*
output bytes to *dst*.  Same multi-squeeze logic as SHAKE-128.
Restores SHA3-256 mode.

```forth
CREATE msg 3 ALLOT  97 msg C!  98 msg 1+ C!  99 msg 2 + C!
CREATE xof 64 ALLOT
msg 3 xof 64 SHAKE-128
\ xof contains 64 bytes of SHAKE-128("abc") = 5881092d...
```

---

## Streaming API

For messages that arrive in fragments or are too large to buffer.

### SHA3-256-BEGIN / SHA3-256-ADD / SHA3-256-END

```forth
SHA3-256-BEGIN  ( -- )           \ reset state, select SHA3-256 mode
SHA3-256-ADD    ( addr len -- )  \ feed data
SHA3-256-END    ( dst -- )       \ finalize, 32 bytes to dst
```

### SHA3-512-BEGIN / SHA3-512-ADD / SHA3-512-END

```forth
SHA3-512-BEGIN  ( -- )           \ reset state, select SHA3-512 mode
SHA3-512-ADD    ( addr len -- )  \ feed data
SHA3-512-END    ( dst -- )       \ finalize, 64 bytes to dst
```

Restores SHA3-256 mode after `SHA3-512-END`.

```forth
SHA3-256-BEGIN
part1 n1 SHA3-256-ADD
part2 n2 SHA3-256-ADD
my-hash SHA3-256-END
\ my-hash = SHA3-256( part1 || part2 )
```

---

## HMAC-SHA3-256

### SHA3-256-HMAC

```forth
SHA3-256-HMAC  ( key klen data dlen dst -- )
```

Compute HMAC-SHA3-256 per RFC 2104.  Block size is the SHA3-256
rate (136 bytes).  Keys longer than 136 bytes should be pre-hashed
by the caller.

```forth
\ HMAC-SHA3-256(key="key", msg="abc")
CREATE k 3 ALLOT  107 k C!  101 k 1+ C!  121 k 2 + C!
CREATE m 3 ALLOT   97 m C!   98 m 1+ C!   99 m 2 + C!
CREATE tag 32 ALLOT
k 3 m 3 tag SHA3-256-HMAC
\ tag = 09b6dbab...
```

---

## Hex Conversion & Display

### SHA3-256-.

```forth
SHA3-256-.  ( addr -- )
```

Print the 32-byte hash at *addr* as 64 lowercase hex characters.

### SHA3-512-.

```forth
SHA3-512-.  ( addr -- )
```

Print the 64-byte hash at *addr* as 128 lowercase hex characters.

### SHA3-256->HEX

```forth
SHA3-256->HEX  ( src dst -- n )
```

Convert 32-byte hash to 64 lowercase hex characters at *dst*.
Returns 64.

### SHA3-512->HEX

```forth
SHA3-512->HEX  ( src dst -- n )
```

Convert 64-byte hash to 128 lowercase hex characters at *dst*.
Returns 128.

---

## Comparison

### SHA3-256-COMPARE

```forth
SHA3-256-COMPARE  ( a b -- flag )
```

Constant-time comparison of two 32-byte hashes.
Returns `TRUE` (-1) if equal, `FALSE` (0) otherwise.

### SHA3-512-COMPARE

```forth
SHA3-512-COMPARE  ( a b -- flag )
```

Constant-time comparison of two 64-byte hashes.

Both use OR-accumulation over all bytes — timing does not depend
on the position of the first differing byte.

---

## Hardware Detail

The BIOS SHA-3 / Keccak coprocessor lives at MMIO base
`0xFFFF_FF00_0000_0780`:

| Offset | Register | Description |
|--------|----------|-------------|
| `+0x00` | CMD | 1 = INIT, 3 = FINAL, 4 = SQUEEZE, 5 = SQUEEZE_NEXT |
| `+0x08` | STATUS | Busy / done flags |
| `+0x10` | MODE | 0 = SHA3-256, 1 = SHA3-512, 2 = SHAKE128, 3 = SHAKE256 |
| `+0x18` | DIN | Byte input |
| `+0x20` | DLEN | Input byte count (for UPDATE) |
| `+0x28` | DOUT_PTR | Read pointer for output |
| `+0x30..+0x6F` | DOUT | 64-byte output buffer (big-endian) |

BIOS words used: `SHA3-INIT`, `SHA3-UPDATE`, `SHA3-FINAL`,
`SHA3-MODE!`, `SHA3-MODE@`, `SHA3-DOUT@`, `SHA3-SQUEEZE-NEXT`.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `SHA3-256-LEN` | `( -- 32 )` | Hash length in bytes |
| `SHA3-256-HEX-LEN` | `( -- 64 )` | Hex string length |
| `SHA3-512-LEN` | `( -- 64 )` | Hash length in bytes |
| `SHA3-512-HEX-LEN` | `( -- 128 )` | Hex string length |
| `SHA3-256-HASH` | `( src len dst -- )` | One-shot SHA3-256 |
| `SHA3-512-HASH` | `( src len dst -- )` | One-shot SHA3-512 |
| `SHAKE-128` | `( src len dst dlen -- )` | SHAKE-128 XOF |
| `SHAKE-256` | `( src len dst dlen -- )` | SHAKE-256 XOF |
| `SHA3-256-BEGIN` | `( -- )` | Start streaming SHA3-256 |
| `SHA3-256-ADD` | `( addr len -- )` | Feed data |
| `SHA3-256-END` | `( dst -- )` | Finalize to dst |
| `SHA3-512-BEGIN` | `( -- )` | Start streaming SHA3-512 |
| `SHA3-512-ADD` | `( addr len -- )` | Feed data |
| `SHA3-512-END` | `( dst -- )` | Finalize to dst |
| `SHA3-256-HMAC` | `( key klen data dlen dst -- )` | HMAC-SHA3-256 |
| `SHA3-256-.` | `( addr -- )` | Print hash as hex |
| `SHA3-512-.` | `( addr -- )` | Print hash as hex |
| `SHA3-256->HEX` | `( src dst -- n )` | Convert to hex string |
| `SHA3-512->HEX` | `( src dst -- n )` | Convert to hex string |
| `SHA3-256-COMPARE` | `( a b -- flag )` | Constant-time equality |
| `SHA3-512-COMPARE` | `( a b -- flag )` | Constant-time equality |
