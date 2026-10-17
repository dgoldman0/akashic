# Prompts, dialogs and notices: what they cost — 2026-10-17

Step 8 of part 5 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md)
measures the guest steps of a key typed into a prompt, of opening and
answering a dialog, and of showing a notice, rich and CELL. This records three
physical applet checks with the screen profile: File Explorer, Daybook and the
Agent, each with Desk.

Every run used the native simulator, one at a time, under the 900-second
watchdog and the 3.5 GiB aggregate-RSS stop, on a 280×84 screen where the
applet's tile fills everything above the taskbar. Guest steps are the
simulator's semantic steps; an accelerated word counts as one. None of this is
UART, panel or touch evidence.

## Bindings

Every run bound clean source trees, unchanged at exit.

| Binding | Value |
| --- | --- |
| Akashic | `672dc622d0ebbaf6ab72febd0034b88546b497d7` (tree `7527234a3c318ff92884049fb32c96d6af25b1ec`) |
| MegaPad | `4b7be4574a13f2c63c806e47c9ec67c532d5062c` (tree `f1182282803a20e0cad5977e7625b3228f79b449`) |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Launcher SHA-256 | `e5f1b34addac6c8d4556a2cf938bc93f536802750933197424b011a4a75ac316` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

| Check | Result | Wall time | Peak aggregate RSS |
| --- | --- | ---: | ---: |
| `physical_desktop_acceptance.py --applet fexp --screen-profile` | passed | 157.2 s | 549 MB |
| `physical_desktop_acceptance.py --applet daybook --screen-profile` | passed | 142.7 s | 560 MB |
| `physical_desktop_acceptance.py --applet agent --screen-profile` | passed | 65.0 s | 566 MB |

## How the steps are counted

For each interaction the window runs from its input to the last PRESENT
before the next input; the idle time after that PRESENT is left out. The idle
loop costs about 1.2 million steps a second. "Rich producer" is the steps
under `RTHP-PREPARE` and `RTHP-STEP`, with everything they call: the hybrid
producer and Desk's shell producer building, matching and emitting the rich
frame. "Outside it" is the rest: handling the input, the applications' and
Desk's paint and the CELL feed, which is what a CELL session runs. It is
measured in the same run, not in a separate CELL session. The word profile
samples once every 65,536 steps, so the split between the two is good to
about that much a sample.

A frame is a START (`REPLACE_START`, then a `REPLACE_CONTINUE` that reveals
it with the CELL cells that changed) or a DELTA. A START defines every
region and object again.

## File Explorer

The journey renames large.txt through the rename prompt and cancels, asks
to delete it and keeps it, then types a missing path into Go to, whose
warning shows in the app shell's notice.

| Interaction | Guest steps, rich | Rich producer | Outside it (CELL) | Frames | Bytes |
| --- | ---: | ---: | ---: | --- | ---: |
| Rename prompt opens (F2) | 15,794,275 | 13,500,502 | 2,293,773 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 34,628 |
| Caret placed in it (PLACE) | 2,883,599 | 2,031,628 | 851,971 | 1 DELTA | 584 |
| Selection extended (EXTEND) | 3,538,968 | 2,686,996 | 851,972 | 1 DELTA | 548 |
| Five characters typed into it | 31,318,386 | 24,379,534 | 6,938,852 | 1 REPLACE_CONTINUE, 2 REPLACE_START | 64,552 |
| Rename prompt cancelled (Escape) | 14,352,477 | 12,320,847 | 2,031,630 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 34,566 |
| Delete question opens (Delete) | 31,646,058 | 26,738,844 | 4,907,214 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 55,826 |
| Question answered (Cancel button) | 49,479,985 | 14,876,755 | 34,603,230 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 34,062 |
| Go to prompt opens (Ctrl+G) | 14,680,157 | 12,517,458 | 2,162,699 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 34,619 |
| Fourteen characters typed into it | 38,076,649 | 25,034,902 | 13,041,747 | 1 REPLACE_CONTINUE, 2 REPLACE_START | 64,625 |
| Enter: prompt closes, warning shows | 14,745,689 | 12,386,379 | 2,359,310 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 35,158 |
| The warning ends | 16,509,897 | 10,944,575 | 5,565,322 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 32,470 |

