#!/usr/bin/env python3
"""Akashic pdf/navigate.f, pdf/tree.f, pdf/textstr.f and PDF-PAGE-INDEX:
where a PDF's links and outline go.

A file written by hand holds three pages in a two-level tree.  Its first
page's links go to a page by an explicit destination, by a name through
the catalog's /Dests (one with a #20 in it), by a string through a name
tree whose kids and pairs lie behind references and out of order, by a
name found only in the tree and a string found only in /Dests, and to
the web; a link that launches a program and an annotation that is no
link are left out.  Destinations are kept as they are and followed on
demand, down to a page index.  The outline nests, has titles in
PDFDocEncoding, UTF-16BE and UTF-16LE, an item to the web and one that
goes nowhere; an outline that loops gives each item once.  Number trees,
text strings and UTF-8 are read directly.  Documents xelatex with
hyperref and LibreOffice wrote are read as MuPDF reads them.  Every byte
is given back.
"""

from __future__ import annotations

import shutil
import subprocess

import pytest

from forth_dependencies import dependency_order
from test_pdf_file import write_pdf
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, MISSING = 0, 1, 5
T_END, T_NAME, T_STRING, T_HEX, T_ARRAY = 0, 3, 4, 5, 6
ONE = 1 << 16
FILE_BYTES = 1 << 20

PRELUDE = f"""
{FILE_BYTES} XBUF NV-BYTES
CREATE NV-SRCS MEDSRC-SIZE 7 + ALLOT  : NV-SRC  NV-SRCS 7 + -8 AND ;
CREATE NV-MSRCS MSRC-SIZE 7 + ALLOT  : NV-MSRC  NV-MSRCS 7 + -8 AND ;
CREATE NV-FILES PDF-FILE-SIZE 7 + ALLOT  : NV-FILE  NV-FILES 7 + -8 AND ;
CREATE NV-PAGES PDF-PAGE-SIZE 7 + ALLOT  : NV-PAGE  NV-PAGES 7 + -8 AND ;
CREATE NV-LINKSS PDF-LINKS-SIZE 7 + ALLOT  : NV-LINKS  NV-LINKSS 7 + -8 AND ;
CREATE NV-OUTS PDF-OUTLINE-SIZE 7 + ALLOT  : NV-OUT  NV-OUTS 7 + -8 AND ;
CREATE NV-TBS PDF-BUF-SIZE 7 + ALLOT  : NV-TB  NV-TBS 7 + -8 AND ;
VARIABLE NV-LIMIT   VARIABLE NV-CAT
: NV-ALLOC  ( bytes ctx -- addr|0 )
    DROP DUP NV-LIMIT @ > IF DROP 0 EXIT THEN ALLOCATE IF DROP 0 THEN ;
: NV-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: NV-OPEN  ( u -- status )
    -1 1 RSHIFT NV-LIMIT !
    NV-BYTES SWAP NV-SRC MEDSRC-MEMORY
    ['] NV-ALLOC ['] NV-FREE 0 0 NV-MSRC MSRC-INIT
    NV-PAGE PDF-PAGE-SIZE 0 FILL  NV-LINKS PDF-LINKS-SIZE 0 FILL  NV-OUT PDF-OUTLINE-SIZE 0 FILL
    NV-TB PDF-BUF-SIZE 0 FILL
    NV-SRC NV-MSRC NV-FILE PDF-OPEN ;
: NV-CLOSE  ( -- held )
    NV-LINKS PDF-LINKS-FREE  NV-OUT PDF-OUTLINE-FREE  NV-PAGE PDF-PAGE-END
    NV-TB NV-MSRC PDF-BUF-FREE  NV-FILE PDF-CLOSE  NV-MSRC MSRC-HELD@ ;
: NV-INDEX  ( num -- i status )  NV-FILE PDF-PAGE-INDEX ;
: NV-DEST  ( va vu type -- num left top status )  NV-FILE PDF-DEST ;
: NV-LINKS-READ  ( i -- status )
    NV-LINKS PDF-LINKS-FREE
    NV-FILE NV-PAGE PDF-PAGE-OPEN ?DUP IF EXIT THEN
    NV-PAGE NV-LINKS PDF-LINKS-READ  NV-PAGE PDF-PAGE-CLOSE ;
: NV-PAGE-OPEN  ( i -- status )  NV-FILE NV-PAGE PDF-PAGE-OPEN ;
: NV-PAGE-CLOSE  ( -- )  NV-PAGE PDF-PAGE-CLOSE ;
: NV-LINKS-ONLY  ( -- status )  NV-LINKS PDF-LINKS-FREE  NV-PAGE NV-LINKS PDF-LINKS-READ ;
: NV-LINK  ( i -- x0 y0 x1 y1 va vu type a u )
    NV-LINKS PDF-LINK >R  R@ PDF-LINK-RECT  R@ NV-LINKS PDF-LINK-DEST  R> NV-LINKS PDF-LINK-URI ;
: NV-LINKS-N  ( -- n )  NV-LINKS PDF-LINKS-COUNT ;
: NV-OUTLINE  ( -- status )  NV-OUT PDF-OUTLINE-FREE  NV-FILE NV-OUT PDF-OUTLINE-READ ;
: NV-ITEMS  ( -- n )  NV-OUT PDF-OUTLINE-COUNT ;
: NV-ITEM  ( i -- level ta tu va vu type a u )
    NV-OUT PDF-OUTLINE-ITEM >R  R@ PDF-ITEM-LEVEL  R@ NV-OUT PDF-ITEM-TITLE
    R@ NV-OUT PDF-ITEM-DEST  R> NV-OUT PDF-ITEM-URI ;
: NV-NUMS  ( key -- obj va vu type status )
    S" Root" NV-FILE PDF-TRAILER@ NV-FILE PDF-RESOLVE DROP DROP ROT NV-CAT !
    S" PageLabels" 2SWAP PDF-DICT@ NV-FILE PDF-NUMS@ ;
: NV-NUMS-END  ( obj -- )  NV-FILE PDF-OBJ-FREE  NV-CAT @ NV-FILE PDF-OBJ-FREE ;
: NV-TEXT  ( a u -- ok? )  0 NV-TB PDF-BUF.U !  NV-TB NV-MSRC PDF-TEXTSTR+ ;
: NV-CHAR  ( cp -- ok? )  NV-TB NV-MSRC PDF-CHAR+ ;
: NV-TB@  ( -- a u )  NV-TB PDF-BUF.A @ NV-TB PDF-BUF.U @ ;
"""


