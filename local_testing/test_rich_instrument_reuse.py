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
        self.definitions = _definitions(PRODUCER.read_text())
        for relative in ("tui/rich-terminal/uidl-hybrid-adapter.f",
                         "tui/rich-terminal/residual-glyph-planner.f",
                         "tui/rich-terminal/uidl-claim-ledger.f"):
            source = (ROOT / "akashic" / relative).read_text()
            for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)",
                                    source):
                self.definitions[match[2]] = match[0]
            if relative.endswith("uidl-claim-ledger.f"):
                for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;[ \t]*(?:\\[^\n]*)?$", source):
                    self.definitions[match[1]] = match[0]
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
                     *extra_words):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0

    def setup(self, *, units=b"Hz\xc2\xb0C", kinds=(1, 2, 3)):
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        count = len(kinds)
        for suffix, value in (("MAX-COLS", 8), ("MAX-ROWS", 2),
                              ("MAX-DOCUMENTS", 1), ("MAX-CONTROLS", 0),
                              ("MAX-RECORDS", 0), ("MAX-TEXT", 0),
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
                              ("INSTRUMENT-REGION-COUNT", 1 if count else 0),
                              ("INSTRUMENT-COUNT", count), ("INSTRUMENT-UNIT-BYTES", len(units))):
            self.field(self.bank, "_RTHP-TB." + suffix, value)

    def packed(self, name):
        return self.results("_RTHP-PACK-" + name + "-A", self.bank)[0]

    def guards(self):
        assert self.runtime.memory.read_bytes(self.arena - 8, 8) == b"LEFTGUAR"
        assert self.runtime.memory.read_bytes(self.arena + self.arena_size, 8) == b"RIGHTGUA"
        assert self.runtime.memory.read_bytes(self.other, self.bank_size) == bytes(self.bank_size)


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
