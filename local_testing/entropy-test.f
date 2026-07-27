\ entropy-test.f - Focused checked entropy contracts

PROVIDED akashic-entropy-test

VARIABLE _entt-fails
VARIABLE _entt-checks
VARIABLE _entt-depth

: _entt-assert  ( flag -- )
    1 _entt-checks +!
    0= IF
        1 _entt-fails +!
        ." ENTROPY ASSERT " _entt-checks @ . CR
    THEN ;

: _entt-stack  ( -- )
    DEPTH _entt-depth @ = _entt-assert ;

: _entt-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

CREATE _entt-output 64 ALLOT

: _entt-test-status  ( -- )
    ENTROPY-S-OK ENTROPY-STATUS-VALID? _entt-assert
    ENTROPY-S-UNAVAILABLE ENTROPY-STATUS-VALID? _entt-assert
    ENTROPY-S-RANGE ENTROPY-STATUS-VALID? _entt-assert
    ENTROPY-S-PROTECTED ENTROPY-STATUS-VALID? _entt-assert
    ENTROPY-S-PROTECTED 1+
        ENTROPY-STATUS-VALID? 0= _entt-assert
    ENTROPY-READY? _entt-assert
    _entt-stack ;

: _entt-test-fill  ( -- )
    _entt-output 64 0xA5 FILL
    _entt-output 64 ENTROPY-FILL
        ENTROPY-S-OK = _entt-assert

    \ Null-empty acquisition is an ordinary no-op and requires no entropy.
    0 0 ENTROPY-FILL ENTROPY-S-OK = _entt-assert
    -1 0 ENTROPY-FILL ENTROPY-S-OK = _entt-assert

    _entt-output 16 0xA5 FILL
    0 16 ENTROPY-FILL ENTROPY-S-RANGE = _entt-assert
    _entt-output 16 0xA5 _entt-filled? _entt-assert
    _entt-output -1 ENTROPY-FILL ENTROPY-S-RANGE = _entt-assert
    _entt-output 16 0xA5 _entt-filled? _entt-assert
    _entt-stack ;

: _ENTT-RUN  ( -- )
    0 _entt-fails !
    0 _entt-checks !
    DEPTH _entt-depth !
    _entt-test-status
    _entt-test-fill
    _entt-stack
    _entt-fails @ 0= IF
        ." ENTROPY PASS " _entt-checks @ . CR
    ELSE
        ." ENTROPY FAIL " _entt-fails @ . CR
    THEN ;
