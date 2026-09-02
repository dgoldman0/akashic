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
    descriptor_bytes: int,
    prior_descriptor_bytes: int,
    native_bytes: int,
    prior_native_bytes: int,
    data_graphics_descriptor_bytes: int,
    prior_data_graphics_descriptor_bytes: int,
    data_graphics_native_bytes: int,
    prior_data_graphics_native_bytes: int,
) -> int:
    """Independent collision-free model of the RUHA provenance rule."""

    unchanged = (
        exact_reuse
        and prior_epoch != 0
        and documents == prior_documents
        and record_bytes == prior_record_bytes
        and text_bytes == prior_text_bytes
        and descriptor_bytes == prior_descriptor_bytes
        and native_bytes == prior_native_bytes
        and data_graphics_descriptor_bytes
        == prior_data_graphics_descriptor_bytes
        and data_graphics_native_bytes == prior_data_graphics_native_bytes
        and directory == prior_directory
    )
    return prior_epoch if unchanged else generation


def _menu_epoch_oracle(
    *,
    generation: int,
    prior_epoch: int,
    records: bytes,
    prior_records: bytes,
    text: bytes,
    prior_text: bytes,
    unique_prior: bool = True,
) -> int:
    """Independent exact-menu lineage model; only UMSN generation is ignored."""

    assert len(records) % 192 == 0
    assert len(prior_records) % 192 == 0
    if not records:
        assert text == b""
        return 0
    if not unique_prior or prior_epoch == 0:
        return generation
    if len(records) != len(prior_records) or text != prior_text:
        return generation

    def normalized(payload: bytes) -> bytes:
        result = bytearray(payload)
        for offset in range(0, len(result), 192):
            result[offset + 24 : offset + 32] = b"\0" * 8
        return bytes(result)

    return prior_epoch if normalized(records) == normalized(prior_records) else generation


def test_adapter_stays_at_the_generic_uidl_snapshot_boundary() -> None:
    source = _source()
    for required in (
        "REQUIRE ../applet-host/host.f",
        "REQUIRE ../uidl-menu-snapshot.f",
        "REQUIRE ../uidl-collection-snapshot.f",
        "REQUIRE ../uidl-data-graphics-snapshot.f",
        "AHOST-UIDL-READY!",
        "_UTUI-PROJECTION-ADAPTER!",
        "UMSN-CAPTURE",
        "UCSN-CAPTURE",
        "UDGSN-CAPTURE",
    ):
        assert required in source
    lowered = source.lower()
    for forbidden in (
        "pad-entry", "daybook-entry", "desk-paint", "rte-owner-open",
        "rte-retained-begin", "rte-control-define", "semantic-provider",
        "provider-register", "provider-capture", "sha3",
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
        "_RUHA-SNAPSHOT-DESCRIPTOR-A",
        "_RUHA-SNAPSHOT-NATIVE-A",
        "_RUHA-SNAPSHOT-DGRAPH-DESCRIPTOR-A",
        "_RUHA-SNAPSHOT-DGRAPH-NATIVE-A",
        "_RUHA-B-CAPTURE",
        "_RUHA-B-PUBLISH",
    )
    capture_at = query.index("['] _RUHA-B-CAPTURE")
    capture_restore_at = query.index("['] _RUHA-B-RESTORE", capture_at)
    assert capture_at < capture_restore_at < query.index("_RUHA-B-PUBLISH")
    _ordered(
        publish,
        "_RUHA-S.GENERATION !",
        "_RUHA-S.DRAW-GENERATION !",
        "_RUHA-S.DIRECTORY-A !",
        "_RUHA-S.RECORDS-A !",
        "_RUHA-S.TEXT-A !",
        "_RUHA-S.COLLECTION-DESCRIPTORS-A !",
        "_RUHA-S.COLLECTION-DESCRIPTORS-U !",
        "_RUHA-S.COLLECTION-NATIVE-A !",
        "_RUHA-S.COLLECTION-NATIVE-U !",
        "_RUHA-S.DGRAPH-DESCRIPTORS-A !",
        "_RUHA-S.DGRAPH-DESCRIPTORS-U !",
        "_RUHA-S.DGRAPH-NATIVE-A !",
        "_RUHA-S.DGRAPH-NATIVE-U !",
        "_RUHA-A.GENERATION !",
        "_RUHA-B-FINALIZE-STAGED",
        "_RUHA-A.ACTIVE-BANK !",
    )
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    dispatch = _word(source, "_RUHA-B-CAPTURE-RECORD")
    assert capture.count("UMSN-CAPTURE") == 1
    assert capture.count("UCSN-CAPTURE") == 1
    assert capture.count("UDGSN-CAPTURE") == 1
    assert "UMSN-CAPTURE" not in dispatch
    assert "UCSN-CAPTURE" not in dispatch
    assert "UDGSN-CAPTURE" not in dispatch


