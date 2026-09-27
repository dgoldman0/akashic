#!/usr/bin/env python3
"""Widgets measure text in cells and never split a character (APT-1-TEXT).

Labels, menu bars, and tab strips place text by its width in cells, and
their clicks follow the same widths.  A label or box title too wide for its
room is clipped by cells, so a wide character the edge cuts shows blanks.
Text grid items are laid out as paragraphs, a right-to-left item set against
its rectangle's right edge.  Dialogs size and wrap their message in cells,
between whole characters.  MegaPad's reference text rules give the cells.
"""

from __future__ import annotations

import re

from test_widget_pointer import _run_forth  # also puts MegaPad on the path

from rich_terminal.text_rules import char_width, characters, layout_row

ROOTS = ("tui/uidl-tui.f",)

HAN = "\u4e2d\u6587"            # two wide Han characters
HEBREW = "\u05e9\u05dc\u05d5\u05dd"
ACCENT = "e\u0301"               # e with a combining acute

_CELL_WORDS = [
    ": _WC  ( cell -- )",
    "  DUP CELL-CP@ CELL-CP-CLUSTER AND IF",
    "    DUP SCR-CLUSTER@ DUP . 0 ?DO DUP I 4 * + L@ . LOOP DROP",
    "  ELSE 1 . DUP CELL-CP@ . THEN",
    "  CELL-ATTRS@ . ;",
    # Control characters mark the output, which echoed source cannot hold.
    ": _WROW  ( row col n -- )  18 EMIT 0 ?DO 2DUP I + SCR-GET _WC LOOP 2DROP 19 EMIT ;",
    ": _WN  ( n -- )  2 EMIT . 3 EMIT ;",
]


def _run(lines: list[str]) -> tuple[list[list[str]], list[int]]:
    """Each printed row as its cells' text ("" for a wide character's
    second cell), and each printed number."""

    output = _run_forth(_CELL_WORDS + lines, roots=ROOTS).decode(
        "utf-8", errors="replace"
    )
    assert "not found" not in output and "underflow" not in output, output[-2000:]
    rows = []
    for body in re.findall("\x12(.*?)\x13", output, re.S):
        tokens = [int(token) for token in body.split()]
        cells, index = [], 0
        while index < len(tokens):
            count = tokens[index]
            scalars = tokens[index + 1 : index + 1 + count]
            cells.append("" if scalars == [0] else "".join(map(chr, scalars)))
            index += count + 2
        rows.append(cells)
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    return rows, numbers


def _field(text: str, width: int, *, right: bool = False) -> list[str]:
    """The cells of a field WIDTH wide showing TEXT as one AUTO paragraph,
    from its left edge, or against its right edge when RIGHT and the
    paragraph is right-to-left; a wide character the edge cuts shows
    blanks."""

    layout = layout_row(text)
    origin = width - layout.width if right and layout.rtl else 0
    cells = [" "] * width
    for placed in layout.characters:
        column = origin + placed.column
        if placed.width == 1:
            if 0 <= column < width:
                cells[column] = placed.text
        elif 0 <= column and column + 1 < width:
            cells[column], cells[column + 1] = placed.text, ""
        else:
            for part in (column, column + 1):
                if 0 <= part < width:
                    cells[part] = " "
    return cells


def _wrap(text: str, width: int) -> list[str]:
    """TEXT's rows when wrapped to WIDTH cells between whole characters."""

    rows, row, used = [], "", 0
    for character in characters(text):
        cells = char_width(character)
        if row and used + cells > width:
            rows.append(row)
            row, used = "", 0
        row += character
        used += cells
    return rows + [row] if row else rows or [""]


def test_a_uidl_label_too_wide_is_clipped_by_cells() -> None:
    label = "a" + HAN + "\u5b57"         # 7 cells in a 6-cell label
    rows, _ = _run(
        [
            "40 10 SCR-NEW DUP SCR-USE SCR-CLEAR",
            "VARIABLE _UR 0 0 10 6 RGN-NEW _UR !",
            f'S" <uidl><region><label id=a text={label}/></region></uidl>" '
            "_UR @ UTUI-LOAD DROP",
            "UTUI-PAINT",
            "0 0 8 _WROW",
        ]
    )
    # The last character's first cell is kept as a blank, and nothing
    # spills past the label.
    assert rows == [_field(label, 6) + [" ", " "]]


def test_uidl_tabs_and_menus_place_and_hit_labels_by_cells() -> None:
    rows, numbers = _run(
        [
            "40 10 SCR-NEW DUP SCR-USE SCR-CLEAR",
            "VARIABLE _UR 0 0 10 40 RGN-NEW _UR !",
            f'S" <uidl><tabs id=t><tab label={HAN}><region/></tab>'
            '<tab label=b><region/></tab></tabs></uidl>" _UR @ UTUI-LOAD DROP',
            "UTUI-PAINT",
            "0 0 10 _WROW",
            # The second label's cell: after the first's four cells and a gap.
            "0 7 0 7 KEY-MOUSE-LEFT UTUI-DISPATCH-POINTER DROP",
            'S" t" UTUI-BY-ID _UTUI-TABS-ACTIVE@ _WN',
            "SCR-CLEAR",
            f'S" <uidl><menubar><menu label={HAN}><item text=x/></menu>'
            '<menu label=b><item text=y/></menu></menubar></uidl>" '
            "_UR @ UTUI-LOAD DROP",
            "UTUI-PAINT",
            "0 0 10 _WROW",
        ]
    )
    tabs, menus = rows
    for cells in (tabs, menus):
        assert cells[1:5] == _field(HAN, 4)
        assert cells[7] == "b"
    assert numbers == [1]


