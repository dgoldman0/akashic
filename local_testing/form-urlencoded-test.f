\ Focused machine contracts for the stateless form component codec.

PROVIDED akashic-fue-contracts

VARIABLE _fuet-checks
VARIABLE _fuet-fails
VARIABLE _fuet-depth
VARIABLE _fuet-encoded-u

CREATE _fuet-source   256 ALLOT
CREATE _fuet-encoded  768 ALLOT
CREATE _fuet-decoded  256 ALLOT
CREATE _fuet-alias    128 ALLOT

: _fuet-assert  ( flag -- )
    1 _fuet-checks +!
    0= IF
        1 _fuet-fails +!
        ." FORM URLENCODED ASSERT " _fuet-checks @ . CR
    THEN ;

: _fuet-status  ( actual expected -- )
    2DUP <> IF
        ." FORM URLENCODED STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _fuet-assert ;

: _fuet-stack  ( -- )
    DEPTH DUP _fuet-depth @ <> IF
        ." FORM URLENCODED STACK "
        _fuet-depth @ . ." -> " DUP . CR .S CR
    THEN
    _fuet-depth @ = _fuet-assert ;

: _fuet-filled?  ( address length byte -- flag )
    BEGIN OVER WHILE
        2 PICK C@ OVER <> IF
            2DROP DROP 0 EXIT
        THEN
        >R 1- SWAP 1+ SWAP R>
    REPEAT
    2DROP DROP -1 ;

: _fuet-encode-input  ( -- address length )
    S" AZaz09*-._ ~+/%" ;

: _fuet-encode-output  ( -- address length )
    S" AZaz09*-._+%7E%2B%2F%25" ;

: _fuet-decode-input  ( -- address length )
    S" a+b%20c%2F%2f%26%3D%2B%00%252F" ;

: _fuet-test-vocabulary-and-empty  ( -- )
    -1 FORM-URLENCODED-STATUS-VALID? 0= _fuet-assert
    FORM-URLENCODED-S-ENCODING
        FORM-URLENCODED-STATUS-VALID? _fuet-assert
    FORM-URLENCODED-S-ENCODING 1+
        FORM-URLENCODED-STATUS-VALID? 0= _fuet-assert

    0 0 FORM-URLENCODED-MEASURE
        FORM-URLENCODED-S-OK _fuet-status
        0= _fuet-assert
    0 0 FORM-URLENCODED-DECODE-MEASURE
        FORM-URLENCODED-S-OK _fuet-status
        0= _fuet-assert
    0 0 0 0 FORM-URLENCODED-ENCODE
        FORM-URLENCODED-S-OK _fuet-status
        0= _fuet-assert
    0 0 0 0 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-OK _fuet-status
        0= _fuet-assert
    _fuet-stack ;

: _fuet-test-encode-vector  ( -- )
    _fuet-encode-input FORM-URLENCODED-MEASURE
        FORM-URLENCODED-S-OK _fuet-status
        23 = _fuet-assert

    _fuet-encoded 64 0xA5 FILL
    _fuet-encode-input _fuet-encoded 64 FORM-URLENCODED-ENCODE
        FORM-URLENCODED-S-OK _fuet-status
        23 = _fuet-assert
    _fuet-encoded 23 _fuet-encode-output
        COMPARE 0= _fuet-assert
    _fuet-encoded 23 + 41 0xA5 _fuet-filled? _fuet-assert
    _fuet-stack ;

: _fuet-decode-bytes?  ( -- flag )
    _fuet-decoded      C@ 97 =
    _fuet-decoded  1 + C@ 32 = AND
    _fuet-decoded  2 + C@ 98 = AND
    _fuet-decoded  3 + C@ 32 = AND
    _fuet-decoded  4 + C@ 99 = AND
    _fuet-decoded  5 + C@ 47 = AND
    _fuet-decoded  6 + C@ 47 = AND
    _fuet-decoded  7 + C@ 38 = AND
    _fuet-decoded  8 + C@ 61 = AND
    _fuet-decoded  9 + C@ 43 = AND
    _fuet-decoded 10 + C@  0 = AND
    _fuet-decoded 11 + C@ 37 = AND
    _fuet-decoded 12 + C@ 50 = AND
    _fuet-decoded 13 + C@ 70 = AND ;

