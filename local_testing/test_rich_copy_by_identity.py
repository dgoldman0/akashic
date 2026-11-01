"""The copy of the bank on screen pairs its controls by identity.

FRAMES-FOLLOW-CHANGE 9c.2c.  The two snapshots' root facts pair their roots
by identity, so a root may come or go.  When they do not name the same
roots in the same order, or the controls are not as many, the copy of the
bank on screen joins the controls by identity, as the comparison does: a
control of a root that came is defined under the fresh identity its
candidate gave it, a control of a root that went is dropped, and a control
of a root both hold that did not move keeps its partner's identity without
a check.  The copy gives the bank, plan and kept facts the full comparison
gives the same frame.

These tests run the production copy, packing and comparison of
test_rich_delta_membership's harness over banks of tab sets, each its own
collection root, with the root facts both snapshots kept and the facts the
bank on screen kept as a START's bank keeps them.
"""

from __future__ import annotations

import re
import struct

import pytest

from test_rich_delta_membership import MembershipHarness
from test_rich_instrument_reuse import InstrumentHarness

URF_F_MENUS = 1
URF_F_COLLECTION = 2
URF_F_DATA_GRAPHICS = 3
URF_F_FIELD = 5
URF_F_DIALOG = 6
# The draws, and so the snapshot generations, of the bank on screen and
# the pending one.
OLD, NEW = 10, 11


