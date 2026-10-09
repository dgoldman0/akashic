#!/usr/bin/env python3
"""The interop/sandbox value bridge against a Python reference of the codec.

The reference below implements docs/sandbox/value-codec.md and reproduces
its golden vectors.  The generated Forth fixture builds each interop value,
encodes it with SBCV-ENCODE and compares the bytes with the reference, then
decodes them and encodes again.  Refusals, limits and malformed canonical
bytes are checked the same way, and the heap must balance afterwards.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

import pytest


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


# ---------------------------------------------------------------------------
# Python reference of the canonical value codec
# ---------------------------------------------------------------------------

T_NULL, T_BOOL, T_I64, T_BYTES, T_UTF8, T_LIST, T_MAP = range(7)
U64 = (1 << 64) - 1


class Blob(bytes):
    """A BYTES value."""


class Raw:
    """A string value holding arbitrary, possibly invalid, UTF-8 bytes."""

    def __init__(self, data: bytes) -> None:
        self.data = data


class F32:
    def __init__(self, bits: int) -> None:
        self.bits = bits


class Resource:
    def __init__(self, data: bytes) -> None:
        self.data = data


class Map:
    """An interop map in insertion order; keys are str, Raw or int."""

    def __init__(self, items: list) -> None:
        self.items = items


def occurrence(tag: int, count: int, payload: bytes, *, flags: int = 0,
               reserved: int = 0, length: int | None = None) -> bytes:
    size = len(payload) if length is None else length
    return struct.pack("<BBHIQ", tag, flags, reserved, count, size) + payload


def key_bytes(key) -> bytes:
    return key.encode() if isinstance(key, str) else key.data


def encode(value) -> bytes:
    if value is None:
        return occurrence(T_NULL, 0, b"")
    if value is True or value is False:
        return occurrence(T_BOOL, 0, (U64 if value else 0).to_bytes(8, "little"))
    if isinstance(value, int):
        return occurrence(T_I64, 0, (value & U64).to_bytes(8, "little"))
    if isinstance(value, Blob):
        return occurrence(T_BYTES, 0, bytes(value))
    if isinstance(value, str):
        return occurrence(T_UTF8, 0, value.encode())
    if isinstance(value, list):
        return occurrence(T_LIST, len(value), b"".join(map(encode, value)))
    assert isinstance(value, Map)
    items = sorted(value.items, key=lambda item: key_bytes(item[0]))
    payload = b"".join(
        occurrence(T_UTF8, 0, key_bytes(key)) + encode(child)
        for key, child in items
    )
    return occurrence(T_MAP, len(items), payload)


def pad8(n: int) -> int:
    return (n + 7) & -8


def nodes(value) -> int:
    if isinstance(value, list):
        return 1 + sum(map(nodes, value))
    if isinstance(value, Map):
        return 1 + sum(1 + nodes(child) for _, child in value.items)
    return 1


def value_bytes(value) -> int:
    if value is None:
        return 16
    if isinstance(value, (bool, int)):
        return 24
    if isinstance(value, (Blob, str)):
        data = bytes(value) if isinstance(value, Blob) else value.encode()
        return 16 + pad8(len(data))
    if isinstance(value, list):
        return 16 + 8 * len(value) + sum(map(value_bytes, value))
    return 16 + 16 * len(value.items) + sum(
        16 + pad8(len(key_bytes(key))) + value_bytes(child)
        for key, child in value.items
    )


GOLDEN = {
    "null": (None, "00000000000000000000000000000000"),
    "false": (False, "010000000000000008000000000000000000000000000000"),
    "empty-list": ([], "05000000000000000000000000000000"),
    "list": (
        [1, "a"],
        "050000000200000029000000000000000200000000000000080000000000000001"
        "000000000000000400000000000000010000000000000061",
    ),
}


def test_the_reference_reproduces_the_golden_vectors() -> None:
    for value, expected in GOLDEN.values():
        assert encode(value).hex() == expected


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------

# The default limits: depth, blob bytes, list count, map count, nodes and
# expanded value bytes, used for input and result alike.
DEFAULT = (8, 1024, 64, 64, 512, 65536)


def nested(depth: int):
    value = 1
    for _ in range(depth - 1):
        value = [value]
    return value


ENCODE_OK = [
    None, False, True, 0, 1, -1, (1 << 63) - 1, -(1 << 63),
    Blob(b""), Blob(b"\x00\xff\x80"), Blob(bytes(range(9))),
    "", "a", "héllo", "ࠀ", "￿", "\U00010000", "\U0010ffff",
    "a\x00b", "﻿",
    [], [1, "a"], [[], [None]], nested(8),
    Map([]),
    Map([("b", 1), ("a", 2)]),
    Map([("ab", 1), ("a", 2), ("", 3)]),
    Map([("\u0080", 1), ("\x7f", 2)]),
    Map([("k", [Map([("z", True), ("y", Blob(b"\x01"))])]), ("j", None)]),
    list(range(64)),
    Map([(f"k{i:02d}", i) for i in reversed(range(64))]),
    "x" * 1024,
]

ENCODE_FAIL = [
    (F32(0x3F800000), "SBCV-S-TYPE"),
    (Resource(b"r"), "SBCV-S-TYPE"),
    ([1, F32(0)], "SBCV-S-TYPE"),
    (Raw(b"\xc0\x80"), "SBCV-S-UTF8"),
    (Raw(b"\xed\xa0\x80"), "SBCV-S-UTF8"),
    (Raw(b"\xf4\x90\x80\x80"), "SBCV-S-UTF8"),
    (Raw(b"\x80"), "SBCV-S-UTF8"),
    (Raw(b"\xe2\x82"), "SBCV-S-UTF8"),
    (Raw(b"\xf5\x80\x80\x80"), "SBCV-S-UTF8"),
    (Raw(b"\xe0\x9f\xbf"), "SBCV-S-UTF8"),
    (Raw(b"\xf0\x8f\xbf\xbf"), "SBCV-S-UTF8"),
    (Raw(b"\xe2\x28\xa1"), "SBCV-S-UTF8"),
    (Raw(b"\xf0\x90\x80"), "SBCV-S-UTF8"),
    (Raw(b"\xc1\xbf"), "SBCV-S-UTF8"),
    (Map([("a", 1), ("a", 2)]), "SBCV-S-KEY"),
    (Map([("b", 1), (7, 2)]), "SBCV-S-KEY"),
    (Map([(Raw(b"\xff"), 1)]), "SBCV-S-UTF8"),
    (nested(9), "SBCV-S-LIMIT"),
    ("x" * 1025, "SBCV-S-LIMIT"),
    (list(range(65)), "SBCV-S-LIMIT"),
    (Map([(f"k{i:02d}", i) for i in range(65)]), "SBCV-S-LIMIT"),
]

# Values checked against one tight node or byte limit, at and past it.
SIZED = [
    Map([("a", [1, 2, "three"]), ("b", Blob(b"four"))]),
    [Map([("x", None)]), "y" * 9, [True]],
]


def bad_list() -> bytes:
    return encode([1, "a"])


DECODE_FAIL = [
    ("empty", b"", "SBCV-S-INVALID"),
    ("truncated header", encode(None)[:15], "SBCV-S-INVALID"),
    ("truncated payload", encode(7)[:-1], "SBCV-S-INVALID"),
    ("truncated child", bad_list()[:-1], "SBCV-S-INVALID"),
    ("trailing byte", encode(None) + b"\x00", "SBCV-S-INVALID"),
    ("two roots", encode(None) + encode(None), "SBCV-S-INVALID"),
    ("unknown tag", occurrence(7, 0, b""), "SBCV-S-INVALID"),
    ("flags", occurrence(T_NULL, 0, b"", flags=1), "SBCV-S-INVALID"),
    ("reserved", occurrence(T_NULL, 0, b"", reserved=1), "SBCV-S-INVALID"),
    ("null payload", occurrence(T_NULL, 0, b"\x00"), "SBCV-S-INVALID"),
    ("null count", occurrence(T_NULL, 1, b""), "SBCV-S-INVALID"),
    ("bool size", occurrence(T_BOOL, 0, b"\x00" * 4), "SBCV-S-INVALID"),
    ("bool bits", occurrence(T_BOOL, 0, (1).to_bytes(8, "little")),
     "SBCV-S-INVALID"),
    ("i64 size", occurrence(T_I64, 0, b"\x00" * 7), "SBCV-S-INVALID"),
    ("string count", occurrence(T_UTF8, 1, b"a"), "SBCV-S-INVALID"),
    ("overlong", occurrence(T_UTF8, 0, b"\xc1\xbf"), "SBCV-S-UTF8"),
    ("surrogate", occurrence(T_UTF8, 0, b"\xed\xbf\xbf"), "SBCV-S-UTF8"),
    ("overlong 3", occurrence(T_UTF8, 0, b"\xe0\x80\x80"), "SBCV-S-UTF8"),
    ("overlong 4", occurrence(T_UTF8, 0, b"\xf0\x80\x80\x80"), "SBCV-S-UTF8"),
    ("above max", occurrence(T_UTF8, 0, b"\xf4\x90\x80\x80"), "SBCV-S-UTF8"),
    ("stray", occurrence(T_UTF8, 0, b"a\x80"), "SBCV-S-UTF8"),
    ("cut", occurrence(T_UTF8, 0, b"\xe2\x82"), "SBCV-S-UTF8"),
    ("too few children", occurrence(T_LIST, 2, encode(1)),
     "SBCV-S-INVALID"),
    ("unused payload", occurrence(T_LIST, 1, encode(1) + b"\x00"),
     "SBCV-S-INVALID"),
    ("payload past span", occurrence(T_LIST, 0, b"", length=U64),
     "SBCV-S-INVALID"),
    ("non-string key", occurrence(T_MAP, 1, encode(1) + encode(2)),
     "SBCV-S-KEY"),
    ("unsorted keys", occurrence(
        T_MAP, 2, encode("b") + encode(1) + encode("a") + encode(2)),
     "SBCV-S-KEY"),
    ("duplicate keys", occurrence(
        T_MAP, 2, encode("a") + encode(1) + encode("a") + encode(2)),
     "SBCV-S-KEY"),
    ("invalid key", occurrence(
        T_MAP, 1, occurrence(T_UTF8, 0, b"\xc0") + encode(1)),
     "SBCV-S-UTF8"),
    ("depth", encode(nested(9)), "SBCV-S-LIMIT"),
    ("list count", encode(list(range(65))), "SBCV-S-LIMIT"),
    ("blob", encode(Blob(b"\x00" * 1025)), "SBCV-S-LIMIT"),
]


# ---------------------------------------------------------------------------
# Forth fixture generation
# ---------------------------------------------------------------------------

def hex_load(data: bytes) -> list[str]:
    text = data.hex()
    lines = ["_bx-begin"]
    lines += [f'S" {text[i:i + 96]}" _bx-add' for i in range(0, len(text), 96)]
    lines.append("_bx-end")
    return lines


def forth_int(value: int) -> str:
    return f"0x{value & U64:X}"


def build(value) -> list[str]:
    """Forth that fills the CV on top of the stack: ( cv -- cv )."""
    if value is None:
        return ["DUP CV-NULL!"]
    if value is True or value is False:
        return [f"{-1 if value else 0} OVER CV-BOOL!"]
    if isinstance(value, int):
        return [f"{forth_int(value)} OVER CV-INT!"]
    if isinstance(value, F32):
        return [f"{forth_int(value.bits)} OVER CV-F32!"]
    if isinstance(value, Blob):
        return hex_load(bytes(value)) + ["2 PICK CV-BYTES! THROW"]
    if isinstance(value, str):
        return hex_load(value.encode()) + ["2 PICK CV-STRING! THROW"]
    if isinstance(value, Raw):
        return hex_load(value.data) + ["2 PICK CV-STRING! THROW"]
    if isinstance(value, Resource):
        return hex_load(value.data) + ["2 PICK CV-RESOURCE! THROW"]
    if isinstance(value, list):
        lines = [f"{len(value)} OVER CV-LIST! THROW"]
        for index, child in enumerate(value):
            lines.append(f"{index} OVER CV-LIST-NTH")
            lines += build(child)
            lines.append("DROP")
        return lines
    lines = [f"{len(value.items)} OVER CV-MAP! THROW"]
    for index, (key, child) in enumerate(value.items):
        name = b"k" if isinstance(key, int) else key_bytes(key)
        lines += hex_load(name)
        lines.append(f"{index} 3 PICK CV-MAP-SLOT! THROW")
        lines += build(child)
        lines.append("DROP")
        if isinstance(key, int):
            lines.append(
                f"{index} OVER CV-MAP-NTH CV-MAP-KEY {key} SWAP CV-INT!")
    return lines


def limits(values: tuple[int, ...]) -> str:
    return " ".join(map(str, values)) + " _vb-limits!"


def fixture() -> bytes:
    lines = [PRELUDE]
    case = 0

    def define(body: list[str]) -> None:
        nonlocal case
        case += 1
        # Each case's code is discarded once it has run.
        lines.append("MARKER _vb-mark")
        lines.append(f": _vb-case-{case}  ( -- )")
        lines.append(f"    {case} _vb-case ! _bx-reset")
        lines.extend("    " + line for line in body)
        lines.append(";")
        lines.append(f"_vb-case-{case}")
        lines.append("_vb-mark")

    for value in ENCODE_OK:
        expected = encode(value)
        define(
            [limits(DEFAULT), "_vb-cv"] + build(value) + ["DROP"]
            + hex_load(expected) + ["_vb-encode-ok"]
        )
    for value, status in ENCODE_FAIL:
        define(
            [limits(DEFAULT), "_vb-cv"] + build(value) + ["DROP"]
            + [f"{status} _vb-encode-fail"]
        )
    for value in SIZED:
        n, b = nodes(value), value_bytes(value)
        for node_limit, byte_limit, status in (
            (n, b, "SBCV-S-OK"),
            (n - 1, b, "SBCV-S-LIMIT"),
            (n, b - 1, "SBCV-S-LIMIT"),
        ):
            values = (8, 1024, 64, 64, node_limit, byte_limit)
            define(
                [limits(values), "_vb-cv"] + build(value) + ["DROP"]
                + [f"{status} _vb-encode-status"]
                + hex_load(encode(value)) + [f"{status} _vb-decode-status"]
            )
    # A buffer one byte short, and one overlapping the value it encodes.
    define(
        [limits(DEFAULT), "_vb-cv"] + build("capacity") + ["DROP"]
        + [f"{len(encode('capacity')) - 1} _vb-encode-short"]
    )
    define([limits(DEFAULT), "_vb-cv"] + build("alias") + ["DROP", "_vb-alias"])
    for _name, data, status in DECODE_FAIL:
        define([limits(DEFAULT)] + hex_load(data) + [f"{status} _vb-decode-fail"])
    lines.append(EPILOGUE)
    return ("\n".join(lines) + "\n").encode()


PRELUDE = r"""\ Generated: interop/sandbox value bridge against the Python reference.
PROVIDED sbcv-tests

