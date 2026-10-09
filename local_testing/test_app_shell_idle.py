"""Execute the production app-shell loop words and their idle decision.

The loop, pass, posted-action drain, tick check, idle predicates and
deadline words are production Forth from app-shell.f, run in both semantic
engines.  The clock, IDLE-UNTIL, input, paint, terminal service, resize
poll and YIELD? are fixtures, so each test can script exactly what a pass
sees and observe every sleep the loop requests.
"""

import re

import pytest

from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions

MASK64 = (1 << 64) - 1

# Each fixture replaces one production word or external dependency.
FIXTURES = {
    "MS@": ": MS@ ( -- ms ) FAKE-MS @ ;",
    # IDLE-UNTIL records every deadline and jumps the fake clock to it.  A
    # deadline of -1 waits for input, which the fixture delivers at once.
    "IDLE-UNTIL": """: IDLE-UNTIL ( deadline -- )
        1 SLEEPS +!  SLEEPS @ 1- CELLS DEADLINES + OVER SWAP !
        DUP -1 = IF DROP INPUT-ON-WAKE @ INPUT-AT ! EXIT THEN
        DUP FAKE-MS @ U> IF FAKE-MS ! ELSE DROP THEN ;""",
    # YIELD? counts passes and ends the loop after the scripted number.
    "YIELD?": """: YIELD? ( -- )
        1 YIELDS +!  YIELDS @ PASS-LIMIT @ U< 0= IF ASHELL-QUIT THEN ;""",
    "_ASHELL-TERM-SERVICE": ": _ASHELL-TERM-SERVICE ( -- ) ;",
    "_ASHELL-POLL-INPUT": """: _ASHELL-POLL-INPUT ( -- has-event )
        INPUT-AT @ 0= IF FALSE EXIT THEN
        INPUT-AT @ FAKE-MS @ U> IF FALSE EXIT THEN
        0 INPUT-AT !  1 INPUTS +!  TRUE ;""",
    "_ASHELL-DISPATCH-EVENT": ": _ASHELL-DISPATCH-EVENT ( -- ) ASHELL-DIRTY! ;",
    "_ASHELL-CHECK-HW-RESIZE": ": _ASHELL-CHECK-HW-RESIZE ( -- ) 1 RESIZE-POLLS +! ;",
    "_ASHELL-PAINT": """: _ASHELL-PAINT ( -- )
        _UTUI-NEEDS-PAINT @ IF 0 _UTUI-NEEDS-PAINT ! ASHELL-DIRTY! THEN
        _ASHELL-DIRTY @ IF
            0 _ASHELL-DIRTY !  1 PAINTS +!
            REDIRTY @ IF ASHELL-DIRTY! THEN
            -1 _ASHELL-OUTPUT-PENDING !
        THEN
        _ASHELL-OUTPUT-PENDING @ IF
            FLUSH-REFUSED @ 0= IF 0 _ASHELL-OUTPUT-PENDING ! THEN
        THEN ;""",
    "_ASHELL-ACTIVATE": ": _ASHELL-ACTIVATE ( -- ) ;",
    "_ASHELL-DIRTY-TOAST-RECT": ": _ASHELL-DIRTY-TOAST-RECT ( -- ) ;",
    "SCR-DIRTY?": ": SCR-DIRTY? ( -- flag ) FALSE ;",
    # The shell reads the tick callback through the descriptor accessor; the
    # fixture descriptor is a single cell holding that callback.
    "APP.TICK-XT": ": APP.TICK-XT ( desc -- a ) ;",
    "_UTUI-NEEDS-PAINT": "VARIABLE _UTUI-NEEDS-PAINT",
    "_ASHELL-POST-Q": "CREATE _ASHELL-POST-Q _ASHELL-POST-MAX CELLS ALLOT",
    "_ASHELL-TOAST-MSG": "CREATE _ASHELL-TOAST-MSG 2 CELLS ALLOT",
}

FIXTURE_STATE = """
VARIABLE FAKE-MS   VARIABLE SLEEPS   VARIABLE YIELDS   VARIABLE PASS-LIMIT
VARIABLE INPUT-AT  VARIABLE INPUT-ON-WAKE  VARIABLE INPUTS
VARIABLE PAINTS    VARIABLE REDIRTY  VARIABLE FLUSH-REFUSED
VARIABLE RESIZE-POLLS  VARIABLE TICKS  VARIABLE ACTIONS
VARIABLE TICK-POSTS  VARIABLE TICK-QUITS
VARIABLE OWNER-PENDING  VARIABLE OWNER-ASKED
CREATE DEADLINES 64 CELLS ALLOT
CREATE TEST-DESC 0 ,
"""

