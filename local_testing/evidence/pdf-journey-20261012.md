# PDFs in File Explorer through the physical viewer — 2026-10-12

Part 14 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"PDFs", checks "File Explorer's check through the physical viewer,
previewing a PDF in CELL and rich, then the Desktop journey". The guarded
launcher `local_testing/physical_desktop_acceptance.py` ran Desk with only
File Explorer, then the canonical Desktop journey, with the native
simulator. Both **passed**.

This is functional regression evidence. The times are the simulator's,
not a device's, and none of this is UART, panel or touch evidence. Guest
step counts for PDFs are step 11's, recorded in the plan from
`local_testing/measure_pdf.py`.

## Bindings

| Binding | Desk with only File Explorer | Canonical Desktop journey |
| --- | --- | --- |
| Akashic | `b8495d36` (tree `15f0e01a`) plus the journey's stages, uncommitted (digest `308ac274…`), committed as `ce1fcb57` | `ce1fcb57` (tree `eb03ed22`), clean |
| MegaPad | `29140c86` (tree `901af5da`), clean | `29140c86` (tree `901af5da`), clean |
| Native extension SHA-256 | `5a06333a…` | `5a06333a…` |
| Launcher SHA-256 | `e5f1b34a…` | `e5f1b34a…` |
| Font | DejaVuSansMono.ttf, `b4a6c3e4…` | the same |

`bindings.json` in each run's artifacts records the full hashes, the
styled faces and the fallback fonts. Neither tree changed during either
run; the launcher enforces that.

Profile and settings: `desktop-apt1-fexp` and `desktop-apt1` in ordinary
source mode; simulator backend with the native executor; 280x84, 18 px
font, 0.75 s action delay, 10 s hold; 900 s watchdog and 3.5 GiB
aggregate-RSS stop. No compiled Forth cache, step-limit change or timing
change was used.

## Runs

| Run | Stages | Result | Wall time | Peak aggregate RSS |
| ---: | ---: | --- | ---: | ---: |
| Desk with only File Explorer (`--applet fexp`) | 34 | pass | 129.9 s | 502 MB |
| Canonical Desktop journey | 55 frames | pass | 247.6 s | 571 MB |

The Desktop image carries the sample PDFs `sample.pdf`, `tagged.pdf` and
`encrypted.pdf` (`local_testing/sample_pdf.py`), the same three-page
document written plainly, with a structure tree, and RC4-encrypted with
the empty user password. Desk with only File Explorer previews them in
195 by 78 cells, after the guide and notes documents of part 12:

- `sample.pdf`'s Preview showed one DOCUMENT from its first page's start,
  the PAGE block labelled 1 at the preview's top and the title a heading
  of level 1, which CELL showed too.
- A FOLLOW on the link "the last page" showed the third page. It is the
  document's last, so the view ended with it: its code paragraph and the
  PAGE block labelled 3 were in view, and CELL showed the code's line.
- The key c, sent once the follow had focused the preview, showed the
  outline in the document's place as a LIST of "A sample PDF", "Lists"
  indented under it, "Pictures" and "The end", with no DOCUMENT shown.
- An OPEN on "Pictures" showed the second page from its start: its label
  and heading, then its JPEG photograph wholly in view and its picture of
  samples below it, each with its own rich IMAGE. CELL beneath the
  photograph said "JPEG, 160 × 100" and drew none of it.
- `encrypted.pdf`, read with the empty password, showed the same title
  from its first page's start.

The journey then went back to the Details tab and went on as before:
`sunset.qoi` shown rich once more, a directory opened, the folder tree
expanded, a child selected and the tree collapsed, and Desk's launcher
opened and closed.

The canonical Desktop journey does not preview a PDF; it ran unchanged as
the regression for the PDF work, the held object streams and the column
layout, and passed.

## What this does not cover

AES-encrypted PDFs (AESV2 and AESV3) still open locked; they wait for the
AES engine's CBC mode. Following links and the outline is checked here on
the sample's short pages; the place a destination names on a longer page,
and pages read only as the view reaches them, are covered by the document
view's and the PDF reader's own tests.
