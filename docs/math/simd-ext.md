# akashic-simd-ext — Batch SIMD for N-Element Arrays on KDOS / Megapad-64

Extends `simd.f` to handle FP16 arrays of arbitrary length.
Each `*-N` word automatically chunks the input into 32-element tiles,
processes full tiles via the tile engine, and handles the remainder
with zero-padded scratch buffers.

```forth
REQUIRE simd-ext.f
```

`PROVIDED akashic-simd-ext` — safe to include multiple times.
Auto-loads `simd.f` and `accum.f` (and transitively `fp16.f`, `fp32.f`)
via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Binary Array Operations](#binary-array-operations)
- [Scaling](#scaling)
- [Reductions](#reductions)
- [BLAS-1 Operations](#blas-1-operations)
- [Normalization](#normalization)
- [Unary Array Operations](#unary-array-operations)
- [Memory Operations](#memory-operations)
- [Tile Chunking Strategy](#tile-chunking-strategy)
- [Mixed-Precision Pipeline](#mixed-precision-pipeline)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Automatic chunking** | All `*-N` words process 32 elements per tile op, handle remainder with zero-padded partial tiles. |
| **Mixed-precision reductions** | Reduction results use `accum.f` for 48.16 fixed-point cross-tile accumulation, returning FP32 results. |
| **Zero-copy full tiles** | Full 32-element chunks are processed directly from the source buffer — no copying. |
| **Safe remainder** | Partial tiles (< 32 elements) are copied to scratch buffers, zero-padded, processed, then only the valid elements are written back. |
| **Shared prefix** | Uses the same `SIMD-` prefix as `simd.f` — the `*-N` suffix distinguishes batch variants. |

---

## Binary Array Operations

All binary `*-N` words have the stack effect `( src0 src1 dst n -- )`.
Each operates elementwise on `n` FP16 values.

| Word | Operation |
|---|---|
| `SIMD-ADD-N` | $\text{dst}[i] = \text{src0}[i] + \text{src1}[i]$ |
| `SIMD-SUB-N` | $\text{dst}[i] = \text{src0}[i] - \text{src1}[i]$ |
| `SIMD-MUL-N` | $\text{dst}[i] = \text{src0}[i] \times \text{src1}[i]$ |

```forth
\ Add 100 elements: c[i] = a[i] + b[i]
a b c 100 SIMD-ADD-N
```

---

## Scaling

### SIMD-SCALE-N

```forth
SIMD-SCALE-N  ( src scalar dst n -- )
```

Multiply `n` elements by a broadcast scalar:

$$\text{dst}[i] = \text{src}[i] \times s, \quad i = 0 \ldots n{-}1$$

The scalar is broadcast into a scratch tile once and reused for all chunks.

---

## Reductions

Reduction operations collapse `n` elements to a single FP32 result.
Cross-tile accumulation uses `accum.f` (48.16 fixed-point) for
numerical stability across hundreds of tiles.

| Word | Stack | Operation |
|---|---|---|
| `SIMD-DOT-N` | `( src0 src1 n -- acc )` | $\sum_{i=0}^{n-1} \text{src0}[i] \cdot \text{src1}[i]$ |
| `SIMD-SUM-N` | `( src n -- sum )` | $\sum_{i=0}^{n-1} \text{src}[i]$ |
| `SIMD-SUMSQ-N` | `( src n -- sumsq )` | $\sum_{i=0}^{n-1} \text{src}[i]^2$ |
| `SIMD-MIN-N` | `( src n -- min )` | $\min(\text{src}[i])$ — result is FP16 |
| `SIMD-MAX-N` | `( src n -- max )` | $\max(\text{src}[i])$ — result is FP16 |

```forth
\ Sum 1000 elements with mixed-precision accumulation
data-ptr 1000 SIMD-SUM-N .   \ prints FP32 sum
```

### Precision Notes

- `SIMD-SUM-N`, `SIMD-SUMSQ-N`, `SIMD-DOT-N` all Use the mixed-precision
  pipeline: `TSUM`/`TSUMSQ`/`TDOT` → FP32 per tile → `ACCUM-ADD-TILE`
  → 48.16 running sum → `ACCUM-GET-FP32` final result.
- `SIMD-MIN-N`, `SIMD-MAX-N` use `TRMIN`/`TRMAX` per tile, then
  scalar `FP16-MIN`/`FP16-MAX` across tile results. No precision loss.

---

## BLAS-1 Operations

### SIMD-SAXPY-N

```forth
SIMD-SAXPY-N  ( a x y dst n -- )
```

Standard BLAS-1 SAXPY operation:

$$\text{dst}[i] = a \times x[i] + y[i]$$

`a` is an FP16 scalar. Internally: broadcast `a` into a scratch tile,
`TMUL` (x × a) → scratch, `TADD` (scratch + y) → dst. Two tile ops
per 32-element chunk.

---

## Normalization

### SIMD-NORM-N

```forth
SIMD-NORM-N  ( src n -- norm )
```

L2 norm (Euclidean length) of `n` elements:

$$\|\text{src}\|_2 = \sqrt{\sum_{i=0}^{n-1} \text{src}[i]^2}$$

Returns an FP32 result. Uses `SIMD-SUMSQ-N` then `FP32-SQRT`.

### SIMD-NORMALIZE-N

```forth
SIMD-NORMALIZE-N  ( src dst n -- )
```

Normalize array to unit length:

$$\text{dst}[i] = \frac{\text{src}[i]}{\|\text{src}\|_2}$$

If the source has zero length, `dst` is zeroed. Otherwise computes
$1/\|\text{src}\|$ in FP32, narrows to FP16, and uses `SIMD-SCALE-N`.

---

## Unary Array Operations

| Word | Stack | Operation |
|---|---|---|
| `SIMD-ABS-N` | `( src dst n -- )` | $\text{dst}[i] = |\text{src}[i]|$ |
| `SIMD-NEG-N` | `( src dst n -- )` | $\text{dst}[i] = -\text{src}[i]$ |
| `SIMD-CLAMP-N` | `( src lo hi dst n -- )` | Clamp to $[\text{lo}, \text{hi}]$ |

`SIMD-CLAMP-N` broadcasts `lo` and `hi` (FP16 scalars) and applies
per-tile `SIMD-CLAMP` with automatic chunking.

---

## Memory Operations

| Word | Stack | Description |
|---|---|---|
| `SIMD-FILL-N` | `( dst val n -- )` | Write `val` (FP16) to `n` elements. |
| `SIMD-ZERO-N` | `( dst n -- )` | Zero `n × 2` bytes. |
| `SIMD-COPY-N` | `( src dst n -- )` | Copy `n` FP16 values (n × 2 bytes). |

---

## Tile Chunking Strategy

Every `*-N` operation follows this pattern:

1. **Full tiles:** While `remaining ≥ 32`, process directly from the
   source buffer (zero-copy). Advance pointer by 64 bytes, decrement
   count by 32.

2. **Remainder:** If `remaining > 0` and `remaining < 32`:
   - Copy source elements to a zero-padded scratch tile
   - Execute the tile operation on the scratch tile
   - Copy only the valid elements from the result tile to the
     destination

This ensures correct results regardless of array alignment or
length while maximizing throughput for the common case
(large arrays that are multiples of 32).

---

## Mixed-Precision Pipeline

Reduction `*-N` words use the full mixed-precision pipeline from
Tier 3:

```
FP16 data (src)
    ↓  TSUM / TSUMSQ / TDOT  (per 32-element tile)
FP32 accumulator (ACC@)
    ↓  ACCUM-ADD-TILE  (accum.f)
48.16 fixed-point running sum  (exact integer accumulation)
    ↓  ACCUM-GET-FP32
FP32 final result
```

This gives ~15 decimal digits of intermediate precision for sums
across thousands of elements, avoiding the catastrophic cancellation
that would occur with naive FP16 addition.

---

## Quick Reference

```
SIMD-ADD-N       ( src0 src1 dst n -- )      SIMD-DOT-N       ( src0 src1 n -- acc )
SIMD-SUB-N       ( src0 src1 dst n -- )      SIMD-SUM-N       ( src n -- sum )
SIMD-MUL-N       ( src0 src1 dst n -- )      SIMD-SUMSQ-N     ( src n -- sumsq )
SIMD-SCALE-N     ( src scalar dst n -- )      SIMD-MIN-N       ( src n -- min )
SIMD-SAXPY-N     ( a x y dst n -- )           SIMD-MAX-N       ( src n -- max )
SIMD-NORM-N      ( src n -- norm )            SIMD-CLAMP-N     ( src lo hi dst n -- )
SIMD-NORMALIZE-N ( src dst n -- )             SIMD-FILL-N      ( dst val n -- )
SIMD-ABS-N       ( src dst n -- )             SIMD-ZERO-N      ( dst n -- )
SIMD-NEG-N       ( src dst n -- )             SIMD-COPY-N      ( src dst n -- )
```
