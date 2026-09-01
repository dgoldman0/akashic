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


def test_shared_scalar_guards_precede_their_first_geometry_consumers() -> None:
    code = _code_without_comments(FACADE.read_text(encoding="utf-8"))
    first_geometry = code.index(": _RTE-REGION-GEOMETRY-BODY?")

    for guard in ("_RTE-U16?", "_RTE-U32?", "_RTE-I32?"):
        declaration = f": {guard} "
        assert code.count(declaration) == 1
        assert code.index(guard) == code.index(declaration) + 2
        assert code.index(declaration) < first_geometry


def test_facade_is_backend_neutral_immutable_and_caller_owned() -> None:
    source = FACADE.read_text(encoding="utf-8")
    code = _code_without_comments(source)

    assert "PROVIDED akashic-tui-rte" in code
    assert re.findall(r"(?m)^REQUIRE\s+(\S+)\s*$", code) == [
        "../../utils/memory-span.f",
        "../../utils/string.f",
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
        r"(?m)(?:^|[ \t])(?:ALLOCATE|FREE|RESIZE|XBUF)(?=[ \t]|$)",
        code,
    )
    assert set(re.findall(r"(?m)^CREATE\s+(\S+)", code)) == {
        "_RTE-HPV-OWNED-START",
        "_RTE-HPV-SUMMARY-MEM",
        "_RTE-HPV-OWNED-END",
    }
    assert code.count("ALLOT") == 1
    assert (
        "CREATE _RTE-HPV-SUMMARY-MEM "
        "RTE-HYBRID-ADMISSION-SIZE 7 + ALLOT" in code
    )
    assert (
        "_RTE-HPV-SUMMARY-MEM 7 + -8 AND "
        "CONSTANT _RTE-HPV-SUMMARY" in code
    )

    assert "_RTE-ABI" not in code
    assert '0x5254454641434144 CONSTANT _RTE-MAGIC' in code
    assert "_RTE-F.RESERVED @ IF DROP 0 EXIT THEN" in _definition(
        source, "RTE-VALID?"
    )
    assert "200 CONSTANT RTE-FACADE-SIZE" in code
    assert "168 CONSTANT RTE-LIMITS-SIZE" in code
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
        "GLYPH-RUN-DEF",
        "GLYPH-RUN-PREFLIGHT",
        "UPDATE-STATE",
        "GLYPH-RUN-REPLACE",
        "CONTROL-PREFLIGHT",
        "CONTROL-DEF",
        "CONTROL-REPLACE",
        "CONTROL-DROP",
        "HYBRID-PREFLIGHT",
        "INSTRUMENT-DEF",
    ):
        assert f"_RTE-F.{callback}-XT @ 0=" in valid

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
        "RTE-UPDATE-STATE-VALID?": "( update-state -- flag )",
        "RTE-UPDATE-STATE@": "( facade -- update-state status )",
        "RTE-LIMITS-BYTES": "( -- bytes )",
        "RTE-LIMITS-VALID?": "( limits -- flag )",
        "RTE-LIMITS@": "( limits facade -- status )",
        "RTE-GLYPH-RUN-BYTES": "( -- bytes )",
        "RTE-GLYPH-RUN-VALID?": "( run -- flag )",
        "RTE-GLYPH-RUN-DEFINE": "( run facade -- status )",
        "RTE-GLYPH-RUN-REPLACE": "( run facade -- status )",
        "RTE-GLYPH-RUN-PLAN-BYTES": "( -- bytes )",
        "RTE-GLYPH-RUN-PLAN-ITEM-BYTES": "( -- bytes )",
        "RTE-GLYPH-RUN-PLAN-VALID?": "( plan -- flag )",
        "RTE-GLYPH-RUN-PREFLIGHT": "( plan facade -- status )",
        "RTE-INSTRUMENT-BYTES": "( -- bytes )",
        "RTE-INSTRUMENT-VALID?": "( instrument -- flag )",
        "RTE-INSTRUMENT-PLAN-BYTES": "( -- bytes )",
        "RTE-INSTRUMENT-REGION-BYTES": "( -- bytes )",
        "RTE-INSTRUMENT-PLAN-ITEM-BYTES": "( -- bytes )",
        "RTE-INSTRUMENT-PLAN-VALID?": "( plan -- flag )",
        "RTE-INSTRUMENT-DEFINE": "( instrument facade -- status )",
        "RTE-CONTROL-BYTES": "( -- bytes )",
        "RTE-CONTROL-VALID?": "( control -- flag )",
        "RTE-CONTROL-PLAN-BYTES": "( -- bytes )",
        "RTE-CONTROL-PLAN-ITEM-BYTES": "( -- bytes )",
        "RTE-CONTROL-PLAN-VALID?": "( plan -- flag )",
        "RTE-CONTROL-PREFLIGHT": "( plan facade -- status )",
        "RTE-CONTROL-DEFINE": "( control facade -- status )",
        "RTE-CONTROL-REPLACE": "( control facade -- status )",
        "RTE-CONTROL-DROP": "( owner generation control facade -- status )",
        "RTE-HYBRID-PLAN-BYTES": "( -- bytes )",
        "RTE-HYBRID-TEXT-REF-BYTES": "( -- bytes )",
        "RTE-HYBRID-ADMISSION-BYTES": "( -- bytes )",
        "RTE-HYBRID-PREFLIGHT": "( hybrid admission facade -- status )",
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
    region_define = _definition(source, "RTE-REGION-DEFINE")
    assert (
        "owner generation region x y cols rows clip-x clip-y clip-cols "
        "clip-rows z flags facade -- status"
    ) in region_define
    assert "2DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP" in region_define
    update_state = _definition(source, "RTE-UPDATE-STATE@")
    assert "RTE-STATUS-VALID?" in update_state
    assert "RTE-UPDATE-STATE-VALID?" in update_state
    assert "RTE-UPDATE-IDLE RTE-S-INVALID" in update_state

    for name in (
        "RTE-STATUS@",
        "RTE-UPDATE-STATE@",
        "RTE-LIMITS@",
        "RTE-OWNER-OPEN",
        "RTE-OWNER-STATE@",
        "RTE-RETAINED-BEGIN",
        "RTE-REGION-DEFINE",
        "RTE-GLYPH-RUN-DEFINE",
        "RTE-GLYPH-RUN-REPLACE",
        "RTE-GLYPH-RUN-PREFLIGHT",
        "RTE-INSTRUMENT-DEFINE",
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

    assert "PROVIDED akashic-tui-rtapte" in code
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
    update_map = _definition(source, "_RTAPTE-UPDATE-ST>RTE")
    assert set(re.findall(r"RTAPT-UPDATE-[A-Z-]+", update_map)) == {
        "RTAPT-UPDATE-IDLE",
        "RTAPT-UPDATE-CAPTURING",
        "RTAPT-UPDATE-SEALED",
        "RTAPT-UPDATE-CELL-OPEN",
        "RTAPT-UPDATE-AWAITING",
    }
    update_callback = _definition(source, "_RTAPTE-UPDATE-STATE@")
    assert "RTAPT-UPDATE-STATE@" in update_callback
    assert "_RTAPTE-UPDATE-ST>RTE" in update_callback
    assert "_RTAPTE-STATUS>RTE" in update_callback

    region_callback = _definition(source, "_RTAPTE-REGION-DEFINE")
    assert (
        "owner generation region x y cols rows clip-x clip-y clip-cols "
        "clip-rows z flags engine -- status"
    ) in region_callback
    assert "RTAPT-REGION-DEFINE _RTAPTE-STATUS>RTE" in region_callback

    init = _definition(source, "_RTAPTE-INIT-BODY")
    assert "RTE-GLYPH-RUN-PLAN-SIZE RTAPT-GLYPH-RUN-PLAN-SIZE <>" in init
    assert (
        "RTE-GLYPH-RUN-PLAN-ITEM-SIZE RTAPT-GLYPH-RUN-PLAN-ITEM-SIZE <>"
        in init
    )
    assert "_RTAPTE-GLYPH-PLAN-LAYOUT? 0= OR" in init
    assert "RTE-INSTRUMENT-SIZE RTAPT-INSTRUMENT-SIZE <>" in init
    assert "_RTAPTE-INSTRUMENT-LAYOUT? 0= OR" in init
    assert "_RTAPTE-INSTRUMENT-VOCABULARY? 0= OR" in init
    span = init.index("RTE-FACADE-SIZE _RTE-SPAN?")
    engine = init.index("RTAPT-VALID?", span)
    disjoint = init.index("RTAPT-STORAGE-DISJOINT?", engine)
    fill = init.index("RTE-FACADE-SIZE 0 FILL", disjoint)
    magic = init.index("_RTE-F.MAGIC !", fill)
    assert span < engine < disjoint < fill < magic
    for field in (
        "_RTE-F.RESERVED !",
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
        "_RTE-F.GLYPH-RUN-DEF-XT !",
        "_RTE-F.GLYPH-RUN-PREFLIGHT-XT !",
        "_RTE-F.UPDATE-STATE-XT !",
        "_RTE-F.GLYPH-RUN-REPLACE-XT !",
        "_RTE-F.CONTROL-PREFLIGHT-XT !",
        "_RTE-F.CONTROL-DEF-XT !",
        "_RTE-F.CONTROL-REPLACE-XT !",
        "_RTE-F.CONTROL-DROP-XT !",
        "_RTE-F.HYBRID-PREFLIGHT-XT !",
        "_RTE-F.INSTRUMENT-DEF-XT !",
    ):
        assert fill < init.index(field) < magic


def test_glyph_run_definition_is_neutral_validated_borrowed_and_exactly_bridged() -> None:
    source = FACADE.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")

    assert "152 CONSTANT RTE-GLYPH-RUN-SIZE" in source
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
        "FG-RGBA": 104,
        "BG-RGBA": 112,
        "ATTRS": 120,
        "TEXT-A": 128,
        "TEXT-U": 136,
        "RESERVED": 144,
    }
    for field, offset in expected_fields.items():
        definition = _definition(source, f"_RTE-GLYPH-RUN.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition

    valid = _definition(source, "RTE-GLYPH-RUN-VALID?")
    fields = _definition(source, "_RTE-GLYPH-RUN-FIELDS?")
    assert "_RTE-GLYPH-RUN-FIELDS?" in valid
    assert "_RTE-GLYPH-RUN-TEXT?" in valid
    for identity in ("OWNER", "GENERATION", "OBJECT", "REGION"):
        assert f"_RTE-GLYPH-RUN.{identity} @ 0=" in fields
    assert (
        "_RTE-GLYPH-RUN.PARENT @ OVER _RTE-GLYPH-RUN.OBJECT @ ="
        in fields
    )
    assert "_RTE-GLYPH-RUN.VISIBLE @ _RTE-BOOL?" in fields
    assert "_RTE-GLYPH-RUN.FG-RGBA @ 0xFFFFFFFF U>" in fields
    assert "_RTE-GLYPH-RUN.BG-RGBA @ 0xFFFFFFFF U>" in fields
    assert "_RTE-GLYPH-RUN.ATTRS @" in fields
    assert "_RTE-GLYPH-RUN-ATTRS? 0=" in fields
    assert "_RTE-GLYPH-RUN.RESERVED @ IF" in fields
    assert "_RTE-GLYPH-RUN-GEOMETRY?" in fields

    geometry = _definition(source, "_RTE-GLYPH-RUN-GEOMETRY?")
    for nonnegative in ("HEIGHT", "WIDTH"):
        assert f"_RTE-GLYPH-RUN.{nonnegative} @ 0<" in geometry
    for positive in ("ROOT-HEIGHT", "ROOT-WIDTH"):
        assert f"_RTE-GLYPH-RUN.{positive} @ 0> 0=" in geometry
    assert geometry.count("_RTE-SADD?") == 2
    assert "_RTE-LG-ROW-END !" in geometry
    assert "_RTE-LG-COL-END !" in geometry
    visible = geometry.index("_RTE-GLYPH-RUN.VISIBLE @ IF")
    for visible_only in (
        "_RTE-GLYPH-RUN.HEIGHT @ 0=",
        "_RTE-GLYPH-RUN.WIDTH @ 0=",
        "_RTE-GLYPH-RUN.ROOT-HEIGHT @ < 0= OR",
        "_RTE-LG-ROW-END @ 0> 0= OR",
        "_RTE-GLYPH-RUN.ROOT-WIDTH @ < 0= OR",
        "_RTE-LG-COL-END @ 0> 0= OR",
    ):
        assert geometry.index(visible_only) > visible

    text_span = _definition(source, "_RTE-GLYPH-RUN-TEXT-SPAN?")
    assert "DUP 0= IF DROP 0= EXIT THEN" in text_span
    assert "MSPAN-NONWRAPPING?" in text_span
    text = _definition(source, "_RTE-GLYPH-RUN-TEXT?")
    assert "_RTE-GLYPH-RUN-UTF8-ONE" in text
    scalar = _definition(source, "_RTE-GLYPH-RUN-UTF8-ONE")
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

    for public, callback_name, callback_field, provider_name in (
        (
            "RTE-GLYPH-RUN-DEFINE",
            "_RTAPTE-GLYPH-RUN-DEFINE",
            "_RTE-F.GLYPH-RUN-DEF-XT @ EXECUTE",
            "RTAPT-GLYPH-RUN-DEFINE",
        ),
        (
            "RTE-GLYPH-RUN-REPLACE",
            "_RTAPTE-GLYPH-RUN-REPLACE",
            "_RTE-F.GLYPH-RUN-REPLACE-XT @ EXECUTE",
            "RTAPT-GLYPH-RUN-REPLACE",
        ),
    ):
        dispatch = _definition(source, public)
        facade_valid = dispatch.index("RTE-VALID?")
        record_span = dispatch.index(
            "RTE-GLYPH-RUN-SIZE _RTE-SPAN?", facade_valid
        )
        record_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", record_span)
        text_span_check = dispatch.index(
            "_RTE-GLYPH-RUN-TEXT-SPAN?", record_disjoint
        )
        text_disjoint = dispatch.index(
            "RTE-STORAGE-DISJOINT?", record_disjoint + 1
        )
        record_valid = dispatch.index("_RTE-GLYPH-RUN-FIELDS?", text_disjoint)
        execute = dispatch.index(callback_field, record_valid)
        assert (
            facade_valid
            < record_span
            < record_disjoint
            < text_span_check
            < text_disjoint
            < record_valid
            < execute
        )
        assert "RTE-GLYPH-RUN-VALID?" not in dispatch
        assert "_RTE-GLYPH-RUN-TEXT?" not in dispatch
        assert "DUP RTE-STATUS-VALID? 0=" in dispatch

        callback = _definition(bridge, callback_name)
        ordered_fields = [
            callback.index(f"_RTE-GLYPH-RUN.{field} @")
            for field in expected_fields
            if field != "RESERVED"
        ]
        assert ordered_fields == sorted(ordered_fields)
        provider = callback.index(provider_name)
        assert ordered_fields[-1] < provider
        assert "R> DROP R>" in callback
        assert "_RTAPTE-STATUS>RTE" in callback[provider:]
        for forbidden in ("PT-PRESENT-OP", "L!", "W!", "C!", "MOVE"):
            assert forbidden not in callback


def test_instrument_definition_uses_one_proven_borrowed_provider_abi() -> None:
    source = FACADE.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")

    assert "208 CONSTANT RTE-INSTRUMENT-SIZE" in source
    expected_fields = {
        "OWNER": 0,
        "GENERATION": 8,
        "ID": 16,
        "KIND": 24,
        "VISIBLE": 32,
        "Z": 40,
        "REGION": 48,
        "PARENT": 56,
        "ROW": 64,
        "COL": 72,
        "HEIGHT": 80,
        "WIDTH": 88,
        "ROOT-HEIGHT": 96,
        "ROOT-WIDTH": 104,
        "COLOR-A": 112,
        "COLOR-B": 120,
        "MODE": 128,
        "OPTIONS": 136,
        "MINIMUM": 144,
        "MAXIMUM": 152,
        "VALUE": 160,
        "SCALE": 168,
        "UNIT-A": 176,
        "UNIT-U": 184,
        "FORMATTED-U": 192,
        "RESERVED": 200,
    }
    for field, offset in expected_fields.items():
        definition = _definition(source, f"_RTE-INSTRUMENT.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition

    layout = _definition(bridge, "_RTAPTE-INSTRUMENT-LAYOUT?")
    for field in expected_fields:
        assert (
            f"0 _RTE-INSTRUMENT.{field} "
            f"0 _RTAPT-INSTRUMENT.{field} ="
        ) in layout

    vocabulary = _definition(bridge, "_RTAPTE-INSTRUMENT-VOCABULARY?")
    for neutral, provider in (
        ("RTE-INSTRUMENT-READOUT", "RTAPT-INSTRUMENT-READOUT"),
        ("RTE-INSTRUMENT-METER", "RTAPT-INSTRUMENT-METER"),
        ("RTE-INSTRUMENT-STATUS", "RTAPT-INSTRUMENT-STATUS"),
        ("RTE-READOUT-INTEGER", "RTAPT-READOUT-INTEGER"),
        ("RTE-READOUT-FIXED", "RTAPT-READOUT-FIXED"),
        ("RTE-READOUT-PERCENT", "RTAPT-READOUT-PERCENT"),
        ("RTE-METER-HORIZONTAL", "RTAPT-METER-HORIZONTAL"),
        ("RTE-METER-VERTICAL", "RTAPT-METER-VERTICAL"),
        ("RTE-METER-SHOW-VALUE", "RTAPT-METER-SHOW-VALUE"),
        ("RTE-STATUS-CIRCLE", "RTAPT-STATUS-CIRCLE"),
        ("RTE-STATUS-SQUARE", "RTAPT-STATUS-SQUARE"),
        ("RTE-STATUS-DIAMOND", "RTAPT-STATUS-DIAMOND"),
    ):
        assert f"{neutral} {provider} =" in vocabulary

    init = _definition(bridge, "_RTAPTE-INIT-BODY")
    size = init.index("RTE-INSTRUMENT-SIZE RTAPT-INSTRUMENT-SIZE <>")
    layout_check = init.index("_RTAPTE-INSTRUMENT-LAYOUT? 0= OR", size)
    vocabulary_check = init.index(
        "_RTAPTE-INSTRUMENT-VOCABULARY? 0= OR", layout_check
    )
    facade_span = init.index("RTE-FACADE-SIZE _RTE-SPAN?", vocabulary_check)
    facade_fill = init.index("RTE-FACADE-SIZE 0 FILL", facade_span)
    callback_store = init.index("_RTE-F.INSTRUMENT-DEF-XT !", facade_fill)
    magic = init.index("_RTE-F.MAGIC !", callback_store)
    assert size < layout_check < vocabulary_check < facade_span
    assert facade_fill < callback_store < magic
    assert "['] _RTAPTE-INSTRUMENT-DEFINE" in init

    exact = _definition(bridge, "_RTAPTE-FACADE?")
    assert re.search(
        r"_RTE-F\.INSTRUMENT-DEF-XT\s+@\s+\[']\s+"
        r"_RTAPTE-INSTRUMENT-DEFINE\s+=\s+AND",
        exact,
    )

    callback = _definition(bridge, "_RTAPTE-INSTRUMENT-DEFINE")
    provider_call = callback.index("RTAPT-INSTRUMENT-DEFINE")
    status_map = callback.index("_RTAPTE-STATUS>RTE", provider_call)
    assert provider_call < status_map
    for forbidden in (
        "_RTE-INSTRUMENT.",
        "_RTAPT-INSTRUMENT.",
        "MOVE",
        "FILL",
        "UCTX-",
        "DESK-",
        "PAD-",
    ):
        assert forbidden not in callback

    hybrid_layout = _definition(bridge, "_RTAPTE-HYBRID-LAYOUT?")
    for field in (
        "CLIP-X",
        "CLIP-Y",
        "CLIP-COLS",
        "CLIP-ROWS",
        "INSTRUMENT-REGION-COUNT",
        "INSTRUMENT-COUNT",
        "READOUT-COUNT",
        "METER-COUNT",
        "STATUS-COUNT",
        "INSTRUMENT-UNIT-BYTES",
        "INSTRUMENT-UNIT-ALIGNED",
        "INSTRUMENT-UNIT-MAX",
        "INSTRUMENT-FORMATTED-BYTES",
        "INSTRUMENT-FORMATTED-MAX",
        "INSTRUMENT-LAST",
    ):
        assert f"0 _RTE-HA.{field}" in hybrid_layout
        assert f"0 _RTAPT-HA.{field} = AND" in hybrid_layout


def test_glyph_run_plan_preflight_is_neutral_complete_and_mutation_free() -> None:
    source = FACADE.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")

    assert "144 CONSTANT RTE-GLYPH-RUN-PLAN-SIZE" in source
    assert "120 CONSTANT RTE-GLYPH-RUN-PLAN-ITEM-SIZE" in source
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
        "CLIP-X": 72,
        "CLIP-Y": 80,
        "CLIP-COLS": 88,
        "CLIP-ROWS": 96,
        "REGION-Z": 104,
        "REGION-FLAGS": 112,
        "ITEMS-A": 120,
        "ITEMS-U": 128,
        "RESERVED": 136,
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
        "FG-RGBA": 80,
        "BG-RGBA": 88,
        "ATTRS": 96,
        "TEXT-CAPACITY": 104,
        "RESERVED": 112,
    }
    for prefix, fields in (("_RTE-LP", plan_fields), ("_RTE-LPI", item_fields)):
        for field, offset in fields.items():
            definition = _definition(source, f"{prefix}.{field}")
            if offset == 0:
                assert "+" not in definition
            else:
                assert f"{offset} +" in definition

    bridge_layout = _definition(bridge, "_RTAPTE-GLYPH-PLAN-LAYOUT?")
    for field in plan_fields:
        assert f"0 _RTE-LP.{field}" in bridge_layout
        assert f"0 _RTAPT-LP.{field}" in bridge_layout
    assert "[DEFINED] _RTAPT-LP.CLIP-X [IF]" in bridge
    init = _definition(bridge, "_RTAPTE-INIT-BODY")
    size_check = init.index(
        "RTE-GLYPH-RUN-PLAN-SIZE RTAPT-GLYPH-RUN-PLAN-SIZE <>"
    )
    item_size_check = init.index(
        "RTE-GLYPH-RUN-PLAN-ITEM-SIZE RTAPT-GLYPH-RUN-PLAN-ITEM-SIZE <>",
        size_check,
    )
    layout_check = init.index("_RTAPTE-GLYPH-PLAN-LAYOUT? 0= OR", item_size_check)
    facade_span = init.index("RTE-FACADE-SIZE _RTE-SPAN?", layout_check)
    assert size_check < item_size_check < layout_check < facade_span

    header = _definition(source, "_RTE-GLYPH-RUN-PLAN-HEADER?")
    valid = _definition(source, "_RTE-GLYPH-RUN-PLAN-VALID-BODY")
    assert "RTE-GLYPH-RUN-PLAN-SIZE _RTE-SPAN?" in header
    assert "_RTE-LPV-ITEMS-U @ 0= IF 0 EXIT THEN" in header
    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE MOD" in header
    assert "MSPAN-OVERLAP?" in header
    assert "_RTE-REGION-GEOMETRY?" in header
    for clip in ("CLIP-X", "CLIP-Y", "CLIP-COLS", "CLIP-ROWS"):
        assert f"_RTE-LP.{clip} @" in header
    assert "_RTE-GLYPH-RUN-PLAN-HEADER?" in valid
    assert "_RTE-GLYPH-RUN-PLAN-ITEM?" in valid
    item = _definition(source, "_RTE-GLYPH-RUN-PLAN-ITEM?")
    assert "_RTE-LPV-PRIOR-OBJECT @ U>" in item
    assert "_RTE-LPI.PARENT @ IF" in item
    assert "_RTE-LPI.TEXT-CAPACITY @ 0<" in item
    monotone = item.index("_RTE-LPV-PRIOR-OBJECT @ U>")
    publish_high = item.index("_RTE-LPV-PRIOR-OBJECT !", monotone)
    assert monotone < publish_high
    assert "strictly increasing but may be sparse" in source
    assert "exact owner object quota is item" in source
    geometry = _definition(source, "_RTE-GLYPH-RUN-PLAN-ITEM-GEOMETRY?")
    assert geometry.count("_RTE-SADD?") == 2
    assert "_RTE-LP.REGION-ROWS @ <>" in geometry
    assert "_RTE-LP.REGION-COLS @ <>" in geometry
    positive_height = geometry.index("_RTE-LPI.HEIGHT @ DUP 0=")
    height_u32 = geometry.index("SWAP _RTE-U32? 0= OR IF", positive_height)
    positive_width = geometry.index("_RTE-LPI.WIDTH @ DUP 0=", height_u32)
    width_u32 = geometry.index("SWAP _RTE-U32? 0= OR IF", positive_width)
    visible_branch = geometry.index("_RTE-LPI.VISIBLE @ IF", positive_width)
    assert positive_height < height_u32 < positive_width < width_u32 < visible_branch
    assert "_RTE-LPI.HEIGHT @ 0<" not in geometry
    assert "_RTE-LPI.WIDTH @ 0<" not in geometry
    assert "_RTE-LPI.HEIGHT @ 0> 0=" not in geometry
    assert "_RTE-LPI.WIDTH @ 0> 0=" not in geometry
    assert "_RTE-LPI.HEIGHT @ 0=" not in geometry[visible_branch:]
    assert "_RTE-LPI.WIDTH @ 0=" not in geometry[visible_branch:]
    hybrid_item = _definition(source, "_RTE-HPV-GLYPH-ITEM?")
    assert "_RTE-GLYPH-RUN-PLAN-ITEM? 0= IF 0 EXIT THEN" in hybrid_item
    signed_add = _definition(source, "_RTE-SADD?")
    assert all(word not in signed_add for word in (">R", "R@", "R>"))

    dispatch = _definition(source, "RTE-GLYPH-RUN-PREFLIGHT")
    plan_span = dispatch.index("RTE-GLYPH-RUN-PLAN-SIZE _RTE-SPAN?")
    plan_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", plan_span)
    items_span = dispatch.index("_RTE-SPAN?", plan_disjoint)
    items_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", items_span)
    validate = dispatch.index("RTE-GLYPH-RUN-PLAN-VALID?", items_disjoint)
    execute = dispatch.index("_RTE-F.GLYPH-RUN-PREFLIGHT-XT @ EXECUTE", validate)
    assert plan_span < plan_disjoint < items_span < items_disjoint < validate < execute
    assert "DUP RTE-STATUS-VALID? 0=" in dispatch

    callback = _definition(bridge, "_RTAPTE-GLYPH-RUN-PREFLIGHT")
    assert "RTAPT-GLYPH-RUN-PREFLIGHT" in callback
    assert "_RTAPTE-STATUS>RTE" in callback
    assert "_RTE-LP.ITEMS-U" not in callback
    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE" not in callback
    assert re.search(r"(?<![A-Z])PT-", callback) is None
    for forbidden in ("OWNER-OPEN", "REGION-DEFINE", "GLYPH-RUN-DEFINE"):
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
        "GLYPH-RUN-DEF",
        "GLYPH-RUN-PREFLIGHT",
        "UPDATE-STATE",
        "GLYPH-RUN-REPLACE",
        "CONTROL-PREFLIGHT",
        "CONTROL-DEF",
        "CONTROL-REPLACE",
        "CONTROL-DROP",
        "HYBRID-PREFLIGHT",
        "INSTRUMENT-DEF",
    ):
        assert re.search(
            rf"_RTE-F\.{callback}-XT\s+@\s+\[']\s+_RTAPTE-",
            exact,
        )

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

    assert "168 CONSTANT RTE-LIMITS-SIZE" in source
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
        "GLYPH-RUN-BYTES": 112,
        "UTF8-BYTES": 120,
        "SAMPLES-APPEND": 128,
        "SERIES-HISTORY": 136,
        "SAMPLE-SLOTS": 144,
        "MIN-INTERVAL-US": 152,
        "OUTBOUND-PAYLOAD": 160,
    }
    for field, offset in expected_fields.items():
        definition = _definition(source, f"_RTE-L.{field}")
        if offset == 0:
            assert "+" not in definition
        else:
            assert f"{offset} +" in definition

    for feature in (
        "CORE",
        "VECTOR",
        "IMAGE",
        "INSTRUMENT",
        "SERIES",
        "CADENCE",
        "CONTROLS",
        "CONTROL-COLLECTIONS",
    ):
        assert re.search(rf"(?m)^\d+\s+CONSTANT RTE-F-{feature}$", source)

    valid = _definition(source, "_RTE-LIMITS-VALID-BODY")
    for relationship in (
        "_RTE-FEATURE-MASK INVERT AND",
        "RTE-F-CORE AND 0=",
        "RTE-F-SERIES AND SWAP RTE-F-INSTRUMENT",
        "_RTE-L.LIVE-OWNERS @",
        "_RTE-L.OWNER-RECORDS @ U>",
        "_RTE-L.UTF8-BYTES @",
        "_RTE-L.GLYPH-RUN-BYTES @ ?DUP IF",
        "_RTE-L.OBJECTS @ 0=",
        "_RTE-L.UTF8-BYTES @ U>",
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
    assert "264 _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN" in valid
    assert (
        "_RTE-LV-L @ _RTE-L.OUTBOUND-PAYLOAD @ 64 U< IF 0 EXIT THEN"
        in valid
    )
    assert "248 _RTE-LV-L @ _RTE-LIMIT-FLOOR?" not in valid
    assert "_RTE-L.OUTBOUND-PAYLOAD @ 0= IF" not in valid
    base_update = valid.index("264 _RTE-LV-L @ _RTE-LIMIT-FLOOR?")
    base_payload = valid.index(
        "_RTE-L.OUTBOUND-PAYLOAD @ 64 U<", base_update
    )
    feature_payload = valid.index("_RTE-L.OUTBOUND-PAYLOAD @ 80 U<", base_payload)
    assert base_update < base_payload < feature_payload
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
    refusal = callback.index("RTAPT-S-OK <> IF", provider)
    copied = callback.index("_RTAPTE-LIMITS-COPY", refusal)
    assert provider < refusal < copied
    assert "RTAPT-S-OK <> IF" in callback
    assert "RTAPT-LIMITS-VALID?" not in callback
    assert "RTE-LIMITS-VALID?" not in callback
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
    for feature in (
        "CORE",
        "VECTOR",
        "IMAGE",
        "INSTRUMENT",
        "SERIES",
        "CADENCE",
        "CONTROLS",
    ):
        assert f"RTAPT-F-{feature}" in feature_map
        assert f"RTE-F-{feature}" in feature_map
