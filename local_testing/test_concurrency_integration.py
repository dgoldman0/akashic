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
"""Comprehensive edge-case and integration tests for the concurrency library.

Covers event.f, semaphore.f, and rwlock.f together — focusing on:
  - Edge cases not hit by the individual test files
  - Exception safety (THROW inside WITH-SEM, WITH-READ, WITH-WRITE)
  - Cross-primitive interactions
  - Stress / stability under many iterations
  - Boundary conditions (large counts, zero counts, rapid transitions)
  - Multiple instances interleaved
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
RWLOCK_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "rwlock.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers (same boilerplate as other test files) ──

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + semaphore.f + rwlock.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    sem_lines  = _load_forth_lines(SEM_F)
    rwl_lines  = _load_forth_lines(RWLOCK_F)
    helpers = [
        # Events
        'EVENT _EV1',
        'EVENT _EV2',
        # Semaphores
        '3 SEMAPHORE _S1',
        '1 SEMAPHORE _S2',
        '0 SEMAPHORE _S3',
        '100 SEMAPHORE _S-BIG',
        # RW locks
        '6 RWLOCK _RW1',
        '5 RWLOCK _RW2',
        # Scratch variables
        'VARIABLE _RES',
        'VARIABLE _RES2',
        'VARIABLE _ACC',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + sem_lines + rwl_lines + helpers) + "\n"
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

# ══════════════════════════════════════════════════════════════════════
#  Tests
# ══════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    build_snapshot()

    # ────────────────────────────────────────────────────────────────
    print("\n═══ EVENT EDGE CASES ═══\n")
    # ────────────────────────────────────────────────────────────────

    check("EVT-SET on already-set event is safe",
          [': _T _EV1 EVT-SET _EV1 EVT-SET _EV1 EVT-SET? . ; _T'],
          "-1 ")

    check("EVT-RESET on already-unset event is safe",
          [': _T _EV1 EVT-RESET _EV1 EVT-RESET _EV1 EVT-SET? . ; _T'],
          "0 ")

    check("EVT-PULSE on unset event does not leave it set",
          [': _T _EV1 EVT-RESET _EV1 EVT-PULSE _EV1 EVT-SET? . ; _T'],
          "0 ")

    check("EVT-PULSE on set event clears it",
          [': _T _EV1 EVT-SET _EV1 EVT-PULSE _EV1 EVT-SET? . ; _T'],
          "0 ")

    check("EVT-WAIT on already-set event does not spin",
          [': _T _EV1 EVT-SET _EV1 EVT-WAIT 77 . ; _T'],
          "77 ")

    check("EVT-WAIT-TIMEOUT 0ms on unset returns FALSE immediately",
          [': _T _EV1 EVT-RESET _EV1 0 EVT-WAIT-TIMEOUT . ; _T'],
          "0 ")

    check("EVT-WAIT-TIMEOUT 0ms on set returns TRUE",
          [': _T _EV1 EVT-SET _EV1 0 EVT-WAIT-TIMEOUT . ; _T'],
          "-1 ")

    check("rapid set/reset 50x leaves event unset",
          [': _T 50 0 DO _EV1 EVT-SET _EV1 EVT-RESET LOOP _EV1 EVT-SET? . ; _T'],
          "0 ")

    check("rapid pulse 50x leaves event unset and waiters=0",
          [': _T 50 0 DO _EV1 EVT-PULSE LOOP _EV1 EVT-SET? . _EV1 8 + @ . ; _T'],
          "0 0 ")

    check("two events are independent: set one, other stays unset",
          [': _T _EV1 EVT-SET _EV2 EVT-SET? . _EV1 EVT-RESET ; _T'],
          "0 ")

    check("event memory layout: all 4 cells zero after reset",
          [': _T _EV1 EVT-SET _EV1 EVT-RESET',
           '  _EV1 @ . _EV1 8 + @ . _EV1 16 + @ . _EV1 24 + @ .',
           '; _T'],
          "0 0 0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n═══ SEMAPHORE EDGE CASES ═══\n")
    # ────────────────────────────────────────────────────────────────

    check("SEM-SIGNAL on count=0 raises to 1",
          [': _T _S3 SEM-SIGNAL _S3 SEM-COUNT . ; _T'],
          "1 ")

    check("large initial count (100) works",
          [': _T _S-BIG SEM-COUNT . ; _T'],
          "100 ")

    check("SEM-TRYWAIT exhausts count=1 then fails",
          [': _T _S2 SEM-TRYWAIT . _S2 SEM-TRYWAIT . _S2 SEM-SIGNAL ; _T'],
          "-1 0 ")

    check("SEM-WAIT-TIMEOUT 0ms on count=0 returns FALSE",
          [': _T _S3 0 SEM-WAIT-TIMEOUT . ; _T'],
          "0 ")

    check("SEM-WAIT-TIMEOUT on count>0 acquires (fast path)",
          [': _T _S1 1000 SEM-WAIT-TIMEOUT . _S1 SEM-SIGNAL ; _T'],
          "-1 ")

    check("20x signal then 20x trywait all succeed",
          [': _T',
           '  20 0 DO _S3 SEM-SIGNAL LOOP',
           '  0 _ACC !',
           '  20 0 DO _S3 SEM-TRYWAIT IF 1 _ACC +! THEN LOOP',
           '  _ACC @ .',
           '; _T'],
          "20 ")

    check("21st trywait after 20 signals fails",
          [': _T',
           '  20 0 DO _S3 SEM-SIGNAL LOOP',
           '  20 0 DO _S3 SEM-TRYWAIT DROP LOOP',
           '  _S3 SEM-TRYWAIT .',
           '; _T'],
          "0 ")

    check("SEM-COUNT is accurate after mixed wait/signal",
          [': _T',
           '  _S1 SEM-WAIT _S1 SEM-WAIT',      # 3->1
           '  _S1 SEM-SIGNAL',                   # 1->2
           '  _S1 SEM-COUNT .',
           '  _S1 SEM-SIGNAL',                   # restore to 3
           '; _T'],
          "2 ")

    # ── WITH-SEM exception safety ──

    check("WITH-SEM releases semaphore even on THROW",
          [': _BOOM 42 THROW ;',
           ": _WRAP ['] _BOOM _S1 WITH-SEM ;",
           ': _T',
           '  _S1 SEM-COUNT .',                  # 3
           "  ['] _WRAP CATCH DROP",              # catch the re-thrown 42
           '  _S1 SEM-COUNT .',                  # should be 3
           '; _T'],
          "3 3 ")

    check("WITH-SEM propagates exception code",
          [': _BOOM2 99 THROW ;',
           ": _WRAP2 ['] _BOOM2 _S1 WITH-SEM ;",
           ": _T ['] _WRAP2 CATCH . ; _T"],      # should print 99
          "99 ")

    check("WITH-SEM normal execution returns cleanly",
          [': _OK 55 . ;',
           ": _T ['] _OK _S1 WITH-SEM _S1 SEM-COUNT . ; _T"],
          "55 3 ")

    check("nested WITH-SEM on same semaphore decrements twice",
          [': _INNER _S1 SEM-COUNT . ;',
           ": _MID ['] _INNER _S1 WITH-SEM ;",
           ": _T ['] _MID _S1 WITH-SEM _S1 SEM-COUNT . ; _T"],
          "1 3 ")


    # ────────────────────────────────────────────────────────────────
    print("\n═══ RWLOCK EDGE CASES ═══\n")
    # ────────────────────────────────────────────────────────────────

    check("nested read-locks on same rwlock (re-entrant reads)",
          [': _T',
           '  _RW1 READ-LOCK _RW1 READ-LOCK _RW1 READ-LOCK',
           '  _RW1 RW-READERS .',
           '  _RW1 READ-UNLOCK _RW1 READ-UNLOCK _RW1 READ-UNLOCK',
           '  _RW1 RW-READERS .',
           '; _T'],
          "3 0 ")

    check("read-unlock on last reader pulses write-event (event resets after pulse)",
          [': _T',
           '  _RW1 READ-LOCK _RW1 READ-UNLOCK',
           '  _RW1 _RW-WEVT EVT-SET? .',         # pulse is transient, should be 0
           '; _T'],
          "0 ")

    check("write-unlock pulses both events (both reset after pulse)",
          [': _T',
           '  _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK',
           '  _RW1 _RW-REVT EVT-SET? .',
           '  _RW1 _RW-WEVT EVT-SET? .',
           '; _T'],
          "0 0 ")

    check("50 read-lock/unlock cycles stable",
          [': _T',
           '  50 0 DO _RW1 READ-LOCK _RW1 READ-UNLOCK LOOP',
           '  _RW1 RW-READERS . _RW1 RW-WRITER? .',
           '; _T'],
          "0 0 ")

    check("50 write-lock/unlock cycles stable",
          [': _T',
           '  50 0 DO _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK LOOP',
           '  _RW1 RW-READERS . _RW1 RW-WRITER? .',
           '; _T'],
          "0 0 ")

    check("alternating read/write 20x stable",
          [': _T',
           '  20 0 DO',
           '    _RW1 READ-LOCK _RW1 READ-UNLOCK',
           '    _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK',
           '  LOOP',
           '  _RW1 RW-READERS . _RW1 RW-WRITER? .',
           '; _T'],
          "0 0 ")

    check("two different rwlocks interleaved",
          [': _T',
           '  _RW1 READ-LOCK _RW2 WRITE-LOCK',
           '  _RW1 RW-READERS . _RW2 RW-WRITER? .',
           '  _RW2 WRITE-UNLOCK _RW1 READ-UNLOCK',
           '  _RW1 RW-READERS . _RW2 RW-WRITER? .',
           '; _T'],
          "1 -1 0 0 ")

    # ── WITH-READ / WITH-WRITE exception safety ──

    check("WITH-READ releases on THROW",
          [': _BANG 7 THROW ;',
           ": _WR1 ['] _BANG _RW1 WITH-READ ;",
           ': _T',
           "  ['] _WR1 CATCH DROP",
           '  _RW1 RW-READERS .',
           '; _T'],
          "0 ")

    check("WITH-WRITE releases on THROW",
          [': _BANG2 8 THROW ;',
           ": _WW1 ['] _BANG2 _RW1 WITH-WRITE ;",
           ': _T',
           "  ['] _WW1 CATCH DROP",
           '  _RW1 RW-WRITER? .',
           '; _T'],
          "0 ")

    check("WITH-READ normal path works and unlocks",
          [': _RD _RW1 RW-READERS . ;',
           ": _T ['] _RD _RW1 WITH-READ _RW1 RW-READERS . ; _T"],
          "1 0 ")

    check("WITH-WRITE normal path works and unlocks",
          [': _WR _RW1 RW-WRITER? . ;',
           ": _T ['] _WR _RW1 WITH-WRITE _RW1 RW-WRITER? . ; _T"],
          "-1 0 ")

    check("nested WITH-READ on same rwlock",
          [': _INNER2 _RW1 RW-READERS . ;',
           ": _MID2 ['] _INNER2 _RW1 WITH-READ ;",
           ": _T ['] _MID2 _RW1 WITH-READ _RW1 RW-READERS . ; _T"],
          "2 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n═══ CROSS-PRIMITIVE INTERACTIONS ═══\n")
    # ────────────────────────────────────────────────────────────────

    check("WITH-SEM inside WITH-READ",
          [': _INNER3 _S1 SEM-COUNT . ;',
           ": _MID3 ['] _INNER3 _S1 WITH-SEM ;",
           ": _T ['] _MID3 _RW1 WITH-READ",
           '  _RW1 RW-READERS . _S1 SEM-COUNT .',
           '; _T'],
          "2 0 3 ")

    check("WITH-READ inside WITH-SEM",
          [': _INNER4 _RW1 RW-READERS . ;',
           ": _MID4 ['] _INNER4 _RW1 WITH-READ ;",
           ": _T ['] _MID4 _S1 WITH-SEM",
           '  _S1 SEM-COUNT . _RW1 RW-READERS .',
           '; _T'],
          "1 3 0 ")

    check("event set/check inside WITH-WRITE",
          [': _EV-OP _EV1 EVT-SET _EV1 EVT-SET? . ;',
           ": _T ['] _EV-OP _RW1 WITH-WRITE",
           '  _EV1 EVT-SET? . _EV1 EVT-RESET',
           '; _T'],
          "-1 -1 ")

    check("semaphore signal inside rwlock write section",
          [': _SIG _S3 SEM-SIGNAL _S3 SEM-SIGNAL ;',
           ": _T ['] _SIG _RW1 WITH-WRITE _S3 SEM-COUNT .",
           '  _S3 SEM-WAIT _S3 SEM-WAIT',       # drain back to 0
           '; _T'],
          "2 ")

    check("all three primitives in one word",
          [': _ALL3',
           '  _EV1 EVT-SET',
           '  _S1 SEM-WAIT',
           '  _RW1 READ-LOCK',
           '  _EV1 EVT-SET? . _S1 SEM-COUNT . _RW1 RW-READERS .',
           '  _RW1 READ-UNLOCK',
           '  _S1 SEM-SIGNAL',
           '  _EV1 EVT-RESET',
           ';',
           ': _T _ALL3 ; _T'],
          "-1 2 1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n═══ STRESS / STABILITY ═══\n")
    # ────────────────────────────────────────────────────────────────

    check("100 event set/reset cycles",
          [': _T 100 0 DO _EV1 EVT-SET _EV1 EVT-RESET LOOP',
           '  _EV1 EVT-SET? . _EV1 8 + @ .',
           '; _T'],
          "0 0 ")

    check("100 event pulse cycles",
          [': _T 100 0 DO _EV1 EVT-PULSE LOOP',
           '  _EV1 EVT-SET? .',
           '; _T'],
          "0 ")

    check("100 semaphore signal then 100 wait drains to 0",
          [': _T',
           '  100 0 DO _S3 SEM-SIGNAL LOOP',
           '  _S3 SEM-COUNT .',                   # 100
           '  100 0 DO _S3 SEM-WAIT LOOP',
           '  _S3 SEM-COUNT .',                   # 0
           '; _T'],
          "100 0 ")

    check("50 WITH-SEM cycles are stable",
          [': _NOP ;',
           ": _T 50 0 DO ['] _NOP _S1 WITH-SEM LOOP _S1 SEM-COUNT . ; _T"],
          "3 ")

    check("50 WITH-READ cycles are stable",
          [': _NOP2 ;',
           ": _T 50 0 DO ['] _NOP2 _RW1 WITH-READ LOOP _RW1 RW-READERS . ; _T"],
          "0 ")

    check("50 WITH-WRITE cycles are stable",
          [': _NOP3 ;',
           ": _T 50 0 DO ['] _NOP3 _RW1 WITH-WRITE LOOP _RW1 RW-WRITER? . ; _T"],
          "0 ")

    check("mixed rw stress: 20x read, then 10x write, then 20x read",
          [': _T',
           '  20 0 DO _RW1 READ-LOCK _RW1 READ-UNLOCK LOOP',
           '  10 0 DO _RW1 WRITE-LOCK _RW1 WRITE-UNLOCK LOOP',
           '  20 0 DO _RW1 READ-LOCK _RW1 READ-UNLOCK LOOP',
           '  _RW1 RW-READERS . _RW1 RW-WRITER? .',
           '; _T'],
          "0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n═══ BOUNDARY CONDITIONS ═══\n")
    # ────────────────────────────────────────────────────────────────

    check("SEM-SIGNAL beyond initial count (3 -> 4 -> 5)",
          [': _T _S1 SEM-SIGNAL _S1 SEM-SIGNAL _S1 SEM-COUNT .',
           '  _S1 SEM-WAIT _S1 SEM-WAIT',        # restore
           '; _T'],
          "5 ")

    check("SEM-TRYWAIT on count=1 then TRYWAIT on 0 then signal back",
          [': _T',
           '  _S2 SEM-TRYWAIT .',                 # -1  (1->0)
           '  _S2 SEM-TRYWAIT .',                 # 0   (still 0)
           '  _S2 SEM-SIGNAL',                    # 0->1
           '  _S2 SEM-COUNT .',                   # 1
           '; _T'],
          "-1 0 1 ")

    check("RW-INFO after read-lock shows readers=1",
          [': _T _RW1 READ-LOCK _RW1 RW-INFO _RW1 READ-UNLOCK ; _T'],
          "readers=1")

    check("RW-INFO after write-lock shows writer=-1",
          [': _T _RW1 WRITE-LOCK _RW1 RW-INFO _RW1 WRITE-UNLOCK ; _T'],
          "writer=-1")

    check("SEM-INFO after wait shows decremented count",
          [': _T _S1 SEM-WAIT _S1 SEM-INFO _S1 SEM-SIGNAL ; _T'],
          "count=2")

    check("EVT-INFO after set shows SET",
          [': _T _EV1 EVT-SET _EV1 EVT-INFO _EV1 EVT-RESET ; _T'],
          "SET")

    check("EVT-INFO after reset shows UNSET",
          [': _T _EV1 EVT-RESET _EV1 EVT-INFO ; _T'],
          "UNSET")

    # ────────────────────────────────────────────────────────────────
    print("\n═══ EXCEPTION SAFETY — COMPLEX ═══\n")
    # ────────────────────────────────────────────────────────────────

    check("WITH-SEM THROW does not corrupt semaphore state",
          [': _THRW 1 THROW ;',
           ": _WS1 ['] _THRW _S1 WITH-SEM ;",
           ': _T',
           '  _S1 SEM-COUNT .',                   # 3
           "  ['] _WS1 CATCH DROP",
           '  _S1 SEM-COUNT .',                   # 3
           "  ['] _WS1 CATCH DROP",
           '  _S1 SEM-COUNT .',                   # 3
           '; _T'],
          "3 3 3 ")

    check("WITH-READ THROW does not corrupt reader count",
          [': _THRW2 2 THROW ;',
           ": _WR2 ['] _THRW2 _RW1 WITH-READ ;",
           ': _T',
           "  ['] _WR2 CATCH DROP",
           '  _RW1 RW-READERS .',
           "  ['] _WR2 CATCH DROP",
           '  _RW1 RW-READERS .',
           '; _T'],
          "0 0 ")

    check("WITH-WRITE THROW does not corrupt writer flag",
          [': _THRW3 3 THROW ;',
           ": _WW2 ['] _THRW3 _RW1 WITH-WRITE ;",
           ': _T',
           "  ['] _WW2 CATCH DROP",
           '  _RW1 RW-WRITER? .',
           "  ['] _WW2 CATCH DROP",
           '  _RW1 RW-WRITER? .',
           '; _T'],
          "0 0 ")

    check("exception in nested WITH-SEM inside WITH-READ unwinds both",
          [': _THRW4 4 THROW ;',
           ": _INNER5 ['] _THRW4 _S1 WITH-SEM ;",
           ": _OUTER5 ['] _INNER5 _RW1 WITH-READ ;",
           ": _T ['] _OUTER5 CATCH DROP",
           '  _RW1 RW-READERS . _S1 SEM-COUNT .',
           '; _T'],
          "0 3 ")

    check("exception in nested WITH-READ inside WITH-SEM unwinds both",
          [': _THRW5 5 THROW ;',
           ": _INNER6 ['] _THRW5 _RW1 WITH-READ ;",
           ": _OUTER6 ['] _INNER6 _S1 WITH-SEM ;",
           ": _T ['] _OUTER6 CATCH DROP",
           '  _S1 SEM-COUNT . _RW1 RW-READERS .',
           '; _T'],
          "3 0 ")

    # ────────────────────────────────────────────────────────────────
    print()
    print("=" * 50)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 50)
    sys.exit(1 if _fail else 0)
