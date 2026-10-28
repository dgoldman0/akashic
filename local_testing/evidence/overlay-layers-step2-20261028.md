# Overlay layers, step 2: tiles stay rich beneath Desk's overlay panes — 2026-10-28

Step 2 of [OVERLAY-LAYERS](../../docs/rich-terminal/OVERLAY-LAYERS.md)
keeps a tile's roots rich beneath Desk's launcher and screens, with the
overlay pane's document in the layer above them. Before it, a check closes
a gap step 1 left: roots stay beneath an overlay only while the overlay is
shown. The code is in 306dd5d6 (the check) and b357c9b6 (step 2), and the
journey's fix in 061f20f2. All of it is simulator evidence, none of it
UART, panel or touch evidence.

## The gap step 1 left

Step 1 kept a document's roots beneath its own dialog or prompt whatever
happened to the overlay. A terminal without fields never receives the
prompt's field and one without dialogs never receives the dialog, since the
producer strips those families when it copies the snapshot, and the field
and dialog lanes strip themselves when the terminal refuses them or space
runs out. In each case the roots beneath still claimed the overlay's cells,
so the residual plan left those cells empty and the frame would have shown
the roots where CELL shows the overlay. The physical runs had not met it:
the reference terminal negotiates both features and no lane was refused.

306dd5d6 has the producer tell the snapshot adapter, from the terminal's
features, which overlays it can show above a document (`RUHA-LAYERS!`).
Where it cannot show one, the overlay's paint falls the document back
whole, as other foreground paint does. A document that keeps its roots
beneath its overlay names the overlay's cells in its directory entry, and
before planning residual glyphs the producer checks that the overlay's own
claim, in the candidate, holds those cells wherever a root of the document
meets them; otherwise the draw goes out as CELL.

## Step 2

b357c9b6 puts documents in layers: an overlay slot's document lies above
the others, and its directory entry says so. The adapter's walk of what
lies above a document takes in the visible overlay slots' rectangles, under
a policy the producer sets only with dialogs and Desk's shell installed.
The aggregate producer's lanes let the claims of documents in different
layers meet, omitted graphs record their document, and the coverage check
also requires an overlay pane's claim over every part of a lower claim it
lies over. The base candidate's one region cannot order two documents, so
a draw that needs the shell's regions goes out as CELL when the shell
cannot build it.

## Tests

Each slice ran a selection of 71 files that load the snapshot adapter, the
producers or Desk's composition, one file at a time with `TMPDIR` in
`/dev/shm`. For 306dd5d6, 69 passed at first; the refactor ratchet's new
hash was recorded, and a profiling structure test found the policy set
after the snapshot phase's mark, which was moved before it. For b357c9b6,
70 passed; the lower UIDL lifecycle's architecture test found the applet
host's document naming the renderer's documents, which it no longer does.
Each pass after its fix. Not run: `test_applet_host.py`, an emulator smoke.

The unit tests that bear on the steps are listed in OVERLAY-LAYERS'
Tests section and in the two commits.

## Physical runs

Every run went through `physical_desktop_acceptance.py`, one at a time,
from RAM clones of the commits named, with output in `/dev/shm` and the
shadow check on.

At b357c9b6, Desk with Pad, the Agent, Daybook, Streams and Sound Lab
passed, and so did the canonical Desktop journey, in 201.2 seconds with
4,373 shadow comparisons, against 4,361 in step 1's run, and 79 refresh
checks. Desk with File
Explorer failed at the launcher with "File Explorer's lists fell back
beneath the launcher".

A run from a RAM copy whose snapshot adapter recorded every failed layer
test found none: File Explorer kept every root beneath the launcher in
every frame. The journey's check was wrong. A list of more than one column
is captured as a table, and Desk's launcher catalog has two, so the check
counted two tables and refused. 061f20f2 leaves the launcher's own list out
of the count, and makes the journey test's launcher fixture a table as
Desk's is.

At 061f20f2, Desk with File Explorer passed. No run had a shadow
difference, a missed change or a skipped check:

| Application | Commit | Seconds | Shadow comparisons | Refresh checks |
| --- | --- | ---: | ---: | ---: |
| File Explorer | 061f20f2 | 125.0 | 1,467 | 47 |
| Pad | b357c9b6 | 40.7 | 402 | 13 |
| Agent | b357c9b6 | 62.1 | 697 | 22 |
| Daybook | b357c9b6 | 137.3 | 362 | 32 |
| Streams | b357c9b6 | 96.2 | 214 | 10 |
| Sound Lab | b357c9b6 | 27.1 | 140 | 5 |

The launcher's picture from that run shows Desk's Applets dialog, with its
two-column catalog, over File Explorer's table. The table keeps the
terminal's own layout of its size and type columns beneath the dialog, the
rows the dialog covers show only their names to its left, and the folder
tree stays on the left.

All three of File Explorer's runs selected sunset.qoi's row after the Go
to warning, where step 1's record left a stall open. The stall did not
recur, and its cause stays unestablished.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clones of the commits and the diagnostic copy. Each
run's shell reported a `write_bytes` of 0, so no run wrote to the drive.
