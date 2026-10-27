"""The rich terminal's owner runs the full refresh's check at quiet moments.

The APT-1 owner of the app shell gives the shell three things for the full
refresh (tui/rich-terminal/frame-refresh.f): its pass service runs the check
when one falls due on a live rich screen with no paint pending and no part
of an input event held back; its deadline callback names when the next
check falls due, so the shell wakes for it; and every event its poll gives
counts as input, after which a check is owed once input is quiet.  These
tests run the owner's production words and the refresh module's, with the
owner's own service, the session's state, the shell's paint state and the
clock replaced by fixtures.
"""

import re

import pytest

from test_rich_glyph_growth import GrowthHarness
from test_rich_terminal_control_map import (
    MEGAPAD_ROOT, MegaForthRuntime, ROOT, _definitions,
)

MASK64 = (1 << 64) - 1

FIXTURES = {
    "FAKE-MS": "VARIABLE FAKE-MS",
    "MS@": ": MS@ ( -- ms ) FAKE-MS @ ;",
    "SCB-S-OK": "0 CONSTANT SCB-S-OK",
    "APTAS-VALID?": ": APTAS-VALID? ( owner -- flag ) DROP -1 ;",
    # The owner's own service, which the pass service runs first.
    "_APTAS-SERVICE": """: _APTAS-SERVICE ( owner -- status owns-stream )
        DROP 1 SERVICES +!  SVC-STATUS @ SVC-OWNS @ ;""",
    "PT-STATE@": ": PT-STATE@ ( session -- state ) DROP SESSION-STATE @ ;",
    "_APTAS-HOLDS?": ": _APTAS-HOLDS? ( owner -- flag ) DROP HOLDING @ ;",
    "ASHELL-PAINT-PENDING?": ": ASHELL-PAINT-PENDING? ( -- flag ) PAINT-PENDING @ ;",
    "_APTAS-POLL-EVENT": """: _APTAS-POLL-EVENT ( event owner -- status has-event )
        2DROP 0 HAS-EVENT @ ;""",
}

STATE = """
VARIABLE SERVICES  VARIABLE SVC-STATUS  VARIABLE SVC-OWNS
VARIABLE SESSION-STATE  VARIABLE HOLDING  VARIABLE PAINT-PENDING
VARIABLE HAS-EVENT  VARIABLE T-CALLS
: T-CHECK ( context -- compared? differs? ) DROP 1 T-CALLS +! -1 0 ;
"""


class RefreshOwnerHarness(GrowthHarness):
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        source = "\n".join(path.read_text() for path in (
            ROOT / "akashic/tui/app-shell.f",
            MEGAPAD_ROOT / "rich-terminal.f",
            ROOT / "akashic/tui/rich-terminal/frame-refresh.f",
            ROOT / "akashic/tui/app-shell-apt1.f",
        ))
        self.definitions = _definitions(source)
        for match in re.finditer(
            r"(?m)^ASHELL-TERMINAL-DESC-SIZE[^\n]* CONSTANT (\S+)", source,
        ):
            self.definitions[match[1]] = match[0]
        self.definitions.update(FIXTURES)
        chunks, seen = [STATE], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            for token in re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration).split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in ("APTAS-SIZE", "RFSH-CHECK!", "RFSH-DEADLINE", "RFSH-CHECKS",
                     "_APTAS-PASS-SERVICE", "_APTAS-DEADLINE", "_APTAS-POLL"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        # The times the module sets as it loads; this build reads only its
        # definitions.
        self.variable("RFSH-QUIET-MS", 1000)
        self.variable("RFSH-INTERVAL-MS", 5000)
        self.owner = self.allocate(bytes(self.constant("APTAS-SIZE")))
        self.field(self.owner, "_APTAS.SESSION", 0x5E55)

    def at(self, ms):
        self.variable("FAKE-MS", ms)

    def live(self):
        """A live rich screen, quiet, whose owner's service went well."""
        self.variable("SVC-STATUS", 0)
        self.variable("SVC-OWNS", MASK64)
        self.variable("SESSION-STATE", self.constant("PT-ST-ACTIVE"))
        self.variable("HOLDING", 0)
        self.variable("PAINT-PENDING", 0)

    def register(self, at=0):
        self.at(at)
        check = self.runtime.find("T-CHECK")
        assert self.results("RFSH-CHECK!", check.xt, 0) == ()

    def serve(self):
        status, owns = self.results("_APTAS-PASS-SERVICE", self.owner)
        assert (status, owns) == (self.variable("SVC-STATUS"), self.variable("SVC-OWNS"))

    def calls(self):
        return self.variable("T-CALLS")


@pytest.fixture(params=["python", "native"])
def owner(request):
    return RefreshOwnerHarness(request.param)


def test_the_pass_service_runs_a_due_check_on_a_quiet_live_screen(owner):
    h = owner
    h.live()
    h.register()
    h.at(4999)
    h.serve()
    assert h.calls() == 0
    h.at(5000)
    h.serve()
    assert h.calls() == 1
    assert h.variable("RFSH-CHECKS") == 1
    # The owner's own service ran each time, first.
    assert h.variable("SERVICES") == 2


@pytest.mark.parametrize("variable, value", [
    ("PAINT-PENDING", MASK64),   # a change has asked for a paint that has not run
    ("HOLDING", MASK64),         # the rest of an input event is still to come
    ("SVC-STATUS", 1),           # the owner's service did not go well
    ("SVC-OWNS", 0),             # the owner does not hold the stream
])
def test_a_due_check_waits_while_the_screen_is_not_quiet(owner, variable, value):
    h = owner
    h.live()
    h.register()
    h.variable(variable, value)
    h.at(6000)
    h.serve()
    assert h.calls() == 0
    # Once quiet again, the check that fell due runs.
    h.live()
    h.serve()
    assert h.calls() == 1


def test_no_check_runs_unless_the_rich_session_is_active(owner):
    h = owner
    h.live()
    h.register()
    h.variable("SESSION-STATE", h.constant("PT-ST-ANSI"))
    h.at(6000)
    h.serve()
    assert h.calls() == 0
    assert h.results("_APTAS-DEADLINE", h.owner) == (MASK64,)


def test_the_deadline_is_the_next_check_on_a_live_rich_screen(owner):
    h = owner
    h.live()
    assert h.results("_APTAS-DEADLINE", h.owner) == (MASK64,)
    h.register(at=1000)
    assert h.results("_APTAS-DEADLINE", h.owner) == (6000,)
    h.variable("SESSION-STATE", h.constant("PT-ST-LOST"))
    assert h.results("_APTAS-DEADLINE", h.owner) == (MASK64,)


def test_every_event_the_owner_gives_is_input(owner):
    h = owner
    h.live()
    h.register()
    h.at(2000)
    h.variable("HAS-EVENT", 0)
    assert h.results("_APTAS-POLL", 0, h.owner) == (0, 0)
    assert h.results("_APTAS-DEADLINE", h.owner) == (5000,)
    h.variable("HAS-EVENT", MASK64)
    assert h.results("_APTAS-POLL", 0, h.owner) == (0, MASK64)
    # A check is owed once input has been quiet for a second.
    assert h.results("_APTAS-DEADLINE", h.owner) == (3000,)
