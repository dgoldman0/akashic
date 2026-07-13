#!/usr/bin/env python3
"""Single- and multicore tests for akashic-guard (guard.f).

Tests: GUARD, GUARD-BLOCKING, GUARD-ACQUIRE, GUARD-RELEASE,
       WITH-GUARD, GUARD-HELD?, GUARD-MINE?, GUARD-INFO,
       recursive ownership, non-owner rejection, and bounded acquisition.

The harness imports the supported sibling MegaPad checkout rather than a
private emulator copy.  Four-core tests exercise real CORE-RUN contention;
they are specifically intended to catch nonatomic check-then-set guards and
the old ambiguity where every BIOS worker appeared to be task zero.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
MEGAPAD_DIR = os.path.abspath(os.environ.get(
    "MEGAPAD_ROOT", os.path.join(ROOT_DIR, "..", "megapad")))
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

sys.path.insert(0, MEGAPAD_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(MEGAPAD_DIR, "bios.asm")
KDOS_PATH = os.path.join(MEGAPAD_DIR, "kdos.f")

# ── Emulator helpers ──

_snapshots = {}

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

def build_snapshot(num_cores=1):
    if num_cores in _snapshots:
        return _snapshots[num_cores]
    print(f"[*] Building {num_cores}-core snapshot: "
          "BIOS + KDOS + event + semaphore + guard ...")
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
    sys_obj = MegapadSystem(ram_size=1024*1024,
                            ext_mem_size=16 * (1 << 20),
                            num_cores=num_cores)
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
    _snapshots[num_cores] = (
        bios_code,
        bytes(sys_obj.cpu.mem),
        [save_cpu_state(cpu) for cpu in sys_obj.cores],
        bytes(sys_obj._ext_mem),
    )
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshots[num_cores]

def run_forth(lines, max_steps=50_000_000, num_cores=1):
    bios_code, mem_bytes, core_states, ext_mem_bytes = build_snapshot(num_cores)
    sys_obj = MegapadSystem(ram_size=1024*1024,
                            ext_mem_size=16 * (1 << 20),
                            num_cores=num_cores)
    buf = capture_uart(sys_obj)
    # Boot once so peripheral-side BIOS state (especially the UART ring) is
    # initialized, then restore the compiled Forth snapshot over the CPUs and
    # shared memories.
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    for cpu, state in zip(sys_obj.cores, core_states):
        restore_cpu_state(cpu, state)
    # Restore the BIOS UART TX ring pointer saved in core 0's R19.
    r19 = sys_obj.cpu.regs[19]
    if r19 and r19 < len(mem_bytes):
        sys_obj.uart._tx_ring_base = r19
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

def check(name, forth_lines, expected, *, num_cores=1,
          max_steps=50_000_000):
    global _pass, _fail
    output = run_forth(forth_lines, max_steps=max_steps,
                       num_cores=num_cores)
    clean = output.strip()
    errors = ("Branch offset overflow", "Stack underflow", "not found")
    if expected in clean and not any(marker in clean for marker in errors):
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

    check("try-acquire succeeds and preserves recursive depth",
          ['GUARD _G5T',
           ': _T',
           '  _G5T GUARD-TRY-ACQUIRE .',
           '  _G5T _GRD-DEPTH @ .',
           '  _G5T GUARD-TRY-ACQUIRE .',
           '  _G5T _GRD-DEPTH @ .',
           '  _G5T GUARD-RELEASE _G5T GUARD-RELEASE',
           '  _G5T GUARD-HELD? .',
           '; _T'],
          "-1 1 -1 2 0 ")

    check("zero-timeout acquire still tries a free guard",
          ['GUARD _G5Z',
           ': _T',
           '  _G5Z 0 GUARD-ACQUIRE-TIMEOUT .',
           '  _G5Z GUARD-RELEASE',
           '; _T'],
          "-1 ")

    check("release of a free guard is rejected",
          ['GUARD _G5R',
           ': _BAD-RELEASE _G5R GUARD-RELEASE ;',
           ": _T ['] _BAD-RELEASE CATCH . ; _T"],
          "-257 ")

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

    check("guard metadata lock is not held across body event calls",
          ['GUARD _G8E',
           'EVENT _G8-EVENT',
           ': _BODY _G8-EVENT EVT-SET ;',
           ': _T',
           "  ['] _BODY _G8E WITH-GUARD",
           '  _G8-EVENT EVT-SET? .',
           '; _T'],
          "-1 ")

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

    check("BIOS coroutine slots are distinct guard owners",
          ['GUARD _CT-G',
           'VARIABLE _CT-OWNER 0 _CT-OWNER !',
           'VARIABLE _CT-TRY1 0 _CT-TRY1 !',
           'VARIABLE _CT-TRY2 0 _CT-TRY2 !',
           ': _CT-BG',
           '  _CT-G GUARD-ACQUIRE',
           '  _CT-G _GRD-OWNER-TASK @ _CT-OWNER !',
           '  TASK-YIELD',
           '  _CT-G GUARD-RELEASE',
           ';',
           "' _CT-BG BACKGROUND",
           'PAUSE',
           '_CT-G GUARD-TRY-ACQUIRE _CT-TRY1 !',
           'PAUSE',
           '_CT-G GUARD-TRY-ACQUIRE _CT-TRY2 !',
           '_CT-G GUARD-RELEASE',
           '_CT-TRY1 @ . _CT-TRY2 @ . _CT-OWNER @ .'],
          "0 -1 -1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Four-core ownership and contention ──\n")

    check("four cores serialize one shared critical section",
          ['GUARD _MC-G',
           'VARIABLE _MC-START  0 _MC-START !',
           'VARIABLE _MC-COUNT  0 _MC-COUNT !',
           'VARIABLE _MC-IN     0 _MC-IN !',
           'VARIABLE _MC-MAX    0 _MC-MAX !',
           ': _MC-CRITICAL',
           '  _MC-G GUARD-ACQUIRE',
           '  1 _MC-IN +!',
           '  _MC-IN @ _MC-MAX @ > IF _MC-IN @ _MC-MAX ! THEN',
           '  1 _MC-COUNT +!',
           '  20 0 DO I DROP LOOP',
           '  -1 _MC-IN +!',
           '  _MC-G GUARD-RELEASE',
           ';',
           ': _MC-WORKER',
           '  BEGIN _MC-START @ 0= WHILE YIELD? REPEAT',
           '  100 0 DO _MC-CRITICAL LOOP',
           ';',
           "' _MC-WORKER 1 CORE-RUN",
           "' _MC-WORKER 2 CORE-RUN",
           "' _MC-WORKER 3 CORE-RUN",
           '-1 _MC-START !',
           '_MC-WORKER',
           'BARRIER',
           '_MC-COUNT @ . _MC-MAX @ .'],
          "400 1 ", num_cores=4, max_steps=150_000_000)

    check("worker checkpoints during LOCK and guard contention preserve core0 task",
          ['GUARD _PC-G',
           'CREATE _PC-OWNER 48 ALLOT',
           'T.RUNNING _PC-OWNER !',
           'CREATE _PC-EXPLICIT 4 CELLS ALLOT',
           'CREATE _PC-HW-READY 4 CELLS ALLOT',
           'CREATE _PC-HW-DONE 4 CELLS ALLOT',
           'CREATE _PC-G-READY 4 CELLS ALLOT',
           'CREATE _PC-G-DONE 4 CELLS ALLOT',
           '_PC-EXPLICIT 4 CELLS 0 FILL',
           '_PC-HW-READY 4 CELLS 0 FILL',
           '_PC-HW-DONE 4 CELLS 0 FILL',
           '_PC-G-READY 4 CELLS 0 FILL',
           '_PC-G-DONE 4 CELLS 0 FILL',
           'VARIABLE _PC-AFTER-HW 0 _PC-AFTER-HW !',
           'VARIABLE _PC-AFTER-G 0 _PC-AFTER-G !',
           'VARIABLE _PC-CURRENT-SAME 0 _PC-CURRENT-SAME !',
           ': _PC-MARK  ( table -- ) COREID CELLS + -1 SWAP ! ;',
           ': _PC-ALL?  ( table -- flag )',
           '  DUP CELL+ @',
           '  OVER 2 CELLS + @ AND',
           '  SWAP 3 CELLS + @ AND',
           ';',
           ': _PC-WAIT-ALL  ( table -- )',
           '  BEGIN DUP _PC-ALL? 0= WHILE REPEAT DROP',
           ';',
           ': _PC-WORKER-FLAGS-CLEAR?  ( -- flag )',
           '  1 PREEMPT-FLAG@ 0=',
           '  2 PREEMPT-FLAG@ 0= AND',
           '  3 PREEMPT-FLAG@ 0= AND',
           ';',
           ': _PC-WAIT-WORKER-FLAGS  ( -- )',
           '  BEGIN _PC-WORKER-FLAGS-CLEAR? 0= WHILE REPEAT',
           ';',
           ': _PC-WORKER',
           '  COREID PREEMPT-SET YIELD?',
           '  _PC-EXPLICIT _PC-MARK',
           '  COREID PREEMPT-SET',
           '  _PC-HW-READY _PC-MARK',
           '  5 LOCK 5 UNLOCK',
           '  _PC-HW-DONE _PC-MARK',
           '  COREID PREEMPT-SET',
           '  _PC-G-READY _PC-MARK',
           '  _PC-G GUARD-ACQUIRE _PC-G GUARD-RELEASE',
           '  _PC-G-DONE _PC-MARK',
           ';',
           '_PC-OWNER CURRENT-TASK !',
           '1 PREEMPT-ENABLED !',
           '5 LOCK _PC-G GUARD-ACQUIRE',
           "' _PC-WORKER 1 CORE-RUN",
           "' _PC-WORKER 2 CORE-RUN",
           "' _PC-WORKER 3 CORE-RUN",
           '_PC-HW-READY _PC-WAIT-ALL',
           '_PC-WAIT-WORKER-FLAGS',
           '_PC-OWNER T.STATUS _PC-AFTER-HW !',
           '5 UNLOCK',
           '_PC-G-READY _PC-WAIT-ALL',
           '_PC-WAIT-WORKER-FLAGS',
           '_PC-OWNER T.STATUS _PC-AFTER-G !',
           '_PC-G GUARD-RELEASE',
           'BARRIER',
           'CURRENT-TASK @ _PC-OWNER = _PC-CURRENT-SAME !',
           '_PC-AFTER-HW @ . _PC-AFTER-G @ . _PC-OWNER T.STATUS . '
           '_PC-CURRENT-SAME @ . _PC-EXPLICIT _PC-ALL? . '
           '_PC-HW-DONE _PC-ALL? . _PC-G-DONE _PC-ALL? . '
           '_PC-WORKER-FLAGS-CLEAR? .',
           '0 CURRENT-TASK ! PREEMPT-OFF-ALL'],
          "2 2 2 -1 -1 -1 -1 -1 ",
          num_cores=4, max_steps=150_000_000)

    check("concurrent worker WITH-GUARD throws use per-core handler chains",
          ['GUARD _HC-G1 GUARD _HC-G2 GUARD _HC-G3',
           'CREATE _HC-READY 4 CELLS ALLOT',
           'CREATE _HC-RESULT 4 CELLS ALLOT',
           '_HC-READY 4 CELLS 0 FILL',
           '_HC-RESULT 4 CELLS 0 FILL',
           ': _HC-MARK  ( table -- ) COREID CELLS + -1 SWAP ! ;',
           ': _HC-ALL?  ( table -- flag )',
           '  DUP CELL+ @',
           '  OVER 2 CELLS + @ AND',
           '  SWAP 3 CELLS + @ AND',
           ';',
           ': _HC-GUARD  ( -- guard )',
           '  COREID 1 = IF _HC-G1 EXIT THEN',
           '  COREID 2 = IF _HC-G2 EXIT THEN',
           '  _HC-G3',
           ';',
           ': _HC-BODY',
           '  _HC-READY _HC-MARK',
           '  BEGIN _HC-READY _HC-ALL? 0= WHILE YIELD? REPEAT',
           '  COREID 10 + THROW',
           ';',
           ": _HC-WRAPPED ['] _HC-BODY _HC-GUARD WITH-GUARD ;",
           ': _HC-WORKER',
           "  ['] _HC-WRAPPED CATCH",
           '  COREID CELLS _HC-RESULT + !',
           ';',
           "' _HC-WORKER 1 CORE-RUN",
           "' _HC-WORKER 2 CORE-RUN",
           "' _HC-WORKER 3 CORE-RUN",
           'BARRIER',
           '_HC-RESULT CELL+ @ . _HC-RESULT 2 CELLS + @ . '
           '_HC-RESULT 3 CELLS + @ . '
           '_HC-G1 GUARD-HELD? . _HC-G2 GUARD-HELD? . '
           '_HC-G3 GUARD-HELD? .'],
          "11 12 13 0 0 0 ", num_cores=4,
          max_steps=100_000_000)

    check("zero-task BIOS workers remain distinct owners",
          ['GUARD _ZT-G',
           'VARIABLE _ZT-READY 0 _ZT-READY !',
           'VARIABLE _ZT-RELEASE 0 _ZT-RELEASE !',
           'VARIABLE _ZT-GOT 0 _ZT-GOT !',
           'VARIABLE _ZT-CORE 0 _ZT-CORE !',
           'VARIABLE _ZT-TASK -1 _ZT-TASK !',
           'VARIABLE _ZT-HELD 0 _ZT-HELD !',
           ': _ZT-HOLDER',
           '  _ZT-G GUARD-ACQUIRE',
           '  _ZT-G _GRD-OWNER-CORE @ _ZT-CORE !',
           '  _ZT-G _GRD-OWNER-TASK @ _ZT-TASK !',
           '  -1 _ZT-READY !',
           '  BEGIN _ZT-RELEASE @ 0= WHILE YIELD? REPEAT',
           '  _ZT-G GUARD-RELEASE',
           ';',
           ': _ZT-CONTENDER',
           '  BEGIN _ZT-READY @ 0= WHILE YIELD? REPEAT',
           '  _ZT-G GUARD-TRY-ACQUIRE DUP _ZT-GOT !',
           '  IF _ZT-G GUARD-RELEASE THEN',
           ';',
           "' _ZT-HOLDER 1 CORE-RUN",
           "' _ZT-CONTENDER 2 CORE-RUN",
           '2 CORE-WAIT',
           '_ZT-G GUARD-HELD? _ZT-HELD !',
           '-1 _ZT-RELEASE ! 1 CORE-WAIT',
           '_ZT-GOT @ . _ZT-CORE @ . _ZT-TASK @ . '
           '_ZT-HELD @ . _ZT-G GUARD-HELD? .'],
          "0 1 0 -1 0 ", num_cores=4)

    check("a different core cannot release the holder's guard",
          ['GUARD _NR-G',
           'VARIABLE _NR-READY 0 _NR-READY !',
           'VARIABLE _NR-RELEASE 0 _NR-RELEASE !',
           'VARIABLE _NR-ERROR 0 _NR-ERROR !',
           'VARIABLE _NR-HELD 0 _NR-HELD !',
           ': _NR-HOLDER',
           '  _NR-G GUARD-ACQUIRE -1 _NR-READY !',
           '  BEGIN _NR-RELEASE @ 0= WHILE YIELD? REPEAT',
           '  _NR-G GUARD-RELEASE',
           ';',
           ': _NR-BAD-RELEASE _NR-G GUARD-RELEASE ;',
           ': _NR-INTRUDER',
           '  BEGIN _NR-READY @ 0= WHILE YIELD? REPEAT',
           "  ['] _NR-BAD-RELEASE CATCH _NR-ERROR !",
           ';',
           "' _NR-HOLDER 1 CORE-RUN",
           "' _NR-INTRUDER 2 CORE-RUN",
           '2 CORE-WAIT',
           '_NR-G GUARD-HELD? _NR-HELD !',
           '-1 _NR-RELEASE ! 1 CORE-WAIT',
           '_NR-ERROR @ . _NR-HELD @ . _NR-G GUARD-HELD? .'],
          "-257 -1 0 ", num_cores=4)

    check("try and timeout fail while another core owns the guard",
          ['GUARD _TO-G',
           'VARIABLE _TO-READY 0 _TO-READY !',
           'VARIABLE _TO-RELEASE 0 _TO-RELEASE !',
           'VARIABLE _TO-TRY 0 _TO-TRY !',
           'VARIABLE _TO-TIME 0 _TO-TIME !',
           'VARIABLE _TO-AFTER 0 _TO-AFTER !',
           ': _TO-HOLDER',
           '  _TO-G GUARD-ACQUIRE -1 _TO-READY !',
           '  BEGIN _TO-RELEASE @ 0= WHILE YIELD? REPEAT',
           '  _TO-G GUARD-RELEASE',
           ';',
           ': _TO-WAIT-READY',
           '  BEGIN _TO-READY @ 0= WHILE YIELD? REPEAT',
           ';',
           "' _TO-HOLDER 1 CORE-RUN",
           '_TO-WAIT-READY',
           '_TO-G GUARD-TRY-ACQUIRE _TO-TRY !',
           '_TO-G 1 GUARD-ACQUIRE-TIMEOUT _TO-TIME !',
           '-1 _TO-RELEASE ! 1 CORE-WAIT',
           '_TO-G 0 GUARD-ACQUIRE-TIMEOUT _TO-AFTER !',
           '_TO-G GUARD-RELEASE',
           '_TO-TRY @ . _TO-TIME @ . _TO-AFTER @ .'],
          "0 0 -1 ", num_cores=4)

    check("blocking wait releases metadata lock before sleeping",
          ['GUARD-BLOCKING _BL-G',
           'VARIABLE _BL-READY 0 _BL-READY !',
           'VARIABLE _BL-WAITING 0 _BL-WAITING !',
           'VARIABLE _BL-RELEASE 0 _BL-RELEASE !',
           'VARIABLE _BL-GOT 0 _BL-GOT !',
           ': _BL-HOLDER',
           '  _BL-G GUARD-ACQUIRE -1 _BL-READY !',
           '  BEGIN _BL-RELEASE @ 0= WHILE YIELD? REPEAT',
           '  _BL-G GUARD-RELEASE',
           ';',
           ': _BL-WAITER',
           '  BEGIN _BL-READY @ 0= WHILE YIELD? REPEAT',
           '  -1 _BL-WAITING !',
           '  _BL-G GUARD-ACQUIRE -1 _BL-GOT !',
           '  _BL-G GUARD-RELEASE',
           ';',
           ': _BL-WAIT-FOR-WAITER',
           '  BEGIN _BL-WAITING @ 0= WHILE YIELD? REPEAT',
           ';',
           "' _BL-HOLDER 1 CORE-RUN",
           "' _BL-WAITER 2 CORE-RUN",
           '_BL-WAIT-FOR-WAITER',
           '-1 _BL-RELEASE !',
           '1 CORE-WAIT 2 CORE-WAIT',
           '_BL-GOT @ . _BL-G GUARD-HELD? .'],
          "-1 0 ", num_cores=4, max_steps=100_000_000)

    # ────────────────────────────────────────────────────────────────
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
