"""A widget UIDL hosts paints again when it changes, wherever it changes.

UIDL keeps, for each element that hosts a widget, the widget's revision as
it last painted it.  A widget changed from outside UIDL's dispatch, in a
callback, a tick or another widget's callback, asks for a paint through the
hook UIDL-DIRTY! uses, and the paint pass paints its element as if it were
marked, with no application code and no change counted to the element.  A
widget changed while a paint runs, such as a canvas the paint draws on, asks
for no paint, so painting never feeds itself.  These tests run KDOS and
UIDL-TUI in the native simulator.
"""

from __future__ import annotations

from pathlib import Path

from native_forth import NativeForth

ROOT = Path(__file__).resolve().parents[1]

PRELUDE = (
    "VARIABLE _WR-FAILS VARIABLE _WR-CHECKS",
    ': _WR-ASSERT 1 _WR-CHECKS +! 0= IF 1 _WR-FAILS +! ." WR ASSERT " _WR-CHECKS @ . CR THEN ;',
    ': _WR-DONE _WR-FAILS @ 0= IF ." WR PASS " ELSE ." WR FAIL " THEN _WR-CHECKS @ . CR ;',
    "80 24 SCR-NEW SCR-USE",
    "VARIABLE _WR-RGN 0 0 24 80 RGN-NEW _WR-RGN !",
    ": _WR-LOAD ( a u -- ) _WR-RGN @ UTUI-LOAD 0<> _WR-ASSERT ;",
    ": _WR-E ( a u -- elem ) UTUI-BY-ID DUP 0<> _WR-ASSERT ;",
    # A widget that counts its draws and writes W where its region starts.
    "CREATE _WR-W WDG-HEADER-SIZE ALLOT VARIABLE _WR-DRAWS VARIABLE _WR-SELF",
    ": _WR-DRAW ( widget -- ) 1 _WR-DRAWS +!"
    "  87 OVER WDG-REGION RGN-ROW OVER WDG-REGION RGN-COL SCR-GET"
    "  CELL-CP! OVER WDG-REGION RGN-ROW 2 PICK WDG-REGION RGN-COL SCR-SET"
    "  _WR-SELF @ IF DUP WDG-DIRTY THEN DROP ;",
    ": _WR-HANDLE ( event widget -- consumed? ) 2DROP 0 ;",
    "_WR-W 99 0 0 1 1 RGN-NEW ' _WR-DRAW ' _WR-HANDLE WDG-INIT",
    ": _WR-MOUNT ( a u -- ) _WR-W -ROT _WR-E UTUI-WIDGET-SET ;",
    ": _WR-CHANGE ( -- ) _WR-W WDG-DIRTY ;",
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=PRELUDE)

DOC = (
    'S" <uidl><region id=r arrange=stack><label id=a text=A/>'
    '<region id=w/></region></uidl>" _WR-LOAD'
)
SCROLL_DOC = 'S" <uidl><scroll id=s><region id=w/></scroll></uidl>" _WR-LOAD'


def _run(lines: list[str]) -> str:
    return SUITE.run(lines + ["_WR-DONE"], 400_000_000).decode(errors="replace")


def _passed(output: str, minimum: int) -> None:
    assert "WR PASS" in output, output[-3000:]
    assert int(output.split("WR PASS")[1].split()[0]) >= minimum


def test_a_widget_changed_outside_dispatch_paints_with_no_application_code():
    _passed(_run([
        DOC, 'S" w" _WR-MOUNT UTUI-PAINT _WR-DRAWS @ 1 = _WR-ASSERT',
        'S" w" _WR-E UIDL-REVISION _WR-SELF !',
        # The change asks for a paint through UIDL's own hook.
        "0 _UTUI-NEEDS-PAINT ! _WR-CHANGE _UTUI-NEEDS-PAINT @ _WR-ASSERT",
        # The element is not marked and its revision stays: the widget
        # changed, not the element.
        'S" w" _WR-E UIDL-DIRTY? 0= _WR-ASSERT',
        "UTUI-PAINT _WR-DRAWS @ 2 = _WR-ASSERT",
        'S" w" _WR-E UIDL-REVISION _WR-SELF @ = _WR-ASSERT 0 _WR-SELF !',
        # Nothing changed, nothing paints.
        "UTUI-PAINT _WR-DRAWS @ 2 = _WR-ASSERT",
        # A second change paints once more.
        "_WR-CHANGE _WR-CHANGE UTUI-PAINT _WR-DRAWS @ 3 = _WR-ASSERT",
    ]), 8)


