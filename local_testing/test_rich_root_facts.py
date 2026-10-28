#!/usr/bin/env python3
"""What each root's capture read, and the judge that holds the facts to it.

RUHA-ROOT-FACTS@ records, for every root the snapshot of a completed draw
holds, the newest UIDL revision among the elements its capture read, the
revisions of the widget and model it shows, and the geometry it was captured
at (uidl-root-facts.f).  The first tests run it on the snapshot adapter's
real textarea document.

With the shadow check on, the screen producer keeps those facts beside each
bank and judges them in its DELTA comparison: an item the comparison finds new
or changed must belong to a root whose facts moved since the bank on screen.
The judge's tests seed two banks and two blocks of facts, and run the
production words.
"""

from __future__ import annotations

import struct

import pytest

from test_data_graphics_series import run_series
from test_rich_adapter_provenance import _program
from test_rich_glyph_growth import GrowthHarness, MASK64


FACTS = r'''
CREATE _RF-MEM 4 URF-SIZE * 7 + ALLOT
: _RF-A _RF-MEM 7 + -8 AND ;
CREATE _RF-OLD-MEM URF-SIZE 7 + ALLOT
: _RF-OLD _RF-OLD-MEM 7 + -8 AND ;
VARIABLE _RF-N VARIABLE _RF-S
: _RF-FACTS ( draw -- )
    >R _RF-A 4 URF-SIZE * R> _RA-ADAPTER RUHA-ROOT-FACTS@ _RF-S ! _RF-N ! ;
: _RF-KEEP _RF-A _RF-OLD URF-SIZE MOVE ;
: _RF-DONE _RA-STACK _RA-FAILS @ 0= IF ." FACTS PASS " ELSE ." FACTS FAIL " THEN
    _RA-CHECKS @ . _RA-FAILS @ . CR ;
'''


def test_a_snapshot_records_what_its_textarea_root_read():
    run_series(_program() + FACTS + r'''
\ Draw 1's snapshot holds the document's textarea, a direct collection root.
1 _RF-FACTS _RF-S @ RUHA-S-OK = _RA-ASSERT _RF-N @ 1 = _RA-ASSERT
_RF-A URF.TOKEN @ _RA-DIR-A @ RUHA-DOCUMENT-TOKEN@ = _RA-ASSERT
_RF-A URF.FAMILY @ URF-F-COLLECTION = _RA-ASSERT
_RF-A URF.SOURCE @ UCSN-SOURCE-UIDL = _RA-ASSERT
_RF-A URF.INDEX @ _RA-DESC-A @ UCSN-DESCRIPTOR-SOURCE-INDEX@ = _RA-ASSERT
_RF-A URF.GENERATION @ 0= _RA-ASSERT
_RF-A URF.KEY @ 1 = _RA-ASSERT
\ The newest revision among the textarea, its ancestors and its contents.
_RF-A URF.STAMP @ DUP 0> SWAP URF-UNKNOWN <> AND _RA-ASSERT
S" note" UTUI-BY-ID UIDL-REVISION _RF-A URF.STAMP @ > 0= _RA-ASSERT
_RF-A URF.WIDGET-REV @ _RA-TEXTAREA @ WDG-REVISION = _RA-ASSERT
\ The geometry the capture placed it at.
_RF-A URF.ROW @ _RA-DESC-A @ UCSN-DESCRIPTOR-ROW@ = _RA-ASSERT
_RF-A URF.WIDTH @ _RA-DESC-A @ UCSN-DESCRIPTOR-WIDTH@ = _RA-ASSERT
_RF-A URF.CLIP-HEIGHT @ _RA-DESC-A @ UCSN-DESCRIPTOR-CLIP-HEIGHT@ = _RA-ASSERT
_RF-A URF.Z @ _RA-DESC-A @ UCSN-DESCRIPTOR-Z@ = _RA-ASSERT
_RF-A _RF-A URF-SAME? _RA-ASSERT
_RF-DONE
''', minimum=17, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",),
        marker="FACTS")


