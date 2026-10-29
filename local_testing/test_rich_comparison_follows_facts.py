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

from test_rich_glyph_growth import MASK64
from test_rich_instrument_reuse import DeltaHarness

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
        super().__init__(backend)
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

    def second_frame(self, *, state=3, old_stamp=5, new_stamp=5, facts=True):
        """The next candidate, packed for draw 12 with its one menu control
        in STATE, and the root facts of both snapshots."""
        self.bank, self.other = self.other, self.bank
        self.frontier = self.read("NEXT-OBJECT")
        self.active_before = self.runtime.memory.read_bytes(self.bank, self.bank_size)
        self.stage(self.other, self.frontier, 27, 12, ("A",), state)
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
