# Part 0: today's changed frames — 2026-10-19

Part 0 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
measures, before any change, where a changed frame's guest steps go and how
much memory each stage of the frame build holds. Its numbers replace the
2026-10-14 ones the design started from, which predate the rich components
work.

This is measurement on the simulator. Steps are the simulator's semantic
steps, and times are the host's. None of this is UART, panel or touch
evidence.

## Bindings

Every run bound clean trees.

| Binding | Value |
| --- | --- |
| Akashic | `8dae27d49c4967f5d8c6bb1b794042a71b9d0a01` (tree `f993dd8209dfd16107250d8e12dbfd84f233823a`): main `1b566fc3` with the design and the adapter's memory in the run diagnostics, so its Forth is main's |
| MegaPad | `dd108ff2bdd8f95e812829f49db94bf5824455c6` (tree `ae5e8dff3be073d4113008800f66548efac7168f`), main |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

## Runs

All runs used the native simulator at 280 × 84 with `--screen-profile` and
every call chain kept (`MEGAPAD_PROFILE_CHAINS=0
MEGAPAD_PROFILE_CHAIN_DEPTH=0`), one at a time, after an uncapped wait for
another project's tests to finish, under the 900-second watchdog and the
3.5 GiB aggregate-RSS stop.

| Run | Result | Time | Peak aggregate RSS |
| --- | --- | ---: | ---: |
| Typing (`physical_typing_cadence.py run --label baseline`) | all 19 characters shown | 23.7 s | 455 MiB |
| Desk with Pad (`physical_desktop_acceptance.py --applet pad`) | passed | 47.7 s | 510 MiB |
| Desk with Daybook | passed | 138.5 s | 535 MiB |
| Desk with Sound Lab | passed | 31.6 s | 530 MiB |
| Desk with Observatory and Worlds | passed | 40.9 s | 510 MiB |
| Desk with File Explorer | passed | 140.2 s | 524 MiB |

## How the steps are counted

`local_testing/frame_build_stages.py`, new with this note, reads a run's
profile. A stage's steps are those of every call chain that passes through
any of its words, so nothing is counted twice inside one stage. A typing run
is read as its isolated first character and, per frame, its burst; a frame
is a PRESENT with a retained part. A Desk run is read per interaction, from
one input to the next. The profile charges steps in tenths of a second, so
the record that holds a frame's build can end after the frame's PRESENT; a
window that stops at the last PRESENT, as earlier notes' did, can miss the
build of a short interaction. The whole-run split counts the whole run,
start-up included.

## Typing

A burst of 18 characters made 14 frames, all DELTAs, 736 bytes a frame on
average.

| Stage, per burst frame | 2026-10-14 | 2026-10-19 |
| --- | ---: | ---: |
| All steps | 17.8M | 19.16M |
| Frame build (`_RTHP-PREPARE-LIVE`) | 15.1M | 16.13M |
| Documents' snapshot | 3.0–3.3M | 3.78M |
| Producer's candidate | 3.5M | 3.56M |
| — the engine's admission | 1.0M | 1.02M |
| — the producer's glyphs | | 0.76M |
| Target pack | | 0.42M |
| Comparison | 1.5M | 1.60M |
| Shell's batch | | 3.74M |
| — its preflight | 2.0M | 2.04M |
| — its glyphs | | 1.11M |
| Shell's freeze | 1.25M | 1.35M |
| Shell's emission | 0.4M | 0.42M |
| Shell's checks at each dispatch | 0.9M (storage proof) | 1.24M (header and authority) |
| Shell model compares (CURRENT and DELTA-PROBE) | | 0.01M |
| Adapter's checks, inside the rows above | 0.8M | 1.62M |
| Storage-aliasing checks, inside the rows above | | 3.82M |
| Desk's painting | | 1.53M |

The frame build rose by about 1 million steps since 14 October, as fields,
dialogs, notices, status fields and plots landed: the snapshot by about 0.5
million and the shell's checks at each dispatch by about 0.3 million.

The isolated first character cost 28.18 million steps, 25.76 million of them
its frame build, with the engine's admission at 4.85 million.

## Desk with one application

Mean frame build of the interactions that sent only DELTAs and of those that
sent a START. An interaction that sent several frames counts all of them, so
these are per interaction, not per frame.

| Desk with | DELTA interactions | Their frame build | START interactions | Their frame build | A START's emission |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pad | 8 | 10.84M | 5 | 23.38M | 8.61M |
| Daybook | 7 | 7.46M | 6 | 18.27M | 4.28M |
| Sound Lab | 2 | 10.85M | 3 | 22.72M | 5.75M |
| Observatory and Worlds | 0 | | 6 | 23.48M | 8.19M |
| File Explorer | 14 | 9.31M | 32 | 18.70M | 4.80M |

