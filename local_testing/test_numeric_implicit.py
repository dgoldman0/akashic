#!/usr/bin/env python3
"""Conjugate gradient and implicit heat steps: numeric/cg.f and heat2d.f.

Each step is compared bit for bit with numeric_reference.py: the solution,
padding lanes included, the iteration count, the status, and the final
residual.  Physics checks follow: a discrete sine mode must decay by its
exact backward-Euler factor, and zero-flux sides must conserve total heat.
"""

from __future__ import annotations

import math
import random

import pytest

import numeric_reference as ref
from numeric_harness import (
    E_ALIGN, E_FORMAT, E_OVERLAP, E_RANGE, E_SHAPE, E_SPACE, NUM_OK, TEAM_PRELUDE,
    NumericMachine, array_of, as_array, real_values, scalar,
    team_init,
)


E_CONVERGE = 7
MACHINE = NumericMachine(
    ("numeric/heat2d.f",),
    prelude=TEAM_PRELUDE + (
        "CREATE T-BC NBC-SIZE ALLOT",
        "CREATE T-STEP NHEAT-IMPLICIT-SIZE ALLOT",
        ': T-CHK ( status -- ) ?DUP IF ." @S:" . CR THEN ;',
    ),
)
SIDES = {"top": "NBC-TOP", "bottom": "NBC-BOTTOM", "left": "NBC-LEFT", "right": "NBC-RIGHT"}


def f64(value: float) -> int:
    return scalar(ref.FP64, value)


def member_ws(u: ref.Array) -> int:
    return max(ref.stencil_ws_bytes(u), ref.ws_bytes(u))


def stepper_bytes(u: ref.Array) -> int:
    return (3 * u.nbytes + ref.storage_bytes(u.fmt, u.nx, 1)
            + ref.storage_bytes(u.fmt, u.ny, 1))


def place_boundary(program, bc: ref.Boundary) -> None:
    program.lines.append("T-BC NBC-INIT")
    for side, word in SIDES.items():
        ghost = getattr(bc, side)
        if ghost is not None:
            program.lines.append(f"{program.array(ghost)} {word} T-BC NBC-DIRICHLET! T-S")


def boundary(rng: random.Random, fmt: int, nx: int, ny: int, mode: str) -> ref.Boundary:
    def vector(n: int) -> ref.Array:
        return array_of(fmt, n, 1, lambda i, j: rng.uniform(-2.0, 2.0))

    if mode == "flux":
        return ref.Boundary()
    if mode == "dirichlet":
        return ref.Boundary(vector(nx), vector(nx), vector(ny), vector(ny))
    return ref.Boundary(top=vector(nx), right=vector(ny))


def grid(rng: random.Random, fmt: int, nx: int, ny: int) -> ref.Array:
    """Real lanes in [-1, 1]; padding lanes are arbitrary bits."""

    arr = array_of(fmt, nx, ny, lambda i, j: rng.uniform(-1.0, 1.0))
    arr.lanes = [
        lane if index % arr.row_lanes < nx else rng.getrandbits(arr.format.width)
        for index, lane in enumerate(arr.lanes)
    ]
    return arr


def run_steps(u0: ref.Array, bc: ref.Boundary, r: int, tol: int, limit: int, steps: int,
              in_place: bool = False, rounding: int | None = None):
    """Run implicit steps from u0; return the final grid and the records.

    Each step leaves three records: its status, its iteration count, and the
    solver's final residual."""

    program = MACHINE.program()
    A = program.array(u0, "a")
    B = A if in_place else program.array(u0, "b")
    place_boundary(program, bc)
    scratch = program.reserve(stepper_bytes(u0))
    program.lines += [
        team_init(1, member_ws(u0)),
        f"{r} {tol} {limit} {scratch} {stepper_bytes(u0)} {A} T-STEP NHEAT-IMPLICIT-INIT T-S",
    ]
    if rounding is not None:
        program.lines.append(f"{rounding} FPCSR!")
    grids = [A, B]
    for step in range(steps):
        src, dst = grids[step % 2], grids[(step + 1) % 2]
        program.lines += [
            f"{src} T-BC {dst} T-STEP T-TEAM NHEAT-IMPLICIT T-S T-S",
            "T-STEP NHEAT-SOLVER NCG-RESIDUAL 0 T-R",
        ]
    if rounding is not None:
        program.lines.append("FPCSR@ 7 AND T-S")
    records, data = program.run()
    final = "b" if steps % 2 and not in_place else "a"
    return as_array(u0, data[final]), records


