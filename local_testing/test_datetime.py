#!/usr/bin/env python3
"""Test suite for akashic-datetime Forth library (datetime.f).

Tests: DT-LEAP?, DT-EPOCH>YMD, DT-EPOCH>HMS, DT-YMD>EPOCH,
       DT-DATE, DT-TIME, DT-ISO8601, DT-PARSE-ISO, DT-NOW.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
DT_F       = os.path.join(ROOT_DIR, "utils", "datetime", "datetime.f")

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
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

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
    print("[*] Building snapshot: BIOS + KDOS + datetime.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    dt_lines   = _load_forth_lines(DT_F)
    helpers = [
        'CREATE _TB 64 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _OB 64 ALLOT',   # output buffer for formatting
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + dt_lines + helpers) + "\n"
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

# ── Test runner ──

_pass = 0
_fail = 0

def check(name, forth_lines, expected):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        print(f"  PASS  {name}")
        _pass += 1
    else:
        print(f"  FAIL  {name}")
        print(f"        expected: {expected!r}")
        print(f"        got (last lines): {clean.split(chr(10))[-3:]}")
        _fail += 1

def tstr(s):
    """Build string s in _TB via TR/TC.  Returns list of Forth lines."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp == -1: sp = 70
        lines.append(full[:sp])
        full = full[sp:].lstrip()
    if full: lines.append(full)
    return lines

# ── Tests ──

