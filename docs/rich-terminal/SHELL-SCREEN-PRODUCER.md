# Optional shell candidate and acknowledged input

`shell-screen-producer.f` adds a complete shell candidate to RTHP. It uses
independently completed SHSN authority and the frozen RUHA directory's signed
slot plus CINST owner/generation. It does not infer ownership from application
names, labels, or the last active UIDL context. The capability remains opt-in.

## Construction and storage

| Word | Stack |
|---|---|
| `RSHSP-INIT` | `( source shell-facade producer sidecar -- rte-status )` |
| `RSHSP-INSTALL` | `( sidecar -- rte-status )` |
| `RSHSP-VALID?` | `( sidecar -- flag )` |
| `RSHSP-SCRATCH-USED@` | `( sidecar -- bytes )` |
| `RSHSP-PART-BYTES@` | `( sidecar -- bytes )` |
| `RSHSP-UNINSTALL-AFTER-STOP` | `( sidecar -- rte-status )` |
| `RSHSP-FINI` | `( sidecar -- )` |
| `RSHSP-CONTROL-TARGET@` | `( owner generation control-id intent sidecar -- row col revision found? )` |

The descriptor is `RSHSP-SIZE` bytes and embeds the RTHP extension descriptor.
`RSHSP-PART-BYTES@` reports the most of the extension block the last build
needed for the shell's part of the frame and `RSHSP-SCRATCH-USED@` the most
of the scratch block it used.

The shell producer owns no storage. It builds the shell's part of each
frame where the part is kept, in the screen producer's storage, does the
build's passing work in a scratch block the producer owns beside its
extension blocks (`_RTHP.XSCRATCH-A`, `_RTHP.XSCRATCH-U`), and plans its
glyph runs in the producer's glyph banks, which are sized for every cell of
the surface and hold no plan of the producer's own while the shell is
installed. The scratch block holds nothing kept and starts empty. When a
build is refused for CAPACITY because the scratch block is too small, the
producer replaces it with a block from its memory source (see
`utils/memory-source.f`) for what the build needed and half again, and the
shell builds once more, until the candidate fits or the memory says no.

RTHP owns two extension blocks beside its target banks (`_RTHP.XBLOCK0-A`,
`_RTHP.XBLOCK1-A`); the shell builds its part in the block the frame on
screen does not name, and the pending bank then names it with the bytes it
uses (`_RTHP-TB.XBLOCK`, `_RTHP-TB.XBLOCK-BYTES`). From then on the part is
the bank's own: the producer publishes, seals, keeps and retires it with the
bank, and drops it from the pending bank whenever it abandons the shell's
preparation, so the bank is the one record of the frame. The blocks lie
outside the producer's arena, whose layout fixes the banks' size, and start
empty. A build refused for room in its block has the producer take a block
from its memory source for what the part needs and half again, and builds
once more. No bank names the free block, so nothing is relocated, and what a
build that cannot finish wrote there is never read.
A new block, scratch or extension, must be separate from the producer's
storage, and the shell's dispatch, with every check on, proves the three
blocks apart from the rest of the storage again. `RTHP-FINI` gives the blocks
back, and `RTHP-MEMORY!` refuses a new memory source while the producer holds
any. Without a memory source a producer has no blocks, and the shell's part
stays CELL.

Construction proves the storage pairwise disjoint from each other,
producer/arena, scratch and extension blocks, provider, SHSN/frozen banks,
ordinary live root/host/children, UIDL, screen and module scratch. With every
check on, a preparation repeats live authority before writing the scratch
block or the free extension block.
Storage that cannot be had refuses the entire optional shell candidate, and
the screen producer's fallback record keeps the bytes asked for and held; the
shell never truncates an object, string, action or sample history. The
model's size is its source's to bound; the shell producer carries no entry or
text limit of its own.

Each immutable part starts with this 96-byte header; the bank that names it
records its bytes, its draw and its wire owner and generation:

| Offset | Value |
|---:|---|
|0|Family-batch offset|
|8/16|SHM copy offset/bytes|
|24/32|Correlation192 offset/bytes|
|40/48|Action-byte offset/bytes|
|56/64|Membership112 offset/bytes|
|72/80|Next region/object identity|
|88|Control identity of Desk's prompt, or 0|

