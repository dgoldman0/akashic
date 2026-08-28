"""Seconds-only locks for the complete hybrid screen producer."""

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
        "_RTHP.NEXT-REGION",
        "_RTHP.NEXT-OBJECT",
        "_RTHP.ACTIVE-DRAW",
    ):
        assert _offset(source, name) == expected
        expected += 8
    for name in (
        "_RTHP.MAX-DOCUMENTS",
        "_RTHP.SOURCE-DIR-A",
        "_RTHP.SOURCE-DIR-U",
        "_RTHP.SOURCE-DIR-USED",
        "_RTHP.DOCUMENT-COUNT",
    ):
        assert _offset(source, name) == expected
        expected += 8
    assert _constant(source, "RTHP-SIZE") == expected == 1984


def test_visible_document_directory_is_caller_bounded_copied_and_appended() -> None:
    source = _source()
    sizing = _word(source, "_RTHP-BYTES-BODY")
    storage = _word(source, "RTHP-STORAGE-BYTES")
    layout = _word(source, "_RTHP-LAYOUT")
    init = _word(source, "RTHP-INIT")
    snapshot_shape = _word(source, "_RTHP-W-SNAPSHOT-SPANS?")
    copy = _word(source, "_RTHP-COPY-SNAPSHOT?")
    controls = _word(source, "_RTHP-BUILD-CONTROLS?")
    claims = _word(source, "_RTHP-BUILD-CLAIMS?")
    wrap_control = _word(source, "_RTHP-W-WRAP-CONTROL-PLAN?")
    document_at = _word(source, "_RTHP-DOCUMENT-AT")
    target_build = _word(source, "_RTHP-TARGET-CANDIDATE?")

    assert "max-documents max-records" in storage
    assert "_RTHP-B-DOCUMENTS" in storage
    assert "_RTHP-B-DOCUMENTS @ RUHA-DOCUMENT-SIZE" in sizing
    assert "_RTHP.MAX-DOCUMENTS @ RUHA-DOCUMENT-SIZE" in layout
    assert "_RTHP.SOURCE-DIR-A" in layout
    assert "RUHA-DOCUMENT-CAPACITY@" in init
    assert "_RTHP.MAX-DOCUMENTS !" in init
    assert source.index(document_at) < source.index(target_build)

    for aggregate in (
        "RUHA-SNAPSHOT-DOCUMENT-COUNT@",
        "RUHA-SNAPSHOT-DIRECTORY@",
        "RUHA-SNAPSHOT-RECORDS@",
        "RUHA-SNAPSHOT-TEXT@",
    ):
        assert aggregate in snapshot_shape
    for field in (
        "RUHA-DOCUMENT-TOKEN@",
        "RUHA-DOCUMENT-SLOT-ID@",
        "RUHA-DOCUMENT-ROW@",
        "RUHA-DOCUMENT-COL@",
        "RUHA-DOCUMENT-HEIGHT@",
        "RUHA-DOCUMENT-WIDTH@",
        "RUHA-DOCUMENT-RECORD-OFFSET@",
        "RUHA-DOCUMENT-RECORD-BYTES@",
        "RUHA-DOCUMENT-TEXT-OFFSET@",
        "RUHA-DOCUMENT-TEXT-BYTES@",
    ):
        assert field in source
    assert snapshot_shape.count("_RTHP-W-DOCUMENT-SHAPE?") == 1
    assert "_RTHP.SOURCE-DIR-A" in copy
    assert "_RTHP.SOURCE-DIR-USED" in copy
    assert "_RTHP.SOURCE-DRAW !" in copy
    assert "_RTHP.DOCUMENT-COUNT !" in copy

    for build, planner in ((controls, "RUCP-BUILD"), (claims, "RUCL-BUILD")):
        assert "_RTHP-W-COPIED-DOCUMENT?" in build
        assert "_RTHP-W-DOC-RECORD-O" in build
        assert "_RTHP-W-DOC-RECORD-COUNT" in build
        assert build.count(planner) == 1
        assert "BEGIN _RTHP-W-DOCUMENT-I @" in build
        assert "_RTHP-W-COPIED-COMPLETE?" in build
    assert "_RTHP-W-DOC-TEXT-O" in controls
    assert "_RTHP-W-NEXT-ID" in controls
    assert "_RTHP-W-WRAP-CONTROL-PLAN?" in controls
    assert "RUCP-BUILD" not in wrap_control
    assert "_RTHP.CONTROLS-A" in wrap_control


