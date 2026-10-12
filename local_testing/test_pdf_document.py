#!/usr/bin/env python3
"""Akashic pdf/document.f: a PDF read as a document, a page at a time.

A PDF opens as a document with a part for each page and no blocks.  Each
page read, in any order, gives its start, labelled with its number, then
the blocks pdf/layout.f lays the page out as, with their containers and
the blank rows between them, and keeps its text so each block's content
comes from it.  A page that cannot be opened says so, a file that needs a
password opens locked, one that is no PDF cannot be read, and every byte
is given back.
"""

from __future__ import annotations

import shutil
import subprocess
import zlib

import pytest

from forth_dependencies import dependency_order
from test_pdf_content import FILE_BYTES, HELVETICA
from test_pdf_crypt import encrypt
from test_pdf_file import stream_object, write_pdf
from test_pdf_layout import COURIER, OBLIQUE, PAGE as EVERY_BLOCK, TEX, Layout, line, picture
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, READ, INVALID, LOCKED = 0, 1, 2, 3, 4
PARAGRAPH, HEADING, CODE, FIGURE, PAGE = 1, 2, 3, 5, 6
QUOTE, BULLET, NUMBERED = 1, 2, 3
NOTE = b"(this page could not be read)"

PRELUDE = f"""
{FILE_BYTES} XBUF PD-BYTES
CREATE PD-SRCS MEDSRC-SIZE 7 + ALLOT  : PD-SRC  PD-SRCS 7 + -8 AND ;
CREATE PD-MSRCS MSRC-SIZE 7 + ALLOT  : PD-MSRC  PD-MSRCS 7 + -8 AND ;
CREATE PD-DOCS DOC-SIZE 7 + ALLOT  : PD-DOC  PD-DOCS 7 + -8 AND ;
: PD-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: PD-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: PD-OPEN  ( u -- status )
    PD-BYTES SWAP PD-SRC MEDSRC-MEMORY
    ['] PD-ALLOC ['] PD-FREE 0 0 PD-MSRC MSRC-INIT
    PD-SRC PDF-DOC-READER PD-MSRC PD-DOC DOC-OPEN ;
: PD-PARTS  ( -- n )  PD-DOC DOC-PARTS ;
: PD-READ  ( part -- status )  PD-DOC DOC-READ-PART ;
: PD-COUNT  ( -- n )  PD-DOC DOC-COUNT ;
: PD-BLOCK  ( i -- part kind level rows inside containers )
    DUP PD-DOC DOC-PART-OF SWAP PD-DOC DOC-BLOCK
    DUP BLK-KIND@ OVER BLK-LEVEL@ 2 PICK BLK-ROWS-BEFORE@ 3 PICK BLK-INSIDE@
    4 ROLL PD-DOC DOC-CONTAINERS NIP ;
: PD-CONTAINER  ( i j -- kind width number start? )
    SWAP PD-DOC DOC-BLOCK PD-DOC DOC-CONTAINERS DROP SWAP CNT-SIZE * +
    DUP CNT-KIND@ OVER CNT-WIDTH@ 2 PICK CNT-NUMBER@ 3 ROLL CNT-START? ;
: PD-CONTENT  ( i -- status kind level a u m fa fu )
    PD-DOC DOC-CONTENT ?DUP IF NIP 0 0 0 0 0 0 0 EXIT THEN
    >R 0 R@ DCT-KIND@ R@ DCT-LEVEL@ R@ DCT-TEXT R@ DCT-MAP R> DCT-FIGURE ;
: PD-CLOSE  ( -- held )  PD-DOC DOC-CLOSE PD-MSRC MSRC-HELD@ ;
: PD-LINKS  ( i -- n )  PD-DOC DOC-CONTENT DROP DCT-LINK-COUNT ;
: PD-LINK  ( i j -- start end ta tu )  SWAP PD-DOC DOC-CONTENT DROP DCT-LINK@ ;
: PD-ANCHOR  ( a u -- part )  PD-DOC DOC-ANCHOR-PART ;
: PD-CONTENTS  ( -- n status )  PD-DOC DOC-CONTENTS ;
: PD-ENTRY  ( i -- level ta tu key ga gu )
    DUP >R PD-DOC DOC-ENTRY R> PD-DOC DOC-ENTRY-GOES ;
"""


