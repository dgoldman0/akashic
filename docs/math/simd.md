# akashic-simd — Multi-Mode SIMD Primitives for KDOS / Megapad-64

Full-width SIMD operations via the Megapad-64 tile engine.  The tile
engine is a 512-bit (64-byte) SIMD unit supporting six element-width
modes: 8/16/32/64-bit integers and FP16/BF16 floats.

```forth
REQUIRE simd.f
```

`PROVIDED akashic-simd` — safe to include multiple times.
Auto-loads `fp16.f` via REQUIRE.

---

## Table of Contents

- [Tile Engine Modes](#tile-engine-modes)
- [Design Principles](#design-principles)
- [Tile Buffers](#tile-buffers)
- [Mode Words](#mode-words)
- [Mode-Agnostic API (TILE- prefix)](#mode-agnostic-api-tile--prefix)
  - [Elementwise Arithmetic](#elementwise-arithmetic)
  - [Bitwise Operations](#bitwise-operations)
  - [Unary Operations](#unary-operations)
  - [Reductions](#reductions)
  - [Utility / Memory](#utility--memory)
  - [Fill Helpers](#fill-helpers)
- [FP16 Convenience API (SIMD- prefix)](#fp16-convenience-api-simd--prefix)
  - [Binary Arithmetic](#binary-arithmetic)
  - [Unary Operations (FP16)](#unary-operations-fp16)
  - [Broadcast Operations](#broadcast-operations)
  - [Reductions (FP16)](#reductions-fp16)
  - [Clamping](#clamping)
  - [Memory Operations](#memory-operations)
  - [Strided 2D Access](#strided-2d-access)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Tile Engine Modes

The TMODE CSR (`0x14`) controls element interpretation:

| EW | Mode | Lanes | TMODE | Description |
|----|------|------:|------:|-------------|
| 0 | **U8** | 64 | `0x00` | Unsigned 8-bit |
| 0 | **I8** | 64 | `0x10` | Signed 8-bit |
| 1 | **U16** | 32 | `0x01` | Unsigned 16-bit |
| 1 | **I16** | 32 | `0x11` | Signed 16-bit |
| 2 | **U32** | 16 | `0x02` | Unsigned 32-bit |
| 2 | **I32** | 16 | `0x12` | Signed 32-bit |
| 3 | **U64** | 8 | `0x03` | Unsigned 64-bit |
| 3 | **I64** | 8 | `0x13` | Signed 64-bit |
| 4 | **FP16** | 32 | `0x04` | IEEE 754 half-precision |
| 5 | **BF16** | 32 | `0x05` | bfloat16 |

**TMODE bit layout:**

```
Bit:  7  6     5       4      3  2  1  0
      R  RND   SAT     SGN    R  EW EW EW
```

| Bits | Field | Meaning |
|------|-------|---------|
| `[2:0]` | EW | Element width: 0=8b, 1=16b, 2=32b, 3=64b, 4=FP16, 5=BF16 |
| `[4]` | Signed | 0=unsigned, 1=signed (affects comparisons, shifts) |
| `[5]` | Saturate | 0=wrapping, 1=saturating (ADD/SUB clamp on overflow) |
| `[6]` | Rounding | 0=truncate, 1=round-to-nearest (for VSHR only) |

---

## Design Principles

| Principle | Detail |
|---|---|
| **Two-layer API** | Mode-agnostic `TILE-` ops (caller sets mode) + FP16 convenience `SIMD-` ops (sets FP16 mode). |
| **64-byte tiles** | All operations work on exactly 64 bytes — lane count depends on mode. |
| **HBW-resident** | Tile addresses must be 64-byte aligned buffers in HBW math RAM. |
| **Caller sets mode** | `TILE-` operations require the caller to set mode first via `U8-MODE`, `U16-MODE`, etc. |
| **FP16-MODE auto** | `SIMD-` operations set `FP16-MODE` automatically before executing. |
| **Not re-entrant** | Shared scratch tiles mean concurrent callers would collide. |

---

## Tile Buffers

### SIMD-ALLOT

```forth
SIMD-ALLOT  ( -- addr )
```

Allocate a new 64-byte tile buffer in HBW math RAM.
Returns a 64-byte aligned address suitable for all tile/SIMD operations.

```forth
SIMD-ALLOT CONSTANT my-tile
my-tile TILE-ZERO                  \ zero the tile
U8-MODE  my-tile 42 TILE-FILL-U8  \ fill with 42
```

---

## Mode Words

Convenience wrappers around `n TMODE!`.

| Word | TMODE | Lanes | Description |
|------|------:|------:|-------------|
| `U8-MODE` | `0x00` | 64 | Unsigned 8-bit |
| `I8-MODE` | `0x10` | 64 | Signed 8-bit |
| `U8S-MODE` | `0x20` | 64 | Unsigned 8-bit, saturating |
| `I8S-MODE` | `0x30` | 64 | Signed 8-bit, saturating |
| `U16-MODE` | `0x01` | 32 | Unsigned 16-bit |
| `I16-MODE` | `0x11` | 32 | Signed 16-bit |
| `U16S-MODE` | `0x21` | 32 | Unsigned 16-bit, saturating |
| `I16S-MODE` | `0x31` | 32 | Signed 16-bit, saturating |
| `U32-MODE` | `0x02` | 16 | Unsigned 32-bit |
| `I32-MODE` | `0x12` | 16 | Signed 32-bit |
| `U64-MODE` | `0x03` | 8 | Unsigned 64-bit |
| `I64-MODE` | `0x13` | 8 | Signed 64-bit |
| `FP16-MODE` | `0x04` | 32 | IEEE FP16 (BIOS word) |
| `BF16-MODE` | `0x05` | 32 | bfloat16 (BIOS word) |

> You can also use raw `n TMODE!` for any combination, e.g.
> `0x60 TMODE!` for unsigned 8-bit with rounding+saturating.

```forth
U8-MODE                         \ 64 × u8 lanes
_a _b _c TILE-ADD               \ 64-wide unsigned byte add
U16S-MODE                       \ 32 × u16, saturating
_a _b _c TILE-ADD               \ saturates instead of wrapping
```

---

## Mode-Agnostic API (TILE- prefix)

These operations do NOT set tile mode — the caller must set mode
first.  The same hardware instructions work across all element widths.

### Elementwise Arithmetic

All binary words: `( src0 src1 dst -- )`

| Word | Operation | Notes |
|---|---|---|
| `TILE-ADD` | $\text{dst}[i] = \text{src0}[i] + \text{src1}[i]$ | Saturates if SAT bit set |
| `TILE-SUB` | $\text{dst}[i] = \text{src0}[i] - \text{src1}[i]$ | Saturates if SAT bit set |
| `TILE-MUL` | $\text{dst}[i] = \text{src0}[i] \times \text{src1}[i]$ | Truncating (low bits) |
| `TILE-WMUL` | Widening multiply → dst and dst+64 | u8→u16, u16→u32, etc. |
| `TILE-FMA` | $\text{dst}[i] \mathrel{+}= \text{src0}[i] \times \text{src1}[i]$ | In-place accumulate |
| `TILE-MAC` | Multiply-accumulate into hardware accumulator | |
| `TILE-MIN` | $\text{dst}[i] = \min(\text{src0}[i],\ \text{src1}[i])$ | Signed-aware |
| `TILE-MAX` | $\text{dst}[i] = \max(\text{src0}[i],\ \text{src1}[i])$ | Signed-aware |

```forth
U8-MODE
_a 10 TILE-FILL-U8
_b 20 TILE-FILL-U8
_a _b _c TILE-ADD          \ _c[0..63] = 30

U16-MODE
_a 300 TILE-FILL-U16
_b 200 TILE-FILL-U16
_a _b _c TILE-WMUL          \ _c = 60000 (u32 per lane, spanning 128 bytes)
```

### Bitwise Operations

`( src0 src1 dst -- )` — operate on raw bits regardless of mode.

| Word | Operation |
|---|---|
| `TILE-AND` | $\text{dst}[i] = \text{src0}[i]\ \mathbin{\&}\ \text{src1}[i]$ |
| `TILE-OR` | $\text{dst}[i] = \text{src0}[i]\ \mathbin{|}\ \text{src1}[i]$ |
| `TILE-XOR` | $\text{dst}[i] = \text{src0}[i]\ \oplus\ \text{src1}[i]$ |

### Unary Operations

| Word | Stack | Operation |
|---|---|---|
| `TILE-ABS` | `( src dst -- )` | $\text{dst}[i] = |\text{src}[i]|$ — signed mode: absolute value, unsigned: identity |

### Reductions

Reductions collapse all lanes into a single scalar in the hardware
accumulator (`ACC@`), returned on the data stack.

| Word | Stack | Operation |
|---|---|---|
| `TILE-SUM` | `( src -- sum )` | $\sum_i \text{src}[i]$ |
| `TILE-RMIN` | `( src -- min )` | $\min(\text{src}[i])$ |
| `TILE-RMAX` | `( src -- max )` | $\max(\text{src}[i])$ |
| `TILE-SUMSQ` | `( src -- sumsq )` | $\sum_i \text{src}[i]^2$ |
| `TILE-DOT` | `( src0 src1 -- acc )` | $\sum_i \text{src0}[i] \cdot \text{src1}[i]$ |
| `TILE-ARGMIN` | `( src -- index )` | Index of minimum element |
| `TILE-ARGMAX` | `( src -- index )` | Index of maximum element |
| `TILE-L1NORM` | `( src -- norm )` | $\sum_i |\text{src}[i]|$ |
| `TILE-POPCNT` | `( src -- cnt )` | Population count (set bits) |

> In FP modes, reductions accumulate in FP32.  In integer modes,
> the accumulator holds a plain integer.

```forth
U8-MODE
_a 3 TILE-FILL-U8
_a TILE-SUM .           \ prints 192  (64 × 3)
```

### Utility / Memory

| Word | Stack | Description |
|---|---|---|
| `TILE-ZERO` | `( dst -- )` | Hardware tile zero (64 bytes) via `TZERO` |
| `TILE-COPY` | `( src dst -- )` | Copy 64 bytes (byte-by-byte) |
| `TILE-TRANS` | `( src dst -- )` | 8×8 byte transpose via `TTRANS` |

### Fill Helpers

Fill all lanes with a broadcast scalar.  Use the variant matching
your current element width.

| Word | Stack | Lanes × Width |
|---|---|---|
| `TILE-FILL-U8` | `( dst val -- )` | 64 × 1 byte |
| `TILE-FILL-U16` | `( dst val -- )` | 32 × 2 bytes |
| `TILE-FILL-U32` | `( dst val -- )` | 16 × 4 bytes |
| `TILE-FILL-U64` | `( dst val -- )` | 8 × 8 bytes |

```forth
U8-MODE   _a 255 TILE-FILL-U8       \ all bytes = 0xFF
U16-MODE  _b 1000 TILE-FILL-U16     \ all words = 1000
U32-MODE  _c 100000 TILE-FILL-U32   \ all dwords = 100000
```

---

## FP16 Convenience API (SIMD- prefix)

These operations set `FP16-MODE` automatically — no need to set mode
first.  Each operates on 32 FP16 lanes.

### Binary Arithmetic

All binary words have the stack effect `( src0 src1 dst -- )`.

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
a b c SIMD-ADD     \ c[i] = a[i] + b[i], all 32 FP16 lanes
```

### Unary Operations (FP16)

| Word | Stack | Operation |
|---|---|---|
| `SIMD-ABS` | `( src dst -- )` | $\text{dst}[i] = |\text{src}[i]|$ — clear sign bit on all 32 lanes. |
| `SIMD-NEG` | `( src dst -- )` | $\text{dst}[i] = -\text{src}[i]$ — flip sign bit on all 32 lanes. |

`src` and `dst` may be the same buffer for in-place operation.

### Broadcast Operations

#### SIMD-SCALE

```forth
SIMD-SCALE  ( src scalar dst -- )
```

Multiply all 32 elements of `src` by `scalar` (FP16), store in `dst`:

$$\text{dst}[i] = \text{src}[i] \times s$$

Internally broadcasts `scalar` into a scratch tile, then uses `TMUL`.

### Reductions (FP16)

Reduction operations collapse 32 elements into a single scalar.
The result is an FP32 bit pattern from the hardware accumulator
(except `SIMD-ARGMIN` and `SIMD-ARGMAX` which return an integer index).

| Word | Stack | Operation |
|---|---|---|
| `SIMD-SUM` | `( src -- sum )` | $\sum_{i=0}^{31} \text{src}[i]$ |
| `SIMD-SUMSQ` | `( src -- sumsq )` | $\sum_{i=0}^{31} \text{src}[i]^2$ |
| `SIMD-DOT` | `( src0 src1 -- acc )` | $\sum_{i=0}^{31} \text{src0}[i] \cdot \text{src1}[i]$ |
| `SIMD-RMIN` | `( src -- min )` | $\min(\text{src}[i])$ |
| `SIMD-RMAX` | `( src -- max )` | $\max(\text{src}[i])$ |
| `SIMD-ARGMIN` | `( src -- index )` | Index of minimum element |
| `SIMD-ARGMAX` | `( src -- index )` | Index of maximum element |
| `SIMD-L1NORM` | `( src -- norm )` | $\sum_{i=0}^{31} |\text{src}[i]|$ |
| `SIMD-POPCNT` | `( src -- cnt )` | Population count |

### Clamping

```forth
SIMD-CLAMP  ( src lo hi dst -- )
```

Clamp all 32 lanes to the range $[\text{lo}, \text{hi}]$:

$$\text{dst}[i] = \min(\max(\text{src}[i],\ \text{lo}),\ \text{hi})$$

`lo` and `hi` are FP16 scalars (broadcast internally).

### Memory Operations

| Word | Stack | Description |
|---|---|---|
| `SIMD-FILL` | `( dst val -- )` | Write `val` (FP16) to all 32 lanes. |
| `SIMD-ZERO` | `( dst -- )` | Zero the entire 64-byte tile. |
| `SIMD-COPY` | `( src dst -- )` | Copy 64 bytes from `src` to `dst`. |

### Strided 2D Access

```forth
SIMD-LOAD2D   ( base stride rows dst -- )
SIMD-STORE2D  ( src base stride rows -- )
```

Load/store strided 2D data from/to memory.  Reads `rows` row segments
starting at `base`, with `stride` bytes between row starts.

---

## Internals

| Word | Purpose |
|---|---|
| `_SIMD-S0` through `_SIMD-S7` | Eight scratch tile VARIABLEs (512 bytes HBW total) |
| `_SIMD-SETUP-BIN` | `( src0 src1 dst -- )` — set FP16-MODE, point TSRC0/TSRC1/TDST |
| `_SIMD-SETUP-UNI` | `( src dst -- )` — set FP16-MODE, point TSRC0/TDST |
| `_TILE-BIN` | `( src0 src1 dst -- )` — point TSRC0/TSRC1/TDST (no mode change) |
| `_TILE-UNI` | `( src dst -- )` — point TSRC0/TDST (no mode change) |
| `_SIMD-INIT-TILES` | Allocate and zero all scratch tiles at load time |

---

## Quick Reference

**Mode words:**
```
U8-MODE  I8-MODE  U8S-MODE  I8S-MODE      (64 lanes, 8-bit)
U16-MODE I16-MODE U16S-MODE I16S-MODE      (32 lanes, 16-bit)
U32-MODE I32-MODE                           (16 lanes, 32-bit)
U64-MODE I64-MODE                           ( 8 lanes, 64-bit)
FP16-MODE  BF16-MODE                        (32 lanes, float)
```

**Mode-agnostic (TILE- prefix, caller sets mode):**
```
TILE-ADD      ( src0 src1 dst -- )    TILE-DOT      ( src0 src1 -- acc )
TILE-SUB      ( src0 src1 dst -- )    TILE-RMIN     ( src -- min )
TILE-MUL      ( src0 src1 dst -- )    TILE-RMAX     ( src -- max )
TILE-WMUL     ( src0 src1 dst -- )    TILE-SUM      ( src -- sum )
TILE-FMA      ( src0 src1 dst -- )    TILE-SUMSQ    ( src -- sumsq )
TILE-MAC      ( src0 src1 dst -- )    TILE-ARGMIN   ( src -- index )
TILE-MIN      ( src0 src1 dst -- )    TILE-ARGMAX   ( src -- index )
TILE-MAX      ( src0 src1 dst -- )    TILE-L1NORM   ( src -- norm )
TILE-AND      ( src0 src1 dst -- )    TILE-POPCNT   ( src -- cnt )
TILE-OR       ( src0 src1 dst -- )    TILE-ZERO     ( dst -- )
TILE-XOR      ( src0 src1 dst -- )    TILE-COPY     ( src dst -- )
TILE-ABS      ( src dst -- )          TILE-TRANS    ( src dst -- )
TILE-FILL-U8  ( dst val -- )          TILE-FILL-U32 ( dst val -- )
TILE-FILL-U16 ( dst val -- )          TILE-FILL-U64 ( dst val -- )
```

**FP16 convenience (SIMD- prefix, auto-sets FP16 mode):**
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
