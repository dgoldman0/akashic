# akashic-analysis-envelope — Temporal Envelope Analysis for KDOS / Megapad-64

Analyses the loudness shape of a sound over time: how fast it
attacks, how long it decays, whether it sustains, and what the
overall envelope curve looks like.

```forth
REQUIRE audio/analysis/envelope.f
```

`PROVIDED akashic-analysis-envelope` — safe to include multiple times.

Dependencies: `fp16.f`, `fp16-ext.f`, `fp32.f`, `audio/pcm.f`.

*No FFT dependency* — purely time-domain, using a sliding RMS window.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Envelope Classes](#envelope-classes)
- [API Reference](#api-reference)
  - [PCM-ATTACK-TIME](#pcm-attack-time)
  - [PCM-DECAY-TIME](#pcm-decay-time)
  - [PCM-SUSTAIN-LEVEL](#pcm-sustain-level)
  - [PCM-SILENCE-RATIO](#pcm-silence-ratio)
  - [PCM-ENVELOPE-DUMP](#pcm-envelope-dump)
  - [PCM-ENVELOPE-CLASS](#pcm-envelope-class)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Sliding RMS window** | 64-sample window (8 ms at 8 kHz) — smooths per-sample noise while tracking dynamics. |
| **FP32 accumulation** | Windowed RMS uses FP32 sum of squares to avoid FP16 cancellation. |
| **Time-domain only** | No FFT required — lighter weight than spectral analysis. |
| **Non-destructive** | All words are read-only; no buffer modification. |
| **Not re-entrant** | Shares scratch `VARIABLE`s — one analysis at a time. |
| **Prefix convention** | Public: `PCM-`, `ENV-`. Internal: `_EN-`. |

---

## Envelope Classes

`PCM-ENVELOPE-CLASS` returns one of five integer constants:

| Constant | Value | Meaning | Heuristic |
|---|---|---|---|
| `ENV-PERCUSSIVE` | 0 | Fast attack, no sustain | Peak in first 10% AND sustain < 0.7 |
| `ENV-SUSTAINED` | 1 | Slow attack or flat body | Sustain level ≥ 0.3 |
| `ENV-SWELL` | 2 | Energy builds up over time | Peak in last 33% of buffer |
| `ENV-SILENCE` | 3 | Effectively silent | Peak RMS < 0.015 |
| `ENV-OTHER` | 4 | None of the above | Fallthrough |

Classification order:
1. Silence check (peak RMS < `_EN-SILENCE-THRESH` ≈ 0.015)
2. Swell check (peak window in last third)
3. Percussive check (peak early AND sustain < 0.7)
4. Sustained check (sustain ≥ 0.3)
5. Fallthrough → `ENV-OTHER`

---

## API Reference

### PCM-ATTACK-TIME

```forth
PCM-ATTACK-TIME  ( buf -- frames )
```

Number of frames from the start of the buffer to the peak
windowed RMS.  The "peak window" is the 64-sample window with
the highest RMS anywhere in the buffer.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `frames` | uint | Frame index of peak window start (0-based) |

**Interpretation:**

| Attack (frames) | At 8 kHz | Signal Type |
|---|---|---|
| 0–40 | 0–5 ms | Percussive (snare, click, pluck) |
| 40–400 | 5–50 ms | Fast synth (keys, stab) |
| 400–1600 | 50–200 ms | Medium (strings pizzicato) |
| > 1600 | > 200 ms | Slow swell (pad, ambient) |

```forth
buf PCM-ATTACK-TIME .  \ e.g. 0 for a snare hit
```

---

### PCM-DECAY-TIME

```forth
PCM-DECAY-TIME  ( buf thresh-fp16 -- frames )
```

Number of frames from the peak window to the first window whose
RMS drops below `thresh-fp16 × peak_rms`.

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |
| `thresh-fp16` | u16 | FP16 fraction of peak (e.g. 0.1 = 10%) |

| Output | Type | Description |
|---|---|---|
| `frames` | uint | Frame count from peak to threshold crossing |

If the signal never drops below the threshold, returns the
remaining buffer length from peak to end.

```forth
\ How long until the sound drops to 10% of peak?
buf 0x2E66 PCM-DECAY-TIME .   \ 0x2E66 ≈ 0.1
```

---

### PCM-SUSTAIN-LEVEL

```forth
PCM-SUSTAIN-LEVEL  ( buf -- ratio-fp16 )
```

Average RMS in the middle 50% of the buffer divided by peak RMS:

$$\text{sustain} = \frac{\text{mean RMS}_{25\%..75\%}}{\text{peak RMS}}$$

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `ratio-fp16` | u16 | FP16 value in [0.0, 1.0] |

**Interpretation:**

| Sustain Level | Signal Type |
|---|---|
| > 0.9 | Constant amplitude (sustained pad, drone) |
| 0.3–0.9 | Decaying but still audible (guitar, bell) |
| 0.1–0.3 | Moderate decay (pluck, short reverb) |
| < 0.1 | Rapid decay (snare, click) |

Returns 0 for silent buffers.  Uses `?DO` to safely handle
edge cases where q1 = q3 (buffer too short for middle-50%).

```forth
buf PCM-SUSTAIN-LEVEL .  \ e.g. 0.535 for linear decay
```

---

### PCM-SILENCE-RATIO

```forth
PCM-SILENCE-RATIO  ( buf thresh-fp16 -- ratio-fp16 )
```

Fraction of the buffer's duration where windowed RMS is below
`thresh-fp16` (an absolute RMS level, not relative to peak).

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |
| `thresh-fp16` | u16 | FP16 absolute RMS threshold |

| Output | Type | Description |
|---|---|---|
| `ratio-fp16` | u16 | FP16 fraction [0.0, 1.0]; 1.0 = all silent |

```forth
\ What fraction of the buffer is "perceptually silent"?
buf 0x2000 PCM-SILENCE-RATIO .   \ 0x2000 ≈ 0.0156
```

---

### PCM-ENVELOPE-DUMP

```forth
PCM-ENVELOPE-DUMP  ( buf n-points -- )
```

Prints a parseable loudness curve to UART.  Samples `n-points`
equally-spaced windows and outputs each as a normalized integer
(0–1000) relative to peak RMS:

```
E0 : 1000
E1 : 843
E2 : 512
E3 : 77
```

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |
| `n-points` | int | Number of sample points (typically 4–16) |

The output is human-readable and machine-parseable (for automated
analysis in test scripts).  Values are `round(window_rms / peak_rms × 1000)`,
clamped to [0, 1000].

For a silent buffer, all values are 0.

```forth
buf 8 PCM-ENVELOPE-DUMP
\ Output:
\   E0 : 1000
\   E1 : 920
\   E2 : 750
\   E3 : 500
\   E4 : 312
\   E5 : 189
\   E6 : 95
\   E7 : 21
```

---

### PCM-ENVELOPE-CLASS

```forth
PCM-ENVELOPE-CLASS  ( buf -- class )
```

Quick heuristic classification of the envelope shape.  Returns
one of the `ENV-*` constants (see [Envelope Classes](#envelope-classes)).

| Input | Type | Description |
|---|---|---|
| `buf` | addr | PCM buffer descriptor |

| Output | Type | Description |
|---|---|---|
| `class` | int | 0=percussive, 1=sustained, 2=swell, 3=silence, 4=other |

Internally calls `_EN-FIND-PEAK` and `PCM-SUSTAIN-LEVEL`.

**Classification logic:**

1. If peak RMS < 0.015 → `ENV-SILENCE`
2. If peak window in last 33% → `ENV-SWELL`
3. If peak in first 10% AND sustain < 0.7 → `ENV-PERCUSSIVE`
4. If sustain ≥ 0.3 → `ENV-SUSTAINED`
5. Otherwise → `ENV-OTHER`

The thresholds (0.7 for percussive ceiling, 0.3 for sustained
floor) are tuned so that:
- A constant-amplitude buffer (sustain ≈ 1.0) is classified as SUSTAINED.
- A linear decay (sustain ≈ 0.535) is classified as PERCUSSIVE.
- A rising signal is classified as SWELL.

```forth
buf PCM-ENVELOPE-CLASS
CASE
    ENV-PERCUSSIVE OF ." Percussive" ENDOF
    ENV-SUSTAINED  OF ." Sustained"  ENDOF
    ENV-SWELL      OF ." Swell"      ENDOF
    ENV-SILENCE    OF ." Silence"    ENDOF
    ." Other"
ENDCASE
```

---

## Internals

| Word | Stack Effect | Purpose |
|---|---|---|
| `_EN-SETUP` | `( buf -- )` | Extract data ptr, len, rate; compute window count |
| `_EN-WIN-RMS` | `( start -- rms-fp16 )` | RMS of one 64-sample window starting at frame `start` |
| `_EN-FIND-PEAK` | `( -- )` | Walk all windows, store peak RMS and its index |

| Variable | Type | Purpose |
|---|---|---|
| `_EN-BUF` | addr | Current PCM buffer descriptor |
| `_EN-DPTR` | addr | Current data pointer |
| `_EN-LEN` | int | Current frame count |
| `_EN-RATE` | int | Sample rate |
| `_EN-NWIN` | int | Number of windows (`len / WINSZ`) |
| `_EN-PKRMS` | u16 | Peak windowed RMS (FP16) |
| `_EN-PKIDX` | int | Window index of peak |

| Constant | Value | Meaning |
|---|---|---|
| `_EN-WINSZ` | 64 | Window size in samples (8 ms at 8 kHz) |
| `_EN-SILENCE-THRESH` | 0x2000 | ~0.015 FP16, threshold for silence classification |

### Window RMS Algorithm

For each window of 64 samples starting at frame `start`:

1. Accumulate `sum += sample² ` in FP32 (via `FP16>FP32`, `FP32-MUL`, `FP32-ADD`).
2. Divide by window size: `sum / 64` in FP32.
3. Square root: `FP32-SQRT`.
4. Narrow to FP16: `FP32>FP16`.

Edge case: if fewer than 64 samples remain, uses the actual count.
Returns 0 for zero-length windows.

---

## Quick Reference

```
PCM-ATTACK-TIME     ( buf -- frames )
PCM-DECAY-TIME      ( buf thresh-fp16 -- frames )
PCM-SUSTAIN-LEVEL   ( buf -- ratio-fp16 )
PCM-SILENCE-RATIO   ( buf thresh-fp16 -- ratio-fp16 )
PCM-ENVELOPE-DUMP   ( buf n-points -- )
PCM-ENVELOPE-CLASS  ( buf -- class )

ENV-PERCUSSIVE  = 0
ENV-SUSTAINED   = 1
ENV-SWELL       = 2
ENV-SILENCE     = 3
ENV-OTHER       = 4
```

---

## Cookbook

### Full envelope report

```forth
: ENV-REPORT  ( buf -- )
    ." Attack:  " DUP PCM-ATTACK-TIME . ." frames" CR
    ." Decay:   " DUP 0x2E66 PCM-DECAY-TIME . ." frames (to 10%)" CR
    ." Sustain: " DUP PCM-SUSTAIN-LEVEL . CR
    ." Silence: " DUP 0x2000 PCM-SILENCE-RATIO . CR
    ." Class:   " DUP PCM-ENVELOPE-CLASS . CR
    ." === Envelope curve ===" CR
    8 PCM-ENVELOPE-DUMP ;

buf ENV-REPORT
```

### Percussive vs sustained check

```forth
: PERCUSSIVE?  ( buf -- flag )
    PCM-ENVELOPE-CLASS ENV-PERCUSSIVE = ;

: SUSTAINED?  ( buf -- flag )
    PCM-ENVELOPE-CLASS ENV-SUSTAINED = ;
```

### Quick silence detector

```forth
: SILENT?  ( buf -- flag )
    PCM-ENVELOPE-CLASS ENV-SILENCE = ;
```

### Attack time guard for snare synthesis

```forth
: CHECK-SNARE  ( buf -- ok? )
    DUP PCM-ATTACK-TIME 40 <          \ attack < 5ms
    SWAP PCM-SUSTAIN-LEVEL
    0x3000 FP16-LT AND ;               \ sustain < 0.25

buf CHECK-SNARE IF ." snare OK" ELSE ." not percussive enough" THEN
```

### Decay curve visualization

```forth
\ Print 16-point loudness curve for visual inspection
buf 16 PCM-ENVELOPE-DUMP
\ Then visually check the shape:
\ E0: 1000  ████████████████████
\ E1: 800   ████████████████
\ E2: 500   ██████████
\ ...
\ E15: 10   ▏
```