def test_candidate_is_copied_planned_and_admitted_once_before_owner_open() -> None:
    source = _source()
    build = _word(source, "_RTHP-BUILD-CANDIDATE")
    attempt = _word(source, "_RTHP-TRY-CANDIDATE")
    ordered = (
        "_RTHP-COPY-SNAPSHOT?",
        "_RTHP-BUILD-CONTROLS?",
        "_RTHP-BUILD-CLAIMS?",
        "_RTHP-BUILD-GLYPHS?",
        "_RTHP-WRAP-HYBRID",
        "RTE-HYBRID-PREFLIGHT",
        "_RTHP-DRAW-CURRENT?",
    )
    positions = [build.index(item) for item in ordered]
    assert positions == sorted(positions)
    assert build.count("RTE-HYBRID-PREFLIGHT") == 1
    assert "_RTHP-OPEN" not in build
    assert "_RTHP.PHASE !" not in build
    assert attempt.index("_RTHP-BUILD-CANDIDATE") < attempt.index("_RTHP-OPEN")
    assert _source().count("RTE-HYBRID-PREFLIGHT") == 1
    assert "RTE-CONTROL-PREFLIGHT" not in source
    assert "RTE-GLYPH-RUN-PREFLIGHT" not in source


def test_owner_open_reserves_one_frame_independently_of_current_content() -> None:
    source = _source()
    open_owner = _word(source, "_RTHP-OPEN")

    assert "_RTHP.ADMISSION" not in open_owner
    for bound in (
        "_RTHP.MAX-RECORDS",
        "_RTHP.MAX-COLS",
        "_RTHP.MAX-ROWS",
        "_RTHP.MAX-TEXT",
        "RTE-LIMITS-OBJECTS@",
        "RTE-LIMITS-UTF8-BYTES@",
    ):
        assert bound in open_owner
    assert open_owner.count("_RTHP-UMIN") == 2
    assert "1 0 _RTHP-O-OBJECTS @ 0 0 _RTHP-O-TEXT @ 0" in open_owner


def test_candidate_ids_advance_only_after_exact_hidden_start_ack() -> None:
    source = _source()
    init = _word(source, "RTHP-INIT")
    build = _word(source, "_RTHP-BUILD-CANDIDATE")
    fixed = _word(source, "_RTHP-FIXED-BODY?")
    candidate_last = _word(source, "_RTHP-CANDIDATE-LAST-OBJECT")
    successors = _word(source, "_RTHP-CANDIDATE-NEXT?")
    advance = _word(source, "_RTHP-ADVANCE-IDS?")
    sealed = _word(source, "_RTHP-STEP-SEALED")
    prepare = _word(source, "RTHP-PREPARE")

    assert "_RTHP.NEXT-REGION !" in init
    assert "_RTHP.NEXT-OBJECT !" in init
    assert build.index("_RTHP-SELECT-NEXT-IDS?") < build.index(
        "_RTHP-BUILD-CONTROLS?"
    )
    assert build.index("RTE-HYBRID-PREFLIGHT") < build.index(
        "_RTHP-CANDIDATE-NEXT?"
    ) < build.index("_RTHP-DRAW-CURRENT?")
    assert "_RTHP.NEXT-REGION" in fixed
    assert "_RTHP.NEXT-OBJECT" in fixed
    assert successors.count("_RTHP-U+?") == 2
    assert "_RTHP-U32+?" not in successors

    build_controls = _word(source, "_RTHP-BUILD-CONTROLS?")
    assert "_RTHP-W-LAST @ 1 _RTHP-U+?" in build_controls
    assert "_RTHP-W-LAST @ 1 _RTHP-U32+?" not in build_controls
    assert "_RTE-HA.GLYPH-LAST" in candidate_last
    assert "_RTE-HA.CONTROL-LAST" in candidate_last
    assert "_RTHP.NEXT-REGION !" in advance
    assert "_RTHP.NEXT-OBJECT !" in advance
    exact_ack = (
        "_RTHP-S-STATE @ RTE-UPDATE-IDLE =\n"
        "    _RTHP-S-STATUS @ RTE-S-OK = AND IF"
    )
    assert sealed.index(exact_ack) < sealed.index("_RTHP-ADVANCE-IDS?")
    assert "_RTHP-PH-READY-REVEAL = IF" in sealed
    assert "_RTHP-ADVANCE-IDS?" not in prepare
    assert source.count("_RTHP-ADVANCE-IDS?") == 2


