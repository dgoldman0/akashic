"""Execute typed-grid capability fallback in the production collection writer.

Both semantic executors run the real writer, capability predicate, native item
walker, geometry/entry checks, output reservation and claim construction. Only
the external content packer is replaced by a bounded observable write. There is
no Desktop boot, terminal, worker or enlarged execution budget.
"""

import re
import struct

import pytest

from test_rich_glyph_growth import GrowthHarness, PRODUCER
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


COUNTERS = {
    "_RTHP-W-TOTAL": 2,
    "_RTHP-W-COLLECTIONS": 3,
    "_RTHP-W-CONTENT-ITEMS": 13,
    "_RTHP-W-CONTENT-UTF8": 17,
    "_RTHP-W-CONTENT-CURSOR": 24,
    "_RTHP-W-NEXT-ID": 101,
    "_RTHP-W-CLAIMS": 1,
}


class GridFallbackHarness(GrowthHarness):
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        sources = [PRODUCER.read_text()]
        for relative in (
            "tui/semantic-collections.f",
            "tui/uidl-collection-snapshot.f",
            "tui/uidl-menu-snapshot.f",
            "tui/rich-terminal/uidl-hybrid-adapter.f",
            "tui/rich-terminal/uidl-claim-ledger.f",
        ):
            sources.append((ROOT / "akashic" / relative).read_text())
        self.definitions = _definitions("\n".join(sources))
        # Snapshot sizes include constants expressed in terms of other sizes.
        for source in sources:
            source = re.sub(r"(?m)\\[^\n]*$", "", source)
            for match in re.finditer(
                r"(?m)^[ \t]*([^\n:]+?)\s+CONSTANT\s+(\S+)[ \t]*$", source
            ):
                self.definitions[match[2]] = match[0]

        self.definitions["_GF-TRACE"] = "VARIABLE _GF-TRACE"
        self.definitions["_GF-STAGE"] = (
            ": _GF-STAGE ( n -- ) _GF-TRACE @ 10 * + _GF-TRACE ! ;"
        )
        # Trace the real stages rather than replacing their decisions.
        for number, suffix in enumerate(
            ("GEOMETRY?", "ENTRY?", "NONOVERLAPPING?", "OUTPUT?"), 1
        ):
            name = "_RTHP-W-COLLECTION-" + suffix
            original = "_GF-REAL-" + suffix
            self.definitions[original] = self.definitions[name].replace(
                ": " + name, ": " + original, 1
            )
            self.definitions[name] = (
                f": {name} ( -- flag ) {number} _GF-STAGE {original} ;"
            )
        self.definitions["_RTHP-W-COLLECTION-CONTENT"] = """
: _RTHP-W-COLLECTION-CONTENT ( -- rte-status )
    5 _GF-STAGE
    _RTHP-W-P @ _RTHP.SOURCE-TEXT-A @ _RTHP-W-CONTENT-CURSOR @ +
        DUP _RTHP-W-CONTENT-A !
    8 90 FILL
    8 _RTHP-W-CONTENT-U !
    8 _RTHP-W-CONTENT-CURSOR +!
    RTE-S-OK ;
"""
        # Preserve the claim constructor's real module-storage authority check.
        self.definitions["_RUCL-OWNED-START"] = "CREATE _RUCL-OWNED-START"
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

        include("_RUCL-OWNED-START")
        for name in (
            "_RTHP-W-WRITE-TEXT-COLLECTION",
            "_RTHP-W-COLLECTION-SUPPORTED?",
            "_RTHP-W-APPEND-COLLECTION-CLAIMS?",
            "USCOL-TEXT-GRID-TYPED?",
        ):
            include(name)
        chunks.append("HERE _RUCL-OWNED-LIMIT !")
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0

    def guarded(self, data):
        allocation = self.allocate(b"LEFTGUAR" + data + b"RIGHTGUA")
        self.guarded_spans.append((allocation, len(data)))
        return allocation + 8

    def setup(self, roles, *, grid_cap=False, family="USCOL-F-TEXT-GRID"):
        self.guarded_spans = []
        family = self.constant(family)
        texts = (b"row", b"123456789", b"", b"tail")
        items = bytearray()
        for index, role in enumerate(roles):
            text = texts[index % len(texts)]
            items.extend(struct.pack("<9Q", index + 1, 0, index, 1, 1,
                                     role, 0, len(text), 0))
            items.extend(text)
            items.extend(bytes((-len(text)) % 8))
        self.item_count = len(roles)
        self.utf8_bytes = sum(len(texts[i % len(texts)]) for i in range(len(roles)))
        self.width = max(len(roles), 1)
        native_size = self.constant("USCOL-TEXT-FIXED-SIZE") + len(items)
        header = struct.pack(
            "<21Q", native_size, family, 1, 71, 0, 0, 1, self.width, 3,
            0, 1, self.width, 0, 0, 1, self.width, 0, 0, 0, 0, len(roles)
        )
        self.native = self.guarded(header + items)
        self.native_size = native_size
        summary = struct.pack("<8Q", family, 71, native_size, 0, len(roles),
                              self.utf8_bytes, 0, 0)
        self.descriptor = self.guarded(
            struct.pack("<13Q", 1, 4, 1, 0, 2, 3, 1, self.width,
                        2, 3, 1, self.width, 0) + summary
        )
        self.document = self.guarded(struct.pack("<Q", 31)
                                     + bytes(self.constant("RUHA-DOCUMENT-SIZE") - 8))
        self.producer = self.guarded(bytes(self.constant("RTHP-SIZE")))
        self.controls_size = 8 * self.constant("RTE-CONTROL-SIZE")
        self.correlations_size = 8 * self.constant("RUCP-CORRELATION-SIZE")
        self.claims_size = 8 * self.constant("RUCL-CLAIM-SIZE")
        self.controls = self.guarded(b"C" * self.controls_size)
        self.correlations = self.guarded(b"R" * self.correlations_size)
        self.claims = self.guarded(b"Q" * self.claims_size)
        self.text = self.guarded(b"T" * 128)
        for suffix, value in (
            ("OWNER", 1), ("OWNER-GEN", 2), ("REGION", 3),
            ("ROWS", 8), ("COLS", 20), ("SOURCE-GEN", 9),
            ("MAX-CONTROLS", 8), ("MAX-COLLECTIONS", 8),
            ("CONTROL-COUNT", 2), ("MENU-CONTROL-COUNT", 2),
            ("COLLECTION-NATIVE-A", self.native),
            ("CONTROLS-A", self.controls), ("CONTROLS-U", self.controls_size),
            ("CORR-A", self.correlations), ("CORR-U", self.correlations_size),
            ("CLAIMS-A", self.claims), ("CLAIMS-U", self.claims_size),
            ("SOURCE-TEXT-A", self.text), ("SOURCE-TEXT-U", 128),
        ):
            self.field(self.producer, "_RTHP." + suffix, value)
        features = self.constant("RTE-F-CONTROL-COLLECTIONS")
        if grid_cap:
            features |= self.constant("RTE-F-GRID-CELLS")
        self.field(self.producer + self.offset("_RTHP.LIMITS"),
                   "_RTE-L.FEATURES", features)
        for name, value in {
            **COUNTERS,
            "_RTHP-W-P": self.producer,
            "_RTHP-W-DESCRIPTOR": self.descriptor,
            "_RTHP-W-DOCUMENT": self.document,
            "_RTHP-W-DOC-NATIVE-O": 0,
            "_RTHP-W-DOC-NATIVE-U": native_size,
            "_GF-TRACE": 0,
        }.items():
            self.variable(name, value)
        self.before = self.snapshot()

    def snapshot(self):
        return {
            "counters": {name: self.variable(name) for name in COUNTERS},
            "controls": self.runtime.memory.read_bytes(self.controls, self.controls_size),
            "correlations": self.runtime.memory.read_bytes(self.correlations, self.correlations_size),
            "claims": self.runtime.memory.read_bytes(self.claims, self.claims_size),
            "text": self.runtime.memory.read_bytes(self.text, 128),
            "native": self.runtime.memory.read_bytes(self.native, self.native_size),
            "descriptor": self.runtime.memory.read_bytes(
                self.descriptor, self.constant("UCSN-DESCRIPTOR-SIZE")),
        }

    def write(self):
        return self.results("_RTHP-W-WRITE-TEXT-COLLECTION")

    def append_claims(self):
        # This is the count committed by LOWER-COLLECTIONS before claim building.
        self.field(self.producer, "_RTHP.CONTROL-COUNT", self.variable("_RTHP-W-TOTAL"))
        assert self.call("_RTHP-W-APPEND-COLLECTION-CLAIMS?")

    def guards(self):
        for allocation, size in self.guarded_spans:
            assert self.runtime.memory.read_bytes(allocation, 8) == b"LEFTGUAR"
            assert self.runtime.memory.read_bytes(allocation + 8 + size, 8) == b"RIGHTGUA"


