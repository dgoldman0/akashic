#!/usr/bin/env python3
"""Focused L12 Library metadata fact-stream contracts."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-metadata-l12-contracts"
IMAGE = Path("/tmp/akashic-library-metadata-l12-contracts.img")

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/model.f
REQUIRE local_testing/lib-metadata-l12-test.f
_LM12-RUN
"""


def main() -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/model.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY METADATA L12 PASS",),
        stable_markers=("LIBRARY METADATA L12 PASS",),
        failure_markers=(
            "LIBRARY METADATA L12 FAIL",
            "LIBRARY METADATA L12 ASSERT",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/lib-metadata-l12-test.f",
                (LOCAL_TESTING / "lib-metadata-l12-test.f").read_bytes(),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=2_000_000_000,
        timeout=30.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
