\ Focused public-client AT Protocol PAR vertical qualification.
\ This fixture reuses only the ready-profile/public-config builders and the
\ deterministic cooperative HTTP port from their established test support.

REQUIRE at-oauth-prof-test.f
REQUIRE at-oauth-client-test.f
REQUIRE o2-http-post-common.f

PROVIDED at-oauth-par-test

VARIABLE _atpart-checks
VARIABLE _atpart-fails
VARIABLE _atpart-depth
VARIABLE _atpart-copy-u
VARIABLE _atpart-body-u
VARIABLE _atpart-expected-u
VARIABLE _atpart-state-u
VARIABLE _atpart-challenge-u
VARIABLE _atpart-pump-status
VARIABLE _atpart-pump-steps
VARIABLE _atpart-nonce-a
VARIABLE _atpart-nonce-u

CREATE _atpart-work-storage
    AT-OAUTH-PAR-WORKSPACE-SIZE 7 + ALLOT
CREATE _atpart-o2work-storage
    O2CODE-WORKSPACE-SIZE 7 + ALLOT
CREATE _atpart-transaction-storage
    O2CODE-TRANSACTION-SIZE 7 + ALLOT
CREATE _atpart-wrong-issuer-storage
    O2CODE-TRANSACTION-SIZE 7 + ALLOT
CREATE _atpart-transaction-copy
    O2CODE-TRANSACTION-SIZE ALLOT
CREATE _atpart-config-b-storage
    OAUTH2-CLIENT-CONFIG-SIZE 7 + ALLOT
CREATE _atpart-state
    O2CODE-STATE-SIZE ALLOT
CREATE _atpart-challenge
    O2CODE-CHALLENGE-SIZE ALLOT
CREATE _atpart-body
    _O2HPT-FORM-CAPACITY ALLOT
CREATE _atpart-expected
    _O2HPT-WIRE-CAPACITY ALLOT

: _atpart-work  ( -- workspace )
    _atpart-work-storage 7 + -8 AND ;

: _atpart-o2work  ( -- workspace )
    _atpart-o2work-storage 7 + -8 AND ;

: _atpart-transaction  ( -- transaction )
    _atpart-transaction-storage 7 + -8 AND ;

: _atpart-wrong-issuer  ( -- transaction )
    _atpart-wrong-issuer-storage 7 + -8 AND ;

: _atpart-config-b  ( -- config )
    _atpart-config-b-storage 7 + -8 AND ;

: _atpart-assert  ( flag -- )
    1 _atpart-checks +!
    0= IF
        1 _atpart-fails +!
        ." AT OAUTH PAR ASSERT " _atpart-checks @ . CR
        TX-FLUSH
    THEN ;

: _atpart-status  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH PAR STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _atpart-assert ;

: _atpart-stack  ( -- )
    DEPTH DUP _atpart-depth @ <> IF
        ." AT OAUTH PAR STACK "
        _atpart-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _atpart-depth @ = _atpart-assert ;

: _atpart-byte?  ( address length byte -- flag )
    >R
    BEGIN DUP WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1 /STRING
    REPEAT
    2DROP R> DROP -1 ;

: _atpart-zero?  ( address length -- flag )
    0 _atpart-byte? ;

: _atpart-fill-work  ( -- )
    _atpart-work AT-OAUTH-PAR-WORKSPACE-SIZE 0xA5 FILL ;

: _atpart-work-zero?  ( -- flag )
    _atpart-work AT-OAUTH-PAR-WORKSPACE-SIZE _atpart-zero? ;

: _atpart-work-filled?  ( -- flag )
    _atpart-work AT-OAUTH-PAR-WORKSPACE-SIZE 0xA5
    _atpart-byte? ;

: _atpart-fill-o2work  ( -- )
    _atpart-o2work O2CODE-WORKSPACE-SIZE 0x5A FILL ;

: _atpart-o2work-zero?  ( -- flag )
    _atpart-o2work O2CODE-WORKSPACE-SIZE _atpart-zero? ;

: _atpart-snapshot  ( transaction -- )
    _atpart-transaction-copy O2CODE-TRANSACTION-SIZE MOVE ;

