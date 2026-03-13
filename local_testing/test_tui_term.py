#!/usr/bin/env python3
"""Test suite for akashic/utils/term.f — Terminal Geometry Utilities.

Tests the TERM- prefix wrapper words and derived geometry utilities.
Uses the UART geometry MMIO controlled via the emulator's CppUartGeomProxy.

Sections:
  A (1-3)   Compilation & basic reads
  B (1-6)   Derived geometry words
  C (1-4)   RESIZED? / change detection
  D (1-3)   Resize request flow
  E (1-3)   Integration: event.f hw-resize + app.f auto-size
"""
import os
import sys
import re
import time

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

# ═══════════════════════════════════════════════════════════════════
#  Dependency lists
# ═══════════════════════════════════════════════════════════════════

# term.f has no Forth deps — it only uses BIOS words
_TERM_DEPS = [
    os.path.join(AK, "utils", "term.f"),
]

# TUI stack deps (for event.f / app.f integration tests)
_TUI_DEPS = [
    os.path.join(AK, "text",  "utf8.f"),
    os.path.join(AK, "utils", "string.f"),
    os.path.join(AK, "utils", "toml.f"),
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
    os.path.join(AK, "utils", "term.f"),
    os.path.join(AK, "tui",   "event.f"),
    os.path.join(AK, "tui",   "app.f"),
]

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers
# ═══════════════════════════════════════════════════════════════════

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
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf
    )

def uart_text_clean(buf):
    raw = uart_text(buf)
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)

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

def feed_and_run(sys_obj, data, max_steps=400_000_000):
    if isinstance(data, str):
        data = data.encode()
    pos = 0; steps = 0
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
    return steps

# ═══════════════════════════════════════════════════════════════════
#  Snapshot — KDOS + term.f
# ═══════════════════════════════════════════════════════════════════

_term_snapshot = None

def build_term_snapshot():
    global _term_snapshot
    if _term_snapshot is not None:
        return _term_snapshot

    print("[*] Building term snapshot: BIOS + KDOS + term.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for p in _TERM_DEPS:
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
    pos = 0; steps = 0; max_steps = 800_000_000

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

    _term_snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                      bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Term snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _term_snapshot


def run_term_forth(lines, cols=80, rows=24, max_steps=80_000_000):
    """Run Forth lines from snapshot with specific terminal dimensions."""
    mem_bytes, cpu_state, ext_mem_bytes = _term_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    # Set UART geometry to known values
    sys_obj.uart_geom.cols = cols
    sys_obj.uart_geom.rows = rows
    # Clear any stale flags
    sys_obj.uart_geom.status = 0

    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode()
    pos = 0; steps = 0

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

    raw = uart_text(buf)
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)


def run_term_forth_sys(lines, cols=80, rows=24, max_steps=80_000_000):
    """Like run_term_forth but also returns the sys_obj for inspection."""
    mem_bytes, cpu_state, ext_mem_bytes = _term_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    sys_obj.uart_geom.cols = cols
    sys_obj.uart_geom.rows = rows
    sys_obj.uart_geom.status = 0

    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode()
    pos = 0; steps = 0

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

    raw = uart_text(buf)
    text = re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)
    return text, sys_obj

# ═══════════════════════════════════════════════════════════════════
#  Snapshot — KDOS + full TUI stack (for event.f / app.f tests)
# ═══════════════════════════════════════════════════════════════════

_tui_snapshot = None

def build_tui_snapshot():
    global _tui_snapshot
    if _tui_snapshot is not None:
        return _tui_snapshot

    print("[*] Building TUI snapshot: BIOS + KDOS + full TUI stack ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for p in _TUI_DEPS:
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
    pos = 0; steps = 0; max_steps = 800_000_000

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

    _tui_snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                     bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] TUI snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _tui_snapshot


def run_tui_forth(lines, cols=80, rows=24, max_steps=80_000_000):
    """Run Forth from TUI snapshot with specific terminal dimensions."""
    mem_bytes, cpu_state, ext_mem_bytes = _tui_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    sys_obj.uart_geom.cols = cols
    sys_obj.uart_geom.rows = rows
    sys_obj.uart_geom.status = 0

    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode()
    pos = 0; steps = 0

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

    raw = uart_text(buf)
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)

# ═══════════════════════════════════════════════════════════════════
#  Test runner
# ═══════════════════════════════════════════════════════════════════

g_pass = 0
g_fail = 0

def check(tag, text, expected):
    global g_pass, g_fail
    if expected in text:
        g_pass += 1
        print(f"  PASS  {tag}")
    else:
        g_fail += 1
        print(f"  FAIL  {tag}")
        # Show relevant output around the expected tag prefix
        prefix = expected.split("=")[0] if "=" in expected else expected[:10]
        for line in text.split('\n'):
            if prefix in line or "?" in line:
                print(f"        | {line}")

