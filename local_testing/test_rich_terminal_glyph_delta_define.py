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
        source = SOURCE.read_text()
        kdos = (MEGAPAD_ROOT / "kdos.f").read_text()
        exceptions = kdos[kdos.index("CREATE _HANDLERS  "):
                          kdos.index("\\ BIOS dictionary emitters")]
        self.definitions = _definitions(
            source + "\n" + (MEGAPAD_ROOT / "rich-terminal.f").read_text() +
            "\n" + exceptions
        )
        # The complete audit also uses production constant expressions, such
        # as combined masks and the signed maximum.  Compile their original
        # expressions, including the provider's two-line declarations.
        for pattern in (r"(?m)^[^\s:\\][^\n;]*[ \t]+CONSTANT[ \t]+(\S+)",
                        r"(?m)^[^\s:\\][^\n;]*\n[ \t]+CONSTANT[ \t]+(\S+)"):
            for match in re.finditer(pattern, source):
                self.definitions[match[1]] = match[0]
        # The audit's real CATCH uses KDOS's normal context-local handler
        # storage.  Include both declarations and their source initialization;
        # the runtime already supplies the BIOS stack/context words.
        for match in re.finditer(r"(?m)^CREATE (_(?:TASK-)?HANDLERS)[^\n]*\n\1[^\n]*",
                                 exceptions):
            self.definitions[match[1]] = match[0]
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
                     "_RTAPT-PUBLICATION-GLYPH?",
                     "_RTAPT-OWNER-LEDGERS?",
                     "_RTAPT-PUBLICATION-AUDIT?"):
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

    def seed_publication(self, mode=1, *, replacement=True, new_region=False,
                         active_regions=1, control_replacement=False):
        """Seed exact captured bytes and owner ledgers for the full audit.

        The mixed DELTA changes an existing glyph and appends one glyph into
        its acknowledged region.  There is deliberately no REGION_DEFINE.
        The optional region record exercises the unchanged START backlink.
        """
        engine, owner, _op, glyph = self.seed(mode, active_regions=active_regions)
        operations = []
        if control_replacement:
            control = self.allocate(152)
            for name, value in (("OWNER", 7), ("GENERATION", 3), ("CONTROL", 2),
                                ("KIND", self.constant("RTAPT-CONTROL-TAB")),
                                ("STATE", 3), ("REGION", 100), ("PARENT", 1),
                                ("LABEL-U", 5)):
                self.field(control, "_RTAPT-CD." + name, value)
            self.runtime.memory.write_bytes(control + 144, b"tabs!")
            operations.append(("CONTROL-REPLACE", control, 152,
                               self.constant("_RTAPT-CONTROL-FRAME-FIXED") + 5, 0))
            ledger = self.allocate(128)
            for index, kind in enumerate(("TABSET", "TAB")):
                for name, value in (("OWNER-SLOT", owner), ("GENERATION", 3),
                                    ("CONTROL", index + 1),
                                    ("META", self.constant("_RTAPT-CL-ACTIVE") |
                                     self.constant("RTAPT-CONTROL-" + kind)),
                                    ("ACTIVE-UTF8", 3 if index else 0)):
                    self.field(ledger + index * 64, "_RTAPT-CL." + name, value)
            for name, value in (("CONTROL-LEDGER-A", ledger), ("CONTROL-LEDGER-U", 128),
                                ("CONTROL-LEDGER-CAP", 2), ("CONTROL-LEDGER-USED", 2)):
                self.field(engine, "_RTAPT-E." + name, value)
        if new_region:
            region = self.allocate(104)
            for name, value in (("OWNER", 7), ("GENERATION", 3), ("REGION", 101),
                                ("COLS", 3), ("ROWS", 1), ("CLIP-COLS", 3),
                                ("CLIP-ROWS", 1), ("FLAGS", 3)):
                self.field(region, "_RTAPT-RD." + name, value)
            operations.append(("REGION-DEFINE", region, 104,
                               self.constant("_RTAPT-REGION-DEFINE-FRAME-BYTES"), 0))
            self.field(glyph, "_RTAPT-LD.REGION", 101)
        if replacement:
            old = self.allocate(128)
            self.runtime.memory.write_bytes(old, self.runtime.memory.read_bytes(glyph, 128))
            self.field(old, "_RTAPT-LD.OBJECT", 110)
            self.field(old, "_RTAPT-LD.REGION", 100)
            operations.append(("GLYPH-RUN-REPLACE", old, 128, 123, 0))
        operations.append(("GLYPH-RUN-DEFINE", glyph, 128, 123, int(new_region)))

        count = len(operations)
        ops = self.allocate(count * 40)
        copies = self.allocate(sum(item[2] for item in operations))
        offset = 0
        for index, (kind, source, size, _wire_size, backlink) in enumerate(operations):
            op = ops + index * 40
            for name, value in (("KIND", self.constant("_RTAPT-OP-" + kind)),
                                ("COPY-OFF", offset), ("COPY-U", size),
                                ("REGION-OP", backlink)):
                self.field(op, "_RTAPT-P." + name, value)
            self.runtime.memory.write_bytes(copies + offset,
                                            self.runtime.memory.read_bytes(source, size))
            offset += size
        for name, value in (("OWNERS-A", owner), ("OWNERS-U", 464), ("OWNER-CAP", 1),
                            ("OWNER-USED", 1), ("OPS-A", ops), ("OPS-U", count * 40),
                            ("OP-CAP", count), ("OP-COUNT", count), ("COPY-A", copies),
                            ("COPY-U", offset), ("COPY-USED", offset),
                            ("RET-BYTES", sum(item[3] for item in operations))):
            self.field(engine, "_RTAPT-E." + name, value)
        for name, value in (("STATE", self.constant("RTAPT-OWNER-ST-OPEN")),
                            ("OWNER", 7), ("GENERATION", 3), ("REGIONS", 2),
                            ("OBJECTS", 2), ("UTF8-BYTES", 15),
                            ("ACTIVE-OBJECTS", int(bool(active_regions))),
                            ("ACTIVE-UTF8", 12 if active_regions else 0),
                            ("OBJECT-HIGH", 110), ("PENDING-OBJECTS", 1),
                            ("PENDING-OBJECT-HIGH", 111), ("PENDING-UTF8", 3),
                            ("PENDING-REGIONS", int(new_region)),
                            ("PENDING-REGION-HIGH", 101 if new_region else 0)):
            self.field(owner, "_RTAPT-O." + name, value)
        if control_replacement:
            # Existing UTF8=12 includes the old three-byte tab label.  Its
            # five-byte replacement targets 14; the appended glyph adds 3.
            for name, value in (("ACTIVE-CONTROLS", 2), ("CONTROL-HIGH", 2),
                                ("ACTIVE-CONTROL-UTF8", 3), ("OBJECTS", 4),
                                ("PENDING-CONTROL-REPLACEMENTS", 1),
                                ("PENDING-UTF8-TARGET", 14), ("UTF8-BYTES", 17)):
                self.field(owner, "_RTAPT-O." + name, value)
        return engine, owner, ops, copies


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