@pytest.fixture(params=("python", "native"))
def harness(request):
    return GridFallbackHarness(request.param)


@pytest.mark.parametrize("typed_role", (4, 5, 6), ids=("number", "formula", "error"))
def test_typed_grid_without_capability_keeps_all_cells_residual(harness, typed_role):
    h = harness
    # The typed item follows differently padded strings, exercising ITEM-NEXT.
    h.setup((1, 1, typed_role, 1))
    assert h.write() == (h.constant("RTE-S-OK"),)
    assert h.variable("_GF-TRACE") == 12
    assert h.snapshot() == h.before
    h.append_claims()
    assert h.snapshot() == h.before
    h.guards()


@pytest.mark.parametrize("roles,grid_cap,family", (
    ((1, 1, 1), False, "USCOL-F-TEXT-GRID"),
    ((2, 3, 1), False, "USCOL-F-TEXT-GRID"),
    ((1, 4, 5, 6), True, "USCOL-F-TEXT-GRID"),
    ((1, 1, 1), False, "USCOL-F-TEXT-AREA"),
), ids=("plain-grid", "grid-headers", "typed-grid-enabled", "text-area"))
def test_supported_collection_still_writes_control_content_and_claim(harness, roles, grid_cap, family):
    h = harness
    h.setup(roles, grid_cap=grid_cap, family=family)
    assert h.write() == (h.constant("RTE-S-OK"),)
    assert h.variable("_GF-TRACE") == 12345
    assert h.variable("_RTHP-W-TOTAL") == COUNTERS["_RTHP-W-TOTAL"] + 1
    assert h.variable("_RTHP-W-COLLECTIONS") == COUNTERS["_RTHP-W-COLLECTIONS"] + 1
    assert h.variable("_RTHP-W-NEXT-ID") == COUNTERS["_RTHP-W-NEXT-ID"] + 1
    assert h.variable("_RTHP-W-CONTENT-ITEMS") == COUNTERS["_RTHP-W-CONTENT-ITEMS"] + len(roles)
    assert h.variable("_RTHP-W-CONTENT-UTF8") == COUNTERS["_RTHP-W-CONTENT-UTF8"] + h.utf8_bytes
    assert h.variable("_RTHP-W-CONTENT-CURSOR") == 32
    assert h.runtime.memory.read_bytes(h.text, 128) == b"T" * 24 + b"Z" * 8 + b"T" * 96
    control = h.controls + 2 * h.constant("RTE-CONTROL-SIZE")
    expected_kind = "RTE-CONTROL-TEXT-AREA" if family.endswith("AREA") else "RTE-CONTROL-TEXT-GRID"
    assert h.runtime.memory.read64(control + h.offset("_RTE-CONTROL.KIND")) == h.constant(expected_kind)
    h.append_claims()
    assert h.variable("_RTHP-W-CLAIMS") == COUNTERS["_RTHP-W-CLAIMS"] + 1
    claim = h.claims + h.constant("RUCL-CLAIM-SIZE")
    assert h.runtime.memory.read_bytes(claim, 80) == struct.pack(
        "<10Q", 31, 9, 1, 4, 71, 0, 2, 3, 3, 3 + h.width)
    after = h.snapshot()
    assert after["native"] == h.before["native"]
    assert after["descriptor"] == h.before["descriptor"]
    h.guards()


@pytest.mark.parametrize("invalid,trace,status", (
    ("geometry", 1, "RTE-S-UNAVAILABLE"),
    ("entry", 12, "RTE-S-INVALID"),
))
def test_missing_grid_capability_does_not_bypass_source_validation(harness, invalid, trace, status):
    h = harness
    h.setup((4,))
    if invalid == "geometry":
        h.field(h.descriptor, "_UCSN-D.CLIP-WIDTH", h.width + 1)
    else:
        h.runtime.memory.write64(h.native + 16, 99)  # Invalid family ABI.
    before = h.snapshot()
    assert h.write() == (h.constant(status),)
    assert h.variable("_GF-TRACE") == trace
    assert h.snapshot() == before
    h.guards()
