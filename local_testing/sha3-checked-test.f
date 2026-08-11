\ sha3-checked-test.f - checked MegaPad SHA3/SHAKE bridge contracts

VARIABLE _s3-fails
VARIABLE _s3-checks
VARIABLE _s3-depth
VARIABLE _s3-fill-byte
VARIABLE _s3-length

: _s3-assert  ( flag -- )
    1 _s3-checks +!
    0= IF 1 _s3-fails +! ." SHA3 ASSERT " _s3-checks @ . CR THEN ;

: _s3-stack  ( -- ) DEPTH _s3-depth @ = _s3-assert ;
: _s3-status-ok  ( status -- ) DUP 0= _s3-assert DROP ;

: _s3-filled?  ( addr len byte -- flag )
    _s3-fill-byte !
    0 ?DO
        DUP I + C@ _s3-fill-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

CREATE _s3-data 169 ALLOT
CREATE _s3-key 200 ALLOT
CREATE _s3-out 80 ALLOT

: _s3-init-input  ( -- )
    169 0 DO I 37 * 11 + 255 AND _s3-data I + C! LOOP
    200 0 DO I 19 * 7 + 255 AND _s3-key I + C! LOOP ;

: _s3-out-reset  ( -- ) _s3-out 80 0xA5 FILL ;

: _s3-canary?  ( used -- flag )
    DUP _s3-out + SWAP 80 SWAP - 0xA5 _s3-filled? ;

CREATE _s3-256-136
    0x9F C, 0x06 C, 0x57 C, 0x22 C, 0x98 C, 0x3C C, 0x1B C, 0x64 C,
    0x3B C, 0x3F C, 0xAB C, 0xBE C, 0xD6 C, 0xE7 C, 0x91 C, 0xF6 C,
    0xD7 C, 0x4F C, 0x77 C, 0xE6 C, 0xCF C, 0x5A C, 0x2D C, 0x38 C,
    0xC0 C, 0x7C C, 0x12 C, 0x44 C, 0x65 C, 0xED C, 0x5D C, 0x9F C,

CREATE _s3-256-137
    0x30 C, 0xEF C, 0xE5 C, 0x17 C, 0x34 C, 0x6C C, 0x81 C, 0x88 C,
    0x28 C, 0x63 C, 0x4C C, 0xB8 C, 0xA3 C, 0xEB C, 0x35 C, 0x38 C,
    0xC1 C, 0x4B C, 0xC2 C, 0xF2 C, 0x80 C, 0x13 C, 0x2C C, 0xF0 C,
    0x26 C, 0x1E C, 0xD1 C, 0x8A C, 0x7D C, 0xD8 C, 0x5A C, 0x8B C,

CREATE _s3-512-72
    0x71 C, 0x63 C, 0x02 C, 0x3F C, 0xB8 C, 0x55 C, 0x89 C, 0x36 C,
    0x2E C, 0x8F C, 0x18 C, 0x43 C, 0x99 C, 0xAC C, 0xCA C, 0xA1 C,
    0x4E C, 0x0D C, 0x17 C, 0xDA C, 0x87 C, 0xDC C, 0xC6 C, 0x9C C,
    0xEC C, 0xE7 C, 0x25 C, 0xC9 C, 0xBE C, 0xF2 C, 0x3B C, 0x0E C,
    0x4D C, 0xFB C, 0x12 C, 0xED C, 0x01 C, 0x52 C, 0x13 C, 0xD3 C,
    0xE6 C, 0xF5 C, 0xC5 C, 0xCC C, 0x98 C, 0xF2 C, 0x3C C, 0x20 C,
    0x30 C, 0x3D C, 0xD5 C, 0xA2 C, 0x09 C, 0x1D C, 0xF3 C, 0x58 C,
    0x15 C, 0xF5 C, 0xF2 C, 0x42 C, 0xE7 C, 0xA9 C, 0xBF C, 0xEB C,

