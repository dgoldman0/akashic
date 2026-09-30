# akashic-numeric-team-blas1 — Level-1 kernels on a team

The kernels of `blas1.md`, split across a team of cores (`team.md`). They
give exactly the same bits as the one-core kernels.

```forth
REQUIRE numeric/team-blas1.f
```

`PROVIDED akashic-numeric-team-blas1`. Requires `numeric/team.f` and
`numeric/blas1.f`.

---

## Words

| Word | Stack | One-core kernel |
|---|---|---|
| `NT-ADD` `NT-SUB` `NT-MUL` | `( x y z team -- status )` | `NV-ADD` `NV-SUB` `NV-MUL` |
| `NT-COPY` | `( x y team -- status )` | `NV-COPY` |
| `NT-FILL` | `( bits x team -- status )` | `NV-FILL` |
| `NT-SCALE` | `( bits x team -- status )` | `NV-SCALE` |
| `NT-AXPY` | `( bits x y team -- status )` | `NV-AXPY` |
| `NT-SUM` `NT-SUMSQ` `NT-ASUM` `NT-MAX` `NT-MIN` | `( x team -- bits status )` | `NV-SUM` … |
| `NT-DOT` | `( x y team -- bits status )` | `NV-DOT` |

## How the work is split

Element-wise kernels split the array's tiles. Each member works on a one-row
view of its share of the tiles. The kernels compute whole tiles, padding
included, so a split at any tile boundary is exact.

Reductions split the blocks. Each member computes the values of its share of
the blocks (`NV-BLOCK-VALUES`) into member 0's workspace. The owner then
combines them all (`NV-COMBINE`). The order is fixed by the blocks, not by
the members.

## Workspace and refusals

Each member's workspace needs `NV-WS-BYTES` of the array for reductions,
because member 0 holds every block value, and 64 bytes for `NT-SCALE` and
`NT-AXPY` (`NUM-E-SPACE` otherwise). Format and shape are checked as for the
one-core kernels. An array that overlaps the team's memory is refused with
`NUM-E-OVERLAP`. A call is checked whole before any member starts, so a
refused call writes nothing.
