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
PARAGRAPH, HEADING, CODE, FIGURE = 1, 2, 3, 5
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
CREATE LY-STRS PDF-STRUCT-SIZE 7 + ALLOT  : LY-STR  LY-STRS 7 + -8 AND ;
: LY-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: LY-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: LY-OPEN  ( u -- status )
    LY-BYTES SWAP LY-SRC MEDSRC-MEMORY
    ['] LY-ALLOC ['] LY-FREE 0 0 LY-MSRC MSRC-INIT
    LY-PAGE PDF-PAGE-SIZE 0 FILL  LY-CONT PDF-CONTENT-SIZE 0 FILL
    LY-SET PDF-FONTS-SIZE 0 FILL  LY-OUT PDF-LAYOUT-SIZE 0 FILL  LY-STR PDF-STRUCT-SIZE 0 FILL
    LY-SRC LY-MSRC LY-FILE PDF-OPEN ;
: LY-CLOSE  ( -- held )
    LY-OUT PDF-LAYOUT-FREE  LY-CONT PDF-CONTENT-FREE  LY-STR PDF-STRUCT-FREE
    LY-PAGE PDF-PAGE-END  LY-SET PDF-FONTS-FREE  LY-FILE PDF-CLOSE  LY-MSRC MSRC-HELD@ ;
: LY-COUNT  ( -- n status )  LY-FILE PDF-PAGE-COUNT ;
: LY-READ  ( i -- status )
    LY-OUT PDF-LAYOUT-FREE  LY-CONT PDF-CONTENT-FREE  LY-STR PDF-STRUCT-FREE
    LY-FILE LY-PAGE PDF-PAGE-OPEN ?DUP IF EXIT THEN
    LY-PAGE LY-SET LY-CONT PDF-CONTENT-READ ?DUP IF LY-PAGE PDF-PAGE-CLOSE EXIT THEN
    LY-PAGE LY-STR PDF-STRUCT-READ ?DUP IF LY-PAGE PDF-PAGE-CLOSE EXIT THEN
    LY-PAGE LY-CONT LY-STR 0 LY-OUT PDF-LAYOUT-READ  LY-PAGE PDF-PAGE-CLOSE ;
: LY-BLOCKS  ( -- n )  LY-OUT PDF-LAYOUT-BLOCKS ;
: LY-BLOCK  ( i -- kind level item number width top a u m )
    LY-OUT PDF-LAYOUT-BLOCK >R
    R@ PDF-BLOCK-KIND  R@ PDF-BLOCK-ITEM  R@ PDF-BLOCK-TOP
    R@ LY-OUT PDF-BLOCK-TEXT  R> LY-OUT PDF-BLOCK-MEANINGS ;
: LY-FIGURE  ( i -- num w h )  LY-OUT PDF-LAYOUT-BLOCK PDF-BLOCK-FIGURE ;
: LY-PLACE  ( i -- top low x0 x1 size )
    LY-OUT PDF-LAYOUT-BLOCK DUP PDF-BLOCK-TOP OVER PDF-BLOCK-LOW 2 PICK PDF-BLOCK-ACROSS
    4 ROLL PDF-BLOCK-SIZE ;
CREATE LY-LNKS PDF-LINKS-SIZE 7 + ALLOT  : LY-LNK  LY-LNKS 7 + -8 AND ;
LY-LNK PDF-LINKS-SIZE 0 FILL
\\ Lay page I out with its links.
: LY-READ-LINKED  ( i -- status )
    LY-OUT PDF-LAYOUT-FREE  LY-CONT PDF-CONTENT-FREE  LY-STR PDF-STRUCT-FREE  LY-LNK PDF-LINKS-FREE
    LY-FILE LY-PAGE PDF-PAGE-OPEN ?DUP IF EXIT THEN
    LY-PAGE LY-SET LY-CONT PDF-CONTENT-READ ?DUP IF LY-PAGE PDF-PAGE-CLOSE EXIT THEN
    LY-PAGE LY-STR PDF-STRUCT-READ ?DUP IF LY-PAGE PDF-PAGE-CLOSE EXIT THEN
    LY-PAGE LY-LNK PDF-LINKS-READ ?DUP IF LY-PAGE PDF-PAGE-CLOSE EXIT THEN
    LY-PAGE LY-CONT LY-STR LY-LNK LY-OUT PDF-LAYOUT-READ  LY-PAGE PDF-PAGE-CLOSE ;
