"""Seconds-only structural locks for the draw-keyed UIDL aggregate, and
one executed seam: the reuse shortcut's fallback to a fresh capture."""

from pathlib import Path
import re

import pytest

from test_rich_terminal_control_map import MASK64, MegaForthRuntime


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "akashic/tui/rich-terminal/uidl-hybrid-adapter.f"
MENU_SNAPSHOT = ROOT / "akashic/tui/uidl-menu-snapshot.f"


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


def _menu_lineage_oracle(
    *,
    generation: int,
    prior_exact_epoch: int,
    prior_topology_epoch: int,
    records: bytes,
    prior_records: bytes,
    text: bytes,
    prior_text: bytes,
    unique_prior: bool = True,
) -> tuple[int, int]:
    """Independent exact and retained-control topology lineage model."""

    assert len(records) % 192 == 0
    assert len(prior_records) % 192 == 0
    if not records:
        assert text == b""
        return 0, 0
    if (
        not unique_prior
        or prior_exact_epoch == 0
        or prior_topology_epoch == 0
        or prior_topology_epoch > prior_exact_epoch
        or prior_exact_epoch > generation
    ):
        return generation, generation
    if len(records) != len(prior_records) or text != prior_text:
        return generation, generation

    def exact_normalized(payload: bytes) -> bytes:
        result = bytearray(payload)
        for offset in range(0, len(result), 192):
            result[offset + 24 : offset + 32] = b"\0" * 8
        return bytes(result)

    def control_topology(payload: bytes) -> tuple[bytes, ...]:
        topology: list[bytes] = []
        for offset in range(0, len(payload), 192):
            record = payload[offset : offset + 192]
            # Keep the checked record header, source/index/subkey/parent/kind,
            # ordinal, and text spans.  Generation and mutable state are not
            # control topology.  Child resolved geometry and all resolved
            # style are also irrelevant to retained menu controls; only a
            # menubar's row/col/height/width/z affect that projection.
            stable = record[:24] + record[32:72] + record[80:120]
            kind = int.from_bytes(record[64:72], "little")
            if kind == 1:  # UMSN-K-MENUBAR
                stable += record[120:152] + record[184:192]
            topology.append(stable)
        return tuple(topology)

    exact_epoch = (
        prior_exact_epoch
        if exact_normalized(records) == exact_normalized(prior_records)
        else generation
    )
    topology_epoch = (
        prior_topology_epoch
        if control_topology(records) == control_topology(prior_records)
        else generation
    )
    return exact_epoch, topology_epoch


def test_adapter_stays_at_the_generic_uidl_snapshot_boundary() -> None:
    source = _source()
    for required in (
        "REQUIRE ../applet-host/host.f",
        "REQUIRE ../screen.f",
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
    assert "17 CONSTANT _RUHA-I-SPAN-CAPACITY" in source
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
    storage = (_word(source, "_RUHA-STORAGE-DISJOINT-CURRENT?")
               + _word(source, "_RUHA-STORAGE-SPANS?"))
    screen_storage = _word(source, "_RUHA-SCREEN-STORAGE-DISJOINT?")
    authority = _word(source, "_RUHA-SNAPSHOT-FOR-IN-DRAW")

    assert "AHS.UCTX @ ASHELL-ACTIVE-CTX <>" in attach
    assert "_RUHA-STORAGE-DISJOINT-CURRENT? 0=" in attach
    assert "_RUHA-B-PREFLIGHT" not in capture
    _ordered(
        query,
        "_RUHA-B-PREFLIGHT-GUARDED",
        "_RUHA-A.LAST-DRAW !",
        "_RUHA-B-CAPTURE",
    )
    assert "' RUHA-SNAPSHOT-FOR@ CONSTANT _ruha-snapshot-for-body-xt" in source
    assert "OVER R@ <> IF" in authority
    assert "0 RUHA-S-STALE EXIT" in authority
    assert "_ruha-snapshot-for-body-xt EXECUTE" in authority
    assert re.search(
        r"(?ms)^: RUHA-SNAPSHOT-FOR@\s+"
        r"\( draw-generation adapter -- snapshot status \)\s*\n"
        r"\s+\['] _RUHA-SNAPSHOT-FOR-IN-DRAW "
        r"_SCR-WITH-DRAW-AUTHORITY ;$",
        source,
    )
    assert "_RUHA-A.CAPACITY @ 0 ?DO" in preflight
    assert "_RUHA-B-PREFLIGHT-RECORD?" in preflight
    _ordered(
        preflight,
        "_RUHA-SCREEN-STORAGE-DISJOINT?",
        "_RUHA-STORAGE-DISJOINT-CURRENT?",
        "_RUHA-A.CAPACITY @ 0 ?DO",
    )
    assert "SCR-STORAGE-DISJOINT?" not in preflight_record
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
    # Screen and authority proofs share memory-span's enclose-then-split
    # prover over one set of every adapter span; clustered storage needs one
    # query of each kind.
    prove = _word(source, "_RUHA-SAFE-PROVE?")
    admit = _word(source, "_RUHA-SAFE-ADMIT?")
    assert "['] SCR-STORAGE-DISJOINT? _RUHA-SAFE-PROVE?" in screen_storage
    assert screen_storage.count("SCR-STORAGE-DISJOINT?") == 1
    assert ("['] _RUHA-CURRENT-AUTHORITY-DISJOINT? _RUHA-SAFE-PROVE?"
            in _word(source, "_RUHA-STORAGE-DISJOINT-CURRENT?"))
    assert "_RUHA-SAFE-SPAN-CAPACITY _RUHA-SAFE-SPANS MSPAN-SET-INIT" in prove
    assert prove.index("['] _RUHA-SAFE-ADMIT? _RUHA-STORAGE-SPANS?") < prove.index(
        "_RUHA-SAFE-SPANS SWAP MSPAN-SET-PROVE-DISJOINT?"
    )
    # RUHA's policy: no address zero and no empty or negative span.
    assert "OVER 0= OVER 0> 0= OR IF 2DROP 0 EXIT THEN" in admit
    assert "_RUHA-SAFE-SPANS MSPAN-SET-PUSH MSPAN-SET-S-OK =" in admit
    assert "17 CONSTANT _RUHA-SAFE-SPAN-CAPACITY" in source
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


def test_abi9_layout_embeds_both_fixed_model_builders_and_menu_lineage() -> None:
    source = _source()
    assert "240 CONSTANT RUHA-DOCUMENT-SIZE" in source
    assert _offset_for_snapshot_field(source, "_RUHA-D.OWNER-ID") == 224
    assert _offset_for_snapshot_field(source, "_RUHA-D.OWNER-GEN") == 232
    assert "208 CONSTANT RUHA-SNAPSHOT-SIZE" in source
    assert _constant(source, "RUHA-SIZE") == 1024
    assert "9 CONSTANT _RUHA-ABI" in source
    assert '0x3941485544495552 CONSTANT _RUHA-MAGIC' in source
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
    ) == 384
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U"
    ) == 392
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U"
    ) == 400
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-NATIVE-A"
    ) == 408
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-NATIVE-U"
    ) == 416
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U"
    ) == 424
    assert _offset_for_snapshot_field(
        source, "_RUHA-A.DATA-GRAPHICS-BUILDER"
    ) == 432
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAPSHOT-A") == 608
    assert _offset_for_snapshot_field(source, "_RUHA-A.SNAPSHOT-B") == 816
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
    assert _offset_for_snapshot_field(
        source, "_RUHA-D.MENU-TOPOLOGY-EPOCH"
    ) == 152
    assert "USCOL-BUILDER-SIZE" in source
    assert "UDG-BUILDER-SIZE" in source
    assert "_RUHA-A.RESERVED" not in source


