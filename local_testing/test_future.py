#!/usr/bin/env python3
"""Test suite for akashic-future Forth library (future.f).

Tests: PROMISE, FULFILL, AWAIT, AWAIT-TIMEOUT, RESOLVED?,
       FUT-RESET, FUT-INFO, ASYNC (with SCHEDULE).

Note: Full blocking tests (AWAIT spinning until another core
fulfills) require multicore emulation.  These tests cover
single-core fast paths, state transitions, ASYNC+SCHEDULE
patterns, and error conditions.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
FUTURE_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "future.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + future.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    fut_lines  = _load_forth_lines(FUTURE_F)
    helpers = [
        # Pre-allocate 3 named promises for testing
        'PROMISE CONSTANT _P1',
        'PROMISE CONSTANT _P2',
        'PROMISE CONSTANT _P3',
        'VARIABLE _RES',
        'VARIABLE _V1',
        # Helper words for ASYNC tests
        ': _RET-42  42 ;',
        ': _RET-99  99 ;',
        ': _RET-0   0 ;',
        ': _RET-NEG -1 ;',
        ': _ADD-10  10 + ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + fut_lines + helpers) + "\n"
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
    print("\n── PROMISE creation ──\n")

    check("promise value starts at 0",
          [': _T _P1 @ . ; _T'],
          "0 ")

    check("promise resolved starts at 0",
          [': _T _P1 8 + @ . ; _T'],
          "0 ")

    check("promise event flag starts at 0 (unset)",
          [': _T _P1 16 + @ . ; _T'],
          "0 ")

    check("promise event wait-count starts at 0",
          [': _T _P1 24 + @ . ; _T'],
          "0 ")

    check("promise event waiter-0 starts at 0",
          [': _T _P1 32 + @ . ; _T'],
          "0 ")

    check("promise event waiter-1 starts at 0",
          [': _T _P1 40 + @ . ; _T'],
          "0 ")

    check("two promises have different addresses",
          [': _T _P1 _P2 <> . ; _T'],
          "-1 ")

    check("three promises have different addresses",
          [': _T _P1 _P2 <> _P2 _P3 <> AND . ; _T'],
          "-1 ")

    check("dynamic PROMISE returns address",
          [': _T PROMISE 0<> . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Constants ──\n")

    check("_FUT-PCELLS is 6",
          [': _T _FUT-PCELLS . ; _T'],
          "6 ")

    check("_FUT-PBYTES is 48",
          [': _T _FUT-PBYTES . ; _T'],
          "48 ")

    check("_FUT-BIND-CAP is 8",
          [': _T _FUT-BIND-CAP . ; _T'],
          "8 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── RESOLVED? ──\n")

    check("pending promise: RESOLVED? = 0",
          [': _T _P1 RESOLVED? . ; _T'],
          "0 ")

    check("after FULFILL: RESOLVED? = -1",
          [': _T 42 _P1 FULFILL _P1 RESOLVED? . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── FULFILL / AWAIT (fast path) ──\n")

    check("fulfill with 42, await returns 42",
          [': _T 42 _P1 FULFILL _P1 AWAIT . ; _T'],
          "42 ")

    check("fulfill with 0, await returns 0",
          [': _T 0 _P1 FULFILL _P1 AWAIT . ; _T'],
          "0 ")

    check("fulfill with -1, await returns -1",
          [': _T -1 _P2 FULFILL _P2 AWAIT . ; _T'],
          "-1 ")

    check("fulfill with large value",
          [': _T 9999999999 _P1 FULFILL _P1 AWAIT . ; _T'],
          "9999999999 ")

    check("fulfill with 1, await returns 1",
          [': _T 1 _P3 FULFILL _P3 AWAIT . ; _T'],
          "1 ")

    check("value field holds result after fulfill",
          [': _T 77 _P1 FULFILL _P1 @ . ; _T'],
          "77 ")

    check("resolved field is -1 after fulfill",
          [': _T 77 _P1 FULFILL _P1 8 + @ . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Event state after FULFILL ──\n")

    check("pending: embedded event is UNSET",
          [': _T _P1 _FUT-EVT EVT-SET? . ; _T'],
          "0 ")

    check("after FULFILL: embedded event is SET",
          [': _T 42 _P1 FULFILL _P1 _FUT-EVT EVT-SET? . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── AWAIT-TIMEOUT ──\n")

    check("timeout on resolved promise returns TRUE immediately",
          [': _T 42 _P1 FULFILL _P1 1000 AWAIT-TIMEOUT . . ; _T'],
          "-1 42 ")

    check("timeout on pending promise with 0ms returns FALSE",
          [': _T _P1 0 AWAIT-TIMEOUT . . ; _T'],
          "0 0 ")

    check("timeout on pending promise with 1ms returns FALSE",
          [': _T _P1 1 AWAIT-TIMEOUT . . ; _T'],
          "0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Double FULFILL (error) ──\n")

    check("double fulfill throws -1",
          [': _dbl-ful 99 _P1 FULFILL ;',
           ": _T 42 _P1 FULFILL ['] _dbl-ful CATCH . .\" |done\" ; _T"],
          "-1 |done")

    # ────────────────────────────────────────────────────────────────
    print("\n── FUT-RESET ──\n")

    check("reset clears resolved flag",
          [': _T 42 _P1 FULFILL _P1 FUT-RESET _P1 RESOLVED? . ; _T'],
          "0 ")

    check("reset clears value field",
          [': _T 42 _P1 FULFILL _P1 FUT-RESET _P1 @ . ; _T'],
          "0 ")

    check("reset clears event flag",
          [': _T 42 _P1 FULFILL _P1 FUT-RESET _P1 _FUT-EVT EVT-SET? . ; _T'],
          "0 ")

    check("can fulfill again after reset",
          [': _T',
           '  42 _P1 FULFILL _P1 FUT-RESET',
           '  99 _P1 FULFILL _P1 AWAIT .',
           '; _T'],
          "99 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── FUT-INFO ──\n")

    check("FUT-INFO on pending shows PENDING",
          [': _T _P1 FUT-INFO ; _T'],
          "PENDING")

    check("FUT-INFO on resolved shows RESOLVED",
          [': _T 42 _P1 FULFILL _P1 FUT-INFO ; _T'],
          "RESOLVED")

    check("FUT-INFO shows [future",
          [': _T _P1 FUT-INFO ; _T'],
          "[future")

    check("FUT-INFO on resolved shows value",
          [': _T 42 _P1 FULFILL _P1 FUT-INFO ; _T'],
          "val=42")

    # ────────────────────────────────────────────────────────────────
    print("\n── Field accessors ──\n")

    check("_FUT-VALUE is identity (offset 0)",
          [': _T _P1 _FUT-VALUE _P1 = . ; _T'],
          "-1 ")

    check("_FUT-RESOLVED is +8",
          [': _T _P1 _FUT-RESOLVED _P1 8 + = . ; _T'],
          "-1 ")

    check("_FUT-EVT is +16",
          [': _T _P1 _FUT-EVT _P1 16 + = . ; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── ASYNC + SCHEDULE ──\n")

    check("ASYNC returns a promise (non-zero addr)",
          [": _T ['] _RET-42 ASYNC 0<> . ; _T"],
          "-1 ")

    check("ASYNC promise starts pending",
          [": _T ['] _RET-42 ASYNC RESOLVED? . ; _T"],
          "0 ")

    check("ASYNC + SCHEDULE + AWAIT = 42",
          [": _T ['] _RET-42 ASYNC SCHEDULE AWAIT . ; _T"],
          "42 ")

    check("ASYNC + SCHEDULE + AWAIT = 99",
          [": _T ['] _RET-99 ASYNC SCHEDULE AWAIT . ; _T"],
          "99 ")

    check("ASYNC + SCHEDULE + AWAIT = 0",
          [": _T ['] _RET-0 ASYNC SCHEDULE AWAIT . ; _T"],
          "0 ")

    check("ASYNC + SCHEDULE + AWAIT = -1",
          [": _T ['] _RET-NEG ASYNC SCHEDULE AWAIT . ; _T"],
          "-1 ")

    check("two ASYNCs resolve correctly",
          [": _T ['] _RET-42 ASYNC ['] _RET-99 ASYNC SCHEDULE",
           '  SWAP AWAIT . AWAIT .',
           '; _T'],
          "42 99 ")

    check("ASYNC promise is resolved after SCHEDULE",
          [": _T ['] _RET-42 ASYNC SCHEDULE RESOLVED? . ; _T"],
          "-1 ")

    check("ASYNC promise value readable after SCHEDULE",
          [": _T ['] _RET-42 ASYNC SCHEDULE @ . ; _T"],
          "42 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Multiple promises (independent) ──\n")

    check("fulfill two different promises",
          [': _T',
           '  10 _P1 FULFILL 20 _P2 FULFILL',
           '  _P1 AWAIT . _P2 AWAIT .',
           '; _T'],
          "10 20 ")

    check("fulfill three different promises",
          [': _T',
           '  10 _P1 FULFILL 20 _P2 FULFILL 30 _P3 FULFILL',
           '  _P1 AWAIT . _P2 AWAIT . _P3 AWAIT .',
           '; _T'],
          "10 20 30 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Edge cases ──\n")

    check("fulfill then await then reset then fulfill again",
          [': _T',
           '  42 _P1 FULFILL _P1 AWAIT DROP',
           '  _P1 FUT-RESET',
           '  77 _P1 FULFILL _P1 AWAIT .',
           '; _T'],
          "77 ")

    check("multiple reset cycles are stable",
          [': _T',
           '  5 0 DO',
           '    I _P1 FULFILL _P1 AWAIT DROP _P1 FUT-RESET',
           '  LOOP',
           '  99 _P1 FULFILL _P1 AWAIT .',
           '; _T'],
          "99 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Summary ──\n")
    total = _pass + _fail
    print(f"  {_pass}/{total} passed, {_fail} failed.")
    if _fail:
        sys.exit(1)
    else:
        print("  All tests passed!")
