\ ecdsa-p256-test.f - Focused generic deterministic ECDSA-P256 contracts

PROVIDED akashic-ecdsa-p256-test

VARIABLE _ept-fails
VARIABLE _ept-checks
VARIABLE _ept-depth

: _ept-assert  ( flag -- )
    1 _ept-checks +!
    0= IF
        1 _ept-fails +!
        ." ECDSA P256 ASSERT " _ept-checks @ . CR
    THEN ;

: _ept-stack  ( -- )
    DEPTH DUP _ept-depth @ <> IF
        ." ECDSA P256 STACK "
        _ept-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ept-depth @ = _ept-assert ;

: _ept-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

: _ept-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ RFC 6979 Appendix A.2.5 private and public key.
CREATE _ept-private
    0xC9 C, 0xAF C, 0xA9 C, 0xD8 C, 0x45 C, 0xBA C, 0x75 C, 0x16 C,
    0x6B C, 0x5C C, 0x21 C, 0x57 C, 0x67 C, 0xB1 C, 0xD6 C, 0x93 C,
    0x4E C, 0x50 C, 0xC3 C, 0xDB C, 0x36 C, 0xE8 C, 0x9B C, 0x12 C,
    0x7B C, 0x8A C, 0x62 C, 0x2B C, 0x12 C, 0x0F C, 0x67 C, 0x21 C,

CREATE _ept-public
    0x04 C,
    0x60 C, 0xFE C, 0xD4 C, 0xBA C, 0x25 C, 0x5A C, 0x9D C, 0x31 C,
    0xC9 C, 0x61 C, 0xEB C, 0x74 C, 0xC6 C, 0x35 C, 0x6D C, 0x68 C,
    0xC0 C, 0x49 C, 0xB8 C, 0x92 C, 0x3B C, 0x61 C, 0xFA C, 0x6C C,
    0xE6 C, 0x69 C, 0x62 C, 0x2E C, 0x60 C, 0xF2 C, 0x9F C, 0xB6 C,
    0x79 C, 0x03 C, 0xFE C, 0x10 C, 0x08 C, 0xB8 C, 0xBC C, 0x99 C,
    0xA4 C, 0x1A C, 0xE9 C, 0xE9 C, 0x56 C, 0x28 C, 0xBC C, 0x64 C,
    0xF2 C, 0xF1 C, 0xB2 C, 0x0C C, 0x2D C, 0x7E C, 0x9F C, 0x51 C,
    0x77 C, 0xA3 C, 0xC2 C, 0x94 C, 0xD4 C, 0x46 C, 0x22 C, 0x99 C,

\ SHA-256("sample").
CREATE _ept-hash-sample
    0xAF C, 0x2B C, 0xDB C, 0xE1 C, 0xAA C, 0x9B C, 0x6E C, 0xC1 C,
    0xE2 C, 0xAD C, 0xE1 C, 0xD6 C, 0x94 C, 0xF4 C, 0x1F C, 0xC7 C,
    0x1A C, 0x83 C, 0x1D C, 0x02 C, 0x68 C, 0xE9 C, 0x89 C, 0x15 C,
    0x62 C, 0x11 C, 0x3D C, 0x8A C, 0x62 C, 0xAD C, 0xD1 C, 0xBF C,

\ RFC 6979 A.2.5, SHA-256, message "sample".  The published s starts
\ with F7 and is intentionally retained rather than low-S normalized.
CREATE _ept-signature-sample
    0xEF C, 0xD4 C, 0x8B C, 0x2A C, 0xAC C, 0xB6 C, 0xA8 C, 0xFD C,
    0x11 C, 0x40 C, 0xDD C, 0x9C C, 0xD4 C, 0x5E C, 0x81 C, 0xD6 C,
    0x9D C, 0x2C C, 0x87 C, 0x7B C, 0x56 C, 0xAA C, 0xF9 C, 0x91 C,
    0xC3 C, 0x4D C, 0x0E C, 0xA8 C, 0x4E C, 0xAF C, 0x37 C, 0x16 C,
    0xF7 C, 0xCB C, 0x1C C, 0x94 C, 0x2D C, 0x65 C, 0x7C C, 0x41 C,
    0xD4 C, 0x36 C, 0xC7 C, 0xA1 C, 0xB6 C, 0xE2 C, 0x9F C, 0x65 C,
    0xF3 C, 0xE9 C, 0x00 C, 0xDB C, 0xB9 C, 0xAF C, 0xF4 C, 0x06 C,
    0x4D C, 0xC4 C, 0xAB C, 0x2F C, 0x84 C, 0x3A C, 0xCD C, 0xA8 C,

