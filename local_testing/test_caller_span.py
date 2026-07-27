#!/usr/bin/env python3
"""Focused linked qualification for checked caller-managed spans."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "checked-caller-span-contracts"
IMAGE = Path("/tmp/akashic-checked-caller-span-contracts.img")
CONTRACT = LOCAL_TESTING / "caller-span-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "utils" / "caller-span.f"

AUTOEXEC = r"""\ autoexec.f - checked caller-managed span contracts
ENTER-USERLAND
REQUIRE utils/caller-span.f
REQUIRE local_testing/caller-span-test.f
_CST-RUN
"""


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    executable = "\n".join(
        line for line in source.splitlines()
        if not line.lstrip().startswith("\\")
    )
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD(?:-BLOCKING)?)\b",
        executable,
    ), "caller-span wrapper must own no mutable state"
    assert (
        "' CALLER-SPAN-STATUS CONSTANT _caller-span-bios-xt"
        in source
    )
    assert "CALLER-SPAN-S-OK" in source
    assert "CALLER-SPAN-S-RANGE" in source
    assert "CALLER-SPAN-S-PROTECTED" in source
    assert "CALLER-SPAN-S-PLATFORM" in source
    assert re.search(
        r"(?m)^:\s+CALLER-SPAN-STATUS\b[\s\S]*?"
        r"\['] _CALLER-SPAN-BIOS-CALL CATCH[\s\S]*?"
        r"_CALLER-SPAN-BIOS>STATUS\s*;",
        source,
    )
    assert "RANDOM" not in executable
    assert "SHA2-SPAN-STATUS" not in executable
    assert "0xFFFF" not in executable


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("utils/caller-span.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("CALLER SPAN PASS",),
        stable_markers=("CALLER SPAN PASS",),
        failure_markers=(
            "CALLER SPAN FAIL",
            "CALLER SPAN ASSERT",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/caller-span-test.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=800_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
