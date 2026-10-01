"""The screen producer's arena grows from its caller's memory as draws need.

The complete producer module and its dependencies run; no terminal or
Desktop starts.  The draw's RUHA snapshot is a fixture record, and the
facade's storage proof is a fixture seam: their behaviour belongs to their
own units.  Capacities, storage bytes, layout and the memory source are the
real ones, over the system heap through a counting allocator.
"""
import pytest

import akashic_tui as packaging
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime


MASK64 = (1 << 64) - 1
STEP_BUDGET = 80_000_000

# Before the producer compiles: the facade's storage proof answers from a
# fixture cell, so no engine has to exist.
SEAMS = b"""
VARIABLE GT-DISJOINT  -1 GT-DISJOINT !
: RTE-STORAGE-DISJOINT?  ( a u facade -- flag ) DROP 2DROP GT-DISJOINT @ ;
"""

# The system heap behind a memory source that counts what it hands out and
# gets back.
FIXTURE = b"""
VARIABLE TM-ALLOCS VARIABLE TM-FREES VARIABLE TM-FREED
: TM-ALLOC  ( bytes ctx -- addr|0 )
    DROP ALLOCATE IF DROP 0 ELSE 1 TM-ALLOCS +! THEN ;
: TM-FREE  ( addr bytes ctx -- )  DROP 1 TM-FREES +! TM-FREED +! FREE ;
CREATE GT-SRC-MEM MSRC-SIZE 7 + ALLOT
: GT-SRC  GT-SRC-MEM 7 + -8 AND ;
CREATE GT-P-MEM RTHP-SIZE 7 + ALLOT
: GT-P  GT-P-MEM 7 + -8 AND ;
CREATE GT-SNAP-MEM RUHA-SNAPSHOT-SIZE 7 + ALLOT
: GT-SNAP  GT-SNAP-MEM 7 + -8 AND ;
CREATE GT-ADAPTER-MEM RUHA-SIZE 7 + ALLOT
4 CONSTANT GT-DOCUMENTS
: GT-FIRST-BYTES  ( -- bytes )
    GT-DOCUMENTS RTHP-FIRST-CAPACITIES RTHP-STORAGE-BYTES ;
\\ A producer with its first arena, taken over with its memory source, as
\\ Desk sets one up.
: GT-SETUP  ( -- )
    0 TM-ALLOCS ! 0 TM-FREES ! 0 TM-FREED !
    ['] TM-ALLOC ['] TM-FREE 0 0 GT-SRC MSRC-INIT
    GT-P RTHP-SIZE 0 FILL GT-SNAP RUHA-SNAPSHOT-SIZE 0 FILL
    GT-DOCUMENTS _RTHP-I-DOCUMENTS !
    RTHP-FIRST-CAPACITIES
        _RTHP-I-ROWS ! _RTHP-I-COLS ! _RTHP-I-FIELD-NATIVE !
        _RTHP-I-STATUS-NATIVE ! _RTHP-I-DGRAPH-NATIVE !
        _RTHP-I-COLLECTION-NATIVE ! _RTHP-I-TEXT ! _RTHP-I-RECORDS !
    GT-P _RTHP-I-CAPACITIES!
    GT-FIRST-BYTES DUP GT-SRC MSRC-ALLOC
        DUP GT-P _RTHP.ARENA-A ! SWAP 0 FILL
    GT-FIRST-BYTES GT-P _RTHP.ARENA-U !
    GT-P _RTHP-LAYOUT
    GT-SRC GT-P _RTHP.MEMORY !
    GT-ADAPTER-MEM 7 + -8 AND GT-P _RTHP.ADAPTER !
    _RTHP-MAGIC GT-P _RTHP.MAGIC ! GT-P GT-P _RTHP.SELF !
    1 GT-P _RTHP.COLS ! 1 GT-P _RTHP.ROWS !
    0 TM-ALLOCS ! ;
\\ One build's admission of the fixture snapshot.
: GT-GROW  ( -- rte-status )
    GT-P _RTHP-W-P ! GT-SNAP _RTHP-W-SNAP !
    0 _RTHP-W-MEMORY-ASKED ! 0 _RTHP-W-MEMORY-HELD !
    RTHP-WHY-OTHER _RTHP-W-WHY !
    _RTHP-GROW-ARENA ;
"""


class ProducerGrowthHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(
                external_size=packaging.DESKTOP_APT1_EXT_MEM_MIB << 20,
                hbw_size=1 << 20,
            ),
            execution_backend=backend,
        )
        self.runtime.evaluate((packaging.MEGAPAD_ROOT / "kdos.f").read_bytes(),
                              source_name="kdos.f")
        profile = packaging.PROFILES["desktop-apt1"]
        self.runtime.evaluate(packaging._with_userland_xmem_reserve(
            "ENTER-USERLAND\n", profile.general_xmem_reserve_bytes,
        ).encode(), source_name="growth-userland")
        modules = packaging.dependency_order(("tui/rich-terminal/hybrid-screen-producer.f",))
        marker = b"PROVIDED akashic-tui-rterm-hybrid-screen-producer"
        injected = 0
        for name, content in packaging._linked_chunks(
            modules, profile.link_chunk_bytes, profile.audited_link_line_bytes,
        ).items():
            injected += content.count(marker)
            self.runtime.evaluate(content.replace(marker, SEAMS + marker),
                                  source_name=name, step_budget=STEP_BUDGET)
        assert injected == 1
        self.runtime.evaluate(FIXTURE, source_name="growth-fixture", step_budget=STEP_BUDGET)
        self.call("GT-SETUP")
        self.producer = self.constant("GT-P")
        self.snapshot = self.constant("GT-SNAP")
        self.source = self.constant("GT-SRC")

    def call(self, word, *inputs):
        data = self.runtime.main_context.data
        assert data.snapshot() == ()
        for value in inputs:
            data.push(value & MASK64)
        self.runtime.execute(word, step_budget=STEP_BUDGET)
        result = data.snapshot()
        for _ in result:
            data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def constant(self, name):
        return self.call(name)[0]

    def cell(self, name):
        return self.runtime.memory.read64(self.runtime.find(name).body_address)

    def set_cell(self, name, value):
        self.runtime.memory.write64(self.runtime.find(name).body_address, value & MASK64)

    def field(self, name, record=None):
        return self.call(name, self.producer if record is None else record)[0]

    def get(self, name):
        return self.runtime.memory.read64(self.field("_RTHP." + name))

    def put(self, name, value):
        self.runtime.memory.write64(self.field("_RTHP." + name), value & MASK64)

    def snap(self, records=0, text=0, collections=0, collection_native=0,
             graphs=0, graph_native=0, statuses=0, status_native=0,
             fields=0, field_native=0):
        for name, value in (
            ("RECORDS-U", records * self.constant("UMSN-RECORD-SIZE")),
            ("TEXT-U", text),
            ("COLLECTION-DESCRIPTORS-U", collections * self.constant("UCSN-DESCRIPTOR-SIZE")),
            ("COLLECTION-NATIVE-U", collection_native),
            ("DGRAPH-DESCRIPTORS-U", graphs * self.constant("UDGSN-DESCRIPTOR-SIZE")),
            ("DGRAPH-NATIVE-U", graph_native),
            ("SFIELD-DESCRIPTORS-U", statuses * self.constant("USFSN-DESCRIPTOR-SIZE")),
            ("SFIELD-NATIVE-U", status_native),
            ("FIELD-DESCRIPTORS-U", fields * self.constant("UFLSN-DESCRIPTOR-SIZE")),
            ("FIELD-NATIVE-U", field_native),
        ):
            self.runtime.memory.write64(self.field("_RUHA-S." + name, self.snapshot), value)

    def grow(self):
        return self.constant("GT-GROW")

    def held(self):
        return self.call("MSRC-HELD@", self.source)[0]

    def capacities(self):
        return tuple(self.get("MAX-" + name) for name in (
            "RECORDS", "TEXT", "COLLECTION-NATIVE", "DGRAPH-NATIVE",
            "STATUS-NATIVE", "FIELD-NATIVE", "COLS", "ROWS"))

    def storage_bytes(self, capacities):
        return self.call("RTHP-STORAGE-BYTES", self.constant("GT-DOCUMENTS"), *capacities)[0]

    def bank_bytes(self):
        size, ok = self.call("_RTHP-TARGET-BANK-BYTES?", self.producer)
        assert ok == MASK64
        return size

    def laid_out(self):
        """Every bank lies inside the arena the record names."""
        arena, size = self.get("ARENA-A"), self.get("ARENA-U")
        banks = self.bank_bytes()
        for bank in ("TARGET0-A", "TARGET1-A"):
            assert arena <= self.get(bank) and self.get(bank) + banks <= arena + size
        return arena, size