def test_the_tab_widget_places_and_hits_labels_by_cells() -> None:
    name = HAN + ".txt"                    # 8 cells, 10 bytes
    rows, numbers = _run(
        [
            "40 10 SCR-NEW DUP SCR-USE SCR-CLEAR",
            "VARIABLE _TW 0 0 5 30 RGN-NEW TAB-NEW _TW !",
            # The widget keeps its labels' addresses, so they must last.
            f': _L1 S" {name}" ;',
            ': _L2 S" b" ;',
            "_L1 _TW @ TAB-ADD DROP",
            "_L2 _TW @ TAB-ADD DROP",
            "_TW @ WDG-DRAW",
            "0 0 14 _WROW",
            "0 11 _TW @ TAB-HIT-INDEX _WN _WN",
        ]
    )
    # " name " then " b ": the second tab begins after eight cells and two
    # blanks, and a click on its label selects it.
    assert rows[0][1:9] == _field(name, 8)
    assert rows[0][10:13] == [" ", "b", " "]
    assert numbers == [-1, 1]


def test_text_grid_items_are_laid_out_and_clipped_by_cells() -> None:
    items = {
        (0, 0): "a" + HAN + HAN,           # 9 cells in an 8-cell item
        (0, 1): HEBREW,                    # right-to-left: set to the right
        (1, 0): ACCENT + " ok",
        (1, 1): "ab",
    }
    lines = [
        "VARIABLE _GW VARIABLE _GU",
        "CREATE _GB-S USCOL-BUILDER-SIZE 7 + ALLOT",
        "CREATE _GM-S 1024 7 + ALLOT",
        "CREATE _GK-S 64 7 + ALLOT",
        "CREATE _GS-S USCOL-SUMMARY-SIZE 7 + ALLOT",
        ": _GB _GB-S 7 + -8 AND ;",
        ": _GM _GM-S 7 + -8 AND ;",
        ": _GK _GK-S 7 + -8 AND ;",
        ": _GS _GS-S 7 + -8 AND ;",
        ": _GOK  USCOL-S-OK <> ABORT\" grid builder\" ;",
        "40 10 SCR-NEW DUP SCR-USE SCR-CLEAR",
        "1 2 2 16 RGN-NEW TGRID-NEW _GW !",
        "_GM 1024 _GB USCOL-BUILDER-INIT _GOK",
        "USCOL-F-TEXT-GRID 1 0 0 2 16 3 _GB USCOL-TEXT-BEGIN _GOK",
        "USCOL-CONTENT-READ-ONLY 2 2 0 0 2 2 _GB USCOL-TEXT-SHAPE _GOK",
        "13 0 0 0 _GB USCOL-TEXT-POSITIONS _GOK",
    ]
    for key, ((row, column), text) in enumerate(sorted(items.items()), 10):
        lines.append(
            f'{key} {row} {column} 1 1 USCOL-ROLE-CONTENT 0 S" {text}" '
            "_GB USCOL-TEXT-ITEM _GOK"
        )
    lines += [
        "_GB USCOL-TEXT-END _GOK",
        "_GB USCOL-BUILDER-FINISH _GOK _GU !",
        "_GM _GU @ _GK 64 _GS _GW @ TGRID-BIND _GOK",
        "SCR-CLEAR _GW @ WDG-DRAW",
        "1 2 16 _WROW 2 2 16 _WROW",
    ]
    rows, _ = _run(lines)
    assert rows == [
        _field(items[0, 0], 8) + _field(items[0, 1], 8, right=True),
        _field(items[1, 0], 8) + _field(items[1, 1], 8),
    ]


def test_dialogs_wrap_between_characters_and_clip_their_title_by_cells() -> None:
    title = "\u6a19\u984c" * 6           # 24 cells for 18 cells of room
    message = "\u4e2d" * 8 + ACCENT + "\u4e2d" * 2
    width = 22                             # the message gets 22 - 4 cells
    rows, numbers = _run(
        [
            "40 12 SCR-NEW DUP SCR-USE SCR-CLEAR",
            "CREATE _DBTN 16 ALLOT",
            ': _DOK S" OK" ;',
            "_DOK _DBTN 8 + ! _DBTN !",
            # The dialog keeps its strings' addresses, so they must last.
            f': _DT S" {title}" ;',
            f': _DM S" {message}" ;',
            "_DT _DM _DBTN 1 DLG-NEW",
            f"1 1 8 {width} RGN-NEW OVER DLG-SET-REGION",
            "WDG-DRAW",
            "1 3 18 _WROW 3 3 18 _WROW 4 3 18 _WROW",
            f'S" {message}" 18 _DLG-MSG-LINES _WN',
        ]
    )
    title_row, *message_rows = rows
    assert title_row == _field(title, 18)
    wrapped = _wrap(message, width - 4)
    assert len(wrapped) == 2
    # The combined accent stays whole, on the first row.
    assert message_rows == [_field(line, 18) for line in wrapped]
    assert numbers == [2]
