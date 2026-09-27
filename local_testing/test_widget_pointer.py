#!/usr/bin/env python3
"""Pointer handling in the canonical widgets and UIDL-TUI's forwarding.

Each widget receives ordinary KEY-T-MOUSE descriptors carrying absolute
0-based screen cells, exactly as UIDL-TUI forwards them from the ANSI SGR
decoder or the APT-1 shell.  Snapshots load each case's real REQUIRE
closure, so they follow the sources instead of a hand-kept module list.
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


WIDGET_ROOTS = (
    "tui/ansi.f",
    "tui/widgets/list.f",
    "tui/widgets/tree.f",
    "tui/widgets/input.f",
    "tui/widgets/explorer.f",
)
UIDL_ROOTS = ("tui/uidl-tui.f", "tui/widgets/list.f")

_snapshots: dict[tuple[str, ...], tuple] = {}


def _build_snapshot(roots: tuple[str, ...]):
    cached = _snapshots.get(roots)
    if cached is not None:
        return cached

    started = time.perf_counter()
    bios = assemble(BIOS_PATH.read_text())
    source = _load_forth_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for module in dependency_order(AKASHIC_ROOT / "akashic", roots):
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
    snapshot = (
        bios,
        bytes(system.cpu.mem),
        bytes(system._ext_mem),
        _cpu_state(system.cpu),
    )
    _snapshots[roots] = snapshot
    print(
        f"pointer snapshot {roots}: {steps:,} steps in "
        f"{time.perf_counter() - started:.2f}s"
    )
    return snapshot


def _run_forth(
    lines: list[str],
    max_steps: int = 200_000_000,
    *,
    roots: tuple[str, ...] = WIDGET_ROOTS,
) -> bytes:
    bios, memory, ext_memory, state = _build_snapshot(roots)
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


def _numbers(
    lines: list[str],
    *,
    roots: tuple[str, ...] = WIDGET_ROOTS,
) -> list[int]:
    """Run a scenario whose last line prints values between STX and ETX."""

    output = _run_forth(lines, roots=roots).decode("utf-8", errors="replace")
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
    "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
    ': _LNAME  ( index -- a u )',
    '  DUP 0= IF DROP S" AA" EXIT THEN 1 = IF S" BB" EXIT THEN S" CC" ;',
    # Keys are row numbers from one.
    ": _LK  ( index widget -- key )  DROP 1+ ;",
    ": _LF  ( index column widget -- a u )  2DROP _LNAME ;",
    *_POINTER,
    "VARIABLE _LW",
]


def _list(height: int) -> list[str]:
    return _LIST + [
        f"0 0 {height} 20 RGN-NEW ' _LK ' _LF LST-NEW _LW !",
        "3 _LW @ LST-ROWS!",
    ]


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


def _screen_rows(output: str) -> list[str]:
    return [
        "".join(chr(int(token)) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]


# Print local rows of the screen between markers.
_SHOW = [": _ROW$  ( row -- )  18 EMIT 20 0 DO DUP I SCR-GET CELL-CP@ . LOOP DROP 19 EMIT ;"]

_TABLE = [
    # Name (the rest) and Size (a number, four cells).
    "CREATE _LCOLS LST-COLUMN-SIZE 2 * ALLOT",
    ': _LNAME$ S" Name" ;',
    ': _LSIZE$ S" Size" ;',
    "USCOL-IV-TEXT _LCOLS LST-COLUMN-KIND + !",
    "_LNAME$ _LCOLS LST-COLUMN-LABEL-U + ! _LCOLS LST-COLUMN-LABEL-A + !",
    "0 _LCOLS LST-COLUMN-WIDTH + !",
    "USCOL-IV-NUMBER _LCOLS 32 + LST-COLUMN-KIND + !",
    "_LSIZE$ _LCOLS 32 + LST-COLUMN-LABEL-U + ! _LCOLS 32 + LST-COLUMN-LABEL-A + !",
    "4 _LCOLS 32 + LST-COLUMN-WIDTH + !",
    ': _LSIZE  ( index -- a u )  DUP 0= IF DROP S" 7" EXIT THEN 1 = IF S" 42" EXIT THEN S" 512" ;',
    ": _LTF  ( index column widget -- a u )  DROP IF _LSIZE ELSE _LNAME THEN ;",
]


def test_a_table_draws_labels_and_aligns_its_columns() -> None:
    output = _run_forth(
        _LIST
        + _SHOW
        + _TABLE
        + [
            "0 0 4 20 RGN-NEW ' _LK ' _LTF LST-NEW _LW !",
            "_LCOLS 2 _LW @ LST-COLUMNS! 3 _LW @ LST-ROWS!",
            "1 _LW @ LST-SELECT _LW @ WDG-DRAW",
            "0 _ROW$ 1 _ROW$ 2 _ROW$ 3 _ROW$",
            "1 3 SCR-GET CELL-ATTRS@ CELL-A-REVERSE AND 0<> 2 EMIT . 3 EMIT",
            "2 3 SCR-GET CELL-ATTRS@ CELL-A-REVERSE AND 0<> 2 EMIT . 3 EMIT",
        ]
    ).decode("utf-8", errors="replace")
    assert "not found" not in output, output[-2000:]
    # Name takes 20 - 4 - 1 cells; Size ends at the right edge.
    assert _screen_rows(output) == [
        "Name            Size",
        "AA                 7",
        "BB                42",
        "CC               512",
    ]
    reversed_rows = [int(v) for v in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    assert reversed_rows == [0, -1]


def test_a_list_follows_item_events_and_opens_the_selection() -> None:
    values = _numbers(
        _list(5)
        + [
            "VARIABLE _LOPENED -1 _LOPENED !",
            ": _L-ON-OPEN  ( index widget -- )  DROP _LOPENED ! ;",
            "' _L-ON-OPEN _LW @ LST-ON-OPEN",
            ": _LITEM  ( key action -- consumed? )",
            "  KEY-MOUSE-ITEM-ACTION ! KEY-MOUSE-ITEM-KEY !",
            "  KEY-MOUSE-ITEM 0 0 _LW @ _PT ;",
            "3 KEY-ITEM-SELECT _LITEM _LW @ LST-SELECTED",
            "2 KEY-ITEM-OPEN _LITEM _LW @ LST-SELECTED _LOPENED @",
            # A key the view does not show is consumed and ignored.
            "9 KEY-ITEM-SELECT _LITEM _LW @ LST-SELECTED",
        ]
        + _report(7)
    )

    assert values == [1, -1, 1, 1, -1, 2, -1]


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
        # A node's address is its key.
        ": _TK  NIP ;",
        *_POINTER,
        "VARIABLE _TW",
        "_TN ' _TC ' _TN-NEXT ' _TLB ' _TLF ' _TK TREE-NEW _TW !",
        "_TW @ _TN TREE-EXPAND",
        ": _TCUR  _TW @ _TREE-SETTLE _TREE-CUR-ROW @ ;",
    ]


def test_tree_press_moves_the_cursor_and_toggles_on_an_arrow() -> None:
    values = _numbers(
        _tree(10)
        + [
            "KEY-MOUSE-LEFT 1 10 _TW @ _PT",
            "_TCUR",
            # ChildB is at depth 1, so its arrow is column 2.
            "KEY-MOUSE-LEFT 2 2 _TW @ _PT",
            "_TCUR _TW @ _TREE-VIS-COUNT",
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
            "_TCUR",
        ]
        + _report(3)
    )

    assert values == [0, 0, -1]


def test_tree_wheel_scrolls_the_visible_rows_without_moving_the_cursor() -> None:
    values = _numbers(
        _tree(2)
        + [
            "KEY-MOUSE-SCROLL-DN 0 0 _TW @ _PT",
            "_TW @ _TREE-O-SCROLL + @ _TCUR",
            "KEY-MOUSE-SCROLL-DN 0 0 _TW @ _PT",
            "_TW @ _TREE-O-SCROLL + @",
            "KEY-MOUSE-SCROLL-UP 0 0 _TW @ _PT",
            "_TW @ _TREE-O-SCROLL + @",
        ]
        + _report(7)
    )

    # Three visible rows in two scroll at most one row.
    assert values == [0, -1, 1, -1, 0, 1, -1]


def test_tree_expansion_follows_keys_when_rows_above_change() -> None:
    values = _numbers(
        _tree(10)
        + [
            # Expand ChildB, collapse Root, and expand Root again: ChildB
            # is still expanded, so Grandchild shows.
            "_TW @ _TN 64 + TREE-EXPAND _TW @ _TREE-VIS-COUNT",
            "_TW @ _TN TREE-COLLAPSE _TW @ _TREE-VIS-COUNT",
            "_TW @ _TN TREE-EXPAND _TW @ _TREE-VIS-COUNT",
            # A leaf does not expand.
            "_TW @ _TN 32 + TREE-EXPAND _TW @ _TREE-VIS-COUNT",
        ]
        + _report(4)
    )

    assert values == [4, 4, 1, 4]


_TREE_ITEM = [
    ": _TITEM  ( key action -- consumed? )",
    "  KEY-MOUSE-ITEM-ACTION ! KEY-MOUSE-ITEM-KEY !",
    "  KEY-MOUSE-ITEM 0 0 _TW @ _PT ;",
    "CREATE _KEV 24 ALLOT",
    ": _TKEY  ( code -- consumed? )",
    "  KEY-T-SPECIAL _KEV ! _KEV 8 + ! 0 _KEV 16 + ! _KEV _TW @ WDG-HANDLE ;",
]


def test_tree_item_events_name_nodes_by_key() -> None:
    values = _numbers(
        _tree(10)
        + _TREE_ITEM
        + [
            "VARIABLE _TOPENED 0 _TOPENED !",
            ": _T-ON-OPEN  ( w -- )  TREE-SELECTED _TOPENED ! ;",
            "_TN 64 + KEY-ITEM-EXPAND _TITEM _TW @ _TREE-VIS-COUNT",
            "_TN 96 + KEY-ITEM-SELECT _TITEM _TCUR",
            # Collapsing ChildB moves the selection up to it.
            "_TN 64 + KEY-ITEM-COLLAPSE _TITEM _TCUR _TW @ _TREE-VIS-COUNT",
            "' _T-ON-OPEN _TW @ TREE-ON-OPEN",
            "_TN 32 + KEY-ITEM-OPEN _TITEM _TOPENED @ _TN 32 + =",
            # A key no longer shown is consumed and changes nothing.
            "_TN 96 + KEY-ITEM-SELECT _TITEM _TCUR",
        ]
        + _report(11)
    )

    assert values == [1, -1, -1, -1, 3, 2, -1, 3, -1, 4, -1]


def test_tree_left_collapses_then_moves_to_the_parent() -> None:
    values = _numbers(
        _tree(10)
        + _TREE_ITEM
        + [
            "_TN 64 + KEY-ITEM-EXPAND _TITEM DROP",
            "_TN 96 + KEY-ITEM-SELECT _TITEM DROP",
            "KEY-LEFT _TKEY _TCUR",
            "KEY-LEFT _TKEY _TW @ _TREE-VIS-COUNT",
            "KEY-LEFT _TKEY _TCUR",
            "KEY-DOWN _TKEY _TCUR",
            # Enter on a leaf with no open callback changes nothing.
            "KEY-ENTER _TKEY _TW @ _TREE-VIS-COUNT",
        ]
        + _report(10)
    )

    assert values == [3, -1, 1, -1, 0, -1, 3, -1, 2, -1]


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
            "_ECOUNT @ _ESEL @ _EW @ EXPL-TREE TREE-SELECTED =",
            "_EW @ EXPL-TREE _TREE-SETTLE _TREE-CUR-ROW @",
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


# ( code mods -- consumed? ) key events for the field, with modifiers.
_KEYS = [
    "CREATE _KEV 24 ALLOT",
    ": _KY  >R _KEV ! _KEV 16 + ! _KEV 8 + ! _KEV R> WDG-HANDLE ;",
    ": _SP  KEY-T-SPECIAL _IW @ _KY ;",
    ": _CH  KEY-T-CHAR _IW @ _KY ;",
]


def test_input_keys_leave_the_callers_stack_alone() -> None:
    """Every key, handled or not, replaces its two inputs with one flag.

    The handler once ate a caller's cell on Right, Home, End, Backspace,
    Delete, and Left at the start, and left an extra cell for keys it did
    not handle, in every application prompt.
    """

    values = _numbers(
        _field()
        + _KEYS
        + [
            ": _BAL  ( code -- intact? )  111 SWAP 0 _SP DROP 111 = ;",
            "VARIABLE _D0 DEPTH _D0 !",
            "KEY-RIGHT _BAL KEY-HOME _BAL KEY-LEFT _BAL KEY-END _BAL",
            "KEY-BACKSPACE _BAL KEY-DEL _BAL KEY-ENTER _BAL",
            "KEY-UP _BAL KEY-F1 _BAL",
            "DEPTH _D0 @ -",
        ]
        + _report(10)
    )

    assert values == [9] + [-1] * 9


def test_input_shift_keys_select_and_editing_replaces_the_selection() -> None:
    values = _numbers(
        _field()
        + _KEYS
        + [
            "KEY-HOME 0 _SP DROP",
            "KEY-RIGHT KEY-MOD-SHIFT _SP DROP KEY-RIGHT KEY-MOD-SHIFT _SP DROP",
            # "Aé" is three bytes.
            "_IW @ _INP-SEL-RANGE",
            "120 0 _CH",
            "_IW @ INP-GET-TEXT NIP _IW @ _INP-SEL? _IW @ INP-CURSOR-POS",
            "KEY-END KEY-MOD-SHIFT _SP DROP KEY-LEFT KEY-MOD-SHIFT _SP DROP",
            "_IW @ _INP-SEL-RANGE",
            # A move without Shift drops the selection.
            "KEY-RIGHT 0 _SP DROP _IW @ _INP-SEL? _IW @ INP-CURSOR-POS",
            "KEY-HOME KEY-MOD-SHIFT _SP DROP KEY-BACKSPACE 0 _SP",
            "_IW @ INP-GET-TEXT NIP",
        ]
        + _report(12)
    )

    assert values == [0, -1, 3, 0, 2, 1, 1, 0, 3, -1, 3, 0]


def test_input_drag_selects_from_a_press_made_in_the_field() -> None:
    values = _numbers(
        _field()
        + _KEYS
        + [
            "KEY-MOUSE-LEFT 2 6 _IW @ _PT",
            "KEY-MOUSE-DRAG 2 8 _IW @ _PT",
            "_IW @ _INP-SEL-RANGE",
            "KEY-MOUSE-RELEASE 2 8 _IW @ _PT",
            "122 0 _CH _IW @ INP-GET-TEXT NIP",
            # With no press held here, drags and releases pass through.
            "KEY-MOUSE-DRAG 2 6 _IW @ _PT KEY-MOUSE-RELEASE 2 6 _IW @ _PT",
            # A Shift press extends from the caret.
            "KEY-MOUSE-LEFT 2 5 _IW @ _PT DROP",
            "KEY-MOUSE-LEFT KEY-MOUSE-MOD-SHIFT OR 2 7 _IW @ _PT",
            "_IW @ _INP-SEL-RANGE",
            "KEY-MOUSE-RELEASE 2 7 _IW @ _PT DROP",
            # Dragging back to the press point leaves no selection.
            "KEY-MOUSE-LEFT 2 6 _IW @ _PT DROP",
            "KEY-MOUSE-DRAG 2 8 _IW @ _PT DROP KEY-MOUSE-DRAG 2 6 _IW @ _PT DROP",
            "_IW @ _INP-SEL?",
        ]
        + _report(13)
    )

    # "éC" is bytes 1..4; after typing over it the text is "AzD".
    assert values == [0, 2, 0, -1, 0, 0, 3, -1, -1, 4, 1, -1, -1]


def test_input_drag_past_either_edge_scrolls_one_column_per_step() -> None:
    values = _numbers(
        _field()
        + [
            "CREATE _NBUF 64 ALLOT VARIABLE _NW",
            "4 5 1 4 RGN-NEW _NBUF 64 INP-NEW _NW !",
            'S" abcdefgh" _NW @ INP-SET-TEXT',
            "0 _NW @ _INP-O-SCROLL + !",
            ": _NSTATE  _NW @ WDG-DRAW"
            "  _NW @ _INP-O-CURSOR + @ _NW @ _INP-O-SCROLL + @ ;",
            "KEY-MOUSE-LEFT 4 5 _NW @ _PT DROP",
            "KEY-MOUSE-DRAG 4 9 _NW @ _PT DROP _NSTATE",
            "KEY-MOUSE-DRAG 4 12 _NW @ _PT DROP _NSTATE",
            "KEY-MOUSE-DRAG 4 2 _NW @ _PT DROP _NSTATE",
            "_NW @ _INP-O-ANCHOR + @",
        ]
        + _report(7)
    )

    assert values == [0, 1, 1, 2, 5, 1, 4]


def test_input_ctrl_and_alt_letters_are_not_typed_but_ctrl_a_selects_all() -> None:
    values = _numbers(
        _field()
        + _KEYS
        + [
            "115 KEY-MOD-CTRL _CH 120 KEY-MOD-ALT _CH",
            "_IW @ INP-GET-TEXT NIP",
            "97 KEY-MOD-CTRL _CH _IW @ _INP-SEL-RANGE",
            "81 0 _CH DROP _IW @ INP-GET-TEXT NIP",
        ]
        + _report(7)
    )

    assert values == [1, 5, 0, -1, 5, 0, 0]


def test_input_draws_the_selection_reversed_without_the_caret() -> None:
    values = _numbers(
        _field()
        + [
            "_IW @ WDG-FOCUS-SET",
            "1 _IW @ _INP-O-ANCHOR + ! 4 _IW @ _INP-O-CURSOR + !",
            "_IW @ WDG-DRAW",
            ": _REV?  ( col -- flag )  CELL-A-REVERSE 2 ROT SCR-GET CELL-HAS-ATTR? ;",
            "5 _REV? 6 _REV? 7 _REV? 8 _REV?",
            # Without a selection the caret shows on the codepoint after it.
            "-1 _IW @ _INP-O-ANCHOR + ! _IW @ WDG-DRAW 8 _REV?",
        ]
        + _report(5)
    )

    assert values == [-1, 0, -1, -1, 0]



# Characters, cells, and right-to-left text
# ---------------------------------------------------------------------
#
# The field lays its text out as one paragraph (APT-1-TEXT): a character
# takes its width in cells, right-to-left text starts at the field's right
# edge, and the caret and pointer move by whole characters.


def _text_field(text: str, width: int = 20) -> list[str]:
    """A focused field at row 2, column 5, holding TEXT with the caret at
    its end."""

    return [
        "80 24 SCR-NEW DUP SCR-USE SCR-CLEAR",
        "CREATE _TBUF 64 ALLOT",
        *_POINTER,
        "VARIABLE _TW",
        f"2 5 1 {width} RGN-NEW _TBUF 64 INP-NEW _TW !",
        "_TW @ WDG-FOCUS-SET",
        f'S" {text}" _TW @ INP-SET-TEXT',
        "CREATE _TEV 24 ALLOT",
        ": _TK  ( code type -- )  _TEV ! _TEV 8 + ! 0 _TEV 16 + !",
        "  _TEV _TW @ WDG-HANDLE DROP ;",
        ": _TSP  ( code -- )  KEY-T-SPECIAL _TK ;",
        ": _TCH  ( cp -- )  KEY-T-CHAR _TK ;",
        ": _TCUR  ( -- off )  _TW @ _INP-O-CURSOR + @ ;",
        ": _TLEN  ( -- u )  _TW @ INP-GET-TEXT NIP ;",
        ": _TCLICK  ( col -- off )  KEY-MOUSE-LEFT 2 ROT _TW @ _PT DROP _TCUR ;",
        # One cell: its scalar count, its scalars, and its attributes.
        ": _TCELL  ( col -- )  2 SWAP SCR-GET",
        "  DUP CELL-CP@ CELL-CP-CLUSTER AND IF",
        "    DUP SCR-CLUSTER@ DUP . 0 ?DO DUP I 4 * + L@ . LOOP DROP",
        "  ELSE 1 . DUP CELL-CP@ . THEN CELL-ATTRS@ . ;",
        ": _TCELLS  ( first last -- )  2 EMIT 1+ SWAP DO I _TCELL LOOP 3 EMIT ;",
        "_TW @ WDG-DRAW",
    ]


def _cells(
    lines: list[str], first: int, last: int
) -> list[tuple[tuple[int, ...], int]]:
    """Run LINES, then read the field row's cells FIRST..LAST."""

    output = _run_forth(lines + [f"{first} {last} _TCELLS"]).decode(
        "utf-8", errors="replace"
    )
    assert "not found" not in output and "underflow" not in output, output
    begin = output.rindex("\x02")
    values = [
        int(token)
        for token in re.findall(r"-?\d+", output[begin + 1 : output.index("\x03", begin)])
    ]
    cells, index = [], 0
    while index < len(values):
        count = values[index]
        cells.append(
            (tuple(values[index + 1 : index + 1 + count]), values[index + 1 + count])
        )
        index += count + 2
    return cells


