#!/usr/bin/env python3
"""Seconds-scale byte and validator oracle for semantic data graphics."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
MODULE = AKASHIC_ROOT / "akashic" / "tui" / "semantic-data-graphics.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "semantic-data-graphics-byte-oracle"
ORACLE_PATH = "local_testing/udg-byte-oracle.f"
SMOKE_MAX_STEPS = 120_000_000
SMOKE_TIMEOUT_SECONDS = 12.0


_MODULE_TEXT = MODULE.read_text(encoding="utf-8")
_MODULE_BODY = "\n".join(
    line
    for line in _MODULE_TEXT.splitlines()
    if not line.startswith("PROVIDED ") and not line.startswith("REQUIRE ")
)


ORACLE_STUBS = r'''\ Standalone oracle identity.
PROVIDED semantic-data-graphics-oracle
'''


ORACLE_CASES = r'''\ Focused native-byte and complete-validation cases.
VARIABLE _udg-fails
VARIABLE _udg-checks
VARIABLE _udg-depth
VARIABLE _udg-fill-byte
VARIABLE _udg-r0
VARIABLE _udg-r1
VARIABLE _udg-r2
VARIABLE _udg-expected

CREATE _udg-output-storage 2055 ALLOT
CREATE _udg-summary-storage UDG-SUMMARY-SIZE 7 + ALLOT
CREATE _udg-builder-storage UDG-BUILDER-SIZE 7 + ALLOT

\ Native graph, summary, and builder values require eight-byte starts.  The
\ target dictionary itself does not promise CREATE more than byte alignment.
: _udg-output  _udg-output-storage 7 + -8 AND ;
: _udg-summary _udg-summary-storage 7 + -8 AND ;
: _udg-builder _udg-builder-storage 7 + -8 AND ;

: _udg-assert  ( flag -- )
    1 _udg-checks +!
    0= IF
        1 _udg-fails +!
        ." UDG ASSERT " _udg-checks @ . CR
    THEN ;

: _udg-stack  ( -- )
    DEPTH DUP _udg-depth @ <> IF
        ." UDG STACK " _udg-depth @ . ." -> " DUP . CR .S CR
    THEN
    _udg-depth @ = _udg-assert ;

: _udg-ok  ( status -- )
    DUP UDG-S-OK <> IF ." UDG STATUS " DUP . CR THEN
    UDG-S-OK = _udg-assert ;

: _udg-filled?  ( address length byte -- flag )
    _udg-fill-byte !
    0 ?DO
        DUP I + C@ _udg-fill-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _udg-readout  ( -- status )
    101 -2 -3 1 12 -1 UDG-OBJECT-VISIBLE
    0x11223344 0x55667788 UDG-READOUT-FIXED 2 -12345 100
    S" dB" _udg-builder UDG-READOUT ;

: _udg-meter  ( -- status )
    102 12 41 2 20 0 UDG-OBJECT-VISIBLE
    0x01020304 0xA0B0C0D0 UDG-METER-HORIZONTAL
    UDG-METER-SHOW-VALUE -20 80 35 _udg-builder UDG-METER ;

: _udg-status  ( -- status )
    103 5 2 1 2 7 0 0x11111111 0xEEEEEEEE
    -1 UDG-STATUS-DIAMOND _udg-builder UDG-STATUS ;

: _udg-begin  ( -- )
    100 2 3 10 40 UDG-STATE-VISIBLE UDG-STATE-ENABLED OR
    _udg-builder UDG-BEGIN _udg-ok ;

: _udg-instrument  ( -- )
    _udg-begin
    _udg-readout _udg-ok
    _udg-meter _udg-ok
    _udg-status _udg-ok
    _udg-builder UDG-END _udg-ok ;

: _udg-copy-build  ( -- bytes )
    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    _udg-instrument
    _udg-builder UDG-BUILDER-FINISH _udg-ok ;

: _udg-measure-build  ( -- bytes )
    0 0 _udg-builder UDG-BUILDER-INIT _udg-ok
    _udg-instrument
    _udg-builder UDG-BUILDER-FINISH _udg-ok ;

: _udg-records  ( -- )
    _udg-output UDG-FIRST-RECORD
    DUP _udg-r0 ! UDG-RECORD-NEXT
    DUP _udg-r1 ! UDG-RECORD-NEXT _udg-r2 ! ;

: _udg-basic-status  ( key row column -- status )
    1 1 0 0 0x01010101 0x02020202
    1 UDG-STATUS-CIRCLE _udg-builder UDG-STATUS ;

: _udg-length=  ( format decimals value scale unit-u expected -- )
    _udg-expected !
    UDG-READOUT-FORMATTED-BYTES? _udg-assert
    _udg-expected @ = _udg-assert ;

: _udg-length-invalid  ( format decimals value scale unit-u -- )
    UDG-READOUT-FORMATTED-BYTES?
    0= _udg-assert 0= _udg-assert ;

: _udg-expect-invalid  ( -- )
    _udg-summary UDG-SUMMARY-SIZE 0xA5 FILL
    _udg-output 536 _udg-summary UDG-ENTRY-VALIDATE
    UDG-S-INVALID = _udg-assert
    _udg-summary UDG-SUMMARY-SIZE 0 _udg-filled? _udg-assert ;

: _udg-expect-unsupported  ( -- )
    _udg-summary UDG-SUMMARY-SIZE 0xA5 FILL
    _udg-output 536 _udg-summary UDG-ENTRY-VALIDATE
    UDG-S-UNSUPPORTED = _udg-assert
    _udg-summary UDG-SUMMARY-SIZE 0 _udg-filled? _udg-assert ;

: _udg-expect-ok  ( -- )
    _udg-summary UDG-SUMMARY-SIZE 0xA5 FILL
    _udg-output 536 _udg-summary UDG-ENTRY-VALIDATE _udg-ok
    _udg-summary UDG-SUMMARY-ENTRY-BYTES@ 536 = _udg-assert
    _udg-summary UDG-SUMMARY-OBJECT-COUNT@ 3 = _udg-assert ;

: _udg-formatted-length-case  ( -- )
    UDG-RECORD-HEADER-SIZE 24 = _udg-assert
    0 UDG-READOUT-RECORD-BYTES 144 = _udg-assert
    2 UDG-READOUT-RECORD-BYTES 152 = _udg-assert
    -1 UDG-READOUT-RECORD-BYTES 0= _udg-assert
    UDG-READOUT-INTEGER 0 0 1 0 1 _udg-length=
    UDG-READOUT-INTEGER 0 0x7FFFFFFFFFFFFFFF 1 0 19 _udg-length=
    UDG-READOUT-INTEGER 0 0x8000000000000000 1 0 20 _udg-length=
    UDG-READOUT-FIXED 2 -12345 100 2 9 _udg-length=
    \ Exact half-way rounding carries 9.995 to the five-byte 10.00.
    UDG-READOUT-FIXED 2 9995 1000 0 5 _udg-length=
    UDG-READOUT-FIXED 2 -9995 1000 0 6 _udg-length=
    \ The sign survives when -0.001 rounds to the five-byte -0.00.
    UDG-READOUT-FIXED 2 -1 1000 0 5 _udg-length=
    UDG-READOUT-PERCENT 1 1 8 0 5 _udg-length=
    UDG-READOUT-PERCENT 0 0x7FFFFFFFFFFFFFFF 1 0 22 _udg-length=
    UDG-READOUT-PERCENT 0 0x8000000000000000 1 0 23 _udg-length=

    99 0 1 1 0 _udg-length-invalid
    UDG-READOUT-INTEGER 1 1 1 0 _udg-length-invalid
    UDG-READOUT-FIXED 2 1 0 0 _udg-length-invalid
    UDG-READOUT-FIXED 2 1 10 -1 _udg-length-invalid
    UDG-READOUT-FIXED 0xFFFFFFFF 1 10 0 _udg-length-invalid ;

: _udg-measure-case  ( -- )
    _udg-measure-build 536 = _udg-assert ;

: _udg-copy-case  ( -- )
    _udg-output 2048 0xA5 FILL
    _udg-copy-build 536 = _udg-assert
    _udg-records

    _udg-output UDG-ENTRY-BYTES@ 536 = _udg-assert
    _udg-output UDG-ENTRY-ABI@ UDG-ABI = _udg-assert
    _udg-output UDG-ROOT-KEY@ 100 = _udg-assert
    _udg-output UDG-ROOT-ROW@ 2 = _udg-assert
    _udg-output UDG-ROOT-COLUMN@ 3 = _udg-assert
    _udg-output UDG-ROOT-HEIGHT@ 10 = _udg-assert
    _udg-output UDG-ROOT-WIDTH@ 40 = _udg-assert
    _udg-output UDG-ROOT-STATE@
        UDG-STATE-VISIBLE UDG-STATE-ENABLED OR = _udg-assert
    _udg-output UDG-RECORD-COUNT@ 3 = _udg-assert
    _udg-output UDG-OBJECT-COUNT@ 3 = _udg-assert
    _udg-output UDG-SERIES-COUNT@ 0= _udg-assert
    _udg-output UDG-SAMPLE-SLOTS@ 0= _udg-assert
    _udg-output UDG-UTF8-BYTES@ 9 = _udg-assert
    _udg-output UDG-RESERVED-OFFSET + @ 0= _udg-assert
    _udg-r0 @ _udg-output 112 + = _udg-assert
    _udg-r1 @ _udg-output 264 + = _udg-assert
    _udg-r2 @ _udg-output 408 + = _udg-assert

    _udg-r0 @ UDG-RECORD-BYTES@ 152 = _udg-assert
    _udg-r0 @ UDG-RECORD-KIND@ UDG-K-READOUT = _udg-assert
    _udg-r0 @ UDG-RECORD-KEY@ 101 = _udg-assert
    _udg-r0 @ UDG-OBJECT-PARENT-KEY@ 0= _udg-assert
    _udg-r0 @ UDG-OBJECT-ROW@ -2 = _udg-assert
    _udg-r0 @ UDG-OBJECT-COLUMN@ -3 = _udg-assert
    _udg-r0 @ UDG-OBJECT-HEIGHT@ 1 = _udg-assert
    _udg-r0 @ UDG-OBJECT-WIDTH@ 12 = _udg-assert
    _udg-r0 @ UDG-OBJECT-Z@ -1 = _udg-assert
    _udg-r0 @ UDG-OBJECT-FLAGS@ UDG-OBJECT-VISIBLE = _udg-assert
    _udg-r0 @ UDG-READOUT-FG@ 0x11223344 = _udg-assert
    _udg-r0 @ UDG-READOUT-FG@ UDG-RGBA-RED@ 0x11 = _udg-assert
    _udg-r0 @ UDG-READOUT-FG@ UDG-RGBA-GREEN@ 0x22 = _udg-assert
    _udg-r0 @ UDG-READOUT-FG@ UDG-RGBA-BLUE@ 0x33 = _udg-assert
    _udg-r0 @ UDG-READOUT-FG@ UDG-RGBA-ALPHA@ 0x44 = _udg-assert
    _udg-r0 @ UDG-READOUT-BG@ 0x55667788 = _udg-assert
    _udg-r0 @ UDG-READOUT-FORMAT@ UDG-READOUT-FIXED = _udg-assert
    _udg-r0 @ UDG-READOUT-DECIMALS@ 2 = _udg-assert
    _udg-r0 @ UDG-READOUT-VALUE@ -12345 = _udg-assert
    _udg-r0 @ UDG-READOUT-SCALE@ 100 = _udg-assert
    _udg-r0 @ UDG-READOUT-UNIT-BYTES@ 2 = _udg-assert
    _udg-r0 @ UDG-READOUT-UNIT@ S" dB" COMPARE 0= _udg-assert
    _udg-r0 @ UDG-READOUT-RESERVED-OFFSET + @ 0= _udg-assert
    _udg-r0 @ UDG-READOUT-UNIT-OFFSET + 2 +
        6 0 _udg-filled? _udg-assert

    _udg-r1 @ UDG-RECORD-BYTES@ 144 = _udg-assert
    _udg-r1 @ UDG-RECORD-KIND@ UDG-K-METER = _udg-assert
    _udg-r1 @ UDG-RECORD-KEY@ 102 = _udg-assert
    _udg-r1 @ UDG-OBJECT-PARENT-KEY@ 0= _udg-assert
    _udg-r1 @ UDG-OBJECT-ROW@ 12 = _udg-assert
    _udg-r1 @ UDG-OBJECT-COLUMN@ 41 = _udg-assert
    _udg-r1 @ UDG-OBJECT-HEIGHT@ 2 = _udg-assert
    _udg-r1 @ UDG-OBJECT-WIDTH@ 20 = _udg-assert
    _udg-r1 @ UDG-OBJECT-Z@ 0= _udg-assert
    _udg-r1 @ UDG-OBJECT-FLAGS@ UDG-OBJECT-VISIBLE = _udg-assert
    _udg-r1 @ UDG-METER-FG@ 0x01020304 = _udg-assert
    _udg-r1 @ UDG-METER-BG@ 0xA0B0C0D0 = _udg-assert
    _udg-r1 @ UDG-METER-ORIENTATION@
        UDG-METER-HORIZONTAL = _udg-assert
    _udg-r1 @ UDG-METER-FLAGS@ UDG-METER-SHOW-VALUE = _udg-assert
    _udg-r1 @ UDG-METER-MINIMUM@ -20 = _udg-assert
    _udg-r1 @ UDG-METER-MAXIMUM@ 80 = _udg-assert
    _udg-r1 @ UDG-METER-VALUE@ 35 = _udg-assert
    _udg-r1 @ UDG-METER-RESERVED-OFFSET + @ 0= _udg-assert

    _udg-r2 @ UDG-RECORD-BYTES@ 128 = _udg-assert
    _udg-r2 @ UDG-RECORD-KIND@ UDG-K-STATUS = _udg-assert
    _udg-r2 @ UDG-RECORD-KEY@ 103 = _udg-assert
    _udg-r2 @ UDG-OBJECT-PARENT-KEY@ 0= _udg-assert
    _udg-r2 @ UDG-OBJECT-ROW@ 5 = _udg-assert
    _udg-r2 @ UDG-OBJECT-COLUMN@ 2 = _udg-assert
    _udg-r2 @ UDG-OBJECT-HEIGHT@ 1 = _udg-assert
    _udg-r2 @ UDG-OBJECT-WIDTH@ 2 = _udg-assert
    _udg-r2 @ UDG-OBJECT-Z@ 7 = _udg-assert
    _udg-r2 @ UDG-OBJECT-FLAGS@ 0= _udg-assert
    _udg-r2 @ UDG-STATUS-INACTIVE@ 0x11111111 = _udg-assert
    _udg-r2 @ UDG-STATUS-ACTIVE@ 0xEEEEEEEE = _udg-assert
    _udg-r2 @ UDG-STATUS-VALUE@ -1 = _udg-assert
    _udg-r2 @ UDG-STATUS-SHAPE@ UDG-STATUS-DIAMOND = _udg-assert
    _udg-r2 @ UDG-STATUS-FLAGS-OFFSET + @ 0= _udg-assert
    _udg-r2 @ UDG-STATUS-RESERVED-OFFSET + @ 0= _udg-assert
    _udg-r2 @ UDG-RECORD-NEXT _udg-output 536 + = _udg-assert
    _udg-output 536 + 16 0xA5 _udg-filled? _udg-assert

    _udg-summary UDG-SUMMARY-SIZE 0xA5 FILL
    _udg-output 536 _udg-summary UDG-ENTRY-VALIDATE _udg-ok
    _udg-summary UDG-SUMMARY-ENTRY-BYTES@ 536 = _udg-assert
    _udg-summary UDG-SUMMARY-ROOT-KEY@ 100 = _udg-assert
    _udg-summary UDG-SUMMARY-OBJECT-COUNT@ 3 = _udg-assert
    _udg-summary UDG-SUMMARY-SERIES-COUNT@ 0= _udg-assert
    _udg-summary UDG-SUMMARY-SAMPLE-SLOTS@ 0= _udg-assert
    _udg-summary UDG-SUMMARY-UTF8-BYTES@ 9 = _udg-assert ;

: _udg-empty-unit-case  ( -- )
    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    200 0 0 2 12 UDG-STATE-VISIBLE
        _udg-builder UDG-BEGIN _udg-ok
    201 0 0 1 12 0 UDG-OBJECT-VISIBLE
        0x01020304 0x05060708 UDG-READOUT-INTEGER 0 42 1
        0 0 _udg-builder UDG-READOUT _udg-ok
    _udg-builder UDG-END _udg-ok
    _udg-builder UDG-BUILDER-FINISH _udg-ok 256 = _udg-assert
    _udg-output UDG-UTF8-BYTES@ 2 = _udg-assert
    _udg-output UDG-FIRST-RECORD DUP _udg-r0 !
        UDG-READOUT-UNIT-BYTES@ 0= _udg-assert
    _udg-r0 @ UDG-READOUT-UNIT@
        DUP 0= _udg-assert DROP
        _udg-r0 @ UDG-READOUT-UNIT-OFFSET + = _udg-assert
    _udg-r0 @ UDG-RECORD-BYTES@ 144 = _udg-assert
    _udg-output 256 _udg-summary UDG-ENTRY-VALIDATE _udg-ok
    _udg-summary UDG-SUMMARY-OBJECT-COUNT@ 1 = _udg-assert
    _udg-summary UDG-SUMMARY-UTF8-BYTES@ 2 = _udg-assert ;

: _udg-capacity-case  ( -- )
    _udg-output 2048 0xA5 FILL
    _udg-output 535 _udg-builder UDG-BUILDER-INIT _udg-ok
    _udg-begin
    _udg-readout _udg-ok
    _udg-meter _udg-ok
    _udg-status UDG-S-CAPACITY = _udg-assert
    _udg-output 535 + C@ 0xA5 = _udg-assert
    _udg-builder UDG-BUILDER-INVALID
        UDG-S-CAPACITY = _udg-assert
    _udg-builder UDG-BUILDER-FINISH
        UDG-S-CAPACITY = _udg-assert 0= _udg-assert ;

: _udg-storage-case  ( -- )
    _udg-output 2048 UDG-STORAGE-DISJOINT? _udg-assert
    0 0 UDG-STORAGE-DISJOINT? _udg-assert
    _udg-output 0 UDG-STORAGE-DISJOINT? 0= _udg-assert
    0 8 UDG-STORAGE-DISJOINT? 0= _udg-assert
    _udg-output -1 UDG-STORAGE-DISJOINT? 0= _udg-assert
    -8 16 UDG-STORAGE-DISJOINT? 0= _udg-assert
    _UDG-OWNED-START 8 UDG-STORAGE-DISJOINT? 0= _udg-assert

    _udg-builder 512 _udg-builder UDG-BUILDER-INIT
        UDG-S-INVALID = _udg-assert
    _udg-output 1+ 512 _udg-builder UDG-BUILDER-INIT
        UDG-S-INVALID = _udg-assert
    _udg-output 512 _udg-builder 1+ UDG-BUILDER-INIT
        UDG-S-INVALID = _udg-assert

    \ A zero-length borrowed source is canonical only as 0 0.
    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    _udg-begin
    101 0 0 1 12 0 UDG-OBJECT-VISIBLE
        0x01020304 0x05060708 UDG-READOUT-INTEGER 0 42 1
        _udg-output 0 _udg-builder UDG-READOUT
        UDG-S-INVALID = _udg-assert

    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    _udg-begin
    101 0 0 1 12 0 UDG-OBJECT-VISIBLE
        0x01020304 0x05060708 UDG-READOUT-FIXED 1 1 10
        _udg-output 600 + 2 _udg-builder UDG-READOUT
        UDG-S-INVALID = _udg-assert
    _udg-builder UDG-BUILDER-INVALID
        UDG-S-INVALID = _udg-assert

    \ A source may not borrow mutable builder state even when its current byte
    \ happens to be valid unit text; reservation would change it before copy.
    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    _udg-begin
    101 0 0 1 12 0 UDG-OBJECT-VISIBLE
        0x01020304 0x05060708 UDG-READOUT-FIXED 1 1 10
        _udg-builder _UDG-B.USED + 1 _udg-builder UDG-READOUT
        UDG-S-INVALID = _udg-assert

    _udg-copy-build 536 = _udg-assert
    _udg-output 536 _udg-output 8 + UDG-ENTRY-VALIDATE
        UDG-S-INVALID = _udg-assert
    _udg-output UDG-ENTRY-BYTES@ 536 = _udg-assert ;

: _udg-builder-rejection-case  ( -- )
    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    100 0xFFFFFFFF 0 2 2 0 _udg-builder UDG-BEGIN
        UDG-S-INVALID = _udg-assert
    _udg-builder UDG-BUILDER-FINISH
        UDG-S-INVALID = _udg-assert 0= _udg-assert

    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    100 0 0 2 2 0 _udg-builder UDG-BEGIN _udg-ok
    101 2147483648 0 _udg-basic-status UDG-S-INVALID = _udg-assert

    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    100 0 0 2 2 0 _udg-builder UDG-BEGIN _udg-ok
    101 0 0 0 1 0 0 0x01010101 0x02020202
        1 UDG-STATUS-CIRCLE _udg-builder UDG-STATUS
        UDG-S-INVALID = _udg-assert

    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    100 0 0 4 8 0 _udg-builder UDG-BEGIN _udg-ok
    102 0 0 _udg-basic-status _udg-ok
    101 1 0 _udg-basic-status UDG-S-INVALID = _udg-assert

    _udg-output 2048 _udg-builder UDG-BUILDER-INIT _udg-ok
    100 0 0 4 8 0 _udg-builder UDG-BEGIN _udg-ok
    100 0 0 _udg-basic-status UDG-S-INVALID = _udg-assert ;

: _udg-unknown-record-case  ( -- )
    _udg-output 136 0 FILL
    136 _udg-output UDG-ENTRY-BYTES-OFFSET + !
    UDG-ABI _udg-output UDG-ENTRY-ABI-OFFSET + !
    100 _udg-output UDG-ROOT-KEY-OFFSET + !
    1 _udg-output UDG-ROOT-HEIGHT-OFFSET + !
    1 _udg-output UDG-ROOT-WIDTH-OFFSET + !
    1 _udg-output UDG-RECORD-COUNT-OFFSET + !
    1 _udg-output UDG-SERIES-COUNT-OFFSET + !
    UDG-RECORD-HEADER-SIZE
        _udg-output UDG-FIRST-RECORD UDG-RECORD-BYTES-OFFSET + !
    99 _udg-output UDG-FIRST-RECORD UDG-RECORD-KIND-OFFSET + !
    101 _udg-output UDG-FIRST-RECORD UDG-RECORD-KEY-OFFSET + !
    _udg-summary UDG-SUMMARY-SIZE 0xA5 FILL
    _udg-output 136 _udg-summary UDG-ENTRY-VALIDATE
        UDG-S-UNSUPPORTED = _udg-assert
    _udg-summary UDG-SUMMARY-SIZE 0 _udg-filled? _udg-assert ;

: _udg-corruption-case  ( -- )
    _udg-copy-build 536 = _udg-assert
    _udg-records

    2 _udg-output UDG-ENTRY-ABI-OFFSET + !
    _udg-expect-unsupported
    UDG-ABI _udg-output UDG-ENTRY-ABI-OFFSET + !

    1 _udg-output UDG-RESERVED-OFFSET + !
    _udg-expect-invalid
    0 _udg-output UDG-RESERVED-OFFSET + !

    \ Known object records cannot be relabelled as future series in header
    \ counts, and history slots cannot exist without a declared series.
    2 _udg-output UDG-OBJECT-COUNT-OFFSET + !
    1 _udg-output UDG-SERIES-COUNT-OFFSET + !
    _udg-expect-invalid
    3 _udg-output UDG-OBJECT-COUNT-OFFSET + !
    0 _udg-output UDG-SERIES-COUNT-OFFSET + !
    1 _udg-output UDG-SAMPLE-SLOTS-OFFSET + !
    _udg-expect-invalid
    0 _udg-output UDG-SAMPLE-SLOTS-OFFSET + !

    99 _udg-r0 @ UDG-RECORD-KIND-OFFSET + !
    _udg-expect-unsupported
    UDG-K-READOUT _udg-r0 @ UDG-RECORD-KIND-OFFSET + !
    1 _udg-r0 @ UDG-READOUT-RESERVED-OFFSET + !
    _udg-expect-invalid
    0 _udg-r0 @ UDG-READOUT-RESERVED-OFFSET + !
    1 _udg-r1 @ UDG-METER-RESERVED-OFFSET + !
    _udg-expect-invalid
    0 _udg-r1 @ UDG-METER-RESERVED-OFFSET + !
    1 _udg-r2 @ UDG-STATUS-FLAGS-OFFSET + !
    _udg-expect-invalid
    0 _udg-r2 @ UDG-STATUS-FLAGS-OFFSET + !
    1 _udg-r2 @ UDG-STATUS-RESERVED-OFFSET + !
    _udg-expect-invalid
    0 _udg-r2 @ UDG-STATUS-RESERVED-OFFSET + !

    0xFF _udg-r0 @ UDG-READOUT-UNIT-OFFSET + C!
    _udg-expect-invalid
    [CHAR] d _udg-r0 @ UDG-READOUT-UNIT-OFFSET + C!
    10 _udg-r0 @ UDG-READOUT-UNIT-OFFSET + C!
    _udg-expect-invalid
    [CHAR] d _udg-r0 @ UDG-READOUT-UNIT-OFFSET + C!
    1 _udg-r0 @ UDG-READOUT-UNIT-OFFSET + 2 + C!
    _udg-expect-invalid
    0 _udg-r0 @ UDG-READOUT-UNIT-OFFSET + 2 + C!
    10 _udg-output UDG-UTF8-BYTES-OFFSET + !
    _udg-expect-invalid
    9 _udg-output UDG-UTF8-BYTES-OFFSET + !

    99 _udg-r0 @ UDG-READOUT-FORMAT-OFFSET + !
    _udg-expect-invalid
    UDG-READOUT-FIXED _udg-r0 @ UDG-READOUT-FORMAT-OFFSET + !
    -1 _udg-r0 @ UDG-READOUT-DECIMALS-OFFSET + !
    _udg-expect-invalid
    2 _udg-r0 @ UDG-READOUT-DECIMALS-OFFSET + !
    0 _udg-r0 @ UDG-READOUT-SCALE-OFFSET + !
    _udg-expect-invalid
    100 _udg-r0 @ UDG-READOUT-SCALE-OFFSET + !
    UDG-READOUT-INTEGER _udg-r0 @ UDG-READOUT-FORMAT-OFFSET + !
    _udg-expect-invalid
    0 _udg-r0 @ UDG-READOUT-DECIMALS-OFFSET + !
    2 _udg-r0 @ UDG-READOUT-SCALE-OFFSET + !
    _udg-expect-invalid
    UDG-READOUT-FIXED _udg-r0 @ UDG-READOUT-FORMAT-OFFSET + !
    2 _udg-r0 @ UDG-READOUT-DECIMALS-OFFSET + !
    100 _udg-r0 @ UDG-READOUT-SCALE-OFFSET + !

    2 _udg-r1 @ UDG-METER-ORIENTATION-OFFSET + !
    _udg-expect-invalid
    UDG-METER-HORIZONTAL _udg-r1 @ UDG-METER-ORIENTATION-OFFSET + !
    2 _udg-r1 @ UDG-METER-FLAGS-OFFSET + !
    _udg-expect-invalid
    UDG-METER-SHOW-VALUE _udg-r1 @ UDG-METER-FLAGS-OFFSET + !
    80 _udg-r1 @ UDG-METER-MINIMUM-OFFSET + !
    _udg-expect-invalid
    -20 _udg-r1 @ UDG-METER-MINIMUM-OFFSET + !
    81 _udg-r1 @ UDG-METER-VALUE-OFFSET + !
    _udg-expect-invalid
    35 _udg-r1 @ UDG-METER-VALUE-OFFSET + !

    \ STATUS accepts the complete signed cell domain: only zero is inactive.
    2 _udg-r2 @ UDG-STATUS-VALUE-OFFSET + !
    _udg-expect-ok
    0 _udg-r2 @ UDG-STATUS-VALUE-OFFSET + !
    _udg-expect-ok
    0x8000000000000000 _udg-r2 @ UDG-STATUS-VALUE-OFFSET + !
    _udg-expect-ok
    0x7FFFFFFFFFFFFFFF _udg-r2 @ UDG-STATUS-VALUE-OFFSET + !
    _udg-expect-ok
    -1 _udg-r2 @ UDG-STATUS-VALUE-OFFSET + !
    3 _udg-r2 @ UDG-STATUS-SHAPE-OFFSET + !
    _udg-expect-invalid
    UDG-STATUS-DIAMOND _udg-r2 @ UDG-STATUS-SHAPE-OFFSET + !
    -1 _udg-r2 @ UDG-STATUS-INACTIVE-OFFSET + !
    _udg-expect-invalid
    0x11111111 _udg-r2 @ UDG-STATUS-INACTIVE-OFFSET + !

    2147483648 _udg-r0 @ UDG-OBJECT-ROW-OFFSET + !
    _udg-expect-invalid
    -2147483648 _udg-r0 @ UDG-OBJECT-ROW-OFFSET + !
    _udg-expect-ok
    -2 _udg-r0 @ UDG-OBJECT-ROW-OFFSET + !
    -2147483649 _udg-r0 @ UDG-OBJECT-COLUMN-OFFSET + !
    _udg-expect-invalid
    -3 _udg-r0 @ UDG-OBJECT-COLUMN-OFFSET + !
    1 _udg-r0 @ UDG-OBJECT-PARENT-KEY-OFFSET + !
    _udg-expect-invalid
    0 _udg-r0 @ UDG-OBJECT-PARENT-KEY-OFFSET + !
    2 _udg-r0 @ UDG-OBJECT-FLAGS-OFFSET + !
    _udg-expect-invalid
    UDG-OBJECT-VISIBLE _udg-r0 @ UDG-OBJECT-FLAGS-OFFSET + !
    2147483648 _udg-r0 @ UDG-OBJECT-Z-OFFSET + !
    _udg-expect-invalid
    -1 _udg-r0 @ UDG-OBJECT-Z-OFFSET + !
    101 _udg-r1 @ UDG-RECORD-KEY-OFFSET + !
    _udg-expect-invalid
    102 _udg-r1 @ UDG-RECORD-KEY-OFFSET + !
    100 _udg-r0 @ UDG-RECORD-KEY-OFFSET + !
    _udg-expect-invalid
    101 _udg-r0 @ UDG-RECORD-KEY-OFFSET + !

    _udg-summary UDG-SUMMARY-SIZE 0xA5 FILL
    _udg-output 536 _udg-summary UDG-ENTRY-VALIDATE _udg-ok
    _udg-summary UDG-SUMMARY-ENTRY-BYTES@ 536 = _udg-assert
    _udg-summary UDG-SUMMARY-OBJECT-COUNT@ 3 = _udg-assert
    _udg-summary UDG-SUMMARY-UTF8-BYTES@ 9 = _udg-assert ;

: _udg-run  ( -- )
    0 _udg-fails ! 0 _udg-checks ! DEPTH _udg-depth !
    _udg-formatted-length-case _udg-stack
    _udg-measure-case _udg-stack
    _udg-copy-case _udg-stack
    _udg-empty-unit-case _udg-stack
    _udg-capacity-case _udg-stack
    _udg-storage-case _udg-stack
    _udg-builder-rejection-case _udg-stack
    _udg-unknown-record-case _udg-stack
    _udg-corruption-case _udg-stack
    _udg-fails @ 0= IF
        ." UDG PASS " _udg-checks @ .
    ELSE
        ." UDG FAIL " _udg-fails @ . ." / " _udg-checks @ .
    THEN CR ;

_udg-run
'''


ORACLE_SOURCE = "\n\n".join(
    (ORACLE_STUBS.strip(), _MODULE_BODY.strip(), ORACLE_CASES.strip())
) + "\n"


AUTOEXEC = rf'''\ autoexec.f - neutral semantic data graphics byte oracle
ENTER-USERLAND
." [akashic] loading neutral semantic data graphics byte oracle" CR
REQUIRE utils/memory-span.f
REQUIRE text/utf8.f
REQUIRE {ORACLE_PATH}
'''


def test_semantic_data_graphics_byte_oracle(tmp_path: Path) -> None:
    assert _MODULE_TEXT.count(
        "PROVIDED akashic-tui-semantic-data-graphics"
    ) == 1
    assert "REQUIRE uidl-tui.f" not in _MODULE_TEXT
    assert "UTUI-" not in _MODULE_TEXT
    assert "UDG-READOUT" in _MODULE_BODY
    assert "UDG-METER" in _MODULE_BODY
    assert "UDG-STATUS" in _MODULE_BODY
    assert "UDG-ENTRY-VALIDATE" in _MODULE_BODY
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("utils/memory-span.f", "text/utf8.f"),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("UDG PASS",),
        stable_markers=("UDG PASS",),
        failure_markers=(
            "UDG FAIL",
            "UDG ASSERT",
            "UDG STACK",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(
            PROFILE_NAME,
            tmp_path / "semantic-data-graphics.img",
        )
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
        test_semantic_data_graphics_byte_oracle(Path(directory))
