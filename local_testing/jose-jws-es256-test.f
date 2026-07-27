\ jose-jws-es256-test.f - Strict generic compact-JWS ES256 contracts

PROVIDED akashic-jose-jws-es256-test

VARIABLE _jjwst-fails
VARIABLE _jjwst-checks
VARIABLE _jjwst-depth

: _jjwst-assert  ( flag -- )
    1 _jjwst-checks +!
    0= IF
        1 _jjwst-fails +!
        ." JOSE JWS ES256 ASSERT " _jjwst-checks @ . CR
    THEN ;

: _jjwst-stack  ( -- )
    DEPTH DUP _jjwst-depth @ <> IF
        ." JOSE JWS ES256 STACK "
        _jjwst-depth @ . ." -> " DUP . CR .S CR
    THEN
    _jjwst-depth @ = _jjwst-assert ;

: _jjwst-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

: _jjwst-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _jjwst-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ The signing vector uses the RFC 7515 Appendix A.3 P-256 key, but a
\ different protected header and payload.  Its deterministic RFC 6979
\ signature was independently derived with a standalone integer P-256
\ implementation.  The Python qualification recomputes it independently.

CREATE _jjwst-private
    0x8E C, 0x9B C, 0x10 C, 0x9E C, 0x71 C, 0x90 C, 0x98 C, 0xBF C,
    0x98 C, 0x04 C, 0x87 C, 0xDF C, 0x1F C, 0x5D C, 0x77 C, 0xE9 C,
    0xCB C, 0x29 C, 0x60 C, 0x6E C, 0xBE C, 0xD2 C, 0x26 C, 0x3B C,
    0x5F C, 0x57 C, 0xC2 C, 0x13 C, 0xDF C, 0x84 C, 0xF4 C, 0xB2 C,

CREATE _jjwst-public
    0x04 C, 0x7F C, 0xCD C, 0xCE C, 0x27 C, 0x70 C, 0xF6 C, 0xC4 C,
    0x5D C, 0x41 C, 0x83 C, 0xCB C, 0xEE C, 0x6F C, 0xDB C, 0x4B C,
    0x7B C, 0x58 C, 0x07 C, 0x33 C, 0x35 C, 0x7B C, 0xE9 C, 0xEF C,
    0x13 C, 0xBA C, 0xCF C, 0x6E C, 0x3C C, 0x7B C, 0xD1 C, 0x54 C,
    0x45 C, 0xC7 C, 0xF1 C, 0x44 C, 0xCD C, 0x1B C, 0xBD C, 0x9B C,
    0x7E C, 0x87 C, 0x2C C, 0xDF C, 0xED C, 0xB9 C, 0xEE C, 0xB9 C,
    0xF4 C, 0xB3 C, 0x69 C, 0x5D C, 0x6E C, 0xA9 C, 0x0B C, 0x24 C,
    0xAD C, 0x8A C, 0x46 C, 0x23 C, 0x28 C, 0x85 C, 0x88 C, 0xE5 C,
    0xAD C,

CREATE _jjwst-header
    0x7B C, 0x22 C, 0x61 C, 0x6C C, 0x67 C, 0x22 C, 0x3A C, 0x22 C,
    0x45 C, 0x53 C, 0x32 C, 0x35 C, 0x36 C, 0x22 C, 0x2C C, 0x22 C,
    0x74 C, 0x79 C, 0x70 C, 0x22 C, 0x3A C, 0x22 C, 0x4A C, 0x57 C,
    0x54 C, 0x22 C, 0x7D C,

CREATE _jjwst-payload
    0x69 C, 0x6E C, 0x64 C, 0x65 C, 0x70 C, 0x65 C, 0x6E C, 0x64 C,
    0x65 C, 0x6E C, 0x74 C, 0x20 C, 0x63 C, 0x6F C, 0x6D C, 0x70 C,
    0x61 C, 0x63 C, 0x74 C, 0x20 C, 0x4A C, 0x57 C, 0x53 C, 0x20 C,
    0x66 C, 0x69 C, 0x78 C, 0x74 C, 0x75 C, 0x72 C, 0x65 C,

