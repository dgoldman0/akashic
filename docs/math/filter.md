# akashic-filter — Digital Filters for KDOS / Megapad-64

FIR, IIR biquad, 1D convolution, moving average, median, and
simple low-pass / high-pass filters on FP16 arrays.

```forth
REQUIRE filter.f
```

`PROVIDED akashic-filter` — safe to include multiple times.
Auto-loads `fp16-ext.f`, `simd.f`, `trig.f`, and `sort.f`
(and their transitive deps) via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [FILT-FIR](#filt-fir)
- [FILT-IIR-BIQUAD](#filt-iir-biquad)
- [FILT-CONV1D](#filt-conv1d)
- [FILT-MA](#filt-ma)
- [FILT-MEDIAN](#filt-median)
- [FILT-LOWPASS](#filt-lowpass)
- [FILT-HIGHPASS](#filt-highpass)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **FP16 throughout** | All signal data and coefficients are raw 16-bit IEEE 754 half-precision bit patterns. |
| **Prefix convention** | Public words use `FILT-` prefix. Internal helpers use `_FILT-`. |
| **VARIABLEs for scratch** | All loop indices and intermediates stored in module-private VARIABLEs. No locals, no nested DO/LOOP. |
| **Not re-entrant** | Shared VARIABLEs mean concurrent callers would collide. |
| **Windowed-sinc kernels** | Low-pass and high-pass filters use Hamming-windowed sinc with auto-normalisation. |

---

## FILT-FIR

```
FILT-FIR  ( input coeff n-taps dst n-out -- )
```

Apply a Finite Impulse Response filter.  Each output sample is:

$$y[i] = \sum_{k=0}^{N_\text{taps}-1} h[k] \cdot x[i+k]$$

The `input` buffer must contain at least `n-out + n-taps - 1`
valid FP16 samples.  `coeff` has `n-taps` FP16 coefficients.
Result is written to `dst` (n-out FP16 values).

```forth
\ Example: 3-tap averaging FIR  h = [1/3, 1/3, 1/3]
6 2 * HBW-ALLOT CONSTANT INP
\  ... fill INP with 6 FP16 samples ...
3 2 * HBW-ALLOT CONSTANT H
0x3555 H 0 + W!  0x3555 H 2 + W!  0x3555 H 4 + W!   \ ≈ 0.3333
4 2 * HBW-ALLOT CONSTANT DST
INP H 3 DST 4 FILT-FIR
\ DST contains 4 filtered samples
```

---

## FILT-IIR-BIQUAD

```
FILT-IIR-BIQUAD  ( input b0 b1 b2 a1 a2 dst n -- )
```

Apply a second-order IIR filter using the Direct Form II
Transposed structure:

$$H(z) = \frac{b_0 + b_1 z^{-1} + b_2 z^{-2}}{1 + a_1 z^{-1} + a_2 z^{-2}}$$

Recurrence:

$$y[n] = b_0 x[n] + s_1$$
$$s_1 = b_1 x[n] - a_1 y[n] + s_2$$
$$s_2 = b_2 x[n] - a_2 y[n]$$

All coefficients (`b0`, `b1`, `b2`, `a1`, `a2`) are FP16 raw bit
patterns.  State registers are zeroed at the start of each call.

```forth
\ Example: simple first-order low-pass as biquad (a2=0, b2=0)
\ b0=0.5, b1=0, b2=0, a1=-0.5, a2=0
INP 0x3800 0x0000 0x0000 0xB800 0x0000 DST 8 FILT-IIR-BIQUAD
```

---

## FILT-CONV1D

```
FILT-CONV1D  ( input kernel ksize dst n -- )
```

1D convolution — identical to FIR mathematically, but the naming
convention signals "general purpose convolution" rather than
"filter coefficients".

$$y[i] = \sum_{k=0}^{K-1} x[i+k] \cdot w[k]$$

Input must have at least `n + ksize - 1` valid samples.

```forth
\ Convolve signal with edge-detect kernel [-1, 2, -1]
INP KERN 3 DST 6 FILT-CONV1D
```

---

## FILT-MA

```
FILT-MA  ( input window dst n -- )
```

Moving average filter.  `window` is an integer (the window width).

$$y[i] = \frac{1}{W} \sum_{k=0}^{W-1} x[i+k]$$

Uses a running-sum algorithm: each step adds the entering sample
and subtracts the leaving sample, giving O(n) total work regardless
of window size.

Input must have at least `n + window - 1` valid samples.

```forth
\ 3-point moving average over 8 input samples → 6 output samples
INP 3 DST 6 FILT-MA
```

---

## FILT-MEDIAN

```
FILT-MEDIAN  ( input window dst n -- )
```

Median filter.  For each output position, the window of `window`
samples is sorted and the middle element is selected (lower-middle
for even window sizes).

$$y[i] = \text{median}\bigl(x[i], x[i+1], \ldots, x[i+W-1]\bigr)$$

Allocates a scratch buffer internally via `HBW-ALLOT`.
Input must have at least `n + window - 1` valid samples.

```forth
\ 3-point median filter to remove impulse noise
INP 3 DST 6 FILT-MEDIAN
```

---

## FILT-LOWPASS

```
FILT-LOWPASS  ( input cutoff dst n -- )
```

Simple low-pass filter using a 15-tap Hamming-windowed sinc kernel.
`cutoff` is a normalised frequency in FP16: 0.0 = DC, 1.0 = Nyquist
(half the sampling rate).

The kernel is designed on-the-fly via `_FILT-DESIGN-LP` and then
applied as a FIR filter.  Input must have at least `n + 14` valid
samples.

```forth
\ Low-pass at 0.25 × Nyquist
INP 0x3400 DST 8 FILT-LOWPASS   \ cutoff ≈ 0.25
```

---

## FILT-HIGHPASS

```
FILT-HIGHPASS  ( input cutoff dst n -- )
```

Simple high-pass filter using spectral inversion of a low-pass
kernel.  Same 15-tap Hamming-windowed sinc, but after designing
the low-pass kernel, coefficients are negated and 1.0 is added
to the centre tap:

$$h_\text{hp}[k] = \begin{cases}
  1 - h_\text{lp}[k] & k = \lfloor N/2 \rfloor \\
  -h_\text{lp}[k]     & \text{otherwise}
\end{cases}$$

Input must have at least `n + 14` valid samples.

```forth
\ High-pass at 0.25 × Nyquist
INP 0x3400 DST 8 FILT-HIGHPASS
```

---

## Internals

| Word | Stack | Purpose |
|---|---|---|
| `_FILT-SINC` | `( x -- sinc )` | $\operatorname{sinc}(x) = \sin(\pi x)/(\pi x)$, returns 1.0 for $x=0$. |
| `_FILT-HAMMING` | `( k M -- w )` | Hamming window: $0.54 - 0.46\cos(2\pi k / M)$. |
| `_FILT-DESIGN-LP` | `( coeff ntaps fc -- )` | Design normalised low-pass windowed-sinc kernel. |

Module-private VARIABLEs: `_FIR-*`, `_IIR-*`, `_C1D-*`, `_MA-*`,
`_MED-*`, `_LP-*`, `_HP-*`, `_DLP-*`, `_SINC-*`, `_HAM-*`.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `FILT-FIR` | `( input coeff n-taps dst n-out -- )` | FIR filter (dot-product per sample) |
| `FILT-IIR-BIQUAD` | `( input b0 b1 b2 a1 a2 dst n -- )` | Second-order IIR (DFT-II transposed) |
| `FILT-CONV1D` | `( input kernel ksize dst n -- )` | 1D convolution |
| `FILT-MA` | `( input window dst n -- )` | Moving average filter |
| `FILT-MEDIAN` | `( input window dst n -- )` | Median filter |
| `FILT-LOWPASS` | `( input cutoff dst n -- )` | Low-pass (15-tap windowed sinc) |
| `FILT-HIGHPASS` | `( input cutoff dst n -- )` | High-pass (spectral inversion) |
