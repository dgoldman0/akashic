#!/usr/bin/env python3
"""Akashic pdf/layout.f: a page's runs of text as a document's blocks.

A page written by hand holds one of each thing the layout knows: a large
heading, paragraphs that wrap, one with its first line indented and one
after a short line, a word hyphenated across lines, bold, italic and code
words, bullet and numbered list items with a line that continues one,
lines of code, a bold line that heads what follows, and the page's
number.  Documents xelatex and LibreOffice write are laid out too, and
their headings, list items and code found.  Every byte is given back.
"""

from __future__ import annotations

import shutil
import subprocess
import zlib

import pytest

from forth_dependencies import dependency_order
from test_pdf_content import FILE_BYTES, page_pdf
from test_pdf_file import stream_object, write_pdf
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK = 0
PARAGRAPH, HEADING, CODE = 1, 2, 3
BULLET, NUMBERED = 2, 3
PLAIN, EMPHASIS, STRONG, TCODE = 0, 6, 7, 8

PRELUDE = f"""
{FILE_BYTES} XBUF LY-BYTES
CREATE LY-SRCS MEDSRC-SIZE 7 + ALLOT  : LY-SRC  LY-SRCS 7 + -8 AND ;
CREATE LY-MSRCS MSRC-SIZE 7 + ALLOT  : LY-MSRC  LY-MSRCS 7 + -8 AND ;
CREATE LY-FILES PDF-FILE-SIZE 7 + ALLOT  : LY-FILE  LY-FILES 7 + -8 AND ;
CREATE LY-PAGES PDF-PAGE-SIZE 7 + ALLOT  : LY-PAGE  LY-PAGES 7 + -8 AND ;
CREATE LY-CONTS PDF-CONTENT-SIZE 7 + ALLOT  : LY-CONT  LY-CONTS 7 + -8 AND ;
CREATE LY-SETS PDF-FONTS-SIZE 7 + ALLOT  : LY-SET  LY-SETS 7 + -8 AND ;
CREATE LY-OUTS PDF-LAYOUT-SIZE 7 + ALLOT  : LY-OUT  LY-OUTS 7 + -8 AND ;
: LY-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: LY-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: LY-OPEN  ( u -- status )
    LY-BYTES SWAP LY-SRC MEDSRC-MEMORY
    ['] LY-ALLOC ['] LY-FREE 0 0 LY-MSRC MSRC-INIT
    LY-PAGE PDF-PAGE-SIZE 0 FILL  LY-CONT PDF-CONTENT-SIZE 0 FILL
    LY-SET PDF-FONTS-SIZE 0 FILL  LY-OUT PDF-LAYOUT-SIZE 0 FILL
    LY-SRC LY-MSRC LY-FILE PDF-OPEN ;
: LY-CLOSE  ( -- held )
    LY-OUT PDF-LAYOUT-FREE  LY-CONT PDF-CONTENT-FREE  LY-PAGE PDF-PAGE-END
    LY-SET PDF-FONTS-FREE  LY-FILE PDF-CLOSE  LY-MSRC MSRC-HELD@ ;
: LY-COUNT  ( -- n status )  LY-FILE PDF-PAGE-COUNT ;
: LY-READ  ( i -- status )
    LY-OUT PDF-LAYOUT-FREE  LY-CONT PDF-CONTENT-FREE
    LY-FILE LY-PAGE PDF-PAGE-OPEN ?DUP IF EXIT THEN
    LY-PAGE LY-SET LY-CONT PDF-CONTENT-READ ?DUP IF LY-PAGE PDF-PAGE-CLOSE EXIT THEN
    LY-PAGE LY-CONT LY-OUT PDF-LAYOUT-READ  LY-PAGE PDF-PAGE-CLOSE ;
: LY-BLOCKS  ( -- n )  LY-OUT PDF-LAYOUT-BLOCKS ;
: LY-BLOCK  ( i -- kind level item number width top a u m )
    LY-OUT PDF-LAYOUT-BLOCK >R
    R@ PDF-BLOCK-KIND  R@ PDF-BLOCK-ITEM  R@ PDF-BLOCK-TOP
    R@ LY-OUT PDF-BLOCK-TEXT  R> LY-OUT PDF-BLOCK-MEANINGS ;
"""


