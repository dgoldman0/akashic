#!/usr/bin/env python3
"""Test suite for akashic-string Forth library (string.f).

Tests: STR-STR=, STR-STRI=, STR-STARTS?, STR-STARTSI?, STR-ENDS?,
       STR-INDEX, STR-RINDEX, STR-SPLIT, STR-TRIM, STR-TOLOWER,
       STR-TOUPPER, NUM>STR, STR>NUM.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "utils", "string", "string.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ──

_snapshot = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_forth_lines(path):
    with open(path) as f:
        return [line for line in f.read().splitlines()
                if line.strip() and not line.strip().startswith('\\')]

def _next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    return data[pos:nl+1] if nl != -1 else data[pos:]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf)

def save_cpu_state(cpu):
    return {k: getattr(cpu, k) for k in
            ['pc','psel','xsel','spsel','flag_z','flag_c','flag_n','flag_v',
             'flag_p','flag_g','flag_i','flag_s','d_reg','q_out','t_reg',
             'ivt_base','ivec_id','trap_addr','halted','idle','cycle_count',
             '_ext_modifier']} | {'regs': list(cpu.regs)}

def restore_cpu_state(cpu, state):
    cpu.regs[:] = state['regs']
    for k, v in state.items():
        if k != 'regs':
            setattr(cpu, k, v)

def build_snapshot():
    global _snapshot
    if _snapshot: return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + string.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 256 ALLOT  VARIABLE _UL',
        ': UR  0 _UL ! ;',
        ': UC  ( c -- ) _UB _UL @ + C!  1 _UL +! ;',
        ': UA  ( -- addr u ) _UB _UL @ ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + str_lines + helpers) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 600_000_000
    while steps < mx:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)
    text = uart_text(buf)
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            print(f"  [!] {l}")
    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode(); pos = 0; steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)

def tstr(s, buf='T'):
    """Build Forth lines that construct string s in _TB (T) or _UB (U)."""
    r = 'TR' if buf == 'T' else 'UR'
    c = 'TC' if buf == 'T' else 'UC'
    a = 'TA' if buf == 'T' else 'UA'
    parts = [r]
    for ch in s:
        parts.append(f'{ord(ch)} {c}')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp == -1: sp = 70
        lines.append(full[:sp]); full = full[sp:].lstrip()
    if full: lines.append(full)
    return lines

# ── Test framework ──

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")

# =====================================================================
#  Tests
# =====================================================================

def test_str_str_equal():
    print("\n── STR-STR= ──")
    # equal strings
    check("equal", tstr("hello") + tstr("hello", 'U') + [
        'TA UA STR-STR= .'
    ], "-1")
    # different strings
    check("differ", tstr("hello") + tstr("world", 'U') + [
        'TA UA STR-STR= .'
    ], "0")
    # different lengths
    check("diff-len", tstr("he") + tstr("hello", 'U') + [
        'TA UA STR-STR= .'
    ], "0")
    # empty strings
    check("empty", [
        '0 0 0 0 STR-STR= .'
    ], "-1")
    # case matters
    check("case-sens", tstr("Hello") + tstr("hello", 'U') + [
        'TA UA STR-STR= .'
    ], "0")

def test_str_stri_equal():
    print("\n── STR-STRI= ──")
    check("same-case", tstr("hello") + tstr("hello", 'U') + [
        'TA UA STR-STRI= .'
    ], "-1")
    check("diff-case", tstr("Hello") + tstr("hELLO", 'U') + [
        'TA UA STR-STRI= .'
    ], "-1")
    check("not-equal", tstr("Hello") + tstr("World", 'U') + [
        'TA UA STR-STRI= .'
    ], "0")
    check("diff-len-i", tstr("Hi") + tstr("Hello", 'U') + [
        'TA UA STR-STRI= .'
    ], "0")
    check("empty-i", [
        '0 0 0 0 STR-STRI= .'
    ], "-1")

def test_str_starts():
    print("\n── STR-STARTS? ──")
    check("starts-yes", tstr("hello world") + tstr("hello", 'U') + [
        'TA UA STR-STARTS? .'
    ], "-1")
    check("starts-no", tstr("hello world") + tstr("world", 'U') + [
        'TA UA STR-STARTS? .'
    ], "0")
    check("starts-empty", tstr("hello") + [
        'TA 0 0 STR-STARTS? .'
    ], "-1")
    check("starts-too-long", tstr("hi") + tstr("hello", 'U') + [
        'TA UA STR-STARTS? .'
    ], "0")

def test_str_startsi():
    print("\n── STR-STARTSI? ──")
    check("startsi-yes", tstr("Hello World") + tstr("hello", 'U') + [
        'TA UA STR-STARTSI? .'
    ], "-1")
    check("startsi-no", tstr("Hello World") + tstr("world", 'U') + [
        'TA UA STR-STARTSI? .'
    ], "0")
    check("startsi-content-length",
        tstr("Content-Length: 42") + tstr("content-length:", 'U') + [
        'TA UA STR-STARTSI? .'
    ], "-1")

def test_str_ends():
    print("\n── STR-ENDS? ──")
    check("ends-yes", tstr("hello world") + tstr("world", 'U') + [
        'TA UA STR-ENDS? .'
    ], "-1")
    check("ends-no", tstr("hello world") + tstr("hello", 'U') + [
        'TA UA STR-ENDS? .'
    ], "0")
    check("ends-empty", tstr("hello") + [
        'TA 0 0 STR-ENDS? .'
    ], "-1")
    check("ends-too-long", tstr("hi") + tstr("hello", 'U') + [
        'TA UA STR-ENDS? .'
    ], "0")
    check("ends-ext", tstr("image.png") + tstr(".png", 'U') + [
        'TA UA STR-ENDS? .'
    ], "-1")

def test_str_index():
    print("\n── STR-INDEX ──")
    check("idx-found", tstr("hello") + [
        'TA 108 STR-INDEX .'
    ], "2")  # 'l' at index 2
    check("idx-first", tstr("abcabc") + [
        'TA 98 STR-INDEX .'
    ], "1")  # 'b' first at index 1
    check("idx-not", tstr("hello") + [
        'TA 122 STR-INDEX .'
    ], "-1")
    check("idx-empty", [
        '0 0 120 STR-INDEX .'
    ], "-1")

def test_str_rindex():
    print("\n── STR-RINDEX ──")
    check("ridx-found", tstr("hello") + [
        'TA 108 STR-RINDEX .'
    ], "3")  # last 'l' at index 3
    check("ridx-last", tstr("abcabc") + [
        'TA 98 STR-RINDEX .'
    ], "4")  # last 'b' at index 4
    check("ridx-not", tstr("hello") + [
        'TA 122 STR-RINDEX .'
    ], "-1")

def test_str_split():
    print("\n── STR-SPLIT ──")
    check("split-found", tstr("key=value") + [
        'TA 61 STR-SPLIT . TYPE 124 EMIT TYPE'
    ], "-1 value|key")
    check("split-not", tstr("hello") + [
        'TA 58 STR-SPLIT . . . TYPE'
    ], "0 0 0 hello")
    check("split-first", tstr("a:b:c") + [
        'TA 58 STR-SPLIT . TYPE 124 EMIT TYPE'
    ], "-1 b:c|a")

def test_str_trim():
    print("\n── STR-TRIM ──")
    check("trim-both", tstr("  hello  ") + [
        'TA STR-TRIM TYPE'
    ], "hello")
    check("trim-left", tstr("   hi") + [
        'TA STR-TRIM-L TYPE'
    ], "hi")
    check("trim-right", tstr("hi   ") + [
        'TA STR-TRIM-R TYPE'
    ], "hi")
    check("trim-tabs", tstr("\t\n hi \r\n") + [
        'TA STR-TRIM TYPE'
    ], "hi")
    check("trim-empty", [
        '0 0 STR-TRIM . .'
    ], "0 0")

def test_str_tolower():
    print("\n── STR-TOLOWER ──")
    check("tolower", tstr("Hello WORLD 123") + [
        'TA 2DUP STR-TOLOWER TYPE'
    ], "hello world 123")

def test_str_toupper():
    print("\n── STR-TOUPPER ──")
    check("toupper", tstr("Hello world 123") + [
        'TA 2DUP STR-TOUPPER TYPE'
    ], "HELLO WORLD 123")

def test_num_to_str():
    print("\n── NUM>STR ──")
    check("n2s-0", [
        '0 NUM>STR TYPE'
    ], "0")
    check("n2s-42", [
        '42 NUM>STR TYPE'
    ], "42")
    check("n2s-neg", [
        '-123 NUM>STR TYPE'
    ], "-123")
    check("n2s-1000", [
        '1000 NUM>STR TYPE'
    ], "1000")

def test_str_to_num():
    print("\n── STR>NUM ──")
    check("s2n-42", tstr("42") + [
        'TA STR>NUM . .'
    ], "-1 42")
    check("s2n-neg", tstr("-99") + [
        'TA STR>NUM . .'
    ], "-1 -99")
    check("s2n-0", tstr("0") + [
        'TA STR>NUM . .'
    ], "-1 0")
    check("s2n-bad", tstr("abc") + [
        'TA STR>NUM . .'
    ], "0 0")
    check("s2n-empty", [
        '0 0 STR>NUM . .'
    ], "0 0")
    check("s2n-plus", tstr("+55") + [
        'TA STR>NUM . .'
    ], "-1 55")

# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()

    test_str_str_equal()
    test_str_stri_equal()
    test_str_starts()
    test_str_startsi()
    test_str_ends()
    test_str_index()
    test_str_rindex()
    test_str_split()
    test_str_trim()
    test_str_tolower()
    test_str_toupper()
    test_num_to_str()
    test_str_to_num()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)
