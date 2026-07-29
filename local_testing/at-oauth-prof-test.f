\ Focused caller-owned AT Protocol OAuth profile contracts.

PROVIDED at-oauth-prof-test

VARIABLE _atopt-checks
VARIABLE _atopt-fails
VARIABLE _atopt-depth
VARIABLE _atopt-body-u
VARIABLE _atopt-copy-u

VARIABLE _atopt-resource-a
VARIABLE _atopt-resource-u
VARIABLE _atopt-as-origin-a
VARIABLE _atopt-as-origin-u

VARIABLE _atopt-issuer-a
VARIABLE _atopt-issuer-u
VARIABLE _atopt-authorization-a
VARIABLE _atopt-authorization-u
VARIABLE _atopt-token-a
VARIABLE _atopt-token-u
VARIABLE _atopt-par-a
VARIABLE _atopt-par-u
VARIABLE _atopt-par-required
VARIABLE _atopt-request-uri-mode
VARIABLE _atopt-signing-none
VARIABLE _atopt-atproto-scope

8192 CONSTANT _ATOPT-BODY-CAPACITY

CREATE _atopt-id-storage
    ATID-RESULT-SIZE 7 + ALLOT
CREATE _atopt-resolver-storage
    ATID-RESOLVER-SIZE 7 + ALLOT
CREATE _atopt-profile-storage
    AT-OAUTH-PROFILE-SIZE 7 + ALLOT
CREATE _atopt-rmeta-storage
    OAUTH2-RESOURCE-METADATA-SIZE 7 + ALLOT
CREATE _atopt-rwork-storage
    OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE 7 + ALLOT
CREATE _atopt-asmeta-storage
    OAUTH2-METADATA-SIZE 7 + ALLOT
CREATE _atopt-aswork-storage
    OAUTH2-METADATA-WORKSPACE-SIZE 7 + ALLOT
CREATE _atopt-body _ATOPT-BODY-CAPACITY ALLOT

: _atopt-id  ( -- result )
    _atopt-id-storage 7 + -8 AND ;

: _atopt-resolver  ( -- resolver )
    _atopt-resolver-storage 7 + -8 AND ;

: _atopt-profile  ( -- profile )
    _atopt-profile-storage 7 + -8 AND ;

: _atopt-rmeta  ( -- metadata )
    _atopt-rmeta-storage 7 + -8 AND ;

: _atopt-rwork  ( -- workspace )
    _atopt-rwork-storage 7 + -8 AND ;

: _atopt-asmeta  ( -- metadata )
    _atopt-asmeta-storage 7 + -8 AND ;

: _atopt-aswork  ( -- workspace )
    _atopt-aswork-storage 7 + -8 AND ;

: _atopt-assert  ( flag -- )
    1 _atopt-checks +!
    0= IF
        1 _atopt-fails +!
        ." AT OAUTH PROFILE ASSERT " _atopt-checks @ . CR
    THEN ;

: _atopt-status  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH PROFILE STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _atopt-assert ;

: _atopt-stack  ( -- )
    DEPTH DUP _atopt-depth @ <> IF
        ." AT OAUTH PROFILE STACK "
        _atopt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _atopt-depth @ = _atopt-assert ;

: _atopt-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _atopt-reset-body  ( -- )
    _atopt-body _ATOPT-BODY-CAPACITY 0 FILL
    0 _atopt-body-u ! ;

: _atopt-char  ( byte -- )
    _atopt-body-u @ _ATOPT-BODY-CAPACITY >= IF
        DROP 0 _atopt-assert EXIT
    THEN
    _atopt-body _atopt-body-u @ + C!
    1 _atopt-body-u +! ;

: _atopt-text  ( address length -- )
    DUP _atopt-copy-u !
    _atopt-body-u @ OVER +
    _ATOPT-BODY-CAPACITY > IF
        2DROP 0 _atopt-assert EXIT
    THEN
    _atopt-body _atopt-body-u @ + SWAP MOVE
    _atopt-copy-u @ _atopt-body-u +! ;

