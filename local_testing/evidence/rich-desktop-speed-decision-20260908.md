# Simulator speed decision — 2026-09-08

The current semantic simulator is not a fast Desktop acceptance backend. Keep
the working native emulator as the acceptance baseline. The user has selected
native simulator execution as the next measured effort in the dedicated
`.worktrees/megapad-simulator` worktree, with merge-back conditional on
considerable measured gains. Preserve the current semantic tests and
diagnostics, and avoid expanding Forth bulk-operation changes in parallel. The
evidence below establishes the present Desktop baseline, not performance for
every simulator workload.

## Revisions and comparable checkpoint

Both runs used the ordinary `desktop-apt1` physical acceptance profile: 280×84,
18px font, 320 MiB external memory, real time, 0.75s action delay, 10s successful
completion hold, 900s deadline, phase profiling off. Both source trees were clean
at launch. Artifacts live under Akashic `local_testing/out/`.

| Run | Akashic head | MegaPad head |
| --- | --- | --- |
| `close-20260908-emulator-r1` | `75952bd21ed70b85d2a8b324e0cdcf713eb9a594` | `65cf61ddbe12888f1dce8d8e2af644b0b2bdaba8` |
| `close-20260908-simulator-r4` | `78608e77a2a8026ad6ec453ac72aa9e365212437` | `c10058bab26820fc5fb78891106d0ec5316661e3` |

| Boundary | Emulator r1 | Simulator r4 |
| --- | ---: | ---: |
| First complete Desk frame physically composited and ACKed | 486.098092178s | 897.181845942s |
| Daybook task-added frame ACK | 578.061029954s | Not reached |
| Final accepted milestone ACK | 682.191468000s | Not reached |
| Acceptance runner finished | 693.264483012s, PASS | 900.075677948s, timeout |
| Outer process wall time | 697.75s | 902.17s |
| Maximum resident set size | 439,996 KiB | 292,980 KiB |

The same initial complete-frame boundary arrived about 411.084s later in r4,
or 1.846 times the elapsed time observed in r1. This is a practical same-profile
comparison, not a qualified matched-revision benchmark: the source heads differ,
and these physical acceptance runs were not balanced, pinned-CPU timing trials.
Do not divide emulator instruction counts by simulator semantic-step counts.

R4 was not stuck forever before rich presentation: offer 1 was observed at
897.027914911s, projected, physically composited, and ACKed at 897.181845942s.
The initial CELL fallback gate also passed. One revision-authorized
`activate_pad_file_menu` input returned `progress` at 897.938150577s; the
`desk-complete` artifact was recorded at 899.177485394s. Timeout followed at
900.075658030s in journey stage 2. No subsequent offer established the visible
result of that interaction, and neither required app interaction was completed.
Only one offer was observed/ACKed. This is initial-frame evidence, not full
simulator acceptance or a merge-ready claim.

## Preparation and fallback observations are separate

R4 logged 11,035,530 semantic steps during source preparation, using the
existing checked-source/load accelerators. The trace's `session_connected`
boundary is 78.874771358s after acceptance start. Separate monitoring found
about 84.53s between run metadata creation and live-session uptime; this includes
different startup boundaries and is only an observation. Neither figure has a
matched emulator source-load boundary, so neither supports a source-load speedup
ratio. Image construction precedes the acceptance trace; outer process timing
includes it. Emulator r1's first CELL appearance was observed around 270s, but
was not recorded as an exact trace checkpoint. A partial CELL snapshot or a
CELL-ready log is not the complete retained Desk ACK in the table.

At r4 monitoring checkpoint `progress-04.json`, 686.174749851s since metadata
creation, the session had executed 316,095,617 semantic steps without a complete
offer ACK. Retained definitions were already present on the wire. A process
sample showed about 99.7% CPU over twelve minutes, consistent with active compute
rather than a sleeping backend. Sampled CRC fallback counters were zero; that
alone does not identify the remaining bottleneck. R4 ended at 429,199,680 semantic
steps. No extrapolated full-journey completion time is claimed.

## The emulator comparison already includes its fast execution machinery

The recorded r1 command selects `--backend emulator`. The launcher builds an
ordinary `session_server.py --bios bios.asm ... --batch-steps 500000` command,
with no JIT-disabling option; the log records one shared execution lane.
MegaPad's `emulator/accel_wrapper.py` requires `_mp64_accel`; this is the C++
native backend. Its exact single-core path uses
`run_uncontended_single_core_round`, and `single_core_jit_regions_enabled`
defaults to true (`emulator/accel/mp64_accel.cpp:5549`).

