#!/usr/bin/env python3
"""Linked RAM-VFS qualification for the neutral persistence landing."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "persistence-storage-contracts"
IMAGE = Path("/tmp/akashic-persistence-storage-contracts.img")

CONTRACT_FILES = (
    "persist-page-test.f",
    "persist-segment-test.f",
    "persist-store-test.f",
    "library-persist-test.f",
    "library-index-keys.f",
)

AUTOEXEC = r'''\ autoexec.f - neutral persistence and Library slice contracts
ENTER-USERLAND
REQUIRE persistence/store.f
REQUIRE tui/applets/library/persistence-adapter.f
REQUIRE tui/applets/library/index-keys.f
REQUIRE local_testing/persist-page-test.f
REQUIRE local_testing/persist-segment-test.f
REQUIRE local_testing/persist-store-test.f
REQUIRE local_testing/library-persist-test.f
REQUIRE local_testing/library-index-keys.f
_PSC-RUN
_PSCT-RUN
_PSTC-RUN
_LPSC-RUN
_LIK-RUN
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    initial_files = tuple(
        (
            f"local_testing/{name}",
            (LOCAL_TESTING / name).read_bytes(),
        )
        for name in CONTRACT_FILES
    )
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "persistence/store.f",
            "tui/applets/library/persistence-adapter.f",
            "tui/applets/library/index-keys.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=(
            "PERSISTENCE PAGE PASS",
            "PERSISTENCE SEGMENT PASS",
            "PERSISTENCE STORE PASS",
            "LIBRARY PERSISTENCE SLICE PASS",
            "LIBRARY INDEX KEYS PASS",
        ),
        stable_markers=("LIBRARY INDEX KEYS PASS",),
        failure_markers=(
            "PERSISTENCE PAGE FAIL",
            "PERSISTENCE PAGE ASSERT",
            "PERSISTENCE PAGE STACK",
            "PERSISTENCE SEGMENT FAIL",
            "PERSISTENCE SEGMENT ASSERT",
            "PERSISTENCE SEGMENT STACK",
            "PERSISTENCE STORE FAIL",
            "PERSISTENCE STORE ASSERT",
            "PERSISTENCE STORE STACK",
            "LIBRARY PERSISTENCE SLICE FAIL",
            "LIBRARY PERSISTENCE SLICE ASSERT",
            "LIBRARY PERSISTENCE SLICE STACK",
            "LIBRARY INDEX KEYS FAIL",
            "LIBRARY INDEX KEY ASSERT",
            "LIBRARY INDEX KEY STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=initial_files,
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
        max_steps=12_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
