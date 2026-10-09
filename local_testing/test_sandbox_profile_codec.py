#!/usr/bin/env python3
"""The canonical profile descriptor loader against the published fixture.

The embedded production descriptor must equal docs/sandbox/fixtures/
pure-compute.profile byte for byte and load to its golden digests.  Every
opcode record must equal the machine's own metadata.  Each descriptor
variant below is built in Forth by splicing the embedded bytes, and must be
refused with the expected status at the expected record, or load with the
digest Python computes for it.
"""

from __future__ import annotations

import difflib
import hashlib
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
REPO_ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


FIXTURE = REPO_ROOT / "docs" / "sandbox" / "fixtures" / "pure-compute.profile"
CODEC = REPO_ROOT / "akashic" / "sandbox" / "profile-codec.f"
PURE = FIXTURE.read_bytes()
LINES = PURE.decode("ascii").split("\n")[:-1]

PROFILE_RAW = "a40084a0350f5f92d42473f46c1836dfaef8550163d9b67d1d3126addb3a8a88"
PROFILE_DIGEST = "6a53f8973d7f99694b242a315234f66e28c04da6e15e61e47f490025f7473b22"
PROFILE_BYTES = 6899

OK, DESCRIPTOR, UNSUPPORTED = "SBOX-PROFILE-S-OK", "SBOX-PROFILE-S-DESCRIPTOR", \
    "SBOX-PROFILE-S-UNSUPPORTED"



def digest(domain: str | None, data: bytes) -> str:
    prefix = b"" if domain is None else domain.encode("ascii") + b"\x00"
    return hashlib.sha3_256(prefix + data).hexdigest()


def make(lines: list[str], final_lf: bool = True) -> bytes:
    return ("\n".join(lines) + ("\n" if final_lf else "")).encode("latin-1")


def at(lines: list[str], index: int) -> int:
    """Byte offset of record INDEX."""
    return sum(len(line) + 1 for line in lines[:index])


def find(lines: list[str], text: str) -> int:
    """Index of the first record equal to TEXT, or starting with TEXT + ' '."""
    for index, line in enumerate(lines):
        if line == text or line.startswith(text + " "):
            return index
    raise KeyError(text)


GROUPS = ("rule", "value", "signature", "import", "opcode")


def fix_end(lines: list[str]) -> list[str]:
    counts = [sum(1 for line in lines if line.split(" ")[0] == group)
              for group in GROUPS]
    return [line for line in lines if not line.startswith("end ")] + [
        "end " + " ".join(str(count) for count in counts)
    ]


def replace(lines: list[str], old: str, new: str) -> list[str]:
    index = find(lines, old)
    return lines[:index] + [new] + lines[index + 1:]


def insert_after(lines: list[str], anchor: str, *new: str) -> list[str]:
    index = find(lines, anchor) + 1
    return lines[:index] + list(new) + lines[index:]


def remove(lines: list[str], *texts: str) -> list[str]:
    out = list(lines)
    for text in texts:
        del out[find(out, text)]
    return out


def swap(lines: list[str], first: str) -> list[str]:
    index = find(lines, first)
    out = list(lines)
    out[index], out[index + 1] = out[index + 1], out[index]
    return out


# ---------------------------------------------------------------------
# Variants: (name, bytes, status, failing byte offset or -1)
# ---------------------------------------------------------------------

def refused(name: str, lines: list[str], status: str, index: int,
            final_lf: bool = True) -> tuple[str, bytes, str, int]:
    return name, make(lines, final_lf), status, at(lines, index)


