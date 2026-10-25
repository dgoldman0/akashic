# Part 3: checks run when they can find something — 2026-10-25

Part 3 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
puts the rich path's repeated checks and its per-frame handover proofs
behind a switch, every-frame checks. Tests and diagnostic runs keep the
switch on, and Desk turns it off when it loads. This note records the
commits, the checks each slice kept and those left for later parts, the
tests, the physical runs in both modes, and what a typed letter's frame
costs now.

All of this is simulator evidence. None of it is UART, panel or touch
evidence. Steps are the simulator's semantic steps.

## What changed

| Commit | Change |
| --- | --- |
| fc62e45f | Desk carves RUHA's record and its eighteen banks from one block. No other storage can then lie between them, so the span-set proof of a document's storage answers in one query, and the frame's cost stops depending on where allocation happened to put the banks. |
| 4442b866 | The switch, `tui/check-mode.f`. It is on unless a composition turns it off, and Desk turns it off after its REQUIREs. `--every-frame-checks` on `akashic_tui.py`, the physical Desktop launcher and the typing run turns it back on, and the final guest diagnostics and the typing run record the mode. RUHA checks another document's stored slices, and its prior menu records, before reusing them only with the switch on. |
| 41a5851e | The shell producer's check of its copy of the published model, and of the bank it has just frozen from proved parts. |
| b5ffd48f | The APT-1 engine's check at each backend call. Its state checks run at every call; its walk of the control and owner ledgers runs when work is queued, or with every-frame checks. |
| ab38976c | The shell producer's dispatch. In normal mode it checks that the sidecar and the producer name themselves, instead of proving every header and span. |
| e79969f9 | Storage the shell takes from Desk's memory source: the proved DELTA emission's authority checks, the clone's span proofs in its proved preparation, the freeze's check that the batch lies outside the bank, and the planner's proof of the model copy. |
| f6a936c6 | The hybrid producer's preflight of the menus it copies from the acknowledged bank, and the DELTA comparison's span checks of the producer's own packs. |
| aceab4f3 | RUHA's proofs, on every draw, that its banks lie apart from the screen's storage, each owner and each document. They are made when the banks are lent, when RUHA installs and when a document attaches; a draw checks the owner's identity. |
| 5baf027d | The glyph planner's proofs that its spans lie apart, the shell snapshot's span proofs at each query, the claim ledger's second check of each menu record's structure, and the producer's walk of a bank's packing and menu directory at each header check. |

Every slice keeps, in both modes, the checks that can find something on
any frame: whether a draw, owner, generation or acknowledgement is still
current; the fit checks; the identity of each record a step reads; the
shapes of the spans its arithmetic uses; the bounds of its own writes; and
the engine's admission of each item the frame sends. Input that comes back
from the terminal is checked as before.

## What normal mode still checks, and why

At 5baf027d checks take 3.48 million steps of a typed letter's 9.62-million
burst frame build. `local_testing/frame_checks.py` sorts them:

| Group | Millions | What is left |
| --- | ---: | --- |
| Items | 1.78 | The engine's admission of the controls and glyphs the frame sends, and the captures' checks of what they read. They visit every item because the build does; part 9 makes them follow change. |
| Repeats | 1.13 | Listed by the tool as repeats, but kept on purpose; see below. |
| Handover | 0.54 | Mostly the public admissions' and the captures' proofs of the spans they are given. |
| State | 0.04 | Kept in every mode. |

The fit checks, the backends' preflights, take 0.05 million beside these.

Kept on purpose:

- **`RTE-FAMILY-BATCH-VALID?`,** 0.46 million. All of it runs inside
  `RTE-FAMILY-BATCH-PREFLIGHT`, the engine's admission of the shell's
  batch, which the frozen bank and the emission rely on. By the plan's
  rules it is an item check at the engine's admission.
- **The glyph planner's claim checks (`_RGRP-CLAIM-VALID?`),** 0.30 million.
  They bound each claim to the surface before the planner uses its rows to
  index the heads and events it writes. Without them a bug in another
  module would become a write outside the planner's storage, not a check
  that goes unnoticed.
- **The text guards in the DELTA comparison (`_RTHP-TEXT-WITHIN?`),** 0.06
  million, which keep each comparison inside the bytes it compares.
- **UIDL-TUI's rechecks of its cached relations and resolved targets,**
  about 0.2 million. UIDL writes these itself; part 5 changes how UIDL
  knows what changed, and these move with it.
