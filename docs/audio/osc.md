# akashic-audio-osc — Band-Limited Oscillators for KDOS / Megapad-64

Five anti-alias-free waveform generators: sine, square, saw, triangle,
and pulse.  All arithmetic is FP16.  Output fills a `pcm.f` buffer
one frame at a time.

```forth
REQUIRE audio/osc.f
```

`PROVIDED akashic-audio-osc` — safe to include multiple times.
Depends on `akashic-audio-pcm`, `akashic-fp16`, `akashic-fp16-ext`,
`akashic-trig`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Accessors & Setters](#accessors--setters)
- [Single-Sample Generation](#single-sample-generation)
- [Bulk Generation](#bulk-generation)
- [Waveform Reference](#waveform-reference)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **FP16 phase accumulator** | Phase is a FP16 value in `[0.0, 1.0)`.  Advances by `freq / rate` each sample. |
| **Shape dispatch** | `CASE/OF/ENDOF/ENDCASE` switches on shape constant. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant across words. |
| **Prefix convention** | Public: `OSC-`.  Internal: `_OSC-`.  Field: `O.xxx`. |
| **PCM integration** | `OSC-FILL` and `OSC-ADD` write directly into PCM buffer frames via `PCM-FRAME!`. |

---

## Memory Layout

An oscillator descriptor occupies 6 cells = 48 bytes:

```
Offset  Size  Field
──────  ────  ──────────────
+0      8     freq    — frequency in Hz (FP16)
+8      8     phase   — current phase [0.0, 1.0) (FP16)
+16     8     rate    — sample rate in Hz (integer)
+24     8     shape   — waveform index (0–4)
+32     8     duty    — duty cycle for pulse/square (FP16, default 0.5)
+40     8     table   — (reserved) wavetable pointer
```

---

## Creation & Destruction

### OSC-CREATE

```forth
OSC-CREATE  ( freq shape rate -- osc )
```

Allocate and initialise an oscillator.

- **freq** — frequency as FP16 (e.g. `440 INT>FP16`)
- **shape** — one of `OSC-SINE`, `OSC-SQUARE`, `OSC-SAW`, `OSC-TRI`, `OSC-PULSE`
- **rate** — sample rate in Hz (integer, e.g. `44100`)

Phase starts at 0.0, duty at 0.5.

```forth
440 INT>FP16 OSC-SINE 44100 OSC-CREATE CONSTANT my-sine
```

### OSC-FREE

```forth
OSC-FREE  ( osc -- )
```

Release the descriptor back to the heap.

---

## Accessors & Setters

### Read-Only Field Access

```forth
OSC-FREQ   ( osc -- freq )    \ current freq (FP16)
OSC-PHASE  ( osc -- phase )   \ current phase (FP16)
OSC-RATE   ( osc -- rate )    \ sample rate (integer)
OSC-SHAPE  ( osc -- shape )   \ waveform index (0–4)
OSC-DUTY   ( osc -- duty )    \ duty cycle (FP16)
```

### Setters

```forth
OSC-FREQ!  ( freq osc -- )    \ set frequency (FP16)
OSC-DUTY!  ( duty osc -- )    \ set duty cycle (FP16)
OSC-RESET  ( osc -- )         \ reset phase to 0.0
```

---

## Single-Sample Generation

### OSC-SAMPLE

```forth
OSC-SAMPLE  ( osc -- value )
```

Generate one FP16 sample at the current phase, then advance the
phase accumulator by `freq / rate`.  Output is in `[−1.0, +1.0]`.

```forth
my-sine OSC-SAMPLE .        \ prints FP16 bit pattern
```

**Phase advance formula:**

```
phase' = phase + freq / rate
if phase' ≥ 1.0 then phase' -= 1.0
```

---

## Bulk Generation

### OSC-FILL

```forth
OSC-FILL  ( buf osc -- )
```

Fill every frame of the PCM buffer with consecutive oscillator
samples.  Uses `PCM-LEN` for the frame count and `PCM-FRAME!` for
writes.  The oscillator phase advances through the buffer.

```forth
4096 44100 16 1 PCM-ALLOC CONSTANT wav
wav my-sine OSC-FILL
```

### OSC-ADD

```forth
OSC-ADD  ( buf osc -- )
```

Same as `OSC-FILL` but *adds* each oscillator sample to the
existing buffer content (`PCM-FRAME@ + FP16-ADD`).  Use for
additive synthesis.

```forth
wav osc-fundamental OSC-FILL     \ base tone
wav osc-harmonic2   OSC-ADD      \ add 2nd harmonic
wav osc-harmonic3   OSC-ADD      \ add 3rd harmonic
```

---

## Waveform Reference

### Shape Constants

| Constant      | Value | Description |
|---------------|-------|-------------|
| `OSC-SINE`    | 0     | Smooth sinusoid via `TRIG-SIN` |
| `OSC-SQUARE`  | 1     | Bipolar square (±1.0), threshold at `duty` |
| `OSC-SAW`     | 2     | Rising sawtooth: `2 × phase − 1` |
| `OSC-TRI`     | 3     | Triangle: `4 × |phase − 0.5| − 1` |
| `OSC-PULSE`   | 4     | Unipolar pulse: `+1.0` while `phase < duty`, else `−1.0` |

### Output Ranges

All waveforms output FP16 values in `[−1.0, +1.0]`.

| Waveform | phase = 0 | phase = 0.25 | phase = 0.5 | phase = 0.75 |
|----------|-----------|-------------|-------------|-------------|
| Sine     | 0.0       | +1.0        | 0.0         | −1.0        |
| Square   | +1.0      | +1.0        | −1.0        | −1.0        |
| Saw      | −1.0      | −0.5        | 0.0         | +0.5        |
| Triangle | +1.0      | 0.0         | −1.0        | 0.0         |
| Pulse    | +1.0      | +1.0        | −1.0        | −1.0        |

*(Square and Pulse with default duty 0.5 are identical.)*

---

## Quick Reference

```
OSC-CREATE  ( freq shape rate -- osc )      create oscillator
OSC-FREE    ( osc -- )                      free descriptor
OSC-SAMPLE  ( osc -- value )                one FP16 sample
OSC-FILL    ( buf osc -- )                  fill PCM buffer
OSC-ADD     ( buf osc -- )                  add to PCM buffer
OSC-RESET   ( osc -- )                      reset phase to 0
OSC-FREQ!   ( freq osc -- )                 set freq (FP16)
OSC-DUTY!   ( duty osc -- )                 set duty (FP16)
OSC-FREQ    ( osc -- freq )                 read freq
OSC-PHASE   ( osc -- phase )                read phase
OSC-RATE    ( osc -- rate )                 read rate
OSC-SHAPE   ( osc -- shape )                read shape
OSC-DUTY    ( osc -- duty )                 read duty
```

---

## Cookbook

### Simple 440 Hz Sine Tone (1 second)

```forth
440 INT>FP16 OSC-SINE 44100 OSC-CREATE CONSTANT tone
44100 44100 16 1 PCM-ALLOC CONSTANT buf
buf tone OSC-FILL
\ buf now holds 1 second of 440 Hz sine
tone OSC-FREE
```

### Two-Oscillator Additive Mix

```forth
440 INT>FP16 OSC-SINE   44100 OSC-CREATE CONSTANT fund
880 INT>FP16 OSC-SINE   44100 OSC-CREATE CONSTANT harm2
4096 44100 16 1 PCM-ALLOC CONSTANT mix
mix fund  OSC-FILL      \ fundamental A4
mix harm2 OSC-ADD       \ add octave
```

### Changing Frequency on the Fly

```forth
440 INT>FP16 OSC-SINE 44100 OSC-CREATE CONSTANT osc
\ ... generate some samples ...
880 INT>FP16 osc OSC-FREQ!     \ shift to 880 Hz
\ phase continues from where it was — no click
```

### Pulse Width Modulation

```forth
200 INT>FP16 OSC-PULSE 44100 OSC-CREATE CONSTANT pw
FP16-POS-HALF pw OSC-DUTY!     \ 50% → square wave
\ Change duty over time for PWM sweep:
\   0x2E66 pw OSC-DUTY!        \ narrow 25% duty
```
