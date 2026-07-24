#!/usr/bin/env python3
"""Focused linked qualification for exact L13 legacy migration evidence."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-l13-evidence-contracts"
IMAGE = Path("/tmp/akashic-streams-l13-evidence-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-l13-evidence.f"

AUTOEXEC = r"""\ autoexec.f - exact L13 legacy migration evidence
ENTER-USERLAND
REQUIRE tui/applets/streams/source-store.f
REQUIRE tui/applets/streams/observation-store.f
REQUIRE local_testing/streams-l13-evidence.f
_SL13E-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "tui/applets/streams/source-store.f",
            "tui/applets/streams/observation-store.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS L13 EVIDENCE PASS",),
        stable_markers=("STREAMS L13 EVIDENCE PASS",),
        failure_markers=(
            "STREAMS L13 EVIDENCE FAIL",
            "STREAMS L13 EVIDENCE ASSERT",
            "STREAMS L13 EVIDENCE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-l13-evidence.f", CONTRACT.read_bytes()),
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
        max_steps=1_500_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
