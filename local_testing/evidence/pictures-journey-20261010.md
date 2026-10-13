# Pictures in File Explorer through the physical viewer — 2026-10-10

Part 7 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Pictures", is done when "the Desktop journey selects the sample picture in
File Explorer and its Preview shows the picture rich in the physical viewer,
CELL shows the block preview on its own, and a terminal that lacks the
feature or refuses the space leaves the CELL preview with the reason
recorded". The guarded launcher `local_testing/physical_desktop_acceptance.py`
ran Desk with only File Explorer, then the canonical journey, with the native
simulator. Both **passed**. The canonical journey selected sunset.qoi in File
Explorer's detail table, activated the Preview tab, and saw the picture as
one IMAGE over its CELL half blocks. The picture stayed shown to the end, and
the final CELL frame showed the half blocks on their own.

The record ends with step 8's measurements: the guest steps a picture costs,
the bytes an upload sends, and what an upload holds up.

This is functional regression evidence and a set of guest step counts. The
host times are the simulator's, not a device's, and none of this is UART,
panel or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `b934f267d3b57e162cc81f42886f87b2bf47e2aa` (tree `27bd4620506b960948d075a97e2d37533f405dfa`) |
| MegaPad | `7d0d86b5a3119916a38a90a09d71044ac6bcd074` (tree `e06d66e04992e3af6992e8c1c7f5f02aa0201a4f`) |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` |
| Launcher SHA-256 | `26517d319f10bd8e0f829f14a29f9e8ca7e883b558bd15b731ca827e4695d715` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The styled faces and fallback fonts are those of part 3; `bindings.json`
records each file's SHA-256.

Profile and settings: `desktop-apt1` and `desktop-apt1-fexp` in ordinary
source mode, which advertise RGBA_IMAGE (raw RGBA8 up to 4096 pixels a side,
16 resources, 64 MiB); simulator backend with the native executor; 280x84,
18 px font, 0.75 s action delay, 10 s hold; 900 s watchdog and 3.5 GiB
aggregate-RSS stop. No compiled Forth cache, step-limit change or timing
change was used.

## Runs

| Run | Stages | Result | Wall time | Peak aggregate RSS |
| --- | ---: | --- | ---: | ---: |
| Desk with only File Explorer (`--applet fexp`) | 19 | pass | 106.2 s | 481 MB |
| Canonical Desktop journey | 55 | pass | 260.5 s | 532 MB |

Desk with only File Explorer selected sunset.qoi, showed its Preview rich,
returned to Details, showed the Preview again, previewed large.txt as text
with no picture, and selected sunset.qoi once more and saw it rich. Each
time the Preview showed the picture, CELL showed its half blocks beneath the
IMAGE. The terminal held the picture three times and gave it back three
times, since the Details tab shows no picture.

The canonical journey's new stages are 48 to 50: Alt+2 focuses File
Explorer, the table scrolls toward sunset.qoi and a SELECT selects it, and
activating the Preview tab shows it rich. Pad's styled-text stages follow as
51 to 55. The terminal held the picture once and kept it to the end.

## Measurements

### Guest steps

`local_testing/measure_pictures.py --area 64x36 --area 195x78` counts the
simulator's semantic steps for the sample picture, 160 by 100 pixels in a
4,601-byte QOI file. The areas are File Explorer's preview in the canonical
Desk (64 by 36 cells) and alone (195 by 78 cells). The rich copy is the
picture's own size in both runs, since a copy is never enlarged.

| Phase | Steps | Per unit |
| --- | ---: | ---: |
| QOI decode of the whole file | 1,916,437 | 120 a pixel |
| Copy at full size, 160x100, 64,000 bytes: decode, rows and digest | 8,356,737 | |
| SHA3-256 of those 64,000 bytes alone | 6,364,731 | 99 a byte |
| Copy at half size, 80x50, 16,000 bytes: decode, averaging and digest | 6,183,984 | |
| SHA3-256 of those 16,000 bytes alone | 1,593,341 | 100 a byte |
| Averaging, by difference | 2,674,206 | 167 a source pixel |

The digest is three quarters of a full-size copy's steps.

| CELL view | 64x36 cells, copy 64x40 | 195x78 cells, copy 160x100 |
| --- | ---: | ---: |
| First draw: starts the copy, shows the placeholder | 684,793 | 4,128,963 |
| Decoding the CELL copy, digest included | 5,343,364 | 8,355,011 |
| First draw of the ready copy: each pixel's palette colour | 7,045,575 | 44,181,257 |
| Each redraw: placing the cells | 2,286,848 | 14,341,212 |

The first ready draw costs about 2,750 steps a pixel and each redraw about
1,790 steps a cell, more than decoding the picture.

### Bytes on the wire

From the terminal's frame counters in each run's `performance-trace.json`:

| Frame | Bytes |
| --- | ---: |
| Resource begin | 120 |
| Resource chunk: the 64,000 bytes in one chunk, with 72 bytes of header | 64,072 |
| Resource commit | 64 |
| One upload of the sample | 64,256 |
| Resource drop | 64 |
| Owner resize | 104 |

Desk with only File Explorer sent 3 uploads, 3 drops and 9 owner resizes
among 3,955,659 bytes in 6,632 frames. The canonical journey sent 1 upload
and 3 owner resizes among 12,164,876 bytes in 61,157 frames.

### What an upload holds up

The contract allows one upload at a time and no transaction beside it, so
while an upload is open no frame, rich or CELL, reaches the screen. The whole
session waits for the upload's bytes, whatever the link's speed:

| Upload | Bytes | Times the sample |
| --- | ---: | ---: |
| The sample, 160x100 | 64,256 | 1 |
| A picture filling the canonical preview, 704x440 | 1,239,040 | 19 |
| A picture filling the preview alone, 2145x1340 | 11,497,200 | 179 |

The larger rows are what the same code would send for a picture of that size
or more, at the pixels these previews cover on this viewer (11 by 21 pixels a
cell). Their bytes are the raw copy's: the Desktop's chunks carry up to
917,576 bytes each with a 72-byte header, so framing adds under 0.02%. As
QOI, the sample is 4,601 bytes, 14 times smaller than its raw copy.

On the simulator the link is not paced, so its times are host times only.
From activating the Preview tab to the picture's surface being ready in the
viewer took 6.0, 4.5 and 6.0 s alone and 7.9 s in the canonical journey.
That covers the guest's decoding, its digest, the CELL draw and the frames
around the upload, at the simulator's speed.

## Findings

- The pause is the largest cost. Every frame waits for the whole upload, at
  any link speed, and a picture filling a preview sends 19 to 179 times the
  sample's bytes. A faster link or compression shortens the pause but keeps
  it. Letting frames through between an upload's chunks removes it, which
  needs the contract's one-upload rule to change.
- On the device, the SHA3-256 digest is three quarters of a rich copy's
  steps. The CELL copy computes one too, and nothing reads it: the only
  readers of a copy's digest, UPICSN's capture and pull, read the rich copy.
  That digest is redundant work, about 1 M steps per CELL copy in the
  canonical Desk and 6.4 M at the picture's own size.
- The CELL view's colour resolution and redraws cost more than decoding.

## Not covered

- A terminal that refuses the space was not run physically. It is held off
  for now by choice, as less important than the work ahead. The hosted
  terminal refuses an owner's request only when all live owners' requests
  together exceed its policy, and the Desktop has one live owner that never
  asks beyond the advertised limits. The producer tests cover refusal, the
  smaller copy that fits the room held, the limit, and a terminal that takes
  no pictures, each leaving the CELL preview with the reason recorded.
- A terminal without RGBA_IMAGE was not run physically; the producer tests
  cover it (Akashic `56cfa044`, after these runs).
- Reset, resize, reconnect, UART, panel and touch remain open, as for every
  family.
