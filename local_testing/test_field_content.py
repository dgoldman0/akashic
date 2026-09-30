"""Exact FDC1 byte oracles for real native UFLD lowering."""
from __future__ import annotations

import struct

from test_field_model import PRELUDE, field_runtime, run_field

HEADER = struct.Struct("<IHHQIIiiIIiiIIqqqqII")


def _expected(kind, *, value=0, minimum=0, maximum=0, step=0,
              label=(0, 0, 4, 1), value_slot=(4, 0, 16, 1), choices=(), text=b"", revision=9, flags=0):
    # Native rows/columns lower to wire x/y. The outer label is separate.
    body = text if kind == 3 else b"".join(
        struct.pack("<qII", number, len(label_text), 0) + label_text
        for number, label_text in choices
    )
    return HEADER.pack(0x31434446, 1, kind, revision, flags, 0,
                       *label, *value_slot,
                       value, minimum, maximum, step, len(choices), len(text)) + body


def _pack(program, expected):
    runtime = field_runtime(("tui/field-content.f",))
    runtime.evaluate((PRELUDE + r'''
CREATE _FC-OS 1031 ALLOT
: _FC-O _FC-OS 7 + -8 AND 1+ ;
''' + program + r'''
_FC-O 1024 90 FILL
_FM-M _FM-U @ UFLDC-BYTES _FM-OK
_FM-M _FM-U @ _FC-O 1024 UFLDC-PACK _FM-OK
2DUP = _FM-A DROP
_FC-O + C@ 90 = _FM-A
_FM-DONE
''').encode(), source_name="field-content-oracle", step_budget=20_000_000)
    output = runtime.drain_uart_output().decode(errors="replace")
    assert "FIELD MODEL PASS" in output, output
    runtime.execute("_FC-O")
    address = runtime.main_context.data.pop()
    assert runtime.memory.read_bytes(address, len(expected)) == expected
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()


def test_field_content_exact_integer_choice_and_text_wire_bytes():
    _pack("_FM-INT", _expected(1, value=7, minimum=-20, maximum=30, step=4))
    _pack("_FM-CHOICES", _expected(2, value=900,
                                  choices=((-10, b"same"), (900, b"same"), (7, b"third"))))
    _pack(r'''3 _FM-START _FM-SLOTS _FM-LABEL
S" 界ab" _FM-B UFLD-TEXT _FM-OK _FM-FINISH''',
          _expected(3, text="界ab".encode()))
    _pack(r'''1 _FM-START _FM-SLOTS _FM-LABEL
0x8000000000000000 0x8000000000000000 0x7FFFFFFFFFFFFFFF 1 _FM-B UFLD-INTEGER _FM-OK _FM-FINISH''',
          _expected(1, value=-(1 << 63), minimum=-(1 << 63), maximum=(1 << 63)-1, step=1))
    _pack(r'''_FM-M 2048 _FM-B UFLD-BUILDER-INIT _FM-OK
42 3 0x8000000000000001 30 15 7 1 _FM-B UFLD-BEGIN _FM-OK
2 1 2 4 5 7 3 16 _FM-B UFLD-SLOTS _FM-OK _FM-LABEL
0 0 _FM-B UFLD-TEXT _FM-OK _FM-FINISH''',
          _expected(3, label=(1, 2, 4, 2), value_slot=(7, 5, 16, 3),
                    revision=(1 << 63) + 1, flags=1))


def test_field_content_atomic_capacity_alias_and_invalid_source_refusals():
    program = PRELUDE + r'''
CREATE _FC-OS 1031 ALLOT
: _FC-O _FC-OS 7 + -8 AND 1+ ;
: _FC-SAME _FC-O 1024 0 DO DUP I + C@ 90 <> IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;
: _FC-REFUSE UFLDC-S-INVALID = _FM-A 0= _FM-A ;
_FM-CHOICES _FC-O 1024 90 FILL _FM-SAVE
_FM-M _FM-U @ _FC-O 156 UFLDC-PACK UFLDC-S-CAPACITY = _FM-A 0= _FM-A
_FC-SAME _FM-A _FM-SAME
_FM-M _FM-U @ _FM-M 1024 UFLDC-PACK _FC-REFUSE _FM-SAME
_FM-M _FM-U @ _FM-M 1+ 1024 UFLDC-PACK _FC-REFUSE _FM-SAME
_FM-M _FM-U @ _UFLDC-M 1024 UFLDC-PACK _FC-REFUSE _FM-SAME
_FM-M _FM-U @ _UFLD-M 1024 UFLDC-PACK _FC-REFUSE _FM-SAME
_FM-M _FM-U @ _USF-I-DST 1024 UFLDC-PACK _FC-REFUSE _FM-SAME
_FM-M _FM-U @ 0 1024 UFLDC-PACK _FC-REFUSE
_FM-M _FM-U @ -8 1024 UFLDC-PACK _FC-REFUSE
_UFLDC-M 192 _FC-O 1024 UFLDC-PACK _FC-REFUSE _FC-SAME _FM-A
_UFLDC-M 192 UFLDC-BYTES _FC-REFUSE
_FM-M 1+ _FM-U @ _FC-O 1024 UFLDC-PACK _FC-REFUSE _FC-SAME _FM-A
2 _FM-M UFLD-ABI-OFFSET + !
_FM-M _FM-U @ _FC-O 1024 UFLDC-PACK _FC-REFUSE _FC-SAME _FM-A
_FM-M _FM-U @ UFLDC-BYTES _FC-REFUSE
_FM-CHOICES 1 _FM-M 196 + C!
_FM-M _FM-U @ _FC-O 1024 UFLDC-PACK _FC-REFUSE _FC-SAME _FM-A
_FM-DONE
'''
    run_field(program, minimum=60, extra_sources=("tui/field-content.f",))
