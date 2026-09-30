"""Execute the production static STATUS_FIELD lane and immutable neutral graph.

The neutral engine is loaded unchanged; only provider callbacks are bounded
spies. Every case runs against both semantic execution backends.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import struct
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
RICH = ROOT / "akashic/tui/rich-terminal"
PAIRED = ROOT.parent / ROOT.name.replace("akashic-", "megapad-", 1)
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PAIRED))
sys.path.insert(0, str(MEGAPAD_ROOT))
from simulator.runtime import MegaForthRuntime  # noqa: E402
from tests.simulator.test_kdos_exceptions import _load_exceptions  # noqa: E402

MASK = (1 << 64) - 1
SENTINEL = 0x1827364554637281
SOURCE = (RICH / "engine.f").read_text()


def _word(source, name):
    source = re.sub(r"(?m)\\[^\n]*$", "", source)
    return re.search(r"(?ms)^: " + re.escape(name) + r"\s.*?;", source).group(0)


def _offset(name):
    match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", _word(SOURCE, name))
    return int(match[1] or 0)


def _clean(source):
    return "\n".join(line for line in source.splitlines()
                     if not line.strip().startswith(("PROVIDED ", "REQUIRE ")))


class StaticHarness:
    def __init__(self, backend):
        self.runtime = _load_exceptions(MegaForthRuntime(execution_backend=backend))
        source = []
        for name in ("uint-range.f", "memory-span.f"):
            source.append(_clean((ROOT / "akashic/utils" / name).read_text()))
        source.append(_word((ROOT / "akashic/utils/string.f").read_text(), "/STRING"))
        source.append(_clean(SOURCE))
        source.append("""
