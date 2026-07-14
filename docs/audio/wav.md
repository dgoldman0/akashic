# akashic-audio-wav — WAV/RIFF Encoder & Decoder for KDOS / Megapad-64

Read and write Microsoft WAV files (RIFF container, PCM payload).
The BMP of audio — simplest useful container format.  In-memory only;
the caller handles file I/O if desired.

```forth
REQUIRE audio/wav.f
```

`PROVIDED akashic-audio-wav`
Dependencies: `fp16-ext.f`, `audio/pcm.f`, `audio/pcm-fp16.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Public API](#public-api)
- [Encoding](#encoding)
- [Decoding](#decoding)
- [Header Inspection](#header-inspection)
- [Bit Depth Mapping](#bit-depth-mapping)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Cursor-based I/O** | Follows the `bmp.f` pattern: `_WAV-BUF`/`_WAV-POS` cursor with `_WAV-B!`/`_WAV-W!`/`_WAV-D!` writers. |
| **FP16 ↔ PCM16** | Encoding accepts the Akashic 16-bit-storage FP16 convention and emits signed 16-bit WAV PCM. Decoding accepts integer PCM8/16/32 and emits FP16 storage. |
| **In-memory** | No file I/O — `WAV-ENCODE`/`WAV-DECODE` work on byte buffers.  Pair with `FWRITE`/`FREAD` if needed. |
| **Variable-based state** | Scratch via `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `WAV-`.  Internal: `_WAV-`. |

---

## Public API

### WAV-FILE-SIZE

```forth
WAV-FILE-SIZE  ( buf -- bytes )
```

Compute total WAV output size for a PCM buffer (44-byte header + data).
The source must satisfy `PCM-FP16?`; output data is always two bytes per
sample regardless of any external integer-PCM convention. This performs the
same checked field derivation as `WAV-ENCODE`: channels/block alignment must
fit u16, and rate, byte rate, data size, and RIFF payload must fit u32.

### WAV-ENCODE

```forth
WAV-ENCODE  ( buf out-addr max-bytes -- len | 0 )
```

Encode a PCM buffer into WAV format at `out-addr`.  Returns byte count
written, or 0 if `max-bytes` is too small.

- Requires `PCM-FP16?` and at least one sample; invalid source contracts abort.
- Reads rate, channels, and length from `buf`; output depth is fixed at 16 bits.
- Validates every multiplication and WAV field width before writing any byte.
- Writes 44-byte RIFF/WAVE/fmt/data header.
- Converts each FP16 sample with canonical `PCM-FP16>S16` policy and writes it.

`WAV-ENCODE-PCM16` has the same stack effect and behavior. It is provided as
an explicit boundary name when fixed PCM16 output matters to the caller.

### WAV-DECODE

```forth
WAV-DECODE  ( in-addr in-len -- pcm-buf | 0 )
```

Decode WAV bytes into a new FP16 PCM buffer. Returns 0 on malformed input or
an unsupported layout. If output allocation fails, the allocator's nonzero
`ior` is propagated with catchable `THROW`.

- Validates the canonical 44-byte RIFF/WAVE/fmt/data layout, redundant byte
  rate/block-align fields, declared sizes, frame alignment, and input bounds.
- Allocates a PCM buffer with the decoded rate, channels, and frame count.
- Output is always 16-bit FP16, regardless of source depth.

### WAV-INFO

```forth
WAV-INFO  ( in-addr in-len -- rate bits chans frames | 0 )
```

Read header fields without loading sample data. Returns 0 on error. This is a
deliberately bounded canonical-layout parser, not a general RIFF chunk walker;
extended `fmt ` chunks and pre-data metadata chunks are rejected.

---

## Encoding

The encoder writes a standard 44-byte WAV header followed by raw PCM
samples.  The header structure:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `"RIFF"` magic |
| 4 | 4 | file size − 8 |
| 8 | 4 | `"WAVE"` magic |
| 12 | 4 | `"fmt "` magic |
| 16 | 4 | fmt chunk size (16 for PCM) |
| 20 | 2 | format tag (1 = PCM) |
| 22 | 2 | channels |
| 24 | 4 | sample rate |
| 28 | 4 | byte rate |
| 32 | 2 | block align |
| 34 | 2 | bits per sample |
| 36 | 4 | `"data"` magic |
| 40 | 4 | data chunk size |
| 44 | … | sample data |

