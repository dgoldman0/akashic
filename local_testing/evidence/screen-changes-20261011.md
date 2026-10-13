# Screen changes that cost what they change — 2026-10-11

Part 10 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md)
cut the guest work Desk spends publishing a screen change. This records the
photo check, File Explorer's check, typing and the full Desktop journey after
it, against the same checks before it and against the baseline in
[tab-change-profile-20261011.md](tab-change-profile-20261011.md).

Every run used the native simulator, one at a time, under the 900-second
watchdog and the 3.5 GiB aggregate-RSS stop. Guest steps are the simulator's
semantic steps; an accelerated word counts as one. The times are the
simulator's, not a device's, and none of this is UART, panel or touch
evidence.

## Bindings

Every run bound clean source trees, unchanged at exit.

| Binding | Before part 10 | After part 10 |
| --- | --- | --- |
| Akashic | `3f1796e2d11d900df2a11406bf3b18986d05e55d` (tree `ea8c812a695ba5c2886275b877e47672d560b221`) | `4ad1f715da828703c439b05d53e502c63f8eae9a` (tree `e8c7f6d63964d8aea381c1fae5171847a6d19b28`) |
| MegaPad | `1e87765e0835f1eb18f0322a7d4d43bf401a9314` (tree `5d226f5c461fd9c62a5f910968251f859e900f6e`) | the same |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` | the same |
| Launcher SHA-256 | `041009b6efd952200321081ae26d1d9e4132eacd040a75267721ac7ac8efc063` | the same |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` | the same |

"Before" is Akashic `3f1796e2`: part 10's measuring tools and none of its
guest changes. MegaPad's only part 10 change is the profile hooks, so both
sides used `1e87765e`. Both typing sides ran the current typing harness
(SHA-256 `124c5d93b95f33e41b7029d4d91a0db444e57499f388456588e44e0ecdbf427b`),
which differs from the old one only by the profile option.

## Done

- Opening the photo's Preview, until the photograph shows, costs
  **88.4 million guest steps**, at most the 100 million part 10 asked for,
  and down from 266.7 million.
- **No PRESENT carries a CELL cell that did not change**, apart from a new
  session's snapshot. The screen sends a delta as the longest runs of cells
  that differ from what the terminal holds, and a retained-only change as a
  PRESENT with no CELL cells. In the photo check, File Explorer's check and
  the full Desktop journey, the only complete snapshot is each session's
  first.

## The photo check

`local_testing/physical_desktop_acceptance.py --applet photo --screen-profile`:

| | Before | After |
| --- | ---: | ---: |
| Result | passed, 54.0 s | passed, 49.3 s |
| Peak aggregate RSS | 538 MB | 533 MB |
| Guest steps, Preview tab to photograph | 266,723,179 | 88,448,039 |
| The same span on the simulator | 6.63 s | 4.62 s |
| PRESENTs | 5 | 4 |
| Complete CELL snapshots | 2 | 0 |
| CELL cells sent | 62,264 | 15,224 |

The transactions after part 10:

| After activation | CELL | Retained | Bytes | Guest steps before it |
| ---: | --- | --- | ---: | ---: |
| 0.51 s | none | full replacement starts, 208 operations | 41,790 | 42,205,477 |
| 0.64 s | delta, 15,224 cells in 80 spans | replacement continues | 126,168 | 6,684,708 |
| 4.37 s | none | full replacement starts, 131 operations | 17,339 | 32,047,300 |
| 4.43 s | none | replacement continues | 160 | 5,505,053 |

The first two make the tab's frame. The preview draws the picture's label
from its first draw, so the third PRESENT before part 10, a complete snapshot
for the label, is gone. The last two show the photograph once the terminal
holds it, with no CELL cell at all; before part 10 the last one carried the
whole screen again.

Each step, measured on the photo check while it was developed:

| Part 10 step | Guest steps |
| --- | ---: |
| Before (`3f1796e2`) | 266.7 million |
| 2. A retained-only change sends no CELL cells | 164.1 million |
| 3. A picture's first draw is its last | 154.1 million |
| 4. The CELL feed checks once a span | 135.8 million |
| 5. The residual scan skips columns where no claim starts or ends, and claimed stretches | 111.0 million |
| 5. Desk's shell producer takes the hybrid producer's runs, and only rows whose claim rectangles came or went are planned again | 99.2 million |
| 5. A rebuild of the same draw keeps its glyph plan | 88.3 million |

The last step removes a whole second scan. The tab's frame needed more
retained space than the terminal had granted; the hybrid producer asked for
it and, once the terminal answered, built the frame again for the same draw.
The planner reads only the draw's planes, the claims, which of them are
menus, the first object ID, the run text limit and the surface, so the
rebuild now finds all of them unchanged, by a byte comparison of the claims,
and keeps the plan it holds.

### Where the 88.4 million steps go

Each word with everything it calls; rows overlap where one word calls
another.

