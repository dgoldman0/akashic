"""Bounded execution of mounted-source ownership against real UIDL layouts.

The production association and region validators run on both executors. Only
canonical widget recognition is a scripted seam; these tests exercise ownership,
not each widget family's independent type/instance contract. The ordinary pool
accessors run without their outer guard, under one fixture-owned document.
"""

import re

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


SOURCE = ROOT / "akashic/tui/uidl-tui.f"


class AssociationHarness(GrowthHarness):
    def __init__(self, backend, source=None):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        # KDOS's signed convenience word is outside this isolated closure.
        self.runtime.evaluate(b": 0>= 0< INVERT ;", step_budget=3_000_000)
        uidl = (ROOT / "akashic/liraq/uidl.f").read_text()
        texts = [SOURCE.read_text() if source is None else source, uidl]
        for name in ("region", "widget", "tui-sidecar"):
            texts.append((ROOT / f"akashic/tui/{name}.f").read_text())
        text = re.sub(r"(?m)\\[^\n]*$", "", "\n".join(texts))
        self.definitions = _definitions(text)
        # Include the production constant aliases as well as numeric constants.
        for match in re.finditer(r"(?m)^\s*(\S+)\s+CONSTANT\s+(\S+)\s*$", text):
            self.definitions[match[2]] = match[0]
        for name in ("UE.TYPE", "UIDL-ELEM-COUNT"):
            self.definitions[name] = re.search(
                rf"(?ms)^: {re.escape(name)}(?=\s).*?;[^\S\n]*$", uidl
            )[0]
        self.definitions["ASSOC-GENUINE"] = "VARIABLE ASSOC-GENUINE"
        self.definitions["_UTUI-MC-GENUINE-SEMANTIC?"] = (
            ": _UTUI-MC-GENUINE-SEMANTIC? DROP ASSOC-GENUINE @ ;"
        )
        self.serial = 0
        for name, size in (("_UDL-ELEMS", "_UDL-ELEMSZ"),
                           ("_UTUI-SIDECARS", "_UTUI-SC-SZ"),
                           ("_UTUI-MC-SOURCES", "_UTUI-MC-SOURCE-SIZE")):
            address = self.allocate(bytes(self.constant("_UTUI-MAX-ELEMS")
                                          * self.constant(size)))
            self.definitions[name] = f"{address} CONSTANT {name}"
        chunks, seen = [], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            code = re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration)
            for token in code.split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in ("_UTUI-MC-ASSOCIATE", "_UTUI-MC-SCRATCH-CLEAR"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.variable("_UTUI-ELEM-BASE", self.constant("_UDL-ELEMS"))
        self.variable("ASSOC-GENUINE", MASK64)

    def constant(self, name):
        token = self.definitions[name].split()[0]
        return self.constant(token) if token in self.definitions else int(token, 0)

    def write(self, address, offset, value):
        self.runtime.memory.write64(address + self.constant(offset), value & MASK64)

    def widget(self, region):
        address = self.allocate(bytes(self.constant("_WDG-HDR-SIZE")))
        self.write(address, "_WDG-O-REGION", region)
        return address

    def setup(self, depth=5, elements=32):
        parent = 0
        self.regions = []
        for _ in range(depth):
            region = self.allocate(bytes(self.constant("_RGN-DESC-SIZE")))
            self.write(region, "_RGN-O-H", 5)
            self.write(region, "_RGN-O-W", 80)
            self.write(region, "_RGN-O-PARENT", parent)
            self.regions.append(region)
            parent = region
        self.variable("_UTUI-RGN", self.regions[0])
        self.variable("_UDL-ECNT", elements)
        for i in range(elements):
            self.runtime.memory.write64(self.constant("_UDL-ELEMS")
                                        + i * self.constant("_UDL-ELEMSZ"), 1)
        self.target = self.widget(self.regions[-1])

    def mount(self, index, region, generation=17, owner=1, live=True, pointer=None):
        widget = self.widget(region) if pointer is None else pointer
        sidecar = self.constant("_UTUI-SIDECARS") + index * self.constant("_UTUI-SC-SZ")
        self.write(sidecar, "_UTUI-SC-O-WPTR", widget)
        self.write(sidecar, "_UTUI-SC-O-WOWNER", owner)
        source = self.constant("_UTUI-MC-SOURCES") + index * self.constant("_UTUI-MC-SOURCE-SIZE")
        self.write(source, "_UTUI-MCS-O-GENERATION", generation)
        if not live:
            self.runtime.memory.write64(self.constant("_UDL-ELEMS")
                                        + index * self.constant("_UDL-ELEMSZ"), 0)
        return widget

    def associate(self, expected, source=None, generation=17):
        assert self.results("_UTUI-MC-ASSOCIATE", self.target) == (
            self.constant("_UTUI-MC-S-" + expected),)
        if expected == "OK":
            assert self.variable("_UTUI-MC-A-SOURCE") == source
            assert self.variable("_UTUI-MC-A-GENERATION") == generation & MASK64


@pytest.fixture(params=("python", "native"))
def harness(request):
    return AssociationHarness(request.param)


@pytest.mark.parametrize("ancestor", (0, 1, 18, 36))
def test_sparse_document_resolves_unique_root_at_any_ancestor(harness, ancestor):
    h = harness
    h.setup(depth=37, elements=256)
    h.mount(255, h.regions[ancestor], generation=MASK64 - 1)
    h.associate("OK", source=255, generation=MASK64 - 1)


@pytest.mark.parametrize("same_region", (False, True))
def test_ambiguous_mounted_roots_fail_closed(harness, same_region):
    h = harness
    h.setup()
    h.mount(25, h.regions[1])
    h.mount(3, h.regions[1 if same_region else 3])
    h.associate("INVALID")


@pytest.mark.parametrize("generation", (0, MASK64))
def test_reserved_generations_are_invalid(harness, generation):
    h = harness
    h.setup()
    h.mount(7, h.regions[2], generation=generation)
    h.associate("INVALID")


def test_nonowners_and_dead_nodes_do_not_create_an_association(harness):
    h = harness
    h.setup()
    unrelated = h.allocate(bytes(h.constant("_RGN-DESC-SIZE")))
    h.mount(1, unrelated)
    h.mount(2, h.regions[2], owner=0)
    h.mount(3, h.regions[2], live=False)
    for index, pointer in enumerate((0, 3, MASK64 - 7), start=4):
        h.mount(index, h.regions[2], pointer=pointer)
    h.associate("UNAVAILABLE")
    h.mount(7, h.regions[2])
    h.associate("OK", source=7)


@pytest.mark.parametrize("defect", ("cycle", "self-cycle", "unaligned", "wrapped",
                                    "negative-height", "negative-width"))
def test_entire_region_chain_is_validated(harness, defect):
    h = harness
    h.setup()
    h.mount(7, h.regions[-1])
    if defect == "cycle":
        h.write(h.regions[0], "_RGN-O-PARENT", h.regions[2])
    elif defect == "self-cycle":
        h.write(h.regions[0], "_RGN-O-PARENT", h.regions[0])
    elif defect in ("unaligned", "wrapped"):
        h.write(h.regions[0], "_RGN-O-PARENT", 3 if defect == "unaligned" else MASK64 - 7)
    else:
        h.write(h.regions[0], "_RGN-O-H" if defect == "negative-height" else "_RGN-O-W", -1)
    h.associate("INVALID")


def test_document_membership_and_unavailable_precedence(harness):
    h = harness
    h.setup()
    h.variable("_UTUI-RGN", h.allocate(bytes(h.constant("_RGN-DESC-SIZE"))))
    h.associate("UNAVAILABLE")
    h.mount(7, h.regions[2])
    h.associate("INVALID")
    h.variable("ASSOC-GENUINE", 0)
    h.associate("UNAVAILABLE")


@pytest.mark.parametrize("count", (-1, 257))
def test_malformed_element_counts_fail_closed(harness, count):
    h = harness
    h.setup()
    h.variable("_UDL-ECNT", count & MASK64)
    h.associate("INVALID")


def test_fresh_association_observes_remount_and_reparenting(harness):
    h = harness
    h.setup()
    widget = h.mount(7, h.regions[2])
    h.associate("OK", source=7)
    h.mount(7, h.regions[2], generation=18, pointer=widget)
    h.associate("OK", source=7, generation=18)
    h.write(h.regions[3], "_RGN-O-PARENT", h.regions[0])
    h.associate("UNAVAILABLE")
    h.write(h.regions[3], "_RGN-O-PARENT", h.regions[2])
    h.associate("OK", source=7, generation=18)
    assert h.results("_UTUI-MC-SCRATCH-CLEAR") == ()
    assert h.variable("_UTUI-MC-A-ROOT") == 0
