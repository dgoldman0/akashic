#!/usr/bin/env python3
"""Akashic pdf/lexer.f: PDF tokens and values as spans of bytes.

Tokens and whole values are read from byte strings written into guest
memory, and each span is checked against the Python offsets it must cover:
names, numbers, keywords, strings of both kinds, arrays and dictionaries
nested in each other, references told apart from two integers, and
comments skipped.  Dictionary and array lookups, names with #xx codes,
fixed-point numbers and string decoding are checked against PDF 32000-1
section 7.3.
"""

from __future__ import annotations

import pytest

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

END, INT, REAL, NAME, STRING, HEX, ARRAY, DICT, KEYWORD, REF = range(10)
OPEN_ARRAY, CLOSE_ARRAY, OPEN_DICT, CLOSE_DICT, BAD = range(10, 15)
MASK = (1 << 64) - 1


def signed(value: int) -> int:
    return value - (1 << 64) if value >> 63 else value


class Lexer:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=8 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/lexer.f",)):
            source.extend(_load_forth_lines(AK / module))
        source += ["65536 XBUF LX-IN", "65536 XBUF LX-OUT", "65536 XBUF LX-KEY"]
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-lexer",
                              step_budget=50_000_000)
        self.runtime.drain_uart_output()
        self.input = self.word("LX-IN")
        self.out = self.word("LX-OUT")
        self.key = self.word("LX-KEY")

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0
        for value in args:
            stack.push(value & MASK)
        self.runtime.execute(name, step_budget=200_000_000)
        result = tuple(stack.snapshot())
        while stack.depth():
            stack.pop()
        return result

    def load(self, data: bytes) -> None:
        self.runtime.memory.write_bytes(self.input, data)

    def scan(self, word: str, data: bytes) -> list[tuple[int, bytes]]:
        """Every token or value of DATA as (type, its bytes)."""

        self.load(data)
        a, u, found = self.input, len(data), []
        while True:
            a, u, ta, tu, kind = self.call(word, a, u)
            if kind == END:
                return found
            found.append((kind, data[ta - self.input:ta - self.input + tu]))
            if kind == BAD:
                return found

    def name(self, text: bytes) -> tuple[int, int]:
        self.runtime.memory.write_bytes(self.key, text)
        return self.key, len(text)

    def value(self, data: bytes) -> tuple[int, int, int]:
        self.load(data)
        _, _, va, vu, kind = self.call("PDF-VALUE", self.input, len(data))
        return va, vu, kind


@pytest.fixture(scope="module")
def lexer():
    return Lexer()


def test_tokens_of_each_kind(lexer):
    data = b"/Name 12 -3.5 .25 (lit) <48 65> [ ] << >> true null obj { } % note\n+7"
    assert lexer.scan("PDF-TOKEN", data) == [
        (NAME, b"/Name"), (INT, b"12"), (REAL, b"-3.5"), (REAL, b".25"),
        (STRING, b"(lit)"), (HEX, b"<48 65>"), (OPEN_ARRAY, b"["), (CLOSE_ARRAY, b"]"),
        (OPEN_DICT, b"<<"), (CLOSE_DICT, b">>"), (KEYWORD, b"true"), (KEYWORD, b"null"),
        (KEYWORD, b"obj"), (KEYWORD, b"{"), (KEYWORD, b"}"), (INT, b"+7"),
    ]


def test_tokens_need_no_white_space_between_delimiters(lexer):
    assert lexer.scan("PDF-TOKEN", b"/A/B[1/C(x)]<</D<<>>>>") == [
        (NAME, b"/A"), (NAME, b"/B"), (OPEN_ARRAY, b"["), (INT, b"1"), (NAME, b"/C"),
        (STRING, b"(x)"), (CLOSE_ARRAY, b"]"), (OPEN_DICT, b"<<"), (NAME, b"/D"),
        (OPEN_DICT, b"<<"), (CLOSE_DICT, b">>"), (CLOSE_DICT, b">>"),
    ]


def test_a_literal_string_keeps_its_balanced_parentheses_and_escapes(lexer):
    data = rb"(a (b) \) c\\) next"
    assert lexer.scan("PDF-TOKEN", data) == [(STRING, rb"(a (b) \) c\\)"),
                                              (KEYWORD, b"next")]
    assert lexer.scan("PDF-TOKEN", b"(open") == [(BAD, b"(open")]


def test_bad_bytes_stop_the_scan(lexer):
    assert lexer.scan("PDF-TOKEN", b"1 ) 2") == [(INT, b"1"), (BAD, b")")]


def test_values_take_whole_arrays_dictionaries_and_references(lexer):
    data = b"<< /Kids [1 0 R 2 0 R] /Count 2 >> [1 2 [3] << /A 4 >>] 12 0 R 5 6 7"
    assert lexer.scan("PDF-VALUE", data) == [
        (DICT, b"<< /Kids [1 0 R 2 0 R] /Count 2 >>"),
        (ARRAY, b"[1 2 [3] << /A 4 >>]"),
        (REF, b"12 0 R"), (INT, b"5"), (INT, b"6"), (INT, b"7"),
    ]
    assert lexer.scan("PDF-VALUE", b"[1 2") == [(BAD, b"[1 2")]
    assert lexer.scan("PDF-VALUE", b"3 0 obj") == [(INT, b"3"), (INT, b"0"),
                                                   (KEYWORD, b"obj")]