: _atopt-quote     ( -- ) 34 _atopt-char ;
: _atopt-comma     ( -- ) 44 _atopt-char ;
: _atopt-colon     ( -- ) 58 _atopt-char ;
: _atopt-lbracket  ( -- ) 91 _atopt-char ;
: _atopt-rbracket  ( -- ) 93 _atopt-char ;
: _atopt-lbrace    ( -- ) 123 _atopt-char ;
: _atopt-rbrace    ( -- ) 125 _atopt-char ;

: _atopt-key  ( address length -- )
    _atopt-quote _atopt-text _atopt-quote _atopt-colon ;

: _atopt-string  ( address length -- )
    _atopt-quote _atopt-text _atopt-quote ;

: _atopt-bool  ( flag -- )
    IF S" true" ELSE S" false" THEN _atopt-text ;

: _atopt-qtext  ( address length -- )
    _atopt-string ;

\ =====================================================================
\  Public identity-result fixture
\ =====================================================================

: _atopt-build-did-document  ( -- )
    _atopt-reset-body
    _atopt-lbrace
    S" id" _atopt-key
    S" did:plc:abcdefghijklmnopqrstuvwx" _atopt-qtext
    _atopt-comma
    S" service" _atopt-key
    _atopt-lbracket _atopt-lbrace
    S" id" _atopt-key S" #atproto_pds" _atopt-qtext
    _atopt-comma
    S" type" _atopt-key
    S" AtprotoPersonalDataServer" _atopt-qtext
    _atopt-comma
    S" serviceEndpoint" _atopt-key
    S" https://pds.example" _atopt-qtext
    _atopt-rbrace _atopt-rbracket
    _atopt-rbrace ;

: _atopt-current-identity-target  ( -- target )
    _atopt-resolver ATID-HTTP-TARGET@
    ATID-S-OK = _atopt-assert ;

: _atopt-build-identity  ( -- )
    _atopt-id ATID-RESULT-INIT
        ATID-S-OK _atopt-status
    _atopt-resolver ATID-RESOLVER-CLEAR
        ATID-S-OK _atopt-status
    S" did:plc:abcdefghijklmnopqrstuvwx"
    _atopt-id _atopt-resolver
    ATID-BEGIN-DID ATID-S-OK _atopt-status
    _atopt-build-did-document
    _atopt-body _atopt-body-u @ 200 0
    _atopt-current-identity-target _atopt-resolver
    ATID-HTTP-RESPONSE! ATID-S-OK _atopt-status ;

\ =====================================================================
\  Generic protected-resource metadata fixture
\ =====================================================================

: _atopt-rmeta-defaults  ( -- )
    S" https://pds.example"
        _atopt-resource-u ! _atopt-resource-a !
    S" https://auth.example"
        _atopt-as-origin-u ! _atopt-as-origin-a ! ;

: _atopt-build-rmeta  ( -- )
    _atopt-reset-body
    _atopt-lbrace
    S" resource" _atopt-key
    _atopt-resource-a @ _atopt-resource-u @ _atopt-string
    _atopt-comma
    S" authorization_servers" _atopt-key
    _atopt-lbracket
    _atopt-as-origin-a @ _atopt-as-origin-u @ _atopt-string
    _atopt-rbracket
    _atopt-rbrace ;

: _atopt-build-rmeta-two  ( -- )
    _atopt-reset-body
    _atopt-lbrace
    S" resource" _atopt-key
    _atopt-resource-a @ _atopt-resource-u @ _atopt-string
    _atopt-comma
    S" authorization_servers" _atopt-key
    _atopt-lbracket
    _atopt-as-origin-a @ _atopt-as-origin-u @ _atopt-string
    _atopt-comma
    S" https://second-auth.example" _atopt-string
    _atopt-rbracket
    _atopt-rbrace ;

: _atopt-parse-rmeta  ( -- )
    _atopt-body _atopt-body-u @
    _atopt-rmeta _atopt-rwork
    OAUTH2-RESOURCE-METADATA-PARSE
    OAUTH2-RESOURCE-METADATA-S-OK _atopt-status ;

\ =====================================================================
\  Generic authorization-server metadata fixture
\ =====================================================================

