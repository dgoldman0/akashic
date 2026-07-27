#!/usr/bin/env python3
"""Focused source qualification for the stateless form encoder."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic" / "net" / "form-urlencoded.f"
DOC = ROOT / "docs" / "net" / "form-urlencoded.md"


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
        "FORM-URLENCODED-STATUS-VALID?",
        "FORM-URLENCODED-MEASURE",
        "FORM-URLENCODED-ENCODE",
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
    escape = _word_body(source, "_FUE-ESCAPE")
    assert "37" in escape
    assert "4 RSHIFT" in escape
    assert "15 AND" in escape

    doc = DOC.read_text(encoding="utf-8")
    assert "application/x-www-form-urlencoded" in doc
    assert "Space becomes" in doc
    assert "source/destination overlap" in doc


if __name__ == "__main__":
    test_form_urlencoded_source_contract()
    print("form-urlencoded source contracts: ok")
