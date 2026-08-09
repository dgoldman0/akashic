#!/usr/bin/env python3
"""Source-loaded Checkpoint-1 Library capability create boundary."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-capability-create-boundary-l1"
IMAGE = Path("/tmp/akashic-library-capability-create-boundary-l1.img")
FIXTURE = LOCAL_TESTING / "lib-cap-l1.f"

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/library.f
REQUIRE local_testing/lib-cap-l1.f
_LC1-CREATE-BOUNDARY-RUN
"""


def main() -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/library.f",),
        resources=("tui/applets/library/library.uidl",),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY CAPABILITY CREATE BOUNDARY L1 PASS",),
        stable_markers=("LIBRARY CAPABILITY CREATE BOUNDARY L1 PASS",),
        failure_markers=(
            "LIBRARY CAPABILITY CREATE BOUNDARY L1 FAIL",
            "LIBRARY CAPABILITY L1 ASSERT",
            "LIBRARY CAPABILITY L1 STACK",
            "LIBRARY CAPABILITY L1 OUTER STACK",
            "LIBRARY CAPABILITY L1 STATUS",
            "DRIVER THROW",
            "EVALUATE depth limit exceeded",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/lib-cap-l1.f", FIXTURE.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=34,
        # This profile isolates the exact 4 KiB public create so the larger
        # read/materialization workload retains its independent step budget.
        max_steps=6_000_000_000,
        timeout=210.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
