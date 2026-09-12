# Simulator improvements — 2026-09-12

Work is isolated in paired `simulator-improvements` branches under
`.worktrees/simulator-improvements/`. Both mains remain unchanged.

## Changes and boundaries

- MegaPad `4bab4e7` extracts the existing PCM register/capture/sink model into
  `shared/audio_output.py`. Emulator and simulator retain their own MMIO and
  guest-memory adapters. Simulator AudioOut now supports real headless capture,
  checked DMA and the ordinary presence/status probe. Memory fault messages
  retain operation, address and length.
- Akashic `9c2977b` fails physical acceptance immediately when the observed
  backend status reports an error, preserving the status without further RPCs.
- MegaPad `b155d36` adds opt-in native exit/settlement profiling. Profiling stays
  off during throughput and physical acceptance measurements.
- MegaPad `04fc18a` executes scalar return-stack words and ordinary preexisting
  continuations in C++. Shared bytes and typed cookie metadata remain authoritative;
  root/fault/stale continuations, loops, pair operations, dynamic execution and
  service boundaries retain their Python behavior. `4ac8c60` adds edge checks
  without changing this runtime implementation.

## Focused validation

All selectors ran sequentially with checked-in budgets, without xdist workers:

| Selector | Result |
| --- | --- |
| Audio, memory, platform and existing emulator AudioOut cases | 63 passed, 0.76s |
| Akashic physical acceptance-runner units | 87 passed, 0.82s |
| Native/runtime/quantum/stacks/source acceleration/clock checks | 275 passed, 10.97s |
| Real CATCH/THROW, memory, session/server, dual-backend terminal and CELL feed | 54 passed, 5.38s |
| Final native differential set, including overflow and Python-created continuations | 54 passed, 0.98s |

Rows overlap; do not add their counts as distinct cases. The final differential
set supersedes the earlier 51 native cases inside the 275-case selector.
Both independent extensions were built in the isolated MegaPad checkout.

## Bounded performance

The existing sequential Python-then-native CELL helper used 280×2 actual cells
inside unchanged caller bounds of 280×84, with the existing 3,000,000-step row
watchdog. Before/after native heads were `4bab4e7` / `04fc18a`; Akashic stayed at
`9c2977b`. Both report clean source bindings. Forth/app sources are unchanged.

| Timed interval | Before native | After native |
| --- | ---: | ---: |
| Unified CELL row feed | 1.696597026s | 0.262752559s |
| Complete small fixture | 2.335793783s | 0.881031477s |

The feed is 6.457× faster than the previous native executor. The after pair
measured Python at 4.545608607s, or 17.300× the new native feed time. These are
single fixed-order pairs on a shared host, not controlled Desktop ratios.
Both feeds retain 2,432,950 semantic steps, 560 cells, revision 2, and 4,848
committed frame bytes, with identical final frames, counters and timer state.
CELL SHA-256: `fca1c2f79d20b6bf2e227900d156dd3a8d8fd8d771879f2d36b9ea87679ff1ee`.

Across the broader post-attachment exercise (including begin/cursor/commit),
successful native entries fell from 176,413 to 6,185, a 96.49% reduction.
Average native interval length increased from 13.0 to 400.2 semantic steps.
Those counters must not be divided by the narrower timed row-feed step count.

Separate profiled pairs confirm the eliminated return-stack exits. Remaining
frequent exits include TRUE, UM*, LOOP and CRC-FEED. Profiled times are diagnostic
and excluded from throughput claims; these counts do not measure time spent in
each fallback operation.

Raw kernel reports are in `local_testing/out/simulator-improvements-20260912/kernels/`.
Its manifest binds all four JSON files by SHA-256, including source and extension
hashes and exact before/after counter snapshots.

## Physical acceptance

**PASS** at Akashic `9c2977bac88714eae154983069c2322c0f77fba9` and MegaPad
`4ac8c60b33d4d6064ac5a6daa7d9fc54a1535138`. Both checkouts were
clean at launch. The ordinary `desktop-apt1` source-mode profile used 280×84
cells, 18px X11 font, 320 MiB external memory, real time, 0.75s action delay,
10s hold, and the unchanged 900s watchdog. No compiled source cache or special
applet/profile path was used.

The 212 ordinary modules loaded in 33 checked-source chunks: 4,028,241 raw source
bytes and 4,029,561 container bytes. The image retains 55,732 free sectors.
Source preparation counted the same 11,035,530 semantic steps as the September
8 runs. Session connection was 78.089007324s into the acceptance trace; this is
not a standalone source-compilation speed measurement.

The final trace has 92 ordered events, 20 offers each observed/projected/ACKed,
and 14 revision-bound inputs, all returning progress after their authorizing
ACK. Eleven visible milestones passed, including real Pad editing, Daybook task
insertion, date advance from September 12 to 13, document handoff into Pad, tab
activation, and ordinary launcher/Sound Lab instruments. Initial and final CELL
fallback checks passed. The final retained raster has 1,016 draws, two text
areas, one text grid, two tabsets, eight readouts, two meters, three status
objects, 173 instrument cells and no clipped region. The retained-only Pad and
final Sound Lab screenshots were visually inspected.

