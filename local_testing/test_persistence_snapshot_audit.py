#!/usr/bin/env python3
"""Focused linked qualification for A/B snapshot and B+tree cold auditing."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "persistence-snapshot-audit-contracts"
IMAGE = Path("/tmp/akashic-persistence-snapshot-audit-contracts.img")
BTREE_CONTRACT = LOCAL_TESTING / "persist-btree-test.f"
AUDIT_CONTRACT = LOCAL_TESTING / "persist-snap-audit.f"

AUTOEXEC = r"""\ autoexec.f - focused immutable snapshot audit contracts
ENTER-USERLAND
REQUIRE persistence/btree.f
REQUIRE local_testing/persist-btree-test.f
REQUIRE local_testing/persist-snap-audit.f
_PBTSA-RUN
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    # Wall-clock guard only; the step budget below bounds the run.  The
    # contracts took about 83 s on this machine on 2026-11-22.
    parser.add_argument("--timeout", type=float, default=240.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("persistence/btree.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("PERSISTENCE SNAPSHOT AUDIT PASS",),
        stable_markers=("PERSISTENCE SNAPSHOT AUDIT PASS",),
        failure_markers=(
            "PERSISTENCE SNAPSHOT AUDIT FAIL",
            "PERSISTENCE BTREE ASSERT",
            "PERSISTENCE BTREE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=(
            ("local_testing/persist-btree-test.f", BTREE_CONTRACT.read_bytes()),
            (
                "local_testing/persist-snap-audit.f",
                AUDIT_CONTRACT.read_bytes(),
            ),
        ),
        linked=True,
        link_chunk_bytes=192 * 1024,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=128,
        rows=45,
        max_steps=4_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


def test_contracts(tmp_path: Path, monkeypatch) -> None:
    """The contracts as a test, so the test selection tool runs them."""
    from contract_script import run_as_test

    run_as_test(sys.modules[__name__], tmp_path, monkeypatch)


if __name__ == "__main__":
    raise SystemExit(main())
