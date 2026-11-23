#!/usr/bin/env python3
"""par.f's combinators over full cores, on the emulator and the simulator.

PAR-MAP, PAR-REDUCE and PAR-FOR divide their work among the full cores:
core 0 takes the first chunk, the other cores receive theirs through
CORE-RUN, and BARRIER waits for them (akashic/concurrency/par.f).
test_par.py runs them on one core, where they run in order. Here they run
on two and four full cores of the emulator, whose cores run in lock-step,
and of MegaPad's simulator, whose cores run in rounds, and each case must
print the sequential result on both. The cases write disjoint cells or
combine each core's own result; test_par.py's accumulation into one
shared variable is left out, since its cores race on it.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys

import pytest

AKASHIC_ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", AKASHIC_ROOT.parent / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402

EVENT_F = AKASHIC_ROOT / "akashic" / "concurrency" / "event.f"
PAR_F = AKASHIC_ROOT / "akashic" / "concurrency" / "par.f"
EXTERNAL_MIB = 16
_BETWEEN = re.compile(rb"<<(.*?)>>", re.S)

HELPERS = [
    "CREATE _ARR 8 CELLS ALLOT",
    "CREATE _ARR2 16 CELLS ALLOT",
    "CREATE _BIG 64 CELLS ALLOT",
    ": _DOUBLE 2 * ;",
    ": _ADD + ;",
    ": _MAX MAX ;",
    ": _FOR-SQ DUP DUP * SWAP CELLS _ARR2 + ! ;",
]

# name: (the case's definition, what it prints)
CASES = {
    "map-4": (
        ": _T 1 _ARR ! 2 _ARR CELL+ ! 3 _ARR 2 CELLS + ! 4 _ARR 3 CELLS + ! "
        "['] _DOUBLE _ARR 4 PAR-MAP "
        "_ARR @ . _ARR CELL+ @ . _ARR 2 CELLS + @ . _ARR 3 CELLS + @ . ;",
        b"2 4 6 8 ",
    ),
    "map-64": (
        ": _T 64 0 DO I 1+ I CELLS _BIG + ! LOOP ['] _DOUBLE _BIG 64 PAR-MAP "
        "_BIG @ . _BIG 63 CELLS + @ . ;",
        b"2 128 ",
    ),
    "reduce-8": (
        ": _T 8 0 DO I 1+ I CELLS _ARR + ! LOOP ['] _ADD 0 _ARR 8 PAR-REDUCE . ;",
        b"36 ",
    ),
    "reduce-max": (
        ": _T 5 _ARR ! 99 _ARR CELL+ ! 3 _ARR 2 CELLS + ! 42 _ARR 3 CELLS + ! "
        "['] _MAX 0 _ARR 4 PAR-REDUCE . ;",
        b"99 ",
    ),
    "reduce-64": (
        ": _T 64 0 DO I 1+ I CELLS _BIG + ! LOOP ['] _ADD 0 _BIG 64 PAR-REDUCE . ;",
        b"2080 ",
    ),
    "for-8": (
        ": _T ['] _FOR-SQ 0 8 PAR-FOR 8 0 DO I CELLS _ARR2 + @ . LOOP ;",
        b"0 1 4 9 16 25 36 49 ",
    ),
}
RUN = ": _RUN 60 EMIT 60 EMIT _T 62 EMIT 62 EMIT ;"


def _forth_lines(path: Path) -> list[str]:
    lines = []
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("\\"):
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        lines.append(line)
    return lines


def _payload() -> list[str]:
    kdos = _forth_lines(MEGAPAD_ROOT / "kdos.f")
    return kdos + ["ENTER-USERLAND"] + _forth_lines(EVENT_F) + _forth_lines(PAR_F) + HELPERS


def _printed(output: bytes) -> bytes:
    found = _BETWEEN.search(output)
    assert found is not None, output[-600:]
    return found.group(1)


class _Emulator:
    def __init__(self, cores: int) -> None:
        self.system = MegapadSystem(
            ram_size=1 << 20, num_cores=cores, num_clusters=0,
            ext_mem_size=EXTERNAL_MIB << 20,
        )
        self._sent = bytearray()
        self.system.uart.on_tx = self._sent.append
        self.system.load_binary(0, assemble((MEGAPAD_ROOT / "bios.asm").read_text()))
        self.system.boot()
        self._type(_payload(), step_limit=800_000_000)

    def _type(self, lines: list[str], *, step_limit: int = 100_000_000) -> bytes:
        data = "".join(line + "\n" for line in lines).encode()
        start = len(self._sent)
        position = steps = 0
        system = self.system
        while steps < step_limit:
            if system.cpu.halted:
                break
            if system.cpu.idle and not system.uart.has_rx_data:
                if position >= len(data):
                    break
                end = data.find(b"\n", position) + 1 or len(data)
                system.uart.inject_input(data[position:end])
                position = end
                continue
            steps += max(system.run_batch(100_000), 1)
        assert position == len(data), "the emulator did not take every line"
        return bytes(self._sent[start:])

    def run(self, definition: str) -> bytes:
        return _printed(self._type([definition, RUN, "_RUN"]))


class _Simulator:
    def __init__(self, cores: int) -> None:
        from simulator.platform import Topology, create_address_space
        from simulator.runtime import MegaForthRuntime

        memory = create_address_space(
            topology=Topology(full_cores=cores), bank0_size=1 << 20,
            external_size=EXTERNAL_MIB << 20,
        )
        self.runtime = MegaForthRuntime(memory=memory)
        self.runtime.evaluate("\n".join(_payload()).encode())
        self.runtime.drain_uart_output()

    def run(self, definition: str) -> bytes:
        self.runtime.evaluate(f"{definition}\n{RUN}\n_RUN".encode())
        return _printed(bytes(self.runtime.drain_uart_output()))


@pytest.fixture(scope="module")
def machines():
    built = {}

    def machine(kind: str, cores: int):
        if (kind, cores) not in built:
            built[kind, cores] = (_Emulator if kind == "emulator" else _Simulator)(cores)
        return built[kind, cores]

    return machine


@pytest.mark.parametrize("cores", (2, 4))
@pytest.mark.parametrize("name", tuple(CASES))
def test_the_combinator_gives_the_sequential_result_on_both_machines(machines, cores, name):
    definition, expected = CASES[name]
    assert machines("simulator", cores).run(definition) == expected
    assert machines("emulator", cores).run(definition) == expected
