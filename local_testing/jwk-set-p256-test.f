\ Focused contracts for checked homogeneous public P-256 JWK Sets.

PROVIDED jwk-set-p256-test

VARIABLE _jjkst-checks
VARIABLE _jjkst-fails
VARIABLE _jjkst-depth
VARIABLE _jjkst-document-u
VARIABLE _jjkst-copy-u
VARIABLE _jjkst-selector-u
VARIABLE _jjkst-kid-a
VARIABLE _jjkst-kid-u
VARIABLE _jjkst-member-count
VARIABLE _jjkst-set-count
VARIABLE _jjkst-y-mode
VARIABLE _jjkst-core-mode
VARIABLE _jjkst-kid-mode
VARIABLE _jjkst-use-mode
VARIABLE _jjkst-alg-mode
VARIABLE _jjkst-ops-mode
VARIABLE _jjkst-extra-mode
VARIABLE _jjkst-expected-public
VARIABLE _jjkst-expected-thumbprint

JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES 8 +
    CONSTANT _JJKST-DOCUMENT-SIZE

CREATE _jjkst-document _JJKST-DOCUMENT-SIZE ALLOT
CREATE _jjkst-document-copy _JJKST-DOCUMENT-SIZE ALLOT
CREATE _jjkst-selector-storage
    JOSE-JWK-SET-P256-KID-CAPACITY 16 + ALLOT
CREATE _jjkst-selector-copy
    JOSE-JWK-SET-P256-KID-CAPACITY 16 + ALLOT
CREATE _jjkst-work-storage
    JOSE-JWK-SET-P256-WORKSPACE-SIZE 23 + ALLOT
CREATE _jjkst-public-storage
    JOSE-JWK-SET-P256-PUBLIC-SIZE 23 + ALLOT
CREATE _jjkst-thumbprint-storage
    JOSE-JWK-SET-P256-THUMBPRINT-SIZE 23 + ALLOT
CREATE _jjkst-long-kid
    JOSE-JWK-SET-P256-KID-CAPACITY 1+ ALLOT
CREATE _jjkst-generated-kid 1 ALLOT

: _jjkst-selector  ( -- address )
    _jjkst-selector-storage 7 + -8 AND ;

: _jjkst-work  ( -- workspace )
    _jjkst-work-storage 7 + -8 AND ;

: _jjkst-public  ( -- address )
    _jjkst-public-storage 7 + -8 AND ;

: _jjkst-thumbprint  ( -- address )
    _jjkst-thumbprint-storage 7 + -8 AND ;

: _jjkst-work-tail  ( -- address )
    _jjkst-work JOSE-JWK-SET-P256-WORKSPACE-SIZE + ;

: _jjkst-public-tail  ( -- address )
    _jjkst-public JOSE-JWK-SET-P256-PUBLIC-SIZE + ;

: _jjkst-thumbprint-tail  ( -- address )
    _jjkst-thumbprint JOSE-JWK-SET-P256-THUMBPRINT-SIZE + ;

: _jjkst-assert  ( flag -- )
    1 _jjkst-checks +!
    0= IF
        1 _jjkst-fails +!
        ." JOSE JWK SET P256 ASSERT " _jjkst-checks @ . CR
        TX-FLUSH
    THEN ;

: _jjkst-status  ( actual expected -- )
    2DUP <> IF
        ." JOSE JWK SET P256 STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _jjkst-assert ;

: _jjkst-stack  ( -- )
    DEPTH DUP _jjkst-depth @ <> IF
        ." JOSE JWK SET P256 STACK "
        _jjkst-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _jjkst-depth @ = _jjkst-assert ;

: _jjkst-byte?  ( address length byte -- flag )
    >R
    BEGIN DUP WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _jjkst-zero?  ( address length -- flag )
    0 _jjkst-byte? ;

: _jjkst-assert-span=  ( actual expected length -- )
    >R R@ SWAP R@ COMPARE 0= _jjkst-assert R> DROP ;

\ The two public points are the RFC 6979 sample point and its valid
\ P-256 Y-coordinate negation.  Thumbprints are independent RFC 7638
\ SHA-256 results over canonical JSON.

