# akashic-audio-seq — Step Sequencer for KDOS / Megapad-64

Pattern-based step sequencer that drives any sound source via a
callback execution token.  Tempo-locked to sample-accurate tick
boundaries with optional swing.

```forth
REQUIRE audio/seq.f
```

`PROVIDED akashic-audio-seq`
Dependencies: `fp16-ext.f`, `audio/pcm.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Pattern Access](#pattern-access)
- [Playback Control](#playback-control)
- [Tick Engine](#tick-engine)
- [Tempo & Swing](#tempo--swing)
- [Callback Convention](#callback-convention)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Sample-accurate** | Tick boundaries are computed in sample frames, not wall-clock time. |
| **Callback-driven** | `SEQ-TICK` fires a user-supplied execution token when a step fires. |
| **Swing** | Even-numbered steps can be delayed by a fraction of half a tick. |
| **Loop / one-shot** | Configurable: loop wraps back to step 0, one-shot stops at end. |
| **Variable-based state** | Scratch via `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `SEQ-`.  Internal: `_SQ-`. |

---

## Memory Layout

Sequencer descriptor: 10 cells (80 bytes) + inline pattern data.

```
Offset  Size   Field
──────  ─────  ──────────────
+0      8      bpm        — tempo in beats per minute
+8      8      steps      — pattern length (1–64)
+16     8      rate       — sample rate in Hz
+24     8      tick-f     — frames per tick (computed)
+32     8      pos        — current step position
+40     8      tcnt       — tick frame counter
+48     8      cb         — callback XT (0 = none)
+56     8      run        — running flag (-1 = running)
+64     8      loop       — loop flag (-1 = loop, 0 = one-shot)
+72     8      swing      — swing amount (FP16, 0 = none)
+80     …      pattern    — steps × 3 cells (24 bytes/step)
```

Each pattern step is 3 cells:

| Cell | Field | Meaning |
|---|---|---|
| +0 | note | MIDI note number (0 = rest → callback skipped) |
| +8 | velocity | 0–127 |
| +16 | gate | Gate length in ticks |

---

## Creation & Destruction

### SEQ-CREATE

```forth
SEQ-CREATE  ( bpm steps rate -- seq )
```

Allocate a sequencer with `steps` slots at the given BPM and sample
rate.  Steps must be 1–64.  Pattern is zeroed (all rests).

### SEQ-FREE

```forth
SEQ-FREE  ( seq -- )
```

Free the sequencer descriptor and pattern.

---

## Pattern Access

### SEQ-STEP!

```forth
SEQ-STEP!  ( note vel gate step# seq -- )
```

Write a step into the pattern.

### SEQ-STEP@

```forth
SEQ-STEP@  ( step# seq -- note vel gate )
```

Read a step from the pattern.

---

## Playback Control

### SEQ-START / SEQ-STOP

```forth
SEQ-START  ( seq -- )
SEQ-STOP   ( seq -- )
```

Start or stop playback.  `SEQ-START` resets position and counter.

### SEQ-RUNNING?

```forth
SEQ-RUNNING?  ( seq -- flag )
```

Returns -1 if running, 0 if stopped.

### SEQ-POSITION

```forth
SEQ-POSITION  ( seq -- step# )
```

Returns the current step index.

---

## Tick Engine

### SEQ-TICK

```forth
SEQ-TICK  ( frames seq -- fired? )
```

Advance the sequencer by `frames` sample frames.  If a step boundary
is crossed:

1. If the step's note ≠ 0 and a callback is set, fire callback with
   `( note vel gate -- )`.
2. Advance position.  If looping and past end, wrap to 0.  If one-shot
   and past end, stop.
3. Return -1 (fired).

If no boundary is crossed, return 0.

**Tick-frames formula:**

$$\text{tick-frames} = \frac{\text{rate} \times 60}{\text{bpm} \times 4}$$

One tick = one sixteenth note.

---

## Tempo & Swing

### SEQ-BPM!

```forth
SEQ-BPM!  ( bpm seq -- )
```

Change BPM and recompute tick-frames.

### SEQ-SWING!

```forth
SEQ-SWING!  ( swing seq -- )
```

Set swing amount (FP16).  Even-numbered steps are delayed by
`swing × (tick-frames / 2)` frames.  0 = straight, 0x3800 (0.5) =
maximum shuffle.

### SEQ-LOOP!

```forth
SEQ-LOOP!  ( flag seq -- )
```

Set loop mode: -1 = loop, 0 = one-shot.

---

## Callback Convention

### SEQ-CALLBACK!

```forth
SEQ-CALLBACK!  ( xt seq -- )
```

Set the callback execution token.  The callback is called with:

```forth
( note vel gate -- )
```

**Important:** Use `[']` (not `'`) inside colon definitions to get the
XT.  The `'` word does not work inside compiled definitions in this
Forth system.

```forth
: MY-CB  ( note vel gate -- ) DROP DROP DROP ." fired!" CR ;
: SETUP  ['] MY-CB my-seq SEQ-CALLBACK! ;
```

---

## Internals

### Tick-Frames Computation

```forth
_SQ-CALC-TICKF  ( seq -- )
```

Computes `rate × 60 / (bpm × 4)` and stores in the descriptor's
tick-frames field.  Called by `SEQ-CREATE` and `SEQ-BPM!`.

### Step Firing

```forth
_SQ-FIRE-STEP  ( seq -- )
```

Reads the current step.  If note ≠ 0 and callback ≠ 0, executes the
callback via `EXECUTE`.

### Scratch Variables

`_SQ-BPM`, `_SQ-STEPS`, `_SQ-RATE`, `_SQ-SEQ` — used during creation
and tick processing.

---

## Quick Reference

```
SEQ-CREATE     ( bpm steps rate -- seq )
SEQ-FREE       ( seq -- )
SEQ-STEP!      ( note vel gate step# seq -- )
SEQ-STEP@      ( step# seq -- note vel gate )
SEQ-START      ( seq -- )
SEQ-STOP       ( seq -- )
SEQ-TICK       ( frames seq -- fired? )
SEQ-BPM!       ( bpm seq -- )
SEQ-SWING!     ( swing seq -- )
SEQ-CALLBACK!  ( xt seq -- )
SEQ-POSITION   ( seq -- step# )
SEQ-RUNNING?   ( seq -- flag )
SEQ-LOOP!      ( flag seq -- )
```

---

## Cookbook

### Basic 4-step pattern

```forth
VARIABLE my-seq
: MY-CB  ( note vel gate -- )
    DROP DROP  ." note=" . CR ;

: INIT
    120 4 44100 SEQ-CREATE my-seq !
    60 100 4  0 my-seq @ SEQ-STEP!   \ C4
    64 100 4  1 my-seq @ SEQ-STEP!   \ E4
    67 100 4  2 my-seq @ SEQ-STEP!   \ G4
    72 100 4  3 my-seq @ SEQ-STEP!   \ C5
    ['] MY-CB my-seq @ SEQ-CALLBACK!
    1 my-seq @ SEQ-LOOP!
    my-seq @ SEQ-START ;

\ In audio callback: 256 my-seq @ SEQ-TICK DROP
```

### One-shot drum fill

```forth
120 2 44100 SEQ-CREATE my-fill !
36 127 2  0 my-fill @ SEQ-STEP!   \ kick
38 100 1  1 my-fill @ SEQ-STEP!   \ snare
0 my-fill @ SEQ-LOOP!             \ one-shot
```
