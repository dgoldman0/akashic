# akashic-baby-bear — Baby Bear Field Arithmetic + Batch Inversion

Baby Bear prime field ($q = 2013265921 = 15 \times 2^{27} + 1$) with
Montgomery's batch inversion trick.  Used by STARKs, NTT domain
arithmetic, and any application over the Baby Bear field.

```forth
REQUIRE baby-bear.f
```

`PROVIDED akashic-baby-bear` — no dependencies.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Field Arithmetic](#field-arithmetic)
- [Packed 32-bit Array Access](#packed-32-bit-array-access)
- [Batch Inversion](#batch-inversion)
- [Usage Example](#usage-example)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Baby Bear prime** | $q = 2013265921 = 15 \times 2^{27} + 1$.  NTT-friendly: $(q-1) \bmod 256 = 0$, so primitive 256th roots of unity exist. |
| **64-bit Forth cells** | Products $a \times b$ fit in a single cell for $a, b < 2^{31}$.  No overflow risk. |
| **Fermat inversion** | $a^{-1} = a^{q-2} \bmod q$ via binary exponentiation (~46 multiplications). |
| **Montgomery's batch trick** | $n$ inversions in $3(n-1)$ multiplications + 1 Fermat inversion, vs $n \times 46$ multiplications individually. |
| **In-place safe** | `BB-BATCH-INV` works correctly when `src == dst`. |
| **Packed 32-bit arrays** | Values stored as 4-byte little-endian in byte-addressed memory, matching the NTT engine's coefficient format. |
| **Not re-entrant** | Shared scratch buffers and variables. |

---

## Constants

### BB-Q

```forth
BB-Q  ( -- 2013265921 )
```

The Baby Bear prime.

---

## Field Arithmetic

### BB+

```forth
BB+  ( a b -- r )
```

Modular addition: $r = (a + b) \bmod q$.

### BB-

```forth
BB-  ( a b -- r )
```

Modular subtraction: $r = (a - b) \bmod q$.  Always returns a
value in $[0, q)$.

### BB\*

```forth
BB*  ( a b -- r )
```

Modular multiplication: $r = (a \times b) \bmod q$.

### BB-POW

```forth
BB-POW  ( base exp -- result )
```

Modular exponentiation via binary square-and-multiply.
Computes $\text{base}^{\text{exp}} \bmod q$.

### BB-INV

```forth
BB-INV  ( a -- 1/a )
```

Modular inverse via Fermat's little theorem:
$a^{-1} = a^{q-2} \bmod q$.  Undefined for $a = 0$.

---

## Packed 32-bit Array Access

### BB-W32!

```forth
BB-W32!  ( val addr -- )
```

Write `val` as 4-byte little-endian at `addr`.

### BB-W32@

```forth
BB-W32@  ( addr -- val )
```

Read 4-byte little-endian from `addr`, masked to 32 bits.

These match the NTT engine's coefficient storage format.
Use them to build packed arrays for `BB-BATCH-INV`.

---

## Batch Inversion

### BB-BATCH-INV

```forth
BB-BATCH-INV  ( src dst n -- )
```

Compute the modular inverse of `n` packed 32-bit Baby Bear values.
Reads from `src`, writes results to `dst`.  `src` and `dst` may
be the same buffer (in-place).

**Algorithm** (Montgomery's trick):

1. **Forward sweep:** build prefix products
   - $\text{prefix}[0] = \text{src}[0]$
   - $\text{prefix}[i] = \text{prefix}[i-1] \times \text{src}[i]$

2. **Single inversion:** $\text{inv} = \text{prefix}[n-1]^{-1}$

3. **Backward sweep:** extract individual inverses
   - For $i = n-1$ down to $1$:
     - $\text{dst}[i] = \text{inv} \times \text{prefix}[i-1]$
     - $\text{inv} = \text{inv} \times \text{src}[i]$
   - $\text{dst}[0] = \text{inv}$

**Cost:** $3(n-1)$ multiplications + 1 Fermat inversion (~46 muls)
$\approx 3n + 43$ muls total, vs $46n$ muls for individual inversions.

**Scratch:** internal prefix buffer supports up to 1024 values.

```forth
CREATE vals 16 ALLOT
CREATE invs 16 ALLOT
7 vals BB-W32!   42 vals 4 + BB-W32!
99 vals 8 + BB-W32!   5 vals 12 + BB-W32!
vals invs 4 BB-BATCH-INV
\ invs now contains the 4 inverses
```

---

## Usage Example

Batch-invert 256 coset denominators for a STARK prover:

```forth
\ Assume denom-buf holds 256 packed Baby Bear denominators
CREATE inv-buf 1024 ALLOT
denom-buf inv-buf 256 BB-BATCH-INV

\ Verify: denom[0] * inv[0] should be 1
denom-buf BB-W32@  inv-buf BB-W32@  BB*  .  \ prints 1
```

Single-value arithmetic:

```forth
\ Compute 3^{20} mod q
3 20 BB-POW .           \ 486784380

\ Verify inverse
42 DUP BB-INV BB* .     \ 1
```

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `BB-Q` | `( -- 2013265921 )` | Baby Bear prime |
| `BB+` | `( a b -- r )` | Modular addition |
| `BB-` | `( a b -- r )` | Modular subtraction |
| `BB*` | `( a b -- r )` | Modular multiplication |
| `BB-POW` | `( base exp -- r )` | Modular exponentiation |
| `BB-INV` | `( a -- 1/a )` | Modular inverse (Fermat) |
| `BB-W32!` | `( val addr -- )` | Write 4-byte LE |
| `BB-W32@` | `( addr -- val )` | Read 4-byte LE |
| `BB-BATCH-INV` | `( src dst n -- )` | Batch-invert n values |
