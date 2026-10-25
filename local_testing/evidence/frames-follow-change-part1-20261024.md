# Part 1: the shadow check — 2026-10-24

Part 1 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
adds a shadow check of the rich frame build's shortcuts. While it is on,
each shortcut also runs its full path into scratch storage, and the two
results must match byte for byte. The frame goes on with the shortcut's
result. This note records what the check compares, the tests, and the
physical runs made with it on and off.

All of this is simulator evidence. None of it is UART, panel or touch
evidence.

## What the check compares

| Stage | Shortcut | Full path | Items compared | Commit |
| --- | --- | --- | --- | --- |
| Snapshot | the adapter reuses an unchanged document's slices, and passes over a clean document known to be empty | every visible document captured live | the header (status, document count, the 13 spans' lengths), then each span: 14 a draw | 06c0532d |
| Producer's glyph runs | a held plan kept, or only the damaged rows planned | every row planned | counts, plan header, runs, references, text: 5 a plan | d59b8e3a |
| Producer's menu controls | a document's controls copied from the acknowledged bank | the document planned afresh | planner results against what the copy implies, controls, correlations: 3 a document | d59b8e3a |
| Shell's glyph runs | a region's unchanged rows copied from the acknowledged bank | the whole region planned, as a START plans it | counts, runs, text, references: 4 a region | 8c615beb |

Comparisons are counted in all and by stage (a1c5d5fb). The first
difference is kept with its stage, item, first differing byte and draw.
A comparison whose scratch the heap cannot give counts as skipped. A run
started with `--shadow-check` fails when it ends if the check found a
difference, skipped a comparison, or was not on.

## Tests

- `test_frame_shadow.py`, 4 tests: the switch, equal and differing
  results, the first difference, per-stage counts, scratch blocks, skips.
- `test_frame_shadow_producer.py`, 21 tests on both backends: the glyph
  and menu checks against stand-in planners, each kind of difference found
  at its item and byte, the shortcut's result and the build's own results
  left as they were, and where each check runs.
- `test_rich_adapter_provenance.py`: an unchanged draw makes 14 equal
  comparisons; a corrupted reused text byte is found as the snapshot's
  fifth item, and the reused snapshot is still the one published.
- `test_shell_delta.py`: a DELTA whose changed row is marked makes 8 equal
  comparisons; with the row damage left empty, the check finds one
  difference, in a region's text, where the copied row still holds the
  acknowledged text.
- The 58-file rich, shell and adapter batch passed after each slice,
  except the refactor inventory, which each slice's review commit then
  moved (fd866afb, e763a575, 37e50381, 36685e86).

## Bindings

The runs below bound clean trees.

| Binding | Value |
| --- | --- |
| Akashic | `36685e86744ff5e0b5388ccb0c049dd54d2bec38` (tree `be8f32af24f89d39a8f541c148904a7210626e03`) |
| MegaPad | `dd108ff2bdd8f95e812829f49db94bf5824455c6` (tree `ae5e8dff3be073d4113008800f66548efac7168f`), main |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

## Runs with the check on

The native simulator at 280 × 84, one run at a time, after an uncapped wait
for other heavy runs, under the 900-second watchdog and the 3.5 GiB
aggregate-RSS stop. Every run passed its journey and the check.

| Run | Time | Comparisons | Snapshot | Producer's runs | Producer's menus | Shell's runs | Differences | Skipped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Typing (`physical_typing_cadence.py run`) | 22.7 s | 618 | 154 | 50 | 150 | 264 | 0 | 0 |
| Desk with Pad | 46.1 s | 437 | 224 | 75 | 42 | 96 | 0 | 0 |
| Desk with Daybook | 137.8 s | 427 | 238 | 75 | 42 | 72 | 0 | 0 |
| Desk with Sound Lab | 29.9 s | 170 | 98 | 30 | 18 | 24 | 0 | 0 |
| Desk with Observatory and Worlds | 37.0 s | 201 | 112 | 35 | 42 | 12 | 0 | 0 |
| Desk with File Explorer | 132.9 s | 1,579 | 868 | 345 | 198 | 168 | 0 | 0 |
| Desk with Streams | 107.3 s | 244 | 140 | 45 | 27 | 32 | 0 | 0 |
| Desk with the Agent | 71.1 s | 913 | 532 | 165 | 96 | 120 | 0 | 0 |
| Desk with Photo | 30.7 s | 79 | 42 | 15 | 6 | 16 | 0 | 0 |
| Desk on a small terminal | 31.8 s | 158 | 126 | 10 | 6 | 16 | 0 | 0 |
| Desk with File Explorer and a damaged picture | 28.3 s | 191 | 98 | 35 | 18 | 40 | 0 | 0 |
| The canonical Desktop journey | 220.2 s | 4,692 | 1,246 | 440 | 1,518 | 1,488 | 0 | 0 |
| **All** | | **9,709** | **3,878** | **1,320** | **2,163** | **2,348** | **0** | **0** |

So every stage's shortcut was taken, and checked, on real frames in every
run. The glyph stage counts the held-plan and damaged-row shortcuts
together, so these runs do not show how often each was taken.

A first set of the same twelve runs, at 37e50381 before the per-stage
counts, made 9,675 comparisons, also with no difference and no skip. Its
totals match this set's in every run but the Desktop journey (4,658
there, 4,692 here).

## Runs with the check off

| Run | Result | Time |
| --- | --- | ---: |
| The canonical Desktop journey | passed | 207.8 s |
| Typing, with `--screen-profile` and every call chain kept | all 19 characters shown | 43.7 s |

The typing run's burst of 18 characters made 15 frames, all DELTAs:

| Stage, per burst frame | Part 0, 2026-10-19 | Part 1, check off |
| --- | ---: | ---: |
| All steps | 19.16M | 18.01M |
| Frame build | 16.13M | 15.48M |
| Documents' snapshot | 3.78M | 3.10M |
| Producer's candidate | 3.56M | 3.57M |
| Comparison | 1.60M | 1.60M |
| Shell's batch | 3.74M | 3.74M |
| Shell's freeze | 1.35M | 1.35M |
| Adapter's checks, inside the rows above | 1.62M | 0.74M |
| Storage-aliasing checks, inside the rows above | 3.82M | 2.73M |

This comparison does not show that part 1 changed the cost. With the check
off, part 1 adds one test of the switch for each shortcut taken. The
differences lie in the snapshot and in the adapter's and storage-aliasing
checks, words part 1 did not change. Neither run pinned `PYTHONHASHSEED`, which
changes the simulator's boot and memory layout, and part 0's burst made 14
frames rather than 15. A controlled comparison would pin the seed at both
commits.

## What the runs wrote

The two check-off runs were measured from their process trees' I/O
counters. The typing run wrote 2.57 GB and the Desktop journey 3.32 GB,
while their artifact directories hold 47 MB and 50 MB. The size points to
the simulator's storage device, which rewrites and syncs the whole 32 MiB
disk image on every guest flush (`simulator/storage.py`; the emulator's
`save_image` does the same): 2.57 GB is about 76 such rewrites, and 3.32 GB
about 97. The runs did not count their flushes.
