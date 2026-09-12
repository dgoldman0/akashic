"""Execute production APT glyph definition gates with bounded guest records."""

import re

import pytest

from test_rich_terminal_control_map import (
    _definitions, MegaForthRuntime, ROOT, MEGAPAD_ROOT, MAPPING_STEP_BUDGET,
)


SOURCE = ROOT / "akashic/tui/rich-terminal/apt1-engine.f"
MASK64 = (1 << 64) - 1


class GlyphDefinitionHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(
            SOURCE.read_text() + "\n" + (MEGAPAD_ROOT / "rich-terminal.f").read_text()
        )
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

        for name in ("_RTAPT-DEFINITION-REGION-OP?",
                     "_RTAPT-GLYPH-RUN-DEFINE-REGION?",
                     "_RTAPT-PUBLICATION-GLYPH?"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=MAPPING_STEP_BUDGET)
        self.serial = 0

    def allocate(self, size):
        self.serial += 1
        word = self.runtime.define_created(
            f"GLYPH-DEFINE-{self.serial}", initial_body=bytes(size + 7))
        return (word.body_address + 7) & -8

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s*\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def constant(self, name):
        return int(self.definitions[name].split()[0], 0)

    def field(self, base, name, value):
        self.runtime.memory.write64(base + self.offset(name), value)

    def variable(self, name, value):
        word = self.runtime.dictionary.find(name.encode())
        assert word is not None, name
        self.runtime.memory.write64(word.body_address, value)

    def value(self, name):
        return self.runtime.memory.read64(self.runtime.dictionary.find(name.encode()).body_address)

    def call(self, name, *inputs):
        context = self.runtime.main_context
        assert context.data.depth() == 0
        for value in inputs:
            context.data.push(value)
        self.runtime.execute(name, step_budget=MAPPING_STEP_BUDGET)
        assert context.data.depth() == 1
        result = context.data.pop()
        assert context.returns.snapshot() == ()
        assert result in (0, MASK64)
        return result == MASK64

    def seed(self, mode=1, *, active_regions=1, region_high=100):
        engine = self.allocate(536)
        owner = self.allocate(464)
        op = self.allocate(40)
        copy = self.allocate(128)
        self.field(engine, "_RTAPT-E.RET-MODE", mode)
        self.field(owner, "_RTAPT-O.ACTIVE-REGIONS", active_regions)
        self.field(owner, "_RTAPT-O.REGION-HIGH", region_high)
        self.field(op, "_RTAPT-P.KIND", self.constant("_RTAPT-OP-GLYPH-RUN-DEFINE"))
        self.field(op, "_RTAPT-P.COPY-U", 128)
        for field, value in (("OWNER", 7), ("GENERATION", 3), ("OBJECT", 111),
                             ("REGION", 100), ("COLS", 3), ("ROWS", 1),
                             ("VISIBLE", 1), ("FG-RGBA", 0xFFFFFFFF),
                             ("BG-RGBA", 0xFF), ("TEXT-U", 3)):
            self.field(copy, "_RTAPT-LD." + field, value)
        self.runtime.memory.write_bytes(copy + 120, b"abc")
        for name, value in (("_RTAPT-LD-E", engine), ("_RTAPT-LD-O", owner),
                            ("_RTAPT-LD-OWNER", 7), ("_RTAPT-LD-GEN", 3),
                            ("_RTAPT-LD-REGION", 100), ("_RTAPT-LD-REGION-OP", 999),
                            ("_RTAPT-PA-E", engine), ("_RTAPT-PF-O", owner),
                            ("_RTAPT-PF-P", op), ("_RTAPT-PF-COPY", copy),
                            ("_RTAPT-PA-I", 0), ("_RTAPT-PF-OHIGH", 110),
                            ("_RTAPT-PF-OCOUNT", 2), ("_RTAPT-PF-UTF8", 12)):
            self.variable(name, value)
        return engine, owner, op, copy


@pytest.fixture(scope="module", params=("python", "native"))
def harness(request):
    return GlyphDefinitionHarness(request.param)