Every span of the part starts on a cell boundary past the header and lies
apart from every other; the part need not be dense. The build takes the
model copy first, then the batch's own spans as it makes them, and writes
the correlations, actions and membership last, at their used sizes. The
family vector grows in the scratch block, since only the build's end knows
how many families there are, and is written into the part before the
preflight. The applications' controls, statics, instruments
and series are not copied: they stay in the screen producer's pending bank,
the one copy of each, and the graph points at them there, each pane's run of
controls with the span of the bank's text they fill, every byte of it one of
theirs, as a family batch requires. The shell writes the region of its pane into each record it
takes, and a preparation that fails gives the bank its own region back. The
part is kept, sealed and retired with the bank that names it, so the records
it points at live as long as it does. Every graph pointer is bounded within
the part, past its header, or within the bank's packed records, before
nested parsing, and the model, correlations, actions and membership are
proved apart from one another and from every span of the batch.
Catalog/object maxima must equal the stored next IDs minus one.

Both blocks use checked aligned bump allocation. Glyph projection plans each
clip in slots in the producer's glyph banks, then copies the runs it planned
into the part before the next clip. In a DELTA's build a glyph family's
items and references leave room for as many runs as the frame on screen's
family in the same place holds, and the identity mapping writes the
tombstones it adds there. `SCRATCH-USED@` and `PART-BYTES@` record each
block's peak reservation. On capacity failure each reports the first
required prefix that did not fit, which is what its block grows to.

The native 32×12 candidate fixture, with one pane, both taskbar bands, one
ordinary MENUBAR and one STATUS_FIELD, uses 9,536 peak scratch bytes and an
8,176-byte part, its application control and status field left in the
pending bank. It exercises actual aggregate admission and family emission,
then overwrites the whole scratch block before validating the part and
publishing its input authority. These are fixture measurements, not Desk
capacity limits; product qualification must measure the complete desktop.

## Geometry and fallback

Ordinary applet CONTROL IDs, hierarchy and FIELD revision bytes stay unchanged.
Each CONTROL run and each STATIC, the bank's own records, references its
actual pane content region;
its logical origin remains0,0 and its logical dimensions remain the full
surface. Each pane content region has the exact explicit SHM content clip.
Instrument regions retain their independent explicit clips and must fit their
associated pane, above chrome and below interactive content. SERIES is taken
intact from the bank, including every waveform sample. New shell controls follow the applet
CONTROL prefix. The screen producer numbers its instruments and statics past
them, having asked the shell how many there are (PLAN, below), and Desk's
status, PANE and newly projected glyph IDs follow those.

A fully visible instrument root may omit its clip flag in the ordinary RUIP
plan. The sidecar copies its logical rectangle into explicit physical clip
fields without changing object coordinates. Catalog and instrument-plan region
rows receive distinct owned copies, and both must still match exactly. Partial
explicit clips remain unchanged; an effective clip outside its associated pane
still refuses the shell candidate.

The two canonical TASKBAR roots share one explicitly clipped taskbar region.
Their distinct root rectangles preserve the divider and label slots. Canonical
blank spacing may acquire rich material. A band is admitted only when its final
writer proof is clear and every authored spacing gap is still blank. If a
source-authored sibling band cannot be admitted, the complete taskbar set stays
ordinary. Global residue holds only cells outside pane content and admitted
shell claims. Its full-surface region sorts below interactive regions so sparse
residual glyphs cannot create an input barrier.

The policy refuses the entire optional shell candidate when pane contents
overlap or a final writer covers any pane outer rectangle, with two
exceptions: an overlay pane over the panes beneath it, described below, and
the overlay a pane's document paints over its own content, the prompt or the
dialog widget it shows. The aggregate adapter captures a prompt as the document's
overlay field, the last record of its field snapshot, and the base candidate
carries it as a `FIELD` control whose correlation names the overlay source; a
dialog it carries as a `DIALOG` with its `BUTTON`s after it, inside its root
(see the [dialog lane](DIALOG-PRODUCER.md)). The shell finds the pane through
the overlay root's document slot, allows one overlay a pane, requires the
root to lie inside the pane's content, and requires the four bands of the
pane's outer rectangle around the root to be clear. The root's own cells are
taken as the overlay's paint, as the adapter took them. A button goes where
its pane's dialog goes, and a button whose pane shows no dialog refuses the
candidate. An application that asks a question while its prompt is open
shows two overlays, so its screen goes out as CELL until one of them closes.
A dialog element is the document's own paint, not an overlay: it and its
contents stay in the pane's content region.

