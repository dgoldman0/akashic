#!/usr/bin/env python3
"""Akashic pdf/filter.f: a PDF stream's bytes through its filters.

Each filter is checked against Python: Flate against zlib, with the PNG
predictors against PNG's own filters and the TIFF predictor against its
definition; ASCIIHex and ASCII85 against Python's codecs; LZW against the
strips Pillow writes into TIFF files, which use PDF's coding with early
change, and against an encoder written from the PDF reference for the
other setting; and RunLength against an encoder written from the reference.
Chains of filters, abbreviated names, damaged data, unsupported filters and
a memory budget the output passes are checked too.  Every buffer the
decoder takes is given back.
"""

from __future__ import annotations

import base64
import io
import random
import zlib

import pytest
from PIL import Image

from forth_dependencies import dependency_order
from test_png import _filter
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, DAMAGED, UNSUPPORTED = 0, 1, 2, 3
IN_BYTES = 1 << 20

PRELUDE = f"""
{IN_BYTES} XBUF FT-IN
65536 XBUF FT-DICT
CREATE FT-BUF PDF-BUF-SIZE ALLOT
CREATE FT-MSRC MSRC-SIZE ALLOT
: FT-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: FT-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: FT-MSRC-INIT  ( budget -- )  >R ['] FT-ALLOC ['] FT-FREE 0 R> FT-MSRC MSRC-INIT ;
: FT-DECODE  ( in-u dict-u budget -- status )
    FT-MSRC-INIT >R FT-IN SWAP FT-DICT R> FT-BUF FT-MSRC PDF-DECODE ;
: FT-OUT  ( -- a u )  FT-BUF PDF-BUF.A @ FT-BUF PDF-BUF.U @ ;
: FT-DONE  ( -- held )  FT-BUF FT-MSRC PDF-BUF-FREE FT-MSRC MSRC-HELD@ ;
"""


class Filters:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=64 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/filter.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-filter",
                              step_budget=200_000_000)
        self.runtime.drain_uart_output()
        self.input = self.word("FT-IN")
        self.dict = self.word("FT-DICT")

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0
        for value in args:
            stack.push(value)
        self.runtime.execute(name, step_budget=4_000_000_000)
        result = tuple(stack.snapshot())
        while stack.depth():
            stack.pop()
        return result

    def decode(self, data: bytes, dictionary: bytes, budget: int = 0) -> tuple[int, bytes]:
        """The status and output of DATA through DICTIONARY's filters."""

        assert len(data) <= IN_BYTES
        self.runtime.memory.write_bytes(self.input, data)
        self.runtime.memory.write_bytes(self.dict, dictionary)
        (status,) = self.call("FT-DECODE", len(data), len(dictionary), budget)
        a, u = self.call("FT-OUT")
        output = self.runtime.memory.read_bytes(a, u) if a else b""
        assert self.call("FT-DONE") == (0,)
        return status, output


@pytest.fixture(scope="module")
def filters():
    return Filters()


def text(size: int, seed: int = 1) -> bytes:
    rng = random.Random(seed)
    words = [b"page", b"font", b"stream", b"object", b"the", b"of", b"text", b"\n"]
    out = bytearray()
    while len(out) < size:
        out += rng.choice(words) + b" "
    return bytes(out[:size])


def test_no_filter_copies(filters):
    data = b"BT /F1 12 Tf (Hello) Tj ET"
    assert filters.decode(data, b"<< /Length 26 >>") == (OK, data)
    assert filters.decode(data, b"<< /Filter [] >>") == (OK, data)


