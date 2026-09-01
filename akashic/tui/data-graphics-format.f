\ =====================================================================
\  data-graphics-format.f -- bounded canonical READOUT text
\ =====================================================================
\
\  This module is the one renderer-neutral spelling of an ABI-1 READOUT.
\  It measures through UDG-READOUT-FORMATTED-BYTES? and writes directly to
\  caller-owned storage only after every source, capacity, and alias check
\  has succeeded.  It allocates no representation and keeps no returned
\  text.  INTEGER, FIXED, and PERCENT use nearest rounding with ties away
\  from zero, retain an exact requested fractional width, preserve negative
\  rounded zero, and append UNIT without an implicit separator.
\
\  Public API:
\
\    DGF-READOUT-MEASURE  ( record -- bytes status )
\    DGF-READOUT-FORMAT   ( record destination capacity -- bytes status )
\    DGF-STORAGE-DISJOINT? ( address bytes -- flag )
\
\  FORMAT returns 0 and an explicit DGF-S-CAPACITY or DGF-S-INVALID on
\  failure.  The destination is unchanged on every failure.  A successful
\  result is not NUL terminated; BYTES is the exact written byte count.
\
\  Prefix: DGF- (public), _DGF- (private)
\ =====================================================================

PROVIDED akashic-tui-dgf-format

REQUIRE data-graphics-model.f

UDG-S-OK       CONSTANT DGF-S-OK
UDG-S-CAPACITY CONSTANT DGF-S-CAPACITY
UDG-S-INVALID  CONSTANT DGF-S-INVALID

CREATE _DGF-OWNED-START
VARIABLE _DGF-OWNED-LIMIT
0 _DGF-OWNED-LIMIT !

0x7FFFFFFFFFFFFFFF CONSTANT _DGF-SIGNED-MAX
0x8000000000000000 CONSTANT _DGF-SIGNED-MIN

: _DGF-U32?  ( value -- flag )
    DUP 0< IF DROP 0 EXIT THEN 0x100000000 U< ;

: _DGF-POS-U32?  ( value -- flag )
    DUP 0> SWAP _DGF-U32? AND ;

: _DGF-I32?  ( value -- flag )
    DUP -2147483648 >= SWAP 2147483647 <= AND ;

: DGF-STORAGE-DISJOINT?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _DGF-OWNED-LIMIT @ DUP _DGF-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _DGF-OWNED-START -
    _DGF-OWNED-START SWAP
    MSPAN-OVERLAP? 0= ;

