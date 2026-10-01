"""The engine's working banks start small and grow from a memory source.

The complete PT module and Akashic engine run against the real terminal
driver; no Desktop starts.  The engine's operation, copy and control-ledger
banks come from a test memory source with an optional byte budget.  What an
admission needed is set directly in the provider's need cells; admission
itself records them, and that is exercised by the producer and Desk checks.
"""
from unittest.mock import patch

import pytest

import test_rich_terminal_cell_feed as cf
from simulator.runtime import MegaForthRuntime
from tests.simulator.test_kdos_exceptions import _load_exceptions


# A bump allocator over one arena: blocks are never reused, and every
# release is counted, so the test sees exactly what the engine gives back.
MEMORY_FIXTURE = b"""
CREATE TM-ARENA-MEM 65543 ALLOT
: TM-ARENA TM-ARENA-MEM 7 + -8 AND ;
VARIABLE TM-NEXT VARIABLE TM-FREES VARIABLE TM-FREED
: TM-ALLOC ( bytes ctx -- addr|0 )
    DROP 7 + -8 AND
    TM-NEXT @ OVER + TM-ARENA 65536 + U> IF DROP 0 EXIT THEN
    TM-NEXT @ SWAP TM-NEXT +! ;
: TM-FREE ( addr bytes ctx -- ) DROP 1 TM-FREES +! TM-FREED +! DROP ;
CREATE TM-SRC-MEM MSRC-SIZE 7 + ALLOT
: TM-SRC TM-SRC-MEM 7 + -8 AND ;
VARIABLE TM-OPS VARIABLE TM-COPY VARIABLE TM-LEDGER
: TM-SETUP
    TM-ARENA TM-NEXT ! 0 TM-FREES ! 0 TM-FREED !
    ['] TM-ALLOC ['] TM-FREE 0 0 TM-SRC MSRC-INIT
    RTAPT-OP-SIZE TM-SRC MSRC-ALLOC TM-OPS !
    8 TM-SRC MSRC-ALLOC TM-COPY !
    RTAPT-CONTROL-LEDGER-SIZE TM-SRC MSRC-ALLOC TM-LEDGER ! ;
"""


class GrowthHarness(cf._FeedHarness):
    def __init__(self, backend):
        fixture = cf._fixture_source(20).replace(
            b"  CF-SESSION CF-OWNERS RTAPT-OWNER-SIZE CF-OPS RTAPT-OP-SIZE\n"
            b"  CF-COPY 8 CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE\n",
            b"  TM-SETUP CF-SESSION CF-OWNERS RTAPT-OWNER-SIZE TM-OPS @ RTAPT-OP-SIZE\n"
            b"  TM-COPY @ 8 TM-LEDGER @ RTAPT-CONTROL-LEDGER-SIZE\n",
        ).replace(
            b"  CF-CONFIG CF-ENGINE RTAPT-INIT THROW ;",
            b"  CF-CONFIG CF-ENGINE RTAPT-INIT THROW\n  TM-SRC CF-ENGINE RTAPT-MEMORY! THROW ;",
        )
        assert b"TM-SETUP" in fixture and b"RTAPT-MEMORY!" in fixture
        with patch.object(cf, "_fixture_source", return_value=MEMORY_FIXTURE + fixture), \
                patch.object(cf, "_load_exceptions", side_effect=lambda: _load_exceptions(
                    MegaForthRuntime(execution_backend=backend))):
            super().__init__(cf.SOURCE.read_bytes(), cols=20)

    def constant(self, name):
        return self.call(name)[0][0]

    def field(self, name):
        return self.runtime.memory.read64(self.call(name, self.engine)[0][0])

    def need(self, ops=0, copy=0, controls=0, engine=None):
        for name, value in (("_RTAPT-NEED-OPS", ops), ("_RTAPT-NEED-COPY", copy),
                            ("_RTAPT-NEED-CONTROLS", controls),
                            ("_RTAPT-NEED-E", self.engine if engine is None else engine)):
            self.runtime.memory.write64(self.runtime.find(name).body_address, value)

    def budget(self, bytes_):
        source = self.constant("TM-SRC")
        self.runtime.memory.write64(self.call("MSRC.BUDGET", source)[0][0], bytes_)

    def grow(self):
        return self.call("RTAPT-STORAGE-GROW", self.engine)[0]

    def banks(self):
        return tuple(self.field(name) for name in (
            "_RTAPT-E.OPS-A", "_RTAPT-E.OPS-U", "_RTAPT-E.OP-CAP",
            "_RTAPT-E.COPY-A", "_RTAPT-E.COPY-U",
            "_RTAPT-E.CONTROL-LEDGER-A", "_RTAPT-E.CONTROL-LEDGER-U",
            "_RTAPT-E.CONTROL-LEDGER-CAP",
        ))

    def held(self):
        return self.call("MSRC-HELD@", self.constant("TM-SRC"))[0][0]


@pytest.fixture(params=("python", "native"))
def harness(request):
    return GrowthHarness(request.param)


def test_the_banks_grow_to_what_the_admission_needed_and_old_ones_go_back(harness):
    ok = harness.constant("RTAPT-S-OK")
    assert harness.held() == 40 + 8 + 64
    harness.need(ops=10, copy=300, controls=3)
    assert harness.grow() == (0, 0, ok)
    ops_a, ops_u, op_cap, copy_a, copy_u, ledger_a, ledger_u, ledger_cap = harness.banks()
    # What was needed and half again.
    assert (op_cap, ops_u) == (15, 15 * 40)
    assert copy_u == 456
    assert (ledger_cap, ledger_u) == (4, 4 * 64)
    assert harness.held() == 600 + 456 + 256
    assert harness.cell("TM-FREES") == 3
    assert harness.cell("TM-FREED") == 40 + 8 + 64
    true = harness.constant("TRUE")
    assert harness.call("RTAPT-VALID?", harness.engine)[0] == (true,)

    # Asking again for what is already held grows nothing.
    assert harness.grow() == (0, 0, harness.constant("RTAPT-S-UNSUPPORTED"))
    assert harness.cell("TM-FREES") == 3


def test_only_the_engine_whose_admission_counted_the_needs_grows(harness):
    harness.need(ops=10, engine=harness.engine + 8)
    assert harness.grow() == (0, 0, harness.constant("RTAPT-S-UNSUPPORTED"))
    assert harness.banks()[2] == 1


def test_a_refusal_keeps_the_banks_and_reports_the_bytes(harness):
    harness.budget(harness.held() + 100)
    before = harness.banks()
    harness.need(ops=10)
    assert harness.grow() == (600, 112, harness.constant("RTAPT-S-CAPACITY"))
    assert harness.banks() == before
    assert harness.held() == 112
    assert harness.cell("TM-FREES") == 0


def test_a_partly_refused_growth_gives_back_what_it_took(harness):
    # Room for the operations but not the copy bytes as well.
    harness.budget(harness.held() + 600 + 100)
    before = harness.banks()
    harness.need(ops=10, copy=300)
    assert harness.grow() == (456, 112, harness.constant("RTAPT-S-CAPACITY"))
    assert harness.banks() == before
    assert harness.held() == 112
    assert (harness.cell("TM-FREES"), harness.cell("TM-FREED")) == (1, 600)


def test_teardown_gives_back_the_banks_the_engine_owns(harness):
    harness.need(ops=10, copy=300, controls=3)
    harness.grow()
    frees = harness.cell("TM-FREES")
    assert harness.call("RTAPT-FINI", harness.engine)[0] == (0,)
    assert harness.cell("TM-FREES") == frees + 3
    assert harness.held() == 0
