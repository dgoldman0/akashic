#!/usr/bin/env python3
"""Test suite for Desk configuration (desk.f): theme and descriptor.

Desk's closure takes minutes to load natively, so the suite loads one
native machine (native_forth.py) and runs every check in it.  Desk keeps
its theme in per-instance state; each check points Desk at a freshly
zeroed state block and applies the theme defaults, so no check sees
another's state.

Desk's host lifecycle (launch, close, relayout, tiling, focus) runs a real
Desk in test_desk_shell_model.py.  EL-SET-* is tested in test_uidl.py and
the menubar layout in test_uidl_tui.py.
"""
import pytest

from native_forth import NativeForth

HELPERS = (
    'CREATE _TB 4096 ALLOT  VARIABLE _TL',
    ': TR  0 _TL ! ;',
    ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
    ': TA  ( -- addr u ) _TB _TL @ ;',
    # A state block of Desk's layout; T-DESK makes it current and fresh.
    '_DESK-STATE-SIZE ALLOCATE THROW CONSTANT _T-DS',
    ': T-DESK  ( -- )',
    '    _T-DS _DESK-STATE-SIZE 0 FILL  _T-DS _DESK-CURRENT-STATE !',
    '    _DESK-THEME-DEFAULTS ;',
)

# Desk's net modules use the constants MegaPad's networking module defines.
SUITE = NativeForth(("tui/applets/desk/desk.f",), system_modules=("networking.f",),
                    prelude=HELPERS, load_steps=1_500_000_000)


@pytest.fixture(scope="module")
def desk():
    return SUITE.shared()


def _text(raw):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in raw
    )


def check(machine, name, forth_lines, expected):
    clean = " ".join(_text(machine.run(forth_lines, 50_000_000)).split())
    assert expected in clean, f"{name}: expected {expected!r}, got: {clean[-400:]!r}"


# Helper: build TOML string char-by-char in _TB
def toml_str(s):
    """Build Forth lines that construct string s in _TB."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
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

def test_compilation(desk):
    """desk.f should compile without errors; key words should exist."""
    check(desk, "words-exist", [
        "' DESK-LAUNCH  0<> .",
        "' DESK-CLOSE-ID  0<> .",
        "' DESK-RELAYOUT  0<> .",
        "' DESK-RUN  0<> .",
        "' DESK-LOAD-CONFIG  0<> .",
    ], '-1 -1 -1 -1 -1')


# ═══════════════════════════════════════════════════════════════════
#  §2 — Theme Defaults
# ═══════════════════════════════════════════════════════════════════

def test_theme_defaults(desk):
    """The theme defaults fill a fresh Desk state."""
    check(desk, "theme-defaults", [
        'T-DESK',
        '_DTH-TBAR-FG @ .  _DTH-TBAR-BG @ .  _DTH-ACT-FG @ .',
        '_DTH-ACT-BG @ .  _DTH-DIV-FG @ .  _DTH-PIN-FG @ .',
    ], '15 17 0 12 240 244')


# ═══════════════════════════════════════════════════════════════════
#  §3 — Theme TOML Loading
# ═══════════════════════════════════════════════════════════════════

def test_theme_loading(desk):
    """_DESK-LOAD-THEME should parse [desk.theme] and update slots."""
    toml_src = '[desk.theme]\ntaskbar-fg = "red"\ntaskbar-bg = "#00ff00"\n'

    check(desk, "theme-load-taskbar-fg", ['T-DESK'] + toml_str(toml_src) + [
        'TA _DESK-LOAD-THEME',
        '_DTH-TBAR-FG @ .',
    ], '196')  # CSS "red" → xterm-256 index 196

    # After loading, other slots should remain at defaults
    check(desk, "theme-load-keeps-defaults", ['T-DESK'] + toml_str(toml_src) + [
        'TA _DESK-LOAD-THEME',
        '_DTH-ACT-FG @ .  _DTH-DIV-FG @ .',
    ], '0 240')

    # Empty config should not crash
    empty_toml = '# nothing here\n'
    check(desk, "theme-load-empty", ['T-DESK'] + toml_str(empty_toml) + [
        'TA _DESK-LOAD-THEME',
        '_DTH-TBAR-FG @ .',
    ], '15')  # should stay at default


# ═══════════════════════════════════════════════════════════════════
#  §4 — DESK-LOAD-CONFIG
# ═══════════════════════════════════════════════════════════════════

def test_load_config(desk):
    """DESK-LOAD-CONFIG should load the theme."""
    toml_src = '[desk.theme]\ndivider-fg = "blue"\n'

    check(desk, "config-theme", ['T-DESK'] + toml_str(toml_src) + [
        'TA DESK-LOAD-CONFIG',
        # Verify divider-fg changed (blue → xterm ~21)
        '_DTH-DIV-FG @ 240 <> .',
    ], '-1')


# ═══════════════════════════════════════════════════════════════════
#  §5 — APP-DESC Descriptor
# ═══════════════════════════════════════════════════════════════════

def test_descriptor(desk):
    """DESK-DESC should be fillable and have correct callbacks."""
    check(desk, "desc-fill", [
        '_DESK-FILL-DESC',
        'DESK-DESC APP.INIT-XT @ 0<> .',
        'DESK-DESC APP.EVENT-XT @ 0<> .',
        'DESK-DESC APP.TICK-XT @ 0<> .',
        'DESK-DESC APP.PAINT-XT @ 0<> .',
        'DESK-DESC APP.SHUTDOWN-XT @ 0<> .',
        'DESK-DESC APP-DESC-VALID? .',
    ], '-1 -1 -1 -1 -1 -1')

    check(desk, "desc-title", [
        '_DESK-FILL-DESC',
        'DESK-DESC APP.TITLE-A @ DESK-DESC APP.TITLE-U @ TYPE',
    ], 'DESK')
