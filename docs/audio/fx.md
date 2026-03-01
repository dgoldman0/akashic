# akashic-audio-fx — Audio Effects Collection for KDOS / Megapad-64

Audio effects that transform PCM buffers in-place.  Each effect has a
`CREATE` word (heap descriptor), a `PROCESS` word with the signature
`( buf desc -- )`, and a `FREE` word.  All effects plug directly into
`chain.f` slots.

**Effects:**
- **FX-DELAY** — Delay / Echo (circular delay line with feedback)
- **FX-DIST** — Distortion / Bitcrusher (soft clip, hard clip, bitcrush)
- **FX-REVERB** — Schroeder reverb (4 comb filters + 2 allpass filters)
- **FX-CHORUS** — LFO-modulated delay chorus
- **FX-EQ** — Parametric EQ (up to 4 IIR biquad bands)

```forth
REQUIRE audio/fx.f
```

`PROVIDED akashic-audio-fx` — safe to include multiple times.
Depends on `akashic-audio-pcm`, `akashic-audio-lfo`, `akashic-math-trig`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Internal: Circular Delay Line](#internal-circular-delay-line)
- [FX-DELAY — Delay / Echo](#fx-delay--delay--echo)
- [FX-DIST — Distortion / Bitcrusher](#fx-dist--distortion--bitcrusher)
- [FX-REVERB — Schroeder Reverb](#fx-reverb--schroeder-reverb)
- [FX-CHORUS — LFO-Modulated Delay](#fx-chorus--lfo-modulated-delay)
- [FX-EQ — Parametric Equalizer](#fx-eq--parametric-equalizer)
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

## FX-REVERB — Schroeder Reverb

Classic Schroeder topology: four parallel comb filters summed and
passed through two series allpass filters.  Each comb has a one-pole
low-pass filter in its feedback path for damping control.

### Architecture

```
                ┌── comb 0 (1116) ──┐
                ├── comb 1 (1188) ──┤
input ──────────┤                    ├─► sum ──► AP 0 (556) ──► AP 1 (441) ──┐
                ├── comb 2 (1277) ──┤                                         ├─► mix ──► output
                └── comb 3 (1356) ──┘                                         │
input ────────────────────────────────────────────────────────────────────────┘
                                                             (dry path, controlled by wet)
```

Delay times shown are Freeverb classic values at 44100 Hz.  They are
automatically scaled to the actual sample rate at creation time.

**Comb filter feedback loop:**

$$\text{filtered} = (1 - \text{damp}) \times \text{delayed} + \text{damp} \times \text{prev\_filtered}$$
$$\text{write} = \text{input} + \text{room} \times \text{filtered}$$

**Allpass filter** (Freeverb style, gain = 0.5):

$$\text{output} = \text{bufout} - \text{input}$$
$$\text{write} = \text{input} + 0.5 \times \text{bufout}$$

### Memory Layout (13 cells = 104 bytes)

```
Offset  Size  Field
──────  ────  ──────────
+0      8     comb DL 0      — pointer to comb 0 delay line
+8      8     comb DL 1      — pointer to comb 1 delay line
+16     8     comb DL 2      — pointer to comb 2 delay line
+24     8     comb DL 3      — pointer to comb 3 delay line
+32     8     allpass DL 0   — pointer to allpass 0 delay line
+40     8     allpass DL 1   — pointer to allpass 1 delay line
+48     8     filt state 0   — one-pole LP state, comb 0 (FP16)
+56     8     filt state 1   — one-pole LP state, comb 1 (FP16)
+64     8     filt state 2   — one-pole LP state, comb 2 (FP16)
+72     8     filt state 3   — one-pole LP state, comb 3 (FP16)
+80     8     room           — feedback amount 0.0–1.0 (FP16)
+88     8     damp           — LP damping 0.0–1.0 (FP16)
+96     8     wet            — wet/dry mix 0.0–1.0 (FP16)
```

**Memory usage:** ~13.4 KiB at 44100 Hz, ~1.3 KiB at 1000 Hz.

### API

#### FX-REVERB-CREATE

```forth
FX-REVERB-CREATE  ( room damp wet rate -- desc )
```

Creates a Schroeder reverb.  Parameters:
- `room` — FP16, 0.0–1.0.  Higher = longer reverb tail.
- `damp` — FP16, 0.0–1.0.  0 = bright, 1 = dark (more HF attenuation).
- `wet` — FP16, 0.0–1.0.  0 = fully dry, 1 = fully wet.
- `rate` — integer sample rate.

#### FX-REVERB-FREE

```forth
FX-REVERB-FREE  ( desc -- )
```

Frees all 6 delay lines and the descriptor.

#### FX-REVERB-ROOM! / FX-REVERB-DAMP!

```forth
FX-REVERB-ROOM!  ( room desc -- )
FX-REVERB-DAMP!  ( damp desc -- )
```

Adjust parameters in real time.

#### FX-REVERB-PROCESS

```forth
FX-REVERB-PROCESS  ( buf desc -- )
```

Applies reverb to every sample in the buffer, in-place.

---

## FX-CHORUS — LFO-Modulated Delay

A short delay line whose read position is swept by an internal LFO.
Linear interpolation between adjacent delay samples for sub-sample
precision.  Produces the classic chorus thickening effect.

### Algorithm

For each sample:

1. Write input into delay line
2. `LFO-TICK` → FP16 tap offset (center ± depth)
3. Split tap into integer + fractional parts
4. Read two adjacent delay taps, linearly interpolate
5. Output = `LERP(dry, delayed, mix)`

The center delay is fixed at 25 ms.  The LFO modulates the tap
position by ±`depth` samples around this center.

### Memory Layout (4 cells = 32 bytes)

```
Offset  Size  Field
──────  ────  ──────────
+0      8     dl      — pointer to delay line
+8      8     lfo     — pointer to LFO descriptor (sine wave)
+16     8     mix     — wet/dry mix 0.0–1.0 (FP16)
+24     8     center  — center delay in samples (integer)
```

### API

#### FX-CHORUS-CREATE

```forth
FX-CHORUS-CREATE  ( depth-ms rate-hz mix rate -- desc )
```

Creates a chorus effect.  Parameters:
- `depth-ms` — integer, LFO modulation depth in milliseconds (typ. 2–10).
- `rate-hz` — FP16, LFO frequency in Hz (typ. 0.3–3.0 Hz).
- `mix` — FP16, wet/dry mix 0.0–1.0.
- `rate` — integer sample rate.

#### FX-CHORUS-FREE

```forth
FX-CHORUS-FREE  ( desc -- )
```

Frees the delay line, LFO, and descriptor.

#### FX-CHORUS-PROCESS

```forth
FX-CHORUS-PROCESS  ( buf desc -- )
```

Applies chorus to every sample in the buffer, in-place.

---

## FX-EQ — Parametric Equalizer

Up to 4 bands of IIR biquad filtering using Direct Form II Transposed.
Each band has persistent state (s1, s2) that carries across buffer
calls, allowing continuous streaming.

### Band Type Auto-Selection

`FX-EQ-BAND!` auto-selects the biquad type based on frequency:

| Condition | Filter Type |
|---|---|
| `freq < 200 Hz` | Low shelf |
| `freq > rate/4` | High shelf |
| Otherwise | Peaking EQ |

Coefficients are computed using the Audio EQ Cookbook (Robert
Bristow-Johnson) formulas with an FP16-friendly linear approximation
for the amplitude parameter $A$.

### Memory Layout

**Descriptor (3 cells = 24 bytes):**

```
Offset  Size  Field
──────  ────  ──────────
+0      8     nbands  — number of bands (1–4)
+8      8     rate    — sample rate (integer)
+16     8     bands   — pointer to band array
```

**Per-band (7 cells = 56 bytes):**

```
Offset  Size  Field
──────  ────  ──────────
+0      8     b0   — biquad coefficient (FP16)
+8      8     b1   — biquad coefficient (FP16)
+16     8     b2   — biquad coefficient (FP16)
+24     8     a1   — biquad coefficient (FP16)
+32     8     a2   — biquad coefficient (FP16)
+40     8     s1   — delay state register 1 (FP16)
+48     8     s2   — delay state register 2 (FP16)
```

### API

#### FX-EQ-CREATE

```forth
FX-EQ-CREATE  ( nbands rate -- desc )
```

Creates a parametric EQ with 1–4 bands (clamped).  All bands default
to unity pass-through (b0 = 1.0, others = 0).

#### FX-EQ-FREE

```forth
FX-EQ-FREE  ( desc -- )
```

Frees the band array and descriptor.

#### FX-EQ-BAND!

```forth
FX-EQ-BAND!  ( freq gain-db Q band# desc -- )
```

Configures a single band.  Parameters:
- `freq` — integer Hz, center/corner frequency.
- `gain-db` — FP16, boost/cut in dB (positive = boost, negative = cut).
- `Q` — FP16, quality factor (typ. 0.707 for Butterworth, 0.1–10.0).
- `band#` — integer, 0-based band index.

Recomputes all 5 biquad coefficients and zeros the state registers.

#### FX-EQ-PROCESS

```forth
FX-EQ-PROCESS  ( buf desc -- )
```

Applies all configured bands in cascade (band 0 → 1 → 2 → 3) to
every sample in the buffer, in-place.  Band state persists between
calls for continuous streaming.

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
| `FX-REVERB-CREATE` | `( room damp wet rate -- desc )` | Create Schroeder reverb |
| `FX-REVERB-FREE` | `( desc -- )` | Free reverb + 6 delay lines |
| `FX-REVERB-ROOM!` | `( room desc -- )` | Set room size |
| `FX-REVERB-DAMP!` | `( damp desc -- )` | Set damping |
| `FX-REVERB-PROCESS` | `( buf desc -- )` | Apply reverb |
| `FX-CHORUS-CREATE` | `( depth-ms rate-hz mix rate -- desc )` | Create chorus |
| `FX-CHORUS-FREE` | `( desc -- )` | Free chorus + DL + LFO |
| `FX-CHORUS-PROCESS` | `( buf desc -- )` | Apply chorus |
| `FX-EQ-CREATE` | `( nbands rate -- desc )` | Create parametric EQ |
| `FX-EQ-FREE` | `( desc -- )` | Free EQ |
| `FX-EQ-BAND!` | `( freq gain-db Q band# desc -- )` | Configure band |
| `FX-EQ-PROCESS` | `( buf desc -- )` | Apply EQ |

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

### Room Reverb

```forth
\ Medium room: room=0.7, damp=0.3, wet=0.4
0x399A 0x34CD 0x3666 44100 FX-REVERB-CREATE  CONSTANT myverb
mybuf myverb FX-REVERB-PROCESS
myverb FX-REVERB-FREE
```

### Thick Chorus

```forth
\ 5ms depth, 1.5Hz rate, 50% mix
5 0x3E00 0x3800 44100 FX-CHORUS-CREATE  CONSTANT mychorus
mybuf mychorus FX-CHORUS-PROCESS
mychorus FX-CHORUS-FREE
```

### 3-Band Parametric EQ

```forth
\ Low shelf boost, mid cut, high shelf boost
3 44100 FX-EQ-CREATE  CONSTANT myeq
100  0x4200 0x3C00 0 myeq FX-EQ-BAND!    \ +3dB low shelf (100Hz)
1000 0xC200 0x3C00 1 myeq FX-EQ-BAND!    \ -3dB peaking (1kHz)
8000 0x4200 0x3C00 2 myeq FX-EQ-BAND!    \ +3dB high shelf (8kHz)
mybuf myeq FX-EQ-PROCESS
myeq FX-EQ-FREE
```

### Full Effects Chain: EQ → Chorus → Reverb

```forth
1 44100 FX-EQ-CREATE  CONSTANT myeq
500 0x4200 0x3C00 0 myeq FX-EQ-BAND!

5 0x3C00 0x3800 44100 FX-CHORUS-CREATE  CONSTANT mychorus
0x3800 0x3400 0x3800 44100 FX-REVERB-CREATE  CONSTANT myverb

3 CHAIN-CREATE  CONSTANT mychain
['] FX-EQ-PROCESS      myeq     0 mychain CHAIN-SET!
['] FX-CHORUS-PROCESS  mychorus 1 mychain CHAIN-SET!
['] FX-REVERB-PROCESS  myverb   2 mychain CHAIN-SET!

mybuf mychain CHAIN-PROCESS

myeq FX-EQ-FREE
mychorus FX-CHORUS-FREE
myverb FX-REVERB-FREE
mychain CHAIN-FREE
```
