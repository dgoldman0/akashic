#!/usr/bin/env python3
"""Grid stencils and explicit heat steps: numeric/boundary.f, stencil2d.f,
and heat2d.f.

Results are compared bit for bit with numeric_reference.py, including each
row's padding lanes.  Two physics checks follow: a discrete sine mode with
zero Dirichlet ghosts must decay by its exact factor per step, and zero-flux
sides must conserve total heat.
"""

from __future__ import annotations

import math
import random

import pytest

import numeric_reference as ref
from numeric_harness import (
    E_FORMAT, E_OVERLAP, E_RANGE, E_SHAPE, E_SPACE, NUM_OK, TEAM_PRELUDE,
    NumericMachine, array_of, as_array, random_array, real_values, scalar,
    team_init,
)


MACHINE = NumericMachine(
    ("numeric/heat2d.f",),
    prelude=TEAM_PRELUDE + (
        "CREATE T-BC NBC-SIZE ALLOT",
        ': T-CHK ( status -- ) ?DUP IF ." @S:" . CR THEN ;',
    ),
)

SIDES = {"top": "NBC-TOP", "bottom": "NBC-BOTTOM", "left": "NBC-LEFT", "right": "NBC-RIGHT"}


def place_boundary(program, bc: ref.Boundary) -> None:
    """Describe bc in T-BC, placing its Dirichlet vectors."""

    program.lines.append("T-BC NBC-INIT")
    for side, word in SIDES.items():
        ghost = getattr(bc, side)
        if ghost is not None:
            name = program.array(ghost)
            program.lines.append(f"{name} {word} T-BC NBC-DIRICHLET! T-S")


def boundary(rng: random.Random, fmt: int, nx: int, ny: int, mode: str) -> ref.Boundary:
    def vector(n: int) -> ref.Array:
        return random_array(rng, fmt, n, 1)

    if mode == "flux":
        return ref.Boundary()
    if mode == "dirichlet":
        return ref.Boundary(vector(nx), vector(nx), vector(ny), vector(ny))
    return ref.Boundary(top=vector(nx), right=vector(ny))


def zero_boundary(fmt: int, nx: int, ny: int) -> ref.Boundary:
    def zeros(n: int) -> ref.Array:
        return array_of(fmt, n, 1, lambda i, j: 0.0)

    return ref.Boundary(zeros(nx), zeros(nx), zeros(ny), zeros(ny))


# ---------------------------------------------------------------------------
# Kernels against the reference
# ---------------------------------------------------------------------------

SHAPES = {
    ref.FP64: [(1, 1), (1, 4), (5, 1), (8, 3), (9, 4), (13, 7), (40, 11)],
    ref.FP32: [(1, 1), (16, 2), (17, 3), (33, 5)],
}
CASES = [
    (fmt, nx, ny, mode)
    for fmt in (ref.FP64, ref.FP32)
    for nx, ny in SHAPES[fmt]
    for mode in ("flux", "dirichlet", "mixed")
]


@pytest.mark.parametrize("fmt,nx,ny,mode", CASES)
def test_stencil_matches_the_reference(fmt: int, nx: int, ny: int, mode: str) -> None:
    rng = random.Random(f"stencil-{fmt}-{nx}-{ny}-{mode}")
    u = random_array(rng, fmt, nx, ny, special=0.05)
    bc = boundary(rng, fmt, nx, ny, mode)
    c = scalar(fmt, -0.3125)
    r = scalar(fmt, 0.2)

    program = MACHINE.program()
    U = program.array(u)
    place_boundary(program, bc)
    outs = {name: program.array(random_array(rng, fmt, nx, ny), name)
            for name in ("laplace", "update", "heat")}
    WS = program.workspace(ref.stencil_ws_bytes(u))
    program.lines += [
        team_init(1, ref.stencil_ws_bytes(u)),
        f"{U} NST-WS-BYTES T-S",
        f"{U} T-BC {outs['laplace']} {WS} NST-LAPLACE T-S",
        f"{c} {U} T-BC {outs['update']} {WS} NST-UPDATE T-S",
        f"{r} {U} T-BC {outs['heat']} T-TEAM NHEAT-EXPLICIT T-S",
    ]
    records, data = program.run()

    statuses = [value for _, value, _ in records]
    assert statuses[:-4] == [NUM_OK] * (len(statuses) - 4)
    assert statuses[-4:] == [ref.stencil_ws_bytes(u), NUM_OK, NUM_OK, NUM_OK]
    assert as_array(u, data["laplace"]).lanes == ref.laplace(u, bc).lanes
    assert as_array(u, data["update"]).lanes == ref.update(c, u, bc).lanes
    assert as_array(u, data["heat"]).lanes == ref.update(r, u, bc).lanes


