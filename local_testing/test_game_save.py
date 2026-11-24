#!/usr/bin/env python3
"""Game saves (akashic/game/save.f).

A save is a CBOR map of text keys to integers, text strings and byte
strings, which a checked replacement writes in a place.  The checks run on
native machines (native_forth.py).  On a RAM volume they round-trip every
kind of value, compare the file's bytes with the host's own encoding, put
truncated, damaged and foreign files where the save lives and expect the
load to answer each as the host's reader below does, keep the old file
when a save is refused, answer a missing save and a read-only place, grow
the buffers with a large save and keep the heap flat over repeated saves
and loads.  Two checks save on the volumes a game's home lies on, the
MP64FS boot volume and an ext4 user volume, and the host reads the file
back from the disk image.
"""
from __future__ import annotations

import os
import random
import subprocess
from pathlib import Path

import pytest

from forth_dependencies import dependency_order
from native_forth import (
    MEGAPAD_ROOT,
    SOURCE_ROOT,
    NativeForth,
    SharedMachine,
    load_sources,
    module_source,
)

import sys

sys.path.insert(0, str(MEGAPAD_ROOT))

from diskutil import MP64FS  # noqa: E402
from simulator.platform import create_address_space  # noqa: E402
from simulator.runtime import MegaForthRuntime  # noqa: E402
from simulator.storage import HostedStorageService  # noqa: E402

ROOTS = ("game/save.f", "utils/fs/place-replace.f")

# GSAVE-S-* in game/save.f
OK, MISSING, CORRUPT, IO, READ_ONLY, RECOVERY, INVALID, NOMEM = range(8)
INT, STR, BLOB = 0, 1, 2

# =====================================================================
#  The host's CBOR: the encoding a save writes and the files it reads
# =====================================================================


def head(major: int, n: int) -> bytes:
    if n < 24:
        return bytes([major << 5 | n])
    for info, size in ((24, 1), (25, 2), (26, 4), (27, 8)):
        if n < 1 << (8 * size):
            return bytes([major << 5 | info]) + n.to_bytes(size, "big")
    raise ValueError(n)


def encode(entries: list[tuple[str, object]]) -> bytes:
    out = head(5, len(entries))
    for key, value in entries:
        name = key.encode()
        out += head(3, len(name)) + name
        if isinstance(value, int):
            out += head(0, value) if value >= 0 else head(1, -1 - value)
        elif isinstance(value, str):
            text = value.encode()
            out += head(3, len(text)) + text
        else:
            out += head(2, len(value)) + bytes(value)
    return out


def decode(data: bytes) -> list[tuple[bytes, int, object]] | None:
    """The entries a load answers for DATA, as (key, type, value), or None
    when the load must refuse it: anything but one definite map of
    distinct UTF-8 text keys to integers that fit a signed cell, UTF-8
    text and byte strings, with nothing after it."""

    pos = 0

    def read_head() -> tuple[int, int]:
        nonlocal pos
        if pos >= len(data):
            raise ValueError("end")
        major, info = data[pos] >> 5, data[pos] & 31
        if info < 24:
            pos += 1
            return major, info
        if info > 27:
            raise ValueError("info")
        size = 1 << (info - 24)
        if pos + 1 + size > len(data):
            raise ValueError("short head")
        value = int.from_bytes(data[pos + 1:pos + 1 + size], "big")
        pos += 1 + size
        return major, value

    def read_string(wanted: int) -> bytes:
        nonlocal pos
        major, n = read_head()
        if major != wanted or n > len(data) - pos:
            raise ValueError("string")
        text = data[pos:pos + n]
        pos += n
        return text

    try:
        major, count = read_head()
        if major != 5:
            raise ValueError("map")
        entries = []
        for _ in range(count):
            key = read_string(3)
            key.decode("utf-8")
            if pos >= len(data):
                raise ValueError("end")
            major = data[pos] >> 5
            if major in (0, 1):
                major, n = read_head()
                if n >= 1 << 63:
                    raise ValueError("range")
                entries.append((key, INT, n if major == 0 else -1 - n))
            elif major == 2:
                entries.append((key, BLOB, read_string(2)))
            elif major == 3:
                text = read_string(3)
                text.decode("utf-8")
                entries.append((key, STR, text))
            else:
                raise ValueError("type")
        if pos != len(data):
            raise ValueError("trailing")
        if len({key for key, _, _ in entries}) != len(entries):
            raise ValueError("repeated")
        return entries
    except (ValueError, UnicodeDecodeError):
        return None


