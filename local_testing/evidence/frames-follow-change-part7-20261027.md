# Part 7: A repaint fills each cell once — 2026-10-27

Part 7 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
makes a fill leave alone the rows that already hold what it writes, and
then fixes three faults part 6 found. The fill is in cb62b4a8 and
919dcb7d, the three fixes in 41b03497, 76435b62 and 95a4b849. This note
records the commits, the tests, and the physical runs that compare the code
before and after. All of it is simulator evidence. None of it is UART,
panel or touch evidence. Steps are the simulator's semantic steps.

## The fill

Every UIDL container fills its rectangle before its children paint, and
many widgets and applets fill their own areas the same way. `DRW-FILL-RECT`
drew such a rectangle a row at a time through `DRW-HLINE`, each row in a
borrow of the back plane of its own and each cell through the plane writer.

| Commit | Change |
| --- | --- |
| 81934a5a | The plan schedules the three faults part 6 found for the end of this part (decision 12). |
| cb62b4a8 | A fill takes one borrow of the back plane for its whole rectangle. For a narrow character it checks each row's cells, residue and provenance with block compares, and leaves alone a row that already holds what it would write. Every row still counts as touched. |
| 919dcb7d | A row that differs is stored whole with block stores when no cell it replaces is half of a wide pair; one over half of a pair goes through `DRW-HLINE` with a touched interval of its own. |

The second commit came out of the first's measurements. On Desk with Pad,
Daybook and Sound Lab, cb62b4a8 cut the fills by 23% with Pad and 17% with
Daybook and made Sound Lab's 8% dearer, frames unchanged in all three.
Most of what fills cost was rows that differ: a region repaints over what
its mounted widget drew there, and a root over the previous frame. Those
rows still paid the plane writer for every cell. Inside the one borrow,
each of their cells after the interval's first row also took the slow
path of the touched-row bookkeeping, which cost more than the borrows the
change saved. Storing a row whole removes both costs.

**Why it is exact.** A row is left alone only when the plane writer would
store, cell by cell, exactly the bytes it holds: the cells, the residue
outside a replacement layer and the provenance all match, and since every
cell then equals the narrow fill cell, none is half of a pair and the
writer would take its direct path. A row is stored whole only when no cell
it replaces, in the cells or, outside a replacement layer, the residue, is
half of a pair, so the writer would again take its direct path in every
column and repair no neighbour. The stores then write what it would: the
cell across the span, the same into the residue, marked changed when it
held anything else, and the writer's provenance. Every row of the
rectangle is touched, so the dirty flag, the touched rows and the retry
plan's invalidation come out as before, and so does the damage plan a
flush computes from them.

**Costs on the chip and the simulator.** On the chip COMPARE is the BCOMP
instruction, at up to 2N+2 cycles for N bytes, MOVE the CMOVE instruction
at 2N+2, and FILL the BFILL instruction at N+2. In the simulator each is
one host primitive, so a row checked or stored costs the simulator less,
next to the rest of the paint, than it costs the chip. Steps here are the
simulator's.

## Tests

`test_draw_fill_rows.py` runs the real screen and draw sources on small
guest screens, 14 by 7, in the Python and the native simulators, and keeps
the fill this part replaced as its reference.

