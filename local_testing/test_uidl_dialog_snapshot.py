"""Capture a document's dialog as a frozen UDLG model, natively."""

from __future__ import annotations

from forth_dependencies import dependency_order
import test_uidl_collection_snapshot as base

_CLOSURE = dependency_order(base.AK, ("tui/uidl-dialog-snapshot.f",))
_PATHS = [base.AK / module for module in _CLOSURE if module not in base._STUBBED_MODULES]
_STUBS_BEFORE = next(
    base.AK / module
    for module in _CLOSURE[_CLOSURE.index("tui/color.f") + 1:]
    if module not in base._STUBBED_MODULES
)


def _closure_source() -> list[str]:
    source = []
    for path in _PATHS:
        if path == _STUBS_BEFORE:
            source.extend(base.COLOR_ABI_STUBS)
        if path.name == "uidl-tui.f":
            source.extend(base.STYLE_ABI_STUBS)
        source.extend(base._load_forth_lines(path))
    return source


PRELUDE = [
    "VARIABLE _DS-FAILS VARIABLE _DS-CHECKS",
    ": _DS-A 1 _DS-CHECKS +! 0= IF 1 _DS-FAILS +! .\" DLGSN ASSERT \" _DS-CHECKS @ . CR THEN ;",
    ": _DS-DONE _DS-FAILS @ 0= IF .\" DLGSN PASS \" ELSE .\" DLGSN FAIL \" THEN _DS-CHECKS @ . CR ;",
    "CREATE _DS-BT 48 ALLOT",
    "S\" OK\" _DS-BT 8 + ! _DS-BT ! DLG-B-DEFAULT _DS-BT 16 + !",
    "S\" Cancel\" _DS-BT 32 + ! _DS-BT 24 + ! DLG-B-CANCEL _DS-BT 40 + !",
    ": _DS-ASK S\" Title\" S\" Hello world\" _DS-BT 2 0 0 DLG-ASK ;",
    "CREATE _DS-DM 135 ALLOT : _DS-D _DS-DM 7 + -8 AND ;",
    "CREATE _DS-NM 1031 ALLOT : _DS-N _DS-NM 7 + -8 AND ;",
    ": _DS-CAPTURE ( native-u -- count used status ) _DS-D 64 ROT _DS-N SWAP UDLSN-CAPTURE ;",
    "VARIABLE _DS-C",
    "80 24 SCR-NEW SCR-USE",
    "UCTX-ALLOC _DS-C ! _DS-C @ UCTX-CLEAR _DS-C @ UCTX-RESTORE",
]


def _run(lines: list[str], minimum: int) -> None:
    original = base._closure_source
    base._closure_source = _closure_source
    try:
        output = base._run_forth(PRELUDE + lines + ["_DS-DONE"])
    finally:
        base._closure_source = original
    assert "DLGSN PASS" in output, output[-3000:]
    assert int(output.split("DLGSN PASS")[1].split()[0]) >= minimum


def test_a_painted_dialog_is_captured_with_its_place_and_identity():
    """Nothing for no dialog or one not yet painted; then one model where
    the paint put the dialog, that frozen validation accepts."""
    _run([
        "1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A",
        "_DS-ASK _DS-A 1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A",
        "DLG-HOST-PAINT 1024 _DS-CAPTURE 0= _DS-A 328 = _DS-A 1 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-OVERLAY = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-KEY@ DLG-SHOWN DLG-INSTANCE@ = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-ROW@ 9 = _DS-A _DS-D UDLSN-DESCRIPTOR-COLUMN@ 29 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-HEIGHT@ 6 = _DS-A _DS-D UDLSN-DESCRIPTOR-WIDTH@ 21 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-ENTRY-BYTES@ 328 = _DS-A",
        "_DS-N 328 UDLG-VALIDATE UDLG-S-OK = _DS-A",
        "_DS-D 64 _DS-N 328 UDLSN-FROZEN-VALIDATE UDLSN-S-OK = _DS-A",
        "0 0 0 0 UDLSN-FROZEN-VALIDATE UDLSN-S-OK = _DS-A",
        "DLG-DISCARD 1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A",
    ], 22)


def test_frozen_validation_refuses_a_slice_its_descriptor_does_not_name():
    _run([
        "_DS-ASK DROP DLG-HOST-PAINT 1024 _DS-CAPTURE 2DROP DROP",
        ": _DS-FROZEN ( -- status ) _DS-D 64 _DS-N 328 UDLSN-FROZEN-VALIDATE ;",
        ": _DS-CELL ( value offset -- status ) _DS-D + DUP @ >R TUCK ! _DS-FROZEN",
        "    SWAP R> SWAP ! ;",
        "_DS-FROZEN UDLSN-S-OK = _DS-A",
        "2 0 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "0 8 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "8 16 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "7 40 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "22 48 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "320 56 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "_DS-D 64 _DS-N 320 UDLSN-FROZEN-VALIDATE UDLSN-S-INVALID = _DS-A",
        "0 0 _DS-N 8 UDLSN-FROZEN-VALIDATE UDLSN-S-INVALID = _DS-A",
        "_DS-D 128 _DS-N 328 UDLSN-FROZEN-VALIDATE UDLSN-S-INVALID = _DS-A",
        "_DS-N 8 + DUP @ 1+ SWAP ! _DS-FROZEN UDLSN-S-INVALID = _DS-A",
        "DLG-DISCARD",
    ], 11)


def test_capture_refuses_short_or_aliased_banks_and_leaves_cramped_dialogs():
    _run([
        "_DS-ASK DROP DLG-HOST-PAINT",
        "320 _DS-CAPTURE UDLSN-S-CAPACITY = _DS-A 0= _DS-A 0= _DS-A",
        "0 0 _DS-N 1024 UDLSN-CAPTURE UDLSN-S-CAPACITY = _DS-A 2DROP",
        "_DS-D 0 _DS-N 1024 UDLSN-CAPTURE UDLSN-S-INVALID = _DS-A 2DROP",
        "_DS-D 64 _DS-D 32 + 64 UDLSN-CAPTURE UDLSN-S-INVALID = _DS-A 2DROP",
        "_DS-D 64 DLG-SHOWN 1024 UDLSN-CAPTURE UDLSN-S-INVALID = _DS-A 2DROP",
        "DLG-SHOWN WDG-REGION RGN-H 6 = _DS-A",
        ": _DS-CRAMPED 0 0 6 80 ;",
        "' _DS-CRAMPED IS _DLG-BOUNDS-HOOK DLG-HOST-PAINT",
        "1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A",
        "' _UTUI-DIALOG-BOUNDS IS _DLG-BOUNDS-HOOK",
        "DLG-DISCARD",
    ], 11)


def test_the_overlay_root_is_the_painted_dialog_before_the_overlay_field():
    _run([
        "UTUI-OVERLAY-ROOT@ 0= _DS-A 2DROP 2DROP",
        "_DS-ASK DROP UTUI-OVERLAY-ROOT@ 0= _DS-A 2DROP 2DROP",
        "DLG-HOST-PAINT UTUI-OVERLAY-ROOT@ _DS-A 21 = _DS-A 6 = _DS-A 29 = _DS-A 9 = _DS-A",
        "DLG-DISCARD UTUI-OVERLAY-ROOT@ 0= _DS-A 2DROP 2DROP",
    ], 8)
