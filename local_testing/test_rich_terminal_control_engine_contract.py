"""Focused structural locks for the semantic CONTROL engine seam."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / "akashic/tui/rich-terminal/apt1-engine.f"


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions)


def test_apt1_control_capability_extends_fixed_records_explicitly() -> None:
    source = _text(PROVIDER)

    for declaration in (
        "64 CONSTANT RTAPT-F-CONTROLS",
        "0x100 CONSTANT _RTAPT-PT-F-CONTROLS",
        "168 CONSTANT RTAPT-LIMITS-SIZE",
        "248 CONSTANT RTAPT-OWNER-SIZE",
        "504 CONSTANT RTAPT-ENGINE-SIZE",
        ": _RTAPT-L.OUTBOUND-PAYLOAD ( l -- a ) 160 + ;",
        ": _RTAPT-O.ACTIVE-CONTROLS ( o -- a ) 208 + ;",
        ": _RTAPT-O.HIDDEN-CONTROLS ( o -- a ) 216 + ;",
        ": _RTAPT-O.CONTROL-HIGH ( o -- a ) 224 + ;",
        ": _RTAPT-O.PENDING-CONTROLS ( o -- a ) 232 + ;",
        ": _RTAPT-O.PENDING-CONTROL-HIGH ( o -- a ) 240 + ;",
        ": _RTAPT-E.LIMITS     ( e -- a ) 336 + ;",
    ):
        assert declaration in source

    limits_copy = _word(source, "_RTAPT-LIMITS-COPY")
    assert "0x3F AND" in limits_copy
    assert "_RTAPT-PT-F-CONTROLS AND IF RTAPT-F-CONTROLS OR" in limits_copy
    assert "PT-OUTBOUND-MAX-PAYLOAD@" in limits_copy
    assert "_RTAPT-L.OUTBOUND-PAYLOAD !" in limits_copy


def test_apt1_control_preflight_consumes_aggregates_without_item_walk() -> None:
    source = _text(PROVIDER)
    public = _word(source, "RTAPT-CONTROL-PREFLIGHT")
    body = _word(source, "_RTAPT-CONTROL-PREFLIGHT-BODY")
    arithmetic = _word(source, "_RTAPT-CONTROL-PREFLIGHT-ARITHMETIC?")

    assert "( aggregate scalars engine -- status )" in public
    assert "ITEMS-A" not in public + body + arithmetic
    assert "?DO" not in public + body + arithmetic
    assert "_RTAPT-CONTROL-COPY-FIXED _RTAPT-UMUL?" in arithmetic
    assert "_RTAPT-CONTROL-FRAME-FIXED _RTAPT-UMUL?" in arithmetic
    assert "_RTAPT-UPDATE-ENVELOPE-FRAME-BYTES" in arithmetic
    assert "_RTAPT-REGION-DEFINE-FRAME-BYTES" in arithmetic
    assert "_RTAPT-CPF-MAX-ITEM-TEXT @ 80 _RTAPT-UADD?" in body
    assert "_RTAPT-LPF-OWNER-ADMISSION" in body


def test_apt1_control_capture_orders_authority_before_mutable_capacity() -> None:
    source = _text(PROVIDER)
    common = _word(source, "_RTAPT-CONTROL-COMMON?")
    capture = _word(source, "_RTAPT-CONTROL-CAPTURE")

    _ordered(
        common,
        "_RTAPT-ENGINE-STORAGE?",
        "_RTAPT-CONTROL-SHAPE?",
        "_RTAPT-CONTROL-TEXT-SPANS?",
        "_RTAPT-CONTROL-TEXT?",
        "_RTAPT-READY-STATUS",
        "_RTAPT-CAPTURE-READY?",
        "_RTAPT-CONTROL-CAPACITY?",
        "_RTAPT-CONTROL-LIMITS",
    )
    assert "RTAPT-OP-SIZE 0 FILL" in capture
    assert "_RTAPT-CD-COPY-U @ 0 FILL" in capture
    assert capture.count("MOVE") == 2
    _ordered(
        capture,
        "_RTAPT-CD-LABEL-A @",
        "MOVE",
        "_RTAPT-CONTROL-COPY-TEXT?",
        "_RTAPT-E.COPY-USED !",
        "_RTAPT-E.OP-COUNT +!",
    )


def test_glyph_and_control_definitions_share_object_and_utf8_quotas() -> None:
    source = _text(PROVIDER)
    object_base = _word(source, "_RTAPT-SHARED-OBJECT-BASE?")
    glyph_define = _word(source, "_RTAPT-GLYPH-RUN-DEFINE-BODY")
    control_quota = _word(source, "_RTAPT-CONTROL-SHARED-QUOTA?")
    control_utf8 = _word(source, "_RTAPT-CONTROL-UTF8-QUOTA?")

    for field in (
        "_RTAPT-O.ACTIVE-OBJECTS",
        "_RTAPT-O.ACTIVE-CONTROLS",
        "_RTAPT-O.HIDDEN-OBJECTS",
        "_RTAPT-O.HIDDEN-CONTROLS",
        "_RTAPT-TARGET-BASE",
    ):
        assert field in object_base
        assert field in control_quota
    assert "_RTAPT-O.PENDING-OBJECTS" in glyph_define
    assert "_RTAPT-O.PENDING-CONTROLS" in glyph_define
    assert "_RTAPT-O.PENDING-OBJECTS" in control_quota
    assert "_RTAPT-O.PENDING-CONTROLS" in control_quota
    assert "_RTAPT-TARGET-BASE" in control_utf8
    assert "_RTAPT-O.PENDING-UTF8" in control_utf8


def test_control_delta_replacement_does_not_fabricate_quota_recovery() -> None:
    source = _text(PROVIDER)
    replace = _word(source, "_RTAPT-CONTROL-REPLACE-BODY")
    drop = _word(source, "_RTAPT-CONTROL-DROP-BODY")

    assert "PT-RET-DELTA <>" in replace
    assert "0 _RTAPT-CONTROL-SHARED-QUOTA?" in replace
    assert "0 _RTAPT-CONTROL-UTF8-QUOTA?" in replace
    assert "_RTAPT-O.PENDING-UTF8 !" not in replace
    assert "_RTAPT-O.ACTIVE-CONTROLS" in drop
    assert "_RTAPT-O.ACTIVE-CONTROLS !" not in drop
    assert "_RTAPT-O.ACTIVE-UTF8 !" not in drop


def test_final_preflight_rechecks_the_complete_define_graph_once() -> None:
    source = _text(PROVIDER)
    next_id = _word(source, "_RTAPT-PF-CONTROL-NEXT-ID?")
    menu = _word(source, "_RTAPT-PF-CONTROL-MENU?")
    item = _word(source, "_RTAPT-PF-CONTROL-ITEM?")
    graph = _word(source, "_RTAPT-PF-CONTROL-DEFINE-GRAPH?")
    candidate = _word(source, "_RTAPT-CANDIDATE-PREFLIGHT?")

    assert "_RTAPT-PF-CCOUNT @ 0= IF" in next_id
    assert "_RTAPT-PF-CHIGH @ U> 0=" in next_id
    assert "_RTAPT-PF-CHIGH @ 1 _RTAPT-UADD?" in next_id
    assert "_RTAPT-PF-CBAR-ID @ <>" in menu
    assert "_RTAPT-PF-COPEN-MENU" in menu
    assert "_RTAPT-PF-CSELECTED-MENU" in menu
    assert "_RTAPT-PF-CMENU-FIRST @ U<" in item
    assert "_RTAPT-PF-CMENU-LAST @ U>" in item
    assert "_RTAPT-PF-CPARENT @ U<" in item
    assert "_RTAPT-PF-CSELECTED-ITEM-PARENT" in item
    assert "RTAPT-CONTROL-MENUBAR" in graph
    assert "RTAPT-CONTROL-MENU" in graph
    assert "_RTAPT-PF-CONTROL-ITEM?" in graph
    assert "PT-RET-REPLACE-START <>" in candidate
    assert "_RTAPT-PF-CONTROL-DEFINE-GRAPH?" in candidate
    assert "_RTAPT-PF-CBAR-COUNT @ 1 <>" in candidate
    assert "_RTAPT-O.PENDING-CONTROL-HIGH" in candidate


def test_captured_controls_are_revalidated_and_serialized_explicitly() -> None:
    source = _text(PROVIDER)
    banks = _word(source, "_RTAPT-CAPTURED-BANKS?")
    candidate = _word(source, "_RTAPT-CANDIDATE-PREFLIGHT?")
    sender = _word(source, "_RTAPT-SEND-CONTROL")

    assert "_RTAPT-CONTROL-COPY-FIXED" in banks
    assert "_RTAPT-CONTROL-DROP-COPY-SIZE" in banks
    assert "_RTAPT-CONTROL-COPY-SHAPE?" in candidate
    assert "_RTAPT-O.PENDING-CONTROLS" in candidate
    assert "_RTAPT-O.PENDING-CONTROL-HIGH" in candidate
    assert "_RTAPT-O.PENDING-UTF8" in candidate
    _ordered(
        sender,
        "_RTAPT-CD.OWNER",
        "_RTAPT-CD.GENERATION",
        "_RTAPT-CD.CONTROL",
        "_RTAPT-CD.KIND",
        "_RTAPT-CD.STATE",
        "_RTAPT-CD.Z",
        "_RTAPT-CD.REGION",
        "_RTAPT-CD.PARENT",
        "_RTAPT-CD.ORDER",
        "_RTAPT-CD.LEFT",
        "_RTAPT-CD.TOP",
        "_RTAPT-CD.RIGHT",
        "_RTAPT-CD.BOTTOM",
        "_RTAPT-CD.LABEL-U",
        "_RTAPT-CD.SHORTCUT-U",
        "PT-CONTROL-REPLACE ELSE PT-CONTROL-DEFINE",
    )
