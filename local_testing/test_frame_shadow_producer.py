#!/usr/bin/env python3
"""The screen producer's shadow check of its shortcuts. A glyph plan that
kept a held plan or planned only the damaged rows is compared with the full
planner's, and a document's menu controls copied from the acknowledged bank
with the control planner's. The shortcut's result is the one that stays."""

from __future__ import annotations

import re

import pytest

from test_rich_terminal_control_map import _definitions, MegaForthRuntime, ROOT

PRODUCER = ROOT / "akashic/tui/rich-terminal/hybrid-screen-producer.f"
PLANNER = ROOT / "akashic/tui/rich-terminal/residual-glyph-planner.f"
MASK64 = (1 << 64) - 1

# The heap is a bump allocator over a block the test gives it. The full
# glyph planner and the control planner are stand-ins that run whatever the
# test chose; the control planner's request keeps the first ID it is given
# and its output the addresses it is given.
STUB = r'''
VARIABLE _ST-HEAP
: _ST-ALLOCATE  ( bytes -- addr ior ) 7 + -8 AND _ST-HEAP @ SWAP _ST-HEAP +! 0 ;
: _ST-FREE  ( addr -- ) DROP ;
VARIABLE _ST-FULL-XT
: _RTHP-BUILD-GLYPHS-FULL?  ( producer -- flag ) DROP _ST-FULL-XT @ EXECUTE ;
VARIABLE _ST-SPANS
VARIABLE _ST-FIRST-ID
VARIABLE _ST-CONTROLS-A
VARIABLE _ST-CORR-A
VARIABLE _ST-BUILD-XT
: _RTHP-W-RUCP-WORK-SPANS?  ( -- flag ) _ST-SPANS @ ;
: _RTHP-W-RUCP-REQUEST  ( next-id -- ) _ST-FIRST-ID ! ;
: RUCP-REQUEST-OUTPUT!  ( plan-a plan-u controls-a controls-u corr-a corr-u request -- )
    DROP DROP _ST-CORR-A ! DROP _ST-CONTROLS-A ! 2DROP ;
: RUCP-BUILD  ( request -- count text aligned max last status )
    DROP _ST-BUILD-XT @ EXECUTE ;
'''
STUBBED = ("_RTHP-BUILD-GLYPHS-FULL?", "_RTHP-W-RUCP-WORK-SPANS?", "_RTHP-W-RUCP-REQUEST",
           "RUCP-REQUEST-OUTPUT!", "RUCP-BUILD")
BUILD_RESULTS = ("_RTHP-W-COUNT", "_RTHP-W-TEXT", "_RTHP-W-ALIGNED", "_RTHP-W-MAX",
                 "_RTHP-W-LAST", "_RTHP-W-STATUS")


class ShadowHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text())
        planner = PLANNER.read_text()
        for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", planner):
            self.definitions[match[2]] = match[0]
        for name in STUBBED:
            del self.definitions[name]
        chunks, seen = [STUB], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            code = re.sub(r"\\[^\n]*", "", declaration)
            code = re.sub(r"\([^)]*\)", "", code)
            for token in code.split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in ("_RTHP-SH-GLYPHS", "_RTHP-SH-MENU", "FSHD-RESET", "_FSHD-ALLOCATE-XT",
                     "_FSHD-FREE-XT", "_RTHP-W-DRAW", *BUILD_RESULTS):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.variable("_ST-HEAP", self.allocate(bytes(1 << 16)))
        self.runtime.evaluate(b"' _ST-ALLOCATE _FSHD-ALLOCATE-XT ! ' _ST-FREE _FSHD-FREE-XT !")

    def allocate(self, data):
        self.serial += 1
        word = self.runtime.define_created(f"SHADOW-{self.serial}",
                                           initial_body=bytes(len(data) + 7))
        address = (word.body_address + 7) & -8
        self.runtime.memory.write_bytes(address, data)
        return address

    def variable(self, name, value=None):
        word = self.runtime.dictionary.find(name.encode())
        if value is None:
            return self.runtime.memory.read64(word.body_address)
        self.runtime.memory.write64(word.body_address, value & MASK64)
        return value

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def field(self, base, name, value=None):
        address = base + self.offset(name)
        if value is None:
            return self.runtime.memory.read64(address)
        self.runtime.memory.write64(address, value & MASK64)
        return value

    def run(self, name, *inputs):
        for value in inputs:
            self.runtime.main_context.data.push(value)
        self.runtime.execute(name, step_budget=3_000_000)
        assert self.runtime.main_context.data.snapshot() == ()
        assert self.runtime.main_context.returns.snapshot() == ()

    def shadow(self, name, *inputs, draw):
        """Run a shadow check with the build's own results set, and return
        what it counted. Those results must be as they were."""
        self.run("FSHD-RESET")
        for index, result in enumerate(BUILD_RESULTS):
            self.variable(result, 11 + index)
        self.variable("_RTHP-W-DRAW", draw)
        self.run(name, *inputs)
        assert [self.variable(result) for result in BUILD_RESULTS] == list(range(11, 17))
        return tuple(self.variable(f"FSHD-{name}") for name in (
            "CHECKS", "MISMATCHES", "SKIPPED", "FIRST-STAGE", "FIRST-ITEM", "FIRST-OFFSET",
            "FIRST-DRAW"))


@pytest.fixture(params=("python", "native"))
def h(request):
    return ShadowHarness(request.param)


# ---------------------------------------------------------------------
# Glyph shortcuts
# ---------------------------------------------------------------------

ITEM = 120   # RTE-GLYPH-RUN-PLAN-ITEM-SIZE
REF = 16     # RGRP-TEXT-REF-SIZE
PLAN = 144   # RTE-GLYPH-RUN-PLAN-SIZE
GLYPHS = 2   # FSHD-STAGE-PRODUCER-GLYPHS


class Glyphs:
    """A producer whose glyph banks hold COUNT runs and TEXT, with three
    rows of row damage."""

    def __init__(self, h, count=2, text=b"HELLO", rows=3):
        self.h = h
        self.producer = h.allocate(bytes(8192))
        self.items = h.allocate(bytes(8 * ITEM))
        self.refs = h.allocate(bytes(8 * REF))
        self.text = h.allocate(bytes(64))
        self.damage = h.allocate(bytes(8))
        h.field(self.producer, "_RTHP.GLYPH-ITEMS-A", self.items)
        h.field(self.producer, "_RTHP.GLYPH-REFS-A", self.refs)
        h.field(self.producer, "_RTHP.GLYPH-TEXT-A", self.text)
        h.field(self.producer, "_RTHP.ROWS", rows)
        h.field(self.producer, "_RTHP.ROW-DAMAGE-A", self.damage)
        h.field(self.producer, "_RTHP.ROW-DAMAGE-U", 8)
        h.field(self.producer, "_RTHP.GLYPH-COUNT", count)
        h.field(self.producer, "_RTHP.GLYPH-TEXT-USED", len(text))
        memory = h.runtime.memory
        memory.write_bytes(self.producer + h.offset("_RTHP.GLYPH-PLAN"), b"\x41" * PLAN)
        memory.write_bytes(self.items, b"\x42" * (count * ITEM))
        memory.write_bytes(self.refs, b"\x43" * (count * REF))
        memory.write_bytes(self.text, text)
        memory.write_bytes(self.damage, b"\x00\xff\x00")
        h.runtime.evaluate(f": _ST-W-ALL {self.damage} 3 -1 FILL ;".encode())

    def image(self):
        h = self.h
        memory = h.runtime.memory
        count = h.field(self.producer, "_RTHP.GLYPH-COUNT")
        used = h.field(self.producer, "_RTHP.GLYPH-TEXT-USED")
        return (count, used,
                memory.read_bytes(self.producer + h.offset("_RTHP.GLYPH-PLAN"), PLAN),
                memory.read_bytes(self.items, count * ITEM),
                memory.read_bytes(self.refs, count * REF),
                memory.read_bytes(self.text, used),
                memory.read_bytes(self.damage, 3))

    def check(self, full_plan):
        """Run the check against a full planner that runs FULL-PLAN, Forth
        that writes its result and leaves a flag."""
        h = self.h
        h.runtime.evaluate(f": _ST-FULL {full_plan} ; ' _ST-FULL _ST-FULL-XT !".encode())
        before = self.image()
        counts = h.shadow("_RTHP-SH-GLYPHS", self.producer, draw=77)
        # The shortcut's result, row damage included, is the one that stays.
        assert self.image() == before
        return counts


