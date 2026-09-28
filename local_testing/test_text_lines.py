#!/usr/bin/env python3
"""Text broken into lines: akashic/text/text-lines.f and TROW-LINE.

A wrapping card field is broken into lines by the client, for CELL, for
its scrolling, and for the rows its item view counts, and again by the
terminal, which draws the field in rich output.  APT-1-TEXT Section 12
is the only rule for that, so both must find the same lines and lay each
one out the same way.  These tests compare every line, and every visible
character on it, with MegaPad's independent implementation
(rich_terminal/text_rules.py).
"""

from __future__ import annotations

import random
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

SNAPSHOT = ForthSnapshot(("text/text-lines.f",))

AUTO, LTR, RTL = 0, 1, 2
UNTRUSTED = 2

_PRELUDE = [
    "CREATE _TL-BUF 8192 ALLOT  VARIABLE _TL-LEN",
    "CREATE _TL-CUR TLINES-SIZE ALLOT  _TL-CUR TLINES-INIT",
    "CREATE _TL-DISPLAY 1024 ALLOT",
    "VARIABLE _TL-P  VARIABLE _TL-ROW",
    ": _TL-CLEAR 0 _TL-LEN ! ;",
    ": _TL-B ( byte -- ) _TL-BUF _TL-LEN @ + C! 1 _TL-LEN +! ;",
    ": _TL-TEXT ( -- a u ) _TL-BUF _TL-LEN @ ;",
    # A line shown as its bytes: one one-cell character per scalar, at
    # level 0.
    "VARIABLE _TL-SA  VARIABLE _TL-SU  VARIABLE _TL-COL",
    ": _TL-SIMPLE-CHARS ( -- )",
    "  _TL-CUR TLINES-BYTES _TL-SU ! _TL-SA ! 0 _TL-COL !",
    "  BEGIN _TL-SU @ 0> WHILE",
    '    ." |" _TL-SA @ _TL-BUF - . 1 . 1 . 0 . _TL-COL @ .',
    "    _TL-SA @ _TL-SU @ UTF8-DECODE _TL-SU ! _TL-SA ! .",
    "    1 _TL-COL +!",
    "  REPEAT ;",
    # A line its row shows: each visible character, left to right.
    ": _TL-ROW-CHARS ( -- )",
    "  _TL-CUR TLINES-PARAGRAPH _TL-BUF - _TL-P !",
    "  _TL-CUR TLINES-ROW _TL-ROW !",
    "  _TL-ROW @ TROW-VISIBLE 0 ?DO",
    '    ." |" I _TL-ROW @ TROW-VCHAR',
    "    DUP TROW.BYTE _TL-P @ + . DUP TROW.SCALARS . DUP TROW.WIDTH .",
    "    DUP TROW.LEVEL . DUP TROW.COLUMN .",
    "    _TL-DISPLAY _TL-ROW @ TROW-DISPLAY 0 ?DO _TL-DISPLAY I 4 * + L@ . LOOP",
    "  LOOP ;",
    ": _TL-SHOW ( -- )",
    '  ." LINE:" _TL-CUR TLINES-BYTES SWAP _TL-BUF - . .',
    "  _TL-CUR TLINES-WIDTH . _TL-CUR TLINES-RTL? 1 AND .",
    '  _TL-CUR TLINES-ROW IF _TL-ROW-CHARS ELSE _TL-SIMPLE-CHARS THEN ." ;" ;',
    ": _TL-LINES ( flags direction limit -- )",
    "  >R >R >R _TL-TEXT R> R> R> _TL-CUR TLINES-START",
    "  BEGIN WHILE _TL-SHOW _TL-CUR TLINES-NEXT REPEAT",
    '  _TL-CUR TLINES-FAILED? IF ." FAILED" THEN ." END" CR ;',
    ": _TL-COUNT ( flags direction limit -- )",
    "  >R >R >R _TL-TEXT R> R> R> _TL-CUR TLINES-COUNT",
    '  ." COUNT:" 1 AND . . CR ;',
]

_DIRECTIONS = {
    AUTO: text_rules.DIRECTION_AUTO,
    LTR: text_rules.DIRECTION_LTR,
    RTL: text_rules.DIRECTION_RTL,
}


def _encode(text: str) -> list[str]:
    data = text.encode("utf-8")
    lines = ["_TL-CLEAR"]
    for start in range(0, len(data), 12):
        lines.append(" ".join(f"{byte} _TL-B" for byte in data[start:start + 12]))
    return lines


def _parse(output: str) -> list[list[tuple]]:
    texts = []
    for block in re.findall(r"((?:LINE:[^;]*;)*)(?:FAILED)?END", output):
        lines = []
        for match in re.finditer(r"LINE:([^;]*);", block):
            head, *chars = match[1].split("|")
            first, length, width, rtl = (int(v) for v in head.split())
            placed = []
            for char in chars:
                values = [int(v) for v in char.split()]
                start, scalars, cell_width, level, column, *display = values
                placed.append((start, scalars, cell_width, level, column, tuple(display)))
            lines.append((first, length, width, rtl, placed))
        texts.append(lines)
    return texts


