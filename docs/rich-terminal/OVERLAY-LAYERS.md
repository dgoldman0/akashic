# Rich content beneath overlays

An application that opens a dialog or a prompt over part of its window lost
the rich rendering of whatever the overlay covered, and Desk's own overlay
boxes, the launcher and the Access, Inspect, Approve, Permissions and
Shutdown screens, still turn every tile they touch to CELL. The terminal can
already draw one layer over another; the producer did not give it the
layers. This plan has the producer keep the content beneath an overlay and
place the overlay above it, in two steps: an application's own overlay
first, then Desk's overlay boxes.

## What happened before step 1

The rich path decides document by document what the CELL draw's final
writer covers ([AKASHIC-RICH-TERMINAL](AKASHIC-RICH-TERMINAL.md) §6.2). A
document touched by later foreground paint contributes a directory-only
identity, so CELL's cells show it whole. One case was narrower: when all the
foreground paint over a document was its own overlay, the dialog it shows or
the prompt it opens, the capture kept the document's roots the overlay did
not meet and clipped the others away. A list, text area or meter the
overlay covered then fell back to CELL's cells for that draw, while the
dialog itself went out as a rich DIALOG.

The clipping existed because the producer refuses overlaps between its
lanes. A dialog that meets an earlier family's claim refuses the rich
candidate ([DIALOG-PRODUCER](DIALOG-PRODUCER.md)), and so does a prompt
([FIELD-PRODUCER](FIELD-PRODUCER.md)); instruments must lie apart from every
earlier claim, and status fields and pictures too. Each rule protects
painter order: two claims in one layer that overlap would leave the terminal
to choose which paints last.

File Explorer showed the result when it asked whether to delete a file: the
list beneath the question switched from the terminal's own rendering to
CELL's, which lays out the size and type columns differently, and switched
back when the question closed.

## What the wire already provides

[APT-1-RETAINED-1](APT-1-RETAINED-1.md) §9.1 composes regions back to front
by signed z order, and controls within a region by z, objects before control
roots at equal z. A visible MODAL region is a modal scope: its barrier keeps
every point it covers from the regions beneath, and the controls beneath it
whose roots meet it are inactive, which the renderer may show by dimming
them. The shell candidate already places an application's overlay in a
modal region over its pane's content when the terminal negotiated DIALOGS,
and an overlay pane's document in a modal region over the whole screen. The
layering a seamless overlay needs was there; the capture and the producer
only had to stop removing what lay beneath.

## Step 1: an application's own overlay

Content beneath an application's overlay stays in the candidate, in the
layer it already occupies, and the overlay stays in the layer above it.

The capture no longer clips: a document whose only foreground paint is its
own dialog or prompt keeps every root, those the overlay meets too, its
pictures included. UIDL-TUI's `UTUI-CAPTURE-OCCLUDED!` and the clipping it
switched on are gone. Any other foreground paint over a document keeps the
document-level rule.

In the aggregate producer, an overlay's claim, from the overlay sources
`UFLSN-SOURCE-OVERLAY` and `UDLSN-SOURCE-OVERLAY`, may meet the claims of
its own document's roots that lie beneath it, at a lower depth: the prompt's
field lane and the dialog lane accept those meetings, and the instrument,
status-field and picture lanes accept meeting their own document's overlay
above them. Every other meeting is refused as before: an overlay over
another document's claim, over a root of its own document at its own depth
or above, or over another overlay. The residual plan already excludes the
union of overlapping claims, so no CELL cell shows through either layer.

The painter order holds in both candidates. The shell candidate puts the
overlay in its pane's modal region, above the pane's content region where
the roots lie, and the roots beneath are inactive while the overlay is open,
as CELL's dialog takes its application's input. In the aggregate
candidate's one region the overlay paints after the roots by its depth, 255
for a prompt and a dialog's buttons and 254 for the DIALOG, and instrument
regions lie below that region.

## Step 2: Desk's overlay boxes

A tile beneath an overlay pane would keep its rich content when the only
foreground paint over it is that pane's. The shell candidate already puts
the overlay pane's document above the tiles. The aggregate producer would
have to order the claims of different documents by layer for that: every
claim in its one region competes, so a launcher list over a Pad text area
is refused. RUHA's directory would carry each document's layer, and the
producer would apply its overlap rules within a layer and order layers by
z in its own region. File Explorer's journey checks today that its lists
fall back beneath the launcher; step 2 would reverse that check.

Each step keeps CELL the complete fallback: a family that refuses still
leaves its cells to CELL, and the terminal's barrier and painter order, not
the producer, decide what shows where layers meet.

## Tests

Step 1's unit tests run the production lanes. The dialog producer lowers a
dialog widget over a root of its own document beneath it, and refuses one
over another document's root, over its own document's root at the dialog's
depth, and over its document's prompt. The field producer lowers an overlay
prompt over its own document's root and refuses an ordinary field there, or
the prompt over another document's root. A status field and a graph beneath
their document's overlay keep their places, and a graph beneath another
document's prompt does not. The field adapter keeps a status field under a
prompt rich; the field snapshot no longer has a clipped capture to test,
and the adapter's structure test checks that the capture word clips
nothing. File Explorer's journey requires its detail table to stay rich
beneath its delete question, and inactive while the question is open.

## Status

Step 1 is done; its record is in
`local_testing/evidence/overlay-layers-step1-20261027.md`. Step 2 is
proposed.
