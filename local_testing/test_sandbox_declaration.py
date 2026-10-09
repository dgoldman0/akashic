#!/usr/bin/env python3
"""Canonical sandbox module declarations.

A Python reference builds declarations (docs/sandbox/declaration-format.md)
and digests them.  The emulator must write the same bytes from the same
parts, digest them as hashlib does, read every field back, refuse each
writer misuse with its status, and refuse every noncanonical byte variant
with the status the format gives it.
"""

from __future__ import annotations

import hashlib
import sys
from dataclasses import dataclass
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


# ---------------------------------------------------------------------
# Reference
# ---------------------------------------------------------------------

OK, INVALID, CAPACITY, ALIAS, STATE, DIGEST, FAULT = range(7)

MAGIC = b"AKSBXDCL"
FORMAT = 1
HEADER = 184
LIMIT_SIZE = 16
ENTRY_SIZE = 168
BYTES_MAX = 16 * 1024 * 1024
ENTRY_MAX = 4096
NAME_MAX = 63
NONE, PACKAGE = 0, 1

# The limit fields, numbered as the declaration stores them.
LIMIT_FIELDS = (
    "INSTRUCTION-BUDGET", "VALUE-OP-BUDGET", "COPY-BUDGET", "WALL-MS",
    "DEPTH", "BLOB-BYTES", "LIST-COUNT", "MAP-COUNT",
    "INPUT-NODES", "INPUT-BYTES", "OUTPUT-ARENA-NODES",
    "OUTPUT-ARENA-BYTES", "OUTPUT-RESULT-NODES", "OUTPUT-RESULT-BYTES",
    "DATA-STACK", "CALL-FRAMES", "LOOP-FRAMES", "MEMORY-BYTES",
)
LIMIT_COUNT = len(LIMIT_FIELDS)
UNBOUNDED = 2 ** 63 - 1


def le(n: int, width: int) -> bytes:
    return (n & ((1 << (8 * width)) - 1)).to_bytes(width, "little")


def schema_digest(document: bytes) -> bytes:
    return hashlib.sha3_256(b"akashic.sandbox.schema\x00" + document).digest()


def declaration_digest(declaration: bytes) -> bytes:
    return hashlib.sha3_256(
        b"akashic.sandbox.declaration\x00" + declaration).digest()


@dataclass(frozen=True)
class Entry:
    name: bytes
    signature: int
    input: bytes
    output: bytes


@dataclass(frozen=True)
class Declaration:
    module: bytes
    revision: int
    artifact: bytes
    profile: bytes
    entries: tuple[Entry, ...]
    limits: tuple[tuple[int, int], ...] = ()
    provenance: tuple[int, bytes, int] = (NONE, bytes(32), 0)

    def schema_bytes(self) -> int:
        return sum(len(e.input) + len(e.output) for e in self.entries)

    def size(self) -> int:
        return (HEADER + LIMIT_SIZE * len(self.limits)
                + ENTRY_SIZE * len(self.entries) + self.schema_bytes())


def build(d: Declaration) -> bytes:
    schemas = b""
    records = b""
    for entry in d.entries:
        record = (le(len(entry.name), 2) + le(0, 2) + le(entry.signature, 4)
                  + entry.name.ljust(64, b"\0"))
        for document in (entry.input, entry.output):
            record += (le(len(schemas), 8) + le(len(document), 8)
                       + schema_digest(document))
            schemas += document
        assert len(record) == ENTRY_SIZE
        records += record
    limits = b"".join(le(f, 2) + bytes(6) + le(v, 8) for f, v in d.limits)
    kind, rid, revision = d.provenance
    header = (MAGIC + le(FORMAT, 2) + le(HEADER, 2) + le(0, 4)
              + le(d.size(), 8) + le(len(d.entries), 4) + le(len(d.limits), 2)
              + le(kind, 2) + le(len(schemas), 8) + le(d.revision, 8)
              + d.module + d.artifact + d.profile + rid + le(revision, 8))
    assert len(header) == HEADER
    out = header + limits + records + schemas
    assert len(out) == d.size()
    return out


def name_ok(name: bytes) -> bool:
    if not 1 <= len(name) <= NAME_MAX:
        return False
    if not ord("a") <= name[0] <= ord("z"):
        return False
    return all(chr(b) in "abcdefghijklmnopqrstuvwxyz0123456789._-"
               for b in name)


