#!/usr/bin/env python3
"""Shared harness for akashic/numeric tests.

A test places arrays and workspaces in a test arena (HBW or external RAM),
runs Forth lines against a snapshot of the numeric modules, and reads the
results back.  Each placed span is followed by a canary tile, so a write
out of bounds fails the run, and every run must leave the stack empty.

Run with MEGAPAD_ROOT pointing at a MegaPad checkout with FP32/FP64 tile
formats (docs/numeric/scientific-computing-plan.md, "MegaPad binding").
"""

from __future__ import annotations

import random
import re
import struct

import numeric_reference as ref
from forth_snapshot import ForthSnapshot, program_output


HBW_ARENA = 1 << 20
XMEM_ARENA = 4 << 20
ARENAS = {"hbw": HBW_ARENA, "xmem": XMEM_ARENA}
CANARY = bytes([0xA5]) * 64

NUM_OK, E_FORMAT, E_SHAPE, E_ALIGN, E_SPACE, E_RANGE, E_OVERLAP = range(7)

PRELUDE = (
    f"HBW-TALIGN {HBW_ARENA} HBW-ALLOT CONSTANT T-HBW",
    f"{XMEM_ARENA} 64 + XMEM-ALLOT 63 + -64 AND CONSTANT T-XMEM",
    "CREATE T-DESC 16 NARR-SIZE * ALLOT",
    ": T-ARR ( i -- arr ) NARR-SIZE * T-DESC + ;",
    "CREATE T-WS NWS-SIZE ALLOT",
    ': T-R ( bits status -- ) ." @R:" . HEX U. DECIMAL CR ;',
    ': T-S ( status -- ) ." @S:" . CR ;',
    ': T-D ( -- ) ." @D:" DEPTH . CR ;',
)

# Machines whose closure includes numeric/team.f can also hold a team.
TEAM_ARENA = 256 << 10
TEAM_PRELUDE = (
    "CREATE T-TEAM NTEAM-SIZE ALLOT",
    f"HBW-TALIGN {TEAM_ARENA} HBW-ALLOT CONSTANT T-TEAM-MEM",
)


def team_init(cores: int, ws_bytes: int) -> str:
    """Forth that carves T-TEAM from T-TEAM-MEM and prints the status."""

    return f"T-TEAM-MEM {TEAM_ARENA} {cores} {ws_bytes} T-TEAM NTEAM-INIT T-S"


RECORD = re.compile(r"@([RSD]):(-?\d+) (?:([0-9A-F]+) )?")


class NumericMachine:
    """A snapshot of numeric modules with the test arenas allocated."""

    def __init__(
        self,
        roots: tuple[str, ...],
        prelude: tuple[str, ...] = (),
        num_cores: int = 1,
    ) -> None:
        self.snapshot = ForthSnapshot(roots, prelude=PRELUDE + prelude, num_cores=num_cores)
        self._regions: dict[str, int] = {}

    def region(self, name: str) -> int:
        if not self._regions:
            lines = ["T-HBW U. T-XMEM U."]
            text = program_output(self.snapshot.run(lines), lines)
            hbw, xmem = (int(value) for value in re.findall(r"\d+", text)[:2])
            self._regions.update(hbw=hbw, xmem=xmem)
        return self._regions[name]

    def program(self, where: str = "hbw") -> "Program":
        return Program(self, where)


