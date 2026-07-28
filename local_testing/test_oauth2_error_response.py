#!/usr/bin/env python3
"""Static and linked qualification for generic OAuth 2 error responses."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-error-response-contracts"
IMAGE = Path("/tmp/akashic-oauth2-error-response-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-errorrsp-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "error-response.f"
)

AUTOEXEC = r"""\ autoexec.f - generic OAuth 2 error-response contracts
ENTER-USERLAND
." OAUTH2 ERROR RESPONSE LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/error-response.f
." OAUTH2 ERROR RESPONSE SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-errorrsp-test.f
." OAUTH2 ERROR RESPONSE FIXTURE READY" CR TX-FLUSH
_O2ERT-RUN
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

    assert len(CONTRACT.name) <= 23
    assert "PROVIDED akashic-oauth2-errorrsp" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "the generic decoder must not own mutable operation state"
    assert re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/json-object.f",
    ]

    public_words = (
        "OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE",
        "OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR",
        "OAUTH2-ERROR-RESPONSE-WITH",
        "OAUTH2-ERROR-VIEW-ERROR@",
        "OAUTH2-ERROR-VIEW-DESCRIPTION@",
        "OAUTH2-ERROR-VIEW-URI@",
        "OAUTH2-ERROR-RESPONSE-STATUS-VALID?",
        "OAUTH2-ERROR-VIEW-ERROR-CAPACITY",
        "OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY",
        "OAUTH2-ERROR-VIEW-URI-CAPACITY",
    )
    for word in public_words:
        assert word in source

    assert "atproto/" not in source.lower()
    assert "tui/applets/streams" not in source.lower()
    assert re.search(
        r"(?m)^256  CONSTANT OAUTH2-ERROR-VIEW-ERROR-CAPACITY$",
        source,
    )
    assert re.search(
        r"(?m)^1024 CONSTANT "
        r"OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY$",
        source,
    )
    assert re.search(
        r"(?m)^4096 CONSTANT OAUTH2-ERROR-VIEW-URI-CAPACITY$",
        source,
    )
    assert re.search(
        r"(?m)^OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE 15864 <> \[IF\]$",
        source,
    )

    clear = _word_body(
        source, "OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR"
    )
    assert clear.index("_O2ER-ADMIT-SPAN") < clear.index("_O2ER-WIPE")
    assert "7 AND" in clear
    assert "OAUTH2-ERROR-RESPONSE-S-INVALID" in clear

    geometry = _word_body(source, "_O2ER-WITH-GEOMETRY")
    assert geometry.count("_O2ER-ADMIT-SPAN") == 2
    assert "MSPAN-OVERLAP?" in geometry
    assert "7 AND" in geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        geometry,
    )

    stage = _word_body(source, "_O2ER-PARSE-STAGE")
    assert "JOSE-JSON-OBJECT-PARSE" in stage
    assert "JOSE-JSON-OBJECT-COUNT@" in stage
    assert stage.index("_O2ER-REQUIRED-PRESENCE") < stage.index(
        "_O2ER-VIEW-MAGIC-VALUE"
    )
    assert stage.index("_O2ERV.PRESENT !") < stage.index(
        "_O2ER-VIEW-MAGIC-VALUE"
    )

    process = _word_body(source, "_O2ER-PROCESS-MEMBER")
    for member in (
        'S" error"',
        'S" error_description"',
        'S" error_uri"',
    ):
        assert member in process
    copy_string = _word_body(source, "_O2ER-COPY-MEMBER-STRING")
    assert "JOSE-JSON-STRING-DECODE" in copy_string
    assert "DUP 0= IF" not in copy_string
    assert process.count("_O2ER-NQSCHAR?") == 2
    assert "_O2ER-URI-REFERENCE?" in process

    nqschar = _word_body(source, "_O2ER-NQSCHAR-BYTE?")
    for boundary in ("0x20", "0x22", "0x23", "0x5C", "0x5D", "0x7F"):
        assert boundary in nqschar
    uri_reference = _word_body(source, "_O2ER-URI-REFERENCE?")
    assert "_O2ER-CUT-QUERY-FRAGMENT" in uri_reference
    assert "_O2ER-URI-CORE?" in uri_reference
    assert "DUP 0= IF" not in uri_reference
    for uri_helper in (
        "_O2ER-PCT-TRIPLET?",
        "_O2ER-AUTHORITY?",
        "_O2ER-IPV4?",
        "_O2ER-IPV6?",
        "_O2ER-IPVFUTURE?",
    ):
        assert f": {uri_helper}" in source

    callback_run = _word_body(source, "_O2ER-CALLBACK-RUN")
    assert "EXECUTE" in callback_run
    assert "DEPTH" in callback_run
    assert "_O2ER-CALLBACK-GUARD SWAP" in callback_run
    assert "OVER _O2ER-CALLBACK-GUARD <>" in callback_run
    callback_safe = _word_body(source, "_O2ER-CALLBACK-SAFE")
    assert "CATCH" in callback_safe
    assert "OAUTH2-ERROR-RESPONSE-S-CALLBACK" in callback_safe
    with_operation = _word_body(source, "_O2ER-WITH-OP")
    assert with_operation.index("_O2ER-PARSE-STAGE") < (
        with_operation.index("_O2ER-CALLBACK-SAFE")
    )
    with_call = _word_body(source, "_O2ER-WITH-CALL")
    assert "CATCH" in with_call
    assert with_call.count("_O2ER-WIPE") >= 2
    public_with = _word_body(source, "OAUTH2-ERROR-RESPONSE-WITH")
    assert public_with.index("_O2ER-WITH-GEOMETRY") < public_with.index(
        "_O2ER-WITH-CALL"
    )

    for accessor in (
        "OAUTH2-ERROR-VIEW-ERROR@",
        "OAUTH2-ERROR-VIEW-DESCRIPTION@",
        "OAUTH2-ERROR-VIEW-URI@",
    ):
        assert "_O2ER-VIEW-VALID?" in _word_body(source, accessor)

    fixture_markers = (
        "_o2ert-test-success-and-lifetime",
        "_o2ert-test-errors-and-json",
        "_o2ert-test-value-grammars",
        "_o2ert-test-uri-reference-matrix",
        "_o2ert-test-callbacks",
        "_o2ert-test-preflight",
        "_o2ert-test-workspace-clear",
        "OAUTH2-ERROR-VIEW-ERROR-CAPACITY 1+",
        "OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY 1+",
        "OAUTH2-ERROR-VIEW-URI-CAPACITY 1+",
        "https://[2001:db8::1]:8443/",
        "../errors/invalid_request?source=as#detail",
        "_o2ert-callback-uri-empty",
        "_o2ert-callback-overconsume",
        "_O2ERT-STACK-SENTINEL =",
        'S" file:///tmp/error"',
        'S" https://[v1.fe80::a]:/x"',
        'S" http://[::ffff:192.0.2.128]/"',
        'S" //u@v@host/x"',
        'S" #a#b"',
        "https://as.example/error%2Gbad",
        "https://[2001:db8:::1]/error",
        "u000A",
        "u0022",
        "u005C",
        "u00E9",
        "u006F",
        "u0069",
        "u0078",
        "JOSE-JSON-MAX-DEPTH 1+",
        "_o2ert-callback-count @ 1 =",
        "_o2ert-saved-view-invalid",
        "_o2ert-work-zero?",
        "_o2ert-work-filled?",
        "_o2ert-work-all-filled?",
        "_o2ert-work 1+",
        "JOSE-JSON-MAX-DOCUMENT-BYTES 1+",
        "OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR",
    )
    for marker in fixture_markers:
        assert marker in fixture
    assert not re.search(
        r"(?mi)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture
    ), "the fixture must use cursor walks rather than indexed loops"
    for path, forth_source in ((SOURCE, source), (CONTRACT, fixture)):
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
        help="check source and fixture contracts without running an image",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("OAUTH2 ERROR RESPONSE STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/error-response.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 ERROR RESPONSE PASS",),
        stable_markers=("OAUTH2 ERROR RESPONSE PASS",),
        failure_markers=(
            "OAUTH2 ERROR RESPONSE FAIL",
            "OAUTH2 ERROR RESPONSE ASSERT",
            "OAUTH2 ERROR RESPONSE STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-errorrsp-test.f",
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
