# akashic-numeric-boundary — Boundary conditions for grid stencils

A stencil reads values outside an `nx`-by-`ny` grid: row −1 above it, row
`ny` below it, column −1 to its left, and column `nx` to its right. These are
its ghost values. A boundary-condition descriptor says where each side's
ghost values come from.

```forth
REQUIRE numeric/boundary.f
```

`PROVIDED akashic-numeric-boundary`. Requires `numeric/array.f`.

---

## Kinds

| Word | Value | Ghost values |
|---|---|---|
| `NBC-ZERO-FLUX` | 0 | Equal to the edge element next to them, so nothing crosses the side |
| `NBC-DIRICHLET` | 1 | From a caller vector: `nx` values for the top and bottom, `ny` for the left and right, in the grid's format |

## Sides

| Word | Value | Ghost cells |
|---|---|---|
| `NBC-TOP` | 0 | Row −1 |
| `NBC-BOTTOM` | 1 | Row `ny` |
| `NBC-LEFT` | 2 | Column −1 |
| `NBC-RIGHT` | 3 | Column `nx` |

## Words

A descriptor is `NBC-SIZE` (64) bytes of caller memory. It holds pointers to
the caller's ghost vectors and does not copy them.

| Word | Stack | Effect |
|---|---|---|
| `NBC-INIT` | `( bc -- )` | Every side zero flux |
| `NBC-ZERO-FLUX!` | `( side bc -- status )` | Make a side zero flux |
| `NBC-DIRICHLET!` | `( ghost side bc -- status )` | Take a side's ghost values from the vector descriptor `ghost` |
| `NBC-KIND` | `( side bc -- kind )` | A side's kind |
| `NBC-GHOST` | `( side bc -- arr )` | A Dirichlet side's vector |
| `NBC-CHECK` | `( u bc -- status )` | Can `bc` serve grid `u`? |

The setters refuse a side outside 0–3 with `NUM-E-RANGE`. `NBC-CHECK`
refuses an unknown kind (`NUM-E-RANGE`), and a missing Dirichlet vector or
one that is not a single row of the grid's format and the side's length
(`NUM-E-SHAPE`). Stencils run `NBC-CHECK` themselves.

```forth
\ Fixed temperatures along the top, insulated elsewhere.
CREATE bc NBC-SIZE ALLOT
bc NBC-INIT
top-values NBC-TOP bc NBC-DIRICHLET!  ( status )
```
