# akashic-audio-env — ADSR Envelope Generators for KDOS / Megapad-64

Linear ADSR envelopes that produce a time-varying FP16 gain curve
in `[0.0, 1.0]`.  Timing specified in milliseconds, converted to
frame counts internally.  Use for amplitude shaping, filter cutoff,
pitch bend, or any parameter that evolves over time.

```forth
REQUIRE audio/env.f
```

`PROVIDED akashic-audio-env` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-audio-pcm-simd`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Phase State Machine](#phase-state-machine)
- [Creation & Destruction](#creation--destruction)
- [Gate Control](#gate-control)
- [Per-Frame Tick](#per-frame-tick)
- [Introspection](#introspection)
- [Bulk Operations](#bulk-operations)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Millisecond timing** | Attack, decay, and release durations in ms; converted to frames at creation via `ms × rate / 1000`. |
| **FP16 levels** | Sustain level and all intermediate values are FP16. |
| **Linear segments** | Attack ramps 0→1, decay ramps 1→sustain, release ramps sustain→0.  Exponential curves reserved for future. |
| **Gate-driven** | `ENV-GATE-ON` starts attack; `ENV-GATE-OFF` starts release from the current level. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `ENV-`.  Internal: `_ENV-`.  Field: `E.xxx`. |

---

## Memory Layout

An envelope descriptor occupies 12 cells = 96 bytes:

```
Offset  Size  Field
──────  ────  ──────────────────
+0      8     attack    — attack time in frames
+8      8     decay     — decay time in frames
+16     8     sustain   — sustain level (FP16, 0.0–1.0)
+24     8     release   — release time in frames
+32     8     phase     — current phase (0–5, see below)
+40     8     position  — frame counter within current phase
+48     8     level     — current output level (FP16)
+56     8     curve     — 0=linear, 1=exponential (reserved)
+64     8     mode      — 0=one-shot, 1=loop, 2=AR
+72     8     rate      — sample rate in Hz (integer)
+80     8     rel-level — level at moment of gate-off (FP16)
+88     8     (reserved)
```

---

## Phase State Machine

```
           GATE-ON              pos ≥ attack            pos ≥ decay
  IDLE ──────────► ATTACK ──────────────► DECAY ──────────────► SUSTAIN
   ▲                  │                     │                      │
   │                  │       GATE-OFF      │       GATE-OFF       │  GATE-OFF
   │                  └────────────┬────────┘──────────────────────┘
   │                               ▼
   │                            RELEASE ──────► DONE
   │                                              │
   └──────── ENV-RESET ◄─────────────────────────┘
