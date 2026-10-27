"""An editor made of canonical widgets, each mounted on its own region.

Pad's editor is a tab strip over a text area.  Each is mounted on its own
<region>, laid out by absolute positioning inside the editor's area, so
UIDL lays them out, focuses the text area, sends it its keys and pointer
events, and paints each widget as it changes, with no application code
between.  A typed character redraws its row alone.  The strip is authored
focusable=false: a press on a tab switches the tab and leaves focus, and
so the keys, with the text area.  The text area tells its owner when an
event moves its caret or its selection, which a status line showing the
caret's place follows.  These tests run KDOS and UIDL-TUI in the native
simulator.
"""

from __future__ import annotations

from native_forth import NativeForth

PRELUDE = (
    "VARIABLE _ME-FAILS VARIABLE _ME-CHECKS",
    ': _ME-ASSERT 1 _ME-CHECKS +! 0= IF 1 _ME-FAILS +! ." ME ASSERT " _ME-CHECKS @ . CR THEN ;',
    ': _ME-DONE _ME-FAILS @ 0= IF ." ME PASS " ELSE ." ME FAIL " THEN _ME-CHECKS @ . CR ;',
    "80 24 SCR-NEW SCR-USE",
    "VARIABLE _ME-RGN 0 0 24 80 RGN-NEW _ME-RGN !",
    # A document longer than one interpreted string, built in pieces.
    "CREATE _ME-DOC 1024 ALLOT VARIABLE _ME-N 0 _ME-N !",
    ": _ME+ ( a u -- ) DUP >R _ME-DOC _ME-N @ + SWAP CMOVE R> _ME-N +! ;",
    ": _ME-LOAD ( -- ) _ME-DOC _ME-N @ _ME-RGN @ UTUI-LOAD 0<> _ME-ASSERT ;",
    ": _ME-E ( a u -- elem ) UTUI-BY-ID DUP 0<> _ME-ASSERT ;",
    # Keys, through UIDL's dispatch or straight to a widget.
    "CREATE _ME-EV 24 ALLOT",
    ": _ME-EVENT ( code type -- ev ) _ME-EV ! _ME-EV 8 + ! 0 _ME-EV 16 + ! _ME-EV ;",
    ": _ME-KEY ( char -- handled? ) KEY-T-CHAR _ME-EVENT UTUI-DISPATCH-KEY ;",
    ": _ME-SPECIAL ( code widget -- consumed? ) >R KEY-T-SPECIAL _ME-EVENT R> WDG-HANDLE ;",
    ": _ME-CHAR ( char widget -- consumed? ) >R KEY-T-CHAR _ME-EVENT R> WDG-HANDLE ;",
    # Paint under an observer that counts whole and partial draws.
    "VARIABLE _ME-FULL VARIABLE _ME-PART",
    ": _ME-OBS ( widget phase context -- status ) DROP NIP"
    "  DUP WDG-DRAW-PHASE-FULL-BEGIN = IF 1 _ME-FULL +! THEN"
    "  WDG-DRAW-PHASE-PARTIAL = IF 1 _ME-PART +! THEN WDG-DRAW-OBS-S-OK ;",
    ": _ME-PAINT ( -- ) 0 _ME-FULL ! 0 _ME-PART !"
    "  0 ['] _ME-OBS ['] UTUI-PAINT WDG-DRAW-OBSERVE DROP ;",
    ": _ME-AT ( row col -- char ) SCR-GET CELL-CP@ ;",
    # Stable tab labels; the tab widget borrows them.
    "CREATE _ME-ONE 111 C, 110 C, 101 C,  CREATE _ME-TWO 116 C, 119 C, 111 C,",
    "CREATE _ME-BUF 256 ALLOT VARIABLE _ME-T VARIABLE _ME-TB",
    "VARIABLE _ME-CARETS VARIABLE _ME-CHANGES",
    ": _ME-ON-CARET ( widget -- ) _ME-T @ = _ME-ASSERT 1 _ME-CARETS +! ;",
    ": _ME-ON-CHANGE ( widget -- ) DROP 1 _ME-CHANGES +! ;",
    # A widget that counts the presses it takes.
    "CREATE _ME-W1 WDG-HEADER-SIZE ALLOT CREATE _ME-W2 WDG-HEADER-SIZE ALLOT",
    "CREATE _ME-W3 WDG-HEADER-SIZE ALLOT VARIABLE _ME-PRESSES",
    ": _ME-W-DRAW ( widget -- ) DROP ;",
    ": _ME-W-HANDLE ( event widget -- consumed? ) 2DROP 1 _ME-PRESSES +! -1 ;",
    "_ME-W1 99 0 0 1 1 RGN-NEW ' _ME-W-DRAW ' _ME-W-HANDLE WDG-INIT",
    "_ME-W2 99 0 0 1 1 RGN-NEW ' _ME-W-DRAW ' _ME-W-HANDLE WDG-INIT",
    "_ME-W3 99 0 0 1 1 RGN-NEW ' _ME-W-DRAW ' _ME-W-HANDLE WDG-INIT",
)

