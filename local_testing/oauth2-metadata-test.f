\ Focused strict OAuth 2 authorization-server metadata contracts.

PROVIDED akashic-o2md-contracts

VARIABLE _o2mdt-checks
VARIABLE _o2mdt-fails
VARIABLE _o2mdt-depth
VARIABLE _o2mdt-input-u
VARIABLE _o2mdt-copy-u

CREATE _o2mdt-input    4096 ALLOT
CREATE _o2mdt-result   OAUTH2-METADATA-SIZE ALLOT
CREATE _o2mdt-work     OAUTH2-METADATA-WORKSPACE-SIZE ALLOT

: _o2mdt-assert  ( flag -- )
    1 _o2mdt-checks +!
    0= IF
        1 _o2mdt-fails +!
        ." OAUTH2 METADATA ASSERT " _o2mdt-checks @ . CR
    THEN ;

: _o2mdt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 METADATA STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _o2mdt-assert ;

: _o2mdt-stack  ( -- )
    DEPTH _o2mdt-depth @ = _o2mdt-assert ;

: _o2mdt-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _o2mdt-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _o2mdt-work-zero?  ( -- flag )
    _o2mdt-work OAUTH2-METADATA-WORKSPACE-SIZE _o2mdt-zero? ;

: _o2mdt-result-unchanged?  ( -- flag )
    _o2mdt-result OAUTH2-METADATA-SIZE 0xA5 _o2mdt-filled? ;

: _o2mdt-preflight-fill  ( -- )
    _o2mdt-result OAUTH2-METADATA-SIZE 0xA5 FILL
    _o2mdt-work OAUTH2-METADATA-WORKSPACE-SIZE 0xC3 FILL ;

: _o2mdt-reset  ( -- ) 0 _o2mdt-input-u ! ;

: _o2mdt-char  ( byte -- )
    _o2mdt-input _o2mdt-input-u @ + C!
    1 _o2mdt-input-u +! ;

: _o2mdt-text  ( address length -- )
    DUP _o2mdt-copy-u !
    _o2mdt-input _o2mdt-input-u @ + SWAP MOVE
    _o2mdt-copy-u @ _o2mdt-input-u +! ;

: _o2mdt-quote    ( -- ) 34 _o2mdt-char ;
: _o2mdt-comma    ( -- ) 44 _o2mdt-char ;
: _o2mdt-colon    ( -- ) 58 _o2mdt-char ;
: _o2mdt-lbracket ( -- ) 91 _o2mdt-char ;
: _o2mdt-rbracket ( -- ) 93 _o2mdt-char ;
: _o2mdt-lbrace   ( -- ) 123 _o2mdt-char ;
: _o2mdt-rbrace   ( -- ) 125 _o2mdt-char ;

: _o2mdt-key  ( address length -- )
    _o2mdt-quote _o2mdt-text _o2mdt-quote _o2mdt-colon ;

: _o2mdt-string  ( address length -- )
    _o2mdt-quote _o2mdt-text _o2mdt-quote ;

: _o2mdt-issuer  ( -- )
    S" issuer" _o2mdt-key
    S" https://auth.example" _o2mdt-string ;

: _o2mdt-authorization  ( -- )
    S" authorization_endpoint" _o2mdt-key
    S" https://auth.example/authorize" _o2mdt-string ;

: _o2mdt-token  ( -- )
    S" token_endpoint" _o2mdt-key
    S" https://auth.example/token" _o2mdt-string ;

: _o2mdt-par  ( -- )
    S" pushed_authorization_request_endpoint" _o2mdt-key
    S" https://auth.example/par" _o2mdt-string ;

: _o2mdt-response-code  ( -- )
    S" response_types_supported" _o2mdt-key
    _o2mdt-lbracket
    S" token" _o2mdt-string _o2mdt-comma
    S" code" _o2mdt-string
    _o2mdt-rbracket ;

: _o2mdt-grants  ( -- )
    S" grant_types_supported" _o2mdt-key
    _o2mdt-lbracket
    S" authorization_code" _o2mdt-string _o2mdt-comma
    S" refresh_token" _o2mdt-string
    _o2mdt-rbracket ;

: _o2mdt-pkce  ( -- )
    S" code_challenge_methods_supported" _o2mdt-key
    _o2mdt-lbracket S" S256" _o2mdt-string _o2mdt-rbracket ;

: _o2mdt-dpop  ( -- )
    S" dpop_signing_alg_values_supported" _o2mdt-key
    _o2mdt-lbracket S" ES256" _o2mdt-string _o2mdt-rbracket ;

