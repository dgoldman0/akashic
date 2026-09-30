# PANE/TASKBAR desktop qualification

PANE and TASKBAR passed the complete native-simulator Desk qualification on
2026-09-30, together with the previously qualified Grid, STATUS_FIELD, FIELD
and SERIES/WAVEFORM paths. The frozen run reports `complete: true`, all 52
ordinary journey stages complete, launcher exit 0 and clean shutdown.

## Executed path and scope

The real `megapad.main --mode simulator --executor native` entry point prepared
and ran Desk at 280×84 cells, delivered acknowledged input and composed flowing
pixels. SessionServer requests used direct in-process dispatch; SDL used a
dummy software sink. Socket transport, a physical display, audio playback and
UART are outside this run's scope. Runtime metadata remained simulator/native
with `machine_code: false`; this is not a hybrid or prepared machine-task Desk
run. The paired runtime's separate prepared-task qualification is recorded in
its `TASK-RUNTIME-INTEGRATION.md`.

The runner freshly linked 242 modules in 41 chunks and prepared 12,805,821
semantic steps before executing with a 65,536-step semantic quantum. The
52-stage journey covered menus, ordinary launching, list scrolling/selection,
rename drag/edit/cancel, multilingual Pad/Daybook input, Markdown and link
following. Typed Grid PLACE selected B2/item key 18 and returned ordinary
selection revision 59. STATUS_FIELD counts changed from 4/2/2/2/6/0 across the
initial panes to 4/2/2/2/6/3 after Sound Lab launched; authored status values
changed and all final panes had coverage.

FIELD checks acknowledged a three-step frequency adjustment, signed-64-bit
extreme adjustments clamped to 2000 and 40, and reverse CHOICE wrap to index 4.
ACTIVATE opened the ordinary exact-value prompt and cancellation restored the
four fields. Prompt checks still required actual whole-CELL fallback evidence.
Typed status, field and shell metadata never became substitute visible-text
markers.

## Acknowledged shell and ordinary input

Five paused-source comparisons checked the ordinary SHSN model against the
immutable acknowledged RSHSP bank and every retained shell claim. Each check
bound owner/generation, completed draw, screen generation, active target,
durable PRESENT completion and copied model bytes to the exact offer scope.
The source reader authenticated native lifecycle and catalog correlations;
it did not infer component authority from painted titles or application names.

| Shell snapshot | Offer / retained revision | Draw / epoch | Visible panes | Observed ordinary state |
| --- | --- | --- | ---: | --- |
| Baseline | 151 / 155 | 145 / 145 | 6 | Component `(6, 9, 9)` selected |
| Task ACTIVATE | 153 / 157 | 146 / 146 | 6 | Component `(1, 3, 3)` selected |
| Alt+M | 155 / 159 | 147 / 147 | 5 | `(1, 3, 3)` minimized; task remains present |
| Minimized task ACTIVATE | 157 / 161 | 148 / 148 | 6 | `(1, 3, 3)` restored and selected |
| Catalog LAUNCHER ACTIVATE | 159 / 163 | 149 / 149 | 6 | Component `(2, 4, 4)` selected |

Component tuples are signed host slot, child owner ID and child generation.
All six task identities remained stable, with exactly one selected task and
two TASKBAR roots throughout. Minimization removed only the target PANE;
restoration recovered the exact original pane outer/content geometry. Task
slot widths followed the ordinary model, including its selected-label width.

The four accepted inputs used acknowledged task IDs 77718 and 79694, ordinary
`alt+m`, and acknowledged launcher ID 80715. The latter matched native action
`org.akashic.fexplorer`, catalog generation 7, selector 2 and running component
`(2, 4, 4)`. This proves direct catalog activation/focus of an already running
component; it does not claim a new instance was created by this probe.
Unaccepted backpressured input is resolved again against the same ordinary
component when a new START replaces retained IDs.

## Full waveform preservation and current limitation

All 13 SERIES probe stages passed. Ordinary FIELD activation set duration to
2000ms and ordinary F5 rendered 16,000 samples. Every signed 64-bit value and
timestamp matched the paused ordinary Sound Lab canonical UDG: interval 125µs,
first timestamp 0 and last timestamp 1,999,875µs. Changing amplitude from 75%
to 40% produced a different complete history, again compared sample for sample.

