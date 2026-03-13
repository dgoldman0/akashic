#!/usr/bin/env python3
"""Test suite for akashic-tui-uidl-tui (UIDL TUI Backend).

Uses the Megapad-64 emulator to boot KDOS, load the full dependency chain
(string → markup → state-tree → lel → uidl → uidl-chrome → TUI stack →
uidl-tui), then exercises the public API.
"""
import os
import sys
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

# Full topological dependency order (REQUIRE/PROVIDED stripped by loader)
_DEP_PATHS = [
    os.path.join(AK, "concurrency", "event.f"),
    os.path.join(AK, "concurrency", "semaphore.f"),
    os.path.join(AK, "concurrency", "guard.f"),
    os.path.join(AK, "utils",       "string.f"),
    os.path.join(AK, "math",        "fp32.f"),
    os.path.join(AK, "math",        "fixed.f"),
    os.path.join(AK, "text",        "utf8.f"),
    os.path.join(AK, "markup",      "core.f"),
    os.path.join(AK, "markup",      "xml.f"),
    os.path.join(AK, "liraq",       "state-tree.f"),
    os.path.join(AK, "liraq",       "lel.f"),
    os.path.join(AK, "liraq",       "uidl.f"),
    os.path.join(AK, "liraq",       "uidl-chrome.f"),
    os.path.join(AK, "tui",         "cell.f"),
    os.path.join(AK, "tui",         "ansi.f"),
    os.path.join(AK, "tui",         "screen.f"),
    os.path.join(AK, "tui",         "draw.f"),
    os.path.join(AK, "tui",         "box.f"),
    os.path.join(AK, "tui",         "region.f"),
    os.path.join(AK, "tui",         "layout.f"),
    os.path.join(AK, "tui",         "keys.f"),
    os.path.join(AK, "tui",         "uidl-tui.f"),
]

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers  (same pattern as test_state_tree.py)
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
            if s.startswith('REQUIRE '):
                continue
            if s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data: bytes, pos: int) -> bytes:
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


def build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + full TUI stack ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    # Load all deps in topo order
    dep_lines = []
    for p in _DEP_PATHS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        dep_lines.extend(_load_forth_lines(p))

    # Test helper words loaded into snapshot
    test_helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 512 ALLOT',
        'CREATE _WB 4096 ALLOT',
        # Region helper: push a 80×24 region
        'VARIABLE _RGN_SLOT',
        ': T-RGN  0 0 24 80 RGN-NEW _RGN_SLOT ! ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines + test_helpers
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
    err_lines = [l for l in text.strip().split('\n') if '?' in l]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-30:]:
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

    return uart_text(buf)


# ═══════════════════════════════════════════════════════════════════
#  Test framework
# ═══════════════════════════════════════════════════════════════════

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected=None, check_fn=None, not_expected=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
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


# ═══════════════════════════════════════════════════════════════════
#  XML test documents
# ═══════════════════════════════════════════════════════════════════

# Minimal doc: a region with a label child
_XML_MINIMAL = '<uidl><region><label text="Hello"/></region></uidl>'

# Doc with focusable elements: action + input + toggle
_XML_FOCUS = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label text="Title"/>'
    '  <action id="btn1" text="Click Me" do="on-btn"/>'
    '  <input  id="inp1" text=""/>'
    '  <toggle id="tog1" text="false"/>'
    '  <action id="btn2" text="Other"   do="on-other"/>'
    '</region>'
    '</uidl>'
)

# Split layout doc
_XML_SPLIT = (
    '<uidl>'
    '<split ratio="40">'
    '  <region><label text="Left"/></region>'
    '  <region><label text="Right"/></region>'
    '</split>'
    '</uidl>'
)

# Dialog doc
_XML_DIALOG = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label text="Main"/>'
    '  <dialog id="dlg1">'
    '    <label text="Dialog Body"/>'
    '    <action id="dlg-ok" text="OK" do="close-dlg"/>'
    '  </dialog>'
    '</region>'
    '</uidl>'
)

# Shortcut doc
_XML_SHORTCUT = (
    '<uidl>'
    '<region arrange="stack">'
    '  <action id="save-btn" text="Save" key="Ctrl+S" do="on-save"/>'
    '  <action id="quit-btn" text="Quit" key="Alt+Q"  do="on-quit"/>'
    '</region>'
    '</uidl>'
)


def _xml_lines(xml_str, extra_before=None, extra_after=None):
    """Build Forth lines that load an XML string and call UTUI-LOAD."""
    out = []
    out.append('T-RGN')
    if extra_before:
        out.extend(extra_before)
    # Build XML in _TB using TC
    out.append('TR')
    for ch in xml_str:
        out.append(f'{ord(ch)} TC')
    out.append(f'TA _RGN_SLOT @ UTUI-LOAD')
    if extra_after:
        out.extend(extra_after)
    return out


