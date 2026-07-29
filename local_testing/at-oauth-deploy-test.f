\ Focused contracts for AT OAuth client deployment binding.
\ The guest filename stays within the MP64FS component limit.

PROVIDED at-oauth-deploy-test

VARIABLE _atodt-checks
VARIABLE _atodt-fails
VARIABLE _atodt-depth
VARIABLE _atodt-expected-status
VARIABLE _atodt-expected-result
VARIABLE _atodt-document-u
VARIABLE _atodt-copy-u
VARIABLE _atodt-callback-count
VARIABLE _atodt-saved-metadata-view
VARIABLE _atodt-inline-jwks-a
VARIABLE _atodt-inline-jwks-u

VARIABLE _atodt-config-client-a
VARIABLE _atodt-config-client-u
VARIABLE _atodt-config-redirect-a
VARIABLE _atodt-config-redirect-u
VARIABLE _atodt-config-scope-a
VARIABLE _atodt-config-scope-u
VARIABLE _atodt-config-method-a
VARIABLE _atodt-config-method-u
VARIABLE _atodt-config-algorithm-a
VARIABLE _atodt-config-algorithm-u
VARIABLE _atodt-config-flags

VARIABLE _atodt-metadata-client-a
VARIABLE _atodt-metadata-client-u
VARIABLE _atodt-application-mode
VARIABLE _atodt-grant-mode
VARIABLE _atodt-response-mode
VARIABLE _atodt-redirect-mode
VARIABLE _atodt-metadata-redirect-a
VARIABLE _atodt-metadata-redirect-u
VARIABLE _atodt-metadata-redirect2-a
VARIABLE _atodt-metadata-redirect2-u
VARIABLE _atodt-metadata-scope-a
VARIABLE _atodt-metadata-scope-u
VARIABLE _atodt-scope-present
VARIABLE _atodt-metadata-method-a
VARIABLE _atodt-metadata-method-u
VARIABLE _atodt-method-present
VARIABLE _atodt-metadata-algorithm-a
VARIABLE _atodt-metadata-algorithm-u
VARIABLE _atodt-algorithm-present
VARIABLE _atodt-dpop-mode
VARIABLE _atodt-key-mode

OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES 8 +
CONSTANT _ATODT-DOCUMENT-SIZE

CREATE _atodt-input-storage
    OAUTH2-CLIENT-CONFIG-INPUT-SIZE 15 + ALLOT
CREATE _atodt-config-storage
    OAUTH2-CLIENT-CONFIG-SIZE 15 + ALLOT
CREATE _atodt-config-copy-storage
    OAUTH2-CLIENT-CONFIG-SIZE 15 + ALLOT
CREATE _atodt-profile-copy-storage
    AT-OAUTH-PROFILE-SIZE 15 + ALLOT
CREATE _atodt-work-storage
    AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE 15 + ALLOT
CREATE _atodt-document _ATODT-DOCUMENT-SIZE ALLOT
CREATE _atodt-document-copy _ATODT-DOCUMENT-SIZE ALLOT

: _atodt-input  ( -- input )
    _atodt-input-storage 7 + -8 AND ;

: _atodt-config  ( -- config )
    _atodt-config-storage 7 + -8 AND ;

: _atodt-config-copy  ( -- config )
    _atodt-config-copy-storage 7 + -8 AND ;

: _atodt-profile-copy  ( -- profile )
    _atodt-profile-copy-storage 7 + -8 AND ;

: _atodt-work  ( -- workspace )
    _atodt-work-storage 7 + -8 AND ;

0x41544F4443545854 CONSTANT _ATODT-CONTEXT
0x41544F4452455354 CONSTANT _ATODT-RESULT
0x41544F445354414B CONSTANT _ATODT-STACK-SENTINEL

: _atodt-assert  ( flag -- )
    1 _atodt-checks +!
    0= IF
        1 _atodt-fails +!
        ." AT OAUTH DEPLOYMENT ASSERT " _atodt-checks @ . CR
        TX-FLUSH
    THEN ;

: _atodt-status  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH DEPLOYMENT STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _atodt-assert ;

: _atodt-stack  ( -- )
    DEPTH DUP _atodt-depth @ <> IF
        ." AT OAUTH DEPLOYMENT STACK "
        _atodt-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _atodt-depth @ = _atodt-assert ;

: _atodt-byte?  ( address length byte -- flag )
    >R
    BEGIN DUP WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _atodt-zero?  ( address length -- flag )
    0 _atodt-byte? ;

: _atodt-pair!
  ( source-address source-length address-field length-field -- )
    >R
    OVER R@ !
    NIP !
    R> DROP ;

: _atodt-config-client!  ( address length -- )
    _atodt-config-client-u ! _atodt-config-client-a ! ;

: _atodt-config-redirect!  ( address length -- )
    _atodt-config-redirect-u ! _atodt-config-redirect-a ! ;

