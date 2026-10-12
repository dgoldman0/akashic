#!/usr/bin/env python3
"""Akashic pdf/page.f: a PDF's page tree, what each page inherits, and a
page's content.

Trees are written by hand: a flat one of thirty pages read in order,
which takes the remembered place, and out of order, which walks down
from the root; a nested one whose pages inherit resources (inline in a
node, or a reference), media boxes, crop boxes and rotations; content as
one stream, an array, a reference to an array, missing, and damaged;
a tree that loops; a root that is itself the page; and kids that are
missing or no reference.  qpdf's object streams and linearized files,
and a document xelatex wrote, are read too.  Every byte is given back.
"""

from __future__ import annotations

import random
import shutil
import subprocess
import zlib
from pathlib import Path

import pytest

from forth_dependencies import dependency_order
from test_pdf_file import stream_object, write_pdf
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, DAMAGED, UNSUPPORTED, READ, MISSING = range(6)
END, INT, REAL, NAME, STRING, HEX, ARRAY, DICT = range(8)
FILE_BYTES = 4 << 20
LETTER = (0, 0, 612 << 16, 792 << 16)
A4 = (0, 0, 595 << 16, 842 << 16)

PRELUDE = f"""
{FILE_BYTES} XBUF PG-BYTES
CREATE PG-SRCS MEDSRC-SIZE 7 + ALLOT  : PG-SRC  PG-SRCS 7 + -8 AND ;
CREATE PG-MSRCS MSRC-SIZE 7 + ALLOT  : PG-MSRC  PG-MSRCS 7 + -8 AND ;
CREATE PG-FILES PDF-FILE-SIZE 7 + ALLOT  : PG-FILE  PG-FILES 7 + -8 AND ;
CREATE PG-PAGES PDF-PAGE-SIZE 7 + ALLOT  : PG-PAGE  PG-PAGES 7 + -8 AND ;
CREATE PG-BUFS PDF-BUF-SIZE 7 + ALLOT  : PG-BUF  PG-BUFS 7 + -8 AND ;
: PG-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: PG-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: PG-OPEN  ( u -- status )
    PG-BYTES SWAP PG-SRC MEDSRC-MEMORY
    ['] PG-ALLOC ['] PG-FREE 0 0 PG-MSRC MSRC-INIT
    PG-PAGE PDF-PAGE-SIZE 0 FILL
    PG-SRC PG-MSRC PG-FILE PDF-OPEN ;
: PG-CLOSE  ( -- held )  PG-PAGE PDF-PAGE-END PG-FILE PDF-CLOSE PG-MSRC MSRC-HELD@ ;
: PG-COUNT  ( -- n status )  PG-FILE PDF-PAGE-COUNT ;
: PG-AT  ( i -- status )  PG-FILE PG-PAGE PDF-PAGE-OPEN ;
: PG-FORGET  ( -- )  PG-PAGE PDF-PAGE-END ;
: PG-FACTS  ( -- num ra ru rtype x0 y0 x1 y1 rotate )
    PG-PAGE PDF-PAGE-NUM  PG-PAGE PDF-PAGE-RESOURCES
    PG-PAGE PDF-PAGE-BOX  PG-PAGE PDF-PAGE-ROTATE ;
: PG-CONTENTS  ( -- status a u )
    PG-BUF PDF-BUF-SIZE 0 FILL  PG-PAGE PG-BUF PDF-PAGE-CONTENTS
    PG-BUF PDF-BUF.A @ PG-BUF PDF-BUF.U @ ;
: PG-CONTENTS-FREE  ( -- )  PG-BUF PG-MSRC PDF-BUF-FREE ;
: PG-HELD  ( -- held )  PG-MSRC MSRC-HELD@ ;
"""


class Pages:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=64 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/page.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-page",
                              step_budget=200_000_000)
        self.runtime.drain_uart_output()
        self.bytes = self.word("PG-BYTES")
        self.steps = 0

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0, stack.snapshot()
        for value in args:
            stack.push(value)
        self.steps = self.runtime.execute(name, step_budget=4_000_000_000).semantic_steps
        result = tuple(stack.snapshot())
        while stack.depth():
            stack.pop()
        return result

    def open(self, pdf: bytes) -> int:
        assert len(pdf) <= FILE_BYTES
        self.runtime.memory.write_bytes(self.bytes, pdf)
        return self.call("PG-OPEN", len(pdf))[0]

    def close(self) -> int:
        return self.call("PG-CLOSE")[0]

    def count(self) -> tuple[int, int]:
        return self.call("PG-COUNT")

    def page(self, index: int) -> int:
        return self.call("PG-AT", index)[0]

    def facts(self) -> tuple[int, bytes, int, tuple[int, ...], int]:
        num, ra, ru, rtype, x0, y0, x1, y1, rotate = self.call("PG-FACTS")
        resources = self.runtime.memory.read_bytes(ra, ru) if rtype != END else b""
        return num, resources, rtype, (x0, y0, x1, y1), rotate

    def contents(self) -> tuple[int, bytes]:
        status, a, u = self.call("PG-CONTENTS")
        data = self.runtime.memory.read_bytes(a, u) if a else b""
        self.call("PG-CONTENTS-FREE")
        return status, data