SUITE = NativeForth(("tui/uidl-tui.f", "tui/widgets/tabs.f"), prelude=PRELUDE)

EDITOR_DOC = [
    'S" <uidl><region id=area>" _ME+',
    'S" <region id=tabs focusable=false style=position:absolute;height:2/>" _ME+',
    'S" <region id=text style=position:absolute;top:2/>" _ME+',
    'S" </region></uidl>" _ME+ _ME-LOAD',
]

MOUNT = [
    'S" tabs" _ME-E DUP UTUI-ELEM-RGN RGN-NEW 4 TAB-NEW-CAP _ME-TB !',
    "_ME-ONE 3 _ME-TB @ TAB-ADD DROP _ME-TWO 3 _ME-TB @ TAB-ADD DROP",
    "_ME-TB @ SWAP UTUI-WIDGET-SET",
    'S" text" _ME-E DUP UTUI-ELEM-RGN RGN-NEW _ME-BUF 256 TXTA-NEW _ME-T !',
    'S" hello" _ME-T @ TXTA-SET-TEXT _ME-T @ SWAP UTUI-WIDGET-SET',
    'S" text" _ME-E UTUI-FOCUS!',
]


def _run(lines: list[str]) -> str:
    return SUITE.run(lines + ["_ME-DONE"], 400_000_000).decode(errors="replace")


def _passed(output: str, minimum: int) -> None:
    assert "ME PASS" in output, output[-3000:]
    assert int(output.split("ME PASS")[1].split()[0]) >= minimum


def test_the_strip_takes_two_rows_and_the_text_the_rest_of_the_area():
    _passed(_run(EDITOR_DOC + [
        'S" area" _ME-E UTUI-ELEM-RGN 80 = _ME-ASSERT 24 = _ME-ASSERT'
        " 0= _ME-ASSERT 0= _ME-ASSERT",
        'S" tabs" _ME-E UTUI-ELEM-RGN 80 = _ME-ASSERT 2 = _ME-ASSERT'
        " 0= _ME-ASSERT 0= _ME-ASSERT",
        'S" text" _ME-E UTUI-ELEM-RGN 80 = _ME-ASSERT 22 = _ME-ASSERT'
        " 0= _ME-ASSERT 2 = _ME-ASSERT",
    ]), 13)


def test_typing_redraws_a_row_and_a_tab_press_leaves_the_keys_with_the_text():
    _passed(_run(EDITOR_DOC + MOUNT + [
        "_ME-PAINT _ME-FULL @ 2 = _ME-ASSERT _ME-PART @ 0= _ME-ASSERT",
        "0 1 _ME-AT 111 = _ME-ASSERT 2 0 _ME-AT 104 = _ME-ASSERT",
        "_ME-T @ WDG-FOCUSED? _ME-ASSERT",
        # A typed character marks nothing, and its row alone is redrawn.
        "0 _UTUI-NEEDS-PAINT ! 120 _ME-KEY _ME-ASSERT",
        'S" text" _ME-E UIDL-DIRTY? 0= _ME-ASSERT _UTUI-NEEDS-PAINT @ _ME-ASSERT',
        "_ME-PAINT _ME-PART @ 1 = _ME-ASSERT _ME-FULL @ 0= _ME-ASSERT",
        "2 5 _ME-AT 120 = _ME-ASSERT",
        # A press on the second tab switches the tab and keeps the focus.
        "0 8 0 8 KEY-MOUSE-LEFT UTUI-DISPATCH-POINTER _ME-ASSERT",
        "_ME-TB @ TAB-ACTIVE 1 = _ME-ASSERT",
        'UTUI-FOCUS S" text" _ME-E = _ME-ASSERT',
        "_ME-PAINT _ME-FULL @ 1 = _ME-ASSERT",
        # So the next key still goes to the text.
        "121 _ME-KEY _ME-ASSERT _ME-PAINT 2 6 _ME-AT 121 = _ME-ASSERT",
    ]), 17)