def variants() -> list[tuple[str, bytes, str, int]]:
    L = LINES
    out: list[tuple[str, bytes, str, int]] = []

    def bad(name: str, lines: list[str], index: int, **kw) -> None:
        out.append(refused(name, lines, DESCRIPTOR, index, **kw))

    def unsupported(name: str, lines: list[str], index: int) -> None:
        out.append(refused(name, lines, UNSUPPORTED, index))

    # Bytes and lines.
    bad("tab", replace(L, "codec", "codec\t1"), 1)
    bad("carriage return", replace(L, "profile",
                                   "profile org.akashic.sandbox.pure-compute\r"), 2)
    bad("delete byte", replace(L, "source-language",
                               "source-language org.akashic.sandbox.sourc\x7f"), 5)
    bad("high byte", replace(L, "semantics", "semantics \xc3"), 3)
    bad("no final line feed", L, len(L) - 1, final_lf=False)
    bad("blank line", insert_after(L, "recursion", ""), 11)
    bad("leading space", replace(L, "codec", " codec 1"), 1)
    bad("trailing space", replace(L, "codec", "codec 1 "), 1)
    bad("doubled space", replace(L, "codec", "codec  1"), 1)
    bad("leading zero", replace(L, "codec", "codec 01"), 1)
    bad("plus sign", replace(L, "false", "false +0"), 8)
    bad("minus zero", replace(L, "false", "false -0"), 8)
    bad("redundant zero", replace(L, "true", "true -01"), 9)
    bad("u16 overflow", replace(L, "codec", "codec 65536"), 1)
    nop = find(L, "opcode 0")
    bad("u64 overflow", replace(L, "opcode 0",
                                "opcode 0 NOP 0 0 0 0 0 18446744073709551616 0 0"), nop)
    bad("identifier start", replace(L, "profile", "profile 9org"), 2)
    bad("identifier length", replace(L, "profile", "profile " + "a" * 128), 2)
    bad("opcode name", replace(L, "opcode 0", "opcode 0 nop 0 0 0 0 0 1 0 0"), nop)
    bad("arity", replace(L, "codec", "codec 1 1"), 1)
    bad("unknown kind", insert_after(L, "semantics", "comment x"), 4)
    bad("repeated fixed record", insert_after(L, "codec", "codec 1"), 2)
    bad("fixed records out of order", swap(L, "codec"), 1)
    bad("no magic", L[1:], 0)
    bad("recursion range", replace(L, "recursion", "recursion 2"), 10)
    # A profile holds no resource limit; the host's policy does.
    bad("limit record", insert_after(L, "opcode 118", "admission-limit entries 32"),
        find(L, "opcode 118") + 1)

    # Group order and keys.
    first_rule = find(L, "rule")
    bad("rules out of order", swap(L, "rule arithmetic.div-trap-min-neg1"),
        first_rule + 2)
    bad("repeated rule",
        insert_after(L, "rule boolean.false-zero-true-minus-one",
                     "rule boolean.false-zero-true-minus-one"),
        find(L, "rule boolean.false-zero-true-minus-one") + 1)
    bad("value tags out of order", swap(L, "value 1"), find(L, "value 1") + 1)
    bad("opcodes out of order", swap(L, "opcode 32"), find(L, "opcode 32") + 1)
    bad("operand kind", replace(L, "opcode 0", "opcode 0 NOP 9 0 0 0 0 1 0 0"), nop)
    ret = find(L, "opcode 6")
    bad("effect with cells", replace(L, "opcode 6",
                                     "opcode 6 RETURN 0 2 1 0 0 1 0 0"), ret)
    call = find(L, "opcode 5")
    bad("divisor", replace(L, "opcode 5", "opcode 5 CALL 3 1 0 0 1 2 4 0"), call)
    bad("fixed cost divisor", replace(L, "opcode 0",
                                      "opcode 0 NOP 0 0 0 0 0 1 8 0"), nop)
    bad("zero cost", replace(L, "opcode 0", "opcode 0 NOP 0 0 0 0 0 0 0 0"), nop)
    import_call = "opcode 80 IMPORT.CALL 8 3 0 0 6 1 0 4"
    lone = fix_end(insert_after(L, "opcode 70", import_call))
    bad("IMPORT.CALL without imports", lone, find(lone, "opcode 0"))
    odd = fix_end(insert_after(L, "opcode 70",
                               "opcode 80 IMPORT.CALL 8 3 0 0 6 2 0 4"))
    bad("IMPORT.CALL form", odd, find(odd, "opcode 80"))
    clock = "import 1 org.example.clock 1 0 5"
    no_call = fix_end(insert_after(L, "signature", clock))
    bad("import without IMPORT.CALL", no_call, find(no_call, "opcode 0"))
    unlisted = fix_end(insert_after(L, "signature",
                                    "import 1 org.example.clock 2 0 5"))
    bad("import signature unlisted", unlisted, find(unlisted, "import"))
    rule4 = fix_end(insert_after(L, "signature", "import 1 org.example.clock 1 4 5"))
    bad("import cost rule", rule4, find(rule4, "import"))
    sig = find(L, "signature")
    sig_text = "signature 1 org.akashic.sandbox.signature.value-to-value"
    bad("signature kind count", replace(L, "signature", sig_text + " 2 VALUE 1 VALUE"),
        sig)
    bad("signature opaque zero",
        replace(L, "signature", sig_text + " 1 OPAQUE.0 1 VALUE"), sig)
    bad("signature opaque leading zero",
        replace(L, "signature", sig_text + " 1 OPAQUE.01 1 VALUE"), sig)
    bad("signature dash", replace(L, "signature", sig_text + " 1 - 1 VALUE"), sig)
    bad("signature empty atom",
        replace(L, "signature", sig_text + " 2 VALUE, 1 VALUE"), sig)

    # Outcomes and the end record.
    bad("detail zero", insert_after(L, "result 9", "request-detail 0 OK"),
        find(L, "result 9") + 1)
    bad("details out of order", swap(L, "trap-detail 1"),
        find(L, "trap-detail 1") + 1)
    bad("end counts", replace(L, "end", "end 17 7 1 0 81"), len(L) - 1)
    bad("end arity", replace(L, "end", "end 17 7 1 0 80 0"), len(L) - 1)
    bad("record after end", L + [L[-1]], len(L))
    bad("no end record", L[:-1], len(L) - 2)
    many = insert_after(L, "rule value.canonical-tree-codec",
                        *[f"rule value.z{n:04d}" for n in range(MANY_RULES)])
    bad("too many records", many, 1024)
    no_values = fix_end([line for line in L if not line.startswith("value ")])
    unsupported("no values", no_values, find(no_values, "signature"))

    # Canonical, but not what this runtime implements.
    unsupported("codec", replace(L, "codec", "codec 2"), 1)
    unsupported("semantics", replace(L, "semantics",
                                     "semantics org.example.semantics"), 3)
    unsupported("artifact format", replace(L, "artifact-format",
                                           "artifact-format 2"), 4)
    unsupported("source language", replace(L, "source-language",
                                           "source-language org.example.forth"), 5)
    unsupported("value codec", replace(L, "value-codec",
                                       "value-codec org.example.cbor"), 6)
    unsupported("cell bits", replace(L, "cell-bits", "cell-bits 32"), 7)
    unsupported("false", replace(L, "false", "false 1"), 8)
    unsupported("true", replace(L, "true", "true 1"), 9)
    unsupported("no recursion", replace(L, "recursion", "recursion 0"), 10)
    unsupported("unknown rule", replace(L, "rule arithmetic.div-trap-zero",
                                        "rule arithmetic.div-trap-zeroes"), first_rule)
    unsupported("missing rule", fix_end(remove(L, "rule import.rw-staged-atomic")),
                first_rule)
    seven = fix_end(insert_after(L, "value 6", "value 7 FLOAT"))
    unsupported("extra value tag", seven, find(seven, "value 0"))
    unsupported("outcome name", replace(L, "trap-detail 1",
                                        "trap-detail 1 BAD_OPCODES"),
                find(L, "result 0"))
    unsupported("opcode cost", replace(L, "opcode 0",
                                       "opcode 0 NOP 0 0 0 0 0 2 0 0"), nop)
    unknown = fix_end(insert_after(L, "opcode 14",
                                   "opcode 15 LOOP.UNKNOWN 0 0 0 1 0 1 0 0"))
    unsupported("unknown opcode", unknown, find(unknown, "opcode 15"))
    more = fix_end(insert_after(L, "signature", "signature 2 org.example.sig 0 - 1 I64"))
    unsupported("unknown signature", more, find(more, "signature 2"))
    imports = fix_end(insert_after(insert_after(L, "opcode 70", import_call),
                                   "signature", clock))
    unsupported("imports", imports, find(imports, "import"))
    unsupported("lowest offset first",
                replace(replace(L, "opcode 0", "opcode 0 NOP 0 0 0 0 0 2 0 0"),
                        "rule arithmetic.div-trap-zero",
                        "rule arithmetic.div-trap-zeroes"), first_rule)
    late = find(L, "opcode 1")
    bad("malformed beats unsupported",
        replace(replace(L, "codec", "codec 2"), "opcode 1",
                L[late] + " "), late)
    return out