class Program:
    """Place data in the test arenas, run Forth lines, and read results back.

    Spans go to the program's arena, "hbw" or "xmem", unless a call names
    the other one.
    """

    def __init__(self, machine: NumericMachine, where: str) -> None:
        self.machine = machine
        self.where = where
        self.base = machine.region(where)
        self.cursors = {name: machine.region(name) for name in ARENAS}
        self.lines: list[str] = []
        self.writes: list[tuple[int, bytes]] = []
        self.canaries: list[int] = []
        self.reads: dict[str, tuple[int, int]] = {}
        self.slots = 0

    def reserve(self, nbytes: int, data: bytes | None = None, where: str | None = None) -> int:
        where = where or self.where
        addr = self.cursors[where]
        canary = addr + -(-nbytes // 64) * 64
        self.writes.append((addr, data if data is not None else bytes(nbytes)))
        self.writes.append((canary, CANARY))
        self.canaries.append(canary)
        self.cursors[where] = canary + 64
        limit = self.machine.region(where) + ARENAS[where]
        assert self.cursors[where] <= limit, "test arena too small"
        return addr

    def array(self, arr: ref.Array, name: str | None = None, where: str | None = None) -> str:
        """Place arr, describe it in the next descriptor, return its name."""

        addr = self.reserve(arr.nbytes, arr.to_bytes(), where)
        return self.describe(addr, arr, name)

    def describe(self, addr: int, arr: ref.Array, name: str | None = None) -> str:
        """Describe storage already placed at addr as arr's shape."""

        slot = self.slots
        self.slots += 1
        self.lines.append(f"{addr} {arr.nx} {arr.ny} {arr.fmt} {slot} T-ARR NARR-INIT T-S")
        if name is not None:
            self.reads[name] = (addr, arr.nbytes)
        return f"{slot} T-ARR"

    def workspace(self, nbytes: int, where: str | None = None) -> str:
        addr = self.reserve(nbytes, where=where)
        self.lines.append(f"{addr} {nbytes} T-WS NWS-INIT T-S")
        return "T-WS"

    def run(self) -> tuple[list[tuple[str, int, int | None]], dict[str, bytes]]:
        captured: dict[str, bytes] = {}
        canaries: list[bytes] = []
        lines = self.lines + ["T-D"]

        def setup(system) -> None:
            for addr, data in self.writes:
                system._raw_mem_write_span(addr, data)

        def inspect(system) -> None:
            for name, (addr, nbytes) in self.reads.items():
                captured[name] = system._raw_mem_read_span(addr, nbytes)
            canaries.extend(system._raw_mem_read_span(addr, 64) for addr in self.canaries)

        output = self.machine.snapshot.run(lines, setup=setup, inspect=inspect)
        text = program_output(output, lines)
        records = [
            (kind, int(value), int(bits, 16) if bits else None)
            for kind, value, bits in RECORD.findall(text)
        ]
        assert records and records[-1] == ("D", 0, None), f"stack not empty:\n{text[-600:]}"
        assert all(canary == CANARY for canary in canaries), "a kernel wrote outside its bounds"
        return records[:-1], captured


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

def specials(f) -> list[int]:
    return [
        0,                                   # +0
        f.sign_bit,                          # -0
        1,                                   # smallest subnormal
        f.fraction_mask,                     # largest subnormal
        1 << f.fraction_bits,                # smallest normal
        f.max_finite,
        f.sign_bit | f.max_finite,
        f.infinity,
        f.sign_bit | f.infinity,
        f.canonical_nan,
        f.infinity | 1,                      # signalling NaN
        f.sign_bit | f.canonical_nan | 5,    # negative NaN with a payload
    ]


def random_lane(rng: random.Random, f, special: float) -> int:
    if rng.random() < special:
        return rng.choice(specials(f))
    exponent = f.bias + rng.randint(-24, 24)
    return (rng.getrandbits(1) << (f.width - 1)) | (exponent << f.fraction_bits) | rng.getrandbits(f.fraction_bits)


def random_array(rng: random.Random, fmt: int, nx: int, ny: int, special: float = 0.0) -> ref.Array:
    """Real lanes from random_lane; padding lanes are arbitrary bits."""

    arr = ref.Array(fmt, nx, ny, [])
    f = arr.format
    arr.lanes = [
        random_lane(rng, f, special) if (index % arr.row_lanes) < nx else rng.getrandbits(f.width)
        for index in range(arr.row_lanes * ny)
    ]
    return arr


def array_of(fmt: int, nx: int, ny: int, values) -> ref.Array:
    """An array whose real lanes are values(i, j) as floats and padding +0."""

    arr = ref.Array(fmt, nx, ny, [])
    arr.lanes = [
        scalar(fmt, values(index // arr.row_lanes, index % arr.row_lanes))
        if index % arr.row_lanes < nx else 0
        for index in range(arr.row_lanes * ny)
    ]
    return arr


def scalar(fmt: int, value: float) -> int:
    if fmt == ref.FP64:
        return struct.unpack("<Q", struct.pack("<d", value))[0]
    return struct.unpack("<I", struct.pack("<f", value))[0]


def as_array(like: ref.Array, data: bytes) -> ref.Array:
    return ref.Array.from_bytes(like.fmt, like.nx, like.ny, data)


def real_values(arr: ref.Array) -> list[list[float]]:
    """The real lanes as host floats, row by row."""

    f = arr.format
    return [
        [ref.fp.to_double(f, arr.lanes[i * arr.row_lanes + j]) for j in range(arr.nx)]
        for i in range(arr.ny)
    ]
