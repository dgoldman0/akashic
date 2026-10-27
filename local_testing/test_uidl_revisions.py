"""Each UIDL element counts the changes to it in its revision.

An element's revision is the stamp of its last change, from one count that
every document and context shares, so a revision is never taken twice.  A
change moves it: an attribute, a child, the focus, the layout, the
visibility, the checked state, the widget attached.  A repaint mark alone,
such as a parent marking its children to paint over its background, or the
elements under an overlay that went away, does not.  These tests run KDOS
and UIDL-TUI in the native simulator.
"""

from __future__ import annotations

import re

from native_forth import NativeForth

PRELUDE = (
    "VARIABLE _RV-FAILS VARIABLE _RV-CHECKS",
    ': _RV-ASSERT 1 _RV-CHECKS +! 0= IF 1 _RV-FAILS +! ." RV ASSERT " _RV-CHECKS @ . CR THEN ;',
    ': _RV-DONE _RV-FAILS @ 0= IF ." RV PASS " ELSE ." RV FAIL " THEN _RV-CHECKS @ . CR ;',
    "80 24 SCR-NEW SCR-USE",
    "VARIABLE _RV-RGN 0 0 24 80 RGN-NEW _RV-RGN !",
    ": _RV-LOAD ( a u -- ) _RV-RGN @ UTUI-LOAD 0<> _RV-ASSERT ;",
    ": _RV-E ( a u -- elem ) UTUI-BY-ID DUP 0<> _RV-ASSERT ;",
    ": _RV-REV ( a u -- n ) UTUI-BY-ID UIDL-REVISION ;",
    # The largest revision in the document, and every element's in order.
    ": _RV-ELEM ( i -- elem ) _UDL-ELEMSZ * _UDL-ELEMS + ;",
    "VARIABLE _RV-MAX",
    ": _RV-MAX@ ( -- n ) 0 UIDL-ELEM-COUNT 0 ?DO I _RV-ELEM UIDL-REVISION MAX LOOP ;",
    "CREATE _RV-SAVED 256 CELLS ALLOT",
    ": _RV-SAVE ( -- ) UIDL-ELEM-COUNT 0 ?DO I _RV-ELEM UIDL-REVISION I CELLS _RV-SAVED + ! LOOP ;",
    ": _RV-SAME? ( i -- flag ) DUP _RV-ELEM UIDL-REVISION SWAP CELLS _RV-SAVED + @ = ;",
    ": _RV-ALL-SAME? ( -- flag ) -1 UIDL-ELEM-COUNT 0 ?DO I _RV-SAME? AND LOOP ;",
    ": _RV-INDEX ( a u -- i ) UTUI-BY-ID UIDL-ELEM-INDEX? 0<> _RV-ASSERT ;",
    ": _RV-MOVED? ( a u -- flag ) _RV-INDEX _RV-SAME? 0= ;",
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=PRELUDE)

DOC = (
    'S" <uidl><region id=r arrange=stack><label id=a text=A/>'
    '<action id=b text=B do=go/><action id=c text=C do=go/>'
    '<label id=d text=D/></region></uidl>" _RV-LOAD'
)
DIALOG_DOC = (
    'S" <uidl><region id=r arrange=stack><label id=a text=A/>'
    '<label id=b text=B/><dialog id=g><label id=h text=H/>'
    '<action id=k text=K do=go/></dialog></region></uidl>" _RV-LOAD'
)
MENU_DOC = (
    'S" <uidl><region id=r arrange=stack><menubar id=m><menu id=f text=File>'
    '<item id=i text=Wrap do=wrap/></menu></menubar><label id=a text=A/>'
    '</region></uidl>" _RV-LOAD'
)


def _run(lines: list[str]) -> str:
    return SUITE.run(lines + ["_RV-DONE"], 400_000_000).decode(errors="replace")


def _passed(output: str, minimum: int) -> None:
    assert "RV PASS" in output, output[-3000:]
    assert int(output.split("RV PASS")[1].split()[0]) >= minimum


def test_each_element_has_its_own_revision_and_a_reload_takes_new_ones():
    output = SUITE.run([
        DOC,
        'S" r" _RV-REV . S" a" _RV-REV . S" b" _RV-REV . S" c" _RV-REV . S" d" _RV-REV . CR',
        "_RV-MAX@ _RV-MAX !",
        DOC,
        'S" r" _RV-REV . S" a" _RV-REV . S" b" _RV-REV . S" c" _RV-REV . S" d" _RV-REV . CR',
        "0 UIDL-REVISION . _UDL-ELEMS 8 + UIDL-REVISION . CR",
    ], 400_000_000).decode(errors="replace")
    rows = [list(map(int, line.split())) for line in output.strip().splitlines()[-3:]]
    first, second, nothing = rows
    assert all(first) and len(set(first)) == len(first)
    assert min(second) > max(first) and len(set(second)) == len(second)
    # No element, or a pointer inside a record, has no revision.
    assert nothing == [0, 0]


