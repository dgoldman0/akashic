#!/usr/bin/env python3
"""Focused linked qualification for the L13 Streams root and key formats."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-l13-core-contracts"
IMAGE = Path("/tmp/akashic-streams-l13-core-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-l13-core.f"

AUTOEXEC = r"""\ autoexec.f - focused L13 Streams root/key contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/authority-root.f
REQUIRE tui/applets/streams/index-keys.f
REQUIRE tui/applets/streams/persistence-records.f
REQUIRE tui/applets/streams/index-record-agreement.f
REQUIRE tui/applets/streams/semantic-record-agreement.f
REQUIRE tui/applets/streams/persistence-adapter.f
REQUIRE local_testing/streams-l13-core.f
_SL13C-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "tui/applets/streams/authority-root.f",
            "tui/applets/streams/index-keys.f",
            "tui/applets/streams/persistence-records.f",
            "tui/applets/streams/index-record-agreement.f",
            "tui/applets/streams/semantic-record-agreement.f",
            "tui/applets/streams/persistence-adapter.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS L13 CORE PASS",),
        stable_markers=("STREAMS L13 CORE PASS",),
        failure_markers=(
            "STREAMS L13 CORE FAIL",
            "STREAMS L13 CORE ASSERT",
            "STREAMS L13 CORE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=(
            ("local_testing/streams-l13-core.f", CONTRACT.read_bytes()),
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
        max_steps=3_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