: LY-LINKS  ( -- n )  LY-OUT PDF-LAYOUT-LINKS ;
: LY-LINK  ( i -- block offset length link )  LY-OUT PDF-LAYOUT-LINK ;
: LY-UNLINK  ( -- )  LY-LNK PDF-LINKS-FREE ;
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
            block = {"kind": kind, "level": level, "item": item, "number": number,
                     "width": width, "top": top / 65536, "text": text.decode("utf-8"),
                     "meanings": meanings, "raw": text}
            if kind == FIGURE:
                num, w, h = self.call("LY-FIGURE", i)
                block["figure"] = (num, round(w / 65536, 3), round(h / 65536, 3))
            out.append(block)
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


QUOTE = 1

TAGGED = (b"/Heading << /MCID 0 >> BDC BT /F1 10 Tf 72 700 Td (Body-size heading) Tj ET EMC\n"
          b"/P << /MCID 1 >> BDC BT /F1 10 Tf 72 688 Td (First paragraph, one line.) Tj ET EMC\n"
          b"/P << /MCID 2 >> BDC BT /F1 10 Tf 72 676 Td (Second paragraph, right below.) Tj ET EMC\n"
          b"/Span << /MCID 3 >> BDC BT /F1 10 Tf 72 664 Td (A paragraph with ) Tj ET EMC\n"
          b"/P << /MCID 4 >> BDC BT /F1 10 Tf 154.7 664 Td (a span inside.) Tj ET EMC\n"
          b"/Artifact BMC BT /F1 10 Tf 300 30 Td (12) Tj ET EMC\n"
          b"/Lbl << /MCID 5 >> BDC BT /F1 10 Tf 72 640 Td (a\\)) Tj ET EMC\n"
          b"/LBody << /MCID 6 >> BDC BT /F1 10 Tf 90 640 Td (lettered item) Tj ET EMC\n")


def tagged_pdf() -> bytes:
    objects = {
        1: b"<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 20 0 R /MarkInfo << /Marked true >> >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /StructParents 0 "
           b"/Resources << /Font << /F1 10 0 R >> >> /Contents 4 0 R >>",
        4: stream_object(zlib.compress(TAGGED), b"/Filter /FlateDecode"),
        10: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        20: b"<< /Type /StructTreeRoot /K 30 0 R /ParentTree 31 0 R /RoleMap 33 0 R >>",
        21: b"<< /Type /StructElem /S /Heading /P 30 0 R /K 0 /Pg 3 0 R >>",
        22: b"<< /Type /StructElem /S /P /P 30 0 R /K 1 /Pg 3 0 R >>",
        23: b"<< /Type /StructElem /S /P /P 30 0 R /K 2 /Pg 3 0 R >>",
        24: b"<< /Type /StructElem /S /P /P 30 0 R /K [25 0 R 4] /Pg 3 0 R >>",
        25: b"<< /Type /StructElem /S /Span /P 24 0 R /K 3 /Pg 3 0 R >>",
        26: b"<< /Type /StructElem /S /LI /P 28 0 R /K [27 0 R 29 0 R] >>",
        27: b"<< /Type /StructElem /S /Lbl /P 26 0 R /K 5 /Pg 3 0 R >>",
        28: b"<< /Type /StructElem /S /L /P 30 0 R /K [26 0 R] "
            b"/A [<< /O /Layout >> 0 << /O /List /ListNumbering /LowerAlpha >>] >>",
        29: b"<< /Type /StructElem /S /LBody /P 26 0 R /K 6 /Pg 3 0 R >>",
        30: b"<< /Type /StructElem /S /Document /P 20 0 R /K [21 0 R 22 0 R 23 0 R 24 0 R 28 0 R] >>",
        31: b"<< /Kids [34 0 R 32 0 R] >>",
        32: b"<< /Limits [0 0] /Nums [0 [21 0 R 22 0 R 23 0 R 25 0 R 24 0 R 27 0 R 29 0 R]] >>",
        33: b"<< /Heading /Hx /Hx /H3 >>",
        34: b"<< /Limits [5 9] /Nums [5 []] >>",
    }
    return write_pdf(objects)


