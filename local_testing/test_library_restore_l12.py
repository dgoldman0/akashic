#!/usr/bin/env python3
"""Focused L12 contracts for zero-copy retained-content restore."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-retained-restore-l12"
IMAGE = Path("/tmp/akashic-library-retained-restore-l12.img")
GUEST_FIXTURE = "local_testing/lib-rest-l12.f"

AUTOEXEC = rf"""\ autoexec.f
ENTER-USERLAND
REQUIRE persistence/store.f
REQUIRE tui/applets/library/persistence-adapter.f
REQUIRE {GUEST_FIXTURE}
." LIBRARY RESTORE L12 START" CR
_LR12-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=360.0)
    args = parser.parse_args()

    fixture_name = Path(GUEST_FIXTURE).name
    if len(fixture_name) > 23:
        raise AssertionError(f"MP64FS fixture component is too long: {fixture_name}")

    adapter_source = (
        LOCAL_TESTING.parent
        / "akashic"
        / "tui"
        / "applets"
        / "library"
        / "persistence-adapter.f"
    ).read_text(encoding="utf-8")
    required = (
        "LIBPA-DOCUMENT-RESTORE-RETAINED-EXACT",
        "LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE",
        "_LIBPIX-RESTORED-BODY-CANDIDATES-ADD",
        "_LIBPIX-DOCUMENT-RESTORE-STAGE",
    )
    missing = tuple(token for token in required if token not in adapter_source)
    if missing:
        raise AssertionError(f"retained restore surface is incomplete: {missing}")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "persistence/store.f",
            "tui/applets/library/persistence-adapter.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY RESTORE L12 PASS",),
        stable_markers=("LIBRARY RESTORE L12 PASS",),
        failure_markers=(
            "LIBRARY RESTORE L12 FAIL",
            "LIBRARY RESTORE L12 ASSERT",
            "LIBRARY RESTORE L12 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=(
            (GUEST_FIXTURE, (LOCAL_TESTING / fixture_name).read_bytes()),
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
        rows=40,
        max_steps=25_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
