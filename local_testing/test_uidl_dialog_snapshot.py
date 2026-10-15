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
    "CREATE _DS-BT 64 ALLOT _DS-BT 64 0 FILL",
    ": _DS-OK S\" OK\" ; : _DS-CANCEL S\" Cancel\" ;",
    "_DS-OK _DS-BT 8 + ! _DS-BT ! DLG-B-DEFAULT _DS-BT 16 + !",
    "_DS-CANCEL _DS-BT 40 + ! _DS-BT 32 + ! DLG-B-CANCEL _DS-BT 48 + !",
    ": _DS-ASK S\" Title\" S\" Hello world\" _DS-BT 2 0 0 DLG-ASK ;",
    "CREATE _DS-DM 175 ALLOT : _DS-D _DS-DM 7 + -8 AND ;",
    "CREATE _DS-NM 1031 ALLOT : _DS-N _DS-NM 7 + -8 AND ;",
    ": _DS-CAPTURE ( native-u -- count used status ) _DS-D 80 ROT _DS-N SWAP UDLSN-CAPTURE ;",
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
        "DLG-HOST-PAINT 1024 _DS-CAPTURE 0= _DS-A 344 = _DS-A 1 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-OVERLAY = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-KEY@ DLG-SHOWN DLG-INSTANCE@ = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-ROW@ 9 = _DS-A _DS-D UDLSN-DESCRIPTOR-COLUMN@ 29 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-HEIGHT@ 6 = _DS-A _DS-D UDLSN-DESCRIPTOR-WIDTH@ 21 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-ENTRY-BYTES@ 344 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-Z@ 255 = _DS-A _DS-D UDLSN-DESCRIPTOR-CONTENTS@ 0= _DS-A",
        "_DS-N 344 UDLG-VALIDATE UDLG-S-OK = _DS-A",
        "_DS-D 80 _DS-N 344 UDLSN-FROZEN-VALIDATE UDLSN-S-OK = _DS-A",
        "0 0 0 0 UDLSN-FROZEN-VALIDATE UDLSN-S-OK = _DS-A",
        "DLG-DISCARD 1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A",
    ], 24)


def test_frozen_validation_refuses_a_slice_its_descriptor_does_not_name():
    _run([
        "_DS-ASK DROP DLG-HOST-PAINT 1024 _DS-CAPTURE 2DROP DROP",
        ": _DS-FROZEN ( -- status ) _DS-D 80 _DS-N 344 UDLSN-FROZEN-VALIDATE ;",
        ": _DS-CELL ( value offset -- status ) _DS-D + DUP @ >R TUCK ! _DS-FROZEN",
        "    SWAP R> SWAP ! ;",
        "_DS-FROZEN UDLSN-S-OK = _DS-A",
        "2 0 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "0 8 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "8 16 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "7 40 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "22 48 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "320 56 _DS-CELL UDLSN-S-INVALID = _DS-A",
        # A dialog widget's contents lie at 255 and are none.
        "254 64 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "1 72 _DS-CELL UDLSN-S-INVALID = _DS-A",
        "_DS-D 80 _DS-N 320 UDLSN-FROZEN-VALIDATE UDLSN-S-INVALID = _DS-A",
        "0 0 _DS-N 8 UDLSN-FROZEN-VALIDATE UDLSN-S-INVALID = _DS-A",
        "_DS-D 160 _DS-N 344 UDLSN-FROZEN-VALIDATE UDLSN-S-INVALID = _DS-A",
        "_DS-N 8 + DUP @ 1+ SWAP ! _DS-FROZEN UDLSN-S-INVALID = _DS-A",
        "DLG-DISCARD",
    ], 13)


