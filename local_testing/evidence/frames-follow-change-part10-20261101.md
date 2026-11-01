# Part 10: today's structure retires — 2026-11-01

Part 10 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
removes the structures part 9 replaced, so that nothing is kept for
compatibility and the full driver remains the one full path. This note
records what was left of them when part 9 ended, the three steps that
removed it, a measurement that set the first step's cost, and the tests
and runs. All of it is simulator evidence. None of it is UART, panel or
touch evidence. Steps are the simulator's semantic steps.

## What was left

Part 9 removed most of what it replaced within its own slices: RUHA's
fixed banks (9a.4), the shell's banks, work space, second admission and
second comparison (9b), and 9a.2's capture into scratch. Of the shortcuts
part 1 put under the shadow check, the snapshot adapter's reuse of an
unchanged document's slices now follows counted change (9a.3c), and the
producer's and the shell's reuse of the runs of rows no draw touched is the
change driver's own residual glyph planning. The full lowering, though,
still copied a document's menu controls and correlations from the bank on
screen, and patched their states, when the document's menu records
matched that bank's; safe mode turned this off, so normal and safe mode
built a full frame two ways. The reuse also mapped the bank's menu
identities by place, which a bank whose DELTA defined or dropped controls
does not keep (9c.2), the latent fault the end of part 9 left open.

The snapshot adapter's two menu epochs per document existed for that
reuse. The adapter derived them at each capture by comparing every menu
record with the prior snapshot's, exactly and by control topology, and
carried them through reuse; the producer otherwise checked only their
shape, and the full refresh compared them after comparing the menus'
slices themselves. A search for definitions nothing references, in the
modules part 9 changed, found two more of part 9's leftovers: a variable
in the region catalog and one in the shell producer.

## What the menu reuse saved

A profiled typing run with the shadow check, at 25f5c5dd, measured both
costs in one run, since the shadow check's menu stage planned each reused
document's menus afresh beside the reuse: 80 reuses took 0.72 million
steps, about 9,000 each, and planning the same menus afresh 9.83 million,
about 123,000 each. A full lowering on the canonical Desktop reuses the
menus of four or five documents, so removing the reuse costs about 0.5
million steps on each frame the full driver builds there, a START or a
frame the change driver turns away. A typed letter, which the change
driver takes, does not reach it. Decision 24 removes it.

## The steps

- **10a** (6e5047a2) removes the reuse's 17 words and 35 variables, and
  its shadow-check stage; the stages after it are numbered one lower, and
  the physical acceptance tool's stage names and counters follow. Every
  full lowering plans each document's menus, as safe mode did. The profile
  classifier counts the engine's control check, whose remaining callers
  check the controls the field and dialog lanes built, among the item
  checks.
- **10b** (48321db6) removes the menu epochs: the cells, their accessors,
  the capture's lineage, the reuse's and the append's handling of them,
  the producer's three checks of their shape and the refresh's comparison.
  A document entry shrinks from 312 bytes to 296, the cells after the
  epochs move 16 bytes down, and the adapter's ABI becomes 13. The
  producer's directory strips, which wrote the status fields', fields' and
  dialogs' cells at literal offsets, name them by the adapter's words.
- **10c** (3d916720) removes `_RTE-RC-USED` and `_RSHSP-STATUS`.

## Tests

Each step ran the test files that load what it changed, one file per
process with `TMPDIR` in `/dev/shm`, the refactor ratchet among them with
its baseline taking each step's new state:

- 10a: 102 files passed, 101 at first and `test_frame_shadow_producer.py`
  once its harness no longer set the menu planner's results around each
  check.
- 10b: 107 files passed, 92 at first and 15 once their tests named the
  shorter entry: the adapter's constructor program pinned the old size,
  and the status, field and dialog producer harnesses and the field-series
  test wrote a document's cells at literal offsets; they now name them by
  the adapter's words.
- 10c: 26 files and the ratchet passed.

Not run: emulator smokes.

## Physical runs

Every run went through `physical_typing_cadence.py` or
`physical_desktop_acceptance.py`, one at a time, from a RAM clone of
3d916720 with MegaPad at 1833d16f, and output in `/dev/shm`. Each run with
the shadow check passed with no difference and nothing skipped.

| Run | Seconds | Comparisons | Judged | Roots | Changed | Items | Presents D/S/C/N | Bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Typing | 20.5 | 5,420 | 13 | 416 | 28 | 28 | 18 DELTAs | 13,158 |
| Pad | 51.0 | 1,920 | 14 | 129 | 33 | 34 | 12/3/3/1 | 617,805 |
| File Explorer | 149.9 | 3,956 | 47 | 285 | 97 | 66 | 28/39/36/1 | 3,870,556 |
| Daybook | 138.7 | 1,462 | 13 | 68 | 25 | 23 | 11/4/4/1 | 626,147 |
| Streams | 130.3 | 479 | 5 | 29 | 9 | 8 | 3/6/6/1 | 575,085 |
| Agent | 73.9 | 2,112 | 22 | 193 | 43 | 32 | 18/11/11/1 | 1,576,200 |
| Sound Lab | 33.3 | 379 | 4 | 39 | 16 | 6 | 3/3/3/1 | 663,613 |
| Observatory | 40.6 | 321 | 4 | 48 | 7 | 2 | 0/8/7/1 | 880,607 |
| Small Terminal | 33.6 | 249 | 3 | 29 | 8 | 1 | 1/4/4/3 | 692,239 |
| Photo | 34.5 | 127 | 2 | 11 | 6 | 3 | 1/3/3/1 | 8,758,813 |
| Damaged | 31.0 | 524 | 6 | 32 | 10 | 9 | 5/2/2/1 | 890,294 |
| Canonical journey | 228.8 | 29,058 | 65 | 2,554 | 132 | 122 | 61/25/25/1 | 4,786,258 |

The columns are part 9's, and the typing row's presents and bytes are its
profiled burst's. The canonical journey made 29,058 comparisons, part 9's
30,483 less the 1,425 of the menu stage that went, and sent the same
presents, with 702 more bytes, which were not traced. Without the shadow
check it passed in 228.3 seconds with the same presents and bytes. In safe
mode it passed in 355.9 seconds with 60 DELTAs, 27 STARTs, 25 CONTINUEs
and one NONE, 5,018,928 bytes. Each run's shell reported a `write_bytes`
of 0.

The profiled typing run built a burst frame in 2.05 million steps, as at
the end of part 9, with the same 18 DELTAs and 13,158 bytes. Its isolated
letter, which goes through the full lowering, built its frame in 6.49
million steps, and a profiled run at 25f5c5dd, the last commit before part
10, in 5.90: the producer's candidate took 1.77 million against 1.18, the
menus planned afresh, and the other stages took the same, the shell's
glyphs within its batch 0.20 million against 0.33. Both frames spent
1.84 million in the shell's batch, which a run at d1db8bc9, of the same
code as 25f5c5dd, had not: in that run the isolated letter's frame built
in 4.00 million. So that one frame's figure varies by about 1.9 million
between runs of the same code, with whether the shell builds its whole
batch for it; why was not traced.

## Open

The search for unreferenced definitions found 15 private words that were
already unreferenced when part 9 began, in the APT-1 engine, the screen
producer, the shell planner, the shell producer and the snapshot adapter,
some of them still called by their unit tests; they are not part 9's, and
are left for a cleanup of their own. The 118 public words nothing in
production calls are the records' field accessors and sizes, which
describe interfaces and stay.

## Files

The runs came from a RAM clone of 3d916720, and their output stayed in
`/dev/shm` and was deleted once its numbers were read.
