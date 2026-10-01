"""Execute the producer's owner open against a terminal that refuses it.

The real first attempt and opening step run on both executors.  The owner
state, the open request and the candidate build are fixture seams; their own
behaviour belongs to their own units.  No display or Desktop is started.
"""

import re

import pytest

from test_rich_menu_projection_damage import MASK64, PRODUCER
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


_SEAMS = {
    "RTE-OWNER-STATE@": ": RTE-OWNER-STATE@ DROP 2DROP FP-STATE @ FP-STATUS @ ;",
    "_RTHP-OPEN": ": _RTHP-OPEN DROP 1 FP-OPENS +! FP-OPEN-STATUS @ ;",
    "_RTHP-BUILD-CANDIDATE": (
        ": _RTHP-BUILD-CANDIDATE DUP _RTHP-W-P ! FP-DRAW @ DUP _RTHP-W-DRAW ! "
        "SWAP _RTHP.SOURCE-DRAW ! 1 FP-BUILDS +! FP-BUILD-STATUS @ FP-BUILT @ ;"
    ),
    "_RTPROF-MARK": ": _RTPROF-MARK DROP ;",
}
_FIXTURE_VARIABLES = (
    "FP-STATE", "FP-STATUS", "FP-OPENS", "FP-OPEN-STATUS", "FP-DRAW", "FP-BUILDS",
    "FP-BUILD-STATUS", "FP-BUILT",
)


class OpenHarness:
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
                if token.startswith("_RTPROF-PH-") and token not in self.definitions:
                    self.definitions[token] = f"0 CONSTANT {token}"
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in (*_FIXTURE_VARIABLES, "_RTHP-TRY-CANDIDATE", "_RTHP-STEP-OPENING",
                     "_RTHP-DIAG-OPEN-REFUSALS"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        word = self.runtime.define_created(
            "OPEN-PRODUCER", initial_body=bytes(self.constant("RTHP-SIZE") + 7))
        self.producer = (word.body_address + 7) & -8
        self.variable("FP-BUILD-STATUS", self.constant("RTE-S-OK"))
        self.variable("FP-BUILT", MASK64)
        self.variable("FP-DRAW", 7)
        self.phase("WAIT")

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

    def owner(self, state, status="RTE-S-OK"):
        self.variable("FP-STATE", self.constant("RTE-OWNER-ST-" + state))
        self.variable("FP-STATUS", self.constant(status))

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
    return OpenHarness(request.param)


def test_a_refused_open_waits_for_a_newer_draw_instead_of_asking_again(harness):
    ok = harness.constant("SCB-S-OK")
    harness.variable("FP-OPEN-STATUS", harness.constant("RTE-S-OK"))
    assert harness.results("_RTHP-TRY-CANDIDATE") == (ok, MASK64)
    assert harness.phase() == harness.constant("_RTHP-PH-OPENING")
    assert harness.read("_RTHP.OPEN-QUEUED") == MASK64
    assert harness.value("FP-OPENS") == 1

    # While the terminal has not answered, the step only waits.
    harness.owner("OPENING")
    assert harness.results("_RTHP-STEP-OPENING") == (ok, MASK64, 0)
    assert harness.value("FP-OPENS") == 1

    # The terminal refused: CELL keeps this draw and nothing is asked again.
    harness.owner("FREE")
    assert harness.results("_RTHP-STEP-OPENING") == (ok, 0, 0)
    assert harness.phase() == harness.constant("_RTHP-PH-WAIT")
    assert harness.read("_RTHP.REFUSED-DRAW") == 7
    assert harness.read("_RTHP.OPEN-QUEUED") == 0
    assert harness.value("FP-OPENS") == 1
    assert harness.value("_RTHP-DIAG-OPEN-REFUSALS") == 1

    # A newer draw is built and asks once more.
    harness.variable("FP-DRAW", 8)
    assert harness.results("_RTHP-TRY-CANDIDATE") == (ok, MASK64)
    assert harness.value("FP-OPENS") == 2
    assert harness.value("FP-BUILDS") == 2


def test_an_open_that_could_not_be_queued_is_tried_again(harness):
    ok = harness.constant("SCB-S-OK")
    harness.variable("FP-OPEN-STATUS", harness.constant("RTE-S-WOULD-BLOCK"))
    assert harness.results("_RTHP-TRY-CANDIDATE") == (ok, MASK64)
    assert harness.phase() == harness.constant("_RTHP-PH-OPENING")
    assert harness.read("_RTHP.OPEN-QUEUED") == 0

    # Nothing was queued, so a FREE owner means ask again, not a refusal.
    harness.owner("FREE")
    assert harness.results("_RTHP-STEP-OPENING") == (ok, MASK64, 0)
    assert harness.value("FP-OPENS") == 2
    assert harness.phase() == harness.constant("_RTHP-PH-OPENING")
    harness.variable("FP-OPEN-STATUS", harness.constant("RTE-S-OK"))
    assert harness.results("_RTHP-STEP-OPENING") == (ok, MASK64, 0)
    assert harness.read("_RTHP.OPEN-QUEUED") == MASK64
    assert harness.value("FP-OPENS") == 3
    assert harness.value("_RTHP-DIAG-OPEN-REFUSALS") == 0

    # The open lands: the START is prepared and the request is settled.
    harness.owner("OPEN")
    assert harness.results("_RTHP-STEP-OPENING") == (ok, 0, MASK64)
    assert harness.phase() == harness.constant("_RTHP-PH-READY-START")
    assert harness.read("_RTHP.OPEN-QUEUED") == 0
