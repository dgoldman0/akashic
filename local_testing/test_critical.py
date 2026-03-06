#!/usr/bin/env python3
"""Test suite for akashic-critical Forth library (critical.f).

Tests: CRITICAL-BEGIN, CRITICAL-END, CRITICAL-DEPTH,
       WITH-CRITICAL, CRITICAL-LOCK, CRITICAL-UNLOCK,
       WITH-CRITICAL-LOCK, CRITICAL-INFO, and nesting behaviour.

Single-core tests verify depth counter, preemption restore after
nesting, RAII cleanup via CATCH, and spinlock integration.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
CRIT_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "critical.f")

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
    print("[*] Building snapshot: BIOS + KDOS + critical ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    crit_lines  = _load_forth_lines(CRIT_F)
    helpers = [
        "VARIABLE _RES   0 _RES !",
        "VARIABLE _CTR   0 _CTR !",
        "VARIABLE _D0    0 _D0 !",
        "VARIABLE _D1    0 _D1 !",
        "VARIABLE _D2    0 _D2 !",
        ": _CLR  0 _RES !  0 _CTR !  0 _D0 !  0 _D1 !  0 _D2 ! ;",
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"]
                        + crit_lines
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

if __name__ == "__main__":
    build_snapshot()

    # ────────────────────────────────────────────────────────────────
    print("\n── CRITICAL-DEPTH initial state ──\n")

    check("initial depth is zero",
          [": _T CRITICAL-DEPTH . ; _T"],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CRITICAL-BEGIN / CRITICAL-END basics ──\n")

    check("single BEGIN/END cycle",
          [": _T",
           "  CRITICAL-BEGIN",
           "  CRITICAL-DEPTH .",
           "  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "1 0 ")

    check("depth reaches 1 inside",
          [": _T  CRITICAL-BEGIN  CRITICAL-DEPTH .  CRITICAL-END ; _T"],
          "1 ")

    check("depth back to 0 after END",
          [": _T  CRITICAL-BEGIN  CRITICAL-END  CRITICAL-DEPTH . ; _T"],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Nesting ──\n")

    check("nesting to depth 2",
          [": _T",
           "  CRITICAL-BEGIN",
           "  CRITICAL-DEPTH .",
           "  CRITICAL-BEGIN",
           "  CRITICAL-DEPTH .",
           "  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "1 2 1 0 ")

    check("nesting to depth 3",
          [": _T",
           "  CRITICAL-BEGIN",
           "  CRITICAL-BEGIN",
           "  CRITICAL-BEGIN",
           "  CRITICAL-DEPTH .",
           "  CRITICAL-END",
           "  CRITICAL-END",
           "  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "3 0 ")

    check("inner END does not drop below 1",
          [": _T",
           "  CRITICAL-BEGIN",
           "  CRITICAL-BEGIN",
           "  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "1 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-CRITICAL ──\n")

    check("WITH-CRITICAL executes xt",
          [": _BODY  42 _RES ! ;",
           ": _T  _CLR  ['] _BODY WITH-CRITICAL  _RES @ . ; _T"],
          "42 ")

    check("depth is 0 after WITH-CRITICAL returns",
          [": _BODY  99 _RES ! ;",
           ": _T  _CLR  ['] _BODY WITH-CRITICAL  CRITICAL-DEPTH . ; _T"],
          "0 ")

    check("depth is 1 inside WITH-CRITICAL",
          [": _BODY  CRITICAL-DEPTH _D0 ! ;",
           ": _T  _CLR  ['] _BODY WITH-CRITICAL  _D0 @ . ; _T"],
          "1 ")

    check("WITH-CRITICAL restores depth on THROW",
          [": _BOMB  -99 THROW ;",
           ": _T  _CLR",
           "  ['] _BOMB ['] WITH-CRITICAL CATCH DROP",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "0 ")

    check("WITH-CRITICAL propagates throw code",
          [": _BOMB  -99 THROW ;",
           ": _T  _CLR",
           "  ['] _BOMB ['] WITH-CRITICAL CATCH",
           "  . CRITICAL-DEPTH .",
           "; _T"],
          "-99 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CRITICAL-LOCK / CRITICAL-UNLOCK ──\n")

    check("CRITICAL-LOCK increases depth",
          [": _T",
           "  7 CRITICAL-LOCK",
           "  CRITICAL-DEPTH .",
           "  7 CRITICAL-UNLOCK",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "1 0 ")

    check("CRITICAL-LOCK then CRITICAL-UNLOCK round-trip",
          [": _T",
           "  7 CRITICAL-LOCK",
           "  42 _RES !",
           "  7 CRITICAL-UNLOCK",
           "  _RES @ .",
           "; _T"],
          "42 ")

    check("nested CRITICAL-LOCK inside CRITICAL-BEGIN",
          [": _T",
           "  CRITICAL-BEGIN",
           "  CRITICAL-DEPTH .",
           "  7 CRITICAL-LOCK",
           "  CRITICAL-DEPTH .",
           "  7 CRITICAL-UNLOCK",
           "  CRITICAL-DEPTH .",
           "  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "1 2 1 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-CRITICAL-LOCK ──\n")

    check("WITH-CRITICAL-LOCK executes xt",
          [": _BODY  77 _RES ! ;",
           ": _T  _CLR  ['] _BODY  7 WITH-CRITICAL-LOCK  _RES @ . ; _T"],
          "77 ")

    check("depth 0 after WITH-CRITICAL-LOCK",
          [": _BODY  88 _RES ! ;",
           ": _T  _CLR  ['] _BODY  7 WITH-CRITICAL-LOCK  CRITICAL-DEPTH . ; _T"],
          "0 ")

    check("depth 1 inside WITH-CRITICAL-LOCK",
          [": _BODY  CRITICAL-DEPTH _D0 ! ;",
           ": _T  _CLR  ['] _BODY  7 WITH-CRITICAL-LOCK  _D0 @ . ; _T"],
          "1 ")

    check("WITH-CRITICAL-LOCK restores on THROW",
          [": _BOMB  -55 THROW ;",
           ": _T  _CLR",
           "  ['] _BOMB  7 ['] WITH-CRITICAL-LOCK CATCH DROP",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── WITH-CRITICAL-LOCK throw propagation ──\n")

    check("WITH-CRITICAL-LOCK propagates throw code",
          [": _BOMB  -55 THROW ;",
           ": _WRAP  ['] _BOMB  7 WITH-CRITICAL-LOCK ;",
           ": _T  _CLR  ['] _WRAP CATCH  .  CRITICAL-DEPTH . ; _T"],
          "-55 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Multiple sequential sections ──\n")

    check("two consecutive critical sections",
          [": _T",
           "  CRITICAL-BEGIN  CRITICAL-DEPTH .  CRITICAL-END",
           "  CRITICAL-BEGIN  CRITICAL-DEPTH .  CRITICAL-END",
           "  CRITICAL-DEPTH .",
           "; _T"],
          "1 1 0 ")

    check("three sequential WITH-CRITICAL calls",
          [": _A  1 _CTR +! ;",
           ": _T  _CLR",
           "  ['] _A WITH-CRITICAL",
           "  ['] _A WITH-CRITICAL",
           "  ['] _A WITH-CRITICAL",
           "  _CTR @ .  CRITICAL-DEPTH .",
           "; _T"],
          "3 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CRITICAL-INFO ──\n")

    check("CRITICAL-INFO outside section",
          [": _T  CRITICAL-INFO ; _T"],
          "[critical depth=0 ]")

    check("CRITICAL-INFO inside section",
          [": _T  CRITICAL-BEGIN  CRITICAL-INFO  CRITICAL-END ; _T"],
          "[critical depth=1 ]")

    # ────────────────────────────────────────────────────────────────
    print("\n── Stack preservation ──\n")

    check("CRITICAL-BEGIN/END preserves data stack",
          [": _T  10 20 30",
           "  CRITICAL-BEGIN  CRITICAL-END",
           "  . . .",
           "; _T"],
          "30 20 10 ")

    check("WITH-CRITICAL preserves data stack",
          [": _NOP ;",
           ": _T  10 20 30  ['] _NOP WITH-CRITICAL  . . . ; _T"],
          "30 20 10 ")

    check("WITH-CRITICAL-LOCK preserves data stack",
          [": _NOP ;",
           ": _T  10 20 30  ['] _NOP  7 WITH-CRITICAL-LOCK  . . . ; _T"],
          "30 20 10 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── PREEMPT-OFF / PREEMPT-ON interaction ──\n")

    check("PREEMPT-FLAG is 0 inside critical section",
          [": _T",
           "  CRITICAL-BEGIN",
           "  PREEMPT-FLAG @ .",
           "  CRITICAL-END",
           "; _T"],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"  Total: {_pass + _fail}   Pass: {_pass}   Fail: {_fail}")
    print(f"{'='*60}")
    if _fail:
        sys.exit(1)
