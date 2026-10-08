"""Execute the canonical UFLD contract in the actual native source runtime."""
from __future__ import annotations

import re
from pathlib import Path

from forth_dependencies import dependency_order
from test_textarea import MEGAPAD_ROOT
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

ROOT = Path(__file__).resolve().parents[1]


def field_runtime(extra_sources=()):
    """Load model plus any ordinary widget roots, without substitute words."""
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20),
        execution_backend="native",
    )
    runtime.evaluate((MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="field-init")
    roots = ("tui/field-model.f", *extra_sources)
    for module in dependency_order(ROOT / "akashic", roots):
        text = (ROOT / "akashic" / module).read_text()
        text = "\n".join(line for line in text.splitlines()
                         if not line.strip().startswith(("REQUIRE ", "PROVIDED ")))
        runtime.evaluate(text.encode(), source_name=module, step_budget=20_000_000)
    runtime.drain_uart_output()
    return runtime


def run_field(program, marker="FIELD MODEL", minimum=1, extra_sources=()):
    runtime = field_runtime(extra_sources)
    try:
        runtime.evaluate(program.encode(), source_name="field-checks", step_budget=20_000_000)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-18000:]) from error
    output = runtime.drain_uart_output().decode(errors="replace")
    summary = re.search(rf"{marker} PASS\s+(\d+)\s+0", output)
    assert summary, (output, runtime.main_context.data.snapshot())
    assert int(summary.group(1)) >= minimum
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
    return runtime


PRELUDE = r'''
VARIABLE _FM-N VARIABLE _FM-FAIL VARIABLE _FM-U
CREATE _FM-MS 2055 ALLOT CREATE _FM-OS 2055 ALLOT
CREATE _FM-BS 47 ALLOT CREATE _FM-OBS 47 ALLOT
: _FM-M _FM-MS 7 + -8 AND ; : _FM-O _FM-OS 7 + -8 AND ;
: _FM-B _FM-BS 7 + -8 AND ; : _FM-OB _FM-OBS 7 + -8 AND ;
: _FM-A 1 _FM-N +! 0= IF 1 _FM-FAIL +! ." FIELD ASSERT " _FM-N @ . CR THEN ;
: _FM-OK UFLD-S-OK = _FM-A ;
: _FM-SAVE _FM-M _FM-O 2048 MOVE _FM-B _FM-OB 40 MOVE ;
: _FM-SAME _FM-M 2048 _FM-O 2048 COMPARE 0= _FM-A _FM-B 40 _FM-OB 40 COMPARE 0= _FM-A ;
: _FM-START ( kind -- )
    >R _FM-M 2048 _FM-B UFLD-BUILDER-INIT _FM-OK
    42 R> 9 20 2 3 0 _FM-B UFLD-BEGIN _FM-OK ;
: _FM-SLOTS 0 0 1 4 0 4 1 16 _FM-B UFLD-SLOTS _FM-OK ;
: _FM-LABEL S" Gain" _FM-B UFLD-LABEL _FM-OK ;
: _FM-EMPTY 0 0 0 0 0 0 1 20 _FM-B UFLD-SLOTS _FM-OK 0 0 _FM-B UFLD-LABEL _FM-OK ;
: _FM-FINISH _FM-B UFLD-FINISH _FM-OK _FM-U ! _FM-M _FM-U @ UFLD-VALIDATE _FM-OK ;
: _FM-INT 1 _FM-START _FM-SLOTS _FM-LABEL 7 -20 30 4 _FM-B UFLD-INTEGER _FM-OK _FM-FINISH ;
: _FM-CHOICES
    2 _FM-START _FM-SLOTS _FM-LABEL 900 _FM-B UFLD-CHOICE-VALUE _FM-OK
    -10 S" same" _FM-B UFLD-CHOICE _FM-OK
    900 S" same" _FM-B UFLD-CHOICE _FM-OK
    7 S" third" _FM-B UFLD-CHOICE _FM-OK _FM-FINISH ;
: _FM-DONE _FM-FAIL @ 0= IF ." FIELD MODEL PASS " ELSE ." FIELD MODEL FAIL " THEN _FM-N @ . _FM-FAIL @ . CR ;
'''