: _fuet-test-decode-vector  ( -- )
    _fuet-decode-input FORM-URLENCODED-DECODE-MEASURE
        FORM-URLENCODED-S-OK _fuet-status
        14 = _fuet-assert

    _fuet-decoded 32 0xA5 FILL
    _fuet-decode-input _fuet-decoded 14 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-OK _fuet-status
        14 = _fuet-assert
    _fuet-decode-bytes? _fuet-assert
    _fuet-decoded 14 + 18 0xA5 _fuet-filled? _fuet-assert
    _fuet-stack ;

: _fuet-expect-malformed  ( source source-u -- )
    2DUP FORM-URLENCODED-DECODE-MEASURE
        FORM-URLENCODED-S-ENCODING _fuet-status
        0= _fuet-assert
    _fuet-decoded 32 0xA5 FILL
    _fuet-decoded 32 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-ENCODING _fuet-status
        0= _fuet-assert
    _fuet-decoded 32 0xA5 _fuet-filled? _fuet-assert ;

: _fuet-test-malformed  ( -- )
    S" %"           _fuet-expect-malformed
    S" %0"          _fuet-expect-malformed
    S" %GG"         _fuet-expect-malformed
    S" %G0"         _fuet-expect-malformed
    S" %0G"         _fuet-expect-malformed
    S" ok%20then%"  _fuet-expect-malformed
    S" ok%20then%0" _fuet-expect-malformed
    _fuet-stack ;

: _fuet-test-capacity-and-shape  ( -- )
    _fuet-encoded 32 0xA5 FILL
    _fuet-encode-input _fuet-encoded 22 FORM-URLENCODED-ENCODE
        FORM-URLENCODED-S-CAPACITY _fuet-status
        0= _fuet-assert
    _fuet-encoded 32 0xA5 _fuet-filled? _fuet-assert

    _fuet-decoded 32 0xA5 FILL
    _fuet-decode-input _fuet-decoded 13 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-CAPACITY _fuet-status
        0= _fuet-assert
    _fuet-decoded 32 0xA5 _fuet-filled? _fuet-assert

    0 1 FORM-URLENCODED-DECODE-MEASURE
        FORM-URLENCODED-S-INVALID _fuet-status
        0= _fuet-assert
    _fuet-source -1 FORM-URLENCODED-DECODE-MEASURE
        FORM-URLENCODED-S-INVALID _fuet-status
        0= _fuet-assert
    S" x" 0 1 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-INVALID _fuet-status
        0= _fuet-assert
    S" x" _fuet-decoded -1 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-INVALID _fuet-status
        0= _fuet-assert
    S" x" 0 0 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-CAPACITY _fuet-status
        0= _fuet-assert
    _fuet-stack ;

: _fuet-copy-a+b  ( destination -- )
    >R S" a+b" R> SWAP MOVE ;

: _fuet-expect-alias  ( source source-u destination capacity -- )
    FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-ALIAS _fuet-status
        0= _fuet-assert ;