def test_public_aggregate_abi_keeps_document_slices_and_draw_identity() -> None:
    source = _source()
    for required in (
        "240 CONSTANT RUHA-DOCUMENT-SIZE",
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
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@",
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
        "9 CONSTANT _RUHA-ABI",
        '0x3941485544495552 CONSTANT _RUHA-MAGIC',
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


def test_document_menu_epochs_certify_exact_and_control_topology_lineage() -> None:
    source = _source()
    append = _word(source, "_RUHA-B-APPEND-DOCUMENT")
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    validate = _word(source, "_RUHA-B-PRIOR-MENU?")
    compare_record = _word(source, "_RUHA-B-MENU-RECORD=?")
    compare_topology = _word(source, "_RUHA-B-MENU-TOPOLOGY-RECORD=?")
    compare_menu = _word(source, "_RUHA-B-MENU-LINEAGE")
    select = _word(source, "_RUHA-B-CAPTURE-MENU-EPOCHS")
    reuse = _word(source, "_RUHA-B-REUSE?")

    assert "_RUHA-B-APPEND-RECORD-U @ 0=" in append
    assert "_RUHA-B-APPEND-MENU-EPOCH @ 0= <>" in append
    assert "_RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH @ 0= <>" in append
    assert re.search(
        r"_RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH\s+@\s+"
        r"_RUHA-B-APPEND-MENU-EPOCH\s+@\s+U>",
        append,
    )
    assert "_RUHA-D.MENU-EPOCH !" in append
    assert "_RUHA-D.MENU-TOPOLOGY-EPOCH !" in append
    assert "RUHA-DOCUMENT-MENU-EPOCH@" in validate
    assert "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@" in validate
    assert "_RUHA-B-REUSE-MENU-EPOCH !" in validate
    assert "_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH !" in validate
    assert "_RUHA-B-REUSE-RECORD-U @ 0=" in validate
    assert "_RUHA-B-REUSE-MENU-EPOCH @ 0= <>" in validate
    assert "_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @ 0= <>" in validate
    assert validate.count("_RUHA-B-PRIOR-GENERATION @ U>") == 2
    assert re.search(
        r"_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH\s+@\s+"
        r"_RUHA-B-REUSE-MENU-EPOCH\s+@\s+U>",
        validate,
    )
    assert "24 COMPARE" in compare_record
    assert compare_record.count("32 + UMSN-RECORD-SIZE 32 -") == 2

    # Control topology excludes generation and state.  It also excludes
    # resolved geometry for menu/item/separator records and resolved style for
    # every record; only the menubar's row/col/height/width/z are retained.
    assert "UMSN-RECORD-KIND@" in compare_topology
    assert "UMSN-K-MENUBAR" in compare_topology
    assert "UMSN-RECORD-SIZE 80 -" not in compare_topology
    assert "UTUI-RESOLVED-SIZE" not in compare_topology
    assert "_RUHA-B-CAPTURE-RECORD-U @" in compare_menu
    assert "_RUHA-B-CAPTURE-TEXT-U @ COMPARE" in compare_menu
    assert "_RUHA-B-MENU-TOPOLOGY-RECORD=?" in compare_menu
    assert "_RUHA-B-GENERATION @" in select
    assert "_RUHA-B-MENU-LINEAGE" in select
    assert "_RUHA-B-CAPTURE-MENU-EPOCH !" in select
    assert "_RUHA-B-CAPTURE-MENU-TOPOLOGY-EPOCH !" in select
    _ordered(
        capture,
        "UMSN-CAPTURE",
        "_RUHA-B-CAPTURE-MENU-EPOCHS",
        "_RUHA-B-CAPTURE-MENU-EPOCH @",
        "_RUHA-B-CAPTURE-MENU-TOPOLOGY-EPOCH @",
        "_RUHA-B-APPEND-DOCUMENT",
    )
    assert "_RUHA-B-REUSE-MENU-EPOCH @" in reuse
    assert "_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @" in reuse
    assert reuse.index("_RUHA-B-REUSE-MENU-EPOCH @") < reuse.index(
        "_RUHA-B-APPEND-DOCUMENT"
    )
    assert reuse.index("_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @") < reuse.index(
        "_RUHA-B-APPEND-DOCUMENT"
    )

    prior = bytearray(2 * 192)
    prior[40:48] = (7).to_bytes(8, "little")
    prior[64:72] = (1).to_bytes(8, "little")  # menubar
    prior[120:152] = b"".join(
        value.to_bytes(8, "little") for value in (0, 0, 1, 80)
    )
    prior[152:184] = b"".join(
        value.to_bytes(8, "little") for value in (7, 0, 3, 1)
    )
    prior[184:192] = (5).to_bytes(8, "little")
    prior[192 + 40 : 192 + 48] = (9).to_bytes(8, "little")
    prior[192 + 56 : 192 + 64] = (1).to_bytes(8, "little")
    prior[192 + 64 : 192 + 72] = (3).to_bytes(8, "little")  # item
    prior[192 + 80 : 192 + 88] = (1).to_bytes(8, "little")
    prior[192 + 120 : 192 + 192] = bytes(range(72))
    current = bytearray(prior)
    current[24:32] = (101).to_bytes(8, "little")
    current[192 + 24 : 192 + 32] = (101).to_bytes(8, "little")
    prior[24:32] = (44).to_bytes(8, "little")
    prior[192 + 24 : 192 + 32] = (44).to_bytes(8, "little")
    common = dict(
        generation=101,
        prior_exact_epoch=12,
        prior_topology_epoch=6,
        records=bytes(current),
        prior_records=bytes(prior),
        text=b"FileEdit",
        prior_text=b"FileEdit",
    )
    assert _menu_lineage_oracle(**common) == (12, 6)

    state_changed = bytearray(current)
    state_changed[72] ^= 1
    assert _menu_lineage_oracle(
        **(common | {"records": bytes(state_changed)})
    ) == (101, 6)

    child_geometry_changed = bytearray(current)
    child_geometry_changed[192 + 120] ^= 1
    assert _menu_lineage_oracle(
        **(common | {"records": bytes(child_geometry_changed)})
    ) == (101, 6)

    menubar_style_changed = bytearray(current)
    menubar_style_changed[152] ^= 1
    assert _menu_lineage_oracle(
        **(common | {"records": bytes(menubar_style_changed)})
    ) == (101, 6)

    for topology_offset in (
        0,    # checked record header
        32,   # source kind
        40,   # source index
        48,   # semantic subkey
        56,   # parent index
        64,   # neutral kind
        80,   # authored order
        88,   # label offset
        96,   # label bytes
        104,  # shortcut offset
        112,  # shortcut bytes
        120,  # menubar row
        184,  # menubar z
        192 + 56,
        192 + 80,
    ):
        topology_changed = bytearray(current)
        topology_changed[topology_offset] ^= 1
        assert _menu_lineage_oracle(
            **(common | {"records": bytes(topology_changed)})
        ) == (101, 101)

    assert _menu_lineage_oracle(**(common | {"text": b"FileExit"})) == (
        101,
        101,
    )
    assert _menu_lineage_oracle(
        **(common | {"prior_exact_epoch": 0})
    ) == (101, 101)
    assert _menu_lineage_oracle(
        **(common | {"prior_topology_epoch": 0})
    ) == (101, 101)
    assert _menu_lineage_oracle(
        **(
            common
            | {"prior_exact_epoch": 12, "prior_topology_epoch": 13}
        )
    ) == (101, 101)
    assert _menu_lineage_oracle(
        **(common | {"unique_prior": False})
    ) == (101, 101)
    assert _menu_lineage_oracle(
        generation=101,
        prior_exact_epoch=0,
        prior_topology_epoch=0,
        records=b"",
        prior_records=b"",
        text=b"",
        prior_text=b"",
    ) == (0, 0)

    old_epochs = ((11, 4), (12, 6), (13, 8))
    new_epochs = tuple(
        _menu_lineage_oracle(
            generation=101,
            prior_exact_epoch=exact_epoch,
            prior_topology_epoch=topology_epoch,
            records=bytes(state_changed) if index == 1 else bytes(current),
            prior_records=bytes(prior),
            text=b"FileEdit",
            prior_text=b"FileEdit",
        )
        for index, (exact_epoch, topology_epoch) in enumerate(old_epochs)
    )
    assert new_epochs == ((11, 4), (101, 6), (13, 8))


# The modules whose builder sizes the adapter's layout embeds.
_BUILDER_MODULES = (
    ROOT / "akashic/tui/semantic-collections.f",
    ROOT / "akashic/tui/data-graphics-model.f",
)


def _constant(source: str, name: str) -> int:
    for text in (source, *(path.read_text(encoding="utf-8") for path in _BUILDER_MODULES)):
        match = re.search(rf"(?m)^(.+?)\s+CONSTANT {re.escape(name)}(?=\s|$)", text)
        if match is not None:
            return _evaluate(source, match.group(1))
    raise AssertionError(name)


def _evaluate(source: str, expression: str) -> int:
    stack: list[int] = []
    for token in expression.split():
        if token == "+":
            right = stack.pop()
            stack.append(stack.pop() + right)
        elif token.isdigit():
            stack.append(int(token))
        else:
            stack.append(_constant(source, token))
    assert len(stack) == 1, expression
    return stack[0]


def _offset_for_snapshot_field(source: str, name: str) -> int:
    """The byte offset a field word adds to its record's address, following
    offsets derived from the sizes of embedded builders and snapshots."""
    definition = _word(source, name)
    match = re.search(r"(?s)\([^)]*--[^)]*\)(.*);", definition)
    assert match is not None, name
    tokens = match.group(1).split()
    if not tokens:
        return 0
    assert tokens[-1] == "+", name
    return _evaluate(source, " ".join(tokens[:-1]))


def test_content_epoch_byte_oracle_preserves_only_exact_complete_reuse() -> None:
    prior_directory = bytes(range(160)) + bytes(reversed(range(160)))
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
        {
            "directory": prior_directory[:152]
            + bytes([prior_directory[152] ^ 1])
            + prior_directory[153:]
        },                              # menu-topology epoch directory byte
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
    # All five families pass two output tails. Every
    # exactly exhausted bank must become canonical `0 0` rather than a
    # one-past-end address with zero bytes.
    assert capture.count("_RUHA-B-TAIL-SPAN") == 10
    assert "ASHELL-ACTIVE-CTX _RUHA-B-ORIGINAL-CTX !" in query
    assert "['] _RUHA-B-CAPTURE CATCH" in query
    assert "['] _RUHA-B-RESTORE CATCH" in query
    assert "_RUHA-R.UCTX @ ASHELL-CTX-SWITCH" in capture
    assert capture.count("ASHELL-CTX-SWITCH") == 1
    switch = capture.index("ASHELL-CTX-SWITCH")
    assert switch < capture.index("UMSN-CAPTURE")
    assert switch < capture.index("UCSN-CAPTURE")
    assert switch < capture.index("UDGSN-CAPTURE")
    _ordered(capture, "UMSN-CAPTURE", "UCSN-CAPTURE", "UDGSN-CAPTURE",
             "USFSN-CAPTURE", "UFLSN-CAPTURE")
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
        r"_RUHA-B-DGRAPH-COUNT @ 0= AND\s+"
        r"_RUHA-B-SFIELD-COUNT @ 0= AND\s+"
        r"_RUHA-B-FIELD-COUNT @ 0= AND IF",
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
    assert "RUHA-DOCUMENT-OWNER-ID@" in find
    assert "RUHA-DOCUMENT-OWNER-GENERATION@" in find
    assert "CINST.ID @ = AND" in find
    assert "CINST.GENERATION @ = AND" in find
    assert "_RUHA-B-FIND-MATCHES @ 1 =" in find
    assert (validate + menu_validate).count("_RUHA-UADD?") >= 6
    assert "RUHA-DOCUMENT-MENU-EPOCH@" in menu_validate
    assert "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@" in menu_validate
    assert "_RUHA-B-REUSE-MENU-EPOCH !" in menu_validate
    assert "_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH !" in menu_validate
    assert "_RUHA-B-REUSE-RECORD-U @ 0=" in menu_validate
    assert "_RUHA-B-REUSE-MENU-EPOCH @ 0= <>" in menu_validate
    assert "_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @ 0= <>" in menu_validate
    assert re.search(
        r"_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH\s+@\s+"
        r"_RUHA-B-REUSE-MENU-EPOCH\s+@\s+U>",
        menu_validate,
    )
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
    # RUHA relocates all ten document-local banks verbatim.
    assert reuse.count(" MOVE") == 10
    for target in (
        "_RUHA-B-REUSE-DESCRIPTOR-TARGET",
        "_RUHA-B-REUSE-NATIVE-TARGET",
        "_RUHA-B-REUSE-DGRAPH-DESCRIPTOR-TARGET",
        "_RUHA-B-REUSE-DGRAPH-NATIVE-TARGET",
        "_RUHA-B-REUSE-SFIELD-DESCRIPTOR-TARGET",
        "_RUHA-B-REUSE-SFIELD-NATIVE-TARGET",
        "_RUHA-B-REUSE-FIELD-DESCRIPTOR-TARGET",
        "_RUHA-B-REUSE-FIELD-NATIVE-TARGET",
    ):
        assert target in reuse
    for length in (
        "_RUHA-B-REUSE-DESCRIPTOR-U @",
        "_RUHA-B-REUSE-NATIVE-U @",
        "_RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @",
        "_RUHA-B-REUSE-DGRAPH-NATIVE-U @",
        "_RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @",
        "_RUHA-B-REUSE-SFIELD-NATIVE-U @",
        "_RUHA-B-REUSE-FIELD-DESCRIPTOR-U @",
        "_RUHA-B-REUSE-FIELD-NATIVE-U @",
    ):
        assert length in reuse
    assert "_RUHA-UMSN.GENERATION !" in reuse
    assert "_RUHA-B-REUSE-MENU-EPOCH @" in reuse
    assert "_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @" in reuse
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
    clean_empty = dispatch.index("_RUHA-RECORD-DIRTY? 0= IF")
    clean_empty_stage = dispatch.index(
        "-1 _RUHA-B-RECORD @ _RUHA-B-STAGE", clean_empty
    )
    occlusion = dispatch.index("SCR-OCCLUSION-RECT?")
    assert clean_empty < clean_empty_stage < occlusion
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


def test_final_writer_occlusion_falls_back_the_complete_document_atomically() -> None:
    source = _source()
    dispatch = _word(source, "_RUHA-B-CAPTURE-RECORD")

    visible_at = dispatch.index("_RUHA-RECORD-VISIBLE?")
    clean_empty_at = dispatch.index("_RUHA-RECORD-DIRTY? 0= IF")
    clean_empty_stage_at = dispatch.index(
        "-1 _RUHA-B-RECORD @ _RUHA-B-STAGE", clean_empty_at
    )
    query_at = dispatch.index("SCR-OCCLUSION-RECT?")
    valid_at = dispatch.index("0= IF DROP RUHA-S-INVALID EXIT THEN", query_at)
    hit_at = dispatch.index("\n    IF\n", valid_at)
    hit_end = dispatch.index("\n    THEN", hit_at)
    hit_branch = dispatch[hit_at:hit_end]
    normal_dirty_at = dispatch.index("_RUHA-RECORD-DIRTY?", hit_end)

    assert (
        visible_at
        < clean_empty_at
        < clean_empty_stage_at
        < query_at
        < valid_at
        < hit_at
        < normal_dirty_at
    )
    assert dispatch.count("SCR-OCCLUSION-RECT?") == 1
    # Directory/totals comparison invalidates the first masked transition;
    # leaving this latch alone lets identical masked frames retain content
    # provenance until exposure triggers the deliberately dirty recapture.
    assert "_RUHA-B-EXACT-REUSE" not in hit_branch
    assert "_RUHA-RECORD-DIRTY!" in hit_branch
    assert (
        "0 0 0 0 0 0 0 0 0 0 _RUHA-B-APPEND-DOCUMENT EXIT"
        in hit_branch
    )
    assert "_RUHA-B-STAGE" not in hit_branch
    for partial_family in (
        "UMSN-CAPTURE",
        "UCSN-CAPTURE",
        "UDGSN-CAPTURE",
        "_RUHA-B-REUSE?",
    ):
        assert partial_family not in hit_branch


def test_a_family_refusal_falls_back_only_its_own_document() -> None:
    source = _source()
    fall_back = _word(source, "_RUHA-B-FALL-BACK")
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")

    # The refused document leaves as a covered one does: a directory-only
    # identity whose residual CELL shows it, dirty so the next draw retries,
    # and unstaged so no refused state can be reused.
    _ordered(
        fall_back,
        "DROP",
        "_RUHA-B-FALL-BACK-REUSE @ _RUHA-B-EXACT-REUSE !",
        "_RUHA-B-RECORD @ _RUHA-RECORD-DIRTY!",
        "0 0 0 0 0 0 0 0 0 0 _RUHA-B-APPEND-DOCUMENT",
    )
    assert "_RUHA-B-STAGE" not in fall_back
    for family in ("UMSN-CAPTURE", "UCSN-CAPTURE", "UDGSN-CAPTURE"):
        assert family not in fall_back

    # No live capture happened, so provenance is what it was before it.
    _ordered(
        capture,
        "_RUHA-B-EXACT-REUSE @ _RUHA-B-FALL-BACK-REUSE !",
        "0 _RUHA-B-EXACT-REUSE !",
        "ASHELL-CTX-SWITCH",
    )
    assert capture.count("_RUHA-B-FALL-BACK EXIT") == 5
    _ordered(
        capture,
        "UMSN-CAPTURE",
        "_RUHA-B-MAP-STATUS _RUHA-B-FALL-BACK EXIT",
        "UCSN-CAPTURE",
        "_RUHA-B-MAP-COLLECTION-STATUS _RUHA-B-FALL-BACK EXIT",
        "UDGSN-CAPTURE",
        "_RUHA-B-MAP-DATA-GRAPHICS-STATUS _RUHA-B-FALL-BACK EXIT",
        "USFSN-CAPTURE",
        "_RUHA-B-MAP-STATUS-FIELDS-STATUS _RUHA-B-FALL-BACK EXIT",
        "UFLSN-CAPTURE",
        "_RUHA-B-MAP-FIELDS-STATUS _RUHA-B-FALL-BACK EXIT",
    )
    # The adapter's own bank checks, and a family result that breaks its
    # contract, remain refusals of the whole aggregate.
    preflight = capture[: capture.index("ASHELL-CTX-SWITCH")]
    assert "_RUHA-B-FALL-BACK EXIT" not in preflight
    assert "RUHA-S-CAPACITY EXIT" in preflight
    assert "RUHA-S-INVALID EXIT" in preflight
    after_menu = capture[capture.index("_RUHA-B-MAP-STATUS _RUHA-B-FALL-BACK EXIT"):]
    assert "_RUHA-B-COUNT @ 0< _RUHA-B-CAPTURE-TEXT-U @ 0< OR IF\n        RUHA-S-INVALID EXIT" in after_menu


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


# The reuse shortcut, executed.  Only the real reuse word, the real append it
# makes, and their source dependencies are compiled.  The prior slice's
# validation and the staging bookkeeping are fixture seams, and the adapter's
# data-graphics fields sit at a fixture offset in fixture storage.
def _reuse_definitions() -> dict[str, str]:
    definitions: dict[str, str] = {}
    for path in (MENU_SNAPSHOT, ADAPTER, ROOT / "akashic/utils/memory-span.f", ROOT / "akashic/utils/uint-range.f", ROOT / "akashic/runtime/instance.f", ROOT / "akashic/tui/applet-host/host.f"):
        text = re.sub(r"(?m)\\[^\n]*$", "", path.read_text(encoding="utf-8"))
        for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;[ \t]*$", text):
            definitions[match[1]] = match[0]
        for match in re.finditer(r"(?m)^VARIABLE (\S+)\s*$", text):
            definitions[match[1]] = match[0]
        for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", text):
            definitions[match[2]] = match[0]
    definitions.update({
        "_RUHA-B-PRIOR-ENTRY?": ": _RUHA-B-PRIOR-ENTRY? DROP -1 ;",
        "RS-STAGED": "VARIABLE RS-STAGED",
        "_RUHA-B-STAGE": ": _RUHA-B-STAGE 2DROP 1 RS-STAGED +! ;",
        "_RUHA-O.DGRAPH": "320 CONSTANT _RUHA-O.DGRAPH",
        "_RUHA-O.SFIELD": "368 CONSTANT _RUHA-O.SFIELD",
        "_RUHA-O.FIELD": "416 CONSTANT _RUHA-O.FIELD",
        "UFLD-HEADER-SIZE": "192 CONSTANT UFLD-HEADER-SIZE",
        "UFLSN-DESCRIPTOR-SIZE": "128 CONSTANT UFLSN-DESCRIPTOR-SIZE",
        "USF-HEADER-SIZE": "72 CONSTANT USF-HEADER-SIZE",
        "USFSN-DESCRIPTOR-SIZE": "128 CONSTANT USFSN-DESCRIPTOR-SIZE",
    })
    return definitions


class _ReuseHarness:
    BANK = 1024
    FILL = 0xA5

    def __init__(self, backend: str) -> None:
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _reuse_definitions()
        chunks: list[str] = []
        seen: set[str] = set()

        def include(name: str) -> None:
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            code = re.sub(r"\([^)]*\)", "", declaration)
            for token in code.split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in ("RS-STAGED", "_RUHA-B-REUSE?", "_RUHA-STATUS-STORAGE?",
                     "_RUHA-FIELD-STORAGE?", "_RUHA-B-TAIL-SPAN"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0

    def allocate(self, size: int, fill: int = 0) -> int:
        self.serial += 1
        word = self.runtime.define_created(f"RS-{self.serial}", initial_body=bytes(size + 7))
        address = (word.body_address + 7) & -8
        self.runtime.memory.write_bytes(address, bytes([fill]) * size)
        return address

    def set(self, name: str, value: int) -> None:
        word = self.runtime.dictionary.find(name.encode())
        self.runtime.memory.write64(word.body_address, value & MASK64)

    def get(self, name: str) -> int:
        return self.runtime.memory.read64(self.runtime.dictionary.find(name.encode()).body_address)

    def offset(self, name: str) -> int:
        match = re.search(r"\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def results(self, name: str, *inputs: int) -> tuple:
        for value in inputs:
            self.runtime.main_context.data.push(value)
        self.runtime.execute(name, step_budget=3_000_000)
        result = self.runtime.main_context.data.snapshot()
        while self.runtime.main_context.data.depth():
            self.runtime.main_context.data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result


_REUSE_BANKS = ("DIRECTORY", "RECORDS", "TEXT", "DESCRIPTORS", "NATIVE",
                "DGRAPH-DESCRIPTORS", "DGRAPH-NATIVE",
                "SFIELD-DESCRIPTORS", "SFIELD-NATIVE",
                "FIELD-DESCRIPTORS", "FIELD-NATIVE")
_BANK_FIELD = {
    "DIRECTORY": "_RUHA-A.SNAP-DIRECTORY-BANK-U",
    "RECORDS": "_RUHA-A.SNAP-RECORD-BANK-U",
    "TEXT": "_RUHA-A.SNAP-TEXT-BANK-U",
    "DESCRIPTORS": "_RUHA-A.SNAP-DESCRIPTOR-BANK-U",
    "NATIVE": "_RUHA-A.SNAP-NATIVE-BANK-U",
}


def _reuse_fixture(harness: _ReuseHarness, native_bank: int) -> dict:
    """One collection-bearing document is already in this draw's aggregate;
    the next, unchanged document reuses 168 descriptor and 256 native bytes."""

    adapter = harness.allocate(512)
    for bank, field in _BANK_FIELD.items():
        harness.runtime.memory.write64(adapter + harness.offset(field), harness.BANK)
    harness.runtime.memory.write64(adapter + harness.offset("_RUHA-A.SNAP-NATIVE-BANK-U"),
                                   native_bank)
    dgraph = harness.definitions["_RUHA-O.DGRAPH"].split()[0]
    for extra in (16, 40):  # the data-graphics descriptor and native bank sizes
        harness.runtime.memory.write64(adapter + int(dgraph) + extra, harness.BANK)
    sfield = int(harness.definitions["_RUHA-O.SFIELD"].split()[0])
    for extra in (16, 40):
        harness.runtime.memory.write64(adapter + sfield + extra, harness.BANK)
    field = int(harness.definitions["_RUHA-O.FIELD"].split()[0])
    for extra in (16, 40):
        harness.runtime.memory.write64(adapter + field + extra, harness.BANK)
    record = harness.allocate(128)
    for field, value in (("_RUHA-R.TOKEN", 11), ("_RUHA-R.SLOT-ID", 22),
                         ("_RUHA-R.ROW", 1), ("_RUHA-R.COL", 2),
                         ("_RUHA-R.HEIGHT", 3), ("_RUHA-R.WIDTH", 4)):
        harness.runtime.memory.write64(record + harness.offset(field), value)
    slot = harness.allocate(256)
    instance = harness.allocate(80)
    harness.runtime.memory.write64(slot + 8, instance)
    harness.runtime.memory.write64(instance + 16, 301)
    harness.runtime.memory.write64(instance + 24, 302)
    harness.runtime.memory.write64(record + harness.offset("_RUHA-R.SLOT"), slot)
    harness.set("_RUHA-B-ADAPTER", adapter)
    harness.set("_RUHA-B-RECORD", record)
    harness.set("_RUHA-B-GENERATION", 7)
    harness.set("_RUHA-B-DOCUMENTS", 1)
    harness.set("RS-STAGED", 0)
    used = {"DIRECTORY": 240, "RECORDS": 0, "TEXT": 0, "DESCRIPTORS": 168,
            "NATIVE": 400, "DGRAPH-DESCRIPTORS": 0, "DGRAPH-NATIVE": 0,
            "SFIELD-DESCRIPTORS": 0, "SFIELD-NATIVE": 0,
            "FIELD-DESCRIPTORS": 0, "FIELD-NATIVE": 0}
    banks = {}
    for bank in _REUSE_BANKS:
        banks[bank] = harness.allocate(harness.BANK, harness.FILL)
        harness.set(f"_RUHA-B-{bank}-A", banks[bank])
        harness.set(f"_RUHA-B-{bank}-U", used[bank])
        if bank != "DIRECTORY":  # the entry is written anew, not copied
            harness.set(f"_RUHA-B-PRIOR-{bank}-A", harness.allocate(harness.BANK))
    prior_native = bytes(range(256))
    harness.runtime.memory.write_bytes(harness.get("_RUHA-B-PRIOR-NATIVE-A"), prior_native)
    for name, value in (("RECORD-U", 0), ("TEXT-U", 0), ("RECORD-O", 0), ("TEXT-O", 0),
                        ("DESCRIPTOR-U", 168), ("DESCRIPTOR-O", 0),
                        ("NATIVE-U", 256), ("NATIVE-O", 0),
                        ("DGRAPH-DESCRIPTOR-U", 0), ("DGRAPH-DESCRIPTOR-O", 0),
                        ("DGRAPH-NATIVE-U", 0), ("DGRAPH-NATIVE-O", 0),
                        ("SFIELD-DESCRIPTOR-U", 0), ("SFIELD-DESCRIPTOR-O", 0),
                        ("SFIELD-NATIVE-U", 0), ("SFIELD-NATIVE-O", 0),
                        ("FIELD-DESCRIPTOR-U", 0), ("FIELD-DESCRIPTOR-O", 0),
                        ("FIELD-NATIVE-U", 0), ("FIELD-NATIVE-O", 0),
                        ("MENU-EPOCH", 0), ("MENU-TOPOLOGY-EPOCH", 0), ("COUNT", 0)):
        harness.set(f"_RUHA-B-REUSE-{name}", value)
    return {"banks": banks, "used": used, "prior_native": prior_native}


def _aggregate_unchanged(harness: _ReuseHarness, fixture: dict) -> None:
    assert harness.get("_RUHA-B-DOCUMENTS") == 1
    assert harness.get("RS-STAGED") == 0
    for bank in _REUSE_BANKS:
        assert harness.get(f"_RUHA-B-{bank}-U") == fixture["used"][bank], bank
        actual = harness.runtime.memory.read_bytes(fixture["banks"][bank], harness.BANK)
        expected = fixture.get("before", {}).get(bank, bytes([harness.FILL]) * harness.BANK)
        assert actual == expected, bank
    for address, before in fixture.get("prior_before", {}).items():
        assert harness.runtime.memory.read_bytes(address, len(before)) == before


@pytest.fixture(params=("python", "native"))
def reuse(request):
    return _ReuseHarness(request.param)


def test_a_reused_slice_that_no_longer_fits_is_captured_afresh(reuse) -> None:
    source = _source()
    word = _word(source, "_RUHA-B-REUSE?")
    # A capacity refusal leaves the document to a fresh capture; any other
    # refusal of the append still refuses the aggregate.
    _ordered(word, "_RUHA-B-APPEND-DOCUMENT",
             "DUP RUHA-S-CAPACITY = IF DROP RUHA-S-OK 0 EXIT THEN",
             "DUP RUHA-S-OK <> IF -1 EXIT THEN DROP")
    assert "_RUHA-B-REUSE? IF EXIT THEN DROP" in _word(source, "_RUHA-B-CAPTURE-RECORD")

    # It fits exactly: the prior slice is appended and the document staged.
    fixture = _reuse_fixture(reuse, native_bank=400 + 256)
    assert reuse.results("_RUHA-B-REUSE?", 0) == (0, MASK64)
    assert reuse.get("_RUHA-B-DOCUMENTS") == 2
    assert reuse.get("_RUHA-B-NATIVE-U") == 656
    assert reuse.get("_RUHA-B-DIRECTORY-U") == 480
    assert reuse.get("RS-STAGED") == 1
    assert reuse.runtime.memory.read_bytes(fixture["banks"]["NATIVE"] + 400, 256) == (
        fixture["prior_native"]
    )
    entry = fixture["banks"]["DIRECTORY"] + 240
    assert reuse.runtime.memory.read64(entry + reuse.offset("_RUHA-D.TOKEN")) == 11
    assert reuse.runtime.memory.read64(
        entry + reuse.offset("_RUHA-D.COLLECTION-NATIVE-OFF")) == 400
    assert reuse.runtime.memory.read64(
        entry + reuse.offset("_RUHA-D.COLLECTION-NATIVE-U")) == 256

    # One byte short: not reused, and nothing of the aggregate changed, so
    # the fresh capture that follows starts from the same place.
    fixture = _reuse_fixture(reuse, native_bank=400 + 256 - 1)
    assert reuse.results("_RUHA-B-REUSE?", 0) == (0, 0)
    _aggregate_unchanged(reuse, fixture)

    # A slice whose menu epochs break the append's contract still refuses.
    fixture = _reuse_fixture(reuse, native_bank=400 + 256)
    reuse.set("_RUHA-B-REUSE-MENU-EPOCH", 1)
    invalid = int(reuse.definitions["RUHA-S-INVALID"].split()[0])
    assert reuse.results("_RUHA-B-REUSE?", 0) == (invalid, MASK64)
    _aggregate_unchanged(reuse, fixture)



@pytest.mark.parametrize("family,native_bytes", (("SFIELD", 80), ("FIELD", 192)))
def test_field_family_reuse_copies_independent_slices_and_checks_capacity_first(reuse, family, native_bytes):
    fixture = _reuse_fixture(reuse, native_bank=656)
    descriptor = bytes((i * 7 + 3) & 255 for i in range(128))
    native = bytes((i * 11 + 5) & 255 for i in range(native_bytes))
    for bank, payload, field, prefix in (("DESCRIPTORS", descriptor, "DESCRIPTOR", 128),
                                        ("NATIVE", native, "NATIVE", native_bytes)):
        # Different source and target offsets detect accidental cross-family
        # copies or interpretation of document-local offsets as aggregate ones.
        reuse.runtime.memory.write_bytes(reuse.get(f"_RUHA-B-PRIOR-{family}-{bank}-A") + 16, payload)
        reuse.set(f"_RUHA-B-REUSE-{family}-{field}-O", 16)
        reuse.set(f"_RUHA-B-REUSE-{family}-{field}-U", len(payload))
        reuse.set(f"_RUHA-B-{family}-{bank}-U", prefix)
    assert reuse.results("_RUHA-B-REUSE?", 0) == (0, MASK64)
    entry = fixture["banks"]["DIRECTORY"] + 240
    for bank, payload, field, prefix in (("DESCRIPTORS", descriptor, "DESCRIPTOR", 128),
                                        ("NATIVE", native, "NATIVE", native_bytes)):
        assert reuse.get(f"_RUHA-B-{family}-{bank}-U") == prefix + len(payload)
        target = fixture["banks"][f"{family}-{bank}"]
        assert reuse.runtime.memory.read_bytes(target, prefix) == bytes([reuse.FILL]) * prefix
        assert reuse.runtime.memory.read_bytes(target + prefix, len(payload)) == payload
        assert reuse.runtime.memory.read64(entry + reuse.offset(f"_RUHA-D.{family}-{field}-OFF")) == prefix
        assert reuse.runtime.memory.read64(entry + reuse.offset(f"_RUHA-D.{family}-{field}-U")) == len(payload)
    untouched_family = "FIELD" if family == "SFIELD" else "SFIELD"
    for bank in ("DESCRIPTORS", "NATIVE"):
        assert reuse.get(f"_RUHA-B-{untouched_family}-{bank}-U") == 0
        assert reuse.runtime.memory.read_bytes(fixture["banks"][f"{untouched_family}-{bank}"], reuse.BANK) == bytes([reuse.FILL]) * reuse.BANK
    fixture = _reuse_fixture(reuse, native_bank=656)
    reuse.set(f"_RUHA-B-REUSE-{family}-DESCRIPTOR-U", 128)
    reuse.set(f"_RUHA-B-REUSE-{family}-NATIVE-U", native_bytes)
    adapter = reuse.get("_RUHA-B-ADAPTER")
    offset = int(reuse.definitions[f"_RUHA-O.{family}"].split()[0])
    reuse.runtime.memory.write64(adapter + offset + 40, native_bytes - 1)
    assert reuse.results("_RUHA-B-REUSE?", 0) == (0, 0)
    _aggregate_unchanged(reuse, fixture)


def test_last_field_native_capacity_failure_preserves_every_prior_bank(reuse):
    fixture = _reuse_fixture(reuse, native_bank=656)
    # Every family contributes bytes. FIELD native is the final capacity
    # check, so a premature append or copy in any earlier family is visible.
    additions = {
        "RECORDS": ("RECORD", 192, 192), "TEXT": ("TEXT", 16, 5),
        "DESCRIPTORS": ("DESCRIPTOR", 168, 168), "NATIVE": ("NATIVE", 400, 256),
        "DGRAPH-DESCRIPTORS": ("DGRAPH-DESCRIPTOR", 128, 128),
        "DGRAPH-NATIVE": ("DGRAPH-NATIVE", 80, 80),
        "SFIELD-DESCRIPTORS": ("SFIELD-DESCRIPTOR", 128, 128),
        "SFIELD-NATIVE": ("SFIELD-NATIVE", 80, 80),
        "FIELD-DESCRIPTORS": ("FIELD-DESCRIPTOR", 128, 128),
        "FIELD-NATIVE": ("FIELD-NATIVE", 192, 192),
    }
    fixture["before"] = {}
    fixture["prior_before"] = {}
    for index, (bank, address) in enumerate(fixture["banks"].items()):
        if bank != "DIRECTORY":
            field, used, append = additions[bank]
            fixture["used"][bank] = used
            reuse.set(f"_RUHA-B-{bank}-U", used)
            reuse.set(f"_RUHA-B-REUSE-{field}-U", append)
            reuse.set(f"_RUHA-B-REUSE-{field}-O", 16)
            prior = reuse.get(f"_RUHA-B-PRIOR-{bank}-A")
            payload = bytes((index * 23 + offset * 7) & 255 for offset in range(reuse.BANK))
            reuse.runtime.memory.write_bytes(prior, payload)
            fixture["prior_before"][prior] = payload
        prefix = bytes((index * 19 + offset * 3) & 255 for offset in range(fixture["used"][bank]))
        reuse.runtime.memory.write_bytes(address, prefix)
        fixture["before"][bank] = reuse.runtime.memory.read_bytes(address, reuse.BANK)
    reuse.set("_RUHA-B-REUSE-MENU-EPOCH", 6)
    reuse.set("_RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH", 5)
    reuse.set("_RUHA-B-REUSE-COUNT", 1)
    adapter = reuse.get("_RUHA-B-ADAPTER")
    offset = int(reuse.definitions["_RUHA-O.FIELD"].split()[0])
    reuse.runtime.memory.write64(adapter + offset + 40, 383)
    record = reuse.get("_RUHA-B-RECORD")
    record_before = reuse.runtime.memory.read_bytes(record, 128)
    assert reuse.results("_RUHA-B-REUSE?", 0) == (0, 0)
    _aggregate_unchanged(reuse, fixture)
    assert reuse.runtime.memory.read_bytes(record, 128) == record_before


@pytest.mark.parametrize("family,native_bytes", (("STATUS", 144), ("FIELD", 384)))
def test_optional_field_banks_require_canonical_absence_or_complete_banks(reuse, family, native_bytes):
    word = f"_RUHA-{family}-STORAGE?"
    assert reuse.results(word, 0, 0, 0, 0) == (MASK64,)
    assert reuse.results(word, 4096, 256, 8192, native_bytes) == (MASK64,)
    assert reuse.results(word, 4096, 512, 8192, native_bytes + 16) == (MASK64,)
    for spans in ((4096, 0, 0, 0), (0, 0, 8192, native_bytes), (4096, 256, 0, 0),
                  (4096, 128, 8192, native_bytes), (4096, 256, 8192, native_bytes - 16),
                  (4097, 256, 8192, native_bytes), (4096, 256, MASK64 - 7, native_bytes),
                  (0, 256, 8192, native_bytes), (4096, 256, 0, native_bytes),
                  (4096, 264, 8192, native_bytes), (4096, 256, 8193, native_bytes),
                  (4096, 256, 8192, native_bytes + 8)):
        assert reuse.results(word, *spans) == (0,), spans
    assert reuse.results("_RUHA-B-TAIL-SPAN", 4096, 256, 256) == (0, 0)
    assert reuse.results("_RUHA-B-TAIL-SPAN", 0, 0, 0) == (0, 0)
    assert reuse.results("_RUHA-B-TAIL-SPAN", 4096, 128, 256) == (4224, 128)


def test_status_family_survives_every_snapshot_and_storage_boundary():
    source = _source()
    assert "RUHA-INIT-STATUS" not in source and "RUHA-INIT-FIELDS" not in source
    assert "USFSN-STORAGE-DISJOINT?" in _word(source, "_RUHA-CURRENT-AUTHORITY-DISJOINT?")
    for word in ("_RUHA-I-PAIRWISE?", "_RUHA-I-MODULE-DISJOINT?", "_RUHA-I-AUTHORITY?",
                 "_RUHA-STORAGE-SPANS?", "_RUHA-B-LOAD-PRIOR", "_RUHA-B-PRIOR-ENTRY?",
                 "_RUHA-B-APPEND-DOCUMENT", "_RUHA-B-REUSE?", "_RUHA-B-PUBLISH",
                 "_RUHA-B-CONTENT-UNCHANGED?"):
        assert "SFIELD" in _word(source, word), word
    prior = _word(source, "_RUHA-B-PRIOR-ENTRY?")
    assert "USFSN-FROZEN-VALIDATE" in prior
    assert "_RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @ 0=" in prior
    assert "_RUHA-B-REUSE-SFIELD-NATIVE-U @ 0= <>" in prior
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    assert "_RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @ IF" in capture
    assert "USFSN-CAPTURE" in capture
    assert re.search(r"_RUHA-B-SFIELD-COUNT @ 0= AND\s+_RUHA-B-FIELD-COUNT @ 0= AND IF", capture)
    assert "_RUHA-B-MAP-STATUS-FIELDS-STATUS _RUHA-B-FALL-BACK EXIT" in capture
    assert "_UTUI-STATUS-LABEL-CANONICAL?" in _word(source, "_RUHA-REPLACEABLE-PAINT?")
    assert _offset_for_snapshot_field(source, "_RUHA-D.SFIELD-DESCRIPTOR-OFF") == 160
    assert _offset_for_snapshot_field(source, "_RUHA-D.SFIELD-NATIVE-U") == 184
    assert _offset_for_snapshot_field(source, "_RUHA-S.SFIELD-DESCRIPTORS-A") == 144
    assert _offset_for_snapshot_field(source, "_RUHA-S.SFIELD-NATIVE-U") == 168


def test_field_family_survives_every_snapshot_and_storage_boundary():
    source = _source()
    assert "UFLSN-STORAGE-DISJOINT?" in _word(source, "_RUHA-CURRENT-AUTHORITY-DISJOINT?")
    for word in ("_RUHA-I-PAIRWISE?", "_RUHA-I-MODULE-DISJOINT?", "_RUHA-I-AUTHORITY?",
                 "_RUHA-STORAGE-SPANS?", "_RUHA-B-LOAD-PRIOR", "_RUHA-B-PRIOR-ENTRY?",
                 "_RUHA-B-APPEND-DOCUMENT", "_RUHA-B-REUSE?", "_RUHA-B-PUBLISH",
                 "_RUHA-B-CONTENT-UNCHANGED?"):
        assert re.search(r"(?<!S)FIELD", _word(source, word)), word
    prior = _word(source, "_RUHA-B-PRIOR-ENTRY?")
    assert "UFLSN-FROZEN-VALIDATE" in prior
    assert re.search(r"_RUHA-B-REUSE-FIELD-DESCRIPTOR-U @ 0=\s+"
                     r"_RUHA-B-REUSE-FIELD-NATIVE-U @ 0= <> IF 0 EXIT THEN", prior)
    capture = _word(source, "_RUHA-B-CAPTURE-CURRENT")
    assert "_RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @ IF" in capture
    assert "UFLSN-CAPTURE" in capture
    assert "_RUHA-B-FIELD-COUNT @ 0= AND IF" in capture
    assert "_RUHA-B-MAP-FIELDS-STATUS _RUHA-B-FALL-BACK EXIT" in capture
    assert _offset_for_snapshot_field(source, "_RUHA-D.FIELD-DESCRIPTOR-OFF") == 192
    assert _offset_for_snapshot_field(source, "_RUHA-D.FIELD-NATIVE-U") == 216
    assert _offset_for_snapshot_field(source, "_RUHA-S.FIELD-DESCRIPTORS-A") == 176
    assert _offset_for_snapshot_field(source, "_RUHA-S.FIELD-NATIVE-U") == 200
