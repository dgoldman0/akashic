\ Focused public-client AT token exchange vertical.
\
\ The staged runner establishes the already-qualified durable PAR and browser
\ authorization path first.  This fixture continues one CODE_READY grant
\ through a nonce-bound P-256 token POST, one exact use_dpop_nonce response,
\ one fresh retry proof and POST, and one admitted AT token grant.

REQUIRE at-oauth-authz-test.f

PROVIDED at-token-p256-test

1700000100 CONSTANT _ATTT-FIRST-IAT
1700000101 CONSTANT _ATTT-RETRY-IAT
7701 CONSTANT _ATTT-GRANT-CONTEXT
7702 CONSTANT _ATTT-GRANT-RESULT

VARIABLE _attt-checks
VARIABLE _attt-fails
VARIABLE _attt-depth
VARIABLE _attt-callback-count
VARIABLE _attt-saved-grant

CREATE _attt-request-store O2TREQ-SIZE 7 + ALLOT
CREATE _attt-nonce-store OAUTH2-DPOP-NONCE-SIZE 7 + ALLOT
CREATE _attt-token-work-store
    AT-OAUTH-TOKEN-WORKSPACE-SIZE 7 + ALLOT
CREATE _attt-input-store
    AT-OAUTH-TOKEN-P256-INPUT-SIZE 7 + ALLOT
CREATE _attt-p256-work-store
    AT-OAUTH-TOKEN-P256-WORKSPACE-SIZE 7 + ALLOT
CREATE _attt-retry-post-store OAUTH2-HTTP-POST-SIZE 7 + ALLOT
CREATE _attt-retry-request-store
    _O2HPT-REQUEST-CAPACITY 7 + ALLOT
CREATE _attt-retry-form-store
    _O2HPT-FORM-CAPACITY 7 + ALLOT
CREATE _attt-retry-response-store
    _O2HPT-RESPONSE-CAPACITY 7 + ALLOT

VARIABLE _attt-post-a
VARIABLE _attt-request-a
VARIABLE _attt-form-a
VARIABLE _attt-response-a

: _attt-request  ( -- request )
    _attt-request-store 7 + -8 AND ;

: _attt-nonce  ( -- nonce-owner )
    _attt-nonce-store 7 + -8 AND ;

: _attt-token-work  ( -- workspace )
    _attt-token-work-store 7 + -8 AND ;

: _attt-input  ( -- input )
    _attt-input-store 7 + -8 AND ;

: _attt-p256-work  ( -- workspace )
    _attt-p256-work-store 7 + -8 AND ;

: _attt-retry-post  ( -- post )
    _attt-retry-post-store 7 + -8 AND ;

: _attt-retry-request  ( -- address )
    _attt-retry-request-store 7 + -8 AND ;

: _attt-retry-form  ( -- address )
    _attt-retry-form-store 7 + -8 AND ;

: _attt-retry-response  ( -- address )
    _attt-retry-response-store 7 + -8 AND ;

: _attt-post  ( -- post ) _attt-post-a @ ;
: _attt-request-a@  ( -- address ) _attt-request-a @ ;
: _attt-form-a@  ( -- address ) _attt-form-a @ ;
: _attt-response-a@  ( -- address ) _attt-response-a @ ;

: _attt-select-first  ( -- )
    _o2hpt-post _attt-post-a !
    _o2hpt-request _attt-request-a !
    _o2hpt-form _attt-form-a !
    _o2hpt-response _attt-response-a ! ;

: _attt-select-retry  ( -- )
    _attt-retry-post _attt-post-a !
    _attt-retry-request _attt-request-a !
    _attt-retry-form _attt-form-a !
    _attt-retry-response _attt-response-a ! ;

: _attt-assert  ( flag -- )
    1 _attt-checks +!
    0= IF
        1 _attt-fails +!
        ." AT TOKEN P256 ASSERT " _attt-checks @ . CR
        TX-FLUSH
    THEN ;

: _attt-status  ( actual expected -- )
    2DUP <> IF
        ." AT TOKEN P256 STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _attt-assert ;

: _attt-stack  ( -- )
    DEPTH DUP _attt-depth @ <> IF
        ." AT TOKEN P256 STACK "
        _attt-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _attt-depth @ = _attt-assert ;

: _attt-request-phase?  ( expected -- )
    >R
    _attt-request O2TREQ-PHASE@
    O2TREQ-S-OK _attt-status
    R> = _attt-assert ;

