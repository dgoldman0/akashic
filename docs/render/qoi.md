# akashic-qoi — QOI Image Codec for KDOS / Megapad-64

Encoder and decoder for the QOI ("Quite OK Image") lossless image
format.  Better compression than BMP, much simpler than PNG.  Both
encode and decode are single-pass with a 64-entry hash table.

```forth
REQUIRE qoi.f
```

`PROVIDED akashic-qoi` — safe to include multiple times.
Automatically requires `surface.f`.

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
| **Encode + decode** | Full codec — surfaces can be serialized and deserialized losslessly. |
| **Single-pass** | Both encoder and decoder iterate pixels once, left-to-right, top-to-bottom. |
| **64-entry hash table** | Runtime-allocated 512-byte table (64 cells).  Freed after each encode/decode call. |
| **4-channel RGBA** | Always encodes/decodes as RGBA (channels=4, colorspace=sRGB). |
| **No allocation for encode** | Writes into a caller-supplied buffer.  Returns 0 if too small. |
| **Decode allocates surface** | `QOI-DECODE` creates a new surface via `SURF-CREATE`. |
| **Prefix convention** | Public: `QOI-`.  Internal: `_QOI-`. |

---

## Dependencies

```
qoi.f
 └── surface.f
      └── color.f → fp16.f, fp16-ext.f, exp.f
```

---

## Public API

### `QOI-FILE-SIZE`

```forth
QOI-FILE-SIZE  ( w h -- max-bytes )
```

Computes the **worst-case** output size for encoding a `w × h`
image.  Equal to `w * h * 5 + 14 + 8` (5 bytes/pixel worst case +
14-byte header + 8-byte end marker).

Actual encoded output is typically much smaller due to run-length
and delta compression.

### `QOI-ENCODE`

```forth
QOI-ENCODE  ( surf buf max -- len | 0 )
```

Encodes the surface `surf` as QOI into `buf`.

- **surf** — surface pointer (from `SURF-CREATE`)
- **buf** — destination buffer address
- **max** — maximum bytes available in `buf`
- Returns the actual number of bytes written, or **0** if `max` is
  less than `QOI-FILE-SIZE` for the surface dimensions.

Pixels are read left-to-right, top-to-bottom from the surface
buffer.

### `QOI-DECODE`

```forth
QOI-DECODE  ( qoi-a qoi-u -- surf | 0 )
```

Decodes QOI data at address `qoi-a` with length `qoi-u` into a
newly allocated surface.

- **qoi-a** — address of QOI data in memory
- **qoi-u** — length in bytes
- Returns a surface pointer on success, or **0** on failure
  (invalid magic, zero dimensions, or data too short).

The caller owns the returned surface and should free it with
`SURF-DESTROY` when done.

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
| `_QOI-WRITE-HDR` | `( -- )` | Write 14-byte QOI header |
| `_QOI-WRITE-END` | `( -- )` | Write 8-byte end marker |
| `_QOI-FLUSH-RUN` | `( -- )` | Emit pending run chunk |
| `_QOI-ENCODE-PIXEL` | `( -- )` | Encode one pixel from source |

### Decoder

| Word | Stack | Purpose |
|------|-------|---------|
| `_QOI-RB` | `( -- byte )` | Read one byte from input |
| `_QOI-RBE32` | `( -- u32 )` | Read big-endian 32-bit from input |

---

## Quick Reference

```
QOI-FILE-SIZE   ( w h -- max )          Worst-case output size
QOI-ENCODE      ( surf buf max -- n|0 ) Encode surface → QOI
QOI-DECODE      ( qoi-a qoi-u -- s|0 ) Decode QOI → surface
QOI-HDR-SIZE    --  14                  Header size constant
QOI-END-SIZE    --   8                  End marker size constant
```

---

## Cookbook

### Encode a surface

```forth
100 50 SURF-CREATE CONSTANT my-surf
my-surf 0xFF0000FF SURF-CLEAR

\ Allocate worst-case buffer
100 50 QOI-FILE-SIZE CONSTANT qoi-max
qoi-max ALLOCATE DROP CONSTANT qoi-buf

\ Encode — returns actual byte count
my-surf qoi-buf qoi-max QOI-ENCODE  ( -- len )
\ len << qoi-max for solid color (run compression)
```

### Roundtrip: encode then decode

```forth
\ Encode
my-surf qoi-buf qoi-max QOI-ENCODE CONSTANT qoi-len

\ Decode into a new surface
qoi-buf qoi-len QOI-DECODE CONSTANT decoded
decoded SURF-W .    \ → 100
decoded SURF-H .    \ → 50
decoded 0 0 SURF-PIXEL@ .   \ → same as original

\ Clean up
decoded SURF-DESTROY
```

### Check compression ratio

```forth
my-surf qoi-buf qoi-max QOI-ENCODE CONSTANT qoi-len
100 50 BMP-FILE-SIZE CONSTANT bmp-size
." QOI: " qoi-len . ." bytes vs BMP: " bmp-size . ." bytes" CR
```
