#!/usr/bin/env python3
"""Focused emulator regressions for the gap-buffer-backed textarea."""

from __future__ import annotations

import os
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
SOURCE_PATHS = [
    AKASHIC_ROOT / "akashic" / "text" / "utf8.f",
    AKASHIC_ROOT / "akashic" / "utils" / "uint-range.f",
    AKASHIC_ROOT / "akashic" / "utils" / "memory-span.f",
    AKASHIC_ROOT / "akashic" / "text" / "cell-width.f",
    AKASHIC_ROOT / "akashic" / "text" / "gap-buf.f",
    AKASHIC_ROOT / "akashic" / "text" / "undo.f",
    AKASHIC_ROOT / "akashic" / "tui" / "ansi.f",
    AKASHIC_ROOT / "akashic" / "utils" / "term.f",
    AKASHIC_ROOT / "akashic" / "tui" / "cell.f",
    AKASHIC_ROOT / "akashic" / "tui" / "screen.f",
    AKASHIC_ROOT / "akashic" / "tui" / "draw.f",
    AKASHIC_ROOT / "akashic" / "tui" / "region.f",
    AKASHIC_ROOT / "akashic" / "tui" / "widget.f",
    AKASHIC_ROOT / "akashic" / "tui" / "keys.f",
    AKASHIC_ROOT / "akashic" / "tui" / "semantic-collections.f",
    AKASHIC_ROOT / "akashic" / "tui" / "widgets" / "textarea.f",
]

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
    return data[pos : end + 1] if end >= 0 else data[pos:]


def _cpu_state(cpu) -> dict:
    fields = (
        "pc",
        "psel",
        "xsel",
        "spsel",
        "flag_z",
        "flag_c",
        "flag_n",
        "flag_v",
        "flag_p",
        "flag_g",
        "flag_i",
        "flag_s",
        "d_reg",
        "q_out",
        "t_reg",
        "ivt_base",
        "ivec_id",
        "trap_addr",
        "halted",
        "idle",
        "cycle_count",
        "_ext_modifier",
    )
    return {name: getattr(cpu, name) for name in fields} | {"regs": list(cpu.regs)}


