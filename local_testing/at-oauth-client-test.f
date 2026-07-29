\ Focused contracts for AT OAuth client-selection policy.

PROVIDED at-oauth-client-test

VARIABLE _atoct-checks
VARIABLE _atoct-fails
VARIABLE _atoct-depth
VARIABLE _atoct-expected

VARIABLE _atoct-client-a
VARIABLE _atoct-client-u
VARIABLE _atoct-redirect-a
VARIABLE _atoct-redirect-u
VARIABLE _atoct-scope-a
VARIABLE _atoct-scope-u
VARIABLE _atoct-method-a
VARIABLE _atoct-method-u
VARIABLE _atoct-algorithm-a
VARIABLE _atoct-algorithm-u
VARIABLE _atoct-flags

VARIABLE _atoct-long-client-u
VARIABLE _atoct-long-redirect-u

CREATE _atoct-input-storage
    OAUTH2-CLIENT-CONFIG-INPUT-SIZE 15 + ALLOT
CREATE _atoct-config-storage
    OAUTH2-CLIENT-CONFIG-SIZE 15 + ALLOT
CREATE _atoct-config-copy-storage
    OAUTH2-CLIENT-CONFIG-SIZE 15 + ALLOT
CREATE _atoct-profile-copy-storage
    AT-OAUTH-PROFILE-SIZE 15 + ALLOT
CREATE _atoct-work-storage
    AT-OAUTH-CLIENT-WORKSPACE-SIZE 15 + ALLOT
CREATE _atoct-adjacent-storage
    OAUTH2-CLIENT-CONFIG-SIZE
    AT-OAUTH-CLIENT-WORKSPACE-SIZE + 15 + ALLOT

2048 CONSTANT _ATOCT-LONG-CLIENT-CAPACITY
4096 CONSTANT _ATOCT-LONG-REDIRECT-CAPACITY

CREATE _atoct-long-client
    _ATOCT-LONG-CLIENT-CAPACITY ALLOT
CREATE _atoct-long-redirect
    _ATOCT-LONG-REDIRECT-CAPACITY ALLOT

: _atoct-input  ( -- input )
    _atoct-input-storage 7 + -8 AND ;

: _atoct-config  ( -- config )
    _atoct-config-storage 7 + -8 AND ;

: _atoct-config-copy  ( -- config )
    _atoct-config-copy-storage 7 + -8 AND ;

: _atoct-profile-copy  ( -- profile )
    _atoct-profile-copy-storage 7 + -8 AND ;

: _atoct-work  ( -- workspace )
    _atoct-work-storage 7 + -8 AND ;

: _atoct-adjacent-config  ( -- config )
    _atoct-adjacent-storage 7 + -8 AND ;

: _atoct-adjacent-work  ( -- workspace )
    _atoct-adjacent-config OAUTH2-CLIENT-CONFIG-SIZE + ;

: _atoct-assert  ( flag -- )
    1 _atoct-checks +!
    0= IF
        1 _atoct-fails +!
        ." AT OAUTH CLIENT ASSERT " _atoct-checks @ . CR
    THEN ;

: _atoct-status  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH CLIENT STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _atoct-assert ;

: _atoct-stack  ( -- )
    DEPTH DUP _atoct-depth @ <> IF
        ." AT OAUTH CLIENT STACK "
        _atoct-depth @ . ." -> " DUP . CR .S CR
    THEN
    _atoct-depth @ = _atoct-assert ;

: _atoct-zero?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _atoct-byte?  ( address length byte -- flag )
    >R
    BEGIN DUP WHILE
        OVER C@ R@ <> IF 2DROP R> DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _atoct-fill-work  ( -- )
    _atoct-work AT-OAUTH-CLIENT-WORKSPACE-SIZE 165 FILL ;

: _atoct-work-zero?  ( -- flag )
    _atoct-work AT-OAUTH-CLIENT-WORKSPACE-SIZE _atoct-zero? ;

: _atoct-work-filled?  ( -- flag )
    _atoct-work AT-OAUTH-CLIENT-WORKSPACE-SIZE 165 _atoct-byte? ;

