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


def _content_epoch_oracle(
    *,
    generation: int,
    prior_epoch: int,
    exact_reuse: bool,
    directory: bytes,
    prior_directory: bytes,
    documents: int,
    prior_documents: int,
    record_bytes: int,
    prior_record_bytes: int,
    text_bytes: int,
    prior_text_bytes: int,
) -> int:
    """Independent collision-free model of the RUHA provenance rule."""

    unchanged = (
        exact_reuse
        and prior_epoch != 0
        and documents == prior_documents
        and record_bytes == prior_record_bytes
        and text_bytes == prior_text_bytes
        and directory == prior_directory
    )
    return prior_epoch if unchanged else generation


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
        "_RUHA-B-LOAD-PRIOR",
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
        "_RUHA-B-FINALIZE-STAGED",
        "_RUHA-A.ACTIVE-BANK !",
    )
    assert _word(source, "_RUHA-B-CAPTURE-CURRENT").count("UMSN-CAPTURE") == 1
    assert "UMSN-CAPTURE" not in _word(source, "_RUHA-B-CAPTURE-RECORD")


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
        "RUHA-SNAPSHOT-CONTENT-EPOCH@",
        "RUHA-SNAPSHOT-DOCUMENT-COUNT@",
        "RUHA-SNAPSHOT-DIRECTORY@",
        "RUHA-SNAPSHOT-FOR@",
        "1 CONSTANT RUHA-S-CAPACITY",
        "2 CONSTANT _RUHA-ABI",
        '0x3241485544495552 CONSTANT _RUHA-MAGIC',
    ):
        assert required in source


def test_content_epoch_is_exact_reuse_provenance_not_a_digest_or_revision_guess() -> None:
    source = _source()
    load = _word(source, "_RUHA-B-LOAD-PRIOR")
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    unchanged = _word(source, "_RUHA-B-CONTENT-UNCHANGED?")
    finalize = _word(source, "_RUHA-B-FINALIZE-CONTENT")
    publish = _word(source, "_RUHA-B-PUBLISH")
    query = _word(source, "RUHA-SNAPSHOT-FOR@")

    assert _offset_for_snapshot_field(source, "_RUHA-S.CONTENT-EPOCH") == 72
    assert "_RUHA-S.RESERVED" not in source
    assert "RUHA-SNAPSHOT-CONTENT-EPOCH@" in load
    assert "DUP 0= IF DROP EXIT THEN _RUHA-B-PRIOR-CONTENT-EPOCH !" in load
    assert "0 _RUHA-B-EXACT-REUSE !" in capture
    for proof in (
        "_RUHA-B-EXACT-REUSE",
        "_RUHA-B-HAS-PRIOR",
        "_RUHA-B-PRIOR-CONTENT-EPOCH",
        "_RUHA-B-DOCUMENTS",
        "_RUHA-B-DIRECTORY-U",
        "_RUHA-B-RECORDS-U",
        "_RUHA-B-TEXT-U",
        "COMPARE 0=",
    ):
        assert proof in unchanged
    assert "_RUHA-B-PRIOR-CONTENT-EPOCH @" in finalize
    assert "_RUHA-B-GENERATION @" in finalize
    assert "_RUHA-S.CONTENT-EPOCH !" in publish
    assert query.index("_RUHA-B-FINALIZE-CONTENT") < query.index(
        "_RUHA-B-PUBLISH"
    )
    assert "RUHA-SNAPSHOT-CONTENT-EPOCH@ 0= IF" in query
    assert "sha" not in (load + capture + unchanged + finalize).lower()


def _offset_for_snapshot_field(source: str, name: str) -> int:
    definition = _word(source, name)
    match = re.search(r"\([^)]*--[^)]*\)\s*(?:(\d+)\s+\+)?\s*;", definition)
    assert match is not None, name
    return int(match.group(1) or 0)


def test_content_epoch_byte_oracle_preserves_only_exact_complete_reuse() -> None:
    prior_directory = bytes(range(80)) + bytes(reversed(range(80)))
    common = dict(
        generation=12,
        prior_epoch=7,
        exact_reuse=True,
        directory=prior_directory,
        prior_directory=prior_directory,
        documents=2,
        prior_documents=2,
        record_bytes=384,
        prior_record_bytes=384,
        text_bytes=37,
        prior_text_bytes=37,
    )
    assert _content_epoch_oracle(**common) == 7

    mutations = (
        {"exact_reuse": False},       # any live UMSN capture
        {"prior_epoch": 0},           # no certified prior publication
        {"documents": 1},             # removal/visibility/empty transition
        {"record_bytes": 192},        # changed semantic slice total
        {"text_bytes": 36},           # changed copied-text total
        {
            "directory": prior_directory[:79]
            + bytes([prior_directory[79] ^ 1])
            + prior_directory[80:]
        },                              # identity/order/geometry/offset byte
    )
    for mutation in mutations:
        assert _content_epoch_oracle(**(common | mutation)) == 12


