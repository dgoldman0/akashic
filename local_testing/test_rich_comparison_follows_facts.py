"""The screen producer's comparison follows the root facts.

When the bank on screen kept the facts its own comparison proved, and the
candidate's controls carry that bank's identities in the same places, a
comparison built for Desk's shell pairs each control with the control in
its place instead of sorting and joining both banks.  Where the root facts
of both banks' snapshots name the same roots in the same order, it checks
against its partner only a control whose root's facts moved.  With the
shadow check on, the full comparison runs as well on the same packed bank,
and a result that differs is a difference of the comparison stage.

These tests run the production packing, comparison and publication of
test_rich_instrument_reuse's harness over two successive frames, the
second built for Desk's shell, and seed the producer's two root facts
blocks as the snapshots would fill them.
"""

from __future__ import annotations

import re
import struct

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64
from test_rich_instrument_reuse import DeltaHarness, InstrumentHarness

# The heap the shadow check takes its blocks from: a bump allocator over a
# block the test gives it.
HEAP = r'''
VARIABLE _CF-HEAP
: _CF-ALLOCATE  ( bytes -- addr ior ) 7 + -8 AND _CF-HEAP @ SWAP _CF-HEAP +! 0 ;
: _CF-FREE  ( addr -- ) DROP ;
'''
URF_F_MENUS = 1
TOKEN = 1


