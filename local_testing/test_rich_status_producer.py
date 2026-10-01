"""Execute production structured-status lowering and immutable candidate paths.

The ordinary model, producer and engine validators are the real Forth words.
Caller-owned banks provide bounded geometry and immutable source fixtures.
"""
import re
import struct

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64, PRODUCER
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


class StatusHarness(GrowthHarness):
    def __init__(self, backend, *, extra_words=(), overrides=None):
        self.backend = backend
        self.runtime = MegaForthRuntime(execution_backend=backend)
        if extra_words:
            from tests.simulator.test_kdos_exceptions import _load_exceptions
            self.runtime = _load_exceptions(self.runtime)
        source = PRODUCER.read_text()
        for relative in (
            "tui/rich-terminal/uidl-hybrid-adapter.f",
            "tui/rich-terminal/residual-glyph-planner.f",
            "tui/rich-terminal/uidl-claim-ledger.f",
            "tui/rich-terminal/uidl-semantic-content-stx1.f",
            "tui/rich-terminal/uidl-semantic-items-itm1.f",
            "tui/uidl-menu-snapshot.f", "tui/semantic-collections.f",
            "tui/uidl-status-field-snapshot.f", "tui/status-field-model.f",
            "tui/uidl-field-snapshot.f", "tui/field-model.f", "tui/field-content.f",
            "tui/rich-terminal/fdc1.f",
            "tui/data-graphics-model.f", "tui/uidl-data-graphics-snapshot.f",
            "tui/uidl-collection-snapshot.f", "text/utf8.f", "utils/string.f",
        ):
            candidate = ROOT / "akashic" / relative
            if candidate.exists():
                source += "\n" + candidate.read_text().split("[DEFINED] GUARDED")[0]
        self.definitions = _definitions(source)
        declarations = re.sub(r"\\[^\n]*|\([^)]*\)", "", source)
        for name in re.findall(r"\bVARIABLE\s+(\S+)", declarations):
            self.definitions[name] = f"VARIABLE {name}"
        for match in re.finditer(r"(?m)^([^\n]+?)\s+CONSTANT\s+(\S+)[ \t]*(?:\\[^\n]*)?$", source):
            if not match[1].lstrip().startswith(("\\", "'")):
                self.definitions[match[2]] = match[0]
        self.definitions["_USF-OWNED-START"] = "CREATE _USF-OWNED-START 8 ALLOT"
        for marker in ("_UFLD-OWNED-START", "_UFLDC-OWNED-START",
                       "_FDC1-OWNED-START", "_FDC1-OWNED-END"):
            self.definitions[marker] = f"CREATE {marker} 8 ALLOT"
        self.definitions["_RUCL-OWNED-START"] = "CREATE _RUCL-OWNED-START 8 ALLOT"
        self.definitions["_UTF8-DECODE-STATE"] = "CREATE _UTF8-DECODE-STATE 48 ALLOT"
        self.definitions["_USF-MAX-TEXT-BYTES"] = "9223372036854775728 CONSTANT _USF-MAX-TEXT-BYTES"
        engine_lines = (ROOT / "akashic/tui/rich-terminal/engine.f").read_text().splitlines()
        for index, line in enumerate(engine_lines):
            if line.strip().startswith("CONSTANT "):
                first = index - 1
                while engine_lines[first].startswith(" "):
                    first -= 1
                self.definitions[line.split()[1]] = "\n".join(engine_lines[first:index+1])
        self.definitions.update(overrides or {})
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

        for name in (
            "RTHP-STORAGE-BYTES", "_RTHP-LAYOUT",
            "_RTHP-BUILD-STATICS", "_RTHP-W-BUILD-OPTIONAL-STATICS",
            "_RTHP-COPY-STATUS-SOURCE?", "_RTHP-STATICS-FIXED?",
            "_RTHP-WRAP-HYBRID", "_RTHP-PACK-ADMITTED-CANDIDATE",
            "_RTHP-PACKED-BANK?", "_RTHP-PACK-STATICS-A",
            "_RTHP-PACK-STATIC-CORR-A", "_RTHP-PACK-STATIC-TEXT-A",
            "_RTHP-STATICS-REUSABLE?", "_RTHP-STATICS-NORMALIZE", *extra_words,
        ):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.variable("_USF-OWNED-LIMIT", self.runtime.find("_USF-OWNED-START").body_address + 8)
        self.variable("_RUCL-OWNED-LIMIT", self.runtime.find("_RUCL-OWNED-START").body_address + 8)
        for marker in ("_UFLD", "_UFLDC"):
            if self.runtime.find(marker + "-OWNED-LIMIT"):
                self.variable(marker + "-OWNED-LIMIT",
                              self.runtime.find(marker + "-OWNED-START").body_address + 8)

    def setup(self, *, label=b"Mode", value=b"Ready", width=20, label_cols=6,
              row=3, col=2, clip=None, flags=3, status_native=512):
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        caps = (1, 1, 64, 256, 256, status_native, 0, 32, 8)
        size, = self.results("RTHP-STORAGE-BYTES", *caps)
        assert size > 0
        self.arena_size = size
        self.arena = self.allocate(b"LEFTGUAR" + bytes(size) + b"RIGHTGUA") + 8
        for name, value_ in (("ARENA-A", self.arena), ("ARENA-U", size),
                             ("MAX-DOCUMENTS", 1), ("MAX-RECORDS", 1),
                             ("MAX-TEXT", 64), ("MAX-COLLECTION-NATIVE", 256),
                             ("MAX-COLLECTION-DESCRIPTORS", 8), ("MAX-COLLECTIONS", 4),
                             ("MAX-CONTROLS", 5), ("MAX-DGRAPH-NATIVE", 256),
                             ("MAX-DGRAPH-DESCRIPTORS", 1), ("MAX-INSTRUMENT-REGIONS", 1),
                             ("MAX-INSTRUMENTS", 2), ("MAX-STATUS-NATIVE", status_native),
                             ("MAX-STATICS", status_native // 72), ("MAX-COLS", 32), ("MAX-ROWS", 8),
                             ("COLS", 32), ("ROWS", 8), ("OWNER", 1), ("OWNER-GEN", 2),
                             ("FIRST-OBJECT", 100), ("REGION", 7), ("SOURCE-GEN", 9),
                             ("DOCUMENT-COUNT", 1)):
            self.field(self.producer, "_RTHP." + name, value_)
        self.results("_RTHP-LAYOUT", self.producer)
        self.variable("_RTHP-W-P", self.producer)
        self.variable("_RTHP-W-DOCUMENTS", 1)
        self.dir = self.get("SOURCE-DIR-A")
        self.field(self.producer, "_RTHP.SOURCE-DIR-USED", self.constant("RUHA-DOCUMENT-SIZE"))
        self.runtime.memory.write64(self.dir, 11)
        text = label + value
        length = (72 + len(text) + 7) & -8
        self.model = struct.pack("<9Q", length, 1, 23, width, label_cols, 2, flags,
                                 len(label), len(value)) + text + bytes(length - 72 - len(text))
        cr, cc, ch, cw = clip or (row, col, 1, width)
        self.descriptor = struct.pack("<16Q", 1, 4, 0, 1, 0, row, col, 1, width,
                                      cr, cc, ch, cw, 3, length, len(text))
        self.runtime.memory.write_bytes(self.get("STATUS-NATIVE-A"), self.model)
        self.runtime.memory.write_bytes(self.get("STATUS-DESCRIPTORS-A"), self.descriptor)
        self.field(self.producer, "_RTHP.STATUS-DESCRIPTORS-USED", 128)
        self.field(self.producer, "_RTHP.STATUS-NATIVE-USED", length)
        for offset, number in ((160, 0), (168, 128), (176, 0), (184, length)):
            self.runtime.memory.write64(self.dir + offset, number)
        self.expected_text = text
        self.label = label
        self.value = value

    def get(self, suffix):
        return self.runtime.memory.read64(self.producer + self.offset("_RTHP." + suffix))

    def guards(self):
        assert self.runtime.memory.read_bytes(self.arena - 8, 8) == b"LEFTGUAR"
        assert self.runtime.memory.read_bytes(self.arena + self.arena_size, 8) == b"RIGHTGUA"

    def build(self):
        return self.results("_RTHP-BUILD-STATICS", self.producer)

    def admit(self):
        n = self.get("STATIC-COUNT")
        text = self.get("STATIC-TEXT-USED")
        aligned = (text + 7) & -8
        admission = self.producer + self.offset("_RTHP.ADMISSION")
        for name, value in (("STATIC-COUNT", n), ("STATIC-TEXT", text),
                            ("STATIC-ALIGNED", aligned), ("STATIC-MAX", text),
                            ("STATIC-LAST", 100 if n else 0),
                            ("STATIC-COPY", 176*n+aligned), ("STATIC-OPS", n)):
            self.field(admission, "_RTE-HA." + name, value)
        self.results("_RTHP-WRAP-HYBRID", self.producer)

    def pack(self):
        bank = self.get("TARGET0-A")
        self.bank = bank
        for name, value in (("COLS", 32), ("ROWS", 8), ("DOCUMENT-COUNT", 1),
                            ("OWNER", 1), ("GENERATION", 2), ("REGION", 7),
                            ("FIRST-OBJECT", 100), ("STATIC-COUNT", self.get("STATIC-COUNT")),
                            ("STATIC-TEXT-BYTES", self.get("STATIC-TEXT-USED"))):
            self.field(bank, "_RTHP-TB." + name, value)
        assert self.call("_RTHP-PACK-ADMITTED-CANDIDATE", bank, self.producer)
        assert self.call("_RTHP-PACKED-BANK?", bank, self.producer)
        self.bank_size = self.results("_RTHP-TARGET-BANK-BYTES?", self.producer)[0]
        return bank


@pytest.fixture(params=("python", "native"))
def h(request):
    return StatusHarness(request.param)


def test_status_preserves_authored_slots_text_and_exact_claim(h):
    h.setup(value="Ready ✓".encode())
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == 1
    assert h.get("STATIC-LAST") == 100
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 101
    item = h.get("STATICS-A")
    fields = struct.unpack("<22Q", h.runtime.memory.read_bytes(item, 176))
    assert fields[:17] == (1, 2, 100, 1, MASK64, 3, 7, 0, 3, 2, 1, 20, 8, 32, 6, 2, MASK64)
    assert h.runtime.memory.read_bytes(fields[17], fields[18]) == h.label
    assert h.runtime.memory.read_bytes(fields[19], fields[20]) == h.value
    claim = h.runtime.memory.read_bytes(h.get("CLAIMS-A"), h.constant("RUCL-CLAIM-SIZE"))
    assert struct.unpack("<4Q", claim[48:80]) == (3, 2, 4, 22)
    h.admit()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    h.guards()


@pytest.mark.parametrize("kwargs", ({"clip": (3, 3, 1, 19)}, {"flags": 0}, {"col": 20}))
def test_unrepresented_status_leaves_no_objects_text_or_claims(h, kwargs):
    h.setup(**kwargs)
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == h.get("STATIC-TEXT-USED") == h.get("CLAIMS-USED") == 0
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 100
    h.guards()


def test_bad_native_source_is_invalid_without_claims(h):
    h.setup()
    h.runtime.memory.write64(h.get("STATUS-NATIVE-A") + 40, 5)
    assert h.build() == (h.constant("RTE-S-INVALID"),)
    assert h.get("CLAIMS-USED") == 0
    h.guards()


def test_optional_capacity_refusal_restores_exact_prefix(h):
    h.setup()
    h.field(h.producer, "_RTHP.STATIC-TEXT-U", 1)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-STATICS") == (0,)
    assert h.get("STATIC-COUNT") == h.get("STATIC-TEXT-USED") == h.get("CLAIMS-USED") == 0
    h.guards()


def test_packed_status_owns_text_and_uses_offsets(h):
    h.setup()
    assert h.build() == (0,)
    h.pack()
    items, = h.results("_RTHP-PACK-STATICS-A", h.bank)
    text, = h.results("_RTHP-PACK-STATIC-TEXT-A", h.bank)
    assert h.runtime.memory.read64(items + 136) == 0
    assert h.runtime.memory.read64(items + 152) == len(h.label)
    assert h.runtime.memory.read_bytes(text, len(h.expected_text)) == h.expected_text
    before = h.runtime.memory.read_bytes(h.bank, h.bank_size)
    h.runtime.memory.write_bytes(h.get("STATIC-TEXT-A"), b"x" * len(h.expected_text))
    h.runtime.memory.write_bytes(h.get("STATUS-NATIVE-A"), bytes(len(h.model)))
    assert h.runtime.memory.read_bytes(h.bank, h.bank_size) == before
    h.guards()


@pytest.mark.parametrize("mutation", (None, "text", "slot", "severity", "identity"))
def test_exact_static_reuse_and_normalization(h, mutation):
    h.setup()
    assert h.build() == (0,)
    h.pack()
    other = h.get("TARGET1-A")
    original = h.runtime.memory.read_bytes(h.bank, h.bank_size)
    h.runtime.memory.write_bytes(other, original)
    h.field(other, "_RTHP-TB.REGION", 17)
    h.field(other, "_RTHP-TB.FIRST-OBJECT", 200)
    item, = h.results("_RTHP-PACK-STATICS-A", other)
    h.runtime.memory.write64(item + 16, 200)
    h.runtime.memory.write64(item + 48, 17)
    if mutation == "text":
        addr, = h.results("_RTHP-PACK-STATIC-TEXT-A", other)
        h.runtime.memory.write_bytes(addr, b"x")
    elif mutation == "slot":
        h.runtime.memory.write64(item + 112, 7)
    elif mutation == "severity":
        h.runtime.memory.write64(item + 120, 3)
    elif mutation == "identity":
        addr, = h.results("_RTHP-PACK-STATIC-CORR-A", other)
        h.runtime.memory.write64(addr, 12)
    assert h.call("_RTHP-STATICS-REUSABLE?", h.bank, other, 0) == (mutation is None)
    if mutation is None:
        h.results("_RTHP-STATICS-NORMALIZE", h.bank, other)
        h.field(other, "_RTHP-TB.REGION", 7)
        assert h.call("_RTHP-STATICS-REUSABLE?", h.bank, other, MASK64)
        assert h.runtime.memory.read64(item + 16) == 100
    assert h.runtime.memory.read_bytes(h.bank, h.bank_size) == original
    h.guards()


@pytest.mark.parametrize("feature,short", ((False, False), (True, False), (True, True)))
def test_optional_source_copy_uses_negotiation_and_independent_capacity(h, feature, short):
    h.setup()
    snapshot = h.allocate(bytes(176))
    descriptors = h.allocate(h.descriptor)
    native = h.allocate(h.model)
    directory = h.allocate(h.runtime.memory.read_bytes(h.dir, 192))
    for offset, value in ((144, descriptors), (152, 128), (160, native), (168, len(h.model))):
        h.runtime.memory.write64(snapshot + offset, value)
    h.variable("_RTHP-W-SNAP", snapshot)
    h.variable("_RTHP-W-DIRECTORY-A", directory)
    h.field(h.producer + h.offset("_RTHP.LIMITS"), "_RTE-L.FEATURES", 0x400 if feature else 0)
    if short:
        h.field(h.producer, "_RTHP.STATUS-NATIVE-U", len(h.model) - 8)
    h.runtime.memory.write_bytes(h.get("STATUS-NATIVE-A"), bytes(len(h.model)))
    assert h.call("_RTHP-COPY-STATUS-SOURCE?")
    copied = feature and not short
    assert h.get("STATUS-DESCRIPTORS-USED") == (128 if copied else 0)
    assert h.get("STATUS-NATIVE-USED") == (len(h.model) if copied else 0)
    assert h.runtime.memory.read_bytes(h.get("STATUS-NATIVE-A"), len(h.model)) == (
        h.model if copied else bytes(len(h.model)))
    assert h.runtime.memory.read64(h.dir + 168) == (128 if copied else 0)
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == int(copied)
    h.guards()


def test_invalid_source_slices_remain_invalid_without_capability(h):
    h.setup()
    snapshot = h.allocate(bytes(176))
    descriptors = h.allocate(h.descriptor)
    native = h.allocate(h.model)
    directory = h.allocate(h.runtime.memory.read_bytes(h.dir, 192))
    for offset, value in ((144, descriptors), (152, 128), (160, native), (168, len(h.model))):
        h.runtime.memory.write64(snapshot + offset, value)
    h.runtime.memory.write64(directory + 184, len(h.model) + 8)
    h.variable("_RTHP-W-SNAP", snapshot)
    h.variable("_RTHP-W-DIRECTORY-A", directory)
    assert not h.call("_RTHP-COPY-STATUS-SOURCE?")
    assert h.get("STATUS-NATIVE-USED") == 0
    h.guards()


def test_status_overlapping_an_existing_claim_refuses_rich_and_preserves_prefix(h):
    h.setup()
    prefix = struct.pack("<10Q", 11, 9, 1, 4, 23, 3, 3, 2, 4, 22)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), prefix)
    h.field(h.producer, "_RTHP.CLAIMS-USED", len(prefix))
    assert h.results("_RTHP-W-BUILD-OPTIONAL-STATICS") == (h.constant("RTE-S-UNAVAILABLE"),)
    assert h.get("STATIC-COUNT") == 0
    assert h.get("CLAIMS-USED") == len(prefix)
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"), len(prefix)) == prefix
    h.guards()