: _o2mdt-auth-methods  ( -- )
    S" token_endpoint_auth_methods_supported" _o2mdt-key
    _o2mdt-lbracket
    S" none" _o2mdt-string _o2mdt-comma
    S" private_key_jwt" _o2mdt-string _o2mdt-comma
    S" client_secret_basic" _o2mdt-string
    _o2mdt-rbracket ;

: _o2mdt-scopes  ( -- )
    S" scopes_supported" _o2mdt-key
    _o2mdt-lbracket
    S" openid" _o2mdt-string _o2mdt-comma
    S" atproto" _o2mdt-string
    _o2mdt-rbracket ;

: _o2mdt-token-auth-signing-algs  ( -- )
    S" token_endpoint_auth_signing_alg_values_supported" _o2mdt-key
    _o2mdt-lbracket
    S" RS256" _o2mdt-string _o2mdt-comma
    S" ES256" _o2mdt-string
    _o2mdt-rbracket ;

: _o2mdt-build-full  ( -- )
    _o2mdt-reset _o2mdt-lbrace
    _o2mdt-issuer _o2mdt-comma
    _o2mdt-authorization _o2mdt-comma
    _o2mdt-token _o2mdt-comma
    _o2mdt-par _o2mdt-comma
    S" require_pushed_authorization_requests" _o2mdt-key
        S" true" _o2mdt-text _o2mdt-comma
    _o2mdt-response-code _o2mdt-comma
    _o2mdt-grants _o2mdt-comma
    _o2mdt-pkce _o2mdt-comma
    _o2mdt-dpop _o2mdt-comma
    _o2mdt-auth-methods _o2mdt-comma
    _o2mdt-scopes _o2mdt-comma
    _o2mdt-token-auth-signing-algs _o2mdt-comma
    S" authorization_response_iss_parameter_supported" _o2mdt-key
        S" true" _o2mdt-text _o2mdt-comma
    S" require_request_uri_registration" _o2mdt-key
        S" true" _o2mdt-text _o2mdt-comma
    S" client_id_metadata_document_supported" _o2mdt-key
        S" true" _o2mdt-text _o2mdt-comma
    S" extension" _o2mdt-key
    _o2mdt-lbrace
        S" nested" _o2mdt-key
        _o2mdt-lbracket S" true" _o2mdt-text
            _o2mdt-comma S" null" _o2mdt-text _o2mdt-rbracket
    _o2mdt-rbrace
    _o2mdt-rbrace ;

: _o2mdt-build-issuer-only  ( -- )
    _o2mdt-reset _o2mdt-lbrace _o2mdt-issuer _o2mdt-rbrace ;

: _o2mdt-build-clear-capabilities  ( -- )
    _o2mdt-reset _o2mdt-lbrace
    _o2mdt-issuer _o2mdt-comma
    S" require_pushed_authorization_requests" _o2mdt-key
        S" false" _o2mdt-text _o2mdt-comma
    S" response_types_supported" _o2mdt-key
        _o2mdt-lbracket S" token" _o2mdt-string
        _o2mdt-rbracket _o2mdt-comma
    S" grant_types_supported" _o2mdt-key
        _o2mdt-lbracket S" client_credentials" _o2mdt-string
        _o2mdt-rbracket _o2mdt-comma
    S" code_challenge_methods_supported" _o2mdt-key
        _o2mdt-lbracket S" plain" _o2mdt-string
        _o2mdt-rbracket _o2mdt-comma
    S" dpop_signing_alg_values_supported" _o2mdt-key
        _o2mdt-lbracket S" EdDSA" _o2mdt-string
        _o2mdt-rbracket _o2mdt-comma
    S" token_endpoint_auth_methods_supported" _o2mdt-key
        _o2mdt-lbracket S" client_secret_basic" _o2mdt-string
        _o2mdt-rbracket _o2mdt-comma
    S" scopes_supported" _o2mdt-key
        _o2mdt-lbracket S" openid" _o2mdt-string
        _o2mdt-rbracket _o2mdt-comma
    S" token_endpoint_auth_signing_alg_values_supported" _o2mdt-key
        _o2mdt-lbracket S" EdDSA" _o2mdt-string
        _o2mdt-rbracket _o2mdt-comma
    S" authorization_response_iss_parameter_supported" _o2mdt-key
        S" false" _o2mdt-text _o2mdt-comma
    S" require_request_uri_registration" _o2mdt-key
        S" false" _o2mdt-text _o2mdt-comma
    S" client_id_metadata_document_supported" _o2mdt-key
        S" false" _o2mdt-text
    _o2mdt-rbrace ;

: _o2mdt-parse  ( -- status )
    _o2mdt-input _o2mdt-input-u @
    _o2mdt-result _o2mdt-work
    OAUTH2-METADATA-PARSE ;