def test_data_graphics_capture_appends_opaque_document_slices() -> None:
    source = _source()
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    append = _word(source, "_RUHA-B-APPEND-DOCUMENT")

    _ordered(
        capture,
        "_RUHA-A.DATA-GRAPHICS-BUILDER",
        "_RUHA-B-DGRAPH-DESCRIPTORS-A",
        "_RUHA-B-DGRAPH-NATIVE-A",
        "UDGSN-CAPTURE",
        "UDGSN-DESCRIPTOR-SIZE _RUHA-UMUL?",
        "_RUHA-B-APPEND-DOCUMENT",
    )
    for accounting in (
        "_RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @ U>",
        "_RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @ U>",
        "_RUHA-D.DGRAPH-DESCRIPTOR-OFF !",
        "_RUHA-D.DGRAPH-DESCRIPTOR-U !",
        "_RUHA-D.DGRAPH-NATIVE-OFF !",
        "_RUHA-D.DGRAPH-NATIVE-U !",
        "_RUHA-B-DGRAPH-DESCRIPTORS-U !",
        "_RUHA-B-DGRAPH-NATIVE-U !",
    ):
        assert accounting in append

    # Relation identity and the app-owned UDG root have distinct meanings.
    # RUHA carries the UDGSN descriptor opaquely and never tries to reconcile
    # either key or rewrite the document-local native offset.
    assert "UDGSN-DESCRIPTOR-ROOT-KEY@" not in source
    assert "UDG-SUMMARY-ROOT-KEY@" not in source
    assert "UDGSN-DESCRIPTOR-NATIVE-OFFSET@" not in source


def test_aggregate_selects_every_normal_visible_host_slot_without_focus() -> None:
    source = _source()
    selected = _word(source, "_RUHA-RECORD-VISIBLE?")
    project = _word(source, "_RUHA-PROJECT")
    ready = _word(source, "RUHA-AHOST-UIDL-READY")
    assert "AHS-VISIBLE?" in selected
    assert "AHOST.FOCUS @" not in selected
    assert "_RUHA-RECORD-IDENTITY?" in selected
    assert "UMSN-CAPTURE" not in project
    assert "UCSN-CAPTURE" not in project
    assert "UDGSN-CAPTURE" not in project
    assert "_UTUI-PROJECTION-ATTACH" in ready
    for forbidden in ("APP.NAME", "APP.ID", "PAD", "DAYBOOK"):
        assert forbidden not in selected + ready


