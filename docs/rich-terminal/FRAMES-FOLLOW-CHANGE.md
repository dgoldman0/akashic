# A frame's work follows what changed — design, 2026-10-19

Status: proposed on 2026-10-19. Its four decisions were taken the same day
(see Decisions). Each part is approved on its own. Part 0 is done. After
it, part 9 and the adapter's growing banks in part 5 were added the same
day. Part 1 was done on 2026-10-24.

Earlier work: [KEYSTROKE-FRAME-WORK.md](KEYSTROKE-FRAME-WORK.md)
(2026-10-14, all seven parts done),
[PER-KEY-FRAME-REPEATS.md](PER-KEY-FRAME-REPEATS.md) (2026-09-28) and
part 10 of the [rich experience plan](RICH-EXPERIENCE-PLAN.md)
(2026-10-11). KEYSTROKE-FRAME-WORK ends: "Going further than that needs the
snapshot itself to follow change." This design is that step.

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

This design adds change counters where change happens, in the canonical
widgets and in UIDL's elements, and carries them through each stage of the
frame build. Each stage rebuilds only what its inputs' counters say changed
and takes everything else from its own last result. Applications stop
bridging change: a widget's change reaches UIDL, CELL and the rich path by
itself.

**Target:** a typed letter's frame build falls from about 16 million steps,
part 0's baseline, to about 6 million or fewer. Frames
that change more, such as an application switch or a dialog opening, gain
less, because more of their inputs change.

Part 0 found two more things this design takes on. Outside typing, painting
the CELL screen costs about as much as building the rich frame, and a third
to over half of that painting fills backgrounds that were just filled; part
9 stops it. And the adapter's banks are fixed at 19.1 MiB while its
snapshots use tens of KiB; part 5 makes them grow on demand.

## Rules

Kept from earlier work:

- Remove only work that is provably repeated. The proof comes from the module
  that owns the data. A check is never skipped on another module's word, and
  a digest is not a proof.
- The terminal receives exactly the frames and operations the full path would
  send.
- Every boundary check stays. Each item that crosses a boundary is checked
  there, directly or because it is byte for byte what that boundary already
  checked and kept.
- Storage is sized from what the screen and content need now, and grows on
  demand. Nothing reserves a guessed maximum.
- Everything stays renderer-neutral and below the applet layer. CELL stays
  complete.

New:

- **Rebuilding and checking are separate.** A stage may skip rebuilding an
  item when the counters of all its inputs are unchanged. Each counter
  belongs to its input's owner: a widget's to the widget, an element's to
  UIDL, a row's to the screen. Skipping a rebuild never skips a check. The
  item still crosses every boundary, and every boundary still checks it.
- **A missed change gives a stale screen, not an unsafe one.** If an owner
  fails to move a counter, the screen shows old content, but every frame is
  still checked in full at every boundary. The shadow check (part 1) exists to
  find such misses, and it is on in every test of this work.
- **Applications do not report change to the rich path.** The counters live
  in canonical widgets and UIDL. Applications go on changing their state
  through the ordinary widget and UIDL words. Where a widget shows data it
  borrows from the application, such as a list's rows, the widget's own
  ordinary word says that the data changed, as `TREE-REFRESH` does today.
  CELL needs that word as much as the rich path does.

## Where change is known today

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

How applications bridge today:

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
used 12 to 40 KiB; part 5 now makes them grow on demand. Outside typing,
Desk's painting costs about as much as the frame build, and a third to over
half of it is repeated background fills, which part 9 now removes. The CELL
flush outside the producer took 51 to 488 million steps over a run, which
this design leaves out.

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
  syncs go through the base words.
- Input's revision already means this, so it becomes the base revision. The
  other existing revisions keep their narrower meanings.
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

**Tests.**

- For every canonical widget: each public word that changes it moves the
  revision, and the widget then draws exactly what a fresh widget in the same
  state draws; each query and capture moves nothing.
- A structural test fails when a module outside a widget's file reads or
  writes that widget's fields by offset.

## Part 3. UIDL sees its widgets' changes and counts its own — design, fixes a violation

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

## Part 4. Applications stop bridging change — cleanup

After parts 2 and 3, each application loses the code that only carries
widget changes to UIDL:

- Pad: the paint-time dirty check and row redraw, the key routing around
  UIDL, and the copied text area offsets.
