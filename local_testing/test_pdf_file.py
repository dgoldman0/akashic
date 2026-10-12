#!/usr/bin/env python3
"""Akashic pdf/file.f: a PDF file's objects, read as they are asked for.

Files are written here by hand with exact offsets, then rewritten by qpdf
into the other shapes a reader meets: cross-reference streams with object
streams, linearized files with two sections, and uncompressed tables.  An
incremental update is appended by hand.  Each object is read through
PDF-GET and checked against what was written; stream data is decoded through
its filters; a /Length that is a reference or wrong, a missing object, and a
damaged cross-reference are checked too.  Every byte the file takes is given
back when it closes.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import zlib
from pathlib import Path

import pytest

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, DAMAGED, UNSUPPORTED, READ, MISSING = range(6)
END, INT, REAL, NAME, STRING, HEX, ARRAY, DICT, KEYWORD, REF = range(10)
FILE_BYTES = 4 << 20

PRELUDE = f"""
{FILE_BYTES} XBUF PF-BYTES
65536 XBUF PF-KEY
CREATE PF-SRCS MEDSRC-SIZE 7 + ALLOT  : PF-SRC  PF-SRCS 7 + -8 AND ;
CREATE PF-MSRCS MSRC-SIZE 7 + ALLOT  : PF-MSRC  PF-MSRCS 7 + -8 AND ;
CREATE PF-FILES PDF-FILE-SIZE 7 + ALLOT  : PF-FILE  PF-FILES 7 + -8 AND ;
CREATE PF-BUFS PDF-BUF-SIZE 7 + ALLOT  : PF-BUF  PF-BUFS 7 + -8 AND ;
: PF-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: PF-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: PF-OPEN  ( u -- status )
    PF-BYTES SWAP PF-SRC MEDSRC-MEMORY
    ['] PF-ALLOC ['] PF-FREE 0 0 PF-MSRC MSRC-INIT
    PF-SRC PF-MSRC PF-FILE PDF-OPEN ;
: PF-CLOSE  ( -- held )  PF-FILE PDF-CLOSE  PF-MSRC MSRC-HELD@ ;
: PF-DECODE  ( obj -- status a u )
    PF-BUF PF-FILE PDF-STREAM PF-BUF PDF-BUF.A @ PF-BUF PDF-BUF.U @ ;
