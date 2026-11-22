#!/usr/bin/env python3
"""Linked RAM-VFS qualification for bounded persistent page reclamation."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "persistence-reclaim-contracts"
IMAGE = Path("/tmp/akashic-persistence-reclaim-contracts.img")

CONTRACT_FILES = (
    "persist-store-test.f",
    "persist-reclaim-test.f",
)

AUTOEXEC = r'''\ autoexec.f - neutral physical reclamation contracts
ENTER-USERLAND
REQUIRE persistence/reclaim.f
REQUIRE local_testing/persist-store-test.f
REQUIRE local_testing/persist-reclaim-test.f
_PRC-RUN
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    # Wall-clock guard only; the step budget below bounds the run.  The
    # contracts took about 202 s on this machine on 2026-11-22.
    parser.add_argument("--timeout", type=float, default=420.0)
    args = parser.parse_args()

    initial_files = tuple(
        (f"local_testing/{name}", (LOCAL_TESTING / name).read_bytes())
        for name in CONTRACT_FILES
    )
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("persistence/reclaim.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("PERSISTENCE RECLAIM PASS",),
        stable_markers=("PERSISTENCE RECLAIM PASS",),
        failure_markers=(
            "PERSISTENCE RECLAIM FAIL",
            "PERSISTENCE RECLAIM ASSERT",
            "PERSISTENCE RECLAIM STATUS",
            "PERSISTENCE RECLAIM STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=initial_files,
        linked=True,
        link_chunk_bytes=192 * 1024,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
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
