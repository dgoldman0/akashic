"""Bounded execution of production instrument snapshot and reuse helpers.

No Desktop boot, display, workers, or enlarged watchdog. Both semantic
executors run the same extracted production words against caller-owned banks.
"""

import re
import struct

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64, PRODUCER
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


class InstrumentHarness(GrowthHarness):
    def __init__(self, backend, extra_words=()):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        sources = [PRODUCER.read_text()]
        for relative in ("tui/rich-terminal/uidl-hybrid-adapter.f",
                         "tui/rich-terminal/residual-glyph-planner.f",
                         "tui/rich-terminal/uidl-claim-ledger.f",
                         "tui/rich-terminal/uidl-semantic-content-stx1.f",
                         "tui/uidl-menu-snapshot.f"):
            sources.append((ROOT / "akashic" / relative).read_text())
        self.definitions = _definitions("\n".join(sources))
        chunks, seen = [], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            code = re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration)
            for token in code.split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in ("_RTHP-PACK-ADMITTED-CANDIDATE", "_RTHP-PACKED-BANK?",
                     "_RTHP-PACK-INSTRUMENT-REGIONS-A", "_RTHP-PACK-INSTRUMENTS-A",
                     "_RTHP-PACK-INSTRUMENT-CORR-A", "_RTHP-PACK-INSTRUMENT-UNITS-A",
                     "_RTHP-INSTRUMENTS-REUSABLE?", "_RTHP-INSTRUMENTS-NORMALIZE",
                     *extra_words):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0

    def setup(self, *, units=b"Hz\xc2\xb0C", kinds=(1, 2, 3), controls=0):
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        count = len(kinds)
        for suffix, value in (("MAX-COLS", 8), ("MAX-ROWS", 2),
                              ("MAX-DOCUMENTS", 1), ("MAX-CONTROLS", controls),
                              ("MAX-RECORDS", controls), ("MAX-TEXT", 0),
                              ("MAX-COLLECTION-NATIVE", 0), ("MAX-COLLECTIONS", 0),
                              ("MAX-INSTRUMENTS", count),
                              ("MAX-INSTRUMENT-REGIONS", 1 if count else 0),
                              ("MAX-DGRAPH-NATIVE", len(units))):
            self.field(self.producer, "_RTHP." + suffix, value)
        self.bank_size, ok = self.results("_RTHP-TARGET-BANK-BYTES?", self.producer)
        assert ok == MASK64
        self.arena_size = self.bank_size * 2 + 4096
        self.arena = self.allocate(b"LEFTGUAR" + bytes(self.arena_size) + b"RIGHTGUA") + 8
        self.bank = self.arena
        self.other = self.bank + self.bank_size
        self.field(self.producer, "_RTHP.ARENA-A", self.arena)
        self.field(self.producer, "_RTHP.ARENA-U", self.arena_size)
        self.field(self.producer, "_RTHP.TARGET0-A", self.bank)
        self.field(self.producer, "_RTHP.TARGET1-A", self.other)
        cursor = self.other + self.bank_size
        for suffix, data in (
            ("SOURCE-DIR", bytes(self.constant("RUHA-DOCUMENT-SIZE"))),
            ("INSTRUMENT-REGIONS", struct.pack("<12Q", 8, 0, 0, 8, 2, 0, 0, 0, 0, 1, 1, 0) if count else b""),
            ("INSTRUMENTS", bytes(count * self.constant("RTE-INSTRUMENT-SIZE"))),
            ("INSTRUMENT-CORR", b"".join(struct.pack("<10Q", 1, 2, 3, 4, 5, 6, i + 1, 8, 100 + i, 0)
                                         for i in range(count))),
            ("INSTRUMENT-UNITS", units),
        ):
            self.field(self.producer, "_RTHP." + suffix + "-A", cursor)
            self.field(self.producer, "_RTHP." + suffix + "-U", len(data))
            self.runtime.memory.write_bytes(cursor, data)
            setattr(self, suffix.lower().replace("-", "_"), cursor)
            cursor += (len(data) + 7) & -8
        self.cursor = cursor
        self.field(self.producer, "_RTHP.SOURCE-DIR-USED", self.constant("RUHA-DOCUMENT-SIZE"))
        self.units = units
        self.count = count
        for index, kind in enumerate(kinds):
            unit = units if kind == 1 else b""
            fields = (1, 2, 100 + index, kind, MASK64, index, 8, 0,
                      0, index, 1, 1, 2, 8, 0xFFFFFFFF, 0, 0, 0, 0, 100,
                      42, 0, self.instrument_units if unit else 0, len(unit),
                      2 + len(unit) if unit else 0, 0)
            self.runtime.memory.write_bytes(self.instruments + index * 208, struct.pack("<26Q", *fields))
        for suffix, value in (("COLS", 8), ("ROWS", 2), ("DOCUMENT-COUNT", 1),
                              ("OWNER", 1), ("GENERATION", 2), ("REGION", 7),
                              ("FIRST-OBJECT", 100),
                              ("INSTRUMENT-REGION-COUNT", 1 if count else 0),
                              ("INSTRUMENT-COUNT", count), ("INSTRUMENT-UNIT-BYTES", len(units))):
            self.field(self.bank, "_RTHP-TB." + suffix, value)

    def packed(self, name):
        return self.results("_RTHP-PACK-" + name + "-A", self.bank)[0]

    def guards(self):
        assert self.runtime.memory.read_bytes(self.arena - 8, 8) == b"LEFTGUAR"
        assert self.runtime.memory.read_bytes(self.arena + self.arena_size, 8) == b"RIGHTGUA"
        assert self.runtime.memory.read_bytes(self.other, self.bank_size) == bytes(self.bank_size)

    def pair(self):
        self.setup()
        assert self.call("_RTHP-PACK-ADMITTED-CANDIDATE", self.bank, self.producer)
        memory = self.runtime.memory
        self.active_before = memory.read_bytes(self.bank, self.bank_size)
        memory.write_bytes(self.other, self.active_before)
        self.field(self.other, "_RTHP-TB.REGION", 17)
        self.field(self.other, "_RTHP-TB.FIRST-OBJECT", 200)
        displacement = self.other - self.bank
        self.pending_regions = self.packed("INSTRUMENT-REGIONS") + displacement
        self.pending_items = self.packed("INSTRUMENTS") + displacement
        self.pending_corr = self.packed("INSTRUMENT-CORR") + displacement
        self.pending_units = self.packed("INSTRUMENT-UNITS") + displacement
        memory.write64(self.pending_regions, 18)
        for i in range(self.count):
            memory.write64(self.pending_items + i * 208 + 16, 200 + i)
            memory.write64(self.pending_items + i * 208 + 48, 18)
            memory.write64(self.pending_corr + i * 80 + 56, 18)
            memory.write64(self.pending_corr + i * 80 + 64, 200 + i)

    def reusable(self, normalized=False):
        return self.call("_RTHP-INSTRUMENTS-REUSABLE?", self.bank, self.other,
                         MASK64 if normalized else 0)


