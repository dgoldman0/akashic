#!/usr/bin/env python3
"""The applet manifest's checked contracts as a test.

The ``manifest-contracts`` profile in akashic_tui.py boots the manifest
reader (akashic/tui/app-manifest.f) and checks how a project manifest and an
installed manifest parse and validate: ids, titles, entries, source and
image paths and digests, sizes, and the refusals of bad trust, bad paths,
bad types and missing fields.  This file runs that profile with the limits
``akashic_tui.py smoke --profile manifest-contracts`` uses, so the test
selection tool runs it whenever the manifest reader or a module it loads
changes.  The harness writes its captures under ``OUTPUT_ROOT``, which this
test points at its own temporary folder.
"""

from __future__ import annotations

from pathlib import Path
import sys

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402

PROFILE_NAME = "manifest-contracts"
# The smoke command's screen when none is named.
COLS, ROWS = 100, 32


def test_manifest_contracts(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    image = harness.build_image(PROFILE_NAME, tmp_path / "manifest-contracts.img")
    max_steps, timeout = harness._smoke_limits(PROFILE_NAME, None, None)
    assert harness.smoke(
        PROFILE_NAME,
        image,
        cols=COLS,
        rows=ROWS,
        max_steps=max_steps,
        timeout=timeout,
    )
