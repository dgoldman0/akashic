# akashic-fixed — 16.16 Fixed-Point Arithmetic for KDOS / Megapad-64

Deterministic 16.16 signed fixed-point math using the integer ALU.
No tile engine dependency — pure integer operations.  Ideal for
pixel-exact rendering, physics, and animation where reproducibility
matters.

```forth
REQUIRE fixed.f
```

`PROVIDED akashic-fixed` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Representation](#representation)
- [Constants](#constants)
- [Conversions](#conversions)
- [Arithmetic](#arithmetic)
- [Rounding & Fractional](#rounding--fractional)
- [Min / Max / Clamp](#min--max--clamp)
- [Linear Interpolation](#linear-interpolation)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Pure integer math** | No tile engine, no FP16 dependency. Works on any core. |
| **64-bit intermediates** | On Megapad-64's 64-bit cells, `FX*` computes `a * b` without overflow for values in ±32767.9999. |
| **No hidden state** | All operations are stack-only. No VARIABLEs needed. |
| **Two multiply variants** | `FX*` (truncating) for speed, `FX*R` (rounded) for accuracy in accumulation chains. |

---

## Representation

A 16.16 fixed-point value is a signed 64-bit integer where the low
16 bits represent the fractional part:

$$\text{value} = \frac{\text{raw}}{65536}$$

| Range | Raw Value |
|---|---|
| 0.0 | 0 |
| 0.5 | 32768 |
| 1.0 | 65536 |
| −1.0 | −65536 |
| Max ≈ 32767.9999 | 2147483647 |

---

## Constants

| Word | Value | Description |
|---|---|---|
| `FX-ONE` | 65536 | 1.0 |
| `FX-HALF` | 32768 | 0.5 |
| `FX-ZERO` | 0 | 0.0 |

---

## Conversions

| Word | Stack | Description |
|---|---|---|
| `INT>FX` | `( n -- fx )` | `n << 16` — integer to fixed-point |
| `FX>INT` | `( fx -- n )` | `fx / 65536` — truncate to integer |

```forth
3 INT>FX .   \ → 196608
196608 FX>INT .   \ → 3
```

---

## Arithmetic

### FX*

```forth
FX*  ( a b -- a*b )
```

Truncating fixed multiply: $(a \times b) / 65536$.  The division
truncates toward zero.  Fast, but repeated application can
accumulate drift.

### FX*R

```forth
FX*R  ( a b -- a*b )
```

Rounded fixed multiply: $(a \times b + 32768) / 65536$.  Adds
half a unit before dividing (half-up rounding).  Reduces drift in
long accumulation chains — animation, filter coefficients, iterative
geometry.

### FX/

```forth
FX/  ( a b -- a/b )
```

Fixed divide: $(a \ll 16) / b$.

### FX-ABS / FX-NEG / FX-SIGN

| Word | Stack | Description |
|---|---|---|
| `FX-ABS` | `( a -- \|a\| )` | Absolute value |
| `FX-NEG` | `( a -- -a )` | Negate |
| `FX-SIGN` | `( a -- -1\|0\|1 )` | Sign indicator |

---

## Rounding & Fractional

| Word | Stack | Description |
|---|---|---|
| `FX-FRAC` | `( fx -- fx )` | Fractional part. Always ≥ 0. For negative values: $1.0 - (|x| \bmod 1.0)$. |
| `FX-FLOOR` | `( fx -- fx )` | Round toward $-\infty$. Clears low 16 bits (works for negatives via two's complement). |
| `FX-CEIL` | `( fx -- fx )` | Round toward $+\infty$. If fractional part is non-zero, rounds up. |
| `FX-ROUND` | `( fx -- fx )` | Round to nearest integer (half rounds up): `FX-HALF + FX-FLOOR`. |

```forth
\ 1.5 = 98304 in 16.16
98304 FX-FLOOR .    \ → 65536  (1.0)
98304 FX-CEIL .     \ → 131072 (2.0)
98304 FX-ROUND .    \ → 131072 (2.0)
98304 FX-FRAC .     \ → 32768  (0.5)
```

---

## Min / Max / Clamp

| Word | Stack | Description |
|---|---|---|
| `FX-MIN` | `( a b -- min )` | Smaller of two values |
| `FX-MAX` | `( a b -- max )` | Larger of two values |
| `FX-CLAMP` | `( x lo hi -- clamped )` | Clamp to $[\text{lo}, \text{hi}]$ |

---

## Linear Interpolation

```forth
FX-LERP  ( a b t -- result )
```

Linear interpolation: $a + t \cdot (b - a)$, where $t$ is a 16.16
value in $[0, \text{FX-ONE}]$.

```forth
0  655360  32768  FX-LERP .   \ LERP(0, 10.0, 0.5) → 327680 (5.0)
```

---

## Quick Reference

```
INT>FX      ( n -- fx )          FX-FRAC    ( fx -- fx )
FX>INT      ( fx -- n )          FX-FLOOR   ( fx -- fx )
FX*         ( a b -- a*b )       FX-CEIL    ( fx -- fx )
FX*R        ( a b -- a*b )       FX-ROUND   ( fx -- fx )
FX/         ( a b -- a/b )       FX-MIN     ( a b -- min )
FX-ABS      ( a -- |a| )        FX-MAX     ( a b -- max )
FX-NEG      ( a -- -a )         FX-CLAMP   ( x lo hi -- r )
FX-SIGN     ( a -- -1|0|1 )     FX-LERP    ( a b t -- r )
```