CREATE _jjwst-expected-compact
    0x65 C, 0x79 C, 0x4A C, 0x68 C, 0x62 C, 0x47 C, 0x63 C, 0x69 C,
    0x4F C, 0x69 C, 0x4A C, 0x46 C, 0x55 C, 0x7A C, 0x49 C, 0x31 C,
    0x4E C, 0x69 C, 0x49 C, 0x73 C, 0x49 C, 0x6E C, 0x52 C, 0x35 C,
    0x63 C, 0x43 C, 0x49 C, 0x36 C, 0x49 C, 0x6B C, 0x70 C, 0x58 C,
    0x56 C, 0x43 C, 0x4A C, 0x39 C, 0x2E C, 0x61 C, 0x57 C, 0x35 C,
    0x6B C, 0x5A C, 0x58 C, 0x42 C, 0x6C C, 0x62 C, 0x6D C, 0x52 C,
    0x6C C, 0x62 C, 0x6E C, 0x51 C, 0x67 C, 0x59 C, 0x32 C, 0x39 C,
    0x74 C, 0x63 C, 0x47 C, 0x46 C, 0x6A C, 0x64 C, 0x43 C, 0x42 C,
    0x4B C, 0x56 C, 0x31 C, 0x4D C, 0x67 C, 0x5A C, 0x6D C, 0x6C C,
    0x34 C, 0x64 C, 0x48 C, 0x56 C, 0x79 C, 0x5A C, 0x51 C, 0x2E C,
    0x6F C, 0x72 C, 0x79 C, 0x30 C, 0x73 C, 0x62 C, 0x30 C, 0x67 C,
    0x41 C, 0x54 C, 0x35 C, 0x67 C, 0x63 C, 0x55 C, 0x54 C, 0x77 C,
    0x70 C, 0x6B C, 0x77 C, 0x35 C, 0x59 C, 0x61 C, 0x41 C, 0x66 C,
    0x73 C, 0x79 C, 0x4C C, 0x49 C, 0x72 C, 0x72 C, 0x74 C, 0x32 C,
    0x6C C, 0x47 C, 0x35 C, 0x36 C, 0x44 C, 0x57 C, 0x51 C, 0x78 C,
    0x44 C, 0x47 C, 0x32 C, 0x70 C, 0x38 C, 0x62 C, 0x4D C, 0x72 C,
    0x65 C, 0x2D C, 0x72 C, 0x6E C, 0x73 C, 0x53 C, 0x6E C, 0x34 C,
    0x31 C, 0x7A C, 0x49 C, 0x71 C, 0x7A C, 0x77 C, 0x71 C, 0x71 C,
    0x4F C, 0x75 C, 0x4C C, 0x6F C, 0x6F C, 0x36 C, 0x2D C, 0x36 C,
    0x45 C, 0x74 C, 0x73 C, 0x77 C, 0x63 C, 0x50 C, 0x32 C, 0x44 C,
    0x55 C, 0x6E C, 0x52 C, 0x70 C, 0x6A C, 0x41 C,

\ RFC 7515 Appendix A.3 verification vector.  Its signature is intentionally
\ not deterministic; verification must accept any valid ES256 signature.

