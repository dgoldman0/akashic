#!/usr/bin/env python3
"""Linked RAM-VFS qualification for neutral immutable chunked blobs."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "persistence-blob-contracts"
IMAGE = Path("/tmp/akashic-persistence-blob-contracts.img")
CONTRACT = LOCAL_TESTING / "persist-blob-test.f"

AUTOEXEC = r'''\ autoexec.f - neutral immutable blob contracts
ENTER-USERLAND
REQUIRE persistence/blob.f
REQUIRE local_testing/persist-blob-test.f
_PBLC-run
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("persistence/blob.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("PERSISTENCE BLOB PASS",),
        stable_markers=("PERSISTENCE BLOB PASS",),
        failure_markers=(
            "PERSISTENCE BLOB FAIL",
            "PERSISTENCE BLOB ASSERT",
            "PERSISTENCE BLOB STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
        ),
        initial_files=(("local_testing/persist-blob-test.f", CONTRACT.read_bytes()),),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=128,
        rows=45,
        max_steps=15_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


def test_contracts(tmp_path: Path, monkeypatch) -> None:
    """The contracts as a test, so the test selection tool runs them."""
    from contract_script import run_as_test

    run_as_test(sys.modules[__name__], tmp_path, monkeypatch)


if __name__ == "__main__":
    raise SystemExit(main())
