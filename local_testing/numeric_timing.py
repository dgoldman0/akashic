#!/usr/bin/env python3
"""Emulator cycle measurements behind docs/numeric/scientific-computing-plan.md.

Each subcommand prints cycles read with PERF-CYCLES on core 0, with the
modules compiled the production way (forth_snapshot.py, BIOS JIT on):

  forth      cost of Forth constructs and BIOS tile words under the JIT
  regions    tile operations and CMOVE by memory region (HBW, external RAM)
  kernels    cycles per tile of the BLAS-1 and stencil kernels
  split      a stencil call's per-call, per-row, and per-tile cost
  steps      explicit and implicit heat steps on one and four cores
  dispatch   team dispatch and worker-job costs on four cores
  decimal    numeric/decimal.f conversions

"steps" and "dispatch" take --strict to run the measured program on the
strict-cycle model, which keeps one clock for all cores and models the
shared bus.  The functional scheduler runs the cores in turn, so its
multi-core timings include waits that the hardware would not have.  The
strict model cannot run the scalar FP64 words, so it times only explicit
steps.

Set MEGAPAD_ROOT as for the tests.  "steps" and "dispatch" boot four cores
and take minutes; run one measurement at a time.

    python3 numeric_timing.py kernels
    python3 numeric_timing.py steps --strict
"""

from __future__ import annotations

import argparse
import random
import re
import struct

import forth_snapshot as fs
import numeric_harness as nh
import numeric_reference as ref
from numeric_harness import NumericMachine, array_of, scalar


FP64 = ref.FP64
CYCLES = ': T-CY ( xt -- ) PERF-CYCLES >R EXECUTE PERF-CYCLES R> - ." @" . ;'


def cycles(snapshot, definitions: dict[str, str], setup: tuple[str, ...] = ()) -> dict[str, int]:
    """Cycles of each body, run once as a word, in one program."""

    lines = list(setup)
    for i, body in enumerate(definitions.values()):
        lines += [f": T-B{i} {body} ;", f"' T-B{i} T-CY"]
    text = fs.program_output(snapshot.run(lines, max_steps=400_000_000), lines)
    values = [int(v) for v in re.findall(r"@(-?\d+) ", text)]
    assert len(values) == len(definitions), text[-400:]
    return dict(zip(definitions, values))


def show(results: dict[str, int], per: int = 1, unit: str = "cycles") -> None:
    for name, value in results.items():
        print(f"  {name:36s} {value / per:>14,.0f} {unit}")


def use_strict_cycles() -> None:
    """Run programs on the strict-cycle model from now on."""

    def run_input(system, payload, max_steps, output=None):
        pos, steps = 0, 0
        while steps < max_steps:
            if system.cpu.halted:
                break
            if system.cpu.idle and not system.uart.has_rx_data:
                if pos >= len(payload):
                    break
                chunk = fs._next_line(payload, pos)
                system.uart.inject_input(chunk)
                pos += len(chunk)
                continue
            stats = system.run_cycle_batch(200_000, max_instructions=100_000)
            steps += max(stats.instructions_executed, 1)
        return steps

    fs._run_input = run_input


# ---------------------------------------------------------------------------
# Measurements
# ---------------------------------------------------------------------------

