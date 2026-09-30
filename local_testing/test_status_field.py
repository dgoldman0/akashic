#!/usr/bin/env python3
"""Execute canonical status model, CELL paint, and capture in real Forth."""

from __future__ import annotations

import re
from pathlib import Path

from test_textarea import MEGAPAD_ROOT, SOURCE_PATHS, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime


ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    ROOT / "akashic/tui/status-field-model.f",
    ROOT / "akashic/tui/widgets/status-field.f",
)


def _run(program: str, marker: str, minimum: int) -> None:
    # Execute the actual KDOS and common drawing/widget closure.  The native
    # source executor avoids the unrelated timing-correct CPU boot cost;
    # there are no substitute status, text, drawing, or allocation words.
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20),
        execution_backend="native",
    )
    runtime.evaluate((MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="status-field-init")
    base = SOURCE_PATHS[:next(i for i, path in enumerate(SOURCE_PATHS)
                              if path.name == "widget.f") + 1]
    for path in (*base, *SOURCES):
        runtime.evaluate("\n".join(_load_forth_lines(path)).encode(),
                         source_name=str(path), step_budget=20_000_000)
    runtime.drain_uart_output()
    try:
        runtime.evaluate(program.encode(), source_name="status-field-checks",
                         step_budget=20_000_000)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-14000:]) from error
    output = runtime.drain_uart_output().decode(errors="replace")
    assert "not found" not in output.lower(), output[-12000:]
    summary = re.search(rf"{marker} PASS\s+(\d+)\s+0", output)
    assert summary, output[-14000:]
    assert int(summary.group(1)) >= minimum


PRELUDE = r'''
VARIABLE _F-N VARIABLE _F-FAIL VARIABLE _F-U VARIABLE _F-D
CREATE _F-MS 519 ALLOT CREATE _F-OS 519 ALLOT
: _F-M _F-MS 7 + -8 AND ;
: _F-O _F-OS 7 + -8 AND ;
: _F-A 1 _F-N +! 0= IF 1 _F-FAIL +! ." STATUS ASSERT " _F-N @ . CR THEN ;
: _F-OK 0= _F-A ;
: _F-REFUSE ( used status -- ) USF-S-INVALID = _F-A 0= _F-A ;
: _F-SENTINEL? ( a -- flag )
    512 0 DO DUP I + C@ 90 <> IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;
: _F-BUILD
    42 8 3 3 3 S" ABCDE" S" xyz01234" _F-M 512 USF-INIT
    _F-OK _F-U ! ;
0 _F-N ! 0 _F-FAIL ! DEPTH _F-D !
'''


