# Roadmap: Math, Text & Font Libraries for Akashic

## Overview

Three new top-level Akashic module families — **math**, **text**, and
**font** — providing general-purpose numeric primitives, Unicode text
handling, and TrueType font parsing/rasterization for KDOS on the
Megapad-64.

The **math/** modules are standalone building blocks: hardware-accelerated
FP16 via the tile engine, 16.16 fixed-point arithmetic, and Bézier curve
evaluation/flattening. These are useful to any application that needs
non-integer math — graphics, physics, signal processing, animation, etc.

The **text/** module provides a UTF-8 codec used anywhere Unicode
strings appear (DOM, CSS, networking, user input).

The **font/** modules build on math and text to parse TrueType files
and rasterize glyph outlines into bitmaps.

---

## Module Map

```
┌─────────────────────────────────────────────────┐
│  math/fp16.f    — core FP16 SIMD wrappers  ✅   │
│  math/fp16-ext.f— lerp, cmp, div, sqrt     ✅   │
│  math/fixed.f   — 16.16 fixed-point        ✅   │
│  math/bezier.f  — Bézier eval & flatten    ✅   │
├─────────────────────────────────────────────────┤
│  text/utf8.f    — UTF-8 codec              ✅   │
│  text/layout.f  — advance widths, breaks   ❌   │
├─────────────────────────────────────────────────┤
│  font/ttf.f     — TrueType parser          ✅   │
│  font/raster.f  — scanline fill            ✅   │
│  font/cache.f   — glyph bitmap cache       ✅   │
└─────────────────────────────────────────────────┘
```

Legend: ✅ = implemented, ⚠️ = partially implemented, ❌ = not started

### Suggested Integration: Graphics / GUI Layer

An application-level graphics layer (e.g., a `gfx/` module) could
combine these libraries to provide high-level text rendering:

```
  Application code
       │
       ▼
  gfx/text.f  ── GFX-TYPE, GFX-CHAR (render cached glyphs to framebuffer)
       │
       ├──→ font/cache.f  (bitmap cache, LRU eviction)
       ├──→ text/layout.f (advance widths, line breaks)
       └──→ text/utf8.f   (codepoint iteration)
```

This integration layer is outside the scope of these libraries but
represents the primary intended consumer.

### Other Potential Consumers

- **css/css.f** — CSS `calc()` or animation timing could use FP16 math
- **dom/dom.f** — UTF-8 codec for text node handling
- **Emulator graphics** — Bézier curves for vector drawing, path rendering
- **Game / demo code** — fixed-point physics, FP16 particle systems
- **Any KDOS app** — general-purpose numeric and string utilities

---

## Module Directory Layout

New modules are organized as top-level packages under `akashic/`,
mirroring the existing convention (`css/`, `dom/`, `markup/`, `net/`, `utils/`):

```
akashic/
├── font/
│   ├── raster.f        scanline rasterizer + glyph contour walker
│   └── ttf.f           TrueType font parser
├── math/
│   ├── bezier.f        quadratic/cubic Bézier primitives
│   ├── fixed.f         16.16 fixed-point arithmetic
│   ├── fp16-ext.f      extended FP16 (comparisons, recip, sqrt, lerp)
│   └── fp16.f          core FP16 SIMD wrappers
└── text/
    └── utf8.f          UTF-8 encode/decode/validate
```

Documentation should mirror in `docs/font/`, `docs/math/`, `docs/text/`.

---

## Potential Future Modules

These are not started but are natural extensions of the existing libraries:

| Module | Location | Purpose | Would depend on |
|--------|----------|---------|-----------------|
| trig.f | math/ | Sin/cos/atan approximations in FP16 (polynomial or CORDIC) | fp16.f |
| mat2d.f | math/ | 2×3 affine transform matrices in FP16 (translate, rotate, scale) | fp16.f, trig.f |
| color.f | math/ | Color-space conversions (HSL↔RGB, sRGB gamma) in FP16 | fp16.f, fp16-ext.f |
| bitmap-font.f | font/ | Simple fixed-width bitmap font loader (PSF, BDF) as fallback | — |
| wordbreak.f | text/ | Unicode word/grapheme segmentation for line-break decisions | utf8.f |
| normalize.f | text/ | Unicode normalization (NFC/NFD) for string comparison | utf8.f |

These are listed for planning purposes. Prioritize based on application needs.

---

## Dependency Graph

```
bezier.f ──→ fp16-ext.f ──→ fp16.f
                               │
                               └──→ BIOS (HBW-ALLOT, tile engine ops)

raster.f ──→ fixed.f
         ──→ ttf.f

layout.f ──→ utf8.f         (planned)
         ──→ ttf.f           (planned)
         ──→ cache.f          (planned)

cache.f  ──→ raster.f        (planned)
```

---

## Current Status & Completeness Analysis

### Tier 1 — Math Primitives

#### `math/fp16.f` — Core FP16 SIMD Wrappers
- **Status**: Implemented
- **API**: ADD, SUB, MUL, NEG, ABS, SIGN, FMA, MIN, MAX, INT>FP16, FP16>INT
- **Constants**: POS-ZERO, NEG-ZERO, POS-ONE, NEG-ONE, POS-HALF, POS-INF, NEG-INF, QNAN
- **Issues**:
  - `FP16-DOT` is documented in the file header's public API section
    but **never implemented**. Either implement it (trivial: `TDOT` +
    `ACC@`) or remove from the header comment. No current consumers
    depend on it.
- **Tests needed**: Full coverage required — see Testing section below.

#### `math/fp16-ext.f` — Extended FP16 Operations
- **Status**: Implemented
- **API**: LT, GT, LE, GE, EQ, LERP, CLAMP, RECIP, DIV, SQRT, FLOOR, FRAC, FP16>FX, FX>FP16
- **Algorithm notes**: RECIP and SQRT use two-iteration Newton-Raphson;
  ~10-bit accuracy matches FP16's 10-bit mantissa.
- **Issues**: None critical. Well-commented.
- **Tests needed**: Full coverage required.

#### `math/fixed.f` — 16.16 Fixed-Point Arithmetic
- **Status**: Implemented
- **API**: FX\*, FX/, ABS, NEG, SIGN, INT>FX, FX>INT, FRAC, FLOOR, CEIL, ROUND, LERP, MIN, MAX, CLAMP
- **Issues**: None. Clean, self-contained, no dependencies.
- **Tests needed**: Full coverage required.

#### `math/bezier.f` — Bézier Curve Primitives
- **Status**: Implemented
- **API**: BZ-QUAD-EVAL, BZ-CUBIC-EVAL, BZ-QUAD-FLAT?, BZ-CUBIC-FLAT?,
  BZ-QUAD-FLATTEN, BZ-CUBIC-FLATTEN
- **Design**: Uses explicit work stack in memory (256 cells) to avoid
  Forth return stack overflow during deep subdivision. Non-recursive.
- **Issues**:
  - `LERP2D` and `MID2D` are public-scope words used by the module
    but not listed in the header's Public API section. Should be
    documented or prefixed with `_BZ-` to mark as internal.
- **Tests needed**: Full coverage required.

### Tier 2 — Text Encoding

#### `text/utf8.f` — UTF-8 Codec
- **Status**: Implemented
- **API**: UTF8-DECODE, UTF8-ENCODE, UTF8-LEN, UTF8-VALID?, UTF8-NTH
- **Error handling**: Invalid/truncated sequences return U+FFFD. Overlong
  encoding detection. Surrogate pair rejection. Out-of-range rejection.
- **Issues**: None. Clean and complete for its scope.
- **Tests needed**: Full coverage required.

### Tier 3 — Font Parsing

#### `font/ttf.f` — TrueType Parser
- **Status**: Implemented (minimum viable subset)
- **Tables parsed**: head, maxp, hhea, hmtx, loca, glyf, cmap (format 4)
- **API**: TTF-BASE!, TTF-PARSE-HEAD/MAXP/HHEA/HMTX/LOCA/GLYF/CMAP,
  TTF-DECODE-GLYPH, TTF-CMAP-LOOKUP, TTF-ADVANCE, TTF-LSB, accessors
- **Issues**:
  - **Composite glyphs silently skipped**: `TTF-DECODE-GLYPH` returns
    `0 0` when nContours < 0. Most Latin glyphs are simple, but
    accented composites (é, ñ, ö) will fail silently. This needs to be
    addressed for non-ASCII Latin text.
  - **cmap format 4 only**: Covers BMP (U+0000–U+FFFF) but not
    supplementary planes. Format 12 support needed for emoji or CJK
    extension characters.
  - `BE-SL@` (signed 32-bit big-endian read) is defined but never used.
    Keep for completeness or remove to reduce footprint.
  - No `kern` table parsing — kerning pairs unavailable.
  - **Hard limits**:
    - `_TTF-MAX-PTS` = 256 points per glyph (May be tight for complex CJK)
    - `_TTF-CONT-ENDS` = 64 bytes → 8 contours max (32 if stored as cells).
      Complex glyphs may exceed this.
- **Tests needed**: Full coverage required, including cmap lookup and
  glyph decoding with real TTF data.

### Tier 4 — Rasterization

#### `font/raster.f` — Scanline Rasterizer
- **Status**: Partially implemented (Stage C1)
- **Working**: Edge table, scanline x-intercept collection, insertion
  sort, even-odd fill, bitmap output (1 byte/pixel, 0xFF=filled).
- **CRITICAL ISSUE — Off-curve points not handled**:
  `_RST-WALK-CONTOUR` treats ALL decoded TrueType points as straight-line
  vertices. Off-curve quadratic Bézier control points are connected
  as straight line segments instead of being flattened through `bezier.f`.
  Curved contours render as coarse polygons. This is the single most
  important fix needed. To implement (Stage C2):
  1. Check `TTF-PT-ONCURVE?` for each point in the contour walker
  2. When off-curve: find next on-curve point (or compute implied
     midpoint between consecutive off-curve points per TrueType spec)
  3. Convert integer pixel coordinates to FP16 via `INT>FP16`
  4. Call `BZ-QUAD-FLATTEN` with appropriate tolerance
  5. In callback: convert FP16 endpoints back to integers, call `RAST-EDGE`
  6. The `bezier.f` API (`BZ-QUAD-FLATTEN`) already exists and is ready
- **Other issues**:
  - **1bpp only** — no anti-aliasing. 4× vertical supersampling
    (render at 4× height, average down) is the planned approach but
    not implemented.
  - `REQUIRE fixed.f` is loaded but not used by current code — was
    added in anticipation of Bézier integration in C2.
  - **Hard limits** (undocumented in header):
    - `_RST-MAX-EDGES` = 512
    - `_RST-MAX-XINTS` = 256
- **Tests needed**: Critical — the contour walker needs integration
  tests with real glyph data to verify correct rendering.

### Not Yet Started

#### `font/cache.f` — Glyph Bitmap Cache
- **Status**: Not started
- **Purpose**: Cache rendered glyph bitmaps in XMEM/HBW to avoid
  re-rasterizing frequently used characters.
- **Design considerations**:
  - LRU eviction or simple hash table keyed on (glyph_id, pixel_size)
  - At 8×16 px, a glyph bitmap is 128 bytes at 1 byte/pixel.
    A 256-glyph cache ≈ 32 KiB — fits easily in HBW's 3 MiB.
  - Should handle cache miss → rasterize → store → return bitmap addr
- **Depends on**: raster.f

#### `text/layout.f` — Text Layout Engine
- **Status**: Not started
- **Purpose**: Advance width accumulation, line breaking, cursor
  positioning. Uses utf8.f for codepoint iteration.
- **Design considerations**:
  - Iterate UTF-8 string → codepoint → glyph ID → advance width
  - Simple line-break at word boundaries or pixel width limit
  - Kerning pairs (if `kern` table is parsed) for tight spacing
- **Depends on**: utf8.f, ttf.f, cache.f

---

## Build Order

| # | Module | Location | Depends On | Status |
|---|--------|----------|-----------|--------|
| 1 | fp16.f | math/ | BIOS | ✅ Done |
| 2 | fp16-ext.f | math/ | fp16.f | ✅ Done |
| 3 | fixed.f | math/ | — | ✅ Done |
| 4 | bezier.f | math/ | fp16-ext.f | ✅ Done |
| 5 | utf8.f | text/ | — | ✅ Done |
| 6 | ttf.f | font/ | — | ✅ Done |
| 7 | raster.f | font/ | fixed.f, ttf.f, bezier.f | ✅ Done |
| 8 | cache.f | font/ | raster.f | ✅ Done |
| 9 | layout.f | text/ | utf8, ttf, cache | ❌ Not started |

---

## Phase Plan

### Phase 1 — Fix Critical Rasterizer Gap (raster.f Stage C2)

**Priority**: Highest. Without this, all curved glyphs render incorrectly.

1. Modify `_RST-WALK-CONTOUR` to inspect `TTF-PT-ONCURVE?`
2. Implement TrueType implied-midpoint logic for consecutive off-curve pts
3. Convert to FP16, call `BZ-QUAD-FLATTEN`, convert results back
4. Write integration tests with known glyph outlines
5. Validate against reference renderings for basic Latin characters

### Phase 2 — Write Tests for All Modules

**Priority**: High. No existing tests can be assumed correct — all tests
must be written fresh.

Each module needs a dedicated test file in `local_testing/`. Test
structure should follow the existing patterns (e.g., `test_css.py`,
`test_json.py`) but target the emulator's Forth execution.

- `test_fp16.py` — INT>FP16, FP16>INT round-trips; arithmetic accuracy;
  edge cases (±0, ±inf, NaN, subnormals); FMA; MIN/MAX
- `test_fp16_ext.py` — Comparison ordering; LERP interpolation accuracy;
  RECIP / DIV precision; SQRT precision; FLOOR/FRAC semantics;
  FP16↔FX conversion round-trips
- `test_fixed.py` — FX\*/FX/ accuracy; FLOOR/CEIL/ROUND; FRAC for
  negative values; LERP endpoints; CLAMP boundary behavior
