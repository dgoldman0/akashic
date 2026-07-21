#!/usr/bin/env python3
"""Focused L7 Agent controller-action and access-policy contracts."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "agent-provider-ui-commands"


def test_l7_agent_action_contracts(tmp_path: Path) -> None:
    assert PROFILE_NAME in PROFILES
    image = build_image(PROFILE_NAME, tmp_path / "l7-agent-actions.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=5_000_000_000,
        timeout=180.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_l7_agent_action_contracts(Path(directory))