def validate(d: bytes) -> int:
    """The format's rules, in the order the emulator applies them."""
    def u(offset: int, width: int) -> int:
        return int.from_bytes(d[offset:offset + width], "little")

    if len(d) < HEADER or d[:8] != MAGIC:
        return INVALID
    if u(8, 2) != FORMAT or u(10, 2) != HEADER or u(12, 4) != 0:
        return INVALID
    if u(16, 8) != len(d):
        return INVALID
    entry_n, limit_n, schema_u = u(24, 4), u(28, 2), u(32, 8)
    if not 1 <= entry_n <= ENTRY_MAX or limit_n > LIMIT_COUNT:
        return INVALID
    if schema_u > BYTES_MAX:
        return INVALID
    if HEADER + LIMIT_SIZE * limit_n + ENTRY_SIZE * entry_n + schema_u \
            != len(d):
        return INVALID
    if not 0 < u(40, 8) < 2 ** 63:
        return INVALID
    if not any(d[48:80]) or not any(d[80:112]) or not any(d[112:144]):
        return INVALID
    kind, rid, revision = u(30, 2), d[144:176], u(176, 8)
    if kind == NONE:
        if any(rid) or revision:
            return INVALID
    elif kind == PACKAGE:
        if not any(rid) or not 0 < revision < 2 ** 63:
            return INVALID
    else:
        return INVALID

    previous = -1
    for i in range(limit_n):
        at = HEADER + LIMIT_SIZE * i
        field, value = u(at, 2), u(at + 8, 8)
        if any(d[at + 2:at + 8]):
            return INVALID
        if not 0 < value < UNBOUNDED:
            return INVALID
        if field >= LIMIT_COUNT or field <= previous:
            return INVALID
        previous = field

    entries = HEADER + LIMIT_SIZE * limit_n
    schemas = entries + ENTRY_SIZE * entry_n
    cursor = 0
    last_name = None
    for i in range(entry_n):
        at = entries + ENTRY_SIZE * i
        if u(at + 2, 2) or u(at + 4, 4) < 1:
            return INVALID
        name_u = u(at, 2)
        name = d[at + 8:at + 8 + name_u]
        if not name_ok(name) or any(d[at + 8 + name_u:at + 72]):
            return INVALID
        if last_name is not None and not name > last_name:
            return INVALID
        last_name = name
        for slot in (at + 72, at + 120):
            offset, length = u(slot, 8), u(slot + 8, 8)
            if offset != cursor or not 0 < length < 2 ** 63:
                return INVALID
            if length > schema_u - cursor:
                return INVALID
            span = d[schemas + cursor:schemas + cursor + length]
            if schema_digest(span) != d[slot + 16:slot + 48]:
                return DIGEST
            cursor += length
    if cursor != schema_u:
        return INVALID
    return OK


# Canonical schema documents (docs/interop/schema-bytes.md).  This layer
# treats them as opaque bytes bound by their digests.
INTEGER = b"AKSCHEMA" + bytes([0x04, 0, 0, 0])
TEXT = b"AKSCHEMA" + bytes([0x10, 0, 0x04, 0]) + le(32, 8)
PAIR = (b"AKSCHEMA" + bytes([0x80, 0, 0x10, 0]) + le(2, 2)
        + le(1, 4) + b"a" + b"\x01" + INTEGER[8:]
        + le(1, 4) + b"b" + b"\x01" + INTEGER[8:])


def rid(seed: int) -> bytes:
    return bytes((seed + i) % 251 + 1 for i in range(32))


FULL = Declaration(
    module=rid(11),
    revision=7,
    artifact=rid(53),
    profile=rid(97),
    entries=(
        Entry(b"add", 1, PAIR, INTEGER),
        Entry(b"echo.v2", 1, TEXT, TEXT),
        Entry(b"len-of_x", 1, TEXT, INTEGER),
    ),
    limits=((LIMIT_FIELDS.index("INSTRUCTION-BUDGET"), 1_000_000),
            (LIMIT_FIELDS.index("MEMORY-BYTES"), 65_536)),
    provenance=(PACKAGE, rid(149), 3),
)

MINIMAL = Declaration(
    module=rid(2),
    revision=1,
    artifact=rid(3),
    profile=rid(5),
    entries=(Entry(b"z", 1, INTEGER, INTEGER),),
)


def patched(base: bytes, offset: int, data: bytes) -> bytes:
    return base[:offset] + data + base[offset + len(data):]


def flipped(base: bytes, offset: int) -> bytes:
    return patched(base, offset, bytes([base[offset] ^ 0xFF]))


def entry_at(d: Declaration, index: int) -> int:
    return HEADER + LIMIT_SIZE * len(d.limits) + ENTRY_SIZE * index


def schemas_at(d: Declaration) -> int:
    return entry_at(d, len(d.entries))