CREATE _jjkst-public-1
    0x04 C, 0x60 C, 0xFE C, 0xD4 C, 0xBA C, 0x25 C, 0x5A C, 0x9D C,
    0x31 C, 0xC9 C, 0x61 C, 0xEB C, 0x74 C, 0xC6 C, 0x35 C, 0x6D C,
    0x68 C, 0xC0 C, 0x49 C, 0xB8 C, 0x92 C, 0x3B C, 0x61 C, 0xFA C,
    0x6C C, 0xE6 C, 0x69 C, 0x62 C, 0x2E C, 0x60 C, 0xF2 C, 0x9F C,
    0xB6 C, 0x79 C, 0x03 C, 0xFE C, 0x10 C, 0x08 C, 0xB8 C, 0xBC C,
    0x99 C, 0xA4 C, 0x1A C, 0xE9 C, 0xE9 C, 0x56 C, 0x28 C, 0xBC C,
    0x64 C, 0xF2 C, 0xF1 C, 0xB2 C, 0x0C C, 0x2D C, 0x7E C, 0x9F C,
    0x51 C, 0x77 C, 0xA3 C, 0xC2 C, 0x94 C, 0xD4 C, 0x46 C, 0x22 C,
    0x99 C,

CREATE _jjkst-public-2
    0x04 C, 0x60 C, 0xFE C, 0xD4 C, 0xBA C, 0x25 C, 0x5A C, 0x9D C,
    0x31 C, 0xC9 C, 0x61 C, 0xEB C, 0x74 C, 0xC6 C, 0x35 C, 0x6D C,
    0x68 C, 0xC0 C, 0x49 C, 0xB8 C, 0x92 C, 0x3B C, 0x61 C, 0xFA C,
    0x6C C, 0xE6 C, 0x69 C, 0x62 C, 0x2E C, 0x60 C, 0xF2 C, 0x9F C,
    0xB6 C, 0x86 C, 0xFC C, 0x01 C, 0xEE C, 0xF7 C, 0x47 C, 0x43 C,
    0x67 C, 0x5B C, 0xE5 C, 0x16 C, 0x16 C, 0xA9 C, 0xD7 C, 0x43 C,
    0x9B C, 0x0D C, 0x0E C, 0x4D C, 0xF4 C, 0xD2 C, 0x81 C, 0x60 C,
    0xAE C, 0x88 C, 0x5C C, 0x3D C, 0x6B C, 0x2B C, 0xB9 C, 0xDD C,
    0x66 C,

CREATE _jjkst-thumbprint-1
    0x0C C, 0xEB C, 0xF1 C, 0xBC C, 0x98 C, 0x80 C, 0x74 C, 0x8A C,
    0x95 C, 0x58 C, 0x89 C, 0x05 C, 0xB7 C, 0x98 C, 0x43 C, 0xB4 C,
    0x2B C, 0xA7 C, 0x5C C, 0xB1 C, 0x74 C, 0x05 C, 0x5E C, 0x3E C,
    0x24 C, 0x6B C, 0xF8 C, 0x7F C, 0xE0 C, 0x0B C, 0x4A C, 0x6D C,

CREATE _jjkst-thumbprint-2
    0xA1 C, 0x10 C, 0x38 C, 0x9F C, 0x0E C, 0x50 C, 0xBE C, 0xA7 C,
    0x08 C, 0xD3 C, 0xA1 C, 0xE5 C, 0x98 C, 0x44 C, 0x5C C, 0xAA C,
    0xEC C, 0xA2 C, 0x5F C, 0x06 C, 0xE3 C, 0x7E C, 0x58 C, 0x64 C,
    0x67 C, 0x22 C, 0x43 C, 0xAA C, 0xC9 C, 0x22 C, 0x7A C, 0x0D C,

\ =====================================================================
\  Bounded document and selector builders
\ =====================================================================

: _jjkst-document-reset  ( -- )
    0 _jjkst-document-u ! ;

: _jjkst-document-char  ( byte -- )
    _jjkst-document-u @ _JJKST-DOCUMENT-SIZE >= IF
        DROP 0 _jjkst-assert EXIT
    THEN
    _jjkst-document _jjkst-document-u @ + C!
    1 _jjkst-document-u +! ;

: _jjkst-document-text  ( address length -- )
    DUP _jjkst-copy-u !
    _jjkst-document-u @ OVER + _JJKST-DOCUMENT-SIZE > IF
        2DROP 0 _jjkst-assert EXIT
    THEN
    _jjkst-document _jjkst-document-u @ + SWAP MOVE
    _jjkst-copy-u @ _jjkst-document-u +! ;

: _jjkst-repeat-char  ( byte count -- )
    BEGIN DUP WHILE
        OVER _jjkst-document-char
        1-
    REPEAT
    2DROP ;

