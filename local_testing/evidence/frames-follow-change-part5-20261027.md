# Part 5: UIDL sees its widgets' changes and counts its own — 2026-10-27

Part 5 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
makes UIDL count change where it owns it and see the changes its widgets
count. Each UIDL element now has a revision, which moves when the element
itself changes and not when it is only marked to paint again. For each
element that hosts a widget, UIDL keeps the widget's revision as it last
painted it, so a widget changed anywhere repaints its element with no word
from the application, and a key a widget consumed and counted marks nothing:
the widget's own revision and, where its kind has one, its partial draw
cover it. A typed character in a UIDL text area now redraws its row alone.

This note records the commits, the rules the revisions follow, the three
defects found on the way, what is left for parts 6 and 9, the tests, and the
physical runs after slice 2 and at the end of the part. All of it is
simulator evidence. None of it is UART, panel or touch evidence. Steps are
the simulator's semantic steps.

## What changed

| Commit | Change |
| --- | --- |
| d852aa27 | Element revisions. `UIDL-REVISION`, `UIDL-TOUCH` (count a change) and `UIDL-MARK!` (ask for a repaint); `UIDL-DIRTY!` is both. A revision is a stamp from one count every document and context shares and nothing resets, so a revision is never taken twice. uidl.f counts allocation, children linked or unlinked, attributes set or removed, and bound values written back; UIDL-TUI counts visibility and a menu's items, and its focus, layout, tabs, checked, widget and dispatch marks stay counted. The revisions are a new UCTX pool. |
| 823ef404 | Widget revisions drive the paint. UIDL keeps each hosted widget's revision as it last painted it, and the paint pass paints an element whose widget moved as if it were marked, a `<scroll>` around it first. Each widget revision move calls widget.f's change hook (`WDG-CHANGE-HOOK!`), which UIDL sets to ask for a paint; `UTUI-PAINTING` keeps a paint from asking for another, and the app shell runs its root and child paints under it. `AHOST-TICK` turns a request a child's tick raises into that child's slot. `UTUI-SERVICE` no longer marks a media element: its widget counts the change. |
| 51e2fadf | Consumed keys and partial draws. A key or pointer event a hosted widget consumed and counted marks nothing. Canonical widget kinds register partial drawers (`WDG-PARTIAL!`, `WDG-DRAW-CHANGED?`); the text area's draws the rows typing changed. A clean element in the normal flow whose widget moved tries the partial draw first, and paints whole when the drawer declines, under a `<scroll>`, or as an overlay. |
| 7607b145 | A defect fix, below: the rich side's picture claims ask for no paint of their own. |

The elements that host a widget are those whose renderer draws it: a
materialized input, text area, tree or media widget, and a widget mounted on
a region or group. A `<tabs>` keeps its active-tab state in the same sidecar
cell, which is no widget. The UCTX buffer grew by two 2,048-byte pools to
115,968 bytes.

## The rules the revisions follow

An element's revision moves when what its renderer shows or lays out from
changes: an attribute, its children, its bound value, its layout, its
visibility, its focus, its checked state, the widget attached to it, and an
application's `UIDL-DIRTY!`. A focus change counts each element up to the
nearest ancestor with a renderer of its own, since a container such as the
menubar paints its children's focus, and a menu that opens or closes counts
the menubar beside its own items. A repaint mark alone does not
move it: a dirty parent marking its children to paint over its background,
`UTUI-INVALIDATE`, a subtree or the rectangle an overlay left, and the
element whose widget changed. A widget's change is counted by the widget's
own revision, which UIDL reads beside the element's.

Over-counting is safe and under-counting is not: a revision that moves
without a change costs a consumer a rebuild, while one that stays through a
change would leave a stale screen once part 9 reads it. Where UIDL-TUI
already marked an element for a change it could not cheaply pin down, as a
relayout marks every element it lays out, the mark is counted.

## Defects found on the way

- **UIDL-MOVE-ELEM linked the new parent under the moved element**
  (d852aa27). It passed its arguments to the link word in the wrong order.
  Nothing calls it, and its test counted only the old parent's children, so
  it went unseen until the revision test checked both parents. It now links
  the element last under its new parent.
- **Part 4's settings documentation used renderer words in a neutral doc**
  (d852aa27). desk.md's System Settings section named the rich terminal,
  which the neutral Desk, UIDL-TUI, app-shell and applet-host docs must not
  (test_uidl_retained_architecture); part 4 had not run that test. Only the
  rich composition reads the settings, so the section moved to
  AKASHIC-RICH-TERMINAL.md as 9.1.
