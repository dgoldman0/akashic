#!/usr/bin/env python3
"""tui/widgets/document.f: a document view, row by row and cell by cell.

A block must take exactly the rows SEMANTIC-CONTENT-1 gives it, as MegaPad's
own rules count them (semantic_documents.block_row_count), with the text a
producer publishes: every document of the Markdown reference fixture, and
text in other scripts, at several widths.  CELL's cells are checked against
a model of MegaPad's reference renderer drawn on the cell grid, scrolling
against the clamp the view's rows imply, and links, figures and memory by
what the view does with them.  Every run checks a balanced stack.
"""

from __future__ import annotations

import re
import shutil
import subprocess

import pytest

import generate_markdown_reference as reference
import qoi_codec
from forth_dependencies import dependency_order
from test_media import _gradient
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from test_widget_pointer import _run_forth  # noqa: F401  (puts MegaPad on the path)
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

from rich_terminal.semantic_content import StyleRun, TextStyle
from rich_terminal.semantic_documents import (
    BlockContainer,
    BlockKind,
    ContainerKind,
    DocumentBlock,
    DocumentContent,
    DocumentFlag,
    block_row_count,
    decode_document_content,
    placed_blocks,
)

FILE_BYTES = 1 << 18
PICTURE_BYTES = 1 << 16
FG, BG = 252, 17                    # the owner's style the view draws over
TOP, LEFT = 1, 2                    # where the view starts on screen

# The looks: style-palette.f's, and the view's own.
MUTED, RULE_FG, CODE_BG = 245, 244, 235
BOLD, ITALIC, UNDERLINE = 1, 4, 8
PALETTE = {5: (215, BOLD), 6: (223, ITALIC), 7: (231, BOLD), 8: (114, 0),
           9: (75, UNDERLINE), 1: (81, BOLD), 2: (245, ITALIC), 3: (186, 0),
           4: (141, 0), 10: (203, UNDERLINE)}
BAR, LINE = 0x2502, 0x2500
BULLETS = (0x2022, 0x25E6, 0x25AA)
PARAGRAPH, HEADING, CODE, RULE, FIGURE, PAGE = 1, 2, 3, 4, 5, 6

SETUP = r"""
VARIABLE DV-RGN  VARIABLE DV-W  VARIABLE DV-DEPTH  VARIABLE DV-H
262144 XBUF DV-FILE
65536 XBUF DV-PIC  VARIABLE DV-PIC-U  0 DV-PIC-U !
CREATE DV-SRC-MEM MEDSRC-SIZE 7 + ALLOT
: DV-SRC  DV-SRC-MEM 7 + -8 AND ;
CREATE DV-MSRC-MEM MSRC-SIZE 7 + ALLOT
: DV-MSRC  DV-MSRC-MEM 7 + -8 AND ;
CREATE DV-DOC-MEM DOC-SIZE 7 + ALLOT
: DV-DOC  DV-DOC-MEM 7 + -8 AND ;
: DV-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: DV-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: DV-MSRC-INIT  ( budget -- )  >R ['] DV-ALLOC ['] DV-FREE 0 R> DV-MSRC MSRC-INIT ;
\ The owner: a picture named sunset.qoi is DV-PIC, and no other exists.
VARIABLE DV-RESOLVED  0 DV-RESOLVED !
VARIABLE DV-RELEASED  0 DV-RELEASED !
: DV-RESOLVE  ( name-a name-u ctx -- source|0 )
    DROP S" sunset.qoi" COMPARE IF 0 EXIT THEN
    MEDSRC-SIZE ALLOCATE IF DROP 0 EXIT THEN
    >R DV-PIC DV-PIC-U @ R@ MEDSRC-MEMORY 1 DV-RESOLVED +! R> ;
: DV-RELEASE  ( source ctx -- )
    DROP DUP MEDSRC-RELEASE FREE 1 DV-RELEASED +! ;
: DV-FOLLOW  ( target-a target-u ctx -- )  DROP ." FOLLOW=" TYPE CR ;
: DV-STYLE  ( -- )  FG-INDEX BG-INDEX 0 DRW-STYLE! DRW-STYLE-SAVE ;
: DV-DRAW  ( -- )  DV-STYLE DV-W @ WDG-DRAW ;
: DV-HEX-NIB  ( n -- )  DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;
: DV-HEX  ( a u -- )
    0 ?DO DUP I + C@ DUP 4 RSHIFT DV-HEX-NIB 15 AND DV-HEX-NIB LOOP DROP ;
\ Each block: kind level rows-before inside, its containers, and its text,
\ meanings and figure.
: DV-BLOCKS-DUMP  ( -- )
    DV-DOC DOC-COUNT 0 ?DO
        ." B " I DV-DOC DOC-BLOCK
        DUP BLK-KIND@ . DUP BLK-LEVEL@ . DUP BLK-ROWS-BEFORE@ . DUP BLK-INSIDE@ .
        DV-DOC DOC-CONTAINERS DUP . 0 ?DO
            DUP I CNT-SIZE * + DUP CNT-KIND@ . DUP CNT-WIDTH@ .
            DUP CNT-NUMBER@ . CNT-START? .
        LOOP DROP
        I DV-DOC DOC-CONTENT ." S=" DUP . IF DROP ELSE
            ." K=" DUP DCT-KIND@ . ." T=" DUP DCT-TEXT DV-HEX
            ." M=" DUP DCT-MAP OVER DCT-TEXT NIP DV-HEX
            ." F=" DCT-FIGURE DV-HEX
        THEN CR
    LOOP ;
\ Open the document at A as DV-DOC and show it in a new view.
: DV-OPEN  ( a u -- )
    DV-SRC MEDSRC-MEMORY
    DV-SRC MD-READER DV-MSRC DV-DOC DOC-OPEN ." OPEN=" . CR
    DV-RGN @ DV-MSRC DOCV-NEW DV-W !
    ['] DV-RESOLVE ['] DV-RELEASE ['] DV-FOLLOW 0 DV-W @ DOCV-OWNER!
    DV-DOC DV-W @ DOCV-DOCUMENT! ;
: DV-CLOSE  ( -- )
    DV-W @ DOCV-FREE DV-DOC DOC-CLOSE ." HELD=" DV-MSRC MSRC-HELD@ . CR ;
\ A reader of lines, for documents with pages: a line that starts with @
\ is a page's start, the rest its label; one that starts with ! is a
\ figure, the rest its picture's name; any other line is a paragraph; a
\ blank row lies between blocks.
CREATE PG-READER RDR-SIZE ALLOT
CREATE PG-C 1 ALLOT
CREATE PG-TEXT 256 ALLOT
VARIABLE PG-D  VARIABLE PG-START  VARIABLE PG-GAP
: PG-SRC  ( -- source )  PG-D @ DOC-SOURCE@ ;
: PG-BYTE  ( offset -- c )  PG-C 1 ROT PG-SRC MEDSRC-READ? DROP PG-C C@ ;
: PG-ADD  ( start end -- ok? )
    OVER - DUP 0= IF 2DROP -1 EXIT THEN
    OVER PG-BYTE DUP 64 = IF DROP 1 /STRING DOC-B-PAGE ELSE
        33 = IF 1 /STRING DOC-B-FIGURE ELSE DOC-B-PARAGRAPH THEN THEN
    -ROT 0 -ROT PG-D @ DOC-ADD-BLOCK
    DUP 0= IF EXIT THEN
    PG-GAP @ SWAP BLK-ROWS-BEFORE!  1 PG-GAP ! -1 ;
: PG-STRUCTURE  ( doc -- status )
    PG-D !  0 PG-START !  0 PG-GAP !
    PG-SRC MEDSRC-SIZE@ 0 ?DO
        I PG-BYTE 10 = IF
            PG-START @ I PG-ADD 0= IF DOC-S-MEMORY UNLOOP EXIT THEN
            I 1+ PG-START !
        THEN
    LOOP
    PG-START @ PG-SRC MEDSRC-SIZE@ PG-ADD 0= IF DOC-S-MEMORY EXIT THEN
    DOC-S-OK ;
: PG-CONTENT  ( index doc -- status )
    PG-D !  PG-D @ DOC-BLOCK DUP BLK-KIND@ >R BLK-LOC@
    255 MIN DUP >R  PG-TEXT SWAP ROT PG-SRC MEDSRC-READ? IF
        R> R> 2DROP DOC-S-READ EXIT
    THEN
    R> R> DOC-B-FIGURE = IF PG-TEXT SWAP PG-D @ DOC-CB-FIGURE
    ELSE PG-TEXT SWAP TSTY-PLAIN PG-D @ DOC-CB-TEXT THEN
    0= IF DOC-S-MEMORY EXIT THEN
    DOC-S-OK ;
: PG-CLOSE  ( doc -- )  DROP ;
' PG-STRUCTURE PG-READER RDR.STRUCTURE-XT !
' PG-CONTENT PG-READER RDR.CONTENT-XT !
' PG-CLOSE PG-READER RDR.CLOSE-XT !
0 PG-READER RDR.PART-XT !
0 PG-READER RDR.PICTURE-XT !
0 PG-READER RDR.ANCHOR-XT !
: DV-OPEN-WITH  ( a u reader -- )
    >R DV-SRC MEDSRC-MEMORY
    DV-SRC R> DV-MSRC DV-DOC DOC-OPEN ." OPEN=" . CR
    DV-RGN @ DV-MSRC DOCV-NEW DV-W !
    ['] DV-RESOLVE ['] DV-RELEASE ['] DV-FOLLOW 0 DV-W @ DOCV-OWNER!
    DV-DOC DV-W @ DOCV-DOCUMENT! ;
: DV-OPEN-PAGES  ( a u -- )  PG-READER DV-OPEN-WITH ;
\ The same lines in parts: each line that starts with @ starts a part.
\ PT-READS counts the parts read, and reading part PT-FAIL fails once its
\ blocks are added.
CREATE PT-READER RDR-SIZE ALLOT
VARIABLE PT-AT  VARIABLE PT-END  VARIABLE PT-N  VARIABLE PT-READS  VARIABLE PT-FAIL
0 PT-READS !  -1 PT-FAIL !
: PT-LINE-START?  ( offset -- flag )  DUP 0= IF DROP -1 EXIT THEN 1- PG-BYTE 10 = ;
: PT-STRUCTURE  ( doc -- status )
    PG-D !  -1 PT-AT !
    PG-SRC MEDSRC-SIZE@ 0 ?DO
        I PT-LINE-START? IF I PG-BYTE 64 = IF
            PT-AT @ 0< 0= IF
                PT-AT @ I PG-D @ DOC-ADD-PART 0= IF DOC-S-MEMORY UNLOOP EXIT THEN
            THEN
            I PT-AT !
        THEN THEN
    LOOP
    PT-AT @ 0< 0= IF
        PT-AT @ PG-SRC MEDSRC-SIZE@ PG-D @ DOC-ADD-PART 0= IF DOC-S-MEMORY EXIT THEN
    THEN DOC-S-OK ;
: PT-PART  ( part doc -- status )
    PG-D !  DUP PT-N !  0<> 1 AND PG-GAP !
    PT-N @ PG-D @ DOC-PART-LOC@ PT-END ! PG-START !
    PT-END @ PG-START @ ?DO
        I PG-BYTE 10 = IF
            PG-START @ I PG-ADD 0= IF DOC-S-MEMORY UNLOOP EXIT THEN
            I 1+ PG-START !
        THEN
    LOOP
    PG-START @ PT-END @ PG-ADD 0= IF DOC-S-MEMORY EXIT THEN
    1 PT-READS +!
    PT-N @ PT-FAIL @ = IF DOC-S-READ EXIT THEN
    DOC-S-OK ;
' PT-STRUCTURE PT-READER RDR.STRUCTURE-XT !
' PG-CONTENT PT-READER RDR.CONTENT-XT !
' PG-CLOSE PT-READER RDR.CLOSE-XT !
' PT-PART PT-READER RDR.PART-XT !
0 PT-READER RDR.PICTURE-XT !
0 PT-READER RDR.ANCHOR-XT !
: DV-OPEN-PARTS  ( a u -- )  PT-READER DV-OPEN-WITH ;
\ Draw, and serve the view until it needs nothing more.
: DV-SETTLE  ( -- )
    DV-DRAW BEGIN DV-W @ DOCV-PENDING? WHILE DV-W @ DOCV-SERVICE DROP DV-DRAW REPEAT ;
\ Which parts are read, and the block the view's top lies in: its part,
\ its place in the part, and its rows above the view.
: DV-READ.  ( -- )
    ." READ=" DV-DOC DOC-PARTS 0 ?DO I DV-DOC DOC-PART-READ? IF I . THEN LOOP
    ." N=" PT-READS @ . CR ;
: DV-AT  ( -- )
    DV-W @ DOCV-TOP@ SWAP DUP DV-DOC DOC-PART-OF
    ." AT=" DUP . DV-DOC DOC-PART-FIRST - . . ." REV=" DV-W @ DOCV-REVISION@ . CR ;
\ Every cell of the view.
: DV-CELLS  ( -- )
    ." @@CELLS" CR
    DV-RGN @ RGN-H 0 ?DO
        DV-RGN @ RGN-W 0 ?DO
            ." C " J . I . J TOP-ROW + I LEFT-COL + SCR-GET
            DUP CELL-CP@ . DUP CELL-FG@ . DUP CELL-BG@ . CELL-ATTRS@ . CR
        LOOP
    LOOP ;
: DV-TOP  ( -- )
    DV-W @ DOCV-TOP@ ." TOP=" SWAP . . ." REV=" DV-W @ DOCV-REVISION@ . CR ;
CREATE DV-EV-MEM 31 ALLOT
: DV-EV  DV-EV-MEM 7 + -8 AND ;
: DV-SEND  ( -- )  DV-EV DV-W @ WDG-HANDLE ." H=" . CR ;
: DV-KEY  ( code -- )  KEY-T-SPECIAL DV-EV !  DV-EV 8 + !  0 DV-EV 16 + ! DV-SEND ;
\ A pointer event at view cell (row, col).
: DV-MOUSE  ( code row col -- )
    LEFT-COL + SWAP TOP-ROW + 16 LSHIFT OR DV-EV 16 + !
    DV-EV 8 + !  KEY-T-MOUSE DV-EV ! DV-SEND ;
: DV-TEXT-FOLLOW  ( key offset -- )
    KEY-MOUSE-TEXT-OFFSET ! KEY-MOUSE-TEXT-KEY ! KEY-MOUSE-TEXT-FOLLOW 0 0 DV-MOUSE ;
: DV-SERVICE  ( -- )  BEGIN PICT-WORK? WHILE DV-W @ DOCV-SERVICE DROP REPEAT ;
: DV-PICT-SERVICE  ( widget -- )
    BEGIN DUP PICT-PENDING? WHILE PICT-STEP-PIXELS OVER PICT-SERVICE DROP REPEAT DROP ;
\ The cells of a ROWS by COLS rectangle DOWN rows below the view's top.
: DV-CELLS-BELOW  ( rows cols down -- )
    ." @@ALONE" CR
    ROT 0 ?DO
        OVER 0 ?DO
            ." C " J . I . DUP J + TOP-ROW + I LEFT-COL + SCR-GET
            DUP CELL-CP@ . DUP CELL-FG@ . DUP CELL-BG@ . CELL-ATTRS@ . CR
        LOOP
    LOOP 2DROP ;
"""