: _atopt-as-defaults  ( -- )
    S" https://auth.example"
        _atopt-issuer-u ! _atopt-issuer-a !
    S" https://auth.example/authorize"
        _atopt-authorization-u ! _atopt-authorization-a !
    S" https://auth.example/token"
        _atopt-token-u ! _atopt-token-a !
    S" https://auth.example/par"
        _atopt-par-u ! _atopt-par-a !
    -1 _atopt-par-required !
    0 _atopt-request-uri-mode !
    0 _atopt-signing-none !
    -1 _atopt-atproto-scope ! ;

: _atopt-json-issuer  ( -- )
    S" issuer" _atopt-key
    _atopt-issuer-a @ _atopt-issuer-u @ _atopt-string ;

: _atopt-json-authorization  ( -- )
    S" authorization_endpoint" _atopt-key
    _atopt-authorization-a @ _atopt-authorization-u @
    _atopt-string ;

: _atopt-json-token  ( -- )
    S" token_endpoint" _atopt-key
    _atopt-token-a @ _atopt-token-u @ _atopt-string ;

: _atopt-json-par  ( -- )
    S" pushed_authorization_request_endpoint" _atopt-key
    _atopt-par-a @ _atopt-par-u @ _atopt-string ;

: _atopt-json-response-code  ( -- )
    S" response_types_supported" _atopt-key
    _atopt-lbracket S" code" _atopt-string _atopt-rbracket ;

: _atopt-json-grants  ( -- )
    S" grant_types_supported" _atopt-key
    _atopt-lbracket
    S" authorization_code" _atopt-string
    _atopt-comma S" refresh_token" _atopt-string
    _atopt-rbracket ;

: _atopt-json-pkce  ( -- )
    S" code_challenge_methods_supported" _atopt-key
    _atopt-lbracket S" S256" _atopt-string _atopt-rbracket ;

: _atopt-json-dpop  ( -- )
    S" dpop_signing_alg_values_supported" _atopt-key
    _atopt-lbracket S" ES256" _atopt-string _atopt-rbracket ;

: _atopt-json-auth-methods  ( -- )
    S" token_endpoint_auth_methods_supported" _atopt-key
    _atopt-lbracket
    S" none" _atopt-string
    _atopt-comma S" private_key_jwt" _atopt-string
    _atopt-rbracket ;

: _atopt-json-scopes  ( -- )
    S" scopes_supported" _atopt-key
    _atopt-lbracket
    _atopt-atproto-scope @ IF
        S" atproto"
    ELSE
        S" openid"
    THEN
    _atopt-string
    _atopt-rbracket ;

: _atopt-json-signing-algs  ( -- )
    S" token_endpoint_auth_signing_alg_values_supported"
    _atopt-key
    _atopt-lbracket
    S" ES256" _atopt-string
    _atopt-signing-none @ IF
        _atopt-comma S" none" _atopt-string
    THEN
    _atopt-rbracket ;

: _atopt-build-asmeta  ( -- )
    _atopt-reset-body
    _atopt-lbrace
    _atopt-json-issuer _atopt-comma
    _atopt-json-authorization _atopt-comma
    _atopt-json-token _atopt-comma
    _atopt-json-par _atopt-comma
    S" require_pushed_authorization_requests" _atopt-key
    _atopt-par-required @ _atopt-bool _atopt-comma
    _atopt-json-response-code _atopt-comma
    _atopt-json-grants _atopt-comma
    _atopt-json-pkce _atopt-comma
    _atopt-json-dpop _atopt-comma
    _atopt-json-auth-methods _atopt-comma
    _atopt-json-scopes _atopt-comma
    _atopt-json-signing-algs _atopt-comma
    S" authorization_response_iss_parameter_supported" _atopt-key
    -1 _atopt-bool
    _atopt-request-uri-mode @ IF
        _atopt-comma
        S" require_request_uri_registration" _atopt-key
        _atopt-request-uri-mode @ 1 = _atopt-bool
    THEN
    _atopt-comma
    S" client_id_metadata_document_supported" _atopt-key
    -1 _atopt-bool
    _atopt-rbrace ;

: _atopt-parse-asmeta  ( -- )
    _atopt-body _atopt-body-u @
    _atopt-asmeta _atopt-aswork
    OAUTH2-METADATA-PARSE
    OAUTH2-METADATA-S-OK _atopt-status ;

