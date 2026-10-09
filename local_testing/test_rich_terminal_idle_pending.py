"""Execute the rich-terminal pending chain the app shell consults before idling.

_APTAS-PENDING, APTSCB-PENDING?, _RTAPTSCB-WORK-PENDING? and
RTAPT-WORK-PENDING? are production Forth, run in both semantic engines.  PT's
queries and each layer's structural validity check are fixtures, so every
test sets exactly the state one layer reads and observes the whole chain.
"""

import re

import pytest

from test_rich_terminal_control_map import (
    MEGAPAD_ROOT, MegaForthRuntime, ROOT, _definitions,
)

MASK64 = (1 << 64) - 1
SESSION = 0x7777
SOURCES = (
    MEGAPAD_ROOT / "rich-terminal.f",
    ROOT / "akashic/tui/screen.f",
    ROOT / "akashic/tui/app-shell.f",
    ROOT / "akashic/tui/screen-backend-apt1.f",
    ROOT / "akashic/tui/app-shell-apt1.f",
    ROOT / "akashic/tui/rich-terminal/apt1-engine.f",
    ROOT / "akashic/tui/rich-terminal/screen-adapter-apt1.f",
)
# Record layouts extend an embedded base descriptor by declared offsets.
LAYOUT_BASES = ("SCB-DESC-SIZE", "APTSCB-PUBLISHER-SIZE", "ASHELL-TERMINAL-DESC-SIZE")

FIXTURES = {
    "PT-SERVICE-PENDING?":
        ": PT-SERVICE-PENDING? ( session -- flag ) SESSION-ASKED ! SESSION-PENDING @ ;",
    "PT-LEGACY-PENDING?":
        ": PT-LEGACY-PENDING? ( session -- flag ) DROP LEGACY-PENDING @ ;",
    "PT-RETAINED-STATE@":
        ": PT-RETAINED-STATE@ ( session -- state ) DROP RETAINED-STATE @ ;",
    "APTAS-VALID?": ": APTAS-VALID? ( owner -- flag ) DROP OWNER-VALID @ ;",
    "APTSCB-VALID?": ": APTSCB-VALID? ( adapter -- flag ) DROP ADAPTER-VALID @ ;",
    "RTAPTSCB-VALID?":
        ": RTAPTSCB-VALID? ( publisher -- flag ) DROP PUBLISHER-VALID @ ;",
    "_RTAPT-ENGINE-STORAGE?":
        ": _RTAPT-ENGINE-STORAGE? ( e -- flag ) DROP ENGINE-VALID @ ;",
}

FIXTURE_STATE = """
VARIABLE SESSION-PENDING  VARIABLE SESSION-ASKED  VARIABLE LEGACY-PENDING
VARIABLE RETAINED-STATE   VARIABLE OWNER-VALID    VARIABLE ADAPTER-VALID
VARIABLE PUBLISHER-VALID  VARIABLE ENGINE-VALID
"""

ROOTS = (
    "_APTAS-PENDING", "APTSCB-PENDING?", "_RTAPTSCB-WORK-PENDING?",
    "RTAPT-WORK-PENDING?", "APTAS-SIZE", "APTSCB-SIZE", "RTAPTSCB-SIZE",
    "APTSCBP.CONTEXT", "APTSCBP.PENDING-XT", "PT-RET-ST-AVAILABLE",
    "_RTAPT-ACTIVE-NONE", "RTAPT-UPDATE-IDLE",
)


