"""Execute a START's and a DELTA's preparation with Desk's shell installed.

With the shell installed, the producer builds its candidate for the shell:
no runs and no admission of its own, since the shell plans the runs of its
regions and admits its whole batch.  When the shell cannot build the batch,
the candidate is built again alone, with its own runs, admission and family
strips, and offered to the shell once more; if the shell still cannot
build, the candidate goes out on its own.  A DELTA the shell cannot
prepare for want of engine working storage is prepared once more after the
storage grew, as a START is.  The real PREPARE-START, alone build, rebuild
result and DELTA preparation run on both executors.  The shell, the candidate
build, capture, packing and the engine are scripted seams, each recording
what the producer asked of it.
"""

import re

import pytest

from test_rich_menu_projection_damage import MASK64, PRODUCER
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


_SEAMS = {
    "_RTPROF-MARK": ": _RTPROF-MARK DROP ;",
    "_RTHP-CAPTURE-SLOT": ": _RTHP-CAPTURE-SLOT DROP SCB-S-OK ;",
    "_RTHP-TARGET-ABORT": ": _RTHP-TARGET-ABORT DROP 1 AR-ABORTS +! ;",
    "_RTHP-FIXED?": ": _RTHP-FIXED? DROP -1 ;",
    "_RTHP-TARGET-CANDIDATE?": ": _RTHP-TARGET-CANDIDATE? DROP 1 AR-PACKS +! -1 ;",
    # The shell: each PREPARE answers with the next scripted status.
    "_RTHP-EXTENSION-CALL": (
        ": _RTHP-EXTENSION-CALL DROP "
        "DUP RTHPX-PREPARE = OVER RTHPX-DELTA-PREPARE = OR IF "
        "DROP AR-PREPARES @ CELLS AR-ANSWERS + @ 1 AR-PREPARES +! EXIT THEN "
        "DUP RTHPX-ABORT = IF DROP 1 AR-XABORTS +! RTE-S-OK EXIT THEN "
        "DUP RTHPX-EMIT = IF DROP 1 AR-XEMITS +! RTE-S-OK EXIT THEN "
        "DROP RTE-S-OK ;"
    ),
    "_RTHP-GROW-STORAGE?": ": _RTHP-GROW-STORAGE? DROP 1 AR-GROWS +! AR-GROW @ ;",
    "_RTHP-ASK-FOR-SPACE?": ": _RTHP-ASK-FOR-SPACE? DROP 0 ;",
    "_RTHP-CROSS-LAYERED?": ": _RTHP-CROSS-LAYERED? DROP 0 ;",
    "_RTHP-REFUSAL-REASON": ": _RTHP-REFUSAL-REASON DROP RTHP-WHY-OTHER ;",
    "_RTHP-EXTENSION-FALLBACK!": ": _RTHP-EXTENSION-FALLBACK! DROP 2DROP 1 AR-FALLBACKS +! ;",
    # A build records whether it ran alone and leaves the candidate built
    # for the mode it ran in, as the real build does.
    "_RTHP-BUILD-CANDIDATE": (
        ": _RTHP-BUILD-CANDIDATE DUP _RTHP-W-P ! 1 AR-BUILDS +! "
        "_RTHP-W-ALONE @ AR-ALONE ! 12 _RTHP-W-DRAW ! "
        "_RTHP-W-SHELL-MODE? 0 _RTHP-W-ALONE ! SWAP _RTHP.SHELL-BUILT ! "
        "AR-BUILD-STATUS @ AR-BUILT @ ;"
    ),
    "SCR-DRAW-GENERATION@": ": SCR-DRAW-GENERATION@ 12 ;",
    "RTE-RETAINED-BEGIN": ": RTE-RETAINED-BEGIN 2DROP RTE-S-OK ;",
    "RTE-RETAINED-SEAL": ": RTE-RETAINED-SEAL 2DROP 1 AR-SEALS +! RTE-S-OK ;",
    "_RTHP-EMIT-BASE-START": ": _RTHP-EMIT-BASE-START 1 AR-BASE-STARTS +! RTE-S-OK ;",
    "_RTHP-SEAL-PENDING": ": _RTHP-SEAL-PENDING DROP ;",
    "UPICSN-RELEASE-ALL": ": UPICSN-RELEASE-ALL ;",
}
_FIXTURE_VARIABLES = (
    "AR-ABORTS", "AR-PACKS", "AR-PREPARES", "AR-XABORTS", "AR-XEMITS", "AR-FALLBACKS",
    "AR-BUILDS", "AR-ALONE", "AR-BUILD-STATUS", "AR-BUILT", "AR-SEALS",
    "AR-BASE-STARTS", "AR-GROWS", "AR-GROW",
)


