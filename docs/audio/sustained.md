# akashic-syn-sustained — Perceptual Sustained-Tone Synthesis for KDOS / Megapad-64

Produces continuously sounding pad / drone / organ tones controlled
through five perceptual dimensions — **brightness**, **warmth**,
**motion**, **density**, and **breathiness** — rather than raw DSP
parameters.  Up to 8 detuned oscillators are blended under the hood,
with LFO vibrato and a one-pole low-pass filter shaped by the
brightness knob.

```forth
REQUIRE audio/syn/sustained.f
```

`PROVIDED akashic-syn-sustained` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-trig`,
`akashic-audio-pcm`, `akashic-audio-noise`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Frequency](#frequency)
- [Perceptual Dimensions](#perceptual-dimensions)
- [Morphing](#morphing)
- [Rendering](#rendering)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Perceptual mapping** | Five 0.0–1.0 knobs map onto raw detune spread, oscillator count, filter cutoff, LFO depth, and noise mix. |
| **Detuned unison** | `density` controls how many oscillators (1–8) sound simultaneously; `warmth` sets the detune spread. |
| **One-pole LP filter** | `brightness` adjusts exponentially-mapped α coefficient — 0 = dark, 1 = open. |
| **LFO vibrato** | `motion` scales LFO depth; the LFO runs at a fixed ~5 Hz and modulates phase increments. |
| **Noise breathiness** | White noise from the shared noise engine is mixed in proportion to `breathiness`. |
| **Block-rate morph** | `SUST-MORPH` schedules linear interpolation of all five dimensions over a frame count. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant across multiple descriptors in parallel. |
| **Prefix convention** | Public: `SUST-`.  Internal: `_SU-`.  Field: `SU.xxx`. |

---

## Memory Layout

### Descriptor (128 bytes)

```
Offset  Size  Field
──────  ────  ──────────────────────────────
+0      8     fundamental    Base frequency Hz (FP16)
+8      8     rate           Sample rate (integer)
+16     8     brightness     0.0–1.0 (FP16)
+24     8     warmth         0.0–1.0 (FP16)
+32     8     motion         0.0–1.0 (FP16)
+40     8     density        0.0–1.0 (FP16)
+48     8     breathiness    0.0–1.0 (FP16)
+56     8     n-active       Number of active oscillators (int, 1–8)
+64     8     noise-eng      Noise engine pointer
+72     8     lfo-phase      LFO accumulator (FP16)
+80     8     lp-state       LP filter state (FP16)
+88     8     lp-alpha       LP filter coefficient (FP16)
+96     32    osc-slots      8 × {phase(2) + detune(2)} = 4 bytes packed
```

Each oscillator slot stores:

| Sub-field | Size | Description |
|-----------|------|-------------|
| `phase`   | 2 B  | Phase accumulator 0.0–1.0 (FP16) |
| `detune`  | 2 B  | Frequency offset as FP16 multiplier (e.g. 1.005) |

---

## Creation & Destruction

### SUST-CREATE

```forth
SUST-CREATE  ( freq rate -- desc )
```

Allocate a sustained-tone descriptor.  `freq` is FP16 Hz; `rate`
is an integer sample rate.  All dimensions default to 0.0 (single
oscillator, dark, no vibrato, no noise).

```forth
440 INT>FP16 44100 SUST-CREATE CONSTANT pad
```

### SUST-FREE

```forth
SUST-FREE  ( desc -- )
```

Free the noise engine and descriptor.

---

## Frequency

### SUST-FREQ!

```forth
SUST-FREQ!  ( freq desc -- )
```

Set the fundamental frequency (FP16 Hz).  All oscillator phase
increments are recomputed with their current detune offsets.

```forth
220 INT>FP16 pad SUST-FREQ!
```

---

## Perceptual Dimensions

All five setters accept an FP16 value in 0.0–1.0.

### SUST-BRIGHTNESS!

```forth
SUST-BRIGHTNESS!  ( v desc -- )
```

Controls the one-pole low-pass cutoff.

| Value | Effect |
|-------|--------|
| 0.0   | Very dark — heavy filtering |
| 0.5   | Moderate warmth |
| 1.0   | Fully open — no filtering |

$$\alpha = v^2 \quad\text{(exponential-feel curve)}$$

### SUST-WARMTH!

```forth
SUST-WARMTH!  ( v desc -- )
```

Sets the detune spread between oscillators.  Higher warmth = wider
spread = lush chorus.  At 0.0 all oscillators are in tune (thin).

### SUST-MOTION!

```forth
SUST-MOTION!  ( v desc -- )
```

Scales the LFO vibrato depth.  0.0 = no vibrato; 1.0 = deep wobble.
The LFO rate is fixed internally at approximately 5 Hz.

### SUST-DENSITY!

```forth
SUST-DENSITY!  ( v desc -- )
```

Controls how many of the 8 oscillator slots are active.

$$n_{\text{active}} = 1 + \lfloor v \times 7 \rfloor$$

| Value | Oscillators |
|-------|-------------|
| 0.0   | 1 (thin) |
| 0.5   | ~4 (ensemble) |
| 1.0   | 8 (full unison) |

### SUST-BREATHINESS!

```forth
SUST-BREATHINESS!  ( v desc -- )
```

Mixes white noise into the output.  0.0 = pure tone; 1.0 = heavy noise.

---

## Morphing

### SUST-MORPH

```forth
SUST-MORPH  ( target frames desc -- )
```

Smoothly interpolate **all five dimensions** from their current
values toward a target parameter set over `frames` render calls.

- **target** — address of a 5-cell block:
  `brightness warmth motion density breathiness` (each FP16)
- **frames** — number of `SUST-RENDER` calls over which to transition

```forth
CREATE tgt
  FP16-POS-ONE ,   \ brightness → 1.0
  FP16-POS-HALF ,  \ warmth → 0.5
  FP16-POS-HALF ,  \ motion → 0.5
  FP16-POS-ONE ,   \ density → 1.0
  FP16-POS-ZERO ,  \ breathiness → 0.0
