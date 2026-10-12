#!/usr/bin/env python3
"""DOC1 documents (SEMANTIC-CONTENT-1) in Akashic's rich engines.

The neutral engine admits a DOCUMENT control only when its scalars agree
exactly with its DOC1 bytes: the blocks are its items, the containers its
fields, and the text bytes and style runs its other totals.  The bytes come
from MegaPad's own encoder.
"""

from __future__ import annotations

import re

from test_widget_pointer import _run_forth  # also puts MegaPad on the path

from rich_terminal.semantic_content import StyleRun, TextStyle
from rich_terminal.semantic_documents import (
    BlockContainer,
    BlockKind,
    ContainerKind,
    DocumentBlock,
    DocumentContent,
    DocumentFlag,
    encode_document_content,
)

ENGINE_ROOTS = ("tui/rich-terminal/engine.f",)


def _forth_bytes(name: str, data: bytes) -> list[str]:
    """Define NAME as DATA's bytes, a line of at most 32 at a time."""

    lines = [f"CREATE {name}"]
    for start in range(0, len(data), 32):
        lines.append(" ".join(f"{byte} C," for byte in data[start:start + 32]))
    return lines


def _sample() -> DocumentContent:
    quote = BlockContainer(ContainerKind.QUOTE, 2)
    item = BlockContainer(ContainerKind.NUMBERED_ITEM, 4, 3, True)
    return DocumentContent(
        7,
        DocumentFlag(0),
        (
            DocumentBlock(1, BlockKind.HEADING, "Notes", level=2),
            DocumentBlock(2, BlockKind.PARAGRAPH, "Read the notes first.", rows_before=1,
                          runs=(StyleRun(9, 5, TextStyle.LINK),)),
            DocumentBlock(3, BlockKind.PARAGRAPH, "quoted", rows_before=1,
                          containers=(quote, item)),
            DocumentBlock(4, BlockKind.RULE, rows_before=1),
        ),
    )