\ =====================================================================
\  Profile setup and inspection helpers
\ =====================================================================

: _atopt-profile-begin  ( -- )
    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-id _atopt-profile AT-OAUTH-PROFILE-BEGIN
        AT-OAUTH-PROFILE-S-OK _atopt-status ;

: _atopt-profile-to-as  ( -- )
    _atopt-profile-begin
    _atopt-rmeta-defaults
    _atopt-build-rmeta
    _atopt-parse-rmeta
    _atopt-rmeta _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-OK _atopt-status ;

: _atopt-profile-ready  ( -- )
    _atopt-profile-to-as
    _atopt-as-defaults
    _atopt-build-asmeta
    _atopt-parse-asmeta
    _atopt-asmeta _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-OK _atopt-status ;

: _atopt-phase  ( expected -- )
    >R
    _atopt-profile AT-OAUTH-PROFILE-PHASE@
    AT-OAUTH-PROFILE-S-OK _atopt-status
    R> = _atopt-assert ;

: _atopt-failed-status  ( expected -- )
    >R
    AT-OAUTH-PROFILE-PHASE-FAILED _atopt-phase
    _atopt-profile AT-OAUTH-PROFILE-STATUS@
    R> _atopt-status
    _atopt-profile AT-OAUTH-PROFILE-VALID? _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-READY? 0= _atopt-assert ;

: _atopt-expect-as-profile-failure  ( -- )
    _atopt-build-asmeta
    _atopt-parse-asmeta
    _atopt-asmeta _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-PROFILE _atopt-status
    AT-OAUTH-PROFILE-S-PROFILE _atopt-failed-status ;

\ =====================================================================
\  Contract groups
\ =====================================================================

: _atopt-test-identity  ( -- )
    _atopt-build-identity
    _atopt-id ATID-RESULT-READY? _atopt-assert
    _atopt-id ATID-PARTICIPATION-READY? 0= _atopt-assert
    _atopt-id ATID-PARTICIPATION-STATUS
        ATID-S-KEY _atopt-status
    _atopt-id ATID-PDS-ORIGIN@
        ATID-S-OK _atopt-status
        S" https://pds.example/" 2SWAP
        COMPARE 0= _atopt-assert

    _atopt-profile-begin
    AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA _atopt-phase
    _atopt-profile AT-OAUTH-PROFILE-VALID? _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-READY? 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-DID@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        S" did:plc:abcdefghijklmnopqrstuvwx" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-RESOURCE@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        S" https://pds.example" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-PDS-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://pds.example/" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE-METADATA-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://pds.example/.well-known/oauth-protected-resource"
        2SWAP COMPARE 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-ISSUER@
        AT-OAUTH-PROFILE-S-STATE _atopt-status
        OR 0= _atopt-assert
    _atopt-stack ;

: _atopt-test-exact-binding  ( -- )
    _atopt-profile-to-as
    AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA
        _atopt-phase
    _atopt-profile AT-OAUTH-PROFILE-ISSUER@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        S" https://auth.example" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://auth.example/" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-METADATA-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://auth.example/.well-known/oauth-authorization-server"
        2SWAP COMPARE 0= _atopt-assert

    _atopt-profile-begin
    _atopt-rmeta-defaults
    S" https://pds.example/"
        _atopt-resource-u ! _atopt-resource-a !
    _atopt-build-rmeta _atopt-parse-rmeta
    _atopt-rmeta _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-RESOURCE-BINDING _atopt-status

    _atopt-profile-begin
    _atopt-rmeta-defaults
    S" https://auth.example/"
        _atopt-as-origin-u ! _atopt-as-origin-a !
    _atopt-build-rmeta _atopt-parse-rmeta
    _atopt-rmeta _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-AUTHORIZATION-SERVER _atopt-status

    _atopt-profile-begin
    _atopt-rmeta-defaults
    _atopt-build-rmeta-two _atopt-parse-rmeta
    _atopt-rmeta _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-AUTHORIZATION-SERVER _atopt-status

    _atopt-profile-to-as
    _atopt-as-defaults
    S" https://auth.example/"
        _atopt-issuer-u ! _atopt-issuer-a !
    _atopt-build-asmeta _atopt-parse-asmeta
    _atopt-asmeta _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-ISSUER-BINDING _atopt-status
    _atopt-stack ;