@pytest.fixture(params=("python", "native"))
def harness(request):
    return InstrumentHarness(request.param)


def test_packed_instruments_own_exact_payload_and_offset_text(harness):
    h = harness
    h.setup()
    source = h.runtime.memory.read_bytes(h.instruments, h.count * 208)
    assert h.call("_RTHP-PACK-ADMITTED-CANDIDATE", h.bank, h.producer)
    assert h.call("_RTHP-PACKED-BANK?", h.bank, h.producer)
    expected = bytearray(source)
    struct.pack_into("<Q", expected, 176, 0)
    assert h.runtime.memory.read_bytes(h.packed("INSTRUMENTS"), len(source)) == expected
    assert h.runtime.memory.read_bytes(h.packed("INSTRUMENT-UNITS"), len(h.units)) == h.units
    assert h.runtime.memory.read_bytes(h.packed("INSTRUMENT-REGIONS"), 96) == h.runtime.memory.read_bytes(h.instrument_regions, 96)
    assert h.runtime.memory.read_bytes(h.packed("INSTRUMENT-CORR"), h.count * 80) == h.runtime.memory.read_bytes(h.instrument_corr, h.count * 80)
    snapshot = h.runtime.memory.read_bytes(h.bank, h.bank_size)
    h.runtime.memory.write_bytes(h.instruments, bytes(len(source)))
    h.runtime.memory.write_bytes(h.instrument_units, b"x" * len(h.units))
    assert h.runtime.memory.read_bytes(h.bank, h.bank_size) == snapshot
    h.guards()