def test_a_tagged_page_takes_its_blocks_from_its_structure(layout):
    layout.open(tagged_pdf())
    assert layout.read() == OK
    assert [(b["kind"], b["level"], b["item"], b["number"], b["text"]) for b in layout.blocks()] == [
        (HEADING, 3, 0, 0, "Body-size heading"),
        (PARAGRAPH, 0, 0, 0, "First paragraph, one line."),
        (PARAGRAPH, 0, 0, 0, "Second paragraph, right below."),
        (PARAGRAPH, 0, 0, 0, "A paragraph with a span inside."),
        (PARAGRAPH, 0, NUMBERED, 1, "lettered item"),
    ]
    layout.close()


@pytest.mark.skipif(shutil.which("soffice") is None, reason="LibreOffice is not installed")
def test_a_tagged_document_libreoffice_wrote(layout, tmp_path):
    (tmp_path / "doc.html").write_text(
        "<html><body><h1>A heading</h1><p>Paragraph one, with <b>bold</b> and <i>italic</i> words, "
        "long enough to wrap onto a second line of the page so that the layout joins its lines "
        "again.</p><h2>A smaller heading</h2><ul><li>first item</li><li>second item</li></ul>"
        "<ol><li>one</li><li>two</li></ol><pre>code line one\n  code line two</pre>"
        "<blockquote>A quoted passage.</blockquote><p>Last paragraph.</p></body></html>",
        encoding="utf-8")
    export = 'pdf:writer_pdf_Export:{"UseTaggedPDF":{"type":"boolean","value":"true"}}'
    subprocess.run(["soffice", f"-env:UserInstallation=file://{tmp_path}/profile", "--headless",
                    "--convert-to", export, "--outdir", str(tmp_path), str(tmp_path / "doc.html")],
                   check=True, capture_output=True, timeout=120)
    layout.open((tmp_path / "doc.pdf").read_bytes())
    assert layout.read() == OK
    assert [(b["kind"], b["level"], b["item"], b["number"], b["text"]) for b in layout.blocks()] == [
        (HEADING, 1, 0, 0, "A heading"),
        (PARAGRAPH, 0, 0, 0, "Paragraph one, with bold and italic words, long enough to wrap onto "
                             "a second line of the page so that the layout joins its lines again."),
        (HEADING, 2, 0, 0, "A smaller heading"),
        (PARAGRAPH, 0, BULLET, 0, "first item"),
        (PARAGRAPH, 0, BULLET, 0, "second item"),
        (PARAGRAPH, 0, NUMBERED, 1, "one"),
        (PARAGRAPH, 0, NUMBERED, 2, "two"),
        (CODE, 0, 0, 0, "code line one\n  code line two"),
        (PARAGRAPH, 0, QUOTE, 0, "A quoted passage."),
        (PARAGRAPH, 0, 0, 0, "Last paragraph."),
    ]
    layout.close()


def picture(width: int = 2, height: int = 2) -> bytes:
    return stream_object(bytes(width * height), b"/Type /XObject /Subtype /Image /Width %d /Height %d "
                         b"/ColorSpace /DeviceGray /BitsPerComponent 8" % (width, height))