def signed(value: int) -> int:
    return value - (1 << 64) if value >= 1 << 63 else value


class Navigate:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=32 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/navigate.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-navigate",
                              step_budget=400_000_000)
        self.runtime.drain_uart_output()
        self.bytes = self.word("NV-BYTES")
        self.limit = self.word("NV-LIMIT")

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0, stack.snapshot()
        for value in args:
            stack.push(value)
        self.runtime.execute(name, step_budget=4_000_000_000)
        result = tuple(stack.snapshot())
        while stack.depth():
            stack.pop()
        return result

    def read(self, a: int, u: int) -> bytes:
        return self.runtime.memory.read_bytes(a, u) if u else b""

    def open(self, pdf: bytes) -> None:
        self.runtime.memory.write_bytes(self.bytes, pdf)
        assert self.call("NV-OPEN", len(pdf)) == (OK,)

    def close(self) -> None:
        assert self.call("NV-CLOSE") == (0,)

    def refuse_above(self, bytes_: int) -> None:
        self.runtime.memory.write_bytes(self.limit, bytes_.to_bytes(8, "little"))

    def follow(self, va: int, vu: int, kind: int) -> tuple[int, float, float, int, int]:
        """A kept destination followed: page object, left, top, page index,
        status; -1 for a left or top it does not give."""
        num, left, top, status = self.call("NV-DEST", va, vu, kind)
        if status != OK:
            return num, -1, -1, -1, status
        index, status = self.call("NV-INDEX", num)
        left, top = signed(left), signed(top)
        return (num, left / ONE if left != -1 else -1, top / ONE if top != -1 else -1,
                signed(index), status)

    def links(self, index: int) -> list[tuple]:
        assert self.call("NV-LINKS-READ", index) == (OK,)
        out = []
        for i in range(self.call("NV-LINKS-N")[0]):
            x0, y0, x1, y1, va, vu, kind, a, u = self.call("NV-LINK", i)
            rect = (x0 / ONE, y0 / ONE, x1 / ONE, y1 / ONE)
            if kind == T_END:
                out.append((rect, None, None, self.read(a, u)))
            else:
                out.append((rect, self.read(va, vu), self.follow(va, vu, kind), b""))
        return out

    def outline(self) -> list[tuple]:
        assert self.call("NV-OUTLINE") == (OK,)
        out = []
        for i in range(self.call("NV-ITEMS")[0]):
            level, ta, tu, va, vu, kind, a, u = self.call("NV-ITEM", i)
            title = self.read(ta, tu).decode("utf-8")
            if kind == T_END:
                out.append((level, title, None, self.read(a, u)))
            else:
                out.append((level, title, self.follow(va, vu, kind)[:4], b""))
        return out

    def text(self, data: bytes) -> str:
        self.runtime.memory.write_bytes(self.bytes, data)
        assert self.call("NV-TEXT", self.bytes, len(data)) != (0,)
        a, u = self.call("NV-TB@")
        return self.read(a, u).decode("utf-8")


