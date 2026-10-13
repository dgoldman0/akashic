#!/usr/bin/env python3
"""Akashic pdf/font.f: the characters and widths of a PDF font's codes.

Fonts are written by hand into small files: standard fonts in WinAnsi,
MacRoman, Standard and Symbol with their metrics' widths; /Differences
through glyph names (known names, uniXXXX, uXXXXX, ligatures joined by
underscores, suffixes, .notdef and names nobody knows); a ToUnicode map
over an encoding; /Widths with /FirstChar and /MissingWidth; a Type 3
font scaled by its matrix; composite fonts with Identity, an embedded
CMap, UCS-2, UTF-16 and a named CMap read through the ToUnicode map's
codespace, with /W and /DW; styles from the descriptor and the name; and
an embedded Type 1 program's own encoding.  Every byte is given back.
"""

from __future__ import annotations

import zlib

import pytest

from forth_dependencies import dependency_order
from test_pdf_cmap import XELATEX
from test_pdf_file import stream_object, write_pdf
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, DAMAGED = 0, 1, 2
REF = 9
TRUE = (1 << 64) - 1
BOLD, ITALIC, FIXED, SERIF, VERTICAL = 1, 2, 4, 8, 16
FILE_BYTES = 1 << 20

PRELUDE = f"""
{FILE_BYTES} XBUF FN-BYTES
256 XBUF FN-KEY
CREATE FN-SRCS MEDSRC-SIZE 7 + ALLOT  : FN-SRC  FN-SRCS 7 + -8 AND ;
CREATE FN-MSRCS MSRC-SIZE 7 + ALLOT  : FN-MSRC  FN-MSRCS 7 + -8 AND ;
CREATE FN-FILES PDF-FILE-SIZE 7 + ALLOT  : FN-FILE  FN-FILES 7 + -8 AND ;
CREATE FN-FONTS PDF-FONT-SIZE 7 + ALLOT  : FN-FONT  FN-FONTS 7 + -8 AND ;
CREATE FN-BUFS PDF-BUF-SIZE 7 + ALLOT  : FN-BUF  FN-BUFS 7 + -8 AND ;
: FN-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: FN-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: FN-OPEN  ( u -- status )
    FN-BYTES SWAP FN-SRC MEDSRC-MEMORY
    ['] FN-ALLOC ['] FN-FREE 0 0 FN-MSRC MSRC-INIT
    FN-SRC FN-MSRC FN-FILE PDF-OPEN ;
: FN-CLOSE  ( -- held )  FN-FILE PDF-CLOSE FN-MSRC MSRC-HELD@ ;
: FN-LOAD  ( u -- status )  FN-KEY SWAP 9 FN-FILE FN-FONT PDF-FONT-LOAD ;
: FN-UNLOAD  ( -- )  FN-FONT PDF-FONT-FREE ;
: FN-TEXT  ( code -- ok? a u )
    FN-BUF PDF-BUF-SIZE 0 FILL  FN-FONT FN-BUF PDF-FONT-TEXT+
    FN-BUF PDF-BUF.A @ FN-BUF PDF-BUF.U @ ;
: FN-TEXT-FREE  ( -- )  FN-BUF FN-MSRC PDF-BUF-FREE ;
: FN-WIDTH  ( code -- w )  FN-FONT PDF-FONT-WIDTH ;
: FN-NEXT  ( a u -- a' u' code n )  FN-FONT PDF-FONT-NEXT ;
: FN-STYLE  ( -- flags )  FN-FONT PDF-FONT-STYLE ;
"""


