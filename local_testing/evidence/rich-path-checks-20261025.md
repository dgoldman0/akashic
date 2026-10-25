# Checks in a typed letter's frame — 2026-10-25

A thin rich path is under discussion: one that keeps the rich terminal's
protection against bad data and bad state but drops checks that cannot find
anything new. This note measures how much of a typed letter's rich frame
build is spent on checks, and sorts every check that costs measurable steps
by what it protects and when it could find something.

This is measurement on the simulator, plus a reading of each check word's
source. Steps are the simulator's semantic steps. None of this is device
timing, UART, panel or touch evidence, and the note proposes no design.

## Bindings

The run bound clean trees.

| Binding | Value |
| --- | --- |
| Akashic | `1b566fc3b32600df7eed3b33dfe976ada5575643` (tree `210f704ec2da26581314a5f6d74a7f1c516b76d0`), main |
| MegaPad | `2faa96d882dbfd4a6ec300fac960681644f88cc2` (tree `331bfad08e3990cbc4de72c3bcd5d827d3279f6e`), main |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | `assets/fonts/DejaVuSansMono.ttf`, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |
| Harness | `physical_typing_cadence.py`, SHA-256 `124c5d93b95f33e41b7029d4d91a0db444e57499f388456588e44e0ecdbf427b` |

## Run

One typing cadence run on the native simulator at 280 × 84:

```text
PYTHONHASHSEED=0 MEGAPAD_PROFILE_CHAINS=0 MEGAPAD_PROFILE_CHAIN_DEPTH=0 \
TMPDIR=/dev/shm/... local_testing/physical_typing_cadence.py run \
  --label baseline --screen-profile --output-parent /dev/shm/... \
  --akashic-root akashic --megapad-root megapad \
  --font akashic/assets/fonts/DejaVuSansMono.ttf
```

All 19 characters showed. The run took 17.0 seconds with a peak aggregate
RSS of 460 MiB, under the 900-second watchdog and the 3.5 GiB stop. It
started after an uncapped wait for another session's tests to finish, and a
watcher that looked every five seconds found no other test running during
it. Its output stayed in `/dev/shm`, and it wrote 3.5 MB to the drive. The
run's files were deleted after this note was written.

The burst of 18 characters made 15 frames, all DELTAs. Its frame build of
16.16 million steps a frame matches part 0 of
[FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md),
16.13 million on 2026-10-19, which measured the same Forth.

## How the steps are charged

`local_testing/frame_checks.py`, new with this note, reads the run's
profile. It charges each call chain under the frame build
(`_RTHP-PREPARE-LIVE`) to the outermost check word on the chain, and that
word to one of four groups:

- **Repeats** check data that nothing has written since it was last checked,
  or that the frame has just built from parts it checked.
- **Handover proofs** check memory layout: headers, and spans proved apart
  from other storage. Their answer can change only when memory is handed
  over or grows.
- **Item checks** check the items a frame sends, when a capture reads them
  or the engine admits them.
- **State checks** ask whether a draw, owner or acknowledgement is still
  current.

Words that mix checks with real work, such as the engine's admission
(`RTE-HYBRID-PREFLIGHT`), are not check words, so the checks inside them
are found instead. The backend's capacity and feature preflights are counted
apart as fit, less the engine audit they call. Whatever no group or fit
claims is the frame build's other work: building, copying and comparing.

The profile charges the steps run since each host boundary, about every
65,536 steps, to the chain the guest stopped in. Over the burst's 15 frames a
check costing 0.05 million steps a frame gets about a dozen samples, so the
smallest rows below are rough. The isolated character is one frame, and its
rows move in steps of about 0.07 million.

## Result

Millions of steps a frame:

| | Burst frame | Isolated character | When the check can find something new |
| --- | ---: | ---: | --- |
| Frame build | 16.16 | 25.76 | |
| Repeats | 5.08 | 7.08 | only after a bug has written where it should not |
| Handover proofs | 2.95 | 3.21 | when memory is handed over or grows |
| Item checks | 1.74 | 5.90 | when an item changes |
| State checks | 0.07 | 0.00 | every frame |
| **All checks** | **9.85 (61%)** | **16.19 (63%)** | |
| Fit | 0.03 | 0.00 | every frame |
| Other work | 6.28 | 9.57 | |

Checks take 61% of a typed letter's frame build: almost 10 of its 16 million
steps. The checks that can find something on every frame cost little: 0.07
million for state and 0.03 million for fit. Most of the rest re-proves
memory layout that has not moved, re-checks items that have not changed, or
checks again what the same frame or an earlier one already checked.

