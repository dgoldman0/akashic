# akashic-ntt — NTT Polynomial Arithmetic (Hardware NTT Engine)

256-point Number Theoretic Transform over 32-bit prime fields.
Delegates all computation to the hardware NTT engine at MMIO
`0xFFFF_FF00_0000_08C0` (Python device `NTTDevice`), which provides
forward/inverse NTT via Cooley-Tukey butterfly, plus pointwise
multiply and add in the NTT domain.

```forth
REQUIRE ntt.f
```

`PROVIDED akashic-ntt` — no dependencies.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Modulus Selection](#modulus-selection)
- [Polynomial Buffers](#polynomial-buffers)
- [Coefficient Access](#coefficient-access)
- [Transforms](#transforms)
- [Polynomial Multiply](#polynomial-multiply)
- [Pointwise Operations](#pointwise-operations)
- [Display](#display)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Hardware-accelerated** | Forward/inverse NTT and pointwise operations execute on a dedicated 256-point engine — no software butterfly loops. |
| **Fixed degree 256** | Polynomials are always 256 coefficients × 4 bytes (32-bit, little-endian). |
| **Cyclic convolution** | `NTT-POLY-MUL` computes products modulo `x^256 − 1`. For degree < 128 inputs, this equals standard polynomial multiplication. |
| **Modulus constraint** | The prime `q` must satisfy `(q − 1) mod 256 == 0` so a primitive 256th root of unity exists. |
| **Thin wrappers** | Core words are thin wrappers over KDOS/BIOS NTT primitives with buffer-load/store management. |
| **Not re-entrant** | Single hardware device, one transform at a time. |

---

## Constants

### NTT-N

```forth
NTT-N  ( -- 256 )
```

Fixed polynomial degree.  All polynomials have exactly 256
coefficients, indexed 0–255.

### NTT-BYTES

```forth
NTT-BYTES  ( -- 1024 )
```

Buffer size in bytes: 256 coefficients × 4 bytes each.

### NTT-Q-KYBER

```forth
NTT-Q-KYBER  ( -- 3329 )
```

ML-KEM (Kyber) modulus.  `(3329 − 1) mod 256 == 0` ✓.

### NTT-Q-DILITHIUM

```forth
NTT-Q-DILITHIUM  ( -- 8380417 )
```

ML-DSA (Dilithium) modulus.  `(8380417 − 1) mod 256 == 0` ✓.

### NTT-Q-STARK

```forth
NTT-Q-STARK  ( -- 2013265921 )
```

Baby Bear prime for STARKs.  `p = 2^31 − 2^27 + 1`.
`(p − 1) = 2^27 × 15`, so `256 | (p − 1)` ✓.  Fits in 32 bits.
Widely used in STARK literature (Plonky2, RISC Zero).

---

## Modulus Selection

The modulus must be set before any transform or multiply operation.
Switching modulus between operations is allowed.

### NTT-SET-MOD

```forth
NTT-SET-MOD  ( q -- )
```

Set the NTT modulus to `q`.  Triggers an internal root-of-unity
recomputation on the hardware device.  `q` must be prime and must
satisfy `(q − 1) mod 256 == 0`.

**Example:**
```forth
NTT-Q-KYBER NTT-SET-MOD       \ select Kyber modulus
NTT-Q-STARK NTT-SET-MOD       \ switch to Baby Bear
```

---

## Polynomial Buffers

Polynomials are stored in contiguous 1024-byte RAM buffers:
256 coefficients, each a 32-bit little-endian integer at offset
`index × 4`.

### NTT-POLY

```forth
NTT-POLY  ( "name" -- )
```

Compile-time word.  Creates a named 1024-byte polynomial buffer.

```forth
NTT-POLY my-poly
```

### NTT-POLY-ZERO

```forth
NTT-POLY-ZERO  ( addr -- )
```

Zero all 256 coefficients (fills 1024 bytes with 0x00).

### NTT-POLY-COPY

```forth
NTT-POLY-COPY  ( src dst -- )
```

Copy 1024 bytes from `src` to `dst`.

---

## Coefficient Access

Individual coefficients are 32-bit unsigned integers.  Indices
range from 0 to 255.

### NTT-COEFF@

```forth
NTT-COEFF@  ( idx addr -- val )
```

Read the 32-bit coefficient at index `idx` from polynomial buffer
`addr`.

### NTT-COEFF!

```forth
NTT-COEFF!  ( val idx addr -- )
```

Write 32-bit value `val` at index `idx` in polynomial buffer `addr`.
Writes exactly 4 bytes (little-endian), preserving adjacent
coefficients.

**Example:**
```forth
NTT-POLY my-p
my-p NTT-POLY-ZERO
42 0 my-p NTT-COEFF!    \ coeff[0] = 42
7  1 my-p NTT-COEFF!    \ coeff[1] = 7
0 my-p NTT-COEFF@ .     \ prints 42
```

---

## Transforms

In-place transforms: the polynomial buffer is overwritten with the
transformed result.

### NTT-FORWARD

```forth
NTT-FORWARD  ( addr -- )
```

In-place forward NTT.  Loads the 256-coefficient polynomial from
`addr` into the hardware engine, executes the forward butterfly
transform, and stores the result back to `addr`.

After this call, `addr` contains the NTT-domain representation.

### NTT-INVERSE

```forth
NTT-INVERSE  ( addr -- )
```

In-place inverse NTT.  Loads the NTT-domain polynomial from `addr`,
executes the inverse butterfly with `1/N` scaling, and stores the
time-domain result back to `addr`.

**Identity property:**
```forth
NTT-Q-KYBER NTT-SET-MOD
NTT-POLY p
\ ... fill p with coefficients ...
p NTT-FORWARD  p NTT-INVERSE
\ p now contains the original coefficients
```

---

## Polynomial Multiply

### NTT-POLY-MUL

```forth
NTT-POLY-MUL  ( a b r -- )
```

Full polynomial multiply: `r = a × b mod q`, computed as cyclic
convolution modulo `x^256 − 1`.

Internally executes the complete NTT pipeline:
1. Forward NTT of `a`
2. Forward NTT of `b`
3. Pointwise multiply in NTT domain
4. Inverse NTT of product → `r`

The modulus must be set via `NTT-SET-MOD` before calling.
Input buffers `a` and `b` are not modified.

**Example — multiply (1 + 2x)(3 + 4x) = 3 + 10x + 8x²:**
```forth
NTT-Q-KYBER NTT-SET-MOD
NTT-POLY pa  NTT-POLY pb  NTT-POLY pr
pa NTT-POLY-ZERO  pb NTT-POLY-ZERO
1 0 pa NTT-COEFF!  2 1 pa NTT-COEFF!   \ pa = 1 + 2x
3 0 pb NTT-COEFF!  4 1 pb NTT-COEFF!   \ pb = 3 + 4x
pa pb pr NTT-POLY-MUL
0 pr NTT-COEFF@ .    \ 3
1 pr NTT-COEFF@ .    \ 10
2 pr NTT-COEFF@ .    \ 8
```

**Cyclic wrap-around:**  Since multiplication is modulo `x^256 − 1`,
the product of `x^255 × x = x^256 ≡ 1`.

---

## Pointwise Operations

These operate on polynomials already in the NTT domain.  Useful for
manual transform pipelines (e.g., accumulating multiple products
without repeated forward transforms).

### NTT-POINTWISE-MUL

```forth
NTT-POINTWISE-MUL  ( a b r -- )
```

`r[i] = a[i] × b[i] mod q` for `i = 0..255`.

All three buffers `a`, `b`, `r` should contain NTT-domain data.
To get a time-domain result, apply `NTT-INVERSE` to `r` afterward.

### NTT-POINTWISE-ADD

```forth
NTT-POINTWISE-ADD  ( a b r -- )
```

`r[i] = (a[i] + b[i]) mod q` for `i = 0..255`.

**Example — manual pipeline for polynomial addition:**
```forth
NTT-Q-KYBER NTT-SET-MOD
NTT-POLY a  NTT-POLY b  NTT-POLY r
\ ... fill a and b ...
a NTT-FORWARD  b NTT-FORWARD
a b r NTT-POINTWISE-ADD
r NTT-INVERSE
\ r now contains a + b (coefficient-wise mod q)
```

---

## Display

### NTT-POLY.

```forth
NTT-POLY.  ( addr n -- )
```

Print the first `n` coefficients of polynomial `addr`, separated
by spaces.  Uses decimal output (current `BASE`).

```forth
my-poly 4 NTT-POLY.    \ prints: 3 10 8 0
```

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `NTT-N` | `( -- 256 )` | Polynomial degree |
| `NTT-BYTES` | `( -- 1024 )` | Buffer size in bytes |
| `NTT-Q-KYBER` | `( -- 3329 )` | Kyber modulus |
| `NTT-Q-DILITHIUM` | `( -- 8380417 )` | Dilithium modulus |
| `NTT-Q-STARK` | `( -- 2013265921 )` | Baby Bear prime (STARKs) |
| `NTT-SET-MOD` | `( q -- )` | Set NTT modulus |
| `NTT-POLY` | `( "name" -- )` | Create polynomial buffer |
| `NTT-POLY-ZERO` | `( addr -- )` | Zero polynomial |
| `NTT-POLY-COPY` | `( src dst -- )` | Copy polynomial |
| `NTT-COEFF@` | `( idx addr -- val )` | Read coefficient |
| `NTT-COEFF!` | `( val idx addr -- )` | Write coefficient |
| `NTT-FORWARD` | `( addr -- )` | In-place forward NTT |
| `NTT-INVERSE` | `( addr -- )` | In-place inverse NTT |
| `NTT-POLY-MUL` | `( a b r -- )` | Polynomial multiply |
| `NTT-POINTWISE-MUL` | `( a b r -- )` | Pointwise multiply |
| `NTT-POINTWISE-ADD` | `( a b r -- )` | Pointwise add |
| `NTT-POLY.` | `( addr n -- )` | Print first n coefficients |

---

## KDOS/BIOS Primitives

Words used from the KDOS/BIOS layer (not part of the public API):

| Primitive | Stack | Layer |
|---|---|---|
| `NTT-SETQ` | `( q -- )` | BIOS |
| `NTT-IDX!` | `( idx -- )` | BIOS |
| `NTT-LOAD` | `( addr buf -- )` | BIOS |
| `NTT-STORE` | `( addr -- )` | BIOS |
| `NTT-FWD` | `( -- )` | BIOS |
| `NTT-INV` | `( -- )` | BIOS |
| `NTT-PMUL` | `( -- )` | BIOS |
| `NTT-PADD` | `( -- )` | BIOS |
| `NTT-STATUS@` | `( -- n )` | BIOS |
| `NTT-WAIT` | `( -- )` | BIOS |
| `NTT-BUF-A` | `( -- 0 )` | KDOS |
| `NTT-BUF-B` | `( -- 1 )` | KDOS |
| `NTT-POLYMUL` | `( a b r -- )` | KDOS |

---

## Hardware Register Map

NTT engine at base `0xFFFF_FF00_0000_08C0`:

| Offset | Name | R/W | Width | Description |
|---|---|---|---|---|
| `+0x00` | STATUS | R | 1 | `bit 0` = busy, `bit 1` = done |
| `+0x08` | Q | RW | 8 | 64-bit modulus (little-endian byte write) |
| `+0x10` | IDX | RW | 2 | Coefficient index (auto-increments on 4th byte) |
| `+0x18` | LOAD_A | W | 4 | Write 4 bytes → poly A at current IDX |
| `+0x1C` | LOAD_B | W | 4 | Write 4 bytes → poly B at current IDX |
| `+0x20` | RESULT | R | 4 | Read 4 bytes ← result at current IDX |
| `+0x28` | CMD | W | 1 | `0x01` FWD, `0x03` INV, `0x05` PMUL, `0x07` PADD |
