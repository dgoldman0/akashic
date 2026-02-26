# akashic-bmp — BMP Image Encoder for KDOS / Megapad-64

Encodes a surface (RGBA8888) as a Windows BMP file — 32-bit BGRA,
uncompressed, bottom-to-top rows.  The simplest raster export path.

```forth
REQUIRE bmp.f
```

`PROVIDED akashic-bmp` — safe to include multiple times.
Automatically requires `surface.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Public API](#public-api)
- [BMP Format Details](#bmp-format-details)
- [Internal Words](#internal-words)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Encode-only** | Produces BMP output from a surface.  No decoder — BMP is used as a simple export format. |
| **32-bit BGRA** | Always writes 32 bits per pixel (BI_RGB, no compression).  Row stride is naturally 4-byte aligned. |
| **Bottom-to-top** | Rows are written bottom-to-top per the BMP spec (positive height in header). |
| **No allocation** | Writes directly into a caller-supplied buffer.  Returns 0 if the buffer is too small. |
| **Prefix convention** | Public: `BMP-`.  Internal: `_BMP-`. |

---

## Dependencies

```
bmp.f
 └── surface.f
      └── color.f → fp16.f, fp16-ext.f, exp.f
```

---

## Public API

### `BMP-FILE-SIZE`

```forth
BMP-FILE-SIZE  ( w h -- bytes )
```

Computes the exact number of bytes a BMP file for a `w × h` image
will occupy.  Equal to `54 + w * h * 4` (14-byte file header +
40-byte DIB header + pixel data).

### `BMP-ENCODE`

```forth
BMP-ENCODE  ( surf buf max -- len | 0 )
```

Encodes the surface `surf` as a 32-bit BMP into `buf`.

- **surf** — surface pointer (from `SURF-CREATE`)
- **buf** — destination buffer address
- **max** — maximum bytes available in `buf`
- Returns the number of bytes written, or **0** if `max` is less
  than `BMP-FILE-SIZE` for the surface dimensions.

The entire surface is encoded.  Clipping is not applied — all pixels
from `(0,0)` to `(w−1, h−1)` are written.

---

## BMP Format Details

### File Header (14 bytes)

| Offset | Size | Field | Value |
|--------|------|-------|-------|
| 0 | 2 | Signature | `"BM"` (0x42, 0x4D) |
| 2 | 4 | File size | `54 + w*h*4` |
| 6 | 2 | Reserved1 | 0 |
| 8 | 2 | Reserved2 | 0 |
| 10 | 4 | Pixel data offset | 54 |

### DIB Header — BITMAPINFOHEADER (40 bytes)

| Offset | Size | Field | Value |
|--------|------|-------|-------|
| 14 | 4 | Header size | 40 |
| 18 | 4 | Width | image width |
| 22 | 4 | Height | image height (positive = bottom-up) |
| 26 | 2 | Planes | 1 |
| 28 | 2 | Bits per pixel | 32 |
| 30 | 4 | Compression | 0 (BI_RGB) |
| 34 | 4 | Image size | `w*h*4` |
| 38 | 4 | X pixels/meter | 2835 (~72 DPI) |
| 42 | 4 | Y pixels/meter | 2835 |
| 46 | 4 | Colors in palette | 0 |
| 50 | 4 | Important colors | 0 |

### Pixel Data

Starting at offset 54, rows are stored **bottom-to-top**.  Each
pixel is 4 bytes in **BGRA** order (blue, green, red, alpha).

The surface pixel format is `R[31:24] G[23:16] B[15:8] A[7:0]`.
The encoder swaps to BMP byte order: `B, G, R, A`.

---

## Internal Words

| Word | Stack | Purpose |
|------|-------|---------|
| `_BMP-B!` | `( byte -- )` | Write one byte, advance position |
| `_BMP-W!` | `( u16 -- )` | Write LE 16-bit value |
| `_BMP-D!` | `( u32 -- )` | Write LE 32-bit value |
| `_BMP-WRITE-HDR` | `( -- )` | Write 54-byte BMP header |
| `_BMP-SWAP-PIXEL` | `( rgba -- )` | Convert RGBA → BGRA bytes |
| `_BMP-WRITE-ROW` | `( row -- )` | Write one row of pixels |
| `_BMP-WRITE-PIXELS` | `( -- )` | Write all rows bottom-to-top |

---

## Quick Reference

```
BMP-FILE-SIZE   ( w h -- bytes )        Exact output size
BMP-ENCODE      ( surf buf max -- n|0 ) Encode surface → BMP
BMP-HDR-SIZE    --  54                  Header size constant
BMP-BPP-BYTES   --   4                  Bytes per pixel constant
```

---

## Cookbook

### Encode a surface to a buffer

```forth
\ Create a 100×50 red surface
100 50 SURF-CREATE CONSTANT my-surf
my-surf 0xFF0000FF SURF-CLEAR

\ Allocate output buffer
100 50 BMP-FILE-SIZE CONSTANT bmp-size
bmp-size ALLOCATE DROP CONSTANT bmp-buf

\ Encode
my-surf bmp-buf bmp-size BMP-ENCODE  ( -- len )
\ len = bmp-size on success, 0 on failure
```

### Check file size before encoding

```forth
: ENCODE-SAFE  ( surf buf max -- len | 0 )
    >R >R DUP SURF-W OVER SURF-H
    BMP-FILE-SIZE              ( surf needed )
    R> R> ROT                  ( surf buf max needed )
    2DUP < IF  2DROP 2DROP 0 EXIT  THEN
    DROP                       ( surf buf max )
    BMP-ENCODE
;
```