def test_facts_hold_without_a_change_and_move_with_one():
    run_series(_program() + FACTS + r'''
1 _RF-FACTS _RF-S @ RUHA-S-OK = _RA-ASSERT _RF-KEEP
\ A draw that changed nothing reuses the document: the same facts.
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
2 _RF-FACTS _RF-S @ RUHA-S-OK = _RA-ASSERT _RF-N @ 1 = _RA-ASSERT
_RF-A _RF-OLD URF-SAME? _RA-ASSERT
\ New text moves the widget's revision; the elements are as they were.
S" aggregate beta" _RA-TEXTAREA @ TXTA-SET-TEXT
UTUI-PAINT UTUI-DRAW-COMPLETE
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
3 _RF-FACTS _RF-S @ RUHA-S-OK = _RA-ASSERT
_RF-A _RF-OLD URF-SAME? 0= _RA-ASSERT
_RF-A URF.WIDGET-REV @ _RF-OLD URF.WIDGET-REV @ <> _RA-ASSERT
_RF-A URF.STAMP @ _RF-OLD URF.STAMP @ = _RA-ASSERT
_RF-KEEP
\ A change counted on the element moves the stamp.
S" note" UTUI-BY-ID UIDL-DIRTY! UTUI-PAINT UTUI-DRAW-COMPLETE
4 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
4 _RF-FACTS _RF-S @ RUHA-S-OK = _RA-ASSERT
_RF-A URF.STAMP @ _RF-OLD URF.STAMP @ > _RA-ASSERT
_RF-A _RF-OLD URF-SAME? 0= _RA-ASSERT
_RF-DONE
''', minimum=14, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",),
        marker="FACTS")


def test_another_draw_is_stale_and_a_short_bank_counts_what_it_needs():
    run_series(_program() + FACTS + r'''
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
\ Facts describe the completed draw's snapshot only.
1 _RF-FACTS _RF-S @ RUHA-S-STALE = _RA-ASSERT _RF-N @ 0= _RA-ASSERT
\ A bank with no room answers how many records it would take.
_RF-A 0 2 _RA-ADAPTER RUHA-ROOT-FACTS@
    RUHA-S-CAPACITY = _RA-ASSERT 1 = _RA-ASSERT
\ A bank as wide as the records takes them.
_RF-A URF-SIZE 2 _RA-ADAPTER RUHA-ROOT-FACTS@
    RUHA-S-OK = _RA-ASSERT 1 = _RA-ASSERT
_RF-DONE
''', minimum=7, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",),
        marker="FACTS")


# ---------------------------------------------------------------------------
# The judge

TOKEN = 0x51
TEXT_AREA, TAB, MENU_ITEM, FIELD, DIALOG = 5, 8, 3, 13, 15
COLLECTION, MENUS, STATUS, F_FIELD, F_DIALOG, DATA_GRAPHICS = 2, 1, 4, 5, 6, 3


