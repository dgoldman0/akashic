\ oauth2-dpop-es256-test.f - Focused standalone DPoP proof contracts

PROVIDED akashic-odpop-contracts

VARIABLE _odpt-fails
VARIABLE _odpt-checks
VARIABLE _odpt-depth
VARIABLE _odpt-proof-u
VARIABLE _odpt-header-u
VARIABLE _odpt-payload-u
VARIABLE _odpt-dot1
VARIABLE _odpt-dot2
VARIABLE _odpt-dot-count
VARIABLE _odpt-needle
VARIABLE _odpt-needle-u
VARIABLE _odpt-haystack
VARIABLE _odpt-haystack-u

: _odpt-assert  ( flag -- )
    1 _odpt-checks +!
    0= IF
        1 _odpt-fails +!
        ." OAUTH2 DPOP ES256 ASSERT " _odpt-checks @ . CR
    THEN ;

: _odpt-stack  ( -- )
    DEPTH DUP _odpt-depth @ <> IF
        ." OAUTH2 DPOP ES256 STACK "
        _odpt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _odpt-depth @ = _odpt-assert ;

: _odpt-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _odpt-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _odpt-contains?
  ( needle needle-u haystack haystack-u -- flag )
    _odpt-haystack-u !
    _odpt-haystack !
    _odpt-needle-u !
    _odpt-needle !
    _odpt-haystack-u @ _odpt-needle-u @ U< IF
        0 EXIT
    THEN
    _odpt-haystack-u @ _odpt-needle-u @ - 1+ 0 ?DO
        _odpt-needle @ _odpt-needle-u @
        _odpt-haystack @ I +
        _odpt-needle-u @ COMPARE 0= IF
            -1 UNLOOP EXIT
        THEN
    LOOP
    0 ;

CREATE _odpt-private
    0x8E C, 0x9B C, 0x10 C, 0x9E C, 0x71 C, 0x90 C, 0x98 C, 0xBF C,
    0x98 C, 0x04 C, 0x87 C, 0xDF C, 0x1F C, 0x5D C, 0x77 C, 0xE9 C,
    0xCB C, 0x29 C, 0x60 C, 0x6E C, 0xBE C, 0xD2 C, 0x26 C, 0x3B C,
    0x5F C, 0x57 C, 0xC2 C, 0x13 C, 0xDF C, 0x84 C, 0xF4 C, 0xB2 C,

CREATE _odpt-public P256-PUBLIC-SIZE ALLOT
CREATE _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES ALLOT
CREATE _odpt-header 256 ALLOT
CREATE _odpt-payload 512 ALLOT
CREATE _odpt-jti-raw 16 ALLOT
CREATE _odpt-work OAUTH2-DPOP-ES256-WORKSPACE-SIZE ALLOT

: _odpt-work-zero?  ( -- flag )
    _odpt-work OAUTH2-DPOP-ES256-WORKSPACE-SIZE _odpt-zero? ;

: _odpt-split  ( -- )
    0 _odpt-dot1 !
    0 _odpt-dot2 !
    0 _odpt-dot-count !
    _odpt-proof-u @ 0 ?DO
        _odpt-proof I + C@ 46 = IF
            _odpt-dot-count @ 0= IF
                I _odpt-dot1 !
            ELSE
                I _odpt-dot2 !
            THEN
            1 _odpt-dot-count +!
        THEN
    LOOP ;

: _odpt-decode  ( -- )
    _odpt-split
    _odpt-dot-count @ 2 = _odpt-assert
    _odpt-proof _odpt-dot1 @
    _odpt-header 256 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _odpt-assert
        _odpt-header-u !
    _odpt-proof _odpt-dot1 @ + 1+
    _odpt-dot2 @ _odpt-dot1 @ - 1-
    _odpt-payload 512 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _odpt-assert
        _odpt-payload-u ! ;

: _odpt-test-vocabulary  ( -- )
    OAUTH2-DPOP-ES256-MAX-METHOD-BYTES 32 = _odpt-assert
    OAUTH2-DPOP-ES256-MAX-HTU-BYTES 4096 = _odpt-assert
    OAUTH2-DPOP-ES256-MAX-NONCE-BYTES 4096 = _odpt-assert
    OAUTH2-DPOP-ES256-JTI-SIZE 22 = _odpt-assert
    OAUTH2-DPOP-ES256-MAX-PROOF-BYTES 11459 = _odpt-assert
    OAUTH2-DPOP-ES256-S-PLATFORM
        OAUTH2-DPOP-ES256-STATUS-VALID? _odpt-assert
    OAUTH2-DPOP-ES256-S-PLATFORM 1+
        OAUTH2-DPOP-ES256-STATUS-VALID? 0= _odpt-assert ;