: _attt-code-phase?  ( expected -- )
    >R
    _atpart-transaction O2CODE-PHASE@
    O2CODE-S-OK _attt-status
    R> = _attt-assert ;

: _attt-token-work-fill  ( -- )
    _attt-token-work AT-OAUTH-TOKEN-WORKSPACE-SIZE
    0xC3 FILL ;

: _attt-token-work-zero?  ( -- flag )
    _attt-token-work AT-OAUTH-TOKEN-WORKSPACE-SIZE
    _atpart-zero? ;

: _attt-p256-work-fill  ( -- )
    _attt-p256-work AT-OAUTH-TOKEN-P256-WORKSPACE-SIZE
    0xC3 FILL ;

: _attt-p256-work-zero?  ( -- flag )
    _attt-p256-work AT-OAUTH-TOKEN-P256-WORKSPACE-SIZE
    _atpart-zero? ;

: _attt-terminal-payload-zero?  ( -- flag )
    _attt-request _O2TRQ-BINDING-OFF +
    O2TREQ-SIZE _O2TRQ-BINDING-OFF -
    _atpart-zero? ;

: _attt-code-secrets-zero?  ( -- flag )
    _atpart-transaction _O2C.STATE O2CODE-STATE-SIZE
    _atpart-zero?
    _atpart-transaction _O2C.CODE O2CODE-CODE-CAPACITY
    _atpart-zero? AND
    _atpart-transaction _O2C.VERIFIER O2CODE-VERIFIER-SIZE
    _atpart-zero? AND
    _atpart-transaction _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE
    _atpart-zero? AND ;

: _attt-saved-grant-zero?  ( -- flag )
    _attt-saved-grant @
    DUP 0= IF DROP 0 EXIT THEN
    O2SESSION-GRANT-SIZE _atpart-zero? ;

\ =====================================================================
\  Owner setup and public-client input
\ =====================================================================

: _attt-input-build  ( iat -- )
    _attt-input AT-OAUTH-TOKEN-P256-INPUT-CLEAR
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-input AT-OAUTH-TOKEN-P256-I.IAT !
    _O2PKT-VAULT @
        _attt-input AT-OAUTH-TOKEN-P256-I.VAULT !
    _atoct-config
        _attt-input AT-OAUTH-TOKEN-P256-I.CONFIG !
    _atopt-profile
        _attt-input AT-OAUTH-TOKEN-P256-I.PROFILE !
    _attt-request
        _attt-input AT-OAUTH-TOKEN-P256-I.TOKEN-REQUEST !
    _attt-nonce
        _attt-input AT-OAUTH-TOKEN-P256-I.NONCE-OWNER !
    _attt-post
        _attt-input AT-OAUTH-TOKEN-P256-I.POST !
    _attt-request-a@
        _attt-input AT-OAUTH-TOKEN-P256-I.REQUEST-A !
    _O2HPT-REQUEST-CAPACITY
        _attt-input AT-OAUTH-TOKEN-P256-I.REQUEST-CAP !
    _attt-form-a@
        _attt-input AT-OAUTH-TOKEN-P256-I.FORM-A !
    _O2HPT-FORM-CAPACITY
        _attt-input AT-OAUTH-TOKEN-P256-I.FORM-CAP !
    _attt-response-a@
        _attt-input AT-OAUTH-TOKEN-P256-I.RESPONSE-A !
    _O2HPT-RESPONSE-CAPACITY
        _attt-input AT-OAUTH-TOKEN-P256-I.RESPONSE-CAP ! ;

: _attt-sent-has?  ( needle-a needle-u -- flag )
    _o2hpt-sent _o2hpt-sent-u @ 2SWAP
    STR-STR-CONTAINS ;

: _attt-correlation-attempt-at?
  ( expected-attempt post -- flag )
    SWAP >R
    OAUTH2-HTTP-POST-CORRELATION@
    IF
        DUP O2CODE-STATE-SIZE 1+ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        DROP
        DUP O2CODE-STATE-SIZE
        _atpart-state _atpart-state-u @
        STR-STR=
        SWAP O2CODE-STATE-SIZE + C@
        R> = AND
    ELSE
        2DROP R> DROP 0
    THEN ;

: _attt-correlation-attempt?  ( expected-attempt -- flag )
    _attt-post _attt-correlation-attempt-at? ;

