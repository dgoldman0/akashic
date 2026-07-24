#!/usr/bin/env python3
"""Focused RAM-VFS qualification for neutral two-bank compaction."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "persistence-compaction-contracts"
IMAGE = Path("/tmp/akashic-persistence-compaction-contracts.img")

AUTOEXEC = r"""\ autoexec.f - focused neutral compaction contracts
ENTER-USERLAND
REQUIRE persistence/compaction.f
REQUIRE persistence/btree.f
REQUIRE persistence/reclaim.f
REQUIRE local_testing/persist-compact-test.f
_PCCT-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=150.0)
    args = parser.parse_args()

    contract = LOCAL_TESTING / "persist-compact-test.f"
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "persistence/compaction.f",
            "persistence/btree.f",
            "persistence/reclaim.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("PERSISTENCE COMPACTION PASS",),
        stable_markers=("PERSISTENCE COMPACTION PASS",),
        failure_markers=(
            "PERSISTENCE COMPACTION FAIL",
            "PERSISTENCE COMPACTION ASSERT",
            "PERSISTENCE COMPACTION STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=(("local_testing/persist-compact-test.f", contract.read_bytes()),),
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