@pytest.fixture
def glyphs(h):
    return Glyphs(h)


def test_a_full_plan_equal_to_the_shortcut_is_five_equal_comparisons(h, glyphs):
    # The full planner marks every row and changes the build's own results.
    counts = glyphs.check("_ST-W-ALL 99 _RTHP-W-STATUS ! 98 _RTHP-W-COUNT ! -1")
    assert counts[:3] == (5, 0, 0)


def test_a_different_letter_is_the_first_difference_in_the_text(h, glyphs):
    counts = glyphs.check(f"80 {glyphs.text} 4 + C! -1")
    assert counts == (5, 1, 0, GLYPHS, 4, 4, 77)


def test_a_different_count_differs_in_the_header_before_any_run(h, glyphs):
    count = glyphs.producer + h.offset("_RTHP.GLYPH-COUNT")
    counts = glyphs.check(f"3 {count} ! -1")
    assert counts == (1, 1, 0, GLYPHS, 0, 0, 77)


def test_a_refused_full_plan_is_a_difference(h, glyphs):
    counts = glyphs.check("0")
    assert counts == (1, 1, 0, GLYPHS, 0, 0, 77)


# ---------------------------------------------------------------------
# Menu reuse
# ---------------------------------------------------------------------

CONTROL = 200      # RTE-CONTROL-SIZE
CORRELATION = 56   # RUCP-CORRELATION-SIZE
MENUS = 3          # FSHD-STAGE-PRODUCER-MENUS


class Menu:
    """The second document's two menu controls and their correlations, as
    reuse copied them, numbered from 900, over five bytes of text."""

    def __init__(self, h, count=2, text=5):
        self.h = h
        self.count = count
        self.control_bytes = bytes((i * 7 + 1) & 0xFF for i in range(count * CONTROL))
        self.corr_bytes = bytes((i * 5 + 3) & 0xFF for i in range(count * CORRELATION))
        self.controls = h.allocate(self.control_bytes)
        self.corr = h.allocate(self.corr_bytes)
        self.fresh_controls = h.allocate(self.control_bytes)
        self.fresh_corr = h.allocate(self.corr_bytes)
        for name, value in (
                ("_RTHP-W-P", h.allocate(bytes(4096))),
                ("_RTHP-W-OUT-CONTROLS-A", self.controls), ("_RTHP-W-OUT-CORR-A", self.corr),
                ("_RTHP-W-RUCP-CONTROL-U", count * CONTROL),
                ("_RTHP-W-RUCP-CORR-U", count * CORRELATION),
                ("_RTHP-W-DOC-RECORD-COUNT", count), ("_RTHP-W-DOC-TEXT-U", text),
                ("_RTHP-W-MR-NEW-FIRST", 900), ("_RTHP-W-MR-NEW-NEXT", 900 + count),
                ("_RTHP-W-DOCUMENT-I", 1), ("_ST-SPANS", -1)):
            h.variable(name, value)

    def check(self, *, status=0, count=2, text=5, last=901, change=""):
        """Run the check against a control planner that writes the copied
        controls and correlations, changed by CHANGE, and gives the results
        named."""
        h = self.h
        h.runtime.evaluate(
            f": _ST-BUILD {self.fresh_controls} _ST-CONTROLS-A @ {len(self.control_bytes)} MOVE"
            f" {self.fresh_corr} _ST-CORR-A @ {len(self.corr_bytes)} MOVE {change}"
            f" {count} {text} 0 0 {last} {status} ; ' _ST-BUILD _ST-BUILD-XT !".encode())
        h.variable("_ST-CONTROLS-A", 0)
        counts = h.shadow("_RTHP-SH-MENU", draw=55)
        memory = h.runtime.memory
        # The planner was asked for the document's controls from the first ID
        # reuse gave them, into storage of its own, and the copy stays.
        if counts[0]:
            assert h.variable("_ST-FIRST-ID") == 900
            fresh = h.variable("_ST-CONTROLS-A")
            assert not self.controls <= fresh < self.controls + len(self.control_bytes)
        assert memory.read_bytes(self.controls, len(self.control_bytes)) == self.control_bytes
        assert memory.read_bytes(self.corr, len(self.corr_bytes)) == self.corr_bytes
        return counts