# ---------------------------------------------------------------------------
# Arrays outside HBW
# ---------------------------------------------------------------------------

STREAM_CASES = [
    (ref.FP64, 9, 1, "dirichlet"),
    (ref.FP64, 8, 2, "flux"),
    (ref.FP32, 17, 3, "mixed"),
    (ref.FP64, 13, 7, "dirichlet"),
]
PLACEMENTS = [  # grid, output, workspace
    ("xmem", "xmem", "hbw"),
    ("xmem", "hbw", "hbw"),
    ("hbw", "xmem", "hbw"),
    ("xmem", "xmem", "xmem"),
]


@pytest.mark.parametrize("grid,out,ws", PLACEMENTS)
@pytest.mark.parametrize("fmt,nx,ny,mode", STREAM_CASES)
def test_arrays_outside_hbw_give_the_same_bits(
    fmt: int, nx: int, ny: int, mode: str, grid: str, out: str, ws: str,
) -> None:
    rng = random.Random(f"stream-{fmt}-{nx}-{ny}-{mode}")
    u = random_array(rng, fmt, nx, ny, special=0.05)
    bc = boundary(rng, fmt, nx, ny, mode)
    c = scalar(fmt, -0.3125)

    program = MACHINE.program("xmem")
    U = program.array(u, where=grid)
    place_boundary(program, bc)
    outs = {name: program.array(random_array(rng, fmt, nx, ny), name, where=out)
            for name in ("laplace", "update")}
    WS = program.workspace(ref.stencil_ws_bytes(u), where=ws)
    program.lines += [
        f"{U} T-BC {outs['laplace']} {WS} NST-LAPLACE T-S",
        f"{c} {U} T-BC {outs['update']} {WS} NST-UPDATE T-S",
    ]
    records, data = program.run()

    assert all(status == NUM_OK for _, status, _ in records)
    assert as_array(u, data["laplace"]).lanes == ref.laplace(u, bc).lanes
    assert as_array(u, data["update"]).lanes == ref.update(c, u, bc).lanes


@pytest.mark.parametrize("where", ["hbw", "xmem"])
def test_row_ranges_together_give_the_whole_grid(where: str) -> None:
    fmt, nx, ny = ref.FP64, 9, 7
    rng = random.Random(f"ranges-{where}")
    u = random_array(rng, fmt, nx, ny)
    bc = boundary(rng, fmt, nx, ny, "mixed")
    c = scalar(fmt, 0.2)
    ranges = [(3, 7), (0, 2), (5, 5), (2, 3)]

    program = MACHINE.program(where)
    U = program.array(u)
    place_boundary(program, bc)
    LAPLACE = program.array(random_array(rng, fmt, nx, ny), "laplace")
    UPDATE = program.array(random_array(rng, fmt, nx, ny), "update")
    WS = program.workspace(ref.stencil_ws_bytes(u), where="hbw")
    for i0, i1 in ranges:
        program.lines += [
            f"{U} T-BC {LAPLACE} {WS} {i0} {i1} NST-LAPLACE-ROWS T-S",
            f"{c} {U} T-BC {UPDATE} {WS} {i0} {i1} NST-UPDATE-ROWS T-S",
        ]
    records, data = program.run()

    assert all(status == NUM_OK for _, status, _ in records)
    assert as_array(u, data["laplace"]).lanes == ref.laplace(u, bc).lanes
    assert as_array(u, data["update"]).lanes == ref.update(c, u, bc).lanes


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

