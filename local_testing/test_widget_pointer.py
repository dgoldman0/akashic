#!/usr/bin/env python3
"""Pointer handling in the canonical list, tree, explorer, and input widgets.

Each widget receives ordinary KEY-T-MOUSE descriptors carrying absolute
0-based screen cells, exactly as UIDL-TUI forwards them from the ANSI SGR
decoder or the APT-1 shell.  The snapshot loads the widgets' real REQUIRE
closure, so it follows the sources instead of a hand-kept module list.
"""

from __future__ import annotations

import re
import time

from forth_dependencies import dependency_order
from test_textarea import (
    AKASHIC_ROOT,
    BIOS_PATH,
    KDOS_PATH,
    MegapadSystem,
    _capture_uart,
    _cpu_state,
    _load_forth_lines,
    _restore_cpu,
    _run_input,
    assemble,
)


MODULES = dependency_order(
    AKASHIC_ROOT / "akashic",
    (
        "tui/ansi.f",
        "tui/widgets/list.f",
        "tui/widgets/tree.f",
        "tui/widgets/input.f",
        "tui/widgets/explorer.f",
    ),
)

_snapshot = None


def _build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    started = time.perf_counter()
    bios = assemble(BIOS_PATH.read_text())
    source = _load_forth_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for module in MODULES:
        source.extend(_load_forth_lines(AKASHIC_ROOT / "akashic" / module))

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
        f"widget pointer snapshot: {steps:,} steps in "
        f"{time.perf_counter() - started:.2f}s"
    )
    return _snapshot


def _run_forth(lines: list[str], max_steps: int = 200_000_000) -> bytes:
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
    return bytes(output)


def _numbers(lines: list[str]) -> list[int]:
    """Run a scenario whose last line prints values between STX and ETX."""

    output = _run_forth(lines).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output
    begin = output.rindex("\x02")
    end = output.index("\x03", begin)
    return [int(token) for token in re.findall(r"-?\d+", output[begin + 1 : end])]


# ( code row col widget -- consumed? ) with 0-based absolute screen cells.
_POINTER = [
    "CREATE _PEV 24 ALLOT",
    ": _PT  >R SWAP 16 LSHIFT OR _PEV 16 + ! _PEV 8 + !",
    "  KEY-T-MOUSE _PEV ! _PEV R> WDG-HANDLE ;",
]


def _report(count: int) -> list[str]:
    """Print the scenario's stacked values, top first, between markers."""

    return ["2 EMIT " + " ".join(["."] * count) + " 3 EMIT"]


# ---------------------------------------------------------------------
# ANSI mouse modes
# ---------------------------------------------------------------------


def test_ansi_mouse_reports_button_motion_with_sgr_encoding() -> None:
    output = _run_forth(["ANSI-MOUSE-ON", "ANSI-MOUSE-OFF", "TX-FLUSH"])

    on = b"\x1b[?1002h\x1b[?1006h"
    off = b"\x1b[?1006l\x1b[?1002l"
    assert on in output
    assert off in output[output.index(on) + len(on) :]
    assert b"[?1000" not in output


# ---------------------------------------------------------------------
# List
# ---------------------------------------------------------------------

_LIST = [
    "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR",
    "CREATE _LITEMS 48 ALLOT",
    'S" AA" _LITEMS 8 + ! _LITEMS !',
    'S" BB" _LITEMS 24 + ! _LITEMS 16 + !',
    'S" CC" _LITEMS 40 + ! _LITEMS 32 + !',
    *_POINTER,
    "VARIABLE _LW",
]


def _list(height: int) -> list[str]:
    return _LIST + [f"0 0 {height} 20 RGN-NEW _LITEMS 3 LST-NEW _LW !"]


def test_list_press_selects_the_row_under_it() -> None:
    values = _numbers(
        _list(5)
        + [
            "KEY-MOUSE-LEFT 1 3 _LW @ _PT",
            "_LW @ LST-SELECTED",
            "KEY-MOUSE-LEFT KEY-MOUSE-MOD-SHIFT OR 2 0 _LW @ _PT",
            "_LW @ LST-SELECTED",
            # A press in the list below its items keeps the selection.
            "KEY-MOUSE-LEFT 4 3 _LW @ _PT",
            "_LW @ LST-SELECTED",
            # Other buttons are left to the caller.
            "KEY-MOUSE-RIGHT 0 3 _LW @ _PT",
            "_LW @ LST-SELECTED",
        ]
        + _report(8)
    )

    # Printed in reverse stack order.
    assert values == [2, 0, 2, -1, 2, -1, 1, -1]


