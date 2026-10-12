# Documents in File Explorer through the physical viewer — 2026-10-12

Part 12 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Documents", is done when "File Explorer previews a Markdown file as a
document in CELL and rich, with wrapped paragraphs, headings, lists, quotes,
code and a picture in the flow; the wheel scrolls it; following a link goes
to its heading or selects its file; and the terminal holds only the blocks in
view". The guarded launcher `local_testing/physical_desktop_acceptance.py`
ran Desk with only File Explorer, with the screen profile, then the canonical
Desktop journey, with the native simulator. Both **passed**.

The record ends with step 10's measurements: the guest steps for opening the
sample, drawing it, a scroll step and following a link, in CELL and rich, and
the bytes a scroll step sends.

This is functional regression evidence and a set of guest step counts. Guest
steps are the simulator's semantic steps; an accelerated word counts as one.
The times are the simulator's, not a device's, and none of this is UART,
panel or touch evidence.

## Bindings

Both runs bound clean source trees, unchanged at exit; the launcher enforces
both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `1aed5ecbc3a2e37fcea6423576a5bd01c9ebbb68` (tree `f32f2f59d2939101205ddc482e48f72e77b5dffe`) |
| MegaPad | `2e1938ab09e5cd8f34e58c6a7e38d1eedb5400ed` (tree `e887ce652aae386e0306ad3bdaa7459ec30d270f`) |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` |
| Launcher SHA-256 | `e5f1b34addac6c8d4556a2cf938bc93f536802750933197424b011a4a75ac316` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The styled faces and fallback fonts are those of part 3; `bindings.json`
records each file's SHA-256.

Profile and settings: `desktop-apt1-fexp` and `desktop-apt1` in ordinary
source mode, which advertise DOCUMENT controls (feature bit 16) beside
pictures; simulator backend with the native executor; 280x84, 18 px font,
0.75 s action delay, 10 s hold; 900 s watchdog and 3.5 GiB aggregate-RSS
stop. No compiled Forth cache, step-limit change or timing change was used.

## Runs

| Run | Stages | Result | Wall time | Peak aggregate RSS |
| --- | ---: | --- | ---: | ---: |
| Desk with only File Explorer (`--applet fexp --screen-profile`) | 25 | pass | 90.6 s | 491 MB |
| Canonical Desktop journey | 58 | pass | 225.1 s | 545 MB |

The sample, `guide.md`, is 1,090 bytes of Markdown with every block kind,
links to its own headings and to `notes.md`, and `sunset.qoi` as a figure,
just after its links. Desk with only File Explorer previews it in 195 by 78
cells. Activating the Preview tab showed it as one DOCUMENT from its first
heading, its paragraphs wrapped to the preview, and its figure whole in view.
The terminal took the figure as its 4,601-byte QOI file and showed it as an
IMAGE in the picture rows the document leaves it, while CELL beneath showed
only what the picture is. The wheel then scrolled the guide by three turns a
step until its end showed. At the second step the figure's top seven rows lay
above the preview: the IMAGE kept the figure's whole rectangle, 50 rows from
above the preview's top, and painted only the 43 rows the document shows, at
the picture's whole size. The link to the first heading scrolled back, and
the link to `notes.md` selected that file and previewed it as a document.

The canonical journey's stages 48 to 50 preview the guide in File Explorer's
tile, 64 by 36 cells, where the figure is whole at the document's top; the
stage waits for it to show rich before it goes back to the Details tab.

A first run of Desk with only File Explorer stopped at the frame with the
figure partly scrolled out: MegaPad's shared-viewer transport decoded an
object's offsets as unsigned, so an IMAGE starting above its region could not
reach the viewer. MegaPad `2e1938ab` carries them signed, as the scene does;
both runs here bind it.

## Measurements

### The document view

`local_testing/measure_documents.py` counts the document view's own guest
steps natively, for the guide at both previews' sizes. CELL alone decodes
the figure and draws it in half blocks; under a rich terminal that takes QOI
files the figure is claimed, and CELL shows what the picture is and decodes
nothing. The picture comes from memory here, not the Desktop's file system.

| Phase | 195x78, CELL | 195x78, rich | 64x36, CELL | 64x36, rich |
| --- | ---: | ---: | ---: | ---: |
| Open: the reader's pass and the view | 243,694 | 243,694 | 243,694 | 243,694 |
| First draw | 7,059,724 | 7,064,160 | 1,357,082 | 1,360,951 |
| The figure's CELL copy | 1,944,109 | none | 4,302,072 | none |
| Draw with the picture | 45,981,617 | 6,388,878 | 7,397,674 | 1,140,296 |
| Redraw | 16,731,878 | 6,388,878 | 2,749,796 | 1,140,296 |
| Each scroll step of nine rows, drawn | 15.1 to 16.8 M | 6.2 to 6.5 M | 1.6 to 2.8 M | 1.0 to 1.2 M |
| End, drawn | 15,084,960 | 6,207,112 | 1,060,724 | 1,049,346 |
| Following the link to the first heading, drawn | 16,835,734 | 6,528,136 | 1,272,901 | 1,278,332 |
| The rich side's capture and DOC1 | 598,489 to 627,304 | the same | 352,566 to 475,129 | the same |

The DOCUMENT entry the capture writes is 2,528 to 2,848 bytes at 195x78 and
1,272 to 2,256 at 64x36, and its DOC1 body 1,346 to 1,464 and 739 to 1,129:
the blocks in view and nothing else.

### Rich frames

From the screen profile of Desk with only File Explorer: each window runs
from an input to the next, about 1.9 s, so its steps include the guest's
idle passes, about 1.4 M a second. A scroll step is the journey's SCROLL of
three wheel turns.

| Window | Guest steps | Desk's draws | Producer's preparation | Presents | PRESENT bytes |
| --- | ---: | ---: | ---: | --- | ---: |
| Preview tab to the guide, figure held | 70,168,183 | 15,007,842 | 26,411,169 | start, continue with CELL, start, continue | 163,818 |
| Scroll step 1 | 68,766,259 | 30,146,733 | 25,886,860 | start, start, continue with CELL | 56,844 |
| Scroll step 2 | 69,105,323 | 29,950,112 | 26,017,944 | start, start, continue with CELL | 59,895 |
| Scroll step 3, to the end | 70,207,082 | 29,491,353 | 26,542,245 | start, start, continue with CELL | 59,138 |
| Following the link to the first heading | 38,439,108 | 14,876,770 | 13,631,569 | start, continue with CELL | 41,357 |
| Following the link to `notes.md` | 29,482,797 | 7,471,147 | 12,779,595 | start, continue with CELL | 27,904 |

The figure's upload is a BEGIN, one chunk of the 4,601-byte file and a
COMMIT, 4,825 bytes in all, in the first window.

### A scroll step's bytes, before and after

| Scroll step with the figure in view | Retained | CELL | In all |
| --- | ---: | ---: | ---: |
| Before figures were rich: one DELTA | 1.5 to 2.0 KB | 54 to 85 KB | 56 to 87 KB |
| Now: two full replacements, then the CELL change | 37.6 to 38.1 KB | 19 to 22 KB | 57 to 60 KB |

"Before" is File Explorer's development run before figures were rich, on
the earlier guide, whose figure also stayed in view as it scrolled, read
from its performance trace.

## Findings

- **A moving figure makes every scroll step a full replacement, and the
  first is thrown away.** A picture that moves changes the static lane's
  shape, so the frame is a full hidden replacement rather than a DELTA. The
  three wheel turns of one step arrive as three wheel events, each drawn:
  the producer starts a replacement for the first, the next two draws land
  before its reveal, and it restarts for the newest. Each step so sends two
  replacements of about 18.7 KB where it sent one DELTA of 2 KB or less
  retained. In all a step sends about what it did, since CELL no longer
  redraws the figure's half blocks, but the retained side's share grew
  about twentyfold. Letting a picture move or change its clip within a DELTA would
  make a scroll step a DELTA again.
- **CELL's figure is CELL's largest cost.** At 195x78 the first draw of the
  ready figure in half blocks costs 46 M steps and each scroll step's draw
  15 to 17 M, against 6.2 to 6.5 M when the rich side claims the figure and
  CELL shows only what it is.
- **Opening and capturing are cheap.** The reader's pass over the guide and
  the view's setup take 0.24 M steps, and the rich side's capture and DOC1
  packing 0.35 to 0.85 M a frame, for the blocks in view only.

## Not covered

- A terminal without DOCUMENT controls, and one that refuses a document's
  space, were not run physically; the producer tests cover both, leaving
  CELL with the reason recorded.
- Reset, resize, reconnect, UART, panel and touch remain open, as for every
  family.