: _atopt-test-happy  ( -- )
    _atopt-profile-ready
    _atopt-profile AT-OAUTH-PROFILE-READY? _atopt-assert
    AT-OAUTH-PROFILE-PHASE-READY _atopt-phase
    _atopt-profile AT-OAUTH-PROFILE-AUTHORIZATION-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://auth.example/authorize" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-TOKEN-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://auth.example/token" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-PAR-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://auth.example/par" 2SWAP
        COMPARE 0= _atopt-assert

    _atopt-profile-to-as
    _atopt-as-defaults
    1 _atopt-request-uri-mode !
    _atopt-build-asmeta _atopt-parse-asmeta
    _atopt-asmeta _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-profile AT-OAUTH-PROFILE-READY? _atopt-assert
    _atopt-stack ;

: _atopt-test-policy  ( -- )
    _atopt-profile-to-as
    _atopt-as-defaults
    0 _atopt-par-required !
    _atopt-expect-as-profile-failure

    _atopt-profile-to-as
    _atopt-as-defaults
    2 _atopt-request-uri-mode !
    _atopt-expect-as-profile-failure

    _atopt-profile-to-as
    _atopt-as-defaults
    -1 _atopt-signing-none !
    _atopt-expect-as-profile-failure

    _atopt-profile-to-as
    _atopt-as-defaults
    0 _atopt-atproto-scope !
    _atopt-expect-as-profile-failure
    _atopt-stack ;

: _atopt-test-endpoints  ( -- )
    _atopt-profile-to-as
    _atopt-as-defaults
    S" https://login.example/authorize"
        _atopt-authorization-u ! _atopt-authorization-a !
    S" https://tokens.example/exchange"
        _atopt-token-u ! _atopt-token-a !
    S" https://par.example/request"
        _atopt-par-u ! _atopt-par-a !
    _atopt-build-asmeta _atopt-parse-asmeta
    _atopt-asmeta _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-profile AT-OAUTH-PROFILE-AUTHORIZATION-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://login.example/authorize" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-TOKEN-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://tokens.example/exchange" 2SWAP
        COMPARE 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-PAR-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://par.example/request" 2SWAP
        COMPARE 0= _atopt-assert

    _atopt-profile-to-as
    _atopt-as-defaults
    S" http://login.example/authorize"
        _atopt-authorization-u ! _atopt-authorization-a !
    _atopt-build-asmeta _atopt-parse-asmeta
    _atopt-asmeta _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-ENDPOINT _atopt-status
    AT-OAUTH-PROFILE-S-ENDPOINT _atopt-failed-status
    _atopt-stack ;

: _atopt-test-terminal  ( -- )
    _atopt-profile-begin
    _atopt-rmeta-defaults
    S" https://other-pds.example"
        _atopt-resource-u ! _atopt-resource-a !
    _atopt-build-rmeta _atopt-parse-rmeta
    _atopt-rmeta _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-RESOURCE-BINDING _atopt-status
    AT-OAUTH-PROFILE-S-RESOURCE-BINDING _atopt-failed-status
    _atopt-profile AT-OAUTH-PROFILE-DID@
        AT-OAUTH-PROFILE-S-RESOURCE-BINDING _atopt-status
        OR 0= _atopt-assert
    _atopt-rmeta _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-STATE _atopt-status

    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    AT-OAUTH-PROFILE-PHASE-EMPTY _atopt-phase
    _atopt-profile AT-OAUTH-PROFILE-DID@
        AT-OAUTH-PROFILE-S-STATE _atopt-status
        OR 0= _atopt-assert
    _atopt-stack ;

