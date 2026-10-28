# A frame's work follows what changed — design, 2026-10-19

Status: proposed on 2026-10-19. On 2026-10-25 it was extended with a thin
rich path: checks that run when they can find something (part 3), a safe
mode (part 4), an occasional full refresh (part 8), and one projection with
two drivers (parts 9 and 10). On 2026-10-27 it gained part 6b, which drops
a frame Desk sends but never shows when a document is handed to Pad, and
part 7 took on three faults part 6 found. Each part is approved on its
own. Parts 0 to 8 and 6b are done, and part 9 is under way. Decisions lists
what is settled and what is still open.

Earlier work: [KEYSTROKE-FRAME-WORK.md](KEYSTROKE-FRAME-WORK.md)
(2026-10-14, all seven parts done),
[PER-KEY-FRAME-REPEATS.md](PER-KEY-FRAME-REPEATS.md) (2026-09-28) and
part 10 of the [rich experience plan](RICH-EXPERIENCE-PLAN.md)
(2026-10-11). KEYSTROKE-FRAME-WORK ends: "Going further than that needs the
snapshot itself to follow change." This design is that step. Parts 3, 4 and
8 to 10 rest on [the check measurement](../../local_testing/evidence/rich-path-checks-20261025.md)
of 2026-10-25.

## Summary

A character typed into Pad on the rich Desktop costs the guest about 19
million steps a frame, and about 16 million of them build the frame
(`_RTHP-PREPARE-LIVE`), measured in part 0. The earlier designs removed work
that repeated within a frame. What is left follows the number of items on
the screen, not what changed: at a quarter of the area, a key still cost
three quarters as much in October, and in part 0 the same kind of edit in
Pad cost half as much on a Desk showing only Pad as on one showing five
applications.

A typed letter changes one text area, the caret and the status line. Each
frame still:

- recaptures all six semantic families of the edited document (menus,
  collections, data graphics, status fields, fields and dialogs), because
  projection marks a document changed whenever its application finishes a
  draw;
- re-validates in depth the stored slices of every other visible document
  before reusing them;
- lowers every control, instrument and series on the screen again, except
  menus whose epochs match, and the engine admits each one;
- compares every item with the acknowledged frame;
- builds, checks and freezes Desk's shell batch for the whole screen.

Desk's shell producer builds its batch, a second candidate for the whole
screen, from the first. So each DELTA frame builds the whole screen twice,
admits it twice, plans residual glyphs twice and compares twice with an
acknowledged bank, and the aggregate passes through five whole copies on the
way: RUHA's bank, the producer's arena, its target bank, the shell's work
space and the shell's frozen bank.

Checks take 9.85 million of those 16 million steps, by the check
measurement. Only about 0.1 million of that can find something on any
frame: whether a draw, owner or acknowledgement is still current, and
whether the items fit what the terminal accepted. The rest checks items
that have not changed, proves again a memory layout that has not moved, or
checks what the same frame or an earlier one already checked. About half of
all the checking can find only a bug that wrote where it should not.

Only one signal finer than "this document drew" exists: the CELL rows a draw
changed. Part 10 of the rich experience plan uses it, so residual glyphs are
planned again only on changed rows.

What changed inside a document is not known, because nothing keeps it. A
canonical widget's dirty bit means "needs redraw"; the draw clears it before
projection runs, and UIDL never reads it. Several widget words change what a
widget shows without setting it. UIDL's own element marks drive repaint
only, and the paint clears them too. So a change made outside UIDL's own
event dispatch, by an application callback, a tick, a prompt action or one
widget's callback changing another, is invisible to UIDL. Applications work
around that by marking their own elements after changing a widget, and Pad
goes further: it checks its editor's dirty bit itself, and reads and writes
the text area's private fields through offsets copied from `textarea.f`.
That is a design violation in its own right. Canonical widgets are meant to
carry their meaning below the applet layer.

This design does three things.

- **Change is counted where it happens,** in the canonical widgets (part 2)
  and in UIDL's elements (part 5). Applications stop bridging change, since
  a widget's change then reaches UIDL, CELL and the rich path by itself
  (part 6).
- **Each check runs when it can find something** (part 3). State and fit
  are checked on every frame. New data is checked once, when an item
  changes. Memory layout is proved when memory is lent, allocated or grows.
  The checks that can find only a bug that wrote where it should not run in
  tests and in safe mode.
- **The frame follows change** (part 9). One projection, fed by the change
  counts, lowers only the elements that changed into one candidate, with
  Desk's chrome in the same projection. The renderer keeps one acknowledged
  frame, and the changes themselves are the DELTA.

The full path stays, as one of two drivers over the same capture, check and
lowering code. The change driver visits the elements that changed. The full
driver visits every element, as today's path does. It builds complete frames
(STARTs), and three more things use it:

- **safe mode** (part 4) runs the full driver, with every check, on every
  frame of an ordinary session, and sends its result. The screen then
  always shows the live state, whether or not a change was reported, and
  the rich path's own records are checked again on every frame.
- **the occasional full refresh** (part 8) captures every visible document
  in full in normal mode at a bounded interval, as the full driver's
  capture does, and compares the capture with what the screen was built
  from. A difference is a missed change: it is reported, and safe mode
  sends it, so a missed change can stay on screen for one interval at most.
- **the shadow check** (part 1) runs it beside the change driver in tests,
  as it runs today's full path beside today's shortcuts, and compares the
  two byte for byte.

**Target:** a typed letter's frame build falls from about 16 million steps,
part 0's baseline, to about 2 million. This is an estimate, and each part
replaces it with measurement. Frames that change more, such as an
application switch or a dialog opening, gain less, because more of their
inputs change. Safe mode costs about what today's path costs.

Part 0 found two more things this design takes on. Outside typing, painting
the CELL screen costs about as much as building the rich frame, and a third
to over half of that painting fills backgrounds that were just filled; part
7 stops it. And the adapter's banks are fixed at 19.1 MiB while its
snapshots use tens of KiB; part 9 removes them.

## Rules

Kept from earlier work:

- The rich-terminal rules in the workspace AGENTS.md. The same applet
  sources, UIDL documents, mounted widgets and draw lifecycle serve CELL and
  rich output. One renderer-neutral projection comes from the ordinary draw
  lifecycle and covers Desk's chrome, UIDL renderers, mounted widgets and
  applet painting. The renderer owns representation, allocation within the
  caller's bounds, clipping and presentation. CELL stays the complete
  fallback. No applet gains a terminal API or scene.
- Remove only work that is provably repeated. The proof comes from the
  module that owns the data, and a digest is not a proof. Checks follow
  their own rule, below.
- Storage is sized from what the screen and content need now, and grows on
  demand, by negotiation with the terminal where the terminal's space is
  concerned. Nothing reserves a guessed maximum.

New:

- **Each check runs at the moment it can find something new** (part 3).
  This replaces the rule that every boundary check stays at every boundary.
  Normal sessions give up one thing: the per-frame checks that notice a bug
  writing where it should not. Safe mode and tests keep them.
- **Storage the rich path takes from a memory source** needs no proof that
  it lies apart from other live storage. That rests on the allocator's
  contract that live blocks do not overlap. Storage a caller lends is proved
  apart when it is lent.
- **Change is counted by its owner.** A stage skips rebuilding an item only
  when the counters of all its inputs are unchanged. Each counter belongs to
  its input's owner: a widget's to the widget, an element's to UIDL, a row's
  to the screen.
- **When every change is counted, the terminal receives exactly the frames
  and operations the full path would send.** The shadow check tests this on
  every frame of every test run.
- **A missed change gives a stale screen, never an unsafe one.** If an owner
  fails to move a counter, the screen shows old content, but every item a
  frame sends has passed its first check. The shadow check finds such misses
  in tests, and it is on in every test of this work. The occasional full
  refresh finds those in what applications show in ordinary sessions,
  reports them and turns safe mode on, which sends the change.
- **Applications do not report change to the rich path.** The counters live
  in canonical widgets and UIDL. Applications go on changing their state
  through the ordinary widget and UIDL words. Where a widget shows data it
  borrows from the application, such as a list's rows, the widget's own
  ordinary word says that the data changed, as `TREE-REFRESH` does today.
  CELL needs that word as much as the rich path does.

## Where change is known today

This section describes the code on 2026-10-19. Part 2 has since fixed the
silent widget words, the reads that change state and Pad's reads of the
text area's fields, and part 6 removed the bridges applications kept,
described below.

| Signal | Owner | Meaning | Read by |
| --- | --- | --- | --- |
| Widget dirty bit | `widget.f` | needs redraw; cleared by the draw | the old event loop (`event.f:158`) and Pad |
| Widget revisions | input, document, dialog, prompt, picture, field model | each narrower than "anything shown changed" (below) | their own widgets, the picture snapshot, the producer |
| UIDL element mark | `uidl.f`, `uidl-tui.f` | needs repaint; cleared by the paint | `UTUI-PAINT` |
| Mounted source generation | `uidl-tui.f` | a mounted widget was swapped or detached | the collection and data-graphics captures |
| Applet instance revision (`CINST-TOUCH`) | `runtime/instance.f` | the applet's slot needs a paint | the applet host |
| RUHA document record dirty | `uidl-hybrid-adapter.f` | the document's application drew | RUHA |
| CELL touched and damage rows | the CELL backend | rows written, rows changed | the CELL feed; the residual planners through `ROW-DAMAGE` |