\ SHA-256("test").
CREATE _ept-hash-test
    0x9F C, 0x86 C, 0xD0 C, 0x81 C, 0x88 C, 0x4C C, 0x7D C, 0x65 C,
    0x9A C, 0x2F C, 0xEA C, 0xA0 C, 0xC5 C, 0x5A C, 0xD0 C, 0x15 C,
    0xA3 C, 0xBF C, 0x4F C, 0x1B C, 0x2B C, 0x0B C, 0x82 C, 0x2C C,
    0xD1 C, 0x5D C, 0x6C C, 0x15 C, 0xB0 C, 0xF0 C, 0x0A C, 0x08 C,

\ RFC 6979 A.2.5, SHA-256, message "test".
CREATE _ept-signature-test
    0xF1 C, 0xAB C, 0xB0 C, 0x23 C, 0x51 C, 0x83 C, 0x51 C, 0xCD C,
    0x71 C, 0xD8 C, 0x81 C, 0x56 C, 0x7B C, 0x1E C, 0xA6 C, 0x63 C,
    0xED C, 0x3E C, 0xFC C, 0xF6 C, 0xC5 C, 0x13 C, 0x2B C, 0x35 C,
    0x4F C, 0x28 C, 0xD3 C, 0xB0 C, 0xB7 C, 0xD3 C, 0x83 C, 0x67 C,
    0x01 C, 0x9F C, 0x41 C, 0x13 C, 0x74 C, 0x2A C, 0x2B C, 0x14 C,
    0xBD C, 0x25 C, 0x92 C, 0x6B C, 0x49 C, 0xC6 C, 0x49 C, 0x15 C,
    0x5F C, 0x26 C, 0x7E C, 0x60 C, 0xD3 C, 0x81 C, 0x4B C, 0x4C C,
    0x0C C, 0xC8 C, 0x42 C, 0x50 C, 0xE4 C, 0x6F C, 0x00 C, 0x83 C,

CREATE _ept-order-be
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,
    0xBC C, 0xE6 C, 0xFA C, 0xAD C, 0xA7 C, 0x17 C, 0x9E C, 0x84 C,
    0xF3 C, 0xB9 C, 0xCA C, 0xC2 C, 0xFC C, 0x63 C, 0x25 C, 0x51 C,

\ Independent RFC 6979 retry transition for K=00*32 and V=01*32:
\   K' = HMAC(K, V || 00)
\   V' = HMAC(K', V)
CREATE _ept-reject-k
    0xA3 C, 0xE7 C, 0x77 C, 0x6D C, 0xD1 C, 0xFC C, 0x68 C, 0x0D C,
    0x83 C, 0xB0 C, 0x95 C, 0x51 C, 0xD2 C, 0xB1 C, 0x17 C, 0x7A C,
    0x5C C, 0x81 C, 0x0B C, 0xDB C, 0xDB C, 0x61 C, 0xB0 C, 0x23 C,
    0x90 C, 0x9C C, 0x6F C, 0x0A C, 0x42 C, 0xC2 C, 0xD2 C, 0x04 C,

CREATE _ept-reject-v
    0xC5 C, 0x60 C, 0x9C C, 0xE6 C, 0xCC C, 0x1B C, 0xAF C, 0xD6 C,
    0x8C C, 0x41 C, 0x0C C, 0xB6 C, 0x72 C, 0x45 C, 0xF8 C, 0x0A C,
    0xB4 C, 0x47 C, 0x89 C, 0xC5 C, 0x1A C, 0x9B C, 0x30 C, 0x0B C,
    0xDE C, 0x0F C, 0xB5 C, 0x9D C, 0x1E C, 0x15 C, 0x58 C, 0x32 C,

