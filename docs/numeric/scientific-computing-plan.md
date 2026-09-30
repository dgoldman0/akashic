# Akashic scientific computing: plan

**Started:** 2026-09-29

**Status:** Slices 1–4 complete. Slice 5, HBW staging, is next.

**Branch:** `feature/akashic-numerics`

**Isolated worktree:** `../akashic-numerics`, a sibling of the main checkout.

**Base:** Akashic `f2f06799`.

**MegaPad binding:** tests run against `../megapad-fp64-pin`, a detached
checkout of a committed `feature/megapad-fp64` revision with its native
accelerator built. It is now at `33e2cba`, the closed full-float plan:
Phases 1–9, with the scalar FP words and instruction-fault reporting. Set
`MEGAPAD_ROOT` to that path. The pin moves only
to committed MegaPad revisions, never to the working tree of `../megapad-fp64`,
which another session is editing.

## 1. Purpose

Akashic has good utility math but no scientific-computing layer. It has no
FP64, no linear solvers, and no grids, fields, or time integrators. This plan
builds that layer natively for MegaPad, around its tile engine, its 3 MiB of
on-chip HBW, and its several cores, rather than copying the interfaces of
NumPy or SciPy.

The target architecture:

```text
                  domain simulations
       heat · mechanics · fluids · particles · ...
                          │
               PDE and particle frameworks
                          │
    2-D arrays · boundary conditions · stencils · steppers
                          │
    BLAS-1 · reductions · CG · tridiagonal · FFT · ODE
                          │
         FP64/FP32 arrays · caller-owned workspaces
                          │
       tile engine · HBW staging · worker-job dispatch
                          │
                       MegaPad
```

It is built one vertical at a time. The first vertical is a 2-D heat
simulation carried through every layer (§6).

## 2. Current state (surveyed 2026-09-29)

### 2.1 Akashic

- **Formats.** Scalar FP16 goes through tile lane 0 (`math/fp16.f`).
  `math/fp32.f` is software binary32; its square root and reciprocal are fixed
  Newton iterations, so it is not correctly rounded. There is 16.16 fixed
  point and a 48.16 accumulator (`math/accum.f`). There is no FP64 anywhere in
  Akashic.
- **Tile layer.** `math/simd.f` and `math/simd-ext.f` provide FP16
  element-wise operations, reductions, dot products, SAXPY, and norms over any
  length. Their mode table stops at BF16.
- **Functions and data analysis.** Trig, exp/log, interpolation, sorting,
  Bézier curves, statistics, regression, probability, time series, and a PRNG.
  All work in FP16 with binary32 accumulation.
- **Signal processing.** A radix-2 FFT in FP16 throughout, including its
  twiddle factors.
- **Geometry and physics.** `vec2`, `mat2d`, and `rect` in FP16. The only
  physics is discrete tile movement for games (`game/2d/`).
- **Absent.** ODE solvers, grids and fields, stencils, boundary conditions,
  dense or sparse linear algebra, iterative solvers, particles, and simulation
  control.
- **Concurrency.** The math modules keep their working state in module
  globals and shared HBW scratch; `math/fft.f` alone declares 65 `VARIABLE`s.
  In GUARDED builds, 27 math modules wrap their public words in one guard per
  module. `simd.f` and `simd-ext.f` tell callers to serialize. Either way, only
  one caller at a time can use them.
- **Machinery to reuse.**
  - `concurrency/worker-job.f` runs one-shot jobs on idle full cores, with
    caller-owned input, output, and scratch spans.
  - `runtime/concurrency-class.f` records where a word may run. `PURE` and
    `EXCLUSIVE-BUFFER` words are worker-safe.
  - `utils/memory-span.f` checks spans.
- **Stale roadmap.** `local_testing/math-roadmap.md` predates most of
  `math/` and lists as missing several things that now exist. It is not
  authoritative.

### 2.2 MegaPad facts this plan depends on

