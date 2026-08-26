"""Seconds-only locks for the neutral retained-engine facade and APT-1 bridge."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FACADE = ROOT / "akashic" / "tui" / "rich-terminal" / "engine.f"
BRIDGE = ROOT / "akashic" / "tui" / "rich-terminal" / "engine-apt1.f"


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def _code_without_comments(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def test_facade_is_backend_neutral_immutable_and_caller_owned() -> None:
    source = FACADE.read_text(encoding="utf-8")
    code = _code_without_comments(source)

    assert "PROVIDED akashic-tui-rte1" in code
    assert re.findall(r"(?m)^REQUIRE\s+(\S+)\s*$", code) == [
        "../../utils/memory-span.f"
    ]
    for forbidden in (
        "PT-",
        "_PT-",
        "RTAPT-",
        "_RTAPT-",
        "APTSCB-",
        "RTERM-",
        "AHOST-",
        "UCTX-",
        "DESK-",
        "rich-terminal.f",
        "apt1-engine.f",
    ):
        assert forbidden not in code
    assert not re.search(
        r"(?m)(?:^|[ \t])(?:CREATE|ALLOT|ALLOCATE|FREE|RESIZE|XBUF)"
        r"(?=[ \t]|$)",
        code,
    )

    assert "4 CONSTANT _RTE-ABI" in code
    assert '0x5254454641434134 CONSTANT _RTE-MAGIC' in code
    assert "136 CONSTANT RTE-FACADE-SIZE" in code
    assert "160 CONSTANT RTE-LIMITS-SIZE" in code
    assert "_RTE-F.CONTEXT" in _definition(source, "RTE-VALID?")
    valid = _definition(source, "RTE-VALID?")
    for callback in (
        "DISJOINT",
        "STATUS",
        "OWNER-OPEN",
        "OWNER-STATE",
        "RETAINED-BEGIN",
        "REGION-DEF",
        "RETAINED-SEAL",
        "RETAINED-CANCEL",
        "OWNER-DROP",
        "LIMITS",
        "LABEL-DEF",
    ):
        assert f"_RTE-F.{callback}-XT @ 0=" in valid
    assert "_RTE-F.LABEL-PREFLIGHT-XT @ 0<>" in valid

    disjoint = _definition(source, "RTE-STORAGE-DISJOINT?")
    assert disjoint.index("RTE-VALID?") < disjoint.index("MSPAN-OVERLAP?")
    assert disjoint.index("MSPAN-OVERLAP?") < disjoint.index("EXECUTE")
    assert "_RTE-F.CONTEXT @" in disjoint
    assert "_RTE-F.DISJOINT-XT @ EXECUTE" in disjoint
    assert "DUP _RTE-BOOL? 0= IF DROP 0 THEN" in disjoint
    assert "3DROP" not in code


def test_facade_dispatch_validates_neutral_arguments_and_provider_results() -> None:
    source = FACADE.read_text(encoding="utf-8")

    public_signatures = {
        "RTE-FACADE-BYTES": "( -- bytes )",
        "RTE-STATUS-VALID?": "( status -- flag )",
        "RTE-OWNER-STATE-VALID?": "( owner-state -- flag )",
        "RTE-VALID?": "( facade -- flag )",
        "RTE-STORAGE-DISJOINT?": "( a u facade -- flag )",
        "RTE-STATUS@": "( facade -- status )",
        "RTE-LIMITS-BYTES": "( -- bytes )",
        "RTE-LIMITS-VALID?": "( limits -- flag )",
        "RTE-LIMITS@": "( limits facade -- status )",
        "RTE-LABEL-BYTES": "( -- bytes )",
        "RTE-LABEL-VALID?": "( label -- flag )",
        "RTE-LABEL-DEFINE": "( label facade -- status )",
        "RTE-LABEL-PLAN-BYTES": "( -- bytes )",
        "RTE-LABEL-PLAN-ITEM-BYTES": "( -- bytes )",
        "RTE-LABEL-PLAN-VALID?": "( plan -- flag )",
        "RTE-LABEL-PREFLIGHT": "( plan facade -- status )",
        "RTE-RETAINED-BEGIN": "( retained-mode facade -- status )",
        "RTE-RETAINED-SEAL": "( disposition facade -- status )",
        "RTE-RETAINED-CANCEL": "( facade -- status )",
        "RTE-OWNER-DROP": "( owner generation facade -- status )",
    }
    for name, signature in public_signatures.items():
        assert signature in _definition(source, name).splitlines()[0]

    owner_state = _definition(source, "RTE-OWNER-STATE@")
    assert "RTE-STATUS-VALID?" in owner_state
    assert "RTE-OWNER-STATE-VALID?" in owner_state
    assert "RTE-OWNER-ST-FREE RTE-S-INVALID" in owner_state
    assert "_RTE-MODE?" in _definition(source, "RTE-RETAINED-BEGIN")
    assert "_RTE-DISPOSITION?" in _definition(source, "RTE-RETAINED-SEAL")

    for name in (
        "RTE-STATUS@",
        "RTE-LIMITS@",
        "RTE-OWNER-OPEN",
        "RTE-OWNER-STATE@",
        "RTE-RETAINED-BEGIN",
        "RTE-REGION-DEFINE",
        "RTE-LABEL-DEFINE",
        "RTE-LABEL-PREFLIGHT",
        "RTE-RETAINED-SEAL",
        "RTE-RETAINED-CANCEL",
        "RTE-OWNER-DROP",
    ):
        dispatch = _definition(source, name)
        assert "RTE-VALID?" in dispatch
        assert "_RTE-F.CONTEXT @" in dispatch
        assert "EXECUTE" in dispatch


def test_apt1_bridge_is_the_only_concrete_mapping_and_is_fail_before_mutation() -> None:
    facade = _code_without_comments(FACADE.read_text(encoding="utf-8"))
    source = BRIDGE.read_text(encoding="utf-8")
    code = _code_without_comments(source)

    assert "PROVIDED akashic-tui-rtapte1" in code
    assert re.findall(r"(?m)^REQUIRE\s+(\S+)\s*$", code) == [
        "engine.f",
        "apt1-engine.f",
    ]
    assert "RTAPT-" not in facade
    assert "RTAPT-" in code
    assert re.search(r"(?<![A-Z])PT-", code) is None

    status_map = _definition(source, "_RTAPTE-STATUS>RTE")
    for status in (
        "OK",
        "WOULD-BLOCK",
        "BUSY",
        "SESSION-LOST",
        "INVALID",
        "UNSUPPORTED",
        "CAPACITY",
        "REJECTED",
    ):
        assert f"RTAPT-S-{status}" in status_map
    owner_map = _definition(source, "_RTAPTE-OWNER-ST>RTE")
    assert len(set(re.findall(r"RTAPT-OWNER-ST-[A-Z-]+", owner_map))) == 14

    init = _definition(source, "_RTAPTE-INIT-BODY")
    assert "RTE-LABEL-PLAN-SIZE RTAPT-LABEL-PLAN-SIZE <>" in init
    assert (
        "RTE-LABEL-PLAN-ITEM-SIZE RTAPT-LABEL-PLAN-ITEM-SIZE <>"
        in init
    )
    span = init.index("RTE-FACADE-SIZE _RTE-SPAN?")
    engine = init.index("RTAPT-VALID?", span)
    disjoint = init.index("RTAPT-STORAGE-DISJOINT?", engine)
    fill = init.index("RTE-FACADE-SIZE 0 FILL", disjoint)
    magic = init.index("_RTE-F.MAGIC !", fill)
    assert span < engine < disjoint < fill < magic
    for field in (
        "_RTE-F.ABI !",
        "_RTE-F.SIZE !",
        "_RTE-F.SELF !",
        "_RTE-F.CONTEXT !",
        "_RTE-F.DISJOINT-XT !",
        "_RTE-F.STATUS-XT !",
        "_RTE-F.OWNER-OPEN-XT !",
        "_RTE-F.OWNER-STATE-XT !",
        "_RTE-F.RETAINED-BEGIN-XT !",
        "_RTE-F.REGION-DEF-XT !",
        "_RTE-F.RETAINED-SEAL-XT !",
        "_RTE-F.RETAINED-CANCEL-XT !",
        "_RTE-F.OWNER-DROP-XT !",
        "_RTE-F.LIMITS-XT !",
        "_RTE-F.LABEL-DEF-XT !",
        "_RTE-F.LABEL-PREFLIGHT-XT !",
    ):
        assert fill < init.index(field) < magic


def test_label_definition_is_neutral_validated_borrowed_and_exactly_bridged() -> None:
    source = FACADE.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")

    assert "160 CONSTANT RTE-LABEL-SIZE" in source
    expected_fields = {
        "OWNER": 0,
        "GENERATION": 8,
        "OBJECT": 16,
        "REGION": 24,
        "PARENT": 32,
        "ROW": 40,
        "COL": 48,
        "HEIGHT": 56,
        "WIDTH": 64,
        "ROOT-HEIGHT": 72,
        "ROOT-WIDTH": 80,
        "Z": 88,
        "VISIBLE": 96,
        "RGBA": 104,
        "H-ALIGN": 112,
        "V-ALIGN": 120,
        "ELLIPSIZE": 128,
        "TEXT-A": 136,
        "TEXT-U": 144,
        "RESERVED": 152,
    }
    for field, offset in expected_fields.items():
        definition = _definition(source, f"_RTE-LABEL.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition

    valid = _definition(source, "RTE-LABEL-VALID?")
    fields = _definition(source, "_RTE-LABEL-FIELDS?")
    assert "_RTE-LABEL-FIELDS?" in valid
    assert "_RTE-LABEL-TEXT?" in valid
    for identity in ("OWNER", "GENERATION", "OBJECT", "REGION"):
        assert f"_RTE-LABEL.{identity} @ 0=" in fields
    assert (
        "_RTE-LABEL.PARENT @ OVER _RTE-LABEL.OBJECT @ ="
        in fields
    )
    for boolean in ("VISIBLE", "ELLIPSIZE"):
        assert f"_RTE-LABEL.{boolean} @ _RTE-BOOL?" in fields
    assert "_RTE-LABEL.RGBA @ 0xFFFFFFFF U>" in fields
    assert "_RTE-LABEL.H-ALIGN @ 3 U<" in fields
    assert "_RTE-LABEL.V-ALIGN @ 3 U<" in fields
    assert "_RTE-LABEL.RESERVED @ IF" in fields
    assert "_RTE-LABEL-GEOMETRY?" in fields

    geometry = _definition(source, "_RTE-LABEL-GEOMETRY?")
    for nonnegative in ("HEIGHT", "WIDTH"):
        assert f"_RTE-LABEL.{nonnegative} @ 0<" in geometry
    for positive in ("ROOT-HEIGHT", "ROOT-WIDTH"):
        assert f"_RTE-LABEL.{positive} @ 0> 0=" in geometry
    assert geometry.count("_RTE-SADD?") == 2
    assert "_RTE-LG-ROW-END !" in geometry
    assert "_RTE-LG-COL-END !" in geometry
    visible = geometry.index("_RTE-LABEL.VISIBLE @ IF")
    for visible_only in (
        "_RTE-LABEL.HEIGHT @ 0=",
        "_RTE-LABEL.WIDTH @ 0=",
        "_RTE-LABEL.ROOT-HEIGHT @ < 0= OR",
        "_RTE-LG-ROW-END @ 0> 0= OR",
        "_RTE-LABEL.ROOT-WIDTH @ < 0= OR",
        "_RTE-LG-COL-END @ 0> 0= OR",
    ):
        assert geometry.index(visible_only) > visible

    text_span = _definition(source, "_RTE-LABEL-TEXT-SPAN?")
    assert "DUP 0= IF DROP 0= EXIT THEN" in text_span
    assert "MSPAN-NONWRAPPING?" in text_span
    text = _definition(source, "_RTE-LABEL-TEXT?")
    assert "_RTE-LABEL-UTF8-ONE" in text
    scalar = _definition(source, "_RTE-LABEL-UTF8-ONE")
    for excluded in ("DUP 0=", "OVER 10 =", "SWAP 13 ="):
        assert excluded in scalar
    assert (
        "SWAP 13 = OR IF\n"
        "            2DROP 0 EXIT\n"
        "        THEN\n"
        "        2DROP 1 EXIT"
        in scalar
    )
    for lead in ("0xC2 0xE0", "0xE0 0xF0", "0xF0 0xF5"):
        assert lead in scalar

    dispatch = _definition(source, "RTE-LABEL-DEFINE")
    facade_valid = dispatch.index("RTE-VALID?")
    record_span = dispatch.index("RTE-LABEL-SIZE _RTE-SPAN?", facade_valid)
    record_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", record_span)
    text_span_check = dispatch.index("_RTE-LABEL-TEXT-SPAN?", record_disjoint)
    text_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", record_disjoint + 1)
    record_valid = dispatch.index("_RTE-LABEL-FIELDS?", text_disjoint)
    execute = dispatch.index("_RTE-F.LABEL-DEF-XT @ EXECUTE", record_valid)
    assert (
        facade_valid
        < record_span
        < record_disjoint
        < text_span_check
        < text_disjoint
        < record_valid
        < execute
    )
    assert "RTE-LABEL-VALID?" not in dispatch
    assert "_RTE-LABEL-TEXT?" not in dispatch
    assert "DUP RTE-STATUS-VALID? 0=" in dispatch

    callback = _definition(bridge, "_RTAPTE-LABEL-DEFINE")
    ordered_fields = [
        callback.index(f"_RTE-LABEL.{field} @")
        for field in expected_fields
        if field != "RESERVED"
    ]
    assert ordered_fields == sorted(ordered_fields)
    provider = callback.index("RTAPT-LABEL-DEFINE")
    assert ordered_fields[-1] < provider
    assert "R> DROP R>" in callback
    assert "_RTAPTE-STATUS>RTE" in callback[provider:]
    for forbidden in ("PT-PRESENT-OP", "L!", "W!", "C!", "MOVE"):
        assert forbidden not in callback


def test_label_plan_preflight_is_neutral_complete_and_mutation_free() -> None:
    source = FACADE.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")

    assert "112 CONSTANT RTE-LABEL-PLAN-SIZE" in source
    assert "128 CONSTANT RTE-LABEL-PLAN-ITEM-SIZE" in source
    plan_fields = {
        "OWNER": 0,
        "GENERATION": 8,
        "SURFACE-COLS": 16,
        "SURFACE-ROWS": 24,
        "REGION-ID": 32,
        "REGION-X": 40,
        "REGION-Y": 48,
        "REGION-COLS": 56,
        "REGION-ROWS": 64,
        "REGION-Z": 72,
        "REGION-FLAGS": 80,
        "ITEMS-A": 88,
        "ITEMS-U": 96,
        "RESERVED": 104,
    }
    item_fields = {
        "OBJECT": 0,
        "PARENT": 8,
        "ROW": 16,
        "COL": 24,
        "HEIGHT": 32,
        "WIDTH": 40,
        "ROOT-HEIGHT": 48,
        "ROOT-WIDTH": 56,
        "Z": 64,
        "VISIBLE": 72,
        "RGBA": 80,
        "H-ALIGN": 88,
        "V-ALIGN": 96,
        "ELLIPSIZE": 104,
        "TEXT-CAPACITY": 112,
        "RESERVED": 120,
    }
    for prefix, fields in (("_RTE-LP", plan_fields), ("_RTE-LPI", item_fields)):
        for field, offset in fields.items():
            definition = _definition(source, f"{prefix}.{field}")
            if offset == 0:
                assert "+" not in definition
            else:
                assert f"{offset} +" in definition

    valid = _definition(source, "_RTE-LABEL-PLAN-VALID-BODY")
    assert "RTE-LABEL-PLAN-SIZE _RTE-SPAN?" in valid
    assert "_RTE-LPV-ITEMS-U @ 0= IF 0 EXIT THEN" in valid
    assert "RTE-LABEL-PLAN-ITEM-SIZE MOD" in valid
    assert "MSPAN-OVERLAP?" in valid
    assert "_RTE-UADD?" in valid
    assert "_RTE-LP.SURFACE-COLS @ U>" in valid
    assert "_RTE-LP.SURFACE-ROWS @ U>" in valid
    assert "_RTE-LABEL-PLAN-ITEM?" in valid
    item = _definition(source, "_RTE-LABEL-PLAN-ITEM?")
    assert "_RTE-LPV-PRIOR-OBJECT @ U>" in item
    assert "_RTE-LPI.PARENT @ IF" in item
    assert "_RTE-LPI.TEXT-CAPACITY @ 0<" in item
    geometry = _definition(source, "_RTE-LABEL-PLAN-ITEM-GEOMETRY?")
    assert geometry.count("_RTE-SADD?") == 2
    assert "_RTE-LP.REGION-ROWS @ <>" in geometry
    assert "_RTE-LP.REGION-COLS @ <>" in geometry
    signed_add = _definition(source, "_RTE-SADD?")
    assert all(word not in signed_add for word in (">R", "R@", "R>"))

    dispatch = _definition(source, "RTE-LABEL-PREFLIGHT")
    plan_span = dispatch.index("RTE-LABEL-PLAN-SIZE _RTE-SPAN?")
    plan_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", plan_span)
    items_span = dispatch.index("_RTE-SPAN?", plan_disjoint)
    items_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", items_span)
    validate = dispatch.index("RTE-LABEL-PLAN-VALID?", items_disjoint)
    execute = dispatch.index("_RTE-F.LABEL-PREFLIGHT-XT @ EXECUTE", validate)
    assert plan_span < plan_disjoint < items_span < items_disjoint < validate < execute
    assert "DUP RTE-STATUS-VALID? 0=" in dispatch

    callback = _definition(bridge, "_RTAPTE-LABEL-PREFLIGHT")
    assert "RTAPT-LABEL-PREFLIGHT" in callback
    assert "_RTAPTE-STATUS>RTE" in callback
    assert re.search(r"(?<![A-Z])PT-", callback) is None
    for forbidden in ("OWNER-OPEN", "REGION-DEFINE", "LABEL-DEFINE"):
        assert forbidden not in callback


def test_apt1_bridge_finalization_is_blank_idempotent_and_scrubs_authority() -> None:
    source = BRIDGE.read_text(encoding="utf-8")
    fini = _definition(source, "_RTAPTE-FINI-BODY")

    span = fini.index("RTE-FACADE-SIZE _RTE-SPAN?")
    blank = fini.index("RTE-FACADE-SIZE _RTAPTE-ZERO?", span)
    exact_bridge = fini.index("_RTAPTE-FACADE?", blank)
    disjoint = fini.index("RTAPT-STORAGE-DISJOINT?", exact_bridge)
    fill = fini.index("RTE-FACADE-SIZE 0 FILL", disjoint)
    assert span < blank < exact_bridge < disjoint < fill

    exact = _definition(source, "_RTAPTE-FACADE?")
    assert "RTE-VALID?" in exact
    assert "RTAPT-VALID?" in exact
    for callback in (
        "DISJOINT",
        "STATUS",
        "OWNER-OPEN",
        "OWNER-STATE",
        "RETAINED-BEGIN",
        "REGION-DEF",
        "RETAINED-SEAL",
        "RETAINED-CANCEL",
        "OWNER-DROP",
        "LIMITS",
        "LABEL-DEF",
        "LABEL-PREFLIGHT",
    ):
        assert f"_RTE-F.{callback}-XT @ ['] _RTAPTE-" in exact

    for public, body in (
        ("RTAPTE-INIT", "_RTAPTE-P-DO-INIT"),
        ("RTAPTE-FINI", "_RTAPTE-P-DO-FINI"),
    ):
        wrapper = _definition(source, public)
        assert f"['] {body} CATCH" in wrapper
        assert wrapper.index("CATCH") < wrapper.index("_RTAPTE-SCRUB-BORROWED")
    scrub = _definition(source, "_RTAPTE-SCRUB-BORROWED")
    assert "0 _RTAPTE-I-ENGINE !" in scrub
    assert "0 _RTAPTE-I-FACADE !" in scrub


def test_limits_snapshot_is_complete_neutral_and_fail_before_dispatch() -> None:
    source = FACADE.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")

    assert "160 CONSTANT RTE-LIMITS-SIZE" in source
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
        definition = _definition(source, f"_RTE-L.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition

    for feature in ("CORE", "VECTOR", "IMAGE", "INSTRUMENT", "SERIES", "CADENCE"):
        assert re.search(rf"(?m)^\d+\s+CONSTANT RTE-F-{feature}$", source)

    valid = _definition(source, "_RTE-LIMITS-VALID-BODY")
    for relationship in (
        "_RTE-FEATURE-MASK INVERT AND",
        "RTE-F-CORE AND 0=",
        "RTE-F-SERIES AND SWAP RTE-F-INSTRUMENT",
        "_RTE-L.LIVE-OWNERS @",
        "_RTE-L.OWNER-RECORDS @ U>",
        "_RTE-L.UTF8-BYTES @",
        "_RTE-L.LABEL-BYTES @ U<",
        "_RTE-L.SAMPLES-APPEND @",
        "_RTE-L.SERIES-HISTORY @ U>",
        "_RTE-L.SAMPLE-SLOTS @ U>",
        "_RTE-L.IMAGE-WIDTH @",
        "_RTE-L.IMAGE-HEIGHT @ _RTE-UMUL?",
        "_RTE-L.RESOURCE-BYTES @ U>",
    ):
        assert relationship in valid
    assert "_RTE-L.UPDATE-BYTES @ U> 0=" in _definition(
        source, "_RTE-LIMIT-FLOOR?"
    )
    public_valid = _definition(source, "RTE-LIMITS-VALID?")
    assert "0 _RTE-LV-L !" in public_valid
    assert "0 _RTE-LV-FEATURES !" in public_valid

    dispatch = _definition(source, "RTE-LIMITS@")
    span = dispatch.index("RTE-LIMITS-SIZE _RTE-SPAN?")
    disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", span)
    execute = dispatch.index("_RTE-F.LIMITS-XT @ EXECUTE", disjoint)
    validate = dispatch.index("RTE-LIMITS-VALID?", execute)
    assert span < disjoint < execute < validate
    assert "DUP RTE-S-OK = IF" in dispatch

    callback = _definition(bridge, "_RTAPTE-LIMITS@")
    provider = callback.index("RTAPT-LIMITS@")
    provider_valid = callback.index("RTAPT-LIMITS-VALID?", provider)
    neutral_valid = callback.index("RTE-LIMITS-VALID?", provider_valid)
    copied = callback.index("_RTAPTE-LIMITS-COPY", neutral_valid)
    assert provider < provider_valid < neutral_valid < copied
    assert "RTAPT-S-OK <> IF" in callback
    assert "_RTAPTE-FEATURES>RTE <> IF" in callback
    bridge_scrub = _definition(bridge, "_RTAPTE-LIMITS-SCRUB")
    for pointer in (
        "_RTAPTE-LS-DST",
        "_RTAPTE-LS-SRC",
        "_RTAPTE-LS-ENGINE",
        "_RTAPTE-LS-STATUS",
    ):
        assert f"0 {pointer} !" in bridge_scrub
    copy = _definition(bridge, "_RTAPTE-LIMITS-COPY")
    for field in expected_fields:
        assert f"_RTAPT-L.{field} @" in copy
        assert f"_RTE-L.{field} !" in copy
    feature_map = _definition(bridge, "_RTAPTE-FEATURES>RTE")
    for feature in ("CORE", "VECTOR", "IMAGE", "INSTRUMENT", "SERIES", "CADENCE"):
        assert f"RTAPT-F-{feature}" in feature_map
        assert f"RTE-F-{feature}" in feature_map