def _expected(text: str, direction: int, limit: int) -> list[tuple]:
    """Each line of ``layout_lines`` in bytes: its first byte, the bytes up
    to the spaces at its end, its width, whether it is RTL, and its visible
    characters."""

    def byte_at(offset: int) -> int:
        return len(text[:offset].encode("utf-8"))

    result = []
    for line in text_rules.layout_lines(text, _DIRECTIONS[direction], limit):
        characters = text_rules.characters(text[line.start:line.end])
        last = line.end
        while characters and characters[-1] == " ":
            characters.pop()
            last -= 1
        placed = [
            (byte_at(p.start), p.scalars, p.width, p.level, p.column,
             tuple(ord(ch) for ch in p.text))
            for p in line.characters
        ]
        result.append(
            (byte_at(line.start), byte_at(last) - byte_at(line.start),
             line.width, int(line.rtl), placed)
        )
    return result


_CASES = [
    ("The quick brown fox jumps over the lazy dog", AUTO, 0, 10),
    ("supercalifragilistic expialidocious", AUTO, 0, 7),
    ("   a  b   c    ", AUTO, 0, 3),
    ("     ", AUTO, 0, 2),
    ("", AUTO, 0, 4),
    ("a\n\nb c d\n", AUTO, 0, 3),
    ("fits exactly", AUTO, 0, 12),
    ("x", AUTO, 0, 1),
    ("\u4f60\u597d\u4e16\u754c\u4f60\u597d\u4e16\u754c", AUTO, 0, 5),
    ("\u4f60 a", AUTO, 0, 1),
    ("\U0001F468\u200d\U0001F469\u200d\U0001F467 \U0001F44D\U0001F3FD "
     "\U0001F1EF\U0001F1F5\U0001F1FA\U0001F1F8 flags", AUTO, 0, 3),
    ("\u05e9\u05dc\u05d5\u05dd \u05e2\u05d5\u05dc\u05dd \u05d6\u05d4 "
     "\u05d8\u05e7\u05e1\u05d8 \u05d0\u05e8\u05d5\u05da", AUTO, 0, 8),
    ("abc \u05d0\u05d1\u05d2 def \u05d3\u05d4\u05d5 ghi", AUTO, 0, 7),
    ("\u0645\u0631\u062d\u0628\u0627\u0628\u0627\u0644\u0639\u0627\u0644\u0645",
     AUTO, 0, 4),
    ("\u05d0\u05d1\u05d2\u3000\u05d3\u05d4\u05d5\u3000\u05d6\u05d7\u05d8", AUTO, 0, 3),
    ("\u05d0\u05d1 \u3000 \u05d2\u05d3 \u3000", AUTO, 0, 4),
    ("x\u202eabc\u202cy z w", AUTO, UNTRUSTED, 3),
    ("x\u202eabc de\u202cy z", AUTO, 0, 4),
    ("hello world foo", RTL, 0, 6),
    ("\u05d0\u05d1 xyz \u05d2", LTR, 0, 4),
    ("123 456 789 \u05d0", RTL, 0, 4),
    ("\u05d0(\u05d1) [c] (d) \u05d2", AUTO, 0, 4),
    ("a \u0301b c", AUTO, 0, 1),
    ("\u0633\u0644\u0627\u0645 123 \u0661\u0662\u0663 \u0628\u0627\u0628", AUTO, 0, 5),
    ("mixed \u4e2d\u6587 \u05e2\u05d1\u05e8\u05d9\u05ea "
     "\u0627\u0644\u0639\u0631\u0628\u064a\u0629 \U0001F600 e\u0301", AUTO, 0, 6),
    ("line one\nline two is longer\n\n\u05d0\u05d1\u05d2 \u05d3\u05d4", AUTO, 0, 5),
    ("tab\there", AUTO, 0, 3),
    ("\u200b\u200fzero \u2066width\u2069 end", AUTO, 0, 5),
    ("the quick \u2014 brown fox \u2018jumps\u2019 over \u2026 the lazy dog", AUTO, 0, 9),
    ("caf\u00e9 \u03bb\u03bf\u03b3\u03b9\u03ba\u03ae \u2022 bullet \u00b7 dot", LTR, 0, 6),
    ("\u2014\u2014\u2014\u2014\u2014\u2014 \u2014\u2014", AUTO, 0, 3),
    ("x \u00e9\u00e9\u00e9  \u2014 y", RTL, 0, 3),
]


def _published(text: str, flags: int) -> str:
    """The text as the terminal receives it.  Untrusted text keeps its
    direction controls inert: an embedding or override is published as
    U+200B and an isolate as U+180E, which reorder nothing and segment and
    join as the controls do (list.f, _LST-INERT-BIDI)."""

    if flags & UNTRUSTED:
        text = re.sub("[\u202a-\u202e]", "\u200b", text)
        return re.sub("[\u2066-\u2069]", "\u180e", text)
    return text


