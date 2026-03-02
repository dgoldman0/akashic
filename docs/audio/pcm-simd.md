# akashic-audio-pcm-simd — SIMD Bulk Operations on PCM Buffers for KDOS / Megapad-64

Thin wrappers around `simd-ext.f` that operate directly on PCM
buffer descriptors.  For mono 16-bit buffers (the standard audio
pipeline format), `PCM-DATA` already points to a packed array of
2-byte FP16 values — exactly the layout that `SIMD-*-N` expects.
No conversion is needed.

```forth
REQUIRE audio/pcm-simd.f
```

`PROVIDED akashic-audio-pcm-simd` — safe to include multiple times.
Depends on `akashic-math-simd-ext`, `akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Why SIMD for Audio?](#why-simd-for-audio)
- [API](#api)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **PCM descriptor aware** | Each word accepts PCM buffer pointers, extracts data address and element count automatically. |
| **Mono + stereo** | Element count is `frames × channels`, so stereo buffers are processed correctly (all interleaved samples). |
| **512-bit tiles** | Internally dispatches via the Megapad-64 FP16 SIMD tile engine (32 lanes × FP16). Full tiles processed with `TADD`/`TMUL` (1–2 cycles each). |
| **Remainder handling** | After processing complete 32-element tiles, remaining elements are handled with a scalar loop. |
| **No allocation** | All operations are in-place or src→dst with no temporary buffers. |
| **Prefix convention** | Public: `PCM-SIMD-`.  Internal: `_PSIMD-`. |

---

## Why SIMD for Audio?

A typical audio block is 256–4096 frames.  Per-sample FP16 arithmetic
costs ~4–6 Forth words per operation (load, operate, store, loop overhead).
The SIMD tile engine processes 32 FP16 values per instruction:

| Operation | Scalar cost | SIMD cost | Speedup |
|-----------|-------------|-----------|---------|
| Scale 800 samples | ~5600 words | ~80 words | ~70× |
| Add two 800-sample buffers | ~5600 words | ~80 words | ~70× |
| Mix (scale + accumulate) | ~8000 words | ~120 words | ~67× |

These speedups compound when multiple operations are chained
(e.g. envelope sustain → scale, mixer master gain → scale).

---

## API

### PCM-SIMD-ADD

```forth
PCM-SIMD-ADD  ( src dst -- )
```

Elementwise addition: `dst[i] += src[i]`.

Both buffers must be 16-bit.  The operation processes
`min(src_samples, dst_samples)` elements.  Uses `SIMD-ADD-N`
internally: `dst[i] = src[i] + dst[i]`.

```forth
buf-osc1 buf-mix PCM-SIMD-ADD      \ accumulate osc1 into mix
```

### PCM-SIMD-SCALE

```forth
PCM-SIMD-SCALE  ( scalar buf -- )
```

In-place broadcast multiply: `buf[i] *= scalar`.

**scalar** is an FP16 gain value.  Uses `SIMD-SCALE-N` with
`src = dst = buf.data`.

```forth
0x3800 my-buf PCM-SIMD-SCALE       \ halve all samples (×0.5)
```

### PCM-SIMD-MIX

```forth
PCM-SIMD-MIX  ( gain src dst -- )
```

Scaled accumulation: `dst[i] += gain × src[i]`.

Uses `SIMD-SAXPY-N` (single-precision A×X+Y): `dst[i] = gain × src[i] + dst[i]`.
Useful for mixing with a per-channel gain in one pass.

```forth
0x3800 buf-voice buf-master PCM-SIMD-MIX   \ mix at -6 dB
```

### PCM-SIMD-MUL

```forth
PCM-SIMD-MUL  ( src dst -- )
```

Elementwise multiply: `dst[i] *= src[i]`.

Uses `SIMD-MUL-N`.  Useful for applying a sample-by-sample gain
curve (e.g. an envelope buffer × audio buffer).

```forth
buf-envelope buf-audio PCM-SIMD-MUL    \ amplitude modulation
```

### PCM-SIMD-FILL

```forth
PCM-SIMD-FILL  ( val buf -- )
```

Fill every sample with a constant FP16 value.  Uses `SIMD-FILL-N`.

```forth
FP16-POS-HALF my-buf PCM-SIMD-FILL    \ fill with 0.5
```

### PCM-SIMD-CLEAR

```forth
PCM-SIMD-CLEAR  ( buf -- )
```

Zero all sample data.  Uses `FILL` with 0 on the raw data bytes.

```forth
my-buf PCM-SIMD-CLEAR                  \ silence
```

---

## Quick Reference

```
PCM-SIMD-ADD    ( src dst -- )          dst[i] += src[i]
PCM-SIMD-SCALE  ( scalar buf -- )      buf[i] *= scalar  (in-place)
PCM-SIMD-MIX    ( gain src dst -- )    dst[i] += gain × src[i]
PCM-SIMD-MUL    ( src dst -- )         dst[i] *= src[i]
PCM-SIMD-FILL   ( val buf -- )         fill every sample with val
PCM-SIMD-CLEAR  ( buf -- )             zero all samples
```

---

## Cookbook

### Additive Mixing (Two Sources)

```forth
buf-osc1 buf-master PCM-SIMD-ADD
buf-osc2 buf-master PCM-SIMD-ADD
```

### Apply Constant Gain

```forth
\ Reduce amplitude to 25% (−12 dB)
0x3400 my-buf PCM-SIMD-SCALE
```

### Weighted Mix of Three Voices

```forth
0x3C00 buf-voice1 buf-master PCM-SIMD-MIX   \ voice1 at 1.0
0x3800 buf-voice2 buf-master PCM-SIMD-MIX   \ voice2 at 0.5
0x3400 buf-voice3 buf-master PCM-SIMD-MIX   \ voice3 at 0.25
```

### Silence a Buffer Before Mixing

```forth
buf-master PCM-SIMD-CLEAR
buf-ch0 buf-master PCM-SIMD-ADD
buf-ch1 buf-master PCM-SIMD-ADD
```

### Amplitude Modulation via Element Multiply

```forth
\ Multiply audio by an LFO envelope buffer (sample-by-sample)
buf-lfo buf-audio PCM-SIMD-MUL
```
