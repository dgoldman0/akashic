# akashic-numeric-blas1 — Element-wise kernels and reductions

Level-1 kernels over numeric arrays (`numeric/array.f`) in FP32 or FP64,
run on the calling core's tile engine.

```forth
REQUIRE numeric/blas1.f
```

`PROVIDED akashic-numeric-blas1`. Requires `numeric/array.f`.

The module holds no state, so any number of cores may run it at once, each
with its own workspace. Kernels set `TMODE` and `TCTRL` and leave them set.

---

## Workspace

| Word | Stack | Result |
|---|---|---|
| `NV-WS-BYTES` | `( arr -- bytes )` | Workspace any kernel here needs for an array of this shape |

It is three tiles plus one binary64 value per reduction block, rounded up
to whole tiles. `NV-SCALE` and `NV-AXPY` need only 64 bytes.

## Element-wise kernels

Arrays in one call must have the same format and shape (`NUM-E-SHAPE`
otherwise). Kernels work on whole tiles, so they also compute each row's
padding lanes. An output may be the same array as an input. A refused call
writes nothing.

| Word | Stack | Operation |
|---|---|---|
| `NV-ADD` | `( x y z -- status )` | `z = RN(x + y)` |
| `NV-SUB` | `( x y z -- status )` | `z = RN(x − y)` |
| `NV-MUL` | `( x y z -- status )` | `z = RN(x × y)` |
| `NV-COPY` | `( x y -- status )` | `y = x`, padding included |
| `NV-FILL` | `( bits x -- status )` | Every lane of `x` becomes the scalar |
| `NV-SCALE` | `( bits x ws -- status )` | `x = RN(x × a)` |
| `NV-AXPY` | `( bits x y ws -- status )` | `y = RN(x × a + y)`, fused: one rounding |

`RN` is IEEE round to nearest, ties to even. NaN results are the format's
canonical NaN, and subnormals are kept, as the tile engine defines.

## Reductions

Reductions return `( bits status )`. The result is binary64 bits in both
formats, because the tile engine accumulates FP32 and FP64 in binary64.
They need a workspace of `NV-WS-BYTES`.

| Word | Stack | Result |
|---|---|---|
| `NV-SUM` | `( x ws -- bits status )` | Σ x |
| `NV-DOT` | `( x y ws -- bits status )` | Σ x·y |
| `NV-SUMSQ` | `( x ws -- bits status )` | Σ x² |
| `NV-ASUM` | `( x ws -- bits status )` | Σ \|x\| |
| `NV-MAX` | `( x ws -- bits status )` | Largest element |
| `NV-MIN` | `( x ws -- bits status )` | Smallest element |

### Order of operations

`NV-SUM`, `NV-DOT`, `NV-SUMSQ`, and `NV-ASUM` have one defined order. A
result is therefore the same bits however the work is split, and a
reference implementation can reproduce it exactly.

1. The array's tiles are taken in row-major order. In each row's last tile,
   lanes past `nx` are replaced by the identity: −0 for SUM, SUMSQ, and
   ASUM. For DOT it is −0 in `x` and +0 in `y`, whose product is −0.
2. Each tile gives the tile engine's canonical pairwise tree result.
3. Runs of `NUM-BLOCK-TILES` (32) consecutive tiles form blocks. A block's
   value chains its tile results in order, with one rounding per add.
4. The result is the canonical pairwise tree over the block values, padded
   with −0 to a power of two.

`NUM-BLOCK-TILES` is part of the definition: changing it changes the
rounding of these results.

`NV-MAX` and `NV-MIN` are exact, so their order does not matter. They skip
NaN elements and order −0 below +0. If every element is NaN, the result is
the canonical binary64 NaN.

## Example

```forth
\ u = 0.5·v + u, then the squared norm of u.
CREATE u NARR-SIZE ALLOT   CREATE v NARR-SIZE ALLOT   CREATE ws NWS-SIZE ALLOT
( ... NARR-INIT u and v with the same shape, NWS-INIT ws with u NV-WS-BYTES ... )
0x3FE0000000000000 v u ws NV-AXPY  ( status ) DROP
u ws NV-SUMSQ  ( bits status )
```
