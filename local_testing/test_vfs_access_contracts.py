#!/usr/bin/env python3
"""The scoped VFS access library's checked contracts as a test.

The ``vfs-access-contracts`` profile in akashic_tui.py boots the access
library (akashic/utils/fs/vfs-access.f) over a RAM volume and checks how a
scope borrows a volume and its current directory, owns one descriptor,
reads bounded ranges, and keeps a primary failure apart from cleanup
uncertainty.  This file runs that profile with the limits ``akashic_tui.py
smoke --profile vfs-access-contracts`` uses, so the test selection tool runs
it whenever the access library or a module it loads changes.  The harness
writes its captures under ``OUTPUT_ROOT``, which this test points at its own
temporary folder.
"""

from __future__ import annotations

from pathlib import Path
import sys

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402

PROFILE_NAME = "vfs-access-contracts"
# The smoke command's screen when none is named.
COLS, ROWS = 100, 32


def test_vfs_access_contracts(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    image = harness.build_image(PROFILE_NAME, tmp_path / "vfs-access-contracts.img")
    max_steps, timeout = harness._smoke_limits(PROFILE_NAME, None, None)
    assert harness.smoke(
        PROFILE_NAME,
        image,
        cols=COLS,
        rows=ROWS,
        max_steps=max_steps,
        timeout=timeout,
    )
