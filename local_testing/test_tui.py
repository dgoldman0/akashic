#!/usr/bin/env python3
"""Test suite for akashic-tui Layer 0 + Layer 1 + Layer 2 + Layer 3.

Tests ANSI escape sequence emission (ansi.f) and terminal input
decoding (keys.f) against the Megapad-64 emulator.

ansi.f tests:  Capture raw UART output and verify exact byte sequences.
keys.f tests:  Define busy-loop Forth words that call KEY-POLL, inject
               raw escape sequences from Python between batches, and
               verify decoded event fields.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
ANSI_F     = os.path.join(ROOT_DIR, "akashic", "tui", "ansi.f")
KEYS_F     = os.path.join(ROOT_DIR, "akashic", "tui", "keys.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
CELL_F     = os.path.join(ROOT_DIR, "akashic", "tui", "cell.f")
SCREEN_F   = os.path.join(ROOT_DIR, "akashic", "tui", "screen.f")
DRAW_F     = os.path.join(ROOT_DIR, "akashic", "tui", "draw.f")
BOX_F      = os.path.join(ROOT_DIR, "akashic", "tui", "box.f")
REGION_F   = os.path.join(ROOT_DIR, "akashic", "tui", "region.f")
LAYOUT_F   = os.path.join(ROOT_DIR, "akashic", "tui", "layout.f")
WIDGET_F   = os.path.join(ROOT_DIR, "akashic", "tui", "widget.f")
LABEL_F    = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "label.f")
PROGRESS_F = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "progress.f")
INPUT_F    = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "input.f")
LIST_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "list.f")
TABS_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "tabs.f")
MENU_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "menu.f")
DIALOG_F   = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "dialog.f")
CANVAS_F   = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "canvas.f")
TREE_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "tree.f")

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
    """Load Forth file, stripping blanks, comments, REQUIRE/PROVIDED."""
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
    """Build BIOS + KDOS + utf8.f + ansi.f + keys.f snapshot."""
    global _snapshot
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + utf8 + ansi + keys + cell + screen + draw + box + region + layout + widget + label + progress + input + list + tabs + menu + dialog + canvas + tree ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    utf8_lines = _load_forth_lines(UTF8_F)
    ansi_lines = _load_forth_lines(ANSI_F)
    keys_lines = _load_forth_lines(KEYS_F)
    cell_lines = _load_forth_lines(CELL_F)
    screen_lines = _load_forth_lines(SCREEN_F)
    draw_lines = _load_forth_lines(DRAW_F)
    box_lines  = _load_forth_lines(BOX_F)
    region_lines = _load_forth_lines(REGION_F)
    layout_lines = _load_forth_lines(LAYOUT_F)
    widget_lines = _load_forth_lines(WIDGET_F)
    label_lines  = _load_forth_lines(LABEL_F)
    progress_lines = _load_forth_lines(PROGRESS_F)
    input_lines    = _load_forth_lines(INPUT_F)
    list_lines     = _load_forth_lines(LIST_F)
    tabs_lines     = _load_forth_lines(TABS_F)
    menu_lines     = _load_forth_lines(MENU_F)
    dialog_lines   = _load_forth_lines(DIALOG_F)
    canvas_lines   = _load_forth_lines(CANVAS_F)
    tree_lines     = _load_forth_lines(TREE_F)

    # Event buffer for key tests (3 cells = 24 bytes)
    helpers = ['CREATE _EV 24 ALLOT']

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    payload = "\n".join(
        kdos_lines + ["ENTER-USERLAND"] +
        utf8_lines + ansi_lines + keys_lines +
        cell_lines + screen_lines +
        draw_lines + box_lines +
        region_lines + layout_lines +
        widget_lines + label_lines + progress_lines +
        input_lines + list_lines + tabs_lines + menu_lines +
        dialog_lines + canvas_lines + tree_lines + helpers
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
        print("[!] Snapshot has compilation errors — tests may fail.")

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def _make_system():
    """Create a fresh system restored from snapshot."""
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
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


def run_forth_raw(lines, max_steps=50_000_000):
    """Run Forth lines and return raw UART bytes."""
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
    return bytes(buf)


def run_forth(lines, max_steps=50_000_000):
    """Run Forth lines and return printable text."""
    raw = run_forth_raw(lines, max_steps)
    return uart_text(raw)


def run_keys_test(define_line, inject_bytes, max_steps=80_000_000):
    """Run a keys.f test using the busy-loop injection pattern.

    define_line:   A single Forth line that defines a word containing
                   BEGIN _EV KEY-POLL UNTIL ... then immediately calls it.
                   Example: ': _KT BEGIN _EV KEY-POLL UNTIL _EV @ . ; _KT'

    inject_bytes:  Raw bytes to inject once the busy-loop is spinning.

    Returns printable text from UART output.
    """
    sys_obj = _make_system()
    buf = capture_uart(sys_obj)

    # Feed the definition + invocation as a single line
    sys_obj.uart.inject_input((define_line + "\n").encode())

    # Phase 1: Let the line compile and the word start executing.
    # The word busy-loops on KEY-POLL (KEY? returns false each time),
    # so the CPU stays busy (not idle) burning cycles.
    steps = 0
    for _ in range(500):
        if sys_obj.cpu.halted:
            break
        batch = sys_obj.run_batch(10_000)
        steps += max(batch, 1)
        # Once the UART RX is drained and CPU is still running,
        # the busy-loop has started
        if not sys_obj.uart.has_rx_data and not sys_obj.cpu.idle:
            break

    # Phase 2: Inject the raw escape sequence bytes
    sys_obj.uart.inject_input(inject_bytes)

    # Phase 3: Let the busy-loop pick up bytes, decode, print results
    for _ in range(4000):
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
        if steps >= max_steps:
            break

    # Phase 4: Feed BYE to halt
    sys_obj.uart.inject_input(b"BYE\n")
    for _ in range(2000):
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
        if steps >= max_steps:
            break

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
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")


def check_raw_suffix(name, forth_lines, expected_suffix):
    """Check that raw UART output contains expected byte sequence."""
    global _pass_count, _fail_count
    raw = run_forth_raw(forth_lines)
    if expected_suffix in raw:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected bytes: {list(expected_suffix)}")
        tail = raw[-120:]
        print(f"        got tail ({len(tail)}B): {list(tail)}")


def check_keys(name, inject_bytes, expected, fields="type-code-mods"):
    """Run a keys.f busy-loop test.

    fields controls what gets printed:
      "type-code-mods" → _EV @ .  _EV KEY-CODE@ .  _EV KEY-MODS@ .
      "type-code"      → _EV @ .  _EV KEY-CODE@ .
    """
    global _pass_count, _fail_count
    if fields == "type-code-mods":
        body = '_EV @ .  _EV KEY-CODE@ .  _EV KEY-MODS@ .'
    elif fields == "type-code":
        body = '_EV @ .  _EV KEY-CODE@ .'
    else:
        body = fields  # custom body
    line = f': _KT  BEGIN _EV KEY-POLL UNTIL  {body} ; _KT'
    text = run_keys_test(line, inject_bytes)
    clean = text.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")


def run_forth_with_keys(setup_lines, modal_line, inject_bytes, max_steps=80_000_000):
    """Send setup Forth lines, start a KEY-POLL modal word, inject keys.

    setup_lines:   Forth lines compiled/executed before the modal word.
    modal_line:    A single Forth line that enters a KEY-POLL modal loop.
    inject_bytes:  Raw bytes to inject once the busy-loop is spinning.

    Returns printable text from UART output.
    """
    sys_obj = _make_system()
    buf = capture_uart(sys_obj)

    # Phase 1: Send setup lines and wait for compilation
    if setup_lines:
        payload = "\n".join(setup_lines) + "\n"
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
    else:
        steps = 0

    # Phase 2: Send modal line (starts KEY-POLL busy-loop)
    sys_obj.uart.inject_input((modal_line + "\n").encode())

    # Phase 3: Wait for the busy-loop to start spinning
    for _ in range(500):
        if sys_obj.cpu.halted:
            break
        batch = sys_obj.run_batch(10_000)
        steps += max(batch, 1)
        if not sys_obj.uart.has_rx_data and not sys_obj.cpu.idle:
            break

    # Phase 4: Inject key bytes
    sys_obj.uart.inject_input(inject_bytes)

    # Phase 5: Let modal loop process keys and complete
    for _ in range(8000):
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
        if steps >= max_steps:
            break

    # Phase 6: Feed BYE to halt
    sys_obj.uart.inject_input(b"BYE\n")
    for _ in range(2000):
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
        if steps >= max_steps:
            break

    return uart_text(buf)


def check_modal(name, setup_lines, modal_line, inject_bytes, expected):
    """Check a modal dialog test with key injection."""
    global _pass_count, _fail_count
    output = run_forth_with_keys(setup_lines, modal_line, inject_bytes)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")


def check_keys_custom(name, inject_bytes, custom_body, expected):
    """Run a keys.f test with a custom word body after KEY-POLL."""
    return check_keys(name, inject_bytes, expected, fields=custom_body)


# =====================================================================
#  ANSI.F TESTS — Escape Sequence Emission
# =====================================================================

ESC = b'\x1b'

def test_ansi_cursor():
    print("\n── ANSI cursor movement ──")
    check_raw_suffix("AT 1,1", ['1 1 ANSI-AT'], ESC + b'[1;1H')
    check_raw_suffix("AT 24,80", ['24 80 ANSI-AT'], ESC + b'[24;80H')
    check_raw_suffix("UP 3", ['3 ANSI-UP'], ESC + b'[3A')
    check_raw_suffix("DOWN 5", ['5 ANSI-DOWN'], ESC + b'[5B')
    check_raw_suffix("RIGHT 10", ['10 ANSI-RIGHT'], ESC + b'[10C')
    check_raw_suffix("LEFT 2", ['2 ANSI-LEFT'], ESC + b'[2D')
    check_raw_suffix("HOME", ['ANSI-HOME'], ESC + b'[H')
    check_raw_suffix("COL 40", ['40 ANSI-COL'], ESC + b'[40G')
    check_raw_suffix("SAVE", ['ANSI-SAVE'], ESC + b'[s')
    check_raw_suffix("RESTORE", ['ANSI-RESTORE'], ESC + b'[u')
    check("UP 0 noop", ['42 EMIT 0 ANSI-UP 43 EMIT'], "*+")


def test_ansi_clear():
    print("\n── ANSI screen clearing ──")
    check_raw_suffix("CLEAR", ['ANSI-CLEAR'], ESC + b'[2J')
    check_raw_suffix("CLEAR-EOL", ['ANSI-CLEAR-EOL'], ESC + b'[K')
    check_raw_suffix("CLEAR-BOL", ['ANSI-CLEAR-BOL'], ESC + b'[1K')
    check_raw_suffix("CLEAR-LINE", ['ANSI-CLEAR-LINE'], ESC + b'[2K')
    check_raw_suffix("CLEAR-EOS", ['ANSI-CLEAR-EOS'], ESC + b'[J')
    check_raw_suffix("CLEAR-BOS", ['ANSI-CLEAR-BOS'], ESC + b'[1J')


def test_ansi_scroll():
    print("\n── ANSI scrolling ──")
    check_raw_suffix("SCROLL-UP 3", ['3 ANSI-SCROLL-UP'], ESC + b'[3S')
    check_raw_suffix("SCROLL-DN 2", ['2 ANSI-SCROLL-DN'], ESC + b'[2T')
    check_raw_suffix("SCROLL-RGN 2,23", ['2 23 ANSI-SCROLL-RGN'], ESC + b'[2;23r')
    check_raw_suffix("SCROLL-RESET", ['ANSI-SCROLL-RESET'], ESC + b'[r')


def test_ansi_attributes():
    print("\n── ANSI text attributes ──")
    check_raw_suffix("RESET", ['ANSI-RESET'], ESC + b'[0m')
    check_raw_suffix("BOLD", ['ANSI-BOLD'], ESC + b'[1m')
    check_raw_suffix("DIM", ['ANSI-DIM'], ESC + b'[2m')
    check_raw_suffix("ITALIC", ['ANSI-ITALIC'], ESC + b'[3m')
    check_raw_suffix("UNDERLINE", ['ANSI-UNDERLINE'], ESC + b'[4m')
    check_raw_suffix("BLINK", ['ANSI-BLINK'], ESC + b'[5m')
    check_raw_suffix("REVERSE", ['ANSI-REVERSE'], ESC + b'[7m')
    check_raw_suffix("HIDDEN", ['ANSI-HIDDEN'], ESC + b'[8m')
    check_raw_suffix("STRIKE", ['ANSI-STRIKE'], ESC + b'[9m')
    check_raw_suffix("NORMAL", ['ANSI-NORMAL'], ESC + b'[22m')
    check_raw_suffix("NO-ITALIC", ['ANSI-NO-ITALIC'], ESC + b'[23m')
    check_raw_suffix("NO-UNDERLINE", ['ANSI-NO-UNDERLINE'], ESC + b'[24m')
    check_raw_suffix("NO-BLINK", ['ANSI-NO-BLINK'], ESC + b'[25m')
    check_raw_suffix("NO-REVERSE", ['ANSI-NO-REVERSE'], ESC + b'[27m')
    check_raw_suffix("NO-HIDDEN", ['ANSI-NO-HIDDEN'], ESC + b'[28m')
    check_raw_suffix("NO-STRIKE", ['ANSI-NO-STRIKE'], ESC + b'[29m')


def test_ansi_colors_16():
    print("\n── ANSI 16 colors ──")
    check_raw_suffix("FG black", ['ANSI-BLACK ANSI-FG'], ESC + b'[30m')
    check_raw_suffix("FG red", ['ANSI-RED ANSI-FG'], ESC + b'[31m')
    check_raw_suffix("FG white", ['ANSI-WHITE ANSI-FG'], ESC + b'[37m')
    check_raw_suffix("BG blue", ['ANSI-BLUE ANSI-BG'], ESC + b'[44m')
    check_raw_suffix("FG-BRIGHT green", ['ANSI-GREEN ANSI-FG-BRIGHT'], ESC + b'[92m')
    check_raw_suffix("BG-BRIGHT cyan", ['ANSI-CYAN ANSI-BG-BRIGHT'], ESC + b'[106m')
    check_raw_suffix("DEFAULT-FG", ['ANSI-DEFAULT-FG'], ESC + b'[39m')
    check_raw_suffix("DEFAULT-BG", ['ANSI-DEFAULT-BG'], ESC + b'[49m')


def test_ansi_colors_256():
    print("\n── ANSI 256 colors ──")
    check_raw_suffix("FG256 208", ['208 ANSI-FG256'], ESC + b'[38;5;208m')
    check_raw_suffix("FG256 0", ['0 ANSI-FG256'], ESC + b'[38;5;0m')
    check_raw_suffix("BG256 255", ['255 ANSI-BG256'], ESC + b'[48;5;255m')


def test_ansi_colors_rgb():
    print("\n── ANSI true-color RGB ──")
    check_raw_suffix("FG-RGB 255,128,0", ['255 128 0 ANSI-FG-RGB'], ESC + b'[38;2;255;128;0m')
    check_raw_suffix("FG-RGB 0,0,0", ['0 0 0 ANSI-FG-RGB'], ESC + b'[38;2;0;0;0m')
    check_raw_suffix("BG-RGB 0,0,64", ['0 0 64 ANSI-BG-RGB'], ESC + b'[48;2;0;0;64m')


def test_ansi_modes():
    print("\n── ANSI terminal modes ──")
    check_raw_suffix("ALT-ON", ['ANSI-ALT-ON'], ESC + b'[?1049h')
    check_raw_suffix("ALT-OFF", ['ANSI-ALT-OFF'], ESC + b'[?1049l')
    check_raw_suffix("CURSOR-ON", ['ANSI-CURSOR-ON'], ESC + b'[?25h')
    check_raw_suffix("CURSOR-OFF", ['ANSI-CURSOR-OFF'], ESC + b'[?25l')
    check_raw_suffix("MOUSE-ON (1000h)", ['ANSI-MOUSE-ON'], ESC + b'[?1000h')
    check_raw_suffix("MOUSE-ON (1006h)", ['ANSI-MOUSE-ON'], ESC + b'[?1006h')
    check_raw_suffix("MOUSE-OFF (1006l)", ['ANSI-MOUSE-OFF'], ESC + b'[?1006l')
    check_raw_suffix("MOUSE-OFF (1000l)", ['ANSI-MOUSE-OFF'], ESC + b'[?1000l')
    check_raw_suffix("PASTE-ON", ['ANSI-PASTE-ON'], ESC + b'[?2004h')
    check_raw_suffix("PASTE-OFF", ['ANSI-PASTE-OFF'], ESC + b'[?2004l')


def test_ansi_queries():
    print("\n── ANSI queries ──")
    check_raw_suffix("QUERY-SIZE", ['ANSI-QUERY-SIZE'], ESC + b'[18t')
    check_raw_suffix("QUERY-CURSOR", ['ANSI-QUERY-CURSOR'], ESC + b'[6n')


def test_ansi_combo():
    print("\n── ANSI combined sequences ──")
    global _pass_count, _fail_count
    check_raw_suffix("BOLD+RED+text", ['ANSI-BOLD ANSI-RED ANSI-FG'], ESC + b'[31m')
    raw = run_forth_raw(['ANSI-ALT-ON ANSI-CLEAR ANSI-HOME ANSI-CURSOR-OFF'])
    ok = True
    for seq, label in [
        (ESC + b'[?1049h', "ALT-ON"),
        (ESC + b'[2J', "CLEAR"),
        (ESC + b'[H', "HOME"),
        (ESC + b'[?25l', "CURSOR-OFF"),
    ]:
        if seq not in raw:
            ok = False
            _fail_count += 1
            print(f"  FAIL  combo init: {label} missing")
    if ok:
        _pass_count += 1
        print(f"  PASS  combo init seq")


# =====================================================================
#  KEYS.F TESTS — Input Decoding (busy-loop injection)
# =====================================================================

def test_keys_printable():
    print("\n── KEYS printable characters ──")
    check_keys("char A", b'A', "0 65 0")
    check_keys("char space", b' ', "0 32 0")
    check_keys("char ~", b'~', "0 126 0")


def test_keys_special():
    print("\n── KEYS special keys ──")
    check_keys("TAB", bytes([9]), "1 24", fields="type-code")
    check_keys("ENTER", bytes([13]), "1 26", fields="type-code")
    check_keys("BACKSPACE", bytes([127]), "1 27", fields="type-code")
    check_keys("BS (byte 8)", bytes([8]), "1 27", fields="type-code")


def test_keys_ctrl():
    print("\n── KEYS ctrl combinations ──")
    check_keys("Ctrl+A", bytes([1]), "0 97 4")
    check_keys("Ctrl+C", bytes([3]), "0 99 4")
    check_keys("Ctrl+Z", bytes([26]), "0 122 4")


def test_keys_arrows():
    print("\n── KEYS arrow keys (CSI) ──")
    check_keys("Arrow UP", b'\x1b[A', "1 1 0")
    check_keys("Arrow DOWN", b'\x1b[B', "1 2 0")
    check_keys("Arrow RIGHT", b'\x1b[C', "1 3 0")
    check_keys("Arrow LEFT", b'\x1b[D', "1 4 0")


def test_keys_home_end():
    print("\n── KEYS Home/End ──")
    check_keys("Home (H)", b'\x1b[H', "1 5 0")
    check_keys("End (F)", b'\x1b[F', "1 6 0")
    check_keys("Home (1~)", b'\x1b[1~', "1 5 0")
    check_keys("End (4~)", b'\x1b[4~', "1 6 0")


def test_keys_page_ins_del():
    print("\n── KEYS PgUp/PgDn/Ins/Del ──")
    check_keys("Insert", b'\x1b[2~', "1 9", fields="type-code")
    check_keys("Delete", b'\x1b[3~', "1 10", fields="type-code")
    check_keys("PgUp", b'\x1b[5~', "1 7", fields="type-code")
    check_keys("PgDn", b'\x1b[6~', "1 8", fields="type-code")


def test_keys_fkeys():
    print("\n── KEYS function keys ──")
    check_keys("F1", b'\x1bOP', "1 11", fields="type-code")
    check_keys("F2", b'\x1bOQ', "1 12", fields="type-code")
    check_keys("F3", b'\x1bOR', "1 13", fields="type-code")
    check_keys("F4", b'\x1bOS', "1 14", fields="type-code")
    check_keys("F5", b'\x1b[15~', "1 15", fields="type-code")
    check_keys("F12", b'\x1b[24~', "1 22", fields="type-code")


def test_keys_shift_tab():
    print("\n── KEYS Shift-Tab ──")
    check_keys("Shift-Tab", b'\x1b[Z', "1 25", fields="type-code")


def test_keys_modifiers():
    print("\n── KEYS modified arrows ──")
    check_keys("Shift+Up", b'\x1b[1;2A', "1 1 1")
    check_keys("Ctrl+Right", b'\x1b[1;5C', "1 3 4")
    check_keys("Alt+Left", b'\x1b[1;3D', "1 4 2")


def test_keys_accessors():
    print("\n── KEYS accessor helpers ──")
    check_keys_custom("IS-CHAR? on A", b'A',
        '_EV KEY-IS-CHAR? .', "-1")
    check_keys_custom("IS-SPECIAL? on UP", b'\x1b[A',
        '_EV KEY-IS-SPECIAL? .', "-1")
    check_keys_custom("HAS-CTRL? on C-Right", b'\x1b[1;5C',
        '_EV KEY-HAS-CTRL? .', "-1")
    check_keys_custom("HAS-SHIFT? false", b'\x1b[A',
        '_EV KEY-HAS-SHIFT? .', "0")


# =====================================================================
#  CELL.F TESTS — Character Cell Type
# =====================================================================

def test_cell_pack_unpack():
    print("\n── CELL pack / unpack round-trip ──")
    # Pack: cp=65('A'), fg=7, bg=0, attrs=0  →  unpack all fields
    check("cp round-trip",    ['65 7 0 0 CELL-MAKE CELL-CP@ .'], "65")
    check("fg round-trip",    ['65 7 0 0 CELL-MAKE CELL-FG@ .'], "7")
    check("bg round-trip",    ['65 7 0 0 CELL-MAKE CELL-BG@ .'], "0")
    check("attrs round-trip", ['65 7 0 0 CELL-MAKE CELL-ATTRS@ .'], "0")
    # Non-zero bg/attrs
    check("bg=42 round-trip", ['88 14 42 0 CELL-MAKE CELL-BG@ .'], "42")
    check("attrs=3 round-trip", ['88 14 42 3 CELL-MAKE CELL-ATTRS@ .'], "3")
    # All fields at once
    check("full round-trip",
        ['9999 200 100 5 CELL-MAKE',
         'DUP CELL-CP@ .',
         'DUP CELL-FG@ .',
         'DUP CELL-BG@ .',
         'CELL-ATTRS@ .'], "9999 200 100 5")


def test_cell_setters():
    print("\n── CELL field setters ──")
    check("FG! replace",
        ['65 7 0 0 CELL-MAKE 200 SWAP CELL-FG!',
         'DUP CELL-FG@ . CELL-CP@ .'], "200 65")
    check("BG! replace",
        ['65 7 0 0 CELL-MAKE 128 SWAP CELL-BG!',
         'DUP CELL-BG@ . CELL-FG@ .'], "128 7")
    check("ATTRS! replace",
        ['65 7 0 0 CELL-MAKE 15 SWAP CELL-ATTRS!',
         'DUP CELL-ATTRS@ . CELL-CP@ .'], "15 65")
    check("CP! replace",
        ['65 7 0 0 CELL-MAKE 90 SWAP CELL-CP!',
         'DUP CELL-CP@ . CELL-FG@ .'], "90 7")


def test_cell_blank():
    print("\n── CELL blank and predicates ──")
    check("CELL-BLANK cp=32",   ['CELL-BLANK CELL-CP@ .'], "32")
    check("CELL-BLANK fg=7",    ['CELL-BLANK CELL-FG@ .'], "7")
    check("CELL-BLANK bg=0",    ['CELL-BLANK CELL-BG@ .'], "0")
    check("CELL-BLANK attrs=0", ['CELL-BLANK CELL-ATTRS@ .'], "0")


def test_cell_predicates():
    print("\n── CELL predicates ──")
    check("EQUAL? same",   ['CELL-BLANK CELL-BLANK CELL-EQUAL? .'], "-1")
    check("EQUAL? diff",   ['CELL-BLANK 65 7 0 0 CELL-MAKE CELL-EQUAL? .'], "0")
    check("EMPTY? blank",  ['CELL-BLANK CELL-EMPTY? .'], "-1")
    check("EMPTY? cp=0",   ['0 7 0 0 CELL-MAKE CELL-EMPTY? .'], "-1")
    check("EMPTY? letter", ['65 7 0 0 CELL-MAKE CELL-EMPTY? .'], "0")
    check("EMPTY? fg≠7",   ['32 14 0 0 CELL-MAKE CELL-EMPTY? .'], "0")
    check("EMPTY? attrs",  ['32 7 0 3 CELL-MAKE CELL-EMPTY? .'], "0")


def test_cell_has_attr():
    print("\n── CELL attribute flag testing ──")
    check("HAS-ATTR? bold true",
        ['65 7 0 CELL-A-BOLD CELL-MAKE',
         'CELL-A-BOLD SWAP CELL-HAS-ATTR? .'], "-1")
    check("HAS-ATTR? bold false",
        ['65 7 0 0 CELL-MAKE',
         'CELL-A-BOLD SWAP CELL-HAS-ATTR? .'], "0")
    check("HAS-ATTR? multi",
        ['65 7 0 CELL-A-BOLD CELL-A-ITALIC OR CELL-MAKE  DUP CELL-A-BOLD SWAP CELL-HAS-ATTR? .  CELL-A-ITALIC SWAP CELL-HAS-ATTR? .'], "-1 -1")


def test_cell_edge_cases():
    print("\n── CELL edge cases ──")
    check("cp=0 empty", ['0 7 0 0 CELL-MAKE CELL-CP@ .'], "0")
    check("fg=255",     ['65 255 0 0 CELL-MAKE CELL-FG@ .'], "255")
    check("bg=255",     ['65 0 255 0 CELL-MAKE CELL-BG@ .'], "255")
    check("max attrs",  ['65 7 0 65535 CELL-MAKE CELL-ATTRS@ .'], "65535")
    check("wide flag",
        ['65 7 0 CELL-A-WIDE CELL-MAKE',
         'CELL-A-WIDE SWAP CELL-HAS-ATTR? .'], "-1")
    check("cont flag",
        ['65 7 0 CELL-A-CONT CELL-MAKE',
         'CELL-A-CONT SWAP CELL-HAS-ATTR? .'], "-1")


# =====================================================================
#  SCREEN.F TESTS — Virtual Screen Buffer
# =====================================================================

def test_scr_create():
    print("\n── SCREEN create / size ──")
    check("SCR-NEW non-zero",
        ['80 24 SCR-NEW DUP 0<> . SCR-FREE'], "-1")
    check("SCR-W",
        ['40 12 SCR-NEW DUP SCR-USE SCR-W . SCR-FREE'], "40")
    check("SCR-H",
        ['40 12 SCR-NEW DUP SCR-USE SCR-H . SCR-FREE'], "12")


def test_scr_set_get():
    print("\n── SCREEN set / get ──")
    check("set/get round-trip",
        ['4 3 SCR-NEW DUP SCR-USE',
         '65 7 0 0 CELL-MAKE 1 2 SCR-SET',
         '1 2 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "65")
    check("set/get at 0,0",
        ['4 3 SCR-NEW DUP SCR-USE',
         '88 14 42 0 CELL-MAKE 0 0 SCR-SET',
         '0 0 SCR-GET DUP CELL-CP@ . CELL-FG@ .',
         'SCR-FREE'], "88 14")
    check("set/get corner",
        ['10 5 SCR-NEW DUP SCR-USE',
         '90 1 2 0 CELL-MAKE 4 9 SCR-SET',
         '4 9 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "90")


def test_scr_clear_fill():
    print("\n── SCREEN clear / fill ──")
    check("clear → blank",
        ['4 2 SCR-NEW DUP SCR-USE',
         'SCR-CLEAR',
         '0 0 SCR-GET CELL-BLANK CELL-EQUAL? .',
         'SCR-FREE'], "-1")
    check("fill custom cell",
        ['4 2 SCR-NEW DUP SCR-USE',
         '88 14 42 0 CELL-MAKE SCR-FILL',
         '0 0 SCR-GET CELL-CP@ .',
         '1 3 SCR-GET CELL-FG@ .',
         'SCR-FREE'], "88 14")


def test_scr_cursor():
    print("\n── SCREEN cursor ──")
    # Cursor position tracked in descriptor
    check("cursor-at",
        ['4 3 SCR-NEW DUP SCR-USE',
         '5 10 SCR-CURSOR-AT',
         # Read descriptor directly to verify
         'DUP 32 + @ . DUP 40 + @ .',
         'SCR-FREE'], "5 10")


def test_scr_flush_basic():
    """Test that flush emits ANSI sequences for changed cells."""
    print("\n── SCREEN flush basics ──")
    # Force + flush a 4x2 screen with one 'X' at (0,0), rest blank
    # Expect: ESC[?25l (cursor off), ESC[1;1H (position), 'X' char
    check_raw_suffix("flush emits cursor-off",
        ['4 2 SCR-NEW DUP SCR-USE',
         '88 7 0 0 CELL-MAKE 0 0 SCR-SET',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[?25l')
    check_raw_suffix("flush emits ANSI-AT 1;1",
        ['4 2 SCR-NEW DUP SCR-USE',
         '88 7 0 0 CELL-MAKE 0 0 SCR-SET',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[1;1H')
    check_raw_suffix("flush emits character X",
        ['4 2 SCR-NEW DUP SCR-USE',
         '88 7 0 0 CELL-MAKE 0 0 SCR-SET',
         'SCR-FORCE SCR-FLUSH'],
        b'X')
    check_raw_suffix("flush emits reset at end",
        ['4 2 SCR-NEW DUP SCR-USE',
         '88 7 0 0 CELL-MAKE 0 0 SCR-SET',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[0m')


def test_scr_flush_skip_unchanged():
    """After flushing, flushing again with no changes should be minimal."""
    print("\n── SCREEN flush skip unchanged ──")
    # Flush once (force), then flush again. Second flush should only have
    # cursor-off, reset, and possibly cursor restore — no cell data
    global _pass_count, _fail_count
    raw = run_forth_raw(
        ['4 2 SCR-NEW DUP SCR-USE',
         'SCR-FORCE SCR-FLUSH',
         '42 EMIT',   # marker byte '*' = 42
         'SCR-FLUSH']
    )
    # Find marker byte position, check output after it
    marker_pos = raw.rfind(ord('*'))
    if marker_pos >= 0:
        after = raw[marker_pos+1:]
        # Second flush should NOT contain ESC[1;1H (no cell positioning needed)
        if b'\x1b[1;1H' not in after:
            _pass_count += 1
            print("  PASS  second flush skips unchanged cells")
        else:
            _fail_count += 1
            print("  FAIL  second flush skips unchanged cells")
            print(f"        second flush still positions cursor: got {list(after[:60])}")
    else:
        _fail_count += 1
        print("  FAIL  second flush skips unchanged cells (no marker found)")


def test_scr_flush_attrs():
    """Flush emits SGR codes for bold cells."""
    print("\n── SCREEN flush with attributes ──")
    check_raw_suffix("flush bold emits SGR 1",
        ['4 2 SCR-NEW DUP SCR-USE',
         '65 7 0 CELL-A-BOLD CELL-MAKE 0 0 SCR-SET',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[1m')


def test_scr_flush_color():
    """Flush emits FG256/BG256 for colored cells."""
    print("\n── SCREEN flush with colors ──")
    check_raw_suffix("flush fg=14",
        ['4 2 SCR-NEW DUP SCR-USE',
         '65 14 0 0 CELL-MAKE 0 0 SCR-SET',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[38;5;14m')
    check_raw_suffix("flush bg=42",
        ['4 2 SCR-NEW DUP SCR-USE',
         '65 7 42 0 CELL-MAKE 0 0 SCR-SET',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[48;5;42m')


def test_scr_flush_cursor_show():
    """Flush shows cursor at specified position when cursor-vis is on."""
    print("\n── SCREEN flush cursor show ──")
    check_raw_suffix("flush shows cursor",
        ['4 2 SCR-NEW DUP SCR-USE',
         'SCR-CURSOR-ON 0 1 SCR-CURSOR-AT',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[?25h')
    # The cursor position should be at row=1,col=2 (0-based→1-based)
    check_raw_suffix("flush cursor at 1,2",
        ['4 2 SCR-NEW DUP SCR-USE',
         'SCR-CURSOR-ON 0 1 SCR-CURSOR-AT',
         'SCR-FORCE SCR-FLUSH'],
        b'\x1b[1;2H')


def test_scr_resize():
    print("\n── SCREEN resize ──")
    check("resize width",
        ['4 2 SCR-NEW DUP SCR-USE',
         '88 7 0 0 CELL-MAKE 0 0 SCR-SET',
         '8 4 SCR-RESIZE',
         'SCR-W . SCR-H .',
         'SCR-FREE'], "8 4")
    check("resize preserves content",
        ['4 2 SCR-NEW DUP SCR-USE',
         '88 7 0 0 CELL-MAKE 0 0 SCR-SET',
         '8 4 SCR-RESIZE',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "88")
    check("resize shrink preserves overlap",
        ['4 4 SCR-NEW DUP SCR-USE',
         '90 7 0 0 CELL-MAKE 1 1 SCR-SET',
         '2 2 SCR-RESIZE',
         '1 1 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "90")


# =====================================================================
#  DRAW.F TESTS — Cell-Level Drawing Primitives
# =====================================================================

def test_draw_style():
    print("\n── DRAW style state ──")
    check("default fg=7",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR',
         'DRW-STYLE-RESET',
         '65 0 0 DRW-CHAR',
         '0 0 SCR-GET CELL-FG@ .',
         'SCR-FREE'], "7")
    check("set fg=14",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '14 DRW-FG!',
         '65 0 0 DRW-CHAR',
         '0 0 SCR-GET CELL-FG@ .',
         'SCR-FREE'], "14")
    check("set bg=42",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '42 DRW-BG!',
         '65 0 0 DRW-CHAR',
         '0 0 SCR-GET CELL-BG@ .',
         'SCR-FREE'], "42")
    check("set attrs=bold",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR',
         'CELL-A-BOLD DRW-ATTR!',
         '65 0 0 DRW-CHAR',
         '0 0 SCR-GET CELL-ATTRS@ .',
         'SCR-FREE'], "1")
    check("STYLE! sets all three",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '14 42 3 DRW-STYLE!',
         '65 0 0 DRW-CHAR',
         '0 0 SCR-GET DUP CELL-FG@ . DUP CELL-BG@ . CELL-ATTRS@ .',
         'SCR-FREE'], "14 42 3")
    check("STYLE-RESET restores defaults",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '14 42 3 DRW-STYLE!',
         'DRW-STYLE-RESET',
         '65 0 0 DRW-CHAR',
         '0 0 SCR-GET DUP CELL-FG@ . DUP CELL-BG@ . CELL-ATTRS@ .',
         'SCR-FREE'], "7 0 0")


def test_draw_char():
    print("\n── DRAW char placement ──")
    check("char at 2,3",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '88 2 3 DRW-CHAR',
         '2 3 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "88")
    check("char clip negative row",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '88 -1 0 DRW-CHAR',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32")   # should remain blank (space=32)
    check("char clip beyond width",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '88 0 10 DRW-CHAR',
         '0 9 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32")   # out-of-bounds, last cell still blank
    check("char clip beyond height",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '88 5 0 DRW-CHAR',
         '4 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32")


def test_draw_hline():
    print("\n── DRAW horizontal line ──")
    check("hline 5 chars",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '45 1 2 5 DRW-HLINE',
         '1 2 SCR-GET CELL-CP@ . 1 6 SCR-GET CELL-CP@ . 1 7 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "45 45 32")
    check("hline len=0 no-op",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '45 0 0 0 DRW-HLINE',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32")


def test_draw_vline():
    print("\n── DRAW vertical line ──")
    check("vline 3 chars",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '124 1 4 3 DRW-VLINE',
         '1 4 SCR-GET CELL-CP@ . 3 4 SCR-GET CELL-CP@ . 4 4 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "124 124 32")


def test_draw_fill_rect():
    print("\n── DRAW fill rectangle ──")
    check("fill 3x4 rect",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '35 1 2 3 4 DRW-FILL-RECT',
         '1 2 SCR-GET CELL-CP@ . 3 5 SCR-GET CELL-CP@ . 0 2 SCR-GET CELL-CP@ . 1 6 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "35 35 32 32")


def test_draw_clear_rect():
    print("\n── DRAW clear rectangle ──")
    check("clear rect restores blanks",
        ['10 5 SCR-NEW DUP SCR-USE',
         '88 7 0 0 CELL-MAKE SCR-FILL',
         'DRW-STYLE-RESET',
         '1 1 2 3 DRW-CLEAR-RECT',
         '1 1 SCR-GET CELL-CP@ . 0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32 88")


def test_draw_text():
    print("\n── DRAW text placement ──")
    check("text at row 0 col 0",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'S" Hi" 0 0 DRW-TEXT',
         '0 0 SCR-GET CELL-CP@ . 0 1 SCR-GET CELL-CP@ . 0 2 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "72 105 32")  # 'H'=72, 'i'=105, blank after
    check("text row 3 col 2",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'S" AB" 3 2 DRW-TEXT',
         '3 2 SCR-GET CELL-CP@ . 3 3 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "65 66")


def test_draw_text_center():
    print("\n── DRAW text center ──")
    # "AB" (2 chars) in field of width 6 → pad 2 left → starts at col 2+2=4
    check("center AB in width 6",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'S" AB" 0 2 6 DRW-TEXT-CENTER',
         '0 4 SCR-GET CELL-CP@ . 0 5 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "65 66")


def test_draw_text_right():
    print("\n── DRAW text right-align ──")
    # "AB" (2 chars) in field of width 6 → pad 4 right → starts at col 2+4=6
    check("right AB in width 6",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'S" AB" 0 2 6 DRW-TEXT-RIGHT',
         '0 6 SCR-GET CELL-CP@ . 0 7 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "65 66")


def test_draw_zero_area():
    print("\n── DRAW zero/edge area ──")
    check("fill 0-height rect",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '35 0 0 0 5 DRW-FILL-RECT',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32")
    check("fill 0-width rect",
        ['10 5 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '35 0 0 5 0 DRW-FILL-RECT',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32")


# =====================================================================
#  BOX.F TESTS — Box Drawing & Borders
# =====================================================================

def test_box_single():
    print("\n── BOX single-line border ──")
    # Draw a 4x6 single box at (0,0)
    # Top-left = ┌ (0x250C = 9484), Top-right = ┐ (0x2510 = 9488)
    # Bot-left = └ (0x2514 = 9492), Bot-right = ┘ (0x2518 = 9496)
    # Horiz = ─ (0x2500 = 9472), Vert = │ (0x2502 = 9474)
    check("single TL corner",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 4 6 BOX-DRAW',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9484")
    check("single TR corner",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 4 6 BOX-DRAW',
         '0 5 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9488")
    check("single BL corner",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 4 6 BOX-DRAW',
         '3 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9492")
    check("single BR corner",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 4 6 BOX-DRAW',
         '3 5 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9496")
    check("single top horiz",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 4 6 BOX-DRAW',
         '0 1 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9472")
    check("single left vert",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 4 6 BOX-DRAW',
         '1 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9474")
    check("single interior blank",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 4 6 BOX-DRAW',
         '1 1 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "32")


def test_box_double():
    print("\n── BOX double-line border ──")
    # ╔ = 0x2554 = 9556
    check("double TL corner",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-DOUBLE 1 1 3 4 BOX-DRAW',
         '1 1 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9556")
    # ═ = 0x2550 = 9552
    check("double horiz",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-DOUBLE 1 1 3 4 BOX-DRAW',
         '1 2 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9552")


def test_box_ascii():
    print("\n── BOX ASCII fallback ──")
    check("ascii TL = +",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-ASCII 0 0 3 5 BOX-DRAW',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "43")
    check("ascii horiz = -",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-ASCII 0 0 3 5 BOX-DRAW',
         '0 1 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "45")
    check("ascii vert = |",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-ASCII 0 0 3 5 BOX-DRAW',
         '1 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "124")


def test_box_min_size():
    print("\n── BOX minimum size ──")
    # 2x2 box: just corners, no edges
    check("2x2 TL corner",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 2 2 BOX-DRAW',
         '0 0 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9484")
    check("2x2 BR corner",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 0 0 2 2 BOX-DRAW',
         '1 1 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9496")


def test_box_titled():
    print("\n── BOX titled border ──")
    # Title "Hi" at col+2 on top row
    check("titled box title chars",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE S" Hi" 0 0 5 10 BOX-DRAW-TITLED',
         '0 2 SCR-GET CELL-CP@ . 0 3 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "72 105")
    check("titled box corners intact",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE S" Hi" 0 0 5 10 BOX-DRAW-TITLED',
         '0 0 SCR-GET CELL-CP@ . 0 9 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9484 9488")


def test_box_hline_vline():
    print("\n── BOX hline / vline helpers ──")
    check("BOX-HLINE uses style horiz",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 2 1 5 BOX-HLINE',
         '2 1 SCR-GET CELL-CP@ . 2 5 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9472 9472")
    check("BOX-VLINE uses style vert",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         'BOX-SINGLE 1 3 4 BOX-VLINE',
         '1 3 SCR-GET CELL-CP@ . 4 3 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9474 9474")


def test_box_shadow():
    print("\n── BOX shadow ──")
    # Shadow at right edge and bottom edge
    # For a box at row=0 col=0 h=3 w=5:
    #   right shadow: col=5, rows 1..3  (vline)
    #   bottom shadow: row=3, cols 1..5  (hline)
    # Shadow char = ░ = 0x2591 = 9617
    check("shadow right edge",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 3 5 BOX-SHADOW',
         '1 5 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9617")
    check("shadow bottom edge",
        ['20 10 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 3 5 BOX-SHADOW',
         '3 1 SCR-GET CELL-CP@ .',
         'SCR-FREE'], "9617")


# =====================================================================
#  REGION.F TESTS — Rectangular Clipping Regions (Layer 3)
# =====================================================================

def test_rgn_create():
    """Root region creation and accessors."""
    print("\n── REGION create ──")
    check("new region row",
        ['2 5 10 20 RGN-NEW DUP RGN-ROW . RGN-FREE'], "2")
    check("new region col",
        ['2 5 10 20 RGN-NEW DUP RGN-COL . RGN-FREE'], "5")
    check("new region h",
        ['2 5 10 20 RGN-NEW DUP RGN-H . RGN-FREE'], "10")
    check("new region w",
        ['2 5 10 20 RGN-NEW DUP RGN-W . RGN-FREE'], "20")


def test_rgn_use_draw():
    """RGN-USE makes DRW-CHAR translate+clip."""
    print("\n── REGION use+draw ──")
    # Draw at (0,0) in region at (2,5) → screen cell (2,5)
    check("char at region origin",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 10 20 RGN-NEW DUP RGN-USE',
         '65 0 0 DRW-CHAR',
         '2 5 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "65")  # 'A'=65
    # Draw at (1,3) in region at (2,5) → screen cell (3,8)
    check("char at region offset",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 10 20 RGN-NEW DUP RGN-USE',
         '66 1 3 DRW-CHAR',
         '3 8 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "66")  # 'B'=66
    # Draw outside region bounds → clipped (silent discard)
    check("char clipped beyond region w",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 3 4 RGN-NEW DUP RGN-USE',
         '88 0 4 DRW-CHAR',
         '2 9 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "32")  # stays blank
    check("char clipped beyond region h",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 3 4 RGN-NEW DUP RGN-USE',
         '88 3 0 DRW-CHAR',
         '5 5 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "32")  # stays blank
    check("char clipped negative",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 3 4 RGN-NEW DUP RGN-USE',
         '88 -1 0 DRW-CHAR',
         '1 5 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "32")  # stays blank


def test_rgn_root():
    """RGN-ROOT resets to full-screen drawing."""
    print("\n── REGION root reset ──")
    check("root draws at screen coords",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 3 4 RGN-NEW',
         'DUP RGN-USE',
         'RGN-ROOT',
         '65 0 0 DRW-CHAR',
         '0 0 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "65")


def test_rgn_sub():
    """Sub-region creation and parent clipping."""
    print("\n── REGION sub-region ──")
    # Sub-region at (1,2) relative to parent at (5,10) → absolute (6,12)
    check("sub row",
        ['5 10 20 30 RGN-NEW',
         'DUP 1 2 5 8 RGN-SUB',
         'DUP RGN-ROW . RGN-FREE RGN-FREE'], "6")
    check("sub col",
        ['5 10 20 30 RGN-NEW',
         'DUP 1 2 5 8 RGN-SUB',
         'DUP RGN-COL . RGN-FREE RGN-FREE'], "12")
    check("sub h",
        ['5 10 20 30 RGN-NEW',
         'DUP 1 2 5 8 RGN-SUB',
         'DUP RGN-H . RGN-FREE RGN-FREE'], "5")
    check("sub w",
        ['5 10 20 30 RGN-NEW',
         'DUP 1 2 5 8 RGN-SUB',
         'DUP RGN-W . RGN-FREE RGN-FREE'], "8")
    # Sub-region clipped to parent: parent h=10, sub at row 8 with h=5 → clipped to 2
    check("sub clipped height",
        ['0 0 10 20 RGN-NEW',
         'DUP 8 0 5 10 RGN-SUB',
         'DUP RGN-H . RGN-FREE RGN-FREE'], "2")
    # Sub-region clipped width: parent w=20, sub at col 15 with w=10 → clipped to 5
    check("sub clipped width",
        ['0 0 10 20 RGN-NEW',
         'DUP 0 15 5 10 RGN-SUB',
         'DUP RGN-W . RGN-FREE RGN-FREE'], "5")


def test_rgn_contains():
    """Point containment testing."""
    print("\n── REGION contains ──")
    check("inside region",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '2 5 10 20 RGN-NEW DUP RGN-USE',
         '3 7 RGN-CONTAINS? .',
         'RGN-FREE SCR-FREE'], "-1")  # TRUE
    check("outside region (col too large)",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '2 5 10 20 RGN-NEW DUP RGN-USE',
         '3 20 RGN-CONTAINS? .',
         'RGN-FREE SCR-FREE'], "0")
    check("outside region (row too large)",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '2 5 10 20 RGN-NEW DUP RGN-USE',
         '10 5 RGN-CONTAINS? .',
         'RGN-FREE SCR-FREE'], "0")


def test_rgn_clip():
    """RGN-CLIP translates and tests."""
    print("\n── REGION clip ──")
    check("clip inside: abs coords + flag",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '2 5 10 20 RGN-NEW DUP RGN-USE',
         '3 7 RGN-CLIP . . .',
         'RGN-FREE SCR-FREE'], "-1 12 5")  # flag row' col' (printed in reverse: col', row', flag from stack)
    check("clip outside: flag=0",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '2 5 10 20 RGN-NEW DUP RGN-USE',
         '10 25 RGN-CLIP . . .',
         'RGN-FREE SCR-FREE'], "0 30 12")


def test_rgn_zero_size():
    """Zero-size region clips everything."""
    print("\n── REGION zero size ──")
    check("zero-h region clips all",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 0 10 RGN-NEW DUP RGN-USE',
         '65 0 0 DRW-CHAR',
         'RGN-ROOT 0 0 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "32")
    check("zero-w region clips all",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 10 0 RGN-NEW DUP RGN-USE',
         '65 0 0 DRW-CHAR',
         'RGN-ROOT 0 0 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "32")


def test_rgn_draw_at_edges():
    """Drawing at the very edges of a region."""
    print("\n── REGION edge drawing ──")
    # Region is 3h x 4w at (1,2). Last valid cell is (2,3) → screen (3,5)
    check("draw at last valid cell",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '1 2 3 4 RGN-NEW DUP RGN-USE',
         '90 2 3 DRW-CHAR',
         '3 5 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "90")  # 'Z'=90
    # Just beyond last valid → clipped
    check("draw just past last col",
        ['20 40 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '1 2 3 4 RGN-NEW DUP RGN-USE',
         '90 2 4 DRW-CHAR',
         'RGN-ROOT 3 6 SCR-GET CELL-CP@ .',
         'RGN-FREE SCR-FREE'], "32")


# =====================================================================
#  LAYOUT.F TESTS — Container Layout Engine (Layer 3)
# =====================================================================

def test_lay_create():
    """Layout creation and accessors."""
    print("\n── LAYOUT create ──")
    check("new layout count=0",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP LAY-COUNT . 8888 .',
         'LAY-FREE RGN-FREE'], "0 8888")


def test_lay_add():
    """LAY-ADD creates children."""
    print("\n── LAYOUT add children ──")
    check("add 1 child",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP 8 2 LAY-ADD DROP',
         'DUP LAY-COUNT . 8888 .',
         'LAY-FREE RGN-FREE'], "1 8888")
    check("add 3 children",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP 8 2 LAY-ADD DROP',
         'DUP 6 2 LAY-ADD DROP',
         'DUP 4 2 LAY-ADD DROP',
         'DUP LAY-COUNT . 8888 .',
         'LAY-FREE RGN-FREE'], "3 8888")


def test_lay_vertical_fixed():
    """Vertical layout with fixed-size children."""
    print("\n── LAYOUT vertical fixed ──")
    # Parent: 24h x 50w at (0,0). Two children: 8 rows and 6 rows.
    check("vert child0 row=0 h=8",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP 8 2 LAY-ADD DROP DUP 6 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD DUP RGN-ROW . RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "0 8 8888")
    check("vert child1 row=8 h=6",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP 8 2 LAY-ADD DROP DUP 6 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 1 LAY-CHILD DUP RGN-ROW . RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "8 6 8888")
    # Width should == parent width
    check("vert child0 w=50",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP 8 2 LAY-ADD DROP DUP 6 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD RGN-W . 8888 .',
         'LAY-FREE RGN-FREE'], "50 8888")


def test_lay_vertical_gap():
    """Vertical layout with gaps."""
    print("\n── LAYOUT vertical gap ──")
    # Parent 24h, gap=2, two children of 7 rows each
    # child0: row=0, h=7; child1: row=7+2=9, h=7
    check("vert gap child1 row=9",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 2 LAY-NEW',
         'DUP 7 2 LAY-ADD DROP DUP 7 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 1 LAY-CHILD RGN-ROW . 8888 .',
         'LAY-FREE RGN-FREE'], "9 8888")


def test_lay_vertical_expand():
    """Vertical layout with expand — auto children split remaining."""
    print("\n── LAYOUT vertical expand ──")
    # Parent 24h, one fixed 6h child + two expand children. gap=0.
    # Remaining = 24 - 6 = 18.  Two auto → 9 each.
    check("expand child1 h=9",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'LAY-F-EXPAND OVER LAY-FLAGS!',
         'DUP 6 2 LAY-ADD DROP DUP 0 0 LAY-ADD DROP DUP 0 0 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 1 LAY-CHILD RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "9 8888")
    check("expand child2 row=15 h=9",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'LAY-F-EXPAND OVER LAY-FLAGS!',
         'DUP 6 2 LAY-ADD DROP DUP 0 0 LAY-ADD DROP DUP 0 0 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 2 LAY-CHILD DUP RGN-ROW . RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "15 9 8888")


def test_lay_horizontal_fixed():
    """Horizontal layout with fixed-size children."""
    print("\n── LAYOUT horizontal fixed ──")
    # Parent 12h x 50w at (0,0). Two children: 18w and 14w.
    check("horiz child0 col=0 w=18",
        ['0 0 12 50 RGN-NEW',
         'DUP LAY-HORIZONTAL 0 LAY-NEW',
         'DUP 18 2 LAY-ADD DROP DUP 14 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD DUP RGN-COL . RGN-W . 8888 .',
         'LAY-FREE RGN-FREE'], "0 18 8888")
    check("horiz child1 col=18 w=14",
        ['0 0 12 50 RGN-NEW',
         'DUP LAY-HORIZONTAL 0 LAY-NEW',
         'DUP 18 2 LAY-ADD DROP DUP 14 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 1 LAY-CHILD DUP RGN-COL . RGN-W . 8888 .',
         'LAY-FREE RGN-FREE'], "18 14 8888")
    # Height should == parent height
    check("horiz child0 h=12",
        ['0 0 12 50 RGN-NEW',
         'DUP LAY-HORIZONTAL 0 LAY-NEW',
         'DUP 18 2 LAY-ADD DROP DUP 14 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "12 8888")


def test_lay_horizontal_gap():
    """Horizontal layout with gaps."""
    print("\n── LAYOUT horizontal gap ──")
    # 16w + gap3 + 14w
    check("horiz gap child1 col=19 w=14",
        ['0 0 12 50 RGN-NEW',
         'DUP LAY-HORIZONTAL 3 LAY-NEW',
         'DUP 16 2 LAY-ADD DROP DUP 14 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 1 LAY-CHILD DUP RGN-COL . RGN-W . 8888 .',
         'LAY-FREE RGN-FREE'], "19 14 8888")


def test_lay_horizontal_expand():
    """Horizontal layout with expand."""
    print("\n── LAYOUT horizontal expand ──")
    # Parent 50w, fixed 16w + expand. gap=0.  expand gets 50-16=34.
    check("horiz expand child1 w=34",
        ['0 0 12 50 RGN-NEW',
         'DUP LAY-HORIZONTAL 0 LAY-NEW',
         'LAY-F-EXPAND OVER LAY-FLAGS!',
         'DUP 16 2 LAY-ADD DROP DUP 0 0 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 1 LAY-CHILD DUP RGN-COL . RGN-W . 8888 .',
         'LAY-FREE RGN-FREE'], "16 34 8888")


def test_lay_min_size():
    """Min-size enforcement."""
    print("\n── LAYOUT min-size ──")
    # Parent 24h. hint=0, expand, min=8. auto=24/1=24. 24>=8 → child=24
    check("min-size not clamped",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'LAY-F-EXPAND OVER LAY-FLAGS!',
         'DUP 0 8 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "24 8888")
    # Fixed hint=3 but min=7 → child gets 7
    check("min-size clamps up",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP 3 7 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "7 8888")


def test_lay_offset_parent():
    """Layout with non-zero-origin parent region."""
    print("\n── LAYOUT offset parent ──")
    # Parent at (7, 13). Vertical, child 8h.
    check("child inherits parent origin",
        ['7 13 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP 8 2 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD DUP RGN-ROW . RGN-COL . 8888 .',
         'LAY-FREE RGN-FREE'], "7 13 8888")


def test_lay_recompute():
    """Recompute after changing parent region."""
    print("\n── LAYOUT recompute ──")
    # Parent 24h. Two expand children. 24/2=12 each.
    check("recompute redistributes",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'LAY-F-EXPAND OVER LAY-FLAGS!',
         'DUP 0 0 LAY-ADD DROP DUP 0 0 LAY-ADD DROP',
         'DUP LAY-COMPUTE',
         'DUP 0 LAY-CHILD RGN-H . 8888 .',
         'LAY-FREE RGN-FREE'], "12 8888")


def test_lay_empty():
    """LAY-COMPUTE on empty layout is a no-op."""
    print("\n── LAYOUT empty ──")
    check("compute empty layout",
        ['0 0 24 50 RGN-NEW',
         'DUP LAY-VERTICAL 0 LAY-NEW',
         'DUP LAY-COMPUTE',
         'DUP LAY-COUNT . 8888 .',
         'LAY-FREE RGN-FREE'], "0 8888")


# =====================================================================
#  WIDGET.F TESTS — Common Widget Header (Layer 4A)
# =====================================================================

def test_wdg_type_constants():
    """Widget type constants have expected values."""
    print("\n── WIDGET type constants ──")
    check("WDG-T-LABEL",
        ['WDG-T-LABEL . 8888 .'], "1 8888")
    check("WDG-T-INPUT",
        ['WDG-T-INPUT . 8888 .'], "2 8888")
    check("WDG-T-PROGRESS",
        ['WDG-T-PROGRESS . 8888 .'], "5 8888")
    check("WDG-T-CANVAS",
        ['WDG-T-CANVAS . 8888 .'], "14 8888")

def test_wdg_flag_constants():
    """Widget flag constants."""
    print("\n── WIDGET flag constants ──")
    check("WDG-F-VISIBLE",
        ['WDG-F-VISIBLE . 8888 .'], "1 8888")
    check("WDG-F-FOCUSED",
        ['WDG-F-FOCUSED . 8888 .'], "2 8888")
    check("WDG-F-DIRTY",
        ['WDG-F-DIRTY . 8888 .'], "4 8888")
    check("WDG-F-DISABLED",
        ['WDG-F-DISABLED . 8888 .'], "8 8888")

def test_wdg_header_access():
    """Create a label to test header accessors."""
    print("\n── WIDGET header access ──")
    # Use a label as a concrete widget
    check("type via header",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         ': _T1 S" Hi" ; DUP _T1 LBL-LEFT LBL-NEW',
         'DUP WDG-TYPE . 8888 .',
         'LBL-FREE RGN-FREE SCR-FREE'], "1 8888")
    check("region via header",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         ': _T2 S" Hi" ;',
         'DUP DUP _T2 LBL-LEFT LBL-NEW',
         'DUP WDG-REGION ROT = . 8888 .',
         'LBL-FREE RGN-FREE SCR-FREE'], "-1 8888")  # same region address

def test_wdg_flags_ops():
    """Flag manipulation words."""
    print("\n── WIDGET flag ops ──")
    # Fresh label has VISIBLE + DIRTY = 5
    check("initial flags (visible+dirty)",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         ': _T3 S" X" ; DUP _T3 LBL-LEFT LBL-NEW',
         'DUP WDG-FLAGS . 8888 .',
         'LBL-FREE RGN-FREE SCR-FREE'], "5 8888")
    check("visible? true",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         ': _T4 S" X" ; DUP _T4 LBL-LEFT LBL-NEW',
         'DUP WDG-VISIBLE? . 8888 .',
         'LBL-FREE RGN-FREE SCR-FREE'], "-1 8888")
    check("hide clears visible",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         ': _T5 S" X" ; DUP _T5 LBL-LEFT LBL-NEW',
         'DUP WDG-HIDE',
         'DUP WDG-VISIBLE? . 8888 .',
         'LBL-FREE RGN-FREE SCR-FREE'], "0 8888")
    check("disable sets flag",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         ': _T6 S" X" ; DUP _T6 LBL-LEFT LBL-NEW',
         'DUP WDG-DISABLE',
         'DUP WDG-DISABLED? . 8888 .',
         'LBL-FREE RGN-FREE SCR-FREE'], "-1 8888")
    check("enable clears disabled",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         ': _T7 S" X" ; DUP _T7 LBL-LEFT LBL-NEW',
         'DUP WDG-DISABLE DUP WDG-ENABLE',
         'DUP WDG-DISABLED? . 8888 .',
         'LBL-FREE RGN-FREE SCR-FREE'], "0 8888")


# =====================================================================
#  LABEL.F TESTS — Static Text Labels (Layer 4A)
# =====================================================================

def test_lbl_left():
    """Left-aligned label draws text at col 0."""
    print("\n── LABEL left-align ──")
    check("left 'Hi' at (0,0)",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 3 20 RGN-NEW',
         ': _TL1 S" Hi" ; DUP _TL1 LBL-LEFT LBL-NEW',
         'WDG-DRAW',
         '2 5 SCR-GET CELL-CP@ . 2 6 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "72 105 8888")  # H=72, i=105
    check("left fills trailing with space",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 1 10 RGN-NEW',
         ': _TL2 S" AB" ; DUP _TL2 LBL-LEFT LBL-NEW',
         'WDG-DRAW',
         '2 7 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "32 8888")  # space after 'B'

def test_lbl_center():
    """Center-aligned label."""
    print("\n── LABEL center ──")
    # "AB" (2 chars) in width 10 → pad 4 left → starts at col 4 (region-rel)
    # Region at col 5, so abs col = 5+4 = 9
    check("center 'AB' in width 10",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 1 10 RGN-NEW',
         ': _TC1 S" AB" ; DUP _TC1 LBL-CENTER LBL-NEW',
         'WDG-DRAW',
         '2 9 SCR-GET CELL-CP@ . 2 10 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "65 66 8888")  # A=65, B=66

def test_lbl_right():
    """Right-aligned label."""
    print("\n── LABEL right ──")
    # "AB" (2 chars) in width 10 → pad 8 right → starts at col 8 (region-rel)
    # Region at col 5, so abs col = 5+8 = 13
    check("right 'AB' in width 10",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '2 5 1 10 RGN-NEW',
         ': _TR1 S" AB" ; DUP _TR1 LBL-RIGHT LBL-NEW',
         'WDG-DRAW',
         '2 13 SCR-GET CELL-CP@ . 2 14 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "65 66 8888")

def test_lbl_truncate():
    """Text longer than region width is truncated."""
    print("\n── LABEL truncate ──")
    check("text wider than region wraps to line 2",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 2 3 RGN-NEW',
         ': _TT1 S" ABCDEF" ;',
         'DUP _TT1 LBL-LEFT LBL-NEW',
         'WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 0 2 SCR-GET CELL-CP@ . 1 0 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "65 67 68 8888")  # A=65 C=67 D=68

def test_lbl_empty():
    """Empty text clears the region."""
    print("\n── LABEL empty ──")
    check("empty text clears region",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 5 RGN-NEW',
         ': _TE1 S" " ; DUP _TE1 0 LBL-LEFT LBL-NEW',
         'WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "32 8888")  # space

def test_lbl_set_text():
    """LBL-SET-TEXT updates text and marks dirty."""
    print("\n── LABEL set-text ──")
    check("set-text marks dirty",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 10 RGN-NEW',
         ': _TS1 S" Old" ; DUP _TS1 LBL-LEFT LBL-NEW',
         'DUP WDG-DRAW',
         ': _TS2 S" New" ; DUP _TS2 LBL-SET-TEXT',
         'DUP WDG-DIRTY? . 8888 .',
         'RGN-FREE SCR-FREE'], "-1 8888")

def test_lbl_set_align():
    """LBL-SET-ALIGN changes alignment."""
    print("\n── LABEL set-align ──")
    check("change to right-align",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 10 RGN-NEW',
         ': _SA1 S" XY" ; DUP _SA1 LBL-LEFT LBL-NEW',
         'DUP LBL-RIGHT LBL-SET-ALIGN',
         'DUP WDG-DRAW',
         '0 8 SCR-GET CELL-CP@ . 0 9 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "88 89 8888")  # X=88, Y=89

def test_lbl_hidden():
    """Hidden label does not draw."""
    print("\n── LABEL hidden ──")
    check("hidden label skips draw",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 10 RGN-NEW',
         ': _TH1 S" AB" ; DUP _TH1 LBL-LEFT LBL-NEW',
         'DUP WDG-HIDE',
         'DUP WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "32 8888")  # space (screen was cleared)


# =====================================================================
#  PROGRESS.F TESTS — Progress Bar & Spinner (Layer 4A)
# =====================================================================

def test_prg_create():
    """Create progress bar, check fields."""
    print("\n── PROGRESS create ──")
    check("type is WDG-T-PROGRESS",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'DUP 100 PRG-BAR PRG-NEW',
         'DUP WDG-TYPE . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "5 8888")
    check("initial pct is 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'DUP 100 PRG-BAR PRG-NEW',
         'DUP PRG-PCT . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_prg_set_pct():
    """Set value and read percentage."""
    print("\n── PROGRESS set/pct ──")
    check("50/100 = 50%",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'DUP 50 PRG-SET',
         'DUP PRG-PCT . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "50 8888")
    check("100/100 = 100%",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'DUP 100 PRG-SET',
         'DUP PRG-PCT . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "100 8888")

def test_prg_inc():
    """Increment value."""
    print("\n── PROGRESS inc ──")
    check("inc from 0 to 1",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'DUP PRG-INC DUP PRG-INC DUP PRG-INC',
         'DUP PRG-PCT . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "3 8888")

def test_prg_bar_draw():
    """Bar draws full/empty/fractional blocks."""
    print("\n── PROGRESS bar draw ──")
    # 0% → all empty blocks (U+2591 = 0x2591 = 9617)
    check("0% all empty",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 10 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "9617 8888")
    # 100% → all full blocks (U+2588 = 0x2588 = 9608)
    check("100% all full",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 10 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'DUP 100 PRG-SET WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 0 9 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "9608 9608 8888")
    # 50% in width 10 → 5 full, then empty
    check("50% half filled",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 10 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'DUP 50 PRG-SET WDG-DRAW',
         '0 4 SCR-GET CELL-CP@ . 0 5 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "9608 9617 8888")  # full at 4, empty at 5

def test_prg_bar_max_zero():
    """Max=0 edge case → all empty."""
    print("\n── PROGRESS max=0 ──")
    check("max=0 draws empty",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 10 RGN-NEW DUP 0 PRG-BAR PRG-NEW',
         'WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "9617 8888")
    check("max=0 pct is 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 10 RGN-NEW DUP 0 PRG-BAR PRG-NEW',
         'DUP PRG-PCT . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_prg_spinner():
    """Spinner draws a Braille character and advances frame."""
    print("\n── PROGRESS spinner ──")
    # Frame 0 → ⠋ = U+280B = 10251
    check("spinner frame 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 5 RGN-NEW DUP 0 PRG-SPINNER PRG-NEW',
         'WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "10251 8888")
    # After tick: frame 1 → ⠙ = U+2819 = 10265
    check("spinner after tick",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
         '0 0 1 5 RGN-NEW DUP 0 PRG-SPINNER PRG-NEW',
         'DUP PRG-TICK WDG-DRAW',
         '0 0 SCR-GET CELL-CP@ . 8888 .',
         'RGN-FREE SCR-FREE'], "10265 8888")

def test_prg_dirty():
    """PRG-SET marks dirty."""
    print("\n── PROGRESS dirty ──")
    check("set marks dirty",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 10 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "0 8888")  # clean after draw
    check("set re-dirties",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 10 RGN-NEW DUP 100 PRG-BAR PRG-NEW',
         'DUP WDG-DRAW DUP 25 PRG-SET',
         'DUP WDG-DIRTY? . 8888 .',
         'PRG-FREE RGN-FREE SCR-FREE'], "-1 8888")


# =====================================================================
#  Input tests (Layer 4B)
# =====================================================================

def test_inp_create():
    """INP-NEW creates an input widget with correct type and empty buffer."""
    print("\n── INPUT create ──")
    check("type is WDG-T-INPUT",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'DUP WDG-TYPE . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "2 8888")
    check("initial buf-len is 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_inp_set_get_text():
    """INP-SET-TEXT / INP-GET-TEXT round-trip."""
    print("\n── INPUT set/get text ──")
    check("set then get length",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" Hello" 2 PICK INP-SET-TEXT',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "5 8888")
    check("cursor at end after set",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" Hey" 2 PICK INP-SET-TEXT',
         'DUP INP-CURSOR-POS . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "3 8888")

def test_inp_insert_chars():
    """Insert characters via internal _INP-INSERT."""
    print("\n── INPUT insert chars ──")
    check("insert 3 chars, len=3",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         '65 OVER _INP-INSERT 66 OVER _INP-INSERT 67 OVER _INP-INSERT',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "3 8888")
    check("insert A B C, first byte = 65",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         '65 OVER _INP-INSERT 66 OVER _INP-INSERT 67 OVER _INP-INSERT',
         'DUP INP-GET-TEXT DROP C@ . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "65 8888")

def test_inp_backspace():
    """Backspace removes character before cursor."""
    print("\n── INPUT backspace ──")
    check("insert ABC, backspace → len=2",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" ABC" 2 PICK INP-SET-TEXT',
         'DUP _INP-BACKSPACE',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "2 8888")
    check("backspace at pos 0 does nothing",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" AB" 2 PICK INP-SET-TEXT',
         'DUP _INP-HOME',
         'DUP _INP-BACKSPACE',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "2 8888")

def test_inp_delete():
    """Forward delete removes character at cursor."""
    print("\n── INPUT delete ──")
    check("home then delete → removes first char",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" XYZ" 2 PICK INP-SET-TEXT',
         'DUP _INP-HOME DUP _INP-DELETE',
         'DUP INP-GET-TEXT NIP . DUP INP-GET-TEXT DROP C@ . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "2 89 8888")
    check("delete at end does nothing",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" AB" 2 PICK INP-SET-TEXT',
         'DUP _INP-DELETE',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "2 8888")

def test_inp_cursor_move():
    """Left/right cursor movement."""
    print("\n── INPUT cursor move ──")
    check("right from home is col 1",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" ABCD" 2 PICK INP-SET-TEXT',
         'DUP _INP-HOME DUP _INP-RIGHT',
         'DUP INP-CURSOR-POS . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "1 8888")
    check("left from end is col 3",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" ABCD" 2 PICK INP-SET-TEXT',
         'DUP _INP-LEFT',
         'DUP INP-CURSOR-POS . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "3 8888")

def test_inp_home_end():
    """Home and End cursor movement."""
    print("\n── INPUT home/end ──")
    check("home sets cursor to 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" ABCD" 2 PICK INP-SET-TEXT',
         'DUP _INP-HOME',
         'DUP INP-CURSOR-POS . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "0 8888")
    check("end after home goes to len",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" ABCD" 2 PICK INP-SET-TEXT',
         'DUP _INP-HOME DUP _INP-END',
         'DUP INP-CURSOR-POS . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "4 8888")

def test_inp_cursor_pos():
    """INP-CURSOR-POS returns codepoint position."""
    print("\n── INPUT cursor pos ──")
    check("cursor at end = char count",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" test" 2 PICK INP-SET-TEXT',
         'DUP INP-CURSOR-POS . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "4 8888")

def test_inp_clear():
    """INP-CLEAR resets buffer."""
    print("\n── INPUT clear ──")
    check("clear sets length to 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" hello" 2 PICK INP-SET-TEXT',
         'DUP INP-CLEAR',
         'DUP INP-GET-TEXT NIP . DUP INP-CURSOR-POS . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "0 0 8888")

def test_inp_capacity():
    """Insertion rejected when buffer is full."""
    print("\n── INPUT capacity ──")
    check("cap=3, insert 4th rejected",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 4 ALLOT',
         'DUP _IBUF 3 INP-NEW',
         '65 OVER _INP-INSERT 66 OVER _INP-INSERT 67 OVER _INP-INSERT',
         '68 OVER _INP-INSERT',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "3 8888")

def test_inp_placeholder():
    """Placeholder shown when buffer is empty."""
    print("\n── INPUT placeholder ──")
    check("placeholder set",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 1 20 RGN-NEW',
         'CREATE _IBUF 64 ALLOT',
         'DUP _IBUF 64 INP-NEW',
         'S" Type here" 2 PICK INP-SET-PLACEHOLDER',
         'DUP WDG-DRAW',
         'DUP INP-GET-TEXT NIP . 8888 .',
         'INP-FREE RGN-FREE SCR-FREE'], "0 8888")


# =====================================================================
#  List tests (Layer 4B)
# =====================================================================

def test_lst_create():
    """LST-NEW creates a list widget."""
    print("\n── LIST create ──")
    check("type is WDG-T-LIST",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 48 ALLOT',                  # 3 items × 2 cells = 48 bytes
         'S" Alpha" _LITEMS ! _LITEMS 8 + !',        # item 0 (reversed: len then addr)
         'S" Beta"  _LITEMS 16 + ! _LITEMS 24 + !',  # item 1
         'S" Gamma" _LITEMS 32 + ! _LITEMS 40 + !',  # item 2
         'DUP _LITEMS 3 LST-NEW',
         'DUP WDG-TYPE . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "3 8888")

def test_lst_select():
    """LST-SELECT and LST-SELECTED work."""
    print("\n── LIST select ──")
    # Items stored as (addr, len) pairs. S" leaves ( addr len ) on stack.
    # We need to store them properly: _LITEMS[0] = addr, _LITEMS[8] = len
    check("initial selection is 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 32 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'DUP _LITEMS 2 LST-NEW',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "0 8888")
    check("select index 1",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 32 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'DUP _LITEMS 2 LST-NEW',
         '1 OVER LST-SELECT',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "1 8888")

def test_lst_draw():
    """LST-NEW widget draws items."""
    print("\n── LIST draw ──")
    check("draw does not crash",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         'CREATE _LITEMS 32 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'DUP _LITEMS 2 LST-NEW',
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_lst_nav_down_up():
    """Navigate list with simulated up/down events."""
    print("\n── LIST nav down/up ──")
    # Simulate KEY-T-SPECIAL(1) KEY-DOWN(2) in event struct _EV
    check("down moves selection to 1",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 32 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'DUP _LITEMS 2 LST-NEW',
         'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "1 8888")
    check("up from 1 → 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 32 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'DUP _LITEMS 2 LST-NEW',
         '1 OVER LST-SELECT',
         'KEY-T-SPECIAL _EV ! KEY-UP _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_lst_scroll():
    """List scrolls when selection moves past visible area."""
    print("\n── LIST scroll ──")
    # 2-row visible region, 3 items: navigating to item 2 should scroll
    check("select 2 in 2-row region scrolls",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 2 20 RGN-NEW',
         'CREATE _LITEMS 48 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'S" CC" _LITEMS 40 + ! _LITEMS 32 + !',
         'DUP _LITEMS 3 LST-NEW',
         '2 OVER LST-SELECT',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "2 8888")

def test_lst_set_items():
    """LST-SET-ITEMS replaces the item list."""
    print("\n── LIST set items ──")
    check("set new items resets selection",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 32 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'DUP _LITEMS 2 LST-NEW',
         '1 OVER LST-SELECT',
         'CREATE _LITEMS2 16 ALLOT',
         'S" XX" _LITEMS2 8 + ! _LITEMS2 !',
         '_LITEMS2 1 2 PICK LST-SET-ITEMS',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_lst_home_end():
    """Home/End keys move to first/last item."""
    print("\n── LIST home/end ──")
    check("end goes to last item",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 48 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'S" CC" _LITEMS 40 + ! _LITEMS 32 + !',
         'DUP _LITEMS 3 LST-NEW',
         'KEY-T-SPECIAL _EV ! KEY-END _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "2 8888")
    check("home goes to first item",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 5 20 RGN-NEW',
         'CREATE _LITEMS 48 ALLOT',
         'S" AA" _LITEMS 8 + ! _LITEMS !',
         'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
         'S" CC" _LITEMS 40 + ! _LITEMS 32 + !',
         'DUP _LITEMS 3 LST-NEW',
         '2 OVER LST-SELECT',
         'KEY-T-SPECIAL _EV ! KEY-HOME _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP LST-SELECTED . 8888 .',
         'LST-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_lst_empty():
    """Empty list doesn't crash on draw or handle."""
    print("\n── LIST empty ──")
    check("draw empty list",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 3 20 RGN-NEW',
         '0 0 0 LST-NEW DROP',
         '8888 .'], "8888")