CREATE _s3-512-73
    0xC2 C, 0x82 C, 0x3E C, 0x8B C, 0x42 C, 0x82 C, 0x15 C, 0xEC C,
    0xAC C, 0xCE C, 0x41 C, 0x59 C, 0x2B C, 0x97 C, 0x65 C, 0x54 C,
    0xF6 C, 0xDB C, 0xDB C, 0x5A C, 0xEB C, 0xA5 C, 0x24 C, 0xCD C,
    0xCD C, 0xA6 C, 0x9D C, 0x3E C, 0x86 C, 0xAC C, 0x79 C, 0x1F C,
    0x77 C, 0x50 C, 0xC2 C, 0x47 C, 0x20 C, 0xFC C, 0x0F C, 0xFE C,
    0xC0 C, 0x96 C, 0x69 C, 0x09 C, 0xC5 C, 0x19 C, 0xFB C, 0x53 C,
    0xA9 C, 0x15 C, 0xF8 C, 0xC9 C, 0xC7 C, 0xB9 C, 0xCA C, 0xBA C,
    0x1D C, 0x2B C, 0x25 C, 0xD5 C, 0xA3 C, 0xB9 C, 0x7C C, 0xAB C,

CREATE _s3-shake128-169-65
    0x52 C, 0x9E C, 0x1B C, 0x66 C, 0xDB C, 0x25 C, 0xB2 C, 0x00 C,
    0x62 C, 0xF2 C, 0x40 C, 0x04 C, 0xFC C, 0xCE C, 0x11 C, 0x48 C,
    0x58 C, 0xC6 C, 0x9A C, 0xF5 C, 0xCC C, 0x49 C, 0xA6 C, 0x3C C,
    0x65 C, 0xD8 C, 0xDF C, 0x4D C, 0xAA C, 0x66 C, 0x21 C, 0x09 C,
    0x10 C, 0xFA C, 0xA4 C, 0xDA C, 0xCF C, 0x34 C, 0x61 C, 0x22 C,
    0xE2 C, 0xB5 C, 0xFF C, 0xC0 C, 0x94 C, 0xF4 C, 0x96 C, 0x8D C,
    0x54 C, 0x74 C, 0xB3 C, 0xCE C, 0x82 C, 0xF3 C, 0x00 C, 0xA7 C,
    0x77 C, 0x89 C, 0x6B C, 0x2D C, 0x6D C, 0x3A C, 0x71 C, 0x7D C,
    0xC4 C,

CREATE _s3-shake256-137-65
    0x59 C, 0xDF C, 0x4C C, 0x6A C, 0x38 C, 0x29 C, 0xEA C, 0xCE C,
    0xCA C, 0x40 C, 0x8C C, 0xDB C, 0xAB C, 0x35 C, 0x9A C, 0xDC C,
    0x23 C, 0x7E C, 0x09 C, 0x09 C, 0x0B C, 0x08 C, 0x5C C, 0x98 C,
    0x70 C, 0x9B C, 0xA7 C, 0x42 C, 0x4C C, 0xFE C, 0x72 C, 0xA5 C,
    0x0E C, 0xA7 C, 0x7C C, 0x38 C, 0x80 C, 0x3A C, 0x53 C, 0x55 C,
    0xC0 C, 0x01 C, 0x23 C, 0xBF C, 0x4D C, 0xB2 C, 0x92 C, 0xD2 C,
    0x37 C, 0x76 C, 0x75 C, 0xA1 C, 0x8F C, 0xE7 C, 0x69 C, 0x4D C,
    0xC2 C, 0x0E C, 0x07 C, 0x66 C, 0x97 C, 0x94 C, 0x42 C, 0x95 C,
    0xA9 C,

CREATE _s3-hmac-200-137
    0xF8 C, 0x8E C, 0x02 C, 0x8B C, 0xC9 C, 0xB0 C, 0xA3 C, 0xA4 C,
    0xF8 C, 0x56 C, 0x62 C, 0x55 C, 0x48 C, 0x26 C, 0xA2 C, 0x4D C,
    0xD1 C, 0x4B C, 0x73 C, 0x46 C, 0xDA C, 0x65 C, 0xC0 C, 0x92 C,
    0x2F C, 0xC9 C, 0x69 C, 0x0D C, 0xBA C, 0x19 C, 0x73 C, 0xC0 C,