- **Lanes.** A tile is 64 bytes: 8 FP64 or 16 FP32 lanes. The production
  engine has two FMA units, so an FP32 or FP64 element-wise operation takes 4
  beats either way. FP32 does twice the lanes per operation.
- **Reductions.** FP32 and FP64 reductions and dot products accumulate in
  binary64. Within a tile they use one canonical pairwise tree, defined in
  MegaPad `docs/floating-point.md` §4.
- **Chaining.** `ACC_ZERO` (TCTRL bit 1) publishes a tile result directly.
  `ACC_ACC` (bit 0) adds it to ACC0 with one rounding, so tile results chain
  in order.
- **Engines.** There are seven tile engines: one private to each of full
  cores 0–3, and one shared by each of the three four-microcore clusters. Each
  engine has one TACC bank, which is claimed and released explicitly, with no
  waiting.
- **Memory.**
  - Bank 0 is 1 MiB.
  - HBW is 3 MiB of on-chip RAM with 512-bit tile ports. It has one shared
    bump pointer and no free, lock, or owner. Arenas can carve private
    per-core areas from it.
  - External RAM, up to about 4 GiB, costs 6 or more cycles per access.
- **BIOS words.** The BIOS exposes only the tile×tile form of each tile
  operation. There are no words for SHUFFLE, RROT, MOVBANK, register
  broadcast, or in-place sources. `CMOVE` is a single hardware block copy.
- **Alignment.** Portable code must keep tile addresses 64-byte aligned; the
  backends disagree about unaligned ones.
- **Scalar FP.** Scalar FP32/FP64 words (`F64+`, `F64/`, `F64SQRT`, `F64<`,
  and so on) are specified in MegaPad `docs/floating-point.md` §11 and were
  committed in full-float Phase 7. Tile `TDIV` and `TSQRT` are Phase 8,
  which is optional.

## 3. Design rules

1. **Vertical first.** Each vertical is one real simulation built through
   every layer. A layer gains a word only when a vertical needs it.
   Horizontal completeness, such as a full BLAS before any solver, is not a
   goal.
2. **Caller-owned state.** Numeric kernels declare no module-level mutable
   state (no `VARIABLE`, `VALUE`, `CREATE`d scratch, or `GUARD`) and never
   allocate. Arrays, workspaces, and results belong to the caller. Every
   kernel is `CCLASS-PURE` or `CCLASS-EXCLUSIVE-BUFFER`, so it can run as a
   worker job on any full core and needs no guard. The refactor ratchet's
   global-state inventory does not grow.
3. **Checked, not capped.** Sizes come from the caller's buffers. A kernel
   checks its inputs and workspace and returns a status instead of writing
   past a buffer. There are no fixed element limits.
4. **Tile-shaped storage.** Arrays are contiguous and 64-byte aligned, and
   each row is padded to whole tiles. The padding belongs to the array, so
   element-wise kernels run on whole tiles. General strided views are not
   provided.
5. **Format-generic kernels.** One kernel serves FP32 and FP64; the format
   selects the tile mode, lane width, and identities. FP64 is the default for
   solvers and for state that integrates over many steps. FP32 storage is
   allowed where accuracy allows, and its reductions still accumulate in
   binary64. FP16 and BF16 stay in `math/`.
6. **One definition of every result.** Each kernel fixes its order of
   operations (N5). Results are the same bits on 1, 2, or 4 cores, and an
   independent Python reference reproduces them bit for bit. Tests compare
   bits wherever the order is defined, and compare with analytic solutions to
   check the physics.
7. **HBW is a staging area.** Large arrays live in external RAM. Kernels take
   a caller-provided workspace, normally in HBW, and stream rows through it.
   They also work when the arrays already live in HBW.
8. **Reuse the machinery.** Dispatch through worker jobs, carve per-core
   workspaces from arenas, and check spans with `utils/memory-span.f`.
   `concurrency/par.f` is not used, because it keeps its state in module
   globals.