def test_static_empty_text_requires_null_pointer_at_fixed_boundary(h):
    h.setup(label=b"", label_cols=0)
    assert h.build() == (0,)
    h.admit()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    h.runtime.memory.write64(h.get("STATICS-A") + 136, h.get("STATIC-TEXT-A"))
    assert not h.call("_RTHP-STATICS-FIXED?", h.producer)


@pytest.mark.parametrize("mutation", ("claim", "row", "text", "id", "copy", "slot"))
def test_fixed_static_audit_rejects_changed_candidate(h, mutation):
    h.setup()
    assert h.build() == (0,)
    h.admit()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    item = h.get("STATICS-A")
    if mutation == "claim":
        h.runtime.memory.write64(h.get("CLAIMS-A") + 56, 3)
    elif mutation == "row":
        h.runtime.memory.write64(item + 64, 8)
    elif mutation == "text":
        h.runtime.memory.write64(item + 152, h.get("STATIC-TEXT-A"))
    elif mutation == "id":
        h.runtime.memory.write64(item + 16, 101)
    elif mutation == "copy":
        h.field(h.producer + h.offset("_RTHP.ADMISSION"), "_RTE-HA.STATIC-COPY", 176)
    else:
        h.runtime.memory.write64(item + 112, 0)
    assert not h.call("_RTHP-STATICS-FIXED?", h.producer)


