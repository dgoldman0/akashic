#!/usr/bin/env python3
"""Focused linked qualification for caller-owned incremental SHA3-256."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "sha3-context-contracts"
IMAGE = Path("/tmp/akashic-sha3-context-contracts.img")
CONTRACT = LOCAL_TESTING / "sha3-context-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "math" / "sha3-context.f"

AUTOEXEC = r"""\ autoexec.f - caller-owned incremental SHA3-256 contracts
ENTER-USERLAND
REQUIRE math/sha3-context.f
REQUIRE math/sha3.f
REQUIRE local_testing/sha3-context-test.f
_S3CT-RUN
"""


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "incremental SHA3 must not own mutable module storage"
    assert "REQUIRE ../utils/memory-span.f" in source
    assert "REQUIRE sha3.f" not in source
    for word in (
        "SHA3-256-CONTEXT-SIZE",
        "SHA3-CONTEXT-S-HARDWARE",
        "SHA3-256-CONTEXT-VALID?",
        "SHA3-256-CONTEXT-INIT",
        "SHA3-256-CONTEXT-UPDATE",
        "SHA3-256-CONTEXT-FINAL",
        "SHA3-256-CONTEXT-FINAL-COMPARE",
    ):
        assert word in source
    for forbidden in ("_SHA3C.SELF", "_SHA3C.XT", "_SHA3C.CALLBACK"):
        assert forbidden not in source
    for removed_round_word in (
        "_SHA3C-THETA",
        "_SHA3C-RHO-PI-STEP",
        "_SHA3C-CHI",
        "_SHA3C-RC",
    ):
        assert removed_round_word not in source
    assert "DUP _SHA3C.STATE KECCAK-F1600" in source
    assert "DUP SHA3-256-CONTEXT-SIZE 0 FILL" in source


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/sha3-context.f", "math/sha3.f"),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("SHA3 CONTEXT PASS",),
        stable_markers=("SHA3 CONTEXT PASS",),
        failure_markers=(
            "SHA3 CONTEXT FAIL",
            "SHA3 CONTEXT ASSERT",
            "SHA3 CONTEXT STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/sha3-context-test.f", CONTRACT.read_bytes()),
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
