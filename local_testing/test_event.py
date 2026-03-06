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
"""Test suite for akashic-event Forth library (event.f).

Tests: EVENT, EVT-SET, EVT-RESET, EVT-SET?, EVT-PULSE, EVT-INFO,
       EVT-WAIT (fast-path), EVT-WAIT-TIMEOUT (fast-path + timeout).

Note: Full blocking tests (EVT-WAIT spinning until another core
signals) require multicore emulation.  These tests cover the
single-core fast paths, state transitions, and data structure layout.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    helpers = [
        'EVENT _EV1',
        'EVENT _EV2',
        'EVENT _EV3',
        'VARIABLE _RES',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines + helpers) + "\n"
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
    print("\n── EVENT creation ──\n")

    check("event initially unset",
          [': _T _EV1 EVT-SET? . ; _T'],
          "0 ")

    check("event flag cell is 0",
          [': _T _EV1 @ . ; _T'],
          "0 ")

    check("event wait-count is 0",
          [': _T _EV1 8 + @ . ; _T'],
          "0 ")

    check("event waiter-0 is 0",
          [': _T _EV1 16 + @ . ; _T'],
          "0 ")

    check("event waiter-1 is 0",
          [': _T _EV1 24 + @ . ; _T'],
          "0 ")

    check("two events are different addresses",
          [': _T _EV1 _EV2 <> . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── EVT-SET / EVT-SET? / EVT-RESET ──\n")

    check("EVT-SET makes event set",
          [': _T _EV1 EVT-SET _EV1 EVT-SET? . ; _T'],
          "-1 ")

    check("EVT-RESET clears event",
          [': _T _EV1 EVT-SET _EV1 EVT-RESET _EV1 EVT-SET? . ; _T'],
          "0 ")

    check("EVT-SET writes -1 to flag cell",
          [': _T _EV1 EVT-SET _EV1 @ . ; _T'],
          "-1 ")

    check("EVT-RESET writes 0 to flag cell",
          [': _T _EV1 EVT-SET _EV1 EVT-RESET _EV1 @ . ; _T'],
          "0 ")

    check("double SET is idempotent",
          [': _T _EV1 EVT-SET _EV1 EVT-SET _EV1 EVT-SET? . ; _T'],
          "-1 ")

    check("double RESET is safe",
          [': _T _EV1 EVT-RESET _EV1 EVT-RESET _EV1 EVT-SET? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── EVT-WAIT (fast path — already set) ──\n")

    check("EVT-WAIT on set event returns immediately",
          [': _T _EV2 EVT-SET _EV2 EVT-WAIT 42 . ; _T'],
          "42 ")

    check("EVT-WAIT on set event does not hang",
          [': _T _EV2 EVT-SET _EV2 EVT-WAIT _EV2 EVT-SET? . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── EVT-WAIT-TIMEOUT ──\n")

    check("timeout on set event returns TRUE immediately",
          [': _T _EV2 EVT-SET _EV2 1000 EVT-WAIT-TIMEOUT . ; _T'],
          "-1 ")

    check("timeout on unset event returns FALSE",
          [': _T _EV3 EVT-RESET _EV3 1 EVT-WAIT-TIMEOUT . ; _T'],
          "0 ")

    check("timeout on unset event with 0ms returns FALSE",
          [': _T _EV3 EVT-RESET _EV3 0 EVT-WAIT-TIMEOUT . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── EVT-PULSE ──\n")

    check("pulse on unset event leaves it unset",
          [': _T _EV3 EVT-RESET _EV3 EVT-PULSE _EV3 EVT-SET? . ; _T'],
          "0 ")

    check("pulse on set event leaves it unset",
          [': _T _EV3 EVT-SET _EV3 EVT-PULSE _EV3 EVT-SET? . ; _T'],
          "0 ")

    check("pulse clears waiters (wait-count stays 0)",
          [': _T _EV3 EVT-PULSE _EV3 8 + @ . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── EVT-INFO ──\n")

    check("EVT-INFO on unset event shows UNSET",
          [': _T _EV3 EVT-RESET _EV3 EVT-INFO ; _T'],
          "UNSET")

    check("EVT-INFO on set event shows SET",
          [': _T _EV3 EVT-SET _EV3 EVT-INFO ; _T'],
          "SET")

    check("EVT-INFO shows waiters=0",
          [': _T _EV3 EVT-RESET _EV3 EVT-INFO ; _T'],
          "waiters=0")

    # ────────────────────────────────────────────────────────────────
    print("\n── Data structure integrity ──\n")

    check("set then reset preserves waiter slots",
          [': _T',
           '  _EV1 EVT-SET _EV1 EVT-RESET',
           '  _EV1 16 + @ .  _EV1 24 + @ .',
           '; _T'],
          "0 0 ")

    check("multiple set/reset cycles are stable",
          [': _T',
           '  10 0 DO _EV1 EVT-SET _EV1 EVT-RESET LOOP',
           '  _EV1 EVT-SET? . _EV1 8 + @ .',
           '; _T'],
          "0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Constants ──\n")

    check("EVT-LOCK is 6",
          [': _T EVT-LOCK . ; _T'],
          "6 ")

    check("_EVT-CELLS is 4",
          [': _T _EVT-CELLS . ; _T'],
          "4 ")

    check("_EVT-SIZE is 32",
          [': _T _EVT-SIZE . ; _T'],
          "32 ")

    check("_EVT-MAX-WAITERS is 2",
          [': _T _EVT-MAX-WAITERS . ; _T'],
          "2 ")

    # ────────────────────────────────────────────────────────────────
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
