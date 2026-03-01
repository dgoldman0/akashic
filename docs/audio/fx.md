# akashic-audio-fx — Audio Effects Collection for KDOS / Megapad-64

Audio effects that transform PCM buffers in-place.  Each effect has a
`CREATE` word (heap descriptor), a `PROCESS` word with the signature
`( buf desc -- )`, and a `FREE` word.  All effects plug directly into
`chain.f` slots.

**Phase 2a** provides two effects:
- **FX-DELAY** — Delay / Echo (circular delay line with feedback)
- **FX-DIST** — Distortion / Bitcrusher (soft clip, hard clip, bitcrush)

Future subphases will add reverb, chorus, parametric EQ, and compressor.

```forth
REQUIRE audio/fx.f
```

`PROVIDED akashic-audio-fx` — safe to include multiple times.
Depends on `akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Internal: Circular Delay Line](#internal-circular-delay-line)
- [FX-DELAY — Delay / Echo](#fx-delay--delay--echo)
- [FX-DIST — Distortion / Bitcrusher](#fx-dist--distortion--bitcrusher)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **FP16 audio** | All sample values are IEEE 754 half-precision bit patterns in 16-bit PCM buffers. |
| **In-place processing** | Effects modify the PCM buffer directly.  No intermediate buffers needed. |
| **Chain-compatible** | Every PROCESS word has `( buf desc -- )` signature for `CHAIN-SET!`. |
| **Heap descriptors** | Effect state lives in heap-allocated descriptors.  Caller owns them. |
| **Circular delay line** | Uses a custom heap-allocated circular buffer (not KDOS `RING`) for per-sample DSP performance — direct `W@`/`W!` without spinlock overhead. |
| **Variable-based scratch** | Non-reentrant.  Uses `VARIABLE`s for intermediate state. |

---

## Internal: Circular Delay Line

The `_DL-` words provide a circular buffer of FP16 samples used
internally by delay-based effects (delay, reverb, chorus).

### Memory Layout (3 cells = 24 bytes)

```
Offset  Size  Field
──────  ────  ──────────
+0      8     capacity  — max samples (integer)
+8      8     wptr      — write position, 0 .. capacity-1
+16     8     data      — pointer to sample buffer (2 bytes/sample)
```

### Internal API

| Word | Stack | Description |
|------|-------|-------------|
| `_DL-CREATE` | `( capacity -- dl )` | Allocate delay line (zeroed) |
| `_DL-FREE` | `( dl -- )` | Free delay line |
| `_DL-WRITE` | `( sample dl -- )` | Write sample at head, advance |
| `_DL-TAP` | `( offset dl -- sample )` | Read sample at offset behind head |

**Tap convention:** offset 0 = most recent sample, offset N = sample
from N+1 writes ago.  Clamped to `[0, capacity-1]`.

---

## FX-DELAY — Delay / Echo

A feedback delay that stores past samples in a circular delay line.
Produces echoes that decay over time.

### Algorithm

For each sample in the buffer:

```
delayed  ← _DL-TAP(delay_frames - 1)
output   ← LERP(input, delayed, wet)       \ wet=0: dry, wet=1: delayed
feed_val ← input + feedback × delayed
_DL-WRITE(feed_val)
```

### Memory Layout (5 cells = 40 bytes)

```
Offset  Size  Field
──────  ────  ──────────
+0      8     dl        — pointer to delay line
+8      8     delay     — delay in frames (integer)
+16     8     feedback  — feedback gain 0.0–1.0 (FP16)
+24     8     wet       — wet/dry mix 0.0–1.0 (FP16)
+32     8     rate      — sample rate (integer)
```

### API

#### FX-DELAY-CREATE

```forth
FX-DELAY-CREATE  ( delay-ms rate -- desc )
```

Creates a delay effect.  The delay line is sized for `delay-ms`
milliseconds at the given sample rate.  Defaults: feedback = 0.5,
wet = 0.5.

#### FX-DELAY-FREE

```forth
FX-DELAY-FREE  ( desc -- )
```

Frees the delay line and descriptor.

#### FX-DELAY!

```forth
FX-DELAY!  ( ms desc -- )
```

Changes delay time in milliseconds.  Clamped to the delay line's
capacity (set at creation time).

#### FX-DELAY-FB! / FX-DELAY-WET!

```forth
FX-DELAY-FB!   ( fb  desc -- )    \ set feedback (FP16)
FX-DELAY-WET!  ( wet desc -- )    \ set wet/dry mix (FP16)
```

#### FX-DELAY-PROCESS

```forth
FX-DELAY-PROCESS  ( buf desc -- )
```

Applies the delay effect to every sample in the buffer, in-place.

---

## FX-DIST — Distortion / Bitcrusher

Three distortion modes selected at creation time.

### Modes

| Mode | Name | Formula |
|------|------|---------|
| 0 | Soft clip | $\text{out} = \frac{t}{1 + |t|}$ where $t = x \times \text{drive}$ |
| 1 | Hard clip | $\text{out} = \text{clamp}(x \times \text{drive}, -1, +1)$ |
| 2 | Bitcrush | Zero lower N mantissa bits + sample-and-hold every Nth sample |

**Soft clip** produces smooth saturation that approaches ±1.0
asymptotically — no harsh edges, no lookup table needed.

**Hard clip** simply clamps the amplified signal — creates harsh
square-edge distortion.

**Bitcrush** reduces effective bit depth and sample rate.  The `drive`
parameter (converted to integer N) controls both:
- **Bit reduction:** zero the lowest N bits of the FP16 mantissa
- **Sample-and-hold:** capture a new sample every N frames, hold
  between captures

### Memory Layout (4 cells = 32 bytes)

```
Offset  Size  Field
──────  ────  ──────────
+0      8     drive  — FP16 gain (modes 0/1) or crush amount (mode 2)
+8      8     mode   — 0=soft, 1=hard, 2=bitcrush
+16     8     hold   — last held sample (bitcrush state)
+24     8     cnt    — hold counter (bitcrush state)
```

### API

#### FX-DIST-CREATE

```forth
FX-DIST-CREATE  ( drive mode -- desc )
```

Creates a distortion effect.  `drive` is an FP16 value:
- Modes 0/1: gain multiplier (e.g., 2.0 = 0x4000)
- Mode 2: crush amount as FP16 integer (e.g., 4.0 = 0x4400 for 4-bit crush)

#### FX-DIST-FREE

```forth
FX-DIST-FREE  ( desc -- )
```

Frees the descriptor (no secondary buffers to free).

#### FX-DIST-DRIVE!

```forth
FX-DIST-DRIVE!  ( drive desc -- )
```

Updates the drive parameter.

#### FX-DIST-PROCESS

```forth
FX-DIST-PROCESS  ( buf desc -- )
```

Applies distortion to every sample in the buffer, in-place.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `FX-DELAY-CREATE` | `( ms rate -- desc )` | Create delay |
| `FX-DELAY-FREE` | `( desc -- )` | Free delay |
| `FX-DELAY!` | `( ms desc -- )` | Change delay time |
| `FX-DELAY-FB!` | `( fb desc -- )` | Set feedback |
| `FX-DELAY-WET!` | `( wet desc -- )` | Set wet/dry mix |
| `FX-DELAY-PROCESS` | `( buf desc -- )` | Apply delay |
| `FX-DIST-CREATE` | `( drive mode -- desc )` | Create distortion |
| `FX-DIST-FREE` | `( desc -- )` | Free distortion |
| `FX-DIST-DRIVE!` | `( drive desc -- )` | Set drive |
| `FX-DIST-PROCESS` | `( buf desc -- )` | Apply distortion |

---

## Cookbook

### Simple Echo

```forth
\ 100 ms echo at 44100 Hz, light feedback
100 44100 FX-DELAY-CREATE  CONSTANT mydelay
0x3400 mydelay FX-DELAY-WET!     \ wet = 0.25 (subtle echo)
0x3000 mydelay FX-DELAY-FB!      \ feedback = 0.125 (decays quickly)
mybuf mydelay FX-DELAY-PROCESS
```

### Guitar-Style Overdrive

```forth
\ Soft clip with moderate drive
0x4200 0 FX-DIST-CREATE  CONSTANT mydist   \ drive = 3.0, soft clip
mybuf mydist FX-DIST-PROCESS
```

### Lo-Fi Bitcrush

```forth
\ Crunchy 4-bit reduction + sample-rate reduction
0x4400 2 FX-DIST-CREATE  CONSTANT mycrush  \ drive = 4.0, bitcrush
mybuf mycrush FX-DIST-PROCESS
```

### Chain: Distortion → Delay

```forth
0x4000 0 FX-DIST-CREATE  CONSTANT mydist
50 44100 FX-DELAY-CREATE  CONSTANT mydelay

2 CHAIN-CREATE  CONSTANT mychain
['] FX-DIST-PROCESS  mydist  0 mychain CHAIN-SET!
['] FX-DELAY-PROCESS mydelay 1 mychain CHAIN-SET!

mybuf mychain CHAIN-PROCESS

\ Cleanup
mydist FX-DIST-FREE
mydelay FX-DELAY-FREE
mychain CHAIN-FREE
```