def mutations() -> list[tuple[str, bytes, int]]:
    """Noncanonical variants of FULL and MINIMAL with their statuses."""
    full = build(FULL)
    minimal = build(MINIMAL)
    e0, e1, e2 = (entry_at(FULL, i) for i in range(3))
    s = schemas_at(FULL)
    out = [
        ("magic", patched(full, 0, b"AKSBXDCM"), INVALID),
        ("format 2", patched(full, 8, le(2, 2)), INVALID),
        ("header 183", patched(full, 10, le(183, 2)), INVALID),
        ("flags", patched(full, 12, le(1, 4)), INVALID),
        ("total + 1", patched(full, 16, le(len(full) + 1, 8)), INVALID),
        ("no entries", patched(full, 24, le(0, 4)), INVALID),
        ("entry count + 1", patched(full, 24, le(4, 4)), INVALID),
        ("4097 entries", patched(full, 24, le(4097, 4)), INVALID),
        ("19 limits", patched(full, 28, le(19, 2)), INVALID),
        ("one limit fewer", patched(full, 28, le(1, 2)), INVALID),
        ("schema bytes + 1", patched(full, 32, le(FULL.schema_bytes() + 1, 8)),
         INVALID),
        ("schema bytes huge", patched(full, 32, le(2 ** 63, 8)), INVALID),
        ("revision 0", patched(full, 40, le(0, 8)), INVALID),
        ("revision negative", patched(full, 40, le(2 ** 63, 8)), INVALID),
        ("module zero", patched(full, 48, bytes(32)), INVALID),
        ("artifact zero", patched(full, 80, bytes(32)), INVALID),
        ("profile zero", patched(full, 112, bytes(32)), INVALID),
        ("provenance kind 2", patched(full, 30, le(2, 2)), INVALID),
        ("package without RID", patched(full, 144, bytes(32)), INVALID),
        ("package revision 0", patched(full, 176, le(0, 8)), INVALID),
        ("package revision negative", patched(full, 176, le(2 ** 63, 8)),
         INVALID),
        ("none with a revision",
         patched(patched(full, 30, le(NONE, 2)), 144, bytes(32)), INVALID),
        ("none with a RID",
         patched(patched(full, 30, le(NONE, 2)), 176, le(0, 8)), INVALID),
        ("limit padding", patched(full, HEADER + 5, b"\x01"), INVALID),
        ("limit value 0", patched(full, HEADER + 8, le(0, 8)), INVALID),
        ("limit value unbounded", patched(full, HEADER + 8, le(UNBOUNDED, 8)),
         INVALID),
        ("limit value negative", patched(full, HEADER + 8, le(2 ** 63, 8)),
         INVALID),
        ("limit field 18", patched(full, HEADER + 16, le(18, 2)), INVALID),
        ("limit fields repeat", patched(full, HEADER + 16, le(0, 2)), INVALID),
        ("limit fields descend",
         patched(patched(full, HEADER, le(17, 2)), HEADER + 16, le(0, 2)),
         INVALID),
        ("entry reserved", patched(full, e0 + 2, le(1, 2)), INVALID),
        ("signature 0", patched(full, e1 + 4, le(0, 4)), INVALID),
        ("name length 0", patched(full, e0, le(0, 2)), INVALID),
        ("name length 64", patched(full, e0, le(64, 2)), INVALID),
        ("name uppercase", patched(full, e1 + 8, b"E"), INVALID),
        ("name digit first", patched(full, e1 + 8, b"1"), INVALID),
        ("name space", patched(full, e1 + 9, b" "), INVALID),
        ("name tail", patched(full, e0 + 8 + 3, b"x"), INVALID),
        ("name tail end", patched(full, e0 + 71, b"\x01"), INVALID),
        ("names repeat", patched(full, e1, le(3, 2) + le(0, 2) + le(1, 4)
                                 + b"add".ljust(64, b"\0")), INVALID),
        ("names descend", patched(full, e2 + 8, b"aaaaaaaa"), INVALID),
        ("input offset", patched(full, e0 + 72, le(1, 8)), INVALID),
        ("input empty", patched(full, e0 + 80, le(0, 8)), INVALID),
        ("output past the end",
         patched(full, e2 + 128, le(FULL.schema_bytes(), 8)), INVALID),
        ("output length huge", patched(full, e2 + 128, le(2 ** 63, 8)),
         INVALID),
        ("schema byte", patched(full, s + 8, b"\x05"), DIGEST),
        ("last schema byte", flipped(full, len(full) - 1), DIGEST),
        ("input digest", flipped(full, e0 + 72 + 16), DIGEST),
        ("output digest", flipped(full, e1 + 120 + 47), DIGEST),
        ("last schema short",
         patched(full, e2 + 128, le(len(INTEGER) - 1, 8)), DIGEST),
        ("minimal magic", patched(minimal, 0, b"XKSBXDCL"), INVALID),
        ("minimal provenance revision", patched(minimal, 176, le(1, 8)),
         INVALID),
    ]
    # Spare bytes after the last schema: every slot is right, but the
    # schemas do not cover the section.
    spare = bytearray(minimal + b"\x00")
    spare[16:24] = le(len(spare), 8)
    spare[32:40] = le(MINIMAL.schema_bytes() + 1, 8)
    out.append(("spare schema byte", bytes(spare), INVALID))
    return out


TRUNCATED = (("truncated by one", len(build(FULL)) - 1),
             ("header only", HEADER),
             ("too short for a header", HEADER - 1))


# ---------------------------------------------------------------------
# Forth fixture
# ---------------------------------------------------------------------

def hex_lines(data: bytes) -> list[str]:
    text = data.hex()
    return [f'S" {text[i:i + 96]}" _bx-add' for i in range(0, len(text), 96)]


def blob(number: int, data: bytes) -> list[str]:
    """Defines and runs a word that loads DATA as blob NUMBER."""
    return ([f": _dc-blob-{number}  ( -- )", "    _bx-begin"]
            + ["    " + line for line in hex_lines(data)]
            + [f"    _bx-end {number} _dc-blob! ;", f"_dc-blob-{number}"])


def forth_string(data: bytes) -> str:
    text = data.decode()
    assert '"' not in text and len(text) < 100
    return f'S" {text}"'


