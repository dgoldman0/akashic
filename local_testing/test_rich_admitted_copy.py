"""An admission keeps what it admitted and checks again only what changed.

The hybrid and family preflights keep a copy of the glyph runs they last
admitted, in a block the engine takes from the memory source it was given.
A run equal to its copy in every byte but its identity, text included, under
the same plan header, is not checked again; its identity, text reference and
totals still are. These tests run the production preflights with and without
a memory source and require the same answer and the same admission record
every time, and fewer steps once the copy is in use.
"""
import struct

import pytest

from test_rich_terminal_family_batch import Families, offset, MASK

INVALID = 5
ARENA = 1 << 16
SOURCE = f"""
CREATE AM-ARENA-MEM {ARENA + 8} ALLOT
AM-ARENA-MEM 7 + -8 AND CONSTANT AM-ARENA
VARIABLE AM-NEXT VARIABLE AM-ALLOCS VARIABLE AM-FREES VARIABLE AM-REFUSE
CREATE AM-SOURCE-MEM 56 ALLOT
AM-SOURCE-MEM 7 + -8 AND CONSTANT AM-SOURCE
: AM-ALLOC ( bytes ctx -- addr|0 )
    DROP AM-REFUSE @ IF DROP 0 EXIT THEN
    7 + -8 AND AM-NEXT @ 2DUP + {ARENA} U> IF 2DROP 0 EXIT THEN
    DUP AM-ARENA + >R + AM-NEXT ! 1 AM-ALLOCS +! R> ;
: AM-FREE ( addr bytes ctx -- ) DROP 2DROP 1 AM-FREES +! ;
' AM-ALLOC ' AM-FREE 0 0 AM-SOURCE MSRC-INIT
"""

# Visible runs in row-major order: (row, col, width, text, fg).
RUNS = [(row, col, 12, f"r{row:02}c{col:02} text".encode(), 0x10203000 + row)
        for row in range(20) for col in (0, 20, 40)]


class Admitted(Families):
    def __init__(self, backend, memory=True):
        super().__init__(backend)
        self.runtime.evaluate(SOURCE.encode(), source_name="admitted-memory",
                              step_budget=2_000_000)
        if memory:
            assert self.run("RTE-ADMITTED-MEMORY!", self.word("AM-SOURCE"))[0] == (0,)

    def word(self, name):
        stack = self.runtime.main_context.data
        self.runtime.execute(name, step_budget=10_000)
        value = stack.pop()
        assert stack.snapshot() == ()
        return value

    def run(self, word, *inputs):
        stack = self.runtime.main_context.data
        for value in inputs:
            stack.push(value & MASK)
        steps = self.runtime.execute(word, step_budget=50_000_000).semantic_steps
        values = stack.snapshot()
        stack.clear()
        assert self.runtime.main_context.returns.snapshot() == ()
        return values, steps

    def store(self, name):
        address = self.word(name)
        return struct.unpack("<4Q", self.read(address, 32))

    def runs(self, rows=24, runs=RUNS, edit=None):
        """A glyph plan of RUNS in a region ROWS high: (plan, items, refs,
        text, count). EDIT may change a run's item bytes or text."""
        items, refs, text = bytearray(), bytearray(), bytearray()
        for index, (row, col, width, payload, fg) in enumerate(runs):
            item = bytearray(120)
            for name, value in (("OBJECT", 100 + index), ("ROW", row), ("COL", col),
                                ("HEIGHT", 1), ("WIDTH", width),
                                ("ROOT-HEIGHT", rows), ("ROOT-WIDTH", 80),
                                ("VISIBLE", -1), ("FG-RGBA", fg),
                                ("TEXT-CAPACITY", len(payload))):
                struct.pack_into("<Q", item, offset("_RTE-LPI." + name), value & MASK)
            if edit:
                item, payload = edit(index, item, payload)
            refs += struct.pack("<2Q", len(text), len(payload))
            text += payload
            items += item
        region = self.region(1, h=rows)
        item_a = self.allocate(bytes(items))
        plan = self.plan(item_a, len(items), region)
        return plan, item_a, self.allocate(bytes(refs)), self.allocate(bytes(text)), len(runs), region

    def family(self, **kwargs):
        plan, items, refs, text, count, region = self.runs(**kwargs)
        entry = self.allocate(struct.pack("<8Q", 2, plan, 144, text,
                                          self._text_bytes(refs, count), refs,
                                          16 * count, 0))
        batch, out, *_ = self.finish([region], [entry])
        return batch, out

    def _text_bytes(self, refs, count):
        offset_, length = struct.unpack("<2Q", self.read(refs + 16 * (count - 1), 16))
        return offset_ + length

    def admit(self, batch, out):
        (status,), steps = self.run("RTE-FAMILY-BATCH-PREFLIGHT", batch, out, self.shell)
        return status, self.read(out, 560), steps

    def hybrid(self, **kwargs):
        plan, items, refs, text, count, _ = self.runs(**kwargs)
        hybrid = self.allocate(struct.pack("<21Q", 1, 2, 3, 0, plan, refs, 16 * count,
                                           text, self._text_bytes(refs, count),
                                           *([0] * 12)))
        return hybrid, self.allocate(bytes(472))

    def admit_hybrid(self, hybrid, out):
        (status,), steps = self.run("RTE-HYBRID-PREFLIGHT", hybrid, out, self.facade)
        return status, self.read(out, 472), steps


@pytest.fixture(params=("python", "native"))
def backend(request):
    return request.param


def _warm(harness, build, admit):
    """Admit a fresh copy of the same plan three times: the first records
    what it needs, the second grows the block and keeps the copy, the third
    uses it."""
    return [admit(*build()) for _ in range(3)]


