"""An observation made in several passes holds the relations it checked.

The rich side captures a document family by family, and each family's
passes check every relation that mounts a widget on an element.  Between
the passes nothing runs but the captures, so UTUI-HOLD checks the relations
once and each pass then finds them checked.  The hold lasts as long as the
observation, in the context it checked them in, and holds nothing when the
relations do not hold when it begins.  These checks break the ledger on
purpose to see which check runs.  They run KDOS and UIDL-TUI in the native
simulator.
"""

from __future__ import annotations

from native_forth import NativeForth

PRELUDE = (
    "VARIABLE _RH-FAILS VARIABLE _RH-CHECKS",
    ': _RH-ASSERT 1 _RH-CHECKS +! 0= IF 1 _RH-FAILS +! ." RH ASSERT " _RH-CHECKS @ . CR THEN ;',
    ': _RH-DONE _RH-FAILS @ 0= IF ." RH PASS " ELSE ." RH FAIL " THEN _RH-CHECKS @ . CR ;',
    # A relation no check accepts, and the ledger made of it alone.
    "CREATE _RH-BAD _UTUI-MC-REL-SIZE ALLOT _RH-BAD _UTUI-MC-REL-SIZE 0 FILL",
    ": _RH-BREAK ( -- ) _RH-BAD _UTUI-MC-HEAD ! 1 _UTUI-MC-COUNT ! ;",
    ": _RH-MEND ( -- ) 0 _UTUI-MC-HEAD ! 0 _UTUI-MC-COUNT ! ;",
    ": _RH-READY? ( -- flag ) _UTUI-MC-RELATIONS-READY? 0<> ;",
    ": _RH-BROKEN-READY? ( -- flag ) _RH-BREAK _RH-READY? _RH-MEND ;",
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=PRELUDE)


def _run(lines: list[str]) -> str:
    return SUITE.run(lines + ["_RH-DONE"], 200_000_000).decode(errors="replace")


def test_a_hold_checks_the_relations_once_for_the_passes_inside_it():
    out = _run([
        # With no relations they hold; a broken ledger does not.
        "_RH-READY? _RH-ASSERT _RH-BROKEN-READY? 0= _RH-ASSERT",
        # Inside a hold a pass finds them as the hold checked them, and the
        # observation's own results come back.
        ": _RH-INSIDE ( -- n ) _RH-BROKEN-READY? _RH-ASSERT 7 ;",
        "' _RH-INSIDE UTUI-HOLD 7 = _RH-ASSERT",
        # Once the hold ends they are checked again.
        "_RH-BROKEN-READY? 0= _RH-ASSERT _UTUI-MC-HELD @ 0= _RH-ASSERT",
    ])
    assert "RH PASS 6" in out, out


def test_a_hold_holds_nothing_the_check_did_not_find():
    out = _run([
        # A ledger broken when the hold begins holds nothing.
        ": _RH-BROKEN ( -- ) _RH-READY? 0= _RH-ASSERT ;",
        "_RH-BREAK ' _RH-BROKEN UTUI-HOLD _RH-MEND",
        # Nor does a hold in another context than the one it checked.
        ": _RH-OTHER ( -- ) _UCTX-LIVE-OWNER @ 99 _UCTX-LIVE-OWNER !",
        "    _RH-BROKEN-READY? 0= _RH-ASSERT _UCTX-LIVE-OWNER ! ;",
        "' _RH-OTHER UTUI-HOLD",
        # Nor a ledger whose status went bad during the hold.
        ": _RH-INVALID ( -- ) _UTUI-MC-S-INVALID _UTUI-MC-STATUS !",
        "    _RH-READY? 0= _RH-ASSERT _UTUI-MC-S-OK _UTUI-MC-STATUS ! ;",
        "' _RH-INVALID UTUI-HOLD",
        "_RH-READY? _RH-ASSERT",
    ])
    assert "RH PASS 4" in out, out


def test_a_nested_hold_keeps_the_outer_one_and_a_throw_ends_it():
    out = _run([
        ": _RH-NOTHING ( -- ) ;",
        ": _RH-NESTED ( -- ) ['] _RH-NOTHING UTUI-HOLD _RH-BROKEN-READY? _RH-ASSERT ;",
        "' _RH-NESTED UTUI-HOLD",
        "_UTUI-MC-HELD @ 0= _RH-ASSERT",
        ": _RH-THROWS ( -- ) 33 THROW ;",
        "' _RH-THROWS ' UTUI-HOLD CATCH 33 = _RH-ASSERT DROP",
        "_UTUI-MC-HELD @ 0= _RH-ASSERT _RH-BROKEN-READY? 0= _RH-ASSERT",
    ])
    assert "RH PASS 5" in out, out
