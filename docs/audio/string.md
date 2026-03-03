# akashic-syn-string — Multi-Voice String Synthesis for KDOS / Megapad-64

Multi-voice Karplus-Strong string instrument engine.  Wraps `pluck.f`
primitives into the standard `syn/` CREATE / RENDER / FREE engine
pattern with per-voice tuning, body resonance filtering, presets,
damping, and one-shot strike.

```forth
REQUIRE audio/syn/string.f
```

`PROVIDED akashic-syn-string` — safe to include multiple times.
Depends on `akashic-fp16-ext`, `akashic-audio-pluck`, `akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Voice Configuration](#voice-configuration)
- [Engine Parameters](#engine-parameters)
- [Excitation & Damping](#excitation--damping)
- [Rendering](#rendering)
- [Presets](#presets)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Karplus-Strong per voice** | Each voice is a full `pluck.f` descriptor with its own delay line, frequency, and decay factor. |
| **1..8 voices** | Supports up to 8 independently tuned + decayed voices.  Create count is clamped. |
| **Division normalisation** | Mixed output is divided by N voices to prevent FP16 clipping when all voices are active. |
| **Body resonance LP** | Optional 1-pole LP filter colours the combined output.  Alpha = 0 bypasses; 0.3 = warm; 0.8 = very dark. |
| **Master amplitude** | Global gain control applied after body filter. |
| **Palm mute** | `STR-DAMP` zeros all delay lines instantly — silences all voices. |
| **One-shot STRIKE** | Allocates a PCM buffer, excites all voices, renders, returns the buffer.  Convenient for non-streaming use. |
| **Block-based RENDER** | `STR-RENDER` fills a user-supplied PCM buffer.  Supports continuous streaming. |
| **Prefix convention** | Public: `STR-`.  Internal: `_ST-`.  Field: `ST.xxx`. |

---

## Memory Layout

### Descriptor (10 cells = 80 bytes)

```
Offset  Size  Field
──────  ────  ──────────────────────
+0      8     n-voices      Number of active voices, 1..8 (integer)
+8      8     rate          Sample rate Hz (integer)
+16     8     voices        Pointer to voice pointer array
+24     8     body-alpha    Body LP filter coefficient (FP16), 0 = bypass
+32     8     body-state    LP filter state (FP16)
+40     8     strum-ms      Strum spread delay in ms (integer) [reserved]
+48     8     master-amp    Output amplitude scale (FP16), default 1.0
+56     8     (reserved)
+64     8     (reserved)
+72     8     (reserved)
```

### Voice Array

A heap-allocated array of N pointers, each pointing to a
`pluck.f` descriptor (56 bytes per voice).

---

## Creation & Destruction

### STR-CREATE

```forth
STR-CREATE  ( n-voices rate -- desc )
```

Allocate a string engine with **n-voices** independent Karplus-Strong
voices at sample rate **rate**.  Each voice defaults to 220 Hz
with decay = 0.996.  Body filter is bypassed (alpha = 0).
Master amplitude = 1.0.

Voice count is clamped to `[1, 8]`.

### STR-FREE

```forth
STR-FREE  ( desc -- )
```

Free the engine, all internal pluck voices, and the voice pointer
array.

---

## Voice Configuration

### STR-VOICE!

```forth
STR-VOICE!  ( freq decay voice# desc -- )
```

Set the **frequency** (FP16 Hz) and **decay** (FP16, 0.0–1.0) for
voice number **voice#** (0-indexed).  Destroys and recreates the
underlying pluck voice to resize the delay line.

Out-of-bounds voice# is silently ignored.

### STR-FREQ!

```forth
STR-FREQ!  ( freq voice# desc -- )
```

Change only the frequency for voice **voice#**, preserving the
current decay setting.  Recreates the voice internally.

### STR-DECAY!

```forth
STR-DECAY!  ( decay voice# desc -- )
```

Change only the decay factor for voice **voice#**.  Does not
reallocate — modifies the voice's decay field in place.

---

## Engine Parameters

### STR-BODY!

```forth
STR-BODY!  ( alpha desc -- )
```

Set the body resonance LP filter coefficient (FP16).
- `0` — bypass (raw Karplus-Strong)
- `0.3` — warm, guitar-body character
- `0.8` — very dark, muted

The filter is: `y += alpha × (x − y)`.

### STR-AMP!

```forth
STR-AMP!  ( amp desc -- )
```

Set master output amplitude (FP16).

### STR-STRUM!

```forth
STR-STRUM!  ( ms desc -- )
```

Set strum spread time in milliseconds.  When `STR-EXCITE` is called,
each successive voice's excitation is delayed by `strum-ms × voice#`
samples.  (Reserved — currently sets the field but strum delay is
not yet applied in excitation.)

---

## Excitation & Damping

### STR-EXCITE

```forth
STR-EXCITE  ( desc -- )
```

Excite (pluck) all voices.  Fills each voice's delay line with
white noise via `PLUCK-EXCITE`.

### STR-DAMP

```forth
STR-DAMP  ( desc -- )
```

Instantly silence all voices.  Zeros every delay line and resets
the body filter state.  (Palm mute effect.)

---

## Rendering

### STR-RENDER

```forth
STR-RENDER  ( buf desc -- )
```

Render one block into the user-supplied PCM buffer **buf**.  The
buffer must have been allocated with `PCM-ALLOC`.  Fills `PCM-LEN`
frames.  Call repeatedly for continuous streaming.

Algorithm per sample:
1. Generate one sample from each voice via `_PL-SAMPLE`
2. Sum and divide by N voices
3. Apply body LP filter (if alpha > 0)
4. Scale by master amplitude
5. Store to buffer

### STR-STRIKE

```forth
STR-STRIKE  ( duration-ms desc -- buf )
```

One-shot convenience:
1. Computes frame count from duration and rate
2. Allocates a new PCM buffer
3. Calls `STR-EXCITE`
4. Renders all frames
5. Returns the buffer (caller must `PCM-FREE`)

---

## Presets

### STR-CHORD

```forth
STR-CHORD  ( desc -- )
```

Configure voices for standard guitar tuning:
E2 (82 Hz), A2 (110), D3 (147), G3 (196), B3 (247), E4 (330).
Requires ≥ 6 voices.  Sets decay ≈ 0.998.

### STR-PRESET-BASS

```forth
STR-PRESET-BASS  ( desc -- )
```

4-string bass: E1 (41), A1 (55), D2 (73), G2 (98).
Requires ≥ 4 voices.

### STR-PRESET-HARP

```forth
STR-PRESET-HARP  ( desc -- )
```

8-string C major harp: C4 D4 E4 F4 G4 A4 B4 C5.
Requires 8 voices.

### STR-PRESET-METAL

```forth
STR-PRESET-METAL  ( desc -- )
```

6 close-pitched inharmonic voices around 400 Hz base for cymbal /
bell / metallic textures: 401, 563, 712, 831, 1087, 1347 Hz.
Requires ≥ 6 voices.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `STR-CREATE` | `( n-voices rate -- desc )` | Allocate engine |
| `STR-FREE` | `( desc -- )` | Free engine + all voices |
| `STR-VOICE!` | `( freq decay voice# desc -- )` | Set voice freq + decay |
| `STR-FREQ!` | `( freq voice# desc -- )` | Set voice frequency |
| `STR-DECAY!` | `( decay voice# desc -- )` | Set voice decay |
| `STR-BODY!` | `( alpha desc -- )` | Set body LP filter |
| `STR-AMP!` | `( amp desc -- )` | Set master amplitude |
| `STR-STRUM!` | `( ms desc -- )` | Set strum spread [reserved] |
| `STR-EXCITE` | `( desc -- )` | Pluck all voices |
| `STR-DAMP` | `( desc -- )` | Silence all voices |
| `STR-RENDER` | `( buf desc -- )` | Render block |
| `STR-STRIKE` | `( duration-ms desc -- buf )` | One-shot render |
| `STR-CHORD` | `( desc -- )` | Guitar preset |
| `STR-PRESET-BASS` | `( desc -- )` | Bass preset |
| `STR-PRESET-HARP` | `( desc -- )` | Harp preset |
| `STR-PRESET-METAL` | `( desc -- )` | Metallic preset |

---

## Cookbook

### Simple plucked string
```forth
1 8000 STR-CREATE
DUP 440 INT>FP16 997 INT>FP16 1000 INT>FP16 FP16-DIV 0 ROT STR-VOICE!
DUP STR-EXCITE
DUP 500 SWAP STR-STRIKE
\ → PCM buffer with 4000 frames of plucked 440 Hz
SWAP STR-FREE  PCM-FREE
```

### Guitar strum
```forth
6 8000 STR-CREATE
DUP STR-CHORD
DUP 0x3266 SWAP STR-BODY!    \ warm body resonance
DUP STR-EXCITE
DUP 2000 SWAP STR-STRIKE     \ 2 seconds of strummed guitar
SWAP STR-FREE  PCM-FREE
```

### Metallic cymbal crash
```forth
6 8000 STR-CREATE
DUP STR-PRESET-METAL
DUP STR-EXCITE
DUP 3000 SWAP STR-STRIKE     \ 3 seconds of metallic decay
SWAP STR-FREE  PCM-FREE
```

### Continuous rendering (streaming)
```forth
1 8000 STR-CREATE  VARIABLE _STR
_STR !

440 INT>FP16 997 INT>FP16 1000 INT>FP16 FP16-DIV 0 _STR @ STR-VOICE!
_STR @ STR-EXCITE

\ Pre-allocate buffer
256 8000 16 1 PCM-ALLOC  VARIABLE _BUF  _BUF !

\ Render loop
BEGIN
    _BUF @  _STR @  STR-RENDER
    \ ... send _BUF @ to audio output ...
AGAIN

_BUF @ PCM-FREE
_STR @ STR-FREE
```

### Palm mute effect
```forth
1 8000 STR-CREATE  VARIABLE _S  _S !
440 INT>FP16 997 INT>FP16 1000 INT>FP16 FP16-DIV 0 _S @ STR-VOICE!
_S @ STR-EXCITE
\ render for a while...
_S @ STR-DAMP            \ ← instant silence
\ re-excite for next note
_S @ STR-EXCITE
```
