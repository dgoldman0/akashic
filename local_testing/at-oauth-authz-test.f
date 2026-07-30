\ Focused durable public-client continuation from PAR_READY through the
\ browser authorization URI, strict issuer callback, and grant loan.

REQUIRE at-par-p256-test.f

PROVIDED at-oauth-authorization-test

VARIABLE _ataut-checks
VARIABLE _ataut-fails
VARIABLE _ataut-depth
VARIABLE _ataut-output-u
VARIABLE _ataut-query-u
VARIABLE _ataut-copy-u

CREATE _ataut-work-storage
    AT-OAUTH-AUTHORIZATION-WORKSPACE-SIZE 7 + ALLOT
CREATE _ataut-output
    AT-OAUTH-AUTHORIZATION-URL-CAPACITY 16 + ALLOT
CREATE _ataut-query 512 ALLOT
CREATE _ataut-query-copy 512 ALLOT
CREATE _ataut-transaction-copy O2CODE-TRANSACTION-SIZE ALLOT

: _ataut-work  ( -- workspace )
    _ataut-work-storage 7 + -8 AND ;

: _ataut-canary  ( -- address )
    _ataut-output AT-OAUTH-AUTHORIZATION-URL-CAPACITY + ;

: _ataut-assert  ( flag -- )
    1 _ataut-checks +!
    0= IF
        1 _ataut-fails +!
        ." AT OAUTH AUTHORIZATION ASSERT "
        _ataut-checks @ . CR
        TX-FLUSH
    THEN ;

: _ataut-status  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH AUTHORIZATION STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _ataut-assert ;

: _ataut-stack  ( -- )
    DEPTH DUP _ataut-depth @ <> IF
        ." AT OAUTH AUTHORIZATION STACK "
        _ataut-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _ataut-depth @ = _ataut-assert ;

: _ataut-work-fill  ( -- )
    _ataut-work AT-OAUTH-AUTHORIZATION-WORKSPACE-SIZE
    0xC3 FILL ;

: _ataut-work-zero?  ( -- flag )
    _ataut-work AT-OAUTH-AUTHORIZATION-WORKSPACE-SIZE
    _atpart-zero? ;

: _ataut-output-reset  ( -- )
    _ataut-output AT-OAUTH-AUTHORIZATION-URL-CAPACITY
    0xA5 FILL
    _ataut-canary 16 0x5A FILL
    0 _ataut-output-u ! ;

: _ataut-canary-clean?  ( -- flag )
    _ataut-canary 16 0x5A _atpart-byte? ;

: _ataut-output-tail-zero?  ( -- flag )
    _ataut-output _ataut-output-u @ +
    AT-OAUTH-AUTHORIZATION-URL-CAPACITY
    _ataut-output-u @ -
    _atpart-zero? ;

: _ataut-transaction-snapshot  ( -- )
    _atpart-transaction _ataut-transaction-copy
    O2CODE-TRANSACTION-SIZE MOVE ;

: _ataut-transaction-unchanged?  ( -- flag )
    _atpart-transaction O2CODE-TRANSACTION-SIZE
    _ataut-transaction-copy O2CODE-TRANSACTION-SIZE
    COMPARE 0= ;

: _ataut-query-reset  ( -- )
    _ataut-query 512 0 FILL
    0 _ataut-query-u ! ;

: _ataut-query,  ( address length -- )
    DUP _ataut-copy-u !
    _ataut-query-u @ OVER + 512 U> IF
        2DROP 0 _ataut-assert EXIT
    THEN
    _ataut-query _ataut-query-u @ + SWAP MOVE
    _ataut-copy-u @ _ataut-query-u +! ;

: _ataut-query-snapshot  ( -- )
    _ataut-query _ataut-query-copy 512 MOVE ;

: _ataut-query-unchanged?  ( -- flag )
    _ataut-query 512 _ataut-query-copy 512
    COMPARE 0= ;

: _ataut-build-query  ( issuer-a issuer-u -- )
    _ataut-query-reset
    S" code=authorization-code-1&state=" _ataut-query,
    _atpart-state _atpart-state-u @ _ataut-query,
    S" &iss=" _ataut-query,
    _ataut-query, ;

: _ataut-phase?  ( expected -- )
    >R
    _atpart-transaction O2CODE-PHASE@
    O2CODE-S-OK _ataut-status
    R> = _ataut-assert ;

: _ATAUT-INIT  ( -- )
    0 _ataut-checks !
    0 _ataut-fails !
    DEPTH _ataut-depth !
    _ataut-work AT-OAUTH-AUTHORIZATION-WORKSPACE-CLEAR
    AT-OAUTH-AUTHORIZATION-S-OK _ataut-status
    _ataut-output-reset
    _ataut-stack ;

