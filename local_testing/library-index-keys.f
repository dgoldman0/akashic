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
CREATE _LIK-body-4 4 ALLOT

: _LIK-assert  ( flag -- )
    1 _LIK-checks +!
    0= IF 1 _LIK-fails +! ." LIBRARY INDEX KEY ASSERT " _LIK-checks @ . CR THEN ;

: _LIK-stack  ( -- )
    DEPTH DUP _LIK-depth @ <> IF
        ." LIBRARY INDEX KEY STACK " _LIK-depth @ . ."  -> " DUP . CR .S CR
    THEN
    _LIK-depth @ = _LIK-assert ;

: _LIK-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY INDEX KEY STATUS actual/expected " 2DUP SWAP . . CR
    THEN
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
    66 _LIK-title-a-nul-b 2 + C!
    65 _LIK-body-4 C! 0 _LIK-body-4 1+ C!
    66 _LIK-body-4 2 + C! 67 _LIK-body-4 3 + C! ;

: _LIK-key-limits  ( -- )
    LIBPI-KEY-MAX 256 = _LIK-assert
    0 LIBPI-KEY-SIZE? 0= _LIK-assert
    1 LIBPI-KEY-SIZE? _LIK-assert
    256 LIBPI-KEY-SIZE? _LIK-assert
    257 LIBPI-KEY-SIZE? 0= _LIK-assert
    LIBPI-RID-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-OPERATION-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-ORDER-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-RECENCY-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-TITLE-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-TAG-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-BODY-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-EDGE-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-MEMBERSHIP-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-HISTORY-DOMAIN-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-STATE-ORDER-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-COLLECTION-TITLE-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-DIRECTORY-KEY-SIZE LIBPI-KEY-SIZE? _LIK-assert
    LIBPI-TAG-PREFIX-SIZE 29 = _LIK-assert
    LIBPI-TAG-ORDER-PREFIX-SIZE 37 = _LIK-assert
    LIBPI-TAG-KEY-SIZE 69 = _LIK-assert
    LIBPI-BODY-PREFIX-SIZE 5 = _LIK-assert
    LIBPI-BODY-ORDER-PREFIX-SIZE 13 = _LIK-assert
    LIBPI-BODY-KEY-SIZE 45 = _LIK-assert
    LIBPI-STATE-ORDER-KEY-SIZE 43 = _LIK-assert
    LIBPI-COLLECTION-TITLE-PREFIX-SIZE 74 = _LIK-assert
    LIBPI-COLLECTION-TITLE-KEY-SIZE 106 = _LIK-assert
    LIBPI-DIRECTORY-KEY-SIZE 33 = _LIK-assert ;

: _LIK-rid-and-order  ( -- )
    _LIK-rid-a _LIK-key-a LIBPI-RID-KEY LIB-S-OK _LIK-status
    _LIK-key-a RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a _LIK-key-b LIBPI-OPERATION-KEY LIB-S-OK _LIK-status
    _LIK-key-a RID-SIZE _LIK-key-b RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a _LIK-rid-a LIBPI-RID-KEY LIB-S-INVALID _LIK-status
    _LIK-rid-a 0 LIBPI-OPERATION-KEY LIB-S-INVALID _LIK-status

    1 _LIK-rid-b _LIK-key-a LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    2 _LIK-rid-a _LIK-key-b LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-ORDER-KEY-SIZE
    _LIK-key-b LIBPI-ORDER-KEY-SIZE COMPARE 0< _LIK-assert

    2 _LIK-rid-a _LIK-key-a LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    2 _LIK-rid-b _LIK-key-b LIBPI-ORDER-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-ORDER-KEY-SIZE
    _LIK-key-b LIBPI-ORDER-KEY-SIZE COMPARE 0< _LIK-assert
    0 _LIK-rid-a _LIK-key-a LIBPI-ORDER-KEY LIB-S-INVALID _LIK-status

    7 _LIK-rid-a _LIK-key-a LIBPI-RECENCY-KEY LIB-S-OK _LIK-status
    7 _LIK-key-b LIBPI-RECENCY-PREFIX LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-RECENCY-PREFIX-SIZE
    _LIK-key-b LIBPI-RECENCY-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    8 _LIK-rid-a _LIK-key-b LIBPI-RECENCY-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-RECENCY-KEY-SIZE
    _LIK-key-b LIBPI-RECENCY-KEY-SIZE COMPARE 0< _LIK-assert ;

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
    0 0 _LIK-rid-a _LIK-key-a LIBPI-TITLE-KEY LIB-S-INVALID _LIK-status
    _LIK-title-a-nul 2 _LIK-key-a LIBPI-TITLE-PREFIX
        LIB-S-OK _LIK-status
    _LIK-title-a-nul 2 _LIK-rid-a _LIK-key-b LIBPI-TITLE-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TITLE-PREFIX-SIZE
    _LIK-key-b LIBPI-TITLE-PREFIX-SIZE
        COMPARE 0= _LIK-assert ;

