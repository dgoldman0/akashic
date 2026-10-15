"""Execute the canonical UDLG dialog model and its DLG1 and BTN1 lowering
in the actual native source runtime."""
from __future__ import annotations

import struct

import pytest

from test_field_model import field_runtime

SOURCES = ("tui/dialog-model.f", "tui/dialog-content.f", "tui/rich-terminal/dlg1.f")
MESSAGE = b"Remove notes.md?\nIt cannot be undone."
DLG1 = struct.Struct("<IHHQIIiiIIiiII")

# A 30 by 8 dialog: the title "Delete" on the top edge, two message lines,
# and [ Delete ], destructive, beside [ Cancel ], the selected default and
# cancel button.
PRELUDE = r'''
VARIABLE _DM-N VARIABLE _DM-FAIL VARIABLE _DM-U
CREATE _DM-MS 2055 ALLOT : _DM-M _DM-MS 7 + -8 AND ;
CREATE _DM-CS 2055 ALLOT : _DM-C _DM-CS 7 + -8 AND ;
CREATE _DM-OS 1031 ALLOT : _DM-O _DM-OS 7 + -8 AND 1+ ;
: _DM-A 1 _DM-N +! 0= IF 1 _DM-FAIL +! ." DIALOG ASSERT " _DM-N @ . CR THEN ;
: _DM-OK UDLG-S-OK = _DM-A ;
: _DM-DONE _DM-FAIL @ 0= IF ." DIALOG MODEL PASS " ELSE ." DIALOG MODEL FAIL " THEN
    _DM-N @ . _DM-FAIL @ . CR ;
: _DM-BUILD
    42 7 30 8 0 3 _DM-M UDLG-START
    0 2 1 6 S" Delete" _DM-M UDLG-TITLE!
    2 2 2 26 _DM-M UDLG-MESSAGE-SLOT!
    S" Remove notes.md?" _DM-M UDLG-LINE+
    S" It cannot be undone." _DM-M UDLG-LINE+
    6 4 1 10 UDLG-B-DESTRUCTIVE 3 S" Delete" _DM-M UDLG-BUTTON+
    6 16 1 10 UDLG-B-DEFAULT UDLG-B-CANCEL OR 7 S" Cancel" _DM-M UDLG-BUTTON+
    _DM-M UDLG-BYTES@ _DM-U ! ;
\ Validate a copy with one cell, or one byte, changed.
: _DM-CELL ( value offset -- status )
    _DM-M _DM-C 2048 MOVE _DM-C + ! _DM-C _DM-U @ UDLG-VALIDATE ;
: _DM-BYTE ( value offset -- status )
    _DM-M _DM-C 2048 MOVE _DM-C + C! _DM-C _DM-U @ UDLG-VALIDATE ;
'''


def _run(program, minimum):
    runtime = field_runtime(SOURCES)
    try:
        runtime.evaluate((PRELUDE + program + "\n_DM-DONE\n").encode(),
                         source_name="dialog-model-checks", step_budget=40_000_000)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-8000:]) from error
    output = runtime.drain_uart_output().decode(errors="replace")
    assert "DIALOG MODEL PASS" in output, output[-4000:]
    count = int(output.split("DIALOG MODEL PASS")[1].split()[0])
    assert count >= minimum
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
    return runtime


def test_dialog_model_writes_a_canonical_value_and_reads_it_back():
    _run(r'''
_DM-BUILD
_DM-U @ 352 = _DM-A
6 37 UDLG-TEXT-BYTES 6 UDLG-BUTTON-BYTES 2* + 352 = _DM-A
_DM-M _DM-U @ UDLG-VALIDATE _DM-OK
_DM-M UDLG-KEY@ 42 = _DM-A _DM-M UDLG-REVISION@ 7 = _DM-A
_DM-M UDLG-WIDTH@ 30 = _DM-A _DM-M UDLG-HEIGHT@ 8 = _DM-A
_DM-M UDLG-SEVERITY@ 3 = _DM-A _DM-M UDLG-FLAGS@ 0= _DM-A
_DM-M UDLG-TITLE@ S" Delete" COMPARE 0= _DM-A
_DM-M UDLG-MESSAGE@ NIP 37 = _DM-A
_DM-M UDLG-MESSAGE-SLOT@ 26 = _DM-A 2 = _DM-A 2 = _DM-A 2 = _DM-A
_DM-M UDLG-BUTTON-COUNT@ 2 = _DM-A
_DM-M UDLG-UTF8-BYTES@ 55 = _DM-A
_DM-M UDLG-BUTTON-FIRST DUP UDLG-BUTTON-LABEL@ S" Delete" COMPARE 0= _DM-A
DUP UDLG-BUTTON-ROLES@ UDLG-B-DESTRUCTIVE = _DM-A
DUP UDLG-BUTTON-STATE@ 3 = _DM-A
DUP UDLG-BUTTON-SLOT@ 10 = _DM-A 1 = _DM-A 4 = _DM-A 6 = _DM-A
UDLG-BUTTON-NEXT DUP UDLG-BUTTON-LABEL@ S" Cancel" COMPARE 0= _DM-A
DUP UDLG-BUTTON-ROLES@ 3 = _DM-A UDLG-BUTTON-STATE@ 7 = _DM-A
''', 24)