The isolated character spent 5.90 million on item checks, against 1.74
million in a burst frame. Many of its items differed from the engine's kept
copy, so the engine ran their full record and text checks: 0.85 million for
controls and 2.42 million for glyph runs, 1.64 million of it reading their
UTF-8 text. That shows roughly what checking this screen's items in full
costs.

## Repeats: 5.08 million a burst frame

| Check | Steps | What it checks | Why it finds nothing new |
| --- | ---: | --- | --- |
| `UCSN-FROZEN-VALIDATE` | 1.06 | Before RUHA reuses another document's stored collection slice, it validates the slice in depth. | RUHA captured and checked the slice in an earlier frame. It checks again because Desk lends it the banks; part 5 of FRAMES-FOLLOW-CHANGE makes them RUHA's own and ends this. |
| `_RSHSP-BANK-VALID?` | 0.80 | After freezing, the shell checks the whole frozen bank: its layout, the shell model again, the graph, the batch's measure and its identity frontiers. | The bank is a proved copy of the batch the family preflight admitted earlier in the frame. |
| `_RTHP-W-MENU-REUSE-PREFLIGHT?` | 0.58 | Menus the producer copies from its acknowledged bank are checked again, control by control, with their texts and correlations. | Each was admitted when it was first sent, and the acknowledged bank is the producer's own. |
| `_RTAPT-ENGINE-VALID?` | 0.56 | The APT-1 engine audits its whole state, from its storage to its control and owner ledgers and its queue, at each backend call: the limits query and both preflights. | Only the engine writes that state. |
| `RTE-FAMILY-BATCH-VALID?` | 0.46 | The family preflight checks the shell batch's structure: every pair of regions, the catalog and every family. | For a typed letter the shell rebuilds the structure it built and checked last frame, around application controls the engine admitted earlier in this one. |
| `_RTE-FEM-AUTHORITY?` | 0.26 | Emission proves the batch's spans apart from the shell's and the engine's storage. | The family preflight proved the same spans earlier in the frame. |
| `_RGRP-CLAIM-VALID?`, `_RGRP-RANGE-AUTHORITY?` | 0.39 | The residual glyph planner checks every claim and proves every span on each of its ten to fourteen calls a frame. | The claims and spans are the same on every call in a frame. |
| `_RTHP-D-CONTROL-TEXT-SPANS?`, `_RTHP-TEXT-WITHIN?`, `_RTHP-D-REF-VALID?` | 0.30 | The comparison checks that each control's texts and each glyph reference lie inside the producer's packs. | The producer built those packs itself, and the engine admitted their items. |
| `_UTUI-MC-RELATION-VALID?`, `_UTUI-RS-TARGET-VALID?`, `UTUI-RESOLVED-VALID?` | 0.27 | UIDL-TUI re-validates each cached mounted-widget relation and resolved target in depth: element, widget, generation and region ancestry. | This asks whether a cache is still current, a state question. Once widgets count their changes (FRAMES-FOLLOW-CHANGE part 2), comparing revisions answers it. |
| `SHSN-FROZEN-VALIDATE` | 0.13 | The shell validates its copy of Desk's shell model. | When the model has not changed since the last frame, this finds nothing new. When it has, this is the first check of new data and belongs with the item checks. |
| `_RUCL-VALIDATE-ONE?` | 0.10 | The claim ledger validates each record of the menu snapshot. | The menu snapshot checked those records when it built them. |
| Others | 0.17 | Other stored slices before reuse (`USFSN-FROZEN-VALIDATE`, `UFLSN-FROZEN-VALIDATE`), the shell planner's model and the clone's batch bounds, statics and single controls. | As above. |

## Handover proofs: 2.95 million a burst frame