class JudgeHarness(GrowthHarness):
    def __init__(self, backend):
        super().__init__(backend, extra_words=(
            "_RTHP-ROOT-BEGIN", "_RTHP-ROOT-JUDGE-CONTROL",
            "_RTHP-ROOT-STATIC-CHANGES", "_RTHP-ROOT-INSTRUMENTS", "FSHD-RESET"))
        self.urf = self.constant("URF-SIZE")
        self.control = self.constant("RTE-CONTROL-SIZE")
        self.correlation = self.constant("RUCP-CORRELATION-SIZE")
        self.header = self.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        self.variable("FSHD-ON", MASK64)
        self.results("FSHD-RESET")

    def bank(self, generation, controls):
        """A packed bank of SOURCE-GEN GENERATION holding CONTROLS, each
        (kind, attachment, source, index, subkey, lifecycle, scope)."""
        count = len(controls)
        bank = self.allocate(bytes(self.header + count * (self.control + self.correlation) + 64))
        self.field(bank, "_RTHP-TB.SOURCE-GEN", generation)
        self.field(bank, "_RTHP-TB.CONTROL-COUNT", count)
        base = bank + self.header
        correlations = base + count * self.control
        for ordinal, (kind, attachment, source, index, subkey, lifecycle, scope) in enumerate(controls):
            self.field(base + ordinal * self.control, "_RTE-CONTROL.KIND", kind)
            self.runtime.memory.write_bytes(
                correlations + ordinal * self.correlation,
                struct.pack("<7Q", attachment, source, index, subkey, 100 + ordinal,
                            lifecycle, scope))
        return bank

    def block(self, number, generation, records, parts=0):
        """Facts block NUMBER of GENERATION holding RECORDS, each
        (family, source, index, generation, key, stamp, widget-revision),
        whose candidate carried PARTS."""
        memory = self.allocate(bytes(max(1, len(records)) * self.urf))
        for position, (family, source, index, gen, key, stamp, revision) in enumerate(records):
            cells = [TOKEN, family, source, index, gen, key, stamp, revision]
            cells += [0] * (self.urf // 8 - len(cells))
            self.runtime.memory.write_bytes(memory + position * self.urf,
                                            struct.pack(f"<{len(cells)}Q", *cells))
        self.variable(f"_RTHP-ROOT-A{number}", memory)
        self.variable(f"_RTHP-ROOT-N{number}", len(records))
        self.variable(f"_RTHP-ROOT-GEN{number}", generation)
        self.variable(f"_RTHP-ROOT-PARTS{number}", parts)

    def begin(self, active, pending):
        self.field(self.producer, "_RTHP.TARGET-ACTIVE", active)
        self.field(self.producer, "_RTHP.TARGET-PENDING", pending)
        self.results("_RTHP-ROOT-BEGIN", self.producer)
        self.variable("_RTHP-D-ACTIVE", active)
        self.variable("_RTHP-D-PENDING", pending)

    def judge(self, index):
        self.results("_RTHP-ROOT-JUDGE-CONTROL", index)

    def counts(self):
        return (self.variable("FSHD-CHECKS-ROOT-FACTS"), self.variable("FSHD-MISMATCHES"),
                self.variable("FSHD-SKIPPED"))


@pytest.fixture(scope="module")
def harness():
    return JudgeHarness("native")


def _fresh(harness):
    harness.results("FSHD-RESET")
    for name in ("FRAMES", "ROOTS", "CHANGED", "ITEMS"):
        harness.variable(f"_RTHP-DIAG-ROOT-{name}", 0)


TEXT = (TEXT_AREA, TOKEN, 1, 5, 1, 0, 0)
TEXT_ROOT = (COLLECTION, 1, 5, 0, 1)


@pytest.mark.parametrize("old_stamp, new_stamp, held", [(40, 40, False), (40, 41, True)])
def test_a_changed_control_needs_its_roots_facts_to_have_moved(harness, old_stamp, new_stamp, held):
    _fresh(harness)
    active, pending = harness.bank(10, [TEXT]), harness.bank(11, [TEXT])
    harness.block(1, 10, [(*TEXT_ROOT, old_stamp, 3)])
    harness.block(2, 11, [(*TEXT_ROOT, new_stamp, 3)])
    harness.begin(active, pending)
    assert harness.variable("_RTHP-DIAG-ROOT-FRAMES") == 1
    assert harness.variable("_RTHP-DIAG-ROOT-CHANGED") == (1 if held else 0)
    harness.judge(0)
    assert harness.counts() == (1, 0 if held else 1, 0)
    if not held:
        assert harness.variable("FSHD-FIRST-STAGE") == harness.constant("FSHD-STAGE-ROOT-FACTS")


def test_a_widget_revision_alone_moves_the_facts(harness):
    _fresh(harness)
    active, pending = harness.bank(10, [TEXT]), harness.bank(11, [TEXT])
    harness.block(1, 10, [(*TEXT_ROOT, 40, 3)])
    harness.block(2, 11, [(*TEXT_ROOT, 40, 4)])
    harness.begin(active, pending)
    harness.judge(0)
    assert harness.counts() == (1, 0, 0)


def test_a_new_root_holds_and_a_control_without_facts_does_not(harness):
    _fresh(harness)
    other = (TEXT_AREA, TOKEN, 1, 6, 1, 0, 0)
    active, pending = harness.bank(10, [TEXT]), harness.bank(11, [TEXT, other])
    harness.block(1, 10, [(*TEXT_ROOT, 40, 3)])
    harness.block(2, 11, [(*TEXT_ROOT, 40, 3), (COLLECTION, 1, 6, 0, 1, 52, 1)])
    harness.begin(active, pending)
    harness.judge(1)
    assert harness.counts() == (1, 0, 0)
    # A root the facts never recorded is a change they missed.
    _fresh(harness)
    stray = harness.bank(11, [(TEXT_AREA, TOKEN, 1, 9, 1, 0, 0)])
    harness.begin(active, stray)
    harness.judge(0)
    assert harness.counts() == (1, 1, 0)


def test_controls_map_to_their_roots_by_kind(harness):
    _fresh(harness)
    # A menu item belongs to its document's menus; a tab to its tab set,
    # whose key is the tab's scope; a dialog's button to its dialog, whatever
    # its ordinal.
    controls = [(MENU_ITEM, TOKEN, 1, 33, 0, 0, 0), (TAB, TOKEN, 1, 7, 900, 0, 1),
                (DIALOG + 1, TOKEN, 3, 2, 77, 1, 77), (FIELD, TOKEN, 2, 0, 600, 1, 9)]
    roots = [(MENUS, 0, 0, 0, 0), (COLLECTION, 1, 7, 0, 1), (F_DIALOG, 3, 0, 0, 77),
             (F_FIELD, 2, 0, 1, 600)]
    active, pending = harness.bank(10, controls), harness.bank(11, controls)
    harness.block(1, 10, [(*root, 40, 3) for root in roots])
    harness.block(2, 11, [(*root, 41, 3) for root in roots])
    harness.begin(active, pending)
    for index in range(len(controls)):
        harness.judge(index)
    assert harness.counts() == (4, 0, 0)
    _fresh(harness)
    harness.block(2, 11, [(*root, 40, 3) for root in roots])
    harness.begin(active, pending)
    for index in range(len(controls)):
        harness.judge(index)
    assert harness.counts() == (4, 4, 0)


def test_banks_from_one_snapshot_or_without_facts_are_not_judged(harness):
    _fresh(harness)
    active, pending = harness.bank(10, [TEXT]), harness.bank(10, [TEXT])
    harness.block(1, 10, [(*TEXT_ROOT, 40, 3)])
    harness.begin(active, pending)
    harness.judge(0)
    assert harness.counts() == (0, 0, 0)
    assert harness.variable("_RTHP-DIAG-ROOT-FRAMES") == 0
    harness.block(2, 0, [])
    harness.begin(active, harness.bank(12, [TEXT]))
    harness.judge(0)
    assert harness.counts() == (0, 0, 0)


@pytest.mark.parametrize("moved, held", [(False, False), (True, True)])
def test_instruments_that_cannot_be_kept_need_a_data_graphics_root_to_move(harness, moved, held):
    _fresh(harness)
    active, pending = harness.bank(10, []), harness.bank(11, [])
    root = (DATA_GRAPHICS, 1, 4, 3, 1)
    harness.block(1, 10, [(*root, 40, 3)])
    harness.block(2, 11, [(*root, 41 if moved else 40, 3)])
    harness.begin(active, pending)
    harness.results("_RTHP-ROOT-INSTRUMENTS")
    assert harness.counts() == (1, 0 if held else 1, 0)


def test_items_that_came_with_their_family_are_not_misses(harness):
    """A family the terminal had no room for comes back whole once it has:
    its items are new though their roots did not change, which lowering
    decided, not the roots."""
    _fresh(harness)
    collections = harness.constant("RTHP-PART-COLLECTIONS")
    active, pending = harness.bank(10, []), harness.bank(11, [TEXT])
    harness.block(1, 10, [(*TEXT_ROOT, 40, 3)], parts=0)
    harness.block(2, 11, [(*TEXT_ROOT, 40, 3)], parts=collections)
    harness.begin(active, pending)
    harness.judge(0)
    assert harness.counts() == (1, 0, 0)
    # With the family carried by both banks the same facts are a miss.
    _fresh(harness)
    harness.block(1, 10, [(*TEXT_ROOT, 40, 3)], parts=collections)
    harness.begin(active, pending)
    harness.judge(0)
    assert harness.counts() == (1, 1, 0)