# Descriptors that load: (name, lines, checks in Forth).
def loadable() -> list[tuple[str, list[str], str]]:
    L = LINES
    typed = [line for line in L
             if line.startswith("opcode ")
             and 96 <= int(line.split(" ")[1]) <= 118]
    no_typed = fix_end([line for line in L if line not in typed])
    loops = {f"opcode {code}" for code in (11, 12, 13, 14)}
    no_loops = fix_end(
        [line for line in L if " ".join(line.split(" ")[:2]) not in loops])
    long_name = replace(L, "profile", "profile " + "a" * 127)
    no_signature = fix_end(remove(L, "signature"))
    qualification = replace(
        replace(L, "profile", "profile org.akashic.sandbox.scalar-qualification"),
        "semantics",
        "semantics org.akashic.sandbox.semantics.scalar-qualification")
    return [
        ("no typed opcodes", no_typed,
         "0x60 _pc-on? 0= _pc-assert 0x76 _pc-on? 0= _pc-assert "
         "0x20 _pc-on? _pc-assert"),
        ("no loops", no_loops,
         "0x0B _pc-on? 0= _pc-assert 0x0E _pc-on? 0= _pc-assert"),
        ("longest identifier", long_name,
         "_pc-prof SBOX-PROFILE-IDENTIFIER$ NIP 127 = _pc-assert"),
        ("no signature", no_signature,
         "1 _pc-prof SBOX-PROFILE-SIGNATURE-ENABLED? 0= SWAP 0= AND _pc-assert"),
        # Scalar qualification enables signature zero as well.
        ("scalar qualification", qualification,
         "_pc-prof SBOX-PROFILE-SEMANTICS@ 0= _pc-assert "
         "SBOX-PROFILE-SEMANTICS-SCALAR-QUALIFICATION = _pc-assert "
         "0 _pc-prof SBOX-PROFILE-SIGNATURE-ENABLED? 0= AND _pc-assert "
         "1 _pc-prof SBOX-PROFILE-SIGNATURE-ENABLED? 0= AND _pc-assert"),
    ]


