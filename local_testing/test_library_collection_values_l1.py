#!/usr/bin/env python3
"""Focused source contracts for pure Library collection preparation."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-collection-values-l1"
IMAGE = Path("/tmp/akashic-library-collection-values-l1.img")
CONTRACT = LOCAL_TESTING / "lib-collval-l1.f"

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/collection-values.f
REQUIRE local_testing/lib-collval-l1.f
." LIBRARY COLLECTION VALUES L1 START" CR
_LCV1-RUN
"""


def main() -> int:
    source = (
        LOCAL_TESTING.parent
        / "akashic"
        / "tui"
        / "applets"
        / "library"
        / "collection-values.f"
    ).read_text(encoding="utf-8")
    forbidden = ("VARIABLE _LIBCV", "CREATE _LIBCV", "WITH-GUARD")
    present = tuple(token for token in forbidden if token in source)
    if present:
        raise AssertionError(f"mutable collection-value state remains: {present}")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/collection-values.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY COLLECTION VALUES L1 PASS",),
        stable_markers=("LIBRARY COLLECTION VALUES L1 PASS",),
        failure_markers=(
            "LIBRARY COLLECTION VALUES L1 FAIL",
            "LIBRARY COLLECTION VALUES L1 ASSERT",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/lib-collval-l1.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=112,
        rows=32,
        max_steps=750_000_000,
        timeout=45.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
