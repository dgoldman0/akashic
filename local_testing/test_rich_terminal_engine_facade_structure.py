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

    assert "128 CONSTANT RTE-FACADE-SIZE" in code
    assert "160 CONSTANT RTE-LIMITS-SIZE" in code
    assert "_RTE-F.CONTEXT" in _definition(source, "RTE-VALID?")
    valid = _definition(source, "RTE-VALID?")
    for callback in (
        "DISJOINT",
        "STATUS",
        "OWNER-OPEN",
        "OWNER-STATE",
        "RICH-BEGIN",
        "REGION-DEF",
        "RICH-SEAL",
        "RICH-CANCEL",
        "OWNER-DROP",
        "LIMITS",
    ):
        assert f"_RTE-F.{callback}-XT @ 0=" in valid
    assert "_RTE-F.RESERVED @ 0=" in valid

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
        "RTE-RICH-BEGIN": "( retained-mode facade -- status )",
        "RTE-RICH-SEAL": "( disposition facade -- status )",
        "RTE-RICH-CANCEL": "( facade -- status )",
        "RTE-OWNER-DROP": "( owner generation facade -- status )",
    }
    for name, signature in public_signatures.items():
        assert signature in _definition(source, name).splitlines()[0]

    owner_state = _definition(source, "RTE-OWNER-STATE@")
    assert "RTE-STATUS-VALID?" in owner_state
    assert "RTE-OWNER-STATE-VALID?" in owner_state
    assert "RTE-OWNER-ST-FREE RTE-S-INVALID" in owner_state
    assert "_RTE-MODE?" in _definition(source, "RTE-RICH-BEGIN")
    assert "_RTE-DISPOSITION?" in _definition(source, "RTE-RICH-SEAL")

    for name in (
        "RTE-STATUS@",
        "RTE-LIMITS@",
        "RTE-OWNER-OPEN",
        "RTE-OWNER-STATE@",
        "RTE-RICH-BEGIN",
        "RTE-REGION-DEFINE",
        "RTE-RICH-SEAL",
        "RTE-RICH-CANCEL",
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
        "_RTE-F.RICH-BEGIN-XT !",
        "_RTE-F.REGION-DEF-XT !",
        "_RTE-F.RICH-SEAL-XT !",
        "_RTE-F.RICH-CANCEL-XT !",
        "_RTE-F.OWNER-DROP-XT !",
        "_RTE-F.LIMITS-XT !",
    ):
        assert fill < init.index(field) < magic


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
        "RICH-BEGIN",
        "REGION-DEF",
        "RICH-SEAL",
        "RICH-CANCEL",
        "OWNER-DROP",
        "LIMITS",
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
