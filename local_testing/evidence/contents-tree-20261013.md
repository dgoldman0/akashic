# A document's contents as a tree: the physical runs — 2026-10-13

A document's contents (part 14's outline) now show as the canonical tree
widget instead of a list: each entry under the entry above it that is
less deep, every branch open unless the document says it starts closed,
as a PDF's outline may. A rich terminal sees them as a `TREE` item view
with each entry's depth and parent. The guarded launcher
`local_testing/physical_desktop_acceptance.py` ran Desk with only File
Explorer, then the canonical Desktop journey, with the native simulator,
after the `fexplorer` smoke on the emulator. All three **passed**.

This is functional regression evidence. The times are the simulator's,
not a device's, and none of this is UART, panel or touch evidence.

## Bindings

| Binding | All three runs |
| --- | --- |
| Akashic | `fb340b0e` (tree `1486213d`), clean |
| MegaPad | `870848cb` (tree `075a42db`), clean |
| Native extension SHA-256 | `5a06333a…` |
| Launcher SHA-256 | `e5f1b34a…` |
| Font | DejaVuSansMono.ttf, `b4a6c3e4…` |

`bindings.json` in each physical run's artifacts records the full hashes,
the styled faces and the fallback fonts. The smoke ran from the same clean
trees, and neither tree changed during any run; the launcher enforces that
for its two.

Profiles and settings: `desktop-apt1-fexp` and `desktop-apt1` in ordinary
source mode; simulator backend with the native executor; 280x84, 18 px
font, 0.75 s action delay, 10 s hold; 900 s watchdog and 3.5 GiB
aggregate-RSS stop. No compiled Forth cache, step-limit change or timing
change was used.

## Runs

| Run | Stages | Result | Wall time | Peak aggregate RSS |
| ---: | ---: | --- | ---: | ---: |
| `fexplorer` smoke (emulator, CELL) | — | pass | 149.5 s, 3.22 billion steps | — |
| Desk with only File Explorer (`--applet fexp`) | 35 | pass | 138.6 s | 502 MB |
| Canonical Desktop journey | 55 frames | pass | 269.8 s | 551 MB |

The earlier runs with the contents as a list took 127.7 s and 505 MB for
File Explorer's 34 stages, and 244.7 s and 571 MB for the Desktop journey
(`pdf-aes-regression-20261012.md`). File Explorer's journey now has one
more stage. Both physical runs here shared the host with another
project's job using a full core (load average about 5), so their times
measure the host, not the change.

## What File Explorer's run showed

- The key c, sent once the follow had focused the preview, showed
  `sample.pdf`'s outline in the document's place as a `TREE`, inside the
  Preview tab's columns beside the folder tree: "A sample PDF" at depth 0,
  open and expandable, as its `/Count 1` says; "Lists" under it at depth
  1; then "Pictures" and "The end" at depth 0. No `DOCUMENT` showed, and
  CELL showed "Pictures".
- A `COLLAPSE` on "A sample PDF" closed it: the tree showed "A sample
  PDF", closed but still expandable, then "Pictures" and "The end".
- An `OPEN` on "Pictures" showed the second page from its start with its
  two pictures rich, as before.

The `fexplorer` smoke's CELL steps reach the same entries: c showed the
outline, Down twice and Enter chose "Pictures", and the second page
showed.

The canonical Desktop journey shows no document's contents. It ran
unchanged as the regression for the tree widget's changes, its larger
descriptor and its draw path, which Pad's file sidebar uses through its
explorer, and passed.
