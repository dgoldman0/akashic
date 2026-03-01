# akashic-audio-lfo — Low-Frequency Oscillators for KDOS / Megapad-64

Thin wrapper around `osc.f` configured for sub-audio control signals.
Outputs a single FP16 value per tick:

```
value = center + depth × oscillator_output
```

Where `oscillator_output ∈ [−1.0, +1.0]`, so the LFO sweeps
between `center − depth` and `center + depth`.

```forth
REQUIRE audio/lfo.f
```

`PROVIDED akashic-audio-lfo` — safe to include multiple times.
Depends on `akashic-audio-osc`, `akashic-audio-pcm`, `akashic-fp16`,
`akashic-fp16-ext`, `akashic-trig`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Setters & Getters](#setters--getters)
- [Per-Frame Tick](#per-frame-tick)
- [Bulk Generation](#bulk-generation)
- [Sync](#sync)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Thin wrapper** | Delegates all waveform math to an underlying `osc.f` oscillator. |
| **Control rate** | Typically 0.1–20 Hz, but any frequency the oscillator supports. |
| **Center + depth** | Output = `center + depth × osc`, giving a configurable range. |
| **Any waveform** | Inherits all 5 `osc.f` shapes (sine, tri, saw, square, pulse). |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `LFO-`.  Internal: `_LFO-`.  Field: `L.xxx`. |

---

## Memory Layout

An LFO descriptor occupies 4 cells = 32 bytes:

```
Offset  Size  Field
──────  ────  ─────────────────────
+0      8     osc     — pointer to underlying oscillator descriptor
+8      8     depth   — modulation depth (FP16, 0.0–1.0 typical)
+16     8     center  — DC offset / center value (FP16)
+24     8     mode    — 0=free-run, 1=key-sync (reserved)
```

The internal oscillator descriptor (48 bytes) is allocated separately
and freed by `LFO-FREE`.

---

## Creation & Destruction

### LFO-CREATE

```forth
LFO-CREATE  ( freq shape depth center rate -- lfo )
```

Create an LFO.

- **freq** — LFO rate in Hz as FP16 (e.g. `5 INT>FP16` for 5 Hz)
- **shape** — waveform via `osc.f` constants (`OSC-SINE`, `OSC-TRI`, etc.)
- **depth** — modulation depth as FP16
- **center** — center value as FP16
- **rate** — audio sample rate in Hz (integer)

```forth
5 INT>FP16 OSC-SINE FP16-POS-HALF FP16-POS-HALF 44100
LFO-CREATE CONSTANT vibrato
\ 5 Hz sine, output sweeps 0.0 to 1.0 (center 0.5, depth 0.5)
```

### LFO-FREE

```forth
LFO-FREE  ( lfo -- )
```

Free the LFO descriptor and the underlying oscillator.

---

## Setters & Getters

### Setters

```forth
LFO-FREQ!    ( freq lfo -- )     \ set LFO rate (FP16 Hz)
LFO-DEPTH!   ( depth lfo -- )    \ set modulation depth (FP16)
LFO-CENTER!  ( center lfo -- )   \ set center value (FP16)
```

`LFO-FREQ!` propagates to the underlying oscillator via `OSC-FREQ!`.

### Getters

```forth
LFO-DEPTH   ( lfo -- depth )     \ read depth
LFO-CENTER  ( lfo -- center )    \ read center
```

---

## Per-Frame Tick

### LFO-TICK

```forth
LFO-TICK  ( lfo -- value )
```

Generate one control sample:

1. Call `OSC-SAMPLE` on the underlying oscillator → `osc_val ∈ [−1, +1]`
2. Compute `value = center + depth × osc_val`
3. Return `value` as FP16

The oscillator phase advances automatically.

---

## Bulk Generation

### LFO-FILL

```forth
LFO-FILL  ( buf lfo -- )
```

Fill a PCM buffer with the LFO control signal.  Calls `LFO-TICK`
once per frame and writes via `PCM-FRAME!`.  Useful for pre-computing
a modulation curve.

```forth
256 44100 16 1 PCM-ALLOC CONSTANT mod-buf
mod-buf vibrato LFO-FILL
```

---

## Sync

### LFO-SYNC

```forth
LFO-SYNC  ( lfo -- )
```

Reset the underlying oscillator phase to 0.0.  Use for key-sync
(restart LFO phase on each note-on).

```forth
vibrato LFO-SYNC     \ phase back to 0
vibrato LFO-TICK .   \ output = center (since sin(0)=0)
```

---

## Quick Reference

```
LFO-CREATE   ( freq shape depth center rate -- lfo )  create LFO
LFO-FREE     ( lfo -- )                               free LFO + osc
LFO-TICK     ( lfo -- value )                          one control sample
LFO-FILL     ( buf lfo -- )                            fill PCM buffer
LFO-SYNC     ( lfo -- )                                reset phase
LFO-FREQ!    ( freq lfo -- )                           set rate
LFO-DEPTH!   ( depth lfo -- )                          set depth
LFO-CENTER!  ( center lfo -- )                         set center
LFO-DEPTH    ( lfo -- depth )                          read depth
LFO-CENTER   ( lfo -- center )                         read center
```

---

## Cookbook

### Vibrato (Pitch Modulation)

```forth
\ 6 Hz vibrato with ±2% pitch deviation around 1.0
6 INT>FP16 OSC-SINE
2 INT>FP16 100 INT>FP16 FP16-DIV       \ depth = 0.02
FP16-POS-ONE                             \ center = 1.0
44100 LFO-CREATE CONSTANT vibrato

\ Each frame: multiply base freq by LFO value
\ freq_actual = freq_base × vibrato.tick()
```

### Tremolo (Amplitude Modulation)

```forth
\ 4 Hz tremolo, amplitude swings 0.3 to 1.0
4 INT>FP16 OSC-SINE
\ depth = 0.35, center = 0.65 → range [0.3, 1.0]
35 INT>FP16 100 INT>FP16 FP16-DIV       \ 0.35
65 INT>FP16 100 INT>FP16 FP16-DIV       \ 0.65
44100 LFO-CREATE CONSTANT tremolo

\ Each frame: multiply audio sample by tremolo.tick()
```

### Autopan (Stereo Panning)

```forth
\ 0.5 Hz sine sweeps pan from 0.0 (left) to 1.0 (right)
1 INT>FP16 2 INT>FP16 FP16-DIV   \ 0.5 Hz
OSC-SINE
FP16-POS-HALF FP16-POS-HALF      \ depth=0.5, center=0.5
44100 LFO-CREATE CONSTANT autopan
```

### Key-Synced LFO

```forth
\ On each note-on:
autopan LFO-SYNC          \ restart from phase 0
\ Then tick per frame
```
