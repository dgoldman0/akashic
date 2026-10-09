#!/usr/bin/env python3
"""The sandbox compiler names the first error of a source and where it is.

Each case below is a source and the status, diagnostic code, byte offset
and length SBOX-COMPILE must report for it.  Offsets are computed here from
the source text, so the fixture checks the compiler's positions exactly.
"""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


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
    s = module("RETURN", entries="ENTRY SIGNATURE 1 aa main ENTRY bb main")
    case(s, SOURCE, "SIGNATURE-MIX", -1, 0)
    s = module("V.TYPE RETURN", entries="ENTRY main main")
    case(s, SOURCE, "SCALAR-TYPED", -1, 0)
    s = module("1 IF " * 65 + "RETURN")
    case(s, CAPACITY, "LIMIT", at(s, "IF", 64), 2)
    s = module("DUP I64.MUL RETURN")
    case(s, PROFILE, "DISABLED", at(s, "I64.MUL"), 7, profile="_cd-limited")
    case(good, PROFILE, "PROFILE", -1, 0, profile="_cd-unusable")
    # Diagnostics belong to the latest compilation alone.
    case(good, OK, "NONE", -1, 0)
    return out


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

CREATE _bx-pool 16384 ALLOT
VARIABLE _bx-top
VARIABLE _bx-start
CREATE _cd-work-raw SBOX-COMPILER-WORKSPACE-SIZE 7 + ALLOT
CREATE _cd-candidate-raw 8192 7 + ALLOT
CREATE _cd-profile-raw SBOX-PROFILE-SIZE 7 + ALLOT
CREATE _cd-limited-raw SBOX-PROFILE-SIZE 7 + ALLOT
CREATE _cd-unusable-raw SBOX-PROFILE-SIZE 7 + ALLOT

: _cd-work  ( -- a ) _cd-work-raw 7 + -8 AND ;
: _cd-candidate  ( -- a ) _cd-candidate-raw 7 + -8 AND ;
: _cd-profile  ( -- a ) _cd-profile-raw 7 + -8 AND ;
: _cd-limited  ( -- a ) _cd-limited-raw 7 + -8 AND ;
: _cd-unusable  ( -- a ) _cd-unusable-raw 7 + -8 AND ;

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

\ The pure profile with I64.MUL turned off, resealed through the public
\ build words so the profile's own checks still apply.
: _cd-setup  ( -- )
    _cd-profile SBOX-PROFILE-PURE-INIT 0= _cd-assert
    _cd-profile _cd-limited SBOX-PROFILE-SIZE MOVE
    _cd-limited DUP _SBP.SELF !
    SBOX-PROFILE-STATE-BUILDING _cd-limited _SBP.STATE !
    SBOX-MACHINE-OP-I64-MUL _cd-limited SBOX-PROFILE-OPCODE-DISABLE
        0= _cd-assert
    _cd-limited SBOX-PROFILE-SEAL 0= _cd-assert
    SBOX-MACHINE-OP-I64-MUL _cd-limited SBOX-PROFILE-OPCODE-ENABLED?
        0= _cd-assert 0= _cd-assert
    _cd-unusable SBOX-PROFILE-SIZE 0 FILL ;

: _cd-zero?  ( a u -- flag )
    0 ?DO DUP I + @ IF DROP 0 UNLOOP EXIT THEN 8 +LOOP DROP -1 ;

\ Compile SOURCE and check the status, the diagnostic, and that only the
\ diagnostic header remains in the workspace.
: _cd-check  ( source source-u profile status code offset length -- )
    _cd-length ! _cd-offset ! _cd-code ! _cd-status !
    64 _cd-candidate 8192 _cd-work SBOX-COMPILE
    _cd-got-status ! DROP
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
    _cd-work SBOX-COMPILER-DIAGNOSTIC-SIZE +
        SBOX-COMPILER-WORKSPACE-SIZE SBOX-COMPILER-DIAGNOSTIC-SIZE -
        _cd-zero? _cd-assert ;
"""

EPILOGUE = r"""
\ A source of exactly the scan ceiling is scanned to its end; one byte more
\ is refused before any byte is read.
: _cd-source-max  ( -- )
    -1 _cd-case !
    SBOX-COMPILER-SOURCE-MAX 1+ ALLOCATE
    DUP 0= _cd-assert IF DROP EXIT THEN
    DUP SBOX-COMPILER-SOURCE-MAX 1+ 32 FILL
    DUP SBOX-COMPILER-SOURCE-MAX _cd-profile
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-END
        SBOX-COMPILER-SOURCE-MAX 0 _cd-check
    DUP SBOX-COMPILER-SOURCE-MAX 1+ _cd-profile
        SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT
        SBOX-COMPILER-SOURCE-MAX 0 _cd-check
    FREE ;

_cd-source-max

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
    lines = [PRELUDE,
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
    lines.append(EPILOGUE)
    return ("\n".join(lines) + "\n").encode()


PROFILE_NAME = "sandbox-compiler-diagnostics"


def test_the_compiler_names_each_error_and_its_place(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("sandbox/compiler.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - sandbox compiler diagnostics
ENTER-USERLAND
." [akashic] loading sandbox compiler diagnostics" CR TX-FLUSH
REQUIRE sandbox/compiler.f
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
        initial_files=(("local_testing/sbox-cdiag-test.f", fixture()),),
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
