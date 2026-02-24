# akashic-accum — 48.16 Fixed-Point Accumulators for KDOS / Megapad-64

Extended-precision accumulators for numerically stable summation
across tile-engine passes.  Each accumulator stores a 48.16 signed
fixed-point running sum (48 integer bits, 16 fractional bits) in a
single 64-bit Forth cell — no intermediate rounding, no catastrophic
cancellation.

```forth
REQUIRE accum.f
```

`PROVIDED akashic-accum` — safe to include multiple times.
Auto-loads `fp32.f` via `REQUIRE`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Context Layout](#context-layout)
- [Initialisation](#initialisation)
- [Accumulation](#accumulation)
- [Extraction](#extraction)
- [Typical Pipeline](#typical-pipeline)
- [Precision Budget](#precision-budget)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **No rounding during accumulation** | FP32 inputs are converted to exact 48.16 integers before addition — the sum is exact as long as values share a compatible scale. |
| **48-bit integer range** | Sums up to ±140 trillion (2⁴⁷ − 1), far beyond FP32's ~16 million contiguous integers. |
| **16 fractional bits** | Preserves sub-integer precision for values like 0.5, enabling accurate mean computation from FP16 data. |
| **Zero-copy tile readout** | `ACCUM-ADD-TILE` reads the tile engine's hardware FP32 accumulator (ACC@) and folds it directly into the running sum. |
| **Context-based API** | Accumulator state lives in user-allocated memory, allowing multiple independent accumulators. |

---

## Context Layout

Each accumulator context is 16 bytes (2 cells):

| Offset | Size | Content |
|---|---|---|
| +0 | 8 bytes | Sum (signed 48.16 fixed-point) |
| +8 | 8 bytes | Reserved (available for count / stats layer) |

A default context is provided for convenience:

```forth
ACCUM-CTX   ( -- addr )   \ pre-allocated 16-byte context
```

Create additional contexts with:

```forth
CREATE MY-ACCUM 16 ALLOT
MY-ACCUM ACCUM-INIT
```

---

## Initialisation

```forth
ACCUM-INIT   ( ctx -- )   \ zero sum and reserved fields
ACCUM-RESET  ( ctx -- )   \ alias for ACCUM-INIT
```

---

## Accumulation

### ACCUM-ADD-FP32

```forth
ACCUM-ADD-FP32  ( ctx fp32 -- )
```

Convert an IEEE 754 binary32 value to 48.16 fixed-point, then add
to the running sum.  The conversion is exact for all normal FP32
values in the representable 48.16 range.

### ACCUM-SUB-FP32

```forth
ACCUM-SUB-FP32  ( ctx fp32 -- )
```

Subtract an FP32 value from the running sum (negate then add).

### ACCUM-ADD-TILE / ACCUM-ADD-TILE1

```forth
ACCUM-ADD-TILE   ( ctx -- )   \ reads ACC@ (CSR 0x19)
ACCUM-ADD-TILE1  ( ctx -- )   \ reads ACC1@ (CSR 0x1A)
```

Read the tile engine's hardware FP32 accumulator register, convert
to 48.16, and add to the running sum.  Use after TSUM, TSUMSQ, TDOT,
or any tile reduction that deposits its result in ACC0/ACC1.

---

## Extraction

| Word | Stack | Description |
|---|---|---|
| `ACCUM-GET-RAW` | `( ctx -- raw )` | Raw 48.16 value (1.0 = 65536) |
| `ACCUM-GET-INT` | `( ctx -- n )` | Integer part only (raw ≫ 16, truncation) |
| `ACCUM-GET-FP32` | `( ctx -- fp32 )` | Convert sum to IEEE 754 binary32 |
| `ACCUM-GET-FP16` | `( ctx -- fp16 )` | Convert sum to FP16 (via FP32, then narrow) |

```forth
ACCUM-CTX ACCUM-GET-INT .    \ print integer part of accumulated sum
ACCUM-CTX ACCUM-GET-FP32 .   \ print FP32 bit pattern of sum
```

---

## Typical Pipeline

Process 1024 FP16 values in 32-element tile passes, accumulating
the sum in extended precision:

```forth
ACCUM-CTX ACCUM-INIT
32 0 DO                         \ 32 tiles × 32 lanes = 1024 values
    I 6 LSHIFT data + _FP16-TA @ TILE-LOAD
    TSUM                        \ FP32 partial sum → ACC0
    ACCUM-CTX ACCUM-ADD-TILE    \ fold into 48.16 running sum
LOOP
ACCUM-CTX ACCUM-GET-FP32       \ final sum as FP32
```

---

## Precision Budget

| Stage | Format | Precision | Range |
|---|---|---|---|
| Input data | FP16 | 3.3 digits | ±65504 |
| Tile reduction | FP32 (hardware) | 7.2 digits | ±3.4 × 10³⁸ |
| Cross-tile accumulation | 48.16 (integer) | exact | ±1.4 × 10¹⁴ |
| Final output | FP32 (software) | 7.2 digits | ±3.4 × 10³⁸ |

The 48.16 integer accumulation eliminates all rounding during the
most error-sensitive phase — summing hundreds or thousands of FP32
partial results.

---

## Internals

### Conversion Helpers

| Word | Stack | Description |
|---|---|---|
| `_ACCUM-FP32>FX48` | `( fp32 -- fx48 )` | FP32 → signed 48.16 integer |
| `_ACCUM-FX48>FP32` | `( fx48 -- fp32 )` | Signed 48.16 → FP32 (find MSB, pack) |

### FP32 → 48.16 Algorithm

1. Extract sign, exponent (unbias: $e = \text{biased} - 127$), and
   24-bit mantissa (with implicit 1).
2. Shift amount = $e - 7$ (places the binary point at bit 16).
3. If shift ≥ 0: left-shift mantissa.  If shift < 0: right-shift.
4. Apply sign.

### 48.16 → FP32 Algorithm

1. Take absolute value, record sign.
2. Find MSB position $p$ (0-based).
3. Biased exponent = $p + 111$ (accounts for 48.16 → real scaling).
4. Extract 23-bit mantissa by shifting relative to MSB.
5. Pack sign, exponent, mantissa.

### Module Variables

| Variable | Purpose |
|---|---|
| `_AC-SIGN` | Sign of current FP32 being converted |
| `_AC-EXP` | Unbiased exponent during conversion |
| `_AC-MANT` | 24-bit mantissa with implicit 1 |
| `_AC-F-SIGN` | Sign during FX48 → FP32 conversion |
| `_AC-F-MAG` | Magnitude during FX48 → FP32 |
| `_AC-F-MSB` | MSB position during FX48 → FP32 |

---

## Quick Reference

```
ACCUM-CTX        ( -- addr )       pre-allocated 16-byte context
ACCUM-INIT       ( ctx -- )        zero the context
ACCUM-RESET      ( ctx -- )        alias for INIT
ACCUM-ADD-FP32   ( ctx fp32 -- )   add FP32 to running sum
ACCUM-SUB-FP32   ( ctx fp32 -- )   subtract FP32 from running sum
ACCUM-ADD-TILE   ( ctx -- )        add ACC@ to running sum
ACCUM-ADD-TILE1  ( ctx -- )        add ACC1@ to running sum
ACCUM-GET-RAW    ( ctx -- raw )    raw 48.16 value
ACCUM-GET-INT    ( ctx -- n )      integer part (truncated)
ACCUM-GET-FP32   ( ctx -- fp32 )   sum as FP32
ACCUM-GET-FP16   ( ctx -- fp16 )   sum as FP16
```