def test_distinct_unit_slices_keep_their_offsets(harness):
    h = harness
    h.setup(kinds=(1, 1))
    h.runtime.memory.write64(h.instruments + 184, 2)
    h.runtime.memory.write64(h.instruments + 208 + 176, h.instrument_units + 2)
    h.runtime.memory.write64(h.instruments + 208 + 184, len(h.units) - 2)
    assert h.call("_RTHP-PACK-ADMITTED-CANDIDATE", h.bank, h.producer)
    assert h.runtime.memory.read64(h.packed("INSTRUMENTS") + 176) == 0
    assert h.runtime.memory.read64(h.packed("INSTRUMENTS") + 208 + 176) == 2
    h.guards()


@pytest.mark.parametrize("mutation", ("before_units", "past_units", "unit_overrun", "unit_wrap",
                                      "short_items", "short_regions", "short_correlations", "short_units",
                                      "too_many_items", "too_many_regions", "misaligned_items"))
def test_bad_instrument_source_never_becomes_valid(harness, mutation):
    h = harness
    h.setup()
    memory = h.runtime.memory
    if mutation in ("before_units", "past_units", "unit_wrap"):
        address = {"before_units": h.instrument_units - 1,
                   "past_units": h.instrument_units + len(h.units), "unit_wrap": MASK64}[mutation]
        memory.write64(h.instruments + 176, address)
    elif mutation == "unit_overrun":
        memory.write64(h.instruments + 184, len(h.units) + 1)
    elif mutation.startswith("short_"):
        suffix = {"items": "INSTRUMENTS", "regions": "INSTRUMENT-REGIONS",
                  "correlations": "INSTRUMENT-CORR", "units": "INSTRUMENT-UNITS"}[mutation[6:]]
        h.field(h.producer, "_RTHP." + suffix + "-U", 0)
    elif mutation == "too_many_items":
        h.field(h.bank, "_RTHP-TB.INSTRUMENT-COUNT", h.count + 1)
    elif mutation == "too_many_regions":
        h.field(h.bank, "_RTHP-TB.INSTRUMENT-REGION-COUNT", 2)
    else:
        h.field(h.producer, "_RTHP.INSTRUMENTS-A", h.instruments + 1)
    assert not h.call("_RTHP-PACK-ADMITTED-CANDIDATE", h.bank, h.producer)
    assert memory.read64(h.bank + h.offset("_RTHP-TB.VALID")) == 0
    h.guards()


@pytest.mark.parametrize("regions,items,units", ((0, 0, 0), (1, 3, 5), (4, 97, 511),
                                                (0xFFFFFFFF, 1, 0), (1, 0xFFFFFFFF, 0),
                                                (0, 0, 0xFFFFFFFF), (0, 0, MASK64)))
def test_instrument_snapshot_capacity_matches_checked_byte_oracle(harness, regions, items, units):
    actual, valid = harness.results("_RTHP-INSTRUMENT-BANK-BYTES?", regions, items, units)
    expected = regions * 96 + items * (208 + 80) + ((units + 7) & -8)
    assert bool(valid) == (expected <= 0xFFFFFFFF)
    if valid:
        assert actual == expected


def test_empty_instruments_add_no_payload(harness):
    h = harness
    h.setup(units=b"", kinds=())
    assert h.call("_RTHP-PACK-ADMITTED-CANDIDATE", h.bank, h.producer)
    assert h.call("_RTHP-PACKED-BANK?", h.bank, h.producer)
    assert h.packed("INSTRUMENT-REGIONS") == h.packed("INSTRUMENT-UNITS")
    h.guards()