: _atodt-config-scope!  ( address length -- )
    _atodt-config-scope-u ! _atodt-config-scope-a ! ;

: _atodt-config-method!  ( address length -- )
    _atodt-config-method-u ! _atodt-config-method-a ! ;

: _atodt-config-algorithm!  ( address length -- )
    _atodt-config-algorithm-u ! _atodt-config-algorithm-a ! ;

: _atodt-no-config-algorithm  ( -- )
    0 _atodt-config-algorithm-a !
    0 _atodt-config-algorithm-u ! ;

: _atodt-metadata-client!  ( address length -- )
    _atodt-metadata-client-u ! _atodt-metadata-client-a ! ;

: _atodt-metadata-redirect!  ( address length -- )
    _atodt-metadata-redirect-u !
    _atodt-metadata-redirect-a ! ;

: _atodt-metadata-redirect2!  ( address length -- )
    _atodt-metadata-redirect2-u !
    _atodt-metadata-redirect2-a ! ;

: _atodt-no-metadata-redirect2  ( -- )
    0 _atodt-metadata-redirect2-a !
    0 _atodt-metadata-redirect2-u ! ;

: _atodt-metadata-scope!  ( address length -- )
    _atodt-metadata-scope-u ! _atodt-metadata-scope-a ! ;

: _atodt-metadata-method!  ( address length -- )
    _atodt-metadata-method-u ! _atodt-metadata-method-a ! ;

: _atodt-metadata-algorithm!  ( address length -- )
    _atodt-metadata-algorithm-u !
    _atodt-metadata-algorithm-a ! ;

\ =====================================================================
\  Local immutable-config builder
\ =====================================================================

: _atodt-input-build  ( -- )
    _atodt-input OAUTH2-CLIENT-CONFIG-INPUT-CLEAR
        OAUTH2-CLIENT-CONFIG-S-OK _atodt-status

    S" at-oauth-deployment-binding"
    _atodt-input OAUTH2-CLIENT-CONFIG-I.BINDING-A
    _atodt-input OAUTH2-CLIENT-CONFIG-I.BINDING-U
        _atodt-pair!

    _atodt-config-client-a @ _atodt-config-client-u @
    _atodt-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A
    _atodt-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U
        _atodt-pair!

    _atodt-config-redirect-a @ _atodt-config-redirect-u @
    _atodt-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-A
    _atodt-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-U
        _atodt-pair!

    _atodt-config-scope-a @ _atodt-config-scope-u @
    _atodt-input OAUTH2-CLIENT-CONFIG-I.SCOPE-A
    _atodt-input OAUTH2-CLIENT-CONFIG-I.SCOPE-U
        _atodt-pair!

    _atodt-config-method-a @ _atodt-config-method-u @
    _atodt-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-A
    _atodt-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-U
        _atodt-pair!

    _atodt-config-algorithm-a @
    _atodt-config-algorithm-u @
    _atodt-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-A
    _atodt-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-U
        _atodt-pair!

    _atodt-config-flags @
    _atodt-input OAUTH2-CLIENT-CONFIG-I.FLAGS ! ;

: _atodt-config-build  ( -- )
    _atodt-config OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-OK _atodt-status
    _atodt-input-build
    _atodt-input _atodt-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-OK _atodt-status ;

\ =====================================================================
\  Local Client ID Metadata Document builder
\ =====================================================================

: _atodt-document-reset  ( -- )
    0 _atodt-document-u ! ;

: _atodt-document-char  ( byte -- )
    _atodt-document-u @ _ATODT-DOCUMENT-SIZE >= IF
        DROP 0 _atodt-assert EXIT
    THEN
    _atodt-document _atodt-document-u @ + C!
    1 _atodt-document-u +! ;

: _atodt-document-text  ( address length -- )
    DUP _atodt-copy-u !
    _atodt-document-u @ OVER +
    _ATODT-DOCUMENT-SIZE > IF
        2DROP 0 _atodt-assert EXIT
    THEN
    _atodt-document _atodt-document-u @ + SWAP MOVE
    _atodt-copy-u @ _atodt-document-u +! ;

: _atodt-quote     ( -- ) 34 _atodt-document-char ;
: _atodt-comma     ( -- ) 44 _atodt-document-char ;
: _atodt-colon     ( -- ) 58 _atodt-document-char ;
: _atodt-lbrace    ( -- ) 123 _atodt-document-char ;
: _atodt-rbrace    ( -- ) 125 _atodt-document-char ;
: _atodt-lbracket  ( -- ) 91 _atodt-document-char ;
: _atodt-rbracket  ( -- ) 93 _atodt-document-char ;

: _atodt-key  ( address length -- )
    _atodt-quote _atodt-document-text
    _atodt-quote _atodt-colon ;