# =====================================================================
#  Tabs tests (Layer 4B)
# =====================================================================

def test_tab_create():
    """TAB-NEW creates an empty tab container."""
    print("\n── TABS create ──")
    check("type is WDG-T-TABS",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 10 40 RGN-NEW DUP TAB-NEW',
         'DUP WDG-TYPE . 8888 .',
         'TAB-FREE RGN-FREE SCR-FREE'], "8 8888")

def test_tab_add():
    """TAB-ADD increases count."""
    print("\n── TABS add ──")
    check("add 2 tabs, count=2",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 10 40 RGN-NEW DUP TAB-NEW',
         'S" Tab1" 2 PICK TAB-ADD DROP',
         'S" Tab2" 2 PICK TAB-ADD DROP',
         'DUP TAB-COUNT . 8888 .',
         'TAB-FREE RGN-FREE SCR-FREE'], "2 8888")

def test_tab_select():
    """TAB-SELECT switches active tab."""
    print("\n── TABS select ──")
    check("select tab 1",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 10 40 RGN-NEW DUP TAB-NEW',
         'S" Tab1" 2 PICK TAB-ADD DROP',
         'S" Tab2" 2 PICK TAB-ADD DROP',
         '1 OVER TAB-SELECT',
         'DUP TAB-ACTIVE . 8888 .',
         'TAB-FREE RGN-FREE SCR-FREE'], "1 8888")

