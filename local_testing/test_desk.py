#!/usr/bin/env python3
"""Test suite for desk.f — TUI Multi-App Desktop with config/theme/hotbar.

Uses the Megapad-64 emulator to boot KDOS, load the full dependency chain
through desk.f, then exercises:
  - Compilation (does it even load?)
  - Theme defaults
  - Theme TOML loading
  - Hotbar TOML loading
  - APP-DESC descriptor setup
  - Lifecycle: init → quit cycle
  - Slot management basics
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

# Full topological dependency order.  REQUIRE/PROVIDED are stripped
# by the loader — we must list every .f file in order.
#
# Compared to test_app_shell.py we add:
#   - toml.f (for config parsing)
#   - color.f (for TUI-PARSE-COLOR, depends on css.f + string.f)
#   - cogs/term-init.f (app-shell now requires this instead of app.f)
#   - desk.f itself
_DEP_PATHS = [
    # concurrency
    os.path.join(AK, "concurrency", "event.f"),
    os.path.join(AK, "concurrency", "semaphore.f"),
    os.path.join(AK, "concurrency", "guard.f"),
    # utils
    os.path.join(AK, "utils",       "string.f"),
    os.path.join(AK, "utils",       "term.f"),
    # math
    os.path.join(AK, "math",        "fp32.f"),
    os.path.join(AK, "math",        "fixed.f"),
    # text
    os.path.join(AK, "text",        "utf8.f"),
    # toml (needs string.f + utf8.f)
    os.path.join(AK, "utils",       "toml.f"),
    # markup / liraq
    os.path.join(AK, "markup",      "core.f"),
    os.path.join(AK, "markup",      "xml.f"),
    os.path.join(AK, "liraq",       "state-tree.f"),
    os.path.join(AK, "liraq",       "lel.f"),
    os.path.join(AK, "liraq",       "uidl.f"),
    os.path.join(AK, "liraq",       "uidl-chrome.f"),
    # TUI core
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
    # CSS + color
    os.path.join(AK, "css",         "css.f"),
    os.path.join(AK, "tui",         "color.f"),
    # TUI runtime
    os.path.join(AK, "tui",         "uidl-tui.f"),
    os.path.join(AK, "tui",         "event.f"),
    os.path.join(AK, "tui",         "cogs", "term-init.f"),
    os.path.join(AK, "tui",         "app-desc.f"),
    # VFS (app-shell.f requires vfs-mp64fs.f for VFS init)
    os.path.join(AK, "utils",       "fs", "vfs.f"),
    os.path.join(AK, "utils",       "fs", "drivers", "vfs-mp64fs.f"),
    os.path.join(AK, "tui",         "app-shell.f"),
    # desk itself
    os.path.join(AK, "tui",         "applets", "desk", "desk.f"),
]

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers (same pattern as test_app_shell.py / test_string.py)
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

def _next_line_chunk(data: bytes, pos: int) -> bytes:
    nl = data.find(b'\n', pos)
    return data[pos:nl+1] if nl != -1 else data[pos:]

def capture_uart(sys_obj):
    buf = []
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
    """Boot BIOS + KDOS + full dep chain + test helpers.  ~97 KiB ctx per UIDL."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + full TUI stack + desk.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for p in _DEP_PATHS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        dep_lines.extend(_load_forth_lines(p))

    # Test helpers: temp buffers for string construction + TOML source
    test_helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 4096 ALLOT  VARIABLE _UL',
        ': UR  0 _UL ! ;',
        ': UC  ( c -- ) _UB _UL @ + C!  1 _UL +! ;',
        ': UA  ( -- addr u ) _UB _UL @ ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines + test_helpers
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 1_500_000_000

    while steps < mx:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)

    text = uart_text(buf)

    # Check for compilation errors
    err_lines = [l for l in text.strip().split('\n')
                 if '?' in l and ('not found' in l.lower() or 'error' in l.lower()
                                  or 'abort' in l.lower())]
    if err_lines:
        print("[!] Possible compilation errors during snapshot build:")
        for ln in err_lines[-40:]:
            print(f"    {ln}")

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=50_000_000):
    """Run Forth lines from snapshot, return UART output text.

    max_steps provides a hard timeout to prevent infinite loops.
    """
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    # Re-boot to wire MMIO routing, then restore snapshot state
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    buf.clear()

    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode(); pos = 0; steps = 0

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    return uart_text(buf), steps


# ═══════════════════════════════════════════════════════════════════
#  Test framework
# ═══════════════════════════════════════════════════════════════════

_pass_count = 0
_fail_count = 0