@pytest.mark.parametrize("boundary", ("family", "hybrid"))
def test_unchanged_runs_are_admitted_from_the_copy_with_the_same_record(backend, boundary):
    harness = Admitted(backend)
    plain = Admitted(backend, memory=False)
    build = getattr(harness, boundary)
    admit = getattr(harness, "admit" if boundary == "family" else "admit_hybrid")
    first, second, third = _warm(harness, build, admit)
    expected = (plain.admit if boundary == "family" else plain.admit_hybrid)(
        *getattr(plain, boundary)())
    assert expected[0] == 0
    for status, record, _ in (first, second, third):
        assert (status, record) == expected[:2]
    # The copy is in use from the third admission on.
    assert third[2] < second[2] * 0.6, (first[2], second[2], third[2])
    store = harness.store("_RTE-AM-FAMILY" if boundary == "family" else "_RTE-AM-HYBRID")
    assert store[0] and store[2] and store[2] <= store[1]


@pytest.mark.parametrize("boundary", ("family", "hybrid"))
@pytest.mark.parametrize("change", ("attrs", "utf8", "parent", "geometry"))
def test_a_run_that_differs_from_its_copy_is_checked_in_full(backend, boundary, change):
    harness = Admitted(backend)
    build = getattr(harness, boundary)
    admit = getattr(harness, "admit" if boundary == "family" else "admit_hybrid")
    _warm(harness, build, admit)

    def edit(index, item, payload):
        if index != 31:
            return item, payload
        if change == "attrs":
            struct.pack_into("<Q", item, offset("_RTE-LPI.ATTRS"), 0x100)
        elif change == "parent":
            struct.pack_into("<Q", item, offset("_RTE-LPI.PARENT"), 7)
        elif change == "geometry":
            struct.pack_into("<Q", item, offset("_RTE-LPI.WIDTH"), 0)
        else:
            payload = payload[:3] + b"\xff" + payload[4:]
        return item, payload

    status, _, _ = admit(*build(edit=edit))
    assert status == INVALID


@pytest.mark.parametrize("boundary", ("family", "hybrid"))
def test_a_changed_valid_run_gets_the_record_a_full_check_gives(backend, boundary):
    harness = Admitted(backend)
    plain = Admitted(backend, memory=False)
    build = getattr(harness, boundary)
    admit = getattr(harness, "admit" if boundary == "family" else "admit_hybrid")
    _warm(harness, build, admit)
    longer = [(row, col, width, payload + b"!" if (row, col) == (7, 20) else payload, fg)
              for row, col, width, payload, fg in RUNS]
    got = admit(*build(runs=longer))
    expected = (plain.admit if boundary == "family" else plain.admit_hybrid)(
        *getattr(plain, boundary)(runs=longer))
    assert got[:2] == expected[:2] and got[0] == 0


def test_a_changed_region_checks_every_run_again(backend):
    harness = Admitted(backend)
    _warm(harness, harness.family, harness.admit)
    # The region shrinks but the runs still claim the old root height.
    def stale(index, item, payload):
        struct.pack_into("<Q", item, offset("_RTE-LPI.ROOT-HEIGHT"), 24)
        return item, payload
    status, _, _ = harness.admit(*harness.family(rows=22, runs=RUNS[:60], edit=stale))
    assert status == INVALID


@pytest.mark.parametrize("target", ("items", "text"))
def test_a_batch_in_the_engines_block_is_refused(backend, target):
    harness = Admitted(backend)
    _warm(harness, harness.family, harness.admit)
    block, size, used, _ = harness.store("_RTE-AM-FAMILY")
    assert block and used
    batch, out = harness.family()
    entry = struct.unpack("<Q", harness.read(batch + offset("_RTE-FB.FAMILIES-A"), 8))[0]
    plan = struct.unpack("<Q", harness.read(entry + 8, 8))[0]
    if target == "items":
        # The copy's own items equal the plan's, but are not the caller's.
        harness.cell(plan + 120, block + 152)
    else:
        harness.cell(entry + 24, block + 152 + 120 * len(RUNS))
    status, _, _ = harness.admit(batch, out)
    assert status == INVALID


def test_without_memory_nothing_is_kept(backend):
    harness = Admitted(backend, memory=False)
    results = _warm(harness, harness.family, harness.admit)
    assert {status for status, _, _ in results} == {0}
    assert harness.store("_RTE-AM-FAMILY") == (0, 0, 0, 0)
    steps = [steps for *_, steps in results]
    assert max(steps) - min(steps) < min(steps) * 0.05


def test_a_refused_block_keeps_no_copy_and_checks_everything(backend):
    harness = Admitted(backend)
    harness.cell(harness.runtime.find("AM-REFUSE").body_address, 1)
    results = _warm(harness, harness.family, harness.admit)
    assert {status for status, _, _ in results} == {0}
    block, size, used, need = harness.store("_RTE-AM-FAMILY")
    assert (block, size, used) == (0, 0, 0) and need


def test_fini_gives_every_block_back(backend):
    harness = Admitted(backend)
    _warm(harness, harness.family, harness.admit)
    _warm(harness, harness.hybrid, harness.admit_hybrid)
    allocs = harness.variable("AM-ALLOCS")
    assert allocs == 2
    harness.run("RTE-ADMITTED-FINI")
    assert harness.variable("AM-FREES") == allocs
    assert harness.store("_RTE-AM-FAMILY") == (0, 0, 0, 0)
    assert harness.store("_RTE-AM-HYBRID") == (0, 0, 0, 0)
    # A batch admitted afterwards is checked in full and keeps nothing.
    assert harness.admit(*harness.family())[0] == 0
    assert harness.store("_RTE-AM-FAMILY") == (0, 0, 0, 0)
