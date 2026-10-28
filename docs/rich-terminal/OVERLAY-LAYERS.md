# Rich content beneath overlays

An application that opens a dialog or a prompt over part of its window lost
the rich rendering of whatever the overlay covered, and Desk's own overlay
boxes, the launcher and the Access, Inspect, Approve, Permissions and
Shutdown screens, turned every tile they touched to CELL. The terminal could
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

Roots stay beneath an overlay only where the overlay is shown above them.
A renderer shows a prompt's field only when the terminal negotiated fields,
and a dialog only with dialogs, so the producer tells the capture from the
terminal's features which of the two it can show (`RUHA-LAYERS!`). Where it
cannot, the overlay's paint falls its document back whole, as any other
foreground paint does, since no claim would cover the overlay's cells. A
document that keeps its roots beneath its overlay names the overlay's cells
in its directory entry (`RUHA-DOCUMENT-OVERLAY@`). Before it plans residual
glyphs, the producer checks each such document: when one of its roots meets
those cells, the candidate must hold the overlay's own claim over all of
them. A family refused after the roots beneath it were admitted, for space
or because the terminal refused it, fails the check, and the draw goes out
as CELL, since those roots would otherwise claim cells where CELL shows the
overlay.

## Step 2: Desk's overlay boxes

A tile beneath an overlay pane keeps its rich content when the only
foreground paint over it is the overlay pane's and its own overlay's. The
host paints an overlay slot's document over the whole of its rectangle,
and each of Desk's screens is a dialog element filling it, so the overlay
pane's DIALOG claims all of those cells.

Documents lie in layers. An overlay slot's document is the layer above the
others, and its directory entry says so (`RUHA-DOCUMENT-LAYER@`). The
capture's test of what lies above a document walks the visible overlay
slots' rectangles beside the document's own overlay, so a tile keeps every
root when all the foreground paint over it lies inside them. The producer
allows this only when the terminal negotiated dialogs and an extension,
Desk's shell, gives the overlay pane a region of its own
(`RUHA-LAYER-PANES`). In the aggregate producer the claims of documents in
different layers may meet; claims of one layer still may not. The field,
dialog, instrument, status-field and picture lanes accept such meetings,
and so does the check of omitted graphs, which now names each graph's
document and passes over a claim of a layer above it.

The shell candidate already paints the layers in order. A tile's controls
stay in its pane's content region, the overlay pane's content region lies
above it, and with dialogs the overlay pane's document goes in a modal
region over the whole screen, where the tiles' controls beneath are
inactive. The tile's residual glyphs leave out the overlay pane's cells,
which the overlay pane's region holds. The aggregate candidate's one
region cannot order two documents, so when the shell cannot build a draw
whose candidate holds a tile's claim under an overlay pane, CELL shows that
draw.

The check before residual planning covers this layer too: wherever a claim
of a document meets an overlay pane's rectangle above it, one claim of the
overlay pane's document must hold that part, or the draw goes out as CELL.

Each step keeps CELL the complete fallback. Where an overlay cannot be
shown above what it covers, the content beneath falls back with it, and
the terminal's barrier and painter order, not the producer, decide what
shows where layers meet.

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
nothing.

The field adapter keeps the document's roots beneath its prompt only while
the capture may layer fields, names the prompt's cells in the directory
then, and falls the document back whole otherwise. The dialog producer's
tests find the roots beneath a dialog covered while the dialog is in the
candidate and uncovered once its lane refuses it for space; a refused
dialog with no root beneath it, or no overlay named in the directory, leaves
the draw rich. UIDL-TUI's dialog tests check which kind of overlay
`UTUI-OVERLAY-KIND@` reports.

Step 2's tests run the same lanes across documents. A dialog of an overlay
pane's document lies over a root of the document beneath it, which the
check finds covered, and the candidate is marked as needing the shell's
regions; two documents of one layer still may not meet, and the roots
beneath a refused overlay pane's dialog fail the check. A field of an
overlay pane's document lies over another document's root, a status field
stays rich beneath an overlay pane's root but not beneath a root of its own
layer, and a graph keeps the base region above it beneath an overlay
pane's root. Omitted graphs name their documents. The shell candidate keeps
a pane's control beneath an overlay pane in the pane's content region,
below the modal region that holds the overlay's control. File Explorer's
journey requires its table and tree to stay rich beneath Desk's launcher,
and inactive while it is open.

The physical acceptance observer reads the layers the same way. A root in a
visible modal region may lie over the roots of the regions beneath it, and
two roots that meet within one region are still refused. A root that a
later region covers is kept apart from the evidence of what shows, since
the observer cannot tell which of its pixels show, but the checks that
every control beneath an overlay is inactive include it. Its shell-scene
tests hold a tabset beneath a pane's dialog and refuse two prompts that
meet in one modal region. File Explorer's journey requires its detail table
to stay rich beneath its delete question, and inactive while the question
is open.

## Status

Both steps are done. Step 1's record is in
`local_testing/evidence/overlay-layers-step1-20261027.md`, and step 2's,
with the check that keeps roots beneath an overlay only while the overlay
is shown, in `local_testing/evidence/overlay-layers-step2-20261028.md`.
