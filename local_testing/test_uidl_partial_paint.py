"""A key a widget consumes repaints what the widget changed, and no more.

A key the focused element's widget consumed changed what the widget's
revision counts, so UIDL marks the element only when the widget counted no
change.  The paint pass then paints the widget for its moved revision, and
a widget kind with a partial drawer draws only what changed onto a screen
that still holds its last draw: a typed character redraws the text area's
row.  A change the partial drawer does not cover, a widget kind without
one, or a widget under a <scroll> paints whole.  These tests run KDOS and
UIDL-TUI in the native simulator and watch the draws through the widget
draw observer.
"""

from __future__ import annotations

from native_forth import NativeForth

PRELUDE = (
    "VARIABLE _PP-FAILS VARIABLE _PP-CHECKS",
    ': _PP-ASSERT 1 _PP-CHECKS +! 0= IF 1 _PP-FAILS +! ." PP ASSERT " _PP-CHECKS @ . CR THEN ;',
    ': _PP-DONE _PP-FAILS @ 0= IF ." PP PASS " ELSE ." PP FAIL " THEN _PP-CHECKS @ . CR ;',
    "80 24 SCR-NEW SCR-USE",
    "VARIABLE _PP-RGN 0 0 24 80 RGN-NEW _PP-RGN !",
    ": _PP-LOAD ( a u -- ) _PP-RGN @ UTUI-LOAD 0<> _PP-ASSERT ;",
    ": _PP-E ( a u -- elem ) UTUI-BY-ID DUP 0<> _PP-ASSERT ;",
    "VARIABLE _PP-R",
    # A typed character, sent through UIDL's key dispatch.
    "CREATE _PP-EV 24 ALLOT",
    ": _PP-KEY ( char -- handled? ) KEY-T-CHAR _PP-EV ! _PP-EV 8 + ! 0 _PP-EV 16 + !"
    "  _PP-EV UTUI-DISPATCH-KEY ;",
    # Paint under an observer that counts whole and partial draws.
    "VARIABLE _PP-FULL VARIABLE _PP-PART",
    ": _PP-OBS ( widget phase context -- status ) DROP NIP"
    "  DUP WDG-DRAW-PHASE-FULL-BEGIN = IF 1 _PP-FULL +! THEN"
    "  WDG-DRAW-PHASE-PARTIAL = IF 1 _PP-PART +! THEN WDG-DRAW-OBS-S-OK ;",
    ": _PP-PAINT ( -- ) 0 _PP-FULL ! 0 _PP-PART !"
    "  0 ['] _PP-OBS ['] UTUI-PAINT WDG-DRAW-OBSERVE DROP ;",
    # Whether CHAR shows in the first row of ELEM's rectangle.
    "VARIABLE _PP-ROW VARIABLE _PP-COL VARIABLE _PP-W",
    ": _PP-SHOWS? ( char elem -- flag ) UTUI-ELEM-RGN _PP-W ! DROP _PP-COL ! _PP-ROW !"
    "  0 _PP-W @ 0 ?DO _PP-ROW @ _PP-COL @ I + SCR-GET CELL-CP@ 2 PICK = OR LOOP NIP ;",
    # A widget that counts nothing when it consumes a key, or counts a
    # change when _PP-COUNTS is set.
    "CREATE _PP-W1 WDG-HEADER-SIZE ALLOT VARIABLE _PP-COUNTS",
    ": _PP-W1-DRAW ( widget -- ) DROP ;",
    ": _PP-W1-HANDLE ( event widget -- consumed? ) NIP _PP-COUNTS @ IF WDG-DIRTY ELSE DROP THEN -1 ;",
    "_PP-W1 99 0 0 1 1 RGN-NEW ' _PP-W1-DRAW ' _PP-W1-HANDLE WDG-INIT",
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=PRELUDE)

TEXTAREA_DOC = 'S" <uidl><textarea id=t text=hello/></uidl>" _PP-LOAD'
SCROLL_DOC = 'S" <uidl><scroll id=s><textarea id=t text=hello/></scroll></uidl>" _PP-LOAD'
REGION_DOC = 'S" <uidl><region id=r arrange=stack><region id=w/></region></uidl>" _PP-LOAD'


def _run(lines: list[str]) -> str:
    return SUITE.run(lines + ["_PP-DONE"], 400_000_000).decode(errors="replace")


