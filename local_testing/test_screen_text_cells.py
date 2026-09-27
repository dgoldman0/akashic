"""Wide and multi-scalar characters in the screen, drawing, and flush.

APT-1-TEXT puts one character in one cell, or in a lead and a continuation
cell when it is wide; a character of several scalars lives in its screen's
cluster pool.  These units run the real screen.f and draw.f sources on the
hosted runtime and compare drawn rows with MegaPad's independent layout
(rich_terminal/text_rules.py), then check pair repair, clipping, the pool's
collection, the backend's cluster words and degraded retry, and that the
ANSI backend's bytes rebuild the same grid in MegaPad's terminal.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import struct
import sys

import pytest

import generate_unicode_text_tables as generator

ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", ROOT.parent / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from simulator.runtime import MegaForthRuntime  # noqa: E402
from tests.simulator.test_kdos_exceptions import _load_exceptions  # noqa: E402
from rich_terminal import text_rules  # noqa: E402
from display import ATTR_CONTINUATION, ATTR_WIDE, VirtualTerminal  # noqa: E402

try:
    generator.ucd_file(generator.DEFAULT_UCD, "UnicodeData.txt")
except generator.UcdError as exc:  # pragma: no cover - depends on the host
    pytest.skip(f"pinned Unicode 15.1.0 data unavailable: {exc}", allow_module_level=True)

STEP_BUDGET = 400_000_000
MODULES = (
    "utils/uint-range.f", "utils/memory-span.f", "tui/cell.f", "tui/ansi.f",
    "text/utf8.f", "text/unicode-tables.f", "text/unicode-props.f",
    "text/grapheme.f", "text/bidi.f", "text/text-row.f", "text/cell-width.f",
    "utils/term.f", "tui/screen.f", "tui/draw.f",
)
WIDE = 128 << 48
CONT = 256 << 48
CLUSTER = 0x80000000

# A capturing backend: BEGIN arguments, then each span's position, count,
# and cluster words.  TL-ONCE makes the first BEGIN report TOO-LARGE.
BACKEND = r"""
CREATE TB-DESC SCB-DESC-SIZE 7 + ALLOT
: TB  TB-DESC 7 + -8 AND ;
CREATE TB-LOG 4096 ALLOT  VARIABLE TB-I  VARIABLE TB-TL-ONCE
CREATE TB-TEXT 4096 ALLOT
: TB-LOG!  ( x -- )  TB-LOG TB-I @ 8 * + !  1 TB-I +! ;
: TB-BEGIN  ( mode cols rows spans cells words peak ctx -- status )
    DROP
    TB-TL-ONCE @ IF 0 TB-TL-ONCE ! 2DROP 2DROP 2DROP DROP
        -7 TB-LOG! SCB-S-TOO-LARGE EXIT THEN
    -1 TB-LOG! >R >R >R >R >R >R TB-LOG!
    R> TB-LOG! R> TB-LOG! R> TB-LOG! R> TB-LOG! R> TB-LOG! R> TB-LOG!
    SCB-S-OK ;
: TB-SPAN  ( cells count row col words ctx -- status )
    DROP -2 TB-LOG! >R TB-LOG! TB-LOG! TB-LOG! DROP R> TB-LOG! SCB-S-OK ;
