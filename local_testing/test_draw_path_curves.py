#!/usr/bin/env python3
"""A path's segments start where the last one ended (render/draw.f).

The stack-effect checker of toolchain/language found DRAW-PATH-QUAD
( cx cy x y -- ) and DRAW-PATH-CUBIC ( c1x c1y c2x c2y x y -- ) setting
the path's cursor from the caller's cells: the Bezier flatten words take
every point, so nothing was left of the destination when the cursor was
set.  DRAW-PATH-MOVE ( x y -- ) took the caller's two cells for its
bounding box, and DRAW-PATH-LINE ( x y -- ) gave the rasterizer its points
in the wrong order and then stored the cursor from an empty stack.  Each
case moves, draws a curve, then a line from the curve's end, and reads the
cursor and the line's edge from the rasterizer's table, with a cell below
that must survive.
"""

from __future__ import annotations

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks


SNAPSHOT = ForthSnapshot(
    ("render/draw.f",),
    prelude=(
        "VARIABLE T-DEPTH",
        ": T{  ( -- )  DEPTH T-DEPTH ! ;",
        ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
        ': T-AT.  ( -- )  ." at=" _DRAW-PATH-CX @ . _DRAW-PATH-CY @ . ;',
        "\\ The last edge's start, as the rasterizer keeps it.",
        ": T-EDGE.  ( -- )  RAST-NEDGES 1- CELLS"
        '    ." from=" DUP _RST-EX0 + @ . _RST-EY0 + @ . ;',
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def test_quad_moves_the_cursor_to_its_end():
    check("quadratic", [
        ": T1  77 DRAW-PATH-BEGIN 2 3 DRAW-PATH-MOVE",
        "      7 10 20 30 T{ DRAW-PATH-QUAD }T T-AT.",
        '      25 35 DRAW-PATH-LINE T-EDGE. T-AT. ." below=" . ;',
        "T1",
    ], "cells=-4 at=20 30 from=20 30 at=25 35 below=77")


def test_cubic_moves_the_cursor_to_its_end():
    check("cubic", [
        ": T1  77 DRAW-PATH-BEGIN 2 3 DRAW-PATH-MOVE",
        "      5 5 15 25 40 8 T{ DRAW-PATH-CUBIC }T T-AT.",
        '      45 18 DRAW-PATH-LINE T-EDGE. T-AT. ." below=" . ;',
        "T1",
    ], "cells=-6 at=40 8 from=40 8 at=45 18 below=77")


def test_move_takes_its_point_for_the_bounds():
    check("bounding box", [
        ": T1  77 DRAW-PATH-BEGIN 4 9 DRAW-PATH-MOVE 6 2 DRAW-PATH-LINE",
        '      ." x=" _DRAW-PATH-MINX @ . _DRAW-PATH-MAXX @ .',
        '      ." y=" _DRAW-PATH-MINY @ . _DRAW-PATH-MAXY @ .',
        '      ." below=" . ;',
        "T1",
    ], "x=4 6 y=2 9 below=77")


if __name__ == "__main__":
    run_file_tests(__file__)