def test_list_selection_scrolls_only_as_far_as_it_must() -> None:
    values = _numbers(
        _list(2)
        + [
            # Visible rows 0-1: selecting row 1 must not move the view, or
            # the row under a pointer press would jump away from it.
            "1 _LW @ LST-SELECT _LW @ _LST-O-SCROLL + @",
            "2 _LW @ LST-SELECT _LW @ _LST-O-SCROLL + @",
            "1 _LW @ LST-SELECT _LW @ _LST-O-SCROLL + @",
            "0 _LW @ LST-SELECT _LW @ _LST-O-SCROLL + @",
        ]
        + _report(4)
    )

    assert values[::-1] == [0, 1, 1, 0]


def test_list_wheel_scrolls_the_view_within_its_items() -> None:
    values = _numbers(
        _list(2)
        + [
            "KEY-MOUSE-SCROLL-DN 0 0 _LW @ _PT",
            "_LW @ _LST-O-SCROLL + @ _LW @ LST-SELECTED",
            "KEY-MOUSE-SCROLL-DN 0 0 _LW @ _PT",
            "_LW @ _LST-O-SCROLL + @",
            "KEY-MOUSE-SCROLL-UP 0 0 _LW @ _PT",
            "_LW @ _LST-O-SCROLL + @",
        ]
        + _report(7)
    )

    # Three items in two rows scroll at most one row, and the selection stays.
    assert values == [0, -1, 1, -1, 0, 1, -1]


# ---------------------------------------------------------------------
# Tree
# ---------------------------------------------------------------------


def _tree(height: int) -> list[str]:
    return [
        "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
        f"0 0 {height} 40 RGN-NEW",
        # Root -> (ChildA, ChildB -> Grandchild); four cells per node.
        "CREATE _TN 128 ALLOT",
        ': _TL-ROOT S" Root" ;',
        ': _TL-A    S" ChildA" ;',
        ': _TL-B    S" ChildB" ;',
        ': _TL-GC   S" Grandchild" ;',
        "_TN 32 + _TN ! 0 _TN 8 + ! _TL-ROOT _TN 24 + ! _TN 16 + !",
        "0 _TN 32 + ! _TN 64 + _TN 40 + ! _TL-A _TN 56 + ! _TN 48 + !",
        "_TN 96 + _TN 64 + ! 0 _TN 72 + ! _TL-B _TN 88 + ! _TN 80 + !",
        "0 _TN 96 + ! 0 _TN 104 + ! _TL-GC _TN 120 + ! _TN 112 + !",
        ": _TC  @ ;",
        ": _TN-NEXT  8 + @ ;",
        ": _TLB  DUP 16 + @ SWAP 24 + @ ;",
        ": _TLF  @ 0= ;",
        *_POINTER,
        "VARIABLE _TW",
        "_TN ' _TC ' _TN-NEXT ' _TLB ' _TLF TREE-NEW _TW !",
        "_TW @ _TN TREE-EXPAND",
    ]


def test_tree_press_moves_the_cursor_and_toggles_on_an_arrow() -> None:
    values = _numbers(
        _tree(10)
        + [
            "KEY-MOUSE-LEFT 1 10 _TW @ _PT",
            "_TW @ _TREE-O-CURSOR + @",
            # ChildB is at depth 1, so its arrow is column 2.
            "KEY-MOUSE-LEFT 2 2 _TW @ _PT",
            "_TW @ _TREE-O-CURSOR + @ _TW @ _TREE-VIS-COUNT",
            "KEY-MOUSE-LEFT 2 2 _TW @ _PT",
            "_TW @ _TREE-VIS-COUNT",
            # The root's arrow is column 0.
            "KEY-MOUSE-LEFT 0 0 _TW @ _PT",
            "_TW @ _TREE-VIS-COUNT",
        ]
        + _report(9)
    )

    assert values == [1, -1, 3, -1, 4, 2, -1, 1, -1]


def test_tree_press_below_its_rows_and_other_buttons_keep_the_cursor() -> None:
    values = _numbers(
        _tree(10)
        + [
            "KEY-MOUSE-LEFT 7 1 _TW @ _PT",
            "KEY-MOUSE-RIGHT 1 10 _TW @ _PT",
            "_TW @ _TREE-O-CURSOR + @",
        ]
        + _report(3)
    )

    assert values == [0, 0, -1]