- **The public admissions' span proofs** (`_RTE-FA-AUTHORITY?`, 0.14
  million, and `_RTE-HPV-FIXED-AUTHORITY?`, 0.04). A public entry cannot
  know where its caller's storage came from, so, as with the public
  emissions in e79969f9, only the proved peers whose callers are known
  stop proving.
- **The callbacks that write the shell snapshot's banks** keep the full
  `SHSN-VALID?`; only its queries, which read, stop proving the spans.

Left for later:

- The captures' proofs of the output ranges they are given, about 0.18
  million (`_UFLSN-AUTHORITY?`, `_USFSN-AUTHORITY?`, `_UCSN-RANGES?`). They
  are handover proofs and can follow the same rule; each is small.

## Tests

- New files: `test_check_mode.py` (the switch's default and the boot
  option), `test_rich_engine_frame_checks.py` (the engine's frame check)
  and `test_uidl_claim_ledger_checks.py` (a real menu capture through the
  claim ledger in both modes).
- From slice 2 on, each slice but the seventh adds a test that runs the
  check it moves in both modes, in `test_rich_adapter_provenance.py`,
  `test_shell_delta.py`, `test_rich_engine_frame_checks.py`,
  `test_rich_shell_composition.py`, `test_shell_snapshot.py`,
  `test_rich_field_producer.py`, `test_residual_glyph_planner_paired.py`
  and `test_uidl_claim_ledger_checks.py`. With every-frame checks the
  damage the test makes is refused; in normal mode the frame goes on, and
  damage to what normal mode still checks, such as a record's identity, an
  owner's generation, a bank's valid mark or a used count beyond its bank,
  is still refused. Slice 7's reused menus are compared with fresh plans by
  the shadow check in the physical runs below. Structure tests check where
  each check stands relative to the switch.
- Harnesses that build their programs without REQUIREs now load
  `check-mode.f` with the switch on, as it loads.
- Each slice ran the files that load or read what it changed, one file at
  a time, with MegaPad on the path: 37 files for slice 2, 16 for slice 3,
  48 for slice 4, 16 for slice 5, 21 for slice 6, 42 for slice 7, 37 for
  slice 8 and 56 for slice 9, whose batch of 46 took 11 minutes with 545 MiB
  the most any file used. Slice 1 ran its structure tests with the refactor,
  packaging, shell composition, acceptance and storage growth tests.
- The refactor ratchet moved in slices 1 to 4, 6, 7 and 9, by Desk's and the
  switch's state and by one require edge for each module that loads
  `check-mode.f`, each in its slice's commit. It did not move in slices 5
  and 8.

## Bindings

The runs at the end bound clean trees.

| Binding | Value |
| --- | --- |
| Akashic | `5baf027dd6aab79a1df99e340135c0182fa525b5` (tree `efc447ad9cedcb3ffb290f993442efb9ebc972c3`) |
| MegaPad | `2faa96d882dbfd4a6ec300fac960681644f88cc2` (tree `331bfad08e3990cbc4de72c3bcd5d827d3279f6e`) |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |
| Typing harness SHA-256 | `e82ef20a27baeaff5d37dda57fccd33ef0feff031cfd1043f8bb3f4fd814f7cd` |
| Desktop launcher SHA-256 | `cf99b1481db40658f5eb1129fca7e2770735656a1cb09dda4c94eb3a486e40c6` |

## Runs with the shadow check

The native simulator at 280 × 84, one run at a time, after an uncapped wait
for other heavy runs, under the 900-second watchdog and the 3.5 GiB
aggregate-RSS stop. Every run passed its journey, every run with the shadow
check found no difference and skipped no comparison, and every run from
4442b866 on recorded the check mode it was asked for.

After each slice, the typing run with every-frame checks, and Desk with Pad
in normal mode and with every-frame checks:

| Commit | Typing | Desk with Pad, normal | Desk with Pad, every frame |
| --- | ---: | ---: | ---: |
| fc62e45f | 560 | — | 437 |
| 4442b866 | 502 | 437 | 437 |
| 41a5851e | 502 | 437 | 437 |
| b5ffd48f | 386 | 437 | 437 |
| ab38976c | 618 | 437 | 437 |
| e79969f9 | 618 | 437 | 437 |
| f6a936c6 | 560 | 437 | 437 |
| aceab4f3 | 618 | 437 | 437 |
| 5baf027d | 618 | 437 | 437 |

At fc62e45f, before the switch, both runs had every check on. A typing
run's count follows the frames it made. Desk with Pad's 437 comparisons
are 224 of the snapshot, 75 of the producer's runs, 42 of its menus and 96
of the shell's runs in every run.

At the end of the part, on 5baf027d, the canonical Desktop journey:

| Run | Time | Comparisons |
| --- | ---: | ---: |
| With the shadow check | 218.1 s | 4,692 |
| Without it | 197.8 s | — |
| With the shadow check and every-frame checks | 229.9 s | 4,655 |

In normal mode the journey made parts 1 and 2's 4,692 comparisons. With
every-frame checks it committed one START fewer, 38 against 39, with the
same DELTAs and continuations, and made 37 fewer comparisons.

## Steps a frame

The typing run with `--screen-profile`, every call chain kept and
`PYTHONHASHSEED=0`, after each slice, in normal mode. The first character
comes alone; the other 18 arrive at five a second. Millions of steps:

| Commit | Burst frames | All steps a frame | Frame build | Checks | Repeats | Handover | Items | Documents' snapshot | Desk's painting | Isolated character, all steps |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 944630df, part 2's end | 15 | 19.59 | 16.69 | | | | | 4.33 | 1.45 | |
| fc62e45f | 12 | 18.34 | 15.36 | 9.08 | 5.23 | 2.13 | 1.69 | 3.10 | 1.43 | 27.57 |
| 4442b866 | 10 | 17.57 | 14.18 | 7.97 | 4.02 | 2.18 | 1.70 | 1.95 | 1.71 | 26.36 |
| 41a5851e | 13 | 16.12 | 13.30 | 7.05 | 3.17 | 2.15 | 1.68 | 1.95 | 1.31 | 25.15 |
| b5ffd48f | 13 | 15.18 | 12.72 | 6.58 | 2.58 | 2.19 | 1.76 | 1.94 | 1.31 | 23.59 |
| ab38976c | 17 | 13.70 | 11.85 | 5.54 | 2.49 | 1.29 | 1.69 | 1.95 | 0.99 | 21.76 |
| e79969f9 | 18 | 12.98 | 11.20 | 5.16 | 2.24 | 1.09 | 1.78 | 1.96 | 0.94 | 21.75 |
| f6a936c6 | 18 | 12.19 | 10.38 | 4.25 | 1.29 | 1.14 | 1.76 | 1.95 | 0.95 | 21.31 |
| aceab4f3 | 18 | 11.66 | 9.94 | 3.87 | 1.39 | 0.68 | 1.72 | 1.55 | 0.86 | 20.86 |
| 5baf027d | 18 | 11.36 | 9.62 | 3.48 | 1.13 | 0.54 | 1.78 | 1.55 | 0.87 | 20.18 |
| 5baf027d, every-frame checks | 14 | 18.06 | 15.41 | 9.26 | 5.17 | 2.24 | 1.82 | 3.10 | 1.20 | 25.36 |

Part 2's end is from its [evidence](frames-follow-change-part2-20261025.md),
which does not sort the checks. In the one-block slice, the span-set proofs
that memory layout had split fell from 2.15 million steps a burst frame to
0.55, while the frame build fell by 1.33 million and the burst made 12
frames rather than 15. The proofs take 0.18 million at 5baf027d.

A burst frame's cost and the number of frames are linked. The keys arrive
on the host's clock, so while a frame took longer than the 200 ms between
keys, the guest folded several keys into one frame. As frames got cheaper
it answered more keys with frames of their own, and from e79969f9 on it
made a frame for every key. The burst's total steps therefore fell less
than its steps a frame: 294 million over 15 frames at part 2's end, 220
million over 12 at fc62e45f, and 205 million over 18 at 5baf027d. From
fc62e45f on the total stayed about the same while the screen came to follow
every key. The isolated character, always one frame, fell from 27.57
million steps at fc62e45f to 20.18.

With every-frame checks on, a burst frame costs about what it cost before
the switch: a frame build of 15.41 million against 15.36 at fc62e45f. Part
4's safe mode runs every check and also turns the reuse shortcuts off, so
until part 9 this is the least it can cost.

## Files

The runs' output stayed in `/dev/shm` and was deleted after this note was
written; the drive's write count for each run was zero.
