#!/usr/bin/env python3
"""Akashic pdf/image.f: a PDF's pictures as files a viewer shows.

Pictures written by hand become QOI files the guest writes, checked pixel
for pixel against a Python model: gray, RGB, CMYK and indexed samples of
1 to 16 bits, palettes in strings and streams, /Decode, ICCBased spaces,
soft masks of the same size and smaller, no filter, FlateDecode with no
predictor, the PNG predictors and the TIFF one, and filters in front of
Flate.  A JPEG under its own filter alone is a span of the PDF itself;
one behind another filter is decoded out of it; one RC4 encrypts is
copied out decrypted.  Small budgets make the same files in many steps,
and two pictures made in turns come out whole.  Damaged data, memory
refused and pictures with no file fail cleanly.  Pictures xelatex and
LibreOffice place are read as their sources are.  Every byte is given
back.
"""

from __future__ import annotations

import io
import re
import shutil
import subprocess
import zlib
from pathlib import Path

import pytest
from PIL import Image

import qoi_codec
from forth_dependencies import dependency_order
from test_pdf_file import stream_object, write_pdf
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, DAMAGED, UNSUPPORTED = 0, 1, 2, 3
EMPTY, PENDING, READY, FAILED = 0, 1, 2, 3
F_QOI, F_JPEG = 2, 4
SAMPLES, DCT, JPX, JBIG2, CCITT = 0, 1, 2, 3, 4
FILE_BYTES = 4 << 20
OUT_BYTES = 8 << 20

PRELUDE = f"""
{FILE_BYTES} XBUF IM-BYTES
{OUT_BYTES} XBUF IM-OUT
CREATE IM-SRCS MEDSRC-SIZE 7 + ALLOT  : IM-SRC  IM-SRCS 7 + -8 AND ;
CREATE IM-MSRCS MSRC-SIZE 7 + ALLOT  : IM-MSRC  IM-MSRCS 7 + -8 AND ;
CREATE IM-FILES PDF-FILE-SIZE 7 + ALLOT  : IM-FILE  IM-FILES 7 + -8 AND ;
CREATE IM-IMGS PDF-IMAGE-SIZE 7 + ALLOT  : IM-IMG  IM-IMGS 7 + -8 AND ;
CREATE IM-IMG2S PDF-IMAGE-SIZE 7 + ALLOT  : IM-IMG2  IM-IMG2S 7 + -8 AND ;
CREATE IM-SPANS MEDSRC-SPAN-SIZE 7 + ALLOT  : IM-SPAN  IM-SPANS 7 + -8 AND ;
VARIABLE IM-LIMIT
: IM-ALLOC  ( bytes ctx -- addr|0 )
    DROP DUP IM-LIMIT @ > IF DROP 0 EXIT THEN ALLOCATE IF DROP 0 THEN ;
: IM-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: IM-OPEN  ( u -- status )
    -1 1 RSHIFT IM-LIMIT !
    IM-BYTES SWAP IM-SRC MEDSRC-MEMORY
    ['] IM-ALLOC ['] IM-FREE 0 0 IM-MSRC MSRC-INIT
    IM-IMG PDF-IMAGE-SIZE 0 FILL  IM-IMG2 PDF-IMAGE-SIZE 0 FILL
    IM-SRC IM-MSRC IM-FILE PDF-OPEN ;
: IM-CLOSE  ( -- held )
    IM-IMG PDF-IMAGE-FREE  IM-IMG2 PDF-IMAGE-FREE  IM-FILE PDF-CLOSE  IM-MSRC MSRC-HELD@ ;
: IM-IMAGE  ( num img -- status )  DUP PDF-IMAGE-FREE  IM-FILE SWAP PDF-IMAGE-OPEN ;
: IM-FACTS  ( img -- w h coding format state reason )
    >R R@ PDF-IMAGE-WIDTH R@ PDF-IMAGE-HEIGHT R@ PDF-IMAGE-CODING R@ PDF-IMAGE-FORMAT
    R@ PDF-IMAGE-STATE@ R> PDF-IMAGE-REASON@ ;
: IM-RUN  ( budget img -- steps state )
    0 BEGIN 2 PICK 2 PICK PDF-IMAGE-STEP DUP PIC-ST-PENDING = WHILE DROP 1+ REPEAT
    >R NIP NIP R> ;
: IM-STEPS  ( n budget img -- state )
    ROT 0 ?DO 2DUP PDF-IMAGE-STEP DROP LOOP NIP PDF-IMAGE-STATE@ ;
: IM-TURNS  ( budget -- steps )
    0 BEGIN
        OVER IM-IMG PDF-IMAGE-STEP PIC-ST-PENDING =
        2 PICK IM-IMG2 PDF-IMAGE-STEP PIC-ST-PENDING = OR
    WHILE 1+ REPEAT NIP ;
: IM-FILE@  ( img -- u ior )
    IM-SPAN PDF-IMAGE-SOURCE
    IM-SPAN MEDSRC-SIZE@  IM-OUT OVER 0 IM-SPAN MEDSRC-READ?  IM-SPAN MEDSRC-RELEASE ;
"""