_REVERSE, _WIDE, _CONT = 32, 128, 256

# "a", a wide Han character, e with a combining acute, a flag, and "b":
# sixteen bytes, five characters, seven cells.
_MIXED = "a\u4e2de\u0301\U0001F1EF\U0001F1F5b"


def test_input_moves_and_deletes_whole_characters() -> None:
    values = _numbers(
        _text_field(_MIXED)
        + [
            "KEY-HOME _TSP",
            "KEY-RIGHT _TSP _TCUR KEY-RIGHT _TSP _TCUR KEY-RIGHT _TSP _TCUR",
            "KEY-RIGHT _TSP _TCUR KEY-RIGHT _TSP _TCUR",
            "KEY-LEFT _TSP _TCUR KEY-LEFT _TSP _TCUR _TW @ INP-CURSOR-POS",
            # Backspace removes the accented e's two scalars, then the flag's.
            "KEY-BACKSPACE _TSP _TCUR _TLEN",
            "KEY-RIGHT _TSP KEY-BACKSPACE _TSP _TCUR _TLEN",
            # Delete removes "b", then the Han character.
            "KEY-DEL _TSP _TLEN",
            "KEY-LEFT _TSP _TCUR KEY-DEL _TSP _TLEN",
        ]
        + _report(15)
    )

    # Printed top first.
    assert values == [1, 1, 4, 5, 4, 13, 4, 3, 7, 15, 16, 15, 7, 4, 1]