: _odpt-test-proof  ( -- )
    _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES 0xA5 FILL
    _odpt-work OAUTH2-DPOP-ES256-WORKSPACE-SIZE 0x5A FILL
    S" POST"
    S" http://server.example/token"
    1562262616
    S" opaque.nonce-1"
    S" opaque-access-token"
    _odpt-private
    _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES _odpt-work
    OAUTH2-DPOP-ES256-PROOF
        OAUTH2-DPOP-ES256-S-OK = _odpt-assert
        DUP 0> _odpt-assert
        DUP OAUTH2-DPOP-ES256-MAX-PROOF-BYTES U> 0= _odpt-assert
        _odpt-proof-u !
    _odpt-work-zero? _odpt-assert

    _odpt-private _odpt-public _odpt-work
    P256-PUBLIC-FROM-PRIVATE
        P256-S-OK = _odpt-assert
    _odpt-proof _odpt-proof-u @ _odpt-public
    _odpt-header 256
    _odpt-payload 512 _odpt-work
    JOSE-JWS-ES256-VERIFY
        JOSE-JWS-ES256-S-OK = _odpt-assert
        _odpt-assert
        _odpt-payload-u !
        _odpt-header-u !
    _odpt-header-u @ 165 = _odpt-assert
    _odpt-payload-u @ 0> _odpt-assert
    _odpt-work-zero? _odpt-assert

    _odpt-decode
    _odpt-header-u @ 165 = _odpt-assert
    S" dpop+jwt" _odpt-header _odpt-header-u @
        _odpt-contains? _odpt-assert
    S" ES256" _odpt-header _odpt-header-u @
        _odpt-contains? _odpt-assert
    S" P-256" _odpt-header _odpt-header-u @
        _odpt-contains? _odpt-assert

    S" POST" _odpt-payload _odpt-payload-u @
        _odpt-contains? _odpt-assert
    S" http://server.example/token"
    _odpt-payload _odpt-payload-u @
        _odpt-contains? _odpt-assert
    S" opaque.nonce-1" _odpt-payload _odpt-payload-u @
        _odpt-contains? _odpt-assert
    S" ziBUtZEpY5JqE5mEv5FPe8jxfREaojHC2Eo9VfATgy4"
    _odpt-payload _odpt-payload-u @
        _odpt-contains? _odpt-assert

    \ The fixed serializer places the fresh 22-character jti after the
    \ eight-byte `{"jti":"` prefix.  It must decode to all 16 entropy bytes.
    _odpt-payload 8 + OAUTH2-DPOP-ES256-JTI-SIZE
    _odpt-jti-raw 16 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _odpt-assert
        16 = _odpt-assert
    _odpt-stack ;

: _odpt-test-boundaries  ( -- )
    _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES 0xA5 FILL
    _odpt-work OAUTH2-DPOP-ES256-WORKSPACE-SIZE 0x5A FILL
    S" GET"
    S" https://resource.example/data?view=full"
    1562262617
    0 0
    0 0
    _odpt-private
    _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES _odpt-work
    OAUTH2-DPOP-ES256-PROOF
        OAUTH2-DPOP-ES256-S-HTU = _odpt-assert
        0= _odpt-assert
    _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES 0xA5
        _odpt-filled? _odpt-assert
    _odpt-work OAUTH2-DPOP-ES256-WORKSPACE-SIZE 0x5A
        _odpt-filled? _odpt-assert

    S" GET"
    S" https://resource.example/data"
    1562262617
    0 0
    S" invalid token"
    _odpt-private
    _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES _odpt-work
    OAUTH2-DPOP-ES256-PROOF
        OAUTH2-DPOP-ES256-S-TOKEN = _odpt-assert
        0= _odpt-assert
    _odpt-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES 0xA5
        _odpt-filled? _odpt-assert
    _odpt-work OAUTH2-DPOP-ES256-WORKSPACE-SIZE 0x5A
        _odpt-filled? _odpt-assert

    _odpt-work OAUTH2-DPOP-ES256-WORKSPACE-CLEAR
        OAUTH2-DPOP-ES256-S-OK = _odpt-assert
    _odpt-work-zero? _odpt-assert
    0 OAUTH2-DPOP-ES256-WORKSPACE-CLEAR
        OAUTH2-DPOP-ES256-S-INVALID = _odpt-assert
    _odpt-stack ;

: _ODPT-RUN  ( -- )
    0 _odpt-fails !
    0 _odpt-checks !
    DEPTH _odpt-depth !
    _odpt-test-vocabulary
    _odpt-test-boundaries
    _odpt-test-proof
    _odpt-stack
    _odpt-fails @ 0= IF
        ." OAUTH2 DPOP ES256 PASS " _odpt-checks @ . CR
    ELSE
        ." OAUTH2 DPOP ES256 FAIL " _odpt-fails @ .
        ." / " _odpt-checks @ . CR
    THEN ;