def test_a_widget_a_paint_changes_asks_for_no_further_paint():
    """A widget its own draw changes, as a canvas its paint draws on, is
    painted by that paint; it does not ask for another."""
    _passed(_run([
        DOC, 'S" w" _WR-MOUNT',
        "0 _UTUI-NEEDS-PAINT ! -1 _WR-SELF ! ' UTUI-PAINT UTUI-PAINTING",
        "_UTUI-NEEDS-PAINT @ 0= _WR-ASSERT _WR-DRAWS @ 1 = _WR-ASSERT",
        # A change made under UTUI-PAINTING asks for nothing either.
        "0 _WR-SELF ! ' _WR-CHANGE UTUI-PAINTING _UTUI-NEEDS-PAINT @ 0= _WR-ASSERT",
        # Outside a paint the same change asks for one, and the scope ended
        # cleanly even after a throw inside it.
        ": _WR-THROW ( -- ) 1 THROW ;",
        "' _WR-THROW ' UTUI-PAINTING CATCH 1 = _WR-ASSERT DROP",
        "_UTUI-PAINTING @ 0= _WR-ASSERT _WR-CHANGE _UTUI-NEEDS-PAINT @ _WR-ASSERT",
    ]), 6)


def test_a_scroll_paints_before_the_widget_inside_it_changed():
    """A <scroll> shows its child's widget's offset in its thumb, and its
    fill covers the widget, so it paints first and the widget after it."""
    _passed(_run([
        SCROLL_DOC, 'S" w" _WR-MOUNT UTUI-PAINT',
        # Stale cells in the scroll's track and over the widget's first cell.
        'S" s" _WR-E UTUI-ELEM-RGN NIP ROT DROP + 1-',
        "VARIABLE _WR-COL _WR-COL ! 0 _WR-COL @ SCR-GET 81 SWAP CELL-CP! 0 _WR-COL @ SCR-SET",
        "_WR-CHANGE UTUI-PAINT",
        "0 _WR-COL @ SCR-GET CELL-CP@ 81 <> _WR-ASSERT",
        'S" w" _WR-E UTUI-ELEM-RGN 2DROP SCR-GET CELL-CP@ 87 = _WR-ASSERT',
        "_WR-DRAWS @ 2 = _WR-ASSERT",
    ]), 5)


def test_shells_and_hosts_paint_under_the_scope_and_turn_tick_requests_into_slots():
    shell = (ROOT / "akashic/tui/app-shell.f").read_text()
    host = (ROOT / "akashic/tui/applet-host/host.f").read_text()
    root_paint = shell[shell.index(": _ASHELL-PAINT  ( -- )"):]
    root_paint = root_paint[:root_paint.index("\n;") if "\n;" in root_paint else None]
    assert "['] _ASHELL-PAINT-BODY UTUI-PAINTING" in root_paint
    assert ": _ASPC-PAINT  ( -- )  ['] _ASPC-DRAW-BODY UTUI-PAINTING ;" in shell
    assert "['] _ASPC-PAINT UTUI-DRAW-OBSERVE" in shell
    tick = host[host.index(": AHOST-TICK  ( host -- )"):host.index("REPEAT\n    _AHTI-PAINT @ _UTUI-NEEDS-PAINT ! ;")]
    # Each child's tick starts with no request, and one it raises marks
    # its slot; the request live before is kept.
    assert tick.index("0 _UTUI-NEEDS-PAINT !") < tick.index("APP.TICK-XT @")
    assert "CINST.REVISION @ <> _UTUI-NEEDS-PAINT @ OR IF" in tick
    assert "_UTUI-NEEDS-PAINT @ _AHTI-PAINT !" in tick
