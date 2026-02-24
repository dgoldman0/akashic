# akashic-fp16-ext — Extended FP16 Operations for KDOS / Megapad-64

Comparisons, linear interpolation, reciprocal, division, square root,
floor/frac, clamping, and FP16 ↔ 16.16 fixed-point conversions.
Built on top of `fp16.f`.

```forth
REQUIRE fp16-ext.f
```

`PROVIDED akashic-fp16-ext` — safe to include multiple times.
Auto-loads `fp16.f` via REQUIRE.

---

## Table of Contents

- [Comparisons](#comparisons)
- [Interpolation & Clamping](#interpolation--clamping)
- [Reciprocal & Division](#reciprocal--division)
- [Square Root](#square-root)
- [Floor & Fractional Part](#floor--fractional-part)
- [FP16 ↔ Fixed-Point Conversion](#fp16--fixed-point-conversion)
- [Quick Reference](#quick-reference)

---

## Comparisons

FP16 comparison uses a sort-key mapping that converts IEEE 754
sign-magnitude representation to an integer ordering:

- Negative values: `key = 0xFFFF XOR raw` (most negative → smallest key)
- Positive values: `key = raw + 0x8000` (positive > all negatives)
- Both ±0 canonicalize to the same key

| Word | Stack | Description |
|---|---|---|
| `FP16-LT` | `( a b -- flag )` | True if $a < b$ |
| `FP16-GT` | `( a b -- flag )` | True if $a > b$ |
| `FP16-LE` | `( a b -- flag )` | True if $a \le b$ |
| `FP16-GE` | `( a b -- flag )` | True if $a \ge b$ |
| `FP16-EQ` | `( a b -- flag )` | True if $a = b$ (±0 compare equal) |

```forth
0x3C00 0x4000 FP16-LT .   \ 1.0 < 2.0 → -1 (true)
```

---

## Interpolation & Clamping

### FP16-LERP

```forth
FP16-LERP  ( a b t -- result )
```

Linear interpolation: $\text{result} = a + t \cdot (b - a)$.

Implemented via FMA: computes $(b-a)$, then `FP16-FMA` for
$(b-a) \times t + a$ — single-pass, no intermediate rounding.

### FP16-CLAMP

```forth
FP16-CLAMP  ( x lo hi -- clamped )
```

Clamp `x` to the range $[\text{lo}, \text{hi}]$:
$\max(\min(x, \text{hi}), \text{lo})$.

---

## Reciprocal & Division

### FP16-RECIP

```forth
FP16-RECIP  ( a -- 1/a )
```

Reciprocal via Newton-Raphson iteration.

**Algorithm:**
1. Extract sign, work with $|a|$.
2. Initial estimate: `0x7800 - |a|` (log-linear, exact for powers of 2).
3. Two Newton iterations: $r' = r \cdot (2 - a \cdot r)$.
4. Restore sign.

Achieves full 10-bit mantissa accuracy (~3 decimal digits).

**Special cases:**
- `RECIP(0)` → `+INF` (or `−INF` for `−0`)
- `RECIP(INF)` → `+0`

### FP16-DIV

```forth
FP16-DIV  ( a b -- a/b )
```

Division: $a / b = a \times \text{recip}(b)$.

---

## Square Root

```forth
FP16-SQRT  ( a -- sqrt[a] )
```

Square root via Newton-Raphson.

**Algorithm:**
1. Initial estimate: `(x >> 1) + 0x1C00` (halved exponent).
2. Two Newton iterations: $s' = 0.5 \cdot (s + x/s)$.
3. Final ULP correction: if $s^2 > x$, subtract 1 ULP.

**Special cases:**
- `SQRT(0)` → `0`
- `SQRT(negative)` → `QNAN`
- `SQRT(INF)` → `INF`

---

## Floor & Fractional Part

### FP16-FLOOR

```forth
FP16-FLOOR  ( a -- floor )
```

Floor to integral FP16 value.  Truncates toward zero via
`FP16>INT INT>FP16`, then adjusts negative non-integers by
subtracting 1.0.

### FP16-FRAC

```forth
FP16-FRAC  ( a -- frac )
```

Fractional part: $a - \lfloor a \rfloor$.  Always non-negative.

---

## FP16 ↔ Fixed-Point Conversion

### FP16>FX

```forth
FP16>FX  ( fp16 -- fx )
```

Convert FP16 to 16.16 fixed-point by extracting sign, exponent,
and mantissa, then shifting the 11-bit mantissa (1.10 format) to
align with the 16.16 format: shift amount = $\text{exp} - 9$.

**Special cases:**
- ±0 → 0
- ±INF / NaN → `0x7FFFFFFF` (saturate)
- Denormals → 0

### FX>FP16

```forth
FX>FP16  ( fx -- fp16 )
```

Convert 16.16 fixed-point to FP16.  Finds the highest set bit to
determine the exponent ($\text{biased\_exp} = \text{msb} - 1$),
extracts a 10-bit mantissa, and assembles the FP16 bit pattern.

**Overflow:** Values exceeding FP16 max (65504) saturate to `0x7BFF`.

---

## Quick Reference

```
FP16-LT     ( a b -- flag )    FP16-RECIP   ( a -- 1/a )
FP16-GT     ( a b -- flag )    FP16-DIV     ( a b -- a/b )
FP16-LE     ( a b -- flag )    FP16-SQRT    ( a -- sqrt )
FP16-GE     ( a b -- flag )    FP16-FLOOR   ( a -- floor )
FP16-EQ     ( a b -- flag )    FP16-FRAC    ( a -- frac )
FP16-LERP   ( a b t -- r )    FP16>FX      ( fp16 -- fx )
FP16-CLAMP  ( x lo hi -- r )  FX>FP16      ( fx -- fp16 )
```
