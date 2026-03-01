# akashic-audio-mix — N-Channel Mixer for KDOS / Megapad-64

Mixes up to 16 mono input channels to a stereo master output buffer.
Each channel has gain, pan, and mute controls.  Uses equal-power
panning via `TRIG-SINCOS` from `trig.f`.

```forth
REQUIRE audio/mix.f
```

`PROVIDED akashic-audio-mix` — safe to include multiple times.
Depends on `akashic-audio-pcm`, `akashic-math-trig`.

---

## Table of Contents

- [Descriptor Layout](#descriptor-layout)
- [Channel Descriptor](#channel-descriptor)
- [API](#api)
- [Pan Law](#pan-law)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Descriptor Layout

Mixer descriptor (32 bytes):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | n-chans | int | Number of input channels (1–16) |
| +8 | master-gain | FP16 | Master output gain (default 1.0) |
| +16 | master-buf | ptr | Pointer to stereo PCM output buffer |
| +24 | chans | ptr | Pointer to channel descriptor array |

---

## Channel Descriptor

Per-channel descriptor (32 bytes each):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | gain | FP16 | Channel gain (default 1.0) |
| +8 | pan | FP16 | Pan position: −1.0 (left) to +1.0 (right), 0.0 = center |
| +16 | mute | int | 0 = active, 1 = muted |
| +24 | buf | ptr | Pointer to input PCM buffer (mono, 16-bit) |

---

## API

### MIX-CREATE

```forth
MIX-CREATE  ( n-chans frames rate -- mix )
```

Allocates a mixer with **n-chans** input channels and a stereo
master output buffer of **frames** length at the given sample **rate**.

- All channels initialize to: gain=1.0, pan=0.0 (center), unmuted.
- Master gain defaults to 1.0.
- The master buffer is stereo (2 channels), 16-bit.

### MIX-FREE

```forth
MIX-FREE  ( mix -- )
```

Frees the mixer descriptor, channel array, and master PCM buffer.

### MIX-INPUT!

```forth
MIX-INPUT!  ( buf chan# mix -- )
```

Assign a mono PCM buffer as the input source for channel **chan#**.
The buffer must have the same frame count as the master buffer
(or at least as many frames).

### MIX-GAIN!

```forth
MIX-GAIN!  ( gain chan# mix -- )
```

Set per-channel gain (FP16, 0.0–1.0).

### MIX-PAN!

```forth
MIX-PAN!  ( pan chan# mix -- )
```

Set channel pan position (FP16):
- `0xBC00` (−1.0) = hard left
- `0x0000` (0.0) = center
- `0x3C00` (+1.0) = hard right

### MIX-MUTE!

```forth
MIX-MUTE!  ( flag chan# mix -- )
```

Mute (`1`) or unmute (`0`) a channel.

### MIX-MASTER-GAIN!

```forth
MIX-MASTER-GAIN!  ( gain mix -- )
```

Set the master output gain applied after all channels are summed.

### MIX-MASTER

```forth
MIX-MASTER  ( mix -- buf )
```

Return the stereo master output PCM buffer pointer.

### MIX-RENDER

```forth
MIX-RENDER  ( mix -- )
```

Sum all active (non-muted, non-NULL) channels into the stereo master
buffer.

For each active channel:
1. Compute L/R pan gains (equal-power law)
2. Multiply gain × pan_gain for effective L/R weights
3. Accumulate: `master[i,0] += sample × L`, `master[i,1] += sample × R`

Finally applies master gain if ≠ 1.0.

---

## Pan Law

Equal-power panning ensures constant perceived loudness across the
stereo field:

$$
L = \cos\!\left(\frac{\pi}{4} \times (1 + \text{pan})\right), \quad
R = \sin\!\left(\frac{\pi}{4} \times (1 + \text{pan})\right)
$$

| Pan | Angle | L | R | Description |
|-----|-------|---|---|-------------|
| −1.0 | 0 | 1.0 | 0.0 | Hard left |
| 0.0 | π/4 | 0.707 | 0.707 | Center (−3 dB each) |
| +1.0 | π/2 | 0.0 | 1.0 | Hard right |

---

## Quick Reference

```
MIX-CREATE        ( n-chans frames rate -- mix )
MIX-FREE          ( mix -- )
MIX-GAIN!         ( gain chan# mix -- )
MIX-PAN!          ( pan chan# mix -- )
MIX-MUTE!         ( flag chan# mix -- )
MIX-MASTER-GAIN!  ( gain mix -- )
MIX-INPUT!        ( buf chan# mix -- )
MIX-RENDER        ( mix -- )
MIX-MASTER        ( mix -- buf )
```

---

## Cookbook

### Simple Stereo Mix

```forth
\ Two mono sources → stereo
2 256 44100 MIX-CREATE  CONSTANT mymixer
buf-left  0 mymixer MIX-INPUT!
buf-right 1 mymixer MIX-INPUT!
0xBC00 0 mymixer MIX-PAN!       \ ch0 hard left
0x3C00 1 mymixer MIX-PAN!       \ ch1 hard right
mymixer MIX-RENDER
mymixer MIX-MASTER               \ → stereo PCM buffer
```

### 4-Channel Mix with Levels

```forth
4 512 44100 MIX-CREATE  CONSTANT mymixer
buf0 0 mymixer MIX-INPUT!
buf1 1 mymixer MIX-INPUT!
buf2 2 mymixer MIX-INPUT!
buf3 3 mymixer MIX-INPUT!

0x3400 0 mymixer MIX-GAIN!      \ ch0 at -6 dB (0.25)
0x3C00 1 mymixer MIX-GAIN!      \ ch1 at  0 dB (1.0)
0x3800 2 mymixer MIX-GAIN!      \ ch2 at -3 dB (0.5)
1      3 mymixer MIX-MUTE!      \ ch3 muted

0x3800 mymixer MIX-MASTER-GAIN! \ master at -3 dB
mymixer MIX-RENDER
```

### Effects Chain → Mixer

```forth
\ Process two oscillators through effects, then mix
buf0 myeffect0 FX-DELAY-PROCESS
buf1 myeffect1 FX-REVERB-PROCESS

2 256 44100 MIX-CREATE  CONSTANT mymixer
buf0 0 mymixer MIX-INPUT!
buf1 1 mymixer MIX-INPUT!
mymixer MIX-RENDER
\ Now mymixer MIX-MASTER is ready for output
```
