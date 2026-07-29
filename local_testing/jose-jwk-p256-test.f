\ jose-jwk-p256-test.f - Strict P-256 public JWK contracts

PROVIDED akashic-jjwk-contracts

VARIABLE _jjpkt-fails
VARIABLE _jjpkt-checks
VARIABLE _jjpkt-depth

: _jjpkt-assert  ( flag -- )
    1 _jjpkt-checks +!
    0= IF
        1 _jjpkt-fails +!
        ." JOSE JWK P256 ASSERT " _jjpkt-checks @ . CR
    THEN ;

: _jjpkt-stack  ( -- )
    DEPTH DUP _jjpkt-depth @ <> IF
        ." JOSE JWK P256 STACK "
        _jjpkt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _jjpkt-depth @ = _jjpkt-assert ;

: _jjpkt-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _jjpkt-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ The key is the RFC 6979 P-256 sample key.  The JWK and digest were
\ independently produced from its published affine coordinates using
\ RFC 4648 Base64url and SHA-256 over the RFC 7638 canonical member set.

CREATE _jjpkt-expected-public
    0x04 C, 0x60 C, 0xFE C, 0xD4 C, 0xBA C, 0x25 C, 0x5A C, 0x9D C,
    0x31 C, 0xC9 C, 0x61 C, 0xEB C, 0x74 C, 0xC6 C, 0x35 C, 0x6D C,
    0x68 C, 0xC0 C, 0x49 C, 0xB8 C, 0x92 C, 0x3B C, 0x61 C, 0xFA C,
    0x6C C, 0xE6 C, 0x69 C, 0x62 C, 0x2E C, 0x60 C, 0xF2 C, 0x9F C,
    0xB6 C, 0x79 C, 0x03 C, 0xFE C, 0x10 C, 0x08 C, 0xB8 C, 0xBC C,
    0x99 C, 0xA4 C, 0x1A C, 0xE9 C, 0xE9 C, 0x56 C, 0x28 C, 0xBC C,
    0x64 C, 0xF2 C, 0xF1 C, 0xB2 C, 0x0C C, 0x2D C, 0x7E C, 0x9F C,
    0x51 C, 0x77 C, 0xA3 C, 0xC2 C, 0x94 C, 0xD4 C, 0x46 C, 0x22 C,
    0x99 C,

CREATE _jjpkt-expected-jwk
    0x7B C, 0x22 C, 0x63 C, 0x72 C, 0x76 C, 0x22 C, 0x3A C, 0x22 C,
    0x50 C, 0x2D C, 0x32 C, 0x35 C, 0x36 C, 0x22 C, 0x2C C, 0x22 C,
    0x6B C, 0x74 C, 0x79 C, 0x22 C, 0x3A C, 0x22 C, 0x45 C, 0x43 C,
    0x22 C, 0x2C C, 0x22 C, 0x78 C, 0x22 C, 0x3A C, 0x22 C, 0x59 C,
    0x50 C, 0x37 C, 0x55 C, 0x75 C, 0x69 C, 0x56 C, 0x61 C, 0x6E C,
    0x54 C, 0x48 C, 0x4A C, 0x59 C, 0x65 C, 0x74 C, 0x30 C, 0x78 C,
    0x6A C, 0x56 C, 0x74 C, 0x61 C, 0x4D C, 0x42 C, 0x4A C, 0x75 C,
    0x4A C, 0x49 C, 0x37 C, 0x59 C, 0x66 C, 0x70 C, 0x73 C, 0x35 C,
    0x6D C, 0x6C C, 0x69 C, 0x4C C, 0x6D C, 0x44 C, 0x79 C, 0x6E C,
    0x37 C, 0x59 C, 0x22 C, 0x2C C, 0x22 C, 0x79 C, 0x22 C, 0x3A C,
    0x22 C, 0x65 C, 0x51 C, 0x50 C, 0x2D C, 0x45 C, 0x41 C, 0x69 C,
    0x34 C, 0x76 C, 0x4A C, 0x6D C, 0x6B C, 0x47 C, 0x75 C, 0x6E C,
    0x70 C, 0x56 C, 0x69 C, 0x69 C, 0x38 C, 0x5A C, 0x50 C, 0x4C C,
    0x78 C, 0x73 C, 0x67 C, 0x77 C, 0x74 C, 0x66 C, 0x70 C, 0x39 C,
    0x52 C, 0x64 C, 0x36 C, 0x50 C, 0x43 C, 0x6C C, 0x4E C, 0x52 C,
    0x47 C, 0x49 C, 0x70 C, 0x6B C, 0x22 C, 0x7D C,