: _ATAUT-TEST-LAUNCH  ( -- )
    O2CODE-PHASE-PAR-READY _ataut-phase?
    _ataut-output-reset
    _ataut-work-fill
    _atoct-config
    _atopt-profile
    100
    _atpart-transaction
    _ataut-output
    AT-OAUTH-AUTHORIZATION-URL-CAPACITY
    _ataut-work
    AT-OAUTH-AUTHORIZATION-LAUNCH
    AT-OAUTH-AUTHORIZATION-S-OK _ataut-status
    DUP _ataut-output-u !
    DROP

    _ataut-output _ataut-output-u @
    S" https://auth.example/authorize?client_id=https%3A%2F%2Fclient.example%2Foauth%2Fclient-metadata.json&request_uri=urn%3Aietf%3Aparams%3Aoauth%3Arequest_uri%3Aabc123"
    COMPARE 0= _ataut-assert
    _ataut-work-zero? _ataut-assert
    _ataut-output-tail-zero? _ataut-assert
    _ataut-canary-clean? _ataut-assert
    O2CODE-PHASE-AWAITING _ataut-phase?
    _atpart-transaction _O2C.REQUEST-URI
    O2CODE-REQUEST-URI-CAPACITY _atpart-zero?
    _ataut-assert
    _atpart-transaction _O2C.REQUEST-URI-U @ 0=
    _ataut-assert
    _ataut-stack ;

: _ATAUT-TEST-ISSUER-REJECTION  ( -- )
    S" https%3A%2F%2Fother-auth.example"
    _ataut-build-query
    _ataut-query-snapshot
    _ataut-transaction-snapshot
    _atpart-fill-o2work
    _ataut-query _ataut-query-u @
    _atpart-transaction
    _atpart-o2work
    O2CODE-ACCEPT-CALLBACK
    O2CODE-S-ISSUER _ataut-status

    _atpart-o2work-zero? _ataut-assert
    _ataut-query-unchanged? _ataut-assert
    _ataut-transaction-unchanged? _ataut-assert
    O2CODE-PHASE-AWAITING _ataut-phase?
    _ataut-stack ;

: _ataut-grant-callback
  \ ( context binding binding-u code code-u verifier verifier-u
  \   -- callback-status )
    DUP O2CODE-VERIFIER-SIZE = >R
    2DUP OAUTH2-PKCE-VERIFIER-VALID?
    R> AND
    _ataut-assert
    2DROP
    S" authorization-code-1" STR-STR= _ataut-assert
    _O2PKT-BINDING OAUTH2-P256-KEY-BINDING-SIZE
    STR-STR= _ataut-assert
    8401 = _ataut-assert
    _atpart-transaction O2CODE-PHASE@
    O2CODE-S-OK _ataut-status
    O2CODE-PHASE-SPENT = _ataut-assert
    8402 ;

: _ATAUT-TEST-CALLBACK-GRANT  ( -- )
    S" https%3A%2F%2Fauth.example"
    _ataut-build-query
    _atpart-fill-o2work
    _ataut-query _ataut-query-u @
    _atpart-transaction
    _atpart-o2work
    O2CODE-ACCEPT-CALLBACK
    O2CODE-S-OK _ataut-status
    _atpart-o2work-zero? _ataut-assert
    O2CODE-PHASE-CODE-READY _ataut-phase?

    ['] _ataut-grant-callback
    8401
    _atpart-transaction
    O2CODE-WITH-GRANT
    8402 = _ataut-assert
    O2CODE-PHASE-SPENT _ataut-phase?
    _atpart-transaction _O2C.STATE O2CODE-STATE-SIZE
    _atpart-zero? _ataut-assert
    _atpart-transaction _O2C.VERIFIER O2CODE-VERIFIER-SIZE
    _atpart-zero? _ataut-assert
    _atpart-transaction _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE
    _atpart-zero? _ataut-assert
    _atpart-transaction _O2C.CODE O2CODE-CODE-CAPACITY
    _atpart-zero? _ataut-assert
    _ataut-stack ;

: _ATAUT-FINISH  ( -- )
    _ataut-work AT-OAUTH-AUTHORIZATION-WORKSPACE-CLEAR
    AT-OAUTH-AUTHORIZATION-S-OK _ataut-status
    _ataut-work-zero? _ataut-assert
    _ataut-canary-clean? _ataut-assert
    _ataut-stack
    _ataut-fails @ IF
        ." AT OAUTH AUTHORIZATION FAIL checks/fails "
        _ataut-checks @ . _ataut-fails @ . CR
    ELSE
        ." AT OAUTH AUTHORIZATION PASS checks "
        _ataut-checks @ . CR
    THEN
    TX-FLUSH ;