- `test_bezier.py` — Quad/Cubic EVAL at t=0, 0.5, 1; flatness test
  for known-flat and known-curved inputs; FLATTEN output against
  reference line segments; work stack exhaustion (deep subdivision)
- `test_utf8.py` — 1/2/3/4-byte sequences; overlong rejection;
  surrogate rejection; truncated input; U+FFFD replacement; LEN
  consistency; VALID? for good and bad input; NTH boundary cases
- `test_ttf.py` — Big-endian readers; table directory lookup; head/maxp
  field extraction; cmap format 4 lookup (both delta and indexed
  segments); glyph decode (flag repetition, short/long deltas, contour
  endpoints); advance width / LSB accessors. Requires a small test TTF
  binary (can use a minimal subset embedded as Forth CREATE data).
- `test_raster.py` — Edge insertion/normalization; horizontal edge
  discard; scanline intercept math; sort correctness; even-odd fill
  for known polygons (triangle, rectangle, overlapping); full
  RAST-GLYPH pipeline once C2 is complete

### Phase 3 — Glyph Cache (cache.f)

1. Design cache data structure (hash map or direct-mapped)
2. Implement CACHE-LOOKUP, CACHE-STORE, CACHE-EVICT
3. Integrate with raster.f: miss → rasterize → store
4. Write tests for hit/miss/eviction paths