def test_completed_draws_recapture_only_through_full_hidden_replacement() -> None:
    source = _source()
    copy = _word(source, "_RTHP-COPY-SNAPSHOT?")
    wrap = _word(source, "_RTHP-WRAP-HYBRID")
    current = _word(source, "_RTHP-DRAW-CURRENT?")
    candidate_current = _word(source, "_RTHP-CANDIDATE-CURRENT?")
    build = _word(source, "_RTHP-BUILD-CANDIDATE")
    rebuild = _word(source, "_RTHP-REBUILD-CANDIDATE")
    recapture = _word(source, "_RTHP-RECAPTURE-START")
    step = _word(source, "RTHP-STEP")
    prepare = _word(source, "RTHP-PREPARE")
    reveal = _word(source, "_RTHP-PREPARE-REVEAL")
    valid = _word(source, "_RTHP-VALID-BODY?")

    assert "_RTHP.SURFACE-GEN !" not in copy
    assert "_RTHP.SOURCE-DRAW @" in wrap
    assert "SCR-DRAW-GENERATION@" in build
    assert build.index("RTE-HYBRID-PREFLIGHT") < build.index(
        "_RTHP-DRAW-CURRENT?"
    ) < build.index("_RTHP.SURFACE-GEN !")
    assert current.count("SCR-DRAW-GENERATION@") == 1
    assert current.count("RUHA-SNAPSHOT-FOR@") == 1
    assert "RUHA-SNAPSHOT-GENERATION@" in current
    assert "RUHA-SNAPSHOT-DRAW-GENERATION@" in current
    assert "RUHA-SNAPSHOT-DOCUMENT-COUNT@" in current
    assert "_RTHP.SOURCE-DRAW" in current
    assert "_RTE-HP.SURFACE-GENERATION" in current
    assert "_RTHP.SURFACE-GEN" in candidate_current

    assert "_RTHP-BUILD-CANDIDATE" in rebuild
    assert "SCB-S-WOULD-BLOCK" in rebuild
    assert "_RTHP-TARGET-ABORT" in recapture
    assert "_RTHP-PH-READY-START" in recapture
    assert recapture.index("_RTHP-REBUILD-CANDIDATE") < recapture.index(
        "_RTHP-PREPARE-START"
    )
    assert "_RTHP-RECAPTURE-START" not in step
    assert prepare.count("_RTHP-RECAPTURE-START") == 4
    assert prepare.count("_RTHP-CANDIDATE-CURRENT?") == 3
    assert "_RTHP-ACTIVE-DRAW-CURRENT?" in prepare
    assert "_RTHP.PHASE @ _RTHP-PH-LIVE = IF" in valid
    assert "_RTHP.SURFACE-GEN @" in valid
    assert "_RTHP.ACTIVE-DRAW @ <>" in valid
    ready_reveal = prepare[prepare.index("_RTHP-PH-READY-REVEAL = IF") :]
    ready_reveal = ready_reveal[: ready_reveal.index("_RTHP-PH-REVEAL-SEALED")]
    assert ready_reveal.index("_RTHP-CANDIDATE-CURRENT?") < ready_reveal.index(
        "_RTHP-PREPARE-REVEAL"
    ) < ready_reveal.index("_RTHP-RECAPTURE-START")
    live = prepare[prepare.index("_RTHP-PH-LIVE = IF") :]
    assert live.index("_RTHP-ACTIVE-DRAW-CURRENT?") < live.index(
        "SCB-S-OK"
    ) < live.index("_RTHP-RECAPTURE-START")

    assert "RTE-RETAINED-REPLACE-CONTINUE" in reveal
    assert "RTE-COMMIT-AND-REVEAL" in reveal
    assert "_RTHP-EMIT-" not in reveal
    assert source.count("RTE-RETAINED-REPLACE-START") == 1
    assert "RTE-RETAINED-DELTA" not in source


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


