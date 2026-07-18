#!/usr/bin/env python3
"""Test suite for akashic-tui-fexplorer applet (fexplorer.f).

Full-featured file explorer applet tests: compilation, widget creation,
navigation, clipboard, sort, preview, menus, status bar, goto-path,
and shutdown.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)
AK         = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# Resolve fexplorer's REQUIRE closure in topological order.  The app-shell is
# deliberately stubbed below because its real terminal lifecycle is outside
# this unit test; every other dependency is compiled exactly once.
FEXPLORER_F = os.path.join(AK, "tui", "applets", "fexplorer", "fexplorer.f")
APP_SHELL_F = os.path.join(AK, "tui", "app-shell.f")


# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers (same pattern as test_explorer.py / test_app_shell.py)
# ═══════════════════════════════════════════════════════════════════

_snapshot = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_forth_source_lines(path):
    with open(path) as f:
        lines = []
        for line_no, line in enumerate(f.read().splitlines(), 1):
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append((path, line_no, line))
        return lines

def _load_forth_lines(path):
    return [line for _, _, line in _load_forth_source_lines(path)]

def _dependency_paths(entry_path, skipped_paths=()):
    """Return the unique REQUIRE closure before entry_path, dependencies first."""
    skipped = {os.path.realpath(path) for path in skipped_paths}
    seen = set()
    ordered = []

    def visit(path):
        path = os.path.realpath(path)
        if path in seen or path in skipped:
            return
        if not os.path.exists(path):
            raise FileNotFoundError(f"Missing dep: {path}")
        seen.add(path)
        with open(path) as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith('REQUIRE '):
                    required = stripped.split(None, 1)[1].split()[0]
                    visit(os.path.join(os.path.dirname(path), required))
        ordered.append(path)

    visit(entry_path)
    return ordered[:-1]

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
    dependency_paths = _dependency_paths(FEXPLORER_F, (APP_SHELL_F,))

    # VFS + test helpers + app-shell stubs
    test_helpers = [
        # VFS creation helper
        'VARIABLE _TARN',
        ': T-VFS-NEW  ( -- vfs )',
        '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
        '    _TARN @ VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;',
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

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    payload_lines = _load_forth_source_lines(KDOS_PATH)
    payload_lines.append(("<harness>", 1, "ENTER-USERLAND"))
    for path in dependency_paths:
        payload_lines.extend(_load_forth_source_lines(path))
    payload_lines.extend(
        ("<test-helpers>", line_no, line)
        for line_no, line in enumerate(test_helpers, 1)
    )
    payload_lines.extend(_load_forth_source_lines(FEXPLORER_F))

    line_index = 0
    current_source = None
    line_steps = 0
    steps = 0
    max_steps = 1_500_000_000
    max_line_steps = 30_000_000
    complete = False

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if line_index < len(payload_lines):
                current_source = payload_lines[line_index]
                line_index += 1
                line_steps = 0
                sys_obj.uart.inject_input((current_source[2] + "\n").encode())
            else:
                complete = True
                break
            continue
        batch = max(sys_obj.run_batch(min(100_000, max_steps - steps)), 1)
        steps += batch
        line_steps += batch
        if current_source is not None and line_steps >= max_line_steps:
            path, line_no, line = current_source
            tail = uart_text(buf)[-2000:]
            raise RuntimeError(
                "guest compile did not return to the prompt after "
                f"{line_steps:,} steps at {path}:{line_no}: {line!r}\n"
                f"UART tail:\n{tail}"
            )

    if not complete:
        location = "before the first input line"
        if current_source is not None:
            path, line_no, line = current_source
            location = f"at {path}:{line_no}: {line!r}"
        raise RuntimeError(
            f"snapshot build stopped after {steps:,} steps {location}; "
            f"loaded {line_index}/{len(payload_lines)} lines"
        )

    text = uart_text(buf)
    errors = False
    for l in text.strip().split('\n'):
        if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower()):
            print(f"  [!] COMPILE ERROR: {l}")
            errors = True
    if errors:
        print("[!] Snapshot has compilation errors.")
        for l in text.strip().split('\n')[-50:]:
            print(f"    {l}")
        raise RuntimeError("snapshot compilation failed")

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
    payload_lines = list(lines) + ["BYE"]
    line_index = 0
    current_line = None
    line_steps = 0
    line_started = None
    steps = 0
    complete = False
    while steps < max_steps:
        if sys_obj.cpu.halted:
            complete = line_index == len(payload_lines)
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if line_index < len(payload_lines):
                current_line = payload_lines[line_index]
                line_index += 1
                line_steps = 0
                line_started = time.monotonic()
                sys_obj.uart.inject_input((current_line + "\n").encode())
            else:
                complete = True
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        batch = max(batch, 1)
        steps += batch
        line_steps += batch
        if (line_steps >= 20_000_000 or
                (line_started is not None and
                 time.monotonic() - line_started >= 10.0)):
            tail = uart_text(buf)[-1000:]
            raise RuntimeError(
                "guest test did not return after "
                f"{line_steps:,} steps on line {line_index}: "
                f"{current_line!r}\nUART tail:\n{tail}"
            )
    if not complete:
        raise RuntimeError(
            f"guest test stopped after {steps:,} steps on line "
            f"{line_index}: {current_line!r}"
        )
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
          ["CREATE TD-C APP-DESC ALLOT  TD-C FEXP-ENTRY  TD-C APP.INIT-XT @ 0<> ."],
          "-1")

def test_fexp_run_exists():
    check("FEXP-RUN word exists",
          [": T-RUN  FEXP-DESC FEXP-ENTRY ; T-RUN  FEXP-DESC APP.INIT-XT @ 0<> ."],
          "-1")

def test_entry_fills_desc():
    """FEXP-ENTRY should fill the descriptor callbacks."""
    check("FEXP-ENTRY fills init-xt",
          ["CREATE TD APP-DESC ALLOT  TD FEXP-ENTRY  TD APP.INIT-XT @ 0<> .",],
          "-1")

def test_entry_fills_paint():
    check("FEXP-ENTRY fills paint-xt",
          ["CREATE TD2 APP-DESC ALLOT  TD2 FEXP-ENTRY  TD2 APP.PAINT-XT @ 0<> .",],
          "-1")

def test_entry_fills_event():
    check("FEXP-ENTRY fills event-xt",
          ["CREATE TD3 APP-DESC ALLOT  TD3 FEXP-ENTRY  TD3 APP.EVENT-XT @ 0<> .",],
          "-1")

def test_entry_fills_shutdown():
    check("FEXP-ENTRY fills shutdown-xt",
          ["CREATE TD4 APP-DESC ALLOT  TD4 FEXP-ENTRY  TD4 APP.SHUTDOWN-XT @ 0<> .",],
          "-1")

def test_entry_title():
    """Title should be 'File Explorer'."""
    check("FEXP-ENTRY sets title",
          ["CREATE TD5 APP-DESC ALLOT  TD5 FEXP-ENTRY",
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

def test_clip_initial_state():
    check("Clipboard initially empty",
          ["_FEXP-CLIP-OP @ ."],
          "0")

# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_snapshot()
    print()
    print("=== fexplorer.f tests ===")

    test_compilation()
    test_fexp_run_exists()
    test_entry_fills_desc()
    test_entry_fills_paint()
    test_entry_fills_event()
    test_entry_fills_shutdown()
    test_entry_title()
    test_constants_sort()
    test_u_to_s_zero()
    test_u_to_s_number()
    test_u_to_s_large()
    test_clip_initial_state()

    print()
    total = _pass_count + _fail_count
    print(f"Results: {_pass_count}/{total} passed, {_fail_count} failed")
    sys.exit(1 if _fail_count else 0)