When the terminal negotiated `RTE-F-DIALOGS`, each overlay gets a modal
region after the planner's regions, in control order: surface-sized logical
bounds, the pane's content as its clip, `VISIBLE | CLIPPED | MODAL`, and z two
above the content z, so above every region the shell defines. The prompt's
control, or the dialog and its buttons, go in it, and the terminal shows the
rest of that application inactive while the overlay is open; Desk and other
applications stay active. Without dialogs the prompt stays in its pane's
content region, and the base candidate carries no dialog.

An overlay whose document is in no pane refuses the candidate, as any
control of such a document does.

An overlay pane is a slot its host paints above the others, as foreground,
such as one of Desk's own screens: the launcher, the sandbox's access prompt
and inspector, and the schedule's approval and permissions. It may lie over
the ordinary panes beneath it. Its cells are its own paint, and in a pane
beneath it only the cells no overlay pane covers must be clear: the shell
takes that pane's rows in bands between the overlay panes' edges and checks
each band in the spans between them. Overlay panes do not overlap one
another, and an overlay pane's document shows no overlay of its own; either
refuses the candidate. The planner gives an overlay pane's content region a
z one above the content z, so it may also lie over the chrome of the panes
beneath it, such as the divider between two tiles. A pane beneath leaves
the overlay panes' cells out of its residual glyphs, which the overlay
pane's content region holds. The overlay pane's own residual glyphs leave
out every claim but the panes' chrome: where it lies over a divider its
glyphs cover it.

A pane beneath an overlay pane may keep its document's roots beneath it
([OVERLAY-LAYERS.md](OVERLAY-LAYERS.md)): they stay in that pane's content
region, beneath the overlay pane's content and modal regions, and the
aggregate producer has checked that the overlay pane's claims cover them.
The base projection's one region cannot paint the two documents in order,
so when this candidate cannot be built for such a draw, CELL shows it.

Desk gives an open screen every key and ignores a press outside it. With
dialogs each overlay pane's document therefore goes in a modal region over
the whole screen, after the overlays' modal regions and at the same z, so
above them: surface-sized with the surface as its clip and `VISIBLE |
CLIPPED | MODAL`. Every control of the document goes there, so the screen
is a modal scope over everything beneath it, and the terminal shows the
panes and taskbar beneath inactive while it is open. The document's
residual glyphs stay in its content region. Without dialogs its controls
stay in its content region.

Desk's own Ask prompt is the shell's. While it is open Desk hides its
taskbar, takes no other input, and paints the prompt over the taskbar row,
and its shell model carries the prompt's TEXT field (see the [shell
model](../tui/shell-model.md)). The shell makes that field a `FIELD`
control after its taskbar controls, packed from the model's UFLD record, on
a root across the last row, with a claim on the row so no residual glyph
covers it. It is one of the controls the producer numbers its statics and
instruments past, and the part records its identity. With dialogs its region is a modal scope over
the whole screen, surface-sized with the surface as its clip, since Desk
takes no other input while the prompt is open; without them it is the last
row alone. Either way it sits three above the content z, above the panes'
modal regions. `PLACE` and `EXTEND` on it resolve to its value's first cell
on that row and its field's revision, and Desk's prompt takes them through
its ordinary event path.

The app shell's notice, while the paint shows one, is in the shell model
too: its UDLG model and where its root lies, apart from every pane. With
dialogs the shell makes it a `DIALOG` with the `NOTICE` flag, packed from
that model, after Desk's prompt or the taskbar's controls, in a region of
its own: surface-sized logical bounds, the notice's root as its clip,
`VISIBLE | CLIPPED`, and z four above the content z, above every other
region, Desk's prompt too. It is no modal scope: the notice takes no input,
and what lies beneath it stays active. A claim on its root keeps residual
glyphs off it. Its cells are its own paint, so the taskbar bands and their
blank gaps are proved clear only outside it, and the taskbar it covers
stays semantic beneath it; it too is one of the controls the producer
numbers its statics and instruments past. Without dialogs
the notice is paint over the taskbar, which then stays ordinary while it
shows.

