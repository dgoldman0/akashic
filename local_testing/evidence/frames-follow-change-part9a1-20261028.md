# Part 9a.1: change detection, checked against the comparison — 2026-10-28

Part 9 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
makes a frame's work follow what changed. Its first slice records, for each
root a document's snapshot holds, what that root's capture read, and checks
the record against the frames the full path builds before anything relies on
it. This note gives part 9's baseline, a fix to overlay step 2 the baseline
found, and the slice's tests and runs. All of it is simulator evidence.

## Baseline

The typing run at 7718ee8f, overlay step 2's end, profiled with every call
chain kept and `PYTHONHASHSEED=0`, built a burst frame in 9.98 million
steps: the snapshot 1.59 million, the producer's candidate 2.89 million, its
target pack 0.29 million, its comparison 1.37 million, and Desk's shell 3.58
million, of which its admission took 1.90 and its glyph planning 0.99. Part
7's end had built the same frame in 9.68 million.

Most of the 0.30 million came from overlay step 2. The field, dialog,
status and picture lanes, and the check of graphs against earlier claims,
test a pair of items' layers to let two documents' claims meet; each loop
joined that test to the test of whether the rectangles meet with AND, which
in Forth evaluates both sides, so every pair paid for it. The document-layer
test scans the document directory twice a call: 0.25 million steps a burst
frame, and 0.03 million for the own-overlay test, nearly all of it in the
status lane. 4f4c935a tests the layers only for a pair that meets. Eleven
lane, shadow and ratchet test files passed. The typing run at 4f4c935a built
a burst frame in 9.63 million steps and sent the same 18 DELTAs, 13,158
bytes, as at 7718ee8f. That run is part 9's baseline.

## Design

c32ae3e3 lays out part 9 from a reading of the snapshot adapter, the screen
producer and Desk's shell, and its slices; decision 15, the order of the
slices, is open.

## The slice

cce2ade3 records, for each root of a snapshot, what its capture read
(`tui/uidl-root-facts.f`, `RUHA-ROOT-FACTS@`): the newest UIDL revision
among the elements it reads, the revisions of the widget and model it
shows, the screen size an overlay prompt or dialog lays out against, and
the geometry it was captured at. With the shadow check on, the screen
producer keeps those facts beside each bank it builds, and its DELTA
comparison judges them: every control and status field it finds new or
changed must belong to a root whose facts moved since the bank on screen,
and instruments it refuses to keep must belong to a data-graphics root
that moved or went. A miss is a difference of the shadow check, which fails
the run. In normal mode none of it runs.

What the facts close of the gaps part 9 lists: the geometry of mounted
roots is recorded as captured; a widget a document no longer mounts, or
mounts anew, shows as a root that went or came; the overlay prompt and the
shown dialog are named by instance, and the screen size and the count of
dialog-element changes are recorded beside them; a field's bound model
records the revision its application issues. Three remain for later
slices. A data-graphics model edited in place moves no counter;
applications change graphs by binding a new model, which moves the
widget's. Desk's shell model belongs to 9b. Pictures are described afresh
for each draw and carry no facts yet, so the statics that show them are not
judged.

### Tests

The selection that loads the snapshot adapter, the producers or Desk's
composition, 71 files, with the new `test_rich_root_facts.py` and
`test_frame_shadow.py`, ran one file at a time with `TMPDIR` in
`/dev/shm`. 68 passed at first. The refactor ratchet failed on the new
module, its requires and the new graph and state hashes, recorded in the
commit. Three files that load the snapshot adapter from one fixture's
explicit module list lacked the new module, which the fixture now loads.
The producer's structural tests read the DELTA comparison's body by name,
which a first form of the judge had moved behind a wrapper; the comparison
keeps its name and begins the judge itself, and judges instruments where it
refuses them. After those fixes, and a check that an item whose family one
bank carried and the other did not is not a miss, the five passed, and 33
files that build the producer's candidate or comparison passed again. Not
run: `test_applet_host.py`, an emulator smoke.

### Physical runs

Every run went through `physical_typing_cadence.py` or
`physical_desktop_acceptance.py`, one at a time, from a RAM clone of
cce2ade3, with output in `/dev/shm`.

Without the shadow check, the profiled typing run built a burst frame in
9.69 million steps against the baseline's 9.63, within the runs' variation;
its host gave the 18 keys 11 frames.

With the shadow check on, every run passed with no difference, no skipped
comparison, and no missed change at any full refresh. The judge's counts:

| Run | Seconds | Shadow comparisons | Comparisons judged | Roots | Changed | Items judged |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Typing | 21.9 | 580 | 9 | 288 | 20 | 20 |
| Pad | 52.0 | 426 | 14 | 129 | 33 | 24 |
| File Explorer | 145.5 | 1,497 | 43 | 261 | 93 | 30 |
| Daybook | 138.4 | 369 | 13 | 68 | 25 | 7 |
| Streams | 116.9 | 216 | 5 | 29 | 9 | 2 |
| Agent | 76.1 | 684 | 18 | 159 | 35 | 9 |
| Sound Lab | 33.5 | 143 | 4 | 39 | 16 | 3 |
| Observatory | 38.6 | 203 | 4 | 48 | 7 | 2 |
| Small Terminal | 33.0 | 115 | 2 | 20 | 2 | 1 |
| Photo | 32.2 | 82 | 2 | 11 | 6 | 3 |
| Damaged | 29.9 | 197 | 6 | 32 | 10 | 6 |
| Canonical Desktop journey | 237.2 | 4,528 | 65 | 2,554 | 132 | 90 |

Roots counts the roots of the pending banks over the comparisons judged,
and Changed those that were new, moved or went. In the typing run a typed
frame changed about two of its 32 roots, as a typed letter changes the text
area and the status line; in the canonical journey 132 of 2,554 changed.
The change driver will capture only those. The judge checks that no changed
item escaped the facts; a root whose facts moved with no item changed only
costs a capture. The canonical journey committed 49 DELTAs, 37 STARTs, 36
CONTINUEs and one NONE, and its 4,528 comparisons are 4,438 of the earlier
stages and 90 of the root facts.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clones. Each run's shell reported a `write_bytes` of 0.