CREATE _jjpkt-expected-digest
    0x0C C, 0xEB C, 0xF1 C, 0xBC C, 0x98 C, 0x80 C, 0x74 C, 0x8A C,
    0x95 C, 0x58 C, 0x89 C, 0x05 C, 0xB7 C, 0x98 C, 0x43 C, 0xB4 C,
    0x2B C, 0xA7 C, 0x5C C, 0xB1 C, 0x74 C, 0x05 C, 0x5E C, 0x3E C,
    0x24 C, 0x6B C, 0xF8 C, 0x7F C, 0xE0 C, 0x0B C, 0x4A C, 0x6D C,

CREATE _jjpkt-input    256 ALLOT
CREATE _jjpkt-public   JOSE-JWK-P256-PUBLIC-SIZE ALLOT
CREATE _jjpkt-emitted  160 ALLOT
CREATE _jjpkt-digest   JOSE-JWK-P256-THUMBPRINT-SIZE ALLOT
CREATE _jjpkt-work     JOSE-JWK-P256-WORKSPACE-SIZE ALLOT

VARIABLE _jjpkt-input-u
VARIABLE _jjpkt-copy-u

: _jjpkt-reset-jwk  ( -- )
    _jjpkt-expected-jwk _jjpkt-input
    JOSE-JWK-P256-CANONICAL-SIZE MOVE ;

: _jjpkt-reset-input  ( -- )
    0 _jjpkt-input-u ! ;

: _jjpkt-char  ( byte -- )
    _jjpkt-input _jjpkt-input-u @ + C!
    1 _jjpkt-input-u +! ;

: _jjpkt-text  ( address length -- )
    DUP _jjpkt-copy-u !
    _jjpkt-input _jjpkt-input-u @ + SWAP MOVE
    _jjpkt-copy-u @ _jjpkt-input-u +! ;

: _jjpkt-quote  ( -- ) 34 _jjpkt-char ;
: _jjpkt-colon  ( -- ) 58 _jjpkt-char ;
: _jjpkt-comma  ( -- ) 44 _jjpkt-char ;
: _jjpkt-lbrace ( -- ) 123 _jjpkt-char ;
: _jjpkt-rbrace ( -- ) 125 _jjpkt-char ;
: _jjpkt-slash  ( -- ) 92 _jjpkt-char ;

: _jjpkt-key  ( address length -- )
    _jjpkt-quote _jjpkt-text _jjpkt-quote _jjpkt-colon ;

: _jjpkt-string  ( address length -- )
    _jjpkt-quote _jjpkt-text _jjpkt-quote ;

: _jjpkt-member-kty  ( -- )
    S" kty" _jjpkt-key S" EC" _jjpkt-string ;

: _jjpkt-member-crv  ( -- )
    S" crv" _jjpkt-key S" P-256" _jjpkt-string ;

: _jjpkt-member-x  ( text-u -- )
    S" x" _jjpkt-key
    _jjpkt-expected-jwk 31 + SWAP _jjpkt-string ;

: _jjpkt-member-y  ( -- )
    S" y" _jjpkt-key
    _jjpkt-expected-jwk 81 + 43 _jjpkt-string ;