class Reader:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=96 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/document.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-document",
                              step_budget=800_000_000)
        self.runtime.drain_uart_output()
        self.runtime.execute("PD-BYTES")
        self.bytes = self.runtime.main_context.data.pop()
        self.steps = 0

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

    def open(self, pdf: bytes) -> int:
        assert len(pdf) <= FILE_BYTES
        self.runtime.memory.write_bytes(self.bytes, pdf)
        return self.call("PD-OPEN", len(pdf))[0]

    def read(self, part: int) -> int:
        return self.call("PD-READ", part)[0]

    def blocks(self) -> list[dict]:
        memory = self.runtime.memory
        out = []
        for i in range(self.call("PD-COUNT")[0]):
            part, kind, level, rows, inside, count = self.call("PD-BLOCK", i)
            containers = [(kind_, width, number, start != 0) for kind_, width, number, start
                          in (self.call("PD-CONTAINER", i, j) for j in range(count))]
            status, ckind, clevel, a, u, m, fa, fu = self.call("PD-CONTENT", i)
            assert status == OK and (ckind, clevel) == (kind, level)
            out.append({"part": part, "kind": kind, "level": level, "rows": rows,
                        "inside": inside, "containers": containers,
                        "text": memory.read_bytes(a, u), "meanings": memory.read_bytes(m, u),
                        "figure": memory.read_bytes(fa, fu)})
        return out

    def close(self) -> int:
        return self.call("PD-CLOSE")[0]


@pytest.fixture(scope="module")
def reader():
    return Reader()


@pytest.fixture(scope="module")
def layout():
    return Layout()


def _pages(layout: Layout, pdf: bytes, parts: int) -> list[list[dict] | None]:
    """Each page's blocks as pdf/layout.f lays it out alone, or None for a
    page that cannot be opened."""

    layout.open(pdf)
    pages = []
    for index in range(parts):
        pages.append(layout.blocks() if layout.read(index) == OK else None)
    layout.close()
    return pages


def _expected(pages: list[list[dict] | None], read: set[int]) -> list[dict]:
    """The document's blocks once the pages READ are read: for each, in page
    order, its start and then its blocks, a blank row before each but the
    first page's start, none between list items, inside between quotes."""

    out = []
    for index in sorted(read):
        label = b"%d" % (index + 1)
        out.append({"part": index, "kind": PAGE, "level": 0, "rows": 1 if index else 0,
                    "inside": 0, "containers": [], "text": label,
                    "meanings": bytes(len(label)), "figure": b""})
        if pages[index] is None:
            out.append({"part": index, "kind": PARAGRAPH, "level": 0, "rows": 1, "inside": 0,
                        "containers": [], "text": NOTE, "meanings": bytes(len(NOTE)),
                        "figure": b""})
            continue
        previous = 0
        for block in pages[index]:
            item = block["item"]
            if item == QUOTE and previous == QUOTE:
                rows, inside = 1, 1
            elif item in (BULLET, NUMBERED) and previous in (BULLET, NUMBERED):
                rows, inside = 0, 0
            else:
                rows, inside = 1, 0
            previous = item
            figure = b"picture %d" % block["figure"][0] if block["kind"] == FIGURE else b""
            out.append({"part": index, "kind": block["kind"], "level": block["level"],
                        "rows": rows, "inside": inside,
                        "containers": [(item, block["width"], block["number"], True)] if item else [],
                        "text": b"" if figure else block["raw"],
                        "meanings": b"" if figure else block["meanings"], "figure": figure})
    return out


def _comparable(blocks: list[dict]) -> list[dict]:
    """Blocks with a figure's meanings left out: it has no text to mean."""

    return [{**b, "meanings": b"" if b["kind"] == FIGURE else b["meanings"]} for b in blocks]


PICTURES = b"".join([
    line("F2", 20, 72, 720, "Pictures"),
    line("F1", 10, 72, 690, "A paragraph before the picture, long enough to reach the right"),
    line("F1", 10, 72, 678, "margin, and it goes on to a second line."),
    b"q 200 0 0 120 72 540 cm /Im1 Do Q\n",
    line("F1", 10, 72, 520, "A paragraph after it."),
])


