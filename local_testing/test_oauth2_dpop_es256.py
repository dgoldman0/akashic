#!/usr/bin/env python3
"""Focused linked qualification for standalone OAuth DPoP ES256 proofs."""

from __future__ import annotations

import argparse
import base64
import hashlib
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from forth_dependencies import dependency_closure  # noqa: E402


PROFILE = "oauth2-dpop-es256-contracts"
IMAGE = Path("/tmp/akashic-oauth2-dpop-es256-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-dpop-es256-test.f"
SOURCE_ROOT = LOCAL_TESTING.parent / "akashic"
SOURCE = SOURCE_ROOT / "security" / "oauth2" / "dpop-es256.f"

AUTOEXEC = r"""\ autoexec.f - standalone OAuth DPoP ES256 contracts
ENTER-USERLAND
REQUIRE security/oauth2/dpop-es256.f
REQUIRE local_testing/oauth2-dpop-es256-test.f
_ODPT-RUN
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
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "DPoP operation state and staging must remain caller-owned"
    assert "PROVIDED akashic-oauth2-dpop256" in source

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/base64url.f",
        "../jose/jwk-p256.f",
        "../jose/jws-es256.f",
        "../../math/sha256.f",
        "../../math/entropy.f",
        "../../math/p256.f",
    ]
    assert not any(
        marker in requirement.lower()
        for requirement in requires
        for marker in ("atproto", "streams", "session", "xrpc", "http")
    )

    closure = set(
        dependency_closure(
            SOURCE_ROOT,
            ("security/oauth2/dpop-es256.f",),
        )
    )
    assert {
        "security/oauth2/dpop-es256.f",
        "security/jose/base64url.f",
        "security/jose/jwk-p256.f",
        "security/jose/jws-es256.f",
        "math/sha256.f",
        "math/entropy.f",
        "math/p256.f",
    } <= closure

    for word in (
        "OAUTH2-DPOP-ES256-MAX-METHOD-BYTES",
        "OAUTH2-DPOP-ES256-MAX-HTU-BYTES",
        "OAUTH2-DPOP-ES256-MAX-NONCE-BYTES",
        "OAUTH2-DPOP-ES256-JTI-SIZE",
        "OAUTH2-DPOP-ES256-MAX-PROOF-BYTES",
        "OAUTH2-DPOP-ES256-WORKSPACE-SIZE",
        "OAUTH2-DPOP-ES256-STATUS-VALID?",
        "OAUTH2-DPOP-ES256-WORKSPACE-CLEAR",
        "OAUTH2-DPOP-ES256-PROOF",
        "OAUTH2-DPOP-ES256-S-HTU",
        "OAUTH2-DPOP-ES256-S-TOKEN",
        "OAUTH2-DPOP-ES256-S-ENTROPY",
        "OAUTH2-DPOP-ES256-S-KEY",
        "OAUTH2-DPOP-ES256-S-CRYPTO",
        "OAUTH2-DPOP-ES256-S-INTERNAL",
        "OAUTH2-DPOP-ES256-S-RANGE",
        "OAUTH2-DPOP-ES256-S-PROTECTED",
        "OAUTH2-DPOP-ES256-S-PLATFORM",
    ):
        assert word in source

    assert "_ODP-JTI-ENTROPY-SIZE" in source
    assert re.search(
        r"(?m)^16 CONSTANT _ODP-JTI-ENTROPY-SIZE$", source
    )
    assert re.search(
        r"(?m)^165[ \t]+CONSTANT _ODP-HEADER-SIZE$", source
    )
    assert re.search(
        r"(?m)^8363 CONSTANT _ODP-MAX-PAYLOAD-SIZE$", source
    )
    assert (
        len(base64.urlsafe_b64encode(bytes(165)).rstrip(b"="))
        + 1
        + len(base64.urlsafe_b64encode(bytes(8363)).rstrip(b"="))
        + 1
        + len(base64.urlsafe_b64encode(bytes(64)).rstrip(b"="))
    ) == 11459
    assert "OAUTH2-DPOP-ES256-MAX-PROOF-BYTES 11459 <>" in source

    # This layer accepts normalized HTTP and HTTPS targets. TLS policy is
    # deliberately left to the transport profile.
    htu = _word_body(source, "_ODP-HTU-VALID?")
    assert "_ODP-ABSOLUTE-HTTP?" in htu
    absolute = _word_body(source, "_ODP-ABSOLUTE-HTTP?")
    assert "_ODP-HTTPS-PREFIX?" in absolute
    assert "_ODP-HTTP-PREFIX?" in absolute
    htu_char = _word_body(source, "_ODP-HTU-CHAR?")
    assert "35 =" in htu_char
    assert "63 =" in htu_char
    for forbidden in (
        "URI-NORMALIZE",
        "HTTP-REQUEST",
        "DISCOVERY",
        "TOKEN-SET",
        "SESSION",
        "VERIFY",
    ):
        assert forbidden not in source

    geometry = _word_body(source, "_ODP-GEOMETRY")
    assert (
        "11 PICK 10 PICK 10 PICK 9 PICK 8 PICK"
        in geometry
    ), "compact sizing must select htm-u/htu-u/iat/nonce-u/token-u"

    format_iat = _word_body(source, "_ODP-FORMAT-IAT")
    assert "OVER _ODPW.DIVISOR @ 1 =" in format_iat
    assert "OVER _ODPW.STARTED @" in format_iat
    assert "2 PICK _ODPW.DIVISOR @" not in format_iat
    assert "2 PICK _ODPW.STARTED @" not in format_iat

    run = _word_body(source, "_ODP-RUN")
    for earlier, later in (
        ("_ODP-BUILD-JTI", "_ODP-DERIVE-PUBLIC"),
        ("_ODP-DERIVE-PUBLIC", "_ODP-BUILD-HEADER"),
        ("_ODP-BUILD-HEADER", "_ODP-BUILD-ATH"),
        ("_ODP-BUILD-ATH", "_ODP-BUILD-PAYLOAD"),
        ("_ODP-BUILD-PAYLOAD", "_ODP-SIGN-STAGED"),
    ):
        assert run.index(earlier) < run.index(later)

    p256_status = _word_body(source, "_ODP-P256>STATUS")
    for marker in (
        "P256-S-RANGE",
        "P256-S-PROTECTED",
        "P256-S-PLATFORM",
        "P256-S-ALIAS",
        "P256-S-PRIVATE",
        "P256-S-PUBLIC",
        "P256-S-INTERNAL",
    ):
        assert marker in p256_status

    jti = _word_body(source, "_ODP-BUILD-JTI")
    assert jti.index("ENTROPY-FILL") < jti.index("JOSE-B64URL-ENCODE")
    assert "_ODP-JTI-ENTROPY-SIZE" in jti

    header = _word_body(source, "_ODP-BUILD-HEADER")
    assert "JOSE-JWK-P256-PUBLIC-EMIT" in header
    assert 'S" dpop+jwt"' in header
    assert 'S" ES256"' in header
    assert 'S" jwk"' in header

    ath = _word_body(source, "_ODP-BUILD-ATH")
    assert ath.index("SHA256-HASH") < ath.index("JOSE-B64URL-ENCODE")
    assert "JOSE-JSON" not in ath
    assert "COMPARE" not in ath
    token = _word_body(source, "_ODP-TOKEN-VALID?")
    assert "_ODP-TOKEN68-BASE?" in token
    assert "_ODP-ALL-EQUALS?" in token

    sign = _word_body(source, "_ODP-SIGN-STAGED")
    assert "JOSE-JWS-ES256-SIGN" in sign
    assert "_ODPW.PROOF" in sign
    assert "_ODPW.JWS-WORK" in sign
    assert "_ODPW.DESTINATION" not in sign
    assert "DROP 2DROP" in sign
    publish = _word_body(source, "_ODP-PUBLISH")
    assert "_ODPW.PROOF" in publish
    assert "_ODPW.DESTINATION" in publish
    assert "MOVE" in publish

    wrapper = _word_body(source, "_ODP-CALL")
    assert wrapper.index("CATCH") < wrapper.index("_ODP-WIPE")
    assert "_ODP-CALL-FINALLY" in wrapper
    assert "THROW" in wrapper

    assert base64.urlsafe_b64encode(
        hashlib.sha256(b"opaque-access-token").digest()
    ).rstrip(b"=") == b"ziBUtZEpY5JqE5mEv5FPe8jxfREaojHC2Eo9VfATgy4"
    for marker in (
        "_odpt-test-vocabulary",
        "_odpt-test-boundaries",
        "_odpt-test-proof",
        "http://server.example/token",
        "https://resource.example/data?view=full",
        "invalid token",
        "ziBUtZEpY5JqE5mEv5FPe8jxfREaojHC2Eo9VfATgy4",
    ):
        assert marker in fixture
    assert "P256-PUBLIC-FROM-PRIVATE" in fixture
    assert "JOSE-JWS-ES256-VERIFY" in fixture


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=480.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/dpop-es256.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 DPOP ES256 PASS",),
        stable_markers=("OAUTH2 DPOP ES256 PASS",),
        failure_markers=(
            "OAUTH2 DPOP ES256 FAIL",
            "OAUTH2 DPOP ES256 ASSERT",
            "OAUTH2 DPOP ES256 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/oauth2-dpop-es256-test.f", CONTRACT.read_bytes()),
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
        rows=44,
        max_steps=2_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