@pytest.fixture(scope="module")
def nav():
    return Navigate()


def objects() -> dict[int, bytes]:
    return {
        1: b"<< /Type /Catalog /Pages 2 0 R /Outlines 20 0 R /Dests 30 0 R "
           b"/Names << /Dests 31 0 R >> /PageLabels 50 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 3 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [10 0 R 11 0 R "
           b"12 0 R 13 0 R 14 0 R 15 0 R << /Subtype /Link /Rect [200 100 50 90] "
           b"/Dest [7 0 R /FitR 0 0 100 650] >> 16 0 R 17 0 R 18 0 R 19 0 R] >>",
        4: b"<< /Type /Pages /Parent 2 0 R /Kids [5 0 R 7 0 R] /Count 2 >>",
        5: b"<< /Type /Page /Parent 4 0 R >>",
        7: b"<< /Type /Page /Parent 4 0 R >>",
        8: b"<< /Type /Page /Parent 4 0 R >>",
        10: b"<< /Type /Annot /Subtype /Link /Rect [72 700 200 712] /Dest [5 0 R /XYZ 72.5 600 0] >>",
        11: b"<< /Type /Annot /Subtype /Link /Rect [72 680 200 692] "
            b"/A << /S /URI /URI 40 0 R >> >>",
        12: b"<< /Type /Annot /Subtype /Link /Rect [72 660 200 672] /A << /S /GoTo /D (chapter2) >> >>",
        13: b"<< /Type /Annot /Subtype /Link /Rect [72 640 200 652] /Dest /intro >>",
        14: b"<< /Type /Annot /Subtype /Link /Rect [72 620 200 632] /A << /S /Launch /F (x.exe) >> >>",
        15: b"<< /Type /Annot /Subtype /Text /Rect [0 0 10 10] /Contents (note) >>",
        16: b"<< /Subtype /Link /Rect [1 2 3 4] /Dest /my#20place >>",
        17: b"<< /Subtype /Link /Rect [1 2 3 4] /A << /S /GoTo /D <696E74726F> >> >>",
        18: b"<< /Subtype /Link /Rect [1 2 3 4] /Dest /chapter1 >>",
        19: b"<< /Subtype /Link /Rect [1 2 3 4] /A << /S /GoTo /D (b) >> >>",
        20: b"<< /Type /Outlines /First 21 0 R /Last 23 0 R /Count 3 >>",
        21: b"<< /Title (Introduction) /Parent 20 0 R /Next 23 0 R /First 22 0 R /Last 22 0 R "
            b"/Count 1 /Dest [3 0 R /Fit] >>",
        22: b"<< /Title <FEFF0044 00E9 0074 0061 0069 006C 0073> /Parent 21 0 R "
            b"/A << /S /GoTo /D [5 0 R /XYZ null 300 null] >> >>",
        23: b"<< /Title (Chapter 2) /Parent 20 0 R /Prev 21 0 R /First 24 0 R /Dest (chapter2) >>",
        24: b"<< /Title <FFFE 5700 6500 6200> /Parent 23 0 R /Next 25 0 R "
            b"/A << /S /URI /URI (https://example.com/c) >> >>",
        25: b"<< /Title (Notes \\200) /Parent 23 0 R /Prev 24 0 R >>",
        30: b"<< /intro [3 0 R /FitH 500] /my#20place 41 0 R >>",
        31: b"<< /Kids 34 0 R >>",
        32: b"<< /Limits [(a) (b)] /Names 35 0 R >>",
        33: b"<< /Limits [(c) (d)] /Names [(chapter2) [7 0 R /Fit] (chapter1) [5 0 R /Fit]] >>",
        34: b"[32 0 R 33 0 R]",
        35: b"[(a) [3 0 R /Fit] (b) << /D [5 0 R /FitH 300] >>]",
        40: b"(https://example.com/a)",
        41: b"<< /D [5 0 R /XYZ 0 100 0] >>",
        50: b"<< /Kids [51 0 R 52 0 R] >>",
        51: b"<< /Limits [0 1] /Nums [0 (first) 1 (second)] >>",
        52: b"<< /Limits [5 9] /Nums [9 (last) 5 (middle)] >>",
    }


