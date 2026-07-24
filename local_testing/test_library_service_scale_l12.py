#!/usr/bin/env python3
"""Disposable public-service scale contracts for L12 collection membership."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-service-scale-l12-contracts"
IMAGE = Path("/tmp/akashic-library-service-scale-l12-contracts.img")

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/service.f
REQUIRE local_testing/lib-repo-l12-test.f
REQUIRE local_testing/lib-service-l12-test.f
REQUIRE local_testing/lib-svc-scale-l12.f
0 DROP
_LS12S-RUN
0 0xFFFFFF0000000006 C!
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/service.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY SERVICE SCALE L12 PASS",),
        stable_markers=("LIBRARY SERVICE SCALE L12 PASS",),
        failure_markers=(
            "LIBRARY SERVICE SCALE L12 FAIL",
            "LIBRARY SERVICE L12 ASSERT",
            "LIBRARY SERVICE L12 STACK",
            "LIBRARY REPOSITORY L12 ASSERT",
            "LIBRARY REPOSITORY L12 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/lib-repo-l12-test.f",
                (LOCAL_TESTING / "lib-repo-l12-test.f").read_bytes(),
            ),
            (
                "local_testing/lib-service-l12-test.f",
                (LOCAL_TESTING / "lib-service-l12-test.f").read_bytes(),
            ),
            (
                "local_testing/lib-svc-scale-l12.f",
                (LOCAL_TESTING / "lib-svc-scale-l12.f").read_bytes(),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=128,
        rows=42,
        max_steps=12_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
