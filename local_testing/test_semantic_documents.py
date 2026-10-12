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
