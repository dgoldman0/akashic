"""Execute the producer's empty-frame fallback with a scripted provider.

A completed draw that cannot be shown rich, once a retained owner is open,
replaces the rich frame with an empty one: a hidden START with no operation,
then its reveal carried with the CELL frame.  The real result seam, the
real empty-frame and reveal words, the real sealed-update steps, and the
real blank-phase PREPARE run on both executors.  Provider state, capture,
candidate building and the rich START are fixture seams; their own
behaviour belongs to their own units.  No display or Desktop is started.
"""

import re

import pytest

from test_rich_menu_projection_damage import MASK64, PRODUCER
from test_rich_terminal_control_map import (
    MegaForthRuntime, NO_EXTENSION_SEAM, ROOT, _definitions,
)


# Fixture seams, each recording what the producer asked of it.
_SEAMS = {
    "RTE-UPDATE-STATE@": ": RTE-UPDATE-STATE@ DROP FP-STATE @ FP-STATUS @ ;",
    "RTE-RETAINED-CANCEL": ": RTE-RETAINED-CANCEL DROP 1 FP-CANCELS +! RTE-S-OK ;",
    "RTE-RETAINED-BEGIN":
        ": RTE-RETAINED-BEGIN DROP FP-BEGIN ! 1 FP-BEGINS +! FP-BEGIN-STATUS @ ;",
    "RTE-RETAINED-SEAL": ": RTE-RETAINED-SEAL DROP FP-SEAL ! 1 FP-SEALS +! RTE-S-OK ;",
    "SCR-DRAW-GENERATION@": ": SCR-DRAW-GENERATION@ FP-DRAW @ ;",
    "_RTHP-BUILD-CANDIDATE": (
        ": _RTHP-BUILD-CANDIDATE DROP 1 FP-BUILDS +! FP-DRAW @ _RTHP-W-DRAW ! "
        "FP-BUILD-STATUS @ FP-BUILT @ ;"
    ),
    "_RTHP-PREPARE-START": ": _RTHP-PREPARE-START DROP 1 FP-STARTS +! SCB-S-OK ;",
    "_RTPROF-MARK": ": _RTPROF-MARK DROP ;",
    # The empty frame never advances the candidate ID frontier, and no step
    # here publishes a rich target bank.
    "_RTHP-ADVANCE-IDS?": ': _RTHP-ADVANCE-IDS? DROP -1 ABORT" unexpected ID advance" ;',
    "_RTHP-TARGET-PUBLISH?": ': _RTHP-TARGET-PUBLISH? DROP -1 ABORT" unexpected publish" ;',
    **NO_EXTENSION_SEAM,
}
_FIXTURE_VARIABLES = (
    "FP-STATE", "FP-STATUS", "FP-CANCELS", "FP-BEGIN", "FP-BEGINS", "FP-BEGIN-STATUS",
    "FP-SEAL", "FP-SEALS", "FP-DRAW", "FP-BUILDS", "FP-BUILD-STATUS", "FP-BUILT",
    "FP-STARTS",
)


class BlankHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text())
        for relative in ("tui/screen.f", "tui/rich-terminal/residual-glyph-planner.f",
                         "tui/rich-terminal/uidl-hybrid-adapter.f"):
            source = (ROOT / "akashic" / relative).read_text()
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

        for name in (*_FIXTURE_VARIABLES, "_RTHP-REBUILD-RESULT", "_RTHP-BLANK-BEGIN",
                     "_RTHP-PREPARE-REVEAL", "_RTHP-PREPARE-BLANK", "_RTHP-STEP-SEALED"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        header = self.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
        self.active = self.allocate(bytes(header))
        self.pending = self.allocate(bytes(header))
        valid = self.constant("_RTHP-TARGET-VALID-MAGIC")
        for bank in (self.active, self.pending):
            self.field(bank, "_RTHP-TB.VALID", valid)
        # A live rich frame: its acknowledged bank routes input and anchors
        # comparison facts; a newer candidate bank is pending.
        for name, value in (("FACADE", 1), ("OWNER", 1), ("OWNER-GEN", 2),
                            ("TARGET-ACTIVE", self.active),
                            ("TARGET-PENDING", self.pending),
                            ("ACTIVE-DRAW", 10), ("SURFACE-GEN", 10),
                            ("NEXT-OBJECT", 104)):
            self.field(self.producer, "_RTHP." + name, value)
        self.runtime.memory.write64(
            self.producer + self.offset("_RTHP.ACTIVE-FACTS")
            + self.offset("_RTHP-KF.BANK"), self.active)
        self.phase("LIVE")
        self.engine("RTE-UPDATE-IDLE")
        self.variable("FP-BEGIN-STATUS", self.constant("RTE-S-OK"))

    def allocate(self, data):
        self.serial += 1
        word = self.runtime.define_created(f"BLANK-{self.serial}", initial_body=bytes(len(data) + 7))
        address = (word.body_address + 7) & -8
        self.runtime.memory.write_bytes(address, data)
        return address

    def constant(self, name):
        return int(self.definitions[name].split()[0], 0)

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def field(self, base, name, value):
        self.runtime.memory.write64(base + self.offset(name), value & MASK64)

    def read(self, name, base=None):
        base = self.producer if base is None else base
        return self.runtime.memory.read64(base + self.offset(name))

    def variable(self, name, value):
        word = self.runtime.dictionary.find(name.encode())
        self.runtime.memory.write64(word.body_address, value & MASK64)

    def value(self, name):
        return self.runtime.memory.read64(self.runtime.dictionary.find(name.encode()).body_address)

    def phase(self, name=None):
        if name is not None:
            self.field(self.producer, "_RTHP.PHASE", self.constant("_RTHP-PH-" + name))
        return self.read("_RTHP.PHASE")

    def engine(self, state, status="RTE-S-OK"):
        self.variable("FP-STATE", self.constant(state))
        self.variable("FP-STATUS", self.constant(status))

    def results(self, name, *inputs):
        for value in inputs:
            self.runtime.main_context.data.push(value & MASK64)
        self.runtime.execute(name, step_budget=3_000_000)
        result = self.runtime.main_context.data.snapshot()
        while self.runtime.main_context.data.depth():
            self.runtime.main_context.data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def step_sealed(self, accept, retry, output):
        return self.results("_RTHP-STEP-SEALED", self.constant("_RTHP-PH-" + accept),
                            self.constant("_RTHP-PH-" + retry), output, self.producer)


@pytest.fixture(params=("python", "native"))
def blank(request):
    return BlankHarness(request.param)


def test_a_refused_draw_asks_for_the_empty_frame_and_holds_cell(blank):
    blank.variable("_RTHP-W-P", blank.producer)
    blank.variable("_RTHP-W-DRAW", 12)
    for refusal in ("RTE-S-CAPACITY", "RTE-S-UNAVAILABLE"):
        blank.phase("READY-START")
        assert blank.results("_RTHP-REBUILD-RESULT", blank.constant(refusal), 0) == (
            blank.constant("SCB-S-WOULD-BLOCK"), 0)
        assert blank.phase() == blank.constant("_RTHP-PH-READY-BLANK")
        assert blank.read("_RTHP.REFUSED-DRAW") == 12
    # Backpressure only waits, and anything else stays fatal.
    blank.phase("READY-START")
    assert blank.results("_RTHP-REBUILD-RESULT", blank.constant("RTE-S-WOULD-BLOCK"), 0) == (
        blank.constant("SCB-S-WOULD-BLOCK"), 0)
    assert blank.results("_RTHP-REBUILD-RESULT", blank.constant("RTE-S-INVALID"), 0) == (
        blank.constant("SCB-S-INVALID"), 0)
    assert blank.phase() == blank.constant("_RTHP-PH-READY-START")


def test_the_empty_frame_is_sealed_revealed_and_retires_the_rich_targets(blank):
    ok = blank.constant("SCB-S-OK")
    blank.phase("READY-BLANK")
    # A retained update still publishing is waited for, and nothing begins.
    blank.engine("RTE-UPDATE-PUBLISHING")
    assert blank.results("_RTHP-BLANK-BEGIN", blank.producer) == (
        blank.constant("SCB-S-WOULD-BLOCK"),)
    assert blank.value("FP-BEGINS") == 0
    assert blank.phase() == blank.constant("_RTHP-PH-READY-BLANK")

    # Idle: a hidden START with no operation is sealed.  The pending
    # candidate bank is abandoned; the old rich targets stay until the reveal.
    blank.engine("RTE-UPDATE-IDLE")
    assert blank.results("_RTHP-BLANK-BEGIN", blank.producer) == (ok,)
    assert blank.value("FP-BEGIN") == blank.constant("RTE-RETAINED-REPLACE-START")
    assert blank.value("FP-SEAL") == blank.constant("RTE-COMMIT")
    assert (blank.value("FP-BEGINS"), blank.value("FP-SEALS")) == (1, 1)
    assert blank.phase() == blank.constant("_RTHP-PH-BLANK-SEALED")
    assert blank.read("_RTHP.TARGET-PENDING") == 0
    assert blank.read("_RTHP-TB.VALID", blank.pending) == 0
    assert blank.read("_RTHP.TARGET-ACTIVE") == blank.active

    # A rejected hidden START is cancelled and begun again.
    blank.engine("RTE-UPDATE-SEALED", "RTE-S-STALE")
    assert blank.step_sealed("READY-BLANK-REVEAL", "READY-BLANK", MASK64) == (ok, 0, MASK64)
    assert blank.value("FP-CANCELS") == 1
    assert blank.phase() == blank.constant("_RTHP-PH-READY-BLANK")
    blank.engine("RTE-UPDATE-IDLE")
    assert blank.results("_RTHP-BLANK-BEGIN", blank.producer) == (ok,)

    # While it publishes the step waits; its acknowledgement asks for the
    # reveal and advances no object ID.
    blank.engine("RTE-UPDATE-AWAITING")
    assert blank.step_sealed("READY-BLANK-REVEAL", "READY-BLANK", MASK64) == (ok, MASK64, 0)
    blank.engine("RTE-UPDATE-IDLE")
    assert blank.step_sealed("READY-BLANK-REVEAL", "READY-BLANK", MASK64) == (ok, 0, MASK64)
    assert blank.phase() == blank.constant("_RTHP-PH-READY-BLANK-REVEAL")
    assert blank.read("_RTHP.NEXT-OBJECT") == 104

    # The reveal is the same empty CONTINUE a rich replacement uses.
    assert blank.results("_RTHP-PREPARE-REVEAL",
                         blank.constant("_RTHP-PH-BLANK-REVEAL-SEALED"), blank.producer) == (ok,)
    assert blank.value("FP-BEGIN") == blank.constant("RTE-RETAINED-REPLACE-CONTINUE")
    assert blank.value("FP-SEAL") == blank.constant("RTE-COMMIT-AND-REVEAL")
    assert blank.phase() == blank.constant("_RTHP-PH-BLANK-REVEAL-SEALED")

    # Its acknowledgement leaves no control to route input to and no bank or
    # facts to compare a later frame with.
    assert blank.step_sealed("BLANK", "READY-BLANK-REVEAL", 0) == (ok, 0, 0)
    assert blank.phase() == blank.constant("_RTHP-PH-BLANK")
    assert blank.read("_RTHP.TARGET-ACTIVE") == 0
    assert blank.read("_RTHP.ACTIVE-DRAW") == 0
    assert blank.read("_RTHP-TB.VALID", blank.active) == 0
    assert blank.runtime.memory.read64(
        blank.producer + blank.offset("_RTHP.ACTIVE-FACTS") + blank.offset("_RTHP-KF.BANK")) == 0
    assert blank.read("_RTHP.NEXT-OBJECT") == 104


def test_with_nothing_retained_cell_shows_each_draw_until_one_fits(blank):
    ok = blank.constant("SCB-S-OK")
    blank.phase("BLANK")
    blank.field(blank.producer, "_RTHP.TARGET-ACTIVE", 0)
    blank.field(blank.producer, "_RTHP.ACTIVE-DRAW", 0)
    blank.field(blank.producer, "_RTHP.REFUSED-DRAW", 12)

    # The refused draw is not built again.
    blank.variable("FP-DRAW", 12)
    assert blank.results("_RTHP-PREPARE-BLANK", blank.producer) == (ok,)
    assert blank.value("FP-BUILDS") == 0

    # A newer draw that still cannot be shown rich is refused in turn.
    blank.variable("FP-DRAW", 13)
    blank.variable("FP-BUILD-STATUS", blank.constant("RTE-S-CAPACITY"))
    blank.variable("FP-BUILT", 0)
    assert blank.results("_RTHP-PREPARE-BLANK", blank.producer) == (ok,)
    assert blank.value("FP-BUILDS") == 1
    assert blank.read("_RTHP.REFUSED-DRAW") == 13
    assert blank.phase() == blank.constant("_RTHP-PH-BLANK")

    # Backpressure shows CELL and keeps the draw for another try.
    blank.variable("FP-DRAW", 14)
    blank.variable("FP-BUILD-STATUS", blank.constant("RTE-S-WOULD-BLOCK"))
    assert blank.results("_RTHP-PREPARE-BLANK", blank.producer) == (ok,)
    assert blank.read("_RTHP.REFUSED-DRAW") == 13
    assert blank.value("FP-STARTS") == 0

    # A draw that can be shown rich goes back through a full replacement.
    blank.variable("FP-BUILD-STATUS", blank.constant("RTE-S-OK"))
    blank.variable("FP-BUILT", MASK64)
    assert blank.results("_RTHP-PREPARE-BLANK", blank.producer) == (ok,)
    assert blank.phase() == blank.constant("_RTHP-PH-READY-START")
    assert blank.value("FP-STARTS") == 1
