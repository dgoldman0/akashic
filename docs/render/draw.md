# akashic-draw — 2D Drawing Primitives for KDOS / Megapad-64

Immediate-mode 2D drawing API that writes to a surface.  Provides
filled and outlined shapes, Bresenham line rasterization, Bézier
curve strokes, path-based filling/stroking, and glyph/text
rendering.

```forth
REQUIRE render/draw.f
```

`PROVIDED akashic-draw` — safe to include multiple times.
Automatically requires `surface.f`, `bezier.f`, `raster.f`,
`cache.f`, `layout.f`, and `utf8.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Rectangles](#rectangles)
- [Lines](#lines)
- [Circles & Ellipses](#circles--ellipses)
- [Triangles](#triangles)
- [Bézier Curves](#bézier-curves)
- [Path API](#path-api)
- [Glyph & Text Rendering](#glyph--text-rendering)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Surface-targeted** | Every draw call takes a surface as its first argument. All clipping is delegated to the surface's clip rectangle. |
| **Integer coordinates** | All coordinates are integer pixels. FP16 is used internally for slopes and curve flattening only. |
| **Packed RGBA color** | Color arguments are 32-bit RGBA8888 integers — the same format as `SURF-PIXEL!` and `COLOR-PACK-RGBA`. |
| **Immediate mode** | No retained scene graph. Each call writes pixels directly. |
| **Delegate to surface** | `DRAW-RECT` and `DRAW-HLINE` are thin wrappers over `SURF-FILL-RECT` and `SURF-HLINE`. |
| **Path API via raster.f** | `DRAW-PATH-*` words accumulate edges in the raster edge table, then fill or stroke in one pass. |
| **Prefix convention** | Public: `DRAW-`. Internal: `_DRAW-`. |

---

## Rectangles

### DRAW-RECT

```forth
DRAW-RECT  ( surf x y w h rgba -- )
```

Filled rectangle.  Equivalent to `SURF-FILL-RECT`.

### DRAW-RECT-OUTLINE

```forth
DRAW-RECT-OUTLINE  ( surf x y w h rgba thick -- )
```

Rectangle outline with inward-growing thickness.  Draws four bands
of horizontal/vertical spans.

```forth
my-fb 10 10 100 60 0xFFFFFFFF 2 DRAW-RECT-OUTLINE   \ 2 px white border
```

---

## Lines

### DRAW-HLINE

```forth
DRAW-HLINE  ( surf x y len rgba -- )
```

Horizontal line.  Equivalent to `SURF-HLINE`.

### DRAW-VLINE

```forth
DRAW-VLINE  ( surf x y len rgba -- )
```

Vertical line of `len` pixels downward from $(x, y)$.

### DRAW-LINE

```forth
DRAW-LINE  ( surf x0 y0 x1 y1 rgba -- )
```

General line using Bresenham's algorithm.  Plots one pixel per
step — single-pixel width with no anti-aliasing.  Works in all
octants.

```forth
my-fb 0 0 319 239 0xFF0000FF DRAW-LINE   \ diagonal red line
```

---

## Circles & Ellipses

### DRAW-CIRCLE

```forth
DRAW-CIRCLE  ( surf cx cy r rgba -- )
```

Filled circle using the midpoint algorithm.  Renders via horizontal
spans (`SURF-HLINE`) for each scanline — four spans per iteration
covering all octants.

### DRAW-CIRCLE-OUTLINE

```forth
DRAW-CIRCLE-OUTLINE  ( surf cx cy r rgba -- )
```

Circle outline (one-pixel width) using the midpoint algorithm.
Plots 8 symmetric pixels per iteration.

```forth
my-fb 160 120 50 0x00FF00FF DRAW-CIRCLE             \ filled green
my-fb 160 120 50 0xFFFFFFFF DRAW-CIRCLE-OUTLINE      \ white outline
```

### DRAW-ELLIPSE

```forth
DRAW-ELLIPSE  ( surf cx cy rx ry rgba -- )
```

Filled ellipse using the two-region midpoint algorithm.

- **Region 1** (slope < 1): increments $x$, conditionally decrements
  $y$.
- **Region 2** (slope ≥ 1): decrements $y$, conditionally increments
  $x$.

Both regions draw horizontal spans for filled rendering.

```forth
my-fb 160 120 80 40 0x0000FFFF DRAW-ELLIPSE   \ wide blue ellipse
```

---

## Triangles

### DRAW-TRIANGLE

```forth
DRAW-TRIANGLE  ( surf x0 y0 x1 y1 x2 y2 rgba -- )
```

Filled triangle via scanline decomposition.

**Algorithm:**
1. Sort vertices by $y$ ascending (bubble sort).
2. Compute FP16 slopes along each edge.
3. Rasterize top half (vertex A → B) and bottom half (B → C) using
   per-scanline horizontal spans.
4. Handles degenerate cases (collinear points, flat-top/flat-bottom).

```forth
my-fb 50 10 10 90 90 90 0xFF8000FF DRAW-TRIANGLE   \ orange triangle
```

---

## Bézier Curves

### DRAW-BEZIER-QUAD

```forth
DRAW-BEZIER-QUAD  ( surf x0 y0 x1 y1 x2 y2 rgba -- )
```

Stroke a quadratic Bézier curve from $(x_0, y_0)$ through control
point $(x_1, y_1)$ to $(x_2, y_2)$.  Flattens the curve into line
segments via `BZ-QUAD-FLATTEN` (tolerance 0.25 px) and draws each
segment with `DRAW-LINE`.

### DRAW-BEZIER-CUBIC

```forth
DRAW-BEZIER-CUBIC  ( surf x0 y0 x1 y1 x2 y2 x3 y3 rgba -- )
```

Stroke a cubic Bézier curve.  Same approach: flatten via
`BZ-CUBIC-FLATTEN`, draw line segments.

```forth
my-fb 10 100 80 10 200 10 280 100 0xFFFFFFFF DRAW-BEZIER-CUBIC
```

---

## Path API

The path API accumulates edges in the raster edge table (`raster.f`)
and then fills or strokes them in a single pass.  This supports
complex filled shapes — polygons, curved outlines, shapes with
holes — that would be tedious with individual draw calls.

### DRAW-PATH-BEGIN

```forth
DRAW-PATH-BEGIN  ( -- )
```

Start a new path.  Resets the raster edge table and bounding box.

### DRAW-PATH-MOVE

```forth
DRAW-PATH-MOVE  ( x y -- )
```

Move the cursor to $(x, y)$ without drawing.  Sets the sub-path
start point (used by `DRAW-PATH-CLOSE`).

### DRAW-PATH-LINE

```forth
DRAW-PATH-LINE  ( x y -- )
```

Add a straight-line edge from the current cursor to $(x, y)$.
Updates the cursor.

### DRAW-PATH-QUAD

```forth
DRAW-PATH-QUAD  ( cx cy x y -- )
```

Add a quadratic Bézier edge from the current cursor through
control point $(cx, cy)$ to $(x, y)$.  The curve is flattened into
line segments that become edges in the raster table.

### DRAW-PATH-CUBIC

```forth
DRAW-PATH-CUBIC  ( c1x c1y c2x c2y x y -- )
```

Add a cubic Bézier edge with two control points.

### DRAW-PATH-CLOSE

```forth
DRAW-PATH-CLOSE  ( -- )
```

Close the current sub-path by adding an edge from the cursor back
to the sub-path start (the last `DRAW-PATH-MOVE` position).

### DRAW-PATH-FILL

```forth
DRAW-PATH-FILL  ( surf rgba -- )
```

Fill the accumulated path using even-odd scanline filling.

**Algorithm:**
1. Compute the bounding box of all edges.
2. Offset all edges so the bbox origin is at (0, 0) — directly
   modifies `_RST-EX0`/`_RST-EY0`/`_RST-EX1`/`_RST-EY1` arrays.
3. Allocate a bbox-sized monochrome bitmap (1 byte/pixel).
4. Call `RAST-FILL` to scanline-fill the bitmap.
5. Blit non-zero bytes to the surface at the original bbox origin.
6. Free the temporary bitmap.

### DRAW-PATH-STROKE

```forth
DRAW-PATH-STROKE  ( surf rgba -- )
```

Stroke the accumulated path with single-pixel-width lines.  Reads
the raster edge arrays directly (`_RST-EX0`, `_RST-EY0`, etc.)
and draws each edge as a `DRAW-LINE`.

```forth
\ Draw a filled pentagon
DRAW-PATH-BEGIN
100 10 DRAW-PATH-MOVE
190 70 DRAW-PATH-LINE
160 160 DRAW-PATH-LINE
40 160 DRAW-PATH-LINE
10 70 DRAW-PATH-LINE
DRAW-PATH-CLOSE
my-fb 0x3399FFFF DRAW-PATH-FILL
```

---

## Glyph & Text Rendering

### DRAW-GLYPH

```forth
DRAW-GLYPH  ( surf glyph-id size x y rgba -- )
```

Render a single cached glyph at $(x, y)$.  Retrieves the glyph
bitmap from `font/cache.f` via `GC-GET`.  The bitmap contains
coverage values (0-255) from anti-aliased rasterization.

Non-zero coverage pixels are alpha-blended with the surface using
**sRGB-correct compositing**: channel values are linearized via a
256-byte LUT before blending, then converted back to sRGB.  This
prevents the "faded text" artifact that naive sRGB-space blending
produces on antialiased edges.

The linearization uses a gamma ≈ 2.1 approximation:
- sRGB → linear: `i² / 270`
- linear → sRGB: `isqrt(i × 255)`

Returns silently if the glyph is not in the cache.

### DRAW-TEXT

```forth
DRAW-TEXT  ( surf addr len x y size rgba -- )
```

Render a UTF-8 string.  For each codepoint:
1. Decode via `UTF8-DECODE`.
2. Map to glyph ID via `TTF-CMAP-LOOKUP`.
3. Render with `DRAW-GLYPH`.
4. Advance the cursor by `LAY-CHAR-WIDTH`.

A font must be loaded (`TTF-BASE!`, `TTF-PARSE-*`) and scale set
(`LAY-SCALE!`) before calling.

```forth
\ Render "Hello" at (10, 30) in 24px white
my-fb S" Hello" 10 30 24 0xFFFFFFFF DRAW-TEXT
```

---

## Internals

| Word | Purpose |
|---|---|
| `_DRAW-SURF`, `_DRAW-RGBA` | Current surface and color scratch. |
| `_DRAW-X0`..`_DRAW-Y3` | Coordinate scratch (shared across shapes). |
| `_DRAW-DX`, `_DRAW-DY`, `_DRAW-SX`, `_DRAW-SY`, `_DRAW-ERR`, `_DRAW-E2` | Bresenham state. |
| `_DRAW-CX`, `_DRAW-CY`, `_DRAW-XI`, `_DRAW-YI`, `_DRAW-D` | Midpoint circle/ellipse state. |
| `_DRAW-RX2`, `_DRAW-RY2`, `_DRAW-PX`, `_DRAW-PY`, `_DRAW-P` | Ellipse region parameters. |
| `_DRAW-TRI-*` | Triangle scanline state (sorted vertices, FP16 slopes). |
| `_DRAW-BZ-TOL` | Bézier flatten tolerance (FP16 0.25 = `0x3400`). |
| `_DRAW-BZ-CB`, `_DRAW-PBZ-CB` | Callbacks for curve flattening. |
| `_DRAW-PATH-*` | Path cursor, sub-path anchor, bounding box. |
| `_DRAW-PATH-OFFSET-EDGES` `( dx dy -- )` | Translate all raster edges for bbox-relative rendering. |
| `_DRAW-GL-*`, `_DRAW-TXT-*` | Glyph and text rendering scratch. |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `DRAW-RECT` | `( surf x y w h rgba -- )` | Filled rectangle |
| `DRAW-RECT-OUTLINE` | `( surf x y w h rgba thick -- )` | Rectangle outline |
| `DRAW-HLINE` | `( surf x y len rgba -- )` | Horizontal line |
| `DRAW-VLINE` | `( surf x y len rgba -- )` | Vertical line |
| `DRAW-LINE` | `( surf x0 y0 x1 y1 rgba -- )` | Bresenham line |
| `DRAW-CIRCLE` | `( surf cx cy r rgba -- )` | Filled circle |
| `DRAW-CIRCLE-OUTLINE` | `( surf cx cy r rgba -- )` | Circle outline |
| `DRAW-ELLIPSE` | `( surf cx cy rx ry rgba -- )` | Filled ellipse |
| `DRAW-TRIANGLE` | `( surf x0 y0 x1 y1 x2 y2 rgba -- )` | Filled triangle |
| `DRAW-BEZIER-QUAD` | `( surf x0 y0 x1 y1 x2 y2 rgba -- )` | Quadratic Bézier stroke |
| `DRAW-BEZIER-CUBIC` | `( surf x0 y0 x1 y1 x2 y2 x3 y3 rgba -- )` | Cubic Bézier stroke |
| `DRAW-PATH-BEGIN` | `( -- )` | Begin path |
| `DRAW-PATH-MOVE` | `( x y -- )` | Move cursor |
| `DRAW-PATH-LINE` | `( x y -- )` | Line edge |
| `DRAW-PATH-QUAD` | `( cx cy x y -- )` | Quadratic Bézier edge |
| `DRAW-PATH-CUBIC` | `( c1x c1y c2x c2y x y -- )` | Cubic Bézier edge |
| `DRAW-PATH-CLOSE` | `( -- )` | Close sub-path |
| `DRAW-PATH-FILL` | `( surf rgba -- )` | Fill path (even-odd) |
| `DRAW-PATH-STROKE` | `( surf rgba -- )` | Stroke path (1 px) |
| `DRAW-GLYPH` | `( surf glyph-id size x y rgba -- )` | Render cached glyph |
| `DRAW-TEXT` | `( surf addr len x y size rgba -- )` | Render UTF-8 string |

---

## Cookbook

### Filled shapes

```forth
320 240 SURF-CREATE CONSTANT fb

fb 10 10 100 50 0xFF0000FF DRAW-RECT          \ red rectangle
fb 160 120 40 0x00FF00FF DRAW-CIRCLE           \ green circle
fb 160 120 60 30 0x0000FFFF DRAW-ELLIPSE       \ blue ellipse
fb 50 10 10 90 90 90 0xFF8000FF DRAW-TRIANGLE  \ orange triangle
```

### Complex path

```forth
DRAW-PATH-BEGIN
50 50 DRAW-PATH-MOVE
150 50 DRAW-PATH-LINE
120 80 100 150 DRAW-PATH-QUAD    \ curve to (100, 150)
50 50 DRAW-PATH-LINE
DRAW-PATH-CLOSE
fb 0x9933CCFF DRAW-PATH-FILL
```

### Text rendering

```forth
\ Assumes font already loaded
fb S" Score: 42" 10 10 16 0xFFFFFFFF DRAW-TEXT
```