tgt 60 pad SUST-MORPH   \ morph over 60 render calls
```

---

## Rendering

### SUST-RENDER

```forth
SUST-RENDER  ( buf desc -- )
```

Fill a PCM buffer with one block of sustained-tone audio.  Per sample:

1. Advance LFO; compute vibrato offset from `motion`.
2. For each active oscillator:
   - Compute `sin(phase × (fund × detune) + vibrato)` via wavetable.
   - Advance and wrap phase.
3. Sum oscillators and normalise by `n-active`.
4. Mix in white noise scaled by `breathiness`.
5. Apply one-pole LP filter:  $y_n = \alpha \cdot x_n + (1 - \alpha) \cdot y_{n-1}$
6. Write sample to buffer.

If a morph is active, advance dimension interpolation once per
`SUST-RENDER` call (block-rate).

```forth
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf pad SUST-RENDER
```

---

## Quick Reference

```
SUST-CREATE       ( freq rate -- desc )       FP16 Hz, int rate
SUST-FREE         ( desc -- )
SUST-FREQ!        ( freq desc -- )            FP16 Hz, recomputes pinc
SUST-BRIGHTNESS!  ( v desc -- )               LP cutoff 0–1
SUST-WARMTH!      ( v desc -- )               detune spread 0–1
SUST-MOTION!      ( v desc -- )               LFO depth 0–1
SUST-DENSITY!     ( v desc -- )               osc count 0–1
SUST-BREATHINESS! ( v desc -- )               noise mix 0–1
SUST-MORPH        ( target frames desc -- )   linear interp all dims
SUST-RENDER       ( buf desc -- )             fill PCM buffer
```

---

## Cookbook

### Warm Pad

```forth
330 INT>FP16 44100 SUST-CREATE CONSTANT pad
FP16-POS-HALF pad SUST-BRIGHTNESS!   \ mellow
FP16-POS-HALF pad SUST-WARMTH!       \ moderate chorus
FP16-POS-ONE  pad SUST-DENSITY!      \ full 8-osc unison
2048 44100 16 1 PCM-ALLOC CONSTANT buf
buf pad SUST-RENDER
buf PCM-FREE  pad SUST-FREE
```

### Airy Flute Tone

```forth
880 INT>FP16 44100 SUST-CREATE CONSTANT fl
FP16-POS-ONE  fl SUST-BRIGHTNESS!    \ bright
FP16-POS-ZERO fl SUST-WARMTH!        \ no detune
FP16-POS-ZERO fl SUST-DENSITY!       \ single osc
\ Slight breath noise
3277 fl SUST-BREATHINESS!            \ ~0.20 FP16
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf fl SUST-RENDER
buf PCM-FREE  fl SUST-FREE
```

### Evolving Drone with Morph

```forth
110 INT>FP16 44100 SUST-CREATE CONSTANT drn
FP16-POS-ZERO drn SUST-BRIGHTNESS!
FP16-POS-ZERO drn SUST-WARMTH!
FP16-POS-ZERO drn SUST-MOTION!
FP16-POS-ZERO drn SUST-DENSITY!
FP16-POS-ZERO drn SUST-BREATHINESS!

CREATE tgt
  FP16-POS-ONE ,   \ brightness opens
  FP16-POS-ONE ,   \ warmth widens
  FP16-POS-HALF ,  \ motion introduces vibrato
  FP16-POS-ONE ,   \ density fills out
  FP16-POS-ZERO ,  \ breathiness stays clean
tgt 120 drn SUST-MORPH          \ morph over 120 render blocks

4096 44100 16 1 PCM-ALLOC CONSTANT buf
\ Render 120 blocks — drone evolves each block
120 0 DO buf drn SUST-RENDER LOOP
buf PCM-FREE  drn SUST-FREE
```