@pytest.mark.parametrize("replacement", (False, True))
def test_delta_definition_passes_complete_publication_and_owner_ledgers(harness, replacement):
    h = harness
    engine, owner, ops, copies = h.seed_publication(replacement=replacement)
    before = tuple(h.runtime.memory.read_bytes(address, size) for address, size in
                   ((engine, 536), (owner, 464), (ops, 40 * (1 + replacement)),
                    (copies, 128 * (1 + replacement))))
    assert h.call("_RTAPT-OWNER-LEDGERS?", engine)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 3, 1, engine)
    assert h.value("_RTAPT-PF-TOTAL") == 1 + replacement
    assert h.value("_RTAPT-PF-RCOUNT") == 0
    assert h.value("_RTAPT-PF-OCOUNT") == 1
    assert h.value("_RTAPT-AUDIT-SCRATCH-DIRTY") == 0
    assert before == tuple(h.runtime.memory.read_bytes(address, size) for address, size in
                           ((engine, 536), (owner, 464), (ops, 40 * (1 + replacement)),
                            (copies, 128 * (1 + replacement))))


@pytest.mark.parametrize("defect", (
    "replace_start", "layout_start", "hidden_only", "no_region", "object_quota",
    "utf8_quota", "pending_count", "pending_high", "pending_utf8", "operation_count",
))
def test_complete_publication_preserves_region_quota_and_ledger_guards(harness, defect):
    h = harness
    mode = {"replace_start": 2, "layout_start": 4}.get(defect, 1)
    engine, owner, _ops, _copies = h.seed_publication(
        mode, replacement=False, active_regions=0 if defect in ("hidden_only", "no_region") else 1)
    if defect == "hidden_only":
        h.field(owner, "_RTAPT-O.HIDDEN-REGIONS", 1)
    elif defect == "object_quota":
        h.field(owner, "_RTAPT-O.OBJECTS", 1)
    elif defect == "utf8_quota":
        h.field(owner, "_RTAPT-O.UTF8-BYTES", 14)
    elif defect == "pending_count":
        h.field(owner, "_RTAPT-O.PENDING-OBJECTS", 0)
        h.field(owner, "_RTAPT-O.PENDING-OBJECT-HIGH", 0)
        h.field(owner, "_RTAPT-O.PENDING-UTF8", 0)
    elif defect == "pending_high":
        h.field(owner, "_RTAPT-O.PENDING-OBJECT-HIGH", 112)
    elif defect == "pending_utf8":
        h.field(owner, "_RTAPT-O.PENDING-UTF8", 2)
    elif defect == "operation_count":
        h.field(engine, "_RTAPT-E.OP-COUNT", 0)
    before = h.runtime.memory.read_bytes(owner, 464)
    assert not h.call("_RTAPT-PUBLICATION-AUDIT?", 3, 1, engine)
    assert h.value("_RTAPT-AUDIT-SCRATCH-DIRTY") == 0
    assert h.runtime.memory.read_bytes(owner, 464) == before


