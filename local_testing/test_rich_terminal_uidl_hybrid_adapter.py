"""Seconds-only structural locks for the draw-keyed UIDL aggregate."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "akashic/tui/rich-terminal/uidl-hybrid-adapter.f"


def _source() -> str:
    return ADAPTER.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions)


def test_adapter_stays_at_the_generic_uidl_snapshot_boundary() -> None:
    source = _source()
    for required in (
        "REQUIRE ../applet-host/host.f",
        "REQUIRE ../uidl-menu-snapshot.f",
        "AHOST-UIDL-READY!",
        "_UTUI-PROJECTION-ADAPTER!",
        "UMSN-CAPTURE",
    ):
        assert required in source
    lowered = source.lower()
    for forbidden in (
        "pad-entry", "daybook-entry", "desk-paint", "rte-owner-open",
        "rte-retained-begin", "rte-control-define", "sha3",
    ):
        assert forbidden not in lowered


def test_capture_uses_inactive_banks_and_publishes_selector_last() -> None:
    source = _source()
    query = _word(source, "RUHA-SNAPSHOT-FOR@")
    publish = _word(source, "_RUHA-B-PUBLISH")
    _ordered(
        query,
        "_RUHA-A.ACTIVE-BANK @ 0= IF 1 ELSE 0 THEN",
        "_RUHA-SNAPSHOT-DIRECTORY-A",
        "_RUHA-SNAPSHOT-RECORD-A",
        "_RUHA-SNAPSHOT-TEXT-A",
        "_RUHA-B-CAPTURE",
        "_RUHA-B-RESTORE",
        "_RUHA-B-PUBLISH",
    )
    _ordered(
        publish,
        "_RUHA-S.GENERATION !",
        "_RUHA-S.DRAW-GENERATION !",
        "_RUHA-S.DIRECTORY-A !",
        "_RUHA-S.RECORDS-A !",
        "_RUHA-S.TEXT-A !",
        "_RUHA-A.GENERATION !",
        "_RUHA-A.ACTIVE-BANK !",
    )
    assert _word(source, "_RUHA-B-CAPTURE-RECORD").count("UMSN-CAPTURE") == 1


def test_aggregate_selects_every_normal_visible_host_slot_without_focus() -> None:
    source = _source()
    selected = _word(source, "_RUHA-RECORD-VISIBLE?")
    project = _word(source, "_RUHA-PROJECT")
    ready = _word(source, "RUHA-AHOST-UIDL-READY")
    assert "AHS-VISIBLE?" in selected
    assert "AHOST.FOCUS @" not in selected
    assert "_RUHA-RECORD-IDENTITY?" in selected
    assert "UMSN-CAPTURE" not in project
    assert "_UTUI-PROJECTION-ATTACH" in ready
    for forbidden in ("APP.NAME", "APP.ID", "PAD", "DAYBOOK"):
        assert forbidden not in selected + ready


def test_constructor_owns_only_caller_bounded_disjoint_banks() -> None:
    source = _source()
    init = _word(source, "RUHA-INIT")
    header = _word(source, "_RUHA-HEADER?")
    ranges = _word(source, "_RUHA-I-RANGES?")
    pairwise = _word(source, "_RUHA-I-PAIRWISE?")
    assert "XBUF" not in source
    assert "ALLOCATE" not in source
    assert "_RUHA-I-RANGES? 0=" in init
    assert "_RUHA-A.SELF @ 2 PICK = AND" in header
    assert "UMSN-WORK-ENTRY-SIZE MOD" in ranges
    assert "UMSN-RECORD-SIZE MOD" in ranges
    assert "snapshot-directory-a snapshot-directory-u" in init
    assert "RUHA-DOCUMENT-SIZE MOD" in ranges
    assert pairwise.count("_RUHA-DISJOINT?") == 15


def test_public_aggregate_abi_keeps_document_slices_and_draw_identity() -> None:
    source = _source()
    for required in (
        "80 CONSTANT RUHA-DOCUMENT-SIZE",
        "RUHA-DOCUMENT-BYTES",
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
        "RUHA-DOCUMENT-CAPACITY@",
        "RUHA-SNAPSHOT-DRAW-GENERATION@",
        "RUHA-SNAPSHOT-DOCUMENT-COUNT@",
        "RUHA-SNAPSHOT-DIRECTORY@",
        "RUHA-SNAPSHOT-FOR@",
        "1 CONSTANT RUHA-S-CAPACITY",
        "2 CONSTANT _RUHA-ABI",
        '0x3241485544495552 CONSTANT _RUHA-MAGIC',
    ):
        assert required in source


def test_capture_restores_uctx_and_caches_success_or_failure_by_draw() -> None:
    source = _source()
    query = _word(source, "RUHA-SNAPSHOT-FOR@")
    capture = _word(source, "_RUHA-B-CAPTURE-RECORD")
    assert "ASHELL-ACTIVE-CTX _RUHA-B-ORIGINAL-CTX !" in query
    assert "['] _RUHA-B-CAPTURE CATCH" in query
    assert "['] _RUHA-B-RESTORE CATCH" in query
    assert "_RUHA-R.UCTX @ ASHELL-CTX-SWITCH" in capture
    assert "_RUHA-B-COUNT @ 0= IF RUHA-S-OK EXIT THEN" in capture
    assert "UMSN-S-CAPACITY" in _word(source, "_RUHA-B-MAP-STATUS")
    _ordered(
        query,
        "_RUHA-A.LAST-DRAW @ = IF",
        "_RUHA-A.LAST-STATUS @",
        "_RUHA-A.LAST-DRAW !",
        "_RUHA-B-CAPTURE",
    )


def test_lifecycle_invalidates_borrowed_snapshot_before_state_changes() -> None:
    source = _source()
    relayout = _word(source, "_RUHA-RELAYOUT")
    quiesce = _word(source, "_RUHA-QUIESCE")
    detach = _word(source, "_RUHA-DETACH")
    _ordered(
        relayout,
        "_RUHA-INVALIDATE",
        "_RUHA-R.VISIBLE !",
    )
    _ordered(
        quiesce,
        "_RUHA-INVALIDATE",
        "_RUHA-RECORD-QUIESCED _RUHA-Q-RECORD",
    )
    _ordered(
        detach,
        "_RUHA-INVALIDATE",
        "RUHA-RECORD-SIZE 0 FILL",
    )
    all_free = _word(source, "_RUHA-ALL-FREE?")
    assert "?DO" in all_free
    assert "R@" not in all_free
    global_invalidate = _word(source, "_RUHA-INVALIDATE")
    assert "_RUHA-A.ACTIVE-BANK !" in global_invalidate
    assert "RUHA-S-STALE" in global_invalidate
    for lifecycle in (relayout, quiesce, detach):
        assert "_RUHA-INVALIDATE" in lifecycle

    host_fini = _word(source, "RUHA-HOST-FINI")
    _ordered(
        host_fini,
        "AHOST.UIDL-READY-XT @",
        "AHOST.UIDL-READY-CONTEXT @",
        "0 0 3 PICK AHOST-UIDL-READY!",
        "_RUHA-A.HOST !",
    )
