#!/usr/bin/env python3
"""cbor.f on the simulator.

The module loads, its decoder reads back what its encoder writes, and
malformed input is a decode error: an item, string or count that runs
past the input's end, or an item of a type other than the word reads.
The input sits in a buffer filled with 238 beyond its end, so a decoder
that read past the end would return those bytes.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


PRELUDE = r"""
CREATE T-IN 64 ALLOT
VARIABLE T-N
: T-RESET  ( -- )  0 T-N !  T-IN 64 238 FILL ;
: T-B,  ( c -- )  T-IN T-N @ + C!  1 T-N +! ;
: T-PARSE  ( -- )  T-IN T-N @ CBOR-PARSE DROP ;
: T-AT  ( addr -- offset )  T-IN - ;
: T-STATE.  ( -- )  CBOR-INPUT-OK? .  CBOR-DONE? . ;
CREATE T-OUT 64 ALLOT
CREATE T-SAVE CBOR-CURSORS-SIZE ALLOT
"""

SUITE = NativeForth(("cbor/cbor.f",), prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str]) -> list[str]:
    output = forth.run(lines, 200_000_000).decode("latin-1")
    assert "??" not in output and "not found" not in output, output[-3000:]
    return [line for line in output.replace("\r", "").split("\n") if line.strip()]


def ints(line: str) -> list[int]:
    return [int(cell) for cell in line.split()]


def given(data: bytes) -> str:
    """Forth that makes DATA the decoder's input."""
    return "T-RESET " + "".join(f"{byte} T-B, " for byte in data) + "T-PARSE "


def test_cbor_loads_on_the_simulator():
    # CBOR-SKIP called itself by name.  A colon name is hidden until ;
    # publishes it, on the simulator as in standard Forth, so the module
    # stopped there with an unknown word; it recurses with RECURSE.
    SUITE.machine()


def test_the_decoder_reads_what_the_encoder_writes(forth):
    lines = run(forth, [
        "T-OUT 64 CBOR-RESET  6 CBOR-ARRAY  500 CBOR-UINT  9 CBOR-NINT",
        "S\" ab\" CBOR-BSTR  S\" xyz\" CBOR-TSTR",
        "1 CBOR-MAP  1 CBOR-UINT CBOR-TRUE  42 CBOR-TAG 7 CBOR-UINT",
        "CBOR-RESULT CBOR-PARSE DROP",
        "CBOR-NEXT-ARRAY . CBOR-NEXT-UINT . CBOR-NEXT-NINT . CBOR-NEXT-BSTR NIP . "
        "CBOR-NEXT-TSTR TYPE SPACE CBOR-NEXT-MAP . CBOR-NEXT-UINT . CBOR-NEXT-BOOL . "
        "CBOR-NEXT-TAG . CBOR-NEXT-UINT . T-STATE. CR",
        # The whole array skips as one item.
        "CBOR-RESULT CBOR-PARSE DROP CBOR-SKIP T-STATE. CR",
        # Simple values and floats skip with their argument bytes.
        given(bytes([0xF4, 0xF6, 0xF9, 0x3C, 0x00, 0xFB]) + bytes(8))
        + "CBOR-SKIP CBOR-SKIP CBOR-SKIP CBOR-SKIP T-STATE. CR",
        given(bytes([0xF5, 0xF4])) + "CBOR-NEXT-BOOL . CBOR-NEXT-BOOL . T-STATE. CR",
    ])
    assert lines[0].split() == ["6", "500", "9", "2", "xyz", "1", "1", "-1", "42", "7",
                                "-1", "-1"]
    assert ints(lines[1]) == [-1, -1]
    assert ints(lines[2]) == [-1, -1]
    assert ints(lines[3]) == [-1, 0, -1, -1]


# Each case: the input, the Forth that reads it, and what that prints
# before the decoder's state (CBOR-INPUT-OK? and CBOR-DONE?).
TRUNCATED = {
    "argument cut short": (bytes([0x19, 0x01]), "CBOR-NEXT-UINT .", [0]),
    "eight-byte argument cut short": (bytes([0x1B, 1, 2, 3]), "CBOR-NEXT-UINT .", [0]),
    "byte string longer than the input": (
        bytes([0x45, 0x61, 0x62]), "CBOR-NEXT-BSTR SWAP T-AT . .", [3, 0]),
    "text string of 2^64-1 bytes": (
        bytes([0x7B]) + bytes([0xFF] * 8), "CBOR-NEXT-TSTR SWAP T-AT . .", [9, 0]),
    "array count beyond the input": (
        bytes([0x9A, 0x00, 0x01, 0x00, 0x00]), "CBOR-NEXT-ARRAY .", [0]),
    "array missing its second item": (bytes([0x82, 0x01]), "CBOR-NEXT-ARRAY .", [0]),
    "map missing its value": (bytes([0xA1, 0x01]), "CBOR-NEXT-MAP .", [0]),
    "skip of a map counting 2^63 pairs": (
        bytes([0xBB, 0x7F]) + bytes([0xFF] * 7), "CBOR-SKIP", []),
    "skip through a truncated nested string": (
        bytes([0x81, 0x45, 0x61]), "CBOR-SKIP", []),
    "skip of nested arrays holding more items than bytes": (
        bytes([0x82, 0x82, 0x82, 0x00]), "CBOR-SKIP", []),
    "tag with no item after it": (bytes([0xC1]), "CBOR-NEXT-TAG .", [0]),
    "read from an empty input": (b"", "CBOR-NEXT-UINT .", [0]),
    "skip at the end of the input": (b"", "CBOR-SKIP", []),
    "indefinite-length string": (
        bytes([0x5F, 0x41, 0x61, 0xFF]), "CBOR-NEXT-BSTR NIP .", [0]),
    "reserved additional information": (bytes([0x1C]), "CBOR-NEXT-UINT .", [0]),
}


