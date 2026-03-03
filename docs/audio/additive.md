# akashic-syn-additive — Harmonic Additive Synthesis with Spectral Morphing for KDOS / Megapad-64

Models sound as a sum of harmonic partials (integer multiples of a
fundamental frequency), each with an independently controllable and
morphable amplitude.  This is the mathematical dual of subtractive
synthesis: instead of filtering away from a rich source, you build up
from pure sines.

```forth
REQUIRE audio/syn/additive.f
```

`PROVIDED akashic-syn-additive` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-trig`,
`akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Setting the Fundamental](#setting-the-fundamental)
- [Harmonic Control](#harmonic-control)
- [Spectral Morphing](#spectral-morphing)
- [Rendering](#rendering)
- [Presets](#presets)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Per-harmonic morph** | Each harmonic has current amp, target amp, and a per-sample delta.  `ADD-MORPH!` schedules smooth transitions over ms. |
| **Wavetable sine** | All harmonics use `WT-SIN-TABLE WT-LOOKUP` for fast per-sample sine generation. |
| **Silent skip** | Harmonics with `amp-cur = 0` are skipped entirely in the render loop. |
| **Phase continuity** | Phase accumulators persist across `ADD-RENDER` calls — no clicks at buffer boundaries. |
| **Integer harmonics** | Harmonic k (0-based) oscillates at `(k+1) × fundamental` Hz. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `ADD-`.  Internal: `_AD-`.  Field: `AD.xxx` / `AH.xxx`. |

---

## Memory Layout

### Descriptor (8 cells = 64 bytes)

```
Offset  Size  Field
──────  ────  ──────────────────
+0      8     n-harmonics   Number of harmonics (integer, 1–16)
+8      8     fundamental   Fundamental frequency Hz (FP16)
+16     8     rate          Sample rate Hz (integer)
+24     8     harm-ptr      Pointer to harmonic array (N × 16 bytes)
+32–63  -     (reserved)
```

### Per-Harmonic Block (16 bytes per harmonic)

```
Offset  Size  Field
──────  ────  ──────────────────
+0      2     amp-cur       Current amplitude (FP16)
+2      2     amp-tgt       Target amplitude (FP16)
+4      2     morph-step    Per-sample amplitude delta (FP16)
+6      2     morph-rem     Frames remaining in morph (int16)
+8      2     phase         Current phase 0.0–1.0 (FP16)
+10     2     pinc          Phase increment per sample (FP16)
+12–15  4     (padding)
```

---

## Creation & Destruction

### ADD-CREATE

```forth
ADD-CREATE  ( n-harmonics rate -- desc )
```

Allocate an additive descriptor and its harmonic array.
All amplitudes start at 0 (silent until set).

- **n-harmonics** — number of harmonics (integer, typically 8–16)
- **rate** — sample rate in Hz (integer)

```forth
8 44100 ADD-CREATE CONSTANT syn
```

### ADD-FREE

```forth
ADD-FREE  ( desc -- )
```

Free the harmonic array and descriptor.

---

## Setting the Fundamental

### ADD-FUND!

```forth
ADD-FUND!  ( freq desc -- )
```

Set the fundamental frequency (FP16 Hz) and recompute all phase
increments.  Harmonic k (0-based) gets `pinc = (k+1) × freq / rate`.

```forth
440 INT>FP16 syn ADD-FUND!
```

Phase accumulators are *not* reset — calling `ADD-FUND!` mid-stream
produces a smooth pitch change without clicks.

---

## Harmonic Control

### ADD-HARMONIC!

```forth
ADD-HARMONIC!  ( amp i desc -- )
```

Set harmonic `i` (0-based) to amplitude `amp` immediately.  Cancels
any in-progress morph.  `amp` is FP16 0.0–1.0.

```forth
\ Fundamental at full, 2nd harmonic at half
FP16-POS-ONE  0 syn ADD-HARMONIC!
FP16-POS-HALF 1 syn ADD-HARMONIC!
```

---

## Spectral Morphing

### ADD-MORPH!

```forth
ADD-MORPH!  ( amp ms i desc -- )
```

Schedule a smooth amplitude transition for harmonic `i`.

- **amp** — target amplitude (FP16)
- **ms** — transition duration in milliseconds (integer)
- **i** — harmonic index (0-based)

The morph runs inside `ADD-RENDER`: each sample, `amp-cur` advances
by `morph-step` until `morph-rem` reaches 0.

$$\text{step} = \frac{\text{target} - \text{current}}{\text{ms} \times \text{rate} / 1000}$$

```forth
\ Fade 3rd harmonic to zero over 500 ms
FP16-POS-ZERO 500 2 syn ADD-MORPH!
```

---

## Rendering

### ADD-RENDER

```forth
ADD-RENDER  ( buf desc -- )
```

Fill a PCM buffer with additive synthesis output.  For each sample:

1. For each harmonic with `amp-cur > 0`:
   - Advance morph (if active).
   - Compute `sin(phase)` via wavetable lookup.
   - Accumulate `sample × amp-cur`.
   - Advance phase, wrap at 1.0.
2. Write accumulated sum to buffer.

Call repeatedly in a render loop.  Phase and morph state persist
across calls.

```forth
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf syn ADD-RENDER
```

---

## Presets

### ADD-PRESET-SAW

```forth
ADD-PRESET-SAW  ( desc -- )
```

Load all harmonics with sawtooth amplitudes: harmonic k gets
amplitude `1 / (k+1)`.  Rich, bright, buzzy tone.

```forth
8 44100 ADD-CREATE CONSTANT saw
440 INT>FP16 saw ADD-FUND!
saw ADD-PRESET-SAW
```

### ADD-PRESET-SQUARE

```forth
ADD-PRESET-SQUARE  ( desc -- )
```

Load odd harmonics only (1, 3, 5, ...) at `1 / (k+1)`.  Even
harmonics set to 0.  Hollow, clarinet-like tone.

### ADD-PRESET-ORGAN

```forth
ADD-PRESET-ORGAN  ( desc -- )
```

Approximate pipe organ drawbar spectrum.  Harmonics 1, 2, 4
prominent; others subdued.  Works best with `n-harmonics ≥ 8`.

| Harmonic | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|----------|-----|-----|-----|-----|-----|------|------|-------|
| Amplitude | 1.0 | 0.75 | 0.25 | 0.5 | 0.15 | 0.125 | 0.10 | 0.075 |

---

## Quick Reference

```
ADD-CREATE        ( n-harmonics rate -- desc )
ADD-FREE          ( desc -- )
ADD-FUND!         ( freq desc -- )            FP16 Hz, recomputes pinc
ADD-HARMONIC!     ( amp i desc -- )           immediate set
ADD-MORPH!        ( amp ms i desc -- )        scheduled transition
ADD-RENDER        ( buf desc -- )             fill PCM buffer
ADD-PRESET-SAW    ( desc -- )                 sawtooth 1/k series
ADD-PRESET-SQUARE ( desc -- )                 odd harmonics only
ADD-PRESET-ORGAN  ( desc -- )                 pipe organ drawbars
```

---

## Cookbook

### Saw → Square Morph Over 2 Seconds

```forth
8 44100 ADD-CREATE CONSTANT syn
440 INT>FP16 syn ADD-FUND!
syn ADD-PRESET-SAW            \ start as sawtooth
\ Schedule even harmonics to zero over 2 seconds
FP16-POS-ZERO 2000 1 syn ADD-MORPH!
FP16-POS-ZERO 2000 3 syn ADD-MORPH!
FP16-POS-ZERO 2000 5 syn ADD-MORPH!
FP16-POS-ZERO 2000 7 syn ADD-MORPH!
\ Render — morph happens inside ADD-RENDER
44100 44100 16 1 PCM-ALLOC CONSTANT buf
buf syn ADD-RENDER \ 1 second, saw morphing toward square
buf PCM-FREE  syn ADD-FREE
```

### Organ Tone

```forth
8 44100 ADD-CREATE CONSTANT org
262 INT>FP16 org ADD-FUND!   \ middle C
org ADD-PRESET-ORGAN
2048 44100 16 1 PCM-ALLOC CONSTANT buf
buf org ADD-RENDER
buf PCM-FREE  org ADD-FREE
```

### Pitch Glide

```forth
8 44100 ADD-CREATE CONSTANT syn
440 INT>FP16 syn ADD-FUND!
FP16-POS-ONE 0 syn ADD-HARMONIC!
\ Render first chunk at 440 Hz
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf syn ADD-RENDER
\ Change pitch — phase continues, no click
880 INT>FP16 syn ADD-FUND!
buf syn ADD-RENDER    \ now at 880 Hz
buf PCM-FREE  syn ADD-FREE
```