def test_tab_draw():
    """TAB drawing does not crash."""
    print("\n── TABS draw ──")
    check("draw with 2 tabs",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 10 40 RGN-NEW DUP TAB-NEW',
         'S" One" 2 PICK TAB-ADD DROP',
         'S" Two" 2 PICK TAB-ADD DROP',
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         'TAB-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_tab_content():
    """TAB-CONTENT returns valid region."""
    print("\n── TABS content ──")
    check("content region is non-zero",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 10 40 RGN-NEW DUP TAB-NEW',
         'S" Tab1" 2 PICK TAB-ADD DROP',
         '0 OVER TAB-CONTENT 0<> . 8888 .',
         'TAB-FREE RGN-FREE SCR-FREE'], "-1 8888")

def test_tab_count():
    """TAB-COUNT returns 0 for empty and correct count after adds."""
    print("\n── TABS count ──")
    check("empty tab count = 0",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         '0 0 10 40 RGN-NEW DUP TAB-NEW',
         'DUP TAB-COUNT . 8888 .',
         'TAB-FREE RGN-FREE SCR-FREE'], "0 8888")


# =====================================================================
#  Menu tests (Layer 4C)
# =====================================================================

# Helper: common setup code for menu tests.
# Creates: screen, region(0 0 15 40), 2 menus, MNU-NEW widget on stack.
# Menu 0 "File" has 2 items: "New" (action _MNP), "Exit" (action _MNP)
# Menu 1 "Edit" has 2 items: "Cut" (action _MNP), "Paste" (action _MNP)