CREATE _jjwst-rfc-compact
    0x65 C, 0x79 C, 0x4A C, 0x68 C, 0x62 C, 0x47 C, 0x63 C, 0x69 C,
    0x4F C, 0x69 C, 0x4A C, 0x46 C, 0x55 C, 0x7A C, 0x49 C, 0x31 C,
    0x4E C, 0x69 C, 0x4A C, 0x39 C, 0x2E C, 0x65 C, 0x79 C, 0x4A C,
    0x70 C, 0x63 C, 0x33 C, 0x4D C, 0x69 C, 0x4F C, 0x69 C, 0x4A C,
    0x71 C, 0x62 C, 0x32 C, 0x55 C, 0x69 C, 0x4C C, 0x41 C, 0x30 C,
    0x4B C, 0x49 C, 0x43 C, 0x4A C, 0x6C C, 0x65 C, 0x48 C, 0x41 C,
    0x69 C, 0x4F C, 0x6A C, 0x45 C, 0x7A C, 0x4D C, 0x44 C, 0x41 C,
    0x34 C, 0x4D C, 0x54 C, 0x6B C, 0x7A C, 0x4F C, 0x44 C, 0x41 C,
    0x73 C, 0x44 C, 0x51 C, 0x6F C, 0x67 C, 0x49 C, 0x6D C, 0x68 C,
    0x30 C, 0x64 C, 0x48 C, 0x41 C, 0x36 C, 0x4C C, 0x79 C, 0x39 C,
    0x6C C, 0x65 C, 0x47 C, 0x46 C, 0x74 C, 0x63 C, 0x47 C, 0x78 C,
    0x6C C, 0x4C C, 0x6D C, 0x4E C, 0x76 C, 0x62 C, 0x53 C, 0x39 C,
    0x70 C, 0x63 C, 0x31 C, 0x39 C, 0x79 C, 0x62 C, 0x32 C, 0x39 C,
    0x30 C, 0x49 C, 0x6A C, 0x70 C, 0x30 C, 0x63 C, 0x6E C, 0x56 C,
    0x6C C, 0x66 C, 0x51 C, 0x2E C, 0x44 C, 0x74 C, 0x45 C, 0x68 C,
    0x55 C, 0x33 C, 0x6C C, 0x6A C, 0x62 C, 0x45 C, 0x67 C, 0x38 C,
    0x4C C, 0x33 C, 0x38 C, 0x56 C, 0x57 C, 0x41 C, 0x66 C, 0x55 C,
    0x41 C, 0x71 C, 0x4F C, 0x79 C, 0x4B C, 0x41 C, 0x4D C, 0x36 C,
    0x2D C, 0x58 C, 0x78 C, 0x2D C, 0x46 C, 0x34 C, 0x47 C, 0x61 C,
    0x77 C, 0x78 C, 0x61 C, 0x65 C, 0x70 C, 0x6D C, 0x58 C, 0x46 C,
    0x43 C, 0x67 C, 0x66 C, 0x54 C, 0x6A C, 0x44 C, 0x78 C, 0x77 C,
    0x35 C, 0x64 C, 0x6A C, 0x78 C, 0x4C C, 0x61 C, 0x38 C, 0x49 C,
    0x53 C, 0x6C C, 0x53 C, 0x41 C, 0x70 C, 0x6D C, 0x57 C, 0x51 C,
    0x78 C, 0x66 C, 0x4B C, 0x54 C, 0x55 C, 0x4A C, 0x71 C, 0x50 C,
    0x50 C, 0x33 C, 0x2D C, 0x4B C, 0x67 C, 0x36 C, 0x4E C, 0x55 C,
    0x31 C, 0x51 C,

CREATE _jjwst-rfc-header
    0x7B C, 0x22 C, 0x61 C, 0x6C C, 0x67 C, 0x22 C, 0x3A C, 0x22 C,
    0x45 C, 0x53 C, 0x32 C, 0x35 C, 0x36 C, 0x22 C, 0x7D C,

CREATE _jjwst-rfc-payload
    0x7B C, 0x22 C, 0x69 C, 0x73 C, 0x73 C, 0x22 C, 0x3A C, 0x22 C,
    0x6A C, 0x6F C, 0x65 C, 0x22 C, 0x2C C, 0x0D C, 0x0A C, 0x20 C,
    0x22 C, 0x65 C, 0x78 C, 0x70 C, 0x22 C, 0x3A C, 0x31 C, 0x33 C,
    0x30 C, 0x30 C, 0x38 C, 0x31 C, 0x39 C, 0x33 C, 0x38 C, 0x30 C,
    0x2C C, 0x0D C, 0x0A C, 0x20 C, 0x22 C, 0x68 C, 0x74 C, 0x74 C,
    0x70 C, 0x3A C, 0x2F C, 0x2F C, 0x65 C, 0x78 C, 0x61 C, 0x6D C,
    0x70 C, 0x6C C, 0x65 C, 0x2E C, 0x63 C, 0x6F C, 0x6D C, 0x2F C,
    0x69 C, 0x73 C, 0x5F C, 0x72 C, 0x6F C, 0x6F C, 0x74 C, 0x22 C,
    0x3A C, 0x74 C, 0x72 C, 0x75 C, 0x65 C, 0x7D C,

