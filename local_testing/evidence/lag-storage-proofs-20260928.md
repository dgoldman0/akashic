# Repeated storage proofs and Desk lag — 2026-09-28

Every Desk input took one to two seconds in the canonical journey, whether
it was a typed character, an arrow key, or a task switch. This note records
how that time was attributed, the first redundancy removed, and what the
measurements now say about the remaining lag.

This is diagnostic and performance evidence. It is not UART, panel, or touch
evidence, and single typing runs vary between runs.

## Tools

The guest phase profiler only worked on the emulator, so two tools were
added:

- MegaPad `fc33b39` samples the packed phase cell (`_RTPROF-EVENT`) after
  every semantic boundary in the simulator. It reports no fixed interval
  bound, because a boundary can run past its quantum.
- Akashic `59e197a3` lets the summary accept that unbounded sampler.

A scratch wrapper around `simulator_server.py` also charged each boundary's
semantic steps to the suspended guest call stack. It recorded inclusive and
exclusive totals and caller-callee edges over the full journey. It changed
no guest dispatch or timing.

## Finding

Over the canonical journey, after the first offer:

| Share of all guest steps | Where |
| ---: | --- |
| 64% | `_ASHELL-TERM-SERVICE`, the terminal service at the top of every shell loop pass |
| 40% | `RTAPTSCB-VALID?`, the publisher's validity check at the start of each step |
| 27% | three `RTAPT-STORAGE-DISJOINT?` queries inside that check |
| 14% | `_RTAPT-ENGINE-RANGES?`, the engine's layout check |
| 22% | the rich frame pipeline, across all of its phases |

Each engine query re-proved the engine's own fixed geometry: its record, its
session record and four banks, and 5 PT and 15 pairwise overlap checks. It
did this before checking the span it was asked about. That geometry is
written only by `RTAPT-INIT` and `PT-INIT`, so every repeat after the first
was redundant.

## Change

- MegaPad `9dd752a` adds `PT-LAYOUT-SERIAL@`. It names the `PT-INIT` that
  fixed a session's borrowed spans: nonzero, never reused, and zero for an
  invalid session.
- Akashic `4a7a79f9` merges the engine's two copies of the geometry proof
  into one stack-only word. The engine's own storage check keeps a
  successful proof with an exact copy of every field it read and the
  session's layout serial. The proof is accepted again only while all of
  them are unchanged.
- The authority query accepts a kept proof but never keeps one. It stays
  stack-only.
- The bounded tails of the mutable banks are still checked every time.

A new test shows the change is safe. A changed bank field is refused. A
session initialized again over the engine's operation bank is refused
through its new serial. A copy of the engine that ignores the serial fails
that test.

## Results

Canonical physical Desktop journey on the committed trees:

| | Before (`911dc0a6`) | After (`4a7a79f9`) |
| --- | ---: | ---: |
| Result | pass, 48/51 | pass, 48/51 |
| Guest steps at the first offer | 408.9M | 261.8M |
| Guest steps at the last event | 6,852.5M | 5,977.4M |
| Peak aggregate RSS | 492,318,720 B | 492,953,600 B |

The stack samples show that `RTAPTSCB-VALID?` fell from 39.7% to 27.3% of
guest work. The engine query fell from 27.3% to 15.4%. The frame capture
phase fell from 490M to 340M steps over the journey.

Typing cadence was measured in one run each, from the same host session. The
"before" run used clean worktrees at Akashic `59e197a3` and MegaPad
`fc33b39`:

| | Before | After |
| --- | ---: | ---: |
| Single character, due to visible | 0.563 s | 0.557 s |
| Burst median, five characters per second | 1.015 s | 0.906 s |
| Burst worst | 1.579 s | 1.378 s |
| Guest steps over the run | 684.0M | 511.9M |

## What the measurements say about the remaining lag

The guest steps counted between an input and its next offer are mostly not
work. The phase profile splits each input's window into three parts (median
of 51 inputs):

- 48M steps before the first pipeline phase;
- 18M steps in the pipeline;
- 44M steps after the last phase, while the guest waits to be observed.

The guest keeps passing through its service loop while it waits, so cheaper
passes add more passes in the same time. That is why the per-input step
count did not fall, while the journey total, startup, and capture work did.

For one typed character, about 0.40 s passes from dispatch until the client
observes the offer. That span includes the guest's work and the simulator
host's delivery. Another 0.13 s goes to the viewer's projection and
composition. The removed proofs did not shorten the 0.40 s, so what
dominates it still needs its own breakdown.

The remaining validity checks at the adapter and publisher layers
(`_APTSCB-CONTEXT-VALID?`, `APTSCB-PUBLISHER-VALID?`, `RTHP-VALID?`) cost
about 5 to 9% each, and some run twice in one call.
