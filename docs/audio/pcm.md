# akashic-audio-pcm — PCM Audio Buffer Abstraction for KDOS / Megapad-64

Flat interleaved PCM audio buffer with arbitrary sample rates, bit
depths, and channel counts.  Every audio source — earcons, voice,
music, synthesis output, streaming — is a PCM buffer.  Analogous to
`surface.f` for pixels.

```forth
REQUIRE audio/pcm.f
```

`PROVIDED akashic-audio-pcm` — safe to include multiple times.
No dependencies (standalone module).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Accessors](#accessors)
- [Computed Properties](#computed-properties)
- [Sample Access](#sample-access)
- [Bulk Operations](#bulk-operations)
- [Buffer Manipulation](#buffer-manipulation)
- [Time Conversion](#time-conversion)
- [Resampling & Channel Mixing](#resampling--channel-mixing)
- [Analysis & Normalization](#analysis--normalization)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Interleaved storage** | Samples are interleaved: `[L0 R0] [L1 R1] ...`. One "frame" = one sample per channel. |
| **Multi-format** | 8-bit unsigned, 16-bit signed, 32-bit signed.  Sample rates 8000–96000 Hz. |
| **Heap + XMEM** | Descriptor (80 bytes) always on heap. Sample data uses XMEM when available, falls back to heap. |
| **Ownership model** | `PCM-ALLOC` owns its data (freed on `PCM-FREE`). `PCM-CREATE-FROM` and `PCM-SLICE` wrap external data (no free). |
| **Variable-based state** | Internal scratch uses `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `PCM-`. Internal: `_PCM-`. Field accessors: `P.xxx`. |

---

## Memory Layout

A PCM descriptor occupies 10 cells = 80 bytes:

```
Offset  Size   Field
──────  ─────  ──────────────
+0      8      data       — pointer to interleaved sample data
+8      8      len        — number of frames
+16     8      rate       — sample rate in Hz
+24     8      bits       — bits per sample (8, 16, or 32)
+32     8      channels   — channel count (1 = mono, 2 = stereo, ...)
+40     8      flags      — bit 0: owns buffer, bit 1: XMEM buffer
+48     8      offset     — read/write cursor (frame index)
+56     8      peak       — peak absolute sample value seen
+64     8      user       — application-defined payload
+72     8      (reserved)
```

Field accessor words (`P.DATA`, `P.LEN`, ...) return the address of
each field for use with `@` and `!`.

### Sample Data Layout

Samples are stored contiguously in interleaved order.  The byte size
of one frame is `(bits / 8) × channels`.

**Mono (1 channel):**
```
[s0] [s1] [s2] [s3] ...
```

**Stereo (2 channels):**
```
[L0 R0] [L1 R1] [L2 R2] ...
```

Total data size in bytes = `frames × (bits / 8) × channels`.

---

## Creation & Destruction

### PCM-ALLOC

```forth
PCM-ALLOC  ( frames rate bits chans -- buf )
```

Allocate a new PCM buffer.  Sample data is zeroed (silence).
Uses XMEM for the data area when available, heap otherwise.
ABORTs if bits is not 8, 16, or 32, or if allocation fails.

```forth
44100 44100 16 2 PCM-ALLOC CONSTANT one-sec-stereo
1024 8000 8 1 PCM-ALLOC CONSTANT short-mono
```

### PCM-ALLOC-MS

```forth
PCM-ALLOC-MS  ( ms rate bits chans -- buf )
```

Allocate by duration in milliseconds.  Computes the frame count
as `ms × rate / 1000`, then delegates to `PCM-ALLOC`.

```forth
500 44100 16 2 PCM-ALLOC-MS CONSTANT half-sec
\ → 22050 frames at 44100 Hz, 16-bit stereo
```

### PCM-CREATE-FROM

```forth
PCM-CREATE-FROM  ( addr frames rate bits chans -- buf )
```

Wrap an existing sample buffer in a PCM descriptor.  The buffer
does **not** own the data — `PCM-FREE` will not free it.  Use for
hardware DMA buffers, shared memory regions, or aliasing into
larger buffers.

```forth
0x80000000 2048 8000 16 1 PCM-CREATE-FROM CONSTANT dma-buf
```

### PCM-FREE

```forth
PCM-FREE  ( buf -- )
```

Free the descriptor, and the sample data if owned.  XMEM data is
released via `XMEM-FREE-BLOCK`; heap data via `FREE`.  Safe to
call on non-owning buffers (only frees the descriptor).

```forth
one-sec-stereo PCM-FREE
```

---

## Accessors

Read-only field access.  Each returns the field value (not address).

```forth
PCM-DATA    ( buf -- addr )      \ pointer to sample data
PCM-LEN     ( buf -- frames )    \ frame count
PCM-RATE    ( buf -- hz )        \ sample rate
PCM-BITS    ( buf -- n )         \ bits per sample (8, 16, 32)
PCM-CHANS   ( buf -- n )        \ channel count
PCM-FLAGS   ( buf -- flags )     \ flag word
PCM-OFFSET  ( buf -- n )        \ cursor position (frame index)
PCM-PEAK    ( buf -- n )        \ peak absolute value seen
PCM-USER    ( buf -- x )        \ application payload
```

---

## Computed Properties

### PCM-FRAME-BYTES

```forth
PCM-FRAME-BYTES  ( buf -- n )
```

Bytes per frame: `(bits / 8) × channels`.

```forth
\ 16-bit stereo → 4 bytes per frame
\ 8-bit mono    → 1 byte per frame
\ 32-bit 5.1    → 24 bytes per frame
```

### PCM-DATA-BYTES

```forth
PCM-DATA-BYTES  ( buf -- n )
```

Total sample data size in bytes: `frames × frame-bytes`.

### PCM-DURATION-MS

```forth
PCM-DURATION-MS  ( buf -- ms )
```

Buffer duration in milliseconds: `frames × 1000 / rate`.

```forth
one-sec-stereo PCM-DURATION-MS .   \ → 1000
```

---

## Sample Access

### PCM-SAMPLE!

```forth
PCM-SAMPLE!  ( value frame chan buf -- )
```

Write one sample at the given frame and channel index.
Automatically dispatches to `C!` (8-bit), `W!` (16-bit), or
`L!` (32-bit) based on the buffer's bit depth.

```forth
\ Write 1000 to frame 0, channel 0
1000 0 0 my-buf PCM-SAMPLE!

\ Write -500 to frame 42, channel 1 (right)
-500 42 1 stereo-buf PCM-SAMPLE!
```

### PCM-SAMPLE@

```forth
PCM-SAMPLE@  ( frame chan buf -- value )
```

Read one sample.  Returns the raw stored value (unsigned for
8-bit, signed for 16/32-bit after sign extension by the caller
if needed).

```forth
0 0 my-buf PCM-SAMPLE@ .   \ read frame 0, channel 0
```

### PCM-FRAME! / PCM-FRAME@

```forth
PCM-FRAME!  ( value frame buf -- )
PCM-FRAME@  ( frame buf -- value )
```

Mono shortcuts — read/write channel 0.  Equivalent to calling
`PCM-SAMPLE!` / `PCM-SAMPLE@` with `chan = 0`.

```forth
440 100 mono-buf PCM-FRAME!
100 mono-buf PCM-FRAME@ .    \ → 440
```

---

## Bulk Operations

### PCM-CLEAR

```forth
PCM-CLEAR  ( buf -- )
```

Zero all sample data (silence).  Uses `0 FILL` across the entire
data area.

### PCM-FILL

```forth
PCM-FILL  ( value buf -- )
```

Write `value` to every sample slot (every channel of every frame).
Dispatches per-sample based on bit depth.

```forth
128 my-8bit-buf PCM-FILL    \ 8-bit center (silence for unsigned)
0 my-16bit-buf PCM-FILL      \ 16-bit silence
```

### PCM-COPY

```forth
PCM-COPY  ( src dst -- )
```

Copy sample data from `src` to `dst`.  Copies
`MIN(src-data-bytes, dst-data-bytes)` bytes via `CMOVE`.
Format compatibility is the caller's responsibility.

```forth
original copy PCM-COPY
```

---

## Buffer Manipulation

### PCM-SLICE

```forth
PCM-SLICE  ( start end buf -- buf' )
```

Create a sub-buffer view into the original data.  The returned
descriptor does **not** own the data — it shares the parent's
sample memory.  Start and end are frame indices, clamped to valid
range.

Writing through the slice modifies the original buffer's samples.

```forth
100 200 my-buf PCM-SLICE CONSTANT segment
\ segment has 100 frames, pointing into my-buf's data
segment PCM-FREE              \ frees descriptor only
```

### PCM-CLONE

```forth
PCM-CLONE  ( buf -- buf' )
```

Deep copy — allocates a new buffer with identical format and data.
Copies offset, peak, and user fields.  The clone owns its data.

```forth
my-buf PCM-CLONE CONSTANT backup
```

### PCM-REVERSE

```forth
PCM-REVERSE  ( buf -- )
```

Reverse all frames in place.  Multi-channel aware: swaps entire
frames (all channels together), not individual samples.

```forth
my-buf PCM-REVERSE    \ [s0 s1 s2 s3] → [s3 s2 s1 s0]
```

---

## Time Conversion

### PCM-MS>FRAMES

```forth
PCM-MS>FRAMES  ( ms buf -- n )
```

Convert milliseconds to frame count: `ms × rate / 1000`.

```forth
500 my-44k-buf PCM-MS>FRAMES .   \ → 22050
```

### PCM-FRAMES>MS

```forth
PCM-FRAMES>MS  ( n buf -- ms )
```

Convert frame count to milliseconds: `n × 1000 / rate`.

```forth
44100 my-44k-buf PCM-FRAMES>MS .  \ → 1000
```

---

## Resampling & Channel Mixing

### PCM-RESAMPLE

```forth
PCM-RESAMPLE  ( new-rate buf -- buf' )
```

Nearest-neighbor resample to a new sample rate.  Allocates a new
buffer with the target rate, same bit depth and channel count.
New frame count = `src-len × new-rate / src-rate`.

```forth
22050 my-44k-buf PCM-RESAMPLE CONSTANT downsampled
\ Half the sample rate, half the frames
```

### PCM-TO-MONO

```forth
PCM-TO-MONO  ( buf -- buf' )
```

Mix down to mono by averaging all channels per frame.  Allocates
a new single-channel buffer.  If the source is already mono,
returns a clone.

```forth
stereo-buf PCM-TO-MONO CONSTANT mono-mix
```

---

## Analysis & Normalization

### PCM-SCAN-PEAK

```forth
PCM-SCAN-PEAK  ( buf -- peak )
```

Scan all samples, compute the peak absolute value, store it in the
descriptor's peak field, and return it.  For 8-bit unsigned samples,
values are centered around 128 before computing absolute value.
For 16/32-bit samples, sign extension is applied.

```forth
my-buf PCM-SCAN-PEAK .     \ → 30000
my-buf PCM-PEAK .           \ → 30000 (also stored)
```

### PCM-NORMALIZE

```forth
PCM-NORMALIZE  ( target buf -- )
```

Scale all samples so the peak equals `target`.  Each sample is
multiplied by `target / current-peak` using integer arithmetic.
No-op if the current peak is 0 (silent buffer).

Internally calls `PCM-SCAN-PEAK` to find the current peak, then
applies per-sample scaling with the appropriate bit-width
read/write operations.

```forth
32767 my-16bit-buf PCM-NORMALIZE   \ maximize 16-bit range
127 my-8bit-buf PCM-NORMALIZE       \ maximize 8-bit range
```

---

## Internals

| Word | Purpose |
|---|---|
| `_PCM-SAMPLE-ADDR` `( frame chan buf -- addr )` | Compute byte address: `data + (frame × channels + chan) × (bits/8)`. |
| `_PCM-VALID-BITS?` `( bits -- flag )` | Returns TRUE if bits is 8, 16, or 32. |
| `P.DATA` ... `P.USER` | Field accessor words returning field addresses at offsets +0 through +64. |
| `_PCM-TMP`, `_PCM-PTR`, `_PCM-CNT`, ... | Scratch `VARIABLE`s used by all operations. |
| `_PCM-SA-BUF` | Saved buf for `_PCM-SAMPLE-ADDR` computation. |
| `_PCM-RW-BUF` | Saved buf for `PCM-SAMPLE!` / `PCM-SAMPLE@`. |
| `_PCM-NORM-TGT` | Dedicated variable for normalize target (avoids clobbering by `PCM-SCAN-PEAK`). |
| `_PCM-REV-LO`, `_PCM-REV-HI`, `_PCM-REV-TMP` | Scratch for `PCM-REVERSE` frame swaps. |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `PCM-ALLOC` | `( frames rate bits chans -- buf )` | Allocate PCM buffer (zeroed) |
| `PCM-ALLOC-MS` | `( ms rate bits chans -- buf )` | Allocate by duration (ms) |
| `PCM-CREATE-FROM` | `( addr frames rate bits chans -- buf )` | Wrap existing data |
| `PCM-FREE` | `( buf -- )` | Free buffer (and data if owned) |
| `PCM-DATA` | `( buf -- addr )` | Sample data pointer |
| `PCM-LEN` | `( buf -- frames )` | Frame count |
| `PCM-RATE` | `( buf -- hz )` | Sample rate |
| `PCM-BITS` | `( buf -- n )` | Bits per sample |
| `PCM-CHANS` | `( buf -- n )` | Channel count |
| `PCM-FLAGS` | `( buf -- flags )` | Flags |
| `PCM-OFFSET` | `( buf -- n )` | Cursor position |
| `PCM-PEAK` | `( buf -- n )` | Peak value |
| `PCM-USER` | `( buf -- x )` | User payload |
| `PCM-FRAME-BYTES` | `( buf -- n )` | Bytes per frame |
| `PCM-DATA-BYTES` | `( buf -- n )` | Total data bytes |
| `PCM-DURATION-MS` | `( buf -- ms )` | Duration in ms |
| `PCM-SAMPLE!` | `( val frame chan buf -- )` | Write one sample |
| `PCM-SAMPLE@` | `( frame chan buf -- val )` | Read one sample |
| `PCM-FRAME!` | `( val frame buf -- )` | Write mono sample (chan 0) |
| `PCM-FRAME@` | `( frame buf -- val )` | Read mono sample (chan 0) |
| `PCM-CLEAR` | `( buf -- )` | Zero all samples |
| `PCM-FILL` | `( val buf -- )` | Fill with constant |
| `PCM-COPY` | `( src dst -- )` | Copy sample data |
| `PCM-SLICE` | `( start end buf -- buf' )` | Sub-buffer view (shared data) |
| `PCM-CLONE` | `( buf -- buf' )` | Deep copy |
| `PCM-REVERSE` | `( buf -- )` | Reverse frames in place |
| `PCM-MS>FRAMES` | `( ms buf -- n )` | Milliseconds to frames |
| `PCM-FRAMES>MS` | `( n buf -- ms )` | Frames to milliseconds |
| `PCM-RESAMPLE` | `( new-rate buf -- buf' )` | Nearest-neighbor resample |
| `PCM-TO-MONO` | `( buf -- buf' )` | Mix down to mono |
| `PCM-SCAN-PEAK` | `( buf -- peak )` | Scan and store peak |
| `PCM-NORMALIZE` | `( target buf -- )` | Scale to target peak |

### Constants

| Name | Value | Meaning |
|---|---|---|
| `PCM-DESC-SIZE` | 80 | Bytes per PCM descriptor |
| `_PCM-F-OWNS-BUF` | 1 | Buffer owns its sample data |
| `_PCM-F-XMEM-BUF` | 2 | Sample data is in XMEM |

---

## Cookbook

### Generate a 1-second 440 Hz square wave

```forth
44100 44100 16 1 PCM-ALLOC CONSTANT tone
44100 0 DO
    I 44100 440 */ 2 MOD IF 10000 ELSE -10000 THEN
    I tone PCM-FRAME!
LOOP
```

### Record and trim silence

```forth
\ Assume raw-buf has audio with leading silence
0 raw-buf PCM-LEN raw-buf PCM-SLICE CONSTANT trimmed
\ Find first non-zero frame, then re-slice
```

### Downmix stereo file to mono and normalize

```forth
stereo-buf PCM-TO-MONO CONSTANT mono
32000 mono PCM-NORMALIZE
```

### Splice two buffers

```forth
\ Clone buf-a, then copy buf-b data starting after buf-a's frames
buf-a PCM-LEN buf-b PCM-LEN + buf-a PCM-RATE buf-a PCM-BITS 1
PCM-ALLOC CONSTANT joined

buf-a PCM-DATA  joined PCM-DATA  buf-a PCM-DATA-BYTES CMOVE
buf-b PCM-DATA  joined PCM-DATA buf-a PCM-DATA-BYTES +
buf-b PCM-DATA-BYTES CMOVE
```

### Reverse echo effect

```forth
my-buf PCM-CLONE CONSTANT echo
echo PCM-REVERSE
\ Mix echo into original at reduced volume (manual loop)
```
