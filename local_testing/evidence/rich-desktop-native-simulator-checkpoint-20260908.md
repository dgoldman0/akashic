# Native simulator Desktop acceptance — 2026-09-08

Status: **stopped after a simulator MMIO error; full acceptance did not pass**.
Native execution reached the complete rich Desk and real Pad/Daybook interaction
milestones. It finished 10 recorded milestones and acknowledged 18 offers before
the later Sound Lab launch faulted. Its initial Desk was substantially earlier
than Python simulator r4, but subsequent interaction intervals were slower than
the emulator. The user subsequently authorized merging the measured state to both mains with
these limitations recorded. Further optimization is outside this checkpoint;
this ledger records the pre-merge launch and does not claim main validation.

## Bound launch

Artifact root in Akashic: `local_testing/out/close-20260908-simulator-native-r1`.
The benchmark helper was temporarily outside the repository during this clean
launch. It was then restored as MegaPad `bench_semantic_cell_feed.py` and
validated sequentially against these same sources.

| Binding | Recorded value |
| --- | --- |
| Akashic head | `2a901086891380bd3802ea6b486ad2ae4594850a` |
| MegaPad simulator head | `3ea7bdc67818a9725669ff4eb9284b3515228403` |
| Working tree status at launch | Both empty/clean |
| Backend / executor | `simulator` / `native` |
| Profile | Ordinary `desktop-apt1` |
| Phase profiling / deadline | Off / 900 seconds |
| Extension | `/home/kir/Documents/Projects/fantasy-computing/.worktrees/megapad-simulator/_megaforth_native.cpython-313-x86_64-linux-gnu.so` |
| Extension SHA-256 | `346065313de001316fbf9d5a2d1f334d1e03fdc7ed67de0a0f2c0374f2e50964` |
| `run-revisions.json` SHA-256 | `025bd9c3854705d2cc594a611d73cc9f1045d0a488afc34f8dbaf9e3bee4718c` |

The launch log confirms checked cold stored source, 212 modules linked in
33 chunks, 4,028,241 raw source bytes and 4,029,561 container bytes, plus the
ordinary MegaPad networking/rich-terminal modules. The 32 MiB MP64FS image has
63 entries and 55,732 free sectors. The physical viewer uses 280×84 cells,
3080×1764 terminal pixels, 3080×1789 window pixels, an 18px font and X11. The
session uses real time and explicitly reports `native semantic` execution.
The final trace confirms the canonical acceptance action delay and configured
successful-completion hold are 0.75s and 10s respectively. The hold was not
reached in this failed run.

Akashic `78608e7..2a90108` changes evidence documents only. The native MegaPad
slice changes the generic execution machinery and its tests/docs, not the Forth
sources. Thus Python simulator r4 and this run use the same ordinary Forth
journey, including the already-corrected CELL validation path. Their backend
implementation and diagnostics differ. The older emulator r1 predates that
small CELL correction and is an operational baseline rather than a matched
source-revision benchmark.

## Prerequisite focused validation

The native prerequisite selectors passed before launch. The
committed `docs/simulator-native-execution.md` records:

- 115 clock-batching cases, 0.19s, checked against repeated individual ticks.
- 103 existing runtime, execution-quantum, CATCH/THROW, memory and source-overlay
  cases with native selected, 10.24s.
- 28 session/server and native differential cases, 1.53s; 20 of these compare
  exact semantic work, stacks/pointers/retained stack bytes, memory, errors,
  dictionary state and fallback effects.

This totals **131 native/runtime cases plus 115 clock cases**. The earlier 17-case differential pass was superseded by the stronger 20-case
run and is not counted again. Clock helpers are committed in `bbe0b7f`,
the initial native executor and differential coverage in `3ea7bdc`.

## First bounded kernel comparison

Raw artifact: `local_testing/out/close-20260908-cell-feed/native-first.jsonl`,
SHA-256 `999b7d07a56d0878e4d1359a05ad977039571aaf3bd7c9bf63ddc4017f9f893c`.
This is one Python-then-native sequential pair using the unchanged production
PT/Akashic engine fixture, actual geometry 280×2 inside caller bounds 280×84,
and the existing 3,000,000-step row watchdog.