def test_zero_backlink_is_exclusively_for_delta_glyph_definitions(harness):
    h = harness
    for mode in range(6):
        engine, _owner, op, _copy = h.seed(mode)
        for name in ("_RTAPT-OP-GLYPH-RUN-DEFINE", "_RTAPT-OP-INSTRUMENT-DEFINE"):
            h.field(op, "_RTAPT-P.KIND", h.constant(name))
            assert h.call("_RTAPT-DEFINITION-REGION-OP?", op, 0, engine) == (
                mode == 1 and name == "_RTAPT-OP-GLYPH-RUN-DEFINE")
            h.field(op, "_RTAPT-P.REGION-OP", 1)
            assert h.call("_RTAPT-DEFINITION-REGION-OP?", op, 1, engine)
            assert not h.call("_RTAPT-DEFINITION-REGION-OP?", op, 0, engine)
            h.field(op, "_RTAPT-P.REGION-OP", 0)
    assert all(h.value(name) == 0 for name in ("_RTAPT-DRO-P", "_RTAPT-DRO-I", "_RTAPT-DRO-E"))


def test_delta_capture_requires_an_acknowledged_region(harness):
    h = harness
    for mode, active_regions, region_high, accepted in (
        (1, 1, 100, True), (1, 0, 100, False), (1, 1, 99, False),
        (2, 1, 100, False), (3, 1, 100, False), (4, 1, 100, False),
    ):
        engine, owner, _op, _copy = h.seed(
            mode, active_regions=active_regions, region_high=region_high)
        before = (h.runtime.memory.read_bytes(engine, 536),
                  h.runtime.memory.read_bytes(owner, 464))
        assert h.call("_RTAPT-GLYPH-RUN-DEFINE-REGION?") == accepted
        assert h.value("_RTAPT-LD-REGION-OP") == 0
        assert before == (h.runtime.memory.read_bytes(engine, 536),
                          h.runtime.memory.read_bytes(owner, 464))


def test_start_capture_still_requires_exact_owner_generation_region_backlink(harness):
    h = harness
    for field, changed in ((None, None), ("OWNER", 8), ("GENERATION", 4), ("REGION", 99)):
        engine, _owner, op, _copy = h.seed(2)
        region_copy = h.allocate(104)
        h.field(engine, "_RTAPT-E.OP-COUNT", 1)
        h.field(engine, "_RTAPT-E.OPS-A", op)
        h.field(engine, "_RTAPT-E.COPY-A", region_copy)
        h.field(engine, "_RTAPT-E.COPY-U", 104)
        h.field(engine, "_RTAPT-E.COPY-USED", 104)
        h.field(op, "_RTAPT-P.KIND", h.constant("_RTAPT-OP-REGION-DEFINE"))
        h.field(op, "_RTAPT-P.COPY-U", 104)
        for name, value in (("OWNER", 7), ("GENERATION", 3), ("REGION", 100)):
            h.field(region_copy, "_RTAPT-RD." + name, value)
        if field:
            h.field(region_copy, "_RTAPT-RD." + field, changed)
        assert h.call("_RTAPT-GLYPH-RUN-DEFINE-REGION?") == (field is None)
        assert h.value("_RTAPT-LD-REGION-OP") == (1 if field is None else 0)


def test_delta_publication_rechecks_region_shape_and_monotonic_definition(harness):
    h = harness
    for defect in (None, "start", "no_active_region", "region_high", "old_id",
                   "forged_backlink", "short_copy", "invalid_utf8", "parent"):
        engine, owner, op, copy = h.seed(2 if defect == "start" else 1)
        if defect == "no_active_region":
            h.field(owner, "_RTAPT-O.ACTIVE-REGIONS", 0)
        elif defect == "region_high":
            h.field(copy, "_RTAPT-LD.REGION", 101)
        elif defect == "old_id":
            h.field(copy, "_RTAPT-LD.OBJECT", 110)
        elif defect == "forged_backlink":
            h.field(op, "_RTAPT-P.REGION-OP", 1)
        elif defect == "short_copy":
            h.field(op, "_RTAPT-P.COPY-U", 120)
        elif defect == "invalid_utf8":
            h.runtime.memory.write_bytes(copy + 120, b"a\nb")
        elif defect == "parent":
            h.field(copy, "_RTAPT-LD.PARENT", 1)
        before = (h.runtime.memory.read_bytes(engine, 536),
                  h.runtime.memory.read_bytes(owner, 464))
        assert h.call("_RTAPT-PUBLICATION-GLYPH?") == (defect is None)
        assert before == (h.runtime.memory.read_bytes(engine, 536),
                          h.runtime.memory.read_bytes(owner, 464))
        assert h.value("_RTAPT-PF-OHIGH") == (111 if defect is None else 110)
        assert h.value("_RTAPT-PF-OCOUNT") == (3 if defect is None else 2)
        assert h.value("_RTAPT-PF-UTF8") == (15 if defect is None else 12)
