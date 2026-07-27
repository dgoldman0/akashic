#!/usr/bin/env python3
"""Focused linked qualification for caller-owned OAuth token rotation."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-token-set-contracts"
IMAGE = Path("/tmp/akashic-oauth2-token-set-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-token-set-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "token-set.f"
)
AUTH_SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "tui"
    / "applets"
    / "agent"
    / "providers"
    / "codex"
    / "auth.f"
)
HARNESS_SOURCE = LOCAL_TESTING / "akashic_tui.py"

AUTOEXEC = r"""\ autoexec.f - opaque OAuth token ownership contracts
ENTER-USERLAND
REQUIRE security/oauth2/token-set.f
REQUIRE local_testing/oauth2-token-set-test.f
_OTST-RUN
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
    auth = AUTH_SOURCE.read_text(encoding="utf-8")
    harness_source = HARNESS_SOURCE.read_text(encoding="utf-8")
    lowered = source.lower()

    assert "U<=" not in source
    assert not re.search(r"(?m)^[ \t]*\([^)\n]*$", source)
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "all mutable token, lease, guard, and staging state must be caller-owned"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../../concurrency/guard.f",
    ]

    for forbidden in (
        "atproto/",
        "streams/",
        "xrpc",
        "net/",
        "persistence/",
        "json-field",
        "jose-json",
    ):
        assert forbidden not in lowered

    for word in (
        "O2TOK-ACCESS-CAPACITY",
        "O2TOK-REFRESH-CAPACITY",
        "O2TOK-ID-CAPACITY",
        "OAUTH2-TOKEN-SET-SIZE",
        "OAUTH2-REFRESH-LEASE-SIZE",
        "O2TOK-INIT?",
        "O2TOK-INIT",
        "O2TOK-REFRESH-LEASE-INIT?",
        "O2TOK-REFRESH-LEASE-INIT",
        "O2TOK-CLEAR?",
        "O2TOK-CLEAR",
        "O2TOK-PRESENCE",
        "O2TOK-SET",
        "O2TOK-WITH-ACCESS",
        "O2TOK-WITH-ID",
        "O2TOK-REFRESH-BEGIN",
        "O2TOK-WITH-REFRESH-LEASE",
        "O2TOK-REFRESH-COMMIT",
        "O2TOK-REFRESH-ABORT",
        "O2TOK-S-ALIAS",
        "O2TOK-S-STALE",
        "O2TOK-S-RANGE",
        "O2TOK-S-PROTECTED",
        "O2TOK-S-PLATFORM",
    ):
        assert word in source

    assert re.search(
        r"(?m)^8192 CONSTANT O2TOK-ACCESS-CAPACITY$", source
    )
    assert re.search(
        r"(?m)^4096 CONSTANT O2TOK-REFRESH-CAPACITY$", source
    )
    assert re.search(r"(?m)^8192 CONSTANT O2TOK-ID-CAPACITY$", source)
    assert re.search(
        r"(?m)^32[ \t]+CONSTANT OAUTH2-REFRESH-LEASE-SIZE$", source
    )
    assert not re.search(r"(?i)\b(?:v2|compat(?:ibility)?)\b", source)
    assert not re.search(
        r"(?m)^:[ \t]+O2TOK-UPDATE(?=[ \t\r\n(])", source
    )
    assert not re.search(
        r"(?m)^:[ \t]+O2TOK-WITH-REFRESH(?=[ \t\r\n(])", source
    )
    assert not re.search(
        r"(?m)^:[ \t]+O2TOK-PRESENT\?(?=[ \t\r\n(])", source
    )
    assert not re.search(r"(?m)^:[ \t]+O2TOK\.REFRESH(?:-U)?\b", source)
    for retired in (
        r"\bO2TOK-UPDATE\b",
        r"\bO2TOK-WITH-REFRESH(?!-LEASE)\b",
        r"\bO2TOK-PRESENT\?",
    ):
        assert not re.search(retired, auth)
        assert not re.search(retired, harness_source)

    object_status = _word_body(source, "_O2TOK-OBJECT-STATUS")
    assert "OAUTH2-TOKEN-SET-SIZE _O2TOK-ADMIT-SPAN" in object_status
    source_status = _word_body(source, "_O2TOK-SOURCE-STATUS")
    assert "_O2TOK-ADMIT-SPAN" in source_status
    assert "OAUTH2-TOKEN-SET-SIZE MSPAN-OVERLAP?" in source_status

    set_geometry = _word_body(source, "_O2TOK-SET-GEOMETRY")
    commit_geometry = _word_body(source, "_O2TOK-COMMIT-GEOMETRY")
    for body in (set_geometry, commit_geometry):
        assert "_O2TOK-OBJECT-STATUS" in body
        assert body.count("_O2TOK-SOURCE-STATUS") == 3
        assert not re.search(
            r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
            r"(?![A-Za-z0-9_-])",
            body,
        ), "geometry must not mutate caller storage"
    assert "1 PICK 0<" in set_geometry
    assert "2 PICK 0<" in commit_geometry
    assert "_O2TOK-LEASE-DESC-STATUS" in commit_geometry
    assert commit_geometry.count("_O2TOK-LEASE-SOURCE-OVERLAP?") == 3
    assert (
        "6 PICK 6 PICK O2TOK-ACCESS-CAPACITY -1 4 PICK"
        in commit_geometry
    )

    set_body = _word_body(source, "_O2TOK-SET-BODY")
    commit_body = _word_body(source, "_O2TOK-COMMIT-BODY")
    for body in (set_body, commit_body):
        assert body.index("_O2TOK-STAGE-ALL") < body.index(
            "_O2TOK-PUBLISH-STAGE"
        )
    assert "_O2TOK-PRESENT-LOCKED?" in set_body
    assert "_O2TOK-LEASE-MATCH?" in commit_body
    assert "_O2TOK-MODE-COMMIT" in commit_body

    publish = _word_body(source, "_O2TOK-PUBLISH-STAGE")
    assert publish.index("_O2TOK-WIPE-LIVE") < publish.index(
        "_O2TOK.STAGE-ACCESS R@ O2TOK.ACCESS"
    )
    assert publish.index("_O2TOK.STAGE-REFRESH R@ _O2TOK.REFRESH") < (
        publish.index("_O2TOK-WIPE-STAGE")
    )
    assert "O2TOK.GENERATION _O2TOK-NEXT-NONZERO" in publish
    assert "_O2TOK-CLEAR-LEASE" in publish

    borrow_run = _word_body(source, "_O2TOK-BORROW-RUN")
    assert "CATCH" in borrow_run
    assert borrow_run.index("CATCH") < borrow_run.index(
        "0 R@ O2TOK.BORROWED !"
    )
    assert "O2TOK-S-CALLBACK" in borrow_run

    leased_borrow = _word_body(source, "O2TOK-WITH-REFRESH-LEASE")
    assert leased_borrow.index("-1 OVER _O2TOK.LEASE-USED !") < (
        leased_borrow.index("_O2TOK-BORROW-RUN")
    )
    assert "_O2TOK-LEASE-MATCH?" in leased_borrow

    begin = _word_body(source, "O2TOK-REFRESH-BEGIN")
    assert "_O2TOK.LEASE-ID @" in begin
    assert "_O2TOK.LEASE-SEQUENCE _O2TOK-NEXT-NONZERO" in begin
    assert "O2TOK.GENERATION @" in begin
    assert "_O2TOK-LEASE-DESC-STATUS" in begin
    assert "_O2LEASE.OWNER" in begin
    assert "_O2LEASE.GENERATION" in begin
    assert "_O2LEASE.ID" in begin

    abort = _word_body(source, "O2TOK-REFRESH-ABORT")
    assert "_O2TOK-LEASE-MATCH?" in abort
    assert "_O2TOK-CLEAR-LEASE" in abort
    assert "O2TOK.GENERATION _O2TOK-NEXT-NONZERO" not in abort

    token_status = _word_body(auth, "_CDA-TOKEN-STATUS")
    assert "AAUTH-S-INVALID SWAP" in token_status
    assert "DROP AAUTH-S-INVALID" not in token_status
    codex_refresh = _word_body(auth, "_CDA-REFRESH")
    assert "O2TOK-REFRESH-BEGIN" in codex_refresh
    assert "O2TOK-WITH-REFRESH-LEASE" in codex_refresh
    assert codex_refresh.count("_CDA-REFRESH-ABORT?") == 2
    assert "_CDA-TRANSIENT-CLEAR" in codex_refresh
    assert "O2TOK-CLEAR" not in codex_refresh
    for terminal in ("_CDA-CANCEL", "_CDA-LOGOUT"):
        assert "_CDA-TOKENS-CLEAR?" in _word_body(auth, terminal)
    assert "CDA.REFRESH-LEASE _O2LEASE.OWNER @" in harness_source
    assert "CDA.TOKENS _O2TOK.LEASE-USED @ -1 =" in harness_source

    fixture = CONTRACT.read_text(encoding="utf-8")
    for test_word in (
        "_otst-test-set-stage-and-alias",
        "_otst-test-optional-refresh-and-id",
        "_otst-test-access-borrow",
        "_otst-test-lease-throw-and-abort",
        "_otst-test-lease-commit",
        "_otst-test-cross-object-lease",
        "_otst-test-clear-invalidates-lease",
    ):
        assert test_word in fixture
    assert "O2TOK-S-CALLBACK" in fixture
    assert "O2TOK-S-STALE" in fixture
    assert "_O2TOK.STAGE-ACCESS" in fixture
    assert "_otst-tokens-b" in fixture
    assert "_O2LEASE.OWNER" in fixture


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/token-set.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 TOKEN SET PASS",),
        stable_markers=("OAUTH2 TOKEN SET PASS",),
        failure_markers=(
            "OAUTH2 TOKEN SET FAIL",
            "OAUTH2 TOKEN SET ASSERT",
            "OAUTH2 TOKEN SET STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/oauth2-token-set-test.f", CONTRACT.read_bytes()),
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
        max_steps=500_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
