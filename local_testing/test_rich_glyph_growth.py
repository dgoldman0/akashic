"""Execute bounded production glyph normalization and delayed-plan admission."""

import re
import struct

import pytest

from test_rich_terminal_control_map import _definitions, MegaForthRuntime, ROOT


MASK64 = (1 << 64) - 1
PRODUCER = ROOT / "akashic/tui/rich-terminal/hybrid-screen-producer.f"


class GrowthHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text())
        for relative in ("residual-glyph-planner.f", "uidl-hybrid-adapter.f"):
            source = (PRODUCER.parent / relative).read_text()
            for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;\s*$", source):
                self.definitions[match[1]] = match[0]
            for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", source):
                self.definitions[match[2]] = match[0]
        chunks, seen = [], set()

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

        for name in ("_RTHP-D-BUILD-SLOT-MAP?", "_RTHP-D-NORMALIZE-GLYPH-IDS?",
                     "_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?",
                     "_RTHP-D-PLAN-COMPACT-GLYPHS", "_RTHP-D-PLAN-GLYPHS-VALID?",
                     "_RTHP-R-BANK-CEILING?"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0

    def allocate(self, data):
        self.serial += 1
        word = self.runtime.define_created(f"GROWTH-{self.serial}", initial_body=bytes(len(data) + 7))
        address = (word.body_address + 7) & -8
        self.runtime.memory.write_bytes(address, data)
        return address

    def constant(self, name):
        return int(self.definitions[name].split()[0], 0)

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def field(self, base, name, value):
        self.runtime.memory.write64(base + self.offset(name), value)

    def variable(self, name, value=None):
        word = self.runtime.find(name)
        assert word is not None, name
        if value is None:
            return self.runtime.memory.read64(word.body_address)
        self.runtime.memory.write64(word.body_address, value)

    def results(self, name, *inputs):
        stack = self.runtime.main_context.data
        assert stack.snapshot() == ()
        for value in inputs:
            stack.push(value)
        self.runtime.execute(name, step_budget=3_000_000)
        result = stack.snapshot()
        while stack.depth():
            stack.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def call(self, name, *inputs):
        result = self.results(name, *inputs)
        assert len(result) == 1
        return result == (MASK64,)

    def bank(self, runs, controls, capacity):
        bank = self.allocate(bytes(capacity))
        for name, value in (("_RTHP-TB.COLS", 8), ("_RTHP-TB.ROWS", 2),
                            ("_RTHP-TB.CONTROL-COUNT", controls),
                            ("_RTHP-TB.GLYPH-SLOT-COUNT", len(runs))):
            self.field(bank, name, value)
        items = (bank + self.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
                 + controls * (self.constant("RTE-CONTROL-SIZE")
                               + self.constant("RUCP-CORRELATION-SIZE")))
        refs = items + len(runs) * self.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
        text = bytearray()
        for index, (object_id, row, col, label) in enumerate(runs):
            visible = label is not None
            item = items + index * self.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
            fields = (object_id, 0, row, col, 1, 1, 2, 8, 0, MASK64 if visible else 0,
                      0, 0, 0, int(visible), 0)
            self.runtime.memory.write_bytes(item, struct.pack("<15Q", *fields))
            self.runtime.memory.write_bytes(refs + index * 16,
                                            struct.pack("<2Q", len(text), int(visible)))
            if visible:
                text.extend(label.encode())
        self.field(bank, "_RTHP-TB.GLYPH-TEXT-USED", len(text))
        self.runtime.memory.write_bytes(refs + len(runs) * 16, bytes(text))
        return bank, items

    def setup(self, active_runs, pending_positions, *, controls=1,
              pending_controls=None, frontier=104, map_bytes=None, matched=True):
        pending_controls = controls if pending_controls is None else pending_controls
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        for name, value in (("_RTHP.MAX-COLS", 8), ("_RTHP.MAX-ROWS", 2),
                            ("_RTHP.MAX-CONTROLS", max(controls, pending_controls)),
                            ("_RTHP.MAX-DOCUMENTS", 1), ("_RTHP.MAX-TEXT", 8),
                            ("_RTHP.NEXT-OBJECT", frontier)):
            self.field(self.producer, name, value)
        capacity, valid = self.results("_RTHP-TARGET-BANK-BYTES?", self.producer)
        assert valid == MASK64
        self.active, self.active_items = self.bank(active_runs, controls, capacity)
        pending = [(frontier + pending_controls + i, *position)
                   for i, position in enumerate(pending_positions)]
        self.pending, self.pending_items = self.bank(pending, pending_controls, capacity)
        self.final_count = max(len(active_runs), len(pending))
        self.map_storage = self.allocate(b"LEFTGUAR" + bytes(self.final_count * 8) + b"RIGHTGUA")
        self.mapping = self.map_storage + 8
        control_map = self.allocate(struct.pack("<Q", 1 if matched else 0) * max(pending_controls, 1))
        arena_end = control_map + max(pending_controls, 1) * 8
        for name, value in (("_RTHP.TARGET0-A", self.active), ("_RTHP.TARGET1-A", self.pending),
                            ("_RTHP.GLYPH-ID-MAP-A", self.mapping),
                            ("_RTHP.GLYPH-ID-MAP-U", self.final_count * 8 if map_bytes is None else map_bytes),
                            ("_RTHP.ORDER2-A", control_map),
                            ("_RTHP.ARENA-A", self.active),
                            ("_RTHP.ARENA-U", arena_end - self.active)):
            self.field(self.producer, name, value)
        for name, value in (("_RTHP-D-P", self.producer), ("_RTHP-D-ACTIVE", self.active),
                            ("_RTHP-D-PENDING", self.pending),
                            ("_RTHP-D-PENDING-FIRST", frontier), ("_RTHP-D-OPS", 0)):
            self.variable(name, value)
        self.active_before = self.runtime.memory.read_bytes(self.active, capacity)
        self.bank_capacity = capacity

    def normalize(self):
        assert self.call("_RTHP-D-BUILD-SLOT-MAP?")
        assert self.call("_RTHP-D-NORMALIZE-GLYPH-IDS?")
        return [self.runtime.memory.read64(self.pending_items + i * 120)
                for i in range(self.final_count)]

    def plan(self):
        for index in range(self.final_count):
            assert self.call("_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?", index)
        assert self.call("_RTHP-D-PLAN-COMPACT-GLYPHS")
        count = self.variable("_RTHP-D-PLAN-GLYPHS")
        result = [self.results("_RTHP-D-PLAN-GLYPH-AT", i) for i in range(count)]
        assert self.call("_RTHP-D-PLAN-GLYPHS-VALID?")
        assert self.runtime.memory.read_bytes(self.active, self.bank_capacity) == self.active_before
        assert self.runtime.memory.read_bytes(self.map_storage, 8) == b"LEFTGUAR"
        assert self.runtime.memory.read_bytes(self.mapping + self.final_count * 8, 8) == b"RIGHTGUA"
        return result


@pytest.fixture(params=("python", "native"))
def harness(request):
    return GrowthHarness(request.param)


ACTIVE = ((103, 0, 0, "A"), (101, 0, 2, "B"), (102, 0, 0, None))
PENDING = ((0, 0, "A"), (0, 1, "N"), (0, 4, "C"), (0, 6, "D"))


def test_growth_preserves_anchors_and_old_pool_before_appending(harness):
    harness.setup(ACTIVE, PENDING)
    assert harness.normalize() == [103, 102, 101, 104]
    assert harness.plan() == [(2, 0), (1, 0), (3, 1)]
    assert harness.runtime.memory.read64(harness.producer + harness.offset("_RTHP.NEXT-OBJECT")) == 104


def test_multiple_new_runs_get_unique_monotone_definitions(harness):
    harness.setup(ACTIVE, (*PENDING, (1, 0, "E")))
    assert harness.normalize() == [103, 102, 101, 104, 105]
    assert harness.plan() == [(2, 0), (1, 0), (3, 1), (4, 1)]


def test_initial_glyph_tail_can_start_at_existing_control_frontier(harness):
    harness.setup((), ((0, 0, "A"), (0, 2, "B")), frontier=100)
    assert harness.normalize() == [100, 101]
    assert harness.plan() == [(0, 1), (1, 1)]


@pytest.mark.parametrize("changes", [{"frontier": 106}, {"pending_controls": 2},
                                     {"matched": False}, {"map_bytes": 31}])
def test_growth_rejects_unowned_frontier_new_controls_or_short_map(harness, changes):
    harness.setup(ACTIVE, PENDING, **changes)
    before = harness.runtime.memory.read_bytes(harness.pending, harness.bank_capacity)
    assert not harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    assert harness.runtime.memory.read_bytes(harness.pending, harness.bank_capacity) == before
    assert harness.runtime.memory.read_bytes(harness.map_storage, 8) == b"LEFTGUAR"
    assert harness.runtime.memory.read_bytes(harness.mapping + 32, 8) == b"RIGHTGUA"


def test_growth_rejects_a_gap_or_duplicate_in_old_slot_namespace(harness):
    harness.setup(((101, 0, 0, "A"), (103, 0, 2, "B"), (103, 0, 0, None)), PENDING)
    assert not harness.call("_RTHP-D-BUILD-SLOT-MAP?")


def test_growth_cannot_append_speculative_invisible_slots(harness):
    harness.setup(ACTIVE, (*PENDING[:3], (0, 0, None)))
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    assert not harness.call("_RTHP-D-NORMALIZE-GLYPH-IDS?")


@pytest.mark.parametrize("mutation", ["old_define", "new_replace", "missing_define",
                                      "duplicate", "bad_index", "frontier_advanced"])
def test_delayed_plan_rejects_changed_definition_authority(harness, mutation):
    harness.setup(ACTIVE, PENDING)
    harness.normalize()
    harness.plan()
    memory = harness.runtime.memory
    if mutation == "old_define":
        memory.write64(harness.mapping, 5)
    elif mutation == "new_replace":
        memory.write64(harness.mapping + 16, 6)
    elif mutation == "missing_define":
        harness.variable("_RTHP-D-PLAN-GLYPHS", 2)
    elif mutation == "duplicate":
        memory.write64(harness.mapping + 8, 4)
    elif mutation == "bad_index":
        memory.write64(harness.mapping + 16, 99)
    else:
        harness.field(harness.producer, "_RTHP.NEXT-OBJECT", 105)
    assert not harness.call("_RTHP-D-PLAN-GLYPHS-VALID?")


def test_slot_ceiling_accounts_for_aligned_packed_menu_rows(harness):
    producer = harness.allocate(bytes(harness.constant("RTHP-SIZE")))
    for name, value in (("_RTHP.MAX-COLS", 1), ("_RTHP.MAX-ROWS", 137),
                        ("_RTHP.MAX-DOCUMENTS", 1), ("_RTHP.MAX-TEXT", 8),
                        ("_RTHP.SOURCE-TEXT-USED", 8),
                        ("_RTHP.GLYPH-TEXT-USED", 548),
                        ("_RTHP.DOCUMENT-COUNT", 1), ("_RTHP.ROWS", 137)):
        harness.field(producer, name, value)
    harness.variable("_RTHP-R-P", producer)
    assert harness.call("_RTHP-R-BANK-CEILING?")
    # The 144-byte aligned bitmap otherwise incorrectly admits one extra
    # 136-byte item/reference slot despite every caller byte being occupied.
    assert harness.variable("_RTHP-R-CEILING") == 137
