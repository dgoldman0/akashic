"""A sparse instrument region must not block disjoint FIELD value targets."""
import struct

import pytest

from test_rich_field_producer import FieldHarness
from test_rich_series_producer import PRELUDE, PRODUCER, run_series


def _field_graph(backend, documents=1):
    h = FieldHarness(backend)
    h.setup(documents=documents)
    assert h.build() == (0,)
    h.field(h.producer, "_RTHP.BASE-CLAIMS-USED", 80)
    h.field(h.producer, "_RTHP.INSTRUMENT-CLAIM-COUNT", 1)
    h.field(h.producer, "_RTHP.CLAIMS-USED", 160)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A") + 80,
                                struct.pack("<10Q", 11, 9, 1, 8, 92, 0, 0, 0, 1, 8))
    h.field(h.producer, "_RTHP.INSTRUMENT-REGION-COUNT", 1)
    r = h.get("INSTRUMENT-REGIONS-A")
    h.runtime.memory.write_bytes(r, struct.pack("<12Q", 8, 0, 0, 32, 8, 0, 0, 0, 0, 0, 1, 0))
    return h


@pytest.fixture(params=("python", "native"))
def field_graph(request):
    return _field_graph(request.param)


@pytest.fixture(params=("python", "native"))
def two_documents(request):
    return _field_graph(request.param, documents=2)


def test_sparse_graph_moves_base_above_barrier_with_authored_field_slots_unchanged(field_graph):
    h = field_graph
    controls = h.runtime.memory.read_bytes(h.get("CONTROLS-A"), 200)
    region = h.runtime.memory.read_bytes(h.get("INSTRUMENT-REGIONS-A"), 96)
    assert h.results("_RTHP-BASE-REGION-Z?", h.producer) == (1, (1 << 64) - 1)
    assert h.call("_RTHP-BASE-LAYER!", h.producer)
    plan = h.producer + h.offset("_RTHP.CONTROL-PLAN")
    assert h.runtime.memory.read64(plan + h.offset("_RTE-CP.REGION-Z")) == 1
    assert h.call("RTE-CONTROL-PLAN-VALID?", plan)
    assert h.call("_RTHP-BASE-Z-FIXED?", 1, h.producer)
    assert not h.call("_RTHP-BASE-Z-FIXED?", 0, h.producer)
    assert h.runtime.memory.read_bytes(h.get("CONTROLS-A"), 200) == controls
    assert h.runtime.memory.read_bytes(h.get("INSTRUMENT-REGIONS-A"), 96) == region
    h.results("_RTHP-WRAP-HYBRID", h.producer)
    assert h.runtime.memory.read64(plan + h.offset("_RTE-CP.REGION-Z")) == 1


def test_a_graph_beneath_its_own_documents_overlay_keeps_the_base_above_it(field_graph):
    h = field_graph
    base = h.get("CLAIMS-A")
    graph = base + 80
    # The base claim is document 11's prompt, at 255 above the graph, and the
    # graph lies under it: the prompt paints above it in either order.
    h.runtime.memory.write64(base, 11)
    h.runtime.memory.write64(base + 16, h.constant("UFLSN-SOURCE-OVERLAY"))
    h.runtime.memory.write64(base + 40, 255)
    for offset in (48, 56, 64, 72):
        h.runtime.memory.write64(graph + offset, h.runtime.memory.read64(base + offset))
    assert h.call("_RTHP-BASE-CLAIMS-DISJOINT?", h.producer)
    assert h.call("_RTHP-BASE-LAYER!", h.producer)
    # Another document's prompt is no layer above this graph.
    h.runtime.memory.write64(base, 12)
    assert not h.call("_RTHP-BASE-CLAIMS-DISJOINT?", h.producer)


def test_a_graph_beneath_an_overlay_panes_document_keeps_the_base_above_it(two_documents):
    h = two_documents
    base = h.get("CLAIMS-A")
    graph = base + 80
    # The base claim is a root of another document, token 12, and the graph
    # of document 11 lies under it.  An overlay pane's document is the layer
    # above, which the shell's regions paint after the graph's.
    h.document(1, token=12, layer=1)
    h.runtime.memory.write64(base, 12)
    for offset in (48, 56, 64, 72):
        h.runtime.memory.write64(graph + offset, h.runtime.memory.read64(base + offset))
    assert h.call("_RTHP-BASE-CLAIMS-DISJOINT?", h.producer)
    # A document of the graph's own layer is no layer above it.
    h.document(1, token=12, layer=0)
    assert not h.call("_RTHP-BASE-CLAIMS-DISJOINT?", h.producer)


