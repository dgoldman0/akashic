#!/usr/bin/env python3
"""The sandbox compiler names the first error of a source and where it is.

Each case below is a source and the status, diagnostic code, byte offset
and length SBOX-COMPILE must report for it.  Offsets are computed here from
the source text, so the fixture checks the compiler's positions exactly.
Every compilation runs in the workspace its source measures, and nothing
past that workspace may change.
"""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
PURE_DESCRIPTOR = (LOCAL_TESTING.parent / "docs" / "sandbox" / "fixtures" /
                   "pure-compute.profile")
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import (  # noqa: E402
    _SANDBOX_QUALIFICATION_FILE,
    Profile,
    PROFILES,
    build_image,
    smoke,
)


def at(source: str, token: str, nth: int = 0) -> int:
    """Offset of the NTH whitespace-delimited occurrence of TOKEN."""
    words, position, found = source.split(" "), 0, -1
    for word in words:
        if word == token:
            found += 1
            if found == nth:
                return position
        position += len(word) + 1
    raise AssertionError((token, nth))


HEAD = "FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0"
ENTRY = "ENTRY SIGNATURE 1 main main"


def module(body: str, *, head: str = HEAD, entries: str = ENTRY) -> str:
    return f"{head} {body} END {entries}".replace("  ", " ")


OK = "SBOX-COMPILER-S-OK"
SOURCE = "SBOX-COMPILER-S-SOURCE"
CAPACITY = "SBOX-COMPILER-S-CAPACITY"
PROFILE = "SBOX-COMPILER-S-PROFILE"


