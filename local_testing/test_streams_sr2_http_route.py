#!/usr/bin/env python3
"""Focused linked qualification for the Streams SR2 HTTP route."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-sr2-http-route-contracts"
IMAGE = Path("/tmp/akashic-streams-sr2-http-route-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-sr2-http.f"

AUTOEXEC = r"""\ autoexec.f - bounded Streams SR2 HTTP route contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/http-route.f
REQUIRE local_testing/streams-sr2-http.f
_SR2H-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/streams/http-route.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS SR2 HTTP ROUTE PASS",),
        stable_markers=("STREAMS SR2 HTTP ROUTE PASS",),
        failure_markers=(
            "STREAMS SR2 HTTP ROUTE FAIL",
            "STREAMS SR2 HTTP ROUTE ASSERT",
            "STREAMS SR2 HTTP ROUTE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-sr2-http.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=128,
        rows=42,
        max_steps=1_200_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
