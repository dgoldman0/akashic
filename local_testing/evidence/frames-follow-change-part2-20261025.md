# Part 2: widgets count their changes — 2026-10-25

Part 2 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
gives every canonical widget a revision that moves whenever what the widget
shows changes, and makes UIDL read widgets only through their public words.
This note records the commits, what testing found, the tests, and the
physical runs with the shadow check on and off. The typing run's frames
cost more at the end of the part than at its start. Most of the extra
steps come from where storage lies in memory rather than from work part 2
added, and the last sections show how that was found.

All of this is simulator evidence. None of it is UART, panel or touch
evidence.

## What changed

| Commit | Change |
| --- | --- |
| 73147730 | The revision, in bits 16 to 63 of the flags cell. `WDG-DIRTY` and the base words that change a flag move it, and `WDG-FLAG!` sets one flag and marks only a real change. The input's own revision becomes the base revision. |
| 00d31ef8 | The words that changed what a widget shows without saying so now move its revision: the text area's selection, gap buffer, gutter and caret scroll, `TAB-ADD`, the menu's item words, the tree's and list's context, the picture's claim, the explorer's hidden-files switch, and each canvas drawing word, once a shape. |
| bc81322b | List and tree queries and captures answer from a scan of the rows and change nothing. The draws and the words that change the widget settle it. |
| 425f1170 | `LST-REFRESH`, for rows that changed in place at the same count. |
| 24a55dae | Public text area words for what Pad reached into its fields for: the caret, a range selection, the view, undo and redo, the gap buffer. Pad's copied offsets are gone. Sound Lab's panel header is built with `WDG-INIT`. |
| da5813c6 | The text area records the rows typing changed (`TXTA-CHANGED-ROWS`), and Pad repaints those rows from that record instead of its own judgement. The descriptor grows from 168 to 224 bytes. |
| 2bf926e8 | Pad keeps its editor's focus in step with one `WDG-FLAG!`, which moves nothing when the focus already agrees. |
| 3d274511 | UIDL reads widgets only through their public words. Each kind UIDL mounts has a public check that a widget is a genuine one of its kind, UIDL reads headers, buffers and regions through the widgets' words, and the dialog's host hooks are public. |
| a69d6c48 | The per-widget revision test, and two canvas fixes. |
| 944630df | A widget that shows others counts their changes in its own revision: the prompt, the explorer and the media widget. `PRM-SET-BOUNDS` given the bounds a prompt has changes nothing. The test adds the media widget and the document view. |

## What testing found

Fixed in part 2:

- **Paints that marked a change.** Since slice 1, `WDG-DIRTY` moves the
  revision. The dialog host's paint and the prompt's body draw called it
  only to force a draw, so every paint looked like a change, and for a shown
  prompt the rich path sent its field again on every frame (00d31ef8).
  `PRM-SET-BOUNDS` did the same with unchanged bounds; Desk and eight
  applications call it before each paint while a prompt is shown (944630df).
- **Pad's focus sync.** It cleared and set the editor's focus on every key
  and every paint, moving the revision twice with nothing changed, so the
  text area's typing record never matched the revision it had drawn and
  Pad drew the whole editor on every typed frame. In typing runs without a
  pinned seed, Desk's painting rose from 1.12 million steps a frame at
  36685e86 to 2.23 million at da5813c6. 2bf926e8 fixed it.
- **Containers.** The prompt's mask and wipe and the explorer's expand and
  collapse moved only the revision of the widget inside (944630df).
- **The canvas.** Its draw left one cell on the data stack for each cell of
  its region, and `CVS-TEXT` swapped the row and the column (a69d6c48).
  Both predate this work.

Left as they were, and recorded:

- The explorer's hidden-files switch marks the explorer, but its tree's
  walker never reads it, so names starting with a dot are never hidden.
- `scroll.f` and `split.f` are first drafts that nothing loads. `scroll.f`
  names a word before defining it, and `split.f`'s vertical recompute
  passes a region address as a width. `menu.f` is unused too; its change is
  small and tested.
- UIDL still writes region fields directly. `region.f` is not a widget.
- The explorer's rename frees its input from inside that input's submit
  callback. Nothing reads the input after the callback returns, so this is
  a hazard for later changes rather than a fault. It predates part 2.

## Tests