class Layout:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=96 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/layout.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-layout",
                              step_budget=600_000_000)
        self.runtime.drain_uart_output()
        self.bytes = self.word("LY-BYTES")
        self.steps = 0

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0, stack.snapshot()
        for value in args:
            stack.push(value)
        self.steps = self.runtime.execute(name, step_budget=8_000_000_000).semantic_steps
        result = tuple(stack.snapshot())
        while stack.depth():
            stack.pop()
        return result

    def open(self, pdf: bytes) -> None:
        assert len(pdf) <= FILE_BYTES
        self.runtime.memory.write_bytes(self.bytes, pdf)
        assert self.call("LY-OPEN", len(pdf)) == (OK,)

    def close(self) -> None:
        assert self.call("LY-CLOSE") == (0,)

    def read(self, index: int = 0) -> int:
        return self.call("LY-READ", index)[0]

    def blocks(self) -> list[dict]:
        out = []
        for i in range(self.call("LY-BLOCKS")[0]):
            kind, level, item, number, width, top, a, u, m = self.call("LY-BLOCK", i)
            text = self.runtime.memory.read_bytes(a, u)
            meanings = self.runtime.memory.read_bytes(m, u)
            out.append({"kind": kind, "level": level, "item": item, "number": number,
                        "width": width, "top": top / 65536, "text": text.decode("utf-8"),
                        "meanings": meanings, "raw": text})
        return out


@pytest.fixture(scope="module")
def layout():
    return Layout()


COURIER = b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>"
OBLIQUE = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>"


def line(font: str, size: float, x: float, y: float, *parts: str) -> bytes:
    shown = b" ".join(b"(%s) Tj" % part.encode("cp1252") for part in parts)
    return b"BT /%s %g Tf %g %g Td %s ET\n" % (font.encode(), size, x, y, shown)


PAGE = b"".join([
    line("F2", 20, 72, 720, "A Title Here"),
    line("F1", 10, 72, 690, "This is a paragraph that wraps onto a second line, and it is long enough"),
    line("F1", 10, 72, 678, "to reach the right margin of the page before it ends."),
    line("F1", 10, 90, 666, "An indented first line starts the next paragraph, which also then"),
    line("F1", 10, 72, 654, "runs to the margin and then stops."),
    line("F1", 10, 72, 642, "A short line ends one."),
    line("F1", 10, 72, 630, "Words split by a hyph-"),
    b"BT /F1 10 Tf 72 618 Td (enated break join; ) Tj /F2 10 Tf (bold) Tj /F1 10 Tf ( and ) Tj "
    b"/F3 10 Tf (italic) Tj /F1 10 Tf ( and ) Tj /F4 10 Tf (code) Tj ET\n",
    line("F1", 10, 72, 594, "\u2022 First item"),
    line("F1", 10, 72, 582, "\u2022 Second item that is long enough to need a second line to hold"),
    line("F1", 10, 79.9, 570, "all of its words."),
    line("F1", 10, 72, 558, "1. Number one"),
    line("F1", 10, 72, 546, "2. Number two"),
    line("F4", 10, 72, 522, "x = 1"),
    line("F4", 10, 84, 510, "y = x + 2"),
    line("F2", 10, 72, 486, "A bold line"),
    line("F1", 10, 72, 474, "And the paragraph under it."),
    line("F1", 10, 300, 30, "7"),
])


def test_a_page_of_every_block(layout):
    resources = b"<< /Font << /F1 10 0 R /F2 11 0 R /F3 12 0 R /F4 13 0 R >> >>"
    pdf = page_pdf(PAGE, resources=resources, extra={11: b"<< /Type /Font /Subtype /Type1 "
                   b"/BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>", 12: OBLIQUE, 13: COURIER})
    layout.open(pdf)
    assert layout.read() == OK
    blocks = layout.blocks()
    got = [(b["kind"], b["level"], b["item"], b["number"], b["text"]) for b in blocks]
    assert got == [
        (HEADING, 1, 0, 0, "A Title Here"),
        (PARAGRAPH, 0, 0, 0, "This is a paragraph that wraps onto a second line, and it is long "
                             "enough to reach the right margin of the page before it ends."),
        (PARAGRAPH, 0, 0, 0, "An indented first line starts the next paragraph, which also then "
                             "runs to the margin and then stops."),
        (PARAGRAPH, 0, 0, 0, "A short line ends one."),
        (PARAGRAPH, 0, 0, 0, "Words split by a hyphenated break join; bold and italic and code"),
        (PARAGRAPH, 0, BULLET, 0, "First item"),
        (PARAGRAPH, 0, BULLET, 0, "Second item that is long enough to need a second line to hold "
                                  "all of its words."),
        (PARAGRAPH, 0, NUMBERED, 1, "Number one"),
        (PARAGRAPH, 0, NUMBERED, 2, "Number two"),
        (CODE, 0, 0, 0, "x = 1\n  y = x + 2"),
        (HEADING, 4, 0, 0, "A bold line"),
        (PARAGRAPH, 0, 0, 0, "And the paragraph under it."),
    ]
    styled = blocks[4]
    text, meanings = styled["raw"], styled["meanings"]
    for word, meaning in ((b"bold", STRONG), (b"italic", EMPHASIS), (b"code", TCODE), (b"join", PLAIN)):
        at = text.index(word)
        assert set(meanings[at:at + len(word)]) == {meaning}, word
    assert set(blocks[0]["meanings"]) == {PLAIN} and set(blocks[9]["meanings"]) == {PLAIN}
    assert blocks[5]["width"] == 2 and blocks[7]["width"] == 3
    assert abs(blocks[0]["top"] - 740) < 0.01
    layout.close()


