"""Execute the production TUI event loop and its idle decision.

TUI-EVT-LOOP, its pass, posted-action drain, tick and resize checks, and
the idle predicates are production Forth from event.f, run in both semantic
engines.  The clock, IDLE-UNTIL, key polling, widget drawing, screen
flushing, the key-source owner and YIELD? are fixtures.
"""

import re

import pytest

from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions

MASK64 = (1 << 64) - 1

FIXTURES = {
    "MS@": ": MS@ ( -- ms ) FAKE-MS @ ;",
    "IDLE-UNTIL": """: IDLE-UNTIL ( deadline -- )
        1 SLEEPS +!  SLEEPS @ 1- CELLS DEADLINES + OVER SWAP !
        DUP -1 = IF DROP EXIT THEN
        DUP FAKE-MS @ U> IF FAKE-MS ! ELSE DROP THEN ;""",
    "YIELD?": """: YIELD? ( -- )
        1 YIELDS +!  YIELDS @ PASS-LIMIT @ U< 0= IF TUI-EVT-QUIT THEN ;""",
    "KEY-POLL": """: KEY-POLL ( ev -- flag )
        DROP INPUT-AT @ 0= IF FALSE EXIT THEN
        INPUT-AT @ FAKE-MS @ U> IF FALSE EXIT THEN
        0 INPUT-AT !  1 INPUTS +!  TRUE ;""",
    "FOC-DISPATCH": ": FOC-DISPATCH ( ev -- ) DROP 1 SCREEN-DIRTY ! ;",
    # A requested redraw repaints every widget into the back buffer.
    "_TUI-EVT-DRAW-DIRTY": """: _TUI-EVT-DRAW-DIRTY ( -- )
        _TUI-EVT-REDRAW-FLAG @ IF 0 _TUI-EVT-REDRAW-FLAG ! 1 SCREEN-DIRTY ! THEN ;""",
    "SCR-DIRTY?": ": SCR-DIRTY? ( -- flag ) SCREEN-DIRTY @ 0<> ;",
    "SCR-FLUSH": """: SCR-FLUSH ( -- )
        SCREEN-DIRTY @ IF 1 FLUSHES +!  FLUSH-REFUSED @ 0= IF 0 SCREEN-DIRTY ! THEN THEN ;""",
    "TERM-RESIZED?": ": TERM-RESIZED? ( -- flag ) FALSE ;",
    "TERM-SIZE": ": TERM-SIZE ( -- w h ) 80 24 ;",
    "KEY-SOURCE-UART?": ": KEY-SOURCE-UART? ( -- flag ) STRUCTURED-SOURCE @ 0= ;",
    "_TUI-EVT-KEY-BUF": "CREATE _TUI-EVT-KEY-BUF 24 ALLOT",
    "_TUI-EVT-POST-Q": "CREATE _TUI-EVT-POST-Q _TUI-EVT-POST-MAX CELLS ALLOT",
}

FIXTURE_STATE = """
VARIABLE FAKE-MS   VARIABLE SLEEPS   VARIABLE YIELDS   VARIABLE PASS-LIMIT
VARIABLE INPUT-AT  VARIABLE INPUTS   VARIABLE SCREEN-DIRTY
VARIABLE FLUSHES   VARIABLE FLUSH-REFUSED   VARIABLE STRUCTURED-SOURCE
VARIABLE TICKS
CREATE DEADLINES 64 CELLS ALLOT
"""

TEST_WORDS = b"""
: TEST-TICK ( -- ) 1 TICKS +! ;
: TEST-RESIZE ( w h -- ) 2DROP ;
"""


class EventLoopHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        source = (ROOT / "akashic/tui/event.f").read_text()
        source = source[: source.index("§9 — Guard")]
        # Key event constants come from keys.f; the fixtures below replace
        # every keys.f word the loop calls.
        keys = (ROOT / "akashic/tui/keys.f").read_text()
        self.definitions = _definitions(keys[: keys.index("[DEFINED] GUARDED")] + source)
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

        for name in ("TUI-EVT-LOOP", "TUI-EVT-ON-TICK", "TUI-EVT-ON-RESIZE",
                     "TUI-EVT-TICK-MS!", "TUI-EVT-POST", "TUI-EVT-REDRAW",
                     "_TUI-EVT-NEXT-DEADLINE"):
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

    def run(self, *, now=1000, passes=6, tick=True, resize=False, tick_ms=100):
        self.variable("FAKE-MS", now)
        self.variable("PASS-LIMIT", passes)
        self.variable("_TUI-EVT-TICK-MS", tick_ms)
        self.runtime.evaluate(
            (b"' TEST-TICK" if tick else b"0") + b" TUI-EVT-ON-TICK "
            + (b"' TEST-RESIZE" if resize else b"0") + b" TUI-EVT-ON-RESIZE",
            step_budget=100_000,
        )
        self.runtime.execute("TUI-EVT-LOOP", step_budget=3_000_000)
        assert self.runtime.main_context.data.snapshot() == ()
        assert self.runtime.main_context.returns.snapshot() == ()

    def deadlines(self):
        base = self.runtime.find("DEADLINES").body_address
        return [
            self.runtime.memory.read64(base + 8 * index)
            for index in range(self.variable("SLEEPS"))
        ]


@pytest.fixture(params=["python", "native"])
def loop(request):
    return EventLoopHarness(request.param)


def test_quiet_passes_sleep_until_each_next_tick(loop):
    loop.run(passes=6)
    assert loop.deadlines() == [1100, 1200, 1300]
    assert loop.variable("TICKS") == 3


def test_without_a_tick_or_resize_callback_the_loop_sleeps_until_input(loop):
    loop.run(tick=False, passes=2)
    assert loop.deadlines() == [MASK64, MASK64]


def test_a_resize_callback_bounds_the_sleep_to_one_tick_interval(loop):
    loop.run(tick=False, resize=True, now=4000, tick_ms=100, passes=1)
    assert loop.deadlines() == [4100]


def test_input_and_its_flush_keep_the_pass_awake(loop):
    loop.variable("INPUT-AT", 1000)
    loop.run(passes=2)
    assert loop.variable("INPUTS") == 1
    assert loop.variable("FLUSHES") == 1
    # Only the quiet second pass sleeps.
    assert loop.variable("SLEEPS") == 1


def test_a_refused_flush_keeps_the_loop_awake(loop):
    loop.variable("SCREEN-DIRTY", 1)
    loop.variable("FLUSH-REFUSED", 1)
    loop.run(passes=4)
    assert loop.variable("SLEEPS") == 0


def test_a_requested_redraw_is_drawn_and_flushed_before_the_loop_sleeps(loop):
    loop.runtime.evaluate(b"TUI-EVT-REDRAW", step_budget=10_000)
    loop.run(passes=2)
    assert loop.variable("FLUSHES") == 1
    assert loop.variable("SLEEPS") == 1


def test_a_structured_key_source_keeps_the_loop_awake(loop):
    loop.variable("STRUCTURED-SOURCE", 1)
    loop.run(passes=4)
    assert loop.variable("SLEEPS") == 0


def test_loop_sleeps_only_while_running_and_before_the_yield():
    source = (ROOT / "akashic/tui/event.f").read_text()
    body = re.search(r"(?ms)^: TUI-EVT-LOOP\b.*?^\s*REPEAT ;", source)[0]
    code = re.sub(r"\\[^\n]*|\([^)]*\)", "", body)
    assert code.index("_TUI-EVT-PASS") < code.index("_TUI-EVT-RUNNING @ IF")
    assert code.index("_TUI-EVT-RUNNING @ IF") < code.index("IDLE-UNTIL")
    assert code.index("IDLE-UNTIL") < code.index("YIELD?")
