"""Execute the production DELTA control join on bounded, seeded guest banks.

Only the real helper's source dependencies are compiled.  This does not boot
Desktop or replace the join with a Python implementation.  The harness also
accepts a prior producer source for a sequential semantic-step comparison.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import struct
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
PRODUCER = ROOT / "akashic/tui/rich-terminal/hybrid-screen-producer.f"
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", ROOT.parent / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from simulator.runtime import MegaForthRuntime  # noqa: E402


# Each case is a bounded helper call, with the existing CELL-fixture watchdog.
MAPPING_STEP_BUDGET = 3_000_000
MASK64 = (1 << 64) - 1


def _definitions(producer_source: str) -> dict[str, str]:
    texts = [producer_source]
    for relative in (
        "tui/rich-terminal/engine.f",
        "tui/rich-terminal/uidl-control-planner.f",
        "tui/rich-terminal/uidl-instrument-planner.f",
        "utils/memory-span.f",
        "utils/uint-range.f",
    ):
        texts.append((ROOT / "akashic" / relative).read_text())
    declarations: dict[str, str] = {}
    for text in texts:
        # A prose semicolon at the end of a line comment is not a definition
        # terminator. Remove comments before finding complete helper bodies.
        text = re.sub(r"(?m)\\[^\n]*$", "", text)
        for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;[ \t]*(?:\\[^\n]*)?$", text):
            declarations[match[1]] = match[0]
        for match in re.finditer(r"(?m)^VARIABLE (\S+)\s*$", text):
            declarations[match[1]] = match[0]
        for match in re.finditer(
            r"(?m)^\s*(-?(?:0x[0-9A-Fa-f]+|[0-9]+))\s+CONSTANT\s+(\S+)",
            text,
        ):
            declarations[match[2]] = match[0]
    return declarations


def control_map_source(producer_source: str) -> bytes:
    """Return the unchanged, dependency-ordered production word closure."""
    declarations = _definitions(producer_source)
    emitted: set[str] = set()
    chunks: list[str] = []

    def include(name: str) -> None:
        if name in emitted:
            return
        emitted.add(name)
        declaration = declarations[name]
        code = re.sub(r"\\[^\n]*", "", declaration)
        code = re.sub(r"\([^)]*\)", "", code)
        for token in code.split():
            if token != name and token in declarations:
                include(token)
        chunks.append(declaration)

    include("_RTHP-D-BUILD-CONTROL-MAP?")
    return "\n".join(chunks).encode("ascii")


class ControlMapHarness:
    def __init__(self, producer_source: str | None = None, *, backend="native"):
        self.source = PRODUCER.read_text() if producer_source is None else producer_source
        self.declarations = _definitions(self.source)
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.runtime.evaluate(
            control_map_source(self.source),
            source_name="production-control-map-closure.f",
            step_budget=MAPPING_STEP_BUDGET,
        )
        self.serial = 0

    def constant(self, name: str) -> int:
        return int(self.declarations[name].split()[0], 0)

    def offset(self, name: str) -> int:
        definition = self.declarations[name]
        match = re.search(r"\([^)]*--[^)]*\)\s*(?:(\d+)\s+\+)?\s*;", definition)
        assert match is not None, name
        return int(match[1] or 0)

    def _allocate(self, size: int) -> int:
        self.serial += 1
        word = self.runtime.define_created(
            f"CM-BUFFER-{self.serial}", initial_body=bytes(size + 7)
        )
        return (word.body_address + 7) & -8

    def _set_variable(self, name: str, value: int) -> None:
        word = self.runtime.dictionary.find(name.encode())
        assert word is not None, name
        self.runtime.memory.write64(word.body_address, value)

    def _bank(self, ids, correlations) -> tuple[int, int]:
        assert len(ids) == len(correlations)
        header = self.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
        control_size = self.constant("RTE-CONTROL-SIZE")
        correlation_size = self.constant("RUCP-CORRELATION-SIZE")
        size = header + len(ids) * (control_size + correlation_size)
        address = self._allocate(size)
        memory = self.runtime.memory
        memory.write64(address + self.offset("_RTHP-TB.CONTROL-COUNT"), len(ids))
        for ordinal, object_id in enumerate(ids):
            memory.write64(
                address + header + ordinal * control_size + self.offset("_RTE-CONTROL.ID"),
                object_id,
            )
        for ordinal, (identity, object_id) in enumerate(correlations):
            assert len(identity) == 6
            cells = (*identity[:4], object_id, *identity[4:])
            memory.write_bytes(
                address + header + len(ids) * control_size + ordinal * correlation_size,
                struct.pack("<7Q", *cells),
            )
        return address, size

    def run(self, active_ids, active_correlations, pending_ids, pending_correlations,
            *, first=1001, workspace_bytes=None, arena_bytes=None):
        active, active_size = self._bank(active_ids, active_correlations)
        pending, pending_size = self._bank(pending_ids, pending_correlations)
        required = len(pending_ids) * 24
        capacity = required if workspace_bytes is None else workspace_bytes
        scratch = self._allocate(required + 16)
        producer = self._allocate(4096)
        memory = self.runtime.memory
        # Sentinels immediately outside the admitted scratch span catch writes
        # beyond an exact caller bound, including a one-byte-short rejection.
        memory.write64(scratch, 0x0123456789ABCDEF)
        memory.write64(scratch + 8 + required, 0xFEDCBA9876543210)
        scratch += 8
        for field, value in (
            ("_RTHP.ORDER2-A", scratch), ("_RTHP.ORDER2-U", capacity),
            ("_RTHP.ARENA-A", scratch),
            ("_RTHP.ARENA-U", required if arena_bytes is None else arena_bytes),
        ):
            memory.write64(producer + self.offset(field), value)
        for name, value in (
            ("_RTHP-D-P", producer), ("_RTHP-D-ACTIVE", active),
            ("_RTHP-D-PENDING", pending), ("_RTHP-D-PENDING-FIRST", first),
        ):
            self._set_variable(name, value)
        before_banks = (memory.read_bytes(active, active_size), memory.read_bytes(pending, pending_size))
        before_native = self.runtime.native_execution_stats["semantic_steps"]
        result = self.runtime.execute(
            "_RTHP-D-BUILD-CONTROL-MAP?", step_budget=MAPPING_STEP_BUDGET
        )
        assert self.runtime.main_context.data.depth() == 1
        accepted = self.runtime.main_context.data.pop() == MASK64
        assert self.runtime.main_context.returns.snapshot() == ()
        assert before_banks == (
            memory.read_bytes(active, active_size), memory.read_bytes(pending, pending_size)
        ), "mapping must never normalize or mutate either source bank"
        assert memory.read64(scratch - 8) == 0x0123456789ABCDEF
        assert memory.read64(scratch + required) == 0xFEDCBA9876543210
        mapping = tuple(memory.read64(scratch + 8 * i) for i in range(len(pending_ids)))
        if self.runtime.execution_backend == "native":
            assert self.runtime.native_execution_stats["semantic_steps"] > before_native
        return accepted, mapping, result.semantic_steps


def _identity(index: int) -> tuple[int, ...]:
    return (7, 3, 0, index, 4, 100)


@pytest.fixture
def harness():
    pytest.importorskip("_megaforth_native")
    return ControlMapHarness()


def test_control_map_executes_reordered_id_and_semantic_joins(harness):
    a, b, c, new = (_identity(i) for i in range(4))
    accepted, mapping, _ = harness.run(
        (43, 41, 42), ((a, 41), (c, 43), (b, 42)),
        (1001, 1002, 1003, 1004), ((new, 1002), (a, 1004), (b, 1001), (c, 1003)),
    )
    assert accepted and mapping == (3, 0, 1, 2)


@pytest.mark.parametrize("field", range(6))
def test_control_map_keeps_every_identity_field_and_all_64_bits(harness, field):
    a = list(_identity(1))
    b = a.copy()
    b[field] ^= 1 << 63
    accepted, mapping, _ = harness.run(
        (41, 42), ((tuple(a), 42), (tuple(b), 41)),
        (1001, 1002), ((tuple(b), 1002), (tuple(a), 1001)),
    )
    assert accepted and mapping == (2, 1)


@pytest.mark.parametrize("defect", (
    "active_id_duplicate", "active_id_zero", "active_id_fresh", "active_correlation_id",
    "active_identity", "pending_id", "pending_correlation_id", "pending_identity",
    "missing_active", "short_workspace", "short_arena", "wrapped_pending_id",
))
def test_control_map_rejects_invalid_bijections_and_bounds_without_bank_writes(harness, defect):
    a, b, c, other = (_identity(i) for i in range(4))
    active_ids, pending_ids = [41, 42], [1001, 1002, 1003]
    active, pending = [(a, 41), (b, 42)], [(c, 1002), (b, 1001), (a, 1003)]
    options = {}
    if defect == "active_id_duplicate": active_ids[1] = 41
    elif defect == "active_id_zero": active_ids[0] = 0
    elif defect == "active_id_fresh": active_ids[0] = 1001
    elif defect == "active_correlation_id": active[1] = (b, 41)
    elif defect == "active_identity": active[1] = (a, 42)
    elif defect == "pending_id": pending_ids[1] = 1001
    elif defect == "pending_correlation_id": pending[1] = (b, 1002)
    elif defect == "pending_identity": pending[0] = (a, 1002)
    elif defect == "missing_active": pending[1] = (other, 1001)
    elif defect == "short_workspace": options["workspace_bytes"] = 24 * 3 - 1
    elif defect == "short_arena": options["arena_bytes"] = 24 * 3 - 1
    elif defect == "wrapped_pending_id": options["first"] = MASK64
    accepted, _, _ = harness.run(active_ids, active, pending_ids, pending, **options)
    assert not accepted


def test_control_map_accepts_empty_banks_and_all_new_controls(harness):
    assert harness.run((), (), (), ())[0]
    accepted, mapping, _ = harness.run((), (), (1001,), ((_identity(1), 1001),))
    assert accepted and mapping == (0,)


def control_map_scaling_case(count: int):
    """Reverse graph order and permute correlations independently of identity."""
    active_ids = tuple(41 + 2 * i for i in range(count))
    active = tuple((_identity(i), active_ids[i]) for i in reversed(range(count)))
    pending_ids = tuple(1001 + i for i in range(count))
    pending = tuple((_identity(count - 1 - i), pending_ids[i]) for i in range(count))
    return active_ids, active, pending_ids, pending[1:] + pending[:1]


def test_control_map_semantic_work_scales_below_pairwise_scanning(harness):
    steps = []
    for count in (32, 64, 128):
        accepted, mapping, work = harness.run(*control_map_scaling_case(count))
        assert accepted and mapping == tuple(range(count, 0, -1))
        steps.append(work)
    # Doubling an n log n join remains well below the fourfold pairwise cost.
    assert all(later < earlier * 3 for earlier, later in zip(steps, steps[1:]))
