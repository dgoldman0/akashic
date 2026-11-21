#!/usr/bin/env python3
"""The scroll widget's offsets and keys (tui/widgets/scroll.f).

The stack-effect checker of toolchain/language found the scroll words
passing their clamp words ( widget offset -- clamped ) the offset in the
widget's place, and the key handler calling SCRL-SCROLL-BY before its
definition, which KDOS cannot compile.  These cases hold the public words
to their comments on a 10 by 20 viewport over 100 by 50 cells of content,
so the offsets clamp to 0..90 and 0..30:

- SCRL-SCROLL-TO, SCRL-SCROLL-BY and SCRL-ENSURE-VISIBLE take their three
  cells and leave the clamped offsets;
- SCRL-SET-SIZE clamps the offsets to the new content;
- the handler moves by one for an arrow key and by half the viewport for
  Page Up and Page Down, and leaves other keys to its caller.

The indicators are drawn on a screen of their own: with the view at 45 by
15 the thumb sits in row 4 of the right-most column and column 6 of the
bottom row, each on a shaded track.  _SCRL-DRAW-INDICATORS used to divide
the offset by the content size it had first multiplied by, and to read its
column and row from the wrong cells.
"""

from __future__ import annotations

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks


SNAPSHOT = ForthSnapshot(
    ("tui/widgets/scroll.f",),
    prelude=(
        "VARIABLE T-DEPTH",
        ": T{  ( -- )  DEPTH T-DEPTH ! ;",
        ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
        "VARIABLE T-W",
        ": T-DRAW  ( oy ox rgn -- )  DROP 2DROP ;",
        "CREATE T-EV 24 ALLOT",
        ": T-NEW  ( -- )  0 0 10 20 RGN-NEW 100 50 ['] T-DRAW SCRL-NEW T-W ! ;",
        ': T-AT.  ( -- )  T-W @ SCRL-OFFSET SWAP ." at=" . . ;',
        ": T-KEY  ( code type -- consumed? )",
        "    T-EV !  T-EV 8 + !  0 T-EV 16 + !  T-EV T-W @ WDG-HANDLE ;",
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def test_scroll_to_clamps_to_the_content():
    check("inside", [
        ": T1  T-NEW T-W @ 5 7 T{ SCRL-SCROLL-TO }T T-AT. ;",
        "T1",
    ], "cells=-3 at=5 7")
    check("past the end", [
        ": T1  T-NEW T-W @ 95 40 T{ SCRL-SCROLL-TO }T T-AT. ;",
        "T1",
    ], "cells=-3 at=90 30")
    check("before the start", [
        ": T1  T-NEW T-W @ -3 -9 SCRL-SCROLL-TO T-AT. ;",
        "T1",
    ], "at=0 0")


def test_scroll_by_moves_and_clamps():
    check("by a delta", [
        ": T1  T-NEW T-W @ 5 7 SCRL-SCROLL-TO"
        "      T-W @ 3 -2 T{ SCRL-SCROLL-BY }T T-AT. ;",
        "T1",
    ], "cells=-3 at=8 5")
    check("past the end", [
        ": T1  T-NEW T-W @ 200 200 SCRL-SCROLL-BY T-AT. ;",
        "T1",
    ], "at=90 30")


def test_ensure_visible_brings_a_cell_into_view():
    check("below and right", [
        ": T1  T-NEW T-W @ 25 45 T{ SCRL-ENSURE-VISIBLE }T T-AT. ;",
        "T1",
    ], "cells=-3 at=16 26")
    check("above and left", [
        ": T1  T-NEW T-W @ 25 45 SCRL-ENSURE-VISIBLE"
        "      T-W @ 3 2 SCRL-ENSURE-VISIBLE T-AT. ;",
        "T1",
    ], "at=3 2")
    check("already visible", [
        ": T1  T-NEW T-W @ 5 7 SCRL-SCROLL-TO"
        "      T-W @ 9 20 SCRL-ENSURE-VISIBLE T-AT. ;",
        "T1",
    ], "at=5 7")


def test_set_size_clamps_the_offsets():
    check("smaller content", [
        ": T1  T-NEW T-W @ 90 30 SCRL-SCROLL-TO"
        "      T-W @ 20 25 T{ SCRL-SET-SIZE }T T-AT. ;",
        "T1",
    ], "cells=-3 at=10 5")


def test_keys_move_the_view():
    check("arrows and pages", [
        ": T1  T-NEW T-W @ 5 5 SCRL-SCROLL-TO",
        '      KEY-DOWN KEY-T-SPECIAL T-KEY ." down=" . T-AT.',
        '      KEY-RIGHT KEY-T-SPECIAL T-KEY ." right=" . T-AT.',
        '      KEY-UP KEY-T-SPECIAL T-KEY ." up=" . T-AT.',
        '      KEY-LEFT KEY-T-SPECIAL T-KEY ." left=" . T-AT.',
        '      KEY-PGDN KEY-T-SPECIAL T-KEY ." pgdn=" . T-AT.',
        '      KEY-PGUP KEY-T-SPECIAL T-KEY ." pgup=" . T-AT. ;',
        "T1",
    ], "down=-1 at=6 5 right=-1 at=6 6 up=-1 at=5 6 left=-1 at=5 5 "
       "pgdn=-1 at=10 5 pgup=-1 at=5 5")


def test_other_keys_are_left_to_the_caller():
    check("home and a character", [
        ": T1  T-NEW T-W @ 5 5 SCRL-SCROLL-TO",
        "      KEY-HOME KEY-T-SPECIAL T{ T-KEY }T",
        '      ." home=" . T-AT.',
        '      65 KEY-T-CHAR T-KEY ." char=" . T-AT. ;',
        "T1",
    ], "cells=-1 home=0 at=5 5 char=0 at=5 5")


def test_indicators_mark_the_view_on_shaded_tracks():
    check("thumbs and tracks", [
        "20 10 SCR-NEW SCR-USE",
        ": T-CP  ( row col -- cp )  SCR-GET CELL-CP@ ;",
        ": T1  T-NEW T-W @ 45 15 SCRL-SCROLL-TO  SCR-CLEAR",
        "      T-W @ WDG-REGION RGN-USE  T-W @ T{ _SCRL-DRAW-INDICATORS }T",
        '      4 19 T-CP ." vthumb=" .  0 19 T-CP ." vtrack=" .',
        '      9 6 T-CP ." hthumb=" .  9 0 T-CP ." htrack=" .',
        '      0 0 T-CP ." inside=" . ;',
        "T1",
    ], "cells=-1 vthumb=9608 vtrack=9617 hthumb=9608 htrack=9617 inside=32")


if __name__ == "__main__":
    run_file_tests(__file__)
