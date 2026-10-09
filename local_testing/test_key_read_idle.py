"""Execute the production blocking key read over a structured key source.

KEY-READ, KEY-POLL and the key-source lease words are production Forth from
keys.f, run in both semantic engines.  The structured source's poll and
pending callbacks, IDLE-UNTIL and YIELD? are fixtures, so each test sees
exactly when a modal read sleeps between empty polls.
"""

import re

import pytest

from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions

MASK64 = (1 << 64) - 1
OWNER = 4242

FIXTURES = {
    "IDLE-UNTIL": ": IDLE-UNTIL ( deadline -- ) LAST-DEADLINE ! 1 SLEEPS +! ;",
    "YIELD?": ": YIELD? ( -- ) 1 YIELDS +! ;",
}

FIXTURE_STATE = """
VARIABLE SLEEPS  VARIABLE YIELDS  VARIABLE LAST-DEADLINE
VARIABLE POLLS   VARIABLE EMPTY-POLLS  VARIABLE SOURCE-PENDING
VARIABLE PENDING-ASKED
CREATE TEST-EV 24 ALLOT
"""

TEST_WORDS = b"""
: TEST-RAW ( owner -- byte has-byte ) DROP 0 FALSE ;
: TEST-EVENT ( ev owner -- has-event )
    DROP 1 POLLS +!
    POLLS @ EMPTY-POLLS @ U> IF 7 SWAP ! TRUE ELSE DROP FALSE THEN ;
: TEST-PENDING ( owner -- flag ) PENDING-ASKED ! SOURCE-PENDING @ ;
"""


class KeyReadHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        source = (ROOT / "akashic/tui/keys.f").read_text()
        source = source[: source.index("[DEFINED] GUARDED")]
        # keys.f decodes UTF-8 with the words text/utf8.f provides; as in
        # keys.f, its optional guard section only wraps them.
        utf8 = (ROOT / "akashic/text/utf8.f").read_text()
        utf8 = utf8[: utf8.index("[DEFINED] GUARDED")]
        self.definitions = _definitions(utf8 + source)
        # The decoders' buffers are declared with CREATE ... ALLOT.
        for match in re.finditer(r"(?m)^CREATE (\S+)([^\\\n]*)", utf8 + source):
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

        for name in ("KEY-READ", "KEY-SOURCE-ACQUIRE", "KEY-SOURCE-RELEASE",
                     "KEY-SOURCE-UART?"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.runtime.evaluate(TEST_WORDS, step_budget=100_000)

    def variable(self, name, value=None):
        word = self.runtime.find(name)
        assert word is not None, name
        if value is None:
            return self.runtime.memory.read64(word.body_address)
        self.runtime.memory.write64(word.body_address, value & MASK64)
        return None

    def stack(self, source):
        self.runtime.evaluate(source, step_budget=1_000_000)
        result = self.runtime.main_context.data.snapshot()
        while self.runtime.main_context.data.depth():
            self.runtime.main_context.data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def acquire(self, pending=True):
        pending_xt = b"' TEST-PENDING" if pending else b"0"
        lease, status = self.stack(
            f"{OWNER} ' TEST-RAW ' TEST-EVENT ".encode() + pending_xt
            + b" KEY-SOURCE-ACQUIRE"
        )
        assert status == 0
        return lease

    def read(self, empty_polls):
        self.variable("EMPTY-POLLS", empty_polls)
        assert self.stack(b"TEST-EV KEY-READ") == (MASK64,)
        assert self.variable("POLLS") == empty_polls + 1


@pytest.fixture(params=["python", "native"])
def keys(request):
    return KeyReadHarness(request.param)


def test_a_quiet_source_sleeps_until_input_between_empty_polls(keys):
    keys.acquire()
    keys.read(3)
    assert keys.variable("SLEEPS") == 3
    assert keys.variable("LAST-DEADLINE") == MASK64
    assert keys.variable("YIELDS") == 3
    assert keys.variable("PENDING-ASKED") == OWNER


def test_a_source_with_pending_work_keeps_polling(keys):
    keys.acquire()
    keys.variable("SOURCE-PENDING", MASK64)
    keys.read(3)
    assert keys.variable("SLEEPS") == 0
    assert keys.variable("YIELDS") == 3


def test_a_source_without_a_pending_callback_keeps_polling(keys):
    keys.acquire(pending=False)
    keys.read(2)
    assert keys.variable("SLEEPS") == 0
    assert keys.variable("YIELDS") == 2


def test_an_event_ready_at_once_never_sleeps(keys):
    keys.acquire()
    keys.read(0)
    assert keys.variable("SLEEPS") == 0
    assert keys.variable("YIELDS") == 0


def test_releasing_the_source_forgets_its_pending_callback(keys):
    lease = keys.acquire()
    assert keys.stack(f"{OWNER} {lease} KEY-SOURCE-RELEASE".encode()) == (0,)
    assert keys.stack(b"KEY-SOURCE-UART?") == (MASK64,)
    assert keys.variable("_KEY-SOURCE-PENDING-XT") == 0
