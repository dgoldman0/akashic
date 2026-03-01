# akashic-audio-porta — Monophonic Portamento for KDOS / Megapad-64

Wraps a single `synth.f` voice with exponential frequency glide
(portamento).  The first note snaps to pitch instantly; subsequent
notes glide from the current frequency to the new target.

```forth
REQUIRE audio/porta.f
```

`PROVIDED akashic-audio-porta` — safe to include multiple times.
Depends on `akashic-fp16-ext`, `akashic-audio-osc`, `akashic-audio-synth`.

---

## Table of Contents

- [Descriptor Layout](#descriptor-layout)
- [Glide Algorithm](#glide-algorithm)
- [API](#api)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Descriptor Layout

Porta descriptor (40 bytes):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | voice | ptr | Synth voice descriptor (NOT owned) |
| +8 | current-freq | FP16 | Current glide frequency (Hz) |
| +16 | target-freq | FP16 | Target frequency (Hz) |
| +24 | glide-speed | FP16 | Glide coefficient (0.0–1.0) |
| +32 | is-playing | int | 0 = idle, 1 = playing |

---

## Glide Algorithm

Each `PORTA-TICK` (once per render block):

$$
f_{\text{current}} \leftarrow f_{\text{current}} + (f_{\text{target}} - f_{\text{current}}) \times \text{speed}
$$

This is exponential approach — the frequency halves the remaining
distance each tick when speed = 0.5.

| Speed | Behaviour |
|-------|-----------|
| 1.0 (0x3C00) | Instant snap (no glide) |
| 0.5 (0x3800) | Fast glide — halves distance per block |
| 0.05 (0x2A66) | Smooth glide — ~0.5 s at 44100 Hz / 256 frames |
| 0.01 | Very slow portamento |

After updating the current frequency, `PORTA-TICK` sets OSC1 and
OSC2 (with detune) to the new value.

### First Note Snap

When `is-playing` is 0, `PORTA-NOTE-ON` sets both current and target
to the same frequency — no glide on the first note.  Subsequent notes
while playing set only the target, causing a glide.

---

## API

### PORTA-CREATE

```forth
PORTA-CREATE  ( voice speed -- porta )
```

Create a portamento wrapper around an existing synth voice.
The **voice** is NOT owned — caller is responsible for freeing it.
**speed** is the glide coefficient (FP16, 0.0–1.0).

### PORTA-FREE

```forth
PORTA-FREE  ( porta -- )
```

Free the porta descriptor only.  Does **not** free the synth voice.

### PORTA-NOTE-ON

```forth
PORTA-NOTE-ON  ( freq vel porta -- )
```

Set the target frequency and trigger `SYNTH-NOTE-ON`.

- If not playing: snaps current to target (no glide).
- If playing: sets target, lets `PORTA-TICK` glide there.
- The synth voice is always triggered with the **current** frequency
  (not the target), so the glide starts from where the pitch is.

### PORTA-NOTE-OFF

```forth
PORTA-NOTE-OFF  ( porta -- )
```

Release the synth voice.  Marks porta as not playing, so the next
`PORTA-NOTE-ON` will snap rather than glide.

### PORTA-SPEED!

```forth
PORTA-SPEED!  ( speed porta -- )
```

Set the glide coefficient (FP16).

### PORTA-TICK

```forth
PORTA-TICK  ( porta -- )
```

Advance the glide by one step.  Call once per render block.
Updates both OSC1 and OSC2 (with detune) frequencies.

### PORTA-RENDER

```forth
PORTA-RENDER  ( porta -- buf )
```

Convenience: `PORTA-TICK` + `SYNTH-RENDER` in one call.  Returns
the synth voice's output buffer.

### PORTA-FREQ

```forth
PORTA-FREQ  ( porta -- freq )
```

Return the current glide frequency (FP16 Hz).

---

## Quick Reference

```
PORTA-CREATE    ( voice speed -- porta )
PORTA-FREE      ( porta -- )
PORTA-NOTE-ON   ( freq vel porta -- )
PORTA-NOTE-OFF  ( porta -- )
PORTA-SPEED!    ( speed porta -- )
PORTA-TICK      ( porta -- )
PORTA-RENDER    ( porta -- buf )
PORTA-FREQ      ( porta -- freq )
```

---

## Cookbook

### Basic Lead with Glide

```forth
0 0 44100 256 SYNTH-CREATE  CONSTANT my-synth
my-synth 0x2A66 PORTA-CREATE  CONSTANT my-lead  \ speed ≈ 0.05

440 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON  \ A4 — snaps
my-lead PORTA-RENDER DROP

523 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON  \ C5 — glides from A4
my-lead PORTA-RENDER DROP                   \ gliding…
my-lead PORTA-RENDER DROP                   \ still gliding…

my-lead PORTA-FREE
my-synth SYNTH-FREE
```

### Instant Pitch (No Glide)

```forth
my-synth 0x3C00 PORTA-CREATE  CONSTANT my-lead  \ speed = 1.0
440 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON
my-lead PORTA-RENDER DROP
523 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON       \ instant jump to C5
my-lead PORTA-RENDER  ( → at C5, no glide )
```

### Changing Glide Speed at Runtime

```forth
my-synth 0x2A66 PORTA-CREATE  CONSTANT my-lead
440 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON
my-lead PORTA-RENDER DROP

\ Speed up the glide mid-phrase
0x3800 my-lead PORTA-SPEED!           \ 0.5 — fast glide
523 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON
my-lead PORTA-RENDER  ( → fast glide to C5 )
```

### Reading Current Pitch

```forth
my-synth 0x3800 PORTA-CREATE  CONSTANT my-lead
200 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON
400 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON
my-lead PORTA-TICK
my-lead PORTA-FREQ  ( → FP16 freq between 200 and 400 )
```