def pages_pdf() -> bytes:
    """Four pages: one of every block, one with a picture, a short one, and
    a fourth the tree promises but does not hold."""

    resources = (b"<< /Font << /F1 10 0 R /F2 11 0 R /F3 12 0 R /F4 13 0 R >> "
                 b"/XObject << /Im1 30 0 R >> >>")
    return write_pdf({
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 4 /MediaBox [0 0 612 792] "
           b"/Resources " + resources + b" >>",
        3: b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
        4: stream_object(zlib.compress(EVERY_BLOCK), b"/Filter /FlateDecode"),
        5: b"<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>",
        6: stream_object(zlib.compress(PICTURES), b"/Filter /FlateDecode"),
        7: b"<< /Type /Page /Parent 2 0 R /Contents 8 0 R >>",
        8: stream_object(line("F1", 10, 72, 700, "The last page.")),
        10: HELVETICA,
        11: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
        12: OBLIQUE, 13: COURIER, 30: picture(),
    })


def test_pages_read_in_any_order_are_their_start_and_their_layout(reader, layout):
    """A part for each page and no blocks at first; each page read is its
    start, then its laid-out blocks with their containers, rows and
    meanings, in page order whatever order they were read in.  A page the
    tree cannot give says so; a page read again stays as it is."""

    pdf = pages_pdf()
    pages = _pages(layout, pdf, 4)
    assert pages[3] is None and all(page is not None for page in pages[:3])
    assert reader.open(pdf) == OK
    assert (reader.call("PD-PARTS"), reader.call("PD-COUNT")) == ((4,), (0,))
    read: set[int] = set()
    for index in (2, 0, 3, 1, 0):
        assert reader.read(index) == OK
        read.add(index)
        assert _comparable(reader.blocks()) == _comparable(_expected(pages, read)), index
    assert reader.read(4) == INVALID
    assert reader.close() == 0


def test_a_page_count_beyond_the_objects_is_the_objects(reader, layout):
    """The tree's count is at most the object numbers the file's table
    spans, each page being an object."""

    pdf = write_pdf({
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1000000 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
           b"/Resources << /Font << /F1 10 0 R >> >> >>",
        4: stream_object(line("F1", 10, 72, 700, "One page.")),
        10: HELVETICA,
    })
    layout.open(pdf)
    layout.runtime.evaluate(b": LY-OBJECTS  LY-FILE PDF-OBJECT-COUNT ;\n", source_name="objects")
    objects = layout.call("LY-OBJECTS")[0]
    layout.close()
    assert reader.open(pdf) == OK
    assert reader.call("PD-PARTS") == (objects,) and objects >= 11
    assert reader.read(objects - 1) == OK
    assert [b["text"] for b in reader.blocks()] == [b"%d" % objects, NOTE]
    assert reader.close() == 0


def test_files_it_cannot_read(reader, tmp_path):
    """A file that is no PDF cannot be read; one that needs a password is
    locked; both give everything back."""

    assert reader.open(b"%PDF-1.7\nthis is not a PDF at all\n") == READ
    assert reader.close() == 0
    if shutil.which("qpdf") is None:
        pytest.skip("qpdf is not installed")
    assert reader.open(encrypt(tmp_path, "128", "--use-aes=n", user="secret")) == LOCKED
    assert reader.close() == 0


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_document_xelatex_wrote(reader, layout, tmp_path):
    (tmp_path / "doc.tex").write_text(TEX.replace(r"\section{A section}",
                                                  r"\section{A section}\newpage"))
    subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                   check=True, capture_output=True)
    pdf = (tmp_path / "doc.pdf").read_bytes()
    assert reader.open(pdf) == OK
    parts = reader.call("PD-PARTS")[0]
    assert parts == 2
    pages = _pages(layout, pdf, parts)
    for index in range(parts):
        assert reader.read(index) == OK
    blocks = reader.blocks()
    assert _comparable(blocks) == _comparable(_expected(pages, set(range(parts))))
    assert [b["kind"] for b in blocks][:3] == [PAGE, HEADING, PAGE]
    assert reader.close() == 0


