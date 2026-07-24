#!/usr/bin/env python3
"""Focused contracts for applet-local L12 Library document values."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-document-values-l12"
IMAGE = Path("/tmp/akashic-library-document-values-l12.img")

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/document-values.f
REQUIRE local_testing/lib-docval-l12.f
." LIBRARY DOCUMENT VALUES L12 START" CR
_LDV12-RUN
"""


def main() -> int:
    source = (
        LOCAL_TESTING.parent
        / "akashic"
        / "tui"
        / "applets"
        / "library"
        / "document-values.f"
    ).read_text(encoding="utf-8")
    forbidden = ("VARIABLE _LIBDV", "CREATE _LIBDV", "WITH-GUARD")
    present = tuple(token for token in forbidden if token in source)
    if present:
        raise AssertionError(f"mutable document-value state remains: {present}")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/document-values.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY DOCUMENT VALUES L12 PASS",),
        stable_markers=("LIBRARY DOCUMENT VALUES L12 PASS",),
        failure_markers=(
            "LIBRARY DOCUMENT VALUES L12 FAIL",
            "LIBRARY DOCUMENT VALUES L12 ASSERT",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/lib-docval-l12.f",
                (LOCAL_TESTING / "lib-document-values-l12-test.f").read_bytes(),
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
        cols=112,
        rows=32,
        max_steps=3_000_000_000,
        timeout=45.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