Six widgets already keep a revision, each for a narrower purpose. Input's
moves on every visible change, which is what this design needs. Document's
holds back failed reads. Dialog's moves on relayout and scrolling, not on a
button's state. Prompt's follows its label and bounds. Picture's names which
picture is shown. The field model's revision is a staleness token the
application issues.

Widget words that change what a widget shows without setting its dirty bit:

- base: `WDG-HIDE`, `WDG-ENABLE`, and UIDL's focus sync, which writes the
  focus bit directly (`uidl-tui.f:393-399`; explorer does the same at
  `explorer.f:154-157`);
- text area: `TXTA-SELECT-ALL`, `TXTA-BIND-GB` and `TXTA-UNBIND-GB`,
  `TXTA-GUTTER!`, `TXTA-ADJUST-SCROLL`, a move that clears the selection and
  then stops at a boundary (`textarea.f:719-769`), and a mouse release that
  clears an empty selection;
- tabs: `TAB-ADD`; menu: `MNU-ITEM-ENABLE`, `MNU-ITEM-DISABLE`,
  `MNU-ITEM-CHECK`; tree: `TREE-UNTRUSTED!`, `TREE-CONTEXT!`; explorer:
  `EXPL-SHOW-HIDDEN!`; scroll: `SCRL-INDICATORS`; picture: `PICT-CLAIM!`,
  `PICT-RICH-FAILED!`; split: `SPL-RECOMPUTE`; canvas: every drawing word.

Reads that change state: list and tree settle their selection and scroll
inside queries and inside their own capture (`LST-SELECTED`,
`LST-SCROLL-INFO`, `LST-ITEM-VIEW-CAPTURE`, `TREE-SELECTED`,
`TREE-SELECTED-KEY`, `TREE-SCROLL-INFO`, `TREE-ITEM-VIEW-CAPTURE`).

Data a widget borrows and cannot see change: a list's rows come from the
application's callbacks, and `LST-RECOUNT` returns early when the count is
the same; tab labels and status bar text are borrowed pointers. A text
grid's model is borrowed too, but applications rebuild it and bind it again,
which the widget sees.

On UIDL's side, `UIDL-NOTIFY` and the state tree's `_ST-NOTIFY` exist but
nothing calls them, so a `bind=` never marks its element. That is UIDL's
documented contract: the application calls `UIDL-DIRTY!` after changing bound
state. This design keeps that contract.

How applications bridged change until part 6:

- Pad checks its editor's dirty bit in its paint callback and redraws the
  panel or one row itself (`pad.f:2731-2768`): "Its model may change from
  app-level prompt actions that bypass UIDL's normal focused-element
  invalidation, so bridge widget dirtiness here." It routes editor keys around
  UIDL (`pad.f:2723-2727`), because UIDL's dispatch would mark and refill the
  whole editor area for each character. It reads and writes the text area's
  cursor, scroll, selection anchor, gap buffer and undo fields through
  offsets copied from `textarea.f` (`pad.f:129-136`): for buffer switches,
  range selection, undo, redo and cursor placement, and to read the text
  around the cursor. After `TXTA-SELECT-ALL`, which is silent, it sets the
  dirty bit itself.
- File Explorer: "UIDL repaints an element only when it is marked dirty, so a
  change made here, rather than through the element's own input, marks its
  element" (`fexplorer.f:537-543`).
- Grid, Sound Lab, Worlds, Observatory, Daybook, the Agent, Library and
  Streams each have an invalidate helper that sets their panel's dirty bit,
  which nothing reads, and marks the element that hosts it, which is what
  works.
- Desk's launcher sets its list's rows again and marks the list's element
  only when the row count changes (`desk.f:2550-2557`), so a change of
  content at the same count is not painted until something else marks the
  list. The sandbox and schedule surfaces do the same, with a refresh flag
  for content (`sandbox-surface.f:373-381`, `schedule-surface.f:531-543`).

## Part 0. Measure the changed frames now — measure

The last breakdown is from 2026-10-14, before fields, dialogs, notices,
status fields and plots landed. Before any change, on main:

- the typing run, `physical_typing_cadence.py run --screen-profile`, with
  every call chain kept (`MEGAPAD_PROFILE_CHAINS=0
  MEGAPAD_PROFILE_CHAIN_DEPTH=0`), read with `screen_change_profile.py`;
- Desk with one application, `physical_desktop_acceptance.py --applet NAME
  --screen-profile`, for Pad, Daybook, Sound Lab, Observatory and File
  Explorer;
- for each changed frame, the frame build by stage, in the tables of
  KEYSTROKE-FRAME-WORK, and the memory RUHA, the producer and the shell hold.

These numbers set the targets the later parts are measured against.

**Done** on 2026-10-19
(`local_testing/evidence/frames-follow-change-part0-20261019.md`), read with
the new `local_testing/frame_build_stages.py`. A typing burst frame costs
19.16 million steps, 16.13 million of them its build: the snapshot 3.78
million, the producer's candidate 3.56 million, the comparison 1.60 million,
and the shell's batch, freeze, emission and per-dispatch checks 6.75
million. Desk with one application builds a DELTA interaction's frames in
7.5 to 10.9 million steps on average and a START's in 18.3 to 23.5 million.
The adapter's banks are 19.1 MiB, fixed when Desk starts, and its snapshots
used 12 to 40 KiB; part 9 removes the banks. Outside typing, Desk's painting
costs about as much as the frame build, and a third to over half of it is
repeated background fills, which part 7 removes. The CELL flush outside the
producer took 51 to 488 million steps over a run, which this design leaves
out.

## Part 1. A shadow check of every shortcut — test tool

**Change.** A switch, off by default (`tui/rich-terminal/frame-shadow.f`).
While it is on, each shortcut the frame build takes also runs its full path,
into storage that does not feed the frame, and the two results must be byte
for byte equal:

- the snapshot adapter captures every visible document live, before its
  ordinary capture reuses unchanged documents' slices and passes over
  documents known to be empty;
- the screen producer plans every row after a plan that kept a held plan
  or copied the runs of unchanged rows, and plans a document's menu
  controls afresh after copying them from the acknowledged bank;
- the shell plans a whole region after copying its unchanged rows' runs.

The shortcut's result is the one the frame goes on with, so a run sends
exactly the frames it would send with the check off. Each difference is
counted, and the first one kept: its stage, its item, the first byte that
differs and the draw. Each later part puts its own shortcuts under the check
as it adds them.

**Where it runs.** `--shadow-check` on `physical_desktop_acceptance.py`,
`physical_typing_cadence.py` and `akashic_tui.py` turns it on at boot. Such
a run fails when it ends if the check found a difference, skipped a
comparison for want of memory, or was asked for and not on. Unit tests turn
it on directly. It never runs in an ordinary session, and while it is off
each shortcut costs one test of the switch.

**Why first.** Every later part is checked by it from its first commit. It
also checks today's shortcuts on real frames: the adapter's reuse of
unchanged documents, the producer's held plans, row damage and menu reuse,
and the shell's row reuse.

**Done** on 2026-10-24 (06c0532d, d59b8e3a, 8c615beb, with the counts by
stage in a1c5d5fb). With the check on, the typing run, Desk with each of ten
applications and the canonical Desktop journey made 9,709 comparisons, with
every stage taking and checking its shortcut in every run, and found no
difference. See the [evidence](../../local_testing/evidence/frames-follow-change-part1-20261024.md).

## Part 2. Widgets count their changes — design, fixes a violation

**Change.**

- The widget header gains a revision. `WDG-DIRTY` moves it, and so does every
  base word that changes what any widget shows: show, hide, enable, disable,
  and setting or clearing focus. The dirty bit keeps its meaning for painting.
- Every word that changes what a canonical widget shows moves its revision.
  The silent words listed above are fixed, and UIDL's and explorer's focus
  syncs go through the base words. `scroll.f` and `split.f`, which nothing
  loads, are left as they are.
- Input's revision already means this, so it becomes the base revision. The
  other existing revisions keep their narrower meanings.
- A widget that shows others, such as a prompt's input or an explorer's
  tree, counts their changes in its own revision. A reader of any widget's
  revision then needs no knowledge of which widgets hold others.
- A query or a capture changes nothing. List and tree settle their selection
  and scroll in the words that change rows, selection or size.
- A widget that shows borrowed data has one ordinary word that says the data
  changed. Lists gain one, since `LST-RECOUNT` returns early on an equal
  count. Tabs and the status bar take their setters again for changed text.
- The text area gains public words for everything Pad reaches into its fields
  for: saving and restoring its view on a buffer switch, selecting a range,
  undo, redo, placing the cursor, and reading its text, cursor and selection.
  It also paints only the rows its last change touched when nothing else
  changed, as Pad's fast path does today through `TXTA-DRAW-ROWS`, so that
  saving stays in the widget.