: _s3-test-fixed  ( -- )
    _s3-out-reset
    _s3-data 136 _s3-out SHA3-256-HASH
    _s3-out _s3-256-136 32 SAMESTR? _s3-assert
    32 _s3-canary? _s3-assert _s3-stack

    _s3-out-reset
    SHA3-256-BEGIN
    _s3-data 7 SHA3-256-ADD
    _s3-data 7 + 130 SHA3-256-ADD
    _s3-out SHA3-256-END
    _s3-out _s3-256-137 32 SAMESTR? _s3-assert
    32 _s3-canary? _s3-assert _s3-stack

    _s3-out-reset
    _s3-data 72 _s3-out SHA3-512-HASH
    _s3-out _s3-512-72 64 SAMESTR? _s3-assert
    64 _s3-canary? _s3-assert _s3-stack

    _s3-out-reset
    SHA3-512-BEGIN
    _s3-data 5 SHA3-512-ADD
    _s3-data 5 + 68 SHA3-512-ADD
    _s3-out SHA3-512-END
    _s3-out _s3-512-73 64 SAMESTR? _s3-assert
    64 _s3-canary? _s3-assert _s3-stack

    _s3-data 137 _s3-256-137 SHA3-256-HASH-COMPARE _s3-assert
    SHA3-256-BEGIN _s3-data 137 SHA3-256-ADD
    _s3-256-137 SHA3-256-END-COMPARE _s3-assert _s3-stack ;

: _s3-check-shake128  ( length -- )
    _s3-length ! _s3-out-reset
    _s3-data 169 _s3-out _s3-length @ SHAKE-128
    _s3-out _s3-shake128-169-65 _s3-length @ SAMESTR? _s3-assert
    _s3-length @ _s3-canary? _s3-assert _s3-stack ;

: _s3-check-shake256  ( length -- )
    _s3-length ! _s3-out-reset
    _s3-data 137 _s3-out _s3-length @ SHAKE-256
    _s3-out _s3-shake256-137-65 _s3-length @ SAMESTR? _s3-assert
    _s3-length @ _s3-canary? _s3-assert _s3-stack ;

: _s3-test-shake  ( -- )
    0 _s3-check-shake128
    1 _s3-check-shake128
    31 _s3-check-shake128
    32 _s3-check-shake128
    33 _s3-check-shake128
    63 _s3-check-shake128
    64 _s3-check-shake128
    65 _s3-check-shake128
    0 _s3-check-shake256
    1 _s3-check-shake256
    31 _s3-check-shake256
    32 _s3-check-shake256
    33 _s3-check-shake256
    63 _s3-check-shake256
    64 _s3-check-shake256
    65 _s3-check-shake256 ;

: _s3-test-shake-streams  ( -- )
    \ Cross the SHAKE-128 168-byte input rate and the 32/64-byte output
    \ windows through independently supplied segments.
    _s3-out-reset
    SHAKE-128-BEGIN
    _s3-data 7 SHAKE-128-ADD
    _s3-data 7 + 162 SHAKE-128-ADD
    _s3-out 65 SHAKE-128-END
    _s3-out _s3-shake128-169-65 65 SAMESTR? _s3-assert
    65 _s3-canary? _s3-assert _s3-stack

    \ SHAKE-256 has a 136-byte rate; 137 input bytes force the next block.
    _s3-out-reset
    SHAKE-256-BEGIN
    _s3-data 5 SHAKE-256-ADD
    _s3-data 5 + 132 SHAKE-256-ADD
    _s3-out 65 SHAKE-256-END
    _s3-out _s3-shake256-137-65 65 SAMESTR? _s3-assert
    65 _s3-canary? _s3-assert _s3-stack ;

: _s3-test-hmac  ( -- )
    _s3-out-reset
    _s3-key 200 _s3-data 137 _s3-out SHA3-256-HMAC
    _s3-out _s3-hmac-200-137 32 SAMESTR? _s3-assert
    32 _s3-canary? _s3-assert _s3-stack ;

: _s3-call-add-without-begin  ( -- ) _s3-data 1 SHA3-256-ADD ;
: _s3-call-end-without-begin  ( -- ) _s3-out SHA3-256-END ;
: _s3-call-negative-hash  ( -- ) _s3-data -1 _s3-out SHA3-256-HASH ;
: _s3-call-negative-shake  ( -- ) _s3-data 1 _s3-out -1 SHAKE-128 ;
: _s3-call-negative-stream  ( -- )
    SHA3-256-BEGIN _s3-data -1 SHA3-256-ADD ;