: _fuet-test-aliases  ( -- )
    _fuet-alias 128 0xA5 FILL
    _fuet-alias _fuet-copy-a+b
    _fuet-alias 3 _fuet-alias 32 FORM-URLENCODED-ENCODE
        FORM-URLENCODED-S-ALIAS _fuet-status
        0= _fuet-assert
    _fuet-alias 3 S" a+b" COMPARE 0= _fuet-assert
    _fuet-alias 3 + 125 0xA5 _fuet-filled? _fuet-assert
    _fuet-alias 3 _fuet-alias 32 _fuet-expect-alias
    _fuet-alias 3 S" a+b" COMPARE 0= _fuet-assert
    _fuet-alias 3 + 125 0xA5 _fuet-filled? _fuet-assert
    _fuet-alias 3 _fuet-alias 2 + 16 _fuet-expect-alias
    _fuet-alias 3 S" a+b" COMPARE 0= _fuet-assert
    _fuet-alias 3 + 125 0xA5 _fuet-filled? _fuet-assert

    _fuet-alias 128 0xA5 FILL
    _fuet-alias 4 + _fuet-copy-a+b
    _fuet-alias 4 + 3 _fuet-alias 8 _fuet-expect-alias
    _fuet-alias 4 0xA5 _fuet-filled? _fuet-assert
    _fuet-alias 4 + 3 S" a+b" COMPARE 0= _fuet-assert
    _fuet-alias 7 + 121 0xA5 _fuet-filled? _fuet-assert

    \ Exact adjacency is disjoint in both directions.
    _fuet-alias 128 0xA5 FILL
    _fuet-alias _fuet-copy-a+b
    _fuet-alias 3 _fuet-alias 3 + 3 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-OK _fuet-status
        3 = _fuet-assert
    _fuet-alias 3 + 3 S" a b" COMPARE 0= _fuet-assert

    _fuet-alias 128 0xA5 FILL
    _fuet-alias 3 + _fuet-copy-a+b
    _fuet-alias 3 + 3 _fuet-alias 3 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-OK _fuet-status
        3 = _fuet-assert
    _fuet-alias 3 S" a b" COMPARE 0= _fuet-assert

    \ Overlap with unused advertised output capacity is still rejected.
    _fuet-alias 128 0xA5 FILL
    _fuet-alias 16 + _fuet-copy-a+b
    _fuet-alias 16 + 3 _fuet-alias 32 _fuet-expect-alias
    _fuet-alias 16 0xA5 _fuet-filled? _fuet-assert
    _fuet-alias 16 + 3 S" a+b" COMPARE 0= _fuet-assert
    _fuet-alias 19 + 109 0xA5 _fuet-filled? _fuet-assert
    _fuet-stack ;

: _fuet-fill-all-bytes  ( -- )
    0
    BEGIN DUP 256 < WHILE
        DUP DUP _fuet-source + C!
        1+
    REPEAT
    DROP ;

: _fuet-test-all-bytes-round-trip  ( -- )
    _fuet-fill-all-bytes
    _fuet-source 256 FORM-URLENCODED-MEASURE
        FORM-URLENCODED-S-OK _fuet-status
        DUP 634 = _fuet-assert
        _fuet-encoded-u !

    _fuet-encoded 768 0xA5 FILL
    _fuet-source 256 _fuet-encoded 768 FORM-URLENCODED-ENCODE
        FORM-URLENCODED-S-OK _fuet-status
        _fuet-encoded-u @ = _fuet-assert

    _fuet-encoded _fuet-encoded-u @
        FORM-URLENCODED-DECODE-MEASURE
        FORM-URLENCODED-S-OK _fuet-status
        256 = _fuet-assert

    _fuet-decoded 256 0xA5 FILL
    _fuet-encoded _fuet-encoded-u @
        _fuet-decoded 256 FORM-URLENCODED-DECODE
        FORM-URLENCODED-S-OK _fuet-status
        256 = _fuet-assert
    _fuet-source 256 _fuet-decoded 256
        COMPARE 0= _fuet-assert
    _fuet-stack ;

: _FUET-RUN  ( -- )
    0 _fuet-checks !
    0 _fuet-fails !
    DEPTH _fuet-depth !
    _fuet-test-vocabulary-and-empty
    _fuet-test-encode-vector
    _fuet-test-decode-vector
    _fuet-test-malformed
    _fuet-test-capacity-and-shape
    _fuet-test-aliases
    _fuet-test-all-bytes-round-trip
    _fuet-fails @ IF
        ." FORM URLENCODED FAIL checks/fails "
        _fuet-checks @ . _fuet-fails @ . CR
    ELSE
        ." FORM URLENCODED PASS checks "
        _fuet-checks @ . CR
    THEN ;
