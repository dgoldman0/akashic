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
    assert expected == 1888
    for name in (
        "_RTHP.TARGET0-A",
        "_RTHP.TARGET1-A",
        "_RTHP.TARGET-ACTIVE",
        "_RTHP.TARGET-PENDING",
    ):
        assert _offset(source, name) == expected
        expected += 8
    assert _constant(source, "RTHP-SIZE") == expected == 1920


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


def test_native_menu_targets_are_built_once_into_the_inactive_bounded_bank() -> None:
    source = _source()
    sizing = _word(source, "_RTHP-BYTES-BODY")
    layout = _word(source, "_RTHP-LAYOUT")
    build = _word(source, "_RTHP-TARGET-CANDIDATE?")
    candidate_shape = _word(source, "_RTHP-CT-CANDIDATE-SHAPE?")
    find_control = _word(source, "_RTHP-CT-FIND-CONTROL?")
    control = _word(source, "_RTHP-CT-CONTROL?")
    target_control = _word(source, "_RTHP-CT-TARGET?")
    correlation_at = _word(source, "_RTHP-CT-CORRELATION-AT?")
    correlation = _word(source, "_RTHP-CT-CORRELATION?")
    record = _word(source, "_RTHP-CT-RECORD?")
    geometry = _word(source, "_RTHP-CT-GEOMETRY?")
    prepare = _word(source, "_RTHP-PREPARE-START")

    assert sizing.count("_RTHP-TARGET-BANK-HEADER-SIZE _RTHP-B-ADD") == 2
    assert sizing.count(
        "_RTHP-B-RECORDS @ _RTHP-TARGET-ENTRY-SIZE _RTHP-B-MUL-ADD"
    ) == 2
    assert layout.count("_RTHP.TARGET0-A") == 1
    assert layout.count("_RTHP.TARGET1-A") == 1
    assert "_RTHP-TARGET-INACTIVE" in build
    assert "_RTHP.TARGET-PENDING" in build
    assert "_RTHP-CT-CANDIDATE-SHAPE?" in build
    assert build.count("0 ?DO") == 1
    assert "0 ?DO" not in correlation_at
    assert "0 ?DO" not in find_control
    assert "_RTHP.FIRST-OBJECT" in find_control
    assert "_RTHP.CONTROLS-A" in find_control
    assert build.index("_RTHP-CT-CORRELATION-AT?") < build.index(
        "_RTHP-CT-FIND-CONTROL?"
    )
    assert candidate_shape.count("_RTHP-ARENA-SPAN?") == 3
    for bounded_bank in (
        "_RTHP.SOURCE-RECS-A",
        "_RTHP.CONTROLS-A",
        "_RTHP.CORR-A",
    ):
        assert bounded_bank in candidate_shape
    assert "RTE-CONTROL-MENU" in target_control
    assert "RTE-CONTROL-MENU-ITEM" in target_control
    assert "RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR" in target_control
    for exact in (
        "_RTE-CONTROL.OWNER",
        "_RTE-CONTROL.GENERATION",
        "_RTE-CONTROL.ID",
    ):
        assert exact in control
    assert "RTE-CONTROL-MENU" in control
    assert "RTE-CONTROL-MENU-ITEM" in control
    assert "RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR" in control

    assert "RUCP-CORRELATION-CONTROL-ID@" in correlation_at
    assert "RUCP-CORRELATION-ATTACHMENT@" in correlation
    assert "RUCP-CORRELATION-SOURCE@" in correlation
    assert "RUCP-CORRELATION-SUBKEY@" in correlation
    assert "_RTHP.SOURCE-RECS-A" in correlation
    assert "UMSN-RECORD-GENERATION@" in record
    assert "UMSN-RECORD-SOURCE-INDEX@" in record
    assert "_UMSN-R.SOURCE" in record
    assert "UMSN-F-PAINTABLE" not in record
    assert "UMSN-RECORD-RESOLVED" not in record
    assert "UTUI-RESOLVED-VALID?" not in record
    assert "UMSN-RECORD-RESOLVED" in geometry
    assert "UTUI-RESOLVED-VALID?" in geometry
    assert "_RTE-CONTROL.ROW" not in geometry
    assert "_RTE-CONTROL.COL" not in geometry
    assert "_RTHP.ROWS" in geometry
    assert "_RTHP.COLS" in geometry
    for metadata in (
        "_RTHP-TB.OWNER",
        "_RTHP-TB.GENERATION",
        "_RTHP-TB.COLS",
        "_RTHP-TB.ROWS",
        "_RTHP-TB.COUNT",
    ):
        assert metadata in build
    for entry in ("_RTHP-TE.ID", "_RTHP-TE.ROW", "_RTHP-TE.COL"):
        assert entry in build
    assert "UMSN-F-PAINTABLE" in build
    assert prepare.index("_RTHP-FIXED?") < prepare.index(
        "_RTHP-TARGET-CANDIDATE?"
    ) < prepare.index("RTE-RETAINED-BEGIN")
    assert "_RTHP-TARGET-CONTROL?" not in _word(source, "_RTHP-EMIT-CONTROLS")


def test_only_the_exactly_revealed_target_bank_becomes_input_active() -> None:
    source = _source()
    sealed = _word(source, "_RTHP-STEP-SEALED")
    publish = _word(source, "_RTHP-TARGET-PUBLISH?")
    lookup = _word(source, "RTHP-CONTROL-MENU-TARGET@")
    header = _word(source, "_RTHP-TARGET-BANK-HEADER?")
    entries = _word(source, "_RTHP-TARGET-BANK-ENTRIES?")
    find = _word(source, "_RTHP-TARGET-BANK-FIND?")
    live = _word(source, "RTHP-LIVE?")

    accepted = "_RTHP-Z-ACCEPT @ _RTHP-Z-P @ _RTHP.PHASE !"
    assert sealed.index(accepted) < sealed.index("_RTHP-TARGET-PUBLISH?")
    assert "_RTHP-PH-LIVE = IF" in sealed
    assert "_RTHP.TARGET-PENDING" in publish
    assert publish.index("_RTHP-TARGET-BANK-ENTRIES?") < publish.index(
        "_RTHP.TARGET-ACTIVE !"
    )
    assert publish.index("_RTHP.TARGET-PENDING !") < publish.index(
        "_RTHP.TARGET-ACTIVE !"
    )

    assert "_RTHP.TARGET-ACTIVE" in lookup
    assert "_RTHP-TARGET-BANK-HEADER?" in lookup
    assert "_RTHP-TARGET-BANK-FIND?" in lookup
    assert "_RTHP.PHASE" not in lookup
    assert "_RTHP.OWNER" in lookup
    assert "_RTHP.OWNER-GEN" in lookup
    assert "_RTHP.TARGET-ACTIVE" in live
    assert "_RTHP.PHASE" not in live
    assert entries.count("0 ?DO") == 1
    assert find.count("0 ?DO") == 1
    assert "_RTHP-TL-MATCHES @ 1 =" in find
    for candidate_bank in (
        "_RTHP.SOURCE-RECS-A",
        "_RTHP.CONTROLS-A",
        "_RTHP.CORR-A",
        "_RTHP.ADMISSION",
    ):
        assert candidate_bank not in lookup + header + find
    for metadata in (
        "_RTHP-TB.OWNER",
        "_RTHP-TB.GENERATION",
        "_RTHP-TB.COLS",
        "_RTHP-TB.ROWS",
        "_RTHP-TB.COUNT",
    ):
        assert metadata in lookup + header + find