: _atoct-pair!
  ( source-address source-length address-field length-field -- )
    >R
    OVER R@ !
    NIP !
    R> DROP ;

: _atoct-client!  ( address length -- )
    _atoct-client-u ! _atoct-client-a ! ;

: _atoct-redirect!  ( address length -- )
    _atoct-redirect-u ! _atoct-redirect-a ! ;

: _atoct-scope!  ( address length -- )
    _atoct-scope-u ! _atoct-scope-a ! ;

: _atoct-method!  ( address length -- )
    _atoct-method-u ! _atoct-method-a ! ;

: _atoct-algorithm!  ( address length -- )
    _atoct-algorithm-u ! _atoct-algorithm-a ! ;

: _atoct-no-algorithm  ( -- )
    0 _atoct-algorithm-a !
    0 _atoct-algorithm-u ! ;

: _atoct-defaults  ( -- )
    S" https://client.example/oauth/client-metadata.json"
        _atoct-client!
    S" https://callback.example/oauth/callback"
        _atoct-redirect!
    S" atproto" _atoct-scope!
    S" none" _atoct-method!
    _atoct-no-algorithm
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND _atoct-flags ! ;

: _atoct-input-build  ( -- )
    _atoct-input OAUTH2-CLIENT-CONFIG-INPUT-CLEAR
        OAUTH2-CLIENT-CONFIG-S-OK _atoct-status

    S" at-oauth-client-binding"
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-U
        _atoct-pair!

    _atoct-client-a @ _atoct-client-u @
    _atoct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U
        _atoct-pair!

    _atoct-redirect-a @ _atoct-redirect-u @
    _atoct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-U
        _atoct-pair!

    _atoct-scope-a @ _atoct-scope-u @
    _atoct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-U
        _atoct-pair!

    _atoct-method-a @ _atoct-method-u @
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-U
        _atoct-pair!

    _atoct-algorithm-a @ _atoct-algorithm-u @
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-U
        _atoct-pair!

    _atoct-flags @
    _atoct-input OAUTH2-CLIENT-CONFIG-I.FLAGS ! ;

: _atoct-config-build  ( -- )
    _atoct-config OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-OK _atoct-status
    _atoct-input-build
    _atoct-input _atoct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-OK _atoct-status ;

: _atoct-config-snapshot  ( -- )
    _atoct-config _atoct-config-copy
        OAUTH2-CLIENT-CONFIG-SIZE MOVE ;

: _atoct-profile-snapshot  ( -- )
    _atopt-profile _atoct-profile-copy
        AT-OAUTH-PROFILE-SIZE MOVE ;

: _atoct-config-unchanged?  ( -- flag )
    _atoct-config OAUTH2-CLIENT-CONFIG-SIZE
    _atoct-config-copy OAUTH2-CLIENT-CONFIG-SIZE
        COMPARE 0= ;

: _atoct-profile-unchanged?  ( -- flag )
    _atopt-profile AT-OAUTH-PROFILE-SIZE
    _atoct-profile-copy AT-OAUTH-PROFILE-SIZE
        COMPARE 0= ;

: _atoct-snapshot  ( -- )
    _atoct-config-snapshot
    _atoct-profile-snapshot ;

: _atoct-inputs-unchanged?  ( -- flag )
    _atoct-config-unchanged?
    _atoct-profile-unchanged? AND ;

: _atoct-expect-admitted  ( expected-status -- )
    _atoct-expected !
    _atoct-config-snapshot
    _atoct-fill-work
    _atoct-config _atopt-profile _atoct-work
    AT-OAUTH-CLIENT-ADMIT
        _atoct-expected @ _atoct-status
    _atoct-work-zero? _atoct-assert
    _atoct-config-unchanged? _atoct-assert ;

: _atoct-expect-preflight  ( expected-status -- )
    _atoct-expected !
    _atoct-snapshot
    _atoct-fill-work
    _atoct-config _atopt-profile _atoct-work
    AT-OAUTH-CLIENT-ADMIT
        _atoct-expected @ _atoct-status
    _atoct-work-filled? _atoct-assert
    _atoct-inputs-unchanged? _atoct-assert ;

