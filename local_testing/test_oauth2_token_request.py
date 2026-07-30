#!/usr/bin/env python3
"""Static and linked qualification for the OAuth token-request owner."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-token-request-contracts"
IMAGE = Path("/tmp/akashic-oauth2-token-request-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-trequest-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "token-request.f"
)

AUTOEXEC = r"""\ autoexec.f - protected OAuth token-request contracts
ENTER-USERLAND
." OAUTH2 TOKEN REQUEST LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/token-request.f
." OAUTH2 TOKEN REQUEST SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-trequest-test.f
." OAUTH2 TOKEN REQUEST FIXTURE READY" CR TX-FLUSH
_O2TQT-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    lowered = source.lower()

    assert len(CONTRACT.name) <= 23
    assert "PROVIDED akashic-oauth2-trequest" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "the protected transaction must remain caller-owned"
    assert re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../../net/http-target.f",
        "authorization-code.f",
    ]

    for forbidden in (
        "atproto/",
        "streams/",
        "xrpc",
        "error-response.f",
        "token-response.f",
        "session.f",
    ):
        assert forbidden not in lowered

    for word in (
        "O2TREQ-SIZE",
        "O2TREQ-HTU-CAPACITY",
        "O2TREQ-STATUS-VALID?",
        "O2TREQ-INIT?",
        "O2TREQ-CLEAR?",
        "O2TREQ-PHASE@",
        "O2TREQ-CAPTURE",
        "O2TREQ-WITH-BUILD",
        "O2TREQ-CLAIM-RETRY",
        "O2TREQ-WITH-PROVENANCE",
        "O2TREQ-TERMINAL",
        "O2TREQ-ABANDON",
    ):
        assert word in source

    for phase in (
        "O2TREQ-PHASE-EMPTY",
        "O2TREQ-PHASE-READY",
        "O2TREQ-PHASE-FIRST-AWAITING",
        "O2TREQ-PHASE-RETRY-READY",
        "O2TREQ-PHASE-RETRY-AWAITING",
        "O2TREQ-PHASE-TERMINAL",
    ):
        assert phase in source

    layout = source[
        source.index("Address-free protected request object") :
        source.index("Admission and object integrity")
    ]
    assert "-A" not in layout
    for capacity in (
        "O2CODE-BINDING-CAPACITY",
        "O2CODE-ISSUER-CAPACITY",
        "O2CODE-STATE-SIZE",
        "O2CODE-VERIFIER-SIZE",
        "O2CODE-CODE-CAPACITY",
        "HTARGET-URI-CAPACITY",
    ):
        assert capacity in layout or capacity in source[
            source.index("Public status") : source.index("Address-free")
        ]

    geometry = _word_body(source, "_O2TRQ-CAPTURE-GEOMETRY")
    assert "O2CODE-PHASE@" in geometry
    assert geometry.count("MSPAN-OVERLAP?") == 3
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        geometry,
    )
    capture = _word_body(source, "O2TREQ-CAPTURE")
    assert capture.index("_O2TRQ-CAPTURE-GEOMETRY") < capture.index(
        "O2CODE-WITH-GRANT"
    )
    assert "_O2TRQ-INITIALIZE" in capture

    build = _word_body(source, "_O2TRQ-WITH-BUILD-CALL")
    assert build.index("CATCH") < build.index(
        "_O2TRQ-PUBLISH-AWAITING"
    )
    assert "DUP 0= IF" in build
    retry = _word_body(source, "O2TREQ-CLAIM-RETRY")
    assert "O2TREQ-PHASE-FIRST-AWAITING" in retry
    assert "O2TREQ-PHASE-RETRY-READY" in retry

    for borrow in (
        "_O2TRQ-WITH-BUILD-CALL",
        "_O2TRQ-WITH-PROVENANCE-CALL",
    ):
        body = _word_body(source, borrow)
        assert body.index("-1 R@ _O2TRQ.BORROWED !") < body.index("CATCH")
        assert body.count("0 R@ _O2TRQ.BORROWED !") >= 2

    terminal = _word_body(source, "_O2TRQ-PUBLISH-TERMINAL")
    assert "O2TREQ-SIZE 0 FILL" in terminal
    assert "O2TREQ-PHASE-TERMINAL" in terminal

    for marker in (
        "_o2tqt-test-capture-and-alias",
        "_o2tqt-test-build-and-sole-retry",
        "_o2tqt-test-terminal-and-abandon",
        "O2CODE-PHASE-SPENT",
        "O2TREQ-S-CALLBACK",
        "O2TREQ-S-BUSY",
        "O2TREQ-ATTEMPT-FIRST",
        "O2TREQ-ATTEMPT-RETRY",
        "_o2tqt-terminal-payload-zero?",
    ):
        assert marker in fixture

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


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
        print("OAUTH2 TOKEN REQUEST STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/token-request.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 TOKEN REQUEST PASS",),
        stable_markers=("OAUTH2 TOKEN REQUEST PASS",),
        failure_markers=(
            "OAUTH2 TOKEN REQUEST FAIL",
            "OAUTH2 TOKEN REQUEST ASSERT",
            "OAUTH2 TOKEN REQUEST STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-trequest-test.f",
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