def test_storage_admits_no_status_bank_and_rejects_a_partial_record(h):
    assert h.results("RTHP-STORAGE-BYTES", 2, 8, 128, 512, 256, 0, 0, 40, 12)[0] > 0
    assert h.results("RTHP-STORAGE-BYTES", 2, 8, 128, 512, 256, 73, 0, 40, 12) == (0,)


def test_static_overlap_strips_both_roots_without_claims(h):
    h.setup()
    second = bytearray(h.descriptor)
    struct.pack_into("<Q", second, 8, 5)
    struct.pack_into("<Q", second, 32, len(h.model))
    h.runtime.memory.write_bytes(h.get("STATUS-DESCRIPTORS-A") + 128, second)
    h.runtime.memory.write_bytes(h.get("STATUS-NATIVE-A") + len(h.model), h.model)
    h.runtime.memory.write64(h.dir + 168, 256)
    h.runtime.memory.write64(h.dir + 184, 2 * len(h.model))
    h.field(h.producer, "_RTHP.STATUS-DESCRIPTORS-USED", 256)
    h.field(h.producer, "_RTHP.STATUS-NATIVE-USED", 2 * len(h.model))
    assert h.results("_RTHP-W-BUILD-OPTIONAL-STATICS") == (0,)
    assert h.get("STATIC-COUNT") == h.get("STATIC-TEXT-USED") == h.get("CLAIMS-USED") == 0
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 100
    h.guards()


