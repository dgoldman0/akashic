# akashic-analysis-spectral — Spectral Analysis for KDOS / Megapad-64

Frequency-domain analysis of PCM buffers using the existing FFT
infrastructure (`akashic/math/fft.f`).  Answers "what frequencies
are present and how loud are they."

```forth
REQUIRE audio/analysis/spectral.f
```

`PROVIDED akashic-analysis-spectral` — safe to include multiple times.

Dependencies: `fp16.f`, `fp16-ext.f`, `fp32.f`, `trig.f`, `fft.f`,
`audio/pcm.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [FFT Parameters](#fft-parameters)
- [API Reference](#api-reference)
  - [PCM-SPECTRAL-CENTROID](#pcm-spectral-centroid)
  - [PCM-SPECTRAL-SPREAD](#pcm-spectral-spread)
  - [PCM-BAND-ENERGY](#pcm-band-energy)
  - [PCM-PITCH-ESTIMATE](#pcm-pitch-estimate)
  - [PCM-SPECTRAL-ROLLOFF](#pcm-spectral-rolloff)
  - [PCM-SPECTRAL-FLUX](#pcm-spectral-flux)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **FFT-based** | Uses `FFT-FORWARD` + `FFT-POWER` from `math/fft.f` — no duplicate DFT code. |
| **FP32 accumulation** | Weighted sums use FP32 to avoid FP16 overflow/cancellation. |
| **Overflow-safe arithmetic** | Bin→Hz conversion computes `bin × (rate/NFFT)` rather than `(bin × rate) / NFFT` to stay within FP16 range. |
| **Lazy allocation** | FFT work arrays (RE, IM, PWR) allocated on first call, reused thereafter. |
| **Non-destructive** | All words are read-only; no buffer modification. |
| **Not re-entrant** | Shares scratch `VARIABLE`s — one analysis at a time. |
| **Prefix convention** | Public: `PCM-`. Internal: `_SP-`. |

---

## FFT Parameters

| Parameter | Value | Meaning |
|---|---|---|
| `_SP-NFFT` | 256 | FFT size (radix-2) |
| `_SP-NBINS` | 128 | Usable bins (NFFT/2) |
| Bin width | ~31.25 Hz | At 8 kHz sample rate: `rate / NFFT` |
| Nyquist bin | 127 | 3968.75 Hz at 8 kHz |

If the PCM buffer has fewer than 256 samples, it is zero-padded.
Only the first 256 samples are analysed; for longer buffers, use
`PCM-SPECTRAL-FLUX` to analyse multiple windows.

---

## API Reference

### PCM-SPECTRAL-CENTROID

```forth
PCM-SPECTRAL-CENTROID  ( buf -- freq-fp16 )
```

The "center of mass" of the power spectrum — the average frequency
weighted by power:

$$\text{centroid} = \frac{\sum_{k=1}^{N/2-1} f_k \times P_k}{\sum_{k=1}^{N/2-1} P_k}$$

Bin 0 (DC) is skipped.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `freq-fp16` | u16 | FP16 centroid frequency in Hz |

**Interpretation:**

| Centroid | Signal Type |
|---|---|
| ~440 | Pure 440 Hz sine |
| < 200 | Bass-heavy / low drone |
| ~Nyquist/2 | White noise |
| 0 | Silent buffer |

```forth
\ Check the "average frequency" of a synthesis output
buf PCM-SPECTRAL-CENTROID
.  \ prints e.g. 449
```

---

### PCM-SPECTRAL-SPREAD

```forth
PCM-SPECTRAL-SPREAD  ( buf -- spread-fp16 )
```

Standard deviation of the spectrum around the centroid:

$$\text{spread} = \sqrt{\frac{\sum_{k=1}^{N/2-1} (f_k - c)^2 \times P_k}{\sum_{k=1}^{N/2-1} P_k}}$$

Computed in two passes: first pass finds centroid, second pass
computes variance.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `spread-fp16` | u16 | FP16 spread in Hz |

**Interpretation:**
- Pure sine: spread < 200 Hz (energy concentrated at one frequency).
- White noise: spread ≈ 1200 Hz (energy everywhere).
- Rich harmonic content: spread 300–800 Hz.

---

### PCM-BAND-ENERGY

```forth
PCM-BAND-ENERGY  ( buf lo-hz hi-hz -- energy-fp16 )
```

Total power in a frequency band.  `lo-hz` and `hi-hz` are plain
integers (Hz), converted to bin indices internally as
`bin = freq / (rate / NFFT)`.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |
| `lo-hz` | int | Lower frequency bound (Hz) |
| `hi-hz` | int | Upper frequency bound (Hz) |

| Output | Type | Description |
|---|---|---|
| `energy-fp16` | u16 | FP16 total power in band |

Bins are clamped to [1, 127].

```forth
\ Compare bass vs treble energy
buf  100  500 PCM-BAND-ENERGY  \ bass
buf 2000 4000 PCM-BAND-ENERGY  \ treble
```

---

### PCM-PITCH-ESTIMATE

```forth
PCM-PITCH-ESTIMATE  ( buf -- freq-fp16 )
```

Autocorrelation-based pitch detection.  Uses the
Wiener–Khinchin theorem: autocorrelation = IFFT of power
spectrum.  After computing the power spectrum, copies it into RE,
zeros IM, runs `FFT-INVERSE`, then searches for the first peak
in the autocorrelation from lag 3 to NFFT/2.

$$f_0 = \frac{\text{rate}}{\text{lag}_\text{peak}}$$

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `freq-fp16` | u16 | FP16 estimated fundamental frequency in Hz |

Returns 0 if no peak is found (e.g. silence, pure noise).

**Accuracy:** Limited by bin resolution (~31 Hz at 8 kHz).  Best
for tonal signals with clear periodicity.

```forth
buf PCM-PITCH-ESTIMATE   \ → ~440 for a 440 Hz sine
```

---

### PCM-SPECTRAL-ROLLOFF

```forth
PCM-SPECTRAL-ROLLOFF  ( buf pct -- freq-fp16 )
```

The frequency below which `pct`% of spectral energy resides.
`pct` is an integer 0–100.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |
| `pct` | int | Cumulative energy percentage (0–100) |

| Output | Type | Description |
|---|---|---|
| `freq-fp16` | u16 | FP16 rolloff frequency in Hz |

**Interpretation:**
- 85% rolloff at 500 Hz → most energy is below 500 Hz.
- 85% rolloff at 3500 Hz → broadband / bright signal.
- Returns Nyquist if threshold is never reached.

```forth
buf 85 PCM-SPECTRAL-ROLLOFF .   \ e.g. 468 for 440 Hz sine
buf 95 PCM-SPECTRAL-ROLLOFF .   \ slightly higher
```

---

### PCM-SPECTRAL-FLUX

```forth
PCM-SPECTRAL-FLUX  ( buf n-windows -- flux-fp16 )
```

Measures timbral change over time.  Splits the buffer into
`n-windows` equal time windows, computes the power spectrum for each
(normalized to sum=1), and averages the bin-by-bin absolute
difference between consecutive windows.

$$\text{flux} = \frac{1}{(W-1) \times B} \sum_{w=1}^{W-1} \sum_{k=1}^{B} \lvert \hat{P}_k^{(w)} - \hat{P}_k^{(w-1)} \rvert$$

where $\hat{P}$ is the normalized power spectrum.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor (should be > NFFT samples) |
| `n-windows` | int | Number of time windows (typically 2–8) |

| Output | Type | Description |
|---|---|---|
| `flux-fp16` | u16 | FP16 average spectral flux (0 = no change) |

**Interpretation:**
- 0: Perfectly steady timbre (constant tone).
- 0.01–0.1: Gradual timbral evolution (morphing pad).
- \> 0.5: Rapid spectral change (drum hit, noise burst).

**Performance:** Runs one FFT per window — `n-windows` × FFT cost.
For a 512-sample buffer with 4 windows, that's 4 × 256-pt FFTs.

```forth
512 8000 16 1 PCM-ALLOC DUP
\ ... fill buffer ...
4 PCM-SPECTRAL-FLUX .   \ flux for 4 time windows
```

---

## Internals

| Word | Stack Effect | Purpose |
|---|---|---|
| `_SP-ALLOC` | `( -- )` | Lazy-allocate RE, IM, PWR arrays (512 bytes each) |
| `_SP-SETUP` | `( buf -- )` | Copy samples → RE, zero IM, run FFT + power |
| `_SP-BIN>HZ` | `( bin -- freq-fp16 )` | Convert bin index to Hz: `bin × (rate / NFFT)` |
| `_SP-FL-ALLOC-PREV` | `( -- )` | Allocate previous-window power array for flux |

| Variable | Type | Purpose |
|---|---|---|
| `_SP-BUF` | addr | Current PCM buffer descriptor |
| `_SP-DPTR` | addr | Current data pointer |
| `_SP-LEN` | int | Current frame count |
| `_SP-RATE` | int | Current sample rate |
| `_SP-RE` | addr | Real array (NFFT × 2 bytes) |
| `_SP-IM` | addr | Imaginary array (NFFT × 2 bytes) |
| `_SP-PWR` | addr | Power spectrum array (NFFT × 2 bytes) |
| `_SP-ALLOCATED` | flag | Have work arrays been allocated? |

All words call `_SP-SETUP` first.  Because they share scratch
variables, analysis words are **not re-entrant**.

### Overflow Avoidance

The original `bin × rate / NFFT` overflows FP16 when `bin × rate`
exceeds 65504 (e.g., bin 14 × 8000 = 112000).  Instead, we
precompute `rate / NFFT` (= 31.25 for 8 kHz / 256), which always
fits in FP16, then multiply by bin.  Same approach for Hz→bin
conversion in `PCM-BAND-ENERGY`.

---

## Quick Reference

```
PCM-SPECTRAL-CENTROID  ( buf -- freq-fp16 )
PCM-SPECTRAL-SPREAD    ( buf -- spread-fp16 )
PCM-BAND-ENERGY        ( buf lo-hz hi-hz -- energy-fp16 )
PCM-PITCH-ESTIMATE     ( buf -- freq-fp16 )
PCM-SPECTRAL-ROLLOFF   ( buf pct -- freq-fp16 )
PCM-SPECTRAL-FLUX      ( buf n-windows -- flux-fp16 )
```

---

## Cookbook

### Frequency fingerprint

```forth
: FREQ-PRINT  ( buf -- )
    ." Centroid: " DUP PCM-SPECTRAL-CENTROID . ." Hz" CR
    ." Spread:  " DUP PCM-SPECTRAL-SPREAD  . ." Hz" CR
    ." Pitch:   " DUP PCM-PITCH-ESTIMATE   . ." Hz" CR
    ." Rolloff: " DUP 85 PCM-SPECTRAL-ROLLOFF . ." Hz (85%)" CR
    ." Bass:    " DUP 100 500  PCM-BAND-ENERGY . CR
    ." Treble:  " 2000 4000 PCM-BAND-ENERGY . CR ;
```

### Detect timbral morphing

```forth
: MORPH?  ( buf -- flag )
    8 PCM-SPECTRAL-FLUX
    0x3000 FP16-GT ;   \ flux > 0.25 → morphing

buf MORPH? IF ." timbre is changing" CR THEN
```

### Bass vs treble classification

```forth
: BASS-HEAVY?  ( buf -- flag )
    DUP  100  500 PCM-BAND-ENERGY   ( buf bass )
    SWAP 2000 4000 PCM-BAND-ENERGY  ( bass treble )
    FP16-GT ;                         \ bass > treble?
```

### Verify synthesis frequency

```forth
: CHECK-FREQ  ( buf expected-hz tolerance -- ok? )
    SWAP INT>FP16 ROT              ( tol expected buf )
    PCM-SPECTRAL-CENTROID          ( tol expected centroid )
    ROT FP16-SUB FP16-ABS          ( tol |centroid - expected| )
    SWAP INT>FP16 FP16-LT ;        \ |diff| < tolerance?

buf 440 50 CHECK-FREQ   \ centroid within ±50 Hz of 440?
```
