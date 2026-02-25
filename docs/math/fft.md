# akashic-fft — Radix-2 Cooley-Tukey FFT for KDOS / Megapad-64

In-place radix-2 decimation-in-time (DIT) FFT on paired real /
imaginary arrays of N FP16 values.  N must be a power of 2.

```forth
REQUIRE fft.f
```

`PROVIDED akashic-fft` — safe to include multiple times.
Auto-loads `fp16-ext.f` and `trig.f` (and transitively `fp16.f`)
via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [FFT-FORWARD](#fft-forward)
- [FFT-INVERSE](#fft-inverse)
- [FFT-MAGNITUDE](#fft-magnitude)
- [FFT-POWER](#fft-power)
- [FFT-CONVOLVE](#fft-convolve)
- [FFT-CORRELATE](#fft-correlate)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **In-place** | FFT-FORWARD and FFT-INVERSE modify their input arrays. |
| **FP16 throughout** | All values are raw 16-bit IEEE 754 half-precision bit patterns. |
| **On-the-fly twiddle** | Twiddle factors are computed per butterfly via `TRIG-SINCOS`, avoiding FP16 accumulation error from recurrence formulas. |
| **PREFIX convention** | Public words use `FFT-` prefix. Internal helpers use `_FFT-`. |
| **VARIABLEs for scratch** | All loop indices and intermediates stored in module-private VARIABLEs. No locals, no nested DO/LOOP. |
| **Not re-entrant** | Shared VARIABLEs mean concurrent callers would collide. |

---

## FFT-FORWARD

```
FFT-FORWARD  ( re im n -- )
```

Compute the in-place forward DFT of the complex signal stored in
arrays `re[]` and `im[]`, each containing `n` FP16 values.

$$X[k] = \sum_{j=0}^{N-1} x[j] \cdot e^{-i\,2\pi\,jk/N}$$

The arrays are modified in place.  `n` must be a power of 2.

```forth
\ Example: FFT of DC signal [1,1,1,1]
8 HBW-ALLOT CONSTANT RE
8 HBW-ALLOT CONSTANT IM
0x3C00 RE 0 + W!  0x3C00 RE 2 + W!
0x3C00 RE 4 + W!  0x3C00 RE 6 + W!
0x0000 IM 0 + W!  0x0000 IM 2 + W!
0x0000 IM 4 + W!  0x0000 IM 6 + W!
RE IM 4 FFT-FORWARD
\ re = [4.0, 0, 0, 0]  im = [0, 0, 0, 0]
```

---

## FFT-INVERSE

```
FFT-INVERSE  ( re im n -- )
```

Compute the in-place inverse DFT, recovering the original signal:

$$x[j] = \frac{1}{N}\sum_{k=0}^{N-1} X[k] \cdot e^{+i\,2\pi\,jk/N}$$

The result is automatically scaled by $1/N$.

```forth
RE IM 4 FFT-FORWARD
RE IM 4 FFT-INVERSE
\ re[], im[] are restored to original values
```

---

## FFT-MAGNITUDE

```
FFT-MAGNITUDE  ( re im mag n -- )
```

Compute the magnitude spectrum from complex FFT output.  Writes
$|X[k]| = \sqrt{\text{re}[k]^2 + \text{im}[k]^2}$ into the
`mag[]` array.  The `mag[]` array must be pre-allocated
(`n * 2` bytes via `HBW-ALLOT`).  `re[]` and `im[]` are not
modified.

```forth
8 HBW-ALLOT CONSTANT MAG
RE IM MAG 4 FFT-MAGNITUDE
\ MAG contains |X[k]| for each bin
```

---

## FFT-POWER

```
FFT-POWER  ( re im pwr n -- )
```

Compute the power spectrum: $P[k] = \text{re}[k]^2 + \text{im}[k]^2$.
Writes result into `pwr[]`.  Same allocation requirement as
FFT-MAGNITUDE.  `re[]` and `im[]` are not modified.

```forth
8 HBW-ALLOT CONSTANT PWR
RE IM PWR 4 FFT-POWER
\ PWR contains re²+im² for each bin
```

---

## FFT-CONVOLVE

```
FFT-CONVOLVE  ( a b dst n -- )
```

Circular convolution of two real signals via the FFT:

1. Forward-FFT both `a[]` and `b[]`
2. Pointwise complex multiply
3. Inverse-FFT the product
4. Store real part in `dst[]`

All arrays are `n` FP16 values.  `a[]`, `b[]` are not modified
(copies are made internally).  Temporary arrays are allocated
with `HBW-ALLOT`.

```forth
8 HBW-ALLOT CONSTANT DST
AA BB DST 4 FFT-CONVOLVE
\ DST = circular convolution of AA and BB
```

---

## FFT-CORRELATE

```
FFT-CORRELATE  ( a b dst n -- )
```

Cross-correlation of two real signals via the FFT:

$$\text{corr}(a, b)[k] = \text{IFFT}\!\bigl(\text{FFT}(a) \cdot \overline{\text{FFT}(b)}\bigr)[k]$$

Same interface and allocation as FFT-CONVOLVE, but the FFT of `b`
is conjugated before multiplication.

```forth
AA BB DST 4 FFT-CORRELATE
\ DST = cross-correlation of AA and BB
```

---

## Internals

| Word | Stack | Purpose |
|---|---|---|
| `_FFT-LOG2` | `( n -- log2 )` | Integer $\log_2(n)$ via right shifts. |
| `_FFT-BITREV` | `( i nbits -- rev )` | Bit-reverse index in an `nbits`-wide field. |
| `_FFT-PERMUTE` | `( -- )` | Bit-reversal permutation of `_FFT-RE[]` / `_FFT-IM[]`. |
| `_FFT-BUTTERFLY` | `( -- )` | One butterfly pass at `_FFT-STAGE` width. |

Module-private VARIABLEs: `_FFT-RE`, `_FFT-IM`, `_FFT-N`, `_FFT-DIR`,
`_FFT-STAGE`, `_FFT-HALF`, `_FFT-AINC`, `_FFT-WR`, `_FFT-WI`,
`_FFT-TR`, `_FFT-TI`, `_FFT-J`, `_FFT-TMP`, `_FFT-GRP`, `_FFT-U`,
`_FFT-L`, `_FFT-UR`, `_FFT-UI`, `_FFT-K`, `_FFT-ANGLE`, plus
variants for INVERSE / CONVOLVE / CORRELATE loops.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `FFT-FORWARD` | `( re im n -- )` | In-place forward FFT |
| `FFT-INVERSE` | `( re im n -- )` | In-place inverse FFT (1/N scaled) |
| `FFT-MAGNITUDE` | `( re im mag n -- )` | $\|X[k]\| = \sqrt{\text{re}^2+\text{im}^2}$ |
| `FFT-POWER` | `( re im pwr n -- )` | $P[k] = \text{re}^2 + \text{im}^2$ |
| `FFT-CONVOLVE` | `( a b dst n -- )` | Circular convolution via FFT |
| `FFT-CORRELATE` | `( a b dst n -- )` | Cross-correlation via FFT |