@pytest.mark.parametrize("case", list(TRUNCATED))
def test_truncated_input_is_a_decode_error(forth, case):
    data, phrase, printed = TRUNCATED[case]
    lines = run(forth, [given(data) + phrase + " T-STATE. CR"])
    assert ints(lines[0]) == printed + [0, -1]


WRONG_TYPE = {
    "unsigned integer read from a negative one": (bytes([0x20]), "CBOR-NEXT-UINT .", [0]),
    "negative integer read from an unsigned one": (bytes([0x01]), "CBOR-NEXT-NINT .", [0]),
    "byte string read from a text string": (
        bytes([0x61, 0x61]), "CBOR-NEXT-BSTR SWAP T-AT . .", [2, 0]),
    "text string read from a byte string": (
        bytes([0x41, 0x61]), "CBOR-NEXT-TSTR SWAP T-AT . .", [2, 0]),
    "array read from a map": (bytes([0xA0]), "CBOR-NEXT-ARRAY .", [0]),
    "map read from an array": (bytes([0x80]), "CBOR-NEXT-MAP .", [0]),
    "tag read from an integer": (bytes([0x01, 0x01]), "CBOR-NEXT-TAG .", [0]),
    "boolean read from null": (bytes([0xF6]), "CBOR-NEXT-BOOL .", [0]),
    "boolean read from the integer 21": (bytes([0x15]), "CBOR-NEXT-BOOL .", [0]),
}


@pytest.mark.parametrize("case", list(WRONG_TYPE))
def test_an_item_of_another_type_is_a_decode_error(forth, case):
    data, phrase, printed = WRONG_TYPE[case]
    lines = run(forth, [given(data) + phrase + " T-STATE. CR"])
    assert ints(lines[0]) == printed + [0, -1]


def test_the_error_lasts_until_the_next_parse_and_travels_with_the_cursors(forth):
    lines = run(forth, [
        # After the error every read finds the input exhausted.
        given(bytes([0x20, 0x01])) + "CBOR-NEXT-UINT . CBOR-NEXT-UINT . T-STATE. CR",
        given(bytes([0x05])) + "T-STATE. CBOR-NEXT-UINT . T-STATE. CR",
        # A nested decode saves the cursors, error flag included.
        given(bytes([0x20])) + "CBOR-NEXT-UINT DROP T-SAVE CBOR-SAVE",
        given(bytes([0x05])) + "CBOR-NEXT-UINT . CBOR-INPUT-OK? . "
        "T-SAVE CBOR-RESTORE T-STATE. CR",
    ])
    assert ints(lines[0]) == [0, 0, 0, -1]
    assert ints(lines[1]) == [-1, 0, 5, -1, -1]
    assert ints(lines[2]) == [5, -1, 0, -1]


def test_a_skip_counts_items_instead_of_recursing(forth):
    depth = 100_000
    lines = run(forth, [
        # A map holding a tagged integer and a string skips whole, and the
        # item after it is the next one read.
        given(bytes([0xA1, 0x01, 0x82, 0xC1, 0x02, 0x63, 0x61, 0x62, 0x63, 0x05]))
        + "CBOR-SKIP CBOR-NEXT-UINT . T-STATE. CR",
        # 100,000 nested one-item arrays around one integer.  A skip that
        # recursed once a level ran out of return stack here; cut short
        # before the integer, the same nesting is a decode error.
        f"VARIABLE T-DEEP  {depth + 1} ALLOCATE DROP T-DEEP !",
        f"T-DEEP @ {depth} 129 FILL  0 T-DEEP @ {depth} + C!",
        f"T-DEEP @ {depth + 1} CBOR-PARSE DROP CBOR-SKIP T-STATE. CR",
        f"T-DEEP @ {depth} CBOR-PARSE DROP CBOR-SKIP T-STATE. CR",
        "T-DEEP @ FREE",
    ])
    assert ints(lines[0]) == [5, -1, -1]
    assert ints(lines[1]) == [-1, -1]
    assert ints(lines[2]) == [0, -1]


DAG_SUITE = NativeForth(("cbor/dag-cbor.f",), prelude=tuple(PRELUDE.strip().splitlines()))


def test_dag_cbor_key_order_refuses_a_map_that_does_not_decode():
    forth = DAG_SUITE.shared()
    lines = run(forth, [
        # {"a": 1, "bb": 2} is in DAG-CBOR order; {"bb": 1, "a": 2} is not.
        given(bytes([0xA2, 0x61, 0x61, 0x01, 0x62, 0x62, 0x62, 0x02]))
        + "DCBOR-SORT-MAP . CR",
        given(bytes([0xA2, 0x62, 0x62, 0x62, 0x01, 0x61, 0x61, 0x02]))
        + "DCBOR-SORT-MAP . CR",
        # A key that is not a text string, and an array where the map
        # should be: neither decodes, so neither is in order.
        given(bytes([0xA1, 0x01, 0x02])) + "DCBOR-SORT-MAP . CR",
        given(bytes([0x80])) + "DCBOR-SORT-MAP . CR",
    ])
    assert [ints(line) for line in lines] == [[-1], [0], [0], [0]]