: _s3-call-negative-shake-stream  ( -- )
    SHAKE-128-BEGIN _s3-data -1 SHAKE-128-ADD ;
: _s3-call-negative-shake-end  ( -- )
    SHAKE-128-BEGIN _s3-out -1 SHAKE-128-END ;
: _s3-call-nested-begin  ( -- ) SHA3-512-BEGIN ;
: _s3-call-one-shot-during-stream  ( -- )
    _s3-data 1 _s3-out SHA3-256-HASH ;
: _s3-call-cross-add  ( -- ) _s3-data 1 SHA3-512-ADD ;
: _s3-call-cross-end  ( -- ) _s3-out SHA3-512-END ;
: _s3-call-cross-shake-add  ( -- ) _s3-data 1 SHAKE-256-ADD ;
: _s3-call-cross-shake-end  ( -- ) _s3-out 1 SHAKE-256-END ;
: _s3-call-one-shot-during-direct  ( -- )
    _s3-data 1 _s3-out SHA3-256-HASH ;

: _s3-assert-recovered  ( -- )
    _s3-data 137 _s3-out SHA3-256-HASH
    _s3-out _s3-256-137 32 SAMESTR? _s3-assert ;

: _s3-test-errors  ( -- )
    4 SHA3-BEGIN 3 = _s3-assert
    _s3-data 1 SHA3-UPDATE 2 = _s3-assert
    ['] _s3-call-add-without-begin CATCH -258 = _s3-assert
    ['] _s3-call-end-without-begin CATCH -258 = _s3-assert
    ['] _s3-call-negative-hash CATCH 3 = _s3-assert
    _s3-assert-recovered
    ['] _s3-call-negative-shake CATCH 3 = _s3-assert
    _s3-assert-recovered
    ['] _s3-call-negative-stream CATCH 3 = _s3-assert
    _s3-assert-recovered
    ['] _s3-call-negative-shake-stream CATCH 3 = _s3-assert
    _s3-assert-recovered
    ['] _s3-call-negative-shake-end CATCH 3 = _s3-assert
    _s3-assert-recovered

    SHA3-256-BEGIN
    ['] _s3-call-nested-begin CATCH -258 = _s3-assert
    ['] _s3-call-one-shot-during-stream CATCH -258 = _s3-assert
    ['] _s3-call-cross-add CATCH -258 = _s3-assert
    ['] _s3-call-cross-end CATCH -258 = _s3-assert
    _s3-data 137 SHA3-256-ADD
    _s3-out SHA3-256-END
    _s3-out _s3-256-137 32 SAMESTR? _s3-assert

    SHAKE-128-BEGIN
    ['] _s3-call-cross-shake-add CATCH -258 = _s3-assert
    ['] _s3-call-cross-shake-end CATCH -258 = _s3-assert
    _s3-data 169 SHAKE-128-ADD
    _s3-out 65 SHAKE-128-END
    _s3-out _s3-shake128-169-65 65 SAMESTR? _s3-assert

    \ BEGIN status 2 belongs to the pre-existing direct transaction.  The
    \ rejected public call must not clear it.
    SHA3-256-MODE SHA3-BEGIN _s3-status-ok
    _s3-data 7 SHA3-UPDATE _s3-status-ok
    ['] _s3-call-one-shot-during-direct CATCH 2 = _s3-assert
    _s3-data 7 + 130 SHA3-UPDATE _s3-status-ok
    _s3-out SHA3-FINAL _s3-status-ok
    _s3-out _s3-256-137 32 SAMESTR? _s3-assert
    _s3-stack ;

: _S3C-RUN  ( -- )
    0 _s3-fails ! 0 _s3-checks ! DEPTH _s3-depth !
    _s3-init-input
    _s3-test-fixed
    _s3-test-shake
    _s3-test-shake-streams
    _s3-test-hmac
    _s3-test-errors
    _s3-stack
    _s3-fails @ 0= IF
        ." SHA3 CHECKED CONTRACTS PASS " _s3-checks @ . CR
    ELSE
        ." SHA3 CHECKED CONTRACTS FAIL " _s3-fails @ .
        ." / " _s3-checks @ . CR
    THEN ;
