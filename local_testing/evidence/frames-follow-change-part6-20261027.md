# Part 6: Applications stop bridging change — 2026-10-27

Part 6 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
removes the code applications kept only to carry their widgets' changes to
UIDL. Since part 5, a widget changed anywhere asks for a paint and repaints
its element, so the marks and shell calls that did that by hand had nothing
left to do. Pad went further: its editor was a composite panel that UIDL
could not see into, and it is now the canonical tab strip and text area,
each mounted on its own region, so a typed character redraws its row
through the text area's partial draw with no code of Pad's in between.

This note records the commits, what stays and why, what was found on the
way, the tests, the physical runs after each slice and at the end of the
part, and two diagnostic runs that compared frames before and after a
slice. All of it is simulator evidence. None of it is UART, panel or touch
evidence. Steps are the simulator's semantic steps.

## What changed

| Commit | Change |
| --- | --- |
| 2ece3986 | Pad's editor area holds two regions placed by absolute positioning: `editor-tabs`, two rows, carries the `TAB` widget, and `editor-text` the shared text area. An element authored `focusable=false` never takes focus, by a press or by Tab, while a press still reaches its widget, so a press on a tab leaves the keys with the text. `TXTA-ON-CARET!` names a word the text area tells when an event moves its caret or selection; the descriptor grows to 232 bytes and the registered handler keeps its name. Pad's panel, caret overlay, paint-time check, key routing and all 30 `ASHELL-DIRTY!`, 11 `WDG-DIRTY` and 3 `UIDL-DIRTY!` calls go; the status bar under its prompt is marked with `UIDL-MARK!`. |
| fd761ec4 | A partial drawer declines a widget that does not draw as its kind does, since applets give their panels numbers canonical kinds use. The text area's drawer checks the draw word first. |
| 1ec7b320 | File Explorer's element helpers and its 14 `ASHELL-DIRTY!` calls go; the status bar under its prompt is marked with `UIDL-MARK!`. |
| ba102832 | Grid, Sound Lab, Worlds, Observatory, Daybook, the Agent, Library and Streams: each invalidate helper keeps its panel's `WDG-DIRTY`, rebuild hooks and status update and drops its element marks and shell call; showing a prompt calls no shell; the status bar under each prompt is marked with `UIDL-MARK!`, the Agent's where its prompt closes. |
| b330a58e | Desk's launcher, sandbox inspector and schedule screens tell their lists when rows change (`LST-COUNT`, `LST-REFRESH`, `LST-RECOUNT`), in place of row-count copies and refresh flags, and Desk refreshes the launcher's rows when it opens a catalog entry or an applet closes. |

Pad's editor is mounted rather than kept as a panel that counts its
children's changes because such a panel could not draw a typed row alone:
its type number has no partial drawer, and the partial-drawer table follows
the canonical kinds, so an applet's own drawer has no place in it.

## What stays, and why

- **The panels' own `WDG-DIRTY`.** Eight applets draw their body through a
  composite panel whose widgets UIDL cannot see, so each counts their
  changes in the panel's revision. That is the applet's own state.
- **Marks over cells an applet draws itself.** Each applet that paints a
  prompt over its status bar marks the status bar once the prompt closes.
  `UIDL-MARK!` repaints without counting a change, so the status bar's
  revision stays.
- **The Agent's `ASHELL-DIRTY!` after it opens a review dialog** from its
  tick. Opening a dialog counts no change: `_DLG-OPEN` only names the dialog
  the host paints. Inside Desk that call marks no slot either; the dialog
  shows because the runtime revision that brings the review also
  invalidates the panel in the same tick.
- **Daybook's tick touches its instance** when its automations change.
  Drawing no longer needs the touch, since the panel's change has Desk draw
  it, but the touch moves the instance revision that the request bus and
  resource references check. Whether it stays belongs to the shared-document
  design.