@pytest.fixture
def menu(h):
    return Menu(h)


def test_a_fresh_plan_equal_to_the_copy_is_three_equal_comparisons(h, menu):
    assert menu.check()[:3] == (3, 0, 0)


def test_a_different_control_names_the_document_and_the_byte(h, menu):
    counts = menu.check(change="99 _ST-CONTROLS-A @ 210 + C!")
    assert counts == (3, 1, 0, MENUS, 4, 210, 55)


def test_a_different_correlation_is_the_documents_third_item(h, menu):
    counts = menu.check(change="99 _ST-CORR-A @ 60 + C!")
    assert counts == (3, 1, 0, MENUS, 5, 60, 55)


def test_a_refused_fresh_plan_differs_in_the_header(h, menu):
    counts = menu.check(status=7)
    assert counts == (1, 1, 0, MENUS, 3, 0, 55)


def test_a_fresh_plan_ending_at_another_identity_differs_in_the_header(h, menu):
    counts = menu.check(last=905)
    assert counts == (1, 1, 0, MENUS, 3, 24, 55)


def test_a_document_without_work_spans_is_skipped_not_passed(h, menu):
    h.variable("_ST-SPANS", 0)
    assert menu.check()[:3] == (0, 0, 1)


# ---------------------------------------------------------------------
# Where the checks run
# ---------------------------------------------------------------------

def _word(source, name):
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_each_check_runs_only_after_its_shortcut_was_taken():
    source = PRODUCER.read_text()
    glyphs = _word(source, "_RTHP-BUILD-GLYPHS?")
    held = glyphs[glyphs.index("_RTHP-GLYPHS-HELD?"):glyphs.index("0 OVER _RTHP.GLYPH-DRAW !")]
    damage, full = glyphs[glyphs.index("0 OVER _RTHP.GLYPH-DRAW !"):].split("ELSE", 1)
    hook = "FSHD? IF DUP _RTHP-SH-GLYPHS THEN"
    # A held plan is checked once it is wrapped and a plan of damaged rows
    # once it is made. A full plan is the path the check runs, so it is not
    # checked.
    assert held.index("_RTHP-WRAP-GLYPH-PLAN? IF") < held.index(hook)
    assert "_RTHP-BUILD-GLYPHS-DAMAGE? IF" in damage and hook in damage
    assert "_RTHP-SH-GLYPHS" not in full
    # Menu controls are checked only when reuse copied them.
    menus = _word(source, "_RTHP-BUILD-MENU-CONTROLS?")
    assert "_RTHP-W-MENU-REUSE? IF\n            FSHD? IF _RTHP-SH-MENU THEN\n          ELSE" in menus
    assert menus.count("_RTHP-SH-MENU") == 1
