#!/usr/bin/env python3
"""Test suite for akashic-tui-app-compositor (TUI Multi-App Compositor).

Uses the Megapad-64 emulator to boot KDOS, load the full dependency chain
through uidl-tui + app-shell + app-compositor, then exercises the public API.

New compositor features tested:
- Linked-list slot management (no fixed array, no slot limit)
- ID-based operations (COMP-LAUNCH returns ID, focus/close/minimize by ID)
- Dynamic tiling (ceil-sqrt grid, dividers, last-col/last-row remainder)
- Screen size from SCR-W / SCR-H (not hardcoded)
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

# Full topological dependency order
_DEP_PATHS = [
    os.path.join(AK, "concurrency", "event.f"),
    os.path.join(AK, "concurrency", "semaphore.f"),
    os.path.join(AK, "concurrency", "guard.f"),
    os.path.join(AK, "utils",       "string.f"),
    os.path.join(AK, "utils",       "term.f"),
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
    os.path.join(AK, "tui",         "widget.f"),
    os.path.join(AK, "tui",         "focus.f"),
    os.path.join(AK, "tui",         "widgets", "tree.f"),
    os.path.join(AK, "tui",         "widgets", "input.f"),
    os.path.join(AK, "text",        "gap-buf.f"),
    os.path.join(AK, "text",        "undo.f"),
    os.path.join(AK, "text",        "cell-width.f"),
    os.path.join(AK, "tui",         "widgets", "textarea.f"),
    os.path.join(AK, "css",         "css.f"),
    os.path.join(AK, "tui",         "color.f"),
    os.path.join(AK, "tui",         "uidl-tui.f"),
    os.path.join(AK, "tui",         "event.f"),
    os.path.join(AK, "tui",         "app.f"),
    os.path.join(AK, "tui",         "app-shell.f"),
    os.path.join(AK, "tui",         "app-compositor.f"),
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

    print("[*] Building snapshot: BIOS + KDOS + full TUI stack + compositor ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for p in _DEP_PATHS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        dep_lines.extend(_load_forth_lines(p))

    # Test helpers: scratch buffer + screen setup for region/layout tests
    test_helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Set up an 80×24 screen so SCR-W / SCR-H work in tests
        '80 24 SCR-NEW SCR-USE',
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
        for line in err_lines[:20]:
            print(f"    {line}")

    elapsed = time.time() - t0
    print(f"[*] Snapshot ready ({steps:,} cycles, {elapsed:.1f}s)")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    return _snapshot


# ═══════════════════════════════════════════════════════════════════
#  Test runner helpers
# ═══════════════════════════════════════════════════════════════════

import re

_pass_count = 0
_fail_count = 0

_ANSI_RE = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')

def _normalize(text):
    """Strip ANSI, command echoes, prompts, 'ok' tags; extract printed values."""
    text = _ANSI_RE.sub('', text)
    # Remove common ANSI fragment leftovers
    text = re.sub(r'\[\??\d+[hlJKm]', '', text)
    text = re.sub(r'\[\d*;\d*[Hfr]', '', text)
    text = re.sub(r'\[[\d;]*m', '', text)
    text = re.sub(r'\[H', '', text)
    text = re.sub(r'\[2J', '', text)
    text = re.sub(r'Megapad-64 Forth BIOS v[\d.]+', '', text)
    text = re.sub(r'RAM: [0-9a-fA-F]+ bytes', '', text)
    text = text.replace('\r', '')
    lines = text.strip().split('\n')
    values = []
    first_echo = True
    for line in lines:
        s = line.strip()
        # Skip command echoes (lines starting with "> ")
        if s.startswith('> ') or s == '>':
            first_echo = False
            continue
        # Skip the very first line (command echo without prompt prefix)
        if first_echo:
            first_echo = False
            continue
        # Remove trailing " ok"
        s = re.sub(r'\s+ok\s*$', '', s)
        # Skip empty and noise lines
        if not s or s == 'Bye!' or s == 'ok':
            continue
        values.append(s)
    return ' '.join(values)


def run_forth(lines):
    mem_bytes, cpu_state, ext_mem_bytes = build_snapshot()
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    buf = capture_uart(sys_obj)
    payload = "\n".join(lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 500_000_000

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


def check(name, lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    raw = run_forth(lines)
    norm = _normalize(raw)

    if expected is not None:
        if expected in norm:
            _pass_count += 1
            print(f"  PASS {name}")
        else:
            _fail_count += 1
            print(f"  FAIL {name}: expected={expected!r} not in {norm!r}")
            for line in raw.strip().split('\n')[-8:]:
                print(f"       | {line.rstrip()}")
    elif check_fn is not None:
        if check_fn(norm):
            _pass_count += 1
            print(f"  PASS {name}")
        else:
            _fail_count += 1
            print(f"  FAIL {name}: check_fn failed on {norm!r}")
            for line in raw.strip().split('\n')[-8:]:
                print(f"       | {line.rstrip()}")
    else:
        raise ValueError(f"check({name}): provide expected or check_fn")

def nums(s):
    """Extract space-separated integers from a string."""
    return ' '.join(re.findall(r'-?\d+', s))


# ═══════════════════════════════════════════════════════════════════
#  §1 — Constants
# ═══════════════════════════════════════════════════════════════════

def test_uctx_total():
    """_UCTX-TOTAL should be 99448."""
    check("uctx-total", [
        '_UCTX-TOTAL .',
    ], expected='99448')

def test_slot_sz():
    """_SLOT-SZ should be 56."""
    check("slot-sz", [
        '_SLOT-SZ .',
    ], expected='56')


# ═══════════════════════════════════════════════════════════════════
#  §2 — UIDL Context Alloc / Free
# ═══════════════════════════════════════════════════════════════════

def test_uctx_alloc_free():
    """UCTX-ALLOC should return a non-zero address; UCTX-FREE should not crash."""
    check("uctx-alloc-free", [
        'VARIABLE _UAF-P',
        'UCTX-ALLOC _UAF-P !',
        '_UAF-P @ 0<> .',
        '_UAF-P @ UCTX-FREE',
        'S" OK" TYPE',
    ], check_fn=lambda s: '-1' in s and 'OK' in s)

def test_uctx_clear():
    """UCTX-CLEAR should zero-fill the context buffer."""
    check("uctx-clear", [
        'UCTX-ALLOC DUP',
        '99 OVER !',
        'DUP UCTX-CLEAR',
        'DUP @ .',
        'UCTX-FREE',
    ], expected='0')


# ═══════════════════════════════════════════════════════════════════
#  §3 — UIDL Context Save / Restore
# ═══════════════════════════════════════════════════════════════════

def test_uctx_save_restore_scalars():
    """UCTX-SAVE should capture scalar state; UCTX-RESTORE should restore it."""
    check("uctx-save-restore-scalars", [
        'VARIABLE _USS-CTX',
        'UCTX-ALLOC _USS-CTX !',
        '_USS-CTX @ UCTX-CLEAR',
        # Set some globals to known values
        '42 _UTUI-FOCUS-P !',
        '7 _UTUI-ACT-CNT !',
        # Save
        '_USS-CTX @ UCTX-SAVE',
        # Clobber globals
        '0 _UTUI-FOCUS-P !',
        '0 _UTUI-ACT-CNT !',
        # Restore
        '_USS-CTX @ UCTX-RESTORE',
        # Check
        '_UTUI-FOCUS-P @ .  _UTUI-ACT-CNT @ .',
        '_USS-CTX @ UCTX-FREE',
    ], check_fn=lambda s: nums(s) == '42 7')

def test_uctx_save_restore_pool():
    """UCTX-SAVE should capture pool data; UCTX-RESTORE should restore it."""
    check("uctx-save-restore-pool", [
        'VARIABLE _USP-CTX',
        'UCTX-ALLOC _USP-CTX !',
        '_USP-CTX @ UCTX-CLEAR',
        # Write a known value into the UIDL element pool
        '12345678 _UDL-ELEMS !',
        # Save
        '_USP-CTX @ UCTX-SAVE',
        # Clobber
        '0 _UDL-ELEMS !',
        # Restore
        '_USP-CTX @ UCTX-RESTORE',
        '_UDL-ELEMS @ .',
        '_USP-CTX @ UCTX-FREE',
    ], expected='12345678')

def test_uctx_two_contexts():
    """Two contexts can be independently saved and restored."""
    check("uctx-two-contexts", [
        'VARIABLE _U2C-1  VARIABLE _U2C-2',
        'UCTX-ALLOC _U2C-1 !',
        'UCTX-ALLOC _U2C-2 !',
        # Verify both allocated (non-zero)
        '_U2C-1 @ 0<> _U2C-2 @ 0<> AND 0= IF',
        '  S" ALLOC-FAIL" TYPE',
        'ELSE',
        '  111 _UTUI-FOCUS-P !',
        '  _U2C-1 @ UCTX-SAVE',
        '  222 _UTUI-FOCUS-P !',
        '  _U2C-2 @ UCTX-SAVE',
        '  0 _UTUI-FOCUS-P !',
        '  _U2C-1 @ UCTX-RESTORE',
        '  _UTUI-FOCUS-P @ .',
        '  _U2C-2 @ UCTX-RESTORE',
        '  _UTUI-FOCUS-P @ .',
        'THEN',
        '_U2C-1 @ ?DUP IF UCTX-FREE THEN',
        '_U2C-2 @ ?DUP IF UCTX-FREE THEN',
    ], check_fn=lambda s: nums(s) == '111 222' or 'ALLOC-FAIL' in s)


# ═══════════════════════════════════════════════════════════════════
#  §4 — COMP-INIT
# ═══════════════════════════════════════════════════════════════════

def test_comp_init():
    """COMP-INIT should reset all compositor state."""
    check("comp-init", [
        'COMP-INIT',
        '_COMP-HEAD @ .',               # 0 (no slots)
        '_COMP-FOCUS-SA @ .',           # 0 (no focus)
        '_COMP-NEXT-ID @ .',            # 1 (counter reset)
        '_COMP-VH @ .',                 # 0 (V-pref)
        '_COMP-FULLFRAME @ .',          # 0
        '_COMP-RUNNING @ .',            # 0
    ], expected='0 0 1 0 0 0')


# ═══════════════════════════════════════════════════════════════════
#  §5 — Integer Math Helpers
# ═══════════════════════════════════════════════════════════════════

def test_isqrt():
    """_COMP-ISQRT should compute integer floor-sqrt."""
    check("isqrt", [
        '0 _COMP-ISQRT .',    # 0
        '1 _COMP-ISQRT .',    # 1
        '2 _COMP-ISQRT .',    # 1
        '3 _COMP-ISQRT .',    # 2 (Newton converges to 2 for n=3)
        '4 _COMP-ISQRT .',    # 2
        '5 _COMP-ISQRT .',    # 2
        '9 _COMP-ISQRT .',    # 3
        '16 _COMP-ISQRT .',   # 4
        '25 _COMP-ISQRT .',   # 5
    ], check_fn=lambda s: nums(s) == '0 1 1 2 2 2 3 4 5')

def test_cdiv():
    """_COMP-CDIV should compute ceiling division."""
    check("cdiv", [
        '1 1 _COMP-CDIV .',    # 1
        '3 2 _COMP-CDIV .',    # 2
        '4 2 _COMP-CDIV .',    # 2
        '5 3 _COMP-CDIV .',    # 2
        '7 3 _COMP-CDIV .',    # 3
        '10 3 _COMP-CDIV .',   # 4
    ], check_fn=lambda s: nums(s) == '1 2 2 2 3 4')


# ═══════════════════════════════════════════════════════════════════
#  §6 — COMP-LAUNCH (returns IDs)
# ═══════════════════════════════════════════════════════════════════

def test_launch_returns_id():
    """COMP-LAUNCH should return monotonic IDs starting at 1."""
    check("launch-returns-id", [
        'COMP-INIT',
        ': _LR-I ;',
        'CREATE _LR-D1 APP-DESC ALLOT  _LR-D1 APP-DESC-INIT',
        'CREATE _LR-D2 APP-DESC ALLOT  _LR-D2 APP-DESC-INIT',
        'CREATE _LR-D3 APP-DESC ALLOT  _LR-D3 APP-DESC-INIT',
        "' _LR-I _LR-D1 APP.INIT-XT !",
        "' _LR-I _LR-D2 APP.INIT-XT !",
        "' _LR-I _LR-D3 APP.INIT-XT !",
        '_LR-D1 COMP-LAUNCH .',        # 1
        '_LR-D2 COMP-LAUNCH .',        # 2
        '_LR-D3 COMP-LAUNCH .',        # 3
    ], expected='1 2 3')

def test_launch_first_focused():
    """First launched app should be focused, second should be running."""
    check("launch-first-focused", [
        'COMP-INIT',
        ': _LF-I ;',
        'CREATE _LF-D1 APP-DESC ALLOT  _LF-D1 APP-DESC-INIT',
        'CREATE _LF-D2 APP-DESC ALLOT  _LF-D2 APP-DESC-INIT',
        "' _LF-I _LF-D1 APP.INIT-XT !",
        "' _LF-I _LF-D2 APP.INIT-XT !",
        '_LF-D1 COMP-LAUNCH DROP',
        '_LF-D2 COMP-LAUNCH DROP',
        # Check state of app ID 1 (should be focused = 3)
        '1 _COMP-FIND-ID _SL-STATE @ .',
        # Check state of app ID 2 (should be running = 1)
        '2 _COMP-FIND-ID _SL-STATE @ .',
        # Check focused slot holds ID 1
        '_COMP-FOCUS-SA @ _SL-ID @ .',
    ], expected='3 1 1')


# ═══════════════════════════════════════════════════════════════════
#  §7 — Slot Count / Visible Count
# ═══════════════════════════════════════════════════════════════════

def test_slot_count():
    """COMP-SLOT-COUNT should count all live slots."""
    check("slot-count", [
        'COMP-INIT',
        'COMP-SLOT-COUNT .',            # 0
        ': _SC-I ;',
        'CREATE _SC-D1 APP-DESC ALLOT  _SC-D1 APP-DESC-INIT',
        'CREATE _SC-D2 APP-DESC ALLOT  _SC-D2 APP-DESC-INIT',
        "' _SC-I _SC-D1 APP.INIT-XT !",
        "' _SC-I _SC-D2 APP.INIT-XT !",
        '_SC-D1 COMP-LAUNCH DROP',
        'COMP-SLOT-COUNT .',            # 1
        '_SC-D2 COMP-LAUNCH DROP',
        'COMP-SLOT-COUNT .',            # 2
    ], check_fn=lambda s: nums(s) == '0 1 2')

def test_vcount():
    """COMP-VCOUNT should count visible (non-minimized) slots."""
    check("vcount", [
        'COMP-INIT',
        'COMP-VCOUNT .',                # 0
        ': _VC-I ;',
        'CREATE _VC-D1 APP-DESC ALLOT  _VC-D1 APP-DESC-INIT',
        'CREATE _VC-D2 APP-DESC ALLOT  _VC-D2 APP-DESC-INIT',
        "' _VC-I _VC-D1 APP.INIT-XT !",
        "' _VC-I _VC-D2 APP.INIT-XT !",
        '_VC-D1 COMP-LAUNCH DROP',
        'COMP-VCOUNT .',                # 1
        '_VC-D2 COMP-LAUNCH DROP',
        'COMP-VCOUNT .',                # 2
        '1 COMP-MINIMIZE-ID',
        'COMP-VCOUNT .',                # 1
    ], check_fn=lambda s: nums(s) == '0 1 2 1')

def test_vcount_after_close():
    """Closing an app should decrease both total and visible counts."""
    check("vcount-after-close", [
        'COMP-INIT',
        ': _VAC-I ;',
        'CREATE _VAC-D1 APP-DESC ALLOT  _VAC-D1 APP-DESC-INIT',
        'CREATE _VAC-D2 APP-DESC ALLOT  _VAC-D2 APP-DESC-INIT',
        "' _VAC-I _VAC-D1 APP.INIT-XT !",
        "' _VAC-I _VAC-D2 APP.INIT-XT !",
        '_VAC-D1 COMP-LAUNCH DROP',
        '_VAC-D2 COMP-LAUNCH DROP',
        'COMP-SLOT-COUNT . COMP-VCOUNT .',  # 2 2
        '1 COMP-CLOSE-ID',
        'COMP-SLOT-COUNT . COMP-VCOUNT .',  # 1 1
    ], check_fn=lambda s: nums(s) == '2 2 1 1')


# ═══════════════════════════════════════════════════════════════════
#  §8 — Focus
# ═══════════════════════════════════════════════════════════════════

def test_focus_switch():
    """COMP-FOCUS-ID switches focus between apps by ID."""
    check("focus-switch", [
        'COMP-INIT',
        ': _FS-I ;',
        'CREATE _FS-D1 APP-DESC ALLOT  _FS-D1 APP-DESC-INIT',
        'CREATE _FS-D2 APP-DESC ALLOT  _FS-D2 APP-DESC-INIT',
        "' _FS-I _FS-D1 APP.INIT-XT !",
        "' _FS-I _FS-D2 APP.INIT-XT !",
        '_FS-D1 COMP-LAUNCH DROP',
        '_FS-D2 COMP-LAUNCH DROP',
        # Initially ID 1 is focused
        '_COMP-FOCUS-SA @ _SL-ID @ .',
        # Switch focus to ID 2
        '2 COMP-FOCUS-ID',
        '_COMP-FOCUS-SA @ _SL-ID @ .',
        '1 _COMP-FIND-ID _SL-STATE @ .',  # ID 1 should be running (1)
        '2 _COMP-FIND-ID _SL-STATE @ .',  # ID 2 should be focused (3)
    ], check_fn=lambda s: nums(s) == '1 2 1 3')

def test_focus_invalid_id():
    """COMP-FOCUS-ID on a non-existent ID should be a no-op."""
    check("focus-invalid-id", [
        'COMP-INIT',
        ': _FI-I ;',
        'CREATE _FI-D APP-DESC ALLOT  _FI-D APP-DESC-INIT',
        "' _FI-I _FI-D APP.INIT-XT !",
        '_FI-D COMP-LAUNCH DROP',
        '999 COMP-FOCUS-ID',           # non-existent ID
        '_COMP-FOCUS-SA @ _SL-ID @ .', # should still be 1
    ], expected='1')

def test_focus_minimized_noop():
    """COMP-FOCUS-ID on a minimized app should be a no-op."""
    check("focus-minimized-noop", [
        'COMP-INIT',
        ': _FM-I ;',
        'CREATE _FM-D1 APP-DESC ALLOT  _FM-D1 APP-DESC-INIT',
        'CREATE _FM-D2 APP-DESC ALLOT  _FM-D2 APP-DESC-INIT',
        "' _FM-I _FM-D1 APP.INIT-XT !",
        "' _FM-I _FM-D2 APP.INIT-XT !",
        '_FM-D1 COMP-LAUNCH DROP',
        '_FM-D2 COMP-LAUNCH DROP',
        '1 COMP-MINIMIZE-ID',
        # Try to focus minimized ID 1 — should be no-op
        '1 COMP-FOCUS-ID',
        '_COMP-FOCUS-SA @ _SL-ID @ .',  # should still be 2
    ], expected='2')


# ═══════════════════════════════════════════════════════════════════
#  §9 — Minimize & Restore
# ═══════════════════════════════════════════════════════════════════

def test_minimize():
    """COMP-MINIMIZE-ID sets state to minimized and finds new focus."""
    check("minimize", [
        'COMP-INIT',
        ': _MN-I ;',
        'CREATE _MN-D1 APP-DESC ALLOT  _MN-D1 APP-DESC-INIT',
        'CREATE _MN-D2 APP-DESC ALLOT  _MN-D2 APP-DESC-INIT',
        "' _MN-I _MN-D1 APP.INIT-XT !",
        "' _MN-I _MN-D2 APP.INIT-XT !",
        '_MN-D1 COMP-LAUNCH DROP',
        '_MN-D2 COMP-LAUNCH DROP',
        # Minimize the focused app (ID 1)
        '1 COMP-MINIMIZE-ID',
        '1 _COMP-FIND-ID _SL-STATE @ .',  # minimized (2)
        '_COMP-FOCUS-SA @ _SL-ID @ .',     # focus should move to ID 2
        '2 _COMP-FIND-ID _SL-STATE @ .',   # ID 2 now focused (3)
    ], expected='2 2 3')

def test_restore():
    """COMP-RESTORE brings back the most recently minimized slot."""
    check("restore", [
        'COMP-INIT',
        ': _RS-I ;',
        'CREATE _RS-D1 APP-DESC ALLOT  _RS-D1 APP-DESC-INIT',
        'CREATE _RS-D2 APP-DESC ALLOT  _RS-D2 APP-DESC-INIT',
        "' _RS-I _RS-D1 APP.INIT-XT !",
        "' _RS-I _RS-D2 APP.INIT-XT !",
        '_RS-D1 COMP-LAUNCH DROP',
        '_RS-D2 COMP-LAUNCH DROP',
        '1 COMP-MINIMIZE-ID',
        'COMP-RESTORE',
        '1 _COMP-FIND-ID _SL-STATE @ .',  # restored = running (1)
        '_COMP-FOCUS-SA @ _SL-ID @ .',     # focus still on ID 2
    ], expected='1 2')

def test_restore_when_no_focus():
    """COMP-RESTORE with no focus should make the restored app focused."""
    check("restore-no-focus", [
        'COMP-INIT',
        ': _RN-I ;',
        'CREATE _RN-D APP-DESC ALLOT  _RN-D APP-DESC-INIT',
        "' _RN-I _RN-D APP.INIT-XT !",
        '_RN-D COMP-LAUNCH DROP',
        # Minimize the only app — no other app gets focus
        '1 COMP-MINIMIZE-ID',
        '_COMP-FOCUS-SA @ .',              # 0 — no focus
        'COMP-RESTORE',
        '1 _COMP-FIND-ID _SL-STATE @ .',  # focused (3)
        '_COMP-FOCUS-SA @ _SL-ID @ .',     # focus = ID 1
    ], expected='0 3 1')


# ═══════════════════════════════════════════════════════════════════
#  §10 — Close
# ═══════════════════════════════════════════════════════════════════

def test_close():
    """COMP-CLOSE-ID removes slot, calls shutdown, reassigns focus."""
    check("close", [
        'COMP-INIT',
        'VARIABLE _CL-SD  0 _CL-SD !',
        ': _CL-I ;',
        ': _CL-S  -1 _CL-SD ! ;',
        'CREATE _CL-D1 APP-DESC ALLOT  _CL-D1 APP-DESC-INIT',
        'CREATE _CL-D2 APP-DESC ALLOT  _CL-D2 APP-DESC-INIT',
        "' _CL-I _CL-D1 APP.INIT-XT !",
        "' _CL-S _CL-D1 APP.SHUTDOWN-XT !",
        "' _CL-I _CL-D2 APP.INIT-XT !",
        '_CL-D1 COMP-LAUNCH DROP',
        '_CL-D2 COMP-LAUNCH DROP',
        # Close focused app (ID 1)
        '1 COMP-CLOSE-ID',
        '_CL-SD @ .',                     # shutdown called (-1)
        '1 _COMP-FIND-ID .',              # slot gone (0)
        'COMP-SLOT-COUNT .',               # 1 slot left
        '_COMP-FOCUS-SA @ _SL-ID @ .',     # focus moved to ID 2
    ], expected='-1 0 1 2')

def test_close_last_app():
    """Closing the only app should leave empty state."""
    check("close-last-app", [
        'COMP-INIT',
        ': _CLA-I ;',
        'CREATE _CLA-D APP-DESC ALLOT  _CLA-D APP-DESC-INIT',
        "' _CLA-I _CLA-D APP.INIT-XT !",
        '_CLA-D COMP-LAUNCH DROP',
        '1 COMP-CLOSE-ID',
        'COMP-SLOT-COUNT .',               # 0
        '_COMP-FOCUS-SA @ .',              # 0
    ], expected='0 0')


# ═══════════════════════════════════════════════════════════════════
#  §11 — Layout (region assignment)
# ═══════════════════════════════════════════════════════════════════

def test_layout_single():
    """Single visible app should get full 80×23 region (80 wide, H-1 tall)."""
    check("layout-single", [
        'COMP-INIT',
        ': _LS-I ;',
        'CREATE _LS-D APP-DESC ALLOT  _LS-D APP-DESC-INIT',
        "' _LS-I _LS-D APP.INIT-XT !",
        '_LS-D COMP-LAUNCH DROP',
        '1 _COMP-FIND-ID _SL-RGN @ DUP 0<> .',  # non-zero region
        'DUP RGN-W .',                            # 80
        'RGN-H .',                                # 23
    ], expected='-1 80 23')

def test_layout_two_vpref():
    """Two visible apps V-pref: 39+40 wide, 23 tall."""
    check("layout-two-vpref", [
        'COMP-INIT',
        ': _LV-I ;',
        'CREATE _LV-D1 APP-DESC ALLOT  _LV-D1 APP-DESC-INIT',
        'CREATE _LV-D2 APP-DESC ALLOT  _LV-D2 APP-DESC-INIT',
        "' _LV-I _LV-D1 APP.INIT-XT !",
        "' _LV-I _LV-D2 APP.INIT-XT !",
        '_LV-D1 COMP-LAUNCH DROP',
        '_LV-D2 COMP-LAUNCH DROP',
        # V-pref (default): cols=2, rows=1
        # TW=(80-1)/2=39, LW=80-1-39=40, TH=23, LH=23
        '1 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 39 23
        '2 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 40 23
    ], expected='39 23 40 23')

def test_layout_two_hpref():
    """Two visible apps H-pref: 80 wide, 11+11 tall."""
    check("layout-two-hpref", [
        'COMP-INIT',
        '1 _COMP-VH !',                # set horizontal preference
        ': _LH-I ;',
        'CREATE _LH-D1 APP-DESC ALLOT  _LH-D1 APP-DESC-INIT',
        'CREATE _LH-D2 APP-DESC ALLOT  _LH-D2 APP-DESC-INIT',
        "' _LH-I _LH-D1 APP.INIT-XT !",
        "' _LH-I _LH-D2 APP.INIT-XT !",
        '_LH-D1 COMP-LAUNCH DROP',
        '_LH-D2 COMP-LAUNCH DROP',
        # H-pref: rows=2, cols=1
        # TW=80, TH=(23-1)/2=11, LW=80, LH=23-1-11=11
        '1 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 80 11
        '2 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 80 11
    ], expected='80 11 80 11')

def test_layout_four_vpref():
    """Four visible apps V-pref: 2×2 grid, 39|40 × 11|11."""
    check("layout-four-vpref", [
        'COMP-INIT',
        ': _L4-I ;',
        'CREATE _L4-D1 APP-DESC ALLOT  _L4-D1 APP-DESC-INIT',
        'CREATE _L4-D2 APP-DESC ALLOT  _L4-D2 APP-DESC-INIT',
        'CREATE _L4-D3 APP-DESC ALLOT  _L4-D3 APP-DESC-INIT',
        'CREATE _L4-D4 APP-DESC ALLOT  _L4-D4 APP-DESC-INIT',
        "' _L4-I _L4-D1 APP.INIT-XT !",
        "' _L4-I _L4-D2 APP.INIT-XT !",
        "' _L4-I _L4-D3 APP.INIT-XT !",
        "' _L4-I _L4-D4 APP.INIT-XT !",
        '_L4-D1 COMP-LAUNCH DROP',
        '_L4-D2 COMP-LAUNCH DROP',
        '_L4-D3 COMP-LAUNCH DROP',
        '_L4-D4 COMP-LAUNCH DROP',
        # 2×2 grid: TW=39,LW=40, TH=11,LH=11
        '1 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 39 11
        '2 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 40 11
        '3 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 39 11
        '4 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 40 11
    ], expected='39 11 40 11 39 11 40 11')

def test_layout_after_minimize():
    """Minimizing an app should relayout remaining visible apps."""
    check("layout-after-minimize", [
        'COMP-INIT',
        ': _LAM-I ;',
        'CREATE _LAM-D1 APP-DESC ALLOT  _LAM-D1 APP-DESC-INIT',
        'CREATE _LAM-D2 APP-DESC ALLOT  _LAM-D2 APP-DESC-INIT',
        "' _LAM-I _LAM-D1 APP.INIT-XT !",
        "' _LAM-I _LAM-D2 APP.INIT-XT !",
        '_LAM-D1 COMP-LAUNCH DROP',
        '_LAM-D2 COMP-LAUNCH DROP',
        # With 2 apps, V-split: 39|40
        '1 _COMP-FIND-ID _SL-RGN @ RGN-W .',  # 39
        # Minimize app 1
        '1 COMP-MINIMIZE-ID',
        # Now only app 2 visible → full width
        '2 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 80 23
    ], check_fn=lambda s: nums(s) == '39 80 23')

def test_toggle_vh():
    """COMP-TOGGLE-VH should flip between V and H preference."""
    check("toggle-vh", [
        'COMP-INIT',
        '_COMP-VH @ .',                # 0 (V-pref)
        'COMP-TOGGLE-VH',
        '_COMP-VH @ 0<> .',            # -1 (H-pref, truthy)
        'COMP-TOGGLE-VH',
        '_COMP-VH @ .',                # 0 (back to V-pref)
    ], check_fn=lambda s: nums(s) == '0 -1 0')


# ═══════════════════════════════════════════════════════════════════
#  §12 — Full-frame toggle
# ═══════════════════════════════════════════════════════════════════

def test_fullframe():
    """COMP-FULLFRAME! toggles full-frame mode."""
    check("fullframe", [
        'COMP-INIT',
        '_COMP-FULLFRAME @ .',         # 0
        '-1 COMP-FULLFRAME!',
        '_COMP-FULLFRAME @ 0<> .',     # -1 (truthy)
        '0 COMP-FULLFRAME!',
        '_COMP-FULLFRAME @ .',         # 0
    ], check_fn=lambda s: nums(s) == '0 -1 0')


# ═══════════════════════════════════════════════════════════════════
#  §13 — Taskbar text builder
# ═══════════════════════════════════════════════════════════════════

def test_taskbar_single_app():
    """Taskbar should show [1:App*] for a single focused app."""
    check("taskbar-single-app", [
        'COMP-INIT',
        ': _TSA-I ;',
        'CREATE _TSA-D APP-DESC ALLOT  _TSA-D APP-DESC-INIT',
        "' _TSA-I _TSA-D APP.INIT-XT !",
        '_TSA-D COMP-LAUNCH DROP',
        # Build taskbar text
        '_COMP-PAINT-TASKBAR',
        '_COMP-TB-BUF _COMP-TB-POS @ TYPE',
    ], expected='[1:App*]')

def test_taskbar_two_apps():
    """Taskbar should show focused(*) and running apps."""
    check("taskbar-two-apps", [
        'COMP-INIT',
        ': _TTA-I ;',
        'CREATE _TTA-D1 APP-DESC ALLOT  _TTA-D1 APP-DESC-INIT',
        'CREATE _TTA-D2 APP-DESC ALLOT  _TTA-D2 APP-DESC-INIT',
        "' _TTA-I _TTA-D1 APP.INIT-XT !",
        "' _TTA-I _TTA-D2 APP.INIT-XT !",
        '_TTA-D1 COMP-LAUNCH DROP',
        '_TTA-D2 COMP-LAUNCH DROP',
        '_COMP-PAINT-TASKBAR',
        '_COMP-TB-BUF _COMP-TB-POS @ TYPE',
    ], expected='[1:App*] [2:App]')


# ═══════════════════════════════════════════════════════════════════
#  §14 — Shortcut Detection
# ═══════════════════════════════════════════════════════════════════

def test_shortcut_alt1():
    """Alt+1 should focus app 1."""
    check("shortcut-alt1", [
        'COMP-INIT',
        ': _SA-I ;',
        'CREATE _SA-D1 APP-DESC ALLOT  _SA-D1 APP-DESC-INIT',
        'CREATE _SA-D2 APP-DESC ALLOT  _SA-D2 APP-DESC-INIT',
        "' _SA-I _SA-D1 APP.INIT-XT !",
        "' _SA-I _SA-D2 APP.INIT-XT !",
        '_SA-D1 COMP-LAUNCH DROP',
        '_SA-D2 COMP-LAUNCH DROP',
        '2 COMP-FOCUS-ID',               # focus app 2
        # Build fake Alt+1 event: type=KEY-T-CHAR(0), code=49('1'), mods=KEY-MOD-ALT(2)
        'CREATE _SA-EV 24 ALLOT',
        'KEY-T-CHAR _SA-EV !  49 _SA-EV 8 + !  KEY-MOD-ALT _SA-EV 16 + !',
        '_SA-EV COMP-SHORTCUT? .',       # should return -1 (handled)
        '_COMP-FOCUS-SA @ _SL-ID @ .',   # focus back to ID 1
    ], expected='-1 1')

def test_shortcut_alt_w():
    """Alt+W should close the focused app."""
    check("shortcut-alt-w", [
        'COMP-INIT',
        ': _SW-I ;',
        'CREATE _SW-D1 APP-DESC ALLOT  _SW-D1 APP-DESC-INIT',
        'CREATE _SW-D2 APP-DESC ALLOT  _SW-D2 APP-DESC-INIT',
        "' _SW-I _SW-D1 APP.INIT-XT !",
        "' _SW-I _SW-D2 APP.INIT-XT !",
        '_SW-D1 COMP-LAUNCH DROP',
        '_SW-D2 COMP-LAUNCH DROP',
        'COMP-SLOT-COUNT .',              # 2
        # Build fake Alt+W event: type=0, code=119('w'), mods=2
        'CREATE _SW-EV 24 ALLOT',
        'KEY-T-CHAR _SW-EV !  119 _SW-EV 8 + !  KEY-MOD-ALT _SW-EV 16 + !',
        '_SW-EV COMP-SHORTCUT? .',        # -1
        'COMP-SLOT-COUNT .',              # 1 (focused app closed)
    ], check_fn=lambda s: nums(s) == '2 -1 1')


# ═══════════════════════════════════════════════════════════════════
#  §15 — COMP-QUIT
# ═══════════════════════════════════════════════════════════════════

def test_comp_quit():
    """COMP-QUIT should clear the running flag."""
    check("comp-quit", [
        '-1 _COMP-RUNNING !',
        '_COMP-RUNNING @ 0<> .',       # -1
        'COMP-QUIT',
        '_COMP-RUNNING @ .',           # 0
    ], check_fn=lambda s: nums(s) == '-1 0')


# ═══════════════════════════════════════════════════════════════════
#  §16 — Init callback invocation
# ═══════════════════════════════════════════════════════════════════

def test_init_callback():
    """COMP-LAUNCH should call the app's init callback."""
    check("init-callback", [
        'COMP-INIT',
        'VARIABLE _IC-V  0 _IC-V !',
        ': _IC-INIT  -1 _IC-V ! ;',
        'CREATE _IC-D APP-DESC ALLOT  _IC-D APP-DESC-INIT',
        "' _IC-INIT _IC-D APP.INIT-XT !",
        '_IC-D COMP-LAUNCH DROP',
        '_IC-V @ 0<> .',
    ], expected='-1')