- UIDL reads widgets only through their public words. Each widget that UIDL
  mounts gains a word that says whether a widget is a genuine one of its
  kind, for UIDL's checks of mounted widgets, and UIDL reads regions,
  buffers and sizes through the widgets' own words.

**Tests.**

- For every canonical widget that something uses (list, tree, tabs, text
  area, input, prompt, dialog, picture, text grid, field, data graphics,
  explorer, canvas, media and the document view): each public word that
  changes it moves the revision, including a change that reaches a widget it
  holds, and the widget then draws exactly what a fresh widget in the same
  state draws; each query and capture moves nothing.
- A structural test fails when a module outside a widget's file reads or
  writes that widget's fields by offset.

**Done** on 2026-10-25 (73147730 to 944630df). Each word that changes what
one of the fifteen kinds shows moves its revision, and the per-widget test
checks every such word. The text area now judges which rows Pad's typing
changed, and UIDL reads widgets through their public words, which the
structural test enforces. Testing found and removed two kinds of false
change: paints that marked a change, which sent a shown prompt's field
again on every frame, and a focus sync in Pad that redrew its whole editor
on every typed frame. With the shadow check on, Desk with the applications
each slice touched, the typing run and the canonical Desktop journey found
no difference. A typed letter's burst frame took 1.3 million more steps to
build at the end than at the start, 16.69 million against 15.37, most of
it in span-set proofs that split their query because other storage now
lies between the spans they prove; part 2 changed none of them. See the
[evidence](../../local_testing/evidence/frames-follow-change-part2-20261025.md).

## Part 3. Checks run when they can find something — a trade

**Today.** Every check runs at every boundary on every frame. The check
measurement sorts the checks of a typed letter's frame build by when they
can find something new:

- **state and fit,** 0.10 million steps a burst frame: whether a draw, owner
  or acknowledgement is still current, and whether the items fit what the
  terminal accepted. These can find something on every frame.
- **item checks,** 1.74 million: the items a frame sends, checked when a
  capture reads them or the engine admits them. These can find something
  when an item changes.
- **handover proofs,** 2.95 million: headers, and spans proved apart from
  other storage, at every entry, several times a frame. Their answer can
  change only when memory is lent, allocated or grows. Their cost also
  follows memory layout: a proof splits its query wherever other storage
  lies between the spans it proves, and in part 2's typing runs the
  span-set proofs took 0.7 to 2.2 million steps a burst frame as
  allocations moved.
- **repeats,** 5.08 million: checks of data that nothing has written since
  it was last checked, or that the frame has just built from parts it
  checked. These can find only a bug that wrote where it should not.

**Where each check runs**, once this design is done:

| Group | Today | Normal mode | Safe mode | Tests |
| --- | --- | --- | --- | --- |
| State and fit | every frame | every frame | every frame | every frame |
| Item checks | every item, every frame | each changed item, once | every item, every frame | each changed item, and every item through the shadow check |
| Handover proofs | at every entry, several times a frame | when memory is lent, allocated or grows | every frame | as in normal mode, and every frame in the tests of the proofs |
| Repeats | every frame | off | every frame | off, and every frame in the tests of the checks |
| Full rebuild | every frame, with some reuse | never; a full capture at each full refresh | every frame | every frame, beside the change driver |

This part moves the handover proofs and the repeats. The item checks follow
change once part 9 builds only what changed; until then they visit every
item on every frame, because the build does.

The item checks a thin frame keeps are the record and text checks of the
items that changed, about 0.07 million steps for a typed letter's controls
in the measurement, and the captures' checks of the elements that changed.
Text that reaches the wire is still read once for valid UTF-8 and for the
characters the wire refuses.

Input that comes back from the terminal is checked as it is today, in every
mode: the owner, generation and frame a click or key names, and the control
it names in that frame.

**Change.** The repeats go behind a switch, every-frame checks
(`tui/check-mode.f`). It is off, so compositions and tests run in normal
mode, unless something turns it on: a test of the checks it holds, safe
mode, or a diagnostic run (`--every-frame-checks`). The handover proofs run
when storage is lent, allocated or grows, instead of at every entry.
Storage taken from a memory source is no longer proved apart from other
live storage.

**Kind.** A trade, not a removal of repeated work. Normal sessions stop
noticing a bug that writes into the rich path's memory between handovers.
Safe mode keeps those checks, and the tests of them turn them on
(decision 4).

**Effect.** The check measurement's rows put the saving at about 8 million
steps of a typed letter's 16 million. This part needs no change counts, so
it comes straight after part 2.

**Done** on 2026-10-25 (fc62e45f to 5baf027d). The switch is
`tui/check-mode.f`, off unless a test of its checks, safe mode or
`--every-frame-checks` turns it on. The first slice made RUHA's
record and banks one block, so that no other storage can lie between them;
the span-set proofs that memory layout had split fell from 2.15 million
steps a burst frame to 0.55. Eight slices then moved the repeats and the
per-frame handover proofs behind the switch. Each keeps, in both modes, the
state and fit checks, the identity of each record a step reads, the shapes
of the spans its arithmetic uses, the bounds of the writes it makes, and
the engine's admission of each item the frame sends. A typed letter's burst
frame build fell from 16.69 million steps at the end of part 2 to 9.62, and
all its steps from 19.59 million to 11.36. Cheaper frames let the guest
answer every key with a frame of its own, 18 rather than 15, so the burst's
total fell less, from 294 million steps to 205. With every-frame checks on,
the frame build took 15.41 million, about its cost before the switch. The
shadow check found no difference in any run in either mode, and the
canonical Desktop journey passed with it, without it, and with it and
every-frame checks. Checks still take 3.48 million of the frame build: the
item checks, 1.78 million, which follow change once part 9 builds only what
changed; the engine's admission of the shell's batch and the planner's
bounds on its writes, 0.76 million; UIDL-TUI's rechecks of its cached
relations, about 0.2 million, which part 5 replaces; and handover proofs,
0.54 million, most of them the public admissions' and the captures' proofs
of the spans they are given. See the
[evidence](../../local_testing/evidence/frames-follow-change-part3-20261025.md).

## Part 4. Safe mode — safety

**What it does.** Every frame goes through the full path with every check
on, and the full path's result is what the terminal receives. The screen
shows the live state of every element, whether or not anything reported a
change, and every check of the rich path's memory runs on every frame. Until
part 9 builds the two drivers, the full path is today's build with its reuse
shortcuts off, which is what the shadow check already runs beside them.

**What it costs.** About twice normal mode's cost, since it reuses nothing
and runs every check. At the end of the part an isolated character took
41.96 million steps in safe mode against 20.31 in normal mode, more than the
26 million the path took before part 3, against the target of about 2
million for a thin frame.

**How it is turned on** (decision 6):

- a key in Desk's system settings, kept across sessions on a read-only
  volume that nothing inside Desk can change (decision 10);
- a boot option;
- by itself, when the thin path meets an anomaly: a handover proof that
  fails, or, from part 8, a full refresh that finds a missed change. Desk
  then says that it is in safe mode, and records why. A first check that
  refuses outside data, such as a file's broken text, is not an anomaly.

The handover proofs are the snapshot adapter's, that its banks lie apart
from a document's storage and an owner's, when it installs, when its host
starts and when a document attaches; and the screen producer's, the
shell's and the engine's, that a block Desk's memory source hands them as
they grow lies apart from what they hold. One that fails names what it
found damaged. Desk's owner of the rich terminal says in a notice that
safe mode is on and why, once, and says once more the first time a check
names damage while safe mode is on; the guest's diagnostics record the
reason and the first damaged structure. Desk without a rich terminal has
no safe mode to speak of, and loads none of it.

**What it cannot do.** Safe mode makes the screen match what the
applications hold. It cannot make an application's own data right, and it
cannot stop a native application that means harm, since such an application
shares Desk's memory.

**Why keep it.** A missed change is silent. The old picture is valid, so
every check passes and nothing looks wrong. Suppose an approval application
shows a payment of 1,200 with an Approve button. An update from the server
changes the held amount to 120,000, through a path that, by a bug, does not
move the list's revision. In normal mode the screen keeps showing 1,200 until
that row changes again or the next refresh, and an approver who clicks
Approve approves 120,000. In safe mode the next frame is built from the held
record, so the screen shows 120,000 before anyone can act on the old figure.
Where a wrong screen costs more than the steps, such as approvals,
operations consoles or audits, safe mode is worth its cost.

A second danger is memory damage. A bug in a native application can
overwrite part of the rich path's memory, such as its record of the frame
the terminal holds, which later frames build on and which tells a click
which control it reached. In normal mode nothing checks that record again,
so the damage can spread into what the screen shows or where a click goes.
In safe mode the rich path's records are checked on every frame and every
frame is rebuilt from the live state. A check that catches the damage names
the damaged structure and refuses what would have been built on it. A frame
whose build finds damage is shown as plain text, and the next draw tries
rich again with every check. When the damage is in the record of the frame
on screen, the DELTA that would start from it is refused, and the frame goes
out whole, built from the live state, which reads nothing from the damaged
record; until then no click is routed through it. Damage to the terminal
engine's own records stops the session, as any broken engine record does,
since nothing can be sent safely without them.

