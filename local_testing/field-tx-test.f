\ field-tx-test.f - Focused always-present field transaction contracts

PROVIDED akashic-field-transaction-test

VARIABLE _ftxt-fails
VARIABLE _ftxt-checks
VARIABLE _ftxt-depth

: _ftxt-assert  ( flag -- )
    1 _ftxt-checks +!
    0= IF
        1 _ftxt-fails +!
        ." FIELD TRANSACTION ASSERT " _ftxt-checks @ . CR
    THEN ;

: _ftxt-stack  ( -- )
    DEPTH DUP _ftxt-depth @ <> IF
        ." FIELD TRANSACTION STACK "
        _ftxt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ftxt-depth @ = _ftxt-assert ;

CREATE _ftxt-a 32 ALLOT
CREATE _ftxt-b 32 ALLOT
CREATE _ftxt-r 32 ALLOT
CREATE _ftxt-expected 32 ALLOT
CREATE _ftxt-acc 32 ALLOT

: _ftxt-zero?  ( address length -- flag )
    0 DO
        DUP I + C@ IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _ftxt-inner  ( -- )
    FIELD-TRANSACTION-MINE? _ftxt-assert
    CRYPTO-ACC-TRANSACTION-MINE? _ftxt-assert
    _ftxt-a _ftxt-b _ftxt-r FIELD-ADD ;

: _ftxt-outer  ( -- )
    FIELD-TRANSACTION-MINE? _ftxt-assert
    FIELD-USE-P256
    2 _ftxt-a FIELD-SET-U64
    3 _ftxt-b FIELD-SET-U64
    ['] _ftxt-inner FIELD-WITH-TRANSACTION
    FIELD-TRANSACTION-MINE? _ftxt-assert
    5 _ftxt-expected FIELD-SET-U64
    _ftxt-r _ftxt-expected FIELD-EQ? _ftxt-assert ;

: _ftxt-throws  ( -- )
    FIELD-TRANSACTION-MINE? _ftxt-assert
    -4096 THROW ;

: _ftxt-throw-scope  ( -- )
    ['] _ftxt-throws FIELD-WITH-TRANSACTION ;

: _ftxt-test-recursion  ( -- )
    FIELD-TRANSACTION-MINE? 0= _ftxt-assert
    CRYPTO-ACC-TRANSACTION-MINE? 0= _ftxt-assert
    ['] _ftxt-outer FIELD-WITH-TRANSACTION
    FIELD-TRANSACTION-MINE? 0= _ftxt-assert
    CRYPTO-ACC-TRANSACTION-MINE? 0= _ftxt-assert
    _ftxt-acc GF-R@
    _ftxt-acc 32 _ftxt-zero? _ftxt-assert
    _ftxt-stack ;

: _ftxt-test-throw-release  ( -- )
    ['] _ftxt-throw-scope CATCH -4096 = _ftxt-assert
    FIELD-TRANSACTION-MINE? 0= _ftxt-assert
    CRYPTO-ACC-TRANSACTION-MINE? 0= _ftxt-assert
    _ftxt-acc GF-R@
    _ftxt-acc 32 _ftxt-zero? _ftxt-assert

    \ A direct public primitive still works after exceptional release,
    \ proving that the guard is not stranded.
    FIELD-USE-P256
    _ftxt-a _ftxt-b _ftxt-r FIELD-ADD
    5 _ftxt-expected FIELD-SET-U64
    _ftxt-r _ftxt-expected FIELD-EQ? _ftxt-assert

    \ Public FIELD-MAC is explicit in/out state, not ambient prev_lo.
    2 _ftxt-a FIELD-SET-U64
    3 _ftxt-b FIELD-SET-U64
    5 _ftxt-r FIELD-SET-U64
    _ftxt-a _ftxt-b _ftxt-r FIELD-MAC
    11 _ftxt-expected FIELD-SET-U64
    _ftxt-r _ftxt-expected FIELD-EQ? _ftxt-assert
    _ftxt-stack ;

: _FTXT-RUN  ( -- )
    0 _ftxt-fails !
    0 _ftxt-checks !
    DEPTH _ftxt-depth !
    _ftxt-test-recursion
    _ftxt-test-throw-release
    _ftxt-stack
    _ftxt-fails @ 0= IF
        ." FIELD TRANSACTION PASS " _ftxt-checks @ . CR
    ELSE
        ." FIELD TRANSACTION FAIL " _ftxt-fails @ . CR
    THEN ;
