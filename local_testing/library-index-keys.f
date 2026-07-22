\ Library-owned ordered-key contracts.

PROVIDED akashic-library-index-key-contracts

VARIABLE _LIK-fails
VARIABLE _LIK-checks
VARIABLE _LIK-depth

CREATE _LIK-rid-a RID-SIZE ALLOT
CREATE _LIK-rid-b RID-SIZE ALLOT
CREATE _LIK-rid-c RID-SIZE ALLOT
CREATE _LIK-key-a LIBPI-TITLE-KEY-SIZE ALLOT
CREATE _LIK-key-b LIBPI-TITLE-KEY-SIZE ALLOT
CREATE _LIK-title-a-nul 2 ALLOT
CREATE _LIK-title-a-one 2 ALLOT
CREATE _LIK-title-a-nul-b 3 ALLOT

: _LIK-assert  ( flag -- )
    1 _LIK-checks +!
    0= IF 1 _LIK-fails +! ." LIBRARY INDEX KEY ASSERT " _LIK-checks @ . CR THEN ;

: _LIK-stack  ( -- )
    DEPTH DUP _LIK-depth @ <> IF
        ." LIBRARY INDEX KEY STACK " _LIK-depth @ . ."  -> " DUP . CR .S CR
    THEN
    _LIK-depth @ = _LIK-assert ;

: _LIK-status  ( actual expected -- )
    2DUP <> IF ." LIBRARY INDEX KEY STATUS actual/expected " 2DUP . . CR THEN
    = _LIK-assert _LIK-stack ;

: _LIK-setup  ( -- )
    _LIK-rid-a RID-SIZE 17 FILL
    _LIK-rid-b RID-SIZE 34 FILL
    _LIK-rid-c RID-SIZE 51 FILL
    _LIK-key-a LIBPI-TITLE-KEY-SIZE 0 FILL
    _LIK-key-b LIBPI-TITLE-KEY-SIZE 0 FILL
    65 _LIK-title-a-nul C! 0 _LIK-title-a-nul 1+ C!
    65 _LIK-title-a-one C! 1 _LIK-title-a-one 1+ C!
    65 _LIK-title-a-nul-b C! 0 _LIK-title-a-nul-b 1+ C!
    66 _LIK-title-a-nul-b 2 + C! ;

: _LIK-rid-and-order  ( -- )
    _LIK-rid-a _LIK-key-a LIBPI-RID-KEY LIB-S-OK _LIK-status
    _LIK-key-a RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert

    1 _LIK-rid-b _LIK-key-a LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    2 _LIK-rid-a _LIK-key-b LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-ORDER-KEY-SIZE
    _LIK-key-b LIBPI-ORDER-KEY-SIZE COMPARE 0< _LIK-assert

    2 _LIK-rid-a _LIK-key-a LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    2 _LIK-rid-b _LIK-key-b LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-ORDER-KEY-SIZE
    _LIK-key-b LIBPI-ORDER-KEY-SIZE COMPARE 0< _LIK-assert
    0 _LIK-rid-a _LIK-key-a LIBPI-ORDER-KEY LIB-S-INVALID _LIK-status ;

: _LIK-title  ( -- )
    LIBPI-TITLE-KEY-SIZE 178 = _LIK-assert
    S" Alpha" _LIK-rid-a _LIK-key-a LIBPI-TITLE-KEY LIB-S-OK _LIK-status
    S" Alphb" _LIK-rid-a _LIK-key-b LIBPI-TITLE-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TITLE-KEY-SIZE
    _LIK-key-b LIBPI-TITLE-KEY-SIZE COMPARE 0< _LIK-assert

    S" Alpha" _LIK-rid-b _LIK-key-b LIBPI-TITLE-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TITLE-KEY-SIZE
    _LIK-key-b LIBPI-TITLE-KEY-SIZE COMPARE 0< _LIK-assert

    \ U+0000 is valid in the current Library text model.  The title key must
    \ therefore retain it, distinguish it from end-of-title, and preserve
    \ prefix/next-byte ordering rather than narrowing Library functionality.
    _LIK-title-a-nul 2 UTF8-VALID? _LIK-assert
    S" A" _LIK-rid-a _LIK-key-a LIBPI-TITLE-KEY LIB-S-OK _LIK-status
    _LIK-title-a-nul 2 _LIK-rid-a _LIK-key-b LIBPI-TITLE-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TITLE-KEY-SIZE
    _LIK-key-b LIBPI-TITLE-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul 2 _LIK-rid-a _LIK-key-a LIBPI-TITLE-KEY
        LIB-S-OK _LIK-status
    _LIK-title-a-one 2 _LIK-rid-a _LIK-key-b LIBPI-TITLE-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TITLE-KEY-SIZE
    _LIK-key-b LIBPI-TITLE-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul-b 3 _LIK-rid-a _LIK-key-b LIBPI-TITLE-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TITLE-KEY-SIZE
    _LIK-key-b LIBPI-TITLE-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-key-a LIBPI-TITLE-KEY-SIZE _LIK-rid-a _LIK-key-a
        LIBPI-TITLE-KEY LIB-S-INVALID _LIK-status
    0 0 _LIK-rid-a _LIK-key-a LIBPI-TITLE-KEY LIB-S-INVALID _LIK-status ;

: _LIK-edge  ( -- )
    _LIK-rid-a _LIK-rid-b _LIK-key-a LIBPI-EDGE-KEY LIB-S-OK _LIK-status
    _LIK-rid-a _LIK-rid-c _LIK-key-b LIBPI-EDGE-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-EDGE-KEY-SIZE
    _LIK-key-b LIBPI-EDGE-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-key-a RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert
    _LIK-key-a RID-SIZE + RID-SIZE
    _LIK-rid-b RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a _LIK-key-b LIBPI-EDGE-PREFIX LIB-S-OK _LIK-status
    _LIK-key-b RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert ;

: _LIK-history  ( -- )
    _LIK-rid-a 1 _LIK-key-a LIBPI-HISTORY-KEY LIB-S-OK _LIK-status
    _LIK-rid-a 2 _LIK-key-b LIBPI-HISTORY-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-HISTORY-KEY-SIZE
    _LIK-key-b LIBPI-HISTORY-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-key-a RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a 0 _LIK-key-a LIBPI-HISTORY-KEY LIB-S-INVALID _LIK-status ;

: _LIK-RUN  ( -- )
    0 _LIK-fails ! 0 _LIK-checks ! DEPTH _LIK-depth !
    _LIK-setup
    _LIK-rid-and-order
    _LIK-title
    _LIK-edge
    _LIK-history
    _LIK-stack
    _LIK-fails @ 0= IF
        ." LIBRARY INDEX KEYS PASS " _LIK-checks @ .
    ELSE
        ." LIBRARY INDEX KEYS FAIL " _LIK-fails @ . ." / " _LIK-checks @ .
    THEN CR ;