These checks prove each record's structure: its sizes, offsets, spans and
links. Damage that leaves a record well formed but changes what it holds,
such as the text of one run in the record of the frame on screen, passes
them, and a DELTA built on that record could then leave the old text on the
screen. So that record is sealed (decision 9). In safe mode the record of a
frame takes the CRC-64 of what it holds, from the CRC engine, when the
frame is sent, and a DELTA or a click uses the record only while it still
matches. A CRC-64 finds every run of damage up to 64 bits long, and other
damage all but once in about 2^63 times. A record without a seal is not
used either, and nothing is named: one sent before safe mode was on, or
one sealed while the task held the CRC engine for something else. The
next frame then goes out whole.

**Change.** The switch, and the ways to turn it on.

**Effect.** None in normal mode. In safe mode, about today's cost.

**Tests.** A unit test damages a record of the acknowledged frame, and
expects safe mode to catch it on the next frame, refuse the DELTA built on
it, send the frame whole and name the structure, and to route no click
through it.

**Done** on 2026-10-26 (Akashic be9a8c80 to 75a5c9e5, MegaPad e5b4ae34 to
1833d16f). Safe mode is `CHK-SAFE-MODE` in `tui/check-mode.f`, which keeps
the first reason it is given for the session. Desk's system settings ask
for it in `system.toml` on the settings disk, MegaPad's second storage unit,
whose medium is write-protected. KDOS opens that disk's volume read-only,
and Desk mounts its filesystem for one read before it builds its first frame
(`tui/desk-system-settings.f`). MegaPad gained the second controller in the
emulator, the simulator, the BIOS, KDOS and the RTL, and the two
controllers share the disk's one DMA port. `--safe-mode` asks for safe
mode at boot, and a handover proof that fails turns it on by itself. The
rich terminal's owner then says in a warning notice that safe mode is on
and why. In safe mode the five reuse shortcuts are off, every
check runs and names the structure it finds damaged, a damaged build is
shown as plain text, and the bank of the frame on screen is sealed with the
CRC engine's CRC-64. The physical runs found two defects the unit tests
could not: the shell's seals overwrote the extension record its record
embeds, and the settings read left Desk without a current filesystem. Two
more were found on the way: a shell click that had read the wrong bank
since part 3, and a test journey that dropped a key the terminal held back.
The canonical Desktop journey passed with the shadow check, making 4,692
comparisons and finding no difference, without it, and with the settings
asking for safe mode, where it compared nothing, since nothing was reused.
Normal mode costs what it did at part 3's end, a burst frame build of 9.63
million steps. In safe mode an isolated character costs 41.96 million, about
twice normal mode's 20.31, of which the seal takes 2.23 million. See the
[evidence](../../local_testing/evidence/frames-follow-change-part4-20261026.md).

## Part 5. UIDL sees its widgets' changes and counts its own — design, fixes a violation

**Change.**

- Each UIDL element gets a revision. It moves when the element itself
  changes: its attributes (`UTUI-SET-ATTR`, `UTUI-CHECKED!`), its widget
  (`UTUI-WIDGET-SET`), its children, its layout, its visibility and its
  focus, and on the application's `UIDL-DIRTY!`. Marking for repaint alone,
  such as a dirty parent marking its children so they paint over its
  background, does not move it.
- The two writers that set the dirty bit without the hook
  (`_UTUI-DIRTY-CHILDREN`, `UTUI-INVALIDATE`) are paint-only marks and stay
  so; every change goes through the counted path.
- UIDL keeps, for each element that hosts a widget, materialized or mounted,
  the widget revision it last painted. A paint pass paints an element whose
  widget's revision moved, as if it were marked. A widget's change also asks
  for that pass through the hook `UIDL-DIRTY!` uses, so its slot repaints.
- A key a focused widget consumes no longer marks the whole element; the
  widget's own revision and its own partial paint cover it. Pad's reason for
  routing keys around UIDL goes with that.

**Tests.** Changing a mounted widget from outside UIDL's dispatch, from a
callback, a tick or another widget's callback, repaints it with no
application code; a paint-only mark moves no element revision.

**Done** on 2026-10-27 (d852aa27 to 7607b145). Each UIDL element has a
revision, `UIDL-REVISION`: the stamp of its last change, from one count that
every document and context shares, so a revision is never taken twice.
uidl.f counts the changes it makes and UIDL-TUI those it owns;
`UIDL-TOUCH` counts a change, `UIDL-MARK!` only repaints, and `UIDL-DIRTY!`
does both. For each element that hosts a widget, UIDL keeps the widget's
revision as it last painted it. The paint pass paints an element whose
widget moved, with a `<scroll>` around it first, and every revision move asks
for a paint through widget.f's change hook, except under `UTUI-PAINTING`,
which the shell's paints and the rich side's picture claims run under. The
applet host turns a request a child's tick raises into that child's slot. A
key or pointer event a widget consumed and counted marks nothing, and a
clean element first tries its widget's partial draw: canonical kinds
register drawers, and the text area's draws a typed character's row. Three
defects were found on the way: `UIDL-MOVE-ELEM` passed its arguments to the
link the wrong way round; part 4's settings documentation used renderer
words in a neutral document; and until 7607b145 the rich side's picture
claims asked for a paint from their own context, which sent two STARTs for
nothing in the canonical journey. A typed letter costs what it did at part
4's end, a burst frame build of 9.64 million steps, since Pad still bridges
its editor until part 6. The canonical journey passed with the shadow check,
making 4,621 comparisons and finding no difference, and without it, with 37
and 38 STARTs against part 4's 39. The STARTs those runs left out are ones
Desk sends but never shows where Pad opens a document, which go out only
when the key's paint comes before the tick that opens the document; part
6b removes them. Under the same conditions part 4's code and the final code
sent the same 128 presents. The UIDL-TUI rechecks of cached
relations, about 0.2 million steps, stay for part 9, which stops the
captures they run in. See the
[evidence](../../local_testing/evidence/frames-follow-change-part5-20261027.md).

## Part 6. Applications stop bridging change — cleanup

After parts 2 and 5, each application loses the code that only carries
widget changes to UIDL:

- Pad: the paint-time dirty check and row redraw, and the key routing around
  UIDL. Its copied text area offsets went in part 2. Its editor is its own
  composite panel, whose revision does not follow the text area inside it,
  so the panel must count the text area's changes and draw typed rows
  alone, or the text area must be mounted itself, for UIDL to see and
  paint typing.
- File Explorer: its dirty helpers.
- Grid, Sound Lab, Worlds, Observatory, Daybook, the Agent, Library and
  Streams: each invalidate helper shrinks to what the application's own
  state needs.
- Desk's launcher, sandbox and schedule surfaces: their row-count tests and
  refresh flags give way to the list's own word for changed rows, so the
  launcher also shows a change of content at the same count.

Each application is checked with its own tests and Desk with that
application. This part follows part 5 directly, so the design violation is
fixed in full before parts 7 to 10 change the paint pass and the frame
build.

**Done** on 2026-10-27 (2ece3986 to b330a58e). Pad's editor is now the
canonical tab strip and text area, each mounted on its own region of the
editor area, so UIDL lays them out, focuses the text area, gives it its
keys and paints each as it changes, and a typed character redraws its row
through the text area's partial draw. Mounting them was chosen over a panel
that counts its children's changes, which could not draw a typed row alone.
Two general capabilities came with it: an element authored
`focusable=false` takes no focus while a press still reaches its widget,
and `TXTA-ON-CARET!` tells a text area's owner when an event moves its
caret. File Explorer's element helpers and shell calls went, and the eight
panel applets' invalidate helpers kept only the panel's own count, its
rebuilds and its status. Where an applet draws its prompt over the status
bar, the status bar is marked with `UIDL-MARK!` once the prompt closes,
which repaints without counting a change. Desk's launcher, sandbox and
schedule screens tell their lists when rows change, so the launcher now
shows an entry's new state at the same count. A partial drawer declines a
widget that only carries its kind's number, since applets' panels reuse the
media and document numbers. Two calls stay for reasons of their own: the
Agent's after it opens a review dialog from its tick, since opening a
dialog counts no change, and Daybook's instance touches, which drawing no
longer needs but resource references read. A typed letter's Desk painting
fell from 1.04 to 0.80 million steps a frame; its frame build is unchanged,
and Desk's own frame is now most of Desk's painting, which part 9b takes
up. Desk with each applet committed part 5's frames, or differed by timing,
which two pairs of runs comparing the code before and after a slice showed
window by window. The canonical journey passed with the shadow check,
making 4,692 comparisons and finding no difference, and without it, each
run with 39 STARTs, the START never shown at both handoffs to Pad included,
which part 6b removes. See the
[evidence](../../local_testing/evidence/frames-follow-change-part6-20261027.md).

## Part 6b. A document handed to Pad opens before Desk paints — speed-up