def cases() -> list[tuple[str, bytes, str, str, int, int]]:
    """(profile, source, status, code, offset, length)."""
    out = []

    def case(source, status, code, offset, length, profile="_cd-profile"):
        data = source if isinstance(source, bytes) else source.encode()
        out.append((profile, data, status, f"SBOX-COMPILER-E-{code}",
                    offset, length))

    good = module("RETURN")
    case(good, OK, "NONE", -1, 0)
    case(good.encode() + b"\x80", SOURCE, "BYTE", len(good), 1)
    s = good.replace("FUNCTION main", "FUNCTION ma\\in")
    case(s, SOURCE, "BACKSLASH", at(s, "ma\\in") + 2, 1)
    long_name = "a" * 64
    s = good.replace("FUNCTION main", f"FUNCTION {long_name}")
    case(s, CAPACITY, "TOKEN-LENGTH", at(s, long_name), 64)
    s = "FUNCTION main PARAMS 1 RESULTS 1"
    case(s, SOURCE, "END", len(s), 0)
    case("ENTRY main main", SOURCE, "EXPECTED-FUNCTION", 0, 5)
    s = f"{HEAD} RETURN END FOO"
    case(s, SOURCE, "EXPECTED-ENTRY", at(s, "FOO"), 3)
    s = f"{HEAD} RETURN END"
    case(s, SOURCE, "EXPECTED-ENTRY", len(s), 0)
    s = f"{good} FOO"
    case(s, SOURCE, "EXPECTED-ENTRY", at(s, "FOO"), 3)
    s = module("RETURN", head="FUNCTION main RESULTS 1 LOCALS 0")
    case(s, SOURCE, "EXPECTED-PARAMS", at(s, "RESULTS"), 7)
    s = module("RETURN", head="FUNCTION main PARAMS 1 LOCALS 0")
    case(s, SOURCE, "EXPECTED-RESULTS", at(s, "LOCALS"), 6)
    s = module("RETURN", head="FUNCTION main PARAMS 1 RESULTS 1")
    case(s, SOURCE, "EXPECTED-LOCALS", at(s, "RETURN"), 6)
    s = good.replace("FUNCTION main", "FUNCTION Main")
    case(s, SOURCE, "NAME", at(s, "Main"), 4)
    s = f"{HEAD} RETURN END {HEAD} RETURN END {ENTRY}"
    case(s, SOURCE, "DUPLICATE", at(s, "main", 1), 4)
    s = good.replace("PARAMS 1", "PARAMS 01")
    case(s, SOURCE, "NUMBER", at(s, "01"), 2)
    s = module("12x RETURN")
    case(s, SOURCE, "NUMBER", at(s, "12x"), 3)
    s = module("-0 RETURN")
    case(s, SOURCE, "NUMBER", at(s, "-0"), 2)
    s = module("FROB RETURN")
    case(s, SOURCE, "UNKNOWN", at(s, "FROB"), 4)
    s = module("THEN RETURN")
    case(s, SOURCE, "UNMATCHED", at(s, "THEN"), 4)
    s = module("RETURN 7")
    case(s, SOURCE, "UNREACHABLE", at(s, "7"), 1)
    s = module("IF RETURN")
    case(s, SOURCE, "OPEN-CONTROL", at(s, "END"), 3)
    s = module("")
    case(s, SOURCE, "FALLTHROUGH", at(s, "END"), 3)
    s = module("0 1 DO RETURN LOOP RETURN")
    case(s, SOURCE, "RETURN-IN-LOOP", at(s, "RETURN"), 6)
    s = module("R RETURN")
    case(s, SOURCE, "LOOP-INDEX", at(s, "R"), 1)
    s = module("LOCAL.GET 9 RETURN",
               head="FUNCTION main PARAMS 1 RESULTS 1 LOCALS 1")
    case(s, SOURCE, "LOCAL-INDEX", at(s, "9"), 1)
    s = module("CALL nothere RETURN")
    case(s, SOURCE, "UNDEFINED-CALL", at(s, "nothere"), 7)
    s = module("RETURN", entries="ENTRY SIGNATURE 1 zz main "
                                 "ENTRY SIGNATURE 1 aa main")
    case(s, SOURCE, "ENTRY-ORDER", at(s, "aa"), 2)
    s = module("RETURN", entries="ENTRY SIGNATURE 1 main nothere")
    case(s, SOURCE, "ENTRY-FUNCTION", at(s, "nothere"), 7)
    s = module("RETURN", entries="ENTRY SIGNATURE 0 main main")
    case(s, SOURCE, "SIGNATURE", at(s, "0", 1), 1)
    s = module("RETURN", head="FUNCTION main PARAMS 2 RESULTS 1 LOCALS 0")
    case(s, SOURCE, "SIGNATURE", at(s, "main", 2), 4)
    # The pure profile enables no scalar entry; the name stands in for the
    # omitted signature.
    s = module("RETURN", entries="ENTRY main main")
    case(s, PROFILE, "SIGNATURE", at(s, "main", 1), 4)
    s = module("RETURN", entries="ENTRY SIGNATURE 1 aa main ENTRY bb main")
    case(s, PROFILE, "SIGNATURE", at(s, "bb"), 2)
    # Scalar qualification enables them, and their rules still hold.
    case(s, SOURCE, "SIGNATURE-MIX", -1, 0, profile="_cd-qual")
    s = module("V.TYPE RETURN", entries="ENTRY main main")
    case(s, SOURCE, "SCALAR-TYPED", -1, 0, profile="_cd-qual")
    # Control nesting is bounded only by the source itself.
    s = module("1 IF " * 100 + "THEN " * 100 + "RETURN")
    case(s, OK, "NONE", -1, 0)
    s = module("DUP I64.MUL RETURN")
    case(s, PROFILE, "DISABLED", at(s, "I64.MUL"), 7, profile="_cd-limited")
    case(good, PROFILE, "PROFILE", -1, 0, profile="_cd-unusable")
    # Diagnostics belong to the latest compilation alone.
    case(good, OK, "NONE", -1, 0)
    return out


def phrase(source: str, text: str, nth: int = 0) -> int:
    """Offset of the NTH occurrence of TEXT."""
    position = -1
    for _ in range(nth + 1):
        position = source.index(text, position + 1)
    return position