CREATE _jjwst-duplicate-alg
    0x7B C, 0x22 C, 0x61 C, 0x6C C, 0x67 C, 0x22 C, 0x3A C, 0x22 C,
    0x45 C, 0x53 C, 0x32 C, 0x35 C, 0x36 C, 0x22 C, 0x2C C, 0x22 C,
    0x5C C, 0x75 C, 0x30 C, 0x30 C, 0x36 C, 0x31 C, 0x6C C, 0x67 C,
    0x22 C, 0x3A C, 0x22 C, 0x45 C, 0x53 C, 0x32 C, 0x35 C, 0x36 C,
    0x22 C, 0x7D C,

CREATE _jjwst-missing-alg
    0x7B C, 0x22 C, 0x74 C, 0x79 C, 0x70 C, 0x22 C, 0x3A C, 0x22 C,
    0x4A C, 0x57 C, 0x54 C, 0x22 C, 0x7D C,

CREATE _jjwst-nonstring-alg
    0x7B C, 0x22 C, 0x61 C, 0x6C C, 0x67 C, 0x22 C, 0x3A C, 0x32 C,
    0x35 C, 0x36 C, 0x7D C,

CREATE _jjwst-unencoded-payload-header
    0x7B C, 0x22 C, 0x61 C, 0x6C C, 0x67 C, 0x22 C, 0x3A C, 0x22 C,
    0x45 C, 0x53 C, 0x32 C, 0x35 C, 0x36 C, 0x22 C, 0x2C C, 0x22 C,
    0x62 C, 0x36 C, 0x34 C, 0x22 C, 0x3A C, 0x66 C, 0x61 C, 0x6C C,
    0x73 C, 0x65 C, 0x7D C,

CREATE _jjwst-critical-header
    0x7B C, 0x22 C, 0x61 C, 0x6C C, 0x67 C, 0x22 C, 0x3A C, 0x22 C,
    0x45 C, 0x53 C, 0x32 C, 0x35 C, 0x36 C, 0x22 C, 0x2C C, 0x22 C,
    0x63 C, 0x72 C, 0x69 C, 0x74 C, 0x22 C, 0x3A C, 0x5B C, 0x22 C,
    0x78 C, 0x22 C, 0x5D C, 0x2C C, 0x22 C, 0x78 C, 0x22 C, 0x3A C,
    0x74 C, 0x72 C, 0x75 C, 0x65 C, 0x7D C,

CREATE _jjwst-empty-payload-short-signature
    0x65 C, 0x33 C, 0x30 C, 0x2E C, 0x2E C, 0x41 C, 0x41 C,

CREATE _jjwst-header-input     256 ALLOT
CREATE _jjwst-compact          512 ALLOT
CREATE _jjwst-protected-output 256 ALLOT
CREATE _jjwst-payload-output   256 ALLOT
CREATE _jjwst-workspace
    JOSE-JWS-ES256-WORKSPACE-SIZE ALLOT

: _jjwst-workspace-zero?  ( -- flag )
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE _jjwst-zero? ;

: _jjwst-compact-unchanged?  ( -- flag )
    _jjwst-compact 512 0xA5 _jjwst-filled? ;

: _jjwst-outputs-unchanged?  ( -- flag )
    _jjwst-protected-output 256 0xA5 _jjwst-filled?
    _jjwst-payload-output 256 0x5A _jjwst-filled? AND ;

: _jjwst-fill-outputs  ( -- )
    _jjwst-protected-output 256 0xA5 FILL
    _jjwst-payload-output 256 0x5A FILL ;

: _jjwst-build-overlong-signature  ( -- )
    S" e30." _jjwst-compact SWAP MOVE
    46 _jjwst-compact 4 + C!
    \ Eighty-seven canonical A characters decode to 65 zero bytes.
    _jjwst-compact 5 + 87 0x41 FILL ;