def _normalize(raw: str) -> str:
    """Strip ANSI leftovers, prompts, ok tags."""
    raw = re.sub(r'\[\??\d+[hlJKm]', '', raw)
    raw = re.sub(r'\[\d*;\d*[Hfr]', '', raw)
    raw = re.sub(r'\[[\d;]*m', '', raw)
    raw = re.sub(r'\[H', '', raw)
    raw = re.sub(r'\[2J', '', raw)
    raw = re.sub(r'Megapad-64 Forth BIOS v[\d.]+', '', raw)
    raw = re.sub(r'RAM: [0-9a-fA-F]+ bytes', '', raw)
    lines = raw.split('\n')
    values = []
    for line in lines:
        line = line.strip()
        if line.startswith('> '):
            continue
        line = re.sub(r'\s+ok\s*$', '', line)
        if not line or line == 'Bye!' or line == '>' or line == 'ok':
            continue
        values.append(line)
    return ' '.join(values)


_STEP_LIMIT_FACTOR = 0.9  # warn if steps used > 90% of max

def check(name, forth_lines, expected=None, check_fn=None,
          not_expected=None, max_steps=50_000_000):
    global _pass_count, _fail_count
    output, steps_used = run_forth(forth_lines, max_steps=max_steps)
    clean = _normalize(output)

    timeout = steps_used >= max_steps
    if timeout:
        _fail_count += 1
        print(f"  TMOUT {name}  (hit {max_steps:,} step limit)")
        raw_last = output.strip().split('\n')[-8:]
        for l in raw_last:
            print(f"          {l!r}")
        return

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
        print(f"  PASS  {name}  ({steps_used:,} steps)")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        if not_expected is not None:
            print(f"        NOT expected: {not_expected!r}")
        print(f"        normalized: {clean!r}")
        raw_last = output.strip().split('\n')[-8:]
        print(f"        raw (last lines):")
        for l in raw_last:
            print(f"          {l!r}")


# Helper: build TOML string char-by-char in buffer T
def toml_str(s, buf='T'):
    """Build Forth lines that construct string s in _TB (T) or _UB (U)."""
    r = 'TR' if buf == 'T' else 'UR'
    c = 'TC' if buf == 'T' else 'UC'
    parts = [r]
    for ch in s:
        parts.append(f'{ord(ch)} {c}')
    # Break into lines of ~70 chars
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp == -1: sp = 70
        lines.append(full[:sp]); full = full[sp:].lstrip()
    if full: lines.append(full)
    return lines


# ═══════════════════════════════════════════════════════════════════
#  §1 — Compilation Smoke Test
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    """desk.f should compile without errors; key words should exist."""
    print("\n── §1: Compilation ──")
    check("words-exist", [
        "' DESK-LAUNCH  0<> .",
        "' DESK-CLOSE-ID  0<> .",
        "' DESK-RELAYOUT  0<> .",
        "' DESK-RUN  0<> .",
        "' DESK-LOAD-CONFIG  0<> .",
    ], expected='-1 -1 -1 -1 -1')


# ═══════════════════════════════════════════════════════════════════
#  §2 — Theme Defaults
# ═══════════════════════════════════════════════════════════════════

def test_theme_defaults():
    """Theme variables should hold default values after compilation."""
    print("\n── §2: Theme Defaults ──")
    check("tbar-fg-default", [
        '_DTH-TBAR-FG @ .',
    ], expected='15')

    check("tbar-bg-default", [
        '_DTH-TBAR-BG @ .',
    ], expected='17')

    check("act-fg-default", [
        '_DTH-ACT-FG @ .',
    ], expected='0')

    check("act-bg-default", [
        '_DTH-ACT-BG @ .',
    ], expected='12')

    check("div-fg-default", [
        '_DTH-DIV-FG @ .',
    ], expected='240')

    check("pin-fg-default", [
        '_DTH-PIN-FG @ .',
    ], expected='244')


# ═══════════════════════════════════════════════════════════════════
#  §3 — Theme TOML Loading
# ═══════════════════════════════════════════════════════════════════

def test_theme_loading():
    """_DESK-LOAD-THEME should parse [desk.theme] and update slots."""
    print("\n── §3: Theme TOML Loading ──")

    toml_src = '[desk.theme]\ntaskbar-fg = "red"\ntaskbar-bg = "#00ff00"\n'

    check("theme-load-taskbar-fg", toml_str(toml_src) + [
        'TA _DESK-LOAD-THEME',
        '_DTH-TBAR-FG @ .',
    ], expected='196')  # CSS "red" → xterm-256 index 196

    # After loading, other slots should remain at defaults
    check("theme-load-keeps-defaults", toml_str(toml_src) + [
        'TA _DESK-LOAD-THEME',
        '_DTH-ACT-FG @ .  _DTH-DIV-FG @ .',
    ], expected='0 240')

    # Empty config should not crash
    empty_toml = '# nothing here\n'
    check("theme-load-empty", toml_str(empty_toml) + [
        'TA _DESK-LOAD-THEME',
        '_DTH-TBAR-FG @ .',
    ], expected='15')  # should stay at default