_MNU_SETUP = [
    '24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
    ': _MNP ;',    # no-op action
    # File menu items (2 × 32 = 64 bytes)
    'CREATE _MI0 64 ALLOT',
    'S" New"  _MI0 8 + ! _MI0 !',
    "' _MNP _MI0 16 + !  0 _MI0 24 + !",
    'S" Exit" _MI0 40 + ! _MI0 32 + !',
    "' _MNP _MI0 48 + !  0 _MI0 56 + !",
    # Edit menu items (2 × 32 = 64 bytes)
    'CREATE _MI1 64 ALLOT',
    'S" Cut"   _MI1 8 + ! _MI1 !',
    "' _MNP _MI1 16 + !  0 _MI1 24 + !",
    'S" Paste" _MI1 40 + ! _MI1 32 + !',
    "' _MNP _MI1 48 + !  0 _MI1 56 + !",
    # Top-level menus (2 × 32 = 64 bytes)
    'CREATE _MENUS 64 ALLOT',
    'S" File" _MENUS 8 + ! _MENUS !',
    '_MI0 _MENUS 16 + !  2 _MENUS 24 + !',
    'S" Edit" _MENUS 40 + ! _MENUS 32 + !',
    '_MI1 _MENUS 48 + !  2 _MENUS 56 + !',
    # Region and widget
    '0 0 15 40 RGN-NEW',
    'DUP _MENUS 2 MNU-NEW',
]