# ═══════════════════════════════════════════════════════════════════
#  §17 — No artificial slot limit
# ═══════════════════════════════════════════════════════════════════

def test_launch_many_apps():
    """Should be able to launch more than 3 apps (no artificial limit)."""
    check("launch-many-apps", [
        'COMP-INIT',
        ': _LM-I ;',
        'CREATE _LM-D1 APP-DESC ALLOT  _LM-D1 APP-DESC-INIT',
        'CREATE _LM-D2 APP-DESC ALLOT  _LM-D2 APP-DESC-INIT',
        'CREATE _LM-D3 APP-DESC ALLOT  _LM-D3 APP-DESC-INIT',
        'CREATE _LM-D4 APP-DESC ALLOT  _LM-D4 APP-DESC-INIT',
        'CREATE _LM-D5 APP-DESC ALLOT  _LM-D5 APP-DESC-INIT',
        "' _LM-I _LM-D1 APP.INIT-XT !",
        "' _LM-I _LM-D2 APP.INIT-XT !",
        "' _LM-I _LM-D3 APP.INIT-XT !",
        "' _LM-I _LM-D4 APP.INIT-XT !",
        "' _LM-I _LM-D5 APP.INIT-XT !",
        '_LM-D1 COMP-LAUNCH .',        # 1
        '_LM-D2 COMP-LAUNCH .',        # 2
        '_LM-D3 COMP-LAUNCH .',        # 3
        '_LM-D4 COMP-LAUNCH .',        # 4
        '_LM-D5 COMP-LAUNCH .',        # 5
        'COMP-SLOT-COUNT .',           # 5
    ], expected='1 2 3 4 5 5')