def test_a_change_moves_the_revision_and_a_mark_alone_does_not():
    _passed(_run([
        DOC, "UTUI-PAINT",
        'S" a" _RV-E DUP UIDL-REVISION _RV-MAX !',
        "DUP UIDL-MARK! DUP UIDL-REVISION _RV-MAX @ = _RV-ASSERT DUP UIDL-DIRTY? _RV-ASSERT",
        "DUP UIDL-CLEAN! DUP UIDL-DIRTY! DUP UIDL-REVISION _RV-MAX @ > _RV-ASSERT",
        "DUP UIDL-DIRTY? _RV-ASSERT DUP UIDL-REVISION _RV-MAX !",
        "DUP UIDL-CLEAN! DUP UIDL-TOUCH DUP UIDL-REVISION _RV-MAX @ > _RV-ASSERT",
        "UIDL-DIRTY? 0= _RV-ASSERT",
        # Touching nothing is harmless.
        "0 UIDL-TOUCH 0 UIDL-REVISION 0= _RV-ASSERT",
    ]), 9)


def test_repainting_the_whole_document_moves_no_revision():
    """A dirty root marks its children as it paints them, which is a
    repaint, not a change."""
    _passed(_run([
        DOC, "UTUI-PAINT _RV-SAVE",
        "UTUI-INVALIDATE UTUI-PAINT _RV-ALL-SAME? _RV-ASSERT",
        'S" r" _RV-E UIDL-MARK! UTUI-PAINT _RV-ALL-SAME? _RV-ASSERT',
    ]), 3)


def test_hiding_an_overlay_moves_its_own_revisions_not_those_under_it():
    _passed(_run([
        DIALOG_DOC, "UTUI-PAINT",
        'S" g" UTUI-SHOW UTUI-PAINT _RV-SAVE',
        'S" g" UTUI-HIDE',
        'S" g" _RV-MOVED? _RV-ASSERT S" h" _RV-MOVED? _RV-ASSERT S" k" _RV-MOVED? _RV-ASSERT',
        # The elements the dialog lay over repaint, unchanged.
        'S" a" _RV-MOVED? 0= _RV-ASSERT S" b" _RV-MOVED? 0= _RV-ASSERT',
        'S" a" _RV-E UIDL-DIRTY? _RV-ASSERT',
        # Showing it again is a change too.
        'UTUI-PAINT _RV-SAVE S" g" UTUI-SHOW S" g" _RV-MOVED? _RV-ASSERT S" h" _RV-MOVED? _RV-ASSERT',
    ]), 8)


def test_attributes_focus_and_layout_move_the_revision():
    _passed(_run([
        DOC, "UTUI-PAINT _RV-SAVE",
        # A new value is a change; writing the same value again is not.
        'S" a" _RV-E S" text" S" X" UTUI-SET-ATTR S" a" _RV-MOVED? _RV-ASSERT',
        'S" b" _RV-MOVED? 0= _RV-ASSERT _RV-SAVE',
        'S" a" _RV-E S" text" S" X" UTUI-SET-ATTR S" a" _RV-MOVED? 0= _RV-ASSERT',
        # An attribute set or removed through UIDL alone counts too.
        'S" d" _RV-E S" role" S" note" UIDL-SET-ATTR S" d" _RV-MOVED? _RV-ASSERT _RV-SAVE',
        'S" d" _RV-E S" role" UIDL-REMOVE-ATTR S" d" _RV-MOVED? _RV-ASSERT',
        # Focus moves the element that loses it and the one that takes it.
        'UTUI-PAINT _RV-SAVE UTUI-FOCUS UIDL-ID S" b" COMPARE 0= _RV-ASSERT',
        'S" c" _RV-E UTUI-FOCUS! S" b" _RV-MOVED? _RV-ASSERT S" c" _RV-MOVED? _RV-ASSERT',
        'S" a" _RV-MOVED? 0= _RV-ASSERT',
        # A relayout is counted as a change of layout.
        "UTUI-PAINT _RV-SAVE UTUI-RELAYOUT",
        'S" a" _RV-MOVED? _RV-ASSERT S" r" _RV-MOVED? _RV-ASSERT',
    ]), 15)