: TB-CURSOR  ( row col visible ctx -- status ) DROP 2DROP DROP SCB-S-OK ;
: TB-COMMIT  ( ctx -- status ) DROP SCB-S-OK ;
: TB-ABORT  ( ctx -- ) DROP ;
: TB-INIT  0 TB-I !  0 ['] TB-BEGIN ['] TB-SPAN ['] TB-CURSOR
    ['] TB-COMMIT ['] TB-ABORT TB SCB-INIT DROP ;
"""


class Screen:
    def __init__(self, cols: int, rows: int) -> None:
        self.runtime = _load_exceptions(MegaForthRuntime(execution_backend="native"))
        self.evaluate(": ALLOCATE (BANK0-ALLOCATE) ; : FREE (BANK0-FREE) ;")
        for relative in MODULES:
            source = (ROOT / "akashic" / relative).read_text()
            source = re.sub(r"(?m)^\s*(?:REQUIRE|PROVIDED)\s+[^\n]+", "", source)
            self.evaluate(source)
        self.evaluate(BACKEND)
        self.cols, self.rows = cols, rows
        self.screen = self.call("SCR-NEW", cols, rows)[0]
        self.call("SCR-USE", self.screen)

    def evaluate(self, source: str) -> None:
        self.runtime.evaluate(source.encode(), source_name="screen-text-test.f",
                              step_budget=STEP_BUDGET)
        assert self.runtime.main_context.data.snapshot() == ()

    def call(self, name: str, *inputs: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        for value in inputs:
            stack.push(value & ((1 << 64) - 1))
        self.runtime.execute(name, step_budget=STEP_BUDGET)
        result = stack.snapshot()
        while stack.depth():
            stack.pop()
        return result

    def put_text(self, text: str, row: int, col: int, word: str = "DRW-TEXT") -> None:
        data = text.encode()
        buffer = self.call("TB-TEXT")[0]
        self.runtime.memory.write_bytes(buffer, data)
        self.call(word, buffer, len(data), row, col)

    def back(self, row: int) -> list[int]:
        plane = self.runtime.memory.read64(self.screen + 24)
        base = plane + 8 * row * self.cols
        return [self.runtime.memory.read64(base + 8 * i) for i in range(self.cols)]

    def scalars(self, cell: int) -> tuple[int, ...]:
        cp = cell & 0xFFFFFFFF
        if not cp & CLUSTER:
            return (cp,)
        address, count = self.call("SCR-CLUSTER@", cell)
        raw = self.runtime.memory.read_bytes(address, 4 * count)
        return struct.unpack(f"<{count}I", raw)

    def row_text(self, row: int) -> list[tuple[str, int]]:
        """Each cell as (its character's text, WIDE/CONT bits)."""

        result = []
        for cell in self.back(row):
            pair = cell & (WIDE | CONT)
            text = "" if pair & CONT else "".join(map(chr, self.scalars(cell)))
            result.append((text, pair))
        return result

    def field(self, offset: int) -> int:
        return self.runtime.memory.read64(self.screen + offset)


@pytest.fixture
def screen():
    return Screen(24, 3)


def _expected_row(text: str, cols: int, col: int) -> list[tuple[str, int]]:
    row = [(" ", 0)] * cols
    for placed in text_rules.layout_row(text).characters:
        if placed.width == 0:
            continue
        at = col + placed.column
        if placed.width == 2:
            row[at] = (placed.text, WIDE)
            row[at + 1] = ("", CONT)
        else:
            row[at] = (placed.text, 0)
    return row


@pytest.mark.parametrize("text", [
    "plain ASCII",
    "a\u4e2d\u6587b e\u0301 \U0001F1EF\U0001F1F5",
    "\U0001F468\u200d\U0001F469\u200d\U0001F467 \u2764\ufe0f!",
    "abc \u05d0\u05d1\u05d2 12",
    "\u0645\u0631\u062d\u0628\u0627 (x)",
    "\u200bzero\u200d",
    "Files \u25b8 notes \u2026 \u2502 caf\u00e9",
    "a\tb\x7fc",
])
def test_drawn_rows_match_the_shared_layout(screen, text):
    screen.put_text(text, 1, 2)
    assert screen.row_text(1) == _expected_row(text, screen.cols, 2)


def test_writes_keep_wide_pairs_whole(screen):
    screen.put_text("\u4e2d\u6587", 0, 0)
    screen.call("SCR-SET", 7 << 32 | ord("x"), 0, 1)
    assert screen.row_text(0)[:4] == [(" ", 0), ("x", 0), ("\u6587", WIDE), ("", CONT)]
    screen.call("SCR-SET", 7 << 32 | ord("y"), 0, 2)
    assert screen.row_text(0)[:4] == [(" ", 0), ("x", 0), ("y", 0), (" ", 0)]
    # A wide scalar written raw gains its continuation; at the edge it
    # becomes a space.
    screen.call("SCR-SET", 7 << 32 | 0x4E2D, 2, 5)
    assert screen.row_text(2)[5:7] == [("\u4e2d", WIDE), ("", CONT)]
    screen.call("SCR-SET", 7 << 32 | 0x4E2D, 2, screen.cols - 1)
    assert screen.row_text(2)[-1] == (" ", 0)
    # A continuation restyles its lead: the pair keeps one style.
    screen.call("SCR-SET", (32 << 48 | 256 << 48) | 3 << 32, 2, 6)
    lead, cont = screen.back(2)[5:7]
    assert lead >> 48 == 32 | 128 and cont >> 48 == 32 | 256
    assert (lead >> 32) & 0xFF == (cont >> 32) & 0xFF == 3
    assert lead & 0xFFFFFFFF == 0x4E2D and cont & 0xFFFFFFFF == 0


def test_the_clip_cuts_a_wide_character_into_spaces(screen):
    screen.evaluate("-1 _DRW-CLIP-ON ! 0 _DRW-CLIP-ROW ! 2 _DRW-CLIP-COL ! "
                    "3 _DRW-CLIP-H ! 3 _DRW-CLIP-W !")
    screen.put_text("\u4e2d\u6587\u5b57", 0, 1)
    assert screen.row_text(0)[:7] == [
        (" ", 0), (" ", 0), (" ", 0), ("\u6587", WIDE), ("", CONT), (" ", 0), (" ", 0),
    ]


def test_backend_gets_cluster_words_and_a_degraded_retry(screen):
    screen.call("TB-INIT")
    screen.call("SCR-BACKEND!", screen.call("TB")[0])
    screen.put_text("e\u0301\U0001F1EF\U0001F1F5x", 0, 0)
    assert screen.call("SCR-FLUSH?") == (0,)
    log_at = screen.call("TB-LOG")[0]
    count = screen.runtime.memory.read64(screen.call("TB-I")[0])
    log = [screen.runtime.memory.read64(log_at + 8 * i) for i in range(count)]
    # A forced first flush is a snapshot: every row is one span.
    begin = log[:8]
    mode, cols, rows, spans, cells, words, peak = begin[1:8]
    assert (cols, rows, spans, cells) == (24, 3, 3, 72)
    # Each two-scalar cluster costs its extra count and its one extra.
    assert words == 2 + 2
    assert peak == 2 * 24 + 4
    first_span = log[8:13]
    assert first_span == [-2 & (2**64 - 1), 0, 0, 24, 4]

    # Drawing again and refusing the first BEGIN retries it degraded.
    screen.call("TB-INIT")
    screen.evaluate("-1 TB-TL-ONCE !")
    screen.put_text("a\u0302", 0, 0)
    assert screen.call("SCR-FLUSH?") == (0,)
    count = screen.runtime.memory.read64(screen.call("TB-I")[0])
    log = [screen.runtime.memory.read64(log_at + 8 * i) for i in range(count)]
    assert log[0] == -7 & (2**64 - 1)
    assert log[1] == -1 & (2**64 - 1)
    assert log[7] == 0  # cluster words
    assert all(entry == 0 for entry in log[13::5])  # every span: no words


def test_the_pool_frees_what_no_plane_holds(screen):
    screen.call("TB-INIT")
    screen.call("SCR-BACKEND!", screen.call("TB")[0])
    for round_ in range(200):
        mark = chr(0x300 + round_ % 100)
        screen.put_text(f"a{mark}b{chr(0x301 + round_ % 50)}", 0, 0)
        assert screen.call("SCR-FLUSH?") == (0,)
    live = screen.field(200)
    assert live < 200, live
    assert screen.row_text(0)[:2] == [(f"a{chr(0x300 + 199 % 100)}", 0),
                                      (f"b{chr(0x301 + 199 % 50)}", 0)]


def test_ansi_output_rebuilds_the_grid_in_megapads_terminal(screen):
    rows = [
        "a\u4e2d\u6587b e\u0301\u0302",
        "\U0001F468\u200d\U0001F469 \U0001F1EF\U0001F1F5 \u05d0\u05d1",
        "\u0645\u0631\u062d\u0628\u0627 \u2764\ufe0f.",
    ]
    for index, text in enumerate(rows):
        screen.put_text(text, index, 1)
    screen.runtime.drain_uart_output()
    assert screen.call("SCR-FLUSH?") == (0,)
    output = screen.runtime.drain_uart_output()
    terminal = VirtualTerminal(cols=screen.cols, rows=screen.rows)
    terminal.write(output)
    for index in range(screen.rows):
        got = [(cell[0], cell[3] & (ATTR_WIDE | ATTR_CONTINUATION))
               for cell in terminal.grid[index]]
        want = [(text, (ATTR_WIDE if pair & WIDE else 0)
                 | (ATTR_CONTINUATION if pair & CONT else 0))
                for text, pair in screen.row_text(index)]
        assert got == want, index