: _atpart-unchanged?  ( transaction -- flag )
    O2CODE-TRANSACTION-SIZE
    _atpart-transaction-copy O2CODE-TRANSACTION-SIZE
    COMPARE 0= ;

: _atpart-phase?  ( transaction expected-phase -- )
    >R
    O2CODE-PHASE@
    O2CODE-S-OK _atpart-status
    R> = _atpart-assert ;

\ =====================================================================
\  Builder and POST setup
\ =====================================================================

: _atpart-config-b-build  ( -- )
    _atoct-input-build
    S" cross-wired-client-binding"
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-U
    _atoct-pair!
    _atpart-config-b OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _atoct-input _atpart-config-b
    OAUTH2-CLIENT-CONFIG-INIT
    OAUTH2-CLIENT-CONFIG-S-OK _atpart-status ;

: _atpart-configure-post-at  ( target -- )
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
    _o2hpt-form _O2HPT-FORM-CAPACITY
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY
    _o2hpt-post OAUTH2-HTTP-POST-CONFIGURE
    OAUTH2-HTTP-POST-S-OK _atpart-status ;

: _atpart-configure-par-post  ( -- )
    _atopt-profile AT-OAUTH-PROFILE-PAR-TARGET@
    AT-OAUTH-PROFILE-S-OK _atpart-status
    _atpart-configure-post-at ;

: _atpart-configure-wrong-post  ( -- )
    S" https://auth.example/not-par"
    _o2hpt-target HTARGET-PARSE
    HTARGET-S-OK _atpart-status
    _o2hpt-target _atpart-configure-post-at ;

: _atpart-wipe-post  ( -- )
    _o2hpt-post OAUTH2-HTTP-POST-WIPE
    OAUTH2-HTTP-POST-S-OK _atpart-status ;

: _atpart-post-configured?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
    OAUTH2-HTTP-POST-STATE-CONFIGURED = ;

: _atpart-correlation-absent?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-CORRELATION@
    IF
        2DROP 0
    ELSE
        2DROP -1
    THEN ;

: _atpart-correlation-is-state?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-CORRELATION@
    IF
        _atpart-state _atpart-state-u @ STR-STR=
    ELSE
        2DROP 0
    THEN ;

\ =====================================================================
\  Guarded transaction inspection and exact wire expectation
\ =====================================================================

: _atpart-capture-state  ( address length -- )
    DUP O2CODE-STATE-SIZE <> IF
        2DROP 0 _atpart-assert EXIT
    THEN
    DUP _atpart-state-u !
    _atpart-state SWAP MOVE ;

: _atpart-capture-challenge  ( address length -- )
    DUP O2CODE-CHALLENGE-SIZE <> IF
        2DROP 0 _atpart-assert EXIT
    THEN
    DUP _atpart-challenge-u !
    _atpart-challenge SWAP MOVE ;

: _atpart-capture-par
  \ ( context binding-a binding-u issuer-a issuer-u issuer-required
  \   state-a state-u challenge-a challenge-u -- callback-status )
    _atpart-capture-challenge
    _atpart-capture-state
    O2CODE-ISSUER-REQUIRED = _atpart-assert
    S" https://auth.example" STR-STR= _atpart-assert
    S" at-oauth-client-binding" STR-STR= _atpart-assert
    9231 = _atpart-assert
    7331 ;

