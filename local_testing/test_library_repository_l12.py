#!/usr/bin/env python3
"""Focused contracts for the L12 Desk/Library repository owner."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-repository-l12-contracts"
IMAGE = Path("/tmp/akashic-library-repository-l12-contracts.img")

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/repository.f
REQUIRE local_testing/lib-repo-l12-test.f
0 DROP
_LR12-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/repository.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY REPOSITORY L12 PASS",),
        stable_markers=("LIBRARY REPOSITORY L12 PASS",),
        failure_markers=(
            "LIBRARY REPOSITORY L12 FAIL",
            "LIBRARY REPOSITORY L12 ASSERT",
            "LIBRARY REPOSITORY L12 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/lib-repo-l12-test.f",
                (LOCAL_TESTING / "lib-repo-l12-test.f").read_bytes(),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=128,
        rows=42,
        max_steps=10_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