BOLD = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"


def set_lines(text: str, measures: list[float]) -> list[str]:
    """TEXT broken at spaces into lines, line I no wider than MEASURES[I],
    the last measure serving every line after it, at 10 points."""

    from sample_pdf import _width
    lines, line = [], ""
    for word in text.split(" "):
        trial = f"{line} {word}" if line else word
        measure = measures[min(len(lines), len(measures) - 1)]
        if line and _width(trial, "F1", 10) > measure * 1000:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def justified(x: float, y: float, line: str, measure: float) -> bytes:
    """LINE at 10 points from (X, Y), its spaces widened so it ends MEASURE
    points on, as a printed column's lines do; a MEASURE of 0, for a
    paragraph's last line, leaves them as they are."""

    from sample_pdf import _width
    spaces = line.count(" ")
    natural = _width(line, "F1", 10) / 1000
    tw = (measure - natural) / spaces if spaces and measure else 0
    return b"BT /F1 10 Tf %.3f Tw %g %g Td (%s) Tj ET\n" % (tw, x, y, line.encode("cp1252"))


TWO_A = ("The first column starts with a paragraph of several lines, set justified "
         "as a printed paper sets its text, so each line but its last runs to the "
         "column's edge.")
TWO_B = ("The second paragraph begins with an indented line and runs on past the "
         "foot of the first column, so that its last lines are set at the top of the "
         "second column, where a reader goes on without a break between the two.")
TWO_C = ("The third paragraph starts with an indent in the second column, after the "
         "end of the second paragraph, and ends there.")
WIDE = ("A paragraph set across both columns, as an abstract can be, runs from the "
        "left margin to the right one over the gutter between them.")


def two_column_pdf(carried: bool = True) -> tuple[bytes, list[str]]:
    """A page of a title and a paragraph across both columns, then two
    columns of justified paragraphs; with CARRIED, the second paragraph
    goes on from the foot of the first column to the top of the second,
    else it ends in the first and the second column starts afresh.  The
    texts the layout should give, in order."""

    ops = [line("F2", 20, 72, 760, "Two Columns")]
    for i, text in enumerate(wide := set_lines(WIDE, [468])):
        ops.append(justified(72, 736 - 12 * i, text, 468 if i < len(wide) - 1 else 0))
    a = set_lines(TWO_A, [216])
    b = set_lines(TWO_B, [201, 216])
    c = set_lines(TWO_C, [201, 216])
    top = 700
    y = top
    for i, text in enumerate(a):
        ops.append(justified(72, y, text, 216 if i < len(a) - 1 else 0))
        y -= 12
    split = len(b) - 2 if carried else len(b)
    for i, text in enumerate(b[:split]):
        x, measure = (87, 201) if i == 0 else (72, 216)
        ops.append(justified(x, y, text, measure if i < len(b) - 1 else 0))
        y -= 12
    y = top
    if carried:
        for i, text in enumerate(b[split:], split):
            ops.append(justified(324, y, text, 216 if i < len(b) - 1 else 0))
            y -= 12
    for i, text in enumerate(c):
        x, measure = (339, 201) if i == 0 and carried else (324, 216 if i else 201)
        ops.append(justified(x, y, text, measure if i < len(c) - 1 else 0))
        y -= 12
    texts = ["Two Columns", WIDE, TWO_A, TWO_B, TWO_C]
    pdf = page_pdf(b"".join(ops), resources=b"<< /Font << /F1 10 0 R /F2 11 0 R >> >>",
                   extra={11: BOLD})
    return pdf, texts


def test_two_columns_read_as_their_paragraphs(layout):
    """On a page of two columns, a line is short against its own column's
    end, so a column's lines make paragraphs, not a block each; a title and
    a paragraph across both columns span the gutter; and a paragraph whose
    last line in the first column runs to its end goes on at the top of the
    second."""

    pdf, texts = two_column_pdf()
    layout.open(pdf)
    assert layout.read() == OK
    blocks = layout.blocks()
    assert [b["text"] for b in blocks] == texts
    assert [b["kind"] for b in blocks] == [HEADING] + [PARAGRAPH] * 4
    layout.close()