class AloneHarness:
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
        self.definitions["AR-ANSWERS"] = "CREATE AR-ANSWERS 4 CELLS ALLOT"
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

        for name in (*_FIXTURE_VARIABLES, "AR-ANSWERS", "_RTHP-PREPARE-START",
                     "_RTHP-EXTENSION-DELTA", "_RTHP-DIAG-ALONE-REBUILDS"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        # An open owner with Desk's shell installed and a live frame.
        for name, value in (("FACADE", 1), ("OWNER", 1), ("OWNER-GEN", 2),
                            ("EXTENSION", 1), ("TARGET-ACTIVE", 1),
                            ("SOURCE-DRAW", 12)):
            self.field("_RTHP." + name, value)
        self.phase("READY-START")

    def allocate(self, data):
        self.serial += 1
        word = self.runtime.define_created(f"ALONE-{self.serial}",
                                           initial_body=bytes(len(data) + 7))
        address = (word.body_address + 7) & -8
        self.runtime.memory.write_bytes(address, data)
        return address

    def constant(self, name):
        return int(self.definitions[name].split()[0], 0)

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def field(self, name, value=None):
        address = self.producer + self.offset(name)
        if value is None:
            return self.runtime.memory.read64(address)
        self.runtime.memory.write64(address, value & MASK64)

    def variable(self, name, value=None):
        address = self.runtime.dictionary.find(name.encode()).body_address
        if value is None:
            return self.runtime.memory.read64(address)
        self.runtime.memory.write64(address, value & MASK64)

    def phase(self, name=None):
        if name is not None:
            self.field("_RTHP.PHASE", self.constant("_RTHP-PH-" + name))
        return self.field("_RTHP.PHASE")

    def shell_answers(self, *statuses):
        answers = self.runtime.dictionary.find(b"AR-ANSWERS").body_address
        for index, status in enumerate(statuses):
            self.runtime.memory.write64(answers + 8 * index, self.constant(status))

    def delta_status(self):
        self.variable("_RTHP-P-P", self.producer)
        self.runtime.execute("_RTHP-EXTENSION-DELTA", step_budget=3_000_000)
        result = self.runtime.main_context.data.snapshot()
        while self.runtime.main_context.data.depth():
            self.runtime.main_context.data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        assert len(result) == 1
        return result[0]

    def prepare_start(self):
        self.runtime.main_context.data.push(self.producer)
        self.runtime.execute("_RTHP-PREPARE-START", step_budget=3_000_000)
        result = self.runtime.main_context.data.snapshot()
        while self.runtime.main_context.data.depth():
            self.runtime.main_context.data.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result


@pytest.fixture(params=("python", "native"))
def harness(request):
    return AloneHarness(request.param)


def _counts(h):
    return {name: h.variable(name) for name in
            ("AR-BUILDS", "AR-PREPARES", "AR-XEMITS", "AR-BASE-STARTS",
             "AR-FALLBACKS", "AR-SEALS")}


def test_a_shell_built_candidate_goes_out_through_the_shell(harness):
    h = harness
    h.field("_RTHP.SHELL-BUILT", MASK64)
    h.shell_answers("RTE-S-OK")
    assert h.prepare_start() == (h.constant("SCB-S-OK"),)
    assert _counts(h) == {"AR-BUILDS": 0, "AR-PREPARES": 1, "AR-XEMITS": 1,
                          "AR-BASE-STARTS": 0, "AR-FALLBACKS": 0, "AR-SEALS": 1}
    assert h.variable("_RTHP-DIAG-ALONE-REBUILDS") == 0
    assert h.phase() == h.constant("_RTHP-PH-START-SEALED")


def test_a_batch_the_shell_cannot_build_is_offered_again_built_alone(harness):
    h = harness
    h.field("_RTHP.SHELL-BUILT", MASK64)
    h.variable("AR-BUILD-STATUS", h.constant("RTE-S-OK"))
    h.variable("AR-BUILT", MASK64)
    h.shell_answers("RTE-S-UNAVAILABLE", "RTE-S-OK")
    assert h.prepare_start() == (h.constant("SCB-S-OK"),)
    # One build, alone; the shell then builds from that candidate.
    assert _counts(h) == {"AR-BUILDS": 1, "AR-PREPARES": 2, "AR-XEMITS": 1,
                          "AR-BASE-STARTS": 0, "AR-FALLBACKS": 0, "AR-SEALS": 1}
    assert h.variable("AR-ALONE") == MASK64
    assert h.variable("_RTHP-W-ALONE") == 0
    assert h.field("_RTHP.SHELL-BUILT") == 0
    assert h.variable("_RTHP-DIAG-ALONE-REBUILDS") == 1
    assert h.phase() == h.constant("_RTHP-PH-START-SEALED")


def test_a_candidate_the_shell_still_cannot_take_goes_out_alone(harness):
    h = harness
    h.field("_RTHP.SHELL-BUILT", MASK64)
    h.variable("AR-BUILD-STATUS", h.constant("RTE-S-OK"))
    h.variable("AR-BUILT", MASK64)
    h.shell_answers("RTE-S-UNAVAILABLE", "RTE-S-UNAVAILABLE")
    assert h.prepare_start() == (h.constant("SCB-S-OK"),)
    assert _counts(h) == {"AR-BUILDS": 1, "AR-PREPARES": 2, "AR-XEMITS": 0,
                          "AR-BASE-STARTS": 1, "AR-FALLBACKS": 1, "AR-SEALS": 1}
    assert h.variable("_RTHP-DIAG-ALONE-REBUILDS") == 1


def test_a_candidate_built_alone_is_not_built_again(harness):
    h = harness
    h.shell_answers("RTE-S-UNAVAILABLE")
    assert h.prepare_start() == (h.constant("SCB-S-OK"),)
    assert _counts(h) == {"AR-BUILDS": 0, "AR-PREPARES": 1, "AR-XEMITS": 0,
                          "AR-BASE-STARTS": 1, "AR-FALLBACKS": 1, "AR-SEALS": 1}
    assert h.variable("_RTHP-DIAG-ALONE-REBUILDS") == 0


def test_a_draw_that_does_not_fit_even_alone_is_refused(harness):
    h = harness
    h.field("_RTHP.SHELL-BUILT", MASK64)
    h.variable("AR-BUILD-STATUS", h.constant("RTE-S-UNAVAILABLE"))
    h.variable("AR-BUILT", 0)
    h.shell_answers("RTE-S-CAPACITY")
    assert h.prepare_start() == (h.constant("SCB-S-WOULD-BLOCK"),)
    # Nothing is sealed: CELL shows the draw once the empty frame replaces
    # the rich one.
    assert _counts(h) == {"AR-BUILDS": 1, "AR-PREPARES": 1, "AR-XEMITS": 0,
                          "AR-BASE-STARTS": 0, "AR-FALLBACKS": 0, "AR-SEALS": 0}
    assert h.variable("_RTHP-W-ALONE") == 0
    assert h.field("_RTHP.REFUSED-DRAW") == 12
    assert h.phase() == h.constant("_RTHP-PH-READY-BLANK")


@pytest.mark.parametrize("answers,grow,status,prepares,grows", [
    (("RTE-S-OK",), 0, "RTE-S-OK", 1, 0),
    (("RTE-S-CAPACITY", "RTE-S-OK"), MASK64, "RTE-S-OK", 2, 1),
    (("RTE-S-CAPACITY",), 0, "RTE-S-CAPACITY", 1, 1),
    (("RTE-S-CAPACITY", "RTE-S-CAPACITY"), MASK64, "RTE-S-CAPACITY", 2, 1),
    (("RTE-S-UNAVAILABLE",), MASK64, "RTE-S-UNAVAILABLE", 1, 0),
])
def test_a_delta_short_of_engine_storage_is_prepared_again_once_it_grew(
        harness, answers, grow, status, prepares, grows):
    h = harness
    h.shell_answers(*answers)
    h.variable("AR-GROW", grow)
    assert h.delta_status() == h.constant(status)
    assert (h.variable("AR-PREPARES"), h.variable("AR-GROWS")) == (prepares, grows)
    # The staged DELTA is abandoned before the shell prepares it again.
    assert h.variable("AR-XABORTS") == prepares - 1


def test_without_the_shell_the_producer_s_own_delta_needs_no_preparation(harness):
    h = harness
    h.field("_RTHP.EXTENSION", 0)
    assert h.delta_status() == h.constant("RTE-S-OK")
    assert (h.variable("AR-PREPARES"), h.variable("AR-GROWS")) == (0, 0)