: _o2mdt-expect-failure  ( expected-status -- )
    >R
    _o2mdt-result OAUTH2-METADATA-SIZE 0xA5 FILL
    _o2mdt-work OAUTH2-METADATA-WORKSPACE-SIZE 0xC3 FILL
    _o2mdt-parse R> _o2mdt-status
    _o2mdt-result-unchanged? _o2mdt-assert
    _o2mdt-work-zero? _o2mdt-assert ;

: _o2mdt-test-full  ( -- )
    _o2mdt-build-full
    _o2mdt-preflight-fill
    _o2mdt-parse OAUTH2-METADATA-S-OK _o2mdt-status
    _o2mdt-result OAUTH2-METADATA-VALID? _o2mdt-assert

    _o2mdt-result OAUTH2-METADATA-PRESENCE@
        OAUTH2-METADATA-S-OK _o2mdt-status
        OAUTH2-METADATA-P-ALL = _o2mdt-assert
    _o2mdt-result OAUTH2-METADATA-FLAGS@
        OAUTH2-METADATA-S-OK _o2mdt-status
        OAUTH2-METADATA-F-ALL = _o2mdt-assert

    _o2mdt-result OAUTH2-METADATA-ISSUER@
        OAUTH2-METADATA-S-OK _o2mdt-status
        S" https://auth.example" 2SWAP COMPARE 0= _o2mdt-assert
    _o2mdt-result OAUTH2-METADATA-TOKEN-ENDPOINT@
        OAUTH2-METADATA-S-OK _o2mdt-status
        S" https://auth.example/token" 2SWAP
        COMPARE 0= _o2mdt-assert

    _o2mdt-result OAUTH2-METADATA-TOKEN-AUTH-COUNT@
        OAUTH2-METADATA-S-OK _o2mdt-status
        3 = _o2mdt-assert
    0 _o2mdt-result OAUTH2-METADATA-TOKEN-AUTH@
        OAUTH2-METADATA-S-OK _o2mdt-status
        S" none" 2SWAP COMPARE 0= _o2mdt-assert
    S" client_secret_basic" _o2mdt-result
        OAUTH2-METADATA-TOKEN-AUTH-METHOD?
        OAUTH2-METADATA-S-OK _o2mdt-status
        _o2mdt-assert
    S" absent" _o2mdt-result
        OAUTH2-METADATA-TOKEN-AUTH-METHOD?
        OAUTH2-METADATA-S-OK _o2mdt-status
        0= _o2mdt-assert
    _o2mdt-result OAUTH2-METADATA-SCOPE-COUNT@
        OAUTH2-METADATA-S-OK _o2mdt-status
        2 = _o2mdt-assert
    1 _o2mdt-result OAUTH2-METADATA-SCOPE@
        OAUTH2-METADATA-S-OK _o2mdt-status
        S" atproto" 2SWAP COMPARE 0= _o2mdt-assert
    S" atproto" _o2mdt-result OAUTH2-METADATA-SCOPE?
        OAUTH2-METADATA-S-OK _o2mdt-status
        _o2mdt-assert
    _o2mdt-result OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG-COUNT@
        OAUTH2-METADATA-S-OK _o2mdt-status
        2 = _o2mdt-assert
    1 _o2mdt-result OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG@
        OAUTH2-METADATA-S-OK _o2mdt-status
        S" ES256" 2SWAP COMPARE 0= _o2mdt-assert
    S" ES256" _o2mdt-result
        OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG?
        OAUTH2-METADATA-S-OK _o2mdt-status
        _o2mdt-assert
    _o2mdt-work-zero? _o2mdt-assert
    _o2mdt-stack ;

: _o2mdt-test-optional  ( -- )
    _o2mdt-build-issuer-only
    _o2mdt-preflight-fill
    _o2mdt-parse OAUTH2-METADATA-S-OK _o2mdt-status
    _o2mdt-result OAUTH2-METADATA-PRESENCE@
        OAUTH2-METADATA-S-OK _o2mdt-status
        OAUTH2-METADATA-P-ISSUER = _o2mdt-assert
    _o2mdt-result OAUTH2-METADATA-FLAGS@
        OAUTH2-METADATA-S-OK _o2mdt-status
        0= _o2mdt-assert
    _o2mdt-result OAUTH2-METADATA-TOKEN-ENDPOINT@
        OAUTH2-METADATA-S-MISSING _o2mdt-status
        OR 0= _o2mdt-assert
    S" none" _o2mdt-result
        OAUTH2-METADATA-TOKEN-AUTH-METHOD?
        OAUTH2-METADATA-S-MISSING _o2mdt-status
        0= _o2mdt-assert
    S" atproto" _o2mdt-result OAUTH2-METADATA-SCOPE?
        OAUTH2-METADATA-S-MISSING _o2mdt-status
        0= _o2mdt-assert
    S" ES256" _o2mdt-result
        OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG?
        OAUTH2-METADATA-S-MISSING _o2mdt-status
        0= _o2mdt-assert
    _o2mdt-work-zero? _o2mdt-assert

    _o2mdt-build-clear-capabilities
    _o2mdt-preflight-fill
    _o2mdt-parse OAUTH2-METADATA-S-OK _o2mdt-status
    _o2mdt-result OAUTH2-METADATA-FLAGS@
        OAUTH2-METADATA-S-OK _o2mdt-status
        0= _o2mdt-assert
    _o2mdt-work-zero? _o2mdt-assert
    _o2mdt-stack ;