_MNU_CLEANUP = 'MNU-FREE RGN-FREE SCR-FREE'


def test_mnu_create():
    """MNU-NEW creates a menu widget."""
    print("\n── MENU create ──")
    check("type is WDG-T-MENU",
        _MNU_SETUP + [
         'DUP WDG-TYPE . 8888 .',
         _MNU_CLEANUP], "4 8888")

def test_mnu_initial_state():
    """Active menu is -1, active item is 0."""
    print("\n── MENU initial state ──")
    check("active menu = -1",
        _MNU_SETUP + [
         'DUP MNU-ACTIVE . 8888 .',
         _MNU_CLEANUP], "-1 8888")
    check("active item = 0",
        _MNU_SETUP + [
         'DUP MNU-ACTIVE-ITEM . 8888 .',
         _MNU_CLEANUP], "0 8888")

def test_mnu_open_close():
    """MNU-OPEN opens, MNU-CLOSE closes."""
    print("\n── MENU open/close ──")
    check("open menu 0",
        _MNU_SETUP + [
         '0 OVER MNU-OPEN',
         'DUP MNU-ACTIVE . 8888 .',
         _MNU_CLEANUP], "0 8888")
    check("close after open",
        _MNU_SETUP + [
         '0 OVER MNU-OPEN',
         'DUP MNU-CLOSE',
         'DUP MNU-ACTIVE . 8888 .',
         _MNU_CLEANUP], "-1 8888")

