# Math Roadmap — Akashic Libraries for KDOS / Megapad-64

The Megapad-64 is, at heart, a math processing unit.  Four full
cores each with a 32-lane FP16 SIMD tile engine, hardware crypto
accelerators (AES-GCM, SHA-3, SHA-256, CRC, TRNG, 512-bit Field ALU,
NTT, ML-KEM), and full 64×64-bit multiply/divide — sitting next to
3 MiB of dedicated HBW math RAM.  The current Akashic math surface
barely scratches this.  This roadmap plans a comprehensive numeric
library that exploits the hardware across the board.

---

## Table of Contents

- [Current State](#current-state)
- [Architecture Principles](#architecture-principles)
- [Tier 0 — Foundation Fixes](#tier-0--foundation-fixes)
- [Tier 1 — Core Numeric Expansion](#tier-1--core-numeric-expansion)
- [Tier 2 — Linear Algebra & Geometry](#tier-2--linear-algebra--geometry)
- [Tier 3 — Precision Infrastructure](#tier-3--precision-infrastructure)
- [Tier 4 — SIMD Batch Operations](#tier-4--simd-batch-operations)
- [Tier 5 — Statistics & Data Analysis](#tier-5--statistics--data-analysis)
  - [5.7 — Inferential Extensions](#57--inferential-extensions)
  - [5.8 — Non-Parametric & Model Diagnostics](#58--non-parametric--model-diagnostics)
  - [5.9 — Advanced Modeling](#59--advanced-modeling)
- [Tier 6 — Crypto Wrappers](#tier-6--crypto-wrappers)
- [Tier 7 — Signal Processing](#tier-7--signal-processing)
- [Tier 8 — Random & Sampling](#tier-8--random--sampling)
- [Tier 9 — Big Integer & Field Arithmetic](#tier-9--big-integer--field-arithmetic)
- [Tier 10 — Color & Pixel Math](#tier-10--color--pixel-math)
- [Tier 11 — Physics & Animation](#tier-11--physics--animation)
- [Dependency Graph](#dependency-graph)
- [Module Map](#module-map)
- [Implementation Stages](#implementation-stages)
- [Testing Strategy](#testing-strategy)
- [Hardware Reference](#hardware-reference)

---

## Current State

### What Exists

| File | Lines | Status | Domain | Key API |
|---|---|---|---|---|
| `math/fp16.f` | 212 | ✅ | FP16 tile-engine scalar wrappers | ADD, SUB, MUL, FMA, MIN, MAX, NEG, ABS, INT↔FP16 |
| `math/fp16-ext.f` | 279 | ✅ | Extended FP16 | LT/GT/LE/GE/EQ, LERP, CLAMP, RECIP, DIV, SQRT, FLOOR, FRAC, FP16↔FX |
| `math/fixed.f` | 118 | ✅ | 16.16 fixed-point | FX\*, FX/, LERP, CLAMP, MIN/MAX, rounding, INT↔FX |
| `math/bezier.f` | 257 | ✅ | Bézier curves (FP16) | Quad/cubic eval, flatness test, adaptive flatten with callback |
| `math/trig.f` | 242 | ✅ | FP16 trigonometry | SIN, COS, SINCOS, TAN, ATAN, ATAN2, ASIN, ACOS, DEG↔RAD |
| `math/exp.f` | — | ✅ | Exponentials & logarithms | EXP, LN, EXP2, LOG2, POW, SIGMOID, TANH |
| `math/interp.f` | — | ✅ | Interpolation & easing | SMOOTHSTEP, ease-in/out/in-out, CUBIC-BEZIER, CATMULL-ROM |
| `math/fp32.f` | 734 | ✅ | Software IEEE 754 binary32 | ADD, SUB, MUL, DIV, SQRT, FMA, comparisons, FP16↔FP32↔FX↔INT |
| `math/accum.f` | 200 | ✅ | Extended-precision accumulators | ACCUM-ADD-TILE, ACCUM-GET-FP32, 48.16 fixed-point pipeline |
| `math/vec2.f` | 242 | ✅ | 2D vectors (FP16) | ADD, SUB, SCALE, DOT, CROSS, LEN, NORM, LERP, ROTATE, REFLECT |
| `math/mat2d.f` | 363 | ✅ | 2×3 affine transforms (FP16) | IDENTITY, TRANSLATE, SCALE, ROTATE, MULTIPLY, TRANSFORM, INVERT, COMPOSE |
| `math/rect.f` | 255 | ✅ | Axis-aligned rectangles (FP16) | CONTAINS?, INTERSECT?, INTERSECT, UNION, EXPAND, AREA, CENTER |

### What's Missing

- `FP16-DOT` declared in header but never implemented
- No trigonometry (sin, cos, atan2)
- No vector/matrix types
- No color math
- No statistics
- No crypto wrappers — hardware accelerators exist but have no Forth API
- No PRNG (TRNG exists in hardware, but no seeded PRNG for reproducibility)
- No signal processing (hardware has DOT, MAC, DOTACC for convolution/FFT)
- No big integer / field math wrappers (512-bit Field ALU sits unused)
- Tile engine used only as scalar (lane 0) — 31 of 32 FP16 lanes wasted
- No batch/vector operations exploiting the full SIMD width

### Hardware Sitting Idle

| Accelerator | MMIO Status | Forth Wrapper | Potential |
|---|---|---|---|
| AES-256-GCM | ✅ Implemented | ❌ None | Authenticated encryption for AT Protocol, file encryption |
| SHA-256 | ✅ Implemented | ❌ None | Content hashing, HMAC, commit verification |
| SHA-3 / SHAKE | ✅ Implemented | ❌ None | Post-quantum signatures, KDF, content addressing |
| CRC32/CRC64 | ✅ Implemented | ❌ None | Network checksums, data integrity, DAG-CBOR |
| TRNG | ✅ Implemented | ❌ None | Key generation, nonce creation, secure random |
| Field ALU (512-bit) | ✅ Implemented | ❌ None | Curve25519, secp256k1, P-256, modular arithmetic |
| NTT Engine | ✅ Implemented | ❌ None | Polynomial multiplication, post-quantum crypto |
| ML-KEM-512 | ✅ Implemented | ❌ None | Post-quantum key encapsulation |
| Tile DOT/DOTACC | ✅ Implemented | ❌ None | Dot products, convolution, correlation |
| Tile MAC/FMA | ✅ Used scalar | ❌ No batch | Matrix multiply, neural inference, batch processing |
| Tile REDUCTION | ✅ Implemented | ❌ None | SUM, MIN, MAX, SUMSQ, L1-norm, POPCNT, argmin/argmax |

---

## Architecture Principles

| Principle | Detail |
|---|---|
| **Three number systems** | FP16 (tile-engine accelerated, 10-bit mantissa) for graphics, audio, ML; 16.16 fixed-point (integer ALU) for deterministic pixel-exact work; software FP32 (integer ALU, `fp32.f`) for statistics, regression, and any computation needing >3.3 decimal digits |
| **Mixed-precision pipeline** | Store data as FP16 (compact, SIMD-friendly). Tile reductions produce FP32 accumulators. Accumulate across tiles in 64-bit integers (48.16 fixed-point). Final-stage arithmetic in software FP32. Convert result back to FP16 for output. |
| **Batch-first design** | New APIs should accept tile-sized buffers (32 FP16 values) for SIMD throughput, with scalar convenience wrappers |
| **Zero-copy where possible** | Operate on HBW-allocated arrays in-place; avoid copying between regions |
| **VARIABLE-based state** | All loops use VARIABLEs — no locals, no return-stack tricks |
| **PREFIX convention** | Each module has a unique prefix (VEC2-, MAT2D-, TRIG-, STAT-, CRYPTO-, etc.) |
| **PROVIDED guards** | Every file uses `PROVIDED akashic-<name>` for idempotent loading |
| **REQUIRE chains** | Dependencies loaded automatically via REQUIRE |
| **HBW for SIMD, XMEM for bulk** | Tile operand buffers in HBW; large datasets in XMEM with DMA staging |

---

## Tier 0 — Foundation Fixes

Patch the existing libraries before building on top.

### 0.1  Implement `FP16-DOT`

Declared in `fp16.f` header but never defined.  Trivial:

```
: FP16-DOT  ( addr n -- acc )
    \ addr → array of n FP16 pairs (interleaved: a0 b0 a1 b1 ...)
    \ Use TDOT for 32-pair tiles, accumulate remainder.
    ... TDOT ACCLO@ ... ;
```

Two variants: `FP16-DOT` (scalar result) and `FP16-DOT32` (batch
32-pair dot via full tile width).

### 0.2  `FP16-SETUP2` tile buffer reuse

Current design zeros 3 × 64-byte tiles at init.  For scalar ops,
only lane 0 matters.  Add lazy-init flag to skip redundant zeroing.
Minor optimization but relevant for tight loops.

### 0.3  `LERP2D` / `MID2D` visibility

In `bezier.f`, `LERP2D` and `MID2D` are public-scope but undocumented.
Either:
- Promote to public API with `BZ-` prefix documentation, or
- Rename to `_BZ-LERP2D` / `_BZ-MID2D` to mark internal

### 0.4  Missing rounding in `FX*`

`FX*` uses `65536 /` (truncation).  Add `FX*R` (rounded variant):
`* 32768 + 65536 /` for half-up rounding.  Important for
accumulation-heavy paths (animation, filter coefficients).

---

## Tier 1 — Core Numeric Expansion

### 1.1  `math/trig.f` — Trigonometry

**File:** `math/trig.f`
**Prefix:** `TRIG-`
**Depends on:** `fp16.f`, `fp16-ext.f`

FP16 polynomial approximations for the core trig functions.
FP16's 10-bit mantissa means ~3 decimal digits — minimax polynomials
of degree 3–5 are sufficient.

| Word | Stack | Description |
|---|---|---|
| `TRIG-SIN` | `( angle -- sin )` | Sine, angle in FP16 radians |
| `TRIG-COS` | `( angle -- cos )` | Cosine |
| `TRIG-SINCOS` | `( angle -- sin cos )` | Both at once (shared range reduction) |
| `TRIG-TAN` | `( angle -- tan )` | Tangent |
| `TRIG-ATAN2` | `( y x -- angle )` | Four-quadrant arctangent |
| `TRIG-ATAN` | `( x -- angle )` | Single-argument arctangent |
| `TRIG-ASIN` | `( x -- angle )` | Arcsine |
| `TRIG-ACOS` | `( x -- angle )` | Arccosine |
| `TRIG-DEG>RAD` | `( deg -- rad )` | Degree → radian conversion |
| `TRIG-RAD>DEG` | `( rad -- deg )` | Radian → degree conversion |

**Constants:**
```
TRIG-PI          3.14159...   → 0x4248 in FP16
TRIG-2PI         6.28318...   → 0x4648
TRIG-PI/2        1.57079...   → 0x3E48
TRIG-PI/4        0.78539...   → 0x3A48
TRIG-INV-PI      0.31831...   → 0x3518
TRIG-INV-2PI     0.15915...   → 0x3118
```

**Algorithm:** Range reduction to [−π/4, π/4], then degree-optimized
minimax polynomial.  For SIN: $x - x^3/6 + x^5/120$ is good to ~12 bits in
[−π/4, π/4].  For ATAN: rational approximation or polynomial fit.

**Alternative:** CORDIC (shifts + adds, no multiply) could be faster
on integer ALU and avoid tile-engine overhead for scalar trig.
Implement both; benchmark; keep the faster one.

| Variant | Pros | Cons |
|---|---|---|
| Polynomial + FP16 tile | Exact control, tile FMA | Tile setup overhead per call |
| CORDIC (integer) | No tile overhead, iterative | Fixed iteration count, lower accuracy per step |
| Polynomial + 16.16 fixed | No tile overhead, FX\* available | Less range than FP16 |

Decision: Implement polynomial/FP16 first (simplest, proven accuracy).
Provide `TRIG-FX-SIN` etc. as 16.16 fixed-point variants for the
rasterizer and physics code that already works in fixed-point.

### 1.2  `math/exp.f` — Exponentials & Logarithms

**File:** `math/exp.f`
**Prefix:** `EXP-`
**Depends on:** `fp16.f`, `fp16-ext.f`

| Word | Stack | Description |
|---|---|---|
| `EXP-EXP` | `( x -- e^x )` | Natural exponential |
| `EXP-LN` | `( x -- ln[x] )` | Natural logarithm |
| `EXP-EXP2` | `( x -- 2^x )` | Base-2 exponential |
| `EXP-LOG2` | `( x -- log2[x] )` | Base-2 logarithm |
| `EXP-POW` | `( base exp -- base^exp )` | General power: $e^{exp \cdot \ln(base)}$ |
| `EXP-SIGMOID` | `( x -- σ[x] )` | Logistic sigmoid: $1/(1+e^{-x})$ |
| `EXP-TANH` | `( x -- tanh[x] )` | Hyperbolic tangent |
| `EXP-SOFTMAX-TILE` | `( src dst n -- )` | Softmax over FP16 array (tile-accelerated) |

**Algorithm:** `EXP2` via range reduction + polynomial.  `LN` via
mantissa extraction + polynomial on [1,2).  `EXP` = `EXP2(x / ln2)`.
`SIGMOID` via the identity $\sigma(x) = 0.5 + 0.5 \cdot \tanh(x/2)$
or direct piecewise polynomial (avoids division).

### 1.3  `math/interp.f` — Interpolation & Easing

**File:** `math/interp.f`
**Prefix:** `INTERP-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `trig.f`

Beyond linear LERP (already exists), add higher-order and easing
functions for animation and CSS transitions.

| Word | Stack | Description |
|---|---|---|
| `INTERP-SMOOTHSTEP` | `( edge0 edge1 x -- r )` | Hermite smoothstep |
| `INTERP-SMOOTHERSTEP` | `( edge0 edge1 x -- r )` | Perlin's improved smoothstep |
| `INTERP-EASE-IN-QUAD` | `( t -- r )` | $t^2$ |
| `INTERP-EASE-OUT-QUAD` | `( t -- r )` | $1-(1-t)^2$ |
| `INTERP-EASE-IN-OUT-QUAD` | `( t -- r )` | Smooth in-out |
| `INTERP-EASE-IN-CUBIC` | `( t -- r )` | $t^3$ |
| `INTERP-EASE-OUT-CUBIC` | `( t -- r )` | $1-(1-t)^3$ |
| `INTERP-EASE-IN-OUT-CUBIC` | `( t -- r )` | Smooth in-out cubic |
| `INTERP-EASE-IN-SINE` | `( t -- r )` | Sinusoidal ease |
| `INTERP-EASE-OUT-SINE` | `( t -- r )` | |
| `INTERP-EASE-ELASTIC` | `( t -- r )` | Elastic bounce |
| `INTERP-EASE-BOUNCE` | `( t -- r )` | Bounce at end |
| `INTERP-CUBIC-BEZIER` | `( t x1 y1 x2 y2 -- r )` | CSS `cubic-bezier()` timing |
| `INTERP-CATMULL-ROM` | `( p0 p1 p2 p3 t -- r )` | Catmull-Rom spline |
| `INTERP-HERMITE` | `( p0 m0 p1 m1 t -- r )` | Cubic Hermite |

CSS timing functions (`cubic-bezier()`) are directly needed by
`css/bridge.f` for animation and transitions.

---

## Tier 2 — Linear Algebra & Geometry  ✅ DONE

### 2.1  `math/vec2.f` — 2D Vectors (FP16)  ✅ DONE

**File:** `math/vec2.f`
**Prefix:** `V2-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `trig.f`
**Guard:** `PROVIDED akashic-vec2`
**Status:** Implemented.

Vectors are two FP16 values on the stack: `( x y )`.

| Word | Stack | Description |
|---|---|---|
| `V2-ADD` | `( ax ay bx by -- rx ry )` | Component-wise add |
| `V2-SUB` | `( ax ay bx by -- rx ry )` | Component-wise subtract |
| `V2-SCALE` | `( x y s -- rx ry )` | Scalar multiply |
| `V2-DOT` | `( ax ay bx by -- dot )` | Dot product |
| `V2-CROSS` | `( ax ay bx by -- cross )` | 2D cross product (scalar) |
| `V2-LEN` | `( x y -- len )` | Length (√(x²+y²)) |
| `V2-LENSQ` | `( x y -- len² )` | Squared length (no sqrt) |
| `V2-NORM` | `( x y -- nx ny )` | Normalize to unit length |
| `V2-DIST` | `( ax ay bx by -- d )` | Distance between two points |
| `V2-LERP` | `( ax ay bx by t -- rx ry )` | Linear interpolation |
| `V2-PERP` | `( x y -- -y x )` | Perpendicular (90° CCW) |
| `V2-REFLECT` | `( vx vy nx ny -- rx ry )` | Reflect v across normal n |
| `V2-ROTATE` | `( x y angle -- rx ry )` | Rotate by angle (requires trig.f) |
| `V2-NEG` | `( x y -- -x -y )` | Negate |
| `V2-MIN` | `( ax ay bx by -- rx ry )` | Component-wise min |
| `V2-MAX` | `( ax ay bx by -- rx ry )` | Component-wise max |

### 2.2  `math/mat2d.f` — 2×3 Affine Transform Matrices (FP16)  ✅ DONE

**File:** `math/mat2d.f`
**Prefix:** `M2D-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `trig.f`
**Guard:** `PROVIDED akashic-mat2d`
**Status:** Implemented.

A 2×3 matrix stored as 6 consecutive FP16 values in memory
(row-major: a b tx c d ty).

```
┌         ┐     ┌         ┐   ┌    ┐
│ a  b  tx│     │ sx·cos θ  -sy·sin θ  tx │   │ x' │   │ a·x + b·y + tx │
│ c  d  ty│  =  │ sx·sin θ   sy·cos θ  ty │   │ y' │ = │ c·x + d·y + ty │
└         ┘     └                          ┘   └    ┘   └                 ┘
```

| Word | Stack | Description |
|---|---|---|
| `M2D-IDENTITY` | `( addr -- )` | Store identity matrix |
| `M2D-TRANSLATE` | `( addr tx ty -- )` | Set translation |
| `M2D-SCALE` | `( addr sx sy -- )` | Set scale |
| `M2D-ROTATE` | `( addr angle -- )` | Set rotation |
| `M2D-MULTIPLY` | `( a b dst -- )` | Matrix multiply: dst = a × b |
| `M2D-TRANSFORM` | `( addr x y -- x' y' )` | Transform point |
| `M2D-TRANSFORM-N` | `( mat src dst n -- )` | Batch transform n points |
| `M2D-INVERT` | `( src dst -- flag )` | Invert matrix (flag=success) |
| `M2D-COMPOSE` | `( addr tx ty sx sy angle -- )` | Build TRS in one call |
| `M2D-COPY` | `( src dst -- )` | Copy 6 FP16 values |

**Consumers:**
- Font composite glyph assembly (TrueType compound glyphs specify
  2×2 affine transforms)
- CSS `transform: matrix()`, `rotate()`, `scale()`, `translate()`
- SVG path transforms
- Game/demo sprite transforms

### 2.3  `math/rect.f` — Axis-Aligned Rectangles  ✅ DONE

**File:** `math/rect.f`
**Prefix:** `RECT-`
**Depends on:** `fp16.f`, `fp16-ext.f`
**Guard:** `PROVIDED akashic-rect`
**Status:** Implemented.

Rectangles as `( x y w h )` in FP16, stored as 4 consecutive values.

| Word | Stack | Description |
|---|---|---|
| `RECT-CONTAINS?` | `( rect px py -- flag )` | Point-in-rect test |
| `RECT-INTERSECT?` | `( r1 r2 -- flag )` | Do two rects overlap? |
| `RECT-INTERSECT` | `( r1 r2 dst -- flag )` | Compute intersection rect |
| `RECT-UNION` | `( r1 r2 dst -- )` | Bounding rect of two rects |
| `RECT-EXPAND` | `( rect margin dst -- )` | Expand by margin |
| `RECT-AREA` | `( rect -- area )` | Width × height |
| `RECT-CENTER` | `( rect -- cx cy )` | Center point |
| `RECT-EMPTY?` | `( rect -- flag )` | Zero area? |

**Consumer:** DOM layout, CSS box model, collision detection, dirty
rect tracking in the framebuffer.

---

## Tier 3 — Precision Infrastructure

FP16 has a 10-bit mantissa (~3.3 decimal digits).  This is fine for
graphics, trig, interpolation, and anything where ±0.1% error is
acceptable.  It is **not** fine for:

- **Variance** — computing $\sum(x_i - \bar{x})^2$ when values are
  near 100.0 (ULP = 0.1 → squared error vanishes into noise)
- **Accumulation** — summing 10,000 FP16 values drifts by hundreds of ULPs
- **Regression R²** — values near 1.0 (e.g., 0.98 vs 0.99) are
  indistinguishable in FP16 (ULP at 1.0 = 0.001)
- **Dynamic range** — FP16 maxes at 65,504; financial data, sensor
  readings, population counts easily exceed this

The solution is a **mixed-precision pipeline**: keep data in FP16
for compactness and SIMD throughput, accumulate intermediate results
in wider formats, and perform final-stage arithmetic in software FP32.

```
  ┌───────────┐   tile engine    ┌──────────────┐   integer ALU   ┌───────────┐
  │  FP16     │ ───────────────► │  FP32 accum  │ ──────────────► │  FP32     │
  │  data     │   TSUM,TSUMSQ   │  (ACC@ read) │   fp32.f ops    │  result   │
  │  (HBW)    │   TDOT,TMAC     │  per-tile     │   div,sqrt      │  (or FP16)│
  └───────────┘                  └──────┬───────┘                  └───────────┘
                                        │
                                 ACCUM-ADD-TILE
                                        │
                                 ┌──────▼───────┐
                                 │  64-bit int  │
                                 │  accumulator │
                                 │  (48.16 FP)  │
                                 │  cross-tile  │
                                 └──────────────┘
```

### 3.1  `math/fp32.f` — Software IEEE 754 Single-Precision  ✅ DONE

**File:** `math/fp32.f` (734 lines)
**Prefix:** `FP32-`
**Depends on:** nothing (pure integer ALU)
**Guard:** `PROVIDED akashic-fp32`
**Status:** Implemented.

Software emulation of IEEE 754 binary32 (single-precision) using the
64-bit integer ALU.  A 32-bit float is packed in the low 32 bits of a
64-bit cell.  ~10–20 cycles per operation — acceptable for final-stage
computation, unacceptable for tight inner loops (that's what the tile
engine is for).

#### Core Arithmetic

| Word | Stack | Description |
|---|---|---|
| `FP32-ADD` | `( a b -- a+b )` | Addition |
| `FP32-SUB` | `( a b -- a-b )` | Subtraction |
| `FP32-MUL` | `( a b -- a*b )` | Multiplication |
| `FP32-DIV` | `( a b -- a/b )` | Division |
| `FP32-NEGATE` | `( a -- -a )` | Flip sign bit (1 cycle) |
| `FP32-ABS` | `( a -- |a| )` | Clear sign bit (1 cycle) |

#### Extended Operations

| Word | Stack | Description |
|---|---|---|
| `FP32-SQRT` | `( a -- √a )` | Square root (Newton's method, 4 iterations) |
| `FP32-RECIP` | `( a -- 1/a )` | Reciprocal (Newton's method, 3 iterations) |
| `FP32-FMA` | `( a b c -- a*b+c )` | Fused multiply-add (single rounding) |

#### Comparison

| Word | Stack | Description |
|---|---|---|
| `FP32<` | `( a b -- flag )` | Less-than |
| `FP32>` | `( a b -- flag )` | Greater-than |
| `FP32=` | `( a b -- flag )` | Equality (exact) |
| `FP32<=` | `( a b -- flag )` | Less-or-equal |
| `FP32>=` | `( a b -- flag )` | Greater-or-equal |
| `FP32-0=` | `( a -- flag )` | Is zero? (±0) |
| `FP32-MIN` | `( a b -- min )` | Minimum |
| `FP32-MAX` | `( a b -- max )` | Maximum |

#### Conversion

| Word | Stack | Description |
|---|---|---|
| `FP16>FP32` | `( fp16 -- fp32 )` | Widen FP16 → FP32 (lossless) |
| `FP32>FP16` | `( fp32 -- fp16 )` | Narrow FP32 → FP16 (round-to-nearest-even) |
| `FP32>FX` | `( fp32 -- fx16.16 )` | FP32 → 16.16 fixed-point |
| `FX>FP32` | `( fx16.16 -- fp32 )` | 16.16 fixed-point → FP32 |
| `FP32>INT` | `( fp32 -- n )` | Truncate to integer |
| `INT>FP32` | `( n -- fp32 )` | Integer → FP32 |
| `ACC>FP32` | `( -- fp32 )` | Read tile accumulator CSR as FP32 (ACC@ low 32 bits) |

#### Constants

```
FP32-ZERO        0x00000000     0.0
FP32-ONE         0x3F800000     1.0
FP32-HALF        0x3F000000     0.5
FP32-TWO         0x40000000     2.0
FP32-PI          0x40490FDB     3.14159265...
FP32-E           0x402DF854     2.71828182...
FP32-INF         0x7F800000     +infinity
FP32-NAN         0x7FC00000     quiet NaN
```

#### Algorithm Notes

- **Multiplication:** Extract 24-bit mantissa (23 stored + implicit 1),
  24×24→48-bit product (fits in 64-bit cell), add exponents, normalize,
  round-to-nearest-even, pack.
- **Addition:** Exponent-align (right-shift smaller mantissa), 25-bit
  add/sub (guard bit for rounding), normalize, round, pack.
- **Division:** 24-bit mantissa divide via 64-bit integer division
  (shift numerator left 24 bits, divide, gives 24-bit quotient).
  Or Newton-Raphson: initial estimate from table, 2 iterations.
- **Square root:** Integer seed from exponent halving, then 4 Newton
  iterations.  Each iteration: `x_{n+1} = (x_n + a/x_n) / 2`,
  implemented in FP32 arithmetic (self-bootstrapping).

### 3.2  `math/accum.f` — Extended-Precision Accumulators  ✅ DONE

**File:** `math/accum.f` (200 lines)
**Prefix:** `ACCUM-`
**Depends on:** `fp32.f`, `fp16.f`
**Guard:** `PROVIDED akashic-accum`
**Status:** Implemented.

64-bit integer accumulators for numerically stable summation across
tile passes.  The tile engine's reductions (TSUM, TSUMSQ, etc.)
produce FP32 results in the accumulator CSRs.  Those are exact per
tile (32 elements).  But when processing thousands of elements across
hundreds of tiles, repeatedly converting FP32→FP16→add loses bits.

This module keeps a running 64-bit integer sum (48.16 fixed-point)
across tile passes, converting only at the end.

| Word | Stack | Description |
|---|---|---|
| `ACCUM-INIT` | `( ctx -- )` | Zero the accumulator context |
| `ACCUM-ADD-FP32` | `( ctx fp32 -- )` | Convert FP32 to 48.16, add to running total |
| `ACCUM-ADD-TILE` | `( ctx -- )` | Read ACC@ as FP32, add to running total |
| `ACCUM-ADD-TILE1` | `( ctx -- )` | Read ACC1@ as FP32, add to running total |
| `ACCUM-SUB-FP32` | `( ctx fp32 -- )` | Subtract FP32 from running total |
| `ACCUM-GET-FP32` | `( ctx -- fp32 )` | Extract current sum as FP32 |
| `ACCUM-GET-FP16` | `( ctx -- fp16 )` | Extract current sum as FP16 |
| `ACCUM-GET-INT` | `( ctx -- n )` | Extract current sum as integer (truncated) |
| `ACCUM-GET-RAW` | `( ctx -- lo hi )` | Raw 48.16 value (unsigned) |
| `ACCUM-RESET` | `( ctx -- )` | Zero without reallocation |

**Context layout (2 cells = 16 bytes):**

```
Offset  Field      Description
  +0    sum_lo     Lower 64 bits of 48.16 accumulator
  +8    flags      Sign + overflow indicator
```

**Usage pattern (typical stats loop):**

```forth
\ Compute mean of N FP16 values at SRC
: STABLE-MEAN  ( src n -- fp32-mean )
  ACCUM-CTX ACCUM-INIT              \ zero accumulator
  0 DO                               \ for each 32-element tile
    DUP I 6 LSHIFT + TILE0!          \   load tile from src + i*64
    TSUM                             \   FP32 sum → ACC0
    ACCUM-CTX ACCUM-ADD-TILE         \   add ACC0 to 48.16 running sum
  32 +LOOP
  DROP
  ACCUM-CTX ACCUM-GET-FP32           \ extract total as FP32
  INT>FP32 FP32-DIV                  \ divide by n in FP32
;
```

This gives ~15 decimal digits of accumulation precision (48.16
fixed-point), vs FP16's 3.3 or FP32's 7.2.  Catastrophic
cancellation in variance, covariance, and regression is eliminated.

**Why not just use FP32 accumulators throughout?**
The tile engine *already* accumulates in FP32 within a single
reduction.  But iterating across tiles requires adding FP32 values
together — which itself loses bits when the running sum grows large.
The 48.16 integer accumulator is exact for any value that fits (up
to ±140 trillion with 16 fractional bits), so running sums never
drift.

---

## Tier 4 — SIMD Batch Operations

The tile engine has 32 FP16 lanes.  Current libraries use lane 0 only.
This tier exposes the full width for data-parallel workloads.

### 4.1  `math/simd.f` — Tile-Width SIMD Primitives

**File:** `math/simd.f`
**Prefix:** `SIMD-`
**Depends on:** `fp16.f`

Raw 32-lane operations on HBW-allocated FP16 arrays.

| Word | Stack | Description |
|---|---|---|
| `SIMD-ADD` | `( src0 src1 dst -- )` | 32-wide FP16 add |
| `SIMD-SUB` | `( src0 src1 dst -- )` | 32-wide FP16 subtract |
| `SIMD-MUL` | `( src0 src1 dst -- )` | 32-wide FP16 multiply |
| `SIMD-FMA` | `( src0 src1 dst -- )` | 32-wide FMA: dst[i] += src0[i]·src1[i] |
| `SIMD-MAC` | `( src0 src1 dst -- )` | 32-wide multiply-accumulate |
| `SIMD-MIN` | `( src0 src1 dst -- )` | 32-wide elementwise min |
| `SIMD-MAX` | `( src0 src1 dst -- )` | 32-wide elementwise max |
| `SIMD-ABS` | `( src dst -- )` | 32-wide absolute value |
| `SIMD-NEG` | `( src dst -- )` | 32-wide negate |
| `SIMD-SCALE` | `( src scalar dst -- )` | Broadcast scalar × 32 elements |
| `SIMD-DOT` | `( src0 src1 -- acc )` | 32-pair dot product |
| `SIMD-SUM` | `( src -- sum )` | Reduction: sum of 32 elements |
| `SIMD-SUMSQ` | `( src -- sumsq )` | Reduction: sum of squares |
| `SIMD-RMIN` | `( src -- min )` | Reduction: minimum |
| `SIMD-RMAX` | `( src -- max )` | Reduction: maximum |
| `SIMD-ARGMIN` | `( src -- index )` | Reduction: index of minimum |
| `SIMD-ARGMAX` | `( src -- index )` | Reduction: index of maximum |
| `SIMD-L1NORM` | `( src -- norm )` | Reduction: L1 norm |
| `SIMD-POPCNT` | `( src -- cnt )` | Reduction: population count |
| `SIMD-CLAMP` | `( src lo hi dst -- )` | 32-wide clamp |
| `SIMD-FILL` | `( dst val -- )` | Broadcast fill |
| `SIMD-ZERO` | `( dst -- )` | Zero a tile |
| `SIMD-COPY` | `( src dst -- )` | Copy 64 bytes |
| `SIMD-LOAD2D` | `( base stride rows dst -- )` | Strided 2D load into tile |
| `SIMD-STORE2D` | `( src base stride rows -- )` | Strided 2D store from tile |

### 4.2  `math/simd-ext.f` — Batch Operations Over Arrays

**File:** `math/simd-ext.f`
**Prefix:** `SIMD-`
**Depends on:** `simd.f`

Operations on arrays longer than 32 elements, with automatic
tile chunking and remainder handling.

| Word | Stack | Description |
|---|---|---|
| `SIMD-ADD-N` | `( src0 src1 dst n -- )` | Add n FP16 pairs |
| `SIMD-MUL-N` | `( src0 src1 dst n -- )` | Multiply n pairs |
| `SIMD-SCALE-N` | `( src scalar dst n -- )` | Scale n elements |
| `SIMD-DOT-N` | `( src0 src1 n -- acc )` | Dot product of n pairs |
| `SIMD-SUM-N` | `( src n -- sum )` | Sum of n elements |
| `SIMD-SUMSQ-N` | `( src n -- sumsq )` | Sum of squares of n elements |
| `SIMD-MIN-N` | `( src n -- min )` | Min of n elements |
| `SIMD-MAX-N` | `( src n -- max )` | Max of n elements |
| `SIMD-SAXPY-N` | `( a x y dst n -- )` | $y_i = a \cdot x_i + y_i$ (BLAS-1) |
| `SIMD-NORM-N` | `( src n -- norm )` | L2 norm of n elements |
| `SIMD-NORMALIZE-N` | `( src dst n -- )` | Normalize array to unit length |

The `*-N` words tile-chunk automatically: process 32 elements per
tile op, handle remainder with masked/partial tiles.

---

## Tier 5 — Statistics & Data Analysis

This is the flagship tier — the one that justifies the platform.
The Megapad-64 has 32-lane FP16 SIMD with hardware reductions
(SUM, SUMSQ, MIN, MAX, ARGMIN, ARGMAX, L1-norm, POPCNT) and
FP32 accumulation for numerically stable per-tile summation.
Most microcontrollers and retro platforms have *nothing* like this.
A rich statistical library running on top of it is genuinely
differentiated — not a thin wrapper, but real analytical tooling.

**Precision strategy (Tier 3 infrastructure):** FP16's 10-bit
mantissa is insufficient for statistical computation (variance,
regression R², accumulated sums).  All Tier 5 modules use the
mixed-precision pipeline from Tier 3:

1. **Data in FP16** — compact, SIMD-friendly, stored in HBW
2. **Tile reductions → FP32 accumulators** — hardware TSUM/TSUMSQ
   produce FP32 results per tile (32 elements)
3. **Cross-tile accumulation → 64-bit integers** — `accum.f` keeps
   48.16 fixed-point running sums across hundreds of tiles
4. **Final-stage arithmetic → software FP32** — `fp32.f` handles
   division, square root, and any computation needing >3.3 decimal
   digits of precision
5. **Result → FP16** — narrow back for storage and display

The stats suite is split into six focused modules:

```
 math/sort.f        ← sorting & rank operations
 math/stats.f       ← descriptive statistics (central tendency, spread, shape)
 math/regression.f  ← linear models, curve fitting, residual analysis
 math/timeseries.f  ← moving averages, smoothing, trend extraction
 math/probability.f ← distributions, hypothesis testing, p-values
 math/counting.f    ← combinatorics, set operations, frequency tables
```

---

### 5.1  `math/sort.f` — Sorting & Rank Operations

**File:** `math/sort.f`
**Prefix:** `SORT-`
**Depends on:** `fp16.f`, `fp16-ext.f`

Sorting is the gateway to almost every order-statistic: median,
percentile, rank, IQR, trimmed mean, MAD.  Getting it right — and
fast — underpins the entire stats suite.

| Word | Stack | Description |
|---|---|---|
| `SORT-FP16` | `( addr n -- )` | In-place sort, ascending |
| `SORT-FP16-DESC` | `( addr n -- )` | In-place sort, descending |
| `SORT-FX` | `( addr n -- )` | Sort 16.16 fixed-point array |
| `SORT-INT` | `( addr n -- )` | Sort 64-bit integers |
| `SORT-ARGSORT` | `( src idx n -- )` | Index permutation (stable) |
| `SORT-PARTIAL` | `( addr n k -- )` | Partial sort: k smallest in [0..k) |
| `SORT-NTH` | `( addr n k -- val )` | k-th order statistic (quickselect, O(n) avg) |
| `SORT-RANK` | `( src dst n -- )` | Rank each element (1-based, ties averaged) |
| `SORT-IS-SORTED?` | `( addr n -- flag )` | Check if already sorted |
| `SORT-REVERSE` | `( addr n -- )` | Reverse array in-place |
| `SORT-UNIQUE` | `( src dst n -- m )` | Copy unique values to dst, return count m |
| `SORT-COUNT-UNIQUE` | `( addr n -- m )` | Count distinct values (sort-based) |

**Algorithms:**

| Algorithm | When | Complexity | Notes |
|---|---|---|---|
| Merge sort | General, stable, `SORT-ARGSORT` | O(n log n) | Uses XMEM temp buffer |
| Introsort | General, in-place | O(n log n) worst | Quicksort + heapsort fallback |
| Bitonic sort | Tile-friendly batches | O(n log² n) | 32-lane parallel compare-swap via `SIMD-MIN`/`SIMD-MAX` |
| Quickselect | `SORT-NTH`, `SORT-PARTIAL` | O(n) average | Median-of-3 pivot |
| Counting sort | Small integer ranges | O(n + k) | When range ≤ 1024 |

**Tile acceleration for bitonic sort:**
Load 32 FP16 values into two tiles.  Each compare-swap stage
becomes `SIMD-MIN` + `SIMD-MAX` (one tile op each).  For 32
elements, full bitonic sort is 5 stages × ~5 passes = ~25 tile
ops instead of ~160 scalar comparisons.  For larger arrays,
tile-sort each 32-element chunk, then merge.

---

### 5.2  `math/stats.f` — Descriptive Statistics

**File:** `math/stats.f`
**Prefix:** `STAT-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `fp32.f`, `accum.f`, `simd.f`, `sort.f`

The core module.  Every word accepts an FP16 array in HBW and
leverages tile reductions where possible.

#### Central Tendency

| Word | Stack | Description |
|---|---|---|
| `STAT-MEAN` | `( src n -- mean )` | Arithmetic mean |
| `STAT-WMEAN` | `( src weights n -- mean )` | Weighted mean |
| `STAT-GMEAN` | `( src n -- gmean )` | Geometric mean ($e^{\text{mean}(\ln x_i)}$) |
| `STAT-HMEAN` | `( src n -- hmean )` | Harmonic mean ($n / \sum 1/x_i$) |
| `STAT-MEDIAN` | `( src n -- med )` | Median (quickselect, non-destructive) |
| `STAT-MODE` | `( src n -- mode count )` | Most frequent value + its count |
| `STAT-TRIMMED-MEAN` | `( src n pct -- mean )` | Mean after trimming pct% from each tail |
| `STAT-WINSORIZED-MEAN` | `( src n pct -- mean )` | Mean with tail values clamped |

**Tile acceleration (mixed-precision):**
- `STAT-MEAN`: `TSUM` reduction over 32-element tiles (FP32
  accumulation per tile), `ACCUM-ADD-TILE` collects sums into 48.16
  integer across tiles, then `ACCUM-GET-FP32` / `INT>FP32` /
  `FP32-DIV` for final division in software FP32.
- `STAT-WMEAN`: `TDOT` (src × weights) + `TSUM` (weights),
  both accumulated via `accum.f`, divide in FP32.
- `STAT-HMEAN`: tile `FP16-RECIP` each element (batch via SIMD
  scale by reciprocal), then `TSUM`, then n / sum via FP32.

#### Dispersion & Spread

| Word | Stack | Description |
|---|---|---|
| `STAT-VARIANCE` | `( src n -- var )` | Population variance |
| `STAT-VARIANCE-S` | `( src n -- var )` | Sample variance (Bessel's correction, n−1) |
| `STAT-STDDEV` | `( src n -- sd )` | Population standard deviation |
| `STAT-STDDEV-S` | `( src n -- sd )` | Sample standard deviation |
| `STAT-SEM` | `( src n -- sem )` | Standard error of the mean (sd/√n) |
| `STAT-RANGE` | `( src n -- range )` | max − min |
| `STAT-IQR` | `( src n -- iqr )` | Interquartile range (Q3 − Q1) |
| `STAT-MAD` | `( src n -- mad )` | Median absolute deviation |
| `STAT-CV` | `( src n -- cv )` | Coefficient of variation (sd/mean) |
| `STAT-MIN` | `( src n -- min )` | Minimum |
| `STAT-MAX` | `( src n -- max )` | Maximum |
| `STAT-ARGMIN` | `( src n -- idx )` | Index of minimum |
| `STAT-ARGMAX` | `( src n -- idx )` | Index of maximum |

**Tile acceleration (mixed-precision):**
- `STAT-VARIANCE`: Two-pass (stable):
  1. `STAT-MEAN` → FP32 mean (via accum.f pipeline)
  2. Broadcast FP32→FP16 mean, `TSUB` per tile, `TSUMSQ` on
     deviations → FP32 per tile, `ACCUM-ADD-TILE` → 48.16 total
  3. `ACCUM-GET-FP32` / `INT>FP32` / `FP32-DIV` → FP32 variance
  4. `FP32>FP16` for output
  Alternatively, one-pass Welford for streaming data (see Online).
- `STAT-MIN/MAX`: Direct `TRMIN` / `TRMAX` reduction — single
  tile op for 32 elements.
- `STAT-ARGMIN/ARGMAX`: `TMINIDX` / `TMAXIDX` — hardware returns
  the lane index directly.
- `STAT-IQR`: `SORT-NTH` at k=n/4 and k=3n/4 (two quickselects).
- `STAT-MAD`: Compute median, subtract (tile `TSUB` with broadcast
  median), `TABS` (tile ABS), then median of result.

#### Shape & Distribution

| Word | Stack | Description |
|---|---|---|
| `STAT-SKEWNESS` | `( src n -- skew )` | Fisher–Pearson skewness |
| `STAT-KURTOSIS` | `( src n -- kurt )` | Excess kurtosis |
| `STAT-PERCENTILE` | `( src n p -- val )` | p-th percentile (linear interpolation) |
| `STAT-QUARTILES` | `( src n -- q1 q2 q3 )` | All three quartiles at once |
| `STAT-QUANTILE` | `( src n q -- val )` | Quantile (q in FP16 [0,1]) |
| `STAT-FIVE-NUM` | `( src n -- min q1 med q3 max )` | Five-number summary |
| `STAT-DESCRIBE` | `( src n dst -- )` | Full summary → 10-cell struct (n, mean, std, min, q1, med, q3, max, skew, kurt) |

**`STAT-DESCRIBE` layout (10 cells = 80 bytes):**

```
Offset  Field      Description
  +0    count      Number of observations (integer)
  +8    mean       Arithmetic mean (FP16)
 +16    stddev     Standard deviation (FP16)
 +24    min        Minimum (FP16)
 +32    q1         First quartile (FP16)
 +40    median     Median (FP16)
 +48    q3         Third quartile (FP16)
 +56    max        Maximum (FP16)
 +64    skewness   Skewness (FP16)
 +72    kurtosis   Excess kurtosis (FP16)
```

This is the `pandas.DataFrame.describe()` equivalent.

#### Histogramming & Frequency

| Word | Stack | Description |
|---|---|---|
| `STAT-HISTOGRAM` | `( src n bins lo hi dst -- )` | Uniform-width bin counts |
| `STAT-HISTOGRAM-AUTO` | `( src n dst -- bins )` | Auto-binned (Sturges' rule: $\lceil\log_2 n\rceil + 1$) |
| `STAT-FREQUENCY` | `( src n dst -- m )` | Frequency table: (value, count) pairs |
| `STAT-CDF` | `( src n x -- p )` | Empirical CDF: proportion ≤ x |
| `STAT-ECDF` | `( src n dst -- )` | Full empirical CDF curve to dst array |
| `STAT-ENTROPY` | `( probs n -- H )` | Shannon entropy: $-\sum p_i \ln p_i$ |
| `STAT-KL-DIV` | `( p q n -- kl )` | KL divergence: $\sum p_i \ln(p_i / q_i)$ |
| `STAT-CROSS-ENTROPY` | `( p q n -- H )` | Cross-entropy: $-\sum p_i \ln q_i$ |

**Tile acceleration for histogramming:**
For uniform bins with range [lo, hi):
- Broadcast-subtract lo from 32 elements (tile `TSUB`)
- Broadcast-multiply by bins/(hi-lo) (tile `TMUL`)
- Truncate to integer bin indices in parallel
- Scatter-increment bin counters

The scatter step is inherently serial (write conflicts), but the
index computation is fully parallel.  For small bin counts (< 32),
bit-manipulation tricks can parallelize further.

#### Bivariate & Multivariate

| Word | Stack | Description |
|---|---|---|
| `STAT-COVARIANCE` | `( x y n -- cov )` | Population covariance |
| `STAT-COVARIANCE-S` | `( x y n -- cov )` | Sample covariance |
| `STAT-CORRELATION` | `( x y n -- r )` | Pearson correlation coefficient |
| `STAT-SPEARMAN` | `( x y n -- rho )` | Spearman rank correlation |
| `STAT-KENDALL` | `( x y n -- tau )` | Kendall rank correlation |
| `STAT-COSINE-SIM` | `( x y n -- sim )` | Cosine similarity |
| `STAT-EUCLIDEAN` | `( x y n -- dist )` | Euclidean distance |
| `STAT-MANHATTAN` | `( x y n -- dist )` | Manhattan (L1) distance |
| `STAT-CHEBYSHEV` | `( x y n -- dist )` | Chebyshev (L∞) distance |
| `STAT-JACCARD` | `( a b n -- j )` | Jaccard index (binary vectors) |
| `STAT-COV-MATRIX` | `( data vars obs dst -- )` | Covariance matrix (vars columns × obs rows) |
| `STAT-CORR-MATRIX` | `( data vars obs dst -- )` | Correlation matrix |

**Tile acceleration (mixed-precision):**
- `STAT-CORRELATION`: Three `SIMD-DOT-N` passes ($\sum x_i y_i$,
  $\sum x_i^2$, $\sum y_i^2$) plus two `SIMD-SUM-N` passes
  ($\sum x_i$, $\sum y_i$).  Five tile-chunked passes, all
  accumulated via `accum.f`.  Final Pearson formula computed in
  software FP32 (needs `FP32-SQRT` for denominator):
  $r = \frac{n\sum xy - \sum x \sum y}{\sqrt{(n\sum x^2 - (\sum x)^2)(n\sum y^2 - (\sum y)^2)}}$
- `STAT-COSINE-SIM`: `SIMD-DOT-N` for numerator, `SIMD-SUMSQ-N`
  × 2 for denominator norms.  Three passes.
- `STAT-EUCLIDEAN`: `TSUB` (tile-wide x−y), then `TSUMSQ` on
  difference.  Two tile ops per 32-element chunk.
- `STAT-MANHATTAN`: `TSUB`, `TABS` (abs), `TSUM`.  = hardware
  `TL1NORM` on the difference tile.  Essentially one reduction.
- `STAT-COV-MATRIX`: Outer loop over variable pairs, inner uses
  `STAT-COVARIANCE` (tile-accelerated).  For p variables:
  p(p+1)/2 covariance computations (symmetric matrix).

#### Online / Streaming Statistics

| Word | Stack | Description |
|---|---|---|
| `STAT-ONLINE-INIT` | `( ctx -- )` | Initialize online stats context |
| `STAT-ONLINE-PUSH` | `( ctx value -- )` | Add one observation |
| `STAT-ONLINE-PUSH-N` | `( ctx src n -- )` | Add n observations (tile-accelerated) |
| `STAT-ONLINE-MEAN` | `( ctx -- mean )` | Current mean |
| `STAT-ONLINE-VARIANCE` | `( ctx -- var )` | Current variance |
| `STAT-ONLINE-STDDEV` | `( ctx -- sd )` | Current stddev |
| `STAT-ONLINE-COUNT` | `( ctx -- n )` | Observations so far |
| `STAT-ONLINE-MIN` | `( ctx -- min )` | Running minimum |
| `STAT-ONLINE-MAX` | `( ctx -- max )` | Running maximum |
| `STAT-ONLINE-MERGE` | `( ctx1 ctx2 dst -- )` | Merge two online contexts (parallel reduce) |
| `STAT-ONLINE-RESET` | `( ctx -- )` | Reset to empty |

**Context layout (8 cells = 64 bytes):**

```
Offset  Field    Description
  +0    n        Count (integer, 64-bit)
  +8    mean     Running mean (FP32, software — needs >3.3 digits)
 +16    m2       Running sum of squared deviations (48.16 fixed-point)
 +24    min      Running min (FP16)
 +32    max      Running max (FP16)
 +40    sum      Running sum (48.16 fixed-point — for weighted variants)
 +48    reserved
 +56    reserved
```

**Algorithm:** Welford's online algorithm for numerically stable
variance.  Key difference from naive: mean and m2 are stored in
**FP32** and **48.16 fixed-point** respectively (not FP16), so
incremental updates don't lose precision.  Each `PUSH` is O(1).
`PUSH-N` uses tile `TSUM` and `TSUMSQ` to batch-update in chunks
of 32, FP32 accumulator results folded into the Welford state via
`accum.f`.  `MERGE` uses Chan's parallel algorithm — enables
multi-core stats by splitting data, computing per-core, then
merging contexts.

This is critical for sensor data, network telemetry, or any
scenario where data arrives incrementally and you can't afford to
re-scan the full array.

---

### 5.3  `math/regression.f` — Linear Models & Curve Fitting

**File:** `math/regression.f`
**Prefix:** `REG-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `fp32.f`, `accum.f`, `simd.f`, `stats.f`

#### Simple Linear Regression

| Word | Stack | Description |
|---|---|---|
| `REG-OLS` | `( x y n ctx -- )` | Ordinary least squares: fit y = β₀ + β₁x |
| `REG-SLOPE` | `( ctx -- slope )` | β₁ coefficient |
| `REG-INTERCEPT` | `( ctx -- intercept )` | β₀ coefficient |
| `REG-R-SQUARED` | `( ctx -- r² )` | Coefficient of determination |
| `REG-ADJ-R-SQUARED` | `( ctx -- r²adj )` | Adjusted R² |
| `REG-PREDICT` | `( ctx x -- y-hat )` | Predict y for given x |
| `REG-PREDICT-N` | `( ctx x-src dst n -- )` | Batch predict (tile-accelerated) |
| `REG-RESIDUALS` | `( ctx x y dst n -- )` | Compute residuals: yᵢ − ŷᵢ |
| `REG-SSE` | `( ctx x y n -- sse )` | Sum of squared errors |
| `REG-SSR` | `( ctx x y n -- ssr )` | Sum of squared regression |
| `REG-SST` | `( ctx y n -- sst )` | Total sum of squares |
| `REG-RMSE` | `( ctx x y n -- rmse )` | Root mean squared error |
| `REG-MAE` | `( ctx x y n -- mae )` | Mean absolute error |
| `REG-SE-SLOPE` | `( ctx x y n -- se )` | Standard error of slope |
| `REG-SE-INTERCEPT` | `( ctx x y n -- se )` | Standard error of intercept |

**Regression context (8 cells = 64 bytes):**

```
Offset  Field       Description
  +0    n           Observation count (integer)
  +8    slope       β₁ (FP32 — needs precision for R² computation)
 +16    intercept   β₀ (FP32)
 +24    r_squared   R² (FP32 — must distinguish 0.98 from 0.99)
 +32    sse         Sum of squared errors (48.16 via accum.f)
 +40    x_mean      Mean of x (FP32, cached for predictions)
 +48    y_mean      Mean of y (FP32)
 +56    sxx         Σ(xᵢ − x̄)² (48.16 via accum.f)
```

**Tile acceleration (mixed-precision):**
- `REG-OLS` requires: $\sum x_i$, $\sum y_i$, $\sum x_i^2$,
  $\sum x_i y_i$ — all computable via `SIMD-SUM-N`,
  `SIMD-SUMSQ-N`, `SIMD-DOT-N`.  Four tile-chunked passes,
  each accumulated via `accum.f` into 48.16.  Final coefficient
  computation (β₁ = Sxy/Sxx, β₀ = ȳ − β₁x̄) in software FP32.
- `REG-PREDICT-N`: Broadcast slope and intercept, then
  `SIMD-SCALE-N` (x × slope) + `SIMD-ADD` (+ intercept).
  Two tile ops per 32-element chunk.
- `REG-RESIDUALS`: `REG-PREDICT-N` then `SIMD-SUB-N`.
  Chain of tile ops — no scalar fallback needed.

#### Polynomial Regression

| Word | Stack | Description |
|---|---|---|
| `REG-POLY` | `( x y n degree ctx -- )` | Fit polynomial of given degree |
| `REG-POLY-PREDICT` | `( ctx x -- y-hat )` | Evaluate fitted polynomial |
| `REG-POLY-COEFFS` | `( ctx dst -- )` | Copy coefficients to dst |
| `REG-POLY-DEGREE` | `( ctx -- degree )` | Degree of fitted polynomial |

**Algorithm:** Vandermonde matrix + normal equations.  For degree ≤ 5
(which is practical in FP16's precision range), the system is small
enough to solve via explicit formulae or Gaussian elimination on a
6×7 augmented matrix.

#### Exponential & Power Fitting

| Word | Stack | Description |
|---|---|---|
| `REG-EXP-FIT` | `( x y n ctx -- )` | Fit y = a·e^(bx) via log-linear OLS |
| `REG-POWER-FIT` | `( x y n ctx -- )` | Fit y = a·x^b via log-log OLS |
| `REG-LOG-FIT` | `( x y n ctx -- )` | Fit y = a + b·ln(x) |

These transform the data (log y, log x) then call `REG-OLS`.
Depends on `exp.f` for `EXP-LN`.

#### Robust Regression

| Word | Stack | Description |
|---|---|---|
| `REG-THEIL-SEN` | `( x y n ctx -- )` | Theil-Sen estimator (median of pairwise slopes) |
| `REG-LAD` | `( x y n ctx -- )` | Least absolute deviations |

**`REG-THEIL-SEN`** is inherently outlier-resistant — the median
slope of all $\binom{n}{2}$ pairs.  For small n (≤ 100), enumerate
all pairs.  For large n, subsample.  Uses `SORT-NTH` (quickselect)
for the median.

---

### 5.4  `math/timeseries.f` — Time Series Analysis

**File:** `math/timeseries.f`
**Prefix:** `TS-`
**Depends on:** `fp16.f`, `simd.f`, `stats.f`

Time-ordered data is the most common data on a connected device:
sensor readings, network latency samples, CPU load, frame times,
price feeds.  This module treats arrays as uniformly-spaced
time series.

#### Smoothing & Moving Averages

| Word | Stack | Description |
|---|---|---|
| `TS-SMA` | `( src n window dst -- )` | Simple moving average |
| `TS-EMA` | `( src n alpha dst -- )` | Exponential moving average |
| `TS-EWMA` | `( src n alpha -- last )` | EWMA → single final value |
| `TS-WMA` | `( src n window dst -- )` | Weighted moving average (linear weights) |
| `TS-DEMA` | `( src n alpha dst -- )` | Double EMA (Holt's method for trends) |
| `TS-MEDIAN-FILTER` | `( src n window dst -- )` | Running median (outlier-resistant) |
| `TS-GAUSSIAN-SMOOTH` | `( src n sigma dst -- )` | Gaussian kernel smoothing |

**Tile acceleration for `TS-SMA`:**
Sliding-window sum via tile:  maintain a running `TSUM` over 32
elements, add the new element, subtract the departing element.
For window sizes ≤ 32, the entire window fits in one tile.
This turns O(n × window) into O(n) with tile-constant overhead.

**`TS-EMA` algorithm:**
$y_t = \alpha \cdot x_t + (1-\alpha) \cdot y_{t-1}$.  Sequential
by nature (each output depends on the previous), but
tile-accelerated for the multiply-add step: broadcast α and
(1−α), tile FMA.

#### Differencing & Returns

| Word | Stack | Description |
|---|---|---|
| `TS-DIFF` | `( src n dst -- )` | First differences: dst[i] = src[i+1] − src[i] |
| `TS-DIFF-K` | `( src n k dst -- )` | k-th order differences |
| `TS-PCT-CHANGE` | `( src n dst -- )` | Percentage change: (x[i+1]−x[i])/x[i] |
| `TS-LOG-RETURN` | `( src n dst -- )` | Log return: ln(x[i+1]/x[i]) |
| `TS-CUMSUM` | `( src n dst -- )` | Cumulative sum |
| `TS-CUMPROD` | `( src n dst -- )` | Cumulative product |
| `TS-CUMMIN` | `( src n dst -- )` | Cumulative minimum |
| `TS-CUMMAX` | `( src n dst -- )` | Cumulative maximum |

Differencing and cumulative ops are inherently sequential but
benefit from tile acceleration on the arithmetic step.

#### Trend & Seasonality

| Word | Stack | Description |
|---|---|---|
| `TS-DETREND` | `( src n dst -- )` | Remove linear trend (via `REG-OLS`) |
| `TS-DETREND-MEAN` | `( src n dst -- )` | Remove mean (center data) |
| `TS-AUTOCORR` | `( src n lag -- r )` | Autocorrelation at given lag |
| `TS-AUTOCORR-N` | `( src n max-lag dst -- )` | Autocorrelation function (all lags 0..max-lag) |
| `TS-CROSSCORR` | `( x y n max-lag dst -- )` | Cross-correlation |
| `TS-LAG` | `( src n k dst -- )` | Lag operator: shift data by k positions |
| `TS-ROLLING-STD` | `( src n window dst -- )` | Rolling standard deviation |
| `TS-ROLLING-CORR` | `( x y n window dst -- )` | Rolling correlation |
| `TS-DRAWDOWN` | `( src n dst -- )` | Drawdown from running maximum |
| `TS-MAX-DRAWDOWN` | `( src n -- mdd )` | Maximum drawdown (peak-to-trough) |

**Tile acceleration for `TS-AUTOCORR`:**
Autocorrelation at lag k is a dot product of the series with
itself shifted by k.  `SIMD-DOT-N` on overlapping windows.
The autocorrelation function for max-lag L is L dot products —
each fully tile-accelerated.

#### Anomaly Detection

| Word | Stack | Description |
|---|---|---|
| `TS-ZSCORE` | `( src n dst -- )` | Z-score normalization |
| `TS-OUTLIERS-IQR` | `( src n dst -- m )` | Flag outliers by IQR rule (1.5×IQR) |
| `TS-OUTLIERS-Z` | `( src n threshold dst -- m )` | Flag outliers by z-score |
| `TS-OUTLIERS-MAD` | `( src n threshold dst -- m )` | Flag outliers by modified z-score (MAD-based) |
| `TS-CHANGE-POINTS` | `( src n threshold dst -- m )` | Detect mean-shift change points (CUSUM) |

---

### 5.5  `math/probability.f` — Distributions & Testing

**File:** `math/probability.f`
**Prefix:** `PROB-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `exp.f`, `trig.f`, `stats.f`, `sort.f`

#### Distribution Functions

| Word | Stack | Description |
|---|---|---|
| `PROB-NORMAL-PDF` | `( x mu sigma -- p )` | Normal density |
| `PROB-NORMAL-CDF` | `( x mu sigma -- p )` | Normal cumulative distribution |
| `PROB-NORMAL-INV` | `( p -- z )` | Inverse normal (probit): p → z-score |
| `PROB-STANDARD-PDF` | `( z -- p )` | Standard normal density (μ=0, σ=1) |
| `PROB-STANDARD-CDF` | `( z -- p )` | Standard normal CDF (Φ) |
| `PROB-UNIFORM-PDF` | `( x a b -- p )` | Uniform density on [a, b] |
| `PROB-UNIFORM-CDF` | `( x a b -- p )` | Uniform CDF |
| `PROB-EXPONENTIAL-CDF` | `( x lambda -- p )` | Exponential CDF: 1 − e^(−λx) |
| `PROB-POISSON-PMF` | `( k lambda -- p )` | Poisson probability mass: e^(−λ)·λ^k/k! |
| `PROB-BINOMIAL-PMF` | `( k n p -- prob )` | Binomial probability mass |
| `PROB-CHI2-CDF` | `( x df -- p )` | Chi-squared CDF (series approximation) |
| `PROB-T-CDF` | `( t df -- p )` | Student's t CDF |

**Algorithms:**
- `PROB-NORMAL-CDF`: Rational approximation of $\Phi(z)$.
  Abramowitz & Stegun formula 26.2.17 — 6 coefficients, accurate
  to ~7 decimal digits (far exceeds FP16's ~3.3 digits).  In FP16,
  only 3–4 coefficients are needed.
- `PROB-NORMAL-INV`: Rational approximation of $\Phi^{-1}(p)$.
  Beasley–Springer–Moro algorithm.
- `PROB-CHI2-CDF`, `PROB-T-CDF`: Regularized incomplete beta/gamma
  function via continued fraction or series expansion.  Truncated
  early for FP16 precision.

#### Hypothesis Testing

| Word | Stack | Description |
|---|---|---|
| `PROB-T-TEST-1` | `( src n mu0 -- t-stat p-value )` | One-sample t-test: is mean = μ₀? |
| `PROB-T-TEST-2` | `( x nx y ny -- t-stat p-value )` | Two-sample t-test (Welch's, unequal variance) |
| `PROB-T-TEST-PAIRED` | `( x y n -- t-stat p-value )` | Paired t-test |
| `PROB-CHI2-GOF` | `( observed expected n -- chi2 p-value )` | Chi-squared goodness of fit |
| `PROB-MANN-WHITNEY` | `( x nx y ny -- U p-value )` | Mann-Whitney U test (non-parametric) |
| `PROB-WILCOXON` | `( x y n -- W p-value )` | Wilcoxon signed-rank (paired non-parametric) |
| `PROB-KS-TEST` | `( x y n -- D p-value )` | Kolmogorov-Smirnov two-sample test |
| `PROB-SHAPIRO-WILK` | `( src n -- W p-value )` | Normality test |

**Practical value:**
These aren't academic exercises.  A sensor network node running
KDOS can do `PROB-T-TEST-1` on-device to ask "is this temperature
reading statistically different from baseline?" without round-
tripping to a server.  Network monitoring can use `PROB-MANN-WHITNEY`
to compare latency distributions between two time windows.

#### Confidence Intervals

| Word | Stack | Description |
|---|---|---|
| `PROB-CI-MEAN` | `( src n alpha -- lo hi )` | Confidence interval for mean |
| `PROB-CI-PROPORTION` | `( successes n alpha -- lo hi )` | CI for proportion (Wilson score) |
| `PROB-CI-DIFF-MEANS` | `( x nx y ny alpha -- lo hi )` | CI for difference of means |

---

### 5.6  `math/counting.f` — Combinatorics & Frequency

**File:** `math/counting.f`
**Prefix:** `COMB-`
**Depends on:** `fp16.f` (or integer arithmetic)

| Word | Stack | Description |
|---|---|---|
| `COMB-FACTORIAL` | `( n -- n! )` | Factorial (integer, 64-bit, max n=20) |
| `COMB-CHOOSE` | `( n k -- nCk )` | Binomial coefficient |
| `COMB-PERMUTE` | `( n k -- nPk )` | k-permutations of n |
| `COMB-GCD` | `( a b -- gcd )` | Greatest common divisor |
| `COMB-LCM` | `( a b -- lcm )` | Least common multiple |
| `COMB-POWER-MOD` | `( base exp mod -- result )` | Modular exponentiation |
| `COMB-IS-PRIME?` | `( n -- flag )` | Miller-Rabin primality test |
| `COMB-NEXT-PRIME` | `( n -- p )` | Next prime ≥ n |
| `COMB-LOG-FACTORIAL` | `( n -- ln[n!] )` | Stirling approximation for large n |
| `COMB-LOG-CHOOSE` | `( n k -- ln[nCk] )` | Log binomial coefficient (avoids overflow) |

Integer combinatorics — no tile engine needed, pure scalar.
`COMB-CHOOSE` uses the multiplicative formula
$\binom{n}{k} = \prod_{i=1}^{k} \frac{n-k+i}{i}$ to avoid
factorial overflow.  `COMB-IS-PRIME?` uses the hardware
64×64 multiply for modular exponentiation (4-cycle `MUL`/`MOD`).

---

### 5.7  Inferential Extensions

**File:** `math/advanced-stats.f`
**Prefix:** `ADVS-` (public API), `_AS-` (internal)
**Depends on:** `probability.f`, `stats.f`, `sort.f`, `counting.f`

Direct extensions of the existing inferential pipeline.  These
build on `PROB-STANDARD-CDF`, `PROB-NORMAL-INV`, and the
mixed-precision accumulation already proven in probability.f.

#### Ranking Infrastructure (sort.f extension)

| Word | Stack | Description |
|---|---|---|
| `SORT-RANK` | `( src dst n -- )` | Rank each element (1-based, average ties) |
| `SORT-ARGSORT` | `( src idx n -- )` | Index permutation (stable) |

`SORT-RANK` is the single most important missing building block.
Mann-Whitney, Wilcoxon, Spearman, and Kruskal-Wallis all require
ranking with tie handling.  Algorithm: argsort the data, walk sorted
order assigning ranks, average within tied groups.

#### Effect Sizes

| Word | Stack | Description |
|---|---|---|
| `ADVS-COHENS-D` | `( x nx y ny -- d )` | Cohen's d (pooled SD) |
| `ADVS-HEDGES-G` | `( x nx y ny -- g )` | Bias-corrected Cohen's d |

Trivial arithmetic on means and standard deviations.  Hedges'
correction factor is $1 - 3/(4(n_1+n_2)-9)$, easily computed in
FP32.

#### Additional Confidence Intervals

| Word | Stack | Description |
|---|---|---|
| `PROB-CI-PROPORTION` | `( successes n alpha -- lo hi )` | Wilson score interval |
| `PROB-CI-DIFF-MEANS` | `( x nx y ny alpha -- lo hi )` | CI for difference of means |

`PROB-CI-PROPORTION` uses the Wilson score formula (more accurate
than Wald for small n or extreme p).  `PROB-CI-DIFF-MEANS` is
Welch's t-interval, reusing the existing `_PR-T-CDF` machinery.

#### F-Distribution & ANOVA

| Word | Stack | Description |
|---|---|---|
| `ADVS-F-CDF` | `( f df1 df2 -- p )` | F-distribution CDF |
| `ADVS-ANOVA-1` | `( groups k dst -- F p-value )` | One-way ANOVA (k groups) |

`ADVS-F-CDF`: Wilson-Hilferty approximation — transform F-statistic
to approximate standard normal, then use `PROB-STANDARD-CDF`.
Same trick we used for chi² in `PROB-CHI2-GOF`.  Accurate to
~2 decimal digits for typical df values — well within FP16.

`ADVS-ANOVA-1`: groups is a packed descriptor
`( addr₁ n₁ addr₂ n₂ ... addrₖ nₖ )`.  Computes SSB (between-group)
and SSW (within-group) via `STAT-MEAN` per group + overall mean.
Returns F-statistic and p-value via `ADVS-F-CDF`.

#### Non-Parametric Two-Sample & Paired Tests

| Word | Stack | Description |
|---|---|---|
| `PROB-MANN-WHITNEY` | `( x nx y ny -- U p-value )` | Mann-Whitney U test |
| `PROB-WILCOXON` | `( x y n -- W p-value )` | Wilcoxon signed-rank test |

**`PROB-MANN-WHITNEY`:** Merge both samples, rank with `SORT-RANK`,
sum ranks for group x → R₁.  $U = R_1 - n_1(n_1+1)/2$.  For
n₁+n₂ > 20, approximate with normal:
$z = (U - n_1 n_2/2) / \sqrt{n_1 n_2 (n_1+n_2+1)/12}$,
then `PROB-STANDARD-CDF` for p-value.

**`PROB-WILCOXON`:** Compute differences, drop zeros, rank absolute
values, sum ranks of positive differences → W⁺.  Normal
approximation for n > 20: $z = (W^+ - n(n+1)/4) / \sqrt{n(n+1)(2n+1)/24}$.

#### Multiple Comparison Correction

| Word | Stack | Description |
|---|---|---|
| `ADVS-BONFERRONI` | `( alpha k -- alpha' )` | Bonferroni: α/k |
| `ADVS-HOLM` | `( p-values n alpha dst -- )` | Holm-Bonferroni step-down |

Bonferroni is trivial division.  Holm sorts p-values ascending,
compares each $p_{(i)}$ to $\alpha / (k - i + 1)$, rejects until
first non-rejection.  Both are essential when running multiple
hypothesis tests.

#### Public T-CDF

| Word | Stack | Description |
|---|---|---|
| `PROB-T-CDF` | `( t df -- p )` | Student's t CDF (was internal `_PR-T-CDF`) |

Expose the existing Cornish-Fisher t→z mapping as public API.

---

### 5.8  Non-Parametric & Model Diagnostics

**File:** `math/advanced-stats.f` (continued)
**Depends on:** all of 5.7, `exp.f`

Moderate complexity, high practical value.  These require either
additional approximation algorithms or precomputed tables, but
all are feasible within FP16/FP32 precision.

#### Distribution Tests

| Word | Stack | Description |
|---|---|---|
| `ADVS-KS-TEST` | `( x nx y ny -- D p-value )` | Kolmogorov-Smirnov two-sample test |
| `ADVS-SHAPIRO-WILK` | `( src n -- W p-value )` | Shapiro-Wilk normality test (n ≤ 50) |

**`ADVS-KS-TEST`:** Sort both samples, compute empirical CDFs,
find maximum absolute difference D.  P-value via the Kolmogorov
distribution approximation:
$p \approx 2 \sum_{k=1}^{\infty} (-1)^{k-1} e^{-2k^2 \lambda^2}$
where $\lambda = D \sqrt{n_{eff}}$.  Converges fast — 3–4 terms
suffice for FP16.

**`ADVS-SHAPIRO-WILK`:** Requires precomputed $a_i$ coefficient
table.  For n ≤ 50, this is ~400 bytes stored in ROM.  Compute
$W = (\sum a_i x_{(i)})^2 / \sum (x_i - \bar{x})^2$.  P-value
via log-normal approximation of the W statistic.

#### Rank Correlation

| Word | Stack | Description |
|---|---|---|
| `ADVS-SPEARMAN` | `( x y n -- rho )` | Spearman rank correlation |
| `ADVS-KRUSKAL-WALLIS` | `( groups k -- H p-value )` | Non-parametric ANOVA |

**`ADVS-SPEARMAN`:** Rank both x and y via `SORT-RANK`, then
`STAT-CORRELATION` on the ranks.  Elegant reuse.

**`ADVS-KRUSKAL-WALLIS`:** Rank all observations combined, compute
rank sums per group.  $H = \frac{12}{N(N+1)} \sum \frac{R_j^2}{n_j} - 3(N+1)$.
P-value via chi² approximation with k−1 degrees of freedom
(reuse `PROB-CHI2-GOF`'s Wilson-Hilferty path).

#### Power Analysis

| Word | Stack | Description |
|---|---|---|
| `ADVS-POWER-T-TEST` | `( effect-d alpha power -- n )` | Required sample size for t-test |

Iterative search: for increasing n, compute the non-centrality
parameter $\delta = d\sqrt{n}$, find the critical t-value at α,
compute power from the shifted t-distribution.  Converges in
< 50 iterations for typical inputs.

---

### 5.9  Advanced Modeling

**File:** `math/advanced-stats.f` (continued)
**Depends on:** all of 5.7–5.8, `regression.f`

Substantial implementations that push the platform's precision
limits.  All feasible but require careful FP32 intermediate
arithmetic and convergence control.

#### Logistic Regression

| Word | Stack | Description |
|---|---|---|
| `ADVS-LOGISTIC-FIT` | `( x y n ctx -- )` | Fit binary logistic model via IRLS |
| `ADVS-LOGISTIC-PREDICT` | `( ctx x -- p )` | Predict probability |
| `ADVS-LOGISTIC-COEFF` | `( ctx -- b0 b1 )` | Extract coefficients |

**Algorithm:** Iteratively Reweighted Least Squares (IRLS).
Each iteration is a weighted OLS step — reuses `REG-OLS`
machinery with updated weights from the sigmoid function.
Converges in 5–10 iterations for well-separated data.  All
arithmetic in FP32; sigmoid via `EXP-SIGMOID` (already in exp.f).

#### Multiple Regression

| Word | Stack | Description |
|---|---|---|
| `ADVS-REG-MULTIPLE` | `( X y n p ctx -- )` | p-predictor OLS (normal equations) |
| `ADVS-REG-MULTI-PREDICT` | `( ctx x-vec -- y-hat )` | Predict from predictor vector |
| `ADVS-REG-MULTI-R2` | `( ctx -- r² )` | Multiple R² |

**Algorithm:** Form X'X (p×p) and X'y (p×1) via tile-accelerated
dot products, solve via Gaussian elimination with partial pivoting.
Feasible for p ≤ 8 predictors — the system matrix fits in
< 600 bytes.  All accumulation via `accum.f`, solve in FP32.

#### Bayesian Conjugate Updates

| Word | Stack | Description |
|---|---|---|
| `ADVS-BAYES-BETA-UPDATE` | `( a b successes trials -- a' b' )` | Beta-binomial conjugate update |
| `ADVS-BAYES-NORMAL-UPDATE` | `( mu0 sigma0² x-bar s² n -- mu1 sigma1² )` | Normal-normal conjugate update |

Conjugate Bayesian updating is closed-form arithmetic — no MCMC
needed.  The Beta-binomial posterior is just
$\text{Beta}(a + s, b + n - s)$.  The normal-normal update
combines prior and likelihood precision.  Both are single
expressions in FP32.

#### Survival Analysis

| Word | Stack | Description |
|---|---|---|
| `ADVS-KAPLAN-MEIER` | `( times events n dst -- )` | Kaplan-Meier survival curve |
| `ADVS-KM-MEDIAN` | `( dst n -- median )` | Median survival time from KM curve |

**Algorithm:** Sort event times, compute product-limit estimator
$S(t) = \prod_{t_i \le t} (1 - d_i/n_i)$.  Uses `SORT-FP16`
and simple FP32 running product.  Output is an array of
(time, survival-probability) pairs.

---

### Design Decisions

**Why FP16 for statistics?**

FP16 has only 10 mantissa bits (~3.3 decimal digits).  For a
typical dataset of 100–1000 observations, this is adequate for:
- Means, medians, percentiles (inheriting input precision)
- Correlation coefficients (inherently [−1, +1])
- Z-scores, t-statistics (typically single-digit)
- Normalized data, probabilities [0, 1]

It is *not* adequate for:
- Financial totals with large magnitudes + fine granularity
- Sums of many large values (catastrophic cancellation)

**Mitigation:** The tile engine accumulates reductions (SUM,
SUMSQ, DOT) in FP32 internally.  So `TSUM` over 32 FP16 values
returns an FP32 accumulator value.  We extract this and convert
back only at the final step.  This gives ~7 decimal digits of
accumulation precision despite FP16 operands — comparable to
32-bit float statistics on other platforms.

For applications needing higher precision, the 16.16 fixed-point
path (`fixed.f`) provides 16 fractional bits (~4.8 decimal digits)
with exact integer arithmetic.  Fixed-point stats variants
(`STAT-FX-MEAN`, `STAT-FX-VARIANCE`, etc.) can be added as a
follow-on.

**Why six modules instead of one?**

Modularity.  An application that only needs `STAT-MEAN` and
`STAT-STDDEV` shouldn't pull in hypothesis testing, curve fitting,
and time series.  `REQUIRE stats.f` loads the core.  The others
are opt-in.

---

## Tier 6 — Crypto Wrappers

Expose the MMIO crypto accelerators with clean Forth APIs.

### 6.1  `crypto/sha256.f` — SHA-256

**File:** `crypto/sha256.f`
**Prefix:** `SHA256-`
**Depends on:** BIOS MMIO

| Word | Stack | Description |
|---|---|---|
| `SHA256-INIT` | `( ctx -- )` | Initialize context |
| `SHA256-UPDATE` | `( ctx data len -- )` | Feed data (multi-block streaming) |
| `SHA256-FINAL` | `( ctx hash -- )` | Finalize, write 32-byte hash |
| `SHA256-HASH` | `( data len hash -- )` | One-shot convenience |
| `SHA256-HMAC` | `( key klen data dlen hash -- )` | HMAC-SHA256 |

Hardware: 64 bytes / 64 cycles throughput.

### 6.2  `crypto/sha3.f` — SHA-3 / SHAKE

**File:** `crypto/sha3.f`
**Prefix:** `SHA3-`

| Word | Stack | Description |
|---|---|---|
| `SHA3-256-HASH` | `( data len hash -- )` | SHA3-256 one-shot |
| `SHA3-INIT` | `( ctx mode -- )` | Initialize (mode: SHA3-256, SHAKE-128, SHAKE-256) |
| `SHA3-UPDATE` | `( ctx data len -- )` | Absorb data |
| `SHA3-FINAL` | `( ctx hash len -- )` | Squeeze output |
| `SHAKE-128` | `( data dlen out olen -- )` | SHAKE-128 XOF |
| `SHAKE-256` | `( data dlen out olen -- )` | SHAKE-256 XOF |

Hardware: Keccak-f[1600] at 136 bytes / 41 cycles.

### 6.3  `crypto/aes.f` — AES-256-GCM

**File:** `crypto/aes.f`
**Prefix:** `AES-`

| Word | Stack | Description |
|---|---|---|
| `AES-SET-KEY` | `( key len -- )` | Load key (128 or 256 bit) |
| `AES-GCM-ENCRYPT` | `( iv pt ptlen aad alen ct tag -- )` | Authenticated encrypt |
| `AES-GCM-DECRYPT` | `( iv ct ctlen aad alen pt tag -- flag )` | Decrypt + verify tag |
| `AES-EXPAND-KEY` | `( key len -- )` | Key schedule expansion |

Hardware: 16 bytes / 12 cycles.

### 6.4  `crypto/crc.f` — CRC32 / CRC64

**File:** `crypto/crc.f`
**Prefix:** `CRC-`

| Word | Stack | Description |
|---|---|---|
| `CRC32` | `( data len -- crc )` | CRC32 (ISO 3309) |
| `CRC32C` | `( data len -- crc )` | CRC32-C (Castagnoli, iSCSI) |
| `CRC64` | `( data len -- crc )` | CRC64 |
| `CRC32-UPDATE` | `( crc data len -- crc' )` | Streaming CRC32 |

Hardware: 8 bytes / cycle.

### 6.5  `crypto/random.f` — True Random / CSPRNG

**File:** `crypto/random.f`
**Prefix:** `RNG-`

| Word | Stack | Description |
|---|---|---|
| `RNG-U64` | `( -- u64 )` | Hardware TRNG: 64 random bits |
| `RNG-BYTES` | `( dst n -- )` | Fill buffer with random bytes |
| `RNG-RANGE` | `( lo hi -- n )` | Uniform random in [lo, hi) |
| `RNG-FP16` | `( -- fp16 )` | Random FP16 in [0.0, 1.0) |

### 6.6  `crypto/field.f` — Field Arithmetic (512-bit)

**File:** `crypto/field.f`
**Prefix:** `FIELD-`

Wraps the hardware Field ALU for big-number modular arithmetic.

| Word | Stack | Description |
|---|---|---|
| `FIELD-SET-PRIME` | `( prime-id -- )` | Select prime (0=Curve25519, 1=secp256k1, 2=P-256) |
| `FIELD-LOAD` | `( addr -- )` | Load 256-bit operand A |
| `FIELD-LOAD-B` | `( addr -- )` | Load 256-bit operand B |
| `FIELD-STORE` | `( addr -- )` | Store 256-bit result |
| `FIELD-ADD` | `( -- )` | A = A + B mod p |
| `FIELD-SUB` | `( -- )` | A = A − B mod p |
| `FIELD-MUL` | `( -- )` | A = A × B mod p |
| `FIELD-SQR` | `( -- )` | A = A² mod p |
| `FIELD-INV` | `( -- )` | A = A⁻¹ mod p |
| `FIELD-POW` | `( exp-addr -- )` | A = A^exp mod p |
| `FIELD-CMOV` | `( flag -- )` | Conditional move (constant-time) |
| `FIELD-CEQ` | `( -- flag )` | Constant-time equality test |

### 6.7  `crypto/x25519.f` — X25519 Key Exchange

**File:** `crypto/x25519.f`
**Prefix:** `X25519-`
**Depends on:** `field.f`

| Word | Stack | Description |
|---|---|---|
| `X25519-KEYGEN` | `( privkey pubkey -- )` | Generate keypair |
| `X25519-SHARED` | `( privkey peerpub shared -- )` | Compute shared secret |
| `X25519-BASE` | `( scalar result -- )` | Scalar × base point |

Hardware Montgomery ladder in the Field ALU.

### 6.8  `crypto/ntt.f` — Number Theoretic Transform

**File:** `crypto/ntt.f`
**Prefix:** `NTT-`

| Word | Stack | Description |
|---|---|---|
| `NTT-FORWARD` | `( src dst n -- )` | Forward NTT |
| `NTT-INVERSE` | `( src dst n -- )` | Inverse NTT |
| `NTT-SET-MOD` | `( modulus -- )` | Set NTT modulus |
| `NTT-POLYMUL` | `( a b dst n -- )` | Polynomial multiplication via NTT |

Hardware: 256-point NTT in ~1280 cycles.

### 6.9  `crypto/kem.f` — ML-KEM-512

**File:** `crypto/kem.f`
**Prefix:** `KEM-`

| Word | Stack | Description |
|---|---|---|
| `KEM-KEYGEN` | `( pk sk -- )` | Generate keypair |
| `KEM-ENCAPS` | `( pk ct ss -- )` | Encapsulate shared secret |
| `KEM-DECAPS` | `( sk ct ss -- flag )` | Decapsulate + verify |

Post-quantum key encapsulation, ~500 cycles total.

---

## Tier 7 — Signal Processing

### 7.1  `math/fft.f` — Fast Fourier Transform (FP16)

**File:** `math/fft.f`
**Prefix:** `FFT-`
**Depends on:** `fp16.f`, `trig.f`, `simd.f`

| Word | Stack | Description |
|---|---|---|
| `FFT-FORWARD` | `( re im n -- )` | In-place radix-2 FFT |
| `FFT-INVERSE` | `( re im n -- )` | In-place inverse FFT |
| `FFT-MAGNITUDE` | `( re im mag n -- )` | $\|X[k]\| = \sqrt{re^2 + im^2}$ |
| `FFT-POWER` | `( re im pwr n -- )` | Power spectrum: $re^2 + im^2$ |
| `FFT-CONVOLVE` | `( a b dst n -- )` | Convolution via FFT |
| `FFT-CORRELATE` | `( a b dst n -- )` | Cross-correlation via FFT |

Butterflies use tile FMA for 32-lane parallel twiddle multiply.
Bit-reversal permutation via tile SHUFFLE where possible.

### 7.2  `math/filter.f` — Digital Filters

**File:** `math/filter.f`
**Prefix:** `FILT-`
**Depends on:** `fp16.f`, `simd.f`

| Word | Stack | Description |
|---|---|---|
| `FILT-FIR` | `( input coeff n-taps dst n-out -- )` | FIR filter (tile DOT) |
| `FILT-IIR-BIQUAD` | `( input b0 b1 b2 a1 a2 dst n -- )` | Second-order IIR |
| `FILT-CONV1D` | `( input kernel ksize dst n -- )` | 1D convolution |
| `FILT-MA` | `( input window dst n -- )` | Moving average filter |
| `FILT-MEDIAN` | `( input window dst n -- )` | Median filter |
| `FILT-LOWPASS` | `( input cutoff dst n -- )` | Simple low-pass filter |
| `FILT-HIGHPASS` | `( input cutoff dst n -- )` | Simple high-pass filter |

FIR filters are a natural fit for tile DOT/MAC operations — each
output sample is a dot product of the coefficient vector with a
sliding window of input samples.

---

## Tier 8 — Random & Sampling

### 8.1  `math/prng.f` — Pseudorandom Number Generator

**File:** `math/prng.f`
**Prefix:** `PRNG-`

Deterministic, reproducible PRNG.  Uses xoshiro256** — fast,
high-quality, 256-bit state.  Seed from hardware TRNG or user-
provided seed.

| Word | Stack | Description |
|---|---|---|
| `PRNG-SEED` | `( s0 s1 s2 s3 -- )` | Set 256-bit state |
| `PRNG-SEED-TRNG` | `( -- )` | Seed from hardware TRNG |
| `PRNG-U64` | `( -- u64 )` | Next 64-bit pseudorandom |
| `PRNG-U32` | `( -- u32 )` | Next 32-bit pseudorandom |
| `PRNG-RANGE` | `( lo hi -- n )` | Uniform in [lo, hi) |
| `PRNG-FP16` | `( -- fp16 )` | Uniform [0.0, 1.0) in FP16 |
| `PRNG-GAUSSIAN` | `( -- x )` | Normal(0,1) via Box-Muller (needs trig.f) |
| `PRNG-SHUFFLE` | `( addr n -- )` | Fisher-Yates shuffle |
| `PRNG-FILL-FP16` | `( addr n -- )` | Fill array with random FP16 [0,1) |
| `PRNG-CHOICE` | `( addr n -- val )` | Random element from array |
| `PRNG-BERNOULLI` | `( p -- flag )` | Bernoulli trial with probability p |

---

## Tier 9 — Big Integer & Field Arithmetic

### 9.1  `math/bigint.f` — Arbitrary-Precision Integers

**File:** `math/bigint.f`
**Prefix:** `BIG-`
**Depends on:** `fixed.f` (for shift helpers), optionally `crypto/field.f` for modular ops

Software big integer using arrays of 64-bit limbs.  For numbers beyond
512 bits that exceed the Field ALU's range.

| Word | Stack | Description |
|---|---|---|
| `BIG-ADD` | `( a b dst n -- carry )` | Add n-limb numbers |
| `BIG-SUB` | `( a b dst n -- borrow )` | Subtract n-limb numbers |
| `BIG-MUL` | `( a b dst an bn -- )` | Schoolbook multiply |
| `BIG-DIVMOD` | `( a b q r an bn -- )` | Division with remainder |
| `BIG-SHL` | `( a dst n bits -- )` | Left shift |
| `BIG-SHR` | `( a dst n bits -- )` | Right shift |
| `BIG-CMP` | `( a b n -- -1\|0\|1 )` | Compare |
| `BIG-PRINT` | `( a n -- )` | Print decimal representation |

For modular arithmetic over standard curves (secp256k1, P-256,
Curve25519), prefer the hardware Field ALU via `crypto/field.f` —
hardware does 256×256→512 multiply in a single op.  `bigint.f` is
for cases exceeding 512 bits (RSA-2048, etc.).

---

## Tier 10 — Color & Pixel Math

### 10.1  `math/color.f` — Color Space Conversions

**File:** `math/color.f`
**Prefix:** `COLOR-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `exp.f` (for gamma)

Colors as 3 or 4 FP16 values, or packed integers.

| Word | Stack | Description |
|---|---|---|
| `COLOR-RGB>HSL` | `( r g b -- h s l )` | RGB → HSL |
| `COLOR-HSL>RGB` | `( h s l -- r g b )` | HSL → RGB |
| `COLOR-RGB>HSV` | `( r g b -- h s v )` | RGB → HSV |
| `COLOR-HSV>RGB` | `( h s v -- r g b )` | HSV → RGB |
| `COLOR-SRGB>LINEAR` | `( srgb -- linear )` | sRGB gamma decode |
| `COLOR-LINEAR>SRGB` | `( linear -- srgb )` | sRGB gamma encode |
| `COLOR-BLEND` | `( r1 g1 b1 a1 r2 g2 b2 a2 -- r g b a )` | Alpha-premultiplied blend |
| `COLOR-LERP` | `( c1 c2 t -- c )` | Color interpolation (per-channel) |
| `COLOR-PACK-RGBA` | `( r g b a -- packed )` | Pack 4×FP16 → 32-bit RGBA |
| `COLOR-UNPACK-RGBA` | `( packed -- r g b a )` | Unpack 32-bit RGBA → 4×FP16 |
| `COLOR-PACK-RGB565` | `( r g b -- packed )` | Pack to 16-bit RGB565 |
| `COLOR-NAMED` | `( name-a name-u -- r g b flag )` | CSS named color lookup |
| `COLOR-HEX-PARSE` | `( str len -- r g b flag )` | Parse #RGB / #RRGGBB |
| `COLOR-CONTRAST` | `( r1 g1 b1 r2 g2 b2 -- ratio )` | WCAG contrast ratio |
| `COLOR-LUMINANCE` | `( r g b -- Y )` | Relative luminance |

**SIMD opportunity:** `COLOR-BLEND` over a scanline of 32 pixels
in parallel (8 RGBA quads per tile pass) — relevant for compositing.

**Consumer:** CSS color values, canvas drawing, framebuffer operations,
sprite rendering, image processing.

---

## Tier 11 — Physics & Animation

### 11.1  `math/physics.f` — 2D Physics Primitives

**File:** `math/physics.f`
**Prefix:** `PHYS-`
**Depends on:** `fp16.f`, `vec2.f`, `trig.f`

| Word | Stack | Description |
|---|---|---|
| `PHYS-INTEGRATE` | `( pos vel acc dt -- pos' vel' )` | Velocity Verlet |
| `PHYS-GRAVITY` | `( mass1 mass2 dist -- force )` | Gravitational force |
| `PHYS-SPRING` | `( displacement k -- force )` | Hooke's law |
| `PHYS-DAMPED-SPRING` | `( disp vel k damp dt -- disp' vel' )` | Spring+damper |
| `PHYS-CIRCLE-COLLIDE` | `( x1 y1 r1 x2 y2 r2 -- flag )` | Circle-circle collision |
| `PHYS-RECT-COLLIDE` | `( r1 r2 -- flag )` | AABB collision |
| `PHYS-BOUNCE` | `( vx vy nx ny restitution -- vx' vy' )` | Elastic bounce |

### 11.2  `math/anim.f` — Animation Primitives

**File:** `math/anim.f`
**Prefix:** `ANIM-`
**Depends on:** `fp16.f`, `interp.f`

| Word | Stack | Description |
|---|---|---|
| `ANIM-TWEEN` | `( start end t ease-xt -- val )` | Generic tween |
| `ANIM-SPRING-STEP` | `( ctx dt -- val done? )` | Spring simulation step |
| `ANIM-KEYFRAME` | `( keys n t -- val )` | Keyframe interpolation |
| `ANIM-PATH` | `( points n t -- x y )` | Animate along path |
| `ANIM-SHAKE` | `( amplitude freq t -- offset )` | Screen shake |

---

## Dependency Graph

```
                     ┌─────────────┐
                     │  BIOS/HW    │
                     │ (MMIO, tile │
                     │  engine,    │
                     │  crypto)    │
                     └──────┬──────┘
                            │
              ┌─────────────┼──────────────┐
              │             │              │
        ┌─────┴─────┐ ┌────┴────┐   ┌─────┴─────┐
        │  fp16.f   │ │ fixed.f │   │ crypto/*  │
        │ (tile L0) │ │ (int)   │   │ (MMIO)    │
        └─────┬─────┘ └────┬────┘   └─────┬─────┘
              │             │              │
        ┌─────┴─────┐      │        ┌─────┴─────┐
        │fp16-ext.f │      │        │  field.f  │
        │(cmp,div,  │      │        │  sha*.f   │
        │ sqrt,lerp)│      │        │  aes.f    │
        └─────┬─────┘      │        │  crc.f    │
              │             │        │  random.f │
     ┌────────┼────────┐    │        │  ntt.f    │
     │        │        │    │        │  kem.f    │
┌────┴───┐┌───┴───┐┌───┴──┐│        │  x25519.f │
│ trig.f ││simd.f ││exp.f │├────┐   └───────────┘
└────┬───┘└───┬───┘└───┬──┘│    │
     │        │        │   │    │
     │        │   ┌────┴───┴┐   │
     │        │   │ fp32.f  │   │   ← software FP32 (int ALU only)
     │        │   └────┬────┘   │
     │        │   ┌────┴────┐   │
     │        │   │ accum.f │   │   ← 48.16 cross-tile accumulators
     │        │   └────┬────┘   │
     │        │        │        │
┌────┴───┐┌───┴────┐┌──┴───┐┌──┴─────┐
│ vec2.f ││simd-   ││color.f││ sort.f  │
│ mat2d.f││ext.f   │└───────┘└────┬───┘
│ rect.f │└───┬────┘              │
└────┬───┘    │         ┌─────────┘
     │   ┌────┴─────┐   │
     │   │ stats.f  │◄──┘
     │   │ fft.f    │
     │   │ filter.f │
     │   └──┬───────┘
     │      │
     │   ┌──┴──────────┐
     │   │regression.f │
     │   │timeseries.f │
     │   │probability.f│
     │   └─────────────┘
     │
┌────┴───────────┐
│ interp.f       │
│ physics.f      │
│ anim.f         │
│ bezier.f (✅)  │
└────────────────┘
```

---

## Module Map

```
akashic/
├── math/                          ← Numeric & geometry
│   ├── fp16.f          ✅          Core FP16 tile wrappers
│   ├── fp16-ext.f      ✅          Extended FP16 (cmp, div, sqrt)
│   ├── fixed.f         ✅          16.16 fixed-point
│   ├── bezier.f        ✅          Bézier curves
│   ├── trig.f          ✅  T1.1    Trigonometry (sin/cos/atan)
│   ├── exp.f           ✅  T1.2    Exponentials & logarithms
│   ├── interp.f        ✅  T1.3    Easing & interpolation
│   ├── vec2.f          ✅  T2.1    2D vectors
│   ├── mat2d.f         ✅  T2.2    2×3 affine matrices
│   ├── rect.f          ✅  T2.3    Axis-aligned rectangles
│   ├── fp32.f          ✅  T3.1    Software IEEE 754 single-precision
│   ├── accum.f         ✅  T3.2    Extended-precision accumulators
│   ├── simd.f          ✅  T4.1    32-lane SIMD primitives
│   ├── simd-ext.f      ✅  T4.2    Batch SIMD (N-element arrays)
│   ├── stats.f         ✅  T5.2    Descriptive statistics (core)
│   ├── regression.f    ✅  T5.3    Linear models & curve fitting
│   ├── timeseries.f    ✅  T5.4    Time series analysis
│   ├── probability.f   ✅  T5.5    Distributions & hypothesis testing
│   ├── counting.f      ✅  T5.6    Combinatorics & frequency
│   ├── sort.f          ✅  T5.1    Sorting & rank operations
│   ├── color.f         ✅  T10.1   Color space math
│   ├── fft.f           ❌  T7.1    Fast Fourier transform
│   ├── filter.f        ❌  T7.2    Digital filters (FIR/IIR)
│   ├── prng.f          ❌  T8.1    Pseudorandom (xoshiro256**)
│   ├── bigint.f        ❌  T9.1    Arbitrary-precision integers
│   ├── physics.f       ❌  T11.1   2D physics primitives
│   └── anim.f          ❌  T11.2   Animation primitives
│
├── crypto/                        ← Hardware crypto wrappers
│   ├── sha256.f        ❌  T6.1    SHA-256
│   ├── sha3.f          ❌  T6.2    SHA-3 / SHAKE
│   ├── aes.f           ❌  T6.3    AES-256-GCM
│   ├── crc.f           ❌  T6.4    CRC32/CRC64
│   ├── random.f        ❌  T6.5    TRNG + CSPRNG
│   ├── field.f         ❌  T6.6    512-bit field arithmetic
│   ├── x25519.f        ❌  T6.7    X25519 key exchange
│   ├── ntt.f           ❌  T6.8    Number theoretic transform
│   └── kem.f           ❌  T6.9    ML-KEM-512
│
├── font/               (existing)
├── text/               (existing)
├── css/                (existing)
├── dom/                (existing)
├── markup/             (existing)
├── net/                (existing)
├── utils/              (existing)
└── atproto/            (existing)
```

Legend: ✅ = implemented, ❌ = not started, T#.# = Tier.Item reference

---

## Implementation Stages

### Stage A — Foundation Fixes (Tier 0)
**Effort:** 1–2 sessions  
**Priority:** Immediate — unblocks everything

1. Implement `FP16-DOT` (and `FP16-DOT32` for full-tile variant)
2. Fix `LERP2D` / `MID2D` visibility in bezier.f
3. Add `FX*R` (rounded fixed-point multiply)
4. Write tests for all existing math modules (fp16, fp16-ext, fixed, bezier)
5. Document existing modules in `docs/math/`

### Stage B — Trig & Transcendentals (Tiers 1.1–1.2)
**Effort:** 2–3 sessions  
**Priority:** High — blocks linear algebra and color math  
**Unlocks:** vec2 rotate, mat2d rotate, HSL↔RGB, gamma, sigmoid

1. `trig.f` — sin, cos, sincos, atan2 (polynomial FP16)
2. `exp.f` — exp, ln, exp2, log2, pow, sigmoid, tanh
3. Tests for both
4. `docs/math/trig.md`, `docs/math/exp.md`

### Stage C — Linear Algebra & Geometry (Tiers 2.1–2.3)  ✅ DONE
**Effort:** 2–3 sessions  
**Priority:** High — needed by font composites, CSS transforms, games
**Status:** Completed — `vec2.f`, `mat2d.f`, `rect.f` implemented.

1. ✅ `vec2.f` — 2D vector operations
2. ✅ `mat2d.f` — affine transforms
3. ✅ `rect.f` — AABB rectangles
4. Wire into font/raster.f for composite glyph assembly
5. ✅ Docs: `docs/math/vec2.md`, `docs/math/mat2d.md`, `docs/math/rect.md`

### Stage D — SIMD Batch Operations (Tiers 4.1–4.2)  ✅ DONE
**Effort:** 2–3 sessions  
**Priority:** High — unlocks mass-parallel computation
**Status:** Completed — `simd.f` and `simd-ext.f` implemented.

1. ✅ `simd.f` — raw 32-lane tile wrappers
2. ✅ `simd-ext.f` — N-element chunked operations
3. Benchmark vs scalar loop equivalents
4. ✅ Tests, docs

### Stage D½ — Precision Infrastructure (Tiers 3.1–3.2)  ✅ DONE
**Effort:** 2–3 sessions  
**Priority:** High — required before statistics (Stage F)  
**Unlocks:** Numerically stable mean, variance, regression, R²
**Status:** Completed — `fp32.f` (734 lines) and `accum.f` (200 lines) implemented.

1. ✅ `fp32.f` — software IEEE 754 binary32 (add, sub, mul, div, sqrt,
   comparisons, conversions FP16↔FP32↔FX↔int, ACC>FP32)
2. ✅ `accum.f` — 48.16 fixed-point accumulators for cross-tile
   summation (ACCUM-ADD-TILE, ACCUM-GET-FP32)
3. Tests: fp32 arithmetic accuracy (vs Python `struct.pack('f',...)`),
   accumulator drift tests (sum 10,000 values, compare to exact)
4. `docs/math/fp32.md`, `docs/math/accum.md`

### Stage E — Interpolation & Easing (Tier 1.3)
**Effort:** 1–2 sessions  
**Priority:** Medium — CSS transitions, game animation

1. `interp.f` — all easing functions + cubic-bezier CSS timing
2. Tests, docs

### Stage F — Statistical Library (Tiers 5.1–5.6)
**Effort:** 6–8 sessions  
**Priority:** High — this is the platform differentiator  
**Requires:** Stage D½ (fp32.f, accum.f) for mixed-precision pipeline

All statistics modules use the mixed-precision pipeline:
FP16 data → tile reductions (FP32 accum) → accum.f (48.16 integer) →
fp32.f (final arithmetic) → FP16 output.

1. `sort.f` — sorting & rank operations (foundation for order stats)
2. `stats.f` — descriptive statistics, central tendency, dispersion,
   shape, histogramming, bivariate, online/streaming (Welford)
3. `regression.f` — OLS, polynomial, exponential/power/log fits,
   Theil-Sen robust regression, residual analysis
4. `timeseries.f` — SMA/EMA/WMA, differencing, autocorrelation,
   change-point detection, rolling stats, anomaly detection
5. `probability.f` — Normal/t/chi²/Poisson/binomial distributions,
   t-tests (1-sample, 2-sample, paired), Mann-Whitney, Wilcoxon,
   KS test, Shapiro-Wilk normality, confidence intervals
6. `counting.f` — factorial, binomial coefficients, GCD/LCM,
   primality testing, modular exponentiation
7. Tests for each module (~150 tests total)
8. `docs/math/stats.md`, `docs/math/regression.md`,
   `docs/math/timeseries.md`, `docs/math/probability.md`

### Stage F½ — Advanced Statistics (Tiers 5.7–5.9)
**Effort:** 4–6 sessions  
**Priority:** High — completes the inferential toolkit  
**Requires:** Stage F (probability.f, stats.f, sort.f, counting.f)

Extends the statistical library with non-parametric tests, effect
sizes, ANOVA, model diagnostics, and advanced modeling.

1. ✅ `sort.f` extension — `SORT-ARGSORT`, `SORT-RANK` with avg ties
2. ✅ `advanced-stats.f` (5.7) — effect sizes (Cohen's d, Hedges' g),
   CI-proportion, CI-diff-means, F-CDF, one-way ANOVA,
   Mann-Whitney U, Wilcoxon signed-rank, Bonferroni/Holm,
   public PROB-T-CDF — **33 tests, 0 failures**
3. `advanced-stats.f` (5.8) — KS test, Shapiro-Wilk normality,
   Spearman rank correlation, Kruskal-Wallis, power analysis
4. `advanced-stats.f` (5.9) — logistic regression, multiple
   regression, Bayesian conjugate updates, Kaplan-Meier survival
5. Tests for each phase (~120+ tests)
6. ✅ `docs/math/advanced-stats.md`, `docs/math/sort.md` updated

### Stage G — Crypto Wrappers (Tier 6)
**Effort:** 3–5 sessions  
**Priority:** Medium — thin MMIO wrappers, build as needed

1. `crypto/crc.f` — simplest, good first test of MMIO wrapping pattern
2. `crypto/random.f` — TRNG wrapper (needed by everything else)
3. `crypto/sha256.f` — AT Protocol commit hashing
4. `crypto/sha3.f` — SHAKE for KDF
5. `crypto/aes.f` — authenticated encryption
6. `crypto/field.f` — modular arithmetic
7. `crypto/x25519.f` — key exchange
8. `crypto/ntt.f` — polynomial multiply
9. `crypto/kem.f` — post-quantum KEM
10. Tests for each, docs

### Stage H — Signal Processing (Tiers 7.1–7.2)
**Effort:** 3–4 sessions  
**Priority:** Medium — audio, spectral analysis, convolution

1. `fft.f` — radix-2 FFT with tile-accelerated butterflies
2. `filter.f` — FIR (tile DOT), IIR biquad, moving average
3. Tests, docs

### Stage I — Color & Pixel Math (Tier 10)
**Effort:** 1–2 sessions  
**Priority:** Medium — CSS colors, framebuffer compositing

1. `color.f` — RGB↔HSL/HSV, sRGB gamma, blending, packing
2. Wire into CSS named color and hex parsing
3. Tests, docs

### Stage J — Random & Sampling (Tier 8)
**Effort:** 1–2 sessions  
**Priority:** Low-medium — games, Monte Carlo, testing

1. `prng.f` — xoshiro256\*\*, seeded from TRNG
2. Gaussian, Bernoulli, shuffle, fill
3. Tests, docs

### Stage K — Big Integer (Tier 9)
**Effort:** 2–3 sessions  
**Priority:** Low — only needed for RSA or numbers > 512 bits

1. `bigint.f` — multi-limb add/sub/mul/div
2. Tests, docs

### Stage L — Physics & Animation (Tier 11)
**Effort:** 2–3 sessions  
**Priority:** Low — game/demo oriented

1. `physics.f` — Verlet integration, collision, spring
2. `anim.f` — tweening, keyframes, path animation
3. Tests, docs

---

## Testing Strategy

### Test Infrastructure

Tests run in the Python emulator harness (`local_testing/`).  Each
math module gets a `test_math_<module>.py` file that:

1. Loads the Forth module via the emulator's `REQUIRE`
2. Pushes test inputs onto the data stack
3. Calls the Forth word
4. Pops and verifies outputs against reference values

### Accuracy Standards

| Domain | Tolerance | Rationale |
|---|---|---|
| FP16 arithmetic | ±1 ULP | Hardware tile engine is exact |
| FP16 trig/exp | ±2 ULP | Polynomial approximation error |
| FP16 Newton-Raphson (recip, sqrt) | ±1 ULP | 2 iterations = full mantissa |
| 16.16 fixed-point | Exact | Integer math is deterministic |
| Software FP32 arithmetic | ±1 ULP (FP32) | Round-to-nearest-even, same as hardware FP32 |
| Software FP32 sqrt/recip | ±1 ULP (FP32) | Newton iterations converge to full 23-bit mantissa |
| 48.16 accumulators | Exact (integer) | Accumulation is integer add — no rounding |
| FP32→FP16 conversion | ±1 ULP (FP16) | Round-to-nearest-even narrowing |
| SIMD batch | ±1 ULP per element | Same as scalar, verify lane independence |
| Crypto hashes | Exact match | NIST test vectors |
| Statistics (output) | ±2 ULP (FP16) | Mixed-precision pipeline: only final FP32→FP16 narrows |

### Test Vectors

- **Trig:** Compare against Python `math.sin()` etc., quantized to FP16
- **Crypto:** NIST CAVP test vectors for SHA-256, SHA-3, AES-GCM
- **FFT:** Compare against `numpy.fft` on small arrays
- **Statistics:** Compare against `numpy.mean()`, `numpy.std()` etc.
- **Big integer:** Known factorizations, modular inverses

### Test Counts (Target)

| Module | Min tests | Focus areas |
|---|---|---|
| trig.f | 40 | Quadrant boundaries, special values (0, π/2, π), large angles |
| exp.f | 25 | Overflow, underflow, ln(1), exp(0), negative inputs |
| fp32.f | 50 | All ops vs Python `struct.pack('f',...)`, subnormals, ±inf, NaN, round-to-nearest-even tie-breaking |
| accum.f | 20 | Sum 10,000 FP16 values vs exact, cross-tile accumulation, overflow boundary at 48.16 limits |
| vec2.f | 30 | Zero vectors, unit vectors, perpendicular, normalize edge cases |
| mat2d.f | 30 | Identity, composition, inversion, determinant near zero |
| simd.f | 40 | Full-tile, partial tile, boundary values in each lane |
| sort.f | 25 | Already sorted, reverse sorted, duplicates, ties, quickselect edge cases |
| stats.f | 40 | Empty/single-element arrays, constant values, known distributions, online merge |
| regression.f | 30 | Perfect fit, no correlation, outlier sensitivity, polynomial degree edge cases |
| timeseries.f | 30 | Constant series, trending, seasonal, step changes, window boundary cases |
| probability.f | 81 ✅ | Distribution tails, p=0/1, extreme z-scores, small sample t-tests, CDF round-trip, hypothesis tests, CI |
| counting.f | 50 ✅ | Factorial overflow at n=21, C(n,0), C(n,n), primality of known primes/composites |
| Each crypto module | 20+ | NIST vectors, empty input, streaming, partial blocks |
| color.f | 25 | Boundary colors (black, white, primaries), round-trip conversions |

---

## Hardware Reference

Quick reference for implementers — key MMIO addresses, tile opcodes,
and hardware capabilities.

### Tile Engine Modes (TMODE CSR 0x14)

| Value | Description |
|---|---|
| `FP16-MODE` | 16-bit float, 32 lanes, FP32 accumulation for reduction |
| `BF16-MODE` | 16-bit bfloat, 32 lanes |
| `I8-MODE` | 8-bit signed integer, 64 lanes |
| `U8-MODE` | 8-bit unsigned, 64 lanes |
| `I16-MODE` | 16-bit signed integer, 32 lanes |
| `I32-MODE` | 32-bit signed integer, 16 lanes |
| `I64-MODE` | 64-bit signed integer, 8 lanes |

### Tile Instructions

| Instruction | Opcode | Description |
|---|---|---|
| `TADD` | | dst = src0 + src1 |
| `TSUB` | | dst = src0 − src1 |
| `TMUL` | | dst = src0 × src1 |
| `TFMA` | | dst += src0 × src1 |
| `TMAC` | | acc += src0 × src1 |
| `TDOT` | | 2-way dot product |
| `TDOTACC` | | 4-way dot → accumulator |
| `TEMIN` | | dst = min(src0, src1) |
| `TEMAX` | | dst = max(src0, src1) |
| `TSUM` | | acc = Σ src0[i] |
| `TSUMSQ` | | acc = Σ src0[i]² |
| `TRMIN` | | acc = min(src0[i]) |
| `TRMAX` | | acc = max(src0[i]) |
| `TMINIDX` | | acc = argmin(src0[i]) |
| `TMAXIDX` | | acc = argmax(src0[i]) |
| `TL1NORM` | | acc = Σ|src0[i]| |
| `TPOPCNT` | | acc = popcount(src0) |
| `TTRANS` | | 8×8 transpose |
| `TSHUFFLE` | | permute by index tile |
| `TPACK` | | narrow elements |
| `TUNPACK` | | widen elements |
| `TRROT` | | rotate right |
| `TZERO` | | zero destination tile |
| `TLOADC` | | load constant tile |
| `TVSHR` / `TVSHL` | | per-element shift |
| `TVSEL` | | per-lane conditional select |
| `TVCLZ` | | per-element count leading zeros |
| `TLOAD2D` / `TSTORE2D` | | strided 2D access |

### Crypto MMIO Register Base Addresses

| Peripheral | Purpose |
|---|---|
| AES-GCM | KEY, IV, PT/CT, AAD, TAG, STATUS, CTRL |
| SHA-256 | DATA, STATE, CMD, STATUS |
| SHA-3 | DATA, STATE, RATE, MODE, CMD, STATUS |
| CRC | DATA, POLY, INIT, MODE, RESULT |
| TRNG | DATA, STATUS |
| Field ALU | A[0:3], B[0:3], PRIME, OP, STATUS, RESULT[0:3] |
| NTT | DATA, MOD, LEN, CMD, STATUS |
| ML-KEM | PK, SK, CT, SS, CMD, STATUS |

### Memory Budget for Math

| Component | Allocation | Notes |
|---|---|---|
| Tile scratch (3 tiles) | 192 B HBW | Already allocated by fp16.f |
| SIMD working tiles (8) | 512 B HBW | For batch operations |
| FFT twiddle table (256-pt) | 1 KiB HBW | Pre-computed sin/cos |
| Stats scratch | 512 B HBW | Partial sums, histogram bins, online contexts |
| Accumulator contexts | 64 B any | 4 × accum.f contexts (16 B each) |
| FP32 scratch | 32 B any | Temp cells for software FP32 intermediates |
| PRNG state | 32 B any | 4 × 64-bit xoshiro state |
| SHA/AES contexts | 256 B each | Hash state + buffer |
| Field ALU operands | 128 B | 2 × 512-bit values |
| **Total new HBW** | **~2.5 KiB** | Out of 3 MiB available |

The math library's HBW footprint is negligible relative to the
3 MiB available.

---

## Cross-Library Integration Points

Once the math tier is built, these existing libraries gain new
capabilities:

| Existing Library | New Math Dependency | What It Enables |
|---|---|---|
| `font/raster.f` | vec2, mat2d | Composite glyph assembly with affine transforms |
| `font/raster.f` | bezier.f → raster bridge | Proper cubic glyph outlines (currently linearized) |
| `css/css.f` | color.f | `hsl()`, `rgb()`, color math, computed colors |
| `css/css.f` | interp.f | `cubic-bezier()` timing functions for transitions |
| `css/bridge.f` | interp.f, color.f | Animated style interpolation |
| `dom/dom.f` | rect.f | Layout bounding boxes, hit testing |
| `atproto/repo.f` | crypto/sha256.f | Commit hash verification |
| `atproto/session.f` | crypto/aes.f | Token encryption at rest |
| `net/http.f` | crypto/sha256.f, aes.f | HTTPS/TLS support foundation |
| `net/ws.f` | crypto/sha256.f | WebSocket handshake hash |
| `cbor/dag-cbor.f` | crypto/sha256.f | CID content hashing |
| _any Forth app_ | prng.f, stats.f, trig.f | General-purpose math toolkit |

---

## Summary

The Megapad-64 has more math hardware than the current Akashic
libraries expose by an order of magnitude.  This roadmap plans
~27 new modules across pure math, precision infrastructure, SIMD
exploitation, statistics, crypto, signal processing, and
application-level numeric tools.  The estimated total effort is
30–40 sessions.

The precision strategy is **mixed-precision**: data lives as FP16
for compactness and 32-lane SIMD throughput; tile reductions produce
FP32 accumulators; cross-tile accumulation uses 48.16 integer
arithmetic (via `accum.f`); and final-stage computation (division,
square root, R²) uses software FP32 (via `fp32.f`).  This gives
~15 decimal digits for intermediate sums and ~7.2 decimal digits
for final results — more than enough for serious statistics, while
keeping the inner loop on the tile engine.

The flagship is the statistical library (Tier 5, Stage F) — six
modules spanning descriptive statistics, regression, time series
analysis, probability distributions, and hypothesis testing, all
tile-accelerated with mixed-precision accumulation.  Most embedded
platforms have nothing remotely like this.  A device that can run a
t-test or compute autocorrelations on-chip is genuinely
differentiated.

The guiding principle: if the hardware can do it in silicon, wrap
it in Forth.  Every idle accelerator is a missed opportunity.