Desk's status, the Agent's state at the taskbar's right end, is in the
shell model too while the taskbar shows it: its USF model and the cell of
its left end, past the taskbar's entries. When the terminal negotiated
status fields, the shell makes it a `STATUS_FIELD` static with the model's
label, value, label slot, severity and emphasis, in a region of its own
across the taskbar row past the entries: surface-sized logical bounds, that
span of the last row as its clip, `VISIBLE | CLIPPED`, at the taskbar's z.
It takes no input. A claim on its root keeps residual glyphs off it. Its
cells the notice leaves must be the shell's own paint; a notice over part
of it hides that part, and the status stays semantic beneath. Otherwise,
or without status fields, it is residual glyphs, as before. Its static
takes the first identity past the base candidate's objects, which the
producer numbered past the shell's controls, and the panes follow it.

Modal/unavailable SHSN authority also refuses the candidate. A refused
batch that more engine storage or more terminal space would not let fit
makes the base producer build its candidate again on its own, with its own
runs and admission, cut down family by family to fit as a candidate going
out alone is, and offer that to the shell once more. If the shell refuses
it too, the candidate goes out alone, with no shell claims leaking into it.

## START, ACK and teardown

RTHP keeps one optional extension pointer (`_RTHP.EXTENSION`); the
`RTHP-EXTENSION-SIZE` descriptor supplies one dispatcher and its context. It
installs only before OWNER_OPEN, while the producer holds no target bank.

The dispatcher events are PREPARE=0, EMIT=1, PUBLISH-CHECK=2, PUBLISH=3,
ABORT=4, RETIRE=5, CURRENT=6, START-ACK=7, DELTA-PROBE=8, DELTA-PREPARE=9,
DELTA-EMIT=10 and PLAN=11.

PLAN comes in every build, once the producer has lowered the applications'
controls. The shell counts the controls it adds after them, the taskbar's
with their tasks and launchers, Desk's prompt and the notice, from the model
for the draw, the notice and the taskbar's bands, as the plan PREPARE builds
does: the planner counts its controls before it numbers anything
(`_RSHPL-CONTROLS-PROVED`), and panes add none, so no pane's eligibility is
asked. The count goes to `_RTHP.SHELL-CONTROLS`, and the producer numbers its
instruments, statics and runs past it, so each carries the identity the
shell's batch sends. PREPARE refuses a batch whose plan adds a different
number of controls. Without an extension the count is 0.

With the shell installed, the base producer builds its candidate for the
shell: it plans no residual runs of its own, leaving its glyph banks to the
shell, and admits nothing. The shell
plans the runs of its regions and admits its whole batch, the candidate's
items among them; the producer's fixed check reads the candidate's own
plans, its identity frontier counts the candidate's objects, and its DELTA
comparison matches the applications' items alone. That comparison refuses
a control the frame on screen lacks, since the shell's DELTA keeps every
applet control under its acknowledged identity. A DELTA the shell cannot
prepare for want of engine working storage is prepared once more after the
storage grew, and one the owner holds too little terminal space for asks
for more and is built again once the terminal answers, as a START is. The
producer builds its candidate alone, with its runs and admission, before
the owner opens, which that admission sizes, after the shell refuses a
batch, and while no rich frame is shown after a draw that could not be,
where its own admission says whether a newer draw can be.

The shell candidate is prepared only after RTHP packs its ordinary target
bank, before retained BEGIN, and its part is built in the free extension
block and named by that pending bank. Only successful PREPARE selects shell
EMIT. Any failure before BEGIN drops the part from the pending bank; the
candidate is then built alone and offered again, as above, and a second
failure selects legacy emission. A candidate that goes out alone emits its
runs from the pending bank's packed copy, which the shell's preparation does
not touch, rather than from the glyph banks the shell planned in.
Any error after shell emission starts cancels the complete capture. A START
defines every object and history with fresh wire identities; an unchanged
current draw is reused. Every SERIES sample and authored history value
survives those replacements. A changed draw whose shell layout matches the
acknowledged one is published as a DELTA instead, described next.

## DELTA publication

A changed draw after an acknowledged one becomes a retained DELTA when its
shell layout matches the acknowledged part, so typing, caret moves and other
changes inside panes send only what changed and keep every unchanged pane,
control and waveform history under its acknowledged identity.