def test_mnu_draw():
    """Draw does not crash."""
    print("\n── MENU draw ──")
    check("draw bar (no dropdown)",
        _MNU_SETUP + [
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         _MNU_CLEANUP], "0 8888")
    check("draw with dropdown open",
        _MNU_SETUP + [
         '0 OVER MNU-OPEN',
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         _MNU_CLEANUP], "0 8888")

def test_mnu_key_down_opens():
    """DOWN key opens first menu when none is open."""
    print("\n── MENU DOWN opens ──")
    check("down opens menu 0",
        _MNU_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE . DUP MNU-ACTIVE . 8888 .',
         _MNU_CLEANUP], "-1 0 8888")

def test_mnu_nav_items():
    """DOWN/UP navigate items in open dropdown."""
    print("\n── MENU nav items ──")
    check("down from item 0 → 1",
        _MNU_SETUP + [
         '0 OVER MNU-OPEN',
         'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP MNU-ACTIVE-ITEM . 8888 .',
         _MNU_CLEANUP], "1 8888")
    check("up from item 1 → 0",
        _MNU_SETUP + [
         '0 OVER MNU-OPEN',
         # Move down first
         'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         # Now move up
         'KEY-T-SPECIAL _EV ! KEY-UP _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP MNU-ACTIVE-ITEM . 8888 .',
         _MNU_CLEANUP], "0 8888")

def test_mnu_enter_fires():
    """ENTER fires action and closes menu."""
    print("\n── MENU ENTER fires ──")
    check("enter fires action, closes menu",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         'VARIABLE _ACTED  0 _ACTED !',
         ': _MACT  1 _ACTED ! ;',
         ': _MNP ;',
         # 2 items: action item + noop
         'CREATE _MI0 64 ALLOT',
         'S" Do" _MI0 8 + ! _MI0 !',
         "' _MACT _MI0 16 + !  0 _MI0 24 + !",
         'S" No" _MI0 40 + ! _MI0 32 + !',
         "' _MNP _MI0 48 + !  0 _MI0 56 + !",
         'CREATE _MENUS 32 ALLOT',
         'S" Act" _MENUS 8 + ! _MENUS !',
         '_MI0 _MENUS 16 + !  2 _MENUS 24 + !',
         '0 0 10 40 RGN-NEW',
         'DUP _MENUS 1 MNU-NEW',
         '0 OVER MNU-OPEN',
         'KEY-T-SPECIAL _EV ! KEY-ENTER _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         '_ACTED @ . DUP MNU-ACTIVE . 8888 .',
         'MNU-FREE RGN-FREE SCR-FREE'], "1 -1 8888")

def test_mnu_esc_closes():
    """ESC closes open dropdown."""
    print("\n── MENU ESC closes ──")
    check("escape closes menu",
        _MNU_SETUP + [
         '0 OVER MNU-OPEN',
         'KEY-T-SPECIAL _EV ! KEY-ESC _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP MNU-ACTIVE . 8888 .',
         _MNU_CLEANUP], "-1 8888")

def test_mnu_left_right():
    """LEFT/RIGHT switch between menus."""
    print("\n── MENU LEFT/RIGHT ──")
    check("right from menu 0 → 1",
        _MNU_SETUP + [
         '0 OVER MNU-OPEN',
         'KEY-T-SPECIAL _EV ! KEY-RIGHT _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP MNU-ACTIVE . 8888 .',
         _MNU_CLEANUP], "1 8888")
    check("left from menu 1 → 0",
        _MNU_SETUP + [
         '1 OVER MNU-OPEN',
         'KEY-T-SPECIAL _EV ! KEY-LEFT _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP MNU-ACTIVE . 8888 .',
         _MNU_CLEANUP], "0 8888")

def test_mnu_item_disable():
    """MNU-ITEM-DISABLE / MNU-ITEM-ENABLE toggle item disabled flag."""
    print("\n── MENU item disable ──")
    check("disable item, skips during nav",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         ': _MNP ;',
         # 3 items: item0 (disabled), item1, item2
         'CREATE _MI0 96 ALLOT',
         'S" AA" _MI0 8 + ! _MI0 !',
         "' _MNP _MI0 16 + !  0 _MI0 24 + !",
         'S" BB" _MI0 40 + ! _MI0 32 + !',
         "' _MNP _MI0 48 + !  0 _MI0 56 + !",
         'S" CC" _MI0 72 + ! _MI0 64 + !',
         "' _MNP _MI0 80 + !  0 _MI0 88 + !",
         'CREATE _MENUS 32 ALLOT',
         'S" Menu" _MENUS 8 + ! _MENUS !',
         '_MI0 _MENUS 16 + !  3 _MENUS 24 + !',
         '0 0 10 40 RGN-NEW',
         'DUP _MENUS 1 MNU-NEW',
         # Disable item 0
         'DUP 0 0 MNU-ITEM-DISABLE',
         '0 OVER MNU-OPEN',
         # Active item should skip item 0 → land on 1
         'DUP MNU-ACTIVE-ITEM . 8888 .',
         'MNU-FREE RGN-FREE SCR-FREE'], "1 8888")

def test_mnu_item_enable():
    """MNU-ITEM-ENABLE re-enables a disabled item."""
    print("\n── MENU item enable ──")
    check("enable re-enables item",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         ': _MNP ;',
         'CREATE _MI0 64 ALLOT',
         'S" AA" _MI0 8 + ! _MI0 !',
         "' _MNP _MI0 16 + !  2 _MI0 24 + !",   # flags=2 (disabled)
         'S" BB" _MI0 40 + ! _MI0 32 + !',
         "' _MNP _MI0 48 + !  0 _MI0 56 + !",
         'CREATE _MENUS 32 ALLOT',
         'S" Menu" _MENUS 8 + ! _MENUS !',
         '_MI0 _MENUS 16 + !  2 _MENUS 24 + !',
         '0 0 10 40 RGN-NEW',
         'DUP _MENUS 1 MNU-NEW',
         # Re-enable item 0
         'DUP 0 0 MNU-ITEM-ENABLE',
         '0 OVER MNU-OPEN',
         # Now item 0 should be selectable
         'DUP MNU-ACTIVE-ITEM . 8888 .',
         'MNU-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_mnu_item_check():
    """MNU-ITEM-CHECK sets checked flag."""
    print("\n── MENU item check ──")
    check("check and draw does not crash",
        _MNU_SETUP + [
         'DUP 0 0 -1 MNU-ITEM-CHECK',
         '0 OVER MNU-OPEN',
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         _MNU_CLEANUP], "0 8888")

def test_mnu_separator():
    """Separator items are skipped during navigation."""
    print("\n── MENU separator ──")
    check("nav skips separator",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         ': _MNP ;',
         # 3 items: item0, separator, item2
         'CREATE _MI0 96 ALLOT',
         'S" AA" _MI0 8 + ! _MI0 !',
         "' _MNP _MI0 16 + !  0 _MI0 24 + !",
         'S" --" _MI0 40 + ! _MI0 32 + !',
         "' _MNP _MI0 48 + !  1 _MI0 56 + !",     # flags=1 (separator)
         'S" BB" _MI0 72 + ! _MI0 64 + !',
         "' _MNP _MI0 80 + !  0 _MI0 88 + !",
         'CREATE _MENUS 32 ALLOT',
         'S" Menu" _MENUS 8 + ! _MENUS !',
         '_MI0 _MENUS 16 + !  3 _MENUS 24 + !',
         '0 0 10 40 RGN-NEW',
         'DUP _MENUS 1 MNU-NEW',
         '0 OVER MNU-OPEN',
         # Down from item 0 → should skip separator → land on item 2
         'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP MNU-ACTIVE-ITEM . 8888 .',
         'MNU-FREE RGN-FREE SCR-FREE'], "2 8888")

def test_mnu_draw_separator():
    """Drawing a menu with separator does not crash."""
    print("\n── MENU draw separator ──")
    check("draw with separator",
        ['24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
         ': _MNP ;',
         'CREATE _MI0 96 ALLOT',
         'S" AA" _MI0 8 + ! _MI0 !',
         "' _MNP _MI0 16 + !  0 _MI0 24 + !",
         'S" --" _MI0 40 + ! _MI0 32 + !',
         "' _MNP _MI0 48 + !  1 _MI0 56 + !",
         'S" BB" _MI0 72 + ! _MI0 64 + !',
         "' _MNP _MI0 80 + !  0 _MI0 88 + !",
         'CREATE _MENUS 32 ALLOT',
         'S" Menu" _MENUS 8 + ! _MENUS !',
         '_MI0 _MENUS 16 + !  3 _MENUS 24 + !',
         '0 0 10 40 RGN-NEW',
         'DUP _MENUS 1 MNU-NEW',
         '0 OVER MNU-OPEN',
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         'MNU-FREE RGN-FREE SCR-FREE'], "0 8888")

def test_mnu_no_consume_when_closed():
    """Keys are not consumed when no menu is open."""
    print("\n── MENU no consume when closed ──")
    check("left not consumed when closed",
        _MNU_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-LEFT _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE . 8888 .',
         _MNU_CLEANUP], "0 8888")
    check("esc not consumed when closed",
        _MNU_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-ESC _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE . 8888 .',
         _MNU_CLEANUP], "0 8888")


# ================================================================
# Dialog tests (Layer 4C)
# ================================================================

_DLG_SETUP = [
    '24 80 SCR-NEW DUP SCR-USE SCR-CLEAR',
    'CREATE _BT 32 ALLOT',
    'S" OK" _BT 8 + ! _BT !',
    'S" Cancel" _BT 24 + ! _BT 16 + !',
    'VARIABLE _RGN',
    '0 0 10 30 RGN-NEW _RGN !',
    'S" Title" S" Hello world" _BT 2 DLG-NEW',
    '_RGN @ OVER DLG-SET-REGION',
]
_DLG_CLEANUP = 'DLG-FREE _RGN @ RGN-FREE SCR-FREE'


