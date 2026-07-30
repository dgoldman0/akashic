\ Focused contracts for the protected OAuth token-request owner.

PROVIDED akashic-o2tq-contracts

VARIABLE _o2tqt-checks
VARIABLE _o2tqt-fails
VARIABLE _o2tqt-depth
VARIABLE _o2tqt-attempt

CREATE _o2tqt-request-store O2TREQ-SIZE 7 + ALLOT
CREATE _o2tqt-code-store O2CODE-TRANSACTION-SIZE 7 + ALLOT

: _o2tqt-request  ( -- object )
    _o2tqt-request-store 7 + -8 AND ;

: _o2tqt-code  ( -- object )
    _o2tqt-code-store 7 + -8 AND ;

: _o2tqt-assert  ( flag -- )
    1 _o2tqt-checks +!
    0= IF
        1 _o2tqt-fails +!
        ." OAUTH2 TOKEN REQUEST ASSERT " _o2tqt-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2tqt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 TOKEN REQUEST STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2tqt-assert ;

: _o2tqt-stack  ( -- )
    DEPTH _o2tqt-depth @ = _o2tqt-assert ;

: _o2tqt-filled?  ( address length byte -- flag )
    0x0101010101010101 *
    BEGIN
        2 PICK 7 AND 0<>
        2 PICK 0<> AND
    WHILE
        2 PICK C@ OVER 0xFF AND <> IF
            2DROP DROP 0 EXIT
        THEN
        >R 1- SWAP 1+ SWAP R>
    REPEAT
    BEGIN 1 PICK 8 U< 0= WHILE
        2 PICK @ OVER <> IF
            2DROP DROP 0 EXIT
        THEN
        >R 8 - SWAP 8 + SWAP R>
    REPEAT
    BEGIN 1 PICK WHILE
        2 PICK C@ OVER 0xFF AND <> IF
            2DROP DROP 0 EXIT
        THEN
        >R 1- SWAP 1+ SWAP R>
    REPEAT
    2DROP DROP -1 ;

: _o2tqt-zero?  ( address length -- flag )
    0 _o2tqt-filled? ;

: _o2tqt-binding  ( -- address length )
    S" account-slot-17" ;

: _o2tqt-issuer  ( -- address length )
    S" https://issuer.example" ;

: _o2tqt-code-value  ( -- address length )
    S" opaque-authorization-code" ;

: _o2tqt-htu  ( -- address length )
    S" https://issuer.example/oauth/token" ;

: _o2tqt-copy
  ( source source-u destination length-field -- )
    >R OVER R@ ! R> DROP SWAP MOVE ;

: _o2tqt-code-ready  ( -- )
    _o2tqt-code O2CODE-INIT?
        O2CODE-S-OK _o2tqt-status
    _o2tqt-binding
        _o2tqt-code _O2C.BINDING
        _o2tqt-code _O2C.BINDING-U
        _o2tqt-copy
    _o2tqt-issuer
        _o2tqt-code _O2C.ISSUER
        _o2tqt-code _O2C.ISSUER-U
        _o2tqt-copy
    _o2tqt-code-value
        _o2tqt-code _O2C.CODE
        _o2tqt-code _O2C.CODE-U
        _o2tqt-copy
    _o2tqt-code _O2C.STATE
        O2CODE-STATE-SIZE [CHAR] s FILL
    _o2tqt-code _O2C.VERIFIER
        O2CODE-VERIFIER-SIZE [CHAR] v FILL
    _o2tqt-code _O2C.CHALLENGE
        O2CODE-CHALLENGE-SIZE [CHAR] c FILL
    O2CODE-ISSUER-REQUIRED
        _o2tqt-code _O2C.ISSUER-REQUIRED !
    12345 _o2tqt-code _O2C.DEADLINE !
    O2CODE-PHASE-CODE-READY
        _o2tqt-code _O2C.PHASE ! ;

: _o2tqt-request-phase  ( expected -- )
    >R
    _o2tqt-request O2TREQ-PHASE@
    O2TREQ-S-OK _o2tqt-status
    R> = _o2tqt-assert ;

: _o2tqt-code-phase  ( expected -- )
    >R
    _o2tqt-code O2CODE-PHASE@
    O2CODE-S-OK _o2tqt-status
    R> = _o2tqt-assert ;