VARIABLE _vb-fails
VARIABLE _vb-checks
VARIABLE _vb-case
VARIABLE _vb-depth
VARIABLE _vb-heap
VARIABLE _vb-ea
VARIABLE _vb-en

CREATE _bx-pool 65536 ALLOT
VARIABLE _bx-top
VARIABLE _bx-start
CREATE _vb-out 65536 ALLOT
CREATE _vb-again 65536 ALLOT
CREATE _vb-cv CV-SIZE ALLOT
CREATE _vb-back CV-SIZE ALLOT
CREATE _vb-limits-raw SBOX-VALUE-LIMITS-SIZE 7 + ALLOT

: _vb-limits  ( -- limits ) _vb-limits-raw 7 + -8 AND ;

: _vb-assert  ( flag -- )
    1 _vb-checks +!
    0= IF
        1 _vb-fails +!
        ." SBCV ASSERT case " _vb-case @ . ." check " _vb-checks @ . CR
    THEN ;

: _bx-reset  ( -- ) 0 _bx-top ! ;
: _bx-begin  ( -- ) _bx-top @ _bx-start ! ;
: _hexval  ( c -- n )
    DUP [CHAR] a >= IF [CHAR] a - 10 + ELSE [CHAR] 0 - THEN ;
: _bx-add  ( c-addr u -- )
    2 / 0 ?DO
        DUP I 2 * + C@ _hexval 4 LSHIFT
        OVER I 2 * + 1+ C@ _hexval OR
        _bx-pool _bx-top @ + C!
        1 _bx-top +!
    LOOP DROP ;
