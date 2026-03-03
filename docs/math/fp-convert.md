# akashic-fp-convert — FP32 / FP16 ↔ Q16.16 Fixed-Point Conversions

Bridge module connecting IEEE 754 floating-point (`fp32.f`, `fp16-ext.f`)
with integer fixed-point (`fixed.f`).  Designed for audio filter
coefficient setup: compute biquad coefficients in FP32 for precision,
convert to Q16.16 for a fast integer inner loop.

```forth
REQUIRE fp-convert.f
```

`PROVIDED akashic-fp-convert` — depends on `fp32.f`, `fp16-ext.f`, `fixed.f`.

---

## Table of Contents

- [Design](#design)
- [FP32 ↔ Q16.16](#fp32--q1616)
- [FP16 ↔ Q16.16](#fp16--q1616)
- [Internals](#internals)
- [Examples](#examples)
- [Quick Reference](#quick-reference)

---

## Design

| Principle | Detail |
|---|---|
| **Setup-time only** | These conversions run once per pole / per coefficient, not in the inner loop.  ~50–200 steps each — negligible vs. per-sample cost. |
| **FP32→FX is bit-exact** | Direct bit manipulation (extract sign / exponent / mantissa, integer shift).  No FP arithmetic — no rounding from multiply or divide. |
| **FX→FP32 reuses INT>FP32** | Converts the raw Q16.16 integer to FP32 then divides by 65536.0.  Uses the existing `fp32.f` pipeline. |
| **FP16 via FP32** | `FP16>FX` and `FX>FP16` compose the FP32 words with `FP16>FP32` / `FP32>FP16`.  Precision is limited by FP16's 10-bit mantissa on the FP16 side, not on the Q16.16 side. |

### Range

Q16.16 represents signed values in $[-32768.0, +32767.99998]$ with
resolution $1/65536 \approx 0.0000153$.  Biquad coefficients (typically
in $[-2, +2]$) fit comfortably with 16 fractional bits — far exceeding
FP16's 10-bit mantissa.

### Accuracy

| Direction | Max Error | Notes |
|---|---|---|
| FP32 → Q16.16 | ≤ 1 ULP (of Q16.16) | Truncation toward zero on the final shift |
| Q16.16 → FP32 | ≤ 1 ULP (of FP32) | Via `INT>FP32` + `FP32-DIV` |
| Round-trip FP32→FX→FP32 | ≤ $1/65536 \approx 1.5 \times 10^{-5}$ | Dominated by Q16.16 quantization |
| FP16→FX→FP16 | Bit-exact for tested values | FP16's 10-bit mantissa is a subset of Q16.16's range |

---

## FP32 ↔ Q16.16

### FP32>FX

```forth
FP32>FX  ( fp32 -- fx )
```

Convert an IEEE 754 binary32 bit pattern to Q16.16 fixed-point.

Algorithm — direct bit manipulation, no FP arithmetic:

$$\text{Q16.16} = (-1)^s \times (1.\text{frac}) \times 2^{(\text{exp} - 134)}$$

where $134 = 127 (\text{bias}) + 23 (\text{mantissa bits}) - 16 (\text{fractional bits})$.

| Input | Result |
|---|---|
| `FP32-ZERO` | 0 |
| `FP32-ONE` (0x3F800000) | 65536 |
| 0.5 (0x3F000000) | 32768 |
| −1.0 (0xBF800000) | −65536 |
| NaN | 0 |
| +Inf | 2147483647 (max Q16.16) |
| −Inf | −2147483648 (min Q16.16) |
| Underflow ($|v| < 2^{-24}/65536$) | 0 |

### FX>FP32

```forth
FX>FP32  ( fx -- fp32 )
```

Convert Q16.16 → FP32 bit pattern.  Implemented as:

```forth
INT>FP32  65536.0_fp32  FP32-DIV
```

Returns `FP32-ZERO` for input 0.

---

## FP16 ↔ Q16.16

### FP16>FX

```forth
FP16>FX  ( fp16 -- fx )
```

Convert FP16 → Q16.16 via FP32 intermediate:

```forth
FP16>FP32  FP32>FX
```

### FX>FP16

```forth
FX>FP16  ( fx -- fp16 )
```

Convert Q16.16 → FP16 via FP32 intermediate:

```forth
FX>FP32  FP32>FP16
```

Note: lossy — FP16 has only a 10-bit mantissa.  Suitable for writing
PCM output samples but not for preserving coefficient precision.

---

## Internals

| Symbol | Type | Purpose |
|---|---|---|
| `_FPC-65536` | CONSTANT | FP32 encoding of 65536.0 (`0x47800000`), used by `FX>FP32` |
| `_FPC-S` | VARIABLE | Scratch: sign bit during `FP32>FX` |
| `_FPC-E` | VARIABLE | Scratch: biased exponent during `FP32>FX` |
| `_FPC-M` | VARIABLE | Scratch: 24-bit mantissa (with implicit 1) during `FP32>FX` |
| `_FPC-SH` | VARIABLE | Scratch: shift amount (exp − 134) during `FP32>FX` |

---

## Examples

### Convert a biquad coefficient

```forth
\ na2n = −0.9915 in FP32
0xBF7DD282 FP32>FX   \ → −64979  (Q16.16)

\ Verify: −64979 / 65536 = −0.99153...  ✓
```

### Round-trip a coefficient

```forth
0x3FF66580 FP32>FX    \ 1.925 → 126156
126156     FX>FP32    \ → 0x3FF66580 ≈ 1.92499  (Q16.16 quantization)
```

### FP16 audio sample to Q16.16 and back

```forth
0x3C00 FP16>FX        \ 1.0 → 65536
65536  FX>FP16         \ → 0x3C00  (bit-exact)
```

### One biquad step in Q16.16

```forth
\ y = b0 * x + s1
b0_fx  x_fx  FX*  s1_fx +    \ 3 + 1 = 4 primitives

\ Compare: FP32 version
\ b0_fp32  x_fp32  FP32-MUL  s1_fp32  FP32-ADD   (~210 primitives)
```

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `FP32>FX` | `( fp32 -- fx )` | FP32 → Q16.16 (bit-exact, no FP mul) |
| `FP16>FX` | `( fp16 -- fx )` | FP16 → Q16.16 (via FP32) |
| `FX>FP32` | `( fx -- fp32 )` | Q16.16 → FP32 |
| `FX>FP16` | `( fx -- fp16 )` | Q16.16 → FP16 (lossy) |
