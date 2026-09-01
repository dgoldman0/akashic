#!/usr/bin/env python3
"""Seconds-scale byte oracle for the canonical data-graphics READOUT text."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
MODULE = AKASHIC_ROOT / "akashic" / "tui" / "data-graphics-format.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "data-graphics-format-byte-oracle"
ORACLE_PATH = "local_testing/dgf-oracle.f"
SMOKE_MAX_STEPS = 160_000_000
SMOKE_TIMEOUT_SECONDS = 12.0


ORACLE_SOURCE = r'''\ Canonical bounded READOUT formatting oracle.
PROVIDED data-graphics-format-oracle

VARIABLE _dgf-fails
VARIABLE _dgf-checks
VARIABLE _dgf-depth
VARIABLE _dgf-byte
VARIABLE _dgf-format
VARIABLE _dgf-decimals
VARIABLE _dgf-value
VARIABLE _dgf-scale
VARIABLE _dgf-unit-a
VARIABLE _dgf-unit-u
VARIABLE _dgf-expected-a
VARIABLE _dgf-expected-u
VARIABLE _dgf-record

CREATE _dgf-graph-storage 2055 ALLOT
CREATE _dgf-builder-storage UDG-BUILDER-SIZE 7 + ALLOT
CREATE _dgf-output 256 ALLOT

: _dgf-graph   _dgf-graph-storage 7 + -8 AND ;
: _dgf-builder _dgf-builder-storage 7 + -8 AND ;

: _dgf-assert  ( flag -- )
    1 _dgf-checks +!
    0= IF
        1 _dgf-fails +!
        ." DGF ASSERT " _dgf-checks @ . CR
    THEN ;

: _dgf-stack  ( -- )
    DEPTH DUP _dgf-depth @ <> IF
        ." DGF STACK " _dgf-depth @ . ." -> " DUP . CR .S CR
    THEN
    _dgf-depth @ = _dgf-assert ;

: _dgf-ok  ( status -- )
    DUP DGF-S-OK <> IF ." DGF STATUS " DUP . CR THEN
    DGF-S-OK = _dgf-assert ;

: _dgf-filled?  ( address length byte -- flag )
    _dgf-byte !
    0 ?DO
        DUP I + C@ _dgf-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _dgf-build  ( format decimals value scale unit-a unit-u -- record )
    _dgf-unit-u ! _dgf-unit-a ! _dgf-scale ! _dgf-value !
    _dgf-decimals ! _dgf-format !
    _dgf-graph 2048 _dgf-builder UDG-BUILDER-INIT _dgf-ok
    100 0 0 2 80 UDG-STATE-VISIBLE _dgf-builder UDG-BEGIN _dgf-ok
    101 0 0 1 40 0 UDG-OBJECT-VISIBLE
        0x11223344 0x55667788
        _dgf-format @ _dgf-decimals @ _dgf-value @ _dgf-scale @
        _dgf-unit-a @ _dgf-unit-u @ _dgf-builder UDG-READOUT _dgf-ok
    _dgf-builder UDG-END _dgf-ok
    _dgf-builder UDG-BUILDER-FINISH _dgf-ok DROP
    _dgf-graph UDG-FIRST-RECORD ;

: _dgf-exact
    ( format decimals value scale unit-a unit-u expected-a expected-u -- )
    _dgf-expected-u ! _dgf-expected-a !
    _dgf-build _dgf-record !
    _dgf-record @ DGF-READOUT-MEASURE _dgf-ok
        _dgf-expected-u @ = _dgf-assert
    _dgf-output 256 0xA5 FILL
    _dgf-record @ _dgf-output 256 DGF-READOUT-FORMAT _dgf-ok
        _dgf-expected-u @ = _dgf-assert
    _dgf-output _dgf-expected-u @
        _dgf-expected-a @ _dgf-expected-u @ COMPARE 0= _dgf-assert
    _dgf-output _dgf-expected-u @ +
        256 _dgf-expected-u @ - 0xA5 _dgf-filled? _dgf-assert ;

: _dgf-expect-invalid  ( record -- )
    DUP DGF-READOUT-MEASURE
        DGF-S-INVALID = _dgf-assert 0= _dgf-assert
    _dgf-output 256 0xA5 FILL
    _dgf-output 256 DGF-READOUT-FORMAT
        DGF-S-INVALID = _dgf-assert 0= _dgf-assert
    _dgf-output 256 0xA5 _dgf-filled? _dgf-assert ;

: _dgf-exact-cases  ( -- )
    UDG-READOUT-INTEGER 0 0 1 0 0 S" 0" _dgf-exact
    UDG-READOUT-INTEGER 0 0x7FFFFFFFFFFFFFFF 1 0 0
        S" 9223372036854775807" _dgf-exact
    UDG-READOUT-INTEGER 0 0x8000000000000000 1 0 0
        S" -9223372036854775808" _dgf-exact
    UDG-READOUT-INTEGER 0 42 1 S" ms" S" 42ms" _dgf-exact

    UDG-READOUT-FIXED 2 9995 1000 0 0 S" 10.00" _dgf-exact
    UDG-READOUT-FIXED 2 -9995 1000 0 0 S" -10.00" _dgf-exact
    UDG-READOUT-FIXED 2 -1 1000 0 0 S" -0.00" _dgf-exact
    UDG-READOUT-FIXED 2 9994 1000 0 0 S" 9.99" _dgf-exact
    UDG-READOUT-FIXED 4 1 8 0 0 S" 0.1250" _dgf-exact
    UDG-READOUT-FIXED 3 19495 10000 0 0 S" 1.950" _dgf-exact

    UDG-READOUT-PERCENT 1 1 8 0 0 S" 12.5%" _dgf-exact
    UDG-READOUT-PERCENT 1 1999 2000 0 0 S" 100.0%" _dgf-exact
    UDG-READOUT-PERCENT 0 0x7FFFFFFFFFFFFFFF 1 0 0
        S" 922337203685477580700%" _dgf-exact
    UDG-READOUT-PERCENT 0 0x8000000000000000 1 0 0
        S" -922337203685477580800%" _dgf-exact ;

: _dgf-capacity-cases  ( -- )
    UDG-READOUT-FIXED 2 -12345 100 S" dB" _dgf-build
        DUP _dgf-record !
    DGF-READOUT-MEASURE _dgf-ok DUP 1- >R DROP
    _dgf-output 256 0xA5 FILL
    _dgf-record @ _dgf-output R> DGF-READOUT-FORMAT
        DGF-S-CAPACITY = _dgf-assert 0= _dgf-assert
    _dgf-output 256 0xA5 _dgf-filled? _dgf-assert

    \ A huge, otherwise-valid width is measured in constant work and rejected
    \ for the tiny destination before a fractional formatting loop begins.
    UDG-READOUT-FIXED 0xFFFFFF00 0 1 0 0 _dgf-build
        DUP _dgf-record !
    DGF-READOUT-MEASURE _dgf-ok 0xFFFFFF02 = _dgf-assert
    _dgf-output 256 0xA5 FILL
    _dgf-record @ _dgf-output 256 DGF-READOUT-FORMAT
        DGF-S-CAPACITY = _dgf-assert 0= _dgf-assert
    _dgf-output 256 0xA5 _dgf-filled? _dgf-assert ;

: _dgf-alias-cases  ( -- )
    UDG-READOUT-INTEGER 0 42 1 S" ms" _dgf-build DUP _dgf-record !
    DUP UDG-READOUT-UNIT@ DROP DUP C@ >R
    8 DGF-READOUT-FORMAT DGF-S-INVALID = _dgf-assert 0= _dgf-assert
    _dgf-record @ UDG-READOUT-UNIT@ DROP C@ R> = _dgf-assert

    0x123456789ABCDEF0 _DGF-F-DST !
    _dgf-record @ _DGF-F-DST 32 DGF-READOUT-FORMAT
        DGF-S-INVALID = _dgf-assert 0= _dgf-assert
    _DGF-F-DST @ 0x123456789ABCDEF0 = _dgf-assert

    _dgf-output 256 DGF-STORAGE-DISJOINT? _dgf-assert
    0 0 DGF-STORAGE-DISJOINT? _dgf-assert
    _dgf-output 0 DGF-STORAGE-DISJOINT? 0= _dgf-assert
    0 8 DGF-STORAGE-DISJOINT? 0= _dgf-assert
    _DGF-OWNED-START 8 DGF-STORAGE-DISJOINT? 0= _dgf-assert ;

: _dgf-invalid-cases  ( -- )
    UDG-READOUT-INTEGER 0 42 1 0 0 _dgf-build
        DUP UDG-RECORD-KIND-OFFSET + UDG-K-METER SWAP !
        _dgf-expect-invalid
    UDG-READOUT-INTEGER 0 42 1 0 0 _dgf-build
        DUP UDG-RECORD-BYTES-OFFSET + 152 SWAP !
        _dgf-expect-invalid
    UDG-READOUT-INTEGER 0 42 1 0 0 _dgf-build
        DUP UDG-READOUT-SCALE-OFFSET + 2 SWAP !
        _dgf-expect-invalid
    UDG-READOUT-INTEGER 0 42 1 0 0 _dgf-build
        DUP UDG-RECORD-KEY-OFFSET + 0 SWAP !
        _dgf-expect-invalid
    UDG-READOUT-INTEGER 0 42 1 S" ms" _dgf-build
        DUP UDG-READOUT-UNIT-OFFSET + 10 SWAP C!
        _dgf-expect-invalid
    UDG-READOUT-INTEGER 0 42 1 S" ms" _dgf-build
        DUP UDG-READOUT-UNIT-OFFSET + 0xFF SWAP C!
        _dgf-expect-invalid
    UDG-READOUT-INTEGER 0 42 1 S" x" _dgf-build
        DUP UDG-READOUT-UNIT-OFFSET + 1+ 1 SWAP C!
        _dgf-expect-invalid ;

: _dgf-run  ( -- )
    0 _dgf-fails ! 0 _dgf-checks ! DEPTH _dgf-depth !
    DGF-S-OK UDG-S-OK = _dgf-assert
    DGF-S-CAPACITY UDG-S-CAPACITY = _dgf-assert
    DGF-S-INVALID UDG-S-INVALID = _dgf-assert
    _dgf-exact-cases _dgf-stack
    _dgf-capacity-cases _dgf-stack
    _dgf-alias-cases _dgf-stack
    _dgf-invalid-cases _dgf-stack
    _dgf-fails @ 0= IF
        ." DGF PASS " _dgf-checks @ .
    ELSE
        ." DGF FAIL " _dgf-fails @ . ." / " _dgf-checks @ .
    THEN CR ;

_dgf-run
'''


AUTOEXEC = rf'''\ autoexec.f - canonical data graphics formatter oracle
ENTER-USERLAND
." [akashic] loading canonical data graphics formatter oracle" CR
REQUIRE tui/data-graphics-format.f
REQUIRE {ORACLE_PATH}
'''


def test_data_graphics_format_byte_oracle(tmp_path: Path) -> None:
    source = MODULE.read_text(encoding="utf-8")
    assert "REQUIRE data-graphics-model.f" in source
    assert "UDG-READOUT-FORMATTED-BYTES?" in source
    assert "NUM>STR" not in source
    assert "ALLOCATE" not in source
    assert "DGF-READOUT-MEASURE" in source
    assert "DGF-READOUT-FORMAT" in source
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("tui/data-graphics-format.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DGF PASS",),
        stable_markers=("DGF PASS",),
        failure_markers=(
            "DGF FAIL",
            "DGF ASSERT",
            "DGF STACK",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(PROFILE_NAME, tmp_path / "data-graphics-format.img")
        assert smoke(
            PROFILE_NAME,
            image,
            cols=80,
            rows=24,
            max_steps=SMOKE_MAX_STEPS,
            timeout=SMOKE_TIMEOUT_SECONDS,
        )
    finally:
        if previous is None:
            PROFILES.pop(PROFILE_NAME, None)
        else:
            PROFILES[PROFILE_NAME] = previous


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_data_graphics_format_byte_oracle(Path(directory))