@pytest.fixture(scope="module")
def pages():
    return Pages()


def content(index: int) -> bytes:
    return b"BT /F1 12 Tf 72 700 Td (page %d) Tj ET" % index


def flat(count: int) -> dict[int, bytes]:
    """Catalog 1, root 2, page i as object 3 + 2i with its content next."""

    kids = b" ".join(b"%d 0 R" % (3 + 2 * i) for i in range(count))
    objects = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [" + kids + b"] /Count %d /MediaBox [0 0 612 792] >>" % count,
    }
    for i in range(count):
        objects[3 + 2 * i] = b"<< /Type /Page /Parent 2 0 R /Contents %d 0 R >>" % (4 + 2 * i)
        objects[4 + 2 * i] = stream_object(content(i))
    return objects


def test_flat_tree_in_order_and_out_of_order(pages):
    assert pages.open(write_pdf(flat(30))) == OK
    assert pages.count() == (30, OK)
    for i in range(30):
        assert pages.page(i) == OK, i
        num, resources, rtype, box, rotate = pages.facts()
        assert (num, rtype, box, rotate) == (3 + 2 * i, END, LETTER, 0)
        assert pages.contents() == (OK, content(i) + b"\n")
    order = list(range(30))
    random.Random(7).shuffle(order)
    for i in order:
        assert pages.page(i) == OK
        assert pages.facts()[0] == 3 + 2 * i
    assert pages.page(30) == MISSING
    assert pages.page(10**6) == MISSING
    assert pages.close() == 0


def test_the_next_page_opens_from_where_the_last_lay(pages):
    assert pages.open(write_pdf(flat(200))) == OK
    assert pages.page(150) == OK
    assert pages.page(151) == OK
    after = pages.steps
    assert pages.facts()[0] == 3 + 2 * 151
    pages.call("PG-FORGET")
    assert pages.page(151) == OK
    fresh = pages.steps
    assert pages.facts()[0] == 3 + 2 * 151
    assert after * 10 < fresh, (after, fresh)
    assert pages.close() == 0


def nested() -> dict[int, bytes]:
    return {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 5 /Rotate 90 "
           b"/Resources << /Font << /F1 20 0 R >> >> /MediaBox [0 0 612 792] >>",
        3: b"<< /Type /Pages /Parent 2 0 R /Kids [5 0 R 6 0 R] /Count 2 "
           b"/MediaBox [0 0 595 842] /Resources 21 0 R >>",
        4: b"<< /Type /Pages /Parent 2 0 R /Kids [7 0 R 8 0 R 9 0 R] /Count 3 /Rotate -90 >>",
        5: b"<< /Type /Page /Parent 3 0 R /Contents 10 0 R >>",
        6: b"<< /Type /Page /Parent 3 0 R /CropBox [10 10.5 600 1000] /Rotate 450 "
           b"/Contents [10 0 R 11 0 R] >>",
        7: b"<< /Type /Page /Parent 4 0 R /Contents 12 0 R >>",
        8: b"<< /Type /Page /Parent 4 0 R /Resources << /XObject << >> >> "
           b"/MediaBox [612 792 0 0] /CropBox [700 700 800 800] /Contents [] >>",
        9: b"<< /Type /Page /Parent 4 0 R >>",
        10: stream_object(zlib.compress(b"(one) Tj"), b"/Filter /FlateDecode"),
        11: stream_object(b"(two) Tj"),
        12: b"[11 0 R 10 0 R]",
        20: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        21: b"<< /Font << /F2 20 0 R >> >>",
    }


def test_pages_inherit_from_their_nodes(pages):
    assert pages.open(write_pdf(nested())) == OK
    assert pages.count() == (5, OK)
    font = b"<< /Font << /F1 20 0 R >> >>"
    expected = [
        (5, b"<< /Font << /F2 20 0 R >> >>", A4, 90, b"(one) Tj\n"),
        (6, b"<< /Font << /F2 20 0 R >> >>", (10 << 16, 10 << 16 | 0x8000, 595 << 16, 842 << 16), 90,
         b"(one) Tj\n(two) Tj\n"),
        (7, font, LETTER, 270, b"(two) Tj\n(one) Tj\n"),
        (8, b"<< /XObject << >> >>", LETTER, 270, b""),
        (9, font, LETTER, 270, b""),
    ]
    for index in (0, 1, 2, 3, 4, 2, 0, 4):
        num, resources, box, rotate, text = expected[index]
        assert pages.page(index) == OK
        assert pages.facts() == (num, resources, DICT, box, rotate), index
        assert pages.contents() == (OK, text), index
    assert pages.page(5) == MISSING
    assert pages.close() == 0