CREATE _ept-private-zero ECDSA-P256-PRIVATE-SIZE ALLOT
CREATE _ept-public-work ECDSA-P256-PUBLIC-SIZE ALLOT
CREATE _ept-signature ECDSA-P256-SIGNATURE-SIZE ALLOT
CREATE _ept-signature-snapshot ECDSA-P256-SIGNATURE-SIZE ALLOT
CREATE _ept-workspace ECDSA-P256-WORKSPACE-SIZE ALLOT
CREATE _ept-workspace-snapshot ECDSA-P256-WORKSPACE-SIZE ALLOT

: _ept-workspace-zero?  ( -- flag )
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE _ept-zero? ;

: _ept-snapshot  ( -- )
    _ept-signature _ept-signature-snapshot
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-workspace _ept-workspace-snapshot
        ECDSA-P256-WORKSPACE-SIZE MOVE ;

: _ept-signature-unchanged?  ( -- flag )
    _ept-signature _ept-signature-snapshot
        ECDSA-P256-SIGNATURE-SIZE _ept-bytes= ;

: _ept-workspace-unchanged?  ( -- flag )
    _ept-workspace _ept-workspace-snapshot
        ECDSA-P256-WORKSPACE-SIZE _ept-bytes= ;

: _ept-sign-vector  ( hash expected -- )
    >R
    _ept-private _ept-signature _ept-workspace
    ECDSA-P256-SIGN-HASH
    ECDSA-P256-S-OK = _ept-assert
    _ept-signature R@ ECDSA-P256-SIGNATURE-SIZE
        _ept-bytes= _ept-assert
    _ept-workspace-zero? _ept-assert
    R> DROP ;

: _ept-verify-vector  ( hash signature -- )
    _ept-public SWAP _ept-workspace
    ECDSA-P256-VERIFY-HASH
    ECDSA-P256-S-OK = _ept-assert
    _ept-assert
    _ept-workspace-zero? _ept-assert ;

: _ept-test-vocabulary  ( -- )
    ECDSA-P256-HASH-SIZE 32 = _ept-assert
    ECDSA-P256-PRIVATE-SIZE 32 = _ept-assert
    ECDSA-P256-PUBLIC-SIZE 65 = _ept-assert
    ECDSA-P256-SIGNATURE-SIZE 64 = _ept-assert
    ECDSA-P256-WORKSPACE-SIZE 2064 = _ept-assert
    ECDSA-P256-S-RANGE 1 = _ept-assert
    ECDSA-P256-S-PROTECTED 2 = _ept-assert
    ECDSA-P256-S-PLATFORM 3 = _ept-assert
    ECDSA-P256-S-INTERNAL 10 = _ept-assert
    ECDSA-P256-S-INTERNAL
        ECDSA-P256-STATUS-VALID? _ept-assert
    ECDSA-P256-S-INTERNAL 1+
        ECDSA-P256-STATUS-VALID? 0= _ept-assert

    CALLER-SPAN-S-OK _ECP-CALLER>STATUS
        ECDSA-P256-S-OK = _ept-assert
    CALLER-SPAN-S-RANGE _ECP-CALLER>STATUS
        ECDSA-P256-S-RANGE = _ept-assert
    CALLER-SPAN-S-PROTECTED _ECP-CALLER>STATUS
        ECDSA-P256-S-PROTECTED = _ept-assert
    CALLER-SPAN-S-PLATFORM _ECP-CALLER>STATUS
        ECDSA-P256-S-PLATFORM = _ept-assert
    99 _ECP-CALLER>STATUS
        ECDSA-P256-S-PLATFORM = _ept-assert

    P256-S-ALIAS _ECP-P256>STATUS
        ECDSA-P256-S-ALIAS = _ept-assert
    P256-S-PRIVATE _ECP-P256>STATUS
        ECDSA-P256-S-INTERNAL = _ept-assert
    P256-S-PUBLIC _ECP-P256>STATUS
        ECDSA-P256-S-PUBLIC = _ept-assert
    P256-S-SCALAR _ECP-P256>STATUS
        ECDSA-P256-S-INTERNAL = _ept-assert
    P256-S-RANGE _ECP-P256>STATUS
        ECDSA-P256-S-RANGE = _ept-assert
    P256-S-PROTECTED _ECP-P256>STATUS
        ECDSA-P256-S-PROTECTED = _ept-assert
    P256-S-PLATFORM _ECP-P256>STATUS
        ECDSA-P256-S-PLATFORM = _ept-assert
    P256-S-ENTROPY _ECP-P256>STATUS
        ECDSA-P256-S-INTERNAL = _ept-assert
    P256-S-IDENTITY _ECP-P256>STATUS
        ECDSA-P256-S-INTERNAL = _ept-assert
    99 _ECP-P256>STATUS
        ECDSA-P256-S-INTERNAL = _ept-assert
    _ept-stack ;