PRELUDE = r"""\ Generated: sandbox module declarations.
PROVIDED sbox-declaration-tests

VARIABLE _dc-fails
VARIABLE _dc-checks
VARIABLE _dc-case
VARIABLE _dc-depth

CREATE _bx-pool 32768 ALLOT
VARIABLE _bx-top
VARIABLE _bx-start
CREATE _dc-blobs 64 16 * ALLOT
CREATE _dc-decl-raw 4096 15 + ALLOT
CREATE _dc-copy-raw 4096 15 + ALLOT
CREATE _dc-scratch-raw 4096 15 + ALLOT
CREATE _dc-ws-raw SBOX-DECL-WORKSPACE-SIZE 15 + ALLOT
CREATE _dc-limits-raw SBOX-LIMITS-SIZE 15 + ALLOT
CREATE _dc-digest 32 ALLOT
CREATE _dc-ones 32 ALLOT
CREATE _dc-pad 64 ALLOT
_dc-ones 32 17 FILL

: _dc-decl  ( -- a ) _dc-decl-raw 15 + -16 AND ;
\ Mutated copies sit at an odd address: the format needs no alignment.
: _dc-copy  ( -- a ) _dc-copy-raw 15 + -16 AND 1+ ;
: _dc-scratch  ( -- a ) _dc-scratch-raw 15 + -16 AND ;
: _dc-ws  ( -- a ) _dc-ws-raw 15 + -16 AND ;
: _dc-limits  ( -- a ) _dc-limits-raw 15 + -16 AND ;

: _dc-assert  ( flag -- )
    1 _dc-checks +!
    0= IF
        1 _dc-fails +!
        ." DECL ASSERT case " _dc-case @ . ." check " _dc-checks @ . CR
    THEN ;

: _dc-is  ( status expected -- ) = _dc-assert ;

: _hexval  ( c -- n )
    DUP [CHAR] a >= IF [CHAR] a - 10 + ELSE [CHAR] 0 - THEN ;
: _bx-begin  ( -- ) _bx-top @ _bx-start ! ;
: _bx-add  ( c-addr u -- )
    2 / 0 ?DO
        DUP I 2 * + C@ _hexval 4 LSHIFT
        OVER I 2 * + 1+ C@ _hexval OR
        _bx-pool _bx-top @ + C!
        1 _bx-top +!
    LOOP DROP ;
: _bx-end  ( -- addr n )
    _bx-pool _bx-start @ + _bx-top @ _bx-start @ - ;

: _dc-blob!  ( addr n number -- ) 16 * _dc-blobs + TUCK 8 + ! ! ;
: _dc-blob  ( number -- addr n ) 16 * _dc-blobs + DUP @ SWAP 8 + @ ;

\ Writes hex bytes over the copy at OFFSET.
: _dc-patch  ( c-addr u offset -- )
    _dc-copy + -ROT
    2 / 0 ?DO
        DUP I 2 * + C@ _hexval 4 LSHIFT
        OVER I 2 * + 1+ C@ _hexval OR
        2 PICK I + C!
    LOOP 2DROP ;

: _dc-copy!  ( addr n -- ) _dc-copy SWAP MOVE ;

: _dc-validate-copy  ( n expected -- )
    >R _dc-copy SWAP _dc-ws SBOX-DECL-VALIDATE R> _dc-is ;

\ The limit fields keep the numbers the format stores.
: _dc-field-numbers  ( -- )
    SBOX-LIMIT-INSTRUCTION-BUDGET 0 = _dc-assert
    SBOX-LIMIT-VALUE-OP-BUDGET 1 = _dc-assert
    SBOX-LIMIT-COPY-BUDGET 2 = _dc-assert
    SBOX-LIMIT-WALL-MS 3 = _dc-assert
    SBOX-LIMIT-DEPTH 4 = _dc-assert
    SBOX-LIMIT-BLOB-BYTES 5 = _dc-assert
    SBOX-LIMIT-LIST-COUNT 6 = _dc-assert
    SBOX-LIMIT-MAP-COUNT 7 = _dc-assert
    SBOX-LIMIT-INPUT-NODES 8 = _dc-assert
    SBOX-LIMIT-INPUT-BYTES 9 = _dc-assert
    SBOX-LIMIT-OUTPUT-ARENA-NODES 10 = _dc-assert
    SBOX-LIMIT-OUTPUT-ARENA-BYTES 11 = _dc-assert
    SBOX-LIMIT-OUTPUT-RESULT-NODES 12 = _dc-assert
    SBOX-LIMIT-OUTPUT-RESULT-BYTES 13 = _dc-assert
    SBOX-LIMIT-DATA-STACK 14 = _dc-assert
    SBOX-LIMIT-CALL-FRAMES 15 = _dc-assert
    SBOX-LIMIT-LOOP-FRAMES 16 = _dc-assert
    SBOX-LIMIT-MEMORY-BYTES 17 = _dc-assert
    SBOX-LIMIT-COUNT 18 = _dc-assert
    SBOX-DECL-HEADER-SIZE 184 = _dc-assert
    SBOX-DECL-WORKSPACE-SIZE 7 AND 0= _dc-assert ;

: _dc-measure  ( entry-n limit-n schema-u u expected -- )
    >R >R SBOX-DECL-MEASURE R> R> ROT _dc-is = _dc-assert ;
"""

EPILOGUE = r"""
: _dc-finish  ( -- )
    0 _dc-case !
    DEPTH _dc-depth @ = _dc-assert
    _dc-fails @ IF
        ." DECL FAIL " _dc-fails @ . ." / " _dc-checks @ . CR
    ELSE
        ." DECL PASS " _dc-checks @ . CR
    THEN ;

_dc-finish
"""

# Blob numbers.
B_FULL, B_MINIMAL, B_FULL_DIGEST, B_MINIMAL_DIGEST = 0, 1, 2, 3
B_INTEGER, B_TEXT, B_PAIR = 4, 5, 6
B_INTEGER_DIGEST, B_TEXT_DIGEST, B_PAIR_DIGEST = 7, 8, 9
B_RID = 10  # 10.. the RIDs and digests of FULL and MINIMAL


def case(number: int, body: list[str]) -> list[str]:
    return ([f": _dc-case-{number}  ( -- )", f"    {number} _dc-case !"]
            + ["    " + line for line in body]
            + [";", f"_dc-case-{number}"])


class Blobs:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.numbers: dict[bytes, int] = {}
        self.next = B_RID

    def fixed(self, number: int, data: bytes) -> None:
        self.lines += blob(number, data)
        self.numbers.setdefault(data, number)

    def of(self, data: bytes) -> int:
        if data not in self.numbers:
            self.lines += blob(self.next, data)
            self.numbers[data] = self.next
            self.next += 1
        return self.numbers[data]