: _attt-post-built?  ( expected-attempt -- flag )
    >R
    _attt-post OAUTH2-HTTP-POST-STATE@
    OAUTH2-HTTP-POST-STATE-SEALED =
    _attt-post OAUTH2-HTTP-POST-DPOP-INCLUDED? AND
    _attt-post OAUTH2-HTTP-POST-AUTHORIZATION-INCLUDED?
    0= AND
    R> _attt-correlation-attempt? AND
    _attt-post OAUTH2-HTTP-POST-HTU$
    S" https://auth.example/token" STR-STR= AND ;

: _attt-build-p256  ( iat expected-attempt -- )
    >R
    _attt-input-build
    _attt-p256-work-fill
    _attt-input _attt-p256-work
    AT-OAUTH-TOKEN-P256-BUILD
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-p256-work-zero? _attt-assert
    R> _attt-post-built? _attt-assert ;

\ =====================================================================
\  Deterministic retained HTTP responses
\ =====================================================================

: _attt-build-challenge-body  ( -- )
    _atopt-reset-body
    _atopt-lbrace
    S" error" _atopt-key
    S" use_dpop_nonce" _atopt-string
    _atopt-rbrace
    _atopt-body-u @ 26 = _attt-assert ;

: _attt-build-challenge-server  ( -- )
    _attt-build-challenge-body
    _o2hpt-server-reset
    S" HTTP/1.1 400 Bad Request" _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    S" Content-Encoding: identity" _o2hpt-server-line,
    S" DPoP-Nonce: token-nonce-2" _o2hpt-server-line,
    S" Content-Length: 26" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf,
    _atopt-body _atopt-body-u @ _o2hpt-server, ;

: _attt-build-success-body  ( -- )
    _atopt-reset-body
    _atopt-lbrace
    S" access_token" _atopt-key
    S" access-vertical" _atopt-string
    _atopt-comma
    S" token_type" _atopt-key
    S" dPoP" _atopt-string
    _atopt-comma
    S" scope" _atopt-key
    S" atproto" _atopt-string
    _atopt-comma
    S" sub" _atopt-key
    S" did:plc:abcdefghijklmnopqrstuvwx" _atopt-string
    _atopt-rbrace
    _atopt-body-u @ 113 = _attt-assert ;

: _attt-build-success-server  ( -- )
    _attt-build-success-body
    _o2hpt-server-reset
    S" HTTP/1.1 200 OK" _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    S" Content-Encoding: identity" _o2hpt-server-line,
    S" DPoP-Nonce: token-nonce-3" _o2hpt-server-line,
    S" Content-Length: 113" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf,
    _atopt-body _atopt-body-u @ _o2hpt-server, ;

: _attt-exchange  ( expected-attempt -- )
    >R
    _o2hpt-transport-reset
    64 _o2hpt-recv-limit !
    _o2hpt-port _attt-post OAUTH2-HTTP-POST-START
    OAUTH2-HTTP-POST-S-PENDING _attt-status
    0 _atpart-pump-steps !
    _attt-post OAUTH2-HTTP-POST-POLL
    _atpart-pump-status !
    BEGIN
        _atpart-pump-status @ OAUTH2-HTTP-POST-S-PENDING =
    WHILE
        1 _atpart-pump-steps +!
        _atpart-pump-steps @ 128 > IF
            0 _attt-assert
            OAUTH2-HTTP-POST-S-INTERNAL
            _atpart-pump-status !
        ELSE
            _attt-post OAUTH2-HTTP-POST-POLL
            _atpart-pump-status !
        THEN
    REPEAT
    _atpart-pump-status @
    OAUTH2-HTTP-POST-S-OK _attt-status
    _attt-post OAUTH2-HTTP-POST-STATE@
    OAUTH2-HTTP-POST-STATE-RESULT = _attt-assert
    _attt-post OAUTH2-HTTP-POST-DPOP-SENT?
    _attt-assert
    _attt-post OAUTH2-HTTP-POST-AUTHORIZATION-SENT?
    0= _attt-assert
    R> _attt-correlation-attempt? _attt-assert ;

: _attt-body-is-current?  ( -- flag )
    _attt-post OAUTH2-HTTP-POST-BODY@
    _atopt-body _atopt-body-u @ STR-STR= ;

: _attt-post-nonce?  ( expected-a expected-u -- flag )
    _attt-post OAUTH2-HTTP-POST-NONCE@
    IF
        STR-STR=
    ELSE
        2DROP 2DROP 0
    THEN ;

