#!/usr/bin/env python3
"""Source-loaded Checkpoint-1 Library capability and owner contracts."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-capability-l1"
IMAGE = Path("/tmp/akashic-library-capability-l1.img")
FIXTURE = LOCAL_TESTING / "lib-cap-l1.f"

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/library.f
REQUIRE local_testing/lib-cap-l1.f
_LC1-RUN
"""


def main() -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/library.f",),
        resources=("tui/applets/library/library.uidl",),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY CAPABILITY L1 PASS",),
        stable_markers=("LIBRARY CAPABILITY L1 PASS",),
        failure_markers=(
            "LIBRARY CAPABILITY L1 FAIL",
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
        # The applet alone measures 3.558B steps.  Existing retained-restore
        # evidence for the 65,537-byte path measures 6.253B; this combined
        # first-run ceiling is provisional and will be tightened from its
        # first passing measurement rather than treated as product capacity.
        max_steps=10_000_000_000,
        # At timing-correct emulator speed, a green candidate reached the
        # replacement/tombstone phase at 7.863B steps when the provisional
        # 240-second wall expired.  This wall allowance lets the unchanged
        # 10B step ceiling govern the run; it does not alter emulator timing.
        timeout=330.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
