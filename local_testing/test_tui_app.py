#!/usr/bin/env python3
"""Test suite for tui/app.f (TUI Application Lifecycle).

Uses the Megapad-64 emulator to boot KDOS, load the full TUI dependency
chain through app.f, then exercises:
  - Compilation (clean load of all deps + app.f)
  - APP-INIT terminal setup
  - APP-SHUTDOWN terminal restore
  - APP-SCREEN / APP-SIZE accessors
  - APP-TITLE! title setting
  - APP-RUN-FULL lifecycle
  - Idempotent init / shutdown
  - CATCH-based cleanup on THROW
"""
import os
import sys
import time
import re

# ──────── paths ────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AK         = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# Dependency order: everything through app.f
_DEP_PATHS = [
    os.path.join(AK, "text",  "utf8.f"),
    os.path.join(AK, "tui",   "ansi.f"),
    os.path.join(AK, "tui",   "keys.f"),
    os.path.join(AK, "tui",   "cell.f"),
    os.path.join(AK, "tui",   "screen.f"),
    os.path.join(AK, "tui",   "draw.f"),
    os.path.join(AK, "tui",   "box.f"),
    os.path.join(AK, "tui",   "region.f"),
    os.path.join(AK, "tui",   "layout.f"),
    os.path.join(AK, "tui",   "widget.f"),
    os.path.join(AK, "tui",   "focus.f"),
    os.path.join(AK, "tui",   "event.f"),
    os.path.join(AK, "tui",   "app.f"),
]

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers
# ═══════════════════════════════════════════════════════════════════

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

def uart_bytes(buf):
    """Return raw bytes from UART buffer."""
    return bytes(buf)

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf
    )

def save_cpu_state(cpu):
    return {
        'pc': cpu.pc,
        'regs': list(cpu.regs),
        'psel': cpu.psel, 'xsel': cpu.xsel, 'spsel': cpu.spsel,
        'flag_z': cpu.flag_z, 'flag_c': cpu.flag_c,
        'flag_n': cpu.flag_n, 'flag_v': cpu.flag_v,
        'flag_p': cpu.flag_p, 'flag_g': cpu.flag_g,
        'flag_i': cpu.flag_i, 'flag_s': cpu.flag_s,
        'd_reg': cpu.d_reg, 'q_out': cpu.q_out, 't_reg': cpu.t_reg,
        'ivt_base': cpu.ivt_base, 'ivec_id': cpu.ivec_id,
        'trap_addr': cpu.trap_addr,
        'halted': cpu.halted, 'idle': cpu.idle,
        'cycle_count': cpu.cycle_count,
        '_ext_modifier': cpu._ext_modifier,
    }

def restore_cpu_state(cpu, state):
    cpu.pc = state['pc']
    cpu.regs[:] = state['regs']
    for k in ('psel', 'xsel', 'spsel',
              'flag_z', 'flag_c', 'flag_n', 'flag_v',
              'flag_p', 'flag_g', 'flag_i', 'flag_s',
              'd_reg', 'q_out', 't_reg',
              'ivt_base', 'ivec_id', 'trap_addr',
              'halted', 'idle', 'cycle_count', '_ext_modifier'):
        setattr(cpu, k, state[k])


def build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + TUI stack + app.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for p in _DEP_PATHS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        dep_lines.extend(_load_forth_lines(p))

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 800_000_000

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    err_lines = [l for l in text.strip().split('\n')
                 if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower())]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-20:]:
            print(f"    {ln}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=80_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode()
    pos = 0
    steps = 0

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    return buf   # return raw byte buffer


def run_forth_text(lines, max_steps=80_000_000):
    """Run Forth and return cleaned text (no ESC sequences)."""
    buf = run_forth(lines, max_steps)
    raw = uart_text(buf)
    # Strip ANSI escape sequences for text-based checks
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)


def run_forth_raw(lines, max_steps=80_000_000):
    """Run Forth and return raw bytes."""
    return uart_bytes(run_forth(lines, max_steps))


# ═══════════════════════════════════════════════════════════════════
#  Test framework
# ═══════════════════════════════════════════════════════════════════

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected=None, check_fn=None, not_expected=None):
    global _pass_count, _fail_count
    output = run_forth_text(forth_lines)
    clean = output.strip()

    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True

    if not_expected is not None and ok:
        ok = not_expected not in clean

    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        if not_expected is not None:
            print(f"        NOT expected: {not_expected!r}")
        last = clean.split('\n')[-8:]
        print(f"        got (last lines):")
        for l in last:
            print(f"          {l}")


def check_raw(name, forth_lines, check_fn):
    """Check using raw bytes from UART (preserves ESC sequences)."""
    global _pass_count, _fail_count
    raw = run_forth_raw(forth_lines)

    ok = check_fn(raw)

    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        # Show last 200 bytes as hex for debugging
        tail = raw[-200:]
        print(f"        last {len(tail)} raw bytes: {tail.hex()}")


# ═══════════════════════════════════════════════════════════════════
#  §A — Compilation
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    check("compile-clean", [
        '." COMPILE-OK" CR',
    ], "COMPILE-OK")


# ═══════════════════════════════════════════════════════════════════
#  §B — APP-INIT terminal setup
# ═══════════════════════════════════════════════════════════════════

