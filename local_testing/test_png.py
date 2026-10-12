#!/usr/bin/env python3
"""Akashic render/png.f: the resumable PNG decoder.

Files a small encoder here makes, of every colour type and bit depth with
each row filter, decode to the R, G, B, A rows their samples mean, fed
whole and in pieces; files Pillow makes decode as Pillow reads them; and
damaged, cut or interlaced files are refused.
"""

from __future__ import annotations

import io
import random
import struct
import zlib

import pytest
from PIL import Image

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

FILE_BYTES = 2 << 20
OUT_BYTES = 4 << 20
DEC_BYTES = 1 << 20
MORE, ROW, DONE, BAD = 0, 1, 2, 3
H_OK, H_NOT, H_DAMAGED, H_UNSUPPORTED = 0, 1, 2, 3
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


# ---------------------------------------------------------------------
#  A small encoder
# ---------------------------------------------------------------------

def _chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def _pack(samples: list[int], depth: int) -> bytes:
    if depth == 16:
        return b"".join(struct.pack(">H", v) for v in samples)
    if depth == 8:
        return bytes(samples)
    out, acc, bits = bytearray(), 0, 0
    for v in samples:
        acc = (acc << depth) | v
        bits += depth
        if bits == 8:
            out.append(acc)
            acc = bits = 0
    if bits:
        out.append(acc << (8 - bits))
    return bytes(out)


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def _filter(kind: int, raw: bytes, prev: bytes, bpp: int) -> bytes:
    out = bytearray()
    for i, x in enumerate(raw):
        a = raw[i - bpp] if i >= bpp else 0
        b = prev[i]
        c = prev[i - bpp] if i >= bpp else 0
        predictor = (0, a, b, (a + b) // 2, _paeth(a, b, c))[kind]
        out.append((x - predictor) & 0xFF)
    return bytes(out)


def png_file(width: int, height: int, depth: int, colour: int, pixels, *,
             palette: list[tuple[int, int, int]] | None = None, trns: bytes | None = None,
             filters=(0, 1, 2, 3, 4), idat_pieces: int = 1, level: int = 6,
             extra: tuple[tuple[bytes, bytes], ...] = (), interlace: int = 0) -> bytes:
    """A PNG of PIXELS, rows of sample tuples, each row filtered by the
    next of FILTERS in turn."""

    bpp = max(1, CHANNELS[colour] * depth // 8)
    stride = (width * CHANNELS[colour] * depth + 7) // 8
    prev = bytes(stride)
    raw_stream = bytearray()
    for y, row in enumerate(pixels):
        raw = _pack([sample for pixel in row for sample in pixel], depth)
        assert len(raw) == stride
        kind = filters[y % len(filters)]
        raw_stream += bytes([kind]) + _filter(kind, raw, prev, bpp)
        prev = raw
    data = zlib.compress(bytes(raw_stream), level)
    out = b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(
        ">IIBBBBB", width, height, depth, colour, 0, 0, interlace))
    for kind, body in extra:
        out += _chunk(kind, body)
    if palette is not None:
        out += _chunk(b"PLTE", b"".join(bytes(entry) for entry in palette))
    if trns is not None:
        out += _chunk(b"tRNS", trns)
    step = max(1, -(-len(data) // idat_pieces))
    for start in range(0, len(data), step):
        out += _chunk(b"IDAT", data[start:start + step])
    return out + _chunk(b"IEND", b"")


def _widen(v: int, depth: int) -> int:
    return {1: v * 255, 2: v * 85, 4: v * 17, 8: v, 16: v >> 8}[depth]


def expected_rgba(depth, colour, pixels, palette=None, trns=None) -> bytes:
    out = bytearray()
    key = None
    if trns is not None and colour in (0, 2):
        key = struct.unpack(">" + "H" * (len(trns) // 2), trns)
    alphas = list(trns) if (trns is not None and colour == 3) else []
    for row in pixels:
        for pixel in row:
            if colour == 0:
                g = _widen(pixel[0], depth)
                out += bytes((g, g, g, 0 if key == pixel else 255))
            elif colour == 2:
                out += bytes(_widen(v, depth) for v in pixel)
                out.append(0 if key == pixel else 255)
            elif colour == 3:
                r, g, b = palette[pixel[0]]
                a = alphas[pixel[0]] if pixel[0] < len(alphas) else 255
                out += bytes((r, g, b, a))
            elif colour == 4:
                g = _widen(pixel[0], depth)
                out += bytes((g, g, g, _widen(pixel[1], depth)))
            else:
                out += bytes(_widen(v, depth) for v in pixel)
    return bytes(out)


# ---------------------------------------------------------------------
#  The decoder in the simulator
# ---------------------------------------------------------------------

class Decoder:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=32 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("render/png.f",)):
            source.extend(_load_forth_lines(AK / module))
        source += [f"{FILE_BYTES} XBUF PT-FILE", f"{OUT_BYTES} XBUF PT-OUT",
                   f"{DEC_BYTES} XBUF PT-DEC", "65536 XBUF PT-ROW"]
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="png",
                              step_budget=80_000_000)
        self.runtime.drain_uart_output()
        self.file, self.out, self.dec, self.row = (self.word(name) for name in (
            "PT-FILE", "PT-OUT", "PT-DEC", "PT-ROW"))

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0
        for value in args:
            stack.push(value)
        self.runtime.execute(name, step_budget=4_000_000_000)
        result = stack.snapshot()
        while stack.depth():
            stack.pop()
        return tuple(result)

    def header(self, data: bytes) -> tuple[int, int, int]:
        self.runtime.memory.write_bytes(self.file, data)
        return self.call("PNG-HEADER", self.file, min(len(data), 33))

    def decode(self, data: bytes, *, chunk: int | None = None,
               rng: random.Random | None = None) -> tuple[bytes, int, int]:
        """The rows DATA decodes to, the last status, and the input used."""

        width, height, status = self.header(data)
        assert status == H_OK, status
        assert self.call("PNG-DEC-SIZE", width)[0] <= DEC_BYTES
        self.call("PNG-DEC-INIT", width, self.dec)
        position, rows = 0, bytearray()
        while True:
            take = len(data) - position
            if chunk is not None:
                take = min(take, chunk if rng is None else rng.randint(1, chunk))
            used, status = self.call("PNG-DEC-FEED", self.file + position, take, self.row,
                                     self.dec)
            assert 0 <= used <= take
            position += used
            if status == ROW:
                rows += self.runtime.memory.read_bytes(self.row, width * 4)
                continue
            if status in (DONE, BAD):
                break
            assert status == MORE and used == take
            if position == len(data):
                break
        return bytes(rows), status, position


@pytest.fixture(scope="module")
def decoder():
    return Decoder()


def _random_pixels(rng, width, height, depth, colour, palette_size=None):
    top = (palette_size or (1 << depth)) - 1 if colour == 3 else (1 << depth) - 1
    return [[tuple(rng.randint(0, top) for _ in range(CHANNELS[colour]))
             for _ in range(width)] for _ in range(height)]


COMBINATIONS = [(0, d) for d in (1, 2, 4, 8, 16)] + [(2, 8), (2, 16)] + \
    [(3, d) for d in (1, 2, 4, 8)] + [(4, 8), (4, 16), (6, 8), (6, 16)]


@pytest.mark.parametrize("colour, depth", COMBINATIONS)
def test_every_colour_type_and_depth_with_each_filter(decoder, colour, depth):
    rng = random.Random(colour * 100 + depth)
    width, height = 13, 11
    palette = None
    if colour == 3:
        palette = [tuple(rng.randint(0, 255) for _ in range(3)) for _ in range(1 << depth)]
    pixels = _random_pixels(rng, width, height, depth, colour)
    for filters in ((0,), (1,), (2,), (3,), (4,), (0, 1, 2, 3, 4)):
        data = png_file(width, height, depth, colour, pixels, palette=palette, filters=filters)
        rows, status, used = decoder.decode(data)
        assert (status, used) == (DONE, len(data)), (filters, status)
        assert rows == expected_rgba(depth, colour, pixels, palette), filters


@pytest.mark.parametrize("colour, depth, trns", (
    (0, 8, struct.pack(">H", 7)),
    (0, 1, struct.pack(">H", 1)),
    (0, 16, struct.pack(">H", 513)),
    (2, 8, struct.pack(">HHH", 1, 2, 3)),
    (2, 16, struct.pack(">HHH", 258, 515, 772)),
))
def test_a_transparent_colour_key(decoder, colour, depth, trns):
    rng = random.Random(depth)
    key = struct.unpack(">" + "H" * (len(trns) // 2), trns)
    pixels = _random_pixels(rng, 9, 5, depth, colour)
    pixels[1][2] = key
    pixels[4][8] = key
    data = png_file(9, 5, depth, colour, pixels, trns=trns)
    rows, status, _ = decoder.decode(data)
    assert status == DONE
    assert rows == expected_rgba(depth, colour, pixels, trns=trns)
    assert rows[(1 * 9 + 2) * 4 + 3] == 0


def test_a_palette_with_partial_transparency(decoder):
    rng = random.Random(3)
    palette = [tuple(rng.randint(0, 255) for _ in range(3)) for _ in range(40)]
    trns = bytes(rng.randint(0, 255) for _ in range(17))
    pixels = _random_pixels(rng, 21, 9, 8, 3, palette_size=40)
    data = png_file(21, 9, 8, 3, pixels, palette=palette, trns=trns)
    rows, status, _ = decoder.decode(data)
    assert (status, rows) == (DONE, expected_rgba(8, 3, pixels, palette, trns))


@pytest.mark.parametrize("chunk", (1, 3, 97))
def test_fed_in_pieces_across_several_image_chunks(decoder, chunk):
    rng = random.Random(chunk)
    pixels = _random_pixels(rng, 37, 23, 8, 6)
    data = png_file(37, 23, 8, 6, pixels, idat_pieces=7,
                    extra=((b"tEXt", b"Comment\x00made by the test"),))
    rows, status, used = decoder.decode(data, chunk=chunk)
    assert (status, used, rows) == (DONE, len(data), expected_rgba(8, 6, pixels))


def test_fed_in_random_pieces(decoder):
    rng = random.Random(77)
    for trial in range(4):
        colour, depth = rng.choice(COMBINATIONS)
        palette = ([tuple(rng.randint(0, 255) for _ in range(3)) for _ in range(1 << depth)]
                   if colour == 3 else None)
        width, height = rng.randint(1, 50), rng.randint(1, 30)
        pixels = _random_pixels(rng, width, height, depth, colour)
        data = png_file(width, height, depth, colour, pixels, palette=palette,
                        idat_pieces=rng.randint(1, 5))
        rows, status, _ = decoder.decode(data, chunk=200, rng=rng)
        assert (status, rows) == (DONE, expected_rgba(depth, colour, pixels, palette)), trial


@pytest.mark.parametrize("mode", ("RGB", "RGBA", "L", "LA", "P", "1"))
def test_files_pillow_makes_decode_as_pillow_reads_them(decoder, mode):
    rng = random.Random(len(mode))
    image = Image.frombytes("RGBA", (31, 17), rng.randbytes(31 * 17 * 4)).convert(mode)
    buffer = io.BytesIO()
    image.save(buffer, "PNG", optimize=mode != "1")
    data = buffer.getvalue()
    rows, status, _ = decoder.decode(data)
    assert status == DONE
    assert rows == Image.open(io.BytesIO(data)).convert("RGBA").tobytes()


def test_a_header_says_what_the_file_is(decoder):
    pixels = [[(1,)] * 4] * 3
    good = png_file(4, 3, 8, 0, pixels)
    assert decoder.header(good) == (4, 3, H_OK)
    assert decoder.header(b"not a png at all, at all, at all.") == (0, 0, H_NOT)
    interlaced = png_file(4, 3, 8, 0, pixels, interlace=1)
    assert decoder.header(interlaced) == (4, 3, H_UNSUPPORTED)
    damaged = bytearray(good)
    damaged[20] ^= 1
    assert decoder.header(bytes(damaged))[2] == H_DAMAGED
    assert decoder.header(good[:20])[2] == H_DAMAGED


def test_damaged_files_are_refused(decoder):
    rng = random.Random(5)
    pixels = _random_pixels(rng, 16, 8, 8, 2)
    good = png_file(16, 8, 8, 2, pixels)
    # A wrong CRC on the image data.
    idat = good.index(b"IDAT")
    damaged = bytearray(good)
    damaged[idat + 6] ^= 0x40
    assert decoder.decode(bytes(damaged))[1] == BAD
    # An unknown critical chunk.
    critical = png_file(16, 8, 8, 2, pixels, extra=((b"ABCD", b"xyz"),))
    assert decoder.decode(critical)[1] == BAD
    # Too few rows of data.
    short = png_file(16, 8, 8, 2, pixels[:5])
    short = short.replace(struct.pack(">II", 16, 5), struct.pack(">II", 16, 8))
    head = short[:33]
    fixed = head[:29] + struct.pack(">I", zlib.crc32(head[12:29])) + short[33:]
    assert decoder.decode(fixed)[1] == BAD
    # A palette index past the palette.
    palette = [(1, 2, 3), (4, 5, 6)]
    indexed = png_file(4, 2, 8, 3, [[(0,), (1,), (2,), (1,)], [(0,)] * 4], palette=palette)
    assert decoder.decode(indexed)[1] == BAD


def test_a_cut_file_never_ends(decoder):
    pixels = _random_pixels(random.Random(6), 20, 10, 8, 6)
    data = png_file(20, 10, 8, 6, pixels)
    for cut in (40, len(data) // 2, len(data) - 1):
        _, status, used = decoder.decode(data[:cut])
        assert (status, used) == (MORE, cut)


def test_the_filters_alone(decoder):
    """PNG-UNFILTER undoes each filter in place, for a PDF predictor too."""

    rng = random.Random(9)
    for bpp in (1, 3, 4, 8):
        prev = rng.randbytes(40)
        raw = rng.randbytes(40)
        for kind in range(5):
            filtered = _filter(kind, raw, prev, bpp)
            decoder.runtime.memory.write_bytes(decoder.row, filtered)
            decoder.runtime.memory.write_bytes(decoder.row + 100, prev)
            assert decoder.call("PNG-UNFILTER", kind, decoder.row, decoder.row + 100, 40,
                                bpp) == ((1 << 64) - 1,)
            assert decoder.runtime.memory.read_bytes(decoder.row, 40) == raw, (bpp, kind)
    assert decoder.call("PNG-UNFILTER", 5, decoder.row, decoder.row + 100, 40, 1) == (0,)