def run_tests():
    global _pass, _fail
    _pass = 0; _fail = 0

    print("\n── Leap Year ──\n")

    check("2000 is leap",
          [': _T 2000 DT-LEAP? . ; _T'],
          "-1 ")

    check("1900 not leap",
          [': _T 1900 DT-LEAP? . ; _T'],
          "0 ")

    check("2024 is leap",
          [': _T 2024 DT-LEAP? . ; _T'],
          "-1 ")

    check("2023 not leap",
          [': _T 2023 DT-LEAP? . ; _T'],
          "0 ")

    check("1600 is leap",
          [': _T 1600 DT-LEAP? . ; _T'],
          "-1 ")

    check("2100 not leap",
          [': _T 2100 DT-LEAP? . ; _T'],
          "0 ")

    print("\n── EPOCH>YMD ──\n")

    # 0 = 1970-01-01
    check("epoch 0 = 1970-01-01",
          [': _T 0 DT-EPOCH>YMD . . . ; _T'],
          "1 1 1970 ")

    # 86400 = 1970-01-02
    check("epoch 86400 = 1970-01-02",
          [': _T 86400 DT-EPOCH>YMD . . . ; _T'],
          "2 1 1970 ")

    # 951782400 = 2000-02-29  (leap day)
    check("2000-02-29 leap day",
          [': _T 951782400 DT-EPOCH>YMD . . . ; _T'],
          "29 2 2000 ")

    # 1718454600 = 2024-06-15  (12:30:00 UTC)
    check("2024-06-15",
          [': _T 1718454600 DT-EPOCH>YMD . . . ; _T'],
          "15 6 2024 ")

    # 1704067200 = 2024-01-01 00:00:00
    check("2024-01-01",
          [': _T 1704067200 DT-EPOCH>YMD . . . ; _T'],
          "1 1 2024 ")

    # 1735689600 = 2025-01-01
    check("2025-01-01",
          [': _T 1735689600 DT-EPOCH>YMD . . . ; _T'],
          "1 1 2025 ")

    # 946684800 = 2000-01-01
    check("2000-01-01",
          [': _T 946684800 DT-EPOCH>YMD . . . ; _T'],
          "1 1 2000 ")

    # 1735603200 = 2024-12-31
    check("2024-12-31",
          [': _T 1735603200 DT-EPOCH>YMD . . . ; _T'],
          "31 12 2024 ")

    print("\n── EPOCH>HMS ──\n")

    check("midnight",
          [': _T 0 DT-EPOCH>HMS . . . ; _T'],
          "0 0 0 ")

    check("01:02:03",
          [': _T 3723 DT-EPOCH>HMS . . . ; _T'],
          "3 2 1 ")

    # 1718465400 = 15:30:00 UTC
    check("15:30:00",
          [': _T 1718465400 DT-EPOCH>HMS . . . ; _T'],
          "0 30 15 ")

    check("23:59:59",
          [': _T 86399 DT-EPOCH>HMS . . . ; _T'],
          "59 59 23 ")

    print("\n── YMD>EPOCH ──\n")

    check("1970-01-01 → 0",
          [': _T 1970 1 1 DT-YMD>EPOCH . ; _T'],
          "0 ")

    check("2000-01-01 → 946684800",
          [': _T 2000 1 1 DT-YMD>EPOCH . ; _T'],
          "946684800 ")

    check("2000-02-29 → 951782400",
          [': _T 2000 2 29 DT-YMD>EPOCH . ; _T'],
          "951782400 ")

    check("2024-01-01 → 1704067200",
          [': _T 2024 1 1 DT-YMD>EPOCH . ; _T'],
          "1704067200 ")

    check("2024-06-15 → 1718409600",
          [': _T 2024 6 15 DT-YMD>EPOCH . ; _T'],
          "1718409600 ")

    # Round-trip: epoch → ymd → epoch
    check("round-trip 951782400",
          [': _T 951782400 DT-EPOCH>YMD DT-YMD>EPOCH . ; _T'],
          "951782400 ")

    check("round-trip 1704067200",
          [': _T 1704067200 DT-EPOCH>YMD DT-YMD>EPOCH . ; _T'],
          "1704067200 ")

    print("\n── Formatting ──\n")

    check("DT-DATE 2024-06-15",
          [': _T 1718409600 _OB 64 DT-DATE',
           '_OB SWAP TYPE ; _T'],
          "2024-06-15")

    check("DT-DATE returns 10",
          [': _T 1718409600 _OB 64 DT-DATE . ; _T'],
          "10 ")

    check("DT-TIME 15:30:00",
          [': _T 1718465400 _OB 64 DT-TIME',
           '_OB SWAP TYPE ; _T'],
          "15:30:00")

    check("DT-TIME returns 8",
          [': _T 1718465400 _OB 64 DT-TIME . ; _T'],
          "8 ")

    check("DT-ISO8601 full",
          [': _T 1718465400 _OB 64 DT-ISO8601',
           '_OB SWAP TYPE ; _T'],
          "2024-06-15T15:30:00Z")

    check("DT-ISO8601 returns 20",
          [': _T 1718465400 _OB 64 DT-ISO8601 . ; _T'],
          "20 ")

    check("DT-ISO8601 epoch 0",
          [': _T 0 _OB 64 DT-ISO8601',
           '_OB SWAP TYPE ; _T'],
          "1970-01-01T00:00:00Z")

    check("DT-DATE 2000-02-29",
          [': _T 951782400 _OB 64 DT-DATE',
           '_OB SWAP TYPE ; _T'],
          "2000-02-29")

    print("\n── Parsing ──\n")

    check("parse 2024-06-15T15:30:00Z",
          tstr("2024-06-15T15:30:00Z") +
          [': _T TA DT-PARSE-ISO . . ; _T'],
          "0 1718465400 ")

    check("parse 1970-01-01T00:00:00Z",
          tstr("1970-01-01T00:00:00Z") +
          [': _T TA DT-PARSE-ISO . . ; _T'],
          "0 0 ")

    check("parse 2000-02-29T00:00:00Z",
          tstr("2000-02-29T00:00:00Z") +
          [': _T TA DT-PARSE-ISO . . ; _T'],
          "0 951782400 ")

    check("parse 2024-01-01T00:00:00Z",
          tstr("2024-01-01T00:00:00Z") +
          [': _T TA DT-PARSE-ISO . . ; _T'],
          "0 1704067200 ")

    check("parse without trailing Z",
          tstr("2024-06-15T15:30:00") +
          [': _T TA DT-PARSE-ISO . . ; _T'],
          "0 1718465400 ")

    check("parse bad input",
          tstr("not-a-date") +
          [': _T TA DT-PARSE-ISO . ; _T'],
          "-1 ")

    check("parse round-trip ISO8601",
          [': _T 1718465400 _OB 64 DT-ISO8601',
           '_OB SWAP DT-PARSE-ISO . . ; _T'],
          "0 1718465400 ")

    print("\n── DT-NOW ──\n")

    check("DT-NOW returns non-zero",
          [': _T DT-NOW 0 > . ; _T'],
          "-1 ")

    check("DT-NOW-S returns non-zero",
          [': _T DT-NOW-S 0 > . ; _T'],
          "-1 ")

    check("DT-NOW-MS returns non-zero",
          [': _T DT-NOW-MS 0 > . ; _T'],
          "-1 ")

    check("DT-NOW = DT-NOW-S",
          [': _T DT-NOW DT-NOW-S - ABS 2 < . ; _T'],
          "-1 ")

    check("DT-NOW-MS > DT-NOW-S",
          [': _T DT-NOW-MS DT-NOW-S > . ; _T'],
          "-1 ")

    print("\n── Compile Checks ──\n")

    check("DT-LEAP? compiles",
          [': _T 2024 DT-LEAP? DROP ; _T'],
          "")

    check("DT-EPOCH>YMD compiles",
          [': _T 0 DT-EPOCH>YMD 2DROP DROP ; _T'],
          "")

    check("DT-YMD>EPOCH compiles",
          [': _T 1970 1 1 DT-YMD>EPOCH DROP ; _T'],
          "")

    # ── Summary ──
    print(f"\n{'='*40}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*40}\n")
    return _fail == 0


if __name__ == "__main__":
    build_snapshot()
    ok = run_tests()
    sys.exit(0 if ok else 1)
