#!/usr/bin/env python3
"""The snapshot harness stops a machine that no longer makes progress.

After an unhandled trap, MegaPad core 0 can park with console input it never
reads.  Each batch then runs only a few instructions, so a step budget alone
would take hours to run out.  These tests drive the harness loop with a fake
machine; no emulator is booted.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

import forth_snapshot
from forth_snapshot import MachineStalled, _run_input


class FakeMachine:
    """Core 0 consumes a line after ``work`` batches, each ``per_batch`` long."""

    def __init__(self, per_batch: int, work: int = 3) -> None:
        self.cpu = SimpleNamespace(halted=False, idle=True, pc=0x1D, ivec_id=2)
        self.uart = SimpleNamespace(has_rx_data=False, inject_input=self._inject)
        self.per_batch = per_batch
        self.work = work
        self.remaining = 0
        self.batches = 0

    def _inject(self, chunk: bytes) -> None:
        self.uart.has_rx_data = True
        self.cpu.idle = False
        self.remaining = self.work

    def run_batch(self, limit: int) -> int:
        self.batches += 1
        if self.per_batch >= forth_snapshot._STALL_INSTRUCTIONS:
            self.remaining -= 1
            if self.remaining <= 0:
                self.uart.has_rx_data = False
                self.cpu.idle = True
        return min(self.per_batch, limit)


def test_a_working_machine_consumes_its_input() -> None:
    machine = FakeMachine(per_batch=50_000)
    steps = _run_input(machine, b"one\ntwo\n", 10_000_000)
    assert steps == 2 * 3 * 50_000
    assert machine.cpu.idle and not machine.uart.has_rx_data


def test_a_parked_machine_is_reported_instead_of_running_out_its_budget() -> None:
    machine = FakeMachine(per_batch=2)
    output = bytearray(b"Megapad-64 Forth BIOS v1.0\r\n")
    with pytest.raises(MachineStalled, match=r"pc=0x1d idle=False last vector=2"):
        _run_input(machine, b"line\nmore\n", 3_000_000_000, output)
    assert machine.batches == forth_snapshot._STALL_BATCHES
