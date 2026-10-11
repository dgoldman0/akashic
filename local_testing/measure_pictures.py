#!/usr/bin/env python3
"""What the Desktop's sample picture costs the device, in guest steps.

The picture plan's step 8 asks for the guest steps a picture takes to
decode, to scale, to digest and to draw in CELL, beside the bytes an upload
sends and how long the screen waits for it.  This script counts the steps
on the MegaPad simulator, natively, for the sample picture the Desktop
image carries (sunset.qoi, 160 by 100 pixels), in each phase on its own:

- the QOI decoder alone, over the whole file;
- a copy at the picture's own size, as the rich terminal gets it here:
  decoding, each row copied, and its SHA3-256 digest;
- a copy at half size: decoding, averaging and the smaller copy's digest;
- SHA3-256 alone over each copy's bytes;
- the CELL view in an area of COLS by ROWS cells: the first draw, which
  starts the CELL copy; decoding it; the first draw of the ready copy,
  which resolves each cell's palette colours; and a redraw, which only
  places cells.

A semantic step is one guest instruction or primitive the simulator
counts.  The counts depend on the picture and the area, not on the host.

Usage: measure_pictures.py [--area COLSxROWS ...] [--json PATH]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import akashic_tui  # noqa: E402
from test_media_widget import _runtime  # noqa: E402

PICTURE = akashic_tui.SAMPLE_PICTURE
WIDTH, HEIGHT = 160, 100

SETUP = r"""
CREATE MP-DEC-MEM QOI-DEC-SIZE 7 + ALLOT
: MP-DEC  MP-DEC-MEM 7 + -8 AND ;
CREATE MP-ROW-MEM 160 4 * 7 + ALLOT
: MP-ROW  MP-ROW-MEM 7 + -8 AND ;
CREATE MP-PIC-MEM PIC-SIZE 7 + ALLOT
: MP-PIC  MP-PIC-MEM 7 + -8 AND ;
CREATE MP-HASH-MEM SHA3-256-CONTEXT-SIZE 7 + ALLOT
: MP-HASH  MP-HASH-MEM 7 + -8 AND ;
CREATE MP-DIGEST 32 ALLOT
VARIABLE MP-A  VARIABLE MP-U  VARIABLE MP-ROWS
\ Feed the whole file after its header to the decoder, a row at a time.
: MP-DECODE  ( file-u -- rows )
    QOI-HDR-SIZE - MP-U !  MW-FILE QOI-HDR-SIZE + MP-A !  0 MP-ROWS !
    160 100 MP-DEC QOI-DEC-INIT
    BEGIN
        MP-A @ MP-U @ MP-ROW MP-DEC QOI-DEC-FEED      ( used status )
        SWAP DUP MP-A +! NEGATE MP-U +!
        DUP QOI-S-ROW = IF 1 MP-ROWS +! THEN
        DUP QOI-S-DONE = SWAP QOI-S-BAD = OR MP-U @ 0= OR
    UNTIL MP-ROWS @ ;
\ A copy of at most W by H pixels, decoded to the end.
: MP-COPY  ( w h -- state )
    MW-SRC MW-MSRC MP-PIC PIC-START DROP
    BEGIN 1000000 MP-PIC PIC-STEP DUP PIC-ST-PENDING = WHILE DROP REPEAT ;
: MP-DIGEST-OF  ( a u -- )
    MP-HASH SHA3-256-CONTEXT-INIT DROP
    MP-HASH SHA3-256-CONTEXT-UPDATE DROP
    MP-DIGEST MP-HASH SHA3-256-CONTEXT-FINAL DROP ;
"""


def _steps(runtime, source: str, name: str) -> int:
    result = runtime.evaluate((source + "\n").encode(), source_name=name,
                              step_budget=2_000_000_000)
    return result.semantic_steps


def measure(areas: list[tuple[int, int]]) -> dict:
    runtime = _runtime(PICTURE)
    runtime.evaluate(SETUP.encode(), source_name="measure-setup")
    size = len(PICTURE)
    _steps(runtime, f"0 MW-MSRC-INIT MW-FILE {size} MW-SRC MEDSRC-MEMORY", "source")
    report = {"picture": {"name": akashic_tui.SAMPLE_PICTURE_NAME, "width": WIDTH,
                          "height": HEIGHT, "file_bytes": size}}

    report["decode_only"] = {"steps": _steps(runtime, f"{size} MP-DECODE MP-ROWS !",
                                             "decode")}
    assert runtime.memory.read64(runtime.dictionary.find(b"MP-ROWS").body_address) == HEIGHT

    for name, (w, h) in (("copy_full", (WIDTH, HEIGHT)), ("copy_half", (WIDTH // 2, HEIGHT // 2))):
        steps = _steps(runtime, f"{w} {h} MP-COPY DROP", name)
        runtime.evaluate(b"MP-PIC PIC-PIXELS", source_name="pixels")
        u = runtime.main_context.data.pop()
        a = runtime.main_context.data.pop()
        digest = _steps(runtime, f"{a} {u} MP-DIGEST-OF", name + "-digest")
        report[name] = {"width": _value_of(runtime, "MP-PIC PIC-WIDTH@"),
                        "height": _value_of(runtime, "MP-PIC PIC-HEIGHT@"),
                        "bytes": u, "steps": steps, "digest_steps": digest}
        runtime.evaluate(b"MP-PIC PIC-FREE", source_name="free")

    report["cell_views"] = []
    _steps(runtime, "280 84 SCR-NEW DUP MW-SCR ! SCR-USE", "screen")
    for cols, rows in areas:
        view = {"cols": cols, "rows": rows}
        _steps(runtime, (
            f"0 0 {rows} {cols} RGN-NEW MW-RGN ! "
            "MW-RGN @ MW-MSRC PICT-NEW MW-W ! "
            'MW-SRC S" sunset" MW-W @ PICT-SOURCE!'
        ), "cell-setup")
        view["first_draw_steps"] = _steps(runtime, "MW-W @ MW-DRAW", "cell-first-draw")
        view["decode_steps"] = _steps(runtime, "MW-W @ MW-PICT-SERVICE DROP", "cell-decode")
        view["ready_draw_steps"] = _steps(runtime, "MW-W @ MW-DRAW", "cell-ready-draw")
        view["redraw_steps"] = _steps(runtime, "MW-W @ MW-DRAW", "cell-redraw")
        view["copy_width"] = _value_of(runtime, "MW-W @ PICT-CELL-COPY@ PIC-WIDTH@")
        view["copy_height"] = _value_of(runtime, "MW-W @ PICT-CELL-COPY@ PIC-HEIGHT@")
        _steps(runtime, "MW-W @ PICT-FREE MW-RGN @ RGN-FREE", "cell-free")
        report["cell_views"].append(view)
    return report


def _value_of(runtime, source: str) -> int:
    runtime.evaluate(source.encode(), source_name="value")
    return runtime.main_context.data.pop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--area", action="append", default=[],
                        help="a CELL area as COLSxROWS; repeatable")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    areas = [tuple(int(n) for n in area.lower().split("x")) for area in args.area] or [(60, 18)]
    report = measure(areas)
    text = json.dumps(report, indent=2)
    if args.json:
        args.json.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
