#!/usr/bin/env python3
"""Focused linked qualification for generic deterministic ECDSA-P256."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from forth_dependencies import dependency_closure  # noqa: E402


PROFILE = "ecdsa-p256-contracts"
IMAGE = Path("/tmp/akashic-ecdsa-p256-contracts.img")
CONTRACT = LOCAL_TESTING / "ecdsa-p256-test.f"
SOURCE_ROOT = LOCAL_TESTING.parent / "akashic"
SOURCE = SOURCE_ROOT / "math" / "ecdsa-p256.f"

AUTOEXEC = r"""\ autoexec.f - generic deterministic ECDSA-P256 contracts
ENTER-USERLAND
REQUIRE math/ecdsa-p256.f
REQUIRE local_testing/ecdsa-p256-test.f
_EPT-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s|\()(.*?)(?=^:\s|\Z)",
        source,
    )
    assert match is not None, f"missing word {name}"
    return match.group(1)


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    lower = source.lower()

    assert not re.search(
        r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER)\b", source
    ), "ECDSA-P256 operation state must be caller-owned"
    assert not re.search(
        r"(?mi)^[ \t]*CREATE\b[^\n]*\bALLOT\b", source
    ), "ECDSA-P256 may own immutable constants, not writable scratch"
    assert set(re.findall(r"(?mi)^[ \t]*CREATE[ \t]+(\S+)", source)) == {
        "_ECP-N",
        "_ECP-PINV0",
    }

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "hmac-sha256.f",
        "p256.f",
        "field.f",
        "../utils/caller-span.f",
        "../utils/memory-span.f",
    ]
    closure = set(
        dependency_closure(SOURCE_ROOT, ("math/ecdsa-p256.f",))
    )
    assert {
        "math/ecdsa-p256.f",
        "math/hmac-sha256.f",
        "math/sha256.f",
        "math/p256.f",
        "math/field.f",
        "utils/caller-span.f",
    } <= closure
    assert not {
        module
        for module in closure
        if module.startswith(
            (
                "atproto/",
                "security/oauth2/",
                "tui/applets/streams/",
            )
        )
    }
    for forbidden in ("atproto/", "streams/", "oauth2/"):
        assert forbidden not in lower

    for word in (
        "ECDSA-P256-HASH-SIZE",
        "ECDSA-P256-PRIVATE-SIZE",
        "ECDSA-P256-PUBLIC-SIZE",
        "ECDSA-P256-SIGNATURE-SIZE",
        "ECDSA-P256-WORKSPACE-SIZE",
        "ECDSA-P256-STATUS-VALID?",
        "ECDSA-P256-WORKSPACE-CLEAR",
        "ECDSA-P256-SIGN-HASH",
        "ECDSA-P256-VERIFY-HASH",
        "ECDSA-P256-S-INTERNAL",
        "ECDSA-P256-S-RANGE",
        "ECDSA-P256-S-PROTECTED",
        "ECDSA-P256-S-PLATFORM",
    ):
        assert word in source

    assert re.search(
        r"(?m)^64 CONSTANT ECDSA-P256-SIGNATURE-SIZE$", source
    )
    assert re.search(
        r"(?m)^64 CONSTANT _ECP-RFC6979-ATTEMPTS$", source
    )
    assert "IEEE P1363 / JOSE form r || s" in source
    assert "DER is deliberately outside" in source

    hmac = _word_body(source, "_ECP-HMAC-AT")
    for region in (
        "_ECPW.K",
        "_ECPW.HMAC-MESSAGE",
        "_ECPW.HMAC-OUTPUT",
        "_ECPW.HMAC-WORKSPACE",
    ):
        assert region in hmac
    assert "HMAC-SHA256" in hmac
    assert "_ECPW-HMAC-OUTPUT HMAC-SHA256-DIGEST-SIZE +" in source
    assert "_ECPW-HMAC-MESSAGE 97 +" in source
    assert "_ECPW-HMAC-WORKSPACE HMAC-SHA256-WORKSPACE-SIZE +" in source

    rfc_init = _word_body(source, "_ECP-RFC6979-INIT")
    assert "97 _ECP-HMAC-INTO-K" in rfc_init
    assert rfc_init.count("32 _ECP-HMAC-INTO-V") == 2
    assert "DUP 0 _ECP-RFC6979-SEED-MESSAGE" in rfc_init
    assert "DUP 1 _ECP-RFC6979-SEED-MESSAGE" in rfc_init
    assert "_ECP-RFC6979-REJECT" in source
    assert "_ECP-RFC6979-ATTEMPTS 0 DO" in _word_body(
        source, "_ECP-SIGN-LOCKED"
    )

    sign_candidate = _word_body(source, "_ECP-SIGN-CANDIDATE")
    assert "P256-PUBLIC-FROM-PRIVATE" in sign_candidate
    assert "FIELD-INV" in sign_candidate
    assert "FIELD-MUL" in sign_candidate
    assert "FIELD-NEG" not in sign_candidate
    assert "LOW-S" not in source.upper()

    verify = _word_body(source, "_ECP-VERIFY-LOCKED")
    assert "P256-PUBLIC-VALID?" in verify
    assert "P256-PUBLIC-SCALAR-LINCOMB" in verify
    assert not re.search(r"(?<![A-Za-z0-9-])_P256", source)
    assert "0 ECDSA-P256-S-OK EXIT" in verify

    sign_tx = _word_body(source, "_ECP-SIGN-TRANSACTION")
    verify_tx = _word_body(source, "_ECP-VERIFY-TRANSACTION")
    assert "FIELD-WITH-TRANSACTION" in sign_tx
    assert "FIELD-WITH-TRANSACTION" in verify_tx
    assert "_fld-guard" not in source

    fixed_span = _word_body(source, "_ECP-FIXED-SPAN-STATUS")
    assert "CALLER-SPAN-STATUS" in fixed_span
    assert "_ECP-CALLER>STATUS" in fixed_span
    assert "_ECP-SHA-SPAN>STATUS" in fixed_span
    assert "FIELD-RESERVED-OVERLAP?" in fixed_span
    assert "P256-RESERVED-OVERLAP?" in fixed_span
    assert "_ECP-TABLE-OVERLAP?" in fixed_span
    caller_map = _word_body(source, "_ECP-CALLER>STATUS")
    for lower, upper in (
        ("CALLER-SPAN-S-RANGE", "ECDSA-P256-S-RANGE"),
        ("CALLER-SPAN-S-PROTECTED", "ECDSA-P256-S-PROTECTED"),
        ("CALLER-SPAN-S-PLATFORM", "ECDSA-P256-S-PLATFORM"),
    ):
        assert lower in caller_map
        assert upper in caller_map
    table_overlap = _word_body(source, "_ECP-TABLE-OVERLAP?")
    assert "_ECP-N" in table_overlap
    assert "_ECP-PINV0" in table_overlap
    p256_map = _word_body(source, "_ECP-P256>STATUS")
    for lower, upper in (
        ("P256-S-ALIAS", "ECDSA-P256-S-ALIAS"),
        ("P256-S-PRIVATE", "ECDSA-P256-S-INTERNAL"),
        ("P256-S-PUBLIC", "ECDSA-P256-S-PUBLIC"),
        ("P256-S-SCALAR", "ECDSA-P256-S-INTERNAL"),
        ("P256-S-RANGE", "ECDSA-P256-S-RANGE"),
        ("P256-S-PROTECTED", "ECDSA-P256-S-PROTECTED"),
        ("P256-S-PLATFORM", "ECDSA-P256-S-PLATFORM"),
        ("P256-S-ENTROPY", "ECDSA-P256-S-INTERNAL"),
        ("P256-S-IDENTITY", "ECDSA-P256-S-INTERNAL"),
    ):
        assert re.search(
            rf"DUP {lower} = IF\s+.*?DROP {upper} EXIT",
            p256_map,
            re.DOTALL,
        )
    assert re.search(
        r"DUP P256-S-PRIVATE = IF\s+"
        r"2DROP 0 ECDSA-P256-S-NONCE EXIT",
        sign_candidate,
    )
    assert re.search(
        r"DUP P256-S-IDENTITY = IF\s+"
        r"2DROP 0 ECDSA-P256-S-OK EXIT",
        verify,
    )
    assert _word_body(
        source, "_ECP-SIGN-GEOMETRY"
    ).count("_ECP-FIXED-SPAN-STATUS") == 4
    assert _word_body(
        source, "_ECP-VERIFY-GEOMETRY"
    ).count("_ECP-FIXED-SPAN-STATUS") == 4
    assert "_ECP-FIXED-SPAN-STATUS" in _word_body(
        source, "ECDSA-P256-WORKSPACE-CLEAR"
    )

    sign_call = _word_body(source, "_ECP-SIGN-CALL")
    verify_call = _word_body(source, "_ECP-VERIFY-CALL")
    for body in (sign_call, verify_call):
        assert "1 PICK >R" in body
        assert "CATCH" in body
        assert "_ECP-WIPE" in body
        assert "THROW" in body
        assert "ECDSA-P256-S-INTERNAL" not in body
    for name in ("_ECP-CLEANUP-STATUS", "_ECP-CLEANUP-RESULT"):
        body = _word_body(source, name)
        assert "EXECUTE" in body
        assert "CATCH" not in body
    publish_clear = _word_body(source, "_ECP-SIGN-PUBLISH-CLEAR")
    assert "CATCH" in publish_clear
    assert "_ECP-WIPE" in publish_clear
    assert "THROW" in publish_clear
    assert "ECDSA-P256-S-INTERNAL" not in publish_clear

    sign_admitted = _word_body(source, "_ECP-SIGN-ADMITTED")
    verify_admitted = _word_body(source, "_ECP-VERIFY-ADMITTED")
    assert sign_admitted.index("_ECP-BIND") < sign_admitted.index(
        "_ECP-SIGN-TRANSACTION"
    )
    assert "MOVE" not in sign_admitted
    assert "_ECPW.S-BE" not in sign_admitted
    assert verify_admitted.index("_ECP-BIND") < verify_admitted.index(
        "_ECP-VERIFY-TRANSACTION"
    )
    sign_publish = _word_body(source, "_ECP-SIGN-PUBLISH")
    assert sign_publish.count("MOVE") == 1
    assert "ECDSA-P256-SIGNATURE-SIZE MOVE" in sign_publish

    sign_public = _word_body(source, "ECDSA-P256-SIGN-HASH")
    verify_public = _word_body(source, "ECDSA-P256-VERIFY-HASH")
    assert sign_public.index("_ECP-SIGN-GEOMETRY") < sign_public.index(
        "_ECP-SIGN-CALL"
    )
    assert verify_public.index("_ECP-VERIFY-GEOMETRY") < (
        verify_public.index("_ECP-VERIFY-CALL")
    )
    assert "_ECP-BIND" not in sign_public
    assert "_ECP-BIND" not in verify_public
    assert sign_public.index("_ECP-SIGN-CALL") < sign_public.index(
        "_ECP-SIGN-PUBLISH-CLEAR"
    )
    assert "_ECP-VERIFY-CLEAR-RETURN" in verify_public

    fixture = CONTRACT.read_text(encoding="utf-8")
    assert "_ept-signature-sample" in fixture
    assert "_ept-signature-test" in fixture
    assert "0xF7 C, 0xCB C," in fixture
    assert "_ept-test-throw-cleanup" in fixture
    assert "_ept-test-cleanup-propagation" in fixture
    assert "CATCH -777 = _ept-assert" in fixture
    assert "CATCH -778 = _ept-assert" in fixture
    assert "CATCH -779 = _ept-assert" in fixture
    assert "CATCH -780 = _ept-assert" in fixture
    assert "_ept-test-rfc6979-reject" in fixture
    assert "0xA3 C, 0xE7 C, 0x77 C, 0x6D C," in fixture
    assert "0xC5 C, 0x60 C, 0x9C C, 0xE6 C," in fixture
    assert fixture.count("_ept-expect-bad-signature") >= 5
    assert fixture.count("_ept-expect-sign-alias") >= 12
    assert fixture.count("_ept-expect-verify-alias") >= 7
    assert "ECDSA-P256-S-RANGE = _ept-assert" in fixture
    assert "ECDSA-P256-S-PROTECTED = _ept-assert" in fixture
    assert "ECDSA-P256-S-PLATFORM = _ept-assert" in fixture


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=360.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/ecdsa-p256.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("ECDSA P256 PASS",),
        stable_markers=("ECDSA P256 PASS",),
        failure_markers=(
            "ECDSA P256 FAIL",
            "ECDSA P256 ASSERT",
            "ECDSA P256 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/ecdsa-p256-test.f", CONTRACT.read_bytes()),
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
        # The fixture executes two scalar multiplications and two public
        # linear combinations.  This is a deterministic instruction ceiling,
        # not a product capacity claim.
        max_steps=4_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
