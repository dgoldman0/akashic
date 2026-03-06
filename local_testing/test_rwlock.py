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
"""Test suite for akashic-rwlock Forth library (rwlock.f).

Tests: RWLOCK, READ-LOCK, READ-UNLOCK, WRITE-LOCK, WRITE-UNLOCK,
       RW-READERS, RW-WRITER?, WITH-READ, WITH-WRITE, RW-INFO,
       data structure layout, and constants.

Note: Full blocking tests (reader blocked behind writer on
another core) require multicore emulation.  These tests cover
single-core fast paths, state transitions, and RAII correctness.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
RWLOCK_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "rwlock.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + rwlock.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    rwl_lines  = _load_forth_lines(RWLOCK_F)
    helpers = [
        '6 RWLOCK _RW1',
        '5 RWLOCK _RW2',
        'VARIABLE _RES',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + rwl_lines + helpers) + "\n"
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
    print("\n── RWLOCK creation ──\n")

    check("lock# stored correctly (6)",
          [': _T _RW1 @ . ; _T'],
          "6 ")

    check("lock# stored correctly (5)",
          [': _T _RW2 @ . ; _T'],
          "5 ")

    check("readers initially 0",
          [': _T _RW1 RW-READERS . ; _T'],
          "0 ")

    check("writer initially unlocked",
          [': _T _RW1 RW-WRITER? . ; _T'],
          "0 ")

    check("two rwlocks are different addresses",
          [': _T _RW1 _RW2 <> . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Constants ──\n")

    check("_RW-CELLS is 11",
          [': _T _RW-CELLS . ; _T'],
          "11 ")

    check("_RW-SIZE is 88",
          [': _T _RW-SIZE . ; _T'],
          "88 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Field accessors ──\n")

    check("_RW-LOCK# is +0",
          [': _T _RW1 _RW-LOCK# _RW1 - . ; _T'],
          "0 ")

    check("_RW-READERS is +8",
          [': _T _RW1 _RW-READERS _RW1 - . ; _T'],
          "8 ")

    check("_RW-WRITER is +16",
          [': _T _RW1 _RW-WRITER _RW1 - . ; _T'],
          "16 ")

    check("_RW-REVT is +24",
          [': _T _RW1 _RW-REVT _RW1 - . ; _T'],
          "24 ")

    check("_RW-WEVT is +56",
          [': _T _RW1 _RW-WEVT _RW1 - . ; _T'],
          "56 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Embedded events structure ──\n")

    check("read-event flag initially 0",
          [': _T _RW1 _RW-REVT @ . ; _T'],
          "0 ")

    check("write-event flag initially 0",
          [': _T _RW1 _RW-WEVT @ . ; _T'],
          "0 ")

    check("read-event is valid event (EVT-SET?)",
          [': _T _RW1 _RW-REVT EVT-SET? . ; _T'],
          "0 ")

    check("write-event is valid event (EVT-SET?)",
          [': _T _RW1 _RW-WEVT EVT-SET? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── READ-LOCK / READ-UNLOCK ──\n")

    check("READ-LOCK increments readers to 1",
          [': _T _RW1 READ-LOCK _RW1 RW-READERS . _RW1 READ-UNLOCK ; _T'],
          "1 ")

    check("READ-UNLOCK decrements readers back to 0",
          [': _T _RW1 READ-LOCK _RW1 READ-UNLOCK _RW1 RW-READERS . ; _T'],
          "0 ")

    check("multiple READ-LOCKs stack (readers=3)",
          [': _T',
           '  _RW1 READ-LOCK _RW1 READ-LOCK _RW1 READ-LOCK',
           '  _RW1 RW-READERS .',
           '  _RW1 READ-UNLOCK _RW1 READ-UNLOCK _RW1 READ-UNLOCK',
           '; _T'],
          "3 ")

    check("stacked READ-UNLOCK drains to 0",
          [': _T',
           '  _RW1 READ-LOCK _RW1 READ-LOCK _RW1 READ-LOCK',
           '  _RW1 READ-UNLOCK _RW1 READ-UNLOCK _RW1 READ-UNLOCK',
           '  _RW1 RW-READERS .',
           '; _T'],
          "0 ")

    check("writer stays unlocked during reads",
          [': _T _RW1 READ-LOCK _RW1 RW-WRITER? . _RW1 READ-UNLOCK ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WRITE-LOCK / WRITE-UNLOCK ──\n")

    check("WRITE-LOCK sets writer flag",
          [': _T _RW1 WRITE-LOCK _RW1 RW-WRITER? . _RW1 WRITE-UNLOCK ; _T'],
          "-1 ")

    check("WRITE-UNLOCK clears writer flag",
          [': _T _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK _RW1 RW-WRITER? . ; _T'],
          "0 ")

    check("readers stay 0 during write lock",
          [': _T _RW1 WRITE-LOCK _RW1 RW-READERS . _RW1 WRITE-UNLOCK ; _T'],
          "0 ")

    check("write-lock then unlock, then read-lock works",
          [': _T',
           '  _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK',
           '  _RW1 READ-LOCK _RW1 RW-READERS . _RW1 READ-UNLOCK',
           '; _T'],
          "1 ")

    check("two write-lock/unlock cycles are stable",
          [': _T',
           '  _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK',
           '  _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK',
           '  _RW1 RW-WRITER? . _RW1 RW-READERS .',
           '; _T'],
          "0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Read then write sequencing ──\n")

    check("read-lock, unlock, then write-lock succeeds",
          [': _T',
           '  _RW1 READ-LOCK _RW1 READ-UNLOCK',
           '  _RW1 WRITE-LOCK _RW1 RW-WRITER? . _RW1 WRITE-UNLOCK',
           '; _T'],
          "-1 ")

    check("write-lock, unlock, then read-lock succeeds",
          [': _T',
           '  _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK',
           '  _RW1 READ-LOCK _RW1 RW-READERS . _RW1 READ-UNLOCK',
           '; _T'],
          "1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-READ (RAII) ──\n")

    check("WITH-READ executes xt and unlocks",
          [': _NOOP 42 . ;',
           ": _T ['] _NOOP _RW1 WITH-READ _RW1 RW-READERS . ; _T"],
          "42 0 ")

    check("WITH-READ holds read lock during xt",
          [': _CHK _RW1 RW-READERS . ;',
           ": _T ['] _CHK _RW1 WITH-READ ; _T"],
          "1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-WRITE (RAII) ──\n")

    check("WITH-WRITE executes xt and unlocks",
          [': _NOOP2 99 . ;',
           ": _T ['] _NOOP2 _RW1 WITH-WRITE _RW1 RW-WRITER? . ; _T"],
          "99 0 ")

    check("WITH-WRITE holds write lock during xt",
          [': _CHK2 _RW1 RW-WRITER? . ;',
           ": _T ['] _CHK2 _RW1 WITH-WRITE ; _T"],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── RW-INFO ──\n")

    check("RW-INFO shows lock#",
          [': _T _RW1 RW-INFO ; _T'],
          "lock#=")

    check("RW-INFO shows readers=",
          [': _T _RW1 RW-INFO ; _T'],
          "readers=")

    check("RW-INFO shows writer=",
          [': _T _RW1 RW-INFO ; _T'],
          "writer=")

    check("RW-INFO shows revt:",
          [': _T _RW1 RW-INFO ; _T'],
          "revt:")

    check("RW-INFO shows wevt:",
          [': _T _RW1 RW-INFO ; _T'],
          "wevt:")

    # ────────────────────────────────────────────────────────────────
    print("\n── Cross-rwlock independence ──\n")

    check("locking RW1 does not affect RW2 readers",
          [': _T _RW1 READ-LOCK _RW2 RW-READERS . _RW1 READ-UNLOCK ; _T'],
          "0 ")

    check("locking RW1 does not affect RW2 writer",
          [': _T _RW1 WRITE-LOCK _RW2 RW-WRITER? . _RW1 WRITE-UNLOCK ; _T'],
          "0 ")

    check("RW2 uses different spinlock than RW1",
          [': _T _RW1 @ . _RW2 @ . ; _T'],
          "6 5 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Data structure integrity ──\n")

    check("read-lock/unlock cycle preserves event state",
          [': _T',
           '  _RW1 READ-LOCK _RW1 READ-UNLOCK',
           '  _RW1 _RW-REVT EVT-SET? .',
           '  _RW1 _RW-WEVT EVT-SET? .',
           '; _T'],
          "0 0 ")

    check("write-lock/unlock cycle leaves events unset",
          [': _T',
           '  _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK',
           '  _RW1 _RW-REVT EVT-SET? .',
           '  _RW1 _RW-WEVT EVT-SET? .',
           '; _T'],
          "0 0 ")

    check("10 read cycles are stable",
          [': _T',
           '  10 0 DO _RW1 READ-LOCK _RW1 READ-UNLOCK LOOP',
           '  _RW1 RW-READERS . _RW1 RW-WRITER? .',
           '; _T'],
          "0 0 ")

    check("10 write cycles are stable",
          [': _T',
           '  10 0 DO _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK LOOP',
           '  _RW1 RW-READERS . _RW1 RW-WRITER? .',
           '; _T'],
          "0 0 ")

    # ────────────────────────────────────────────────────────────────
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
