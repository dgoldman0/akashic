\ hmac-sha256-test.f - Focused generic HMAC-SHA-256 contracts

PROVIDED akashic-hmac-sha256-test

VARIABLE _h256t-fails
VARIABLE _h256t-checks
VARIABLE _h256t-depth

: _h256t-assert  ( flag -- )
    1 _h256t-checks +!
    0= IF
        1 _h256t-fails +!
        ." HMAC SHA256 ASSERT " _h256t-checks @ . CR
    THEN ;

: _h256t-stack  ( -- )
    DEPTH DUP _h256t-depth @ <> IF
        ." HMAC SHA256 STACK "
        _h256t-depth @ . ." -> " DUP . CR .S CR
    THEN
    _h256t-depth @ = _h256t-assert ;

: _h256t-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

: _h256t-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

CREATE _h256t-key-a 160 ALLOT
CREATE _h256t-message-a 160 ALLOT
CREATE _h256t-digest-a HMAC-SHA256-DIGEST-SIZE ALLOT
CREATE _h256t-digest-copy HMAC-SHA256-DIGEST-SIZE ALLOT
CREATE _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE ALLOT
CREATE _h256t-workspace-b HMAC-SHA256-WORKSPACE-SIZE ALLOT
CREATE _h256t-workspace-copy HMAC-SHA256-WORKSPACE-SIZE ALLOT

CREATE _h256t-hi-there
    0x48 C, 0x69 C, 0x20 C, 0x54 C, 0x68 C, 0x65 C, 0x72 C, 0x65 C,

CREATE _h256t-jefe
    0x4A C, 0x65 C, 0x66 C, 0x65 C,

CREATE _h256t-what
    0x77 C, 0x68 C, 0x61 C, 0x74 C, 0x20 C, 0x64 C, 0x6F C, 0x20 C,
    0x79 C, 0x61 C, 0x20 C, 0x77 C, 0x61 C, 0x6E C, 0x74 C, 0x20 C,
    0x66 C, 0x6F C, 0x72 C, 0x20 C, 0x6E C, 0x6F C, 0x74 C, 0x68 C,
    0x69 C, 0x6E C, 0x67 C, 0x3F C,

CREATE _h256t-long-message
    0x54 C, 0x65 C, 0x73 C, 0x74 C, 0x20 C, 0x55 C, 0x73 C, 0x69 C,
    0x6E C, 0x67 C, 0x20 C, 0x4C C, 0x61 C, 0x72 C, 0x67 C, 0x65 C,
    0x72 C, 0x20 C, 0x54 C, 0x68 C, 0x61 C, 0x6E C, 0x20 C, 0x42 C,
    0x6C C, 0x6F C, 0x63 C, 0x6B C, 0x2D C, 0x53 C, 0x69 C, 0x7A C,
    0x65 C, 0x20 C, 0x4B C, 0x65 C, 0x79 C, 0x20 C, 0x2D C, 0x20 C,
    0x48 C, 0x61 C, 0x73 C, 0x68 C, 0x20 C, 0x4B C, 0x65 C, 0x79 C,
    0x20 C, 0x46 C, 0x69 C, 0x72 C, 0x73 C, 0x74 C,

CREATE _h256t-expected-1
    0xB0 C, 0x34 C, 0x4C C, 0x61 C, 0xD8 C, 0xDB C, 0x38 C, 0x53 C,
    0x5C C, 0xA8 C, 0xAF C, 0xCE C, 0xAF C, 0x0B C, 0xF1 C, 0x2B C,
    0x88 C, 0x1D C, 0xC2 C, 0x00 C, 0xC9 C, 0x83 C, 0x3D C, 0xA7 C,
    0x26 C, 0xE9 C, 0x37 C, 0x6C C, 0x2E C, 0x32 C, 0xCF C, 0xF7 C,

CREATE _h256t-expected-2
    0x5B C, 0xDC C, 0xC1 C, 0x46 C, 0xBF C, 0x60 C, 0x75 C, 0x4E C,
    0x6A C, 0x04 C, 0x24 C, 0x26 C, 0x08 C, 0x95 C, 0x75 C, 0xC7 C,
    0x5A C, 0x00 C, 0x3F C, 0x08 C, 0x9D C, 0x27 C, 0x39 C, 0x83 C,
    0x9D C, 0xEC C, 0x58 C, 0xB9 C, 0x64 C, 0xEC C, 0x38 C, 0x43 C,