def test_field_native_contract_and_canonical_extent():
    program = PRELUDE + r'''
_FM-INT
_FM-U @ 200 = _FM-A
_FM-M UFLD-KEY@ 42 = _FM-A _FM-M UFLD-REVISION@ 9 = _FM-A
_FM-M UFLD-LABEL@ S" Gain" COMPARE 0= _FM-A
_FM-M UFLD-VALUE@ 7 = _FM-A _FM-M UFLD-STEP@ 4 = _FM-A
_FM-M 196 + 4 _UFLD-ZERO? _FM-A
3 _FM-START _FM-EMPTY S" Full text" _FM-B UFLD-TEXT _FM-OK _FM-FINISH
_FM-U @ 208 = _FM-A
_FM-M UFLD-TEXT@ S" Full text" COMPARE 0= _FM-A
_FM-M UFLD-UTF8-BYTES@ 9 = _FM-A
3 _FM-START _FM-EMPTY 0 0 _FM-B UFLD-TEXT _FM-OK _FM-FINISH
_FM-U @ 192 = _FM-A
_FM-CHOICES
_FM-M UFLD-CHOICE-COUNT@ 3 = _FM-A _FM-U @ 296 = _FM-A
_FM-M UFLD-UTF8-BYTES@ 17 = _FM-A
_FM-M UFLD-CHOICE-FIRST UFLD-CHOICE-VALUE@ -10 = _FM-A
_FM-M UFLD-CHOICE-SELECTED@ UFLD-CHOICE-VALUE@ 900 = _FM-A
_FM-M UFLD-CHOICE-FIRST UFLD-CHOICE-LABEL@ S" same" COMPARE 0= _FM-A
_FM-SAVE
0 _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK 900 = _FM-A
1 _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK 7 = _FM-A
-1 _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK -10 = _FM-A
4 _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK 7 = _FM-A
0x8000000000000000 _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK 7 = _FM-A
0x7FFFFFFFFFFFFFFF _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK 7 = _FM-A
_FM-SAME
2 _FM-START _FM-EMPTY 900 _FM-B UFLD-CHOICE-VALUE _FM-OK
7 S" first" _FM-B UFLD-CHOICE _FM-OK
900 S" second" _FM-B UFLD-CHOICE _FM-OK
-10 S" third" _FM-B UFLD-CHOICE _FM-OK _FM-FINISH
1 _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK -10 = _FM-A
_FM-CHOICES -10 _FM-M UFLD-VALUE-OFFSET + !
-1 _FM-M _FM-U @ UFLD-CHOICE-WRAP _FM-OK 7 = _FM-A
_FM-CHOICES 900 _FM-M UFLD-CHOICE-FIRST 8 + !
_FM-M _FM-U @ UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_FM-CHOICES 123 _FM-M UFLD-VALUE-OFFSET + !
_FM-M _FM-U @ UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_FM-CHOICES 0xFFFFFFFF _FM-M UFLD-CHOICE-COUNT-OFFSET + !
_FM-M _FM-U @ UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_FM-CHOICES 24 _FM-M UFLD-CHOICE-FIRST !
_FM-M _FM-U @ UFLD-VALIDATE UFLD-S-INVALID = _FM-A
'''
    for field, value, status in (
        ("ABI", 2, "UNSUPPORTED"), ("KIND", 99, "UNSUPPORTED"),
        ("KEY", 0, "INVALID"), ("REVISION", 0, "INVALID"),
        ("WIDTH", 0, "INVALID"), ("HEIGHT", 0, "INVALID"),
        ("WIDTH", 1 << 32, "INVALID"), ("STATE", 4, "INVALID"),
        ("STATE", 8, "INVALID"), ("FLAGS", 2, "INVALID"),
        ("LABEL-ROW", -1, "INVALID"), ("LABEL-COLUMN", 1 << 31, "INVALID"),
        ("LABEL-WIDTH", 5, "INVALID"), ("VALUE-WIDTH", 17, "INVALID"),
        ("LABEL-HEIGHT", 0, "INVALID"), ("VALUE-HEIGHT", 0, "INVALID"),
        ("STEP", 0, "INVALID"), ("MINIMUM", 8, "INVALID"), ("MAXIMUM", 6, "INVALID"),
        ("TEXT-BYTES", 1, "INVALID"), ("CHOICE-COUNT", 1, "INVALID"),
        ("LABEL-BYTES", -1, "INVALID"),
    ):
        program += f"\n_FM-INT {value} _FM-M UFLD-{field}-OFFSET + !\n_FM-M _FM-U @ UFLD-VALIDATE UFLD-S-{status} = _FM-A\n"
    program += r'''
_FM-INT 1 _FM-M 196 + C! _FM-M _FM-U @ UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_FM-INT _FM-M _FM-U @ 8 + UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_FM-M 191 UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_FM-M 1+ _FM-U @ UFLD-VALIDATE UFLD-S-INVALID = _FM-A
-8 200 UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_UFLD-V-M 192 UFLD-VALIDATE UFLD-S-INVALID = _FM-A
_FM-DONE
'''
    run_field(program, minimum=250)