9. **No legacy.** New code replaces what it supersedes. No parallel path is
   kept for compatibility.

## 4. Package layout

- **Source.** `akashic/numeric/`, an independent library package. It is added
  to the ratchet's `independent_prefixes`.
- **Docs.** `docs/numeric/`, one page per module, as in `docs/math/`.
- **Tests.** `local_testing/test_numeric_*.py`, built on
  `local_testing/forth_snapshot.py`.

## 5. Decisions (2026-09-29)

**N1. First vertical.** 2-D heat diffusion on a rectangular grid, in FP64 with
FP32 also supported. It has explicit and implicit time steps, and Dirichlet
and zero-flux boundaries. It exercises arrays, BLAS-1, reductions, stencils,
boundary conditions, a Krylov solver, time stepping, parallel dispatch, and
HBW staging, and it has analytic solutions to check against.

**N2. Arrays.** One descriptor serves vectors and grids: base address,
format, `nx` elements per row, and `ny` rows. The row pitch is `nx` rounded up
to whole tiles. A vector is one row. Storage has no halo.

**N3. Scalars.** A scalar is a cell holding raw IEEE bits: all 64 bits for
FP64, or the low 32 bits for FP32. Reductions return binary64 bits in both
formats. A kernel that needs a scalar operand fills a workspace tile with it
and uses the tile×tile form.

**N4. Status.** Public kernels return a status: 0 on success, or a
`NUM-E-…` code for a bad format, a shape mismatch, misalignment, too little
workspace, or an out-of-range argument. They do not throw for these.

**N5. Reduction order.** SUM, DOT, SUMSQ, and L1 over an array are defined as
follows.

- The array's tiles are taken in row-major order.
- In each row's last tile, lanes past `nx` are replaced by the identity. For
  SUM that is −0, the exact identity of IEEE addition. For DOT it is −0 in one
  operand and +0 in the other, whose product is −0.
- Each tile gives the hardware's canonical tree result.
- Consecutive runs of `B` tiles form blocks. A block's value chains its tile
  results in order, with one rounding per add (`ACC_ACC`).
- The result is the canonical pairwise tree over the block values, padded
  with −0 to a power of two. It is computed by packing block values eight to a
  tile and applying `TSUM` level by level, which gives exactly that tree.

`B` is fixed because it is part of the definition: changing it changes the
rounding. It starts at 32 tiles (256 FP64 or 512 FP32 elements). Blocks can be
computed on any core in any order, so the result does not depend on the core
count. MIN and MAX are exact and order-free, so they simply chain. Their
padding lanes hold the canonical NaN, which the NaN-skipping reductions
ignore.

**N6. Horizontal neighbours.** A stencil gets a row's left and right
neighbours by copying the row, shifted by one element, into two aligned
workspace rows with `CMOVE`. The boundary condition supplies the first or
last element of each shifted row. The up and down neighbours are the adjacent
rows, which are already aligned; for the first and last rows, the boundary
condition supplies them. No new MegaPad words are needed. If measurement
later shows the copies dominate, MegaPad can be asked for BIOS words for
SHUFFLE and the in-place forms.

**N7. Parallel decomposition.** The owner core splits work into row or block
ranges. It runs them as worker jobs on full cores 1–3 while it does its own
share. Each core gets a private workspace from an HBW arena carved before
dispatch. Outputs are disjoint and inputs are read-only, so no halo exchange
is needed. Microcores are left for later, because each cluster shares one
tile engine.

**N8. MegaPad dependencies.** Slices 1 and 2 need only the committed
full-float Phases 4–6. Slice 3 needs the Phase 7 scalar `F64` words for the
solver's divisions and comparisons, and waits until they are committed. No
slice needs Phase 8.

## 6. First vertical: 2-D heat

Each slice ends with a commit that has a full multi-paragraph message. A slice
may land in several commits, one per coherent green step.

### Slice 1 — Arrays, BLAS-1, and reductions (complete)

Progress:

