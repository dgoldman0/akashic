# akashic-field — Field Arithmetic (Hardware Field ALU)

256-bit modular arithmetic over standard elliptic-curve primes and
user-defined custom primes.  Delegates all computation to the
hardware Field ALU at MMIO `0xFFFF_FF00_0000_0840` (C++ device
`CryptoFieldALU`), which provides single-cycle modular
add/sub/mul/sqr/inv/pow plus 512-bit raw multiply.

```forth
REQUIRE field.f
```

`PROVIDED akashic-field` — no dependencies.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Prime Selection](#prime-selection)
- [Buffer Management](#buffer-management)
- [Core Arithmetic](#core-arithmetic)
- [Exponentiation](#exponentiation)
- [Raw Multiply](#raw-multiply)
- [Comparison](#comparison)
- [Display](#display)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Hardware-accelerated** | Every arithmetic operation maps to a single Field ALU command — no software bignum fallback. |
| **Address-based API** | All operands are 32-byte RAM buffers (little-endian). Words take addresses, not values. |
| **Four built-in primes** | Curve25519 (`2^255 − 19`), secp256k1, NIST P-256, plus one user-loadable custom prime. |
| **Thin wrappers** | Core words (`FIELD-ADD`, `FIELD-MUL`, etc.) are 1:1 wrappers over KDOS primitives. |
| **Constant-time comparison** | `FIELD-EQ?` uses hardware `FCEQ` — no timing side-channels. |
| **Not re-entrant** | Single hardware device, one computation at a time. |

---

## Constants

### FIELD-BYTES

```forth
FIELD-BYTES  ( -- 32 )
```

Size of a field element buffer in bytes (256 bits).

---

## Prime Selection

All arithmetic is performed modulo the currently selected prime.
The prime must be selected before any arithmetic operation.

### FIELD-USE-25519

```forth
FIELD-USE-25519  ( -- )
```

Select Curve25519 prime `p = 2^255 − 19`.

### FIELD-USE-SECP

```forth
FIELD-USE-SECP  ( -- )
```

Select secp256k1 prime.

### FIELD-USE-P256

```forth
FIELD-USE-P256  ( -- )
```

Select NIST P-256 prime.

### FIELD-USE-CUSTOM

```forth
FIELD-USE-CUSTOM  ( -- )
```

Select the user-loaded custom prime (see `FIELD-LOAD-PRIME`).

### FIELD-LOAD-PRIME

```forth
FIELD-LOAD-PRIME  ( p-addr pinv-addr -- )
```

Load a custom 256-bit prime and its Montgomery inverse, then select
it as the active prime.  Both `p-addr` and `pinv-addr` point to
32-byte little-endian buffers.  Pass a zero-filled buffer for
`pinv` if Montgomery multiplication is not needed (the ALU falls
back to standard modular reduction).

**Example — Baby Bear prime for STARKs:**
```forth
CREATE _bb-p  32 ALLOT  _bb-p 32 0 FILL
2013265921 _bb-p !

CREATE _bb-inv  32 ALLOT  _bb-inv 32 0 FILL

_bb-p _bb-inv FIELD-LOAD-PRIME   \ now active
```

---

## Buffer Management

### FIELD-BUF

```forth
FIELD-BUF  ( "name" -- )
```

Compile-time word.  Creates a named 32-byte field element buffer.

```forth
FIELD-BUF my-element
```

### FIELD-ZERO

```forth
FIELD-ZERO  ( addr -- )
```

Zero all 32 bytes of a field element buffer.

### FIELD-ONE

```forth
FIELD-ONE  ( addr -- )
```

Set a field element to the multiplicative identity (1).  Clears all
bytes then sets byte 0 to 1 (little-endian).

### FIELD-SET-U64

```forth
FIELD-SET-U64  ( u64 addr -- )
```

Store a 64-bit integer as a field element.  Clears all 32 bytes,
then writes the 64-bit value at offset 0 (native 64-bit cell store).

### FIELD-COPY

```forth
FIELD-COPY  ( src dst -- )
```

Copy 32 bytes from `src` to `dst`.

---

## Core Arithmetic

All arithmetic words operate modulo the currently selected prime.
Operands and results are 32-byte buffer addresses.

### FIELD-ADD

```forth
FIELD-ADD  ( a b r -- )
```

`r = (a + b) mod p`.

### FIELD-SUB

```forth
FIELD-SUB  ( a b r -- )
```

`r = (a − b) mod p`.  Wraps into positive range if `a < b`.

### FIELD-MUL

```forth
FIELD-MUL  ( a b r -- )
```

`r = (a × b) mod p`.

### FIELD-SQR

```forth
FIELD-SQR  ( a r -- )
```

`r = a² mod p`.  More efficient than `a a r FIELD-MUL` — the
hardware avoids loading operand B.

### FIELD-INV

```forth
FIELD-INV  ( a r -- )
```

`r = a^(p−2) mod p` (Fermat's little theorem inversion).
Undefined for `a = 0`.

### FIELD-NEG

```forth
FIELD-NEG  ( a r -- )
```

`r = (0 − a) mod p` — the additive inverse.  `a + neg(a) = 0`.

### FIELD-MAC

```forth
FIELD-MAC  ( a b r -- )
```

Multiply-accumulate: `r += (a × b) mod p`.  Accumulates into the
hardware result register, then copies out.

---

## Exponentiation

### FIELD-POW

```forth
FIELD-POW  ( a exp r -- )
```

`r = a^exp mod p`.  `exp` is a 32-byte buffer address containing the
256-bit exponent (little-endian).

**Example — Fermat's little theorem:**
```forth
FIELD-USE-25519
FIELD-BUF base   3 base FIELD-SET-U64
FIELD-BUF exp    \ p - 1
FIELD-BUF result

base exp result FIELD-POW
\ result = 3^(p-1) mod p = 1
```

---

## Raw Multiply

These return 512-bit results without modular reduction.

### FIELD-MUL-RAW

```forth
FIELD-MUL-RAW  ( a b rlo rhi -- )
```

512-bit raw product: `{rhi, rlo} = a × b`.  Both `rlo` and `rhi`
are 32-byte buffer addresses.  No modular reduction is applied.

### FIELD-MAC-RAW

```forth
FIELD-MAC-RAW  ( a b rlo rhi -- )
```

512-bit multiply-accumulate: `{rhi, rlo} += a × b`.

---

## Comparison

### FIELD-EQ?

```forth
FIELD-EQ?  ( a b -- flag )
```

Constant-time equality test.  Returns `TRUE` (-1) if `a = b`,
`FALSE` (0) otherwise.  Uses the hardware `FCEQ` instruction —
no timing side-channel.

### FIELD-ZERO?

```forth
FIELD-ZERO?  ( a -- flag )
```

Test if a field element is zero.  Returns `TRUE` (-1) if all 32
bytes are zero, `FALSE` (0) otherwise.

---

## Display

### FIELD.

```forth
FIELD.  ( addr -- )
```

Print a 256-bit field element as 64 hexadecimal characters
(big-endian, most significant byte first).

```forth
FIELD-BUF x   42 x FIELD-SET-U64
x FIELD.
\ prints: 000000000000000000000000000000000000000000000000000000000000002a
```

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `FIELD-BYTES` | `( -- 32 )` | Element size in bytes |
| `FIELD-USE-25519` | `( -- )` | Select Curve25519 prime |
| `FIELD-USE-SECP` | `( -- )` | Select secp256k1 prime |
| `FIELD-USE-P256` | `( -- )` | Select P-256 prime |
| `FIELD-USE-CUSTOM` | `( -- )` | Select custom prime |
| `FIELD-LOAD-PRIME` | `( p pinv -- )` | Load + select custom prime |
| `FIELD-BUF` | `( "name" -- )` | Create 32-byte element |
| `FIELD-ZERO` | `( addr -- )` | Zero element |
| `FIELD-ONE` | `( addr -- )` | Set to 1 |
| `FIELD-SET-U64` | `( u64 addr -- )` | Store 64-bit value |
| `FIELD-COPY` | `( src dst -- )` | Copy element |
| `FIELD-ADD` | `( a b r -- )` | Modular add |
| `FIELD-SUB` | `( a b r -- )` | Modular subtract |
| `FIELD-MUL` | `( a b r -- )` | Modular multiply |
| `FIELD-SQR` | `( a r -- )` | Modular square |
| `FIELD-INV` | `( a r -- )` | Modular inverse |
| `FIELD-POW` | `( a exp r -- )` | Modular exponentiation |
| `FIELD-NEG` | `( a r -- )` | Additive inverse |
| `FIELD-MAC` | `( a b r -- )` | Multiply-accumulate |
| `FIELD-MUL-RAW` | `( a b rlo rhi -- )` | 512-bit raw multiply |
| `FIELD-MAC-RAW` | `( a b rlo rhi -- )` | 512-bit raw MAC |
| `FIELD-EQ?` | `( a b -- flag )` | Constant-time equality |
| `FIELD-ZERO?` | `( a -- flag )` | Test if zero |
| `FIELD.` | `( addr -- )` | Print as hex |
