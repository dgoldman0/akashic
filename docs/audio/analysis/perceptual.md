# akashic-analysis-perceptual — Perceptual Audio Metrics for KDOS / Megapad-64

Human-ear-weighted metrics.  These answer "how does this actually
sound to a person?" rather than "what are the raw numbers?"

```forth
REQUIRE audio/analysis/perceptual.f
```

`PROVIDED akashic-analysis-perceptual` — safe to include multiple times.

Dependencies: `fp16.f`, `fp16-ext.f`, `fp32.f`, `fft.f`, `audio/pcm.f`
(plus transitive: `trig.f`, `simd-ext.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [A-Weighting Curve](#a-weighting-curve)
- [API Reference](#api-reference)
  - [PCM-A-WEIGHTED-RMS](#pcm-a-weighted-rms)
  - [PCM-BRIGHTNESS](#pcm-brightness)
  - [PCM-SPECTRAL-FLATNESS](#pcm-spectral-flatness)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **FFT-based** | Uses 256-pt FFT (independent of `spectral.f`) with its own `_PP-` allocation. |
| **A-weight table** | 16-entry lookup table of linear gains covering 8-bin ranges (IEC 61672 approximation). |
| **Parseval normalization** | A-weighted RMS is normalized by `NFFT²/2` to match time-domain amplitude scale. |
| **FP32 accumulation** | All weighted sums computed in FP32. |
| **Non-destructive** | All words are read-only; no buffer modification. |
| **Not re-entrant** | Shares scratch `VARIABLE`s — one analysis at a time. |
| **Prefix convention** | Public: `PCM-`. Internal: `_PP-`. |

---

## A-Weighting Curve

The IEC 61672 A-weighting curve attenuates frequencies where human
hearing is less sensitive (below 500 Hz and above 6 kHz) and
slightly boosts the 1–4 kHz range where hearing is most acute.

For a 256-pt FFT at 8 kHz (31.25 Hz/bin), we store 16 linear gain
values covering 8-bin ranges each:

| Range | Bins | Frequency | dB | Linear Gain | FP16 |
|---|---|---|---|---|---|
| 0 | 0–7 | 0–218 Hz | ~−25 | 0.056 | 0x2B2F |
| 1 | 8–15 | 250–468 Hz | ~−8 | 0.40 | 0x3666 |
| 2 | 16–23 | 500–718 Hz | ~−3 | 0.71 | 0x39AC |
| 3 | 24–31 | 750–968 Hz | ~−0.8 | 0.91 | 0x3B47 |
| 4 | 32–39 | 1000–1218 Hz | 0 | 1.00 | 0x3C00 |
| 5 | 40–47 | 1250–1468 Hz | +0.6 | 1.07 | 0x3C47 |
| 6 | 48–55 | 1500–1718 Hz | +1.0 | 1.12 | 0x3C7B |
| 7 | 56–63 | 1750–1968 Hz | +1.2 | 1.15 | 0x3C9A |
| 8 | 64–71 | 2000–2218 Hz | +1.2 | 1.15 | 0x3C9A |
| 9 | 72–79 | 2250–2468 Hz | +1.1 | 1.13 | 0x3C87 |
| 10 | 80–87 | 2500–2718 Hz | +1.0 | 1.12 | 0x3C7B |
| 11 | 88–95 | 2750–2968 Hz | +0.8 | 1.10 | 0x3C66 |
| 12 | 96–103 | 3000–3218 Hz | +0.5 | 1.06 | 0x3C3D |
| 13 | 104–111 | 3250–3468 Hz | +0.1 | 1.01 | 0x3C08 |
| 14 | 112–119 | 3500–3718 Hz | −0.3 | 0.97 | 0x3BE1 |
| 15 | 120–127 | 3750–3968 Hz | −0.8 | 0.91 | 0x3B47 |

The table is heap-allocated (32 bytes) on first use and reused
thereafter.

---

## API Reference

### PCM-A-WEIGHTED-RMS

```forth
PCM-A-WEIGHTED-RMS  ( buf -- rms-fp16 )
```

Computes RMS from the A-weighted power spectrum:

$$\text{RMS}_A = \sqrt{\frac{2}{N^2} \sum_{k=1}^{N/2-1} g_k^2 \times P_k}$$

where $g_k$ is the A-weight gain for bin $k$, $P_k$ is the power
spectrum value, $N$ is the FFT size, and the $2/N^2$ factor is
Parseval normalization to match time-domain amplitude.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `rms-fp16` | u16 | FP16 A-weighted RMS level |

**Interpretation:**

Sub-bass at 80 Hz that looks loud in raw `PCM-RMS` is actually
~−25 dB perceptually.  This metric catches that.

| A-weighted RMS | Meaning |
|---|---|
| > 0.5 | Loud in the 1–4 kHz range |
| 0.1–0.5 | Moderate perceived loudness |
| < 0.05 | Perceptually quiet (even if raw RMS is high) |
| 0 | Silent |

```forth
\ Compare raw vs perceived loudness
buf PCM-RMS .              \ might be 0.5 for 100 Hz sine
buf PCM-A-WEIGHTED-RMS .   \ but only 0.07 perceived
```

---

### PCM-BRIGHTNESS

```forth
PCM-BRIGHTNESS  ( buf -- ratio-fp16 )
```

Ratio of spectral energy above 2 kHz to total energy:

$$\text{brightness} = \frac{\sum_{k=\text{cutoff}}^{N/2-1} P_k}{\sum_{k=1}^{N/2-1} P_k}$$

The cutoff bin is 64 (= 2000 Hz at 8 kHz / 256-pt FFT), defined
as `_PP-BR-CUTOFF-BIN`.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `ratio-fp16` | u16 | FP16 ratio [0.0, 1.0] |

**Interpretation:**

| Brightness | Signal Type |
|---|---|
| > 0.5 | Very bright (hi-hat, noise burst, 3 kHz+ sine) |
| 0.2–0.5 | Moderate treble (string, snare) |
| 0.05–0.2 | Warm (piano, guitar) |
| < 0.05 | Dark / bass-heavy (sub-bass, bass drum) |
| 0 | Silent or all energy below 2 kHz |

```forth
\ Check if a snare has enough treble
buf PCM-BRIGHTNESS
0x3400 FP16-GT IF   \ > 0.25?
    ." bright enough for a snare"
THEN
```

---

### PCM-SPECTRAL-FLATNESS

```forth
PCM-SPECTRAL-FLATNESS  ( buf -- ratio-fp16 )
```

Geometric mean divided by arithmetic mean of the power spectrum:

$$\text{flatness} = \frac{\left(\prod_{k} P_k\right)^{1/K}}{\frac{1}{K}\sum_{k} P_k}$$

Computed in the log domain to avoid numerical overflow:

$$\log_2(\text{flatness}) = \text{mean}(\log_2(P_k)) - \log_2(\text{mean}(P_k))$$

Then $\text{flatness} = 2^{\log_2(\text{flatness})}$ via an integer/fractional
split with first-order Taylor approximation for $2^f$.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `ratio-fp16` | u16 | FP16 ratio [0.0, 1.0] |

Zero-power bins are excluded from the computation.  Returns 0 if
fewer than 2 non-zero bins exist.

**Interpretation:**

| Flatness | Signal Type |
|---|---|
| > 0.8 | White/pink noise (all bins roughly equal) |
| 0.3–0.8 | Noisy mix (breathy sound, wind) |
| 0.05–0.3 | Rich harmonics (sawtooth, vocal) |
| < 0.05 | Pure tone (sine wave, clean whistle) |
| 0 | Silent or single-bin energy |

```forth
\ Is this noise or a tone?
buf PCM-SPECTRAL-FLATNESS
0x3400 FP16-GT IF   \ > 0.25
    ." noise-like"
ELSE
    ." tonal"
THEN
```

---

## Internals

| Word | Stack Effect | Purpose |
|---|---|---|
| `_PP-ALLOC` | `( -- )` | Lazy-allocate RE, IM, PWR arrays |
| `_PP-SETUP` | `( buf -- )` | Copy samples → RE, zero IM, run FFT + power |
| `_PP-AWT-INIT` | `( -- )` | Lazy-allocate + populate A-weight lookup table |
| `_PP-AWT-GAIN` | `( bin -- gain-fp16 )` | Look up A-weight gain for a bin index |
| `_PP-LOG2-APPROX` | `( fp16 -- log2-fp32 )` | Approximate log₂ from FP16 exponent + mantissa |

| Variable | Type | Purpose |
|---|---|---|
| `_PP-BUF` | addr | Current PCM buffer descriptor |
| `_PP-DPTR` | addr | Current data pointer |
| `_PP-LEN` | int | Current frame count |
| `_PP-RATE` | int | Sample rate |
| `_PP-RE` | addr | Real array (NFFT × 2 bytes) |
| `_PP-IM` | addr | Imaginary array (NFFT × 2 bytes) |
| `_PP-PWR` | addr | Power spectrum array (NFFT × 2 bytes) |
| `_PP-AWT-ADDR` | addr | A-weight table (16 × 2 bytes) |
| `_PP-BR-CUTOFF-BIN` | constant | Brightness cutoff bin (64 = 2000 Hz) |

| Constant | Value | Meaning |
|---|---|---|
| `_PP-NFFT` | 256 | FFT size |
| `_PP-NBINS` | 128 | Usable bins (NFFT/2) |
| `_PP-BR-CUTOFF-BIN` | 64 | 2000 Hz at 8 kHz/256 |

### Log₂ Approximation

For positive FP16 value `x`:

$$\log_2(x) \approx \text{exponent} - 15 + \frac{\text{mantissa}}{1024}$$

where `exponent` is bits [14:10] and `mantissa` is bits [9:0] of
the FP16 bit pattern.  The −15 unbiases the FP16 exponent.
Result is FP32 for accumulation precision.

### 2^x Reconstruction

For the flatness ratio, we need $2^x$ where $x \in [-14, 0]$:

1. If $x \geq 0$: clamp to 1.0 (flatness cannot exceed 1).
2. If $x < -10$: return 0 (below FP16 precision).
3. Otherwise: split into integer $n$ and fraction $f$:
   $2^x = \frac{1}{2^{|n|} \times (1 + 0.693 \times f)}$

---

## Quick Reference

```
PCM-A-WEIGHTED-RMS     ( buf -- rms-fp16 )
PCM-BRIGHTNESS         ( buf -- ratio-fp16 )
PCM-SPECTRAL-FLATNESS  ( buf -- ratio-fp16 )
```

---

## Cookbook

### Full perceptual report

```forth
: PERCEPT-REPORT  ( buf -- )
    ." A-RMS:    " DUP PCM-A-WEIGHTED-RMS . CR
    ." Bright:   " DUP PCM-BRIGHTNESS . CR
    ." Flatness: " PCM-SPECTRAL-FLATNESS . CR ;

buf PERCEPT-REPORT
```

### Validate snare sound

A good snare hit should be bright (treble content from the
snare wires) with moderate noise (not a pure tone).

```forth
: SNARE-OK?  ( buf -- flag )
    DUP PCM-BRIGHTNESS
    0x3200 FP16-GT               \ brightness > 0.19?
    SWAP PCM-SPECTRAL-FLATNESS
    0x2800 FP16-GT AND ;          \ flatness > 0.03?

buf SNARE-OK? IF ." snare" ELSE ." not snare-like" THEN
```

### Compare perceived loudness of two buffers

```forth
: LOUDER?  ( buf-a buf-b -- flag )
    PCM-A-WEIGHTED-RMS
    SWAP PCM-A-WEIGHTED-RMS
    FP16-GT ;   \ is A louder than B?

buf1 buf2 LOUDER? IF ." buf1 louder" ELSE ." buf2 louder" THEN
```

### Noise vs tone classifier

```forth
: NOISY?  ( buf -- flag )
    PCM-SPECTRAL-FLATNESS
    0x3800 FP16-GT ;   \ flatness > 0.5?

: TONAL?  ( buf -- flag )
    PCM-SPECTRAL-FLATNESS
    0x2C00 FP16-LT ;   \ flatness < 0.0625?
```

### Dark vs bright classification

```forth
: DARK?  ( buf -- flag )
    PCM-BRIGHTNESS
    0x2C00 FP16-LT ;   \ brightness < 0.0625

: BRIGHT?  ( buf -- flag )
    PCM-BRIGHTNESS
    0x3800 FP16-GT ;   \ brightness > 0.5
```