class Chain:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        source = "\n".join(path.read_text() for path in SOURCES)
        self.definitions = _definitions(source)
        for match in re.finditer(
            rf"(?m)^(?:{'|'.join(LAYOUT_BASES)})[^\n]* CONSTANT (\S+)", source,
        ):
            self.definitions[match[1]] = match[0]
        self.definitions.update(FIXTURES)
        chunks, seen = [FIXTURE_STATE], set()

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

        for name in ROOTS:
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.owner = self.allocate(self.value("APTAS-SIZE"))
        self.adapter = self.allocate(self.value("APTSCB-SIZE"))
        self.publisher = self.allocate(self.value("RTAPTSCB-SIZE"))
        self.engine = self.allocate(4096)
        self.runtime.evaluate(b"' _RTAPTSCB-WORK-PENDING?", step_budget=10_000)
        pending_xt = self.runtime.main_context.data.pop()
        self.store("_APTAS.SESSION", self.owner, SESSION)
        self.store("_APTAS.ADAPTER", self.owner, self.adapter)
        self.store("APTSCB.SESSION", self.adapter, SESSION)
        self.store("APTSCB.PUBLISHER", self.adapter, self.publisher)
        self.store("APTSCBP.CONTEXT", self.publisher, self.publisher)
        self.store("APTSCBP.PENDING-XT", self.publisher, pending_xt)
        self.store("RTAPTSCB.ENGINE", self.publisher, self.engine)
        self.store("_RTAPT-E.SESSION", self.engine, SESSION)
        for name in ("OWNER-VALID", "ADAPTER-VALID", "PUBLISHER-VALID", "ENGINE-VALID"):
            self.variable(name, MASK64)

    def allocate(self, size):
        self.serial += 1
        word = self.runtime.define_created(
            f"CHAIN-{self.serial}", initial_body=bytes(size + 7),
        )
        return (word.body_address + 7) & -8

    def results(self, name, *inputs):
        stack = self.runtime.main_context.data
        for value in inputs:
            stack.push(value & MASK64)
        self.runtime.execute(name, step_budget=1_000_000)
        result = stack.snapshot()
        while stack.depth():
            stack.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def value(self, name):
        (result,) = self.results(name)
        return result

    def store(self, accessor, base, value):
        (field,) = self.results(accessor, base)
        self.runtime.memory.write64(field, value & MASK64)

    def variable(self, name, value):
        word = self.runtime.find(name)
        assert word is not None, name
        self.runtime.memory.write64(word.body_address, value & MASK64)

    def flag(self, name, base):
        (result,) = self.results(name, base)
        assert result in (0, MASK64)
        return result == MASK64

    def pending(self):
        return self.flag("_APTAS-PENDING", self.owner)

    def queue_lifecycle_work(self):
        self.store("_RTAPT-E.QUEUE-HEAD", self.engine, 0x100)
        self.variable("RETAINED-STATE", self.value("PT-RET-ST-AVAILABLE"))


@pytest.fixture(params=["python", "native"])
def chain(request):
    return Chain(request.param)


def test_a_quiet_owner_session_publisher_and_engine_report_no_work(chain):
    assert not chain.pending()
    assert chain.runtime.memory.read64(
        chain.runtime.find("SESSION-ASKED").body_address
    ) == SESSION


@pytest.mark.parametrize("field,value", [
    ("_APTAS.TEXT-PHASE", 2), ("_APTAS.PTR-CHANGED", 1),
    ("_APTAS.PTR-WHEEL-Y", -1), ("_APTAS.PTR-DRAG", 1),
])
def test_the_rest_of_a_text_or_pointer_event_is_pending(chain, field, value):
    chain.store(field, chain.owner, value)
    assert chain.pending()


@pytest.mark.parametrize("variable", ["LEGACY-PENDING", "SESSION-PENDING"])
def test_retained_legacy_bytes_and_session_work_are_pending(chain, variable):
    chain.variable(variable, MASK64)
    assert chain.pending()


@pytest.mark.parametrize("variable", ["OWNER-VALID", "ADAPTER-VALID", "PUBLISHER-VALID"])
def test_a_malformed_layer_reports_work_so_service_surfaces_its_error(chain, variable):
    chain.variable(variable, 0)
    assert chain.pending()


@pytest.mark.parametrize("field", ["_RTAPTSCB.FAULT-STATUS", "_RTAPTSCB.MORE-WORK"])
def test_a_latched_fault_or_producer_more_work_is_pending(chain, field):
    chain.store(field, chain.publisher, 2 if "FAULT" in field else MASK64)
    assert chain.pending()


def test_an_adapter_without_a_publisher_reports_only_session_work(chain):
    chain.store("APTSCB.PUBLISHER", chain.adapter, 0)
    chain.store("_RTAPTSCB.MORE-WORK", chain.publisher, MASK64)
    assert not chain.pending()


def test_queued_engine_lifecycle_work_is_pending_once_retained_output_is_available(chain):
    chain.queue_lifecycle_work()
    assert chain.pending()
    assert chain.flag("RTAPT-WORK-PENDING?", chain.engine)
    chain.variable("RETAINED-STATE", 0)
    assert not chain.pending()


@pytest.mark.parametrize("field", ["_RTAPT-E.ACTIVE-KIND", "_RTAPT-E.UPDATE-STATE"])
def test_an_engine_awaiting_a_completion_or_holding_an_update_is_not_pending(chain, field):
    chain.queue_lifecycle_work()
    chain.store(field, chain.engine, 1)
    assert not chain.pending()


def test_an_engine_with_invalid_storage_is_not_pending(chain):
    chain.queue_lifecycle_work()
    chain.variable("ENGINE-VALID", 0)
    assert not chain.flag("RTAPT-WORK-PENDING?", chain.engine)
