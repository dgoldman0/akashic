#!/usr/bin/env python3
"""Numeric arrays and level-1 kernels: akashic/numeric/array.f and blas1.f.

Every kernel result is compared bit for bit with numeric_reference.py,
which computes the documented definitions with MegaPad's exact IEEE oracle.
Each array and workspace is followed by a canary tile, so a write outside
its bounds fails the test, and every program must leave the stack empty.

Run with MEGAPAD_ROOT pointing at a MegaPad checkout with FP32/FP64 tile
formats (docs/numeric/scientific-computing-plan.md, "MegaPad binding").
"""

from __future__ import annotations

import random
import re
import struct

import pytest

import numeric_reference as ref
from forth_snapshot import ForthSnapshot, program_output


HBW_ARENA = 1 << 20
XMEM_ARENA = 4 << 20
CANARY = bytes([0xA5]) * 64

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
SNAPSHOT = ForthSnapshot(("numeric/blas1.f",), prelude=PRELUDE)

NUM_OK, E_FORMAT, E_SHAPE, E_ALIGN, E_SPACE = 0, 1, 2, 3, 4
RECORD = re.compile(r"@([RSD]):(-?\d+) (?:([0-9A-F]+) )?")

_regions: dict[str, int] = {}


def region(name: str) -> int:
    if not _regions:
        lines = ["T-HBW U. T-XMEM U."]
        text = program_output(SNAPSHOT.run(lines), lines)
        hbw, xmem = (int(value) for value in re.findall(r"\d+", text)[:2])
        _regions.update(hbw=hbw, xmem=xmem)
    return _regions[name]