def writer_calls(d: Declaration, blobs: Blobs, target: str) -> list[str]:
    """The writer calls that build D at TARGET."""
    kind, prov_rid, prov_revision = d.provenance
    lines = [
        f"{blobs.of(d.module)} _dc-blob DROP {d.revision}",
        f"{blobs.of(d.artifact)} _dc-blob DROP"
        f" {blobs.of(d.profile)} _dc-blob DROP",
        f"{len(d.entries)} {len(d.limits)} {d.schema_bytes()}"
        f" {target} {d.size()} SBOX-DECL-START 0 _dc-is",
    ]
    if kind == PACKAGE:
        lines.append(f"SBOX-DECL-PROVENANCE-PACKAGE {blobs.of(prov_rid)}"
                     f" _dc-blob DROP {prov_revision}"
                     f" {target} SBOX-DECL-PROVENANCE! 0 _dc-is")
    for i, (field, value) in enumerate(d.limits):
        lines.append(f"{i} {field} {value} {target} SBOX-DECL-LIMIT! 0 _dc-is")
    for i, entry in enumerate(d.entries):
        lines.append(f"{i} {forth_string(entry.name)} {entry.signature}"
                     f" {target} SBOX-DECL-ENTRY! 0 _dc-is")
    for i, entry in enumerate(d.entries):
        lines.append(f"{i} {blobs.of(entry.input)} _dc-blob"
                     f" {blobs.of(entry.output)} _dc-blob"
                     f" _dc-ws {target} SBOX-DECL-SCHEMAS! 0 _dc-is")
    return lines


def reader_checks(d: Declaration, blobs: Blobs, target: str) -> list[str]:
    """Every reader returns what D holds."""
    kind, prov_rid, prov_revision = d.provenance
    lines = [
        f"{target} SBOX-DECL-MODULE@ {d.revision} = _dc-assert",
        f"32 {blobs.of(d.module)} _dc-blob COMPARE 0= _dc-assert",
        f"{target} SBOX-DECL-ARTIFACT-DIGEST@ 32"
        f" {blobs.of(d.artifact)} _dc-blob COMPARE 0= _dc-assert",
        f"{target} SBOX-DECL-PROFILE-DIGEST@ 32"
        f" {blobs.of(d.profile)} _dc-blob COMPARE 0= _dc-assert",
        f"{target} SBOX-DECL-PROVENANCE@ {prov_revision} = _dc-assert",
        f"32 {blobs.of(prov_rid)} _dc-blob COMPARE 0= _dc-assert",
        f"{kind} = _dc-assert",
        f"{target} SBOX-DECL-ENTRY-N@ {len(d.entries)} = _dc-assert",
        f"{target} SBOX-DECL-LIMIT-N@ {len(d.limits)} = _dc-assert",
    ]
    for i, entry in enumerate(d.entries):
        lines += [
            f"{i} {target} SBOX-DECL-ENTRY-NAME$"
            f" {forth_string(entry.name)} COMPARE 0= _dc-assert",
            f"{i} {target} SBOX-DECL-ENTRY-SIGNATURE@"
            f" {entry.signature} = _dc-assert",
            f"{i} {target} SBOX-DECL-ENTRY-INPUT$ 32"
            f" {blobs.of(schema_digest(entry.input))} _dc-blob"
            f" COMPARE 0= _dc-assert",
            f"{blobs.of(entry.input)} _dc-blob COMPARE 0= _dc-assert",
            f"{i} {target} SBOX-DECL-ENTRY-OUTPUT$ 32"
            f" {blobs.of(schema_digest(entry.output))} _dc-blob"
            f" COMPARE 0= _dc-assert",
            f"{blobs.of(entry.output)} _dc-blob COMPARE 0= _dc-assert",
            f"{forth_string(entry.name)} {target} SBOX-DECL-ENTRY-FIND"
            f" {i} = _dc-assert",
        ]
    names = [e.name for e in d.entries]
    misses = {b"a", b"b", b"zz", b"echo", b"echo.v20", b"len-of_",
              b"len-of_y", b"zzz", b"x" * 63, b"add" + b"0"}
    for miss in sorted(misses - set(names)):
        lines.append(f"{forth_string(miss)} {target} SBOX-DECL-ENTRY-FIND"
                     f" -1 = _dc-assert")
    lines.append(f"_dc-pad 0 {target} SBOX-DECL-ENTRY-FIND -1 = _dc-assert")
    lines.append(f"_dc-pad 64 {target} SBOX-DECL-ENTRY-FIND -1 = _dc-assert")
    for i, (field, value) in enumerate(d.limits):
        lines.append(f"{i} {target} SBOX-DECL-LIMIT@ {value} = _dc-assert"
                     f" {field} = _dc-assert")
    lines.append(f"{target} _dc-limits SBOX-DECL-LIMITS 0 _dc-is")
    capped = dict(d.limits)
    for field in range(LIMIT_COUNT):
        value = capped.get(field)
        lines.append(f"{field} _dc-limits SBOX-LIMIT@ 0 _dc-is"
                     f" {value or 'SBOX-LIMIT-UNBOUNDED'} = _dc-assert")
    return lines