| Measured interval | Python | First native | Observed ratio |
| --- | ---: | ---: | ---: |
| Source/runtime setup and CF-INIT | 0.545144015s | 0.502729175s | Not a cold Desktop source ratio |
| Two initial direct PT snapshot row calls | 0.448447629s | 0.043847839s | 10.2274× |
| Two unified CELL row-write calls | 4.555204137s | 1.789606554s | 2.5454× |
| Complete small fixture | 6.077742440s | 2.452929715s | 2.4777× |

Both unified feeds execute exactly 2,432,950 semantic steps and commit the same
560 cells, revision 2, and 4,848 decoded frame bytes. The CELL content hash is
`fca1c2f79d20b6bf2e227900d156dd3a8d8fd8d771879f2d36b9ea87679ff1ee`.
Initial direct PT rows consume 220,364 semantic steps in both cases. Kernel
timing excludes source/setup, attachment/negotiation, begin/cursor/commit work,
and physical presentation; it measures the existing row calls. This first pair
is not a balanced pinned-host benchmark or a whole-Desktop speed result.

## Reproducible benchmark verification

MegaPad `bench_semantic_cell_feed.py` reran the same Python-then-native fixture
sequentially after Desktop diagnostics were saved. It checks source/extension
hashes and repository bindings before and after the run, fixed geometry and
watchdogs, actual native progress, and exact final frame, timer and semantic
counter equivalence. It is a bounded kernel comparison, not another Desktop run.

| Interval | Python | Native | Observed ratio |
| --- | ---: | ---: | ---: |
| Unified CELL feed | 4.112512329s | 1.845714117s | 2.2281× |
| Initial direct PT snapshot rows | 0.380752664s | 0.042558094s | 8.9467× |
| Complete small fixture | 5.432440428s | 2.464224263s | 2.2045× |

The same 2,432,950 feed steps, 220,364 initial-row steps, cells, revision and
CELL hash were confirmed. Across these two fixed-order pairs, feed gains were
2.2–2.5× and initial-row gains 8.9–10.2×. This variation is retained rather than
presenting a single favorable kernel measurement as Desktop throughput.

Raw artifact: `local_testing/out/close-20260908-cell-feed/native-reproducible.json`.
SHA-256: `c1286dc2df64cfcca5ce01850b2c726c205b57f7c693611b723608705be9c0c9`.

## Completed trace and observed fault

The log records the same 11,035,530 semantic preparation steps as Python r4.
Enabled source accelerators are `EVALUATE-CHECKED`, `SOURCE-EVALUATE-CHECKED`,
`_LD-STATUS-THROW`, `_CRC-BUF-CHECKED`, `_LD-WALK` and `_PS-LINE-LEN`. Monitoring
indicated roughly 84.35s from run metadata creation to live-session uptime.
That includes about 18s before acceptance trace start: the exact trace
`session_connected` event is 65.988623280s. Metadata-relative observations are
not trace checkpoint timings. No source preparation speedup is inferred from
the monitoring offset.

`progress-03.json` records 318,012,689 session semantic steps at
316.349090099s since metadata creation, with no reported backend error. Native
statistics confirm actual native work; their counters include preparation and
must not be divided directly by session-only counters to claim a coverage rate.
The completed trace supersedes the earlier approximate first-ACK observation.

| Exact acceptance-trace checkpoint | Python simulator r4 | Emulator r1 | Native simulator r1 |
| --- | ---: | ---: | --- |
| Session connected | 78.874771358s | See original trace | 65.988623280s |
| First complete rich Desk ACK | 897.181845942s | 486.098092178s | 383.162946660s |
| Pad edited ACK | Not reached | 524.156536944s | 469.611251155s |
| Daybook task-added ACK | Not reached | 578.061029954s | 597.039409642s |
| Daybook date-advanced ACK | Not reached | 587.697482776s | 615.583017075s |
| Daybook source opened in Pad ACK | Not reached | 597.055056573s | 637.062558933s |
| Sound Lab launch-source ACK | Not reached | 639.777357703s | 733.570857360s |
| Final required milestone ACK | Not reached | 682.191468000s | Not reached |
| Runner finished | 900.075677948s, timeout | 693.264483012s, PASS | 872.876517792s, failure after SIGINT |
| Outer process wall | 902.17s | 697.75s | 875.07s, interrupted |

Acceptance-trace timings exclude preceding image construction; outer process
wall includes it and teardown. Successful runner completion includes the fixed
10s hold. Do not compare a failed timeout with a successful full journey as a
speed ratio. Compare exact common ACK milestones, and retain the shared-host,
single-run and differing-revision caveats. No full-journey extrapolation is used.