- **Modules.** `numeric/array.f` holds the formats, status codes, and the
  array and workspace descriptors. `numeric/blas1.f` holds the kernels. They
  declare only constants.
- **Tests.** `local_testing/test_numeric_blas1.py` checks every kernel bit
  for bit against `local_testing/numeric_reference.py`, in FP64 and FP32, in
  HBW and external RAM, and with up to three tree levels. A canary tile after
  each array and workspace catches writes out of bounds, and every program
  must leave the stack empty. 40 tests pass in about 14 s.
- **Harness.** `ForthSnapshot` gained a build prelude, setup and inspect
  hooks for writing and reading machine memory, and it now keeps HBW in the
  image.

- Format words and the array descriptor, with sizing words so callers can
  allocate exactly.
- Element-wise kernels: fill, copy, scale, AXPY (one fused `TFMA` per tile),
  add, subtract, and multiply.
- Reductions in the N5 order: sum, dot, sum of squares, L1, maximum, and
  minimum.
- Workspace sizing words for each kernel that needs scratch.
- Tests: bit-exact against a Python reference in FP64 and FP32. Cases include
  partial tiles, several rows, one and many blocks, −0, subnormals,
  infinities, and NaN lanes, plus refusals for a bad format, shape,
  alignment, or workspace.

### Slice 2 — Grids, boundary conditions, and the explicit step (complete)

Progress:

- **Modules.** `numeric/boundary.f` describes each side's ghost values.
  `numeric/stencil2d.f` provides `NST-LAPLACE` and `NST-UPDATE`
  (`RN(L(u) × c + u)`), which serves both the explicit step (`c = r`) and,
  in Slice 3, the implicit operator (`c = −r`). `numeric/heat2d.f` provides
  `NHEAT-EXPLICIT`. All three declare only constants.
- **Definition.** Each output row's padding lanes are defined too: the
  shifted neighbour rows hold +0 past `nx`, so tests compare whole storage.
  An output that overlaps the grid, a ghost vector, or the workspace is
  refused with the new status `NUM-E-OVERLAP`.
- **Tests.** `local_testing/test_numeric_stencil.py` has 37 tests that run in
  about 11 s. They check the Laplacian, the update, and the heat step bit
  for bit, including padding lanes, for FP64 and FP32 shapes from 1×1 up.
  Each shape runs with zero-flux, Dirichlet, and mixed sides. The physics
  checks hold a discrete sine mode's decay to within 10⁻¹³ of its exact
  factor over 20 FP64 steps, and total heat under zero flux to within
  10⁻¹³. There is also a refusal test. Swapping the order of the
  neighbour additions in the reference changes about a fifth of the lanes,
  so the bit comparison does check the order.
- **Harness.** The shared test machinery moved into
  `local_testing/numeric_harness.py`.

- Boundary-condition descriptors: Dirichlet with caller-supplied edge values,
  and zero flux (mirror).
- The 5-point Laplacian as a matrix-free operator, in a fixed order:
  `t = up + down`, then `t = t + left`, then `t = t + right`, then
  `t = RN(u × −4 + t)`.
- The explicit (FTCS) step `u' = RN(L(u) × r + u)`, refusing `r > 1/4`. For
  nonnegative values, IEEE bit patterns compare like unsigned integers, so the
  check needs no scalar FP.
- Tests: bit-exact against the reference, and decay of a discrete sine mode
  by the factor `1 + rλ` per step, within rounding.

### Slice 3 — Scalar FP64 and the implicit step (complete)

Progress:

- **Modules.**
  - `numeric/cg.f` is conjugate gradient on a team, for any symmetric
    positive definite operator given as an execution token. Its steps are
    fixed. Its binary64 scalar steps round to nearest even whatever
    `FPCSR`'s rounding mode is, and the caller's mode is restored. It keeps
    no module state, and it reports `NUM-E-CONVERGE` when it stops short.
  - `numeric/heat2d.f` adds an implicit stepper and `NHEAT-IMPLICIT`. The
    right-hand side is built in the solver's own work arrays, so a step
    needs three arrays of scratch and may run in place.