# ---------------------------------------------------------------------
# Forth generation
# ---------------------------------------------------------------------

SAFE = re.compile(rb'[\x20\x21\x23-\x7e]{1,96}')


def records(data: bytes) -> list[bytes]:
    return re.findall(rb"[^\n]*\n|[^\n]+$", data)


MANY_RULES = 900


def splice_lines(target: bytes) -> list[str]:
    """Forth that turns the embedded descriptor into TARGET."""
    base_records, target_records = records(PURE), records(target)
    inserted = [r for r in target_records if r.startswith(b"rule value.z")]
    if len(inserted) == MANY_RULES:
        offset = PURE.index(b"value 0 ")
        return [f"    {offset} {MANY_RULES} _pc-many-rules"]
    matcher = difflib.SequenceMatcher(None, base_records, target_records,
                                      autojunk=False)
    hunks = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        offset = sum(len(r) for r in base_records[:i1])
        delete = sum(len(r) for r in base_records[i1:i2])
        hunks.append((offset, delete, b"".join(target_records[j1:j2])))
    out = []
    for offset, delete, insert in reversed(hunks):
        out.append(f"    {offset} {delete} _pc-cut")
        position = offset
        while insert:
            match = SAFE.match(insert)
            if match:
                text = match.group(0)
                out.append(f'    {position} S" {text.decode("ascii")}" _pc-put')
            else:
                text = insert[:1]
                out.append(f"    {position} {text[0]} _pc-put-byte")
            position += len(text)
            insert = insert[len(text):]
    return out


