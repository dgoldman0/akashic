# akashic-raster — Scanline Glyph Rasterizer for KDOS / Megapad-64

Even-odd scanline fill rasterizer for TrueType glyph outlines
with configurable N×N anti-aliased supersampling.
Handles on-curve and off-curve (quadratic Bézier) points, flattening
curves via `BZ-QUAD-FLATTEN` from `bezier.f`.

```forth
REQUIRE raster.f
```

`PROVIDED akashic-raster` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Edge Table](#edge-table)
- [Anti-Aliased Fill](#anti-aliased-fill)
- [Scanline Fill](#scanline-fill)
- [Contour Walker](#contour-walker)
- [RAST-GLYPH](#rast-glyph)
- [Quick Reference](#quick-reference)
- [Known Limitations](#known-limitations)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Even-odd fill rule** | Scanline x-intercepts are sorted; pixels between pairs are filled. |
| **Anti-aliased** | Configurable N×N supersampling grid; each pixel gets 0-255 coverage. Default N=6. |
| **1 byte/pixel** | Bitmap format: 0x00 = empty, 0xFF = fully covered, intermediates for AA edges.  Row-major. |
| **Integer pixel coords** | Coordinates are scaled to pixels before edge insertion. |
| **Bézier flattening** | Off-curve TrueType control points are flattened through `BZ-QUAD-FLATTEN` with 0.25px tolerance. |
| **Coordinate pipeline** | Font units → integer pixels → FP16 (for Bézier) → integer pixels (for edges). |

---

## Dependencies

```
raster.f ──→ fixed.f
         ──→ ttf.f
         ──→ bezier.f ──→ fp16-ext.f ──→ fp16.f
```

---

## Edge Table

Edges are stored as `(x0, y0, x1, y1)` integer quads, normalized
so `y0 <= y1`.  Horizontal edges (`y0 == y1`) are discarded since
they don't affect the even-odd fill.

| Word | Stack Effect | Description |
|---|---|---|
| `RAST-RESET` | `( -- )` | Clear all edges |
| `RAST-EDGE` | `( x0 y0 x1 y1 -- )` | Add edge (auto-normalizes, discards horizontal) |
| `RAST-NEDGES` | `( -- n )` | Current number of stored edges |

Maximum edges: 512 (`_RST-MAX-EDGES`).

---

## Scanline Fill

| Word | Stack Effect | Description |
|---|---|---|
| `RAST-FILL` | `( buf-addr width height -- )` | Rasterize edges into bitmap (no AA) |

For each scanline `y` from 0 to `height-1`:
1. Collect x-intercepts from all active edges (`y0 <= y < y1`)
2. Sort intercepts (insertion sort)
3. Fill pixel spans between consecutive pairs (even-odd rule)

The bitmap at `buf-addr` is cleared to zero before filling.
Each pixel is 1 byte: 0x00 = empty, 0xFF = filled.

---

## Anti-Aliased Fill

| Word | Stack Effect | Description |
|---|---|---|
| `RAST-AA!` | `( n -- )` | Set supersampling rate (1=off, 4–8 typical, default 6) |
| `RAST-AA@` | `( -- n )` | Get current supersampling rate |
| `RAST-FILL-AA` | `( buf-addr width height -- )` | Rasterize edges with N×N AA |

For each output pixel, an N×N grid of sub-pixels is sampled:

1. Edges must be pre-scaled to N× resolution (done by `RAST-GLYPH`)
2. For each output row, N sub-scanlines are rasterized at N× width
3. Sub-pixel hits are accumulated (0 to N per sub-column per row)
4. N sub-columns are summed per output pixel (total 0–N²)
5. Coverage mapped: `255 * hits / N²`

Higher N values give smoother edges but cost O(N²) per pixel.
Typical values:

| N | Sub-pixels | Coverage levels | Speed |
|---|---|---|---|
| 1 | 1 | 2 (binary) | Fastest |
| 4 | 16 | 17 | Fast |
| 6 | 36 | 37 | Default |
| 8 | 64 | 65 | High quality |
| 10 | 100 | 101 | Ultra |

---

## Contour Walker

The contour walker (`_RST-WALK-CONTOUR`) processes decoded TrueType
glyph points, handling the three cases:

1. **On-curve → on-curve**: Emit a straight line edge
2. **On-curve → off-curve → on-curve**: Emit a flattened quadratic Bézier
3. **Consecutive off-curve**: Compute implied midpoint, emit Bézier
   to midpoint, continue from there

### Starting Point Logic

- If the first point is on-curve: use it as the starting point
- If the first point is off-curve and the last is on-curve: start
  from the last point
- If both first and last are off-curve: start from their midpoint

### Coordinate Pipeline

```
Font units (TTF-PT-X/Y)
    │
    ▼  _RST-SCALE-X/Y  (multiply by pixel_size / UPEM, Y-flip)
Integer pixels
    │
    ▼  INT>FP16  (for Bézier segments only)
FP16 values
    │
    ▼  BZ-QUAD-FLATTEN  (0.25px tolerance)
FP16 line segments
    │
    ▼  FP16>INT  (in _RST-BZ-CB callback)
Integer pixel edges → RAST-EDGE
```

| Word | Stack Effect | Description |
|---|---|---|
| `RAST-SCALE!` | `( pixel-size-y pixel-size-x upem -- )` | Set coordinate scaling (separate X/Y for AA) |

---

## RAST-GLYPH

| Word | Stack Effect | Description |
|---|---|---|
| `RAST-GLYPH` | `( glyph-id pixel-size buf-addr w h -- ok? )` | Full glyph rasterization pipeline |

Steps:
1. Set scale from `pixel-size` and `TTF-UPEM`
2. Reset edge table
3. Decode glyph via `TTF-DECODE-GLYPH`
4. Walk each contour, emitting edges
5. Fill bitmap via `RAST-FILL-AA` (anti-aliased, uses current `RAST-AA@` rate)

Returns `TRUE` on success, `FALSE` if glyph has no data (e.g.,
space character or composite glyph).

Prerequisite: All TTF tables must be parsed (`TTF-PARSE-HEAD`,
`MAXP`, `LOCA`, `GLYF`).

---

## Quick Reference

```
RAST-RESET      ( -- )
RAST-EDGE       ( x0 y0 x1 y1 -- )
RAST-NEDGES     ( -- n )
RAST-FILL       ( buf-addr width height -- )     \ no AA
RAST-FILL-AA    ( buf-addr width height -- )     \ N×N AA
RAST-AA!        ( n -- )                         \ set AA rate
RAST-AA@        ( -- n )                         \ get AA rate
RAST-SCALE!     ( pixel-size-y pixel-size-x upem -- )
RAST-GLYPH      ( glyph-id pixel-size buf-addr w h -- ok? )
```

---

## Known Limitations

1. **512 edge limit** — Complex glyphs with many curve segments
   may exceed this.
2. **256 x-intercept limit** — Extremely complex scanlines could
   overflow.
3. **Simple glyphs only** — Inherits ttf.f limitation: composite
   glyphs are skipped.
4. **No hinting** — Outline geometry only; small sizes may look
   rough compared to hinted renderers.
5. **Max AA width** — Output width × N must fit in 1280-byte
   scratch buffer (e.g. N=8 → 160px max, N=6 → 213px max).
