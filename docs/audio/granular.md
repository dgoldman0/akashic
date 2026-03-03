# akashic-syn-granular — Granular Synthesis Engine for KDOS / Megapad-64

Slices a source PCM buffer into tiny overlapping **grains** (typically
10–100 ms) and scatters them across time with controllable density,
position, pitch shift, and randomisation.  Useful for time-stretching,
freeze effects, texture clouds, and spectral smearing.

```forth
REQUIRE audio/syn/granular.f
```

`PROVIDED akashic-syn-granular` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-trig`,
`akashic-audio-pcm`, `akashic-audio-noise`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Source Buffer](#source-buffer)
- [Grain Parameters](#grain-parameters)
- [Scatter / Randomisation](#scatter--randomisation)
- [Rendering](#rendering)
- [Envelope Types](#envelope-types)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Fixed grain pool** | 16 grain slots; new grains steal the oldest inactive slot.  No heap allocation during render. |
| **Scheduled spawning** | A scheduling counter triggers new grains at `rate / density` sample intervals. |
| **Per-grain envelope** | Each grain carries its own envelope phase and type — Hann, trapezoidal, or flat. |
| **Scatter randomisation** | Position, pitch, and amplitude jitter are applied from a shared noise engine at grain birth. |
| **Sample-accurate read** | Grains read from the source buffer with a per-grain step (pitch shift).  No interpolation — integer index. |
| **Hann via TRIG-SIN** | Hann envelope uses `TRIG-SIN` (not WT-LOOKUP) because it needs a half-cycle sin(π × phase). |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `GRAN-`.  Internal: `_GR-`.  Field: `GR.xxx` / `GS.xxx`. |

---

## Memory Layout

### Descriptor (128 bytes)

```
Offset  Size  Field
──────  ────  ──────────────────────────────
+0      8     source         Source PCM buffer pointer
+8      8     density        Grains per second (FP16)
+16     8     grain-ms       Grain duration in ms (integer)
+24     8     position       Read position 0.0–1.0 into source (FP16)
+32     8     pos-scatter    Position jitter range (FP16)
+40     8     pitch-shift    Pitch ratio (FP16, 1.0 = normal)
+48     8     pitch-scatter  Pitch jitter range (FP16)
+56     8     amp-scatter    Amplitude jitter range (FP16)
+64     8     envelope       Default envelope type (0/1/2)
+72     8     rate           Sample rate (integer)
+80     8     pool           Pointer to grain slot array (16 × 16 B)
+88     8     sched-ctr      Scheduling countdown (int)
+96     8     noise-eng      Noise engine pointer
+104    8     sched-period   Samples between grain spawns (int)
+112–127 -    (reserved)
```

### Grain Slot (16 bytes × 16 slots = 256 bytes)

```
Offset  Size  Field
──────  ────  ──────────────────
+0      2     src-pos     Current read position in source (int16)
+2      2     step        Read step per sample (FP16, pitch)
+4      2     env-phase   Envelope phase 0.0–1.0 (FP16)
+6      2     env-step    Envelope phase increment (FP16)
+8      2     amp         Grain amplitude (FP16)
+10     1     active      1 = sounding, 0 = free
+11     1     env-type    0 = Hann, 1 = trapezoidal, 2 = flat
+12–15  4     (padding)
```

---

## Creation & Destruction

### GRAN-CREATE

```forth
GRAN-CREATE  ( source-buf rate -- desc )
```

Allocate a granular descriptor and its 16-slot grain pool.
`source-buf` is a PCM buffer to read grains from; `rate` is the
integer sample rate.  Defaults: density 10 grains/s, grain 50 ms,
position 0.0, pitch 1.0, no scatter.

```forth
src-pcm 44100 GRAN-CREATE CONSTANT gr
```

### GRAN-FREE

```forth
GRAN-FREE  ( desc -- )
```

Free the grain pool, noise engine, and descriptor.

---

## Source Buffer

### GRAN-SOURCE!

```forth
GRAN-SOURCE!  ( buf desc -- )
```

Replace the source PCM buffer.  Active grains continue reading from
their current positions (they hold absolute offsets), so a source
swap mid-stream can cause artefacts — best done between render calls.

---

## Grain Parameters

### GRAN-DENSITY!

```forth
GRAN-DENSITY!  ( density desc -- )
```

Set grains-per-second (FP16).  Recomputes `sched-period`.

$$\text{sched\_period} = \left\lfloor \frac{\text{rate}}{\text{density}} \right\rfloor$$

| Density | Character |
|---------|-----------|
| 1–5     | Sparse, rhythmic pops |
| 10–20   | Smooth texture |
| 40+     | Dense cloud / smear |

```forth
20 INT>FP16 gr GRAN-DENSITY!
```

### GRAN-GRAIN!

```forth
GRAN-GRAIN!  ( ms desc -- )
```

Set grain duration in milliseconds (integer).  Longer grains =
smoother overlap; shorter = more percussive.

```forth
30 gr GRAN-GRAIN!
```

### GRAN-POSITION!

```forth
GRAN-POSITION!  ( pos desc -- )
```

Set the nominal read position into the source buffer (FP16 0.0–1.0).
0.0 = start; 1.0 = end.  Grains spawn near this position, offset
by scatter.

```forth
FP16-POS-HALF gr GRAN-POSITION!  \ read from centre
```

### GRAN-PITCH!

```forth
GRAN-PITCH!  ( ratio desc -- )
```

Set the pitch-shift ratio (FP16).  1.0 = original pitch; 2.0 = up
one octave; 0.5 = down one octave.

```forth
FP16-POS-HALF gr GRAN-PITCH!  \ half speed, octave down
```

---

## Scatter / Randomisation

### GRAN-SCATTER!

```forth
GRAN-SCATTER!  ( pos pitch amp desc -- )
```

Set the scatter (jitter) ranges for position, pitch, and amplitude.
All three are FP16.  At grain birth, each parameter is offset by a
random value in `[-scatter, +scatter]` drawn from the noise engine.

- **pos** — position scatter (fraction of source length)
- **pitch** — pitch ratio scatter (±)
- **amp** — amplitude scatter (±)

```forth
\ Moderate position jitter, slight pitch wobble, no amp scatter
3277 1638 FP16-POS-ZERO gr GRAN-SCATTER!   \ ~0.20 ~0.10 0.0
```

Setting all three to 0 produces perfectly repeatable grains — useful
for rhythmic effects.

---

## Rendering

### GRAN-RENDER

```forth
GRAN-RENDER  ( buf desc -- )
```

Fill a PCM buffer with granular synthesis output.  Per sample:

1. Decrement `sched-ctr`; if 0, spawn a new grain:
   - Find a free slot (or steal the oldest active one).
   - Set `src-pos` from `position + random(pos-scatter)`.
   - Set `step` from `pitch + random(pitch-scatter)`.
   - Set `amp` from `1.0 + random(amp-scatter)`.
   - Reset envelope phase to 0; set `env-step` from `grain-ms`.
   - Reset counter to `sched-period`.
2. For each active grain:
   - Compute envelope amplitude from `env-phase` and `env-type`.
   - Read source sample at `src-pos`; multiply by `amp × envelope`.
   - Accumulate into output sample.
   - Advance `src-pos` by `step`; advance `env-phase` by `env-step`.
   - If `env-phase ≥ 1.0`, mark slot inactive.
3. Write accumulated sample to buffer.

```forth
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf gr GRAN-RENDER
```

---

## Envelope Types

Set via the `envelope` field in the descriptor (integer 0, 1, or 2).
Applies to all subsequently spawned grains.

### Type 0 — Hann Window (default)

$$w(t) = \sin(\pi \cdot t), \quad t \in [0, 1]$$

Smooth fade-in and fade-out; no discontinuities at grain boundaries.
Standard choice for granular synthesis.

### Type 1 — Trapezoidal

```
     ┌────────────┐
    /              \
   / 10%  80%  10% \