def test_a_paragraph_ending_at_a_column_s_foot_ends_there(layout):
    """A paragraph whose last line ends short at the foot of the first
    column ends there: the second column starts a paragraph of its own,
    though its first line is not indented."""

    pdf, texts = two_column_pdf(carried=False)
    layout.open(pdf)
    assert layout.read() == OK
    assert [b["text"] for b in layout.blocks()] == texts
    layout.close()


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_two_column_article_xelatex_wrote(layout, tmp_path):
    """A two-column article reads as its source's paragraphs, each whole,
    the one the first column's foot splits included."""

    from measure_pdf import SENTENCES
    paragraphs = [[" ".join(SENTENCES[(s + p + k) % len(SENTENCES)] for k in range(6))
                   for p in range(3)] for s in range(3)]
    tex = [r"\documentclass[twocolumn]{article}\begin{document}"]
    for s, section in enumerate(paragraphs):
        tex.append(r"\section{Section %d}" % (s + 1))
        tex.extend(text + "\n" for text in section)
    tex.append(r"\end{document}")
    (tmp_path / "two.tex").write_text("\n\n".join(tex), encoding="utf-8")
    subprocess.run(["xelatex", "-interaction=batchmode", "two.tex"], cwd=tmp_path,
                   capture_output=True, check=True)
    layout.open((tmp_path / "two.pdf").read_bytes())
    assert layout.read() == OK
    blocks = layout.blocks()
    layout.close()
    got = [b["text"].replace("\u2019", "'") for b in blocks if b["kind"] == PARAGRAPH]
    want = [text for section in paragraphs for text in section]
    assert got == want[:len(got)] and len(got) >= 5, got
    # The first column's foot fell inside a paragraph, which reads whole.
    assert [b["text"] for b in blocks if b["kind"] == HEADING] == [
        "1 Section 1", "2 Section 2", "3 Section 3"][:sum(b["kind"] == HEADING for b in blocks)]


def pictured_pdf() -> bytes:
    stream = b"".join([
        line("F2", 20, 72, 720, "A Title Here"),
        line("F1", 10, 72, 690, "A paragraph before the picture, long enough to reach the right"),
        line("F1", 10, 72, 678, "margin, and it goes on to a second line."),
        b"q 200 0 0 120 72 540 cm /Im1 Do Q\n",
        b"q 6 0 0 6 60 520 cm /Im1 Do Q\n",
        b"/Artifact BMC q 612 0 0 792 0 0 cm /Im1 Do Q EMC\n",
        line("F1", 10, 72, 520, "A paragraph after it, which also runs to the margin of the page"),
        line("F1", 10, 72, 508, "and then the picture below breaks it, here."),
        b"q 0 80 -150 0 400 300 cm /Im2 Do Q\n",
        line("F1", 10, 72, 496, "Its last line follows the picture."),
    ])
    resources = b"<< /Font << /F1 10 0 R /F2 11 0 R >> /XObject << /Im1 30 0 R /Im2 31 0 R >> >>"
    return page_pdf(stream, resources=resources, extra={
        11: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
        30: picture(), 31: picture(3, 2)})


def test_pictures_are_figures_where_they_fall(layout):
    layout.open(pictured_pdf())
    assert layout.read() == OK
    blocks = layout.blocks()
    assert [b["kind"] for b in blocks] == [HEADING, PARAGRAPH, FIGURE, PARAGRAPH, FIGURE, PARAGRAPH]
    assert blocks[2]["figure"] == (30, 200, 120) and blocks[2]["top"] == 660 and blocks[2]["text"] == ""
    assert blocks[4]["figure"] == (31, 150, 80) and blocks[4]["top"] == 380
    assert blocks[3]["text"].endswith("breaks it, here.")
    assert blocks[5]["text"] == "Its last line follows the picture."
    layout.close()


