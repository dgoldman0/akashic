#!/usr/bin/env python3
"""Source-loaded Checkpoint-1 Library capability read boundaries."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-capability-boundaries-l1"
IMAGE = Path("/tmp/akashic-library-capability-boundaries-l1.img")
WIRE_PROFILE = "library-wire-boundaries-l1"
WIRE_IMAGE = Path("/tmp/akashic-library-wire-boundaries-l1.img")
FIXTURE = LOCAL_TESTING / "lib-cap-l1.f"
MAX_STEPS = 10_000_000_000
DEFAULT_TIMEOUT = 330.0

BOUNDARY_AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/library.f
REQUIRE local_testing/lib-cap-l1.f
_LC1-BOUNDARY-RUN
"""

WIRE_AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/library.f
REQUIRE local_testing/lib-cap-l1.f
_LC1-WIRE-BOUND-RUN
"""


def _profile(autoexec: str, marker: str) -> harness.Profile:
    return harness.Profile(
        roots=("tui/applets/library/library.f",),
        resources=("tui/applets/library/library.uidl",),
        autoexec=autoexec,
        ready_markers=(marker,),
        stable_markers=(marker,),
        failure_markers=(
            "LIBRARY CAPABILITY BOUNDARY L1 FAIL",
            "LIBRARY WIRE BOUNDS FAIL",
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--wire",
        action="store_true",
        help="run only the Checkpoint-5 IVJSON maxima and bounded-decode gate",
    )
    parser.add_argument("--static-only", action="store_true")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    args = parser.parse_args()

    if args.wire:
        profile_name = WIRE_PROFILE
        image_path = WIRE_IMAGE
        autoexec = WIRE_AUTOEXEC
        marker = "LIBRARY WIRE BOUNDS PASS"
    else:
        profile_name = PROFILE
        image_path = IMAGE
        autoexec = BOUNDARY_AUTOEXEC
        marker = "LIBRARY CAPABILITY BOUNDARY L1 PASS"

    harness.PROFILES[profile_name] = _profile(autoexec, marker)
    if args.static_only:
        assert "_LC1-BOUNDARY-RUN" in BOUNDARY_AUTOEXEC
        assert "_LC1-WIRE-BOUND-RUN" not in BOUNDARY_AUTOEXEC
        assert "_LC1-WIRE-BOUND-RUN" in WIRE_AUTOEXEC
        assert "_LC1-BOUNDARY-RUN" not in WIRE_AUTOEXEC
        print("LIBRARY CAPABILITY BOUNDARY RUNNERS STATIC PASS")
        return 0

    image = harness.build_image(profile_name, image_path)
    ok = harness.smoke(
        profile_name,
        image,
        cols=120,
        rows=34,
        # The exact 4 KiB create has a separate runner.  This profile keeps
        # the 65,536/65,537 read and pagination work under its own ceiling.
        max_steps=MAX_STEPS,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