Before the base producer compares its candidate, DELTA-PROBE checks that the
shell model of the new draw equals the copied acknowledged model apart from
its epoch, which every paint advances, and the field of Desk's prompt, which
typing changes; the prompt must be in both models at the same place or in
neither. The app shell's notice, which follows the prompt, must be the same
in both, wherever the prompt's size puts it. A renamed or refocused task, a
new pane, the prompt opening or closing, a notice appearing, changing or
ending, or any other model change leaves the draw to a complete START
without further comparison. Desk's status, which shows only with the
taskbar and so never with the prompt, must end both models or neither; its
value, severity and place may change. Its region spans the taskbar row past
the entries, whatever the status's width, so a change of the Agent's state
keeps the catalog and replaces the status field in a DELTA.

After the base producer has matched its controls, statics, instruments and
series to their acknowledged identities, DELTA-PREPARE builds the shell
candidate. It reads the base candidate's controls, instruments and series
from the producer's pending target bank, which carries those identities,
instead of from the candidate fields a START reads, so a waveform or plot
and the series it names come from the same place: the candidate itself
numbers its series afresh. A DELTA's batch keeps the catalog and families of
the frame on screen, which the terminal admitted, and its emission sends
only the items that differ from that frame's, each checked in full by the
engine as it is sent, so in normal mode the batch is not admitted again.
With every-frame checks on it is, which checks how the shell built it, and
a batch found malformed names the shell's batch. A DELTA too large for the
terminal's space fails as it is sent and goes out as a START, whose
admission asks for the space.
The shell then gives each item the acknowledged identity in the same place:

- the catalog must be identical, region identities included;
- families must match in order, kind and region;
- applet controls must already carry their acknowledged identities;
- Desk's prompt takes its acknowledged identity and may change, so typing in
  it sends one CONTROL-REPLACE;
- the notice takes its acknowledged identity and is unchanged;
- the taskbar takes the acknowledged identities and must otherwise be
  unchanged, because a DELTA cannot replace taskbar controls;
- instruments and series take the identities in place; the base producer's
  comparison has found them unchanged, since a DELTA cannot replace them.
  Status fields and panes take them and may change;
- residual glyph runs take the acknowledged runs' identities slot by slot in
  each region. Unused acknowledged slots become invisible empty runs, and
  extra runs get identities above the producer's object frontier.

Taskbar correlations and pane memberships are renumbered with them. Any other
difference refuses the DELTA, and the producer rebuilds the draw with fresh
identities for a complete START. DELTA-EMIT sends the difference between the
pending and acknowledged parts through `_RTE-FAMILY-BATCH-DELTA-EMIT-PROVED`
inside the open retained DELTA, and the base producer's comparison is the one
comparison of the applications' controls, instruments and series. That
comparison seals a plan of the controls it found changed, each a place in
the pending bank, and `_RTHP-DELTA-PLAN-CONTROLS@ ( producer -- a n flag )`
gives it while it is the plan sealed for the banks now pending and on
screen. The applications' families of controls take the bank's records in
order, so the plan's places, which ascend, fall to them in turn: the shell
hands the emitter each family's places as indexes in the family, written in
the scratch block, which nothing reads once the part is built, and the
emitter replaces those controls without comparing them. The instruments and
series are known unchanged. The shell's own items and the applications'
statics are compared as before, and the base producer, which counts the
statics' changes for its own DELTA, looks for them in a comparison built for
the shell only to judge them for the root facts. A plan control to define,
or one no family holds, refuses the DELTA, and without a plan sealed for
these banks every item is compared. With the shadow check on, the emitter
compares the known families too, and the journey counts each item as a
comparison of the shell-delta stage. After the physical acknowledgement the producer publishes
the pending bank, its part with it, exactly as after a reveal. A DELTA
consumes no region identities, and the published part's frontier covers its
new object identities.