def test_constructor_owns_only_caller_bounded_disjoint_banks() -> None:
    source = _source()
    init = _word(source, "RUHA-INIT")
    header = _word(source, "_RUHA-HEADER?")
    ranges = _word(source, "_RUHA-I-RANGES?")
    pairwise = _word(source, "_RUHA-I-PAIRWISE?")
    add_span = _word(source, "_RUHA-I-ADD-SPAN?")
    module_disjoint = _word(source, "_RUHA-I-MODULE-DISJOINT?")
    owned_disjoint = _word(source, "_RUHA-I-OWNED-DISJOINT?")
    authority = _word(source, "_RUHA-I-AUTHORITY?")
    current_authority = _word(source, "_RUHA-CURRENT-AUTHORITY-DISJOINT?")
    assert "XBUF" not in source
    assert "ALLOCATE" not in source
    assert "_RUHA-I-RANGES? 0=" in init
    assert init.index("_RUHA-I-RANGES? 0=") < init.index(
        "_RUHA-I-RECORDS-A @ _RUHA-I-RECORDS-U @ 0 FILL"
    )
    assert "_RUHA-I-ADAPTER @ RUHA-SIZE 0 FILL" in init
    for tail in (
        "WORK",
        "WORK-TEXT",
        "COLLECTION-VALIDATION",
        "COLLECTION-WORK",
        "SNAP-DIRECTORY",
        "SNAP-RECORDS",
        "SNAP-TEXT",
        "SNAP-DESCRIPTORS",
        "SNAP-NATIVE",
        "SNAP-DGRAPH-DESCRIPTORS",
        "SNAP-DGRAPH-NATIVE",
    ):
        assert not re.search(
            rf"_RUHA-I-{tail}-A @\s+_RUHA-I-{tail}-U @ 0 FILL", init
        )
    assert "_RUHA-A.SELF @ 2 PICK = AND" in header
    assert "_RUHA-A.COLLECTION-BUILDER USCOL-BUILDER-SIZE" in header
    assert "_RUHA-A.DATA-GRAPHICS-BUILDER UDG-BUILDER-SIZE" in header
    assert "UMSN-WORK-ENTRY-SIZE MOD" in ranges
    assert "UMSN-RECORD-SIZE MOD" in ranges
    assert "UCSN-DESCRIPTOR-SIZE MOD" in ranges
    assert "UDGSN-DESCRIPTOR-SIZE MOD" in ranges
    assert "_RUHA-I-COLLECTION-VALIDATION-A" in ranges
    assert "_RUHA-I-COLLECTION-WORK-A" in ranges
    assert "_RUHA-I-SNAP-DESCRIPTORS-A" in ranges
    assert "_RUHA-I-SNAP-NATIVE-A" in ranges
    assert "_RUHA-I-SNAP-DGRAPH-DESCRIPTORS-A" in ranges
    assert "_RUHA-I-SNAP-DGRAPH-NATIVE-A" in ranges
    assert "snapshot-directory-a snapshot-directory-u" in init
    assert "collection-validation-a collection-validation-u" in init
    assert "collection-work-a collection-work-u" in init
    assert "snapshot-descriptors-a snapshot-descriptors-u" in init
    assert "snapshot-native-a snapshot-native-u" in init
    assert "snapshot-data-graphics-descriptors-a" in init
    assert "snapshot-data-graphics-descriptors-u" in init
    assert "snapshot-data-graphics-native-a" in init
    assert "snapshot-data-graphics-native-u" in init
    assert "RUHA-DOCUMENT-SIZE MOD" in ranges
    assert "13 CONSTANT _RUHA-I-SPAN-CAPACITY" in source
    assert "_RUHA-I-SPANS" in pairwise
    assert "MSPAN-SET-INIT" in pairwise
    assert "MSPAN-SET-ADD" in add_span
    assert "MSPAN-SET-S-OK" in pairwise + add_span
    assert "MSPAN-SET-COUNT@" in pairwise
    assert "_RUHA-I-SPAN-CAPACITY =" in pairwise
    assert "_RUHA-I-SPAN-CAPACITY MSPAN-SET-BYTES ALLOT" in source
    assert "_RUHA-OWNED-START" in owned_disjoint
    assert "_RUHA-I-OWNED-DISJOINT?" in module_disjoint
    assert "_RUHA-OWNED-LIMIT @" in owned_disjoint
    assert "MSPAN-OVERLAP? 0=" in owned_disjoint
    assert "_RUHA-OWNED-END _RUHA-OWNED-LIMIT !" in source
    assert source.index("CREATE _RUHA-OWNED-START") < source.index(
        "VARIABLE _RUHA-SAFE-ADAPTER"
    )
    assert "_RUHA-I-MODULE-DISJOINT?" in ranges
    assert "_RUHA-I-AUTHORITY? 0=" in ranges
    for authority_check in (
        "USCOL-STORAGE-DISJOINT?",
        "TXTA-STORAGE-DISJOINT?",
        "TGRID-STORAGE-DISJOINT?",
        "UDG-STORAGE-DISJOINT?",
        "DGRAPH-STORAGE-DISJOINT?",
        "DGF-STORAGE-DISJOINT?",
        "UTUI-STORAGE-DISJOINT?",
        "UTUI-COLLECTION-STORAGE-DISJOINT?",
        "USCOL-S-OK <>",
    ):
        assert authority_check in current_authority
    for caller_span in (
        "_RUHA-I-RECORDS-A",
        "_RUHA-I-WORK-A",
        "_RUHA-I-WORK-TEXT-A",
        "_RUHA-I-COLLECTION-VALIDATION-A",
        "_RUHA-I-COLLECTION-WORK-A",
        "_RUHA-I-SNAP-DIRECTORY-A",
        "_RUHA-I-SNAP-RECORDS-A",
        "_RUHA-I-SNAP-TEXT-A",
        "_RUHA-I-SNAP-DESCRIPTORS-A",
        "_RUHA-I-SNAP-NATIVE-A",
        "_RUHA-I-SNAP-DGRAPH-DESCRIPTORS-A",
        "_RUHA-I-SNAP-DGRAPH-NATIVE-A",
        "_RUHA-I-ADAPTER",
    ):
        assert caller_span in authority


