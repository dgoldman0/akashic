#!/usr/bin/env python3
"""Numeric kernels on a team of cores: numeric/team.f, team-blas1.f, and
team-stencil2d.f, on a four-core machine.

Every team result must equal numeric_reference.py bit for bit, for teams of
one to four cores, so a result does not depend on how many cores ran it.
The team counters show that worker cores really ran their shares, and that
the owner ran the share of a worker that was busy.  The four emulated
cores run on one host thread.
"""

from __future__ import annotations

import math
import random

import pytest

import numeric_reference as ref
from numeric_harness import (
    E_ALIGN, E_FORMAT, E_OVERLAP, E_RANGE, E_SHAPE, E_SPACE, NUM_OK, TEAM_ARENA,
    TEAM_PRELUDE, NumericMachine, array_of, as_array, random_array, scalar,
    team_init,
)
from forth_snapshot import program_output


CORES = 4
MACHINE = NumericMachine(
    ("numeric/team-blas1.f", "numeric/heat2d.f"),
    prelude=TEAM_PRELUDE + (
        "CREATE T-BC NBC-SIZE ALLOT",
        ': T-CHK ( status -- ) ?DUP IF ." @S:" . CR THEN ;',
        ": T-SPIN ( -- ) 1000000 0 DO LOOP ;",
    ),
    num_cores=CORES,
)
SIDES = {"top": "NBC-TOP", "bottom": "NBC-BOTTOM", "left": "NBC-LEFT", "right": "NBC-RIGHT"}


def worker_shares(total: int, cores: int) -> int:
    """Members after the owner whose share of total items is not empty."""

    return sum(
        (k + 1) * total // cores > k * total // cores for k in range(1, cores)
    )


def stencil_ws(u: ref.Array) -> int:
    return 320 + 2 * u.row_tiles * 64


