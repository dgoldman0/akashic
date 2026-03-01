# akashic-audio-noise — Noise Generators for KDOS / Megapad-64

Three noise generator types: white (LFSR), pink (Voss-McCartney),
and brown (leaky integrator).  All output is FP16 in `[−1.0, +1.0]`.
Fills `pcm.f` buffers one frame at a time.

```forth
REQUIRE audio/noise.f
```

`PROVIDED akashic-audio-noise` — safe to include multiple times.
Depends on `akashic-audio-pcm`, `akashic-fp16`, `akashic-fp16-ext`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Single-Sample Generation](#single-sample-generation)
- [Bulk Generation](#bulk-generation)
- [Noise Types](#noise-types)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **LFSR core** | All noise types build on a 16-bit Galois LFSR (taps `0xB400`). |
| **TRNG seeding** | LFSR state seeded from hardware TRNG via `RANDOM16`. |
| **FP16 output** | Samples are FP16 bit patterns in `[−1.0, +1.0]`. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `NOISE-`.  Internal: `_NZ-`.  Field: `N.xxx`. |
| **PCM integration** | `NOISE-FILL` and `NOISE-ADD` write directly into PCM buffers. |

---

## Memory Layout

A noise descriptor occupies 6 cells = 48 bytes:

```
Offset  Size  Field
──────  ────  ──────────────
+0      8     type     — noise type (0=white, 1=pink, 2=brown)
+8      8     state    — LFSR state (16-bit, never 0)
+16     8     accum    — brown noise accumulator (FP16)
+24     8     counter  — pink noise sample counter
+32     8     rows     — pointer to 8-cell LFSR row array (pink only)
+40     8     (reserved)
```

Pink noise additionally allocates a separate 64-byte array (8 cells)
to hold one LFSR state per octave band.

---

## Creation & Destruction

### NOISE-CREATE

```forth
NOISE-CREATE  ( type -- desc )
```

Allocate and seed a noise generator.

- **type** — one of `NOISE-WHITE`, `NOISE-PINK`, `NOISE-BROWN`

The LFSR is seeded from hardware TRNG.  Pink noise also allocates
and seeds 8 octave-band LFSR rows.

```forth
NOISE-WHITE NOISE-CREATE CONSTANT wn
NOISE-PINK  NOISE-CREATE CONSTANT pn
NOISE-BROWN NOISE-CREATE CONSTANT bn
```

### NOISE-FREE

```forth
NOISE-FREE  ( desc -- )
```

Free the descriptor and the pink row array (if present).

---

## Single-Sample Generation

### NOISE-SAMPLE

```forth
NOISE-SAMPLE  ( desc -- value )
```

Generate one FP16 noise sample.  Dispatches to the appropriate
algorithm based on `N.TYPE`:

| Type | Algorithm |
|------|-----------|
| `NOISE-WHITE` | Step LFSR → center → normalise to `[−1, +1]` |
| `NOISE-PINK`  | Voss-McCartney: update one octave row per step, sum all 8, normalise |
| `NOISE-BROWN` | Leaky integrator: `accum = accum × 0.98 + white × 0.02`, clamp `[−1, +1]` |

---

## Bulk Generation

### NOISE-FILL

```forth
NOISE-FILL  ( buf desc -- )
```

Fill a PCM buffer with noise.  Uses `PCM-LEN` for frame count and
`PCM-FRAME!` for writes.

```forth
1024 44100 16 1 PCM-ALLOC CONSTANT nbuf
nbuf wn NOISE-FILL
```

### NOISE-ADD

```forth
NOISE-ADD  ( buf desc -- )
```

Add noise to existing buffer content (`PCM-FRAME@ + FP16-ADD`).
Use for layering noise on top of tonal signals.

```forth
nbuf my-sine OSC-FILL      \ tonal base
nbuf wn     NOISE-ADD      \ add white noise
```

---

## Noise Types

### White Noise (`NOISE-WHITE = 0`)

- **Algorithm:** 16-bit Galois LFSR (polynomial taps `0xB400`).
- **Spectrum:** Flat (equal energy per frequency bin).
- **Use:** Hiss, snare/hi-hat transients, dithering.

Each sample:
1. Step the LFSR: if bit 0 set, shift right and XOR taps; else just shift.
2. Mask to 16 bits.
3. Center: `state − 32768` → signed integer.
4. Convert to FP16 and divide by 32768 (split as `÷128 × ÷256` to
   avoid subnormal FP16 reciprocal).

### Pink Noise (`NOISE-PINK = 1`)

- **Algorithm:** Voss-McCartney with 8 octave-band LFSR rows.
- **Spectrum:** −3 dB/octave (equal energy per octave).
- **Use:** Natural/ambient textures, rain, wind.

Each sample:
1. Increment counter.
2. Find the lowest set bit index (count trailing zeros, clamped to 7).
3. Update that row's LFSR.
4. Sum all 8 rows (centered to signed), divide by 8.
5. Normalise to FP16 `[−1, +1]`.

### Brown Noise (`NOISE-BROWN = 2`)

- **Algorithm:** Leaky integrator of white noise.
- **Spectrum:** −6 dB/octave (random walk, heavily bass-weighted).
- **Use:** Thunder, rumble, low drones.

Each sample:
1. Generate a white noise sample.
2. `accum = accum × 0.98 + white × 0.02` (all FP16 arithmetic).
3. Clamp accumulator to `[−1.0, +1.0]`.

---

## Quick Reference

```
NOISE-CREATE   ( type -- desc )     create noise generator
NOISE-FREE     ( desc -- )          free descriptor
NOISE-SAMPLE   ( desc -- value )    one FP16 noise sample
NOISE-FILL     ( buf desc -- )      fill PCM buffer
NOISE-ADD      ( buf desc -- )      add noise to PCM buffer
```

**Type constants:**

```
NOISE-WHITE   0
NOISE-PINK    1
NOISE-BROWN   2
```

---

## Cookbook

### White Noise Burst (50 ms)

```forth
NOISE-WHITE NOISE-CREATE CONSTANT wn
50 44100 16 1 PCM-ALLOC-MS CONSTANT burst
burst wn NOISE-FILL
wn NOISE-FREE
```

### Layered Noise: Pink + Sine Pad

```forth
NOISE-PINK NOISE-CREATE CONSTANT pn
220 INT>FP16 OSC-SINE 44100 OSC-CREATE CONSTANT pad
4096 44100 16 1 PCM-ALLOC CONSTANT mix
mix pad OSC-FILL       \ tonal bed
mix pn  NOISE-ADD      \ add pink texture
```

### Brown Noise Floor

```forth
NOISE-BROWN NOISE-CREATE CONSTANT bn
44100 44100 16 1 PCM-ALLOC CONSTANT floor
floor bn NOISE-FILL    \ 1 second of rumble
```
