#!/usr/bin/env python3
"""Focused single-process qualification for the L13 refresh owner."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-l13-refresh-owner-contracts"
IMAGE = Path("/tmp/akashic-streams-l13-refresh-owner-contracts.img")
APPLY_CONTRACT = LOCAL_TESTING / "streams-l13-apply.f"
OWNER_CONTRACT = LOCAL_TESTING / "streams-l13-refresh-owner.f"

AUTOEXEC = r"""\ autoexec.f - focused L13 repository refresh-owner contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/source-authority.f
REQUIRE tui/applets/streams/repository-refresh-owner.f
REQUIRE local_testing/streams-l13-apply.f
REQUIRE local_testing/streams-l13-rfowner.f
_SL13R-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=240.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "tui/applets/streams/source-authority.f",
            "tui/applets/streams/repository-refresh-owner.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS L13 REFRESH PASS",),
        stable_markers=("STREAMS L13 REFRESH PASS",),
        failure_markers=(
            "STREAMS L13 REFRESH FAIL",
            "STREAMS L13 REFRESH ASSERT",
            "STREAMS L13 REFRESH STACK",
            "STREAMS L13 APPLY ASSERT",
            "STREAMS L13 APPLY STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-l13-apply.f", APPLY_CONTRACT.read_bytes()),
            ("local_testing/streams-l13-rfowner.f", OWNER_CONTRACT.read_bytes()),
            ("srro-base.json", harness.SYNDICATION_JSON_FEED_BASE_FIXTURE),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=128,
        rows=42,
        max_steps=6_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