@pytest.mark.skipif(shutil.which("soffice") is None, reason="LibreOffice is not installed")
def test_a_tagged_document_libreoffice_wrote(reader, layout, tmp_path):
    (tmp_path / "doc.html").write_text(
        "<html><body><h1>A heading</h1><ul><li>first item</li><li>second item</li></ul>"
        "<blockquote><p>A quoted passage.</p><p>And a second one.</p></blockquote>"
        "<p>Last paragraph.</p></body></html>", encoding="utf-8")
    export = 'pdf:writer_pdf_Export:{"UseTaggedPDF":{"type":"boolean","value":"true"}}'
    subprocess.run(["soffice", f"-env:UserInstallation=file://{tmp_path}/profile", "--headless",
                    "--convert-to", export, "--outdir", str(tmp_path), str(tmp_path / "doc.html")],
                   check=True, capture_output=True, timeout=120)
    pdf = (tmp_path / "doc.pdf").read_bytes()
    assert reader.open(pdf) == OK and reader.read(0) == OK
    blocks = reader.blocks()
    assert _comparable(blocks) == _comparable(_expected(_pages(layout, pdf, 1), {0}))
    quoted = [b for b in blocks if b["containers"] and b["containers"][0][0] == QUOTE]
    assert [(b["rows"], b["inside"]) for b in quoted] == [(1, 0), (1, 1)]
    items = [b for b in blocks if b["containers"] and b["containers"][0][0] == BULLET]
    assert [b["rows"] for b in items] == [1, 0]
    assert reader.close() == 0


# --------------------------------------------------------------------------
# Links
# --------------------------------------------------------------------------

LINK = 9


def _links(reader: Reader, index: int) -> list[tuple[bytes, bytes]]:
    """Block INDEX's links: the text each covers, and its target."""

    memory = reader.runtime.memory
    text = reader.blocks()[index]["text"]
    out = []
    for j in range(reader.call("PD-LINKS", index)[0]):
        start, end, a, u = reader.call("PD-LINK", index, j)
        out.append((text[start:end], memory.read_bytes(a, u)))
    return out


def _anchor(reader: Reader, target: bytes) -> int:
    """The part a link's target names within the document, or -1."""

    assert target.startswith(b"#")
    address = reader.bytes + FILE_BYTES - 4096       # past the file, in its buffer
    reader.runtime.memory.write_bytes(address, target[1:])
    value = reader.call("PD-ANCHOR", address, len(target) - 1)[0]
    return value - (1 << 64) if value >= 1 << 63 else value


def test_a_page_gives_its_links_over_the_text_they_cover(reader):
    """A block's content has the links the layout placed over its text,
    in the link's look: a link to the web with its address, one within the
    file with "#" and its destination, which resolves to its page."""

    from test_pdf_layout import linked_pdf
    assert reader.open(linked_pdf()) == OK and reader.read(0) == OK
    blocks = reader.blocks()
    assert [b["kind"] for b in blocks] == [PAGE, PARAGRAPH, CODE, PARAGRAPH]
    first = _links(reader, 1)
    assert [text for text, _ in first] == [b"section on links", b"web site."]
    assert first[1][1] == b"https://example.com/"
    assert first[0][1].startswith(b"#") and _anchor(reader, first[0][1]) == 0
    code = _links(reader, 2)
    assert code[0][0] == b"section" and _anchor(reader, code[0][1]) == -1   # no such name
    assert [(text, target) for text, target in _links(reader, 3)] == [
        (b"goes over", b"https://example.org/"), (b"two lines", b"https://example.org/")]
    text, meanings = blocks[1]["text"], blocks[1]["meanings"]
    at = text.index(b"section on links")
    assert set(meanings[at:at + 16]) == {LINK} and meanings[at - 1] != LINK
    assert reader.close() == 0


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_hyperref_links_go_to_their_pages(reader, tmp_path):
    """The contents, a reference and an address hyperref writes are links
    whose targets name their pages, or the address."""

    from test_pdf_navigate import HYPERREF
    (tmp_path / "doc.tex").write_text(HYPERREF, encoding="utf-8")
    for _ in range(2):
        subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                       capture_output=True, check=True)
    assert reader.open((tmp_path / "doc.pdf").read_bytes()) == OK and reader.read(0) == OK
    blocks = reader.blocks()
    found = {}
    for index, block in enumerate(blocks):
        for text, target in _links(reader, index):
            found[text] = _anchor(reader, target) if target.startswith(b"#") else target
    assert found[b"1 Introduction"] == 0 and found["2 Détails".encode()] == 1
    assert found[b"3 End"] == 2 and found[b"2"] == 1
    assert found[b"the paper"] == b"https://example.com/paper"
    assert reader.close() == 0