def test_tree_wheel_scrolls_the_visible_rows_without_moving_the_cursor() -> None:
    values = _numbers(
        _tree(2)
        + [
            "KEY-MOUSE-SCROLL-DN 0 0 _TW @ _PT",
            "_TW @ _TREE-O-SCROLL + @ _TW @ _TREE-O-CURSOR + @",
            "KEY-MOUSE-SCROLL-DN 0 0 _TW @ _PT",
            "_TW @ _TREE-O-SCROLL + @",
            "KEY-MOUSE-SCROLL-UP 0 0 _TW @ _PT",
            "_TW @ _TREE-O-SCROLL + @",
        ]
        + _report(7)
    )

    # Three visible rows in two scroll at most one row.
    assert values == [0, -1, 1, -1, 0, 1, -1]


def test_explorer_press_selects_through_its_tree_and_reports_it() -> None:
    values = _numbers(
        [
            "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
            *_POINTER,
            "VARIABLE _EARENA",
            "524288 A-XMEM ARENA-NEW THROW _EARENA !",
            "0 0 20 40 RGN-NEW",
            "_EARENA @ VFS-RAM-BINDING 0 VFS-NEW THROW DUP VFS-USE",
            'S" docs" VFS-CUR VFS-MKDIR DROP',
            'S" hello.f" VFS-CUR VFS-MKFILE DROP',
            'S" notes.txt" VFS-CUR VFS-MKFILE DROP',
            "VARIABLE _EV-VFS VFS-CUR _EV-VFS !",
            "_EV-VFS @ V.ROOT @ EXPL-NEW",
            "VARIABLE _EW _EW !",
            "VARIABLE _ESEL 0 _ESEL !",
            "VARIABLE _ECOUNT 0 _ECOUNT !",
            ": _E-ON-SEL  ( inode expl -- )  DROP _ESEL ! 1 _ECOUNT +! ;",
            "' _E-ON-SEL _EW @ EXPL-ON-SELECT",
            "_EW @ EXPL-TREE _EV-VFS @ V.ROOT @ TREE-EXPAND",
            "KEY-MOUSE-LEFT 2 10 _EW @ _PT",
            "_ECOUNT @ _ESEL @ _EW @ EXPL-TREE TREE-SELECTED NIP =",
            "_EW @ EXPL-TREE _TREE-O-CURSOR + @",
            # The wheel and other buttons do not report a selection.
            "KEY-MOUSE-SCROLL-DN 0 0 _EW @ _PT _ECOUNT @",
            "KEY-MOUSE-RIGHT 1 10 _EW @ _PT _ECOUNT @",
        ]
        + _report(8)
    )

    assert values == [1, 0, 1, -1, 2, -1, 1, -1]


# ---------------------------------------------------------------------
# Input field
# ---------------------------------------------------------------------


def _field() -> list[str]:
    return [
        "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR",
        "CREATE _IBUF 64 ALLOT",
        *_POINTER,
        "VARIABLE _IW",
        "2 5 1 20 RGN-NEW _IBUF 64 INP-NEW _IW !",
        # Two bytes for the second codepoint: four codepoints in five bytes.
        'S" AéCD" _IW @ INP-SET-TEXT',
    ]


def test_input_press_places_the_caret_at_the_codepoint_drawn_there() -> None:
    values = _numbers(
        _field()
        + [
            "KEY-MOUSE-LEFT 2 7 _IW @ _PT",
            "_IW @ INP-CURSOR-POS _IW @ _INP-O-CURSOR + @",
            # Past the text, the caret goes to its end.
            "KEY-MOUSE-LEFT 2 20 _IW @ _PT",
            "_IW @ INP-CURSOR-POS",
            # A scrolled field maps from its first drawn codepoint.
            "2 _IW @ _INP-O-SCROLL + !",
            "KEY-MOUSE-LEFT 2 5 _IW @ _PT",
            "_IW @ INP-CURSOR-POS",
        ]
        + _report(7)
    )

    assert values == [2, -1, 4, -1, 3, 2, -1]


def test_input_ignores_other_rows_buttons_and_drags() -> None:
    values = _numbers(
        _field()
        + [
            "_IW @ _INP-HOME",
            "KEY-MOUSE-LEFT 3 7 _IW @ _PT",
            "KEY-MOUSE-RIGHT 2 7 _IW @ _PT",
            "KEY-MOUSE-DRAG 2 7 _IW @ _PT",
            "_IW @ INP-CURSOR-POS",
        ]
        + _report(4)
    )

    assert values == [0, 0, 0, 0]
