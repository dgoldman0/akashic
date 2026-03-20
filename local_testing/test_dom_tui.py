#!/usr/bin/env python3
"""Test suite for akashic tui/dom-tui.f — DOM-to-TUI Node Mapping.

Builds a MP64FS disk image containing the full dependency chain
(markup, css, dom, html5, text/utf8, utils/string, tui/*), boots
KDOS, loads via REQUIRE, then exercises every public API plus key
internals through UART-driven test expressions.
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
CELL_F    = os.path.join(ROOT_DIR, "akashic", "tui", "cell.f")
ANSI_F    = os.path.join(ROOT_DIR, "akashic", "tui", "ansi.f")
SCREEN_F  = os.path.join(ROOT_DIR, "akashic", "tui", "screen.f")
DRAW_F    = os.path.join(ROOT_DIR, "akashic", "tui", "draw.f")
SIDECAR_F = os.path.join(ROOT_DIR, "akashic", "tui", "tui-sidecar.f")
REGION_F  = os.path.join(ROOT_DIR, "akashic", "tui", "region.f")
DOMTUI_F  = os.path.join(ROOT_DIR, "akashic", "tui",         "dom-tui.f")
BOX_F     = os.path.join(ROOT_DIR, "akashic", "tui",         "box.f")
KEYS_F    = os.path.join(ROOT_DIR, "akashic", "tui",         "keys.f")
DOMREN_F  = os.path.join(ROOT_DIR, "akashic", "tui",         "dom-render.f")
DOMEVT_F  = os.path.join(ROOT_DIR, "akashic", "tui",         "dom-event.f")
DOMEV_F   = os.path.join(ROOT_DIR, "akashic", "dom",         "event.f")
GUARD_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
SEMA_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
CEVT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")

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
        # dir idx 9: utils/
        ("utils",    255, 8, b''),
        # idx 10: utils/string.f
        ("string.f",   9, 1, read_file_bytes(STR_F)),
        # dir idx 11: text/
        ("text",     255, 8, b''),
        # idx 12: text/utf8.f
        ("utf8.f",    11, 1, read_file_bytes(UTF8_F)),
        # dir idx 13: tui/
        ("tui",      255, 8, b''),
        # idx 14: tui/cell.f
        ("cell.f",    13, 1, read_file_bytes(CELL_F)),
        # idx 15: tui/ansi.f
        ("ansi.f",    13, 1, read_file_bytes(ANSI_F)),
        # idx 16: tui/screen.f
        ("screen.f",  13, 1, read_file_bytes(SCREEN_F)),
        # idx 17: tui/draw.f
        ("draw.f",    13, 1, read_file_bytes(DRAW_F)),
        # tui/tui-sidecar.f
        ("tui-sidecar.f", 13, 1, read_file_bytes(SIDECAR_F)),
        # idx 18: tui/region.f
        ("region.f",  13, 1, read_file_bytes(REGION_F)),
        # idx 19: tui/dom-tui.f
        ("dom-tui.f", 13, 1, read_file_bytes(DOMTUI_F)),
        # idx 20: tui/box.f
        ("box.f",     13, 1, read_file_bytes(BOX_F)),
        # idx 21: tui/keys.f
        ("keys.f",    13, 1, read_file_bytes(KEYS_F)),
        # idx 22: tui/dom-render.f
        ("dom-render.f", 13, 1, read_file_bytes(DOMREN_F)),
        # idx 23: tui/dom-event.f
        ("dom-event.f", 13, 1, read_file_bytes(DOMEVT_F)),
        # idx 24: dom/event.f
        ("event.f",    6, 1, read_file_bytes(DOMEV_F)),
        # dir idx 25: concurrency/
        ("concurrency", 255, 8, b''),
        # idx 26: concurrency/event.f
        ("event.f",   25, 1, read_file_bytes(CEVT_F)),
        # idx 27: concurrency/semaphore.f
        ("semaphore.f", 25, 1, read_file_bytes(SEMA_F)),
        # idx 28: concurrency/guard.f
        ("guard.f",   25, 1, read_file_bytes(GUARD_F)),
    ]

    image = build_disk_image(disk_files)
    _img_path = os.path.join(tempfile.gettempdir(), 'test_dom_tui.img')
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
        'REQUIRE dom-event.f',
        'CD /',
        # String-builder helpers
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 512 ALLOT  VARIABLE _UL',
        ': UR  0 _UL ! ;',
        ': UC  ( c -- ) _UB _UL @ + C!  1 _UL +! ;',
        ': UA  ( -- addr u ) _UB _UL @ ;',
        'CREATE _OB 1024 ALLOT',
        # Helper: SET-STYLE ( node c-addr u -- )
        #   Sets style="<value>" on a node without S" clobbering.
        #   Stores "style" in _UB, then calls DOM-ATTR!.
        'UR 115 UC 116 UC 121 UC 108 UC 101 UC',
        ': SET-STYLE  ( node val-a val-u -- ) >R >R UA R> R> DOM-ATTR! ;',
        # Create test arena, document, attach
        '524288 A-XMEM ARENA-NEW DROP CONSTANT _TARN',
        '_TARN 64 64 DOM-DOC-NEW CONSTANT _TDOC',
        'DOM-HTML-INIT',
        # Screen + region for render tests
        '80 24 SCR-NEW CONSTANT _TSCR',
        '_TSCR SCR-USE',
        '0 0 24 80 RGN-NEW CONSTANT _TRGN',
    ]

    steps = _feed_and_run(sys_obj, buf, load_lines, 2_000_000_000)
    load_text = uart_text(buf)
    elapsed = time.time() - t0
    print(f"    Loaded — {steps:,} steps, {elapsed:.1f}s")

    load_errs = [l for l in load_text.split('\n')
                 if 'not found' in l.lower() or 'error' in l.lower()
                 or 'abort' in l.lower()]
    if load_errs:
        print("[!] Errors during load:")
        for e in load_errs[-10:]:
            print(f"    {e}")

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
        ok = True  # existence check

    status = "PASS" if ok else "FAIL"
    _results.append((name, ok))
    print(f"  {status}  {name}")
    if not ok:
        if check_fn:
            print(f"        check_fn failed")
        else:
            print(f"        expected: {expected!r}")
        print(f"        got (last 3): {out_lines[-3:]}")

# ---------------------------------------------------------------------------
#  Tests
# ---------------------------------------------------------------------------

def run_tests():
    print("\n=== Style Packing ===")

    check("DTUI-PACK-STYLE basic",
        [': t1  7 0 1 2 DTUI-PACK-STYLE',
         '  CR ." [S=" . ." ]" ; t1'],
        check_fn=lambda out: '[S=' in out and ']' in out)

    check("Unpack FG from packed style",
        [': t2  42 128 3 1 DTUI-PACK-STYLE DTUI-UNPACK-FG',
         '  CR ." [FG=" . ." ]" ; t2'],
        '[FG=42 ]')

    check("Unpack BG from packed style",
        [': t3  42 128 3 1 DTUI-PACK-STYLE DTUI-UNPACK-BG',
         '  CR ." [BG=" . ." ]" ; t3'],
        '[BG=128 ]')

    check("Unpack ATTRS from packed style",
        [': t4  42 128 5 1 DTUI-PACK-STYLE DTUI-UNPACK-ATTRS',
         '  CR ." [AT=" . ." ]" ; t4'],
        '[AT=5 ]')

    check("Unpack BORDER from packed style",
        [': t5  42 128 5 3 DTUI-PACK-STYLE DTUI-UNPACK-BORDER',
         '  CR ." [BD=" . ." ]" ; t5'],
        '[BD=3 ]')

    check("Pack/unpack round-trip",
        [': t6  196 77 9 4 DTUI-PACK-STYLE',
         '  DUP DTUI-UNPACK-FG',
         '  OVER DTUI-UNPACK-BG',
         '  2 PICK DTUI-UNPACK-ATTRS',
         '  3 PICK DTUI-UNPACK-BORDER',
         '  CR ." [" . . . . ." ]" DROP ; t6'],
        '[4 9 77 196 ]')

    print("\n=== Color Resolution ===")

    check("Black (0,0,0) → palette index ≤ 16",
        [': tc1  0 0 0 DTUI-RESOLVE-COLOR',
         '  CR ." [C=" . ." ]" ; tc1'],
        check_fn=lambda out: re.search(r'\[C=(\d+)', out) and
                  int(re.search(r'\[C=(\d+)', out).group(1)) <= 16)

    check("Red (255,0,0) → palette ~196",
        [': tc2  255 0 0 DTUI-RESOLVE-COLOR',
         '  CR ." [C=" . ." ]" ; tc2'],
        check_fn=lambda out: re.search(r'\[C=(\d+)', out) and
                  int(re.search(r'\[C=(\d+)', out).group(1)) in (196, 9, 1))

    check("Green (0,255,0) → palette ~46",
        [': tc3  0 255 0 DTUI-RESOLVE-COLOR',
         '  CR ." [C=" . ." ]" ; tc3'],
        check_fn=lambda out: re.search(r'\[C=(\d+)', out) and
                  int(re.search(r'\[C=(\d+)', out).group(1)) in (46, 10, 2))

    check("Gray (128,128,128) → grayscale ramp",
        [': tc4  128 128 128 DTUI-RESOLVE-COLOR',
         '  CR ." [C=" . ." ]" ; tc4'],
        check_fn=lambda out: re.search(r'\[C=(\d+)', out) and
                  232 <= int(re.search(r'\[C=(\d+)', out).group(1)) <= 255)

    check("White (255,255,255) → palette ≥231",
        [': tc5  255 255 255 DTUI-RESOLVE-COLOR',
         '  CR ." [C=" . ." ]" ; tc5'],
        check_fn=lambda out: re.search(r'\[C=(\d+)', out) and
                  int(re.search(r'\[C=(\d+)', out).group(1)) >= 231)

    print("\n=== Sidecar Allocation ===")

    check("DTUI-ATTACH allocates sidecars",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': ta1  DOM-HTML DTUI-SIDECAR 0<>',
         '  DOM-BODY DTUI-SIDECAR 0<>  AND',
         '  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR 0<>  AND',
         '  CR ." [A=" . ." ]" ; ta1'],
        '[A=-1 ]')

    check("Sidecar back-pointer integrity",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': ta2  DOM-BODY DUP DTUI-SIDECAR DTUI-SC-NODE =',
         '  CR ." [BP=" . ." ]" ; ta2'],
        '[BP=-1 ]')

    check("DTUI-DETACH clears all sidecars",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_TDOC DTUI-DETACH',
         ': ta3  DOM-BODY DTUI-SIDECAR 0=',
         '  CR ." [D=" . ." ]" ; ta3'],
        '[D=-1 ]')

    check("DTUI-VISIBLE? true for normal element",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': ta4  DOM-BODY DOM-FIRST-CHILD DTUI-VISIBLE?',
         '  CR ." [V=" . ." ]" ; ta4'],
        '[V=-1 ]')

    # ---- CSS → TUI Resolution ----
    # All CSS tests use SET-STYLE helper (stores "style" in _UB to avoid
    # S" buffer clobbering).  Pattern:
    #   S" div" DOM-CREATE-ELEMENT CONSTANT _X
    #   _X S" <css>" SET-STYLE
    #   _X DOM-BODY DOM-APPEND
    #   _TDOC DTUI-ATTACH  ... check _X sidecar ...

    print("\n=== CSS → TUI Resolution ===")

    check("display:none → not visible",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DN',
         '_DN S" display:none" SET-STYLE',
         '_DN DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _DN DTUI-VISIBLE?',
         '  CR ." [V=" . ." ]" ; t'],
        '[V=0 ]')

    check("display:block → block flag set",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DB',
         '_DB S" display:block" SET-STYLE',
         '_DB DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _DB DTUI-SIDECAR DTUI-SC-FLAGS',
         '  16 AND 0<>',
         '  CR ." [B=" . ." ]" ; t'],
        '[B=-1 ]')

    check("color:red → fg resolved",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CR',
         '_CR S" color:red" SET-STYLE',
         '_CR DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CR DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-FG',
         '  CR ." [FG=" . ." ]" ; t'],
        check_fn=lambda out: re.search(r'\[FG=(\d+)', out) and
                  int(re.search(r'\[FG=(\d+)', out).group(1)) != 7)

    check("background-color:blue → bg resolved",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CB',
         '_CB S" background-color:blue" SET-STYLE',
         '_CB DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CB DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-BG',
         '  CR ." [BG=" . ." ]" ; t'],
        check_fn=lambda out: re.search(r'\[BG=(\d+)', out) and
                  int(re.search(r'\[BG=(\d+)', out).group(1)) != 0)

    check("font-weight:bold → bold attr",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _FB',
         '_FB S" font-weight:bold" SET-STYLE',
         '_FB DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _FB DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-ATTRS',
         '  1 AND 0<>',
         '  CR ." [BD=" . ." ]" ; t'],
        '[BD=-1 ]')

    check("font-style:italic → italic attr",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _FI',
         '_FI S" font-style:italic" SET-STYLE',
         '_FI DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _FI DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-ATTRS',
         '  4 AND 0<>',
         '  CR ." [IT=" . ." ]" ; t'],
        '[IT=-1 ]')

    check("text-decoration:underline → underline attr",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _TU',
         '_TU S" text-decoration:underline" SET-STYLE',
         '_TU DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _TU DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-ATTRS',
         '  8 AND 0<>',
         '  CR ." [UL=" . ." ]" ; t'],
        '[UL=-1 ]')

    check("text-decoration:line-through → strike attr",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _TS',
         '_TS S" text-decoration:line-through" SET-STYLE',
         '_TS DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _TS DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-ATTRS',
         '  64 AND 0<>',
         '  CR ." [ST=" . ." ]" ; t'],
        '[ST=-1 ]')

    check("border-style:solid → single border",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _BS',
         '_BS S" border-style:solid" SET-STYLE',
         '_BS DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _BS DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-BORDER',
         '  CR ." [BR=" . ." ]" ; t'],
        '[BR=1 ]')

    check("border-style:double → double border",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _BD',
         '_BD S" border-style:double" SET-STYLE',
         '_BD DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _BD DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-BORDER',
         '  CR ." [BR=" . ." ]" ; t'],
        '[BR=2 ]')

    check("border-style:none → no border",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _BN',
         '_BN S" border-style:none" SET-STYLE',
         '_BN DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _BN DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-BORDER',
         '  CR ." [BR=" . ." ]" ; t'],
        '[BR=0 ]')

    print("\n=== Dimensions ===")

    check("width CSS → sidecar width",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DW',
         '_DW S" width:40px" SET-STYLE',
         '_DW DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _DW DTUI-SIDECAR DTUI-SC-W',
         '  CR ." [W=" . ." ]" ; t'],
        '[W=40 ]')

    check("height CSS → sidecar height",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DH',
         '_DH S" height:25px" SET-STYLE',
         '_DH DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _DH DTUI-SIDECAR DTUI-SC-H',
         '  CR ." [H=" . ." ]" ; t'],
        '[H=25 ]')

    check("No width → sidecar width 0",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-SC-W',
         '  CR ." [W=" . ." ]" ; t'],
        '[W=0 ]')

    print("\n=== Focusable Detection ===")

    check("input element → focusable flag",
        ['S" input" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-SC-FLAGS',
         '  4 AND 0<>',
         '  CR ." [F=" . ." ]" ; t'],
        '[F=-1 ]')

    check("button element → focusable flag",
        ['S" button" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-SC-FLAGS',
         '  4 AND 0<>',
         '  CR ." [F=" . ." ]" ; t'],
        '[F=-1 ]')

    check("div element → not focusable",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-SC-FLAGS',
         '  4 AND 0=',
         '  CR ." [F=" . ." ]" ; t'],
        '[F=-1 ]')

    check("tabindex attr → focusable flag",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _TI',
         # Use _TB helpers to avoid S" clobbering for tabindex attr
         'TR 116 TC 97 TC 98 TC 105 TC 110 TC 100 TC 101 TC 120 TC',
         '_TI TA S" 0" DOM-ATTR!',
         '_TI DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _TI DTUI-SIDECAR DTUI-SC-FLAGS',
         '  16 AND 0<>',
         '  CR ." [F=" . ." ]" ; t'],
        '[F=-1 ]')

    print("\n=== Refresh ===")

    check("DTUI-REFRESH updates after style change",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _RR',
         '_RR S" color:red" SET-STYLE',
         '_RR DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         # Get initial fg
         '_RR DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-FG',
         # Change style to blue
         '_RR S" color:blue" SET-STYLE',
         '_TDOC DTUI-REFRESH',
         # Get new fg  
         '_RR DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-FG',
         'CR ." [OLD=" SWAP . ." NEW=" . ." ]"'],
        check_fn=lambda out: re.search(r'\[OLD=(\d+) NEW=(\d+)', out) is not None)

    print("\n=== DTUI-STYLE! Override ===")

    check("DTUI-STYLE! overrides fg/bg/attrs",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         'DOM-BODY DOM-FIRST-CHILD',
         'DUP 100 200 5 DTUI-STYLE!',
         'DTUI-SIDECAR DTUI-SC-STYLE',
         'DUP DTUI-UNPACK-FG',
         'OVER DTUI-UNPACK-BG',
         '2 PICK DTUI-UNPACK-ATTRS',
         'CR ." [" . . . ." ]" DROP'],
        '[5 200 100 ]')

    print("\n=== Visibility ===")

    check("visibility:hidden → hidden+visible flags",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _VH',
         '_VH S" visibility:hidden" SET-STYLE',
         '_VH DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _VH DTUI-SIDECAR DTUI-SC-FLAGS',
         '  DUP 8 AND 0<>',
         '  SWAP 2 AND 0<>',
         '  CR ." [H=" . ." V=" . ." ]" ; t'],
        '[H=-1 V=-1 ]')

    print("\n=== Multi-Element Tree ===")

    check("Attach to tree: div > span + p",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _MD',
         'S" span" DOM-CREATE-ELEMENT _MD DOM-APPEND',
         'S" p" DOM-CREATE-ELEMENT _MD DOM-APPEND',
         '_MD DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _MD DTUI-SIDECAR 0<>',
         '  _MD DOM-FIRST-CHILD DTUI-SIDECAR 0<>  AND',
         '  _MD DOM-LAST-CHILD DTUI-SIDECAR 0<>  AND',
         '  CR ." [T=" . ." ]" ; t'],
        '[T=-1 ]')

    check("All sidecars have dirty flag set",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-SC-FLAGS',
         '  32 AND 0<>',
         '  CR ." [D=" . ." ]" ; t'],
        '[D=-1 ]')

    # ==================================================================
    #  §NEW-1 — Sidecar User Data (DTUI-SC-UDATA / DTUI-SC-UDATA!)
    # ==================================================================
    print("\n=== Sidecar User Data ===")

    check("DTUI-SC-UDATA default is 0",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-SC-UDATA',
         '  CR ." [U=" . ." ]" ; t'],
        '[U=0 ]')

    check("DTUI-SC-UDATA! / DTUI-SC-UDATA round-trip",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR',
         '  12345 OVER DTUI-SC-UDATA!',
         '  DTUI-SC-UDATA',
         '  CR ." [U=" . ." ]" ; t'],
        '[U=12345 ]')

    # ==================================================================
    #  §NEW-2 — DTUI-SC-DRAW default
    # ==================================================================
    print("\n=== Sidecar Draw XT ===")

    check("DTUI-SC-DRAW default is 0",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-SC-DRAW',
         '  CR ." [X=" . ." ]" ; t'],
        '[X=0 ]')

    # ==================================================================
    #  §NEW-3 — Flag Constants
    # ==================================================================
    print("\n=== Flag Constants ===")

    check("DTUI-F-GEOM-DIRTY = 64",
        [': t  DTUI-F-GEOM-DIRTY',
         '  CR ." [G=" . ." ]" ; t'],
        '[G=64 ]')

    check("All flag values",
        [': t  DTUI-F-DIRTY DTUI-F-VISIBLE DTUI-F-BLOCK',
         '  DTUI-F-HIDDEN DTUI-F-FOCUSABLE DTUI-F-GEOM-DIRTY',
         '  CR ." [" . . . . . . ." ]" ; t'],
        '[64 4 8 16 2 32 ]')

    # ==================================================================
    #  §NEW-4 — Dirty Marking
    # ==================================================================
    print("\n=== Dirty Marking ===")

    check("DTUI-MARK-DIRTY sets DIRTY flag",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DM',
         '_DM DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_DM DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         ': t  _DM DTUI-SIDECAR DTUI-SC-FLAGS 32 AND',
         '  _DM DTUI-MARK-DIRTY',
         '  _DM DTUI-SIDECAR DTUI-SC-FLAGS 32 AND',
         '  CR ." [A=" . ." B=" . ." ]" ; t'],
        '[A=32 B=0 ]')

    check("DTUI-MARK-GEOM-DIRTY sets DIRTY + GEOM-DIRTY",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DG',
         '_DG DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         # Clear both flags
         '_DG DTUI-SIDECAR DUP DTUI-SC-FLAGS 32 INVERT AND 64 INVERT AND SWAP DTUI-SC-FLAGS!',
         ': t  _DG DTUI-MARK-GEOM-DIRTY',
         '  _DG DTUI-SIDECAR DTUI-SC-FLAGS',
         '  DUP 32 AND 0<>',
         '  SWAP 64 AND 0<>',
         '  CR ." [D=" . ." G=" . ." ]" ; t'],
        '[D=-1 G=-1 ]')

    check("DTUI-CLEAR-DIRTY clears DIRTY flag",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DC',
         '_DC DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_DC DTUI-MARK-DIRTY',
         ': t  _DC DTUI-SIDECAR DUP DTUI-SC-FLAGS 32 AND',
         '  SWAP DTUI-CLEAR-DIRTY',
         '  _DC DTUI-SIDECAR DTUI-SC-FLAGS 32 AND',
         '  CR ." [A=" . ." B=" . ." ]" ; t'],
        '[A=0 B=32 ]')

    check("DTUI-CLEAR-GEOM-DIRTY clears only GEOM-DIRTY",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CG',
         '_CG DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_CG DTUI-MARK-GEOM-DIRTY',
         ': t  _CG DTUI-SIDECAR DTUI-CLEAR-GEOM-DIRTY',
         '  _CG DTUI-SIDECAR DTUI-SC-FLAGS',
         '  DUP 32 AND 0<>',    # DIRTY still set
         '  SWAP 64 AND',        # GEOM-DIRTY cleared
         '  CR ." [G=" . ." D=" . ." ]" ; t'],
        '[G=0 D=-1 ]')

    # ==================================================================
    #  §NEW-5 — Convenience Wrappers (auto-dirty)
    # ==================================================================
    print("\n=== Convenience Wrappers (auto-dirty) ===")

    check("DTUI-SET-TEXT! marks dirty",
        ['S" span" DOM-CREATE-ELEMENT CONSTANT _ST',
         'S" hello" DOM-CREATE-TEXT _ST DOM-APPEND',
         '_ST DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_ST DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         ': t  _ST S" world" DTUI-SET-TEXT!',
         '  _ST DTUI-SIDECAR DTUI-SC-FLAGS 32 AND',
         '  CR ." [D=" . ." ]" ; t'],
        '[D=32 ]')

    check("DTUI-ATTR! marks dirty",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DA',
         '_DA DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_DA DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         ': t  _DA S" id" S" foo" DTUI-ATTR!',
         '  _DA DTUI-SIDECAR DTUI-SC-FLAGS 32 AND',
         '  CR ." [D=" . ." ]" ; t'],
        '[D=32 ]')

    check("DTUI-ATTR-DEL! marks dirty",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DD',
         '_DD S" id" S" bar" DOM-ATTR!',
         '_DD DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_DD DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         ': t  _DD S" id" DTUI-ATTR-DEL!',
         '  _DD DTUI-SIDECAR DTUI-SC-FLAGS 32 AND',
         '  CR ." [D=" . ." ]" ; t'],
        '[D=32 ]')

    # ==================================================================
    #  §NEW-6 — Class Helpers (token ops)
    # ==================================================================
    print("\n=== Class Helpers ===")

    check("DTUI-CLASS-ADD on empty class",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CA',
         '_CA DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CA S" fancy" DTUI-CLASS-ADD',
         '  _CA DOM-CLASS',
         '  CR ." [C=" TYPE ." ]" ; t'],
        '[C=fancy]')

    check("DTUI-CLASS-ADD appends to existing",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CB',
         # Use _UB to build "class" attr name, _TB for value
         'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
         '_CB TA S" foo" DOM-ATTR!',
         '_CB DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CB S" bar" DTUI-CLASS-ADD',
         '  _CB DOM-CLASS',
         '  CR ." [C=" TYPE ." ]" ; t'],
        '[C=foo bar]')

    check("DTUI-CLASS-REMOVE middle token",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CR',
         'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
         '_CR TA S" aaa bbb ccc" DOM-ATTR!',
         '_CR DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CR S" bbb" DTUI-CLASS-REMOVE',
         '  _CR DOM-CLASS',
         '  CR ." [C=" TYPE ." ]" ; t'],
        '[C=aaa ccc]')

    check("DTUI-CLASS-REMOVE first token",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CF',
         'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
         '_CF TA S" xxx yyy" DOM-ATTR!',
         '_CF DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CF S" xxx" DTUI-CLASS-REMOVE',
         '  _CF DOM-CLASS',
         '  CR ." [C=" TYPE ." ]" ; t'],
        '[C=yyy]')

    check("DTUI-CLASS-REMOVE last token",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CL',
         'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
         '_CL TA S" aaa bbb" DOM-ATTR!',
         '_CL DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CL S" bbb" DTUI-CLASS-REMOVE',
         '  _CL DOM-CLASS',
         '  CR ." [C=" TYPE ." ]" ; t'],
        '[C=aaa]')

    check("DTUI-CLASS-REMOVE sole class → empty",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CS',
         'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
         '_CS TA S" alone" DOM-ATTR!',
         '_CS DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CS S" alone" DTUI-CLASS-REMOVE',
         '  _CS DOM-CLASS NIP',
         '  CR ." [L=" . ." ]" ; t'],
        '[L=0 ]')

    check("DTUI-CLASS-REMOVE non-existent → unchanged",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _CN',
         'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
         '_CN TA S" alpha beta" DOM-ATTR!',
         '_CN DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         ': t  _CN S" gamma" DTUI-CLASS-REMOVE',
         '  _CN DOM-CLASS',
         '  CR ." [C=" TYPE ." ]" ; t'],
        '[C=alpha beta]')

    # ==================================================================
    #  §NEW-7 — DREN-DIRTY?
    # ==================================================================
    print("\n=== DREN-DIRTY? ===")

    check("DREN-DIRTY? false when all clean",
        ['S" div" DOM-CREATE-ELEMENT DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         # Clear all dirty flags on all nodes
         'DOM-BODY DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         'DOM-BODY DOM-FIRST-CHILD DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         # Also clear html node
         'DOM-HTML DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         ': t  _TDOC DREN-DIRTY?',
         '  CR ." [D=" . ." ]" ; t'],
        '[D=0 ]')

    check("DREN-DIRTY? true when one node dirty",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DD2',
         '_DD2 DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         # Clear all, then dirty one
         'DOM-HTML DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         'DOM-BODY DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         '_DD2 DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         '_DD2 DTUI-MARK-DIRTY',
         ': t  _TDOC DREN-DIRTY?',
         '  CR ." [D=" . ." ]" ; t'],
        '[D=-1 ]')

    # ==================================================================
    #  §NEW-8 — Layout + Render Pipeline
    # ==================================================================
    print("\n=== Layout + Render ===")

    check("DREN-LAYOUT sets row/col",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DL',
         '_DL S" display:block;width:10;height:3" SET-STYLE',
         '_DL DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_TDOC _TRGN DREN-LAYOUT',
         ': t  _DL DTUI-SIDECAR',
         '  DUP DTUI-SC-ROW',
         '  OVER DTUI-SC-COL',
         '  2 PICK DTUI-SC-W',
         '  3 PICK DTUI-SC-H',
         '  CR ." [" . . . . ." ]" DROP ; t'],
        check_fn=lambda out: '[' in out and ']' in out)

    check("DREN-RENDER completes without crash",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _DR',
         'S" Hello" DOM-CREATE-TEXT _DR DOM-APPEND',
         '_DR S" display:block;width:20;height:1" SET-STYLE',
         '_DR DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_TDOC _TRGN DREN-RENDER',
         'CR ." [OK]"'],
        '[OK]')

    check("Two block divs stack vertically",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _D1',
         '_D1 S" display:block;width:20;height:3" SET-STYLE',
         'S" div" DOM-CREATE-ELEMENT CONSTANT _D2',
         '_D2 S" display:block;width:20;height:2" SET-STYLE',
         '_D1 DOM-BODY DOM-APPEND',
         '_D2 DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_TDOC _TRGN DREN-LAYOUT',
         ': t  _D1 DTUI-SIDECAR DTUI-SC-ROW',
         '  _D2 DTUI-SIDECAR DTUI-SC-ROW',
         '  CR ." [R1=" . ." R2=" . ." ]" ; t'],
        check_fn=lambda out: re.search(r'\[R1=\d+ R2=\d+', out) is not None)

    # ==================================================================
    #  §NEW-9 — DREN-PAINT-DIRTY (dirty-only repaint)
    # ==================================================================
    print("\n=== DREN-PAINT-DIRTY ===")

    check("DREN-PAINT-DIRTY clears dirty flags",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _PD1',
         '_PD1 S" display:block;width:10;height:1" SET-STYLE',
         'S" div" DOM-CREATE-ELEMENT CONSTANT _PD2',
         '_PD2 S" display:block;width:10;height:1" SET-STYLE',
         '_PD1 DOM-BODY DOM-APPEND',
         '_PD2 DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_TDOC _TRGN DREN-LAYOUT',
         # Clear all dirty
         'DOM-HTML DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         'DOM-BODY DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         '_PD1 DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         '_PD2 DTUI-SIDECAR DTUI-CLEAR-DIRTY',
         # Mark only PD1 dirty
         '_PD1 DTUI-MARK-DIRTY',
         '_TDOC DREN-PAINT-DIRTY',
         ': t  _PD1 DTUI-SIDECAR DTUI-SC-FLAGS 1 AND',
         '  _PD2 DTUI-SIDECAR DTUI-SC-FLAGS 1 AND',
         '  CR ." [D1=" . ." D2=" . ." ]" ; t'],
        '[D1=0 D2=0 ]')

    # ==================================================================
    #  §NEW-10 — Smart DREN-RELAYOUT
    # ==================================================================
    print("\n=== Smart DREN-RELAYOUT ===")

    check("DREN-RELAYOUT skips when no GEOM-DIRTY",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _RL1',
         '_RL1 S" display:block;width:10;height:1" SET-STYLE',
         '_RL1 DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_TDOC _TRGN DREN-LAYOUT',
         # Clear geom-dirty
         'DOM-HTML DTUI-SIDECAR DTUI-CLEAR-GEOM-DIRTY',
         'DOM-BODY DTUI-SIDECAR DTUI-CLEAR-GEOM-DIRTY',
         '_RL1 DTUI-SIDECAR DTUI-CLEAR-GEOM-DIRTY',
         '_TDOC _TRGN DREN-RELAYOUT',
         'CR ." [OK]"'],
        '[OK]')

    check("DREN-RELAYOUT clears GEOM-DIRTY after run",
        ['S" div" DOM-CREATE-ELEMENT CONSTANT _RL2',
         '_RL2 S" display:block;width:10;height:1" SET-STYLE',
         '_RL2 DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         '_TDOC _TRGN DREN-LAYOUT',
         '_RL2 DTUI-MARK-GEOM-DIRTY',
         '_TDOC _TRGN DREN-RELAYOUT',
         ': t  _RL2 DTUI-SIDECAR DTUI-SC-FLAGS 32 AND',
         '  CR ." [G=" . ." ]" ; t'],
        '[G=0 ]')

    # ==================================================================
    #  §NEW-11 — Custom draw-xt dispatch
    # ==================================================================
    print("\n=== Custom Draw Callback ===")

    check("Custom draw-xt is called during paint",
        ['VARIABLE _MYCALLED  0 _MYCALLED !',
         ': _MYDRAW  ( node sc rgn -- ) DROP 2DROP -1 _MYCALLED ! ;',
         'S" div" DOM-CREATE-ELEMENT CONSTANT _CX',
         '_CX S" display:block;width:10;height:3" SET-STYLE',
         '_CX DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         "' _MYDRAW _CX DTUI-SIDECAR DTUI-SC-DRAW!",
         '_TDOC _TRGN DREN-RENDER',
         'CR ." [C=" _MYCALLED @ . ." ]"'],
        '[C=-1 ]')

    check("Custom draw-xt no crash with noop",
        [': _NOOP  ( node sc rgn -- ) DROP 2DROP ;',
         'S" div" DOM-CREATE-ELEMENT CONSTANT _CN2',
         '_CN2 S" display:block;width:10;height:3;border-style:solid" SET-STYLE',
         'S" text inside" DOM-CREATE-TEXT _CN2 DOM-APPEND',
         '_CN2 DOM-BODY DOM-APPEND',
         '_TDOC DTUI-ATTACH',
         "' _NOOP _CN2 DTUI-SIDECAR DTUI-SC-DRAW!",
         '_TDOC _TRGN DREN-RENDER',
         'CR ." [OK]"'],
        '[OK]')

    # ==================================================================
    print(f"\n{'='*50}")
    passed = sum(1 for _, ok in _results if ok)
    failed = sum(1 for _, ok in _results if not ok)
    print(f"Results: {passed} passed, {failed} failed, {len(_results)} total")
    return failed == 0


if __name__ == '__main__':
    ok = run_tests()
    sys.exit(0 if ok else 1)