def map_cases() -> list[tuple[str, list[str]]]:
    """Successful sources and the source span of each instruction."""
    good = module("RETURN")
    rich = (
        f"{HEAD.replace('LOCALS 0', 'LOCALS 1')} LOCAL.SET 0 LOCAL.GET 0 "
        "CALL helper RETURN END FUNCTION helper PARAMS 1 RESULTS 1 LOCALS 0 "
        f"RETURN END {ENTRY}"
    )
    rich_spans = [
        ("LOCAL.SET 0", 0), ("LOCAL.GET 0", 0), ("CALL helper", 0),
        ("RETURN", 0), ("RETURN", 1),
    ]
    out = [(good, [f"0 {phrase(good, 'RETURN')} 6 _cd-span", "1 _cd-no-span"])]
    checks = [
        f"{index} {phrase(rich, text, nth)} {len(text)} _cd-span"
        for index, (text, nth) in enumerate(rich_spans)
    ]
    out.append((rich, checks + [f"{len(rich_spans)} _cd-no-span"]))
    # A failed compilation keeps no map.
    out.append((module("FROB RETURN"), ["0 _cd-no-span"]))
    return out


def limited_descriptor() -> bytes:
    """The pure descriptor without I64.MUL, under its own identifier."""
    lines = PURE_DESCRIPTOR.read_text(encoding="ascii").split("\n")
    assert lines[-1] == ""
    mul = [line for line in lines if line.startswith("opcode 34 I64.MUL ")]
    assert len(mul) == 1
    out = []
    for line in lines[:-1]:
        if line == mul[0]:
            continue
        if line == "profile org.akashic.sandbox.pure-compute":
            line += ".no-multiply"
        if line.startswith("end "):
            counts = line.split(" ")[1:]
            counts[-1] = str(int(counts[-1]) - 1)
            line = "end " + " ".join(counts)
        out.append(line)
    assert out != lines[:-1]
    return ("\n".join(out) + "\n").encode("ascii")


def hex_load(data: bytes) -> list[str]:
    text = data.hex()
    lines = ["_bx-begin"]
    lines += [f'S" {text[i:i + 96]}" _bx-add' for i in range(0, len(text), 96)]
    return lines + ["_bx-end"]


PRELUDE = r"""\ Generated: sandbox compiler diagnostics.
PROVIDED sbox-cdiag-tests

VARIABLE _cd-fails
VARIABLE _cd-checks
VARIABLE _cd-case
VARIABLE _cd-depth
VARIABLE _cd-status
VARIABLE _cd-code
VARIABLE _cd-offset
VARIABLE _cd-length
VARIABLE _cd-got-status
VARIABLE _cd-got-code
VARIABLE _cd-got-offset
VARIABLE _cd-got-length
VARIABLE _cd-total
VARIABLE _cd-keep
VARIABLE _cd-written
VARIABLE _cd-cap
VARIABLE _cd-byte

\ Every source here is small, so its measured workspace fits this.
65536 CONSTANT _cd-work-cap

CREATE _bx-pool 16384 ALLOT
VARIABLE _bx-top
VARIABLE _bx-start
CREATE _cd-work-raw _cd-work-cap 7 + ALLOT
CREATE _cd-artifact-raw 8192 7 + ALLOT
CREATE _cd-profile-raw SBOX-PROFILE-SIZE 7 + ALLOT
CREATE _cd-limited-raw SBOX-PROFILE-SIZE 7 + ALLOT
CREATE _cd-unusable-raw SBOX-PROFILE-SIZE 7 + ALLOT
CREATE _cd-qual-raw SBOX-PROFILE-SIZE 7 + ALLOT
CREATE _cd-load-raw SBOX-PROFILE-LOAD-WORKSPACE-SIZE 7 + ALLOT

: _cd-work  ( -- a ) _cd-work-raw 7 + -8 AND ;
: _cd-load  ( -- a ) _cd-load-raw 7 + -8 AND ;
: _cd-artifact  ( -- a ) _cd-artifact-raw 7 + -8 AND ;
: _cd-profile  ( -- a ) _cd-profile-raw 7 + -8 AND ;
: _cd-limited  ( -- a ) _cd-limited-raw 7 + -8 AND ;
: _cd-unusable  ( -- a ) _cd-unusable-raw 7 + -8 AND ;
: _cd-qual  ( -- a ) _cd-qual-raw 7 + -8 AND ;

: _cd-assert  ( flag -- )
    1 _cd-checks +!
    0= IF
        1 _cd-fails +!
        ." CDIAG ASSERT case " _cd-case @ . ." check " _cd-checks @ . CR
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

"""