```

| Phase Constant | Value | Behaviour |
|----------------|-------|-----------|
| `ENV-IDLE`     | 0     | Output = 0.0.  Waiting for gate. |
| `ENV-ATTACK`   | 1     | Linear ramp from 0.0 to 1.0 over `attack` frames. |
| `ENV-DECAY`    | 2     | Linear ramp from 1.0 to `sustain` over `decay` frames. |
| `ENV-SUSTAIN`  | 3     | Hold at `sustain` level indefinitely. |
| `ENV-RELEASE`  | 4     | Linear ramp from current level to 0.0 over `release` frames. |
| `ENV-DONE`     | 5     | Output = 0.0.  Envelope complete. |

---

## Creation & Destruction

### ENV-CREATE

```forth
ENV-CREATE  ( a d s r rate -- env )
```

Create an ADSR envelope.

- **a** — attack time in milliseconds (integer)
- **d** — decay time in milliseconds (integer)
- **s** — sustain level as FP16 (e.g. `FP16-POS-HALF` for 0.5)
- **r** — release time in milliseconds (integer)
- **rate** — sample rate in Hz (integer)

All durations are converted to frames (minimum 1 frame).

```forth
50 100 FP16-POS-HALF 200 44100 ENV-CREATE CONSTANT my-env
\ 50 ms attack, 100 ms decay, 0.5 sustain, 200 ms release
```

### ENV-CREATE-AR

```forth
ENV-CREATE-AR  ( a r rate -- env )
```

Shorthand for attack–release envelope (no decay/sustain).
Sets mode to AR (2).  After attack completes, jumps directly
to release.

```forth
10 50 44100 ENV-CREATE-AR CONSTANT click-env
```

### ENV-FREE

```forth
ENV-FREE  ( env -- )
```

Release the descriptor back to the heap.

---

## Gate Control

### ENV-GATE-ON

```forth
ENV-GATE-ON  ( env -- )
```

Trigger the attack phase.  Sets phase = ATTACK, position = 0.
Can be called at any time (retrigger from current state).

### ENV-GATE-OFF

```forth
ENV-GATE-OFF  ( env -- )
```

Trigger the release phase.  Saves the current level as the
release start point, then starts ramping toward 0.

### ENV-RETRIGGER

```forth
ENV-RETRIGGER  ( env -- )
```

Alias for `ENV-GATE-ON`.  Useful for fast retrigger effects.

### ENV-RESET

```forth
ENV-RESET  ( env -- )
```

Return to idle.  Sets phase = IDLE, level = 0.0, position = 0.

---

## Per-Frame Tick

### ENV-TICK

```forth
ENV-TICK  ( env -- level )
```

Advance the envelope by one frame and return the current FP16 level.
Internally:

1. Read current phase.
2. Compute level for this frame (linear interpolation).
3. Advance position counter.
4. Check for phase transitions (attack→decay, decay→sustain, etc.).
5. Store the new level in the descriptor.
6. Return level on the stack.

Call once per audio frame.  The level is also stored in `E.LEVEL`
for later introspection via `ENV-LEVEL`.

---

## Introspection

### ENV-LEVEL

```forth
ENV-LEVEL  ( env -- level )
```

Return the most recently computed FP16 level without advancing
the envelope.  Reads `E.LEVEL @`.

### ENV-DONE?

```forth
ENV-DONE?  ( env -- flag )
```

True (−1) if the envelope has completed its release phase.
False (0) otherwise.

---

## Bulk Operations

### ENV-FILL

```forth
ENV-FILL  ( buf env -- )
```

Fill a PCM buffer with the envelope curve.  Calls `ENV-TICK` once
per frame and writes each level via direct `W!` (bypasses
`PCM-FRAME!` for faster writes).  Useful for pre-rendering an
envelope curve into a buffer.

### ENV-APPLY

```forth
ENV-APPLY  ( buf env -- )
```

Multiply each sample in the PCM buffer by the envelope level.

**SIMD fast paths:**

- **Sustain phase** — the envelope level is constant for the entire
  buffer.  Uses `PCM-SIMD-SCALE` to multiply all samples at once
  (~70× faster than per-sample).
- **Done phase** — the envelope has completed.  Uses
  `PCM-SIMD-CLEAR` to zero all samples in one pass.

**Per-sample path** (attack, decay, release phases): reads each
sample via `W@`, multiplies by `ENV-TICK`, and writes back via
`W!` (direct pointer access, no `PCM-FRAME@`/`PCM-FRAME!`).

```forth
buf my-sine OSC-FILL          \ fill with sine
my-env ENV-GATE-ON
buf my-env ENV-APPLY          \ shape amplitude
```

---

## Quick Reference

```
ENV-CREATE     ( a d s r rate -- env )    create ADSR envelope
ENV-CREATE-AR  ( a r rate -- env )        create AR envelope
ENV-FREE       ( env -- )                 free descriptor
ENV-GATE-ON    ( env -- )                 trigger attack
ENV-GATE-OFF   ( env -- )                 trigger release
ENV-RETRIGGER  ( env -- )                 retrigger attack
ENV-RESET      ( env -- )                 reset to idle
ENV-TICK       ( env -- level )           advance one frame
ENV-LEVEL      ( env -- level )           read current level
ENV-DONE?      ( env -- flag )            true if complete
ENV-FILL       ( buf env -- )             fill buffer with curve
ENV-APPLY      ( buf env -- )             multiply buffer by env
```

**Phase constants:**

```
ENV-IDLE      0
ENV-ATTACK    1
ENV-DECAY     2
ENV-SUSTAIN   3
ENV-RELEASE   4
ENV-DONE      5
```

---

## Cookbook

### Plucked String (Fast Attack, Long Decay)

```forth
1 200 FP16-POS-ZERO 500 44100 ENV-CREATE CONSTANT pluck
\ 1 ms attack (instant), 200 ms decay to 0, 500 ms release
440 INT>FP16 OSC-SAW 44100 OSC-CREATE CONSTANT str
4096 44100 16 1 PCM-ALLOC CONSTANT buf
buf str OSC-FILL
pluck ENV-GATE-ON
buf pluck ENV-APPLY
```

### Organ Sustain (Instant Attack, Hold, Instant Release)

```forth
1 1 FP16-POS-ONE 1 44100 ENV-CREATE CONSTANT organ-env
\ Sustain = 1.0 → full volume while gate is on
organ-env ENV-GATE-ON
\ ... tick as needed ...
organ-env ENV-GATE-OFF
```

### Percussion (AR, No Sustain)

```forth
2 50 44100 ENV-CREATE-AR CONSTANT perc
perc ENV-GATE-ON
\ Ticks through attack (2 ms) then jumps to release (50 ms)
```

### Checking Envelope Completion

```forth
BEGIN
    my-env ENV-TICK DROP
    my-env ENV-DONE?
UNTIL
\ Envelope has fully released
```