### Phase 4 — Text Layout (layout.f)

1. Implement advance-width accumulation: codepoint → glyph → width
2. Simple line-break algorithm at configurable pixel width
3. Cursor positioning (x, y baseline) for rendering pipeline
4. Optional: kern table parsing in ttf.f for pair adjustments
5. Write tests for multi-character strings, word-wrap, mixed-width text

### Phase 5 — Anti-Aliasing (raster.f enhancement)

1. Implement 4× vertical supersampling in RAST-FILL
2. Average down to produce 4-level alpha (0x00, 0x55, 0xAA, 0xFF)
3. Update cache to store alpha bitmaps
4. Write visual comparison tests

### Phase 6 — Documentation

Write `docs/` markdown files for each new module mirroring the
existing documentation style:

- `docs/math/fp16.md`
- `docs/math/fp16-ext.md`
- `docs/math/fixed.md`
- `docs/math/bezier.md`
- `docs/text/utf8.md`
- `docs/font/ttf.md`
- `docs/font/raster.md`
- `docs/font/cache.md` (when implemented)
- `docs/text/layout.md` (when implemented)

Each doc should include: purpose, dependencies, public API reference
with stack effects, internal word table, usage examples, and known
limitations.

---

## Known Limitations & Design Constraints

### Math

1. **FP16 precision**: 10-bit mantissa gives ~3 decimal digits.
   Sufficient for curve math at moderate sizes but may accumulate
   visible error for large-scale computation. Use fixed-point (16.16)
   where sub-pixel precision matters.