class Fonts:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=64 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/font.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-font",
                              step_budget=400_000_000)
        self.runtime.drain_uart_output()
        self.bytes = self.word("FN-BYTES")
        self.key = self.word("FN-KEY")

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

    def load(self, objects: dict[int, bytes], font: int = 10) -> int:
        """Open a file of OBJECTS and load the font object FONT."""

        objects = {1: b"<< /Type /Catalog /Pages 2 0 R >>",
                   2: b"<< /Type /Pages /Kids [] /Count 0 >>", **objects}
        pdf = write_pdf(objects)
        self.runtime.memory.write_bytes(self.bytes, pdf)
        assert self.call("FN-OPEN", len(pdf)) == (OK,)
        ref = b"%d 0 R" % font
        self.runtime.memory.write_bytes(self.key, ref)
        return self.call("FN-LOAD", len(ref))[0]

    def done(self) -> None:
        self.call("FN-UNLOAD")
        assert self.call("FN-CLOSE") == (0,)

    def text(self, code: int) -> str:
        ok, a, u = self.call("FN-TEXT", code)
        assert ok == TRUE
        data = self.runtime.memory.read_bytes(a, u) if a else b""
        self.call("FN-TEXT-FREE")
        return data.decode("utf-8")

    def width(self, code: int) -> int:
        (w,) = self.call("FN-WIDTH", code)
        return w - (1 << 64) if w >= 1 << 63 else w

    def codes(self, data: bytes) -> list[tuple[int, int]]:
        """The codes a shown string holds, with their lengths."""

        self.runtime.memory.write_bytes(self.key, data)
        a, u, out = self.key, len(data), []
        while u:
            a, u, code, n = self.call("FN-NEXT", a, u)
            out.append((code, n))
        return out

    def style(self) -> int:
        return self.call("FN-STYLE")[0]


@pytest.fixture(scope="module")
def fonts():
    return Fonts()


def test_helvetica_in_winansi(fonts):
    assert fonts.load({10: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
                           b"/Encoding /WinAnsiEncoding >>"}) == OK
    assert [fonts.text(c) for c in b"Hi \x80\x93\x94\xe9"] == list("Hi €“”é")
    assert [fonts.width(c) for c in b"AW i"] == [667, 944, 278, 222]
    assert fonts.width(0x80) == 556
    assert fonts.codes(b"ab") == [(0x61, 1), (0x62, 1)]
    assert fonts.style() == 0
    fonts.done()


def test_standard_encoding_and_ligatures(fonts):
    assert fonts.load({10: b"<< /Type /Font /Subtype /Type1 /BaseFont /Times-Bold >>"}) == OK
    assert fonts.text(0x27) == "’" and fonts.text(0x60) == "‘"
    assert fonts.text(0xAE) == "fi" and fonts.text(0xAF) == "fl"
    assert fonts.text(0x80) == "�"
    assert fonts.width(ord("A")) == 722 and fonts.width(0x20) == 250
    assert fonts.style() & BOLD
    fonts.done()


def test_macroman_symbol_and_courier(fonts):
    assert fonts.load({10: b"<< /Type /Font /Subtype /Type1 /BaseFont /Times-Italic "
                           b"/Encoding /MacRomanEncoding >>"}) == OK
    assert fonts.text(0x8E) == "é" and fonts.text(0xD0) == "–"
    assert fonts.style() & ITALIC
    fonts.done()
    assert fonts.load({10: b"<< /Type /Font /Subtype /Type1 /BaseFont /Symbol >>"}) == OK
    assert fonts.text(0x61) == "α" and fonts.text(0x57) == "Ω"
    fonts.done()
    assert fonts.load({10: b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold "
                           b"/Encoding /WinAnsiEncoding >>"}) == OK
    assert fonts.width(ord("i")) == 600 and fonts.width(0x20) == 600
    assert fonts.style() & FIXED and fonts.style() & BOLD
    fonts.done()


def test_differences_through_glyph_names(fonts):
    font = (b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding << "
            b"/BaseEncoding /WinAnsiEncoding /Differences [65 /B /uni00C9 /u1F600 /f_i "
            b"/uni00660069 128 /Euro /a.sc /.notdef /gibberish /f_f_l /quoteright /union] >> >>")
    assert fonts.load({10: font}) == OK
    expected = {65: "B", 66: "É", 67: "\U0001F600", 68: "fi", 69: "f", 128: "€", 129: "a",
                130: "�", 131: "�", 132: "ffl", 133: "’", 134: "∪",
                70: "F", 0x93: "“"}
    for code, text in expected.items():
        assert fonts.text(code) == text, hex(code)
    fonts.done()


def test_tounicode_over_an_encoding(fonts):
    tounicode = (b"/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n"
                 b"1 begincodespacerange <00> <FF> endcodespacerange\n"
                 b"2 beginbfchar <41> <0058> <42> <00660066> endbfchar\n"
                 b"1 beginbfchar <43> <> endbfchar\nendcmap end end")
    assert fonts.load({10: b"<< /Type /Font /Subtype /TrueType /BaseFont /ABCDEF+Arial "
                           b"/Encoding /WinAnsiEncoding /ToUnicode 11 0 R >>",
                       11: stream_object(zlib.compress(tounicode), b"/Filter /FlateDecode")}) == OK
    assert fonts.text(0x41) == "X" and fonts.text(0x42) == "ff" and fonts.text(0x43) == ""
    assert fonts.text(0x44) == "D" and fonts.text(0x80) == "€"
    fonts.done()


