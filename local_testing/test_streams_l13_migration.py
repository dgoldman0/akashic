#!/usr/bin/env python3
"""Bounded, single-process qualification for the L13 cold migration."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-l13-migration-contracts"
IMAGE = Path("/tmp/akashic-streams-l13-migration-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-l13-migrate.f"

AUTOEXEC = r"""\ autoexec.f - bounded L13 cold migration contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/migration.f
REQUIRE local_testing/streams-l13-migrate.f
_SL13M-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=240.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/streams/migration.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS L13 MIGRATION PASS",),
        stable_markers=("STREAMS L13 MIGRATION PASS",),
        failure_markers=(
            "STREAMS L13 MIGRATION FAIL",
            "STREAMS L13 MIGRATION ASSERT",
            "STREAMS L13 MIGRATION STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/streams-l13-migrate.f", CONTRACT.read_bytes()),
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
        max_steps=4_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