@pytest.mark.parametrize("reason", ("overlap", "no-headroom", "short-region-bank"))
def test_ambiguous_overlap_or_z_exhaustion_refuses_base_reordering_before_plan_writes(field_graph, reason):
    h = field_graph
    if reason == "overlap":
        claim = h.get("CLAIMS-A") + 80
        for offset, value in ((48, 3), (56, 2), (64, 4), (72, 10)):
            h.runtime.memory.write64(claim + offset, value)
    elif reason == "no-headroom":
        h.field(h.get("INSTRUMENT-REGIONS-A"), "_RTE-IR.Z", 2147483647)
    else:
        h.field(h.producer, "_RTHP.INSTRUMENT-REGIONS-U", 95)
    plan = h.producer + h.offset("_RTHP.CONTROL-PLAN")
    before = h.runtime.memory.read_bytes(plan, 144)
    assert not h.call("_RTHP-BASE-LAYER!", h.producer)
    assert h.runtime.memory.read_bytes(plan, 144) == before


def test_authored_graph_order_survives_derived_base_z_and_all_three_plans_agree():
    run_series(PRELUDE+r'''
_PP-BUILD
-3 _PP-P _RTHP.INSTRUMENT-REGIONS-A @ _RTE-IR.Z !
7 _PP-P _RTHP.INSTRUMENT-REGIONS-A @ 96 + _RTE-IR.Z !
1 _PP-P _RTHP.CONTROL-COUNT ! 1 _PP-P _RTHP.STATIC-COUNT !
1 _PP-P _RTHP.GLYPH-COUNT !
_PP-P _RTHP-BASE-LAYER! _RP-A
_PP-P _RTHP.CONTROL-PLAN _RTE-CP.REGION-Z @ 8 = _RP-A
_PP-P _RTHP.STATIC-PLAN _RTE-SP.REGION-Z @ 8 = _RP-A
_PP-P _RTHP.GLYPH-PLAN _RTE-LP.REGION-Z @ 8 = _RP-A
_PP-P _RTHP.INSTRUMENT-REGIONS-A @ _RTE-IR.Z @ -3 = _RP-A
_PP-P _RTHP.INSTRUMENT-REGIONS-A @ 96 + _RTE-IR.Z @ 7 = _RP-A
\ An all-negative graph stack already precedes the ordinary zero base.
-1 _PP-P _RTHP.INSTRUMENT-REGIONS-A @ 96 + _RTE-IR.Z !
_PP-P _RTHP-BASE-LAYER! _RP-A
_PP-P _RTHP.CONTROL-PLAN _RTE-CP.REGION-Z @ 0= _RP-A _RP-DONE
''', minimum=25, extra_sources=PRODUCER)


def test_cross_family_overlap_and_invalid_source_propagate_before_optional_retry():
    run_series(PRELUDE+r'''
\ A generic menu/collection claim may overlap a later graph without any FIELD.
_PP-P _RTHP.CLAIMS-A @ DUP RUCL-CLAIM-SIZE 0 FILL
1 OVER _RUCL-C.ROW0 ! 2 OVER _RUCL-C.COL0 !
2 OVER _RUCL-C.ROW1 ! 3 SWAP _RUCL-C.COL1 !
RUCL-CLAIM-SIZE _PP-P _RTHP.CLAIMS-USED !
_PP-P _RTHP-W-P ! _RTHP-W-BUILD-OPTIONAL-INSTRUMENTS RTE-S-UNAVAILABLE = _RP-A
_PP-P _RTHP.INSTRUMENT-COUNT @ 5 = _RP-A
_PP-P _RTHP.FIELD-COUNT @ 0= _RP-A
\ Native graph layering is currently bounded to0..255; invalid source stays invalid.
_PP-INIT
2147483647 _PP-P _RTHP.DGRAPH-DESCRIPTORS-A @ _UDGSN-D.Z !
_PP-P _RTHP-W-P ! _RTHP-W-BUILD-OPTIONAL-INSTRUMENTS RTE-S-INVALID = _RP-A
_PP-P _RTHP.INSTRUMENT-COUNT @ 0= _RP-A _RP-DONE
''', minimum=20, extra_sources=PRODUCER)