A Pad interaction that sent one DELTA, a key or a click that placed the
caret, built its frame in about 8.2 million steps: half of a typing burst
frame, which changes the same editor. The typing run's Desktop shows five
applications (Pad, File Explorer, Daybook, Grid and the Agent), and Desk
with Pad shows one: the build follows what is on the screen. Single DELTAs
in Daybook took 5.4 to 6.3 million. Within the
DELTA interactions the snapshot took 2.2 to 3.5 million, the candidate 1.3
to 2.2 million and the shell's batch 1.3 to 2.3 million. A START also
recaptures the screen and sends every object again: its emission alone took
4.3 to 8.6 million.

Observatory sent no DELTA. Every Worlds step and analysis changed its plot
and series, which a DELTA cannot yet replace.

## The whole run

| Run | All steps | Frame build | Desk's painting | — background fills | CELL flush outside the producer |
| --- | ---: | ---: | ---: | ---: | ---: |
| Typing | 534.5M | 251.5M | 57.1M | 15.0M | 51.4M |
| Desk with Pad | 555.3M | 203.6M | 156.7M | 61.9M | 71.0M |
| Desk with Daybook | 628.5M | 161.9M | 163.5M | 53.7M | 78.1M |
| Desk with Sound Lab | 347.3M | 89.9M | 86.3M | 30.0M | 72.0M |
| Desk with Observatory and Worlds | 413.0M | 140.9M | 64.3M | 27.3M | 86.4M |
| Desk with File Explorer | 2,482.3M | 728.8M | 834.6M | 454.8M | 488.3M |

Desk's painting is everything under `DESK-PAINT-CB`: UIDL and the
applications drawing into the CELL screen. Background fills are the steps
under `_UTUI-FILL-BG`. The CELL flush outside the producer is `SCR-FLUSH?`
less the rich producer: the changed cells' path through the CELL layers.

When a document repaints, each nested container fills its whole area before
its children paint over it. In File Explorer's item open (input 54), the
painting's 30.9 million steps included 24.1 million of fills: the root 6.2
million, the split 5.3 million, the region 5.2 million, the tab set 3.7
million and the scroll area 3.6 million, over largely the same cells. The
widgets' own drawing was 6.4 million.

## Memory

From each Desk run's `final-guest-diagnostics.json`. The typing tool records
no guest diagnostics.

| Desk with | Producer holds (its arena) | Shell's two banks | Shell's work space | Adapter's banks | Adapter's snapshot used |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pad | 14.5 MiB (9.8 MiB) | 0.25 MiB | 4.1 MiB | 19.1 MiB | 13 KiB, 1 document |
| Daybook | 14.3 MiB (9.9 MiB) | 0.13 MiB | 4.1 MiB | 19.1 MiB | 13 KiB, 1 document |
| Sound Lab | 15.4 MiB (10.8 MiB) | 0.25 MiB | 4.1 MiB | 19.1 MiB | 40 KiB, 1 document |
| Observatory and Worlds | 14.6 MiB (10.0 MiB) | 0.22 MiB | 4.1 MiB | 19.1 MiB | 12 KiB, 2 documents |
| File Explorer | 14.7 MiB (10.2 MiB) | 0.19 MiB | 4.1 MiB | 19.1 MiB | 16 KiB, 1 document |

The producer, the engine and the shell grow from Desk's memory source as
the screen needs. The adapter's banks do not: Desk gives it 19.1 MiB when it
starts, sized from the most documents, UIDL elements and text it could hold.
The largest are the collection descriptors (3.9 MiB), menu records (3.0
MiB), data-graphics descriptors (2.5 MiB), the collection work space (2.0
MiB) and data-graphics values (1.75 MiB). In File Explorer's run the
snapshot used 16 KiB of them.

## Findings

1. **Typing.** The frame build is 16.1 million of a burst frame's 19.2
   million steps. The design's target, a frame build of about 6 million or
   fewer, stands.
2. **Painting.** Outside typing, Desk's painting costs about as much as the
   frame build, and more in File Explorer, and background fills are a third
   to over half of it. Parts 2 to 4 cut how often whole documents repaint;
   the repeated fills of one repaint are not in the design.
3. **The CELL flush.** The changed cells' path through the CELL layers took
   51 to 488 million steps over these runs. It is not in the design.
4. **The adapter's memory.** Its 19.1 MiB of banks are reserved for the most
   it could hold, while its snapshots used 12 to 40 KiB. Part 5's copy would
   hold one snapshot's slices: tens of KiB in these runs.
5. **Observatory** sends every changed frame as a START.
6. **The shell model compares** cost 0.01 million steps a frame, so the
   design no longer lists them among the repeats for part 8.