- **Tests.**
  - `local_testing/test_numeric_implicit.py` has 14 single-core tests that
    run in about 18 s. Steps match the reference bit for bit: the solution
    with its padding lanes, the iteration count, the status, and the final
    residual. That holds in FP64 and FP32, with zero-flux, Dirichlet, and
    mixed sides.
  - Also covered: a solve that hits its iteration limit, `r = 0`, in-place
    steps, and a caller rounding mode that is kept and does not change the
    bits.
  - Physics: three implicit steps at `r = 2`, eight times the explicit
    limit, decay a sine mode to within 10⁻¹² of the exact factor, and
    implicit steps conserve heat under zero flux.
  - Refusals are covered.
  - Two tests in `test_numeric_team.py` show the same bits on four cores.
- Conjugate gradient on `(I − rL₀)u' = u + r·g` with the matrix-free
  operator, where `L₀` is the Laplacian with zero boundary values and `g`
  carries the Dirichlet edge values. It stops when `‖res‖² ≤ tol²‖b‖²` or at
  an iteration limit the caller chooses.
- The backward-Euler step, built on it.
- Tests: bit-exact against the reference, iteration counts, and decay by the
  factor `1/(1 − rλ)` per step.

### Slice 4 — Parallel execution (complete)

Done ahead of Slice 3, which was waiting for MegaPad.

Progress:

- **Modules.**
  - `numeric/team.f` holds the team: the owner core plus worker cores,
    each with its own workspace carved from one caller span. It dispatches
    one task per member as worker jobs. When a worker core cannot take its
    job, the owner runs that share itself, and gets the same bits.
  - `numeric/team-blas1.f` splits element-wise kernels by tiles, and
    reductions by blocks. Reductions now run in two steps in
    `numeric/blas1.f`: `NV-BLOCK-VALUES` for any range of blocks, then
    `NV-COMBINE`.
  - `numeric/team-stencil2d.f` splits the stencils by rows, through the new
    `NST-LAPLACE-ROWS` and `NST-UPDATE-ROWS`.
  - `NHEAT-EXPLICIT` now takes a team.
  - Team state lives in the caller's descriptor, so the modules still
    declare only constants.
- **Tests.** `local_testing/test_numeric_team.py` runs on a four-core
  machine, emulated on one host thread, with 20 tests in about 80 s.
  - Every team kernel matches the reference bit for bit on teams of 1, 2,
    3, and 4 cores.
  - The team counters show the worker cores ran their shares.
  - Twenty four-core heat steps match the reference.
  - A worker core kept busy by another job leaves its share to the owner,
    with the same bits.
  - The refusals are covered.
- **Found on the way.**
  - `concurrency/worker-job.f` could not be loaded line by line: a stack
    comment split over two lines broke `WJOB-PREPARE`. It and two other
    modules were fixed, and `test_forth_line_delimiters.py` now keeps every
    comment and string on one line.
  - The snapshot harness now stops a machine that has stopped making
    progress, instead of running out a multi-billion-step budget.

- Row ranges and reduction blocks run as worker jobs on full cores, with
  per-core HBW workspaces.
- Tests: the same bits on 1, 2, and 4 cores for every kernel from Slices 1–3.

### Slice 5 — HBW staging

- Arrays in external RAM stream through an HBW workspace in row slabs.
- Tests: the same bits as all-HBW runs. Cycles are measured with the
  emulator's timing model, not host time.

### Slice 6 — Acceptance

- One heat simulation runs end to end on four full cores with its fields in
  external RAM. It must be bit-exact against the reference and within
  tolerance of the analytic decay, and its timing is recorded. Grid size and
  step count are chosen from Slice 5's measurements.
- Module docs under `docs/numeric/`.

## 7. Later verticals

Each needs a real consumer before it starts. This is a list, not a schedule.

