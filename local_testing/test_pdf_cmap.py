#!/usr/bin/env python3
"""Akashic pdf/cmap.f: a font's ToUnicode map, or its embedded encoding.

The maps are checked against what they say: the ToUnicode map xelatex
wrote for a DejaVu Serif subset, with ligatures and a character outside
the BMP; ranges counted up and given as arrays; codes out of order,
overlapping and repeated; empty and literal destinations; the cidchar and
cidrange entries of an encoding; codespace ranges matched byte by byte,
as Shift-JIS has them; and a large map built at random, checked code by
code against a Python model.  A budget the map passes is refused, and
every byte the map takes is given back.
"""

from __future__ import annotations

import random

import pytest

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY = 0, 1
TRUE = (1 << 64) - 1
IN_BYTES = 1 << 20

PRELUDE = f"""
{IN_BYTES} XBUF CT-IN
CREATE CT-MAPS PDF-CMAP-SIZE 7 + ALLOT  : CT-MAP  CT-MAPS 7 + -8 AND ;
CREATE CT-MSRCS MSRC-SIZE 7 + ALLOT  : CT-MSRC  CT-MSRCS 7 + -8 AND ;
: CT-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: CT-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: CT-PARSE  ( u budget -- status )
    >R ['] CT-ALLOC ['] CT-FREE 0 R> CT-MSRC MSRC-INIT
    CT-IN SWAP CT-MSRC CT-MAP PDF-CMAP-PARSE ;
: CT-LOOKUP  ( code -- a n delta true | false )  CT-MAP PDF-CMAP-LOOKUP ;
: CT-BYTES  ( u -- n )  CT-IN SWAP CT-MAP PDF-CMAP-BYTES ;
: CT-HELD  ( -- held )  CT-MSRC MSRC-HELD@ ;
: CT-DONE  ( -- held )  CT-MAP PDF-CMAP-FREE CT-MSRC MSRC-HELD@ ;
: CT-INIT  ( -- )
    ['] CT-ALLOC ['] CT-FREE 0 0 CT-MSRC MSRC-INIT  CT-MSRC CT-MAP PDF-CMAP-INIT ;
: CT-ADD  ( first last value -- ok? )  CT-MAP PDF-CMAP-ADD ;
: CT-SEAL  ( -- )  CT-MAP PDF-CMAP-SEAL ;
"""

# The ToUnicode map xelatex 2024 wrote for a DejaVu Serif subset showing
# "Office affine fluffy — “quoted” café 𝔸 Ωmega. Ligatures: ffi ffl fi fl."
XELATEX = b"""/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CMapName /TTNQZN+DejaVuSerif-UTF16 def
/CMapType 2 def
/CIDSystemInfo <<
  /Registry (Adobe)
  /Ordering (UCS)
  /Supplement 0
>> def
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
9 beginbfchar
<0011> <002E>
<0014> <0031>
<001D> <003A>
<002F> <004C>
<0032> <004F>
<0044> <0061>
<004C> <0069>
<005C> <0079>
<00AB> <00E9>
endbfchar
3 beginbfrange
<0046> <004A> <0063>
<0050> <0052> <006D>
<0054> <0058> <0071>
endbfrange
9 beginbfchar
<0322> <03A9>
<0783> <2014>
<078B> <201C>
<078C> <201D>
<0CF2> <00660066>
<0CF3> <00660069>
<0CF4> <0066006C>
<0CF6> <00660066006C>
<0D41> <D835DD38>
endbfchar
endcmap
CMapName currentdict /CMap defineresource pop
end
end
"""


class Maps:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=64 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/cmap.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-cmap",
                              step_budget=200_000_000)
        self.runtime.drain_uart_output()
        self.input = self.word("CT-IN")

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

    def parse(self, text: bytes, budget: int = 0) -> int:
        assert len(text) <= IN_BYTES
        self.runtime.memory.write_bytes(self.input, text)
        (status,) = self.call("CT-PARSE", len(text), budget)
        return status

    def lookup(self, code: int) -> list[int] | None:
        """The code's values, the last counted up, or None."""

        result = self.call("CT-LOOKUP", code)
        if result == (0,):
            return None
        a, n, delta, flag = result
        assert flag == TRUE
        raw = self.runtime.memory.read_bytes(a, 4 * n) if n else b""
        values = [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]
        if values:
            values[-1] += delta
        return values

    def raw(self, code: int) -> tuple[list[int], int] | None:
        """The code's values as stored, and its delta, or None."""

        result = self.call("CT-LOOKUP", code)
        if result == (0,):
            return None
        a, n, delta, _ = result
        raw = self.runtime.memory.read_bytes(a, 4 * n) if n else b""
        return [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)], delta

    def text(self, code: int) -> str | None:
        values = self.lookup(code)
        return None if values is None else "".join(map(chr, values))

    def code_bytes(self, data: bytes) -> int:
        self.runtime.memory.write_bytes(self.input, data)
        (n,) = self.call("CT-BYTES", len(data))
        return n

    def done(self) -> None:
        assert self.call("CT-DONE") == (0,)