TEST_WORDS = b"""
: TEST-ACTION ( -- ) 1 ACTIONS +! ;
: TEST-TICK ( instance -- )
    DROP 1 TICKS +!
    TICK-POSTS @ IF ['] TEST-ACTION ASHELL-POST THEN
    TICK-QUITS @ IF ASHELL-QUIT THEN ;
: TEST-OWNER-PENDING ( context -- flag )
    OWNER-ASKED !  OWNER-PENDING @ ;
CREATE TEST-OWNER ASHELL-TERMINAL-DESC-SIZE ALLOT
TEST-OWNER ASHELL-TERMINAL-DESC-SIZE 0 FILL
4242 TEST-OWNER _ASHT.CONTEXT !
' TEST-OWNER-PENDING TEST-OWNER _ASHT.PENDING-XT !
TEST-OWNER _ASHELL-TERM-OWNER !
' TEST-TICK
"""


class IdleLoopHarness:
    ROOTS = (
        "_ASHELL-LOOP", "ASHELL-POST", "ASHELL-QUIT", "ASHELL-DIRTY!",
        "ASHELL-TOAST", "_ASHELL-NEXT-DEADLINE", "ASHELL-TERMINAL-DESC-SIZE",
        "_ASHT.CONTEXT", "_ASHT.PENDING-XT",
    )

    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        source = (ROOT / "akashic/tui/app-shell.f").read_text()
        # The optional guard section redefines public words as guarded
        # wrappers; the unguarded originals are the production behaviour.
        source = source[: source.index("§14 — Guard")]
        self.definitions = _definitions(source)
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

        for name in self.ROOTS:
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.runtime.evaluate(TEST_WORDS, step_budget=100_000)
        self.tick_xt = self.runtime.main_context.data.pop()

    def variable(self, name, value=None):
        word = self.runtime.find(name)
        assert word is not None, name
        if value is None:
            return self.runtime.memory.read64(word.body_address)
        self.runtime.memory.write64(word.body_address, value & MASK64)
        return None

    def start(self, *, now=1000, tick=True, tick_ms=50, passes=8):
        """Arm the shell the way _ASHELL-SETUP leaves it, at fake time NOW."""

        self.variable("FAKE-MS", now)
        self.variable("PASS-LIMIT", passes)
        desc = self.runtime.find("TEST-DESC").body_address
        self.runtime.memory.write64(desc, self.tick_xt if tick else 0)
        self.variable("_ASHELL-DESC", desc)
        self.variable("_ASHELL-TICK-MS", tick_ms)
        self.variable("_ASHELL-LAST-TICK", now)
        self.variable("_ASHELL-RUNNING", MASK64)

    def run(self):
        self.runtime.execute("_ASHELL-LOOP", step_budget=3_000_000)
        assert self.runtime.main_context.data.snapshot() == ()
        assert self.runtime.main_context.returns.snapshot() == ()

    def deadlines(self):
        base = self.runtime.find("DEADLINES").body_address
        return [
            self.runtime.memory.read64(base + 8 * index)
            for index in range(self.variable("SLEEPS"))
        ]

    def next_deadline(self):
        self.runtime.execute("_ASHELL-NEXT-DEADLINE", step_budget=100_000)
        return self.runtime.main_context.data.pop()


@pytest.fixture(params=["python", "native"])
def shell(request):
    return IdleLoopHarness(request.param)


def test_quiet_passes_sleep_until_each_next_tick(shell):
    shell.start(passes=6)
    shell.run()
    # Quiet pass, sleep to the tick, tick pass, quiet pass, sleep, ...
    assert shell.deadlines() == [1050, 1100, 1150]
    assert shell.variable("TICKS") == 3
    assert shell.variable("FAKE-MS") == 1150


def test_a_pass_that_consumed_input_does_not_sleep(shell):
    shell.start(passes=2)
    shell.variable("INPUT-AT", 1000)
    shell.run()
    # The input pass painted; only the following quiet pass sleeps.
    assert shell.variable("INPUTS") == 1
    assert shell.variable("PAINTS") == 1
    assert shell.variable("SLEEPS") == 1


def test_a_tick_that_posts_an_action_drains_it_before_sleeping(shell):
    shell.start(passes=3)
    shell.variable("TICK-POSTS", 1)
    shell.variable("_ASHELL-LAST-TICK", 1000 - 50)
    shell.run()
    # Tick pass, drain pass, then a quiet pass sleeps to the next tick.
    assert shell.variable("TICKS") == 1
    assert shell.variable("ACTIONS") == 1
    assert shell.deadlines()[0] == 1050


