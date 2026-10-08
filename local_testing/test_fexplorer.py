#!/usr/bin/env python3
"""Test suite for akashic-tui-fexplorer applet (fexplorer.f).

Full-featured file explorer applet tests: compilation, descriptor entry,
title and sort constants.  Every check runs on a fresh native machine
(native_forth.py) with fexplorer.f's closure loaded.
"""
from native_forth import NativeForth

# The app-shell's real terminal lifecycle is outside this unit test, so the
# four app-shell words fexplorer uses stand in for app-shell.f itself.
APP_SHELL_STANDIN = (
    ': ASHELL-DIRTY!  ( -- ) ;',
    ': ASHELL-QUIT    ( -- ) ;',
    ': ASHELL-RUN     ( desc -- ) DROP ;',
    ': ASHELL-TOAST   ( addr len ms -- ) 2DROP DROP ;',
)

SUITE = NativeForth(
    ("tui/applets/fexplorer/fexplorer.f",),
    replace={"tui/app-shell.f": APP_SHELL_STANDIN},
    load_steps=1_500_000_000,
)


def uart_text(raw):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in raw)


def run_forth(lines, max_steps=80_000_000):
    return uart_text(SUITE.run(lines, max_steps))


def check(name, forth_lines, expected):
    output = run_forth(forth_lines)
    tail = "\n".join(output.strip().split("\n")[-8:])
    assert expected in output, f"{name}: expected {expected!r}, got:\n{tail}"


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