- **Desk's own `ASHELL-DIRTY!` calls.** Desk is the root shell and paints
  its own chrome and overlays.

## Found on the way

- **Type numbers are not a kind's alone** (fd761ec4). Observatory's panel
  carries 29, the media kind's, and Daybook's, Worlds' and Library's panels
  carry 30, the document kind's. Neither kind registers a drawer yet and no
  widget outside the text area carries its 23, so nothing reached a wrong
  drawer; the rule and the text area's check come before more kinds
  register drawers. The test now gives a foreign widget bytes that read as a
  typed row: with the check taken out, the text area's drawer draws it.
- **Opening a dialog asks for no paint**, found by reading `dialog.f` and
  the host. A dialog opened from a key shows because the host marks the
  slot of any key an applet handled. One opened from a tick shows only if
  something else in that tick asks for a paint.
- **The Agent's sign-in panel** draws over the body's whole rectangle from
  the paint callback. When the Agent's prompt opens it hides the panel, and
  by the code nothing repaints the body underneath; no run has shown it.
  That predates part 6.
- **File Explorer's journey sends ten STARTs it never shows**, 222,683
  bytes, at part 5's code and at slice 2's alike: after one key (54,302
  bytes), three document scrolls (about 19 KB each) and two tab switches
  that show pictures (two and four STARTs of about 18.7 KB). Each is staged
  and then overtaken by a newer draw before the terminal reveals it.
- **`test_streams_burrow_caps.py` holds no pytest tests**, as in part 5's
  runs, and pytest says so with exit status 5.

## Left for later

The dialog that asks for no paint, the sign-in panel's underlay, and File
Explorer's unshown STARTs are recorded above, not fixed: the next steps of
the plan do not depend on them. Daybook's touches wait on the
shared-document design. Most of Desk's painting in a typed letter is now
Desk's own frame, which part 9b takes into the projection (see Typing).

## Tests

Each slice ran the test files that load or name what it changed, one file at
a time or in one sequential process, with `TMPDIR` in `/dev/shm`.

- **Slice 1 (Pad).** 87 files. All passed once the widget revision tests
  placed `TXTA-ON-CARET!` among the words that move no revision. New:
  `test_uidl_mounted_editor.py`, four tests of the editor's layout, typing,
  the caret word and `focusable=false`. The first commit's tree alone passed
  82 tests in seven files.
- **Slice 2 (File Explorer).** 362 tests in six files, `test_tui.py` limited
  to the guard-wrapper scan that reads File Explorer.
- **Slice 3 (panel applets).** 21 files and the functional ledger's check;
  20 hold tests, all passing.
  `test_soundlab_prompt_restore.py` now also checks that the status bar's
  revision stays when the prompt closes.