def test_dlg_create():
    """DLG-NEW creates a dialog widget."""
    print("\n── DIALOG create ──")
    check("type is WDG-T-DIALOG",
        _DLG_SETUP + [
         'DUP WDG-TYPE . 8888 .',
         _DLG_CLEANUP], "7 8888")


def test_dlg_accessors():
    """DLG-SELECTED, DLG-BTN-COUNT, DLG-RESULT accessors."""
    print("\n── DIALOG accessors ──")
    check("selected = 0",
        _DLG_SETUP + [
         'DUP DLG-SELECTED . 8888 .',
         _DLG_CLEANUP], "0 8888")
    check("btn-count = 2",
        _DLG_SETUP + [
         'DUP DLG-BTN-COUNT . 8888 .',
         _DLG_CLEANUP], "2 8888")
    check("result = -1 initially",
        _DLG_SETUP + [
         'DUP DLG-RESULT . 8888 .',
         _DLG_CLEANUP], "-1 8888")


def test_dlg_draw():
    """Draw does not crash."""
    print("\n── DIALOG draw ──")
    check("draw clears dirty",
        _DLG_SETUP + [
         'DUP WDG-DRAW',
         'DUP WDG-DIRTY? . 8888 .',
         _DLG_CLEANUP], "0 8888")


def test_dlg_nav_left_right():
    """Arrow keys navigate buttons."""
    print("\n── DIALOG left/right ──")
    check("right moves to button 1",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-RIGHT _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-SELECTED . 8888 .',
         _DLG_CLEANUP], "1 8888")
    check("left clamps at 0",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-LEFT _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-SELECTED . 8888 .',
         _DLG_CLEANUP], "0 8888")
    check("right then left → 0",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-RIGHT _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'KEY-T-SPECIAL _EV ! KEY-LEFT _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-SELECTED . 8888 .',
         _DLG_CLEANUP], "0 8888")


def test_dlg_nav_tab():
    """Tab cycles buttons."""
    print("\n── DIALOG tab ──")
    check("tab → button 1",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-TAB _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-SELECTED . 8888 .',
         _DLG_CLEANUP], "1 8888")
    check("tab tab wraps → 0",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-TAB _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'KEY-T-SPECIAL _EV ! KEY-TAB _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-SELECTED . 8888 .',
         _DLG_CLEANUP], "0 8888")


def test_dlg_enter():
    """Enter sets result to selected button."""
    print("\n── DIALOG enter ──")
    check("enter sets result to 0",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-ENTER _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-RESULT . 8888 .',
         _DLG_CLEANUP], "0 8888")
    check("tab then enter sets result to 1",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-TAB _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'KEY-T-SPECIAL _EV ! KEY-ENTER _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-RESULT . 8888 .',
         _DLG_CLEANUP], "1 8888")


def test_dlg_escape():
    """Escape sets result to last button index."""
    print("\n── DIALOG escape ──")
    check("escape sets result to last btn (1)",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-ESC _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE DROP',
         'DUP DLG-RESULT . 8888 .',
         _DLG_CLEANUP], "1 8888")


def test_dlg_consumed():
    """Handle returns correct consumed flag."""
    print("\n── DIALOG consumed ──")
    check("enter consumed",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-ENTER _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE . 8888 .',
         _DLG_CLEANUP], "-1 8888")
    check("unknown key not consumed",
        _DLG_SETUP + [
         'KEY-T-SPECIAL _EV ! KEY-UP _EV 8 + ! 0 _EV 16 + !',
         '_EV OVER WDG-HANDLE . 8888 .',
         _DLG_CLEANUP], "0 8888")


def test_dlg_modal_enter():
    """DLG-SHOW modal loop — Enter selects button 0."""
    print("\n── DIALOG modal enter ──")
    check_modal("DLG-SHOW enter → btn 0",
        ['VARIABLE _SCR',
         '24 80 SCR-NEW DUP _SCR ! DUP SCR-USE SCR-CLEAR',
         'CREATE _MB 16 ALLOT',
         'S" OK" _MB 8 + ! _MB !',
        ],
        'S" Test" S" Hello" _MB 1 DLG-NEW DUP DLG-SHOW . 8888 . DLG-FREE _SCR @ SCR-FREE',
        b'\x0d',   # Enter (CR)
        "0 8888")


def test_dlg_modal_tab_enter():
    """DLG-SHOW modal loop — Tab + Enter selects button 1."""
    print("\n── DIALOG modal tab+enter ──")
    check_modal("DLG-SHOW tab+enter → btn 1",
        ['VARIABLE _SCR',
         '24 80 SCR-NEW DUP _SCR ! DUP SCR-USE SCR-CLEAR',
         'CREATE _MB 32 ALLOT',
         'S" Yes" _MB 8 + ! _MB !',
         'S" No" _MB 24 + ! _MB 16 + !',
        ],
        'S" Pick" S" Choose" _MB 2 DLG-NEW DUP DLG-SHOW . 8888 . DLG-FREE _SCR @ SCR-FREE',
        b'\x09\x0d',   # Tab then Enter
        "1 8888")


def test_dlg_modal_arrow_enter():
    """DLG-SHOW modal loop — Right arrow + Enter selects button 1."""
    print("\n── DIALOG modal arrow+enter ──")
    check_modal("DLG-SHOW arrow+enter → btn 1",
        ['VARIABLE _SCR',
         '24 80 SCR-NEW DUP _SCR ! DUP SCR-USE SCR-CLEAR',
         'CREATE _MB 32 ALLOT',
         'S" Yes" _MB 8 + ! _MB !',
         'S" No" _MB 24 + ! _MB 16 + !',
        ],
        'S" Pick" S" Choose" _MB 2 DLG-NEW DUP DLG-SHOW . 8888 . DLG-FREE _SCR @ SCR-FREE',
        b'\x1b[C\x0d',   # Right arrow then Enter
        "1 8888")


def test_dlg_free():
    """DLG-FREE does not crash."""
    print("\n── DIALOG free ──")
    check("free does not crash",
        _DLG_SETUP + [_DLG_CLEANUP, '8888 .'], "8888")


# =====================================================================
#  Canvas tests (Layer 7 — Braille canvas with per-cell colour)
# =====================================================================

# Setup: create a 10×5 cell region → 20×20 dot canvas
_CVS_SETUP = [
    '24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
    '0 0 5 10 RGN-NEW',
    'DUP CVS-NEW',
]
_CVS_CLEANUP = 'CVS-FREE RGN-FREE SCR-FREE'


def test_cvs_create():
    """CVS-NEW creates a canvas widget with type WDG-T-CANVAS."""
    print("\n── CANVAS create ──")
    check("type is WDG-T-CANVAS (14)",
        _CVS_SETUP + [
            'DUP WDG-TYPE . 8888 .',
            _CVS_CLEANUP], "14 8888")
    check("dot-w = region-w * 2 = 20",
        _CVS_SETUP + [
            'DUP 48 + @ . 8888 .',  # _CVS-O-DW = 48
            _CVS_CLEANUP], "20 8888")
    check("dot-h = region-h * 4 = 20",
        _CVS_SETUP + [
            'DUP 56 + @ . 8888 .',  # _CVS-O-DH = 56
            _CVS_CLEANUP], "20 8888")


def test_cvs_set_get():
    """CVS-SET / CVS-GET set and read individual dots."""
    print("\n── CANVAS set/get ──")
    check("set then get returns true",
        _CVS_SETUP + [
            'DUP 3 4 CVS-SET',
            'DUP 3 4 CVS-GET . 8888 .',
            _CVS_CLEANUP], "-1 8888")
    check("unset dot returns false",
        _CVS_SETUP + [
            'DUP 3 4 CVS-GET . 8888 .',
            _CVS_CLEANUP], "0 8888")


def test_cvs_clr():
    """CVS-CLR clears a previously set dot."""
    print("\n── CANVAS clr ──")
    check("set then clear then get",
        _CVS_SETUP + [
            'DUP 5 2 CVS-SET',
            'DUP 5 2 CVS-CLR',
            'DUP 5 2 CVS-GET . 8888 .',
            _CVS_CLEANUP], "0 8888")


def test_cvs_oob():
    """Out-of-bounds dots are silently ignored."""
    print("\n── CANVAS out-of-bounds ──")
    check("set oob does not crash",
        _CVS_SETUP + [
            'DUP 99 99 CVS-SET',
            'DUP 99 99 CVS-GET . 8888 .',
            _CVS_CLEANUP], "0 8888")


def test_cvs_pen():
    """CVS-PEN! sets pen colour stored in descriptor."""
    print("\n── CANVAS pen ──")
    # After CVS-PEN! with fg=3 bg=1, read them back from descriptor
    check("pen fg/bg stored",
        _CVS_SETUP + [
            'DUP 3 1 CVS-PEN!',
            'DUP 72 + @ .  DUP 80 + @ . 8888 .',  # +72=pen-fg, +80=pen-bg
            _CVS_CLEANUP], "3 1 8888")


def test_cvs_stamp():
    """Setting a dot stamps pen colour into the colour map cell."""
    print("\n── CANVAS stamp ──")
    # col-buf at +64.  Cell (0,0) is first 2 bytes: fg, bg.
    # Default pen is fg=7, bg=0.  Change pen to (2,5) then set dot (0,0).
    check("stamp writes pen to col-buf",
        _CVS_SETUP + [
            'DUP 2 5 CVS-PEN!',
            'DUP 0 0 CVS-SET',                      # stamps cell (0,0)
            'DUP 64 + @  DUP C@ . 1+ C@ . 8888 .',  # read col-buf[0]: fg bg
            _CVS_CLEANUP], "2 5 8888")


def test_cvs_color_direct():
    """CVS-COLOR! sets cell colour directly."""
    print("\n── CANVAS color! ──")
    # CVS-COLOR! ( w col row fg bg -- )
    # Set cell (2, 1) to fg=4, bg=6.  col-buf addr = base + (1*cw + 2)*2
    # cw = 10, so offset = (10 + 2)*2 = 24 bytes into col-buf.
    check("direct colour set",
        _CVS_SETUP + [
            'DUP 2 1 4 6 CVS-COLOR!',
            'DUP 64 + @ 24 +  DUP C@ . 1+ C@ . 8888 .',
            _CVS_CLEANUP], "4 6 8888")


def test_cvs_clear():
    """CVS-CLEAR zeroes all dots and resets colour map to pen."""
    print("\n── CANVAS clear ──")
    check("clear zeroes dots",
        _CVS_SETUP + [
            'DUP 3 3 CVS-SET',
            'DUP CVS-CLEAR',
            'DUP 3 3 CVS-GET . 8888 .',
            _CVS_CLEANUP], "0 8888")
    # After clear, colour map should use current pen
    check("clear resets colours to pen",
        _CVS_SETUP + [
            'DUP 4 2 CVS-PEN!',
            'DUP CVS-CLEAR',
            'DUP 64 + @  DUP C@ . 1+ C@ . 8888 .',   # cell (0,0): fg bg
            _CVS_CLEANUP], "4 2 8888")


def test_cvs_line():
    """CVS-LINE draws a horizontal line (all dots on the line are set)."""
    print("\n── CANVAS line ──")
    check("horizontal line sets dots",
        _CVS_SETUP + [
            'DUP 0 0 5 0 CVS-LINE',
            'DUP 0 0 CVS-GET . DUP 3 0 CVS-GET . DUP 5 0 CVS-GET . 8888 .',
            _CVS_CLEANUP], "-1 -1 -1 8888")
    check("diagonal line sets start and end",
        _CVS_SETUP + [
            'DUP 0 0 4 4 CVS-LINE',
            'DUP 0 0 CVS-GET . DUP 4 4 CVS-GET . 8888 .',
            _CVS_CLEANUP], "-1 -1 8888")


def test_cvs_rect():
    """CVS-RECT draws an outline rectangle."""
    print("\n── CANVAS rect ──")
    # 4×4 rect at (1,1): corners should be set, center should not
    check("rect corners set, center not",
        _CVS_SETUP + [
            'DUP 1 1 4 4 CVS-RECT',
            'DUP 1 1 CVS-GET . DUP 4 4 CVS-GET . DUP 2 2 CVS-GET . 8888 .',
            _CVS_CLEANUP], "-1 -1 0 8888")


def test_cvs_fill_rect():
    """CVS-FILL-RECT fills the entire rectangle."""
    print("\n── CANVAS fill-rect ──")
    check("fill-rect sets interior",
        _CVS_SETUP + [
            'DUP 0 0 3 3 CVS-FILL-RECT',
            'DUP 0 0 CVS-GET . DUP 1 1 CVS-GET . DUP 2 2 CVS-GET . 8888 .',
            _CVS_CLEANUP], "-1 -1 -1 8888")


def test_cvs_circle():
    """CVS-CIRCLE draws a circle (center+radius)."""
    print("\n── CANVAS circle ──")
    # Draw circle at center (8,8) radius 5.
    # Rightmost point = (13,8) must be set (initial octant point).
    check("circle sets rightmost point",
        _CVS_SETUP + [
            'DUP 8 8 5 CVS-CIRCLE',
            'DUP 13 8 CVS-GET . 8888 .',
            _CVS_CLEANUP], "-1 8888")
    # Top point = (8,3) should also be set.
    check("circle sets top point",
        _CVS_SETUP + [
            'DUP 8 8 5 CVS-CIRCLE',
            'DUP 8 3 CVS-GET . 8888 .',
            _CVS_CLEANUP], "-1 8888")
    # Center should NOT be set.
    check("circle center not set",
        _CVS_SETUP + [
            'DUP 8 8 5 CVS-CIRCLE',
            'DUP 8 8 CVS-GET . 8888 .',
            _CVS_CLEANUP], "0 8888")


def test_cvs_draw():
    """WDG-DRAW on canvas does not crash."""
    print("\n── CANVAS draw ──")
    check("draw does not crash",
        _CVS_SETUP + [
            'DUP 3 5 CVS-SET',
            'DUP WDG-DRAW',
            '8888 .',
            _CVS_CLEANUP], "8888")


def test_cvs_handle():
    """Canvas event handler returns 0 (does not consume events)."""
    print("\n── CANVAS handle ──")
    check("handle returns 0",
        _CVS_SETUP + [
            'KEY-T-SPECIAL _EV ! KEY-UP _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE . 8888 .',
            _CVS_CLEANUP], "0 8888")


def test_cvs_free():
    """CVS-FREE does not crash."""
    print("\n── CANVAS free ──")
    check("free does not crash",
        _CVS_SETUP + [
            _CVS_CLEANUP,
            '8888 .'], "8888")


# =====================================================================
#  Tree tests (Layer 7 — Tree View widget)
# =====================================================================

# Build a simple in-memory tree with 4 nodes:
#   Root (1)
#   ├── Child A (2)  -- leaf
#   └── Child B (3)  -- has child
#       └── Grandchild (4) -- leaf
#
# Each node is 4 cells:
#   +0  first-child (or 0)
#   +8  next-sibling (or 0)
#   +16 label-addr
#   +24 label-len
#
# Callback definitions:
#   children-xt ( node -- child|0 )  =  @
#   next-xt     ( node -- sib|0 )    =  8 + @
#   label-xt    ( node -- addr len ) =  DUP 16 + @ SWAP 24 + @
#   leaf?-xt    ( node -- flag )     =  @ 0=

