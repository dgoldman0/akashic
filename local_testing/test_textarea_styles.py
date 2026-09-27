#!/usr/bin/env python3
"""Styled text and links in the canonical text area, in CELL.

A text area with a style source draws each meaning in its palette's look:
the meaning's colour, with its attributes added to the drawing style's.
Plain text keeps the drawing style.  Ctrl and a primary press on a link,
or a renderer's FOLLOW at one, calls the follow word; a plain press still
places the caret.
"""

from __future__ import annotations

import re

from test_widget_pointer import _run_forth

ROOTS = ("tui/widgets/textarea.f", "text/syntax.f")

BASE_FG = 253
BOLD, ITALIC, UNDERLINE, REVERSE = 1, 4, 8, 32
# The default palette (tui/style-palette.f).
HEADING = (215, BOLD)
LINK = (75, UNDERLINE)
STRONG = (231, BOLD)
CODE = (114, 0)
PLAIN = (BASE_FG, 0)

# A 40x6 screen and a text area at rows 1-4, columns 2-39, no gutter.
_SETUP = [
    "VARIABLE _W",
    "CREATE _BUF 512 ALLOT",
    "CREATE _EV 24 ALLOT",
    "40 6 SCR-NEW SCR-USE",
    "1 2 4 38 RGN-NEW _BUF 512 TXTA-NEW _W !",
    ": _SET  ( a u -- )  _W @ TXTA-SET-TEXT ;",
    ": _DRAW  SCR-CLEAR 253 DRW-FG! 234 DRW-BG! 0 DRW-ATTR! _W @ WDG-DRAW ;",
    # Each cell as: codepoint fg attrs, without the wide-cell marks.
    ": _CELL  ( row col -- )  SCR-GET DUP CELL-CP@ . DUP CELL-FG@ . CELL-ATTRS@ 0x7F AND . ;",
    ": _ROW  ( row col n -- )  18 EMIT 0 ?DO 2DUP I + _CELL LOOP 2DROP 19 EMIT ;",
    ": _N  ( n -- )  2 EMIT . 3 EMIT ;",
    # ( code row col -- consumed? ) with 0-based absolute screen cells.
    ": _PRESS  SWAP 16 LSHIFT OR _EV 16 + ! _EV 8 + ! KEY-T-MOUSE _EV ! _EV _W @ WDG-HANDLE ;",
    ": _TEXT  ( code key offset -- consumed? )",
    "  KEY-MOUSE-TEXT-OFFSET ! KEY-MOUSE-TEXT-KEY ! 1 2 _PRESS ;",
    # The follow word prints the link target and the press's byte offset.
    ": _FOLLOW  ( line-a line-u pos widget -- )",
    "  DROP DUP _N SYN-MD-LINK-AT DROP 18 EMIT TYPE 19 EMIT ;",
]


def _bytes(name: str, text: str) -> list[str]:
    data = text.encode("utf-8")
    return [
        f"CREATE {name} " + " ".join(f"{byte} C," for byte in data),
        f": {name}$  {name} {len(data)} ;",
    ]


