#!/usr/bin/env python3
"""Focused single-process qualification for the L13 Streams repository."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-l13-repository-contracts"
IMAGE = Path("/tmp/akashic-streams-l13-repository-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-l13-repo.f"

AUTOEXEC = r"""\ autoexec.f - focused L13 Streams repository contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/source-authority.f
REQUIRE tui/applets/streams/query.f
REQUIRE local_testing/streams-l13-repo.f
_SL13R-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "tui/applets/streams/source-authority.f",
            "tui/applets/streams/query.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS L13 REPOSITORY PASS",),
        stable_markers=("STREAMS L13 REPOSITORY PASS",),
        failure_markers=(
            "STREAMS L13 REPOSITORY FAIL",
            "STREAMS L13 REPOSITORY ASSERT",
            "STREAMS L13 REPOSITORY STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-l13-repo.f", CONTRACT.read_bytes()),
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
        max_steps=4_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
