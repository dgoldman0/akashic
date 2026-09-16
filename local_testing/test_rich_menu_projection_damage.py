"""Execute production menu-row capture and ACK-based projection damage words."""

import re
import struct

import pytest

from test_rich_terminal_control_map import _definitions, MegaForthRuntime, ROOT


PRODUCER = ROOT / "akashic/tui/rich-terminal/hybrid-screen-producer.f"
MASK64 = (1 << 64) - 1


class DamageHarness:
    def __init__(self, backend, source=None):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text() if source is None else source)
        ledger = (ROOT / "akashic/tui/rich-terminal/uidl-claim-ledger.f").read_text()
        for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;\s*$", ledger):
            self.definitions[match[1]] = match[0]
        for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", ledger):
            self.definitions[match[2]] = match[0]
        for relative in ("uidl-hybrid-adapter.f", "residual-glyph-planner.f"):
            text = (ROOT / "akashic/tui/rich-terminal" / relative).read_text()
            for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;\s*$", text):
                self.definitions[match[1]] = match[0]
            for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", text):
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

        for name in ("_RTHP-MENU-ROWS!", "_RTHP-RD-MARK-CELL-DAMAGE?",
                     "_RTHP-RD-MARK-PROJECTION-DAMAGE?", "_RTHP-RD-MARK-ACKED-MENUS?",
                     "_RTHP-RD-MARK-CURRENT-CLAIMS?", "_RTHP-PK-LAYOUT?",
                     "_RTHP-PACKED-BANK?", "_RTHP-U-CLONE?",
                     "_RTHP-RD-SCAN-ACTIVE-ROW?", "_RTHP-RD-COPY-ACTIVE-ROW?"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0

    def allocate(self, data):
        self.serial += 1
        word = self.runtime.define_created(f"DAMAGE-{self.serial}", initial_body=bytes(len(data) + 7))
        address = (word.body_address + 7) & -8
        self.runtime.memory.write_bytes(address, data)
        return address

    def variable(self, name, value):
        word = self.runtime.dictionary.find(name.encode())
        self.runtime.memory.write64(word.body_address, value)

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def field(self, base, name, value):
        self.runtime.memory.write64(base + self.offset(name), value)

    def constant(self, name):
        return int(self.definitions[name].split()[0], 0)

    def value(self, name):
        return self.runtime.memory.read64(self.runtime.dictionary.find(name.encode()).body_address)

    def results(self, name, *inputs):
        assert self.runtime.main_context.data.depth() == 0
        for value in inputs:
            self.runtime.main_context.data.push(value)
        self.runtime.execute(name, step_budget=3_000_000)
        result = self.runtime.main_context.data.snapshot()
        while self.runtime.main_context.data.depth():
            self.runtime.main_context.data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def call(self, name, *inputs):
        result = self.results(name, *inputs)
        assert len(result) == 1
        return result[0] == MASK64

    def claims(self, ranges):
        return self.allocate(b"".join(struct.pack("<10Q", 1, 1, 1, i, 0, 0,
                                                   lo & MASK64, 0, hi & MASK64, 4)
                                      for i, (lo, hi) in enumerate(ranges)))


@pytest.fixture(params=("python", "native"))
def harness(request):
    return DamageHarness(request.param)


def test_menu_bitmap_captures_only_prefix_and_preserves_caller_bounds(harness):
    claims = harness.claims(((1, 3), (2, 4), (5, 7)))
    storage = harness.allocate(b"LEFTGUAR" + b"?" * 8 + b"RIGHTGUA")
    assert harness.call("_RTHP-MENU-ROWS!", claims, 240, 2, storage + 8, 8)
    assert harness.runtime.memory.read_bytes(storage, 24) == b"LEFTGUAR\x00\x01\x01\x01\x00\x00\x00\x00RIGHTGUA"
    assert harness.call("_RTHP-MENU-ROWS!", 0, 0, 0, storage + 8, 8)
    assert harness.runtime.memory.read_bytes(storage + 8, 8) == bytes(8)


@pytest.mark.parametrize("ranges,count,used", [(((1, 9),), 1, 80),
                                            (((-1, 2),), 1, 80),
                                            (((3, 3),), 1, 80),
                                            (((1, 3),), 2, 80),
                                            (((1, 3),), 1, 79)])
def test_invalid_claim_geometry_or_prefix_cannot_overrun_rows(harness, ranges, count, used):
    claims = harness.claims(ranges)
    storage = harness.allocate(b"LEFTGUAR" + b"?" * 8 + b"RIGHTGUA")
    assert not harness.call("_RTHP-MENU-ROWS!", claims, used, count, storage + 8, 8)
    assert harness.runtime.memory.read_bytes(storage, 8) == b"LEFTGUAR"
    assert harness.runtime.memory.read_bytes(storage + 16, 8) == b"RIGHTGUA"


def test_closed_menu_and_residue_only_changes_survive_clean_cell_damage(harness):
    memory = harness.runtime.memory
    rows = 8
    producer = harness.allocate(bytes(3016))
    # No controls or glyphs: the existing packed address words place the
    # directory at the header and the row map after one real directory slot.
    adapter = (ROOT / "akashic/tui/rich-terminal/uidl-hybrid-adapter.f").read_text()
    match = re.search(r"(?m)^(\d+) CONSTANT RUHA-DOCUMENT-SIZE", adapter)
    assert match
    directory_size = int(match[1])
    header = int(harness.definitions["_RTHP-TARGET-BANK-HEADER-SIZE"].split()[0])
    bank = harness.allocate(bytes(header + directory_size) + bytes((0, 1, 1, 0, 0, 0, 0, 0)))
    harness.field(bank, "_RTHP-TB.DOCUMENT-COUNT", 1)
    damage = harness.allocate(bytes(rows))
    cell_damage = harness.allocate(bytes(rows))
    residue_damage = harness.allocate(bytes((0, 0, 0, 0, 0, 1, 0, 0)))
    harness.field(producer, "_RTHP.ARENA-A", bank)
    harness.field(producer, "_RTHP.ARENA-U", header + directory_size + rows)
    harness.field(producer, "_RTHP.ROW-DAMAGE-A", damage)
    for name, value in (("_RTHP-RD-P", producer), ("_RTHP-RD-BANK", bank),
                        ("_RTHP-RD-ROWS", rows), ("_RTHP-RD-CELL-DAMAGE-A", cell_damage),
                        ("_RTHP-RD-CELL-DAMAGE-U", rows),
                        ("_RTHP-RD-PROJECTION-DAMAGE-A", residue_damage),
                        ("_RTHP-RD-PROJECTION-DAMAGE-U", rows)):
        harness.variable(name, value)
    for name in ("_RTHP-RD-MARK-CELL-DAMAGE?", "_RTHP-RD-MARK-PROJECTION-DAMAGE?",
                 "_RTHP-RD-MARK-ACKED-MENUS?", "_RTHP-RD-MARK-CURRENT-CLAIMS?"):
        assert harness.call(name)
    assert memory.read_bytes(damage, rows) == bytes((0, 255, 255, 0, 0, 255, 0, 0))


def _bounded_target_producer(harness):
    producer = harness.allocate(bytes(harness.constant("RTHP-SIZE")))
    for name, value in (("_RTHP.MAX-COLS", 3), ("_RTHP.MAX-ROWS", 9),
                        ("_RTHP.MAX-DOCUMENTS", 2), ("_RTHP.MAX-CONTROLS", 2),
                        ("_RTHP.MAX-RECORDS", 2), ("_RTHP.MAX-TEXT", 13),
                        ("_RTHP.SOURCE-TEXT-U", 13)):
        harness.field(producer, name, value)
    bank_bytes, valid = harness.results("_RTHP-TARGET-BANK-BYTES?", producer)
    assert valid == MASK64
    return producer, bank_bytes


def test_full_packed_target_reserves_aligned_menu_rows_at_exact_capacity(harness):
    memory = harness.runtime.memory
    producer, bank_bytes = _bounded_target_producer(harness)
    header = harness.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
    entry = harness.constant("_RTHP-TARGET-ENTRY-SIZE")
    expected = (header + 2 * entry + 2 * harness.constant("RTE-CONTROL-SIZE")
                + 2 * harness.constant("RUCP-CORRELATION-SIZE") + 16
                + 27 * harness.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
                + 27 * harness.constant("RGRP-TEXT-REF-SIZE") + 112
                + 2 * harness.constant("RUHA-DOCUMENT-SIZE") + 16 + 2 * 32)
    assert bank_bytes == expected
    storage = harness.allocate(b"LEFTGUAR" + bytes(bank_bytes) + b"RIGHTGUA")
    bank = storage + 8
    harness.field(producer, "_RTHP.ARENA-A", bank)
    harness.field(producer, "_RTHP.ARENA-U", bank_bytes)
    for name, value in (("_RTHP-TB.COLS", 3), ("_RTHP-TB.ROWS", 9),
                        ("_RTHP-TB.COUNT", 2), ("_RTHP-TB.CONTROL-COUNT", 2),
                        ("_RTHP-TB.MENU-CONTROL-COUNT", 2),
                        ("_RTHP-TB.DOCUMENT-COUNT", 2),
                        ("_RTHP-TB.PROJECTION-RECTS", 2),
                        ("_RTHP-TB.GLYPH-SLOT-COUNT", 27),
                        ("_RTHP-TB.SOURCE-TEXT-USED", 13),
                        ("_RTHP-TB.MENU-TEXT-USED", 13),
                        ("_RTHP-TB.GLYPH-TEXT-USED", 108)):
        harness.field(bank, name, value)
    harness.variable("_RTHP-PK-P", producer)
    harness.variable("_RTHP-PK-BANK", bank)
    assert harness.call("_RTHP-PK-LAYOUT?")
    assert harness.value("_RTHP-PK-MENU-ROWS-A") == bank + bank_bytes - 16 - 64
    assert harness.value("_RTHP-PK-MENU-ROWS-U") == 16
    assert harness.value("_RTHP-PK-CURSOR") == bank + bank_bytes
    packed_bytes = harness.value("_RTHP-PK-TOTAL")
    assert packed_bytes == bank_bytes - header - 2 * entry
    harness.field(bank, "_RTHP-TB.VALID", harness.constant("_RTHP-TARGET-VALID-MAGIC"))
    harness.field(bank, "_RTHP-TB.PACKED-BYTES", packed_bytes)
    assert harness.call("_RTHP-PACKED-BANK?", bank, producer)

    # A former layout that omitted the row map cannot be admitted; neither
    # can an otherwise full target whose caller arena is one byte short.
    harness.field(bank, "_RTHP-TB.PACKED-BYTES", packed_bytes - 16)
    assert not harness.call("_RTHP-PACKED-BANK?", bank, producer)
    harness.field(bank, "_RTHP-TB.PACKED-BYTES", packed_bytes)
    harness.field(producer, "_RTHP.ARENA-U", bank_bytes - 1)
    assert not harness.call("_RTHP-PACKED-BANK?", bank, producer)
    assert memory.read_bytes(storage, 8) == b"LEFTGUAR"
    assert memory.read_bytes(bank + bank_bytes, 8) == b"RIGHTGUA"


def test_unchanged_clone_preserves_menu_bitmap_and_its_packed_extent(harness):
    memory = harness.runtime.memory
    producer, bank_bytes = _bounded_target_producer(harness)
    header = harness.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
    directory = harness.constant("RUHA-DOCUMENT-SIZE")
    packed_bytes = directory + 16  # Nine rows plus alignment padding.
    copy_bytes = header + packed_bytes
    storage = harness.allocate(b"LEFTGUAR" + bytes(bank_bytes)
                               + b"MIDGUARD" + b"?" * bank_bytes + b"RIGHTGUA")
    active, pending = storage + 8, storage + 16 + bank_bytes
    arena_bytes = 2 * bank_bytes + 8
    for name, value in (("_RTHP.ARENA-A", active), ("_RTHP.ARENA-U", arena_bytes),
                        ("_RTHP.TARGET0-A", active), ("_RTHP.TARGET1-A", pending),
                        ("_RTHP.TARGET-ACTIVE", active)):
        harness.field(producer, name, value)
    for name, value in (("_RTHP-TB.COLS", 3), ("_RTHP-TB.ROWS", 9),
                        ("_RTHP-TB.DOCUMENT-COUNT", 1),
                        ("_RTHP-TB.PACKED-BYTES", packed_bytes),
                        ("_RTHP-TB.VALID", harness.constant("_RTHP-TARGET-VALID-MAGIC")),
                        ("_RTHP-TB.DRAW", 7), ("_RTHP-TB.SOURCE-GEN", 9),
                        ("_RTHP-TB.CONTENT-EPOCH", 11)):
        harness.field(active, name, value)
    memory.write_bytes(active + header, b"D" * directory)
    bitmap = bytes((0, 1, 1, 0, 0, 1, 0, 0, 1)) + bytes(7)
    memory.write_bytes(active + header + directory, bitmap)
    assert harness.call("_RTHP-PACKED-BANK?", active, producer)
    original = memory.read_bytes(active, bank_bytes)
    for name, value in (("_RTHP-U-P", producer), ("_RTHP-U-ACTIVE", active),
                        ("_RTHP-U-DRAW", 8), ("_RTHP-U-SOURCE-GEN", 10),
                        ("_RTHP-U-CONTENT-EPOCH", 12)):
        harness.variable(name, value)
    assert harness.call("_RTHP-U-CLONE?")
    expected = bytearray(original[:copy_bytes])
    for name, value in (("_RTHP-TB.VALID", 0), ("_RTHP-TB.DRAW", 8),
                        ("_RTHP-TB.SOURCE-GEN", 10), ("_RTHP-TB.CONTENT-EPOCH", 12)):
        struct.pack_into("<Q", expected, harness.offset(name), value)
    assert memory.read_bytes(pending, copy_bytes) == expected
    assert memory.read_bytes(pending + header + directory, 16) == bitmap
    assert memory.read_bytes(pending + copy_bytes, bank_bytes - copy_bytes) == b"?" * (bank_bytes - copy_bytes)
    assert memory.read_bytes(active, bank_bytes) == original
    assert memory.read_bytes(storage, 8) == b"LEFTGUAR"
    assert memory.read_bytes(active + bank_bytes, 8) == b"MIDGUARD"
    assert memory.read_bytes(pending + bank_bytes, 8) == b"RIGHTGUA"

    before = memory.read_bytes(pending, bank_bytes)
    harness.field(producer, "_RTHP.ARENA-U", arena_bytes - 1)
    assert not harness.call("_RTHP-U-CLONE?")
    assert memory.read_bytes(pending, bank_bytes) == before


def _residual_row(h, spans, *, same=True, dirty=0):
    """An ACK row with holes occupied by ordinary semantic widgets."""
    producer = h.allocate(bytes(h.constant("RTHP-SIZE")))
    bank = h.allocate(bytes(h.constant("_RTHP-TARGET-BANK-HEADER-SIZE")))
    item_size = h.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
    items = h.allocate(bytes(item_size * len(spans)))
    refs = h.allocate(bytes(16 * len(spans)))
    text = b"".join(bytes((65 + i,)) * width for i, (_col, width) in enumerate(spans))
    text_a = h.allocate(text)
    cursor = 0
    for i, (col, width) in enumerate(spans):
        item = items + i * item_size
        for name, value in (("ROW", 0), ("COL", col), ("HEIGHT", 1), ("WIDTH", width),
                            ("VISIBLE", MASK64), ("TEXT-CAPACITY", width)):
            h.field(item, "_RTE-LPI." + name, value)
        h.runtime.memory.write_bytes(refs + i * 16, struct.pack("<QQ", cursor, width))
        cursor += width
    damage = h.allocate(b"LEFTGUAR" + bytes((dirty,)) + b"RIGHTGUA") + 8
    h.field(producer, "_RTHP.ROW-DAMAGE-A", damage)
    h.field(bank, "_RTHP-TB.GLYPH-SLOT-COUNT", len(spans))
    h.field(bank, "_RTHP-TB.GLYPH-TEXT-USED", len(text))
    for name, value in (("_RTHP-RD-P", producer), ("_RTHP-RD-BANK", bank),
                        ("_RTHP-RD-ACTIVE-ITEMS", items), ("_RTHP-RD-ACTIVE-REFS", refs),
                        ("_RTHP-RD-ACTIVE-TEXT", text_a), ("_RTHP-RD-COLS", 12),
                        ("_RTHP-RD-ROWS", 1), ("_RTHP-RD-ROW", 0),
                        ("_RTHP-RD-ACTIVE-I", 0),
                        ("_RTHP-RD-PROJECTION-SAME", MASK64 if same else 0)):
        h.variable(name, value)
    return producer, bank, damage, items, refs, text_a, text


@pytest.mark.parametrize("spans", (((2, 10),), ((0, 2), (8, 4)), ((0, 8),), ()))
@pytest.mark.parametrize("same", (False, True))
def test_acknowledged_claim_gaps_reuse_only_identical_coverage(harness, spans, same):
    h = harness
    _producer, _bank, damage, *_ = _residual_row(h, spans, same=same)
    assert h.call("_RTHP-RD-SCAN-ACTIVE-ROW?")
    assert h.runtime.memory.read_bytes(damage, 1) == bytes((0 if same else 255,))
    assert h.value("_RTHP-RD-ROW-FIRST") == 0
    assert h.value("_RTHP-RD-ROW-LIMIT") == len(spans)
    assert h.runtime.memory.read_bytes(damage - 8, 8) == b"LEFTGUAR"
    assert h.runtime.memory.read_bytes(damage + 1, 8) == b"RIGHTGUA"


@pytest.mark.parametrize("dirty", (1, 255))
def test_identical_coverage_keeps_cell_residue_and_menu_damage(harness, dirty):
    h = harness
    _producer, _bank, damage, *_ = _residual_row(h, ((0, 2), (8, 4)), dirty=dirty)
    assert h.call("_RTHP-RD-SCAN-ACTIVE-ROW?")
    assert h.runtime.memory.read_bytes(damage, 1) == bytes((dirty,))


@pytest.mark.parametrize("field,value", (("ROW", MASK64), ("COL", MASK64),
                                        ("HEIGHT", 2), ("WIDTH", 0), ("WIDTH", 13)))
def test_identical_coverage_still_rejects_invalid_ack_geometry(harness, field, value):
    h = harness
    _producer, _bank, _damage, items, *_ = _residual_row(h, ((2, 5),))
    h.field(items, "_RTE-LPI." + field, value)
    assert not h.call("_RTHP-RD-SCAN-ACTIVE-ROW?")


def test_identical_coverage_rejects_overlapping_residual_runs(harness):
    h = harness
    _residual_row(h, ((0, 5), (4, 3)))
    assert not h.call("_RTHP-RD-SCAN-ACTIVE-ROW?")


def test_clean_gapped_row_copies_exact_payload_and_rebases_references(harness):
    h = harness
    producer, bank, damage, items, refs, text_a, text = _residual_row(h, ((0, 2), (8, 4)))
    item_size = h.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
    outputs = []
    for name, size in (("ITEMS", 2 * item_size), ("REFS", 32), ("TEXT", len(text))):
        pointer = h.allocate(b"LEFTGUAR" + bytes(size) + b"RIGHTGUA") + 8
        h.field(producer, "_RTHP.GLYPH-" + name + "-A", pointer)
        h.field(producer, "_RTHP.GLYPH-" + name + "-U", size)
        outputs.append((pointer, size))
    for name, value in (("_RTHP-W-GLYPH-FIRST", 10), ("_RTHP-RD-ITEM-CAP", 2),
                        ("_RTHP-RD-REF-CAP", 2), ("_RTHP-RD-OUT-COUNT", 0),
                        ("_RTHP-RD-OUT-TEXT", 0)):
        h.variable(name, value)
    before = h.runtime.memory.read_bytes(items, 2 * item_size)
    assert h.call("_RTHP-RD-SCAN-ACTIVE-ROW?")
    assert h.runtime.memory.read_bytes(damage, 1) == b"\0"
    assert h.call("_RTHP-RD-COPY-ACTIVE-ROW?")
    expected = bytearray(before)
    for i in range(2):
        struct.pack_into("<Q", expected, i * item_size + h.offset("_RTE-LPI.OBJECT"), 10 + i)
    assert h.runtime.memory.read_bytes(outputs[0][0], 2 * item_size) == expected
    assert h.runtime.memory.read_bytes(outputs[1][0], 32) == struct.pack("<4Q", 0, 2, 2, 4)
    assert h.runtime.memory.read_bytes(outputs[2][0], len(text)) == text
    assert h.runtime.memory.read_bytes(items, 2 * item_size) == before
    assert h.runtime.memory.read_bytes(text_a, len(text)) == text
    for pointer, size in outputs:
        assert h.runtime.memory.read_bytes(pointer - 8, 8) == b"LEFTGUAR"
        assert h.runtime.memory.read_bytes(pointer + size, 8) == b"RIGHTGUA"