: _jjkst-quote     ( -- ) 34 _jjkst-document-char ;
: _jjkst-comma     ( -- ) 44 _jjkst-document-char ;
: _jjkst-colon     ( -- ) 58 _jjkst-document-char ;
: _jjkst-backslash ( -- ) 92 _jjkst-document-char ;
: _jjkst-lbrace    ( -- ) 123 _jjkst-document-char ;
: _jjkst-rbrace    ( -- ) 125 _jjkst-document-char ;
: _jjkst-lbracket  ( -- ) 91 _jjkst-document-char ;
: _jjkst-rbracket  ( -- ) 93 _jjkst-document-char ;

: _jjkst-key  ( address length -- )
    _jjkst-quote _jjkst-document-text
    _jjkst-quote _jjkst-colon ;

: _jjkst-string  ( address length -- )
    _jjkst-quote _jjkst-document-text _jjkst-quote ;

: _jjkst-member-prefix  ( address length -- )
    _jjkst-member-count @ IF _jjkst-comma THEN
    _jjkst-key
    1 _jjkst-member-count +! ;

: _jjkst-kid!  ( address length -- )
    _jjkst-kid-u ! _jjkst-kid-a ! ;

: _jjkst-default-key  ( -- )
    S" target" _jjkst-kid!
    0 _jjkst-y-mode !
    0 _jjkst-core-mode !
    0 _jjkst-kid-mode !
    0 _jjkst-use-mode !
    0 _jjkst-alg-mode !
    0 _jjkst-ops-mode !
    0 _jjkst-extra-mode ! ;

: _jjkst-emit-kid  ( -- )
    _jjkst-kid-mode @ 1 = IF EXIT THEN
    _jjkst-kid-mode @ 3 = IF
        _jjkst-member-count @ IF _jjkst-comma THEN
        _jjkst-quote _jjkst-backslash S" u006bid"
            _jjkst-document-text
        _jjkst-quote _jjkst-colon
        _jjkst-quote S" target-" _jjkst-document-text
        _jjkst-backslash S" u0032" _jjkst-document-text
        _jjkst-quote
        1 _jjkst-member-count +!
        EXIT
    THEN
    S" kid" _jjkst-member-prefix
    _jjkst-kid-mode @ 2 = IF
        S" 7" _jjkst-document-text
        EXIT
    THEN
    _jjkst-kid-a @ _jjkst-kid-u @ _jjkst-string ;

: _jjkst-emit-core  ( -- )
    S" kty" _jjkst-member-prefix
    _jjkst-core-mode @ 1 = IF
        S" RSA" _jjkst-string
    ELSE
        S" EC" _jjkst-string
    THEN

    S" crv" _jjkst-member-prefix S" P-256" _jjkst-string

    S" x" _jjkst-member-prefix
    _jjkst-core-mode @ 2 = IF
        S" +" _jjkst-string
    ELSE
        S" YP7UuiVanTHJYet0xjVtaMBJuJI7Yfps5mliLmDyn7Y"
            _jjkst-string
    THEN

    _jjkst-core-mode @ 3 <> IF
        S" y" _jjkst-member-prefix
        _jjkst-y-mode @ IF
            S" hvwB7vdHQ2db5RYWqddDmw0OTfTSgWCuiFw9ayu53WY"
                _jjkst-string
        ELSE
            S" eQP-EAi4vJmkGunpVii8ZPLxsgwtfp9Rd6PClNRGIpk"
                _jjkst-string
        THEN
    THEN ;

: _jjkst-emit-use  ( -- )
    _jjkst-use-mode @ 0= IF EXIT THEN
    S" use" _jjkst-member-prefix
    _jjkst-use-mode @ 3 = IF
        S" 7" _jjkst-document-text EXIT
    THEN
    _jjkst-use-mode @ 1 = IF
        S" sig" _jjkst-string
    ELSE
        S" enc" _jjkst-string
    THEN ;

: _jjkst-emit-algorithm  ( -- )
    _jjkst-alg-mode @ 0= IF EXIT THEN
    S" alg" _jjkst-member-prefix
    _jjkst-alg-mode @ 1 = IF
        S" ES256" _jjkst-string
    ELSE
        S" ES256K" _jjkst-string
    THEN ;

: _jjkst-emit-escaped-verify  ( -- )
    _jjkst-quote S" ver" _jjkst-document-text
    _jjkst-backslash S" u0069" _jjkst-document-text
    S" fy" _jjkst-document-text _jjkst-quote ;