| Exact physical ACK milestone | Offer | Trace seconds |
| --- | ---: | ---: |
| desk-complete | 1 | 204.060423439s |
| pad-file-menu-open | 3 | 227.861605139s |
| pad-file-menu-closed | 4 | 242.479931483s |
| pad-edited | 5 | 258.872016975s |
| daybook-task-added | 11 | 335.927848272s |
| daybook-date-advanced | 12 | 349.228896128s |
| daybook-source-opened-in-pad | 13 | 363.453376425s |
| pad-tab-activated | 14 | 378.130828073s |
| desk-launcher-open | 16 | 400.911238906s |
| soundlab-launch-source | 18 | 424.422426167s |
| soundlab-instruments-live | 20 | 497.698337208s |

Acceptance finished at 509.028190732s including the 10s hold. Outer elapsed time
was 511.819575605s including image construction and teardown. The first complete
rich Desk arrived at 204.060423439s versus the earlier native 383.162946660s.
Initial Desk to Daybook task added fell from 213.876462982s to 131.867424833s.
That interaction interval remains slower than the earlier emulator's
91.962937776s. The emulator's successful full run took 697.75s externally,
versus this run's 511.82s. These are historical same-profile operational
comparisons on shared hosts and differing source revisions, not matched
controlled backend benchmarks; no speed ratio uses the earlier native failure.

Resource monitoring sampled the process tree every 15 seconds. Maximum sampled
aggregate RSS was 370,696 KiB (~362 MiB), child peak RSS was 294,516 KiB, minimum
system available memory was 10,275,800 KiB (~9.80 GiB), and maximum one-minute
load was 8.98 on 16 logical CPUs. The acceptance ran alone and neither resource
guard fired. `resources.jsonl` and `wall-time.json` retain the observations.

The first sandboxed attempt completed source preparation but could not bind its
local Unix socket (PermissionError). It was stopped and retained separately as
`native-desktop/`; it is not functional failure or acceptance evidence. The
second run uses the required local socket/X11 access and retains the same source,
geometry, watchdog, action delay, and completion hold.

The software reference completion boundary is `pygame.display.flip`, not
physical panel scanout or e-paper completion. This run does not qualify audible
simulator playback, live network ports, persistence/reopen, broad resize/reset,
or sustained cadence. Native remains opt-in; Python remains the simulator
reference/default. No further optimization or merge to either main is included.
The next performance candidates are the remaining generic call/loop boundaries;
measure them on interactive workloads before claiming the CELL gain transfers.

The sandbox attempt also exposed a diagnostic limitation: server death before
the session socket exists still leaves the connector awaiting its deadline.
The run was manually stopped; the new status fault check applies after
connection. This startup-process reporting issue did not block the retry and is
recorded for a separate focused follow-up.

## Artifact bindings

Paths below are relative to `local_testing/out/simulator-improvements-20260912/`.
Raw outputs remain in this isolated Akashic worktree, including the separate
sandbox attempt. Do not retire the worktree before preserving these outputs.

| Artifact | SHA-256 |
| --- | --- |
| native-desktop-r2/manifest.json | `2e9de34ce77b79585efb35a42fe1ff3e64cfa4e796d0d6f96f40fa63c30ce042` |
| native-desktop-r2/performance-trace.json | `dadfca4c62dbfedd4c258f4a0c60daa1101ac325b1e5b0d733d5a51878bc6962` |
| native-desktop-r2/run-revisions.json | `4b02ced74ce4247227303a49c0ebd40fe3dae3dcfc57f2dfe30bcd6cc6c29d5b` |
| native-desktop-r2/run.log | `687fdaebaa6957a794b7946d0b9b6d62c65a5c84eddf5be92e355f8057bf934a` |
| native-desktop-r2/resources.jsonl | `8bae2327e94422cc9de5f50713a0820074934e23c8a67081df288b420868989c` |
| native-desktop-r2/wall-time.json | `a61acb6aa9aec648a1f35e32291650ce64dcb5d95ec1b415a8819b9fb058ea63` |
| kernels/native-before.json | `fa092d0e008e2d9a909f364820fcf0e09b401c44126c4c20f09fcd440cd5469c` |
| kernels/native-after.json | `a0f2a426e4aa42eaf2f5e9cad01d2643f06fd14f85954b737f7b9baecf4a96c0` |
| kernels/native-profile-before.json | `bab1c2a5101fa76d1d6f2e54266ed70ef8bab7a738a79c9026836ef4ce0ff865` |
| kernels/native-profile-after.json | `5ed7f8fad88d1ef8327a56713809727fc1563586d887f61eeeae11a5d9908ee9` |