def test_unchanged_instruments_rebase_only_wire_identity(harness):
    h = harness
    h.pair()
    assert h.reusable()
    assert not h.reusable(normalized=True)
    assert h.results("_RTHP-INSTRUMENTS-NORMALIZE", h.bank, h.other) == ()
    h.field(h.other, "_RTHP-TB.REGION", 7)
    assert h.reusable(normalized=True)
    for i in range(h.count):
        assert h.runtime.memory.read64(h.pending_items + i * 208 + 16) == 100 + i
        assert h.runtime.memory.read64(h.pending_items + i * 208 + 48) == 8
        assert h.runtime.memory.read64(h.pending_corr + i * 80 + 64) == 100 + i
    assert h.runtime.memory.read_bytes(h.bank, h.bank_size) == h.active_before


@pytest.mark.parametrize("offset", (0, 8, 16, 24, 32, 40, 48, 72))
def test_source_identity_and_lifecycle_changes_refuse_reuse(harness, offset):
    h = harness
    h.pair()
    memory = h.runtime.memory
    memory.write64(h.pending_corr + offset, memory.read64(h.pending_corr + offset) + 1)
    pending = memory.read_bytes(h.other, h.bank_size)
    assert not h.reusable()
    assert memory.read_bytes(h.other, h.bank_size) == pending
    assert memory.read_bytes(h.bank, h.bank_size) == h.active_before


@pytest.mark.parametrize("family,offset", (("items", 24), ("items", 32), ("items", 40),
                                          ("items", 56), ("items", 64), ("items", 112),
                                          ("items", 160), ("items", 176), ("items", 184),
                                          ("items", 192), ("regions", 8), ("regions", 40),
                                          ("regions", 72), ("regions", 80), ("units", 0)))
def test_changed_payload_or_region_requires_complete_replacement(harness, family, offset):
    h = harness
    h.pair()
    address = getattr(h, "pending_" + family) + offset
    old = h.runtime.memory.read_bytes(address, 1)
    h.runtime.memory.write_bytes(address, bytes([old[0] ^ 1]))
    assert not h.reusable()


@pytest.mark.parametrize("field", ("INSTRUMENT-COUNT", "INSTRUMENT-REGION-COUNT", "INSTRUMENT-UNIT-BYTES"))
def test_changed_instrument_membership_refuses_before_payload_access(harness, field):
    h = harness
    h.pair()
    h.field(h.other, "_RTHP-TB." + field, MASK64)
    assert not h.reusable()


