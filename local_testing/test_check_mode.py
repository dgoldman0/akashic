#!/usr/bin/env python3
"""check-mode.f: every-frame checks are on until a composition turns them off."""

import pytest

import akashic_tui as packaging
from test_field_model import PRELUDE, run_field


def test_every_frame_checks_are_on_until_turned_off():
    run_field(PRELUDE + r'''
CHK-EVERY-FRAME? _FM-A
0 CHK-EVERY-FRAME ! CHK-EVERY-FRAME? 0= _FM-A
-1 CHK-EVERY-FRAME ! CHK-EVERY-FRAME? _FM-A
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