: PF-DECODED-FREE  ( -- )  PF-BUF PF-MSRC PDF-BUF-FREE ;
"""


class File:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=64 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/file.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-file",
                              step_budget=200_000_000)
        self.runtime.drain_uart_output()
        self.bytes = self.word("PF-BYTES")
        self.key = self.word("PF-KEY")
        self.file = self.word("PF-FILE")

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

    def open(self, pdf: bytes) -> int:
        assert len(pdf) <= FILE_BYTES
        self.runtime.memory.write_bytes(self.bytes, pdf)
        return self.call("PF-OPEN", len(pdf))[0]

    def close(self) -> int:
        return self.call("PF-CLOSE")[0]

    def read(self, a: int, u: int) -> bytes:
        return self.runtime.memory.read_bytes(a, u)

    def get(self, num: int) -> tuple[int, int]:
        return self.call("PDF-GET", num, self.file)

    def value(self, obj: int) -> tuple[bytes, int]:
        a, u, kind = self.call("PDF-OBJ-VALUE", obj)
        return self.read(a, u), kind

    def object(self, num: int) -> tuple[int, bytes, int, bool]:
        """Status, value bytes, type and whether it is a stream; freed."""

        obj, status = self.get(num)
        if status != OK:
            return status, b"", END, False
        text, kind = self.value(obj)
        (stream,) = self.call("PDF-OBJ-STREAM?", obj)
        self.call("PDF-OBJ-FREE", obj, self.file)
        return status, text, kind, bool(stream)

    def stream(self, num: int) -> tuple[int, bytes]:
        obj, status = self.get(num)
        assert status == OK, status
        status, a, u = self.call("PF-DECODE", obj)
        data = self.read(a, u) if a else b""
        self.call("PF-DECODED-FREE")
        self.call("PDF-OBJ-FREE", obj, self.file)
        return status, data

    def trailer(self, key: bytes) -> tuple[bytes, int]:
        self.runtime.memory.write_bytes(self.key, key)
        a, u, kind = self.call("PDF-TRAILER@", self.key, len(key), self.file)
        return (self.read(a, u) if kind != END else b""), kind


@pytest.fixture(scope="module")
def pdf_file():
    return File()


CONTENT = b"BT /F1 24 Tf 72 700 Td (Hello, world) Tj ET\n" * 20


def write_pdf(objects: dict[int, bytes], root: int = 1, *, extra_trailer: bytes = b"",
              header: bytes = b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n") -> bytes:
    """A PDF of OBJECTS, each "N 0 obj ... endobj", with an exact table."""

    out = bytearray(header)
    offsets = {}
    for num in sorted(objects):
        offsets[num] = len(out)
        out += b"%d 0 obj\n" % num + objects[num] + b"\nendobj\n"
    size = max(objects) + 1
    xref = len(out)
    out += b"xref\n0 %d\n" % size
    out += b"0000000000 65535 f\r\n"
    for num in range(1, size):
        if num in offsets:
            out += b"%010d 00000 n\r\n" % offsets[num]
        else:
            out += b"0000000000 00000 f\r\n"
    out += (b"trailer\n<< /Size %d /Root %d 0 R " % (size, root)) + extra_trailer + b">>\n"
    out += b"startxref\n%d\n%%%%EOF\n" % xref
    return bytes(out)


def stream_object(data: bytes, dictionary: bytes = b"", *, length: bytes | None = None) -> bytes:
    length = b"%d" % len(data) if length is None else length
    return b"<< /Length " + length + b" " + dictionary + b" >>\nstream\n" + data + b"\nendstream"


def simple_objects() -> dict[int, bytes]:
    return {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
           b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        4: stream_object(zlib.compress(CONTENT), b"/Filter /FlateDecode"),
        5: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        6: b"(a string \\(with\\) escapes)",
        7: b"[1 2.5 /Name (str) <414243> << /K 8 0 R >> null true]",
    }


def test_a_table_and_its_objects(pdf_file):
    objects = simple_objects()
    assert pdf_file.open(write_pdf(objects)) == OK
    assert pdf_file.trailer(b"Root") == (b"1 0 R", REF)
    assert pdf_file.call("PDF-OBJECT-COUNT", pdf_file.file) == (8,)
    for num, text in objects.items():
        status, value, kind, stream = pdf_file.object(num)
        assert status == OK, num
        if num == 4:
            assert stream and kind == DICT and value.startswith(b"<< /Length")
        else:
            assert (value, stream) == (text, False), num
    assert pdf_file.stream(4) == (OK, CONTENT)
    assert pdf_file.object(0)[0] == MISSING
    assert pdf_file.object(8)[0] == MISSING
    assert pdf_file.object(99)[0] == MISSING
    assert pdf_file.close() == 0


def test_resolving_a_reference(pdf_file):
    assert pdf_file.open(write_pdf(simple_objects())) == OK
    pdf_file.runtime.memory.write_bytes(pdf_file.key, b"2 0 R")
    obj, a, u, kind, status = pdf_file.call("PDF-RESOLVE", pdf_file.key, 5, REF, pdf_file.file)
    assert (status, kind) == (OK, DICT) and obj
    assert pdf_file.read(a, u) == b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    pdf_file.call("PDF-OBJ-FREE", obj, pdf_file.file)
    pdf_file.runtime.memory.write_bytes(pdf_file.key, b"/Plain")
    assert pdf_file.call("PDF-RESOLVE", pdf_file.key, 6, NAME, pdf_file.file) == (
        0, pdf_file.key, 6, NAME, OK)
    assert pdf_file.close() == 0


def test_a_length_that_is_a_reference_or_wrong(pdf_file):
    objects = simple_objects()
    objects[4] = stream_object(CONTENT, length=b"9 0 R")
    objects[9] = b"%d" % len(CONTENT)
    assert pdf_file.open(write_pdf(objects)) == OK
    assert pdf_file.stream(4) == (OK, CONTENT)
    assert pdf_file.close() == 0
    for wrong in (len(CONTENT) - 7, len(CONTENT) + 5, 0):
        objects = simple_objects()
        objects[4] = stream_object(CONTENT, length=b"%d" % wrong)
        assert pdf_file.open(write_pdf(objects)) == OK
        assert pdf_file.stream(4) == (OK, CONTENT), wrong
        assert pdf_file.close() == 0


def qpdf(pdf: bytes, *options: str, tmp: Path) -> bytes:
    source, target = tmp / "in.pdf", tmp / "out.pdf"
    source.write_bytes(pdf)
    subprocess.run(["qpdf", *options, str(source), str(target)], check=True)
    return target.read_bytes()


needs_qpdf = pytest.mark.skipif(shutil.which("qpdf") is None, reason="qpdf is not installed")


def many_objects() -> dict[int, bytes]:
    objects = simple_objects()
    for num in range(10, 60):
        objects[num] = b"<< /Index %d /Name /Object%d /Text (object %d) >>" % (num, num, num)
    objects[1] = b"<< /Type /Catalog /Pages 2 0 R /Extra [" + b" ".join(
        b"%d 0 R" % num for num in range(10, 60)) + b"] >>"
    return objects


def read_back(pdf_file: File, pdf: bytes) -> dict[int, bytes]:
    """Every object's value, by number, as the file reads them."""

    assert pdf_file.open(pdf) == OK
    (count,) = pdf_file.call("PDF-OBJECT-COUNT", pdf_file.file)
    found = {}
    for num in range(1, count):
        status, value, _, _ = pdf_file.object(num)
        if status == OK:
            found[num] = value
    return found


