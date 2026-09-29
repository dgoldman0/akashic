# Where the simulator's own time goes for one typed key — 2026-09-29

A typed key on the rich Desk has two kinds of cost. The guest's own work is
also paid on the real device, and earlier work measured and reduced it
([lag-storage-proofs-20260928.md](lag-storage-proofs-20260928.md)). The
simulator host's work, in Python, is paid only on the simulator. This note
measures the host part stage by stage, then records the changes that
followed and what they measured.

This is diagnostic evidence. It is not a comparison with earlier notes'
runs, and not UART, panel, or touch evidence.

## Method

Both runs used the tracked typing benchmark,
`local_testing/physical_typing_cadence.py`: the ordinary source-mode Desktop
and the physical X11 viewer, one isolated character, then eighteen at five
per second. A scratch copy of the runner, never committed, installed timing
wrappers in the server and the client. Each wrapper recorded the wall time
(CLOCK_MONOTONIC, which both processes share, so no clock alignment was
needed) and the calling thread's CPU time. Wall time minus CPU time is time
spent waiting, for the GIL, a lock, or I/O. On the server's runner thread,
frequent calls were summed per semantic boundary. A thread in the server
slept for 20 ms at a time and recorded how late it woke, which is how long a
waking thread waits for the GIL.

The second run also set `MEGAFORTH_NATIVE_PROFILE=1`, which names the reason
for every exit from native execution. That profile adds some cost of its own.

Both runs used Akashic `e3a5e43c`, MegaPad `10916b9` and its native extension
(SHA-256 `120704dae29f…`), under the 900 s watchdog and the 3.5 GiB
aggregate-RSS stop. Load averages were 1 to 3.

| Run | Isolated | Burst median | Burst worst | Characters | Peak aggregate RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Timing wrappers | 0.387 s | 0.684 s | 0.953 s | 19/19 | 527,671,296 bytes |
| Also the exit profile | 0.374 s | 0.662 s | 0.896 s | 19/19 | — |

## One isolated key

In the first run, the isolated key took 387 ms from its due time to visible
text:

| Span | Time |
| --- | ---: |
| The harness loop sends the key | 13 ms |
| The server receives it and the next boundary admits it | 12 ms |
| The guest works until its first publication | 118 ms |
| The rest of publication, then the host builds the offer | 86 ms |
| The client's screen request carries the offer and is decoded | 60 ms |
| The harness checks it, the viewer composes, flips and acknowledges | 99 ms |

The 86 ms is mostly one boundary of 80 ms. In it, 26 ms is Python time inside
the guest's batch, 6 ms decodes and commits the frame, and 40 ms builds the
offer.

## Per offer

Medians over the offers of each run, in milliseconds:

| Stage | Where | Run 1 | Run 2 |
| --- | --- | ---: | ---: |
| Convert the whole CELL screen for the offer (`_snapshot_output_view`) | server, owner lock | 28.2 | 27.4 |
| Project the rich plane (`project_composite_draw_plane`) | server, owner lock | 7.1 | 6.9 |
| Decode the guest's frame and commit it (`feed_machine`) | server, owner lock | 2.3 | 4.1 |
| Screen request, server wall | server, RPC thread | 18.7 | 13.0 |
| of which CPU | | 8.2 | 7.6 |
| of which run-length encoding of every cell (`snapshot_to_wire`) | | 12.6 | 11.7 |
| of which the draw plane (`retained_draw_plane_to_wire`) | | 0.9 | 0.8 |
| JSON encoding of the response | server, RPC thread | 2.9 | 2.5 |
| Response size | | 211,534 bytes | 211,548 bytes |
| The client's wait for the response | client | 29.6 | 24.4 |
| JSON decoding | client | 3.2 | 2.7 |
| Strict decoding of the draw plane | client | 15.0 | 14.2 |
| Decoding the cells | client | 8.4 | 7.4 |
| Rebuilding the viewer's grid | client | 4.2 | 3.7 |
| Harness only: saving the offer as a file | client | 12.7 | 13.1 |
| Harness only: checking the screen (`reconstruct_retained_screen`) | client | 18.4 | 17.8 |
| Composition | client | 47.1 | 42.7 |
| of which the CELL pass (`VirtualTerminal.render`) | | 21.8 | 19.7 |
| of which the rich layer (`composite_draw_plane_result`) | | 21.5 | 20.4 |
| of which cell coverage | | 2.1 | 2.1 |
| Flip | client | 4.6 | 4.1 |
| Acknowledgement request | client | 7.0 | 6.2 |