def test_capture_restores_uctx_and_caches_success_or_failure_by_draw() -> None:
    source = _source()
    query = _word(source, "RUHA-SNAPSHOT-FOR@")
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    assert "ASHELL-ACTIVE-CTX _RUHA-B-ORIGINAL-CTX !" in query
    assert "['] _RUHA-B-CAPTURE CATCH" in query
    assert "['] _RUHA-B-RESTORE CATCH" in query
    assert "_RUHA-R.UCTX @ ASHELL-CTX-SWITCH" in capture
    assert "_RUHA-B-COUNT @ 0= IF" in capture
    assert "-1 _RUHA-B-RECORD @ _RUHA-B-STAGE" in capture
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
    assert "RUHA-S-STALE" in global_invalidate
    assert "_RUHA-A.ACTIVE-BANK" not in global_invalidate
    query = _word(source, "RUHA-SNAPSHOT-FOR@")
    _ordered(
        query,
        "_RUHA-A.LAST-STATUS @",
        "_RUHA-A.ACTIVE-BANK @",
    )
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


def test_clean_documents_reuse_only_exact_valid_prior_slices() -> None:
    source = _source()
    load = _word(source, "_RUHA-B-LOAD-PRIOR")
    find = _word(source, "_RUHA-B-FIND-PRIOR")
    validate = _word(source, "_RUHA-B-PRIOR-ENTRY?")
    record_validate = _word(source, "_RUHA-B-PRIOR-RECORD?")
    reuse = _word(source, "_RUHA-B-REUSE?")

    for required in (
        "_RUHA-A.ACTIVE-BANK @",
        "RUHA-SNAPSHOT-GENERATION@",
        "_RUHA-A.GENERATION @",
        "_RUHA-SNAPSHOT-DIRECTORY-A",
        "_RUHA-SNAPSHOT-RECORD-A",
        "_RUHA-SNAPSHOT-TEXT-A",
    ):
        assert required in load
    assert "_RUHA-R.TOKEN @ =" in find
    assert "_RUHA-R.SLOT-ID @ = AND" in find
    assert "_RUHA-B-FIND-MATCHES @ 1 =" in find
    assert validate.count("_RUHA-UADD?") == 2
    assert "UMSN-RECORD-SIZE MOD" in validate
    assert "UMSN-RECORD-GENERATION@" in record_validate
    assert record_validate.count("_RUHA-B-LOCAL-TEXT?") == 2
    assert reuse.count(" MOVE") == 2
    assert "_RUHA-UMSN.GENERATION !" in reuse
    assert "LABEL-OFFSET" not in reuse
    assert "SHORTCUT-OFFSET" not in reuse


def test_dirty_empty_and_reuse_decisions_commit_only_with_publication() -> None:
    source = _source()
    dispatch = _word(source, "_RUHA-B-CAPTURE-RECORD")
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    aggregate = _word(source, "_RUHA-B-CAPTURE")
    stage = _word(source, "_RUHA-B-STAGE")
    finalize = _word(source, "_RUHA-B-FINALIZE-STAGED")
    publish = _word(source, "_RUHA-B-PUBLISH")

    assert dispatch.count("_RUHA-B-CAPTURE-CURRENT") == 2
    assert "_RUHA-RECORD-DIRTY?" in dispatch
    assert "_RUHA-RECORD-EMPTY?" in dispatch
    assert "_RUHA-B-FIND-PRIOR" in dispatch
    assert "_RUHA-B-REUSE? IF EXIT THEN DROP" in dispatch
    assert "-1 _RUHA-B-RECORD @ _RUHA-B-STAGE" in dispatch
    assert "-1 _RUHA-B-RECORD @ _RUHA-B-STAGE" in capture
    assert "0 _RUHA-B-RECORD @ _RUHA-B-STAGE" in capture
    assert "_RUHA-B-CLEAR-STAGED" in aggregate
    assert "_RUHA-RF-STAGED _RUHA-RF-STAGED-EMPTY OR INVERT AND" in stage
    assert "_RUHA-RF-DIRTY _RUHA-RF-EMPTY OR" in finalize
    assert "_RUHA-B-FINALIZE-STAGED" in publish
    assert "_RUHA-B-FINALIZE-STAGED" not in aggregate
    query = _word(source, "RUHA-SNAPSHOT-FOR@")
    assert "_RUHA-B-FINALIZE-STAGED" not in query
    assert query.count("_RUHA-B-CLEAR-STAGED") == 2


def test_projection_dirties_only_its_document_and_failure_keeps_retry_state() -> None:
    source = _source()
    attach = _word(source, "_RUHA-ATTACH")
    project = _word(source, "_RUHA-PROJECT")
    relayout = _word(source, "_RUHA-RELAYOUT")
    dirty = _word(source, "_RUHA-RECORD-DIRTY!")
    publish = _word(source, "_RUHA-B-PUBLISH")

    assert "_RUHA-A-FREE @ _RUHA-RECORD-DIRTY!" in attach
    assert "_RUHA-P-RECORD @ _RUHA-RECORD-DIRTY!" in project
    assert "_RUHA-RL-RECORD @ _RUHA-RECORD-DIRTY!" in relayout
    assert "_RUHA-RF-DIRTY OR" in dirty
    assert "_RUHA-RF-STAGED _RUHA-RF-STAGED-EMPTY OR INVERT AND" in dirty
    for word in (dirty, _word(source, "_RUHA-B-REUSE?"),
                 _word(source, "_RUHA-B-FINALIZE-STAGED")):
        assert ">R" not in word
        assert "R>" not in word
    _ordered(
        publish,
        "_RUHA-A.LAST-STATUS !",
        "_RUHA-B-FINALIZE-STAGED",
        "_RUHA-A.ACTIVE-BANK !",
    )
