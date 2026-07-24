#!/usr/bin/env python3
"""Linked qualification for Library-owned ordered persistence keys."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-index-key-contracts"
IMAGE = Path("/tmp/akashic-library-index-key-contracts.img")
CONTRACT = LOCAL_TESTING / "library-index-keys.f"

AUTOEXEC = r'''\ autoexec.f - Library-owned ordered persistence keys
ENTER-USERLAND
REQUIRE tui/applets/library/index-keys.f
REQUIRE local_testing/library-index-keys.f
_LIK-RUN
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/index-keys.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY INDEX KEYS PASS",),
        stable_markers=("LIBRARY INDEX KEYS PASS",),
        failure_markers=(
            "LIBRARY INDEX KEYS FAIL",
            "LIBRARY INDEX KEY ASSERT",
            "LIBRARY INDEX KEY STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=(
            ("local_testing/library-index-keys.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=8_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