# ═══════════════════════════════════════════════════════════════════
#  §A — Compilation & Snapshot Tests
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    """All libraries compile without error."""
    check("compile-clean", [
        '." COMPILE-OK" CR',
    ], "COMPILE-OK")


# ═══════════════════════════════════════════════════════════════════
#  §B — Load / Parse Tests
# ═══════════════════════════════════════════════════════════════════

def test_load_minimal():
    """UTUI-LOAD parses minimal XML and returns true."""
    check("load-minimal-flag", _xml_lines(_XML_MINIMAL, extra_after=[
        'IF ." LOAD-OK" ELSE ." LOAD-FAIL" THEN CR',
    ]), "LOAD-OK")

def test_load_sets_loaded():
    """After UTUI-LOAD, the DOC-LOADED flag is set."""
    check("load-sets-loaded", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        '_UTUI-DOC-LOADED @ 0<> IF ." LOADED" ELSE ." NOT" THEN CR',
    ]), "LOADED")

def test_load_bad_xml():
    """UTUI-LOAD with bad XML returns false."""
    check("load-bad-xml", [
        'T-RGN',
        'TR 60 TC 98 TC 97 TC 100 TC',  # "<bad" — incomplete
        'TA _RGN_SLOT @ UTUI-LOAD',
        'IF ." LOAD-OK" ELSE ." LOAD-FAIL" THEN CR',
    ], "LOAD-FAIL")


# ═══════════════════════════════════════════════════════════════════
#  §C — Sidecar Allocation Tests
# ═══════════════════════════════════════════════════════════════════

def test_sidecar_allocation():
    """After load, root element has a sidecar with visible flags."""
    check("sidecar-root-vis", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        'UIDL-ROOT _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        'DUP _UTUI-SCF-HAS AND 0<> IF ." HAS" ELSE ." NO-HAS" THEN CR',
        '_UTUI-SCF-VIS AND 0<> IF ." VIS" ELSE ." NO-VIS" THEN CR',
    ]), check_fn=lambda o: "HAS" in o and "VIS" in o)

def test_sidecar_dimensions():
    """Root sidecar gets region dimensions (80×24)."""
    check("sidecar-root-dims", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        'UIDL-ROOT _UTUI-SIDECAR',
        'DUP _UTUI-SC-W@ . CR',
        '_UTUI-SC-H@ . CR',
    ]), check_fn=lambda o: "80" in o and "24" in o)


# ═══════════════════════════════════════════════════════════════════
#  §D — Focus Management Tests
# ═══════════════════════════════════════════════════════════════════

def test_focus_initial():
    """UTUI-LOAD auto-focuses the first focusable element (action btn1)."""
    check("focus-initial", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP ." no-id" THEN',
        'ELSE ." none" THEN CR',
    ]), "btn1")

def test_focus_next():
    """UTUI-FOCUS-NEXT cycles through focusable elements."""
    check("focus-next-cycle", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        # Focus is on btn1 after load. Step through.
        'UTUI-FOCUS-NEXT',  # → inp1
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
        'UTUI-FOCUS-NEXT',  # → tog1
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
        'UTUI-FOCUS-NEXT',  # → btn2
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
    ]), check_fn=lambda o: "inp1" in o and "tog1" in o and "btn2" in o)

def test_focus_prev():
    """UTUI-FOCUS-PREV cycles backwards."""
    check("focus-prev-cycle", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        # Focus is on btn1 after load.
        'UTUI-FOCUS-PREV',  # → btn2 (wraps)
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
    ]), "btn2")

def test_focus_explicit():
    """UTUI-FOCUS! sets focus directly."""
    check("focus-explicit-set", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'S" tog1" UTUI-BY-ID DUP 0<> IF',
        '  UTUI-FOCUS!',
        '  UTUI-FOCUS UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." not-found" THEN CR',
    ]), "tog1")


# ═══════════════════════════════════════════════════════════════════
#  §E — Action Dispatch Tests
# ═══════════════════════════════════════════════════════════════════

def test_action_register_fire():
    """UTUI-DO! registers an action; _UTUI-FIRE-DO fires it."""
    check("action-fire", _xml_lines(_XML_FOCUS, extra_before=[
        'VARIABLE _ACT-HIT',
        ': _ON-BTN  DROP 1 _ACT-HIT ! ;',
        "S\" on-btn\" ['] _ON-BTN UTUI-DO!",
    ], extra_after=[
        'DROP',
        # Focus is btn1, which has do="on-btn".  Fire it.
        'UTUI-FOCUS _UTUI-FIRE-DO',
        '_ACT-HIT @ . CR',
    ]), "1")


