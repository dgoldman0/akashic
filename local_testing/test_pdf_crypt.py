#!/usr/bin/env python3
"""Akashic pdf/crypt.f with pdf/file.f: PDF files encrypted by the
standard security handler, opened with the empty password.

qpdf encrypts one file in each way the handler reads: RC4 of 40 bits
(revision 2), of 128 bits (revision 3), through crypt filters (revision
4), with the metadata left in the clear, and with object streams.  Each
must give back its page's content and its information's title, decrypted.
qpdf's AES of 128 and 256 bits, and a file with a user password, open
locked: their streams cannot be read.  Every byte is given back.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import zlib
from pathlib import Path

import pytest

from test_pdf_file import CONTENT, File, stream_object, write_pdf

OK, MEMORY, DAMAGED, UNSUPPORTED, READ, MISSING, LOCKED = range(7)
DICT, STRING, HEX = 7, 4, 5
TRUE = (1 << 64) - 1

pytestmark = pytest.mark.skipif(shutil.which("qpdf") is None, reason="qpdf is not installed")

TITLE = b"A title, (with parentheses) and \\\\ a backslash"
PLAIN_TITLE = b"A title, (with parentheses) and \\ a backslash"


def source() -> bytes:
    return write_pdf({
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
           b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        4: stream_object(zlib.compress(CONTENT), b"/Filter /FlateDecode"),
        5: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        6: b"<< /Title (" + TITLE.replace(b"(", b"\\(").replace(b")", b"\\)") + b") >>",
    }, extra_trailer=b"/Info 6 0 R ")


def encrypt(tmp: Path, *options: str, user: str = "", general: tuple[str, ...] = ()) -> bytes:
    (tmp / "in.pdf").write_bytes(source())
    subprocess.run(["qpdf", "--allow-weak-crypto", *general, "--encrypt", user, "owner", *options,
                    "--", str(tmp / "in.pdf"), str(tmp / "out.pdf")], check=True, capture_output=True)
    return (tmp / "out.pdf").read_bytes()


@pytest.fixture(scope="module")
def pdf_file():
    file = File()
    file.runtime.evaluate(b"""
CREATE PF-STR 256 ALLOT
: PF-LOCKED  ( -- flag )  PF-FILE PDF-FILE-LOCKED? ;
: PF-STRING  ( va vu type -- a u )  PF-STR 256 PDF-STRING PF-STR SWAP ;
""", source_name="crypt-test")
    return file


def ref(value: bytes, key: bytes) -> int:
    """The number of the reference a dictionary's KEY holds."""

    return int(re.search(rb"/" + key + rb"\s*\[?\s*(\d+) 0 R", value).group(1))


def dictionary(pdf_file: File, num: int) -> bytes:
    status, value, kind, _ = pdf_file.object(num)
    assert (status, kind) == (OK, DICT), num
    return value


def title(pdf_file: File) -> bytes:
    info, kind = pdf_file.trailer(b"Info")
    obj, status = pdf_file.get(int(info.split()[0]))
    assert status == OK
    pdf_file.runtime.memory.write_bytes(pdf_file.key, b"Title")
    va, vu, vtype = pdf_file.call("PDF-DICT@", pdf_file.key, 5, *pdf_file.call("PDF-OBJ-VALUE", obj)[:2])
    a, u = pdf_file.call("PF-STRING", va, vu, vtype)
    text = pdf_file.read(a, u)
    pdf_file.call("PDF-OBJ-FREE", obj, pdf_file.file)
    return text


def content_object(pdf_file: File) -> int:
    root, _ = pdf_file.trailer(b"Root")
    pages = ref(dictionary(pdf_file, int(root.split()[0])), b"Pages")
    page = ref(dictionary(pdf_file, pages), b"Kids")
    return ref(dictionary(pdf_file, page), b"Contents")


def content(pdf_file: File) -> tuple[int, bytes]:
    return pdf_file.stream(content_object(pdf_file))


@pytest.mark.parametrize("options", (
    ("40",), ("128", "--use-aes=n"), ("128", "--use-aes=n", "--force-V4"),
    ("128", "--use-aes=n", "--force-V4", "--cleartext-metadata"),
))
def test_rc4_files_open_with_the_empty_password(pdf_file, tmp_path, options):
    assert pdf_file.open(encrypt(tmp_path, *options)) == OK
    assert pdf_file.call("PF-LOCKED") == (0,)
    assert content(pdf_file) == (OK, CONTENT)
    assert title(pdf_file) == PLAIN_TITLE
    assert pdf_file.close() == 0


def test_an_encrypted_file_with_object_streams(pdf_file, tmp_path):
    pdf = encrypt(tmp_path, "128", "--use-aes=n", general=("--object-streams=generate",))
    assert pdf_file.open(pdf) == OK
    assert pdf_file.call("PF-LOCKED") == (0,)
    assert content(pdf_file) == (OK, CONTENT)
    assert title(pdf_file) == PLAIN_TITLE
    assert pdf_file.close() == 0


@pytest.mark.parametrize("options, user", (
    (("128", "--use-aes=y"), ""), (("256",), ""), (("128", "--use-aes=n"), "secret"),
))
def test_files_it_cannot_open_are_locked(pdf_file, tmp_path, options, user):
    assert pdf_file.open(encrypt(tmp_path, *options, user=user)) == OK
    assert pdf_file.call("PF-LOCKED") == (TRUE,)
    obj, status = pdf_file.get(content_object(pdf_file))
    assert status == OK
    status, a, u = pdf_file.call("PF-DECODE", obj)
    assert status == LOCKED
    pdf_file.call("PF-DECODED-FREE")
    pdf_file.call("PDF-OBJ-FREE", obj, pdf_file.file)
    assert pdf_file.close() == 0


def test_a_file_without_encryption_is_not_locked(pdf_file):
    assert pdf_file.open(source()) == OK
    assert pdf_file.call("PF-LOCKED") == (0,)
    assert title(pdf_file) == PLAIN_TITLE
    assert pdf_file.close() == 0