def blocks(arr: ref.Array) -> int:
    return -(-arr.tiles // ref.BLOCK_TILES)


def team_counters(records) -> tuple[int, int]:
    """The last two records: NTEAM-JOBS and NTEAM-OWNED."""

    return records[-2][1], records[-1][1]


def place_boundary(program, bc: ref.Boundary) -> None:
    program.lines.append("T-BC NBC-INIT")
    for side, word in SIDES.items():
        ghost = getattr(bc, side)
        if ghost is not None:
            program.lines.append(f"{program.array(ghost)} {word} T-BC NBC-DIRICHLET! T-S")


# ---------------------------------------------------------------------------
# Level-1 kernels
# ---------------------------------------------------------------------------

BLAS_CASES = [
    (cores, fmt, nx, ny)
    for cores in (1, 2, 3, 4)
    for fmt, nx, ny in ((ref.FP64, 257, 9), (ref.FP64, 5, 1), (ref.FP32, 33, 5))
]


@pytest.mark.parametrize("cores,fmt,nx,ny", BLAS_CASES)
def test_team_level1_kernels_match_one_core(cores: int, fmt: int, nx: int, ny: int) -> None:
    rng = random.Random(f"team-{cores}-{fmt}-{nx}-{ny}")
    x = random_array(rng, fmt, nx, ny, special=0.03)
    y = random_array(rng, fmt, nx, ny, special=0.03)
    s = scalar(fmt, 0.625)

    program = MACHINE.program()
    X = program.array(x)
    Y = program.array(y)
    outs = {name: program.array(random_array(rng, fmt, nx, ny), name)
            for name in ("add", "sub", "mul", "copy", "scale", "axpy", "fill")}
    program.lines += [
        team_init(cores, max(ref.ws_bytes(x), 64)),
        f"{X} T-TEAM NT-SUM T-R",
        f"{X} T-TEAM NT-SUMSQ T-R",
        f"{X} T-TEAM NT-ASUM T-R",
        f"{X} T-TEAM NT-MAX T-R",
        f"{X} T-TEAM NT-MIN T-R",
        f"{X} {Y} T-TEAM NT-DOT T-R",
        f"{X} {Y} {outs['add']} T-TEAM NT-ADD T-S",
        f"{X} {Y} {outs['sub']} T-TEAM NT-SUB T-S",
        f"{X} {Y} {outs['mul']} T-TEAM NT-MUL T-S",
        f"{X} {outs['copy']} T-TEAM NT-COPY T-S",
        f"{X} {outs['scale']} T-TEAM NT-COPY T-S",
        f"{s} {outs['scale']} T-TEAM NT-SCALE T-S",
        f"{Y} {outs['axpy']} T-TEAM NT-COPY T-S",
        f"{s} {X} {outs['axpy']} T-TEAM NT-AXPY T-S",
        f"{s} {outs['fill']} T-TEAM NT-FILL T-S",
        "T-TEAM NTEAM-JOBS T-S",
        "T-TEAM NTEAM-OWNED T-S",
    ]
    records, data = program.run()

    inits = 9
    assert records[:inits + 1] == [("S", NUM_OK, None)] * (inits + 1)
    reductions = records[inits + 1:inits + 7]
    assert [(kind, status) for kind, status, _ in reductions] == [("R", NUM_OK)] * 6
    assert [bits for _, _, bits in reductions] == [
        ref.reduce_sum(x), ref.reduce_sumsq(x), ref.reduce_asum(x),
        ref.reduce_max(x), ref.reduce_min(x), ref.reduce_dot(x, y),
    ]
    assert records[inits + 7:-2] == [("S", NUM_OK, None)] * 9
    expected = {
        "add": ref.add(x, y), "sub": ref.sub(x, y), "mul": ref.mul(x, y),
        "copy": x, "scale": ref.scale(s, x), "axpy": ref.axpy(s, x, y),
        "fill": ref.fill(s, x),
    }
    for name, want in expected.items():
        assert as_array(x, data[name]).lanes == want.lanes, name

    jobs, owned = team_counters(records)
    assert owned == 0
    assert jobs == 6 * worker_shares(blocks(x), cores) + 9 * worker_shares(x.tiles, cores)


# ---------------------------------------------------------------------------
# Stencils and heat steps
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("cores", [1, 2, 3, 4])
def test_team_stencils_match_one_core(cores: int) -> None:
    fmt, nx, ny = ref.FP64, 13, 7
    rng = random.Random(f"team-stencil-{cores}")
    u = random_array(rng, fmt, nx, ny, special=0.05)
    bc = ref.Boundary(top=random_array(rng, fmt, nx, 1), right=random_array(rng, fmt, ny, 1))
    c = scalar(fmt, -0.3125)
    r = scalar(fmt, 0.2)

    program = MACHINE.program()
    U = program.array(u)
    place_boundary(program, bc)
    outs = {name: program.array(random_array(rng, fmt, nx, ny), name)
            for name in ("laplace", "update", "heat")}
    program.lines += [
        team_init(cores, stencil_ws(u)),
        f"{U} T-BC {outs['laplace']} T-TEAM NT-LAPLACE T-S",
        f"{c} {U} T-BC {outs['update']} T-TEAM NT-UPDATE T-S",
        f"{r} {U} T-BC {outs['heat']} T-TEAM NHEAT-EXPLICIT T-S",
        "T-TEAM NTEAM-JOBS T-S",
        "T-TEAM NTEAM-OWNED T-S",
    ]
    records, data = program.run()
    assert all(status == NUM_OK for _, status, _ in records[:-2])
    assert as_array(u, data["laplace"]).lanes == ref.laplace(u, bc).lanes
    assert as_array(u, data["update"]).lanes == ref.update(c, u, bc).lanes
    assert as_array(u, data["heat"]).lanes == ref.update(r, u, bc).lanes
    assert team_counters(records) == (3 * worker_shares(ny, cores), 0)


def test_four_core_heat_steps_match_the_reference() -> None:
    fmt, nx, ny, steps = ref.FP64, 30, 20, 20
    r = scalar(fmt, 0.2)

    def mode(i: int, j: int) -> float:
        return math.sin(math.pi * (j + 1) / (nx + 1)) * math.sin(math.pi * (i + 1) / (ny + 1))

    u0 = array_of(fmt, nx, ny, mode)
    zeros = lambda n: array_of(fmt, n, 1, lambda i, j: 0.0)  # noqa: E731
    bc = ref.Boundary(zeros(nx), zeros(nx), zeros(ny), zeros(ny))

    program = MACHINE.program()
    A = program.array(u0, "a")
    B = program.array(u0)
    place_boundary(program, bc)
    program.lines += [
        team_init(CORES, stencil_ws(u0)),
        f": T-RUN {steps // 2} 0 DO",
        f"  {r} {A} T-BC {B} T-TEAM NHEAT-EXPLICIT T-CHK",
        f"  {r} {B} T-BC {A} T-TEAM NHEAT-EXPLICIT T-CHK",
        "  LOOP ;",
        "T-RUN",
        "T-TEAM NTEAM-JOBS T-S",
        "T-TEAM NTEAM-OWNED T-S",
    ]
    records, data = program.run()
    assert all(status == NUM_OK for _, status, _ in records[:-2])
    want = u0
    for _ in range(steps):
        want = ref.update(r, want, bc)
    assert as_array(u0, data["a"]).lanes == want.lanes
    assert team_counters(records) == (steps * (CORES - 1), 0)


# ---------------------------------------------------------------------------
# A busy worker core
# ---------------------------------------------------------------------------

def test_a_busy_worker_core_leaves_its_share_to_the_owner() -> None:
    fmt, nx, ny = ref.FP64, 64, 12
    rng = random.Random("team-busy")
    x = random_array(rng, fmt, nx, ny)
    y = random_array(rng, fmt, nx, ny)
    bc = ref.Boundary()
    c = scalar(fmt, 0.125)

    program = MACHINE.program()
    X = program.array(x)
    Y = program.array(y)
    OUT = program.array(random_array(rng, fmt, nx, ny), "out")
    place_boundary(program, bc)
    program.lines += [
        team_init(CORES, max(ref.ws_bytes(x), stencil_ws(x))),
        # Core 3 is still spinning when the dot product is dispatched.
        f"' T-SPIN 3 CORE-RUN {X} {Y} T-TEAM NT-DOT T-R",
        f"{c} {X} T-BC {OUT} T-TEAM NT-UPDATE T-S",
        "3 CORE-WAIT",
        "T-TEAM NTEAM-JOBS T-S",
        "T-TEAM NTEAM-OWNED T-S",
    ]
    records, data = program.run()
    dot, update = records[-4], records[-3]
    assert dot == ("R", NUM_OK, ref.reduce_dot(x, y))
    assert update == ("S", NUM_OK, None)
    assert as_array(x, data["out"]).lanes == ref.update(c, x, bc).lanes
    jobs, owned = team_counters(records)
    assert owned >= 1
    assert jobs + owned == worker_shares(blocks(x), CORES) + worker_shares(ny, CORES)


# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

def _team_memory() -> int:
    lines = ["T-TEAM-MEM U."]
    return int(program_output(MACHINE.snapshot.run(lines), lines).split()[0])


def test_team_sizes_and_init_refusals() -> None:
    memory = _team_memory()
    program = MACHINE.program()
    program.lines += [
        "0 64 NTEAM-BYTES T-S",
        "1 -1 NTEAM-BYTES T-S",
        "2 100 NTEAM-BYTES T-S",
        f"{memory} {TEAM_ARENA} 0 64 T-TEAM NTEAM-INIT T-S",
        f"{memory} {TEAM_ARENA} {CORES + 1} 64 T-TEAM NTEAM-INIT T-S",
        f"{memory + 8} {TEAM_ARENA - 64} 2 64 T-TEAM NTEAM-INIT T-S",
        f"{memory} 100 2 64 T-TEAM NTEAM-INIT T-S",
        f"{memory} {TEAM_ARENA} 2 64 T-TEAM NTEAM-INIT T-S",
        "T-TEAM NTEAM-CORES T-S",
    ]
    records, _ = program.run()
    assert [value for _, value, _ in records] == [
        0, 0, 2 * (128 + 256 + 192),
        E_RANGE, E_RANGE, E_ALIGN, E_SPACE, NUM_OK, 2,
    ]


def test_team_kernels_refuse_bad_calls_without_running() -> None:
    fmt, nx, ny = ref.FP64, 9, 4
    rng = random.Random("team-refuse")
    x = random_array(rng, fmt, nx, ny)
    narrow = random_array(rng, fmt, nx - 1, ny)
    out = random_array(rng, fmt, nx, ny)
    memory = _team_memory()
    s = scalar(fmt, 2.0)

    program = MACHINE.program()
    X = program.array(x, "x")
    N = program.array(narrow)
    Z = program.array(out, "z")
    INSIDE = program.describe(memory, x)
    place_boundary(program, ref.Boundary())
    program.lines += [
        team_init(CORES, 64),
        f"{X} {N} {Z} T-TEAM NT-ADD T-S",
        f"{X} {X} {INSIDE} T-TEAM NT-SUB T-S",
        f"{X} {N} T-TEAM NT-DOT T-R",
        f"{X} T-TEAM NT-SUM T-R",
        f"{X} T-BC {Z} T-TEAM NT-LAPLACE T-S",
        f"{s} {X} T-BC {Z} T-TEAM NT-UPDATE T-S",
        team_init(CORES, 0),
        f"{s} {Z} T-TEAM NT-SCALE T-S",
        f"{s} {X} {Z} T-TEAM NT-AXPY T-S",
        team_init(CORES, max(ref.ws_bytes(x), stencil_ws(x))),
        f"{INSIDE} T-TEAM NT-SUM T-R",
        f"{X} T-BC {INSIDE} T-TEAM NT-LAPLACE T-S",
        f"5 {X} 8 + !",
        f"{X} T-TEAM NT-SUM T-R",
        f"{s} {X} T-TEAM NT-FILL T-S",
        "T-TEAM NTEAM-JOBS T-S",
        "T-TEAM NTEAM-OWNED T-S",
    ]
    records, data = program.run()
    statuses = [value for _, value, _ in records]
    inits = 5  # four descriptors and the team
    assert statuses[:inits] == [NUM_OK] * inits
    assert statuses[inits:] == [
        E_SHAPE, E_OVERLAP, E_SHAPE, E_SPACE, E_SPACE, E_SPACE,
        NUM_OK, E_SPACE, E_SPACE,
        NUM_OK, E_OVERLAP, E_OVERLAP,
        E_FORMAT, E_FORMAT,
        0, 0,
    ]
    assert as_array(x, data["x"]).lanes == x.lanes
    assert as_array(out, data["z"]).lanes == out.lanes