\ These preflights do not mutate module storage.  That matters when an
\ adversarial caller points an input or destination at one of our variables:
\ rejection must happen before merely saving the public arguments changes it.
: _DGF-RECORD-SPAN?  ( record -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP UDG-READOUT-FIXED-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP UDG-READOUT-FIXED-SIZE DGF-STORAGE-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP UDG-READOUT-FIXED-SIZE UDG-STORAGE-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP UDG-RECORD-BYTES@
    DUP UDG-READOUT-FIXED-SIZE U< IF 2DROP 0 EXIT THEN
    DUP 7 AND IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    2DUP DGF-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UDG-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DROP -1 ;

: _DGF-OUTPUT-SPAN?  ( destination capacity -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    2DUP DGF-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UDG-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DROP -1 ;

: _DGF-ZERO-BYTES?  ( address bytes -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _DGF-UNIT-TEXT?  ( address bytes -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    2DUP UTF8-VALID? 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ DUP 32 U< SWAP 127 = OR IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

VARIABLE _DGF-M-RECORD
VARIABLE _DGF-M-RECORD-U
VARIABLE _DGF-M-RAW-U
VARIABLE _DGF-M-UNIT-U

: _DGF-MEASURE-CLEAR  ( -- )
    0 _DGF-M-RECORD ! 0 _DGF-M-RECORD-U !
    0 _DGF-M-RAW-U ! 0 _DGF-M-UNIT-U ! ;

: _DGF-M-OBJECT?  ( record -- flag )
    DUP UDG-RECORD-KEY@ 0= IF DROP 0 EXIT THEN
    DUP UDG-OBJECT-PARENT-KEY@ IF DROP 0 EXIT THEN
    DUP UDG-OBJECT-ROW@ _DGF-I32? 0= IF DROP 0 EXIT THEN
    DUP UDG-OBJECT-COLUMN@ _DGF-I32? 0= IF DROP 0 EXIT THEN
    DUP UDG-OBJECT-HEIGHT@ _DGF-POS-U32? 0= IF DROP 0 EXIT THEN
    DUP UDG-OBJECT-WIDTH@ _DGF-POS-U32? 0= IF DROP 0 EXIT THEN
    DUP UDG-OBJECT-Z@ _DGF-I32? 0= IF DROP 0 EXIT THEN
    DUP UDG-OBJECT-FLAGS@ UDG-OBJECT-VISIBLE INVERT AND IF
        DROP 0 EXIT
    THEN
    DROP -1 ;

: DGF-READOUT-MEASURE  ( record -- bytes status )
    DUP _DGF-RECORD-SPAN? 0= IF DROP 0 DGF-S-INVALID EXIT THEN
    _DGF-M-RECORD !
    _DGF-M-RECORD @ UDG-RECORD-BYTES@ _DGF-M-RECORD-U !
    _DGF-M-RECORD @ UDG-RECORD-KIND@ UDG-K-READOUT <> IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-RECORD @ _DGF-M-OBJECT? 0= IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-RECORD @ UDG-READOUT-FG@ _DGF-U32? 0=
    _DGF-M-RECORD @ UDG-READOUT-BG@ _DGF-U32? 0= OR IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-RECORD @ UDG-READOUT-RESERVED-OFFSET + @ IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-RECORD @ UDG-READOUT-UNIT-BYTES@ DUP _DGF-M-UNIT-U !
        _DGF-U32? 0= IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-UNIT-U @ UDG-READOUT-FIXED-SIZE + _DGF-M-RAW-U !
    _DGF-M-UNIT-U @ UDG-READOUT-RECORD-BYTES
        _DGF-M-RECORD-U @ <> IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-RECORD @ UDG-READOUT-UNIT@ _DGF-UNIT-TEXT? 0= IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-RECORD @ _DGF-M-RAW-U @ +
        _DGF-M-RECORD-U @ _DGF-M-RAW-U @ -
        _DGF-ZERO-BYTES? 0= IF
        DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    _DGF-M-RECORD @ UDG-READOUT-FORMAT@
    _DGF-M-RECORD @ UDG-READOUT-DECIMALS@
    _DGF-M-RECORD @ UDG-READOUT-VALUE@
    _DGF-M-RECORD @ UDG-READOUT-SCALE@
    _DGF-M-UNIT-U @ UDG-READOUT-FORMATTED-BYTES? 0= IF
        DROP DGF-S-INVALID _DGF-MEASURE-CLEAR 0 SWAP EXIT
    THEN
    DGF-S-OK _DGF-MEASURE-CLEAR ;

\ =====================================================================
\  Exact rational decomposition and output
\ =====================================================================

VARIABLE _DGF-F-RECORD
VARIABLE _DGF-F-DST
VARIABLE _DGF-F-CAP
VARIABLE _DGF-F-NEEDED
VARIABLE _DGF-F-FORMAT
VARIABLE _DGF-F-DECIMALS
VARIABLE _DGF-F-VALUE
VARIABLE _DGF-F-SCALE
VARIABLE _DGF-F-UNIT-A
VARIABLE _DGF-F-UNIT-U
VARIABLE _DGF-F-SIGN
VARIABLE _DGF-F-Q-LO
VARIABLE _DGF-F-Q-HI
VARIABLE _DGF-F-REM0
VARIABLE _DGF-F-REM
VARIABLE _DGF-F-CARRY
VARIABLE _DGF-F-INT-DIGITS
VARIABLE _DGF-F-CURSOR
VARIABLE _DGF-F-FRAC-START
VARIABLE _DGF-F-FRAC-END

VARIABLE _DGF-T-QUOT
VARIABLE _DGF-T-REM
VARIABLE _DGF-T-PROD-LO
VARIABLE _DGF-T-PROD-HI
VARIABLE _DGF-T-EXTRA
VARIABLE _DGF-T-POW10
VARIABLE _DGF-T-GAP
VARIABLE _DGF-T-Q-LO
VARIABLE _DGF-T-Q-HI
VARIABLE _DGF-T-DIV-LO
VARIABLE _DGF-T-DIV-QLO
VARIABLE _DGF-T-DIV-REM
VARIABLE _DGF-T-DIGIT
VARIABLE _DGF-T-PTR
VARIABLE _DGF-T-I

: _DGF-MAGNITUDE/MOD  ( value positive-scale -- remainder quotient )
    _DGF-F-SCALE !
    DUP 0< IF
        DUP _DGF-SIGNED-MIN = IF
            DROP _DGF-SIGNED-MAX _DGF-F-SCALE @ /MOD
            _DGF-T-QUOT ! 1+ DUP _DGF-F-SCALE @ = IF
                DROP 0 _DGF-T-REM !
                _DGF-T-QUOT @ 1+ _DGF-T-QUOT !
            ELSE
                _DGF-T-REM !
            THEN
            _DGF-T-REM @ _DGF-T-QUOT @ EXIT
        THEN
        NEGATE
    THEN
    _DGF-F-SCALE @ /MOD ;

: _DGF-PRODUCT>=SCALE?  ( -- flag )
    _DGF-T-PROD-HI @ IF -1 EXIT THEN
    _DGF-T-PROD-LO @ _DGF-F-SCALE @ U< 0= ;

: _DGF-PRODUCT-SCALE-  ( -- )
    _DGF-T-PROD-LO @ _DGF-F-SCALE @ U< IF
        -1 _DGF-T-PROD-HI +!
    THEN
    _DGF-T-PROD-LO @ _DGF-F-SCALE @ - _DGF-T-PROD-LO ! ;

: _DGF-Q+  ( u -- )
    _DGF-F-Q-LO @ OVER + DUP _DGF-F-Q-LO @ U< IF
        1 _DGF-F-Q-HI +!
    THEN
    _DGF-F-Q-LO ! DROP ;

: _DGF-DECOMPOSE  ( -- )
    _DGF-F-VALUE @ _DGF-F-SCALE @ _DGF-MAGNITUDE/MOD
    _DGF-F-Q-LO ! _DGF-F-REM0 !
    0 _DGF-F-Q-HI !
    _DGF-F-FORMAT @ UDG-READOUT-PERCENT = IF
        _DGF-F-Q-LO @ 100 UM*
        _DGF-F-Q-HI ! _DGF-F-Q-LO !
        _DGF-F-REM0 @ 100 UM*
        _DGF-T-PROD-HI ! _DGF-T-PROD-LO !
        0 _DGF-T-EXTRA !
        BEGIN _DGF-PRODUCT>=SCALE? WHILE
            _DGF-PRODUCT-SCALE-
            1 _DGF-T-EXTRA +!
        REPEAT
        _DGF-T-PROD-LO @ _DGF-F-REM0 !
        _DGF-T-EXTRA @ _DGF-Q+
    THEN ;

\ A carry into the integer part is possible only through nineteen decimal
\ places because SCALE is at most signed-i64 max.  This is the exact test
\ (scale - remainder) * 10^decimals <= scale/2, evaluated as a double-cell
\ product so 10^19 and the full remainder domain remain safe.
: _DGF-INTEGER-CARRY?  ( -- flag )
    _DGF-F-REM0 @ 0= IF 0 EXIT THEN
    _DGF-F-DECIMALS @ 19 U> IF 0 EXIT THEN
    1 _DGF-T-POW10 !
    _DGF-F-DECIMALS @ 0 ?DO
        _DGF-T-POW10 @ 10 * _DGF-T-POW10 !
    LOOP
    _DGF-F-SCALE @ _DGF-F-REM0 @ - _DGF-T-GAP !
    _DGF-T-GAP @ _DGF-T-POW10 @ UM*
    DUP IF 2DROP 0 EXIT THEN DROP
    _DGF-F-SCALE @ 2/ U> 0= ;

\ Divide the unsigned double cell in _DGF-T-Q-HI/_DGF-T-Q-LO by ten.
\ The high half of a READOUT percent is small, but the bitwise low-half
\ division deliberately does not depend on that incidental bound.
: _DGF-Q/10  ( -- remainder )
    _DGF-T-Q-LO @ _DGF-T-DIV-LO !
    _DGF-T-Q-HI @ 10 /MOD
    _DGF-T-Q-HI ! _DGF-T-DIV-REM !
    0 _DGF-T-DIV-QLO !
    64 0 DO
        _DGF-T-DIV-QLO @ 1 LSHIFT _DGF-T-DIV-QLO !
        _DGF-T-DIV-REM @ 1 LSHIFT
        _DGF-T-DIV-LO @ 63 I - RSHIFT 1 AND OR
        DUP 10 U< IF
            _DGF-T-DIV-REM !
        ELSE
            10 - _DGF-T-DIV-REM !
            _DGF-T-DIV-QLO @ 1 OR _DGF-T-DIV-QLO !
        THEN
    LOOP
    _DGF-T-DIV-QLO @ _DGF-T-Q-LO !
    _DGF-T-DIV-REM @ ;

: _DGF-WRITE-INTEGER  ( -- )
    _DGF-F-Q-LO @ _DGF-T-Q-LO !
    _DGF-F-Q-HI @ _DGF-T-Q-HI !
    _DGF-F-CURSOR @ _DGF-F-INT-DIGITS @ + _DGF-T-PTR !
    _DGF-F-INT-DIGITS @ 0 ?DO
        _DGF-Q/10 [CHAR] 0 +
        -1 _DGF-T-PTR +! _DGF-T-PTR @ C!
    LOOP
    _DGF-F-INT-DIGITS @ _DGF-F-CURSOR +! ;

\ Advance one base-ten fractional digit without overflowing remainder*10.
\ At most nine subtractions are possible because remainder is below SCALE.
: _DGF-NEXT-FRACTION  ( -- digit )
    _DGF-F-REM @ 10 UM*
    _DGF-T-PROD-HI ! _DGF-T-PROD-LO !
    0 _DGF-T-DIGIT !
    BEGIN _DGF-PRODUCT>=SCALE? WHILE
        _DGF-PRODUCT-SCALE-
        1 _DGF-T-DIGIT +!
    REPEAT
    _DGF-T-PROD-LO @ _DGF-F-REM !
    _DGF-T-DIGIT @ ;

: _DGF-ROUND-UP?  ( -- flag )
    _DGF-F-SCALE @ 2/
    _DGF-F-SCALE @ 1 AND +
    _DGF-F-REM @ SWAP U< 0= ;

: _DGF-ROUND-FRACTION  ( -- )
    _DGF-F-DECIMALS @ _DGF-T-I !
    _DGF-F-FRAC-END @ _DGF-T-PTR !
    BEGIN _DGF-T-I @ WHILE
        -1 _DGF-T-PTR +!
        _DGF-T-PTR @ C@ [CHAR] 9 = IF
            [CHAR] 0 _DGF-T-PTR @ C!
            -1 _DGF-T-I +!
        ELSE
            _DGF-T-PTR @ DUP C@ 1+ SWAP C!
            0 _DGF-T-I !
        THEN
    REPEAT ;

: _DGF-WRITE-FRACTION  ( -- )
    _DGF-F-DECIMALS @ 0= IF EXIT THEN
    [CHAR] . _DGF-F-CURSOR @ C! 1 _DGF-F-CURSOR +!
    _DGF-F-CURSOR @ _DGF-F-FRAC-START !
    _DGF-F-CARRY @ IF
        _DGF-F-CURSOR @ _DGF-F-DECIMALS @ [CHAR] 0 FILL
        _DGF-F-DECIMALS @ _DGF-F-CURSOR +!
        _DGF-F-CURSOR @ _DGF-F-FRAC-END !
        EXIT
    THEN
    _DGF-F-REM0 @ _DGF-F-REM !
    _DGF-F-DECIMALS @ 0 ?DO
        _DGF-NEXT-FRACTION [CHAR] 0 +
        _DGF-F-CURSOR @ C! 1 _DGF-F-CURSOR +!
    LOOP
    _DGF-F-CURSOR @ _DGF-F-FRAC-END !
    _DGF-ROUND-UP? IF _DGF-ROUND-FRACTION THEN ;

: _DGF-FORMAT-PREPARE  ( -- )
    _DGF-F-RECORD @ UDG-READOUT-FORMAT@ _DGF-F-FORMAT !
    _DGF-F-RECORD @ UDG-READOUT-DECIMALS@ _DGF-F-DECIMALS !
    _DGF-F-RECORD @ UDG-READOUT-VALUE@ DUP _DGF-F-VALUE !
        0< _DGF-F-SIGN !
    _DGF-F-RECORD @ UDG-READOUT-SCALE@ _DGF-F-SCALE !
    _DGF-F-RECORD @ UDG-READOUT-UNIT@
        _DGF-F-UNIT-U ! _DGF-F-UNIT-A !
    _DGF-DECOMPOSE
    _DGF-INTEGER-CARRY? DUP _DGF-F-CARRY ! IF 1 _DGF-Q+ THEN
    _DGF-F-NEEDED @ _DGF-F-UNIT-U @ -
    _DGF-F-FORMAT @ UDG-READOUT-PERCENT = IF 1- THEN
    _DGF-F-DECIMALS @ IF
        _DGF-F-DECIMALS @ - 1-
    THEN
    _DGF-F-SIGN @ IF 1- THEN
    _DGF-F-INT-DIGITS ! ;

: _DGF-FORMAT-WRITE  ( -- )
    _DGF-F-DST @ _DGF-F-CURSOR !
    _DGF-F-SIGN @ IF
        [CHAR] - _DGF-F-CURSOR @ C! 1 _DGF-F-CURSOR +!
    THEN
    _DGF-WRITE-INTEGER
    _DGF-WRITE-FRACTION
    _DGF-F-FORMAT @ UDG-READOUT-PERCENT = IF
        [CHAR] % _DGF-F-CURSOR @ C! 1 _DGF-F-CURSOR +!
    THEN
    _DGF-F-UNIT-A @ _DGF-F-CURSOR @ _DGF-F-UNIT-U @ MOVE ;

: _DGF-FORMAT-CLEAR  ( -- )
    0 _DGF-F-RECORD ! 0 _DGF-F-DST ! 0 _DGF-F-CAP !
    0 _DGF-F-NEEDED ! 0 _DGF-F-FORMAT ! 0 _DGF-F-DECIMALS !
    0 _DGF-F-VALUE ! 0 _DGF-F-SCALE ! 0 _DGF-F-UNIT-A !
    0 _DGF-F-UNIT-U ! 0 _DGF-F-SIGN ! 0 _DGF-F-Q-LO !
    0 _DGF-F-Q-HI ! 0 _DGF-F-REM0 ! 0 _DGF-F-REM !
    0 _DGF-F-CARRY ! 0 _DGF-F-INT-DIGITS ! 0 _DGF-F-CURSOR !
    0 _DGF-F-FRAC-START ! 0 _DGF-F-FRAC-END ! ;

: DGF-READOUT-FORMAT  ( record destination capacity -- bytes status )
    2DUP _DGF-OUTPUT-SPAN? 0= IF 2DROP DROP 0 DGF-S-INVALID EXIT THEN
    _DGF-F-CAP ! _DGF-F-DST ! _DGF-F-RECORD !
    _DGF-F-RECORD @ DGF-READOUT-MEASURE
    DUP DGF-S-OK <> IF
        >R DROP _DGF-FORMAT-CLEAR 0 R> EXIT
    THEN
    DROP _DGF-F-NEEDED !
    _DGF-F-NEEDED @ _DGF-F-CAP @ U> IF
        _DGF-FORMAT-CLEAR 0 DGF-S-CAPACITY EXIT
    THEN
    _DGF-F-RECORD @ DUP UDG-RECORD-BYTES@
        _DGF-F-DST @ _DGF-F-CAP @ MSPAN-OVERLAP? IF
        _DGF-FORMAT-CLEAR 0 DGF-S-INVALID EXIT
    THEN
    _DGF-FORMAT-PREPARE
    _DGF-FORMAT-WRITE
    _DGF-F-NEEDED @ DGF-S-OK
    _DGF-FORMAT-CLEAR ;

HERE _DGF-OWNED-LIMIT !
