"""Host-only source contracts for the relocatable binary-image builder."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic" / "utils" / "binimg.f"


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def test_build_into_uses_checked_range_geometry_with_typed_failures() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    body = _word_body(source, "IMG-BUILD-INTO")
    capacity_check = (
        "_img-build-dst @ 0=\n"
        "    _img-build-cap @ _img-build-used @ < OR IF "
        "0 IMG-E-CAPACITY EXIT THEN"
    )
    destination_check = (
        "_img-build-dst @ _img-build-used @ URANGE-VALID? 0= IF\n"
        "        0 IMG-E-CAPACITY EXIT"
    )
    live_check = (
        "_img-reloc-buf @ HERE _img-reloc-buf @ - URANGE-VALID? 0= IF\n"
        "        0 IMG-E-STATE EXIT"
    )
    overlap_check = (
        "_img-build-dst @ _img-build-used @\n"
        "    _img-reloc-buf @ HERE _img-reloc-buf @ -\n"
        "    URANGE-OVERLAP? 0= IF DROP 0 IMG-E-STATE EXIT THEN\n"
        "    IF 0 IMG-E-STATE EXIT THEN"
    )

    assert "REQUIRE uint-range.f" in source
    assert "_IMG-RANGE-OVERLAP?" not in source
    assert body.count("URANGE-VALID?") == 2
    assert body.count("URANGE-OVERLAP?") == 1
    assert body.index(capacity_check) < body.index(destination_check)
    assert body.index(destination_check) < body.index(live_check)
    assert body.index(live_check) < body.index(overlap_check)


def test_loaded_provided_identity_uses_public_exact_span_registration() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    body = _word_body(source, "_IMG-REGISTER-PROVIDED")
    assert "NAMEBUF _img-request-len @ PROVIDED-SPAN" in body
    assert "_MOD-MARK" not in source
