#!/usr/bin/env python3
"""Focused single-process qualification for the L13 apply authority."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-l13-apply-contracts"
IMAGE = Path("/tmp/akashic-streams-l13-apply-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-l13-apply.f"

AUTOEXEC = r"""\ autoexec.f - focused L13 apply authority contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/source-authority.f
REQUIRE tui/applets/streams/acquisition-authority.f
REQUIRE tui/applets/streams/apply-authority.f
REQUIRE local_testing/streams-l13-apply.f
_SL13P-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=240.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "tui/applets/streams/source-authority.f",
            "tui/applets/streams/acquisition-authority.f",
            "tui/applets/streams/apply-authority.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS L13 APPLY PASS",),
        stable_markers=("STREAMS L13 APPLY PASS",),
        failure_markers=(
            "STREAMS L13 APPLY FAIL",
            "STREAMS L13 APPLY ASSERT",
            "STREAMS L13 APPLY STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-l13-apply.f", CONTRACT.read_bytes()),
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
