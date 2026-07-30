#!/usr/bin/env python3
"""Static and linked qualification for the OAuth DPoP nonce owner."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from forth_dependencies import dependency_closure  # noqa: E402


PROFILE = "oauth2-dpop-nonce-contracts"
IMAGE = Path("/tmp/akashic-oauth2-dpop-nonce-contracts.img")
SOURCE_ROOT = ROOT / "akashic"
SOURCE = SOURCE_ROOT / "security" / "oauth2" / "dpop-nonce.f"
DOC = ROOT / "docs" / "security" / "oauth2-dpop-nonce.md"
CONTRACT = LOCAL_TESTING / "oauth2-dpop-nonce-test.f"
MAX_STEPS = 250_000_000

AUTOEXEC = r"""\ autoexec.f - issuer-bound OAuth DPoP nonce contracts
ENTER-USERLAND
." OAUTH2 DPOP NONCE LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/dpop-nonce.f
." OAUTH2 DPOP NONCE SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-dpop-nonce-test.f
." OAUTH2 DPOP NONCE FIXTURE READY" CR TX-FLUSH
_O2DNT-RUN
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


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    lowered = source.lower()

    assert "PROVIDED akashic-oauth2-dpnonce" in source
    fixture_key = re.search(r"(?m)^PROVIDED[ \t]+(\S+)$", fixture)
    assert fixture_key is not None
    assert len(fixture_key.group(1)) <= 23
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "nonce records and borrow state must remain caller-owned"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "authorization-code.f",
        "http-post.f",
    ]
    assert not any(
        marker in requirement.lower()
        for requirement in requires
        for marker in ("atproto", "streams", "tui/", "xrpc", "session")
    )

    closure = dependency_closure(
        SOURCE_ROOT,
        ("security/oauth2/dpop-nonce.f",),
    )
    assert not any(
        path.startswith(("atproto/", "tui/applets/", "streams/"))
        for path in closure
    ), "the generic nonce owner must not acquire provider dependencies"
    for forbidden in ("atproto/", "streams/", "xrpc", "tui/applets/"):
        assert forbidden not in lowered

    assert re.search(
        r"O2CODE-ISSUER-CAPACITY\s+"
        r"CONSTANT OAUTH2-DPOP-NONCE-SERVER-CAPACITY",
        source,
    )
    assert re.search(
        r"OAUTH2-HTTP-POST-NONCE-CAPACITY\s+"
        r"CONSTANT OAUTH2-DPOP-NONCE-CAPACITY",
        source,
    )
    layout = source[
        source.index("Address-free nonce record") :
        source.index("Caller-memory, syntax, and object admission")
    ]
    assert "OAUTH2-DPOP-NONCE-SERVER-CAPACITY" in layout
    assert "OAUTH2-DPOP-NONCE-CAPACITY" in layout
    assert "-A" not in layout

    for word in (
        "OAUTH2-DPOP-NONCE-SIZE",
        "OAUTH2-DPOP-NONCE-STATUS-VALID?",
        "OAUTH2-DPOP-NONCE-VALID?",
        "OAUTH2-DPOP-NONCE-INIT",
        "OAUTH2-DPOP-NONCE-REPLACE",
        "OAUTH2-DPOP-NONCE-WITH",
        "OAUTH2-DPOP-NONCE-GENERATION@",
        "OAUTH2-DPOP-NONCE-WIPE",
    ):
        assert word in source

    replace = _word_body(source, "OAUTH2-DPOP-NONCE-REPLACE")
    assert replace.index("_O2DN-SOURCE-GEOMETRY") < replace.index(
        "_O2DN-SERVER-MATCH?"
    )
    assert replace.index("_O2DN-SERVER-MATCH?") < replace.index(
        "OAUTH2-DPOP-NONCE-CAPACITY 0 FILL"
    )
    assert replace.index("OAUTH2-DPOP-NONCE-CAPACITY 0 FILL") < (
        replace.index("MOVE")
    )
    assert replace.index("MOVE") < replace.index(
        "_O2DN.GENERATION @ 1+"
    )

    borrow = _word_body(source, "_O2DN-WITH-CALL")
    assert borrow.index("-1 R@ _O2DN.BORROWED !") < borrow.index("CATCH")
    assert borrow.count("0 R@ _O2DN.BORROWED !") == 2

    for marker in (
        "_o2dnt-test-init-and-borrow",
        "_o2dnt-test-rejections-unchanged",
        "_o2dnt-test-replace-and-wipe",
        "OAUTH2-DPOP-NONCE-S-BINDING",
        "OAUTH2-DPOP-NONCE-S-INVALID",
        "OAUTH2-DPOP-NONCE-S-BUSY",
        "_o2dnt-tail-zero?",
        "S\" bad nonce\"",
    ):
        assert marker in fixture

    for marker in (
        "provider-neutral",
        "address-free",
        "exact opaque server key",
        "1*NQCHAR",
        "single retry",
        "symbolic words",
    ):
        assert marker in doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source, fixture, and documentation without an image",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("OAUTH2 DPOP NONCE STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/dpop-nonce.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 DPOP NONCE PASS",),
        stable_markers=("OAUTH2 DPOP NONCE PASS",),
        failure_markers=(
            "OAUTH2 DPOP NONCE FAIL",
            "OAUTH2 DPOP NONCE ASSERT",
            "OAUTH2 DPOP NONCE STATUS",
            "OAUTH2 DPOP NONCE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-dpop-nonce-test.f",
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
        max_steps=MAX_STEPS,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
