#!/usr/bin/env python3
"""Linked one-core qualification for Streams SR3 atomic admission."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-sr3-admission-contracts"
IMAGE = Path("/tmp/akashic-streams-sr3-admission-contracts.img")
CONTRACT = LOCAL_TESTING / "streams-sr3-admission.f"

AUTOEXEC = r"""\ autoexec.f - bounded Streams SR3 admission contracts
ENTER-USERLAND
REQUIRE tui/applets/streams/operational-spool.f
REQUIRE local_testing/streams-sr3-admission.f
_SR3A-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/streams/operational-spool.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("STREAMS SR3 ADMISSION PASS",),
        stable_markers=("STREAMS SR3 ADMISSION PASS",),
        failure_markers=(
            "STREAMS SR3 ADMISSION FAIL",
            "STREAMS SR3 ADMISSION ASSERT",
            "STREAMS SR3 ADMISSION STACK",
            "STREAMS SR3 ADMISSION API MISSING",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            (
                "local_testing/streams-sr3-admission.f",
                harness._minify_forth(
                    CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
        ),
        linked=True,
        link_chunk_bytes=192 * 1024,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=128,
        rows=44,
        max_steps=5_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