: _jjwst-test-vocabulary  ( -- )
    JOSE-JWS-ES256-MAX-PROTECTED-BYTES 4096 = _jjwst-assert
    JOSE-JWS-ES256-MAX-PAYLOAD-BYTES 65536 = _jjwst-assert
    JOSE-JWS-ES256-MAX-COMPACT-BYTES 92932 = _jjwst-assert
    JOSE-JWS-ES256-SIGNATURE-SIZE 64 = _jjwst-assert
    JOSE-JWS-ES256-WORKSPACE-SIZE 100000 > _jjwst-assert
    JOSE-JWS-ES256-S-CRYPTO
        JOSE-JWS-ES256-STATUS-VALID? _jjwst-assert
    JOSE-JWS-ES256-S-INTERNAL
        JOSE-JWS-ES256-STATUS-VALID? _jjwst-assert
    JOSE-JWS-ES256-S-INTERNAL 1+
        JOSE-JWS-ES256-STATUS-VALID? 0= _jjwst-assert

    27 31 JOSE-JWS-ES256-COMPACT-SIZE
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        166 = _jjwst-assert
    15 0 JOSE-JWS-ES256-COMPACT-SIZE
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        108 = _jjwst-assert
    JOSE-JWS-ES256-MAX-PROTECTED-BYTES
    JOSE-JWS-ES256-MAX-PAYLOAD-BYTES
    JOSE-JWS-ES256-COMPACT-SIZE
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        JOSE-JWS-ES256-MAX-COMPACT-BYTES = _jjwst-assert
    0 0 JOSE-JWS-ES256-COMPACT-SIZE
        JOSE-JWS-ES256-S-INVALID = _jjwst-assert
        0= _jjwst-assert
    _jjwst-stack ;

: _jjwst-test-deterministic-sign  ( -- )
    _jjwst-compact 512 0xA5 FILL
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-header 27 _jjwst-payload 31 _jjwst-private
    _jjwst-compact 512 _jjwst-workspace
    JOSE-JWS-ES256-SIGN
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        166 = _jjwst-assert
    _jjwst-compact _jjwst-expected-compact 166
        _jjwst-bytes= _jjwst-assert
    _jjwst-compact 166 + 512 166 - 0xA5
        _jjwst-filled? _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert
    _jjwst-stack ;

: _jjwst-test-rfc-verify  ( -- )
    _jjwst-fill-outputs
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-rfc-compact 202 _jjwst-public
    _jjwst-protected-output 256
    _jjwst-payload-output 256 _jjwst-workspace
    JOSE-JWS-ES256-VERIFY
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        _jjwst-assert
        70 = _jjwst-assert
        15 = _jjwst-assert
    _jjwst-protected-output _jjwst-rfc-header 15
        _jjwst-bytes= _jjwst-assert
    _jjwst-payload-output _jjwst-rfc-payload 70
        _jjwst-bytes= _jjwst-assert
    _jjwst-protected-output 15 + 256 15 - 0xA5
        _jjwst-filled? _jjwst-assert
    _jjwst-payload-output 70 + 256 70 - 0x5A
        _jjwst-filled? _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert
    _jjwst-stack ;

: _jjwst-expect-sign-failure
  ( protected protected-u expected-status -- )
    >R
    _jjwst-compact 512 0xA5 FILL
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-payload 31 _jjwst-private
    _jjwst-compact 512 _jjwst-workspace
    JOSE-JWS-ES256-SIGN
    R> = _jjwst-assert
    0= _jjwst-assert
    _jjwst-compact-unchanged? _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert ;

: _jjwst-test-header-policy  ( -- )
    _jjwst-header _jjwst-header-input 27 MOVE
    0x58 _jjwst-header-input 8 + C!
    _jjwst-header-input 27 JOSE-JWS-ES256-S-ALGORITHM
        _jjwst-expect-sign-failure

    _jjwst-missing-alg 13 JOSE-JWS-ES256-S-ALGORITHM
        _jjwst-expect-sign-failure
    _jjwst-nonstring-alg 11 JOSE-JWS-ES256-S-ALGORITHM
        _jjwst-expect-sign-failure
    _jjwst-duplicate-alg 34 JOSE-JWS-ES256-S-JSON
        _jjwst-expect-sign-failure
    _jjwst-unencoded-payload-header 27 JOSE-JWS-ES256-S-POLICY
        _jjwst-expect-sign-failure
    _jjwst-critical-header 37 JOSE-JWS-ES256-S-POLICY
        _jjwst-expect-sign-failure

    _jjwst-header _jjwst-header-input 27 MOVE
    0x5D _jjwst-header-input 26 + C!
    _jjwst-header-input 27 JOSE-JWS-ES256-S-JSON
        _jjwst-expect-sign-failure
    _jjwst-stack ;

