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
"""Test suite for akashic-semaphore Forth library (semaphore.f).

Tests: SEMAPHORE, SEM-COUNT, SEM-WAIT (fast-path), SEM-SIGNAL,
       SEM-TRYWAIT, SEM-WAIT-TIMEOUT, WITH-SEM, SEM-INFO.

Note: Full blocking tests (SEM-WAIT spinning until another core
calls SEM-SIGNAL) require multicore emulation.  These tests cover
single-core fast paths, state transitions, and RAII correctness.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + semaphore.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    sem_lines  = _load_forth_lines(SEM_F)
    helpers = [
        '3 SEMAPHORE _S1',
        '1 SEMAPHORE _S2',
        '0 SEMAPHORE _S3',
        'VARIABLE _RES',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + sem_lines + helpers) + "\n"
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
    print("\n── SEMAPHORE creation ──\n")

    check("initial count = 3",
          [': _T _S1 SEM-COUNT . ; _T'],
          "3 ")

    check("initial count = 1",
          [': _T _S2 SEM-COUNT . ; _T'],
          "1 ")

    check("initial count = 0",
          [': _T _S3 SEM-COUNT . ; _T'],
          "0 ")

    check("embedded event initially unset",
          [': _T _S1 _SEM-EVT EVT-SET? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Constants ──\n")

    check("_SEM-CELLS is 5",
          [': _T _SEM-CELLS . ; _T'],
          "5 ")

    check("_SEM-SIZE is 40",
          [': _T _SEM-SIZE . ; _T'],
          "40 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── SEM-WAIT (fast path — count > 0) ──\n")

    check("SEM-WAIT decrements count (3 -> 2)",
          [': _T _S1 SEM-WAIT _S1 SEM-COUNT . ; _T'],
          "2 ")

    check("SEM-WAIT on count=1 decrements to 0",
          [': _T _S2 SEM-WAIT _S2 SEM-COUNT . ; _T'],
          "0 ")

    check("two SEM-WAITs on count=3 decrements to 1",
          [': _T _S1 SEM-WAIT _S1 SEM-WAIT _S1 SEM-COUNT . ; _T'],
          "1 ")

    check("three SEM-WAITs on count=3 decrements to 0",
          [': _T _S1 SEM-WAIT _S1 SEM-WAIT _S1 SEM-WAIT _S1 SEM-COUNT . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── SEM-SIGNAL ──\n")

    check("SEM-SIGNAL increments count (3 -> 4)",
          [': _T _S1 SEM-SIGNAL _S1 SEM-COUNT . ; _T'],
          "4 ")

    check("SEM-SIGNAL on count=0 makes count=1",
          [': _T _S3 SEM-SIGNAL _S3 SEM-COUNT . ; _T'],
          "1 ")

    check("wait then signal restores count",
          [': _T _S1 SEM-WAIT _S1 SEM-SIGNAL _S1 SEM-COUNT . ; _T'],
          "3 ")

    check("multiple signal increments correctly",
          [': _T _S3 SEM-SIGNAL _S3 SEM-SIGNAL _S3 SEM-SIGNAL _S3 SEM-COUNT . ; _T'],
          "3 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── SEM-TRYWAIT ──\n")

    check("TRYWAIT on count=3 returns TRUE",
          [': _T _S1 SEM-TRYWAIT . ; _T'],
          "-1 ")

    check("TRYWAIT on count=3 decrements to 2",
          [': _T _S1 SEM-TRYWAIT DROP _S1 SEM-COUNT . ; _T'],
          "2 ")

    check("TRYWAIT on count=0 returns FALSE",
          [': _T _S3 SEM-TRYWAIT . ; _T'],
          "0 ")

    check("TRYWAIT on count=0 does not change count",
          [': _T _S3 SEM-TRYWAIT DROP _S3 SEM-COUNT . ; _T'],
          "0 ")

    check("TRYWAIT exhausts count",
          [': _T _S2 SEM-TRYWAIT . _S2 SEM-TRYWAIT . ; _T'],
          "-1 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── SEM-WAIT-TIMEOUT ──\n")

    check("timeout on count>0 returns TRUE immediately",
          [': _T _S1 1000 SEM-WAIT-TIMEOUT . ; _T'],
          "-1 ")

    check("timeout on count>0 decrements count",
          [': _T _S1 1000 SEM-WAIT-TIMEOUT DROP _S1 SEM-COUNT . ; _T'],
          "2 ")

    check("timeout on count=0 returns FALSE",
          [': _T _S3 1 SEM-WAIT-TIMEOUT . ; _T'],
          "0 ")

    check("timeout on count=0 does not change count",
          [': _T _S3 1 SEM-WAIT-TIMEOUT DROP _S3 SEM-COUNT . ; _T'],
          "0 ")

    check("timeout with 0ms on count=0 returns FALSE",
          [': _T _S3 0 SEM-WAIT-TIMEOUT . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-SEM (RAII) ──\n")

    check("WITH-SEM executes xt and restores count",
          [': _NOOP ;',
           ': _T _S1 SEM-COUNT .',      # 3
           "  ['] _NOOP _S1 WITH-SEM",
           '  _S1 SEM-COUNT .',          # still 3
           '; _T'],
          "3 3 ")

    check("WITH-SEM decrements then increments",
          [': _SHOW _S2 SEM-COUNT . ;',
           ": _T ['] _SHOW _S2 WITH-SEM _S2 SEM-COUNT . ; _T"],
          "0 1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── SEM-INFO ──\n")

    check("SEM-INFO shows count",
          [': _T _S1 SEM-INFO ; _T'],
          "count=")

    check("SEM-INFO output contains evt",
          [': _T _S1 SEM-INFO ; _T'],
          "evt:")

    # ────────────────────────────────────────────────────────────────
    print("\n── Data structure integrity ──\n")

    check("_SEM-EVT points 8 bytes past sem",
          [': _T _S1 _SEM-EVT _S1 - . ; _T'],
          "8 ")

    check("embedded event accessible as event",
          [': _T',
           '  _S1 _SEM-EVT EVT-RESET',
           '  _S1 _SEM-EVT EVT-SET? .',
           '; _T'],
          "0 ")

    check("wait-signal cycle preserves event state",
          [': _T',
           '  _S1 SEM-WAIT _S1 SEM-SIGNAL',
           '  _S1 _SEM-EVT EVT-SET? .',
           '  _S1 SEM-COUNT .',
           '; _T'],
          "0 3 ")

    # ────────────────────────────────────────────────────────────────
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
