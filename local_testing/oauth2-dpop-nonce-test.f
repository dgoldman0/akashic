\ Focused contracts for issuer-bound OAuth DPoP nonce ownership.

PROVIDED akashic-o2dn-contracts

VARIABLE _o2dnt-checks
VARIABLE _o2dnt-fails
VARIABLE _o2dnt-depth
VARIABLE _o2dnt-callback-runs

CREATE _o2dnt-owner-store OAUTH2-DPOP-NONCE-SIZE 7 + ALLOT
CREATE _o2dnt-snapshot OAUTH2-DPOP-NONCE-SIZE ALLOT

: _o2dnt-owner  ( -- owner )
    _o2dnt-owner-store 7 + -8 AND ;

: _o2dnt-server  ( -- address length )
    S" https://issuer.example" ;

: _o2dnt-other-server  ( -- address length )
    S" https://other.example" ;

: _o2dnt-first-nonce  ( -- address length )
    S" first-server-nonce-with-tail" ;

: _o2dnt-second-nonce  ( -- address length )
    S" replacement-nonce" ;

: _o2dnt-assert  ( flag -- )
    1 _o2dnt-checks +!
    0= IF
        1 _o2dnt-fails +!
        ." OAUTH2 DPOP NONCE ASSERT " _o2dnt-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2dnt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 DPOP NONCE STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2dnt-assert ;

: _o2dnt-stack  ( -- )
    DEPTH _o2dnt-depth @ = _o2dnt-assert ;

: _o2dnt-zero?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1 /STRING
    REPEAT
    2DROP -1 ;

: _o2dnt-snapshot!  ( -- )
    _o2dnt-owner _o2dnt-snapshot
    OAUTH2-DPOP-NONCE-SIZE MOVE ;

: _o2dnt-unchanged?  ( -- flag )
    _o2dnt-owner _o2dnt-snapshot
    OAUTH2-DPOP-NONCE-SIZE COMPARE 0= ;

: _o2dnt-tail-zero?  ( -- flag )
    _o2dnt-second-nonce NIP DUP
    _o2dnt-owner _O2DN.NONCE + SWAP
    OAUTH2-DPOP-NONCE-CAPACITY SWAP -
    _o2dnt-zero? ;

: _o2dnt-first-borrow
  ( nonce-a nonce-u generation context -- callback-result )
    _o2dnt-owner = _o2dnt-assert
    1 = _o2dnt-assert
    2DUP _o2dnt-first-nonce COMPARE 0= _o2dnt-assert
    2DROP

    _o2dnt-server _o2dnt-second-nonce _o2dnt-owner
    OAUTH2-DPOP-NONCE-REPLACE
        OAUTH2-DPOP-NONCE-S-BUSY _o2dnt-status

    1 _o2dnt-callback-runs +!
    701 ;

: _o2dnt-second-borrow
  ( nonce-a nonce-u generation context -- callback-result )
    _o2dnt-owner = _o2dnt-assert
    2 = _o2dnt-assert
    2DUP _o2dnt-second-nonce COMPARE 0= _o2dnt-assert
    2DROP
    1 _o2dnt-callback-runs +!
    702 ;

: _o2dnt-test-init-and-borrow  ( -- )
    OAUTH2-DPOP-NONCE-SERVER-CAPACITY
        O2CODE-ISSUER-CAPACITY = _o2dnt-assert
    OAUTH2-DPOP-NONCE-CAPACITY
        OAUTH2-HTTP-POST-NONCE-CAPACITY = _o2dnt-assert

    _o2dnt-owner OAUTH2-DPOP-NONCE-SIZE 0xA5 FILL
    _o2dnt-server _o2dnt-first-nonce _o2dnt-owner
    OAUTH2-DPOP-NONCE-INIT
        OAUTH2-DPOP-NONCE-S-OK _o2dnt-status
    _o2dnt-owner OAUTH2-DPOP-NONCE-VALID? _o2dnt-assert

    _o2dnt-owner OAUTH2-DPOP-NONCE-GENERATION@
        OAUTH2-DPOP-NONCE-S-OK _o2dnt-status
        1 = _o2dnt-assert

    0 _o2dnt-callback-runs !
    ['] _o2dnt-first-borrow _o2dnt-owner
    _o2dnt-server _o2dnt-owner OAUTH2-DPOP-NONCE-WITH
        OAUTH2-DPOP-NONCE-S-OK _o2dnt-status
        701 = _o2dnt-assert
    _o2dnt-callback-runs @ 1 = _o2dnt-assert
    _o2dnt-stack ;

: _o2dnt-test-rejections-unchanged  ( -- )
    _o2dnt-snapshot!
    _o2dnt-other-server _o2dnt-second-nonce _o2dnt-owner
    OAUTH2-DPOP-NONCE-REPLACE
        OAUTH2-DPOP-NONCE-S-BINDING _o2dnt-status
    _o2dnt-unchanged? _o2dnt-assert

    _o2dnt-snapshot!
    _o2dnt-server S" bad nonce" _o2dnt-owner
    OAUTH2-DPOP-NONCE-REPLACE
        OAUTH2-DPOP-NONCE-S-INVALID _o2dnt-status
    _o2dnt-unchanged? _o2dnt-assert
    _o2dnt-stack ;

: _o2dnt-test-replace-and-wipe  ( -- )
    _o2dnt-server _o2dnt-second-nonce _o2dnt-owner
    OAUTH2-DPOP-NONCE-REPLACE
        OAUTH2-DPOP-NONCE-S-OK _o2dnt-status

    _o2dnt-owner OAUTH2-DPOP-NONCE-GENERATION@
        OAUTH2-DPOP-NONCE-S-OK _o2dnt-status
        2 = _o2dnt-assert
    _o2dnt-owner _O2DN.NONCE
    _o2dnt-owner _O2DN.NONCE-U @
        _o2dnt-second-nonce COMPARE 0= _o2dnt-assert
    _o2dnt-tail-zero? _o2dnt-assert

    ['] _o2dnt-second-borrow _o2dnt-owner
    _o2dnt-server _o2dnt-owner OAUTH2-DPOP-NONCE-WITH
        OAUTH2-DPOP-NONCE-S-OK _o2dnt-status
        702 = _o2dnt-assert
    _o2dnt-callback-runs @ 2 = _o2dnt-assert

    _o2dnt-owner OAUTH2-DPOP-NONCE-WIPE
        OAUTH2-DPOP-NONCE-S-OK _o2dnt-status
    _o2dnt-owner OAUTH2-DPOP-NONCE-SIZE
        _o2dnt-zero? _o2dnt-assert
    _o2dnt-owner OAUTH2-DPOP-NONCE-VALID? 0= _o2dnt-assert
    _o2dnt-stack ;

: _O2DNT-RUN  ( -- )
    0 _o2dnt-checks !
    0 _o2dnt-fails !
    DEPTH _o2dnt-depth !
    _o2dnt-test-init-and-borrow
    _o2dnt-test-rejections-unchanged
    _o2dnt-test-replace-and-wipe
    ." OAUTH2 DPOP NONCE CHECKS " _o2dnt-checks @ . CR
    _o2dnt-fails @ IF
        ." OAUTH2 DPOP NONCE FAIL " _o2dnt-fails @ . CR
    ELSE
        ." OAUTH2 DPOP NONCE PASS" CR
    THEN
    TX-FLUSH ;