: _LIK-tag-and-body  ( -- )
    _LIK-title-a-nul 2 7 _LIK-rid-a _LIK-key-a LIBPI-TAG-KEY
        LIB-S-OK _LIK-status
    _LIK-title-a-one 2 7 _LIK-rid-a _LIK-key-b LIBPI-TAG-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TAG-KEY-SIZE
    _LIK-key-b LIBPI-TAG-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul 2 _LIK-key-b LIBPI-TAG-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TAG-PREFIX-SIZE
    _LIK-key-b LIBPI-TAG-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    _LIK-title-a-nul 2 8 _LIK-rid-a _LIK-key-b LIBPI-TAG-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TAG-KEY-SIZE
    _LIK-key-b LIBPI-TAG-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul 2 7 _LIK-rid-b _LIK-key-b LIBPI-TAG-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TAG-KEY-SIZE
    _LIK-key-b LIBPI-TAG-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul 2 7 _LIK-key-b LIBPI-TAG-ORDER-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-TAG-ORDER-PREFIX-SIZE
    _LIK-key-b LIBPI-TAG-ORDER-PREFIX-SIZE COMPARE 0= _LIK-assert
    0 0 7 _LIK-rid-a _LIK-key-a LIBPI-TAG-KEY
        LIB-S-INVALID _LIK-status
    _LIK-key-a 2 7 _LIK-rid-a _LIK-key-a LIBPI-TAG-KEY
        LIB-S-INVALID _LIK-status

    S" A" 7 _LIK-rid-a _LIK-key-a LIBPI-BODY-KEY LIB-S-OK _LIK-status
    _LIK-title-a-nul 2 7 _LIK-rid-a _LIK-key-b LIBPI-BODY-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-BODY-KEY-SIZE
    _LIK-key-b LIBPI-BODY-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul 2 _LIK-key-a LIBPI-BODY-PREFIX
        LIB-S-OK _LIK-status
    _LIK-title-a-nul 2 8 _LIK-rid-a _LIK-key-b LIBPI-BODY-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-BODY-KEY-SIZE
    _LIK-key-b LIBPI-BODY-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul 2 7 _LIK-rid-b _LIK-key-b LIBPI-BODY-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-BODY-PREFIX-SIZE
    _LIK-key-b LIBPI-BODY-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    _LIK-title-a-nul 2 7 _LIK-key-b LIBPI-BODY-ORDER-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-BODY-ORDER-PREFIX-SIZE
    _LIK-key-b LIBPI-BODY-ORDER-PREFIX-SIZE COMPARE 0= _LIK-assert
    _LIK-title-a-nul-b 3 7 _LIK-rid-a _LIK-key-a LIBPI-BODY-KEY
        LIB-S-OK _LIK-status
    _LIK-body-4 4 7 _LIK-rid-a _LIK-key-a LIBPI-BODY-KEY
        LIB-S-INVALID _LIK-status
    0 0 7 _LIK-rid-a _LIK-key-a LIBPI-BODY-KEY
        LIB-S-INVALID _LIK-status
    _LIK-key-a 2 7 _LIK-rid-a _LIK-key-a LIBPI-BODY-KEY
        LIB-S-INVALID _LIK-status ;

