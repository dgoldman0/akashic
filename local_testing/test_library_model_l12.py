#!/usr/bin/env python3
"""Focused load check for the reentrant L12 Library model."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-model-l12"
IMAGE = Path("/tmp/akashic-library-model-l12.img")

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
-1 CONSTANT GUARDED
REQUIRE tui/applets/library/model.f
REQUIRE local_testing/library-model-l12.f
_L12M-RUN
"""


def main() -> int:
    model = (
        LOCAL_TESTING.parent / "akashic" / "tui" / "applets" / "library" / "model.f"
    ).read_text(encoding="utf-8")
    forbidden = (
        "CREATE _LIBM-PRIVATE",
        "VARIABLE _LIBM",
        "_lib-model-guard",
        "_libm-vfs-valid-xt",
        "WITH-GUARD",
    )
    present = tuple(token for token in forbidden if token in model)
    if present:
        raise AssertionError(f"mutable Library model validation state remains: {present}")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/library/model.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY MODEL L12 PASS",),
        stable_markers=("LIBRARY MODEL L12 PASS",),
        failure_markers=(
            "LIBRARY MODEL L12 FAIL",
            "LIBRARY MODEL L12 ASSERT",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=(
            (
                "local_testing/library-model-l12.f",
                (LOCAL_TESTING / "library-model-l12.f").read_bytes(),
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
        cols=100,
        rows=30,
        max_steps=2_000_000_000,
        timeout=30.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
