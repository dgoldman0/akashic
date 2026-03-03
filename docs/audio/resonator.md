# akashic-syn-resonator — Resonant Filter Bank Synthesis for KDOS / Megapad-64

Pushes white, pink, or brown noise through a bank of digital bandpass
filters (resonators).  The filters color the noise continuously; the
result is a steady, sustained sound whose spectral character is
entirely determined by filter center frequencies, Q values, and
amplitudes.

```forth
REQUIRE audio/syn/resonator.f
```

`PROVIDED akashic-syn-resonator` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-trig`,
`akashic-audio-noise`, `akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Sound Character Map](#sound-character-map)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Pole Configuration](#pole-configuration)
- [Noise & Excitation](#noise--excitation)
- [Rendering](#rendering)
- [Convenience Presets](#convenience-presets)
- [Biquad Internals](#biquad-internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Second-order IIR** | Each pole is a biquad bandpass (RBJ Audio EQ, constant peak gain).  Direct-form II transposed. |
| **Persistent state** | Biquad streaming registers `s1`, `s2` persist across `RESON-RENDER` calls, ensuring phase continuity. |
| **Coefficients once** | Biquad coefficients are computed at `RESON-POLE!` time; the inner render loop only applies them. |
| **Noise excitation** | White, pink, or brown noise → all poles in parallel → sum.  Pulsed mode modulates the excitation at 40 Hz for breath-like articulation. |
| **Silent pole skip** | Poles with `amp = 0` are skipped in the inner loop. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `RESON-`.  Internal: `_RS-`.  Field: `RS.xxx` / `RP.xxx`. |

---

## Sound Character Map

| Poles | Q | Noise | Mode | Character |
|-------|---|-------|------|-----------|
| Few, wide Q | 2–5 | White | Continuous | Colored drone, wind |
| Many, narrow Q | 10–20 | White | Continuous | Pitched tone cluster, vowel |
| Harmonic series | 10+ | White | Pulsed | Breath-driven flute |
| Mixed | Low | Pink/brown | Continuous | Steam, bubbles, ambient |
| Formant set | 8–12 | White | Continuous | Vocal approximation |

---

## Memory Layout

### Descriptor (8 cells = 64 bytes)

```
Offset  Size  Field
──────  ────  ──────────────────────
+0      8     n-poles       Number of filter bands (integer, 1–16)
+8      8     noise-color   0 = white, 1 = pink, 2 = brown (integer)
+16     8     excitation    0 = continuous, 1 = pulsed (integer)
+24     8     intensity     Overall excitation level 0.0–1.0 (FP16)
+32     8     rate          Sample rate Hz (integer)
+40     8     poles-addr    Pointer to pole block (N × 24 bytes)
+48     8     noise-eng     Pointer to persistent noise generator
+56     8     pulse-ctr     Frame counter for pulsed mode (integer)
```

### Per-Pole Block (24 bytes per pole)

```
Offset  Size  Field
──────  ────  ──────────────────────
+0      2     center-hz     Filter center frequency (FP16)
+2      2     Q             Resonance / sharpness (FP16, typical 1–20)
+4      2     amp           Pole amplitude 0.0–1.0 (FP16)
+6      2     b0n           Normalized biquad coefficient b0 (FP16)
+8      2     neg-a1n       Normalized −a1 coefficient (FP16)
+10     2     neg-a2n       Normalized −a2 coefficient (FP16)
+12     2     s1            Streaming state register 1 (FP16)
+14     2     s2            Streaming state register 2 (FP16)
+16–23  8     (padding)
```

---

## Creation & Destruction

### RESON-CREATE

```forth
RESON-CREATE  ( n-poles rate -- desc )
```

Allocate a resonator descriptor, pole block, and white noise
generator.  All poles are zeroed (silent until configured with
`RESON-POLE!`).

- **n-poles** — number of filter bands (integer, 1–16)
- **rate** — sample rate in Hz (integer)

Defaults: `noise-color = 0` (white), `excitation = 0` (continuous),
`intensity = 1.0`.

```forth
5 44100 RESON-CREATE CONSTANT rez
```

### RESON-FREE

```forth
RESON-FREE  ( desc -- )
```

Free noise generator, pole block, and descriptor.

---

## Pole Configuration

### RESON-POLE!

```forth
RESON-POLE!  ( center-hz Q amp i desc -- )
```

Configure one filter pole and compute its biquad coefficients.

- **center-hz** — filter center frequency (FP16)
- **Q** — resonance (FP16, higher = narrower/sharper)
- **amp** — pole contribution amplitude (FP16 0.0–1.0)
- **i** — zero-based pole index (integer)

Resets the pole's streaming state (`s1`, `s2`) to zero.

```forth
440 INT>FP16 10 INT>FP16 FP16-POS-ONE 0 rez RESON-POLE!
```

---

## Noise & Excitation

### RESON-NOISE!

```forth
RESON-NOISE!  ( color intensity desc -- )
```

Set noise color and overall intensity.

- **color** — `0` = white, `1` = pink, `2` = brown
- **intensity** — FP16 0.0–1.0

If the color changes, the old noise generator is freed and a new one
created.

### RESON-EXCITE!

```forth
RESON-EXCITE!  ( mode desc -- )
```

Set excitation mode: `0` = continuous, `1` = pulsed (40 Hz breath
envelope).

### RESON-BLOW!

```forth
RESON-BLOW!  ( intensity desc -- )
```

Live intensity modulation (FP16 0.0–1.0).  Change between render
calls for dynamic control.

---

## Rendering

### RESON-RENDER

```forth
RESON-RENDER  ( buf desc -- )
```

Fill a PCM buffer with resonator output.  For each sample:

1. Generate noise, scale by intensity (and pulse envelope if pulsed).
2. Route through all active poles (biquad bandpass).
3. Accumulate pole outputs weighted by `amp`.
4. Write the sum to the output buffer.

Call repeatedly in a render loop for continuous output.  Biquad
streaming state persists between calls — no clicks at buffer
boundaries.

```forth
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf rez RESON-RENDER
```

---

## Convenience Presets

### RESON-HARM-FILL

```forth
RESON-HARM-FILL  ( fundamental-hz Q n desc -- )
```

Fill poles 0..n-1 with harmonics: `f`, `2f`, `3f`, ... at equal
amplitude (`1/n`).  Useful for quick harmonic series resonance.

```forth
\ 5 harmonics of A4 at Q=10
440 INT>FP16  10 INT>FP16  5  rez RESON-HARM-FILL
```

### RESON-VOWEL-FILL

```forth
RESON-VOWEL-FILL  ( desc -- )
```

Load 5 formant bands approximating an open vowel "a":

| Formant | Center Hz | Q | Amp |
|---------|-----------|---|-----|
| F0 | 800 | 10 | 0.35 |
| F1 | 1200 | 8 | 0.35 |
| F2 | 2500 | 12 | 0.25 |
| F3 | 3700 | 10 | 0.15 |
| F4 | 5000 | 6 | 0.125 |

Descriptor must have at least 5 poles.

```forth
5 44100 RESON-CREATE CONSTANT voice
voice RESON-VOWEL-FILL
```

---

## Biquad Internals

Each pole implements a classic RBJ Audio EQ bandpass (constant peak
gain) via direct-form II transposed:

$$\omega = 2\pi \cdot \frac{f_c}{\text{rate}}, \quad
\alpha = \frac{\sin(\omega)}{2Q}$$

$$b_0 = \frac{\sin(\omega)}{2}, \quad
a_0 = 1 + \alpha, \quad
a_1 = -2\cos(\omega), \quad
a_2 = 1 - \alpha$$

Normalized: $b_{0n} = b_0 / a_0$, stored alongside $-a_1/a_0$ and
$-a_2/a_0$ to avoid per-sample division.

Per-sample update (transposed direct form II):

$$y = b_{0n} \cdot x + s_1$$
$$s_1 = (-a_{1n}) \cdot y + s_2 + (-b_{0n}) \cdot x$$
$$s_2 = (-a_{2n}) \cdot y$$

---

## Quick Reference

```
RESON-CREATE     ( n-poles rate -- desc )
RESON-FREE       ( desc -- )
RESON-POLE!      ( center Q amp i desc -- )   set one pole
RESON-NOISE!     ( color intensity desc -- )  noise params
RESON-EXCITE!    ( mode desc -- )             0=cont 1=pulsed
RESON-BLOW!      ( intensity desc -- )        live intensity
RESON-RENDER     ( buf desc -- )              fill PCM buffer
RESON-HARM-FILL  ( fund Q n desc -- )         harmonic series
RESON-VOWEL-FILL ( desc -- )                  open 'a' formants
```

---

## Cookbook

### Simple Harmonic Resonance

```forth
5 44100 RESON-CREATE CONSTANT rez
440 INT>FP16 10 INT>FP16 5 rez RESON-HARM-FILL
1024 44100 16 1 PCM-ALLOC CONSTANT buf
buf rez RESON-RENDER
buf PCM-FREE  rez RESON-FREE
```

### Wind-Like Drone

```forth
3 44100 RESON-CREATE CONSTANT wind
\ Wide (low Q) filters spread across low frequencies
200 INT>FP16  3 INT>FP16  FP16-POS-ONE  0  wind RESON-POLE!
500 INT>FP16  4 INT>FP16  FP16-POS-HALF 1  wind RESON-POLE!
900 INT>FP16  3 INT>FP16  0x3400        2  wind RESON-POLE!
4096 44100 16 1 PCM-ALLOC CONSTANT buf
buf wind RESON-RENDER
buf PCM-FREE  wind RESON-FREE
```

### Pulsed Breath Flute

```forth
4 44100 RESON-CREATE CONSTANT flute
440 INT>FP16 15 INT>FP16 4 flute RESON-HARM-FILL
1 flute RESON-EXCITE!           \ pulsed mode
2048 44100 16 1 PCM-ALLOC CONSTANT buf
buf flute RESON-RENDER
buf PCM-FREE  flute RESON-FREE
```

### Vocal Approximation

```forth
5 44100 RESON-CREATE CONSTANT voice
voice RESON-VOWEL-FILL
4096 44100 16 1 PCM-ALLOC CONSTANT speech
speech voice RESON-RENDER
speech PCM-FREE  voice RESON-FREE
```