2. **Not re-entrant**: fp16.f operations use module-level tile buffers
   in HBW. No concurrent FP16 callers. The bezier.f flatten callback
   must not call BZ-*-FLATTEN recursively.

3. **Flatten tolerance**: For 8–16 px output, a deviation threshold of
   ~0.25 pixel in em-space (scaled by ppem) is sufficient. Larger sizes
   may want tighter tolerance at the cost of more edges.

4. **No trig**: Sine, cosine, atan2 are not yet available. Rotation
   and polar-coordinate work requires adding `math/trig.f`.

### Font

5. **Simple glyphs only**: Composite TrueType glyphs (nContours < 0)
   are silently skipped. Accented Latin characters that use composition
   will not render until composite glyph support is added to ttf.f.

6. **BMP only**: cmap format 4 covers U+0000–U+FFFF. Supplementary
   plane characters (emoji, CJK extensions) need format 12 support.

7. **No hinting**: TrueType instructions (bytecode hints) are skipped.
   Rendering relies solely on outline geometry and flattening tolerance.
   At small sizes, hinted fonts will look worse than on hinting-capable
   rasterizers.

8. **Memory budget**: At 8×16 pixels (1bpp), a glyph bitmap is 16 bytes.
   A 256-glyph cache with 8bpp = 32 KiB. Fits in HBW's 3 MiB.

### Text

9. **No normalization**: UTF-8 codec handles encoding/decoding but does
   not perform Unicode normalization (NFC/NFD). String comparison of
   equivalent but differently-encoded sequences will fail.

10. **No bidirectional text**: Layout (when implemented) will assume
    left-to-right only. RTL and mixed-direction text needs a bidi
    algorithm.
