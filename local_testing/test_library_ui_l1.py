#!/usr/bin/env python3
"""Focused source-loaded visible-key regression for the Library applet."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-ui-l1"
IMAGE = Path("/tmp/akashic-library-ui-l1.img")
FIXTURE = LOCAL_TESTING / "lib-ui-l1.f"

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/library.f
REQUIRE local_testing/lib-ui-l1.f
"""


def main() -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/library.f",),
        resources=("tui/applets/library/library.uidl",),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY UI L1 PASS",),
        stable_markers=("LIBRARY UI L1 PASS",),
        failure_markers=(
            "LIBRARY UI L1 FAIL",
            "LIBRARY UI L1 ASSERT",
            "LIBRARY UI L1 STACK",
            "DRIVER THROW",
            "EVALUATE depth limit exceeded",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/lib-ui-l1.f", FIXTURE.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=112,
        rows=32,
        # The source-loaded Library applet alone measures 3.56B steps on the
        # canonical scheduler; the visible-key exercise historically adds
        # about 0.6B.  Keep bounded headroom without changing guest timing.
        max_steps=5_000_000_000,
        timeout=120.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
