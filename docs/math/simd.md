# akashic-simd — 32-Lane FP16 SIMD Primitives for KDOS / Megapad-64

Tile-width SIMD operations on 32-element FP16 arrays in HBW math RAM.
Exposes the full 32-lane width of the Megapad-64 tile engine for
data-parallel workloads.

```forth
REQUIRE simd.f
```

`PROVIDED akashic-simd` — safe to include multiple times.
Auto-loads `fp16.f` via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Tile Buffers](#tile-buffers)
- [Binary Arithmetic](#binary-arithmetic)
- [Unary Operations](#unary-operations)
- [Broadcast Operations](#broadcast-operations)
- [Reductions](#reductions)
- [Clamping](#clamping)
- [Memory Operations](#memory-operations)
- [Strided 2D Access](#strided-2d-access)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Tile-width data** | All operations work on exactly 32 FP16 values (64 bytes). |
| **HBW-resident** | Source and destination addresses must be 64-byte aligned tile buffers in HBW math RAM. |
| **PREFIX convention** | All public words use the `SIMD-` prefix. Internal helpers use `_SIMD-`. |
| **Not re-entrant** | Shared scratch tiles mean concurrent callers would collide. |
| **FP16-MODE** | Every operation sets the tile engine to FP16 mode before executing. |

---

## Tile Buffers

### SIMD-ALLOT

```forth
SIMD-ALLOT  ( -- addr )
```

Allocate a new 64-byte tile buffer in HBW math RAM.
Returns a 64-byte aligned address suitable for all SIMD operations.

```forth
SIMD-ALLOT CONSTANT my-tile
my-tile SIMD-ZERO                  \ zero the tile
my-tile 0x3C00 SIMD-FILL          \ fill with 1.0
```

---

## Binary Arithmetic

All binary words have the stack effect `( src0 src1 dst -- )`.
Each operates elementwise on all 32 FP16 lanes in parallel.

| Word | Operation |
|---|---|
| `SIMD-ADD` | $\text{dst}[i] = \text{src0}[i] + \text{src1}[i]$ |
| `SIMD-SUB` | $\text{dst}[i] = \text{src0}[i] - \text{src1}[i]$ |
| `SIMD-MUL` | $\text{dst}[i] = \text{src0}[i] \times \text{src1}[i]$ |
| `SIMD-FMA` | $\text{dst}[i] \mathrel{+}= \text{src0}[i] \times \text{src1}[i]$ |
| `SIMD-MAC` | Multiply-accumulate into hardware accumulator |
| `SIMD-MIN` | $\text{dst}[i] = \min(\text{src0}[i],\ \text{src1}[i])$ |
| `SIMD-MAX` | $\text{dst}[i] = \max(\text{src0}[i],\ \text{src1}[i])$ |

```forth
SIMD-ALLOT CONSTANT a
SIMD-ALLOT CONSTANT b
SIMD-ALLOT CONSTANT c
a b c SIMD-ADD     \ c[i] = a[i] + b[i], all 32 lanes
```

---

## Unary Operations

| Word | Stack | Operation |
|---|---|---|
| `SIMD-ABS` | `( src dst -- )` | $\text{dst}[i] = |\text{src}[i]|$ — clear sign bit on all 32 lanes. |
| `SIMD-NEG` | `( src dst -- )` | $\text{dst}[i] = -\text{src}[i]$ — flip sign bit on all 32 lanes. |

`src` and `dst` may be the same buffer for in-place operation.

---

## Broadcast Operations

### SIMD-SCALE

```forth
SIMD-SCALE  ( src scalar dst -- )
```

Multiply all 32 elements of `src` by `scalar` (FP16), store in `dst`:

$$\text{dst}[i] = \text{src}[i] \times s$$

Internally broadcasts `scalar` into a scratch tile, then uses `TMUL`.

---

## Reductions

Reduction operations collapse 32 elements into a single scalar.
The result is an FP32 bit pattern from the hardware accumulator
(except `SIMD-ARGMIN` and `SIMD-ARGMAX` which return an integer index).

| Word | Stack | Operation |
|---|---|---|
| `SIMD-SUM` | `( src -- sum )` | $\sum_{i=0}^{31} \text{src}[i]$ — uses `TSUM` |
| `SIMD-SUMSQ` | `( src -- sumsq )` | $\sum_{i=0}^{31} \text{src}[i]^2$ — uses `TSUMSQ` |
| `SIMD-DOT` | `( src0 src1 -- acc )` | $\sum_{i=0}^{31} \text{src0}[i] \cdot \text{src1}[i]$ — uses `TDOT` |
| `SIMD-RMIN` | `( src -- min )` | $\min(\text{src}[i])$ — uses `TRMIN` |
| `SIMD-RMAX` | `( src -- max )` | $\max(\text{src}[i])$ — uses `TRMAX` |
| `SIMD-ARGMIN` | `( src -- index )` | Index of minimum element — uses `TMINIDX` |
| `SIMD-ARGMAX` | `( src -- index )` | Index of maximum element — uses `TMAXIDX` |
| `SIMD-L1NORM` | `( src -- norm )` | $\sum_{i=0}^{31} |\text{src}[i]|$ — uses `TL1NORM` |
| `SIMD-POPCNT` | `( src -- cnt )` | Population count — uses `TPOPCNT` |

```forth
my-tile SIMD-SUM .       \ print sum of all 32 elements (FP32)
a b SIMD-DOT .            \ dot product of two tiles (FP32)
```

---

## Clamping

### SIMD-CLAMP

```forth
SIMD-CLAMP  ( src lo hi dst -- )
```

Clamp all 32 lanes to the range $[\text{lo}, \text{hi}]$:

$$\text{dst}[i] = \min(\max(\text{src}[i],\ \text{lo}),\ \text{hi})$$

`lo` and `hi` are FP16 scalars (broadcast internally).
Uses two tile ops: `TEMAX` (clamp below) then `TEMIN` (clamp above).

---

## Memory Operations

| Word | Stack | Description |
|---|---|---|
| `SIMD-FILL` | `( dst val -- )` | Write `val` (FP16) to all 32 lanes. |
| `SIMD-ZERO` | `( dst -- )` | Zero the entire 64-byte tile. |
| `SIMD-COPY` | `( src dst -- )` | Copy 64 bytes from `src` to `dst`. |

```forth
SIMD-ALLOT CONSTANT buf
buf 0x4000 SIMD-FILL   \ fill with 2.0
```

---

## Strided 2D Access

### SIMD-LOAD2D

```forth
SIMD-LOAD2D  ( base stride rows dst -- )
```

Load strided 2D data into a tile buffer. Reads `rows` row segments
starting at `base`, with `stride` bytes between row starts, packing
them sequentially into `dst`.

### SIMD-STORE2D

```forth
SIMD-STORE2D  ( src base stride rows -- )
```

Write tile data back to strided memory locations. The inverse of
`SIMD-LOAD2D`.

---

## Internals

| Word | Purpose |
|---|---|
| `_SIMD-S0` through `_SIMD-S7` | Eight scratch tile VARIABLEs (512 bytes HBW total) |
| `_SIMD-SETUP-BIN` | `( src0 src1 dst -- )` — set FP16-MODE, point TSRC0/TSRC1/TDST |
| `_SIMD-SETUP-UNI` | `( src dst -- )` — set FP16-MODE, point TSRC0/TDST |
| `_SIMD-INIT-TILES` | Allocate and zero all scratch tiles at load time |

---

## Quick Reference

```
SIMD-ADD      ( src0 src1 dst -- )    SIMD-DOT      ( src0 src1 -- acc )
SIMD-SUB      ( src0 src1 dst -- )    SIMD-RMIN     ( src -- min )
SIMD-MUL      ( src0 src1 dst -- )    SIMD-RMAX     ( src -- max )
SIMD-FMA      ( src0 src1 dst -- )    SIMD-ARGMIN   ( src -- index )
SIMD-MAC      ( src0 src1 dst -- )    SIMD-ARGMAX   ( src -- index )
SIMD-MIN      ( src0 src1 dst -- )    SIMD-L1NORM   ( src -- norm )
SIMD-MAX      ( src0 src1 dst -- )    SIMD-POPCNT   ( src -- cnt )
SIMD-ABS      ( src dst -- )          SIMD-CLAMP    ( src lo hi dst -- )
SIMD-NEG      ( src dst -- )          SIMD-FILL     ( dst val -- )
SIMD-SCALE    ( src scalar dst -- )   SIMD-ZERO     ( dst -- )
SIMD-SUM      ( src -- sum )          SIMD-COPY     ( src dst -- )
SIMD-SUMSQ    ( src -- sumsq )        SIMD-ALLOT    ( -- addr )
SIMD-LOAD2D   ( base stride rows dst -- )
SIMD-STORE2D  ( src base stride rows -- )
```
