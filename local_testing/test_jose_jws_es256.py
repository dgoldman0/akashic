#!/usr/bin/env python3
"""Focused linked qualification for strict generic compact-JWS ES256."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "jose-jws-es256-contracts"
IMAGE = Path("/tmp/akashic-jose-jws-es256-contracts.img")
CONTRACT = LOCAL_TESTING / "jose-jws-es256-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "jose"
    / "jws-es256.f"
)

AUTOEXEC = r"""\ autoexec.f - strict generic compact-JWS ES256 contracts
ENTER-USERLAND
REQUIRE security/jose/jws-es256.f
REQUIRE local_testing/jose-jws-es256-test.f
_JJWST-RUN
"""


P256_P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
P256_A = P256_P - 3
P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
P256_G = (
    0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296,
    0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5,
)


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _create_bytes(source: str, name: str) -> bytes:
    match = re.search(
        rf"(?ms)^CREATE[ \t]+{re.escape(name)}[ \t]*\n"
        rf"(?P<body>.*?)(?=^(?:CREATE|:|[ \t]*\\ [=]{{5,}})|\Z)",
        source,
    )
    assert match is not None, f"missing immutable byte table {name}"
    return bytes(
        int(value, 16)
        for value in re.findall(r"0x([0-9A-Fa-f]{2})[ \t]+C,", match.group("body"))
    )


def _b64url(value: bytes) -> bytes:
    return base64.urlsafe_b64encode(value).rstrip(b"=")


def _p256_add(
    first: tuple[int, int] | None,
    second: tuple[int, int] | None,
) -> tuple[int, int] | None:
    if first is None:
        return second
    if second is None:
        return first
    x1, y1 = first
    x2, y2 = second
    if x1 == x2 and (y1 + y2) % P256_P == 0:
        return None
    if first == second:
        slope = (
            (3 * x1 * x1 + P256_A) * pow(2 * y1, -1, P256_P)
        ) % P256_P
    else:
        slope = ((y2 - y1) * pow(x2 - x1, -1, P256_P)) % P256_P
    x3 = (slope * slope - x1 - x2) % P256_P
    return x3, (slope * (x1 - x3) - y1) % P256_P


def _p256_mul(
    scalar: int,
    point: tuple[int, int],
) -> tuple[int, int] | None:
    result = None
    addend: tuple[int, int] | None = point
    while scalar:
        if scalar & 1:
            result = _p256_add(result, addend)
        addend = _p256_add(addend, addend)
        scalar >>= 1
    return result


def _rfc6979_es256(private: bytes, message: bytes) -> bytes:
    """Independent RFC 6979 and integer P-256 signing oracle."""

    private_int = int.from_bytes(private, "big")
    digest = hashlib.sha256(message).digest()
    digest_int = int.from_bytes(digest, "big")
    seed = private + (digest_int % P256_N).to_bytes(32, "big")

    key = b"\x00" * 32
    value = b"\x01" * 32
    key = hmac.new(key, value + b"\x00" + seed, hashlib.sha256).digest()
    value = hmac.new(key, value, hashlib.sha256).digest()
    key = hmac.new(key, value + b"\x01" + seed, hashlib.sha256).digest()
    value = hmac.new(key, value, hashlib.sha256).digest()

    while True:
        value = hmac.new(key, value, hashlib.sha256).digest()
        nonce = int.from_bytes(value, "big")
        if 1 <= nonce < P256_N:
            break
        key = hmac.new(key, value + b"\x00", hashlib.sha256).digest()
        value = hmac.new(key, value, hashlib.sha256).digest()

    point = _p256_mul(nonce, P256_G)
    assert point is not None
    r = point[0] % P256_N
    s = (
        pow(nonce, -1, P256_N)
        * (digest_int + r * private_int)
    ) % P256_N
    assert r != 0 and s != 0
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def _verify_es256(public: bytes, message: bytes, signature: bytes) -> bool:
    """Independent integer P-256 verification oracle."""

    if len(public) != 65 or public[0] != 4 or len(signature) != 64:
        return False
    point = (
        int.from_bytes(public[1:33], "big"),
        int.from_bytes(public[33:65], "big"),
    )
    r = int.from_bytes(signature[:32], "big")
    s = int.from_bytes(signature[32:], "big")
    if not (1 <= r < P256_N and 1 <= s < P256_N):
        return False
    inverse = pow(s, -1, P256_N)
    digest = int.from_bytes(hashlib.sha256(message).digest(), "big")
    first = _p256_mul((digest * inverse) % P256_N, P256_G)
    second = _p256_mul((r * inverse) % P256_N, point)
    result = _p256_add(first, second)
    return result is not None and result[0] % P256_N == r


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert not re.search(
        r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER)\b", source
    ), "the JWS layer must not own mutable operation state"
    assert not re.search(
        r"(?mi)^[ \t]*CREATE\b", source
    ), "the JWS layer needs no module-owned byte tables or scratch"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "base64url.f",
        "json-object.f",
        "../../math/sha256.f",
        "../../math/ecdsa-p256.f",
    ]
    assert not any(
        marker in requirement.lower()
        for requirement in requires
        for marker in ("atproto", "oauth", "streams", "session", "xrpc")
    )

    for word in (
        "JOSE-JWS-ES256-MAX-PROTECTED-BYTES",
        "JOSE-JWS-ES256-MAX-PAYLOAD-BYTES",
        "JOSE-JWS-ES256-MAX-COMPACT-BYTES",
        "JOSE-JWS-ES256-SIGNATURE-SIZE",
        "JOSE-JWS-ES256-WORKSPACE-SIZE",
        "JOSE-JWS-ES256-STATUS-VALID?",
        "JOSE-JWS-ES256-COMPACT-SIZE",
        "JOSE-JWS-ES256-WORKSPACE-CLEAR",
        "JOSE-JWS-ES256-SIGN",
        "JOSE-JWS-ES256-VERIFY",
        "JOSE-JWS-ES256-S-POLICY",
        "JOSE-JWS-ES256-S-INTERNAL",
        "JOSE-JWS-ES256-S-RANGE",
        "JOSE-JWS-ES256-S-PROTECTED",
        "JOSE-JWS-ES256-S-PLATFORM",
    ):
        assert word in source

    assert re.search(
        r"(?m)^4096[ \t]+CONSTANT "
        r"JOSE-JWS-ES256-MAX-PROTECTED-BYTES$",
        source,
    )
    assert re.search(
        r"(?m)^65536 CONSTANT JOSE-JWS-ES256-MAX-PAYLOAD-BYTES$",
        source,
    )
    assert re.search(
        r"(?m)^CONSTANT JOSE-JWS-ES256-MAX-COMPACT-BYTES$",
        source,
    )
    assert "_JJWS-MAX-PROTECTED-TEXT 5462 <>" in source
    assert "_JJWS-MAX-PAYLOAD-TEXT 87382 <>" in source
    assert "_JJWS-SIGNATURE-TEXT-SIZE 86 <>" in source
    assert "JOSE-JWS-ES256-MAX-COMPACT-BYTES 92932 <>" in source

    compact_size = _word_body(source, "JOSE-JWS-ES256-COMPACT-SIZE")
    assert compact_size.count("JOSE-B64URL-ENCODED-LENGTH") == 2
    assert "JOSE-JWS-ES256-SIGNATURE-SIZE" in source

    header = _word_body(source, "_JJWS-HEADER-VALIDATE")
    assert "JOSE-JSON-OBJECT-PARSE" in header
    assert "JOSE-JSON-OBJECT-COUNT@" in header
    assert "0 ?DO" in header
    assert "I OVER _JJWS-PROCESS-HEADER-MEMBER" in header

    member = _word_body(source, "_JJWS-PROCESS-HEADER-MEMBER")
    assert 'S" alg"' in member
    assert 'S" b64"' in member
    assert 'S" crit"' in member
    assert "JOSE-JWS-ES256-S-POLICY" in member
    assert "_JJWS-EXPECT-ES256" in member
    assert "JOSE-JWS-ES256-S-OK EXIT" in member

    algorithm = _word_body(source, "_JJWS-EXPECT-ES256")
    assert "JOSE-JSON-T-STRING" in algorithm
    assert "JOSE-JSON-STRING-MEASURE" in algorithm
    assert "JOSE-JSON-STRING-DECODE" in algorithm
    assert 'S" ES256"' in algorithm

    sign = _word_body(source, "_JJWS-SIGN-RUN")
    assert sign.index("_JJWS-SIGN-PREPARE") < sign.index(
        "_JJWS-SIGN-ALIASES"
    )
    assert sign.index("_JJWS-SIGN-ALIASES") < sign.index(
        "_JJWS-SIGN-STAGE-INPUTS"
    )
    assert sign.index("_JJWS-SIGN-STAGE-INPUTS") < sign.index(
        "_JJWS-HEADER-VALIDATE"
    )
    assert sign.index("_JJWS-HEADER-VALIDATE") < sign.index(
        "_JJWS-SIGN-BUILD"
    )

    build = _word_body(source, "_JJWS-SIGN-BUILD")
    assert build.count("JOSE-B64URL-ENCODE") == 3
    assert build.index("SHA256-HASH") < build.index("ECDSA-P256-SIGN-HASH")
    assert build.index("ECDSA-P256-SIGN-HASH") < build.rindex(
        "JOSE-B64URL-ENCODE"
    )
    assert build.rindex("JOSE-B64URL-ENCODE") < build.index("MOVE")
    assert "JOSE-JWS-ES256-S-CRYPTO" in build[
        build.index("SHA256-HASH") :
        build.index("ECDSA-P256-SIGN-HASH")
    ]

    split = _word_body(source, "_JJWS-SPLIT-COMPACT")
    assert "_JJWS-RECORD-DOT" in split
    assert "_JJWSW.COUNT @ 2 <>" in split
    assert "_JJWS-SET-SEGMENTS" in split

    lengths = _word_body(source, "_JJWS-VERIFY-LENGTHS")
    assert lengths.count("_JJWS-DECODED-LENGTH") == 3
    assert "JOSE-JWS-ES256-SIGNATURE-SIZE <>" in lengths

    verify = _word_body(source, "_JJWS-VERIFY-RUN")
    for earlier, later in (
        ("_JJWS-SPLIT-COMPACT", "_JJWS-VERIFY-LENGTHS"),
        ("_JJWS-VERIFY-LENGTHS", "_JJWS-VERIFY-DECODE"),
        ("_JJWS-VERIFY-DECODE", "_JJWS-VERIFY-SIGNATURE"),
        ("_JJWS-VERIFY-SIGNATURE", "_JJWS-VERIFY-PUBLISH"),
    ):
        assert verify.index(earlier) < verify.index(later)

    verify_decode = _word_body(source, "_JJWS-VERIFY-DECODE")
    assert verify_decode.index("_JJWS-HEADER-VALIDATE") < (
        verify_decode.index("_JJWSW.PAYLOAD")
    )
    verify_signature = _word_body(source, "_JJWS-VERIFY-SIGNATURE")
    assert verify_signature.index("SHA256-HASH") < (
        verify_signature.index("ECDSA-P256-VERIFY-HASH")
    )
    assert "JOSE-JWS-ES256-S-CRYPTO" in verify_signature[
        verify_signature.index("SHA256-HASH") :
        verify_signature.index("ECDSA-P256-VERIFY-HASH")
    ]

    admit = _word_body(source, "_JJWS-ADMIT-SPAN")
    assert "CALLER-SPAN-STATUS" in admit
    assert "_JJWS-CALLER>STATUS" in admit
    assert "ECDSA-P256-RESERVED-OVERLAP?" in admit
    assert "_JJWS-SHA-SPAN>STATUS" in admit
    caller_map = _word_body(source, "_JJWS-CALLER>STATUS")
    for lower, upper in (
        ("CALLER-SPAN-S-RANGE", "JOSE-JWS-ES256-S-RANGE"),
        ("CALLER-SPAN-S-PROTECTED", "JOSE-JWS-ES256-S-PROTECTED"),
        ("CALLER-SPAN-S-PLATFORM", "JOSE-JWS-ES256-S-PLATFORM"),
    ):
        assert lower in caller_map and upper in caller_map
    assert "_JJWS-ADMIT-SPAN" in _word_body(
        source, "JOSE-JWS-ES256-WORKSPACE-CLEAR"
    )

    for wrapper in ("_JJWS-SIGN-CALL", "_JJWS-VERIFY-CALL"):
        body = _word_body(source, wrapper)
        assert body.index("CATCH") < body.index("_JJWS-WIPE")
        assert "THROW" in body
        assert "JOSE-JWS-ES256-S-INTERNAL" not in body

    public_sign = _word_body(source, "JOSE-JWS-ES256-SIGN")
    assert public_sign.index("_JJWS-SIGN-GEOMETRY") < (
        public_sign.index("_JJWS-SIGN-CALL")
    )
    assert "_JJWS-SIGN-ADMITTED _JJWS-SIGN-CALL" in public_sign

    public_verify = _word_body(source, "JOSE-JWS-ES256-VERIFY")
    assert public_verify.index("_JJWS-VERIFY-GEOMETRY") < (
        public_verify.index("_JJWS-VERIFY-CALL")
    )
    assert "_JJWS-VERIFY-ADMITTED _JJWS-VERIFY-CALL" in public_verify

    private = bytes.fromhex(
        "8e9b109e719098bf980487df1f5d77e9"
        "cb29606ebed2263b5f57c213df84f4b2"
    )
    public = bytes.fromhex(
        "047fcdce2770f6c45d4183cbee6fdb4b"
        "7b580733357be9ef13bacf6e3c7bd15445"
        "c7f144cd1bbd9b7e872cdfedb9eeb9f4"
        "b3695d6ea90b24ad8a4623288588e5ad"
    )
    header_bytes = b'{"alg":"ES256","typ":"JWT"}'
    payload = b"independent compact JWS fixture"
    signing_input = _b64url(header_bytes) + b"." + _b64url(payload)

    # Anchor the standalone signer to RFC 6979 Appendix A.2.5 before using
    # it as the oracle for the independent compact-JWS fixture.
    assert _rfc6979_es256(
        bytes.fromhex(
            "c9afa9d845ba75166b5c215767b1d693"
            "4e50c3db36e89b127b8a622b120f6721"
        ),
        b"sample",
    ) == bytes.fromhex(
        "efd48b2aacb6a8fd1140dd9cd45e81d6"
        "9d2c877b56aaf991c34d0ea84eaf3716"
        "f7cb1c942d657c41d436c7a1b6e29f65"
        "f3e900dbb9aff4064dc4ab2f843acda8"
    )

    derived_public = _p256_mul(int.from_bytes(private, "big"), P256_G)
    assert derived_public is not None
    assert public == (
        b"\x04"
        + derived_public[0].to_bytes(32, "big")
        + derived_public[1].to_bytes(32, "big")
    )

    expected_compact = (
        signing_input + b"." + _b64url(_rfc6979_es256(private, signing_input))
    )
    assert len(expected_compact) == 166
    assert expected_compact == _create_bytes(
        fixture, "_jjwst-expected-compact"
    )
    assert private == _create_bytes(fixture, "_jjwst-private")
    assert public == _create_bytes(fixture, "_jjwst-public")
    assert header_bytes == _create_bytes(fixture, "_jjwst-header")
    assert payload == _create_bytes(fixture, "_jjwst-payload")

    critical_header = _create_bytes(fixture, "_jjwst-critical-header")
    assert critical_header == b'{"alg":"ES256","crit":["x"],"x":true}'

    tampered_compact = bytearray(expected_compact)
    tampered_compact[-1] = ord("Q")
    tampered_signing_input, tampered_signature_text = bytes(
        tampered_compact
    ).rsplit(b".", 1)
    tampered_signature = base64.urlsafe_b64decode(
        tampered_signature_text + b"=="
    )
    assert len(tampered_signature) == 64
    assert not _verify_es256(
        public, tampered_signing_input, tampered_signature
    )

    rfc_compact = _create_bytes(fixture, "_jjwst-rfc-compact")
    encoded_header, encoded_payload, encoded_signature = rfc_compact.split(b".")
    rfc_signing_input = encoded_header + b"." + encoded_payload
    rfc_signature = base64.urlsafe_b64decode(encoded_signature + b"==")
    assert base64.urlsafe_b64decode(encoded_header + b"==") == (
        _create_bytes(fixture, "_jjwst-rfc-header")
    )
    assert base64.urlsafe_b64decode(encoded_payload + b"==") == (
        _create_bytes(fixture, "_jjwst-rfc-payload")
    )
    assert len(rfc_signature) == 64
    assert _verify_es256(public, rfc_signing_input, rfc_signature)

    assert "_jjwst-test-deterministic-sign" in fixture
    assert "_jjwst-test-rfc-verify" in fixture
    assert "_jjwst-test-compact-rejection" in fixture
    assert "_jjwst-test-header-policy" in fixture
    assert "_jjwst-test-empty-payload-round-trip" in fixture
    assert "_jjwst-test-valid-tampered-signature" in fixture
    assert "_jjwst-test-aliases" in fixture
    assert "_jjwst-test-throw-cleanup" in fixture
    assert "_jjwst-build-overlong-signature" in fixture
    assert "_jjwst-workspace-zero?" in fixture
    assert "_JJWS-SIGN-BIND" in _word_body(fixture, "_jjwst-throw-sign")
    assert "_JJWS-VERIFY-BIND" in _word_body(
        fixture, "_jjwst-throw-verify"
    )
    assert fixture.count("JOSE-JWS-ES256-S-COMPACT") >= 4
    assert fixture.count("_jjwst-expect-sign-failure") >= 7
    assert fixture.count("_jjwst-expect-verify-failure") >= 9


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=480.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/jose/jws-es256.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("JOSE JWS ES256 PASS",),
        stable_markers=("JOSE JWS ES256 PASS",),
        failure_markers=(
            "JOSE JWS ES256 FAIL",
            "JOSE JWS ES256 ASSERT",
            "JOSE JWS ES256 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/jose-jws-es256-test.f", CONTRACT.read_bytes()),
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
        # Valid signing, empty-payload round-trip, RFC verification, and
        # mathematically invalid-signature paths exercise the expensive
        # scalar operations.  Malformed cases fail before reaching them.
        max_steps=3_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
