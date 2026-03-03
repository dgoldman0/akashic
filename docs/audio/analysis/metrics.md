# akashic-analysis-metrics — PCM Buffer Analysis Metrics for KDOS / Megapad-64

Seven diagnostic metrics for inspecting PCM buffers produced by
synthesis engines.  Operates on FP16-valued PCM buffers (the native
format of every Akashic `syn/` engine).  Useful for automated
verification that audio output is non-silent, non-clipped, has
expected energy profile, etc.

```forth
REQUIRE audio/analysis/metrics.f
```

`PROVIDED akashic-analysis-metrics` — safe to include multiple times.

Dependencies: `fp16.f`, `fp16-ext.f`, `fp32.f`, `audio/pcm.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Metrics Overview](#metrics-overview)
- [API Reference](#api-reference)
  - [PCM-PEAK](#pcm-peak)
  - [PCM-ZERO-CROSSINGS](#pcm-zero-crossings)
  - [PCM-RMS](#pcm-rms)
  - [PCM-DC-OFFSET](#pcm-dc-offset)
  - [PCM-CLIP-COUNT](#pcm-clip-count)
  - [PCM-CREST-FACTOR](#pcm-crest-factor)
  - [PCM-ENERGY-REGIONS](#pcm-energy-regions)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **PCM-level analysis** | Operates on PCM buffers (not WAV files). |
| **FP32 accumulation** | RMS and DC-OFFSET accumulate in FP32 to avoid FP16 cancellation. |
| **Non-destructive** | All metrics are read-only; no buffer modification. |
| **Variable-based state** | Internal scratch uses `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `PCM-`. Internal: `_PM-`. |

---

## Metrics Overview

| Metric | Stack Effect | What it Detects |
|---|---|---|
| **PCM-PEAK** | `( buf -- peak frame )` | Maximum absolute amplitude and where it occurs |
| **PCM-ZERO-CROSSINGS** | `( buf -- count )` | Number of sign transitions — proxy for frequency content |
| **PCM-RMS** | `( buf -- rms )` | Root mean square energy level |
| **PCM-DC-OFFSET** | `( buf -- mean )` | DC bias — should be ~0 for centered audio |
| **PCM-CLIP-COUNT** | `( buf -- count )` | Samples with &#124;value&#124; ≥ 1.0 — digital clipping |
| **PCM-CREST-FACTOR** | `( buf -- cf )` | Peak / RMS ratio — characterizes waveform shape |
| **PCM-ENERGY-REGIONS** | `( buf n -- )` | Per-region energy profile printed to UART |

---

## API Reference

### PCM-PEAK

```forth
PCM-PEAK  ( buf -- peak-fp16 frame )
```

Scans every sample in the buffer.  Returns the maximum absolute
amplitude as an FP16 value (always positive) and the frame index
where it was found.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `peak-fp16` | u16 | FP16 bit pattern of max &#124;sample&#124; |
| `frame` | uint | Frame index of peak (0-based) |

**Interpretation:**
- `peak = 0`: Buffer is silent.
- `frame` near 0: Percussive attack (expected for strikes).
- `frame` near end: Energy builds up — check for feedback/instability.

```forth
\ Example: check if a synthesis output has any energy
buf PCM-PEAK DROP FP16-POS-ZERO FP16-GT IF
    ." non-silent"
THEN
```

---

### PCM-ZERO-CROSSINGS

```forth
PCM-ZERO-CROSSINGS  ( buf -- count )
```