def test_widths_first_char_and_missing_width(fonts):
    font = (b"<< /Type /Font /Subtype /TrueType /BaseFont /ABCDEF+SomeSans /FirstChar 32 "
            b"/LastChar 35 /Widths 12 0 R /FontDescriptor 11 0 R /Encoding /WinAnsiEncoding >>")
    descriptor = (b"<< /Type /FontDescriptor /FontName /ABCDEF+SomeSans /Flags 32 "
                  b"/MissingWidth 111 /FontWeight 700 /ItalicAngle -12 >>")
    assert fonts.load({10: font, 11: descriptor, 12: b"[250 333.4 500 -20]"}) == OK
    assert [fonts.width(c) for c in range(30, 37)] == [111, 111, 250, 333, 500, -20, 111]
    assert fonts.style() == BOLD | ITALIC
    fonts.done()


def test_type3_scaled_by_its_matrix(fonts):
    font = (b"<< /Type /Font /Subtype /Type3 /FontMatrix [0.01 0 0 0.01 0 0] /FontBBox [0 0 100 100] "
            b"/CharProcs << >> /Encoding << /Type /Encoding /Differences [0 /a /b /c] >> "
            b"/FirstChar 0 /LastChar 2 /Widths [50 60.5 0.25] >>")
    assert fonts.load({10: font}) == OK
    assert [fonts.text(c) for c in range(3)] == ["a", "b", "c"]
    assert [fonts.width(c) for c in range(3)] == [500, 605, 2]
    fonts.done()


def composite(encoding: bytes, extra: bytes = b"", w: bytes = b"") -> dict[int, bytes]:
    return {
        10: b"<< /Type /Font /Subtype /Type0 /BaseFont /ABCDEF+DejaVuSerif-Bold /Encoding "
            + encoding + b" /DescendantFonts [11 0 R] " + extra + b">>",
        11: b"<< /Type /Font /Subtype /CIDFontType2 /BaseFont /ABCDEF+DejaVuSerif-Bold "
            b"/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> "
            b"/FontDescriptor 12 0 R /DW 900 " + w + b">>",
        12: b"<< /Type /FontDescriptor /FontName /ABCDEF+DejaVuSerif-Bold /Flags 6 >>",
    }


def test_identity_with_tounicode_and_w(fonts):
    objects = composite(b"/Identity-H", b"/ToUnicode 13 0 R",
                        b"/W [17 [500 600] 70 72 700 100 [800 800 800 300]]")
    objects[13] = stream_object(XELATEX)
    assert fonts.load(objects) == OK
    assert fonts.codes(b"\x00\x11\x00\x46\x0c\xf2") == [(0x11, 2), (0x46, 2), (0xCF2, 2)]
    assert [fonts.text(c) for c in (0x11, 0x46, 0x4A, 0xCF2, 0xD41)] == [".", "c", "g", "ff", "\U0001D538"]
    assert fonts.text(0x1234) == "�"
    assert [fonts.width(c) for c in (17, 18, 19, 70, 72, 73, 100, 102, 103, 104)] == [
        500, 600, 900, 700, 700, 900, 800, 800, 300, 900]
    assert fonts.style() == BOLD | SERIF
    fonts.done()


def test_an_embedded_encoding(fonts):
    encoding = (b"/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n"
                b"2 begincodespacerange <00> <7F> <8000> <FFFF> endcodespacerange\n"
                b"1 begincidrange <20> <7E> 1 endcidrange\n"
                b"1 begincidrange <8140> <817E> 633 endcidrange\nendcmap end end")
    objects = composite(b"13 0 R", w=b"/W [1 1 250 34 [610] 643 [999]]")
    objects[13] = stream_object(encoding, b"/Type /CMap /CMapName /Test-H")
    assert fonts.load(objects) == OK
    assert fonts.codes(b"A \x81\x4a\x90") == [(0x41, 1), (0x20, 1), (0x814A, 2), (0x90, 1)]
    assert fonts.width(0x20) == 250 and fonts.width(0x41) == 610 and fonts.width(0x42) == 900
    assert fonts.width(0x814A) == 999 and fonts.width(0x8140) == 900
    fonts.done()


