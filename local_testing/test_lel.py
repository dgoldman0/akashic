#!/usr/bin/env python3
"""Test suite for akashic-lel (LIRAQ LEL Expression Language).

Uses the Megapad-64 emulator to boot KDOS, load dependencies, and
exercise the LEL evaluator in phases.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
FP32_F     = os.path.join(ROOT_DIR, "akashic", "math", "fp32.f")
FIXED_F    = os.path.join(ROOT_DIR, "akashic", "math", "fixed.f")
STREE_F    = os.path.join(ROOT_DIR, "akashic", "liraq", "state-tree.f")
LEL_F      = os.path.join(ROOT_DIR, "akashic", "liraq", "lel.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

# ---------------------------------------------------------------------------
#  Emulator helpers (same pattern as test_state_tree.py)
# ---------------------------------------------------------------------------

_snapshot = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_forth_lines(path):
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE '):
                continue
            if s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data: bytes, pos: int) -> bytes:
    nl = data.find(b'\n', pos)
    if nl == -1:
        return data[pos:]
    return data[pos:nl + 1]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf
    )

def save_cpu_state(cpu):
    return {
        'pc': cpu.pc,
        'regs': list(cpu.regs),
        'psel': cpu.psel, 'xsel': cpu.xsel, 'spsel': cpu.spsel,
        'flag_z': cpu.flag_z, 'flag_c': cpu.flag_c,
        'flag_n': cpu.flag_n, 'flag_v': cpu.flag_v,
        'flag_p': cpu.flag_p, 'flag_g': cpu.flag_g,
        'flag_i': cpu.flag_i, 'flag_s': cpu.flag_s,
        'd_reg': cpu.d_reg, 'q_out': cpu.q_out, 't_reg': cpu.t_reg,
        'ivt_base': cpu.ivt_base, 'ivec_id': cpu.ivec_id,
        'trap_addr': cpu.trap_addr,
        'halted': cpu.halted, 'idle': cpu.idle,
        'cycle_count': cpu.cycle_count,
        '_ext_modifier': cpu._ext_modifier,
    }

def restore_cpu_state(cpu, state):
    cpu.pc = state['pc']
    cpu.regs[:] = state['regs']
    for k in ('psel', 'xsel', 'spsel',
              'flag_z', 'flag_c', 'flag_n', 'flag_v',
              'flag_p', 'flag_g', 'flag_i', 'flag_s',
              'd_reg', 'q_out', 't_reg',
              'ivt_base', 'ivec_id', 'trap_addr',
              'halted', 'idle', 'cycle_count', '_ext_modifier'):
        setattr(cpu, k, state[k])


def build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + string + fp32 + fixed + state-tree + lel ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    str_lines   = _load_forth_lines(STR_F)
    fp32_lines  = _load_forth_lines(FP32_F)
    fixed_lines = _load_forth_lines(FIXED_F)
    stree_lines = _load_forth_lines(STREE_F)
    lel_lines   = _load_forth_lines(LEL_F)

    test_helpers = [
        # Shared text buffer for building strings
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # State tree init for tests that need it
        ': T-INIT  65536 A-XMEM ARENA-NEW ABORT" arena fail"  256 ST-DOC-NEW  DROP ;',
        # LEL test helpers: print type tag
        ': T-TYPE  ( a l -- )  LEL-EVAL 2DROP . CR ;',
        # Print integer/boolean val1
        ': T-INT   ( a l -- )  LEL-EVAL DROP NIP . CR ;',
        # Print string content
        ': T-STR   ( a l -- )  LEL-EVAL ROT DROP TYPE CR ;',
        # Print float truncated to int
        ': T-FINT  ( a l -- )  LEL-EVAL DROP NIP FP32>INT . CR ;',
        # Print type and int val (2 numbers)
        ': T-TINT  ( a l -- )  LEL-EVAL DROP NIP SWAP . . CR ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + str_lines + fp32_lines + fixed_lines
                 + stree_lines + lel_lines + test_helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 800_000_000

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    err_lines = [l for l in text.strip().split('\n') if '?' in l]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-20:]:
            print(f"    {ln}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=50_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode()
    pos = 0
    steps = 0

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    return uart_text(buf)


# ---------------------------------------------------------------------------
#  Test framework
# ---------------------------------------------------------------------------

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()

    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True

    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        last = clean.split('\n')[-5:]
        print(f"        got (last lines): {last}")


# ---------------------------------------------------------------------------
#  Phase 1 Tests — Literals, state refs, context vars, function call skeleton
# ---------------------------------------------------------------------------

def test_literals():
    """Integer, float, string, boolean, null literals."""

    # Integer literals
    check("int-42", [
        'S" 42" T-TYPE',
    ], '2')

    check("int-42-val", [
        'S" 42" T-INT',
    ], '42')

    check("int-0", [
        'S" 0" T-INT',
    ], '0')

    check("int-neg", [
        'S" -5" T-INT',
    ], '-5')

    check("int-large", [
        'S" 9999" T-INT',
    ], '9999')

    # Float literals
    check("float-type", [
        'S" 3.14" T-TYPE',
    ], '5')

    check("float-trunc", [
        'S" 3.14" T-FINT',
    ], '3')

    check("float-neg-trunc", [
        'S" -2.7" T-FINT',
    ], '-2')

    check("float-1.0", [
        'S" 1.0" T-FINT',
    ], '1')

    # String literals
    check("str-hello", [
        'S" \'hello\'" T-TYPE',
    ], '1')

    check("str-hello-val", [
        'S" \'hello\'" T-STR',
    ], 'hello')

    check("str-empty", [
        "S\" ''\" T-STR",
    ], check_fn=lambda out: 'ok' in out.lower())

    check("str-escape", [
        "S\" 'it''s'\" T-STR",
    ], "it's")

    # Boolean literals
    check("bool-true-type", [
        'S" true" T-TYPE',
    ], '3')

    check("bool-true-val", [
        'S" true" T-INT',
    ], '1')

    check("bool-false-val", [
        'S" false" T-INT',
    ], '0')

    # Null literal
    check("null-type", [
        'S" null" T-TYPE',
    ], '4')


def test_state_refs():
    """State tree path lookups via LEL."""

    check("state-int", [
        'T-INIT',
        '100 S" speed" ST-SET-PATH-INT',
        'S" speed" T-INT',
    ], '100')

    check("state-str", [
        'T-INIT',
        'S" warp" S" drive" ST-SET-PATH-STR',
        'S" drive" T-STR',
    ], 'warp')

    check("state-bool", [
        'T-INIT',
        '1 S" active" ST-SET-PATH-BOOL',
        'S" active" T-INT',
    ], '1')

    check("state-dotted", [
        'T-INIT',
        '42 S" ship.speed" ST-SET-PATH-INT',
        'S" ship.speed" T-INT',
    ], '42')

    check("state-deep", [
        'T-INIT',
        'S" Enterprise" S" ship.info.name" ST-SET-PATH-STR',
        'S" ship.info.name" T-STR',
    ], 'Enterprise')

    check("state-missing", [
        'T-INIT',
        'S" missing.path" T-TYPE',
    ], '4')

    check("state-float", [
        'T-INIT',
        'FP32-PI S" heading" ST-SET-PATH-FLOAT',
        'S" heading" T-FINT',
    ], '3')


def test_context_vars():
    """_index and _item context variables."""

    check("ctx-index", [
        'T-INIT',
        '0 7 LEL-SET-CONTEXT',
        'S" _index" T-INT',
    ], '7')

    check("ctx-index-type", [
        'T-INIT',
        '0 42 LEL-SET-CONTEXT',
        'S" _index" T-TYPE',
    ], '2')

    check("ctx-item-null", [
        'T-INIT',
        'LEL-CLEAR-CONTEXT',
        'S" _item" T-TYPE',
    ], '4')

    # _item pointing to a node with a value
    check("ctx-item-int", [
        'T-INIT',
        '99 S" myval" ST-SET-PATH-INT',
        'S" myval" ST-GET-PATH',
        '5 LEL-SET-CONTEXT',
        'S" _item" T-INT',
    ], '99')


def test_funcall_skeleton():
    """Function calls parse correctly but return null (no builtins yet)."""

    check("func-unknown", [
        'S" foo()" T-TYPE',
    ], '4')

    check("func-with-args", [
        'S" bar(42, 3)" T-TYPE',
    ], '4')

    check("func-nested", [
        'S" foo(bar(1))" T-TYPE',
    ], '4')


def test_edge_cases():
    """Empty expression, whitespace, etc."""

    check("empty-expr", [
        'S" " T-TYPE',
    ], '4')

    check("whitespace-only", [
        'S"   " T-TYPE',
    ], '4')


def test_arithmetic():
    """Phase 2: Arithmetic builtins with float promotion."""

    # Basic integer arithmetic
    check("add-int", [
        'S" add(3, 4)" T-INT',
    ], '7')

    check("sub-int", [
        'S" sub(10, 3)" T-INT',
    ], '7')

    check("mul-int", [
        'S" mul(6, 7)" T-INT',
    ], '42')

    check("div-int", [
        'S" div(20, 4)" T-INT',
    ], '5')

    check("mod-int", [
        'S" mod(17, 5)" T-INT',
    ], '2')

    # Integer division by zero -> 0
    check("div-zero", [
        'S" div(42, 0)" T-INT',
    ], '0')

    check("mod-zero", [
        'S" mod(42, 0)" T-INT',
    ], '0')

    # Negative integer arithmetic
    check("add-neg", [
        'S" add(-3, 7)" T-INT',
    ], '4')

    check("sub-neg-result", [
        'S" sub(3, 10)" T-INT',
    ], '-7')

    # Unary ops
    check("neg-int", [
        'S" neg(42)" T-INT',
    ], '-42')

    check("abs-neg", [
        'S" abs(-7)" T-INT',
    ], '7')

    check("abs-pos", [
        'S" abs(5)" T-INT',
    ], '5')

    # min/max integer
    check("min-int", [
        'S" min(10, 3)" T-INT',
    ], '3')

    check("max-int", [
        'S" max(10, 3)" T-INT',
    ], '10')

    # clamp
    check("clamp-lo", [
        'S" clamp(1, 5, 10)" T-INT',
    ], '5')

    check("clamp-hi", [
        'S" clamp(99, 5, 10)" T-INT',
    ], '10')

    check("clamp-mid", [
        'S" clamp(7, 5, 10)" T-INT',
    ], '7')

    # Float promotion
    check("add-float", [
        'S" add(1, 2.5)" T-FINT',
    ], '3')

    check("sub-float", [
        'S" sub(10.5, 3)" T-FINT',
    ], '7')

    check("mul-float", [
        'S" mul(3.0, 4)" T-FINT',
    ], '12')

    check("div-float", [
        'S" div(7.0, 2.0)" T-FINT',
    ], '3')

    check("float-type-result", [
        'S" add(1, 2.5)" T-TYPE',
    ], '5')

    # Neg/abs on float
    check("neg-float", [
        'S" neg(3.5)" T-FINT',
    ], '-3')

    check("abs-float-neg", [
        'S" abs(-2.5)" T-FINT',
    ], '2')

    # round/floor/ceil
    check("round-up", [
        'S" round(3.7)" T-FINT',
    ], '4')

    check("round-down", [
        'S" round(3.2)" T-FINT',
    ], '3')

    check("floor-pos", [
        'S" floor(3.9)" T-FINT',
    ], '3')

    check("ceil-pos", [
        'S" ceil(3.1)" T-FINT',
    ], '4')

    # min/max float
    check("min-float", [
        'S" min(1.5, 2.5)" T-FINT',
    ], '1')

    check("max-float", [
        'S" max(1.5, 2.5)" T-FINT',
    ], '2')

    # Nested
    check("nested-arith", [
        'S" add(mul(3, 4), 8)" T-INT',
    ], '20')

    check("deep-nested", [
        'S" mul(add(2, 3), sub(10, 4))" T-INT',
    ], '30')

    # Boolean coercion in math
    check("add-bool", [
        'S" add(true, 1)" T-INT',
    ], '2')

    # Null coercion in math
    check("add-null", [
        'S" add(null, 5)" T-INT',
    ], '5')

    # State ref in arithmetic
    check("add-state", [
        'T-INIT',
        '7 S" x" ST-SET-PATH-INT',
        'S" add(x, 3)" T-INT',
    ], '10')


def test_comparison():
    """Phase 3: Comparison builtins."""

    check("eq-int", [
        'S" eq(5, 5)" T-INT',
    ], '1')

    check("eq-int-false", [
        'S" eq(5, 3)" T-INT',
    ], '0')

    check("neq-int", [
        'S" neq(5, 3)" T-INT',
    ], '1')

    check("neq-same", [
        'S" neq(7, 7)" T-INT',
    ], '0')

    check("gt-true", [
        'S" gt(10, 3)" T-INT',
    ], '1')

    check("gt-false", [
        'S" gt(3, 10)" T-INT',
    ], '0')

    check("gte-eq", [
        'S" gte(5, 5)" T-INT',
    ], '1')

    check("lt-true", [
        'S" lt(3, 10)" T-INT',
    ], '1')

    check("lte-eq", [
        'S" lte(5, 5)" T-INT',
    ], '1')

    # Float comparison
    check("gt-float", [
        'S" gt(3.5, 2.0)" T-INT',
    ], '1')

    check("eq-int-float", [
        'S" eq(5, 5.0)" T-INT',
    ], '1')

    # String comparison
    check("eq-str", [
        "S\" eq('hello', 'hello')\" T-INT",
    ], '1')

    check("eq-str-false", [
        "S\" eq('hello', 'world')\" T-INT",
    ], '0')

    check("neq-str", [
        "S\" neq('a', 'b')\" T-INT",
    ], '1')

    # Null comparison
    check("eq-null-null", [
        'S" eq(null, null)" T-INT',
    ], '1')

    check("eq-null-int", [
        'S" eq(null, 0)" T-INT',
    ], '0')

    # Boolean comparison
    check("eq-bool", [
        'S" eq(true, true)" T-INT',
    ], '1')

    check("not-true", [
        'S" not(true)" T-INT',
    ], '0')

    check("not-false", [
        'S" not(false)" T-INT',
    ], '1')

    check("not-zero", [
        'S" not(0)" T-INT',
    ], '1')

    check("not-str", [
        "S\" not('hello')\" T-INT",
    ], '0')


def test_logic():
    """Phase 3: Logic and short-circuit builtins."""

    # if()
    check("if-true", [
        'S" if(true, 42, 99)" T-INT',
    ], '42')

    check("if-false", [
        'S" if(false, 42, 99)" T-INT',
    ], '99')

    check("if-int-cond", [
        'S" if(1, 10, 20)" T-INT',
    ], '10')

    check("if-zero-cond", [
        'S" if(0, 10, 20)" T-INT',
    ], '20')

    check("if-nested", [
        'S" if(true, add(1, 2), 99)" T-INT',
    ], '3')

    # and()
    check("and-true-true", [
        'S" and(true, 42)" T-INT',
    ], '42')

    check("and-false-skip", [
        'S" and(false, 42)" T-INT',
    ], '0')

    check("and-returns-a", [
        'S" and(0, 99)" T-INT',
    ], '0')

    # or()
    check("or-true-skip", [
        'S" or(42, 99)" T-INT',
    ], '42')

    check("or-false-b", [
        'S" or(false, 99)" T-INT',
    ], '99')

    check("or-zero-b", [
        'S" or(0, 77)" T-INT',
    ], '77')

    # coalesce()
    check("coalesce-nonnull", [
        'S" coalesce(42, 99)" T-INT',
    ], '42')

    check("coalesce-null", [
        'S" coalesce(null, 99)" T-INT',
    ], '99')

    # Nested short-circuit
    check("if-in-add", [
        'S" add(if(true, 10, 20), 5)" T-INT',
    ], '15')

    check("nested-if", [
        'S" if(gt(10, 5), mul(3, 4), 0)" T-INT',
    ], '12')


def test_string_builtins():
    """Phase 4: String builtins."""

    # concat
    check("concat-2", [
        "S\" concat('hello', ' world')\" T-STR",
    ], 'hello world')

    check("concat-3", [
        "S\" concat('a', 'b', 'c')\" T-STR",
    ], 'abc')

    check("concat-int", [
        "S\" concat('val=', 42)\" T-STR",
    ], 'val=42')

    check("concat-empty", [
        'S" concat()" T-TYPE',
    ], '1')

    # length
    check("length-str", [
        "S\" length('hello')\" T-INT",
    ], '5')

    check("length-empty", [
        "S\" length('')\" T-INT",
    ], '0')

    # upper/lower
    check("upper", [
        "S\" upper('hello')\" T-STR",
    ], 'HELLO')

    check("lower", [
        "S\" lower('WORLD')\" T-STR",
    ], 'world')

    # trim
    check("trim", [
        "S\" trim('  hi  ')\" T-STR",
    ], 'hi')

    # substring
    check("substring-mid", [
        "S\" substring('hello world', 6, 5)\" T-STR",
    ], 'world')

    check("substring-start", [
        "S\" substring('hello', 0, 3)\" T-STR",
    ], 'hel')

    # contains
    check("contains-true", [
        "S\" contains('hello world', 'world')\" T-INT",
    ], '1')

    check("contains-false", [
        "S\" contains('hello', 'xyz')\" T-INT",
    ], '0')

    # starts-with / ends-with
    check("starts-with-true", [
        "S\" starts-with('hello', 'hel')\" T-INT",
    ], '1')

    check("starts-with-false", [
        "S\" starts-with('hello', 'xyz')\" T-INT",
    ], '0')

    check("ends-with-true", [
        "S\" ends-with('hello', 'llo')\" T-INT",
    ], '1')

    check("ends-with-false", [
        "S\" ends-with('hello', 'xyz')\" T-INT",
    ], '0')


def test_type_builtins():
    """Phase 5: Type builtins."""

    check("to-string-int", [
        'S" to-string(42)" T-STR',
    ], '42')

    check("to-string-str", [
        "S\" to-string('hi')\" T-STR",
    ], 'hi')

    check("to-string-bool", [
        'S" to-string(true)" T-STR',
    ], 'true')

    check("to-number-str", [
        "S\" to-number('42')\" T-INT",
    ], '42')

    check("to-number-bool", [
        'S" to-number(true)" T-INT',
    ], '1')

    check("to-boolean-int", [
        'S" to-boolean(42)" T-INT',
    ], '1')

    check("to-boolean-zero", [
        'S" to-boolean(0)" T-INT',
    ], '0')

    check("is-null-true", [
        'S" is-null(null)" T-INT',
    ], '1')

    check("is-null-false", [
        'S" is-null(42)" T-INT',
    ], '0')

    check("type-of-int", [
        'S" type-of(42)" T-STR',
    ], 'integer')

    check("type-of-str", [
        "S\" type-of('hi')\" T-STR",
    ], 'string')

    check("type-of-null", [
        'S" type-of(null)" T-STR',
    ], 'null')

    check("type-of-bool", [
        'S" type-of(true)" T-STR',
    ], 'boolean')

    check("type-of-float", [
        'S" type-of(3.14)" T-STR',
    ], 'float')


# ---------------------------------------------------------------------------
#  Phase 2 Tests — Infix operators, array functions, string functions,
#  literal, computed linkage
# ---------------------------------------------------------------------------

def test_infix_arithmetic():
    """Infix arithmetic operators."""

    check("infix-add", [
        'S" 2 + 3" T-INT',
    ], '5')

    check("infix-sub", [
        'S" 10 - 4" T-INT',
    ], '6')

    check("infix-mul", [
        'S" 3 * 7" T-INT',
    ], '21')

    check("infix-div", [
        'S" 20 / 4" T-INT',
    ], '5')

    check("infix-mod", [
        'S" 7 % 3" T-INT',
    ], '1')

    check("infix-precedence1", [
        'S" 2 + 3 * 4" T-INT',
    ], '14')

    check("infix-precedence2", [
        'S" (2 + 3) * 4" T-INT',
    ], '20')

    check("infix-unary-neg", [
        'S" -5" T-INT',
    ], '-5')

    check("infix-unary-neg-expr", [
        'S" -(3 + 2)" T-INT',
    ], '-5')

    check("infix-assoc-left", [
        'S" 2 - 3 - 4" T-INT',
    ], '-5')

    check("infix-nested-parens", [
        'S" ((2 + 3))" T-INT',
    ], '5')


def test_infix_comparison():
    """Infix comparison operators."""

    check("infix-gt", [
        'S" 5 > 3" T-INT',
    ], '1')

    check("infix-ge", [
        'S" 3 >= 3" T-INT',
    ], '1')

    check("infix-lt", [
        'S" 2 < 5" T-INT',
    ], '1')

    check("infix-le", [
        'S" 5 <= 5" T-INT',
    ], '1')

    check("infix-eqeq", [
        'S" 3 == 3" T-INT',
    ], '1')

    check("infix-neq", [
        'S" 3 != 4" T-INT',
    ], '1')

    check("infix-gt-false", [
        'S" 2 > 5" T-INT',
    ], '0')

    check("infix-eqeq-false", [
        'S" 3 == 4" T-INT',
    ], '0')


def test_infix_logic():
    """Infix logic operators: and, or, not."""

    check("infix-and-true", [
        'S" true and true" T-INT',
    ], '1')

    check("infix-and-false", [
        'S" true and false" T-INT',
    ], '0')

    check("infix-or-true", [
        'S" false or true" T-INT',
    ], '1')

    check("infix-or-false", [
        'S" false or false" T-INT',
    ], '0')

    check("infix-not", [
        'S" not true" T-INT',
    ], '0')

    check("infix-not-false", [
        'S" not false" T-INT',
    ], '1')

    # Precedence: not a or b and c = (not a) or (b and c)
    check("infix-logic-prec", [
        'S" not false or true and false" T-INT',
    ], '1')


def test_infix_ternary():
    """Ternary ? : operator."""

    check("ternary-true", [
        'S" true ? 1 : 2" T-INT',
    ], '1')

    check("ternary-false", [
        'S" false ? 1 : 2" T-INT',
    ], '2')

    check("ternary-nested", [
        'S" true ? false ? 1 : 2 : 3" T-INT',
    ], '2')

    check("ternary-expr", [
        'S" 3 > 2 ? 10 : 20" T-INT',
    ], '10')


def test_infix_mixed():
    """Mixed infix and function-call expressions."""

    check("infix-func-mix", [
        'T-INIT',
        'S" hello" S" name" ST-SET-PATH-STR',
        "S\" length(name) > 0\" T-INT",
    ], '1')

    check("infix-state-arith", [
        'T-INIT',
        '5 S" a" ST-SET-PATH-INT',
        '3 S" b" ST-SET-PATH-INT',
        'S" a + b" T-INT',
    ], '8')

    check("infix-complex", [
        'T-INIT',
        '10 S" x" ST-SET-PATH-INT',
        'S" (x + 5) * 2 > 20" T-INT',
    ], '1')


def test_literal():
    """literal() function — identity pass-through."""

    check("literal-int", [
        'S" literal(42)" T-INT',
    ], '42')

    check("literal-str", [
        "S\" literal('hello')\" T-STR",
    ], 'hello')


def test_string_funcs():
    """New string functions: replace, split, join, format."""

    check("replace-single", [
        "S\" replace('hello world', 'world', 'earth')\" T-STR",
    ], 'hello earth')

    check("replace-multiple", [
        "S\" replace('ababab', 'ab', 'x')\" T-STR",
    ], 'xxx')

    check("replace-not-found", [
        "S\" replace('hello', 'xyz', 'abc')\" T-STR",
    ], 'hello')

    check("split-comma", [
        'T-INIT',
        "S\" length(split('a,b,c', ','))\" T-INT",
    ], '3')

    check("split-single", [
        'T-INIT',
        "S\" length(split('hello', ','))\" T-INT",
    ], '1')

    check("join-basic", [
        'T-INIT',
        'TR 97 TC 97 TC 97 TC',
        'TA S" items" ST-ARRAY-APPEND-STR',
        'TR 98 TC 98 TC 98 TC',
        'TA S" items" ST-ARRAY-APPEND-STR',
        'TR 99 TC 99 TC 99 TC',
        'TA S" items" ST-ARRAY-APPEND-STR',
        "S\" join(items, ',')\" T-STR",
    ], 'aaa,bbb,ccc')

    check("join-empty-delim", [
        'T-INIT',
        'TR 97 TC 97 TC',
        'TA S" xs" ST-ARRAY-APPEND-STR',
        'TR 98 TC 98 TC',
        'TA S" xs" ST-ARRAY-APPEND-STR',
        "S\" join(xs, '')\" T-STR",
    ], 'aabb')

    check("format-int", [
        "S\" format(42, '')\" T-STR",
    ], '42')


def test_array_funcs():
    """Array functions: at, first, last, includes, reverse."""

    check("at-valid", [
        'T-INIT',
        "10 S\" nums\" ST-ARRAY-APPEND-INT",
        "20 S\" nums\" ST-ARRAY-APPEND-INT",
        "30 S\" nums\" ST-ARRAY-APPEND-INT",
        'S" at(nums, 1)" T-INT',
    ], '20')

    check("at-oob", [
        'T-INIT',
        "10 S\" nums\" ST-ARRAY-APPEND-INT",
        'S" at(nums, 5)" T-TYPE',
    ], '4')

    check("first-nonempty", [
        'T-INIT',
        "10 S\" ns\" ST-ARRAY-APPEND-INT",
        "20 S\" ns\" ST-ARRAY-APPEND-INT",
        'S" first(ns)" T-INT',
    ], '10')

    check("first-empty", [
        'T-INIT',
        'S" es" ST-ENSURE-ARRAY DROP',
        'S" first(es)" T-TYPE',
    ], '4')

    check("last-nonempty", [
        'T-INIT',
        "10 S\" ns\" ST-ARRAY-APPEND-INT",
        "20 S\" ns\" ST-ARRAY-APPEND-INT",
        'S" last(ns)" T-INT',
    ], '20')

    check("includes-found", [
        'T-INIT',
        "10 S\" xs\" ST-ARRAY-APPEND-INT",
        "20 S\" xs\" ST-ARRAY-APPEND-INT",
        "30 S\" xs\" ST-ARRAY-APPEND-INT",
        'S" includes(xs, 20)" T-INT',
    ], '1')

    check("includes-not-found", [
        'T-INIT',
        "10 S\" xs\" ST-ARRAY-APPEND-INT",
        "20 S\" xs\" ST-ARRAY-APPEND-INT",
        'S" includes(xs, 99)" T-INT',
    ], '0')

    check("reverse-basic", [
        'T-INIT',
        "10 S\" rs\" ST-ARRAY-APPEND-INT",
        "20 S\" rs\" ST-ARRAY-APPEND-INT",
        "30 S\" rs\" ST-ARRAY-APPEND-INT",
        'S" first(reverse(rs))" T-INT',
    ], '30')

    check("reverse-last", [
        'T-INIT',
        "10 S\" rs\" ST-ARRAY-APPEND-INT",
        "20 S\" rs\" ST-ARRAY-APPEND-INT",
        "30 S\" rs\" ST-ARRAY-APPEND-INT",
        'S" last(reverse(rs))" T-INT',
    ], '10')

    check("length-array", [
        'T-INIT',
        "10 S\" ar\" ST-ARRAY-APPEND-INT",
        "20 S\" ar\" ST-ARRAY-APPEND-INT",
        'S" length(ar)" T-INT',
    ], '2')


def test_computed_linkage():
    """Phase 2.5 — computed value linkage with LEL evaluator."""

    check("computed-basic", [
        'T-INIT',
        '10 S" base" ST-SET-PATH-INT',
        'TR 98 TC 97 TC 115 TC 101 TC 32 TC 43 TC 32 TC 53 TC',
        'TA S" derived" ST-COMPUTED!',
        'S" derived" ST-GET-PATH DUP ST-COMPUTED? . CR',
    ], check_fn=lambda out: '1' in out)

    check("computed-eval", [
        'T-INIT',
        '10 S" base" ST-SET-PATH-INT',
        'TR 97 TC 100 TC 100 TC 40 TC 98 TC 97 TC 115 TC 101 TC 44 TC 32 TC 53 TC 41 TC',
        'TA S" derived" ST-COMPUTED!',
        'S" derived" ST-GET-PATH',
        'ST-GET-STR LEL-EVAL DROP NIP . CR',
    ], '15')


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    build_snapshot()

    groups = [
        ("Literals",       test_literals),
        ("State Refs",     test_state_refs),
        ("Context Vars",   test_context_vars),
        ("Funcall Skel",   test_funcall_skeleton),
        ("Edge Cases",     test_edge_cases),
        ("Arithmetic",     test_arithmetic),
        ("Comparison",     test_comparison),
        ("Logic",          test_logic),
        ("String",         test_string_builtins),
        ("Type",           test_type_builtins),
        ("Infix Arith",    test_infix_arithmetic),
        ("Infix Compare",  test_infix_comparison),
        ("Infix Logic",    test_infix_logic),
        ("Infix Ternary",  test_infix_ternary),
        ("Infix Mixed",    test_infix_mixed),
        ("Literal Fn",     test_literal),
        ("String Funcs",   test_string_funcs),
        ("Array Funcs",    test_array_funcs),
        ("Computed Link",  test_computed_linkage),
    ]

    for label, fn in groups:
        print(f"\n=== {label} ===")
        fn()

    total = _pass_count + _fail_count
    print(f"\n{'='*60}")
    print(f"  {_pass_count}/{total} passed")
    if _fail_count:
        print(f"  {_fail_count} FAILED")
        sys.exit(1)
    else:
        print("  All tests passed!")
