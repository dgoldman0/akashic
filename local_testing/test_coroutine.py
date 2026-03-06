#!/usr/bin/env python3
"""Test suite for akashic-coroutine Forth library (coroutine.f).

Tests: BG-ALIVE?, BG-ANY?, WITH-BACKGROUND, WITH-BG, BG-POLL,
       BG-POLL-SLOT, BG-WAIT-DONE, BG-WAIT-ALL, BG-STOP-ALL, BG-INFO,
       and interaction with raw BIOS words PAUSE/BACKGROUND/BACKGROUND2/
       BACKGROUND3/TASK-STOP/TASK?/#TASKS.

The emulator runs the full BIOS with Phase 8 cooperative multitasking
(4-task round-robin via SEP R20).  Tests exercise single-core
cooperative context-switching between Task 0 and background slots 1–3.
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
        'VARIABLE _R2    0 _R2 !',
        'VARIABLE _R3    0 _R3 !',
        ': _CLR  0 _RES !  0 _CTR !  0 _DONE !  0 _R2 !  0 _R3 ! ;',
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

    # ================================================================
    print("\n── Raw BIOS: TASK? when no background task ──\n")

    check("TASK? returns 0 for slot 1 with no bg task",
          [': _T 1 TASK? . ; _T'],
          "0 ")

    check("TASK? returns 0 for slot 2 with no bg task",
          [': _T 2 TASK? . ; _T'],
          "0 ")

    check("TASK? returns 0 for slot 3 with no bg task",
          [': _T 3 TASK? . ; _T'],
          "0 ")

    check("#TASKS returns 0 with no bg tasks",
          [': _T #TASKS . ; _T'],
          "0 ")

    check("BG-ALIVE? returns FALSE for slot 1 with no bg task",
          [': _T 1 BG-ALIVE? . ; _T'],
          "0 ")

    check("BG-ANY? returns FALSE with no bg tasks",
          [': _T BG-ANY? . ; _T'],
          "0 ")

    # ================================================================
    print("\n── Raw BIOS: PAUSE with no background task (no-op) ──\n")

    check("PAUSE is no-op when no background task",
          [': _T PAUSE 42 . ; _T'],
          "42 ")

    check("multiple PAUSEs are safe with no task",
          [': _T PAUSE PAUSE PAUSE 99 . ; _T'],
          "99 ")

    # ================================================================
    print("\n── Raw BIOS: BACKGROUND + TASK? + one-shot ──\n")

    check("BACKGROUND starts a task, 1 TASK? returns 1",
          [': _A1 42 _RES ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A1 BACKGROUND",
           '  1 TASK? .',
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
           '  1 TASK? .',
           '; _T'],
          "0 ")

    # ================================================================
    print("\n── Raw BIOS: BACKGROUND2 + BACKGROUND3 ──\n")

    check("BACKGROUND2 starts task in slot 2",
          [': _A4 99 _R2 ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A4 BACKGROUND2",
           '  2 TASK? .',
           '  PAUSE',
           '  2 TASK? .',
           '  _R2 @ .',
           '; _T'],
          "1 0 99 ")

    check("BACKGROUND3 starts task in slot 3",
          [': _A5 77 _R3 ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A5 BACKGROUND3",
           '  3 TASK? .',
           '  PAUSE',
           '  3 TASK? .',
           '  _R3 @ .',
           '; _T'],
          "1 0 77 ")

    # ================================================================
    print("\n── Raw BIOS: TASK-STOP (slot argument) ──\n")

    check("1 TASK-STOP cancels slot 1",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           '  1 TASK? .',
           '  1 TASK-STOP',
           '  1 TASK? .',
           '; _T'],
          "1 0 ")

    check("2 TASK-STOP cancels slot 2",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND2",
           '  2 TASK? .',
           '  2 TASK-STOP',
           '  2 TASK? .',
           '; _T'],
          "1 0 ")

    check("3 TASK-STOP cancels slot 3",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND3",
           '  3 TASK? .',
           '  3 TASK-STOP',
           '  3 TASK? .',
           '; _T'],
          "1 0 ")

    # ================================================================
    print("\n── Raw BIOS: multi-round-trip PAUSE/TASK-YIELD ──\n")

    check("background task increments counter across PAUSEs",
          [': _BG  BEGIN 1 _CTR +! TASK-YIELD AGAIN ;',
           ': _T',
           '  _CLR',
           "  ['] _BG BACKGROUND",
           '  PAUSE PAUSE PAUSE',
           '  1 TASK-STOP',
           '  _CTR @ .',
           '; _T'],
          "3 ")

    # ================================================================
    print("\n── Raw BIOS: #TASKS ──\n")

    check("#TASKS tracks active tasks",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           '  #TASKS .',
           "  ['] _BG BACKGROUND",
           '  #TASKS .',
           "  ['] _BG BACKGROUND2",
           '  #TASKS .',
           "  ['] _BG BACKGROUND3",
           '  #TASKS .',
           '  1 TASK-STOP  2 TASK-STOP  3 TASK-STOP',
           '  #TASKS .',
           '; _T'],
          "0 1 2 3 0 ")

    # ================================================================
    print("\n── Raw BIOS: round-robin across 3 slots ──\n")

    check("PAUSE round-robins through all 3 slots",
          ['VARIABLE c1  VARIABLE c2  VARIABLE c3',
           ': T1  BEGIN  c1 @ 1 + c1 !  TASK-YIELD  AGAIN ;',
           ': T2  BEGIN  c2 @ 1 + c2 !  TASK-YIELD  AGAIN ;',
           ': T3  BEGIN  c3 @ 1 + c3 !  TASK-YIELD  AGAIN ;',
           ': _T',
           '  0 c1 !  0 c2 !  0 c3 !',
           "  ['] T1 BACKGROUND",
           "  ['] T2 BACKGROUND2",
           "  ['] T3 BACKGROUND3",
           '  9 0 DO PAUSE LOOP',
           '  1 TASK-STOP  2 TASK-STOP  3 TASK-STOP',
           '  c1 @ . c2 @ . c3 @ .',
           '; _T'],
          "3 3 3 ")

    # ================================================================
    print("\n── BG-ALIVE? ──\n")

    check("BG-ALIVE? TRUE when slot 1 running",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           '  1 BG-ALIVE? .',
           '  1 TASK-STOP',
           '; _T'],
          "-1 ")

    check("BG-ALIVE? FALSE after 1 TASK-STOP",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           '  1 TASK-STOP',
           '  1 BG-ALIVE? .',
           '; _T'],
          "0 ")

    check("BG-ALIVE? works for slot 2",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND2",
           '  2 BG-ALIVE? .',
           '  2 TASK-STOP',
           '  2 BG-ALIVE? .',
           '; _T'],
          "-1 0 ")

    # ================================================================
    print("\n── BG-ANY? ──\n")

    check("BG-ANY? TRUE when a task is running",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND2",
           '  BG-ANY? .',
           '  2 TASK-STOP',
           '  BG-ANY? .',
           '; _T'],
          "-1 0 ")

    # ================================================================
    print("\n── WITH-BACKGROUND ──\n")

    check("WITH-BACKGROUND runs body and stops slot 1",
          [': _BG  BEGIN 1 _CTR +! TASK-YIELD AGAIN ;',
           ': _BODY PAUSE PAUSE PAUSE ;',
           ': _T',
           '  _CLR',
           "  ['] _BG",
           "  ['] _BODY",
           '  WITH-BACKGROUND',
           '  _CTR @ . 1 TASK? .',
           '; _T'],
          "3 0 ")

    check("WITH-BACKGROUND stops bg on THROW",
          [': _BG  BEGIN TASK-YIELD AGAIN ;',
           ': _BODY 99 THROW ;',
           ': _T',
           "  ['] _BG",
           "  ['] _BODY",
           "  ['] WITH-BACKGROUND CATCH",
           '  . 1 TASK? .',
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

    # ================================================================
    print("\n── WITH-BG (generic slot) ──\n")

    check("WITH-BG slot 2 runs body and stops",
          [': _BG  BEGIN 1 _CTR +! TASK-YIELD AGAIN ;',
           ': _BODY PAUSE PAUSE ;',
           ': _T',
           '  _CLR',
           "  2 ['] _BG ['] _BODY WITH-BG",
           '  _CTR @ . 2 TASK? .',
           '; _T'],
          "2 0 ")

    check("WITH-BG slot 3 stops on THROW",
          [': _BG  BEGIN TASK-YIELD AGAIN ;',
           ': _BODY 42 THROW ;',
           ': _T',
           "  3 ['] _BG ['] _BODY",
           "  ['] WITH-BG CATCH",
           '  . 3 TASK? .',
           '; _T'],
          "42 0 ")

    # ================================================================
    print("\n── BG-POLL ──\n")

    check("BG-POLL installs polling loop in slot 1",
          [': _POLL1 1 _CTR +! ;',
           ': _T',
           '  _CLR',
           "  ['] _POLL1 BG-POLL",
           '  PAUSE PAUSE PAUSE',
           '  1 TASK-STOP',
           '  _CTR @ .',
           '; _T'],
          "3 ")

    check("BG-POLL task is alive",
          [': _POLL2 ;',
           ': _T',
           '  _CLR',
           "  ['] _POLL2 BG-POLL",
           '  1 BG-ALIVE? .',
           '  1 TASK-STOP',
           '; _T'],
          "-1 ")

    check("BG-POLL survives five round-trips",
          [': _POLL3 1 _CTR +! ;',
           ': _T',
           '  _CLR',
           "  ['] _POLL3 BG-POLL",
           '  PAUSE PAUSE PAUSE PAUSE PAUSE',
           '  1 TASK-STOP',
           '  _CTR @ . 1 TASK? .',
           '; _T'],
          "5 0 ")

    # ================================================================
    print("\n── BG-POLL-SLOT ──\n")

    check("BG-POLL-SLOT installs poll in slot 2",
          [': _P2 1 _R2 +! ;',
           ': _T',
           '  _CLR',
           "  2 ['] _P2 BG-POLL-SLOT",
           '  PAUSE PAUSE PAUSE',
           '  2 TASK-STOP',
           '  _R2 @ .',
           '; _T'],
          "3 ")

    check("BG-POLL-SLOT installs poll in slot 3",
          [': _P3 1 _R3 +! ;',
           ': _T',
           '  _CLR',
           "  3 ['] _P3 BG-POLL-SLOT",
           '  PAUSE PAUSE',
           '  3 TASK-STOP',
           '  _R3 @ .',
           '; _T'],
          "2 ")

    check("BG-POLL + BG-POLL-SLOT simultaneous",
          [': _PA 1 _CTR +! ;',
           ': _PB 1 _R2 +! ;',
           ': _T',
           '  _CLR',
           "  ['] _PA BG-POLL",
           "  2 ['] _PB BG-POLL-SLOT",
           '  PAUSE PAUSE PAUSE PAUSE PAUSE PAUSE',
           '  1 TASK-STOP  2 TASK-STOP',
           '  _CTR @ . _R2 @ .',
           '; _T'],
          "3 3 ")

    # ================================================================
    print("\n── BG-WAIT-DONE ──\n")

    check("BG-WAIT-DONE waits for slot 1 one-shot",
          [': _A4 77 _RES ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A4 BACKGROUND",
           '  1 BG-WAIT-DONE',
           '  _RES @ . 1 TASK? .',
           '; _T'],
          "77 0 ")

    check("BG-WAIT-DONE returns immediately if slot empty",
          [': _T 1 BG-WAIT-DONE 55 . ; _T'],
          "55 ")

    check("BG-WAIT-DONE waits for slot 2",
          [': _A5 88 _R2 ! ;',
           ': _T',
           '  _CLR',
           "  ['] _A5 BACKGROUND2",
           '  2 BG-WAIT-DONE',
           '  _R2 @ . 2 TASK? .',
           '; _T'],
          "88 0 ")

    # ================================================================
    print("\n── BG-WAIT-ALL ──\n")

    check("BG-WAIT-ALL waits for all one-shot tasks",
          [': _W1 11 _RES ! ;',
           ': _W2 22 _R2 ! ;',
           ': _W3 33 _R3 ! ;',
           ': _T',
           '  _CLR',
           "  ['] _W1 BACKGROUND",
           "  ['] _W2 BACKGROUND2",
           "  ['] _W3 BACKGROUND3",
           '  BG-WAIT-ALL',
           '  _RES @ . _R2 @ . _R3 @ .',
           '  #TASKS .',
           '; _T'],
          "11 22 33 0 ")

    # ================================================================
    print("\n── BG-STOP-ALL ──\n")

    check("BG-STOP-ALL stops all slots",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           "  ['] _BG BACKGROUND2",
           "  ['] _BG BACKGROUND3",
           '  #TASKS .',
           '  BG-STOP-ALL',
           '  #TASKS .',
           '; _T'],
          "3 0 ")

    # ================================================================
    print("\n── BG-INFO ──\n")

    check("BG-INFO shows all slots stopped",
          [': _T BG-INFO ; _T'],
          "[coroutine 1=-- 2=-- 3=-- n=0]")

    check("BG-INFO shows active slots",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           "  ['] _BG BACKGROUND",
           "  ['] _BG BACKGROUND3",
           '  BG-INFO',
           '  BG-STOP-ALL',
           '; _T'],
          "[coroutine 1=ON 2=-- 3=ON n=2]")

    # ================================================================
    print("\n── Stack preservation across PAUSE ──\n")

    check("stack preserved across PAUSE round-trips",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           '  11 22 33',
           "  ['] _BG BACKGROUND",
           '  PAUSE PAUSE',
           '  1 TASK-STOP',
           '  . . .',
           '; _T'],
          "33 22 11 ")

    check("stack preserved with multi-slot round-robin",
          [': _BG BEGIN TASK-YIELD AGAIN ;',
           ': _T',
           '  11 22 33',
           "  ['] _BG BACKGROUND",
           "  ['] _BG BACKGROUND2",
           '  PAUSE PAUSE PAUSE PAUSE',
           '  BG-STOP-ALL',
           '  . . .',
           '; _T'],
          "33 22 11 ")

    # ================================================================
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
