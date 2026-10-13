# A real photograph through the physical viewer — 2026-10-11

The pictures checked until now were the generated 160 by 100 sunset, which
the viewer enlarges by repeating pixels, and its CELL half blocks. The photo
check shows a real photograph instead. It is the baseline for part 9 of the
[rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Pictures the terminal decodes".

The guarded launcher `local_testing/physical_desktop_acceptance.py --applet
photo` ran Desk with File Explorer holding
`assets/pictures/spice-market.qoi`, a public-domain photograph of a spice
stall, 2160 by 1620 pixels and 8,144,442 bytes as QOI, with the native
simulator. It **passed** in 279.4 s with a peak aggregate RSS of 601 MB.

This is functional evidence and a set of guest step counts. The times are the
simulator's, not a device's, and none of this is UART, panel or touch
evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit.

| Binding | Value |
| --- | --- |
| Akashic | `2906f020d6e700830bcfa6834d4c8f24c0a3c21c` (tree `6723350f2d1cea13ed41a2e7f7d6f6da5e29a89f`) |
| MegaPad | `5d61a17f7cd576ee290ce182ead6d69d2241051e` (tree `12a6e4905a580bf7eb2c00cc1c08f343f258d9a6`) |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` |
| Launcher SHA-256 | `b4d5c2323759b87369c82e13bd0d6150bfa2e197688378d8477123b71fd5657a` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

Profile `desktop-apt1-photo` in ordinary source mode, with the settings of
the other single-applet checks and a 600 s journey timeout.

## What the terminal showed

File Explorer's preview took 195 by 78 cells, 2145 by 1638 pixels at the
viewer's 11 by 21 pixel cells. The terminal held a copy of 2145 by 1609
pixels, 13,805,220 bytes of RGBA8, and showed it at that size: the copy fills
the area's width exactly and keeps the photo's shape, so nothing was enlarged.
A crop of the recorded frame at full size shows single seeds and grains
sharply, in full colour. CELL showed the photo's half blocks beneath.

## How long it took

From activating the Preview tab, on the simulator:

| Moment | Seconds after | Guest steps since |
| --- | ---: | ---: |
| "Loading the picture" shown | 1.4 | 0.11 billion |
| CELL view shown | 43.2 | 2.9 billion |
| Rich copy ready | 173.7 | 7.3 billion |
| Upload begun | 175.3 | 7.4 billion |
| Upload committed | 222.0 | 7.5 billion |
| Picture ready in the viewer | 223.5 | 7.5 billion |

The upload of 13,806,372 bytes in 16 chunks took 46.7 s while the guest ran
only 87 million steps: the hosted terminal took the bytes at about 300 KB a
second. That is a host cost, not a device one.

## Guest steps by phase

`local_testing/measure_pictures.py --picture assets/pictures/spice-market.qoi
--copy 2145x1638 --copy 704x756 --area 195x78 --area 64x36` counts each phase
on its own. The copies are those the producer asks for in File Explorer's
preview alone and in the canonical Desk.

| Phase | Steps | Per unit |
| --- | ---: | ---: |
| QOI decode of the whole file | 1,832,961,506 | 524 a pixel |
| Rich copy, 2145 by 1609, with its digest | 4,228,487,381 | |
| That copy's SHA3-256 digest alone | 1,372,199,431 | 99 a byte |
| Rich copy, 704 by 528, with its digest | 2,461,017,925 | |
| CELL copy, 195 by 146, which decodes the file again | 2,254,859,935 | |
| CELL copy, 64 by 48 | 2,237,141,613 | |
| First draw of the ready CELL copy, 195 by 78 cells | 74,193,138 | |

Showing the photo the first time in the larger preview costs about 6.6
billion guest steps. The sunset decoded at 120 steps a pixel because it is
mostly runs; a photograph has few.

## Findings

- The terminal can show a real photograph sharply, one pixel per pixel, at
  more pixels than a 1600 by 1200 colour e-paper panel has.
- The guest's picture work is the cost: decoding, scaling, a digest of the
  raw copy, and a second decode for CELL. Part 9 moves decoding and scaling
  to the terminal, drops the digest, and makes the CELL copy only when CELL
  shows the picture.
- The hosted terminal's upload rate, about 300 KB a second, made the upload
  take 47 s on the simulator. Part 9 finds and removes it.
- The CELL view is half blocks in the 256 xterm colours, and the viewer's
  font leaves gaps between block characters.
