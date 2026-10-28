# Part 9b.2: one bank — 2026-10-28

Part 9 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
makes a frame's work follow what changed, and decision 15 put one record of
the frame first. Its second step makes the screen producer's bank that
record for Desk: the shell's part of each frame, which the shell had kept
in two banks of its own, now freezes into storage the producer owns, and
the frame's bank names it. This note gives the slice, its tests and its
runs, and a failure in safe mode, from 9b.1, that the runs found and
ceabef49 fixes. All of it is simulator evidence.

## The slice

Before 9852b10a a frame of Desk's had two records. The producer's target
bank held the applications' controls, keys and input targets and decided
whether the frame could go out as a DELTA; the shell's bank held the batch
on the wire, with the model copy, the taskbar's correlations and actions and
the panes' membership that a click on the chrome reads. The shell gave its
banks pending and active roles of its own, sealed them itself, and tied each
to the producer's bank of the same frame by pointer, draw, owner and
generation, retiring its banks when the two records stopped pairing.

The shell now freezes its part into one of two extension blocks the
producer owns, the one the bank on screen does not name, and the pending
bank records the part's address and the bytes it uses. From then on the
part belongs to the bank: it is published, kept and retired with it, and
every path on which the producer abandons the shell's preparation drops it
from the pending bank through one word. With every check on, the bank's
seal runs on over the part, so the producer's seal checks before each DELTA
comparison and each application click cover the shell's part as well, and
the shell checks the same seal before it routes a click on its chrome. The
shell's roles, banks, seals and pairing checks go. Its part header no
longer records the target, draw, owner, generation or used bytes the bank
now holds, and shrinks from 136 bytes to 96; the shell's record shrinks
from 224 bytes to 128.

The blocks lie outside the producer's arena, whose layout fixes the banks'
size from the producer's capacities, while a part's size follows the
desktop. They start empty. A freeze refused for room has the producer take
a block from its memory source for what the part needs and half again, and
the shell builds once more, the rule the shell's banks grew by, so a part
that grows neither grows the arena nor turns a DELTA into a START. Desk no
longer gives the shell first banks, and the producer gives the blocks back
when it is finished.

## Tests

The 74 files that load the snapshot adapter, the producers or Desk's
composition, the same selection as 9b.1's, ran one file at a time with
`TMPDIR` in `/dev/shm`, and all passed, the refactor ratchet with the new
state recorded in the commit. The shell's tests now stage real bank headers
and the producer's extension blocks, and their DELTA steps pack each frame
into the bank the frame on screen is not, as the producer does. The new
cases check the part against its bank's draw, owner and generation and
against a part that does not start its block, show the bank's seal finding
a change to the part that keeps the part's structure, and show a grown
block that overlaps the producer's record refused as an anomaly that names
Desk's memory source. Not run: emulator smokes.

## Physical runs

Every run went through `physical_typing_cadence.py` or
`physical_desktop_acceptance.py`, one at a time, from a RAM clone of
9852b10a with MegaPad at 1833d16f, and output in `/dev/shm`. The runs
before the slice are 9b.1's, from a tree identical to e840181f's.

### A typed letter's frame