# ---------------------------------------------------------------------------
# Steps against the reference
# ---------------------------------------------------------------------------

CASES = [
    (ref.FP64, 13, 7, mode, rate)
    for mode in ("flux", "dirichlet", "mixed")
    for rate in (0.5, 4.0)
] + [(ref.FP32, 17, 5, "dirichlet", 1.0), (ref.FP64, 1, 1, "dirichlet", 2.0)]


@pytest.mark.parametrize("fmt,nx,ny,mode,rate", CASES)
def test_implicit_step_matches_the_reference(fmt: int, nx: int, ny: int, mode: str, rate: float) -> None:
    rng = random.Random(f"implicit-{fmt}-{nx}-{ny}-{mode}-{rate}")
    u = grid(rng, fmt, nx, ny)
    bc = boundary(rng, fmt, nx, ny, mode)
    r = scalar(fmt, rate)
    tol = f64(1e-5 if fmt == ref.FP32 else 1e-12)

    got, records = run_steps(u, bc, r, tol, 200, 1)
    want = ref.implicit_step(r, u, bc, tol, 200)
    status, iterations = records[-3][1], records[-2][1]
    assert (status, iterations) == (NUM_OK, want.iterations)
    assert records[-1] == ("R", NUM_OK, want.rr)
    assert got.lanes == want.x.lanes
    assert want.iterations > 0


def test_a_solve_that_runs_out_of_iterations_says_so() -> None:
    rng = random.Random("implicit-limit")
    u = grid(rng, ref.FP64, 13, 7)
    bc = boundary(rng, ref.FP64, 13, 7, "dirichlet")
    r, tol = f64(4.0), f64(1e-14)
    got, records = run_steps(u, bc, r, tol, 3, 1)
    want = ref.implicit_step(r, u, bc, tol, 3)
    assert want.status == E_CONVERGE
    assert (records[-3][1], records[-2][1]) == (E_CONVERGE, 3)
    assert got.lanes == want.x.lanes


def test_r_zero_needs_no_iterations_and_in_place_steps_work() -> None:
    rng = random.Random("implicit-zero")
    u = grid(rng, ref.FP64, 9, 4)
    bc = boundary(rng, ref.FP64, 9, 4, "mixed")
    tol = f64(1e-12)
    got, records = run_steps(u, bc, f64(0.0), tol, 50, 1)
    assert records[-2][1] == 0
    assert got.lanes == ref.implicit_step(f64(0.0), u, bc, tol, 50).x.lanes

    r = f64(1.5)
    got, records = run_steps(u, bc, r, tol, 100, 2, in_place=True)
    want = u
    for _ in range(2):
        want = ref.implicit_step(r, want, bc, tol, 100).x
    assert got.lanes == want.lanes


def test_the_callers_rounding_mode_is_kept_and_does_not_change_the_step() -> None:
    rng = random.Random("implicit-rounding")
    u = grid(rng, ref.FP64, 13, 7)
    bc = boundary(rng, ref.FP64, 13, 7, "dirichlet")
    r, tol = f64(2.0), f64(1e-12)
    got, records = run_steps(u, bc, r, tol, 200, 1, rounding=1)
    assert records[-1][1] == 1
    assert got.lanes == ref.implicit_step(r, u, bc, tol, 200).x.lanes


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

def test_implicit_steps_decay_a_discrete_sine_mode_even_past_the_explicit_limit() -> None:
    nx, ny, steps, rate = 30, 20, 3, 2.0

    def mode(i: int, j: int) -> float:
        return math.sin(math.pi * (j + 1) / (nx + 1)) * math.sin(math.pi * (i + 1) / (ny + 1))

    u0 = array_of(ref.FP64, nx, ny, mode)
    zeros = lambda n: array_of(ref.FP64, n, 1, lambda i, j: 0.0)  # noqa: E731
    bc = ref.Boundary(zeros(nx), zeros(nx), zeros(ny), zeros(ny))
    got, _ = run_steps(u0, bc, f64(rate), f64(1e-13), 100, steps)

    eigenvalue = (-4 * math.sin(math.pi / (2 * (nx + 1))) ** 2
                  - 4 * math.sin(math.pi / (2 * (ny + 1))) ** 2)
    factor = (1 / (1 - rate * eigenvalue)) ** steps
    initial, final = real_values(u0), real_values(got)
    error = max(abs(final[i][j] - factor * initial[i][j]) for i in range(ny) for j in range(nx))
    assert error <= 1e-12 * factor


