# akashic-numeric-cg — Conjugate gradient on a team

Solves `A x = b` for a symmetric positive definite operator `A`, on a team of
cores (`team.md`). The operator is an execution token that applies `A` to an
array, so no matrix is ever formed.

```forth
REQUIRE numeric/cg.f
```

`PROVIDED akashic-numeric-cg`. Requires `numeric/team-blas1.f`.

---

## The operator

```forth
op  ( v out team ctx -- status )     \ out = A v
```

`ctx` is whatever the caller registered with the operator. The operator
should run on the team it is given, and it must be symmetric positive
definite for the solve to converge.

## Order of operations

The steps are fixed, so a solve gives the same bits on any number of cores:

```
bb = b·b;  Q = A x;  R = RN(b − Q);  P = R;  rr = R·R
thr = RN(RN(tol · tol) · bb);  k = 0
until rr ≤ thr:
    stop with NUM-E-CONVERGE when k = limit
    Q = A P;  pq = P·Q;  stop with NUM-E-CONVERGE unless pq > 0
    α = RN(rr / pq)
    x = RN(P · α + x);  R = RN(Q · −α + R)
    rr' = R·R;  k = k + 1
    unless rr' ≤ thr:  P = RN(P · RN(rr' / rr) + R)
    rr = rr'
```

The dot products are the fixed-order reductions of `blas1.md`. The scalar
steps are binary64 and round to nearest even whatever the rounding mode in
`FPCSR` is. The solve leaves that mode as it found it, and any flags its
steps raise stay set. For an FP32 array, `α` and the `P` coefficient are
rounded to binary32 before use.

## Words

| Word | Stack | Result |
|---|---|---|
| `NCG-SIZE` | `( -- 224 )` | Bytes of a solver descriptor |
| `NCG-SCRATCH-BYTES` | `( like -- bytes )` | Scratch for three arrays shaped like `like` |
| `NCG-INIT` | `( addr bytes like ncg -- status )` | Carve the solver's arrays `R`, `P`, and `Q` from aligned scratch |
| `NCG-OPERATOR!` | `( xt ctx ncg -- )` | Set the operator and its context |
| `NCG-LIMITS!` | `( tol limit ncg -- status )` | Stop when `R·R ≤ tol² · b·b`, or after `limit` iterations; `tol` is binary64 bits, nonnegative and finite |
| `NCG-R` | `( ncg -- arr )` | The residual array: put `b` here before a solve |
| `NCG-P` `NCG-Q` | `( ncg -- arr )` | Work arrays, free for the caller outside a solve |
| `NCG-SOLVE` | `( x team ncg -- status )` | Solve from `x`; `x` becomes the solution |
| `NCG-ITERATIONS` | `( ncg -- n )` | Iterations of the last solve |
| `NCG-RESIDUAL` | `( ncg -- bits )` | Its final `R·R`, binary64 bits |

`NCG-SOLVE` returns `NUM-E-CONVERGE` when it stops without reaching the
tolerance: at the iteration limit, or when `P·Q` is not positive. `x` then
holds the last iterate. It refuses an `x` of another shape (`NUM-E-SHAPE`),
an `x` that overlaps the solver's scratch (`NUM-E-OVERLAP`), and a solver
with no operator (`NUM-E-RANGE`). The team kernels' own refusals pass
through.