- New files: `test_widget_revision.py` (slice 1),
  `test_widget_change_words.py` (slices 2, 4, 5a and 5b),
  `test_widget_queries.py` (slice 3), `test_widget_private_words.py` (the
  structural test, 3 tests) and `test_widget_revisions.py` (30 tests).
- `test_widget_revisions.py` covers fifteen kinds: list, tree, tabs, text
  area, input, prompt, dialog, picture, text grid, field, data graphics,
  explorer, canvas, media and the document view. One widget of each kind
  takes every public word that changes what it shows, with a draw after
  each, and each word must move its revision. A second widget takes the same
  words with no draw between them and must then draw the same cells, so
  nothing an earlier draw left behind changes what a widget shows. Every
  word that only reads, captures or checks a widget must move nothing. A
  placement test holds each module's public words against the test's
  lists, so a word added later must be placed. A change word listed as
  moving nothing, a second widget given one more change, and undoing the
  prompt's count of its mask or the media widget's count of its view each
  make the test fail.
- `test_widget_private_words.py` fails when a module uses a private word
  of `widget.f` or a canonical widget module, except that canonical and game
  widgets, which implement widget kinds, fill and read the header. A probe
  module with a field read fails it.
- The 113-file batch, slice 2's 103 files and the ten added since, passed
  on a69d6c48: one file at a time, in 34 minutes, with 3.5 GiB the most any
  file used. After 944630df the 21 files that load the prompt, explorer or
  media widget passed again.

## Bindings

The end runs bound clean trees.

| Binding | Value |
| --- | --- |
| Akashic | `944630dfa657b0d5a470d5fbfb3af93c8857b3bb` (tree `a95725740e07feb27515fe4913f09a5c2875469e`) |
| MegaPad | `2faa96d882dbfd4a6ec300fac960681644f88cc2` (tree `331bfad08e3990cbc4de72c3bcd5d827d3279f6e`) |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |
| Typing harness SHA-256 | `e32511e0f4ecfab8182ad3299c5947f600027f340233763e49ae07f98e3b25f9` |

## Runs with the check on

The native simulator at 280 × 84, one run at a time, after an uncapped wait
for other heavy runs, under the 900-second watchdog and the 3.5 GiB
aggregate-RSS stop. Every run passed its journey and found no difference,
and none skipped a comparison.

After each slice, Desk ran with the applications the slice touches:

| Commit | Applications | Comparisons |
| --- | --- | --- |
| 00d31ef8 | Pad, Daybook, File Explorer | 437, 427, 1,637 |
| bc81322b | File Explorer, Daybook, Streams, the Agent | 1,637, 427, 244, 913 |
| 24a55dae | Pad, Sound Lab | 437, 170 |
| da5813c6 | Pad | 437 |
| 2bf926e8 | Pad | 437 |
| 3d274511 | Pad, Daybook, File Explorer, Sound Lab | 437, 427, 1,579, 170 |
| 944630df | Pad, File Explorer, Daybook | 437, 1,609, 427 |

The typing run with the check also passed at 24a55dae and da5813c6. Slice
1's commit, made in an earlier session, records no Desk run, and slice 4's
word has no caller yet. A run's count follows the frames it made: File
Explorer at 944630df made two more complete frames than at 3d274511, and
30 more comparisons.

At the end of the part, on 944630df:

| Run | Time | Comparisons | Snapshot | Producer's runs | Producer's menus | Shell's runs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Typing | 17.9 s | 676 | 168 | 55 | 165 | 288 |
| The canonical Desktop journey | 213.9 s | 4,692 | 1,246 | 440 | 1,518 | 1,488 |

The journey's counts are part 1's to the comparison.

## Runs with the check off

The canonical Desktop journey passed in 192.9 s.

The typing run with `--screen-profile`, every call chain kept and
`PYTHONHASHSEED=0`, at the part's start and end and at two points between.
Millions of steps in a burst frame:

| Stage | 36685e86, start | 2bf926e8, slices | 3d274511, UIDL | 944630df, end |
| --- | ---: | ---: | ---: | ---: |
| All steps | 17.79 | 18.87 | 18.80 | 19.59 |
| Frame build | 15.37 | 16.09 | 16.09 | 16.69 |
| Documents' snapshot | 3.12 | 3.70 | 3.71 | 4.33 |
| Desk's painting | 1.06 | 1.35 | 1.34 | 1.45 |
| Span-set proofs, inside the rows above | 0.67 | 1.54 | 1.54 | 2.15 |