def test_blocks_keep_where_they_lie(layout):
    """Each block keeps its top, its low (its lowest line's middle, a third
    of its size above its baseline), how far across its lines reach, and
    its first line's size; a figure its box, its middle and no size."""

    from sample_pdf import HELVETICA, HELVETICA_BOLD

    def width(text: str, table: tuple[int, ...], size: int) -> float:
        return sum(table[ord(c) - 32] for c in text) * size / 1000

    layout.open(pictured_pdf())
    assert layout.read() == OK
    places = [tuple(round(v / 65536, 3) for v in layout.call("LY-PLACE", i))
              for i in range(layout.call("LY-BLOCKS")[0])]
    body = width("A paragraph before the picture, long enough to reach the right", HELVETICA, 10)
    after = width("A paragraph after it, which also runs to the margin of the page", HELVETICA, 10)
    assert places == [
        (740, round(720 + 20 / 3, 3), 72, round(72 + width("A Title Here", HELVETICA_BOLD, 20), 3), 20),
        (700, round(678 + 10 / 3, 3), 72, round(72 + body, 3), 10),
        (660, 600, 72, 272, 0),
        (530, round(508 + 10 / 3, 3), 72, round(72 + after, 3), 10),
        (380, 340, 250, 400, 0),
        (506, round(496 + 10 / 3, 3), 72,
         round(72 + width("Its last line follows the picture.", HELVETICA, 10), 3), 10),
    ]
    layout.close()


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_picture_xelatex_places(layout, tmp_path):
    from PIL import Image
    Image.new("RGB", (60, 40), (200, 30, 30)).save(tmp_path / "red.png")
    (tmp_path / "doc.tex").write_text(
        "\\documentclass{article}\\usepackage{graphicx}\\begin{document}\n"
        "A paragraph before the picture.\n\n"
        "\\includegraphics[width=4cm]{red.png}\n\n"
        "A paragraph after the picture.\n\\end{document}\n")
    subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                   check=True, capture_output=True)
    layout.open((tmp_path / "doc.pdf").read_bytes())
    assert layout.read() == OK
    blocks = layout.blocks()
    assert [(b["kind"], b["text"]) for b in blocks] == [
        (PARAGRAPH, "A paragraph before the picture."), (FIGURE, ""),
        (PARAGRAPH, "A paragraph after the picture.")]
    width = blocks[1]["figure"][1]
    assert abs(width - 4 * 72 / 2.54) < 0.5 and abs(blocks[1]["figure"][2] - width * 40 / 60) < 0.5
    layout.close()


@pytest.mark.skipif(shutil.which("soffice") is None, reason="LibreOffice is not installed")
def test_a_picture_libreoffice_places(layout, tmp_path):
    from PIL import Image
    Image.new("RGB", (60, 40), (30, 30, 200)).save(tmp_path / "blue.png")
    (tmp_path / "doc.html").write_text(
        '<html><body><p>A paragraph before the picture.</p>'
        '<p><img src="blue.png" width="120" height="80"></p>'
        '<p>A paragraph after the picture.</p></body></html>', encoding="utf-8")
    subprocess.run(["soffice", f"-env:UserInstallation=file://{tmp_path}/profile", "--headless",
                    "--convert-to", "pdf", "--outdir", str(tmp_path), str(tmp_path / "doc.html")],
                   check=True, capture_output=True, timeout=120)
    layout.open((tmp_path / "doc.pdf").read_bytes())
    assert layout.read() == OK
    blocks = layout.blocks()
    assert [(b["kind"], b["text"]) for b in blocks] == [
        (PARAGRAPH, "A paragraph before the picture."), (FIGURE, ""),
        (PARAGRAPH, "A paragraph after the picture.")]
    layout.close()


