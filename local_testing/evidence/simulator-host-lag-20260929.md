# Where the simulator's own time goes for one typed key — 2026-09-29

A typed key on the rich Desk has two kinds of cost. The guest's own work is
also paid on the real device, and earlier work measured and reduced it
([lag-storage-proofs-20260928.md](lag-storage-proofs-20260928.md)). The
simulator host's work, in Python, is paid only on the simulator. This note
measures the host part on the current trees, stage by stage. No code
changed.

This is diagnostic evidence from two runs. It is not a comparison with
earlier runs, and not UART, panel, or touch evidence.

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