A DELTA plans residual runs only on rows that changed. Once a candidate is
built, the producer's ROW-DAMAGE names the rows a plan must build again:
those of CELL and residue damage, and those of claims that came, went or
moved. The acknowledged bank keeps its projection's rectangles, the menus'
first, and how many are the menus', so a menu's claim is compared with the
acknowledged menus' and any other claim with the acknowledged others'; a
menu that opens, closes or moves marks its rows, and one that stays where it
was marks none. Every other row's cells, residue and claims, menus'
included, are unchanged since the acknowledged frame, and safe mode, or a
frame on screen that cannot vouch for them, marks every row. A DELTA
also keeps the shell's own claims and regions, so the
shell's runs on an unmarked row equal the acknowledged part's. For each
region whose catalog row equals the acknowledged one, the shell copies those
rows' runs and text from the acknowledged part and plans each band of marked
rows through the residual planner with a clip of just that band. Runs never
span rows, so the region gets exactly the runs a whole-region plan would
give; a test checks that the two parts are identical byte for byte. While
typing, that is the edited line and the status line instead of every cell of
every pane. Every planner call of one build runs under a single
borrow of the projection planes: every request, claim, work and output span
lies in the producer's scratch block or in its arena, which holds the glyph
banks, so one proof each that the two are disjoint from screen storage covers
them all, as the base producer does for its rows.

The producer's unchanged-frame shortcut republishes its own target alone, so
with the shell installed every changed draw takes the full build. Private
counters record DELTA-PROBE refusals, DELTA-PREPARE refusals and successes,
and where the last refusal happened. They also count each refusal by its
reason: a probe by the part of the two shell models that differed, a
preparation by its stage times 16 plus the build's stage or the family's
kind. The base producer counts its own DELTA refusals the same way, by the
check of its gate that refused. Desk acceptance runs record all of them in
`final-guest-diagnostics.json`, with the terminal's count of committed
PRESENT modes.

A part is checked in full once, when it is finished. STAGE builds in the
extension block the frame on screen does not name, after the pending bank
dropped its part, so a part a bank names is never written again. The checks
below therefore compare its identities and do not check its contents again.
With every check on, the structure is checked again before a DELTA builds on
the part or a click is routed through it, and the seal of the frame's bank,
taken when the frame is sent, covers the part: the producer checks it before
the comparison every DELTA starts with, and the shell before it routes a
click on its chrome.

After a successful hidden START acknowledgement, START-ACK checks the pending
part's frontiers against its regions and objects again. It advances each
region/object frontier to the maximum of the base frontier and the copied
shell frontier. These IDs have been consumed even when a newer ordinary draw
replaces the hidden candidate before reveal. This event does not publish a
part or change input authority. Unacknowledged or rejected STARTs do not
advance shell frontiers.

Neither ACK requires the old draw to remain current while its physical ACK is
awaited. After visible core ACK publication, PUBLISH raises the frontiers from
the published part, preserving the already consumed ones. PUBLISH-CHECK,
ABORT and RETIRE leave the shell nothing to do: the part is the bank's, so
there is nothing to pair, and the producer drops or retires it with the bank.
Neither rewinds consumed IDs. Repeating START-ACK or publishing after a larger
base reservation cannot move a frontier backwards.

The real Desk regression exposed this timing when ordinary typing completed a
new draw before reveal: the next catalog began at region 54, but the provider
had already acknowledged hidden regions through 61. It correctly rejected the
first region before emitting any text. Advancing only the base candidate's
frontiers at hidden ACK caused that reuse; START-ACK reserves the complete
shell range at the same acknowledgement boundary.

CURRENT and input additionally require the frame on screen's draw to be the
screen's last and its owner the producer's, and the current SHSN model to
equal the part's copied model. Unacknowledged parts never route input.

A shell ACTIVATE must match a unique retained CONTROL and correlation, the
canonical parent band and translated slot, source lifecycle tuple, copied label
and action bytes, epoch and draw. It returns the ordinary root mouse coordinate;
existing host/Desk handling performs task focus/restore or catalog activation.
It does not invoke applications directly. Applet intents retain their original
acknowledged IDs and FIELD revisions through `RTHP-CONTROL-TARGET@`.

`UNINSTALL-AFTER-STOP` requires the composition to revoke draw/input callbacks
and drain/stop transport first. It verifies the facade is idle, clears only its
own extension, and emits nothing; the frame's banks keep their parts in the
producer's extension blocks until the producer is finished. Desk calls it after
`APTAS-UNINSTALL`, then detaches SHSN and finalizes the shell facade. A refused
teardown retains state for a later retry.