CREATE _h256t-expected-3
    0x77 C, 0x3E C, 0xA9 C, 0x1E C, 0x36 C, 0x80 C, 0x0E C, 0x46 C,
    0x85 C, 0x4D C, 0xB8 C, 0xEB C, 0xD0 C, 0x91 C, 0x81 C, 0xA7 C,
    0x29 C, 0x59 C, 0x09 C, 0x8B C, 0x3E C, 0xF8 C, 0xC1 C, 0x22 C,
    0xD9 C, 0x63 C, 0x55 C, 0x14 C, 0xCE C, 0xD5 C, 0x65 C, 0xFE C,

CREATE _h256t-expected-6
    0x60 C, 0xE4 C, 0x31 C, 0x59 C, 0x1E C, 0xE0 C, 0xB6 C, 0x7F C,
    0x0D C, 0x8A C, 0x26 C, 0xAA C, 0xCB C, 0xF5 C, 0xB7 C, 0x7F C,
    0x8E C, 0x0B C, 0xC6 C, 0x21 C, 0x37 C, 0x28 C, 0xC5 C, 0x14 C,
    0x05 C, 0x46 C, 0x04 C, 0x0F C, 0x0E C, 0xE3 C, 0x7F C, 0x54 C,

CREATE _h256t-expected-empty
    0xB6 C, 0x13 C, 0x67 C, 0x9A C, 0x08 C, 0x14 C, 0xD9 C, 0xEC C,
    0x77 C, 0x2F C, 0x95 C, 0xD7 C, 0x78 C, 0xC3 C, 0x5F C, 0xC5 C,
    0xFF C, 0x16 C, 0x97 C, 0xC4 C, 0x93 C, 0x71 C, 0x56 C, 0x53 C,
    0xC6 C, 0xC7 C, 0x12 C, 0x14 C, 0x42 C, 0x92 C, 0xC5 C, 0xAD C,

: _h256t-snapshots  ( -- )
    _h256t-digest-a _h256t-digest-copy HMAC-SHA256-DIGEST-SIZE MOVE
    _h256t-workspace-a _h256t-workspace-copy
        HMAC-SHA256-WORKSPACE-SIZE MOVE ;

: _h256t-unchanged?  ( -- flag )
    _h256t-digest-a _h256t-digest-copy HMAC-SHA256-DIGEST-SIZE
        _h256t-bytes=
    _h256t-workspace-a _h256t-workspace-copy
        HMAC-SHA256-WORKSPACE-SIZE _h256t-bytes= AND ;

: _h256t-run-vector  ( key key-u message message-u expected workspace -- )
    SWAP >R
    _h256t-digest-a SWAP
    HMAC-SHA256 HMAC-SHA256-S-OK = _h256t-assert
    _h256t-digest-a R@ HMAC-SHA256-DIGEST-SIZE
        _h256t-bytes=
        DUP 0= IF
            ." HMAC SHA256 GOT " _h256t-digest-a SHA256-. CR
        THEN
        _h256t-assert
    R> DROP ;

: _h256t-test-vectors  ( -- )
    HMAC-SHA256-DIGEST-SIZE 32 = _h256t-assert
    HMAC-SHA256-WORKSPACE-SIZE 192 = _h256t-assert
    HMAC-SHA256-S-CRYPTO HMAC-SHA256-STATUS-VALID? _h256t-assert
    HMAC-SHA256-S-CRYPTO 1+
        HMAC-SHA256-STATUS-VALID? 0= _h256t-assert

    _h256t-key-a 20 0x0B FILL
    _h256t-key-a 20 _h256t-hi-there 8
        _h256t-expected-1 _h256t-workspace-a _h256t-run-vector

    _h256t-jefe 4 _h256t-what 28
        _h256t-expected-2 _h256t-workspace-a _h256t-run-vector

    _h256t-key-a 20 0xAA FILL
    _h256t-message-a 50 0xDD FILL
    _h256t-key-a 20 _h256t-message-a 50
        _h256t-expected-3 _h256t-workspace-b _h256t-run-vector

    _h256t-key-a 131 0xAA FILL
    _h256t-key-a 131 _h256t-long-message 54
        _h256t-expected-6 _h256t-workspace-a _h256t-run-vector

    0 0 0 0 _h256t-expected-empty _h256t-workspace-b
        _h256t-run-vector

    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE
        _h256t-zero? _h256t-assert
    _h256t-workspace-b HMAC-SHA256-WORKSPACE-SIZE
        _h256t-zero? _h256t-assert
    _h256t-stack ;