# Writer misuse and span refusals, run against the scratch buffer.  The
# names refer to FULL's parts.
def misuse(blobs: Blobs) -> list[list[str]]:
    m = f"{blobs.of(FULL.module)} _dc-blob DROP"
    a = f"{blobs.of(FULL.artifact)} _dc-blob DROP"
    p = f"{blobs.of(FULL.profile)} _dc-blob DROP"
    size = MINIMAL.size()
    start = f"1 0 {MINIMAL.schema_bytes()} _dc-scratch"
    integer = f"{B_INTEGER} _dc-blob"
    zero = f"{blobs.of(bytes(32))} _dc-blob"
    two = Declaration(FULL.module, 1, FULL.artifact, FULL.profile,
                      (Entry(b"a", 1, INTEGER, INTEGER),
                       Entry(b"b", 1, INTEGER, INTEGER)), ((0, 5),))
    start2 = f"2 1 {two.schema_bytes()} _dc-scratch {two.size()}"
    return [
        # Measuring.
        [f"1 0 {len(INTEGER) * 2} {HEADER + ENTRY_SIZE + 2 * len(INTEGER)}"
         " 0 _dc-measure",
         f"2 3 100 {HEADER + 3 * LIMIT_SIZE + 2 * ENTRY_SIZE + 100}"
         " 0 _dc-measure",
         f"{ENTRY_MAX} {LIMIT_COUNT} 0"
         f" {HEADER + LIMIT_COUNT * LIMIT_SIZE + ENTRY_MAX * ENTRY_SIZE}"
         " 0 _dc-measure",
         f"0 0 10 0 {INVALID} _dc-measure",
         f"-1 0 10 0 {INVALID} _dc-measure",
         f"{ENTRY_MAX + 1} 0 10 0 {INVALID} _dc-measure",
         f"1 {LIMIT_COUNT + 1} 10 0 {INVALID} _dc-measure",
         f"1 -1 10 0 {INVALID} _dc-measure",
         f"1 0 -1 0 {INVALID} _dc-measure",
         f"1 0 {BYTES_MAX + 1} 0 {CAPACITY} _dc-measure",
         f"1 0 {BYTES_MAX} 0 {CAPACITY} _dc-measure",
         f"1 0 {BYTES_MAX - HEADER - ENTRY_SIZE}"
         f" {BYTES_MAX} 0 _dc-measure"],
        # Starting.
        [f"{m} 1 {a} {p} {start} {size - 1} SBOX-DECL-START {CAPACITY} _dc-is",
         f"{m} 1 {a} {p} {start} {size + 1} SBOX-DECL-START {INVALID} _dc-is",
         f"{m} 1 {a} {p} 0 0 {MINIMAL.schema_bytes()} _dc-scratch {size}"
         f" SBOX-DECL-START {INVALID} _dc-is",
         f"{m} 1 {a} {p} 1 0 {MINIMAL.schema_bytes()} 0 {size}"
         f" SBOX-DECL-START {INVALID} _dc-is",
         f"_dc-pad 32 0 FILL _dc-pad 1 {a} {p} {start} {size}"
         f" SBOX-DECL-START {INVALID} _dc-is",
         f"0 1 {a} {p} {start} {size} SBOX-DECL-START {INVALID} _dc-is",
         f"{m} 0 {a} {p} {start} {size} SBOX-DECL-START {INVALID} _dc-is",
         f"{m} -1 {a} {p} {start} {size} SBOX-DECL-START {INVALID} _dc-is",
         f"_dc-pad 32 0 FILL {m} 1 _dc-pad {p} {start} {size}"
         f" SBOX-DECL-START {INVALID} _dc-is",
         f"_dc-pad 32 0 FILL {m} 1 {a} _dc-pad {start} {size}"
         f" SBOX-DECL-START {INVALID} _dc-is",
         "_dc-ones _dc-scratch 40 + 32 MOVE",
         f"_dc-scratch 40 + 1 {a} {p} {start} {size}"
         f" SBOX-DECL-START {ALIAS} _dc-is",
         f"{m} 1 _dc-scratch 40 + {p} {start} {size}"
         f" SBOX-DECL-START {ALIAS} _dc-is",
         f"{m} 1 {a} _dc-scratch 40 + {start} {size}"
         f" SBOX-DECL-START {ALIAS} _dc-is"],
        # Provenance, limits and entries.
        [f"{m} 1 {a} {p} {start2} SBOX-DECL-START 0 _dc-is",
         f"2 {m} 1 _dc-scratch SBOX-DECL-PROVENANCE! {INVALID} _dc-is",
         f"SBOX-DECL-PROVENANCE-NONE {m} 0 _dc-scratch"
         f" SBOX-DECL-PROVENANCE! {INVALID} _dc-is",
         "SBOX-DECL-PROVENANCE-NONE 0 1 _dc-scratch"
         f" SBOX-DECL-PROVENANCE! {INVALID} _dc-is",
         "SBOX-DECL-PROVENANCE-PACKAGE 0 1 _dc-scratch"
         f" SBOX-DECL-PROVENANCE! {INVALID} _dc-is",
         "_dc-pad 32 0 FILL SBOX-DECL-PROVENANCE-PACKAGE _dc-pad 1 _dc-scratch"
         f" SBOX-DECL-PROVENANCE! {INVALID} _dc-is",
         f"SBOX-DECL-PROVENANCE-PACKAGE {m} 0 _dc-scratch"
         f" SBOX-DECL-PROVENANCE! {INVALID} _dc-is",
         f"SBOX-DECL-PROVENANCE-PACKAGE {m} 9 _dc-scratch"
         " SBOX-DECL-PROVENANCE! 0 _dc-is",
         "_dc-scratch SBOX-DECL-PROVENANCE@ 9 = _dc-assert"
         f" 32 {m} 32 COMPARE 0= _dc-assert 1 = _dc-assert",
         "SBOX-DECL-PROVENANCE-NONE 0 0 _dc-scratch"
         " SBOX-DECL-PROVENANCE! 0 _dc-is",
         "_dc-scratch SBOX-DECL-PROVENANCE@ 0= _dc-assert"
         f" 32 {zero} COMPARE 0= _dc-assert 0= _dc-assert",
         f"1 0 5 _dc-scratch SBOX-DECL-LIMIT! {STATE} _dc-is",
         f"-1 0 5 _dc-scratch SBOX-DECL-LIMIT! {STATE} _dc-is",
         f"0 0 0 _dc-scratch SBOX-DECL-LIMIT! {INVALID} _dc-is",
         f"0 0 SBOX-LIMIT-UNBOUNDED _dc-scratch SBOX-DECL-LIMIT!"
         f" {INVALID} _dc-is",
         f"0 {LIMIT_COUNT} 5 _dc-scratch SBOX-DECL-LIMIT! {INVALID} _dc-is",
         f"0 -1 5 _dc-scratch SBOX-DECL-LIMIT! {INVALID} _dc-is",
         f"2 S\" c\" 1 _dc-scratch SBOX-DECL-ENTRY! {STATE} _dc-is",
         f"-1 S\" c\" 1 _dc-scratch SBOX-DECL-ENTRY! {STATE} _dc-is",
         f"0 S\" a\" 0 _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 S\" a\" {2 ** 32} _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 _dc-pad 0 1 _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 0 3 1 _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 S\" Abc\" 1 _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 S\" 1ab\" 1 _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 S\" a b\" 1 _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 S\" a/b\" 1 _dc-scratch SBOX-DECL-ENTRY! {INVALID} _dc-is",
         f"0 {forth_string(b'a' * 64)} 1 _dc-scratch SBOX-DECL-ENTRY!"
         f" {INVALID} _dc-is",
         f"0 {forth_string(b'a' * 63)} 1 _dc-scratch SBOX-DECL-ENTRY!"
         " 0 _dc-is"],
        # Schemas.
        [f"{m} 1 {a} {p} {start2} SBOX-DECL-START 0 _dc-is",
         f"1 {integer} {integer} _dc-ws _dc-scratch SBOX-DECL-SCHEMAS!"
         f" {STATE} _dc-is",
         f"2 {integer} {integer} _dc-ws _dc-scratch SBOX-DECL-SCHEMAS!"
         f" {STATE} _dc-is",
         f"0 {integer} DROP 0 {integer} _dc-ws _dc-scratch"
         f" SBOX-DECL-SCHEMAS! {INVALID} _dc-is",
         f"0 {integer} {integer} DROP 0 _dc-ws _dc-scratch"
         f" SBOX-DECL-SCHEMAS! {INVALID} _dc-is",
         f"0 0 12 {integer} _dc-ws _dc-scratch SBOX-DECL-SCHEMAS!"
         f" {INVALID} _dc-is",
         f"0 {integer} {integer} _dc-ws 1+ _dc-scratch SBOX-DECL-SCHEMAS!"
         f" {INVALID} _dc-is",
         f"0 {integer} {integer} _dc-scratch _dc-scratch SBOX-DECL-SCHEMAS!"
         f" {ALIAS} _dc-is",
         f"0 _dc-scratch 12 {integer} _dc-ws _dc-scratch SBOX-DECL-SCHEMAS!"
         f" {ALIAS} _dc-is",
         f"0 {integer} _dc-ws 12 _dc-ws _dc-scratch SBOX-DECL-SCHEMAS!"
         f" {ALIAS} _dc-is",
         f"0 {integer} {integer} DROP {two.schema_bytes()} _dc-ws _dc-scratch"
         f" SBOX-DECL-SCHEMAS! {CAPACITY} _dc-is",
         f"0 {integer} DROP {two.schema_bytes() + 1} {integer} _dc-ws"
         f" _dc-scratch SBOX-DECL-SCHEMAS! {CAPACITY} _dc-is",
         # The declaration is not complete until every part is written.
         f"_dc-scratch {two.size()} _dc-ws SBOX-DECL-VALIDATE {INVALID} _dc-is",
         "0 0 5 _dc-scratch SBOX-DECL-LIMIT! 0 _dc-is",
         "0 S\" a\" 1 _dc-scratch SBOX-DECL-ENTRY! 0 _dc-is",
         "1 S\" b\" 1 _dc-scratch SBOX-DECL-ENTRY! 0 _dc-is",
         f"0 {integer} {integer} _dc-ws _dc-scratch SBOX-DECL-SCHEMAS!"
         " 0 _dc-is",
         f"_dc-scratch {two.size()} _dc-ws SBOX-DECL-VALIDATE {INVALID} _dc-is",
         f"1 {integer} {integer} _dc-ws _dc-scratch SBOX-DECL-SCHEMAS!"
         " 0 _dc-is",
         f"_dc-scratch {two.size()} _dc-ws SBOX-DECL-VALIDATE 0 _dc-is",
         f"_dc-scratch {two.size()} {blobs.of(build(two))} _dc-blob"
         " COMPARE 0= _dc-assert",
         # Validation spans.
         f"_dc-scratch {two.size()} _dc-ws 1+ SBOX-DECL-VALIDATE"
         f" {INVALID} _dc-is",
         f"_dc-scratch {two.size()} 0 SBOX-DECL-VALIDATE {INVALID} _dc-is",
         f"0 {two.size()} _dc-ws SBOX-DECL-VALIDATE {INVALID} _dc-is",
         f"_dc-scratch {two.size()} _dc-scratch SBOX-DECL-VALIDATE"
         f" {ALIAS} _dc-is",
         f"_dc-scratch {two.size()} _dc-scratch 8 + _dc-ws SBOX-DECL-DIGEST"
         f" {ALIAS} _dc-is",
         f"_dc-scratch {two.size()} _dc-ws 8 + _dc-ws SBOX-DECL-DIGEST"
         f" {ALIAS} _dc-is",
         f"_dc-scratch {two.size()} _dc-ws SBOX-DECL-VALIDATE 0 _dc-is",
         f"_dc-scratch {two.size()} _dc-digest _dc-ws SBOX-DECL-DIGEST 0 _dc-is",
         f"_dc-digest 32 {blobs.of(declaration_digest(build(two)))} _dc-blob"
         " COMPARE 0= _dc-assert",
         # A refused declaration leaves the digest alone.
         "_dc-digest 32 0 FILL",
         f"_dc-scratch {two.size() - 1} _dc-digest _dc-ws SBOX-DECL-DIGEST"
         f" {INVALID} _dc-is",
         f"_dc-digest 32 {zero} COMPARE 0= _dc-assert"],
    ]