class IdentityHarness(MembershipHarness):
    subkey = 5

    def __init__(self, backend):
        InstrumentHarness.__init__(self, backend, (
            "_RTHP-DELTA-CANDIDATE?", "_RTHP-D-PLAN-BIND?", "_RTHP-U-CLONE?",
            "_RTHP-U-FENCE-PLAN?", "_RTHP-U-COMMIT", "_RTHP-TARGET-PUBLISH?",
            "_RTHP-R-BANK-CEILING?", "_RTHP-C-FOLLOWS?", "_RTHP-C-COPY?",
            "_RTHP-START-FACTS", "_RTHP-FACTS-INDEX", "_RTHP-PACK-A"))
        self.urf = self.constant("URF-SIZE")
        stride, base = map(int, re.search(r"SWAP 1- (\d+) \* \+ (\d+) \+",
                                          self.definitions["_RTHP.ROOT-BLOCK"]).groups())
        self.root_blocks = (base, stride)

    def roots(self, number, generation, indexes, *, stamps=None, families=None, parts=0):
        """Root facts block NUMBER of GENERATION: a root for each tab set's
        correlation index in INDEXES, a collection's unless FAMILIES says,
        whose capture read up to its stamp in STAMPS, or 5."""
        data = b""
        for index in indexes:
            family = (families or {}).get(index, URF_F_COLLECTION)
            cells = [1, family, 1, index, 0, self.subkey, (stamps or {}).get(index, 5)]
            cells += [0] * (self.urf // 8 - len(cells))
            data += struct.pack(f"<{len(cells)}Q", *cells)
        memory = self.allocate(data or bytes(8))
        base, stride = self.root_blocks
        self.runtime.memory.write_bytes(
            self.producer + base + (number - 1) * stride,
            struct.pack("<5Q", memory, len(data), len(indexes), generation, parts))

    def kept(self):
        """The bank on screen keeps the facts a START's bank keeps: its
        controls' index, sorted by identity, and their count."""
        self.field(self.producer, "_RTHP.TARGET-PENDING", self.bank)
        self.results("_RTHP-START-FACTS", self.producer)
        pending = self.producer + self.offset("_RTHP.PENDING-FACTS")
        record = self.runtime.memory.read_bytes(pending, self.constant("_RTHP-KF-SIZE"))
        assert struct.unpack_from("<Q", record)[0] == self.bank
        self.runtime.memory.write_bytes(self.producer + self.offset("_RTHP.ACTIVE-FACTS"), record)
        self.runtime.memory.write64(pending, 0)
        self.field(self.producer, "_RTHP.TARGET-PENDING", self.other)

    def frame(self, active, pending, *, old=None, new=None, **kwargs):
        """The bank on screen of tab sets ACTIVE, which kept its facts, and
        the pending candidate of tab sets PENDING, built for the shell.  The
        root facts name each tab set's root, unless OLD and NEW name others,
        and take what roots() takes from the dicts in KWARGS."""
        old_facts = kwargs.pop("old_facts", {})
        new_facts = kwargs.pop("new_facts", {})
        self.banks(active, pending, **kwargs)
        self.kept()
        self.roots(1, OLD, old if old is not None else active, **old_facts)
        self.roots(2, NEW, new if new is not None else pending, **new_facts)
        self.variable("_RTHP-C-P", self.producer)
        self.saved = tuple(self.read(name) for name in ("REGION", "FIRST-OBJECT", "FIRST-SERIES"))

    def result(self):
        """The pending bank's bytes, the plan, its drops, and the facts the
        bank keeps with its sorted index."""
        packed = self.results("_RTHP-PACK-A", self.other)[0]
        used = packed - self.other + self.runtime.memory.read64(
            self.other + self.offset("_RTHP-TB.PACKED-BYTES"))
        facts = self.producer + self.offset("_RTHP.PENDING-FACTS")
        record = self.runtime.memory.read_bytes(facts, self.constant("_RTHP-KF-SIZE"))
        controls = self.runtime.memory.read64(facts + self.offset("_RTHP-KF.CONTROLS"))
        index = self.results("_RTHP-FACTS-INDEX", self.other, self.producer)[0]
        return (self.runtime.memory.read_bytes(self.other, used), self.plan(), self.drops(),
                record, self.runtime.memory.read_bytes(index, 8 * controls))

    def compared(self):
        """What the full comparison makes of the frame, from a pending bank
        written as the copy writes one, with the header the pack gives it
        and no input targets, as a bank of tab sets has none; the frame is
        then set back as the copy finds it."""
        self.variable("_RTHP-C-ACTIVE", self.bank)
        self.variable("_RTHP-C-PLACE", 0)
        assert self.call("_RTHP-C-WRITE?")
        assert self.call("_RTHP-DELTA-CANDIDATE?", self.producer)
        full = self.result()
        for name, value in zip(("REGION", "FIRST-OBJECT", "FIRST-SERIES"), self.saved):
            self.field(self.producer, "_RTHP." + name, value)
        return full

    def why(self):
        return self.variable("_RTHP-C-WHY")


@pytest.fixture(params=("python", "native"))
def identity(request):
    return IdentityHarness(request.param)


@pytest.mark.parametrize("active, pending, plan, drops", (
    # A tab set came: defined under the fresh identity, the second in place.
    ((1, 3), (1, 2, 3), [1 * 2 + 1], []),
    # One went: dropped by its place on screen.
    ((1, 2, 3), (1, 3), [], [1]),
    # One went and another came.
    ((1, 2, 4), (1, 3, 4), [1 * 2 + 1], [1]),
    # Every one on screen went.
    ((1, 2), (3,), [0 * 2 + 1], [0, 1]),
))
def test_roots_that_came_or_went_are_copied_by_identity(identity, active, pending, plan, drops):
    h = identity
    h.frame(active, pending)
    full = h.compared()
    assert h.call("_RTHP-C-FOLLOWS?")
    assert h.call("_RTHP-C-COPY?", h.producer)
    assert h.variable("_RTHP-DIAG-COPIED") == 1
    assert h.variable("_RTHP-DIAG-COPIED-BY-IDENTITY") == 1
    assert h.plan() == plan and h.drops() == drops
    # A tab set both hold keeps its identity on screen, and a new one the
    # fresh identity its candidate gave it.
    expected = [100 + active.index(index) if index in active else h.frontier + place
                for place, index in enumerate(pending)]
    assert h.ids(h.other) == expected
    assert h.result() == full
    assert h.call("_RTHP-D-PLAN-BIND?", h.producer)
    h.assert_unchanged_active()


def test_the_same_roots_in_the_same_order_are_copied_by_place(identity):
    h = identity
    h.frame((1, 2), (1, 2))
    assert h.call("_RTHP-C-FOLLOWS?")
    assert h.call("_RTHP-C-COPY?", h.producer)
    assert h.variable("_RTHP-DIAG-COPIED") == 1
    assert h.variable("_RTHP-DIAG-COPIED-BY-IDENTITY") == 0
    assert h.ids(h.other) == [100, 101] and h.plan() == [] and h.drops() == []


@pytest.mark.parametrize("case", ("came into a root on screen", "went from a root kept"))
def test_each_pairing_must_be_the_one_the_facts_allow(identity, case):
    """A control the frame on screen lacks belongs to a root that came, and
    a control dropped to a root that went: otherwise the copy is refused,
    by its pairing."""
    h = identity
    if case == "came into a root on screen":
        h.frame((1, 3), (1, 2, 3), old=(1, 2, 3))
    else:
        h.frame((1, 2, 3), (1, 3), new=(1, 2, 3))
    assert h.call("_RTHP-C-FOLLOWS?")
    assert not h.call("_RTHP-C-COPY?", h.producer)
    assert h.why() == 9
    assert h.read("TARGET-PENDING") == 0
    assert tuple(h.read(name) for name in ("REGION", "FIRST-OBJECT", "FIRST-SERIES")) == h.saved
    h.assert_unchanged_active()


def test_a_root_of_another_family_both_hold_that_moved_refuses_the_copy(identity):
    """A moved data-graphics root refuses the copy at the facts, while a
    moved field root, which the copy checks against its partner, does not
    (FRAMES-FOLLOW-CHANGE 9c.3a)."""
    h = identity
    h.frame((1, 3), (1, 2, 3), old_facts={"families": {1: URF_F_DATA_GRAPHICS}},
            new_facts={"families": {1: URF_F_DATA_GRAPHICS}, "stamps": {1: 6}})
    assert not h.call("_RTHP-C-FOLLOWS?")
    assert h.why() == 7
    h.frame((1, 3), (1, 2, 3), old_facts={"families": {1: URF_F_FIELD}},
            new_facts={"families": {1: URF_F_FIELD}, "stamps": {1: 6}})
    assert h.call("_RTHP-C-FOLLOWS?")


@pytest.mark.parametrize("parts", (0, "instruments"))
def test_a_family_that_came_with_the_bank_moves_its_roots(identity, parts):
    """A data-graphics root both hold with the same facts moved all the same
    when the instruments came with the pending bank, as when the terminal had
    no room for them before."""
    h = identity
    instruments = h.constant("RTHP-PART-INSTRUMENTS") if parts else 0
    h.frame((1, 3), (1, 2, 3), old_facts={"families": {1: URF_F_DATA_GRAPHICS}},
            new_facts={"families": {1: URF_F_DATA_GRAPHICS}, "parts": instruments})
    assert bool(h.call("_RTHP-C-FOLLOWS?")) == (not parts)


def test_the_copy_needs_both_snapshots_facts(identity):
    h = identity
    h.frame((1, 3), (1, 2, 3))
    # The pending snapshot's facts are of another generation.
    h.roots(2, NEW + 1, (1, 2, 3))
    assert not h.call("_RTHP-C-FOLLOWS?")
    assert h.why() == 6


def test_a_moved_menus_root_passes_the_facts_and_pairs_by_identity(identity):
    """A moved menus root no longer refuses the copy at the facts.  Its
    targets may then change in number, so the copy pairs by identity even
    with every control in its partner's place (FRAMES-FOLLOW-CHANGE 9c.3c)."""
    h = identity
    menus = {"families": {7: URF_F_MENUS}}
    for stamps, moved in (({}, False), ({7: 6}, True)):
        h.frame((1, 2), (1, 2), old=(1, 2, 7), new=(1, 2, 7), old_facts=menus,
                new_facts={**menus, "stamps": stamps})
        assert h.call("_RTHP-C-FOLLOWS?")
        assert bool(h.variable("_RTHP-C-MENUS")) == moved
        assert bool(h.call("_RTHP-C-PLACE?")) == (not moved)


def test_a_moved_menu_control_or_tab_set_is_paired_whatever_its_state(identity):
    """A menu control of a moved menus root, or a moved tab set, keeps its
    partner's place in the input whatever state it shows, since their
    targets are built again; a control the copy does not write in does
    not."""
    h = identity
    h.frame((1, 2), (1, 2))
    h.variable("_RTHP-D-PENDING", h.other)
    assert h.call("_RTHP-C-MOVED-PAIR?", 0)
    controls = h.results("_RTHP-PACK-CONTROLS-A", h.other)[0]
    kind = controls + h.offset("_RTE-CONTROL.KIND")
    h.runtime.memory.write64(kind, h.constant("RTE-CONTROL-MENU-BAR"))
    assert not h.call("_RTHP-C-MOVED-PAIR?", 0)
    h.field(h.other, "_RTHP-TB.MENU-CONTROL-COUNT", 1)
    assert h.call("_RTHP-C-MOVED-PAIR?", 0)


def test_menu_targets_built_again_take_their_partners_identities(identity):
    """The menus' targets built again carry the identities the candidate
    numbered by place: a paired control's takes its partner's on screen,
    and a new control's keeps the candidate's."""
    h = identity
    h.frame((1, 2), (1, 2))
    first = h.frontier
    for name, value in (("_RTHP-D-P", h.producer), ("_RTHP-D-ACTIVE", h.bank),
                        ("_RTHP-D-PENDING-FIRST", first)):
        h.variable(name, value)
    # Pending control 0 pairs with control 1 on screen; control 1 is new.
    order2 = h.read("ORDER2-A")
    h.runtime.memory.write64(order2, 2)
    h.runtime.memory.write64(order2 + 8, 0)
    header = h.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
    size = h.constant("_RTHP-TARGET-ENTRY-SIZE")
    targets = h.allocate(bytes(header + 2 * size))
    for place in range(2):
        h.runtime.memory.write64(targets + header + place * size, first + place)
    h.variable("_RTHP-TG-BANK", targets)
    h.variable("_RTHP-TG-COUNT", 2)
    h.results("_RTHP-C-T-MENU-IDS")
    assert [h.runtime.memory.read64(targets + header + place * size)
            for place in range(2)] == [101, first + 1]


@pytest.mark.parametrize("pending", ((1, 2), (1, 2, 3)), ids=("by place", "by identity"))
def test_a_moved_tab_set_is_copied_with_its_targets_built_again(identity, pending):
    """A moved tab set is checked against its partner, and its tabs'
    targets are built again by the pack's own words, in their places on
    screen or, when the copy pairs by identity, under their partners'
    identities; the copy gives the bank, plan and kept facts the full
    comparison gives (FRAMES-FOLLOW-CHANGE 9c.3d)."""
    h = identity
    h.frame((1, 2), pending, new_facts={"stamps": {1: 6}})
    full = h.compared()
    assert h.call("_RTHP-C-FOLLOWS?")
    assert h.call("_RTHP-C-COPY?", h.producer)
    assert h.variable("_RTHP-DIAG-COPIED-BY-IDENTITY") == (len(pending) == 3)
    assert h.result() == full
    h.assert_unchanged_active()

def test_a_moved_dialog_passes_the_facts_and_is_paired_whatever_its_state(identity):
    """A moved dialog root no longer refuses the copy at the facts, and a
    moved dialog or button is paired by identity whatever state it shows,
    since its targets are built again (FRAMES-FOLLOW-CHANGE 9c.3d)."""
    h = identity
    h.frame((1, 2), (1, 2), old=(1, 2, 7), new=(1, 2, 7),
            old_facts={"families": {7: URF_F_DIALOG}},
            new_facts={"families": {7: URF_F_DIALOG}, "stamps": {7: 6}})
    assert h.call("_RTHP-C-FOLLOWS?")
    h.variable("_RTHP-D-PENDING", h.other)
    controls = h.results("_RTHP-PACK-CONTROLS-A", h.other)[0]
    kind = controls + h.offset("_RTE-CONTROL.KIND")
    for name in ("RTE-CONTROL-DIALOG", "RTE-CONTROL-BUTTON"):
        h.runtime.memory.write64(kind, h.constant(name))
        assert h.call("_RTHP-C-MOVED-PAIR?", 0)


def test_the_copy_writes_in_a_dialogs_controls_past_the_fields(identity):
    """Past the collections and fields lie the dialogs' controls, which the
    copy writes in when it is a dialog or button."""
    h = identity
    h.frame((1, 2), (1, 2))
    h.variable("_RTHP-D-PENDING", h.other)
    h.field(h.other, "_RTHP-TB.DIALOG-CONTROLS", 1)
    for name, movable in (("RTE-CONTROL-DIALOG", True), ("RTE-CONTROL-BUTTON", True),
                          ("RTE-CONTROL-FIELD", False)):
        assert bool(h.call("_RTHP-C-MOVABLE?", 1, h.constant(name))) == movable
