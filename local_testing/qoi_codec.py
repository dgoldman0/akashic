"""A small, independent QOI encoder and decoder.

It follows the reference algorithm of the QOI specification (qoiformat.org),
so tests can check Akashic's render/qoi.f against it and the Desktop disk
builder can make sample pictures.  Pixels are rows of (r, g, b, a) tuples.
"""

from __future__ import annotations

import struct

MAGIC = b"qoif"
END_MARKER = bytes(7) + b"\x01"

OP_INDEX = 0x00
OP_DIFF = 0x40
OP_LUMA = 0x80
OP_RUN = 0xC0
OP_RGB = 0xFE
OP_RGBA = 0xFF

Pixel = tuple[int, int, int, int]


def _hash(pixel: Pixel) -> int:
    r, g, b, a = pixel
    return (r * 3 + g * 5 + b * 7 + a * 11) % 64


def _signed(delta: int) -> int:
    """A channel difference wrapped into -128..127."""

    return ((delta + 128) & 0xFF) - 128


def encode(rows: list[list[Pixel]], channels: int = 4, colorspace: int = 0) -> bytes:
    height = len(rows)
    width = len(rows[0]) if rows else 0
    if width == 0 or height == 0 or any(len(row) != width for row in rows):
        raise ValueError("a picture is a non-empty rectangle of pixels")
    out = bytearray(MAGIC + struct.pack(">II", width, height) + bytes((channels, colorspace)))
    index: list[Pixel] = [(0, 0, 0, 0)] * 64
    previous: Pixel = (0, 0, 0, 255)
    run = 0
    pixels = [pixel for row in rows for pixel in row]
    for position, pixel in enumerate(pixels):
        if pixel == previous:
            run += 1
            if run == 62 or position == len(pixels) - 1:
                out.append(OP_RUN | (run - 1))
                run = 0
            continue
        if run:
            out.append(OP_RUN | (run - 1))
            run = 0
        slot = _hash(pixel)
        if index[slot] == pixel:
            out.append(OP_INDEX | slot)
        else:
            index[slot] = pixel
            if pixel[3] == previous[3]:
                vr = _signed(pixel[0] - previous[0])
                vg = _signed(pixel[1] - previous[1])
                vb = _signed(pixel[2] - previous[2])
                vg_r = vr - vg
                vg_b = vb - vg
                if -2 <= vr <= 1 and -2 <= vg <= 1 and -2 <= vb <= 1:
                    out.append(OP_DIFF | (vr + 2) << 4 | (vg + 2) << 2 | (vb + 2))
                elif -32 <= vg <= 31 and -8 <= vg_r <= 7 and -8 <= vg_b <= 7:
                    out.append(OP_LUMA | (vg + 32))
                    out.append((vg_r + 8) << 4 | (vg_b + 8))
                else:
                    out += bytes((OP_RGB, *pixel[:3]))
            else:
                out += bytes((OP_RGBA, *pixel))
        previous = pixel
    out += END_MARKER
    return bytes(out)


def decode(data: bytes) -> tuple[int, int, list[list[Pixel]]]:
    if len(data) < 14 + len(END_MARKER) or data[:4] != MAGIC:
        raise ValueError("not a QOI file")
    width, height = struct.unpack(">II", data[4:12])
    if width == 0 or height == 0 or data[12] not in (3, 4) or data[13] > 1:
        raise ValueError("bad QOI header")
    index: list[Pixel] = [(0, 0, 0, 0)] * 64
    pixel: Pixel = (0, 0, 0, 255)
    position = 14
    run = 0
    pixels: list[Pixel] = []
    for _ in range(width * height):
        if run:
            run -= 1
        else:
            op = data[position]
            position += 1
            if op == OP_RGB:
                pixel = (*data[position:position + 3], pixel[3])
                position += 3
            elif op == OP_RGBA:
                pixel = tuple(data[position:position + 4])
                position += 4
            elif op & 0xC0 == OP_INDEX:
                pixel = index[op]
            elif op & 0xC0 == OP_DIFF:
                pixel = (
                    (pixel[0] + ((op >> 4) & 3) - 2) & 0xFF,
                    (pixel[1] + ((op >> 2) & 3) - 2) & 0xFF,
                    (pixel[2] + (op & 3) - 2) & 0xFF,
                    pixel[3],
                )
            elif op & 0xC0 == OP_LUMA:
                second = data[position]
                position += 1
                vg = (op & 0x3F) - 32
                pixel = (
                    (pixel[0] + vg - 8 + (second >> 4)) & 0xFF,
                    (pixel[1] + vg) & 0xFF,
                    (pixel[2] + vg - 8 + (second & 0x0F)) & 0xFF,
                    pixel[3],
                )
            else:
                run = op & 0x3F
            index[_hash(pixel)] = pixel
        pixels.append(pixel)
    if data[position:position + len(END_MARKER)] != END_MARKER:
        raise ValueError("bad QOI end marker")
    rows = [pixels[row * width:(row + 1) * width] for row in range(height)]
    return width, height, rows


def rgba_bytes(rows: list[list[Pixel]]) -> bytes:
    """Rows as raw row-major RGBA8, the rich terminal's resource format."""

    return bytes(channel for row in rows for pixel in row for channel in pixel)
