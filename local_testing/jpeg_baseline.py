"""A baseline JPEG encoder in integer arithmetic, for sample files.

Writes a colour picture as a baseline sequential JPEG (ITU T.81): YCbCr
with no subsampling, the Annex K quantization tables scaled to a quality,
and the Annex K Huffman tables.  Every step is integer arithmetic, the DCT
through a fixed table, so the bytes are the same on every host, as the
image build's other samples are.  It is small and slow, and meant for
pictures of a few thousand pixels.
"""

from __future__ import annotations

import struct

# The 8-point DCT-II basis, scaled by 4096: round(4096 * C(u) / 2 *
# cos((2x + 1) u pi / 16)), C(0) = 1/sqrt(2), else 1.
DCT = (
    (1448, 1448, 1448, 1448, 1448, 1448, 1448, 1448),
    (2009, 1703, 1138, 400, -400, -1138, -1703, -2009),
    (1892, 784, -784, -1892, -1892, -784, 784, 1892),
    (1703, -400, -2009, -1138, 1138, 2009, 400, -1703),
    (1448, -1448, -1448, 1448, 1448, -1448, -1448, 1448),
    (1138, -2009, 400, 1703, -1703, -400, 2009, -1138),
    (784, -1892, 1892, -784, -784, 1892, -1892, 784),
    (400, -1138, 1703, -2009, 2009, -1703, 1138, -400),
)

LUMA_Q = (
    16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
    14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
    18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
)
CHROMA_Q = (
    17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99,
) + (99,) * 32

ZIGZAG = (
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
)

# Annex K.3 Huffman tables: counts of codes of each length 1-16, values.
DC_LUMA = ((0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0), tuple(range(12)))
DC_CHROMA = ((0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0), tuple(range(12)))
AC_LUMA = ((0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D), bytes.fromhex(
    "01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a"
    "161718191a25262728292a3435363738393a434445464748494a535455565758595a6364656667"
    "68696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3"
    "b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4"
    "f5f6f7f8f9fa"))
AC_CHROMA = ((0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77), bytes.fromhex(
    "000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a1624"
    "34e125f11718191a262728292a35363738393a434445464748494a535455565758595a63646566"
    "6768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aa"
    "b2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4"
    "f5f6f7f8f9fa"))


def _codes(table) -> dict[int, tuple[int, int]]:
    """Each value's code and its length, as Annex C makes them."""

    counts, values = table
    codes, code, k = {}, 0, 0
    for length, count in enumerate(counts, 1):
        for _ in range(count):
            codes[values[k]] = (code, length)
            code += 1
            k += 1
        code <<= 1
    return codes


def _scaled(table, quality: int) -> list[int]:
    scale = 5000 // quality if quality < 50 else 200 - 2 * quality
    return [min(255, max(1, (q * scale + 50) // 100)) for q in table]


class _Bits:
    def __init__(self) -> None:
        self.out = bytearray()
        self.acc = 0
        self.n = 0

    def put(self, code: int, length: int) -> None:
        self.acc = (self.acc << length) | (code & ((1 << length) - 1))
        self.n += length
        while self.n >= 8:
            self.n -= 8
            byte = (self.acc >> self.n) & 0xFF
            self.out.append(byte)
            if byte == 0xFF:
                self.out.append(0)

    def flush(self) -> bytes:
        if self.n:
            self.put((1 << (8 - self.n)) - 1, 8 - self.n)
        return bytes(self.out)


def _magnitude(value: int) -> tuple[int, int]:
    """A coefficient's category and its bits, as T.81 F.1.2.1 codes it."""

    size = abs(value).bit_length()
    return size, (value if value >= 0 else value + (1 << size) - 1)


def _dct(block: list[int]) -> list[int]:
    """The 2-D DCT of 64 level-shifted samples, rounded."""

    rows = [[sum(DCT[u][x] * block[y * 8 + x] for x in range(8)) for u in range(8)]
            for y in range(8)]
    out = []
    for v in range(8):
        for u in range(8):
            total = sum(DCT[v][y] * rows[y][u] for y in range(8))
            out.append((total + (1 << 23)) >> 24 if total >= 0 else -((-total + (1 << 23)) >> 24))
    return out


def _quantize(value: int, q: int) -> int:
    return (value + q // 2) // q if value >= 0 else -((-value + q // 2) // q)


def encode(rows: list[list[tuple[int, int, int]]], quality: int = 85) -> bytes:
    """ROWS of (r, g, b) pixels as a baseline JPEG."""

    height, width = len(rows), len(rows[0])
    tables = (_scaled(LUMA_Q, quality), _scaled(CHROMA_Q, quality))
    dc = (_codes(DC_LUMA), _codes(DC_CHROMA))
    ac = (_codes(AC_LUMA), _codes(AC_CHROMA))
    planes = ([], [], [])
    for row in rows:
        for plane in planes:
            plane.append([])
        for r, g, b in row:
            y = (19595 * r + 38470 * g + 7471 * b + 32768) >> 16
            cb = ((-11059 * r - 21709 * g + 32768 * b + 32768) >> 16) + 128
            cr = ((32768 * r - 27439 * g - 5329 * b + 32768) >> 16) + 128
            for plane, value in zip(planes, (y, cb, cr)):
                plane[-1].append(min(255, max(0, value)))
    bits = _Bits()
    previous = [0, 0, 0]
    for by in range(0, height, 8):
        for bx in range(0, width, 8):
            for c, plane in enumerate(planes):
                block = [plane[min(by + y, height - 1)][min(bx + x, width - 1)] - 128
                         for y in range(8) for x in range(8)]
                kind = 0 if c == 0 else 1
                coefficients = _dct(block)
                q = [_quantize(coefficients[ZIGZAG[k]], tables[kind][ZIGZAG[k]])
                     for k in range(64)]
                size, value = _magnitude(q[0] - previous[c])
                previous[c] = q[0]
                bits.put(*dc[kind][size])
                if size:
                    bits.put(value, size)
                run = 0
                for k in range(1, 64):
                    if q[k] == 0:
                        run += 1
                        continue
                    while run > 15:
                        bits.put(*ac[kind][0xF0])
                        run -= 16
                    size, value = _magnitude(q[k])
                    bits.put(*ac[kind][(run << 4) | size])
                    bits.put(value, size)
                    run = 0
                if run:
                    bits.put(*ac[kind][0x00])
    scan = bits.flush()

    def segment(marker: int, body: bytes) -> bytes:
        return struct.pack(">HH", 0xFF00 | marker, len(body) + 2) + body

    def quant(index: int, table: list[int]) -> bytes:
        return bytes([index]) + bytes(table[ZIGZAG[k]] for k in range(64))

    def huffman(cls: int, index: int, table) -> bytes:
        counts, values = table
        return bytes([(cls << 4) | index]) + bytes(counts) + bytes(values)

    return b"".join([
        b"\xff\xd8",
        segment(0xE0, b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"),
        segment(0xDB, quant(0, tables[0]) + quant(1, tables[1])),
        segment(0xC0, struct.pack(">BHHB", 8, height, width, 3)
                + bytes([1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1])),
        segment(0xC4, huffman(0, 0, DC_LUMA) + huffman(1, 0, AC_LUMA)
                + huffman(0, 1, DC_CHROMA) + huffman(1, 1, AC_CHROMA)),
        segment(0xDA, bytes([3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0])),
        scan,
        b"\xff\xd9",
    ])