**Today.** Daybook's Ctrl+O and File Explorer's open hand a document to Pad
through Desk's intent route. The route runs inside the sending applet's
input handling: it focuses Pad at once and queues the request on Desk's bus,
and Pad's handler opens the document only when Desk's next tick pumps the
bus. The pass that handled the input usually paints first, so Desk builds
Pad focused with its old document and sends it as a START, since a refocused
task cannot go out as a DELTA. By the time the terminal has answered that
START, Desk's tick has opened the document and painted again, and the screen
producer stages a replacement from the newer draw instead of revealing the
first. That first START is built and sent but never shown: in part 5's runs
it cost about 37 million guest steps and 122 KB at the Daybook handoff, and
50 million steps and 166 KB at File Explorer's. Only when Desk's
50-millisecond tick has already fallen due by the time the input's pass
reaches it does the document open first, under one START, so the canonical
journey sends 37 to 39 STARTs as the timing falls.

**Change.** Desk delivers the requests an input queued in the same pass,
before that pass paints. Each pass runs the shell's service step, for work
due now, after input and before the tick and the paint; Desk pumps its bus
there as well as in its tick, so a handoff's request reaches Pad's handler
before the first paint after the input. The route still focuses Pad at once,
and that paint shows Pad focused with the document. Requests queued during a
tick keep the tick's own pump.

**Tests.** A key that queues `resource.open` from Daybook has Pad's handler
run before the pass that handled it paints, and that pass paints once. The
canonical journey then sends one START at each handoff to Pad, whatever the
timing, with its checks of the new tab and its text passing, and Desk with
Daybook and with File Explorer pass.

**Effect.** At each handoff to Pad, one frame build and one START fewer
where the input's paint used to come first: about 37 million guest steps and
122 KB at Daybook's, and 50 million steps and 166 KB at File Explorer's.
Other requests an input queues are delivered before its paint in the same
way. A terminal without the rich path no longer shows the frame in between,
Pad focused with its old document, either.

**Done** on 2026-10-27 (411a8d67). Desk's per-pass service pumps its bus as
well as its tick, and reports work when the pump delivered a request. A
check in Desk's suite has the service deliver a queued request and fails
without the pump. The canonical journey sent 37 STARTs in each of three
runs, with the shadow check, without it and profiled with a pinned hash
seed, where part 6's runs each sent 39. Against part 6's profiled run, 77
of 79 input windows committed the same presents; at the two handoffs the
START never shown is gone, and the frame shown, the same to the byte, is on
screen 0.64 seconds sooner at Daybook's and 0.86 at File Explorer's. The
two windows took 43.7 and 53.9 million guest steps fewer, and the journey
sent 288,150 bytes fewer. In the interval after the key, Desk's service ran
Pad's open handler before the pass painted. Desk with Daybook, the Agent,
File Explorer and Pad passed with the shadow check. See the
[evidence](../../local_testing/evidence/frames-follow-change-part6b-20261027.md).

## Part 7. A repaint fills each cell once — exact speed-up

**Today.**

- When a document repaints, each container element fills its whole
  rectangle with blanks before its children draw (`_UTUI-FILL-BG`,
  `uidl-tui.f:1010`), and each child container fills its own rectangle
  again. Nested containers cover largely the same cells.
- A fill (`DRW-FILL-RECT`, `draw.f:582`) draws its rectangle a row at a time
  through `DRW-HLINE`. Each row takes its own borrow of the screen's back
  plane, and each cell its own store into the plane.
- In File Explorer's item open in part 0, the root, the split, the region,
  the tab set and the scroll area filled for 24.1 million of the painting's
  30.9 million steps; the widgets themselves drew for 6.4 million. Over part
  0's runs, fills took 15 to 455 million steps a run, a third to over half
  of Desk's painting, which outside typing costs about as much as the frame
  build.

**Change.**

- A fill leaves alone every row whose cells, and the residue the draw
  records for them, already hold byte for byte what the fill would write.
  Each row is checked with block compares, and only rows that differ are
  written.
- A fill takes one borrow of the back plane for all its rows.

**Proof.** A row left alone already holds what writing it would store, in
its cells and its residue. The CELL damage plan comes out the same: a row
this fill does not write was either untouched since the last commit, and so
equal to the front, or written earlier in the frame and still marked as
touched. The tests compare the screen, the residue and the damage plan of
whole paints, with and without the check, over seeded documents with nested
containers, styles, wide characters and clips. The shadow check compares
the rich frames.

**Effect.** Most of the repeated fills. This is CELL-side work, done on
every repaint whether the terminal is rich or not, so it helps the
simulator and the chip alike. Parts 2, 5 and 6 cut how often whole
documents repaint; this part cuts what each repaint costs. It comes after
parts 5 and 6 because it changes the same paint pass.

### Then three faults part 6 found

Part 6 found three faults that its own work did not need fixed. They are
fixed at the end of this part, after the fill change, each with its own
tests and Desk runs (decision 12).

- **Opening a dialog asks for no paint.** `_DLG-OPEN` makes a dialog the
  one its application shows, and the host paints it over the application,
  but nothing asks for that paint. A dialog opened from a key shows
  because the host marks the slot of any key an application handled. One
  opened from a tick, a request or a service pass shows only if something
  else in that pass asks for a paint. The Agent works around this with an
  `ASHELL-DIRTY!` after it opens its review dialog from its tick. Inside
  Desk that call marks no slot. The dialog shows only because the runtime
  revision that brought the review also counts a change to the Agent's
  panel in the same tick. **Change:** opening a dialog moves the dialog's
  revision, so it asks for a paint as any widget's change has done since
  part 5, and the Agent's call goes. **Tests:** a dialog an application
  opens from its tick, with nothing else changed, paints in that pass.
- **The Agent's account panel stays on screen under its prompt.** The
  Agent draws its account panel over its body from its paint callback. Its
  own panel draws only its background while the account panel or the run
  settings show. Opening the prompt hides them without counting a change
  to the Agent's panel, so nothing repaints the body. The account panel's
  cells then stay until something else repaints. This was found by reading
  the code, and it predates part 6. **Change:** hiding an overlay that
  shows counts a change to the Agent's panel, since its drawing changes.
  **Tests:** with the account panel or the run settings showing, opening
  the prompt repaints the body.
- **File Explorer sends STARTs the terminal never shows.** In part 6's
  runs Desk with File Explorer sent ten such STARTs, 222,683 bytes, and part
  5's code did the same. They came after one key, three document scrolls
  and two tab switches that show pictures. Each was staged, and a newer
  draw completed before it was revealed. The producer then built and sent
  a START from the newer draw instead (`_RTHP-REVEAL-STALE`).
  **Change:** this part's profiled runs of Desk with File Explorer show
  which draws overtake each START and what work lies behind them. The fix
  removes that cause, as part 6b did for the handoff to Pad. If the cause
  cannot be removed, the choice comes back for a decision. **Tests:** they
  follow the cause; Desk with File Explorer then sends no START the
  terminal never shows.

**Done** on 2026-10-27 (cb62b4a8, 919dcb7d, 41b03497, 76435b62 and
95a4b849). A fill takes one borrow of the back plane for its rectangle. For
a narrow character it checks each row's cells, residue and provenance with
block compares and leaves alone a row that already holds what it would
write. A row that differs is stored whole with block stores when no cell
it replaces is half of a wide pair, and one over half of a pair goes
through `DRW-HLINE`, which repairs the pair. Every row still counts as
touched. The first version, which only left rows alone, made fills a fifth
cheaper at best and Sound Lab's dearer, since the rows a fill must write
are most of its cost: a region repaints over what its widget drew, a root
over the previous frame. With the stores, fills fell by 90 to 95% in Desk
with Pad, Daybook, Sound Lab, Observatory and File Explorer, and Desk's
painting by 56 to 87%; the typing run's fills fell from 29.6 to 2.7
million steps, and a typed letter's Desk painting from 0.92 to 0.79
million. Each pair committed the same presents in every window, except
File Explorer's, whose five differing windows end on the same presents and
differ in frames stepped work overtook. A test compares the fill with the
one it replaced from 96 seeded states and over seeded documents, plane by
plane and flush by flush.

Then the three faults part 6 found. Opening a dialog moves its revision,
so it asks for its paint wherever it opens, and the Agent's call after its
review dialog went. Hiding the Agent's account panel or run settings
counts a change to its panel, so the body repaints under the prompt. File
Explorer's STARTs never shown had three causes. A scroll's detents were
painted one at a time: the shell now paints an input event the terminal
owner gives in steps once it is whole, through a new `held` callback in
the owner interface, so each scroll sends one START, on screen 0.3 to 0.4
seconds sooner, and a text sent as one event paints once. A document's
loading in slices after a tab switch sends a START for each stage the view
shows, and the next stage often overtakes it; those frames stay (decision
13), five to nine a run. A notice's expiry just as the next key arrives is
a race between two changes, which nothing removes. The canonical journey
passed with the shadow check, 4,361 comparisons and no difference, and
without it. Profiled against part 6b's end with a pinned hash seed, it
took 3,479 million steps instead of 3,762: Desk's painting fell from 337
to 126 million and fills from 174 to 12.5 million. Sixty of its 79 windows
committed the same presents; four texts went out in one DELTA instead of
two, and the other differences are the sizes of the disk image's source
files, which differ between commits. See the
[evidence](../../local_testing/evidence/frames-follow-change-part7-20261027.md).