def test_numbers(lexer):
    for text, whole in ((b"0", 0), (b"42", 42), (b"-17", -17), (b"+8", 8), (b"3.9", 3)):
        lexer.load(text)
        assert signed(lexer.call("PDF-INT", lexer.input, len(text))[0]) == whole
    for text, value in ((b"1", 1.0), (b"-2.5", -2.5), (b".25", 0.25), (b"612.0", 612.0),
                        (b"-0.001", -0.001), (b"3.14159", 3.14159), (b"7.", 7.0)):
        lexer.load(text)
        fixed = signed(lexer.call("PDF-FIXED", lexer.input, len(text))[0])
        assert abs(fixed / 65536 - value) < 2 / 65536, (text, fixed)


def test_a_reference_s_numbers(lexer):
    va, vu, kind = lexer.value(b"  1234 7 R")
    assert kind == REF
    assert lexer.call("PDF-REF@", va, vu) == (1234, 7)


def test_names_compare_with_their_codes_decoded(lexer):
    for text, name, same in ((b"/Type", b"Type", True), (b"/Type", b"Typ", False),
                             (b"/Typ", b"Type", False), (b"/A#20B", b"A B", True),
                             (b"/#41", b"A", True), (b"/", b"", True)):
        lexer.load(text)
        flag = lexer.call("PDF-NAME=", lexer.input, len(text), *lexer.name(name))[0]
        assert bool(flag) == same, (text, name)


def test_a_dictionary_s_values(lexer):
    va, vu, kind = lexer.value(
        b"<< /Type /Page /Parent 3 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 9 0 R >> >> /A#20B (x) >>")
    assert kind == DICT
    for key, kind_wanted, text in ((b"Type", NAME, b"/Page"), (b"Parent", REF, b"3 0 R"),
                                   (b"MediaBox", ARRAY, b"[0 0 612 792]"),
                                   (b"Resources", DICT, b"<< /Font << /F1 9 0 R >> >>"),
                                   (b"A B", STRING, b"(x)"), (b"Font", END, b"")):
        a, u, got = lexer.call("PDF-DICT@", *lexer.name(key), va, vu)
        assert got == kind_wanted, key
        if got != END:
            assert lexer.runtime.memory.read_bytes(a, u) == text


def test_an_array_s_values(lexer):
    va, vu, kind = lexer.value(b"[ /A 1 0 R << /B 2 >> (s) 4.5 ]")
    assert kind == ARRAY
    assert lexer.call("PDF-ARRAY-N", va, vu) == (5,)
    wanted = [(NAME, b"/A"), (REF, b"1 0 R"), (DICT, b"<< /B 2 >>"), (STRING, b"(s)"),
              (REAL, b"4.5")]
    for index, (kind_wanted, text) in enumerate(wanted):
        a, u, got = lexer.call("PDF-ARRAY@", index, va, vu)
        assert got == kind_wanted and lexer.runtime.memory.read_bytes(a, u) == text
    assert lexer.call("PDF-ARRAY@", 5, va, vu)[2] == END
    va, vu, _ = lexer.value(b"[]")
    assert lexer.call("PDF-ARRAY-N", va, vu) == (0,)


@pytest.mark.parametrize("text, decoded", (
    (rb"(plain)", b"plain"),
    (rb"(a\nb\tc\\d\)e\(f)", b"a\nb\tc\\d)e(f"),
    (rb"(nested (paren) ok)", b"nested (paren) ok"),
    (rb"(\101\102\7\0011)", b"AB\x07\x011"),
    (b"(line\\\ncontinued\\\r\nhere)", b"linecontinuedhere"),
    (b"(cr\rlf\nboth\r\nend)", b"cr\nlf\nboth\nend"),
    (rb"(\q unknown)", b"q unknown"),
    (b"<48656C6C6F>", b"Hello"),
    (b"<48 65 6c\n6C 6f>", b"Hello"),
    (b"<414>", b"A@"),
    (b"<>", b""),
))
def test_string_bytes(lexer, text, decoded):
    va, vu, kind = lexer.value(text)
    assert kind in (STRING, HEX)
    (length,) = lexer.call("PDF-STRING", va, vu, kind, lexer.out, 4096)
    assert length == len(decoded)
    assert lexer.runtime.memory.read_bytes(lexer.out, length) == decoded


def test_a_string_longer_than_its_room_says_its_length(lexer):
    va, vu, kind = lexer.value(b"(0123456789)")
    lexer.runtime.memory.write_bytes(lexer.out, b"\xee" * 8)
    assert lexer.call("PDF-STRING", va, vu, kind, lexer.out, 4) == (10,)
    assert lexer.runtime.memory.read_bytes(lexer.out, 8) == b"0123\xee\xee\xee\xee"


@pytest.mark.parametrize("text, decoded", (
    (b"/Type", b"Type"),
    (b"/A#20B", b"A B"),
    (b"/#41#62", b"Ab"),
    (b"/my#2Fplace#", b"my/place#"),
    (b"/", b""),
))
def test_name_bytes(lexer, text, decoded):
    va, vu, kind = lexer.value(text)
    assert kind == NAME
    (length,) = lexer.call("PDF-NAME", va, vu, lexer.out, 4096)
    assert length == len(decoded)
    assert lexer.runtime.memory.read_bytes(lexer.out, length) == decoded
    lexer.load(text)
    assert lexer.call("PDF-NAME=", lexer.input, len(text), lexer.out, length) != (0,)


def test_a_name_longer_than_its_room_says_its_length(lexer):
    va, vu, _ = lexer.value(b"/Long#20name")
    lexer.runtime.memory.write_bytes(lexer.out, b"\xee" * 8)
    assert lexer.call("PDF-NAME", va, vu, lexer.out, 5) == (9,)
    assert lexer.runtime.memory.read_bytes(lexer.out, 8) == b"Long \xee\xee\xee"
