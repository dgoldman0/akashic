#!/usr/bin/env python3
"""Test suite for akashic-coroutine Forth library (coroutine.f).

Tests: BG-ALIVE?, WITH-BACKGROUND, BG-POLL, BG-WAIT-DONE, BG-INFO,
       and interaction with raw BIOS words PAUSE/BACKGROUND/TASK-STOP/TASK?.

The emulator runs the full BIOS with Phase 8 cooperative multitasking
(SEP R13 hardware coroutine pair).  Tests exercise single-core
cooperative context-switching between Task 0 and Task 1.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
COROUTINE_F = os.path.join(ROOT_DIR, "akashic", "concurrency", "coroutine.f")

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
    print("[*] Building snapshot: BIOS + KDOS + coroutine.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    crt_lines  = _load_forth_lines(COROUTINE_F)
    helpers = [
        'VARIABLE _RES   0 _RES !',
        'VARIABLE _CTR   0 _CTR !',
        'VARIABLE _DONE  0 _DONE !',
        ': _CLR  0 _RES !  0 _CTR !  0 _DONE ! ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + crt_lines + helpers) + "\n"
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
    # boot() wires MMIO routing + C++ accelerator.  Let it run to
    # idle so the accelerator fully initialises its internal state.
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    # Now overwrite RAM / ext-mem / CPU state from the snapshot.
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    buf.clear()  # discard boot banner
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
    print("\n── Raw BIOS: TASK? when no background task ──\n")

    check("TASK? returns 0 with no background task",
          [': _T TASK? . ; _T'],
          "0 ")

    check("BG-ALIVE? returns FALSE with no background task",
          [': _T BG-ALIVE? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Raw BIOS: PAUSE with no background task (no-op) ──\n")

    check("PAUSE is no-op when no background task",
          [': _T PAUSE 42 . ; _T'],
          "42 ")

    check("multiple PAUSEs are safe with no task",
          [': _T PAUSE PAUSE PAUSE 99 . ; _T'],
          "99 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Raw BIOS: BACKGROUND + TASK? + one-shot ──\n")

    check("BACKGROUND starts a task, TASK? returns 1",
          [': _A1 42 _RES ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A1 BACKGROUND",
           '  TASK? .',
           '; _T'],
          "1 ")

    check("one-shot background task runs on PAUSE",
          [': _A2 42 _RES ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A2 BACKGROUND",
           '  PAUSE',
           '  _RES @ .',
           '; _T'],
          "42 ")

    check("one-shot task cleans up (TASK? = 0 after completion)",
          [': _A3 42 _RES ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A3 BACKGROUND",
           '  PAUSE',
           '  TASK? .',
           '; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Raw BIOS: TASK-STOP ──\n")

    check("TASK-STOP cancels a background task",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           '  TASK? .',
           '  TASK-STOP',
           '  TASK? .',
           '; _T'],
          "1 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Raw BIOS: multi-round-trip PAUSE/TASK-YIELD ──\n")

    check("background task increments counter across PAUSEs",
          [': _BG  BEGIN 1 _CTR +! TASK-YIELD AGAIN ;',
           ': _T',
           '  _CLR',
           "  ['] _BG BACKGROUND",
           '  PAUSE PAUSE PAUSE',
           '  TASK-STOP',
           '  _CTR @ .',
           '; _T'],
          "3 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── BG-ALIVE? ──\n")

    check("BG-ALIVE? TRUE when task running",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           '  BG-ALIVE? .',
           '  TASK-STOP',
           '; _T'],
          "-1 ")

    check("BG-ALIVE? FALSE after TASK-STOP",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           '  TASK-STOP',
           '  BG-ALIVE? .',
           '; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-BACKGROUND ──\n")

    check("WITH-BACKGROUND runs body and stops bg",
          [': _BG  BEGIN 1 _CTR +! TASK-YIELD AGAIN ;',
           ': _BODY PAUSE PAUSE PAUSE ;',
           ': _T',
           '  _CLR',
           "  ['] _BG",
           "  ['] _BODY",
           '  WITH-BACKGROUND',
           '  _CTR @ . TASK? .',
           '; _T'],
          "3 0 ")

    check("WITH-BACKGROUND stops bg on THROW",
          [': _BG  BEGIN TASK-YIELD AGAIN ;',
           ': _BODY 99 THROW ;',
           ': _T',
           "  ['] _BG",
           "  ['] _BODY",
           "  ['] WITH-BACKGROUND CATCH",
           '  . TASK? .',
           '; _T'],
          "99 0 ")

    check("WITH-BACKGROUND body runs when bg is one-shot",
          [': _BG2 10 _RES ! ;',
           ': _BODY2 PAUSE 20 _RES +! ;',
           ': _T',
           '  _CLR',
           "  ['] _BG2",
           "  ['] _BODY2",
           '  WITH-BACKGROUND',
           '  _RES @ .',
           '; _T'],
          "30 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── BG-POLL ──\n")

    check("BG-POLL installs polling loop",
          [': _POLL1 1 _CTR +! ;',
           ': _T',
           '  _CLR',
           "  ['] _POLL1 BG-POLL",
           '  PAUSE PAUSE PAUSE',
           '  TASK-STOP',
           '  _CTR @ .',
           '; _T'],
          "3 ")

    check("BG-POLL task is alive",
          [': _POLL2 ;',
           ': _T',
           '  _CLR',
           "  ['] _POLL2 BG-POLL",
           '  BG-ALIVE? .',
           '  TASK-STOP',
           '; _T'],
          "-1 ")

    check("BG-POLL survives five round-trips",
          [': _POLL3 1 _CTR +! ;',
           ': _T',
           '  _CLR',
           "  ['] _POLL3 BG-POLL",
           '  PAUSE PAUSE PAUSE PAUSE PAUSE',
           '  TASK-STOP',
           '  _CTR @ . TASK? .',
           '; _T'],
          "5 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── BG-WAIT-DONE ──\n")

    check("BG-WAIT-DONE waits for one-shot task",
          [': _A4 77 _RES ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A4 BACKGROUND",
           '  BG-WAIT-DONE',
           '  _RES @ . TASK? .',
           '; _T'],
          "77 0 ")

    check("BG-WAIT-DONE returns immediately if no task",
          [': _T BG-WAIT-DONE 55 . ; _T'],
          "55 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── BG-INFO ──\n")

    check("BG-INFO shows STOPPED when no task",
          [': _T BG-INFO ; _T'],
          "STOPPED")

    check("BG-INFO shows ACTIVE when task running",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ": _T ['] _BG BACKGROUND BG-INFO TASK-STOP ; _T"],
          "ACTIVE")

    # ────────────────────────────────────────────────────────────────
    print("\n── Stack preservation across PAUSE ──\n")

    check("stack preserved across PAUSE round-trips",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           '  11 22 33',
           "  ['] _BG BACKGROUND",
           '  PAUSE PAUSE',
           '  TASK-STOP',
           '  . . .',
           '; _T'],
          "33 22 11 ")

    # ────────────────────────────────────────────────────────────────
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
