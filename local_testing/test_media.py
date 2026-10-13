#!/usr/bin/env python3
"""Akashic media/: sources, file kinds, and scaled picture copies.

A picture copy is checked against a Python model of the same integer
arithmetic: the fitted size, the column and row each source pixel goes to,
alpha-weighted averages with the same rounding, and the SHA3-256 of the
result.  Copies run in many small steps and in one, from memory and from a
file in a RAM VFS, and every failure must say why and give back every byte
it took.  Every run checks the data stack is balanced.
"""

from __future__ import annotations

import io
import random
import re
import struct
import zlib

import pytest
from PIL import Image

import qoi_codec
from forth_snapshot import ForthSnapshot, program_output

FILE_BYTES = 1 << 20
OUT_BYTES = 4 << 20

EMPTY, PENDING, READY, FAILED = 0, 1, 2, 3
R_NONE, R_UNSUPPORTED, R_DAMAGED, R_READ, R_MEMORY, R_INVALID = range(6)
BINARY, TEXT, HTML, QOI, PNG, JPEG, GIF, BMP, WAV, MARKDOWN = range(10)

SNAPSHOT = ForthSnapshot(
    ("media/kind.f", "media/picture.f", "media/vfs-source.f"),
    prelude=(
        f"{FILE_BYTES} XBUF MT-FILE",
        f"{OUT_BYTES} XBUF MT-OUT",
        "256 XBUF MT-NAME",
        "VARIABLE MT-PIC     PIC-SIZE ALLOCATE DROP MT-PIC !",
        "VARIABLE MT-MEMSRC  MEDSRC-SIZE ALLOCATE DROP MT-MEMSRC !",
        "VARIABLE MT-VFSSRC  MEDSRC-VFS-SIZE ALLOCATE DROP MT-VFSSRC !",
        "VARIABLE MT-SPAN    MEDSRC-SPAN-SIZE ALLOCATE DROP MT-SPAN !",
        "VARIABLE MT-MSRC    MSRC-SIZE ALLOCATE DROP MT-MSRC !",
        ": MT-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;",
        ": MT-FREE  ( addr bytes ctx -- )  2DROP FREE ;",
        ": MT-MSRC-INIT  ( budget -- )",
        "  >R ['] MT-ALLOC ['] MT-FREE 0 R> MT-MSRC @ MSRC-INIT ;",
        # Step until the copy is no longer pending; leave the steps taken.
        ": MT-RUN  ( budget -- steps state )",
        "  0 BEGIN OVER MT-PIC @ PIC-STEP DUP PIC-ST-PENDING = WHILE",
        "    DROP 1+ REPEAT ROT DROP ;",
        ": MT-SAVE  ( -- )",
        "  MT-PIC @ PIC-PIXELS MT-OUT SWAP MOVE ;",
        ": MT-REPORT  ( -- )",
        '  ." R=" MT-PIC @ PIC-REASON@ .',
        '  ." SIZE=" MT-PIC @ PIC-WIDTH@ . MT-PIC @ PIC-HEIGHT@ .',
        '  ." HELD=" MT-MSRC @ MSRC-HELD@ . ;',
        ": MT-RAM-VFS  ( -- vfs )",
        "  524288 A-XMEM ARENA-NEW IF -1 THROW THEN",
        "  VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;",
    ),
)

_ADDRESSES: dict[str, int] = {}


def _address(name: str) -> int:
    if not _ADDRESSES:
        lines = ["MT-FILE U. MT-OUT U. MT-NAME U."]
        text = program_output(SNAPSHOT.run(lines), lines)
        values = [int(value) for value in re.findall(r"\d+", text)[:3]]
        _ADDRESSES.update(zip(("file", "out", "name"), values))
    return _ADDRESSES[name]