- File Explorer: its dirty helpers.
- Grid, Sound Lab, Worlds, Observatory, Daybook, the Agent, Library and
  Streams: each invalidate helper shrinks to what the application's own
  state needs.
- Desk's launcher, sandbox and schedule surfaces: their row-count tests and
  refresh flags give way to the list's own word for changed rows, so the
  launcher also shows a change of content at the same count.

Each application is checked with its own tests and Desk with that
application. This part follows part 3 directly, so the design violation is
fixed in full before the parts that make frames cheaper.

## Part 5. The snapshot recaptures only what changed — repeat, with memory

**Today.**

- Projection marks a document's record dirty whenever its application
  finishes a draw (`_RUHA-PROJECT`, `uidl-hybrid-adapter.f:1392-1407`),
  whether or not anything changed.
- A dirty record is recaptured whole, all six families
  (`_RUHA-B-CAPTURE-CURRENT`, 2668).
- A clean record's prior slices are validated in depth, every family
  (`_RUHA-B-PRIOR-ENTRY?`, 2017), then moved into the inactive bank and
  rebased.
- The snapshot exports one aggregate content epoch, which moves on every key,
  and each document's menu epochs. It does not say which documents or
  families it recaptured.
- The producer captures pictures for every visible document on every build
  (`RUHA-PICTURES@`, 3510).
- Desk gives RUHA fixed banks when it starts, sized from the most documents,
  UIDL elements and text it could hold (`desk-apt1.f:229-305`): 19.1 MiB,
  of which part 0's snapshots used 12 to 40 KiB. The producer, the engine
  and the shell instead grow from Desk's memory source as the screen needs.

**Change.**

- For every element it captures, RUHA keeps the counters of everything the
  capture reads: the element's revision, its widget's revision, the mounted
  source's generation, and the document's geometry, visibility, focus and
  occlusion.
- A family slice none of whose elements' counters moved is copied, with its
  offsets rebased into the new banks. A family with a changed element is
  recaptured whole. Recapturing single elements inside a family, and copying
  the rest, is a later step, taken only if part 0 or this part's measurement
  shows that a family's other elements cost much.
- RUHA's banks become its own and grow from Desk's memory source, as the
  shell's do (SHELL-SCREEN-PRODUCER). Each starts small. When a capture runs
  out of room in a bank, RUHA takes a block for what was needed and half
  again and captures once more, until the snapshot fits or the memory source
  says no. Only the inactive bank grows, and nothing reads it, so nothing is
  relocated. Desk no longer sizes them.
- RUHA's active bank is then its own copy of what it last captured or
  copied, from Desk's memory source, as the engine keeps what it admitted
  (KEYSTROKE-FRAME-WORK part 5): only RUHA writes it, and nothing writes it
  while it is active. Reused slices are copied from it, and their deep
  re-validation stops, since no caller holds the banks any more.
- The snapshot exports a revision for each document's family slice, which
  moves whenever RUHA recaptures it. Part 6 lowers again only the slices whose
  revisions moved.
- Pictures are captured again only when a picture widget's revision or place
  moved.

**Proof.** A capture reads only the element's state, its widget's state, and
the document's geometry, visibility, focus and occlusion. Each is counted by
its owner on every change (parts 2 and 3) or compared directly, so equal
counters give an equal capture. Only RUHA writes its banks: the inactive one
while it captures, from the active one or from live widgets, and neither
while it is active. The storage proofs keep every other span apart from
them. The shadow check confirms the equality on every frame of every test.

**Effect.** Most of the snapshot's 3.78 million steps a typing frame:
only the families holding the edited text area and the status line are
captured, and no slice is validated in depth. RUHA's memory falls from 19.1
MiB to what its two banks need, tens of KiB in part 0's runs.

## Part 6. The producer lowers only what changed — repeat

**Today.** On every frame the producer:

- copies the whole aggregate into its arena;
- lowers every text area, text grid, item view, document and tab set again,
  with the aggregate epoch as its revision, and builds every field, dialog,
  instrument, series and status field again. Only menus are copied from the
  acknowledged bank, when their epochs match;
- has the engine admit every item. Controls and glyph runs equal to the
  engine's kept copy skip their record and text checks; fields, dialogs,
  instruments, series and status fields are checked in full every frame;
- counts everything again and builds an input target for every control;
- compares every control and every glyph slot with the acknowledged bank,
  including the runs of rows that `ROW-DAMAGE` leaves unmarked, which it
  copied from that same bank.

