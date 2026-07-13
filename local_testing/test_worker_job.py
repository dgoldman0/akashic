#!/usr/bin/env python3
"""Focused full-core tests for concurrency/worker-job.f.

This test uses the supported sibling MegaPad checkout rather than the removed
``local_testing/emu`` copy.  It boots four full cores so the worker trampoline
and publication boundary are exercised, not merely parsed on core 0.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys
import time


PROJECT_ROOT = Path(__file__).resolve().parents[2]
AKASHIC_ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PROJECT_ROOT / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402


BIOS_PATH = MEGAPAD_ROOT / "bios.asm"
CLASS_F = AKASHIC_ROOT / "akashic" / "runtime" / "concurrency-class.f"
WORKER_F = AKASHIC_ROOT / "akashic" / "concurrency" / "worker-job.f"


def _forth_lines(path: Path) -> list[str]:
    source: list[str] = []
    for line in path.read_text().splitlines():
        # Coalesce complete colon definitions into one REPL submission.  A
        # backslash comment must be removed first or it would comment out the
        # rest of the coalesced definition.
        stripped = line.split("\\", 1)[0].strip()
        if not stripped or stripped.startswith("\\"):
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        source.append(stripped)
    # Keep every submitted line below the BIOS input-buffer limit while
    # reducing the otherwise dominant prompt/idle round trips.  Colon
    # compilation is deliberately allowed to span these packed lines.
    lines: list[str] = []
    packed = ""
    for line in source:
        candidate = f"{packed} {line}" if packed else line
        if len(candidate) <= 180:
            packed = candidate
        else:
            lines.append(packed)
            packed = line
    if packed:
        lines.append(packed)
    return lines


def _next_line(data: bytes, pos: int) -> bytes:
    newline = data.find(b"\n", pos)
    return data[pos : newline + 1] if newline >= 0 else data[pos:]


def _capture_uart(system: MegapadSystem) -> bytearray:
    output = bytearray()
    system.uart.on_tx = output.append
    return output


def _uart_text(output: bytearray) -> str:
    return "".join(
        chr(value) if 0x20 <= value < 0x7F or value in (9, 10, 13) else ""
        for value in output
    )


_CPU_FIELDS = (
    "pc", "psel", "xsel", "spsel", "flag_z", "flag_c", "flag_n",
    "flag_v", "flag_p", "flag_g", "flag_i", "flag_s", "d_reg",
    "q_out", "t_reg", "ivt_base", "ivec_id", "trap_addr", "halted",
    "idle", "cycle_count", "_ext_modifier",
)


def _save_cpu(cpu) -> dict:
    return {name: getattr(cpu, name) for name in _CPU_FIELDS} | {
        "regs": list(cpu.regs)
    }


def _restore_cpu(cpu, state: dict) -> None:
    cpu.regs[:] = state["regs"]
    for name in _CPU_FIELDS:
        setattr(cpu, name, state[name])


_snapshot: tuple[bytes, bytes, list[dict]] | None = None


def build_snapshot() -> None:
    global _snapshot
    if _snapshot is not None:
        return
    print("[*] Building four-core worker-job snapshot ...")
    started = time.monotonic()
    bios = assemble(BIOS_PATH.read_text())
    system = MegapadSystem(ram_size=1024 * 1024, num_cores=4)
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    # The contemporary monolithic KDOS source nearly fills the 1 MiB Forth
    # dictionary by itself.  This focused test loads the exact KDOS primitives
    # the library relies on over the real BIOS multicore words; production
    # image builds separately validate the complete REQUIRE closure.
    kdos_contract = [
        "VARIABLE CURRENT-TASK 0 CURRENT-TASK !",
        "1 CONSTANT T.READY",
        "2 CONSTANT T.RUNNING",
        "3 CONSTANT T.BLOCKED",
        ": T.STATUS! ! ;",
        ": YIELD? ;",
        ": LOCK BEGIN DUP SPIN@ 0<> WHILE REPEAT DROP ;",
        ": UNLOCK SPIN! ;",
        ": CORE-RUN WAKE-CORE ;",
        ": CORE-WAIT BEGIN DUP CORE-STATUS 0<> WHILE REPEAT DROP ;",
        "NCORES 4 MIN CONSTANT N-FULL-CORES",
        ": MS@ EPOCH@ ;",
        ": 0>= 0< INVERT ;",
        "CREATE _HANDLERS NCORES CELLS ALLOT _HANDLERS NCORES CELLS 0 FILL",
        ": HANDLER COREID CELLS _HANDLERS + ;",
        ": CATCH SP@ >R HANDLER @ >R RP@ HANDLER ! EXECUTE R> HANDLER ! R> DROP 0 ;",
        ": THROW ?DUP IF HANDLER @ RP! R> HANDLER ! R> SWAP >R SP! DROP R> THEN ;",
        "6 CONSTANT EVT-LOCK",
    ]
    payload = "\n".join(
        kdos_contract
        + _forth_lines(CLASS_F)
        + _forth_lines(WORKER_F)
    ) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    load_budget = 220_000_000
    while steps < load_budget:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(data):
                break
            chunk = _next_line(data, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
        ran = system.run_batch(min(100_000, load_budget - steps))
        steps += max(ran, 1)
    transcript = _uart_text(output)
    if not system.cpu.idle:
        raise RuntimeError(
            "worker-job load did not return to idle:\n" + transcript[-8000:]
        )
    errors = [
        line for line in transcript.splitlines()
        if "not found" in line.lower() or "stack underflow" in line.lower()
    ]
    if errors:
        raise RuntimeError(
            "worker-job snapshot failed:\n"
            + "\n".join(errors)
            + "\n--- transcript tail ---\n"
            + transcript[-12000:]
        )
    _snapshot = bios, bytes(system.cpu.mem), [_save_cpu(cpu) for cpu in system.cores]
    print(f"[*] Snapshot ready in {time.monotonic() - started:.1f}s")


def run_forth(lines: list[str], max_steps: int = 100_000_000) -> str:
    assert _snapshot is not None
    bios, memory, core_states = _snapshot
    system = MegapadSystem(ram_size=1024 * 1024, num_cores=4)
    output = _capture_uart(system)
    # Boot once before restoring the snapshot so accelerated MMIO/UART routing
    # is initialized on this fresh system object.
    system.load_binary(0, bios)
    system.boot()
    for _ in range(5_000_000):
        if system.cpu.idle and not system.uart.has_rx_data:
            break
        system.run_batch(10_000)
    system.cpu.mem[: len(memory)] = memory
    for cpu, state in zip(system.cores, core_states):
        _restore_cpu(cpu, state)
    tx_ring = system.cpu.regs[19]
    if 0 < tx_ring < len(memory):
        system.uart._tx_ring_base = tx_ring
    output.clear()

    data = ("\n".join(lines) + "\nBYE\n").encode()
    pos = 0
    steps = 0
    while steps < max_steps:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(data):
                break
            chunk = _next_line(data, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
        ran = system.run_batch(min(100_000, max_steps - steps))
        steps += max(ran, 1)
    transcript = _uart_text(output)
    if pos < len(data):
        raise RuntimeError(
            f"worker-job test input stalled at {pos}/{len(data)} bytes; "
            f"halted={system.cpu.halted} idle={system.cpu.idle}:\n{transcript[-4000:]}"
        )
    return transcript


passed = 0
failed = 0


def check(name: str, forth: list[str], expected: str) -> None:
    global passed, failed
    output = run_forth(forth)
    results: list[str] = []
    for raw in output.splitlines():
        line = raw.strip()
        if not line.endswith("ok"):
            continue
        fields = line[:-2].strip().split()
        if fields and all(re.fullmatch(r"-?\d+", field) for field in fields):
            results.extend(fields)
    actual = " ".join(results) + (" " if results else "")
    errors = ("Stack underflow", "Branch offset overflow", "not found")
    if actual == expected and not any(marker in output for marker in errors):
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(
            f"  FAIL  {name}\n"
            f"        expected {expected!r}\n"
            f"        actual   {actual!r}\n"
            f"        output   {output!r}"
        )


def main() -> int:
    build_snapshot()

    check(
        "execution classes separate worker and owner work",
        [
            "CCLASS-PURE CCLASS-WORKER? .",
            "CCLASS-SNAPSHOT-READ CCLASS-WORKER? .",
            "CCLASS-OWNER-COMMIT CCLASS-WORKER? .",
            "CCLASS-OWNER-COMMIT CCLASS-OWNER-ONLY? .",
        ],
        "-1 -1 0 -1 ",
    )

    setup = [
        "CREATE _WJ-IN 8 ALLOT",
        "CREATE _WJ-OUT 8 ALLOT",
        "CREATE _WJ-SCRATCH 8 ALLOT",
        "CREATE _WJ WJOB-SIZE ALLOT",
        ": _WJ-WORK  ( job -- )",
        "  DUP WJOB.IN-A @ @ 1+ OVER WJOB.OUT-A @ !",
        "  8 SWAP WJOB-OUTPUT-LEN! DROP 0 ;",
        "41 _WJ-IN ! 0 _WJ-OUT ! _WJ WJOB-INIT",
    ]
    check(
        "worker publishes output and terminal state",
        setup + [
            "' _WJ-WORK _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 7 99 _WJ WJOB-PREPARE .",
            "1 _WJ WJOB-SUBMIT .",
            "123 .",
            "1 CORE-WAIT",
            "_WJ WJOB-POLL . .",
            "_WJ-OUT @ . _WJ WJOB.OUT-U @ .",
            "_WJ WJOB-REAP .",
        ],
        "0 0 123 0 3 42 8 0 ",
    )

    check(
        "two supervised jobs run on distinct full cores",
        setup + [
            "CREATE _WJ-IN2 8 ALLOT CREATE _WJ-OUT2 8 ALLOT",
            "CREATE _WJ-SCRATCH2 8 ALLOT CREATE _WJ2 WJOB-SIZE ALLOT",
            "99 _WJ-IN2 ! _WJ2 WJOB-INIT",
            "' _WJ-WORK _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 8 101 _WJ WJOB-PREPARE .",
            "' _WJ-WORK _WJ-IN2 8 _WJ-OUT2 8 _WJ-SCRATCH2 8",
            "  CCLASS-PURE 9 102 _WJ2 WJOB-PREPARE .",
            "1 _WJ WJOB-SUBMIT . 2 _WJ2 WJOB-SUBMIT .",
            "1 CORE-WAIT 2 CORE-WAIT",
            "_WJ WJOB-POLL . . _WJ2 WJOB-POLL . .",
            "_WJ-OUT @ . _WJ-OUT2 @ .",
            "_WJ WJOB-REAP . _WJ2 WJOB-REAP .",
        ],
        "0 0 0 0 0 3 0 3 42 100 0 0 ",
    )

    check(
        "unsupported class and core fail closed",
        setup + [
            "' _WJ-WORK _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-OWNER-COMMIT 1 2 _WJ WJOB-PREPARE .",
            "_WJ WJOB-INIT",
            "' _WJ-WORK _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 1 2 _WJ WJOB-PREPARE .",
            "0 _WJ WJOB-SUBMIT .",
        ],
        "1 0 4 ",
    )

    check(
        "invalid generations and overlapping spans fail closed",
        setup + [
            "' _WJ-WORK _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 0 2 _WJ WJOB-PREPARE .",
            "_WJ WJOB-INIT",
            "' _WJ-WORK _WJ-IN 8 _WJ-IN 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 1 2 _WJ WJOB-PREPARE .",
        ],
        "1 1 ",
    )

    check(
        "worker nonzero result becomes failed result",
        setup + [
            ": _WJ-BOOM  DROP 73 ;",
            "' _WJ-BOOM _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 3 4 _WJ WJOB-PREPARE .",
            "1 _WJ WJOB-SUBMIT . 1 CORE-WAIT",
            "_WJ WJOB-POLL . . _WJ WJOB-REAP .",
        ],
        "0 0 73 4 0 ",
    )

    check(
        "worker throw is contained on its core",
        setup + [
            ": _WJ-THROW  DROP 74 THROW ;",
            "' _WJ-THROW _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 4 5 _WJ WJOB-PREPARE .",
            "1 _WJ WJOB-SUBMIT . 1 CORE-WAIT",
            "_WJ WJOB-POLL . . _WJ WJOB-REAP .",
        ],
        "0 0 74 4 0 ",
    )

    check(
        "cancelled prepared job never dispatches",
        setup + [
            "' _WJ-WORK _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-PURE 5 6 _WJ WJOB-PREPARE .",
            "_WJ WJOB-CANCEL . _WJ WJOB-POLL . .",
            "_WJ WJOB-REAP .",
        ],
        "0 0 0 5 0 ",
    )

    check(
        "generation and caller tag reject late result",
        setup + [
            "' _WJ-WORK _WJ-IN 8 _WJ-OUT 8 _WJ-SCRATCH 8",
            "  CCLASS-SNAPSHOT-READ 11 22 _WJ WJOB-PREPARE DROP",
            "11 22 _WJ WJOB-MATCH? .",
            "12 22 _WJ WJOB-MATCH? .",
            "11 23 _WJ WJOB-MATCH? .",
        ],
        "-1 0 0 ",
    )

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