: _atpart-capture-transaction  ( -- )
    ['] _atpart-capture-par
    9231
    _atpart-transaction
    O2CODE-WITH-PAR
    7331 = _atpart-assert ;

: _atpart-body-reset  ( -- )
    _atpart-body _O2HPT-FORM-CAPACITY 0 FILL
    0 _atpart-body-u ! ;

: _atpart-body,  ( address length -- )
    DUP _atpart-copy-u !
    _atpart-body-u @ OVER +
    _O2HPT-FORM-CAPACITY U> IF
        2DROP 0 _atpart-assert EXIT
    THEN
    _atpart-body _atpart-body-u @ + SWAP MOVE
    _atpart-copy-u @ _atpart-body-u +! ;

: _atpart-build-body  ( -- )
    _atpart-body-reset
    S" client_id=https%3A%2F%2Fclient.example%2Foauth%2Fclient-metadata.json&response_type=code&code_challenge="
    _atpart-body,
    _atpart-challenge _atpart-challenge-u @ _atpart-body,
    S" &code_challenge_method=S256&state=" _atpart-body,
    _atpart-state _atpart-state-u @ _atpart-body,
    S" &redirect_uri=https%3A%2F%2Fcallback.example%2Foauth%2Fcallback&scope=atproto"
    _atpart-body,
    _atpart-body-u @ 301 = _atpart-assert ;

: _atpart-expected-reset  ( -- )
    _atpart-expected _O2HPT-WIRE-CAPACITY 0 FILL
    0 _atpart-expected-u ! ;

: _atpart-expected,  ( address length -- )
    DUP _atpart-copy-u !
    _atpart-expected-u @ OVER +
    _O2HPT-WIRE-CAPACITY U> IF
        2DROP 0 _atpart-assert EXIT
    THEN
    _atpart-expected _atpart-expected-u @ + SWAP MOVE
    _atpart-copy-u @ _atpart-expected-u +! ;

: _atpart-expected-crlf,  ( -- )
    13 _atpart-expected _atpart-expected-u @ + C!
    1 _atpart-expected-u +!
    10 _atpart-expected _atpart-expected-u @ + C!
    1 _atpart-expected-u +! ;

: _atpart-expected-line,  ( address length -- )
    _atpart-expected,
    _atpart-expected-crlf, ;

: _atpart-build-expected  ( -- )
    _atpart-build-body
    _atpart-expected-reset
    S" POST /par HTTP/1.1" _atpart-expected-line,
    S" Host: auth.example" _atpart-expected-line,
    S" Accept: application/json" _atpart-expected-line,
    S" Content-Type: application/x-www-form-urlencoded"
    _atpart-expected-line,
    S" DPoP: vertical-dpop-proof" _atpart-expected-line,
    S" Connection: close" _atpart-expected-line,
    S" Content-Length: 301" _atpart-expected-line,
    _atpart-expected-crlf,
    _atpart-body _atpart-body-u @ _atpart-expected, ;

\ =====================================================================
\  Deterministic PAR response exchange
\ =====================================================================

: _atpart-server-quote,  ( -- )
    34 _o2hpt-server _o2hpt-server-u @ + C!
    1 _o2hpt-server-u +! ;

: _atpart-build-server  ( -- )
    _o2hpt-server-reset
    S" HTTP/1.1 201 Created" _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    S" Content-Encoding: identity" _o2hpt-server-line,
    S" DPoP-Nonce: par-nonce-1" _o2hpt-server-line,
    S" Content-Length: 74" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf,
    S" {" _o2hpt-server,
    _atpart-server-quote,
    S" request_uri" _o2hpt-server,
    _atpart-server-quote,
    S" :" _o2hpt-server,
    _atpart-server-quote,
    S" urn:ietf:params:oauth:request_uri:abc123" _o2hpt-server,
    _atpart-server-quote,
    S" ," _o2hpt-server,
    _atpart-server-quote,
    S" expires_in" _o2hpt-server,
    _atpart-server-quote,
    S" :90}" _o2hpt-server, ;

: _atpart-pump  ( -- status )
    0 _atpart-pump-steps !
    _o2hpt-post OAUTH2-HTTP-POST-POLL
    _atpart-pump-status !
    BEGIN
        _atpart-pump-status @ OAUTH2-HTTP-POST-S-PENDING =
    WHILE
        1 _atpart-pump-steps +!
        _atpart-pump-steps @ 128 > IF
            0 _atpart-assert
            OAUTH2-HTTP-POST-S-INTERNAL _atpart-pump-status !
        ELSE
            _o2hpt-post OAUTH2-HTTP-POST-POLL
            _atpart-pump-status !
        THEN
    REPEAT
    _atpart-pump-status @ ;

: _atpart-save-nonce  ( address length -- )
    _atpart-nonce-u !
    _atpart-nonce-a ! ;

: _atpart-returned-nonce-is-borrow?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-NONCE@
    IF
        _atpart-nonce-u @ =
        SWAP _atpart-nonce-a @ = AND
    ELSE
        2DROP 0
    THEN ;

\ =====================================================================
\  Focused staged groups
\ =====================================================================

: _ATPART-INIT  ( -- )
    0 _atpart-checks !
    0 _atpart-fails !
    DEPTH _atpart-depth !

    _ATOCT-INIT
    0 _o2hpt-checks !
    0 _o2hpt-fails !
    DEPTH _o2hpt-depth !
    _atopt-profile-ready
    _atoct-defaults
    _atoct-config-build
    _atpart-config-b-build

    _o2hpt-post OAUTH2-HTTP-POST-SIZE 0 FILL
    _o2hpt-request _O2HPT-REQUEST-CAPACITY 0 FILL
    _o2hpt-form _O2HPT-FORM-CAPACITY 0 FILL
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY 0 FILL

    _atpart-transaction O2CODE-INIT?
    O2CODE-S-OK _atpart-status
    _atpart-fill-work
    _atoct-config
    _atopt-profile
    _atpart-transaction
    _atpart-work
    AT-OAUTH-PAR-PREPARE
    AT-OAUTH-PAR-S-OK _atpart-status
    _atpart-work-zero? _atpart-assert
    _atpart-transaction O2CODE-PHASE-PREPARED
    _atpart-phase?
    _atpart-stack ;

: _ATPART-TEST-REJECTIONS  ( -- )
    \ A DPoP source inside a POST arena is rejected by public geometry.
    _atpart-configure-par-post
    _atpart-transaction _atpart-snapshot
    _atpart-fill-work
    0 0 0 0
    _o2hpt-request 1
    _atoct-config
    _atopt-profile
    _atpart-transaction
    _o2hpt-post
    _atpart-work
    AT-OAUTH-PAR-BUILD
    AT-OAUTH-PAR-S-ALIAS _atpart-status
    _atpart-work-filled? _atpart-assert
    _atpart-post-configured? _atpart-assert
    _atpart-correlation-absent? _atpart-assert
    _atpart-transaction _atpart-unchanged? _atpart-assert
    _atpart-wipe-post

    \ Target policy is checked before POST-BEGIN.
    _atpart-configure-wrong-post
    _atpart-transaction _atpart-snapshot
    _atpart-fill-work
    0 0 0 0
    S" vertical-dpop-proof"
    _atoct-config
    _atopt-profile
    _atpart-transaction
    _o2hpt-post
    _atpart-work
    AT-OAUTH-PAR-BUILD
    AT-OAUTH-PAR-S-TARGET _atpart-status
    _atpart-work-zero? _atpart-assert
    _atpart-post-configured? _atpart-assert
    _atpart-correlation-absent? _atpart-assert
    _atpart-transaction _atpart-unchanged? _atpart-assert
    _atpart-wipe-post

    \ A valid client with a different durable binding cannot cross-wire
    \ this PREPARED transaction and cannot begin the POST.
    _atpart-configure-par-post
    _atpart-transaction _atpart-snapshot
    _atpart-fill-work
    0 0 0 0
    S" vertical-dpop-proof"
    _atpart-config-b
    _atopt-profile
    _atpart-transaction
    _o2hpt-post
    _atpart-work
    AT-OAUTH-PAR-BUILD
    AT-OAUTH-PAR-S-BINDING _atpart-status
    _atpart-work-zero? _atpart-assert
    _atpart-post-configured? _atpart-assert
    _atpart-correlation-absent? _atpart-assert
    _atpart-transaction _atpart-unchanged? _atpart-assert
    _atpart-wipe-post

    \ A separately prepared transaction with the right client binding but
    \ a different issuer is rejected without mutating either owner.
    _atpart-wrong-issuer O2CODE-INIT?
    O2CODE-S-OK _atpart-status
    _atpart-fill-o2work
    _atoct-config OAUTH2-CLIENT-CONFIG-BINDING@
    OAUTH2-CLIENT-CONFIG-S-OK _atpart-status
    S" https://other-auth.example"
    O2CODE-ISSUER-REQUIRED
    _atpart-wrong-issuer
    _atpart-o2work
    O2CODE-PREPARE
    O2CODE-S-OK _atpart-status
    _atpart-o2work-zero? _atpart-assert
    _atpart-wrong-issuer O2CODE-PHASE-PREPARED
    _atpart-phase?

    _atpart-configure-par-post
    _atpart-wrong-issuer _atpart-snapshot
    _atpart-fill-work
    0 0 0 0
    S" vertical-dpop-proof"
    _atoct-config
    _atopt-profile
    _atpart-wrong-issuer
    _o2hpt-post
    _atpart-work
    AT-OAUTH-PAR-BUILD
    AT-OAUTH-PAR-S-BINDING _atpart-status
    _atpart-work-zero? _atpart-assert
    _atpart-post-configured? _atpart-assert
    _atpart-correlation-absent? _atpart-assert
    _atpart-wrong-issuer _atpart-unchanged? _atpart-assert
    _atpart-wipe-post
    _atpart-stack ;

: _ATPART-TEST-BUILD  ( -- )
    _atpart-configure-par-post
    _atpart-transaction _atpart-snapshot
    _atpart-fill-work
    0 0 0 0
    S" vertical-dpop-proof"
    _atoct-config
    _atopt-profile
    _atpart-transaction
    _o2hpt-post
    _atpart-work
    AT-OAUTH-PAR-BUILD
    AT-OAUTH-PAR-S-OK _atpart-status
    _atpart-work-zero? _atpart-assert
    _atpart-transaction _atpart-unchanged? _atpart-assert
    _atpart-transaction O2CODE-PHASE-PREPARED
    _atpart-phase?
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
    OAUTH2-HTTP-POST-STATE-SEALED = _atpart-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-INCLUDED?
    _atpart-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-INCLUDED?
    0= _atpart-assert

    _atpart-capture-transaction
    _atpart-correlation-is-state? _atpart-assert
    _atpart-build-expected
    _atpart-stack ;

: _ATPART-TEST-ACCEPT  ( -- )
    _atpart-build-server
    _o2hpt-transport-reset
    64 _o2hpt-recv-limit !
    _o2hpt-start
    OAUTH2-HTTP-POST-S-PENDING _atpart-status
    _atpart-pump
    OAUTH2-HTTP-POST-S-OK _atpart-status

    _o2hpt-post OAUTH2-HTTP-POST-STATE@
    OAUTH2-HTTP-POST-STATE-RESULT = _atpart-assert
    _o2hpt-post OAUTH2-HTTP-POST-OUTCOME@
    OAUTH2-HTTP-POST-O-SUCCESS = _atpart-assert
    _o2hpt-post OAUTH2-HTTP-POST-DETAIL@
    OAUTH2-HTTP-POST-D-NONE = _atpart-assert
    _o2hpt-post OAUTH2-HTTP-POST-HTTP-STATUS@
    201 = _atpart-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-SENT?
    _atpart-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-SENT?
    0= _atpart-assert
    _atpart-correlation-is-state? _atpart-assert
    _o2hpt-sent _o2hpt-sent-u @
    _atpart-expected _atpart-expected-u @
    STR-STR= _atpart-assert
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
    _atpart-zero? _atpart-assert
    _o2hpt-form _O2HPT-FORM-CAPACITY
    _atpart-zero? _atpart-assert

    _atpart-fill-work
    _o2hpt-post
    100
    _atopt-profile
    _atpart-transaction
    _atpart-work
    AT-OAUTH-PAR-ACCEPT
    AT-OAUTH-PAR-S-OK _atpart-status
    2DUP _atpart-save-nonce
    S" par-nonce-1" STR-STR= _atpart-assert
    _atpart-returned-nonce-is-borrow? _atpart-assert
    _atpart-work-zero? _atpart-assert
    _atpart-transaction O2CODE-PHASE-PAR-READY
    _atpart-phase?
    _atpart-correlation-is-state? _atpart-assert

    _atpart-wipe-post
    _atpart-correlation-absent? _atpart-assert
    _atpart-stack ;

: _ATPART-FINISH  ( -- )
    _atopt-fails @ 0= _atpart-assert
    _atoct-fails @ 0= _atpart-assert
    _o2hpt-fails @ 0= _atpart-assert
    _atpart-stack
    _atpart-fails @ IF
        ." AT OAUTH PAR FAIL checks/fails "
        _atpart-checks @ . _atpart-fails @ . CR
    ELSE
        ." AT OAUTH PAR PASS checks "
        _atpart-checks @ . CR
    THEN
    TX-FLUSH ;
