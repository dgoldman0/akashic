# Part 9b.1: one admission and one set of runs — 2026-10-28

Part 9 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
makes a frame's work follow what changed, and decision 15 put one record of
the frame first. Its first step leaves Desk's residual runs and admission to
the shell's batch: with the shell installed, the screen producer no longer
plans runs for its own candidate or admits it. This note gives the slice,
what the first runs found missing from it, its tests and its runs. All of
it is simulator evidence.

## The slice

4cdfcbd3 builds the producer's candidate for Desk's shell. The candidate
still passes the gates every plan of the residue needs, and the producer
marks in `ROW-DAMAGE` the rows a plan must build again, from the same
eligibility and marks its own damage path used, now split from that path's
row planning. It plans no runs and admits nothing. The record keeps whether
the candidate was built that way (`SHELL-BUILT`) and the Z of its region
(`BASE-Z`), which the shell now reads in place of the admission summary. The
fixed check compares the summary only for a candidate admitted alone, the
identity frontier counts the candidate's own objects, and a comparison of
shell-built candidates matches the applications' items without pairing runs
or adding a fence. The producer still builds alone, with its runs,
admission and family strips, before the owner opens and when the shell
refuses a batch that neither more engine storage nor more terminal space
would let fit; that candidate is offered to the shell again and goes out
alone only if the shell still cannot build.

The first runs of that commit found that the producer's own admission had
done work on the DELTA path that nothing else did, in four places:

- It grew the engine's working storage before the shell's batch was
  admitted. Without it, the typing run's lone letter, a 1,123-byte DELTA
  before, went out as a 116 KB START. d423d746 prepares a DELTA the shell
  refuses for want of engine storage once more after the storage grew, as
  a START already was.
- It refused, wherever the producer's own runs grew as well, a frame with a
  control the frame on screen lacks, which the shell's DELTA cannot carry:
  Desk with Pad, run with markers in the family admission, named a new TAB
  whose fresh identity broke the batch's control graph. d423d746 makes a
  comparison of shell-built candidates refuse such a control itself.
- It asked the terminal for more space inside a DELTA's build, and the draw
  was built again as a DELTA once the terminal answered. e840181f asks the
  same way when the shell's batch finds the space short.
- While nothing is shown after a draw that could not be, it refused a newer
  draw that still did not fit and left CELL showing it. Without it, Desk with
  Small Terminal sent a second empty frame over the first. e840181f builds
  alone in that state.

## Tests

For 4cdfcbd3, the 74 files that load the snapshot adapter, the producers or
Desk's composition, with the new `test_rich_shell_alone_rebuild.py`, ran one
file at a time with `TMPDIR` in `/dev/shm`, and 71 passed at first. The
refactor ratchet failed on the new state hash, recorded in that commit; the
owner's open-refusal tests failed on an exception handler the alone build no
longer uses; and the schema of the producer's guest failure record lacked
the two new fields. After those fixes, the eleven files that name a changed
word and the five lane producers' files passed. For d423d746, the 32 files
that name the comparison's control check, the comparison, the live
preparation or the glyph growth harness passed, the ratchet among them. For
e840181f, the alone-rebuild and structural producer files, the empty frame's,
the retained architecture's, the picture lane's, the owner's space and
open-refusal files and the ratchet passed. The new test runs START and DELTA
preparation with the shell and the build scripted: what goes out through the
shell, what is built alone and offered again, what goes out alone, what is
refused and left to CELL, and a DELTA prepared again once storage grew. Not
run: emulator smokes.

## Physical runs

Every run went through `physical_typing_cadence.py` or
`physical_desktop_acceptance.py`, one at a time, from RAM clones of
6467e0e5, the commit before 9b.1, and of a tree identical to e840181f's,
with output in `/dev/shm`.

### A typed letter's frame

The profiled typing run, with `PYTHONHASHSEED=0` and every call chain kept,
sent the same 18 DELTAs and 13,158 bytes for its burst before and after, and
its lone letter as the same 1,123-byte DELTA. A burst frame's build, in
millions of steps:

