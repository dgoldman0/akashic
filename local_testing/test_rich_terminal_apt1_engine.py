"""Seconds-only structural qualification for the neutral APT-1 engine."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic" / "tui" / "rich-terminal" / "apt1-engine.f"

U32_MAX = 0xFFFFFFFF
LABEL_COPY_FIXED = 128
LABEL_FRAME_FIXED = 120
REGION_COPY_BYTES = 72
REGION_FRAME_BYTES = 88


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$", source
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def _align8(value: int) -> int:
    return (value + 7) & ~7


def _unorm32(boundary: int, root: int) -> int:
    assert 0 <= boundary <= root <= U32_MAX
    assert root > 0
    return boundary * U32_MAX // root


def _project_label(
    row: int,
    col: int,
    height: int,
    width: int,
    root_height: int,
    root_width: int,
    *,
    visible: bool,
) -> tuple[int, int, int, int] | None:
    """Mirror the neutral cell-rectangle to APT UNORM32 projection."""

    assert -(1 << 31) <= row < (1 << 31)
    assert -(1 << 31) <= col < (1 << 31)
    assert 0 <= height <= U32_MAX
    assert 0 <= width <= U32_MAX
    assert 0 < root_height <= U32_MAX
    assert 0 < root_width <= U32_MAX

    row_end = row + height
    col_end = col + width
    intersects = (
        height > 0
        and width > 0
        and row < root_height
        and row_end > 0
        and col < root_width
        and col_end > 0
    )
    if visible and not intersects:
        return None

    # Invisible empty/off-root objects still need an ordered wire rectangle;
    # pin that rectangle to the nearest root cell without making it visible.
    left_cell = min(max(col, 0), root_width - 1)
    right_cell = min(max(max(col_end, 0), left_cell + 1), root_width)
    top_cell = min(max(row, 0), root_height - 1)
    bottom_cell = min(max(max(row_end, 0), top_cell + 1), root_height)
    return (
        _unorm32(left_cell, root_width),
        _unorm32(top_cell, root_height),
        _unorm32(right_cell, root_width),
        _unorm32(bottom_cell, root_height),
    )


def _label_retry_copy(text: bytes) -> bytes:
    copied = bytearray(_align8(LABEL_COPY_FIXED + len(text)))
    copied[LABEL_COPY_FIXED : LABEL_COPY_FIXED + len(text)] = text
    return bytes(copied)


def _label_frame_bytes(text: bytes) -> int:
    return LABEL_FRAME_FIXED + len(text)


def _has_prior_region(
    operations: list[tuple[str, int, int, int]],
    index: int,
    owner: int,
    generation: int,
    region: int,
) -> bool:
    return any(
        kind == "region"
        and op_owner == owner
        and op_generation == generation
        and op_region == region
        for kind, op_owner, op_generation, op_region in operations[:index]
    )


def test_rich_terminal_engine_owner_lifecycle_structure() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    provider = "akashic-tui-rtapt1"
    assert f"PROVIDED {provider}" in source
    assert len(provider.encode("ascii")) <= 23
    assert not re.search(
        r"(?m)^REQUIRE\s+.*(?:presentation-terminal|rich-terminal)\.f\s*$",
        source,
    )
    assert "REQUIRE ../../utils/memory-span.f" in source
    assert " CONSTANT APTR-" not in source
    assert "\n: APTR-" not in source
    assert "208 CONSTANT RTAPT-OWNER-SIZE" in source
    assert "496 CONSTANT RTAPT-ENGINE-SIZE" in source
    assert "160 CONSTANT RTAPT-LIMITS-SIZE" in source
    assert ": _RTAPT-E.LIMITS" in source
    owner_fields = {
        "STATE": 0,
        "OWNER": 8,
        "GENERATION": 16,
        "REGIONS": 24,
        "RESOURCES": 32,
        "OBJECTS": 40,
        "SERIES": 48,
        "RES-BYTES": 56,
        "UTF8-BYTES": 64,
        "SAMPLES": 72,
        "WIRE-STATUS": 80,
        "NEXT": 88,
        "PRIOR-GENERATION": 96,
        "ACTIVE-REGIONS": 104,
        "HIDDEN-REGIONS": 112,
        "REGION-HIGH": 120,
        "PENDING-REGIONS": 128,
        "PENDING-REGION-HIGH": 136,
        "ACTIVE-OBJECTS": 144,
        "HIDDEN-OBJECTS": 152,
        "OBJECT-HIGH": 160,
        "ACTIVE-UTF8": 168,
        "HIDDEN-UTF8": 176,
        "PENDING-OBJECTS": 184,
        "PENDING-OBJECT-HIGH": 192,
        "PENDING-UTF8": 200,
    }
    for field, offset in owner_fields.items():
        definition = _definition(source, f"_RTAPT-O.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition
    assert "72 CONSTANT _RTAPT-REGION-DEFINE-COPY-SIZE" in source
    assert "88 CONSTANT _RTAPT-REGION-DEFINE-FRAME-BYTES" in source
    assert "128 CONSTANT _RTAPT-LABEL-DEFINE-COPY-FIXED" in source
    assert "120 CONSTANT _RTAPT-LABEL-DEFINE-FRAME-FIXED" in source
    label_copy_fields = {
        "OWNER": 0,
        "GENERATION": 8,
        "OBJECT": 16,
        "REGION": 24,
        "PARENT": 32,
        "LEFT": 40,
        "TOP": 48,
        "RIGHT": 56,
        "BOTTOM": 64,
        "Z": 72,
        "VISIBLE": 80,
        "RGBA": 88,
        "H-ALIGN": 96,
        "V-ALIGN": 104,
        "ELLIPSIZE": 112,
        "TEXT-U": 120,
        "TEXT": 128,
    }
    for field, offset in label_copy_fields.items():
        definition = _definition(source, f"_RTAPT-LD.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition
    for pt_name, rtapt_name in (
        ("PT-RET-DELTA", "RTAPT-RICH-DELTA"),
        ("PT-RET-REPLACE-START", "RTAPT-RICH-REPLACE-START"),
        ("PT-RET-REPLACE-CONTINUE", "RTAPT-RICH-REPLACE-CONTINUE"),
        ("PT-RET-LAYOUT-START", "RTAPT-RICH-LAYOUT-START"),
        ("PT-RET-LAYOUT-CONTINUE", "RTAPT-RICH-LAYOUT-CONTINUE"),
        ("PT-COMMIT", "RTAPT-COMMIT"),
        ("PT-COMMIT-AND-REVEAL", "RTAPT-COMMIT-AND-REVEAL"),
    ):
        assert re.search(
            rf"(?m)^{re.escape(pt_name)}\s+CONSTANT "
            rf"{re.escape(rtapt_name)}\s*$",
            source,
        )

    config = _definition(source, "RTAPT-CONFIG-INIT")
    init = _definition(source, "RTAPT-INIT")
    fini = _definition(source, "RTAPT-FINI")
    assert "_RTAPT-CONFIG-RANGES?" in config
    assert "_RTAPT-ENGINE-DISJOINT?" in init
    assert "PT-RETAINED-DISCOVER" in init
    assert "_RTAPT-E.OWNER-CAP" in init
    assert "_RTAPT-E.OP-CAP" in init
    assert init.index("_RTAPT-ENGINE-MAGIC = IF") < init.index(
        "PT-RETAINED-DISCOVER"
    )
    assert "_RTAPT-E.OWNER-USED" in fini
    assert "RTAPT-S-BUSY" in fini
    assert "_RTAPT-SESSION-ENDED?" in fini

    ranges = _definition(source, "_RTAPT-CONFIG-RANGES?")
    engine_ranges = _definition(source, "_RTAPT-ENGINE-DISJOINT?")
    assert ranges.count("MSPAN-OVERLAP?") == 10
    assert ranges.count("PT-STORAGE-DISJOINT?") == 4
    assert engine_ranges.count("MSPAN-OVERLAP?") == 5
    assert engine_ranges.count("PT-STORAGE-DISJOINT?") == 1
    assert "RTAPT-OWNER-SIZE MOD" in ranges
    assert "RTAPT-OP-SIZE MOD" in ranges
    assert "_RTAPT-CI-CU @ 7 AND" not in ranges

    validate = _definition(source, "_RTAPT-ENGINE-VALID?")
    quarantine_coherent = _definition(source, "_RTAPT-QUARANTINE-COHERENT?")
    stored_ranges = _definition(source, "_RTAPT-ENGINE-RANGES?")
    assert "_RTAPT-ENGINE-RANGES?" in validate
    assert validate.index("_RTAPT-ENGINE-MAGIC <>") < validate.index(
        "_RTAPT-ENGINE-RANGES?"
    )
    assert stored_ranges.count("PT-STORAGE-DISJOINT?") == 4
    assert stored_ranges.count("MSPAN-OVERLAP?") == 6
    assert "_RTAPT-OWNER-POINTER-OR-ZERO?" in validate
    assert "_RTAPT-ACTIVE-QUARANTINED" in validate
    assert "RTAPT-OWNER-ST-TOMBSTONE-DROPPING" in validate
    assert "_RTAPT-QUARANTINE-COHERENT?" in validate
    assert "_RTAPT-E.OWNER-CAP @ 0 ?DO" in quarantine_coherent
    assert "RTAPT-OWNER-ST-FREE" in quarantine_coherent
    assert "RTAPT-OWNER-ST-QUARANTINED" in quarantine_coherent
    assert "_RTAPT-QV-EXPECT @ <>" in quarantine_coherent

    quarantine = _definition(source, "_RTAPT-QUARANTINE-ALL")
    assert "_RTAPT-E.OWNER-CAP @ 0 ?DO" in quarantine
    assert "RTAPT-OWNER-ST-QUARANTINED" in quarantine
    assert "_RTAPT-E.QUEUE-HEAD" in quarantine
    assert "_RTAPT-E.QUEUE-TAIL" in quarantine
    assert "_RTAPT-ACTIVE-QUARANTINED" in quarantine
    assert "_RTAPT-O.NEXT" in quarantine

    tombstone = _definition(source, "_RTAPT-OWNER>TOMBSTONE")
    restore_tombstone = _definition(source, "_RTAPT-OWNER-RESTORE-TOMBSTONE")
    assert "RTAPT-OWNER-SIZE 0 FILL" in tombstone
    assert "_RTAPT-O.OWNER" in tombstone
    assert "_RTAPT-O.GENERATION" in tombstone
    assert "RTAPT-OWNER-ST-TOMBSTONE" in tombstone
    assert "_RTAPT-O.PRIOR-GENERATION" in restore_tombstone
    assert "RTAPT-OWNER-SIZE 0 FILL" in restore_tombstone

    owner_open = _definition(source, "RTAPT-OWNER-OPEN")
    owner_drop = _definition(source, "RTAPT-OWNER-DROP")
    send = _definition(source, "_RTAPT-OWNER-SEND")
    reconcile_open = _definition(source, "_RTAPT-RECONCILE-OPEN")
    reconcile_drop = _definition(source, "_RTAPT-RECONCILE-DROP")
    assert "_RTAPT-OWNER-ID-FIND" in owner_open
    assert "_RTAPT-OWNER-FREE-SLOT" in owner_open
    assert "RTAPT-OWNER-ST-TOMBSTONE" in owner_open
    assert "_RTAPT-OO-GEN @ U<" in owner_open
    assert "_RTAPT-OO-REUSED" in owner_open
    assert "_RTAPT-OO-PRIOR-GEN" in owner_open
    assert "RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED" in owner_open
    assert "_RTAPT-QUEUE-PUSH" in owner_open
    assert "RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED" in owner_drop
    assert "RTAPT-OWNER-ST-DROP-RETRY-QUEUED" in owner_drop
    assert "PT-TX-RESULT-INVALID" in owner_drop
    assert "PT-TX-RESULT-STALE" in owner_drop
    assert "PT-OWNER-OPEN" in send
    assert "PT-OWNER-DROP" in send
    assert "RTAPT-OWNER-ST-TOMBSTONE-OPENING" in send
    assert "RTAPT-OWNER-ST-TOMBSTONE-DROPPING" in send
    assert "PT-COMPLETE-RET PT-REQUEST-OWNER-OPEN" in reconcile_open
    assert "_RTAPT-OWNER-RESTORE-TOMBSTONE" in reconcile_open
    assert "_RTAPT-O.PRIOR-GENERATION" in reconcile_open
    assert "PT-COMPLETE-TX PT-REQUEST-OWNER-DROP" in reconcile_drop
    assert "_RTAPT-OWNER-CLEAR" not in reconcile_drop
    assert "PT-TX-RESULT-OK = IF" in reconcile_drop
    assert "RTAPT-OWNER-ST-TOMBSTONE" in reconcile_drop
    assert "RTAPT-OWNER-ST-DROPPING" in reconcile_drop
    assert reconcile_drop.count("_RTAPT-OWNER>TOMBSTONE") == 2
    assert "PT-TX-RESULT-ABORTED" in reconcile_drop
    assert "_RTAPT-QUARANTINE-ALL" in reconcile_drop

    step = _definition(source, "RTAPT-STEP")
    assert "_RTAPT-POLL-COMPLETION" in step
    assert step.count("_RTAPT-QUEUE-POP") == 1
    assert step.count("_RTAPT-OWNER-SEND") == 1
    assert step.index("_RTAPT-READY-STATUS") < step.index(
        "_RTAPT-E.QUEUE-HEAD @ 0= IF"
    )
    assert step.index("_RTAPT-E.QUEUE-HEAD @") < step.index("_RTAPT-OWNER-SEND")
    assert step.index("_RTAPT-OWNER-SEND") < step.index("_RTAPT-QUEUE-POP")
    assert step.index("_RTAPT-ACTIVE-NONE <> IF") < step.index(
        "_RTAPT-POLL-COMPLETION"
    )
    assert "_RTAPT-OWNER-ADMISSION-FAILED" in step
    assert "_RTAPT-ST-PT @ RTAPT-S-SESSION-LOST = IF" in step
    assert "_RTAPT-QUARANTINE-ALL" in step
    assert "_RTAPT-ACTIVE-QUARANTINED" in step
    assert "_RTAPT-QUARANTINE-ALL" in reconcile_open
    assert "PT-SERVICE" not in step

    captured = _definition(source, "_RTAPT-CAPTURED-BANKS?")
    ledgers = _definition(source, "_RTAPT-OWNER-LEDGERS?")
    target_count = _definition(source, "_RTAPT-TARGET-COUNT?")
    target_base = _definition(source, "_RTAPT-TARGET-BASE")
    rich_begin = _definition(source, "RTAPT-RICH-BEGIN")
    region_define = _definition(source, "RTAPT-REGION-DEFINE")
    label_define = _definition(source, "RTAPT-LABEL-DEFINE")
    label_body = _definition(source, "_RTAPT-LABEL-DEFINE-BODY")
    label_geometry = _definition(source, "_RTAPT-LABEL-GEOMETRY?")
    unorm32 = _definition(source, "_RTAPT-UNORM32")
    label_text_span = _definition(source, "_RTAPT-LABEL-TEXT-SPAN?")
    label_utf8 = _definition(source, "_RTAPT-LABEL-UTF8?")
    forbidden_byte = _definition(source, "_RTAPT-LABEL-FORBIDDEN-BYTE?")
    label_scrub = _definition(source, "_RTAPT-LABEL-SCRUB")
    pending_region = _definition(source, "_RTAPT-LABEL-REGION-PENDING?")
    rich_seal = _definition(source, "RTAPT-RICH-SEAL")
    rich_cancel = _definition(source, "RTAPT-RICH-CANCEL")
    candidate_preflight = _definition(source, "_RTAPT-CANDIDATE-PREFLIGHT?")
    prior_region = _definition(source, "_RTAPT-PRIOR-REGION?")
    label_shape = _definition(source, "_RTAPT-LABEL-COPY-SHAPE?")
    cell_begin = _definition(source, "RTAPT-CELL-BEGIN")
    cell_span = _definition(source, "RTAPT-CELL-SPAN-BEGIN")
    cell_write = _definition(source, "RTAPT-CELL-WRITE")
    cell_cursor = _definition(source, "RTAPT-CELL-CURSOR")
    cell_abort = _definition(source, "RTAPT-CELL-ABORT")
    abort_open = _definition(source, "_RTAPT-ABORT-OPEN")
    cell_commit = _definition(source, "RTAPT-CELL-COMMIT")
    commit_failed = _definition(source, "_RTAPT-COMMIT-FAILED")
    reconcile_output = _definition(source, "_RTAPT-RECONCILE-OUTPUT")
    apply_output = _definition(source, "_RTAPT-APPLY-OUTPUT")
    output_identity = _definition(source, "_RTAPT-OUTPUT-COMPLETION?")
    poll_completion = _definition(source, "_RTAPT-POLL-COMPLETION")
    storage_disjoint = _definition(source, "RTAPT-STORAGE-DISJOINT?")
    pending_clear = _definition(source, "_RTAPT-PENDING-CLEAR")
    send_label = _definition(source, "_RTAPT-SEND-LABEL")
    send_captured = _definition(source, "_RTAPT-SEND-CAPTURED")

    assert "_RTAPT-E.OP-CAP" in captured
    assert "_RTAPT-E.OP-COUNT @ _RTAPT-U32?" in captured
    assert "_RTAPT-E.COPY-U" in captured
    assert "_RTAPT-REGION-DEFINE-COPY-SIZE" in captured
    assert "_RTAPT-REGION-DEFINE-FRAME-BYTES" in captured
    assert "_RTAPT-OP-REGION-DEFINE" in captured
    assert "_RTAPT-OP-LABEL-DEFINE" in captured
    assert "_RTAPT-LABEL-DEFINE-COPY-FIXED" in captured
    assert "_RTAPT-LABEL-DEFINE-FRAME-FIXED" in captured
    assert "_RTAPT-ALIGN8?" in captured
    assert "_RTAPT-ZERO-SPAN?" in captured
    assert "_RTAPT-LD.TEXT-U" in captured
    assert "_RTAPT-E.RET-BYTES" in captured
    assert "_RTAPT-TARGET-COUNT?" in ledgers
    assert "_RTAPT-TARGET-BASE" in target_count
    assert "PT-RET-DELTA" in target_base
    assert "PT-RET-REPLACE-START" in target_base
    assert "PT-RET-LAYOUT-START" in target_base
    assert "_RTAPT-O.ACTIVE-REGIONS" in ledgers
    assert "_RTAPT-O.HIDDEN-REGIONS" in ledgers
    assert "_RTAPT-O.ACTIVE-OBJECTS" in ledgers
    assert "_RTAPT-O.HIDDEN-OBJECTS" in ledgers
    assert "_RTAPT-O.ACTIVE-UTF8" in ledgers
    assert "_RTAPT-O.HIDDEN-UTF8" in ledgers
    assert "_RTAPT-O.PENDING-OBJECTS" in ledgers
    assert "_RTAPT-O.PENDING-OBJECT-HIGH" in ledgers
    assert "_RTAPT-O.PENDING-UTF8" in ledgers
    assert ledgers.count("_RTAPT-TARGET-COUNT?") == 3
    for region_target, object_target in (
        ("ACTIVE-REGIONS", "ACTIVE-OBJECTS"),
        ("HIDDEN-REGIONS", "HIDDEN-OBJECTS"),
        ("PENDING-REGIONS", "PENDING-OBJECTS"),
    ):
        region_zero = f"_RTAPT-O.{region_target} @ 0="
        object_nonzero = f"_RTAPT-O.{object_target} @ 0<> AND"
        assert region_zero in ledgers
        assert object_nonzero in ledgers
        assert ledgers.index(region_zero) < ledgers.index(object_nonzero)
    for object_target, utf8_target in (
        ("ACTIVE-OBJECTS", "ACTIVE-UTF8"),
        ("HIDDEN-OBJECTS", "HIDDEN-UTF8"),
        ("PENDING-OBJECTS", "PENDING-UTF8"),
    ):
        object_zero = f"_RTAPT-O.{object_target} @ 0="
        utf8_nonzero = f"_RTAPT-O.{utf8_target} @ 0<> AND"
        assert object_zero in ledgers
        assert utf8_nonzero in ledgers
        assert ledgers.index(object_zero) < ledgers.index(utf8_nonzero)

    assert "PT-PRESENT-BEGIN" not in rich_begin
    assert "RTAPT-UPDATE-CAPTURING" in rich_begin
    assert "_RTAPT-E.OP-CAP" in region_define
    assert "_RTAPT-E.OP-COUNT @ 0xFFFFFFFF U<" in region_define
    assert "_RTAPT-E.COPY-U" in region_define
    assert "_RTAPT-O.REGION-HIGH" in region_define
    assert "_RTAPT-O.PENDING-REGION-HIGH" in region_define
    assert "_RTAPT-O.PENDING-REGIONS" in region_define
    assert not re.search(r"(?<!R)\bPT-REGION-DEFINE\b", region_define)

    # LABEL capture accepts neutral cell geometry, owns a padded retry copy,
    # and accounts only the exact typed PT frame bytes.  No PT call occurs
    # until the already-sealed candidate is serialized.
    assert "root-height root-width z visible rgba" in label_define
    assert "['] _RTAPT-LABEL-DEFINE-BODY CATCH" in label_define
    assert label_define.index("CATCH") < label_define.index(
        "_RTAPT-LABEL-SCRUB"
    )
    assert not re.search(r"\bPT-LABEL-DEFINE\b", label_define)
    assert not re.search(r"\bPT-LABEL-DEFINE\b", label_body)
    assert "_RTAPT-LABEL-FIELDS?" in label_body
    assert "_RTAPT-LABEL-TEXT-SPAN?" in label_body
    assert "_RTAPT-LABEL-REGION-PENDING?" in label_body
    assert "_RTAPT-OBJECT-BASE" in label_body
    assert "_RTAPT-UTF8-BASE" in label_body
    assert "_RTAPT-O.PENDING-OBJECTS" in label_body
    assert "_RTAPT-O.PENDING-OBJECT-HIGH" in label_body
    assert "_RTAPT-O.PENDING-UTF8" in label_body
    assert "_RTAPT-LABEL-DEFINE-COPY-FIXED _RTAPT-UADD?" in label_body
    assert "_RTAPT-ALIGN8?" in label_body
    assert "_RTAPT-LABEL-DEFINE-FRAME-FIXED _RTAPT-UADD?" in label_body
    assert "_RTAPT-LD-COPY @ _RTAPT-LD-COPY-U @ 0 FILL" in label_body
    assert "_RTAPT-LD-TEXT-U @ IF" in label_body
    assert "_RTAPT-LD-TEXT-U @ MOVE" in label_body
    fields = label_body.index("_RTAPT-LABEL-FIELDS?")
    text_span = label_body.index("_RTAPT-LABEL-TEXT-SPAN?")
    ready = label_body.index("_RTAPT-READY-STATUS")
    limits = label_body.index("_RTAPT-LABEL-LIMITS")
    utf8 = label_body.index("_RTAPT-LABEL-UTF8?")
    capture = label_body.index("_RTAPT-OP-LABEL-DEFINE")
    assert fields < text_span < ready < limits < utf8 < capture
    assert label_body.index("_RTAPT-LD-NEXT-RET !") < label_body.index(
        "_RTAPT-OP-LABEL-DEFINE"
    )
    assert label_body.index("0 FILL") < label_body.index("MOVE")

    # Projection is rooted in integer UIDL geometry.  Visible zero-area or
    # fully off-root labels fail, while invisible labels are still given a
    # legal nearest-cell APT rectangle.
    assert "_RTAPT-LD-ROOT-H" in label_geometry
    assert "_RTAPT-LD-ROOT-W" in label_geometry
    assert "_RTAPT-LD-VISIBLE @ IF" in label_geometry
    visible_guard = label_geometry.index("_RTAPT-LD-VISIBLE @ IF")
    clamp = label_geometry.index("_RTAPT-LD-COL @ 0 MAX")
    assert visible_guard < clamp
    assert "_RTAPT-LD-HEIGHT @ 0=" in label_geometry
    assert "_RTAPT-LD-WIDTH @ 0=" in label_geometry
    assert "_RTAPT-LD-LEFT @ 1+ MAX" in label_geometry
    assert "_RTAPT-LD-TOP @ 1+ MAX" in label_geometry
    assert label_geometry.count("_RTAPT-UNORM32") == 4
    assert "_RTAPT-LD-LEFT @ _RTAPT-LD-RIGHT @ U<" in label_geometry
    assert "_RTAPT-LD-TOP @ _RTAPT-LD-BOTTOM @ U<" in label_geometry
    assert "_RTAPT-UN-B @ 0= IF 0 EXIT THEN" in unorm32
    assert "_RTAPT-UN-B @ _RTAPT-UN-R @ = IF 0xFFFFFFFF EXIT THEN" in unorm32
    assert "0xFFFFFFFF _RTAPT-UN-R @ /MOD" in unorm32

    # UTF-8 is validated locally before the source is copied: scalar-only,
    # with the APT LABEL NUL/LF/CR exclusions and no borrowed-pointer residue.
    assert "DUP 0=" in forbidden_byte
    assert "OVER 10 =" in forbidden_byte
    assert "SWAP 13 =" in forbidden_byte
    for fragment in (
        "0xC2 >=",
        "0xDF <=",
        "0xE0 =",
        "0xED =",
        "0xF0 =",
        "0xF4 =",
        "_RTAPT-LUTF8-CONT?",
    ):
        assert fragment in label_utf8
    assert "_RTAPT-BYTE-SPAN-DISJOINT?" in label_text_span
    assert "_RTAPT-LABEL-UTF8?" not in label_text_span
    assert (
        "_RTAPT-LD-TEXT-U @ 0= IF _RTAPT-LD-TEXT-A @ 0= EXIT THEN"
        in label_text_span
    )
    assert "_RTAPT-LABEL-FORBIDDEN-BYTE?" in label_utf8
    assert "_RTAPT-LABEL-UTF8?" in label_shape
    for scratch in (
        "_RTAPT-LD-TEXT-A",
        "_RTAPT-LD-TEXT-U",
        "_RTAPT-LU-A",
        "_RTAPT-LU-U",
        "_RTAPT-BSD-A",
        "_RTAPT-BSD-U",
        "_RTAPT-BSD-E",
    ):
        assert f"0 {scratch} !" in label_scrub

    assert "_RTAPT-MODE-DISPOSITION?" in rich_seal
    assert "RTAPT-UPDATE-SEALED" in rich_seal
    assert "_RTAPT-CANDIDATE-DISCARD" in rich_cancel

    assert "_RTAPT-REGION-COPY-SHAPE?" in candidate_preflight
    assert "_RTAPT-LABEL-COPY-SHAPE?" in candidate_preflight
    assert "_RTAPT-OP-REGION-DEFINE" in candidate_preflight
    assert "_RTAPT-OP-LABEL-DEFINE" in candidate_preflight
    assert "_RTAPT-O.REGION-HIGH" in candidate_preflight
    assert "_RTAPT-O.PENDING-REGIONS" in candidate_preflight
    assert "_RTAPT-O.PENDING-OBJECTS" in candidate_preflight
    assert "_RTAPT-O.PENDING-OBJECT-HIGH" in candidate_preflight
    assert "_RTAPT-O.PENDING-UTF8" in candidate_preflight
    assert "_RTAPT-PRIOR-REGION?" in candidate_preflight
    assert "_RTAPT-LD.OBJECT" in candidate_preflight
    assert "_RTAPT-LD.TEXT-U" in candidate_preflight
    assert "_RTAPT-PF-BASE-RHIGH" not in source
    assert "_RTAPT-REGION-TARGET-HIGH" not in source
    assert "_RTAPT-OBJECT-TARGET-HIGH" not in source

    fields_validator = _definition(source, "_RTAPT-LABEL-FIELDS?")
    assert "_RTAPT-LD-PARENT @ IF 0 EXIT THEN" in fields_validator
    assert "_RTAPT-LD.PARENT @ IF 0 EXIT THEN" in label_shape
    assert "_RTAPT-E.OP-COUNT @ 0 ?DO" in pending_region
    assert "_RTAPT-OP-REGION-DEFINE" in pending_region
    for identity in ("OWNER", "GENERATION", "REGION"):
        assert f"_RTAPT-RD.{identity}" in pending_region
    assert "_RTAPT-PRR-I @ 0 ?DO" in prior_region
    assert "_RTAPT-OP-REGION-DEFINE" in prior_region
    for identity in ("OWNER", "GENERATION", "REGION"):
        assert f"_RTAPT-RD.{identity}" in prior_region
        assert f"_RTAPT-LD.{identity}" in prior_region
    assert cell_begin.count("PT-PRESENT-BEGIN") == 2
    assert cell_begin.index("_RTAPT-CANDIDATE-PREFLIGHT?") < cell_begin.index(
        "PT-PRESENT-BEGIN"
    )
    assert "PT-RET-NONE" in cell_begin
    assert "RTAPT-COUPLING-CELL" in cell_begin
    assert "RTAPT-COUPLING-RETAINED" in cell_begin
    assert "RTAPT-UPDATE-CELL-OPEN" in cell_begin
    assert "PT-SPAN-BEGIN" in cell_span
    assert "PT-CELL" in cell_write
    assert "PT-CURSOR" in cell_cursor
    assert "_RTAPT-ABORT-OPEN" in cell_abort

    assert "_RTAPT-SEND-CAPTURED" in cell_commit
    assert cell_commit.index("_RTAPT-CANDIDATE-PREFLIGHT?") < cell_commit.index(
        "_RTAPT-SEND-CAPTURED"
    )
    assert "PT-PRESENT-COMMIT" in cell_commit
    assert "_RTAPT-COMMIT-FAILED" in cell_commit
    assert "RTAPT-UPDATE-AWAITING" in cell_commit
    assert "_RTAPT-ACTIVE-OUTPUT" in cell_commit
    for field in label_copy_fields:
        assert f"_RTAPT-LD.{field}" in send_label
    assert "24 RSHIFT 0xFF AND" in send_label
    assert "16 RSHIFT 0xFF AND" in send_label
    assert "8 RSHIFT 0xFF AND" in send_label
    assert "ELSE 0 0 THEN" in send_label
    assert "PT-LABEL-DEFINE _RTAPT-PT>STATUS" in send_label
    assert "_RTAPT-OP-REGION-DEFINE" in send_captured
    assert "_RTAPT-SEND-REGION" in send_captured
    assert "_RTAPT-OP-LABEL-DEFINE" in send_captured
    assert "_RTAPT-SEND-LABEL" in send_captured
    assert "PT-TX-ABORT" in abort_open
    assert "_RTAPT-WIRE-REWIND" in abort_open
    assert "_RTAPT-ABORT-OPEN" in commit_failed
    assert "_RTAPT-CANDIDATE-DISCARD" in reconcile_output
    assert "_RTAPT-WIRE-REWIND" in reconcile_output
    assert "RTAPT-COUPLING-RETAINED" in reconcile_output
    assert "_RTAPT-QUARANTINE-ALL" in reconcile_output
    assert "PT-REQUEST-PRESENT-COMMIT" in output_identity
    assert "PT-COMPLETION-TXID@ 0<>" in output_identity
    assert "PT-COMPLETION-DETAIL@ 0=" in output_identity
    assert "_RTAPT-APPLY-OUTPUT" in reconcile_output
    assert "PT-RET-REPLACE-START" in apply_output
    assert "PT-RET-LAYOUT-START" in apply_output
    assert "PT-COMMIT-AND-REVEAL" in apply_output
    for ledger in (
        "ACTIVE-OBJECTS",
        "HIDDEN-OBJECTS",
        "OBJECT-HIGH",
        "ACTIVE-UTF8",
        "HIDDEN-UTF8",
        "PENDING-OBJECTS",
        "PENDING-OBJECT-HIGH",
        "PENDING-UTF8",
    ):
        assert f"_RTAPT-O.{ledger}" in apply_output
    for pending in (
        "PENDING-OBJECTS",
        "PENDING-OBJECT-HIGH",
        "PENDING-UTF8",
    ):
        assert f"_RTAPT-O.{pending}" in pending_clear
        assert f"_RTAPT-O.{pending}" in quarantine
    assert "_RTAPT-ACTIVE-OUTPUT" in poll_completion

    assert "RTAPT-USES-SESSION?" in source
    assert "RTAPT-SESSION@" not in source
    assert "PT-STORAGE-DISJOINT?" in storage_disjoint
    assert storage_disjoint.count("MSPAN-OVERLAP?") == 4
    assert "PT-SERVICE" not in source.replace(
        "It never calls PT-SERVICE and cannot consume input events.", ""
    )

    # PT's public surface is the engine's lower boundary.  Depending on a PT
    # private word would duplicate or bypass its wire/session authority.
    assert not re.search(r"(?<!RTAPT)\b_PT-", source)


def test_rich_terminal_engine_copies_one_typed_negotiated_limits_snapshot() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    expected_fields = {
        "FEATURES": 0,
        "OWNER-RECORDS": 8,
        "LIVE-OWNERS": 16,
        "REGIONS": 24,
        "RESOURCES": 32,
        "OBJECTS": 40,
        "SERIES": 48,
        "OPS": 56,
        "UPDATE-BYTES": 64,
        "CHUNK-BYTES": 72,
        "RESOURCE-BYTES": 80,
        "IMAGE-WIDTH": 88,
        "IMAGE-HEIGHT": 96,
        "PATH-POINTS": 104,
        "LABEL-BYTES": 112,
        "UTF8-BYTES": 120,
        "SAMPLES-APPEND": 128,
        "SERIES-HISTORY": 136,
        "SAMPLE-SLOTS": 144,
        "MIN-INTERVAL-US": 152,
    }
    for field, offset in expected_fields.items():
        definition = _definition(source, f"_RTAPT-L.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition

    limits = _definition(source, "RTAPT-LIMITS@")
    ready = limits.index("_RTAPT-READY-STATUS")
    caps = limits.index("PT-RETAINED-CAPS@", ready)
    formats = limits.index("PT-RETAINED-FORMATS@", caps)
    sizes = limits.index("_RTAPT-LS-CAPS-U @ 64 <>", formats)
    copy = limits.index("_RTAPT-LIMITS-COPY", sizes)
    validate = limits.index("RTAPT-LIMITS-VALID?", copy)
    scrub = limits.rindex("_RTAPT-LIMITS-SCRUB")
    assert ready < caps < formats < sizes < copy < validate < scrub
    assert "DUP RTAPT-S-OK <> IF" in limits
    assert "0 SWAP _RTAPT-LIMITS-SCRUB EXIT" in limits
    assert "RTAPT-LIMITS-SIZE 0 FILL" in limits

    copied = _definition(source, "_RTAPT-LIMITS-COPY")
    assert "_RTAPT-E.LIMITS" in copied
    assert "RTAPT-LIMITS-SIZE 0 FILL" in copied
    for field in expected_fields:
        assert f"_RTAPT-L.{field} !" in copied
    for caps_offset in (8, 16, 20, 24, 28, 32, 36, 40, 44, 48, 56):
        assert f"_RTAPT-LS-CAPS-A @ {caps_offset} +" in copied
    for formats_offset in (12, 16, 20, 24, 28, 32, 36, 40, 48):
        assert f"_RTAPT-LS-FORMATS-A @ {formats_offset} +" in copied
    assert copied.count("_RTAPT-LE64@") == 5

    valid = _definition(source, "_RTAPT-LIMITS-VALID-BODY")
    for relationship in (
        "_RTAPT-FEATURE-MASK INVERT AND",
        "RTAPT-F-CORE AND 0=",
        "RTAPT-F-SERIES AND SWAP RTAPT-F-INSTRUMENT",
        "_RTAPT-L.LIVE-OWNERS @",
        "_RTAPT-L.OWNER-RECORDS @ U>",
        "_RTAPT-L.UTF8-BYTES @",
        "_RTAPT-L.LABEL-BYTES @ U<",
        "_RTAPT-L.SAMPLES-APPEND @",
        "_RTAPT-L.SERIES-HISTORY @ U>",
        "_RTAPT-L.SAMPLE-SLOTS @ U>",
        "_RTAPT-L.IMAGE-HEIGHT @ _RTAPT-UMUL?",
        "_RTAPT-L.RESOURCE-BYTES @ U>",
        "_RTAPT-L.PATH-POINTS @ 8 _RTAPT-UMUL?",
        "_RTAPT-L.LABEL-BYTES @ 304 _RTAPT-UADD?",
        "_RTAPT-L.SAMPLES-APPEND @ 16 _RTAPT-UMUL?",
        "_RTAPT-LIMIT-FLOOR?",
    ):
        assert relationship in valid
    assert "_RTAPT-L.UPDATE-BYTES @ U> 0=" in _definition(
        source, "_RTAPT-LIMIT-FLOOR?"
    )

    pointer_scrub = _definition(source, "_RTAPT-LIMITS-SCRUB")
    for pointer in (
        "_RTAPT-LS-E",
        "_RTAPT-LS-CAPS-A",
        "_RTAPT-LS-CAPS-U",
        "_RTAPT-LS-FORMATS-A",
        "_RTAPT-LS-FORMATS-U",
    ):
        assert f"0 {pointer} !" in pointer_scrub


def test_label_geometry_projects_integer_cell_edges_exactly() -> None:
    assert _project_label(
        2, 10, 3, 20, 24, 80, visible=True
    ) == (0x1FFFFFFF, 0x15555555, 0x5FFFFFFF, 0x35555555)

    # A partially off-root visible label is clipped before normalization.
    assert _project_label(
        -2, -3, 4, 7, 24, 80, visible=True
    ) == (0, 0, 0x0CCCCCCC, 0x15555555)

    assert _unorm32(0, 80) == 0
    assert _unorm32(80, 80) == U32_MAX


def test_invisible_empty_and_offroot_geometry_stays_wire_legal() -> None:
    first_cell = (0, 0, 0x03333333, 0x0AAAAAAA)
    assert _project_label(0, 0, 0, 0, 24, 80, visible=False) == first_cell
    assert _project_label(-999, -999, 0, 0, 24, 80, visible=False) == first_cell
    assert _project_label(
        999, 999, 0, 0, 24, 80, visible=False
    ) == (0xFCCCCCCB, 0xF5555554, U32_MAX, U32_MAX)

    # The same degenerate/off-root inputs cannot truthfully be made visible.
    assert _project_label(0, 0, 0, 1, 24, 80, visible=True) is None
    assert _project_label(24, 0, 1, 1, 24, 80, visible=True) is None
    assert _project_label(0, 80, 1, 1, 24, 80, visible=True) is None


def test_label_region_reference_requires_an_exact_earlier_candidate_region() -> None:
    operations = [
        ("region", 7, 3, 2),
        ("region", 7, 3, 100),
        ("label", 7, 3, 100),
    ]

    # Sparse IDs stay legal, but high-water membership is not fabricated.
    assert _has_prior_region(operations, 2, 7, 3, 100)
    assert not _has_prior_region(operations, 2, 7, 3, 50)
    assert not _has_prior_region(operations, 2, 8, 3, 100)
    assert not _has_prior_region(operations, 2, 7, 4, 100)

    # Replacement and delta candidates can both use a region they define in
    # that candidate.  A committed-only region remains conservatively
    # unsupported until an exact persistent identity/type ledger exists.
    replacement = [("region", 7, 3, 42), ("label", 7, 3, 42)]
    delta = [("region", 7, 3, 101), ("label", 7, 3, 101)]
    assert _has_prior_region(replacement, 1, 7, 3, 42)
    assert _has_prior_region(delta, 1, 7, 3, 101)
    assert not _has_prior_region([("label", 7, 3, 10)], 0, 7, 3, 10)


def test_mixed_retry_copy_stride_and_frame_accounting_are_exact() -> None:
    ascii_text = b"abc"
    scalar_text = "☃".encode("utf-8")
    ascii_copy = _label_retry_copy(ascii_text)
    scalar_copy = _label_retry_copy(scalar_text)

    assert len(ascii_copy) == 136
    assert ascii_copy[LABEL_COPY_FIXED : LABEL_COPY_FIXED + 3] == ascii_text
    assert ascii_copy[LABEL_COPY_FIXED + 3 :] == b"\x00" * 5
    assert len(scalar_copy) == 136
    assert scalar_copy[LABEL_COPY_FIXED : LABEL_COPY_FIXED + 3] == scalar_text
    assert scalar_copy[LABEL_COPY_FIXED + 3 :] == b"\x00" * 5

    # REGION followed by two LABEL records uses each record's aligned retry
    # stride, while PRESENT_BEGIN accounts the unpadded typed wire frames.
    offsets = (0, REGION_COPY_BYTES, REGION_COPY_BYTES + len(ascii_copy))
    assert offsets == (0, 72, 208)
    assert REGION_COPY_BYTES + len(ascii_copy) + len(scalar_copy) == 344
    assert _label_frame_bytes(ascii_text) == 123
    assert _label_frame_bytes(scalar_text) == 123
    assert (
        REGION_FRAME_BYTES
        + _label_frame_bytes(ascii_text)
        + _label_frame_bytes(scalar_text)
        == 334
    )

    assert len(_label_retry_copy(b"")) == LABEL_COPY_FIXED
    assert _label_frame_bytes(b"") == LABEL_FRAME_FIXED
