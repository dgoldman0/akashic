# akashic-fp-convert — FP16 ↔ Q16.16 Fixed-Point Conversions

Bridge module connecting IEEE 754 floating-point (`fp32.f`, `fp16-ext.f`)
with integer fixed-point (`fixed.f`). Designed for audio filter
coefficient setup: compute biquad coefficients in FP32 for precision,
convert to Q16.16 for a fast integer inner loop.

```forth
REQUIRE fp-convert.f
```

`PROVIDED akashic-fp-convert` — depends on `fp32.f`, `fp16-ext.f`, `fixed.f`.

---

## Design

| Principle | Detail |
|---|---|
| **FP32 conversions come from `fp32.f`** | `FP32>FX` scales by 2¹⁶ exactly and truncates toward zero; `FX>FP32` rounds once. Both give 0 for NaN or saturate at the cell's range. |
| **FP16 via FP32** | `FP16>FX` and `FX>FP16` compose the FP32 conversions with `FP16>FP32` / `FP32>FP16`. Precision is limited by FP16's 10-bit mantissa on the FP16 side. |
| **No state** | The words keep no module state and need no guard. |

### Range

A fixed-point value is a signed cell with 16 fraction bits, so its
resolution is 1/65536 ≈ 0.0000153. Biquad coefficients (typically in
[−2, +2]) keep 16 fractional bits of precision — far exceeding FP16's
10-bit mantissa.

---

## FP16 ↔ Q16.16

| Word | Stack | Result |
|---|---|---|
| `FP16>FX` | `( fp16 -- fx )` | `FP16>FP32 FP32>FX`; exact for every finite FP16 value |
| `FX>FP16` | `( fx -- fp16 )` | `FX>FP32 FP32>FP16`; lossy, for writing PCM samples |

---

## Examples

### Convert a biquad coefficient

```forth
\ na2n = −0.9915 in FP32
0xBF7DD282 FP32>FX   \ → −64979  (Q16.16, truncated toward zero)
```

### FP16 audio sample to Q16.16 and back

```forth
0x3C00 FP16>FX        \ 1.0 → 65536
65536  FX>FP16         \ → 0x3C00  (bit-exact)
```

### One biquad step in Q16.16

```forth
\ y = b0 * x + s1
b0_fx  x_fx  FX*  s1_fx +
```

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `FP16>FX` | `( fp16 -- fx )` | FP16 → Q16.16 (via FP32) |
| `FX>FP16` | `( fx -- fp16 )` | Q16.16 → FP16 (lossy) |