- **Slice 4 (Desk's lists).** 476 tests in 11 files. New: opening a catalog
  entry refreshes the launcher's rows.

Not run: the emulator tests the selections named, 18 for slice 1, one for
slice 2, twelve for slice 3 and three for slice 4, among them
`test_observatory_worlds_slice.py`, whose stubs slice 3 trimmed after
reading the two sources it compiles; and
`test_desk_library_burrow_capstone.py`, a script with no pytest tests whose
product mode runs a 30-billion-step journey. Only Desk's emulator smokes draw the
sandbox and schedule screens, so their drawing after slice 4 is unchecked.

## Bindings

Every run bound clean trees. Each slice's runs bound its commit: Pad's
fd761ec4 (tree `ceea23408577271b7ac349c63d860d06a7ac0758`), File Explorer's
and the pictures' 1ec7b320 (tree `ab585cf2849fa8b8af1ec07aaf23eaf8517cb577`),
the panel applets' ba102832 (tree `1703a99234a757cf50ae321d37368ca92d715ae5`),
and the end of the part b330a58e (tree
`b8b1d957124149783f014538d2692917bc05c5a6`). The diagnostic runs' base was
8ca825f6 (tree `411379e072a9a0141310127f4b80bf4f0bbe4b4a`), from a RAM clone; its code is part 5's end. This
note is committed after them.

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
aggregate-RSS stop, with the shadow check and an unpinned hash seed, as in
part 5. Every run passed, and the shadow check found no difference and
skipped no comparison. Comparisons and the presents committed, as DELTAs,
STARTs, continuations and empty presents:

| Applet | Part 5 | Part 6 | Run at |
| --- | --- | --- | --- |
| Pad | 437; 10, 6, 6, 1 | 437; 10, 6, 6, 1 | fd761ec4 |
| Small terminal | 158; 2, 4, 4, 4 | 158; 2, 4, 4, 4 | fd761ec4 |
| Daybook | 427; 9, 8, 8, 1 | 427; 9, 8, 8, 1 | fd761ec4, ba102832 |
| File Explorer | 1,595; 18, 54, 45, 1 | 1,609; 18, 55, 45, 1 | 1ec7b320 |
| Photo | 79; 1, 3, 3, 1 | 79; 1, 3, 3, 1 | 1ec7b320 |
| Damaged picture | 191; 3, 4, 4, 1 | 191; 3, 4, 4, 1 | 1ec7b320 |
| Streams | 266; 3, 8, 7, 1 and 244; 3, 7, 6, 1 | 266; 3, 8, 7, 1 | ba102832 |
| Agent | 905; 15, 21, 14, 1 and 918; 15, 22, 14, 1 | 905; 15, 22, 15, 1 | ba102832 |
| Sound Lab | 170; 3, 4, 4, 1 and 192; 3, 4, 4, 1 | 170; 3, 4, 4, 1 | ba102832 |
| Observatory | 226; 0, 8, 7, 1 | 201; 0, 8, 8, 1 | ba102832 |

Part 5's column gives its last run of each applet, at 7607b145 for File
Explorer, photo and damaged picture and at 51e2fadf for the rest, and both
of its runs where they differed. Pad, the small terminal, Daybook and the
picture runs committed the same frames as part 5. Streams, the Agent and
Sound Lab vary between runs of the same code, as part 5 found. File
Explorer's one extra START and Observatory's START that is now shown are
timing, as the diagnostics below show. At b330a58e, after slice 4, Desk
with File Explorer, whose journey opens the launcher and opens a row from
it, committed 1,609; 18, 55, 45, 1 again.

## Typing

The typing run with `--screen-profile`, every call chain kept and
`PYTHONHASHSEED=0`, in normal mode, at fd761ec4. Millions of steps:

| | Part 5 (51e2fadf) | Part 6 (fd761ec4) |
| --- | ---: | ---: |
| Isolated character, all steps | 20.14 | 20.33 |
| Its frame build | 18.28 | 18.28 |
| Burst frames | 15 | 18 |
| A burst frame's build | 9.64 | 9.68 |
| A burst frame's checks | 3.53 | 3.45 |
| Desk's painting a burst frame | 1.04 | 0.80 |

A typed letter now goes through UIDL's dispatch to the text area and through
the text area's partial drawer: over the burst, `TXTA-DRAW-ROWS` ran under
`WDG-DRAW-CHANGED?` and the text area never drew whole. The tab strip drew
once, on the first key, when the buffer's label gained its mark of unsaved
changes. Each of the 18 keys had its own frame, where part 5's run folded 18
keys into 15; Desk's painting over the burst fell from 15.6 to 14.4 million
steps.

Pad's own paint is now a small part of that. Of the burst's 14.4 million
steps of Desk's painting, UIDL's paint of Pad (`AHOST-PAINT`) took 1.18
million; Desk's own frame took the rest: completing the shell's draw
(`AHOST-SHELL-DRAW-COMPLETE`) 6.03 million, the dividers 3.41 million, the
taskbar 2.36 million and the shell's begin 1.44 million. Part 9b takes
Desk's chrome into the projection. The frame build itself, which part 6 does
not touch, is unchanged. The isolated character took 20.33 million steps
in all, against 20.14 to 20.31 million in the three runs part 5's table
records, with the same frame build of 18.28 million.

## File Explorer's extra START

The slice 2 run of Desk with File Explorer committed 55 STARTs against part
5's 54 and the same 45 continuations, so the extra START was never shown.
Two runs compared the code before and after
slice 2 under the same conditions: Desk with File Explorer, without the
shadow check, with the screen profile and `PYTHONHASHSEED=0`, at part 5's
code (8ca825f6, from a RAM clone) and at 1ec7b320. They took 124.6 and
120.9 seconds. Both committed 18 DELTAs, 54 STARTs, 44 continuations and an
empty present, with the same DELTA refusals, and every one of the 54 input
windows committed the same presents, mode, bytes and cells alike. Slice 2
changed none of File Explorer's frames; the shadow run's extra START is its
timing. The same runs show the ten STARTs never shown recorded above.

## Observatory's START

The slice 3 run of Desk with Observatory committed 8 STARTs, all shown, and
201 comparisons, where both of part 5's runs committed 8 STARTs with one
never shown and 226 comparisons. Two runs with the shadow check, the screen
profile and `PYTHONHASHSEED=0`, at part 5's code and at ba102832, took 34.3
and 34.4 seconds and matched exactly: 226 comparisons with no difference, 9
STARTs, 8 continuations and an empty present, the same refusals, and the
same presents in each of the nine input windows, the seventh with one START
overtaken. Slice 3 changed none of Observatory's frames; in the slice 3 run
that overtaking did not happen.

## The canonical Desktop journey

Across Desk, Pad, Daybook, Sound Lab and File Explorer, at b330a58e, with
the presents it committed:

| Run | Time | Comparisons | DELTAs | STARTs | Continuations |
| --- | ---: | ---: | ---: | ---: | ---: |
| with the shadow check | 191.1 s | 4,692 | 52 | 39 | 36 |
| without it | 174.4 s | — | 52 | 39 | 36 |
| without it, with `--screen-profile` and `PYTHONHASHSEED=0` | 175.9 s | — | 52 | 39 | 36 |

Every run passed, the shadow check found no difference and skipped no
comparison, and each run also committed one empty present and the same
DELTA refusals. The shadow run made 4,692 comparisons, as parts 1 to 4's
did; part 5's end runs made 4,621 with 37 STARTs and committed 38 without
the check. Part 5 traced that to a START Desk sends but never shows where
Pad opens a document, which the order of a key's paint and Desk's tick
decides; here all three runs sent it at both handoffs, as part 5's profiled
runs did.

The profiled run, made as part 5's profiled runs were, with 100 call
chains of 16 words kept an interval, matches them at both handoffs to the
byte. At stage 10, where Daybook hands its task to Pad, it sent a START of
121,952 bytes that was never shown, then one of 122,530 bytes and its
CONTINUE of 233 cells; at stage 40, where File Explorer opens the renamed
file in Pad, 166,198 and 169,723 bytes and 1,755 cells. Each came a little
sooner after its input than in part 5's runs: at 0.32, 1.08 and 1.40
seconds at stage 10, against 0.33–0.36, 1.11–1.18 and 1.43–1.56, and at
0.49, 1.50 and 1.94 seconds at stage 40, against 0.51–0.52, 1.54–1.55 and
1.98–2.08. The input windows of the two handoffs took 94.5 and 126.5
million guest steps. This run is part 6b's starting point.

The runs took less time than part 5's, which took 246.3 and 206.9 seconds.
The journey's time is mostly its scripted pauses, boot and the host, so
this note draws no conclusion from it.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clones of part 5's tree, except the profiled journey's,
which part 6b compares with. By their shells' `write_bytes`, none of the 20
physical runs wrote to the drive.