The profiled typing run, with `PYTHONHASHSEED=0` and every call chain kept,
sent the same 18 DELTAs and 13,158 bytes for its burst as 9b.1's, and its
lone letter as the same 1,123-byte DELTA. A burst frame built in the same
7.78 million steps, and every stage matched 9b.1's within 0.01 million: the
shell's freeze took 0.20 million steps and its emission 0.17, against 0.38
for the two before. The part check and the seal run only with every check
on, and the bank's naming of the part adds no measurable work to a normal
frame. The lone letter's frame build was 15.40 million steps both times;
its window held 0.31 million more steps outside the build, in Desk's loop
(painting, the flush and the terminal's service), and the whole run took
402.1 million steps against 403.1. With the shadow check on, the typing run made
889 comparisons with no difference and nothing skipped, and judged 15
frames, 480 roots, 32 changed, 32 items, as before.

### Desk and the journey, with the shadow check

Each run below passed with no difference and nothing skipped.

| Run | Seconds | Comparisons | Judged | Roots | Changed | Items | Presents D/S/C/N | Bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Typing | 17.6 | 889 | 15 | 480 | 32 | 32 | 18 DELTAs | |
| Pad | 43.5 | 354 | 14 | 129 | 33 | 20 | 9/6/6/1 | 824,123 |
| File Explorer | 128.3 | 1,191 | 44 | 268 | 94 | 30 | 16/52/44/1 | 4,014,167 |
| Daybook | 137.0 | 309 | 13 | 68 | 25 | 7 | 7/8/8/1 | 664,481 |
| Streams | 100.7 | 181 | 5 | 29 | 9 | 2 | 2/7/7/1 | 583,140 |
| Agent | 63.1 | 567 | 18 | 159 | 35 | 9 | 9/20/16/1 | 1,645,532 |
| Sound Lab | 27.9 | 118 | 4 | 39 | 16 | 3 | 2/4/4/1 | 738,686 |
| Observatory | 34.4 | 168 | 4 | 48 | 7 | 2 | 0/8/8/1 | 880,235 |
| Small Terminal | 29.5 | 110 | 3 | 29 | 8 | 1 | 1/4/4/3 | 692,239 |
| Photo | 28.2 | 75 | 2 | 11 | 6 | 3 | 1/3/3/1 | 8,758,659 |
| Damaged | 28.8 | 158 | 6 | 32 | 10 | 5 | 3/4/4/1 | 924,151 |
| Canonical journey | 194.9 | 4,087 | 65 | 2,554 | 132 | 86 | 49/37/36/1 | 6,594,384 |

Judged, roots, changed and items are the root facts' judge, as in part
9a.1; presents count DELTAs, STARTs, CONTINUEs and NONEs, and the typing
row's are its profiled burst's.

Against 9b.1's runs, every application and the journey sent the same
presents, and every root-facts and comparison count matched but File
Explorer's, which follow the frames a run happens to build. Agent,
Damaged, Daybook, Pad, Photo, Small Terminal and Sound Lab sent the same
bytes. Streams sent 1,904 more, the bytes the runs before 9b.1 sent, so
its bytes take one of two values from run to run. Observatory sent 588
fewer; its bytes differ between runs of one commit, by 39,469 in 9b.1's
comparison. The journey sent 1,308 fewer, which was not traced. File
Explorer sent 976 more, all in one pair of STARTs early in its run, one
of them overtaken before it was shown.

With the hash seed pinned, as in 9b.1's comparison, Observatory sent the
same presents, and File Explorer the same 44 CONTINUEs and 16 DELTAs with
50 STARTs, where 9b.1's run had sent 52 and the run before 9b.1 51. Set
side by side, the three runs' timelines differ only around STARTs
overtaken before they were shown, which move with timing, and in that
early pair, whose bytes 9b.2's runs share with the run before 9b.1 while
9b.1's, pinned and unpinned alike, came to 976 fewer; what made 9b.1's
smaller was not traced. Against the run before 9b.1, 9b.2's pinned run
differs by one overtaken START of 18,719 bytes alone.

### Safe mode

Safe mode turns every check on, so the canonical journey in safe mode is
the run that seals and checks the shell's part on every frame. From
9852b10a it stopped about a minute in, when the screen adapter recorded
the fault INVALID and Desk raised exception -3203. Run again from 9b.1's
tree, it stopped the same way at the same point, with the same counters:
the shell had refused 18 complete preparations, all at its glyph stage
with UNAVAILABLE, and the producer had built 16 frames alone. From the
tree before 9b.1 it passed in 354 seconds, with every check on and no
damage named.

Since 9b.1 the producer plans no runs for the candidate it builds for
Desk's shell, so in a session its glyph banks hold the plan of the last
draw it built alone. The shell hands the planner that plan as a reference
only when it is this draw's, and otherwise a count of no runs, but it
still passed the old plan's item, reference and text addresses. With
every check on, the planner proves the reference's banks well formed, and
a bank of no bytes that names storage is not one, so it named the
producer's held glyph plan damaged and refused, and the shell refused its
build. Each frame of Desk's then went out only after the producer had
built it alone, with a plan of its own draw, and offered it to the shell
again. The step from those refusals to the fault that stopped Desk was
not traced. ceabef49 gives the planner a reference that names no banks
when the producer's plan is another draw's or holds no runs. Its test
holds a producer plan of an older draw, and one of this draw with no
runs, with every check on: on 9852b10a the first preparation refused at
the glyph stage with UNAVAILABLE and named the producer's held glyph plan,
and with the change both prepare and name nothing. The shell's test
files, the planner's contract, the check tools and the ratchet passed
again, 18 files. A reference with runs is unchanged, and in normal mode,
where the planner does not prove the banks, the reference of no runs
plans the same runs, so the runs above, from 9852b10a, stand for the
commit after it.

From a RAM clone of ceabef49 the journey in safe mode passed in 391
seconds, with no damage named: the part's checks and the bank's seal over
it ran on every frame and found nothing, the shell prepared each of its 48
DELTAs, and the producer built no frame alone. Against the same
journey from the tree before 9b.1 it sent one DELTA fewer and one START
and one CONTINUE more, 6,827,144 bytes against 6,710,044. Its one refusal
more is the comparison's refusal of a control the frame on screen lacks,
which 9b.1 added (d423d746) and which the normal-mode journey above also
makes once.

### Memory

The blocks take the shell's banks' place and grow by the same rule, from
a part 40 bytes smaller. In File Explorer, against 9b.1's run of the same
journey, the part came to 43,840 bytes where the bank had used 43,880, the
blocks to 65,760 and 65,776 bytes where the banks had been 65,824 and
65,832, and Desk's memory source held 88 bytes less, 15,226,496: 120 bytes
fewer in the blocks and 32 more in the producer's arena, whose two target
banks each gained the two cells that name the part. In the canonical
journey the part ended at 201,400 bytes and each block at 236,536 bytes,
against the two 237 KB banks the plan recorded on 2026-10-18. In the
safe-mode journey from ceabef49 the blocks came to 237,784 bytes each,
where the run before 9b.1 had grown the shell's banks to 237,840, for a
part of 201,400 bytes against a bank of 201,440.

## A stale reader in the headless grid tool

`_read_shell_source` in `rich_terminal_desktop_acceptance.py`, which
`run_headless_grid_acceptance.py` uses to read the shell's acknowledged
frame from a paused guest, still expects the layouts of 2026-10-01: a
4,136-byte producer record, a 64-byte extension descriptor and a 240-byte
shell record with its extension at offset 176. The producer's record has
grown since, to 5,128 bytes with 9b.2, so the reader's first check refuses
any current guest. Its unit test passes because its synthetic guest is
built with the same old layouts. This was found by reading the code, not by
running the tool; it predates 9b.2, which takes away the shell's active
bank that the reader goes on to read, so a repair would find the part
through the producer's active bank. Nothing on the frames plan's path uses
the tool, and it is left for its next use.

## Files

The safe-mode runs from 9b.1's tree and from the tree before it came from
RAM clones of 563cbfb1, whose sources are e840181f's, and of 6467e0e5. The
runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clones; each run's shell reported a `write_bytes` of 0.
