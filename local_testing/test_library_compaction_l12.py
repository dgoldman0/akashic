#!/usr/bin/env python3
"""Fresh-image semantic compaction contracts for the L12 Library adapter."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "library-compaction-l12-contracts"
IMAGE = Path("/tmp/akashic-library-compaction-l12-contracts.img")
CONTRACT = LOCAL_TESTING / "lib-comp-l12-test.f"

AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/persistence-adapter.f
REQUIRE local_testing/lib-comp-l12-test.f
_L12X-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    # Wall-clock guard only; the step budget bounds the run.  The contracts
    # took about 171 s on a 256 MiB machine on 2026-11-22.
    parser.add_argument("--timeout", type=float, default=360.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        # The fixture's RAM volume takes a 64 MiB arena.  KDOS gives half
        # the machine's extended memory to the dictionary, so a 128 MiB
        # machine leaves about 62 MiB for everything else.
        default_ext_mem_mib=256,
        roots=("tui/applets/library/persistence-adapter.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("LIBRARY COMPACTION L12 PASS",),
        stable_markers=("LIBRARY COMPACTION L12 PASS",),
        failure_markers=(
            "LIBRARY COMPACTION L12 FAIL",
            "LIBRARY COMPACTION L12 ASSERT",
            "DRIVER THROW",
            " ? (not found)",
            "dictionary full",
            "exception",
        ),
        initial_files=(
            ("local_testing/lib-comp-l12-test.f", CONTRACT.read_bytes()),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=24_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


def test_contracts(tmp_path: Path, monkeypatch) -> None:
    """The contracts as a test, so the test selection tool runs them."""
    from contract_script import run_as_test

    run_as_test(sys.modules[__name__], tmp_path, monkeypatch)


if __name__ == "__main__":
    raise SystemExit(main())
