#!/usr/bin/env python3
"""Focused source and linked contracts for strict OAuth 2 metadata parsing."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-metadata-contracts"
IMAGE = Path("/tmp/akashic-oauth2-metadata-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-metadata-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "metadata.f"
)
DOC = LOCAL_TESTING.parent / "docs" / "security" / "oauth2-metadata.md"

AUTOEXEC = r"""\ autoexec.f - strict OAuth 2 metadata contracts
ENTER-USERLAND
REQUIRE security/oauth2/metadata.f
REQUIRE local_testing/oauth2-metadata-test.f
_O2MDT-RUN
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
    doc = DOC.read_text(encoding="utf-8")

    assert "U<=" not in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER|CREATE)\b", source
    ), "metadata operations must use only caller-owned mutable storage"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/json-object.f",
    ]
    assert not any(
        marker in requirement.lower()
        for requirement in requires
        for marker in (
            "http",
            "atproto",
            "identity",
            "session",
            "redirect",
            "xrpc",
        )
    )

    for word in (
        "OAUTH2-METADATA-SIZE",
        "OAUTH2-METADATA-WORKSPACE-SIZE",
        "OAUTH2-METADATA-STATUS-VALID?",
        "OAUTH2-METADATA-VALID?",
        "OAUTH2-METADATA-WORKSPACE-CLEAR",
        "OAUTH2-METADATA-PARSE",
        "OAUTH2-METADATA-PRESENCE@",
        "OAUTH2-METADATA-FLAGS@",
        "OAUTH2-METADATA-ISSUER@",
        "OAUTH2-METADATA-AUTHORIZATION-ENDPOINT@",
        "OAUTH2-METADATA-TOKEN-ENDPOINT@",
        "OAUTH2-METADATA-PAR-ENDPOINT@",
        "OAUTH2-METADATA-TOKEN-AUTH-COUNT@",
        "OAUTH2-METADATA-TOKEN-AUTH@",
        "OAUTH2-METADATA-TOKEN-AUTH-METHOD?",
        "OAUTH2-METADATA-SCOPE-COUNT@",
        "OAUTH2-METADATA-SCOPE@",
        "OAUTH2-METADATA-SCOPE?",
        "OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG-COUNT@",
        "OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG@",
        "OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG?",
    ):
        assert word in source

    for field in (
        "issuer",
        "authorization_endpoint",
        "token_endpoint",
        "pushed_authorization_request_endpoint",
        "require_pushed_authorization_requests",
        "response_types_supported",
        "grant_types_supported",
        "code_challenge_methods_supported",
        "dpop_signing_alg_values_supported",
        "token_endpoint_auth_methods_supported",
        "scopes_supported",
        "token_endpoint_auth_signing_alg_values_supported",
        "authorization_response_iss_parameter_supported",
        "require_request_uri_registration",
        "client_id_metadata_document_supported",
    ):
        assert f'S" {field}"' in source

    parser = _word_body(source, "_O2MD-PARSE-STAGE")
    assert "JOSE-JSON-OBJECT-PARSE" in parser
    assert "_O2MD-PROCESS-ALL" in parser
    assert "_O2MD-P-ISSUER AND 0=" in parser
    assert "_O2MD-P-ALL <>" not in parser
    assert "_O2MD.PRESENCE !" in parser
    assert "MOVE" not in parser

    process = _word_body(source, "_O2MD-PROCESS-MEMBER")
    assert "JOSE-JSON-T-STRING" not in process
    assert "JOSE-JSON-T-BOOL" in process
    assert process.count("_O2MD-CAPTURE-ARRAY") == 7
    for literal in (
        'S" code"',
        'S" authorization_code"',
        'S" refresh_token"',
        'S" S256"',
        'S" ES256"',
        'S" none"',
        'S" private_key_jwt"',
    ):
        assert literal in process

    array_parser = _word_body(source, "_O2MD-ARRAY-PARSE")
    assert "_O2MD-DECODE-ARRAY-TOKEN" in array_parser
    assert "_O2MD-ARRAY-APPEND" in array_parser
    assert "JOSE-JSON-STRING-DECODE" in _word_body(
        source, "_O2MD-DECODE-ARRAY-TOKEN"
    )
    assert "OAUTH2-METADATA-S-DUPLICATE" in _word_body(
        source, "_O2MD-ARRAY-APPEND"
    )

    validity = _word_body(source, "OAUTH2-METADATA-VALID?")
    assert validity.count("_O2MD-FLAG-REQUIRES-PRESENCE?") == 12
    assert "_O2MD-RAW-AUTH-METHOD?" in validity
    assert "_O2MD-RAW-TOKEN-AUTH-SIGNING-ALG?" in validity
    assert "OAUTH2-METADATA-F-ATPROTO" not in source

    assert "_O2MD-COPY-SCOPES" in process
    assert "_O2MD-COPY-TOKEN-AUTH-SIGNING-ALGS" in process

    geometry = _word_body(source, "_O2MD-PARSE-GEOMETRY")
    assert geometry.count("_O2MD-ADMIT-SPAN") == 3
    assert geometry.count("MSPAN-OVERLAP?") == 3

    admitted = _word_body(source, "_O2MD-PARSE-ADMITTED")
    publish = _word_body(source, "_O2MD-PUBLISH")
    call = _word_body(source, "_O2MD-PARSE-CALL")
    assert "_O2MD-WIPE" in admitted
    assert "MOVE" not in admitted
    assert publish.index("0 OVER _O2MDW.OUTPUT @ _O2MD.MAGIC !") < publish.index(
        "MOVE"
    )
    assert publish.index("MOVE") < publish.index("_O2MD-MAGIC-VALUE")
    assert "_O2MD-CALL-FINALLY" in call

    assert "`issuer` is the only field required" in doc
    assert "profile validator" in doc
    assert "does not fetch" in doc
    assert "does not assign a dedicated" in doc


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source contracts without building or running an image",
    )
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("OAUTH2 METADATA STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/metadata.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 METADATA PASS",),
        stable_markers=("OAUTH2 METADATA PASS",),
        failure_markers=(
            "OAUTH2 METADATA FAIL",
            "OAUTH2 METADATA ASSERT",
            "OAUTH2 METADATA STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-metadata-test.f",
                CONTRACT.read_bytes(),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=2_000_000_000,
        timeout=30.0,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