| Check | Steps | What it proves | When the answer can change |
| --- | ---: | --- | --- |
| `_RUHA-STORAGE-DISJOINT-CURRENT?`, `_RUHA-SCREEN-STORAGE-DISJOINT?`, `_RUHA-O-SPAN?` | 0.97 | RUHA's banks lie apart from the screen's storage and from all storage of each attached document, every mounted widget included. It proves this once for the frame and again for each document. | When a document attaches, when its widgets get new storage, or when RUHA's banks change. |
| `_RSHSP-AUTHORITY?`, `_RSHSP-HEADER?` | 1.01 | At each of the shell's dispatches, about six a frame, the headers of the producer, engine, adapter, shell snapshot and shell facade are valid, the shell's four spans lie apart from all of them, and RUHA's banks lie apart from those spans. | When one of them is built or grows. |
| `_RSHFC-SOURCE?` | 0.25 | Freezing measures and then copies the shell's batch, and each pass proves every span of the batch apart from the region catalog's and the clone's own storage. | When the shell's work space, which holds the batch, grows. |
| `_UCSN-RANGES?`, `_UFLSN-AUTHORITY?`, `_USFSN-AUTHORITY?`, `_UDLSN-AUTHORITY?`, `_UMSN-RANGES?` | 0.31 | Each capture's caller spans, RUHA's banks, are well formed and lie apart from the document's storage. | When RUHA's banks or the document's storage change. |
| `_RTE-FA-AUTHORITY?`, `_RTE-HPV-FIXED-AUTHORITY?` | 0.16 | The admitted batch's and candidate's storage lies apart from the engine's. | When the producer's or the shell's storage is allocated or grows. |
| Others | 0.25 | Headers of the shell snapshot and the producer's banks (`SHSN-VALID?`, `_RTHP-TARGET-BANK-HEADER?`) and other span proofs. | As above. |

## Item checks: 1.74 million a burst frame

The engine's admission walks every control and glyph run of the candidate
on every frame. For controls (`_RTE-CONTROL-PLAN-VALID-BODY`, 0.84
million) it checks every control's spans, graph, correlation and totals,
about 0.61 million. A compare with the engine's kept copy, 0.12 million,
then decides which controls get the full record and text checks, and those
took 0.07 million. Glyph runs (`_RTE-HPV-GLYPH?`, 0.62 million) are compared
with the kept copy the same way, 0.27 million, around their structural
checks. Statics took 0.08 million.

The captures' own checks took 0.20 million: the texts and resolved elements
of the edited document's menus, collections and status fields
(`_UMSN-TEXT?`, `_UCSN-V-ARGS?`, `USF-VALIDATE` and others). They run on
every element of the edited document, because that document is recaptured
whole on every frame.

Checking each item once, when it changes, keeps the record and text checks
of changed items and the captures' checks of changed elements. For a typed
letter that is the text area, the caret and the status line: on the order
of 0.1 million steps, an estimate from the 0.07 million the changed controls'
checks took here. Admitting an item also checks that it fits what the
terminal accepted; that is the fit row, 0.03 million.

## State checks and fit

The state checks cost 0.07 million a burst frame:
`_RTHP-TG-APPEND-CURRENT?` and `_UTUI-SFI-CURRENT?`. Two currency words,
`_RTHP-ACTIVE-DRAW-CURRENT?` and `_UTUI-MI-CURRENT-VALID?`, are counted as
wrappers: their own comparisons are small, and the work inside them, a
shell dispatch's proofs and a relation's re-validation, is charged above.
Fit, the backend's capacity and feature preflights less the engine audit,
cost 0.03 million.

## What follows from the sorting

The checks that can find something on every frame, state and fit, cost
about 0.1 million steps a typed letter. Checking items once when they change
would add about 0.1 million more, by the estimate above. Handover proofs,
run only when memory is handed over or grows, would cost nothing on most
frames. The repeats can only find a bug that wrote where it should not;
behind a switch that tests turn on, as the shadow check is, they would still
run wherever tests look for bugs. Under that sorting, a typed letter's frame
would spend roughly 0.2 million steps on checks instead of 9.85 million.
That figure is an estimate from this run's rows, not a measurement of any
built change.

The other 6.28 million steps of the frame build are building, copying and
comparing the whole screen. FRAMES-FOLLOW-CHANGE takes those on.

FRAMES-FOLLOW-CHANGE keeps every boundary check at every boundary. Its parts
5 to 8 remove some repeats with proofs: part 5 the reused slices'
re-validation, parts 6 and 7 the checks of unchanged items through kept
copies, and part 8 the proofs repeated within one frame. Under its rules a
handover proof still runs on every frame, and the engine audit is not among
its parts. Running them only at handover, or behind a test switch, needs a
decision on those rules.

## Limits

- One run of one journey: typing on the canonical typing Desktop, whose
  frames are DELTAs. START frames, Desk with other applications, Desk's
  painting and the CELL flush were not measured here. Part 0 found painting
  and the CELL flush as costly as the frame build outside typing.
- Checks outside the frame build, such as input validation and Desk's own
  checks, are not counted.
- The groups come from reading each check word. A few words mix purposes,
  and their rows say so. The tool's word lists record each assignment.
- Sampling makes rows under about 0.05 million steps a frame rough.
