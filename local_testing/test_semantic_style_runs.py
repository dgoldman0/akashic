#!/usr/bin/env python3
"""Style runs from the text area to STX1 (SEMANTIC-CONTENT-1).

A text area with a style source publishes each carried row's style runs in
its native TEXT_AREA entry.  The one deep validation proves them, and the
STX1 packer writes them after each item's text, where MegaPad's decoder
reads them back.  Runs count Unicode scalars, and a malformed run, or any
run on a TEXT_GRID, makes the entry invalid.
"""

from __future__ import annotations

import re

from test_widget_pointer import _run_forth  # also puts MegaPad on the path

from rich_terminal.semantic_content import (
    StyleRun,
    TextStyle,
    decode_semantic_text_content,
)

ROOTS = (
    "tui/widgets/textarea.f",
    "text/syntax.f",
    "tui/rich-terminal/uidl-semantic-content-stx1.f",
)

_SETUP = [
    "VARIABLE _W",
    "VARIABLE _U",
    "VARIABLE _S",
    "CREATE _BUF 512 ALLOT",
    "CREATE _B-S USCOL-BUILDER-SIZE 7 + ALLOT",
    "CREATE _O-S 4096 7 + ALLOT",
    "CREATE _K-S 256 7 + ALLOT",
    "CREATE _M-S USCOL-SUMMARY-SIZE 7 + ALLOT",
    "CREATE _X 4096 ALLOT",
    ": _B _B-S 7 + -8 AND ;",
    ": _O _O-S 7 + -8 AND ;",
    ": _K _K-S 7 + -8 AND ;",
    ": _M _M-S 7 + -8 AND ;",
    ": _N  ( n -- )  2 EMIT . 3 EMIT ;",
    ": _BYTES  ( a u -- )  18 EMIT 0 ?DO DUP I + C@ . LOOP DROP 19 EMIT ;",
    "40 6 SCR-NEW SCR-USE",
    "0 0 4 38 RGN-NEW _BUF 512 TXTA-NEW _W !",
    # Validate the entry built in _O, then pack it as STX1 revision 9.
    ": _VALIDATE  ( -- status )  _O _U @ _K 256 _M USCOL-ENTRY-VALIDATE ;",
    ": _PACK  ( -- )",
    "  _O _U @ _M 9 _X 4096 USSTX-PACK _N _X SWAP _BYTES ;",
    # Copy an item's text "abcdef" into the builder's destination, if any.
    ': _FILL-TEXT  ( dst|0 -- )  ?DUP IF S" abcdef" ROT SWAP MOVE THEN ;',
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
    groups = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    return groups, numbers


def test_a_styled_text_area_publishes_its_rows_runs_in_stx1() -> None:
    heading = "# Head"
    line = "see [é](x.md) **b**"
    groups, numbers = _run([
        "SYN-LANG-MD _W @ TXTA-STYLE!",
        *_bytes("_T", heading + "\n" + line),
        "_T$ _W @ TXTA-SET-TEXT",
        "0 _W @ TXTA-SCROLL-SET",
        # Measure, capture, validate, and pack.
        "7 _B _W @ TXTA-TEXT-AREA-MEASURE _N DUP _U ! _N",
        "7 _O _U @ _B _W @ TXTA-TEXT-AREA-CAPTURE _N _N",
        "_VALIDATE _N",
        "_M USCOL-SUMMARY-RUN-COUNT@ _N",
        "_M USCOL-SUMMARY-STX1-BYTES _N _N",
        "_PACK",
    ])
    assert numbers[0] == 0                      # measured
    assert numbers[2:4] == [0, numbers[1]]      # captured exactly that
    assert numbers[4] == 0                      # valid
    assert numbers[5] == 3                      # three runs
    status, stx1_bytes = numbers[6], numbers[7]
    assert status == 0
    assert numbers[8] == 0                      # packed
    (payload,) = groups
    assert len(payload) == stx1_bytes
    content = decode_semantic_text_content(payload)
    assert [item.text for item in content.items] == [heading, line]
    assert content.items[0].runs == (StyleRun(0, 6, TextStyle.HEADING),)
    # "[é](x.md)" starts at scalar 4 and is nine scalars, though ten bytes.
    assert content.items[1].runs == (
        StyleRun(4, 9, TextStyle.LINK),
        StyleRun(14, 5, TextStyle.STRONG),
    )
    assert content.style_run_count == 3


def test_without_a_style_source_rows_carry_no_runs() -> None:
    groups, numbers = _run([
        *_bytes("_T", "# Head"),
        "_T$ _W @ TXTA-SET-TEXT",
        "7 _B _W @ TXTA-TEXT-AREA-MEASURE _N _U !",
        "7 _O _U @ _B _W @ TXTA-TEXT-AREA-CAPTURE _N DROP",
        "_VALIDATE _N",
        "_PACK",
    ])
    assert numbers[:3] == [0, 0, 0]
    content = decode_semantic_text_content(groups[0])
    assert content.items[0].runs == ()


# A one-item TEXT_AREA of "abcdef", or a one-item TEXT_GRID, with RUNS added
# by the builder; the deep validation's status is printed.
def _entry(family: str, runs: list[tuple[int, int, int]]) -> list[str]:
    run_lines = [
        f"{start} {length} {meaning} _B USCOL-TEXT-ITEM-RUN _N"
        for start, length, meaning in runs
    ]
    return [
        "_O 4096 _B USCOL-BUILDER-INIT DROP",
        f"{family} 5 0 0 1 8 USCOL-STATE-VISIBLE USCOL-STATE-ENABLED OR _B USCOL-TEXT-BEGIN DROP",
        "0 1 8 0 0 1 8 _B USCOL-TEXT-SHAPE DROP",
        "0 0 0 0 _B USCOL-TEXT-POSITIONS DROP",
        f"1 0 0 1 8 USCOL-ROLE-CONTENT 0 6 _B USCOL-TEXT-ITEM-BEGIN DROP",
        "_FILL-TEXT",
        *run_lines,
        "_B USCOL-TEXT-ITEM-END DROP _B USCOL-TEXT-END DROP",
        "_B USCOL-BUILDER-FINISH DROP _U !",
        "_VALIDATE _N",
    ]


def test_the_deep_validation_proves_every_run() -> None:
    area, grid = "USCOL-F-TEXT-AREA", "USCOL-F-TEXT-GRID"
    cases = [
        (area, [(0, 2, 1), (2, 2, 9)], 0),       # touching, different meanings
        (area, [(0, 2, 1), (1, 2, 9)], 4),       # overlapping
        (area, [(2, 2, 1), (0, 1, 9)], 4),       # out of order
        (area, [(0, 2, 8), (2, 2, 8)], 4),       # touching with one meaning
        (area, [(4, 3, 9)], 4),                  # past the text's end
        (area, [(0, 0, 9)], 4),                  # empty
        (area, [(0, 1, 0)], 4),                  # plain is not a meaning
        (area, [(0, 1, 11)], 4),                 # nor is eleven
        (grid, [(0, 1, 4)], 4),                  # grids carry no runs
        (grid, [], 0),
    ]
    lines: list[str] = []
    for family, runs, _expected in cases:
        lines += _entry(family, runs)
    _groups, numbers = _run(lines)
    statuses = []
    cursor = 0
    for _family, runs, _expected in cases:
        cursor += len(runs)                     # each builder run printed OK
        statuses.append(numbers[cursor])
        cursor += 1
    assert statuses == [expected for _f, _r, expected in cases]
