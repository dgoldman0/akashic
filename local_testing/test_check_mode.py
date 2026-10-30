#!/usr/bin/env python3
"""check-mode.f: every-frame checks are off until something turns them on."""

import re
from pathlib import Path

import pytest

import akashic_tui as packaging
from test_field_model import PRELUDE, run_field

SOURCE = Path(__file__).resolve().parents[1] / "akashic"


def test_every_frame_checks_are_off_until_turned_on():
    run_field(PRELUDE + r'''
CHK-EVERY-FRAME? 0= _FM-A
-1 CHK-EVERY-FRAME ! CHK-EVERY-FRAME? _FM-A
0 CHK-EVERY-FRAME ! CHK-EVERY-FRAME? 0= _FM-A
\ Any nonzero cell is on.
5 CHK-EVERY-FRAME ! CHK-EVERY-FRAME? -1 = _FM-A
_FM-DONE
''', minimum=4, extra_sources=("tui/check-mode.f",))


def test_the_boot_option_follows_the_last_require():
    modules = (packaging.CHECK_MODE_MODULE,)
    autoexec = "ENTER-USERLAND\nREQUIRE a.f\nREQUIRE b.f\nDESK-RUN\n"
    assert packaging._with_every_frame_checks(autoexec, modules) == (
        "ENTER-USERLAND\nREQUIRE a.f\nREQUIRE b.f\n-1 CHK-EVERY-FRAME !\nDESK-RUN\n"
    )
    with pytest.raises(RuntimeError, match="tui/check-mode.f"):
        packaging._with_every_frame_checks(autoexec, ())
    with pytest.raises(RuntimeError, match="REQUIREs"):
        packaging._with_every_frame_checks("DESK-RUN\n", modules)


def test_the_rich_desktop_loads_the_switch():
    profile = packaging.PROFILES["desktop-apt1"]
    assert packaging.CHECK_MODE_MODULE in packaging.dependency_order(profile.roots)


def test_safe_mode_turns_on_once_and_runs_every_check():
    run_field(PRELUDE + r'''
CHK-SAFE? 0= _FM-A CHK-SAFE-MODE @ 0= _FM-A CHK-EVERY-FRAME? 0= _FM-A
\ No reason, no safe mode.
0 CHK-SAFE-ON CHK-SAFE? 0= _FM-A
CHK-WHY-BOOT CHK-SAFE-ON CHK-SAFE? _FM-A CHK-SAFE-MODE @ CHK-WHY-BOOT = _FM-A
\ Every check runs in safe mode, whatever the every-frame switch says.
CHK-EVERY-FRAME @ 0= _FM-A CHK-EVERY-FRAME? _FM-A
\ The first reason stays.
CHK-WHY-ANOMALY CHK-SAFE-ON CHK-SAFE-MODE @ CHK-WHY-BOOT = _FM-A
_FM-DONE
''', minimum=9, extra_sources=("tui/check-mode.f",))


def test_the_safe_mode_boot_option_follows_the_last_require():
    modules = (packaging.CHECK_MODE_MODULE,)
    autoexec = "ENTER-USERLAND\nREQUIRE a.f\nREQUIRE b.f\nDESK-RUN\n"
    assert packaging._with_safe_mode(autoexec, modules) == (
        "ENTER-USERLAND\nREQUIRE a.f\nREQUIRE b.f\nCHK-WHY-BOOT CHK-SAFE-ON\nDESK-RUN\n"
    )
    with pytest.raises(RuntimeError, match="tui/check-mode.f"):
        packaging._with_safe_mode(autoexec, ())


def test_a_failed_check_names_the_structure_it_found_damaged():
    run_field(PRELUDE + r'''
: T-FIRST  S" the first structure" ;
: T-SECOND  S" the second structure" ;
CHK-DAMAGE NIP 0= _FM-A CHK-DAMAGE-COUNT @ 0= _FM-A
\ A check that passes names nothing and keeps its flag.
-1 T-FIRST CHK-NAME -1 = _FM-A CHK-DAMAGE-COUNT @ 0= _FM-A
\ A check that fails names its structure and keeps its flag.
0 T-FIRST CHK-NAME 0= _FM-A CHK-DAMAGE-COUNT @ 1 = _FM-A
CHK-DAMAGE T-FIRST COMPARE 0= _FM-A
\ The first name stays, and the count grows with every check that names one.
0 T-SECOND CHK-NAME 0= _FM-A CHK-DAMAGE-COUNT @ 2 = _FM-A
CHK-DAMAGE T-FIRST COMPARE 0= _FM-A
T-SECOND CHK-DAMAGED CHK-DAMAGE-COUNT @ 3 = _FM-A
_FM-DONE
''', minimum=11, extra_sources=("tui/check-mode.f",))


def test_every_check_that_runs_only_with_every_check_on_names_its_structure():
    """A check that only every-frame checks or safe mode run can fail only
    after a bug wrote where it should not, so each one names what it found
    damaged."""
    words = []
    for path in sorted(SOURCE.rglob("*.f")):
        if path.name == "check-mode.f":
            continue
        text = re.sub(r"(?m)\\[^\n]*$", "", path.read_text())
        for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;[ \t]*$", text):
            if "CHK-EVERY-FRAME?" in match[0]:
                words.append((path.name, match[1], match[0]))
    assert len(words) >= 20
    for name, word, body in words:
        # Taking a seal is not a check: it records what a later check
        # compares, and that check names what it finds.
        if word == "_RTHP-BANK-SEAL-TAKE":
            continue
        # Deciding whether a capture holds its relation checks is not a
        # check either: it reads the switch so that with every check on the
        # relations are checked in every pass.
        if word == "_RUHA-B-HOLD?":
            continue
        # The shell's proved emission names through one helper of its own,
        # and the checks of a seal through the one that compares seals.
        assert ("CHK-NAME" in body or "_RTE-FDE-NAMED" in body
                or "_RTHP-SEAL-HOLDS?" in body), (name, word)


def test_a_failed_handover_proof_names_its_structure_and_turns_safe_mode_on():
    run_field(PRELUDE + r'''
: T-BANKS  S" the banks" ;
\ A proof that holds changes nothing.
-1 T-BANKS CHK-HANDOVER -1 = _FM-A CHK-SAFE? 0= _FM-A CHK-DAMAGE-COUNT @ 0= _FM-A
\ One that fails names the structure and turns safe mode on for an anomaly,
\ with every check.
0 T-BANKS CHK-HANDOVER 0= _FM-A CHK-SAFE? _FM-A CHK-EVERY-FRAME? _FM-A
CHK-SAFE-MODE @ CHK-WHY-ANOMALY = _FM-A
CHK-DAMAGE T-BANKS COMPARE 0= _FM-A CHK-DAMAGE-COUNT @ 1 = _FM-A
_FM-DONE
''', minimum=9, extra_sources=("tui/check-mode.f",))


def test_an_anomaly_keeps_the_reason_safe_mode_was_turned_on_for():
    run_field(PRELUDE + r'''
: T-BANKS  S" the banks" ;
CHK-WHY-BOOT CHK-SAFE-ON
T-BANKS CHK-ANOMALY
CHK-SAFE-MODE @ CHK-WHY-BOOT = _FM-A CHK-DAMAGE T-BANKS COMPARE 0= _FM-A
_FM-DONE
''', minimum=2, extra_sources=("tui/check-mode.f",))