: _jjkst-emit-key-ops  ( -- )
    _jjkst-ops-mode @ 0= IF EXIT THEN
    S" key_ops" _jjkst-member-prefix
    _jjkst-ops-mode @ 5 = IF
        S" verify" _jjkst-string EXIT
    THEN
    _jjkst-lbracket
    _jjkst-ops-mode @ 4 <> IF
        _jjkst-ops-mode @ 6 = IF
            _jjkst-emit-escaped-verify
        ELSE
            _jjkst-ops-mode @ 2 = IF
                S" sign" _jjkst-string
            ELSE
                S" verify" _jjkst-string
            THEN
        THEN
    THEN
    _jjkst-ops-mode @ 3 = IF
        _jjkst-comma S" sign" _jjkst-string
    THEN
    _jjkst-rbracket ;

: _jjkst-emit-nested-trap  ( -- )
    S" meta" _jjkst-member-prefix _jjkst-lbrace
    S" trap" _jjkst-key S" literal },]" _jjkst-string
    _jjkst-comma S" array" _jjkst-key _jjkst-lbracket
    S" 1" _jjkst-document-text _jjkst-comma _jjkst-lbrace
    S" text" _jjkst-key
    _jjkst-quote S" quote " _jjkst-document-text
    _jjkst-backslash _jjkst-quote
    S"  and ]}" _jjkst-document-text _jjkst-quote
    _jjkst-rbrace _jjkst-rbracket
    _jjkst-rbrace ;

: _jjkst-emit-extra  ( -- )
    _jjkst-extra-mode @ 0= IF EXIT THEN
    _jjkst-extra-mode @ 1 = IF
        S" k" _jjkst-member-prefix S" AA" _jjkst-string EXIT
    THEN
    _jjkst-extra-mode @ 2 = IF
        _jjkst-member-count @ IF _jjkst-comma THEN
        _jjkst-quote _jjkst-backslash S" u0064"
            _jjkst-document-text
        _jjkst-quote _jjkst-colon S" AA" _jjkst-string
        1 _jjkst-member-count +!
        EXIT
    THEN
    _jjkst-extra-mode @ 3 = IF
        S" x5t" _jjkst-member-prefix S" AA" _jjkst-string EXIT
    THEN
    _jjkst-extra-mode @ 4 = IF
        S" kid" _jjkst-member-prefix S" duplicate" _jjkst-string EXIT
    THEN
    _jjkst-extra-mode @ 5 = IF
        _jjkst-emit-nested-trap EXIT
    THEN
    _jjkst-extra-mode @ 6 = IF
        S" priv" _jjkst-member-prefix S" AA" _jjkst-string EXIT
    THEN
    _jjkst-extra-mode @ 7 = IF
        S" nbf" _jjkst-member-prefix S" 0" _jjkst-document-text EXIT
    THEN
    _jjkst-extra-mode @ 8 = IF
        S" exp" _jjkst-member-prefix S" 0" _jjkst-document-text EXIT
    THEN
    S" revoked" _jjkst-member-prefix
    _jjkst-lbrace S" revoked_at" _jjkst-key
    S" 0" _jjkst-document-text _jjkst-rbrace ;

: _jjkst-emit-key  ( -- )
    _jjkst-lbrace
    0 _jjkst-member-count !
    _jjkst-emit-kid
    _jjkst-emit-core
    _jjkst-emit-use
    _jjkst-emit-algorithm
    _jjkst-emit-key-ops
    _jjkst-emit-extra
    _jjkst-rbrace ;

: _jjkst-set-start  ( -- )
    _jjkst-document-reset
    0 _jjkst-set-count !
    _jjkst-lbrace S" keys" _jjkst-key _jjkst-lbracket ;

: _jjkst-set-start-escaped  ( -- )
    _jjkst-document-reset
    0 _jjkst-set-count !
    _jjkst-lbrace
    _jjkst-quote _jjkst-backslash S" u006beys"
        _jjkst-document-text
    _jjkst-quote _jjkst-colon _jjkst-lbracket ;

: _jjkst-set-key  ( -- )
    _jjkst-set-count @ IF _jjkst-comma THEN
    _jjkst-emit-key
    1 _jjkst-set-count +! ;

: _jjkst-set-end  ( -- )
    _jjkst-rbracket _jjkst-rbrace ;

: _jjkst-set-end-with-extension  ( -- )
    _jjkst-rbracket
    _jjkst-comma S" issuer" _jjkst-key S" local" _jjkst-string
    _jjkst-rbrace ;

: _jjkst-build-one  ( -- )
    _jjkst-set-start _jjkst-set-key _jjkst-set-end ;

: _jjkst-selector!  ( address length -- )
    DUP JOSE-JWK-SET-P256-KID-CAPACITY 1+ > IF
        2DROP 0 _jjkst-assert EXIT
    THEN
    DUP _jjkst-selector-u !
    _jjkst-selector SWAP MOVE ;