TEX = r"""\documentclass{article}
\usepackage{fontspec}
\setmainfont{DejaVu Serif}
\setmonofont{DejaVu Sans Mono}
\begin{document}
\section{A section}
The first paragraph of the section, long enough that it wraps across two
or three lines of the page, so that its lines must be joined again into
one paragraph by the layout.

The second paragraph follows it, indented as LaTeX indents a paragraph,
and it too runs over several lines of text before it comes to an end.
\subsection{A subsection}
\begin{itemize}
\item The first item of a list.
\item The second item, which is long enough that it needs a second line
of the page to say what it has to say.
\end{itemize}
\begin{enumerate}
\item One.
\item Two.
\end{enumerate}
\begin{verbatim}
for x in range(3):
    print(x)
\end{verbatim}
After the code, a last paragraph.
\end{document}
"""


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_document_xelatex_wrote(layout, tmp_path):
    (tmp_path / "doc.tex").write_text(TEX)
    subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                   check=True, capture_output=True)
    layout.open((tmp_path / "doc.pdf").read_bytes())
    assert layout.read() == OK
    blocks = layout.blocks()
    kinds = [(b["kind"], b["level"], b["item"], b["number"]) for b in blocks]
    texts = [b["text"] for b in blocks]
    assert texts[0] == "1 A section" and kinds[0][:2] == (HEADING, 2)
    assert texts[1].startswith("The first paragraph") and texts[1].endswith("by the layout.")
    assert texts[2].startswith("The second paragraph") and texts[2].endswith("to an end.")
    assert texts[3] == "1.1 A subsection" and kinds[3][:2] == (HEADING, 3)
    assert (kinds[4][2], texts[4]) == (BULLET, "The first item of a list.")
    assert kinds[5][2] == BULLET and texts[5].endswith("what it has to say.")
    assert (kinds[6][2:], texts[6]) == ((NUMBERED, 1), "One.")
    assert (kinds[7][2:], texts[7]) == ((NUMBERED, 2), "Two.")
    assert (kinds[8][0], texts[8]) == (CODE, "for x in range(3):\n    print(x)")
    assert texts[9] == "After the code, a last paragraph."
    assert kinds[9][0] == PARAGRAPH and len(blocks) == 10
    layout.close()


@pytest.mark.skipif(shutil.which("soffice") is None, reason="LibreOffice is not installed")
def test_a_document_libreoffice_wrote(layout, tmp_path):
    (tmp_path / "doc.html").write_text(
        "<html><body><h1>A heading</h1><p>Paragraph one, with <b>bold</b> and <i>italic</i> words, "
        "long enough to wrap onto a second line of the page so that the layout joins its lines "
        "again.</p><h2>A smaller heading</h2><ul><li>first item</li><li>second item</li></ul>"
        "<ol><li>one</li><li>two</li></ol><pre>code line one\n  code line two</pre>"
        "<p>Last paragraph.</p></body></html>", encoding="utf-8")
    subprocess.run(["soffice", f"-env:UserInstallation=file://{tmp_path}/profile", "--headless",
                    "--convert-to", "pdf", "--outdir", str(tmp_path), str(tmp_path / "doc.html")],
                   check=True, capture_output=True, timeout=120)
    layout.open((tmp_path / "doc.pdf").read_bytes())
    assert layout.read() == OK
    blocks = layout.blocks()
    assert [(b["kind"], b["level"], b["item"], b["number"], b["text"]) for b in blocks] == [
        (HEADING, 1, 0, 0, "A heading"),
        (PARAGRAPH, 0, 0, 0, "Paragraph one, with bold and italic words, long enough to wrap onto "
                             "a second line of the page so that the layout joins its lines again."),
        (HEADING, 2, 0, 0, "A smaller heading"),
        (PARAGRAPH, 0, BULLET, 0, "first item"),
        (PARAGRAPH, 0, BULLET, 0, "second item"),
        (PARAGRAPH, 0, NUMBERED, 1, "one"),
        (PARAGRAPH, 0, NUMBERED, 2, "two"),
        (CODE, 0, 0, 0, "code line one\n  code line two"),
        (PARAGRAPH, 0, 0, 0, "Last paragraph."),
    ]
    text, meanings = blocks[1]["raw"], blocks[1]["meanings"]
    assert set(meanings[text.index(b"bold"):text.index(b"bold") + 4]) == {STRONG}
    assert set(meanings[text.index(b"italic"):text.index(b"italic") + 6]) == {EMPHASIS}
    layout.close()
