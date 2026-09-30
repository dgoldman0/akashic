# akashic-numeric-array — Formats, arrays, and workspaces

The base of the numeric package: FP32 and FP64 formats, status codes, and
the caller-owned descriptors every numeric kernel takes.

```forth
REQUIRE numeric/array.f
```

`PROVIDED akashic-numeric-array`. Requires `utils/memory-span.f`.

The module holds no state. Descriptors, storage, and workspaces belong to
the caller, so every word may run on any core.

---

## Formats

A format is its TMODE element-width code, so `NUM-FP64 TMODE!` selects it
on the tile engine.

| Word | Value | Meaning |
|---|---|---|
| `NUM-FP32` | 6 | IEEE binary32, 16 lanes per tile |
| `NUM-FP64` | 7 | IEEE binary64, 8 lanes per tile |
| `NUM-TILE` | 64 | Bytes per tile |

| Word | Stack | Result |
|---|---|---|
| `NUM-FORMAT?` | `( fmt -- flag )` | True for FP32 and FP64 |
| `NUM-LANE-BYTES` | `( fmt -- u )` | 4 or 8 |
| `NUM-LANES` | `( fmt -- u )` | 16 or 8 |
| `NUM-NEG-ZERO` | `( fmt -- bits )` | −0, the exact identity of IEEE addition |
| `NUM-NAN` | `( fmt -- bits )` | The canonical quiet NaN |
| `NUM-SPLAT-CELL` | `( bits fmt -- cell )` | The cell whose eight copies fill a tile with `bits` |
| `NUM-TILE-FILL` | `( cell addr -- )` | Store `cell` in all eight cells of an aligned tile |
| `NUM-ROW-TILES` | `( nx fmt -- tiles )` | Tiles for a row of `nx` elements; 0 when `nx < 1` |

The binary64 constants `NUM-F64-NEG-ZERO` and `NUM-F64-NAN`, and the binary32
constants `NUM-F32-NEG-ZERO` and `NUM-F32-NAN`, are also defined.

## Scalars

A scalar is a cell holding raw IEEE bits: all 64 bits for FP64, or the low
32 bits for FP32. For example, 1.0 is `0x3FF0000000000000` in FP64 and
`0x3F800000` in FP32.

## Status codes

Public numeric words return a status instead of throwing.

| Word | Value | Meaning |
|---|---|---|
| `NUM-OK` | 0 | Success |
| `NUM-E-FORMAT` | 1 | The format is not FP32 or FP64 |
| `NUM-E-SHAPE` | 2 | A dimension is invalid, or arrays differ in format or shape |
| `NUM-E-ALIGN` | 3 | An address is not 64-byte aligned |
| `NUM-E-SPACE` | 4 | Storage would wrap, or a workspace is too small |
| `NUM-E-RANGE` | 5 | An argument is outside its allowed range |
| `NUM-E-OVERLAP` | 6 | An output or workspace overlaps an input |
| `NUM-E-CONVERGE` | 7 | A solver stopped before reaching its tolerance |

## Arrays

An array is `nx` elements per row and `ny` rows. Each row is padded to whole
64-byte tiles, so the row pitch is `nx` rounded up to whole tiles. The
padding lanes belong to the array. Element-wise kernels compute them along
with the real lanes, and reductions replace them with the operation's
identity. A vector is an array with one row. Storage is 64-byte aligned and
has no halo.

A descriptor is `NARR-SIZE` (32) bytes of caller memory.

| Word | Stack | Result |
|---|---|---|
| `NARR-BYTES` | `( nx ny fmt -- bytes\|0 )` | Storage size; 0 for a bad format or dimension, or a size too large for a cell |
| `NARR-INIT` | `( addr nx ny fmt arr -- status )` | Describe the storage at `addr` |
| `NARR-ADDR` `NARR-FMT` `NARR-NX` `NARR-NY` | `( arr -- x )` | Fields |
| `NARR-ROW-TILES` | `( arr -- tiles )` | Tiles per row |
| `NARR-PITCH` | `( arr -- bytes )` | Bytes per row |
| `NARR-TILES` | `( arr -- tiles )` | Tiles in the whole array |
| `NARR-STORAGE` | `( arr -- addr bytes )` | The whole storage span |
| `NARR-SAME-SHAPE?` | `( a b -- flag )` | Same format, `nx`, and `ny` |

`NARR-INIT` refuses a bad format (`NUM-E-FORMAT`), an unaligned address
(`NUM-E-ALIGN`), a dimension below 1 or a size too large for a cell
(`NUM-E-SHAPE`), and storage that would wrap the address space
(`NUM-E-SPACE`). It does not write the storage.

```forth
CREATE u NARR-SIZE ALLOT
HBW-TALIGN  100 60 NUM-FP64 NARR-BYTES HBW-ALLOT
100 60 NUM-FP64 u NARR-INIT  ( status )
```

## Workspaces

A workspace is caller scratch: a 64-byte aligned address and a byte count.
Kernels that need scratch document how much. A workspace descriptor is
`NWS-SIZE` (16) bytes.

| Word | Stack | Result |
|---|---|---|
| `NWS-INIT` | `( addr bytes ws -- status )` | Describe scratch; refuses unaligned (`NUM-E-ALIGN`) or wrapping (`NUM-E-SPACE`) spans |
| `NWS-ADDR` `NWS-BYTES` | `( ws -- x )` | Fields |

One workspace must not be used by two calls at once. Give each core its own.
