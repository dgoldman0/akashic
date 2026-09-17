"""Execute exact-layout glyph admission and compare the full general result."""
import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64


class LayoutHarness(GrowthHarness):
    def __init__(self, backend="native", *, producer_source=None):
        super().__init__(backend, producer_source=producer_source,
                         extra_words=("_RTHP-D-TRY-GLYPH-LAYOUT?",
                                      "_RTHP-D-PLAN-REVISION-FENCE?"))

    def observe(self):
        memory = self.runtime.memory
        return (memory.read_bytes(self.active, self.bank_capacity),
                memory.read_bytes(self.pending, self.bank_capacity),
                memory.read_bytes(self.map_storage, self.final_count * 8 + 16),
                self.variable("_RTHP-D-OPS"),
                self.variable("_RTHP-D-PENDING-VISIBLE"),
                memory.read64(self.producer + self.offset("_RTHP.NEXT-OBJECT")))

    def references(self):
        return self.pending_items + self.final_count * 120


@pytest.fixture(params=("python", "native"))
def harness(request):
    return LayoutHarness(request.param)


ACTIVE = ((103, 0, 0, "A"), (101, 0, 2, "B"), (102, 1, 0, "C"))
PENDING = ((0, 0, "A"), (0, 2, "X"), (1, 0, "C"))


@pytest.mark.parametrize("changed", ((), (0,), (1,), (0, 1, 2)))
def test_layout_path_matches_general_ids_bytes_and_compact_plan(harness, changed):
    pending = tuple((row, col, "X" if i in changed else text)
                    for i, (_, row, col, text) in enumerate(ACTIVE))
    harness.setup(ACTIVE, pending)
    memory = harness.runtime.memory
    fresh = memory.read_bytes(harness.pending, harness.bank_capacity)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    # Other families may have already contributed operations.
    harness.variable("_RTHP-D-OPS", 7)
    assert harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    fast = harness.observe()
    assert harness.call("_RTHP-D-PLAN-COMPACT-GLYPHS")
    count = harness.variable("_RTHP-D-PLAN-GLYPHS")
    fast_plan = [harness.results("_RTHP-D-PLAN-GLYPH-AT", i) for i in range(count)]
    assert harness.call("_RTHP-D-PLAN-GLYPHS-VALID?")
    memory.write_bytes(harness.pending, fresh)
    harness.variable("_RTHP-D-OPS", 7)
    harness.normalize()
    for index in range(harness.final_count):
        assert harness.call("_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?", index)
    assert harness.observe() == fast
    assert harness.variable("_RTHP-D-OPS") == 7 + len(changed)
    assert harness.call("_RTHP-D-PLAN-COMPACT-GLYPHS")
    count = harness.variable("_RTHP-D-PLAN-GLYPHS")
    assert [harness.results("_RTHP-D-PLAN-GLYPH-AT", i) for i in range(count)] == fast_plan
    assert memory.read_bytes(harness.active, harness.bank_capacity) == harness.active_before


@pytest.mark.parametrize("cell", range(15))
def test_late_item_difference_leaves_banks_map_and_operation_count_untouched(harness, cell):
    harness.setup(ACTIVE, PENDING)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    address = harness.pending_items + 2 * 120 + cell * 8
    memory = harness.runtime.memory
    memory.write64(address, memory.read64(address) ^ 0x80)
    harness.variable("_RTHP-D-PENDING-VISIBLE", 77)
    before = harness.observe()
    assert not harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert harness.observe() == before


@pytest.mark.parametrize("mutation", ("offset", "length", "map", "rows", "cols", "count", "id-wrap"))
def test_layout_rejects_invalid_references_map_geometry_and_namespace_without_writes(harness, mutation):
    harness.setup(ACTIVE, PENDING)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    memory = harness.runtime.memory
    if mutation == "offset":
        memory.write64(harness.references() + 2 * 16, 4)
    elif mutation == "length":
        memory.write64(harness.references() + 2 * 16 + 8, 2)
    elif mutation == "map":
        memory.write64(harness.mapping + 8, 99)
    elif mutation in ("rows", "cols", "count"):
        field = "GLYPH-SLOT-COUNT" if mutation == "count" else mutation.upper()
        harness.field(harness.pending, "_RTHP-TB." + field, 9)
    else:
        harness.variable("_RTHP-D-PENDING-FIRST", MASK64)
    before = harness.observe()
    assert not harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert harness.observe() == before


def test_equal_text_at_different_valid_offsets_is_not_marked_changed(harness):
    harness.setup(ACTIVE, tuple((row, col, text) for _, row, col, text in ACTIVE))
    memory = harness.runtime.memory
    refs = harness.references()
    text = refs + 3 * 16
    memory.write_bytes(text, b"CAB")
    for ordinal, offset in enumerate((1, 2, 0)):
        memory.write64(refs + ordinal * 16, offset)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    assert harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert harness.variable("_RTHP-D-OPS") == 0
    assert memory.read_bytes(harness.mapping, 24) == bytes(24)