class Images:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=64 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/image.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-image",
                              step_budget=600_000_000)
        self.runtime.drain_uart_output()
        self.bytes = self.word("IM-BYTES")
        self.out = self.word("IM-OUT")
        self.limit = self.word("IM-LIMIT")
        self.img = self.word("IM-IMG")
        self.img2 = self.word("IM-IMG2")

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

    def open(self, pdf: bytes) -> None:
        assert len(pdf) <= FILE_BYTES
        self.runtime.memory.write_bytes(self.bytes, pdf)
        assert self.call("IM-OPEN", len(pdf)) == (OK,)

    def close(self) -> None:
        assert self.call("IM-CLOSE") == (0,)

    def refuse_above(self, size: int) -> None:
        self.runtime.memory.write_bytes(self.limit, size.to_bytes(8, "little"))

    def facts(self, img: int | None = None) -> tuple[int, ...]:
        return self.call("IM-FACTS", self.img if img is None else img)

    def run(self, num: int, budget: int = 1 << 30) -> tuple[int, int]:
        assert self.call("IM-IMAGE", num, self.img) == (OK,)
        return self.call("IM-RUN", budget, self.img)

    def file(self, img: int | None = None) -> bytes:
        size, ior = self.call("IM-FILE@", self.img if img is None else img)
        assert ior == 0
        return self.runtime.memory.read_bytes(self.out, size)

    def pixels(self, num: int, budget: int = 1 << 30) -> list[list[tuple[int, int, int, int]]]:
        _, state = self.run(num, budget)
        assert state == READY, self.facts()
        _, _, rows = qoi_codec.decode(self.file())
        return rows


@pytest.fixture(scope="module")
def images():
    return Images()


def picture(data: bytes, entries: bytes) -> bytes:
    return stream_object(data, b"/Type /XObject /Subtype /Image " + entries)


def document(pictures: dict[int, bytes]) -> bytes:
    """A page whose resources name every picture, so a writer keeps them."""
    names = b" ".join(b"/Im%d %d 0 R" % (num, num) for num, body in sorted(pictures.items())
                      if b"/Subtype /Image" in body)
    objects = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << "
           + names + b" >> >> >>",
    }
    objects.update(pictures)
    return write_pdf(objects)