The BIOS Forth compiler's JIT is separately enabled by `kdos.f:39` (`JIT-ON`).
`_AUTOEXEC-RUN` executes before the final `JIT-OFF` at line 9893, so ordinary
Akashic autoexec compilation occurs with that setting enabled. The generated
Akashic source does not disable it. These are confirmed launch paths and source
defaults, not per-run native block/region hit counts: phase profiling was off.
The simulator accepts `JIT-ON`/`JIT-OFF` as semantic no-ops
(`simulator/core_words.py:2599`); ordinary semantic IR still executes in Python.

## What the bounded measurements say about making it fast

The redundant inner CELL validation removal is a real local improvement.
The existing 560-cell, 280×2 fixture with caller bounds 280×84 measured
8.159745327s / 4,321,270 semantic operations before versus 4.753684869s /
2,432,950 after: 1.7165× faster kernel time, identical committed CELL content
and 4,848 frame bytes. Whole-fixture times were 9.508073538s and 6.226350772s;
source/setup and other fixture work are excluded from the kernel comparison.
See `close-20260908-cell-feed/comparison.json` and `revisions.json`, and the
separate CELL improvement ledger. This is not a whole-Desktop speedup claim.

After r4 ended, the existing fixture was profiled sequentially at 28×2 cells,
covering `_exercise` after source/setup. `current-kernel-profile.txt` records
306,892 observed semantic ticks (253,150 in the timed CELL feed), 8,290,215 host
function calls, 1,968,729 `isinstance` calls, 149,828 execution-token resolutions,
and 380,655 sparse-page integer reads/writes. The 2.668s cProfile total is
diagnostic, not throughput evidence; its overhead differs from the unprofiled
560-cell measurement. Cumulative `tick` time was 0.493s, about 18.5% of that
profile. Disabling counters alone cannot plausibly supply an order-of-magnitude
gain. Repeated Python dispatch, stack, dictionary, and memory operations are
distributed costs, rather than one remaining app-specific slow call.

A native semantic executor with native stack and memory operations is a credible
route to a major general improvement, but the size of any gain is unmeasured.
It must preserve semantic behavior, execution budgets, resumability, and host
service boundaries. The user has explicitly authorized this next execution-engine
effort in `.worktrees/megapad-simulator`; use bounded kernel and matched checkpoint
evidence before deciding whether its gains justify merging it back.

## Earlier speed claims do not establish a Desktop advantage

`simulator/README.md` describes a fast semantic backend and a fast focused-test
inner loop. `docs/simulator-contract.md` section 12 explicitly records no
qualified emulator/simulator speed result. Its September 1 KDOS-only shakedown
ran on a heavily loaded host; wall ratios were rejected. Semantic KDOS readiness
also starts from a prepared BIOS and omits ROM execution and the BIOS load-buffer
transfer, unlike the emulator's reset-to-ready path. Those readiness numbers
cannot be reused as equal-work engine speed or full Desktop evidence.

Primary artifacts: each run's `run-revisions.json`, `performance-trace.json`,
`wall-time.txt`, plus r4 `progress-04.json`, `desk-complete-retained.txt`,
`timeout-state.json`, and CELL fixture `current-kernel-profile.txt`.

## Artifact hashes

| Artifact | SHA-256 |
| --- | --- |
| r4 `performance-trace.json` | `3ed74f2f4b55f4a819e4ed6a50f06a5eeedba4cc73c1a3f4e7b42bde546d4c48` |
| r4 `timeout-state.json` | `725c85905b86642f2ad274d6bc3dc296396ee99a366c4e4c9752fd4486b7476b` |
| r4 `run-revisions.json` | `12d6f92d572181dd70df931802e52c0ad5aa2371fce3f730109eed0a40aa35e3` |
| r4 `desk-complete-retained-only.png` | `f71b71aedc36a39132593ce02f7fd49885cb5ff78cf286c26d4c21a553e9d47e` |
| CELL `current-kernel-profile.txt` | `ff20d2107d0beda90e17060b86ea138513db15f934ab8a8ab3c654083f9b4bef` |

The simulator worktree was clean and 73 commits behind the vertical, with no
unique commits. It was fast-forwarded from `655cf9b` to `c10058b` before native
implementation. No native acceleration has been merged into the vertical at
this baseline checkpoint.