def shown(entries) -> str:
    """ENTRIES as the guest's ENTRIES. prints them."""
    words = []
    for key, kind, value in entries:
        words.append("x" + key.hex())
        words.append(str(kind))
        words.append(str(value) if kind == INT else "x" + bytes(value).hex())
    return " ".join(words)


def forth_string(text: str) -> str:
    """An S" literal for TEXT, which holds no double quote."""
    assert '"' not in text
    return f'S" {text}"'


# =====================================================================
#  The guest: a RAM volume with a home and a read-only grant of it
# =====================================================================

HELPERS = (
    'VARIABLE VA  VARIABLE PVA  VARIABLE D-HOME  VARIABLE SET',
    'VARIABLE P-HOME  VARIABLE P-RO  VARIABLE REPL  VARIABLE RREPL',
    'VARIABLE CTX  VARIABLE LD  VARIABLE T-FD  VARIABLE FB-LEN',
    'VARIABLE X0',
    'CREATE FB 65536 ALLOT',
    ': T-SETUP  ( -- )',
    # The RAM binding keeps a replaced file's buffer until the volume
    # goes, so the arena holds every file the checks put.
    '    16777216 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN VA !',
    '    S" game" VA @ VFS-MKDIR THROW',
    '    S" va" PLACES-VOLUME THROW PVA !  VA @ PVA @ PVOL-ATTACH THROW',
    '    S" game" S" /game" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW D-HOME !',
    '    PLSET-NEW THROW SET !',
    '    PLACE-WRITABLE D-HOME @ SET @ PLSET-GRANT THROW P-HOME !',
    '    PLSET-NEW THROW >R',
    '    PLACE-READ-ONLY D-HOME @ R> PLSET-GRANT THROW P-RO !',
    '    VREPL-SIZE ALLOCATE THROW DUP VREPL-SIZE 0 FILL REPL !',
    '    VREPL-SIZE ALLOCATE THROW DUP VREPL-SIZE 0 FILL RREPL !',
    '    S" /night.sav" P-HOME @ -1 REPL @ PLACE-VREPL! THROW',
    '    S" /night.sav" P-RO @ 0 RREPL @ PLACE-VREPL! THROW  0 FB-LEN ! ;',
    'T-SETUP',
    # Hex text appended to FB; FB put as the save file
    ': HX-DIGIT  ( c -- n )  DUP 97 >= IF 87 - ELSE 48 - THEN ;',
    ': HX+  ( a u -- )',
    '    0 ?DO',
    '        DUP I + C@ HX-DIGIT 4 LSHIFT  OVER I + 1+ C@ HX-DIGIT OR',
    '        FB FB-LEN @ + C!  1 FB-LEN +!',
    '    2 +LOOP DROP ;',
    ': PUT  ( -- )  FB FB-LEN @ REPL @ VREPL-REPLACE ABORT" put"  0 FB-LEN ! ;',
    # Printing bytes, the file and a load's entries
    ': H1  ( n -- )  DUP 10 < IF 48 ELSE 87 THEN + EMIT ;',
    ': H2  ( c -- )  DUP 4 RSHIFT H1 15 AND H1 ;',
    ': HX.  ( a u -- )  ." x" 0 ?DO DUP I + C@ H2 LOOP DROP SPACE ;',
    ': FILE.  ( -- )',
    '    S" /night.sav" VFS-FF-READ P-HOME @ PLACE-OPEN ABORT" open" T-FD !',
    '    FB T-FD @ VFS-SIZE DUP >R T-FD @ VFS-READ-EXACT ABORT" read"',
    '    T-FD @ VFS-CLOSE  FB R> HX. ;',
    ': ENTRIES.  ( ld -- )',
    '    DUP GLOAD-COUNT 0 ?DO',
    '        DUP _GLD-O-INDEX + @ I _GLD-ENTRY-SZ * +',
    '        DUP @ OVER CELL+ @ HX.',
    '        DUP 2 CELLS + @ DUP .',
    '        _GSV-T-INT = IF 3 CELLS + @ . ELSE',
    '            DUP 3 CELLS + @ SWAP 4 CELLS + @ HX. THEN',
    '    LOOP DROP ;',
    # A load through REPL: its status, then its count and entries
    ': LOAD.  ( repl -- )',
    '    GLOAD-OPEN DUP . IF DROP EXIT THEN',
    '    DUP GLOAD-COUNT . DUP ENTRIES. GLOAD-CLOSE ;',
)