## Part 8. The occasional full refresh — safety

**When.** In normal mode, once input has been quiet for a second, and at
least once every five seconds while a rich screen is shown (decision 7), at
a moment when no paint is pending. It draws nothing (decision 14): a draw
that changed nothing still sends a frame in the ordinary case, a
one-operation revision fence, since the wire forbids an empty DELTA, so a
refresh that drew would send one each time, even when it found nothing. A check
takes a while, and input that came during it is bound to the frame on
screen: the owner reads the terminal again after a check, so that input
reaches the application before anything later in the pass draws.

**What it does.** It captures every visible document in full, as the full
path does, into the snapshot adapter's spare bank, and compares the capture
with the snapshot the screen was built from. Every change counted since
that snapshot has asked for a paint, so with none pending the two agree;
any difference is a missed change. The refresh then records a report that
names the application, the family and the element, with the element's
revision, which did not move, and turns safe mode on (decision 6). The next
frame is built in full from live state and goes out whole, which sends the
change.

**What it bounds.** A missed change in what an application shows stays on
screen for one interval at most, and every such change leaves a report that
points at the code that failed to count it. The producers' reuse of screen
rows builds from the screen's own cells, which the check does not capture
again; the shadow check keeps covering that reuse in tests.

**What it costs.** One full capture of the visible documents per check,
6.2 million steps in the typing run and about 8.0 million in the Desktop
journey, where more documents show, and nothing on the wire unless it finds
a missed change.

**Change.** The check, its timing in the rich terminal's owner, its report,
and a missed change as a reason for safe mode.

**Tests.** A unit test changes a widget's borrowed data without its change
word, and expects the next check to find the change and report it, safe
mode to turn on, and the next capture to hold the change.

**Done** on 2026-10-27 (ab0e4429 and 19b4b765). The check runs as above;
it found no missed change in Desk with any application or in the Desktop
journey, which made 79 or 80 checks a run. Its cost is twice the plan's
estimate: a check is one capture of every visible document, without the
reuse the frame build has. In the typing run the one check added 6.2
million steps to 429.7 million; in the profiled journey 80 checks added
634 million to 3,479 million, while the frame build and every present but
a few cells of File Explorer's size column stayed the same. Desk with
Streams found a fault: a check, about 8 million steps, could be running
when a click arrived, and a tick and paint later in the same pass then drew
a frame in which nothing changed, which sent nothing but made the click
stale, so Streams never got it. The owner now reads the terminal again
after a check, so such input comes before the rest of the pass. That a
draw which changes and sends nothing makes the frame on screen stale for
input stays an open defect, older than this part. The record is
`local_testing/evidence/frames-follow-change-part8-20261027.md`.

## Part 9. One projection, two drivers — repeat, with memory

This is the part that makes the frame follow change. It needs the change
counts of parts 2 and 5. Both drivers use the same capture, check and
lowering code. They differ in which elements they visit and in where their
result goes.

### What a frame build does now

A typed letter's burst frame took 9.63 million steps to build at 4f4c935a,
measured with the typing run at the start of this part. Three layers each
rebuild the whole screen and then compare it with the frame on screen:

- The snapshot adapter captures a document whole, every family of it,
  whenever the document painted, and copies the others: 1.59 million.
- The screen producer copies the snapshot, lowers every root again,
  numbering identities by position (control *i* is the first object plus
  *i*), admits every item, packs a target bank, and joins that bank's
  controls to the acknowledged bank's by their keys, renumbering them to
  the acknowledged identities: 4.22 million.
- Desk's shell copies every one of those items into its regions, plans the
  glyph runs of every region again, copying those of rows no draw changed,
  admits the whole batch again, freezes it into a bank, and compares the
  bank with its acknowledged one: 3.58 million. Its comparison is what goes
  on the wire. The producer's only decides whether the frame can be a DELTA
  and lends the shell its identities.

Block moves cost almost nothing in this profile; the steps go to visiting
every item, to check it, copy it with its pointers rebased, or compare it.
Two more facts shape the change driver. No root can be lowered alone
today: identities, text cursors and claims run across roots, and each lane
checks a root against every claim placed before it. And the counters of
parts 2 and 5 do not yet cover everything a capture reads (below).

### What a root's capture reads

The change driver's unit is a root: the menus of a document, a collection
root (a text area, text grid, tab set or item view), a data-graphics root, a
status field, a field, or the dialog a document shows. Its key is the one
the comparison already joins controls by: the document, source, index,
subkey, lifecycle and scope.

Element revisions come from one count every document shares, so a root
whose element, ancestors and the descendants it reads carry no revision
newer than the frame's has not changed in UIDL. Widgets count their own
changes. A capture also reads what nothing counts yet, and each must be
counted by its owner or compared directly:

- the regions of mounted widgets, which carry no counter;
- which widgets a document mounts, and their keys, which change only when a
  draw observes them;
- data-graphics and field models an application edits in place;
- which prompt is a document's overlay, and the screen's size;
- whether a dialog is shown, and the count of dialog-element changes that
  element dialogs embed, which every document shares;
- Desk's shell model, whose epoch counts paints rather than changes.

### The change driver

- **What changed.** The change driver reads the revisions that parts 2 and
  5 add: each canonical widget's, and each UIDL element's. It compares
  directly what is not counted (above), the shell model included, and reads
  each document's geometry, visibility, focus and occlusion, and the CELL
  rows a draw changed (`ROW-DAMAGE`).
- **What the projection keeps.** For each element that projects, the
  projection keeps the revisions it last projected and the wire items they
  became (decision 8).
- **A frame.** The driver visits only the elements whose revisions moved.
  It captures each into scratch, checks what it captured, lowers it, checks
  that the items fit what the terminal accepted, and compares them with the
  items that element sent before. The items that differ, and their
  operations, go into the pending change set. Residual glyphs are planned
  once, for damaged rows only.
- **One candidate.** Desk's chrome (panes, taskbar bands and status) comes
  from the shell model through the same projection. The shell's second
  candidate, its work space and its frozen banks go. How application items
  are placed in their pane regions within one candidate needs its own look
  (9b).
- **The renderer.** The renderer keeps the acknowledged frame, with its items
  and input targets. The DELTA is the pending change set, so no comparison of
  the whole screen is needed. On ACK the change set is applied to the
  acknowledged frame. When a change cannot go out as a DELTA, for the reasons
  that send a START today (a refocused task, storage growth, moving pictures,
  changed instruments, changed membership), the full driver builds a START.

### The full driver

The full driver visits every element. It captures, checks and lowers each,
builds a complete candidate, and compares it with the acknowledged frame
through today's comparison, which then decides between a DELTA and a START.
STARTs, safe mode and the shadow check use it, and the full refresh uses
its capture (decision 14).

### Slices

Laid out on 2026-10-28, once the snapshot, the producer and the shell had
been read for this part, in the order decision 15 chose: one record of the
frame before the change driver.

- **9a.1. Change detection.** Each snapshot records, for each root, what
  its capture read: the newest revision among the elements it reads, its
  widget's and its model's revisions, and the facts compared directly. The
  producer keeps these facts with each target bank, so the frame on screen
  keeps the facts it was built from, and a pass over the visible documents
  finds the roots that changed since. Nothing acts on the pass's answer
  yet. With the shadow check on, every control, status field or instrument
  the comparison finds changed must belong to a root the pass found
  changed, or the run fails; each frame also counts the roots found changed
  and those whose items changed. The gaps listed above are closed here, so
  the change driver starts from detection the journeys have checked.
  **Done** on 2026-10-28 (cce2ade3). The facts are `tui/uidl-root-facts.f`
  and `RUHA-ROOT-FACTS@`; the judge sits in the comparison. With the shadow
  check on, the typing run, Desk with each of the ten applications and the
  canonical journey passed, and the judge found every changed item's root
  moved: 90 items in the journey, whose comparisons held 2,554 roots of
  which 132 changed. A typed frame changed about two of its 32 roots. Three
  gaps remain: a data-graphics model edited in place, which applications
  rebind instead; Desk's shell model, for 9b; and pictures, which carry no
  facts yet. Normal mode is unchanged. See the
  [evidence](../../local_testing/evidence/frames-follow-change-part9a1-20261028.md).
- **9a.2. A document's families captured into scratch.** The snapshot
  adapter captures chosen families of one shown document into a caller's
  scratch, through the capture words and work spans the snapshot uses, and
  records the facts of the roots it captured, without publishing anything.
  Lowering one root alone comes with the change driver (9a.3), since 9b
  changes where the items go. **Done** on 2026-10-28: `RUHA-CAPTURE-FAMILIES`.
  A family captured into scratch is the snapshot's slice byte for byte, and
  its facts are the facts pass's. Within a family every root is captured;
  capturing one root of several is left for later. Nothing on the frame's
  path calls it yet.
