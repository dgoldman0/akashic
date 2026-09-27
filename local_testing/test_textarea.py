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
    AKASHIC_ROOT / "akashic" / "utils" / "caller-span.f",
    AKASHIC_ROOT / "akashic" / "utils" / "string.f",
    AKASHIC_ROOT / "akashic" / "utils" / "datetime.f",
    AKASHIC_ROOT / "akashic" / "text" / "unicode-tables.f",
    AKASHIC_ROOT / "akashic" / "text" / "unicode-props.f",
    AKASHIC_ROOT / "akashic" / "text" / "grapheme.f",
    AKASHIC_ROOT / "akashic" / "text" / "bidi.f",
    AKASHIC_ROOT / "akashic" / "text" / "text-row.f",
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
    AKASHIC_ROOT / "akashic" / "tui" / "widgets" / "text-grid.f",
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


def _textarea_pointer_program() -> list[str]:
    """Drive the canonical textarea with pointer cells and text positions."""

    return [
        "VARIABLE _TP-FAILS",
        "VARIABLE _TP-CHECKS",
        "VARIABLE _TP-ARENA",
        "VARIABLE _TP-GB",
        "VARIABLE _TP-RGN",
        "VARIABLE _TP-W",
        "CREATE _TP-FLAT 1 ALLOT",
        "CREATE _TP-EV 24 ALLOT",
        ': _TP-ASSERT  1 _TP-CHECKS +! 0= IF 1 _TP-FAILS +! ." FAIL# " _TP-CHECKS @ . CR THEN ;',
        # ( code row col -- consumed? ) with 0-based absolute screen cells.
        ": _TP-MOUSE  SWAP 16 LSHIFT OR _TP-EV 16 + ! _TP-EV 8 + !",
        "  KEY-T-MOUSE _TP-EV ! _TP-EV _TP-W @ WDG-HANDLE ;",
        ": _TP-TEXT  ( code key offset -- consumed? )",
        "  KEY-MOUSE-TEXT-OFFSET ! KEY-MOUSE-TEXT-KEY ! 1 2 _TP-MOUSE ;",
        ": _TP-AT?  ( line col -- flag )",
        "  _TP-W @ TXTA-CURSOR-COL = SWAP _TP-W @ TXTA-CURSOR-LINE = AND ;",
        ": _TP-SEL-LEN  ( -- u )  _TP-W @ TXTA-GET-SEL NIP ;",
        ": _TP-SCROLL  ( -- u )  _TP-W @ TXTA-SCROLL-INFO DROP NIP ;",
        "0 _TP-FAILS ! 0 _TP-CHECKS !",
        "262144 A-XMEM ARENA-NEW DUP 0= _TP-ASSERT DROP _TP-ARENA !",
        "64 _TP-ARENA @ GB-NEW _TP-GB !",
        "20 6 SCR-NEW SCR-USE",
        # Region at screen row 1, column 2, three rows by ten columns, with a
        # two-column gutter: text starts at absolute column 4.
        "1 2 3 10 RGN-NEW _TP-RGN !",
        "_TP-RGN @ _TP-FLAT 1 TXTA-NEW _TP-W !",
        "_TP-GB @ _TP-W @ TXTA-BIND-GB",
        "0 2 _TP-W @ TXTA-GUTTER!",
        "_TP-W @ WDG-FOCUS-SET",
        "CREATE _TP-TEXT$ 32 ALLOT",
        ': _TP-LOAD  S" alpha" _TP-TEXT$ SWAP MOVE',
        "  10 _TP-TEXT$ 5 + C!",
        '  S" beta" _TP-TEXT$ 6 + SWAP MOVE 10 _TP-TEXT$ 10 + C!',
        '  S" gamma" _TP-TEXT$ 11 + SWAP MOVE 10 _TP-TEXT$ 16 + C!',
        '  S" delta" _TP-TEXT$ 17 + SWAP MOVE 10 _TP-TEXT$ 22 + C!',
        '  S" epsilon" _TP-TEXT$ 23 + SWAP MOVE',
        "  _TP-TEXT$ 30 _TP-W @ TXTA-SET-TEXT ;",
        "_TP-LOAD",
        # A press places the caret through the gutter/scroll layout.
        "KEY-MOUSE-LEFT 2 6 _TP-MOUSE _TP-ASSERT",
        "1 2 _TP-AT? _TP-ASSERT",
        "_TP-SEL-LEN 0= _TP-ASSERT",
        # A drag extends from that caret; the release keeps the range.
        "KEY-MOUSE-DRAG 3 5 _TP-MOUSE _TP-ASSERT",
        "2 1 _TP-AT? _TP-ASSERT",
        "_TP-SEL-LEN 4 = _TP-ASSERT",
        "KEY-MOUSE-RELEASE 3 5 _TP-MOUSE _TP-ASSERT",
        "_TP-SEL-LEN 4 = _TP-ASSERT",
        # Past the end of a line clamps to it; the gutter means column zero.
        "KEY-MOUSE-LEFT 1 19 _TP-MOUSE _TP-ASSERT",
        "0 5 _TP-AT? _TP-ASSERT",
        "_TP-SEL-LEN 0= _TP-ASSERT",
        "KEY-MOUSE-LEFT 1 2 _TP-MOUSE _TP-ASSERT",
        "0 0 _TP-AT? _TP-ASSERT",
        # Shift+press extends from the existing caret.
        "KEY-MOUSE-LEFT KEY-MOUSE-MOD-SHIFT OR 3 7 _TP-MOUSE _TP-ASSERT",
        "2 3 _TP-AT? _TP-ASSERT",
        "_TP-SEL-LEN 14 = _TP-ASSERT",
        # A drag above the viewport clamps to its first row.
        "KEY-MOUSE-DRAG 0 6 _TP-MOUSE _TP-ASSERT",
        "0 2 _TP-AT? _TP-ASSERT",
        # The wheel scrolls three lines within the text; a caret the viewport
        # leaves follows to its nearest visible line and keeps its column.
        "KEY-MOUSE-LEFT 1 4 _TP-MOUSE _TP-ASSERT",
        "KEY-MOUSE-SCROLL-DN 2 6 _TP-MOUSE _TP-ASSERT",
        "_TP-SCROLL 2 = _TP-ASSERT",
        "2 0 _TP-AT? _TP-ASSERT",
        "KEY-MOUSE-SCROLL-UP 2 6 _TP-MOUSE _TP-ASSERT",
        "_TP-SCROLL 0= _TP-ASSERT",
        "2 0 _TP-AT? _TP-ASSERT",
        # Renderer-named positions use the published key (line + 1).
        "KEY-MOUSE-TEXT-PLACE 4 3 _TP-TEXT _TP-ASSERT",
        "3 3 _TP-AT? _TP-ASSERT",
        "KEY-MOUSE-TEXT-EXTEND 5 7 _TP-TEXT _TP-ASSERT",
        "4 7 _TP-AT? _TP-ASSERT",
        "_TP-SEL-LEN 10 = _TP-ASSERT",
        # A position from an older frame clamps to the current text.
        "KEY-MOUSE-TEXT-PLACE 99 2 _TP-TEXT _TP-ASSERT",
        "4 2 _TP-AT? _TP-ASSERT",
        "KEY-MOUSE-TEXT-PLACE 1 99 _TP-TEXT _TP-ASSERT",
        "0 5 _TP-AT? _TP-ASSERT",
        # Other buttons are left to the caller.
        "KEY-MOUSE-MIDDLE 2 6 _TP-MOUSE 0= _TP-ASSERT",
        "0 5 _TP-AT? _TP-ASSERT",
        '_TP-FAILS @ 0= IF ." TEXTAREA POINTER PASS " ELSE ." TEXTAREA POINTER FAIL " THEN _TP-CHECKS @ . _TP-FAILS @ . CR',
    ]


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
        "VARIABLE _TS-SAVED-LCNT",
        "VARIABLE _TS-SAVED-L1",
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
        # A caller output aliasing GB-COPY's own range-copy scratch must fail
        # before any gap-buffer query or copy can rewrite that scratch.
        "777777 _GB-RNG-DEST !",
        "101 _GB-RNG-DEST _TS-U @ _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-CAPTURE",
        "USCOL-S-INVALID = _TS-ASSERT 0= _TS-ASSERT",
        "_GB-RNG-DEST @ 777777 = _TS-ASSERT",
        "_TS-STACK",
        "101 _TS-OUT-B 8192 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-CAPTURE",
        "DUP _TS-OK DROP DUP _TS-U @ = _TS-ASSERT DROP",
        "_TS-OUT-A _TS-OUT-B _TS-U @ _TS-SAME? _TS-ASSERT",
        "_TS-STACK",
        # A bounded descriptor is not enough: semantic capture must reject a
        # line count or packed start offset that disagrees with logical bytes
        # before any GB line-index query can consume it.
        "_TS-GB @ _GB-O-LCNT + @ _TS-SAVED-LCNT !",
        "1 _TS-GB @ _GB-O-LCNT + !",
        "202 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-MEASURE",
        "USCOL-S-INVALID = _TS-ASSERT 0= _TS-ASSERT",
        "_TS-SAVED-LCNT @ _TS-GB @ _GB-O-LCNT + !",
        "_TS-GB @ _GB-O-LIDX + @ 4 + DUP L@ _TS-SAVED-L1 !",
        "2 OVER L! DROP",
        "202 _TS-BUILDER _TS-W @ TXTA-TEXT-AREA-MEASURE",
        "USCOL-S-INVALID = _TS-ASSERT 0= _TS-ASSERT",
        "_TS-SAVED-L1 @ _TS-GB @ _GB-O-LIDX + @ 4 + L!",
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


