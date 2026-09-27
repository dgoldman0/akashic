#!/usr/bin/env python3
"""Row layout on the cell grid: akashic/text/text-row.f.

The client and the terminal each lay out rows under APT-1-TEXT, and they
must agree cell for cell: the client draws CELL fallback and publishes
STX1, and the terminal lays STX1 out again for rich text.  These tests run
the Forth layout on mixed rows and compare every visible character with
MegaPad's independent implementation (rich_terminal/text_rules.py), which
itself passes Unicode's conformance files.
"""

from __future__ import annotations

import re
import sys

import pytest

import generate_unicode_text_tables as generator
from forth_snapshot import MEGAPAD_ROOT, ForthSnapshot, program_output

sys.path.insert(0, str(MEGAPAD_ROOT))

from rich_terminal import text_rules  # noqa: E402

try:
    generator.ucd_file(generator.DEFAULT_UCD, "UnicodeData.txt")
except generator.UcdError as exc:  # pragma: no cover - depends on the host
    pytest.skip(f"pinned Unicode 15.1.0 data unavailable: {exc}", allow_module_level=True)

SNAPSHOT = ForthSnapshot(("text/text-row.f",))

AUTO, LTR, RTL = 0, 1, 2
TAB, UNTRUSTED = 1, 2

_PRELUDE = [
    "CREATE _TT-BUF 4096 ALLOT  VARIABLE _TT-LEN",
    "CREATE _TT-ROW TROW-SIZE ALLOT  _TT-ROW TROW-INIT",
    "CREATE _TT-DISPLAY 1024 ALLOT",
    ": _TT-CLEAR 0 _TT-LEN ! ;",
    ": _TT-B ( byte -- ) _TT-BUF _TT-LEN @ + C! 1 _TT-LEN +! ;",
    ": _TT-TEXT ( -- a u ) _TT-BUF _TT-LEN @ ;",
    # Print one layout: its summary, then each visible character.
    ": _TT-SHOW ( -- )",
    '  ." ROW:" _TT-ROW TROW-LENGTH . _TT-ROW TROW-WIDTH . _TT-ROW TROW-PARA .',
    "  _TT-ROW TROW-VISIBLE 0 ?DO",
    '    ." |" I _TT-ROW TROW-VCHAR',
    "    DUP TROW.START . DUP TROW.SCALARS . DUP TROW.WIDTH . DUP TROW.LEVEL .",
    "    DUP TROW.COLUMN . _TT-DISPLAY _TT-ROW TROW-DISPLAY 0 ?DO",
    "      _TT-DISPLAY I 4 * + L@ .",
    "    LOOP",
    '  LOOP ." ;" CR ;',
    ": _TT-LAYOUT ( flags direction -- ) >R >R _TT-TEXT R> R> _TT-ROW TROW-LAYOUT",
    '  IF _TT-SHOW ELSE ." ROW-FAILED" CR THEN ;',
]


def _encode(text: str) -> list[str]:
    data = text.encode("utf-8")
    lines = ["_TT-CLEAR"]
    for start in range(0, len(data), 12):
        lines.append(" ".join(f"{byte} _TT-B" for byte in data[start:start + 12]))
    return lines


def _parse(output: str) -> list[tuple]:
    rows = []
    for match in re.finditer(r"ROW:([^;]*);", output):
        head, *chars = match[1].split("|")
        length, width, para = (int(v) for v in head.split())
        placed = []
        for char in chars:
            values = [int(v) for v in char.split()]
            start, scalars, cell_width, level, column, *display = values
            placed.append((start, scalars, cell_width, level, column, tuple(display)))
        rows.append((length, width, para, placed))
    return rows


def _expected(text: str, direction: int, keep_tab: bool) -> tuple:
    python_direction = {
        AUTO: text_rules.DIRECTION_AUTO,
        LTR: text_rules.DIRECTION_LTR,
        RTL: text_rules.DIRECTION_RTL,
    }[direction]
    layout = text_rules.layout_row(text, python_direction, keep_tab=keep_tab)
    placed = [
        (p.start, p.scalars, p.width, p.level, p.column, tuple(ord(ch) for ch in p.text))
        for p in layout.characters
    ]
    return layout.length, layout.width, layout.paragraph_level, placed


_ROWS = [
    ("Hello, world", AUTO, 0),
    ("\u4f60\u597d, \u4e16\u754c", AUTO, 0),
    ("e\u0301te\u0301 d'e\u0301te\u0301", AUTO, 0),
    ("\U0001F468\u200d\U0001F469\u200d\U0001F467 \U0001F44D\U0001F3FD \u2764\ufe0f", AUTO, 0),
    ("\U0001F1EF\U0001F1F5\U0001F1FA\U0001F1F8 flags", AUTO, 0),
    ("\u05e9\u05dc\u05d5\u05dd, world!", AUTO, 0),
    ("abc \u05d0\u05d1\u05d2 123 \u05d3\u05d4", AUTO, 0),
    ("\u05d0(\u05d1)[c]", AUTO, 0),
    ("\u0645\u0631\u062d\u0628\u0627 \u0628\u0627\u0644\u0639\u0627\u0644\u0645", AUTO, 0),
    ("\u0633\u0644\u0627\u0645 123 \u0661\u0662\u0663", AUTO, 0),
    ("abc", RTL, 0),
    ("abc \u05d0", RTL, 0),
    ("\u05d0\u05d1 xyz", LTR, 0),
    ("a\tb\t\u05d0", AUTO, TAB),
    ("x\u202eabc\u202cy", AUTO, 0),
    ("\u200b\u200fzero\u2066width\u2069", AUTO, 0),
    ("mixed \u4e2d\u6587 \u05e2\u05d1\u05e8\u05d9\u05ea \u0627\u0644\u0639\u0631\u0628\u064a\u0629 \U0001F600 e\u0301", AUTO, 0),
    ("\u0628\u064e\u064a\u0652\u062a", AUTO, 0),
    ("\u0645\u06cc\u200c\u062e\u0648\u0627\u0647\u0645", AUTO, 0),
    ("", AUTO, 0),
]


