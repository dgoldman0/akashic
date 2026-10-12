# akashic-qoi — QOI Image Codec for KDOS / Megapad-64

Encoder and resumable decoder for the QOI ("Quite OK Image") lossless
image format.  Better compression than BMP, much simpler than PNG.  Both
are single-pass with a 64-entry hash table.  The decoder works a chunk of
the file at a time and hands back one row at a time, so a caller never
needs the whole file or the whole picture in memory.

```forth
REQUIRE qoi.f          \ the header and the decoder
REQUIRE qoi-rows.f     \ the encoder, a row at a time, which also loads qoi.f
REQUIRE qoi-encode.f   \ a whole surface encoded, which loads qoi-rows.f
```

`qoi.f` provides `akashic-qoi` and depends on nothing, so a viewer that only
decodes loads no encoder.  `qoi-rows.f` provides `akashic-qoi-rows` and
requires `qoi.f`, so a decoder of another format that writes QOI a row at a
time never loads the surface renderer.  `qoi-encode.f` provides
`akashic-qoi-encode` and requires `qoi-rows.f` and `surface.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Public API](#public-api)
- [QOI Format Overview](#qoi-format-overview)
- [Chunk Types](#chunk-types)
- [Internal Words](#internal-words)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Encode + decode** | Surfaces encode losslessly; any QOI file decodes. |
| **Single-pass** | Both encoder and decoder iterate pixels once, left-to-right, top-to-bottom. |
| **No allocation** | The encoder writes into a caller buffer and keeps its state, index included, in a caller-owned record of `QOI-ENC-SIZE` bytes.  The decoder keeps all of its state, index included, in a caller-owned record of `QOI-DEC-SIZE` bytes. |
| **Resumable decode** | `QOI-DEC-FEED` takes whatever bytes the caller has.  An operation split between two chunks waits in the record. |
| **Rows in wire order** | Decoded rows are R, G, B, A bytes, the order of the rich terminal's RGBA8 resources and of `QOI-HEADER` callers that scale, hash or send rows.  Three-channel files decode with alpha 255. |
| **Clean failure** | A short file never reports done, a wrong end marker reports bad, and a bad header is refused before decoding starts. |
| **Channels** | `QOI-ENCODE` writes RGBA (channels=4, colorspace=sRGB); a caller encoding by rows names 3 or 4 in its header. |
| **Prefix convention** | Public: `QOI-`.  Internal: `_QOI-` (encoder), `_QD-` (decoder). |

---

## Dependencies

```
qoi.f              (no dependencies)
qoi-rows.f
 └── qoi.f
qoi-encode.f
 ├── qoi-rows.f
 └── surface.f
      └── color.f → fp16.f, fp16-ext.f, exp.f