## Daybook

The journey adds a task through Daybook's prompt, asks to delete the daily
reminder and keeps it; later the reminder fires and its notice shows.

| Interaction | Guest steps, rich | Rich producer | Outside it (CELL) | Frames | Bytes |
| --- | ---: | ---: | ---: | --- | ---: |
| Task prompt opens | 20,963,981 | 17,956,969 | 3,007,012 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 35,292 |
| Backspace in it | 15,269,982 | 12,255,301 | 3,014,681 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 33,090 |
| Caret placed in it (PLACE) | 2,155,036 | 983,044 | 1,171,992 | 1 DELTA | 635 |
| One character typed into it | 15,007,831 | 12,058,693 | 2,949,138 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 33,307 |
| Enter: prompt closes, task added | 38,338,771 | 12,451,913 | 25,886,858 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 40,691 |
| Delete question opens (Delete) | 25,420,742 | 19,923,056 | 5,497,686 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 44,632 |
| Question answered (Cancel button) | 32,964,831 | 8,519,729 | 24,445,102 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 12,607 |

The reminder's notice comes with no input. Its frame is a START of 33,235
bytes: about 12.7 million steps in the rich producer and about 0.5 million in
Desk's paint, beside the work of firing the reminder. The notice ending is a
START too, about 11.2 million steps in the rich producer.

## The Agent

The journey types into Desk's own Ask prompt, and then into the Agent's.

| Interaction | Guest steps, rich | Rich producer | Outside it (CELL) | Frames | Bytes |
| --- | ---: | ---: | ---: | --- | ---: |
| Desk's Ask prompt opens (Alt+A) | 6,094,883 | 5,636,127 | 458,756 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 13,244 |
| Five characters typed into it | 9,044,025 | 6,488,101 | 2,555,924 | 2 DELTA | 1,070 |
| Caret placed in it (PLACE) | 1,826,652 | 1,114,120 | 712,532 | 1 DELTA | 577 |
| Two characters typed over a selection | 10,092,609 | 8,912,956 | 1,179,653 | 2 DELTA | 1,063 |
| Desk's Ask prompt cancelled (Escape) | 6,881,320 | 6,488,102 | 393,218 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 14,586 |
| Agent's Ask prompt opens (Ctrl+L) | 11,395,402 | 10,616,897 | 778,505 | 1 REPLACE_CONTINUE, 1 REPLACE_START | 16,197 |
| Fourteen characters typed into it | 33,219,037 | 22,020,229 | 11,198,808 | 1 REPLACE_CONTINUE, 2 REPLACE_START | 27,825 |

## What the numbers say

- **A key typed into Desk's Ask prompt** is a DELTA: about 4 to 6 million
  steps a frame, of which the rich producer takes about 2.5 to 5.5 million,
  and about 0.5 KB.
- **A key typed into an application's prompt** is a START in all three
  applets: about 10 to 23 million steps a frame, mostly 12 to 15, of which
  the rich producer takes about 9 to 13 million, and 13 to 33 KB a frame.
  Outside the producer, what a CELL session spends, it costs about 3 to 6
  million. A PLACE or an EXTEND on the same prompt is a DELTA of 2 to 3.5
  million steps and 0.6 KB. The producer does not match the typing frames as
  DELTAs: in File Explorer the shell producer's probe refusals equal them,
  and in Daybook the base producer's DELTA match refuses them. File Explorer
  runs since step 3 show the same counts. The cause is not diagnosed.
- **Opening or closing a prompt or a dialog, and a notice coming or going**,
  adds or removes a region, the modal region or the notice's, so each is a
  START by design: about 6 to 27 million steps in the rich producer and 10 to
  56 KB. Outside the producer they cost 0.4 to 5.5 million.
- **Answering a dialog** costs most outside the producer: 34.6 million steps
  in File Explorer and 24.4 million in Daybook, where cancelling a prompt
  costs 0.4 to 2 million. In File Explorer Desk's paint takes 32.8 million of
  them, where opening the dialog took 0.5 million and closing a prompt 0.5 to
  0.8 million: the application paints far more after its dialog closes than
  after its prompt does.
- **Showing a notice** costs about 12.7 million steps in the rich producer and
  about 0.5 million in Desk's paint.
