#!/usr/bin/env python3
"""Focused source qualification for stateless form encoding and decoding."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "net" / "form-urlencoded.f"
DOC = ROOT / "docs" / "net" / "form-urlencoded.md"
CONTRACT = LOCAL_TESTING / "form-urlencoded-test.f"
PROFILE = "form-urlencoded-contracts"
IMAGE = Path("/tmp/akashic-form-urlencoded-contracts.img")

AUTOEXEC = r"""\ autoexec.f - stateless form component codec contracts
ENTER-USERLAND
REQUIRE net/form-urlencoded.f
REQUIRE local_testing/form-urlencoded-test.f
_FUET-RUN
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


def test_form_urlencoded_source_contract() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    lowered = source.lower()

    assert "PROVIDED akashic-form-urlencoded" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    )
    assert re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    ) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
    ]
    for forbidden in ("atproto", "streams", "session", "xrpc"):
        assert forbidden not in lowered

    for word in (
        "FORM-URLENCODED-S-OK",
        "FORM-URLENCODED-S-INVALID",
        "FORM-URLENCODED-S-CAPACITY",
        "FORM-URLENCODED-S-ALIAS",
        "FORM-URLENCODED-S-RANGE",
        "FORM-URLENCODED-S-PROTECTED",
        "FORM-URLENCODED-S-PLATFORM",
        "FORM-URLENCODED-S-ENCODING",
        "FORM-URLENCODED-STATUS-VALID?",
        "FORM-URLENCODED-MEASURE",
        "FORM-URLENCODED-ENCODE",
        "FORM-URLENCODED-DECODE-MEASURE",
        "FORM-URLENCODED-DECODE",
    ):
        assert word in source

    literal = _word_body(source, "_FUE-LITERAL?")
    for spelling in (
        "48 58 WITHIN",
        "65 91 WITHIN",
        "97 123 WITHIN",
        "42 =",
        "45 =",
        "46 =",
        "95 =",
    ):
        assert spelling in literal

    size = _word_body(source, "_FUE-BYTE-SIZE")
    assert "_FUE-LITERAL?" in size
    assert "32 =" in size

    geometry = _word_body(source, "_FUE-GEOMETRY")
    assert geometry.count("_FUE-SPAN-STATUS") >= 2
    assert "MSPAN-OVERLAP?" in geometry
    assert "FORM-URLENCODED-MEASURE" in geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        geometry,
    )

    encode = _word_body(source, "FORM-URLENCODED-ENCODE")
    assert encode.index("_FUE-GEOMETRY") < encode.index("C!")
    assert "_FUE-ESCAPE" in encode
    assert "BEGIN OVER WHILE" in encode
    assert "2 PICK C@" in encode
    assert "_FUE-NEXT" in encode
    escape = _word_body(source, "_FUE-ESCAPE")
    assert "37" in escape
    assert "4 RSHIFT" in escape
    assert "15 AND" in escape

    measure = _word_body(source, "FORM-URLENCODED-MEASURE")
    assert "BEGIN OVER WHILE" in measure
    assert "2 PICK C@" in measure
    assert "_FUE-NEXT" in measure

    hex_value = _word_body(source, "_FUE-HEX-VALUE")
    for spelling in ("48 58 WITHIN", "65 71 WITHIN", "97 103 WITHIN"):
        assert spelling in hex_value

    decode_measure = _word_body(
        source, "FORM-URLENCODED-DECODE-MEASURE"
    )
    assert decode_measure.count("_FUE-HEX-VALUE") == 2
    assert "FORM-URLENCODED-S-ENCODING" in decode_measure

    decode_geometry = _word_body(source, "_FUE-DECODE-GEOMETRY")
    assert decode_geometry.count("_FUE-SPAN-STATUS") >= 2
    assert "MSPAN-OVERLAP?" in decode_geometry
    assert "FORM-URLENCODED-DECODE-MEASURE" in decode_geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        decode_geometry,
    )

    decode = _word_body(source, "FORM-URLENCODED-DECODE")
    assert decode.index("_FUE-DECODE-GEOMETRY") < decode.index("C!")
    assert "DUP 43 = IF DROP 32 THEN" in decode
    assert "4 LSHIFT OR" in decode

    doc = DOC.read_text(encoding="utf-8")
    assert "application/x-www-form-urlencoded" in doc
    assert "Space becomes" in doc
    assert "source/destination overlap" in doc
    assert "uppercase or lowercase hexadecimal digits" in doc
    assert "incomplete or malformed percent escape" in doc
    assert "duplicate decoded names" in doc

    fixture = CONTRACT.read_text(encoding="utf-8")
    assert "PROVIDED akashic-fue-contracts" in fixture
    for test_word in (
        "_fuet-test-encode-vector",
        "_fuet-test-decode-vector",
        "_fuet-test-malformed",
        "_fuet-test-capacity-and-shape",
        "_fuet-test-aliases",
        "_fuet-test-all-bytes-round-trip",
    ):
        assert test_word in fixture
    assert "2 PICK C@ OVER <>" in fixture
    assert "DUP DUP _fuet-source + C!" in fixture


def _linked_contracts() -> bool:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("net/form-urlencoded.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("FORM URLENCODED PASS",),
        stable_markers=("FORM URLENCODED PASS",),
        failure_markers=(
            "FORM URLENCODED FAIL",
            "FORM URLENCODED ASSERT",
            "FORM URLENCODED STATUS",
            "FORM URLENCODED STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/form-urlencoded-test.f", CONTRACT.read_bytes()),
        ),
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
        max_steps=250_000_000,
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

    test_form_urlencoded_source_contract()
    if args.static_only:
        print("FORM URLENCODED STATIC PASS")
        return 0
    return 0 if _linked_contracts() else 1


if __name__ == "__main__":
    raise SystemExit(main())