With seeds 1 and 2 the snapshot took 3.12 and 3.11 million at the start
and 4.31 and 4.32 at the end, so the difference is not noise.

The UIDL change, 3d274511, costs nothing measurable here. In a GUARDED
build its header reads take `widget.f`'s guard, but the Desktop build does
not define GUARDED, and no GUARDED build was measured.

## Why the frames cost more: where storage lies

A burst frame gained 1.80 million steps over the part. Of that, 1.48
million is in span-set proofs (`MSPAN-SET-PROVE-DISJOINT?`), which went
from 0.67 to 2.15 million; most of it is RUHA's, and 0.12 million is the
collection snapshot's proof of its output ranges. Such a proof first asks whether the
range from its lowest span to the end of its highest lies clear of all live
UIDL storage. When other storage lies inside that range, the query is
refused, and the set splits and asks again for each half. In the snapshot,
the proof of each document's storage took 1.00 million steps a frame in
these split queries at 944630df, where 36685e86 answered it in one query
for 0.21 million. Desk's painting gained the same way, in the proof RUHA
makes when a projection is published (0.09 to 0.41 million). The other
0.32 million is spread over other stages, under 0.1 million each, while
the burst made 15 frames at 944630df and 16 at 36685e86.

RUHA proves its own record and the eighteen banks Desk gives it, all made
when Desk loads. Desk makes them with `XBUF`, which takes the first free
block that fits before it extends the allocated region, so they do not lie
together. Two runs of Desk with Pad, one at each end of the part, with
throwaway instrumentation of UIDL-TUI's storage check, showed where they
and the refused storage lay:

| | 36685e86 | 944630df |
| --- | --- | --- |
| Six small spans, 73 KiB together | from 198,544,496 | from 198,176,928 |
| Thirteen large banks, 19.0 MiB together | from 199,573,392 | from 199,573,920 |
| Gap between the two groups | 954 KB | 1,322 KB |
| The current root region | 198,397,848, below the spans, at the end of the run | 198,644,888, in the gap, at the largest refusal and at the end |
| UIDL-TUI storage checks refused | 0 of 1,151 | 364 of 1,263 |

Each refusal at 944630df found a root region inside the queried range. The
check tests that after UIDL-TUI's own module storage and before the live
context and UIDL's other storage, so other storage may also have lain in
the gap. At 36685e86 no check was refused. The small spans started 368 KB
lower at 944630df, and a root region lay between the groups.

The two runs differ only in the Akashic tree, and part 2 changed no proof,
no allocator and nothing in Desk's adapter setup. It changed sizes: of
source files, and of the descriptors widgets allocate. Those decide which
free blocks the boot leaves and where later blocks land. Six controls left
the snapshot within 0.1 million of where it was: at 944630df the text area's descriptor made 8
or 64 bytes larger, and 6.6 KB of comment added to `widget.f` or `desk.f`
at 36685e86 and to `desk.f` or `textarea.f` at 944630df. So small changes
of size do not move the placement, and which of part 2's changes moved it
was not identified.

## What follows

Until the proofs leave the frame, a commit can move a typed letter's frame
by more than a million steps without touching a check, in either direction,
by where its allocations happen to land. Part 1's note put the difference between part 0's and part 1's snapshot
(3.78 and 3.10 million) down to the unpinned seed. The seeds made no
difference here, so that difference may have had this cause too.

Part 3, as proposed, moves the handover proofs to when memory is lent,
allocated or grows, which would take this cost and its dependence on layout
off the frame.
Safe mode runs every check on every frame, so there the dependence stays
until part 9 removes RUHA's banks.

A smaller change would remove the dependence now: Desk could make RUHA's
record and banks from one load-time block, so that nothing else can lie between them
and one query proves them all. It would also give part 3's measurement a
starting point that layout does not move. This is a proposal, not done
here.

## What the runs wrote

The runs' output went to `/dev/shm`. By their process trees' I/O counters,
each run wrote between 0 and 440 KiB to the drive; the end runs and the
Desk runs at 3d274511 and 944630df wrote nothing.
