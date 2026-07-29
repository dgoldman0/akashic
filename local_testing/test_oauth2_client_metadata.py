#!/usr/bin/env python3
"""Static and linked qualification for OAuth Client ID Metadata parsing."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-client-metadata-contracts"
IMAGE = Path("/tmp/akashic-oauth2-client-metadata-contracts.img")
SOURCE = ROOT / "akashic" / "security" / "oauth2" / "client-metadata.f"
DOC = ROOT / "docs" / "security" / "oauth2-client-metadata.md"
FIXTURE = LOCAL_TESTING / "oauth2-clientmd-test.f"
MAX_STEPS = 500_000_000

AUTOEXEC = r"""\ autoexec.f - OAuth Client ID Metadata contracts
ENTER-USERLAND
." OAUTH2 CLIENT METADATA LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/client-metadata.f
." OAUTH2 CLIENT METADATA SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-clientmd-test.f
." OAUTH2 CLIENT METADATA FIXTURE READY" CR TX-FLUSH
_O2CMT-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    lowered = source.lower()

    assert len(FIXTURE.name) <= 23
    assert "PROVIDED akashic-oauth2-clientmeta" in source
    assert re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/json-object.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "the parser must own no mutable operation state"
    for forbidden in (
        "atproto/",
        "streams/",
        "xrpc",
        "http-target",
        "credential-vault",
        "client-config.f",
    ):
        assert forbidden not in lowered

    public_words = (
        "OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE",
        "OAUTH2-CLIENT-METADATA-WORKSPACE-CLEAR",
        "OAUTH2-CLIENT-METADATA-STATUS-VALID?",
        "OAUTH2-CLIENT-METADATA-WITH",
        "OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@",
        "OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@",
        "OAUTH2-CLIENT-METADATA-VIEW-APPLICATION-TYPE@",
        "OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@",
        "OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@",
        "OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE?",
        "OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE-COUNT@",
        "OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE@",
        "OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE?",
        "OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI-COUNT@",
        "OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI@",
        "OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI?",
        "OAUTH2-CLIENT-METADATA-VIEW-SCOPE@",
        "OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-METHOD@",
        "OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-SIGNING-ALG@",
        "OAUTH2-CLIENT-METADATA-VIEW-DPOP-BOUND?",
        "OAUTH2-CLIENT-METADATA-VIEW-JWKS@",
        "OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@",
    )
    for word in public_words:
        assert word in source

    for member in (
        "client_id",
        "application_type",
        "grant_types",
        "response_types",
        "redirect_uris",
        "scope",
        "token_endpoint_auth_method",
        "token_endpoint_auth_signing_alg",
        "dpop_bound_access_tokens",
        "jwks",
        "jwks_uri",
        "client_secret",
        "client_secret_expires_at",
    ):
        assert f'S" {member}"' in source

    for method in (
        "client_secret_post",
        "client_secret_basic",
        "client_secret_jwt",
    ):
        assert f'S" {method}"' in source
    assert 'S" none" _O2CM-BYTES=' in source

    assert re.search(
        r"(?m)^5120 CONSTANT "
        r"OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES$",
        source,
    )
    assert "_O2CM-VIEW-SIZE 28568 <> [IF]" in source
    assert (
        "OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE 53256 <> [IF]"
        in source
    )

    stage = _word_body(source, "_O2CM-PARSE-STAGE")
    assert stage.index("JOSE-JSON-OBJECT-PARSE") < stage.index(
        "_O2CM-PROCESS-ALL"
    )
    assert stage.index("_O2CM-REQUIRED-PRESENCE") < stage.index(
        "_O2CM-VIEW-MAGIC-VALUE"
    )
    assert (
        "OAUTH2-CLIENT-METADATA-P-JWKS" in stage
        and "OAUTH2-CLIENT-METADATA-P-JWKS-URI" in stage
    )

    array_decode = _word_body(source, "_O2CM-DECODE-ARRAY-TOKEN")
    array_append = _word_body(source, "_O2CM-ARRAY-APPEND")
    assert "JOSE-JSON-STRING-DECODE" in array_decode
    assert "_O2CM-ARRAY-CONTAINS?" in array_append
    assert "OAUTH2-CLIENT-METADATA-S-DUPLICATE" in array_append

    view_valid = _word_body(source, "_O2CM-VIEW-VALID?")
    for validator in (
        "_O2CM-GRANT-HEADER?",
        "_O2CM-GRANT-ENTRIES?",
        "_O2CM-RESPONSE-HEADER?",
        "_O2CM-RESPONSE-ENTRIES?",
        "_O2CM-REDIRECT-HEADER?",
        "_O2CM-REDIRECT-ENTRIES?",
    ):
        assert validator in view_valid
    for validator in (
        "_O2CM-GRANT-ENTRIES?",
        "_O2CM-RESPONSE-ENTRIES?",
        "_O2CM-REDIRECT-ENTRIES?",
    ):
        body = _word_body(source, validator)
        assert "_O2CM-OFFSET-SPAN?" in body
        assert "UNLOOP EXIT" in body
        assert "R@" not in body

    for accessor in public_words[4:]:
        assert "_O2CM-VIEW-VALID?" in _word_body(source, accessor)

    geometry = _word_body(source, "_O2CM-WITH-GEOMETRY")
    assert geometry.count("_O2CM-ADMIT-SPAN") == 2
    assert "MSPAN-OVERLAP?" in geometry
    assert "7 AND" in geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        geometry,
    )
    public_with = _word_body(source, "OAUTH2-CLIENT-METADATA-WITH")
    assert public_with.index("_O2CM-WITH-GEOMETRY") < public_with.index(
        "_O2CM-WITH-CALL"
    )
    callback_run = _word_body(source, "_O2CM-CALLBACK-RUN")
    assert "_O2CM-CALLBACK-GUARD SWAP" in callback_run
    assert "OVER _O2CM-CALLBACK-GUARD <>" in callback_run
    assert "DEPTH" in callback_run and "EXECUTE" in callback_run
    assert "CATCH" in _word_body(source, "_O2CM-CALLBACK-SAFE")
    with_call = _word_body(source, "_O2CM-WITH-CALL")
    assert "CATCH" in with_call
    assert with_call.count("_O2CM-WIPE") >= 2

    fixture_markers = (
        "_o2cmt-test-statuses",
        "_o2cmt-test-success-and-lifetime",
        "_o2cmt-test-arrays-and-presence",
        "_o2cmt-test-errors-and-json",
        "_o2cmt-test-capacities",
        "_o2cmt-test-callbacks",
        "_o2cmt-test-preflight-and-clear",
        "_o2cmt-source-unchanged?",
        "_o2cmt-saved-view-invalid",
        "_o2cmt-callback-overconsume",
        "_o2cmt-callback-missing",
        "_O2CMT-STACK-SENTINEL =",
        "_o2cmt-callback-corrupt-entry",
        "_o2cmt-jwks-expected",
        "_o2cmt-source-span?",
        "_o2cmt-build-grant-pair-total",
        "_o2cmt-build-name-capacity",
        "_o2cmt-build-name-overflow",
        "OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES 1+",
        "_o2cmt-work 1+",
        "OAUTH2-CLIENT-METADATA-WORKSPACE-CLEAR",
    )
    for marker in fixture_markers:
        assert marker in fixture
    assert not re.search(
        r"(?mi)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture
    ), "the fixture must use cursor walks"
    run_body = _word_body(fixture, "_O2CMT-RUN")
    for group in fixture_markers[:7]:
        assert group in run_body
    assert "120 4087 _o2cmt-repeat-char" in _word_body(
        fixture, "_o2cmt-build-name-capacity"
    )
    assert "120 4088 _o2cmt-repeat-char" in _word_body(
        fixture, "_o2cmt-build-name-overflow"
    )

    for phrase in (
        "structural boundary",
        "byte-for-byte equality",
        "five-kilobyte",
        "private or symmetric",
        "present empty array",
        "callback",
        "AT Protocol binder",
    ):
        assert phrase in doc

    for path, forth_source in ((SOURCE, source), (FIXTURE, fixture)):
        for line_number, line in enumerate(
            forth_source.splitlines(), start=1
        ):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source, fixture, and documentation without a guest",
    )
    parser.add_argument("--timeout", type=float, default=240.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("OAUTH2 CLIENT METADATA STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/client-metadata.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 CLIENT METADATA PASS",),
        stable_markers=("OAUTH2 CLIENT METADATA PASS",),
        failure_markers=(
            "OAUTH2 CLIENT METADATA FAIL",
            "OAUTH2 CLIENT METADATA ASSERT",
            "OAUTH2 CLIENT METADATA STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-clientmd-test.f",
                FIXTURE.read_bytes(),
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
        rows=42,
        max_steps=MAX_STEPS,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