def test_status_model_validates_owned_utf8_slots_and_atomic_refusals() -> None:
    program = PRELUDE + r'''
0 0 USF-BYTES 72 = _F-A
5 8 USF-BYTES 88 = _F-A
-1 0 USF-BYTES 0= _F-A
0x7FFFFFFFFFFFFFFF 1 USF-BYTES 0= _F-A
_F-BUILD
_F-M _F-U @ USF-VALIDATE _F-OK
_F-M USF-KEY@ 42 = _F-A
_F-M USF-WIDTH@ 8 = _F-A
_F-M USF-LABEL-COLS@ 3 = _F-A
_F-M USF-LABEL@ NIP 5 = _F-A
_F-M USF-VALUE@ NIP 8 = _F-A
_F-M 87 + C@ 0= _F-A
_F-M 512 90 FILL
42 8 3 3 3 S" ABCDE" S" xyz01234" _F-M 87 USF-INIT
USF-S-CAPACITY = _F-A 0= _F-A
_F-M _F-SENTINEL? _F-A
42 8 3 3 3 _F-M 1 S" value" _F-M 512 USF-INIT _F-REFUSE
_F-M _F-SENTINEL? _F-A
42 8 0 0 1 S" label" S" value" _F-M 512 USF-INIT _F-REFUSE
42 8 8 0 1 0 0 S" value" _F-M 512 USF-INIT _F-REFUSE
42 0 0 0 1 0 0 0 0 _F-M 512 USF-INIT _F-REFUSE
0 8 0 0 1 0 0 0 0 _F-M 512 USF-INIT _F-REFUSE
42 8 9 0 1 0 0 0 0 _F-M 512 USF-INIT _F-REFUSE
42 8 0 5 1 0 0 0 0 _F-M 512 USF-INIT _F-REFUSE
42 8 0 0 4 0 0 0 0 _F-M 512 USF-INIT _F-REFUSE
42 8 0 0 1 0 0 0 0 _F-M 1+ 511 USF-INIT _F-REFUSE
42 8 0 0 1 0 0 0 0 -8 512 USF-INIT _F-REFUSE
42 8 0 0 1 0 0 0 0 _USF-I-DST 512 USF-INIT _F-REFUSE
_F-M _F-SENTINEL? _F-A
CREATE _F-BAD 8 ALLOT
'''
    for raw in (b"\n", b"\x7f", b"\xc2\x85", b"\xe2\x80\xa8", b"\xe2\x80\xa9", b"\xc0\x80", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xc2"):
        program += "\n".join(f"{byte} _F-BAD {index} + C!" for index, byte in enumerate(raw))
        program += f"\n_F-BAD {len(raw)} USF-TEXT? 0= _F-A\n"
        program += f"42 8 0 0 1 0 0 _F-BAD {len(raw)} _F-M 512 USF-INIT _F-REFUSE\n"
        program += "_F-M _F-SENTINEL? _F-A\n"
    program += r'''
42 8 0 0 1 0 0 S" complete value" _F-M 512 USF-INIT _F-OK _F-U !
_F-M _F-U @ USF-VALIDATE _F-OK
_F-M USF-LABEL-COLS@ 0= _F-A
42 8 8 0 1 S" label" 0 0 _F-M 512 USF-INIT _F-OK DROP
42 8 8 0 1 0 0 0 0 _F-M 512 USF-INIT _F-OK 72 = _F-A
_F-BUILD 2 _F-M USF-ABI-OFFSET + !
_F-M _F-U @ USF-VALIDATE USF-S-UNSUPPORTED = _F-A
_F-BUILD 0 _F-M USF-KEY-OFFSET + !
_F-M _F-U @ USF-VALIDATE USF-S-INVALID = _F-A
_F-BUILD 0 _F-M USF-LABEL-COLS-OFFSET + !
_F-M _F-U @ USF-VALIDATE USF-S-INVALID = _F-A
_F-BUILD 8 _F-M USF-LABEL-COLS-OFFSET + !
_F-M _F-U @ USF-VALIDATE USF-S-INVALID = _F-A
_F-BUILD 1 _F-M 87 + C!
_F-M _F-U @ USF-VALIDATE USF-S-INVALID = _F-A
_F-BUILD -1 _F-M USF-LABEL-BYTES-OFFSET + !
_F-M _F-U @ USF-VALIDATE USF-S-INVALID = _F-A
DEPTH _F-D @ = _F-A
_F-FAIL @ 0= IF ." STATUS MODEL PASS " ELSE ." STATUS MODEL FAIL " THEN
_F-N @ . _F-FAIL @ . CR
'''
    _run(program, "STATUS MODEL", 80)


def test_status_display_construction_matches_ordinary_scalar_substitution() -> None:
    program = PRELUDE + r'''
CREATE _F-RAW 7 ALLOT
10 _F-RAW C! 194 _F-RAW 1+ C! 133 _F-RAW 2 + C!
226 _F-RAW 3 + C! 128 _F-RAW 4 + C! 168 _F-RAW 5 + C! 255 _F-RAW 6 + C!
_F-RAW 7 USF-DISPLAY-BYTES _F-OK 12 = _F-A
_F-M 512 90 FILL
42 8 0 0 1 0 0 _F-RAW 7 _F-M 87 USF-INIT-DISPLAY
USF-S-CAPACITY = _F-A 0= _F-A _F-M _F-SENTINEL? _F-A
42 8 0 0 1 0 0 _F-RAW 7 _F-M 512 USF-INIT-DISPLAY
_F-OK DUP _F-U ! 88 = _F-A
_F-M _F-U @ USF-VALIDATE _F-OK
_F-M USF-VALUE-BYTES@ 12 = _F-A
_F-M USF-VALUE@ UTF8-LEN 4 = _F-A
_F-M USF-VALUE@ USF-TEXT? _F-A
_F-M USF-VALUE@ UTF8-DECODE 2DROP 65533 = _F-A
_F-RAW C@ 10 = _F-A _F-RAW 6 + C@ 255 = _F-A
12 3 SCR-NEW SCR-USE RGN-ROOT SCR-CLEAR
_F-RAW 7 0 0 8 SFIELD-DRAW-SLOT
_F-M USF-VALUE@ 1 0 8 SFIELD-DRAW-SLOT
0 0 SCR-GET CELL-CP@ 1 0 SCR-GET CELL-CP@ = _F-A
0 1 SCR-GET CELL-CP@ 1 1 SCR-GET CELL-CP@ = _F-A
0 2 SCR-GET CELL-CP@ 1 2 SCR-GET CELL-CP@ = _F-A
0 3 SCR-GET CELL-CP@ 1 3 SCR-GET CELL-CP@ = _F-A
226 _F-RAW C! 128 _F-RAW 1+ C! 174 _F-RAW 2 + C!
_F-RAW 3 USF-DISPLAY-BYTES _F-OK 3 = _F-A
42 8 0 0 1 0 0 _F-RAW 3 _F-M 512 USF-INIT-DISPLAY _F-OK DROP
_F-M USF-VALUE@ UTF8-DECODE 2DROP 8238 = _F-A
_F-M 512 90 FILL
42 8 0 0 1 0 0 _F-M 3 _F-M 512 USF-INIT-DISPLAY _F-REFUSE
_F-M _F-SENTINEL? _F-A
0 1 USF-DISPLAY-BYTES _F-REFUSE
-2 4 USF-DISPLAY-BYTES _F-REFUSE
_USF-I-VA 8 USF-DISPLAY-BYTES _F-REFUSE
0 0 USF-DISPLAY-BYTES _F-OK 0= _F-A
DEPTH _F-D @ = _F-A
_F-FAIL @ 0= IF ." STATUS DISPLAY PASS " ELSE ." STATUS DISPLAY FAIL " THEN
_F-N @ . _F-FAIL @ . CR
'''
    _run(program, "STATUS DISPLAY", 25)


def test_status_widget_exact_slots_visibility_lifetime_and_capture() -> None:
    program = PRELUDE + r'''
VARIABLE _F-W VARIABLE _F-R VARIABLE _F-T
14 4 SCR-NEW SCR-USE
1 2 1 8 RGN-NEW DUP _F-R ! SFIELD-NEW _F-W !
_F-W @ SFIELD-INSTANCE@ DUP _F-T ! 0<> _F-A
_F-W @ _SFIELD-GENUINE? _F-A
_F-W @ SFIELD-STATUS-FIELD-MEASURE _F-REFUSE
_F-BUILD _F-M _F-U @ _F-W @ SFIELD-BIND _F-OK
_F-W @ SFIELD-INSTANCE@ _F-T @ = _F-A
SCR-CLEAR RGN-ROOT 7 0 0 DRW-STYLE!
33 1 1 DRW-CHAR 33 1 10 DRW-CHAR
_F-W @ WDG-DRAW
1 2 SCR-GET CELL-CP@ 65 = _F-A
1 3 SCR-GET CELL-CP@ 66 = _F-A
1 4 SCR-GET CELL-CP@ 67 = _F-A
1 5 SCR-GET CELL-CP@ 120 = _F-A
1 9 SCR-GET CELL-CP@ 49 = _F-A
1 1 SCR-GET CELL-CP@ 33 = _F-A
1 10 SCR-GET CELL-CP@ 33 = _F-A
2 2 SCR-GET CELL-CP@ 32 = _F-A
1 2 SCR-GET CELL-FG@ 3 = _F-A
CELL-A-BOLD 1 2 SCR-GET CELL-HAS-ATTR? _F-A
DRW-FG@ 7 = _F-A DRW-ATTR@ 0= _F-A
0 _F-W @ WDG-HANDLE 0= _F-A
_F-W @ SFIELD-STATUS-FIELD-MEASURE _F-OK _F-U @ = _F-A
_F-O 512 90 FILL
_F-O _F-U @ 1- _F-W @ SFIELD-STATUS-FIELD-CAPTURE
USF-S-CAPACITY = _F-A 0= _F-A _F-O _F-SENTINEL? _F-A
_F-M 512 _F-W @ SFIELD-STATUS-FIELD-CAPTURE _F-REFUSE
_F-W @ 64 _F-W @ SFIELD-STATUS-FIELD-CAPTURE _F-REFUSE
_F-R @ RGN-SIZE _F-W @ SFIELD-STATUS-FIELD-CAPTURE _F-REFUSE
_SFIELD-C-DST 8 _F-W @ SFIELD-STATUS-FIELD-CAPTURE _F-REFUSE
_F-O 1+ 511 _F-W @ SFIELD-STATUS-FIELD-CAPTURE _F-REFUSE
_F-O 512 _F-W @ SFIELD-STATUS-FIELD-CAPTURE _F-OK _F-U @ = _F-A
_F-O _F-U @ USF-VALIDATE _F-OK
_F-O USF-KEY@ 42 = _F-A
_F-O USF-LABEL-COLS@ 3 = _F-A
_F-O USF-FLAGS@ 3 = _F-A
_F-W @ WDG-HIDE SCR-CLEAR _F-W @ WDG-DRAW
1 2 SCR-GET CELL-CP@ 32 = _F-A
_F-O 512 _F-W @ SFIELD-STATUS-FIELD-CAPTURE _F-OK DROP
_F-O USF-FLAGS@ 2 = _F-A
_F-M USF-FLAGS@ 3 = _F-A
_F-W @ WDG-SHOW
7 _F-R @ _RGN-O-W + !
_F-W @ SFIELD-STATUS-FIELD-MEASURE _F-REFUSE
_F-M _F-U @ _F-W @ SFIELD-BIND USF-S-INVALID = _F-A
SCR-CLEAR _F-W @ WDG-DRAW 1 2 SCR-GET CELL-CP@ 32 = _F-A
8 _F-R @ _RGN-O-W + !
_F-M _F-U @ _F-W @ SFIELD-BIND _F-OK
: _F-SHORT-PAIR 42 8 3 0 1 S" A" S" B" _F-O 512 USF-INIT ;
_F-SHORT-PAIR _F-OK
_F-O SWAP _F-W @ SFIELD-BIND _F-OK
SCR-CLEAR _F-W @ WDG-DRAW
1 2 SCR-GET CELL-CP@ 65 = _F-A
1 3 SCR-GET CELL-CP@ 32 = _F-A
1 4 SCR-GET CELL-CP@ 32 = _F-A
1 5 SCR-GET CELL-CP@ 66 = _F-A
1 9 SCR-GET CELL-CP@ 32 = _F-A
: _F-WIDE-PAIR 42 8 1 0 1 S" 界" S" B" _F-M 512 USF-INIT ;
_F-WIDE-PAIR _F-OK
_F-M SWAP _F-W @ SFIELD-BIND _F-OK
SCR-CLEAR _F-W @ WDG-DRAW
1 2 SCR-GET CELL-CP@ 32 = _F-A
1 3 SCR-GET CELL-CP@ 66 = _F-A
42 8 0 0 0 0 0 S" hidden" _F-M 512 USF-INIT _F-OK
_F-M SWAP _F-W @ SFIELD-BIND _F-OK
SCR-CLEAR _F-W @ WDG-DRAW 1 2 SCR-GET CELL-CP@ 32 = _F-A
_F-W @ SFIELD-UNBIND _F-W @ SFIELD-STATUS-FIELD-MEASURE _F-REFUSE
_F-W @ SFIELD-INSTANCE@ _F-T @ = _F-A
_F-W @ SFIELD-FREE
_F-R @ SFIELD-NEW DUP _F-W ! SFIELD-INSTANCE@ _F-T @ <> _F-A
_F-W @ SFIELD-FREE _F-R @ RGN-FREE
DEPTH _F-D @ = _F-A
_F-FAIL @ 0= IF ." STATUS WIDGET PASS " ELSE ." STATUS WIDGET FAIL " THEN
_F-N @ . _F-FAIL @ . CR
'''
    _run(program, "STATUS WIDGET", 69)