class Program:
    """Place data in one region, run Forth lines, and read results back."""

    def __init__(self, where: str = "hbw") -> None:
        self.base = region(where)
        self.limit = self.base + (HBW_ARENA if where == "hbw" else XMEM_ARENA)
        self.cursor = self.base
        self.lines: list[str] = []
        self.writes: list[tuple[int, bytes]] = []
        self.canaries: list[int] = []
        self.reads: dict[str, tuple[int, int]] = {}
        self.slots = 0

    def reserve(self, nbytes: int, data: bytes | None = None) -> int:
        addr = self.cursor
        self.cursor += -(-nbytes // 64) * 64
        self.writes.append((addr, data if data is not None else bytes(nbytes)))
        self.writes.append((self.cursor, CANARY))
        self.canaries.append(self.cursor)
        self.cursor += 64
        assert self.cursor <= self.limit, "test arena too small"
        return addr

    def array(self, arr: ref.Array, name: str | None = None) -> str:
        """Place arr, describe it in the next descriptor, return its name."""

        addr = self.reserve(arr.nbytes, arr.to_bytes())
        slot = self.slots
        self.slots += 1
        self.lines.append(f"{addr} {arr.nx} {arr.ny} {arr.fmt} {slot} T-ARR NARR-INIT T-S")
        if name is not None:
            self.reads[name] = (addr, arr.nbytes)
        return f"{slot} T-ARR"

    def workspace(self, nbytes: int) -> str:
        addr = self.reserve(nbytes)
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

        text = program_output(SNAPSHOT.run(lines, setup=setup, inspect=inspect), lines)
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

def _specials(f) -> list[int]:
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
        return rng.choice(_specials(f))
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


def scalar(fmt: int, value: float) -> int:
    if fmt == ref.FP64:
        return struct.unpack("<Q", struct.pack("<d", value))[0]
    return struct.unpack("<I", struct.pack("<f", value))[0]


def as_array(like: ref.Array, data: bytes) -> ref.Array:
    return ref.Array.from_bytes(like.fmt, like.nx, like.ny, data)


# ---------------------------------------------------------------------------
# Kernels against the reference
# ---------------------------------------------------------------------------

SHAPES = {
    ref.FP64: [(1, 1), (5, 1), (8, 1), (9, 1), (13, 3), (64, 5), (300, 1), (257, 9), (1000, 20)],
    ref.FP32: [(1, 1), (7, 1), (16, 1), (17, 1), (13, 3), (64, 5), (600, 1), (257, 9), (2000, 40)],
}
CASES = [
    (fmt, nx, ny, special)
    for fmt in (ref.FP64, ref.FP32)
    for nx, ny in SHAPES[fmt]
    for special in (0.0, 0.08)
    if not (special and nx * ny > 20_000)
]


def _where(fmt: int, nx: int, ny: int) -> str:
    return "xmem" if ref.storage_bytes(fmt, nx, ny) * 9 > HBW_ARENA else "hbw"


@pytest.mark.parametrize("fmt,nx,ny,special", CASES)
def test_kernels_match_the_reference(fmt: int, nx: int, ny: int, special: float) -> None:
    rng = random.Random(f"{fmt}-{nx}-{ny}-{special}")
    x = random_array(rng, fmt, nx, ny, special)
    y = random_array(rng, fmt, nx, ny, special)
    s = scalar(fmt, -1.75)

    program = Program(_where(fmt, nx, ny))
    X = program.array(x)
    Y = program.array(y)
    outputs = {name: program.array(random_array(rng, fmt, nx, ny), name)
               for name in ("add", "sub", "mul", "copy", "scale", "axpy", "fill")}
    WS = program.workspace(ref.ws_bytes(x))
    program.lines += [
        f"{X} NV-WS-BYTES . CR",
        f"{X} {WS} NV-SUM T-R",
        f"{X} {WS} NV-SUMSQ T-R",
        f"{X} {WS} NV-ASUM T-R",
        f"{X} {WS} NV-MAX T-R",
        f"{X} {WS} NV-MIN T-R",
        f"{X} {Y} {WS} NV-DOT T-R",
        f"{X} {Y} {outputs['add']} NV-ADD T-S",
        f"{X} {Y} {outputs['sub']} NV-SUB T-S",
        f"{X} {Y} {outputs['mul']} NV-MUL T-S",
        f"{X} {outputs['copy']} NV-COPY T-S",
        f"{X} {outputs['scale']} NV-COPY T-S",
        f"{s} {outputs['scale']} {WS} NV-SCALE T-S",
        f"{Y} {outputs['axpy']} NV-COPY T-S",
        f"{s} {X} {outputs['axpy']} {WS} NV-AXPY T-S",
        f"{s} {outputs['fill']} NV-FILL T-S",
    ]
    records, data = program.run()

    inits = records[:10]
    assert inits == [("S", NUM_OK, None)] * 10
    reductions = records[10:16]
    assert [(kind, status) for kind, status, _ in reductions] == [("R", NUM_OK)] * 6
    got = [bits for _, _, bits in reductions]
    assert got == [
        ref.reduce_sum(x), ref.reduce_sumsq(x), ref.reduce_asum(x),
        ref.reduce_max(x), ref.reduce_min(x), ref.reduce_dot(x, y),
    ]
    assert records[16:] == [("S", NUM_OK, None)] * 9

    expected = {
        "add": ref.add(x, y), "sub": ref.sub(x, y), "mul": ref.mul(x, y),
        "copy": x, "scale": ref.scale(s, x), "axpy": ref.axpy(s, x, y),
        "fill": ref.fill(s, x),
    }
    for name, want in expected.items():
        assert as_array(x, data[name]).lanes == want.lanes, name


def test_workspace_size_is_what_the_reference_expects() -> None:
    program = Program()
    shapes = [(ref.FP64, 1, 1), (ref.FP64, 256, 1), (ref.FP64, 257, 1), (ref.FP32, 2000, 40)]
    for index, (fmt, nx, ny) in enumerate(shapes):
        program.lines.append(f"{program.base} {nx} {ny} {fmt} {index} T-ARR NARR-INIT T-S")
        program.lines.append(f"{index} T-ARR NV-WS-BYTES T-S")
    records, _ = program.run()
    sizes = [value for kind, value, _ in records[1::2]]
    assert sizes == [ref.ws_bytes(ref.Array(fmt, nx, ny, [])) for fmt, nx, ny in shapes]


def test_outputs_may_alias_inputs() -> None:
    rng = random.Random("alias")
    x = random_array(rng, ref.FP64, 21, 2)
    s = scalar(ref.FP64, 0.5)
    program = Program()
    X = program.array(x, "sum")
    Y = program.array(x, "axpy")
    WS = program.workspace(64)
    program.lines += [f"{X} {X} {X} NV-ADD T-S", f"{s} {Y} {Y} {WS} NV-AXPY T-S"]
    records, data = program.run()
    assert records == [("S", NUM_OK, None)] * 5
    assert as_array(x, data["sum"]).lanes == ref.add(x, x).lanes
    assert as_array(x, data["axpy"]).lanes == ref.axpy(s, x, x).lanes


# ---------------------------------------------------------------------------
# Sizes and refusals
# ---------------------------------------------------------------------------

def test_storage_sizes_and_invalid_shapes() -> None:
    program = Program()
    program.lines += [
        f"10 1 {ref.FP64} NARR-BYTES T-S",
        f"10 3 {ref.FP32} NARR-BYTES T-S",
        f"17 2 {ref.FP32} NARR-BYTES T-S",
        f"0 1 {ref.FP64} NARR-BYTES T-S",
        f"1 0 {ref.FP64} NARR-BYTES T-S",
        f"-4 1 {ref.FP64} NARR-BYTES T-S",
        "8 1 5 NARR-BYTES T-S",
        f"-1 1 RSHIFT 2 {ref.FP64} NARR-BYTES T-S",
        f"1 -1 1 RSHIFT {ref.FP64} NARR-BYTES T-S",
    ]
    records, _ = program.run()
    assert [value for _, value, _ in records] == [128, 192, 256, 0, 0, 0, 0, 0, 0]


def test_descriptors_refuse_bad_storage() -> None:
    base = region("hbw")
    program = Program()
    program.lines += [
        f"{base} 8 1 5 0 T-ARR NARR-INIT T-S",
        f"{base + 8} 8 1 {ref.FP64} 0 T-ARR NARR-INIT T-S",
        f"{base} 0 1 {ref.FP64} 0 T-ARR NARR-INIT T-S",
        f"{base} 8 -1 {ref.FP64} 0 T-ARR NARR-INIT T-S",
        f"-64 16 1 {ref.FP64} 0 T-ARR NARR-INIT T-S",
        f"{base + 32} 64 T-WS NWS-INIT T-S",
        f"{base} -64 T-WS NWS-INIT T-S",
        f"-64 128 T-WS NWS-INIT T-S",
    ]
    records, _ = program.run()
    assert [value for _, value, _ in records] == [
        E_FORMAT, E_ALIGN, E_SHAPE, E_SHAPE, E_SPACE, E_ALIGN, E_SPACE, E_SPACE,
    ]


def test_kernels_refuse_mismatches_without_writing() -> None:
    rng = random.Random("refuse")
    x = random_array(rng, ref.FP64, 9, 2)
    narrow = random_array(rng, ref.FP64, 8, 2)
    single = random_array(rng, ref.FP32, 9, 2)
    out = random_array(rng, ref.FP64, 9, 2)
    s = scalar(ref.FP64, 3.0)
    program = Program()
    X = program.array(x, "x")
    N = program.array(narrow)
    F = program.array(single)
    Z = program.array(out, "z")
    small = program.workspace(ref.ws_bytes(x) - 64)
    program.lines += [
        f"{X} {N} {Z} NV-ADD T-S",
        f"{X} {F} {Z} NV-SUB T-S",
        f"{X} {Z} {N} NV-MUL T-S",
        f"{N} {Z} NV-COPY T-S",
        f"{X} {N} {small} NV-DOT T-R",
        f"{X} {small} NV-SUM T-R",
        f"{X} {Z} {small} NV-DOT T-R",
        f"{s} {X} {N} {small} NV-AXPY T-S",
        f"{program.base} 32 T-WS NWS-INIT T-S",
        f"{s} {X} T-WS NV-SCALE T-S",
        f"{s} {X} {Z} T-WS NV-AXPY T-S",
        # A descriptor whose format field is not FP32 or FP64.
        f"5 {X} 8 + !",
        f"{s} {X} NV-FILL T-S",
        f"{X} {Z} {small} NV-DOT T-R",
    ]
    records, data = program.run()
    assert records[:5] == [("S", NUM_OK, None)] * 5
    statuses = [value for _, value, _ in records[5:]]
    assert statuses == [
        E_SHAPE, E_SHAPE, E_SHAPE, E_SHAPE, E_SHAPE, E_SPACE, E_SPACE, E_SHAPE,
        NUM_OK, E_SPACE, E_SPACE, E_FORMAT, E_FORMAT,
    ]
    assert as_array(x, data["x"]).lanes == x.lanes
    assert as_array(out, data["z"]).lanes == out.lanes
