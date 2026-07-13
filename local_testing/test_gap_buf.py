#!/usr/bin/env python3
"""Focused emulator tests for incremental gap-buffer line indexing."""

from __future__ import annotations

import os
import random
import re
import sys
import time
from pathlib import Path


AKASHIC_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = AKASHIC_ROOT.parent
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PROJECT_ROOT / "megapad"))

sys.path.insert(0, str(MEGAPAD_ROOT))

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402


BIOS_PATH = MEGAPAD_ROOT / "bios.asm"
KDOS_PATH = MEGAPAD_ROOT / "kdos.f"
UTF8_PATH = AKASHIC_ROOT / "akashic" / "text" / "utf8.f"
GAP_PATH = AKASHIC_ROOT / "akashic" / "text" / "gap-buf.f"
UNDO_PATH = AKASHIC_ROOT / "akashic" / "text" / "undo.f"

_snapshot = None


def _load_forth_lines(path: Path) -> list[str]:
    lines = []
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("\\"):
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        lines.append(line)
    return lines


def _next_line(data: bytes, pos: int) -> bytes:
    end = data.find(b"\n", pos)
    return data[pos:end + 1] if end >= 0 else data[pos:]


def _cpu_state(cpu) -> dict:
    fields = (
        "pc", "psel", "xsel", "spsel", "flag_z", "flag_c", "flag_n",
        "flag_v", "flag_p", "flag_g", "flag_i", "flag_s", "d_reg",
        "q_out", "t_reg", "ivt_base", "ivec_id", "trap_addr", "halted",
        "idle", "cycle_count", "_ext_modifier",
    )
    return {name: getattr(cpu, name) for name in fields} | {"regs": list(cpu.regs)}


def _restore_cpu(cpu, state: dict):
    cpu.regs[:] = state["regs"]
    for name, value in state.items():
        if name != "regs":
            setattr(cpu, name, value)


def _capture_uart(system: MegapadSystem) -> bytearray:
    output = bytearray()
    system.uart.on_tx = output.append
    return output