```

---

## Public API

### `QOI-FILE-SIZE`

```forth
QOI-FILE-SIZE  ( w h -- max-bytes )    \ qoi-encode.f
```

Computes the **worst-case** output size for encoding a `w × h`
image.  Equal to `w * h * 5 + 14 + 8` (5 bytes/pixel worst case +
14-byte header + 8-byte end marker).

Actual encoded output is typically much smaller due to run-length
and delta compression.

### `QOI-ENCODE`

```forth
QOI-ENCODE  ( surf buf max -- len | 0 )    \ qoi-encode.f
```

Encodes the surface `surf` as QOI into `buf`.

- **surf** — surface pointer (from `SURF-CREATE`)
- **buf** — destination buffer address
- **max** — maximum bytes available in `buf`
- Returns the actual number of bytes written, or **0** if `max` is
  less than `QOI-FILE-SIZE` for the surface dimensions.

Pixels are read left-to-right, top-to-bottom from the surface
buffer.  It is qoi-rows.f's encoder below, run over the whole surface.

### A picture a row at a time

```forth
QOI-ENC-SIZE    ( -- bytes )                   \ qoi-rows.f
QOI-ENC-HEADER  ( w h channels dst -- dst' )
QOI-ENC-START   ( enc -- )
QOI-ENC-PIXELS  ( src n dst enc -- dst' )
QOI-ENC-ROOM    ( n -- bytes )
QOI-ENC-END     ( dst enc -- dst' )
```

A caller that makes its pixels a row at a time, such as a decoder of
another format, encodes them as it goes instead of holding a whole
surface.  `QOI-ENC-HEADER` writes the 14-byte header for a `w × h`
picture of 3 or 4 channels, sRGB.  The encoder's state is a record the
caller owns, `QOI-ENC-SIZE` bytes, cell-aligned: the previous pixel, the
run and the index.  `QOI-ENC-START` starts it: the pixel before the
first opaque black, no run, the index empty.  `QOI-ENC-PIXELS` encodes
`n` pixels at `src`, each 32 bits with red in the high byte and alpha in
the low, as a surface holds them, writing at most `QOI-ENC-ROOM` bytes:
a run may wait for the next call.  `QOI-ENC-END` writes the run that
waits and the end marker, at most nine bytes.  Pictures may take turns,
each with its own record; one call runs at a time.

### `QOI-HEADER`

```forth
QOI-HEADER  ( a u -- w h channels colorspace true | false )
```

Reads the 14-byte header that starts a QOI file.  False unless `u` is at
least 14, the magic is `"qoif"`, both dimensions are positive, channels is
3 or 4, and the colorspace is 0 (sRGB) or 1 (linear).

### `QOI-DEC-SIZE`, `QOI-DEC-INIT`

```forth
QOI-DEC-SIZE  ( -- bytes )
QOI-DEC-INIT  ( w h dec -- )
```

A decoder is a caller-owned record of `QOI-DEC-SIZE` bytes, eight-byte
aligned.  `QOI-DEC-INIT` starts decoding a `w` by `h` picture whose header
the caller has read with `QOI-HEADER`; the next byte fed is the first byte
after the header.

### `QOI-DEC-FEED`

```forth
QOI-DEC-FEED  ( src-a src-u row-a dec -- used status )
```

Decodes from the `src-u` bytes at `src-a` until the next row is complete,
the input runs out, or the file ends, and returns how many input bytes it
used.  `row-a` holds at least `w * 4` bytes and keeps a partly decoded row
between feeds, so the caller passes the same row buffer until a row is
reported.  The status is one of:

| Status | Meaning |
|---|---|
| `QOI-S-MORE` | All of the input is used and the row is unfinished.  Feed more. |
| `QOI-S-ROW` | `row-a` holds the next complete row.  `used` may be less than `src-u`; feed the rest after using the row. |
| `QOI-S-DONE` | Every pixel and the end marker are read.  Later feeds report `QOI-S-DONE` and use nothing. |
| `QOI-S-BAD` | The end marker is wrong.  Later feeds report `QOI-S-BAD`. |

Every byte of a QOI pixel stream is a valid operation, so damage inside
the pixels cannot be detected; a file cut short ends with `QOI-S-MORE` and
no input left, and a wrong end marker ends with `QOI-S-BAD`.  A run longer
than the rest of the picture ends with it.

### `QOI-DEC-ROWS@`

```forth
QOI-DEC-ROWS@  ( dec -- rows )
```

How many rows have been reported so far.

---

## QOI Format Overview

A QOI file consists of:

1. **14-byte header** (big-endian)
2. **Data chunks** (variable length)
3. **8-byte end marker** (`00 00 00 00 00 00 00 01`)

### Header

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | Magic | `"qoif"` = `0x716F6966` |
| 4 | 4 | Width | Image width (BE) |
| 8 | 4 | Height | Image height (BE) |
| 12 | 1 | Channels | 3=RGB, 4=RGBA |
| 13 | 1 | Colorspace | 0=sRGB, 1=linear |

### Color Hash

Both encoder and decoder maintain a running array of 64 previously
seen pixel values.  The hash function is:

$$\text{index} = (r \times 3 + g \times 5 + b \times 7 + a \times 11) \bmod 64$$

### Initial State

- Previous pixel: `(r=0, g=0, b=0, a=255)`
- Hash table: all zeros
- Run counter: 0

---

## Chunk Types

### QOI_OP_INDEX — `00xxxxxx`

2-bit tag `00`, 6-bit index into the hash table (0–63).  Emitted
when the current pixel matches a previously seen color at that
hash position.

### QOI_OP_DIFF — `01drdgdb`

2-bit tag `01`, then 2 bits each for red, green, blue deltas.
Each delta is biased by +2, encoding differences in the range
−2 to +1.  Alpha must be unchanged.

### QOI_OP_LUMA — `10gggggg` `rrrrbbbb`

2-bit tag `10`, 6-bit green delta (bias +32, range −32 to +31).
Second byte: 4-bit red-minus-green delta (bias +8, range −8 to +7)
in the high nibble, 4-bit blue-minus-green delta in the low nibble.
Alpha must be unchanged.

### QOI_OP_RUN — `11rrrrrr`

2-bit tag `11`, 6-bit run length minus 1 (range 1–62).  Repeats
the previous pixel.  Values 63 and 64 are reserved for the RGB
and RGBA tags.

### QOI_OP_RGB — `11111110` `rr` `gg` `bb`

8-bit tag `0xFE` followed by 3 literal color bytes.  Alpha stays
the same as the previous pixel.

### QOI_OP_RGBA — `11111111` `rr` `gg` `bb` `aa`

8-bit tag `0xFF` followed by 4 literal color bytes.  Used when
alpha changes.

---

## Internal Words

### Encoder

| Word | Stack | Purpose |
|------|-------|---------|
| `_QOI-B!` | `( byte -- )` | Write byte to output, advance position |
| `_QOI-BE32!` | `( u32 -- )` | Write big-endian 32-bit value |
| `_QOI-UNPACK` | `( rgba -- r g b a )` | Extract channels from packed pixel |
| `_QOI-PACK` | `( r g b a -- rgba )` | Pack channels into pixel |
| `_QOI-HASH-IDX` | `( r g b a -- idx )` | Compute hash table index |
| `_QOI-HASH-SET` | `( rgba -- )` | Store pixel in hash table |
| `_QOI-HASH-GET` | `( idx -- rgba )` | Retrieve pixel from hash table |
| `_QOI-HASH-CLEAR` | `( -- )` | Zero all 64 hash entries |
| `_QOI-SBYTE` | `( n -- signed )` | Mask to 8 bits, sign-extend |
| `_QOI-WRITE-END` | `( -- )` | Write 8-byte end marker |
| `_QOI-FLUSH-RUN` | `( -- )` | Emit pending run chunk |
| `_QOI-ENCODE-PIXEL` | `( -- )` | Encode one pixel from source |

### Decoder

A decoded pixel is a little-endian u32 whose bytes are R, G, B, A, so
`L!` writes it in row order.  One feed loads the record's hot fields into
module variables and stores them back when it returns.

| Word | Stack | Purpose |
|------|-------|---------|
| `_QOI-BE32@` | `( a -- u32 )` | Read a big-endian 32-bit header field |
| `_QD-TAKE` | `( -- complete? )` | Gather the next whole operation into the record |
| `_QD-APPLY` | `( -- )` | Apply the gathered operation and record the pixel in the index |
| `_QD-ADD` | `( px delta shift -- px' )` | Add a delta to one channel, wrapping at 256 |
| `_QD-SLOT` | `( px -- addr )` | The index entry a pixel hashes to |
| `_QD-PUT` | `( -- )` | Write the current pixel into the row |
| `_QD-END-MARKER` | `( -- used status )` | Match the eight-byte end marker |

---

## Quick Reference

```
QOI-FILE-SIZE   ( w h -- max )          Worst-case output size
QOI-ENCODE      ( surf buf max -- n|0 ) Encode surface → QOI
QOI-ENC-SIZE    ( -- bytes )            An encoder's record
QOI-ENC-HEADER  ( w h ch dst -- dst' )  Header of a picture encoded by rows
QOI-ENC-START   ( enc -- )              Start a picture's state
QOI-ENC-PIXELS  ( src n dst enc -- dst' )  N more pixels
QOI-ENC-ROOM    ( n -- bytes )          The most N pixels write
QOI-ENC-END     ( dst enc -- dst' )     Last run and end marker
QOI-HEADER      ( a u -- w h ch cs -1 | 0 )  Read and check the header
QOI-DEC-SIZE    ( -- bytes )            Decoder record size
QOI-DEC-INIT    ( w h dec -- )          Start after the header
QOI-DEC-FEED    ( src u row dec -- used status )  Decode toward the next row
QOI-DEC-ROWS@   ( dec -- rows )         Rows reported so far
QOI-S-MORE QOI-S-ROW QOI-S-DONE QOI-S-BAD  Feed statuses
QOI-HDR-SIZE    --  14                  Header size constant
QOI-END-SIZE    --   8                  End marker size constant
```

---

## Cookbook

### Encode a surface

```forth
REQUIRE qoi-encode.f
100 50 SURF-CREATE CONSTANT my-surf
my-surf 0xFF0000FF SURF-CLEAR

\ Allocate worst-case buffer
100 50 QOI-FILE-SIZE CONSTANT qoi-max
qoi-max ALLOCATE DROP CONSTANT qoi-buf

\ Encode — returns actual byte count
my-surf qoi-buf qoi-max QOI-ENCODE  ( -- len )
\ len << qoi-max for solid color (run compression)
```

### Decode a file a chunk at a time

```forth
CREATE dec QOI-DEC-SIZE ALLOT
VARIABLE src  VARIABLE left  VARIABLE row
\ file-a file-u: the file's bytes (a caller reading a file in pieces
\ feeds each piece it reads the same way)
file-a file-u QOI-HEADER 0= ABORT" not a QOI file"
2DROP                                  ( w h )
OVER 4 * ALLOCATE THROW row !          \ one row of RGBA bytes
dec QOI-DEC-INIT
file-a 14 + src !  file-u 14 - left !
BEGIN
    src @ left @ row @ dec QOI-DEC-FEED    ( used status )
    SWAP DUP src +! NEGATE left +!
    DUP QOI-S-ROW = IF ( use the row at row @ ) THEN
    DUP QOI-S-DONE = OVER QOI-S-BAD = OR
    SWAP QOI-S-MORE = left @ 0= AND OR    \ MORE with nothing left: short file
UNTIL
```

The bytes a `QOI-S-ROW` feed did not use are fed again once the row is
used.

### Check compression ratio

```forth
my-surf qoi-buf qoi-max QOI-ENCODE CONSTANT qoi-len
100 50 BMP-FILE-SIZE CONSTANT bmp-size
." QOI: " qoi-len . ." bytes vs BMP: " bmp-size . ." bytes" CR
```