: _attt-nonce-two
  ( nonce-a nonce-u generation context -- result )
    7202 = _attt-assert
    2 = _attt-assert
    S" token-nonce-2" STR-STR= _attt-assert
    7203 ;

: _attt-nonce-three
  ( nonce-a nonce-u generation context -- result )
    7302 = _attt-assert
    3 = _attt-assert
    S" token-nonce-3" STR-STR= _attt-assert
    7303 ;

: _attt-check-nonce-two  ( -- )
    ['] _attt-nonce-two 7202
    S" https://auth.example"
    _attt-nonce OAUTH2-DPOP-NONCE-WITH
    OAUTH2-DPOP-NONCE-S-OK _attt-status
    7203 = _attt-assert ;

: _attt-check-nonce-three  ( -- )
    ['] _attt-nonce-three 7302
    S" https://auth.example"
    _attt-nonce OAUTH2-DPOP-NONCE-WITH
    OAUTH2-DPOP-NONCE-S-OK _attt-status
    7303 = _attt-assert ;

\ =====================================================================
\  Initial grant callback
\ =====================================================================

: _attt-grant-callback  ( grant context -- callback-result )
    1 _attt-callback-count +!
    _ATTT-GRANT-CONTEXT = _attt-assert
    DUP _attt-saved-grant !
    DUP O2SESSION-G.ACCESS-A @
    OVER O2SESSION-G.ACCESS-U @
    S" access-vertical" 2SWAP COMPARE 0= _attt-assert
    DUP O2SESSION-G.TOKEN-TYPE-A @
    OVER O2SESSION-G.TOKEN-TYPE-U @
    S" dPoP" 2SWAP COMPARE 0= _attt-assert
    DUP O2SESSION-G.SCOPE-A @
    OVER O2SESSION-G.SCOPE-U @
    S" atproto" 2SWAP COMPARE 0= _attt-assert
    DUP O2SESSION-G.REFRESH-A @ 0= _attt-assert
    DUP O2SESSION-G.REFRESH-U @ 0= _attt-assert
    DUP O2SESSION-G.ID-A @ 0= _attt-assert
    DUP O2SESSION-G.ID-U @ 0= _attt-assert
    DUP O2SESSION-G.EXPIRES-AT-MS @ 0= _attt-assert
    O2SESSION-G.FLAGS @
    O2SESSION-GRANT-F-SCOPE = _attt-assert
    _ATTT-GRANT-RESULT ;

\ =====================================================================
\  One public nonce-retry-success vertical
\ =====================================================================

: _ATTT-INIT  ( -- )
    0 _attt-checks !
    0 _attt-fails !
    0 _attt-callback-count !
    0 _attt-saved-grant !
    DEPTH _attt-depth !

    _attt-select-first
    _atpart-wipe-post
    _attt-retry-post OAUTH2-HTTP-POST-SIZE 0 FILL
    _attt-retry-request _O2HPT-REQUEST-CAPACITY 0 FILL
    _attt-retry-form _O2HPT-FORM-CAPACITY 0 FILL
    _attt-retry-response _O2HPT-RESPONSE-CAPACITY 0 FILL
    _attt-request O2TREQ-SIZE 0 FILL
    _attt-request O2TREQ-INIT?
    O2TREQ-S-OK _attt-status
    _attt-nonce OAUTH2-DPOP-NONCE-SIZE 0 FILL
    _attt-token-work AT-OAUTH-TOKEN-WORKSPACE-CLEAR
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-input AT-OAUTH-TOKEN-P256-INPUT-CLEAR
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-p256-work AT-OAUTH-TOKEN-P256-WORKSPACE-CLEAR
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-stack ;

: _ATTT-PREPARE  ( -- )
    S" https%3A%2F%2Fauth.example"
    _ataut-build-query
    _atpart-fill-o2work
    _ataut-query _ataut-query-u @
    _atpart-transaction
    _atpart-o2work
    O2CODE-ACCEPT-CALLBACK
    O2CODE-S-OK _attt-status
    O2CODE-PHASE-CODE-READY _attt-code-phase?

    S" https://auth.example" S" par-nonce-1"
    _attt-nonce OAUTH2-DPOP-NONCE-INIT
    OAUTH2-DPOP-NONCE-S-OK _attt-status
    _attt-nonce OAUTH2-DPOP-NONCE-GENERATION@
    OAUTH2-DPOP-NONCE-S-OK _attt-status
    1 = _attt-assert

    _attt-token-work-fill
    _atoct-config
    _atopt-profile
    _atpart-transaction
    _attt-request
    _attt-token-work
    AT-OAUTH-TOKEN-PREPARE
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-token-work-zero? _attt-assert
    O2TREQ-PHASE-READY _attt-request-phase?
    O2CODE-PHASE-SPENT _attt-code-phase?
    _attt-code-secrets-zero? _attt-assert
    _attt-stack ;

: _ATTT-FIRST-BUILD  ( -- )
    _O2PKD-RESET
    _ATTT-FIRST-IAT O2TREQ-ATTEMPT-FIRST
    _attt-build-p256
    O2TREQ-PHASE-FIRST-AWAITING _attt-request-phase?
    _O2PKD-DPOP-CALLS @ 1 = _attt-assert
    _O2PKD-P256-DERIVE-CALLS @ 1 = _attt-assert
    _O2PKD-JWK-CALLS @ 1 = _attt-assert
    _O2PKD-DPOP-HTM-A @ _O2PKD-DPOP-HTM-U @
    S" POST" STR-STR= _attt-assert
    _O2PKD-DPOP-HTU-A @ _O2PKD-DPOP-HTU-U @
    S" https://auth.example/token" STR-STR= _attt-assert
    _O2PKD-DPOP-IAT @ _ATTT-FIRST-IAT = _attt-assert
    _O2PKD-DPOP-NONCE-A @ _O2PKD-DPOP-NONCE-U @
    S" par-nonce-1" STR-STR= _attt-assert
    _O2PKD-DPOP-TOKEN-A @ 0= _attt-assert
    _O2PKD-DPOP-TOKEN-U @ 0= _attt-assert
    _attt-stack ;

: _ATTT-CHALLENGE  ( -- )
    _attt-build-challenge-server
    O2TREQ-ATTEMPT-FIRST _attt-exchange
    _attt-post OAUTH2-HTTP-POST-OUTCOME@
    OAUTH2-HTTP-POST-O-OAUTH-ERROR = _attt-assert
    _attt-post OAUTH2-HTTP-POST-DETAIL@
    OAUTH2-HTTP-POST-D-NONE = _attt-assert
    _attt-post OAUTH2-HTTP-POST-HTTP-STATUS@
    400 = _attt-assert
    _attt-body-is-current? _attt-assert
    S" token-nonce-2" _attt-post-nonce? _attt-assert
    S" POST /token HTTP/1.1" _attt-sent-has? _attt-assert
    S" DPoP: deterministic-dpop-proof"
    _attt-sent-has? _attt-assert
    S" grant_type=authorization_code"
    _attt-sent-has? _attt-assert
    S" code=authorization-code-1"
    _attt-sent-has? _attt-assert
    S" redirect_uri=https%3A%2F%2Fcallback.example%2Foauth%2Fcallback"
    _attt-sent-has? _attt-assert
    S" client_id=https%3A%2F%2Fclient.example%2Foauth%2Fclient-metadata.json"
    _attt-sent-has? _attt-assert
    S" code_verifier=" _attt-sent-has? _attt-assert

    _attt-token-work-fill
    _atoct-config
    _atopt-profile
    _attt-request
    _attt-post
    _attt-nonce
    _attt-token-work
    AT-OAUTH-TOKEN-ACCEPT-NONCE-CHALLENGE
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-token-work-zero? _attt-assert
    O2TREQ-PHASE-RETRY-READY _attt-request-phase?
    _attt-request _O2TRQ.CODE-U @ 0> _attt-assert
    _attt-body-is-current? _attt-assert
    _attt-check-nonce-two

    _o2hpt-post OAUTH2-HTTP-POST-STATE@
    OAUTH2-HTTP-POST-STATE-RESULT = _attt-assert
    O2TREQ-ATTEMPT-FIRST _o2hpt-post
    _attt-correlation-attempt-at? _attt-assert
    _attt-select-retry
    _attt-retry-post OAUTH2-HTTP-POST-SIZE
    _atpart-zero? _attt-assert
    _attt-retry-request _O2HPT-REQUEST-CAPACITY
    _atpart-zero? _attt-assert
    _attt-retry-form _O2HPT-FORM-CAPACITY
    _atpart-zero? _attt-assert
    _attt-retry-response _O2HPT-RESPONSE-CAPACITY
    _atpart-zero? _attt-assert
    _attt-stack ;

: _ATTT-RETRY-BUILD  ( -- )
    _ATTT-RETRY-IAT O2TREQ-ATTEMPT-RETRY
    _attt-build-p256
    O2TREQ-PHASE-RETRY-AWAITING _attt-request-phase?
    _O2PKD-DPOP-CALLS @ 2 = _attt-assert
    _O2PKD-P256-DERIVE-CALLS @ 2 = _attt-assert
    _O2PKD-JWK-CALLS @ 2 = _attt-assert
    _O2PKD-DPOP-HTU-A @ _O2PKD-DPOP-HTU-U @
    S" https://auth.example/token" STR-STR= _attt-assert
    _O2PKD-DPOP-IAT @ _ATTT-RETRY-IAT = _attt-assert
    _O2PKD-DPOP-NONCE-A @ _O2PKD-DPOP-NONCE-U @
    S" token-nonce-2" STR-STR= _attt-assert
    _attt-stack ;

: _ATTT-SUCCESS  ( -- )
    _attt-build-success-server
    O2TREQ-ATTEMPT-RETRY _attt-exchange
    _attt-post OAUTH2-HTTP-POST-OUTCOME@
    OAUTH2-HTTP-POST-O-SUCCESS = _attt-assert
    _attt-post OAUTH2-HTTP-POST-DETAIL@
    OAUTH2-HTTP-POST-D-NONE = _attt-assert
    _attt-post OAUTH2-HTTP-POST-HTTP-STATUS@
    200 = _attt-assert
    _attt-body-is-current? _attt-assert
    S" token-nonce-3" _attt-post-nonce? _attt-assert

    0 _attt-callback-count !
    0 _attt-saved-grant !
    _attt-token-work-fill
    123000
    _atoct-config
    _atopt-profile
    _attt-request
    _attt-post
    _attt-nonce
    ['] _attt-grant-callback
    _ATTT-GRANT-CONTEXT
    _attt-token-work
    AT-OAUTH-TOKEN-ACCEPT-SUCCESS
    AT-OAUTH-TOKEN-S-OK _attt-status
    _ATTT-GRANT-RESULT = _attt-assert

    _attt-callback-count @ 1 = _attt-assert
    _attt-saved-grant-zero? _attt-assert
    _attt-token-work-zero? _attt-assert
    O2TREQ-PHASE-TERMINAL _attt-request-phase?
    _attt-terminal-payload-zero? _attt-assert
    _attt-code-secrets-zero? _attt-assert
    _attt-check-nonce-three
    _attt-stack ;

: _ATTT-FINISH  ( -- )
    _o2hpt-post OAUTH2-HTTP-POST-WIPE
    OAUTH2-HTTP-POST-S-OK _attt-status
    _attt-retry-post OAUTH2-HTTP-POST-WIPE
    OAUTH2-HTTP-POST-S-OK _attt-status
    _attt-nonce OAUTH2-DPOP-NONCE-WIPE
    OAUTH2-DPOP-NONCE-S-OK _attt-status
    _attt-request O2TREQ-CLEAR?
    O2TREQ-S-OK _attt-status
    O2TREQ-PHASE-EMPTY _attt-request-phase?
    _attt-terminal-payload-zero? _attt-assert
    _attt-input AT-OAUTH-TOKEN-P256-INPUT-CLEAR
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-token-work AT-OAUTH-TOKEN-WORKSPACE-CLEAR
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-p256-work AT-OAUTH-TOKEN-P256-WORKSPACE-CLEAR
    AT-OAUTH-TOKEN-S-OK _attt-status
    _attt-token-work-zero? _attt-assert
    _attt-p256-work-zero? _attt-assert

    _ataut-fails @ 0= _attt-assert
    _atp2t-fails @ 0= _attt-assert
    _atpart-fails @ 0= _attt-assert
    _atoct-fails @ 0= _attt-assert
    _atopt-fails @ 0= _attt-assert
    _O2PKT-FAILS @ 0= _attt-assert
    _attt-stack

    _ATAUT-FINISH
    _ATP2T-FINISH
    _attt-fails @ IF
        ." AT TOKEN P256 FAIL checks/fails "
        _attt-checks @ . _attt-fails @ . CR
    ELSE
        ." AT TOKEN P256 PASS checks "
        _attt-checks @ . CR
    THEN
    TX-FLUSH ;