@pytest.fixture(scope="module")
def maps():
    return Maps()


def cmap(*sections: str, codespace: str = "<0000> <FFFF>") -> bytes:
    head = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n"
    if codespace:
        head += f"1 begincodespacerange {codespace} endcodespacerange\n"
    return (head + "\n".join(sections) + "\nendcmap end end\n").encode()


def test_xelatex_map(maps):
    assert maps.parse(XELATEX) == OK
    assert maps.text(0x0011) == "."
    assert maps.text(0x00AB) == "é"
    assert maps.text(0x0046) == "c" and maps.text(0x004A) == "g"
    assert maps.text(0x0056) == "s" and maps.text(0x0058) == "u"
    assert maps.text(0x0322) == "Ω" and maps.text(0x0783) == "—"
    assert maps.text(0x0CF2) == "ff" and maps.text(0x0CF6) == "ffl"
    assert maps.text(0x0D41) == "\U0001D538"
    for missing in (0x0000, 0x0010, 0x0012, 0x004B, 0x0053, 0x0059, 0x0CF5, 0xFFFF):
        assert maps.lookup(missing) is None
    assert maps.code_bytes(b"\x00\x11\x00\x46") == 2
    assert maps.code_bytes(b"\x00") == 1
    maps.done()


def test_ranges_count_up_and_take_arrays(maps):
    text = cmap("2 beginbfrange",
                "<20> <7E> <0020>",
                "<A0> <A3> [<00660069> <D83DDE00> <0041> (\\000B)]",
                "endbfrange",
                "1 beginbfrange <0100> <0102> <00660066> endbfrange",
                codespace="<00> <FF>")
    assert maps.parse(text) == OK
    assert maps.text(0x20) == " " and maps.text(0x41) == "A" and maps.text(0x7E) == "~"
    assert maps.text(0x7F) is None
    assert [maps.text(code) for code in range(0xA0, 0xA4)] == ["fi", "\U0001F600", "A", "B"]
    # A string destination of several characters counts up its last.
    assert [maps.text(code) for code in (0x100, 0x101, 0x102)] == ["ff", "fg", "fh"]
    maps.done()


def test_short_array_leaves_the_rest_unmapped(maps):
    text = cmap("1 beginbfrange <0010> <0015> [<0041> <0042>] endbfrange")
    assert maps.parse(text) == OK
    assert maps.text(0x10) == "A" and maps.text(0x11) == "B"
    assert maps.lookup(0x12) is None and maps.lookup(0x15) is None
    maps.done()


def test_out_of_order_overlapping_and_repeated(maps):
    text = cmap("3 beginbfchar <0030> <0031> <0015> <0058> <0005> <0061> endbfchar",
                "1 beginbfrange <0010> <0020> <0041> endbfrange",
                "2 beginbfchar <0030> <0032> <0001> <0062> endbfchar")
    assert maps.parse(text) == OK
    assert maps.text(0x01) == "b" and maps.text(0x05) == "a"
    assert maps.text(0x10) == "A" and maps.text(0x14) == "E"
    # A character inside a range wins there; the range holds either side.
    assert maps.text(0x15) == "X" and maps.text(0x16) == "G" and maps.text(0x20) == "Q"
    assert maps.lookup(0x21) is None and maps.lookup(0x00) is None
    # The code given twice has its later destination.
    assert maps.text(0x30) == "2"
    maps.done()


def test_empty_literal_and_odd_destinations(maps):
    text = cmap("4 beginbfchar <0001> <> (\\000\\002) (\\000x) <0003> <41> <0004> /space",
                "endbfchar", "1 beginbfchar <0005> <D800> endbfchar")
    assert maps.parse(text) == OK
    assert maps.lookup(0x01) == []
    assert maps.text(0x02) == "x"
    assert maps.text(0x03) == "A"
    # A name is no ToUnicode destination; a lone surrogate gives nothing.
    assert maps.lookup(0x04) is None
    assert maps.lookup(0x05) == []
    maps.done()


