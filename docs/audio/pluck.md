# akashic-audio-pluck — Karplus-Strong Plucked String for KDOS / Megapad-64

Physical-model synthesis of plucked strings using the Karplus-Strong
algorithm.  A circular delay line is excited with white noise and
filtered with an averaging low-pass at the read head.  Pitch is
determined by the delay-line length (`rate / freq`).

```forth
REQUIRE audio/pluck.f
```

`PROVIDED akashic-audio-pluck` — safe to include multiple times.
Depends on `akashic-fp16-ext`, `akashic-audio-pcm`, `akashic-audio-noise`.

---

## Table of Contents

- [Descriptor Layout](#descriptor-layout)
- [Algorithm](#algorithm)
- [API](#api)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Descriptor Layout

Pluck descriptor (56 bytes):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | dl-data | ptr | Pointer to delay-line sample buffer (FP16) |
| +8 | dl-len | int | Delay-line length in samples (`rate / freq`) |
| +16 | dl-wptr | int | Current write-pointer index |
| +24 | rate | int | Sample rate (Hz) |
| +32 | freq | FP16 | Fundamental frequency |
| +40 | decay | FP16 | Decay coefficient (default 0.996) |
| +48 | work-buf | ptr | 256-frame mono PCM output buffer |

---

## Algorithm

Each sample:

1. Read the current sample `s[n]` and the next sample `s[n+1]` from
   the circular delay line.
2. Compute the averaged value: $y = \frac{s[n] + s[n+1]}{2}$
3. Apply decay: $y' = y \times \text{decay}$
4. Write $y'$ back to the delay line at the write pointer.
5. Advance the write pointer (wrapping at `dl-len`).
6. Output $y'$ as the next PCM sample.

The delay-line length sets the fundamental:

$$
L = \left\lfloor \frac{\text{rate}}{\text{freq}} \right\rfloor
$$

Higher decay values sustain longer; lower values damp faster.

---

## API

### PLUCK-CREATE

```forth
PLUCK-CREATE  ( freq rate -- desc )
```

Allocate a pluck voice with fundamental **freq** (FP16, Hz) at the
given integer sample **rate**.

- Delay line is sized to `rate / freq` samples.
- Decay defaults to 0.996.
- A 256-frame mono work buffer is allocated.

### PLUCK-FREE

```forth
PLUCK-FREE  ( desc -- )
```

Free the descriptor, delay-line buffer, and work buffer.

### PLUCK-EXCITE

```forth
PLUCK-EXCITE  ( desc -- )
```

Fill the delay line with white noise (via `NOISE-RENDER`), simulating
the initial pluck of the string.

### PLUCK-RENDER

```forth
PLUCK-RENDER  ( desc -- buf )
```

Render 256 frames of plucked-string audio into the internal work
buffer.  Returns the PCM buffer pointer.

### PLUCK-DECAY!

```forth
PLUCK-DECAY!  ( decay desc -- )
```

Set the decay coefficient (FP16).  Values near 1.0 sustain longer;
values near 0.5 damp rapidly.

### PLUCK-FREQ

```forth
PLUCK-FREQ  ( desc -- freq )
```

Return the stored fundamental frequency (FP16).

### PLUCK-LEN

```forth
PLUCK-LEN  ( desc -- len )
```

Return the delay-line length in samples.

### PLUCK

```forth
PLUCK  ( freq decay buf -- )
```

One-shot convenience word.  Creates a temporary pluck voice at
44100 Hz, excites it, renders one block, copies the first 64 frames
to **buf**, and frees the voice.  **freq** and **decay** are FP16.

---

## Quick Reference

```
PLUCK-CREATE   ( freq rate -- desc )
PLUCK-FREE     ( desc -- )
PLUCK-EXCITE   ( desc -- )
PLUCK-RENDER   ( desc -- buf )
PLUCK-DECAY!   ( decay desc -- )
PLUCK-FREQ     ( desc -- freq )
PLUCK-LEN      ( desc -- len )
PLUCK          ( freq decay buf -- )
```

---

## Cookbook

### Basic Plucked String

```forth
440 INT>FP16 44100 PLUCK-CREATE  CONSTANT mypluck
mypluck PLUCK-EXCITE
mypluck PLUCK-RENDER  ( → buf )
\ buf now contains 256 frames of plucked sound
mypluck PLUCK-FREE
```

### Guitar-Like Sustained Note

```forth
330 INT>FP16 44100 PLUCK-CREATE  CONSTANT mypluck
\ High decay for long sustain
0x3BF6  mypluck PLUCK-DECAY!    \ ~0.998
mypluck PLUCK-EXCITE
\ Render multiple blocks for sustained note
mypluck PLUCK-RENDER DROP
mypluck PLUCK-RENDER DROP
mypluck PLUCK-RENDER             \ third block still ringing
mypluck PLUCK-FREE
```

### Quick One-Shot

```forth
64 1 PCM-BUF-ALLOC  CONSTANT mybuf
440 INT>FP16  0x3BF0  mybuf PLUCK
\ mybuf now has 64 frames of plucked sound
mybuf FREE
```

### Re-excite (Multiple Plucks)

```forth
440 INT>FP16 44100 PLUCK-CREATE  CONSTANT mypluck
mypluck PLUCK-EXCITE
mypluck PLUCK-RENDER DROP         \ first pluck
mypluck PLUCK-RENDER DROP         \ decaying…
mypluck PLUCK-EXCITE              \ pluck again!
mypluck PLUCK-RENDER DROP         \ fresh attack
mypluck PLUCK-FREE
```