def forth_costs(_args) -> None:
    """Loop bodies run 1000 times; the empty loop is subtracted."""

    snippets = [
        "", "5 DROP", "K64 DROP", "HA DROP", "HA 64 + DROP", "HA K64 + DROP",
        "HA [ K64 ] LITERAL + DROP", "HA @ DROP", "I DROP", "NOP", "XNOP EXECUTE",
        "1 2 3 2DROP DROP", "1 2 3 2 PICK 2DROP 2DROP", "1 2 3 ROT 2DROP DROP",
        "1 2 2DROP", "1 2 2DUP 2DROP 2DROP", "1 2 OVER 2DROP DROP", "1 >R R> DROP",
        "1 2 = DROP", "1 2 XOR DROP", "5 1+ DROP", "5 1 - DROP", "HA TSRC0!", "TADD",
        "TFMA", "HA HB 512 CMOVE",
    ]
    # K64 and HA are named constants; NOP is an empty colon word.
    bodies = {snippet or "(empty)": snippet for snippet in snippets}
    setup = ("JIT-RESET", "JIT-ON", "64 CONSTANT K64", "HBW-TALIGN 4096 HBW-ALLOT CONSTANT HA",
             "HA 1024 + CONSTANT HB", ": NOP ;", "' NOP CONSTANT XNOP")
    setup += tuple(f": L{i} 1000 0 DO {body} LOOP ;" for i, body in enumerate(bodies.values()))
    snapshot = fs.ForthSnapshot(("numeric/array.f",), prelude=setup + ("JIT-OFF", CYCLES))
    results = cycles(snapshot, {name: f"L{i}" for i, name in enumerate(bodies)},
                     ("7 TMODE! HA TSRC0! HA 64 + TSRC1! HA 128 + TDST!",))
    empty = results.pop("(empty)")
    print(f"  empty DO LOOP: {empty / 1000:.1f} cycles per pass; each body net of it:")
    show({name: value - empty for name, value in results.items()}, 1000)


def regions(_args) -> None:
    setup = ("HBW-TALIGN 8192 HBW-ALLOT CONSTANT HA",
             "8192 64 + XMEM-ALLOT 63 + -64 AND CONSTANT XA")
    snapshot = fs.ForthSnapshot(("numeric/array.f",), prelude=setup + (CYCLES,))
    bodies = {
        "100 TADD, HBW operands": "7 TMODE! HA TSRC0! HA 64 + TSRC1! HA 128 + TDST! 100 0 DO TADD LOOP",
        "100 TADD, external operands": "7 TMODE! XA TSRC0! XA 64 + TSRC1! XA 128 + TDST! 100 0 DO TADD LOOP",
        "100 CMOVE 64 bytes, HBW": "100 0 DO HA HA 1024 + 64 CMOVE LOOP",
        "100 CMOVE 1024 bytes, HBW": "100 0 DO HA HA 1024 + 1024 CMOVE LOOP",
        "100 CMOVE 1024 bytes, external to HBW": "100 0 DO XA HA 1024 + 1024 CMOVE LOOP",
    }
    show(cycles(snapshot, bodies))
    print("  PERF-EXTMEM counts only TACC image words in the emulator.")


def machine(num_cores: int = 1) -> NumericMachine:
    roots = ("numeric/team-blas1.f", "numeric/heat2d.f")
    prelude = nh.TEAM_PRELUDE + (
        "CREATE T-BC NBC-SIZE ALLOT",
        "CREATE T-STEP NHEAT-IMPLICIT-SIZE ALLOT",
        CYCLES,
    )
    return NumericMachine(roots, prelude=prelude, num_cores=num_cores)


def program_cycles(program, bodies: dict[str, str], lines: list[str] = ()) -> dict[str, int]:
    """Cycles of each body after the program's own lines and data."""

    program.lines += list(lines)
    for i, body in enumerate(bodies.values()):
        program.lines += [f": T-B{i} {body} ;", f"' T-B{i} T-CY"]

    def setup(system) -> None:
        for addr, data in program.writes:
            system._raw_mem_write_span(addr, data)

    output = program.machine.snapshot.run(program.lines, setup=setup)
    text = fs.program_output(output, program.lines)
    values = [int(v) for v in re.findall(r"@(-?\d+) ", text)]
    return dict(zip(bodies, values[-len(bodies):]))


