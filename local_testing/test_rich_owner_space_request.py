"""Execute the producer asking an open owner's terminal for more space.

The real decision, request and answer handling run on both executors.  The
owner state, the request itself, the counted needs, the quotas held and the
terminal's limits are fixture seams; their own behaviour belongs to their
own units.  No display or Desktop is started.
"""

import re

import pytest

from test_rich_menu_projection_damage import MASK64, PRODUCER
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


# Only the object quota varies: the frame needs FP-NEED, the owner holds
# FP-HELD, and the terminal offers FP-LIMIT.  A request records what it
# asked for; the terminal's answer is whatever FP-HELD says afterwards.
_SEAMS = {
    "RTE-OWNER-STATE@": ": RTE-OWNER-STATE@ DROP 2DROP FP-STATE @ FP-STATUS @ ;",
    "_RTHP-RESIZE": (
        ": _RTHP-RESIZE 1 FP-ASKS +! DUP _RTHP.ASK 16 + @ FP-ASKED ! "
        "DROP FP-RESIZE-STATUS @ ;"
    ),
    "_RTHP-NEED@": (
        ": _RTHP-NEED@ DUP _RTHP.NEED RTE-QUOTA-SIZE 0 FILL "
        "FP-NEED @ SWAP _RTHP.NEED 16 + ! -1 ;"
    ),
    "_RTHP-HELD@": (
        ": _RTHP-HELD@ DUP _RTHP.HELD RTE-QUOTA-SIZE 0 FILL "
        "FP-HELD @ SWAP _RTHP.HELD 16 + ! FP-OPEN @ ;"
    ),
    "_RTHP-Q-LIMIT": ": _RTHP-Q-LIMIT 2DROP FP-LIMIT @ ;",
    "SCR-DRAW-GENERATION@": ": SCR-DRAW-GENERATION@ FP-DRAW @ ;",
    "_RTPROF-MARK": ": _RTPROF-MARK DROP ;",
}
_FIXTURE_VARIABLES = (
    "FP-STATE", "FP-STATUS", "FP-ASKS", "FP-ASKED", "FP-RESIZE-STATUS",
    "FP-NEED", "FP-HELD", "FP-OPEN", "FP-LIMIT", "FP-DRAW",
)


class SpaceHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text())
        source = (ROOT / "akashic" / "tui/screen.f").read_text()
        for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", source):
            self.definitions[match[2]] = match[0]
        for name in _FIXTURE_VARIABLES:
            self.definitions[name] = f"VARIABLE {name}"
        self.definitions.update(_SEAMS)
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

        for name in (*_FIXTURE_VARIABLES, "_RTHP-ASK-FOR-SPACE?", "_RTHP-STEP-RESIZING"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        word = self.runtime.define_created(
            "SPACE-PRODUCER", initial_body=bytes(self.constant("RTHP-SIZE") + 7))
        self.producer = (word.body_address + 7) & -8
        self.variable("FP-DRAW", 7)
        self.variable("FP-NEED", 30)
        self.variable("FP-HELD", 20)
        self.variable("FP-OPEN", MASK64)
        self.variable("FP-LIMIT", 100)
        self.variable("FP-RESIZE-STATUS", self.constant("RTE-S-OK"))
        self.owner("OPEN")
        self.phase("LIVE")

    def constant(self, name):
        return int(self.definitions[name].split()[0], 0)

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def read(self, name):
        return self.runtime.memory.read64(self.producer + self.offset(name))

    def variable(self, name, value):
        word = self.runtime.dictionary.find(name.encode())
        self.runtime.memory.write64(word.body_address, value & MASK64)

    def value(self, name):
        return self.runtime.memory.read64(self.runtime.dictionary.find(name.encode()).body_address)

    def phase(self, name=None):
        if name is not None:
            self.runtime.memory.write64(self.producer + self.offset("_RTHP.PHASE"),
                                        self.constant("_RTHP-PH-" + name))
        return self.read("_RTHP.PHASE")

    def owner(self, state):
        self.variable("FP-STATE", self.constant("RTE-OWNER-ST-" + state))
        self.variable("FP-STATUS", self.constant("RTE-S-OK"))

    def results(self, name):
        self.runtime.main_context.data.push(self.producer)
        self.runtime.execute(name, step_budget=3_000_000)
        result = self.runtime.main_context.data.snapshot()
        while self.runtime.main_context.data.depth():
            self.runtime.main_context.data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result


@pytest.fixture(params=("python", "native"))
def harness(request):
    return SpaceHarness(request.param)


def test_a_frame_that_outgrows_its_owner_asks_and_resumes_when_granted(harness):
    ok = harness.constant("SCB-S-OK")
    assert harness.results("_RTHP-ASK-FOR-SPACE?") == (MASK64,)
    # Thirty objects needed, twenty held: ask for thirty and half again.
    assert (harness.value("FP-ASKS"), harness.value("FP-ASKED")) == (1, 45)
    assert harness.phase() == harness.constant("_RTHP-PH-RESIZING")
    assert harness.read("_RTHP.RESUME-PHASE") == harness.constant("_RTHP-PH-LIVE")

    harness.owner("RESIZING")
    assert harness.results("_RTHP-STEP-RESIZING") == (ok, MASK64, 0)
    harness.owner("OPEN")
    harness.variable("FP-HELD", 45)
    assert harness.results("_RTHP-STEP-RESIZING") == (ok, 0, MASK64)
    assert harness.phase() == harness.constant("_RTHP-PH-LIVE")
    assert harness.read("_RTHP.SPACE-REFUSED-DRAW") == 0
    assert harness.value("FP-ASKS") == 1


def test_a_refusal_asks_for_the_exact_need_once_then_the_draw_is_not_asked_again(harness):
    ok = harness.constant("SCB-S-OK")
    harness.results("_RTHP-ASK-FOR-SPACE?")
    # No room for forty-five: ask once more for exactly thirty.
    assert harness.results("_RTHP-STEP-RESIZING") == (ok, MASK64, 0)
    assert (harness.value("FP-ASKS"), harness.value("FP-ASKED")) == (2, 30)
    assert harness.phase() == harness.constant("_RTHP-PH-RESIZING")
    # No room for thirty either: the draw is refused and the phase resumes,
    # so the rebuilt frame leaves what does not fit as CELL.
    assert harness.results("_RTHP-STEP-RESIZING") == (ok, 0, MASK64)
    assert harness.phase() == harness.constant("_RTHP-PH-LIVE")
    assert harness.read("_RTHP.SPACE-REFUSED-DRAW") == 7
    assert harness.results("_RTHP-ASK-FOR-SPACE?") == (0,)
    assert harness.value("FP-ASKS") == 2
    # A newer draw asks again.
    harness.variable("FP-DRAW", 8)
    assert harness.results("_RTHP-ASK-FOR-SPACE?") == (MASK64,)
    assert harness.value("FP-ASKS") == 3


@pytest.mark.parametrize("need,held,is_open,limit,status", [
    (30, 30, True, 100, "RTE-S-OK"),  # the frame fits what is held
    (300, 20, True, 100, "RTE-S-OK"),  # more than the terminal offers at all
    (30, 20, False, 100, "RTE-S-OK"),  # no open owner
    (30, 20, True, 100, "RTE-S-WOULD-BLOCK"),  # the request could not be made
])
def test_no_request_when_more_space_cannot_help(harness, need, held, is_open, limit, status):
    harness.variable("FP-NEED", need)
    harness.variable("FP-HELD", held)
    harness.variable("FP-OPEN", MASK64 if is_open else 0)
    harness.variable("FP-LIMIT", limit)
    harness.variable("FP-RESIZE-STATUS", harness.constant(status))
    assert harness.results("_RTHP-ASK-FOR-SPACE?") == (0,)
    assert harness.phase() == harness.constant("_RTHP-PH-LIVE")
    asked = 1 if status == "RTE-S-WOULD-BLOCK" else 0
    assert harness.value("FP-ASKS") == asked
    # A request that could not be made counts as refused for this draw.
    assert harness.read("_RTHP.SPACE-REFUSED-DRAW") == (7 if asked else 0)


def test_the_ask_never_exceeds_what_the_terminal_offers(harness):
    harness.variable("FP-LIMIT", 40)
    assert harness.results("_RTHP-ASK-FOR-SPACE?") == (MASK64,)
    assert harness.value("FP-ASKED") == 40
