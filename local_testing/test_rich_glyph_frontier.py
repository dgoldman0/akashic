"""Execute the producer's glyph-ID publication fence with a scripted provider.

The real sealed-update state machine, target publication, cancellation, and
frontier arithmetic run on both executors.  Provider completion and packed-bank
admission are explicit fixture seams; their independent validation belongs to
the provider and packed-bank units.  No display or Desktop workload is started.
"""

import re

import pytest

from test_rich_menu_projection_damage import DamageHarness, MASK64, PRODUCER
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


class FrontierHarness(DamageHarness):
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text())
        for relative in ("tui/screen.f", "tui/rich-terminal/residual-glyph-planner.f"):
            source = (ROOT / "akashic" / relative).read_text()
            for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", source):
                self.definitions[match[2]] = match[0]
        for name in ("FP-STATE", "FP-STATUS", "FP-CANCELS", "FP-HEADER", "FP-ENTRIES"):
            self.definitions[name] = f"VARIABLE {name}"
        self.definitions.update({
            "RTE-UPDATE-STATE@": ": RTE-UPDATE-STATE@ DROP FP-STATE @ FP-STATUS @ ;",
            "RTE-RETAINED-CANCEL": ": RTE-RETAINED-CANCEL DROP 1 FP-CANCELS +! RTE-S-OK ;",
            "_RTHP-TARGET-BANK-HEADER?": ": _RTHP-TARGET-BANK-HEADER? 2DROP FP-HEADER @ ;",
            "_RTHP-TARGET-BANK-ENTRIES?": ": _RTHP-TARGET-BANK-ENTRIES? FP-ENTRIES @ ;",
            # The tested DELTA path must never advance the START frontier.
            "_RTHP-ADVANCE-IDS?": ': _RTHP-ADVANCE-IDS? DROP -1 ABORT" unexpected START advance" ;',
        })
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

        for name in ("_RTHP-STEP-SEALED", "_RTHP-TARGET-NEXT-OBJECT?",
                     "_RTHP-PACK-ITEMS-A", "_RTHP-TARGET-PUBLISH?"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        header = self.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
        controls = 2 * (self.constant("RTE-CONTROL-SIZE")
                        + self.constant("RUCP-CORRELATION-SIZE"))
        glyphs = 3 * (self.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
                      + self.constant("RGRP-TEXT-REF-SIZE"))
        self.bank = self.allocate(bytes(header + controls + glyphs))
        self.old_bank = self.allocate(bytes(header))
        for name in ("FP-HEADER", "FP-ENTRIES"):
            self.variable(name, MASK64)
        for suffix, value in (("OWNER", 1), ("COLS", 10), ("ROWS", 4),
                              ("PHYSICAL-GEN", 3), ("REGION", 7),
                              ("FIRST-OBJECT", 100), ("CONTROL-COUNT", 2)):
            self.field(self.producer, "_RTHP." + suffix, value)
            self.field(self.bank, "_RTHP-TB." + suffix, value)
        for producer_field, bank_field, value in (
            ("OWNER-GEN", "GENERATION", 2), ("SURFACE-GEN", "DRAW", 11),
            ("SOURCE-GEN", "SOURCE-GEN", 5),
            ("SOURCE-CONTENT-EPOCH", "CONTENT-EPOCH", 6),
            ("GLYPH-COUNT", "GLYPH-SLOT-COUNT", 3),
        ):
            self.field(self.producer, "_RTHP." + producer_field, value)
            self.field(self.bank, "_RTHP-TB." + bank_field, value)
        self.field(self.producer, "_RTHP.NEXT-OBJECT", 104)
        self.field(self.producer, "_RTHP.TARGET-ACTIVE", self.old_bank)
        self.field(self.producer, "_RTHP.TARGET-PENDING", self.bank)
        self.field(self.producer, "_RTHP.ACTIVE-DRAW", 10)
        self.field(self.producer, "_RTHP.DELTA-PLAN-VALID", MASK64)
        self.field(self.producer, "_RTHP.PHASE", self.constant("_RTHP-PH-DELTA-SEALED"))
        self.field(self.bank, "_RTHP-TB.VALID", self.constant("_RTHP-TARGET-VALID-MAGIC"))
        control_base = self.results("_RTHP-PACK-CONTROLS-A", self.bank)[0]
        for ordinal, identity in enumerate((100, 101)):
            self.field(control_base + ordinal * self.constant("RTE-CONTROL-SIZE"),
                       "_RTE-CONTROL.ID", identity)
        self.items = self.results("_RTHP-PACK-ITEMS-A", self.bank)[0]
        for ordinal, identity in enumerate((102, 103, 104)):
            self.field(self.items + ordinal * self.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE"),
                       "_RTE-LPI.OBJECT", identity)

    def read(self, name):
        return self.runtime.memory.read64(self.producer + self.offset("_RTHP." + name))

    def step(self, state, status="RTE-S-OK"):
        self.variable("FP-STATE", self.constant(state))
        self.variable("FP-STATUS", self.constant(status))
        return self.results("_RTHP-STEP-SEALED", self.constant("_RTHP-PH-LIVE"),
                            self.constant("_RTHP-PH-READY-DELTA"), 0, self.producer)


@pytest.fixture(params=("python", "native"))
def frontier(request):
    return FrontierHarness(request.param)


def test_glyph_frontier_advances_only_after_provider_reports_physical_completion(frontier):
    memory = frontier.runtime.memory
    before = memory.read_bytes(frontier.producer, frontier.constant("RTHP-SIZE"))
    for state, expected in (("RTE-UPDATE-SEALED", (0, 0, MASK64)),
                            ("RTE-UPDATE-PUBLISHING", (0, MASK64, 0)),
                            ("RTE-UPDATE-AWAITING", (0, MASK64, 0))):
        assert frontier.step(state) == expected
        assert memory.read_bytes(frontier.producer, len(before)) == before
    assert frontier.step("RTE-UPDATE-IDLE") == (0, 0, 0)
    assert frontier.read("NEXT-OBJECT") == 105
    assert frontier.read("TARGET-ACTIVE") == frontier.bank
    assert frontier.read("TARGET-PENDING") == 0
    assert frontier.read("ACTIVE-DRAW") == 11
    assert frontier.read("DELTA-PLAN-VALID") == 0


def test_stale_sealed_growth_cancels_without_consuming_candidate_ids(frontier):
    assert frontier.step("RTE-UPDATE-SEALED", "RTE-S-STALE") == (0, 0, MASK64)
    assert frontier.value("FP-CANCELS") == 1
    assert frontier.read("NEXT-OBJECT") == 104
    assert frontier.read("TARGET-ACTIVE") == frontier.old_bank
    assert frontier.read("TARGET-PENDING") == 0
    assert frontier.read("ACTIVE-DRAW") == 10
    assert frontier.read("PHASE") == frontier.constant("_RTHP-PH-READY-DELTA")
    assert frontier.runtime.memory.read64(frontier.bank + frontier.offset("_RTHP-TB.VALID")) == 0


@pytest.mark.parametrize("refusal", ("header", "entries", "draw", "zero-id", "wrap-id"))
def test_failed_publication_does_not_consume_glyph_ids(frontier, refusal):
    if refusal in ("header", "entries"):
        frontier.variable("FP-" + refusal.upper(), 0)
    elif refusal == "draw":
        frontier.field(frontier.bank, "_RTHP-TB.DRAW", 12)
    else:
        frontier.field(frontier.items + 2 * frontier.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE"),
                       "_RTE-LPI.OBJECT", 0 if refusal == "zero-id" else MASK64)
    status, more, output = frontier.step("RTE-UPDATE-IDLE")
    assert status == frontier.constant("SCB-S-INVALID") and (more, output) == (0, 0)
    assert frontier.read("NEXT-OBJECT") == 104
    assert frontier.read("TARGET-ACTIVE") == frontier.old_bank
    assert frontier.read("ACTIVE-DRAW") == 10


def test_frontier_derivation_is_read_only_and_never_moves_backwards(frontier):
    frontier.field(frontier.producer, "_RTHP.NEXT-OBJECT", 109)
    frontier.variable("_RTHP-TP-P", frontier.producer)
    frontier.variable("_RTHP-TP-BANK", frontier.bank)
    before = frontier.runtime.memory.read_bytes(frontier.producer, frontier.constant("RTHP-SIZE"))
    assert frontier.call("_RTHP-TARGET-NEXT-OBJECT?")
    assert frontier.value("_RTHP-TP-NEXT-OBJECT") == 109
    assert frontier.runtime.memory.read_bytes(frontier.producer, len(before)) == before


def test_spatial_glyph_order_does_not_determine_the_published_frontier(frontier):
    # Slot normalization orders glyphs by geometry; ID order may differ.
    frontier.field(frontier.items, "_RTE-LPI.OBJECT", 110)
    item_bytes = 3 * frontier.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
    before = frontier.runtime.memory.read_bytes(frontier.items, item_bytes)
    assert frontier.step("RTE-UPDATE-IDLE") == (0, 0, 0)
    assert frontier.read("NEXT-OBJECT") == 111
    assert frontier.runtime.memory.read_bytes(frontier.items, item_bytes) == before
