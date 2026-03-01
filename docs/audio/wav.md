# akashic-audio-wav — WAV/RIFF Encoder & Decoder for KDOS / Megapad-64

Read and write Microsoft WAV files (RIFF container, PCM payload).
The BMP of audio — simplest useful container format.  In-memory only;
the caller handles file I/O if desired.

```forth
REQUIRE audio/wav.f
```

`PROVIDED akashic-audio-wav`
Dependencies: `fp16-ext.f`, `audio/pcm.f`

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
| **FP16 ↔ PCM** | Internal samples are always FP16 [-1, +1].  WAV encoding converts to the target bit depth; decoding reverses. |
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

### WAV-ENCODE

```forth
WAV-ENCODE  ( buf out-addr max-bytes -- len | 0 )
```

Encode a PCM buffer into WAV format at `out-addr`.  Returns byte count
written, or 0 if `max-bytes` is too small.

- Reads PCM properties (rate, bits, channels, length) from `buf`.
- Writes 44-byte RIFF/WAVE/fmt/data header.
- Converts each FP16 sample to the target bit depth and writes it.

### WAV-DECODE

```forth
WAV-DECODE  ( in-addr in-len -- pcm-buf | 0 )
```

Decode WAV bytes into a new FP16 PCM buffer.  Returns 0 on error
(bad magic, unsupported format).

- Validates RIFF/WAVE/fmt/data header structure.
- Allocates a PCM buffer with the decoded rate, channels, and frame count.
- Output is always 16-bit FP16, regardless of source depth.

### WAV-INFO

```forth
WAV-INFO  ( in-addr in-len -- rate bits chans frames | 0 )
```

Read header fields without loading sample data.  Returns 0 on error.

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
| 8-bit | `sample × 127 + 128` (unsigned, center 128) | 0–255 |
| 16-bit | `sample × 32767` (signed) | −32768–32767 |
| 32-bit | `(sample × 32767) << 16` (signed, 16-bit shifted) | full 32-bit |

Signed clamping uses `<` / `>` (not `MAX`/`MIN`, which are unsigned
in this Forth).

### Decode (raw → FP16)

| Depth | Formula |
|---|---|
| 8-bit | `(u8 − 128) / 127` |
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
WAV-DECODE     ( in-addr in-len -- pcm-buf | 0 )
WAV-INFO       ( in-addr in-len -- rate bits chans frames | 0 )
```

---

## Cookbook

### Encode a PCM buffer to WAV

```forth
: SAVE-WAV  ( pcm-buf -- )
    DUP WAV-FILE-SIZE              \ compute size
    DUP ALLOCATE DROP              \ alloc output buffer
    SWAP 2DUP ROT                  \ ( buf out fsiz )
    WAV-ENCODE                     \ returns len or 0
    DUP 0= IF ." encode failed" CR 2DROP EXIT THEN
    \ … write (out-addr, len) to file …
    DROP FREE ;
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
