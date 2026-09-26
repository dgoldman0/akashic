# Simulator host quantum — September 26, 2026

The hosted simulator stops the guest every few thousand semantic steps to
service the session: settle UART output, run the terminal driver, and admit
input. This boundary had a fixed 8,192-step size. Typing profiles showed that
its host cost dominated simulator typing latency, so MegaPad made the size
configurable and measured it through the ordinary Desktop.

The new default for native execution is 65,536 steps. Median feedback for an
isolated character falls from 649 ms to 416 ms, and the median burst
character from 1,076 ms to 561 ms. Guest work per keystroke is unchanged.
This improves the simulated experience only; the real device has no host
quantum.

## Implementation

- MegaPad `182ee52` makes the quantum configurable. An explicit
  `semantic_quantum_steps` argument wins, then the `MEGAFORTH_QUANTUM_STEPS`
  environment variable, then the default. `simulator_server.py` gains
  `--semantic-quantum-steps`. Server status reports the selected value as
  `semantic_execution.quantum_steps`, so every trace records it. A native
  entry now runs to the quantum boundary instead of stopping every 8,192
  steps inside it.
- MegaPad `a649f32` sets the default by executor: 65,536 steps for native
  execution and 8,192 for the Python reference. The Python reference runs
  about 0.6 to 0.8 million steps per second on this host. At 65,536 steps it
  would hold the owner lock for 90 to 110 ms per boundary and gain nothing,
  since its boundary overhead is already about 1% at 8,192.

Akashic production is unchanged. No compiled Forth cache, step budget change,
guest timing change, or harness change is involved.

## Method

Runs used the tracked `local_testing/physical_typing_cadence.py`: a fresh
source-mode Desktop image, the physical X11 viewer, one isolated character,
then eighteen characters at 5 Hz. MegaPad was at `182ee52` with the default
still 8,192, and `MEGAFORTH_QUANTUM_STEPS` selected each size. Every run ran
alone, in alternating order, under the runner's 900 s watchdog and 3.5 GiB
aggregate-RSS stop.

- Three unprofiled rounds: 8K→128K, then 128K→8K, then 8K→128K.
- One profiled round with the archived first-character observer from
  `simulator-calls-20260917`. It attributes host time for the isolated
  character; its latencies are not used as the measurement of record.

The host was shared with another project using four of sixteen cores. Load
averages were 7 to 14 during the runs. All slow runs are kept.

## Results

All runs show all nineteen characters. The saved ready, first-character and
final screenshots are pixel-identical across all 22 typing runs in this
report, at every quantum.

Unprofiled medians of three runs:

| Quantum | Isolated | Burst median | Final drain |
| ---: | ---: | ---: | ---: |
| 8,192 | 649 ms | 1,076 ms | 1,039 ms |
| 32,768 | 503 ms | 648 ms | 579 ms |
| 65,536 | 416 ms | 561 ms | 611 ms |
| 131,072 | 459 ms | 612 ms | 563 ms |

Individual isolated values: 8,192: 622, 649, 750 ms. 32,768: 503, 546,
491 ms. 65,536: 404, 511, 416 ms. 131,072: 500, 459, 418 ms.

The gain is in the input-to-frame stage, from input acceptance until the
viewer sees the new frame. Its median is 496 ms at 8,192, 367 ms at 32,768,
287 ms at 65,536, and 322 ms at 131,072. Viewer reconstruction (47–67 ms),
composition (62–72 ms), and flip plus acknowledgement (10–12 ms) do not
depend on the quantum.

## Why larger quanta stop helping

The profiled round shows the first character's host time:

| Quantum | Boundaries | Boundary wall | Native | Settlement | Other host time | Guest steps |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8,192 | 1,973 | 388 ms | 164 ms | 14.7 ms | 209 ms | 16.16 M |
| 32,768 | 508 | 344 ms | 201 ms | 9.9 ms | 133 ms | 16.65 M |
| 65,536 | 269 | 351 ms | 217 ms | 9.0 ms | 125 ms | 17.63 M |
| 131,072 | 138 | 345 ms | 220 ms | 8.1 ms | 117 ms | 18.09 M |

Two effects meet. Host time outside native execution falls steeply up to
32,768 steps, then flattens. The remaining part is per-frame work, mostly
host processing of the published output, which does not depend on the
number of boundaries.

Meanwhile guest steps rise with the quantum. The added steps fall in the
"other" phase: the app shell's polling loop. The guest only learns of host
events, such as admitted input or a processed transaction, at a boundary, and
it keeps polling until then. Larger quanta make each of those waits longer.
At 65,536 steps a native boundary lasts about 1.3 ms in the Desktop, so these
waits add little latency, but 131,072 shows no further gain.

65,536 is past the point where boundary overhead stops mattering, without
the longer waits of 131,072.

## The guest never idles

The traces also show that the Desktop guest never stops executing. Between
the ready frame and the first key, about 0.87 s with no input, the step
counter keeps advancing at the full rate: about 30 million steps per second
at 8,192 and 70 million at 65,536. The app shell's event loop is
non-blocking by design. It services the terminal owner, polls input, drains
deferred actions, checks the 50 ms tick, paints when dirty, and calls
`YIELD?`. It never waits in `IDL`, so it spins even when nothing happens.

This is not caused by the quantum change and does not affect this report's
measurements. It does mean the simulator keeps one host core fully busy while
the Desktop is open, and the real device would spend the same polling work.
Blocking until input or the next tick deadline would fix both. That change
touches the app shell, the terminal owner, and MegaPad's idle wake, and is
recorded here as separate follow-up work.

## Qualification

- MegaPad focused selectors pass 397 tests on the Python default and 44
  native-selected session tests. The full simulator suite passes 2,221 of
  2,222 tests on each executor. The one failure,
  `test_kdos_file_abstraction.py::test_signed_capacity_and_eof_guards_reject_safe_high_bit_cases`,
  fails the same way at `4fcb671`, before any quantum change.
- At `a649f32`, without the environment override, server status reports
  65,536 steps. Two alternating pairs against an explicit 8,192 ran in the
  order default, 8,192, 8,192, default:

  | Quantum | Isolated | Burst median |
  | ---: | ---: | ---: |
  | 65,536 (default) | 473, 464 ms | 622, 664 ms |
  | 8,192 | 662, 675 ms | 1,001, 1,054 ms |

  One earlier confirmation run at the default measured 909 ms isolated.
  During it the whole host was slower: session preparation took 52 s
  instead of about 39 s, and viewer composition, which does not involve the
  simulator, took 116 ms instead of about 64 ms. It is kept in the evidence
  but is not comparable. A single 8,192 run straight after it measured
  743 ms, also under uneven load.
- The canonical 22-stage physical Desktop journey passes at `a649f32` through
  `local_testing/physical_desktop_acceptance.py`: 18 milestones in the usual
  order, 21 revision-bound inputs with no manual input, 27 physical
  acknowledgements, and both CELL fallback checks (offers 1 and 27). It took
  181.3 s at a peak aggregate RSS of 439.4 MiB. The earlier 125.4 s run was
  on a less loaded host, so the times are not comparable. The native binary
  is unchanged (`120704da…`).

## Evidence

`local_testing/evidence/simulator-quantum-20260926.json` records bindings,
every run's summary and raw-file hashes, the stage and phase breakdowns, and
the analysis script hashes. Artifacts are in
`local_testing/out/simulator-quantum-20260926/`, which is ignored.