: _jjkst-snapshot-inputs  ( -- )
    _jjkst-document _jjkst-document-copy
    _jjkst-document-u @ MOVE
    _jjkst-selector _jjkst-selector-copy
    _jjkst-selector-u @ MOVE ;

: _jjkst-inputs-unchanged?  ( -- flag )
    _jjkst-document _jjkst-document-u @
    _jjkst-document-copy _jjkst-document-u @
    COMPARE 0=
    _jjkst-selector _jjkst-selector-u @
    _jjkst-selector-copy _jjkst-selector-u @
    COMPARE 0= AND ;

: _jjkst-prepare-call  ( -- )
    _jjkst-public JOSE-JWK-SET-P256-PUBLIC-SIZE 8 + 0xA5 FILL
    _jjkst-thumbprint
        JOSE-JWK-SET-P256-THUMBPRINT-SIZE 8 + 0xB6 FILL
    _jjkst-work
        JOSE-JWK-SET-P256-WORKSPACE-SIZE 8 + 0xC3 FILL
    _jjkst-snapshot-inputs ;

: _jjkst-select  ( -- status )
    _jjkst-document _jjkst-document-u @
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT ;

: _jjkst-work-zero?  ( -- flag )
    _jjkst-work JOSE-JWK-SET-P256-WORKSPACE-SIZE _jjkst-zero? ;

: _jjkst-work-tail-unchanged?  ( -- flag )
    _jjkst-work-tail 8 0xC3 _jjkst-byte? ;

: _jjkst-outputs-unchanged?  ( -- flag )
    _jjkst-public JOSE-JWK-SET-P256-PUBLIC-SIZE 8 +
        0xA5 _jjkst-byte?
    _jjkst-thumbprint JOSE-JWK-SET-P256-THUMBPRINT-SIZE 8 +
        0xB6 _jjkst-byte? AND ;

: _jjkst-expect-success
  ( expected-public expected-thumbprint -- )
    _jjkst-expected-thumbprint !
    _jjkst-expected-public !
    _jjkst-prepare-call
    _jjkst-select JOSE-JWK-SET-P256-S-OK _jjkst-status
    _jjkst-inputs-unchanged? _jjkst-assert
    _jjkst-public _jjkst-expected-public @
        JOSE-JWK-SET-P256-PUBLIC-SIZE _jjkst-assert-span=
    _jjkst-thumbprint _jjkst-expected-thumbprint @
        JOSE-JWK-SET-P256-THUMBPRINT-SIZE _jjkst-assert-span=
    _jjkst-public-tail 8 0xA5 _jjkst-byte? _jjkst-assert
    _jjkst-thumbprint-tail 8 0xB6 _jjkst-byte? _jjkst-assert
    _jjkst-work-zero? _jjkst-assert
    _jjkst-work-tail-unchanged? _jjkst-assert
    _jjkst-stack ;

: _jjkst-expect-failure  ( expected-status -- )
    >R
    _jjkst-prepare-call
    _jjkst-select R> _jjkst-status
    _jjkst-inputs-unchanged? _jjkst-assert
    _jjkst-outputs-unchanged? _jjkst-assert
    _jjkst-work-zero? _jjkst-assert
    _jjkst-work-tail-unchanged? _jjkst-assert
    _jjkst-stack ;

: _jjkst-assert-preflight-state  ( -- )
    _jjkst-inputs-unchanged? _jjkst-assert
    _jjkst-outputs-unchanged? _jjkst-assert
    _jjkst-work JOSE-JWK-SET-P256-WORKSPACE-SIZE 8 +
        0xC3 _jjkst-byte? _jjkst-assert
    _jjkst-stack ;

: _jjkst-build-three  ( selected-position -- )
    >R
    _jjkst-set-start

    _jjkst-default-key S" first" _jjkst-kid!
    R@ 0= IF 1 _jjkst-y-mode ! THEN
    _jjkst-set-key

    _jjkst-default-key S" middle" _jjkst-kid!
    R@ 1 = IF 1 _jjkst-y-mode ! THEN
    _jjkst-set-key

    _jjkst-default-key S" last" _jjkst-kid!
    R@ 2 = IF 1 _jjkst-y-mode ! THEN
    _jjkst-set-key

    _jjkst-set-end
    R> DROP ;

: _jjkst-generated-char  ( index -- byte )
    DUP 26 < IF
        97 + EXIT
    THEN
    26 - 65 + ;