def test_an_encoding_gives_cids(maps):
    text = cmap("1 begincidrange <0000> <00FF> 100 <8140> <817E> 633 endcidrange",
                "1 begincidchar <0100> 7 endcidchar",
                "1 beginnotdefrange <00> <1F> 1 endnotdefrange", codespace="")
    assert maps.parse(text) == OK
    assert maps.lookup(0x0000) == [100] and maps.lookup(0x00FF) == [355]
    assert maps.lookup(0x8150) == [633 + 0x10]
    assert maps.lookup(0x0100) == [7]
    assert maps.lookup(0x0101) is None
    # With no codespace ranges, codes are as long as the entries' longest.
    assert maps.code_bytes(b"\x81\x50") == 2 and maps.code_bytes(b"\x41") == 1
    maps.done()


def test_codespace_bytes_match_byte_by_byte(maps):
    shift_jis = "<00> <80> <8140> <9FFC> <A0> <DF> <E040> <FCFC>"
    assert maps.parse(cmap("1 beginbfchar <41> <0041> endbfchar", codespace=shift_jis)) == OK
    assert maps.code_bytes(b"A\x81\x40") == 1
    assert maps.code_bytes(b"\xA5") == 1
    assert maps.code_bytes(b"\x81\x40A") == 2
    assert maps.code_bytes(b"\xE0\x40") == 2
    # In range as a number, but not byte by byte: the second byte is out.
    assert maps.code_bytes(b"\x81\xFDA") == 1
    assert maps.code_bytes(b"\x81") == 1
    maps.done()
    four = "<00> <7F> <81308130> <8439FE39>"
    assert maps.parse(cmap("", codespace=four)) == OK
    assert maps.code_bytes(b"\x81\x30\x81\x30") == 4
    assert maps.code_bytes(b"\x81\x30\x81") == 1
    maps.done()


def test_large_random_map_matches_a_model(maps):
    rng = random.Random(14)
    model: dict[int, str] = {}
    lines, code = [], 0
    while code < 60_000:
        code += rng.randint(1, 12)
        if rng.random() < 0.7:
            dest = "".join(chr(rng.choice((rng.randint(0x20, 0xD7FF), rng.randint(0x10000, 0x10FFFF))))
                           for _ in range(rng.choice((1, 1, 1, 2, 3))))
            lines.append(("char", code, dest))
            model[code] = dest
        else:
            last = code + rng.randint(0, 30)
            start = rng.randint(0x4E00, 0x9F00)
            lines.append(("range", code, last, start))
            for value in range(code, last + 1):
                model[value] = chr(start + value - code)
            code = last
    rng.shuffle(lines)
    sections = []
    for line in lines:
        if line[0] == "char":
            dest = line[2].encode("utf-16-be").hex().upper()
            sections.append(f"1 beginbfchar <{line[1]:04X}> <{dest}> endbfchar")
        else:
            sections.append(f"1 beginbfrange <{line[1]:04X}> <{line[2]:04X}> <{line[3]:04X}> endbfrange")
    assert maps.parse(cmap(*sections)) == OK
    for value in rng.sample(range(0, 60_100), 3000):
        assert maps.text(value) == model.get(value), hex(value)
    maps.done()


def test_budget_is_refused_and_memory_given_back(maps):
    text = cmap("1 beginbfrange <0000> <00FF> [" + " ".join(f"<{c:04X}>" for c in range(0x100)) + "]",
                "endbfrange")
    assert maps.parse(text, budget=1024) == MEMORY
    assert maps.call("CT-HELD")[0] > 0
    maps.done()
    assert maps.parse(text) == OK
    assert maps.text(0xFF) == "ÿ"
    maps.done()


def test_a_map_built_by_hand(maps):
    maps.call("CT-INIT")
    for first, last, value in ((100, 199, 7), (0, 9, 3), (10, 10, 500), (50, 59, 0xFFFFFF9C)):
        assert maps.call("CT-ADD", first, last, value) == (TRUE,)
    maps.call("CT-SEAL")
    assert maps.raw(150) == ([7], 50)
    assert maps.raw(0) == ([3], 0) and maps.raw(9) == ([3], 9)
    assert maps.raw(10) == ([500], 0)
    assert maps.raw(55) == ([0xFFFFFF9C], 5)
    assert maps.raw(11) is None and maps.raw(200) is None and maps.raw(60) is None
    maps.done()