| Acknowledged offer | History identity | WAVEFORM ID | Evidence |
| --- | --- | ---: | --- |
| 137 | `(1, 1, 47)` | 69762 | First full render, 75% amplitude |
| 149 | `(1, 1, 49)` | 76728 | Changed full render, 40% amplitude |
| 151 | `(1, 1, 50)` | 77745 | Ordinary selection redraw, unchanged source and samples |

All three retained waveform bounds were `[188, 54, 278, 66]`. The first sample
SHA-256 was `f3f4a68dd3897f155e03c306f7cb3ac5042fa405ecb9b7e16a26ddda1a55fbf2`;
the changed render and redraw both had
`5dcb18ee44497dee2e657f759826447d5d79d38aa7a3c850a10ecf158d030bd3`.
Their corresponding source graph hashes were
`b49a7e1e1a508e46ceaf0e701dcae506443bf67d9778c90b6f67370f5dc660cc` and
`ebdf98283326532f08738190785b2af777066c9fcd1f273e741f750e38e5a400`.

The shell currently publishes complete START/reveal replacements on changed
draws. The report explicitly records `publication_mode: shell_full_replacement`,
`stable_reuse: null` and successful `redraw_preservation`. Selection moved from
Amplitude to Duration while preserving bounds, all samples and the ordinary
source graph, with newly assigned history/object identities. This qualifies
data preservation, not retained identity reuse or cross-transaction streaming.
The standalone SERIES path retains its separate strict identity-reuse evidence
in [SERIES-DESKTOP-QUALIFICATION.md](SERIES-DESKTOP-QUALIFICATION.md).

## Timing, memory and shutdown

| Measurement | Observed run |
| --- | ---: |
| Launcher startup, including preparation | 30.644805786s |
| Desktop ready | 39.509288245s |
| Final milestone of the 52-stage journey | 225.747616518s |
| Full journey, Grid/FIELD/SERIES/shell probes and cleanup | 336.833311859s |
| Peak process RSS | 302,321,664 bytes (288.31640625MiB) |
| Acknowledged offers across the full run | 159 |

These are functional-run measurements, not a controlled performance comparison.
The total includes source reads, composed image capture, both complete waveform
comparisons and four extra shell actions after the ordinary journey. It is not
directly comparable with an earlier shorter simulator smoke run.

| Guest storage | Configured capacity | Largest observed use in the five shell snapshots |
| --- | ---: | ---: |
| Sidecar work arena | 8,388,608 bytes (8MiB) | 3,490,336 bytes |
| Each immutable sidecar A/B bank | 4,194,304 bytes (4MiB) | 318,456 bytes in the active bank |
| Ordinary/copied shell model | 49,152-byte source bank bound | 24,065 copied bytes |

The work value includes the candidate builder's temporary reservation high-water.
The report's `memory_max` aggregates these five snapshots; it is not continuous
instrumentation of every frame or proof of the global worst case. Its
`work_capacity` and `bank_capacity` entries remain configured ceilings even
though they appear under that name. The two immutable banks each reserve 4MiB;
318,456 bytes is not their combined capacity.

The authenticated RTHP arena capacity was 94,107,960 bytes. The launch configured
384MiB external memory, 1MiB RAM and 4MiB VRAM. These are declared guest limits,
not measured resident usage and not quantities to add to process RSS. SERIES
limits remained 32,768 samples per history, 65,536 total reserved sample slots
and 4,096 samples per append.

The server, owner thread, semantic backend, display lease, runtime owner and
terminal driver all closed cleanly. `terminal_events` was empty; no runtime or
terminal failure was recorded.

## Integration corrections exercised

Three corrections were necessary before this passing frozen run:

1. A fully visible ordinary instrument root could legitimately omit an explicit
   clip. The shell now normalizes only its owned copied rows to the same
   effective clip, preserving logical coordinates and existing partial clips.
   Instrument-plan rows receive a separate owned copy to preserve source-span
   disjointness. Out-of-pane and mismatched attachment cases still refuse.
2. The acceptance reader's arbitrary 64MiB arena cutoff rejected the genuine
   94,107,960-byte RTHP arena. It now mirrors the native unsigned, nonwrapping
   arena contract while retaining exact TARGET0/1 membership and a bounded
   336-byte target-header read. It does not infer a large memory read from the
   declared capacity.