def _run(
    lines: list[str],
    data: bytes = b"",
    *,
    name: bytes = b"",
    out_bytes: int = 0,
) -> tuple[str, bytes, bytes]:
    """Run LINES with DATA at MT-FILE and NAME at MT-NAME.

    Return the output and OUT_BYTES of MT-OUT.
    """

    captured = bytearray()

    def setup(system) -> None:
        if data:
            system._raw_mem_write_span(_address("file"), data)
        if name:
            system._raw_mem_write_span(_address("name"), name)

    def inspect(system) -> None:
        if out_bytes:
            captured.extend(system._raw_mem_read_span(_address("out"), out_bytes))

    lines = lines + ['DEPTH ." @D:" . CR']
    output = program_output(SNAPSHOT.run(lines, setup=setup, inspect=inspect), lines)
    assert "@D:0 " in output, output[-600:]
    return output, bytes(captured)


# --------------------------------------------------------------------------
# Kinds
# --------------------------------------------------------------------------

def _kind(data: bytes, name: bytes = b"file") -> int:
    prefix = data[:512]
    output, _ = _run(
        [f'MT-FILE {len(prefix)} MT-NAME {len(name)} MEDIA-KIND ." K=" .'],
        prefix,
        name=name,
    )
    return int(re.search(r"K=(-?\d+)", output).group(1))


QOI_FILE = qoi_codec.encode([[(1, 2, 3, 255)] * 3] * 2)


@pytest.mark.parametrize(
    ("data", "name", "expected"),
    (
        (QOI_FILE, b"picture.txt", QOI),          # a signature beats the name
        (b"\x89PNG\r\n\x1a\n" + bytes(20), b"a.png", PNG),
        (b"\xff\xd8\xff\xe0" + bytes(20), b"a.jpg", JPEG),
        (b"GIF89a" + bytes(20), b"a.gif", GIF),
        (b"BM" + bytes(12) + struct.pack("<I", 40) + bytes(20), b"a.bmp", BMP),
        (b"BMW is a car.\n", b"notes", TEXT),     # "BM" without a bitmap header
        (b"RIFF" + bytes(4) + b"WAVEfmt " + bytes(20), b"a.wav", WAV),
        (b"plain words\nand lines\n", b"notes", TEXT),
        ("Grüße, 世界".encode() * 60, b"notes", TEXT),   # 512 cuts a character
        (b"", b"empty", TEXT),
        (b"text\x00with a nul", b"notes", BINARY),
        (b"bad \xff byte", b"notes", BINARY),
        (b"\xef\xbb\xbf \n\t<!DOCTYPE HTML><p>hi", b"x", HTML),
        (b"<html><body>hi", b"x", HTML),
        (b"<p>a fragment</p>", b"PAGE.HTM", HTML),
        (b"<p>a fragment</p>", b"page.html", HTML),
        (b"<p>a fragment</p>", b"notes.txt", TEXT),
        (b"# Notes\n", b"README.md", MARKDOWN),
        (b"# Notes\n", b"notes.Markdown", MARKDOWN),
        (b"# Notes\n", b"notes.mdx", TEXT),
        (b"<html><body>hi", b"page.md", HTML),    # a page's opening beats the name
        (QOI_FILE, b"picture.md", QOI),
    ),
)
def test_kind_from_signature_then_text_then_name(data, name, expected) -> None:
    assert _kind(data, name) == expected


def test_kind_names_say_what_a_file_is() -> None:
    lines = [
        f'{kind} MEDIA-KIND-NAME ." [" TYPE ." ]"'
        for kind in (QOI, TEXT, BINARY, WAV, MARKDOWN)
    ]
    output, _ = _run(lines)
    assert "[QOI picture]" in output and "[text]" in output
    assert "[binary data]" in output and "[WAV sound]" in output
    assert "[Markdown document]" in output


# --------------------------------------------------------------------------
# Picture copies
# --------------------------------------------------------------------------