SETUP = r"""
\ The pure profile, the scalar-qualification profile, and one loaded from a
\ descriptor without I64.MUL.
: _cd-setup  ( -- )
    8192 _cd-cap !
    _cd-profile _cd-load SBOX-PROFILE-PURE-INIT 0= _cd-assert
    _cd-qual _cd-load SBOX-QUALIFICATION-INIT 0= _cd-assert
    _cd-limited-descriptor _cd-limited _cd-load SBOX-PROFILE-LOAD
        0= _cd-assert
    SBOX-MACHINE-OP-I64-MUL _cd-limited SBOX-PROFILE-OPCODE-ENABLED?
        0= _cd-assert 0= _cd-assert
    SBOX-MACHINE-OP-I64-ADD _cd-limited SBOX-PROFILE-OPCODE-ENABLED?
        0= _cd-assert _cd-assert
    _cd-unusable SBOX-PROFILE-SIZE 0 FILL ;

: _cd-zero?  ( a u -- flag )
    0 ?DO DUP I + @ IF DROP 0 UNLOOP EXIT THEN 8 +LOOP DROP -1 ;

: _cd-filled?  ( a u byte -- flag )
    _cd-byte !
    0 ?DO DUP I + C@ _cd-byte @ <> IF DROP 0 UNLOOP EXIT THEN LOOP
    DROP -1 ;

\ The latest compilation's source span for one instruction.
: _cd-span  ( index offset length -- )
    ROT _cd-work SBOX-COMPILER-SOURCE-SPAN@ SBOX-COMPILER-S-OK = _cd-assert
    ROT = _cd-assert = _cd-assert ;

: _cd-no-span  ( index -- )
    _cd-work SBOX-COMPILER-SOURCE-SPAN@ SBOX-COMPILER-S-INVALID = _cd-assert
    0= _cd-assert -1 = _cd-assert ;

\ Compile SOURCE in its measured workspace and check the status, the
\ diagnostic, and what remains in the workspace.
: _cd-check  ( source source-u profile status code offset length -- )
    _cd-length ! _cd-offset ! _cd-code ! _cd-status !
    2 PICK 2 PICK SBOX-COMPILER-WORKSPACE-MEASURE
        SBOX-COMPILER-S-OK = _cd-assert
        DUP _cd-total ! _cd-work-cap <= _cd-assert
    2 PICK 2 PICK SBOX-COMPILER-DIAGNOSTIC-MEASURE
        SBOX-COMPILER-S-OK = _cd-assert _cd-keep !
    _cd-work _cd-work-cap 0x5A FILL
    64 _cd-artifact _cd-cap @ _cd-work SBOX-COMPILE
    _cd-got-status ! _cd-written !
    _cd-work SBOX-COMPILER-LAST-STATUS@ SBOX-COMPILER-S-OK = _cd-assert
        _cd-got-status @ = _cd-assert
    _cd-work SBOX-COMPILER-ERROR@ SBOX-COMPILER-S-OK = _cd-assert
    _cd-got-length ! _cd-got-offset ! _cd-got-code !
    _cd-got-status @ _cd-status @ =
    _cd-got-code @ _cd-code @ = AND
    _cd-got-offset @ _cd-offset @ = AND
    _cd-got-length @ _cd-length @ = AND
    DUP 0= IF
        ." CDIAG GOT " _cd-got-status @ . _cd-got-code @ .
        _cd-got-offset @ . _cd-got-length @ . CR
    THEN
    _cd-assert
    \ Only the header and, after a success, the source map remain, and
    \ nothing past the measured workspace moved.
    _cd-work SBOX-COMPILER-DIAGNOSTIC-SIZE +
        _SCD-MAP SBOX-COMPILER-DIAGNOSTIC-SIZE - _cd-zero? _cd-assert
    _cd-got-status @ IF
        _cd-work _SCD-MAP + _cd-keep @ _SCD-MAP - _cd-zero? _cd-assert
    THEN
    _cd-work _cd-keep @ + _cd-total @ _cd-keep @ - _cd-zero? _cd-assert
    _cd-work _cd-total @ + _cd-work-cap _cd-total @ - 0x5A _cd-filled?
        _cd-assert ;
"""

