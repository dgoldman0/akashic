#!/usr/bin/env python3
"""Static and linked qualification for ephemeral OAuth 2 token responses."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-token-response-contracts"
IMAGE = Path("/tmp/akashic-oauth2-token-response-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-tokenrsp-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "token-response.f"
)

AUTOEXEC = r"""\ autoexec.f - ephemeral OAuth 2 token-response contracts
ENTER-USERLAND
." OAUTH2 TOKEN RESPONSE LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/token-response.f
." OAUTH2 TOKEN RESPONSE SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-tokenrsp-test.f
." OAUTH2 TOKEN RESPONSE FIXTURE READY" CR TX-FLUSH
_O2TRT-RUN
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
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert "PROVIDED akashic-oauth2-tokenrsp" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "the generic decoder must not own mutable operation state"
    assert re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/json-object.f",
    ]

    public_words = (
        "OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE",
        "OAUTH2-TOKEN-RESPONSE-WITH",
        "OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@",
        "OAUTH2-TOKEN-VIEW-TOKEN-TYPE@",
        "OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@",
        "OAUTH2-TOKEN-VIEW-SCOPE@",
        "OAUTH2-TOKEN-VIEW-EXPIRES-IN@",
        "OAUTH2-TOKEN-RESPONSE-STATUS-VALID?",
        "OAUTH2-TOKEN-VIEW-MAX-EXPIRES-IN",
    )
    for word in public_words:
        assert word in source

    for removed_persistent_api in (
        "OAUTH2-TOKEN-RESULT-SIZE",
        "OAUTH2-TOKEN-RESPONSE-PARSE",
        "OAUTH2-TOKEN-RESULT-INIT",
        "OAUTH2-TOKEN-RESULT-CLEAR",
        "OAUTH2-TOKEN-RESULT-PRESENCE@",
        "OAUTH2-TOKEN-RESULT-ID-TOKEN@",
        "OAUTH2-TOKEN-RESULT-SUB@",
    ):
        assert removed_persistent_api not in source

    assert re.search(
        r"(?m)^8192 CONSTANT OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY$",
        source,
    )
    for capacity in (
        "OAUTH2-TOKEN-VIEW-TOKEN-TYPE-CAPACITY",
        "OAUTH2-TOKEN-VIEW-REFRESH-CAPACITY",
        "OAUTH2-TOKEN-VIEW-SCOPE-CAPACITY",
    ):
        assert re.search(rf"(?m)^4096 CONSTANT {capacity}$", source)
    assert re.search(
        r"(?m)^2147483647 CONSTANT "
        r"OAUTH2-TOKEN-VIEW-MAX-EXPIRES-IN$",
        source,
    )
    assert re.search(
        r"(?m)^OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE 30976 <> \[IF\]$",
        source,
    )

    geometry = _word_body(source, "_O2TR-WITH-GEOMETRY")
    assert geometry.count("_O2TR-ADMIT-SPAN") == 2
    assert "MSPAN-OVERLAP?" in geometry
    assert geometry.count("0= IF") >= 2
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        geometry,
    )

    stage = _word_body(source, "_O2TR-PARSE-STAGE")
    assert "JOSE-JSON-OBJECT-PARSE" in stage
    assert "JOSE-JSON-OBJECT-COUNT@" in stage
    assert stage.index("_O2TR-REQUIRED-PRESENCE") < stage.index(
        "_O2TR-VIEW-MAGIC-VALUE"
    )

    process = _word_body(source, "_O2TR-PROCESS-MEMBER")
    for member in (
        'S" access_token"',
        'S" token_type"',
        'S" refresh_token"',
        'S" scope"',
        'S" expires_in"',
    ):
        assert member in process
    assert 'S" id_token"' not in process
    assert 'S" sub"' not in process
    assert "JOSE-JSON-STRING-DECODE" in _word_body(
        source, "_O2TR-COPY-MEMBER-STRING"
    )
    assert "_O2TR-VSCHAR?" in process
    assert "_O2TR-TOKEN-TYPE?" in process
    assert "_O2TR-SCOPE?" in process

    expires = _word_body(source, "_O2TR-PARSE-EXPIRES")
    assert "JOSE-JSON-T-NUMBER" in expires
    assert "_O2TR-DIGIT?" in expires
    assert "_O2TR-EXPIRES-ACCUMULATE" in expires
    accumulate = _word_body(source, "_O2TR-EXPIRES-ACCUMULATE")
    assert "_O2TR-EXPIRES-QUOTIENT" in accumulate
    assert "_O2TR-EXPIRES-REMAINDER" in accumulate

    callback_run = _word_body(source, "_O2TR-CALLBACK-RUN")
    assert "EXECUTE" in callback_run
    assert "DEPTH" in callback_run
    callback_safe = _word_body(source, "_O2TR-CALLBACK-SAFE")
    assert "CATCH" in callback_safe
    assert "OAUTH2-TOKEN-RESPONSE-S-CALLBACK" in callback_safe
    with_operation = _word_body(source, "_O2TR-WITH-OP")
    assert with_operation.index("_O2TR-PARSE-STAGE") < with_operation.index(
        "_O2TR-CALLBACK-SAFE"
    )
    with_call = _word_body(source, "_O2TR-WITH-CALL")
    assert "CATCH" in with_call
    assert with_call.count("_O2TR-WIPE") >= 2
    public_with = _word_body(source, "OAUTH2-TOKEN-RESPONSE-WITH")
    assert public_with.index("_O2TR-WITH-GEOMETRY") < public_with.index(
        "_O2TR-WITH-CALL"
    )

    for accessor in (
        "OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@",
        "OAUTH2-TOKEN-VIEW-TOKEN-TYPE@",
        "OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@",
        "OAUTH2-TOKEN-VIEW-SCOPE@",
        "OAUTH2-TOKEN-VIEW-EXPIRES-IN@",
    ):
        assert "_O2TR-VIEW-VALID?" in _word_body(source, accessor)

    fixture_markers = (
        "_o2trt-test-success-and-lifetime",
        "_o2trt-test-errors-and-duplicates",
        "_o2trt-test-value-grammars",
        "_o2trt-test-expiry",
        "_o2trt-test-callback-throw",
        "_o2trt-test-callback-stack",
        "_o2trt-test-internal-throw",
        "_o2trt-test-preflight-alias",
        "OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY 1+",
        'S" D PoP"',
        "urn:ietf:params:oauth:token-type:example",
        "https://[2001:db8::1]/oauth?kind=proof#v1",
        "urn:example:%2G",
        "https://[2001:::1]/x",
        "u001F",
        "u005F",
        "2147483648",
        "_o2trt-callback-count @ 1 =",
        "_o2trt-saved-view-invalid",
        "_o2trt-work-zero?",
        "_o2trt-work-filled?",
    )
    for marker in fixture_markers:
        assert marker in fixture
    assert not re.search(
        r"(?mi)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture
    ), "the fixture must use cursor walks rather than indexed loops"
    for line_number, line in enumerate(fixture.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {line_number}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source and fixture contracts without running an image",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("OAUTH2 TOKEN RESPONSE STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/token-response.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 TOKEN RESPONSE PASS",),
        stable_markers=("OAUTH2 TOKEN RESPONSE PASS",),
        failure_markers=(
            "OAUTH2 TOKEN RESPONSE FAIL",
            "OAUTH2 TOKEN RESPONSE ASSERT",
            "OAUTH2 TOKEN RESPONSE STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-tokenrsp-test.f",
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
        max_steps=250_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
