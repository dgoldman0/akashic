#!/usr/bin/env python3
"""Static and linked qualification for ephemeral OAuth 2.0 PAR responses."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-par-response-contracts"
IMAGE = Path("/tmp/akashic-oauth2-par-response-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-parrsp-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "par-response.f"
)

AUTOEXEC = r"""\ autoexec.f - ephemeral OAuth 2.0 PAR response contracts
ENTER-USERLAND
." OAUTH2 PAR RESPONSE LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/par-response.f
." OAUTH2 PAR RESPONSE SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-parrsp-test.f
." OAUTH2 PAR RESPONSE FIXTURE READY" CR TX-FLUSH
_O2PRT-RUN
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

    assert "PROVIDED akashic-oauth2-parrsp" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "the generic decoder must not own mutable operation state"
    assert re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/json-object.f",
    ]

    public_words = (
        "OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE",
        "OAUTH2-PAR-RESPONSE-WITH",
        "OAUTH2-PAR-VIEW-REQUEST-URI@",
        "OAUTH2-PAR-VIEW-EXPIRES-IN@",
        "OAUTH2-PAR-RESPONSE-STATUS-VALID?",
        "OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY",
        "OAUTH2-PAR-VIEW-MAX-EXPIRES-IN",
    )
    for word in public_words:
        assert word in source

    assert "atproto/" not in source.lower()
    assert "tui/applets/streams" not in source.lower()

    assert re.search(
        r"(?m)^4096 CONSTANT "
        r"OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY$",
        source,
    )
    assert re.search(
        r"(?m)^2147483647 CONSTANT "
        r"OAUTH2-PAR-VIEW-MAX-EXPIRES-IN$",
        source,
    )
    assert re.search(
        r"(?m)^OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE 14568 <> \[IF\]$",
        source,
    )

    geometry = _word_body(source, "_O2PR-WITH-GEOMETRY")
    assert geometry.count("_O2PR-ADMIT-SPAN") == 2
    assert "MSPAN-OVERLAP?" in geometry
    assert "ALIGNED" in geometry or "7 AND" in geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        geometry,
    )

    stage = _word_body(source, "_O2PR-PARSE-STAGE")
    assert "JOSE-JSON-OBJECT-PARSE" in stage
    assert "JOSE-JSON-OBJECT-COUNT@" in stage
    assert stage.index("_O2PR-REQUIRED-PRESENCE") < stage.index(
        "_O2PR-VIEW-MAGIC-VALUE"
    )

    process = _word_body(source, "_O2PR-PROCESS-MEMBER")
    assert 'S" request_uri"' in process
    assert 'S" expires_in"' in process
    copy_string = _word_body(source, "_O2PR-COPY-MEMBER-STRING")
    assert "JOSE-JSON-STRING-DECODE" in copy_string
    assert "_O2PR-VSCHAR?" in process

    expires = _word_body(source, "_O2PR-PARSE-EXPIRES")
    assert "JOSE-JSON-T-NUMBER" in expires
    assert "_O2PR-DIGIT?" in expires
    assert "_O2PR-EXPIRES-ACCUMULATE" in expires
    assert "0=" in expires, "PAR expires_in must reject zero"
    accumulate = _word_body(source, "_O2PR-EXPIRES-ACCUMULATE")
    assert "_O2PR-EXPIRES-QUOTIENT" in accumulate
    assert "_O2PR-EXPIRES-REMAINDER" in accumulate

    callback_run = _word_body(source, "_O2PR-CALLBACK-RUN")
    assert "EXECUTE" in callback_run
    assert "DEPTH" in callback_run
    callback_safe = _word_body(source, "_O2PR-CALLBACK-SAFE")
    assert "CATCH" in callback_safe
    assert "OAUTH2-PAR-RESPONSE-S-CALLBACK" in callback_safe
    with_operation = _word_body(source, "_O2PR-WITH-OP")
    assert with_operation.index("_O2PR-PARSE-STAGE") < with_operation.index(
        "_O2PR-CALLBACK-SAFE"
    )
    with_call = _word_body(source, "_O2PR-WITH-CALL")
    assert "CATCH" in with_call
    assert with_call.count("_O2PR-WIPE") >= 2
    public_with = _word_body(source, "OAUTH2-PAR-RESPONSE-WITH")
    assert public_with.index("_O2PR-WITH-GEOMETRY") < public_with.index(
        "_O2PR-WITH-CALL"
    )

    for accessor in (
        "OAUTH2-PAR-VIEW-REQUEST-URI@",
        "OAUTH2-PAR-VIEW-EXPIRES-IN@",
    ):
        assert "_O2PR-VIEW-VALID?" in _word_body(source, accessor)

    fixture_markers = (
        "_o2prt-test-success-and-lifetime",
        "_o2prt-test-errors-and-json",
        "_o2prt-test-value-grammars",
        "_o2prt-test-callback-throw",
        "_o2prt-test-callback-stack",
        "_o2prt-test-internal-throw",
        "_o2prt-test-preflight",
        "OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY 1+",
        "u002D",
        "u000A",
        "u00E9",
        "u005F",
        "_o2prt-build-duplicate-expires",
        "JOSE-JSON-MAX-DEPTH 1+",
        "2147483648",
        "_o2prt-callback-count @ 1 =",
        "_o2prt-saved-view-invalid",
        "_o2prt-work-zero?",
        "_o2prt-work-filled?",
        "_o2prt-work-all-filled?",
        "_o2prt-work 1+",
        "JOSE-JSON-MAX-DOCUMENT-BYTES 1+",
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
        print("OAUTH2 PAR RESPONSE STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/par-response.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 PAR RESPONSE PASS",),
        stable_markers=("OAUTH2 PAR RESPONSE PASS",),
        failure_markers=(
            "OAUTH2 PAR RESPONSE FAIL",
            "OAUTH2 PAR RESPONSE ASSERT",
            "OAUTH2 PAR RESPONSE STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-parrsp-test.f",
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
