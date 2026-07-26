#!/usr/bin/env python3
"""Focused successor contracts for the L12 Library persistence adapter."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-persistence-l12-contracts"
IMAGE = Path("/tmp/akashic-library-persistence-l12-contracts.img")

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE persistence/store.f
REQUIRE tui/applets/library/persistence-adapter.f
REQUIRE local_testing/lib-persist-l12-test.f
_L12P-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "persistence/store.f",
            "tui/applets/library/persistence-adapter.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY PERSISTENCE L12 PASS",),
        stable_markers=("LIBRARY PERSISTENCE L12 PASS",),
        failure_markers=(
            "LIBRARY PERSISTENCE L12 FAIL",
            "LIBRARY PERSISTENCE L12 ASSERT",
            "LIBRARY PERSISTENCE L12 STACK",
            "DRIVER THROW",
            " ? (not found)",
            "dictionary full",
            "exception",
        ),
        initial_files=(
            (
                "local_testing/lib-persist-l12-test.f",
                (LOCAL_TESTING / "lib-persist-l12-test.f").read_bytes(),
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
        cols=120,
        rows=40,
        max_steps=10_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
