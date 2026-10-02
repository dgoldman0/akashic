#!/usr/bin/env python3
"""Test suite for akashic/utils/term.f — Terminal Geometry Utilities.

Tests the TERM- prefix wrapper words and derived geometry utilities.
Every check runs on a fresh native machine (native_forth.py) whose hosted
terminal geometry is set for that check.

Sections:
  A (1-3)   Compilation & basic reads
  B (1-6)   Derived geometry words
  C (1-4)   RESIZED? / change detection
  D (1-3)   Integration: app.f auto-size

The BIOS resize request words (RESIZE-REQUEST, RESIZE-DENIED?) are tested
in MegaPad's tests/simulator/test_bios_terminal_geometry.py.
"""
import re

from native_forth import NativeForth

TERM = NativeForth(("utils/term.f",))
TUI = NativeForth(("utils/term.f", "tui/app.f"))


def _text(raw):
    text = "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in raw
    )
    return re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', text)


def run_term_forth(lines, cols=80, rows=24, max_steps=80_000_000, host_resize=None):
    """Run Forth lines over term.f with specific terminal dimensions."""
    return _text(TERM.run(lines, max_steps, cols=cols, rows=rows,
                          host_resize=host_resize))


def run_tui_forth(lines, cols=80, rows=24, max_steps=80_000_000):
    """Run Forth lines over app.f with specific terminal dimensions."""
    return _text(TUI.run(lines, max_steps, cols=cols, rows=rows))


def check(tag, text, expected):
    assert expected in text, f"{tag}: expected {expected!r}, got:\n{text[-400:]}"

# ═══════════════════════════════════════════════════════════════════
#  Section A — Compilation & Basic Reads
# ═══════════════════════════════════════════════════════════════════

def test_section_A():
    # A1: term.f compiles without error
    text = run_term_forth([
        '." R=TERM-OK"'
    ], cols=80, rows=24)
    check("A1 compilation", text, "R=TERM-OK")

    # A2: TERM-W reads correct column count
    text = run_term_forth([
        'TERM-W ." R=W=" .',
    ], cols=100, rows=30)
    check("A2 TERM-W", text, "R=W=100")

    # A3: TERM-H reads correct row count
    text = run_term_forth([
        'TERM-H ." R=H=" .',
    ], cols=100, rows=30)
    check("A3 TERM-H", text, "R=H=30")

# ═══════════════════════════════════════════════════════════════════
#  Section B — Derived Geometry Words
# ═══════════════════════════════════════════════════════════════════

def test_section_B():
    # B1: TERM-SIZE returns w h
    text = run_term_forth([
        'TERM-SIZE ." R=SZ=" . ." ," .',
    ], cols=120, rows=40)
    check("B1 TERM-SIZE", text, "R=SZ=40 ,120")

    # B2: TERM-AREA returns w*h
    text = run_term_forth([
        'TERM-AREA ." R=AREA=" .',
    ], cols=80, rows=25)
    check("B2 TERM-AREA", text, "R=AREA=2000")

    # B3: TERM-FIT? — fits
    text = run_term_forth([
        '60 20 TERM-FIT? ." R=FIT=" .',
    ], cols=80, rows=24)
    check("B3 TERM-FIT? yes", text, "R=FIT=-1")

    # B4: TERM-FIT? — does not fit (too wide)
    text = run_term_forth([
        '100 20 TERM-FIT? ." R=FIT=" .',
    ], cols=80, rows=24)
    check("B4 TERM-FIT? no", text, "R=FIT=0")

    # B5: TERM-CLAMP
    text = run_term_forth([
        '200 100 TERM-CLAMP ." R=CL=" . ." ," .',
    ], cols=80, rows=24)
    check("B5 TERM-CLAMP", text, "R=CL=24 ,80")

    # B6: TERM-CENTER
    text = run_term_forth([
        '20 10 TERM-CENTER ." R=CTR=" . ." ," .',
    ], cols=80, rows=24)
    # col = (80-20)/2 = 30, row = (24-10)/2 = 7
    check("B6 TERM-CENTER", text, "R=CTR=7 ,30")

# ═══════════════════════════════════════════════════════════════════
#  Section C — RESIZED? / Change Detection
# ═══════════════════════════════════════════════════════════════════

def test_section_C():
    # C1: TERM-RESIZED? returns FALSE when no resize happened
    text = run_term_forth([
        'TERM-RESIZED? ." R=RSZ=" .',
    ], cols=80, rows=24)
    check("C1 RESIZED? no", text, "R=RSZ=0")

    # C2: TERM-RESIZED? returns TRUE after the host resized the terminal
    text = run_term_forth([
        'TERM-RESIZED? ." R=RSZ=" .',
    ], cols=80, rows=24, host_resize=(120, 40))
    # Any nonzero value is TRUE.
    m = re.search(r'R=RSZ=(-?\d+)', text)
    assert m and int(m.group(1)) != 0, f"C2 RESIZED? yes: got {text[-200:]!r}"

    # C3: RESIZED? clears after read (second call returns FALSE)
    text = run_term_forth([
        'TERM-RESIZED? DROP TERM-RESIZED? ." R=RSZ2=" .',
    ], cols=80, rows=24, host_resize=(100, 50))
    check("C3 RESIZED? clears", text, "R=RSZ2=0")

    # C4: TERM-CHANGED? detects size difference
    text = run_term_forth([
        '80 24 TERM-SAVE',
        '2DROP',
        '80 24 TERM-CHANGED? ." R=CHG1=" .',
        '90 30 TERM-CHANGED? ." R=CHG2=" .',
    ], cols=80, rows=24)
    # CHG1: 80==80 and 24==24 → FALSE; CHG2: 90!=80 → TRUE
    check("C4 TERM-CHANGED?", text, "R=CHG1=0")
    check("C4 TERM-CHANGED? diff", text, "R=CHG2=-1")

# ═══════════════════════════════════════════════════════════════════
#  Section D — Integration: app.f
# ═══════════════════════════════════════════════════════════════════

def test_section_D():
    # D1: TUI stack compiles with term.f dependency
    text = run_tui_forth([
        '." R=TUI-OK"',
    ], cols=80, rows=24)
    check("D1 TUI+term compile", text, "R=TUI-OK")

    # D2: APP-INIT with 0 0 auto-sizes from TERM-SIZE
    # We can't run the full event loop, but we can call APP-INIT
    # and check APP-SIZE returns the hardware dimensions.
    text = run_tui_forth([
        '0 0 APP-INIT',
        'APP-SIZE ." R=ASZ=" . ." ," .',
        'APP-SHUTDOWN',
    ], cols=100, rows=35)
    check("D2 APP-INIT auto-size", text, "R=ASZ=35 ,100")

    # D3: APP-INIT with explicit size still works
    text = run_tui_forth([
        '60 20 APP-INIT',
        'APP-SIZE ." R=ASZ=" . ." ," .',
        'APP-SHUTDOWN',
    ], cols=100, rows=35)
    check("D3 APP-INIT explicit", text, "R=ASZ=20 ,60")
