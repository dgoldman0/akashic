#!/usr/bin/env python3
"""Focused linked qualification for strict generic P-256 public JWKs."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "jose-jwk-p256-contracts"
IMAGE = Path("/tmp/akashic-jose-jwk-p256-contracts.img")
CONTRACT = LOCAL_TESTING / "jose-jwk-p256-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "jose"
    / "jwk-p256.f"
)

AUTOEXEC = r"""\ autoexec.f - strict generic P-256 JWK contracts
ENTER-USERLAND
REQUIRE security/jose/jwk-p256.f
REQUIRE local_testing/jose-jwk-p256-test.f
_JJPKT-RUN
"""


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


def _independent_vector() -> tuple[bytes, bytes, bytes]:
    x = bytes.fromhex(
        "60FED4BA255A9D31C961EB74C6356D68"
        "C049B8923B61FA6CE669622E60F29FB6"
    )
    y = bytes.fromhex(
        "7903FE1008B8BC99A41AE9E95628BC64"
        "F2F1B20C2D7E9F5177A3C294D4462299"
    )

    def b64url(value: bytes) -> str:
        return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")

    members = {
        "kty": "EC",
        "crv": "P-256",
        "x": b64url(x),
        "y": b64url(y),
    }
    canonical = json.dumps(
        members,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return b"\x04" + x + y, canonical, hashlib.sha256(canonical).digest()


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    assert not re.search(
        r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER)\b", source
    ), "the JWK layer must not own mutable operation state"

    creates = re.findall(r"(?mi)^[ \t]*CREATE[ \t]+(\S+)", source)
    assert creates == [
        "_JJPK-CANONICAL-PREFIX",
        "_JJPK-CANONICAL-MIDDLE",
        "_JJPK-CANONICAL-SUFFIX",
    ], "only immutable canonical JSON fragments may be module-owned"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "base64url.f",
        "json-object.f",
        "../../math/sha256.f",
        "../../math/p256.f",
    ]
    assert not any(
        marker in requirement.lower()
        for requirement in requires
        for marker in ("atproto", "oauth", "streams", "session", "xrpc")
    )

    for word in (
        "JOSE-JWK-P256-S-OK",
        "JOSE-JWK-P256-S-INVALID",
        "JOSE-JWK-P256-S-CAPACITY",
        "JOSE-JWK-P256-S-ALIAS",
        "JOSE-JWK-P256-S-JSON",
        "JOSE-JWK-P256-S-POLICY",
        "JOSE-JWK-P256-S-ENCODING",
        "JOSE-JWK-P256-S-PUBLIC",
        "JOSE-JWK-P256-S-CRYPTO",
        "JOSE-JWK-P256-S-INTERNAL",
        "JOSE-JWK-P256-S-RANGE",
        "JOSE-JWK-P256-S-PROTECTED",
        "JOSE-JWK-P256-S-PLATFORM",
        "JOSE-JWK-P256-PUBLIC-SIZE",
        "JOSE-JWK-P256-CANONICAL-SIZE",
        "JOSE-JWK-P256-THUMBPRINT-SIZE",
        "JOSE-JWK-P256-MAX-MEMBERS",
        "JOSE-JWK-P256-WORKSPACE-SIZE",
        "JOSE-JWK-P256-CALLER-SPAN-STATUS",
        "JOSE-JWK-P256-PUBLIC-PARSE",
        "JOSE-JWK-P256-PUBLIC-EMIT",
        "JOSE-JWK-P256-THUMBPRINT",
    ):
        assert word in source

    admit = _word_body(source, "_JJPK-ADMIT-SPAN")
    assert "CALLER-SPAN-STATUS" in admit
    assert "P256-RESERVED-OVERLAP?" in admit
    assert "SHA256-CALLER-SPAN-STATUS" in admit
    caller_map = _word_body(source, "_JJPK-CALLER>STATUS")
    for source_status, jwk_status in (
        ("CALLER-SPAN-S-RANGE", "JOSE-JWK-P256-S-RANGE"),
        ("CALLER-SPAN-S-PROTECTED", "JOSE-JWK-P256-S-PROTECTED"),
        ("CALLER-SPAN-S-PLATFORM", "JOSE-JWK-P256-S-PLATFORM"),
    ):
        assert source_status in caller_map and jwk_status in caller_map
    assert "_JJPK-SPAN?" not in source
    assert "MSPAN-NONWRAPPING?" not in source
    caller_span = _word_body(
        source, "JOSE-JWK-P256-CALLER-SPAN-STATUS"
    )
    assert "_JJPK-ADMIT-SPAN" in caller_span

    for geometry in (
        "_JJPK-PARSE-GEOMETRY",
        "_JJPK-EMIT-GEOMETRY",
        "_JJPK-THUMBPRINT-GEOMETRY",
    ):
        assert _word_body(source, geometry).count("_JJPK-ADMIT-SPAN") >= 3

    parser = _word_body(source, "_JJPK-PARSE-STAGE")
    assert "JOSE-JSON-OBJECT-PARSE" in parser
    assert "JOSE-JSON-OBJECT-COUNT@" in parser
    assert "_JJPK-PROCESS-ALL" in parser
    assert parser.index("_JJPK-PROCESS-ALL") < parser.index(
        "_JJPK-VALIDATE-PUBLIC"
    )
    assert "MOVE" not in parser
    assert re.search(
        r"(?m)^32[ \t]+CONSTANT JOSE-JWK-P256-MAX-MEMBERS$",
        source,
    )

    process = _word_body(source, "_JJPK-PROCESS-MEMBER")
    for name in ('S" kty"', 'S" crv"', 'S" x"', 'S" y"'):
        assert name in process
    assert 'S" d"' in process
    for literal in ('S" EC"', 'S" P-256"'):
        assert literal in process
    assert process.rstrip().endswith("JOSE-JWK-P256-S-OK")

    process_all = _word_body(source, "_JJPK-PROCESS-ALL")
    assert "0 ?DO" in process_all
    assert "I OVER _JJPK-PROCESS-MEMBER" in process_all

    coordinate = _word_body(source, "_JJPK-DECODE-COORDINATE")
    assert "JOSE-JSON-T-STRING" in coordinate
    assert "_JJPK-COORDINATE-TEXT-SIZE" in coordinate
    assert "JOSE-B64URL-DECODE" in coordinate

    build = _word_body(source, "_JJPK-BUILD-CANONICAL")
    assert build.count("JOSE-B64URL-ENCODE") == 2
    assert "_JJPK-CANONICAL-X-OFF" in build
    assert "_JJPK-CANONICAL-Y-OFF" in build

    thumbprint = _word_body(source, "_JJPK-THUMBPRINT-STAGE")
    assert thumbprint.index("_JJPK-BUILD-CANONICAL") < thumbprint.index(
        "SHA256-HASH"
    )
    assert "MOVE" not in thumbprint
    assert "JOSE-JWK-P256-S-CRYPTO" in thumbprint[
        thumbprint.index("SHA256-HASH") :
    ]

    finally_call = _word_body(source, "_JJPK-CALL-FINALLY")
    assert "CATCH" in finally_call
    assert "THROW" in finally_call
    assert finally_call.count("EXECUTE") >= 2
    for wrapper in (
        "_JJPK-PARSE-CALL",
        "_JJPK-EMIT-CALL",
        "_JJPK-THUMBPRINT-CALL",
    ):
        body = _word_body(source, wrapper)
        assert body.index("CATCH") < body.index("_JJPK-WIPE")
        assert "JOSE-JWK-P256-S-INTERNAL" in body
        assert "_JJPK-CALL-FINALLY" in body

    assert "MOVE" in _word_body(source, "_JJPK-PARSE-PUBLISH")
    assert "MOVE" in _word_body(source, "_JJPK-EMIT-PUBLISH")
    assert "MOVE" in _word_body(source, "_JJPK-THUMBPRINT-PUBLISH")
    assert "MOVE" in _word_body(source, "_JJPK-STAGE-PUBLIC")

    public_key, canonical, digest = _independent_vector()
    assert len(public_key) == 65
    assert len(canonical) == 126
    assert canonical == (
        b'{"crv":"P-256","kty":"EC",'
        b'"x":"YP7UuiVanTHJYet0xjVtaMBJuJI7Yfps5mliLmDyn7Y",'
        b'"y":"eQP-EAi4vJmkGunpVii8ZPLxsgwtfp9Rd6PClNRGIpk"}'
    )
    assert digest.hex() == (
        "0cebf1bc9880748a95588905b79843b4"
        "2ba75cb174055e3e246bf87fe00b4a6d"
    )

    prefix = _create_bytes(source, "_JJPK-CANONICAL-PREFIX")
    middle = _create_bytes(source, "_JJPK-CANONICAL-MIDDLE")
    suffix = _create_bytes(source, "_JJPK-CANONICAL-SUFFIX")
    assert prefix == b'{"crv":"P-256","kty":"EC","x":"'
    assert middle == b'","y":"'
    assert suffix == b'"}'

    fixture = CONTRACT.read_text(encoding="utf-8")
    assert "_jjpkt-test-order-and-metadata" in fixture
    assert "_jjpkt-build-private-member" in fixture
    assert 'S" u0064"' in fixture
    assert "42 _jjpkt-build-x-width" in fixture
    assert "0x5A _jjpkt-input 73 + C!" in fixture
    assert "_jjpkt-test-mapped-spans" in fixture
    assert "_jjpkt-test-caller-span" in fixture
    assert fixture.count("JOSE-JWK-P256-CALLER-SPAN-STATUS") >= 3
    assert "_jjpkt-test-publication-throws" in fixture


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=600.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/jose/jwk-p256.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("JOSE JWK P256 PASS",),
        stable_markers=("JOSE JWK P256 PASS",),
        failure_markers=(
            "JOSE JWK P256 FAIL",
            "JOSE JWK P256 ASSERT",
            "JOSE JWK P256 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/jose-jwk-p256-test.f", CONTRACT.read_bytes()),
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
        max_steps=900_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