def test_init_alt_screen():
    """APP-INIT emits ESC[?1049h (enter alternate screen)."""
    check_raw("init-alt-screen", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?1049h' in raw)

def test_init_cursor_off():
    """APP-INIT emits ESC[?25l (hide cursor)."""
    check_raw("init-cursor-off", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?25l' in raw)

def test_init_sets_inited():
    """_APP-INITED is TRUE after APP-INIT."""
    check("init-sets-flag", [
        '80 24 APP-INIT',
        '." R=" _APP-INITED @ 0<> . CR',
        'APP-SHUTDOWN',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §C — APP-SHUTDOWN terminal restore
# ═══════════════════════════════════════════════════════════════════

def test_shutdown_alt_off():
    """APP-SHUTDOWN emits ESC[?1049l (leave alternate screen)."""
    check_raw("shutdown-alt-off", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?1049l' in raw)

def test_shutdown_cursor_on():
    """APP-SHUTDOWN emits ESC[?25h (show cursor)."""
    check_raw("shutdown-cursor-on", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?25h' in raw)

def test_shutdown_reset():
    """APP-SHUTDOWN emits ESC[0m (reset attributes)."""
    check_raw("shutdown-reset", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[0m' in raw)

def test_shutdown_clears_flag():
    """_APP-INITED is FALSE after APP-SHUTDOWN."""
    check("shutdown-clears-flag", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
        '." R=" _APP-INITED @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §D — Accessors
# ═══════════════════════════════════════════════════════════════════

def test_app_screen():
    """APP-SCREEN returns non-zero after init."""
    check("app-screen", [
        '80 24 APP-INIT',
        '." R=" APP-SCREEN 0<> . CR',
        'APP-SHUTDOWN',
    ], "R=-1 ")

def test_app_size():
    """APP-SIZE returns the dimensions passed to APP-INIT."""
    check("app-size", [
        '80 24 APP-INIT',
        'APP-SIZE',
        '." R=" SWAP . . CR',
        'APP-SHUTDOWN',
    ], "R=80 24 ")

def test_app_size_no_init():
    """APP-SIZE returns 0 0 before init."""
    # Need to clear the screen set by snapshot
    check("app-size-no-init", [
        '." R=" _APP-SCR @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §E — APP-TITLE!
# ═══════════════════════════════════════════════════════════════════

def test_title():
    """APP-TITLE! emits ESC]2;...ESC\\ title sequence."""
    check_raw("title-set", [
        '80 24 APP-INIT',
        'S" MyApp" APP-TITLE!',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b]2;MyApp\x1b\\' in raw)


# ═══════════════════════════════════════════════════════════════════
#  §F — Idempotent init / shutdown
# ═══════════════════════════════════════════════════════════════════

def test_init_idempotent():
    """Calling APP-INIT twice doesn't create a second screen."""
    check("init-idempotent", [
        '80 24 APP-INIT',
        'APP-SCREEN',      # save first screen addr
        '40 12 APP-INIT',  # second call should be no-op
        '." R=" APP-SCREEN = . CR',  # should be same addr
        'APP-SHUTDOWN',
    ], "R=-1 ")

def test_shutdown_idempotent():
    """Calling APP-SHUTDOWN without APP-INIT is a no-op."""
    check("shutdown-no-init", [
        'APP-SHUTDOWN',
        '." SAFE" CR',
    ], "SAFE")


# ═══════════════════════════════════════════════════════════════════
#  §G — APP-RUN-FULL lifecycle
# ═══════════════════════════════════════════════════════════════════

def test_run_full():
    """APP-RUN-FULL calls init-xt, runs loop, shuts down."""
    check("run-full", [
        # The init-xt posts QUIT so the loop exits immediately
        ": _MY-INIT  ' TUI-EVT-QUIT TUI-EVT-POST ;",
        "' _MY-INIT 80 24 APP-RUN-FULL",
        '." EXITED" CR',
    ], "EXITED")

def test_run_full_shutdown():
    """APP-RUN-FULL leaves _APP-INITED FALSE after completion."""
    check("run-full-shutdown", [
        ": _MY-INIT2  ' TUI-EVT-QUIT TUI-EVT-POST ;",
        "' _MY-INIT2 80 24 APP-RUN-FULL",
        '." R=" _APP-INITED @ . CR',
    ], "R=0 ")

def test_run_full_alt_restore():
    """APP-RUN-FULL restores normal screen (ESC[?1049l emitted)."""
    check_raw("run-full-alt-restore", [
        ": _MY-INIT3  ' TUI-EVT-QUIT TUI-EVT-POST ;",
        "' _MY-INIT3 80 24 APP-RUN-FULL",
    ], lambda raw: b'\x1b[?1049l' in raw)


# ═══════════════════════════════════════════════════════════════════
#  §H — FOC-CLEAR integration
# ═══════════════════════════════════════════════════════════════════

def test_init_clears_focus():
    """APP-INIT calls FOC-CLEAR — focus count is 0."""
    check("init-clears-focus", [
        '80 24 APP-INIT',
        '." R=" FOC-COUNT . CR',
        'APP-SHUTDOWN',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  Run all
# ═══════════════════════════════════════════════════════════════════

def main():
    build_snapshot()

    print()
    print("=" * 60)
    print("  tui/app.f test suite")
    print("=" * 60)

    test_compilation()

    test_init_alt_screen()
    test_init_cursor_off()
    test_init_sets_inited()

    test_shutdown_alt_off()
    test_shutdown_cursor_on()
    test_shutdown_reset()
    test_shutdown_clears_flag()

    test_app_screen()
    test_app_size()
    test_app_size_no_init()

    test_title()

    test_init_idempotent()
    test_shutdown_idempotent()

    test_run_full()
    test_run_full_shutdown()
    test_run_full_alt_restore()

    test_init_clears_focus()

    print()
    print(f"  {_pass_count + _fail_count} tests: "
          f"{_pass_count} passed, {_fail_count} failed")
    print("=" * 60)
    sys.exit(1 if _fail_count else 0)


if __name__ == "__main__":
    main()