def test_overlap_refusal_retires_acknowledged_rich_before_cell_reveal(h):
    from test_rich_blank_frame import BlankHarness

    h.setup()
    prefix = struct.pack("<10Q", 11, 9, 1, 4, 23, 3, 3, 2, 4, 22)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), prefix)
    h.field(h.producer, "_RTHP.CLAIMS-USED", len(prefix))
    refusal, = h.results("_RTHP-W-BUILD-OPTIONAL-STATICS")
    assert refusal == h.constant("RTE-S-UNAVAILABLE")
    # Feed the actual lowering refusal into the existing publication protocol,
    # whose provider seam records BEGIN/SEAL and drives acknowledgement.
    blank = BlankHarness(h.backend)
    blank.variable("_RTHP-W-P", blank.producer)
    blank.variable("_RTHP-W-DRAW", 12)
    assert blank.results("_RTHP-REBUILD-RESULT", refusal, 0) == (
        blank.constant("SCB-S-WOULD-BLOCK"), 0)
    assert blank.phase() == blank.constant("_RTHP-PH-READY-BLANK")
    assert blank.read("_RTHP.TARGET-ACTIVE") == blank.active
    assert blank.results("_RTHP-BLANK-BEGIN", blank.producer) == (0,)
    assert blank.value("FP-BEGIN") == blank.constant("RTE-RETAINED-REPLACE-START")
    assert blank.step_sealed("READY-BLANK-REVEAL", "READY-BLANK", MASK64) == (0, 0, MASK64)
    assert blank.results("_RTHP-PREPARE-REVEAL",
                         blank.constant("_RTHP-PH-BLANK-REVEAL-SEALED"), blank.producer) == (0,)
    assert blank.value("FP-SEAL") == blank.constant("RTE-COMMIT-AND-REVEAL")
    assert blank.step_sealed("BLANK", "READY-BLANK-REVEAL", 0) == (0, 0, 0)
    assert blank.read("_RTHP.TARGET-ACTIVE") == blank.read("_RTHP.ACTIVE-DRAW") == 0
    assert blank.read("_RTHP-TB.VALID", blank.active) == 0