def _run(lines: list[str]):
    output = _run_forth(_SETUP + lines, roots=ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    groups = re.findall("\x12(.*?)\x13", output, re.S)
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    return groups, numbers


def _cells(group: str) -> list[tuple[str, int, int]]:
    tokens = [int(token) for token in group.split()]
    return [
        (chr(tokens[i]) if tokens[i] else "", tokens[i + 1], tokens[i + 2])
        for i in range(0, len(tokens), 3)
    ]


def _expect(text: str, spans: list[tuple[str, tuple[int, int]]]) -> list[tuple[str, int, int]]:
    """Cells of an LTR line of one-cell characters, each piece in its look."""

    looks = [PLAIN] * len(text)
    cursor = 0
    for piece, look in spans:
        start = text.index(piece, cursor)
        for index in range(start, start + len(piece)):
            looks[index] = look
        cursor = start + len(piece)
    return [(char, fg, attrs) for char, (fg, attrs) in zip(text, looks)]


def test_markdown_lines_draw_each_meaning_in_its_palette_look() -> None:
    heading = "# Plan"
    body = "See **it** and [x](b.md) `c`"
    groups, _ = _run([
        "SYN-LANG-MD _W @ TXTA-STYLE!",
        *_bytes("_T", heading + "\n" + body),
        "_T$ _SET 0 _W @ TXTA-SCROLL-SET",
        "_W @ WDG-FOCUS-CLR _DRAW",
        f"1 2 {len(heading)} _ROW",
        f"2 2 {len(body)} _ROW",
        # Without a style source the same text is plain.
        "0 _W @ TXTA-STYLE! _DRAW",
        f"2 2 {len(body)} _ROW",
    ])
    assert _cells(groups[0]) == _expect(heading, [(heading, HEADING)])
    assert _cells(groups[1]) == _expect(body, [
        ("**it**", STRONG), ("[x](b.md)", LINK), ("`c`", CODE),
    ])
    assert _cells(groups[2]) == _expect(body, [])


def test_laid_out_lines_and_selections_keep_their_styles() -> None:
    # A wide character sends the line through the laid-out path.
    line = "中 [文](c.md)!"
    groups, _ = _run([
        "SYN-LANG-MD _W @ TXTA-STYLE!",
        *_bytes("_T", line),
        "_T$ _SET",
        "_W @ WDG-FOCUS-CLR _DRAW",
        "1 2 14 _ROW",
        # Select the whole line: marked cells add reverse to their look.
        "_W @ TXTA-SELECT-ALL _DRAW",
        "1 2 14 _ROW",
    ])
    cells = _cells(groups[0])
    # 中 takes cells 0 and 1 (its continuation cell has no codepoint).
    assert cells[0] == ("中", *PLAIN)
    assert cells[2] == (" ", *PLAIN)
    link = cells[3:12]
    assert [cell[0] for cell in link] == ["[", "文", "", "]", "(", "c", ".", "m", "d"]
    assert all(cell[1:] == LINK or cell[0] == "" for cell in link)
    assert cells[12] == (")", *LINK)
    assert cells[13] == ("!", *PLAIN)
    marked = _cells(groups[1])
    assert marked[3] == ("[", LINK[0], LINK[1] | REVERSE)
    assert marked[13] == ("!", BASE_FG, REVERSE)


def test_a_palette_changes_the_look_of_a_meaning() -> None:
    line = "[x](y.md)"
    groups, _ = _run([
        "SYN-LANG-MD _W @ TXTA-STYLE!",
        "CREATE _PAL SPAL-SIZE ALLOT  _PAL SPAL-INIT",
        "33 CELL-A-BOLD TSTY-LINK _PAL SPAL-SET",
        "_PAL _W @ TXTA-PALETTE!",
        *_bytes("_T", line),
        "_T$ _SET _W @ WDG-FOCUS-CLR _DRAW",
        f"1 2 {len(line)} _ROW",
    ])
    assert _cells(groups[0]) == _expect(line, [(line, (33, BOLD))])


def test_ctrl_press_on_a_link_follows_it_and_a_plain_press_places_the_caret() -> None:
    line = "go [notes](docs/notes.md) now"
    on_link = line.index("notes")          # a cell on the link
    off_link = line.index("now")
    groups, numbers = _run([
        "SYN-LANG-MD _W @ TXTA-STYLE!",
        "' _FOLLOW _W @ TXTA-ON-FOLLOW!",
        *_bytes("_T", line),
        "_T$ _SET _DRAW",
        # Ctrl (SGR 16) and a primary press on the link follows it.
        f"KEY-MOUSE-LEFT KEY-MOUSE-MOD-CTRL OR 1 {2 + on_link} _PRESS _N",
        "_W @ TXTA-CURSOR-COL _N",
        # A plain press on the link places the caret.
        f"KEY-MOUSE-LEFT 1 {2 + on_link} _PRESS _N",
        "_W @ TXTA-CURSOR-COL _N",
        # Ctrl and a press off any link places the caret too.
        f"KEY-MOUSE-LEFT KEY-MOUSE-MOD-CTRL OR 1 {2 + off_link} _PRESS _N",
        "_W @ TXTA-CURSOR-COL _N",
        # A renderer's FOLLOW names the line key and a scalar offset.
        f"KEY-MOUSE-TEXT-FOLLOW 1 {on_link} _TEXT _N",
        # One that no longer lies on a link is dropped, but consumed.
        f"KEY-MOUSE-TEXT-FOLLOW 1 {off_link} _TEXT _N",
        "_W @ TXTA-CURSOR-COL _N",
        # Without a follow word nothing is followed and the press places.
        "0 _W @ TXTA-ON-FOLLOW!",
        f"KEY-MOUSE-LEFT KEY-MOUSE-MOD-CTRL OR 1 {2 + on_link} _PRESS _N",
        "_W @ TXTA-CURSOR-COL _N",
    ])
    assert groups == ["docs/notes.md", "docs/notes.md"]
    assert numbers == [
        # the follow word saw the press's byte offset, then was consumed;
        # the caret stayed at the text's end
        on_link, -1, len(line),
        -1, on_link,
        -1, off_link,
        on_link, -1,
        -1, off_link,
        -1, on_link,
    ]