: _jjpkt-build-metadata-order  ( -- )
    _jjpkt-reset-input _jjpkt-lbrace
    S" kid" _jjpkt-key S" key-1" _jjpkt-string
    _jjpkt-comma _jjpkt-member-y
    _jjpkt-comma
    S" use" _jjpkt-key S" sig" _jjpkt-string
    _jjpkt-comma 43 _jjpkt-member-x
    _jjpkt-comma _jjpkt-member-crv
    _jjpkt-comma _jjpkt-member-kty
    _jjpkt-comma
    S" x5t#S256" _jjpkt-key S" metadata" _jjpkt-string
    _jjpkt-rbrace ;

: _jjpkt-build-private-member  ( -- )
    _jjpkt-reset-input _jjpkt-lbrace
    _jjpkt-member-kty
    _jjpkt-comma _jjpkt-member-crv
    _jjpkt-comma 43 _jjpkt-member-x
    _jjpkt-comma _jjpkt-member-y
    _jjpkt-comma
    _jjpkt-quote _jjpkt-slash S" u0064" _jjpkt-text
    _jjpkt-quote _jjpkt-colon S" AA" _jjpkt-string
    _jjpkt-rbrace ;

: _jjpkt-build-x-width  ( text-u -- )
    _jjpkt-reset-input _jjpkt-lbrace
    _jjpkt-member-kty
    _jjpkt-comma _jjpkt-member-crv
    _jjpkt-comma _jjpkt-member-x
    _jjpkt-comma _jjpkt-member-y
    _jjpkt-rbrace ;

: _jjpkt-work-zero?  ( -- flag )
    _jjpkt-work JOSE-JWK-P256-WORKSPACE-SIZE _jjpkt-zero? ;

: _jjpkt-public-unchanged?  ( -- flag )
    _jjpkt-public JOSE-JWK-P256-PUBLIC-SIZE 0xA5 _jjpkt-filled? ;

: _jjpkt-fill-preflight  ( -- )
    _jjpkt-public JOSE-JWK-P256-PUBLIC-SIZE 0xA5 FILL
    _jjpkt-emitted 160 0x5A FILL
    _jjpkt-digest JOSE-JWK-P256-THUMBPRINT-SIZE 0xA5 FILL
    _jjpkt-work JOSE-JWK-P256-WORKSPACE-SIZE 0xC3 FILL ;

: _jjpkt-bad-span  ( -- address length )
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2 ;

: _jjpkt-test-parse  ( -- )
    _jjpkt-reset-jwk
    _jjpkt-public JOSE-JWK-P256-PUBLIC-SIZE 0xA5 FILL
    _jjpkt-input JOSE-JWK-P256-CANONICAL-SIZE
    _jjpkt-public _jjpkt-work
    JOSE-JWK-P256-PUBLIC-PARSE
        JOSE-JWK-P256-S-OK = _jjpkt-assert
    _jjpkt-public JOSE-JWK-P256-PUBLIC-SIZE
    _jjpkt-expected-public JOSE-JWK-P256-PUBLIC-SIZE
        COMPARE 0= _jjpkt-assert
    _jjpkt-work-zero? _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-test-order-and-metadata  ( -- )
    _jjpkt-build-metadata-order
    _jjpkt-public JOSE-JWK-P256-PUBLIC-SIZE 0xA5 FILL
    _jjpkt-input _jjpkt-input-u @
    _jjpkt-public _jjpkt-work
    JOSE-JWK-P256-PUBLIC-PARSE
        JOSE-JWK-P256-S-OK = _jjpkt-assert
    _jjpkt-public JOSE-JWK-P256-PUBLIC-SIZE
    _jjpkt-expected-public JOSE-JWK-P256-PUBLIC-SIZE
        COMPARE 0= _jjpkt-assert
    _jjpkt-work-zero? _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-test-emit  ( -- )
    _jjpkt-emitted 160 0xA5 FILL
    _jjpkt-public _jjpkt-emitted 160 _jjpkt-work
    JOSE-JWK-P256-PUBLIC-EMIT
        JOSE-JWK-P256-S-OK = _jjpkt-assert
        JOSE-JWK-P256-CANONICAL-SIZE = _jjpkt-assert
    _jjpkt-emitted JOSE-JWK-P256-CANONICAL-SIZE
    _jjpkt-expected-jwk JOSE-JWK-P256-CANONICAL-SIZE
        COMPARE 0= _jjpkt-assert
    _jjpkt-emitted JOSE-JWK-P256-CANONICAL-SIZE +
    160 JOSE-JWK-P256-CANONICAL-SIZE - 0xA5
        _jjpkt-filled? _jjpkt-assert
    _jjpkt-work-zero? _jjpkt-assert

    _jjpkt-emitted 160 0xA5 FILL
    _jjpkt-public _jjpkt-emitted
    JOSE-JWK-P256-CANONICAL-SIZE 1- _jjpkt-work
    JOSE-JWK-P256-PUBLIC-EMIT
        JOSE-JWK-P256-S-CAPACITY = _jjpkt-assert
        0= _jjpkt-assert
    _jjpkt-emitted 160 0xA5 _jjpkt-filled? _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-test-thumbprint  ( -- )
    _jjpkt-digest JOSE-JWK-P256-THUMBPRINT-SIZE 0xA5 FILL
    _jjpkt-public _jjpkt-digest _jjpkt-work
    JOSE-JWK-P256-THUMBPRINT
        JOSE-JWK-P256-S-OK = _jjpkt-assert
    _jjpkt-digest JOSE-JWK-P256-THUMBPRINT-SIZE
    _jjpkt-expected-digest JOSE-JWK-P256-THUMBPRINT-SIZE
        COMPARE 0= _jjpkt-assert
    _jjpkt-work-zero? _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-expect-parse-failure  ( input-u expected-status -- )
    >R
    _jjpkt-public JOSE-JWK-P256-PUBLIC-SIZE 0xA5 FILL
    _jjpkt-input SWAP _jjpkt-public _jjpkt-work
    JOSE-JWK-P256-PUBLIC-PARSE
    R> = _jjpkt-assert
    _jjpkt-public-unchanged? _jjpkt-assert
    _jjpkt-work-zero? _jjpkt-assert ;

