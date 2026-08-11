\ sha3-context-test.f - Focused caller-owned SHA3-256 contracts

PROVIDED akashic-sha3ctx-test

VARIABLE _s3ct-fails
VARIABLE _s3ct-checks
VARIABLE _s3ct-depth

: _s3ct-assert  ( flag -- )
    1 _s3ct-checks +!
    0= IF
        1 _s3ct-fails +!
        ." SHA3 CONTEXT ASSERT " _s3ct-checks @ . CR
    THEN ;

: _s3ct-stack  ( -- )
    DEPTH DUP _s3ct-depth @ <> IF
        ." SHA3 CONTEXT STACK "
        _s3ct-depth @ . ." -> " DUP . CR .S CR
    THEN
    _s3ct-depth @ = _s3ct-assert ;

: _s3ct-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

CREATE _s3ct-empty-expected
    0xA7 C, 0xFF C, 0xC6 C, 0xF8 C,
    0xBF C, 0x1E C, 0xD7 C, 0x66 C,
    0x51 C, 0xC1 C, 0x47 C, 0x56 C,
    0xA0 C, 0x61 C, 0xD6 C, 0x62 C,
    0xF5 C, 0x80 C, 0xFF C, 0x4D C,
    0xE4 C, 0x3B C, 0x49 C, 0xFA C,
    0x82 C, 0xD8 C, 0x0A C, 0x4B C,
    0x80 C, 0xF8 C, 0x43 C, 0x4A C,

CREATE _s3ct-abc
    0x61 C, 0x62 C, 0x63 C,

CREATE _s3ct-abc-expected
    0x3A C, 0x98 C, 0x5D C, 0xA7 C,
    0x4F C, 0xE2 C, 0x25 C, 0xB2 C,
    0x04 C, 0x5C C, 0x17 C, 0x2D C,
    0x6B C, 0xD3 C, 0x90 C, 0xBD C,
    0x85 C, 0x5F C, 0x08 C, 0x6E C,
    0x3E C, 0x9D C, 0x52 C, 0x5B C,
    0x46 C, 0xBF C, 0xE2 C, 0x45 C,
    0x11 C, 0x43 C, 0x15 C, 0x32 C,

CREATE _s3ct-input 409 ALLOT

CREATE _s3ct-context-a SHA3-256-CONTEXT-SIZE ALLOT
CREATE _s3ct-context-b SHA3-256-CONTEXT-SIZE ALLOT
CREATE _s3ct-context-c SHA3-256-CONTEXT-SIZE ALLOT
CREATE _s3ct-context-copy SHA3-256-CONTEXT-SIZE ALLOT

CREATE _s3ct-digest-a SHA3-256-CONTEXT-DIGEST-SIZE ALLOT
CREATE _s3ct-digest-b SHA3-256-CONTEXT-DIGEST-SIZE ALLOT
CREATE _s3ct-digest-c SHA3-256-CONTEXT-DIGEST-SIZE ALLOT
CREATE _s3ct-digest-copy SHA3-256-CONTEXT-DIGEST-SIZE ALLOT

: _s3ct-input-init  ( -- )
    409 0 DO
        I 73 * 19 + 0xFF AND _s3ct-input I + C!
    LOOP ;

: _s3ct-context-snapshot  ( context -- )
    _s3ct-context-copy SHA3-256-CONTEXT-SIZE MOVE ;

: _s3ct-context-unchanged?  ( context -- flag )
    _s3ct-context-copy SHA3-256-CONTEXT-SIZE _s3ct-bytes= ;

: _s3ct-digest-snapshot  ( digest -- )
    _s3ct-digest-copy SHA3-256-CONTEXT-DIGEST-SIZE MOVE ;

: _s3ct-digest-unchanged?  ( digest -- flag )
    _s3ct-digest-copy SHA3-256-CONTEXT-DIGEST-SIZE _s3ct-bytes= ;

: _s3ct-length-parity  ( input-u -- )
    >R
    _s3ct-input R@ _s3ct-digest-a SHA3-256-HASH
    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input R@ _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-b _s3ct-context-a SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-b _s3ct-digest-a 32 _s3ct-bytes= _s3ct-assert
    R> DROP ;

: _s3ct-test-vectors  ( -- )
    SHA3-256-CONTEXT-SIZE 648 = _s3ct-assert
    SHA3-256-CONTEXT-DIGEST-SIZE 32 = _s3ct-assert
    SHA3-CONTEXT-S-HARDWARE SHA3-CONTEXT-STATUS-VALID? _s3ct-assert
    SHA3-CONTEXT-S-HARDWARE 1+
        SHA3-CONTEXT-STATUS-VALID? 0= _s3ct-assert

    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-context-a SHA3-256-CONTEXT-VALID? _s3ct-assert
    0 0 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-a _s3ct-context-a SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-a _s3ct-empty-expected 32 _s3ct-bytes=
        _s3ct-assert
    _s3ct-context-a SHA3-256-CONTEXT-VALID? _s3ct-assert

    _s3ct-context-b SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-abc 3 _s3ct-context-b SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-b _s3ct-context-b SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-b _s3ct-abc-expected 32 _s3ct-bytes=
        _s3ct-assert
    _s3ct-stack ;

