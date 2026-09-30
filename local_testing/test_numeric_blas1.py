#!/usr/bin/env python3
"""Numeric arrays and level-1 kernels: akashic/numeric/array.f and blas1.f.

Every kernel result is compared bit for bit with numeric_reference.py,
which computes the documented definitions with MegaPad's exact IEEE oracle.
numeric_harness.py places the data, checks bounds with canary tiles, and
requires every program to leave the stack empty.
"""

from __future__ import annotations

import random

import pytest

import numeric_reference as ref
from numeric_harness import (
    E_ALIGN, E_FORMAT, E_SHAPE, E_SPACE, HBW_ARENA, NUM_OK, NumericMachine,
    as_array, random_array, scalar,
)


MACHINE = NumericMachine(("numeric/blas1.f",))


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

    program = MACHINE.program(_where(fmt, nx, ny))
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
    program = MACHINE.program()
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
    program = MACHINE.program()
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
    program = MACHINE.program()
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
    base = MACHINE.region("hbw")
    program = MACHINE.program()
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
    program = MACHINE.program()
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


def test_reductions_leave_the_accumulator_control_clear() -> None:
    # Older tile users in Akashic read reductions without setting TCTRL, so
    # every reduction path must finish with it clear, even when it was set.
    rng = random.Random("tctrl")
    x = random_array(rng, ref.FP64, 300, 1)
    y = random_array(rng, ref.FP64, 300, 1)
    program = MACHINE.program()
    X = program.array(x)
    Y = program.array(y)
    WS = program.workspace(ref.ws_bytes(x))
    for call in (f"{X} {WS} NV-SUM", f"{X} {WS} NV-SUMSQ", f"{X} {WS} NV-ASUM",
                 f"{X} {WS} NV-MAX", f"{X} {WS} NV-MIN", f"{X} {Y} {WS} NV-DOT"):
        program.lines.append(f"1 TCTRL! {call} 2DROP TCTRL@ T-S")
    program.lines += [
        f"1 TCTRL! {X} 0 NV-OP-SUM {WS} {WS} NV-PARTIALS 0 1 NV-BLOCK-VALUES DROP TCTRL@ T-S",
        f"1 TCTRL! 1 NV-OP-SUM {WS} NV-COMBINE 2DROP TCTRL@ T-S",
        f"1 TCTRL! 1 NV-OP-MAX {WS} NV-COMBINE 2DROP TCTRL@ T-S",
    ]
    records, _ = program.run()
    assert [value for _, value, _ in records[3:]] == [0] * 9