def test_page_indexes(nav):
    nav.open(write_pdf(objects()))
    assert [nav.call("NV-INDEX", num) for num in (3, 5, 7)] == [(0, OK), (1, OK), (2, OK)]
    assert nav.call("NV-INDEX", 2) == (0, OK)
    for stranger in (8, 10, 99, 0):
        index, status = nav.call("NV-INDEX", stranger)
        assert (signed(index), status) == (-1, MISSING), stranger
    nav.close()


def test_links_keep_their_destinations_and_follow_them(nav):
    nav.open(write_pdf(objects()))
    assert nav.links(0) == [
        ((72, 700, 200, 712), b"[5 0 R /XYZ 72.5 600 0]", (5, 72.5, 600, 1, OK), b""),
        ((72, 680, 200, 692), None, None, b"https://example.com/a"),
        ((72, 660, 200, 672), b"(chapter2)", (7, -1, -1, 2, OK), b""),
        ((72, 640, 200, 652), b"/intro", (3, -1, 500, 0, OK), b""),
        ((50, 90, 200, 100), b"[7 0 R /FitR 0 0 100 650]", (7, 0, 650, 2, OK), b""),
        ((1, 2, 3, 4), b"/my#20place", (5, 0, 100, 1, OK), b""),
        ((1, 2, 3, 4), b"<696E74726F>", (3, -1, 500, 0, OK), b""),
        ((1, 2, 3, 4), b"/chapter1", (5, -1, -1, 1, OK), b""),
        ((1, 2, 3, 4), b"(b)", (5, -1, 300, 1, OK), b""),
    ]
    assert nav.links(1) == []
    nav.close()


def test_a_destination_that_names_nothing(nav):
    nav.open(write_pdf(objects()))
    for value, kind in ((b"/nowhere", T_NAME), (b"(nowhere)", T_STRING), (b"[/XYZ 0 0 0]", T_ARRAY),
                        (b"[99 0 R /Fit]", T_ARRAY)):
        nav.runtime.memory.write_bytes(nav.bytes + FILE_BYTES - 64, value)
        num, left, top, status = nav.call("NV-DEST", nav.bytes + FILE_BYTES - 64, len(value), kind)
        if value.startswith(b"[99"):
            # An object the file does not have is still a page object to the
            # destination; the page tree is what says it is none.
            assert (num, status) == (99, OK)
            index, status = nav.call("NV-INDEX", num)
            assert (signed(index), status) == (-1, MISSING)
        else:
            assert (num, signed(left), signed(top), status) == (0, -1, -1, MISSING), value
    nav.close()


def test_the_outline(nav):
    nav.open(write_pdf(objects()))
    assert nav.outline() == [
        (0, "Introduction", (3, -1, -1, 0), b""),
        (1, "Détails", (5, -1, 300, 1), b""),
        (0, "Chapter 2", (7, -1, -1, 2), b""),
        (1, "Web", None, b"https://example.com/c"),
        (1, "Notes •", None, b""),
    ]
    nav.close()