def _fit(sw: int, sh: int, mw: int, mh: int) -> tuple[int, int]:
    if sw <= mw and sh <= mh:
        return sw, sh
    if sw * mh <= sh * mw:
        return max(1, (sw * mh + sh // 2) // sh), mh
    return mw, max(1, (sh * mw + sw // 2) // sw)


def _round(total: int, divisor: int) -> int:
    return (total + divisor // 2) // divisor


def _scaled(rows, mw: int, mh: int) -> tuple[int, int, bytes]:
    """The copy media/picture.f must make, by its own integer arithmetic."""

    sh, sw = len(rows), len(rows[0])
    ow, oh = _fit(sw, sh, mw, mh)
    if (ow, oh) == (sw, sh):
        return ow, oh, qoi_codec.rgba_bytes(rows)
    columns = []
    column, error = 0, 0
    for _ in range(sw):
        columns.append(column)
        error += ow
        if error >= sw:
            error -= sw
            column += 1
    sums = [[[0] * 5 for _ in range(ow)] for _ in range(oh)]
    for y, row in enumerate(rows):
        out_row = sums[y * oh // sh]
        for x, (r, g, b, a) in enumerate(row):
            cell = out_row[columns[x]]
            cell[0] += r * a
            cell[1] += g * a
            cell[2] += b * a
            cell[3] += a
            cell[4] += 1
    out = bytearray()
    for out_row in sums:
        for ra, ga, ba, alpha, count in out_row:
            if alpha:
                out += bytes((_round(ra, alpha), _round(ga, alpha), _round(ba, alpha)))
            else:
                out += bytes(3)
            out.append(_round(alpha, count))
    return ow, oh, bytes(out)


def _png(rows) -> bytes:
    """ROWS as an RGBA PNG, as Pillow writes one."""

    image = Image.frombytes("RGBA", (len(rows[0]), len(rows)), qoi_codec.rgba_bytes(rows))
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


def _picture(rows, mw: int, mh: int, *, budget: int = 1 << 30, memory: int = 0,
             encode=qoi_codec.encode):
    data = encode(rows)
    width, height, expected = _scaled(rows, mw, mh)
    lines = [
        f"{memory} MT-MSRC-INIT",
        f"MT-FILE {len(data)} MT-MEMSRC @ MEDSRC-MEMORY",
        f'{mw} {mh} MT-MEMSRC @ MT-MSRC @ MT-PIC @ PIC-START ." START=" .',
        f'{budget} MT-RUN ." STATE=" . ." STEPS=" .',
        "MT-REPORT MT-SAVE",
        'MT-PIC @ PIC-FREE ." FREED=" MT-MSRC @ MSRC-HELD@ .',
    ]
    output, pixels = _run(lines, data, out_bytes=len(expected))
    return output, pixels, width, height, expected


def _gradient(width, height):
    return [
        [((x * 9) & 0xFF, (y * 13) & 0xFF, (x * y) & 0xFF,
          255 if (x + 2 * y) % 7 else (x * 40) & 0xFF)
         for x in range(width)]
        for y in range(height)
    ]


def _noise(width, height, seed):
    rng = random.Random(seed)
    return [[tuple(rng.randrange(256) for _ in range(4)) for _ in range(width)]
            for _ in range(height)]


@pytest.mark.parametrize(
    ("rows", "bound"),
    (
        (_gradient(17, 9), (100, 100)),     # fits: copied as it is
        (_gradient(17, 9), (17, 9)),
        (_gradient(40, 30), (10, 10)),      # width limits
        (_gradient(30, 40), (10, 10)),      # height limits
        (_noise(23, 19, 3), (7, 19)),       # only the width shrinks
        (_noise(23, 19, 5), (23, 4)),       # only the height shrinks
        (_noise(9, 9, 8), (1, 1)),          # down to one pixel
        ([[(0, 0, 0, 0)] * 6] * 6, (3, 3)),  # fully transparent stays black
    ),
)
def test_a_copy_matches_the_model(rows, bound) -> None:
    output, pixels, width, height, expected = _picture(rows, *bound)
    assert "START=1 " in output and "STATE=2 " in output, output
    assert f"SIZE={width} {height} " in output
    # Once ready, only the copy is held, and freeing gives that back too.
    assert f"HELD={width * height * 4} " in output
    assert "FREED=0 " in output
    assert pixels == expected


def test_small_budgets_take_many_steps_and_make_the_same_copy() -> None:
    rows = _gradient(40, 30)
    one_step, pixels_one, *_ = _picture(rows, 12, 12)
    many, pixels_many, *_ = _picture(rows, 12, 12, budget=1)
    assert "STEPS=0 " in one_step
    # One row per pending step, then one more step reads the end marker.
    assert "STEPS=30 " in many, many
    assert pixels_many == pixels_one


def _start_only(data: bytes, mw: int = 10, mh: int = 10, memory: int = 0) -> str:
    lines = [
        f"{memory} MT-MSRC-INIT",
        f"MT-FILE {len(data)} MT-MEMSRC @ MEDSRC-MEMORY",
        f'{mw} {mh} MT-MEMSRC @ MT-MSRC @ MT-PIC @ PIC-START ." START=" .',
        '1000000 MT-RUN ." STATE=" . DROP',
        "MT-REPORT",
    ]
    output, _ = _run(lines, data)
    return output


@pytest.mark.parametrize(
    ("data", "bound", "reason"),
    (
        (b"\x89PNG\r\n\x1a\n" + bytes(40), (10, 10), R_DAMAGED),
        (b"plain text", (10, 10), R_UNSUPPORTED),
        (b"qoif" + struct.pack(">II", 0, 4) + bytes((4, 0)) + bytes(8), (10, 10), R_DAMAGED),
        (b"qoif" + bytes(3), (10, 10), R_DAMAGED),
        (QOI_FILE, (0, 10), R_INVALID),
    ),
)
def test_a_copy_that_cannot_start_says_why_and_holds_nothing(data, bound, reason) -> None:
    output = _start_only(data, *bound)
    assert "START=3 " in output and "STATE=3 " in output, output
    assert f"R={reason} " in output and "HELD=0 " in output


@pytest.mark.parametrize(
    ("rows", "bound"),
    (
        (_gradient(17, 9), (100, 100)),
        (_gradient(40, 30), (10, 10)),
        (_noise(23, 19, 5), (23, 4)),
    ),
)
def test_a_png_copy_matches_the_model(rows, bound) -> None:
    """A PNG makes the same copy as the same picture in QOI, and its
    decoder goes back with the other work buffers."""

    output, pixels, width, height, expected = _picture(rows, *bound, encode=_png)
    assert "START=1 " in output and "STATE=2 " in output, output
    assert f"HELD={width * height * 4} " in output and "FREED=0 " in output
    assert pixels == expected


def _interlaced(png: bytes) -> bytes:
    ihdr = bytearray(png[16:29])
    ihdr[12] = 1
    chunk = b"IHDR" + bytes(ihdr)
    return png[:12] + chunk + struct.pack(">I", zlib.crc32(chunk)) + png[33:]


def test_png_files_a_copy_cannot_read_say_why() -> None:
    png = _png(_gradient(12, 8))
    output = _start_only(_interlaced(png))
    assert "START=3 " in output and f"R={R_UNSUPPORTED} " in output, output
    idat = png.index(b"IDAT")
    damaged = bytearray(png)
    damaged[idat + 5] ^= 0x10
    for broken in (bytes(damaged), png[: len(png) // 2], png[:-12]):
        output = _start_only(broken)
        assert "START=1 " in output and "STATE=3 " in output, output
        assert f"R={R_DAMAGED} " in output and "HELD=0 " in output
    # Room for the input chunk and the rows, not for the decoder.
    output = _start_only(png, 12, 8, memory=4096 + 12 * 4 + 12 * 8 * 4 + 64)
    assert "START=3 " in output and f"R={R_MEMORY} " in output, output
    assert "HELD=0 " in output


def test_short_files_and_wrong_end_markers_are_damaged() -> None:
    data = qoi_codec.encode(_gradient(12, 8))
    for broken in (data[: len(data) // 2], data[:-1], data[:-1] + b"\x05"):
        output = _start_only(broken)
        assert "START=1 " in output and "STATE=3 " in output, output
        assert f"R={R_DAMAGED} " in output and "HELD=0 " in output


def test_memory_the_caller_refuses_fails_cleanly() -> None:
    data = qoi_codec.encode(_gradient(40, 30))
    # Enough for the input chunk, not for the rows and the copy.
    output = _start_only(data, 40, 30, memory=4200)
    assert "START=3 " in output and f"R={R_MEMORY} " in output, output
    assert "HELD=0 " in output


def test_a_copy_reads_its_picture_from_a_vfs_file() -> None:
    rows = _gradient(21, 13)
    data = qoi_codec.encode(rows)
    width, height, expected = _scaled(rows, 8, 8)
    lines = [
        "0 MT-MSRC-INIT",
        "MT-RAM-VFS CONSTANT MT-V",
        'S" /pic.qoi" MT-V VFS-CREATE 0= IF -101 THROW THEN',
        'S" /pic.qoi" VFS-FF-WRITE MT-V VFS-OPEN? ?DUP IF THROW THEN',
        f"DUP MT-FILE {len(data)} ROT VFS-WRITE-EXACT IF -102 THROW THEN VFS-CLOSE",
        'S" /missing.qoi" MT-V MT-VFSSRC @ MEDSRC-VFS-OPEN 0<> ." MISSING=" .',
        'S" /pic.qoi" MT-V MT-VFSSRC @ MEDSRC-VFS-OPEN ." OPEN=" .',
        '." BYTES=" MT-VFSSRC @ MEDSRC-SIZE@ .',
        '8 8 MT-VFSSRC @ MT-MSRC @ MT-PIC @ PIC-START ." START=" .',
        '64 MT-RUN ." STATE=" . DROP',
        "MT-REPORT MT-SAVE",
        "MT-PIC @ PIC-FREE MT-VFSSRC @ MEDSRC-RELEASE",
        '." LIVE=" MT-VFSSRC @ MEDSRC-VALID? .',
    ]
    output, pixels = _run(lines, data, out_bytes=len(expected))
    assert "MISSING=-1 " in output and "OPEN=0 " in output, output
    assert f"BYTES={len(data)} " in output
    assert "START=1 " in output and "STATE=2 " in output
    assert pixels == expected
    assert "LIVE=0 " in output


def test_a_source_refuses_spans_past_its_end() -> None:
    lines = [
        "MT-FILE 10 MT-MEMSRC @ MEDSRC-MEMORY",
        'MT-OUT 4 6 MT-MEMSRC @ MEDSRC-READ? ." IN=" .',
        'MT-OUT 4 7 MT-MEMSRC @ MEDSRC-READ? ." PAST=" .',
        'MT-OUT 2 -1 MT-MEMSRC @ MEDSRC-READ? ." WRAP=" .',
    ]
    output, read = _run(lines, b"0123456789", out_bytes=4)
    assert "IN=0 " in output and "PAST=-2 " in output and "WRAP=-2 " in output
    assert read == b"6789"


def test_a_span_reads_part_of_another_source() -> None:
    lines = [
        "MT-FILE 10 MT-MEMSRC @ MEDSRC-MEMORY",
        "3 5 MT-MEMSRC @ MT-SPAN @ MEDSRC-SPAN",
        '." BYTES=" MT-SPAN @ MEDSRC-SIZE@ .',
        'MT-OUT 3 1 MT-SPAN @ MEDSRC-READ? ." IN=" .',
        'MT-OUT 3 3 MT-SPAN @ MEDSRC-READ? ." PAST=" .',
        "8 5 MT-MEMSRC @ MT-SPAN @ MEDSRC-SPAN",
        'MT-OUT 3 0 MT-SPAN @ MEDSRC-READ? ." BEYOND=" .',
        "MT-SPAN @ MEDSRC-RELEASE",
        '." LIVE=" MT-SPAN @ MEDSRC-VALID? . ." BASE=" MT-MEMSRC @ MEDSRC-VALID? 0<> .',
    ]
    output, read = _run(lines, b"0123456789", out_bytes=3)
    assert "BYTES=5 " in output and "IN=0 " in output and "PAST=-2 " in output
    assert "BEYOND=-2 " in output and "LIVE=0 " in output and "BASE=-1 " in output
    assert read == b"456"