def _draw_observer_program() -> list[str]:
    """Exercise generic nested/full/partial observation and throw cleanup."""

    return [
        "VARIABLE _TO-FAILS",
        "VARIABLE _TO-CHECKS",
        "VARIABLE _TO-DEPTH",
        "VARIABLE _TO-N",
        "VARIABLE _TO-SCR",
        "VARIABLE _TO-RGN",
        "VARIABLE _TO-W",
        "CREATE _TO-BUF 64 ALLOT",
        "CREATE _TO-PANEL _WDG-HDR-SIZE ALLOT",
        "CREATE _TO-BAD _WDG-HDR-SIZE ALLOT",
        "CREATE _TO-PHASES 16 CELLS ALLOT",
        "CREATE _TO-WIDGETS 16 CELLS ALLOT",
        ': _TO-ASSERT 1 _TO-CHECKS +! 0= IF 1 _TO-FAILS +! ." OBS ASSERT " _TO-CHECKS @ . CR THEN ;',
        ": _TO-STACK DEPTH _TO-DEPTH @ = _TO-ASSERT ;",
        ": _TO-PHASE@ CELLS _TO-PHASES + @ ;",
        ": _TO-WIDGET@ CELLS _TO-WIDGETS + @ ;",
        ": _TO-OBS ( widget phase context -- status )",
        "  77 = _TO-ASSERT",
        "  _TO-N @ CELLS _TO-PHASES + !",
        "  _TO-N @ CELLS _TO-WIDGETS + !",
        "  1 _TO-N +! WDG-DRAW-OBS-S-OK ;",
        ": _TO-THROW-OBS ( widget phase context -- status )",
        "  DROP 2DROP -778 THROW ;",
        ": _TO-HANDLE ( event widget -- consumed? ) 2DROP 0 ;",
        ": _TO-PANEL-DRAW ( widget -- ) DROP _TO-W @ WDG-DRAW ;",
        ": _TO-BAD-DRAW ( widget -- ) DROP -777 THROW ;",
        ": _TO-BODY ( -- )",
        "  _TO-PANEL WDG-DRAW",
        "  0 1 _TO-W @ TXTA-DRAW-ROWS ;",
        ": _TO-THROW-BODY ( -- ) _TO-BAD WDG-DRAW ;",
        ": _TO-THROW-SCOPE ( -- )",
        "  77 ['] _TO-OBS ['] _TO-THROW-BODY WDG-DRAW-OBSERVE DROP ;",
        "0 _TO-FAILS ! 0 _TO-CHECKS !",
        "20 8 SCR-NEW DUP _TO-SCR ! SCR-USE",
        "1 2 3 8 RGN-NEW _TO-RGN !",
        "_TO-RGN @ _TO-BUF 64 TXTA-NEW _TO-W !",
        'S" observed" _TO-W @ TXTA-SET-TEXT',
        "_TO-PANEL WDG-T-CANVAS _TO-RGN @ ' _TO-PANEL-DRAW ' _TO-HANDLE WDG-INIT",
        "_TO-BAD WDG-T-CANVAS _TO-RGN @ ' _TO-BAD-DRAW ' _TO-HANDLE WDG-INIT",
        "DEPTH _TO-DEPTH ! 0 _TO-N !",
        "77 ' _TO-OBS ' _TO-BODY WDG-DRAW-OBSERVE",
        "WDG-DRAW-OBS-S-OK = _TO-ASSERT",
        "_TO-N @ 5 = _TO-ASSERT",
        "0 _TO-PHASE@ WDG-DRAW-PHASE-FULL-BEGIN = _TO-ASSERT",
        "1 _TO-PHASE@ WDG-DRAW-PHASE-FULL-BEGIN = _TO-ASSERT",
        "2 _TO-PHASE@ WDG-DRAW-PHASE-FULL-END = _TO-ASSERT",
        "3 _TO-PHASE@ WDG-DRAW-PHASE-FULL-END = _TO-ASSERT",
        "4 _TO-PHASE@ WDG-DRAW-PHASE-PARTIAL = _TO-ASSERT",
        "0 _TO-WIDGET@ _TO-PANEL = _TO-ASSERT",
        "1 _TO-WIDGET@ _TO-W @ = _TO-ASSERT",
        "2 _TO-WIDGET@ _TO-W @ = _TO-ASSERT",
        "3 _TO-WIDGET@ _TO-PANEL = _TO-ASSERT",
        "4 _TO-WIDGET@ _TO-W @ = _TO-ASSERT",
        "_TO-W @ WDG-DIRTY? 0= _TO-ASSERT",
        "_TO-STACK",
        # A throwing draw emits ABORT, remains dirty, and is rethrown with the
        # exact original code after the observation scope has been scrubbed.
        "0 _TO-N ! ' _TO-THROW-SCOPE CATCH -777 = _TO-ASSERT",
        "_TO-N @ 2 = _TO-ASSERT",
        "0 _TO-PHASE@ WDG-DRAW-PHASE-FULL-BEGIN = _TO-ASSERT",
        "1 _TO-PHASE@ WDG-DRAW-PHASE-FULL-ABORT = _TO-ASSERT",
        "_TO-BAD WDG-DIRTY? _TO-ASSERT",
        "_WDG-OBS-ACTIVE @ 0= _TO-ASSERT",
        "_TO-STACK",
        # Observer failure is diagnostic only.  The complete ordinary draw
        # still runs and cleans the canonical child.
        "_TO-W @ WDG-DIRTY 0 _TO-N !",
        "77 ' _TO-THROW-OBS ' _TO-BODY WDG-DRAW-OBSERVE",
        "WDG-DRAW-OBS-S-CALLBACK = _TO-ASSERT",
        "_TO-W @ WDG-DIRTY? 0= _TO-ASSERT",
        "_WDG-OBS-ACTIVE @ 0= _TO-ASSERT",
        "_TO-STACK",
        # A fresh scope after both failure modes proves no callback/context
        # leaked from either prior execution.
        "0 _TO-N ! 77 ' _TO-OBS ' _TO-BODY WDG-DRAW-OBSERVE",
        "WDG-DRAW-OBS-S-OK = _TO-ASSERT",
        "_TO-N @ 5 = _TO-ASSERT",
        "_TO-STACK",
        '_TO-FAILS @ 0= IF ." DRAW OBSERVER PASS " ELSE ." DRAW OBSERVER FAIL " THEN _TO-CHECKS @ . _TO-FAILS @ . CR',
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


def test_textarea_pointer_places_extends_scrolls_and_follows_text_positions():
    output = _run_forth(_textarea_pointer_program())
    summary = re.search(r"TEXTAREA POINTER PASS\s+(\d+)\s+0", output)
    assert summary, output[-4000:]
    assert int(summary.group(1)) == 37


def test_widget_draw_observer_covers_nested_partial_and_throw_paths():
    output = _run_forth(_draw_observer_program())
    summary = re.search(r"DRAW OBSERVER PASS\s+(\d+)\s+0", output)
    assert summary, output[-8000:]
    assert int(summary.group(1)) >= 25


# ---------------------------------------------------------------------------
# Wide characters, clusters, and right-to-left lines
# ---------------------------------------------------------------------------
#
# MegaPad's reference text rules (rich_terminal/text_rules.py) are an
# independent implementation of APT-1-TEXT, checked against Unicode's
# conformance data.  They say what each row of the text area must show and
# where each caret move, vertical move, and click must land.

from rich_terminal.text_rules import display_scalars, layout_row, segment  # noqa: E402

_REVERSE, _WIDE, _CONT = 32, 128, 256
_TX_REGION = (1, 2, 6, 24)  # row, column, height, width on a 40 by 10 screen
_TX_GUTTER = 2
_TX_TEXT_W = _TX_REGION[3] - _TX_GUTTER

_MIXED_LINES = (
    # English, Chinese, an accent built from a combining mark, a family
    # emoji sequence, and a flag.
    "Hi \u4e2d\u6587 e\u0301 \U0001F468\u200d\U0001F469\u200d\U0001F467 \U0001F1EF\U0001F1F5",
    # Hebrew, and Arabic with English, resolve to right-to-left rows.
    "\u05e9\u05dc\u05d5\u05dd \u05e2\u05d5\u05dc\u05dd",
    "\u0645\u0631\u062d\u0628\u0627 abc",
    "abc",
    # A right-to-left row wider than the text viewport.
    "\u05d0\u05d1\u05d2\u05d3\u05d4\u05d5\u05d6\u05d7\u05d8\u05d9\u05db"
    "\u05dc\u05de\u05e0\u05e1\u05e2\u05e4\u05e6\u05e7\u05e8\u05e9\u05ea 12",
    # A left-to-right row that scrolls to its end and cuts a wide character.
    "\u4e2d\u6587" * 6 + " ends",
)


def _line_starts(lines) -> list[int]:
    starts, offset = [], 0
    for line in lines:
        starts.append(offset)
        offset += len(line.encode()) + 1
    return starts


def _byte(text: str, scalar: int) -> int:
    return len(text[:scalar].encode())


def _layout(text: str):
    return layout_row(text, keep_tab=True)


def _text_origin(text: str, sx: int) -> int:
    """The text viewport column of the row's visual column zero."""

    layout = _layout(text)
    return _TX_TEXT_W - layout.width + sx if layout.rtl else -sx


def _caret_v(text: str, scalar: int) -> int:
    """APT-1-TEXT Section 9.2: the lead cell of the caret's character, or
    just past the content on the row's end side."""

    layout = _layout(text)
    placed = layout.caret_character(scalar)
    if placed is not None:
        return placed.column
    return -1 if layout.rtl else layout.width


def _caret_x(text: str, scalar: int, sx: int) -> int:
    return _text_origin(text, sx) + _caret_v(text, scalar)


def _position_at_x(text: str, x: int, sx: int) -> int:
    """APT-1-TEXT Section 9.1 for a text viewport column."""

    return _layout(text).position_at_column(x - _text_origin(text, sx))


def _boundaries(text: str) -> list[int]:
    """The byte offset after each character of TEXT."""

    spans = segment(display_scalars(text, keep_tab=True))
    return [_byte(text, start + length) for start, length in spans]


def _expected_row(text, sx, caret=None, selection=None) -> list:
    """The region's cells of one row, as (scalars, attrs), left to right.

    CARET is a focused caret's scalar offset on this row; SELECTION is a
    marked range of scalar offsets."""

    cells = [((32,), 0) for _ in range(_TX_REGION[3])]
    if text is None:
        return cells
    layout = _layout(text)
    origin = _TX_GUTTER + _text_origin(text, sx)
    marked = selection or (1, 0)
    end_caret = None
    if caret is not None:
        placed = layout.caret_character(caret)
        if placed is None:
            end_caret = origin + _caret_v(text, caret)
        else:
            marked = (placed.start, placed.start + 1)

    def put(col, cell):
        if _TX_GUTTER <= col < _TX_REGION[3]:
            cells[col] = cell

    for placed in layout.characters:
        attrs = _REVERSE if marked[0] <= placed.start < marked[1] else 0
        col = origin + placed.column
        scalars = tuple(map(ord, placed.text))
        if placed.width == 1:
            put(col, (scalars, attrs))
        elif _TX_GUTTER <= col and col + 2 <= _TX_REGION[3]:
            put(col, (scalars, attrs | _WIDE))
            put(col + 1, ((0,), attrs | _CONT))
        else:
            # APT-1-TEXT Section 6: a cut character shows a space in its
            # style in each cell the clip keeps.
            put(col, ((32,), attrs))
            put(col + 1, ((32,), attrs))
    if end_caret is not None:
        put(end_caret, ((32,), _REVERSE))
    return cells


def _expected_rows(lines, sx, caret_line=None, caret=None, selection=None):
    return [
        _expected_row(
            lines[index] if index < len(lines) else None,
            sx,
            caret if index == caret_line else None,
            selection if index == caret_line else None,
        )
        for index in range(_TX_REGION[2])
    ]


class _TextScript:
    """Forth lines for the text area and the records they must print."""

    def __init__(self) -> None:
        self.lines: list[str] = []
        self.expected: list[tuple[str, str, object]] = []

    def run(self, *lines: str) -> None:
        self.lines.extend(lines)

    def cursor(self, label: str, offset: int) -> None:
        self.lines.append("_TX-CUR")
        self.expected.append(("C", label, offset))

    def number(self, label: str, forth: str, value: int) -> None:
        self.lines.append(f"{forth} _TX-N")
        self.expected.append(("N", label, value))

    def rows(self, label: str, rows: list) -> None:
        self.lines.append("_TX-ROWS")
        for index, row in enumerate(rows):
            self.expected.append(("R", f"{label}, row {index}", row))


def _cells(tokens: list[int]) -> list:
    cells, index = [], 0
    while index < len(tokens):
        count = tokens[index]
        scalars = tuple(tokens[index + 1 : index + 1 + count])
        cells.append((scalars, tokens[index + 1 + count]))
        index += count + 2
    return cells


def _set_text_lines(lines) -> list[str]:
    forth = ["0 _TX-LEN !"]
    for index, line in enumerate(lines):
        forth.append(f'S" {line}" _TX+' + (" _TX-NL" if index + 1 < len(lines) else ""))
    forth.append("_TX-SET")
    return forth


def _textarea_text_script() -> _TextScript:
    lines = _MIXED_LINES
    starts = _line_starts(lines)
    ends = [start + len(line.encode()) for start, line in zip(starts, lines)]
    script = _TextScript()
    row, col, height, width = _TX_REGION
    script.run(
        "VARIABLE _TX-ARENA",
        "VARIABLE _TX-GB",
        "VARIABLE _TX-RGN",
        "VARIABLE _TX-W",
        "VARIABLE _TX-LEN",
        "VARIABLE _TX-U",
        "CREATE _TX-BUF 512 ALLOT",
        "CREATE _TX-FLAT 1 ALLOT",
        "CREATE _TX-EV 24 ALLOT",
        "CREATE _TX-BLD-S USCOL-BUILDER-SIZE 7 + ALLOT",
        "CREATE _TX-OUT-S 4096 7 + ALLOT",
        "CREATE _TX-WORK-S 256 7 + ALLOT",
        "CREATE _TX-SUM-S USCOL-SUMMARY-SIZE 7 + ALLOT",
        ": _TX-BLD _TX-BLD-S 7 + -8 AND ;",
        ": _TX-OUT _TX-OUT-S 7 + -8 AND ;",
        ": _TX-WORK _TX-WORK-S 7 + -8 AND ;",
        ": _TX-SUM _TX-SUM-S 7 + -8 AND ;",
        ": _TX+  ( a u -- )  DUP >R _TX-BUF _TX-LEN @ + SWAP MOVE R> _TX-LEN +! ;",
        ": _TX-NL  ( -- )  10 _TX-BUF _TX-LEN @ + C! 1 _TX-LEN +! ;",
        ": _TX-SET  ( -- )  _TX-BUF _TX-LEN @ _TX-W @ TXTA-SET-TEXT ;",
        ": _TX-AT  ( off -- )  -1 _TX-W @ _TXTA-O-SEL-ANCHOR + !",
        "  DUP _TX-W @ _TXTA-O-CURSOR + ! _TX-GB @ GB-MOVE! ;",
        ": _TX-ANCHOR  ( off -- )  _TX-W @ _TXTA-O-SEL-ANCHOR + ! ;",
        ": _TX-KEY  ( code -- )  KEY-T-SPECIAL _TX-EV ! _TX-EV 8 + !",
        "  0 _TX-EV 16 + ! _TX-EV _TX-W @ WDG-HANDLE DROP ;",
        ": _TX-CHAR  ( cp -- )  KEY-T-CHAR _TX-EV ! _TX-EV 8 + !",
        "  0 _TX-EV 16 + ! _TX-EV _TX-W @ WDG-HANDLE DROP ;",
        ": _TX-CLICK  ( row col -- )  SWAP 16 LSHIFT OR _TX-EV 16 + !",
        "  KEY-MOUSE-LEFT _TX-EV 8 + ! KEY-T-MOUSE _TX-EV !",
        "  _TX-EV _TX-W @ WDG-HANDLE DROP ;",
        ": _TX-DRAW  ( -- )  SCR-CLEAR _TX-W @ WDG-DRAW ;",
        ": _TX-CELL  ( cell -- )",
        "  DUP CELL-CP@ CELL-CP-CLUSTER AND IF",
        "    DUP SCR-CLUSTER@ DUP . 0 ?DO DUP I 4 * + L@ . LOOP DROP",
        "  ELSE 1 . DUP CELL-CP@ . THEN",
        "  CELL-ATTRS@ . ;",
        f': _TX-ROW  ( row -- )  ." ~R " {col + width} {col} DO DUP I SCR-GET _TX-CELL LOOP',
        '  DROP ." ~E " ;',
        f": _TX-ROWS  ( -- )  {row + height} {row} DO I _TX-ROW LOOP ;",
        ': _TX-CUR  ( -- )  ." ~C " _TX-W @ _TXTA-O-CURSOR + @ . ." ~E " ;',
        ': _TX-N  ( n -- )  ." ~N " . ." ~E " ;',
        ": _TX-CAPTURE  ( -- status )",
        "  101 _TX-OUT 4096 _TX-BLD _TX-W @ TXTA-TEXT-AREA-CAPTURE SWAP _TX-U ! ;",
        "262144 A-XMEM ARENA-NEW DROP _TX-ARENA !",
        "512 _TX-ARENA @ GB-NEW _TX-GB !",
        "40 10 SCR-NEW SCR-USE",
        f"{row} {col} {height} {width} RGN-NEW _TX-RGN !",
        "_TX-RGN @ _TX-FLAT 1 TXTA-NEW _TX-W !",
        "_TX-GB @ _TX-W @ TXTA-BIND-GB",
        f"0 {_TX_GUTTER} _TX-W @ TXTA-GUTTER!",
        "_TX-W @ WDG-FOCUS-SET",
    )
    script.run(*_set_text_lines(lines))

    # Each row takes its characters' cells in visual order: an RTL row starts
    # at the viewport's right edge, and one wider than the viewport is cut at
    # the gutter.  The focused caret marks its character.
    script.run(f"{starts[3]} _TX-AT _TX-DRAW")
    script.rows("caret on an ASCII row", _expected_rows(lines, 0, 3, 0))

    # At an RTL row's end the caret sits just left of the content.
    script.run(f"{ends[1]} _TX-AT _TX-DRAW")
    script.rows("caret at an RTL row's end", _expected_rows(lines, 0, 1, len(lines[1])))

    # A selection marks whole characters, wide ones in both cells.
    script.run(f"13 _TX-AT {starts[0] + 3} _TX-ANCHOR _TX-DRAW")
    script.rows("selection over wide characters and a cluster", _expected_rows(lines, 0, 0, None, (3, 8)))

    # A caret past the viewport scrolls it: every LTR row moves left and
    # every RTL row right, and characters the scroll cuts show spaces.
    width5 = _layout(lines[5]).width
    sx = width5 - _TX_TEXT_W + 4
    script.run(f"{ends[5]} _TX-AT _TX-DRAW")
    script.number("horizontal scroll", "_TX-W @ TXTA-SCROLL-X@", sx)
    script.rows("scrolled to a long row's end", _expected_rows(lines, sx, 5, len(lines[5])))
    script.number("caret characters", "_TX-W @ TXTA-CURSOR-COL", len(_boundaries(lines[5])))
    script.number("caret cells", "_TX-W @ TXTA-CURSOR-CELL", width5)
    script.number("caret viewport column", "_TX-W @ TXTA-CURSOR-X", width5 - sx)

    # TEXT_AREA columns count cells: the widest row's, or the scrolled
    # viewport's right edge.  Offsets count scalars.
    script.number("capture", "_TX-CAPTURE", 0)
    script.number("capture validates", "_TX-OUT _TX-U @ _TX-WORK 256 _TX-SUM USCOL-ENTRY-VALIDATE", 0)
    columns = max(max(_layout(line).width for line in lines), sx + _TX_TEXT_W)
    script.number("columns", "_TX-OUT USCOL-TEXT-COLUMNS@", columns)
    script.number("viewport column", "_TX-OUT USCOL-TEXT-VIEWPORT-COLUMN@", sx)
    script.number("viewport columns", "_TX-OUT USCOL-TEXT-VIEWPORT-COLUMNS@", _TX_TEXT_W)
    script.number("primary key", "_TX-OUT USCOL-TEXT-PRIMARY-KEY@", 6)
    script.number("primary offset", "_TX-OUT USCOL-TEXT-PRIMARY-OFFSET@", len(lines[5]))

    # Right and Left move over whole characters in logical order, and across
    # the line break.
    script.run(f"{starts[0]} _TX-AT")
    stops = [starts[0] + end for end in _boundaries(lines[0])] + [starts[1]]
    for stop in stops:
        script.run("KEY-RIGHT _TX-KEY")
        script.cursor("Right over the mixed row", stop)
    for stop in [starts[0] + end for end in reversed(_boundaries(lines[0]))] + [0]:
        script.run("KEY-LEFT _TX-KEY")
        script.cursor("Left over the mixed row", stop)
    script.run(f"{starts[2]} _TX-AT")
    for end in _boundaries(lines[2]):
        script.run("KEY-RIGHT _TX-KEY")
        script.cursor("Right over the Arabic row", starts[2] + end)

    # Unscrolled, the columns are the widest row's cells, not the most
    # scalars any row has.
    script.run("0 _TX-W @ TXTA-SCROLL-X!")
    widest = max(_layout(line).width for line in lines)
    assert widest != max(len(line) for line in lines)
    script.number("capture unscrolled", "_TX-CAPTURE", 0)
    script.number("columns of the widest row", "_TX-OUT USCOL-TEXT-COLUMNS@", widest)

    # Up and Down keep the caret's viewport column.
    for line, scalar, target in ((0, 4, 1), (0, len(lines[0]), 1), (1, 3, 2), (2, 6, 1), (4, 0, 3)):
        x = _caret_x(lines[line], scalar, 0)
        expected = starts[target] + _byte(lines[target], _position_at_x(lines[target], x, 0))
        key = "KEY-DOWN" if target > line else "KEY-UP"
        script.run(f"{starts[line] + _byte(lines[line], scalar)} _TX-AT {key} _TX-KEY")
        script.cursor(f"{key} from row {line} scalar {scalar}", expected)

    # A click names the character under it, or past the content the row's
    # end on its end side; a click in the gutter means the viewport's first
    # column.
    for line, abs_col in ((1, 25), (1, 21), (1, 10), (0, 8), (0, 24), (4, 2), (2, 18), (2, 21)):
        x = max(0, abs_col - col - _TX_GUTTER)
        expected = starts[line] + _byte(lines[line], _position_at_x(lines[line], x, 0))
        script.run(f"{row + line} {abs_col} _TX-CLICK")
        script.cursor(f"click on row {line} column {abs_col}", expected)

    # The caret's characters, cells from its row's start edge, and viewport
    # column.
    for line, scalar in ((0, 8), (1, 2), (1, len(lines[1])), (2, 7)):
        layout = _layout(lines[line])
        v = _caret_v(lines[line], scalar)
        cells = layout.width - 1 - v if layout.rtl else v
        count = sum(1 for start, _ in segment(display_scalars(lines[line][:scalar])))
        script.run(f"{starts[line] + _byte(lines[line], scalar)} _TX-AT")
        script.number(f"characters before row {line} scalar {scalar}", "_TX-W @ TXTA-CURSOR-COL", count)
        script.number(f"cells before row {line} scalar {scalar}", "_TX-W @ TXTA-CURSOR-CELL", cells)
        script.number(f"viewport column of row {line} scalar {scalar}", "_TX-W @ TXTA-CURSOR-X", _caret_x(lines[line], scalar, 0))

    # Backspace and Delete remove whole characters: the flag, a space, the
    # family sequence, and then the accented e.
    total = ends[-1]
    cursor = ends[0]
    script.run(f"{cursor} _TX-AT")
    for removed in (8, 1, 18):
        cursor -= removed
        total -= removed
        script.run("KEY-BACKSPACE _TX-KEY")
        script.cursor("Backspace removes a whole character", cursor)
        script.number("bytes after Backspace", "_TX-GB @ GB-LEN", total)
    script.run(f"{starts[0] + 10} _TX-AT KEY-DEL _TX-KEY")
    script.cursor("Delete keeps the caret", starts[0] + 10)
    script.number("Delete removes the accented e", "_TX-GB @ GB-LEN", total - 3)

    # An edit that joins characters leaves the caret on a boundary: a base
    # typed before a lone combining mark joins it, and deleting what stood
    # between two Hangul jamo joins them.
    script.run(*_set_text_lines(["\u0301x"]), "0 _TX-AT 101 _TX-CHAR")
    script.cursor("a typed base joins a combining mark", 3)
    script.run(*_set_text_lines(["\u1100x\u1161"]), "3 _TX-AT KEY-DEL _TX-KEY")
    script.cursor("a deletion joins two jamo", 0)
    script.number("jamo bytes", "_TX-GB @ GB-LEN", 6)
    return script


def test_textarea_lays_out_mixed_scripts_and_moves_by_characters():
    script = _textarea_text_script()
    output = _run_forth(script.lines, max_steps=1_500_000_000)
    records = [
        (tag, [int(token) for token in body.split()])
        for tag, body in re.findall(r"~([A-Z]) ((?:-?\d+ )*)~E", output)
    ]
    assert len(records) == len(script.expected), output[-4000:]
    failures = []
    for (tag, values), (want_tag, label, want) in zip(records, script.expected):
        assert tag == want_tag, (label, tag, want_tag)
        got = _cells(values) if tag == "R" else values[0]
        if got != want:
            failures.append(f"{label}:\n  got  {got}\n  want {want}")
    assert not failures, "\n".join(failures)


if __name__ == "__main__":
    test_gap_buffer_textarea_scroll_and_newline_caret()
    test_textarea_captures_canonical_text_area_from_flat_and_gap_state()
    test_widget_draw_observer_covers_nested_partial_and_throw_paths()