**Change.**

- A family slice whose revision did not move is not lowered again. Its
  controls, instruments, series and status fields, with their input targets,
  are copied from the producer's acknowledged bank. Menus do this today with
  their epochs; every family does it now.
- The engine's kept copy extends to fields, dialogs, instruments, series and
  status fields. An item equal to what the engine last admitted skips the
  checks that read only what was compared, as controls and glyph runs do
  today.
- The comparison takes as equal every item the producer copied from the
  acknowledged bank, and every run of a row `ROW-DAMAGE` leaves unmarked. It
  compares the rest as today.

**Proof.** Lowering reads only the slice, the region geometry, the claims and
the features the terminal negotiated, apart from the content revision, which
the comparison already sets to the acknowledged one for an unchanged body
(KEYSTROKE-FRAME-WORK part 1). The producer compares geometry, claims and
features itself, and takes the slice's revision from its owner, RUHA. The
copied items come from the producer's own acknowledged bank. The engine's skips
rest on KEYSTROKE-FRAME-WORK part 5's proof, unchanged: only the engine
writes its copy, from items it has just checked in full.

**Effect.** Most of the candidate's 3.56 million steps, the target pack's
0.42 million and the comparison's 1.60 million in a typing frame.

## Part 7. The shell builds only what changed — repeat

**Today.** On every DELTA frame, after the producer, the shell:

- compares the whole shell model with the acknowledged one twice, at
  CURRENT and at DELTA-PROBE;
- copies and validates the shell model, plans the catalog and the panes'
  membership, and builds every family again: the applications' controls,
  copied from the producer's pending bank, then series, instruments, status
  fields, panes and residual glyphs, reusing unchanged rows' runs one at a
  time;
- admits the whole batch (`RTE-FAMILY-BATCH-PREFLIGHT`). Controls and glyph
  runs use the kept copy; instruments, status fields, series and panes are
  checked in full;
- freezes it: measures it, copies it deep into a bank and checks the bank in
  full;
- emits the difference, skipping glyph families equal to the acknowledged
  ones.

**Change.**

- When DELTA-PROBE has passed and a region's catalog row equals the
  acknowledged one, each of that region's families whose inputs are
  unchanged is copied from the shell's active bank: applications'
  controls the producer carried unchanged (part 6), and glyph families whose
  rows `ROW-DAMAGE` leaves unmarked. Only the other families are built.
- The family preflight's kept copy extends to instruments, status fields,
  series and panes.
- The freeze checks in full only the families it built. A copied family is
  byte for byte one the shell checked when it froze its active bank.
- The emitter skips every family the shell copied, as it already skips equal
  glyph families.

**Proof.** The shell's active bank is its own, checked in full when it was
frozen, and a bank that ACTIVE names is never written again
(SHELL-SCREEN-PRODUCER). Which inputs are unchanged comes from their owners:
the producer for the items it carried, the screen for `ROW-DAMAGE`, and the
shell's own model comparison.

**Effect.** Most of the shell's batch, freeze and emission, 5.51 million
steps a typing frame.

## Part 8. What the call tree still shows — repeat, exact speed-up

After parts 5 to 7, a call tree of the typing run and the applications' runs,
as in KEYSTROKE-FRAME-WORK part 6, decides this part. Each item is taken with
its own proof, and the review approves it once measured. Known now:

- RUHA validates its header and proves its storage, and every document's, at
  each entry: at projection, in the snapshot's preflight, and in each of the
  shell's six dispatches a frame, which also prove the shell's own storage.
  In part 0 the adapter's checks took 1.62 million steps a typing frame and
  the shell's checks at each dispatch 1.24 million. Where nothing can move
  storage between two proofs in one frame, the later proof repeats the
  earlier one.
- The snapshot's preflight runs before its check for a draw already
  captured, so a repeated call for the same draw proves everything again.
- Unchanged rows' runs are copied one at a time, about 0.7 million steps a
  frame across both producers; whole rows can be copied at once.
- The residual planner checks every claim and span once a call, ten to
  fourteen calls a frame; one call a region saves about 0.25 million.
- With the shell installed, the producer's own candidate is admitted although
  only the shell's batch is sent unless the shell refuses. Whether that
  admission can wait until the base candidate is needed needs its own look.

## Part 9. A repaint fills each cell once — exact speed-up

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
simulator and the chip alike. Parts 2 to 4 cut how often whole documents
repaint; this part cuts what each repaint costs.

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