_TREE_SETUP = [
    '24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
    '0 0 10 40 RGN-NEW',
    # Allocate 4 nodes × 4 cells each = 128 bytes
    'CREATE _TN 128 ALLOT',
    # Label strings
    ': _TL-ROOT S" Root" ;',
    ': _TL-A    S" ChildA" ;',
    ': _TL-B    S" ChildB" ;',
    ': _TL-GC   S" Grandchild" ;',
    # Node 1 (Root) at _TN + 0:  child=Node2, next=0, label=Root
    '_TN 32 + _TN !',                            # child → Node2
    '0 _TN 8 + !',                                # next → 0
    '_TL-ROOT _TN 24 + ! _TN 16 + !',            # label (addr, len)
    # Node 2 (ChildA) at _TN + 32:  child=0, next=Node3, label=ChildA
    '0 _TN 32 + !',                               # child → 0 (leaf)
    '_TN 64 + _TN 32 + 8 + !',                    # next → Node3
    '_TL-A _TN 32 + 24 + ! _TN 32 + 16 + !',     # label
    # Node 3 (ChildB) at _TN + 64:  child=Node4, next=0, label=ChildB
    '_TN 96 + _TN 64 + !',                        # child → Node4
    '0 _TN 64 + 8 + !',                           # next → 0
    '_TL-B _TN 64 + 24 + ! _TN 64 + 16 + !',     # label
    # Node 4 (Grandchild) at _TN + 96:  child=0, next=0, label=Grandchild
    '0 _TN 96 + !',                               # child → 0 (leaf)
    '0 _TN 96 + 8 + !',                           # next → 0
    '_TL-GC _TN 96 + 24 + ! _TN 96 + 16 + !',    # label
    # Callbacks
    ': _TC  @ ;',                                  # children-xt
    ': _TN-NEXT  8 + @ ;',                        # next-xt (avoid reuse of _TN)
    ': _TLB DUP 16 + @ SWAP 24 + @ ;',            # label-xt
    ': _TLF @ 0= ;',                              # leaf?-xt
    # Create tree widget
    "DUP _TN  ' _TC  ' _TN-NEXT  ' _TLB  ' _TLF  TREE-NEW",
]
_TREE_CLEANUP = 'TREE-FREE RGN-FREE SCR-FREE'


def test_tree_create():
    """TREE-NEW creates a tree widget with type WDG-T-TREE."""
    print("\n── TREE create ──")
    check("type is WDG-T-TREE (11)",
        _TREE_SETUP + [
            'DUP WDG-TYPE . 8888 .',
            _TREE_CLEANUP], "11 8888")
    check("cursor starts at 0",
        _TREE_SETUP + [
            'DUP 80 + @ . 8888 .',  # _TREE-O-CURSOR = +80
            _TREE_CLEANUP], "0 8888")


def test_tree_vis_count():
    """Initially only root is visible (children not expanded)."""
    print("\n── TREE visible-count ──")
    # Only root is visible at start (nothing expanded)
    check("initial visible count = 1",
        _TREE_SETUP + [
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "1 8888")


def test_tree_expand():
    """TREE-EXPAND expands a non-leaf node, revealing children."""
    print("\n── TREE expand ──")
    # Expand root → should show Root + ChildA + ChildB = 3 rows
    check("expand root → 3 visible",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "3 8888")
    # Expand root + expand ChildB → should show 4 rows
    check("expand root + ChildB → 4 visible",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'DUP _TN 64 + TREE-EXPAND',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "4 8888")


def test_tree_collapse():
    """TREE-COLLAPSE hides children."""
    print("\n── TREE collapse ──")
    check("expand then collapse root → 1 visible",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'DUP _TN TREE-COLLAPSE',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "1 8888")


def test_tree_toggle():
    """TREE-TOGGLE flips expanded state."""
    print("\n── TREE toggle ──")
    check("toggle root (expand) → 3 visible",
        _TREE_SETUP + [
            'DUP _TN TREE-TOGGLE',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "3 8888")
    check("toggle twice (expand then collapse) → 1 visible",
        _TREE_SETUP + [
            'DUP _TN TREE-TOGGLE',
            'DUP _TN TREE-TOGGLE',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "1 8888")


def test_tree_expand_leaf():
    """TREE-EXPAND on a leaf is a no-op (does not crash)."""
    print("\n── TREE expand-leaf ──")
    # Expand root first to make ChildA visible, then try expanding ChildA (leaf)
    check("expand leaf no-op",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'DUP _TN 32 + TREE-EXPAND',   # ChildA is a leaf
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "3 8888")  # still 3, not more


def test_tree_expand_all():
    """TREE-EXPAND-ALL expands everything."""
    print("\n── TREE expand-all ──")
    check("expand-all → 4 visible",
        _TREE_SETUP + [
            'DUP TREE-EXPAND-ALL',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "4 8888")


def test_tree_nav_down():
    """Down key moves cursor."""
    print("\n── TREE nav-down ──")
    # Expand root to have 3 rows, then press down
    check("down moves cursor to 1",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP 80 + @ . 8888 .',   # cursor
            _TREE_CLEANUP], "1 8888")
    check("two downs → cursor 2",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            '_EV OVER WDG-HANDLE DROP',
            'DUP 80 + @ . 8888 .',
            _TREE_CLEANUP], "2 8888")


def test_tree_nav_up():
    """Up key moves cursor."""
    print("\n── TREE nav-up ──")
    check("up from 0 stays at 0",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'KEY-T-SPECIAL _EV ! KEY-UP _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP 80 + @ . 8888 .',
            _TREE_CLEANUP], "0 8888")
    check("down then up back to 0",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'KEY-T-SPECIAL _EV ! KEY-UP _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP 80 + @ . 8888 .',
            _TREE_CLEANUP], "0 8888")


def test_tree_nav_clamp():
    """Down key clamps cursor to last visible row."""
    print("\n── TREE nav-clamp ──")
    # Only 1 visible row (root collapsed), down should stay at 0
    check("clamp at single row",
        _TREE_SETUP + [
            'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP 80 + @ . 8888 .',
            _TREE_CLEANUP], "0 8888")


def test_tree_nav_expand_key():
    """Right key expands node at cursor."""
    print("\n── TREE nav-right-expand ──")
    # Cursor is at row 0 (Root).  Right should expand root.
    check("right key expands root",
        _TREE_SETUP + [
            'KEY-T-SPECIAL _EV ! KEY-RIGHT _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "3 8888")


def test_tree_nav_collapse_key():
    """Left key collapses node at cursor."""
    print("\n── TREE nav-left-collapse ──")
    check("left key collapses root",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'KEY-T-SPECIAL _EV ! KEY-LEFT _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "1 8888")


def test_tree_nav_enter():
    """Enter key toggles expand and fires selection callback."""
    print("\n── TREE nav-enter ──")
    check("enter toggles root expand",
        _TREE_SETUP + [
            'KEY-T-SPECIAL _EV ! KEY-ENTER _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP _TREE-VIS-COUNT . 8888 .',
            _TREE_CLEANUP], "3 8888")


def test_tree_selected():
    """TREE-SELECTED returns the node at cursor."""
    print("\n── TREE selected ──")
    # Root at cursor 0
    check("selected at cursor 0 is root",
        _TREE_SETUP + [
            'DUP TREE-SELECTED _TN = . 8888 .',
            _TREE_CLEANUP], "-1 8888")
    # Expand, move down to cursor 1 → should be ChildA (at _TN + 32)
    check("selected at cursor 1 is ChildA",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'KEY-T-SPECIAL _EV ! KEY-DOWN _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            'DUP TREE-SELECTED _TN 32 + = . 8888 .',
            _TREE_CLEANUP], "-1 8888")


def test_tree_on_select():
    """Selection callback is invoked on Enter."""
    print("\n── TREE on-select ──")
    check("on-select callback fires",
        _TREE_SETUP + [
            'VARIABLE _SEL-FIRED  0 _SEL-FIRED !',
            ": _ONSF  DROP -1 _SEL-FIRED ! ;",
            "DUP ' _ONSF TREE-ON-SELECT",
            'KEY-T-SPECIAL _EV ! KEY-ENTER _EV 8 + ! 0 _EV 16 + !',
            '_EV OVER WDG-HANDLE DROP',
            '_SEL-FIRED @ . 8888 .',
            _TREE_CLEANUP], "-1 8888")


def test_tree_draw():
    """WDG-DRAW on tree does not crash."""
    print("\n── TREE draw ──")
    check("draw does not crash",
        _TREE_SETUP + [
            'DUP _TN TREE-EXPAND',
            'DUP WDG-DRAW',
            '8888 .',
            _TREE_CLEANUP], "8888")


def test_tree_handle_unrelated():
    """Unrelated key is not consumed (returns 0)."""
    print("\n── TREE unrelated key ──")
    check("printable key not consumed",
        _TREE_SETUP + [
            '65 _EV ! 0 _EV 8 + ! 0 _EV 16 + !',   # 'A', not special
            '_EV OVER WDG-HANDLE . 8888 .',
            _TREE_CLEANUP], "0 8888")


def test_tree_free():
    """TREE-FREE does not crash."""
    print("\n── TREE free ──")
    check("free does not crash",
        _TREE_SETUP + [
            _TREE_CLEANUP,
            '8888 .'], "8888")


if __name__ == "__main__":
    build_snapshot()

    # ANSI tests
    test_ansi_cursor()
    test_ansi_clear()
    test_ansi_scroll()
    test_ansi_attributes()
    test_ansi_colors_16()
    test_ansi_colors_256()
    test_ansi_colors_rgb()
    test_ansi_modes()
    test_ansi_queries()
    test_ansi_combo()

    # Keys tests
    test_keys_printable()
    test_keys_special()
    test_keys_ctrl()
    test_keys_arrows()
    test_keys_home_end()
    test_keys_page_ins_del()
    test_keys_fkeys()
    test_keys_shift_tab()
    test_keys_modifiers()
    test_keys_accessors()

    # Cell tests (Layer 1)
    test_cell_pack_unpack()
    test_cell_setters()
    test_cell_blank()
    test_cell_predicates()
    test_cell_has_attr()
    test_cell_edge_cases()

    # Screen tests (Layer 1)
    test_scr_create()
    test_scr_set_get()
    test_scr_clear_fill()
    test_scr_cursor()
    test_scr_flush_basic()
    test_scr_flush_skip_unchanged()
    test_scr_flush_attrs()
    test_scr_flush_color()
    test_scr_flush_cursor_show()
    test_scr_resize()

    # Draw tests (Layer 2)
    test_draw_style()
    test_draw_char()
    test_draw_hline()
    test_draw_vline()
    test_draw_fill_rect()
    test_draw_clear_rect()
    test_draw_text()
    test_draw_text_center()
    test_draw_text_right()
    test_draw_zero_area()

    # Box tests (Layer 2)
    test_box_single()
    test_box_double()
    test_box_ascii()
    test_box_min_size()
    test_box_titled()
    test_box_hline_vline()
    test_box_shadow()

    # Region tests (Layer 3)
    test_rgn_create()
    test_rgn_use_draw()
    test_rgn_root()
    test_rgn_sub()
    test_rgn_contains()
    test_rgn_clip()
    test_rgn_zero_size()
    test_rgn_draw_at_edges()

    # Layout tests (Layer 3)
    test_lay_create()
    test_lay_add()
    test_lay_vertical_fixed()
    test_lay_vertical_gap()
    test_lay_vertical_expand()
    test_lay_horizontal_fixed()
    test_lay_horizontal_gap()
    test_lay_horizontal_expand()
    test_lay_min_size()
    test_lay_offset_parent()
    test_lay_recompute()
    test_lay_empty()

    # Widget tests (Layer 4A)
    test_wdg_type_constants()
    test_wdg_flag_constants()
    test_wdg_header_access()
    test_wdg_flags_ops()

    # Label tests (Layer 4A)
    test_lbl_left()
    test_lbl_center()
    test_lbl_right()
    test_lbl_truncate()
    test_lbl_empty()
    test_lbl_set_text()
    test_lbl_set_align()
    test_lbl_hidden()

    # Progress tests (Layer 4A)
    test_prg_create()
    test_prg_set_pct()
    test_prg_inc()
    test_prg_bar_draw()
    test_prg_bar_max_zero()
    test_prg_spinner()
    test_prg_dirty()

    # Input tests (Layer 4B)
    test_inp_create()
    test_inp_set_get_text()
    test_inp_insert_chars()
    test_inp_backspace()
    test_inp_delete()
    test_inp_cursor_move()
    test_inp_home_end()
    test_inp_cursor_pos()
    test_inp_clear()
    test_inp_capacity()
    test_inp_placeholder()

    # List tests (Layer 4B)
    test_lst_create()
    test_lst_select()
    test_lst_draw()
    test_lst_nav_down_up()
    test_lst_scroll()
    test_lst_set_items()
    test_lst_home_end()
    test_lst_empty()

    # Tabs tests (Layer 4B)
    test_tab_create()
    test_tab_add()
    test_tab_select()
    test_tab_draw()
    test_tab_content()
    test_tab_count()

    # Menu tests (Layer 4C)
    test_mnu_create()
    test_mnu_initial_state()
    test_mnu_open_close()
    test_mnu_draw()
    test_mnu_key_down_opens()
    test_mnu_nav_items()
    test_mnu_enter_fires()
    test_mnu_esc_closes()
    test_mnu_left_right()
    test_mnu_item_disable()
    test_mnu_item_enable()
    test_mnu_item_check()
    test_mnu_separator()
    test_mnu_draw_separator()
    test_mnu_no_consume_when_closed()

    # Dialog tests (Layer 4C)
    test_dlg_create()
    test_dlg_accessors()
    test_dlg_draw()
    test_dlg_nav_left_right()
    test_dlg_nav_tab()
    test_dlg_enter()
    test_dlg_escape()
    test_dlg_consumed()
    test_dlg_modal_enter()
    test_dlg_modal_tab_enter()
    test_dlg_modal_arrow_enter()
    test_dlg_free()

    # Canvas tests (Layer 7)
    test_cvs_create()
    test_cvs_set_get()
    test_cvs_clr()
    test_cvs_oob()
    test_cvs_pen()
    test_cvs_stamp()
    test_cvs_color_direct()
    test_cvs_clear()
    test_cvs_line()
    test_cvs_rect()
    test_cvs_fill_rect()
    test_cvs_circle()
    test_cvs_draw()
    test_cvs_handle()
    test_cvs_free()

    # Tree tests (Layer 7)
    test_tree_create()
    test_tree_vis_count()
    test_tree_expand()
    test_tree_collapse()
    test_tree_toggle()
    test_tree_expand_leaf()
    test_tree_expand_all()
    test_tree_nav_down()
    test_tree_nav_up()
    test_tree_nav_clamp()
    test_tree_nav_expand_key()
    test_tree_nav_collapse_key()
    test_tree_nav_enter()
    test_tree_selected()
    test_tree_on_select()
    test_tree_draw()
    test_tree_handle_unrelated()
    test_tree_free()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)
