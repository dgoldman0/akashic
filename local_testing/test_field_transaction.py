#!/usr/bin/env python3
"""Focused linked qualification for the always-present Field ALU transaction."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "field-transaction-contracts"
IMAGE = Path("/tmp/akashic-field-transaction-contracts.img")
CONTRACT = LOCAL_TESTING / "field-tx-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "math" / "field.f"
ACC_SOURCE = LOCAL_TESTING.parent / "akashic" / "math" / "crypto-acc.f"

AUTOEXEC = r"""\ autoexec.f - always-present Field ALU transaction contracts
ENTER-USERLAND
REQUIRE math/field.f
REQUIRE local_testing/field-tx-test.f
_FTXT-RUN
"""


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    acc_source = ACC_SOURCE.read_text(encoding="utf-8")
    assert "REQUIRE crypto-acc.f" in source
    assert "GUARD-BLOCKING _crypto-acc-guard" in acc_source
    assert "_CACC-SCRUB" in acc_source
    assert "_CACC-WITH-OUTER" in acc_source
    assert "GUARD-BLOCKING _fld-guard" in source
    assert "FIELD-WITH-TRANSACTION" in source
    assert "FIELD-TRANSACTION-MINE?" in source
    assert "FIELD-MAC-RAW" not in source

    guard_region = source[source.index("GUARD-BLOCKING _fld-guard") :]
    assert "[DEFINED] GUARDED" not in guard_region
    assert re.search(
        r"(?m)^:\s+_FIELD-WITH-LOCAL\b[\s\S]*?_fld-guard WITH-GUARD\s*;",
        source,
    )
    assert re.search(
        r"(?m)^:\s+FIELD-WITH-TRANSACTION\b[\s\S]*?"
        r"CRYPTO-ACC-WITH-TRANSACTION\s*;",
        source,
    )

    for word in (
        "FIELD-USE-25519",
        "FIELD-USE-SECP",
        "FIELD-USE-P256",
        "FIELD-USE-CUSTOM",
        "FIELD-LOAD-PRIME",
        "FIELD-ADD",
        "FIELD-SUB",
        "FIELD-MUL",
        "FIELD-SQR",
        "FIELD-INV",
        "FIELD-POW",
        "FIELD-MAC",
        "FIELD-MUL-RAW",
        "FIELD-EQ?",
        "FIELD-ZERO?",
    ):
        assert re.search(
            rf"(?m)^:\s+{re.escape(word)}(?=[ \t(])[^\n]*"
            r"FIELD-WITH-TRANSACTION\s*;",
            source,
        ), f"{word} is not protected by the shared accumulator/field scope"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/field.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("FIELD TRANSACTION PASS",),
        stable_markers=("FIELD TRANSACTION PASS",),
        failure_markers=(
            "FIELD TRANSACTION FAIL",
            "FIELD TRANSACTION ASSERT",
            "FIELD TRANSACTION STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/field-tx-test.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=800_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