: _jjpkt-test-policy  ( -- )
    \ A public parser rejects a private `d` even when all four required
    \ public members are also present.
    _jjpkt-build-private-member
    _jjpkt-input-u @ JOSE-JWK-P256-S-POLICY
        _jjpkt-expect-parse-failure

    \ Missing y.
    _jjpkt-reset-jwk
    0x22 _jjpkt-input 74 + C!
    0x7D _jjpkt-input 75 + C!
    76 JOSE-JWK-P256-S-POLICY _jjpkt-expect-parse-failure

    \ Exact member values are enforced.
    _jjpkt-reset-jwk
    0x58 _jjpkt-input 22 + C!
    JOSE-JWK-P256-CANONICAL-SIZE JOSE-JWK-P256-S-POLICY
        _jjpkt-expect-parse-failure
    _jjpkt-stack ;

: _jjpkt-test-encoding-and-point  ( -- )
    \ '+' is JSON-safe but is outside the Base64url alphabet.
    _jjpkt-reset-jwk
    0x2B _jjpkt-input 31 + C!
    JOSE-JWK-P256-CANONICAL-SIZE JOSE-JWK-P256-S-ENCODING
        _jjpkt-expect-parse-failure

    \ A coordinate must decode from exactly 43 Base64url characters.
    42 _jjpkt-build-x-width
    _jjpkt-input-u @ JOSE-JWK-P256-S-ENCODING
        _jjpkt-expect-parse-failure

    \ The final Base64url character for 32 bytes has two unused low bits.
    \ Changing canonical `Y` to noncanonical `Z` must not be accepted as
    \ the same coordinate.
    _jjpkt-reset-jwk
    0x5A _jjpkt-input 73 + C!
    JOSE-JWK-P256-CANONICAL-SIZE JOSE-JWK-P256-S-ENCODING
        _jjpkt-expect-parse-failure

    \ Change only canonical low-significance y bits; decoding remains
    \ canonical but the resulting SEC 1 point is not on P-256.
    _jjpkt-reset-jwk
    0x6F _jjpkt-input 123 + C!
    JOSE-JWK-P256-CANONICAL-SIZE JOSE-JWK-P256-S-PUBLIC
        _jjpkt-expect-parse-failure

    \ A non-whitespace byte after the object is not a second document.
    _jjpkt-reset-jwk
    0x78 _jjpkt-input JOSE-JWK-P256-CANONICAL-SIZE + C!
    JOSE-JWK-P256-CANONICAL-SIZE 1+
    JOSE-JWK-P256-S-JSON _jjpkt-expect-parse-failure
    _jjpkt-stack ;