def test_input_draws_characters_in_their_cells_with_the_caret_after_them() -> None:
    assert _cells(_text_field(_MIXED), 5, 12) == [
        ((ord("a"),), 0),
        ((0x4E2D,), _WIDE),
        ((0,), _CONT),
        ((ord("e"), 0x301), 0),
        ((0x1F1EF, 0x1F1F5), _WIDE),
        ((0,), _CONT),
        ((ord("b"),), 0),
        # The caret at the end is a reversed blank past the content.
        ((32,), _REVERSE),
    ]


_HEBREW = "\u05e9\u05dc\u05d5\u05dd"  # four letters, eight bytes


def test_input_right_to_left_text_starts_at_the_right_edge() -> None:
    # The field's twenty cells end at column 24.  The caret at the end sits
    # just left of the mirrored text, on its end side.
    assert _cells(_text_field(_HEBREW), 20, 24) == [
        ((32,), _REVERSE),
        ((0x5DD,), 0),
        ((0x5D5,), 0),
        ((0x5DC,), 0),
        ((0x5E9,), 0),
    ]
    # A click names the character under it; left of the text, the end side,
    # names the end, and right of it the start.
    values = _numbers(
        _text_field(_HEBREW)
        + ["24 _TCLICK 22 _TCLICK 10 _TCLICK"]
        + _report(3)
    )
    assert values == [8, 4, 0]