class DeltaHarness(InstrumentHarness):
    """Run complete production packing, delta planning, and delayed admission.

    Only the input candidate is a fixture. No planner, header validator,
    normalization, fallback, or retry word is replaced with a test double.
    """

    def __init__(self, backend):
        super().__init__(backend, ("_RTHP-DELTA-CANDIDATE?", "_RTHP-D-PLAN-BIND?",
                                   "_RTHP-U-CLONE?", "_RTHP-U-FENCE-PLAN?",
                                   "_RTHP-U-COMMIT", "_RTHP-TARGET-PUBLISH?",
                                   "_RTHP-R-BANK-CEILING?"))

    def read(self, suffix):
        return self.runtime.memory.read64(self.producer + self.offset("_RTHP." + suffix))

    def reserve(self, suffix, size):
        address = self.cursor
        self.cursor += (size + 7) & -8
        assert self.cursor <= self.arena + self.arena_size
        self.field(self.producer, "_RTHP." + suffix + "-A", address)
        self.field(self.producer, "_RTHP." + suffix + "-U", size)
        return address

    def delta_pair(self, active=("A",), pending=("B",), *, changed_control=False):
        self.setup(controls=1)
        self.controls = self.reserve("CONTROLS", self.constant("RTE-CONTROL-SIZE"))
        self.corr = self.reserve("CORR", self.constant("RUCP-CORRELATION-SIZE"))
        self.items = self.reserve("GLYPH-ITEMS", 6 * 120)
        self.refs = self.reserve("GLYPH-REFS", 6 * 16)
        self.text = self.reserve("GLYPH-TEXT", 16)
        self.reserve("GLYPH-ID-MAP", 6 * 8)
        self.reserve("ORDER2", 24)
        for suffix, value in (("OWNER", 1), ("OWNER-GEN", 2), ("COLS", 8), ("ROWS", 2),
                              ("PHYSICAL-GEN", 3), ("DOCUMENT-COUNT", 1),
                              ("CONTROL-COUNT", 1), ("MENU-CONTROL-COUNT", 1),
                              ("INSTRUMENT-REGION-COUNT", 1),
                              ("INSTRUMENT-COUNT", 3), ("INSTRUMENT-UNITS-USED", len(self.units))):
            self.field(self.producer, "_RTHP." + suffix, value)
        self.field(self.producer + self.offset("_RTHP.LIMITS"), "_RTE-L.GLYPH-RUN-BYTES", 8)
        # One ordinary document and one menu control. The directory is real
        # and passes the production header's geometry/epoch/span checks.
        directory = (1, 1, 0, 0, 2, 8, 0, self.constant("UMSN-RECORD-SIZE"),
                     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1)
        self.runtime.memory.write_bytes(self.source_dir, struct.pack("<20Q", *directory))
        self.stage(self.bank, 100, 7, 10, active, 3)
        self.active_before = self.runtime.memory.read_bytes(self.bank, self.bank_size)
        self.frontier = 104 + len(active)
        self.stage(self.other, self.frontier, 17, 11, pending, 11 if changed_control else 3)
        for suffix, value in (("TARGET-ACTIVE", self.bank), ("TARGET-PENDING", self.other),
                              ("ACTIVE-DRAW", 10), ("NEXT-OBJECT", self.frontier)):
            self.field(self.producer, "_RTHP." + suffix, value)

    def stage(self, bank, first, region, draw, runs, state):
        memory = self.runtime.memory
        for suffix, value in (("OWNER", 1), ("GENERATION", 2), ("COLS", 8), ("ROWS", 2),
                              ("PHYSICAL-GEN", 3), ("DOCUMENT-COUNT", 1),
                              ("DRAW", draw), ("SOURCE-GEN", draw), ("CONTENT-EPOCH", draw),
                              ("REGION", region), ("FIRST-OBJECT", first),
                              ("GLYPH-RUN-LIMIT", 8), ("CONTROL-COUNT", 1),
                              ("MENU-CONTROL-COUNT", 1), ("GLYPH-SLOT-COUNT", len(runs)),
                              ("GLYPH-TEXT-USED", len(runs)),
                              ("INSTRUMENT-REGION-COUNT", 1), ("INSTRUMENT-COUNT", 3),
                              ("INSTRUMENT-UNIT-BYTES", len(self.units))):
            self.field(bank, "_RTHP-TB." + suffix, value)
        for suffix, value in (("SURFACE-GEN", draw), ("SOURCE-DRAW", draw),
                              ("SOURCE-GEN", draw), ("SOURCE-CONTENT-EPOCH", draw),
                              ("REGION", region), ("FIRST-OBJECT", first),
                              ("ATTEMPT", draw), ("GLYPH-COUNT", len(runs)),
                              ("GLYPH-TEXT-USED", len(runs))):
            self.field(self.producer, "_RTHP." + suffix, value)
        control = (1, 2, first, 1, state, 0, region, 0, 0, 0, 0, 1, 8, 2, 8,
                   0, 0, 0, 0, 0, 0, 0, 0, 0)
        memory.write_bytes(self.controls, struct.pack("<24Q", *control))
        memory.write_bytes(self.corr, struct.pack("<7Q", 1, 1, 1, 0, first, 0, 0))
        memory.write64(self.instrument_regions, region + 1)
        for index in range(3):
            memory.write64(self.instruments + index * 208 + 16, first + 1 + index)
            memory.write64(self.instruments + index * 208 + 48, region + 1)
            memory.write64(self.instrument_corr + index * 80 + 56, region + 1)
            memory.write64(self.instrument_corr + index * 80 + 64, first + 1 + index)
        for index, label in enumerate(runs):
            item = (first + 4 + index, 0, 1, index * 2, 1, 1, 2, 8, 0, MASK64,
                    0, 0, 0, 1, 0)
            memory.write_bytes(self.items + index * 120, struct.pack("<15Q", *item))
            memory.write_bytes(self.refs + index * 16, struct.pack("<2Q", index, 1))
        memory.write_bytes(self.text, "".join(runs).encode())
        assert self.call("_RTHP-PACK-CANDIDATE", bank, self.producer)
        assert self.call("_RTHP-TARGET-BANK-HEADER?", bank, self.producer)

    def assert_unchanged_active(self):
        assert self.runtime.memory.read_bytes(self.bank, self.bank_size) == self.active_before
        assert self.read("NEXT-OBJECT") == self.frontier
        assert self.read("TARGET-ACTIVE") == self.bank