: _atodt-string  ( address length -- )
    _atodt-quote _atodt-document-text _atodt-quote ;

: _atodt-member-string
  ( key-a key-u value-a value-u -- )
    >R >R
    _atodt-key
    R> R> _atodt-string ;

: _atodt-member-raw
  ( key-a key-u value-a value-u -- )
    >R >R
    _atodt-key
    R> R> _atodt-document-text ;

: _atodt-json-application  ( -- )
    _atodt-application-mode @ 0= IF EXIT THEN
    _atodt-comma
    S" application_type" _atodt-key
    _atodt-application-mode @ 1 = IF
        S" native" _atodt-string EXIT
    THEN
    _atodt-application-mode @ 2 = IF
        S" web" _atodt-string EXIT
    THEN
    S" desktop" _atodt-string ;

: _atodt-json-grants  ( -- )
    _atodt-grant-mode @ 0= IF EXIT THEN
    _atodt-comma
    S" grant_types" _atodt-key _atodt-lbracket
    _atodt-grant-mode @ 3 = IF
        S" refresh_token" _atodt-string
    ELSE
        S" authorization_code" _atodt-string
    THEN
    _atodt-grant-mode @ 2 = IF
        _atodt-comma S" refresh_token" _atodt-string
    THEN
    _atodt-grant-mode @ 4 = IF
        _atodt-comma S" urn:example:extra" _atodt-string
    THEN
    _atodt-rbracket ;

: _atodt-json-responses  ( -- )
    _atodt-response-mode @ 0= IF EXIT THEN
    _atodt-comma
    S" response_types" _atodt-key _atodt-lbracket
    _atodt-response-mode @ 2 = IF
        S" token" _atodt-string
    ELSE
        S" code" _atodt-string
    THEN
    _atodt-response-mode @ 3 = IF
        _atodt-comma S" token" _atodt-string
    THEN
    _atodt-rbracket ;

: _atodt-json-redirects  ( -- )
    _atodt-redirect-mode @ 0= IF EXIT THEN
    _atodt-comma
    S" redirect_uris" _atodt-key _atodt-lbracket
    _atodt-redirect-mode @ 3 <> IF
        _atodt-metadata-redirect-a @
        _atodt-metadata-redirect-u @ _atodt-string
        _atodt-redirect-mode @ 2 = IF
            _atodt-comma
            _atodt-metadata-redirect2-a @
            _atodt-metadata-redirect2-u @ _atodt-string
        THEN
    THEN
    _atodt-rbracket ;

: _atodt-json-scope  ( -- )
    _atodt-scope-present @ 0= IF EXIT THEN
    _atodt-comma
    S" scope"
    _atodt-metadata-scope-a @
    _atodt-metadata-scope-u @
        _atodt-member-string ;

: _atodt-json-method  ( -- )
    _atodt-method-present @ 0= IF EXIT THEN
    _atodt-comma
    S" token_endpoint_auth_method"
    _atodt-metadata-method-a @
    _atodt-metadata-method-u @
        _atodt-member-string ;

: _atodt-json-algorithm  ( -- )
    _atodt-algorithm-present @ 0= IF EXIT THEN
    _atodt-comma
    S" token_endpoint_auth_signing_alg"
    _atodt-metadata-algorithm-a @
    _atodt-metadata-algorithm-u @
        _atodt-member-string ;

: _atodt-json-dpop  ( -- )
    _atodt-dpop-mode @ 0= IF EXIT THEN
    _atodt-comma
    S" dpop_bound_access_tokens" _atodt-key
    _atodt-dpop-mode @ 2 = IF
        S" true"
    ELSE
        S" false"
    THEN
    _atodt-document-text ;

: _atodt-json-inline-jwks  ( -- )
    _atodt-comma
    S" jwks" _atodt-key
    _atodt-document _atodt-document-u @ +
        _atodt-inline-jwks-a !
    _atodt-lbrace
    S" keys" _atodt-key _atodt-lbracket
    _atodt-lbrace
    S" kty" S" EC" _atodt-member-string _atodt-comma
    S" kid" S" client-1" _atodt-member-string
    _atodt-rbrace _atodt-rbracket _atodt-rbrace
    _atodt-document _atodt-document-u @ +
    _atodt-inline-jwks-a @ -
        _atodt-inline-jwks-u ! ;

: _atodt-json-jwks-uri  ( -- )
    _atodt-comma
    S" jwks_uri" S" https://client.example/oauth/jwks.json"
        _atodt-member-string ;

: _atodt-json-keys  ( -- )
    _atodt-key-mode @ 1 = IF
        _atodt-json-inline-jwks EXIT
    THEN
    _atodt-key-mode @ 2 = IF
        _atodt-json-jwks-uri EXIT
    THEN
    _atodt-key-mode @ 3 = IF
        _atodt-json-inline-jwks
        _atodt-json-jwks-uri
    THEN ;

