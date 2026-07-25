#!/usr/bin/env python3
"""Focused linked qualification for the bounded Streams SR2 runtime."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-sr2-runtime-contracts"
IMAGE = Path("/tmp/akashic-streams-sr2-runtime-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-sr2-runtime.f"

AUTOEXEC = r"""\ autoexec.f - bounded Streams SR2 runtime contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/execution-pool.f
REQUIRE local_testing/streams-sr2-runtime.f
_SR2R-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/streams/execution-pool.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS SR2 RUNTIME PASS",),
        stable_markers=("STREAMS SR2 RUNTIME PASS",),
        failure_markers=(
            "STREAMS SR2 RUNTIME FAIL",
            "STREAMS SR2 RUNTIME ASSERT",
            "STREAMS SR2 RUNTIME STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-sr2-runtime.f", CONTRACT.read_bytes()),
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