def test_unicode_and_named_cmaps(fonts):
    assert fonts.load(composite(b"/UniGB-UCS2-H")) == OK
    assert fonts.codes(b"\x4e\x2d\x00A") == [(0x4E2D, 2), (0x41, 2)]
    assert fonts.text(0x4E2D) == "中" and fonts.width(0x4E2D) == 900
    fonts.done()
    assert fonts.load(composite(b"/UniJIS-UTF16-V")) == OK
    assert fonts.codes(b"\xd8\x3d\xde\x00\x30\x42") == [(0xD83DDE00, 4), (0x3042, 2)]
    assert fonts.text(0xD83DDE00) == "\U0001F600" and fonts.text(0x3042) == "あ"
    assert fonts.style() & VERTICAL
    fonts.done()
    tounicode = (b"begincmap 2 begincodespacerange <00> <80> <8140> <9FFC> endcodespacerange\n"
                 b"2 beginbfchar <41> <0041> <8260> <FF21> endbfchar endcmap")
    objects = composite(b"/90ms-RKSJ-H", b"/ToUnicode 13 0 R")
    objects[13] = stream_object(tounicode)
    assert fonts.load(objects) == OK
    assert fonts.codes(b"A\x82\x60") == [(0x41, 1), (0x8260, 2)]
    assert fonts.text(0x8260) == "Ａ"
    fonts.done()


def test_styles_from_names(fonts):
    for name, style in ((b"ABCDEF+Arial-BoldItalicMT", BOLD | ITALIC),
                        (b"CMBX10", BOLD), (b"CMTI10", ITALIC), (b"CMTT10", FIXED),
                        (b"LMMono10-Regular", FIXED), (b"Helvetica-Oblique", ITALIC),
                        (b"MinionPro-Semibold", BOLD), (b"Palatino-Roman", 0)):
        assert fonts.load({10: b"<< /Type /Font /Subtype /Type1 /BaseFont /" + name + b" >>"}) == OK
        assert fonts.style() == style, name
        fonts.done()


def type1_program(encoding: bytes) -> bytes:
    clear = (b"%!PS-AdobeFont-1.0: CMR10 003.002\n/FontName /CMR10 def\n/PaintType 0 def\n"
             b"/FontMatrix [0.001 0 0 0.001 0 0] readonly def\n" + encoding +
             b"\n/FontBBox {-40 -250 1009 750} readonly def\ncurrentdict end\ncurrentfile eexec\n")
    return clear + bytes(range(256)) * 4


def test_an_embedded_type1_programs_encoding(fonts):
    encoding = (b"/Encoding 256 array\n0 1 255 {1 index exch /.notdef put} for\n"
                b"dup 11 /ff put\ndup 12 /fi put\ndup 65 /A put\ndup 123 /endash put\n"
                b"readonly def")
    font = (b"<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+CMR10 /FirstChar 11 /LastChar 123 "
            b"/Widths [583 556] /FontDescriptor 11 0 R >>")
    descriptor = b"<< /Type /FontDescriptor /FontName /ABCDEF+CMR10 /Flags 4 /FontFile 12 0 R >>"
    program = type1_program(encoding)
    objects = {10: font, 11: descriptor,
               12: stream_object(zlib.compress(program), b"/Filter /FlateDecode /Length1 300 /Length2 1024 /Length3 0")}
    assert fonts.load(objects) == OK
    assert [fonts.text(c) for c in (11, 12, 65, 123, 66)] == ["ff", "fi", "A", "–", "�"]
    assert fonts.width(11) == 583 and fonts.width(12) == 556
    fonts.done()
    objects[12] = stream_object(type1_program(b"/Encoding StandardEncoding def"))
    assert fonts.load(objects) == OK
    assert fonts.text(0x27) == "’" and fonts.text(65) == "A"
    fonts.done()


def test_a_font_that_is_no_dictionary(fonts):
    assert fonts.load({10: b"[1 2 3]"}) == DAMAGED
    fonts.done()
    assert fonts.load({}, font=10) != OK
    fonts.done()