- **Particles.** N-body with velocity Verlet: structure-of-arrays storage,
  direct forces and then cell lists, and energy monitoring.
- **Tridiagonal and banded solvers,** batched across columns so that eight
  systems share one FP64 tile, and ADI for the heat equation.
- **FP64 FFT,** replacing the FP16 FFT for scientific use.
- **Dense linear algebra:** LU, Cholesky, QR, and matrix products built on
  TAMAC.
- **ODE integrators:** RK4 and adaptive Runge–Kutta, with state, derivative,
  stepper, and clock kept separate.
- **Sparse matrices,** multigrid, and preconditioners.

## 8. Defects found during the survey, not on this critical path

These are recorded here and left alone unless a slice cannot be correct
without fixing them.

- **FFT HBW leak.** `FFT-CONVOLVE`, `FFT-CORRELATE`, and their `-TW` forms
  take `8 × N` bytes of HBW on every call and never return them
  (`math/fft.f`). HBW cannot free single blocks. Nothing in the tree calls
  them yet.
- **Statistics overflow.** `math/stats.f` uses two fixed 2,048-element HBW
  scratch buffers with no size check. `STAT-MEDIAN`, `STAT-VARIANCE`, and the
  other words built on `_STAT-SS` write past them when `n > 2048`, into other
  modules' HBW. `math/timeseries.f` shares the same limit.
- **Microcores.** `concurrency/par.f` says microcores have no tile engine.
  MegaPad's tile-engine guide says each cluster shares one.
- **Software FP32.** Once MegaPad's scalar FP words land, `math/fp32.f` should
  be replaced by them. Audio, statistics, and store modules use it, so this is
  its own piece of work.
- **FP16 dot sums (fixed).** MegaPad's handoff reported that `FP16-DOT` in
  `math/fp16.f` added the chunks' binary32 results with an integer `+`,
  which was wrong whenever more than one 32-pair chunk was nonzero. It now
  adds them in binary32 with `ACC_ACC`, and both dot words set `TCTRL`
  themselves. `local_testing/test_fp16_dot.py` covers it.
- **`TCTRL` left set (fixed).** The numeric reductions used to leave
  `TCTRL` at `ACC_ACC`. The older `math/` modules (`simd.f`, `simd-ext.f`,
  and the statistics built on them) read reductions without setting
  `TCTRL`, so mixing them on one core would have corrupted their sums.
  `NV-BLOCK-VALUES` and `NV-COMBINE` now leave it clear, on the owner and on
  every worker core, and the tests check both.
- **Stale roadmap.** Delete `local_testing/math-roadmap.md` after checking
  whether its unfinished statistics items (Tier 5.7) are still wanted.
- **MegaPad trap handling (fixed in MegaPad).** Illegal-instruction traps
  used to restart the machine silently, reachable since Phase 7 through a
  reserved `FPCSR` rounding mode. MegaPad `a9f1dd8` and `b8e1a7e` now report
  such faults and throw them to the innermost `CATCH`. The numeric package
  sets only the rounding mode, to round to nearest even, during a solve.

## 9. Testing and resource rules

- **Binding.** Set `MEGAPAD_ROOT` to the absolute path of
  `../megapad-fp64-pin`. After moving the pin, rebuild its accelerator once
  with `make accel`.
- **Reference.** The Python reference computes each operation with MegaPad's
  exact oracle (`shared/ieee_fp.py`), or with host binary64 where that is
  provably identical.
- **Focused tests run freely.** These are single-core Forth snapshot tests of
  the numeric modules.
- **Multi-core tests** boot four full cores. Run them one at a time.
- **Desktop journey.** No Desk module loads `numeric/`, so the physical
  Desktop journey is not affected. Run it once at closure only if a shared
  module changed.
- **Architecture ratchet.** `python3 local_testing/refactor_inventory.py
  --check` must pass. Each new module updates the reviewed module count and
  digests in `local_testing/refactor_architecture.json` and adds no mutable
  globals.
