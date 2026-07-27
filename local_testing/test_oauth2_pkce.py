#!/usr/bin/env python3
"""Focused linked qualification for generic OAuth 2 PKCE S256."""

from __future__ import annotations

import argparse
import base64
import hashlib
import re
import sys
from pathlib import Path
from unittest import mock


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from forth_dependencies import dependency_closure  # noqa: E402


PROFILE = "oauth2-pkce-contracts"
IMAGE = Path("/tmp/akashic-oauth2-pkce-contracts.img")
ENTROPY_FAIL_PROFILE = "oauth2-pkce-entropy-fail-contracts"
ENTROPY_FAIL_IMAGE = Path("/tmp/akashic-oauth2-pkce-entropy-fail-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-pkce-test.f"
SOURCE_ROOT = LOCAL_TESTING.parent / "akashic"
SOURCE = SOURCE_ROOT / "security" / "oauth2" / "pkce.f"

RFC7636_VERIFIER = (
    b"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
)
RFC7636_CHALLENGE = (
    b"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
)

AUTOEXEC = r"""\ autoexec.f - generic OAuth 2 PKCE S256 contracts
ENTER-USERLAND
REQUIRE security/oauth2/pkce.f
REQUIRE local_testing/oauth2-pkce-test.f
{entrypoint}
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    lowered = source.lower()

    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "PKCE operation state and scratch must remain caller-owned"
    assert "PROVIDED akashic-oauth2-pkce" in source

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/base64url.f",
        "../../math/sha256.f",
        "../../math/entropy.f",
    ]
    assert not any(
        marker in requirement.lower()
        for requirement in requires
        for marker in ("atproto", "streams", "session", "xrpc")
    )
    for forbidden in ("atproto/", "streams/", "tui/", "xrpc"):
        assert forbidden not in lowered

    closure = set(
        dependency_closure(
            SOURCE_ROOT,
            ("security/oauth2/pkce.f",),
        )
    )
    assert {
        "security/oauth2/pkce.f",
        "security/jose/base64url.f",
        "math/entropy.f",
        "math/sha256.f",
        "math/crypto-acc.f",
    } <= closure
    assert "../../math/crypto-acc.f" not in requires

    for word in (
        "OAUTH2-PKCE-S-OK",
        "OAUTH2-PKCE-S-INVALID",
        "OAUTH2-PKCE-S-VERIFIER",
        "OAUTH2-PKCE-S-CAPACITY",
        "OAUTH2-PKCE-S-ALIAS",
        "OAUTH2-PKCE-S-ENTROPY",
        "OAUTH2-PKCE-S-CRYPTO",
        "OAUTH2-PKCE-S-INTERNAL",
        "OAUTH2-PKCE-S-RANGE",
        "OAUTH2-PKCE-S-PROTECTED",
        "OAUTH2-PKCE-S-PLATFORM",
        "OAUTH2-PKCE-VERIFIER-MIN",
        "OAUTH2-PKCE-VERIFIER-MAX",
        "OAUTH2-PKCE-GENERATED-VERIFIER-SIZE",
        "OAUTH2-PKCE-CHALLENGE-SIZE",
        "OAUTH2-PKCE-WORKSPACE-SIZE",
        "OAUTH2-PKCE-STATUS-VALID?",
        "OAUTH2-PKCE-VERIFIER-VALID?",
        "OAUTH2-PKCE-WORKSPACE-CLEAR",
        "OAUTH2-PKCE-S256",
        "OAUTH2-PKCE-GENERATE",
    ):
        assert word in source

    assert re.search(
        r"(?m)^43[ \t]+CONSTANT OAUTH2-PKCE-VERIFIER-MIN$",
        source,
    )
    assert re.search(
        r"(?m)^128 CONSTANT OAUTH2-PKCE-VERIFIER-MAX$",
        source,
    )
    assert re.search(
        r"(?m)^43[ \t]+CONSTANT OAUTH2-PKCE-CHALLENGE-SIZE$",
        source,
    )
    assert re.search(
        r"(?m)^219 CONSTANT OAUTH2-PKCE-WORKSPACE-SIZE$",
        source,
    )

    # One canonical S256 surface: no weak transform and no compatibility API.
    assert "OAUTH2-PKCE-PLAIN" not in source
    assert not re.search(r"(?i)\bV2\b", source)
    assert len(
        re.findall(r"(?m)^:[ \t]+OAUTH2-PKCE-S256\b", source)
    ) == 1
    assert len(
        re.findall(r"(?m)^:[ \t]+OAUTH2-PKCE-GENERATE\b", source)
    ) == 1

    verifier = _word_body(source, "OAUTH2-PKCE-VERIFIER-VALID?")
    for marker in (
        "OAUTH2-PKCE-VERIFIER-MIN <",
        "OAUTH2-PKCE-VERIFIER-MAX >",
        "_OPK-ADMIT-SPAN",
        "_OPK-UNRESERVED?",
    ):
        assert marker in verifier
    unreserved = _word_body(source, "_OPK-UNRESERVED?")
    for ascii_value in ("65", "90", "97", "122", "48", "57"):
        assert ascii_value in unreserved
    for punctuation in ("45 =", "46 =", "95 =", "126 ="):
        assert punctuation in unreserved

    s256_geometry = _word_body(source, "_OPK-S256-GEOMETRY")
    generate_geometry = _word_body(source, "_OPK-GENERATE-GEOMETRY")
    for body in (s256_geometry, generate_geometry):
        assert "_OPK-ADMIT-SPAN" in body
        assert "OAUTH2-PKCE-S-CAPACITY" in body
        assert "MSPAN-OVERLAP?" in body
        assert "OAUTH2-PKCE-S-ALIAS" in body
        assert not re.search(
            r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
            r"(?![A-Za-z0-9_-])",
            body,
        ), "geometry preflight must not mutate caller storage"
    assert "OAUTH2-PKCE-VERIFIER-VALID?" in s256_geometry
    assert generate_geometry.count("MSPAN-OVERLAP?") == 3

    build = _word_body(source, "_OPK-BUILD-S256")
    assert build.index("SHA256-HASH") < build.index(
        "JOSE-B64URL-ENCODE"
    )
    assert "SHA256-LEN" in build
    assert "OAUTH2-PKCE-CHALLENGE-SIZE" in build
    sha_tail = build[build.index("SHA256-HASH") :]
    assert "_OPK-SHA>STATUS" in sha_tail
    assert sha_tail.index("_OPK-SHA>STATUS") < sha_tail.index(
        "JOSE-B64URL-ENCODE"
    )
    assert "OAUTH2-PKCE-S-CRYPTO" in _word_body(
        source, "_OPK-SHA>STATUS"
    )

    generate = _word_body(source, "_OPK-GENERATE-STAGE")
    assert generate.index("ENTROPY-FILL") < generate.index(
        "JOSE-B64URL-ENCODE"
    )
    assert generate.index("JOSE-B64URL-ENCODE") < generate.index(
        "_OPK-BUILD-S256"
    )
    assert " MOVE" not in generate
    assert _word_body(source, "_OPK-GENERATE-PUBLISH").count(" MOVE") == 2

    s256_stage = _word_body(source, "_OPK-S256-STAGE")
    assert "_OPK-BUILD-S256" in s256_stage
    assert "MOVE" not in s256_stage
    s256_publish = _word_body(source, "_OPK-S256-PUBLISH")
    assert "_OPKW.STAGED-CHALLENGE" in s256_publish
    assert "MOVE" in s256_publish

    for wrapper in ("_OPK-CALL-RESULT", "_OPK-CALL-GENERATE"):
        body = _word_body(source, wrapper)
        assert body.index("CATCH") < body.index("_OPK-WIPE")
        assert "1 PICK >R" in body
        assert "_OPK-DROP5" in body
        assert "THROW" in body
        assert "OAUTH2-PKCE-S-INTERNAL" not in body

    s256_public = _word_body(source, "OAUTH2-PKCE-S256")
    generate_public = _word_body(source, "OAUTH2-PKCE-GENERATE")
    assert s256_public.index("_OPK-S256-GEOMETRY") < s256_public.index(
        "_OPK-CALL-RESULT"
    )
    assert generate_public.index(
        "_OPK-GENERATE-GEOMETRY"
    ) < generate_public.index("_OPK-CALL-GENERATE")
    assert "_OPK-S256-ADMITTED" in s256_public
    assert "_OPK-GENERATE-ADMITTED" in generate_public

    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(RFC7636_VERIFIER).digest()
    ).rstrip(b"=")
    assert len(RFC7636_VERIFIER) == 43
    assert len(challenge) == 43
    assert challenge == RFC7636_CHALLENGE

    fixture = CONTRACT.read_text(encoding="utf-8")
    assert RFC7636_VERIFIER.decode("ascii") in fixture
    assert RFC7636_CHALLENGE.decode("ascii") in fixture
    for test_word in (
        "_opkt-test-rfc7636-vector",
        "_opkt-test-strict-verifiers",
        "_opkt-test-capacity",
        "_opkt-test-alias-geometry",
        "_opkt-test-entropy-output",
        "_opkt-test-entropy-unavailable",
        "_opkt-test-wipe-and-throw",
        "_OPKT-RUN-ENTROPY-FAIL",
    ):
        assert test_word in fixture


def _profile(entrypoint: str, ready_marker: str) -> harness.Profile:
    return harness.Profile(
        roots=("security/oauth2/pkce.f",),
        resources=(),
        autoexec=AUTOEXEC.format(entrypoint=entrypoint),
        ready_markers=(ready_marker,),
        stable_markers=(ready_marker,),
        failure_markers=(
            "OAUTH2 PKCE FAIL",
            "OAUTH2 PKCE ENTROPY FAIL",
            "OAUTH2 PKCE ASSERT",
            "OAUTH2 PKCE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/oauth2-pkce-test.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )


def _smoke_with_trng_disabled(
    profile: str,
    image: Path,
    *,
    timeout: float,
) -> bool:
    original_from_bios = harness.MachineSession.from_bios

    def from_bios_with_trng_disabled(*args, **kwargs):
        session = original_from_bios(*args, **kwargs)
        session.system.cores[0]._cs.disable_trng()
        assert not session.system.cores[0]._cs.trng_enabled()
        return session

    with mock.patch.object(
        harness.MachineSession,
        "from_bios",
        side_effect=from_bios_with_trng_disabled,
    ):
        return harness.smoke(
            profile,
            image,
            cols=120,
            rows=44,
            max_steps=800_000_000,
            timeout=timeout,
            ext_mem_mib=128,
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = _profile("_OPKT-RUN", "OAUTH2 PKCE PASS")
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=44,
        max_steps=800_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    if not ok:
        return 1

    harness.PROFILES[ENTROPY_FAIL_PROFILE] = _profile(
        "_OPKT-RUN-ENTROPY-FAIL",
        "OAUTH2 PKCE ENTROPY PASS",
    )
    entropy_fail_image = harness.build_image(
        ENTROPY_FAIL_PROFILE,
        ENTROPY_FAIL_IMAGE,
    )
    ok = _smoke_with_trng_disabled(
        ENTROPY_FAIL_PROFILE,
        entropy_fail_image,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