def test_input_masks_whole_characters() -> None:
    lines = _text_field("e\u0301x") + ["42 _TW @ INP-MASK! _TW @ WDG-DRAW"]
    assert _cells(lines, 5, 7) == [((42,), 0), ((42,), 0), ((32,), _REVERSE)]
    values = _numbers(lines + ["_TW @ INP-CURSOR-POS"] + _report(1))
    assert values == [2]


def test_input_typing_keeps_the_caret_between_characters() -> None:
    # A base typed before a lone combining mark joins it into one
    # character, and the caret moves past both.
    values = _numbers(
        _text_field("\u0301")
        + ["KEY-HOME _TSP 101 _TCH _TCUR _TLEN"]
        + _report(2)
    )
    assert values == [3, 3]


def test_input_scrolls_a_wide_character_fully_into_view() -> None:
    # Four cells from the start: with the caret on the second Han character
    # the field scrolls two cells, not one, so both of its cells show.
    lines = _text_field("ab\u4e2d\u6587", width=4) + [
        "KEY-HOME _TSP KEY-RIGHT _TSP KEY-RIGHT _TSP KEY-RIGHT _TSP",
        "0 _TW @ _INP-O-SCROLL + ! _TW @ WDG-DRAW",
    ]
    assert _cells(lines, 5, 8) == [
        ((0x4E2D,), _WIDE),
        ((0,), _CONT),
        ((0x6587,), _WIDE | _REVERSE),
        ((0,), _CONT | _REVERSE),
    ]
    values = _numbers(lines + ["_TW @ _INP-O-SCROLL + @"] + _report(1))
    assert values == [2]