# ═══════════════════════════════════════════════════════════════════
#  Section A — Compilation & Basic Reads
# ═══════════════════════════════════════════════════════════════════

def test_section_A():
    print("\n── Section A: Compilation & basic reads ──")

    # A1: term.f compiles without error
    text = run_term_forth([
        '." R=TERM-OK"'
    ], cols=80, rows=24)
    check("A1 compilation", text, "R=TERM-OK")

    # A2: TERM-W reads correct column count
    text = run_term_forth([
        'TERM-W ." R=W=" .',
    ], cols=100, rows=30)
    check("A2 TERM-W", text, "R=W=100")

    # A3: TERM-H reads correct row count
    text = run_term_forth([
        'TERM-H ." R=H=" .',
    ], cols=100, rows=30)
    check("A3 TERM-H", text, "R=H=30")

# ═══════════════════════════════════════════════════════════════════
#  Section B — Derived Geometry Words
# ═══════════════════════════════════════════════════════════════════

def test_section_B():
    print("\n── Section B: Derived geometry words ──")

    # B1: TERM-SIZE returns w h
    text = run_term_forth([
        'TERM-SIZE ." R=SZ=" . ." ," .',
    ], cols=120, rows=40)
    check("B1 TERM-SIZE", text, "R=SZ=40 ,120")

    # B2: TERM-AREA returns w*h
    text = run_term_forth([
        'TERM-AREA ." R=AREA=" .',
    ], cols=80, rows=25)
    check("B2 TERM-AREA", text, "R=AREA=2000")

    # B3: TERM-FIT? — fits
    text = run_term_forth([
        '60 20 TERM-FIT? ." R=FIT=" .',
    ], cols=80, rows=24)
    check("B3 TERM-FIT? yes", text, "R=FIT=-1")

    # B4: TERM-FIT? — does not fit (too wide)
    text = run_term_forth([
        '100 20 TERM-FIT? ." R=FIT=" .',
    ], cols=80, rows=24)
    check("B4 TERM-FIT? no", text, "R=FIT=0")

    # B5: TERM-CLAMP
    text = run_term_forth([
        '200 100 TERM-CLAMP ." R=CL=" . ." ," .',
    ], cols=80, rows=24)
    check("B5 TERM-CLAMP", text, "R=CL=24 ,80")

    # B6: TERM-CENTER
    text = run_term_forth([
        '20 10 TERM-CENTER ." R=CTR=" . ." ," .',
    ], cols=80, rows=24)
    # col = (80-20)/2 = 30, row = (24-10)/2 = 7
    check("B6 TERM-CENTER", text, "R=CTR=7 ,30")

# ═══════════════════════════════════════════════════════════════════
#  Section C — RESIZED? / Change Detection
# ═══════════════════════════════════════════════════════════════════

def test_section_C():
    global g_pass, g_fail
    print("\n── Section C: RESIZED? / change detection ──")

    # C1: TERM-RESIZED? returns FALSE when no resize happened
    text = run_term_forth([
        'TERM-RESIZED? ." R=RSZ=" .',
    ], cols=80, rows=24)
    check("C1 RESIZED? no", text, "R=RSZ=0")

    # C2: TERM-RESIZED? returns TRUE when RESIZED was set
    # We need to pre-set the RESIZED flag before running Forth.
    # Use the run_term_forth_sys variant to set status after restore.
    mem_bytes, cpu_state, ext_mem_bytes = _term_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    sys_obj.uart_geom.cols = 120
    sys_obj.uart_geom.rows = 40
    # Simulate host resize: sets RESIZED flag
    sys_obj.uart_geom.host_set_size(120, 40)

    payload = 'TERM-RESIZED? ." R=RSZ=" .\nBYE\n'
    feed_and_run(sys_obj, payload)
    raw = uart_text(buf)
    text = re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)
    # BIOS may return 255 (0xFF) or -1 for TRUE — check nonzero
    m = re.search(r'R=RSZ=(-?\d+)', text)
    if m and int(m.group(1)) != 0:
        g_pass += 1
        print(f"  PASS  C2 RESIZED? yes (value={m.group(1)})")
    else:
        g_fail += 1
        print(f"  FAIL  C2 RESIZED? yes (value={m.group(1) if m else '???'})")

    # C3: RESIZED? clears after read (second call returns FALSE)
    mem_bytes, cpu_state, ext_mem_bytes = _term_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    sys_obj.uart_geom.host_set_size(100, 50)

    payload = 'TERM-RESIZED? DROP TERM-RESIZED? ." R=RSZ2=" .\nBYE\n'
    feed_and_run(sys_obj, payload)
    raw = uart_text(buf)
    text = re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)
    check("C3 RESIZED? clears", text, "R=RSZ2=0")

    # C4: TERM-CHANGED? detects size difference
    text = run_term_forth([
        '80 24 TERM-SAVE',
        '2DROP',
        '80 24 TERM-CHANGED? ." R=CHG1=" .',
        '90 30 TERM-CHANGED? ." R=CHG2=" .',
    ], cols=80, rows=24)
    # CHG1: 80==80 and 24==24 → FALSE; CHG2: 90!=80 → TRUE
    check("C4 TERM-CHANGED?", text, "R=CHG1=0")
    check("C4 TERM-CHANGED? diff", text, "R=CHG2=-1")