| Stage | Before | After |
| --- | ---: | ---: |
| Snapshot | 1.60 | 1.61 |
| Producer's candidate | 2.59 | 0.99 |
| — its admission | 0.91 | 0 |
| — its runs | 0.73 | 0 |
| — the rows marked for the shell | | 0.03 |
| Target pack | 0.27 | 0.29 |
| Comparison | 1.37 | 1.05 |
| Shell's batch | 3.21 | 3.24 |
| — its admission | 1.87 | 1.90 |
| — its runs | 1.00 | 1.00 |
| Shell's freeze and emission | 0.36 | 0.38 |
| Frame build | 9.63 | 7.78 |

The frame build fell by 1.85 million steps, 19 percent, against the plan's
estimate of 1.6 million. The shell's runs cost the same 1.00 million steps
without the producer's runs as a reference; on these frames it copies every
unchanged row from its own acknowledged bank and plans only the edited
rows. The lone letter's frame fell from 24.8 to 17.0 million steps, and the
whole run from 436 to 403 million.

### Desk and the journey, with the shadow check

Each run below passed after 9b.1 with no difference and nothing skipped.
The producer's own glyph stage makes no comparisons now, since it plans no
runs; the shell's stage checks the rows the producer marks.

| Run | Seconds | Comparisons | Judged | Roots | Changed | Items | Presents D/S/C/N | Bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Typing | 18.0 | 889 | 15 | 480 | 32 | 32 | 18 DELTAs | |
| Pad | 43.5 | 354 | 14 | 129 | 33 | 20 | 9/6/6/1 | 824,123 |
| File Explorer | 131.8 | 1,194 | 43 | 261 | 93 | 30 | 16/52/44/1 | 4,013,191 |
| Daybook | 136.5 | 309 | 13 | 68 | 25 | 7 | 7/8/8/1 | 664,481 |
| Streams | 107.1 | 181 | 5 | 29 | 9 | 2 | 2/7/7/1 | 581,236 |
| Agent | 66.6 | 567 | 18 | 159 | 35 | 9 | 9/20/16/1 | 1,645,532 |
| Sound Lab | 29.4 | 118 | 4 | 39 | 16 | 3 | 2/4/4/1 | 738,686 |
| Observatory | 36.2 | 168 | 4 | 48 | 7 | 2 | 0/8/8/1 | 880,823 |
| Small Terminal | 30.9 | 110 | 3 | 29 | 8 | 1 | 1/4/4/3 | 692,239 |
| Photo | 30.4 | 75 | 2 | 11 | 6 | 3 | 1/3/3/1 | 8,758,659 |
| Damaged | 27.3 | 158 | 6 | 32 | 10 | 5 | 3/4/4/1 | 924,151 |
| Canonical journey | 200.2 | 4,087 | 65 | 2,554 | 132 | 86 | 49/37/36/1 | 6,595,692 |

Judged, roots, changed and items are the root facts' judge, as in part
9a.1. Presents count DELTAs, STARTs, CONTINUEs and NONEs.

The same runs from 6467e0e5 passed with no difference either. Against them,
Agent, Damaged, Daybook, Pad, Photo, Small Terminal and Sound Lab sent the
same presents and the same bytes. The journey and Streams sent the same
presents, their bytes 2,384 more and 1,904 fewer. Observatory sent one more
CONTINUE unpinned; with the hash seed pinned in both, it sent the same
presents, though its bytes still differed, as they do between two runs of
the same commit (880,607 unpinned and 841,138 pinned, both before). File
Explorer, with the seed pinned in both, sent one more START that was
overtaken before it was shown, at stages 26 and 27, where inputs arrive in
quick succession and one met backpressure; it showed the same 44
CONTINUEs and 16 DELTAs. A diagnostic run of it found its one DELTA the shell
first refused for want of the engine's control ledger prepared again and
sent once the storage grew. The extra START reads as timing rather than a
change in what frames carry: every frame shown matched, the refusal counts
moved by one frame between two refusals that both send a START, and the
count of overtaken STARTs moves with a build's cost alone, as the
diagnostic run, whose markers only add steps, sent 53. 9b.1 shortens each
frame's build, which moves draws against the journey's paced inputs.

Where milestone screens differ between the two commits, they differ only in
content each run reads afresh. Photo's, Damaged's, File Explorer's and the
journey's differ in one column of their file tables, the sizes of each
commit's own `source-NN.src` files on the disk image; Daybook's in an
automation's next run time, which follows the clock.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clones; each run's shell reported a `write_bytes` of 0.
The diagnostic markers lived only in RAM clones and never entered the
repository.