: _atopt-test-corruption  ( -- )
    _atopt-profile-begin
    _atopt-profile AT-OAUTH-PROFILE-PDS-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$ DROP
        DUP C@ 1 XOR SWAP C!
    _atopt-profile AT-OAUTH-PROFILE-VALID? 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-DID@
        AT-OAUTH-PROFILE-S-INVALID _atopt-status
        OR 0= _atopt-assert

    _atopt-profile-begin
    _atopt-profile AT-OAUTH-PROFILE-PDS-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        1 SWAP HTARGET.REDIRECT-COUNT !
    _atopt-profile AT-OAUTH-PROFILE-VALID? 0= _atopt-assert

    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-profile AT-OAUTH-PROFILE-VALID? _atopt-assert
    0 _atopt-profile C!
    _atopt-profile AT-OAUTH-PROFILE-VALID? 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-READY? 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-PHASE@
        AT-OAUTH-PROFILE-S-INVALID _atopt-status
        0= _atopt-assert

    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    1 _atopt-profile AT-OAUTH-PROFILE-SIZE 1- + C!
    _atopt-profile AT-OAUTH-PROFILE-VALID? 0= _atopt-assert
    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    AT-OAUTH-PROFILE-S-PLATFORM
        AT-OAUTH-PROFILE-STATUS-VALID? _atopt-assert
    AT-OAUTH-PROFILE-S-PLATFORM 1+
        AT-OAUTH-PROFILE-STATUS-VALID? 0= _atopt-assert
    AT-OAUTH-PROFILE-PHASE-FAILED
        AT-OAUTH-PROFILE-PHASE-VALID? _atopt-assert
    AT-OAUTH-PROFILE-PHASE-FAILED 1+
        AT-OAUTH-PROFILE-PHASE-VALID? 0= _atopt-assert
    _atopt-stack ;

: _atopt-test-ownership  ( -- )
    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-profile _atopt-profile
    AT-OAUTH-PROFILE-BEGIN
        AT-OAUTH-PROFILE-S-ALIAS _atopt-status
    AT-OAUTH-PROFILE-PHASE-EMPTY _atopt-phase

    _atopt-id _atopt-profile
    AT-OAUTH-PROFILE-BEGIN
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-id ATID-RESULT-INIT
        ATID-S-OK _atopt-status
    _atopt-profile AT-OAUTH-PROFILE-DID@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        S" did:plc:abcdefghijklmnopqrstuvwx" 2SWAP
        COMPARE 0= _atopt-assert

    _atopt-rmeta-defaults
    _atopt-build-rmeta _atopt-parse-rmeta
    _atopt-rmeta 1+ _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-INVALID _atopt-status
    AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA _atopt-phase
    _atopt-profile _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-ALIAS _atopt-status
    AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA _atopt-phase
    _atopt-rmeta _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE!
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-rmeta OAUTH2-RESOURCE-METADATA-SIZE 0 FILL
    _atopt-profile AT-OAUTH-PROFILE-ISSUER@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        S" https://auth.example" 2SWAP
        COMPARE 0= _atopt-assert

    _atopt-as-defaults
    _atopt-build-asmeta _atopt-parse-asmeta
    _atopt-asmeta 1+ _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-INVALID _atopt-status
    AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA
        _atopt-phase
    _atopt-profile _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-ALIAS _atopt-status
    AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA
        _atopt-phase
    _atopt-asmeta _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-asmeta OAUTH2-METADATA-SIZE 0 FILL
    _atopt-profile AT-OAUTH-PROFILE-TOKEN-TARGET@
        AT-OAUTH-PROFILE-S-OK _atopt-status
        HTARGET-URI$
        S" https://auth.example/token" 2SWAP
        COMPARE 0= _atopt-assert

    _atopt-profile AT-OAUTH-PROFILE-WIPE
        AT-OAUTH-PROFILE-S-OK _atopt-status
    _atopt-profile AT-OAUTH-PROFILE-SIZE
        _atopt-zero? _atopt-assert
    _atopt-stack ;

: _ATOPT-INIT  ( -- )
    0 _atopt-checks !
    0 _atopt-fails !
    DEPTH _atopt-depth ! ;

: _ATOPT-FINISH  ( -- )
    _atopt-stack
    _atopt-fails @ IF
        ." AT OAUTH PROFILE FAIL checks/fails "
        _atopt-checks @ . _atopt-fails @ . CR
    ELSE
        ." AT OAUTH PROFILE PASS " _atopt-checks @ . CR
    THEN ;
