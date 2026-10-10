#!/usr/bin/env python3
"""Akashic render/qoi.f: the QOI encoder and the resumable decoder.

The decoder is checked pixel for pixel against an independent Python codec
(qoi_codec.py), fed in several chunk sizes so that every kind of operation
also arrives split between two feeds.  Short files, a wrong end marker and
bad headers must fail cleanly, and every run must leave the data stack as it
found it.  The encoder must produce exactly the reference byte stream.
"""

from __future__ import annotations

import random
import re
import struct

import pytest

import qoi_codec
from forth_snapshot import ForthSnapshot, program_output

FILE_BYTES = 1 << 20
OUT_BYTES = 4 << 20

SNAPSHOT = ForthSnapshot(
    ("render/qoi-encode.f",),
    prelude=(
        f"{FILE_BYTES} XBUF QT-FILE",
        f"{OUT_BYTES} XBUF QT-OUT",
        "65536 XBUF QT-ROW",
        "CREATE QT-DEC QOI-DEC-SIZE ALLOT",
        "VARIABLE QT-P  VARIABLE QT-LEFT  VARIABLE QT-OUT-P  VARIABLE QT-CHUNK",
        "VARIABLE QT-W",
        # Decode the FILE-U bytes at QT-FILE, CHUNK bytes per feed at most,
        # copying each finished row to QT-OUT.
        ": QT-DECODE  ( file-u chunk -- )",
        "  QT-CHUNK !",
        "  QT-FILE OVER QOI-HEADER 0= IF DROP .\" NOHEADER\" EXIT THEN",
        "  2DROP OVER QT-W ! QT-DEC QOI-DEC-INIT",
        "  14 - QT-LEFT !  QT-FILE 14 + QT-P !  QT-OUT QT-OUT-P !",
        "  BEGIN",
        "    QT-P @ QT-LEFT @ QT-CHUNK @ MIN QT-ROW QT-DEC QOI-DEC-FEED",
        "    SWAP DUP QT-P +! NEGATE QT-LEFT +!",
        "    DUP QOI-S-ROW = IF",
        "      QT-ROW QT-OUT-P @ QT-W @ 4 * MOVE  QT-W @ 4 * QT-OUT-P +!",
        "    THEN",
        "    DUP QOI-S-DONE = IF DROP .\" DONE \" QT-DEC QOI-DEC-ROWS@ . EXIT THEN",
        "    DUP QOI-S-BAD = IF DROP .\" BAD \" QT-DEC QOI-DEC-ROWS@ . EXIT THEN",
        "    QOI-S-MORE = QT-LEFT @ 0= AND IF",
        "      .\" TRUNCATED \" QT-DEC QOI-DEC-ROWS@ . EXIT",
        "    THEN",
        "  AGAIN ;",
    ),
)

_ADDRESSES: dict[str, int] = {}


def _address(name: str) -> int:
    if not _ADDRESSES:
        lines = ["QT-FILE U. QT-OUT U."]
        text = program_output(SNAPSHOT.run(lines), lines)
        file_address, out_address = (int(value) for value in re.findall(r"\d+", text)[:2])
        _ADDRESSES.update(file=file_address, out=out_address)
    return _ADDRESSES[name]


def _run(lines: list[str], data: bytes = b"", *, out_bytes: int = 0) -> tuple[str, bytes]:
    """Run LINES with DATA at QT-FILE; return the output and OUT_BYTES of QT-OUT."""

    assert len(data) <= FILE_BYTES and out_bytes <= OUT_BYTES
    file_address = _address("file")
    out_address = _address("out")
    captured = bytearray()

    def setup(system) -> None:
        if data:
            system._raw_mem_write_span(file_address, data)

    def inspect(system) -> None:
        if out_bytes:
            captured.extend(system._raw_mem_read_span(out_address, out_bytes))

    lines = lines + ['DEPTH ." @D:" . CR']
    output = program_output(SNAPSHOT.run(lines, setup=setup, inspect=inspect), lines)
    assert "@D:0 " in output, output[-500:]
    return output, bytes(captured)


def _gradient(width: int, height: int) -> list[list[tuple[int, int, int, int]]]:
    """Smooth steps for DIFF and LUMA, sharp steps for RGB, alpha for RGBA."""

    return [
        [
            (
                (x * 7 + y * 3) & 0xFF,
                (x * 2 + y * 11) & 0xFF,
                (x * x + y) & 0xFF,
                255 if (x + y) % 9 else (x * 29) & 0xFF,
            )
            for x in range(width)
        ]
        for y in range(height)
    ]


def _noise(width: int, height: int, seed: int) -> list[list[tuple[int, int, int, int]]]:
    rng = random.Random(seed)
    return [
        [tuple(rng.randrange(256) for _ in range(4)) for _ in range(width)]
        for _ in range(height)
    ]


def _palette(width: int, height: int, seed: int) -> list[list[tuple[int, int, int, int]]]:
    """Few colours in random order, so most pixels are INDEX hits."""

    rng = random.Random(seed)
    colours = [(200, 10, 10, 255), (10, 200, 10, 255), (10, 10, 200, 255),
               (250, 250, 250, 128), (0, 0, 0, 0)]
    return [[rng.choice(colours) for _ in range(width)] for _ in range(height)]