: _atoct-reject-client  ( address length -- )
    _atoct-client!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-CLIENT-ID _atoct-expect-admitted ;

: _atoct-reject-redirect  ( address length -- )
    _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-REDIRECT _atoct-expect-admitted ;

: _atoct-throw-operation
  ( config profile workspace -- status )
    2DROP DROP
    -17621 THROW ;

: _atoct-long-client-text  ( address length -- )
    DUP _atoct-expected !
    _atoct-long-client _atoct-long-client-u @ + SWAP MOVE
    _atoct-expected @ _atoct-long-client-u +! ;

: _atoct-long-client-char  ( byte -- )
    _atoct-long-client _atoct-long-client-u @ + C!
    1 _atoct-long-client-u +! ;

: _atoct-long-redirect-text  ( address length -- )
    DUP _atoct-expected !
    _atoct-long-redirect _atoct-long-redirect-u @ + SWAP MOVE
    _atoct-expected @ _atoct-long-redirect-u +! ;

: _atoct-long-redirect-char  ( byte -- )
    _atoct-long-redirect _atoct-long-redirect-u @ + C!
    1 _atoct-long-redirect-u +! ;

: _atoct-long-client-repeat  ( byte count -- )
    BEGIN DUP WHILE
        OVER _atoct-long-client-char
        1-
    REPEAT
    2DROP ;

: _atoct-long-redirect-repeat  ( byte count -- )
    BEGIN DUP WHILE
        OVER _atoct-long-redirect-char
        1-
    REPEAT
    2DROP ;

: _atoct-build-long-values  ( -- )
    0 _atoct-long-client-u !
    S" https://client.example/" _atoct-long-client-text
    1536 _atoct-long-client-u @ -
    BEGIN DUP WHILE
        [CHAR] a _atoct-long-client-char
        1-
    REPEAT
    DROP

    0 _atoct-long-redirect-u !
    S" https://callback.example/" _atoct-long-redirect-text
    1600 _atoct-long-redirect-u @ -
    BEGIN DUP WHILE
        [CHAR] b _atoct-long-redirect-char
        1-
    REPEAT
    DROP ;

: _atoct-build-max-host-native  ( -- )
    0 _atoct-long-client-u !
    S" https://" _atoct-long-client-text
    [CHAR] a 63 _atoct-long-client-repeat
    [CHAR] . _atoct-long-client-char
    [CHAR] b 63 _atoct-long-client-repeat
    [CHAR] . _atoct-long-client-char
    [CHAR] c 63 _atoct-long-client-repeat
    [CHAR] . _atoct-long-client-char
    [CHAR] d 61 _atoct-long-client-repeat
    S" /client.json" _atoct-long-client-text

    0 _atoct-long-redirect-u !
    [CHAR] d 61 _atoct-long-redirect-repeat
    [CHAR] . _atoct-long-redirect-char
    [CHAR] c 63 _atoct-long-redirect-repeat
    [CHAR] . _atoct-long-redirect-char
    [CHAR] b 63 _atoct-long-redirect-repeat
    [CHAR] . _atoct-long-redirect-char
    [CHAR] a 63 _atoct-long-redirect-repeat
    S" :/callback" _atoct-long-redirect-text ;

\ =====================================================================
\  Contract groups
\ =====================================================================