# ═══════════════════════════════════════════════════════════════════
#  Section D — Resize Request Flow
# ═══════════════════════════════════════════════════════════════════

def test_section_D():
    global g_pass, g_fail
    print("\n── Section D: Resize request flow ──")

    # D1: TERM-RESIZE accepted — firmware requests, host accepts
    # We need to intercept the resize request and accept it mid-run.
    # Strategy: run RESIZE-REQUEST manually, then check that
    # the firmware side wrote REQ_COLS/REQ_ROWS correctly.
    text, sys_obj = run_term_forth_sys([
        '120 40 RESIZE-REQUEST',
        '." R=REQ-OK"',
    ], cols=80, rows=24)
    check("D1 RESIZE-REQUEST", text, "R=REQ-OK")
    # Verify the firmware wrote the correct request values
    req_c = sys_obj.uart_geom.req_cols
    req_r = sys_obj.uart_geom.req_rows
    if req_c == 120 and req_r == 40:
        print(f"  PASS  D1b req_cols={req_c} req_rows={req_r}")
        g_pass += 1
    else:
        print(f"  FAIL  D1b req_cols={req_c} (expected 120) req_rows={req_r} (expected 40)")
        g_fail += 1

    # D2: RESIZE-DENIED? works after host denial
    mem_bytes, cpu_state, ext_mem_bytes = _term_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    sys_obj.uart_geom.cols = 80
    sys_obj.uart_geom.rows = 24
    # Pre-set the DENIED flag as if host denied
    sys_obj.uart_geom.host_deny_resize()

    payload = 'RESIZE-DENIED? ." R=DEN=" .\nBYE\n'
    feed_and_run(sys_obj, payload)
    raw = uart_text(buf)
    text = re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)
    # BIOS may return 255 (0xFF) or -1 for TRUE — check nonzero
    m = re.search(r'R=DEN=(-?\d+)', text)
    if m and int(m.group(1)) != 0:
        g_pass += 1
        print(f"  PASS  D2 RESIZE-DENIED? (value={m.group(1)})")
    else:
        g_fail += 1
        print(f"  FAIL  D2 RESIZE-DENIED? (value={m.group(1) if m else '???'})")

    # D3: RESIZE-DENIED? clears after read
    mem_bytes, cpu_state, ext_mem_bytes = _term_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    sys_obj.uart_geom.host_deny_resize()

    payload = 'RESIZE-DENIED? DROP RESIZE-DENIED? ." R=DEN2=" .\nBYE\n'
    feed_and_run(sys_obj, payload)
    raw = uart_text(buf)
    text = re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)
    check("D3 RESIZE-DENIED? clears", text, "R=DEN2=0")

# ═══════════════════════════════════════════════════════════════════
#  Section E — Integration: event.f / app.f
# ═══════════════════════════════════════════════════════════════════

def test_section_E():
    print("\n── Section E: TUI integration ──")

    # E1: TUI stack compiles with term.f dependency
    text = run_tui_forth([
        '." R=TUI-OK"',
    ], cols=80, rows=24)
    check("E1 TUI+term compile", text, "R=TUI-OK")

    # E2: APP-INIT with 0 0 auto-sizes from TERM-SIZE
    # We can't run the full event loop, but we can call APP-INIT
    # and check APP-SIZE returns the hardware dimensions.
    text = run_tui_forth([
        '0 0 APP-INIT',
        'APP-SIZE ." R=ASZ=" . ." ," .',
        'APP-SHUTDOWN',
    ], cols=100, rows=35)
    check("E2 APP-INIT auto-size", text, "R=ASZ=35 ,100")

    # E3: APP-INIT with explicit size still works
    text = run_tui_forth([
        '60 20 APP-INIT',
        'APP-SIZE ." R=ASZ=" . ." ," .',
        'APP-SHUTDOWN',
    ], cols=100, rows=35)
    check("E3 APP-INIT explicit", text, "R=ASZ=20 ,60")

# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_term_snapshot()
    test_section_A()
    test_section_B()
    test_section_C()
    test_section_D()

    build_tui_snapshot()
    test_section_E()

    print(f"\n{'='*50}")
    print(f"  {g_pass} passed, {g_fail} failed")
    print(f"{'='*50}")
    sys.exit(1 if g_fail else 0)