def test_an_outline_that_loops_gives_each_item_once(nav):
    loop = objects()
    loop[23] = loop[23].replace(b"/Prev 21 0 R", b"/Next 21 0 R")
    loop[25] = loop[25].replace(b"/Prev 24 0 R", b"/Next 24 0 R /First 23 0 R")
    nav.open(write_pdf(loop))
    assert [title for _, title, _, _ in nav.outline()] == [
        "Introduction", "Détails", "Chapter 2", "Web", "Notes •"]
    nav.close()


def test_a_file_without_an_outline(nav):
    plain = objects()
    plain[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
    nav.open(write_pdf(plain))
    assert nav.outline() == []
    # Without /Dests or /Names, a named link is kept but goes nowhere.
    links = nav.links(0)
    assert links[3][1:3] == (b"/intro", (0, -1, -1, -1, MISSING))
    nav.close()


def test_memory_refused(nav):
    nav.open(write_pdf(objects()))
    nav.refuse_above(8)
    assert nav.call("NV-OUTLINE") == (MEMORY,)
    nav.refuse_above(1 << 40)
    assert nav.call("NV-PAGE-OPEN", 0) == (OK,)
    nav.refuse_above(8)
    assert nav.call("NV-LINKS-ONLY") == (MEMORY,)
    obj = b"[5 0 R /Fit]"
    nav.runtime.memory.write_bytes(nav.bytes + FILE_BYTES - 64, obj)
    assert nav.call("NV-DEST", nav.bytes + FILE_BYTES - 64, len(obj), T_ARRAY) == (
        5, (1 << 64) - 1, (1 << 64) - 1, OK)
    for value, kind in ((b"/intro", T_NAME), (b"(chapter2)", T_STRING)):
        nav.runtime.memory.write_bytes(nav.bytes + FILE_BYTES - 64, value)
        num, _, _, status = nav.call("NV-DEST", nav.bytes + FILE_BYTES - 64, len(value), kind)
        assert (num, status) == (0, MEMORY), value
    nav.refuse_above(1 << 40)
    nav.call("NV-PAGE-CLOSE")
    nav.close()


def test_number_trees(nav):
    nav.open(write_pdf(objects()))
    for key, want in ((0, b"(first)"), (1, b"(second)"), (5, b"(middle)"), (9, b"(last)"),
                      (3, None), (10, None), (-1, None)):
        obj, va, vu, kind, status = nav.call("NV-NUMS", key & ((1 << 64) - 1))
        assert status == OK
        assert (nav.read(va, vu) if kind != T_END else None) == want, key
        nav.call("NV-NUMS-END", obj)
    nav.close()


def test_text_strings(nav):
    nav.open(write_pdf(objects()))
    assert nav.text(b"Plain \x80 \x84 \x9d \x9f") == "Plain • — š �"
    assert nav.text(b"\xfe\xff\xd8\x34\xdd\x1e\x00A") == "\U0001d11eA"
    assert nav.text(b"\xfe\xff\x00\x1b\x65\x6e\x00\x1b\x00H\x00i") == "Hi"
    assert nav.text(b"\xfe\xff\xd8\x34\x00A\xdd\x1e") == "�A�"
    assert nav.text(b"\xfe\xff\x00\x09\x00\x01\x00x") == " x"
    assert nav.text(b"\xff\xfeH\x00i\x00") == "Hi"
    assert nav.text("﻿UTF-8 é".encode("utf-8")) == "UTF-8 é"
    assert nav.text(b"") == ""
    nav.call("NV-TEXT", 0, 0)
    for cp in (0x41, 0xE9, 0x20AC, 0x1F600):
        assert nav.call("NV-CHAR", cp) != (0,)
    a, u = nav.call("NV-TB@")
    assert nav.read(a, u).decode("utf-8") == "Aé€\U0001f600"
    nav.close()


MUPDF_SCRIPT = """
var doc = Document.openDocument(scriptArgs[0]);
function walk(items, level) {
  for (var i = 0; i < items.length; i++) {
    print("OUT\\t" + level + "\\t" + doc.resolveLink(items[i].uri) + "\\t" + items[i].title);
    if (items[i].down) walk(items[i].down, level + 1);
  }
}
walk(doc.loadOutline() || [], 0);
for (var p = 0; p < doc.countPages(); p++) {
  var page = doc.loadPage(p), links = page.getLinks();
  for (var j = 0; j < links.length; j++) {
    var l = links[j], b = l.getBounds();
    print("LINK\\t" + p + "\\t" + b.join(",") + "\\t" + page.getBounds()[3] + "\\t"
          + (l.isExternal() ? l.getURI() : doc.resolveLink(l.getURI())));
  }
}
"""

HYPERREF = r"""\documentclass{article}
\usepackage{hyperref}
\begin{document}
\tableofcontents
\section{Introduction}\label{sec:intro}
See section~\ref{sec:details} and \href{https://example.com/paper}{the paper}.
\subsection{Background}
Text.
\newpage
\section{Détails}\label{sec:details}
Back to \hyperref[sec:intro]{the introduction}.
\subsection{More}
\newpage
\section{End}
\end{document}
"""


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_document_xelatex_and_hyperref_wrote(nav, tmp_path):
    (tmp_path / "doc.tex").write_text(HYPERREF, encoding="utf-8")
    for _ in range(2):
        subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                       capture_output=True, check=True)
    outline, links = read_document(nav, tmp_path / "doc.pdf", 3)
    assert outline == [(0, "Introduction", 0), (1, "Background", 0), (0, "Détails", 1),
                       (1, "More", 1), (0, "End", 2)]
    assert [(page, to) for page, _, to in links] == [
        (0, 0), (0, 0), (0, 1), (0, 1), (0, 2), (0, 1), (0, "https://example.com/paper"), (1, 0)]
    same_as_mupdf(tmp_path, outline, links)