# ═══════════════════════════════════════════════════════════════════
#  §4 — Hotbar TOML Loading
# ═══════════════════════════════════════════════════════════════════

def test_hotbar_loading():
    """_DESK-LOAD-HOTBAR should parse [[desk.hotbar]] entries."""
    print("\n── §4: Hotbar TOML Loading ──")

    toml_src = (
        '[[desk.hotbar]]\n'
        'label = "Pad"\n'
        'file = "pad.f"\n'
        'desc = "PAD-DESC"\n'
        '\n'
        '[[desk.hotbar]]\n'
        'label = "Files"\n'
        'file = "files.f"\n'
        'desc = "FILES-DESC"\n'
    )

    check("hotbar-count", toml_str(toml_src) + [
        'TA _DESK-LOAD-HOTBAR',
        '_DHBAR-COUNT @ .',
    ], expected='2')

    check("hotbar-label-0", toml_str(toml_src) + [
        'TA _DESK-LOAD-HOTBAR',
        '0 _HB-ENTRY DUP _HB-LBL-A + @ SWAP _HB-LBL-U + @ TYPE',
    ], expected='Pad')

    check("hotbar-file-1", toml_str(toml_src) + [
        'TA _DESK-LOAD-HOTBAR',
        '1 _HB-ENTRY DUP _HB-FILE-A + @ SWAP _HB-FILE-U + @ TYPE',
    ], expected='files.f')

    check("hotbar-slot-init-zero", toml_str(toml_src) + [
        'TA _DESK-LOAD-HOTBAR',
        '0 _HB-ENTRY _HB-SLOT + @ .',
        '1 _HB-ENTRY _HB-SLOT + @ .',
    ], expected='0 0')

    # No hotbar section → count should be 0
    empty = '[desk.theme]\ntaskbar-fg = "white"\n'
    check("hotbar-empty", toml_str(empty) + [
        'TA _DESK-LOAD-HOTBAR',
        '_DHBAR-COUNT @ .',
    ], expected='0')


# ═══════════════════════════════════════════════════════════════════
#  §5 — DESK-LOAD-CONFIG (combined)
# ═══════════════════════════════════════════════════════════════════

def test_load_config():
    """DESK-LOAD-CONFIG should load both theme and hotbar."""
    print("\n── §5: DESK-LOAD-CONFIG ──")

    toml_src = (
        '[desk.theme]\n'
        'divider-fg = "blue"\n'
        '\n'
        '[[desk.hotbar]]\n'
        'label = "App1"\n'
        'file = "app1.f"\n'
        'desc = "APP1-DESC"\n'
    )

    check("config-combined", toml_str(toml_src) + [
        'TA DESK-LOAD-CONFIG',
        '_DHBAR-COUNT @ .',
        # Verify divider-fg changed (blue → xterm ~21)
        '_DTH-DIV-FG @ 240 <> .',
    ], expected='1 -1')


# ═══════════════════════════════════════════════════════════════════
#  §6 — APP-DESC Descriptor
# ═══════════════════════════════════════════════════════════════════

def test_descriptor():
    """DESK-DESC should be fillable and have correct callbacks."""
    print("\n── §6: Descriptor ──")

    check("desc-fill", [
        '_DESK-FILL-DESC',
        'DESK-DESC APP.INIT-XT @ 0<> .',
        'DESK-DESC APP.EVENT-XT @ 0<> .',
        'DESK-DESC APP.TICK-XT @ 0<> .',
        'DESK-DESC APP.PAINT-XT @ 0<> .',
        'DESK-DESC APP.SHUTDOWN-XT @ 0<> .',
    ], expected='-1 -1 -1 -1 -1')

    check("desc-title", [
        '_DESK-FILL-DESC',
        'DESK-DESC APP.TITLE-A @ DESK-DESC APP.TITLE-U @ TYPE',
    ], expected='DESK')


# ═══════════════════════════════════════════════════════════════════
#  §7 — Lifecycle: init → quit
# ═══════════════════════════════════════════════════════════════════

def test_lifecycle():
    """DESK-RUN should init and shut down cleanly when app quits immediately."""
    print("\n── §7: Lifecycle ──")

    # Run DESK via ASHELL-RUN.  In INIT-CB we immediately quit.
    # We can't easily override DESK-INIT-CB, but we can test
    # that _DESK-FILL-DESC + ASHELL-RUN with a quit-immediately
    # event handler works.
    check("desk-run-quit", [
        # Patch the event callback to quit on first call
        'VARIABLE _DRQ-DONE  0 _DRQ-DONE !',
        ': _DRQ-INIT  ASHELL-QUIT ;',
        '_DESK-FILL-DESC',
        # Override init to quit immediately
        "' _DRQ-INIT DESK-DESC APP.INIT-XT !",
        'DESK-DESC ASHELL-RUN',
        '-1 _DRQ-DONE !',
        '_DRQ-DONE @ .',
    ], expected='-1', max_steps=80_000_000)