3. A hidden START ACK consumes all shell IDs before visible REVEAL. The new
   START-ACK hook validates the exact immutable pending tuple and advances
   region/object frontiers monotonically, without publishing input authority.
   A newer draw can safely supersede that hidden candidate. Previously it
   attempted region 54 after the provider had already accepted IDs through 61.

The dedicated real-provider regression passed three cases in 8.28s, including
red reproduction with the new hook suppressed, successful recapture before
REVEAL, source invalidation, malformed pending tuples and abort/MAX boundaries.
It drives real provider acknowledgements but uses a caller-built legacy fixture
and extension dispatcher; its final sidecar PUBLISH is explicitly called after
real host REVEAL. The full Desk run supplies the public composition and complete
visible-publication evidence. The test-only follow-up commit is `037553b`;
production behavior is the frozen `a6cf346` checkpoint.

The composed PNG was visually inspected: six panes, canonical taskbar slots
and the full waveform are present within the existing geometry. Local font
coverage still produces missing-glyph boxes in the Daybook multilingual fixture;
this does not indicate an encoding or ordinary-source failure. Dense Sound Lab
analysis labels/readouts also remain crowded. This is functional object/input
qualification, not final font coverage or pixel-level design approval.

## Frozen sources and evidence

MegaPad: `7b2746d75911f83cf92802bb75c01410fbb7df5c`, no tracked diff.
Akashic: `a6cf3465dad6399050a261c1d30e0f91bf340c5f`, with only the shell-enabled
paired-profile diff in `local_testing/akashic_tui.py`.

| Recorded digest | SHA-256 |
| --- | --- |
| MegaPad tracked diff (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Akashic tracked diff | `82e6e0fa9aa9e77bf0240f9d12685d0de48851b5a36d5980b2677de8b058b25b` |
| Fresh prepared image | `25fd145c24859a958c3ac01d1b7fdb3f2e6d323743a1e2000cbc0dd34cfaf334` |
| `result.json` | `d6116500061de227411862de2fad62f9aebdf003c3bde30e734bf07d1cfa48f9` |
| `shell-offer.json` | `5f4a2c67186c16b9c1af2841f0f96379abd0cd5eac39c6e62e00e0b97e2b25f8` |
| `Desk-Shell-Verified.png` | `7e9fbcdd27a699e39255c73b837d7518704444f96f92c24b74ef18f0b26fbd7b` |

The frozen Akashic tree is
`/workspace/scratch/64bce13821f6/akashic-shell-qualified-20260930`.
The paired MegaPad tree is
`/workspace/scratch/64bce13821f6/megapad-flowing-machine-integration`.
Its `build/shell-qualified/` directory contains the report, fresh image,
acknowledged offers, `Desk-Shell-Verified.png`, `Desk-Series-Verified.png` and
`Desk-Simulator-Final.png`. The full log is
`/workspace/scratch/64bce13821f6/shell-qualified.log`.
Earlier failed runs are separate diagnostic evidence and contribute no pass
metrics to this document.

## Selected-profile equivalence

After the frozen run passed, the registered rich Desktop profile was switched
to the same explicit 8 MiB work / 4 MiB bank helper result. The shell-off base
remains available for fallback checks; `desktop-apt1-small-terminal` retains
that base. The host's `reference` appearance remains the default and `flowing`
remains opt-in.

All 153 focused packaging, shell composition and cold-series-storage tests
passed through the paired Make supervisor in 48.70s. The selected profile's
280×84 guest/host configuration exactly equals the frozen run's configuration.
A freshly prepared selected-profile image differs only in MP64FS directory
creation timestamps. Restoring the original 72 timestamp fields reproduces
the exact recorded pre-run image SHA-256 above, without changing file payloads.
The journey had cleared the Daybook timestamp; its original value was recovered
from the two observed build seconds by matching that pre-run digest. This is
configuration and image-content equivalence, not a second full Desk execution.
The local comparison is recorded in `/tmp/shell-activation-equivalence.json`.

## Reproduction

From the recorded Akashic source/profile checkpoint, using the paired native
runtime build:

```sh
MP64_RUNTIME_NAMESPACE=shell-qualification python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output /path/to/megapad/build/shell-qualified \
  --deadline 480 --require-status-fields --require-fields --require-series --require-shell
```

The qualification interpreter was
`/workspace/scratch/64bce13821f6/runcheck-venv/bin/python`. The runner rebuilds
the image and writes exact scope/input, ordinary source, resource and cleanup
evidence alongside the composed images.
