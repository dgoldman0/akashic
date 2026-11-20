#!/usr/bin/env python3
"""The generation pair's checked contracts as a test.

The ``generation-pair-contracts`` profile in akashic_tui.py boots
``utils/generation-pair.f`` alone and checks how a pair classifies its two
candidates, selects among them, publishes into the inactive slot and guards
its descriptors.  Every two-slot store builds on it: the persistence root
that Streams and Library share, the Agent's conversation store and the
Practice head.  This file runs that profile with the limits ``akashic_tui.py
smoke --profile generation-pair-contracts`` uses, so the test selection tool
runs it whenever the pair or a module it loads changes.  The harness writes
its captures (screen text, cells, PNG and the raw transcript) under
``OUTPUT_ROOT``, which this test points at its own temporary folder.
"""

from __future__ import annotations

from pathlib import Path
import sys

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402

PROFILE_NAME = "generation-pair-contracts"
# The smoke command's screen when none is named.
COLS, ROWS = 100, 32


def test_generation_pair_contracts(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    image = harness.build_image(
        PROFILE_NAME, tmp_path / "generation-pair-contracts.img"
    )
    max_steps, timeout = harness._smoke_limits(PROFILE_NAME, None, None)
    assert harness.smoke(
        PROFILE_NAME,
        image,
        cols=COLS,
        rows=ROWS,
        max_steps=max_steps,
        timeout=timeout,
    )