def test_sealed_retry_preserves_only_a_current_exact_candidate() -> None:
    prepare = _word(_source(), "RTHP-PREPARE")
    start_sealed = prepare.split("_RTHP-PH-START-SEALED = IF", 1)[1].split(
        "THEN", 1
    )[0]
    reveal_sealed = prepare.split("_RTHP-PH-REVEAL-SEALED = IF", 1)[1].split(
        "THEN", 1
    )[0]
    assert "SCB-S-OK EXIT" in start_sealed
    assert "_RTHP-PREPARE-START" not in start_sealed
    assert "_RTHP-PREPARE-REVEAL" not in reveal_sealed
    assert "_RTHP-RECAPTURE-START" not in start_sealed
    assert reveal_sealed.index("_RTHP-CANDIDATE-CURRENT?") < reveal_sealed.index(
        "SCB-S-OK"
    ) < reveal_sealed.index("_RTHP-RECAPTURE-START")


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
        "RUHA-SNAPSHOT-FOR@",
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
    assert _constant(source, "_RTHP-TARGET-BANK-HEADER-SIZE") == 48
    assert sizing.count(
        "_RTHP-B-RECORDS @ _RTHP-TARGET-ENTRY-SIZE _RTHP-B-MUL-ADD"
    ) == 2
    assert layout.count("_RTHP.TARGET0-A") == 1
    assert layout.count("_RTHP.TARGET1-A") == 1
    assert "_RTHP-TARGET-INACTIVE" in build
    assert "_RTHP.TARGET-PENDING" in build
    assert "_RTHP-CT-CANDIDATE-SHAPE?" in build
    assert "0 ?DO" not in build
    assert build.count("BEGIN") == 2
    assert "0 ?DO" not in correlation_at
    assert "0 ?DO" not in find_control
    assert "_RTHP.FIRST-OBJECT" in find_control
    assert "_RTHP.CONTROLS-A" in find_control
    assert build.index("_RTHP-CT-CORRELATION-AT?") < build.index(
        "_RTHP-CT-FIND-CONTROL?"
    )
    assert candidate_shape.count("_RTHP-ARENA-SPAN?") == 4
    assert candidate_shape.count("@ 7 AND IF 0 EXIT THEN") == 4
    assert "DUP 7 AND" not in candidate_shape
    for bounded_bank in (
        "_RTHP.SOURCE-DIR-A",
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
    assert "RTE-CONTROL-MENU-BAR" in control
    assert "RTE-CONTROL-MENU-SEPARATOR" in control

    assert "RUCP-CORRELATION-CONTROL-ID@" in correlation_at
    assert "RUCP-CORRELATION-ATTACHMENT@" in correlation
    assert "_RTHP-CT-ATTACHMENT" in correlation
    assert "RUCP-CORRELATION-SOURCE@" in correlation
    assert "RUCP-CORRELATION-SUBKEY@" in correlation
    record_at = _word(source, "_RTHP-CT-RECORD-AT?")
    document_shape = _word(source, "_RTHP-CT-DOCUMENT-SHAPE?")
    assert "_RTHP.SOURCE-RECS-A" in record_at
    assert "_RTHP-CT-LOCAL" in record_at
    assert "RUHA-DOCUMENT-TOKEN@" in document_shape
    assert "RUHA-DOCUMENT-RECORD-OFFSET@" in document_shape
    assert "RUHA-DOCUMENT-TEXT-OFFSET@" in document_shape
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
        "_RTHP-TB.DRAW",
    ):
        assert metadata in build
    assert "_RTHP.SURFACE-GEN @" in build
    for entry in ("_RTHP-TE.ID", "_RTHP-TE.ROW", "_RTHP-TE.COL"):
        assert entry in build
    assert "UMSN-F-PAINTABLE" in build
    assert build.index("_RTHP-CT-DOCUMENT-SHAPE?") < build.index(
        "_RTHP-CT-CORRELATION-AT?"
    )
    assert build.index("_RTHP-CT-RECORD-AT?") < build.index(
        "_RTHP-CT-RECORD?"
    )
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
    assert publish.index("_RTHP-TB.DRAW @") < publish.index(
        "_RTHP.SURFACE-GEN @"
    ) < publish.index("_RTHP-TARGET-BANK-ENTRIES?")
    assert publish.rindex("_RTHP-TB.DRAW @") < publish.index(
        "_RTHP.ACTIVE-DRAW !"
    ) < publish.index("_RTHP.TARGET-ACTIVE !")
    assert source.count("_RTHP.ACTIVE-DRAW !") == 2

    assert "_RTHP.TARGET-ACTIVE" in lookup
    assert "_RTHP-TARGET-BANK-HEADER?" in lookup
    assert "_RTHP-TARGET-BANK-FIND?" in lookup
    assert "_RTHP.PHASE" not in lookup
    assert "_RTHP.OWNER" in lookup
    assert "_RTHP.OWNER-GEN" in lookup
    assert "_RTHP.ACTIVE-DRAW" in lookup
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
        "_RTHP-TB.DRAW",
    ):
        assert metadata in lookup + header + find


def test_repeat_capacity_pressure_preserves_the_active_frame_and_backpressures_cell() -> None:
    rebuild = _word(_source(), "_RTHP-REBUILD-CANDIDATE")

    for temporary_status in (
        "RTE-S-WOULD-BLOCK",
        "RTE-S-UNAVAILABLE",
        "RTE-S-CAPACITY",
    ):
        branch = rebuild[rebuild.index(f"DUP {temporary_status} = IF") :]
        branch = branch[: branch.index("EXIT THEN")]
        assert "SCB-S-WOULD-BLOCK 0" in branch