def test_runtime_preflights_every_attached_uctx_before_any_bank_write() -> None:
    source = _source()
    attach = _word(source, "_RUHA-ATTACH")
    capture = _word(source, "_RUHA-B-CAPTURE")
    query = _word(source, "RUHA-SNAPSHOT-FOR@")
    preflight = _word(source, "_RUHA-B-PREFLIGHT")
    preflight_record = _word(source, "_RUHA-B-PREFLIGHT-RECORD?")
    storage = _word(source, "_RUHA-STORAGE-DISJOINT-CURRENT?")

    assert "AHS.UCTX @ ASHELL-ACTIVE-CTX <>" in attach
    assert "_RUHA-STORAGE-DISJOINT-CURRENT? 0=" in attach
    assert "_RUHA-B-PREFLIGHT" not in capture
    _ordered(
        query,
        "_RUHA-B-PREFLIGHT-GUARDED",
        "_RUHA-A.LAST-DRAW !",
        "_RUHA-B-CAPTURE",
    )
    assert "_RUHA-A.CAPACITY @ 0 ?DO" in preflight
    assert "_RUHA-B-PREFLIGHT-RECORD?" in preflight
    assert "_RUHA-RECORD-ATTACHED" in preflight_record
    assert "_RUHA-RECORD-QUIESCED" in preflight_record
    assert "AHS.ID @" in preflight_record
    assert "_RUHA-R.SLOT-ID @" in preflight_record
    assert "AHS.UCTX @" in preflight_record
    assert "ASHELL-CTX-SWITCH" in preflight_record
    assert "ASHELL-ACTIVE-CTX" in preflight_record
    assert "_RUHA-STORAGE-DISJOINT-CURRENT?" in preflight_record
    for adapter_span in (
        "_RUHA-A.RECORDS-A",
        "_RUHA-A.WORK-A",
        "_RUHA-A.WORK-TEXT-A",
        "_RUHA-A.COLLECTION-VALIDATION-A",
        "_RUHA-A.COLLECTION-WORK-A",
        "_RUHA-A.SNAP-DIRECTORY-A",
        "_RUHA-A.SNAP-RECORDS-A",
        "_RUHA-A.SNAP-TEXT-A",
        "_RUHA-A.SNAP-DESCRIPTORS-A",
        "_RUHA-A.SNAP-NATIVE-A",
        "_RUHA-A.SNAP-DGRAPH-DESCRIPTORS-A",
        "_RUHA-A.SNAP-DGRAPH-NATIVE-A",
        "RUHA-SIZE",
    ):
        assert adapter_span in storage
    for lifecycle in (
        "_RUHA-RELAYOUT",
        "_RUHA-PROJECT",
        "_RUHA-QUIESCE",
        "_RUHA-DETACH",
    ):
        assert "_RUHA-RECORD-STORAGE-CURRENT?" in _word(source, lifecycle)


def test_storage_shape_compares_halves_without_wrapping_multiplication() -> None:
    shape = _word(_source(), "_RUHA-STORAGE-SHAPE?")
    for total, half in (
        ("_RUHA-A.SNAP-DIRECTORY-U @ 2 /", "_RUHA-A.SNAP-DIRECTORY-BANK-U @"),
        ("_RUHA-A.SNAP-RECORDS-U @ 2 /", "_RUHA-A.SNAP-RECORD-BANK-U @"),
        ("_RUHA-A.SNAP-TEXT-U @ 2 /", "_RUHA-A.SNAP-TEXT-BANK-U @"),
        ("_RUHA-A.SNAP-DESCRIPTORS-U @ 2 /", "_RUHA-A.SNAP-DESCRIPTOR-BANK-U @"),
        ("_RUHA-A.SNAP-NATIVE-U @ 2 /", "_RUHA-A.SNAP-NATIVE-BANK-U @"),
        (
            "_RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U @ 2 /",
            "_RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @",
        ),
        (
            "_RUHA-A.SNAP-DGRAPH-NATIVE-U @ 2 /",
            "_RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @",
        ),
    ):
        assert total in shape
        assert half in shape
    assert "BANK-U @ 2 *" not in shape


