#!/usr/bin/env python3
"""Akashic pdf/crypt.f with pdf/file.f: PDF files encrypted by the
standard security handler, opened with the empty password.

qpdf encrypts one file in each way the handler reads: RC4 of 40 bits
(revision 2), of 128 bits (revision 3), through crypt filters (revision
4), with the metadata left in the clear, and with object streams; AES of
128 bits (revision 4's /AESV2), and of 256 bits (/AESV3) in revisions 5
and 6.  Each must give back its page's content and its information's
title, decrypted, and an empty string as empty.  The content stream read
in pieces of any size, through PDF-RAW-READ, gives back the bytes qpdf
stored before encrypting them.  Files with a user password open locked:
their streams cannot be read.  Every byte is given back.
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
        6: b"<< /Title (" + TITLE.replace(b"(", b"\\(").replace(b")", b"\\)") + b") /Subject () >>",
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
CREATE PF-RAWS PDF-RAW-SIZE 7 + ALLOT  : PF-RAW  PF-RAWS 7 + -8 AND ;
65536 XBUF PF-OUT
VARIABLE PF-OUT-U
\\ Stream OBJ's stored bytes, read in pieces of N, into PF-OUT.
: PF-RAW-ALL  ( obj n -- status u )
    >R PF-FILE PF-RAW PDF-RAW-START ?DUP IF R> DROP 0 EXIT THEN
    0 PF-OUT-U !
    BEGIN
        PF-OUT PF-OUT-U @ + R@ PF-RAW PDF-RAW-READ
        ?DUP IF NIP R> DROP PF-OUT-U @ EXIT THEN
        DUP PF-OUT-U +!
    0= UNTIL
    R> DROP 0 PF-OUT-U @ ;
""", source_name="crypt-test")
    return file


def ref(value: bytes, key: bytes) -> int:
    """The number of the reference a dictionary's KEY holds."""

    return int(re.search(rb"/" + key + rb"\s*\[?\s*(\d+) 0 R", value).group(1))


def dictionary(pdf_file: File, num: int) -> bytes:
    status, value, kind, _ = pdf_file.object(num)
    assert (status, kind) == (OK, DICT), num
    return value


def info_string(pdf_file: File, key: bytes) -> bytes:
    info, kind = pdf_file.trailer(b"Info")
    obj, status = pdf_file.get(int(info.split()[0]))
    assert status == OK
    pdf_file.runtime.memory.write_bytes(pdf_file.key, key)
    va, vu, vtype = pdf_file.call("PDF-DICT@", pdf_file.key, len(key), *pdf_file.call("PDF-OBJ-VALUE", obj)[:2])
    a, u = pdf_file.call("PF-STRING", va, vu, vtype)
    text = pdf_file.read(a, u)
    pdf_file.call("PDF-OBJ-FREE", obj, pdf_file.file)
    return text


def title(pdf_file: File) -> bytes:
    return info_string(pdf_file, b"Title")


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


AES = (("128", "--use-aes=y"), ("256",), ("256", "--force-R5"))


@pytest.mark.parametrize("options", AES)
def test_aes_files_open_with_the_empty_password(pdf_file, tmp_path, options):
    assert pdf_file.open(encrypt(tmp_path, *options)) == OK
    assert pdf_file.call("PF-LOCKED") == (0,)
    assert content(pdf_file) == (OK, CONTENT)
    assert title(pdf_file) == PLAIN_TITLE
    # An empty string is its IV and one block of padding alone.
    assert info_string(pdf_file, b"Subject") == b""
    assert pdf_file.close() == 0


def test_an_aes_file_with_object_streams(pdf_file, tmp_path):
    pdf = encrypt(tmp_path, "256", general=("--object-streams=generate",))
    assert pdf_file.open(pdf) == OK
    assert pdf_file.call("PF-LOCKED") == (0,)
    assert content(pdf_file) == (OK, CONTENT)
    assert title(pdf_file) == PLAIN_TITLE
    assert pdf_file.close() == 0


@pytest.mark.parametrize("options", (("128", "--use-aes=n"), *AES))
def test_streams_read_in_pieces_of_any_size(pdf_file, tmp_path, options):
    """Whole blocks, part blocks, one byte at a time, and more than all: the
    stored bytes come back the same, their padding gone."""

    assert pdf_file.open(encrypt(tmp_path, *options)) == OK
    obj, status = pdf_file.get(content_object(pdf_file))
    assert status == OK
    out = pdf_file.word("PF-OUT")
    pieces = []
    for piece in (1, 7, 15, 16, 17, 33, 4096):
        status, u = pdf_file.call("PF-RAW-ALL", obj, piece)
        assert status == OK, piece
        pieces.append(pdf_file.read(out, u))
    assert all(piece == pieces[0] for piece in pieces)
    assert zlib.decompress(pieces[0]) == CONTENT
    pdf_file.call("PDF-OBJ-FREE", obj, pdf_file.file)
    assert pdf_file.close() == 0


@pytest.mark.parametrize("options", (("128", "--use-aes=n"), *AES))
def test_files_with_a_user_password_are_locked(pdf_file, tmp_path, options):
    user = "secret"
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