- **The rich side's picture claims asked for a paint from its own context**
  (7607b145). The canonical journey at 51e2fadf committed 41 STARTs where
  every run from part 1 to part 4 committed 39. A run of part 4's end
  (4c7cd482) from a RAM copy of the tree, compared stage by stage, put the
  two extra ones in File Explorer's document and picture previews. While it
  builds a frame, the rich side claims a picture it will show
  (`PICT-CLAIM!`) or notes one it could not send (`PICT-RICH-FAILED!`), and
  both move the picture's revision. Since 823ef404 that asked for a paint,
  from the rich side's own context, which repainted nothing of File
  Explorer's slot and still published a frame. The picture's CELL view
  follows at its next service pass or draw, as its words say, so the claim
  and the failure notes now run under `UTUI-PAINTING`. The preview stages
  then matched part 4's again.

The UCTX section header, two docs and a structure test also gave the context
size as 107,776 bytes, from before the attribute record grew to 48 bytes;
uidl-tui.md's word table had the true 111,872. All now give the new total.

## Left for later

- **Pad still bridges its editor** until part 6. Its editor is its own
  composite panel mounted on a region, whose revision does not follow the
  text area inside it, so UIDL sees no change when typing changes the text
  area. Pad's paint callback keeps redrawing the rows, and its key routing
  around UIDL stays; nothing is painted twice, since UIDL paints the panel
  only when the panel's own revision moves. Part 6 makes the panel count
  its inner widgets, or mounts the text area itself, and removes both.
- **The applications' invalidate helpers** stay until part 6. They mark
  their elements as before; the marks are counted changes, at worst a
  rebuild part 9 does not need.
- **The UIDL-TUI rechecks of mounted relations and resolved records**, about
  0.2 million steps a frame, stay. They run inside the captures, once per
  capture of a mounted collection, and part 9 stops capturing unchanged
  elements, which takes them with it with no cache of its own to prove.
- **Nothing reads the element revisions yet.** Part 9's projection will
  keep the revision each element last projected (decision 8).

## Tests

Each slice ran the Akashic test files that load or read UIDL or UIDL-TUI,
chosen by following the REQUIRE closure of every Forth module a test file
names, one file at a time with MegaPad on the path. The largest, test_tui,
peaked at 3.5 GiB.

