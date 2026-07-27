#!/usr/bin/env python3
"""Focused linked qualification for checked hardware entropy acquisition."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "checked-entropy-contracts"
IMAGE = Path("/tmp/akashic-checked-entropy-contracts.img")
CONTRACT = LOCAL_TESTING / "entropy-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "math" / "entropy.f"

AUTOEXEC = r"""\ autoexec.f - checked hardware entropy contracts
ENTER-USERLAND
REQUIRE math/entropy.f
REQUIRE local_testing/entropy-test.f
_ENTT-RUN
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
    ), "entropy wrapper must own no mutable state"
    assert "0xFFFFFF00000008" not in executable
    assert "RANDOM8" not in executable
    assert "SEED-RNG" not in executable
    assert "' ENTROPY-FILL   CONSTANT _entropy-bios-fill-xt" in source
    assert "' ENTROPY-READY? CONSTANT _entropy-bios-ready-xt" in source
    assert "ENTROPY-S-UNAVAILABLE" in source
    assert "ENTROPY-S-RANGE" in source
    assert "ENTROPY-S-PROTECTED" in source
    assert re.search(
        r"(?m)^:\s+ENTROPY-FILL\b[\s\S]*?"
        r"_entropy-bios-fill-xt EXECUTE\s*;",
        source,
    )
    assert re.search(
        r"(?m)^:\s+ENTROPY-READY\?(?=\s|\()[\s\S]*?"
        r"_entropy-bios-ready-xt EXECUTE\s*;",
        source,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/entropy.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("ENTROPY PASS",),
        stable_markers=("ENTROPY PASS",),
        failure_markers=(
            "ENTROPY FAIL",
            "ENTROPY ASSERT",
            "ENTROPY STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/entropy-test.f", CONTRACT.read_bytes()),
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