: _jjwst-expect-verify-failure
  ( compact compact-u expected-status -- )
    >R
    _jjwst-fill-outputs
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-public
    _jjwst-protected-output 256
    _jjwst-payload-output 256 _jjwst-workspace
    JOSE-JWS-ES256-VERIFY
    R> = _jjwst-assert
    0= _jjwst-assert
    0= _jjwst-assert
    0= _jjwst-assert
    _jjwst-outputs-unchanged? _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert ;

: _jjwst-test-compact-rejection  ( -- )
    S" AA.AA" JOSE-JWS-ES256-S-COMPACT
        _jjwst-expect-verify-failure
    S" .AA.AA" JOSE-JWS-ES256-S-COMPACT
        _jjwst-expect-verify-failure
    S" AA.AA." JOSE-JWS-ES256-S-COMPACT
        _jjwst-expect-verify-failure
    S" AA.AA.AA.AA" JOSE-JWS-ES256-S-COMPACT
        _jjwst-expect-verify-failure
    S" Zh.AA.AA" JOSE-JWS-ES256-S-ENCODING
        _jjwst-expect-verify-failure
    S" Zg=.AA.AA" JOSE-JWS-ES256-S-ENCODING
        _jjwst-expect-verify-failure

    \ The empty middle segment is valid ordinary JWS encoding for a
    \ zero-byte payload.  This input therefore reaches signature-width
    \ rejection rather than being rejected as malformed compact syntax.
    _jjwst-empty-payload-short-signature 7
    JOSE-JWS-ES256-S-SIGNATURE
        _jjwst-expect-verify-failure

    _jjwst-build-overlong-signature
    _jjwst-compact 92 JOSE-JWS-ES256-S-SIGNATURE
        _jjwst-expect-verify-failure
    _jjwst-stack ;

: _jjwst-test-capacity  ( -- )
    _jjwst-compact 512 0xA5 FILL
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-header 27 _jjwst-payload 31 _jjwst-private
    _jjwst-compact 165 _jjwst-workspace
    JOSE-JWS-ES256-SIGN
        JOSE-JWS-ES256-S-CAPACITY = _jjwst-assert
        0= _jjwst-assert
    _jjwst-compact-unchanged? _jjwst-assert
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A
        _jjwst-filled? _jjwst-assert

    _jjwst-fill-outputs
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-rfc-compact 202 _jjwst-public
    _jjwst-protected-output 14
    _jjwst-payload-output 256 _jjwst-workspace
    JOSE-JWS-ES256-VERIFY
        JOSE-JWS-ES256-S-CAPACITY = _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
    _jjwst-outputs-unchanged? _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert
    _jjwst-stack ;

: _jjwst-test-empty-payload-round-trip  ( -- )
    _jjwst-compact 512 0xA5 FILL
    _jjwst-header 27 0 0 _jjwst-private
    _jjwst-compact 512 _jjwst-workspace
    JOSE-JWS-ES256-SIGN
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        124 = _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert

    _jjwst-fill-outputs
    _jjwst-compact 124 _jjwst-public
    _jjwst-protected-output 256
    _jjwst-payload-output 256 _jjwst-workspace
    JOSE-JWS-ES256-VERIFY
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        _jjwst-assert
        0= _jjwst-assert
        27 = _jjwst-assert
    _jjwst-protected-output _jjwst-header 27
        _jjwst-bytes= _jjwst-assert
    _jjwst-payload-output 256 0x5A
        _jjwst-filled? _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert
    _jjwst-stack ;

: _jjwst-test-valid-tampered-signature  ( -- )
    _jjwst-expected-compact _jjwst-compact 166 MOVE
    \ The final canonical Base64url character changes one signature bit
    \ while preserving the exact 64-byte raw-signature geometry.
    0x51 _jjwst-compact 165 + C!
    _jjwst-fill-outputs
    _jjwst-compact 166 _jjwst-public
    _jjwst-protected-output 256
    _jjwst-payload-output 256 _jjwst-workspace
    JOSE-JWS-ES256-VERIFY
        JOSE-JWS-ES256-S-OK = _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
    _jjwst-outputs-unchanged? _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert
    _jjwst-stack ;

