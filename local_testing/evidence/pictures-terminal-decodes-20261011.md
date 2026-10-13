# Pictures the terminal decodes — 2026-10-11

Part 9 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md)
moved picture decoding to the terminal. This records the photo check, File
Explorer's check and the full Desktop journey after it, against the
baseline in [photo-check-20261011.md](photo-check-20261011.md).

All three ran on the native simulator through
`local_testing/physical_desktop_acceptance.py`, one at a time. The times are
the simulator's, not a device's, and none of this is UART, panel or touch
evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit.

| Binding | Value |
| --- | --- |
| Akashic | `37364aaeeb2f76c9441d31e6e877d50d004eba35` (tree `8169768e2df106aa527ed491b03508f5215e7e54`) |
| MegaPad | `795cb02e415cef005010093ed98b53525974a55c` (tree `16cf4ad5cc5b4d0fcf1a7c64e963668464c91847`) |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` |
| Launcher SHA-256 | `af274173bdea1b2fbb491c59ed5e340d0b22c9a870e1d1fe1b146ba36829c466` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

## The photo check

`--applet photo` **passed** in 56.5 s, against 279.4 s before, with a peak
aggregate RSS of 559 MB, against 601 MB.

The terminal advertised QOI, so the producer sent the photograph's file as
it is: 8,144,442 bytes in one RESOURCE_BEGIN, nine chunks and a COMMIT. The
terminal decoded it at COMMIT and holds the whole picture, 2160 by 1620
pixels, 13,996,800 bytes of RGBA8. The viewer fits it into File Explorer's
195 by 78 cell preview, 2145 by 1638 pixels at its 11 by 21 pixel cells,
scaling smoothly. A crop of the recorded frame at full size shows single
seeds and grains sharply, in full colour.

Beneath it, CELL showed only what the picture is, "QOI, 2160 × 1620" under
the file's name, and no half block. The journey now fails if CELL draws any of
the picture there, or if the terminal holds anything but the photograph at
its own size.

From activating the Preview tab:

| Moment | After part 9 | Before |
| --- | ---: | ---: |
| Upload sent and committed | 6.0 s, 0.21 billion guest steps | 222.0 s, 7.5 billion |
| Photograph shown | 6.9 s, 0.27 billion guest steps | 223.5 s, 7.5 billion |

Most of the 0.27 billion steps are Desk drawing its 280 by 84 cell screen
for the tab change and the frames that follow; the picture itself costs
the guest almost nothing (below).

## Guest steps by phase

`local_testing/measure_pictures.py --picture assets/pictures/spice-market.qoi
--copy 2145x1638 --copy 704x756 --area 195x78 --area 64x36` now also counts
the route a picture takes when the terminal decodes its format.

| Phase | Before | After |
| --- | ---: | ---: |
| Reading the file's facts from its header | — | 796 |
| Reading the whole file for its upload, from memory | — | 110 |
| Rich copy, 2145 by 1609 | 4,228,487,381, with its digest | none: the file goes as it is |
| CELL copy for File Explorer's 195 by 78 cell preview | 2,254,859,935 | none while the picture shows rich |
| Drawing that CELL view | 74,193,138, the copy | 4,126,485, what the picture is |
| CELL copy for the canonical Desk's 64 by 36 cell preview | 2,237,141,613 | none while the picture shows rich |
| Drawing that CELL view | 8,263,120, the copy | 628,709, what the picture is |

The read from memory is a lower bound: Desk reads the file through its file
system. For a terminal that decodes none of the picture's formats, the
guest still makes a copy for the area, now without a digest: 2,855,528,864
steps for the 2145 by 1609 copy instead of 4,228,487,381.

## Where the host's time went

The first photo check after the guest work moved showed the photograph 18 s
after its Preview opened, while the guest ran only 57 million steps in the
upload's 14 s. A stack sampler in the session server found three host
costs, each removed by a host-only change that leaves guest behaviour and
the device unchanged:

- The simulator's TYPE wrote one byte per Python call, about 300 KB a
  second. It now writes a span of ordinary memory in one call (MegaPad
  `ed20d17c`).
- Pillow's QOI plugin decodes in Python a byte at a time: 4.1 s for the
  photograph. The hosted terminal now has its own decoder, which gives
  Pillow's pixels exactly in 1.6 s (MegaPad `a5b7b4e0`).
- The guest module fed each frame's CRC with its own copy of KDOS's buffer
  loop, one CRC-FEED call per eight bytes, each a round trip from native
  execution to the Python dispatcher: about a million calls for the photo.
  It now calls KDOS's `_CRC-BUF-CHECKED`, which the simulator already runs
  as one bulk feed (MegaPad `795cb02e`). This also removes the 7 ms a frame
  the 2026-09-29 host-lag record found while typing.

What remains is host work: the two pure-Python CRC-32C passes, the guest
CRC model's and the terminal's, about 0.7 s each for this file, and the
QOI decode, 1.6 s. On the simulator an accelerated word counts as one
semantic step, so guest step counts for frames now leave out the CRC loop
the device runs, about 1.25 instructions a byte.

## File Explorer's check

`--applet fexp` **passed** in 89.7 s with a peak aggregate RSS of 507 MB and
22 milestones. The sample picture showed rich three times, each time with
"QOI, 160 × 100" beneath it in CELL and no half block.

## The Desktop journey

The canonical journey **passed** in 235.0 s with a peak aggregate RSS of
530 MB: 67 milestones from 70 inputs, every frame rich with 550 to 853
retained draws. It sent 12,224,210 bytes in 60,716 frames, among them one
upload, the sample picture's 4,601-byte QOI file in a single chunk where a
64,000-byte raw copy went before, and 133 PRESENT transactions. File
Explorer's preview showed the sample rich with "QOI, 160 × 100" beneath it in
CELL, and the final CELL evidence names those facts in place of a half
block. Part 8's canonical run took 295.5 s at 560 MB; wall times vary with
the host's load.

## Open defects

- A file the terminal refuses as damaged is sent again on each newer draw,
  as every refused upload already was.
- A picture whose cells another root claims can show its label in CELL
  while nothing rich shows it.
- The file pull reads the whole file into staging in one call, so the guest
  holds as much memory as the file for the upload; it could be streamed.
- Claims stay through a soft reset or reopen until the producer rebuilds.
- From part 8: PT-CLOSE does not abort an open upload, and a frame refused
  more room during an upload records a terminal refusal.