: _o2tqt-drop15
  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 -- )
    DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP ;

: _o2tqt-build-check
  \ ( context binding binding-u issuer issuer-u issuer-required
  \   state state-u code code-u verifier verifier-u htu htu-u attempt
  \   -- callback-status )
    _o2tqt-attempt !
    2DUP _o2tqt-htu COMPARE 0= _o2tqt-assert
    2DROP
    2DUP [CHAR] v _o2tqt-filled? _o2tqt-assert
    NIP O2CODE-VERIFIER-SIZE = _o2tqt-assert
    2DUP _o2tqt-code-value COMPARE 0= _o2tqt-assert
    2DROP
    2DUP [CHAR] s _o2tqt-filled? _o2tqt-assert
    NIP O2CODE-STATE-SIZE = _o2tqt-assert
    O2CODE-ISSUER-REQUIRED = _o2tqt-assert
    2DUP _o2tqt-issuer COMPARE 0= _o2tqt-assert
    2DROP
    2DUP _o2tqt-binding COMPARE 0= _o2tqt-assert
    2DROP
    _o2tqt-request = _o2tqt-assert
    O2TREQ-S-OK ;

: _o2tqt-build-reject
  \ ( context binding binding-u issuer issuer-u issuer-required
  \   state state-u code code-u verifier verifier-u htu htu-u attempt
  \   -- callback-status )
    _o2tqt-drop15 91 ;

: _o2tqt-build-throw
  \ ( context binding binding-u issuer issuer-u issuer-required
  \   state state-u code code-u verifier verifier-u htu htu-u attempt
  \   -- callback-status )
    -811 THROW ;

: _o2tqt-provenance-check
  \ ( context binding binding-u issuer issuer-u issuer-required
  \   state state-u htu htu-u attempt -- callback-status )
    _o2tqt-attempt !
    2DUP _o2tqt-htu COMPARE 0= _o2tqt-assert
    2DROP
    2DUP [CHAR] s _o2tqt-filled? _o2tqt-assert
    NIP O2CODE-STATE-SIZE = _o2tqt-assert
    O2CODE-ISSUER-REQUIRED = _o2tqt-assert
    2DUP _o2tqt-issuer COMPARE 0= _o2tqt-assert
    2DROP
    2DUP _o2tqt-binding COMPARE 0= _o2tqt-assert
    2DROP
    DUP O2TREQ-CLAIM-RETRY
        O2TREQ-S-BUSY _o2tqt-status
    _o2tqt-request = _o2tqt-assert
    O2TREQ-S-OK ;

: _o2tqt-capture  ( -- status )
    _o2tqt-htu _o2tqt-code _o2tqt-request
    O2TREQ-CAPTURE ;

: _o2tqt-test-capture-and-alias  ( -- )
    _o2tqt-request O2TREQ-INIT?
        O2TREQ-S-OK _o2tqt-status
    _o2tqt-code-ready

    _o2tqt-request _O2TRQ.HTU 1
    _o2tqt-code _o2tqt-request O2TREQ-CAPTURE
        O2TREQ-S-ALIAS _o2tqt-status
    O2CODE-PHASE-CODE-READY _o2tqt-code-phase
    O2TREQ-PHASE-EMPTY _o2tqt-request-phase

    _o2tqt-code _O2C.ISSUER
    _o2tqt-code _O2C.ISSUER-U @
    _o2tqt-code _o2tqt-request O2TREQ-CAPTURE
        O2TREQ-S-ALIAS _o2tqt-status
    O2CODE-PHASE-CODE-READY _o2tqt-code-phase

    _o2tqt-capture O2TREQ-S-OK _o2tqt-status
    O2TREQ-PHASE-READY _o2tqt-request-phase
    O2CODE-PHASE-SPENT _o2tqt-code-phase
    _o2tqt-code _O2C.STATE O2CODE-STATE-SIZE
        _o2tqt-zero? _o2tqt-assert
    _o2tqt-code _O2C.CODE O2CODE-CODE-CAPACITY
        _o2tqt-zero? _o2tqt-assert
    _o2tqt-code _O2C.VERIFIER O2CODE-VERIFIER-SIZE
        _o2tqt-zero? _o2tqt-assert
    _o2tqt-stack ;