The Python r4 initial Desk time was 2.342× the native time. Native also
arrived 102.935s before the emulator's corresponding ACK (1.269× ratio). That
startup advantage did not persist through the interaction sequence:

| Interval after initial complete Desk ACK | Emulator | Native simulator |
| --- | ---: | ---: |
| To Pad edit | 38.058444766s | 86.448304495s |
| To Daybook task added | 91.962937776s | 213.876462982s |
| To Sound Lab launch source | 153.679265525s | 350.407910700s |

The native interval to Daybook task completion was 2.326× longer; to Sound Lab
launch source it was 2.280× longer. Native remained ahead in absolute elapsed
time at offer 9, then fell behind at offer 10 immediately before the recorded
task-added milestone. Task-added ended 18.978s later than the emulator, and the
last common recorded milestone ended 93.793s later. This is a measured startup
improvement with slower subsequent interactions, not a full-journey speed win.

All 18 offers were observed, projected and physically acknowledged exactly once.
All 14 recorded input calls returned `progress` after their authorizing
generation/offer ACK. The trace records 10 milestones, including actual Pad
editing, Daybook task addition/date change, and ordinary source opening/tab
activation. The initial complete CELL fallback gate passed at 383.169163318s;
the final fallback gate and final Sound Lab frame were not reached. Saved
ordinary and retained-only milestone PNGs accompany the trace. No final
acceptance manifest was produced.

`progress-04.json` already reports `MMIOAccessError: MMIO service rejected read
preflight` at 785.499403477s since metadata creation. The later saved
`error-state.json`, at 866.443018913s, has the same unchanged progress counters:
1,068,592,067 session semantic steps and 130,437 boundaries. The session is
paused in error; the terminal attachment itself remains ACTIVE with no reported
terminal failure and zero buffered decoder bytes. SIGINT ended the runner after
diagnostics were saved. The final 872.876517792s trace duration and 875.07s outer
wall include time spent inspecting the existing error, not completed work.
Maximum resident set size was 295,228 KiB; no swaps were recorded.

The strongest current cause candidate is the ordinary Sound Lab graph's
AudioOut presence/status probe. Akashic `akashic/audio/output.f:47` defines
AudioOut base `0xFFFFFF0000000C00`, with the status byte at base+1; the simulator
platform does not expose AudioOut. The focused `audio-mmio-probe.json` reads
`0xFFFFFF0000000C01 C@` and records the same `MMIOAccessError`, address/length,
retained stack and three semantic steps in both Python and native configurations.
This confirms that the candidate access is rejected by their shared platform
boundary. The native-configured probe records zero native steps, so it is not
claimed as proof that this failing read ran inside the native kernel. The exact
address of the live Desktop fault was not captured, and the full failing
instruction sequence was not replayed. AudioOut is therefore a source-supported,
focused-confirmed explanation for the failure stage, not a proven exact trace
of the live fault or proof that every possible native defect has been excluded.

## Final artifact bindings and decision

All paths below are relative to the native r1 artifact root above.

| Artifact | SHA-256 |
| --- | --- |
| `performance-trace.json` | `6fcb82fd327e36566ee5228516261329de2666be92f3bdc64e124820eac066c1` |
| `run.log` | `4b3761afc5d49c4c3a9a14ee94151e4aed1b0114a3002e9df4930ac825127073` |
| `wall-time.txt` | `c676ed174e719c1521b050c18c310054f054363b1ca95fe722430f573bd6eec9` |
| `progress-04.json` | `7dee5ff7098333015b745062e1107be4891095841b43565c37897d314fb2d218` |
| `error-state.json` | `381bdf6d24f22cb47918ce292853621140dc745a408ba82f5f853488e82c5528` |
| `audio-mmio-probe.json` | `51b69857f6dcbed98a724beb2d55ab41cba148087a18358424664dbac66478e8` |

Preserve this result as substantial progress through the real rich-terminal
journey, with a clear remaining platform failure and a measured interaction
speed limitation. It does not satisfy full simulator acceptance or establish overall superiority
over the emulator. The user has authorized integration to mains with these
limitations retained. Keep native acceleration optional, preserve Python as
the default, and bind the merged state to this evidence without presenting the
failed simulator run as a pass. Further performance work is deferred.