# ═══════════════════════════════════════════════════════════════════
#  §F — Shortcut Parsing Tests
# ═══════════════════════════════════════════════════════════════════

def test_shortcut_parse_single():
    """_UTUI-PARSE-KEY-DESC parses single char."""
    check("shortcut-parse-single-char", [
        'S" S" _UTUI-PARSE-KEY-DESC',
        'SWAP . . CR',
    ], check_fn=lambda o: str(ord('S')) in o and "0" in o)

def test_shortcut_parse_ctrl():
    """_UTUI-PARSE-KEY-DESC parses Ctrl+S."""
    check("shortcut-parse-ctrl", [
        'S" Ctrl+S" _UTUI-PARSE-KEY-DESC',
        '. . CR',
    ], check_fn=lambda o: "4" in o)  # KEY-MOD-CTRL = 4

def test_shortcut_parse_ctrl_shift():
    """_UTUI-PARSE-KEY-DESC parses Ctrl+Shift+S."""
    check("shortcut-parse-ctrl-shift", [
        'S" Ctrl+Shift+S" _UTUI-PARSE-KEY-DESC',
        '. . CR',
    ], check_fn=lambda o: "5" in o)  # KEY-MOD-CTRL(4) | KEY-MOD-SHIFT(1) = 5


# ═══════════════════════════════════════════════════════════════════
#  §G — Layout Tests
# ═══════════════════════════════════════════════════════════════════

def test_layout_stack():
    """Stack layout gives children sequential rows."""
    check("layout-stack-rows", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        # First child is <label text="Title"> — row should be 0 (rgn origin)
        'UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
        # Second child <action btn1> — row should be 1
        'UIDL-ROOT UIDL-FIRST-CHILD UIDL-NEXT-SIB _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
    ]), check_fn=lambda o: "0" in o and "1" in o)

def test_layout_stack_width():
    """Stack layout children inherit parent width (80)."""
    check("layout-stack-width", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR _UTUI-SC-W@ . CR',
    ]), "80")

def test_layout_split():
    """Split layout divides width by ratio."""
    check("layout-split", _xml_lines(_XML_SPLIT, extra_after=[
        'DROP',
        # Root is <split ratio="40">.  Left pane = 40% of 80 = 32
        'UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR DUP _UTUI-SC-W@ . CR',
        'DROP',
        # Right pane
        'UIDL-ROOT UIDL-FIRST-CHILD UIDL-NEXT-SIB _UTUI-SIDECAR',
        'DUP _UTUI-SC-W@ . CR',
        'DUP _UTUI-SC-COL@ . CR',
        'DROP',
    ]), check_fn=lambda o: "32" in o)


# ═══════════════════════════════════════════════════════════════════
#  §H — Paint Tests
# ═══════════════════════════════════════════════════════════════════

def test_paint_no_crash():
    """UTUI-PAINT runs without crash after UTUI-LOAD."""
    check("paint-no-crash", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")

def test_paint_with_focus():
    """UTUI-PAINT runs with focus doc without crash."""
    check("paint-focus-doc", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")


# ═══════════════════════════════════════════════════════════════════
#  §I — Detach Tests
# ═══════════════════════════════════════════════════════════════════

def test_detach():
    """UTUI-DETACH resets all state."""
    check("detach-clears", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-DETACH',
        '_UTUI-DOC-LOADED @ 0= IF ." UNLOADED" ELSE ." STILL" THEN CR',
        'UTUI-FOCUS 0= IF ." NO-FOCUS" ELSE ." FOCUS" THEN CR',
    ]), check_fn=lambda o: "UNLOADED" in o and "NO-FOCUS" in o)


# ═══════════════════════════════════════════════════════════════════
#  §J — Dialog Tests
# ═══════════════════════════════════════════════════════════════════

def test_dialog_show_hide():
    """UTUI-SHOW-DIALOG makes dialog visible; UTUI-HIDE-DIALOG hides it."""
    check("dialog-show-hide", _xml_lines(_XML_DIALOG, extra_after=[
        'DROP',
        # Dialog starts hidden (when= not set → visible by default actually,
        # but we hide then show to test the API)
        'S" dlg1" UTUI-HIDE-DIALOG',
        'S" dlg1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0= IF ." HIDDEN" ELSE ." VIS" THEN CR',
        'S" dlg1" UTUI-SHOW-DIALOG',
        'S" dlg1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0<> IF ." VISIBLE" ELSE ." INVIS" THEN CR',
    ]), check_fn=lambda o: "HIDDEN" in o and "VISIBLE" in o)


# ═══════════════════════════════════════════════════════════════════
#  §K — UTUI-BY-ID Tests
# ═══════════════════════════════════════════════════════════════════