def test_the_text_area_tells_its_owner_when_an_event_moves_its_caret():
    _passed(_run([
        "0 0 5 40 RGN-NEW _ME-BUF 256 TXTA-NEW _ME-T !",
        'S" hello" _ME-T @ TXTA-SET-TEXT 0 _ME-T @ TXTA-CURSOR!',
        "' _ME-ON-CARET _ME-T @ TXTA-ON-CARET! ' _ME-ON-CHANGE _ME-T @ TXTA-ON-CHANGE",
        "_ME-T @ TXTA-GENUINE? _ME-ASSERT",
        # A move tells the caret word and edits nothing.
        "KEY-RIGHT _ME-T @ _ME-SPECIAL _ME-ASSERT",
        "_ME-CARETS @ 1 = _ME-ASSERT _ME-CHANGES @ 0= _ME-ASSERT",
        "KEY-LEFT _ME-T @ _ME-SPECIAL _ME-ASSERT _ME-CARETS @ 2 = _ME-ASSERT",
        # A key that leaves the caret where it was tells it nothing.
        "KEY-LEFT _ME-T @ _ME-SPECIAL _ME-ASSERT _ME-CARETS @ 2 = _ME-ASSERT",
        "KEY-DEL _ME-T @ _ME-SPECIAL _ME-ASSERT",
        "_ME-CARETS @ 2 = _ME-ASSERT _ME-CHANGES @ 1 = _ME-ASSERT",
        # Typing edits and moves the caret, so both are told.
        "120 _ME-T @ _ME-CHAR _ME-ASSERT",
        "_ME-CARETS @ 3 = _ME-ASSERT _ME-CHANGES @ 2 = _ME-ASSERT",
        # A selection moves the caret's anchor.
        "KEY-RIGHT KEY-T-SPECIAL _ME-EVENT KEY-MOD-SHIFT OVER 16 + ! _ME-T @ WDG-HANDLE _ME-ASSERT",
        "_ME-CARETS @ 4 = _ME-ASSERT _ME-T @ TXTA-SELECTION? _ME-ASSERT",
        # With no caret word the text area takes its events as before.
        "0 _ME-T @ TXTA-ON-CARET! KEY-RIGHT _ME-T @ _ME-SPECIAL _ME-ASSERT",
        "_ME-CARETS @ 4 = _ME-ASSERT",
    ]), 18)


def test_focusable_false_keeps_focus_from_a_press_and_from_tab():
    _passed(_run([
        'S" <uidl arrange=flex><region id=a/><region id=b focusable=false/><region id=c/></uidl>" _ME+',
        "_ME-LOAD",
        '_ME-W1 S" a" _ME-E UTUI-WIDGET-SET _ME-W2 S" b" _ME-E UTUI-WIDGET-SET',
        '_ME-W3 S" c" _ME-E UTUI-WIDGET-SET _ME-PAINT',
        'S" a" _ME-E UTUI-FOCUS! UTUI-FOCUS-NEXT UTUI-FOCUS S" c" _ME-E = _ME-ASSERT',
        'UTUI-FOCUS-PREV UTUI-FOCUS S" a" _ME-E = _ME-ASSERT',
        # A press on b reaches its widget, and focus stays where it was.
        'S" b" _ME-E UTUI-ELEM-RGN 2DROP 2DUP KEY-MOUSE-LEFT UTUI-DISPATCH-POINTER _ME-ASSERT',
        '_ME-PRESSES @ 1 = _ME-ASSERT UTUI-FOCUS S" a" _ME-E = _ME-ASSERT',
    ]), 9)