# --------------------------------------------------------------------------
# Links
# --------------------------------------------------------------------------

def link(rect: tuple[float, float, float, float], target: bytes) -> bytes:
    return (b"<< /Type /Annot /Subtype /Link /Rect [%g %g %g %g] " % rect) + target + b" >>"


def words(font: str, size: float, x: float, y: float, step: float, *parts: str) -> bytes:
    """Each word a run of its own, STEP apart, as TeX sets them."""
    return b"".join(line(font, size, x + i * step, y, part) for i, part in enumerate(parts))


LINKED = b"".join([
    words("F1", 8, 72, 700, 40, "See", "the", "section", "on", "links", "and", "the", "web", "site."),
    line("F4", 10, 72, 660, "See the section on links."),
    words("F1", 8, 72, 620, 40, "This", "sentence", "has", "a", "link", "that", "goes", "over",
          "all"),
    words("F1", 8, 72, 610, 40, "two", "lines", "here,", "and", "then", "stops", "on", "a", "short"),
    words("F1", 8, 72, 600, 40, "line."),
])


def linked_pdf() -> bytes:
    resources = b"<< /Font << /F1 10 0 R /F4 13 0 R >> >>"
    return page_pdf(LINKED, resources=resources, extra={
        13: COURIER,
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources " + resources
           + b" /Contents 4 0 R /Annots [20 0 R 21 0 R 22 0 R 23 0 R 24 0 R] >>",
        20: link((150, 696, 270, 708), b"/Dest [3 0 R /XYZ 0 792 0]"),
        21: link((350, 696, 420, 708), b"/A << /S /URI /URI (https://example.com/) >>"),
        # Inside "section" of the Courier line, short of its ends.
        22: link((122, 657, 157, 668), b"/Dest (named)"),
        23: link((310, 616, 388, 628), b"/A << /S /URI /URI (https://example.org/) >>"),
        24: link((70, 606, 150, 618), b"/A << /S /URI /URI (https://example.org/) >>"),
    })


def test_links_cover_the_text_their_rectangles_meet(layout):
    """A link covers the words whose runs its rectangle meets, across the
    spaces between them, or the words its share of a run's span takes in
    proportion; each block's text says where, in the block's own bytes."""

    layout.open(linked_pdf())
    assert layout.call("LY-READ-LINKED", 0) == (OK,)
    blocks = layout.blocks()
    places = [layout.call("LY-LINK", i) for i in range(layout.call("LY-LINKS")[0])]
    layout.call("LY-UNLINK")
    layout.close()
    covered = [(block, blocks[block]["raw"][offset:offset + length], link)
               for block, offset, length, link in places]
    assert covered == [
        (0, b"section on links", 0), (0, b"web site.", 1),
        (1, b"section", 2),
        (2, b"goes over", 3), (2, b"two lines", 4),
    ], (covered, [b["text"] for b in blocks])
    assert [b["kind"] for b in blocks] == [PARAGRAPH, CODE, PARAGRAPH]


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_links_hyperref_writes_cover_their_words(layout, tmp_path):
    """The references, citations and addresses hyperref links cover the
    words a reader sees as links."""

    from test_pdf_navigate import HYPERREF
    (tmp_path / "doc.tex").write_text(HYPERREF, encoding="utf-8")
    for _ in range(2):
        subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                       capture_output=True, check=True)
    layout.open((tmp_path / "doc.pdf").read_bytes())
    assert layout.call("LY-READ-LINKED", 0) == (OK,)
    blocks = layout.blocks()
    places = [layout.call("LY-LINK", i) for i in range(layout.call("LY-LINKS")[0])]
    layout.call("LY-UNLINK")
    layout.close()
    covered = [blocks[block]["raw"][offset:offset + length] for block, offset, length, _ in places]
    assert b"the paper" in covered and b"2" in covered, covered
    assert any(text.startswith(b"1") and b"Introduction" in text for text in covered), covered