@pytest.fixture(params=("python", "native"))
def delta(request):
    return DeltaHarness(request.param)


@pytest.mark.parametrize("changed_control", (False, True))
def test_mixed_delta_retains_instruments_and_only_plans_changed_objects(delta, changed_control):
    h = delta
    h.delta_pair(changed_control=changed_control)
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.read("DELTA-PLAN-CONTROLS") == int(changed_control)
    assert h.read("DELTA-PLAN-GLYPHS") == 1
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
    assert h.reusable(normalized=True)
    h.assert_unchanged_active()


def test_glyph_growth_with_instruments_uses_acknowledged_frontier(delta):
    h = delta
    h.delta_pair(pending=("A", "N", "C"))
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.read("DELTA-PLAN-GLYPHS") == 2
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
    items = h.results("_RTHP-PACK-ITEMS-A", h.other)[0]
    assert [h.runtime.memory.read64(items + i * 120) for i in range(3)] == [104, 105, 106]
    assert [h.results("_RTHP-D-PLAN-GLYPH-AT", i) for i in range(2)] == [(1, 1), (2, 1)]
    assert h.reusable(normalized=True)
    h.assert_unchanged_active()


def test_glyph_shrink_repacks_instruments_and_keeps_tombstone_ids(delta):
    h = delta
    h.delta_pair(active=("A", "B", "C"), pending=("A",))
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.read("GLYPH-COUNT") == 3
    assert h.read("DELTA-PLAN-GLYPHS") == 2
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
    assert h.reusable(normalized=True)
    h.assert_unchanged_active()


@pytest.mark.parametrize("mutation", ("value", "identity", "instrument-id", "region-id", "attempt", "active-draw"))
def test_delayed_mixed_delta_rejects_changed_instrument_or_ack_binding(delta, mutation):
    h = delta
    h.delta_pair()
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    if mutation in ("attempt", "active-draw"):
        h.field(h.producer, "_RTHP." + mutation.upper(), 99)
    else:
        name = "INSTRUMENT-CORR" if mutation == "identity" else "INSTRUMENTS"
        address = h.results("_RTHP-PACK-" + name + "-A", h.other)[0]
        offset = {"value": 160, "identity": 24, "instrument-id": 16, "region-id": 48}[mutation]
        h.runtime.memory.write64(address + offset, 99)
    assert not h.call("_RTHP-D-PLAN-BIND?", h.producer)
    h.assert_unchanged_active()


def test_changed_instrument_refuses_delta_before_normalizing_candidate(delta):
    h = delta
    h.delta_pair()
    address = h.results("_RTHP-PACK-INSTRUMENTS-A", h.other)[0]
    h.runtime.memory.write64(address + 160, 43)
    pending = h.runtime.memory.read_bytes(h.other, h.bank_size)
    assert not h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.read("DELTA-PLAN-VALID") == 0
    assert h.runtime.memory.read_bytes(h.other, h.bank_size) == pending
    h.assert_unchanged_active()


