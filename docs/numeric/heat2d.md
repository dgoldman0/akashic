# akashic-numeric-heat2d — Time steps for 2-D heat diffusion

Time steps for the heat equation `∂u/∂t = α (∂²u/∂x² + ∂²u/∂y²)` on a grid
with equal spacing `h` and time step `Δt`, where `r = α Δt / h²`.

```forth
REQUIRE numeric/heat2d.f
```

`PROVIDED akashic-numeric-heat2d`. Requires `numeric/team-stencil2d.f` and
`numeric/cg.f`.

---

## Words

| Word | Stack | Result |
|---|---|---|
| `NHEAT-WS-BYTES` | `( u -- bytes )` | Workspace each team member needs for a step on a grid of this shape |
| `NHEAT-EXPLICIT` | `( r u bc out team -- status )` | One forward-Euler step on a team: `out = RN(L(u) × r + u)` |
| `NHEAT-IMPLICIT-SIZE` | `( -- n )` | Bytes of an implicit stepper |
| `NHEAT-IMPLICIT-BYTES` | `( u -- bytes )` | Stepper scratch for grids shaped like `u` |
| `NHEAT-IMPLICIT-INIT` | `( r tol limit addr bytes u stepper -- status )` | Set up a stepper |
| `NHEAT-IMPLICIT` | `( u bc out stepper team -- iterations status )` | One backward-Euler step on a team |
| `NHEAT-SOLVER` | `( stepper -- ncg )` | The stepper's solver, for `NCG-RESIDUAL` |

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

## Implicit steps

`NHEAT-IMPLICIT` is one backward-Euler step. It is stable for every `r ≥ 0`,
so it can take far longer steps than `NHEAT-EXPLICIT`. It solves

```
(I − r L₀) u' = u + r g
```

`L₀` is the Laplacian with zero Dirichlet ghost values; zero-flux sides stay
as they are. `g = L(0)` carries the Dirichlet ghost values. The step computes
the right-hand side `RN(L(0) × r + u)`, then solves with conjugate gradient
(`cg.md`) starting from `u`. Its operator is `NT-UPDATE` at `c = −r`, which
is symmetric positive definite. So the step also gives the same bits on any
number of cores.

A stepper is set up once and used for many steps. It holds:

- `r`, in the grid's format;
- the solver's tolerance, in binary64 bits;
- the iteration limit;
- scratch of `NHEAT-IMPLICIT-BYTES`, holding the solver's three arrays and
  two zero ghost vectors.

`NHEAT-IMPLICIT-INIT` refuses a bad format (`NUM-E-FORMAT`), a negative or
non-finite `r` or `tol`, or a negative limit (`NUM-E-RANGE`), too little
scratch (`NUM-E-SPACE`), and unaligned scratch (`NUM-E-ALIGN`).

`NHEAT-IMPLICIT` returns the solver's iteration count. Its status is
`NUM-E-CONVERGE` when the solve stops short of the tolerance. The output may
be the grid itself, which gives an in-place step; otherwise it must not
overlap the grid. It refuses a grid or output of another shape
(`NUM-E-SHAPE`), and a grid, output, or Dirichlet vector that overlaps the
stepper's scratch (`NUM-E-OVERLAP`). Each team member needs `NHEAT-WS-BYTES`
of workspace.

## Checks

With zero Dirichlet ghost values, the discrete sine mode
`sin(π(j+1)/(nx+1)) · sin(π(i+1)/(ny+1))` is an eigenvector of the
Laplacian with eigenvalue `λ = −4 sin²(π/(2(nx+1))) − 4 sin²(π/(2(ny+1)))`.
Each explicit step multiplies it by `1 + rλ`, and the tests hold FP64 runs
to within 10⁻¹³ of that. Each implicit step multiplies it by `1/(1 − rλ)`,
and the tests hold three FP64 steps at `r = 2`, eight times the explicit
limit, to within 10⁻¹² of that. With zero flux on every side, the total
heat is conserved. The tests hold it to within 10⁻¹³ over 20 explicit
steps, and to within 10⁻¹¹ over three implicit ones.