: _LIK-state  ( -- )
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT
        LIB-MEDIA-TEXT-PLAIN 7 _LIK-rid-a _LIK-key-a
        LIBPI-STATE-ORDER-KEY LIB-S-OK _LIK-status
    LIB-LIFECYCLE-ACTIVE _LIK-key-b LIBPI-STATE-LIFECYCLE-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-STATE-LIFECYCLE-PREFIX-SIZE
    _LIK-key-b LIBPI-STATE-LIFECYCLE-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT _LIK-key-b
        LIBPI-STATE-KIND-PREFIX LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-STATE-KIND-PREFIX-SIZE
    _LIK-key-b LIBPI-STATE-KIND-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT
        LIB-MEDIA-TEXT-PLAIN _LIK-key-b LIBPI-STATE-MEDIA-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-STATE-MEDIA-PREFIX-SIZE
    _LIK-key-b LIBPI-STATE-MEDIA-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT
        LIB-MEDIA-TEXT-PLAIN 7 _LIK-key-b
        LIBPI-STATE-MUTATION-PREFIX LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-STATE-MUTATION-PREFIX-SIZE
    _LIK-key-b LIBPI-STATE-MUTATION-PREFIX-SIZE
        COMPARE 0= _LIK-assert

    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT
        LIB-MEDIA-TEXT-PLAIN 8 _LIK-rid-a _LIK-key-b
        LIBPI-STATE-ORDER-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-STATE-ORDER-KEY-SIZE
    _LIK-key-b LIBPI-STATE-ORDER-KEY-SIZE COMPARE 0< _LIK-assert
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT
        LIB-MEDIA-TEXT-PLAIN 7 _LIK-rid-b _LIK-key-b
        LIBPI-STATE-ORDER-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-STATE-ORDER-KEY-SIZE
    _LIK-key-b LIBPI-STATE-ORDER-KEY-SIZE COMPARE 0< _LIK-assert

    0 LIB-KIND-MANAGED-DOCUMENT LIB-MEDIA-TEXT-PLAIN 1
        _LIK-rid-a _LIK-key-a LIBPI-STATE-ORDER-KEY
        LIB-S-INVALID _LIK-status
    LIB-LIFECYCLE-ACTIVE 0 LIB-MEDIA-TEXT-PLAIN 1
        _LIK-rid-a _LIK-key-a LIBPI-STATE-ORDER-KEY
        LIB-S-INVALID _LIK-status
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT 99 1
        _LIK-rid-a _LIK-key-a LIBPI-STATE-ORDER-KEY
        LIB-S-INVALID _LIK-status
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT
        LIB-MEDIA-TEXT-PLAIN 0 _LIK-rid-a _LIK-key-a
        LIBPI-STATE-ORDER-KEY LIB-S-INVALID _LIK-status
    LIB-LIFECYCLE-ACTIVE LIB-KIND-MANAGED-DOCUMENT
        LIB-MEDIA-TEXT-PLAIN 1 _LIK-key-a _LIK-key-a
        LIBPI-STATE-ORDER-KEY LIB-S-INVALID _LIK-status ;

: _LIK-edge  ( -- )
    _LIK-rid-a _LIK-rid-b _LIK-key-a LIBPI-EDGE-KEY LIB-S-OK _LIK-status
    _LIK-rid-a _LIK-rid-c _LIK-key-b LIBPI-EDGE-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-EDGE-KEY-SIZE
    _LIK-key-b LIBPI-EDGE-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-key-a RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert
    _LIK-key-a RID-SIZE + RID-SIZE
    _LIK-rid-b RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a _LIK-key-b LIBPI-EDGE-PREFIX LIB-S-OK _LIK-status
    _LIK-key-b RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert

    _LIK-rid-a 7 _LIK-rid-b _LIK-key-a LIBPI-MEMBERSHIP-KEY
        LIB-S-OK _LIK-status
    _LIK-rid-a 8 _LIK-rid-b _LIK-key-b LIBPI-MEMBERSHIP-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-MEMBERSHIP-KEY-SIZE
    _LIK-key-b LIBPI-MEMBERSHIP-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-rid-a 7 _LIK-rid-c _LIK-key-b LIBPI-MEMBERSHIP-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-MEMBERSHIP-KEY-SIZE
    _LIK-key-b LIBPI-MEMBERSHIP-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-rid-a _LIK-key-b LIBPI-MEMBERSHIP-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a RID-SIZE _LIK-key-b RID-SIZE COMPARE 0= _LIK-assert ;