: _atodt-document-build  ( -- )
    _atodt-document-reset _atodt-lbrace
    S" client_id"
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
        _atodt-member-string
    _atodt-json-application
    _atodt-json-grants
    _atodt-json-responses
    _atodt-json-redirects
    _atodt-json-scope
    _atodt-json-method
    _atodt-json-algorithm
    _atodt-json-dpop
    _atodt-json-keys
    _atodt-rbrace ;

: _atodt-document-malformed  ( -- )
    _atodt-document-reset _atodt-lbrace
    S" client_id"
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
        _atodt-member-string
    _atodt-comma
    S" grant_types" _atodt-key _atodt-lbracket ;

\ =====================================================================
\  Baseline deployments
\ =====================================================================

: _atodt-native-public-defaults  ( -- )
    S" https://app.example.com/oauth/client-metadata.json"
        _atodt-config-client!
    S" com.example.app:/oauth/callback"
        _atodt-config-redirect!
    S" atproto" _atodt-config-scope!
    S" none" _atodt-config-method!
    _atodt-no-config-algorithm
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR
        _atodt-config-flags !

    S" https://app.example.com/oauth/client-metadata.json"
        _atodt-metadata-client!
    1 _atodt-application-mode !
    1 _atodt-grant-mode !
    1 _atodt-response-mode !
    1 _atodt-redirect-mode !
    S" com.example.app:/oauth/callback"
        _atodt-metadata-redirect!
    _atodt-no-metadata-redirect2
    S" atproto" _atodt-metadata-scope!
    -1 _atodt-scope-present !
    S" none" _atodt-metadata-method!
    -1 _atodt-method-present !
    S" ES256" _atodt-metadata-algorithm!
    0 _atodt-algorithm-present !
    2 _atodt-dpop-mode !
    0 _atodt-key-mode ! ;

: _atodt-web-confidential-defaults  ( -- )
    S" https://client.example/oauth/client-metadata.json"
        _atodt-config-client!
    S" https://client.example/oauth/callback"
        _atodt-config-redirect!
    S" repo:write atproto" _atodt-config-scope!
    S" private_key_jwt" _atodt-config-method!
    S" ES256" _atodt-config-algorithm!
    OAUTH2-CLIENT-CONFIG-F-REFRESH
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR
        _atodt-config-flags !

    S" https://client.example/oauth/client-metadata.json"
        _atodt-metadata-client!
    2 _atodt-application-mode !
    2 _atodt-grant-mode !
    1 _atodt-response-mode !
    2 _atodt-redirect-mode !
    S" https://client.example/oauth/callback"
        _atodt-metadata-redirect!
    S" https://other.example/oauth/callback"
        _atodt-metadata-redirect2!
    S" atproto transition:generic repo:write"
        _atodt-metadata-scope!
    -1 _atodt-scope-present !
    S" private_key_jwt" _atodt-metadata-method!
    -1 _atodt-method-present !
    S" ES256" _atodt-metadata-algorithm!
    -1 _atodt-algorithm-present !
    2 _atodt-dpop-mode !
    1 _atodt-key-mode ! ;

\ =====================================================================
\  Snapshots, calls, and callback views
\ =====================================================================

: _atodt-snapshot  ( -- )
    _atodt-document _atodt-document-copy
        _atodt-document-u @ MOVE
    _atodt-config _atodt-config-copy
        OAUTH2-CLIENT-CONFIG-SIZE MOVE
    _atopt-profile _atodt-profile-copy
        AT-OAUTH-PROFILE-SIZE MOVE ;

: _atodt-document-unchanged?  ( -- flag )
    _atodt-document _atodt-document-u @
    _atodt-document-copy _atodt-document-u @
        COMPARE 0= ;

: _atodt-config-unchanged?  ( -- flag )
    _atodt-config OAUTH2-CLIENT-CONFIG-SIZE
    _atodt-config-copy OAUTH2-CLIENT-CONFIG-SIZE
        COMPARE 0= ;

: _atodt-profile-unchanged?  ( -- flag )
    _atopt-profile AT-OAUTH-PROFILE-SIZE
    _atodt-profile-copy AT-OAUTH-PROFILE-SIZE
        COMPARE 0= ;

: _atodt-inputs-unchanged?  ( -- flag )
    _atodt-document-unchanged?
    _atodt-config-unchanged? AND
    _atodt-profile-unchanged? AND ;

: _atodt-fill-work  ( -- )
    _atodt-work AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE
        0xA5 FILL ;

: _atodt-fill-all-work  ( -- )
    _atodt-work AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE 8 +
        0xA5 FILL ;

: _atodt-work-zero?  ( -- flag )
    _atodt-work AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE
        _atodt-zero? ;

: _atodt-work-filled?  ( -- flag )
    _atodt-work AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE
        0xA5 _atodt-byte? ;

