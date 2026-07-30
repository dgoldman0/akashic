\ Focused durable-P256 AT Protocol PAR composition qualification.
\
\ The runner loads the exact raw AT PAR closure, exact credential vault,
\ exact P-256 key owner, and exact AT/PAR wrapper.  Its deterministic
\ P-256/JWK/DPoP subordinate seams keep this test about composition.

REQUIRE at-oauth-par-test.f
REQUIRE oauth2-p256-key-test.f

PROVIDED at-par-p256-test

1700000000 CONSTANT _ATP2T-IAT

VARIABLE _atp2t-checks
VARIABLE _atp2t-fails
VARIABLE _atp2t-depth
VARIABLE _atp2t-generation
VARIABLE _atp2t-resolver-before

CREATE _atp2t-input-storage
    AT-OAUTH-PAR-P256-INPUT-SIZE 7 + ALLOT
CREATE _atp2t-input-copy
    AT-OAUTH-PAR-P256-INPUT-SIZE ALLOT
CREATE _atp2t-work-storage
    AT-OAUTH-PAR-P256-WORKSPACE-SIZE 23 + ALLOT

: _atp2t-input  ( -- input )
    _atp2t-input-storage 7 + -8 AND ;

: _atp2t-work  ( -- workspace )
    _atp2t-work-storage 7 + -8 AND ;

: _atp2t-canary  ( -- address )
    _atp2t-work AT-OAUTH-PAR-P256-WORKSPACE-SIZE + ;

: _atp2t-assert  ( flag -- )
    1 _atp2t-checks +!
    0= IF
        1 _atp2t-fails +!
        ." AT PAR P256 ASSERT " _atp2t-checks @ . CR
        TX-FLUSH
    THEN ;

: _atp2t-status  ( actual expected -- )
    2DUP <> IF
        ." AT PAR P256 STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _atp2t-assert ;

: _atp2t-stack  ( -- )
    DEPTH DUP _atp2t-depth @ <> IF
        ." AT PAR P256 STACK "
        _atp2t-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _atp2t-depth @ = _atp2t-assert ;

: _atp2t-work-fill  ( -- )
    _atp2t-work AT-OAUTH-PAR-P256-WORKSPACE-SIZE
        0xC3 FILL
    _atp2t-canary 16 0xA5 FILL ;

: _atp2t-work-zero?  ( -- flag )
    _atp2t-work AT-OAUTH-PAR-P256-WORKSPACE-SIZE
        _atpart-zero?
    _atp2t-canary 16 0xA5 _atpart-byte?
    AND ;

: _atp2t-work-contains?
  ( address length -- flag )
    >R
    DUP _atp2t-work U< 0=
    SWAP R> +
    _atp2t-work AT-OAUTH-PAR-P256-WORKSPACE-SIZE +
        U> 0=
    AND ;

: _atp2t-input-snapshot  ( -- )
    _atp2t-input _atp2t-input-copy
    AT-OAUTH-PAR-P256-INPUT-SIZE MOVE ;

: _atp2t-input-unchanged?  ( -- flag )
    _atp2t-input AT-OAUTH-PAR-P256-INPUT-SIZE
    _atp2t-input-copy AT-OAUTH-PAR-P256-INPUT-SIZE
    COMPARE 0= ;

\ =====================================================================
\  Durable binding, client config, and prepared transaction
\ =====================================================================

: _atp2t-provision-dpop  ( -- )
    _O2PKT-WORK-RESET
    _O2PKT-RID _O2PKT-VAULT @
    _O2PKT-DPOP-SLOT _O2PKT-WORK @
    OAUTH2-P256-KEY-PROVISION-DPOP
    DUP OAUTH2-P256-KEY-S-OK _atp2t-status
    DROP
    DUP 1 = _atp2t-assert
    _atp2t-generation !
    _O2PKT-WORK-CLEAN? _atp2t-assert
    _O2PKD-P256-KEYGEN-CALLS @ 1 = _atp2t-assert ;

