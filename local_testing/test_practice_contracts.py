#!/usr/bin/env python3
"""The Practice activation's checked contracts as a test.

The ``practice-contracts`` profile in akashic_tui.py boots the runtime's
Practice closure alone and checks how an activation selects its durable
head, gives each component instance the places its descriptor needs, gives
a component with an id a home folder of its own where the activation's home
stands apart from the documents place, and narrows every place in recovery.
This file runs that profile with the limits ``akashic_tui.py smoke --profile
practice-contracts`` uses, so the test selection tool runs it whenever the
activation or a module it loads changes.  The harness writes its captures
(screen text, cells, PNG and the raw transcript) under ``OUTPUT_ROOT``, which
this test points at its own temporary folder.
"""

from __future__ import annotations

from pathlib import Path
import sys

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402

PROFILE_NAME = "practice-contracts"
# The smoke command's screen when none is named.
COLS, ROWS = 100, 32


def test_practice_contracts(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    image = harness.build_image(PROFILE_NAME, tmp_path / "practice-contracts.img")
    max_steps, timeout = harness._smoke_limits(PROFILE_NAME, None, None)
    assert harness.smoke(
        PROFILE_NAME,
        image,
        cols=COLS,
        rows=ROWS,
        max_steps=max_steps,
        timeout=timeout,
    )
