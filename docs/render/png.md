# akashic-png — PNG decoder

A resumable decoder for PNG files. Like the [QOI decoder](qoi.md), it reads
the file a chunk at a time, as the caller has it, and hands back one row at
a time as R, G, B, A bytes, so a caller never needs the whole file or the
whole picture in memory. It allocates nothing.

```forth
REQUIRE png.f
```

`PROVIDED akashic-png`. It requires [`utils/inflate.f`](../utils/inflate.md)
and `math/crc.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PNG-HDR-SIZE` | `( -- 33 )` | The bytes `PNG-HEADER` reads: the signature and the IHDR chunk. |
| `PNG-HEADER` | `( a u -- w h status )` | A file's size, and whether this module decodes it. |
| `PNG-DEC-SIZE` | `( w -- bytes )` | The decoder for pictures `w` pixels wide, its window and rows included. |
| `PNG-DEC-INIT` | `( w dec -- )` | Start decoding a picture `w` pixels wide. |
| `PNG-DEC-FEED` | `( src-a src-u row-a dec -- used status )` | Decode the file's next bytes, a row at most. |
| `PNG-DEC-ROWS@` | `( dec -- rows )` | Rows handed back so far. |
| `PNG-UNFILTER` | `( filter row prev n bpp -- ok? )` | Undo one row's filter in place. |

`PNG-HEADER` answers `PNG-H-OK` for a file this module decodes,
`PNG-H-NOT` for no PNG file, `PNG-H-DAMAGED` for a wrong or short IHDR, and
`PNG-H-UNSUPPORTED` for an interlaced file.

The decoder is `PNG-DEC-SIZE` bytes, cell-aligned: its record, the
inflater's 32 KB window, and the two rows a filter reads, sized for eight
bytes a pixel. The caller feeds the file from its first byte; the decoder
reads the signature and IHDR again and checks the width is the one it was
started with.

## Statuses

The statuses are the QOI decoder's, so a picture's loop feeds either:

| Status | Meaning |
|---|---|
| `PNG-S-MORE` | All of the input is used and the row is unfinished. |
| `PNG-S-ROW` | A row is in the caller's row buffer, `w * 4` bytes. The caller feeds the rest of its input again. |
| `PNG-S-DONE` | The file ended, after its last row, with IEND. |
| `PNG-S-BAD` | The file is damaged. |

DONE and BAD stay. A file cut short never reports done: the caller sees MORE
with no input left.

## What it reads

- Every chunk's CRC is checked.
- PLTE gives up to 256 colours, and tRNS their alpha, or for grey and RGB
  pictures the one colour that is transparent.
- The image data is inflated as one zlib stream across its IDAT chunks,
  which must follow one another. Data after the stream's end is skipped.
- Each row's filter is undone against the row before.
- Every colour type and bit depth PNG allows becomes eight bits a channel:
  sixteen-bit samples by their high byte, and one, two and four-bit grey
  scaled to the full range.
- An unknown chunk is skipped unless its name marks it critical.

A wrong CRC, an unknown critical chunk, a palette index past the palette,
too little image data or too much, chunks out of order, and a filter PNG
does not define are each damage. Colour profiles and gamma are ignored.

## The filters alone

`PNG-UNFILTER` undoes a filter on `n` bytes at `row` in place, with the
row before at `prev`, all zeros for the first row, and `bpp` bytes a
whole pixel, at least one. A PDF Flate stream's predictor uses the same
five filters.
