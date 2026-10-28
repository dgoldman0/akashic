# Overlay layers, step 1: a document stays rich beneath its own overlay — 2026-10-27

Step 1 of [OVERLAY-LAYERS](../../docs/rich-terminal/OVERLAY-LAYERS.md)
keeps a document's roots rich beneath the dialog or prompt it shows, with
the overlay in the layer above them. The code is in 4611f1dd, and the
physical observer's change in 29353c51. All of it is simulator evidence,
none of it UART, panel or touch evidence, and steps are the simulator's
semantic steps.

## What changed

Before the change, the capture clipped away every root of a document that
its own overlay met, so those roots fell back to CELL's cells while the
overlay showed. Now the document keeps every root and its pictures, and the
aggregate producer lets an overlay's claim, from `UFLSN-SOURCE-OVERLAY` or
`UDLSN-SOURCE-OVERLAY`, meet the claims of its own document's roots at a
lower depth; the instrument, status-field and picture lanes accept meeting
their document's overlay above them. Every other meeting of claims is
refused as before. UIDL-TUI's `UTUI-CAPTURE-OCCLUDED!` and the clipping it
switched on are removed.

## Tests

- **The dialog lane** (`test_rich_dialog_producer.py`) lowers a dialog
  widget over a root of its own document at depth 3, beneath the dialog at
  254, and refuses one over another document's root, over its own
  document's root at 254, and over its document's prompt.
- **The field lane** (`test_rich_field_producer.py`) lowers an overlay
  prompt over its own document's root beneath it, and refuses an ordinary
  field there and the prompt over another document's root.
- **The later lanes.** A status field beneath its document's prompt is
  lowered (`test_rich_status_producer.py`); a graph beneath its document's
  prompt keeps the base layer above it, and one beneath another document's
  prompt does not (`test_rich_region_order.py`).
- **The capture.** The field adapter's prompt over a status row now leaves
  the status field it covers rich (`test_rich_terminal_field_adapter.py`).
  The field snapshot's clipped capture went with the word.
- **The journey.** File Explorer's journey now requires its detail table to
  stay rich beneath the delete question, inactive while it is open.

The step's test selection at 4611f1dd, 54 files that load the snapshot
adapter or the aggregate producer, or exercise dialogs, prompts and
overlays, ran one file at a time with `TMPDIR` in `/dev/shm`. Four failed
first, each from the change itself: the refactor ratchet, whose state hash
the removed variables moved; the instrument reuse harness, which builds the
producer's words from a list of sources that lacked the overlay source
constants; the journey structure test, whose simulated delete question left
File Explorer's table out, as the old capture did; and the adapter's
structure test, which reads the capture word's layout. After their fixes
they pass, with the other 50. Not run: `test_applet_host.py`, an emulator
smoke.

## The physical observer

The first physical runs, at 4611f1dd, failed as soon as an overlay opened:
Desk with File Explorer at its rename prompt, over 280 cells, and Desk with
Pad at its close question, over 168, each with "retained semantic root
claims overlap". The acceptance observer, which rebuilds each retained
frame cell by cell, refused any two root claims that met anywhere on the
screen, and the roots beneath an overlay now meet it. The rest of that
queue was stopped.

29353c51 lets a root in a visible modal region lie over the roots of the
regions beneath it, and still refuses roots that meet within one region. A
root that a later region covers goes to the projection's
`covered_root_claims`, retained but no evidence of what shows, and the
checks that every control beneath an overlay is inactive include it; the
viewer marks such a root inactive by the same modal scope. File Explorer's
journey finds its detail table among the shown or covered item views. The
observer's and journeys' four unit-test files, the six other files that
load them and the refactor ratchet, eleven files, passed at 29353c51, run
one at a time.

## Physical runs

Every physical run went through `physical_desktop_acceptance.py`, one at a
time, from RAM clones of the commits named, with output in `/dev/shm` and
the shadow check on.

At 29353c51, Desk with Pad, the Agent, Daybook, Streams and Sound Lab
passed, with no shadow difference, no missed change and no check skipped:

| Application | Seconds | Shadow comparisons | Refresh checks |
| --- | ---: | ---: | ---: |
| Pad | 40.5 | 402 | 13 |
| Agent | 60.8 | 675 | 22 |
| Daybook | 136.0 | 362 | 32 |
| Streams | 91.0 | 214 | 10 |
| Sound Lab | 27.0 | 140 | 5 |

Pad's close question now lies over its text area, which stays in the
layer beneath it, and the Pad and Agent journeys found every control
beneath their overlays inactive, the covered ones included. The canonical
Desktop journey passed in 182.2 seconds, with 4,361 shadow comparisons, as
many as part 8's run at 19b4b765, and no difference, and 79 refresh
checks, none missed or skipped.

### File Explorer

Desk with File Explorer timed out once at 29353c51, at its 300-second
limit, after its delete question had passed with the table held beneath
it. Once the Go to prompt closes with its two-second warning, the journey
selects sunset.qoi's row, sending the select again only when the host
reports backpressure. The host accepted the select after a wait of 615 ms,
but the shell's resolver in the guest found no target for it, so the row
was never selected.

Two more runs passed: one from a RAM copy of 29353c51 whose guest records
where the resolver refuses, in 119.0 seconds, and one at 29353c51 itself,
in 119.2 seconds. Each made 1,511 shadow comparisons with no difference and
47 refresh checks, none missed or skipped. In both, the same select waited
0.6 to 0.7 s at the host each time it was sent, and came back backpressured
twice before the third went through. The guest is busy whenever the journey
sends it there, and the journey sends a backpressured select again but
never one the guest has refused. No overlay is open at that stage. The
refusal fits the older defect part 8 recorded, input bound to a frame the
guest has drawn past, but its cause was not established, since the run with
the markers passed. It stays open.

The delete question's picture from the run that timed out shows the table
rich beneath the question, in the terminal's own layout of its size and
type columns.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clone of the trees and the diagnostic copy. Of the
step's twelve physical runs, the ten whose shells' `write_bytes` were read
wrote nothing to the drive; the counts of the first queue's Pad run and its
stopped Agent run were not kept.