: _jjpkt-test-alias  ( -- )
    _jjpkt-reset-jwk
    _jjpkt-input JOSE-JWK-P256-CANONICAL-SIZE
    _jjpkt-input _jjpkt-work
    JOSE-JWK-P256-PUBLIC-PARSE
        JOSE-JWK-P256-S-ALIAS = _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-test-mapped-spans  ( -- )
    _jjpkt-reset-jwk

    _jjpkt-fill-preflight
    _jjpkt-bad-span _jjpkt-public _jjpkt-work
    JOSE-JWK-P256-PUBLIC-PARSE
        JOSE-JWK-P256-S-RANGE = _jjpkt-assert
    _jjpkt-public-unchanged? _jjpkt-assert
    _jjpkt-work JOSE-JWK-P256-WORKSPACE-SIZE
        0xC3 _jjpkt-filled? _jjpkt-assert

    _jjpkt-fill-preflight
    _jjpkt-input JOSE-JWK-P256-CANONICAL-SIZE
    _jjpkt-public 1
    JOSE-JWK-P256-PUBLIC-PARSE
        JOSE-JWK-P256-S-PROTECTED = _jjpkt-assert
    _jjpkt-public-unchanged? _jjpkt-assert

    \ P-256, local immutable, and SHA reserved footprints are all excluded.
    _jjpkt-fill-preflight
    _P256-GX _jjpkt-emitted 160 _jjpkt-work
    JOSE-JWK-P256-PUBLIC-EMIT
        JOSE-JWK-P256-S-ALIAS = _jjpkt-assert
        0= _jjpkt-assert
    _jjpkt-emitted 160 0x5A _jjpkt-filled? _jjpkt-assert

    _jjpkt-fill-preflight
    _JJPK-CANONICAL-PREFIX _JJPK-CANONICAL-PREFIX-SIZE
    _jjpkt-public _jjpkt-work
    JOSE-JWK-P256-PUBLIC-PARSE
        JOSE-JWK-P256-S-ALIAS = _jjpkt-assert

    _jjpkt-fill-preflight
    _jjpkt-input JOSE-JWK-P256-CANONICAL-SIZE
    _sha256-guard _jjpkt-work
    JOSE-JWK-P256-PUBLIC-PARSE
        JOSE-JWK-P256-S-ALIAS = _jjpkt-assert

    _jjpkt-fill-preflight
    _jjpkt-public _jjpkt-bad-span _jjpkt-work
    JOSE-JWK-P256-PUBLIC-EMIT
        JOSE-JWK-P256-S-RANGE = _jjpkt-assert
        0= _jjpkt-assert
    _jjpkt-work JOSE-JWK-P256-WORKSPACE-SIZE
        0xC3 _jjpkt-filled? _jjpkt-assert

    _jjpkt-fill-preflight
    _jjpkt-public 1 _jjpkt-work
    JOSE-JWK-P256-THUMBPRINT
        JOSE-JWK-P256-S-PROTECTED = _jjpkt-assert
    _jjpkt-digest JOSE-JWK-P256-THUMBPRINT-SIZE
        0xA5 _jjpkt-filled? _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-test-caller-span  ( -- )
    _jjpkt-work JOSE-JWK-P256-WORKSPACE-SIZE
    JOSE-JWK-P256-CALLER-SPAN-STATUS
        JOSE-JWK-P256-S-OK = _jjpkt-assert

    _jjpkt-bad-span
    JOSE-JWK-P256-CALLER-SPAN-STATUS
        JOSE-JWK-P256-S-RANGE = _jjpkt-assert

    _JJPK-CANONICAL-PREFIX _JJPK-CANONICAL-PREFIX-SIZE
    JOSE-JWK-P256-CALLER-SPAN-STATUS
        JOSE-JWK-P256-S-ALIAS = _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-stage-throw
  ( source source-u public-output workspace -- status )
    DUP JOSE-JWK-P256-WORKSPACE-SIZE 0x44 FILL
    -876 THROW ;