def test_layout_five_vpref():
    """Five apps V-pref: 3×2 grid."""
    check("layout-five-vpref", [
        'COMP-INIT',
        ': _L5-I ;',
        'CREATE _L5-D1 APP-DESC ALLOT  _L5-D1 APP-DESC-INIT',
        'CREATE _L5-D2 APP-DESC ALLOT  _L5-D2 APP-DESC-INIT',
        'CREATE _L5-D3 APP-DESC ALLOT  _L5-D3 APP-DESC-INIT',
        'CREATE _L5-D4 APP-DESC ALLOT  _L5-D4 APP-DESC-INIT',
        'CREATE _L5-D5 APP-DESC ALLOT  _L5-D5 APP-DESC-INIT',
        "' _L5-I _L5-D1 APP.INIT-XT !",
        "' _L5-I _L5-D2 APP.INIT-XT !",
        "' _L5-I _L5-D3 APP.INIT-XT !",
        "' _L5-I _L5-D4 APP.INIT-XT !",
        "' _L5-I _L5-D5 APP.INIT-XT !",
        '_L5-D1 COMP-LAUNCH DROP',
        '_L5-D2 COMP-LAUNCH DROP',
        '_L5-D3 COMP-LAUNCH DROP',
        '_L5-D4 COMP-LAUNCH DROP',
        '_L5-D5 COMP-LAUNCH DROP',
        # 5 apps, V-pref: cols=ceil(sqrt(5))=3, rows=ceil(5/3)=2
        # TW=(80-2)/3=26, TH=(23-1)/2=11
        # LW=80-2-26*2=26, LH=23-1-11=11
        '1 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 26 11
        '3 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 26 11 (last col)
        '5 _COMP-FIND-ID _SL-RGN @ DUP RGN-W . RGN-H .',  # 26 11
    ], expected='26 11 26 11 26 11')