def test_zero_flux_implicit_steps_conserve_heat() -> None:
    nx, ny, steps = 30, 20, 3
    rng = random.Random("implicit-conserve")
    u0 = array_of(ref.FP64, nx, ny, lambda i, j: 1.0 + rng.random())
    got, _ = run_steps(u0, ref.Boundary(), f64(1.0), f64(1e-13), 200, steps)
    before = math.fsum(value for row in real_values(u0) for value in row)
    after = math.fsum(value for row in real_values(got) for value in row)
    assert abs(after - before) <= 1e-11 * before


# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

def test_stepper_and_step_refusals() -> None:
    fmt, nx, ny = ref.FP64, 9, 4
    rng = random.Random("implicit-refuse")
    u = array_of(fmt, nx, ny, lambda i, j: rng.uniform(-1.0, 1.0))
    out = array_of(fmt, nx, ny, lambda i, j: 0.0)
    narrow = array_of(fmt, nx - 1, ny, lambda i, j: 0.0)
    need = stepper_bytes(u)

    program = MACHINE.program()
    U = program.array(u, "u")
    OUT = program.array(out, "out")
    NARROW = program.array(narrow)
    scratch = program.reserve(need)
    u_addr = program.reads["u"][0]
    INSIDE = program.describe(scratch, u)
    HALF = program.describe(u_addr + 64, u)
    BAD = program.describe(u_addr, u)
    good = f"{f64(1.0)} {f64(1e-10)} 50 {scratch} {need} {U} T-STEP NHEAT-IMPLICIT-INIT T-S"
    program.lines += [
        team_init(1, member_ws(u)),
        "T-BC NBC-INIT",
        # stepper; BAD's format field becomes 5
        f"5 {BAD} 8 + !",
        f"{f64(1.0)} {f64(1e-10)} 50 {scratch} {need} {BAD} T-STEP NHEAT-IMPLICIT-INIT T-S",
        f"{f64(-1.0)} {f64(1e-10)} 50 {scratch} {need} {U} T-STEP NHEAT-IMPLICIT-INIT T-S",
        f"{f64(math.inf)} {f64(1e-10)} 50 {scratch} {need} {U} T-STEP NHEAT-IMPLICIT-INIT T-S",
        f"{ref.fp.FP64.canonical_nan} {f64(1e-10)} 50 {scratch} {need} {U} T-STEP NHEAT-IMPLICIT-INIT T-S",
        f"{f64(1.0)} {f64(-1e-10)} 50 {scratch} {need} {U} T-STEP NHEAT-IMPLICIT-INIT T-S",
        f"{f64(1.0)} {f64(1e-10)} -1 {scratch} {need} {U} T-STEP NHEAT-IMPLICIT-INIT T-S",
        f"{f64(1.0)} {f64(1e-10)} 50 {scratch} {need - 64} {U} T-STEP NHEAT-IMPLICIT-INIT T-S",
        f"{f64(1.0)} {f64(1e-10)} 50 {scratch + 8} {need} {U} T-STEP NHEAT-IMPLICIT-INIT T-S",
        good,
        # steps
        f"{U} T-BC {NARROW} T-STEP T-TEAM NHEAT-IMPLICIT T-S T-S",
        f"{U} T-BC {HALF} T-STEP T-TEAM NHEAT-IMPLICIT T-S T-S",
        f"{U} T-BC {INSIDE} T-STEP T-TEAM NHEAT-IMPLICIT T-S T-S",
        f"{INSIDE} NBC-TOP T-BC NBC-DIRICHLET! T-S",
        f"{U} T-BC {OUT} T-STEP T-TEAM NHEAT-IMPLICIT T-S T-S",
    ]
    records, data = program.run()
    statuses = [value for _, value, _ in records]
    inits = 7  # six descriptors and the team
    assert statuses[:inits] == [NUM_OK] * inits
    assert statuses[inits:] == [
        E_FORMAT, E_RANGE, E_RANGE, E_RANGE, E_RANGE, E_RANGE, E_SPACE, E_ALIGN, NUM_OK,
        E_SHAPE, 0, E_OVERLAP, 0, E_OVERLAP, 0,
        NUM_OK, E_OVERLAP, 0,
    ]
    assert as_array(u, data["u"]).lanes == u.lanes
    assert as_array(out, data["out"]).lanes == out.lanes