: _s3ct-test-boundaries  ( -- )
    \ Exercise the final partial byte, exact rate, and first byte of the
    \ next rate independently so padding placement is not inferred from
    \ only one longer message.
    135 _s3ct-length-parity
    136 _s3ct-length-parity
    137 _s3ct-length-parity

    _s3ct-input 409 _s3ct-digest-a SHA3-256-HASH

    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input 1 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input 1+ 135 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input 136 + 136 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input 272 + 137 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-a _s3ct-context-a
        SHA3-256-CONTEXT-FINAL-COMPARE
        SHA3-CONTEXT-S-OK = _s3ct-assert
        _s3ct-assert

    \ Two contexts advance in an interleaved order without sharing state.
    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-context-b SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input 100 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-abc 1 _s3ct-context-b SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input 100 + 173 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-abc 1+ 1 _s3ct-context-b SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-input 273 + 136 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-abc 2 + 1 _s3ct-context-b SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-b _s3ct-context-a SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-b _s3ct-digest-a 32 _s3ct-bytes= _s3ct-assert
    _s3ct-digest-c _s3ct-context-b SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-c _s3ct-abc-expected 32 _s3ct-bytes=
        _s3ct-assert
    _s3ct-stack ;

: _s3ct-test-rejections  ( -- )
    -8 SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-INVALID = _s3ct-assert

    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-context-a _s3ct-context-snapshot
    _s3ct-context-a 1 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-ALIAS = _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert
    _s3ct-input -1 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-INVALID = _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert

    _SHA3C-LENGTH-MAX _s3ct-context-a _SHA3C.TOTAL !
    _SHA3C-LENGTH-MAX _SHA3C-RATE MOD
        _s3ct-context-a _SHA3C.BUFFERED !
    _s3ct-context-a SHA3-256-CONTEXT-VALID? _s3ct-assert
    _s3ct-context-a _s3ct-context-snapshot
    _s3ct-input 1 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-CAPACITY = _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert

    \ Invalid and aliased digest destinations never consume the context.
    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-context-a _s3ct-context-snapshot
    0 _s3ct-context-a SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-INVALID = _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert
    _s3ct-context-a _s3ct-context-a SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-ALIAS = _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert
    _s3ct-context-a _s3ct-context-a
        SHA3-256-CONTEXT-FINAL-COMPARE
        SHA3-CONTEXT-S-ALIAS = _s3ct-assert
        0= _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert

    _s3ct-digest-a 32 0xA5 FILL
    _s3ct-digest-a _s3ct-digest-snapshot
    _s3ct-context-c SHA3-256-CONTEXT-SIZE 0 FILL
    _s3ct-digest-a _s3ct-context-c SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-INVALID = _s3ct-assert
    _s3ct-digest-a _s3ct-digest-unchanged? _s3ct-assert
    _s3ct-stack ;

: _s3ct-test-final-state  ( -- )
    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-abc 3 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-digest-a _s3ct-context-a SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-context-a _s3ct-context-snapshot
    _s3ct-digest-b 32 0x5A FILL
    _s3ct-digest-b _s3ct-digest-snapshot
    _s3ct-input 1 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-STATE = _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert
    _s3ct-digest-b _s3ct-context-a SHA3-256-CONTEXT-FINAL
        SHA3-CONTEXT-S-STATE = _s3ct-assert
    _s3ct-context-a _s3ct-context-unchanged? _s3ct-assert
    _s3ct-digest-b _s3ct-digest-unchanged? _s3ct-assert

    \ A valid mismatch still finalizes exactly once and reports S-OK.
    _s3ct-context-b SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-abc-expected _s3ct-context-b
        SHA3-256-CONTEXT-FINAL-COMPARE
        SHA3-CONTEXT-S-OK = _s3ct-assert
        0= _s3ct-assert
    _s3ct-context-b SHA3-256-CONTEXT-VALID? _s3ct-assert
    _s3ct-context-b _s3ct-context-snapshot
    _s3ct-empty-expected _s3ct-context-b
        SHA3-256-CONTEXT-FINAL-COMPARE
        SHA3-CONTEXT-S-STATE = _s3ct-assert
        0= _s3ct-assert
    _s3ct-context-b _s3ct-context-unchanged? _s3ct-assert

    _s3ct-context-c SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    _s3ct-empty-expected _s3ct-context-c
        SHA3-256-CONTEXT-FINAL-COMPARE
        SHA3-CONTEXT-S-OK = _s3ct-assert
        _s3ct-assert
    _s3ct-stack ;

: _s3ct-test-hardware-conflict  ( -- )
    \ A raw permutation rejected by an independently owned SHA3 transaction
    \ invalidates and wipes the complete caller context without disturbing
    \ that direct owner.
    _s3ct-context-a SHA3-256-CONTEXT-INIT
        SHA3-CONTEXT-S-OK = _s3ct-assert
    SHA3-256-MODE SHA3-BEGIN 0= _s3ct-assert
    _s3ct-input 136 _s3ct-context-a SHA3-256-CONTEXT-UPDATE
        SHA3-CONTEXT-S-HARDWARE = _s3ct-assert
    _s3ct-context-a SHA3-256-CONTEXT-VALID? 0= _s3ct-assert
    _s3ct-context-a SHA3-256-CONTEXT-SIZE _SHA3C-ZERO? _s3ct-assert
    SHA3-CLEAR 0= _s3ct-assert
    _s3ct-stack ;

: _S3CT-RUN  ( -- )
    0 _s3ct-fails !
    0 _s3ct-checks !
    DEPTH _s3ct-depth !
    _s3ct-input-init
    _s3ct-test-vectors
    _s3ct-test-boundaries
    _s3ct-test-rejections
    _s3ct-test-final-state
    _s3ct-test-hardware-conflict
    _s3ct-stack
    _s3ct-fails @ 0= IF
        ." SHA3 CONTEXT PASS " _s3ct-checks @ . CR
    ELSE
        ." SHA3 CONTEXT FAIL " _s3ct-fails @ . CR
    THEN ;