def test_capture_refuses_short_or_aliased_banks_and_leaves_cramped_dialogs():
    _run([
        "_DS-ASK DROP DLG-HOST-PAINT",
        "320 _DS-CAPTURE UDLSN-S-CAPACITY = _DS-A 0= _DS-A 0= _DS-A",
        "0 0 _DS-N 1024 UDLSN-CAPTURE UDLSN-S-CAPACITY = _DS-A 2DROP",
        "_DS-D 0 _DS-N 1024 UDLSN-CAPTURE UDLSN-S-INVALID = _DS-A 2DROP",
        "_DS-D 80 _DS-D 40 + 80 UDLSN-CAPTURE UDLSN-S-INVALID = _DS-A 2DROP",
        "_DS-D 80 DLG-SHOWN 1024 UDLSN-CAPTURE UDLSN-S-INVALID = _DS-A 2DROP",
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


# A document whose dialog element holds two labels and a list mounted on a
# region, in a 12 by 40 box at row 5, column 10.
ELEMENT = [
    "VARIABLE _DS-RGN VARIABLE _DS-L",
    ": _DS-KEY ( index widget -- key ) DROP 1+ ;",
    ': _DS-FIELD ( index column widget -- a u ) 2DROP DROP S" row" ;',
    ': _DS-MOUNT ( -- ) S" r" UTUI-BY-ID UTUI-ELEM-RGN RGN-NEW'
    " ['] _DS-KEY ['] _DS-FIELD LST-NEW DUP _DS-L !"
    ' S" r" UTUI-BY-ID UTUI-WIDGET-SET ;',
    ': _DS-UNMOUNT ( -- ) 0 S" r" UTUI-BY-ID UTUI-WIDGET-SET ;',
    ': _DS-BUSY ( -- ) S" s" UTUI-BY-ID S" text" S" Busy" UTUI-SET-ATTR ;',
    ': _DS-KEY-OF ( -- key ) S" d" UTUI-BY-ID UIDL-ELEM-INDEX? DROP 1+ ;',
    "5 10 12 40 RGN-NEW _DS-RGN !",
]


def _load(document: str) -> list[str]:
    return [f'S" {document}" _DS-RGN @ UTUI-LOAD _DS-A']


DIALOG = ("<uidl arrange=stack><dialog id=d title=Applets><label id=s text=Ready/>"
          "<label id=h text=Esc/><region id=r/></dialog></uidl>")


def test_a_dialog_element_is_captured_with_its_message_and_contents():
    """The element's model: its title on the top edge, its labels as the
    message under it, no buttons, and its one mounted list as contents."""
    _run(ELEMENT + _load(DIALOG) + [
        "_DS-MOUNT 1024 _DS-CAPTURE 0= _DS-A 184 = _DS-A 1 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-ELEMENT = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-KEY@ _DS-KEY-OF = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-ROW@ 5 = _DS-A _DS-D UDLSN-DESCRIPTOR-COLUMN@ 10 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-HEIGHT@ 12 = _DS-A _DS-D UDLSN-DESCRIPTOR-WIDTH@ 40 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-Z@ 255 = _DS-A _DS-D UDLSN-DESCRIPTOR-CONTENTS@ 1 = _DS-A",
        "_DS-N 184 UDLG-VALIDATE UDLG-S-OK = _DS-A",
        "_DS-N UDLG-KEY@ _DS-KEY-OF = _DS-A _DS-N UDLG-BUTTON-COUNT@ 0= _DS-A",
        "_DS-N UDLG-REVISION@ UTUI-DIALOG-REVISION = _DS-A",
        "_DS-N UDLG-TITLE@ S\" Applets\" COMPARE 0= _DS-A",
        "_DS-N UDLG-TITLE-SLOT@ 7 = _DS-A 1 = _DS-A 2 = _DS-A 0= _DS-A",
        "_DS-N UDLG-MESSAGE-SLOT@ 38 = _DS-A 2 = _DS-A 1 = _DS-A 1 = _DS-A",
        "_DS-N UDLG-MESSAGE-BYTES@ 9 = _DS-A",
        "_DS-N UDLG-MESSAGE@ DROP 5 + C@ 10 = _DS-A",
        "_DS-D 80 _DS-N 184 UDLSN-FROZEN-VALIDATE UDLSN-S-OK = _DS-A",
    ], 26)


def test_a_dialog_element_keeps_its_revision_until_it_changes():
    _run(ELEMENT + _load(DIALOG) + [
        "_DS-MOUNT 1024 _DS-CAPTURE 2DROP DROP _DS-N UDLG-REVISION@",
        "1024 _DS-CAPTURE 2DROP DROP DUP _DS-N UDLG-REVISION@ = _DS-A",
        "_DS-BUSY 1024 _DS-CAPTURE 0= _DS-A 2DROP _DS-N UDLG-REVISION@ < _DS-A",
    ], 3)


def test_an_empty_first_label_keeps_its_line():
    _run(ELEMENT + _load(
        "<uidl arrange=stack><dialog id=d title=Applets><label id=s/>"
        "<label id=h text=Esc/><region id=r/></dialog></uidl>") + [
        "_DS-MOUNT 1024 _DS-CAPTURE 0= _DS-A DROP 1 = _DS-A",
        "_DS-N UDLG-MESSAGE-BYTES@ 4 = _DS-A",
        "_DS-N UDLG-MESSAGE@ DROP C@ 10 = _DS-A",
        "_DS-N UDLG-MESSAGE-SLOT@ 38 = _DS-A 2 = _DS-A 1 = _DS-A 1 = _DS-A",
    ], 8)


def test_a_dialog_element_with_unrepresented_children_stays_cell():
    """No list mounted, a label after the contents, two dialogs, or a
    hidden one: nothing is captured, so the dialog stays painted text."""
    _run(ELEMENT + _load(DIALOG) + [
        "1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A",
        "_DS-MOUNT S\" d\" UTUI-HIDE 1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A",
        "_DS-UNMOUNT",
    ] + _load(
        "<uidl arrange=stack><dialog id=d title=Applets><label id=s text=Ready/>"
        "<region id=r/><label id=h text=Esc/></dialog></uidl>") + [
        "_DS-MOUNT 1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A _DS-UNMOUNT",
    ] + _load(
        "<uidl arrange=flex><dialog id=d title=A><region id=r/></dialog>"
        "<dialog id=e title=B><label text=x/></dialog></uidl>") + [
        "_DS-MOUNT 1024 _DS-CAPTURE 0= _DS-A 0= _DS-A 0= _DS-A _DS-UNMOUNT",
    ], 12)


def test_a_shown_dialog_widget_is_captured_before_a_dialog_element():
    _run(ELEMENT + _load(DIALOG) + [
        "_DS-MOUNT _DS-ASK _DS-A DLG-HOST-PAINT",
        "1024 _DS-CAPTURE 0= _DS-A 344 = _DS-A 1 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-OVERLAY = _DS-A",
        "DLG-DISCARD 1024 _DS-CAPTURE 0= _DS-A 184 = _DS-A 1 = _DS-A",
        "_DS-D UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-ELEMENT = _DS-A",
    ], 9)