def test_paint_that_dirties_itself_again_never_sleeps(shell):
    shell.start(passes=6)
    shell.variable("REDIRTY", 1)
    shell.variable("_ASHELL-DIRTY", MASK64)
    shell.run()
    assert shell.variable("PAINTS") == 6
    assert shell.variable("SLEEPS") == 0


def test_a_refused_flush_keeps_the_loop_awake(shell):
    shell.start(passes=5)
    shell.variable("FLUSH-REFUSED", 1)
    shell.variable("_ASHELL-DIRTY", MASK64)
    shell.run()
    assert shell.variable("SLEEPS") == 0
    assert shell.variable("_ASHELL-OUTPUT-PENDING") == MASK64


def test_a_live_owner_with_pending_work_keeps_the_loop_awake(shell):
    shell.start(passes=5)
    shell.variable("_ASHELL-TERM-OWNS", MASK64)
    shell.variable("OWNER-PENDING", MASK64)
    shell.run()
    assert shell.variable("SLEEPS") == 0
    assert shell.variable("OWNER-ASKED") == 4242
    assert shell.variable("RESIZE-POLLS") == 0


def test_a_quiet_live_owner_lets_the_loop_sleep_until_the_tick(shell):
    shell.start(passes=6)
    shell.variable("_ASHELL-TERM-OWNS", MASK64)
    shell.run()
    # The owner reports resizes as input, so no one-tick resize poll bounds
    # the sleep; with no tick the loop would wait for input alone.
    assert shell.deadlines() == [1050, 1100, 1150]
    assert shell.variable("OWNER-ASKED") == 4242


def test_a_quiet_live_owner_without_a_tick_waits_for_input(shell):
    shell.start(tick=False, passes=2)
    shell.variable("_ASHELL-TERM-OWNS", MASK64)
    shell.variable("INPUT-ON-WAKE", 1)
    shell.run()
    assert shell.deadlines()[0] == MASK64
    assert shell.variable("INPUTS") == 1


def test_a_toast_without_a_tick_wakes_at_its_expiry(shell):
    shell.start(tick=False, passes=3)
    shell.runtime.evaluate(b'S" saved" 20 ASHELL-TOAST', step_budget=100_000)
    shell.variable("_ASHELL-DIRTY", 0)
    shell.run()
    # Expiry at 1020 is earlier than the one-tick resize poll at 1050; the
    # expiry pass repaints to clear the toast.
    assert shell.deadlines()[0] == 1020
    assert shell.variable("_ASHELL-TOAST-WAS-VIS") == 0
    assert shell.variable("PAINTS") == 1


def test_without_an_owner_the_resize_poll_bounds_every_sleep(shell):
    shell.start(tick=False, now=5000, tick_ms=50, passes=3)
    assert shell.next_deadline() == 5050
    shell.variable("_ASHELL-TERM-OWNS", MASK64)
    assert shell.next_deadline() == MASK64


def test_the_tick_deadline_is_the_last_tick_plus_the_interval(shell):
    shell.start(now=7000, tick_ms=125)
    shell.variable("_ASHELL-LAST-TICK", 6990)
    shell.variable("_ASHELL-TERM-OWNS", MASK64)
    assert shell.next_deadline() == 7115


def test_a_quit_during_the_pass_skips_the_sleep_and_the_yield(shell):
    shell.start(passes=8)
    shell.variable("TICK-QUITS", 1)
    shell.variable("_ASHELL-LAST-TICK", 1000 - 50)
    shell.run()
    assert shell.variable("TICKS") == 1
    assert shell.variable("SLEEPS") == 0
    assert shell.variable("YIELDS") == 0


def test_loop_sleeps_only_after_its_pass_and_before_the_yield():
    source = (ROOT / "akashic/tui/app-shell.f").read_text()
    loop = re.search(r"(?ms)^: _ASHELL-LOOP\b.*?^\s*REPEAT ;", source)[0]
    code = re.sub(r"\\[^\n]*|\([^)]*\)", "", loop)
    assert code.index("_ASHELL-PASS") < code.index("_ASHELL-RUNNING @ IF")
    assert code.index("_ASHELL-RUNNING @ IF") < code.index("IDLE-UNTIL")
    assert code.index("IDLE-UNTIL") < code.index("YIELD?")