def hex_lines(data: bytes) -> list[str]:
    text = data.hex()
    return ["    _bx-begin"] + [
        f'    S" {text[i:i + 96]}" _bx-add' for i in range(0, len(text), 96)
    ] + ["    _bx-end"]


PRELUDE = r"""\ Generated: canonical profile descriptor loader.
PROVIDED sbox-profile-codec-tests

VARIABLE _pc-fails
VARIABLE _pc-checks
VARIABLE _pc-case
VARIABLE _pc-depth
VARIABLE _pc-buf
VARIABLE _pc-u
VARIABLE _pc-st
VARIABLE _pc-off
VARIABLE _pc-pa
VARIABLE _pc-pu

CREATE _bx-pool 256 ALLOT
VARIABLE _bx-top
VARIABLE _bx-start
CREATE _pc-prof-raw SBOX-PROFILE-SIZE 2 * 15 + ALLOT
CREATE _pc-ws-raw SBOX-PROFILE-LOAD-WORKSPACE-SIZE 15 + ALLOT
CREATE _pc-byte 1 ALLOT
CREATE _pc-rule 32 ALLOT

: _pc-prof  ( -- a ) _pc-prof-raw 7 + -8 AND ;
: _pc-copy  ( -- a ) _pc-prof SBOX-PROFILE-SIZE + ;
: _pc-ws  ( -- a ) _pc-ws-raw 7 + -8 AND ;

: _pc-assert  ( flag -- )
    1 _pc-checks +!
    0= IF
        1 _pc-fails +!
        ." SPC ASSERT case " _pc-case @ . ." check " _pc-checks @ . CR
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

\ The buffer starts as the embedded descriptor and is edited in place.
: _pc-reset  ( -- )
    SBOX-PROFILE-PURE-DESCRIPTOR DUP _pc-u ! _pc-buf @ SWAP MOVE ;

\ Removes DELETE bytes at OFFSET.
: _pc-cut  ( offset delete -- )
    >R
    _pc-buf @ OVER + R@ +
    _pc-buf @ ROT +
    _pc-u @ 2 PICK _pc-buf @ - -
    MOVE
    R> NEGATE _pc-u +! ;

\ Opens room at OFFSET and copies LENGTH bytes from ADDRESS into it.
: _pc-put  ( offset address length -- )
    _pc-pu ! _pc-pa !
    _pc-buf @ OVER +
    DUP _pc-pu @ +
    _pc-u @ 3 PICK -
    MOVE
    _pc-pa @ SWAP _pc-buf @ + _pc-pu @ MOVE
    _pc-pu @ _pc-u +! ;

: _pc-put-byte  ( offset byte -- )
    _pc-byte C! _pc-byte 1 _pc-put ;

\ Inserts COUNT records "rule value.zNNNN" at OFFSET.
: _pc-many-rules  ( offset count -- )
    0 ?DO
        S" rule value.z" _pc-rule SWAP MOVE
        I 1000 / [CHAR] 0 + _pc-rule 12 + C!
        I 100 / 10 MOD [CHAR] 0 + _pc-rule 13 + C!
        I 10 / 10 MOD [CHAR] 0 + _pc-rule 14 + C!
        I 10 MOD [CHAR] 0 + _pc-rule 15 + C!
        10 _pc-rule 16 + C!
        DUP _pc-rule 17 _pc-put
        17 +
    LOOP DROP ;

\ The workspace keeps only its status and the failing offset.
: _pc-scratch-clear?  ( -- flag )
    SBOX-PROFILE-LOAD-WORKSPACE-SIZE 16 DO
        _pc-ws I + @ IF 0 UNLOOP EXIT THEN
    8 +LOOP -1 ;

: _pc-load  ( -- status )
    _pc-buf @ _pc-u @ _pc-prof _pc-ws SBOX-PROFILE-LOAD ;

\ Loads the buffer and expects STATUS at byte OFFSET (-1 when it loads).
: _pc-expect  ( status offset -- )
    _pc-off ! _pc-st !
    _pc-load
    DUP _pc-st @ <> IF
        ." SPC case " _pc-case @ . ." status " DUP . CR
    THEN
    _pc-st @ = _pc-assert
    _pc-ws SBOX-PROFILE-LOAD-ERROR@ SBOX-PROFILE-S-OK = _pc-assert
    DUP _pc-off @ <> IF
        ." SPC case " _pc-case @ . ." offset " DUP . CR
    THEN
    _pc-off @ = _pc-assert
    _pc-st @ = _pc-assert
    _pc-scratch-clear? _pc-assert
    _pc-prof SBOX-PROFILE-VALID? _pc-st @ SBOX-PROFILE-S-OK = = _pc-assert ;

: _pc-on?  ( opcode -- flag )
    _pc-prof SBOX-PROFILE-OPCODE-ENABLED?
    SBOX-PROFILE-S-OK = _pc-assert ;

: _pc-digest=  ( expected expected-u -- )
    32 = _pc-assert _pc-prof SBOX-PROFILE-DIGEST= _pc-assert ;

\ An opcode record's machine fields arrive last field first and must
\ equal SBOX-ABI-METADATA field by field.
: _pc-meta-check  ( opcode extra divisor base cost push pop effect operand -- )
    >R >R >R >R >R >R >R >R
    SBOX-ABI-METADATA SBOX-MACHINE-S-OK = _pc-assert
    R> = _pc-assert R> = _pc-assert R> = _pc-assert R> = _pc-assert
    R> = _pc-assert R> = _pc-assert R> = _pc-assert R> = _pc-assert ;
"""