def test_field_builder_atomic_refusals_aliases_and_clean_text():
    program = PRELUDE + r'''
_FM-M 2048 90 FILL
_FM-M 191 _FM-B UFLD-BUILDER-INIT _FM-OK _FM-SAVE
42 1 1 20 2 3 0 _FM-B UFLD-BEGIN UFLD-S-CAPACITY = _FM-A _FM-SAME
_FM-M 2048 _FM-M UFLD-BUILDER-INIT UFLD-S-INVALID = _FM-A _FM-SAME
_UFLD-M 2048 _FM-B UFLD-BUILDER-INIT UFLD-S-INVALID = _FM-A _FM-SAME
_FM-M 2048 _UFLD-B UFLD-BUILDER-INIT UFLD-S-INVALID = _FM-A _FM-SAME
_FM-M 2048 _FM-B UFLD-BUILDER-INIT _FM-OK _FM-SAVE
0 1 1 20 2 3 0 _FM-B UFLD-BEGIN UFLD-S-INVALID = _FM-A _FM-SAME
42 1 1 20 2 4 0 _FM-B UFLD-BEGIN UFLD-S-INVALID = _FM-A _FM-SAME
1 _FM-START _FM-SAVE
0 0 1 5 0 4 1 16 _FM-B UFLD-SLOTS UFLD-S-INVALID = _FM-A _FM-SAME
0 0 0 4 0 4 1 16 _FM-B UFLD-SLOTS UFLD-S-INVALID = _FM-A _FM-SAME
0 0 1 4 0 4 1 17 _FM-B UFLD-SLOTS UFLD-S-INVALID = _FM-A _FM-SAME
_FM-SLOTS _FM-SAVE
0 0 _FM-B UFLD-LABEL UFLD-S-INVALID = _FM-A _FM-SAME
_FM-M 1 _FM-B UFLD-LABEL UFLD-S-INVALID = _FM-A _FM-SAME
_FM-B 1 _FM-B UFLD-LABEL UFLD-S-INVALID = _FM-A _FM-SAME
_UFLD-V-M 1 _FM-B UFLD-LABEL UFLD-S-INVALID = _FM-A _FM-SAME
_FM-LABEL _FM-SAVE
7 -2 5 1 _FM-B UFLD-INTEGER UFLD-S-INVALID = _FM-A _FM-SAME
7 -2 8 0 _FM-B UFLD-INTEGER UFLD-S-INVALID = _FM-A _FM-SAME
S" x" _FM-B UFLD-TEXT UFLD-S-INVALID = _FM-A _FM-SAME
_FM-B UFLD-FINISH UFLD-S-INVALID = _FM-A 0= _FM-A _FM-SAME
2 _FM-START _FM-EMPTY 7 _FM-B UFLD-CHOICE-VALUE _FM-OK _FM-SAVE
_FM-B UFLD-FINISH UFLD-S-INVALID = _FM-A 0= _FM-A _FM-SAME
7 0 0 _FM-B UFLD-CHOICE UFLD-S-INVALID = _FM-A _FM-SAME
7 S" seven" _FM-B UFLD-CHOICE _FM-OK _FM-SAVE
7 S" duplicate" _FM-B UFLD-CHOICE UFLD-S-INVALID = _FM-A _FM-SAME
_FM-FINISH
CREATE _FM-BAD 8 ALLOT
'''
    for raw in (b"\n", b"\x7f", b"\xc2\x85", b"\xe2\x80\xa8", b"\xe2\x80\xa9", b"\xc0\x80", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xc2"):
        program += "\n3 _FM-START _FM-EMPTY _FM-SAVE\n"
        program += "\n".join(f"{byte} _FM-BAD {i} + C!" for i, byte in enumerate(raw))
        program += f"\n_FM-BAD {len(raw)} _FM-B UFLD-TEXT UFLD-S-INVALID = _FM-A _FM-SAME\n"
    program += r'''
3 _FM-START _FM-EMPTY _FM-SAVE
_FM-M 1 _FM-B UFLD-TEXT UFLD-S-INVALID = _FM-A _FM-SAME
-2 8 _FM-B UFLD-TEXT UFLD-S-INVALID = _FM-A _FM-SAME
_FM-M 192 _FM-B UFLD-BUILDER-INIT _FM-OK
42 3 1 20 2 3 0 _FM-B UFLD-BEGIN _FM-OK _FM-EMPTY _FM-SAVE
S" x" _FM-B UFLD-TEXT UFLD-S-CAPACITY = _FM-A _FM-SAME
_FM-M 199 _FM-B UFLD-BUILDER-INIT _FM-OK
42 1 1 20 2 3 0 _FM-B UFLD-BEGIN _FM-OK _FM-SLOTS _FM-SAVE
S" Gain" _FM-B UFLD-LABEL UFLD-S-CAPACITY = _FM-A _FM-SAME
_FM-M 224 _FM-B UFLD-BUILDER-INIT _FM-OK
42 2 1 20 2 3 0 _FM-B UFLD-BEGIN _FM-OK _FM-EMPTY
7 _FM-B UFLD-CHOICE-VALUE _FM-OK
7 S" one" _FM-B UFLD-CHOICE _FM-OK _FM-SAVE
99 S" two" _FM-B UFLD-CHOICE UFLD-S-CAPACITY = _FM-A _FM-SAME
_USF-I-DST 2048 _FM-B UFLD-BUILDER-INIT UFLD-S-INVALID = _FM-A _FM-SAME
_FM-M 2048 _USF-I-DST UFLD-BUILDER-INIT UFLD-S-INVALID = _FM-A _FM-SAME
_FM-FINISH
_FM-DONE
'''
    run_field(program, minimum=140)


def test_field_integer_clamp_signed_extremes_and_large_adjustments():
    lo, hi = -(1 << 63), (1 << 63) - 1
    cases = [(7, -20, 30, 4, a) for a in (0, 1, -1, 100, -100, lo, hi)]
    cases += [(v, lo, hi, step, a)
              for v in (lo, -1, 0, hi)
              for step in (1, hi)
              for a in (lo, hi, -1, 0, 1)]
    cases += [(4, 4, 4, hi, lo), (lo, lo, lo, 1, hi)]
    program = PRELUDE
    for value, minimum, maximum, step, adjustment in cases:
        expected = max(minimum, min(maximum, value + step * adjustment))
        program += f"\n{value} {minimum} {maximum} {step} {adjustment} UFLD-INTEGER-CLAMP _FM-OK {expected} = _FM-A\n"
    for args in ((0, 1, 2, 1, 0), (3, 1, 2, 1, 0), (1, 0, 2, 0, 1), (1, 0, 2, -1, 1)):
        program += " ".join(map(str, args)) + " UFLD-INTEGER-CLAMP UFLD-S-INVALID = _FM-A 0= _FM-A\n"
    run_field(program + "\n_FM-DONE\n", minimum=100)
