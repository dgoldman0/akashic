#!/usr/bin/env python3
"""Test suite for akashic tui/dom-event.f — DOM Event Routing for TUI.

Builds a disk image with the full dependency chain (dom.f, event.f,
dom-tui.f, dom-render.f, keys.f, dom-event.f), boots KDOS, and
exercises focus management, hit-testing, key dispatch, and mouse
dispatch via UART-driven test expressions.
"""
import os
import sys
import struct
import time
import tempfile
import re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Source files
CORE_F    = os.path.join(ROOT_DIR, "akashic", "markup", "core.f")
HTML_F    = os.path.join(ROOT_DIR, "akashic", "markup", "html.f")
CSS_F     = os.path.join(ROOT_DIR, "akashic", "css", "css.f")
BRIDGE_F  = os.path.join(ROOT_DIR, "akashic", "css", "bridge.f")
UTF8_F    = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
STR_F     = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
DOM_F     = os.path.join(ROOT_DIR, "akashic", "dom", "dom.f")
HTML5_F   = os.path.join(ROOT_DIR, "akashic", "dom", "html5.f")
EVENT_F   = os.path.join(ROOT_DIR, "akashic", "dom", "event.f")
CELL_F    = os.path.join(ROOT_DIR, "akashic", "tui", "cell.f")
ANSI_F    = os.path.join(ROOT_DIR, "akashic", "tui", "ansi.f")
SCREEN_F  = os.path.join(ROOT_DIR, "akashic", "tui", "screen.f")
DRAW_F    = os.path.join(ROOT_DIR, "akashic", "tui", "draw.f")
SIDECAR_F = os.path.join(ROOT_DIR, "akashic", "tui", "tui-sidecar.f")
REGION_F  = os.path.join(ROOT_DIR, "akashic", "tui", "region.f")
BOX_F     = os.path.join(ROOT_DIR, "akashic", "tui", "box.f")
DOMTUI_F  = os.path.join(ROOT_DIR, "akashic", "tui", "dom-tui.f")
DOMREN_F  = os.path.join(ROOT_DIR, "akashic", "tui", "dom-render.f")
KEYS_F    = os.path.join(ROOT_DIR, "akashic", "tui", "keys.f")
DOMEVT_F  = os.path.join(ROOT_DIR, "akashic", "tui", "dom-event.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

SECTOR = 512

# ---------------------------------------------------------------------------
#  Disk image builder
# ---------------------------------------------------------------------------

def make_entry(name, start_sec, sec_count, used_bytes, ftype, parent):
    e = bytearray(48)
    name_b = name.encode('ascii')[:24]
    e[:len(name_b)] = name_b
    struct.pack_into('<HH', e, 24, start_sec, sec_count)
    struct.pack_into('<I', e, 28, used_bytes)
    e[32] = ftype
    e[34] = parent
    return bytes(e)

def build_disk_image(files):
    data_start = 14
    entries = []
    data_sectors = []
    next_sec = data_start

    for name, parent, ftype, content in files:
        if ftype == 8:
            entries.append(make_entry(name, 0, 0, 0, 8, parent))
        else:
            content_bytes = content if isinstance(content, bytes) else content.encode('utf-8')
            n_sec = max(1, (len(content_bytes) + SECTOR - 1) // SECTOR)
            entries.append(make_entry(name, next_sec, n_sec,
                                      len(content_bytes), 1, parent))
            padded = content_bytes + b'\x00' * (n_sec * SECTOR - len(content_bytes))
            data_sectors.append((next_sec, padded))
            next_sec += n_sec

    sb = bytearray(SECTOR)
    sb[0:4] = b'MP64'
    struct.pack_into('<H', sb, 4, 1)
    struct.pack_into('<I', sb, 6, 2048)
    struct.pack_into('<H', sb, 10, 1)
    struct.pack_into('<H', sb, 12, 1)
    struct.pack_into('<H', sb, 14, 2)
    struct.pack_into('<H', sb, 16, 12)
    struct.pack_into('<H', sb, 18, 14)
    sb[20] = 128
    sb[21] = 48

    bmap = bytearray(SECTOR)
    for s in range(data_start):
        bmap[s // 8] |= (1 << (s % 8))
    for sec_start, padded in data_sectors:
        n = len(padded) // SECTOR
        for s in range(sec_start, sec_start + n):
            bmap[s // 8] |= (1 << (s % 8))

    dir_data = bytearray(12 * SECTOR)
    for i, e in enumerate(entries):
        dir_data[i * 48 : i * 48 + 48] = e

    total_sectors = max(next_sec, 2048)
    image = bytearray(total_sectors * SECTOR)
    image[0:SECTOR] = sb
    image[SECTOR:2*SECTOR] = bmap
    image[2*SECTOR:14*SECTOR] = dir_data
    for sec_start, padded in data_sectors:
        off = sec_start * SECTOR
        image[off:off + len(padded)] = padded

    return bytes(image)

def read_file_bytes(path):
    with open(path, 'rb') as f:
        return f.read()

# ---------------------------------------------------------------------------
#  Emulator helpers
# ---------------------------------------------------------------------------

_snapshot = None
_img_path = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_kdos_lines(path):
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    if nl == -1:
        return data[pos:]
    return data[pos:nl + 1]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
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

def _feed_and_run(sys_obj, buf, lines, max_steps):
    payload = "\n".join(lines) + "\n"
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
    return steps


def build_snapshot():
    global _snapshot, _img_path
    if _snapshot is not None:
        return _snapshot

    print("[*] Building disk image ...")

    disk_files = [
        # dir idx 0: markup/
        ("markup",   255, 8, b''),
        # idx 1: markup/core.f
        ("core.f",     0, 1, read_file_bytes(CORE_F)),
        # idx 2: markup/html.f
        ("html.f",     0, 1, read_file_bytes(HTML_F)),
        # dir idx 3: css/
        ("css",      255, 8, b''),
        # idx 4: css/css.f
        ("css.f",      3, 1, read_file_bytes(CSS_F)),
        # idx 5: css/bridge.f
        ("bridge.f",   3, 1, read_file_bytes(BRIDGE_F)),
        # dir idx 6: dom/
        ("dom",      255, 8, b''),
        # idx 7: dom/dom.f
        ("dom.f",      6, 1, read_file_bytes(DOM_F)),
        # idx 8: dom/html5.f
        ("html5.f",    6, 1, read_file_bytes(HTML5_F)),
        # idx 9: dom/event.f
        ("event.f",    6, 1, read_file_bytes(EVENT_F)),
        # dir idx 10: utils/
        ("utils",    255, 8, b''),
        # idx 11: utils/string.f
        ("string.f",  10, 1, read_file_bytes(STR_F)),
        # dir idx 12: text/
        ("text",     255, 8, b''),
        # idx 13: text/utf8.f
        ("utf8.f",    12, 1, read_file_bytes(UTF8_F)),
        # dir idx 14: tui/
        ("tui",      255, 8, b''),
        # idx 15: tui/cell.f
        ("cell.f",    14, 1, read_file_bytes(CELL_F)),
        # idx 16: tui/ansi.f
        ("ansi.f",    14, 1, read_file_bytes(ANSI_F)),
        # idx 17: tui/screen.f
        ("screen.f",  14, 1, read_file_bytes(SCREEN_F)),
        # idx 18: tui/draw.f
        ("draw.f",    14, 1, read_file_bytes(DRAW_F)),
        # tui/tui-sidecar.f
        ("tui-sidecar.f", 14, 1, read_file_bytes(SIDECAR_F)),
        # idx 19: tui/region.f
        ("region.f",  14, 1, read_file_bytes(REGION_F)),
        # idx 20: tui/box.f
        ("box.f",     14, 1, read_file_bytes(BOX_F)),
        # idx 21: tui/dom-tui.f
        ("dom-tui.f", 14, 1, read_file_bytes(DOMTUI_F)),
        # idx 22: tui/dom-render.f
        ("dom-render.f", 14, 1, read_file_bytes(DOMREN_F)),
        # idx 23: tui/keys.f
        ("keys.f",    14, 1, read_file_bytes(KEYS_F)),
        # idx 24: tui/dom-event.f
        ("dom-event.f", 14, 1, read_file_bytes(DOMEVT_F)),
    ]

    image = build_disk_image(disk_files)
    _img_path = os.path.join(tempfile.gettempdir(), 'test_tui_dom_event.img')
    with open(_img_path, 'wb') as f:
        f.write(image)
    data_secs = sum(max(1, (len(c)+511)//512)
                    for _,_,t,c in disk_files if t != 8)
    print(f"    {len(image)//1024}KB image, {data_secs} data sectors")

    print("[*] Booting KDOS ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_kdos_lines(KDOS_PATH)

    sys_obj = MegapadSystem(ram_size=1024 * 1024, storage_image=_img_path,
                            ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    steps = _feed_and_run(sys_obj, buf, kdos_lines, 400_000_000)
    elapsed = time.time() - t0
    print(f"    KDOS ready — {steps:,} steps, {elapsed:.1f}s")

    print("[*] REQUIRE dom-event.f from disk ...")
    buf.clear()
    t0 = time.time()

    load_lines = [
        'ENTER-USERLAND',
        'CD tui',
        'REQUIRE dom-tui.f',
        'REQUIRE draw.f',
        'REQUIRE box.f',
        'REQUIRE dom-render.f',
        'REQUIRE keys.f',
        'CD /',
        'CD dom',
        'REQUIRE event.f',
        'CD /',
        'CD tui',
        'REQUIRE dom-event.f',
        'CD /',
        # String-builder helpers (avoid S" buffer clobbering)
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 512 ALLOT  VARIABLE _UL',
        ': UR  0 _UL ! ;',
        ': UC  ( c -- ) _UB _UL @ + C!  1 _UL +! ;',
        ': UA  ( -- addr u ) _UB _UL @ ;',
        # Helper: SET-STYLE ( node c-addr u -- )
        'UR 115 UC 116 UC 121 UC 108 UC 101 UC',
        ': SET-STYLE  ( node val-a val-u -- ) >R >R UA R> R> DOM-ATTR! ;',
        # Helper: SET-TABINDEX ( node -- )
        'CREATE _TI-N 2 ALLOT  48 _TI-N C!',
        'CREATE _TI-K 8 ALLOT',
        ': _TI-KINIT  116 _TI-K C!  97 _TI-K 1+ C!  98 _TI-K 2 + C!',
        '  105 _TI-K 3 + C!  110 _TI-K 4 + C!  100 _TI-K 5 + C!',
        '  101 _TI-K 6 + C!  120 _TI-K 7 + C! ;',
        '_TI-KINIT',
        ': SET-TABINDEX  ( node -- ) _TI-K 8 _TI-N 1 DOM-ATTR! ;',
        # Create test arena, document, screen, region
        '524288 A-XMEM ARENA-NEW DROP CONSTANT _TARN',
        '_TARN 64 64 DOM-DOC-NEW CONSTANT _TDOC',
        'DOM-HTML-INIT',
        '80 24 SCR-NEW CONSTANT _TSCR',
        '_TSCR SCR-USE',
        'SCR-CLEAR',
        '0 0 24 80 RGN-NEW CONSTANT _TRGN',
        # Initialize DOME event system
        '_TDOC DOME-INIT-DEFAULT CONSTANT _TDOM',
        # Initialize event routing
        '_TDOC _TDOM DEVT-INIT',
        # Listener-test sentinel variables
        'VARIABLE _LHIT      0 _LHIT !',
        'VARIABLE _LCODE     0 _LCODE !',
        'VARIABLE _LMODS     0 _LMODS !',
        'VARIABLE _LPHASE    0 _LPHASE !',
        'VARIABLE _LNODE     0 _LNODE !',
        'VARIABLE _LHIT2     0 _LHIT2 !',
        # Generic listener: increments _LHIT, stores detail in _LCODE
        ': _TL-KEY  ( event node -- )',
        '  _LNODE !',
        '  _LHIT @ 1+ _LHIT !',
        '  DUP E.DETAIL @ _LCODE !',
        '  DUP E.DETAIL2 @ _LMODS !',
        '  E.PHASE @ _LPHASE ! ;',
        # Click listener: increments _LHIT2
        ': _TL-CLICK  ( event node -- )',
        '  DROP',
        '  _LHIT2 @ 1+ _LHIT2 ! DROP ;',
        # Key event descriptor (24 bytes: type+code+mods)
        'CREATE _KEV 24 ALLOT',
        ': KE-SET  ( type code mods -- )',
        '  _KEV 16 + !  _KEV 8 + !  _KEV ! ;',
    ]

    steps = _feed_and_run(sys_obj, buf, load_lines, 2_000_000_000)
    load_text = uart_text(buf)
    elapsed = time.time() - t0
    print(f"    Loaded — {steps:,} steps, {elapsed:.1f}s")

    # Verify critical words exist
    buf.clear()
    verify_lines = [
        ': _vfy CR',
        '  [DEFINED] DEVT-INIT      IF ." DI:ok " ELSE ." DI:MISS " THEN',
        '  [DEFINED] DEVT-FOCUS     IF ." DF:ok " ELSE ." DF:MISS " THEN',
        '  [DEFINED] DEVT-DISPATCH  IF ." DD:ok " ELSE ." DD:MISS " THEN',
        '  [DEFINED] DEVT-HIT-TEST  IF ." HT:ok " ELSE ." HT:MISS " THEN',
        '  [DEFINED] DOME-LISTEN    IF ." DL:ok " ELSE ." DL:MISS " THEN',
        '  [DEFINED] DOME-DISPATCH  IF ." DS:ok " ELSE ." DS:MISS " THEN',
        '  [DEFINED] _TDOM          IF ." TD:ok " ELSE ." TD:MISS " THEN',
        '; _vfy',
    ]
    _feed_and_run(sys_obj, buf, verify_lines, 50_000_000)
    vfy_text = uart_text(buf)
    print(f"    Verify: {vfy_text.strip()}")

    load_errs = [l for l in load_text.split('\n')
                 if 'not found' in l.lower() or 'error' in l.lower()
                 or 'abort' in l.lower()]
    if load_errs:
        print("[!] Errors during load:")
        for e in load_errs[-10:]:
            print(f"    {e}")
    else:
        last_lines = [l.strip() for l in load_text.split('\n') if l.strip()]
        print(f"    Last output: {last_lines[-3:]}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print("[*] Snapshot ready.")
    return _snapshot


def run_forth(lines, max_steps=200_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024,
                            ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    lines_with_bye = lines + ['BYE']
    steps = _feed_and_run(sys_obj, buf, lines_with_bye, max_steps)
    return uart_text(buf)


def tstr(s):
    """Build string in test buffer _TB using TR/TC."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp < 1:
            sp = 70
        lines.append(full[:sp])
        full = full[sp+1:]
    if full:
        lines.append(full)
    return lines


# ---------------------------------------------------------------------------
#  Test harness
# ---------------------------------------------------------------------------

_results = []

def check(name, lines, expected=None, check_fn=None):
    """Run Forth lines and verify output."""
    build_snapshot()
    out = run_forth(lines)
    out_lines = [l.strip() for l in out.replace('\r', '').split('\n')]

    ok = False
    if check_fn:
        ok = check_fn(out)
    elif expected is not None:
        ok = expected in out
    else:
        ok = True

    status = "PASS" if ok else "FAIL"
    _results.append((name, ok))
    print(f"  {status}  {name}")
    if not ok:
        if check_fn:
            print(f"        check_fn failed")
        else:
            print(f"        expected: {expected!r}")
        print(f"        got (last 5): {out_lines[-5:]}")

# ---------------------------------------------------------------------------
#  Helpers: DOM construction
# ---------------------------------------------------------------------------

def _mk_el(varname, tag, style=None):
    """Return lines to create an element with optional style."""
    lines = tstr(tag)
    lines.append(f'TA DOM-CREATE-ELEMENT CONSTANT {varname}')
    if style:
        lines += tstr(style)
        lines.append(f'{varname} TA SET-STYLE')
    return lines

def _mk_div(varname, style=None):
    return _mk_el(varname, 'div', style)

def _mk_button(varname, style=None):
    return _mk_el(varname, 'button', style)

def _mk_input(varname, style=None):
    return _mk_el(varname, 'input', style)

def _mk_text(varname, text):
    lines = tstr(text)
    lines.append(f'TA DOM-CREATE-TEXT CONSTANT {varname}')
    return lines

def _append(child, parent):
    return [f'{child} {parent} DOM-APPEND']

def _tabindex(node):
    return [f'{node} SET-TABINDEX']

def _attach_and_layout():
    return [
        '_TDOC DTUI-ATTACH',
        '_TDOC _TRGN DREN-LAYOUT',
    ]

def _reset_sentinels():
    return [
        '0 _LHIT !  0 _LCODE !  0 _LMODS !  0 _LPHASE !  0 _LNODE !',
        '0 _LHIT2 !',
    ]


# ---------------------------------------------------------------------------
#  Tests
# ---------------------------------------------------------------------------

def run_tests():
    # ==================================================================
    print("\n=== Load Check ===")
    # ==================================================================

    check("dom-event.f loads without error",
        [': t CR ." [OK]" ; t'],
        '[OK]')

    # ==================================================================
    print("\n=== Focus Management ===")
    # ==================================================================

    check("DEVT-FOCUS starts at 0",
        [': t  DEVT-FOCUS',
         '  CR ." [F=" . ." ]" ; t'],
        '[F=0 ]')

    # Focus a button (natively focusable)
    check("DEVT-FOCUS! sets focus",
        _mk_button('_B1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  _B1 DEVT-FOCUS!',
         '  DEVT-FOCUS _B1 =',
         '  CR ." [EQ=" . ." ]" ; t'],
        '[EQ=-1 ]')

    # Focus same node twice — should be no-op
    check("DEVT-FOCUS! same node is no-op",
        _mk_button('_B1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  _B1 DEVT-FOCUS!  _B1 DEVT-FOCUS!',
         '  DEVT-FOCUS _B1 =',
         '  CR ." [EQ=" . ." ]" ; t'],
        '[EQ=-1 ]')

    # ==================================================================
    print("\n=== Focus Events (blur/focus) ===")
    # ==================================================================

    # Focus a button — should fire focus event
    check("DEVT-FOCUS! fires focus event",
        _mk_button('_B1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        # Register focus listener on button
        ['_TDOM DOME-USE',
         "_B1  DOME-TI-FOCUS DOME-TYPE@  ' _TL-KEY  DOME-LISTEN",
         '_B1 DEVT-FOCUS!',
         ': t  CR ." [H=" _LHIT @ . ." ]" ; t'],
        '[H=1 ]')

    # Focus switch: blur old, focus new
    check("Focus switch fires blur then focus",
        _mk_button('_B1') +
        _mk_button('_B2') +
        _append('_B1', 'DOM-BODY') +
        _append('_B2', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         'VARIABLE _BLUR-HIT  0 _BLUR-HIT !',
         ': _TL-BLUR  ( event node -- ) 2DROP  _BLUR-HIT @ 1+ _BLUR-HIT ! ;',
         "_B1  DOME-TI-BLUR  DOME-TYPE@  ' _TL-BLUR  DOME-LISTEN",
         "_B2  DOME-TI-FOCUS DOME-TYPE@  ' _TL-KEY   DOME-LISTEN",
         '_B1 DEVT-FOCUS!',
         '0 _LHIT !',         # reset after focusing B1
         '_B2 DEVT-FOCUS!',
         ': t  CR ." [BL=" _BLUR-HIT @ . ." FO=" _LHIT @ . ." ]" ; t'],
        '[BL=1 FO=1 ]')

    # ==================================================================
    print("\n=== Focus Traversal (Tab Cycling) ===")
    # ==================================================================

    # 3 focusable elements: Tab cycles through them
    check("DEVT-FOCUS-NEXT cycles forward",
        _mk_button('_B1') +
        _mk_button('_B2') +
        _mk_button('_B3') +
        _append('_B1', 'DOM-BODY') +
        _append('_B2', 'DOM-BODY') +
        _append('_B3', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  DEVT-FOCUS-NEXT',   # → B1
         '  DEVT-FOCUS _B1 = >R',
         '  DEVT-FOCUS-NEXT',       # → B2
         '  DEVT-FOCUS _B2 = >R',
         '  DEVT-FOCUS-NEXT',       # → B3
         '  DEVT-FOCUS _B3 = >R',
         '  DEVT-FOCUS-NEXT',       # → B1 (wrap)
         '  DEVT-FOCUS _B1 =',
         '  R> R> R>',
         '  CR ." [" . . . . ." ]"',
         '; t'],
        '[-1 -1 -1 -1 ]')

    check("DEVT-FOCUS-PREV cycles backward",
        _mk_button('_B1') +
        _mk_button('_B2') +
        _mk_button('_B3') +
        _append('_B1', 'DOM-BODY') +
        _append('_B2', 'DOM-BODY') +
        _append('_B3', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  DEVT-FOCUS-PREV',   # → B3 (wraps to last)
         '  DEVT-FOCUS _B3 = >R',
         '  DEVT-FOCUS-PREV',       # → B2
         '  DEVT-FOCUS _B2 = >R',
         '  DEVT-FOCUS-PREV',       # → B1
         '  DEVT-FOCUS _B1 =',
         '  R> R>',
         '  CR ." [" . . . ." ]"',
         '; t'],
        '[-1 -1 -1 ]')

    # Div with tabindex is also focusable
    check("Div with tabindex is focusable",
        _mk_div('_D1') +
        _tabindex('_D1') +
        _mk_button('_B1') +
        _append('_D1', 'DOM-BODY') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  DEVT-FOCUS-NEXT',   # → D1
         '  DEVT-FOCUS _D1 = >R',
         '  DEVT-FOCUS-NEXT',       # → B1
         '  DEVT-FOCUS _B1 =',
         '  R>',
         '  CR ." [" . . ." ]"',
         '; t'],
        '[-1 -1 ]')

    # ==================================================================
    print("\n=== Hit Testing ===")
    # ==================================================================

    # Single div at (0,0) with w=80, h=1
    check("Hit-test: inside single div",
        _mk_div('_D1') +
        _append('_D1', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  0 0 DEVT-HIT-TEST _D1 =',
         '  CR ." [EQ=" . ." ]" ; t'],
        '[EQ=-1 ]')

    check("Hit-test: outside returns 0",
        _mk_div('_D1') +
        _append('_D1', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  10 0 DEVT-HIT-TEST',
         '  CR ." [HT=" . ." ]" ; t'],
        '[HT=0 ]')

    # Nested: child at specific position
    check("Hit-test: nested child found",
        _mk_div('_D1', 'height:5') +
        _mk_div('_D2', 'width:10;height:3') +
        _append('_D2', '_D1') +
        _append('_D1', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  1 3 DEVT-HIT-TEST _D2 =',
         '  CR ." [EQ=" . ." ]" ; t'],
        '[EQ=-1 ]')

    # Hit parent area outside child
    check("Hit-test: parent area outside child",
        _mk_div('_D1', 'height:5') +
        _mk_div('_D2', 'width:10;height:3') +
        _append('_D2', '_D1') +
        _append('_D1', 'DOM-BODY') +
        _attach_and_layout() +
        [': t  4 50 DEVT-HIT-TEST _D1 =',
         '  CR ." [EQ=" . ." ]" ; t'],
        '[EQ=-1 ]')

    # ==================================================================
    print("\n=== Key Event Dispatch ===")
    # ==================================================================

    # Dispatch a char key to focused button
    check("Key dispatch: char 'A' to focused node",
        _mk_button('_B1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         "_B1  DOME-TI-KEYDOWN DOME-TYPE@  ' _TL-KEY  DOME-LISTEN",
         '_B1 DEVT-FOCUS!',
         '0 _LHIT !',
         # Build key event: type=KEY-T-CHAR(0), code=65('A'), mods=0
         'KEY-T-CHAR 65 0 KE-SET',
         '_KEV DEVT-DISPATCH DROP',
         ': t  CR ." [H=" _LHIT @ .',
         '  ." C=" _LCODE @ .',
         '  ." ]" ; t'],
        '[H=1 C=65 ]')

    # Char key also fires keypress
    check("Char key fires keypress after keydown",
        _mk_button('_B1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         'VARIABLE _KP-HIT  0 _KP-HIT !',
         ': _TL-KP  ( event node -- ) 2DROP _KP-HIT @ 1+ _KP-HIT ! ;',
         "_B1  DOME-TI-KEYPRESS DOME-TYPE@  ' _TL-KP  DOME-LISTEN",
         '_B1 DEVT-FOCUS!',
         'KEY-T-CHAR 65 0 KE-SET',
         '_KEV DEVT-DISPATCH DROP',
         ': t  CR ." [KP=" _KP-HIT @ . ." ]" ; t'],
        '[KP=1 ]')

    # Special key (arrow) — no keypress
    check("Special key: no keypress fired",
        _mk_button('_B1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         'VARIABLE _KP-HIT  0 _KP-HIT !',
         ': _TL-KP  ( event node -- ) 2DROP _KP-HIT @ 1+ _KP-HIT ! ;',
         "_B1  DOME-TI-KEYDOWN  DOME-TYPE@  ' _TL-KEY  DOME-LISTEN",
         "_B1  DOME-TI-KEYPRESS DOME-TYPE@  ' _TL-KP   DOME-LISTEN",
         '_B1 DEVT-FOCUS!',
         '0 _LHIT !',
         'KEY-T-SPECIAL KEY-UP 0 KE-SET',
         '_KEV DEVT-DISPATCH DROP',
         ': t  CR ." [KD=" _LHIT @ . ." KP=" _KP-HIT @ . ." ]" ; t'],
        '[KD=1 KP=0 ]')

    # Tab key → focus cycles, no keydown dispatched
    check("Tab key: focus cycles, no keydown event",
        _mk_button('_B1') +
        _mk_button('_B2') +
        _append('_B1', 'DOM-BODY') +
        _append('_B2', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         "_B1  DOME-TI-KEYDOWN DOME-TYPE@  ' _TL-KEY  DOME-LISTEN",
         "_B2  DOME-TI-KEYDOWN DOME-TYPE@  ' _TL-KEY  DOME-LISTEN",
         # Tab → should focus B1 (first DEVT-FOCUS-NEXT from no focus)
         'KEY-T-SPECIAL KEY-TAB 0 KE-SET',
         '_KEV DEVT-DISPATCH DROP',
         ': t  CR ." [F=" DEVT-FOCUS _B1 = .',
         '  ." H=" _LHIT @ . ." ]" ; t'],
        '[F=-1 H=0 ]')

    # Shift-Tab → DEVT-FOCUS-PREV
    check("Shift-Tab: focus cycles backward",
        _mk_button('_B1') +
        _mk_button('_B2') +
        _mk_button('_B3') +
        _append('_B1', 'DOM-BODY') +
        _append('_B2', 'DOM-BODY') +
        _append('_B3', 'DOM-BODY') +
        _attach_and_layout() +
        # Shift-Tab: no current focus → FOCUS-PREV → wraps to B3
        ['KEY-T-SPECIAL KEY-TAB KEY-MOD-SHIFT KE-SET',
         '_KEV DEVT-DISPATCH DROP',
         ': t  CR ." [F=" DEVT-FOCUS _B3 = . ." ]" ; t'],
        '[F=-1 ]')

    # Key dispatch to body when no focus
    check("Key dispatch: target=body when no focus",
        _mk_div('_D1') +
        _append('_D1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         "DOM-BODY  DOME-TI-KEYDOWN DOME-TYPE@  ' _TL-KEY  DOME-LISTEN",
         'KEY-T-CHAR 66 0 KE-SET',     # 'B'
         '_KEV DEVT-DISPATCH DROP',
         ': t  CR ." [H=" _LHIT @ . ." C=" _LCODE @ . ." ]" ; t'],
        '[H=1 C=66 ]')

    # ==================================================================
    print("\n=== Mouse Event Dispatch ===")
    # ==================================================================

    # Click on button → fires mousedown + click
    check("Mouse click on button fires click",
        _mk_button('_B1', 'width:20;height:3') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         "_B1  DOME-TI-CLICK DOME-TYPE@  ' _TL-CLICK  DOME-LISTEN",
         '1 5 0 DEVT-DISPATCH-MOUSE DROP',   # row=1, col=5, button=left
         ': t  CR ." [CL=" _LHIT2 @ . ." ]" ; t'],
        '[CL=1 ]')

    # Click on focusable element → auto-focuses
    check("Mouse click auto-focuses clicked button",
        _mk_button('_B1', 'width:20;height:3') +
        _mk_button('_B2', 'width:20;height:3') +
        _append('_B1', 'DOM-BODY') +
        _append('_B2', 'DOM-BODY') +
        _attach_and_layout() +
        ['_B1 DEVT-FOCUS!',   # start focused on B1
         # Click B2 (at row=3..5, col=0..19)
         '3 5 0 DEVT-DISPATCH-MOUSE DROP',
         ': t  CR ." [F=" DEVT-FOCUS _B2 = . ." ]" ; t'],
        '[F=-1 ]')

    # Click on empty space → miss, returns 0
    check("Mouse click on empty space: no dispatch",
        _mk_button('_B1', 'width:10;height:1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         "_B1  DOME-TI-CLICK DOME-TYPE@  ' _TL-CLICK  DOME-LISTEN",
         '10 50 0 DEVT-DISPATCH-MOUSE',   # way outside
         ': t  CR ." [RET=" . ." CL=" _LHIT2 @ . ." ]" ; t'],
        '[RET=0 CL=0 ]')

    # ==================================================================
    print("\n=== Modifier Passthrough ===")
    # ==================================================================

    # Key with Ctrl modifier
    check("Keydown carries modifier flags",
        _mk_button('_B1') +
        _append('_B1', 'DOM-BODY') +
        _attach_and_layout() +
        _reset_sentinels() +
        ['_TDOM DOME-USE',
         "_B1  DOME-TI-KEYDOWN DOME-TYPE@  ' _TL-KEY  DOME-LISTEN",
         '_B1 DEVT-FOCUS!',
         '0 _LHIT !  0 _LMODS !',
         'KEY-T-CHAR 99 KEY-MOD-CTRL KE-SET',   # Ctrl-c
         '_KEV DEVT-DISPATCH DROP',
         ': t  CR ." [M=" _LMODS @ . ." ]" ; t'],
        '[M=4 ]')    # KEY-MOD-CTRL = 4

    # ==================================================================
    print("\n=== Summary ===")
    # ==================================================================
    total = len(_results)
    passed = sum(1 for _, ok in _results if ok)
    failed = total - passed
    print(f"\n{passed}/{total} tests passed")
    if failed:
        print("FAILURES:")
        for name, ok in _results:
            if not ok:
                print(f"  - {name}")
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    sys.exit(run_tests())
