# akashic-par — Parallel Combinators for KDOS / Megapad-64

Structured parallel operations over arrays and ranges.
Automatically divides work across available cores.
Includes full/micro core-type awareness.

```forth
REQUIRE par.f
```

`PROVIDED akashic-par` — safe to include multiple times.
Automatically requires `event.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Core-Type Awareness](#core-type-awareness)
- [Per-Core Storage](#per-core-storage)
- [Chunk Distribution](#chunk-distribution)
- [PAR-DO — Run Two XTs](#par-do--run-two-xts)
- [PAR-MAP — Parallel Map](#par-map--parallel-map)
- [PAR-REDUCE — Parallel Reduction](#par-reduce--parallel-reduction)
- [PAR-FOR — Parallel FOR Loop](#par-for--parallel-for-loop)
- [PAR-SCATTER / PAR-GATHER](#par-scatter--par-gather)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Core-type safe by default** | `_PAR-NCORES` defaults to `N-FULL`: only full cores are used. Micro-cores (no tile engine, limited stacks) are excluded unless explicitly opted in. |
| **Automatic chunking** | Work is divided into `PAR-CORES` chunks with even distribution; remainder elements go to the lowest-numbered cores. |
| **Zero contention** | Each core writes only its own slot in the per-core parameter/result tables — no locks needed for the data-parallel phase. |
| **Sequential fallback** | When `PAR-CORES = 1`, all combinators execute sequentially on core 0 with identical semantics. |
| **CORE-RUN + BARRIER** | Multicore dispatch uses KDOS §8.1 primitives: `CORE-RUN` sends an xt to a secondary core, `BARRIER` waits for all cores. |
| **Static storage** | All per-core tables are `CREATE`d at load time (16 × CELL each). No heap allocation during parallel execution. |
| **Prefix convention** | Public: `PAR-`. Internal: `_PAR-`. |

---

## Core-Type Awareness

Megapad-64 has two core flavors:

| Property | Full Cores (0..N-FULL−1) | Micro-Cores (N-FULL..NCORES−1) |
|----------|--------------------------|-------------------------------|
| Tile engine | Yes | No |
| Stack depth | Full | Limited |
| Local memory | Normal RAM | Cluster scratchpad (SPAD) |
| Heap / ALLOT | Yes (core 0 only) | No |
| Barrier | Software (`BARRIER`) | Hardware (`HW-BARRIER-WAIT`) |

By default, par.f dispatches work **only to full cores**.  This is
the safe default — any xt will work, including those that use tile
engine operations.

### PAR-USE-FULL

```forth
PAR-USE-FULL  ( -- )
```

Restrict parallel dispatch to full cores only (IDs 0..N-FULL−1).
This is the default and is always safe.

### PAR-USE-ALL

```forth
PAR-USE-ALL  ( -- )
```

Include micro-cores in parallel dispatch (IDs 0..NCORES−1).
**Only safe when xt uses purely scalar operations** — no tile
engine words, no heap allocation, no `ALLOT`.  Micro-cores have
limited stack depth and no tile engine.

### PAR-CORES

```forth
PAR-CORES  ( -- n )
```

Query the current core count used for parallel dispatch.
Returns `N-FULL` after `PAR-USE-FULL`, `NCORES` after `PAR-USE-ALL`.

---

## Per-Core Storage

Six static arrays, each 16 cells (one per possible core):

| Array | Purpose |
|-------|---------|
| `_PAR-XT` | Execution token for each core's work |
| `_PAR-ADDR` | Base address of the data being processed |
| `_PAR-START` | Start index for each core's chunk |
| `_PAR-CNT` | Element count for each core's chunk |
| `_PAR-IDENT` | Identity value for reductions (per-core) |
| `_PAR-RESULTS` | Result cell per core (written by each core) |

Each core reads only its own index (via `COREID`), so there is
no contention during parallel execution.

---

## Chunk Distribution

### _PAR-DISTRIBUTE

```forth
_PAR-DISTRIBUTE  ( count running-start -- )
```

Internal helper.  Divides `count` items into `PAR-CORES` chunks
and fills `_PAR-START[i]` and `_PAR-CNT[i]` for each core.

Distribution is greedy-even: `base = count / PAR-CORES`,
`remainder = count MOD PAR-CORES`.  Cores 0..remainder−1 get
`base + 1` elements; the rest get `base`.

Example with 10 items across 4 cores:

| Core | Start | Count |
|------|-------|-------|
| 0    | 0     | 3     |
| 1    | 3     | 3     |
| 2    | 6     | 2     |
| 3    | 8     | 2     |

`running-start` is typically 0 for array operations, or `lo` for
PAR-FOR range operations.

---

## PAR-DO — Run Two XTs

```forth
PAR-DO  ( xt1 xt2 -- )
```

Run two execution tokens in parallel.

- **Multicore** (`PAR-CORES >= 2`): dispatches `xt2` to core 1
  via `CORE-RUN`, executes `xt1` on core 0, then `BARRIER`.
- **Single-core**: executes `xt1` then `xt2` sequentially.

Both XTs must have signature `( -- )`.  They share no stack.

```forth
: compute-a  ( -- )  ... ;
: compute-b  ( -- )  ... ;
['] compute-a ['] compute-b PAR-DO
```

---

## PAR-MAP — Parallel Map

```forth
PAR-MAP  ( xt addr count -- )
```

Apply `xt` to each element of a cell array **in-place**.

`xt` must have signature `( val -- val' )`.  The array at `addr`
(containing `count` cells) is divided into `PAR-CORES` chunks.
Each core applies `xt` to its chunk independently.

Returns immediately if `count <= 0`.

```forth
\ Double every element of a 1024-cell array
: my-double  ( n -- n*2 )  2 * ;
['] my-double data-array 1024 PAR-MAP
```

### How _PAR-MAP-CHUNK works

Each core's worker reads its parameters from the per-core tables:

1. Look up `xt`, `addr`, `start`, `count` via `COREID`
2. For each element in `[start, start+count)`:
   - Load `addr[i]`
   - Execute `xt`
   - Store result back to `addr[i]`

---

## PAR-REDUCE — Parallel Reduction

```forth
PAR-REDUCE  ( xt identity addr count -- val )
```

Reduce (fold) a cell array in parallel.

`xt` must have signature `( a b -- c )` and **must be associative**
(the order of partial reductions across cores is not guaranteed to
match left-to-right sequential order).

`identity` is the neutral element for `xt` (e.g. `0` for `+`,
`1` for `*`, `0` for `MAX` when values are non-negative).

Returns `identity` if `count <= 0`.

**Algorithm:**

1. Each core reduces its chunk: `acc = identity; for each elem: acc = xt(acc, elem)`
2. Core stores its local result in `_PAR-RESULTS[coreid]`
3. After `BARRIER`, core 0 does a final sequential reduction
   over the per-core results

```forth
\ Sum 1024 elements
['] + 0 data-array 1024 PAR-REDUCE  .

\ Product of 4 elements
['] * 1 data-array 4 PAR-REDUCE  .
```

### How _PAR-REDUCE-CHUNK works

Each core's worker:

1. Look up `xt`, `addr`, `start`, `count`, `identity` via `COREID`
2. Set `acc = identity`
3. For each element: `acc = xt(acc, elem)`
4. Store `acc` in `_PAR-RESULTS[coreid]`

---

## PAR-FOR — Parallel FOR Loop

```forth
PAR-FOR  ( xt lo hi -- )
```

Execute `xt` for each index in the half-open range `[lo, hi)`.
The range is divided across `PAR-CORES` cores.

`xt` must have signature `( i -- )`.

Returns immediately if `lo >= hi` (empty range).

```forth
\ Sum indices 0..999 into a shared variable
VARIABLE my-sum
: add-idx  ( i -- )  my-sum +! ;
['] add-idx 0 1000 PAR-FOR
my-sum @ .  \ 499500
```

**Note on shared state:** When `PAR-CORES > 1`, each core
executes `xt` concurrently.  If `xt` writes to shared memory
(like the example above), you must use a spinlock or atomic
operations.  On single-core, sequential execution is safe.

---

## PAR-SCATTER / PAR-GATHER

### PAR-SCATTER

```forth
PAR-SCATTER  ( src-addr elem-size count -- )
```

Setup helper: distribute `count` elements from `src-addr`
into the per-core parameter tables.  Fills `_PAR-ADDR`,
`_PAR-START`, and `_PAR-CNT`.

After scatter, core I's data starts at
`src-addr + (_PAR-START[i] × elem-size)`.

Returns immediately if `count <= 0`.

### PAR-GATHER

```forth
PAR-GATHER  ( dest-addr count -- )
```

Collect per-core results from `_PAR-RESULTS` into a destination
cell array.  Copies `min(count, PAR-CORES)` cells.

```forth
\ After a PAR-REDUCE or manual per-core computation:
CREATE results 16 CELLS ALLOT
results 16 PAR-GATHER
\ results[0..PAR-CORES-1] now hold per-core values
```

---

## Debug

### PAR-INFO

```forth
PAR-INFO  ( -- )
```

Print parallel combinator state.  Shows active core count,
full/total core counts, and per-core parameters with core
type annotation.

```
[par active=16 full=16 total=28 ]
  core 0 (full) start=0 cnt=64 result=2080
  core 1 (full) start=64 cnt=64 result=2144
  ...
  core 15 (full) start=960 cnt=64 result=3920
```

On single-core emulator:

```
[par active=1 full=1 total=1 ]
  core 0 (full) start=0 cnt=1024 result=0
```

---

## Concurrency Model

### Dispatch Pattern

1. Core 0 stores xt, addr, start, count for each core
2. Core 0 dispatches `_PAR-*-CHUNK` to cores 1..N-1 via `CORE-RUN`
3. Core 0 runs its own chunk directly
4. `BARRIER` synchronizes all cores
5. Core 0 collects/combines results

### What Secondary Cores Can Do

Per the KDOS §8.1 concurrency contract, workers dispatched via
`CORE-RUN` must only use:

- Direct memory access (`@`, `!`, `C@`, `C!`, `MOVE`, `FILL`)
- Arena bump-allocation (`ARENA-ALLOT`)
- Stack operations, arithmetic, logic
- **Full cores only:** tile engine operations

They must **not** use: `ALLOCATE`, `FREE`, `RESIZE`, `ARENA-NEW`,
`ARENA-DESTROY`, dictionary words, or I/O.

### DO vs ?DO

This library uses `?DO` (not `DO`) for all loops where the
iteration count might be zero.  Standard Forth `DO` always enters
the loop body at least once, which causes infinite loops when
limit equals start (e.g. `1 1 DO`).  `?DO` checks and skips
the body when limit = start.

### Return Stack and DO Loops

Worker words avoid placing values on the return stack before
`DO..LOOP` because `R@` inside the loop body accesses the
**loop index**, not previously pushed values.  Instead, workers
re-read parameters from the per-core tables via `COREID`.

---

## Quick Reference

| Word             | Signature                           | Behavior                                 |
|------------------|-------------------------------------|------------------------------------------|
| `PAR-USE-FULL`   | `( -- )`                            | Use full cores only (default, safe)      |
| `PAR-USE-ALL`    | `( -- )`                            | Use all cores incl. micro-cores          |
| `PAR-CORES`      | `( -- n )`                          | Query active core count                  |
| `PAR-DO`         | `( xt1 xt2 -- )`                   | Run two XTs in parallel                  |
| `PAR-MAP`        | `( xt addr count -- )`             | Parallel in-place map                    |
| `PAR-REDUCE`     | `( xt id addr count -- val )`      | Parallel reduction (fold)                |
| `PAR-FOR`        | `( xt lo hi -- )`                  | Parallel FOR loop over range             |
| `PAR-SCATTER`    | `( src esize count -- )`           | Distribute to per-core params            |
| `PAR-GATHER`     | `( dest count -- )`                | Collect per-core results                 |
| `PAR-INFO`       | `( -- )`                            | Debug display (shows core types)         |

### Internal Words

| Word                | Signature                   | Behavior                              |
|---------------------|-----------------------------|---------------------------------------|
| `_PAR-DISTRIBUTE`   | `( count start -- )`       | Divide work into per-core chunks      |
| `_PAR-MAP-CHUNK`    | `( -- )`                   | Per-core map worker                   |
| `_PAR-REDUCE-CHUNK` | `( -- )`                   | Per-core reduce worker                |
| `_PAR-FOR-CHUNK`    | `( -- )`                   | Per-core for-loop worker              |
| `_PAR-RESULTS@`     | `( core -- val )`          | Read per-core result                  |
| `_PAR-RESULTS!`     | `( val core -- )`          | Write per-core result                 |
| `_PAR-XT@`          | `( core -- xt )`           | Read per-core execution token         |
| `_PAR-ADDR@`        | `( core -- addr )`         | Read per-core base address            |
| `_PAR-START@`       | `( core -- n )`            | Read per-core start index             |
| `_PAR-CNT@`         | `( core -- n )`            | Read per-core element count           |
| `_PAR-IDENT@`       | `( core -- v )`            | Read per-core identity value          |

### Constants & Variables

| Name              | Type     | Value / Default  | Meaning                            |
|-------------------|----------|------------------|------------------------------------|
| `_PAR-MAX-CORES`  | Constant | 16               | Max supported cores                |
| `_PAR-NCORES`     | Variable | N-FULL           | Active core count for dispatch     |
| `_PAR-RS`         | Variable | (transient)      | Running-start temp for distribute  |