def _runtime(document: bytes = b"", picture: bytes = b"", roots: tuple[str, ...] = ()):
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20, hbw_size=1 << 20),
        execution_backend="native",
    )
    runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="document-view-userland")
    source = []
    for module in dependency_order(AK, ("tui/widgets/document.f", "markup/markdown.f",
                                        "tui/rich-terminal/uidl-semantic-documents-doc1.f",
                                        *roots)):
        source.extend(_load_forth_lines(AK / module))
    runtime.evaluate(("\n".join(source) + "\n").encode(),
                     source_name="document-view-closure", step_budget=800_000_000)
    constants = (
        f"{TOP} CONSTANT TOP-ROW  {LEFT} CONSTANT LEFT-COL  "
        f"{FG} CONSTANT FG-INDEX  {BG} CONSTANT BG-INDEX"
    )
    runtime.evaluate((constants + "\n" + SETUP).encode(), source_name="document-view-setup")
    runtime.drain_uart_output()
    assert len(document) <= FILE_BYTES and len(picture) <= PICTURE_BYTES
    for name, data in (("DV-FILE", document), ("DV-PIC", picture)):
        if data:
            runtime.execute(name)
            runtime.memory.write_bytes(runtime.main_context.data.pop(), data)
    if picture:
        runtime.evaluate(f"{len(picture)} DV-PIC-U !\n".encode(), source_name="picture")
    return runtime


def _run(lines: list[str], document: bytes = b"", picture: bytes = b"",
         max_steps: int = 2_000_000_000, roots: tuple[str, ...] = ()) -> str:
    runtime = _runtime(document, picture, roots)
    program = ["DEPTH DV-DEPTH !", "0 DV-MSRC-INIT", "80 30 SCR-NEW SCR-USE", *lines,
               'DEPTH DV-DEPTH @ - ." @D:" . CR']
    try:
        runtime.evaluate(("\n".join(program) + "\n").encode(),
                         source_name="document-view-proof", step_budget=max_steps)
    except Exception as error:
        raise AssertionError(
            f"{error}\n" + runtime.uart_output.decode(errors="replace")[-6000:]) from error
    output = runtime.drain_uart_output().decode("utf-8", errors="replace")
    assert "@D:0 " in output, output[-3000:]
    return output


def _view(rows: int, cols: int) -> str:
    return f"TOP-ROW LEFT-COL {rows} {cols} RGN-NEW DV-RGN !  {rows} DV-H !"


# --------------------------------------------------------------------------
# The blocks the view shows, as MegaPad's rules take them
# --------------------------------------------------------------------------

_BLOCK = re.compile(r"B ([-\d ]+?) S=(-?\d+)\s*(?:K=(\d+)\s+T=([0-9a-f]*)\s*M=([0-9a-f]*)\s*"
                    r"F=([0-9a-f]*))?\s*$")


class Shown:
    """One block as the guest's document holds it."""

    def __init__(self, line: str) -> None:
        match = _BLOCK.match(line.strip())
        assert match is not None and match.group(2) == "0", line
        head = [int(value) for value in match.group(1).split()]
        kind, self.level, self.rows_before, self.inside, count = head[:5]
        self.containers = [tuple(head[5 + 4 * i:9 + 4 * i]) for i in range(count)]
        self.kind = int(match.group(3))
        assert kind == self.kind or (kind, self.kind) == (PARAGRAPH, FIGURE), line
        self.text = bytes.fromhex(match.group(4))
        self.meanings = bytes.fromhex(match.group(5))
        self.figure = bytes.fromhex(match.group(6))