@pytest.mark.skipif(shutil.which("soffice") is None, reason="LibreOffice is not installed")
def test_a_document_libreoffice_wrote(nav, tmp_path):
    (tmp_path / "doc.html").write_text(
        '<html><body><h1>First chapter</h1><p>See <a href="#later">the later part</a> or '
        '<a href="https://example.org/x">the site</a>.</p><h2>A section</h2><p>Text.</p>'
        '<h1 style="page-break-before: always"><a name="later"></a>Second chapter</h1>'
        '<p>Back.</p></body></html>', encoding="utf-8")
    subprocess.run(["soffice", f"-env:UserInstallation=file://{tmp_path}/profile", "--headless",
                    "--convert-to", "pdf", "--outdir", str(tmp_path), str(tmp_path / "doc.html")],
                   check=True, capture_output=True, timeout=120)
    outline, links = read_document(nav, tmp_path / "doc.pdf", 2)
    assert ("A section", 0) in [(title, page) for _, title, page in outline]
    assert [(page, to) for page, _, to in links] == [(0, 1), (0, "https://example.org/x")]
    same_as_mupdf(tmp_path, outline, links)


def read_document(nav, path, pages: int) -> tuple[list, list]:
    """A document's outline, each item's page index, and its links, page by page."""
    nav.open(path.read_bytes())
    outline = [(level, title, target[3]) for level, title, target, _ in nav.outline()]
    links = []
    for page in range(pages):
        for rect, _, target, uri in nav.links(page):
            links.append((page, rect, uri.decode() if uri else target[3]))
    nav.close()
    return outline, links


def same_as_mupdf(tmp_path, outline: list, links: list) -> None:
    """The outline and links MuPDF reads in doc.pdf, when it is installed."""
    if shutil.which("mutool") is None:
        return
    (tmp_path / "read.js").write_text(MUPDF_SCRIPT)
    lines = subprocess.run(["mutool", "run", str(tmp_path / "read.js"), str(tmp_path / "doc.pdf")],
                           capture_output=True, text=True, check=True).stdout.splitlines()
    theirs = [line.split("\t") for line in lines]
    assert [(int(row[1]), row[3], int(row[2])) for row in theirs if row[0] == "OUT"] == outline
    their_links = [row[1:] for row in theirs if row[0] == "LINK"]
    assert len(their_links) == len(links)
    for (page, rect, to), (their_page, bounds, height, their_to) in zip(links, their_links):
        x0, top, x1, bottom = (float(v) for v in bounds.split(","))
        assert page == int(their_page)
        assert rect == pytest.approx((x0, float(height) - bottom, x1, float(height) - top), abs=0.01)
        assert str(to) == their_to