def png_filtered(rows: list[bytes], bpp: int, kinds: list[int]) -> bytes:
    out, prev = bytearray(), bytes(len(rows[0]))
    for row, kind in zip(rows, kinds):
        line = bytearray(row)
        for i in range(len(row)):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if kind == 1:
                line[i] = (row[i] - a) & 255
            elif kind == 2:
                line[i] = (row[i] - b) & 255
            elif kind == 3:
                line[i] = (row[i] - (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                predicted = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (row[i] - predicted) & 255
        out += bytes([kind]) + line
        prev = row
    return bytes(out)


def tiff_differenced(rows: list[bytes], colors: int) -> bytes:
    out = bytearray()
    for row in rows:
        out += bytes(row[i] if i < colors else (row[i] - row[i - colors]) & 255
                     for i in range(len(row)))
    return bytes(out)


def rgb_rows(width: int, height: int) -> list[bytes]:
    return [bytes(channel for x in range(width)
                  for channel in ((x * 37 + y * 11) & 255, (x * x + y * 5) & 255, (x * 3 + y * y) & 255))
            for y in range(height)]


def opaque(rows: list[bytes], width: int) -> list[list[tuple[int, int, int, int]]]:
    return [[(row[3 * x], row[3 * x + 1], row[3 * x + 2], 255) for x in range(width)] for row in rows]


def packed(samples: list[list[int]], bits: int) -> list[bytes]:
    """Rows of samples of BITS bits each, packed most significant first."""
    out = []
    for row in samples:
        value, count = 0, 0
        for sample in row:
            value = (value << bits) | sample
            count += bits
        pad = (-count) % 8
        out.append((value << pad).to_bytes((count + pad) // 8, "big") if count else b"")
    return out


def test_rgb_samples_with_each_flate_shape(images):
    width, height = 13, 9
    rows = rgb_rows(width, height)
    data = b"".join(rows)
    base = b"/Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 " % (width, height)
    kinds = [0, 1, 2, 3, 4, 4, 3, 2, 1]
    pdf = document({
        10: picture(zlib.compress(data), base + b"/Filter /FlateDecode"),
        11: picture(data, base),
        12: picture(zlib.compress(png_filtered(rows, 3, kinds)),
                    base + b"/Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 3 /Columns %d >>" % width),
        13: picture(zlib.compress(tiff_differenced(rows, 3)),
                    base + b"/Filter [/FlateDecode] /DecodeParms [<< /Predictor 2 /Colors 3 /Columns %d >>]" % width),
        14: picture(zlib.compress(data).hex().encode() + b">",
                    base + b"/Filter [/ASCIIHexDecode /FlateDecode]"),
    })
    images.open(pdf)
    for num in (10, 11, 12, 13, 14):
        assert images.pixels(num) == opaque(rows, width), num
        w, h, coding, form, state, reason = images.facts()
        assert (w, h, coding, form, state) == (width, height, SAMPLES, F_QOI, READY)
        assert images.file()[12] == 3          # three channels: no mask
    images.close()


def test_small_budgets_and_pictures_in_turns(images):
    width, height = 21, 17
    rows = rgb_rows(width, height)
    grey = [bytes((x * 7 + y * 13) & 255 for x in range(width)) for y in range(height)]
    pdf = document({
        10: picture(zlib.compress(png_filtered(rows, 3, [4] * height)),
                    b"/Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 "
                    b"/Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 3 /Columns %d >>"
                    % (width, height, width)),
        11: picture(zlib.compress(b"".join(grey)),
                    b"/Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode"
                    % (width, height)),
    })
    images.open(pdf)
    steps, state = images.run(10, budget=1)
    assert state == READY and steps == height - 1
    one = images.file()
    assert images.call("IM-IMAGE", 10, images.img) == (OK,)
    assert images.call("IM-IMAGE", 11, images.img2) == (OK,)
    assert images.call("IM-TURNS", 5)[0] >= height - 1
    assert images.file() == one
    _, _, theirs = qoi_codec.decode(images.file(images.img2))
    assert theirs == [[(v, v, v, 255) for v in row] for row in grey]
    # Given back halfway, a picture holds nothing.
    assert images.call("IM-IMAGE", 10, images.img) == (OK,)
    assert images.call("IM-STEPS", 3, 1, images.img) == (PENDING,)
    assert images.call("IM-IMAGE", 11, images.img2) == (OK,)
    assert images.call("IM-STEPS", 2, 1, images.img2) == (PENDING,)
    images.close()


def test_gray_cmyk_icc_and_sixteen_bits(images):
    width, height = 9, 4
    grey = [[(x * 29 + y * 61) & 255 for x in range(width)] for y in range(height)]
    cmyk = [[((x * 40) & 255, (y * 70) & 255, (x * y * 9) & 255, (x * 17) & 255) for x in range(width)]
            for y in range(height)]
    wide = [[((x * 7919 + y * 104729) & 0xFFFF, (x * 31337) & 0xFFFF, (y * 4099 + x) & 0xFFFF)
             for x in range(width)] for y in range(height)]
    entries = b"/Width %d /Height %d " % (width, height)
    pdf = document({
        10: picture(bytes(v for row in grey for v in row),
                    entries + b"/ColorSpace /DeviceGray /BitsPerComponent 8"),
        11: picture(bytes(v for row in cmyk for p in row for v in p),
                    entries + b"/ColorSpace /DeviceCMYK /BitsPerComponent 8"),
        12: picture(bytes(v for row in grey for v in row),
                    entries + b"/ColorSpace [/ICCBased 20 0 R] /BitsPerComponent 8 /Decode [1 0]"),
        13: picture(b"".join(v.to_bytes(2, "big") for row in wide for p in row for v in p),
                    entries + b"/ColorSpace [/CalRGB << /WhitePoint [1 1 1] >>] /BitsPerComponent 16"),
        20: stream_object(b"icc", b"/N 1"),
    })
    images.open(pdf)
    assert images.pixels(10) == [[(v, v, v, 255) for v in row] for row in grey]

    def ink(v: int, k: int) -> int:
        return 255 - min(255, v + k)

    assert images.pixels(11) == [[(ink(c, k), ink(m, k), ink(y, k), 255) for c, m, y, k in row]
                                 for row in cmyk]
    assert images.pixels(12) == [[(255 - v, 255 - v, 255 - v, 255) for v in row] for row in grey]
    assert images.pixels(13) == [[(r >> 8, g >> 8, b >> 8, 255) for r, g, b in row] for row in wide]
    images.close()


def test_small_samples_and_palettes(images):
    width, height = 11, 5
    bits1 = [[(x + y) % 2 for x in range(width)] for y in range(height)]
    bits2 = [[(x * 3 + y) % 4 for x in range(width)] for y in range(height)]
    bits4 = [[(x * 5 + y * 3) % 16 for x in range(width)] for y in range(height)]
    palette = bytes(channel for i in range(16) for channel in (i * 16, 255 - i * 9, (i * 77) & 255))
    grey_palette = bytes((0, 90, 180, 250))
    entries = b"/Width %d /Height %d " % (width, height)
    pdf = document({
        10: picture(b"".join(packed(bits1, 1)),
                    entries + b"/ColorSpace /DeviceGray /BitsPerComponent 1 /Decode [1 0]"),
        11: picture(b"".join(packed(bits2, 2)),
                    entries + b"/ColorSpace /DeviceGray /BitsPerComponent 2"),
        12: picture(zlib.compress(b"".join(packed(bits4, 4))),
                    entries + b"/ColorSpace [/Indexed /DeviceRGB 15 <" + palette.hex().encode()
                    + b">] /BitsPerComponent 4 /Filter /FlateDecode"),
        13: picture(b"".join(packed(bits2, 2)),
                    entries + b"/ColorSpace [/Indexed /DeviceGray 3 21 0 R] /BitsPerComponent 2"),
        14: picture(b"".join(packed(bits4, 4)),
                    entries + b"/ColorSpace [/Indexed /DeviceRGB 5 <" + palette[:18].hex().encode()
                    + b">] /BitsPerComponent 4"),
        21: stream_object(zlib.compress(grey_palette), b"/Filter /FlateDecode"),
    })
    images.open(pdf)
    assert images.pixels(10) == [[(0, 0, 0, 255) if v else (255, 255, 255, 255) for v in row]
                                 for row in bits1]
    assert images.pixels(11) == [[(v * 85,) * 3 + (255,) for v in row] for row in bits2]
    assert images.pixels(12) == [[tuple(palette[3 * v:3 * v + 3]) + (255,) for v in row] for row in bits4]
    assert images.pixels(13) == [[(grey_palette[v],) * 3 + (255,) for v in row] for row in bits2]
    # Indexes past the top index take the last entry.
    assert images.pixels(14) == [[tuple(palette[3 * min(v, 5):3 * min(v, 5) + 3]) + (255,) for v in row]
                                 for row in bits4]
    images.close()


def test_soft_masks(images):
    width, height = 12, 8
    rows = rgb_rows(width, height)
    same = [[(x * 20 + y * 7) & 255 for x in range(width)] for y in range(height)]
    small = [[(x * 60 + y * 90) & 255 for x in range(4)] for y in range(3)]
    entries = b"/Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode " % (
        width, height)
    pdf = document({
        10: picture(zlib.compress(b"".join(rows)), entries + b"/SMask 20 0 R"),
        11: picture(zlib.compress(b"".join(rows)), entries + b"/SMask 21 0 R"),
        20: picture(zlib.compress(bytes(v for row in same for v in row)),
                    b"/Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode"
                    % (width, height)),
        21: picture(bytes(v for row in small for v in row),
                    b"/Width 4 /Height 3 /ColorSpace /DeviceGray /BitsPerComponent 8"),
    })
    images.open(pdf)
    base = opaque(rows, width)
    assert images.pixels(10) == [[p[:3] + (same[y][x],) for x, p in enumerate(row)]
                                 for y, row in enumerate(base)]
    assert images.file()[12] == 4
    assert images.pixels(11) == [[p[:3] + (small[y * 3 // height][x * 4 // width],) for x, p in enumerate(row)]
                                 for y, row in enumerate(base)]
    images.close()


def jpeg(width: int = 24, height: int = 16) -> bytes:
    picture_ = Image.new("RGB", (width, height))
    picture_.putdata([((x * 9) & 255, (y * 15) & 255, 128) for y in range(height) for x in range(width)])
    out = io.BytesIO()
    picture_.save(out, "JPEG", quality=90)
    return out.getvalue()


def test_jpegs_are_spans_or_decoded_out(images):
    data = jpeg()
    entries = b"/Width 24 /Height 16 /ColorSpace /DeviceRGB /BitsPerComponent 8 "
    pdf = document({
        10: picture(data, entries + b"/Filter /DCTDecode"),
        11: picture(data.hex().encode() + b">", entries + b"/Filter [/AHx /DCT]"),
    })
    images.open(pdf)
    assert images.call("IM-IMAGE", 10, images.img) == (OK,)
    assert images.facts() == (24, 16, DCT, F_JPEG, READY, OK)
    assert images.file() == data
    steps, state = images.run(11)
    assert state == READY and images.file() == data
    images.close()


@pytest.mark.skipif(shutil.which("qpdf") is None, reason="qpdf is not installed")
def test_an_encrypted_jpeg_is_copied_out_decrypted(images, tmp_path):
    data = jpeg(40, 30)
    width, height = 9, 4
    grey = bytes((x * 29 + y * 61) & 255 for y in range(height) for x in range(width))
    (tmp_path / "in.pdf").write_bytes(document({
        10: picture(data, b"/Width 40 /Height 30 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode"),
        11: picture(zlib.compress(grey), b"/Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8 "
                                         b"/Filter /FlateDecode" % (width, height)),
    }))
    subprocess.run(["qpdf", "--allow-weak-crypto", "--object-streams=disable", "--encrypt", "", "owner",
                    "128", "--use-aes=n", "--", str(tmp_path / "in.pdf"), str(tmp_path / "out.pdf")],
                   check=True, capture_output=True)
    pdf = (tmp_path / "out.pdf").read_bytes()
    found = {}
    for match in re.finditer(rb"(\d+) 0 obj\s*<<((?:(?!endobj).)*?)>>\s*stream", pdf, re.S):
        if b"/DCTDecode" in match.group(2):
            found["jpeg"] = int(match.group(1))
        elif b"/DeviceGray" in match.group(2):
            found["grey"] = int(match.group(1))
    images.open(pdf)
    steps, state = images.run(found["jpeg"], budget=1000)
    assert state == READY and steps >= 1
    assert images.file() == data
    assert images.pixels(found["grey"]) == [[(v, v, v, 255) for v in grey[y * width:(y + 1) * width]]
                                            for y in range(height)]
    images.close()


def test_pictures_with_no_file_and_damaged_ones(images):
    entries = b"/Width 8 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 "
    good = zlib.compress(bytes(range(16)))
    pdf = document({
        10: picture(b"jp2", entries + b"/Filter /JPXDecode"),
        11: picture(b"jb2", b"/Width 8 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /JBIG2Decode"),
        12: picture(b"\xff\x00", b"/Width 8 /Height 2 /ImageMask true /BitsPerComponent 1"),
        13: picture(b"lab", b"/Width 1 /Height 1 /ColorSpace [/Lab << >>] /BitsPerComponent 8"),
        14: picture(good[:len(good) // 2], entries + b"/Filter /FlateDecode"),
        15: picture(bytes(10), entries),
        16: picture(good, b"/Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode"),
        17: b"<< /Type /XObject /Subtype /Form /BBox [0 0 1 1] >>",
    })
    images.open(pdf)
    for num, coding in ((10, JPX), (11, JBIG2), (12, SAMPLES), (13, SAMPLES)):
        assert images.call("IM-IMAGE", num, images.img) == (OK,)
        assert images.facts()[2:] == (coding, 0, FAILED, UNSUPPORTED), num
        assert images.call("IM-RUN", 100, images.img) == (0, FAILED)
    assert images.facts()[:2] == (1, 1)
    for num in (14, 15):
        assert images.run(num) == (0, FAILED), num
        assert images.facts()[5] == DAMAGED
    assert images.call("IM-IMAGE", 16, images.img) == (DAMAGED,)
    assert images.call("IM-IMAGE", 17, images.img) == (DAMAGED,)
    images.close()


def test_memory_refused(images):
    width, height = 30, 20
    rows = rgb_rows(width, height)
    pdf = document({
        10: picture(zlib.compress(b"".join(rows)),
                    b"/Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode"
                    % (width, height)),
    })
    images.open(pdf)
    images.refuse_above(2000)
    assert images.run(10) == (0, FAILED)
    assert images.facts()[5] == MEMORY
    images.refuse_above(1 << 40)
    assert images.pixels(10) == opaque(rows, width)
    images.close()


def flatten(path: Path) -> list[list[tuple[int, int, int, int]]]:
    source = Image.open(path).convert("RGBA")
    width, height = source.size
    data = list(source.getdata())
    return [data[y * width:(y + 1) * width] for y in range(height)]


@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_pictures_xelatex_places(images, tmp_path):
    photo = Image.new("RGB", (32, 20))
    photo.putdata([((x * 8) & 255, (y * 12) & 255, (x * y) & 255) for y in range(20) for x in range(32)])
    photo.save(tmp_path / "photo.png")
    clear = Image.new("RGBA", (16, 10))
    clear.putdata([(200, (x * 16) & 255, 40, (y * 25) & 255) for y in range(10) for x in range(16)])
    clear.save(tmp_path / "clear.png")
    (tmp_path / "photo.jpg").write_bytes(jpeg(48, 32))
    (tmp_path / "doc.tex").write_text(
        "\\documentclass{article}\\usepackage{graphicx}\\begin{document}\n"
        "\\includegraphics{photo.png}\\includegraphics{clear.png}\\includegraphics{photo.jpg}\n"
        "\\end{document}\n")
    subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                   capture_output=True, check=True)
    pdf = (tmp_path / "doc.pdf").read_bytes()
    images.open(pdf)
    seen = set()
    for num in range(1, 64):
        if images.call("IM-IMAGE", num, images.img) != (OK,):
            continue
        width, height, coding, form, state, _ = images.facts()
        if (width, height) == (32, 20) and coding == SAMPLES:
            assert images.pixels(num) == flatten(tmp_path / "photo.png")
            seen.add("photo")
        elif (width, height) == (16, 10) and coding == SAMPLES and form == F_QOI:
            ours = images.pixels(num)
            if ours[0][0][3] != 255 or ours[9][0][3] != 255:
                assert ours == flatten(tmp_path / "clear.png")
                seen.add("clear")
        elif (width, height) == (48, 32) and coding == DCT:
            assert state == READY
            assert Image.open(io.BytesIO(images.file())).size == (48, 32)
            seen.add("jpeg")
    assert seen == {"photo", "clear", "jpeg"}, seen
    images.close()


@pytest.mark.skipif(shutil.which("soffice") is None, reason="LibreOffice is not installed")
def test_pictures_libreoffice_places(images, tmp_path):
    photo = Image.new("RGB", (64, 40))
    photo.putdata([((x * 4) & 255, (y * 6) & 255, (x * y) & 255) for y in range(40) for x in range(64)])
    photo.save(tmp_path / "photo.png")
    (tmp_path / "photo.jpg").write_bytes(jpeg(48, 32))
    (tmp_path / "doc.html").write_text(
        '<html><body><p>Pictures:</p><p><img src="photo.png" width="64" height="40">'
        '<img src="photo.jpg" width="48" height="32"></p></body></html>', encoding="utf-8")
    subprocess.run(["soffice", f"-env:UserInstallation=file://{tmp_path}/profile", "--headless",
                    "--convert-to", "pdf", "--outdir", str(tmp_path), str(tmp_path / "doc.html")],
                   check=True, capture_output=True, timeout=120)
    pdf = (tmp_path / "doc.pdf").read_bytes()
    nums = [int(m.group(1)) for m in re.finditer(rb"(\d+) 0 obj\s*<<(?:(?!endobj).)*?/Subtype\s*/Image",
                                                 pdf, re.S)]
    images.open(pdf)
    sizes = set()
    for num in nums:
        assert images.call("IM-IMAGE", num, images.img) == (OK,)
        width, height, coding, form, state, _ = images.facts()
        if form == 0:
            continue
        _, state = images.call("IM-RUN", 1 << 30, images.img)
        assert state == READY, num
        data = images.file()
        if form == F_QOI:
            got_w, got_h, rows = qoi_codec.decode(data)
            assert (got_w, got_h) == (width, height) and len(rows) == height
        else:
            assert Image.open(io.BytesIO(data)).size == (width, height)
        sizes.add((width, height))
    assert {(64, 40), (48, 32)} <= sizes, sizes
    images.close()