SUITE = NativeForth(ROOTS, prelude=HELPERS)


def words(raw: bytes) -> str:
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (10, 13, 9) else ""
                   for b in raw)
    assert "RESULT:" in text, text[-600:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail and "ABORT" not in tail, tail[-600:]
    return " ".join(tail.split()).lower()


def run(lines, max_steps=400_000_000) -> str:
    return words(SUITE.run(['." RESULT: "', *lines, 'CR'], max_steps))


def put_lines(data: bytes) -> list[str]:
    """Lines that make DATA the save file."""
    hexed = data.hex()
    lines = [f'S" {hexed[at:at + 128]}" HX+' for at in range(0, len(hexed), 128)]
    return lines + ["PUT"]


def save_lines(entries, ctx: str = "CTX @") -> list[str]:
    """A word that adds ENTRIES to the save context CTX, and its call.  The
    strings are compiled, since an interpreted S" reuses one buffer."""
    body = []
    for key, value in entries:
        k = forth_string(key)
        if isinstance(value, int):
            body.append(f"{ctx} {k} {value} GSAVE-INT")
        elif isinstance(value, str):
            body.append(f"{ctx} {k} {forth_string(value)} GSAVE-STR")
        else:
            body += [f'0 FB-LEN !  S" {value.hex()}" HX+',
                     f"{ctx} {k} FB FB-LEN @ GSAVE-BLOB"]
    return [": ADD", *body, ";", "ADD"]


def expected(entries) -> list[tuple[bytes, int, object]]:
    out = []
    for key, value in entries:
        if isinstance(value, int):
            out.append((key.encode(), INT, value))
        elif isinstance(value, str):
            out.append((key.encode(), STR, value.encode()))
        else:
            out.append((key.encode(), BLOB, bytes(value)))
    return out


# Every head size, both signs, multibyte text, an empty key and empties
VALUES = [
    ("night", 3), ("zero", 0), ("i23", 23), ("i24", 24), ("i255", 255),
    ("i256", 256), ("i65535", 65535), ("i65536", 65536),
    ("i2^32-1", 2**32 - 1), ("i2^32", 2**32), ("max", 2**63 - 1),
    ("m1", -1), ("m24", -24), ("m25", -25), ("m256", -256),
    ("m257", -257), ("m2^32", -(2**32) - 1), ("min", -(2**63)),
    ("name", "Ember – lamp été 機 \U0001f56f"),
    ("empty", ""),
    ("", 7), ("fog", bytes(range(0, 250, 7))), ("nothing", b""),
]


def test_a_save_round_trips_every_kind_of_value():
    """Integers at each CBOR head size and of both signs, text with
    characters of two, three and four UTF-8 bytes, empty text, an empty
    key and byte strings come back as saved, and the file's bytes are the
    host's own encoding of the map."""
    got = run([
        ": T  GSAVE-NEW CTX ! ;", "T",
        *save_lines(VALUES),
        "CTX @ REPL @ GSAVE-WRITE .",
        "FILE.",
        "REPL @ LOAD.",
        "CTX @ GSAVE-FREE",
    ])
    want = (f"0 x{encode(VALUES).hex()} 0 {len(VALUES)} "
            f"{shown(expected(VALUES))}")
    assert got == want.lower(), got


def test_lookups_answer_the_kind_asked_for():
    """A key answers through the word for its kind only, and a key the
    save lacks answers not found with zeros."""
    got = run([
        ": T  GSAVE-NEW CTX !",
        '     CTX @ S" night" 12 GSAVE-INT',
        '     CTX @ S" name" S" Ember" GSAVE-STR',
        '     CTX @ S" fog" S" abc" GSAVE-BLOB',
        "     CTX @ REPL @ GSAVE-WRITE .",
        "     REPL @ GLOAD-OPEN . LD !",
        '     LD @ S" night" GLOAD-INT . .',
        '     LD @ S" name" GLOAD-STR ROT DROP . .',
        '     LD @ S" fog" GLOAD-BLOB . NIP .',
        '     LD @ S" night" GLOAD-STR . . .',
        '     LD @ S" name" GLOAD-BLOB . . .',
        '     LD @ S" fog" GLOAD-INT . .',
        '     LD @ S" nigh" GLOAD-INT . .',
        '     LD @ S" nights" GLOAD-INT . .',
        "     LD @ GLOAD-COUNT .",
        "     LD @ GLOAD-CLOSE  CTX @ GSAVE-FREE ;",
        "T",
    ])
    assert got == ("0 0 -1 12 -1 5 -1 3 0 0 0 0 0 0 0 0 "
                   "0 0 0 0 3"), got


def variants(data: bytes, seed: int) -> list[bytes]:
    """Every truncation of DATA, bytes replaced, inserted and removed at
    random, and foreign files."""
    rng = random.Random(seed)
    out = [data[:cut] for cut in range(len(data))]
    for _ in range(160):
        damaged = bytearray(data)
        for _ in range(rng.choice((1, 1, 1, 2, 3))):
            damaged[rng.randrange(len(damaged))] = rng.randrange(256)
        out.append(bytes(damaged))
    for _ in range(30):
        at = rng.randrange(len(data) + 1)
        out.append(data[:at] + bytes([rng.randrange(256)]) + data[at:])
        at = rng.randrange(len(data))
        out.append(data[:at] + data[at + 1:])
    out += [
        b"hello, world",
        head(4, 2) + head(0, 1) + head(0, 2),              # an array
        head(5, 1) + head(0, 1) + head(0, 2),              # an integer key
        head(5, 1) + head(3, 1) + b"k" + b"\xf9\x3c\x00",  # a half float
        head(5, 1) + head(3, 1) + b"k" + b"\xf5",          # true
        head(5, 1) + head(3, 1) + b"k" + head(6, 1) + head(0, 5),  # a tag
        head(5, 1) + head(3, 1) + b"k" + head(4, 0),       # an array value
        head(5, 1) + head(3, 1) + b"k" + head(5, 0),       # a map value
        b"\xbf" + head(3, 1) + b"k" + head(0, 1) + b"\xff",  # indefinite
        head(5, 1) + head(3, 1) + b"k" + b"\x1c",          # reserved info
        head(5, 1) + head(3, 1) + b"k" + b"\x1b" + b"\x80" + bytes(7),
        head(5, 1) + head(3, 1) + b"k" + b"\x3b" + b"\x80" + bytes(7),
        head(5, 1) + head(3, 1) + b"k" + b"\x1b" + b"\x7f" + b"\xff" * 7,
        head(5, 1) + head(3, 1) + b"k" + b"\x3b" + b"\x7f" + b"\xff" * 7,
        head(5, 1) + head(3, 1) + b"k" + b"\x18\x05",      # not shortest
        head(5, 2) + (head(3, 1) + b"k" + head(0, 1)) * 2,  # repeated key
        head(5, 1) + head(3, 1) + b"k" + head(0, 1) + b"\x00",  # trailing
        head(5, 1) + head(3, 2) + b"\xc3\x28" + head(0, 1),  # bad UTF-8 key
        head(5, 1) + head(3, 1) + b"k" + head(3, 3) + b"\xed\xa0\x80",
        head(5, 1) + head(3, 1) + b"k" + head(3, 2) + b"\xc0\xaf",
        head(5, 1) + head(3, 1) + b"k" + head(2, 2) + b"\xc0\xaf",
        head(5, 0),
        head(5, 3) + head(3, 1) + b"k" + head(0, 1),       # pairs missing
        b"\xbb" + b"\xff" * 8,                              # a huge map
        head(5, 1) + head(3, 1) + b"k" + b"\x5b" + b"\xff" * 8,  # huge bytes
        # Lengths past the file's end, and past memory's
        head(5, 1) + b"\x7b" + b"\xff" * 8 + b"k" + head(0, 1),
        head(5, 1) + head(3, 1) + b"k" + b"\x7b\x7f" + b"\xff" * 7 + b"ab",
        head(5, 1) + head(3, 1) + b"k" + b"\x7a\x00\x01\x00\x00" + b"ab",
    ]
    return out


def test_a_load_refuses_every_file_the_hosts_reader_refuses():
    """Each truncation of a save, a few hundred damaged copies of it and
    foreign files are put where the save lives.  The load answers each as
    the host's reader answers it: corrupt, or the entries it holds."""
    base = encode(VALUES[:12] + VALUES[18:])
    files = variants(base, seed=20261123)
    lines = []
    for index, data in enumerate(files):
        lines += [f'." |{index} "', *put_lines(data), "REPL @ LOAD."]
    got = run(lines, max_steps=4_000_000_000)
    answers = got.split("|")[1:]
    assert len(answers) == len(files), (len(answers), len(files))
    refused = 0
    for index, (data, answer) in enumerate(zip(files, answers)):
        entries = decode(data)
        if entries is None:
            refused += 1
            want = f"{index} {CORRUPT}"
        else:
            want = f"{index} 0 {len(entries)} {shown(entries)}".rstrip()
        assert answer.strip() == want.lower(), (data.hex(), answer)
    # Most damage is caught, and some damage still makes a save.
    assert refused > len(files) // 2
    assert refused < len(files)


def test_a_missing_save_and_a_read_only_place():
    """With no file a load answers missing.  A save through a read-only
    grant of the home answers read-only and leaves no file, and once a
    writable grant has saved, the read-only grant loads the save."""
    got = run([
        ": T  REPL @ LOAD.  RREPL @ LOAD.",
        "     GSAVE-NEW CTX !",
        '     CTX @ S" night" 4 GSAVE-INT',
        "     CTX @ RREPL @ GSAVE-WRITE .  REPL @ LOAD.",
        "     CTX @ REPL @ GSAVE-WRITE .  RREPL @ LOAD.",
        "     CTX @ GSAVE-FREE ;",
        "T",
    ])
    assert got == (f"{MISSING} {MISSING} {READ_ONLY} {MISSING} 0 "
                   f"0 1 x{b'night'.hex()} {INT} 4"), got


def test_a_refused_save_keeps_the_old_file():
    """A save with a repeated key, a key that is not UTF-8 or text that
    is not UTF-8 is refused before anything is written, and the last
    good save stays.  GSAVE-RESET empties the context for the next save,
    which may hold fewer entries."""
    got = run([
        ": T  GSAVE-NEW CTX !",
        '     CTX @ S" night" 4 GSAVE-INT  CTX @ S" lamp" 9 GSAVE-INT',
        "     CTX @ REPL @ GSAVE-WRITE .",
        '     CTX @ S" night" 5 GSAVE-INT  CTX @ REPL @ GSAVE-WRITE .',
        "     REPL @ LOAD. ;",
        "T",
        "195 FB C!  40 FB 1+ C!",
        ": U  CTX @ GSAVE-RESET  CTX @ FB 2 1 GSAVE-INT",
        "     CTX @ REPL @ GSAVE-WRITE .  REPL @ LOAD.",
        '     CTX @ GSAVE-RESET  CTX @ S" k" FB 2 GSAVE-STR',
        "     CTX @ REPL @ GSAVE-WRITE .  REPL @ LOAD.",
        '     CTX @ GSAVE-RESET  CTX @ S" k" FB 2 GSAVE-BLOB',
        "     CTX @ REPL @ GSAVE-WRITE .  REPL @ LOAD.",
        "     CTX @ GSAVE-FREE ;",
        "U",
    ])
    first = shown([(b"night", INT, 4), (b"lamp", INT, 9)])
    assert got == (f"0 {INVALID} 0 2 {first} "
                   f"{INVALID} 0 2 {first} "
                   f"{INVALID} 0 2 {first} "
                   f"0 0 1 x{b'k'.hex()} {BLOB} xc328"), got


def test_buffers_grow_with_the_save_and_the_heap_stays_flat():
    """Three hundred entries and a blob of 20,000 bytes grow the entry
    and encoding buffers and round-trip.  Ten more saves and loads of the
    same entries leave the extended heap where the first left it."""
    lines = [
        "CREATE KB 32 ALLOT",
        ': KEY$  ( n -- a u )  S" key-" KB SWAP CMOVE',
        "     DUP 100 / 48 + KB 4 + C!  DUP 10 / 10 MOD 48 + KB 5 + C!",
        "     10 MOD 48 + KB 6 + C!  KB 7 ;",
        ": FILL-BLOB  20000 0 DO I 31 * 251 MOD FB I + C! LOOP ;",
        ": ENTRIES+  300 0 DO CTX @ I KEY$ I 7919 * 1000000 - GSAVE-INT LOOP",
        '     CTX @ S" blob" FB 20000 GSAVE-BLOB ;',
        ": ONE  ( -- write-status load-status )",
        "     CTX @ GSAVE-RESET ENTRIES+  CTX @ REPL @ GSAVE-WRITE",
        "     REPL @ GLOAD-OPEN SWAP LD ! ;",
        ": ALL?  ( -- n )  0 300 0 DO",
        "     LD @ I KEY$ GLOAD-INT SWAP I 7919 * 1000000 - = AND IF 1+ THEN",
        "     LOOP ;",
        ": T  FILL-BLOB  GSAVE-NEW CTX !  ONE . .  LD @ GLOAD-COUNT .",
        '     LD @ S" key-299" GLOAD-INT . .  ALL? .',
        '     LD @ S" blob" GLOAD-BLOB . FB 20000 COMPARE .',
        "     LD @ GLOAD-CLOSE ;",
        "T",
        ": U  ONE 2DROP LD @ GLOAD-CLOSE  XMEM-HERE @ X0 !",
        "     0 10 0 DO ONE OR OR LD @ GLOAD-CLOSE LOOP .",
        "     XMEM-HERE @ X0 @ - .  CTX @ GSAVE-FREE ;",
        "U",
    ]
    got = run(lines, max_steps=4_000_000_000)
    assert got == f"0 0 301 -1 {299 * 7919 - 1_000_000} 300 -1 0 0 0", got


# =====================================================================
#  The volumes a game's home lies on
# =====================================================================

BOOT_HELPERS = (
    'VARIABLE CTX  VARIABLE LD  VARIABLE REPL',
    ': T-BOOT  ( -- )',
    '    S" boot" PLACES-VOLUME THROW',
    '    >R S" game" S" /game" PLACE-WRITABLE R> PLACES-DECLARE THROW',
    '    PLSET-NEW THROW PLACE-WRITABLE -ROT PLSET-GRANT THROW',
    '    VREPL-SIZE ALLOCATE THROW DUP VREPL-SIZE 0 FILL DUP REPL !',
    '    S" /night.sav" 2SWAP -1 SWAP PLACE-VREPL! THROW ;',
)

GAME_ENTRIES = [("night", 2), ("lamp-oil", -3), ("name", "Ember"),
                ("fog", bytes(range(40)))]


def game_save_lines() -> list[str]:
    """Lines that fill a save context with GAME_ENTRIES."""
    adds = []
    for key, value in GAME_ENTRIES:
        if isinstance(value, bytes):
            adds.append(f'CTX @ S" {key}" T-FOG {len(value)} GSAVE-BLOB')
        elif isinstance(value, int):
            adds.append(f'CTX @ S" {key}" {value} GSAVE-INT')
        else:
            adds.append(f'CTX @ S" {key}" S" {value}" GSAVE-STR')
    fog = dict(GAME_ENTRIES)["fog"]
    return ["CREATE T-FOG " + " ".join(f"{b} C," for b in fog),
            ": ADD  GSAVE-NEW CTX !  " + "  ".join(adds) + " ;", "ADD"]


GAME_CHECKS = ["CTX @ REPL @ GSAVE-WRITE .",
               "REPL @ GLOAD-OPEN . LD !",
               'LD @ GLOAD-COUNT .  LD @ S" lamp-oil" GLOAD-INT . .',
               "LD @ GLOAD-CLOSE  CTX @ GSAVE-FREE"]


def boot_image(total_sectors: int) -> bytes:
    fs = MP64FS(total_sectors=total_sectors)
    fs.format()
    fs.mkdir("/game")
    return bytes(fs.img)


def test_a_save_round_trips_on_the_mp64fs_boot_volume():
    """A game whose home lies on the MP64FS boot volume saves there, and
    the host reads the disk image: the file is the save's encoding."""
    storage = HostedStorageService(boot_image(2048))
    runtime = MegaForthRuntime(
        memory=create_address_space(external_size=128 << 20,
                                    hbw_size=1 << 20),
        execution_backend="native",
        storage=storage,
    )
    sources = [("kdos.f", (MEGAPAD_ROOT / "kdos.f").read_bytes()),
               ("userland", b"ENTER-USERLAND\n")]
    roots = ROOTS + ("tui/platform/mp64fs-vfs.f",)
    sources += [(module, module_source(SOURCE_ROOT / module))
                for module in dependency_order(SOURCE_ROOT, roots)]
    sources.append(("prelude", ("\n".join(BOOT_HELPERS) + "\nT-BOOT\n")
                    .encode()))
    load_sources(runtime, sources, 800_000_000)
    got = words(SharedMachine(runtime).run(
        ['." RESULT: "', *game_save_lines(), *GAME_CHECKS, "CR"],
        400_000_000))
    assert got == "0 0 4 -1 -3", got
    fs = MP64FS(bytearray(storage.image_bytes))
    data = fs.read_file("night.sav", parent=fs.resolve_path("/game"))
    assert data == encode(GAME_ENTRIES)
    assert sorted(entry.name for entry in fs.list_files(
        parent=fs.resolve_path("/game"))) == ["night.sav"]


def _toolchain():
    if not os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR"):
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR to build user volumes")
    import akashic_tui as tui
    return tui._system_volume_toolchain()


def test_a_save_round_trips_on_an_ext4_user_volume(tmp_path: Path):
    """A game whose home lies on the ext4 user volume saves there.  The
    host's e2fsck passes the image, and debugfs reads the save's encoding
    back from it."""
    manifest, env, tools = _toolchain()
    import akashic_tui as tui
    from test_user_volume import ARENA, Machine

    image = tmp_path / "user.img"
    tui._build_user_image(image, 64 << 20, (manifest, env, tools),
                          documents={})
    machine = Machine(image.read_bytes(), roots=("game/save.f",),
                      helpers="\n".join(BOOT_HELPERS).replace(
                          'S" boot"', 'S" user"').replace(
                          'S" /game"', 'S" /documents"'))
    assert machine.run(f"{ARENA} USERVOL-MOUNT") == (0,)
    assert machine.run("T-BOOT") == ()
    for line in game_save_lines():
        assert machine.run(line) == ()
    assert machine.run("CTX @ REPL @ GSAVE-WRITE") == (0,)
    ctx, status = machine.run("REPL @ GLOAD-OPEN")
    assert status == 0
    assert machine.run(f"{ctx} GLOAD-COUNT") == (4,)
    assert machine.run(f'{ctx} S" name" GLOAD-STR ROT DROP') == (5, 2**64 - 1)
    machine.run(f"{ctx} GLOAD-CLOSE  CTX @ GSAVE-FREE")
    assert machine.run("USERVOL-VFS VFS-SYNC") == (0,)
    image.write_bytes(machine.user.image_bytes)
    checked = subprocess.run(
        [tools["e2fsck"]["path"], "-f", "-n", str(image)],
        env=env, text=True, capture_output=True, check=False,
    )
    assert checked.returncode == 0, checked.stdout + checked.stderr
    read = subprocess.run(
        [tools["debugfs"]["path"], "-R", "cat /documents/night.sav",
         str(image)],
        env=env, capture_output=True, check=False,
    )
    assert read.returncode == 0, read.stderr
    assert read.stdout == encode(GAME_ENTRIES)