──/                  \──
```

Linear 10% attack, 80% sustain at full amplitude, 10% release.
Slightly more present than Hann; useful for percussive grains.

### Type 2 — Flat (Rectangular)

Full amplitude for entire grain.  Produces clicks at grain
boundaries unless grains overlap heavily.  Use for glitch effects.

---

## Quick Reference

```
GRAN-CREATE    ( source-buf rate -- desc )
GRAN-FREE      ( desc -- )
GRAN-SOURCE!   ( buf desc -- )              swap source buffer
GRAN-DENSITY!  ( density desc -- )          grains/sec (FP16)
GRAN-GRAIN!    ( ms desc -- )               grain length ms (int)
GRAN-POSITION! ( pos desc -- )              source read pos 0–1 (FP16)
GRAN-PITCH!    ( ratio desc -- )            pitch shift (FP16)
GRAN-SCATTER!  ( pos pitch amp desc -- )    jitter ranges (FP16)
GRAN-RENDER    ( buf desc -- )              fill PCM buffer
```

---

## Cookbook

### Time-Stretch Freeze

```forth
\ Freeze on a single point in the source
src-pcm 44100 GRAN-CREATE CONSTANT gr
40 INT>FP16 gr GRAN-DENSITY!    \ dense cloud
50 gr GRAN-GRAIN!               \ 50 ms grains
FP16-POS-HALF gr GRAN-POSITION! \ freeze at centre
FP16-POS-ONE  gr GRAN-PITCH!    \ original pitch
FP16-POS-ZERO FP16-POS-ZERO FP16-POS-ZERO gr GRAN-SCATTER!
4096 44100 16 1 PCM-ALLOC CONSTANT buf
buf gr GRAN-RENDER
buf PCM-FREE  gr GRAN-FREE
```

### Texture Cloud with Scatter

```forth
src-pcm 44100 GRAN-CREATE CONSTANT gr
20 INT>FP16 gr GRAN-DENSITY!
30 gr GRAN-GRAIN!
FP16-POS-ZERO gr GRAN-POSITION!      \ start of source
\ Wide scatter for evolving texture
FP16-POS-HALF 3277 3277 gr GRAN-SCATTER!  \ ±0.5 pos, ±0.20 pitch/amp
2048 44100 16 1 PCM-ALLOC CONSTANT buf
buf gr GRAN-RENDER
buf PCM-FREE  gr GRAN-FREE
```

### Octave-Down Granular Bass

```forth
src-pcm 44100 GRAN-CREATE CONSTANT gr
15 INT>FP16 gr GRAN-DENSITY!
80 gr GRAN-GRAIN!               \ longer grains for bass
FP16-POS-ZERO gr GRAN-POSITION!
FP16-POS-HALF gr GRAN-PITCH!   \ half speed = octave down
FP16-POS-ZERO FP16-POS-ZERO FP16-POS-ZERO gr GRAN-SCATTER!
4096 44100 16 1 PCM-ALLOC CONSTANT buf
buf gr GRAN-RENDER
buf PCM-FREE  gr GRAN-FREE
```

### Glitch Stutter

```forth
src-pcm 44100 GRAN-CREATE CONSTANT gr
8 INT>FP16 gr GRAN-DENSITY!    \ sparse
10 gr GRAN-GRAIN!              \ very short — clicks
FP16-POS-ZERO gr GRAN-POSITION!
FP16-POS-ONE  gr GRAN-PITCH!
\ Use flat envelope for hard edges
2 gr 64 + !                      \ set envelope type = flat
FP16-POS-ZERO FP16-POS-ZERO FP16-POS-ZERO gr GRAN-SCATTER!
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf gr GRAN-RENDER
buf PCM-FREE  gr GRAN-FREE
```