def _run_steps(fmt: int, u0: ref.Array, bc: ref.Boundary, r: int, pairs: int) -> ref.Array:
    """Run 2 * pairs explicit steps, alternating two grids; return the result."""

    program = MACHINE.program()
    A = program.array(u0, "a")
    B = program.array(u0)
    place_boundary(program, bc)
    program.lines += [
        team_init(1, ref.stencil_ws_bytes(u0)),
        f": T-RUN {pairs} 0 DO",
        f"  {r} {A} T-BC {B} T-TEAM NHEAT-EXPLICIT T-CHK",
        f"  {r} {B} T-BC {A} T-TEAM NHEAT-EXPLICIT T-CHK",
        "  LOOP ;",
        "T-RUN",
    ]
    records, data = program.run()
    assert all(value == NUM_OK for _, value, _ in records), records
    return as_array(u0, data["a"])


@pytest.mark.parametrize("fmt,tolerance", [(ref.FP64, 1e-13), (ref.FP32, 1e-5)])
def test_explicit_steps_decay_a_discrete_sine_mode(fmt: int, tolerance: float) -> None:
    nx, ny, steps = 30, 20, 20
    r = scalar(fmt, 0.2)
    rate = ref.fp.to_double(ref.FORMATS[fmt], r)

    def mode(i: int, j: int) -> float:
        return math.sin(math.pi * (j + 1) / (nx + 1)) * math.sin(math.pi * (i + 1) / (ny + 1))

    u0 = array_of(fmt, nx, ny, mode)
    bc = zero_boundary(fmt, nx, ny)
    got = _run_steps(fmt, u0, bc, r, steps // 2)

    want = u0
    for _ in range(steps):
        want = ref.update(r, want, bc)
    assert got.lanes == want.lanes

    eigenvalue = (-4 * math.sin(math.pi / (2 * (nx + 1))) ** 2
                  - 4 * math.sin(math.pi / (2 * (ny + 1))) ** 2)
    factor = (1 + rate * eigenvalue) ** steps
    initial = real_values(u0)
    final = real_values(got)
    error = max(abs(final[i][j] - factor * initial[i][j]) for i in range(ny) for j in range(nx))
    assert error <= tolerance * factor


def test_zero_flux_steps_conserve_heat() -> None:
    fmt, nx, ny, steps = ref.FP64, 30, 20, 20
    rng = random.Random("conserve")
    u0 = array_of(fmt, nx, ny, lambda i, j: 1.0 + rng.random())
    bc = ref.Boundary()
    r = scalar(fmt, 0.25)
    got = _run_steps(fmt, u0, bc, r, steps // 2)

    want = u0
    for _ in range(steps):
        want = ref.update(r, want, bc)
    assert got.lanes == want.lanes

    before = math.fsum(value for row in real_values(u0) for value in row)
    after = math.fsum(value for row in real_values(got) for value in row)
    assert abs(after - before) <= 1e-13 * before


# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

def test_stencils_refuse_bad_arguments_without_writing() -> None:
    fmt, nx, ny = ref.FP64, 9, 4
    rng = random.Random("stencil-refuse")
    u = random_array(rng, fmt, nx, ny)
    out = random_array(rng, fmt, nx, ny)
    good_top = random_array(rng, fmt, nx, 1)
    short_top = random_array(rng, fmt, nx - 1, 1)
    single_top = random_array(rng, ref.FP32, nx, 1)
    narrow = random_array(rng, fmt, nx - 1, ny)
    f64 = lambda value: scalar(fmt, value)  # noqa: E731

    program = MACHINE.program()
    U = program.array(u, "u")
    OUT = program.array(out, "out")
    OK = program.array(random_array(rng, fmt, nx, ny), "ok")
    GOOD = program.array(good_top)
    SHORT = program.array(short_top)
    SINGLE = program.array(single_top)
    NARROW = program.array(narrow)
    ws_addr = program.reserve(ref.stencil_ws_bytes(u))
    out_addr = program.reads["out"][0]
    u_addr = program.reads["u"][0]
    OUT_ROW = program.describe(out_addr, good_top)
    BAD_FMT = program.describe(u_addr, u)
    good_ws = f"{ws_addr} {ref.stencil_ws_bytes(u)} T-WS NWS-INIT T-S"
    program.lines += [
        good_ws,
        team_init(1, ref.stencil_ws_bytes(u)),
        "T-BC NBC-INIT",
        f"{f64(0.25)} {U} T-BC {OK} T-TEAM NHEAT-EXPLICIT T-S",
        # r outside [0, 1/4]
        f"{f64(0.25) + 1} {U} T-BC {OUT} T-TEAM NHEAT-EXPLICIT T-S",
        f"{f64(-0.1)} {U} T-BC {OUT} T-TEAM NHEAT-EXPLICIT T-S",
        f"{f64(math.inf)} {U} T-BC {OUT} T-TEAM NHEAT-EXPLICIT T-S",
        f"{ref.fp.FP64.canonical_nan} {U} T-BC {OUT} T-TEAM NHEAT-EXPLICIT T-S",
        # shapes and boundary vectors
        f"{U} T-BC {NARROW} T-WS NST-LAPLACE T-S",
        f"{SHORT} NBC-TOP T-BC NBC-DIRICHLET! T-S",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        f"{SINGLE} NBC-TOP T-BC NBC-DIRICHLET! T-S",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        f"0 NBC-TOP T-BC NBC-DIRICHLET! T-S",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        "7 T-BC !",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        f"{GOOD} 4 T-BC NBC-DIRICHLET! T-S",
        "-1 T-BC NBC-ZERO-FLUX! T-S",
        # overlaps
        "T-BC NBC-INIT",
        f"{U} T-BC {U} T-WS NST-LAPLACE T-S",
        f"{OUT_ROW} NBC-TOP T-BC NBC-DIRICHLET! T-S",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        "T-BC NBC-INIT",
        f"{out_addr} {ref.stencil_ws_bytes(u)} T-WS NWS-INIT T-S",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        f"{u_addr} {ref.stencil_ws_bytes(u)} T-WS NWS-INIT T-S",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        # workspace and format
        f"{ws_addr} {ref.stencil_ws_bytes(u) - 64} T-WS NWS-INIT T-S",
        f"{U} T-BC {OUT} T-WS NST-LAPLACE T-S",
        good_ws,
        f"5 {BAD_FMT} 8 + !",
        f"{BAD_FMT} T-BC {OUT} T-WS NST-LAPLACE T-S",
        f"{f64(0.1)} {BAD_FMT} T-BC {OUT} T-TEAM NHEAT-EXPLICIT T-S",
    ]
    records, data = program.run()
    statuses = [value for _, value, _ in records]
    inits = 11  # nine descriptors, the workspace, and the team
    assert statuses[:inits] == [NUM_OK] * inits
    assert statuses[inits:] == [
        NUM_OK,
        E_RANGE, E_RANGE, E_RANGE, E_RANGE,
        E_SHAPE,
        NUM_OK, E_SHAPE,
        NUM_OK, E_SHAPE,
        NUM_OK, E_SHAPE,
        E_RANGE,
        E_RANGE, E_RANGE,
        E_OVERLAP,
        NUM_OK, E_OVERLAP,
        NUM_OK, E_OVERLAP,
        NUM_OK, E_OVERLAP,
        NUM_OK, E_SPACE,
        NUM_OK,
        E_FORMAT, E_FORMAT,
    ]
    assert as_array(out, data["out"]).lanes == out.lanes
    assert as_array(u, data["u"]).lanes == u.lanes
    bc = ref.Boundary()
    assert as_array(u, data["ok"]).lanes == ref.update(f64(0.25), u, bc).lanes