: _o2tqt-test-build-and-sole-retry  ( -- )
    ['] _o2tqt-provenance-check
    _o2tqt-request _o2tqt-request O2TREQ-WITH-PROVENANCE
        O2TREQ-S-PHASE _o2tqt-status

    ['] _o2tqt-build-reject
    _o2tqt-request _o2tqt-request O2TREQ-WITH-BUILD
        91 _o2tqt-status
    O2TREQ-PHASE-READY _o2tqt-request-phase

    ['] _o2tqt-build-throw
    _o2tqt-request _o2tqt-request O2TREQ-WITH-BUILD
        O2TREQ-S-CALLBACK _o2tqt-status
    O2TREQ-PHASE-READY _o2tqt-request-phase

    ['] _o2tqt-build-check
    _o2tqt-request _o2tqt-request O2TREQ-WITH-BUILD
        O2TREQ-S-OK _o2tqt-status
    O2TREQ-ATTEMPT-FIRST _o2tqt-attempt @ = _o2tqt-assert
    O2TREQ-PHASE-FIRST-AWAITING _o2tqt-request-phase

    ['] _o2tqt-provenance-check
    _o2tqt-request _o2tqt-request O2TREQ-WITH-PROVENANCE
        O2TREQ-S-OK _o2tqt-status
    O2TREQ-ATTEMPT-FIRST _o2tqt-attempt @ = _o2tqt-assert

    _o2tqt-request O2TREQ-CLAIM-RETRY
        O2TREQ-S-OK _o2tqt-status
    O2TREQ-PHASE-RETRY-READY _o2tqt-request-phase
    _o2tqt-request O2TREQ-CLAIM-RETRY
        O2TREQ-S-PHASE _o2tqt-status

    ['] _o2tqt-build-check
    _o2tqt-request _o2tqt-request O2TREQ-WITH-BUILD
        O2TREQ-S-OK _o2tqt-status
    O2TREQ-ATTEMPT-RETRY _o2tqt-attempt @ = _o2tqt-assert
    O2TREQ-PHASE-RETRY-AWAITING _o2tqt-request-phase
    _o2tqt-request O2TREQ-CLAIM-RETRY
        O2TREQ-S-PHASE _o2tqt-status

    ['] _o2tqt-provenance-check
    _o2tqt-request _o2tqt-request O2TREQ-WITH-PROVENANCE
        O2TREQ-S-OK _o2tqt-status
    O2TREQ-ATTEMPT-RETRY _o2tqt-attempt @ = _o2tqt-assert
    _o2tqt-stack ;

: _o2tqt-terminal-payload-zero?  ( -- flag )
    _o2tqt-request _O2TRQ-BINDING-OFF +
    O2TREQ-SIZE _O2TRQ-BINDING-OFF -
    _o2tqt-zero? ;

: _o2tqt-test-terminal-and-abandon  ( -- )
    _o2tqt-request O2TREQ-TERMINAL
        O2TREQ-S-OK _o2tqt-status
    O2TREQ-PHASE-TERMINAL _o2tqt-request-phase
    _o2tqt-terminal-payload-zero? _o2tqt-assert
    _o2tqt-request O2TREQ-CLEAR?
        O2TREQ-S-OK _o2tqt-status

    _o2tqt-code-ready
    _o2tqt-capture O2TREQ-S-OK _o2tqt-status
    _o2tqt-request O2TREQ-ABANDON
        O2TREQ-S-OK _o2tqt-status
    O2TREQ-PHASE-TERMINAL _o2tqt-request-phase
    _o2tqt-terminal-payload-zero? _o2tqt-assert
    _o2tqt-stack ;

: _O2TQT-RUN  ( -- )
    0 _o2tqt-checks !
    0 _o2tqt-fails !
    DEPTH _o2tqt-depth !
    _o2tqt-test-capture-and-alias
    _o2tqt-test-build-and-sole-retry
    _o2tqt-test-terminal-and-abandon
    ." OAUTH2 TOKEN REQUEST CHECKS " _o2tqt-checks @ . CR
    _o2tqt-fails @ IF
        ." OAUTH2 TOKEN REQUEST FAIL " _o2tqt-fails @ . CR
    ELSE
        ." OAUTH2 TOKEN REQUEST PASS" CR
    THEN
    TX-FLUSH ;
