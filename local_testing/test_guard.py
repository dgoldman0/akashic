#!/usr/bin/env python3
"""Test suite for akashic-guard Forth library (guard.f).

Tests: GUARD, GUARD-BLOCKING, GUARD-ACQUIRE, GUARD-RELEASE,
       WITH-GUARD, GUARD-HELD?, GUARD-MINE?, GUARD-INFO,
       and re-entry detection.

Single-core tests verify guard lifecycle, RAII semantics via
WITH-GUARD, re-entry abort, and blocking guard (semaphore-backed).
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event + semaphore + guard ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    evt_lines   = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    helpers = [
        'VARIABLE _RES   0 _RES !',
        'VARIABLE _CTR   0 _CTR !',
        ': _CLR  0 _RES !  0 _CTR ! ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"]
                        + evt_lines + sem_lines + guard_lines
                        + helpers) + "\n"
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
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    buf.clear()
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
        print(f"        full output: {clean!r}")
        _fail += 1

# ── Tests ──

if __name__ == '__main__':
    build_snapshot()

    # ────────────────────────────────────────────────────────────────
    print("\n── GUARD creation and initial state ──\n")

    check("spinning guard is initially free",
          ['GUARD _G1',
           ': _T _G1 GUARD-HELD? . ; _T'],
          "0 ")

    check("GUARD-MINE? false when not held",
          ['GUARD _G2',
           ': _T _G2 GUARD-MINE? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── GUARD-ACQUIRE / GUARD-RELEASE ──\n")

    check("acquire then release spinning guard",
          ['GUARD _G3',
           ': _T',
           '  _G3 GUARD-ACQUIRE',
           '  _G3 GUARD-HELD? .',
           '  _G3 GUARD-RELEASE',
           '  _G3 GUARD-HELD? .',
           '; _T'],
          "-1 0 ")

    check("GUARD-MINE? true while held",
          ['GUARD _G4',
           ': _T',
           '  _G4 GUARD-ACQUIRE',
           '  _G4 GUARD-MINE? .',
           '  _G4 GUARD-RELEASE',
           '; _T'],
          "-1 ")

    check("GUARD-MINE? false after release",
          ['GUARD _G5',
           ': _T',
           '  _G5 GUARD-ACQUIRE',
           '  _G5 GUARD-RELEASE',
           '  _G5 GUARD-MINE? .',
           '; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-GUARD (RAII) ──\n")

    check("WITH-GUARD acquires and releases",
          ['GUARD _G6',
           ': _BODY  _G6 GUARD-HELD? . ;',
           ': _T',
           "  ['] _BODY _G6 WITH-GUARD",
           '  _G6 GUARD-HELD? .',
           '; _T'],
          "-1 0 ")

    check("WITH-GUARD releases on THROW",
          ['GUARD _G7',
           ': _BAD  99 THROW ;',
           ': _T',
           "  ['] _BAD _G7 ['] WITH-GUARD CATCH",
           '  . _G7 GUARD-HELD? .',
           '; _T'],
          "99 0 ")

    check("WITH-GUARD body result preserved",
          ['GUARD _G8',
           ': _BODY  42 _RES ! ;',
           ': _T',
           '  _CLR',
           "  ['] _BODY _G8 WITH-GUARD",
           '  _RES @ .',
           '; _T'],
          "42 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Recursive nesting ──\n")

    check("re-entry on spinning guard nests correctly",
          ['GUARD _G9',
           ': _INNER  _G9 GUARD-ACQUIRE  _G9 GUARD-MINE? .  _G9 GUARD-RELEASE ;',
           ': _T',
           '  _G9 GUARD-ACQUIRE',
           '  _INNER',
           '  _G9 GUARD-HELD? .',
           '  _G9 GUARD-RELEASE',
           '  _G9 GUARD-HELD? .',
           '; _T'],
          "-1 -1 0 ")

    check("nested GUARD-ACQUIRE inside WITH-GUARD succeeds",
          ['GUARD _G10',
           ': _INNER  _G10 GUARD-ACQUIRE  _G10 GUARD-RELEASE ;',
           ': _T',
           '  _G10 GUARD-ACQUIRE',
           '  _INNER',
           '  _G10 GUARD-HELD? .',
           '  _G10 GUARD-RELEASE',
           '  _G10 GUARD-HELD? .',
           '; _T'],
          "-1 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── GUARD-BLOCKING creation and state ──\n")

    check("blocking guard is initially free",
          ['GUARD-BLOCKING _BG1',
           ': _T _BG1 GUARD-HELD? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── GUARD-BLOCKING acquire/release ──\n")

    check("acquire and release blocking guard",
          ['GUARD-BLOCKING _BG2',
           ': _T',
           '  _BG2 GUARD-ACQUIRE',
           '  _BG2 GUARD-HELD? .',
           '  _BG2 GUARD-RELEASE',
           '  _BG2 GUARD-HELD? .',
           '; _T'],
          "-1 0 ")

    check("GUARD-MINE? works with blocking guard",
          ['GUARD-BLOCKING _BG3',
           ': _T',
           '  _BG3 GUARD-ACQUIRE',
           '  _BG3 GUARD-MINE? .',
           '  _BG3 GUARD-RELEASE',
           '  _BG3 GUARD-MINE? .',
           '; _T'],
          "-1 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-GUARD blocking ──\n")

    check("WITH-GUARD works with blocking guard",
          ['GUARD-BLOCKING _BG4',
           ': _BODY  _BG4 GUARD-HELD? . ;',
           ': _T',
           "  ['] _BODY _BG4 WITH-GUARD",
           '  _BG4 GUARD-HELD? .',
           '; _T'],
          "-1 0 ")

    check("WITH-GUARD blocking releases on THROW",
          ['GUARD-BLOCKING _BG5',
           ': _BAD  55 THROW ;',
           ': _T',
           "  ['] _BAD _BG5 ['] WITH-GUARD CATCH",
           '  . _BG5 GUARD-HELD? .',
           '; _T'],
          "55 0 ")

    check("re-entry on blocking guard nests correctly",
          ['GUARD-BLOCKING _BG6',
           ': _INNER  _BG6 GUARD-ACQUIRE  _BG6 GUARD-MINE? .  _BG6 GUARD-RELEASE ;',
           ': _T',
           '  _BG6 GUARD-ACQUIRE',
           '  _INNER',
           '  _BG6 GUARD-HELD? .',
           '  _BG6 GUARD-RELEASE',
           '  _BG6 GUARD-HELD? .',
           '; _T'],
          "-1 -1 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Multiple acquires / releases ──\n")

    check("spinning guard can be acquired again after release",
          ['GUARD _G11',
           ': _T',
           '  _G11 GUARD-ACQUIRE  _G11 GUARD-RELEASE',
           '  _G11 GUARD-ACQUIRE  _G11 GUARD-RELEASE',
           '  _G11 GUARD-ACQUIRE  _G11 GUARD-RELEASE',
           '  42 .',
           '; _T'],
          "42 ")

    check("blocking guard can be acquired again after release",
          ['GUARD-BLOCKING _BG7',
           ': _T',
           '  _BG7 GUARD-ACQUIRE  _BG7 GUARD-RELEASE',
           '  _BG7 GUARD-ACQUIRE  _BG7 GUARD-RELEASE',
           '  _BG7 GUARD-ACQUIRE  _BG7 GUARD-RELEASE',
           '  42 .',
           '; _T'],
          "42 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Guard protecting shared state ──\n")

    check("guard protects variable mutation",
          ['GUARD _G12',
           ': _INC  1 _CTR +! ;',
           ': _T',
           '  _CLR',
           "  ['] _INC _G12 WITH-GUARD",
           "  ['] _INC _G12 WITH-GUARD",
           "  ['] _INC _G12 WITH-GUARD",
           '  _CTR @ .',
           '; _T'],
          "3 ")

    check("blocking guard protects variable mutation",
          ['GUARD-BLOCKING _BG8',
           ': _INC  1 _CTR +! ;',
           ': _T',
           '  _CLR',
           "  ['] _INC _BG8 WITH-GUARD",
           "  ['] _INC _BG8 WITH-GUARD",
           "  ['] _INC _BG8 WITH-GUARD",
           '  _CTR @ .',
           '; _T'],
          "3 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── GUARD-INFO ──\n")

    check("GUARD-INFO shows FREE for spinning guard",
          ['GUARD _G13',
           ': _T _G13 GUARD-INFO ; _T'],
          "FREE")

    check("GUARD-INFO shows HELD for acquired guard",
          ['GUARD _G14',
           ': _T',
           '  _G14 GUARD-ACQUIRE',
           '  _G14 GUARD-INFO',
           '  _G14 GUARD-RELEASE',
           '; _T'],
          "HELD")

    check("GUARD-INFO shows spin for spinning guard",
          ['GUARD _G15',
           ': _T _G15 GUARD-INFO ; _T'],
          "spin")

    check("GUARD-INFO shows blocking for blocking guard",
          ['GUARD-BLOCKING _BG9',
           ': _T _BG9 GUARD-INFO ; _T'],
          "blocking")

    # ────────────────────────────────────────────────────────────────
    print("\n── Stack preservation ──\n")

    check("WITH-GUARD preserves stack across call",
          ['GUARD _G16',
           ': _BODY ;',
           ': _T',
           '  11 22 33',
           "  ['] _BODY _G16 WITH-GUARD",
           '  . . .',
           '; _T'],
          "33 22 11 ")

    # ────────────────────────────────────────────────────────────────
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