def _passed(output: str, minimum: int) -> None:
    assert "PP PASS" in output, output[-3000:]
    assert int(output.split("PP PASS")[1].split()[0]) >= minimum


def test_a_typed_character_redraws_only_the_text_areas_row():
    _passed(_run([
        TEXTAREA_DOC, 'S" t" _PP-E UTUI-FOCUS! _PP-PAINT _PP-FULL @ 1 = _PP-ASSERT',
        'S" t" _PP-E UIDL-REVISION _PP-R !',
        "0 _UTUI-NEEDS-PAINT ! 120 _PP-KEY _PP-ASSERT",
        # The key marked nothing: the text area counted the change and asked
        # for the paint itself.
        'S" t" _PP-E UIDL-DIRTY? 0= _PP-ASSERT _UTUI-NEEDS-PAINT @ _PP-ASSERT',
        "_PP-PAINT _PP-PART @ 1 = _PP-ASSERT _PP-FULL @ 0= _PP-ASSERT",
        '120 S" t" _PP-E _PP-SHOWS? _PP-ASSERT',
        'S" t" _PP-E UIDL-REVISION _PP-R @ = _PP-ASSERT',
        # Nothing more to paint.
        "_PP-PAINT _PP-PART @ 0= _PP-FULL @ 0= AND _PP-ASSERT",
    ]), 10)


def test_a_change_the_partial_draw_does_not_cover_paints_whole():
    _passed(_run([
        TEXTAREA_DOC, 'S" t" _PP-E UTUI-FOCUS! _PP-PAINT',
        # One interpreted string at a time: they share a buffer.
        'S" t" _PP-E UTUI-WIDGET@ _PP-R ! S" other" _PP-R @ TXTA-SET-TEXT',
        "_PP-PAINT _PP-FULL @ 1 = _PP-ASSERT _PP-PART @ 0= _PP-ASSERT",
        '111 S" t" _PP-E _PP-SHOWS? _PP-ASSERT',
    ]), 4)


def test_a_text_area_under_a_scroll_paints_whole_with_its_thumb():
    _passed(_run([
        SCROLL_DOC, 'S" t" _PP-E UTUI-FOCUS! _PP-PAINT',
        "120 _PP-KEY _PP-ASSERT",
        'S" t" _PP-E UIDL-DIRTY? 0= _PP-ASSERT',
        "_PP-PAINT _PP-FULL @ 1 = _PP-ASSERT _PP-PART @ 0= _PP-ASSERT",
        '120 S" t" _PP-E _PP-SHOWS? _PP-ASSERT',
    ]), 5)


def test_a_key_a_widget_counts_nothing_for_still_marks_its_element():
    _passed(_run([
        REGION_DOC, '_PP-W1 S" w" _PP-E UTUI-WIDGET-SET S" w" _PP-E UTUI-FOCUS! UTUI-PAINT',
        # Consumed, but the widget counted no change: the element is marked
        # as before, and paints whole.
        "0 _PP-COUNTS ! 120 _PP-KEY _PP-ASSERT",
        'S" w" _PP-E UIDL-DIRTY? _PP-ASSERT UTUI-PAINT',
        # Consumed and counted: nothing is marked; the widget, which has no
        # partial drawer, paints whole for its moved revision.
        "-1 _PP-COUNTS ! 120 _PP-KEY _PP-ASSERT",
        'S" w" _PP-E UIDL-DIRTY? 0= _PP-ASSERT',
        "_PP-PAINT _PP-FULL @ 1 = _PP-ASSERT _PP-PART @ 0= _PP-ASSERT",
    ]), 7)


def test_partial_drawers_follow_the_canonical_kinds():
    _passed(_run([
        # A kind past the canonical ones has no place in the table, and its
        # registration writes nothing past it.
        "_WDG-T-LIMIT CELLS _WDG-PARTIALS + @ _PP-R !",
        "' DROP _WDG-T-LIMIT WDG-PARTIAL! _WDG-T-LIMIT CELLS _WDG-PARTIALS + @ _PP-R @ = _PP-ASSERT",
        "WDG-T-TEXTAREA CELLS _WDG-PARTIALS + @ 0<> _PP-ASSERT",
        # A hidden widget, or one whose kind has no drawer, draws nothing.
        "_PP-W1 WDG-DRAW-CHANGED? 0= _PP-ASSERT",
        "_PP-W1 WDG-HIDE _PP-W1 WDG-DRAW-CHANGED? 0= _PP-ASSERT",
    ]), 4)