: _h256t-test-rejections  ( -- )
    _h256t-digest-a HMAC-SHA256-DIGEST-SIZE 0xA5 FILL
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE 0x5A FILL
    _h256t-snapshots
    0 1 0 0 _h256t-digest-a _h256t-workspace-a HMAC-SHA256
        HMAC-SHA256-S-INVALID = _h256t-assert
    _h256t-unchanged? _h256t-assert

    _h256t-snapshots
    _h256t-key-a -1 0 0 _h256t-digest-a _h256t-workspace-a HMAC-SHA256
        HMAC-SHA256-S-INVALID = _h256t-assert
    _h256t-unchanged? _h256t-assert

    _h256t-snapshots
    _h256t-key-a 1 0 0
        _h256t-workspace-a _h256t-workspace-a HMAC-SHA256
        HMAC-SHA256-S-ALIAS = _h256t-assert
    _h256t-unchanged? _h256t-assert

    _h256t-snapshots
    _h256t-workspace-a 1 0 0
        _h256t-digest-a _h256t-workspace-a HMAC-SHA256
        HMAC-SHA256-S-ALIAS = _h256t-assert
    _h256t-unchanged? _h256t-assert

    _h256t-snapshots
    _h256t-digest-a 1 0 0
        _h256t-digest-a _h256t-workspace-a HMAC-SHA256
        HMAC-SHA256-S-ALIAS = _h256t-assert
    _h256t-unchanged? _h256t-assert

    \ An admitted message that the BIOS cannot read must become the HMAC
    \ layer's CRYPTO status without publishing a digest.
    _h256t-digest-a HMAC-SHA256-DIGEST-SIZE 0xA5 FILL
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE 0x5A FILL
    _h256t-snapshots
    _h256t-jefe 4
        EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        _h256t-digest-a _h256t-workspace-a HMAC-SHA256
        HMAC-SHA256-S-CRYPTO = _h256t-assert
    _h256t-digest-a _h256t-digest-copy HMAC-SHA256-DIGEST-SIZE
        _h256t-bytes= _h256t-assert
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE
        _h256t-zero? _h256t-assert
    _h256t-stack ;

: _h256t-test-clear  ( -- )
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE 0xA5 FILL
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-CLEAR
        HMAC-SHA256-S-OK = _h256t-assert
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE
        _h256t-zero? _h256t-assert
    0 HMAC-SHA256-WORKSPACE-CLEAR
        HMAC-SHA256-S-INVALID = _h256t-assert
    _h256t-stack ;

: _h256t-throw
  ( key key-u message message-u digest workspace -- workspace status )
    -779 THROW ;

: _h256t-test-compute-throw-cleanup  ( -- )
    _h256t-digest-a HMAC-SHA256-DIGEST-SIZE 0xA5 FILL
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE 0x5A FILL
    _h256t-snapshots
    _h256t-jefe 4 _h256t-what 28
        _h256t-digest-a _h256t-workspace-a
        ['] _h256t-throw _H256-COMPUTE-CALL
        DUP IF _H256-CLEAR-RETURN THEN
        HMAC-SHA256-S-CRYPTO = _h256t-assert
    _h256t-digest-a _h256t-digest-copy HMAC-SHA256-DIGEST-SIZE
        _h256t-bytes= _h256t-assert
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE
        _h256t-zero? _h256t-assert
    _h256t-stack ;

: _h256t-publication-throw  ( -- )
    _h256t-workspace-a _H256-PUBLISH-CLEAR DROP ;

: _h256t-test-publication-throw-cleanup  ( -- )
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE 0x5A FILL
    EXT-MEM-BASE EXT-MEM-SIZE +
        _h256t-workspace-a _H256.DIGEST !
    ['] _h256t-publication-throw CATCH
        0<> _h256t-assert
    _h256t-workspace-a HMAC-SHA256-WORKSPACE-SIZE
        _h256t-zero? _h256t-assert
    _h256t-stack ;

: _h256t-cleanup-throw  ( -- )
    EXT-MEM-BASE EXT-MEM-SIZE +
        HMAC-SHA256-S-CRYPTO _H256-CLEAR-RETURN DROP ;

: _h256t-test-cleanup-throw-propagates  ( -- )
    ['] _h256t-cleanup-throw CATCH
        0<> _h256t-assert
    _h256t-stack ;

: _H256T-RUN  ( -- )
    0 _h256t-fails !
    0 _h256t-checks !
    DEPTH _h256t-depth !
    _h256t-test-vectors
    _h256t-test-rejections
    _h256t-test-compute-throw-cleanup
    _h256t-test-publication-throw-cleanup
    _h256t-test-cleanup-throw-propagates
    _h256t-test-clear
    _h256t-stack
    _h256t-fails @ 0= IF
        ." HMAC SHA256 PASS " _h256t-checks @ . CR
    ELSE
        ." HMAC SHA256 FAIL " _h256t-fails @ . CR
    THEN ;
