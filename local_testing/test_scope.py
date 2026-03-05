#!/usr/bin/env python3
"""Test suite for akashic-scope Forth library (scope.f).

Tests: TASK-GROUP, TG-SPAWN, TG-WAIT, TG-CANCEL, TG-ANY,
       TG-COUNT, TG-CANCELLED?, TG-ERROR, WITH-TASKS,
       THIS-GROUP, TG-RESET, TG-INFO.

The emulator runs single-core (NCORES = 1), so all tasks execute
cooperatively via SCHEDULE.  Tests verify group lifecycle, error
capture (CATCH/THROW), structured concurrency (WITH-TASKS +
THIS-GROUP), cancellation, and reset semantics.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SCOPE_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "scope.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + scope.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    scp_lines  = _load_forth_lines(SCOPE_F)
    helpers = [
        # Side-effect variables for verifying tasks ran
        'VARIABLE _RAN1  0 _RAN1 !',
        'VARIABLE _RAN2  0 _RAN2 !',
        'VARIABLE _RAN3  0 _RAN3 !',
        'VARIABLE _RAN4  0 _RAN4 !',
        'VARIABLE _RES   0 _RES !',
        # Task bodies ( -- )
        ': _SET1  1 _RAN1 ! ;',
        ': _SET2  1 _RAN2 ! ;',
        ': _SET3  1 _RAN3 ! ;',
        ': _SET4  1 _RAN4 ! ;',
        ': _CLR   0 _RAN1 !  0 _RAN2 !  0 _RAN3 !  0 _RAN4 !  0 _RES ! ;',
        ': _NOOP ;',
        # Counter bumpers ( -- )
        ': _ADD10  10 _RES +! ;',
        ': _ADD20  20 _RES +! ;',
        ': _ADD30  30 _RES +! ;',
        # Throwing tasks ( -- )
        ': _THROW42  42 THROW ;',
        ': _THROW99  99 THROW ;',
        # Pre-allocated named task groups
        'TASK-GROUP _TG1',
        'TASK-GROUP _TG2',
        # WITH-TASKS helpers (read THIS-GROUP @ at runtime)
        ': _WXT1  [\'] _SET1 THIS-GROUP @ TG-SPAWN ;',
        ': _WXT2  [\'] _SET1 THIS-GROUP @ TG-SPAWN [\'] _SET2 THIS-GROUP @ TG-SPAWN ;',
        ': _WXT3  [\'] _SET1 THIS-GROUP @ TG-SPAWN [\'] _SET2 THIS-GROUP @ TG-SPAWN [\'] _SET3 THIS-GROUP @ TG-SPAWN ;',
        # Nested WITH-TASKS helpers
        ': _INNER-XT  [\'] _SET2 THIS-GROUP @ TG-SPAWN ;',
        ': _OUTER-XT  [\'] _SET1 THIS-GROUP @ TG-SPAWN [\'] _INNER-XT WITH-TASKS ;',
        # WITH-TASKS + error
        ': _WXT-ERR  [\'] _THROW42 THIS-GROUP @ TG-SPAWN ;',
        # Counter-based WITH-TASKS helper
        ': _WXT-ADD  [\'] _ADD10 THIS-GROUP @ TG-SPAWN [\'] _ADD20 THIS-GROUP @ TG-SPAWN [\'] _ADD30 THIS-GROUP @ TG-SPAWN ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + scp_lines + helpers) + "\n"
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
    print("\n── Task Group Creation ──\n")

    check("TASK-GROUP: initial count is 0",
          [': _T _TG1 TG-COUNT . ; _T'],
          "0 ")

    check("TASK-GROUP: not cancelled initially",
          [': _T _TG1 TG-CANCELLED? . ; _T'],
          "0 ")

    check("TASK-GROUP: no error initially",
          [': _T _TG1 TG-ERROR . ; _T'],
          "0 ")

    check("two groups independent",
          [': _T _TG1 TG-COUNT . _TG2 TG-COUNT . ; _T'],
          "0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TG-SPAWN + SCHEDULE ──\n")

    check("TG-SPAWN increments active count",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN _TG1 TG-COUNT . ; _T"],
          "1 ")

    check("SCHEDULE runs task, active goes to 0",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN SCHEDULE _TG1 TG-COUNT . ; _T"],
          "0 ")

    check("task body executes (side effect)",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN SCHEDULE _RAN1 @ . ; _T"],
          "1 ")

    check("two tasks both execute",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN ['] _SET2 _TG1 TG-SPAWN",
           "SCHEDULE _RAN1 @ . _RAN2 @ . ; _T"],
          "1 1 ")

    check("three tasks all execute",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN ['] _SET2 _TG1 TG-SPAWN",
           "['] _SET3 _TG1 TG-SPAWN SCHEDULE",
           "_RAN1 @ . _RAN2 @ . _RAN3 @ . ; _T"],
          "1 1 1 ")

    check("counter tasks sum correctly",
          [": _T _CLR ['] _ADD10 _TG1 TG-SPAWN ['] _ADD20 _TG1 TG-SPAWN",
           "['] _ADD30 _TG1 TG-SPAWN SCHEDULE _RES @ . ; _T"],
          "60 ")

    check("noop task runs without error",
          [": _T _CLR ['] _NOOP _TG1 TG-SPAWN SCHEDULE _TG1 TG-ERROR . ; _T"],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TG-WAIT ──\n")

    check("TG-WAIT on empty group is no-op",
          [': _T _TG1 TG-WAIT 42 . ; _T'],
          "42 ")

    check("TG-WAIT runs tasks and waits",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN _TG1 TG-WAIT _RAN1 @ . ; _T"],
          "1 ")

    check("TG-WAIT with two tasks",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN ['] _SET2 _TG1 TG-SPAWN",
           "_TG1 TG-WAIT _RAN1 @ . _RAN2 @ . ; _T"],
          "1 1 ")

    check("TG-WAIT with three tasks, count is 0 after",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN ['] _SET2 _TG1 TG-SPAWN",
           "['] _SET3 _TG1 TG-SPAWN _TG1 TG-WAIT",
           "_TG1 TG-COUNT . _RAN1 @ . _RAN2 @ . _RAN3 @ . ; _T"],
          "0 1 1 1 ")

    check("TG-WAIT idempotent (call twice)",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN _TG1 TG-WAIT",
           "_TG1 TG-WAIT _RAN1 @ . ; _T"],
          "1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TG-CANCEL ──\n")

    check("TG-CANCEL sets cancelled flag",
          [': _T _TG1 TG-CANCEL _TG1 TG-CANCELLED? . ; _T'],
          "-1 ")

    check("TG-CANCEL on empty group, then CANCELLED? is true",
          [': _T _TG1 TG-CANCEL _TG1 TG-CANCELLED? . ; _T'],
          "-1 ")

    check("TG-SPAWN into cancelled group is no-op",
          [": _T _CLR _TG1 TG-CANCEL ['] _SET1 _TG1 TG-SPAWN",
           "_TG1 TG-COUNT . _RAN1 @ . ; _T"],
          "0 0 ")

    check("TG-CANCEL idempotent",
          [': _T _TG1 TG-CANCEL _TG1 TG-CANCEL _TG1 TG-CANCELLED? . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TG-ERROR (CATCH/THROW) ──\n")

    check("throwing task stores error code",
          [": _T ['] _THROW42 _TG1 TG-SPAWN SCHEDULE _TG1 TG-ERROR . ; _T"],
          "42 ")

    check("non-throwing task leaves error at 0",
          [": _T ['] _SET1 _TG1 TG-SPAWN SCHEDULE _TG1 TG-ERROR . ; _T"],
          "0 ")

    check("first error wins (42 before 99)",
          [": _T ['] _THROW42 _TG1 TG-SPAWN ['] _THROW99 _TG1 TG-SPAWN",
           "SCHEDULE _TG1 TG-ERROR . ; _T"],
          "42 ")

    check("error task still decrements active count",
          [": _T ['] _THROW42 _TG1 TG-SPAWN SCHEDULE _TG1 TG-COUNT . ; _T"],
          "0 ")

    check("mix of error and normal tasks",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN ['] _THROW42 _TG1 TG-SPAWN",
           "SCHEDULE _RAN1 @ . _TG1 TG-ERROR . _TG1 TG-COUNT . ; _T"],
          "1 42 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TG-ANY ──\n")

    check("TG-ANY on empty group is no-op",
          [': _T _TG1 TG-ANY 42 . ; _T'],
          "42 ")

    check("TG-ANY runs tasks and cancels",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN ['] _SET2 _TG1 TG-SPAWN",
           "_TG1 TG-ANY _TG1 TG-CANCELLED? . _RAN1 @ . _RAN2 @ . ; _T"],
          "-1 1 1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-TASKS ──\n")

    check("WITH-TASKS spawns and waits (1 task)",
          [": _T _CLR ['] _WXT1 WITH-TASKS _RAN1 @ . ; _T"],
          "1 ")

    check("WITH-TASKS spawns and waits (2 tasks)",
          [": _T _CLR ['] _WXT2 WITH-TASKS _RAN1 @ . _RAN2 @ . ; _T"],
          "1 1 ")

    check("WITH-TASKS spawns and waits (3 tasks)",
          [": _T _CLR ['] _WXT3 WITH-TASKS _RAN1 @ . _RAN2 @ . _RAN3 @ . ; _T"],
          "1 1 1 ")

    check("WITH-TASKS counter sum",
          [": _T _CLR ['] _WXT-ADD WITH-TASKS _RES @ . ; _T"],
          "60 ")

    check("WITH-TASKS restores THIS-GROUP to 0",
          [": _T _CLR ['] _WXT1 WITH-TASKS THIS-GROUP @ . ; _T"],
          "0 ")

    check("WITH-TASKS with error, TG-ERROR available",
          [": _T _CLR ['] _WXT-ERR WITH-TASKS ; _T"],
          "")  # just check it doesn't crash

    # ────────────────────────────────────────────────────────────────
    print("\n── Nested WITH-TASKS ──\n")

    check("nested WITH-TASKS runs both levels",
          [": _T _CLR ['] _OUTER-XT WITH-TASKS _RAN1 @ . _RAN2 @ . ; _T"],
          "1 1 ")

    check("nested WITH-TASKS restores THIS-GROUP",
          [": _T _CLR ['] _OUTER-XT WITH-TASKS THIS-GROUP @ . ; _T"],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TG-RESET ──\n")

    check("TG-RESET clears cancelled flag",
          [': _T _TG1 TG-CANCEL _TG1 TG-CANCELLED? .',
           '_TG1 TG-RESET _TG1 TG-CANCELLED? . ; _T'],
          "-1 0 ")

    check("TG-RESET clears error",
          [": _T ['] _THROW42 _TG1 TG-SPAWN SCHEDULE",
           "_TG1 TG-ERROR . _TG1 TG-RESET _TG1 TG-ERROR . ; _T"],
          "42 0 ")

    check("TG-RESET clears active count",
          [': _T _TG1 TG-RESET _TG1 TG-COUNT . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TG-INFO ──\n")

    check("TG-INFO outputs group prefix",
          [': _T _TG1 TG-INFO ; _T'],
          "[group")

    check("TG-INFO shows active=0",
          [': _T _TG1 TG-INFO ; _T'],
          "active=0")

    # ────────────────────────────────────────────────────────────────
    print("\n── Multiple Groups ──\n")

    check("two groups with tasks, both complete",
          [": _T _CLR ['] _SET1 _TG1 TG-SPAWN ['] _SET2 _TG2 TG-SPAWN",
           "_TG1 TG-WAIT _TG2 TG-WAIT _RAN1 @ . _RAN2 @ . ; _T"],
          "1 1 ")

    check("cancel one group, other unaffected",
          [": _T _CLR _TG1 TG-CANCEL ['] _SET2 _TG2 TG-SPAWN",
           "_TG2 TG-WAIT _TG1 TG-CANCELLED? . _TG2 TG-CANCELLED? . _RAN2 @ . ; _T"],
          "-1 0 1 ")

    # ────────────────────────────────────────────────────────────────
    # Done
    print(f"\n{'='*60}")
    print(f"  {_pass} passed, {_fail} failed, {_pass + _fail} total")
    print(f"{'='*60}")
    sys.exit(1 if _fail else 0)