: _atp2t-config-build  ( -- )
    _atoct-defaults
    _atoct-input-build
    _O2PKT-BINDING OAUTH2-P256-KEY-BINDING-SIZE
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-U
    _atoct-pair!
    _atoct-config OAUTH2-CLIENT-CONFIG-WIPE
    OAUTH2-CLIENT-CONFIG-S-OK _atp2t-status
    _atoct-input _atoct-config
    OAUTH2-CLIENT-CONFIG-INIT
    OAUTH2-CLIENT-CONFIG-S-OK _atp2t-status
    _atoct-config OAUTH2-CLIENT-CONFIG-BINDING@
    OAUTH2-CLIENT-CONFIG-S-OK _atp2t-status
    _O2PKT-BINDING OAUTH2-P256-KEY-BINDING-SIZE
    STR-STR= _atp2t-assert ;

: _atp2t-prepare  ( -- )
    _atpart-transaction O2CODE-CLEAR?
    O2CODE-S-OK _atp2t-status
    _atpart-fill-work
    _atoct-config
    _atopt-profile
    _atpart-transaction
    _atpart-work
    AT-OAUTH-PAR-PREPARE
    AT-OAUTH-PAR-S-OK _atp2t-status
    _atpart-work-zero? _atp2t-assert
    _atpart-transaction O2CODE-PHASE-PREPARED
    _atpart-phase? ;

: _atp2t-capture-par
  \ ( context binding-a binding-u issuer-a issuer-u issuer-required
  \   state-a state-u challenge-a challenge-u -- callback-status )
    _atpart-capture-challenge
    _atpart-capture-state
    O2CODE-ISSUER-REQUIRED = _atp2t-assert
    S" https://auth.example" STR-STR= _atp2t-assert
    _atoct-config OAUTH2-CLIENT-CONFIG-BINDING@
    OAUTH2-CLIENT-CONFIG-S-OK _atp2t-status
    STR-STR= _atp2t-assert
    9231 = _atp2t-assert
    7331 ;