# ═══════════════════════════════════════════════════════════════════
#  §8 — Slot Management
# ═══════════════════════════════════════════════════════════════════

def test_slot_management():
    """DESK-LAUNCH / DESK-CLOSE-ID should create and destroy slots."""
    print("\n── §8: Slot Management ──")

    # Launch a minimal sub-app during desk init, check slot count,
    # then close it and quit.
    check("launch-and-close", [
        'VARIABLE _LC-SID  0 _LC-SID !',
        'VARIABLE _LC-CNT1  0 _LC-CNT1 !',
        'VARIABLE _LC-CNT2  0 _LC-CNT2 !',
        # Minimal sub-app descriptor
        'CREATE _LC-SUB APP-DESC ALLOT  _LC-SUB APP-DESC-INIT',
        'S" TST" _LC-SUB APP.TITLE-U !  _LC-SUB APP.TITLE-A !',
        # Desk init: launch sub-app, count, close, count, quit
        ': _LC-INIT',
        '    _LC-SUB DESK-LAUNCH _LC-SID !',
        '    DESK-SLOT-COUNT _LC-CNT1 !',
        '    _LC-SID @ DESK-CLOSE-ID',
        '    DESK-SLOT-COUNT _LC-CNT2 !',
        '    ASHELL-QUIT ;',
        '_DESK-FILL-DESC',
        "' _LC-INIT DESK-DESC APP.INIT-XT !",
        'DESK-DESC ASHELL-RUN',
        '_LC-SID @ .  _LC-CNT1 @ .  _LC-CNT2 @ .',
    ], expected='1 1 0', max_steps=80_000_000)


# ═══════════════════════════════════════════════════════════════════
#  §9 — Hotbar Slot Tracking
# ═══════════════════════════════════════════════════════════════════

def test_hotbar_slot_tracking():
    """_DESK-HOTBAR-MARK / _DESK-HOTBAR-SLOT-CLOSED should track slot IDs."""
    print("\n── §9: Hotbar Slot Tracking ──")

    check("mark-slot", [
        # Manually add a hotbar entry
        'S" Test" S" test.f" S" TEST-DESC" _DESK-HOTBAR-ADD',
        '_DHBAR-COUNT @ .',
        # Mark as running in slot 42
        '0 42 _DESK-HOTBAR-MARK',
        '0 _HB-ENTRY _HB-SLOT + @ .',
        # Close slot 42
        '42 _DESK-HOTBAR-SLOT-CLOSED',
        '0 _HB-ENTRY _HB-SLOT + @ .',
    ], expected='1 42 0')


# ═══════════════════════════════════════════════════════════════════
#  §10 — Config via _DESK-CFG-A/L (auto-load on init)
# ═══════════════════════════════════════════════════════════════════

def test_config_auto_load():
    """Setting _DESK-CFG-A/L before DESK-RUN should auto-load config."""
    print("\n── §10: Config Auto-Load ──")

    toml_src = (
        '[desk.theme]\n'
        'divider-fg = "#ff0000"\n'
    )

    check("cfg-auto-load", toml_str(toml_src) + [
        'TA _DESK-CFG-L !  _DESK-CFG-A !',
        'VARIABLE _CAL-VAL',
        ': _CAL-INIT',
        '    DESK-INIT-CB',
        '    _DTH-DIV-FG @ _CAL-VAL !',
        '    ASHELL-QUIT ;',
        '_DESK-FILL-DESC',
        "' _CAL-INIT DESK-DESC APP.INIT-XT !",
        'DESK-DESC ASHELL-RUN',
        # div-fg should have changed from default 240
        '_CAL-VAL @ 240 <> .',
    ], expected='-1', max_steps=80_000_000)


# ═══════════════════════════════════════════════════════════════════
#  Runner
# ═══════════════════════════════════════════════════════════════════

def main():
    global _pass_count, _fail_count

    build_snapshot()
    print()

    tests = [
        test_compilation,
        test_theme_defaults,
        test_theme_loading,
        test_hotbar_loading,
        test_load_config,
        test_descriptor,
        test_lifecycle,
        test_slot_management,
        test_hotbar_slot_tracking,
        test_config_auto_load,
    ]

    for test in tests:
        try:
            test()
        except Exception as e:
            _fail_count += 1
            import traceback
            print(f"  ERROR {test.__name__}: {e}")
            traceback.print_exc()

    print(f"\n{'='*60}")
    total = _pass_count + _fail_count
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    if _fail_count:
        print("  SOME TESTS FAILED")
    else:
        print("  ALL TESTS PASSED")
    print(f"{'='*60}")
    return 0 if _fail_count == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
