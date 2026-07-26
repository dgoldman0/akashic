#!/usr/bin/env python3
"""Focused linked qualification for current Streams SR3 configuration bytes."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-sr3-config-record-contracts"
IMAGE = Path("/tmp/akashic-streams-sr3-config-record-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-sr3-config.f"

AUTOEXEC = r"""\ autoexec.f - Streams SR3 configuration record contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/operational-config-records.f
REQUIRE local_testing/streams-sr3-config.f
_SR3C-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "tui/applets/streams/operational-records.f",
            "tui/applets/streams/operational-config-records.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS SR3 CONFIG PASS",),
        stable_markers=("STREAMS SR3 CONFIG PASS",),
        failure_markers=(
            "STREAMS SR3 CONFIG FAIL",
            "STREAMS SR3 CONFIG ASSERT",
            "STREAMS SR3 CONFIG STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            (
                "local_testing/streams-sr3-config.f",
                CONTRACT.read_bytes(),
            ),
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
        max_steps=800_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