def test_abi5_layout_embeds_both_fixed_model_builders_and_menu_lineage() -> None:
    source = _source()
    assert "152 CONSTANT RUHA-DOCUMENT-SIZE" in source
    assert "144 CONSTANT RUHA-SNAPSHOT-SIZE" in source
    assert "784 CONSTANT RUHA-SIZE" in source
    assert "5 CONSTANT _RUHA-ABI" in source
    assert '0x3541485544495552 CONSTANT _RUHA-MAGIC' in source
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.COLLECTION-VALIDATION-A"
    ) == 216
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.COLLECTION-VALIDATION-U"
    ) == 224
    assert _offset_for_snapshot_field(source, "_RUHA-A.COLLECTION-WORK-A") == 232
    assert _offset_for_snapshot_field(source, "_RUHA-A.COLLECTION-WORK-U") == 240
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAP-DESCRIPTORS-A") == 248
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAP-DESCRIPTORS-U") == 256
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DESCRIPTOR-BANK-U"
    ) == 264
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAP-NATIVE-A") == 272
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAP-NATIVE-U") == 280
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAP-NATIVE-BANK-U") == 288
    assert _offset_for_snapshot_field(source, "_RUHA-A.COLLECTION-BUILDER") == 296
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-DESCRIPTORS-A"
    ) == 368
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U"
    ) == 376
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U"
    ) == 384
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-NATIVE-A"
    ) == 392
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-NATIVE-U"
    ) == 400
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U"
    ) == 408
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.DATA-GRAPHICS-BUILDER"
    ) == 416
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAPSHOT-A") == 496
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAPSHOT-B") == 640
    assert _offset_for_snapshot_field(
        source, "_RUHA-D.COLLECTION-DESCRIPTOR-OFF"
    ) == 80
    assert _offset_for_snapshot_field(
        source, "_RUHA-D.COLLECTION-DESCRIPTOR-U"
    ) == 88
    assert _offset_for_snapshot_field(
        source, "_RUHA-D.COLLECTION-NATIVE-OFF"
    ) == 96
    assert _offset_for_snapshot_field(
        source, "_RUHA-D.COLLECTION-NATIVE-U"
    ) == 104
    assert _offset_for_snapshot_field(
        source, "_RUHA-D.DGRAPH-DESCRIPTOR-OFF"
    ) == 112
    assert _offset_for_snapshot_field(
        source, "_RUHA-D.DGRAPH-DESCRIPTOR-U"
    ) == 120
    assert _offset_for_snapshot_field(source, "_RUHA-D.DGRAPH-NATIVE-OFF") == 128
    assert _offset_for_snapshot_field(source, "_RUHA-D.DGRAPH-NATIVE-U") == 136
    assert _offset_for_snapshot_field(source, "_RUHA-D.MENU-EPOCH") == 144
    assert "USCOL-BUILDER-SIZE" in source
    assert "UDG-BUILDER-SIZE" in source
    assert "_RUHA-A.RESERVED" not in source