- **9b. One record of the frame.** Desk's chrome comes from the shell model
  through the same projection, as one candidate. The shell's second
  candidate, its work space and its frozen banks go. Before 9b the
  producer planned runs for its own one-region candidate and admitted it,
  and in Desk that candidate was never sent: the shell planned the runs
  again for each region and admitted its batch, which was. Yet about ten
  things in Desk's paths read the producer's runs or admission: the family
  strips, the request for terminal space, the owner's sizing, the
  candidate's currency and identity frontier, the comparison's fence, and
  the next frame's reuse of runs. In three steps, each sending what it sent
  before:
  - **9b.1. One admission and one set of runs.** With the shell installed,
    the producer no longer plans runs for its own candidate or admits it.
    Each reader moves to the batch or to the candidate itself: the request
    for space follows the batch's admission; the fixed check and the
    identity frontier read the candidate; the shell takes the rows to plan
    again and the Z of the candidate's region from the producer; and the
    producer's comparison matches the applications' items without pairing
    runs or needing a fence of its own. The producer plans and admits its
    own candidate only before the owner opens, which that admission sizes,
    and when the shell cannot build its batch: the candidate built alone is
    cut down family by family, as one going out alone is, and offered to
    the shell again, and goes out alone if the shell still cannot build.
    The family strips thus still follow the producer's own admission until
    the producer builds the batch itself (9b.3).
    Estimated saving: about 1.6 million steps of a typed letter's frame.
    **Done** on 2026-10-28 (4cdfcbd3, d423d746, e840181f). The first runs
    found that the producer's admission had also grown the engine's working
    storage, refused a control the shell's DELTA cannot carry, asked the
    terminal for space inside a DELTA, and refused draws while nothing was
    shown; the DELTA path now does the first three itself, and the
    empty-frame state builds alone. A typed letter's burst frame builds in
    7.78 million steps against 9.63, sending the same 18 DELTAs and bytes.
    Desk with each of the ten applications and the canonical journey passed
    with the shadow check. Against the same runs before 9b.1, with the hash
    seed pinned for the two whose frames vary between runs, they sent the
    same presents but for one START that File Explorer overtook before
    showing it, which reads as timing. See the
    [evidence](../../local_testing/evidence/frames-follow-change-part9b1-20261028.md).
  - **9b.2. One bank.** The batch freezes into the producer's bank, beside
    the controls, keys and input targets the producer keeps, and the
    shell's own banks go. The shell's part of the frame, its batch with the
    model copy, taskbar correlations and actions and pane membership a
    click on the chrome reads, goes into one of two extension blocks the
    producer owns, and the pending bank names it; from then on it is
    published, sealed, kept and retired with the bank, so pairing the two
    records, the shell's roles for its banks and its seals go. The blocks
    lie outside the arena, whose layout fixes the banks' size, and grow to
    what a part needs and half again, as the shell's banks did. The shell
    keeps its work space until 9b.3.
    **Done** on 2026-10-28 (9852b10a, ceabef49). The shell freezes its part
    into the extension block the frame on screen does not name, and the
    pending bank names it; the shell's roles, banks, seals and pairing
    checks are gone, and with every check on the bank's seal covers the
    part. A typed letter's frame builds in the same 7.78 million steps and
    sends the same 18 DELTAs and bytes. Desk with each of the ten
    applications and the canonical journey passed with the shadow check,
    sending the presents 9b.1's runs sent. The blocks came to the banks'
    size less the smaller header's share; in File Explorer, Desk's memory
    source held 88 bytes less. The journey in safe mode found that since
    9b.1 the shell had handed the planner an empty glyph plan that still
    named the producer's old banks, which every check refuses, so the shell
    refused each frame of Desk's until the producer had built it alone, and
    Desk stopped a minute in. ceabef49 gives the planner no banks then, and
    the journey passed in safe mode with no damage named. See the
    [evidence](../../local_testing/evidence/frames-follow-change-part9b2-20261028.md).
  - **9b.3. One build.** The producer builds the batch itself, calling the
    shell's model, region and chrome words; the shell's work space, its
    second copy of every item and its own comparison go, and the
    producer's comparison covers the whole batch. The two number items in
    different orders today: the producer numbers its instruments, statics
    and runs straight after the applications' controls, and the shell,
    whose own controls must follow those, moves the statics and
    instruments up past them as it copies them, while its regions and
    panes are numbered after the producer's instrument regions and
    statics. Building once needs one order, so 9b.3 goes in four steps
    (decision 16), each showing the frames it showed before:
    - **9b.3.1. The shell plans first.** Once the producer has lowered the
      applications' controls, the shell takes its model and plans Desk's
      layout: panes, taskbar, prompt, notice and status, and which pane
      each document lies in. The producer numbers its instruments,
      statics and runs after the shell's controls, so every item carries
      the identity the batch sends, and the shell numbers its regions and
      panes once the producer's instrument regions and statics are known.
      The shell stops moving identities.
    - **9b.3.2. The applications' items once.** The producer packs the
      applications' controls, statics, instruments and series in the
      batch's shape, each in its pane's content region with its text
      dense in item order, and the batch's families for them name the
      pending bank's arrays; the shell's copies go. The producer's
      comparison and a click read the same arrays.
    - **9b.3.3. The producer builds the batch.** The producer writes the
      catalog and the shell's chrome families into the extension block
      through the shell's region and chrome words, plans each region's
      runs in its own glyph banks, which sit unused while the shell is
      installed, and admits the batch. The shell's build, its freeze and
      its work space go.
    - **9b.3.4. One comparison.** The producer's comparison covers the
      whole batch: the catalog, the shell's controls, panes and status,
      and the runs slot by slot. The shell's mapping of a DELTA onto the
      acknowledged part goes, and the DELTA goes out from the producer's
      comparison.
- **9a.3. The change driver.** When only roots' contents changed, and
  nothing about the documents' places or the shell model did, the driver
  captures and lowers the changed roots into scratch, takes each item's
  identity from the frame on screen, checks the changed items, plans glyph
  runs for the damaged rows once, and sends the changes as the DELTA. The
  pending record is a copy of the acknowledged one with the changes written
  in, so the next frame and every click read it as they read a built one.
  Any other frame goes to the full driver.
- **9a.4. RUHA's banks go.** The full driver captures into scratch too,
  sized to one build. The full refresh lowers what it captures and compares
  the items with those on screen.
- **9c. The rest of the DELTA.** The other changes the terminal accepts in
  a DELTA go through the change driver as well, such as controls that come
  or go within what a DELTA may carry. The whole-screen comparison remains
  for the full driver alone.

**Proof.** The change driver passes over an element only when none of the
counters it keeps for that element has moved. A capture reads only the
element's state, its widget's state, and the document's geometry,
visibility, focus and occlusion. Each is counted by its owner on every
change (parts 2 and 5) or compared directly, once 9a.1 has closed the gaps
listed above, so equal counters give an equal capture. Lowering an equal
capture with the same region geometry, claims and negotiated features gives
equal items, and the projection compares geometry, claims and features
itself. The shadow check compares the two drivers on every frame of every
test, and the full refresh finds in ordinary sessions what a missed count
left stale.

**Effect.** A typed letter's frame build, 9.63 million steps at the start
of this part, falls toward the target of about 2 million, an estimate each
slice replaces with measurement. RUHA's banks, 19.1 MiB, and the shell's
work space are freed. The shell's banks become the screen producer's
extension blocks, of about the same size, since the frame on screen needs its
record.

## Part 10. Today's structure retires — cleanup

Once the change driver passes the typing run, Desk with every application
and the full Desktop journey with the shadow check, and safe mode passes the
same journeys, the structures part 9 replaced are removed. Nothing is kept
for compatibility. The full driver remains the one full path.

## Memory

On the canonical Desktop at 280 × 84 the producer holds about 19 MB from
Desk's memory source, 13.5 MB of it its arena, and the shell about 5 MB: two
237 KB banks and a 4.4 MB work space (`final-guest-diagnostics.json`,
2026-10-18). With one application, in part 0, the producer held 14.3 to
15.4 MiB and the shell 4.2 to 4.4 MiB. The rich Desktop machine has 384 MiB
of external memory, and about 178 MiB of its general partition is free once
the system and Desk have loaded (`akashic_tui.py`). RUHA's banks are fixed
by Desk when it starts, at 19.1 MiB, and its snapshots used 12 to 40 KiB of
them in part 0's runs.

Part 9 frees RUHA's banks (9a) and the shell's work space (9b.3). 9b.2
moved the shell's two banks into the screen producer's extension blocks,
which grow by the banks' rule from a part 40 bytes smaller; in the canonical
journey each came to 236,536 bytes. Part 9 also adds the projection's record
of what each element last projected, sized from the elements on the screen,
and the pending change set, sized from one frame's changes. Captures go into
scratch, which grows to what one build needs; a full build's captures came
to 12 to 40 KiB in part 0's runs. Every block grows from Desk's memory
source to what the screen needs and half again, as the engine's does. Each
part reports what it adds or frees.

## Order and checks

The parts run in their numbered order. Parts 3 and 4 need no change counts,
so they come straight after part 2. Part 6 follows part 5 directly
(decision 2), and part 7 follows both because it changes the same paint
pass. Part 6b follows part 6 (decision 11), and part 7 ends with three
fixes part 6 found (decision 12).