def test_forth_rows_match_the_terminal_layout_cell_for_cell() -> None:
    lines = list(_PRELUDE)
    for text, direction, flags in _ROWS:
        lines += _encode(text) + [f"{flags} {direction} _TT-LAYOUT"]
    output = program_output(SNAPSHOT.run(lines), lines)
    rows = _parse(output)
    assert len(rows) == len(_ROWS), output[-3000:]
    for (text, direction, flags), got in zip(_ROWS, rows):
        want = _expected(text, direction, keep_tab=bool(flags & TAB))
        assert got == want, text


def test_untrusted_rows_ignore_explicit_direction_controls() -> None:
    text = "x\u202eabc\u202cy"
    lines = list(_PRELUDE) + _encode(text) + [f"{UNTRUSTED} {AUTO} _TT-LAYOUT"]
    rows = _parse(program_output(SNAPSHOT.run(lines), lines))
    length, width, para, placed = rows[0]
    # The override would reverse "abc"; untrusted text keeps logical order.
    assert [chr(p[5][0]) for p in placed] == list("xabcy")
    assert width == 5


@pytest.mark.parametrize("text", [
    "ab\u05d0\u05d1\u4e2dc\U0001F1EF\U0001F1F5",
    "\u05d0\u05d1 cd \u05d2",
])
def test_positions_and_carets_follow_sections_9_1_and_9_2(text) -> None:
    layout = text_rules.layout_row(text)
    columns = range(-1, layout.width + 2)
    lines = list(_PRELUDE) + _encode(text) + [
        f"0 {AUTO} _TT-LAYOUT",
        '." POS:" ' + " ".join(f"{c} _TT-ROW TROW-POSITION-AT ." for c in columns) + " CR",
        '." CARET:" ' + " ".join(
            f"{o} _TT-ROW TROW-CARET ?DUP IF TROW.COLUMN . ELSE -1 . THEN"
            for o in range(layout.length + 1)
        ) + " CR",
    ]
    output = program_output(SNAPSHOT.run(lines), lines)
    positions = [int(v) for v in re.search(r"POS:([-\d ]*)", output)[1].split()]
    carets = [int(v) for v in re.search(r"CARET:([-\d ]*)", output)[1].split()]
    assert positions == [layout.position_at_column(c) for c in columns]
    assert carets == [
        (placed.column if (placed := layout.caret_character(o)) else -1)
        for o in range(layout.length + 1)
    ]


def test_byte_and_scalar_offsets_convert_both_ways() -> None:
    text = "a\u00e9\u4e2d\U0001F600z"
    data = text.encode("utf-8")
    starts = []
    position = 0
    for character in text:
        starts.append(position)
        position += len(character.encode("utf-8"))
    lines = list(_PRELUDE) + _encode(text) + [
        f"0 {AUTO} _TT-LAYOUT",
        '." TOB:" ' + " ".join(f"{i} _TT-ROW TROW-OFFSET>BYTE ." for i in range(len(text) + 1)) + " CR",
        '." TOO:" ' + " ".join(f"{b} _TT-ROW TROW-BYTE>OFFSET ." for b in range(len(data) + 1)) + " CR",
    ]
    output = program_output(SNAPSHOT.run(lines), lines)
    to_byte = [int(v) for v in re.search(r"TOB:([-\d ]*)", output)[1].split()]
    to_offset = [int(v) for v in re.search(r"TOO:([-\d ]*)", output)[1].split()]
    assert to_byte == starts + [len(data)]
    assert to_offset == [
        max(i for i, s in enumerate(starts) if s <= b) if b < len(data) else len(text)
        for b in range(len(data) + 1)
    ]


def _layout_steps(text: str, flags: int = 0, direction: int = AUTO, repeats: int = 5) -> float:
    setup = list(_PRELUDE) + _encode(text) + [
        f": _TT-A {repeats} 0 DO _TT-TEXT 2DROP LOOP ;",
        f": _TT-L {repeats} 0 DO _TT-TEXT {flags} {direction} _TT-ROW TROW-LAYOUT DROP LOOP ;",
        # Warm the row buffer so growth is not measured.
        f"_TT-TEXT {flags} {direction} _TT-ROW TROW-LAYOUT DROP",
    ]
    SNAPSHOT.run(setup + ["_TT-A"])
    baseline = SNAPSHOT.last_steps
    SNAPSHOT.run(setup + ["_TT-L"])
    return (SNAPSHOT.last_steps - baseline) / repeats / max(1, len(text))


def test_layout_cost_keeps_cheap_paths() -> None:
    """Ratchets on measured guest steps per scalar (APT-1-TEXT Section 11).

    Printable ASCII takes the byte path with no table lookups; other text
    pays for decoding, segmentation, and records, and right-to-left text
    also for bidi and joining.  Drawing and editors skip the layout
    altogether for ASCII rows.
    """

    ascii_cost = _layout_steps("plain ASCII text for a row " * 4)
    cjk_cost = _layout_steps("\u4e2d\u6587\u5b57" * 30)
    hebrew_cost = _layout_steps("\u05e9\u05dc\u05d5\u05dd " * 20)
    print(f"TROW-LAYOUT steps per scalar: ascii {ascii_cost:.0f}, "
          f"CJK {cjk_cost:.0f}, Hebrew {hebrew_cost:.0f}")
    assert ascii_cost < 1_500
    assert cjk_cost < 12_000
    assert hebrew_cost < 25_000