EPILOGUE = r"""
: _pc-finish  ( -- )
    0 _pc-case !
    DEPTH _pc-depth @ = _pc-assert
    _pc-buf @ FREE
    _pc-fails @ IF
        ." SPC FAIL " _pc-fails @ . ." / " _pc-checks @ . CR
    ELSE
        ." SPC PASS " _pc-checks @ . CR
    THEN ;

_pc-finish
"""


def metadata_lines() -> list[str]:
    """Each opcode record's machine fields against SBOX-ABI-METADATA."""
    out = []
    rows = [line for line in LINES if line.startswith("opcode ")]
    rows.append("opcode 80 IMPORT.CALL 8 3 0 0 6 1 0 4")
    for line in rows:
        fields = line.split(" ")
        code = fields[1]
        values = " ".join(reversed(fields[3:]))
        out.append(f"    {code} {values} _pc-meta-check")
    return out


def fixture_bytes() -> bytes:
    lines = [PRELUDE]
    lines.append("0 _pc-fails ! 0 _pc-checks ! DEPTH _pc-depth !")
    lines.append("65536 2 * ALLOCATE 0= _pc-assert _pc-buf !")

    # The embedded bytes, the golden digests and the loaded table.
    lines.append(": _pc-pure  ( -- )")
    lines.append("    1 _pc-case !")
    lines.append(f"    SBOX-PROFILE-PURE-DESCRIPTOR NIP {PROFILE_BYTES} = _pc-assert")
    lines.append("    _bx-reset")
    lines.append("    SBOX-PROFILE-PURE-DESCRIPTOR _pc-copy _pc-ws")
    lines.append("    SBOX-DIGEST-RAW SBOX-DIGEST-S-OK = _pc-assert")
    lines.extend(hex_lines(bytes.fromhex(PROFILE_RAW)))
    lines.append("    _pc-copy 32 COMPARE 0= _pc-assert")
    lines.append("    _pc-prof _pc-ws SBOX-PROFILE-PURE-INIT SBOX-PROFILE-S-OK = _pc-assert")
    lines.append("    _pc-prof SBOX-PROFILE-VALID? _pc-assert")
    lines.extend(hex_lines(bytes.fromhex(PROFILE_DIGEST)))
    lines.append("    _pc-digest=")
    lines.append("    _pc-ws SBOX-PROFILE-LOAD-ERROR@ SBOX-PROFILE-S-OK = _pc-assert")
    lines.append("    -1 = _pc-assert SBOX-PROFILE-S-OK = _pc-assert")
    lines.append("    _pc-scratch-clear? _pc-assert")
    lines.append("    _pc-prof SBOX-PROFILE-IDENTIFIER$")
    lines.append('    S" org.akashic.sandbox.pure-compute" COMPARE 0= _pc-assert')
    lines.append("    _pc-prof SBOX-PROFILE-SEMANTICS@ SBOX-PROFILE-S-OK = _pc-assert")
    lines.append("    SBOX-PROFILE-SEMANTICS-PURE = _pc-assert")
    enabled = {int(line.split(" ")[1]) for line in LINES if line.startswith("opcode ")}
    for code in range(0, 128):
        flag = "_pc-assert" if code in enabled else "0= _pc-assert"
        lines.append(f"    {code} _pc-prof SBOX-PROFILE-OPCODE-ENABLED? DROP {flag}")
    lines.append("    1 _pc-prof SBOX-PROFILE-SIGNATURE-ENABLED? DROP _pc-assert")
    lines.append("    0 _pc-prof SBOX-PROFILE-SIGNATURE-ENABLED? DROP 0= _pc-assert")
    lines.append("    2 _pc-prof SBOX-PROFILE-SIGNATURE-ENABLED? DROP 0= _pc-assert")
    lines.append(";")
    lines.append("_pc-pure")

    # The embedded opcode records are the machine's own metadata.
    lines.append(": _pc-machine  ( -- )")
    lines.append("    2 _pc-case !")
    lines.extend(metadata_lines())
    lines.append(";")
    lines.append("_pc-machine")

    # Queries, copies and arguments.
    lines.append(r""": _pc-objects  ( -- )
    3 _pc-case !
    _pc-prof _pc-ws SBOX-PROFILE-PURE-INIT SBOX-PROFILE-S-OK = _pc-assert
    0x0F _pc-prof SBOX-PROFILE-OPCODE-ENABLED?
        SBOX-PROFILE-S-OPCODE = _pc-assert 0= _pc-assert
    \ A byte copy is not a profile.
    _pc-prof _pc-copy SBOX-PROFILE-SIZE MOVE
    _pc-copy SBOX-PROFILE-VALID? 0= _pc-assert
    _pc-copy SBOX-PROFILE-DIGEST@ 0= _pc-assert
    0 _pc-copy SBOX-PROFILE-OPCODE-ENABLED?
        SBOX-PROFILE-S-INVALID = _pc-assert DROP
    _pc-copy SBOX-PROFILE-IDENTIFIER$ NIP 0= _pc-assert
    _pc-prof SBOX-PROFILE-DIGEST@ _pc-copy SBOX-PROFILE-DIGEST= 0= _pc-assert
    _pc-prof SBOX-PROFILE-DIGEST@ 1+ _pc-prof SBOX-PROFILE-DIGEST= 0= _pc-assert
    \ Arguments that cannot be admitted leave the profile as it was.
    SBOX-PROFILE-PURE-DESCRIPTOR _pc-prof 1+ _pc-ws SBOX-PROFILE-LOAD
        SBOX-PROFILE-S-INVALID = _pc-assert
    SBOX-PROFILE-PURE-DESCRIPTOR _pc-prof 0 SBOX-PROFILE-LOAD
        SBOX-PROFILE-S-INVALID = _pc-assert
    SBOX-PROFILE-PURE-DESCRIPTOR _pc-prof _pc-ws 4 + SBOX-PROFILE-LOAD
        SBOX-PROFILE-S-INVALID = _pc-assert
    0 16 _pc-prof _pc-ws SBOX-PROFILE-LOAD SBOX-PROFILE-S-INVALID = _pc-assert
    _pc-buf @ 0 _pc-prof _pc-ws SBOX-PROFILE-LOAD
        SBOX-PROFILE-S-DESCRIPTOR = _pc-assert
    _pc-buf @ 65537 _pc-prof _pc-ws SBOX-PROFILE-LOAD
        SBOX-PROFILE-S-DESCRIPTOR = _pc-assert
    _pc-ws 64 _pc-prof _pc-ws SBOX-PROFILE-LOAD SBOX-PROFILE-S-ALIAS = _pc-assert
    _pc-prof 64 _pc-prof _pc-ws SBOX-PROFILE-LOAD SBOX-PROFILE-S-ALIAS = _pc-assert
    SBOX-PROFILE-PURE-DESCRIPTOR _pc-prof _pc-prof 8 + SBOX-PROFILE-LOAD
        SBOX-PROFILE-S-ALIAS = _pc-assert
    _pc-prof SBOX-PROFILE-VALID? _pc-assert
    \ An admitted load that fails leaves the profile invalid.
    _pc-reset 0 1 _pc-cut _pc-load SBOX-PROFILE-S-DESCRIPTOR = _pc-assert
    _pc-prof SBOX-PROFILE-VALID? 0= _pc-assert
;
_pc-objects""")

    case = 10
    for name, data, status, offset in variants():
        if data == PURE:
            raise AssertionError(name)
        case += 1
        lines.append(f"\\ {name}")
        lines.append("MARKER _pc-mark")
        lines.append(f": _pc-case-{case}  ( -- )")
        lines.append(f"    {case} _pc-case ! _pc-reset")
        lines.extend(splice_lines(data))
        lines.append(f"    {status} {offset} _pc-expect")
        lines.append(";")
        lines.append(f"_pc-case-{case}")
        lines.append("_pc-mark")

    for name, variant_lines, checks in loadable():
        data = make(variant_lines)
        case += 1
        lines.append(f"\\ loads: {name}")
        lines.append("MARKER _pc-mark")
        lines.append(f": _pc-case-{case}  ( -- )")
        lines.append(f"    {case} _pc-case ! _pc-reset _bx-reset")
        lines.extend(splice_lines(data))
        lines.append(f"    {OK} -1 _pc-expect")
        lines.extend(hex_lines(bytes.fromhex(digest("akashic.sandbox.profile", data))))
        lines.append("    _pc-digest=")
        lines.append(f"    {checks}")
        lines.append(";")
        lines.append(f"_pc-case-{case}")
        lines.append("_pc-mark")

    lines.append(EPILOGUE)
    return ("\n".join(lines) + "\n").encode()