def _shown(output: str) -> list[Shown]:
    return [Shown(line) for line in output.splitlines() if line.startswith("B ")]


def _published(text: str) -> str:
    """The text a producer publishes: each explicit embedding, override or
    isolate an inert stand-in, as CELL's untrusted layout treats it."""

    return "".join(
        "​" if 0x202A <= ord(c) <= 0x202E else "᠎" if 0x2066 <= ord(c) <= 0x2069
        else c
        for c in text
    )


def _picture_rows(size, width: int, height: int) -> int:
    """A figure's picture rows: its size at no more than WIDTH cells, a
    cell two pixels high, at most HEIGHT rows; one when its size is unknown."""

    if size is None:
        return 1
    pw, ph = size
    cols = min(width, pw)
    return min(max(-(-ph * cols // (2 * pw)), 1), height)


def _document(shown: list[Shown], cols: int, height: int, pictures: dict, top: int = 0):
    """The DOC1 content a producer would send for the whole document, its
    first block TOP rows above the view."""

    blocks = []
    for index, block in enumerate(shown):
        containers = tuple(
            BlockContainer(ContainerKind(kind), width, number, bool(start))
            for kind, width, number, start in block.containers
        )
        indent = sum(container.width for container in containers)
        picture_rows = 0
        if block.kind == FIGURE:
            picture_rows = _picture_rows(pictures.get(block.figure), max(cols - indent, 1), height)
        blocks.append(DocumentBlock(
            index + 1, BlockKind(block.kind), _published(block.text.decode("utf-8")),
            level=block.level, rows_before=block.rows_before,
            rows_before_inside=block.inside, picture_rows=picture_rows,
            containers=containers,
        ))
    return DocumentContent(1, DocumentFlag(0), tuple(blocks), top)


# --------------------------------------------------------------------------
# Rows
# --------------------------------------------------------------------------

SCRIPTS = (
    "# مرحبا بالعالم\n\n"
    "שלום עולם 123 and English mixed in one paragraph that runs long enough to wrap.\n\n"
    "漢字とかなの文章は幅が二つのセルを取ります。漢字とかなの文章は幅が二つのセルを取ります。\n\n"
    "Emoji 👩‍👩‍👧‍👦 family, flags 🇯🇵🇫🇷 and combining é marks, then "
    "averyveryverylongwordthatnolinecanholdatall.\n\n"
    "> - العربية في قائمة داخل اقتباس طويل بما يكفي ليلتف عبر عدة أسطر\n"
    ">   متتالية\n\n"
    "Explicit ‮override‬ and ⁧isolate⁩ controls.\n\n"
    "```\n\ttab\tseparated\tcode with a very_long_identifier_that_does_not_fit\n  \n```\n\n"
    "![A *sunset* over the water, with a caption long enough to wrap](sunset.qoi)\n\n"
    "- ![inside an item](sunset.qoi)\n"
)

PICTURE = qoi_codec.encode(_gradient(40, 24))
PICTURES = {b"sunset.qoi": (40, 24)}


def test_rows_are_the_rows_megapad_counts() -> None:
    """Every block takes the rows MegaPad's rules give the text a producer
    publishes, at every width: prose and code lines, rules, figures and
    the blank rows between blocks."""

    sources, _ = reference.load()
    documents = [source.encode("utf-8") for source in sources] + [SCRIPTS.encode("utf-8")]
    widths = (7, 23, 64)
    height = 20
    data = b"".join(documents)
    lines = [
        _view(height, widths[0]),
        f"CREATE DV-WIDTHS {' , '.join(map(str, widths))} ,",
        ": DV-ROWS-OF  ( a u -- )",
        '    ." @@DOC" CR DV-OPEN DV-BLOCKS-DUMP',
        f"    {len(widths)} 0 DO",
        "        0 0 DV-H @ I CELLS DV-WIDTHS + @ DV-RGN @ RGN-BOUNDS!",
        '        ." W " I CELLS DV-WIDTHS + @ .',
        "        DV-DOC DOC-COUNT 0 ?DO I DV-W @ DOCV-ROWS . LOOP CR",
        "    LOOP",
        "    DV-CLOSE ;",
    ]
    offset = 0
    for document in documents:
        lines.append(f"DV-FILE {offset} + {len(document)} DV-ROWS-OF")
        offset += len(document)
    output = _run(lines, data, PICTURE, max_steps=20_000_000_000)
    parts = output.split("@@DOC")[1:]
    assert len(parts) == len(documents)
    for document, part in zip(documents, parts):
        assert "OPEN=0 " in part and "HELD=0 " in part, part[-2000:]
        shown = _shown(part)
        for width, values in re.findall(r"W (\d+)((?:\s+-?\d+)*)", part):
            content = _document(shown, int(width), height, PICTURES)
            expected = [block_row_count(content, block, int(width)) for block in content.blocks]
            assert [int(v) for v in values.split()] == expected, (document, width)


# --------------------------------------------------------------------------
# Cells
# --------------------------------------------------------------------------

def _cells(output: str, part: int = 0) -> dict[tuple[int, int], tuple[int, int, int, int]]:
    section = output.split("@@CELLS")[part + 1]
    return {
        (int(r), int(c)): (int(cp), int(fg), int(bg), int(attrs))
        for r, c, cp, fg, bg, attrs in re.findall(
            r"C (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)", section.split("@@")[0])
    }


def _model(shown: list[Shown], cols: int, height: int, top: int, pictures=None):
    """The view's cells, as the reference renderer draws a document on the
    cell grid: marks muted in their containers' cells, a rule's line, code
    on its background, and text in its meanings' looks over its block's."""

    grid = {(r, c): (32, FG, BG, 0) for r in range(height) for c in range(cols)}

    def put(row, col, cell):
        if 0 <= row < height and 0 <= col < cols:
            grid[(row, col)] = cell

    content = _document(shown, cols, height, pictures or {}, top)
    for item, block in zip(placed_blocks(content, cols), shown):
        if item.top >= height:
            break
        doc = item.block
        indent = doc.indent
        last = indent + max(cols - indent, 1)
        left, depth = 0, 0
        for index, container in enumerate(doc.containers):
            first, end = left, left + container.width
            left = end
            if container.kind is ContainerKind.QUOTE:
                begin = item.top if index < doc.rows_before_inside else item.content_top
                for row in range(begin, item.top + item.rows):
                    put(row, first, (BAR, MUTED, BG, 0))
                continue
            if not container.item_start:
                depth += container.kind is ContainerKind.BULLET_ITEM
                continue
            if container.kind is ContainerKind.BULLET_ITEM:
                put(item.content_top, first, (BULLETS[depth % 3], MUTED, BG, 0))
                depth += 1
            else:
                mark = f"{container.number}."
                for k, character in enumerate(mark):
                    col = end - 1 - len(mark) + k
                    if first <= col < end - 1:
                        put(item.content_top, col, (ord(character), MUTED, BG, 0))
        if doc.kind is BlockKind.RULE:
            for col in range(indent, last):
                put(item.content_top, col, (LINE, RULE_FG, BG, 0))
            continue
        base = (FG, 0)
        if doc.kind is BlockKind.HEADING:
            base = (215, BOLD | (UNDERLINE if doc.level <= 2 else 0))
        elif doc.kind is BlockKind.PAGE:
            base = (MUTED, 0)
        elif doc.kind is BlockKind.FIGURE:
            base = (MUTED, ITALIC)
            if block.figure not in (pictures or {}):
                for k, character in enumerate(block.figure.decode()):
                    if indent + k < last:
                        put(item.content_top, indent + k, (ord(character), MUTED, BG, 0))
        background = CODE_BG if doc.kind is BlockKind.CODE else BG
        starts = [i for i, byte in enumerate(block.text) if byte & 0xC0 != 0x80]
        for index, line in enumerate(item.lines):
            row = item.text_top + index
            if doc.kind is BlockKind.CODE:
                for col in range(indent, last):
                    put(row, col, (32, FG, CODE_BG, 0))
            start = last - line.width if line.rtl else indent
            for character in line.characters:
                col = start + character.column
                if col < indent or col + character.width > last:
                    continue
                meaning = block.meanings[starts[character.start]]
                fg, attrs = base
                if meaning in PALETTE:
                    fg, attrs = PALETTE[meaning][0], PALETTE[meaning][1] | base[1]
                put(row, col, (ord(character.text[0]), fg, background, attrs))
            if doc.kind is BlockKind.PAGE:
                # A page's break: a rule's line across the cells its line
                # leaves, one clear of the label, before it right to left.
                taken = line.width + (1 if line.width else 0)
                free = last - indent - taken
                if free > 0:
                    first = indent if line.rtl else indent + taken
                    for col in range(first, first + free):
                        put(row, col, (LINE, RULE_FG, BG, 0))
    return grid


SAMPLE = (
    "# Notes\n\n"
    "Some *emphasis*, **strong**, `code` and a [link](other.md) in a paragraph "
    "long enough to wrap across lines.\n\n"
    "> A quote with **strong** text.\n>\n"
    "> - an item in the quote\n>   - a deeper item\n>     - deeper still\n\n"
    "1. first\n2. second\n\n"
    "10. ten\n11. eleven\n\n"
    "```\ncode line one\n    indented code that is longer than the view is wide\n```\n\n"
    "---\n\n"
    "### Third level\n\n"
    "שלום עולם, זו פסקה מימין לשמאל עם *123* ו-English באמצע.\n\n"
    "![gone](missing.qoi)\n\n"
    "A [heading link](#notes) at the end.\n"
).encode()


def _offset(shown: list[Shown], cols: int, height: int, block: int, row: int) -> int:
    content = _document(shown, cols, height, {})
    return sum(block_row_count(content, b, cols) for b in content.blocks[:block]) + row


def test_cells_are_the_reference_look() -> None:
    """At the top, scrolled within blocks, and at the end, every cell is
    the reference renderer's look on the cell grid."""

    rows, cols = 14, 36
    lines = [_view(rows, cols), f"DV-FILE {len(SAMPLE)} DV-OPEN", "DV-BLOCKS-DUMP"]
    for scroll in (0, 5, 9, 1000):
        lines += [f"{scroll} DV-W @ DOCV-SCROLL", "DV-DRAW", "DV-TOP", "DV-CELLS"]
    lines.append("DV-CLOSE")
    output = _run(lines, SAMPLE)
    shown = _shown(output)
    tops = [tuple(map(int, t)) for t in re.findall(r"TOP=(\d+) (\d+)", output)]
    content = _document(shown, cols, rows, {})
    total = sum(block_row_count(content, block, cols) for block in content.blocks)
    expected_offsets = [0, 5, 14, total - rows]
    seen = set()
    for part, (top, expected) in enumerate(zip(tops, expected_offsets)):
        offset = _offset(shown, cols, rows, *top)
        assert offset == expected
        cells = _cells(output, part)
        assert len(cells) == rows * cols
        assert cells == _model(shown, cols, rows, offset), part
        seen |= {cell[0] for cell in cells.values()} | {cell[1:] for cell in cells.values()}
    # Every mark and look was drawn somewhere.
    assert {BAR, LINE, *BULLETS, ord("1"), ord("."), ord("ש")} <= seen
    assert {(215, BG, BOLD | UNDERLINE), (215, BG, BOLD), (75, BG, UNDERLINE),
            (223, BG, ITALIC), (231, BG, BOLD), (114, BG, 0), (FG, CODE_BG, 0),
            (MUTED, BG, ITALIC), (MUTED, BG, 0)} <= seen
    assert "HELD=0 " in output


# --------------------------------------------------------------------------
# Scrolling
# --------------------------------------------------------------------------

def _long_document() -> bytes:
    words = "alpha beta gamma delta epsilon zeta eta theta iota kappa".split()
    parts = []
    for n in range(30):
        parts.append(" ".join(words[: 3 + (n * 7) % 10] * (1 + n % 3)))
    return "\n\n".join(parts).encode() + b"\n"


def test_keys_and_the_wheel_scroll_by_rows_within_the_document() -> None:
    """Each key or wheel turn moves the view's top by its rows, never above
    the document's first row or so far that its last row rises above the
    view's bottom; Home and End go to either end, and a change in what the
    view shows takes a new revision."""

    document = _long_document()
    rows, cols = 8, 30
    actions = [("KEY-DOWN DV-KEY", 1), ("KEY-DOWN DV-KEY", 1), ("KEY-DOWN DV-KEY", 1),
               ("KEY-MOUSE-SCROLL-DN 2 2 DV-MOUSE", 3), ("KEY-PGDN DV-KEY", 7),
               ("KEY-PGDN DV-KEY", 7), ("KEY-END DV-KEY", "end"), ("KEY-DOWN DV-KEY", 1),
               ("KEY-UP DV-KEY", -1), ("KEY-MOUSE-SCROLL-UP 0 0 DV-MOUSE", -3),
               ("KEY-PGUP DV-KEY", -7), ("KEY-HOME DV-KEY", "home"), ("KEY-UP DV-KEY", -1),
               ("12 DV-W @ DOCV-GO", ("go", 12)), ("29 DV-W @ DOCV-GO", ("go", 29))]
    lines = [_view(rows, cols), f"DV-FILE {len(document)} DV-OPEN", "DV-BLOCKS-DUMP",
             "DV-DRAW", "DV-TOP"]
    for action, _ in actions:
        lines += [action, "DV-TOP"]
    lines.append("DV-CLOSE")
    output = _run(lines, document)
    shown = _shown(output)
    content = _document(shown, cols, rows, {})
    counts = [block_row_count(content, block, cols) for block in content.blocks]
    starts = [sum(counts[:i]) for i in range(len(counts))]
    last = max(sum(counts) - rows, 0)
    tops = [(int(b), int(r), int(v)) for b, r, v in re.findall(r"TOP=(\d+) (\d+) REV=(\d+)", output)]
    assert len(tops) == len(actions) + 1
    assert re.findall(r"H=(-?\d+)", output) == ["-1"] * len(actions[:13])
    offset = 0
    assert starts[tops[0][0]] + tops[0][1] == 0
    for (action, delta), before, after in zip(actions, tops, tops[1:]):
        if delta == "end":
            offset = last
        elif delta == "home":
            offset = 0
        elif isinstance(delta, tuple):
            offset = min(starts[delta[1]], last)
        else:
            offset = min(max(offset + delta, 0), last)
        assert starts[after[0]] + after[1] == offset, action
        assert after[1] < counts[after[0]]
        if (after[0], after[1]) != (before[0], before[1]):
            assert after[2] > before[2], action


# --------------------------------------------------------------------------
# Links
# --------------------------------------------------------------------------

def test_a_press_on_a_link_follows_it() -> None:
    """A press on a link's cell gives its target to the owner, a link to one
    of the document's headings scrolls there, and a press on anything else,
    or a rich position that is no link, does nothing."""

    rows, cols = 14, 36
    first = [_view(rows, cols), f"DV-FILE {len(SAMPLE)} DV-OPEN", "DV-BLOCKS-DUMP",
             "DV-DRAW", "DV-CELLS", "DV-CLOSE"]
    output = _run(first, SAMPLE)
    cells = _cells(output)
    link = min(key for key, cell in cells.items() if cell[1] == 75)
    plain = min(key for key, cell in cells.items() if cell[1] == FG and cell[0] != 32)
    shown = _shown(output)
    paragraph = next(i for i, b in enumerate(shown) if b.text.startswith(b"Some"))
    text = shown[paragraph].text.decode()
    link_offset = text.index("link in")
    heading_link = next(i for i, b in enumerate(shown) if b.text.startswith(b"A heading link"))
    lines = [
        _view(rows, cols), f"DV-FILE {len(SAMPLE)} DV-OPEN", "DV-DRAW",
        '." ~1" CR', f"KEY-MOUSE-LEFT {link[0]} {link[1]} DV-MOUSE",
        '." ~2" CR', f"KEY-MOUSE-LEFT {plain[0]} {plain[1]} DV-MOUSE",
        '." ~3" CR', f"{paragraph + 1} {link_offset} DV-TEXT-FOLLOW",
        '." ~4" CR', f"{paragraph + 1} 0 DV-TEXT-FOLLOW",
        "1000 DV-W @ DOCV-SCROLL DV-TOP",
        '." ~5" CR', f"{heading_link + 1} {len('A ')} DV-TEXT-FOLLOW", "DV-TOP",
        "DV-CLOSE",
    ]
    output = _run(lines, SAMPLE)
    steps = output.split("~")
    assert "FOLLOW=other.md" in steps[1]
    assert "FOLLOW=" not in steps[2]
    assert "FOLLOW=other.md" in steps[3]
    assert "FOLLOW=" not in steps[4] and "TOP=0 0 " not in steps[4]
    assert "FOLLOW=" not in steps[5] and "TOP=0 0 " in steps[5]


# --------------------------------------------------------------------------
# Figures
# --------------------------------------------------------------------------

FIGURES = (
    b"Before the picture.\n\n"
    b"![A sunset](sunset.qoi)\n\n"
    + b"".join(b"Paragraph %d after it.\n\n" % n for n in range(12))
)


def test_a_figure_shows_its_picture_and_the_part_in_view() -> None:
    """A figure's picture rows show the same cells a picture widget of that
    size shows; scrolled partly out, the rows still in view; and the
    picture's copy and source go back once the figure leaves the view."""

    rows, cols = 10, 30
    picture_rows = _picture_rows(PICTURES[b"sunset.qoi"], cols, rows)
    lines = [
        _view(rows, cols), f"DV-FILE {len(FIGURES)} DV-OPEN", "DV-BLOCKS-DUMP",
        "DV-DRAW DV-SERVICE DV-DRAW DV-CELLS",
        # The same picture alone, in a region of the figure's size.
        "VARIABLE DV-P  VARIABLE DV-PR  VARIABLE DV-PS",
        f"TOP-ROW 15 + LEFT-COL {picture_rows} {cols} RGN-NEW DV-PR !",
        "DV-PR @ DV-MSRC PICT-NEW DV-P !",
        "MEDSRC-SIZE ALLOCATE DROP DV-PS !  DV-PIC DV-PIC-U @ DV-PS @ MEDSRC-MEMORY",
        "DV-PS @ S\" sunset.qoi\" DV-P @ PICT-SOURCE!",
        "DV-STYLE DV-P @ WDG-DRAW DV-P @ DV-PICT-SERVICE DV-STYLE DV-P @ WDG-DRAW",
        f"{picture_rows} {cols} 15 DV-CELLS-BELOW",
        "DV-P @ PICT-FREE DV-PR @ RGN-FREE DV-PS @ FREE",
        # Scrolled so the picture's first three rows lie above the view.
        "5 DV-W @ DOCV-SCROLL DV-DRAW DV-TOP DV-CELLS",
        '." SHOWN=" DV-MSRC MSRC-HELD@ . CR',
        # Scrolled past it.
        "20 DV-W @ DOCV-SCROLL DV-DRAW DV-TOP",
        '." AWAY=" DV-MSRC MSRC-HELD@ . ." R=" DV-RESOLVED @ . DV-RELEASED @ . CR',
        "DV-CLOSE",
        '." END=" DV-RESOLVED @ . DV-RELEASED @ . CR',
    ]
    output = _run(lines, FIGURES, PICTURE)
    shown = _shown(output)
    assert shown[1].kind == FIGURE
    alone_section = output.split("@@ALONE")[1].split("@@")[0]
    alone = {
        (int(r), int(c)): (int(cp), int(fg), int(bg), int(attrs))
        for r, c, cp, fg, bg, attrs in re.findall(
            r"C (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)", alone_section)
    }
    assert any(cell[0] == 0x2580 for cell in alone.values())
    # At the top: the figure's rows lie under "Before the picture." and a
    # blank row; the rest is the model's.
    first = _cells(output, 0)
    picture_top = 2
    for (row, col), cell in alone.items():
        if picture_top + row < rows:
            assert first[(picture_top + row, col)] == cell
    model = _model(shown, cols, rows, 0, PICTURES)
    for key, cell in model.items():
        if not picture_top <= key[0] < picture_top + picture_rows:
            assert first[key] == cell, key
    # Scrolled: the picture's lower rows.
    top = tuple(map(int, re.findall(r"TOP=(\d+) (\d+)", output)[0]))
    offset = _offset(shown, cols, rows, *top)
    assert offset == 5
    scrolled = _cells(output, 1)
    for (row, col), cell in alone.items():
        if 0 <= picture_top + row - offset < rows:
            assert scrolled[(picture_top + row - offset, col)] == cell
    shown_held = int(re.search(r"SHOWN=(\d+)", output).group(1))
    away_held, resolved, released = map(int, re.search(
        r"AWAY=(\d+) R=(\d+) (\d+)", output).groups())
    assert away_held < shown_held
    assert resolved == released
    assert "HELD=0 " in output
    end = re.search(r"END=(\d+) (\d+)", output).groups()
    assert end[0] == end[1]


def test_the_view_keeps_its_figures_in_block_order() -> None:
    """The view keeps a record of each figure it meets, in block order
    whichever it meets first, keyed by its block's index plus one, with
    the picture widget showing it while it has a row in view."""

    paragraphs = b"".join(b"Paragraph %d.\n\n" % n for n in range(12))
    document = (b"![one](sunset.qoi)\n\n" + paragraphs
                + b"![two](sunset.qoi)\n\n" + paragraphs)
    lines = [
        _view(10, 30), f"DV-FILE {len(document)} DV-OPEN",
        ": DV-FIG. ( i -- ) DV-W @ DOCV-FIGURE@ SWAP .\" K=\" . .\" P=\" 0<> . ;",
        ": DV-FIGS. ( -- ) .\" N=\" DV-W @ DOCV-FIGURE-COUNT . 0 DV-FIG. 1 DV-FIG. CR ;",
        # The second figure first, then the first.
        "13 DV-W @ DOCV-GO DV-DRAW DV-FIGS.",
        "0 DV-W @ DOCV-GO DV-DRAW DV-FIGS.",
        '." PAST=" 2 DV-FIG. CR',
        # By key: the first figure's picture; none for the second, out of
        # view, a paragraph, or no block.
        '." BYKEY=" 0 DV-W @ DOCV-FIGURE@ NIP 1 DV-W @ DOCV-FIGURE-PICTURE = .',
        "14 DV-W @ DOCV-FIGURE-PICTURE . 2 DV-W @ DOCV-FIGURE-PICTURE .",
        "0 DV-W @ DOCV-FIGURE-PICTURE . CR",
        "DV-CLOSE",
    ]
    output = _run(lines, document, PICTURE)
    first, second = re.findall(r"N=(\d+) K=(\d+) P=(-?\d+) K=(\d+) P=(-?\d+)", output)
    assert first == ("1", "14", "-1", "0", "0"), output[-2000:]
    assert second == ("2", "1", "-1", "14", "0")
    assert "PAST=K=0 P=0 " in output
    assert "BYKEY=-1 0 0 0 " in output


def test_a_figure_without_its_picture_shows_its_name() -> None:
    rows, cols = 6, 24
    document = b"![gone](missing.qoi)\n\nAfter.\n"
    lines = [_view(rows, cols), f"DV-FILE {len(document)} DV-OPEN", "DV-BLOCKS-DUMP",
             "DV-DRAW DV-CELLS", "DV-CLOSE"]
    output = _run(lines, document)
    shown = _shown(output)
    assert _cells(output) == _model(shown, cols, rows, 0)
    assert "".join(chr(_cells(output)[(0, c)][0]) for c in range(11)) == "missing.qoi"


# --------------------------------------------------------------------------
# Memory
# --------------------------------------------------------------------------

def test_the_view_keeps_only_what_it_shows() -> None:
    """Drawn at the end of a long document, the view holds about what it
    held at the top: the contents of the blocks it shows, and every
    block's count; and all of it comes back."""

    many = b"".join(b"Paragraph %d with *emphasis* and `code`.\n\n" % n for n in range(1500))
    lines = [
        _view(12, 40), f"DV-FILE {len(many)} DV-OPEN",
        'DV-DRAW ." TOPHELD=" DV-MSRC MSRC-HELD@ . CR',
        'KEY-END DV-KEY DV-DRAW ." ENDHELD=" DV-MSRC MSRC-HELD@ . CR', "DV-TOP",
        "DV-CLOSE",
    ]
    output = _run(lines, many)
    top_held = int(re.search(r"TOPHELD=(\d+)", output).group(1))
    end_held = int(re.search(r"ENDHELD=(\d+)", output).group(1))
    assert abs(end_held - top_held) <= 1024
    assert "TOP=1495 " in output or "TOP=1494 " in output or "TOP=1496 " in output
    assert "HELD=0 " in output


def test_a_view_without_a_document_shows_nothing_and_takes_no_keys() -> None:
    lines = [_view(4, 10), "DV-RGN @ DV-MSRC DOCV-NEW DV-W !", "DV-DRAW", "DV-CELLS",
             "KEY-DOWN DV-KEY", "DV-W @ DOCV-FREE"]
    output = _run(lines)
    assert set(_cells(output).values()) == {(32, FG, BG, 0)}
    assert "H=0 " in output


# --------------------------------------------------------------------------
# The document a view publishes
# --------------------------------------------------------------------------

CAPTURE_SETUP = [
    "CREATE DV-B-S USCOL-BUILDER-SIZE 7 + ALLOT  : DV-B DV-B-S 7 + -8 AND ;",
    "CREATE DV-O-S 16384 7 + ALLOT  : DV-O DV-O-S 7 + -8 AND ;",
    "CREATE DV-K-S 4096 7 + ALLOT  : DV-K DV-K-S 7 + -8 AND ;",
    "CREATE DV-M-S USCOL-SUMMARY-SIZE 7 + ALLOT  : DV-M DV-M-S 7 + -8 AND ;",
    "CREATE DV-X 16384 ALLOT  VARIABLE DV-U",
    ": DV-BYTES  ( a u -- )  .\" @@BYTES \" DV-HEX CR ;",
    ": DV-CAPTURE  ( -- )",
    '    7 DV-B DV-W @ DOCV-DOCUMENT-MEASURE ." MEASURE=" . . CR',
    '    7 DV-O 16384 DV-B DV-W @ DOCV-DOCUMENT-CAPTURE ." CAPTURE=" . DUP DV-U ! ." BYTES=" . CR',
    '    DV-O DV-U @ DV-K 4096 DV-M USCOL-ENTRY-VALIDATE ." VALID=" . CR',
    '    DV-O DV-U @ DV-M 9 DV-X 16384 USDOC-PACK ." PACK=" DUP . CR',
    "    DROP DV-X SWAP DV-BYTES ;",
]


def _runs(text: bytes, meanings: bytes) -> tuple[StyleRun, ...]:
    """The style runs a meaning a byte gives: each scalar takes its first
    byte's meaning, and neighbours that share one form a run."""

    runs, start, current, scalar = [], 0, 0, 0
    for index, byte in enumerate(text):
        if byte & 0xC0 == 0x80:
            continue
        meaning = meanings[index] if 0 < meanings[index] < 11 else 0
        if meaning != current:
            if current:
                runs.append(StyleRun(start, scalar - start, TextStyle(current)))
            current, start = meaning, scalar
        scalar += 1
    if current:
        runs.append(StyleRun(start, scalar - start, TextStyle(current)))
    return tuple(runs)


def _publication(shown: list[Shown], cols: int, rows: int, top: int, pictures=None):
    """The DOC1 content a view showing SHOWN publishes at its top offset:
    the blocks it shows, keyed by index plus one, with their style runs."""

    content = _document(shown, cols, rows, pictures or {}, 0)
    placed = placed_blocks(content, cols)
    first = next(i for i, item in enumerate(placed) if item.top + item.rows > top)
    blocks = []
    for item, block in zip(placed[first:], shown[first:]):
        if item.top - top >= rows:
            break
        doc = item.block
        blocks.append(DocumentBlock(
            doc.block_key, doc.kind, doc.text, _runs(block.text, block.meanings),
            doc.level, doc.rows_before, doc.rows_before_inside, doc.picture_rows,
            doc.containers))
    return DocumentContent(9, DocumentFlag(0), tuple(blocks), top - placed[first].top)


def test_the_view_publishes_the_blocks_it_shows_as_doc1() -> None:
    """At the top and scrolled into a block, the view's DOCUMENT entry is the
    blocks it drew, from the one its top row lies in to the last that starts
    above its bottom, with the rows above the view; it validates, measure
    mode counts what capture copies, and its DOC1 is the model's."""

    rows, cols = 14, 36
    lines = [_view(rows, cols), *CAPTURE_SETUP, f"DV-FILE {len(SAMPLE)} DV-OPEN",
             "DV-BLOCKS-DUMP"]
    for scroll in (0, 5, 1000):
        lines += [f"{scroll} DV-W @ DOCV-SCROLL", "DV-DRAW", "DV-TOP", '." @@PART" CR',
                  "DV-CAPTURE"]
    lines.append("DV-CLOSE")
    output = _run(lines, SAMPLE)
    shown = _shown(output)
    parts = output.split("@@PART")[1:]
    tops = [tuple(map(int, t)) for t in re.findall(r"TOP=(\d+) (\d+)", output)]
    for part, top in zip(parts, tops):
        measured_status, measured = map(int, re.search(r"MEASURE=(-?\d+) (-?\d+)", part).groups())
        assert "CAPTURE=0 " in part and "VALID=0 " in part and "PACK=0 " in part, part
        payload = bytes.fromhex(re.search(r"@@BYTES ([0-9a-f]*)", part).group(1))
        offset = _offset(shown, cols, rows, *top)
        assert decode_document_content(payload) == _publication(shown, cols, rows, offset)
        assert measured_status == 0
        assert measured == int(re.search(r"BYTES=(-?\d+)", part).group(1))
    assert "HELD=0 " in output


PAGES = (
    "@iv\n"
    "A paragraph of prose that is long enough to wrap onto more lines.\n"
    "@\n"
    "@Appendix the second, a label long enough to wrap\n"
    "@\u05e2\u05de\u05d5\u05d3\n"
    "Last.\n"
).encode()


def test_pages_show_their_labels_and_their_breaks() -> None:
    """A page's start takes a paragraph's rows, as MegaPad counts them, and
    draws as the reference renderer does: its label muted, a rule's line
    across the cells each of its lines leaves, a whole row for an empty
    label, and the line before a right-to-left label; the view publishes
    it as a PAGE block."""

    rows, cols = 12, 24
    lines = [
        _view(rows, cols), *CAPTURE_SETUP, f"DV-FILE {len(PAGES)} DV-OPEN-PAGES",
        "DV-BLOCKS-DUMP",
        ': DV-ALL-ROWS  ." ROWS " DV-DOC DOC-COUNT 0 ?DO I DV-W @ DOCV-ROWS . LOOP CR ;',
        "DV-ALL-ROWS",
    ]
    for scroll in (0, 5):
        lines += [f"{scroll} DV-W @ DOCV-SCROLL", "DV-DRAW", "DV-TOP", "DV-CELLS",
                  '." @@PART" CR', "DV-CAPTURE"]
    lines.append("DV-CLOSE")
    output = _run(lines, PAGES)
    assert "OPEN=0 " in output and "HELD=0 " in output
    shown = _shown(output)
    assert [block.kind for block in shown] == [PAGE, PARAGRAPH, PAGE, PAGE, PAGE, PARAGRAPH]
    assert [block.text for block in shown][:3] == [b"iv", PAGES[4:69], b""]
    content = _document(shown, cols, rows, {})
    expected = [block_row_count(content, block, cols) for block in content.blocks]
    assert [int(v) for v in re.search(r"ROWS ([-\d ]+)", output).group(1).split()] == expected
    tops = [tuple(map(int, t)) for t in re.findall(r"TOP=(\d+) (\d+)", output)]
    seen = set()
    for part, top in enumerate(tops):
        offset = _offset(shown, cols, rows, *top)
        cells = _cells(output, part)
        assert cells == _model(shown, cols, rows, offset), part
        seen |= set(cells.values())
        payload = bytes.fromhex(re.search(r"@@BYTES ([0-9a-f]*)",
                                          output.split("@@PART")[part + 1]).group(1))
        published = decode_document_content(payload)
        assert published == _publication(shown, cols, rows, offset)
        assert BlockKind.PAGE in {block.kind for block in published.blocks}
    assert (LINE, RULE_FG, BG, 0) in seen and (ord("i"), MUTED, BG, 0) in seen
    assert (0x05E2, MUTED, BG, 0) in seen


# --------------------------------------------------------------------------
# Documents in parts
# --------------------------------------------------------------------------

PARTED = b"".join(
    b"@Page %d\n" % (n + 1)
    + b"".join(b"Part %d, paragraph %d: words enough to wrap twice here.\n" % (n, k)
               for k in range(3 + n % 3))
    for n in range(6)
)


class Line:
    """One block as the reader of lines gives it."""

    def __init__(self, text: bytes, rows_before: int) -> None:
        self.kind, self.text, self.figure = PARAGRAPH, text, b""
        if text.startswith(b"@"):
            self.kind, self.text = PAGE, text[1:]
        elif text.startswith(b"!"):
            self.kind, self.text, self.figure = FIGURE, b"", text[1:]
        self.level, self.inside, self.containers = 0, 0, []
        self.rows_before = rows_before
        self.meanings = bytes(len(self.text))


def _part_lines(source: bytes) -> list[list[tuple[int, bytes]]]:
    """Each part of a document of lines: its lines, with where each starts."""

    parts, offset = [], 0
    for line in source.split(b"\n"):
        if line.startswith(b"@"):
            parts.append([])
        if line and parts:
            parts[-1].append((offset, line))
        offset += len(line) + 1
    return parts


def _whole(source: bytes) -> tuple[list[Line], list[int]]:
    """The blocks of every part, as one document, and where each part starts."""

    blocks, firsts = [], []
    for part, lines in enumerate(_part_lines(source)):
        firsts.append(len(blocks))
        blocks += [Line(line, 0 if part == 0 and i == 0 else 1)
                   for i, (_, line) in enumerate(lines)]
    return blocks, firsts


def _arrangement(parts, reads):
    """The document after READS, each a part and whether its read succeeded:
    its blocks as (key, part, where its text starts), each part's first
    index, block count and state, and DOC-GAP's answers at each index."""

    keys, key, read = {}, 0, set()
    for part, ok in reads:
        for i in range(len(parts[part])):
            key += 1
            keys[(part, i)] = key
        if ok:
            read.add(part)
    blocks, records = [], []
    for part, lines in enumerate(parts):
        records.append((len(blocks), len(lines) if part in read else 0, -1 if part in read else 0))
        if part in read:
            blocks += [(keys[(part, i)], part, offset + (line[:1] in (b"@", b"!")))
                       for i, (offset, line) in enumerate(lines)]
    gaps = []
    for index in range(len(blocks) + 1):
        before = blocks[index - 1][1] if index else -1
        after = blocks[index][1] if index < len(blocks) else len(parts)
        between = [p for p in range(before + 1, after) if p not in read]
        gaps.append((between[0], between[-1]) if between else (-1, -1))
    return blocks, records, gaps


DUMP = r"""
: DM-DUMP  ( -- )
    ." @@DUMP" CR
    DV-DOC DOC-COUNT 0 ?DO
        ." K " I DV-DOC DOC-BLOCK DUP BLK-KEY@ . I DV-DOC DOC-PART-OF . BLK-LOC@ DROP . CR
    LOOP
    DV-DOC DOC-PARTS 0 ?DO
        ." P " I DV-DOC DOC-PART-FIRST . I DV-DOC DOC-PART-COUNT . I DV-DOC DOC-PART-READ? . CR
    LOOP
    DV-DOC DOC-COUNT 1+ 0 ?DO
        ." G " I 0 DV-DOC DOC-GAP . I -1 DV-DOC DOC-GAP . CR
    LOOP
    DV-DOC DOC-COUNT 0 ?DO
        ." X " I DV-DOC DOC-BLOCK BLK-KEY@ DV-DOC DOC-KEY>INDEX . CR
    LOOP ;
VARIABLE DM-C
"""


def test_parts_read_in_any_order_lie_where_they_belong() -> None:
    """A document in parts starts with no blocks; each part read, in any
    order, puts its blocks where the part lies, moving the blocks and
    contents after it on, while every block keeps the key it was given.
    A read that fails leaves the document as it was, a part read twice is
    read once, and a structure pass adds parts or blocks, not both."""

    parts = _part_lines(PARTED)
    reads = [(3, True), (1, True), (2, False), (4, True), (0, True), (2, True), (5, True)]
    lines = [
        f"DV-FILE {len(PARTED)} DV-SRC MEDSRC-MEMORY",
        'DV-SRC PT-READER DV-MSRC DV-DOC DOC-OPEN ." OPEN=" . CR',
        *DUMP.strip().splitlines(),
        'DV-DOC DOC-COUNT ." COUNT=" . DV-DOC DOC-PARTS ." PARTS=" . CR',
        'DOC-B-PARAGRAPH 0 0 0 DV-DOC DOC-ADD-BLOCK ." ADDBLOCK=" . CR',
        "DM-DUMP",
    ]
    for step, (part, ok) in enumerate(reads):
        if part == 1:
            # Keep part 3's first block's content, which part 1 moves on.
            lines.append("0 DV-DOC DOC-CONTENT DROP DM-C !")
        if not ok:
            lines.append(f"{part} PT-FAIL !")
        lines.append(f'{part} DV-DOC DOC-READ-PART ." READ=" . CR')
        if not ok:
            lines.append("-1 PT-FAIL !")
        if part == 1:
            lines += ['3 DV-DOC DOC-PART-FIRST DV-DOC DOC-KEPT DM-C @ = ." KEPT=" .',
                      '1 DV-DOC DOC-PART-FIRST DV-DOC DOC-KEPT ." NEW=" . CR',
                      '0 0 DV-DOC DOC-ADD-PART ." ADDPART=" . CR']
        lines.append("DM-DUMP")
    lines += [
        '3 DV-DOC DOC-READ-PART ." AGAIN=" . ." N=" PT-READS @ . CR',
        '6 DV-DOC DOC-READ-PART ." BEYOND=" . CR',
        'DV-DOC DOC-CLOSE ." HELD=" DV-MSRC MSRC-HELD@ . CR',
    ]
    output = _run(lines, PARTED)
    assert "OPEN=0 " in output and "COUNT=0 PARTS=6 " in output, output[-2000:]
    assert "ADDBLOCK=0 " in output and "ADDPART=0 " in output
    assert "KEPT=-1 NEW=0 " in output
    statuses = [int(v) for v in re.findall(r"READ=(-?\d+)", output)]
    assert statuses == [0 if ok else 2 for _, ok in reads]
    assert "AGAIN=0 N=7 " in output and "BEYOND=3 " in output and "HELD=0 " in output
    dumps = output.split("@@DUMP")[1:]
    assert len(dumps) == len(reads) + 1
    for count, dump in enumerate(dumps):
        blocks, records, gaps = _arrangement(parts, reads[:count])
        assert [tuple(map(int, m)) for m in re.findall(r"K (\d+) (-?\d+) (\d+)", dump)] == blocks
        assert [tuple(map(int, m)) for m in re.findall(r"P (\d+) (\d+) (-?\d+)", dump)] == records
        assert [tuple(map(int, m)) for m in re.findall(r"G (-?\d+) (-?\d+)", dump)] == gaps
        assert [int(m) for m in re.findall(r"X (-?\d+)", dump)] == list(range(len(blocks)))


def _settled(output: str, step: int) -> tuple[set[int], int, tuple[int, int, int, int]]:
    """Step STEP's parts read, the reads so far, and where the view's top lies."""

    read = re.findall(r"READ=([\d ]*)N=(\d+)", output)[step]
    at = tuple(map(int, re.findall(r"AT=(-?\d+) (\d+) (\d+) REV=(\d+)", output)[step]))
    return {int(v) for v in read[0].split()}, int(read[1]), at


def test_a_view_reads_parts_as_it_nears_them() -> None:
    """Scrolled through a document in parts, the view shows what it would
    show with every part read, and reads only the parts within a screen
    below its bottom and a screen above its top."""

    rows, cols = 8, 30
    whole, firsts = _whole(PARTED)
    content = _document(whole, cols, rows, {})
    counts = [block_row_count(content, block, cols) for block in content.blocks]
    starts = [sum(counts[:i]) for i in range(len(counts) + 1)]
    part_starts = [starts[first] for first in firsts] + [starts[-1]]
    last = starts[-1] - rows
    actions = [("KEY-PGDN DV-KEY", 7), ("KEY-PGDN DV-KEY", 7), ("KEY-DOWN DV-KEY", 1),
               ("KEY-MOUSE-SCROLL-DN 2 2 DV-MOUSE", 3), ("KEY-PGDN DV-KEY", 7),
               ("KEY-PGUP DV-KEY", -7), ("KEY-END DV-KEY", "end"),
               ("KEY-PGUP DV-KEY", -7), ("KEY-HOME DV-KEY", "home")]
    lines = [_view(rows, cols), f"DV-FILE {len(PARTED)} DV-OPEN-PARTS",
             "DV-SETTLE DV-READ. DV-AT DV-CELLS"]
    for action, _ in actions:
        lines.append(f"{action} DV-SETTLE DV-READ. DV-AT DV-CELLS")
    lines.append("DV-CLOSE")
    output = _run(lines, PARTED)
    assert "HELD=0 " in output
    offset = 0
    for step, (action, delta) in enumerate([("open", 0), *actions]):
        if delta == "end":
            offset = last
        elif delta == "home":
            offset = 0
        else:
            offset = min(max(offset + delta, 0), last)
        read, _, (part, place, row, _) = _settled(output, step)
        assert starts[firsts[part] + place] + row == offset, action
        assert _cells(output, step) == _model(whole, cols, rows, offset), action
        # No part it needs is left unread.
        for unread in set(range(6)) - read:
            assert part_starts[unread] - offset >= 2 * rows or \
                offset - part_starts[unread + 1] >= rows, (action, unread)
    assert _settled(output, 0)[0] == {0, 1}


def test_a_jump_reads_that_part_alone_and_the_view_stays_put() -> None:
    """Going to a far part reads it alone and shows it from its top; the
    view stops at the part not read above it until that part is read;
    the parts it then reads leave what it shows and publishes as they
    were, its blocks' keys included, and it goes on into them."""

    rows, cols = 8, 30
    whole, firsts = _whole(PARTED)
    content = _document(whole, cols, rows, {})
    counts = [block_row_count(content, block, cols) for block in content.blocks]
    starts = [sum(counts[:i]) for i in range(len(counts) + 1)]
    lines = [
        _view(rows, cols), *CAPTURE_SETUP, f"DV-FILE {len(PARTED)} DV-OPEN-PARTS",
        "3 DV-W @ DOCV-GO-PART DV-DRAW DV-READ. DV-AT DV-CELLS", '." @@PART" CR', "DV-CAPTURE",
        "KEY-UP DV-KEY DV-DRAW DV-READ. DV-AT",
        "DV-SETTLE DV-READ. DV-AT DV-CELLS", '." @@PART" CR', "DV-CAPTURE",
        "KEY-UP DV-KEY DV-SETTLE DV-READ. DV-AT DV-CELLS",
        "DV-CLOSE",
    ]
    output = _run(lines, PARTED)
    assert "HELD=0 " in output
    jumped, reads, at = _settled(output, 0)
    assert (jumped, reads, at[:3]) == ({3}, 1, (3, 0, 0))
    offset = starts[firsts[3]]
    assert _cells(output, 0) == _model(whole, cols, rows, offset)
    # Up: the part above is not read, so nothing moves.
    assert _settled(output, 1)[1:] == (1, at)
    # Settled: the parts within reach are read, and the view is as it was.
    settled, _, after = _settled(output, 2)
    assert settled == {2, 3, 4} and after[:3] == (3, 0, 0)
    assert _cells(output, 1) == _cells(output, 0)
    captures = re.findall(r"@@BYTES ([0-9a-f]*)", output)
    assert "CAPTURE=0 " in output and len(captures) == 2 and captures[0] == captures[1]
    published = decode_document_content(bytes.fromhex(captures[0]))
    assert [block.block_key for block in published.blocks] == \
        list(range(1, len(published.blocks) + 1))
    # Up again: into the part read above.
    _, _, (part, place, row, _) = _settled(output, 3)
    assert starts[firsts[part] + place] + row == offset - 1
    assert _cells(output, 2) == _model(whole, cols, rows, offset - 1)


def test_a_part_that_fails_to_read_is_tried_again_only_after_a_change() -> None:
    """A part whose read fails leaves the view stopped before it, and the
    view asks for it again only once what it shows has changed."""

    rows, cols = 8, 30
    whole, firsts = _whole(PARTED)
    content = _document(whole, cols, rows, {})
    counts = [block_row_count(content, block, cols) for block in content.blocks]
    lines = [
        _view(rows, cols), f"DV-FILE {len(PARTED)} DV-OPEN-PARTS", "1 PT-FAIL !",
        "DV-SETTLE DV-READ.", "DV-SETTLE DV-READ.",
        "KEY-DOWN DV-KEY DV-SETTLE DV-READ.",
        "1000 DV-W @ DOCV-SCROLL DV-SETTLE DV-READ. DV-AT",
        "-1 PT-FAIL ! KEY-UP DV-KEY DV-SETTLE DV-READ.",
        "DV-CLOSE",
    ]
    output = _run(lines, PARTED)
    assert "HELD=0 " in output
    states = re.findall(r"READ=([\d ]*)N=(\d+)", output)
    assert [(set(map(int, r.split())), int(n)) for r, n in states[:4]] == \
        [({0}, 2), ({0}, 2), ({0}, 3), ({0}, 4)]
    # Stopped before the part not read: part 0's last row at the bottom.
    part, place, row, _ = map(int, re.search(r"AT=(-?\d+) (\d+) (\d+) REV=(\d+)", output).groups())
    assert part == 0 and sum(counts[:place]) + row == sum(counts[:firsts[1]]) - rows
    assert {1} <= set(map(int, states[4][0].split()))


FIGURED = (
    b"@Page 1\n" + b"".join(b"First part, paragraph %d, long enough to wrap.\n" % k
                            for k in range(4))
    + b"@Page 2\n!sunset.qoi\nAfter the picture.\n"
    + b"@Page 3\nThe last part.\n"
)


def test_a_figure_keeps_its_record_when_a_part_is_read_before_it() -> None:
    """A part read before a figure's moves the figure on: the view keeps
    the one record for it, with its key and picture, and publishes it."""

    lines = [
        _view(10, 30), *CAPTURE_SETUP, f"DV-FILE {len(FIGURED)} DV-OPEN-PARTS",
        ": DV-FIGS. ( -- ) .\" N=\" DV-W @ DOCV-FIGURE-COUNT . 0 DV-W @ DOCV-FIGURE@"
        " SWAP .\" K=\" . .\" P=\" 0<> . CR ;",
        "1 DV-W @ DOCV-GO-PART DV-DRAW DV-FIGS. DV-READ.",
        "DV-SETTLE DV-FIGS. DV-READ. DV-AT",
        '." BYKEY=" 2 DV-W @ DOCV-FIGURE-PICTURE 0<> . CR',
        "DV-CAPTURE",
        "DV-CLOSE",
    ]
    output = _run(lines, FIGURED, PICTURE)
    assert "HELD=0 " in output
    figures = re.findall(r"N=(\d+) K=(\d+) P=(-?\d+)", output)
    assert figures == [("1", "2", "-1"), ("1", "2", "-1")], output[-3000:]
    read = re.findall(r"READ=([\d ]*)N=", output)
    assert set(map(int, read[0].split())) == {1}
    assert set(map(int, read[1].split())) == {0, 1, 2}
    assert re.search(r"AT=1 0 0 ", output)
    assert "BYKEY=-1 " in output
    assert "CAPTURE=0 " in output and "VALID=0 " in output


# --------------------------------------------------------------------------
# Pictures a document holds
# --------------------------------------------------------------------------

def _figured_pdf() -> tuple[bytes, list]:
    """A page with a Flate picture of samples and a stored JPEG, and the
    samples' pixels."""

    import zlib
    from test_pdf_content import HELVETICA
    from test_pdf_file import stream_object, write_pdf
    from test_pdf_image import jpeg, picture
    from test_pdf_layout import line
    rows = [[(r, g, b, 255) for r, g, b, _ in row] for row in _gradient(40, 24)]
    samples = bytes(c for row in rows for pixel in row for c in pixel[:3])
    stream = b"".join([
        line("F1", 10, 72, 720, "Before the pictures."),
        b"q 200 0 0 120 72 560 cm /Im1 Do Q\n",
        line("F1", 10, 72, 540, "Between them."),
        b"q 120 0 0 90 72 430 cm /Im2 Do Q\n",
        line("F1", 10, 72, 410, "After them."),
    ])
    pdf = write_pdf({
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
           b"/Resources << /Font << /F1 10 0 R >> /XObject << /Im1 30 0 R /Im2 31 0 R >> >> >>",
        4: stream_object(zlib.compress(stream), b"/Filter /FlateDecode"),
        10: HELVETICA,
        30: picture(zlib.compress(samples), b"/Width 40 /Height 24 /ColorSpace /DeviceRGB "
                    b"/BitsPerComponent 8 /Filter /FlateDecode"),
        31: picture(jpeg(40, 30), b"/Width 40 /Height 30 /ColorSpace /DeviceRGB "
                    b"/BitsPerComponent 8 /Filter /DCTDecode"),
    })
    return pdf, rows


def test_a_pdf_figure_shows_the_picture_its_file_is_made_into() -> None:
    """A PDF holds its figures' pictures: the view takes each one's size
    from its maker, makes its file from the service while it is shown,
    and then shows it as any figure's picture: the samples as a QOI file
    in the same cells a picture widget shows for that QOI, and the JPEG as
    a JPEG file of its size.  Everything comes back."""

    pdf, rows = _figured_pdf()
    expected = qoi_codec.encode(rows)
    height, cols = 30, 40
    picture_rows = _picture_rows((40, 24), cols, height)
    lines = [
        _view(height, cols), f"DV-FILE {len(pdf)} PDF-DOC-READER DV-OPEN-WITH",
        ": DV-FIG.  ( i -- )  DV-W @ DOCV-FIGURE@ SWAP .\" K=\" . ?DUP IF PICT-FILE@ "
        "ROT .\" F=\" . SWAP . . ELSE .\" NONE \" THEN ;",
        "DV-DRAW DV-W @ DOCV-SERVICE DROP DV-DRAW",
        '." MAKING=" DV-W @ DOCV-PENDING? . 0 DV-FIG. CR',
        'DV-SETTLE ." MADE=" DV-W @ DOCV-FIGURE-COUNT . 0 DV-FIG. 1 DV-FIG. CR',
        "DV-CELLS",
        "VARIABLE DV-P  VARIABLE DV-PR  VARIABLE DV-PS",
        f"TOP-ROW LEFT-COL {picture_rows} {cols} RGN-NEW DV-PR !",
        "DV-PR @ DV-MSRC PICT-NEW DV-P !",
        "MEDSRC-SIZE ALLOCATE DROP DV-PS !  DV-PIC DV-PIC-U @ DV-PS @ MEDSRC-MEMORY",
        "DV-PS @ S\" alone\" DV-P @ PICT-SOURCE!",
        "DV-STYLE DV-P @ WDG-DRAW DV-P @ DV-PICT-SERVICE DV-STYLE DV-P @ WDG-DRAW",
        f"{picture_rows} {cols} 0 DV-CELLS-BELOW",
        "DV-P @ PICT-FREE DV-PR @ RGN-FREE DV-PS @ FREE",
        "DV-CLOSE",
    ]
    output = _run(lines, pdf, expected, roots=("pdf/document.f",))
    assert "OPEN=0 " in output and "HELD=0 " in output, output[-3000:]
    # Before the service, the first figure's file is still being made.
    assert re.search(r"MAKING=-1 K=3 NONE", output), output[:300]
    # Made: the samples as a QOI file of their size, the JPEG as itself.
    assert "MADE=2 K=3 F=2 40 24 K=5 F=4 40 30 " in output, output[:300]
    alone_section = output.split("@@ALONE")[1].split("@@")[0]
    alone = {(int(r), int(c)): (int(cp), int(fg), int(bg), int(attrs))
             for r, c, cp, fg, bg, attrs in re.findall(
                 r"C (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)", alone_section)}
    assert any(cell[0] == 0x2580 for cell in alone.values())
    cells = _cells(output)
    picture_top = 4          # the page's start, a blank row, a line, a blank row
    for (row, col), cell in alone.items():
        assert cells[(picture_top + row, col)] == cell, (row, col)


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_press_on_a_pdf_link_goes_to_its_page_or_the_owner(tmp_path) -> None:
    """A press on a reference in a PDF reads the page it names, if need
    be, and shows it from its top; a press on an address gives it to the
    owner's follow word."""

    filler = "\n\n".join(["This paragraph is here to fill the page with words, so that "
                           "each page is longer than the view is high."] * 6)
    tex = (r"\documentclass{article}\usepackage{hyperref}\begin{document}"
           r"\section{Introduction}\label{sec:intro}"
           r"See section~\ref{sec:details} and \href{https://example.com/paper}{the paper}."
           "\n\n" + filler + r"\newpage\section{Details}\label{sec:details}" + filler
           + r"\newpage\section{End}" + filler + r"\end{document}")
    (tmp_path / "doc.tex").write_text(tex, encoding="utf-8")
    for _ in range(2):
        subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                       capture_output=True, check=True)
    pdf = (tmp_path / "doc.pdf").read_bytes()
    rows, cols = 24, 60
    first = [_view(rows, cols), f"DV-FILE {len(pdf)} PDF-DOC-READER DV-OPEN-WITH",
             "DV-SETTLE DV-CELLS", "DV-CLOSE"]
    cells = _cells(_run(first, pdf, roots=("pdf/document.f",)))
    texts = ["".join(chr(cells[(r, c)][0]) for c in range(cols)) for r in range(rows)]
    row = next(r for r, text in enumerate(texts) if text.startswith("See section 2"))
    reference = (row, texts[row].index("2"))
    address = (row, texts[row].index("the paper"))
    assert cells[reference][1] == cells[address][1] == 75      # the link's look
    lines = [_view(rows, cols), f"DV-FILE {len(pdf)} PDF-DOC-READER DV-OPEN-WITH",
             "DV-SETTLE", '." ~1" CR', f"KEY-MOUSE-LEFT {address[0]} {address[1]} DV-MOUSE",
             '." ~2" CR', f"KEY-MOUSE-LEFT {reference[0]} {reference[1]} DV-MOUSE",
             "DV-DRAW DV-AT", "DV-CLOSE"]
    output = _run(lines, pdf, roots=("pdf/document.f",))
    steps = output.split("~")
    assert "FOLLOW=https://example.com/paper" in steps[1]
    assert "FOLLOW=" not in steps[2] and re.search(r"AT=1 0 0 ", steps[2]), steps[2][-800:]
    assert "HELD=0 " in output
