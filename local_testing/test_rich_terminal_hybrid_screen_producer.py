"""Seconds-only locks for the first complete hybrid screen producer."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PRODUCER = ROOT / "akashic/tui/rich-terminal/hybrid-screen-producer.f"


def _source() -> str:
    return PRODUCER.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _constant(source: str, name: str) -> int:
    match = re.search(
        rf"(?m)^\s*(0x[0-9A-Fa-f]+|[0-9]+)\s+CONSTANT\s+"
        rf"{re.escape(name)}\s*$",
        source,
    )
    assert match is not None, name
    return int(match.group(1), 0)


def _offset(source: str, name: str) -> int:
    definition = _word(source, name)
    match = re.search(r"\([^)]*--[^)]*\)\s*(?:(\d+)\s+\+)?\s*;", definition)
    assert match is not None, name
    return int(match.group(1) or 0)


def test_inline_records_are_disjoint_and_exactly_cover_the_producer() -> None:
    source = _source()
    records = (
        ("_RTHP.LIMITS", 168),
        ("_RTHP.RUCP-Q", 248),
        ("_RTHP.RUCL-Q", 112),
        ("_RTHP.RGRP-Q", 248),
        ("_RTHP.CONTROL-PLAN", 112),
        ("_RTHP.GLYPH-PLAN", 112),
        ("_RTHP.HYBRID", 96),
        ("_RTHP.ADMISSION", 176),
        ("_RTHP.RUN", 152),
    )
    expected = 464
    for name, size in records:
        assert _offset(source, name) == expected
        expected += size
    assert _constant(source, "RTHP-SIZE") == expected == 1888


def test_candidate_is_copied_planned_and_admitted_once_before_owner_open() -> None:
    source = _source()
    attempt = _word(source, "_RTHP-TRY-CANDIDATE")
    ordered = (
        "_RTHP-COPY-SNAPSHOT?",
        "_RTHP-BUILD-CONTROLS?",
        "_RTHP-BUILD-CLAIMS?",
        "_RTHP-BUILD-GLYPHS?",
        "_RTHP-WRAP-HYBRID",
        "RTE-HYBRID-PREFLIGHT",
        "_RTHP-OPEN",
    )
    positions = [attempt.index(item) for item in ordered]
    assert positions == sorted(positions)
    assert attempt.count("RTE-HYBRID-PREFLIGHT") == 1
    assert _source().count("RTE-HYBRID-PREFLIGHT") == 1
    assert "RTE-CONTROL-PREFLIGHT" not in source
    assert "RTE-GLYPH-RUN-PREFLIGHT" not in source


def test_final_capture_rechecks_fixed_authority_then_traverses_each_family_once() -> None:
    source = _source()
    start = _word(source, "_RTHP-PREPARE-START")
    assert start.index("_RTHP-FIXED?") < start.index("RTE-RETAINED-BEGIN")
    assert start.count("_RTHP-EMIT-CONTROLS") == 1
    assert start.count("_RTHP-EMIT-GLYPHS") == 1
    controls = _word(source, "_RTHP-EMIT-CONTROLS")
    glyphs = _word(source, "_RTHP-EMIT-GLYPHS")
    assert controls.count("?DO") == len(re.findall(r"(?m)^\s*LOOP\s*$", controls)) == 1
    assert glyphs.count("?DO") == len(re.findall(r"(?m)^\s*LOOP\s*$", glyphs)) == 1
    assert ">R" not in controls + glyphs


def test_sealed_retry_preserves_the_exact_candidate() -> None:
    prepare = _word(_source(), "RTHP-PREPARE")
    start_sealed = prepare.split("_RTHP-PH-START-SEALED = IF", 1)[1].split(
        "THEN", 1
    )[0]
    reveal_sealed = prepare.split("_RTHP-PH-REVEAL-SEALED = IF", 1)[1].split(
        "THEN", 1
    )[0]
    assert "SCB-S-OK EXIT" in start_sealed
    assert "SCB-S-OK EXIT" in reveal_sealed
    assert "_RTHP-PREPARE-START" not in start_sealed
    assert "_RTHP-PREPARE-REVEAL" not in reveal_sealed


def test_slice_remains_generic_caller_bounded_and_digest_free() -> None:
    source = _source()
    lowered = source.lower()
    assert "allocate" not in lowered
    assert "xbuf" not in lowered
    assert "sha3" not in lowered
    assert "pad-entry" not in lowered
    assert "daybook-entry" not in lowered
    for required in (
        "RTHP-STORAGE-BYTES",
        "RUHA-SNAPSHOT@",
        "RUCP-BUILD",
        "RUCL-BUILD",
        "RGRP-BUILD",
        "RTE-CONTROL-DEFINE",
        "RTE-GLYPH-RUN-DEFINE",
    ):
        assert required in source


def test_native_menu_target_is_correlated_to_safe_source_geometry() -> None:
    source = _source()
    target = _word(source, "RTHP-CONTROL-MENU-TARGET@")
    live_shape = _word(source, "_RTHP-CT-LIVE-SHAPE?")
    find_control = _word(source, "_RTHP-CT-FIND-CONTROL?")
    control = _word(source, "_RTHP-CT-CONTROL?")
    find_correlation = _word(source, "_RTHP-CT-FIND-CORRELATION?")
    correlation = _word(source, "_RTHP-CT-CORRELATION?")
    record = _word(source, "_RTHP-CT-RECORD?")
    geometry = _word(source, "_RTHP-CT-GEOMETRY?")

    assert "_RTHP-CT-LIVE-SHAPE?" in target
    assert "_RTHP-FIXED?" not in target
    assert "_RTHP-PH-LIVE" in live_shape
    assert "_RTHP.SOURCE-USED" in live_shape
    assert "_RTHP.CONTROLS-U" in live_shape
    assert "_RTHP.CORR-U" in live_shape
    assert "_RTHP-CT-IN-ARENA?" in live_shape
    assert "0 ?DO" not in live_shape
    assert "0 ?DO" not in find_control
    assert "_RTHP.FIRST-OBJECT" in find_control
    assert "0 ?DO" in find_correlation
    for identity in ("_RTHP.OWNER", "_RTHP.OWNER-GEN", "_RTHP-CT-ID"):
        assert identity in target
    for exact in (
        "_RTE-CONTROL.OWNER",
        "_RTE-CONTROL.GENERATION",
        "_RTE-CONTROL.ID",
    ):
        assert exact in control
    assert "RTE-CONTROL-MENU" in control
    assert "RTE-CONTROL-MENU-ITEM" in control
    assert "RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR" in control

    assert "RUCP-CORRELATION-ATTACHMENT@" in correlation
    assert "RUCP-CORRELATION-SOURCE@" in correlation
    assert "RUCP-CORRELATION-SUBKEY@" in correlation
    assert "_RTHP.SOURCE-RECS-A" in correlation
    assert "UMSN-RECORD-GENERATION@" in record
    assert "UMSN-RECORD-SOURCE-INDEX@" in record
    assert "_UMSN-R.SOURCE" in record
    assert "UMSN-F-PAINTABLE" in record
    assert "UMSN-RECORD-RESOLVED" in record
    assert "UTUI-RESOLVED-VALID?" in record
    assert "_RTE-CONTROL.ROW" not in geometry
    assert "_RTE-CONTROL.COL" not in geometry
    assert "_RTHP.ROWS" in geometry
    assert "_RTHP.COLS" in geometry