def _run(cases: list[tuple]) -> tuple[list[list[tuple]], list[tuple[int, int]], str]:
    lines = list(_PRELUDE)
    for text, direction, flags, limit in cases:
        lines += _encode(text)
        lines.append(f"{flags} {direction} {limit} _TL-LINES")
        lines.append(f"{flags} {direction} {limit} _TL-COUNT")
    output = program_output(SNAPSHOT.run(lines), lines)
    counts = [
        (int(ok), int(n)) for ok, n in re.findall(r"COUNT:\s*(-?\d+)\s+(-?\d+)", output)
    ]
    return _parse(output), counts, output


def test_lines_match_the_terminal_line_for_line_and_cell_for_cell() -> None:
    texts, counts, output = _run(_CASES)
    assert len(texts) == len(_CASES), output[-3000:]
    for (text, direction, flags, limit), got, count in zip(_CASES, texts, counts):
        want = _expected(_published(text, flags), direction, limit)
        assert got == want, (text, limit)
        assert count == (1, len(want)), (text, limit)


def test_lines_match_the_terminal_on_random_text() -> None:
    alphabet = (
        list("abcdefghij") + [" "] * 6 + ["\n"]
        + ["\u4e2d", "\u6587", "\u3000"]
        + ["\u05d0", "\u05d1", "\u05d2", "(", ")", "1", "2"]
        + ["\u0628", "\u0627", "\u0644", "\u0661"]
        + ["\u2014", "\u00e9", "\u2019", "\u03bb"]
        + ["\u0301", "\U0001F600", "\u200d", "\u202e", "\u2067", "\u2069"]
    )
    generator_ = random.Random(20260928)
    cases = []
    for _ in range(60):
        text = "".join(generator_.choice(alphabet) for _ in range(generator_.randint(0, 40)))
        direction = generator_.choice((AUTO, AUTO, LTR, RTL))
        flags = generator_.choice((0, UNTRUSTED))
        cases.append((text, direction, flags, generator_.randint(1, 9)))
    texts, counts, output = _run(cases)
    assert len(texts) == len(cases), output[-3000:]
    for (text, direction, flags, limit), got, count in zip(cases, texts, counts):
        want = _expected(_published(text, flags), direction, limit)
        assert got == want, (text, direction, flags, limit)
        assert count == (1, len(want)), (text, limit)


def test_ascii_lines_match_the_terminal_on_random_text() -> None:
    """Printable ASCII breaks on its bytes without walking each line, so
    it gets its own random texts: words, runs of spaces, and line feeds."""

    generator_ = random.Random(9282026)
    cases = []
    for _ in range(80):
        text = "".join(
            generator_.choice(("a", "b", "c", "de", "fgh", " ", " ", "  ", "\n"))
            for _ in range(generator_.randint(0, 30))
        )
        cases.append((text, generator_.choice((AUTO, LTR)), 0, generator_.randint(1, 8)))
    texts, counts, output = _run(cases)
    assert len(texts) == len(cases), output[-3000:]
    for (text, direction, flags, limit), got, count in zip(cases, texts, counts):
        want = _expected(text, direction, limit)
        assert got == want, (text, limit)
        assert count == (1, len(want)), (text, limit)


def _line_steps(text: str, limit: int, repeats: int = 3) -> float:
    setup = list(_PRELUDE) + _encode(text) + [
        f": _TL-A {repeats} 0 DO _TL-TEXT 2DROP LOOP ;",
        f": _TL-C {repeats} 0 DO _TL-TEXT 0 0 {limit} _TL-CUR TLINES-COUNT 2DROP LOOP ;",
        f"_TL-TEXT 0 0 {limit} _TL-CUR TLINES-COUNT 2DROP",
    ]
    SNAPSHOT.run(setup + ["_TL-A"])
    baseline = SNAPSHOT.last_steps
    SNAPSHOT.run(setup + ["_TL-C"])
    return (SNAPSHOT.last_steps - baseline) / repeats / max(1, len(text))


def test_counting_lines_keeps_ascii_cheap() -> None:
    """A ratchet on guest steps per scalar: simple text (printable ASCII,
    and one-cell characters that never reorder) breaks on its scalars and
    needs no layout, which other text pays for."""

    ascii_cost = _line_steps("plain words for a wrapped card field " * 8, 30)
    simple_cost = _line_steps("plain words \u2014 for a \u2018wrapped\u2019 card " * 8, 30)
    hebrew_cost = _line_steps("\u05e9\u05dc\u05d5\u05dd \u05e2\u05d5\u05dc\u05dd " * 12, 30)
    print(f"TLINES-COUNT steps per scalar: ascii {ascii_cost:.0f}, "
          f"simple {simple_cost:.0f}, Hebrew {hebrew_cost:.0f}")
    assert ascii_cost < 600
    assert simple_cost < 2_000
    assert hebrew_cost < 26_000