class FollowHarness(DeltaHarness):
    def __init__(self, backend):
        # The DELTA harness's words, and the copy of the bank on screen.
        InstrumentHarness.__init__(self, backend, (
            "_RTHP-DELTA-CANDIDATE?", "_RTHP-D-PLAN-BIND?", "_RTHP-U-CLONE?",
            "_RTHP-U-FENCE-PLAN?", "_RTHP-U-COMMIT", "_RTHP-TARGET-PUBLISH?",
            "_RTHP-R-BANK-CEILING?", "_RTHP-C-FOLLOWS?", "_RTHP-C-COPY?",
            "_RTHP-START-FACTS"))
        self.runtime.evaluate(HEAP.encode())
        self.variable("_CF-HEAP", self.allocate(bytes(1 << 18)))
        self.runtime.evaluate(b"' _CF-ALLOCATE _FSHD-ALLOCATE-XT ! ' _CF-FREE _FSHD-FREE-XT !")
        self.urf = self.constant("URF-SIZE")
        stride, base = map(int, re.search(r"SWAP 1- (\d+) \* \+ (\d+) \+",
                                          self.definitions["_RTHP.ROOT-BLOCK"]).groups())
        self.root_blocks = (base, stride)

    def facts(self, number, generation, stamp, *, token=TOKEN, parts=0):
        """Root facts block NUMBER of GENERATION: the menus root of document
        TOKEN, whose capture read up to revision STAMP."""
        cells = [token, URF_F_MENUS, 0, 0, 0, 0, stamp]
        cells += [0] * (self.urf // 8 - len(cells))
        memory = self.allocate(struct.pack(f"<{len(cells)}Q", *cells))
        base, stride = self.root_blocks
        self.runtime.memory.write_bytes(
            self.producer + base + (number - 1) * stride,
            struct.pack("<5Q", memory, self.urf, 1, generation, parts))

    def first_frame(self):
        """A frame built for the shell is compared in full and goes out; the
        bank it leaves on screen kept the facts its comparison proved."""
        self.delta_pair()
        # Each bank's annex for the sorted index its comparison keeps.
        for number in (0, 1):
            self.field(self.producer, f"_RTHP.FACTS-INDEX{number}-A", self.cursor)
            self.cursor += 8
        assert self.cursor <= self.arena + self.arena_size
        self.field(self.producer, "_RTHP.FACTS-INDEX-U", 8)
        self.field(self.producer, "_RTHP.SHELL-BUILT", MASK64)
        assert self.call("_RTHP-DELTA-CANDIDATE?", self.producer)
        assert self.variable("_RTHP-DIAG-PLACED") == 0
        self.field(self.producer, "_RTHP.PHASE", self.constant("_RTHP-PH-LIVE"))
        assert self.call("_RTHP-TARGET-PUBLISH?", self.producer)
        assert self.read("ACTIVE-FACTS") == self.other

    def start_bank(self, *, runs=()):
        """A frame built for the shell whose bank goes out as a START, with
        RUNS of its own, and each bank's annex for its sorted index."""
        self.delta_pair(pending=runs)
        for number in (0, 1):
            self.field(self.producer, f"_RTHP.FACTS-INDEX{number}-A", self.cursor)
            self.cursor += 8
        assert self.cursor <= self.arena + self.arena_size
        self.field(self.producer, "_RTHP.FACTS-INDEX-U", 8)
        self.field(self.producer, "_RTHP.SHELL-BUILT", MASK64)

    def start_frame(self):
        """The START's bank, which nothing compares, keeps the facts a
        comparison would keep for it, and goes out."""
        self.start_bank()
        self.results("_RTHP-START-FACTS", self.producer)
        assert self.read("PENDING-FACTS") == self.other
        self.field(self.producer, "_RTHP.PHASE", self.constant("_RTHP-PH-LIVE"))
        assert self.call("_RTHP-TARGET-PUBLISH?", self.producer)
        assert self.read("ACTIVE-FACTS") == self.other

    def second_frame(self, *, state=3, old_stamp=5, new_stamp=5, facts=True, runs=("A",)):
        """The next candidate, packed for draw 12 with its one menu control
        in STATE and RUNS, and the root facts of both snapshots."""
        self.bank, self.other = self.other, self.bank
        self.frontier = self.read("NEXT-OBJECT")
        self.active_before = self.runtime.memory.read_bytes(self.bank, self.bank_size)
        self.stage(self.other, self.frontier, 27, 12, runs, state)
        self.field(self.producer, "_RTHP.TARGET-PENDING", self.other)
        self.field(self.producer, "_RTHP.SHELL-BUILT", MASK64)
        if facts:
            self.facts(1, 11, old_stamp)
            self.facts(2, 12, new_stamp)

    def control_state(self):
        controls = self.results("_RTHP-PACK-CONTROLS-A", self.other)[0]
        return self.runtime.memory.read64(controls + self.offset("_RTE-CONTROL.STATE"))

    def diagnostics(self):
        return tuple(self.variable("_RTHP-DIAG-" + name)
                     for name in ("PLACED", "FOLLOWED", "CHECKED"))


@pytest.fixture(params=("python", "native"))
def follow(request):
    return FollowHarness(request.param)


def test_an_unmoved_root_s_controls_are_paired_by_place_and_not_checked(follow):
    h = follow
    h.first_frame()
    h.second_frame()
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.diagnostics() == (1, 1, 0)
    assert h.read("DELTA-PLAN-CONTROLS") == 0
    # The pending bank carries the identities on screen and keeps the bank
    # on screen's sorted index as its own.
    controls = h.results("_RTHP-PACK-CONTROLS-A", h.other)[0]
    assert h.runtime.memory.read64(controls + h.offset("_RTE-CONTROL.ID")) == 100
    assert h.read("PENDING-FACTS") == h.other
    h.assert_unchanged_active()


def test_a_moved_root_s_controls_are_checked_and_planned(follow):
    h = follow
    h.first_frame()
    h.second_frame(state=11, new_stamp=6)
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.diagnostics() == (1, 1, 1)
    assert h.read("DELTA-PLAN-CONTROLS") == 1
    assert h.control_state() == 11
    h.assert_unchanged_active()


def test_without_root_facts_every_control_is_checked(follow):
    h = follow
    h.first_frame()
    h.second_frame(state=11, facts=False)
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    # Paired by place, but checked as the full comparison checks.
    assert h.diagnostics() == (1, 0, 0)
    assert h.read("DELTA-PLAN-CONTROLS") == 1


@pytest.mark.parametrize("why", ("safe", "alone"))
def test_safe_mode_and_a_candidate_built_alone_take_the_full_comparison(follow, why):
    h = follow
    h.first_frame()
    h.second_frame(state=11, new_stamp=6)
    if why == "safe":
        h.variable("CHK-SAFE-MODE", MASK64)
    else:
        h.field(h.producer, "_RTHP.SHELL-BUILT", 0)
    h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.diagnostics() == (0, 0, 0)


def test_the_shadow_check_compares_the_two_comparisons(follow):
    h = follow
    h.first_frame()
    h.second_frame(state=11, new_stamp=6)
    h.variable("FSHD-ON", MASK64)
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.variable("FSHD-CHECKS-COMPARISON") == 5
    assert h.variable("FSHD-MISMATCHES") == 0
    assert h.variable("FSHD-SKIPPED") == 0
    assert h.read("DELTA-PLAN-CONTROLS") == 1
    assert h.control_state() == 11


def test_the_shadow_check_catches_a_change_the_facts_missed(follow):
    """A control that changed though its root's facts did not move goes
    unsent by the comparison that follows the facts.  The full comparison
    finds it: the judge of the root facts counts the miss, and the
    comparison stage the different plan.  The frame keeps the shortcut's
    result, as it does with the check off."""
    h = follow
    h.first_frame()
    h.second_frame(state=11)
    h.variable("FSHD-ON", MASK64)
    assert h.call("_RTHP-DELTA-CANDIDATE?", h.producer)
    assert h.variable("FSHD-MISMATCHES") == 2
    assert h.variable("FSHD-FIRST-STAGE") == h.constant("FSHD-STAGE-ROOT-FACTS")
    assert h.variable("FSHD-CHECKS-COMPARISON") == 1
    assert h.read("DELTA-PLAN-CONTROLS") == 0


# ---------------------------------------------------------------------------
# Pairing by place

PENDING_FIRST = 200
X = [(1, 1, index, 0, 0, 0) for index in (10, 11, 12)]


class PlaceHarness(GrowthHarness):
    """Two packed banks of three menu controls each, whose correlations keep
    their source order while the controls lie in graph order, and the index
    the bank on screen's comparison kept."""

    def __init__(self, backend):
        super().__init__(backend, extra_words=("_RTHP-D-PLACE-MAP?",))
        self.control = self.constant("RTE-CONTROL-SIZE")
        self.correlation = self.constant("RUCP-CORRELATION-SIZE")
        self.header = self.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        self.variable("_RTHP-D-P", self.producer)
        arena = self.allocate(bytes(3 * 3 * 8 + 3 * 8))
        self.field(self.producer, "_RTHP.ARENA-A", arena)
        self.field(self.producer, "_RTHP.ARENA-U", 3 * 3 * 8 + 3 * 8)
        self.field(self.producer, "_RTHP.ORDER2-A", arena)
        self.field(self.producer, "_RTHP.ORDER2-U", 3 * 3 * 8)
        self.annex = arena + 3 * 3 * 8
        self.field(self.producer, "_RTHP.FACTS-INDEX0-A", self.annex)
        self.field(self.producer, "_RTHP.FACTS-INDEX-U", 3 * 8)

    def bank(self, ids, correlations):
        """A bank whose controls carry IDS in graph order and whose
        correlations, in source order, are (identity, control id)."""
        count = len(ids)
        bank = self.allocate(bytes(self.header + count * (self.control + self.correlation)))
        self.field(bank, "_RTHP-TB.CONTROL-COUNT", count)
        controls = bank + self.header
        for place, identity in enumerate(ids):
            self.field(controls + place * self.control, "_RTE-CONTROL.ID", identity)
        base = controls + count * self.control
        for ordinal, ((attachment, source, index, subkey, lifecycle, scope), control) in (
                enumerate(correlations)):
            self.runtime.memory.write_bytes(
                base + ordinal * self.correlation,
                struct.pack("<7Q", attachment, source, index, subkey, control, lifecycle,
                            scope))
        return bank

    def pair(self, *, pending_ids=None, pending_places=(0, 2, 1), identities=X,
             active_ids=(100, 102, 101), kept_places=(0, 2, 1), active_places=None):
        """Correlation j names identity X[j] and, on screen, the control in
        place ACTIVE_PLACES[j], which the kept index gives as KEPT_PLACES[j];
        in the pending bank, the control in place PENDING_PLACES[j]."""
        pending_ids = pending_ids or [PENDING_FIRST + place for place in range(3)]
        active_places = active_places or kept_places
        active = self.bank(active_ids, [(X[j], active_ids[active_places[j]])
                                        for j in range(3)])
        pending = self.bank(pending_ids, [(identities[j], PENDING_FIRST + pending_places[j])
                                          for j in range(3)])
        self.runtime.memory.write_bytes(self.annex, struct.pack(
            "<3Q", *[(j << 32) | kept_places[j] for j in range(3)]))
        self.field(self.producer, "_RTHP.TARGET0-A", active)
        self.field(self.producer + self.offset("_RTHP.ACTIVE-FACTS"), "_RTHP-KF.LAST-ID",
                   max(active_ids))
        self.variable("_RTHP-D-ACTIVE", active)
        self.variable("_RTHP-D-PENDING", pending)
        self.variable("_RTHP-D-PENDING-FIRST", PENDING_FIRST)

    def map(self):
        order2 = self.runtime.memory.read64(self.producer + self.offset("_RTHP.ORDER2-A"))
        return [self.runtime.memory.read64(order2 + 8 * place) for place in range(3)]


@pytest.fixture(params=("python", "native"))
def place(request):
    return PlaceHarness(request.param)


def test_controls_pair_by_place_though_their_correlations_keep_source_order(place):
    place.pair()
    assert place.call("_RTHP-D-PLACE-MAP?")
    assert place.map() == [1, 2, 3]
    # The pending bank keeps the index the bank on screen kept.
    assert place.variable("_RTHP-D-INDEX-B") == place.annex


@pytest.mark.parametrize("case", ("place", "identity", "numbering", "stale"))
def test_controls_that_moved_or_changed_identity_need_the_join(place, case):
    if case == "place":
        # A correlation names a control in another place than on screen.
        place.pair(pending_places=(1, 2, 0))
    elif case == "identity":
        place.pair(identities=[X[0], X[1], (1, 1, 99, 0, 0, 0)])
    elif case == "numbering":
        place.pair(pending_ids=[PENDING_FIRST, PENDING_FIRST + 2, PENDING_FIRST + 1])
    else:
        # The kept index no longer names the control its correlation names.
        place.pair(active_places=(0, 1, 2))
    assert not place.call("_RTHP-D-PLACE-MAP?")


# ---------------------------------------------------------------------------
# The copy of the bank on screen

def test_a_frame_whose_roots_did_not_move_copies_the_bank_on_screen(follow):
    """A candidate built for the shell, with no runs of its own, whose
    snapshot's root facts did not move: the pending bank is the bank on
    screen's copy, its control in the identity on screen, nothing planned,
    and the bank on screen's kept facts its own."""
    h = follow
    h.first_frame()
    h.second_frame(runs=())
    h.variable("_RTHP-C-P", h.producer)
    assert h.call("_RTHP-C-FOLLOWS?")
    assert h.call("_RTHP-C-COPY?", h.producer)
    assert h.variable("_RTHP-DIAG-COPIED") == 1
    assert h.read("TARGET-PENDING") == h.other
    assert h.read("DELTA-PLAN-CONTROLS") == 0
    assert h.read("DELTA-PLAN-VALID") == MASK64
    controls = h.results("_RTHP-PACK-CONTROLS-A", h.other)[0]
    assert h.runtime.memory.read64(controls + h.offset("_RTE-CONTROL.ID")) == 100
    assert h.read("FIRST-OBJECT") == 100
    assert h.read("PENDING-FACTS") == h.other
    h.assert_unchanged_active()


def test_a_start_s_bank_keeps_facts_the_next_frame_follows(follow):
    """A bank that went out as a START keeps its controls' sorted index, as
    a comparison keeps a DELTA's bank's, so the next frame is paired by place
    and copied from it (FRAMES-FOLLOW-CHANGE, 9c.1)."""
    h = follow
    h.start_frame()
    kept = h.producer + h.offset("_RTHP.ACTIVE-FACTS")
    assert h.runtime.memory.read64(kept + h.offset("_RTHP-KF.CONTROLS")) == 1
    # The START's one control holds the first fresh ID, the frontier.
    assert h.runtime.memory.read64(kept + h.offset("_RTHP-KF.LAST-ID")) == h.frontier
    h.second_frame(runs=())
    h.variable("_RTHP-C-P", h.producer)
    assert h.call("_RTHP-C-FOLLOWS?")
    assert h.call("_RTHP-C-COPY?", h.producer)
    assert h.variable("_RTHP-DIAG-COPIED") == 1
    assert h.read("PENDING-FACTS") == h.other
    h.assert_unchanged_active()


@pytest.mark.parametrize("why", ("runs", "safe", "alone", "kept"))
def test_a_start_keeps_no_facts_in_safe_mode_alone_or_with_runs(follow, why):
    """Desk's shell builds no runs, and a START's glyph facts would need the
    comparison's glyph plan; safe mode reuses nothing an earlier frame built;
    a bank built alone is compared in full."""
    h = follow
    h.start_bank(runs=("B",) if why == "runs" else ())
    if why == "safe":
        h.variable("CHK-SAFE-MODE", MASK64)
    if why == "alone":
        h.field(h.producer, "_RTHP.SHELL-BUILT", 0)
    h.results("_RTHP-START-FACTS", h.producer)
    assert h.read("PENDING-FACTS") == (h.other if why == "kept" else 0)


@pytest.mark.parametrize("why", ("menus", "runs", "safe"))
def test_a_moved_menu_runs_of_its_own_and_safe_mode_are_not_copied(follow, why):
    h = follow
    h.first_frame()
    h.second_frame(runs=("A",) if why == "runs" else (),
                   new_stamp=6 if why == "menus" else 5)
    if why == "safe":
        h.variable("CHK-SAFE-MODE", MASK64)
    h.variable("_RTHP-C-P", h.producer)
    assert not h.call("_RTHP-C-FOLLOWS?")