def fixture() -> bytes:
    blobs = Blobs()
    full, minimal = build(FULL), build(MINIMAL)
    blobs.fixed(B_FULL, full)
    blobs.fixed(B_MINIMAL, minimal)
    blobs.fixed(B_FULL_DIGEST, declaration_digest(full))
    blobs.fixed(B_MINIMAL_DIGEST, declaration_digest(minimal))
    blobs.fixed(B_INTEGER, INTEGER)
    blobs.fixed(B_TEXT, TEXT)
    blobs.fixed(B_PAIR, PAIR)
    blobs.fixed(B_INTEGER_DIGEST, schema_digest(INTEGER))
    blobs.fixed(B_TEXT_DIGEST, schema_digest(TEXT))
    blobs.fixed(B_PAIR_DIGEST, schema_digest(PAIR))

    cases: list[list[str]] = [["_dc-field-numbers"]]
    for d, number, digest_number in ((FULL, B_FULL, B_FULL_DIGEST),
                                     (MINIMAL, B_MINIMAL, B_MINIMAL_DIGEST)):
        body = writer_calls(d, blobs, "_dc-decl")
        body += [
            f"_dc-decl {d.size()} {number} _dc-blob COMPARE 0= _dc-assert",
            f"_dc-decl {d.size()} _dc-ws SBOX-DECL-VALIDATE 0 _dc-is",
            f"_dc-decl {d.size()} _dc-digest _dc-ws SBOX-DECL-DIGEST 0 _dc-is",
            f"_dc-digest 32 {digest_number} _dc-blob COMPARE 0= _dc-assert",
        ]
        body += reader_checks(d, blobs, "_dc-decl")
        # The same bytes validate at an odd address.
        body += [f"{number} _dc-blob _dc-copy!",
                 f"{d.size()} 0 _dc-validate-copy"]
        cases.append(body)
    cases += misuse(blobs)

    for name, data, expected in mutations():
        if len(data) == len(full):
            body = [f"\\ {name}", f"{B_FULL} _dc-blob _dc-copy!"]
            runs = []
            offset = 0
            while offset < len(data):
                if data[offset] != full[offset]:
                    end = offset
                    while end < len(data) and data[end] != full[end]:
                        end += 1
                    runs.append((offset, data[offset:end]))
                    offset = end
                else:
                    offset += 1
            assert runs, name
            for at, run in runs:
                for i in range(0, len(run), 48):
                    body.append(f'S" {run[i:i + 48].hex()}" {at + i} _dc-patch')
        else:
            body = [f"\\ {name}", f"{blobs.of(data)} _dc-blob _dc-copy!"]
        body.append(f"{len(data)} {expected} _dc-validate-copy")
        cases.append(body)
    for name, length in TRUNCATED:
        cases.append([f"\\ {name}", f"{B_FULL} _dc-blob _dc-copy!",
                      f"{length} {INVALID} _dc-validate-copy"])

    # Every blob the cases name is loaded before the cases run.
    lines = [PRELUDE] + blobs.lines
    lines.append("0 _dc-fails ! 0 _dc-checks ! DEPTH _dc-depth !")
    for number, body in enumerate(cases, start=1):
        lines += case(number, body)
    lines.append(EPILOGUE)
    return ("\n".join(lines) + "\n").encode()


def test_the_reference_matches_its_own_rules() -> None:
    assert validate(build(FULL)) == OK
    assert validate(build(MINIMAL)) == OK
    assert len(LIMIT_FIELDS) == 18
    for name, data, expected in mutations():
        assert validate(data) == expected, name
    full = build(FULL)
    for name, length in TRUNCATED:
        assert validate(full[:length]) == INVALID, name


PROFILE_NAME = "sandbox-declaration-contracts"


def test_declarations_match_the_reference(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("runtime/sandbox-declaration.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - sandbox module declarations
ENTER-USERLAND
." [akashic] loading sandbox declarations" CR TX-FLUSH
REQUIRE runtime/sandbox-declaration.f
REQUIRE local_testing/sbox-decl-test.f
""",
        ready_markers=("DECL PASS",),
        stable_markers=("DECL PASS",),
        failure_markers=(
            "DECL FAIL",
            "DECL ASSERT",
            "? (not found)",
            "Branch offset overflow",
            "dictionary full",
            "exception",
        ),
        linked=True,
        include_large_sample=False,
        initial_files=(("local_testing/sbox-decl-test.f", fixture()),),
    )
    image = build_image(PROFILE_NAME, tmp_path / "declaration.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=600_000_000,
        timeout=180.0,
    )