: _atodt-all-work-filled?  ( -- flag )
    _atodt-work AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE 8 +
        0xA5 _atodt-byte? ;

: _atodt-work-wiped-canary?  ( -- flag )
    _atodt-work-zero?
    _atodt-work AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE +
    8 0xA5 _atodt-byte? AND ;

: _atodt-call  ( callback context -- result status )
    >R >R
    _atodt-document _atodt-document-u @
    _atodt-config _atopt-profile
    R> R> _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH ;

: _atodt-jwks-shape?  ( address length -- flag )
    DUP 2 U< IF 2DROP 0 EXIT THEN
    2DUP + 1- C@ 125 = >R
    DROP C@ 123 =
    R> AND ;

: _atodt-view-callback
  ( config-view metadata-view context -- result )
    1 _atodt-callback-count +!
    _ATODT-CONTEXT = _atodt-assert
    OVER _atodt-config = _atodt-assert
    DUP _atodt-saved-metadata-view !

    OVER OAUTH2-CLIENT-VIEW-BINDING@
    S" at-oauth-deployment-binding"
        COMPARE 0= _atodt-assert
    OVER OAUTH2-CLIENT-VIEW-CLIENT-ID@
    _atodt-config-client-a @ _atodt-config-client-u @
        COMPARE 0= _atodt-assert
    OVER OAUTH2-CLIENT-VIEW-REDIRECT-URI@
    _atodt-config-redirect-a @ _atodt-config-redirect-u @
        COMPARE 0= _atodt-assert
    OVER OAUTH2-CLIENT-VIEW-SCOPE@
    _atodt-config-scope-a @ _atodt-config-scope-u @
        COMPARE 0= _atodt-assert
    OVER OAUTH2-CLIENT-VIEW-AUTH-METHOD@
    _atodt-config-method-a @ _atodt-config-method-u @
        COMPARE 0= _atodt-assert
    OVER OAUTH2-CLIENT-VIEW-DPOP-BOUND?
        _atodt-assert

    DUP OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-OK _atodt-status
    0<> _atodt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
    OAUTH2-CLIENT-METADATA-S-OK _atodt-status
    _atodt-metadata-client-a @ _atodt-metadata-client-u @
        COMPARE 0= _atodt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-DPOP-BOUND?
    OAUTH2-CLIENT-METADATA-S-OK _atodt-status
    _atodt-assert

    _atodt-key-mode @ 1 = IF
        DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS@
        OAUTH2-CLIENT-METADATA-S-OK _atodt-status
        DUP _atodt-inline-jwks-u @ = >R
        OVER _atodt-inline-jwks-a @ = R> AND
            _atodt-assert
        2DUP _atodt-jwks-shape? _atodt-assert
        2DROP
        DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
        OAUTH2-CLIENT-METADATA-S-MISSING _atodt-status
        2DROP
    ELSE
        _atodt-key-mode @ 2 = IF
            DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
            OAUTH2-CLIENT-METADATA-S-OK _atodt-status
            S" https://client.example/oauth/jwks.json"
                COMPARE 0= _atodt-assert
            DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS@
            OAUTH2-CLIENT-METADATA-S-MISSING _atodt-status
            2DROP
        ELSE
            DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS@
            OAUTH2-CLIENT-METADATA-S-MISSING _atodt-status
            2DROP
            DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
            OAUTH2-CLIENT-METADATA-S-MISSING _atodt-status
            2DROP
        THEN
    THEN

    2DROP
    _ATODT-RESULT ;

: _atodt-callback-never
  ( config-view metadata-view context -- result )
    1 _atodt-callback-count +!
    2DROP DROP
    0 _atodt-assert
    0 ;

: _atodt-callback-throw
  ( config-view metadata-view context -- result )
    1 _atodt-callback-count +!
    DROP
    DUP _atodt-saved-metadata-view !
    2DROP
    -17641 THROW ;

: _atodt-callback-extra
  ( config-view metadata-view context -- result extra )
    1 _atodt-callback-count +!
    DROP
    DUP _atodt-saved-metadata-view !
    2DROP
    301 302 ;

: _atodt-callback-missing
  ( config-view metadata-view context -- )
    1 _atodt-callback-count +!
    DROP
    DUP _atodt-saved-metadata-view !
    2DROP ;

: _atodt-callback-overconsume
  ( guard config-view metadata-view context -- result extra )
    1 _atodt-callback-count +!
    DROP
    DUP _atodt-saved-metadata-view !
    2DROP DROP
    401 402 ;

: _atodt-saved-view-invalid  ( -- )
    _atodt-saved-metadata-view @
    OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-INVALID _atodt-status
    DROP
    _atodt-saved-metadata-view @
    OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
    OAUTH2-CLIENT-METADATA-S-INVALID _atodt-status
    2DROP ;

