# akashic-numeric-team-stencil2d — Grid stencils on a team

`NST-LAPLACE` and `NST-UPDATE` (`stencil2d.md`) split across a team of cores
(`team.md`) by output rows. Every output value depends only on its own
inputs, so the results are the same bits as on one core.

```forth
REQUIRE numeric/team-stencil2d.f
```

`PROVIDED akashic-numeric-team-stencil2d`. Requires `numeric/team.f` and
`numeric/stencil2d.f`.

---

## Words

| Word | Stack | Result |
|---|---|---|
| `NT-LAPLACE` | `( u bc out team -- status )` | `out = L(u)` |
| `NT-UPDATE` | `( c u bc out team -- status )` | `out = RN(L(u) × c + u)` |

Each member computes its share of the rows with `NST-LAPLACE-ROWS` or
`NST-UPDATE-ROWS`, reading whatever grid rows and ghost values those rows
need. A grid or output outside HBW streams through each member's own
workspace (`stencil2d.md`), so members' workspaces should be in HBW.

## Workspace and refusals

Each member's workspace needs `NST-WS-BYTES` of the grid. The whole call is
checked with `NST-CHECK` on member 0's workspace before any member starts,
so a refused call writes nothing and the statuses are those of
`stencil2d.md`. In addition, the grid, the output, or a Dirichlet vector
that overlaps the team's memory is refused with `NUM-E-OVERLAP`.