def test_the_neutral_engine_admits_only_exact_doc1_content() -> None:
    """A DOCUMENT control's scalars must agree with its DOC1 bytes."""

    content = _sample()
    data = encode_document_content(content)
    containers = sum(len(block.containers) for block in content.blocks)
    lines = [
        ": _N  ( n -- )  2 EMIT . 3 EMIT ;",
        *_forth_bytes("_X", data),
        "CREATE _C-S RTE-CONTROL-SIZE 7 + ALLOT",
        ": _C _C-S 7 + -8 AND ;",
        ": _CTL  _C RTE-CONTROL-SIZE 0 FILL",
        "  1 _C _RTE-CONTROL.OWNER ! 1 _C _RTE-CONTROL.GENERATION !",
        "  7 _C _RTE-CONTROL.ID ! RTE-CONTROL-DOCUMENT _C _RTE-CONTROL.KIND !",
        "  RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR _C _RTE-CONTROL.STATE !",
        "  3 _C _RTE-CONTROL.REGION !",
        "  12 _C _RTE-CONTROL.HEIGHT ! 30 _C _RTE-CONTROL.WIDTH !",
        "  24 _C _RTE-CONTROL.ROOT-HEIGHT ! 80 _C _RTE-CONTROL.ROOT-WIDTH !",
        f"  _X _C _RTE-CONTROL.CONTENT-A ! {len(data)} _C _RTE-CONTROL.CONTENT-U !",
        f"  {len(content.blocks)} _C _RTE-CONTROL.CONTENT-ITEMS !",
        f"  {content.utf8_bytes} _C _RTE-CONTROL.CONTENT-UTF8 !",
        f"  {content.style_run_count} _C _RTE-CONTROL.CONTENT-RUNS !",
        f"  {containers} _C _RTE-CONTROL.CONTENT-FIELDS ! ;",
        ": _OK?  _C RTE-CONTROL-VALID? _N ;",
        "_CTL _OK?",
        # Each total disagrees with the bytes.
        "_CTL 1 _C _RTE-CONTROL.CONTENT-FIELDS +! _OK?",
        "_CTL 1 _C _RTE-CONTROL.CONTENT-UTF8 +! _OK?",
        "_CTL 1 _C _RTE-CONTROL.CONTENT-RUNS +! _OK?",
        "_CTL 1 _C _RTE-CONTROL.CONTENT-ITEMS +! _OK?",
        # The header's tag, its block count, and a reserved field.
        "_CTL 0 _X C! _OK? 68 _X C!",
        "_CTL _X 20 + C@ 1+ _X 20 + C! _OK? _X 20 + C@ 1- _X 20 + C!",
        "_CTL 1 _X 28 + C! _OK? 0 _X 28 + C!",
        # Too short for the smallest body, and a label it may not carry.
        "_CTL 31 _C _RTE-CONTROL.CONTENT-U ! _OK?",
        "_CTL _X _C _RTE-CONTROL.LABEL-A ! 1 _C _RTE-CONTROL.LABEL-U ! _OK?",
        "_CTL _OK?",
    ]
    output = _run_forth(lines, roots=ENGINE_ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    verdicts = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    assert verdicts == [-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1]


# --------------------------------------------------------------------------
# The native DOCUMENT family and its DOC1 packer
# --------------------------------------------------------------------------

from rich_terminal.semantic_documents import decode_document_content  # noqa: E402

FAMILY_ROOTS = (
    "tui/semantic-collections.f",
    "tui/rich-terminal/uidl-semantic-documents-doc1.f",
)
_SETUP = [
    "VARIABLE _U",
    "CREATE _B-S USCOL-BUILDER-SIZE 7 + ALLOT",
    "CREATE _O-S 8192 7 + ALLOT",
    "CREATE _K-S 512 7 + ALLOT",
    "CREATE _M-S USCOL-SUMMARY-SIZE 7 + ALLOT",
    "CREATE _X 8192 ALLOT",
    ": _B _B-S 7 + -8 AND ;",
    ": _O _O-S 7 + -8 AND ;",
    ": _K _K-S 7 + -8 AND ;",
    ": _M _M-S 7 + -8 AND ;",
    ": _N  ( n -- )  2 EMIT . 3 EMIT ;",
    ": _BYTES  ( a u -- )  18 EMIT 0 ?DO DUP I + C@ . LOOP DROP 19 EMIT ;",
    ": _VALIDATE  ( -- status )  _O _U @ _K 512 _M USCOL-ENTRY-VALIDATE ;",
    ": _COPY  ( src u dst|0 -- )  ?DUP IF SWAP MOVE ELSE 2DROP THEN ;",
]


class _Program:
    """Forth lines that build one document; each builder status is printed."""

    def __init__(self) -> None:
        self.lines: list[str] = []
        self.statuses = 0

    def _bytes(self, data: bytes) -> str:
        name = f"_S{len(self.lines)}"
        self.lines += [
            f"CREATE {name} " + " ".join(f"{byte} C," for byte in data),
            f": {name}$  {name} {len(data)} ;",
        ]
        return name

    def call(self, text: str) -> None:
        self.lines.append(f"{text} _N")
        self.statuses += 1

    def begin(self, flags: int, viewport_row: int, *, key=5, capacity=8192) -> None:
        destination = "_O 8192" if capacity else "0 0"
        self.lines.append(f"{destination} _B USCOL-BUILDER-INIT DROP")
        self.call(f"{key} 0 0 12 30 3 _B USCOL-DOC-BEGIN")
        self.call(f"{flags} {viewport_row} _B USCOL-DOC-SHAPE")

    def block(self, key, kind, level, rows_before, inside, picture_rows, containers,
              text: bytes, runs) -> None:
        self.call(f"{key} {kind} {level} {rows_before} {inside} {picture_rows} "
                  "_B USCOL-DOC-BLOCK-BEGIN")
        for kind_, width, number, start in containers:
            self.call(f"{kind_} {width} {number} {-1 if start else 0} _B USCOL-DOC-CONTAINER")
        if text or runs:
            name = self._bytes(text)
            self.lines.append(f"{len(text)} _B USCOL-DOC-TEXT-BEGIN _N {name}$ ROT _COPY")
            self.statuses += 1
            for start, length, meaning in runs:
                self.call(f"{start} {length} {meaning} _B USCOL-DOC-TEXT-RUN")
        self.call("_B USCOL-DOC-BLOCK-END")

    def content(self, content: DocumentContent) -> None:
        for block in content.blocks:
            self.block(
                block.block_key, int(block.kind), block.level, block.rows_before,
                block.rows_before_inside, block.picture_rows,
                [(int(c.kind), c.width, c.number, c.item_start) for c in block.containers],
                block.text.encode("utf-8"),
                [(r.start, r.length, int(r.meaning)) for r in block.runs],
            )

    def end(self) -> None:
        self.call("_B USCOL-DOC-END")
        self.lines.append("_B USCOL-BUILDER-FINISH DROP _U !")


def _family_run(lines: list[str]):
    output = _run_forth(_SETUP + lines, roots=FAMILY_ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    groups = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    return groups, numbers


def _every_kind() -> DocumentContent:
    quote = BlockContainer(ContainerKind.QUOTE, 2)
    first = BlockContainer(ContainerKind.NUMBERED_ITEM, 4, 9, True)
    later = BlockContainer(ContainerKind.NUMBERED_ITEM, 4, 9, False)
    bullet = BlockContainer(ContainerKind.BULLET_ITEM, 2, 0, True)
    return DocumentContent(
        11,
        DocumentFlag.DIRECTION_RTL,
        (
            DocumentBlock(3, BlockKind.HEADING, "Notes", level=1),
            DocumentBlock(4, BlockKind.PARAGRAPH, "See the étude and code.", rows_before=1,
                          runs=(StyleRun(8, 5, TextStyle.LINK),
                                StyleRun(18, 4, TextStyle.CODE))),
            DocumentBlock(5, BlockKind.PARAGRAPH, "quoted\nitem", rows_before=1,
                          rows_before_inside=1, containers=(quote, first)),
            DocumentBlock(6, BlockKind.CODE, "a\n  b", rows_before=1, rows_before_inside=2,
                          containers=(quote, later)),
            DocumentBlock(7, BlockKind.RULE, rows_before=1),
            DocumentBlock(8, BlockKind.FIGURE, "A sunset", rows_before=1, picture_rows=6,
                          runs=(StyleRun(2, 6, TextStyle.EMPHASIS),)),
            DocumentBlock(9, BlockKind.FIGURE, "", picture_rows=1),
            DocumentBlock(10, BlockKind.PARAGRAPH, "", containers=(bullet,)),
            DocumentBlock(11, BlockKind.PAGE, "iv", rows_before=1),
        ),
        viewport_row=2,
    )


def test_a_document_builds_validates_and_packs_to_the_same_doc1_value() -> None:
    """Copy mode builds the entry the deep validation proves and the packer
    writes as the exact DOC1 MegaPad encodes; measure mode counts its bytes."""

    content = _every_kind()
    program = _Program()
    program.begin(int(content.flags), content.viewport_row)
    program.content(content)
    program.end()
    program.lines += [
        "_U @ _N",
        "_VALIDATE _N",
        "_M USCOL-SUMMARY-ITEM-COUNT@ _N",
        "_M USCOL-SUMMARY-FIELD-COUNT@ _N",
        "_M USCOL-SUMMARY-UTF8-BYTES@ _N",
        "_M USCOL-SUMMARY-RUN-COUNT@ _N",
        "_M USCOL-SUMMARY-DOC1-BYTES _N _N",
        "_O _U @ _M 11 _X 8192 USDOC-PACK _N _X SWAP _BYTES",
    ]
    groups, numbers = _family_run(program.lines)
    assert numbers[: program.statuses] == [0] * program.statuses, numbers
    entry_bytes, status, blocks, containers, utf8, runs, doc1_status, doc1_bytes, pack = (
        numbers[program.statuses:]
    )
    assert status == 0
    assert (blocks, containers, runs) == (9, 5, 3)
    assert utf8 == content.utf8_bytes
    assert (doc1_status, doc1_bytes, pack) == (0, content.wire_bytes, 0)
    (payload,) = groups
    assert payload == encode_document_content(content)
    assert decode_document_content(payload) == content

    measure = _Program()
    measure.begin(int(content.flags), content.viewport_row, capacity=0)
    measure.content(content)
    measure.call("_B USCOL-DOC-END")
    measure.lines.append("_B USCOL-BUILDER-FINISH _N _N")
    _groups, numbers = _family_run(measure.lines)
    assert numbers[: measure.statuses] == [0] * measure.statuses
    assert numbers[measure.statuses:] == [0, entry_bytes]


def _status(blocks, *, flags=0, viewport_row=0) -> int:
    """Build BLOCKS, each (key kind level before inside picture containers
    text runs), past the Python value's own checks, and return the deep
    validation's status."""

    program = _Program()
    program.begin(flags, viewport_row)
    for block in blocks:
        program.block(*block)
    program.end()
    program.lines.append("_VALIDATE _N")
    _groups, numbers = _family_run(program.lines)
    assert numbers[: program.statuses] == [0] * program.statuses
    return numbers[program.statuses]


P, H, C, R, F, PG = 1, 2, 3, 4, 5, 6
QUOTE, BULLET, NUMBERED = 1, 2, 3


def test_the_deep_validation_refuses_every_structural_rule() -> None:
    ok = [(1, P, 0, 0, 0, 0, [(QUOTE, 2, 0, False)], b"text", [(0, 4, 9)])]
    assert _status(ok) == 0
    assert _status([]) == 0
    cases = {
        "no key": [(0, P, 0, 0, 0, 0, [], b"x", [])],
        "a key twice": [(1, P, 0, 0, 0, 0, [], b"x", []), (1, P, 0, 0, 0, 0, [], b"y", [])],
        "no kind": [(1, 0, 0, 0, 0, 0, [], b"x", [])],
        "an unknown kind": [(1, 7, 0, 0, 0, 0, [], b"x", [])],
        "a page's start in a quote": [(1, PG, 0, 0, 0, 0, [(QUOTE, 2, 0, False)], b"4", [])],
        "a level on a page's start": [(1, PG, 1, 0, 0, 0, [], b"4", [])],
        "a heading without a level": [(1, H, 0, 0, 0, 0, [], b"x", [])],
        "a heading too deep": [(1, H, 7, 0, 0, 0, [], b"x", [])],
        "a level on a paragraph": [(1, P, 1, 0, 0, 0, [], b"x", [])],
        "a figure without picture rows": [(1, F, 0, 0, 0, 0, [], b"x", [])],
        "picture rows on a paragraph": [(1, P, 0, 0, 0, 2, [], b"x", [])],
        "a rule with text": [(1, R, 0, 0, 0, 0, [], b"x", [])],
        "a rule with a run": [(1, R, 0, 0, 0, 0, [], b"", [(0, 1, 9)])],
        "too many rows before": [(1, P, 0, 65536, 0, 0, [], b"x", [])],
        "rows before inside more containers": [(1, P, 0, 1, 1, 0, [], b"x", [])],
        "no container kind": [(1, P, 0, 0, 0, 0, [(0, 2, 0, False)], b"x", [])],
        "an unknown container kind": [(1, P, 0, 0, 0, 0, [(4, 2, 0, False)], b"x", [])],
        "a container of no width": [(1, P, 0, 0, 0, 0, [(QUOTE, 0, 0, False)], b"x", [])],
        "a container too wide": [(1, P, 0, 0, 0, 0, [(QUOTE, 65536, 0, False)], b"x", [])],
        "a quote that starts": [(1, P, 0, 0, 0, 0, [(QUOTE, 2, 0, True)], b"x", [])],
        "a bullet with a number": [(1, P, 0, 0, 0, 0, [(BULLET, 2, 3, True)], b"x", [])],
        "a tab": [(1, P, 0, 0, 0, 0, [], b"a\tb", [])],
        "DEL": [(1, P, 0, 0, 0, 0, [], b"a\x7fb", [])],
        "a byte that starts nothing": [(1, P, 0, 0, 0, 0, [], b"a\xffb", [])],
        "a run past the text": [(1, P, 0, 0, 0, 0, [], b"ab", [(1, 2, 9)])],
        "an unknown meaning": [(1, P, 0, 0, 0, 0, [], b"ab", [(0, 1, 11)])],
        "touching runs that mean the same": [
            (1, P, 0, 0, 0, 0, [], b"abcd", [(0, 2, 9), (2, 2, 9)])],
        "runs out of order": [(1, P, 0, 0, 0, 0, [], b"abcd", [(2, 1, 9), (0, 1, 8)])],
    }
    for name, blocks in cases.items():
        assert _status(blocks) == 4, name
    assert _status(ok, flags=3) == 4, "both directions"
    assert _status(ok, flags=4) == 4, "a reserved flag"
    assert _status([], viewport_row=1) == 4, "a viewport row with no blocks"
    assert _status([(1, C, 0, 0, 0, 0, [], b"a\nb", [])]) == 0, "line feeds"
    assert _status([(1, PG, 0, 1, 0, 0, [], b"iv", []), (2, PG, 0, 0, 0, 0, [], b"", [])]) == 0
