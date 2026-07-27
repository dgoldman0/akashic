#!/usr/bin/env python3
"""Focused linked qualification for the checked Ed25519 SHA migration."""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "ed25519-linked-contracts"
IMAGE = Path("/tmp/akashic-ed25519-linked-contracts.img")
CONTRACT = LOCAL_TESTING / "ed25519-linked-test.f"
MATH = LOCAL_TESTING.parent / "akashic" / "math"
ED25519 = MATH / "ed25519.f"
FIELD = MATH / "field.f"
SHA512 = MATH / "sha512.f"
MAX_STEPS = 800_000_000

AUTOEXEC = r"""\ autoexec.f - linked Ed25519 caller-migration contracts
ENTER-USERLAND
REQUIRE math/ed25519.f
REQUIRE local_testing/ed25519-linked-test.f
_EDLT-RUN
"""


def _word_bodies(source: str, name: str) -> tuple[str, ...]:
    pattern = (
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;"
    )
    return tuple(match.group("body") for match in re.finditer(pattern, source))


def _only_word_body(source: str, name: str) -> str:
    bodies = _word_bodies(source, name)
    assert len(bodies) == 1, f"expected exactly one definition for {name}"
    return bodies[0]


def _assert_checked_sha_migration() -> None:
    ed_source = ED25519.read_text(encoding="utf-8")
    sha_source = SHA512.read_text(encoding="utf-8")

    sha_check = _only_word_body(ed_source, "_ED-SHA-CHECK")
    assert "?DUP IF" in sha_check
    assert "ED25519-E-SHA THROW" in sha_check

    checked_calls = re.findall(
        r"\b(SHA512-HASH(?:-2|-3)?)\s+_ED-SHA-CHECK\b",
        ed_source,
    )
    assert Counter(checked_calls) == Counter(
        {
            "SHA512-HASH": 1,
            "SHA512-HASH-2": 1,
            "SHA512-HASH-3": 2,
        }
    ), "Ed25519 must check all four one-shot SHA-512 calls"

    for removed in (
        "SHA512-BEGIN",
        "SHA512-ADD",
        "SHA512-END",
        "SHA512-INIT",
        "SHA512-UPDATE",
        "SHA512-FINAL",
    ):
        assert removed not in ed_source
    for removed in ("SHA512-BEGIN", "SHA512-ADD", "SHA512-END"):
        assert not re.search(
            rf"(?m)^:[ \t]+{re.escape(removed)}\b",
            sha_source,
        ), f"removed public streaming API {removed} was restored"

    for suffix, input_count in (("HASH", 1), ("HASH-2", 2), ("HASH-3", 3)):
        body = _only_word_body(sha_source, f"SHA512-{suffix}")
        assert f"_S512-PREFLIGHT-{input_count}" in body
        assert "CRYPTO-ACC-WITH-TRANSACTION" in body
        assert f"_S512-UNIT-{input_count}" in body
    assert len(_word_bodies(sha_source, "SHA512-CALLER-SPAN-STATUS")) == 1
    assert len(_word_bodies(sha_source, "SHA512-STATUS-VALID?")) == 1


def _assert_always_present_ownership() -> None:
    ed_source = ED25519.read_text(encoding="utf-8")
    field_source = FIELD.read_text(encoding="utf-8")

    assert re.search(
        r"(?m)^GUARD-BLOCKING[ \t]+_ed25519-guard[ \t]*$",
        ed_source,
    )
    assert re.search(
        r"(?m)^GUARD-BLOCKING[ \t]+_fld-guard[ \t]*$",
        field_source,
    )
    for source in (ed_source, field_source):
        assert "[DEFINED] GUARDED" not in source
        assert "[UNDEFINED] GUARDED" not in source

    for public, owned in (
        ("ED25519-KEYGEN", "_ed-keygen-owned-xt"),
        ("ED25519-SIGN", "_ed-sign-owned-xt"),
        ("ED25519-VERIFY", "_ed-verify-owned-xt"),
    ):
        bodies = _word_bodies(ed_source, public)
        assert len(bodies) == 2, f"{public} must have core and owned wrappers"
        assert owned in bodies[-1]
        assert "FIELD-WITH-TRANSACTION" in bodies[-1]

    for owned in (
        "_ED25519-KEYGEN-OWNED",
        "_ED25519-SIGN-OWNED",
        "_ED25519-VERIFY-OWNED",
    ):
        body = _only_word_body(ed_source, owned)
        assert "_ed25519-guard WITH-GUARD" in body

    field_transaction = _only_word_body(
        field_source, "FIELD-WITH-TRANSACTION"
    )
    assert "_FIELD-WITH-LOCAL" in field_transaction
    assert "CRYPTO-ACC-WITH-TRANSACTION" in field_transaction


def _assert_fixture_contract() -> None:
    source = CONTRACT.read_text(encoding="utf-8")
    assert source.count(" ED25519-KEYGEN") == 1
    assert source.count(" ED25519-SIGN") == 1
    assert source.count(" ED25519-VERIFY") == 1
    assert source.count(
        "_edlt-ownership-released? _edlt-assert"
    ) == 4, "ownership must be clear initially and after all three public calls"
    for required in (
        "_ed25519-guard GUARD-HELD? 0=",
        "_fld-guard GUARD-HELD? 0=",
        "_crypto-acc-guard GUARD-HELD? 0=",
        "CRYPTO-ACC-TRANSACTION-MINE? 0=",
        "ED25519 LINKED PASS",
        "ED25519 LINKED FAIL",
        "ED25519 LINKED ASSERT",
    ):
        assert required in source


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=900.0)
    args = parser.parse_args()

    _assert_checked_sha_migration()
    _assert_always_present_ownership()
    _assert_fixture_contract()

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/ed25519.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("ED25519 LINKED PASS",),
        stable_markers=("ED25519 LINKED PASS",),
        failure_markers=(
            "ED25519 LINKED FAIL",
            "ED25519 LINKED ASSERT",
            "ED25519 LINKED STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/ed25519-linked-test.f", CONTRACT.read_bytes()),
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
        max_steps=MAX_STEPS,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