: _LIK-collection  ( -- )
    _LIK-rid-a _LIK-key-a LIBPI-COLLECTION-KEY LIB-S-OK _LIK-status
    _LIK-key-a RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert
    3 _LIK-rid-a _LIK-key-a LIBPI-COLLECTION-ORDER-KEY
        LIB-S-OK _LIK-status
    4 _LIK-rid-a _LIK-key-b LIBPI-COLLECTION-ORDER-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-COLLECTION-ORDER-KEY-SIZE
    _LIK-key-b LIBPI-COLLECTION-ORDER-KEY-SIZE COMPARE 0< _LIK-assert
    3 _LIK-key-b LIBPI-COLLECTION-ORDER-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-COLLECTION-ORDER-PREFIX-SIZE
    _LIK-key-b LIBPI-COLLECTION-ORDER-PREFIX-SIZE
        COMPARE 0= _LIK-assert

    _LIK-title-a-nul 2 _LIK-rid-a _LIK-key-a
        LIBPI-COLLECTION-TITLE-KEY LIB-S-OK _LIK-status
    _LIK-title-a-one 2 _LIK-rid-a _LIK-key-b
        LIBPI-COLLECTION-TITLE-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-COLLECTION-TITLE-KEY-SIZE
    _LIK-key-b LIBPI-COLLECTION-TITLE-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-title-a-nul 2 _LIK-key-b LIBPI-COLLECTION-TITLE-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-COLLECTION-TITLE-PREFIX-SIZE
    _LIK-key-b LIBPI-COLLECTION-TITLE-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    _LIK-key-a 2 _LIK-rid-a _LIK-key-a LIBPI-COLLECTION-TITLE-KEY
        LIB-S-INVALID _LIK-status ;

: _LIK-directory  ( -- )
    _LIK-rid-a _LIK-key-a LIBPI-DOCUMENT-DIRECTORY-KEY
        LIB-S-OK _LIK-status
    _LIK-rid-a _LIK-key-b LIBPI-COLLECTION-DIRECTORY-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-DIRECTORY-KEY-SIZE
    _LIK-key-b LIBPI-DIRECTORY-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-key-a RID-SIZE _LIK-key-b RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a _LIK-key-a LIBPI-RECEIPT-DIRECTORY-KEY
        LIB-S-OK _LIK-status
    _LIK-key-b LIBPI-DIRECTORY-KEY-SIZE
    _LIK-key-a LIBPI-DIRECTORY-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-rid-a _LIK-key-b LIBPI-DIRECTORY-PREFIX
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-DIRECTORY-PREFIX-SIZE
    _LIK-key-b LIBPI-DIRECTORY-PREFIX-SIZE
        COMPARE 0= _LIK-assert
    _LIK-rid-a 0 _LIK-key-a LIBPI-DIRECTORY-KEY
        LIB-S-INVALID _LIK-status
    _LIK-rid-a 4 _LIK-key-a LIBPI-DIRECTORY-KEY
        LIB-S-INVALID _LIK-status
    _LIK-key-a LIBPI-DIRECTORY-DOCUMENT _LIK-key-a
        LIBPI-DIRECTORY-KEY LIB-S-INVALID _LIK-status ;

: _LIK-history  ( -- )
    _LIK-rid-a 7 _LIK-key-a LIBPI-HISTORY-DOMAIN-KEY
        LIB-S-OK _LIK-status
    _LIK-rid-a 42 _LIK-key-b LIBPI-HISTORY-DOMAIN-KEY
        LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-HISTORY-DOMAIN-KEY-SIZE
    _LIK-key-b LIBPI-HISTORY-DOMAIN-KEY-SIZE COMPARE 0< _LIK-assert
    _LIK-key-a RID-SIZE _LIK-rid-a RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a 7 _LIK-key-b LIBPI-HISTORY-KEY LIB-S-OK _LIK-status
    _LIK-key-a LIBPI-HISTORY-KEY-SIZE
    _LIK-key-b LIBPI-HISTORY-KEY-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a _LIK-key-b LIBPI-HISTORY-PREFIX LIB-S-OK _LIK-status
    _LIK-key-a RID-SIZE _LIK-key-b RID-SIZE COMPARE 0= _LIK-assert
    _LIK-rid-a 0 _LIK-key-a LIBPI-HISTORY-DOMAIN-KEY
        LIB-S-INVALID _LIK-status
    _LIK-key-a 1 _LIK-key-a LIBPI-HISTORY-DOMAIN-KEY
        LIB-S-INVALID _LIK-status ;

: _LIK-RUN  ( -- )
    0 _LIK-fails ! 0 _LIK-checks ! DEPTH _LIK-depth !
    _LIK-setup
    _LIK-key-limits
    _LIK-rid-and-order
    _LIK-title
    _LIK-tag-and-body
    _LIK-state
    _LIK-edge
    _LIK-collection
    _LIK-directory
    _LIK-history
    _LIK-stack
    _LIK-fails @ 0= IF
        ." LIBRARY INDEX KEYS PASS " _LIK-checks @ .
    ELSE
        ." LIBRARY INDEX KEYS FAIL " _LIK-fails @ . ." / " _LIK-checks @ .
    THEN CR ;
