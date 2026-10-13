# Where a tab change's guest work goes — 2026-10-11

Opening File Explorer's Preview tab in the photo check, until the photograph
shows, took about 270 million guest steps after part 9. This records where
they go, as the baseline for part 10 of the
[rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md).

The run was `local_testing/physical_desktop_acceptance.py --applet photo` on
the native simulator. It **passed** in 52.7 s with a peak aggregate RSS of
539 MB. Guest steps are the simulator's semantic steps; an accelerated word,
such as KDOS's CRC buffer feed, counts as one.

## Bindings

Both source trees were clean at launch and unchanged at exit.

| Binding | Value |
| --- | --- |
| Akashic | `378e58f885b7203de6a518193f4b94ce8fde76dd` (tree `78f09a48779fe725493db109a7eba8eba59de45d`) |
| MegaPad | `795cb02e415cef005010093ed98b53525974a55c` (tree `16cf4ad5cc5b4d0fcf1a7c64e963668464c91847`) |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` |

## How it was measured

Two host-side hooks, loaded into the session server from outside both trees,
did the measuring. Neither changes what the guest or the terminal does.

- **A guest word profile.** The simulator hands control back to the host
  every 65,536 semantic steps with the guest suspended. At each of those
  points the hook read the suspended word and every colon caller on the
  return stack, and charged the steps since the last point to each of them.
- **A transaction log.** The hosted terminal logged each PRESENT_BEGIN it
  accepted: its CELL mode, spans and cells, and its retained mode and
  operations.

The window runs from the Preview tab's activation to the terminal holding
the photograph: 7.1 s and 268,559,395 steps in this run.

## The transactions

| After activation | CELL | Retained | Bytes | Guest steps before it |
| ---: | --- | --- | ---: | ---: |
| 0.96 s | none | full replacement starts, 208 operations | 41,790 | 88,731,575 |
| 1.08 s | delta, 15,224 cells in 80 spans | replacement continues | 126,168 | 4,980,767 |
| 1.64 s | **complete snapshot**, 23,520 cells | none | 192,744 | 37,028,058 |
| 5.79 s | none | full replacement starts, 131 operations | 17,339 | 76,022,262 |
| 5.85 s | **complete snapshot**, 23,520 cells | replacement continues | 192,744 | 5,963,815 |

The first two make the tab's frame: the new rich frame, and the preview's
cells, which say "Loading the picture". The third redraws the preview with
the picture's label, after the rich side claimed it, and sends the whole
280 by 84 screen to do so. The fourth and fifth show the photograph once the
terminal holds it. The CELL text did not change at all in the fifth, yet it
sent the whole screen again: the APT adapter promotes a retained-only
request to a complete CELL snapshot (`_RTAPTSCB-PROMOTE-NONE`), although
RETAINED-1 allows a PRESENT with no CELL cells.

Each complete snapshot cost 37 to 50 million guest steps to publish, about
1,500 to 2,100 steps a cell.

## The guest word profile

Steps under each word, including everything it calls, over the window:

| Work | Steps | Share |
| --- | ---: | ---: |
| Painting the screen and publishing it (`_ASHELL-PAINT`) | 259,655,211 | 96.7% |
| Desk and File Explorer drawing (`DESK-PAINT-CB`) | 20,185,213 | 7.5% |
| Publishing CELL cells one at a time (`_APTSCB-WRITE-CELL`) | 134,152,961 | 50.0% |
| Encoding them for the wire (`PT-CELL`) | 29,884,613 | 11.1% |
| Building rich frames (`RTHP-PREPARE`) | 90,309,202 | 33.6% |
| Residual glyph scans (`_RGRP-BUILD-BODY`) | 65,536,447 | 24.4% |
| The hybrid producer's scan (`RGRP-BUILD-PAIRED`) | 34,734,310 | 12.9% |
| Desk's shell producer's scan (`_RSHSP-GLYPH-PLAN`) | 30,802,137 | 11.5% |

Within publishing, these checks run once for every cell. Part 10 must show
which of them can change between the cells of one span before any runs less
often:

| Check | Steps | Share |
| --- | ---: | ---: |
| The publisher and the span's memory (`_RTAPTSCB-FEED-VALID?`) | 23,199,866 | 8.6% |
| The engine's storage layout (`_RTAPT-ENGINE-STORAGE?`) | 29,360,281 | 10.9% |
| The engine's cell counts (`_RTAPT-CELL-FEED-READY?`) | 28,115,098 | 10.5% |

Together that is 80,675,245 steps, 30% of the window.

## What this means

Drawing is a small part of a screen change. Publishing is most of it: every
changed cell passes through four layers (APTSCB, RTAPTSCB, RTAPT and PT),
each re-checking state for each cell, and the screen is sometimes sent whole
when little or nothing in it changed. Building the rich frame scans the
whole screen twice for residual glyphs. Typing, scrolling and menus pay the
same per-cell and per-frame costs.

On a device, guest time is steps times average clocks per instruction over
the clock rate. At 2 GHz and one to two clocks an instruction, these 270
million steps would take 0.13 to 0.27 s, up to half of the 0.5 s an
e-paper panel that refreshes twice a second allows for the whole change. At
the 100 MHz FPGA target, they would take about 10 s. These are arithmetic
scenarios, not measurements.
