#!/usr/bin/env python3
"""check-mode.f: every-frame checks are off until something turns them on."""

import pytest

import akashic_tui as packaging
from test_field_model import PRELUDE, run_field


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