## Findings

**Whole-screen work for a small change.** Each offer converts all 23,520 CELL
cells to renderer cells, although the CELL model keeps unchanged rows shared
between publications. The screen request then run-length encodes every cell
again, and sends about 211 KB of JSON. The viewer decodes all of it,
checks every one of about 800 draws, rebuilds its whole grid, and composes
the whole window. For one typed character, almost all of that content is
unchanged since the last offer.

**The guest's checksum runs in Python.** MegaPad's `rich-terminal.f`
(`_PT-CRC-FEED?`) checksums each outgoing frame with the BIOS words
`CRC-FEED`, eight bytes per call, and `CRC-FEED-BYTE`. The native executor
does not run these calls, so each one returns to the Python dispatcher. The
exit profile counted 12,482 such calls in the 6.2 s typing window, about 560
per published frame. The boundaries that carried them spent a median 18.6 ms
of Python time per frame. On the device these words use the CPU's own CRC
instructions.

**Waiting for the GIL.** The native executor holds the GIL while it runs,
and the guest's loop never sleeps, so the runner thread holds it most of the
time: it was busy for 5.85 s of the 6.2 s typing window. A waking thread
waited a median 5.1 ms for the GIL (p90 5.2 ms), which is the default switch
interval. The screen request used 8.2 ms of CPU in 18.7 ms, and the client
waited 29.6 ms for it.

**Polling.** The product viewer, `megapad/session_viewer.py`, asks for a new
screen at its frame rate, 30 times a second by default, which adds about
17 ms on average before it sees a new offer. The typing harness instead
polls `status` and `screen` with a 10 ms sleep between rounds. The harness's
own file save and screen check, about 31 ms per offer, are not part of the
product viewer.

Over the typing window, the runner's time was 3.67 s of native execution,
1.30 s of Python dispatch (0.37 s of it in the checksum boundaries) and
0.84 s of driver service. The guest's work for one key, about 120 ms, is the
part the device also pays. The host's part for the same key is about
200 ms: about 75 ms on the server before the offer is ready, about 30 ms of
transfer and 30 ms of decoding, and about 60 ms to compose, flip and
acknowledge, plus the waits above.

## Changes

Three changes followed from these findings. Each removes work the host was
repeating, or does the same work faster, and leaves the guest, its values
and its semantic step counts unchanged. The device is not affected.

While they were measured, another program on the host started using eight
of its sixteen cores, and load averages rose from 1 to 3 to 10 to 14. The
runs below are therefore compared with runs under similar load, stage by
stage, and not with the quiet runs above. Every run showed all nineteen
characters, and its ready, first-character and final screenshots were
pixel-identical to the quiet run before any change.

**Unchanged rows are reused (MegaPad `0cfece4`).** A CELL publication keeps
each row it did not change as the same immutable tuple. The session now
converts only the rows the model replaced, and the screen response encodes
only rows it has not met before, still joining runs across row ends as
before. Converting the screen for an offer fell from a median 28.2 ms on the
quiet host to 1.65 ms in a typing run under load, and encoding its cells
from 12.6 ms to 2.2 ms.

**CRC feeds use per-mode byte tables (MegaPad `8908734`).** `shared.crc`
derives a 256-entry table for each CRC mode from the same bit recurrence,
which gives exactly the recurrence's value with one lookup per byte. One
8-byte feed now takes 3 us instead of 18 us, measured side by side under the
same load. This saves less than first estimated. Each `CRC-FEED` call still
leaves native execution for the Python dispatcher and returns, and that
round trip, about 11 us on a quiet host judging by the idle loop's exits,
was most of each call's cost. The saving is therefore about 7 ms per frame
rather than about 19 ms. Keeping these calls native would mean passing the
CRC unit's state into and out of each native run, since the native executor
never calls back into Python. That is a change to the executor's interface
and is left as a follow-up.

**Offers are sent as their changes (MegaPad `2f42352`, Akashic `fa068df2`).**
A display holder may now name the offer it last presented, and the server
then sends only the rows that differ and, per region, the draws removed,
added or changed, keyed by object or control ID. The viewer rebuilds the
complete offer from its presented offer before staging it, reusing the
base's decoded rows and draws. The contract is in MegaPad's
`docs/development-session.md`. Both physical runners name their base, as the
product viewer does. Under load, the typing run's offer-bearing screen
response fell from about 211 KB to about 12 KB, its JSON encoding from
12.4 ms to 0.3 ms, and the server's CPU for it from 5.1 ms to 2.8 ms. The
viewer's JSON decoding took 0.3 ms, rebuilding the offer 6.7 ms, and
updating its grid 5.3 ms.