def _runs(width: int, height: int) -> list[list[tuple[int, int, int, int]]]:
    """Long runs that cross rows and pass the 62-pixel run limit."""

    rows = [[(40, 80, 120, 255)] * width for _ in range(height)]
    rows[1][width // 2] = (41, 80, 120, 255)
    rows[height - 1][width - 1] = (90, 90, 90, 255)
    return rows


PICTURES = {
    "gradient": _gradient(37, 23),
    "noise": _noise(16, 16, 7),
    "palette": _palette(31, 17, 11),
    "runs": _runs(70, 5),
    "single": [[(1, 2, 3, 4)]],
    "tall": _gradient(1, 40),
}


@pytest.mark.parametrize("name", sorted(PICTURES))
@pytest.mark.parametrize("chunk", (1, 5, FILE_BYTES))
def test_decoder_matches_the_reference_in_any_chunking(name: str, chunk: int) -> None:
    rows = PICTURES[name]
    data = qoi_codec.encode(rows)
    width, height = len(rows[0]), len(rows)
    output, pixels = _run(
        [f"{len(data)} {chunk} QT-DECODE"], data, out_bytes=width * height * 4,
    )
    assert f"DONE {height} " in output, output
    assert pixels == qoi_codec.rgba_bytes(rows)


def test_decoder_keeps_alpha_opaque_in_three_channel_files() -> None:
    rows = [[(x * 30, 255 - x * 30, 7, 255) for x in range(8)] for _ in range(3)]
    data = qoi_codec.encode(rows, channels=3)
    output, pixels = _run([f"{len(data)} 3 QT-DECODE"], data, out_bytes=8 * 3 * 4)
    assert "DONE 3 " in output
    assert pixels == qoi_codec.rgba_bytes(rows)


@pytest.mark.parametrize("chunk", (1, FILE_BYTES))
def test_short_files_and_wrong_end_markers_fail_cleanly(chunk: int) -> None:
    rows = _gradient(9, 6)
    data = qoi_codec.encode(rows)

    # Cut inside the pixels: rows before the cut are reported, then the
    # input runs out.
    output, _ = _run([f"{len(data) // 2} {chunk} QT-DECODE"], data[: len(data) // 2])
    assert "TRUNCATED " in output and "DONE" not in output
    # Every pixel present, part of the end marker missing.
    output, _ = _run([f"{len(data) - 3} {chunk} QT-DECODE"], data[:-3])
    assert "TRUNCATED 6 " in output
    # A wrong end marker byte.
    bad = data[:-1] + b"\x02"
    output, _ = _run([f"{len(bad)} {chunk} QT-DECODE"], bad)
    assert "BAD 6 " in output


@pytest.mark.parametrize(
    "header",
    (
        b"qoig" + struct.pack(">II", 2, 2) + bytes((4, 0)),
        b"qoif" + struct.pack(">II", 0, 2) + bytes((4, 0)),
        b"qoif" + struct.pack(">II", 2, 0) + bytes((4, 0)),
        b"qoif" + struct.pack(">II", 2, 2) + bytes((5, 0)),
        b"qoif" + struct.pack(">II", 2, 2) + bytes((4, 2)),
        b"qoif" + struct.pack(">II", 2, 2) + bytes((4,)),
    ),
)
def test_bad_headers_are_refused(header: bytes) -> None:
    output, _ = _run([f'QT-FILE {len(header)} QOI-HEADER . ." H"'], header)
    assert "0 H" in output


def test_a_good_header_reports_its_fields() -> None:
    header = b"qoif" + struct.pack(">II", 640, 480) + bytes((3, 1))
    output, _ = _run(['QT-FILE 14 QOI-HEADER . . . . . ." H"'], header)
    assert "-1 1 3 480 640 H" in output


@pytest.mark.parametrize("name", ("gradient", "noise", "palette", "runs", "single"))
def test_encoder_matches_the_reference_byte_stream(name: str) -> None:
    rows = PICTURES[name]
    width, height = len(rows[0]), len(rows)
    # Surfaces hold 0xRRGGBBAA values stored with L!, so A, B, G, R in memory.
    surface = bytes(
        channel for row in rows for (r, g, b, a) in row for channel in (a, b, g, r)
    )
    expected = qoi_codec.encode(rows)
    lines = [
        f"QT-FILE {width} {height} {width * 4} SURF-CREATE-FROM",
        f"QT-OUT {OUT_BYTES} QOI-ENCODE . .\" LEN\"",
    ]
    output, encoded = _run(lines, surface, out_bytes=len(expected))
    assert f"{len(expected)} LEN" in output
    assert encoded == expected


def test_encoder_refuses_a_buffer_too_small_for_the_worst_case() -> None:
    # QOI-FILE-SIZE allows five bytes a pixel plus the header and end marker.
    worst = 1 * 1 * 5 + 14 + 8
    lines = [
        "QT-FILE 1 1 4 SURF-CREATE-FROM",
        f"QT-OUT {worst - 1} QOI-ENCODE . .\" LEN\"",
        f"1 1 QOI-FILE-SIZE . .\" WORST\"",
    ]
    output, _ = _run(lines, bytes((4, 3, 2, 1)))
    assert "0 LEN" in output
    assert f"{worst} WORST" in output
