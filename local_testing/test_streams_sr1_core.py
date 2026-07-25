#!/usr/bin/env python3
"""Focused linked qualification for the storage-free Streams SR1 core."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-sr1-core-contracts"
IMAGE = Path("/tmp/akashic-streams-sr1-core-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-sr1-core.f"

AUTOEXEC = r"""\ autoexec.f - storage-free Streams SR1 core contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/flow-core.f
REQUIRE local_testing/streams-sr1-core.f
_SR1C-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/streams/flow-core.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS SR1 CORE PASS",),
        stable_markers=("STREAMS SR1 CORE PASS",),
        failure_markers=(
            "STREAMS SR1 CORE FAIL",
            "STREAMS SR1 CORE ASSERT",
            "STREAMS SR1 CORE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-sr1-core.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=1_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