def kernels(_args) -> None:
    rng = random.Random(1)
    x = array_of(FP64, 1024, 8, lambda i, j: rng.random())
    program = machine().program()
    X, Y, Z = program.array(x), program.array(x), program.array(x)
    ws = program.workspace(max(ref.ws_bytes(x), ref.stencil_ws_bytes(x)))
    a = scalar(FP64, 0.5)
    bodies = {
        "NV-ADD": f"{X} {Y} {Z} NV-ADD DROP",
        "NV-AXPY": f"{a} {X} {Y} {ws} NV-AXPY DROP",
        "NV-DOT": f"{X} {Y} {ws} NV-DOT 2DROP",
        "NV-SUM": f"{X} {ws} NV-SUM 2DROP",
        "NST-UPDATE": f"{a} {X} T-BC {Z} {ws} NST-UPDATE DROP",
        "NST-LAPLACE": f"{X} T-BC {Z} {ws} NST-LAPLACE DROP",
    }
    print("  1024x8 FP64 arrays in HBW, cycles per tile:")
    show(program_cycles(program, bodies, ["T-BC NBC-INIT"]), x.tiles)


def split(_args) -> None:
    """Fit cycles = call + rows * row + tiles * tile over four shapes."""

    shapes = [(8, 1), (8, 64), (512, 1), (512, 64)]
    program = machine().program()
    a = scalar(FP64, 0.2)
    ws = program.workspace(ref.stencil_ws_bytes(array_of(FP64, 512, 1, lambda i, j: 0.0)))
    bodies = {}
    for nx, ny in shapes:
        u = array_of(FP64, nx, ny, lambda i, j: 0.5)
        U, O = program.array(u), program.array(u)
        bodies[f"NST-UPDATE {nx}x{ny}"] = f"{a} {U} T-BC {O} {ws} NST-UPDATE DROP"
    got = list(program_cycles(program, bodies, ["T-BC NBC-INIT"]).values())
    tile = (got[2] - got[0]) / 63
    row = (got[1] - got[0]) / 63 - tile
    call = got[0] - row - tile
    print(f"  per call {call:,.0f}   per row {row:,.0f}   per tile {tile:,.0f} cycles")


def steps(args) -> None:
    team = machine(4)
    team.region("hbw")
    if args.strict:
        use_strict_cycles()
    rng = random.Random(5)
    for n in args.sizes:
        for cores in (1, 4):
            u = array_of(FP64, n, n, lambda i, j: rng.uniform(-1, 1))
            zeros = lambda k: array_of(FP64, k, 1, lambda i, j: 0.0)  # noqa: E731
            bc = ref.Boundary(zeros(n), zeros(n), zeros(n), zeros(n))
            need = 3 * u.nbytes + 2 * ref.storage_bytes(FP64, n, 1)
            program = team.program()
            U, O = program.array(u), program.array(u)
            lines = ["T-BC NBC-INIT"]
            for side, word in {"top": "NBC-TOP", "bottom": "NBC-BOTTOM",
                               "left": "NBC-LEFT", "right": "NBC-RIGHT"}.items():
                lines.append(f"{program.array(getattr(bc, side))} {word} T-BC NBC-DIRICHLET! DROP")
            scratch = program.reserve(need)
            lines += [
                nh.team_init(cores, max(ref.ws_bytes(u), ref.stencil_ws_bytes(u))),
                f"{scalar(FP64, 2.0)} {scalar(FP64, 1e-30)} {args.iterations} {scratch} {need} {U}"
                " T-STEP NHEAT-IMPLICIT-INIT DROP",
            ]
            bodies = {"explicit step": f"{scalar(FP64, 0.2)} {U} T-BC {O} T-TEAM NHEAT-EXPLICIT DROP"}
            if not args.strict:
                bodies[f"implicit step, {args.iterations} iterations"] = (
                    f"{U} T-BC {O} T-STEP T-TEAM NHEAT-IMPLICIT 2DROP")
            print(f"  {n}x{n} FP64, {cores} core{'s' * (cores > 1)}"
                  f" ({'strict' if args.strict else 'functional'}):")
            show(program_cycles(program, bodies, lines))