def test_children_widgets_and_checked_items_move_the_revision():
    _passed(_run([
        DOC, "UTUI-PAINT _RV-SAVE _RV-MAX@ _RV-MAX !",
        # A child added to an element, or removed, changes the element.
        'S" r" _RV-E UIDL-T-LABEL UTUI-ADD-ELEM DUP 0<> _RV-ASSERT',
        "DUP UIDL-REVISION _RV-MAX @ > _RV-ASSERT",
        'S" r" _RV-MOVED? _RV-ASSERT UTUI-PAINT _RV-SAVE',
        'UTUI-REMOVE-ELEM S" r" _RV-MOVED? _RV-ASSERT',
        # Moving a child changes both parents, and the child lands last
        # under its new one.
        'UTUI-PAINT _RV-SAVE S" c" _RV-E S" b" _RV-E UIDL-MOVE-ELEM',
        'S" r" _RV-MOVED? _RV-ASSERT S" b" _RV-MOVED? _RV-ASSERT',
        'S" b" _RV-E UIDL-LAST-CHILD S" c" _RV-E = _RV-ASSERT',
        'S" c" _RV-E UIDL-PARENT S" b" _RV-E = _RV-ASSERT',
        # Attaching a widget, or detaching it, changes its element.
        "UTUI-PAINT _RV-SAVE _RV-RGN @ 256 ALLOCATE DROP 256 INP-NEW",
        'DUP S" d" _RV-E UTUI-WIDGET-SET S" d" _RV-MOVED? _RV-ASSERT',
        'UTUI-PAINT _RV-SAVE 0 S" d" _RV-E UTUI-WIDGET-SET S" d" _RV-MOVED? _RV-ASSERT',
        "INP-FREE",
        MENU_DOC, "UTUI-PAINT _RV-SAVE",
        'TRUE S" i" _RV-E UTUI-CHECKED! S" i" _RV-MOVED? _RV-ASSERT',
        'UTUI-PAINT _RV-SAVE TRUE S" i" _RV-E UTUI-CHECKED! S" i" _RV-MOVED? 0= _RV-ASSERT',
    ]), 20)


def test_a_menu_opening_and_closing_moves_its_items_and_menubar():
    _passed(_run([
        MENU_DOC, "UTUI-PAINT _RV-SAVE",
        'S" f" _RV-E _UTUI-MENU-OPEN!',
        'S" f" _RV-MOVED? _RV-ASSERT S" i" _RV-MOVED? _RV-ASSERT S" m" _RV-MOVED? _RV-ASSERT',
        'S" a" _RV-MOVED? 0= _RV-ASSERT',
        "UTUI-PAINT _RV-SAVE _UTUI-MENU-CLOSE",
        'S" f" _RV-MOVED? _RV-ASSERT S" i" _RV-MOVED? _RV-ASSERT S" m" _RV-MOVED? _RV-ASSERT',
    ]), 7)


def test_each_context_keeps_its_revisions_and_shares_the_count():
    """A context's revisions come back with it, and a change made in one
    context takes a stamp no other context has."""
    _passed(_run([
        "VARIABLE _RV-A VARIABLE _RV-B VARIABLE _RV-AR",
        ": _RV-LEAVE ( ctx -- ) UCTX-SAVE UCTX-LIVE-DISOWN ;",
        "UCTX-ALLOC DUP _RV-A ! 0<> _RV-ASSERT UCTX-ALLOC DUP _RV-B ! 0<> _RV-ASSERT",
        "_RV-A @ UCTX-CLEAR _RV-B @ UCTX-CLEAR",
        '_RV-A @ UCTX-RESTORE ' + DOC + ' S" a" _RV-REV _RV-AR ! _RV-A @ _RV-LEAVE',
        '_RV-B @ UCTX-RESTORE ' + DOC + ' S" a" _RV-E UIDL-DIRTY!',
        '_RV-MAX@ _RV-MAX ! _RV-B @ _RV-LEAVE',
        '_RV-A @ UCTX-RESTORE S" a" _RV-REV _RV-AR @ = _RV-ASSERT',
        'S" a" _RV-E UIDL-DIRTY! S" a" _RV-REV _RV-MAX @ > _RV-ASSERT _RV-A @ _RV-LEAVE',
        "_RV-B @ UCTX-FREE _RV-A @ UCTX-FREE",
    ]), 6)


def test_the_context_buffer_holds_the_revisions():
    output = SUITE.run([
        "UCTX-TOTAL . _UCTX-O-REVS . _UCTX-REVS-SZ . _UCTX-O-WREVS . CR",
        "_UDL-REVS 8 UIDL-STORAGE-DISJOINT? . _UDL-STAMP 8 UIDL-STORAGE-DISJOINT? . CR",
    ], 100_000_000).decode(errors="replace")
    total, offset, size, painted = map(int, output.strip().splitlines()[-2].split())
    # The element revisions, then the painted widget revisions, end it.
    assert size == 256 * 8 and offset + size == painted
    assert painted + 256 * 8 == total == 115_968
    # The revisions and their count are UIDL's own storage.
    assert re.fullmatch(r"\s*0\s+0\s*", output.strip().splitlines()[-1])
