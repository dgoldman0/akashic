#!/usr/bin/env python3
"""Focused linked qualification for the allocation-free HTTP primitives."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "web-http-primitives-contracts"
IMAGE = Path("/tmp/akashic-web-http-primitives-contracts.img")
CONTRACT = LOCAL_TESTING / "web-http-primitives.f"

AUTOEXEC = r"""\ autoexec.f - focused allocation-free HTTP contracts
ENTER-USERLAND
REQUIRE web/http-request-stream.f
REQUIRE web/http-router-owner.f
REQUIRE web/http-response-writer.f
REQUIRE local_testing/web-http-primitives.f
_WHQ-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "web/http-request-stream.f",
            "web/http-router-owner.f",
            "web/http-response-writer.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("WEB HTTP PRIMITIVES PASS",),
        stable_markers=("WEB HTTP PRIMITIVES PASS",),
        failure_markers=(
            "WEB HTTP PRIMITIVES FAIL",
            "WEB HTTP PRIMITIVES ASSERT",
            "WEB HTTP PRIMITIVES STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/web-http-primitives.f", CONTRACT.read_bytes()),
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
