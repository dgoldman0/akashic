#!/usr/bin/env python3
# ┌──────────────────────────────────────────────────────────────┐
# │ HARNESS UPDATE REQUIRED (March 2026)                         │
# │                                                              │
# │ 1. BOOT-TO-IDLE: run_forth() must call boot() on a fresh    │
# │    MegapadSystem before overwriting RAM/CPU state from the   │
# │    snapshot.  Without boot(), the C++ accelerator's MMIO     │
# │    routing (UART writes) is never wired → empty output.      │
# │    Fix: save bios_code in the snapshot tuple, then in        │
# │    run_forth(): load_binary(0, bios_code), boot(), run to    │
# │    idle, THEN overwrite mem/cpu/ext from snapshot.           │
# │                                                              │
# │ 2. NO [: ;] CLOSURES: This BIOS/KDOS does not define the    │
# │    [: ... ;] anonymous quotation words.  Replace all uses    │
# │    with named helper words and ['] ticks.                    │
# │                                                              │
# │ See test_coroutine.py for the corrected pattern.             │
# └──────────────────────────────────────────────────────────────┘
"""Test suite for akashic-cvar Forth library (cvar.f).

Tests: CVAR, CV@, CV!, CV-CAS, CV-ADD, CV-WAIT (fast path),
       CV-WAIT-TIMEOUT, CV-RESET, CV-INFO.

The emulator runs single-core, so full blocking CV-WAIT tests
(spinning until another core writes) are not exercised.  We test
fast-path CV-WAIT (value already differs), CV-WAIT-TIMEOUT with
zero timeout, and all atomic operations.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
CVAR_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "cvar.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + cvar.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    cv_lines   = _load_forth_lines(CVAR_F)
    helpers = [
        # Named cvars for testing
        '0 CVAR _CV1',
        '42 CVAR _CV2',
        '-1 CVAR _CV3',
        '100 CVAR _CV4',
        'VARIABLE _RES  0 _RES !',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + cv_lines + helpers) + "\n"
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

# ── Tests ──

if __name__ == '__main__':
    build_snapshot()

    # ────────────────────────────────────────────────────────────────
    print("\n── CVAR Creation & CV@ ──\n")

    check("CVAR initial value 0",
          [': _T _CV1 CV@ . ; _T'],
          "0 ")

    check("CVAR initial value 42",
          [': _T _CV2 CV@ . ; _T'],
          "42 ")

    check("CVAR initial value -1",
          [': _T _CV3 CV@ . ; _T'],
          "-1 ")

    check("CVAR initial value 100",
          [': _T _CV4 CV@ . ; _T'],
          "100 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CV! — Atomic Write ──\n")

    check("CV! stores value",
          [': _T 99 _CV1 CV! _CV1 CV@ . ; _T'],
          "99 ")

    check("CV! stores 0",
          [': _T 0 _CV1 CV! _CV1 CV@ . ; _T'],
          "0 ")

    check("CV! stores negative",
          [': _T -42 _CV1 CV! _CV1 CV@ . ; _T'],
          "-42 ")

    check("CV! stores large value",
          [': _T 999999 _CV1 CV! _CV1 CV@ . ; _T'],
          "999999 ")

    check("CV! on different cvars independent",
          [': _T 10 _CV1 CV! 20 _CV2 CV! _CV1 CV@ . _CV2 CV@ . ; _T'],
          "10 20 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CV-ADD — Atomic Fetch-and-Add ──\n")

    check("CV-ADD increments by 1",
          [': _T 0 _CV1 CV! 1 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "1 ")

    check("CV-ADD increments by 10",
          [': _T 0 _CV1 CV! 10 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "10 ")

    check("CV-ADD accumulates",
          [': _T 0 _CV1 CV! 5 _CV1 CV-ADD 3 _CV1 CV-ADD 2 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "10 ")

    check("CV-ADD negative",
          [': _T 10 _CV1 CV! -3 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "7 ")

    check("CV-ADD from nonzero base",
          [': _T 100 _CV1 CV! 50 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "150 ")

    check("CV-ADD zero is no-op",
          [': _T 42 _CV1 CV! 0 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "42 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CV-CAS — Compare-and-Swap ──\n")

    check("CV-CAS succeeds when match",
          [': _T 0 _CV1 CV! 0 1 _CV1 CV-CAS . _CV1 CV@ . ; _T'],
          "-1 1 ")

    check("CV-CAS fails when mismatch",
          [': _T 0 _CV1 CV! 5 1 _CV1 CV-CAS . _CV1 CV@ . ; _T'],
          "0 0 ")

    check("CV-CAS chain: 0→1→2",
          [': _T 0 _CV1 CV! 0 1 _CV1 CV-CAS . 1 2 _CV1 CV-CAS . _CV1 CV@ . ; _T'],
          "-1 -1 2 ")

    check("CV-CAS fails after change",
          [': _T 0 _CV1 CV! 10 _CV1 CV! 0 1 _CV1 CV-CAS . _CV1 CV@ . ; _T'],
          "0 10 ")

    check("CV-CAS swap to 0",
          [': _T 42 _CV1 CV! 42 0 _CV1 CV-CAS . _CV1 CV@ . ; _T'],
          "-1 0 ")

    check("CV-CAS swap to negative",
          [': _T 0 _CV1 CV! 0 -1 _CV1 CV-CAS . _CV1 CV@ . ; _T'],
          "-1 -1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CV-WAIT — Fast Path ──\n")

    check("CV-WAIT returns immediately if value differs",
          [': _T 42 _CV1 CV! 0 _CV1 CV-WAIT 99 . ; _T'],
          "99 ")

    check("CV-WAIT returns for negative expected",
          [': _T 1 _CV1 CV! -1 _CV1 CV-WAIT 77 . ; _T'],
          "77 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CV-WAIT-TIMEOUT ──\n")

    check("CV-WAIT-TIMEOUT returns TRUE if value already differs",
          [': _T 42 _CV1 CV! 0 _CV1 1000 CV-WAIT-TIMEOUT . ; _T'],
          "-1 ")

    check("CV-WAIT-TIMEOUT returns FALSE on 0ms timeout when same",
          [': _T 0 _CV1 CV! 0 _CV1 0 CV-WAIT-TIMEOUT . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CV-RESET ──\n")

    check("CV-RESET sets value without notify",
          [': _T 99 _CV1 CV-RESET _CV1 CV@ . ; _T'],
          "99 ")

    check("CV-RESET to 0",
          [': _T 0 _CV1 CV-RESET _CV1 CV@ . ; _T'],
          "0 ")

    check("CV-RESET then CV@ works",
          [': _T 123 _CV1 CV-RESET _CV1 CV@ . ; _T'],
          "123 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CV-INFO ──\n")

    check("CV-INFO outputs prefix",
          [': _T _CV1 CV-INFO ; _T'],
          "[cvar")

    check("CV-INFO shows val=",
          [': _T 42 _CV1 CV! _CV1 CV-INFO ; _T'],
          "val=")

    # ────────────────────────────────────────────────────────────────
    print("\n── Integration ──\n")

    check("multiple ops sequence: CV! CV-ADD CV@ ",
          [': _T 10 _CV1 CV! 5 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "15 ")

    check("CAS + ADD combo",
          [': _T 0 _CV1 CV! 0 10 _CV1 CV-CAS DROP 5 _CV1 CV-ADD _CV1 CV@ . ; _T'],
          "15 ")

    check("independent cvars after ops",
          [': _T 1 _CV1 CV! 2 _CV2 CV! 3 _CV3 CV! _CV1 CV@ . _CV2 CV@ . _CV3 CV@ . ; _T'],
          "1 2 3 ")

    check("CV-ADD in loop (10 iterations)",
          [': _T 0 _CV1 CV! 10 0 DO 1 _CV1 CV-ADD LOOP _CV1 CV@ . ; _T'],
          "10 ")

    check("CAS spin loop pattern",
          [': _T 0 _CV1 CV!',
           '  BEGIN 0 1 _CV1 CV-CAS UNTIL',
           '  _CV1 CV@ . ; _T'],
          "1 ")

    # ────────────────────────────────────────────────────────────────
    # Done
    print(f"\n{'='*60}")
    print(f"  {_pass} passed, {_fail} failed, {_pass + _fail} total")
    print(f"{'='*60}")
    sys.exit(1 if _fail else 0)
