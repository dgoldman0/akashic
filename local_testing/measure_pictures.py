#!/usr/bin/env python3
"""What a picture costs the device, in guest steps.

This counts the steps on the MegaPad simulator, natively, for a QOI picture:
by default the sample the Desktop image carries (sunset.qoi, 160 by 100
pixels), or any QOI file given with --picture.  Each phase runs on its own:

- the QOI decoder alone, over the whole file;
- rich copies of at most W by H pixels, as the producer asks for an area
  of a terminal that decodes none of the picture's formats: decoding and
  scaling; by default the picture's own size and half of it;
- the CELL view in an area of COLS by ROWS cells: the first draw, which
  starts the CELL copy; decoding it; the first draw of the ready copy,
  which resolves each cell's palette colours; and a redraw, which only
  places cells.

A semantic step is one guest instruction or primitive the simulator
counts.  The counts depend on the picture and the areas, not on the host.

Usage: measure_pictures.py [--picture PATH] [--copy WxH ...]
                           [--area COLSxROWS ...] [--json PATH]
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

STEP_BUDGET = 20_000_000_000


def _setup(width: int, height: int, file_bytes: int) -> str:
    return rf"""
{(file_bytes + 4095) // 4096 * 4096} XBUF MP-FILE
CREATE MP-DEC-MEM QOI-DEC-SIZE 7 + ALLOT
: MP-DEC  MP-DEC-MEM 7 + -8 AND ;
{width * 4} XBUF MP-ROW
CREATE MP-PIC-MEM PIC-SIZE 7 + ALLOT
: MP-PIC  MP-PIC-MEM 7 + -8 AND ;
VARIABLE MP-A  VARIABLE MP-U  VARIABLE MP-ROWS
\ Feed the whole file after its header to the decoder, a row at a time.
: MP-DECODE  ( file-u -- rows )
    QOI-HDR-SIZE - MP-U !  MP-FILE QOI-HDR-SIZE + MP-A !  0 MP-ROWS !
    {width} {height} MP-DEC QOI-DEC-INIT
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
"""


def _steps(runtime, source: str, name: str) -> int:
    result = runtime.evaluate((source + "\n").encode(), source_name=name,
                              step_budget=STEP_BUDGET)
    return result.semantic_steps


def _value_of(runtime, source: str) -> int:
    runtime.evaluate(source.encode(), source_name="value")
    return runtime.main_context.data.pop()


def _size(text: str) -> tuple[int, int]:
    first, second = text.lower().split("x")
    return int(first), int(second)


def measure(picture: bytes, name: str, copies: list[tuple[int, int]],
            areas: list[tuple[int, int]]) -> dict:
    if picture[:4] != b"qoif":
        raise ValueError(f"{name} is not a QOI file")
    width = int.from_bytes(picture[4:8], "big")
    height = int.from_bytes(picture[8:12], "big")
    size = len(picture)
    runtime = _runtime()
    runtime.evaluate(_setup(width, height, size).encode(), source_name="measure-setup")
    runtime.execute("MP-FILE")
    runtime.memory.write_bytes(runtime.main_context.data.pop(), picture)
    _steps(runtime, f"0 MW-MSRC-INIT MP-FILE {size} MW-SRC MEDSRC-MEMORY", "source")
    report = {"picture": {"name": name, "width": width, "height": height,
                          "file_bytes": size}}

    report["decode_only"] = {"steps": _steps(runtime, f"{size} MP-DECODE MP-ROWS !",
                                             "decode")}
    assert _value_of(runtime, "MP-ROWS @") == height

    report["copies"] = []
    for w, h in copies or [(width, height), (width // 2, height // 2)]:
        steps = _steps(runtime, f"{w} {h} MP-COPY DROP", f"copy-{w}x{h}")
        runtime.evaluate(b"MP-PIC PIC-PIXELS", source_name="pixels")
        u = runtime.main_context.data.pop()
        runtime.main_context.data.pop()
        report["copies"].append({"asked": [w, h],
                                 "width": _value_of(runtime, "MP-PIC PIC-WIDTH@"),
                                 "height": _value_of(runtime, "MP-PIC PIC-HEIGHT@"),
                                 "bytes": u, "steps": steps})
        runtime.evaluate(b"MP-PIC PIC-FREE", source_name="free")

    report["cell_views"] = []
    _steps(runtime, "280 84 SCR-NEW DUP MW-SCR ! SCR-USE", "screen")
    for cols, rows in areas:
        view = {"cols": cols, "rows": rows}
        _steps(runtime, (
            f"0 0 {rows} {cols} RGN-NEW MW-RGN ! "
            "MW-RGN @ MW-MSRC PICT-NEW MW-W ! "
            f'MW-SRC S" {Path(name).stem}" MW-W @ PICT-SOURCE!'
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--picture", type=Path,
                        help="a QOI file (default: the Desktop's sample picture)")
    parser.add_argument("--copy", action="append", default=[],
                        help="a rich copy of at most WxH pixels; repeatable "
                             "(default: the picture's size and half of it)")
    parser.add_argument("--area", action="append", default=[],
                        help="a CELL area as COLSxROWS; repeatable")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    if args.picture is None:
        picture, name = akashic_tui.SAMPLE_PICTURE, akashic_tui.SAMPLE_PICTURE_NAME
    else:
        picture, name = args.picture.read_bytes(), args.picture.name
    report = measure(picture, name, [_size(copy) for copy in args.copy],
                     [_size(area) for area in args.area] or [(60, 18)])
    text = json.dumps(report, indent=2)
    if args.json:
        args.json.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