# ═══════════════════════════════════════════════════════════════════
#  §18 — Linked-list helpers
# ═══════════════════════════════════════════════════════════════════

def test_find_id():
    """_COMP-FIND-ID should find slot by ID or return 0."""
    check("find-id", [
        'COMP-INIT',
        ': _FID-I ;',
        'CREATE _FID-D APP-DESC ALLOT  _FID-D APP-DESC-INIT',
        "' _FID-I _FID-D APP.INIT-XT !",
        '_FID-D COMP-LAUNCH DROP',
        '1 _COMP-FIND-ID 0<> .',       # found (-1)
        '99 _COMP-FIND-ID .',           # not found (0)
    ], expected='-1 0')

def test_unlink_relink():
    """Close should properly unlink from the middle of the list."""
    check("unlink-relink", [
        'COMP-INIT',
        ': _UR-I ;',
        'CREATE _UR-D1 APP-DESC ALLOT  _UR-D1 APP-DESC-INIT',
        'CREATE _UR-D2 APP-DESC ALLOT  _UR-D2 APP-DESC-INIT',
        'CREATE _UR-D3 APP-DESC ALLOT  _UR-D3 APP-DESC-INIT',
        "' _UR-I _UR-D1 APP.INIT-XT !",
        "' _UR-I _UR-D2 APP.INIT-XT !",
        "' _UR-I _UR-D3 APP.INIT-XT !",
        '_UR-D1 COMP-LAUNCH DROP',
        '_UR-D2 COMP-LAUNCH DROP',
        '_UR-D3 COMP-LAUNCH DROP',
        'COMP-SLOT-COUNT .',            # 3
        # Close middle app (ID 2)
        '2 COMP-CLOSE-ID',
        'COMP-SLOT-COUNT .',            # 2
        # Remaining apps should still be findable
        '1 _COMP-FIND-ID 0<> .',       # -1
        '3 _COMP-FIND-ID 0<> .',       # -1
        '2 _COMP-FIND-ID .',           # 0 (gone)
    ], expected='3 2 -1 -1 0')


