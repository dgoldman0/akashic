# akashic-audio-synth — Subtractive Synthesizer for KDOS / Megapad-64

Dual-oscillator subtractive synthesizer with a resonant biquad filter
and ADSR envelope control.  Signal path:

```
OSC1 ──┐
       ├─→ Biquad Filter ─→ Amp Envelope ─→ Output
OSC2 ──┘
```

The filter uses second-order RBJ cookbook coefficients in Direct Form II
Transposed (DFII-T) topology for low-pass, high-pass, or band-pass modes.
A dedicated filter envelope modulates the cutoff frequency per render block.

```forth
REQUIRE audio/synth.f
```

`PROVIDED akashic-audio-synth` — safe to include multiple times.
Depends on `akashic-fp16-ext`, `akashic-fp32`, `akashic-math-trig`,
`akashic-audio-pcm`, `akashic-audio-osc`, `akashic-audio-env`.

---

## Table of Contents

- [Descriptor Layout](#descriptor-layout)
- [Filter Types](#filter-types)
- [Filter Envelope](#filter-envelope)
- [API](#api)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Descriptor Layout

Synth voice descriptor (72 bytes):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | osc1 | ptr | Primary oscillator descriptor |
| +8 | osc2 | ptr | Secondary oscillator (or 0 if single-osc) |
| +16 | filt-type | int | Filter type: 0=LP, 1=HP, 2=BP |
| +24 | filt-cutoff | FP16 | Base cutoff frequency (Hz) |
| +32 | filt-reso | FP16 | Resonance / Q factor |
| +40 | amp-env | ptr | Amplitude ADSR envelope |
| +48 | filt-env | ptr | Filter modulation ADSR envelope |
| +56 | work-buf | ptr | Output PCM buffer (mono) |
| +64 | detune | FP16 | OSC2 detune in cents (default 0.0) |

---

## Filter Types

| Constant | Value | Description |
|----------|-------|-------------|
| `SYNTH-FILT-LP` | 0 | Low-pass: attenuates frequencies above cutoff |
| `SYNTH-FILT-HP` | 1 | High-pass: attenuates frequencies below cutoff |
| `SYNTH-FILT-BP` | 2 | Band-pass: passes a band around cutoff |

### Filter Math (RBJ Biquad)

For a given cutoff $f_c$, Q, and sample rate $f_s$:

$$
\omega_0 = \frac{2\pi f_c}{f_s}, \quad
\alpha = \frac{\sin\omega_0}{2Q}
$$

**Low-pass coefficients:**

$$
b_0 = \frac{1 - \cos\omega_0}{2}, \quad
b_1 = 1 - \cos\omega_0, \quad
b_2 = b_0
$$

$$
a_0 = 1 + \alpha, \quad a_1 = -2\cos\omega_0, \quad a_2 = 1 - \alpha
$$

All coefficients are normalized by $a_0$.

The cutoff/rate ratio is formed in FP32 before narrowing the angular
frequency for trigonometry.  This avoids saturating integer rates such as
96 kHz through FP16 and avoids first forming an overflowing `2π × cutoff`.

The cutoff is clamped to $[20,\; f_s/2 - 1]$ to prevent division
by zero when $\omega_0 = 2\pi$.

---

## Filter Envelope

The filter envelope modulates cutoff each render block:

$$
f_c' = f_c \times (1 + \text{env\_level} \times 3)
$$

This gives a range of 1× to 4× the base cutoff at full envelope level.
The filter envelope has its own ADSR parameters (A=20ms, D=200ms,
S=0.3, R=300ms by default).

---

## API

### SYNTH-CREATE

```forth
SYNTH-CREATE  ( shape1 shape2 rate frames -- voice )
```

Allocate a synth voice with one or two oscillators of the given waveform
shapes at **rate** Hz, rendering **frames** per block.

- **shape1**: Primary oscillator waveform (0=sine, 1=saw, etc.)
- **shape2**: Secondary oscillator waveform, or `-1` for a single oscillator
- Defaults: LP filter, cutoff=1000 Hz, Q=0.707, detune=0 cents
- Amp envelope: A=10ms, D=100ms, S=0.7, R=200ms
- Filter envelope: A=20ms, D=200ms, S=0.3, R=300ms

Shapes, rate, and frame count are validated before allocation.  Construction
is transactional: if any oscillator, envelope, or PCM allocation returns an
error, all subobjects created so far are released before the allocator `ior`
is rethrown.
The rate must be at least 42 Hz, keeping the filter's `[20, rate/2-1]` range
nonempty.  Fixed envelope-duration and work-buffer products are also checked
for cell overflow during this preflight.

Contract violations use `ABORT"` before any allocation.  Allocation failures
use catchable `THROW`, including in the child constructors, which is what makes
partial-graph cleanup effective under KDOS's exception semantics.

### SYNTH-FREE

```forth
SYNTH-FREE  ( voice -- )
```

Free both oscillators, both envelopes, the work buffer, and the
descriptor.  Passing `0` is a no-op.

### SYNTH-NOTE-ON

```forth
SYNTH-NOTE-ON  ( freq vel voice -- )
```

Trigger a note.  Sets oscillator 1 to **freq** (FP16, Hz).  When oscillator 2
exists, its frequency uses the current linear cents approximation
`freq × (1 + cents/1200)`.  Both envelopes are gated on.

**vel** is currently reserved and discarded; it does not scale the amplitude.
It must nevertheless be a finite FP16 value from 0.0 through 1.0. Frequency
and the detuned second-oscillator frequency are both validated before either
oscillator is mutated, so a rejected note cannot leave a half-updated voice.

### SYNTH-NOTE-OFF

```forth
SYNTH-NOTE-OFF  ( voice -- )
```

Release both ADSR envelopes (enter release phase).

### SYNTH-RENDER

```forth
SYNTH-RENDER  ( voice -- buf )
```

Render one block.  For each frame:
1. Sum OSC1 + OSC2 samples
2. Apply biquad filter (DFII-T), which clamps its output to `[−1, +1]`
3. Multiply by amp envelope tick
4. Store to output buffer

The dual-oscillator sum is not halved before filtering; callers choosing two
full-scale oscillators should account for that gain structure.

Filter history is module-global rather than stored in each voice.  Callers
that interleave multiple voices must bracket each voice with
`SYNTH-SAVE-FILT ( -- s1 s2 )` and `SYNTH-LOAD-FILT ( s1 s2 -- )`, maintaining
one saved `(s1,s2)` pair per voice.

Returns the PCM buffer pointer.

### SYNTH-CUTOFF!

```forth
SYNTH-CUTOFF!  ( freq voice -- )
```

Set the base filter cutoff frequency (FP16, Hz).
The value must be finite and positive; rendering clamps the envelope-modulated
effective cutoff to the filter's stable range.

### SYNTH-RESO!

```forth
SYNTH-RESO!  ( q voice -- )
```

Set filter resonance / Q factor (FP16).  Higher Q = sharper peak.
The supported finite range is 0.1 through 32.

### SYNTH-DETUNE!

```forth
SYNTH-DETUNE!  ( cents voice -- )
```

Set OSC2 detune in FP16 cents.  `0.0` is unison; small values such as `7.0`
produce a chorus-like offset.  The current note-on calculation is the linear
approximation `1 + cents/1200`, not an exact `2^(cents/1200)` conversion.
The supported finite range is -1200 through +1200 cents.

### SYNTH-FILT-TYPE!

```forth
SYNTH-FILT-TYPE!  ( type voice -- )
SYNTH-SAVE-FILT   ( -- s1 s2 )
SYNTH-LOAD-FILT   ( s1 s2 -- )
```

Switch filter type: `SYNTH-FILT-LP`, `SYNTH-FILT-HP`, or `SYNTH-FILT-BP`.
Other integer values are rejected before changing the voice.

---

## Quick Reference

```
SYNTH-CREATE      ( shape1 shape2 rate frames -- voice )
SYNTH-FREE        ( voice -- )
SYNTH-NOTE-ON     ( freq vel voice -- )
SYNTH-NOTE-OFF    ( voice -- )
SYNTH-RENDER      ( voice -- buf )
SYNTH-CUTOFF!     ( freq voice -- )
SYNTH-RESO!       ( q voice -- )
SYNTH-DETUNE!     ( cents voice -- )
SYNTH-FILT-TYPE!  ( type voice -- )
SYNTH-FILT-LP     ( -- 0 )
SYNTH-FILT-HP     ( -- 1 )
SYNTH-FILT-BP     ( -- 2 )
```

---

## Cookbook

### Basic Saw Bass

```forth
1 -1 44100 256 SYNTH-CREATE  CONSTANT mybass
200 INT>FP16  mybass SYNTH-CUTOFF!    \ low-pass at 200 Hz
220 INT>FP16 0x3C00 mybass SYNTH-NOTE-ON
mybass SYNTH-RENDER  ( → buf )
mybass SYNTH-NOTE-OFF
mybass SYNTH-RENDER DROP              \ release tail
mybass SYNTH-FREE
```

### Detuned Pad

```forth
0 0 44100 256 SYNTH-CREATE  CONSTANT mypad
\ Slight detune for chorus effect
7 INT>FP16 mypad SYNTH-DETUNE!       \ 7 cents
440 INT>FP16 0x3C00 mypad SYNTH-NOTE-ON
mypad SYNTH-RENDER  ( → buf )
mypad SYNTH-FREE
```

### Resonant Sweep

```forth
1 1 44100 256 SYNTH-CREATE  CONSTANT mysynth
\ High resonance for acid-style filter
0x4200 mysynth SYNTH-RESO!           \ Q ≈ 3.0
500 INT>FP16 mysynth SYNTH-CUTOFF!
330 INT>FP16 0x3C00 mysynth SYNTH-NOTE-ON
\ The filter envelope will sweep cutoff upward
mysynth SYNTH-RENDER DROP
mysynth SYNTH-RENDER DROP
mysynth SYNTH-FREE
```

### High-Pass Mode

```forth
0 -1 44100 256 SYNTH-CREATE  CONSTANT mysynth
SYNTH-FILT-HP mysynth SYNTH-FILT-TYPE!
500 INT>FP16 mysynth SYNTH-CUTOFF!
440 INT>FP16 0x3C00 mysynth SYNTH-NOTE-ON
mysynth SYNTH-RENDER  ( → buf, low freqs removed )
mysynth SYNTH-FREE
```
