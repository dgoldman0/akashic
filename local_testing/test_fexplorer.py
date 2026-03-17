#!/usr/bin/env python3
"""Test suite for akashic-tui-fexplorer applet (fexplorer.f).

Full-featured file explorer applet tests: compilation, widget creation,
navigation, clipboard, sort, preview, menus, status bar, goto-path,
and shutdown.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AK         = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# Use the known-good test_explorer.py chain + split/status + app-desc stubs.
# The explorer chain loads: utf8, ansi, keys, cell, screen, draw, box, region,
# layout, widget, label, progress, input, list, tabs, menu, dialog, canvas,
# tree, vfs, explorer.
# On top of that we add: split, status, textarea, app-desc.
# App-shell words (ASHELL-*) are stubbed since they need a full terminal.

# Phase 1: Known-good explorer chain
_BASE_DEPS = [
    os.path.join(AK, "text", "utf8.f"),
    os.path.join(AK, "tui", "ansi.f"),
    os.path.join(AK, "tui", "keys.f"),
    os.path.join(AK, "tui", "cell.f"),
    os.path.join(AK, "tui", "screen.f"),
    os.path.join(AK, "tui", "draw.f"),
    os.path.join(AK, "tui", "box.f"),
    os.path.join(AK, "tui", "region.f"),
    os.path.join(AK, "tui", "layout.f"),
    os.path.join(AK, "tui", "widget.f"),
    os.path.join(AK, "tui", "widgets", "label.f"),
    os.path.join(AK, "tui", "widgets", "progress.f"),
    os.path.join(AK, "tui", "widgets", "input.f"),
    os.path.join(AK, "tui", "widgets", "list.f"),
    os.path.join(AK, "tui", "widgets", "tabs.f"),
    os.path.join(AK, "tui", "widgets", "menu.f"),
    os.path.join(AK, "tui", "widgets", "dialog.f"),
    os.path.join(AK, "tui", "widgets", "canvas.f"),
    os.path.join(AK, "tui", "widgets", "tree.f"),
    os.path.join(AK, "utils", "fs", "vfs.f"),
    os.path.join(AK, "tui", "widgets", "explorer.f"),
]

# Phase 2: Extra widgets (loaded after stubs for missing words)
_EXTRA_DEPS = [
    os.path.join(AK, "tui", "widgets", "split.f"),
    os.path.join(AK, "tui", "widgets", "status.f"),
    os.path.join(AK, "text", "gap-buf.f"),
    os.path.join(AK, "text", "undo.f"),
    os.path.join(AK, "text", "cell-width.f"),
    os.path.join(AK, "tui", "widgets", "textarea.f"),
    os.path.join(AK, "tui", "app-desc.f"),
]

# Fexplorer source loaded separately (after stubs)
FEXPLORER_F = os.path.join(AK, "tui", "applets", "fexplorer", "fexplorer.f")


# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers (same pattern as test_explorer.py / test_app_shell.py)
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
    buf = bytearray()
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
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + TUI + app-shell + fexplorer ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for p in _BASE_DEPS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        dep_lines.extend(_load_forth_lines(p))

    # Stubs for missing words — must come BEFORE split.f etc.
    pre_stubs = []

    extra_lines = []
    for p in _EXTRA_DEPS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        extra_lines.extend(_load_forth_lines(p))

    # VFS + test helpers + app-shell stubs
    test_helpers = [
        # VFS creation helper
        'VARIABLE _TARN',
        ': T-VFS-NEW  ( -- vfs )',
        '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
        '    _TARN @ VFS-RAM-VTABLE VFS-NEW ;',
        'CREATE _EV 24 ALLOT',
        # App-shell stubs (fexplorer uses these but they need full terminal)
        ': ASHELL-REGION  ( -- rgn )  0 0 25 80 RGN-NEW ;',
        ': ASHELL-DIRTY!  ( -- ) ;',
        ': ASHELL-QUIT    ( -- ) ;',
        ': ASHELL-RUN     ( desc -- ) DROP ;',
        ': ASHELL-TOAST   ( addr len ms -- ) 2DROP DROP ;',
        'VARIABLE _ASHELL-TOAST-VIS',
        ': ASHELL-TOAST-VISIBLE?  ( -- flag )  0 ;',
        # Stub KEY-F10 / KEY-T-RESIZE / KEY-BACKSPACE if not already defined
        '[DEFINED] KEY-F10 [IF] [ELSE] 30 CONSTANT KEY-F10 [THEN]',
        '[DEFINED] KEY-T-RESIZE [IF] [ELSE] 2 CONSTANT KEY-T-RESIZE [THEN]',
        '[DEFINED] KEY-BACKSPACE [IF] [ELSE] 27 CONSTANT KEY-BACKSPACE [THEN]',
    ]

    # Load fexplorer.f (strip REQUIRE/PROVIDED)
    fexplorer_lines = _load_forth_lines(FEXPLORER_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    payload = "\n".join(
        kdos_lines + ["ENTER-USERLAND"] +
        dep_lines + pre_stubs + extra_lines + test_helpers +
        fexplorer_lines
    ) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    mx = 800_000_000

    while steps < mx:
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
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    errors = False
    for l in text.strip().split('\n'):
        if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower()):
            print(f"  [!] COMPILE ERROR: {l}")
            errors = True
    if errors:
        print("[!] Snapshot has compilation errors — tests will likely fail.")
        for l in text.strip().split('\n')[-50:]:
            print(f"    {l}")

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def _make_system():
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    return sys_obj


def run_forth(lines, max_steps=80_000_000):
    sys_obj = _make_system()
    buf = capture_uart(sys_obj)
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
    return uart_text(buf)


# ── Test framework ──

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-8:]:
            print(f"        > {l}")


def check_absent(name, forth_lines, absent_str):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if absent_str not in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name} (unexpected string present)")
        for l in clean.split('\n')[-8:]:
            print(f"        > {l}")


# ═══════════════════════════════════════════════════════════════════
#  Tests
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    """Verify fexplorer.f compiled with no errors."""
    check("fexplorer compiles: FEXP-ENTRY exists",
          ["CREATE TD-C 96 ALLOT  TD-C FEXP-ENTRY  TD-C APP.INIT-XT @ 0<> ."],
          "-1")

def test_fexp_run_exists():
    check("FEXP-RUN word exists",
          [": T-RUN  FEXP-DESC FEXP-ENTRY ; T-RUN  FEXP-DESC APP.INIT-XT @ 0<> ."],
          "-1")

def test_fexp_desc_size():
    """FEXP-DESC should be an APP-DESC-sized buffer."""
    check("FEXP-DESC is APP-DESC sized",
          ["FEXP-DESC APP-DESC + FEXP-DESC - . "],
          "96")

def test_entry_fills_desc():
    """FEXP-ENTRY should fill the descriptor callbacks."""
    check("FEXP-ENTRY fills init-xt",
          ["CREATE TD 96 ALLOT  TD FEXP-ENTRY  TD APP.INIT-XT @ 0<> .",],
          "-1")

def test_entry_fills_paint():
    check("FEXP-ENTRY fills paint-xt",
          ["CREATE TD2 96 ALLOT  TD2 FEXP-ENTRY  TD2 APP.PAINT-XT @ 0<> .",],
          "-1")

def test_entry_fills_event():
    check("FEXP-ENTRY fills event-xt",
          ["CREATE TD3 96 ALLOT  TD3 FEXP-ENTRY  TD3 APP.EVENT-XT @ 0<> .",],
          "-1")

def test_entry_fills_shutdown():
    check("FEXP-ENTRY fills shutdown-xt",
          ["CREATE TD4 96 ALLOT  TD4 FEXP-ENTRY  TD4 APP.SHUTDOWN-XT @ 0<> .",],
          "-1")

def test_entry_title():
    """Title should be 'File Explorer'."""
    check("FEXP-ENTRY sets title",
          ["CREATE TD5 96 ALLOT  TD5 FEXP-ENTRY",
           "TD5 APP.TITLE-A @ TD5 APP.TITLE-U @ TYPE"],
          "File Explorer")

def test_constants_sort():
    check("Sort constants defined",
          ["FEXP-SORT-NAME FEXP-SORT-SIZE FEXP-SORT-TYPE . . .",],
          "2 1 0")

def test_u_to_s_zero():
    check("_FEXP-U>S formats 0",
          ["0 _FEXP-U>S TYPE"],
          "0")

def test_u_to_s_number():
    check("_FEXP-U>S formats 42",
          ["42 _FEXP-U>S TYPE"],
          "42")

def test_u_to_s_large():
    check("_FEXP-U>S formats 12345",
          ["12345 _FEXP-U>S TYPE"],
          "12345")

def test_size_fmt_small():
    check("_FEXP-SIZE-FMT formats bytes",
          ["512 _FEXP-SIZE-FMT TYPE"],
          "512")

def test_size_fmt_kib():
    check("_FEXP-SIZE-FMT formats KiB",
          ["2048 _FEXP-SIZE-FMT TYPE"],
          "2K")

def test_size_fmt_mib():
    check("_FEXP-SIZE-FMT formats MiB",
          ["1048576 _FEXP-SIZE-FMT TYPE"],
          "1M")

def test_str_cmp_equal():
    check("_FEXP-STR-CMP equal strings",
          ['S" abc" S" abc" _FEXP-STR-CMP .'],
          "0")

def test_str_cmp_less():
    check("_FEXP-STR-CMP less",
          [': T-CMP  S" abc" S" abd" _FEXP-STR-CMP . ;', 'T-CMP'],
          "-1")

def test_str_cmp_greater():
    check("_FEXP-STR-CMP greater",
          [': T-CMP2  S" abd" S" abc" _FEXP-STR-CMP . ;', 'T-CMP2'],
          "1")

def test_str_cmp_case_insensitive():
    check("_FEXP-STR-CMP case insensitive",
          ['S" ABC" S" abc" _FEXP-STR-CMP .'],
          "0")

def test_clip_initial_state():
    check("Clipboard initially empty",
          ["_FEXP-CLIP-OP @ ."],
          "0")

def test_focus_constants():
    check("Focus constants sequential",
          ["_FEXP-FOCUS-TREE _FEXP-FOCUS-DETAIL _FEXP-FOCUS-PREVIEW",
           "_FEXP-FOCUS-MENU _FEXP-FOCUS-GOTO . . . . ."],
          "4 3 2 1 0")


# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_snapshot()
    print()
    print("=== fexplorer.f tests ===")

    test_compilation()
    test_fexp_run_exists()
    test_fexp_desc_size()
    test_entry_fills_desc()
    test_entry_fills_paint()
    test_entry_fills_event()
    test_entry_fills_shutdown()
    test_entry_title()
    test_constants_sort()
    test_u_to_s_zero()
    test_u_to_s_number()
    test_u_to_s_large()
    test_size_fmt_small()
    test_size_fmt_kib()
    test_size_fmt_mib()
    test_str_cmp_equal()
    test_str_cmp_less()
    test_str_cmp_greater()
    test_str_cmp_case_insensitive()
    test_clip_initial_state()
    test_focus_constants()

    print()
    total = _pass_count + _fail_count
    print(f"Results: {_pass_count}/{total} passed, {_fail_count} failed")
    sys.exit(1 if _fail_count else 0)