: _atp2t-capture-transaction  ( -- )
    ['] _atp2t-capture-par
    9231
    _atpart-transaction
    O2CODE-WITH-PAR
    7331 = _atp2t-assert ;

\ =====================================================================
\  Wrapper input, arenas, and exact proof-bearing request
\ =====================================================================

: _atp2t-arenas-fill  ( byte -- )
    >R
    _o2hpt-post OAUTH2-HTTP-POST-SIZE 0 FILL
    _o2hpt-request _O2HPT-REQUEST-CAPACITY R@ FILL
    _o2hpt-form _O2HPT-FORM-CAPACITY R@ FILL
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY R> FILL ;

: _atp2t-arenas-byte?  ( byte -- flag )
    >R
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
    R@ _atpart-byte?
    _o2hpt-form _O2HPT-FORM-CAPACITY
    R@ _atpart-byte? AND
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY
    R> _atpart-byte? AND ;

: _atp2t-post-zero?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-SIZE
    _atpart-zero? ;

: _atp2t-input-build  ( -- )
    _atp2t-input AT-OAUTH-PAR-P256-INPUT-CLEAR
    AT-OAUTH-PAR-S-OK _atp2t-status
    0
        _atp2t-input AT-OAUTH-PAR-P256-I.LOGIN-A !
    0
        _atp2t-input AT-OAUTH-PAR-P256-I.LOGIN-U !
    0
        _atp2t-input AT-OAUTH-PAR-P256-I.NONCE-A !
    0
        _atp2t-input AT-OAUTH-PAR-P256-I.NONCE-U !
    _ATP2T-IAT
        _atp2t-input AT-OAUTH-PAR-P256-I.IAT !
    _O2PKT-VAULT @
        _atp2t-input AT-OAUTH-PAR-P256-I.VAULT !
    _atoct-config
        _atp2t-input AT-OAUTH-PAR-P256-I.CONFIG !
    _atopt-profile
        _atp2t-input AT-OAUTH-PAR-P256-I.PROFILE !
    _atpart-transaction
        _atp2t-input AT-OAUTH-PAR-P256-I.TRANSACTION !
    _o2hpt-post
        _atp2t-input AT-OAUTH-PAR-P256-I.POST !
    _o2hpt-request
        _atp2t-input AT-OAUTH-PAR-P256-I.REQUEST-A !
    _O2HPT-REQUEST-CAPACITY
        _atp2t-input AT-OAUTH-PAR-P256-I.REQUEST-CAP !
    _o2hpt-form
        _atp2t-input AT-OAUTH-PAR-P256-I.FORM-A !
    _O2HPT-FORM-CAPACITY
        _atp2t-input AT-OAUTH-PAR-P256-I.FORM-CAP !
    _o2hpt-response
        _atp2t-input AT-OAUTH-PAR-P256-I.RESPONSE-A !
    _O2HPT-RESPONSE-CAPACITY
        _atp2t-input AT-OAUTH-PAR-P256-I.RESPONSE-CAP ! ;

: _atp2t-build-expected  ( -- )
    _atpart-build-body
    _atpart-expected-reset
    S" POST /par HTTP/1.1" _atpart-expected-line,
    S" Host: auth.example" _atpart-expected-line,
    S" Accept: application/json" _atpart-expected-line,
    S" Content-Type: application/x-www-form-urlencoded"
    _atpart-expected-line,
    S" DPoP: deterministic-dpop-proof"
    _atpart-expected-line,
    S" Connection: close" _atpart-expected-line,
    S" Content-Length: 301" _atpart-expected-line,
    _atpart-expected-crlf,
    _atpart-body _atpart-body-u @ _atpart-expected, ;

\ =====================================================================
\  One gating rejection and one public proof-bearing vertical
\ =====================================================================

: _ATP2T-INIT  ( -- )
    0 _atp2t-checks !
    0 _atp2t-fails !
    DEPTH _atp2t-depth !

    _ATOCT-INIT
    0 _o2hpt-checks !
    0 _o2hpt-fails !
    DEPTH _o2hpt-depth !
    0 _atpart-checks !
    0 _atpart-fails !
    DEPTH _atpart-depth !
    _atopt-profile-ready

    _o2hpt-post OAUTH2-HTTP-POST-SIZE 0 FILL
    _o2hpt-request _O2HPT-REQUEST-CAPACITY 0 FILL
    _o2hpt-form _O2HPT-FORM-CAPACITY 0 FILL
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY 0 FILL
    _atpart-transaction O2CODE-INIT?
    O2CODE-S-OK _atp2t-status

    _O2PKT-INIT
    _atp2t-provision-dpop
    _atp2t-input AT-OAUTH-PAR-P256-INPUT-CLEAR
    AT-OAUTH-PAR-S-OK _atp2t-status
    _atp2t-work AT-OAUTH-PAR-P256-WORKSPACE-CLEAR
    AT-OAUTH-PAR-S-OK _atp2t-status
    _atp2t-stack ;

: _ATP2T-TEST-REJECTION  ( -- )
    OAUTH2-P256-KEY-ROLE-CLIENT 0x71 0x72
    _O2PKT-CLIENT-SLOT _O2PKT-MAKE-SLOT
    _O2PKT-CLIENT-SLOT _O2PKT-BIND-CLIENT
    _atp2t-config-build
    _atp2t-prepare
    _atpart-transaction _atpart-snapshot

    0xA6 _atp2t-arenas-fill
    _atp2t-input-build
    _atp2t-input-snapshot
    _O2PKD-RESET
    _O2PKT-RESOLVER-CALLS @ _atp2t-resolver-before !
    _atp2t-work-fill
    _atp2t-input _atp2t-work
    AT-OAUTH-PAR-P256-BUILD
    AT-OAUTH-PAR-S-BINDING _atp2t-status

    _atp2t-work-zero? _atp2t-assert
    _atp2t-input-unchanged? _atp2t-assert
    _atp2t-post-zero? _atp2t-assert
    0xA6 _atp2t-arenas-byte? _atp2t-assert
    _atpart-transaction _atpart-unchanged? _atp2t-assert
    _atpart-transaction O2CODE-PHASE-PREPARED
    _atpart-phase?
    _O2PKD-DPOP-CALLS @ 0= _atp2t-assert
    _O2PKT-RESOLVER-CALLS @
    _atp2t-resolver-before @ = _atp2t-assert
    _atp2t-stack ;

: _ATP2T-TEST-HAPPY  ( -- )
    _O2PKT-DPOP-SLOT _O2PKT-BIND-DPOP
    _atp2t-config-build
    _atp2t-prepare
    _atp2t-capture-transaction
    _atp2t-build-expected
    _atpart-transaction _atpart-snapshot

    0 _atp2t-arenas-fill
    _atp2t-input-build
    _atp2t-input-snapshot
    _O2PKD-RESET
    _atp2t-work-fill
    _atp2t-input _atp2t-work
    AT-OAUTH-PAR-P256-BUILD
    AT-OAUTH-PAR-S-OK _atp2t-status

    _atp2t-work-zero? _atp2t-assert
    _atp2t-input-unchanged? _atp2t-assert
    _atpart-transaction _atpart-unchanged? _atp2t-assert
    _atpart-transaction O2CODE-PHASE-PREPARED
    _atpart-phase?
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
    OAUTH2-HTTP-POST-STATE-SEALED = _atp2t-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-INCLUDED?
    _atp2t-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-INCLUDED?
    0= _atp2t-assert
    _atpart-correlation-is-state? _atp2t-assert
    _o2hpt-post OAUTH2-HTTP-POST-HTU$
    S" https://auth.example/par"
    STR-STR= _atp2t-assert

    _O2PKD-DPOP-CALLS @ 1 = _atp2t-assert
    _O2PKD-DPOP-PRIVATE-OK @ _atp2t-assert
    _O2PKD-P256-DERIVE-CALLS @ 1 = _atp2t-assert
    _O2PKD-JWK-CALLS @ 1 = _atp2t-assert
    _O2PKD-DPOP-HTM-A @ _O2PKD-DPOP-HTM-U @
    S" POST" STR-STR= _atp2t-assert
    _O2PKD-DPOP-HTU-A @ _O2PKD-DPOP-HTU-U @
    S" https://auth.example/par"
    STR-STR= _atp2t-assert
    _O2PKD-DPOP-IAT @ _ATP2T-IAT = _atp2t-assert
    _O2PKD-DPOP-NONCE-A @ 0= _atp2t-assert
    _O2PKD-DPOP-NONCE-U @ 0= _atp2t-assert
    _O2PKD-DPOP-TOKEN-A @ 0= _atp2t-assert
    _O2PKD-DPOP-TOKEN-U @ 0= _atp2t-assert
    _O2PKD-DPOP-DESTINATION @
    _O2PKD-DPOP-CAPACITY @
    _atp2t-work-contains? _atp2t-assert
    _O2PKD-DPOP-WORK @
    OAUTH2-DPOP-ES256-WORKSPACE-SIZE
    _atp2t-work-contains? _atp2t-assert
    _O2PKD-DPOP-DESTINATION @
    _O2PKD-DPOP-CAPACITY @
    _atpart-zero? _atp2t-assert
    _O2PKD-DPOP-WORK @
    OAUTH2-DPOP-ES256-WORKSPACE-SIZE
    _atpart-zero? _atp2t-assert

    _ATPART-TEST-ACCEPT
    _atpart-transaction O2CODE-PHASE-PAR-READY
    _atpart-phase?
    _atp2t-work-zero? _atp2t-assert
    _O2PKT-DPOP-OWNER-CLEAN? _atp2t-assert
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
    _atpart-zero? _atp2t-assert
    _o2hpt-form _O2HPT-FORM-CAPACITY
    _atpart-zero? _atp2t-assert
    _atp2t-stack ;

: _ATP2T-FINISH  ( -- )
    _atp2t-input AT-OAUTH-PAR-P256-INPUT-CLEAR
    AT-OAUTH-PAR-S-OK _atp2t-status
    _atp2t-work AT-OAUTH-PAR-P256-WORKSPACE-CLEAR
    AT-OAUTH-PAR-S-OK _atp2t-status
    _atp2t-work-zero? _atp2t-assert
    _atopt-fails @ 0= _atp2t-assert
    _atoct-fails @ 0= _atp2t-assert
    _o2hpt-fails @ 0= _atp2t-assert
    _atpart-fails @ 0= _atp2t-assert
    _O2PKT-FINISH
    _O2PKT-FAILS @ 0= _atp2t-assert
    _atp2t-stack
    _atp2t-fails @ IF
        ." AT PAR P256 FAIL checks/fails "
        _atp2t-checks @ . _atp2t-fails @ . CR
    ELSE
        ." AT PAR P256 PASS checks "
        _atp2t-checks @ . CR
    THEN
    TX-FLUSH ;
