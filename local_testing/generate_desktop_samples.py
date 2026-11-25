#!/usr/bin/env python3
"""Write the Desktop's sample files into assets/samples/desktop.

The Desktop carries 41 sample files: the text samples every image carries,
the picture, guide and PDFs that File Explorer previews (sample_pdf.py), and
the notes and lists a person keeps (sample_documents.py).  Images take them
from assets/samples/desktop (akashic_tui._sample_files), and a configuration
names that folder as the first documents of its user volume.  This script is
the only way those files are made; they are never edited by hand.

    python3 local_testing/generate_desktop_samples.py [--check]

``--check`` exits nonzero when the folder differs from what this script
writes, so a test can prove the files are current.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

import qoi_codec  # noqa: E402
import sample_documents  # noqa: E402
import sample_pdf  # noqa: E402
import styled_text  # noqa: E402

AKASHIC_ROOT = LOCAL_TESTING.parent
OUTPUT = AKASHIC_ROOT / "assets" / "samples" / "desktop"

# The day the sample daybook's four records fall on.  A profile whose applet
# shows "today" from them starts its clock at noon UTC on this day
# (akashic_tui.SAMPLE_CLOCK_MS), so the images are the same on every day.
SAMPLE_DATE = "2026-11-24"

DAYBOOK_SAMPLE = (
    "# Daybook\n\n"
    f"- {SAMPLE_DATE} 09:30 | Project review\n"
    f"- [ ] {SAMPLE_DATE} | Plan the next release\n"
    f"- [x] {SAMPLE_DATE} | Morning walk\n"
    f"> {SAMPLE_DATE} | Keep the system small and legible\n"
).encode()

LARGE_SAMPLE = b"".join(
    f"Large fixture line {line:03d}: Pad crosses MP64FS sector boundaries.\n".encode()
    for line in range(1, 49)
)

GRID_SAMPLE = (
    "Item,Qty,Price,Total\n"
    '"Paper, A4",3,12,=B2*C2\n'
    "Ink,2,25,=B3*C3\n"
    "Subtotal,,,=SUM(D2:D3)\n"
).encode()


def _sample_picture() -> bytes:
    """An evening sky over two hills with a low sun, 160 by 100 pixels, as
    QOI.  Integer arithmetic keeps its bytes the same on every host.  The
    corners are rounded with transparent and half-transparent pixels, so a
    viewer's background and blending show."""

    width, height = 160, 100
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            r = 30 + 200 * y // 70
            g = 40 + 110 * y // 70
            b = 120 - 50 * y // 70
            dx, dy = x - 112, y - 60
            if dx * dx + dy * dy < 16 * 16:
                r, g, b = 255, 214, 96
            hill = 66 + (abs(x % 64 - 32) * 3) // 8 - x // 20
            if y >= hill:
                r, g, b = 26, 70 + (y - hill) * 2, 44
            r, g, b = (min(255, max(0, value)) for value in (r, g, b))
            cx, cy = min(x, width - 1 - x), min(y, height - 1 - y)
            alpha = 255
            if cx < 8 and cy < 8:
                distance = (8 - cx) ** 2 + (8 - cy) ** 2
                alpha = 0 if distance > 80 else 128 if distance > 48 else 255
            row.append((r, g, b, alpha))
        rows.append(row)
    return qoi_codec.encode(rows)


# A Markdown document with every kind of block, links to its own headings
# and to other files, and the sample picture as a figure, long enough to
# scroll in File Explorer's preview.
SAMPLE_DOCUMENT = """# A guide to Akashic

Akashic is a library of Forth modules for **MegaPad**. This guide is a
*Markdown* document, which File Explorer shows as a document: headings,
lists, quotes, code and pictures, with the text wrapped to the preview.

- [Notes](notes.md), another document
- [Pictures](#pictures), just below
- [The end](#the-end)

## Pictures

![An evening sky over two hills](sunset.qoi)

The picture above is sunset.qoi, from the same folder.

## Lists

1. Select a file in File Explorer.
2. Its preview shows it the way its kind is shown.
3. A link to a file selects that file and previews it.

- A bullet
  - inside another
    - and one more

## Quotes

> A quote with **strong** words and `code` in it.
>
> - and a list inside the quote

## Code

```
: SQUARE  ( n -- n*n )  DUP * ;
9 SQUARE .
```

---

## Reading

- The wheel scrolls a document three rows a turn.
- A link to a heading, such as [Lists](#lists), scrolls to it.
- A link to a file selects that file and shows it here.

## The end

Back to [the top](#a-guide-to-akashic), or see the [example](example.f) in
Forth.
""".encode()


def desktop_samples() -> dict[str, bytes]:
    """Every sample file by name, as the folder holds them."""

    groups = (
        {
            "welcome.txt": b"Welcome to Akashic.\nThis file is editable in Pad.\n",
            "example.f": b": SQUARE DUP * ;\n9 SQUARE .\n",
            "large.txt": LARGE_SAMPLE,
            "daybook.md": DAYBOOK_SAMPLE,
            styled_text.NOTES_NAME: styled_text.NOTES_MD,
            "grid.csv": GRID_SAMPLE,
        },
        {"sunset.qoi": _sample_picture(), "guide.md": SAMPLE_DOCUMENT},
        sample_pdf.SAMPLES,
        sample_documents.SAMPLES,
    )
    samples: dict[str, bytes] = {}
    for group in groups:
        for name, content in group.items():
            if name in samples:
                raise RuntimeError(f"two samples are named {name}")
            samples[name] = content
    return samples


def differences(folder: Path = OUTPUT) -> list[str]:
    """What FOLDER holds that differs from what this script writes."""

    samples = desktop_samples()
    present = {path.name for path in folder.iterdir()} if folder.is_dir() else set()
    found = [f"missing {name}" for name in sorted(set(samples) - present)]
    found += [f"not a sample: {name}" for name in sorted(present - set(samples))]
    found += [
        f"out of date: {name}"
        for name in sorted(set(samples) & present)
        if (folder / name).read_bytes() != samples[name]
    ]
    return found


def write(folder: Path = OUTPUT) -> None:
    """Make FOLDER hold exactly the sample files."""

    samples = desktop_samples()
    folder.mkdir(parents=True, exist_ok=True)
    for path in folder.iterdir():
        if path.name not in samples:
            path.unlink()
    for name, content in samples.items():
        (folder / name).write_bytes(content)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="report how the folder differs from what this script writes",
    )
    args = parser.parse_args()
    if args.check:
        found = differences()
        for line in found:
            print(line)
        return 1 if found else 0
    write()
    print(f"wrote {len(desktop_samples())} sample files to {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
