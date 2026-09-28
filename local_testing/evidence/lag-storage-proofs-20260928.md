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

## Second slice: the control ledger, and where one key's time goes

A timing observer in the simulator server recorded absolute times for each
owner boundary during typing. For each boundary it recorded the guest batch,
the driver service around it, the admitted events, and the host driver's
received publications, along with every input RPC's arrival and the guest
call stack. Aligning it with the typing harness's own trace gives each key's
exact path. For the single first key of one run (0.384 s in total):

| Span | Time | Side |
| --- | ---: | --- |
| Harness sends the key after its due time | ~19 ms | harness |
| Key waits for the next guest boundary | ~8 ms | simulator |
| Guest takes the key, paints, builds and records the frame | ~120-190 ms | guest (device too) |
| Host driver applies the frame and builds the offer | ~35 ms, plus ~17 ms inside the publishing batch | simulator |
| Offer packaging, transfer, and the client's next poll | ~50 ms | simulator |
| Viewer projection, composition, flip, and acknowledgement | ~100-110 ms | simulator |

Across typed keys, 91% of the guest's work sits in the frame builder
(`RTHP-PREPARE`). Desk's own painting is about 3%. Within the builder:

| Share of per-key guest work | Stage |
| ---: | --- |
| 24% | comparing the candidate with the previous target (slot and control maps) |
| 21% | hybrid admission of the whole candidate, including UTF-8 checks of every text run |
| 12% | the aggregate snapshot of the edited document |
| 11% | residual planning of damaged rows |
| 9% | recording control changes, mostly `_RTAPT-CONTROL-LEDGER-VALID?` |

The ledger check walked every control entry and its owner on each recorded
control define and replace. The engine writes the ledger only when it
reconciles a completed transaction, clears an owner, or quarantines, and
each of those needs an idle engine or an active transaction. Recording needs
a capturing engine with none. `RTAPT-RICH-BEGIN` audits the ledger before
capture, and the publication audit rescans it and checks every recorded
change against it. Akashic `538b4020` therefore stops the per-call rescans.
It also removes a second complete audit that `RTAPT-RICH-BEGIN` ran through
`RTAPT-LIMITS@` straight after its own.

With the observer in both runs, one run each:

| | After `4a7a79f9` | After `538b4020` |
| --- | ---: | ---: |
| Guest steps per key window | 3.54M (24 windows) | 3.09M (22 windows) |
| First key's guest work | 11.53M steps | 10.75M steps |
| Control recording share of the builder | 13.3% | 6.4% |
| Single character, due to visible | 0.384 s | 0.341 s |
| Burst median | 0.711 s | 0.612 s |

The canonical physical Desktop journey passes on Akashic `538b4020` with
MegaPad `9dd752a`: exit 0, 48 milestones and 51 inputs, and peak aggregate
RSS 492,003,328 bytes. Its total guest steps rose to 7,060M, against 5,977M
at `4a7a79f9`, while its wall time fell from 220 s to 175 s. In that run the
host executed the guest at a median 61M steps per second between offers,
against 39M. The guest's waiting loop fills whatever time the host and viewer
take, so journey step totals follow host speed and waiting, not work. The
per-key windows above are the work measure.

What remains of one key's guest work is mostly whole-frame work: comparing,
admitting, and snapshotting the complete candidate for a one-character
change. Reducing it further means making those stages follow the damage
instead of the whole frame, which is a design change rather than removing a
repeat. About half of a single key's time on the simulator is host and
viewer work in Python.
