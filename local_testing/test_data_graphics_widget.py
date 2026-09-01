#!/usr/bin/env python3
"""Seconds-scale oracle for the canonical DATA_GRAPHICS widget."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
MODULE = AKASHIC_ROOT / "akashic" / "tui" / "widgets" / "data-graphics.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "data-graphics-widget-byte-oracle"
ORACLE_PATH = "local_testing/dgraph-oracle.f"
SMOKE_MAX_STEPS = 220_000_000
SMOKE_TIMEOUT_SECONDS = 15.0


ORACLE_SOURCE = r'''\ Canonical DATA_GRAPHICS widget oracle.
PROVIDED dgraph-widget-oracle

VARIABLE _dg-fails
VARIABLE _dg-checks
VARIABLE _dg-depth
VARIABLE _dg-screen
VARIABLE _dg-region
VARIABLE _dg-parent
VARIABLE _dg-widget
VARIABLE _dg-bytes
VARIABLE _dg-model-a
VARIABLE _dg-model-u
VARIABLE _dg-scratch-a
VARIABLE _dg-dgf-first

CREATE _dg-graph-s 8199 ALLOT
CREATE _dg-builder-s UDG-BUILDER-SIZE 7 + ALLOT
CREATE _dg-summary-s UDG-SUMMARY-SIZE 7 + ALLOT
CREATE _dg-output-s 8199 ALLOT
CREATE _dg-throw-widget _WDG-HDR-SIZE ALLOT

: _dg-graph _dg-graph-s 7 + -8 AND ;
: _dg-builder _dg-builder-s 7 + -8 AND ;
: _dg-summary _dg-summary-s 7 + -8 AND ;
: _dg-output _dg-output-s 7 + -8 AND ;

: _dg-assert  ( flag -- )
    1 _dg-checks +!
    0= IF
        1 _dg-fails +!
        ." DGRAPH ASSERT " _dg-checks @ . CR
    THEN ;

: _dg-ok  ( status -- )
    DGRAPH-S-OK = _dg-assert ;

: _dg-stack  ( -- )
    DEPTH _dg-depth @ = _dg-assert ;

: _dg-finish  ( -- )
    _dg-builder UDG-END _dg-ok
    _dg-builder UDG-BUILDER-FINISH
    DUP _dg-ok DROP _dg-bytes ! ;

: _dg-build-scratch-utf8  ( -- )
    _dg-graph 8192 _dg-builder UDG-BUILDER-INIT _dg-ok
    100 0 0 12 30 UDG-STATE-VISIBLE UDG-STATE-ENABLED OR
        _dg-builder UDG-BEGIN _dg-ok
    101 0 0 1 4 0 UDG-OBJECT-VISIBLE
        0xFFFFFFFF 0x00000000
        UDG-READOUT-INTEGER 0 42 1 S"  ☃"
        _dg-builder UDG-READOUT _dg-ok
    102 20 0 1 20 0 UDG-OBJECT-VISIBLE
        0xFFFFFFFF 0x00000000
        UDG-READOUT-INTEGER 0 0x8000000000000000 1 0 0
        _dg-builder UDG-READOUT _dg-ok
    103 2 0 1 1 0 UDG-OBJECT-VISIBLE
        0xFFFFFFFF 0x00000000
        UDG-READOUT-INTEGER 0 12345 1 0 0
        _dg-builder UDG-READOUT _dg-ok
    _dg-finish ;

: _dg-build-signed-min  ( -- )
    _dg-graph 8192 _dg-builder UDG-BUILDER-INIT _dg-ok
    200 0 0 12 30 UDG-STATE-VISIBLE UDG-STATE-ENABLED OR
        _dg-builder UDG-BEGIN _dg-ok
    201 0 0 1 20 0 UDG-OBJECT-VISIBLE
        0xFF0000FF 0x0000FFFF UDG-METER-HORIZONTAL
        UDG-METER-SHOW-VALUE
        0x8000000000000000 0 0x8000000000000000
        _dg-builder UDG-METER _dg-ok
    _dg-finish ;

: _dg-build-render  ( -- )
    _dg-graph 8192 _dg-builder UDG-BUILDER-INIT _dg-ok
    300 0 0 12 30 UDG-STATE-VISIBLE UDG-STATE-ENABLED OR
        _dg-builder UDG-BEGIN _dg-ok
    301 0 0 3 3 0 UDG-OBJECT-VISIBLE
        0x00FF00FF 0x00000000
        UDG-READOUT-INTEGER 0 12345 1 0 0
        _dg-builder UDG-READOUT _dg-ok
    302 3 0 1 7 0 UDG-OBJECT-VISIBLE
        0xFF0000FF 0x0000FFFF UDG-METER-HORIZONTAL 0
        0x8000000000000000 0x7FFFFFFFFFFFFFFF 0
        _dg-builder UDG-METER _dg-ok
    303 4 8 4 2 0 UDG-OBJECT-VISIBLE
        0x00FF00FF 0x0000FFFF UDG-METER-VERTICAL 0 0 4 2
        _dg-builder UDG-METER _dg-ok
    304 8 0 1 1 0 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF 0 UDG-STATUS-CIRCLE
        _dg-builder UDG-STATUS _dg-ok
    305 8 2 1 1 0 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF -1 UDG-STATUS-CIRCLE
        _dg-builder UDG-STATUS _dg-ok
    306 8 4 1 1 0 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF 0 UDG-STATUS-SQUARE
        _dg-builder UDG-STATUS _dg-ok
    307 8 6 1 1 0 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF 9 UDG-STATUS-SQUARE
        _dg-builder UDG-STATUS _dg-ok
    308 8 8 1 1 0 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF 0 UDG-STATUS-DIAMOND
        _dg-builder UDG-STATUS _dg-ok
    309 8 10 1 1 0 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF -7 UDG-STATUS-DIAMOND
        _dg-builder UDG-STATUS _dg-ok
    310 1 12 1 1 5 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF -1 UDG-STATUS-DIAMOND
        _dg-builder UDG-STATUS _dg-ok
    311 1 12 1 1 2 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF -1 UDG-STATUS-SQUARE
        _dg-builder UDG-STATUS _dg-ok
    312 1 14 1 1 3 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF -1 UDG-STATUS-CIRCLE
        _dg-builder UDG-STATUS _dg-ok
    313 1 14 1 1 3 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF -1 UDG-STATUS-SQUARE
        _dg-builder UDG-STATUS _dg-ok
    314 10 -2 2 5 0 UDG-OBJECT-VISIBLE
        0xFF0000FF 0x0000FFFF UDG-METER-HORIZONTAL 0 0 4 4
        _dg-builder UDG-METER _dg-ok
    315 -1 28 3 5 0 UDG-OBJECT-VISIBLE
        0xFF0000FF 0x0000FFFF UDG-METER-HORIZONTAL 0 0 4 4
        _dg-builder UDG-METER _dg-ok
    316 6 20 2 4 0 UDG-OBJECT-VISIBLE
        0xFF000000 0x0000FF00 UDG-METER-HORIZONTAL 0 0 4 4
        _dg-builder UDG-METER _dg-ok
    317 8 20 1 1 0 UDG-OBJECT-VISIBLE
        0x77777700 0x00FF0000 -1 UDG-STATUS-CIRCLE
        _dg-builder UDG-STATUS _dg-ok
    _dg-finish ;

: _dg-build-small  ( -- )
    _dg-graph 8192 _dg-builder UDG-BUILDER-INIT _dg-ok
    400 0 0 4 8 UDG-STATE-VISIBLE UDG-STATE-ENABLED OR
        _dg-builder UDG-BEGIN _dg-ok
    401 0 0 1 1 0 UDG-OBJECT-VISIBLE
        0x777777FF 0xFFFFFFFF -1 UDG-STATUS-CIRCLE
        _dg-builder UDG-STATUS _dg-ok
    _dg-finish ;

: _dg-build-huge-meters  ( -- )
    _dg-graph 8192 _dg-builder UDG-BUILDER-INIT _dg-ok
    500 0 0 12 30 UDG-STATE-VISIBLE UDG-STATE-ENABLED OR
        _dg-builder UDG-BEGIN _dg-ok
    501 -2147483648 -2147483648 0xFFFFFFFF 0xFFFFFFFF
        0 UDG-OBJECT-VISIBLE
        0xFF0000FF 0x0000FFFF UDG-METER-HORIZONTAL 0 0 4 4
        _dg-builder UDG-METER _dg-ok
    502 2147483647 2147483647 0xFFFFFFFF 0xFFFFFFFF
        1 UDG-OBJECT-VISIBLE
        0x00FF00FF 0x0000FFFF UDG-METER-VERTICAL 0 0 4 4
        _dg-builder UDG-METER _dg-ok
    _dg-finish ;

: _dg-bind  ( -- )
    _dg-graph _dg-bytes @ _dg-summary _dg-widget @ DGRAPH-BIND _dg-ok ;

: _dg-clear  ( -- )
    [CHAR] . 7 0 0 CELL-MAKE SCR-FILL ;

: _dg-cell-cp=  ( cp row col -- flag )
    SCR-GET CELL-CP@ = ;

: _dg-cell-bg=  ( color row col -- flag )
    SCR-GET CELL-BG@ = ;

: _dg-check-scratch-utf8  ( -- )
    _dg-clear _dg-build-scratch-utf8 _dg-bind
    _dg-widget @ _DGRAPH-O-SCRATCH-U + @ 6 = _dg-assert
    _dg-widget @ _DGRAPH-O-SCRATCH-A + @ DUP 0<> _dg-assert
        _dg-scratch-a !
    _dg-bind
    _dg-widget @ _DGRAPH-O-SCRATCH-A + @
        _dg-scratch-a @ = _dg-assert
    _dg-widget @ WDG-DRAW
    [CHAR] 4 2 3 _dg-cell-cp= _dg-assert
    [CHAR] 2 2 4 _dg-cell-cp= _dg-assert
    32 2 5 _dg-cell-cp= _dg-assert
    0x2603 2 6 _dg-cell-cp= _dg-assert
    [CHAR] . 2 7 _dg-cell-cp= _dg-assert
    [CHAR] # 4 3 _dg-cell-cp= _dg-assert
    _dg-stack ;

: _dg-check-signed-min  ( -- )
    _dg-clear _dg-build-signed-min _dg-bind
    _dg-widget @ _DGRAPH-O-SCRATCH-U + @ 20 = _dg-assert
    _dg-widget @ WDG-DRAW
    [CHAR] - 2 3 _dg-cell-cp= _dg-assert
    [CHAR] 9 2 4 _dg-cell-cp= _dg-assert
    [CHAR] 8 2 22 _dg-cell-cp= _dg-assert
    0 0 255 TUI-RESOLVE-COLOR 2 3 _dg-cell-bg= _dg-assert
    _dg-stack ;

: _dg-check-meters  ( -- )
    255 0 0 TUI-RESOLVE-COLOR
    DUP 5 3 _dg-cell-bg= _dg-assert
    DUP 5 4 _dg-cell-bg= _dg-assert
    5 5 _dg-cell-bg= _dg-assert
    0 0 255 TUI-RESOLVE-COLOR
    DUP 5 6 _dg-cell-bg= _dg-assert
    5 9 _dg-cell-bg= _dg-assert
    0 0 255 TUI-RESOLVE-COLOR
    DUP 6 11 _dg-cell-bg= _dg-assert
    7 11 _dg-cell-bg= _dg-assert
    0 255 0 TUI-RESOLVE-COLOR
    DUP 8 11 _dg-cell-bg= _dg-assert
    9 12 _dg-cell-bg= _dg-assert ;

: _dg-check-statuses  ( -- )
    0x25CB 10 3 _dg-cell-cp= _dg-assert
    0x25CF 10 5 _dg-cell-cp= _dg-assert
    0x25A1 10 7 _dg-cell-cp= _dg-assert
    0x25A0 10 9 _dg-cell-cp= _dg-assert
    0x25C7 10 11 _dg-cell-cp= _dg-assert
    0x25C6 10 13 _dg-cell-cp= _dg-assert
    0x25C6 3 15 _dg-cell-cp= _dg-assert
    0x25A0 3 17 _dg-cell-cp= _dg-assert ;

: _dg-check-clipping  ( -- )
    255 0 0 TUI-RESOLVE-COLOR
    DUP 12 3 _dg-cell-bg= _dg-assert
    DUP 13 5 _dg-cell-bg= _dg-assert
    DUP 2 31 _dg-cell-bg= _dg-assert
    3 32 _dg-cell-bg= _dg-assert
    [CHAR] . 12 2 _dg-cell-cp= _dg-assert
    [CHAR] . 2 33 _dg-cell-cp= _dg-assert
    [CHAR] . 1 31 _dg-cell-cp= _dg-assert ;

: _dg-check-transparent  ( -- )
    [CHAR] . 8 23 _dg-cell-cp= _dg-assert
    [CHAR] . 9 26 _dg-cell-cp= _dg-assert
    [CHAR] . 10 23 _dg-cell-cp= _dg-assert
    [CHAR] . 13 20 _dg-cell-cp= _dg-assert ;

: _dg-check-render  ( -- )
    _dg-clear _dg-build-render _dg-bind
    _dg-widget @ _DGRAPH-O-SCRATCH-U + @ 0= _dg-assert
    _dg-widget @ WDG-DRAW
    [CHAR] # 3 5 _dg-cell-cp= _dg-assert
    [CHAR] . 3 3 _dg-cell-cp= _dg-assert
    _dg-check-meters
    _dg-check-statuses
    _dg-check-clipping
    _dg-check-transparent
    _dg-stack ;

: _dg-capture-ok  ( root-key -- )
    _dg-output _dg-bytes @ _dg-builder _dg-widget @
        DGRAPH-DATA-GRAPHICS-CAPTURE
    DUP _dg-ok DROP _dg-bytes @ = _dg-assert ;

: _dg-check-capture-errors  ( -- )
    0x1122334455667788 _dg-output !
    900 _dg-output _dg-bytes @ 1- _dg-builder _dg-widget @
        DGRAPH-DATA-GRAPHICS-CAPTURE
    DUP DGRAPH-S-CAPACITY = _dg-assert DROP 0= _dg-assert
    _dg-output @ 0x1122334455667788 = _dg-assert
    0x2233445566778899 _dg-output !
    301 _dg-output _dg-bytes @ _dg-builder _dg-widget @
        DGRAPH-DATA-GRAPHICS-CAPTURE
    DUP DGRAPH-S-INVALID = _dg-assert DROP 0= _dg-assert
    _dg-output @ 0x2233445566778899 = _dg-assert
    0x33445566778899AA _dg-output !
    0 _dg-output _dg-bytes @ _dg-builder _dg-widget @
        DGRAPH-DATA-GRAPHICS-CAPTURE
    DUP DGRAPH-S-INVALID = _dg-assert DROP 0= _dg-assert
    _dg-output @ 0x33445566778899AA = _dg-assert ;

: _dg-invalid-capture  ( root-key -- )
    0x445566778899AABB _dg-output !
    _dg-output _dg-bytes @ _dg-builder _dg-widget @
        DGRAPH-DATA-GRAPHICS-CAPTURE
    DUP DGRAPH-S-INVALID = _dg-assert DROP 0= _dg-assert
    _dg-output @ 0x445566778899AABB = _dg-assert ;

: _dg-check-capture-state  ( -- )
    900 _dg-builder _dg-widget @ DGRAPH-DATA-GRAPHICS-MEASURE
    DUP _dg-ok DROP _dg-bytes @ = _dg-assert
    900 _dg-capture-ok
    _dg-output UDG-ROOT-KEY@ 900 = _dg-assert
    _dg-output UDG-ROOT-ROW@ 0= _dg-assert
    _dg-output UDG-ROOT-COLUMN@ 0= _dg-assert
    _dg-output UDG-ROOT-HEIGHT@ 12 = _dg-assert
    _dg-output UDG-ROOT-WIDTH@ 30 = _dg-assert
    _dg-output UDG-ROOT-STATE@ 3 = _dg-assert
    _dg-output UDG-FIRST-RECORD UDG-RECORD-KEY@ 301 = _dg-assert
    _dg-graph UDG-ROOT-KEY@ 300 = _dg-assert
    _dg-output _dg-bytes @ _dg-summary UDG-ENTRY-VALIDATE _dg-ok
    _dg-widget @ WDG-DISABLE
    901 _dg-capture-ok
    _dg-output UDG-ROOT-STATE@ UDG-STATE-VISIBLE = _dg-assert
    _dg-widget @ WDG-HIDE
    902 _dg-capture-ok
    _dg-output UDG-ROOT-STATE@ 0= _dg-assert
    _dg-widget @ WDG-ENABLE
    903 _dg-capture-ok
    _dg-output UDG-ROOT-STATE@ UDG-STATE-ENABLED = _dg-assert
    _dg-widget @ WDG-SHOW
    _dg-check-capture-errors
    _dg-stack ;

: _dg-check-storage-aliases  ( -- )
    _dg-widget @ _DGRAPH-O-MODEL-A + @ _dg-model-a !
    _dg-widget @ _DGRAPH-O-MODEL-U + @ _dg-model-u !
    _DGF-OWNED-START @ _dg-dgf-first !
    _dg-output 8 DGRAPH-STORAGE-DISJOINT? _dg-assert
    _DGRAPH-OWNED-START 1 DGRAPH-STORAGE-DISJOINT? 0= _dg-assert
    _DGF-OWNED-START 1 DGRAPH-STORAGE-DISJOINT? _dg-assert
    _DGF-OWNED-LIMIT @ 1- 1 DGRAPH-STORAGE-DISJOINT? _dg-assert
    _DGF-OWNED-START 1 DGF-STORAGE-DISJOINT? 0= _dg-assert
    _DGF-OWNED-LIMIT @ 1- 1 DGF-STORAGE-DISJOINT? 0= _dg-assert
    _DGF-OWNED-START 1 _dg-widget @
        DGRAPH-DATA-GRAPHICS-STORAGE-DISJOINT? _dg-assert
    0x66778899AABBCCDD _dg-summary !
    _DGF-OWNED-START UDG-HEADER-SIZE _dg-summary _dg-widget @
        DGRAPH-BIND DGRAPH-S-INVALID = _dg-assert
    _dg-summary @ 0x66778899AABBCCDD = _dg-assert
    _dg-widget @ _DGRAPH-O-MODEL-A + @ _dg-model-a @ = _dg-assert
    _dg-widget @ _DGRAPH-O-MODEL-U + @ _dg-model-u @ = _dg-assert
    0x5566778899AABBCC _dg-output !
    910 _dg-output _dg-bytes @ _DGF-OWNED-START _dg-widget @
        DGRAPH-DATA-GRAPHICS-CAPTURE
    DUP DGRAPH-S-INVALID = _dg-assert DROP 0= _dg-assert
    _dg-output @ 0x5566778899AABBCC = _dg-assert
    911 _DGF-OWNED-START 1 _dg-builder _dg-widget @
        DGRAPH-DATA-GRAPHICS-CAPTURE
    DUP DGRAPH-S-INVALID = _dg-assert DROP 0= _dg-assert
    _DGF-OWNED-START @ _dg-dgf-first @ = _dg-assert
    _dg-widget @ _DGRAPH-O-MODEL-A + @ _dg-model-a @ = _dg-assert
    _dg-stack ;

: _dg-bind-invalid  ( -- )
    _dg-graph _dg-bytes @ _dg-summary _dg-widget @ DGRAPH-BIND
        DGRAPH-S-INVALID = _dg-assert ;

: _dg-check-dimensions  ( -- )
    _dg-clear
    2 3 4 8 _dg-region @ RGN-BOUNDS!
    _dg-widget @ WDG-DRAW
    [CHAR] . 3 5 _dg-cell-cp= _dg-assert
    920 _dg-invalid-capture
    _dg-bind-invalid
    _dg-build-small _dg-bind
    _dg-widget @ WDG-DRAW
    0x25CF 2 3 _dg-cell-cp= _dg-assert
    921 _dg-capture-ok
    _dg-output UDG-ROOT-HEIGHT@ 4 = _dg-assert
    _dg-output UDG-ROOT-WIDTH@ 8 = _dg-assert
    2 3 0 8 _dg-region @ RGN-BOUNDS!
    922 _dg-invalid-capture
    _dg-bind-invalid
    2 3 4 0 _dg-region @ RGN-BOUNDS!
    923 _dg-invalid-capture
    _dg-bind-invalid
    2 3 0x100000000 8 _dg-region @ RGN-BOUNDS!
    924 _dg-invalid-capture
    _dg-bind-invalid
    2 3 4 0x100000000 _dg-region @ RGN-BOUNDS!
    925 _dg-invalid-capture
    _dg-bind-invalid
    2 3 4 8 _dg-region @ RGN-BOUNDS!
    _dg-bind
    926 _dg-capture-ok
    2 3 12 30 _dg-region @ RGN-BOUNDS!
    _dg-build-render _dg-bind
    _dg-stack ;

: _dg-check-huge-meters  ( -- )
    _dg-clear _dg-build-huge-meters _dg-bind
    _dg-widget @ WDG-DRAW
    255 0 0 TUI-RESOLVE-COLOR
    DUP 2 3 _dg-cell-bg= _dg-assert
    13 32 _dg-cell-bg= _dg-assert
    [CHAR] . 1 3 _dg-cell-cp= _dg-assert
    [CHAR] . 2 33 _dg-cell-cp= _dg-assert
    _dg-build-render _dg-bind
    _dg-stack ;

: _dg-throw-draw  ( widget -- )
    DROP -777 THROW ;

: _dg-throw-handle  ( event widget -- consumed? )
    2DROP 0 ;

: _dg-throw-in  ( -- )
    _dg-throw-widget _dg-parent @ WDG-DRAW-IN ;

: _dg-check-draw-in  ( -- )
    _dg-parent @ RGN-USE
    _dg-widget @ _dg-parent @ WDG-DRAW-IN
    [CHAR] P 0 0 DRW-CHAR
    [CHAR] P 10 35 _dg-cell-cp= _dg-assert
    _dg-throw-widget WDG-T-LABEL _dg-region @
        ['] _dg-throw-draw ['] _dg-throw-handle WDG-INIT
    _dg-parent @ RGN-USE
    ['] _dg-throw-in CATCH -777 = _dg-assert
    [CHAR] Q 1 1 DRW-CHAR
    [CHAR] Q 11 36 _dg-cell-cp= _dg-assert
    _dg-stack ;

: _dg-run  ( -- )
    0 _dg-fails ! 0 _dg-checks ! DEPTH _dg-depth !
    50 20 SCR-NEW DUP _dg-screen ! SCR-USE
    2 3 12 30 RGN-NEW DUP _dg-region ! DGRAPH-NEW _dg-widget !
    10 35 4 12 RGN-NEW _dg-parent !
    DRW-STYLE-RESET DRW-STYLE-SAVE
    _dg-widget @ WDG-TYPE WDG-T-DATA-GRAPHICS = _dg-assert
    _dg-widget @ DGRAPH-INSTANCE@ 0<> _dg-assert
    _dg-check-scratch-utf8
    _dg-check-signed-min
    _dg-check-render
    _dg-check-capture-state
    _dg-check-storage-aliases
    _dg-check-dimensions
    _dg-check-huge-meters
    _dg-check-draw-in
    RGN-ROOT
    _dg-widget @ DGRAPH-FREE
    _dg-region @ RGN-FREE
    _dg-parent @ RGN-FREE
    _dg-screen @ SCR-FREE
    _dg-stack
    _dg-fails @ 0= IF
        ." DGRAPH PASS " _dg-checks @ .
    ELSE
        ." DGRAPH FAIL " _dg-fails @ . ." / " _dg-checks @ .
    THEN CR ;

_dg-run
'''


AUTOEXEC = rf'''\ autoexec.f - canonical DATA_GRAPHICS widget oracle
ENTER-USERLAND
." [akashic] loading canonical data graphics widget oracle" CR
REQUIRE tui/widgets/data-graphics.f
REQUIRE {ORACLE_PATH}
'''


def test_data_graphics_widget_byte_oracle(tmp_path: Path) -> None:
    source = MODULE.read_text(encoding="utf-8")
    assert "REQUIRE ../data-graphics-format.f" in source
    assert "rich-terminal" not in source
    assert "soundlab" not in source.lower()
    assert "worlds" not in source.lower()
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("tui/widgets/data-graphics.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DGRAPH PASS",),
        stable_markers=("DGRAPH PASS",),
        failure_markers=(
            "DGRAPH FAIL",
            "DGRAPH ASSERT",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(PROFILE_NAME, tmp_path / "data-graphics-widget.img")
        assert smoke(
            PROFILE_NAME,
            image,
            cols=88,
            rows=26,
            max_steps=SMOKE_MAX_STEPS,
            timeout=SMOKE_TIMEOUT_SECONDS,
        )
    finally:
        if previous is None:
            PROFILES.pop(PROFILE_NAME, None)
        else:
            PROFILES[PROFILE_NAME] = previous


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_data_graphics_widget_byte_oracle(Path(directory))