| Part | Content | State |
| --- | --- | --- |
| 0 | Measure the changed frames now | done |
| 1 | A shadow check of every shortcut | done |
| 2 | Widgets count their changes | done |
| 3 | Checks run when they can find something | done |
| 4 | Safe mode | done |
| 5 | UIDL sees its widgets' changes and counts its own | done |
| 6 | Applications stop bridging change | done |
| 6b | A document handed to Pad opens before Desk paints | done |
| 7 | A repaint fills each cell once, then three faults part 6 found | done |
| 8 | The occasional full refresh | done |
| 9 | One projection, two drivers, in slices 9a.1 to 9c | under way |
| 10 | Today's structure retires | proposed |

For each slice:

- unit and byte-oracle tests, with the shadow check on;
- guest steps a key and wire operations a key from the typing run, before
  and after;
- Desk with Pad, and with each application the slice touches;
- the refactor ratchet, since every slice changes Forth state.

At the end of each part, the full Desktop journey runs once with the shadow
check on and once without it, as regression, one run at a time under the
existing guards. From part 4 on, a part that changes safe mode or the full
path also runs the journey once in safe mode.

## Expected effect

Millions of steps in a typed letter's burst frame, from the check
measurement, whose frame build of 16.16 million matches part 0's 16.13
million. During part 2 the same frame build took 15.4 to 16.7 million,
most of the difference in handover proofs that memory layout made split.
The figures after part 3 were measured at 5baf027d; those after part 9 are
estimates.

| | Today | After part 3 | After part 9 |
| --- | ---: | ---: | ---: |
| Checks | 9.85 | 3.48 | about 0.2 |
| Building, copying and comparing | 6.28 | 6.08 | about 2 |
| Fit | 0.03 | 0.05 | 0.03 |
| Frame build | 16.16 | 9.62 | about 2 |

Part 4 left normal mode as it was: at its end the frame build took 9.63
million. Part 3 was estimated to leave 1.9 million of checks and left 3.48. The
engine's admission of the shell's batch, the glyph planner's bounds on its
writes, UIDL-TUI's rechecks of its relations, and the public admissions'
and captures' proofs of the spans they are given stayed, for the reasons in
its evidence. After part 3, the item checks still visit every item on every
frame. Part 9 makes them follow change.

Steps a frame also count Desk's painting and the terminal service, about 3
million together. A typed letter repaints one row, so part 7 changes little
here; its gain is in frames that repaint whole documents.

## Not in this design

- **More kinds of DELTA.** About 40% of the canonical journey's changed
  frames still go out as STARTs: a refocused task or Desk's status
  appearing, the first frame after storage grows, pictures that appear,
  and pictures that move or clip while scrolling, changed instruments, and
  changes in control or dialog membership. Most need the terminal to accept
  more kinds of change in a DELTA. The full driver builds each START, so a
  START gains from part 3 but keeps a whole-screen build, emission and
  identities.
- **Applications' own work,** such as a Worlds step's repaint, or Sound Lab's
  render and its CELL waveform.
- **The CELL flush:** the changed cells' path through the CELL layers, 51 to
  488 million steps over part 0's runs. It needs its own design.
- **The simulator host's work:** decoding, composition and the viewer.
- **A text area capturing only its changed lines,** and the STX1 item patch
  on the wire that would carry them.
- **Bound state marking its elements by itself.** UIDL's contract keeps the
  application's `UIDL-DIRTY!` after it changes bound state.

## Decisions

Taken on 2026-10-19:

1. **The shadow check.** It is a committed switch, off by default, that
   tests and diagnostic runs turn on, so it also runs under the physical
   launcher, which refuses uncommitted sources (part 1).
2. **When applications stop bridging.** Part 6 follows part 5 directly, so
   the design violation is fixed in full before parts 7 to 10 change the
   paint pass and the frame build.

Taken on 2026-10-25:

3. **How the frame follows change.** Through one projection with a change
   driver and a full driver, and one candidate (part 9). Safe mode, the
   full refresh and the shadow check use the full driver. Parts 3 and 4
   come straight after part 2.
4. **Where checks run.** The table in part 3 replaces the rule that every
   boundary check stays at every boundary. Normal sessions then stop
   noticing a bug that writes into the rich path's memory between handovers,
   and safe mode keeps those checks. Tests run in normal mode too, except
   the tests of the checks normal mode skips, which turn every-frame checks
   on.
5. **Part 2's tests and containers.** The per-widget tests cover the
   widgets something uses: list, tree, tabs, text area, input, prompt,
   dialog, picture, text grid, field, data graphics, explorer and canvas,
   and the media widget and document view, which File Explorer's preview
   and Pad's file sidebar use. UIDL moves its reads of widget fields behind
   the widgets' own words within part 2, so that the structural test covers
   UIDL too. A widget that shows others counts their changes in its own
   revision, rather than UIDL reading the inner widgets' revisions beside
   it.

6. **How safe mode turns on** (part 4). All three ways: a key in Desk's
   configuration file that nothing inside Desk can change, a boot option,
   and an anomaly, by itself. Desk then says that it is in safe mode, and
   records why.
7. **The refresh interval** (part 8). A full refresh once input has been
   quiet for one second, and at least one every five seconds while the
   screen is shown. Both are settings.

Taken on 2026-10-26:

8. **What the projection keeps** (part 9). Only the revisions each element
   last projected and the wire items they became, with content captured
   into scratch when it changes, in every mode. A renderer-neutral copy of
   each element's content would cost memory and give no current renderer
   anything it reads; safe mode builds every frame from live state, so it
   would not read one either.
9. **What safe mode trusts of the frame on screen** (part 4). Its record is
   sealed. In safe mode the record of a frame takes a hardware CRC when the
   frame is sent, and the CRC is checked before the next DELTA or click uses
   the record. A record that no longer matches is damage: the frame goes
   out whole. When safe mode turns on during a session, the record of the
   frame on screen has no seal, so the next frame goes out whole as well.
10. **Where the configuration key lives** (part 4). On a small volume of
    Desk's system settings, which KDOS mounts read-only and only the host
    changes, by rebuilding or editing the image. MegaPad takes a second,
    write-protected disk for it.

Taken on 2026-10-27:

11. **The frame a handoff to Pad never shows** (part 6b). It goes, after
    part 6. Part 5's runs found it: Desk focuses Pad while handling the
    sender's input and opens the document at its next tick, so the input's
    paint usually sends a START that the next draw overtakes before it is
    shown.
12. **Three faults part 6 found** (part 7). They are fixed at the end of
    part 7: opening a dialog asks for no paint, the Agent's account panel
    stays on screen under its prompt, and File Explorer sends STARTs the
    terminal never shows.
13. **A document's loading frames** (part 7). They stay. After a tab
    switch, File Explorer's document view reads the document, makes each
    figure's picture file and decodes it, a bounded slice a service pass,
    and each slice that changes the view paints. Each such frame goes out
    as a START, since a change that brings a picture goes out whole, and
    the next slice's frame often overtakes it before the terminal's answer
    is read: five, five and nine STARTs in part 7's three runs of Desk
    with File Explorer. They are the document's real stages, text before
    pictures, and a quicker answer from the terminal shows more of them.
    Holding a document's frames until its slices finish would hide that
    progress on every link. Each costs a whole START only because a change
    that brings a picture goes out whole, which more kinds of DELTA,
    outside this design, would change.
14. **How the full refresh checks** (part 8). It checks without drawing:
    at a moment when no paint is pending, it captures every visible
    document in full and compares the capture with the snapshot the screen
    was built from, and sends nothing unless they differ. Riding a draw, as
    part 8 first planned, would have sent a frame at every refresh, since
    every draw sends one. Comparing a full build with the frame on screen
    also cannot tell a missed change from a counted one not yet sent, so
    such a refresh would have run the shadow check's comparisons beside an
    ordinary build, about two builds a refresh. The check costs one capture.
    It does not check the producers' reuse of screen rows again, which the
    shadow check covers in tests. Of decision 3, the refresh keeps the full
    driver's capture alone.

Taken on 2026-10-28:

15. **The order of part 9's slices.** One record of the frame comes before
    the change driver: 9a.1, 9a.2, 9b, 9a.3, 9a.4, 9c. In Desk the frame on
    the wire is the shell's batch, while the producer's bank is the record
    that clicks on an application's controls, and the next DELTA, read. A
    change driver built before 9b would have had to write both records and
    send its changes in the shell's identities, and 9b would then have
    removed that half of it. 9b also removes the second admission, the
    second glyph planning and the second copy and comparison of every item,
    an estimated 2 to 3 million of a typed letter's 9.63 million steps, on
    STARTs as well as DELTAs.
16. **How 9b.3 goes.** In full, before the change driver, in the four steps
    above. A smaller 9b.3 would only have moved the shell's glyph slots
    into the producer's unused glyph banks, freeing about 4 MB, and left
    one copy of each item and one comparison to part 10. It would have
    reached the change driver sooner, but the driver would then have
    written each change into both copies, and part 10 would have removed
    that half of it.