# --------------------------------------------------------------------------
# Contents
# --------------------------------------------------------------------------

def _contents(reader: Reader) -> list[tuple[int, str, object]]:
    """The document's contents: each entry's level, title, and the part
    its target names, or its address."""

    memory = reader.runtime.memory
    count, status = reader.call("PD-CONTENTS")
    assert status == OK
    out = []
    for i in range(count):
        level, ta, tu, key, ga, gu = reader.call("PD-ENTRY", i)
        target = memory.read_bytes(ga, gu)
        assert key == 0
        goes = _anchor(reader, target) if target.startswith(b"#") else target
        out.append((level, memory.read_bytes(ta, tu).decode(), goes))
    return out


def test_a_pdf_without_an_outline_has_its_pages_as_contents(reader):
    assert reader.open(pages_pdf()) == OK
    assert _contents(reader) == [(0, f"Page {n + 1}", n) for n in range(4)]
    assert reader.call("PD-COUNT") == (0,)        # no page was read to make them
    assert reader.close() == 0


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_pdf_outline_is_its_contents(reader, tmp_path):
    from test_pdf_navigate import HYPERREF
    (tmp_path / "doc.tex").write_text(HYPERREF, encoding="utf-8")
    for _ in range(2):
        subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                       capture_output=True, check=True)
    assert reader.open((tmp_path / "doc.pdf").read_bytes()) == OK
    assert _contents(reader) == [(0, "Introduction", 0), (1, "Background", 0),
                                 (0, "Détails", 1), (1, "More", 1), (0, "End", 2)]
    assert reader.call("PD-COUNT") == (0,)
    assert reader.close() == 0


# --------------------------------------------------------------------------
# Page labels
# --------------------------------------------------------------------------

def _labelled(labels: bytes, extra: dict[int, bytes] | None = None) -> bytes:
    """The four pages of pages_pdf, with a catalog that gives page labels."""

    import re as _re
    pdf = pages_pdf()
    objects = {}
    for match in _re.finditer(rb"(\d+) 0 obj\n(.*?)\nendobj\n", pdf, _re.S):
        objects[int(match.group(1))] = match.group(2)
    objects[1] = b"<< /Type /Catalog /Pages 2 0 R /PageLabels " + labels + b" >>"
    objects.update(extra or {})
    return write_pdf(objects)


def _page_labels(reader: Reader, pdf: bytes) -> tuple[list[bytes], list[str]]:
    """The labels each page's start shows, and the page list's titles."""

    assert reader.open(pdf) == OK
    contents = [title for _, title, _ in _contents(reader)]
    for part in range(reader.call("PD-PARTS")[0]):
        assert reader.read(part) == OK
    starts = [b["text"] for b in reader.blocks() if b["kind"] == PAGE]
    assert reader.close() == 0
    return starts, contents


@pytest.mark.parametrize(("labels", "extra", "expected"), (
    (b"<< /Nums [0 << /S /r >> 2 << /S /D >> 3 << /P (A-) /S /D /St 3 >> ] >>", None,
     ["i", "ii", "1", "A-3"]),
    (b"<< /Nums [0 << /S /R /St 1994 >> 1 << /S /a /St 27 >> 2 << /P (Cover) >> "
     b"3 << /S /A /St 53 >> ] >>", None, ["MCMXCIV", "aa", "Cover", "AAA"]),
    (b"40 0 R", {40: b"<< /Kids [41 0 R 42 0 R] >>",
                 41: b"<< /Limits [0 1] /Nums [0 << /S /A >>] >>",
                 42: b"<< /Limits [2 3] /Nums [2 << /S /r /St 4 >>] >>"},
     ["A", "B", "iv", "v"]),
    (b"<< /Nums [1 << /S /D /St 10 >>] >>", None, ["1", "10", "11", "12"]),
))
def test_pages_show_the_labels_the_file_gives(reader, labels, extra, expected):
    """A page's start, and its entry in a file's page list, show the label
    the file's /PageLabels give it: decimal, roman or letters, from the
    range's start, after its prefix, through a tree with kids too; a page
    before every range shows its number."""

    starts, contents = _page_labels(reader, _labelled(labels, extra))
    assert starts == [label.encode() for label in expected]
    assert contents == [f"Page {label}" for label in expected]