: _ept-test-rfc6979  ( -- )
    _ept-hash-sample _ept-signature-sample _ept-sign-vector
    _ept-hash-sample _ept-signature-sample _ept-verify-vector

    _ept-hash-test _ept-signature-test _ept-sign-vector
    _ept-stack ;

: _ept-test-rfc6979-reject  ( -- )
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0 FILL
    _ept-workspace _ECPW.V ECDSA-P256-HASH-SIZE 1 FILL
    _ept-workspace _ECP-RFC6979-REJECT
        ECDSA-P256-S-OK = _ept-assert
    _ept-workspace _ECPW.K _ept-reject-k ECDSA-P256-HASH-SIZE
        _ept-bytes= _ept-assert
    _ept-workspace _ECPW.V _ept-reject-v ECDSA-P256-HASH-SIZE
        _ept-bytes= _ept-assert
    _ept-workspace ECDSA-P256-WORKSPACE-CLEAR
        ECDSA-P256-S-OK = _ept-assert
    _ept-workspace-zero? _ept-assert
    _ept-stack ;

: _ept-test-mismatch  ( -- )
    _ept-signature-sample _ept-signature
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-signature 63 + DUP C@ 1 XOR SWAP C!
    _ept-hash-sample _ept-public _ept-signature _ept-workspace
        ECDSA-P256-VERIFY-HASH
        ECDSA-P256-S-OK = _ept-assert
        0= _ept-assert
    _ept-workspace-zero? _ept-assert
    _ept-stack ;

: _ept-expect-bad-signature  ( -- )
    _ept-hash-sample _ept-public _ept-signature _ept-workspace
        ECDSA-P256-VERIFY-HASH
        ECDSA-P256-S-SIGNATURE = _ept-assert
        0= _ept-assert
    _ept-workspace-zero? _ept-assert ;

: _ept-test-strict-inputs  ( -- )
    \ Independently reject each zero/order boundary for r and s.
    _ept-signature-sample _ept-signature
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-signature 32 0 FILL
    _ept-expect-bad-signature

    _ept-signature-sample _ept-signature
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-order-be _ept-signature 32 MOVE
    _ept-expect-bad-signature

    _ept-signature-sample _ept-signature
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-signature 32 + 32 0 FILL
    _ept-expect-bad-signature

    _ept-signature-sample _ept-signature
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-order-be _ept-signature 32 + 32 MOVE
    _ept-expect-bad-signature

    \ A malformed SEC 1 point is a public-key error.
    _ept-public _ept-public-work ECDSA-P256-PUBLIC-SIZE MOVE
    0x05 _ept-public-work C!
    _ept-signature-sample _ept-signature
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-hash-sample _ept-public-work _ept-signature _ept-workspace
        ECDSA-P256-VERIFY-HASH
        ECDSA-P256-S-PUBLIC = _ept-assert
        0= _ept-assert
    _ept-workspace-zero? _ept-assert

    \ A zero private scalar is admitted geometry but rejected key material.
    _ept-private-zero ECDSA-P256-PRIVATE-SIZE 0 FILL
    _ept-signature ECDSA-P256-SIGNATURE-SIZE 0xA5 FILL
    _ept-signature _ept-signature-snapshot
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0x5A FILL
    _ept-hash-sample _ept-private-zero _ept-signature _ept-workspace
        ECDSA-P256-SIGN-HASH
        ECDSA-P256-S-PRIVATE = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-zero? _ept-assert

    \ The subgroup order itself is not a private scalar.
    _ept-signature ECDSA-P256-SIGNATURE-SIZE 0xA5 FILL
    _ept-signature _ept-signature-snapshot
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0x5A FILL
    _ept-hash-sample _ept-order-be _ept-signature _ept-workspace
        ECDSA-P256-SIGN-HASH
        ECDSA-P256-S-PRIVATE = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-zero? _ept-assert
    _ept-stack ;