def test_the_embedded_descriptor_is_the_fixture() -> None:
    text = CODEC.read_text()
    embedded = re.findall(r'^S" (.*)" _SPC-LINE,$', text, re.MULTILINE)
    assert ("\n".join(embedded) + "\n").encode() == PURE
    assert len(PURE) == PROFILE_BYTES
    assert digest(None, PURE) == PROFILE_RAW
    assert digest("akashic.sandbox.profile", PURE) == PROFILE_DIGEST


def test_every_variant_differs_from_the_fixture() -> None:
    names = [name for name, *_ in variants()]
    assert len(names) == len(set(names))
    for name, data, status, offset in variants():
        assert data != PURE, name
        assert 0 <= offset < max(len(data), 1) or status == DESCRIPTOR, name


PROFILE_NAME = "sandbox-profile-codec"


def test_the_loader_matches_the_fixture(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("sandbox/profile-codec.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - sandbox profile descriptor loader
ENTER-USERLAND
." [akashic] loading sandbox profile loader" CR TX-FLUSH
REQUIRE sandbox/profile-codec.f
REQUIRE local_testing/sbox-pcodec-test.f
""",
        ready_markers=("SPC PASS",),
        stable_markers=("SPC PASS",),
        failure_markers=(
            "SPC FAIL",
            "SPC ASSERT",
            "? (not found)",
            "Branch offset overflow",
            "dictionary full",
            "exception",
        ),
        linked=True,
        include_large_sample=False,
        initial_files=(("local_testing/sbox-pcodec-test.f", fixture_bytes()),),
    )
    image = build_image(PROFILE_NAME, tmp_path / "sandbox-profile-codec.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=1_500_000_000,
        timeout=300.0,
    )