VARIABLE SF-CALLS
VARIABLE SF-STATUS
: SF-DISJOINT ( a u context -- flag ) DROP 2DROP -1 ;
: SF-CALLBACK ( record context -- status ) 2DROP 1 SF-CALLS +! SF-STATUS @ ;
""")
        self.runtime.evaluate("\n".join(source).encode(),
                              source_name="production-static-engine.f",
                              step_budget=8_000_000)
        self.serial = 0
        self.spans = []
        self.facade = self.allocate(bytes(216))
        callback = self.runtime.find("SF-CALLBACK").xt
        fields = [0x5254454641434144, 0, 216, self.facade, 1,
                  self.runtime.find("SF-DISJOINT").xt] + [callback] * 21
        self.write(self.facade, struct.pack("<27Q", *fields))

    def call(self, word, *inputs, readonly=True):
        stack = self.runtime.main_context.data
        assert stack.snapshot() == ()
        before = [(a, self.read(a, u)) for a, u in self.spans] if readonly else []
        for value in (SENTINEL, *inputs):
            stack.push(value)
        self.runtime.execute(word, step_budget=3_000_000)
        values = stack.snapshot()
        stack.clear()
        assert values[0] == SENTINEL, (word, values)
        assert self.runtime.main_context.returns.snapshot() == (), word
        for a, payload in before:
            assert self.read(a, len(payload)) == payload
        return values[1:]

    def read(self, address, length):
        return self.runtime.memory.read_bytes(address, length)

    def write(self, address, payload):
        self.runtime.memory.write_bytes(address, payload)

    def cell(self, address, value):
        self.runtime.memory.write64(address, value & MASK)

    def variable(self, name, value=None):
        address = self.runtime.find(name).body_address
        if value is None:
            return self.runtime.memory.read64(address)
        self.cell(address, value)

    def allocate(self, payload):
        self.serial += 1
        word = self.runtime.define_created(f"SF-MEM-{self.serial}",
                                           initial_body=bytes(len(payload) + 23))
        start = (word.body_address + 7) & -8
        address = start + 8
        self.write(start, b"LEFTEDGE" + payload + b"RIGHTEND")
        self.spans.append((start, len(payload) + 16))
        return address

    def record(self, prefix, length, fields):
        payload = bytearray(length)
        for name, value in fields.items():
            struct.pack_into("<Q", payload, _offset(prefix + "." + name), value & MASK)
        return self.allocate(payload)

    def status_fields(self, label=b"Ready", value=b"online", **changes):
        text = label + value
        address = self.allocate(text) if text else 0
        fields = dict(OWNER=1, GENERATION=2, ID=3, KIND=1, VISIBLE=-1,
                      REGION=1, HEIGHT=1, WIDTH=20, **{"ROOT-HEIGHT": 24,
                      "ROOT-WIDTH": 80, "LABEL-COLS": 6, "LABEL-A": address if label else 0,
                      "LABEL-U": len(label), "VALUE-A": address + len(label) if value else 0,
                      "VALUE-U": len(value)})
        fields.update(changes)
        return fields, address, len(text)

    def static(self, label=b"Ready", value=b"online", **changes):
        fields, _, _ = self.status_fields(label, value, **changes)
        return self.record("_RTE-STATIC", 176, fields)

    def graph(self, label=b"Ready", value=b"online", **changes):
        fields, text_a, text_u = self.status_fields(label, value, **changes)
        item = self.record("_RTE-STATIC", 176, fields)
        header = dict(OWNER=1, GENERATION=2, **{"SURFACE-COLS": 80,
                      "SURFACE-ROWS": 24, "REGION-ID": 1, "REGION-COLS": 80,
                      "REGION-ROWS": 24, "ITEMS-A": item, "ITEMS-U": 176})
        plan = self.record("_RTE-SP", 144, header)
        hybrid = self.record("_RTE-HP", 144, {"ATTEMPT": 1,
                             "SOURCE-GENERATION": 1, "SURFACE-GENERATION": 1,
                             "STATIC-PLAN": plan, "STATIC-BYTES-A": text_a,
                             "STATIC-BYTES-U": text_u})
        admission = self.allocate(b"A" * 376)
        return item, plan, hybrid, admission


@pytest.fixture(scope="module", params=("python", "native"))
def static(request):
    return StaticHarness(request.param)


@pytest.mark.parametrize("label,value,changes", [
    (b"", b"", {"LABEL-COLS": 0}),
    (b"", b"up", {"LABEL-COLS": 0}),
    (b"label", b"", {"LABEL-COLS": 20}),
    ("État".encode(), "prêt ✓".encode(), {"SEVERITY": 4, "EMPHASIZED": -1}),
    (b"hidden", b"retained", {"VISIBLE": 0, "COL": -20, "ROW": -1}),
])
def test_static_accepts_independent_clean_fields(static, label, value, changes):
    record = static.static(label, value, **changes)
    assert static.call("RTE-STATIC-VALID?", record) == (MASK,)


@pytest.mark.parametrize("field,value", [
    ("OWNER", 0), ("GENERATION", 0), ("ID", 0), ("REGION", 0),
    ("KIND", 2), ("PARENT", 1), ("RESERVED", 1),
    ("HEIGHT", 0), ("HEIGHT", 2), ("WIDTH", 0), ("WIDTH", 1 << 32),
    ("ROOT-HEIGHT", 0), ("ROOT-WIDTH", 0), ("SEVERITY", 5), ("SEVERITY", -1),
    ("VISIBLE", 1), ("EMPHASIZED", 1), ("LABEL-COLS", -1),
    ("LABEL-COLS", 0), ("LABEL-COLS", 20), ("LABEL-COLS", 21),
    ("ROW", 1 << 31), ("COL", -(1 << 31) - 1), ("Z", 1 << 31),
    ("LABEL-A", 0), ("VALUE-A", 0), ("LABEL-U", 1 << 32),
])
def test_static_rejects_invalid_scalar_and_span_fields(static, field, value):
    record = static.static(**{field: value})
    assert static.call("RTE-STATIC-VALID?", record) == (0,)


@pytest.mark.parametrize("bad", [
    b"\0", b"\x01", b"\x1f", b"\x7f", b"\n", b"\r", b"\t",
    b"\xc2\x80", b"\xc2\x9f", b"\xe2\x80\xa8", b"\xe2\x80\xa9",
    b"\x80", b"\xc0\x80", b"\xc2", b"\xe0\x80\x80",
    b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xf0\x90\x80",
])
@pytest.mark.parametrize("side", ("label", "value"))
def test_status_fields_reject_controls_and_bad_utf8_independently(static, bad, side):
    record = static.static(**{side: bad})
    assert static.call("RTE-STATIC-VALID?", record) == (0,)


def test_field_boundary_cannot_complete_a_utf8_scalar(static):
    record = static.static(b"\xc2", b"\xa0")
    assert static.call("RTE-STATIC-VALID?", record) == (0,)


@pytest.mark.parametrize("word", ("RTE-STATIC-DEFINE", "RTE-STATIC-REPLACE"))
def test_static_dispatches_only_after_full_span_authority(static, word):
    record = static.static()
    static.variable("SF-CALLS", 0)
    static.variable("SF-STATUS", 0)
    assert static.call(word, record, static.facade) == (0,)
    assert static.variable("SF-CALLS") == 1
    static.cell(record + _offset("_RTE-STATIC.LABEL-A"), record + 8)
    assert static.call(word, record, static.facade) == (5,)
    assert static.variable("SF-CALLS") == 1
    owned = static.call("_RTE-HPV-OWNED-START")[0]
    static.cell(record + _offset("_RTE-STATIC.LABEL-A"), owned)
    assert static.call(word, record, static.facade) == (5,)
    assert static.variable("SF-CALLS") == 1


def test_static_only_hybrid_returns_exact_base_and_independent_aggregates(static):
    item, plan, hybrid, admission = static.graph("État".encode(), b"ok")
    static.variable("SF-CALLS", 0)
    static.variable("SF-STATUS", 0)
    sources = [(a, static.read(a, n)) for a, n in ((item, 176), (plan, 144), (hybrid, 144))]
    assert static.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, static.facade,
                       readonly=False) == (0,)
    assert static.variable("SF-CALLS") == 1
    for a, payload in sources:
        assert static.read(a, len(payload)) == payload
    summary = struct.unpack("<47Q", static.read(admission, 376))
    assert summary[:15] == (1, 2, 80, 24, 1, 0, 0, 80, 24, 0, 0, 0, 0, 0, 0)
    assert summary[15:40] == (0,) * 25
    assert summary[40:] == (1, 7, 8, 7, 3, 184, 1)


@pytest.mark.parametrize("mutation", ("bank-short", "outside", "unaligned-record",
                                      "plan-alias", "bank-alias", "admission-alias",
                                      "scratch-bank", "bad-text", "bad-root"))
def test_static_hybrid_refuses_bad_graph_before_provider_and_output(static, mutation):
    item, plan, hybrid, admission = static.graph()
    static.variable("SF-CALLS", 0)
    if mutation == "bank-short":
        static.cell(hybrid + _offset("_RTE-HP.STATIC-BYTES-U"), 10)
    elif mutation == "outside":
        static.cell(item + _offset("_RTE-STATIC.VALUE-A"), static.allocate(b"online"))
    elif mutation == "unaligned-record":
        static.cell(plan + _offset("_RTE-SP.ITEMS-A"), item + 1)
    elif mutation == "plan-alias":
        static.cell(plan + _offset("_RTE-SP.ITEMS-A"), plan)
    elif mutation == "bank-alias":
        static.cell(hybrid + _offset("_RTE-HP.STATIC-BYTES-A"), item)
    elif mutation == "admission-alias":
        admission = hybrid
    elif mutation == "scratch-bank":
        static.cell(hybrid + _offset("_RTE-HP.STATIC-BYTES-A"),
                    static.call("_RTE-HPV-OWNED-START")[0])
    elif mutation == "bad-text":
        a = static.runtime.memory.read64(item + _offset("_RTE-STATIC.LABEL-A"))
        static.write(a, b"\n")
    elif mutation == "bad-root":
        static.cell(item + _offset("_RTE-STATIC.ROOT-WIDTH"), 79)
    assert static.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, static.facade) == (5,)
    assert static.variable("SF-CALLS") == 0


def test_failed_provider_does_not_publish_checked_summary(static):
    _, _, hybrid, admission = static.graph()
    static.variable("SF-STATUS", 2)
    assert static.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, static.facade) == (2,)
    static.variable("SF-STATUS", 0)


def test_status_only_capability_has_core_dependency_and_no_glyph_dependency(static):
    limits = [0x401, 1, 1, 1, 0, 1, 0, 2, 296, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 96]
    record = static.allocate(struct.pack("<21Q", *limits))
    assert static.call("RTE-LIMITS-VALID?", record) == (MASK,)
    static.cell(record, 0x400)
    assert static.call("RTE-LIMITS-VALID?", record) == (0,)


def test_static_abi_is_separate_from_instruments():
    assert "176 CONSTANT RTE-STATIC-SIZE" in SOURCE
    assert "144 CONSTANT RTE-STATIC-PLAN-SIZE" in SOURCE
    assert "144 CONSTANT RTE-HYBRID-PLAN-SIZE" in SOURCE
    assert "376 CONSTANT RTE-HYBRID-ADMISSION-SIZE" in SOURCE
    assert "216 CONSTANT RTE-FACADE-SIZE" in SOURCE
    body = _word(SOURCE, "_RTE-HPV-STATIC?")
    assert "INSTRUMENT" not in body
    assert body.count("_RTE-SPV-ITEM?") == 1
    assert "_RTE-HA.STATIC-COPY !" in body
    assert "_RTE-HA.STATIC-OPS !" in body


def test_static_copy_padding_and_last_id_are_per_item_not_quota(static):
    _, plan, hybrid, admission = static.graph(b"", b"")
    text = static.allocate(b"AB")
    records = []
    for ordinal, identity in enumerate((3, 900)):
        fields, _, _ = static.status_fields(b"A", b"", ID=identity,
                                            **{"LABEL-A": text + ordinal})
        item = static.record("_RTE-STATIC", 176, fields)
        records.append(static.read(item, 176))
    items = static.allocate(b"".join(records))
    static.cell(plan + _offset("_RTE-SP.ITEMS-A"), items)
    static.cell(plan + _offset("_RTE-SP.ITEMS-U"), 352)
    static.cell(hybrid + _offset("_RTE-HP.STATIC-BYTES-A"), text)
    static.cell(hybrid + _offset("_RTE-HP.STATIC-BYTES-U"), 2)
    assert static.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, static.facade,
                       readonly=False) == (0,)
    summary = struct.unpack("<47Q", static.read(admission, 376))
    assert summary[40:] == (2, 2, 16, 1, 900, 368, 2)
    static.cell(items + 176 + _offset("_RTE-STATIC.ID"), 3)
    assert static.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, static.facade) == (5,)


@pytest.mark.parametrize("glyph_id,region_width,expected", [(4, 80, 0), (3, 80, 5), (4, 79, 5)])
def test_static_and_glyph_lanes_share_root_and_order_identity_ranges(
        static, glyph_id, region_width, expected):
    _, plan, hybrid, admission = static.graph()
    glyph = static.record("_RTE-LPI", 120, {"OBJECT": glyph_id,
                          "HEIGHT": 1, "WIDTH": 1, "ROOT-HEIGHT": 24,
                          "ROOT-WIDTH": region_width, "VISIBLE": -1,
                          "TEXT-CAPACITY": 1})
    header = bytearray(static.read(plan, 144))
    struct.pack_into("<Q", header, _offset("_RTE-LP.REGION-COLS"), region_width)
    struct.pack_into("<Q", header, _offset("_RTE-LP.ITEMS-A"), glyph)
    struct.pack_into("<Q", header, _offset("_RTE-LP.ITEMS-U"), 120)
    glyph_plan = static.allocate(header)
    refs = static.allocate(struct.pack("<QQ", 0, 1))
    text = static.allocate(b"x")
    for field, value in {"GLYPH-PLAN": glyph_plan, "GLYPH-REFS-A": refs,
                         "GLYPH-REFS-U": 16, "GLYPH-TEXT-A": text,
                         "GLYPH-TEXT-U": 1}.items():
        static.cell(hybrid + _offset("_RTE-HP." + field), value)
    static.variable("SF-CALLS", 0)
    assert static.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, static.facade,
                       readonly=bool(expected)) == (expected,)
    assert static.variable("SF-CALLS") == (expected == 0)
    if expected == 0:
        summary = struct.unpack("<47Q", static.read(admission, 376))
        assert summary[4] == 1
        assert summary[23:28] == (1, 1, 8, 1, 4)
        assert summary[40:] == (1, 11, 16, 11, 3, 192, 1)