def test_public_aggregate_abi_keeps_document_slices_and_draw_identity() -> None:
    source = _source()
    for required in (
        "152 CONSTANT RUHA-DOCUMENT-SIZE",
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
        "RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@",
        "RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@",
        "RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@",
        "RUHA-DOCUMENT-COLLECTION-NATIVE-BYTES@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-OFFSET@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-OFFSET@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-BYTES@",
        "RUHA-DOCUMENT-MENU-EPOCH@",
        "RUHA-DOCUMENT-CAPACITY@",
        "RUHA-SNAPSHOT-DRAW-GENERATION@",
        "RUHA-SNAPSHOT-CONTENT-EPOCH@",
        "RUHA-SNAPSHOT-DOCUMENT-COUNT@",
        "RUHA-SNAPSHOT-DIRECTORY@",
        "RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@",
        "RUHA-SNAPSHOT-COLLECTION-NATIVE@",
        "RUHA-SNAPSHOT-COLLECTION-COUNT@",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@",
        "RUHA-SNAPSHOT-FOR@",
        "1 CONSTANT RUHA-S-CAPACITY",
        "5 CONSTANT _RUHA-ABI",
        '0x3541485544495552 CONSTANT _RUHA-MAGIC',
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
    assert _offset_for_snapshot_field(
        source, "_RUHA-S.COLLECTION-DESCRIPTORS-A"
    ) == 80
    assert _offset_for_snapshot_field(
        source, "_RUHA-S.COLLECTION-DESCRIPTORS-U"
    ) == 88
    assert _offset_for_snapshot_field(
        source, "_RUHA-S.COLLECTION-NATIVE-A"
    ) == 96
    assert _offset_for_snapshot_field(
        source, "_RUHA-S.COLLECTION-NATIVE-U"
    ) == 104
    assert _offset_for_snapshot_field(
        source, "_RUHA-S.DGRAPH-DESCRIPTORS-A"
    ) == 112
    assert _offset_for_snapshot_field(
        source, "_RUHA-S.DGRAPH-DESCRIPTORS-U"
    ) == 120
    assert _offset_for_snapshot_field(source, "_RUHA-S.DGRAPH-NATIVE-A") == 128
    assert _offset_for_snapshot_field(source, "_RUHA-S.DGRAPH-NATIVE-U") == 136
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
        "_RUHA-B-DESCRIPTORS-U",
        "_RUHA-B-PRIOR-DESCRIPTORS-U",
        "_RUHA-B-NATIVE-U",
        "_RUHA-B-PRIOR-NATIVE-U",
        "_RUHA-B-DGRAPH-DESCRIPTORS-U",
        "_RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-U",
        "_RUHA-B-DGRAPH-NATIVE-U",
        "_RUHA-B-PRIOR-DGRAPH-NATIVE-U",
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


def test_document_menu_epoch_is_exact_normalized_menu_family_lineage() -> None:
    source = _source()
    append = _word(source, "_RUHA-B-APPEND-DOCUMENT")
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    validate = _word(source, "_RUHA-B-PRIOR-MENU?")
    compare_record = _word(source, "_RUHA-B-MENU-RECORD=?")
    compare_menu = _word(source, "_RUHA-B-MENU-UNCHANGED?")
    select = _word(source, "_RUHA-B-CAPTURE-MENU-EPOCH")
    reuse = _word(source, "_RUHA-B-REUSE?")

    assert "_RUHA-B-APPEND-RECORD-U @ 0=" in append
    assert "_RUHA-B-APPEND-MENU-EPOCH @ 0= <>" in append
    assert "_RUHA-D.MENU-EPOCH !" in append
    assert "RUHA-DOCUMENT-MENU-EPOCH@" in validate
    assert "_RUHA-B-REUSE-MENU-EPOCH !" in validate
    assert "_RUHA-B-REUSE-RECORD-U @ 0=" in validate
    assert "_RUHA-B-REUSE-MENU-EPOCH @ 0= <>" in validate
    assert "_RUHA-B-PRIOR-GENERATION @ U>" in validate
    assert "24 COMPARE" in compare_record
    assert compare_record.count("32 + UMSN-RECORD-SIZE 32 -") == 2
    assert "_RUHA-B-CAPTURE-RECORD-U @" in compare_menu
    assert "_RUHA-B-CAPTURE-TEXT-U @ COMPARE" in compare_menu
    assert "_RUHA-B-GENERATION @" in select
    assert "_RUHA-B-MENU-UNCHANGED?" in select
    assert "_RUHA-B-REUSE-MENU-EPOCH @ EXIT" in select
    _ordered(capture, "UMSN-CAPTURE", "_RUHA-B-CAPTURE-MENU-EPOCH", "_RUHA-B-APPEND-DOCUMENT")
    assert "_RUHA-B-REUSE-MENU-EPOCH @" in reuse
    assert reuse.index("_RUHA-B-REUSE-MENU-EPOCH @") < reuse.index(
        "_RUHA-B-APPEND-DOCUMENT"
    )

    prior = bytearray(2 * 192)
    prior[40] = 7
    prior[192 + 80] = 9
    current = bytearray(prior)
    current[24:32] = (101).to_bytes(8, "little")
    current[192 + 24 : 192 + 32] = (101).to_bytes(8, "little")
    prior[24:32] = (44).to_bytes(8, "little")
    prior[192 + 24 : 192 + 32] = (44).to_bytes(8, "little")
    common = dict(
        generation=101,
        prior_epoch=12,
        records=bytes(current),
        prior_records=bytes(prior),
        text=b"FileEdit",
        prior_text=b"FileEdit",
    )
    assert _menu_epoch_oracle(**common) == 12
    state_changed = bytearray(current)
    state_changed[40] ^= 1
    assert _menu_epoch_oracle(**(common | {"records": bytes(state_changed)})) == 101
    assert _menu_epoch_oracle(**(common | {"text": b"FileExit"})) == 101
    assert _menu_epoch_oracle(**(common | {"prior_epoch": 0})) == 101
    assert _menu_epoch_oracle(**(common | {"unique_prior": False})) == 101
    assert _menu_epoch_oracle(
        generation=101,
        prior_epoch=0,
        records=b"",
        prior_records=b"",
        text=b"",
        prior_text=b"",
    ) == 0

    old_epochs = (11, 12, 13)
    changed_middle = bytearray(current)
    changed_middle[40] ^= 1
    new_epochs = tuple(
        _menu_epoch_oracle(
            generation=101,
            prior_epoch=epoch,
            records=bytes(changed_middle) if index == 1 else bytes(current),
            prior_records=bytes(prior),
            text=b"FileEdit",
            prior_text=b"FileEdit",
        )
        for index, epoch in enumerate(old_epochs)
    )
    assert new_epochs == (11, 101, 13)


def _offset_for_snapshot_field(source: str, name: str) -> int:
    definition = _word(source, name)
    match = re.search(r"\([^)]*--[^)]*\)\s*(?:(\d+)\s+\+)?\s*;", definition)
    assert match is not None, name
    return int(match.group(1) or 0)


def test_content_epoch_byte_oracle_preserves_only_exact_complete_reuse() -> None:
    prior_directory = bytes(range(152)) + bytes(reversed(range(152)))
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
        descriptor_bytes=304,
        prior_descriptor_bytes=304,
        native_bytes=928,
        prior_native_bytes=928,
        data_graphics_descriptor_bytes=320,
        prior_data_graphics_descriptor_bytes=320,
        data_graphics_native_bytes=1960,
        prior_data_graphics_native_bytes=1960,
    )
    assert _content_epoch_oracle(**common) == 7

    mutations = (
        {"exact_reuse": False},       # any live family capture
        {"prior_epoch": 0},           # no certified prior publication
        {"documents": 1},             # removal/visibility/empty transition
        {"record_bytes": 192},        # changed semantic slice total
        {"text_bytes": 36},           # changed copied-text total
        {"descriptor_bytes": 152},    # changed collection descriptor total
        {"native_bytes": 920},        # changed frozen native collection total
        {"data_graphics_descriptor_bytes": 160},
        {"data_graphics_native_bytes": 1952},
        {
            "directory": prior_directory[:80]
            + bytes([prior_directory[80] ^ 1])
            + prior_directory[81:]
        },                              # collection-offset directory byte
        {
            "directory": prior_directory[:112]
            + bytes([prior_directory[112] ^ 1])
            + prior_directory[113:]
        },                              # DATA_GRAPHICS-offset directory byte
    )
    for mutation in mutations:
        assert _content_epoch_oracle(**(common | mutation)) == 12