def dispatch(args) -> None:
    prelude = nh.TEAM_PRELUDE + (
        CYCLES,
        ": T-NOP-TASK ( task -- status ) DROP 0 ;",
        ": T-SET ( -- ) T-TEAM NTEAM-CORES 0 ?DO ['] T-NOP-TASK I T-TEAM NTEAM-TASK NTASK.XT ! LOOP ;",
        ": T-NOPW ( -- ) ;",
        "VARIABLE T-J",
    )
    snapshot = fs.ForthSnapshot(("numeric/team.f",), prelude=prelude, num_cores=4)
    snapshot.run(["1 DROP"])
    if args.strict:
        use_strict_cycles()

    def team(cores: int) -> tuple[str, ...]:
        return (nh.team_init(cores, 256).replace(" T-S", " DROP"), "T-SET")

    print(f"  {'strict' if args.strict else 'functional'} model:")
    show(cycles(snapshot, {"CORE-RUN and CORE-WAIT, empty word": "['] T-NOPW 1 CORE-RUN 1 CORE-WAIT"}))
    show(cycles(snapshot, {"dispatch, 4-core team, empty tasks": "T-TEAM NTEAM-DISPATCH DROP"}, team(4)))
    show(cycles(snapshot, {"dispatch, 1-core team, empty task": "T-TEAM NTEAM-DISPATCH DROP"}, team(1)))
    job = team(4) + ("1 T-TEAM _NTM-GEN + +!", "1 T-TEAM _NTM-RESET", "1 T-TEAM _NTM-JOB T-J !")
    show(cycles(snapshot, {
        "WJOB-VALID?": "T-J @ WJOB-VALID? DROP",
        "prepare a job": "1 T-TEAM _NTM-PREPARE DROP",
        "WJOB-SUBMIT": "1 T-J @ WJOB-SUBMIT DROP",
        "wait until done": "100000 0 DO T-J @ WJOB-POLL DROP WJOB-TERMINAL? IF UNLOOP EXIT THEN LOOP",
        "WJOB-REAP": "T-J @ WJOB-REAP DROP",
    }, job))


def decimal(_args) -> None:
    def f64(value: float) -> int:
        return struct.unpack("<Q", struct.pack("<d", value))[0]

    prelude = ("CREATE T-OUT 4096 ALLOT", "CREATE T-WS NWS-SIZE ALLOT",
               "HBW-TALIGN NDEC-WS-BYTES HBW-ALLOT NDEC-WS-BYTES T-WS NWS-INIT DROP", CYCLES)
    snapshot = fs.ForthSnapshot(("numeric/decimal.f",), prelude=prelude)
    fmt = "7 T-OUT 4096 T-WS NDEC-FORMAT 2DROP"
    show(cycles(snapshot, {
        "format 0.1": f"{f64(0.1)} {fmt}",
        "format 1/3": f"{f64(1 / 3)} {fmt}",
        "format 1e-300": f"{f64(1e-300)} {fmt}",
        "fixed 123.456 to 2 places": f"{f64(123.456)} 7 2 T-OUT 4096 T-WS NDEC-FIXED 2DROP",
        "parse 3.14159": 'S" 3.14159" 7 T-WS NDEC-PARSE 2DROP',
        "parse 0.30000000000000004": 'S" 0.30000000000000004" 7 T-WS NDEC-PARSE 2DROP',
        "parse 1e-300": 'S" 1e-300" 7 T-WS NDEC-PARSE 2DROP',
    }))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    for name, function in (("forth", forth_costs), ("regions", regions), ("kernels", kernels),
                           ("split", split), ("decimal", decimal)):
        commands.add_parser(name).set_defaults(run=function)
    for name, function in (("steps", steps), ("dispatch", dispatch)):
        command = commands.add_parser(name)
        command.add_argument("--strict", action="store_true")
        command.set_defaults(run=function)
        if name == "steps":
            command.add_argument("--sizes", type=int, nargs="+", default=[64, 128])
            command.add_argument("--iterations", type=int, default=5)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
