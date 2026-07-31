#!/usr/bin/env python3
"""Focused qualification for caller-owned JSON quoted-string output."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "utils" / "json-writer.f"
DOC = ROOT / "docs" / "utils" / "json-writer.md"
CONTRACT = LOCAL_TESTING / "json-writer-test.f"
PROFILE = "json-writer-contracts"
IMAGE = Path("/tmp/akashic-json-writer-contracts.img")

AUTOEXEC = r"""\ autoexec.f - caller-owned JSON writer contracts
ENTER-USERLAND
REQUIRE utils/json-writer.f
REQUIRE local_testing/json-writer-test.f
_JWT-RUN
TX-FLUSH
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
                "KDOS parenthesized comments must close on their "
                f"physical line: {path}:{line_number}"
            )


def test_json_writer_source_contract() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert "PROVIDED akashic-json-writer" in source
    assert re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    ) == ["buffer-writer.f", "../text/utf8.f"]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    )
    assert not re.search(
        r"(?mi)^.*\bCONSTANT\b.*\b(?:MAX|CAPACITY|LIMIT)\b",
        source,
    )

    for word in (
        "JSONW-STRING-MEASURE",
        "JSONW-STRING",
        "UTF8-VALID?",
        "_CBW-RESERVE",
        "_JSONW-ROLLBACK-INVALID",
    ):
        assert word in source

    measure = _word_body(source, "JSONW-STRING-MEASURE")
    assert "_CBW-SOURCE-VALID?" in measure
    assert "UTF8-VALID?" in measure
    assert "_JSONW-MEASURE-VALID" in measure

    append = _word_body(source, "JSONW-STRING")
    assert append.count("_CBW-RESERVE") == 1
    assert append.index("_CBW-RESERVE") < append.index("C!")
    assert "MSPAN-OVERLAP?" in append
    assert "_JSONW-ROLLBACK-INVALID" in append
    assert "CBW-S-INVALID _JSONW-FAIL" in append

    for phrase in (
        "no process-global builder",
        "payload ceiling",
        "strict UTF-8",
        "uppercase `\\u00XX`",
        "Independent writers can be used in any interleaving",
        "complete representation before writing any byte",
        "earlier, disjoint part of the same output arena",
    ):
        assert phrase in doc

    assert "PROVIDED json-writer-test" in fixture
    assert len(CONTRACT.name) <= 23
    for test_word in (
        "_JWT-TEST-MEASURE",
        "_JWT-TEST-INTERLEAVED",
        "_JWT-TEST-ESCAPES-AND-UTF8",
        "_JWT-TEST-ATOMIC-CAPACITY",
        "_JWT-TEST-INVALID-AND-STICKY",
        "_JWT-TEST-ALIAS-POLICY",
    ):
        assert test_word in fixture
    assert "_JWT-ESCAPE-EXPECTED 35" in fixture
    assert "_JWT-BUFFER-A 128 0xA5 _JWT-FILLED?" in fixture
    assert "_JWT-BUFFER-A 3 _JWT-WRITER-A JSONW-STRING" in fixture

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _linked_contracts() -> bool:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("utils/json-writer.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("JSON WRITER PASS",),
        stable_markers=("JSON WRITER PASS",),
        failure_markers=(
            "JSON WRITER FAIL",
            "JSON WRITER ASSERT",
            "JSON WRITER STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(("local_testing/json-writer-test.f", CONTRACT.read_bytes()),),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    return harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=180_000_000,
        timeout=120.0,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source contracts without building or running an image",
    )
    args = parser.parse_args()

    test_json_writer_source_contract()
    if args.static_only:
        print("JSON WRITER STATIC PASS")
        return 0
    return 0 if _linked_contracts() else 1


if __name__ == "__main__":
    raise SystemExit(main())