EPILOGUE = r"""
: _cd-good  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 RETURN END ENTRY SIGNATURE 1 main main" ;

\ An artifact buffer one byte short of the module is refused with LIMIT.
: _cd-artifact-limit  ( -- )
    -1 _cd-case !
    _cd-good _cd-profile
        SBOX-COMPILER-S-OK SBOX-COMPILER-E-NONE -1 0 _cd-check
    _cd-written @ 1- _cd-cap !
    _cd-good _cd-profile
        SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT -1 0 _cd-check
    _cd-written @ 0= _cd-assert
    8192 _cd-cap ! ;

_cd-artifact-limit

: _cd-finish  ( -- )
    0 _cd-case !
    0 SBOX-COMPILER-ERROR@ SBOX-COMPILER-S-INVALID = _cd-assert
        2DROP DROP
    DEPTH _cd-depth @ = _cd-assert
    _cd-fails @ IF
        ." CDIAG FAIL " _cd-fails @ . ." / " _cd-checks @ . CR
    ELSE
        ." CDIAG PASS " _cd-checks @ . CR
    THEN ;

_cd-finish
"""


def fixture() -> bytes:
    lines = [PRELUDE, ": _cd-limited-descriptor  ( -- address length )",
             "    _bx-reset"]
    lines.extend("    " + line for line in hex_load(limited_descriptor()))
    lines += [";", SETUP,
              "0 _cd-fails ! 0 _cd-checks ! DEPTH _cd-depth ! _cd-setup"]
    for number, (profile, data, status, code, offset, length) in enumerate(
        cases(), start=1
    ):
        lines.append("MARKER _cd-mark")
        lines.append(f": _cd-case-{number}  ( -- )")
        lines.append(f"    {number} _cd-case ! _bx-reset")
        lines.extend("    " + line for line in hex_load(data))
        lines.append(f"    {profile} {status} {code} {offset} {length} _cd-check")
        lines.append(";")
        lines.append(f"_cd-case-{number}")
        lines.append("_cd-mark")
    for offset, (source, checks) in enumerate(map_cases(), start=1):
        number = 1000 + offset
        code = "OK NONE" if "FROB" not in source else "SOURCE UNKNOWN"
        status, error = code.split()
        position, length = (-1, 0) if status == "OK" else (
            at(source, "FROB"), 4)
        lines.append("MARKER _cd-mark")
        lines.append(f": _cd-case-{number}  ( -- )")
        lines.append(f"    {number} _cd-case ! _bx-reset")
        lines.extend("    " + line for line in hex_load(source.encode()))
        lines.append(
            f"    _cd-profile SBOX-COMPILER-S-{status} SBOX-COMPILER-E-{error}"
            f" {position} {length} _cd-check"
        )
        lines.extend("    " + line for line in checks)
        lines.append(";")
        lines.append(f"_cd-case-{number}")
        lines.append("_cd-mark")
    lines.append(EPILOGUE)
    return ("\n".join(lines) + "\n").encode()


PROFILE_NAME = "sandbox-compiler-diagnostics"


def test_the_compiler_names_each_error_and_its_place(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("sandbox/compiler.f", "sandbox/profile-codec.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - sandbox compiler diagnostics
ENTER-USERLAND
." [akashic] loading sandbox compiler diagnostics" CR TX-FLUSH
REQUIRE sandbox/compiler.f
REQUIRE sandbox/profile-codec.f
REQUIRE local_testing/sbox-qual-profile.f
REQUIRE local_testing/sbox-cdiag-test.f
""",
        ready_markers=("CDIAG PASS",),
        stable_markers=("CDIAG PASS",),
        failure_markers=(
            "CDIAG FAIL",
            "CDIAG ASSERT",
            "? (not found)",
            "Branch offset overflow",
            "dictionary full",
            "exception",
        ),
        linked=True,
        include_large_sample=False,
        initial_files=(
            _SANDBOX_QUALIFICATION_FILE,
            ("local_testing/sbox-cdiag-test.f", fixture()),
        ),
    )
    image = build_image(PROFILE_NAME, tmp_path / "compiler-diagnostics.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=800_000_000,
        timeout=120.0,
    )