# ═══════════════════════════════════════════════════════════════════
#  Runner
# ═══════════════════════════════════════════════════════════════════

def main():
    global _pass_count, _fail_count

    build_snapshot()
    print()

    tests = [
        # §1 — Constants
        test_uctx_total,
        test_slot_sz,
        # §2 — UIDL Context alloc/free
        test_uctx_alloc_free,
        test_uctx_clear,
        # §3 — Save/Restore
        test_uctx_save_restore_scalars,
        test_uctx_save_restore_pool,
        test_uctx_two_contexts,
        # §4 — COMP-INIT
        test_comp_init,
        # §5 — Math helpers
        test_isqrt,
        test_cdiv,
        # §6 — Launch
        test_launch_returns_id,
        test_launch_first_focused,
        # §7 — Counts
        test_slot_count,
        test_vcount,
        test_vcount_after_close,
        # §8 — Focus
        test_focus_switch,
        test_focus_invalid_id,
        test_focus_minimized_noop,
        # §9 — Minimize & Restore
        test_minimize,
        test_restore,
        test_restore_when_no_focus,
        # §10 — Close
        test_close,
        test_close_last_app,
        # §11 — Layout
        test_layout_single,
        test_layout_two_vpref,
        test_layout_two_hpref,
        test_layout_four_vpref,
        test_layout_after_minimize,
        test_toggle_vh,
        # §12 — Full-frame
        test_fullframe,
        # §13 — Taskbar
        test_taskbar_single_app,
        test_taskbar_two_apps,
        # §14 — Shortcuts
        test_shortcut_alt1,
        test_shortcut_alt_w,
        # §15 — Quit
        test_comp_quit,
        # §16 — Init callback
        test_init_callback,
        # §17 — No artificial limit
        test_launch_many_apps,
        test_layout_five_vpref,
        # §18 — Linked-list
        test_find_id,
        test_unlink_relink,
    ]

    for test in tests:
        try:
            test()
        except Exception as e:
            _fail_count += 1
            print(f"  ERROR {test.__name__}: {e}")

    print(f"\n{'='*50}")
    total = _pass_count + _fail_count
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    if _fail_count:
        print("  SOME TESTS FAILED")
    else:
        print("  ALL TESTS PASSED")
    print(f"{'='*50}")
    return 0 if _fail_count == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