All multi-byte fields are little-endian.

---

## Decoding

The decoder validates the RIFF/WAVE header, extracts format fields from
the `fmt ` sub-chunk, then reads samples from the `data` sub-chunk.
Each raw sample is converted to FP16 and stored in a newly allocated
PCM buffer.

---

## Bit Depth Mapping

### Encode (FP16 → raw)

| Depth | Formula | Range |
|---|---|---|
| 16-bit | Canonical `PCM-FP16>S16`: exact interior scale 32768, signed clamp, `+1 → 32767`, `-1 → -32768` | −32768–32767 |

NaN maps to silence; infinities and finite out-of-range values saturate.
Signed clamping uses `<` / `>` because KDOS `MAX`/`MIN` are unsigned.

### Decode (raw → FP16)

| Depth | Formula |
|---|---|
| 8-bit | Below center: `(u8 − 128) / 128`; at/above center: `(u8 − 128) / 127`. Thus 0, 128, 255 map exactly to −1, 0, +1. |
| 16-bit | `(s16 / 2) / 16384` — halved first to keep FP16 exponents in safe range |
| 32-bit | `(s32 >> 16) / 2 / 16384` |

---

## Internals

### Cursor Writers (encode)

| Word | Stack | Description |
|---|---|---|
| `_WAV-B!` | `( byte -- )` | Write 1 byte, advance cursor |
| `_WAV-W!` | `( u16 -- )` | Write 16-bit LE, advance 2 |
| `_WAV-D!` | `( u32 -- )` | Write 32-bit LE, advance 4 |

### Cursor Readers (decode)

| Word | Stack | Description |
|---|---|---|
| `_WAV-RB@` | `( -- byte )` | Read 1 byte, advance cursor |
| `_WAV-RW@` | `( -- u16 )` | Read 16-bit LE, advance 2 |
| `_WAV-RD@` | `( -- u32 )` | Read 32-bit LE, advance 4 |

### Scratch Variables

`_WAV-BUF`, `_WAV-POS`, `_WAV-IN`, `_WAV-RPOS`, `_WAV-SRC`,
`_WAV-RATE`, `_WAV-BITS`, `_WAV-CHANS`, `_WAV-FRAMES`, `_WAV-DSIZ`,
`_WAV-FSIZ`.

---

## Quick Reference

```
WAV-HDR-SIZE   ( -- 44 )
WAV-FILE-SIZE  ( buf -- bytes )
WAV-ENCODE     ( buf out-addr max-bytes -- len | 0 )
WAV-ENCODE-PCM16 ( buf out-addr max-bytes -- len | 0 )
WAV-DECODE     ( in-addr in-len -- pcm-buf | 0 )
WAV-INFO       ( in-addr in-len -- rate bits chans frames | 0 )
```

---

## Cookbook

### Encode a PCM buffer to WAV

```forth
: SAVE-WAV  ( pcm-buf -- )
    DUP WAV-FILE-SIZE              ( pcm-buf size )
    DUP ALLOCATE IF                ( pcm-buf size out-addr )
        ." allocation failed" CR
        2DROP DROP EXIT
    THEN
    DUP >R SWAP                    ( pcm-buf out-addr size ) ( R: out-addr )
    WAV-ENCODE                     ( len )
    DUP 0= IF
        DROP ." encode failed" CR
        R> FREE EXIT
    THEN
    R@ SWAP                        ( out-addr len ) ( R: out-addr )
    \ … replace this 2DROP with a writer that consumes (out-addr, len) …
    2DROP
    R> FREE ;
```

### Decode WAV bytes

```forth
: LOAD-WAV  ( addr len -- pcm-buf )
    WAV-DECODE
    DUP 0= IF ." bad WAV file" CR EXIT THEN ;
```

### Inspect WAV header

```forth
: SHOW-WAV  ( addr len -- )
    WAV-INFO DUP 0= IF DROP ." invalid" CR EXIT THEN
    ." frames=" . ." chans=" . ." bits=" . ." rate=" . CR ;
```
