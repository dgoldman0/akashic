"""A DELTA defines the controls that came and drops those that went.

FRAMES-FOLLOW-CHANGE 9c.2a.  When the bank on screen and the pending bank
hold different controls, the screen producer's comparison pairs them by
identity.  A pending control that no control on screen matches is defined
under the fresh identity its candidate gave it, past the producer's object
frontier, and a control on screen that no pending control matches is
dropped.  The plan lists the definitions with the controls that changed,
by their places in the pending bank, and keeps the drops beside them, by
their places on screen, ascending.  This holds for a frame built for
Desk's shell as for one that is not.  A field or a dialog that comes still
needs the frame replaced whole.

These tests run the production packing, comparison and plan check of
test_rich_instrument_reuse's DELTA harness over banks of tab sets, each
its own root with its own correlation.
"""

from __future__ import annotations

import struct

import pytest

from test_rich_glyph_growth import MASK64
from test_rich_instrument_reuse import DeltaHarness

TABSET = 7
FIELD = 13


class MembershipHarness(DeltaHarness):
    def banks(self, active, pending, *, shell=True, kinds=None):
        """The bank on screen holds a tab set for each correlation index in
        ACTIVE, the pending bank one for each in PENDING, its kind from
        KINDS when given.  A pending control with an index on screen is the
        same control; the pending bank's take fresh identities from the
        producer's frontier, as a candidate's do.  A frame built for the
        shell has no runs of its own."""
        n = max(len(active), len(pending), 1)
        self.setup(controls=n)
        self.control_size = self.constant("RTE-CONTROL-SIZE")
        self.corr_size = self.constant("RUCP-CORRELATION-SIZE")
        self.controls = self.reserve("CONTROLS", n * self.control_size)
        self.corr = self.reserve("CORR", n * self.corr_size)
        self.items = self.reserve("GLYPH-ITEMS", 6 * 120)
        self.refs = self.reserve("GLYPH-REFS", 6 * 16)
        self.text = self.reserve("GLYPH-TEXT", 16)
        self.reserve("GLYPH-ID-MAP", 6 * 8)
        self.reserve("ORDER2", 24 * n)
        # Each bank's annex for the sorted index its comparison keeps.
        for number in (0, 1):
            self.field(self.producer, f"_RTHP.FACTS-INDEX{number}-A", self.cursor)
            self.cursor += 8 * n
        assert self.cursor <= self.arena + self.arena_size
        self.field(self.producer, "_RTHP.FACTS-INDEX-U", 8 * n)
        for suffix, value in (("OWNER", 1), ("OWNER-GEN", 2), ("COLS", 8), ("ROWS", 2),
                              ("PHYSICAL-GEN", 3), ("DOCUMENT-COUNT", 1),
                              ("MAX-COLLECTIONS", n), ("MAX-FIELDS", n),
                              ("INSTRUMENT-REGION-COUNT", 1),
                              ("INSTRUMENT-COUNT", 3),
                              ("INSTRUMENT-UNITS-USED", len(self.units))):
            self.field(self.producer, "_RTHP." + suffix, value)
        self.field(self.producer + self.offset("_RTHP.LIMITS"), "_RTE-L.GLYPH-RUN-BYTES", 8)
        directory = (1, 1, 0, 0, 2, 8, 0, self.constant("UMSN-RECORD-SIZE"),
                     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1)
        self.runtime.memory.write_bytes(self.source_dir, struct.pack("<20Q", *directory))
        runs = () if shell else ("A",)
        self.stage_tabs(self.bank, 100, 7, 10, active, runs, None)
        self.active_before = self.runtime.memory.read_bytes(self.bank, self.bank_size)
        self.frontier = 100 + len(active) + 3 + len(runs)
        self.stage_tabs(self.other, self.frontier, 17, 11, pending, runs, kinds)
        for suffix, value in (("TARGET-ACTIVE", self.bank), ("TARGET-PENDING", self.other),
                              ("ACTIVE-DRAW", 10), ("NEXT-OBJECT", self.frontier)):
            self.field(self.producer, "_RTHP." + suffix, value)
        if shell:
            self.field(self.producer, "_RTHP.SHELL-BUILT", MASK64)

    def stage_tabs(self, bank, first, region, draw, indexes, runs, kinds):
        memory = self.runtime.memory
        n = len(indexes)
        kinds = kinds or (TABSET,) * n
        fields = sum(1 for kind in kinds if kind == FIELD)
        for suffix, value in (("OWNER", 1), ("GENERATION", 2), ("COLS", 8), ("ROWS", 2),
                              ("PHYSICAL-GEN", 3), ("DOCUMENT-COUNT", 1),
                              ("DRAW", draw), ("SOURCE-GEN", draw), ("CONTENT-EPOCH", draw),
                              ("REGION", region), ("FIRST-OBJECT", first),
                              ("GLYPH-RUN-LIMIT", 8), ("CONTROL-COUNT", n),
                              ("COLLECTION-COUNT", n - fields), ("FIELD-COUNT", fields),
                              ("GLYPH-SLOT-COUNT", len(runs)),
                              ("GLYPH-TEXT-USED", len(runs)),
                              ("INSTRUMENT-REGION-COUNT", 1), ("INSTRUMENT-COUNT", 3),
                              ("INSTRUMENT-UNIT-BYTES", len(self.units))):
            self.field(bank, "_RTHP-TB." + suffix, value)
        for suffix, value in (("SURFACE-GEN", draw), ("SOURCE-DRAW", draw),
                              ("SOURCE-GEN", draw), ("SOURCE-CONTENT-EPOCH", draw),
                              ("REGION", region), ("FIRST-OBJECT", first),
                              ("ATTEMPT", draw), ("GLYPH-COUNT", len(runs)),
                              ("GLYPH-TEXT-USED", len(runs)), ("CONTROL-COUNT", n),
                              ("COLLECTION-COUNT", n - fields), ("FIELD-COUNT", fields)):
            self.field(self.producer, "_RTHP." + suffix, value)
        for place, (index, kind) in enumerate(zip(indexes, kinds)):
            control = (1, 2, first + place, kind, 3, 0, region, 0, 0, 0, 0, 1, 8, 2, 8,
                       0, 0, 0, 0, 0, 0, 0, 0, 0)
            memory.write_bytes(self.controls + place * self.control_size,
                               struct.pack("<24Q", *control))
            memory.write_bytes(self.corr + place * self.corr_size,
                               struct.pack("<7Q", 1, 1, index, 0, first + place, 0, 0))
        memory.write64(self.instrument_regions, region + 1)
        for index in range(3):
            memory.write64(self.instruments + index * 216 + 16, first + n + index)
            memory.write64(self.instruments + index * 216 + 48, region + 1)
            memory.write64(self.instrument_corr + index * 80 + 56, region + 1)
            memory.write64(self.instrument_corr + index * 80 + 64, first + n + index)
        for index, label in enumerate(runs):
            item = (first + n + 3 + index, 0, 1, index * 2, 1, 1, 2, 8, 0, MASK64,
                    0, 0, 0, 1, 0)
            memory.write_bytes(self.items + index * 120, struct.pack("<15Q", *item))
            memory.write_bytes(self.refs + index * 16, struct.pack("<2Q", index, 1))
        memory.write_bytes(self.text, "".join(runs).encode())
        assert self.call("_RTHP-PACK-CANDIDATE", bank, self.producer)
        assert self.call("_RTHP-TARGET-BANK-HEADER?", bank, self.producer)

    def plan(self):
        """The sealed plan's entries: each place in the pending bank, doubled,
        with the low bit set for a control to define."""
        count = self.read("DELTA-PLAN-CONTROLS")
        order2 = self.read("ORDER2-A")
        return [self.runtime.memory.read64(order2 + 8 * index) for index in range(count)]

    def drops(self):
        address, count, ok = self.results("_RTHP-DELTA-PLAN-DROPS@", self.producer)
        assert ok == MASK64
        return [self.runtime.memory.read64(address + 8 * index) for index in range(count)]

    def ids(self, bank):
        controls = self.results("_RTHP-PACK-CONTROLS-A", bank)[0]
        count = self.runtime.memory.read64(bank + self.offset("_RTHP-TB.CONTROL-COUNT"))
        return [self.runtime.memory.read64(controls + place * self.control_size + 16)
                for place in range(count)]


