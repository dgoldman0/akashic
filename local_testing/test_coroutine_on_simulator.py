#!/usr/bin/env python3
"""coroutine.f's checks on MegaPad's simulator.

test_coroutine.py runs coroutine.f's structured wrappers and the BIOS's
cooperative task words on the emulator, whose BIOS switches between the
foreground and three background slots through SEP R20. MegaPad's simulator
runs the same slots as contexts of core 0 (MegaPad's simulator/tasks.py,
stage 5 of its docs/multicore-simulator-plan.md). Here every check of
test_coroutine.py runs on the simulator instead, each on a fresh machine
with KDOS, coroutine.f and the suite's helpers, as each runs on a fresh
emulator there, and must print what the suite expects of the emulator. The
checks and their expectations come from test_coroutine.py itself, so the
two machines answer the same suite.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from forth_snapshot import transcript_checks  # noqa: E402
from native_forth import NativeForth  # noqa: E402


def _emulator_suite():
    """test_coroutine.py as a module of its own name, so that its checks can
    be bound to the simulator without touching the suite pytest collects."""

    spec = importlib.util.spec_from_file_location(
        "_coroutine_emulator_suite", LOCAL_TESTING / "test_coroutine.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


EMULATOR_SUITE = _emulator_suite()
MACHINE = NativeForth(
    ("concurrency/coroutine.f",),
    prelude=tuple(EMULATOR_SUITE.HELPERS),
    external_size=16 << 20,
)


def run_forth(lines: list[str], max_steps: int = 50_000_000) -> str:
    return MACHINE.run(lines, max_steps).decode("latin-1")


CHECK, _CHECK_FN, _CHECK_EMITTED = transcript_checks(run_forth)
CASES = tuple(
    name for name, value in vars(EMULATOR_SUITE).items()
    if name.startswith("test_") and callable(value)
)


def test_the_emulator_suite_s_checks_are_found():
    assert "test_raw_bios_round_robin_across_three_slots" in CASES
    assert "test_with_background" in CASES
    assert "test_stack_preservation_across_pause" in CASES


@pytest.mark.parametrize("name", CASES)
def test_the_coroutine_check_passes_on_the_simulator(name, monkeypatch):
    monkeypatch.setattr(EMULATOR_SUITE, "check", CHECK)
    getattr(EMULATOR_SUITE, name)()