: _o2mdt-test-rejections  ( -- )
    _o2mdt-reset _o2mdt-lbrace
    S" token_endpoint" _o2mdt-key S" x" _o2mdt-string
    _o2mdt-rbrace
    OAUTH2-METADATA-S-MISSING _o2mdt-expect-failure

    _o2mdt-reset _o2mdt-lbrace
    S" issuer" _o2mdt-key S" true" _o2mdt-text
    _o2mdt-rbrace
    OAUTH2-METADATA-S-TYPE _o2mdt-expect-failure

    _o2mdt-reset _o2mdt-lbrace
    _o2mdt-issuer _o2mdt-comma
    S" token_endpoint" _o2mdt-key S" null" _o2mdt-text
    _o2mdt-rbrace
    OAUTH2-METADATA-S-TYPE _o2mdt-expect-failure

    _o2mdt-reset _o2mdt-lbrace
    _o2mdt-issuer _o2mdt-comma
    S" response_types_supported" _o2mdt-key
    _o2mdt-lbracket S" code" _o2mdt-string
        _o2mdt-comma S" true" _o2mdt-text _o2mdt-rbracket
    _o2mdt-rbrace
    OAUTH2-METADATA-S-TYPE _o2mdt-expect-failure

    _o2mdt-reset _o2mdt-lbrace
    _o2mdt-issuer _o2mdt-comma
    S" response_types_supported" _o2mdt-key
    _o2mdt-lbracket S" code" _o2mdt-string
        _o2mdt-comma S" code" _o2mdt-string _o2mdt-rbracket
    _o2mdt-rbrace
    OAUTH2-METADATA-S-DUPLICATE _o2mdt-expect-failure

    _o2mdt-reset _o2mdt-lbrace
    _o2mdt-issuer _o2mdt-comma _o2mdt-issuer _o2mdt-rbrace
    OAUTH2-METADATA-S-DUPLICATE _o2mdt-expect-failure

    _o2mdt-reset _o2mdt-lbrace
    _o2mdt-issuer _o2mdt-comma
    S" authorization_response_iss_parameter_supported" _o2mdt-key
        S" 1" _o2mdt-text
    _o2mdt-rbrace
    OAUTH2-METADATA-S-TYPE _o2mdt-expect-failure

    _o2mdt-reset _o2mdt-lbrace
    OAUTH2-METADATA-S-JSON _o2mdt-expect-failure
    _o2mdt-stack ;

: _o2mdt-test-corruption  ( -- )
    _o2mdt-build-issuer-only
    _o2mdt-preflight-fill
    _o2mdt-parse OAUTH2-METADATA-S-OK _o2mdt-status
    OAUTH2-METADATA-F-RESPONSE-CODE
        _o2mdt-result _O2MD.FLAGS !
    _o2mdt-result OAUTH2-METADATA-VALID? 0= _o2mdt-assert
    _o2mdt-stack ;

: _o2mdt-test-preflight  ( -- )
    _o2mdt-build-issuer-only
    _o2mdt-preflight-fill
    _o2mdt-input _o2mdt-input-u @
    _o2mdt-work _o2mdt-work
    OAUTH2-METADATA-PARSE
        OAUTH2-METADATA-S-ALIAS _o2mdt-status
    _o2mdt-work OAUTH2-METADATA-WORKSPACE-SIZE
        0xC3 _o2mdt-filled? _o2mdt-assert
    _o2mdt-result-unchanged? _o2mdt-assert
    _o2mdt-stack ;

: _O2MDT-RUN  ( -- )
    0 _o2mdt-checks !
    0 _o2mdt-fails !
    DEPTH _o2mdt-depth !
    _o2mdt-test-full
    _o2mdt-test-optional
    _o2mdt-test-rejections
    _o2mdt-test-corruption
    _o2mdt-test-preflight
    _o2mdt-fails @ IF
        ." OAUTH2 METADATA FAIL checks/fails "
        _o2mdt-checks @ . _o2mdt-fails @ . CR
    ELSE
        ." OAUTH2 METADATA PASS " _o2mdt-checks @ . CR
    THEN ;