: _jjkst-build-key-count  ( count selected-index -- )
    >R
    _jjkst-set-start
    0 SWAP
    BEGIN
        2DUP <
    WHILE
        OVER _jjkst-generated-char _jjkst-generated-kid C!
        _jjkst-default-key
        _jjkst-generated-kid 1 _jjkst-kid!
        OVER R@ = IF 1 _jjkst-y-mode ! THEN
        _jjkst-set-key
        SWAP 1+ SWAP
    REPEAT
    2DROP
    _jjkst-set-end
    R> DROP ;

\ =====================================================================
\  Contract groups
\ =====================================================================

: _jjkst-test-statuses  ( -- )
    JOSE-JWK-SET-P256-PUBLIC-SIZE 65 = _jjkst-assert
    JOSE-JWK-SET-P256-THUMBPRINT-SIZE 32 = _jjkst-assert
    JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES 65536 = _jjkst-assert
    JOSE-JWK-SET-P256-MAX-KEYS 32 = _jjkst-assert
    JOSE-JWK-SET-P256-MAX-MEMBERS 32 = _jjkst-assert
    JOSE-JWK-SET-P256-KID-CAPACITY 256 = _jjkst-assert
    JOSE-JWK-SET-P256-WORKSPACE-SIZE 39528 = _jjkst-assert

    JOSE-JWK-SET-P256-S-OK
        JOSE-JWK-SET-P256-STATUS-VALID? _jjkst-assert
    JOSE-JWK-SET-P256-S-SENSITIVE
        JOSE-JWK-SET-P256-STATUS-VALID? _jjkst-assert
    JOSE-JWK-SET-P256-S-CRYPTO
        JOSE-JWK-SET-P256-STATUS-VALID? _jjkst-assert
    JOSE-JWK-SET-P256-S-INTERNAL
        JOSE-JWK-SET-P256-STATUS-VALID? _jjkst-assert
    JOSE-JWK-SET-P256-S-RANGE
        JOSE-JWK-SET-P256-STATUS-VALID? _jjkst-assert
    JOSE-JWK-SET-P256-S-PROTECTED
        JOSE-JWK-SET-P256-STATUS-VALID? _jjkst-assert
    JOSE-JWK-SET-P256-S-PLATFORM
        JOSE-JWK-SET-P256-STATUS-VALID? _jjkst-assert
    JOSE-JWK-SET-P256-S-PLATFORM 1+
        JOSE-JWK-SET-P256-STATUS-VALID? 0= _jjkst-assert

    _jjkst-work JOSE-JWK-SET-P256-WORKSPACE-SIZE 8 +
        0xC3 FILL
    _jjkst-work JOSE-JWK-SET-P256-WORKSPACE-CLEAR
        JOSE-JWK-SET-P256-S-OK _jjkst-status
    _jjkst-work-zero? _jjkst-assert
    _jjkst-work-tail-unchanged? _jjkst-assert
    _jjkst-stack ;

: _jjkst-test-successes  ( -- )
    _jjkst-default-key _jjkst-build-one
    S" target" _jjkst-selector!
    _jjkst-public-1 _jjkst-thumbprint-1 _jjkst-expect-success

    \ Published output remains self-contained after source destruction.
    _jjkst-document _jjkst-document-u @ 0 FILL
    _jjkst-public _jjkst-public-1
        JOSE-JWK-SET-P256-PUBLIC-SIZE _jjkst-assert-span=
    _jjkst-thumbprint _jjkst-thumbprint-1
        JOSE-JWK-SET-P256-THUMBPRINT-SIZE _jjkst-assert-span=

    _jjkst-default-key
    1 _jjkst-use-mode !
    1 _jjkst-alg-mode !
    1 _jjkst-ops-mode !
    5 _jjkst-extra-mode !
    _jjkst-set-start _jjkst-set-key
    _jjkst-set-end-with-extension
    S" target" _jjkst-selector!
    _jjkst-public-1 _jjkst-thumbprint-1 _jjkst-expect-success

    0 _jjkst-build-three
    S" first" _jjkst-selector!
    _jjkst-public-2 _jjkst-thumbprint-2 _jjkst-expect-success

    1 _jjkst-build-three
    S" middle" _jjkst-selector!
    _jjkst-public-2 _jjkst-thumbprint-2 _jjkst-expect-success

    2 _jjkst-build-three
    S" last" _jjkst-selector!
    _jjkst-public-2 _jjkst-thumbprint-2 _jjkst-expect-success

    _jjkst-default-key
    3 _jjkst-kid-mode !
    6 _jjkst-ops-mode !
    _jjkst-set-start-escaped _jjkst-set-key _jjkst-set-end
    S" target-2" _jjkst-selector!
    _jjkst-public-1 _jjkst-thumbprint-1 _jjkst-expect-success
    _jjkst-stack ;