@pytest.fixture(params=("python", "native"))
def harness(request):
    return ProducerGrowthHarness(request.param)


def test_a_draw_that_fits_takes_nothing(harness):
    first = harness.capacities()
    arena = harness.get("ARENA-A")
    harness.snap(records=1, text=8)
    assert harness.grow() == harness.constant("RTE-S-OK")
    assert harness.capacities() == first
    assert harness.get("ARENA-A") == arena
    assert harness.cell("TM-ALLOCS") == 0


def test_content_takes_half_again_of_room_and_the_surface_exactly(harness):
    first_bytes = harness.constant("GT-FIRST-BYTES")
    first_arena = harness.get("ARENA-A")
    harness.put("COLS", 12)
    harness.put("ROWS", 5)
    harness.put("SOURCE-DRAW", 7)
    harness.snap(records=10, text=100, graphs=2, graph_native=400)
    assert harness.grow() == harness.constant("RTE-S-OK")
    records, text, collection, graph, status, field, cols, rows = harness.capacities()
    assert (records, text) == (15, 150)
    # Never smaller than a header for each of its descriptors, and aligned.
    assert graph == (400 + 200) & -8
    assert (cols, rows) == (12, 5)
    # The first arena is untouched content that no frame shows: it goes back.
    arena, size = harness.laid_out()
    assert size == harness.storage_bytes(harness.capacities())
    assert arena != first_arena
    assert (harness.cell("TM-FREES"), harness.cell("TM-FREED")) == (1, first_bytes)
    assert harness.held() == size
    assert harness.get("KEPT-ARENA-A") == 0
    # No candidate built in the old arena may pass as current.
    assert harness.get("SOURCE-DRAW") == 0

    # A later draw that fits the room takes nothing more.
    harness.snap(records=14, text=140)
    assert harness.grow() == harness.constant("RTE-S-OK")
    assert harness.get("ARENA-A") == arena
    assert harness.cell("TM-ALLOCS") == 1