@needs_qpdf
@pytest.mark.parametrize("options", (
    ("--object-streams=generate",),
    ("--object-streams=generate", "--compress-streams=y"),
    ("--linearize",),
    ("--qdf", "--object-streams=disable"),
))
def test_files_qpdf_writes(pdf_file, tmp_path, options):
    pdf = qpdf(write_pdf(many_objects()), *options, tmp=tmp_path)
    found = read_back(pdf_file, pdf)
    # qpdf renumbers objects: find each by its own text.
    texts = [value for value in found.values()]
    for num in range(10, 60):
        assert any(b"/Name /Object%d" % num in text for text in texts), num
    catalogs = [num for num, text in found.items() if b"/Catalog" in text]
    assert len(catalogs) == 1
    root, kind = pdf_file.trailer(b"Root")
    assert kind == REF and int(root.split()[0]) == catalogs[0]
    contents = [num for num, text in found.items() if b"/Length" in text
                and b"/Type" not in text]
    assert contents
    assert any(pdf_file.stream(num) == (OK, CONTENT) for num in contents)
    assert pdf_file.close() == 0


@needs_qpdf
def test_an_object_stream_s_objects_cross_the_held_stream(pdf_file, tmp_path):
    pdf = qpdf(write_pdf(many_objects()), "--object-streams=generate",
               "--qdf", tmp=tmp_path)
    assert b"/ObjStm" in pdf
    found = read_back(pdf_file, pdf)
    assert sum(b"/Name /Object" in text for text in found.values()) == 50
    assert pdf_file.close() == 0


def test_an_incremental_update_stands_over_the_original(pdf_file):
    base = write_pdf(simple_objects())
    start = re.search(rb"startxref\n(\d+)", base)
    prev = int(start.group(1))
    update = bytearray(base)
    offset5 = len(update)
    update += b"5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n"
    offset8 = len(update)
    update += b"8 0 obj\n(added)\nendobj\n"
    xref = len(update)
    update += b"xref\n5 1\n%010d 00000 n\r\n8 1\n%010d 00000 n\r\n" % (offset5, offset8)
    update += b"7 1\n0000000000 00001 f\r\n"
    update += b"trailer\n<< /Size 9 /Root 1 0 R /Prev %d >>\nstartxref\n%d\n%%%%EOF\n" % (
        prev, xref)
    assert pdf_file.open(bytes(update)) == OK
    assert pdf_file.object(5)[1] == b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"
    assert pdf_file.object(8)[1] == b"(added)"
    assert pdf_file.object(7)[0] == MISSING
    assert pdf_file.object(2)[1] == b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    assert pdf_file.close() == 0


def test_a_damaged_cross_reference_is_repaired_by_scanning(pdf_file):
    objects = simple_objects()
    pdf = write_pdf(objects)
    for broken in (pdf.replace(b"startxref", b"startxrex"),
                   pdf.replace(b"trailer", b"trailor"),
                   pdf[:pdf.index(b"xref\n0")] + b"trailer << /Root 1 0 R >>\n%%EOF\n"):
        assert pdf_file.open(broken) == OK
        assert pdf_file.call("PDF-REPAIRED?", pdf_file.file)[0]
        assert pdf_file.object(2)[1] == objects[2]
        assert pdf_file.stream(4) == (OK, CONTENT)
        assert pdf_file.close() == 0


def test_objects_moved_from_their_entries_are_found_by_scanning(pdf_file):
    objects = simple_objects()
    pdf = write_pdf(objects)
    # The objects move but the table's own offset stays right.
    pad = b"% padding moved me\n"
    shifted = pdf.replace(b"1 0 obj", pad + b"1 0 obj", 1)
    xref = int(re.search(rb"startxref\n(\d+)", pdf).group(1))
    shifted = shifted.replace(b"startxref\n%d" % xref, b"startxref\n%d" % (xref + len(pad)))
    assert pdf_file.open(shifted) == OK
    assert not pdf_file.call("PDF-REPAIRED?", pdf_file.file)[0]
    assert pdf_file.object(3)[1] == objects[3]
    assert pdf_file.call("PDF-REPAIRED?", pdf_file.file)[0]
    assert pdf_file.object(5)[1] == objects[5]
    assert pdf_file.close() == 0


@needs_qpdf
def test_a_file_with_no_trailer_finds_its_catalog(pdf_file, tmp_path):
    pdf = qpdf(write_pdf(many_objects()), "--object-streams=generate", tmp=tmp_path)
    # No startxref: the cross-reference stream is never read, so the catalog,
    # which lies in an object stream, must be found there.
    broken = pdf.replace(b"startxref", b"startxrex")
    assert pdf_file.open(broken) == OK
    root, kind = pdf_file.trailer(b"Root")
    assert kind == REF
    status, value, _, _ = pdf_file.object(int(root.split()[0]))
    assert status == OK and b"/Catalog" in value
    found = read_back(pdf_file, broken)
    assert sum(b"/Name /Object" in text for text in found.values()) == 50
    assert pdf_file.close() == 0


def test_nothing_to_find(pdf_file):
    assert pdf_file.open(b"%PDF-1.7\nnothing here\n") == DAMAGED
    assert pdf_file.close() == 0
    assert pdf_file.open(b"") == DAMAGED
    assert pdf_file.close() == 0