: _jjpkt-publication-throw  ( workspace -- )
    0x33 OVER _JJPKW.OUTPUT @ C!
    DROP -877 THROW ;

: _jjpkt-invoke-publication-throw  ( -- )
    _jjpkt-work
    ['] _jjpkt-publication-throw
    ['] _JJPK-WIPE
    _JJPK-CALL-FINALLY ;

: _jjpkt-operation-throw  ( workspace -- )
    DROP -878 THROW ;

: _jjpkt-cleanup-throw  ( workspace -- )
    DROP -879 THROW ;

: _jjpkt-invoke-double-throw  ( -- )
    _jjpkt-work
    ['] _jjpkt-operation-throw
    ['] _jjpkt-cleanup-throw
    _JJPK-CALL-FINALLY ;

: _jjpkt-test-publication-throws  ( -- )
    _jjpkt-reset-jwk
    _jjpkt-fill-preflight
    _jjpkt-input JOSE-JWK-P256-CANONICAL-SIZE
    _jjpkt-public _jjpkt-work
    ['] _jjpkt-stage-throw _JJPK-PARSE-CALL
        JOSE-JWK-P256-S-INTERNAL = _jjpkt-assert
    _jjpkt-public-unchanged? _jjpkt-assert
    _jjpkt-work-zero? _jjpkt-assert

    _jjpkt-emitted 160 0x5A FILL
    _jjpkt-work _JJPK-WIPE
    _jjpkt-emitted _jjpkt-work _JJPKW.OUTPUT !
    ['] _jjpkt-invoke-publication-throw CATCH
        -877 = _jjpkt-assert
    _jjpkt-emitted C@ 0x33 = _jjpkt-assert
    _jjpkt-work-zero? _jjpkt-assert

    ['] _jjpkt-invoke-double-throw CATCH
        -879 = _jjpkt-assert
    _jjpkt-stack ;

: _jjpkt-test-vocabulary  ( -- )
    JOSE-JWK-P256-S-CRYPTO
        JOSE-JWK-P256-STATUS-VALID? _jjpkt-assert
    JOSE-JWK-P256-S-INTERNAL
        JOSE-JWK-P256-STATUS-VALID? _jjpkt-assert
    JOSE-JWK-P256-S-RANGE
        JOSE-JWK-P256-STATUS-VALID? _jjpkt-assert
    JOSE-JWK-P256-S-PROTECTED
        JOSE-JWK-P256-STATUS-VALID? _jjpkt-assert
    JOSE-JWK-P256-S-PLATFORM
        JOSE-JWK-P256-STATUS-VALID? _jjpkt-assert
    JOSE-JWK-P256-S-PLATFORM 1+
        JOSE-JWK-P256-STATUS-VALID? 0= _jjpkt-assert
    _jjpkt-stack ;

: _JJPKT-RUN  ( -- )
    0 _jjpkt-fails !
    0 _jjpkt-checks !
    DEPTH _jjpkt-depth !

    _jjpkt-test-vocabulary
    _jjpkt-test-parse
    _jjpkt-test-order-and-metadata
    _jjpkt-test-emit
    _jjpkt-test-thumbprint
    _jjpkt-test-policy
    _jjpkt-test-encoding-and-point
    _jjpkt-test-alias
    _jjpkt-test-mapped-spans
    _jjpkt-test-caller-span
    _jjpkt-test-publication-throws

    _jjpkt-stack
    _jjpkt-fails @ 0= IF
        ." JOSE JWK P256 PASS" CR
    ELSE
        ." JOSE JWK P256 FAIL " _jjpkt-fails @ . CR
    THEN ;
