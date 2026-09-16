# Interpreter optimization evidence — September 16, 2026

The hosted simulator is a Forth semantic interpreter. Its native backend
interprets admitted IR in C++; it does not yet generate host machine code.
This pass implements ordinary interpreter optimizations, with Python retained
as the reference for unsupported operations and precise partial faults.

The subsequent [bulk and pointer pass](INTERPRETER-BULK-PERFORMANCE-20260916.md)
is also physically qualified. It adds native bulk operations and pointer reads
and records the latest typing measurements.

## Implemented slices

- `fabef61`: static superinstructions for literal/constant arithmetic and
  `DUP` conditional branches, retaining every original IR entry point.
- `c14470b`: reuse qualified contiguous stack spans for whole operand sets,
  avoiding repeated address resolution while updating the same guest bytes.
- `01dc03c`: skip known zero-progress native entries at Python-owned
  instructions; reuse prepared plans without rebuilding their work list.
- `15613d8`: keep identity-bound `EXECUTE` calls to prepared colon targets
  inside C++, preserving continuation cookies, return indices and both ticks.

All original semantic budgets, 8,192-step native intervals, virtual clocks,
stack capacities, source loading and physical input/ACK rules remain intact.
There is no persistent Forth cache or app-specific acceleration.

## Bounded kernels

Five alternating sequential processes per extension, each with the existing
four trials; medians below use the 15 warmed trials. The checked per-run
1.5-million-step limit is unchanged. Both extensions use Python host revision
`15613d8`, so this comparison isolates native changes and excludes the benefit
of avoiding empty native entries. Every trial preserved its semantic count
and result cells. These are short kernels on a shared host, not UI timings.

| Kernel | Before | After | Speedup | Semantic steps |
| --- | ---: | ---: | ---: | ---: |
| arithmetic | 4.623 ms | 2.081 ms | 2.22x | 380,008 |
| field_reads | 8.670 ms | 5.051 ms | 1.72x | 640,028 |
| loop_calls | 5.545 ms | 5.093 ms | 1.09x | 200,005 |
| dynamic_calls | 247.988 ms | 5.227 ms | 47.44x | 240,005 |
| scattered_reads | 6.490 ms | 2.879 ms | 2.25x | 520,008 |

The 47x result applies to a kernel dominated by dynamic calls that previously
crossed Python for every iteration. The ordinary counted-call kernel improved
only 1.09x: call/return metadata and other interpreter costs remain.
All raw trials and binary hashes are in
`local_testing/evidence/interpreter-kernels-20260916.json`.

## Physical typing

Akashic `8e95c0f` keeps the same production Forth as the earlier `de6a6aa`
measurements. MegaPad `15613d8` passed the same source-mode `desktop-apt1`
19-character journey through the ordinary keyboard forwarder, real X11
composition and post-flip ACKs at 3080×1764. Native profiling was disabled.

| MegaPad | Isolated character | Burst median delay | Last-character drain |
| --- | ---: | ---: | ---: |
| `efed68a`, previous interpreter | 1.413 s | 2.500 s | 2.397 s |
| `15613d8`, this pass | 1.262 s | 2.531 s | 2.274 s |

The isolated observation is 10.7% lower. Burst latency is essentially
unchanged; this is not fluid typing. Each row is one run, not a statistical
latency estimate. Scheduling delay is additional to the table: the latest
worst delay was 288 ms versus 214 ms previously. All 19 characters were
accepted and visibly retained. The run completed in 63.313 s including fresh
source preparation, with 393.164 MiB peak aggregate RSS.

Artifact: `local_testing/out/typing-20260916/fixed-8co6ac8t/`.
Use `local_testing/physical_typing_cadence.py` as recorded in the typing ledger.
The final native binary SHA256 is
`49a9386fcdc1747192ce1e385b219bd12514f301c8197ddfb412528be084e0fb`.

## Remaining interpreter work

A separate first-character diagnostic, `fixed-hfpooc1w`, found 2,590 COMPARE
boundaries, 1,862 each for RP@ and SP@, 1,750 FILL, 1,239 skipped CMOVE
boundaries and 575 MOVE boundaries between the first two complete offers.
This interval includes the pre-input idle delay. EXECUTE fell to 10
zero-progress attempts in that interval; it is no longer a dominant exit.
These are native exit counters, not wall-time percentages. The per-boundary
cProfile call tree still contained inconsistent cumulative totals; it must
not be used for an Amdahl estimate or a claimed percentage breakdown.

Bulk string/memory primitives and safe stack-pointer reads are now native;
see the linked follow-up for overlap, fault and capture-generation coverage.
Remaining candidates, in priority order:

1. Reduce call/return metadata construction and suspension snapshot work
   while retaining typed cookies, popped metadata and exact mutation checks
   at every existing owner boundary. The weak counted-call kernel gain
   identifies a remaining area that arithmetic fusion does not solve.
2. Compare token/direct-threaded dispatch with the current switch on the
   same kernels and actual UI workload. Treat the gain as unknown on this
   host; existing operation bodies may dominate the dispatch itself.
3. Expand measured superinstruction patterns and register stack caching.
   Flush observable state at budget/fault exits and aliasing memory accesses;
   keep popped bytes and every original instruction resumable.

Superinstructions, stack caching and threaded dispatch are established Forth
interpreter techniques; see the authors’ [interpreter research overview](https://www.complang.tuwien.ac.at/projects/interpreters.html) and
[threaded-code explanation](https://www.complang.tuwien.ac.at/forth/threaded-code.html).
Those references motivate candidates, not speedup forecasts for this VM.
An actual JIT remains a later option after this interpreter work is measured.

## Validation

The sequential native execution/loop/memory/clock, stack snapshot, session
clock and shared-session selector passed 462 cases in 4.38 s. It includes
exact budget/fault effects, sparse and fragmented stacks, original second
instruction entry, dynamic targets, shadowing and dictionary rollback.

The full ordinary physical Desktop/menu journey also passed at clean Akashic
`8e95c0f` and MegaPad `15613d8`: 18 milestones, 21 inputs, 27 post-flip ACKs,
and both complete CELL fallback gates. It used X11 with
`pygame.display.flip` as the physical sink and no manual input RPCs.
Total time was 143.037 s; aggregate peak RSS was 439.945 MiB. The previous
journey took 154.121 s, but these are individual shared-host functional runs,
not a controlled whole-application speedup measurement.

Artifact: `local_testing/out/typing-20260916/physical-menus-y1qa8j_u/`.
The existing 900 s / 3.5 GiB guards were unchanged. All tests and physical
runs were sequential; observed system available memory stayed above 8 GiB.
