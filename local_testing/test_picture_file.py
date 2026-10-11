#!/usr/bin/env python3
"""PIC-FILE: which picture a file holds, read from its first bytes.

A rich terminal that decodes QOI, PNG or JPEG files takes a picture as its
file, so the guest needs only the file's format and the picture's size, not
its pixels.  PIC-FILE reads them from a QOI or PNG header, and from the
frame header a JPEG's earlier segments lead to, natively on the simulator.
"""

from __future__ import annotations

import io
import re
import struct

import pytest
from PIL import Image

import qoi_codec
from test_media import R_NONE, R_UNSUPPORTED, R_DAMAGED, _gradient, _run


def _facts(data: bytes) -> tuple[int, int, int, int]:
    lines = [
        f"MT-FILE {len(data)} MT-MEMSRC @ MEDSRC-MEMORY",
        'MT-MEMSRC @ PIC-FILE ." R=" . ." H=" . ." W=" . ." F=" .',
    ]
    output, _ = _run(lines, data)
    values = dict(re.findall(r"([RHWF])=(-?\d+)", output))
    return tuple(int(values[key]) for key in "FWHR")


def _pillow(fmt: str, size=(37, 21), **options) -> bytes:
    image = Image.new("RGB" if fmt == "JPEG" else "RGBA", size, (200, 40, 90))
    out = io.BytesIO()
    image.save(out, fmt, **options)
    return out.getvalue()


# Picture formats, numbered as RETAINED-1 numbers them; media/kind.f's kinds
# are a separate numbering.
F_QOI, F_PNG, F_JPEG = 2, 3, 4


def test_the_formats_are_numbered_as_the_terminal_numbers_them() -> None:
    lines = ['PIC-F-RGBA8 . PIC-F-QOI . PIC-F-PNG . PIC-F-JPEG . ." |"']
    output, _ = _run(lines)
    assert "1 2 3 4 |" in output


@pytest.mark.parametrize(
    ("data", "facts"),
    (
        (qoi_codec.encode(_gradient(17, 9)), (F_QOI, 17, 9, R_NONE)),
        (_pillow("PNG"), (F_PNG, 37, 21, R_NONE)),
        (_pillow("PNG", (1, 4000)), (F_PNG, 1, 4000, R_NONE)),
        (_pillow("JPEG"), (F_JPEG, 37, 21, R_NONE)),
        (_pillow("JPEG", progressive=True), (F_JPEG, 37, 21, R_NONE)),
        # EXIF and comment segments come before the frame header.
        (_pillow("JPEG", (640, 480), exif=b"Exif\0\0" + bytes(9000),
                 comment=b"a" * 3000), (F_JPEG, 640, 480, R_NONE)),
    ),
)
def test_a_picture_file_says_its_format_and_size(data, facts) -> None:
    assert _facts(data) == facts


def test_fill_bytes_and_standalone_markers_lead_to_the_frame() -> None:
    jpeg = _pillow("JPEG", (33, 7))
    # SOI, then fill bytes and a restart marker before the first segment.
    data = jpeg[:2] + b"\xff\xff\xff\xd3" + jpeg[2:]
    assert _facts(data) == (F_JPEG, 33, 7, R_NONE)


def _sof_at(jpeg: bytes) -> int:
    at = 2
    while True:
        marker, length = jpeg[at + 1], struct.unpack(">H", jpeg[at + 2:at + 4])[0]
        if marker in (0xC0, 0xC2):
            return at
        at += 2 + length


@pytest.mark.parametrize(
    ("case", "reason"),
    (
        ("text", R_UNSUPPORTED),
        ("gif", R_UNSUPPORTED),
        ("short", R_UNSUPPORTED),
        ("qoi-zero-width", R_DAMAGED),
        ("qoi-short", R_DAMAGED),
        ("png-not-ihdr", R_DAMAGED),
        ("png-zero-height", R_DAMAGED),
        ("png-short", R_DAMAGED),
        ("jpeg-no-frame", R_DAMAGED),
        ("jpeg-scan-first", R_DAMAGED),
        ("jpeg-not-a-marker", R_DAMAGED),
        ("jpeg-height-later", R_UNSUPPORTED),
    ),
)
def test_a_file_that_is_not_a_picture_it_knows_says_why(case, reason) -> None:
    png = _pillow("PNG")
    jpeg = _pillow("JPEG")
    sof = _sof_at(jpeg)
    data = {
        "text": b"plain words, not a picture",
        "gif": b"GIF89a" + bytes(20),
        "short": b"\xff",
        "qoi-zero-width": b"qoif" + struct.pack(">II", 0, 4) + bytes((4, 0)),
        "qoi-short": b"qoif" + bytes(6),
        "png-not-ihdr": png[:12] + b"IDAT" + png[16:],
        "png-zero-height": png[:20] + bytes(4) + png[24:],
        "png-short": png[:20],
        "jpeg-no-frame": jpeg[:sof],
        "jpeg-scan-first": jpeg[:2] + b"\xff\xda\x00\x02" + jpeg[2:],
        "jpeg-not-a-marker": jpeg[:2] + b"\x00\x00" + jpeg[2:],
        # A frame header whose height a later DNL segment gives.
        "jpeg-height-later": jpeg[:sof + 5] + b"\x00\x00" + jpeg[sof + 7:],
    }[case]
    assert _facts(data) == (0, 0, 0, reason)