| Work | Steps | Share |
| --- | ---: | ---: |
| Building rich frames (`RTHP-PREPARE`) | 44,302,618 | 50.1% |
| Desk's shell producer (`_RSHSP-DISPATCH`) | 24,707,222 | 27.9% |
| The hybrid producer's candidate (`_RTHP-BUILD-CANDIDATE`) | 20,840,584 | 23.6% |
| All residual glyph planning (`_RGRP-BUILD-BODY`) | 18,546,801 | 21.0% |
| The hybrid producer's one full scan (`RGRP-BUILD-PAIRED`) | 10,747,974 | 12.2% |
| Publishing the 15,224 changed CELL cells (`_APTSCB-WRITE-CELL`) | 13,566,048 | 15.3% |
| Desk and File Explorer drawing (`DESK-PAINT-CB`) | 12,648,538 | 14.3% |
| The shell proving its storage apart, again at each call (`_RSHSP-AUTHORITY?`) | 7,471,154 | 8.4% |
| The shell emitting its families (`RTE-FAMILY-BATCH-EMIT`) | 6,881,314 | 7.8% |
| The shell's glyph plans, mostly runs taken whole (`_RSHSP-GLYPH-PLAN`) | 5,242,911 | 5.9% |

Before part 10 the per-cell checks of the CELL feed, `_RTAPTSCB-FEED-VALID?`,
`_RTAPT-ENGINE-STORAGE?` and `_RTAPT-CELL-FEED-READY?`, took 80.7 million
steps of the change; now they run once a span and take about 0.5 million.
The shell's glyph planning fell from 30.8 million steps to 5.2 million.

## File Explorer's check

`--applet fexp --screen-profile`. Guest steps are counted from each input
until the next one.

| | Before | After |
| --- | ---: | ---: |
| Result | passed, 94.5 s | passed, 77.6 s |
| Peak aggregate RSS | 487 MB | 485 MB |
| Guest steps over all inputs | 1.914 billion | 0.980 billion |
| Complete CELL snapshots | 11 | 1, the session's first |
| CELL cells sent | 409,710 | 174,512 |

By kind of input:

| Inputs | Before | After |
| --- | ---: | ---: |
| Eight tab changes | 1,420.8 million, 92 to 300 million each | 562.7 million, 61 to 88 million each |
| Five item selections | 149.7 million, 25 to 33 million each | 144.8 million, 25 to 32 million each |
| Opening an item, twice | 135.9 million | 111.1 million |
| Expanding and collapsing a folder | 82.5 million | 63.8 million |
| A key | 125.1 million | 97.4 million |

The journey is the same on both sides. Before part 10 it sent three inputs
twice, a tab change, a selection and an opening, because the first of each
showed nothing in time; those resends are counted in the totals above.

## Typing

`local_testing/physical_typing_cadence.py --screen-profile`, two runs on each
side: one isolated character, then eighteen at five a second, into Pad on the
full Desktop. All nineteen characters showed in every run.

| | Before | After |
| --- | ---: | ---: |
| Isolated character, due to visible | 0.509 s, 0.612 s | 0.576 s, 0.542 s |
| Burst median | 0.718 s, 0.747 s | 0.728 s, 0.631 s |
| Burst worst | 0.983 s, 1.087 s | 0.932 s, 0.819 s |
| Guest steps over the whole run | 704.0 million, 679.6 million | 591.0 million, 591.0 million |

The guest does not idle while typing: from the burst's first character until
its last shows, it builds frames throughout. Measured with the profile, in
the first run on each side:

| Burst of eighteen characters | Before | After |
| --- | ---: | ---: |
| Frames | 11 | 11 |
| Guest steps | 295.0 million | 302.4 million |
| Building rich frames, per frame (`RTHP-PREPARE`) | 22.8 million | 22.9 million |
| Of which the shell's checks and its DELTA build (`_RTHP-EXTENSION-CHECK`) | 10.4 million | 10.1 million |
| Of which the hybrid producer's candidate (`_RTHP-BUILD-CANDIDATE`) | 8.4 million | 8.9 million |
| Residual glyph planning, per frame | 2.2 million | 1.6 million |

Typing's guest work a frame did not change: part 10 cut what a large change
costs, and a typed character changes a few cells. The latency differences
are within the spread of runs on the same side. The run totals fell because
the Desktop's own start, which draws whole screens, got cheaper.

## The full Desktop journey

`local_testing/physical_desktop_acceptance.py --screen-profile`, the
canonical journey with Pad, Daybook, the launcher and Sound Lab, **passed**
in 215.3 s with a peak aggregate RSS of 560 MB. Its only complete CELL
snapshot was the session's first; across the journey 42,548 CELL cells were
sent.

## On a device

Guest time is steps times average clocks per instruction over the clock
rate. With the baseline's assumptions, the photo's 88.4 million steps would
take 0.044 to 0.088 s on a 2 GHz chip at one to two clocks an instruction,
and about 3.3 s at the 100 MHz FPGA target. These are arithmetic scenarios,
not measurements.

## What remains

- The CELL feed still costs about 900 steps for each changed cell through
  its four layers: 13.6 million steps for the tab change's 15,224 cells.
- Desk's shell producer proves its storage apart from everything else on
  every call, 7.5 million steps in the tab change, and emits its families,
  6.9 million.
- A typed character costs about 23 million guest steps a frame, most of it
  the shell's checks and DELTA build and the hybrid producer's candidate,
  none of which part 10 changed.
- The hybrid producer still asks the terminal for more space before
  admitting a frame that has outgrown what it holds; the rebuild after the
  answer now keeps its glyph plan but redoes the rest of the candidate.
