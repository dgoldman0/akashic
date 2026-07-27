#!/usr/bin/env python3
"""Focused linked qualification for generic caller-owned NIST P-256."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "p256-point-key-contracts"
IMAGE = Path("/tmp/akashic-p256-point-key-contracts.img")
CONTRACT = LOCAL_TESTING / "p256-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "math" / "p256.f"

AUTOEXEC = r"""\ autoexec.f - generic caller-owned NIST P-256
ENTER-USERLAND
REQUIRE math/p256.f
REQUIRE local_testing/p256-test.f
_P256T-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(name)}(?=[ \t(\r\n])(.*?)(?=^:\s|\Z)",
        source,
    )
    assert match is not None, f"missing word {name}"
    return match.group(1)


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    lower = source.lower()

    assert not re.search(
        r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER)\b", source
    ), "P-256 operation state must be caller-owned"
    assert not re.search(
        r"(?mi)^[ \t]*CREATE\b[^\n]*\bALLOT\b", source
    ), "P-256 may own immutable tables, not writable scratch buffers"
    creates = re.findall(r"(?mi)^[ \t]*CREATE[ \t]+(\S+)", source)
    assert set(creates) == {
        "_P256-GX",
        "_P256-GY",
        "_P256-B",
        "_P256-P",
        "_P256-N",
    }

    assert "REQUIRE ../utils/memory-span.f" in source
    assert "REQUIRE ../utils/caller-span.f" in source
    assert "REQUIRE field.f" in source
    assert "REQUIRE entropy.f" in source
    for forbidden in ("streams", "atproto", "oauth"):
        assert forbidden not in lower

    for word in (
        "P256-WORKSPACE-CLEAR",
        "P256-RESERVED-OVERLAP?",
        "P256-KEYGEN",
        "P256-PUBLIC-FROM-PRIVATE",
        "P256-PUBLIC-VALID?",
        "P256-PUBLIC-SCALAR-LINCOMB",
        "_P256-COMPLETE-ADD",
        "_P256-SCALAR-MUL-G",
        "_P256-PUBLIC-SCALAR-LINCOMB-MUL",
    ):
        assert word in source

    assert "Renes-Costello-Batina" in source
    assert "Algorithm 4" in source
    assert "256 0 DO" in _word_body(source, "_P256-SCALAR-MUL-G")
    assert "256 0 DO" in _word_body(
        source, "_P256-PUBLIC-SCALAR-LINCOMB-MUL"
    )
    assert "P256-S-SCALAR" in source
    assert "P256-S-PUBLIC" in source
    assert "P256-S-IDENTITY" in source
    assert "P256-S-ENTROPY" in source
    assert "P256-S-INTERNAL" in source
    assert "P256-S-RANGE" in source
    assert "P256-S-PROTECTED" in source
    assert "P256-S-PLATFORM" in source
    assert "P256-S-INVALID" not in source
    for value, name in enumerate(
        (
            "P256-S-OK",
            "P256-S-RANGE",
            "P256-S-PROTECTED",
            "P256-S-PLATFORM",
            "P256-S-ALIAS",
            "P256-S-PRIVATE",
            "P256-S-PUBLIC",
            "P256-S-SCALAR",
            "P256-S-IDENTITY",
            "P256-S-ENTROPY",
            "P256-S-INTERNAL",
        )
    ):
        assert f"{value} CONSTANT {name}" in source
    assert "1096 CONSTANT _P256W-PRIVATE-STAGED" in source

    mapper = _word_body(source, "_P256-CALLER>STATUS")
    for generic, public in (
        ("CALLER-SPAN-S-OK", "P256-S-OK"),
        ("CALLER-SPAN-S-RANGE", "P256-S-RANGE"),
        ("CALLER-SPAN-S-PROTECTED", "P256-S-PROTECTED"),
        ("CALLER-SPAN-S-PLATFORM", "P256-S-PLATFORM"),
    ):
        assert generic in mapper
        assert public in mapper
    assert mapper.count("P256-S-PLATFORM") >= 2

    fixed_span = _word_body(source, "_P256-FIXED-SPAN-STATUS")
    assert "CALLER-SPAN-STATUS" in fixed_span
    assert "P256-RESERVED-OVERLAP?" in fixed_span
    assert fixed_span.index("CALLER-SPAN-STATUS") < fixed_span.index(
        "P256-RESERVED-OVERLAP?"
    )
    assert "_P256-SPAN?" not in source

    tables = _word_body(source, "_P256-TABLE-OVERLAP?")
    for table in ("_P256-GX", "_P256-GY", "_P256-B", "_P256-P", "_P256-N"):
        assert table in tables
    reserved = _word_body(source, "P256-RESERVED-OVERLAP?")
    assert "FIELD-RESERVED-OVERLAP?" in reserved
    assert "_P256-TABLE-OVERLAP?" in reserved

    for geometry, expected_checks in (
        ("_P256-DERIVE-GEOMETRY", 3),
        ("_P256-VALIDATE-GEOMETRY", 2),
        ("_P256-LINCOMB-GEOMETRY", 5),
    ):
        body = _word_body(source, geometry)
        assert body.count("_P256-FIXED-SPAN-STATUS") == expected_checks
    assert "_P256-FIXED-SPAN-STATUS" in _word_body(
        source, "P256-WORKSPACE-CLEAR"
    )
    candidate = _word_body(source, "_P256-KEYGEN-CANDIDATE")
    assert "_P256-KEYGEN-ATTEMPTS 0 DO" in candidate
    assert "ENTROPY-FILL" in candidate
    assert "RANDOM" not in candidate
    keygen = _word_body(source, "_P256-KEYGEN-LOCKED")
    assert "_P256-SCALAR-MUL-G" in keygen
    assert "_P256W.PRIVATE-STAGED" in keygen
    transaction = _word_body(source, "_P256-KEYGEN-TRANSACTION")
    assert "FIELD-WITH-TRANSACTION" in transaction
    assert "FIELD-WITH-TRANSACTION" in source
    assert "_fld-guard" not in source
    assert "GUARDED" not in source
    assert "P256-S-CONFIG" not in source
    for name in (
        "_P256-CALL3-STATUS",
        "_P256-CALL2-RESULT",
        "_P256-CALL5-STATUS",
    ):
        body = _word_body(source, name)
        assert "1 PICK >R" in body
        assert "CATCH" in body
        assert "_P256-WIPE" in body
        assert "THROW" in body
        assert "P256-S-INTERNAL" not in body
        assert body.index("CATCH") < body.index("_P256-WIPE")
        assert body.index("_P256-WIPE") < body.index("THROW")
    for name in ("_P256-CLEANUP-STATUS", "_P256-CLEANUP-RESULT"):
        body = _word_body(source, name)
        assert "EXECUTE" in body
        assert "CATCH" not in body
        assert "P256-S-INTERNAL" not in body
    workspace_clear = _word_body(source, "P256-WORKSPACE-CLEAR")
    assert "_P256-WIPE" in workspace_clear
    assert "CATCH" not in workspace_clear
    for name in (
        "_P256-KEYGEN-ADMITTED",
        "_P256-DERIVE-ADMITTED",
        "_P256-VALIDATE-ADMITTED",
        "_P256-LINCOMB-ADMITTED",
    ):
        body = _word_body(source, name)
        assert "_P256-WIPE" in body
        assert "TRANSACTION" in body

    for name in (
        "_P256-KEYGEN-LOCKED",
        "_P256-DERIVE-LOCKED",
        "_P256-PUBLIC-SCALAR-LINCOMB-LOCKED",
    ):
        assert "MOVE" in _word_body(source, name)

    for name in (
        "_P256-COMPLETE-ADD",
        "_P256-SELECT-POINT",
        "_P256-SCALAR-ROUND",
        "_P256-SCALAR-MUL-G",
        "_P256-PUBLIC-SCALAR-LINCOMB-ROUND",
        "_P256-PUBLIC-SCALAR-LINCOMB-MUL",
    ):
        body = _word_body(source, name)
        assert not re.search(
            r"(?i)\b(?:IF|ELSE|WHILE|UNTIL|AGAIN)\b", body
        ), f"{name} contains a secret-path branch"
    select = _word_body(source, "_P256-SELECT-POINT")
    assert "XOR" in select and "AND" in select
    scalar_round = _word_body(source, "_P256-SCALAR-ROUND")
    assert "NEGATE" in scalar_round

    fixture = CONTRACT.read_text(encoding="utf-8")
    for marker in (
        "_p256t-test-lincomb",
        "_p256t-test-lincomb-aliases",
        "_p256t-test-exception-transparency",
        "_p256t-test-cleanup-propagation",
        "_p256t-public-2g",
        "P256-S-IDENTITY",
        "P256-S-SCALAR",
        "P256-S-PUBLIC",
        "P256-S-RANGE",
        "P256-S-PROTECTED",
        "P256-S-PLATFORM",
        "P256-RESERVED-OVERLAP?",
    ):
        assert marker in fixture
    assert fixture.count("P256-PUBLIC-SCALAR-LINCOMB") >= 5


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=1500.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/p256.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("P256 PASS",),
        stable_markers=("P256 PASS",),
        failure_markers=(
            "P256 FAIL",
            "P256 ASSERT",
            "P256 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/p256-test.f", CONTRACT.read_bytes()),
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
        max_steps=1_200_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
