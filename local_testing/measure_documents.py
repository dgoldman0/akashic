#!/usr/bin/env python3
"""What a document costs the device's document view, in guest steps.

This counts the steps on the MegaPad simulator, natively, for the sample
document the Desktop image carries (guide.md, with sunset.qoi as a figure),
shown in a document view of each area given, in each phase on its own:

- opening it: the Markdown reader's pass over the file for the document's
  structure, and the view;
- the first draw, which lays out the blocks in view and keeps their
  contents;
- for CELL alone, decoding the figure's CELL copy;
- the draw with the picture, and a redraw;
- the rich side's capture of the blocks in view, its DOCUMENT entry, and
  their DOC1 packing, before and after the scrolls;
- three scroll steps of nine rows, each drawn;
- the End key, drawn; and following the link to the first heading, drawn.

Each area is measured twice: for CELL alone, where the figure's picture is
decoded and drawn in half blocks, and as under a rich terminal that takes
QOI files, which claims the figure, so CELL shows what the picture is and
decodes nothing.

A semantic step is one guest instruction or primitive the simulator
counts.  The counts depend on the document and the area, not on the host.
The picture comes from memory here rather than the Desktop's file system,
and the screen producer's own work for a rich frame is not counted: the
physical run's screen profile counts that.

Usage: measure_documents.py [--area COLSxROWS ...] [--json PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import akashic_tui  # noqa: E402
import test_document_view as view  # noqa: E402

DOCUMENT = akashic_tui.SAMPLE_DOCUMENT
PICTURE = akashic_tui.SAMPLE_PICTURE
SCROLL_ROWS = 9
SCROLLS = 3


def _steps(runtime, line: str) -> int:
    result = runtime.evaluate((line + "\n").encode(), source_name="measure",
                              step_budget=4_000_000_000)
    return result.semantic_steps


def measure(cols: int, rows: int, rich: bool) -> dict:
    runtime = view._runtime(DOCUMENT, PICTURE)
    runtime.evaluate(("\n".join(view.CAPTURE_SETUP) + "\n").encode(),
                     source_name="capture-setup")
    for line in ("0 DV-MSRC-INIT", "300 100 SCR-NEW SCR-USE",
                 f"0 0 {rows} {cols} RGN-NEW DV-RGN !  {rows} DV-H !"):
        _steps(runtime, line)
    if rich:
        # A capture tells pictures the files the rich side takes.
        _steps(runtime, "1 PIC-F-QOI 1- LSHIFT PICT-RICH-FORMATS!")
    phases = {
        "open": _steps(runtime, f"DV-FILE {len(DOCUMENT)} DV-OPEN"),
        "first draw": _steps(runtime, "DV-DRAW"),
    }
    if rich:
        # The capture claims the figure the rich side shows.
        _steps(runtime, "0 DV-W @ DOCV-FIGURE@ NIP ?DUP IF -1 SWAP PICT-CLAIM! THEN")
    else:
        phases["CELL copy of the figure"] = _steps(runtime, "DV-SERVICE")
    phases["draw with the picture"] = _steps(runtime, "DV-DRAW")
    phases["redraw"] = _steps(runtime, "DV-DRAW")
    phases["rich capture and DOC1"] = _steps(runtime, "DV-CAPTURE")
    phases["scroll step and draw"] = [
        _steps(runtime, f"{SCROLL_ROWS} DV-W @ DOCV-SCROLL DV-DRAW") for _ in range(SCROLLS)
    ]
    phases["rich capture and DOC1 after the scrolls"] = _steps(runtime, "DV-CAPTURE")
    phases["End and draw"] = _steps(runtime, "KEY-END DV-KEY DV-DRAW")
    phases["follow the link to the first heading and draw"] = _steps(
        runtime, 'S" #a-guide-to-akashic" DV-W @ DOCV-FOLLOW DV-DRAW')
    output = runtime.drain_uart_output().decode("utf-8", errors="replace")
    _steps(runtime, "DV-CLOSE")
    return {
        "area": [cols, rows],
        "mode": "rich" if rich else "CELL",
        "phases": phases,
        "entry_bytes": [int(value) for value in re.findall(r"BYTES=(\d+)", output)],
        "doc1_bytes": [len(packed) // 2
                       for packed in re.findall(r"@@BYTES ([0-9a-f]*)", output)],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--area", action="append", default=[], metavar="COLSxROWS",
                        help="a view's size in cells; File Explorer's previews by default")
    parser.add_argument("--json", type=Path, help="also write the counts here")
    args = parser.parse_args()
    areas = [tuple(int(part) for part in area.split("x")) for area in args.area]
    report = [measure(cols, rows, rich)
              for cols, rows in areas or ((195, 78), (64, 36)) for rich in (False, True)]
    text = json.dumps(report, indent=2)
    print(text)
    if args.json is not None:
        args.json.write_text(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