# ---------------------------------------------------------------------
# UIDL-TUI forwarding
# ---------------------------------------------------------------------


def test_uidl_repaints_a_widget_and_its_scroll_after_consumed_pointer_input() -> None:
    """UIDL paints only dirty elements, so forwarding must mark them.

    A list mounted inside <scroll> scrolls on a wheel step; its element and
    the scroll container (whose thumb follows the list) must both repaint.
    An event the widget refuses repaints nothing.
    """

    values = _numbers(
        [
            "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR",
            "VARIABLE _UR 0 0 24 80 RGN-NEW _UR !",
            'S" <uidl><scroll id=s><region id=r/></scroll></uidl>" '
            "_UR @ UTUI-LOAD DROP",
            ": _ULK  ( index widget -- key )  DROP 1+ ;",
            ': _ULF  ( index column widget -- addr len )  2DROP DROP S" row" ;',
            ': _UE  ( -- elem )  S" r" UTUI-BY-ID ;',
            ': _US  ( -- elem )  S" s" UTUI-BY-ID ;',
            ": _UCELL  ( -- row col )  _UE _UTUI-SIDECAR DUP _UTUI-SC-ROW@"
            " SWAP _UTUI-SC-COL@ ;",
            "VARIABLE _UL",
            "_UE UTUI-ELEM-RGN RGN-NEW ' _ULK ' _ULF LST-NEW _UL !",
            "30 _UL @ LST-ROWS!",
            "_UL @ _UE UTUI-WIDGET-SET",
            "UTUI-PAINT",
            "_UE UIDL-DIRTY? _US UIDL-DIRTY?",
            "_UCELL 2DUP KEY-MOUSE-RIGHT UTUI-DISPATCH-POINTER",
            "_UE UIDL-DIRTY? _US UIDL-DIRTY?",
            "_UCELL 2DUP KEY-MOUSE-SCROLL-DN UTUI-DISPATCH-POINTER",
            "_UL @ _LST-O-SCROLL + @",
            "_UE UIDL-DIRTY? _US UIDL-DIRTY?",
        ]
        + _report(9),
        roots=UIDL_ROOTS,
    )

    # Printed top first: the wheel scrolled three rows and dirtied both
    # elements; before it, the refused press left both clean.
    assert values == [-1, -1, 3, -1, 0, 0, 0, 0, 0]