def test_start_definition_still_passes_full_audit_with_exact_region_backlink(harness):
    h = harness
    engine, owner, _ops, _copies = h.seed_publication(
        mode=2, replacement=False, new_region=True)
    before = h.runtime.memory.read_bytes(owner, 464)
    assert h.call("_RTAPT-OWNER-LEDGERS?", engine)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 3, 1, engine)
    assert h.value("_RTAPT-PF-TOTAL") == 2
    assert h.value("_RTAPT-PF-RCOUNT") == 1
    assert h.value("_RTAPT-PF-OCOUNT") == 1
    assert h.runtime.memory.read_bytes(owner, 464) == before


@pytest.mark.parametrize("defect", (None, "utf8_target", "utf8_quota", "object_quota"))
def test_glyph_append_after_control_replacement_audits_exact_target_totals(harness, defect):
    h = harness
    engine, owner, _ops, _copies = h.seed_publication(control_replacement=True)
    if defect == "utf8_target":
        h.field(owner, "_RTAPT-O.PENDING-UTF8-TARGET", 13)
    elif defect == "utf8_quota":
        h.field(owner, "_RTAPT-O.UTF8-BYTES", 16)
    elif defect == "object_quota":
        h.field(owner, "_RTAPT-O.OBJECTS", 3)
    before = h.runtime.memory.read_bytes(owner, 464)
    # Both nondefinitions are counted separately from the one glyph addition.
    # The public audit then recomputes all three operations before invoking
    # the same complete owner ledger with audit=true.
    assert h.call("_RTAPT-OWNER-LEDGERS-FROM?", 2, 0, engine) == (
        defect in (None, "utf8_target"))
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 3, 1, engine) == (defect is None)
    assert h.value("_RTAPT-PF-TOTAL") == 3
    assert h.value("_RTAPT-PF-UTF8") == 17
    assert h.value("_RTAPT-PF-OCOUNT") == 1
    assert h.value("_RTAPT-PF-RCOUNT") == 0
    assert h.value("_RTAPT-AUDIT-SCRATCH-DIRTY") == 0
    assert h.runtime.memory.read_bytes(owner, 464) == before


def test_mixed_delta_preserves_retained_instrument_regions_and_quota(harness):
    h = harness
    engine, owner, _ops, _copies = h.seed_publication(
        control_replacement=True, active_regions=2)
    # Three instruments remain live in a second region. Their objects and
    # five formatted bytes remain charged without any instrument operation.
    for name, value in (("REGION-HIGH", 101), ("ACTIVE-OBJECTS", 4),
                        ("OBJECTS", 7), ("ACTIVE-UTF8", 17),
                        ("PENDING-UTF8-TARGET", 19), ("UTF8-BYTES", 22)):
        h.field(owner, "_RTAPT-O." + name, value)
    before = h.runtime.memory.read_bytes(owner, 464)
    assert h.call("_RTAPT-OWNER-LEDGERS-FROM?", 2, 0, engine)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 3, 1, engine)
    assert h.value("_RTAPT-PF-TOTAL") == 3
    assert h.value("_RTAPT-PF-RCOUNT") == 0
    assert h.value("_RTAPT-PF-OCOUNT") == 1
    assert h.value("_RTAPT-PF-UTF8") == 22
    assert h.runtime.memory.read_bytes(owner, 464) == before