: _atodt-expected-callback-count  ( -- count )
    _atodt-expected-status @
    DUP AT-OAUTH-DEPLOYMENT-S-OK =
    SWAP AT-OAUTH-DEPLOYMENT-S-CALLBACK = OR
    IF 1 ELSE 0 THEN ;

: _atodt-expect-call
  ( callback expected-result expected-status -- )
    _atodt-expected-status !
    _atodt-expected-result !
    0 _atodt-callback-count !
    0 _atodt-saved-metadata-view !
    _atodt-snapshot
    _atodt-fill-all-work
    _ATODT-CONTEXT _atodt-call
    _atodt-expected-status @ _atodt-status
    _atodt-expected-result @ = _atodt-assert
    _atodt-callback-count @
    _atodt-expected-callback-count = _atodt-assert
    _atodt-work-wiped-canary? _atodt-assert
    _atodt-inputs-unchanged? _atodt-assert ;

: _atodt-expect-ok  ( -- )
    ['] _atodt-view-callback
    _ATODT-RESULT AT-OAUTH-DEPLOYMENT-S-OK
        _atodt-expect-call
    _atodt-saved-view-invalid ;

: _atodt-expect-rejection  ( expected-status -- )
    >R
    ['] _atodt-callback-never 0 R>
        _atodt-expect-call ;

: _atodt-preflight-start  ( -- )
    0 _atodt-callback-count !
    _atodt-snapshot
    _atodt-fill-all-work ;

: _atodt-preflight-finish
  ( result status expected-status -- )
    _atodt-status
    0= _atodt-assert
    _atodt-callback-count @ 0= _atodt-assert
    _atodt-all-work-filled? _atodt-assert
    _atodt-inputs-unchanged? _atodt-assert ;

: _atodt-expect-current-preflight  ( expected-status -- )
    >R
    _atodt-preflight-start
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-call
    R> _atodt-preflight-finish ;

\ =====================================================================
\  Contract groups
\ =====================================================================

: _atodt-test-statuses  ( -- )
    AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE 53760 =
        _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-OK 0 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-INVALID 1 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-CAPACITY 2 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-ALIAS 3 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-CONFIG 4 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-PROFILE 5 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-METADATA 6 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-CLIENT-ID 7 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-APPLICATION 8 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-GRANT 9 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-RESPONSE 10 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-REDIRECT 11 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-SCOPE 12 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-AUTH-METHOD 13 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-AUTH-ALGORITHM 14 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-DPOP 15 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-KEY-SOURCE 16 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-CALLBACK 17 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-INTERNAL 18 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-RANGE 19 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-PROTECTED 20 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-PLATFORM 21 = _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-OK
        AT-OAUTH-DEPLOYMENT-STATUS-VALID? _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-PLATFORM
        AT-OAUTH-DEPLOYMENT-STATUS-VALID? _atodt-assert
    -1 AT-OAUTH-DEPLOYMENT-STATUS-VALID? 0=
        _atodt-assert
    AT-OAUTH-DEPLOYMENT-S-PLATFORM 1+
        AT-OAUTH-DEPLOYMENT-STATUS-VALID? 0=
        _atodt-assert

    _atodt-fill-all-work
    _atodt-work AT-OAUTH-DEPLOYMENT-WORKSPACE-CLEAR
        AT-OAUTH-DEPLOYMENT-S-OK _atodt-status
    _atodt-work-wiped-canary? _atodt-assert

    _atodt-fill-all-work
    _atodt-work 1+ AT-OAUTH-DEPLOYMENT-WORKSPACE-CLEAR
        AT-OAUTH-DEPLOYMENT-S-INVALID _atodt-status
    _atodt-all-work-filled? _atodt-assert
    _atodt-stack ;

: _atodt-test-successes  ( -- )
    _atopt-profile-ready

    _atodt-native-public-defaults
    _atodt-config-build
    _atodt-document-build
    _atodt-expect-ok

    _atodt-web-confidential-defaults
    1 _atodt-key-mode !
    _atodt-config-build
    _atodt-document-build
    _atodt-expect-ok

    _atodt-web-confidential-defaults
    2 _atodt-key-mode !
    _atodt-config-build
    _atodt-document-build
    _atodt-expect-ok

    _atodt-web-confidential-defaults
    0 _atodt-application-mode !
    2 _atodt-key-mode !
    _atodt-config-build
    _atodt-document-build
    _atodt-expect-ok
    _atodt-stack ;

: _atodt-test-client-application  ( -- )
    _atopt-profile-ready

    _atodt-native-public-defaults
    S" https://other.example/oauth/client-metadata.json"
        _atodt-metadata-client!
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-CLIENT-ID
        _atodt-expect-rejection

    _atodt-native-public-defaults
    0 _atodt-application-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-APPLICATION
        _atodt-expect-rejection

    _atodt-native-public-defaults
    2 _atodt-application-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-APPLICATION
        _atodt-expect-rejection

    _atodt-native-public-defaults
    3 _atodt-application-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-APPLICATION
        _atodt-expect-rejection
    _atodt-stack ;

: _atodt-test-grants-responses  ( -- )
    _atopt-profile-ready

    _atodt-native-public-defaults
    0 _atodt-grant-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-GRANT _atodt-expect-rejection

    _atodt-native-public-defaults
    2 _atodt-grant-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-GRANT _atodt-expect-rejection

    _atodt-native-public-defaults
    3 _atodt-grant-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-GRANT _atodt-expect-rejection

    _atodt-native-public-defaults
    4 _atodt-grant-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-GRANT _atodt-expect-rejection

    _atodt-web-confidential-defaults
    1 _atodt-grant-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-GRANT _atodt-expect-rejection

    _atodt-native-public-defaults
    0 _atodt-response-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-RESPONSE
        _atodt-expect-rejection

    _atodt-native-public-defaults
    2 _atodt-response-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-RESPONSE
        _atodt-expect-rejection

    _atodt-native-public-defaults
    3 _atodt-response-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-RESPONSE
        _atodt-expect-rejection
    _atodt-stack ;

: _atodt-test-redirects-scope  ( -- )
    _atopt-profile-ready

    _atodt-native-public-defaults
    0 _atodt-redirect-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-REDIRECT
        _atodt-expect-rejection

    _atodt-native-public-defaults
    3 _atodt-redirect-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-REDIRECT
        _atodt-expect-rejection

    _atodt-native-public-defaults
    S" com.example.app:/oauth/other"
        _atodt-metadata-redirect!
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-REDIRECT
        _atodt-expect-rejection

    _atodt-native-public-defaults
    2 _atodt-redirect-mode !
    S" http://evil.example/oauth/callback"
        _atodt-metadata-redirect2!
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-REDIRECT
        _atodt-expect-rejection

    _atodt-native-public-defaults
    2 _atodt-redirect-mode !
    S" com.example.app:/oauth/other"
        _atodt-metadata-redirect!
    S" com.example.app:/oauth/callback"
        _atodt-metadata-redirect2!
    _atodt-config-build
    _atodt-document-build
    _atodt-expect-ok

    _atodt-native-public-defaults
    S" repo:write atproto" _atodt-config-scope!
    S" atproto transition:generic repo:write"
        _atodt-metadata-scope!
    _atodt-config-build
    _atodt-document-build
    _atodt-expect-ok

    _atodt-native-public-defaults
    S" repo:write atproto" _atodt-config-scope!
    S" atproto transition:generic"
        _atodt-metadata-scope!
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-SCOPE _atodt-expect-rejection

    _atodt-native-public-defaults
    0 _atodt-scope-present !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-SCOPE _atodt-expect-rejection
    _atodt-stack ;

: _atodt-test-auth-dpop-keys  ( -- )
    _atopt-profile-ready

    _atodt-native-public-defaults
    0 _atodt-method-present !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-AUTH-METHOD
        _atodt-expect-rejection

    _atodt-web-confidential-defaults
    S" none" _atodt-metadata-method!
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-AUTH-METHOD
        _atodt-expect-rejection

    _atodt-native-public-defaults
    S" tls_client_auth" _atodt-metadata-method!
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-AUTH-METHOD
        _atodt-expect-rejection

    _atodt-native-public-defaults
    -1 _atodt-algorithm-present !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-AUTH-ALGORITHM
        _atodt-expect-rejection

    _atodt-web-confidential-defaults
    0 _atodt-algorithm-present !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-AUTH-ALGORITHM
        _atodt-expect-rejection

    _atodt-web-confidential-defaults
    S" RS256" _atodt-metadata-algorithm!
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-AUTH-ALGORITHM
        _atodt-expect-rejection

    _atodt-native-public-defaults
    0 _atodt-dpop-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-DPOP _atodt-expect-rejection

    _atodt-native-public-defaults
    1 _atodt-dpop-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-DPOP _atodt-expect-rejection

    _atodt-native-public-defaults
    1 _atodt-key-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-KEY-SOURCE
        _atodt-expect-rejection

    _atodt-native-public-defaults
    2 _atodt-key-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-KEY-SOURCE
        _atodt-expect-rejection

    _atodt-web-confidential-defaults
    0 _atodt-key-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-KEY-SOURCE
        _atodt-expect-rejection

    _atodt-web-confidential-defaults
    3 _atodt-key-mode !
    _atodt-config-build
    _atodt-document-build
    AT-OAUTH-DEPLOYMENT-S-METADATA
        _atodt-expect-rejection
    _atodt-stack ;

: _atodt-test-precedence  ( -- )
    _atodt-native-public-defaults
    _atodt-config-build
    _atodt-document-malformed
    _atopt-profile-ready
    0 _atodt-config !
    0 _atopt-profile !
    AT-OAUTH-DEPLOYMENT-S-CONFIG
        _atodt-expect-current-preflight

    _atodt-native-public-defaults
    _atodt-config-build
    _atodt-document-malformed
    _atopt-profile-ready
    0 _atopt-profile !
    AT-OAUTH-DEPLOYMENT-S-PROFILE
        _atodt-expect-current-preflight

    _atodt-native-public-defaults
    _atodt-config-build
    _atodt-document-malformed
    _atopt-profile-ready
    AT-OAUTH-DEPLOYMENT-S-METADATA
        _atodt-expect-rejection

    _atodt-native-public-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
        _atodt-config-flags !
    _atodt-config-build
    _atodt-document-malformed
    _atopt-profile-ready
    AT-OAUTH-DEPLOYMENT-S-DPOP
        _atodt-expect-rejection
    _atodt-stack ;

: _atodt-test-callbacks  ( -- )
    _atopt-profile-ready
    _atodt-native-public-defaults
    _atodt-config-build
    _atodt-document-build

    ['] _atodt-callback-throw
    0 AT-OAUTH-DEPLOYMENT-S-CALLBACK
        _atodt-expect-call
    _atodt-saved-view-invalid

    ['] _atodt-callback-extra
    0 AT-OAUTH-DEPLOYMENT-S-CALLBACK
        _atodt-expect-call
    _atodt-saved-view-invalid

    ['] _atodt-callback-missing
    0 AT-OAUTH-DEPLOYMENT-S-CALLBACK
        _atodt-expect-call
    _atodt-saved-view-invalid

    _ATODT-STACK-SENTINEL
    ['] _atodt-callback-overconsume
    0 AT-OAUTH-DEPLOYMENT-S-CALLBACK
        _atodt-expect-call
    _ATODT-STACK-SENTINEL = _atodt-assert
    _atodt-saved-view-invalid
    _atodt-stack ;

: _atodt-test-preflight-ownership  ( -- )
    _atopt-profile-ready
    _atodt-native-public-defaults
    _atodt-config-build
    _atodt-document-build

    _atodt-preflight-start
    _atodt-document 0
    _atodt-config _atopt-profile
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-INVALID _atodt-preflight-finish

    OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES 1+
        _atodt-document-u !
    _atodt-preflight-start
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-call
    AT-OAUTH-DEPLOYMENT-S-CAPACITY _atodt-preflight-finish
    _atodt-document-build

    _atodt-preflight-start
    _atodt-document _atodt-document-u @
    _atodt-config _atopt-profile
    0 _ATODT-CONTEXT _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-INVALID _atodt-preflight-finish

    _atodt-preflight-start
    _atodt-document _atodt-document-u @
    _atodt-config 1+ _atopt-profile
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-INVALID _atodt-preflight-finish

    _atodt-preflight-start
    _atodt-document _atodt-document-u @
    _atodt-config _atopt-profile 1+
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-INVALID _atodt-preflight-finish

    _atodt-preflight-start
    _atodt-document _atodt-document-u @
    _atodt-config _atopt-profile
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-work 1+
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-INVALID _atodt-preflight-finish

    _atodt-preflight-start
    _atodt-work 2
    _atodt-config _atopt-profile
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-ALIAS _atodt-preflight-finish

    _atodt-preflight-start
    _atodt-document _atodt-document-u @
    _atodt-work _atopt-profile
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-ALIAS _atodt-preflight-finish

    _atodt-preflight-start
    _atodt-document _atodt-document-u @
    _atodt-config _atodt-work
    ['] _atodt-callback-never _ATODT-CONTEXT _atodt-work
    AT-OAUTH-DEPLOYMENT-WITH
    AT-OAUTH-DEPLOYMENT-S-ALIAS _atodt-preflight-finish
    _atodt-stack ;

: _ATODT-INIT  ( -- )
    _ATOPT-INIT
    _atopt-build-identity
    0 _atodt-checks !
    0 _atodt-fails !
    DEPTH _atodt-depth ! ;

: _ATODT-FINISH  ( -- )
    _atopt-fails @ 0= _atodt-assert
    _atodt-stack
    _atodt-fails @ IF
        ." AT OAUTH DEPLOYMENT FAIL checks/fails "
        _atodt-checks @ . _atodt-fails @ . CR
    ELSE
        ." AT OAUTH DEPLOYMENT PASS "
        _atodt-checks @ . CR
    THEN ;

: _ATODT-RUN  ( -- )
    _ATODT-INIT
    _atodt-test-statuses
    _atodt-test-successes
    _atodt-test-client-application
    _atodt-test-grants-responses
    _atodt-test-redirects-scope
    _atodt-test-auth-dpop-keys
    _atodt-test-precedence
    _atodt-test-callbacks
    _atodt-test-preflight-ownership
    _ATODT-FINISH ;
