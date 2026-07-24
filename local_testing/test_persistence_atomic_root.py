#!/usr/bin/env python3
"""Focused RAM-VFS qualification for store root publication and mirroring."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "persistence-atomic-root-contracts"
IMAGE = Path("/tmp/akashic-persistence-atomic-root-contracts.img")

AUTOEXEC = r"""\ autoexec.f - focused atomic-root contracts
ENTER-USERLAND
REQUIRE persistence/store.f
REQUIRE local_testing/persist-store-test.f
_PSTC-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    contract = LOCAL_TESTING / "persist-store-test.f"
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("persistence/store.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("PERSISTENCE STORE PASS",),
        stable_markers=("PERSISTENCE STORE PASS",),
        failure_markers=(
            "PERSISTENCE STORE FAIL",
            "PERSISTENCE STORE ASSERT",
            "PERSISTENCE STORE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=(("local_testing/persist-store-test.f", contract.read_bytes()),),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=4_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
