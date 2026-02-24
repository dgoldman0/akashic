# akashic-ttf — TrueType Font Parser for KDOS / Megapad-64

Parses raw TrueType (.ttf) font data in memory.  Reads essential
tables for glyph outline extraction and character-to-glyph mapping.

```forth
REQUIRE ttf.f
```

`PROVIDED akashic-ttf` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Big-Endian Readers](#big-endian-readers)
- [Table Directory](#table-directory)
- [head + maxp](#head--maxp)
- [hhea + hmtx](#hhea--hmtx)
- [loca + glyf](#loca--glyf)
- [Simple Glyph Decoder](#simple-glyph-decoder)
- [cmap (Format 4)](#cmap-format-4)
- [Quick Reference](#quick-reference)
- [Known Limitations](#known-limitations)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Minimum viable subset** | Only tables needed for outline rasterization: head, maxp, hhea, hmtx, loca, glyf, cmap. |
| **Big-endian aware** | TrueType uses big-endian; platform is little-endian.  All reads go through `BE-W@` / `BE-L@` / `BE-SW@`. |
| **In-memory parsing** | Expects the entire TTF file loaded contiguously in RAM.  Set base address with `TTF-BASE!`. |
| **Simple glyphs only** | Composite glyphs (nContours < 0) are silently skipped. |
| **cmap format 4** | Covers BMP (U+0000–U+FFFF).  No format 12 (supplementary planes). |

---

## Big-Endian Readers

| Word | Stack Effect | Description |
|---|---|---|
| `BE-W@` | `( addr -- u16 )` | Read unsigned 16-bit big-endian |
| `BE-L@` | `( addr -- u32 )` | Read unsigned 32-bit big-endian |
| `BE-SW@` | `( addr -- s16 )` | Read signed 16-bit big-endian |
| `BE-SL@` | `( addr -- s32 )` | Read signed 32-bit big-endian |

---

## Table Directory

| Word | Stack Effect | Description |
|---|---|---|
| `TTF-BASE!` | `( addr -- )` | Set base address of loaded TTF data |
| `TTF-BASE@` | `( -- addr )` | Get base address |
| `TTF-NUM-TABLES` | `( -- n )` | Number of tables in font |
| `TTF-FIND-TABLE` | `( tag -- addr len \| 0 0 )` | Find table by 4-byte tag |

Tags are 32-bit integers constructed from 4 ASCII characters:

```forth
S" head" TTF-TAG  \ → 0x68656164
```

---

## head + maxp

| Word | Stack Effect | Description |
|---|---|---|
| `TTF-PARSE-HEAD` | `( -- flag )` | Parse `head` table; sets UPEM, loca format |
| `TTF-PARSE-MAXP` | `( -- flag )` | Parse `maxp` table; sets glyph count |
| `TTF-UPEM` | `( -- n )` | Units per em (typically 1000 or 2048) |
| `TTF-LOCA-FMT` | `( -- n )` | Loca index format (0=short, 1=long) |
| `TTF-NGLYPHS` | `( -- n )` | Total number of glyphs in font |

---

## hhea + hmtx

| Word | Stack Effect | Description |
|---|---|---|
| `TTF-PARSE-HHEA` | `( -- flag )` | Parse `hhea` table; sets metrics |
| `TTF-PARSE-HMTX` | `( -- flag )` | Parse `hmtx` table |
| `TTF-ADVANCE` | `( glyph-id -- width )` | Horizontal advance width |
| `TTF-LSB` | `( glyph-id -- lsb )` | Left side bearing |
| `TTF-ASCENDER` | `( -- n )` | Font ascender (font units) |
| `TTF-DESCENDER` | `( -- n )` | Font descender (font units, negative) |
| `TTF-LINEGAP` | `( -- n )` | Line gap (font units) |

---

## loca + glyf

| Word | Stack Effect | Description |
|---|---|---|
| `TTF-PARSE-LOCA` | `( -- flag )` | Parse `loca` table |
| `TTF-PARSE-GLYF` | `( -- flag )` | Parse `glyf` table |
| `TTF-GLYPH-DATA` | `( glyph-id -- addr len \| 0 0 )` | Raw glyph data location |
| `TTF-GLYPH-NCONTOURS` | `( glyph-addr -- n )` | Number of contours |
| `TTF-GLYPH-XMIN` | `( glyph-addr -- n )` | Glyph bounding box min X |
| `TTF-GLYPH-YMIN` | `( glyph-addr -- n )` | Glyph bounding box min Y |
| `TTF-GLYPH-XMAX` | `( glyph-addr -- n )` | Glyph bounding box max X |
| `TTF-GLYPH-YMAX` | `( glyph-addr -- n )` | Glyph bounding box max Y |

---

## Simple Glyph Decoder

| Word | Stack Effect | Description |
|---|---|---|
| `TTF-DECODE-GLYPH` | `( glyph-id -- npts ncont \| 0 0 )` | Decode glyph outline points |
| `TTF-PT-X` | `( i -- x )` | X coordinate of decoded point i |
| `TTF-PT-Y` | `( i -- y )` | Y coordinate of decoded point i |
| `TTF-PT-FLAG` | `( i -- flag )` | Raw flag byte of point i |
| `TTF-PT-ONCURVE?` | `( i -- flag )` | True if point i is on-curve |
| `TTF-CONT-END` | `( i -- idx )` | Last point index of contour i |

After calling `TTF-DECODE-GLYPH`, point data is stored in internal
arrays (`_TTF-PTS-X`, `_TTF-PTS-Y`, `_TTF-PTS-FL`) and contour
endpoints in `_TTF-CONT-ENDS`.

### Flag Bits

| Bit | Name | Meaning |
|---|---|---|
| 0 | ON_CURVE_POINT | Point is on the curve (vs. off-curve control point) |
| 1 | X_SHORT_VECTOR | X delta is 1 byte |
| 2 | Y_SHORT_VECTOR | Y delta is 1 byte |
| 3 | REPEAT_FLAG | Next byte is repeat count |
| 4 | X_IS_SAME | X delta is 0 (if short: positive) |
| 5 | Y_IS_SAME | Y delta is 0 (if short: positive) |

---

## cmap (Format 4)

| Word | Stack Effect | Description |
|---|---|---|
| `TTF-PARSE-CMAP` | `( -- flag )` | Parse cmap table, find format 4 subtable |
| `TTF-CMAP-LOOKUP` | `( unicode -- glyph-id )` | Map Unicode codepoint to glyph ID |

Format 4 covers BMP characters (U+0000–U+FFFF).  Prefers platform
(3,1) Windows Unicode BMP or (0,*) Unicode encoding.

---

## Quick Reference

```
TTF-BASE!           ( addr -- )
TTF-PARSE-HEAD      ( -- flag )
TTF-PARSE-MAXP      ( -- flag )
TTF-PARSE-HHEA      ( -- flag )
TTF-PARSE-HMTX      ( -- flag )
TTF-PARSE-LOCA      ( -- flag )
TTF-PARSE-GLYF      ( -- flag )
TTF-PARSE-CMAP      ( -- flag )
TTF-CMAP-LOOKUP     ( unicode -- glyph-id )
TTF-DECODE-GLYPH    ( glyph-id -- npts ncont | 0 0 )
TTF-PT-X            ( i -- x )
TTF-PT-Y            ( i -- y )
TTF-PT-ONCURVE?     ( i -- flag )
TTF-CONT-END        ( i -- idx )
TTF-ADVANCE         ( glyph-id -- width )
TTF-LSB             ( glyph-id -- lsb )
TTF-UPEM            ( -- n )
TTF-ASCENDER        ( -- n )
TTF-DESCENDER       ( -- n )
```

### Typical Usage

```forth
REQUIRE ttf.f

\ Load TTF file into memory at some-addr
some-addr TTF-BASE!
TTF-PARSE-HEAD DROP
TTF-PARSE-MAXP DROP
TTF-PARSE-HHEA DROP
TTF-PARSE-HMTX DROP
TTF-PARSE-LOCA DROP
TTF-PARSE-GLYF DROP
TTF-PARSE-CMAP DROP

\ Look up glyph for 'A' (U+0041)
0x41 TTF-CMAP-LOOKUP   ( -- glyph-id )
TTF-DECODE-GLYPH       ( -- npts ncont )
```

---

## Known Limitations

1. **Simple glyphs only** — Composite glyphs (nContours < 0) return
   `0 0`.  Accented characters using composition won't render.
2. **BMP only** — cmap format 4 covers U+0000–U+FFFF.  Emoji and
   CJK extensions need format 12.
3. **No hinting** — TrueType bytecode instructions are skipped.
4. **No kerning** — `kern` table is not parsed.
5. **Hard limits** — 256 points per glyph, 64 bytes for contour
   endpoints (enough for most Latin glyphs).