- **The fill against the reference.** From 96 seeded states it runs both
  fills from the same state and compares every plane and flag the screen
  keeps (front, back, residue, accepted residue, provenance, touched rows,
  damage, residue damage, dirty, force, flush request, the two draw
  generations and the residue's dirty flag), the retry plan's validity,
  and the damage plan and counts a flush makes from them. The states come
  from earlier fills of the same cell, text with wide characters and
  clusters, overlays, replacement layers and committed frames, and in a
  quarter of the cases arbitrary bytes and broken pairs. Fills use spaces,
  a printable, wide characters, a combining mark, NUL and DEL, under no
  clip, clips with origins, and an origin left behind with no clip. Each
  case first fills the same cells as a parent container would. The seeds
  reach every kind of row the fill meets: rows left alone, rows left alone
  over another residue inside a replacement layer, rows stored whole with
  the cells, the residue or the provenance differing, rows written cell by
  cell over half of a pair, and fills it does not check.
- **The work.** A repeated fill takes under a quarter of the old fill's
  steps, a rectangle whose rows all differ under a third, and one changed
  cell rewrites one row; the rows left alone still count as touched.
- **Documents.** Four seeded documents of nested containers, with inherited
  and own styles, clipped children that reach past their parents, layers,
  and labels with wide characters and clusters, are painted both ways for
  four frames each, the same document, again, changed and again. After
  each paint and each flush the screens match, and their ANSI output
  matches byte for byte. With 919dcb7d's stores, repainting an unchanged
  document took 32% of the old fill's steps, 131,270 against 415,748, in
  both simulators; with cb62b4a8's alone, 57%.
- **Controls.** With the residue check or the provenance check taken out,
  rows left alone untouched, the residue mark, the pair check or the
  residue store taken out of a stored row, or a row's touched interval not
  joined to the fill's, the tests fail.

At cb62b4a8 the 101 test files that load draw.f or name the fill ran one at
a time with `TMPDIR` in `/dev/shm` and passed, 2,725 tests; `test_tui.py`
ran whole and peaked at 3.5 GiB. At 919dcb7d the fill test, the screen,
draw, UIDL paint, widget, Desk and shell producer suites, `test_tui.py` and
the inventory test passed, 394 tests in 13 files. Not run: the 17 emulator
smoke scripts among the files that load draw.f, as for every part since
part 5.

## Fills and painting

The native simulator at 280 by 84, one run at a time after an uncapped
wait for other heavy runs, under the 900-second watchdog and the 3.5 GiB
aggregate-RSS stop. Each before and after pair ran with the shadow check,
the screen profile, every call chain kept and `PYTHONHASHSEED=0`, the
before side at part 6b's end (ab3bab49) and the after side at cb62b4a8 or
919dcb7d, each from a RAM clone. Every run passed, and the shadow check
found no difference and skipped no comparison. None wrote to the drive.
Millions of steps over each run; fills are the steps under
`DRW-FILL-RECT`, of which UIDL's background fills are those under
`_UTUI-FILL-BG`:

| Desk with | Code | All steps | Desk's painting | Fills | UIDL's background fills | Frame build |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Pad | ab3bab49 | 593.7 | 156.6 | 94.6 | 82.5 | 251.9 |
| | cb62b4a8 | 571.6 | 135.2 | 72.7 | 62.3 | 251.9 |
| | 919dcb7d | 506.2 | 68.9 | 6.8 | 6.1 | 252.1 |
| Daybook | ab3bab49 | 646.1 | 155.1 | 137.4 | 53.9 | 191.4 |
| | cb62b4a8 | 622.0 | 131.4 | 113.7 | 59.4 | 191.7 |
| | 919dcb7d | 516.8 | 26.5 | 8.8 | 4.3 | 191.6 |
| Sound Lab | ab3bab49 | 352.2 | 83.0 | 62.3 | 30.0 | 105.1 |
| | cb62b4a8 | 357.4 | 88.5 | 67.6 | 33.1 | 104.9 |
| | 919dcb7d | 295.8 | 25.6 | 5.0 | 2.4 | 105.1 |
| Observatory | ab3bab49 | 390.7 | 62.3 | 56.3 | 27.3 | 153.8 |
| | 919dcb7d | 340.5 | 11.5 | 5.4 | 2.6 | 153.9 |
| File Explorer | ab3bab49 | 2,484.7 | 812.1 | 738.4 | 458.2 | 816.5 |
| | 919dcb7d | 1,770.1 | 105.1 | 34.0 | 29.8 | 783.2 |

With the stores, fills fell by 90 to 95% in every run, and Desk's painting
by 56% with Pad, 83% with Daybook, 69% with Sound Lab, 82% with
Observatory and 87% with File Explorer. In Pad's run at cb62b4a8 the
nested split's fills went from 19.1 million to 0.13 million of checks; the
region and root fills that remained were rows a widget or the previous
frame had drawn, written cell by cell. What painting is left is mostly
the widgets' own drawing and Desk's chrome.

Desk with the small terminal, the photo, the damaged picture, Streams and
the Agent ran at 919dcb7d with the shadow check and an unpinned seed:
158, 79, 191, 244 and 932 comparisons, no difference and none skipped.
Streams and the Agent vary from run to run, as parts 5 and 6 found.

## Typing

`physical_typing_cadence.py run --screen-profile`, every call chain kept,
`PYTHONHASHSEED=0`, normal mode. Millions of steps:

| | ab3bab49 | cb62b4a8 | 919dcb7d |
| --- | ---: | ---: | ---: |
| Whole run | 456.9 | 450.9 | 429.1 |
| Desk's painting over the run | 48.7 | 42.7 | 21.8 |
| Fills over the run | 29.6 | 23.7 | 2.7 |
| Frame build over the run | 192.7 | 192.7 | 192.6 |
| Isolated character, all steps | 20.33 | 20.33 | 20.27 |
| Its Desk painting | 0.92 | 0.92 | 0.79 |
| Burst frames | 18 | 18 | 18 |
| A burst frame's build | 9.58 | 9.69 | 9.68 |
| A burst frame's Desk painting | 0.79 | 0.79 | 0.74 |

The three runs sent the same presents, 322,912 bytes. A typed letter
repaints one row, as the plan expected, so most of the typing run's gain
is in its other paints. The burst frame's build rose by 0.1 million while
the whole run's frame build differs by 65,572 steps, 0.03%: the profile
charges steps in tenths of a second, and the after runs painted sooner, so
the burst's window took in a different part of the frame after it.

After the three fixes, at 95a4b849, the same typing run sent the same
presents, 322,912 bytes, and took 428.0 million steps against 919dcb7d's
429.1. The held check runs on every shell pass, and typing does not show
its cost. The isolated character's frame build stayed at 18.35 million and
its Desk painting at 0.79 million. Its window counted 20.40 million steps
against 20.27, about one idle tenth of a second's steps (0.14 million),
which the longer window, 0.41 seconds against 0.38, takes in. A burst frame
took 11.31 million against 11.34, with its build at 9.67 million.

## Frames compared window by window

Each pair's presents compared window by window, from one input to the
next: mode, bytes and cells. Pad committed the same presents in all 13
windows at both commits, Daybook in all 13, Sound Lab in all 5 and
Observatory in all 9.

File Explorer committed the same presents in 49 of its 54 windows. The
other five end on the same presents and differ only in the frames before
them. Once a paint took a seventh of the steps, stepped work and new input
overtook frames at other moments: windows 25 and 31 sent one and two
STARTs fewer, window 6 one more, and windows 41 and 42 split one tab
switch's work differently. The run sent 116 presents against 118, and nine
STARTs never shown in each. Those differences are timing: the fill writes
what it wrote before, for the reasons above and by the tests, the other
four pairs committed the same presents in every window, and the shadow
check found no difference.

## Opening a dialog asks for its paint

`_DLG-OPEN` made a dialog the one its application shows, and the host
paints that dialog over the application, but nothing asked for the pass
that paints it. A dialog opened from a key showed, because the host marks
the slot of any key an application handled. One opened from a tick, a bus
request or a service pass showed only when something else in the same
pass asked for a paint. The Agent's review dialog, which its tick opens,
showed because the runtime revision that brings the review also counted a
change to the Agent's panel; the Agent's own `ASHELL-DIRTY!` after opening
it marked no slot inside Desk.

41b03497 has opening a dialog move the dialog's revision, so the widget
change hook asks for a paint pass, as it does for any widget's change, and
in Desk the applet host turns the request into the child's slot. A dialog
opened while a paint runs asks for none, since the host paints an
application's dialog after the application's own painting. The Agent's
`ASHELL-DIRTY!` goes. `test_dialog_contexts.py` checks that asking a dialog
asks for a paint pass and that asking during a paint asks for none; the
first check fails with the old `_DLG-OPEN`.

At 95a4b849, Desk with the Agent, whose run opens the review dialog twice
and approves each review, passed with the shadow check: 672 comparisons, no
difference, none skipped. So did Desk with Pad, which asks before closing
a document, with 407, and Desk with Daybook, which asks before deleting,
with 367.

## The Agent's account panel under its prompt

Part 6 found this fault by reading the code. No run had shown it, since no
journey opens the account panel and then the prompt. The Agent draws its
account panel over its body from its paint callback, and its own panel
draws only its background while the account panel or the run settings
show. Opening the prompt, the credential prompt or the scheduled runs hides
both, but hiding them counted no change to the panel, so nothing repainted
the body, and the account panel's cells stayed on screen until something
else repainted it.

76435b62 has `_AG-HIDE-OVERLAYS` count a change to the panel when an
overlay showed, and UIDL repaints the body as it repaints the element of
any widget whose revision moves. When none shows, the word changes nothing,
as before, since hiding a hidden widget changes nothing.
`test_agent_overlays.py` runs the Agent's own words in the native
simulator on a state block of its own, with widget headers in the
overlays' places: hiding a shown account panel or run settings moves the
panel's revision, and hiding when none shows does not. With the old word
the test fails. Desk with the Agent shows and closes the run settings and
passed, as above; no run opens the prompt over the account panel, so only
the test shows the repaint.

## File Explorer's STARTs the terminal never showed

A START stages a hidden replacement. Once the terminal has answered it,
the producer reveals it with a CONTINUE if no newer draw has completed;
otherwise it builds a START from the newer draw, and the first is never
shown. The runs of Desk with File Explorer at ab3bab49 and 919dcb7d each
sent nine such STARTs, and part 6's runs ten. Read with the profile, window
by window, they have three causes:

| Cause | Windows | Never shown at ab3bab49 | At 919dcb7d | At 95a4b849 |
| --- | --- | ---: | ---: | ---: |
| A scroll's detents, painted one at a time | 23, 24, 25 | 4, 75,796 bytes | 3, 56,749 bytes | 0 |
| A document's loading in slices after a tab switch | 31, 41 | 5, 92,907 bytes | 5, 92,913 bytes | 9, 167,783 bytes |
| A notice's expiry just as the next key arrives | 6 | 0 | 1, 32,135 bytes | 1, 32,135 bytes |

**A scroll's detents.** The journey scrolls a document with one control
event of three wheel detents. The APT-1 owner gives each detent as an
ordinary wheel step, a poll each, and the shell polls one event a pass and
paints at the end of it. Each detent's paint built a START, since a
document whose figure moves goes out whole, and the next detent's paint
overtook it.

95a4b849 gives the shell's terminal owner interface a `held` callback,
true while the owner holds the rest of an input event it has received,
which its next polls give. While it is true, a pass takes the next step
and runs its posted actions, service and tick as before, but does not
paint; the pass that takes the last step paints the event whole. APT-1
reports the rest of a text or pointer event: a text's further characters,
a press's further buttons, a scroll's further detents or a drag's motion.
`test_app_shell_idle.py` runs the shell's loop over an owner holding an
event of three steps: three passes take them, one paints and none sleeps
before the last, and with the check taken out it paints three times.
`test_app_shell_apt1_field_input.py` checks that APT-1 holds the rest of a
scroll of three detents after its first two polls and nothing after the
third.

**A document's loading in slices.** A tab switch shows a document with
figures. Its view reads the part it needs, makes each figure's picture
file and decodes it, one bounded slice a service pass, so that input stays
answered while a large document loads. Each slice that changes what the
view shows asks for a paint, and each paint sends a START, since a change
that brings a picture goes out whole. The next slice's paint often
overtakes it. These frames are the document's real stages, text before
pictures. A stage is shown only when the terminal's answer to its START is
read before the next slice changes the view, so a quicker answer, from a
faster link or terminal, would show more of them, and a slower link fewer.
They stay, decided on 2026-10-27 (decision 13). Each costs a whole START
only because a change that brings a picture goes out whole, which more
kinds of DELTA, outside this design, would change.

**A notice's expiry.** Window 5's Enter raises File Explorer's "Path not
found" notice. As window 6's key arrives, the notice's time runs out, and
Desk's repaint without it sends a START, which the key's frame overtakes.
Two changes that happen to fall together; there is nothing to remove.

**At 95a4b849.** Desk with File Explorer ran again with the shadow check,
the screen profile, every call chain kept and `PYTHONHASHSEED=0`, and
passed: 1,519 comparisons, no difference, none skipped. Each of the three
scrolls sent one START and its CONTINUE, and none went unshown. Each
scroll's window took 20.6 to 22.6 million steps where it took 35.8 to
38.1, and its frame was on screen 0.27 to 0.32 seconds after the input
instead of 0.60 to 0.71. The two texts the run types, which APT-1 gives as
pastes, now paint once each: one DELTA instead of two, and 14.0 and 14.9
million steps instead of 27.4 and 33.2. The other 47 of the 54 windows
committed the same presents as at 919dcb7d.

The run still sent ten STARTs it never showed, 199,918 bytes: one at the
notice's expiry in window 6, as at 919dcb7d, and nine in the two tab
switches' loading, four in window 31 and five in window 41. The same
windows overtook four and one at ab3bab49, and two and three at 919dcb7d.
A tab's activation is one pointer event, so nothing is held there and the
shell paints as before. How many of a document's stages are overtaken
follows the race between its slices and the terminal's answers, which
falls differently from run to run.

## The three fixes' tests

The three fixes' test selection, 84 files of dialog, app shell, Desk,
UIDL, widget and rich producer tests, ran one file at a time on their
combined tree before they were committed, with `TMPDIR` in `/dev/shm`:
2,510 tests passed, and the one failure was the refactor ratchet's state
hash, which 95a4b849 records. On the tree of the first two fixes alone,
76435b62's, the ratchet passed with its recorded hash, and so did the
dialog, Agent and dialog-hosting tests. At 95a4b849 the ratchet and the
functional baseline passed. Not run: the 16 emulator smoke scripts in the
selection.

## The canonical Desktop journey

At 95a4b849 the canonical journey passed with the shadow check, 4,361
comparisons with no difference and none skipped, and without it. The
shadow run made fewer comparisons than part 6b's 4,621 because the journey
sends fewer frames: four of its texts now go out in one DELTA each.

The journey also ran with the screen profile, every call chain kept and
`PYTHONHASHSEED=0`, at part 6b's end (ab3bab49) and at 95a4b849, each from
a RAM clone. Millions of steps over each run:

| | ab3bab49 | 95a4b849 |
| --- | ---: | ---: |
| All steps | 3,762.0 | 3,478.8 |
| Desk's painting | 337.3 | 126.0 |
| Fills | 174.0 | 12.5 |
| UIDL's background fills | 102.6 | 7.9 |
| Frame build | 2,151.4 | 2,093.7 |

Both runs committed 37 STARTs and 36 CONTINUEs; the later one 48 DELTAs
against 52, and 6,368,915 bytes against 6,373,112. Sixty of the 79 input
windows committed the same presents. Four of the five texts the journey
types, in windows 23, 32, 52 and 76, went out in one DELTA instead of two,
each window taking 18.2 to 26.5 million steps where it took 35.0 to 59.6.
The fifth, in window 46, 61 bytes in five scripts, still went out in two
DELTAs: the guest received its characters in two batches with a paint
between, for a reason this part did not trace. It was whole on screen
0.67 seconds after its input instead of 1.40, in 43.6 million steps
instead of 75.0.

The other 14 windows, the list scrolls in windows 27 and 60 to 71 and the
Enter that finishes a rename in window 33, differ by up to eight cells. In
each, File Explorer's list shows the sizes of the disk image's
`source-NN.src` files, which hold each commit's own sources and so differ
between the runs. The retained text of every checkpoint is the same in
both runs except where that list shows those sizes, and every checkpoint
image that differs does so only in that column.

Both runs sent one START they never showed, 166,064 bytes, after File
Explorer's Delete key in window 34: the key's paint built it, and a paint
after a Desk tick, 1.2 seconds after the key, overtook it. It is the same
at both commits, and this part did not examine it.

From part 4 on, a part that changes safe mode or the full path also runs
the journey in safe mode. Part 7 changes neither, so no safe-mode journey
ran.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clones of the trees they ran. By their shells'
`write_bytes`, none of the part's 30 physical runs wrote to the drive.
