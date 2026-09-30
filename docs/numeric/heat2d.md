# akashic-numeric-heat2d — Time steps for 2-D heat diffusion

Time steps for the heat equation `∂u/∂t = α (∂²u/∂x² + ∂²u/∂y²)` on a grid
with equal spacing `h` and time step `Δt`, where `r = α Δt / h²`.

```forth
REQUIRE numeric/heat2d.f
```

`PROVIDED akashic-numeric-heat2d`. Requires `numeric/team-stencil2d.f`.

---

## Words

| Word | Stack | Result |
|---|---|---|
| `NHEAT-WS-BYTES` | `( u -- bytes )` | Workspace each team member needs for a step on a grid of this shape |
| `NHEAT-EXPLICIT` | `( r u bc out team -- status )` | One forward-Euler step on a team: `out = RN(L(u) × r + u)` |

`NHEAT-EXPLICIT` is stable only for `0 ≤ r ≤ 1/4`, and it refuses any other
`r` with `NUM-E-RANGE`. The check compares IEEE bit patterns as unsigned
integers. That orders nonnegative values correctly and puts negative
values, infinity, and NaN above 1/4. Its other refusals are those of
`NT-UPDATE` (`team-stencil2d.md`).

The step runs on a team of cores (`team.md`). The result is the same bits
on any number of cores; a team of one core runs it on the caller's core
alone.

A step writes a separate output grid. Alternate two grids from step to
step:

```forth
: STEPS  ( n -- )
    0 ?DO
        r a bc b team NHEAT-EXPLICIT DROP
        r b bc a team NHEAT-EXPLICIT DROP
    LOOP ;
```

## Checks

With zero Dirichlet ghost values, the discrete sine mode
`sin(π(j+1)/(nx+1)) · sin(π(i+1)/(ny+1))` is an eigenvector of the
Laplacian with eigenvalue `λ = −4 sin²(π/(2(nx+1))) − 4 sin²(π/(2(ny+1)))`.
Each step multiplies it by `1 + rλ`, and the tests hold FP64 runs to
within 10⁻¹³ of that. With zero flux on every side, the total heat is
conserved; the tests hold it to within 10⁻¹³ over 20 steps.