: _jjkst-test-envelope  ( -- )
    S" target" _jjkst-selector!

    _jjkst-document-reset _jjkst-lbrace _jjkst-rbrace
    JOSE-JWK-SET-P256-S-MISSING _jjkst-expect-failure

    _jjkst-document-reset _jjkst-lbrace
    S" keys" _jjkst-key _jjkst-lbrace _jjkst-rbrace _jjkst-rbrace
    JOSE-JWK-SET-P256-S-TYPE _jjkst-expect-failure

    _jjkst-set-start _jjkst-set-end
    JOSE-JWK-SET-P256-S-EMPTY _jjkst-expect-failure

    _jjkst-set-start S" 7" _jjkst-document-text
    1 _jjkst-set-count +! _jjkst-set-end
    JOSE-JWK-SET-P256-S-TYPE _jjkst-expect-failure

    _jjkst-default-key _jjkst-build-one
    120 _jjkst-document-char
    JOSE-JWK-SET-P256-S-JSON _jjkst-expect-failure

    _jjkst-document-reset _jjkst-lbrace
    S" keys" _jjkst-key _jjkst-lbracket _jjkst-rbracket
    _jjkst-comma
    _jjkst-quote _jjkst-backslash S" u006beys"
        _jjkst-document-text
    _jjkst-quote _jjkst-colon _jjkst-lbracket _jjkst-rbracket
    _jjkst-rbrace
    JOSE-JWK-SET-P256-S-JSON _jjkst-expect-failure

    _jjkst-default-key
    4 _jjkst-extra-mode !
    _jjkst-build-one
    JOSE-JWK-SET-P256-S-JSON _jjkst-expect-failure
    _jjkst-stack ;

: _jjkst-test-policy  ( -- )
    S" target" _jjkst-selector!

    _jjkst-default-key 1 _jjkst-kid-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-MISSING _jjkst-expect-failure

    _jjkst-default-key 2 _jjkst-kid-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-TYPE _jjkst-expect-failure

    _jjkst-default-key S" " _jjkst-kid! _jjkst-build-one
    JOSE-JWK-SET-P256-S-EMPTY _jjkst-expect-failure

    _jjkst-long-kid
        JOSE-JWK-SET-P256-KID-CAPACITY 1+ 97 FILL
    _jjkst-default-key
    _jjkst-long-kid JOSE-JWK-SET-P256-KID-CAPACITY 1+
        _jjkst-kid!
    _jjkst-build-one
    JOSE-JWK-SET-P256-S-CAPACITY _jjkst-expect-failure

    _jjkst-default-key 1 _jjkst-core-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-KEY _jjkst-expect-failure

    _jjkst-default-key 2 _jjkst-core-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-KEY _jjkst-expect-failure

    _jjkst-default-key 3 _jjkst-core-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-KEY _jjkst-expect-failure

    _jjkst-default-key 1 _jjkst-extra-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-SENSITIVE _jjkst-expect-failure

    _jjkst-default-key 2 _jjkst-extra-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-SENSITIVE _jjkst-expect-failure

    _jjkst-default-key 3 _jjkst-extra-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-UNSUPPORTED _jjkst-expect-failure

    _jjkst-default-key 6 _jjkst-extra-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-SENSITIVE _jjkst-expect-failure

    _jjkst-default-key 7 _jjkst-extra-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-UNSUPPORTED _jjkst-expect-failure

    _jjkst-default-key 8 _jjkst-extra-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-UNSUPPORTED _jjkst-expect-failure

    _jjkst-default-key 9 _jjkst-extra-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-UNSUPPORTED _jjkst-expect-failure

    _jjkst-default-key 2 _jjkst-use-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-USE _jjkst-expect-failure

    _jjkst-default-key 3 _jjkst-use-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-USE _jjkst-expect-failure

    _jjkst-default-key 2 _jjkst-alg-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-ALGORITHM _jjkst-expect-failure

    _jjkst-default-key 2 _jjkst-ops-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-KEY-OPS _jjkst-expect-failure

    _jjkst-default-key 3 _jjkst-ops-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-KEY-OPS _jjkst-expect-failure

    _jjkst-default-key 4 _jjkst-ops-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-KEY-OPS _jjkst-expect-failure

    _jjkst-default-key 5 _jjkst-ops-mode ! _jjkst-build-one
    JOSE-JWK-SET-P256-S-KEY-OPS _jjkst-expect-failure

    _jjkst-default-key _jjkst-build-one
    S" absent" _jjkst-selector!
    JOSE-JWK-SET-P256-S-NOT-FOUND _jjkst-expect-failure

    \ Global decoded-kid uniqueness is enforced even for unselected keys.
    _jjkst-set-start
    _jjkst-default-key S" duplicate" _jjkst-kid! _jjkst-set-key
    _jjkst-default-key S" duplicate" _jjkst-kid!
    1 _jjkst-y-mode ! _jjkst-set-key
    _jjkst-set-end
    S" absent" _jjkst-selector!
    JOSE-JWK-SET-P256-S-DUPLICATE _jjkst-expect-failure

    \ A selected key does not short-circuit a later sensitive candidate.
    _jjkst-set-start
    _jjkst-default-key S" target" _jjkst-kid! _jjkst-set-key
    _jjkst-default-key S" later" _jjkst-kid!
    1 _jjkst-extra-mode ! _jjkst-set-key
    _jjkst-set-end
    S" target" _jjkst-selector!
    JOSE-JWK-SET-P256-S-SENSITIVE _jjkst-expect-failure

    \ An invalid candidate before the selected key also rejects the set.
    _jjkst-set-start
    _jjkst-default-key S" earlier" _jjkst-kid!
    2 _jjkst-core-mode ! _jjkst-set-key
    _jjkst-default-key S" target" _jjkst-kid! _jjkst-set-key
    _jjkst-set-end
    JOSE-JWK-SET-P256-S-KEY _jjkst-expect-failure
    _jjkst-stack ;