This design changes:

- RUHA's banks fall from 19.1 MiB, fixed, to what its snapshots need,
  growing on demand: tens of KiB in part 0's runs. Its active bank serves as
  its copy, so it keeps no other (part 5);
- the engine's and the family preflight's copies grow to cover fields,
  dialogs, instruments, series, status fields and panes, a small share of
  what they keep for controls and glyph runs today.

The producer and the shell copy from banks they already keep. Every bank
and copy grows from Desk's memory source to what the screen needs and half
again, as the engine's does. Each part reports what it adds or frees.

## Order and checks

| Slice | Content | Approval | State |
| --- | --- | --- | --- |
| 1 | Part 0 | this review | done |
| 2 | Part 1 | this review | done |
| 3 | Part 2 | this review | proposed |
| 4 | Part 3 | this review | proposed |
| 5 | Part 4 | this review | proposed |
| 6 | Part 9, which changes the same paint pass as parts 3 and 4 | this review | proposed |
| 7 | Part 5 | this review | proposed |
| 8 | Part 6 | this review | proposed |
| 9 | Part 7 | this review | proposed |
| 10 | Part 8 | its own, once the call tree is in | proposed |

For each slice:

- unit and byte-oracle tests, with the shadow check on;
- guest steps a key and wire operations a key from the typing run, before
  and after;
- Desk with Pad, and with each application the slice touches;
- the refactor ratchet, since every slice changes Forth state;
- at the end, the full Desktop journey once with the shadow check on and
  once without it, as regression, one run at a time under the existing
  guards.

## Expected effect

Estimates against part 0's measurement of a burst typing frame. The
adapter's checks (1.62M) and the storage-aliasing checks (3.82M) run inside
these rows.

| Stage | Part 0, 2026-10-19 | After this design (estimate) |
| --- | ---: | ---: |
| Documents' snapshot | 3.78M | about 1.0M |
| Producer's candidate, with the engine's admission and its glyphs | 3.56M | about 1.3M |
| Target pack | 0.42M | about 0.1M |
| Comparison | 1.60M | about 0.3M |
| Shell's batch, with its preflight and glyphs | 3.74M | about 1.3M |
| Shell's freeze and emission | 1.77M | about 0.4M |
| Shell's checks at each dispatch | 1.24M | 1.24M, less after part 8 |
| Frame build | 16.13M | about 5.6M |

Steps a frame also count Desk's painting and the terminal service, about 3
million together. A typed letter repaints one row, so part 9 changes little
here; its gain is in frames that repaint whole documents.

## Not in this design

- **More kinds of DELTA.** About 40% of the canonical journey's changed
  frames still go out as STARTs: a refocused task or Desk's status
  appearing, the first frame after storage grows, pictures that move or clip
  while scrolling, changed instruments, and changes in control or dialog
  membership. Most need the terminal to accept more kinds of change in a
  DELTA. A START can still gain from parts 5 and 6, since its unchanged
  documents are neither recaptured nor lowered again, but its emission and
  identities stay whole-screen.
- **Applications' own work,** such as a Worlds step's repaint, or Sound Lab's
  render and its CELL waveform.
- **The CELL flush:** the changed cells' path through the CELL layers, 51 to
  488 million steps over part 0's runs. It needs its own design.
- **The simulator host's work:** decoding, composition and the viewer.
- **One candidate instead of two.** The producer's and the shell's stages
  stay separate; this design makes both follow change.
- **A text area capturing only its changed lines,** and the STX1 item patch
  on the wire that would carry them.
- **Bound state marking its elements by itself.** UIDL's contract keeps the
  application's `UIDL-DIRTY!` after it changes bound state.

## Decisions

Taken on 2026-10-19:

1. **How fine the snapshot reuses.** Counters are kept per widget and per
   UIDL element. The snapshot reuses whole family slices first, and single
   elements inside a family only if measurement shows it pays (part 5).
2. **RUHA's own copy.** RUHA keeps its own copy of what it captured, in a
   block from Desk's memory source, and stops validating reused slices in
   depth, as the engine does with what it admitted (part 5).
3. **The shadow check.** It is a committed switch, off by default, that
   tests and diagnostic runs turn on, so it also runs under the physical
   launcher, which refuses uncommitted sources (part 1).
4. **When applications stop bridging.** Part 4 follows part 3 directly, so
   the design violation is fixed in full first.