Counts sign transitions between consecutive non-zero samples.
The sign bit is bit 15 (0x8000) of the FP16 value.  Exact-zero
samples are skipped (they don't contribute a crossing).

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `count` | uint | Number of zero crossings |

**Interpretation:**
For a pure sine wave at frequency *f* with *N* frames at sample
rate *R*:

$$\text{expected crossings} \approx \frac{2 \times f \times N}{R}$$

- `count = 0` on a non-silent buffer: DC offset or broken oscillator.
- Very high count relative to expected: Noise-dominated signal.

```forth
\ Expected ZC for 440 Hz sine, 8000 Hz rate, 256 frames:
\ 2 × 440 × 256 / 8000 = 28.16 → ~28 crossings
buf PCM-ZERO-CROSSINGS .   \ should print ~28
```

---

### PCM-RMS

```forth
PCM-RMS  ( buf -- rms-fp16 )
```

Root mean square amplitude:
$$\text{RMS} = \sqrt{\frac{1}{N} \sum_{i=0}^{N-1} x_i^2}$$

Uses FP32 accumulation internally: each sample is converted
FP16→FP32, squared, added to an FP32 running sum, then
divided and square-rooted.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `rms-fp16` | u16 | FP16 bit pattern of RMS |

**Interpretation:**
- Constant signal: RMS = the constant value.
- Alternating ±A: RMS = A.
- Silence: RMS = 0.
- RMS close to 0 on a supposedly non-silent buffer → broken synthesis.

---

### PCM-DC-OFFSET

```forth
PCM-DC-OFFSET  ( buf -- mean-fp16 )
```

Arithmetic mean of all sample values:
$$\text{DC} = \frac{1}{N} \sum_{i=0}^{N-1} x_i$$

Uses FP32 accumulation to avoid catastrophic cancellation.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `mean-fp16` | u16 | FP16 bit pattern of mean |

**Interpretation:**
- Should be ~0 for properly centered audio.
- Nonzero value indicates DC bias bug in synthesis engine.
- Symmetric waveforms (sine, square) should give exactly 0.

---

### PCM-CLIP-COUNT

```forth
PCM-CLIP-COUNT  ( buf -- count )
```

Counts samples where |value| ≥ 1.0. The FP16 check is:
clear sign bit (AND 0x7FFF), compare ≥ 0x3C00.  This catches
1.0, values above 1.0, Infinity, and NaN — all problematic.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `count` | uint | Number of clipped samples |

**Interpretation:**
- 0: No clipping. Good.
- Small count: Occasional peaks hitting the rail.
- Equal to buffer length: Everything is clipped — gain way too high.

---

### PCM-CREST-FACTOR

```forth
PCM-CREST-FACTOR  ( buf -- cf-fp16 )
```

$$\text{Crest Factor} = \frac{\text{Peak}}{\text{RMS}}$$

Calls `PCM-PEAK` and `PCM-RMS` internally.  Returns 0 if the
buffer is silent (RMS = 0) to avoid division by zero.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `cf-fp16` | u16 | FP16 crest factor |

**Interpretation:**

| Crest Factor | Signal Shape |
|---|---|
| 1.0 | Square wave / constant |
| √2 ≈ 1.414 | Sine wave |
| > 4 | Sparse peaks in mostly quiet audio |
| > 10 | Impulsive / nearly silent with rare spikes |

---

### PCM-ENERGY-REGIONS

```forth
PCM-ENERGY-REGIONS  ( buf n -- )
```

Splits the buffer into *n* equal regions and prints one
diagnostic line per region to UART:

```
R0: rms=<int> pk=<int> zc=<int>
R1: rms=<int> pk=<int> zc=<int>
...
```

Values `rms` and `pk` are FP16 bit patterns printed as integers
(for easy machine parsing).  `zc` is zero-crossing count.

Creates a temporary 80-byte PCM descriptor (no sample data
allocation) that points into successive slices of the source buffer.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |
| `n` | uint | Number of regions (must divide evenly into frame count) |

**Interpretation:**
- **Percussive decay:** R0 highest rms, monotonically decreasing.
- **Sustained pad:** Roughly equal rms across all regions.
- **Silent buffer:** All rms = 0.
- **Broken oscillator:** Some regions have zc = 0 unexpectedly.

```forth
\ Split a 1-second buffer into 4 quarter-second regions
buf 4 PCM-ENERGY-REGIONS
\ Output:
\   R0: rms=14336 pk=15360 zc=110
\   R1: rms=12288 pk=14336 zc=95
\   R2: rms=8192  pk=10240 zc=60
\   R3: rms=2048  pk=4096  zc=15
```

---

## Internals

| Word | Stack Effect | Purpose |
|---|---|---|
| `_PM-SETUP` | `( buf -- )` | Extract data pointer and length into scratch variables |
| `_PM-BUF` | variable | Current buffer descriptor |
| `_PM-DPTR` | variable | Current data pointer |
| `_PM-LEN` | variable | Current frame count |

All metrics call `_PM-SETUP` first.  Because they share
scratch variables, metrics are **not re-entrant**.
`PCM-ENERGY-REGIONS` safely calls metrics in a loop using
its own `_PM-ER-*` scratch variables for the outer loop state.

---

## Quick Reference

```
PCM-PEAK            ( buf -- peak-fp16 frame )
PCM-ZERO-CROSSINGS  ( buf -- count )
PCM-RMS             ( buf -- rms-fp16 )
PCM-DC-OFFSET       ( buf -- mean-fp16 )
PCM-CLIP-COUNT      ( buf -- count )
PCM-CREST-FACTOR    ( buf -- cf-fp16 )
PCM-ENERGY-REGIONS  ( buf n -- )
```

---

## Cookbook

### Silence detector

```forth
: SILENT?  ( buf -- flag )
    PCM-RMS FP16-POS-ZERO = ;

buf SILENT? IF ." buffer is silent!" CR THEN
```

### Quick health check

```forth
: PCM-HEALTH  ( buf -- )
    ." Peak:   " DUP PCM-PEAK . ."  at frame " . CR
    ." RMS:    " DUP PCM-RMS . CR
    ." DC:     " DUP PCM-DC-OFFSET . CR
    ." ZC:     " DUP PCM-ZERO-CROSSINGS . CR
    ." Clips:  " DUP PCM-CLIP-COUNT . CR
    ." Crest:  " DUP PCM-CREST-FACTOR . CR
    ." === Energy regions ===" CR
    4 PCM-ENERGY-REGIONS ;

buf PCM-HEALTH
```

### Automated pass/fail for synthesis output

```forth
: CHECK-SYNTH  ( buf -- ok? )
    DUP PCM-RMS FP16-POS-ZERO FP16-GT    \ non-silent?
    OVER PCM-CLIP-COUNT 0=  AND            \ no clipping?
    OVER PCM-ZERO-CROSSINGS 0<> AND        \ has oscillation?
    SWAP PCM-DC-OFFSET FP16-ABS
    0x2C00 FP16-GT 0= AND ;               \ DC < 0.0625?
```