: _ept-expect-sign-alias
  ( hash private signature workspace -- )
    _ept-snapshot
    ECDSA-P256-SIGN-HASH
    ECDSA-P256-S-ALIAS = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-unchanged? _ept-assert ;

: _ept-expect-verify-alias
  ( hash public signature workspace -- )
    _ept-snapshot
    ECDSA-P256-VERIFY-HASH
    ECDSA-P256-S-ALIAS = _ept-assert
    0= _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-unchanged? _ept-assert ;

: _ept-test-geometry  ( -- )
    \ Invalid pointers and aliases are rejected before workspace admission.
    _ept-signature ECDSA-P256-SIGNATURE-SIZE 0xA5 FILL
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0x5A FILL
    _ept-snapshot
    _ept-hash-sample 0 _ept-signature _ept-workspace
        ECDSA-P256-SIGN-HASH
        ECDSA-P256-S-RANGE = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-unchanged? _ept-assert

    \ Complete caller spans retain range/protection distinctions and reject
    \ before the output or workspace is admitted.
    _ept-snapshot
    EXT-MEM-BASE EXT-MEM-SIZE + 16 -
        _ept-private _ept-signature _ept-workspace
        ECDSA-P256-SIGN-HASH
        ECDSA-P256-S-RANGE = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-unchanged? _ept-assert

    _ept-snapshot
    1 _ept-private _ept-signature _ept-workspace
        ECDSA-P256-SIGN-HASH
        ECDSA-P256-S-PROTECTED = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-unchanged? _ept-assert

    _ept-snapshot
    _ept-hash-sample _ept-private _ept-workspace _ept-workspace
        ECDSA-P256-SIGN-HASH
        ECDSA-P256-S-ALIAS = _ept-assert
    _ept-workspace-unchanged? _ept-assert

    \ Every pair of borrowed/output/workspace spans is rejected on overlap.
    _ept-hash-sample _ept-hash-sample
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-signature _ept-private
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-workspace _ept-private
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-hash-sample _ept-signature
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-hash-sample _ept-workspace
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-hash-sample _ept-private
        _ept-workspace _ept-workspace _ept-expect-sign-alias

    _ept-hash-sample _ept-hash-sample
        _ept-signature _ept-workspace _ept-expect-verify-alias
    _ept-signature _ept-public
        _ept-signature _ept-workspace _ept-expect-verify-alias
    _ept-workspace _ept-public
        _ept-signature _ept-workspace _ept-expect-verify-alias
    _ept-hash-sample _ept-signature
        _ept-signature _ept-workspace _ept-expect-verify-alias
    _ept-hash-sample _ept-workspace
        _ept-signature _ept-workspace _ept-expect-verify-alias
    _ept-hash-sample _ept-public
        _ept-workspace _ept-workspace _ept-expect-verify-alias

    \ ECDSA's immutable order tables and every exposed subordinate reserved
    \ footprint are never caller operands, even for an apparent read.
    _ECP-N _ept-private
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-hash-sample _ECP-PINV0
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _fld-guard _ept-private
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-hash-sample _P256-GX
        _ept-signature _ept-workspace _ept-expect-sign-alias
    _ept-hash-sample _ept-private
        _sha256-guard _ept-workspace _ept-expect-sign-alias
    _ept-stack ;