def _run_input(system: MegapadSystem, payload: bytes, max_steps: int) -> int:
    pos = 0
    steps = 0
    while steps < max_steps:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(payload):
                break
            chunk = _next_line(payload, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
            continue
        executed = system.run_batch(min(100_000, max_steps - steps))
        steps += max(executed, 1)
    return steps


def _build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    started = time.perf_counter()
    bios = assemble(BIOS_PATH.read_text())
    source = (
        _load_forth_lines(KDOS_PATH)
        + ["ENTER-USERLAND"]
        + _load_forth_lines(UTF8_PATH)
        + _load_forth_lines(GAP_PATH)
        + _load_forth_lines(UNDO_PATH)
    )
    system = MegapadSystem(ram_size=1 << 20, ext_mem_size=16 << 20)
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    steps = _run_input(system, ("\n".join(source) + "\n").encode(), 1_500_000_000)
    text = output.decode("utf-8", errors="replace")
    compile_errors = [
        line for line in text.splitlines()
        if "?" in line
        and ("not found" in line.lower() or "undefined" in line.lower())
    ]
    assert not compile_errors, "Forth compile errors:\n" + "\n".join(compile_errors[-10:])
    assert system.cpu.idle and not system.uart.has_rx_data, (
        f"snapshot build did not quiesce after {steps:,} steps"
    )
    _snapshot = (
        bios,
        bytes(system.cpu.mem),
        bytes(system._ext_mem),
        _cpu_state(system.cpu),
    )
    print(
        f"gap-buffer snapshot: {steps:,} steps in "
        f"{time.perf_counter() - started:.2f}s"
    )
    return _snapshot


def _run_forth(lines: list[str], max_steps: int = 400_000_000) -> str:
    bios, memory, ext_memory, state = _build_snapshot()
    system = MegapadSystem(ram_size=1 << 20, ext_mem_size=16 << 20)
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    _run_input(system, b"", 5_000_000)
    system.cpu.mem[:len(memory)] = memory
    system._ext_mem[:len(ext_memory)] = ext_memory
    _restore_cpu(system.cpu, state)
    output.clear()
    payload = ("\n".join(lines) + "\nBYE\n").encode()
    _run_input(system, payload, max_steps)
    return output.decode("utf-8", errors="replace")


def _set_source(data: bytes) -> list[str]:
    lines = []
    for index, value in enumerate(data):
        lines.append(f"{value} _TG-SRC {index} + C!")
    return lines


def _expected_checks(data: bytes) -> list[str]:
    offsets = [0] + [index + 1 for index, value in enumerate(data) if value == 10]
    lines = [
        f"_TG-GB @ GB-LEN {len(data)} = _TG-ASSERT",
        f"_TG-GB @ GB-LINES {len(offsets)} = _TG-ASSERT",
    ]
    lines.extend(
        f"{line_no} _TG-GB @ GB-LINE-OFF {offset} = _TG-ASSERT"
        for line_no, offset in enumerate(offsets)
    )
    lengths = [
        offsets[index + 1] - offset - 1
        if index + 1 < len(offsets) else len(data) - offset
        for index, offset in enumerate(offsets)
    ]
    lines.extend(
        f"{line_no} _TG-GB @ GB-LINE-LEN {length} = _TG-ASSERT"
        for line_no, length in enumerate(lengths)
    )
    lines.extend(
        f"{index} _TG-GB @ GB-BYTE@ {value} = _TG-ASSERT"
        for index, value in enumerate(data)
    )
    lines.append("DEPTH _TG-DEPTH @ = _TG-ASSERT")
    return lines


def _insert(model: bytearray, pos: int, data: bytes) -> list[str]:
    model[pos:pos] = data
    return (
        _set_source(data)
        + [
            f"{pos} _TG-GB @ GB-MOVE!",
            f"_TG-SRC {len(data)} _TG-GB @ GB-INS",
        ]
        + _expected_checks(bytes(model))
    )


def _delete(model: bytearray, pos: int, count: int, backwards: bool) -> list[str]:
    cursor = pos
    if backwards:
        actual = min(count, cursor)
        start = cursor - actual
        deleted = bytes(model[start:cursor])
        del model[start:cursor]
        word = "GB-BS"
    else:
        actual = min(count, len(model) - cursor)
        start = cursor
        deleted = bytes(model[cursor:cursor + actual])
        del model[cursor:cursor + actual]
        word = "GB-DEL"
    lines = [
        f"{cursor} _TG-GB @ GB-MOVE!",
        f"{count} _TG-GB @ {word} _TG-DEL-U ! _TG-DEL-A !",
        f"_TG-DEL-U @ {actual} = _TG-ASSERT",
    ]
    lines.extend(
        f"_TG-DEL-A @ {index} + C@ {value} = _TG-ASSERT"
        for index, value in enumerate(deleted)
    )
    return lines + _expected_checks(bytes(model))


def _correctness_program() -> list[str]:
    lines = [
        "VARIABLE _TG-FAILS",
        "VARIABLE _TG-CHECKS",
        "VARIABLE _TG-DEPTH",
        "VARIABLE _TG-ARENA",
        "VARIABLE _TG-GB",
        "VARIABLE _TG-UNDO",
        "VARIABLE _TG-DEL-A",
        "VARIABLE _TG-DEL-U",
        "VARIABLE _TG-T0",
        "VARIABLE _TG-X0",
        "VARIABLE _TG-XFREE",
        "CREATE _TG-SRC 2048 ALLOT",
        "CREATE _TG-COPY 2048 ALLOT",
        ": _TG-ASSERT  1 _TG-CHECKS +! 0= IF 1 _TG-FAILS +! .\" FAIL# \" _TG-CHECKS @ . CR THEN ;",
        ": _TG-XMEM-AVAIL  0 _TG-XFREE ! XMEM-FL @ BEGIN DUP WHILE DUP @ _TG-XFREE +! 8 + @ REPEAT DROP XMEM-FREE _TG-XFREE @ + ;",
        "0 _TG-FAILS ! 0 _TG-CHECKS ! DEPTH _TG-DEPTH !",
        "_TG-XMEM-AVAIL _TG-X0 !",
        "524288 A-XMEM ARENA-NEW DUP 0= _TG-ASSERT DROP _TG-ARENA !",
        "16 _TG-ARENA @ GB-NEW _TG-GB !",
    ]

    model = bytearray(b"aa\nbb\ncc")
    lines += _set_source(model)
    lines += [f"_TG-SRC {len(model)} _TG-GB @ GB-SET"]
    lines += _expected_checks(model)
    lines += [
        "4 _TG-GB @ GB-MOVE!",
        "1 _TG-COPY 6 _TG-GB @ GB-COPY 6 = _TG-ASSERT",
    ]
    lines += [
        f"_TG-COPY {index} + C@ {value} = _TG-ASSERT"
        for index, value in enumerate(model[1:7])
    ]
    lines += ["999 _TG-COPY 4 _TG-GB @ GB-COPY 0= _TG-ASSERT"]

    lines += _insert(model, 2, b"XYZ")
    lines += _insert(model, 5, "\u00e9\n\u263a\n".encode())
    line_start = model.index(10) + 1
    lines += _insert(model, line_start, b"\nQ")
    lines += _insert(model, len(model), b"tail\n")
    lines += _delete(model, 1, 9, backwards=False)
    lines += _delete(model, len(model), 7, backwards=True)
    lines += _delete(model, 0, 999, backwards=True)
    lines += _delete(model, 0, 2, backwards=False)

    # Deterministic model-based mutations exercise boundary combinations that
    # are easy to miss in hand-written insert/delete cases.
    rng = random.Random(0xA5A51C)
    model = bytearray(b"head\nmid\ntail")
    lines += _set_source(model)
    lines += [f"_TG-SRC {len(model)} _TG-GB @ GB-SET"]
    lines += _expected_checks(model)
    inserts = (b"x", b"\n", b"A\nB", "\u00e9".encode(), b"\n\n", b"123")
    for _ in range(60):
        if len(model) < 80 and rng.randrange(3) == 0:
            pos = rng.randrange(len(model) + 1)
            lines += _insert(model, pos, rng.choice(inserts))
            continue
        backwards = bool(rng.randrange(2))
        cursor = rng.randrange(len(model) + 1)
        lines += _delete(model, cursor, rng.randrange(9), backwards)

    # Codepoint deletion must preserve byte-offset line indexes.
    model = bytearray("A\u00e9\n\u263aZ".encode())
    lines += _set_source(model)
    lines += [f"_TG-SRC {len(model)} _TG-GB @ GB-SET"]
    lines += _expected_checks(model)
    cp_start = 1
    deleted = bytes(model[cp_start:cp_start + 2])
    del model[cp_start:cp_start + 2]
    lines += [
        f"{cp_start} _TG-GB @ GB-MOVE!",
        "_TG-GB @ GB-DEL-CP _TG-DEL-U ! _TG-DEL-A !",
        "_TG-DEL-U @ 2 = _TG-ASSERT",
    ]
    lines += [
        f"_TG-DEL-A @ {index} + C@ {value} = _TG-ASSERT"
        for index, value in enumerate(deleted)
    ]
    lines += _expected_checks(model)
    smile = "\u263a".encode()
    smile_end = model.index(smile) + len(smile)
    del model[smile_end - len(smile):smile_end]
    lines += [
        f"{smile_end} _TG-GB @ GB-MOVE!",
        "_TG-GB @ GB-BS-CP _TG-DEL-U ! _TG-DEL-A !",
        "_TG-DEL-U @ 3 = _TG-ASSERT",
    ]
    lines += _expected_checks(model)

    # One insertion must be able to grow a 256-entry line index repeatedly.
    lines += [
        "_TG-GB @ GB-CLEAR",
        "_TG-SRC 600 10 FILL",
        "_TG-SRC 600 _TG-GB @ GB-INS",
        "_TG-GB @ GB-LINES 601 = _TG-ASSERT",
        "_TG-GB @ _GB-O-LCAP + @ 601 >= _TG-ASSERT",
        ": _TG-CHECK-DENSE  601 0 DO I _TG-GB @ GB-LINE-OFF I = _TG-ASSERT LOOP ;",
        "_TG-CHECK-DENSE",
        "0 _TG-GB @ GB-MOVE!",
        "600 _TG-GB @ GB-DEL 2DROP",
    ]
    lines += _expected_checks(b"")

    # Exercise the exact GB-INS/GB-DEL paths used by undo and redo.
    model = bytearray(b"one\ntwo")
    lines += _set_source(model)
    lines += [
        f"_TG-SRC {len(model)} _TG-GB @ GB-SET",
        "UNDO-NEW _TG-UNDO !",
    ]
    insertion = b"X\nY"
    pos = 2
    lines += _set_source(insertion)
    lines += [
        f"{pos} _TG-GB @ GB-MOVE!",
        f"UNDO-T-INS {pos} _TG-SRC {len(insertion)} _TG-UNDO @ UNDO-PUSH",
        f"_TG-SRC {len(insertion)} _TG-GB @ GB-INS",
    ]
    model[pos:pos] = insertion
    lines += _expected_checks(model)
    lines += ["_TG-GB @ _TG-UNDO @ UNDO-UNDO _TG-ASSERT"]
    model[pos:pos + len(insertion)] = b""
    lines += _expected_checks(model)
    lines += ["_TG-GB @ _TG-UNDO @ UNDO-REDO _TG-ASSERT"]
    model[pos:pos] = insertion
    lines += _expected_checks(model)
    lines += [
        "_TG-UNDO @ UNDO-CLEAR",
        "DEPTH _TG-DEPTH @ = _TG-ASSERT",
        "_TG-UNDO @ UNDO-FREE",
    ]

    # Compare the incremental single-byte path with the retained bulk rebuild.
    lines += [
        "_TG-ARENA @ 60000 ARENA-ALLOT DUP 60000 65 FILL",
        "DUP 60000 _TG-GB @ GB-SET",
        "30000 _TG-GB @ GB-MOVE!",
        "90 _TG-SRC C!",
        "CYCLES _TG-T0 !",
        "_TG-SRC 1 _TG-GB @ GB-INS",
        'CYCLES _TG-T0 @ - ." GB-INC-CYCLES " . CR',
        "_TG-GB @ _GB-T ! CYCLES _TG-T0 ! _GB-REBUILD-LINES",
        'CYCLES _TG-T0 @ - ." GB-FULL-CYCLES " . CR',
        "_TG-GB @ GB-FREE",
        "_TG-ARENA @ ARENA-DESTROY",
        "_TG-XMEM-AVAIL _TG-X0 @ = _TG-ASSERT",
        '_TG-FAILS @ 0= IF ." GB TEST PASS " ELSE ." GB TEST FAIL " THEN '
        "_TG-CHECKS @ . _TG-FAILS @ . CR",
    ]
    return lines


def test_incremental_line_index():
    output = _run_forth(_correctness_program())
    summary = re.search(r"GB TEST PASS\s+(\d+)\s+0", output)
    assert summary, output[-4000:]
    assert int(summary.group(1)) > 500
    match_inc = re.search(r"GB-INC-CYCLES\s+(\d+)", output)
    match_full = re.search(r"GB-FULL-CYCLES\s+(\d+)", output)
    assert match_inc and match_full, output[-4000:]
    incremental = int(match_inc.group(1))
    full = int(match_full.group(1))
    assert full > incremental * 5, (incremental, full, output[-1000:])
    print(f"incremental={incremental:,} full-rebuild={full:,} cycles")


if __name__ == "__main__":
    test_incremental_line_index()
