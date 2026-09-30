# akashic-numeric-stencil2d — The 5-point Laplacian on 2-D grids

The discrete Laplacian of an `nx`-by-`ny` grid with unit spacing, and the
explicit update built on it, in FP32 or FP64.

```forth
REQUIRE numeric/stencil2d.f
```

`PROVIDED akashic-numeric-stencil2d`. Requires `numeric/array.f` and
`numeric/boundary.f`.

The module holds no state; a workspace carries each call's loop state.
Kernels set `TMODE` and the tile address registers and leave them set.

---

## Definition

At row `i` and column `j`:

```
L(u) = up + down + left + right − 4u
```

Neighbours outside the grid are ghost values from a boundary-condition
descriptor (`numeric/boundary.f`). The order of operations is fixed, with
one rounding each:

```
t = up + down
t = t + left
t = t + right
L = RN(u × −4 + t)
```

`NST-UPDATE` adds `c × L(u)` to the grid with one more fused rounding:
`RN(L × c + u)`. With `c = r` it is an explicit diffusion step. With
`c = −r` it is the operator of an implicit one.

Each output row's padding lanes are also defined. They are computed from
the grid's padding lanes, the ghost rows' padding lanes, and zeros for the
shifted neighbour rows.

## Words

| Word | Stack | Result |
|---|---|---|
| `NST-WS-BYTES` | `( u -- bytes )` | Workspace for a grid of this shape: 320 bytes plus two rows |
| `NST-LAPLACE` | `( u bc out ws -- status )` | `out = L(u)` |
| `NST-UPDATE` | `( c u bc out ws -- status )` | `out = RN(L(u) × c + u)`; `c` is scalar bits in the grid's format |
| `NST-LAPLACE-ROWS` | `( u bc out ws i0 i1 -- status )` | Rows `i0` up to `i1` of `out = L(u)` |
| `NST-UPDATE-ROWS` | `( c u bc out ws i0 i1 -- status )` | Rows `i0` up to `i1` of the update |
| `NST-CHECK` | `( u bc out ws -- status )` | The checks below, without computing |

The row words let several cores share a grid (`numeric/team-stencil2d.f`).
They refuse `i0 < 0`, `i1 < i0`, or `i1 > ny` with `NUM-E-RANGE`, and they
read whatever grid rows and ghost values their rows need.

Refusals, in the order they are checked:

| Status | When |
|---|---|
| `NUM-E-FORMAT` | The grid's format is not FP32 or FP64 |
| `NUM-E-SHAPE` | `out` differs from `u` in format or shape, or a Dirichlet vector does not fit (`NBC-CHECK`) |
| `NUM-E-RANGE` | A side has an unknown kind |
| `NUM-E-SPACE` | The workspace is smaller than `NST-WS-BYTES` |
| `NUM-E-OVERLAP` | `out` or the workspace overlaps `u`, a Dirichlet vector, or each other |

A refused call writes nothing.

## How it runs

Rows are processed whole. The up and down neighbours are the adjacent rows,
which are already tile-aligned. The left and right neighbours are the row
copied one element over, with `CMOVE`, into two aligned workspace rows. The
boundary condition supplies the element shifted in. Each tile then takes
four tile operations for the Laplacian and one more for the update.