: _jjwst-test-aliases  ( -- )
    _jjwst-header _jjwst-header-input 27 MOVE
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-header-input 27 _jjwst-payload 31 _jjwst-private
    _jjwst-header-input 256 _jjwst-workspace
    JOSE-JWS-ES256-SIGN
        JOSE-JWS-ES256-S-ALIAS = _jjwst-assert
        0= _jjwst-assert
    _jjwst-header-input _jjwst-header 27
        _jjwst-bytes= _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert

    _jjwst-rfc-compact _jjwst-compact 202 MOVE
    _jjwst-payload-output 256 0x5A FILL
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-compact 202 _jjwst-public
    _jjwst-compact 15
    _jjwst-payload-output 256 _jjwst-workspace
    JOSE-JWS-ES256-VERIFY
        JOSE-JWS-ES256-S-ALIAS = _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
    _jjwst-compact _jjwst-rfc-compact 202
        _jjwst-bytes= _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert

    \ Workspace overlap is rejected before admission, so caller bytes stay
    \ unchanged rather than being scrubbed through an aliased output.
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-header 27 _jjwst-payload 31 _jjwst-private
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE _jjwst-workspace
    JOSE-JWS-ES256-SIGN
        JOSE-JWS-ES256-S-ALIAS = _jjwst-assert
        0= _jjwst-assert
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A
        _jjwst-filled? _jjwst-assert
    _jjwst-stack ;

: _jjwst-test-invalid-geometry  ( -- )
    _jjwst-compact 512 0xA5 FILL
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A FILL
    _jjwst-header 27 _jjwst-payload 31 0
    _jjwst-compact 512 _jjwst-workspace
    JOSE-JWS-ES256-SIGN
        JOSE-JWS-ES256-S-INVALID = _jjwst-assert
        0= _jjwst-assert
    _jjwst-compact-unchanged? _jjwst-assert
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0x5A
        _jjwst-filled? _jjwst-assert
    _jjwst-stack ;

: _jjwst-throw-sign
  \ ( protected protected-u payload payload-u private
  \   destination capacity workspace -- written status )
    _JJWS-SIGN-BIND
    -777 THROW ;

: _jjwst-throw-verify
  \ ( compact compact-u public
  \   protected-output protected-capacity
  \   payload-output payload-capacity workspace
  \   -- protected-u payload-u valid? status )
    _JJWS-VERIFY-BIND
    -778 THROW ;

: _jjwst-test-throw-cleanup  ( -- )
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0xA5 FILL
    _jjwst-header 27 _jjwst-payload 31 _jjwst-private
    _jjwst-compact 512 _jjwst-workspace
    ['] _jjwst-throw-sign _JJWS-SIGN-CALL
        JOSE-JWS-ES256-S-INTERNAL = _jjwst-assert
        0= _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert

    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0xA5 FILL
    _jjwst-rfc-compact 202 _jjwst-public
    _jjwst-protected-output 256
    _jjwst-payload-output 256 _jjwst-workspace
    ['] _jjwst-throw-verify _JJWS-VERIFY-CALL
        JOSE-JWS-ES256-S-INTERNAL = _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
        0= _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert
    _jjwst-stack ;

: _jjwst-test-clear  ( -- )
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-SIZE 0xA5 FILL
    _jjwst-workspace JOSE-JWS-ES256-WORKSPACE-CLEAR
        JOSE-JWS-ES256-S-OK = _jjwst-assert
    _jjwst-workspace-zero? _jjwst-assert
    0 JOSE-JWS-ES256-WORKSPACE-CLEAR
        JOSE-JWS-ES256-S-INVALID = _jjwst-assert
    _jjwst-stack ;

: _JJWST-RUN  ( -- )
    0 _jjwst-fails !
    0 _jjwst-checks !
    DEPTH _jjwst-depth !
    _jjwst-test-vocabulary
    _jjwst-test-header-policy
    _jjwst-test-compact-rejection
    _jjwst-test-capacity
    _jjwst-test-aliases
    _jjwst-test-invalid-geometry
    _jjwst-test-throw-cleanup
    _jjwst-test-clear
    _jjwst-test-deterministic-sign
    _jjwst-test-rfc-verify
    _jjwst-test-empty-payload-round-trip
    _jjwst-test-valid-tampered-signature
    _jjwst-stack
    _jjwst-fails @ 0= IF
        ." JOSE JWS ES256 PASS " _jjwst-checks @ . CR
    ELSE
        ." JOSE JWS ES256 FAIL " _jjwst-fails @ .
        ." / " _jjwst-checks @ . CR
    THEN ;
