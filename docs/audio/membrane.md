# akashic-syn-membrane — Membrane + Noise Percussive Synthesis for KDOS / Megapad-64

Models a struck membrane as two summed components: a frequency-sweeping
sine tone (fundamental mode relaxation) and bandpass-filtered noise
(stick impact / upper mode incoherence).  Blend and decay times
determine everything about sound character — from tuned kettledrums
to dry snare hits.

```forth
REQUIRE audio/syn/membrane.f
```

`PROVIDED akashic-syn-membrane` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-trig`,
`akashic-audio-osc`, `akashic-audio-noise`, `akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Sound Character Map](#sound-character-map)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Setters](#setters)
- [Rendering](#rendering)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Two-component model** | Tone (swept sine) + noise (filtered), each with independent amplitude and linear decay. |
| **Frequency sweep** | Tone frequency linearly interpolates from `freq-start` to `freq-end` over `sweep-ms`, then holds at `freq-end`. |
| **Bandpass noise** | 1-pole HP + 1-pole LP chain approximates a bandpass filter.  `noise-lo` sets the HP cutoff, `noise-hi` the LP cutoff. |
| **Linear envelopes** | Both tone and noise use simple linear decay: `level -= 1.0 / decay_frames` per sample.  Fast and FP16-friendly. |
| **Wavetable sine** | Tone oscillator uses `WT-SIN-TABLE WT-LOOKUP` for fast per-sample generation. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `MEMB-`.  Internal: `_MB-`.  Field: `MB.xxx`. |

---

## Sound Character Map

| Tone Ratio | Sweep | Noise | Decay | Character |
|------------|-------|-------|-------|-----------|
| Low, deep | Wide sweep down | Low mix | Slow | Large resonant drum |
| Mid | Narrow sweep | Moderate | Medium | Toms, congas |
| High | Narrow | High, white | Fast noise | Snare |
| Near-zero | — | All noise | Short | Dry impact, click |
| Low | None | Zero | Very slow | Tuned kettle |

---

## Memory Layout

A membrane descriptor occupies 12 cells = 96 bytes:

```
Offset  Size  Field
──────  ────  ───────────────────
+0      8     freq-start     Tone sweep start Hz (FP16)
+8      8     freq-end       Tone sweep end / sustain Hz (FP16)
+16     8     sweep-ms       Sweep duration ms (integer)
+24     8     tone-decay-ms  Tone decay time ms (integer)
+32     8     tone-amp       Tone amplitude 0.0–1.0 (FP16)
+40     8     noise-color    0 = white, 1 = pink (integer)
+48     8     noise-lo       HP cutoff Hz (FP16, 0 = no HP)
+56     8     noise-hi       LP cutoff Hz (FP16, 0 = no LP)
+64     8     noise-decay-ms Noise decay time ms (integer)
+72     8     noise-amp      Noise amplitude 0.0–1.0 (FP16)
+80     8     rate           Sample rate Hz (integer)
+88     8     (reserved)
```

---

## Creation & Destruction

### MEMB-CREATE

```forth
MEMB-CREATE  ( rate -- desc )
```

Allocate a membrane descriptor with sensible defaults:

| Parameter | Default |
|-----------|---------|
| freq-start | 200 Hz |
| freq-end | 60 Hz |
| sweep-ms | 20 |
| tone-decay-ms | 300 |
| tone-amp | 0.8 |
| noise-color | white (0) |
| noise-lo | 200 Hz |
| noise-hi | 8000 Hz |
| noise-decay-ms | 80 |
| noise-amp | 0.5 |

```forth
44100 MEMB-CREATE CONSTANT drum
```

### MEMB-FREE

```forth
MEMB-FREE  ( desc -- )
```

Free the descriptor.

---

## Setters

### MEMB-TONE!

```forth
MEMB-TONE!  ( start-hz end-hz sweep-ms tone-decay-ms desc -- )
```

Set the tonal component parameters.  Hz values are FP16,
ms values are integers.

```forth
\ Kick drum: 180 → 50 Hz, 15 ms sweep, 250 ms decay
180 INT>FP16 50 INT>FP16 15 250 drum MEMB-TONE!
```

### MEMB-NOISE!

```forth
MEMB-NOISE!  ( lo-hz hi-hz noise-decay-ms desc -- )
```

Set noise bandpass cutoffs and decay.  Hz values are FP16,
ms is integer.

```forth
\ Snare-like band: 200–6000 Hz, 60 ms decay
200 INT>FP16 6000 INT>FP16 60 drum MEMB-NOISE!
```

### MEMB-MIX!

```forth
MEMB-MIX!  ( tone-amp noise-amp desc -- )
```

Set the amplitude blend between tone and noise components.
Both are FP16 0.0–1.0.

```forth
\ Pure tonal drum (no noise)
FP16-POS-ONE FP16-POS-ZERO drum MEMB-MIX!
```

### MEMB-COLOR!

```forth
MEMB-COLOR!  ( color desc -- )
```

Set noise color: 0 = white, 1 = pink.

---

## Rendering

### MEMB-STRIKE

```forth
MEMB-STRIKE  ( velocity desc -- buf )
```

Render a complete membrane strike to a freshly allocated mono 16-bit
PCM buffer.

- **velocity** — strike intensity (FP16 0.0–1.0), scales both
  tone-amp and noise-amp

Duration = max(tone-decay-ms, noise-decay-ms), clamped to 10–8000 ms.
Caller must `PCM-FREE` when done.

Internally creates a temporary noise generator (freed after render).

```forth
FP16-POS-ONE drum MEMB-STRIKE CONSTANT hit
hit PCM-FREE
```

### MEMB-STRIKE-INTO

```forth
MEMB-STRIKE-INTO  ( buf velocity desc -- )
```

Render and *add* into an existing PCM buffer.  The temporary strike
buffer is allocated internally, mixed sample-by-sample, then freed.
The shorter of the two buffers determines the mix length.

```forth
4096 44100 16 1 PCM-ALLOC CONSTANT mix
mix FP16-POS-ONE drum MEMB-STRIKE-INTO
```

---

## Internals

### Per-sample render

Each sample is the sum of:

1. **Tone:** `sin(phase) × tone_amp × velocity × env`, where
   phase advances at an interpolated frequency between `freq-start`
   and `freq-end` during the sweep window.
2. **Noise:** `raw → HP → LP → × noise_amp × velocity × env`.

Both envelopes decay linearly from 1.0 to 0.0 over their
respective `decay-ms` durations.

### Filter approximations

HP and LP alphas are computed from cutoff Hz:

$$\alpha_{LP} = \frac{2\pi \cdot f_c}{\text{rate}} \quad (\text{clipped to } [0, 1])$$

$$\alpha_{HP} = 1 - \alpha_{LP}$$

Where $2\pi \approx 6$ (integer approximation, sufficient for noise
coloring).

---

## Quick Reference

```
MEMB-CREATE      ( rate -- desc )
MEMB-FREE        ( desc -- )
MEMB-TONE!       ( start end sweep-ms decay-ms desc -- )
MEMB-NOISE!      ( lo hi decay-ms desc -- )
MEMB-MIX!        ( tone-amp noise-amp desc -- )
MEMB-COLOR!      ( color desc -- )               0=white 1=pink
MEMB-STRIKE      ( velocity desc -- buf )         render → new PCM
MEMB-STRIKE-INTO ( buf velocity desc -- )         render → add into
```

---

## Cookbook

### Basic Kick Drum

```forth
44100 MEMB-CREATE CONSTANT kick
180 INT>FP16 40 INT>FP16 10 200 kick MEMB-TONE!
FP16-POS-ONE 0x3266 kick MEMB-MIX!    \ loud tone, quiet noise
FP16-POS-ONE kick MEMB-STRIKE CONSTANT k-buf
k-buf PCM-FREE  kick MEMB-FREE
```

### Snare

```forth
44100 MEMB-CREATE CONSTANT snare
300 INT>FP16 180 INT>FP16 5 80 snare MEMB-TONE!
200 INT>FP16 8000 INT>FP16 60 snare MEMB-NOISE!
FP16-POS-HALF FP16-POS-ONE snare MEMB-MIX!  \ noise-heavy
FP16-POS-ONE snare MEMB-STRIKE CONSTANT s-buf
s-buf PCM-FREE  snare MEMB-FREE
```

### Layered Drum Hit

```forth
44100 MEMB-CREATE CONSTANT tom
200 INT>FP16 80 INT>FP16 15 250 tom MEMB-TONE!
4096 44100 16 1 PCM-ALLOC CONSTANT mix
mix FP16-POS-ONE  tom MEMB-STRIKE-INTO   \ first hit
mix FP16-POS-HALF tom MEMB-STRIKE-INTO   \ ghost note
mix PCM-FREE  tom MEMB-FREE
```