: _bx-end  ( -- addr n )
    _bx-pool _bx-start @ + _bx-top @ _bx-start @ - ;

: _vb-limit!  ( value field -- )
    _vb-limits SBOX-VALUE-LIMIT! 0= _vb-assert ;

\ Input and result totals share one pair of values in these cases.
: _vb-limits!  ( depth blob list map nodes bytes -- )
    _vb-limits SBOX-VALUE-LIMITS-BEGIN 0= _vb-assert
    DUP SBOX-VALUE-LIMIT-INPUT-BYTES _vb-limit!
    DUP SBOX-VALUE-LIMIT-OUTPUT-ARENA-BYTES _vb-limit!
    SBOX-VALUE-LIMIT-OUTPUT-RESULT-BYTES _vb-limit!
    DUP SBOX-VALUE-LIMIT-INPUT-NODES _vb-limit!
    DUP SBOX-VALUE-LIMIT-OUTPUT-ARENA-NODES _vb-limit!
    SBOX-VALUE-LIMIT-OUTPUT-RESULT-NODES _vb-limit!
    SBOX-VALUE-LIMIT-MAP-COUNT _vb-limit!
    SBOX-VALUE-LIMIT-LIST-COUNT _vb-limit!
    SBOX-VALUE-LIMIT-BLOB-BYTES _vb-limit!
    SBOX-VALUE-LIMIT-DEPTH _vb-limit!
    _vb-limits SBOX-VALUE-LIMITS-SEAL 0= _vb-assert ;