# Each change, by cell or byte offset, and the status it leaves.  The
# buttons begin at 208 and 280.
CELL_REFUSALS = [
    (2, 8, 1),          # another ABI is unsupported
    (0, 16, 3),         # no identity
    (0, 24, 3),         # no revision
    (0, 32, 3),         # no width
    (2, 48, 3),         # reserved flag
    (5, 56, 3),         # severity past error
    (1, 152, 3),        # reserved cell
    (0, 88, 3),         # a title without a slot width
    (25, 72, 3),        # the title past the root's edge
    (0, 96, 3),         # the message over the title
    (1, 112, 3),        # more lines than message rows
    (1, 48, 3),         # a notice with buttons
    (5, 216, 3),        # a destructive default
    (1, 216, 3),        # two defaults
    (7, 224, 3),        # two selected
    (5, 296, 3),        # selected but not enabled
    (12, 240, 3),       # buttons that meet
    (0, 232, 3),        # a button on the title's row...
    (80, 208, 3),       # a button record of the wrong size
    (344, 0, 3),        # a length that is not the value's
]
BYTE_REFUSALS = [
    (1, 166, 3),        # nonzero title padding
    (9, 172, 3),        # a tab in the message
    (10, 168 + 36, 3),  # an extra line
]


@pytest.mark.parametrize("value,offset,status", CELL_REFUSALS)
def test_dialog_model_refuses_each_noncanonical_cell(value, offset, status):
    extra = "2 240 _DM-C + ! " if offset == 232 else ""
    program = f"""
_DM-BUILD
_DM-M _DM-C 2048 MOVE {value} _DM-C {offset} + ! {extra}_DM-C _DM-U @ UDLG-VALIDATE {status} = _DM-A
_DM-M _DM-U @ UDLG-VALIDATE _DM-OK
"""
    _run(program, 2)


@pytest.mark.parametrize("value,offset,status", BYTE_REFUSALS)
def test_dialog_model_refuses_each_noncanonical_byte(value, offset, status):
    _run(f"_DM-BUILD {value} {offset} _DM-BYTE {status} = _DM-A", 1)


def test_dialog_model_without_title_or_message_and_a_notice():
    _run(r'''
\ Buttons alone.
1 1 12 3 0 0 _DM-M UDLG-START
1 1 1 10 UDLG-B-DEFAULT 7 S" OK" _DM-M UDLG-BUTTON+
_DM-M DUP UDLG-BYTES@ UDLG-VALIDATE _DM-OK
\ A notice: a message and no buttons.
2 1 20 1 UDLG-F-NOTICE 4 _DM-M UDLG-START
0 0 1 20 _DM-M UDLG-MESSAGE-SLOT! S" Disk full" _DM-M UDLG-LINE+
_DM-M DUP UDLG-BYTES@ UDLG-VALIDATE _DM-OK
_DM-M UDLG-BYTES@ 0 9 UDLG-TEXT-BYTES = _DM-A
_DM-M UDLG-UTF8-BYTES@ 9 = _DM-A
''', 4)


def _bytes(runtime, word, length):
    runtime.execute(word)
    address = runtime.main_context.data.pop()
    return runtime.memory.read_bytes(address, length)


def test_dialog_content_packs_exact_dlg1_and_btn1_that_dlg1_accepts():
    runtime = _run(r'''
_DM-BUILD
_DM-M _DM-U @ UDLGC-DIALOG-BYTES 0= _DM-A 93 = _DM-A
_DM-O 1024 90 FILL
_DM-M _DM-U @ _DM-O 1024 UDLGC-DIALOG-PACK 0= _DM-A 93 = _DM-A
_DM-O 93 + C@ 90 = _DM-A
\ The terminal's own validator accepts it with the title as the label.
_DM-O 93 _DM-M UDLG-TITLE@ 30 8 DLG1-VALIDATE _DM-A 37 = _DM-A
_DM-M _DM-U @ _DM-O 92 UDLGC-DIALOG-PACK UDLGC-S-CAPACITY = _DM-A 0= _DM-A
_DM-M _DM-U @ _DM-M 8 + 1024 UDLGC-DIALOG-PACK UDLGC-S-INVALID = _DM-A DROP
_DM-M UDLG-BUTTON-FIRST _DM-O 100 + 8 UDLGC-BUTTON-PACK 0= _DM-A 8 = _DM-A
_DM-O 100 + 8 BTN1-VALIDATE _DM-A
_DM-M UDLG-BUTTON-FIRST _DM-O 100 + 7 UDLGC-BUTTON-PACK UDLGC-S-CAPACITY = _DM-A DROP
''', 14)
    expected = DLG1.pack(0x31474C44, 1, 0, 7, 3, len(MESSAGE),
                         2, 0, 6, 1, 2, 2, 26, 2) + MESSAGE
    assert _bytes(runtime, "_DM-O", 93) == expected
    runtime.execute("_DM-O")
    address = runtime.main_context.data.pop()
    assert runtime.memory.read_bytes(address + 100, 8) == struct.pack("<IHH", 0x314E5442, 1, 4)