def test_capture_restores_uctx_and_caches_success_or_failure_by_draw() -> None:
    source = _source()
    query = _word(source, "RUHA-SNAPSHOT-FOR@")
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    tail_span = _word(source, "_RUHA-B-TAIL-SPAN")
    assert "( base used capacity -- tail-a tail-u )" in tail_span
    assert "OVER - DUP 0= IF DROP 2DROP 0 0 EXIT THEN" in tail_span
    assert ">R + R>" in tail_span
    # Menu, collection, and DATA_GRAPHICS each pass two output tails.  Every
    # exactly exhausted bank must become canonical `0 0` rather than a
    # one-past-end address with zero bytes.
    assert capture.count("_RUHA-B-TAIL-SPAN") == 6
    assert "ASHELL-ACTIVE-CTX _RUHA-B-ORIGINAL-CTX !" in query
    assert "['] _RUHA-B-CAPTURE CATCH" in query
    assert "['] _RUHA-B-RESTORE CATCH" in query
    assert "_RUHA-R.UCTX @ ASHELL-CTX-SWITCH" in capture
    assert capture.count("ASHELL-CTX-SWITCH") == 1
    switch = capture.index("ASHELL-CTX-SWITCH")
    assert switch < capture.index("UMSN-CAPTURE")
    assert switch < capture.index("UCSN-CAPTURE")
    assert switch < capture.index("UDGSN-CAPTURE")
    _ordered(capture, "UMSN-CAPTURE", "UCSN-CAPTURE", "UDGSN-CAPTURE")
    for storage in (
        "_RUHA-A.COLLECTION-BUILDER",
        "_RUHA-A.COLLECTION-VALIDATION-A",
        "_RUHA-A.COLLECTION-VALIDATION-U",
        "_RUHA-A.COLLECTION-WORK-A",
        "_RUHA-A.COLLECTION-WORK-U",
        "_RUHA-B-DESCRIPTORS-A",
        "_RUHA-A.SNAP-DESCRIPTOR-BANK-U",
        "_RUHA-B-NATIVE-A",
        "_RUHA-A.SNAP-NATIVE-BANK-U",
        "_RUHA-A.DATA-GRAPHICS-BUILDER",
        "_RUHA-B-DGRAPH-DESCRIPTORS-A",
        "_RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U",
        "_RUHA-B-DGRAPH-NATIVE-A",
        "_RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U",
    ):
        assert storage in capture
    combined_empty = re.search(
        r"_RUHA-B-COUNT @ 0=\s+"
        r"_RUHA-B-COLLECTION-COUNT @ 0= AND\s+"
        r"_RUHA-B-DGRAPH-COUNT @ 0= AND IF",
        capture,
    )
    assert combined_empty is not None
    assert capture.index("UCSN-CAPTURE") < combined_empty.start()
    assert capture.index("UDGSN-CAPTURE") < combined_empty.start()
    assert "-1 _RUHA-B-RECORD @ _RUHA-B-STAGE" in capture
    assert "UMSN-S-CAPACITY" in _word(source, "_RUHA-B-MAP-STATUS")
    collection_status = _word(source, "_RUHA-B-MAP-COLLECTION-STATUS")
    for status in (
        "UCSN-S-CAPACITY",
        "UCSN-S-UNAVAILABLE",
        "UCSN-S-INVALID",
    ):
        assert status in collection_status
    data_graphics_status = _word(source, "_RUHA-B-MAP-DATA-GRAPHICS-STATUS")
    for status in (
        "UDGSN-S-CAPACITY",
        "UDGSN-S-UNAVAILABLE",
        "UDGSN-S-INVALID",
    ):
        assert status in data_graphics_status
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
    menu_validate = _word(source, "_RUHA-B-PRIOR-MENU?")
    record_validate = _word(source, "_RUHA-B-PRIOR-RECORD?")
    reuse = _word(source, "_RUHA-B-REUSE?")

    for required in (
        "_RUHA-A.ACTIVE-BANK @",
        "RUHA-SNAPSHOT-GENERATION@",
        "_RUHA-A.GENERATION @",
        "_RUHA-SNAPSHOT-DIRECTORY-A",
        "_RUHA-SNAPSHOT-RECORD-A",
        "_RUHA-SNAPSHOT-TEXT-A",
        "_RUHA-SNAPSHOT-DESCRIPTOR-A",
        "_RUHA-SNAPSHOT-NATIVE-A",
        "_RUHA-SNAPSHOT-DGRAPH-DESCRIPTOR-A",
        "_RUHA-SNAPSHOT-DGRAPH-NATIVE-A",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@",
    ):
        assert required in load
    assert "_RUHA-R.TOKEN @ =" in find
    assert "_RUHA-R.SLOT-ID @ = AND" in find
    assert "_RUHA-B-FIND-MATCHES @ 1 =" in find
    assert (validate + menu_validate).count("_RUHA-UADD?") >= 6
    assert "RUHA-DOCUMENT-MENU-EPOCH@" in menu_validate
    assert "_RUHA-B-REUSE-MENU-EPOCH !" in menu_validate
    assert "_RUHA-B-REUSE-RECORD-U @ 0=" in menu_validate
    assert "_RUHA-B-REUSE-MENU-EPOCH @ 0= <>" in menu_validate
    assert "UMSN-RECORD-SIZE MOD" in menu_validate
    assert "RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@" in validate
    assert "RUHA-DOCUMENT-COLLECTION-NATIVE-BYTES@" in validate
    assert "UCSN-FROZEN-VALIDATE" in validate
    assert (
        "_RUHA-B-REUSE-DESCRIPTOR-U @ 0=\n"
        "        _RUHA-B-REUSE-NATIVE-U @ 0= <> IF 0 EXIT THEN"
    ) in validate
    assert "RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@" in validate
    assert "RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-BYTES@" in validate
    assert "UDGSN-FROZEN-VALIDATE" in validate
    assert (
        "_RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @ 0=\n"
        "        _RUHA-B-REUSE-DGRAPH-NATIVE-U @ 0= <> IF 0 EXIT THEN"
    ) in validate
    assert "UMSN-RECORD-GENERATION@" in record_validate
    assert record_validate.count("_RUHA-B-LOCAL-TEXT?") == 2
    # The owning snapshot modules authenticate every enriched slice before
    # RUHA relocates all six pointer-free document-local banks verbatim.
    assert reuse.count(" MOVE") == 6
    for target in (
        "_RUHA-B-REUSE-DESCRIPTOR-TARGET",
        "_RUHA-B-REUSE-NATIVE-TARGET",
        "_RUHA-B-REUSE-DGRAPH-DESCRIPTOR-TARGET",
        "_RUHA-B-REUSE-DGRAPH-NATIVE-TARGET",
    ):
        assert target in reuse
    for length in (
        "_RUHA-B-REUSE-DESCRIPTOR-U @",
        "_RUHA-B-REUSE-NATIVE-U @",
        "_RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @",
        "_RUHA-B-REUSE-DGRAPH-NATIVE-U @",
    ):
        assert length in reuse
    assert "_RUHA-UMSN.GENERATION !" in reuse
    assert "_RUHA-B-REUSE-MENU-EPOCH @" in reuse
    assert "LABEL-OFFSET" not in reuse
    assert "SHORTCUT-OFFSET" not in reuse
    assert "UCSN-DESCRIPTOR" not in reuse
    assert "UDGSN-DESCRIPTOR" not in reuse


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
    assert "_RUHA-B-COLLECTION-COUNT @ 0= AND" in capture
    assert "_RUHA-B-DGRAPH-COUNT @ 0= AND" in capture
    assert "0 _RUHA-B-RECORD @ _RUHA-B-STAGE" in capture
    assert "_RUHA-B-GENERATION @" in capture
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
