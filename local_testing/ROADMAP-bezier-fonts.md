# Roadmap: Bézier & Font Stack for Megapad-64

## Goal

Runtime vector font rendering using the tile engine's FP16 SIMD.
TrueType glyph outlines → Bézier flattening → scanline rasterization → glyph cache.

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Kalki GUI  (kalki-gfx.f, kalki-widget.f, ...)  │
│    GFX-TYPE / GFX-CHAR  — render cached glyphs   │
├─────────────────────────────────────────────────┤
│  utils/font/cache.f   — glyph bitmap cache  ❌   │
│  utils/font/raster.f  — scanline fill        ⚠️   │
│  utils/font/ttf.f     — TrueType parser      ✅   │
├─────────────────────────────────────────────────┤
│  utils/text/layout.f  — advance widths, break ❌   │
│  utils/text/utf8.f    — UTF-8 codec           ✅   │
├─────────────────────────────────────────────────┤
│  utils/math/bezier.f  — Bézier eval & flatten ✅   │
│  utils/math/fp16-ext.f— lerp, cmp, div, sqrt  ✅   │
│  utils/math/fp16.f    — basic FP16 SIMD        ✅   │
│  utils/math/fixed.f   — 16.16 fixed-point      ✅   │
└─────────────────────────────────────────────────┘
```

## Hardware Inventory (relevant tile engine ops)

| Category | BIOS Word | Description |
|----------|-----------|-------------|
| Arith | TADD, TSUB | element-wise add/sub |
| Arith | TMUL | element-wise multiply |
| Arith | TFMA | fused multiply-add: dst = src0*src1 + dst |
| Arith | TMAC | multiply-accumulate in-place |
| Compare | TEMIN, TEMAX | element-wise min/max |
| Unary | TABS | element-wise absolute value |
| Reduce | TMIN, TMAX | reduction min/max → ACC |
| Reduce | TSUM, TDOT | sum / dot product → ACC |
| Mode | FP16-MODE | set 32-lane × 16-bit IEEE 754 half |
| Memory | TLOAD2D, TSTORE2D | strided 2D DMA |
| Accum | ACC@, ACC1@, ACC2@, ACC3@ | read accumulators |

**SS modes**: tile-tile (0), broadcast-reg (1), imm8-splat (2), in-place (3).
Broadcast mode not yet exposed as Forth words — fp16-ext.f will use
raw CSR writes if needed, or write directly to tile buffers.

**Not available as BIOS words**: extended shift (VSHR/VSHL/VCLZ) — hardware exists
but no Forth wrappers. Can add if needed.

---

## Phase 1: General Math Helpers (akashic)

### 1a. `utils/math/fp16-ext.f` — Extended FP16 Operations

**Depends on**: fp16.f

These are general-purpose FP16 operations useful beyond just Bézier:

| Word | Stack | Description |
|------|-------|-------------|
| `FP16-LT` | ( a b -- flag ) | a < b (signed compare via bit tricks) |
| `FP16-GT` | ( a b -- flag ) | a > b |
| `FP16-LE` | ( a b -- flag ) | a ≤ b |
| `FP16-EQ` | ( a b -- flag ) | a = b (with ±0 handling) |
| `FP16-LERP` | ( a b t -- result ) | linear interpolation: a + t*(b-a) |
| `FP16-CLAMP` | ( x lo hi -- clamped ) | clamp x to [lo, hi] |
| `FP16-RECIP` | ( a -- 1/a ) | reciprocal via Newton-Raphson (2 iterations) |
| `FP16-DIV` | ( a b -- a/b ) | a * recip(b) |
| `FP16-SQRT` | ( a -- √a ) | square root via Newton-Raphson |
| `FP16-FLOOR` | ( a -- ⌊a⌋ ) | floor to integer FP16 |
| `FP16-FRAC` | ( a -- frac ) | fractional part |
| `FP16>S31.16` | ( fp16 -- fixed ) | convert FP16 to 16.16 fixed-point |
| `S31.16>FP16` | ( fixed -- fp16 ) | convert 16.16 fixed-point to FP16 |

**Comparison approach**: IEEE 754 FP16 bit patterns are ordered like
sign-magnitude integers. For two positive FP16 values, unsigned integer
comparison gives correct ordering. For negatives, reverse. Handle ±0.

**Reciprocal approach** (Newton-Raphson):
1. Initial estimate: manipulate exponent bits: `recip0 ≈ 0x7BFF - x`
2. Refine: `r = r * (2 - x*r)` — uses FP16-MUL, FP16-SUB, FP16-FMA
3. Two iterations give ~10-bit accuracy (sufficient for FP16's 10-bit mantissa)

**Square root approach** (Newton-Raphson):
1. Initial estimate from halved exponent
2. Refine: `s = 0.5 * (s + x/s)` — uses FP16-DIV (so RECIP must come first)
3. Two iterations sufficient

**Lerp**: `a + t*(b-a)` = one FP16-SUB, one FP16-MUL, one FP16-ADD.
Or better: put `a` in DST, `t` and `(b-a)` in SRC0/SRC1, use TFMA.

### 1b. `utils/math/fixed.f` — 16.16 Fixed-Point Arithmetic

**Depends on**: nothing (pure integer math)

For pixel-precise coordinate work. TrueType internally uses 26.6 fixed,
but 16.16 is more general and easier to work with in Forth.

| Word | Stack | Description |
|------|-------|-------------|
| `FX*` | ( a b -- a*b ) | fixed multiply (>> 16 after) |
| `FX/` | ( a b -- a/b ) | fixed divide (<< 16 before) |
| `FX-ABS` | ( a -- |a| ) | absolute value |
| `INT>FX` | ( n -- fx ) | integer to 16.16 |
| `FX>INT` | ( fx -- n ) | truncate to integer |
| `FX>FP16` | ( fx -- fp16 ) | convert to FP16 |
| `FP16>FX` | ( fp16 -- fx ) | convert from FP16 |
| `FX-LERP` | ( a b t -- r ) | fixed-point lerp, t in 0..0x10000 |

**Implementation**: 64-bit intermediates via `UM*` / `UM/MOD` or shift chains.
This gives us sub-pixel precision for rasterizer output coordinates
without tile engine overhead for simple coordinate math.

---

## Phase 2: Bézier Library (akashic)

### 2a. `utils/math/bezier.f` — Bézier Curve Primitives

**Depends on**: fp16.f, fp16-ext.f

All coordinates are FP16 (x, y) pairs.

| Word | Stack | Description |
|------|-------|-------------|
| `BZ-QUAD-EVAL` | ( P0x P0y P1x P1y P2x P2y t -- Rx Ry ) | evaluate quadratic at t |
| `BZ-CUBIC-EVAL` | ( ... t -- Rx Ry ) | evaluate cubic at t |
| `BZ-QUAD-SPLIT` | ( P0-P2 -- L0-L2 R0-R2 ) | split quad at t=0.5 |
| `BZ-CUBIC-SPLIT` | ( P0-P3 -- L0-L3 R0-R3 ) | split cubic at t=0.5 |
| `BZ-QUAD-FLAT?` | ( P0-P2 tol -- flag ) | flatness test |
| `BZ-CUBIC-FLAT?` | ( P0-P3 tol -- flag ) | flatness test |
| `BZ-QUAD-FLATTEN` | ( P0-P2 tol cb -- ) | recursive flatten, callback per segment |
| `BZ-CUBIC-FLATTEN` | ( P0-P3 tol cb -- ) | recursive flatten, callback per segment |

**Algorithm**: De Casteljau for eval/split. Flatness test: max distance
from control point(s) to chord < tolerance. Flatten: recursive subdivision
until flat, emit line segments.

**Stack depth concern**: Recursive subdivision can be deep. Use an explicit
stack in memory (array of control points) rather than Forth return stack
to avoid overflow. Max depth ~16 for typical glyphs at 8–16px sizes.

---

## Phase 3: Font Libraries (akashic)

### 3a. `utils/font/ttf.f` — TrueType Parser

Parse the minimum viable subset of TrueType:
- Offset table, table directory
- `head` — units per em, index format
- `maxp` — number of glyphs
- `cmap` — character to glyph ID mapping (format 4 for BMP)
- `loca` — glyph data offsets
- `glyf` — glyph outlines (simple + composite)
- `hhea` + `hmtx` — horizontal metrics (advance width, LSB)

Input: raw TTF data in memory (loaded from disk or embedded).
Output: glyph outlines as arrays of (x, y, on-curve) + contour endpoints.

### 3b. `utils/font/raster.f` — Scanline Rasterizer

Takes flattened line segments (from bezier.f), fills a monochrome or
anti-aliased bitmap.

1. Flatten all contours → edge list
2. For each scanline y: find x-intercepts, sort, fill between pairs
3. Write pixels to glyph bitmap buffer

Anti-aliasing: 4× vertical supersampling (render at 4× height,
average down to get 4-level alpha). Or use exact area coverage.

### 3c. `utils/font/cache.f` — Glyph Cache

Cache rendered glyph bitmaps in XMEM/HBW to avoid re-rasterizing.
LRU or simple hash table keyed on (glyph_id, size).

### 3d. `utils/text/layout.f` — Text Layout

Advance widths, kerning pairs (if `kern` table present),
line breaking, cursor positioning. Builds on utf8.f for
codepoint iteration.

---

## Build Order

| # | Module | Type | Depends On | Status | Tests |
|---|--------|------|-----------|--------|-------|
| 1 | fp16.f | general | BIOS | ✅ Done (be0e331) | 14/14 |
| 2 | utf8.f | general | — | ✅ Done (53814fc) | 14/14 |
| 3 | fp16-ext.f | general | fp16.f | ✅ Done (7517582) | 15/15 |
| 4 | fixed.f | general | — | ✅ Done (7517582) | 14/14 |
| 5 | bezier.f | general | fp16, fp16-ext | ✅ Done (3cb9bf6) | 15/15 |
| 6 | ttf.f | font | — | ✅ Done (c1693e7) | 20/20 |
| 7 | raster.f | font | bezier, fixed, ttf | ⚠️ Partial (4852623) | 9/9 |
| 8 | cache.f | font | raster | ❌ Not started | — |
| 9 | layout.f | text | utf8, ttf, cache | ❌ Not started | — |

Tests for each module go in `local_testing/` (gitignored from akashic main).

### Total: 7 modules committed, 95 tests passing, 2 modules remaining.

---

## Known Gaps & Limitations (for handoff)

### Critical — must fix before production use

1. **raster.f Stage C2 — off-curve Bézier handling NOT IMPLEMENTED**.
   `_RST-WALK-CONTOUR` treats ALL decoded TrueType points as straight-line
   vertices. Off-curve quadratic Bézier control points are connected as
   straight lines instead of being flattened through bezier.f. Curved
   contours render as coarse polygons. To fix:
   - Check `TTF-PT-ONCURVE?` for each decoded point
   - When off-curve: find next on-curve (or compute implied midpoint
     between consecutive off-curve points per TrueType spec)
   - Convert integer pixel coords to FP16 via `INT>FP16`
   - Call `BZ-QUAD-FLATTEN` with appropriate tolerance
   - In callback: convert FP16 endpoints back to integers, call `RAST-EDGE`
   - bezier.f is ready — the API `BZ-QUAD-FLATTEN ( x0 y0 x1 y1 x2 y2 tol xt -- )` exists and is tested

2. **fp16.f — `FP16-DOT` documented in header but never implemented**.
   Either implement it (trivial: `TDOT` tile op + `ACC@`) or remove from
   the API comment. No consumers currently depend on it.

### Minor — document or address later

3. **ttf.f — composite glyphs silently skipped** (returns `0 0` from
   `TTF-DECODE-GLYPH` when nContours < 0). Most Latin glyphs are simple;
   accented composites (é, ñ) will fail silently.
4. **ttf.f — `BE-SL@` defined but never used** anywhere. Keep for
   completeness or remove.
5. **ttf.f — cmap and glyph decode have no direct unit tests** in
   test-ttf.f (only tested indirectly via raster.f integration).
6. **raster.f — 1bpp only**, no anti-aliasing. Roadmap mentions 4×
   supersampling but it's not implemented.
7. **raster.f — `REQUIRE fixed.f` is unused** in current code. Was added
   in anticipation of C2 Bézier integration. Remove if C2 takes a
   different approach.
8. **Hard limits undocumented in headers**: `_TTF-MAX-PTS` = 256 (ttf.f),
   `_RST-MAX-EDGES` = 512 (raster.f), `_RST-MAX-XINTS` = 256 (raster.f).
9. **bezier.f — `LERP2D` and `MID2D` are public words** not listed in
   the file header's Public API section. Either document or prefix with `_BZ-`.

---

## Key Design Decisions

1. **FP16 for curve math, fixed-point for pixel coords**: FP16 gives us
   hardware-accelerated lerp/mul for Bézier evaluation. Fixed-point gives
   us exact sub-pixel precision for the rasterizer's scanline intersections
   where FP16's 10-bit mantissa would cause visible artifacts.

2. **Adaptive subdivision, not algebraic root-finding**: Finding where a
   curve crosses a scanline algebraically needs square roots and cubic
   solvers. Subdivision until flat + line-scanline intersection is simpler,
   uses only basic FP16 ops, and naturally handles degenerate cases.

3. **Memory budget**: At 8×16 pixels, a glyph bitmap is 16 bytes (1bpp)
   or 128 bytes (8bpp AA). A 256-glyph cache = 4 KiB (1bpp) or 32 KiB (AA).
   Fits easily in HBW's 3 MiB.

4. **Flatten tolerance**: For 8×16 output, deviation < 0.25 pixel is
   sufficient. In FP16 em-space, scale by ppem (pixels per em).