: _atoct-test-happy  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" https://callback.example.net:8443/cb?slot=1"
        _atoct-redirect!
    OAUTH2-CLIENT-CONFIG-F-REFRESH
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR
        _atoct-flags !
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" private_key_jwt" _atoct-method!
    S" ES256" _atoct-algorithm!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" https://app.example.com/oauth/client.json" _atoct-client!
    S" com.example.app:/oauth/callback?slot=1" _atoct-redirect!
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR
        _atoct-flags !
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" https://app.example.com/oauth/client.json" _atoct-client!
    S" https://APP.EXAMPLE.COM:443/callback?[slot]=1"
        _atoct-redirect!
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-REFRESH OR
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR
        _atoct-flags !
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-client-id-positive  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    S" HTTPS://CLIENT.EXAMPLE/?tenant=1" _atoct-client!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-build-max-host-native
    _atoct-defaults
    _atoct-long-client _atoct-long-client-u @ _atoct-client!
    _atoct-long-redirect _atoct-long-redirect-u @ _atoct-redirect!
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-client-id-form  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot
    _atoct-defaults
    S" https://client.example/client%2Ejson" _atoct-client!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-build-long-values
    _atoct-defaults
    _atoct-long-client _atoct-long-client-u @ _atoct-client!
    _atoct-long-redirect _atoct-long-redirect-u @ _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" http://client.example/client.json" _atoct-reject-client
    _atoct-defaults
    S" https:///client.json" _atoct-reject-client
    _atoct-defaults
    S" https://user@client.example/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client.example:443/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client.example:8443/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client.example" _atoct-reject-client
    _atoct-defaults
    S" https://client.example?tenant=1" _atoct-reject-client
    _atoct-defaults
    S" https://client.example/client.json#fragment"
        _atoct-reject-client
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-client-id-dots  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot
    _atoct-defaults
    S" https://client.example/a/./client.json"
        _atoct-reject-client
    _atoct-defaults
    S" https://client.example/a/../client.json"
        _atoct-reject-client
    _atoct-defaults
    S" https://client.example/a/%2e%2E/client.json"
        _atoct-reject-client
    _atoct-defaults
    S" https://client.example/a/%2e/client.json"
        _atoct-reject-client
    _atoct-defaults
    S" https://client.example/a/.%2e/client.json"
        _atoct-reject-client
    _atoct-defaults
    S" https://client.example/a/%2e" _atoct-reject-client
    _atoct-defaults
    S" https://client.example/a/.." _atoct-reject-client
    _atoct-defaults
    S" https://client.example/client%2Gjson" _atoct-reject-client
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-client-id-host  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot
    _atoct-defaults
    S" https://127.0.0.1/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://0x7f000001/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://127.0.0x0.1/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client.example.123/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client.example.0x/client.json" _atoct-reject-client
    _atoct-defaults
    S" http://localhost/" _atoct-reject-client
    _atoct-defaults
    S" https://[::1]/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client.example./client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client..example/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://-client.example/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://client-.example/client.json" _atoct-reject-client
    _atoct-defaults
    S" https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example/client.json"
        _atoct-reject-client
    _atoct-defaults
    S" https://client.example/bad path" _atoct-reject-client
    _atoct-defaults
    S" https://client.example/bad\path" _atoct-reject-client
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-redirect-web-form  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    S" https://other.example:8443/cb?slot=[1]" _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" http://callback.example/cb" _atoct-reject-redirect
    _atoct-defaults
    S" example.client:/callback" _atoct-reject-redirect
    _atoct-defaults
    S" https://callback.example:443/cb" _atoct-reject-redirect
    _atoct-defaults
    S" https://user@callback.example/cb" _atoct-reject-redirect
    _atoct-defaults
    S" https://callback.example/cb#fragment" _atoct-reject-redirect
    _atoct-defaults
    S" https://callback.example/cb%2G" _atoct-reject-redirect
    _atoct-defaults
    S" https://callback.example/bad\path" _atoct-reject-redirect
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-redirect-web-port  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    S" https://callback.example:0/cb" _atoct-reject-redirect
    _atoct-defaults
    S" https://callback.example:65536/cb" _atoct-reject-redirect
    _atoct-defaults
    S" https://callback.example:abc/cb" _atoct-reject-redirect
    _atoct-defaults
    S" https://callback.example:0008443/cb" _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-redirect-native-custom  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" example.client:/callback?slot=[1]" _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" example.client:/" _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" client.example:/callback" _atoct-reject-redirect
    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" example.client://callback" _atoct-reject-redirect
    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" example.client:callback" _atoct-reject-redirect
    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" example.client:/callback#fragment" _atoct-reject-redirect
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-redirect-native-https  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" https://CLIENT.EXAMPLE:443/callback" _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" https://CLIENT.EXAMPLE/callback" _atoct-redirect!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" https://other.example/callback" _atoct-reject-redirect
    _atoct-defaults
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    S" https://client.example:8443/callback"
        _atoct-reject-redirect
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-scope  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    S" atproto transition:generic" _atoct-scope!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" transition:generic atproto repo:write" _atoct-scope!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    S" transition:generic atproto" _atoct-scope!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted

    _atoct-defaults
    0 0 _atoct-scope!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-SCOPE _atoct-expect-admitted
    _atoct-defaults
    S" ATPROTO" _atoct-scope!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-SCOPE _atoct-expect-admitted
    _atoct-defaults
    S" xatproto" _atoct-scope!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-SCOPE _atoct-expect-admitted
    _atoct-defaults
    S" atprotox" _atoct-scope!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-SCOPE _atoct-expect-admitted
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-auth  ( -- )
    _atopt-profile-ready
    _atoct-profile-snapshot

    _atoct-defaults
    S" client_secret_basic" _atoct-method!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-AUTH-METHOD _atoct-expect-admitted

    _atoct-defaults
    S" private_key_jwt" _atoct-method!
    _atoct-no-algorithm
    _atoct-config-build
    AT-OAUTH-CLIENT-S-AUTH-ALGORITHM _atoct-expect-admitted
    _atoct-defaults
    S" private_key_jwt" _atoct-method!
    S" RS256" _atoct-algorithm!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-AUTH-ALGORITHM _atoct-expect-admitted
    _atoct-defaults
    S" private_key_jwt" _atoct-method!
    S" es256" _atoct-algorithm!
    _atoct-config-build
    AT-OAUTH-CLIENT-S-AUTH-ALGORITHM _atoct-expect-admitted

    _atoct-defaults
    S" https://app.example.com/oauth/client.json" _atoct-client!
    S" com.example.app:/oauth/callback" _atoct-redirect!
    S" private_key_jwt" _atoct-method!
    S" ES256" _atoct-algorithm!
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR _atoct-flags !
    _atoct-config-build
    AT-OAUTH-CLIENT-S-AUTH-METHOD _atoct-expect-admitted

    _atoct-defaults
    0 _atoct-flags !
    _atoct-config-build
    AT-OAUTH-CLIENT-S-DPOP _atoct-expect-admitted
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-api-geometry  ( -- )
    AT-OAUTH-CLIENT-WORKSPACE-SIZE 432 = _atoct-assert
    AT-OAUTH-CLIENT-S-OK
        AT-OAUTH-CLIENT-STATUS-VALID? _atoct-assert
    AT-OAUTH-CLIENT-S-INTERNAL
        AT-OAUTH-CLIENT-STATUS-VALID? _atoct-assert
    AT-OAUTH-CLIENT-S-INTERNAL 1+
        AT-OAUTH-CLIENT-STATUS-VALID? 0= _atoct-assert
    -1 AT-OAUTH-CLIENT-STATUS-VALID? 0= _atoct-assert

    _atopt-profile-ready
    _atoct-defaults
    _atoct-config-build

    _atoct-snapshot
    _atoct-fill-work
    _atoct-config 1+ _atopt-profile _atoct-work
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-INVALID _atoct-status
    _atoct-work-filled? _atoct-assert
    _atoct-inputs-unchanged? _atoct-assert

    _atoct-snapshot
    _atoct-fill-work
    _atoct-config _atopt-profile 1+ _atoct-work
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-INVALID _atoct-status
    _atoct-work-filled? _atoct-assert
    _atoct-inputs-unchanged? _atoct-assert

    _atoct-snapshot
    _atoct-fill-work
    _atoct-config _atopt-profile _atoct-work 1+
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-INVALID _atoct-status
    _atoct-work-filled? _atoct-assert
    _atoct-inputs-unchanged? _atoct-assert

    _atoct-snapshot
    _atoct-config _atopt-profile _atoct-config
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-ALIAS _atoct-status
    _atoct-inputs-unchanged? _atoct-assert

    _atoct-snapshot
    _atoct-config _atopt-profile _atopt-profile
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-ALIAS _atoct-status
    _atoct-inputs-unchanged? _atoct-assert

    _atoct-snapshot
    _atoct-config _atopt-profile _atoct-config 8 +
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-ALIAS _atoct-status
    _atoct-inputs-unchanged? _atoct-assert

    _atoct-snapshot
    _atoct-config _atopt-profile _atopt-profile 8 +
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-ALIAS _atoct-status
    _atoct-inputs-unchanged? _atoct-assert

    _atoct-config _atoct-adjacent-config
        OAUTH2-CLIENT-CONFIG-SIZE MOVE
    _atoct-profile-snapshot
    _atoct-adjacent-work
        AT-OAUTH-CLIENT-WORKSPACE-SIZE 165 FILL
    _atoct-adjacent-config _atopt-profile _atoct-adjacent-work
    AT-OAUTH-CLIENT-ADMIT
        AT-OAUTH-CLIENT-S-OK _atoct-status
    _atoct-adjacent-work AT-OAUTH-CLIENT-WORKSPACE-SIZE
        _atoct-zero? _atoct-assert
    _atoct-adjacent-config OAUTH2-CLIENT-CONFIG-SIZE
    _atoct-config OAUTH2-CLIENT-CONFIG-SIZE
        COMPARE 0= _atoct-assert
    _atoct-profile-unchanged? _atoct-assert
    _atoct-stack ;