@pytest.fixture(params=("python", "native"))
def membership(request):
    return MembershipHarness(request.param)


@pytest.mark.parametrize("shell", (True, False))
def test_a_control_that_went_is_dropped_by_its_place_on_screen(membership, shell):
    h = membership
    h.banks((1, 2, 3), (1, 3), shell=shell)
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    # The tab sets left keep their identities on screen, wherever they lie.
    assert h.ids(h.other) == [100, 102]
    assert h.plan() == []
    assert h.read("DELTA-PLAN-DROPS") == 1 and h.drops() == [1]
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
    h.assert_unchanged_active()


@pytest.mark.parametrize("shell", (True, False))
def test_a_control_that_came_is_defined_under_its_fresh_identity(membership, shell):
    h = membership
    h.banks((1, 3), (1, 2, 3), shell=shell)
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    # The new tab set keeps the identity its candidate gave it, past the
    # frontier; the others take theirs on screen.
    assert h.ids(h.other) == [100, h.frontier + 1, 101]
    assert h.plan() == [1 * 2 + 1]
    assert h.drops() == []
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
    # The bank keeps the facts its comparison proved, the new identity last.
    facts = h.producer + h.offset("_RTHP.PENDING-FACTS")
    assert h.runtime.memory.read64(facts + h.offset("_RTHP-KF.LAST-ID")) == h.frontier + 1
    assert h.runtime.memory.read64(facts + h.offset("_RTHP-KF.CONTROLS")) == 3
    h.assert_unchanged_active()


def test_a_control_that_went_and_one_that_came_together(membership):
    h = membership
    h.banks((1, 2, 4), (1, 3, 4))
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.ids(h.other) == [100, h.frontier + 1, 102]
    assert h.plan() == [1 * 2 + 1]
    assert h.drops() == [1]
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)


def test_every_control_on_screen_may_go(membership):
    h = membership
    h.banks((1, 2), (3,))
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.plan() == [0 * 2 + 1]
    assert h.drops() == [0, 1]
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)


def test_a_field_that_came_still_needs_a_start(membership):
    h = membership
    h.banks((1,), (1, 2), kinds=(TABSET, FIELD))
    assert not h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    h.assert_unchanged_active()