def test_by_id_found():
    """UTUI-BY-ID returns non-zero for existing id."""
    check("by-id-found", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'S" btn1" UTUI-BY-ID 0<> IF ." FOUND" ELSE ." MISSING" THEN CR',
    ]), "FOUND")

def test_by_id_missing():
    """UTUI-BY-ID returns 0 for non-existent id."""
    check("by-id-missing", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'S" nonexistent" UTUI-BY-ID 0= IF ." MISSING" ELSE ." FOUND" THEN CR',
    ]), "MISSING")


# ═══════════════════════════════════════════════════════════════════
#  §L — Relayout Tests
# ═══════════════════════════════════════════════════════════════════

def test_relayout():
    """UTUI-RELAYOUT can be called after load without crash."""
    check("relayout-no-crash", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-RELAYOUT',
        '." RELAYOUT-OK" CR',
    ]), "RELAYOUT-OK")


# ═══════════════════════════════════════════════════════════════════
#  §M — XT Installation Tests
# ═══════════════════════════════════════════════════════════════════

def test_xt_installed():
    """After loading, EL-LOOKUP for 'label' shows a non-NOOP render-xt."""
    check("xt-render-installed", [
        'S" label" EL-LOOKUP ?DUP IF',
        '  ED.RENDER-XT @ [\'] NOOP <> IF ." INSTALLED" ELSE ." NOOP" THEN',
        'ELSE ." NOT-FOUND" THEN CR',
    ], "INSTALLED")

def test_xt_event_installed():
    """After loading, EL-LOOKUP for 'action' shows a non-NOOP event-xt."""
    check("xt-event-installed", [
        'S" action" EL-LOOKUP ?DUP IF',
        '  ED.EVENT-XT @ [\'] NOOP <> IF ." INSTALLED" ELSE ." NOOP" THEN',
        'ELSE ." NOT-FOUND" THEN CR',
    ], "INSTALLED")

def test_xt_layout_installed():
    """After loading, EL-LOOKUP for 'region' shows a non-NOOP layout-xt."""
    check("xt-layout-installed", [
        'S" region" EL-LOOKUP ?DUP IF',
        '  ED.LAYOUT-XT @ [\'] NOOP <> IF ." INSTALLED" ELSE ." NOOP" THEN',
        'ELSE ." NOT-FOUND" THEN CR',
    ], "INSTALLED")


# ═══════════════════════════════════════════════════════════════════
#  §N — Hit Test (basic smoke)
# ═══════════════════════════════════════════════════════════════════

def test_hit_test_root():
    """UTUI-HIT-TEST at (0,0) finds the root or a child."""
    check("hit-test-root", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        '0 0 UTUI-HIT-TEST 0<> IF ." HIT" ELSE ." MISS" THEN CR',
    ]), "HIT")


# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════

def main():
    global _pass_count, _fail_count

    build_snapshot()
    print()
    print("=" * 60)
    print("  UIDL-TUI Test Suite")
    print("=" * 60)
    print()

    # §A Compilation
    print("[A] Compilation")
    test_compilation()
    print()

    # §B Load / Parse
    print("[B] Load / Parse")
    test_load_minimal()
    test_load_sets_loaded()
    test_load_bad_xml()
    print()

    # §C Sidecar
    print("[C] Sidecar Allocation")
    test_sidecar_allocation()
    test_sidecar_dimensions()
    print()

    # §D Focus
    print("[D] Focus Management")
    test_focus_initial()
    test_focus_next()
    test_focus_prev()
    test_focus_explicit()
    print()

    # §E Actions
    print("[E] Action Dispatch")
    test_action_register_fire()
    print()

    # §F Shortcuts
    print("[F] Shortcut Parsing")
    test_shortcut_parse_single()
    test_shortcut_parse_ctrl()
    test_shortcut_parse_ctrl_shift()
    print()

    # §G Layout
    print("[G] Layout")
    test_layout_stack()
    test_layout_stack_width()
    test_layout_split()
    print()

    # §H Paint
    print("[H] Paint")
    test_paint_no_crash()
    test_paint_with_focus()
    print()

    # §I Detach
    print("[I] Detach")
    test_detach()
    print()

    # §J Dialog
    print("[J] Dialog")
    test_dialog_show_hide()
    print()

    # §K By-ID
    print("[K] By-ID")
    test_by_id_found()
    test_by_id_missing()
    print()

    # §L Relayout
    print("[L] Relayout")
    test_relayout()
    print()

    # §M XT Installation
    print("[M] XT Installation")
    test_xt_installed()
    test_xt_event_installed()
    test_xt_layout_installed()
    print()

    # §N Hit Test
    print("[N] Hit Test")
    test_hit_test_root()
    print()

    # Summary
    print("=" * 60)
    total = _pass_count + _fail_count
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    print("=" * 60)
    return 1 if _fail_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