: _vb-same?  ( a u b v -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN COMPARE 0= ;

\ The CV encodes to the expected bytes, measures their length, decodes
\ back, and encodes to the same bytes again.
: _vb-encode-ok  ( expected expected-u -- )
    _vb-en ! _vb-ea !
    _vb-cv _vb-limits SBCV-MEASURE
        SBCV-S-OK = _vb-assert _vb-en @ = _vb-assert
    _vb-cv _vb-limits _vb-out 65536 SBCV-ENCODE
        SBCV-S-OK = _vb-assert
        _vb-out SWAP _vb-ea @ _vb-en @ _vb-same? _vb-assert
    _vb-ea @ _vb-en @ _vb-limits _vb-back SBCV-DECODE
        SBCV-S-OK = _vb-assert
    _vb-back _vb-limits _vb-again 65536 SBCV-ENCODE
        SBCV-S-OK = _vb-assert
        _vb-again SWAP _vb-ea @ _vb-en @ _vb-same? _vb-assert
    _vb-cv CV-NULL! _vb-back CV-NULL! ;

: _vb-encode-status  ( status -- )
    _vb-cv _vb-limits _vb-out 65536 SBCV-ENCODE
    ROT = _vb-assert DROP
    _vb-cv CV-NULL! ;

: _vb-encode-fail  ( status -- )
    DUP _vb-cv _vb-limits SBCV-MEASURE ROT = _vb-assert 0= _vb-assert
    _vb-encode-status ;

: _vb-decode-status  ( bytes bytes-u status -- )
    >R _vb-limits _vb-back SBCV-DECODE R> = _vb-assert
    _vb-back CV-NULL! ;

\ A refused decode leaves its value NULL.
: _vb-decode-fail  ( bytes bytes-u status -- )
    >R _vb-limits _vb-back SBCV-DECODE R> = _vb-assert
    _vb-back CV-TYPE@ CV-T-NULL = _vb-assert ;

: _vb-encode-short  ( capacity -- )
    >R _vb-cv _vb-limits _vb-out R> SBCV-ENCODE
    SBCV-S-CAPACITY = _vb-assert 0= _vb-assert
    _vb-cv CV-NULL! ;

: _vb-alias  ( -- )
    _vb-cv _vb-limits _vb-cv CV-DATA@ 65536 SBCV-ENCODE
    SBCV-S-ALIAS = _vb-assert 0= _vb-assert
    _vb-cv CV-NULL! ;

: _vb-start  ( -- )
    0 _vb-fails ! 0 _vb-checks ! DEPTH _vb-depth !
    _vb-cv CV-INIT _vb-back CV-INIT
    HEAP-FREE-BYTES _vb-heap ! ;

_vb-start
"""

EPILOGUE = r"""
: _vb-finish  ( -- )
    0 _vb-case !
    DEPTH _vb-depth @ = _vb-assert
    HEAP-FREE-BYTES _vb-heap @ = _vb-assert
    _vb-fails @ IF
        ." SBCV BRIDGE FAIL " _vb-fails @ . ." / " _vb-checks @ . CR
    ELSE
        ." SBCV BRIDGE PASS " _vb-checks @ . CR
    THEN ;

_vb-finish
"""


PROFILE_NAME = "sandbox-value-bridge"


@pytest.mark.parametrize("name", ["sandbox-value-bridge"])
def test_the_bridge_matches_the_reference(name: str, tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("interop/codecs/sandbox-value.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - interop/sandbox value bridge
ENTER-USERLAND
." [akashic] loading the sandbox value bridge" CR TX-FLUSH
REQUIRE interop/codecs/sandbox-value.f
REQUIRE local_testing/sbcv-test.f
""",
        ready_markers=("SBCV BRIDGE PASS",),
        stable_markers=("SBCV BRIDGE PASS",),
        failure_markers=(
            "SBCV BRIDGE FAIL",
            "SBCV ASSERT",
            "? (not found)",
            "Branch offset overflow",
            "dictionary full",
            "exception",
        ),
        linked=True,
        include_large_sample=False,
        initial_files=(("local_testing/sbcv-test.f", fixture()),),
    )
    image = build_image(PROFILE_NAME, tmp_path / "sandbox-value-bridge.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=800_000_000,
        timeout=120.0,
    )