def test_native_banks_cover_a_header_for_each_descriptor(harness):
    harness.snap(records=1, collections=6, collection_native=8,
                 statuses=2, status_native=16, fields=1, field_native=0)
    assert harness.grow() == harness.constant("RTE-S-OK")
    _, _, collection, _, status, field, _, _ = harness.capacities()
    header = harness.constant("USCOL-ENTRY-HEADER-SIZE")
    assert collection == (6 * header * 3 // 2 + 7) & -8
    assert status == (2 * harness.constant("USF-HEADER-SIZE") * 3 // 2 + 7) & -8
    assert field == (harness.constant("UFLD-HEADER-SIZE") * 3 // 2 + 7) & -8
    harness.laid_out()


def test_the_frame_on_screen_keeps_its_bank_until_it_is_replaced(harness):
    first_arena = harness.get("ARENA-A")
    first_bytes = harness.get("ARENA-U")
    on_screen = harness.get("TARGET0-A")
    first_bank_bytes = harness.bank_bytes()
    harness.put("TARGET-ACTIVE", on_screen)
    harness.snap(records=10, text=100)
    assert harness.grow() == harness.constant("RTE-S-OK")
    assert (harness.get("KEPT-ARENA-A"), harness.get("KEPT-ARENA-U")) == (first_arena, first_bytes)
    assert (harness.get("KEPT-BANK-A"), harness.get("KEPT-BANK-U")) == (on_screen, first_bank_bytes)
    assert harness.cell("TM-FREES") == 0
    # Only input routing reads the kept bank; every other reader sees no
    # current bank, so the replacing frame is a complete START.
    assert harness.call("_RTHP-TARGET-BANK-HEADER?", on_screen, harness.producer) == (0,)

    # Growing again while that frame is still on screen: the arena nobody
    # reads goes back, the kept one stays.
    grown = harness.get("ARENA-A")
    grown_bytes = harness.get("ARENA-U")
    harness.snap(records=40, text=100)
    assert harness.grow() == harness.constant("RTE-S-OK")
    assert (harness.cell("TM-FREES"), harness.cell("TM-FREED")) == (1, grown_bytes)
    assert harness.get("KEPT-ARENA-A") == first_arena
    assert harness.get("ARENA-A") != grown

    # While it is still on screen, releasing changes nothing.
    harness.call("_RTHP-KEPT-ARENA-RELEASE", harness.producer)
    assert harness.get("KEPT-ARENA-A") == first_arena
    # Its replacement is shown: the kept arena goes back.
    harness.put("TARGET-ACTIVE", harness.get("TARGET0-A"))
    harness.call("_RTHP-KEPT-ARENA-RELEASE", harness.producer)
    assert tuple(harness.get(name) for name in (
        "KEPT-ARENA-A", "KEPT-ARENA-U", "KEPT-BANK-A", "KEPT-BANK-U")) == (0, 0, 0, 0)
    assert (harness.cell("TM-FREES"), harness.cell("TM-FREED")) == (2, grown_bytes + first_bytes)
    assert harness.held() == harness.get("ARENA-U")


def test_a_retired_frame_lets_the_kept_arena_go(harness):
    harness.put("TARGET-ACTIVE", harness.get("TARGET0-A"))
    harness.snap(records=10, text=100)
    assert harness.grow() == harness.constant("RTE-S-OK")
    assert harness.get("KEPT-ARENA-A") != 0
    harness.call("_RTHP-TARGET-RETIRE", harness.producer)
    assert harness.get("KEPT-ARENA-A") == 0
    assert harness.held() == harness.get("ARENA-U")


def test_a_refusal_keeps_the_arena_and_records_the_first_bytes(harness):
    arena = harness.get("ARENA-A")
    held = harness.held()
    harness.runtime.memory.write64(harness.call("MSRC.BUDGET", harness.source)[0], held + 100)
    harness.snap(records=10, text=100)
    capacity = harness.constant("RTE-S-CAPACITY")
    assert harness.grow() == capacity
    asked = harness.storage_bytes((15, 150) + harness.capacities()[2:])
    assert (harness.cell("_RTHP-W-MEMORY-ASKED"), harness.cell("_RTHP-W-MEMORY-HELD")) == (
        asked, held)
    assert harness.cell("_RTHP-W-WHY") == harness.constant("RTHP-WHY-MEMORY")
    assert harness.get("ARENA-A") == arena
    assert harness.capacities()[:2] == (1, 8)
    assert harness.cell("TM-ALLOCS") == 0

    # A smaller retry of the same draw keeps the first refusal's bytes.
    harness.snap(records=5, text=100)
    harness.set_cell("_RTHP-W-WHY", harness.constant("RTHP-WHY-OTHER"))
    assert harness.call("_RTHP-GROW-ARENA") == (capacity,)
    assert harness.cell("_RTHP-W-MEMORY-ASKED") == asked


def test_a_fixed_arena_or_a_pending_bank_never_grows(harness):
    harness.snap(records=10, text=100)
    harness.put("TARGET-PENDING", harness.get("TARGET1-A"))
    assert harness.grow() == harness.constant("RTE-S-INVALID")
    harness.put("TARGET-PENDING", 0)
    harness.put("MEMORY", 0)
    assert harness.grow() == harness.constant("RTE-S-OK")
    assert harness.capacities()[:2] == (1, 8)
    assert harness.cell("TM-ALLOCS") == 0


def test_a_block_that_is_not_separate_is_given_back(harness):
    harness.set_cell("GT-DISJOINT", 0)
    harness.snap(records=10, text=100)
    assert harness.grow() == harness.constant("RTE-S-INVALID")
    assert (harness.cell("TM-ALLOCS"), harness.cell("TM-FREES")) == (1, 1)
    assert harness.capacities()[:2] == (1, 8)


def test_teardown_gives_back_every_arena(harness):
    harness.put("TARGET-ACTIVE", harness.get("TARGET0-A"))
    harness.snap(records=10, text=100)
    assert harness.grow() == harness.constant("RTE-S-OK")
    assert harness.get("KEPT-ARENA-A") != 0
    harness.call("RTHP-FINI", harness.producer)
    assert harness.held() == 0
    assert harness.cell("TM-FREES") == 2
    assert harness.get("MAGIC") == 0
    # A cleared record has nothing left to give back.
    harness.call("RTHP-FINI", harness.producer)
    assert harness.cell("TM-FREES") == 2


@pytest.mark.parametrize("address,size,inside", [
    (100, 10, True), (100, 0, True), (99, 10, False), (191, 10, False),
    (190, 10, True), (MASK64 - 4, 10, False),
])
def test_a_span_lies_inside_a_base_and_total(harness, address, size, inside):
    assert harness.call("_RTHP-SPAN-IN?", address, size, 100, 100) == (
        (MASK64 if inside else 0),)