def test_unchanged_clone_keeps_instrument_offsets_and_seals_revision_fence(delta):
    h = delta
    h.delta_pair()
    h.field(h.producer, "_RTHP.TARGET-PENDING", 0)
    for name, value in (("P", h.producer), ("ACTIVE", h.bank), ("DRAW", 12),
                        ("SOURCE-GEN", 12), ("CONTENT-EPOCH", 10),
                        ("DOCUMENTS", 1), ("ATTEMPT", 12)):
        h.variable("_RTHP-U-" + name, value)
    assert h.call("_RTHP-U-CLONE?")
    assert h.call("_RTHP-U-FENCE-PLAN?")
    assert h.results("_RTHP-U-COMMIT") == ()
    assert h.read("DELTA-PLAN-CONTROLS") == 1
    assert h.read("DELTA-PLAN-GLYPHS") == 0
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
    assert h.reusable(normalized=True)
    h.assert_unchanged_active()


def test_successive_acknowledged_deltas_preserve_instrument_identity(delta):
    h = delta
    h.delta_pair(pending=("A", "N"))
    for draw, runs in ((11, ("A", "N")), (12, ("B", "N", "C"))):
        if draw == 12:
            h.bank, h.other = h.other, h.bank
            h.frontier = h.read("NEXT-OBJECT")
            h.active_before = h.runtime.memory.read_bytes(h.bank, h.bank_size)
            h.stage(h.other, h.frontier, 27, draw, runs, 3)
            h.field(h.producer, "_RTHP.TARGET-PENDING", h.other)
        assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
        assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
        h.assert_unchanged_active()
        # Invoke the real promotion used after provider physical completion;
        # the sealed/awaiting/cancel state machine is tested separately.
        h.field(h.producer, "_RTHP.PHASE", h.constant("_RTHP-PH-LIVE"))
        assert h.call("_RTHP-TARGET-PUBLISH?", h.producer)
        assert h.read("TARGET-ACTIVE") == h.other
        assert h.read("TARGET-PENDING") == 0
        assert h.read("NEXT-OBJECT") == 104 + len(runs)
        items = h.results("_RTHP-PACK-INSTRUMENTS-A", h.other)[0]
        assert [h.runtime.memory.read64(items + i * 208 + 16) for i in range(3)] == [101, 102, 103]


@pytest.mark.parametrize("bad_id", (None, 0, MASK64))
def test_instrument_ids_participate_in_safe_publication_frontier(delta, bad_id):
    h = delta
    h.setup()
    assert h.call("_RTHP-PACK-ADMITTED-CANDIDATE", h.bank, h.producer)
    h.field(h.producer, "_RTHP.NEXT-OBJECT", 100)
    h.variable("_RTHP-TP-P", h.producer)
    h.variable("_RTHP-TP-BANK", h.bank)
    if bad_id is not None:
        h.runtime.memory.write64(h.packed("INSTRUMENTS") + 2 * 208 + 16, bad_id)
    assert h.call("_RTHP-TARGET-NEXT-OBJECT?") == (bad_id is None)
    if bad_id is None:
        assert h.variable("_RTHP-TP-NEXT-OBJECT") == 103
    assert h.read("NEXT-OBJECT") == 100


def test_glyph_reserve_accounts_for_instrument_snapshot_storage(delta):
    h = delta
    h.delta_pair()
    # Occupy the maximum glyph text allowance and input-target prefix. The
    # snapshot's instrument sections must not be counted as free glyph slots.
    for suffix, value in (("ROWS", 2), ("GLYPH-TEXT-USED", 64),
                          ("DOCUMENT-COUNT", 1)):
        h.field(h.producer, "_RTHP." + suffix, value)
    h.variable("_RTHP-R-P", h.producer)
    assert h.call("_RTHP-R-BANK-CEILING?")
    assert h.variable("_RTHP-R-CEILING") == 16