| Slice | Files | Passed | Smoke scripts | Failed first, then passed as fixed |
| --- | ---: | ---: | ---: | --- |
| d852aa27 | 113 | 92 | 18 | the ratchet, the storage proof's structure test, and the architecture test, which pinned the UCTX layout and found the neutral-doc words |
| 823ef404 | 115 | 95 | 18 | the widget-privacy test (UIDL-TUI had set widget.f's private hook variable; widget.f gained `WDG-CHANGE-HOOK!`) and the media capture test, which expected the decoded picture to mark its element |
| 51e2fadf | 119 | 100 | 18 | test_widget_pointer's wheel test, which expected the scrolled list to mark its element and its scroll |
| 7607b145 | 8 | 8 | — | the picture-related files only |

The 18 smoke scripts are emulator smokes run as programs, not pytest files
(test_applet_host, test_applet_close, test_desk_host_characterization, the
AT/XRPC and Streams verticals, the Library L1 checks, test_explorer_transactions,
test_markup_progress, test_observatory_worlds_slice and others). They were
not run in this part; the applet host smoke's checked-in budget is three
billion steps.

New files: `test_uidl_revisions.py` (9 tests: fresh and unique revisions,
marks against changes, paint-only marks, an overlay's own revisions against
those under it, attributes, focus, layout, children, widgets, checked items,
menus, contexts and the UCTX layout); `test_uidl_widget_repaint.py` (5: a
widget changed outside dispatch repaints with no application code, a paint
asks for no paint, a scroll paints before its widget, the shells and the
host run under the scope, the rich side's picture claims ask for no paint);
`test_uidl_partial_paint.py` (5: a typed character redraws one row, a
change the drawer does not cover paints whole, a text area under a scroll
paints whole, a key a widget counts nothing for still marks its element,
the drawer table follows the canonical kinds).

## Bindings

Every run bound clean trees. The runs at the end of the part bound Akashic
51e2fadf (tree `87f3302c16726cef9b1779e6d134f80bb44e55bc`), and the runs after
the claim fix bound 7607b145 (tree `e7ef4a13fb9ca751009c0a15b21da5331104e214`). This note is committed after
them.

| Binding | Value |
| --- | --- |
| MegaPad | `1833d16f70322ee95a3a5404c323d4b8dfdf92dc` (tree `ed0550c17cb3f029838036cf95b980dcf4f92365`) |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |
| Typing harness SHA-256 | `618fb25dfb7c7925eb8ed93825be93e28e22d3565df4fa54ce4df3a5f6f82f1f` |
| Desktop launcher SHA-256 | `3a037906ed72cfa5ff7014d5328b184405b748c7db5066347f488bbe3bdace64` |

## Desk with each applet

The native simulator at 280 × 84, one run at a time, after an uncapped wait
for other heavy runs, under the 900-second watchdog and the 3.5 GiB
aggregate-RSS stop, with the shadow check. Every run passed, and the shadow
check found no difference and skipped no comparison. Comparisons and the
presents committed, as DELTAs, STARTs, continuations and empty presents:

| Applet | 823ef404 | 51e2fadf | 7607b145 |
| --- | --- | --- | --- |
| Pad | 437; 10, 6, 6, 1 | 437; 10, 6, 6, 1 | |
| File Explorer | 1,667; 18, 58, 45, 1 | 1,689; 18, 59, 45, 1 | 1,595; 18, 54, 45, 1 |
| Daybook | 427; 9, 8, 8, 1 | 427; 9, 8, 8, 1 | |
| Streams | 266; 3, 8, 7, 1 | 244; 3, 7, 6, 1 | |
| Agent | 905; 15, 21, 14, 1 | 918; 15, 22, 14, 1 | |
| Sound Lab | 170; 3, 4, 4, 1 | 192; 3, 4, 4, 1 | |
| Observatory | 226; 0, 8, 7, 1 | 226; 0, 8, 7, 1 | |
| Small terminal | 158; 2, 4, 4, 4 | 158; 2, 4, 4, 4 | |
| Photo | 88; 1, 3, 3, 1 | 88; 1, 3, 3, 1 | 79; 1, 3, 3, 1 |
| Damaged picture | 200; 3, 4, 4, 1 | 200; 3, 4, 4, 1 | 191; 3, 4, 4, 1 |

Desk with Pad committed the same frames as at part 4's end. The counts of
the applets driven by ticks or host time, Streams, Agent and Sound Lab, vary
between runs of the same code. File Explorer made four or five STARTs fewer
after the claim fix, and Photo and Damaged picture the same frames with
fewer comparisons.

## Typing

The typing run with `--screen-profile`, every call chain kept and
`PYTHONHASHSEED=0`, in normal mode. Millions of steps:

| | Part 4's end | 823ef404 | 51e2fadf |
| --- | ---: | ---: | ---: |
| Isolated character, all steps | 20.31 | 20.20 | 20.14 |
| Its frame build | 18.28 | 18.28 | 18.28 |
| Burst frames | 17 | 18 | 15 |
| A burst frame's build | 9.63 | 9.63 | 9.64 |
| A burst frame's checks | 3.51 | 3.52 | 3.53 |
| Desk's painting a burst frame | 0.92 | 0.88 | 1.04 |

A typed letter costs what it did at part 4's end. Pad still routes its
editor's keys and repaints the rows itself, so the paint UIDL does for a
typed letter has not changed; what part 5 adds to each paint, a look at
each hosted widget's revision, does not show at this resolution. The burst
made 15 frames in the last run, folding more keys into each, so its Desk
painting per frame rose while the burst's total, 15.6 million, stayed
part 4's.

## The canonical Desktop journey

Across Desk, Pad, Daybook, Sound Lab and File Explorer, with the presents it
committed:

| Code | Run | Time | Comparisons | DELTAs | STARTs | Continuations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 4c7cd482, part 4's end | without the shadow check | 224.6 s | — | 52 | 39 | 36 |
| 51e2fadf | with it | 260.9 s | 4,743 | 52 | 41 | 36 |
| 51e2fadf | without it | 221.3 s | — | 52 | 41 | 36 |
| 7607b145 | with it | 246.3 s | 4,621 | 52 | 37 | 36 |
| 7607b145 | without it | 206.9 s | — | 52 | 38 | 36 |

Every run passed, the shadow check found no difference, and each run also
committed one empty present. Part 4's end ran from a RAM copy of its tree,
to compare stage by stage; every run from part 1 to part 4 had committed 39
STARTs. At 51e2fadf the two extra STARTs were the claim defect above. On
the final code, stage 10, where Daybook hands its task to Pad, sent one
START fewer in both runs, and stage 40, where File Explorer opens the
renamed file in Pad, one fewer in one of them: in part 4 each sent a small
START before the full one. Both are stages where Pad opens a document and
takes focus, and the journey's checks of the new tab and its text pass in
every run. What makes the small START go is not traced.

## Files

The runs' output stayed in `/dev/shm` and was deleted after this note was
written, with the RAM copy of part 4's tree. By their shells' `write_bytes`,
the 30 physical runs wrote 237,568 bytes to the drive in all; 28 wrote
nothing.