def _restore_cpu(cpu, state: dict) -> None:
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
    source = _load_forth_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for path in SOURCE_PATHS:
        source.extend(_load_forth_lines(path))

    system = MegapadSystem(ram_size=1 << 20, ext_mem_size=16 << 20)
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    steps = _run_input(system, ("\n".join(source) + "\n").encode(), 1_500_000_000)
    text = output.decode("utf-8", errors="replace")
    compile_errors = [
        line
        for line in text.splitlines()
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
        f"textarea snapshot: {steps:,} steps in "
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
    system.cpu.mem[: len(memory)] = memory
    system._ext_mem[: len(ext_memory)] = ext_memory
    _restore_cpu(system.cpu, state)
    output.clear()
    payload = ("\n".join(lines) + "\nBYE\n").encode()
    _run_input(system, payload, max_steps)
    return output.decode("utf-8", errors="replace")


def _textarea_program() -> list[str]:
    lines = [
        "VARIABLE _TT-FAILS",
        "VARIABLE _TT-CHECKS",
        "VARIABLE _TT-ARENA",
        "VARIABLE _TT-GB",
        "VARIABLE _TT-SCR",
        "VARIABLE _TT-RGN",
        "VARIABLE _TT-W",
        "CREATE _TT-FLAT 1 ALLOT",
        "CREATE _TT-EV 24 ALLOT",
        ': _TT-ASSERT  1 _TT-CHECKS +! 0= IF 1 _TT-FAILS +! ." FAIL# " _TT-CHECKS @ . CR THEN ;',
        "0 _TT-FAILS ! 0 _TT-CHECKS !",
        "262144 A-XMEM ARENA-NEW DUP 0= _TT-ASSERT DROP _TT-ARENA !",
        "32 _TT-ARENA @ GB-NEW _TT-GB !",
        "20 6 SCR-NEW DUP _TT-SCR ! SCR-USE",
        "1 2 3 8 RGN-NEW _TT-RGN !",
        "_TT-RGN @ _TT-FLAT 1 TXTA-NEW _TT-W !",
        "_TT-GB @ _TT-W @ TXTA-BIND-GB",
        "0 2 _TT-W @ TXTA-GUTTER!",
        "_TT-W @ WDG-FOCUS-SET",
        'S" abcdefghijklmnopqrst" _TT-W @ TXTA-SET-TEXT',
        "SCR-CLEAR _TT-W @ WDG-DRAW",
        "_TT-W @ TXTA-SCROLL-X@ 0> _TT-ASSERT",
        # The content origin must show the codepoint at the horizontal
        # offset, not merely update the scroll counter while drawing column 0.
        "1 4 SCR-GET CELL-CP@ _TT-W @ TXTA-SCROLL-X@ _TT-GB @ GB-BYTE@ = _TT-ASSERT",
    ]

    # A long logical line must be horizontally clipped, not continued as
    # implicit soft-wrapped text on the next viewport row.
    for col in range(4, 10):
        lines.append(f"2 {col} SCR-GET CELL-CP@ 32 = _TT-ASSERT")

    lines += [
        "KEY-T-SPECIAL _TT-EV !",
        "KEY-ENTER _TT-EV 8 + !",
        "0 _TT-EV 16 + !",
        "_TT-EV _TT-W @ WDG-HANDLE _TT-ASSERT",
        "_TT-W @ TXTA-CURSOR-LINE 1 = _TT-ASSERT",
        "_TT-W @ TXTA-CURSOR-COL 0= _TT-ASSERT",
        "SCR-CLEAR _TT-W @ WDG-DRAW",
        "_TT-W @ TXTA-SCROLL-X@ 0= _TT-ASSERT",
        # The region begins at screen (1,2), with a two-column gutter, so
        # the second logical line's content origin is absolute cell (2,4).
        "2 4 SCR-GET CELL-CP@ 32 = _TT-ASSERT",
        "CELL-A-REVERSE 2 4 SCR-GET CELL-HAS-ATTR? _TT-ASSERT",
        '_TT-FAILS @ 0= IF ." TEXTAREA TEST PASS " ELSE ." TEXTAREA TEST FAIL " THEN _TT-CHECKS @ . _TT-FAILS @ . CR',
    ]
    return lines


def _textarea_semantic_program() -> list[str]:
    """Exercise canonical flat/GB TEXT_AREA capture without a Desk fixture."""

    return [
        "VARIABLE _TS-FAILS",
        "VARIABLE _TS-CHECKS",
        "VARIABLE _TS-DEPTH",
        "VARIABLE _TS-ARENA",
        "VARIABLE _TS-GB",
        "VARIABLE _TS-SCR",
        "VARIABLE _TS-RGN",
        "VARIABLE _TS-W",
        "VARIABLE _TS-U",
        "CREATE _TS-NL 1 ALLOT",
        "CREATE _TS-FLAT 4096 ALLOT",
        "CREATE _TS-LONG 1301 ALLOT",
        "CREATE _TS-BUILDER-STORAGE USCOL-BUILDER-SIZE 7 + ALLOT",
        "CREATE _TS-OUT-A-STORAGE 8192 7 + ALLOT",
        "CREATE _TS-OUT-B-STORAGE 8192 7 + ALLOT",
        "CREATE _TS-WORK-STORAGE 128 7 + ALLOT",
        "CREATE _TS-SUMMARY-STORAGE USCOL-SUMMARY-SIZE 7 + ALLOT",
        ": _TS-BUILDER _TS-BUILDER-STORAGE 7 + -8 AND ;",
        ": _TS-OUT-A _TS-OUT-A-STORAGE 7 + -8 AND ;",
        ": _TS-OUT-B _TS-OUT-B-STORAGE 7 + -8 AND ;",
        ": _TS-WORK _TS-WORK-STORAGE 7 + -8 AND ;",
        ": _TS-SUMMARY _TS-SUMMARY-STORAGE 7 + -8 AND ;",
        ': _TS-ASSERT 1 _TS-CHECKS +! 0= IF 1 _TS-FAILS +! ." SEM ASSERT " _TS-CHECKS @ . CR THEN ;',
        ": _TS-OK USCOL-S-OK = _TS-ASSERT ;",
        ": _TS-STACK DEPTH _TS-DEPTH @ = _TS-ASSERT ;",
        ": _TS-SAME? ( a b u -- flag ) 0 ?DO 2DUP I + C@ SWAP I + C@ <> IF 2DROP 0 UNLOOP EXIT THEN LOOP 2DROP -1 ;",
        "0 _TS-FAILS ! 0 _TS-CHECKS !",
        "10 _TS-NL C!",
        "262144 A-XMEM ARENA-NEW DUP 0= _TS-ASSERT DROP _TS-ARENA !",
        "4096 _TS-ARENA @ GB-NEW _TS-GB !",
        "20 10 SCR-NEW DUP _TS-SCR ! SCR-USE",
        "1 2 3 8 RGN-NEW _TS-RGN !",
        "_TS-RGN @ _TS-FLAT 4096 TXTA-NEW _TS-W !",
        "0 2 _TS-W @ TXTA-GUTTER!",
        "_TS-W @ WDG-FOCUS-SET",
        'S" zero" _TS-W @ TXTA-SET-TEXT',
        "_TS-NL 1 _TS-W @ TXTA-INS-STR",
        'S" one" _TS-W @ TXTA-INS-STR',
        "_TS-NL 1 _TS-W @ TXTA-INS-STR",
        'S" αβγδεζη" _TS-W @ TXTA-INS-STR',
        "_TS-NL 1 _TS-W @ TXTA-INS-STR",
        'S" three" _TS-W @ TXTA-INS-STR',
        "_TS-NL 1 _TS-W @ TXTA-INS-STR",
        'S" four" _TS-W @ TXTA-INS-STR',
        # Cursor is at the end of row 3; row 0 is an off-viewport anchor.
        "29 _TS-W @ _TXTA-O-CURSOR + !",
        "0 _TS-W @ _TXTA-O-SEL-ANCHOR + !",
        "1 _TS-W @ TXTA-SCROLL-SET",
        "1 _TS-W @ TXTA-SCROLL-X!",
        "SCR-CLEAR _TS-W @ WDG-DRAW",
        "DEPTH _TS-DEPTH !",
        # Exact measure, one-byte-short refusal, and unpublished length cell.
        "101 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-MEASURE",
        "DUP _TS-OK DROP DUP 464 = _TS-ASSERT _TS-U !",
        "_TS-STACK",
        "_TS-OUT-A _TS-U @ 165 FILL",
        "101 _TS-OUT-A _TS-U @ 1- _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-CAPTURE",
        "USCOL-S-CAPACITY = _TS-ASSERT 0= _TS-ASSERT",
        "_TS-OUT-A @ 0= _TS-ASSERT",
        "_TS-OUT-A _TS-U @ 1- + C@ 165 = _TS-ASSERT",
        "_TS-STACK",
        # Successful flat-buffer capture and the native/deep shape proof.
        "101 _TS-OUT-A _TS-U @ _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-CAPTURE",
        "DUP _TS-OK DROP _TS-U @ = _TS-ASSERT",
        "_TS-OUT-A USCOL-ENTRY-BYTES@ _TS-U @ = _TS-ASSERT",
        "_TS-OUT-A USCOL-ENTRY-FAMILY@ USCOL-F-TEXT-AREA = _TS-ASSERT",
        "_TS-OUT-A USCOL-ENTRY-KEY@ 101 = _TS-ASSERT",
        "_TS-OUT-A USCOL-ROOT-ROW@ 0= _TS-ASSERT",
        "_TS-OUT-A USCOL-ROOT-COLUMN@ 2 = _TS-ASSERT",
        "_TS-OUT-A USCOL-ROOT-HEIGHT@ 3 = _TS-ASSERT",
        "_TS-OUT-A USCOL-ROOT-WIDTH@ 6 = _TS-ASSERT",
        "_TS-OUT-A USCOL-ROOT-STATE@ 7 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-ROWS@ 5 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-COLUMNS@ 7 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-VIEWPORT-ROW@ 1 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-VIEWPORT-COLUMN@ 1 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-VIEWPORT-ROWS@ 3 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-VIEWPORT-COLUMNS@ 6 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-PRIMARY-KEY@ 4 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-ANCHOR-KEY@ 1 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-PRIMARY-OFFSET@ 5 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-ANCHOR-OFFSET@ 0= _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-ITEM-COUNT@ 4 = _TS-ASSERT",
        "_TS-OUT-A USCOL-TEXT-FIRST DUP USCOL-ITEM-KEY@ 1 = _TS-ASSERT",
        "DUP USCOL-ITEM-ROW@ 0= _TS-ASSERT",
        "DUP USCOL-ITEM-TEXT-BYTES@ 4 = _TS-ASSERT",
        "USCOL-ITEM-NEXT DUP USCOL-ITEM-KEY@ 2 = _TS-ASSERT",
        "DUP USCOL-ITEM-ROW@ 1 = _TS-ASSERT",
        "USCOL-ITEM-NEXT DUP USCOL-ITEM-KEY@ 3 = _TS-ASSERT",
        "DUP USCOL-ITEM-ROW@ 2 = _TS-ASSERT",
        "DUP USCOL-ITEM-TEXT-BYTES@ 14 = _TS-ASSERT",
        "USCOL-ITEM-NEXT DUP USCOL-ITEM-KEY@ 4 = _TS-ASSERT",
        "DUP USCOL-ITEM-ROW@ 3 = _TS-ASSERT DROP",
        "_TS-OUT-A _TS-U @ _TS-WORK 128 _TS-SUMMARY USCOL-ENTRY-VALIDATE _TS-OK",
        "_TS-SUMMARY USCOL-SUMMARY-ITEM-COUNT@ 4 = _TS-ASSERT",
        "_TS-SUMMARY USCOL-SUMMARY-UTF8-BYTES@ 26 = _TS-ASSERT",
        "101 _TS-FLAT _TS-U @ _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-CAPTURE",
        "USCOL-S-INVALID = _TS-ASSERT 0= _TS-ASSERT",
        "_TS-FLAT C@ 122 = _TS-ASSERT",
        "_TS-STACK",
        # Rebind the exact same ordinary content to a split gap buffer.  The
        # neutral bytes must be identical, including scalar positions.
        "_TS-FLAT 34 _TS-GB @ GB-SET",
        "_TS-GB @ _TS-W @ TXTA-BIND-GB",
        "29 _TS-GB @ GB-MOVE!",
        "101 _TS-OUT-B 8192 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-CAPTURE",
        "DUP _TS-OK DROP DUP _TS-U @ = _TS-ASSERT DROP",
        "_TS-OUT-A _TS-OUT-B _TS-U @ _TS-SAME? _TS-ASSERT",
        "_TS-STACK",
        # A line larger than the legacy 1024-byte draw scratch is copied in
        # full across both physical sides of the gap, with no producer cap.
        "120 _TS-LONG C!",
        "_TS-LONG _TS-LONG 1+ 1 CMOVE",
        "_TS-LONG _TS-LONG 2 + 2 CMOVE",
        "_TS-LONG _TS-LONG 4 + 4 CMOVE",
        "_TS-LONG _TS-LONG 8 + 8 CMOVE",
        "_TS-LONG _TS-LONG 16 + 16 CMOVE",
        "_TS-LONG _TS-LONG 32 + 32 CMOVE",
        "_TS-LONG _TS-LONG 64 + 64 CMOVE",
        "_TS-LONG _TS-LONG 128 + 128 CMOVE",
        "_TS-LONG _TS-LONG 256 + 256 CMOVE",
        "_TS-LONG _TS-LONG 512 + 512 CMOVE",
        "_TS-LONG _TS-LONG 1024 + 277 CMOVE",
        "_TS-LONG 1301 _TS-W @ TXTA-SET-TEXT",
        "650 _TS-W @ _TXTA-O-CURSOR + !",
        "650 _TS-GB @ GB-MOVE!",
        "202 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-MEASURE",
        "DUP _TS-OK DROP DUP 1536 = _TS-ASSERT _TS-U !",
        "202 _TS-OUT-B _TS-U @ _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-CAPTURE",
        "DUP _TS-OK DROP _TS-U @ = _TS-ASSERT",
        "_TS-OUT-B USCOL-TEXT-ITEM-COUNT@ 1 = _TS-ASSERT",
        "_TS-OUT-B USCOL-TEXT-FIRST DUP USCOL-ITEM-TEXT-BYTES@ 1301 = _TS-ASSERT",
        "DUP USCOL-ITEM-TEXT@ DROP C@ 120 = _TS-ASSERT",
        "USCOL-ITEM-TEXT@ DROP 1300 + C@ 120 = _TS-ASSERT",
        "_TS-OUT-B _TS-U @ _TS-WORK 128 _TS-SUMMARY USCOL-ENTRY-VALIDATE _TS-OK",
        "_TS-STACK",
        # Invalid identity, zero visible geometry, and a cursor inside UTF-8
        # continuation bytes all refuse before a publishable entry exists.
        "0 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-MEASURE",
        "USCOL-S-INVALID = _TS-ASSERT 0= _TS-ASSERT",
        "1 2 0 8 _TS-RGN @ RGN-BOUNDS!",
        "303 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-MEASURE",
        "USCOL-S-UNAVAILABLE = _TS-ASSERT 0= _TS-ASSERT",
        "1 2 3 8 _TS-RGN @ RGN-BOUNDS!",
        'S" α" _TS-W @ TXTA-SET-TEXT',
        "1 _TS-W @ _TXTA-O-CURSOR + !",
        "1 _TS-GB @ GB-MOVE!",
        "303 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-MEASURE",
        "USCOL-S-INVALID = _TS-ASSERT 0= _TS-ASSERT",
        "_TS-STACK",
        '_TS-FAILS @ 0= IF ." TEXTAREA SEMANTIC PASS " ELSE ." TEXTAREA SEMANTIC FAIL " THEN _TS-CHECKS @ . _TS-FAILS @ . CR',
    ]


def test_gap_buffer_textarea_scroll_and_newline_caret():
    output = _run_forth(_textarea_program())
    summary = re.search(r"TEXTAREA TEST PASS\s+(\d+)\s+0", output)
    assert summary, output[-4000:]
    assert int(summary.group(1)) == 15


def test_textarea_captures_canonical_text_area_from_flat_and_gap_state():
    output = _run_forth(_textarea_semantic_program(), max_steps=700_000_000)
    summary = re.search(r"TEXTAREA SEMANTIC PASS\s+(\d+)\s+0", output)
    assert summary, output[-8000:]
    assert int(summary.group(1)) >= 50


if __name__ == "__main__":
    test_gap_buffer_textarea_scroll_and_newline_caret()
    test_textarea_captures_canonical_text_area_from_flat_and_gap_state()