: _ept-throw-sign
  ( hash private signature workspace -- status )
    -777 THROW ;

: _ept-throw-verify
  ( hash public signature workspace -- valid? status )
    -778 THROW ;

: _ept-throw-wipe  ( workspace -- )
    -779 THROW ;

: _ept-throw-publish  ( workspace -- workspace )
    -780 THROW ;

: _ept-call-throw-sign  ( -- )
    _ept-hash-sample _ept-private _ept-signature _ept-workspace
        ['] _ept-throw-sign _ECP-SIGN-CALL
    2DROP ;

: _ept-call-throw-verify  ( -- )
    _ept-hash-sample _ept-public _ept-signature _ept-workspace
        ['] _ept-throw-verify _ECP-VERIFY-CALL
    2DROP DROP ;

: _ept-call-throw-publish  ( -- )
    _ept-workspace ['] _ept-throw-publish
        _ECP-SIGN-PUBLISH-CLEAR
    DROP ;

: _ept-call-throw-cleanup-status  ( -- )
    ECDSA-P256-S-PRIVATE _ept-workspace ['] _ept-throw-wipe
        _ECP-CLEANUP-STATUS
    DROP ;

: _ept-call-throw-cleanup-result  ( -- )
    -1 ECDSA-P256-S-OK _ept-workspace ['] _ept-throw-wipe
        _ECP-CLEANUP-RESULT
    2DROP ;

: _ept-test-throw-cleanup  ( -- )
    _ept-signature ECDSA-P256-SIGNATURE-SIZE 0x3C FILL
    _ept-signature _ept-signature-snapshot
        ECDSA-P256-SIGNATURE-SIZE MOVE
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0xA5 FILL
    ['] _ept-call-throw-sign CATCH -777 = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-zero? _ept-assert
    _ept-stack

    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0xA5 FILL
    ['] _ept-call-throw-verify CATCH -778 = _ept-assert
    _ept-workspace-zero? _ept-assert
    _ept-stack

    \ A publication exception is never converted to a status.  The outer
    \ secret workspace is still wiped before the original THROW is reissued.
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0xA5 FILL
    ['] _ept-call-throw-publish CATCH -780 = _ept-assert
    _ept-signature-unchanged? _ept-assert
    _ept-workspace-zero? _ept-assert
    _ept-stack ;

: _ept-test-cleanup-propagation  ( -- )
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0xA5 FILL
    _ept-snapshot
    ['] _ept-call-throw-cleanup-status CATCH -779 = _ept-assert
    _ept-workspace-unchanged? _ept-assert

    ['] _ept-call-throw-cleanup-result CATCH -779 = _ept-assert
    _ept-workspace-unchanged? _ept-assert
    _ept-stack ;

: _ept-test-clear  ( -- )
    _ept-workspace ECDSA-P256-WORKSPACE-SIZE 0xA5 FILL
    _ept-workspace ECDSA-P256-WORKSPACE-CLEAR
        ECDSA-P256-S-OK = _ept-assert
    _ept-workspace-zero? _ept-assert
    0 ECDSA-P256-WORKSPACE-CLEAR
        ECDSA-P256-S-RANGE = _ept-assert
    1 ECDSA-P256-WORKSPACE-CLEAR
        ECDSA-P256-S-PROTECTED = _ept-assert
    _ept-stack ;

: _EPT-RUN  ( -- )
    0 _ept-fails !
    0 _ept-checks !
    DEPTH _ept-depth !
    _ept-test-vocabulary
    _ept-test-rfc6979-reject
    _ept-test-rfc6979
    _ept-test-mismatch
    _ept-test-strict-inputs
    _ept-test-geometry
    _ept-test-throw-cleanup
    _ept-test-cleanup-propagation
    _ept-test-clear
    _ept-stack
    _ept-fails @ 0= IF
        ." ECDSA P256 PASS " _ept-checks @ . CR
    ELSE
        ." ECDSA P256 FAIL " _ept-fails @ .
        ." / " _ept-checks @ . CR
    THEN ;