def test_damaged_content_keeps_what_it_can(pages):
    objects = nested()
    text = b"".join(b"(part %d) Tj " % i for i in range(400))
    whole = zlib.compress(text)
    objects[10] = stream_object(whole[: len(whole) // 2], b"/Filter /FlateDecode")
    assert pages.open(write_pdf(objects)) == OK
    assert pages.page(1) == OK
    status, data = pages.contents()
    assert status == DAMAGED
    first, rest = data.split(b"\n", 1)
    assert 0 < len(first) < len(text) and text.startswith(first)
    assert rest == b"(two) Tj\n"
    assert pages.close() == 0


def test_a_tree_that_loops_ends(pages):
    objects = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 5 >>",
        3: b"<< /Type /Pages /Kids [2 0 R] /Count 5 >>",
    }
    assert pages.open(write_pdf(objects)) == OK
    assert pages.page(0) == DAMAGED
    assert pages.close() == 0


def test_a_root_that_is_the_page_and_kids_that_are_not(pages):
    objects = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Page /MediaBox [0 0 595 842] /Contents 3 0 R >>",
        3: stream_object(b"(alone) Tj"),
    }
    assert pages.open(write_pdf(objects)) == OK
    assert pages.count() == (1, OK)
    assert pages.page(0) == OK
    assert pages.facts()[0] == 2 and pages.facts()[3] == A4
    assert pages.contents() == (OK, b"(alone) Tj\n")
    assert pages.page(1) == MISSING
    assert pages.close() == 0
    objects = flat(3)
    objects[2] = (b"<< /Type /Pages /Kids [99 0 R 3 0 R /Junk 5 0 R << /Type /Page >> 7 0 R] "
                  b"/Count 3 >>")
    assert pages.open(write_pdf(objects)) == OK
    assert [pages.page(i) for i in range(4)] == [OK, OK, OK, MISSING]
    assert pages.close() == 0


def test_a_file_with_no_pages(pages):
    objects = {1: b"<< /Type /Catalog >>"}
    assert pages.open(write_pdf(objects)) == OK
    assert pages.count() == (0, DAMAGED)
    assert pages.page(0) == DAMAGED
    assert pages.close() == 0


needs_qpdf = pytest.mark.skipif(shutil.which("qpdf") is None, reason="qpdf is not installed")


def qpdf(pdf: bytes, *options: str, tmp: Path) -> bytes:
    source, target = tmp / "in.pdf", tmp / "out.pdf"
    source.write_bytes(pdf)
    subprocess.run(["qpdf", *options, str(source), str(target)], check=True)
    return target.read_bytes()


@needs_qpdf
@pytest.mark.parametrize("options", (("--object-streams=generate", "--compress-streams=y"),
                                     ("--linearize",)))
def test_files_qpdf_rewrites(pages, tmp_path, options):
    assert pages.open(qpdf(write_pdf(flat(40)), *options, tmp=tmp_path)) == OK
    assert pages.count() == (40, OK)
    for i in list(range(40)) + [33, 2, 17]:
        assert pages.page(i) == OK
        assert pages.contents() == (OK, content(i) + b"\n"), i
    assert pages.close() == 0


TEX = r"""\documentclass{article}
\usepackage{lipsum}
\begin{document}
\section{One}\lipsum[1-12]
\section{Two}\lipsum[13-30]
\end{document}
"""


@pytest.mark.skipif(shutil.which("xelatex") is None or shutil.which("qpdf") is None,
                    reason="xelatex or qpdf is not installed")
def test_a_document_xelatex_wrote(pages, tmp_path):
    (tmp_path / "doc.tex").write_text(TEX)
    subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                   check=True, capture_output=True)
    pdf = (tmp_path / "doc.pdf").read_bytes()
    count = int(subprocess.run(["qpdf", "--show-npages", str(tmp_path / "doc.pdf")],
                               check=True, capture_output=True, text=True).stdout)
    assert count > 3
    assert pages.open(pdf) == OK
    assert pages.count() == (count, OK)
    for i in range(count):
        assert pages.page(i) == OK
        num, resources, rtype, (x0, y0, x1, y1), rotate = pages.facts()
        assert rtype == DICT and b"/Font" in resources and rotate == 0
        assert x0 == y0 == 0 and x1 > 500 << 16 and y1 > 700 << 16
        status, data = pages.contents()
        assert status == OK and b"TJ" in data and b"Tf" in data
    assert pages.close() == 0
