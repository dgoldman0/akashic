# akashic-audio-poly — Polyphonic Voice Manager for KDOS / Megapad-64

Wraps N identical `synth.f` voices into a polyphonic instrument with
intelligent voice stealing, per-voice biquad filter state context
switching, and a master output buffer.

```forth
REQUIRE audio/poly.f
```

`PROVIDED akashic-audio-poly` — safe to include multiple times.
Depends on `akashic-fp16-ext`, `akashic-audio-pcm`, `akashic-audio-osc`,
`akashic-audio-env`, `akashic-audio-synth`.

---

## Table of Contents

- [Descriptor Layout](#descriptor-layout)
- [Voice Stealing](#voice-stealing)
- [Filter State Isolation](#filter-state-isolation)
- [API](#api)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Descriptor Layout

Poly descriptor (48 bytes):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | n-voices | int | Number of synth voices in the pool |
| +8 | voices | ptr | Pointer to array of synth voice descriptors |
| +16 | states | ptr | Pointer to filter state array (2 FP16 per voice) |
| +24 | master-buf | ptr | Pointer to master output PCM buffer (mono) |
| +32 | frames | int | Block size in frames |
| +40 | rate | int | Sample rate (Hz) |

---

## Voice Stealing

When `POLY-NOTE-ON` is called, voices are allocated in priority order:

1. **Idle or done voices** — envelope in `ENV-IDLE` or `ENV-DONE`
   phase.  These are preferred since they produce no audible output.
2. **Quietest active voice** — among voices still sounding, the one
   with the lowest amplitude envelope level is stolen.

This ensures new notes never cut off louder, more perceptually
important voices.

---

## Filter State Isolation

Each `synth.f` voice uses global biquad filter state variables
(`_SY-FS1`, `_SY-FS2`).  `POLY-RENDER` saves and restores these
per-voice via `SYNTH-SAVE-FILT` / `SYNTH-LOAD-FILT`, ensuring
independent filter behaviour across voices.

When a voice is stolen via `POLY-NOTE-ON`, its filter state is
reset to zero (clean start for the new note).

---

## API

### POLY-CREATE

```forth
POLY-CREATE  ( n shape1 shape2 rate frames -- poly )
```

Create a polyphonic voice pool with **n** identical synth voices.
All voices use oscillator shapes **shape1** and **shape2** at the
given sample **rate**, rendering **frames** per block.

- Minimum 1 voice (aborts otherwise).
- A mono master output buffer is allocated automatically.
- Default synth parameters apply to all voices (LP filter,
  cutoff=1000 Hz, Q=0.707, etc.).

### POLY-FREE

```forth
POLY-FREE  ( poly -- )
```

Free all voices, arrays, master buffer, and descriptor.

### POLY-NOTE-ON

```forth
POLY-NOTE-ON  ( freq vel poly -- )
```

Allocate the best available voice and trigger a note.  Uses the
[voice stealing](#voice-stealing) priority to select which voice.

### POLY-NOTE-OFF-ALL

```forth
POLY-NOTE-OFF-ALL  ( poly -- )
```

Release all voices (all envelopes enter release phase).

### POLY-RENDER

```forth
POLY-RENDER  ( poly -- buf )
```

Render one block from all voices and accumulate into the master
buffer.  For each voice:
1. Load per-voice filter state
2. Call `SYNTH-RENDER`
3. Save filter state
4. Add voice output to master buffer (FP16 accumulation)

Returns the master PCM buffer pointer.

### POLY-VOICE

```forth
POLY-VOICE  ( idx poly -- voice )
```

Return the raw `synth.f` voice descriptor for index **idx**
(0-based).  Use for per-voice customization (cutoff, reso, detune).

### POLY-COUNT

```forth
POLY-COUNT  ( poly -- n )
```

Return the number of voices in the pool.

### POLY-CUTOFF!

```forth
POLY-CUTOFF!  ( freq poly -- )
```

Set filter cutoff on all voices simultaneously.

### POLY-RESO!

```forth
POLY-RESO!  ( q poly -- )
```

Set filter resonance on all voices simultaneously.

---

## Quick Reference

```
POLY-CREATE       ( n shape1 shape2 rate frames -- poly )
POLY-FREE         ( poly -- )
POLY-NOTE-ON      ( freq vel poly -- )
POLY-NOTE-OFF-ALL ( poly -- )
POLY-RENDER       ( poly -- buf )
POLY-VOICE        ( idx poly -- voice )
POLY-COUNT        ( poly -- n )
POLY-CUTOFF!      ( freq poly -- )
POLY-RESO!        ( q poly -- )
```

---

## Cookbook

### 4-Voice Sine Pad

```forth
4 0 0 44100 256 POLY-CREATE  CONSTANT my-pad
440 INT>FP16 0x3C00 my-pad POLY-NOTE-ON   \ A4
523 INT>FP16 0x3C00 my-pad POLY-NOTE-ON   \ C5
659 INT>FP16 0x3C00 my-pad POLY-NOTE-ON   \ E5
my-pad POLY-RENDER  ( → master buf with 3-note chord )
my-pad POLY-FREE
```

### Warm Saw Chord with Low-Pass

```forth
4 1 1 44100 256 POLY-CREATE  CONSTANT my-pad
200 INT>FP16 my-pad POLY-CUTOFF!     \ warm LP at 200 Hz
0x4000 my-pad POLY-RESO!             \ mild resonance
220 INT>FP16 0x3C00 my-pad POLY-NOTE-ON
277 INT>FP16 0x3C00 my-pad POLY-NOTE-ON
330 INT>FP16 0x3C00 my-pad POLY-NOTE-ON
my-pad POLY-RENDER DROP
my-pad POLY-NOTE-OFF-ALL
my-pad POLY-RENDER  ( → release tail )
my-pad POLY-FREE
```

### Accessing Individual Voices

```forth
4 0 0 44100 256 POLY-CREATE  CONSTANT my-pad
\ Detune voice 2 for chorus effect
0x4100 2 my-pad POLY-VOICE SYNTH-DETUNE!
\ Custom cutoff on voice 0 only
500 INT>FP16 0 my-pad POLY-VOICE SYNTH-CUTOFF!
```

### Voice Stealing in Action

```forth
2 0 0 44100 256 POLY-CREATE  CONSTANT my-pad
\ Two voices, three notes — third steals quietest
440 INT>FP16 0x3C00 my-pad POLY-NOTE-ON   \ → voice 0
523 INT>FP16 0x3C00 my-pad POLY-NOTE-ON   \ → voice 1
my-pad POLY-RENDER DROP                    \ advance envelopes
659 INT>FP16 0x3C00 my-pad POLY-NOTE-ON   \ steals quietest
my-pad POLY-RENDER  ( → two-voice output )
my-pad POLY-FREE
```