: _jjkst-bad-span  ( -- address length )
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2 ;

: _jjkst-test-preflight-ownership  ( -- )
    _jjkst-default-key _jjkst-build-one
    S" target" _jjkst-selector!

    _jjkst-prepare-call
    _jjkst-document 0
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-INVALID _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-document
        JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES 1+
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-CAPACITY _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-bad-span
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-RANGE _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    1 1
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-PROTECTED _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-selector 0
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-INVALID _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-selector
        JOSE-JWK-SET-P256-KID-CAPACITY 1+ 97 FILL
    JOSE-JWK-SET-P256-KID-CAPACITY 1+ _jjkst-selector-u !
    _jjkst-prepare-call
    _jjkst-select
        JOSE-JWK-SET-P256-S-CAPACITY _jjkst-status
    _jjkst-assert-preflight-state

    S" target" _jjkst-selector!
    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-thumbprint _jjkst-work 1+
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-INVALID _jjkst-status
    _jjkst-assert-preflight-state

    \ Source/output, source/workspace, selector/output, selector/workspace,
    \ output/output, and output/workspace aliases are all rejected.
    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-selector _jjkst-selector-u @
    _jjkst-document _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-ALIAS _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-work _jjkst-document-u @
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-ALIAS _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-public 6
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-ALIAS _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-work 6
    _jjkst-public _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-ALIAS _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-public _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-ALIAS _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-selector _jjkst-selector-u @
    _jjkst-work _jjkst-thumbprint _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-ALIAS _jjkst-status
    _jjkst-assert-preflight-state

    _jjkst-prepare-call
    _jjkst-document _jjkst-document-u @
    _jjkst-selector _jjkst-selector-u @
    _jjkst-public _jjkst-work _jjkst-work
    JOSE-JWK-SET-P256-SELECT
        JOSE-JWK-SET-P256-S-ALIAS _jjkst-status
    _jjkst-assert-preflight-state
    _jjkst-stack ;

: _jjkst-test-key-bound  ( -- )
    32 15 _jjkst-build-key-count
    S" p" _jjkst-selector!
    _jjkst-public-2 _jjkst-thumbprint-2 _jjkst-expect-success

    33 15 _jjkst-build-key-count
    S" p" _jjkst-selector!
    JOSE-JWK-SET-P256-S-CAPACITY _jjkst-expect-failure
    _jjkst-stack ;

: _JJKST-INIT  ( -- )
    0 _jjkst-checks !
    0 _jjkst-fails !
    DEPTH _jjkst-depth !
    _jjkst-default-key ;

: _JJKST-FINISH  ( -- )
    _jjkst-stack
    _jjkst-fails @ 0= IF
        ." JOSE JWK SET P256 PASS" CR
    ELSE
        ." JOSE JWK SET P256 FAIL " _jjkst-fails @ . CR
    THEN
    TX-FLUSH ;

: _JJKST-RUN  ( -- )
    _JJKST-INIT
    _jjkst-test-statuses
    _jjkst-test-successes
    _jjkst-test-envelope
    _jjkst-test-policy
    _jjkst-test-preflight-ownership
    _jjkst-test-key-bound
    _JJKST-FINISH ;
