#!/usr/bin/env python3
"""Test suite for akashic-tui Layer 0 + Layer 1.

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
    print("[*] Building snapshot: BIOS + KDOS + utf8 + ansi + keys + cell + screen ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    utf8_lines = _load_forth_lines(UTF8_F)
    ansi_lines = _load_forth_lines(ANSI_F)
    keys_lines = _load_forth_lines(KEYS_F)
    cell_lines = _load_forth_lines(CELL_F)
    screen_lines = _load_forth_lines(SCREEN_F)

    # Event buffer for key tests (3 cells = 24 bytes)
    helpers = ['CREATE _EV 24 ALLOT']

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    payload = "\n".join(
        kdos_lines + ["ENTER-USERLAND"] +
        utf8_lines + ansi_lines + keys_lines +
        cell_lines + screen_lines + helpers
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
#  Main
# =====================================================================

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

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)