@pytest.mark.parametrize("size", (0, 1, 1000, 200_000))
def test_flate(filters, size):
    data = text(size, seed=size) + random.Random(size).randbytes(size // 10)
    assert filters.decode(zlib.compress(data), b"<< /Filter /FlateDecode >>") == (OK, data)


def test_flate_damaged_or_cut_keeps_what_came_before(filters):
    data = text(20_000, seed=3)
    stream = zlib.compress(data)
    status, output = filters.decode(stream[: len(stream) // 2], b"<</Filter/FlateDecode>>")
    assert status == DAMAGED and 0 < len(output) < len(data) and data.startswith(output)
    damaged = stream[:-4] + bytes(b ^ 0xFF for b in stream[-4:])
    status, output = filters.decode(damaged, b"<</Filter/FlateDecode>>")
    assert status == DAMAGED and output == data


def png_rows(rows: list[bytes], kinds: list[int], bpp: int) -> bytes:
    out, prev = bytearray(), bytes(len(rows[0]))
    for row, kind in zip(rows, kinds):
        out += bytes([kind]) + _filter(kind, row, prev, bpp)
        prev = row
    return bytes(out)


@pytest.mark.parametrize("colors, bpc, columns", ((3, 8, 17), (1, 8, 40), (4, 8, 5),
                                                  (1, 1, 37), (2, 16, 9)))
def test_flate_with_the_png_predictors(filters, colors, bpc, columns):
    rng = random.Random(colors * 100 + bpc + columns)
    row_bytes = (colors * bpc * columns + 7) // 8
    bpp = max(1, (colors * bpc + 7) // 8)
    rows = [bytes(rng.randrange(256) for _ in range(row_bytes)) for _ in range(23)]
    kinds = [i % 5 for i in range(23)]
    parms = (f"<< /Predictor 15 /Colors {colors} /BitsPerComponent {bpc} "
             f"/Columns {columns} >>").encode()
    stream = zlib.compress(png_rows(rows, kinds, bpp))
    status, output = filters.decode(stream, b"<< /Filter /FlateDecode /DecodeParms " + parms
                                    + b" >>")
    assert (status, output) == (OK, b"".join(rows))


def test_a_png_row_with_no_filter_png_defines_is_damage(filters):
    stream = zlib.compress(b"\x00abc" + b"\x07def")
    status, output = filters.decode(
        stream, b"<< /Filter /FlateDecode /DecodeParms << /Predictor 12 /Columns 3 >> >>")
    assert status == DAMAGED and output.startswith(b"abc")


def test_flate_with_the_tiff_predictor(filters):
    rng = random.Random(5)
    columns, colors = 11, 3
    rows = [bytes(rng.randrange(256) for _ in range(columns * colors)) for _ in range(9)]
    encoded = bytearray()
    for row in rows:
        encoded += bytes((row[i] - (row[i - colors] if i >= colors else 0)) & 255
                         for i in range(len(row)))
    parms = f"<< /Predictor 2 /Colors {colors} /Columns {columns} >>".encode()
    status, output = filters.decode(zlib.compress(bytes(encoded)),
                                    b"<< /Filter /FlateDecode /DecodeParms " + parms + b" >>")
    assert (status, output) == (OK, b"".join(rows))


def test_ascii_hex(filters):
    data = random.Random(6).randbytes(500)
    encoded = " ".join(f"{b:02X}" if i % 2 else f"{b:02x}" for i, b in enumerate(data))
    assert filters.decode(encoded.encode() + b">", b"<</Filter/ASCIIHexDecode>>") == (OK, data)
    assert filters.decode(b"41 4>", b"<</Filter/ASCIIHexDecode>>") == (OK, b"A@")
    assert filters.decode(b"41 4G 42>", b"<</Filter/ASCIIHexDecode>>") == (DAMAGED, b"A")


@pytest.mark.parametrize("size", (0, 1, 2, 3, 4, 5, 999))
def test_ascii85(filters, size):
    data = random.Random(size).randbytes(size) + bytes(8) + b"tail"[: size % 4]
    encoded = base64.a85encode(data, wrapcol=40) + b"~>"
    assert filters.decode(encoded, b"<< /Filter /ASCII85Decode >>") == (OK, data)


def test_ascii85_damage(filters):
    assert filters.decode(b"87cURD]i,\"Ebo80{~>", b"<</Filter/A85>>")[0] == DAMAGED


def run_length(data: bytes) -> bytes:
    out, i = bytearray(), 0
    while i < len(data):
        run = 1
        while i + run < len(data) and run < 128 and data[i + run] == data[i]:
            run += 1
        if run > 1:
            out += bytes([257 - run, data[i]])
            i += run
        else:
            start = i
            while i < len(data) and i - start < 128 and (
                    i + 1 >= len(data) or data[i + 1] != data[i]):
                i += 1
            out += bytes([i - start - 1]) + data[start:i]
    return bytes(out) + b"\x80"


def test_run_length(filters):
    data = b"aaaaaaaaab" + bytes(300) + random.Random(7).randbytes(400) + b"zz"
    assert filters.decode(run_length(data), b"<< /Filter /RunLengthDecode >>") == (OK, data)
    assert filters.decode(b"\x05ab", b"<< /Filter /RL >>")[0] == DAMAGED


def lzw_encode(data: bytes, early: int) -> bytes:
    """LZW as PDF 32000-1 section 7.4.4 describes it.  The decoder adds each
    code to its table one code after the encoder does, so the encoder widens
    its codes one code later than its own table would say."""

    bits, width = [], 9

    def emit(code: int) -> None:
        bits.append((code, width))

    def reset() -> dict[bytes, int]:
        return {bytes([i]): i for i in range(256)}

    table, next_code = reset(), 258
    emit(256)
    w = b""
    for byte in data:
        wc = w + bytes([byte])
        if wc in table:
            w = wc
            continue
        emit(table[w])
        table[wc] = next_code
        next_code += 1
        if next_code + early - 1 in (512, 1024, 2048):
            width += 1
        if next_code >= 4093:
            emit(256)
            table, next_code, width = reset(), 258, 9
        w = bytes([byte])
    if w:
        emit(table[w])
    emit(257)
    value, count = 0, 0
    for code, size in bits:
        value = (value << size) | code
        count += size
    count_pad = (-count) % 8
    return (value << count_pad).to_bytes((count + count_pad) // 8, "big")


def test_lzw_the_reference_example(filters):
    # PDF 32000-1 section 7.4.4.2: "-----A---B" is codes 256 45 258 258 65
    # 259 66 257 in nine bits each.
    codes = [256, 45, 258, 258, 65, 259, 66, 257]
    value = 0
    for code in codes:
        value = (value << 9) | code
    stream = (value << 0).to_bytes(9, "big")
    assert filters.decode(stream, b"<< /Filter /LZWDecode >>") == (OK, b"-----A---B")


@pytest.mark.parametrize("early", (1, 0))
def test_lzw_through_every_code_width(filters, early):
    data = text(60_000, seed=8) + random.Random(8).randbytes(9_000)
    parms = f"<< /EarlyChange {early} >>".encode()
    status, output = filters.decode(lzw_encode(data, early),
                                    b"<< /Filter /LZWDecode /DecodeParms " + parms + b" >>")
    assert (status, output) == (OK, data)


def test_lzw_against_pillow_s_tiff_strips(filters):
    from PIL import TiffImagePlugin  # noqa: F401

    rng = random.Random(9)
    width, height = 97, 61
    pixels = bytes(rng.choice((0, 0, 0, 40, 200, rng.randrange(256))) for _ in range(width * height))
    image = Image.frombytes("L", (width, height), pixels)
    buffer = io.BytesIO()
    image.save(buffer, "TIFF", compression="tiff_lzw")
    tiff = Image.open(io.BytesIO(buffer.getvalue()))
    offsets, counts = tiff.tag_v2[273], tiff.tag_v2[279]
    raw = buffer.getvalue()
    decoded = bytearray()
    for offset, count in zip(offsets, counts):
        status, output = filters.decode(raw[offset:offset + count], b"<< /Filter /LZWDecode >>")
        assert status == OK
        decoded += output
    assert bytes(decoded) == pixels


def test_a_chain_of_filters_with_their_parameters(filters):
    rows = [bytes(range(i, i + 12)) for i in range(10)]
    stream = base64.a85encode(zlib.compress(png_rows(rows, [2] * 10, 3))) + b"~>"
    dictionary = (b"<< /Filter [ /ASCII85Decode /FlateDecode ] /DecodeParms [ null "
                  b"<< /Predictor 12 /Colors 3 /Columns 4 >> ] >>")
    assert filters.decode(stream, dictionary) == (OK, b"".join(rows))
    hexed = zlib.compress(b"inline").hex().encode() + b">"
    assert filters.decode(hexed, b"<< /F [/AHx /Fl] >>") == (OK, b"inline")


def test_unsupported_filters(filters):
    assert filters.decode(b"\xff\xd8\xff", b"<< /Filter /DCTDecode >>")[0] == UNSUPPORTED
    assert filters.decode(b"x", b"<< /Filter [/FlateDecode /JBIG2Decode] >>")[0] in (
        UNSUPPORTED, DAMAGED)
    assert filters.decode(b"x", b"<< /Filter 5 >>")[0] == UNSUPPORTED


def test_a_budget_the_output_passes_is_memory(filters):
    data = bytes(500_000)
    status, output = filters.decode(zlib.compress(data), b"<< /Filter /FlateDecode >>",
                                    budget=100_000)
    assert (status, output) == (MEMORY, b"")