In typing runs under load, the isolated character took 0.736 s after
the first change, at load averages of 12 to 14, and 0.630 s after the
third, at about 10.5. The burst median fell from 1.462 s to 0.851 s.

**Two viewer changes were not kept.** A glyph cache in the viewer's font
set removed about a third of a composition's Python calls, and a direct
coverage check in the CELL renderer replaced a generator per cell. In three
alternating pairs of runs on a real Desktop offer, composition took 57 to
66 ms with them and 57 to 64 ms without, so neither was committed.
Rasterizing glyphs is cheap. The time goes to per-cell and per-draw work
over the whole frame: 23,520 cell visits in the CELL pass, about 9,500
rectangle fills, and 695 glyph runs in the rich layer.

The canonical physical Desktop journey passes on Akashic `fa068df2` with
MegaPad `2f42352`, both clean: exit 0, 48 milestones and 51 inputs, every
frame rich with 709 to 1,038 retained draws, and peak aggregate RSS
492,986,368 bytes. It took 287.6 s under the same load.

## What remained after these changes

- Composition, about 45 ms a frame on a quiet host, repaints the whole
  window. Repainting only what changed needs every painter to keep within
  an outer clip, and the hit map of unchanged draws to be kept. That needs
  its own design.
- Waiting for the GIL and polling, about 20 ms a key.
- Keeping the CRC calls native, about 7 ms a frame.

The guest also repeats work here. Across ten consecutive frames of typing,
the same six controls, four item views, a text grid and a text area that
was not being typed in, changed only in their content revision, the
8-byte field at offset 8 of their STX1 or ITM1 body. The guest republishes
them every frame with an otherwise identical body, and the device would pay
for that as well.

## Repainting only what a frame changes

Composition was the largest remaining host cost, so MegaPad built
`docs/viewer-partial-repaint.md` in four steps: the CELL renderer can
repaint one area (`608ca90`); each composition records every draw's paint
extent and hit entries (`a7c3f6d`); a new frame repaints only the previous
and new extents of the paint operations that changed (`03bac17`); and the
viewer composes and presents that way, updating only the damaged
rectangles of its window (`c9134b2`). Akashic `62239a30` composes the
physical runs the same way.

Every repainted frame is held to a full composition of the same inputs,
pixel for pixel and hit entry for hit entry. The tests replay twelve real
typing offers and 160 frames of random edits to a scene with every draw
family, and a loop test holds the viewer's window to its composed frame
after every present. A text area, grid or item view that changes only its
content revision is not repainted, since no painter reads that revision;
its hit entries take the new revision. Building it found one painter that
is not exact under a smaller clip: a menu bar paints its shadow below its
anchor but paints nothing when its anchor is clipped out, so menu bars are
always repainted whole.

In a typing run under similar load, at load averages of about 8.5 to 10.5:

| | Offers as changes (MegaPad `2f42352`) | Partial repaint (MegaPad `c9134b2`) |
| --- | ---: | ---: |
| Isolated character | 0.630 s | 0.295 s |
| Burst median | 0.851 s | 0.430 s |
| Burst worst | 1.039 s | 0.544 s |
| Composition per offer, median | 86.6 ms | 17.8 ms |
| Blit and flip, or blit and update | 6.2 ms | 2.2 ms |

The first frame is still composed in full, in 76 ms. The run showed all
nineteen characters, and its screenshots were pixel-identical to the quiet
run before any change. Under this load the isolated character now appears
faster than it did on the quiet host at the start of this note (0.387 s).

The canonical physical Desktop journey passes on Akashic `62239a30` with
MegaPad `c9134b2`, both clean: exit 0, 48 milestones and 51 inputs, every
frame rich with 709 to 1,038 retained draws, and peak aggregate RSS
513,269,760 bytes, in 223.9 s at load averages near 11. Its runner
composed each frame from the one before, with a median of 37.2 ms over 70
compositions.

Profiled offline on the same typing offers, about half of what remains of
an incremental composition is laying out and comparing all of the frame's
roughly 700 draws, most of them unchanged, and the other half is
repainting the damaged area. Reusing an unchanged draw's extent from the
previous frame would remove most of the first half.

What remains after this: reusing unchanged draws' extents, as above;
waiting for the GIL and polling, about 20 ms a key; keeping the CRC calls
native, about 7 ms a frame; and the six controls the guest republishes
every frame with only a new revision.
