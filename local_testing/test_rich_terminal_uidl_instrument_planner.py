"""Seconds-only structural contract for generic UDGSN instrument lowering."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLANNER = ROOT / "akashic" / "tui" / "rich-terminal" / "uidl-instrument-planner.f"
ENGINE = ROOT / "akashic" / "tui" / "rich-terminal" / "engine.f"
SNAPSHOT = ROOT / "akashic" / "tui" / "uidl-data-graphics-snapshot.f"
CLAIMS = ROOT / "akashic" / "tui" / "rich-terminal" / "uidl-claim-ledger.f"


def _definitions(source: str) -> list[tuple[str, str]]:
    return [
        (match.group(1), match.group(0))
        for match in re.finditer(
            r"(?ms)^:\s+(\S+)(?=\s).*?;\s*(?:\\[^\n]*)?$",
            source,
        )
    ]


def _definition(source: str, name: str) -> str:
    matches = [body for word, body in _definitions(source) if word == name]
    assert matches, f"missing Forth definition {name}"
    return matches[0]


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions), needles


def test_ruip_public_request_and_output_abis_are_exact_and_caller_bounded() -> None:
    source = PLANNER.read_text(encoding="utf-8")
    engine = ENGINE.read_text(encoding="utf-8")
    claims = CLAIMS.read_text(encoding="utf-8")

    assert "PROVIDED akashic-tui-rterm-ruip" in source
    for value, name in enumerate(("RUIP-S-OK", "RUIP-S-CAPACITY", "RUIP-S-INVALID")):
        assert re.search(rf"(?m)^{value}\s+CONSTANT\s+{name}\b", source)
    assert "3 U<" in _definition(source, "RUIP-STATUS-VALID?")
    assert "192 CONSTANT RUIP-REQUEST-SIZE" in source
    assert "80 CONSTANT RUIP-CORRELATION-SIZE" in source
    assert "72 CONSTANT RTE-INSTRUMENT-PLAN-SIZE" in engine
    assert "96 CONSTANT RTE-INSTRUMENT-REGION-SIZE" in engine
    assert "208 CONSTANT RTE-INSTRUMENT-SIZE" in engine
    assert "80 CONSTANT RUCL-CLAIM-SIZE" in claims

    offsets = {
        "ATTACHMENT": 0,
        "OWNER": 8,
        "OWNER-GEN": 16,
        "SURFACE-W": 24,
        "SURFACE-H": 32,
        "FIRST-REGION": 40,
        "FIRST-ITEM": 48,
        "DESCRIPTORS-A": 56,
        "DESCRIPTORS-U": 64,
        "NATIVE-A": 72,
        "NATIVE-U": 80,
        "PLAN-A": 88,
        "PLAN-U": 96,
        "REGIONS-A": 104,
        "REGIONS-U": 112,
        "ITEMS-A": 120,
        "ITEMS-U": 128,
        "UNITS-A": 136,
        "UNITS-U": 144,
        "CLAIMS-A": 152,
        "CLAIMS-U": 160,
        "CORR-A": 168,
        "CORR-U": 176,
        "RESERVED": 184,
    }
    for field, offset in offsets.items():
        body = _definition(source, f"_RUIP-Q.{field}")
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]

    public = re.sub(r"\s+", " ", _definition(source, "RUIP-BUILD"))
    assert (
        "( request -- region-count instrument-count unit-bytes claim-count "
        "last-region-id last-instrument-id status )" in public
    )
    for setter in (
        "RUIP-REQUEST-CLEAR",
        "RUIP-REQUEST-IDENTITY!",
        "RUIP-REQUEST-SURFACE!",
        "RUIP-REQUEST-SOURCE!",
        "RUIP-REQUEST-PLAN!",
        "RUIP-REQUEST-AUXILIARY!",
    ):
        assert _definition(source, setter)

    # Capacities come only from the supplied spans; there is no product count.
    capacities = _definition(source, "_RUIP-CAPACITIES?")
    for output, stride in (
        ("REGIONS", "RTE-INSTRUMENT-REGION-SIZE"),
        ("ITEMS", "RTE-INSTRUMENT-SIZE"),
        ("CLAIMS", "RUCL-CLAIM-SIZE"),
        ("CORR", "RUIP-CORRELATION-SIZE"),
    ):
        assert f"_RUIP-{output}-U @ {stride} /" in capacities
    assert not re.search(r"(?m)^\d+\s+CONSTANT\s+_RUIP-MAX", source)


def test_ruip_preserves_relation_native_and_retained_identity_namespaces() -> None:
    source = PLANNER.read_text(encoding="utf-8")

    correlation_offsets = {
        "ATTACHMENT": 0,
        "SOURCE": 8,
        "INDEX": 16,
        "SOURCE-GEN": 24,
        "RELATION-ROOT": 32,
        "NATIVE-ROOT": 40,
        "NATIVE-OBJECT": 48,
        "REGION-ID": 56,
        "INSTRUMENT-ID": 64,
        "RESERVED": 72,
    }
    for field, offset in correlation_offsets.items():
        body = _definition(source, f"_RUIP-X.{field}")
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]

    write = _definition(source, "_RUIP-WRITE-CORRELATION")
    for source_accessor, output_field in (
        ("UDGSN-DESCRIPTOR-ROOT-KEY@", "_RUIP-X.RELATION-ROOT"),
        ("UDG-ROOT-KEY@", "_RUIP-X.NATIVE-ROOT"),
        ("UDG-RECORD-KEY@", "_RUIP-X.NATIVE-OBJECT"),
        ("_RUIP-CURRENT-REGION @", "_RUIP-X.REGION-ID"),
        ("_RUIP-CURRENT-ITEM @", "_RUIP-X.INSTRUMENT-ID"),
    ):
        assert source_accessor in write
        assert output_field in write
    assert "UDGSN-DESCRIPTOR-ROOT-KEY@ _RUIP-CURRENT-REGION" not in source
    assert "UDG-RECORD-KEY@ _RUIP-CURRENT-ITEM" not in source

    emit_graph = _definition(source, "_RUIP-EMIT-GRAPH?")
    emit_one = _definition(source, "_RUIP-EMIT-ONE?")
    assert "_RUIP-FIRST-REGION @ _RUIP-REGION-I @ _RUIP-UADD?" in emit_graph
    assert "_RUIP-FIRST-ITEM @ _RUIP-ITEM-I @ _RUIP-UADD?" in emit_one
    assert "_RUIP-GRAPH @ UDG-FIRST-RECORD" in emit_graph

    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())
    for forbidden in (
        "DESK-",
        "AHOST-",
        "ASHELL-",
        "PAD-",
        "DAYBOOK-",
        "SOUNDLAB-",
        "WORLD-",
        "OBS-",
        "RTE-REGION-DEFINE",
        "RTE-INSTRUMENT-DEFINE",
        "RTE-HYBRID-PREFLIGHT",
    ):
        assert forbidden not in code
    assert not re.search(r"(?m)(?:^|\s)(?:ALLOCATE|FREE|RESIZE)(?:\s|$)", code)


def test_ruip_proves_all_authority_before_source_reads_or_output_mutation() -> None:
    source = PLANNER.read_text(encoding="utf-8")
    body = _definition(source, "_RUIP-BUILD-BODY")
    authority = _definition(source, "_RUIP-RANGE-AUTHORITY?")
    shapes = _definition(source, "_RUIP-SPANS-SHAPED?")

    for bank, stride in (
        ("DESCRIPTORS", "UDGSN-DESCRIPTOR-SIZE"),
        ("REGIONS", "RTE-INSTRUMENT-REGION-SIZE"),
        ("ITEMS", "RTE-INSTRUMENT-SIZE"),
        ("CLAIMS", "RUCL-CLAIM-SIZE"),
        ("CORR", "RUIP-CORRELATION-SIZE"),
    ):
        assert f"_RUIP-{bank}-U @ {stride} MOD" in shapes
    for proof in (
        "_RUIP-REQUEST-DISJOINT?",
        "_RUIP-SOURCE-DISJOINT-MUTABLE?",
        "_RUIP-MUTABLE-SPANS-DISJOINT?",
        "_RUIP-ALL-SPANS-OWNED-DISJOINT?",
        "_RUIP-ALL-SPANS-UDG-DISJOINT?",
    ):
        assert proof in authority
    _ordered(
        body,
        "_RUIP-RANGE-AUTHORITY? 0=",
        "_RUIP-SCALARS?",
        "_RUIP-VALIDATE-AND-MEASURE?",
        "_RUIP-CAPACITIES?",
        "_RUIP-CLEAR-MEASURED-OUTPUT",
        "_RUIP-EMIT?",
    )
    assert "_RUIP-CLEAR-OUTPUT" not in body

    public = _definition(source, "RUIP-BUILD")
    span_at = public.index("RUIP-REQUEST-SIZE _RUIP-OPTIONAL-ALIGNED-SPAN?")
    owned_at = public.index("RUIP-REQUEST-SIZE _RUIP-OWNED-DISJOINT?")
    udg_at = public.index("RUIP-REQUEST-SIZE _RUIP-UDG-DISJOINT?")
    catch_at = public.index("['] _RUIP-BUILD-BODY CATCH")
    final_scrub_at = public.rindex("_RUIP-SCRUB")
    assert span_at < owned_at < udg_at < catch_at < final_scrub_at
    assert public.count("_RUIP-SCRUB") == 4


def test_ruip_authenticates_dense_canonical_frozen_graphs_once() -> None:
    source = PLANNER.read_text(encoding="utf-8")
    order = _definition(source, "_RUIP-DESCRIPTOR-ORDER?")
    native = _definition(source, "_RUIP-DESCRIPTOR-NATIVE?")
    summary = _definition(source, "_RUIP-SUMMARY-CORRELATES?")
    validate = _definition(source, "_RUIP-VALIDATE-AND-MEASURE?")

    assert "UDGSN-DESCRIPTOR-SOURCE-INDEX@" in order
    assert "_RUIP-PRIOR-INDEX @ U<" in order
    assert "UDGSN-DESCRIPTOR-ROOT-KEY@" in order
    assert "_RUIP-PRIOR-RELATION @ U> 0=" in order
    assert "UDGSN-DESCRIPTOR-SOURCE-GENERATION@" in order
    assert "_RUIP-PRIOR-GENERATION @ <>" in order

    _ordered(
        native,
        "UDGSN-DESCRIPTOR-NATIVE-OFFSET@",
        "_RUIP-EXPECTED-NATIVE @ <>",
        "UDGSN-DESCRIPTOR-ENTRY-BYTES@",
        "_RUIP-DESCRIPTOR @ _RUIP-NATIVE-A @ UDGSN-DESCRIPTOR-NATIVE",
        "UDG-ENTRY-VALIDATE",
        "_RUIP-SUMMARY-CORRELATES?",
    )
    for field in (
        "ENTRY-BYTES",
        "ROOT-KEY",
        "OBJECT-COUNT",
        "SERIES-COUNT",
        "SAMPLE-SLOTS",
        "UTF8-BYTES",
    ):
        assert f"UDG-SUMMARY-{field}@" in summary
    assert "_RUIP-EXPECTED-NATIVE @ _RUIP-NATIVE-U @ <>" in validate
    assert validate.count("_RUIP-DESCRIPTOR?") == 1
    assert validate.count("_RUIP-MEASURE-GRAPH?") == 1


def test_ruip_preserves_raw_geometry_and_claims_only_clipped_visible_cells() -> None:
    source = PLANNER.read_text(encoding="utf-8")
    geometry = _definition(source, "_RUIP-DESCRIPTOR-ROOT-GEOMETRY?")
    clip = _definition(source, "_RUIP-DESCRIPTOR-CLIP?")
    rich_visible = _definition(source, "_RUIP-GRAPH-RICH-VISIBLE?")
    measure = _definition(source, "_RUIP-MEASURE-GRAPH?")
    region = _definition(source, "_RUIP-WRITE-REGION")
    instrument = _definition(source, "_RUIP-WRITE-INSTRUMENT?")
    object_clip = _definition(source, "_RUIP-OBJECT-CLIP?")
    maybe_claim = _definition(source, "_RUIP-MAYBE-WRITE-CLAIM")
    emit = _definition(source, "_RUIP-EMIT-GRAPH?")

    assert "UDGSN-DESCRIPTOR-ROW@" in geometry
    assert "UDGSN-DESCRIPTOR-COLUMN@" in geometry
    assert geometry.count("_RUIP-I32?") == 2
    assert geometry.count("_RUIP-POS-U32?") == 2
    assert geometry.count("_RUIP-SADD?") == 2
    for relation in (
        "_RUIP-SURFACE-H @ U>",
        "_RUIP-SURFACE-W @ U>",
        "_RUIP-CLIP-ROW @ _RUIP-ROOT-ROW @ <",
        "_RUIP-CLIP-COL @ _RUIP-ROOT-COL @ <",
        "_RUIP-CLIP-ROW-END @ _RUIP-ROOT-ROW-END @ >",
        "_RUIP-CLIP-COL-END @ _RUIP-ROOT-COL-END @ >",
    ):
        assert relation in clip

    for source_value, target in (
        ("_RUIP-ROOT-COL @", "_RTE-IR.X"),
        ("_RUIP-ROOT-ROW @", "_RTE-IR.Y"),
        ("_RUIP-ROOT-W @", "_RTE-IR.COLS"),
        ("_RUIP-ROOT-H @", "_RTE-IR.ROWS"),
        ("_RUIP-CLIP-COL @", "_RTE-IR.CLIP-X"),
        ("_RUIP-CLIP-ROW @", "_RTE-IR.CLIP-Y"),
    ):
        assert source_value in region
        assert target in region
    assert "_RUIP-REGION-CLIPPED?" in region
    assert "RTE-REGION-CLIPPED OR" in region

    for accessor, target in (
        ("UDG-OBJECT-ROW@", "_RTE-INSTRUMENT.ROW"),
        ("UDG-OBJECT-COLUMN@", "_RTE-INSTRUMENT.COL"),
        ("UDG-OBJECT-HEIGHT@", "_RTE-INSTRUMENT.HEIGHT"),
        ("UDG-OBJECT-WIDTH@", "_RTE-INSTRUMENT.WIDTH"),
        ("UDG-OBJECT-Z@", "_RTE-INSTRUMENT.Z"),
    ):
        assert accessor in instrument
        assert target in instrument
    assert " MAX " in object_clip
    assert " MIN " in object_clip
    assert rich_visible.count("UDG-ROOT-STATE@") == 1
    assert "DUP UDG-STATE-VISIBLE AND 0<>" in rich_visible
    assert "SWAP UDG-STATE-ENABLED AND 0<> AND" in rich_visible
    for phase in (measure, emit):
        assert (
            "_RUIP-GRAPH @ _RUIP-GRAPH-RICH-VISIBLE? "
            "_RUIP-ROOT-VISIBLE !" in phase
        )
        assert "UDG-STATE-VISIBLE AND" not in phase
    assert "_RUIP-ROOT-VISIBLE @ IF RTE-REGION-VISIBLE ELSE 0 THEN" in region
    assert "_RUIP-ROOT-VISIBLE @ IF" in instrument
    assert "_RUIP-ROOT-VISIBLE @ 0=" in maybe_claim
    assert "UDG-OBJECT-VISIBLE AND 0=" in maybe_claim
    assert "_RUIP-OBJECT-CLIP? IF _RUIP-WRITE-CLAIM" in maybe_claim


def test_ruip_maps_all_current_instruments_and_failure_clears_tentative_claims() -> None:
    source = PLANNER.read_text(encoding="utf-8")
    kind = _definition(source, "_RUIP-KIND>RTE")
    readout_mode = _definition(source, "_RUIP-READOUT-MODE>RTE")
    meter_mode = _definition(source, "_RUIP-METER-MODE>RTE")
    status_mode = _definition(source, "_RUIP-STATUS-MODE>RTE")
    instrument = _definition(source, "_RUIP-WRITE-INSTRUMENT?")
    readout = _definition(source, "_RUIP-WRITE-READOUT?")
    unit = _definition(source, "_RUIP-WRITE-UNIT?")
    clear = _definition(source, "_RUIP-CLEAR-OUTPUT")
    measured = _definition(source, "_RUIP-CLEAR-MEASURED-OUTPUT")
    fail = _definition(source, "_RUIP-FAIL-RESULT")
    body = _definition(source, "_RUIP-BUILD-BODY")

    for udg, rte in (
        ("UDG-K-READOUT", "RTE-INSTRUMENT-READOUT"),
        ("UDG-K-METER", "RTE-INSTRUMENT-METER"),
        ("UDG-K-STATUS", "RTE-INSTRUMENT-STATUS"),
    ):
        assert udg in kind and rte in kind
        assert udg in instrument
    for udg, rte in (
        ("UDG-READOUT-INTEGER", "RTE-READOUT-INTEGER"),
        ("UDG-READOUT-FIXED", "RTE-READOUT-FIXED"),
        ("UDG-READOUT-PERCENT", "RTE-READOUT-PERCENT"),
    ):
        assert udg in readout_mode and rte in readout_mode
    for udg, rte in (
        ("UDG-METER-HORIZONTAL", "RTE-METER-HORIZONTAL"),
        ("UDG-METER-VERTICAL", "RTE-METER-VERTICAL"),
    ):
        assert udg in meter_mode and rte in meter_mode
    for udg, rte in (
        ("UDG-STATUS-CIRCLE", "RTE-STATUS-CIRCLE"),
        ("UDG-STATUS-SQUARE", "RTE-STATUS-SQUARE"),
        ("UDG-STATUS-DIAMOND", "RTE-STATUS-DIAMOND"),
    ):
        assert udg in status_mode and rte in status_mode

    assert "UDG-READOUT-FORMATTED-BYTES?" in readout
    assert "_RTE-INSTRUMENT.FORMATTED-U" in readout
    assert "UDG-READOUT-UNIT@" in unit
    assert "UDG-READOUT-UNIT " not in unit
    assert " MOVE" in unit
    assert "_RTE-INSTRUMENT.UNIT-A" in unit
    assert "_RTE-INSTRUMENT.UNIT-U" in unit

    for bank in ("PLAN", "REGIONS", "ITEMS", "UNITS", "CLAIMS", "CORR"):
        assert f"_RUIP-{bank}-U @ ?DUP IF" in clear
    _ordered(fail, "_RUIP-CLEAR-OUTPUT", "0 0 0 0 0 0 _RUIP-STATUS @")
    assert "_RUIP-ITEM-COUNT @ 0= IF EXIT THEN" in measured
    for extent in (
        "_RUIP-PLAN-A @ RTE-INSTRUMENT-PLAN-SIZE 0 FILL",
        "_RUIP-REGION-COUNT @ RTE-INSTRUMENT-REGION-SIZE *",
        "_RUIP-ITEM-COUNT @ RTE-INSTRUMENT-SIZE *",
        "_RUIP-UNIT-BYTES @",
        "_RUIP-CLAIM-COUNT @ RUCL-CLAIM-SIZE *",
        "_RUIP-ITEM-COUNT @ RUIP-CORRELATION-SIZE *",
    ):
        assert extent in measured
    for capacity in (
        "_RUIP-PLAN-U",
        "_RUIP-REGIONS-U",
        "_RUIP-ITEMS-U",
        "_RUIP-UNITS-U",
        "_RUIP-CLAIMS-U",
        "_RUIP-CORR-U",
    ):
        assert capacity not in measured
    _ordered(
        body,
        "_RUIP-VALIDATE-AND-MEASURE?",
        "_RUIP-CAPACITIES?",
        "_RUIP-CLEAR-MEASURED-OUTPUT",
        "_RUIP-EMIT?",
    )
    emit_one = _definition(source, "_RUIP-EMIT-ONE?")
    emit = _definition(source, "_RUIP-EMIT?")
    _ordered(
        emit_one,
        "_RUIP-WRITE-INSTRUMENT?",
        "_RUIP-WRITE-CORRELATION",
        "_RUIP-MAYBE-WRITE-CLAIM",
    )
    _ordered(
        emit,
        "_RUIP-EMIT-GRAPH?",
        "_RUIP-WRITE-PLAN",
    )