def test_invisible_reserve_keeps_general_tombstone_canonicalization(harness):
    harness.setup((*ACTIVE[:2], (102, 0, 0, None)),
                  ((0, 0, "A"), (0, 2, "B"), (0, 0, None)))
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    before = harness.observe()
    assert not harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert harness.observe() == before
    assert harness.call("_RTHP-D-NORMALIZE-GLYPH-IDS?")
    assert harness.plan() == []


def test_empty_layout_is_a_noop(harness):
    harness.setup((), (), frontier=100)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    before = harness.observe()
    harness.variable("_RTHP-D-PENDING-VISIBLE", 5)
    assert harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert harness.observe() == before


@pytest.mark.parametrize("controls", (0, 1))
def test_unchanged_layout_uses_current_visibility_for_revision_carrier(harness, controls):
    pending = tuple((row, col, text) for _, row, col, text in ACTIVE)
    harness.setup(ACTIVE, pending, controls=controls)
    memory = harness.runtime.memory
    if controls:
        for bank, object_id in ((harness.active, 100), (harness.pending, 104)):
            control, = harness.results("_RTHP-D-CONTROL-AT", 0, bank)
            harness.field(control, "_RTE-CONTROL.ID", object_id)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    # A prior draw's count must not make a visible run look like reserve space.
    harness.variable("_RTHP-D-PENDING-VISIBLE", 1)
    assert harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert harness.variable("_RTHP-D-OPS") == 0
    assert harness.call("_RTHP-D-PLAN-REVISION-FENCE?")
    assert harness.variable("_RTHP-D-OPS") == 1
    assert harness.call("_RTHP-D-PLAN-COMPACT-GLYPHS")
    if controls:
        assert harness.variable("_RTHP-D-PLAN-GLYPHS") == 0
        control_map = memory.read64(harness.producer + harness.offset("_RTHP.ORDER2-A"))
        assert memory.read64(control_map) == MASK64
    else:
        assert harness.variable("_RTHP-D-PLAN-GLYPHS") == 1
        assert harness.results("_RTHP-D-PLAN-GLYPH-AT", 0) == (0, 0)
    assert harness.variable("_RTHP-D-PENDING-VISIBLE") == len(ACTIVE)
    assert harness.call("_RTHP-D-PLAN-GLYPHS-VALID?")


@pytest.mark.parametrize("text", ("", "é", "☃", "🦉"))
def test_text_comparison_uses_bounded_utf8_bytes_including_empty_runs(harness, text):
    harness.setup(((101, 0, 0, text),), ((0, 0, text),))
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    assert harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert harness.variable("_RTHP-D-OPS") == 0


def test_full_width_ids_are_preserved_without_truncation(harness):
    base = (1 << 63) + 123
    active = ((base + 2, 0, 0, "A"), (base, 0, 2, "B"), (base + 1, 1, 0, "C"))
    harness.setup(active, PENDING, frontier=base + 3)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    assert harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    assert [harness.runtime.memory.read64(harness.pending_items + i * 120) for i in range(3)] == [r[0] for r in active]
    assert harness.call("_RTHP-D-PLAN-COMPACT-GLYPHS")
    assert harness.results("_RTHP-D-PLAN-GLYPH-AT", 0) == (1, 0)
    assert harness.call("_RTHP-D-PLAN-GLYPHS-VALID?")


@pytest.mark.parametrize("count", (32, 128, 784))
def test_sparse_text_change_removes_redundant_matching_work(count):
    harness = LayoutHarness()
    active = tuple((1001 + count - i - 1, 0, i, "A") for i in range(count))
    pending = tuple((0, i, "X" if i == count // 2 else "A") for i in range(count))
    harness.setup(active, pending, frontier=1001 + count, cols=count, rows=1)
    memory = harness.runtime.memory
    fresh = memory.read_bytes(harness.pending, harness.bank_capacity)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    before = harness.runtime.diagnostics.semantic_cycles
    assert harness.call("_RTHP-D-TRY-GLYPH-LAYOUT?")
    fast_steps = harness.runtime.diagnostics.semantic_cycles - before
    fast = harness.observe()
    memory.write_bytes(harness.pending, fresh)
    harness.variable("_RTHP-D-OPS", 0)
    assert harness.call("_RTHP-D-BUILD-SLOT-MAP?")
    before = harness.runtime.diagnostics.semantic_cycles
    assert harness.call("_RTHP-D-NORMALIZE-GLYPH-IDS?")
    for index in range(count):
        assert harness.call("_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?", index)
    general_steps = harness.runtime.diagnostics.semantic_cycles - before
    assert harness.observe() == fast
    assert fast_steps * 3 < general_steps