: _atoct-test-readiness-precedence  ( -- )
    _atopt-profile-ready
    _atoct-defaults
    _atoct-config-build

    1 _atoct-config OAUTH2-CLIENT-CONFIG-SIZE 1- + C!
    AT-OAUTH-CLIENT-S-CONFIG _atoct-expect-preflight

    _atoct-defaults
    _atoct-config-build
    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    AT-OAUTH-CLIENT-S-PROFILE _atoct-expect-preflight

    _atopt-profile-ready
    1 _atopt-profile AT-OAUTH-PROFILE-SIZE 1- + C!
    AT-OAUTH-CLIENT-S-PROFILE _atoct-expect-preflight

    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _atopt-status
    1 _atoct-config OAUTH2-CLIENT-CONFIG-SIZE 1- + C!
    AT-OAUTH-CLIENT-S-CONFIG _atoct-expect-preflight

    _atopt-profile-ready
    _atoct-defaults
    S" http://client.example/client.json" _atoct-client!
    0 0 _atoct-scope!
    0 _atoct-flags !
    _atoct-config-build
    AT-OAUTH-CLIENT-S-CLIENT-ID _atoct-expect-admitted
    _atoct-stack ;

: _atoct-test-ownership  ( -- )
    _atoct-fill-work
    _atoct-work AT-OAUTH-CLIENT-WORKSPACE-CLEAR
        AT-OAUTH-CLIENT-S-OK _atoct-status
    _atoct-work-zero? _atoct-assert

    _atoct-fill-work
    _atoct-work 1+ AT-OAUTH-CLIENT-WORKSPACE-CLEAR
        AT-OAUTH-CLIENT-S-INVALID _atoct-status
    _atoct-work-filled? _atoct-assert

    _atopt-profile-ready
    _atoct-defaults
    _atoct-config-build
    _atoct-profile-snapshot
    AT-OAUTH-CLIENT-S-OK _atoct-expect-admitted
    _atoct-profile-unchanged? _atoct-assert

    _atoct-snapshot
    _atoct-fill-work
    _atoct-config _atopt-profile _atoct-work
    ['] _atoct-throw-operation _ATOC-ADMIT-CALL
        AT-OAUTH-CLIENT-S-INTERNAL _atoct-status
    _atoct-work-zero? _atoct-assert
    _atoct-inputs-unchanged? _atoct-assert
    _atoct-stack ;

: _ATOCT-INIT  ( -- )
    _ATOPT-INIT
    _atopt-build-identity
    0 _atoct-checks !
    0 _atoct-fails !
    DEPTH _atoct-depth ! ;

: _ATOCT-FINISH  ( -- )
    _atopt-fails @ 0= _atoct-assert
    _atoct-stack
    _atoct-fails @ IF
        ." AT OAUTH CLIENT FAIL checks/fails "
        _atoct-checks @ . _atoct-fails @ . CR
    ELSE
        ." AT OAUTH CLIENT PASS " _atoct-checks @ . CR
    THEN ;
