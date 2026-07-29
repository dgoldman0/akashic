\ Focused generic OAuth Client ID Metadata Document contracts.
\ This guest filename stays within the MP64FS component limit.

PROVIDED akashic-o2cm-contracts

VARIABLE _o2cmt-checks
VARIABLE _o2cmt-fails
VARIABLE _o2cmt-depth
VARIABLE _o2cmt-input-u
VARIABLE _o2cmt-copy-u
VARIABLE _o2cmt-callback-count
VARIABLE _o2cmt-saved-view
VARIABLE _o2cmt-remaining
VARIABLE _o2cmt-sequence

OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES 8 +
CONSTANT _O2CMT-INPUT-SIZE

CREATE _o2cmt-input _O2CMT-INPUT-SIZE ALLOT
CREATE _o2cmt-input-copy _O2CMT-INPUT-SIZE ALLOT
CREATE _o2cmt-work-storage
    OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE 15 + ALLOT

CREATE _o2cmt-jwks-expected
    0x7B C, 0x22 C, 0x6B C, 0x65 C, 0x79 C, 0x73 C, 0x22 C, 0x3A C,
    0x5B C, 0x7B C, 0x22 C, 0x6B C, 0x74 C, 0x79 C, 0x22 C, 0x3A C,
    0x22 C, 0x45 C, 0x43 C, 0x22 C, 0x2C C, 0x22 C, 0x6B C, 0x69 C,
    0x64 C, 0x22 C, 0x3A C, 0x22 C, 0x31 C, 0x22 C, 0x7D C, 0x5D C,
    0x7D C,

: _o2cmt-work  ( -- address )
    _o2cmt-work-storage 7 + -8 AND ;

0x123456 CONSTANT _O2CMT-CONTEXT
0x4F32434D5354414B CONSTANT _O2CMT-STACK-SENTINEL

: _o2cmt-assert  ( flag -- )
    1 _o2cmt-checks +!
    0= IF
        1 _o2cmt-fails +!
        ." OAUTH2 CLIENT METADATA ASSERT " _o2cmt-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2cmt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 CLIENT METADATA STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2cmt-assert ;

: _o2cmt-stack  ( -- )
    DEPTH _o2cmt-depth @ = _o2cmt-assert ;

: _o2cmt-filled?  ( address length byte -- flag )
    0x0101010101010101 *
    BEGIN
        2 PICK 7 AND 0<>
        2 PICK 0<> AND
    WHILE
        2 PICK C@ OVER 0xFF AND <> IF
            2DROP DROP 0 EXIT
        THEN
        >R
        1- SWAP 1+ SWAP
        R>
    REPEAT
    BEGIN 1 PICK 8 U< 0= WHILE
        2 PICK @ OVER <> IF
            2DROP DROP 0 EXIT
        THEN
        >R
        8 - SWAP 8 + SWAP
        R>
    REPEAT
    BEGIN 1 PICK WHILE
        2 PICK C@ OVER 0xFF AND <> IF
            2DROP DROP 0 EXIT
        THEN
        >R
        1- SWAP 1+ SWAP
        R>
    REPEAT
    2DROP DROP -1 ;

: _o2cmt-zero?  ( address length -- flag )
    0 _o2cmt-filled? ;

: _o2cmt-work-zero?  ( -- flag )
    _o2cmt-work OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE
    _o2cmt-zero? ;

: _o2cmt-work-filled?  ( -- flag )
    _o2cmt-work OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE
    0xC3 _o2cmt-filled? ;

: _o2cmt-work-all-filled?  ( -- flag )
    _o2cmt-work OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE 8 +
    0xC3 _o2cmt-filled? ;

: _o2cmt-fill-work  ( -- )
    _o2cmt-work OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE
    0xC3 FILL ;

: _o2cmt-fill-all-work  ( -- )
    _o2cmt-work OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE 8 +
    0xC3 FILL ;

: _o2cmt-snapshot  ( -- )
    _o2cmt-input _o2cmt-input-copy _o2cmt-input-u @ MOVE ;

: _o2cmt-source-unchanged?  ( -- flag )
    _o2cmt-input _o2cmt-input-u @
    _o2cmt-input-copy _o2cmt-input-u @
    COMPARE 0= ;

: _o2cmt-source-span?  ( address length -- flag )
    >R
    _o2cmt-input -
    R> _o2cmt-input-u @
    _O2CM-OFFSET-SPAN? ;

: _o2cmt-jwks-exact?  ( address length -- flag )
    _o2cmt-jwks-expected 33 COMPARE 0= ;

: _o2cmt-reset  ( -- )
    0 _o2cmt-input-u ! ;

: _o2cmt-char  ( byte -- )
    _o2cmt-input _o2cmt-input-u @ + C!
    1 _o2cmt-input-u +! ;

: _o2cmt-text  ( address length -- )
    DUP _o2cmt-copy-u !
    _o2cmt-input _o2cmt-input-u @ + SWAP MOVE
    _o2cmt-copy-u @ _o2cmt-input-u +! ;

: _o2cmt-repeat-char  ( byte count -- )
    DUP _o2cmt-copy-u ! >R
    _o2cmt-input _o2cmt-input-u @ + SWAP
    R> SWAP FILL
    _o2cmt-copy-u @ _o2cmt-input-u +! ;

: _o2cmt-repeat-byte  ( byte count -- )
    BEGIN DUP WHILE
        OVER _o2cmt-char
        1-
    REPEAT
    2DROP ;

: _o2cmt-quote     ( -- ) 34 _o2cmt-char ;
: _o2cmt-slash     ( -- ) 92 _o2cmt-char ;
: _o2cmt-comma     ( -- ) 44 _o2cmt-char ;
: _o2cmt-colon     ( -- ) 58 _o2cmt-char ;
: _o2cmt-lbrace    ( -- ) 123 _o2cmt-char ;
: _o2cmt-rbrace    ( -- ) 125 _o2cmt-char ;
: _o2cmt-lbracket  ( -- ) 91 _o2cmt-char ;
: _o2cmt-rbracket  ( -- ) 93 _o2cmt-char ;

: _o2cmt-key  ( address length -- )
    _o2cmt-quote _o2cmt-text _o2cmt-quote _o2cmt-colon ;

: _o2cmt-string  ( address length -- )
    _o2cmt-quote _o2cmt-text _o2cmt-quote ;

: _o2cmt-member-raw
  ( key-a key-u value-a value-u -- )
    >R >R
    _o2cmt-key
    R> R> _o2cmt-text ;

: _o2cmt-member-string
  ( key-a key-u value-a value-u -- )
    >R >R
    _o2cmt-key
    R> R> _o2cmt-string ;

: _o2cmt-client-id  ( -- )
    S" client_id" _o2cmt-key
    S" https://client.example/client.json" _o2cmt-string ;

: _o2cmt-build-minimal  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id
    _o2cmt-rbrace ;

: _o2cmt-build-full  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    S" extension" _o2cmt-key _o2cmt-lbrace
    S" nested" _o2cmt-key _o2cmt-lbracket
    S" true" _o2cmt-text _o2cmt-comma
    S" null" _o2cmt-text _o2cmt-rbracket
    _o2cmt-rbrace _o2cmt-comma

    S" client_id" _o2cmt-key _o2cmt-quote
    S" https:" _o2cmt-text
    _o2cmt-slash S" /" _o2cmt-text
    _o2cmt-slash S" /client.example" _o2cmt-text
    _o2cmt-slash S" /client.json" _o2cmt-text
    _o2cmt-quote _o2cmt-comma

    S" application_type" S" web" _o2cmt-member-string
    _o2cmt-comma
    S" grant_types" _o2cmt-key _o2cmt-lbracket
    S" authorization_code" _o2cmt-string _o2cmt-comma
    _o2cmt-quote S" refresh" _o2cmt-text
    _o2cmt-slash S" u005Ftoken" _o2cmt-text _o2cmt-quote
    _o2cmt-rbracket _o2cmt-comma

    S" response_types" _o2cmt-key _o2cmt-lbracket
    S" code" _o2cmt-string _o2cmt-comma
    S" extension_response" _o2cmt-string
    _o2cmt-rbracket _o2cmt-comma

    S" redirect_uris" _o2cmt-key _o2cmt-lbracket
    S" https://client.example/cb" _o2cmt-string _o2cmt-comma
    S" app:/cb" _o2cmt-string
    _o2cmt-rbracket _o2cmt-comma

    S" scope" S" atproto transition:generic"
    _o2cmt-member-string _o2cmt-comma
    S" token_endpoint_auth_method" S" private_key_jwt"
    _o2cmt-member-string _o2cmt-comma
    S" token_endpoint_auth_signing_alg" S" ES256"
    _o2cmt-member-string _o2cmt-comma
    S" dpop_bound_access_tokens" S" true"
    _o2cmt-member-raw _o2cmt-comma

    S" jwks" _o2cmt-key _o2cmt-lbrace
    S" keys" _o2cmt-key _o2cmt-lbracket _o2cmt-lbrace
    S" kty" S" EC" _o2cmt-member-string _o2cmt-comma
    S" kid" S" 1" _o2cmt-member-string
    _o2cmt-rbrace _o2cmt-rbracket _o2cmt-rbrace
    _o2cmt-rbrace ;

: _o2cmt-build-policy-neutral  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" application_type" S" desktop" _o2cmt-member-string
    _o2cmt-comma
    S" grant_types" S" []" _o2cmt-member-raw _o2cmt-comma
    S" response_types" S" []" _o2cmt-member-raw _o2cmt-comma
    S" redirect_uris" S" []" _o2cmt-member-raw _o2cmt-comma
    S" scope" S" profile" _o2cmt-member-string _o2cmt-comma
    S" token_endpoint_auth_method" S" custom_method"
    _o2cmt-member-string _o2cmt-comma
    S" token_endpoint_auth_signing_alg" S" PS256"
    _o2cmt-member-string _o2cmt-comma
    S" dpop_bound_access_tokens" S" false"
    _o2cmt-member-raw _o2cmt-comma
    S" jwks_uri" S" https://client.example/jwks.json"
    _o2cmt-member-string
    _o2cmt-rbrace ;

: _o2cmt-build-client-string  ( value-a value-u -- )
    _o2cmt-reset _o2cmt-lbrace
    S" client_id" 2SWAP _o2cmt-member-string
    _o2cmt-rbrace ;

: _o2cmt-build-client-raw  ( value-a value-u -- )
    _o2cmt-reset _o2cmt-lbrace
    S" client_id" 2SWAP _o2cmt-member-raw
    _o2cmt-rbrace ;

: _o2cmt-build-extra-string
  ( key-a key-u value-a value-u -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    _o2cmt-member-string
    _o2cmt-rbrace ;

: _o2cmt-build-extra-raw
  ( key-a key-u value-a value-u -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    _o2cmt-member-raw
    _o2cmt-rbrace ;

: _o2cmt-build-extra-array-one
  ( key-a key-u value-a value-u -- )
    >R >R
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    _o2cmt-key _o2cmt-lbracket
    R> R> _o2cmt-string
    _o2cmt-rbracket _o2cmt-rbrace ;

: _o2cmt-build-missing  ( -- )
    _o2cmt-reset _o2cmt-lbrace _o2cmt-rbrace ;

: _o2cmt-build-malformed  ( -- )
    _o2cmt-reset _o2cmt-lbrace _o2cmt-client-id ;

: _o2cmt-build-invalid-utf8  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    S" client_id" _o2cmt-key
    _o2cmt-quote 0xFF _o2cmt-char _o2cmt-quote
    _o2cmt-rbrace ;

: _o2cmt-build-duplicate-client-id  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    _o2cmt-quote S" client" _o2cmt-text
    _o2cmt-slash S" u005Fid" _o2cmt-text
    _o2cmt-quote _o2cmt-colon
    S" https://other.example/client.json" _o2cmt-string
    _o2cmt-rbrace ;

: _o2cmt-build-duplicate-grant  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" grant_types" _o2cmt-key _o2cmt-lbracket
    S" authorization_code" _o2cmt-string _o2cmt-comma
    _o2cmt-quote S" authorization" _o2cmt-text
    _o2cmt-slash S" u005Fcode" _o2cmt-text
    _o2cmt-quote _o2cmt-rbracket
    _o2cmt-rbrace ;

: _o2cmt-build-nested-jwks-duplicate  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" jwks" _o2cmt-key _o2cmt-lbrace
    S" keys" S" []" _o2cmt-member-raw _o2cmt-comma
    _o2cmt-quote S" k" _o2cmt-text
    _o2cmt-slash S" u0065ys" _o2cmt-text
    _o2cmt-quote _o2cmt-colon S" []" _o2cmt-text
    _o2cmt-rbrace _o2cmt-rbrace ;

: _o2cmt-build-both-key-sources  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" jwks" S" {}" _o2cmt-member-raw _o2cmt-comma
    S" jwks_uri" S" https://client.example/jwks.json"
    _o2cmt-member-string
    _o2cmt-rbrace ;

: _o2cmt-build-escaped-secret-method  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" token_endpoint_auth_method" _o2cmt-key
    _o2cmt-quote S" client" _o2cmt-text
    _o2cmt-slash S" u005Fsecret_basic" _o2cmt-text
    _o2cmt-quote _o2cmt-rbrace ;

: _o2cmt-build-too-deep  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" extension" _o2cmt-key
    91 JOSE-JSON-MAX-DEPTH 1+ _o2cmt-repeat-byte
    S" 0" _o2cmt-text
    93 JOSE-JSON-MAX-DEPTH 1+ _o2cmt-repeat-byte
    _o2cmt-rbrace ;

: _o2cmt-build-long-client  ( decoded-u -- )
    _o2cmt-reset _o2cmt-lbrace
    S" client_id" _o2cmt-key _o2cmt-quote
    97 SWAP _o2cmt-repeat-char
    _o2cmt-quote _o2cmt-rbrace ;

: _o2cmt-build-long-application  ( decoded-u -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" application_type" _o2cmt-key _o2cmt-quote
    97 SWAP _o2cmt-repeat-char
    _o2cmt-quote _o2cmt-rbrace ;

: _o2cmt-build-long-extra  ( key-a key-u decoded-u -- )
    >R
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    _o2cmt-key _o2cmt-quote
    97 R> _o2cmt-repeat-char
    _o2cmt-quote _o2cmt-rbrace ;

: _o2cmt-build-long-grant  ( decoded-u -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" grant_types" _o2cmt-key _o2cmt-lbracket
    _o2cmt-quote 97 SWAP _o2cmt-repeat-char _o2cmt-quote
    _o2cmt-rbracket _o2cmt-rbrace ;

: _o2cmt-build-grant-pair-total  ( decoded-total -- )
    >R
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" grant_types" _o2cmt-key _o2cmt-lbracket
    _o2cmt-quote 97 2048 _o2cmt-repeat-char _o2cmt-quote
    _o2cmt-comma _o2cmt-quote
    98 R> 2048 - _o2cmt-repeat-char
    _o2cmt-quote _o2cmt-rbracket _o2cmt-rbrace ;

: _o2cmt-append-unique-values  ( count -- )
    35 _o2cmt-sequence !
    _o2cmt-remaining !
    BEGIN _o2cmt-remaining @ WHILE
        _o2cmt-quote
        _o2cmt-sequence @
        DUP 92 >= IF 1+ THEN
        _o2cmt-char
        _o2cmt-quote
        -1 _o2cmt-remaining +!
        1 _o2cmt-sequence +!
        _o2cmt-remaining @ IF _o2cmt-comma THEN
    REPEAT ;

: _o2cmt-build-grant-count  ( count -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id _o2cmt-comma
    S" grant_types" _o2cmt-key _o2cmt-lbracket
    _o2cmt-append-unique-values
    _o2cmt-rbracket _o2cmt-rbrace ;

: _o2cmt-append-unknown-members  ( count -- )
    35 _o2cmt-sequence !
    _o2cmt-remaining !
    BEGIN _o2cmt-remaining @ WHILE
        _o2cmt-comma _o2cmt-quote
        120 _o2cmt-char
        _o2cmt-sequence @
        DUP 92 >= IF 1+ THEN
        _o2cmt-char
        _o2cmt-quote _o2cmt-colon S" 0" _o2cmt-text
        -1 _o2cmt-remaining +!
        1 _o2cmt-sequence +!
    REPEAT ;

: _o2cmt-build-member-overflow  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id
    64 _o2cmt-append-unknown-members
    _o2cmt-rbrace ;

: _o2cmt-build-name-capacity  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id
    _o2cmt-comma _o2cmt-quote
    120 4087 _o2cmt-repeat-char
    _o2cmt-quote _o2cmt-colon S" 0" _o2cmt-text
    _o2cmt-rbrace ;

: _o2cmt-build-name-overflow  ( -- )
    _o2cmt-reset _o2cmt-lbrace
    _o2cmt-client-id
    _o2cmt-comma _o2cmt-quote
    120 4088 _o2cmt-repeat-char
    _o2cmt-quote _o2cmt-colon S" 0" _o2cmt-text
    _o2cmt-rbrace ;

: _o2cmt-call
  ( callback context -- callback-status metadata-status )
    >R >R
    _o2cmt-input _o2cmt-input-u @
    R> R> _o2cmt-work
    OAUTH2-CLIENT-METADATA-WITH ;

: _o2cmt-saved-view-invalid  ( -- )
    _o2cmt-saved-view @ OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    DROP
    _o2cmt-saved-view @ OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    2DROP
    _o2cmt-saved-view @
    OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    DROP
    _o2cmt-saved-view @ OAUTH2-CLIENT-METADATA-VIEW-JWKS@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    2DROP ;

: _o2cmt-callback-minimal  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    _O2CMT-CONTEXT = _o2cmt-assert
    DUP _o2cmt-saved-view !

    DUP OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    OAUTH2-CLIENT-METADATA-P-CLIENT-ID = _o2cmt-assert

    DUP OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" https://client.example/client.json"
    COMPARE 0= _o2cmt-assert

    DUP OAUTH2-CLIENT-METADATA-VIEW-APPLICATION-TYPE@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    DROP
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    S" authorization_code" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE?
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    DROP
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    S" code" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE?
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI-COUNT@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    DROP
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    S" https://client.example/cb" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI?
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-SCOPE@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-METHOD@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-SIGNING-ALG@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-DPOP-BOUND?
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    DROP
    DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    101 ;

: _o2cmt-callback-full  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    DROP
    DUP _o2cmt-saved-view !

    DUP OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    OAUTH2-CLIENT-METADATA-P-ALL
    OAUTH2-CLIENT-METADATA-P-JWKS-URI INVERT AND
    = _o2cmt-assert

    DUP OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" https://client.example/client.json"
    COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-APPLICATION-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" web" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-SCOPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" atproto transition:generic" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-METHOD@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" private_key_jwt" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-SIGNING-ALG@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" ES256" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-DPOP-BOUND?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    _o2cmt-assert

    DUP OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    2 = _o2cmt-assert
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" authorization_code" COMPARE 0= _o2cmt-assert
    1 OVER OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" refresh_token" COMPARE 0= _o2cmt-assert
    S" refresh_token" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    _o2cmt-assert
    S" REFRESH_TOKEN" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    -1 OVER OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    2DROP
    2 OVER OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    2DROP

    DUP OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    2 = _o2cmt-assert
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" code" COMPARE 0= _o2cmt-assert
    S" extension_response" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    _o2cmt-assert

    DUP OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    2 = _o2cmt-assert
    1 OVER OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" app:/cb" COMPARE 0= _o2cmt-assert
    S" https://client.example/cb" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    _o2cmt-assert

    DUP OAUTH2-CLIENT-METADATA-VIEW-JWKS@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    2DUP _o2cmt-source-span? _o2cmt-assert
    _o2cmt-jwks-exact? _o2cmt-assert
    OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-status
    2DROP
    202 ;

: _o2cmt-callback-policy-neutral
  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    DROP
    DUP _o2cmt-saved-view !

    DUP OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    OAUTH2-CLIENT-METADATA-P-ALL
    OAUTH2-CLIENT-METADATA-P-JWKS INVERT AND
    = _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-APPLICATION-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" desktop" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    2DROP
    S" authorization_code" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    2DROP
    S" code" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI@
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    2DROP
    S" https://client.example/cb" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-SCOPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" profile" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-METHOD@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" custom_method" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-SIGNING-ALG@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" PS256" COMPARE 0= _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-DPOP-BOUND?
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    0= _o2cmt-assert
    OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" https://client.example/jwks.json"
    COMPARE 0= _o2cmt-assert
    303 ;

: _o2cmt-callback-long-client  ( view expected-u -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    404 ;

: _o2cmt-callback-long-application
  ( view expected-u -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    OAUTH2-CLIENT-METADATA-VIEW-APPLICATION-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    505 ;

: _o2cmt-callback-long-scope  ( view expected-u -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    OAUTH2-CLIENT-METADATA-VIEW-SCOPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    515 ;

: _o2cmt-callback-long-auth-method
  ( view expected-u -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-METHOD@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    525 ;

: _o2cmt-callback-long-auth-alg
  ( view expected-u -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-SIGNING-ALG@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    535 ;

: _o2cmt-callback-long-jwks-uri
  ( view expected-u -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    545 ;

: _o2cmt-callback-long-grant  ( view expected-u -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    0 SWAP OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    606 ;

: _o2cmt-callback-grant-pair  ( view expected-total -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    DUP OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    2 = _o2cmt-assert
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP 2048 = _o2cmt-assert
    97 _o2cmt-filled? _o2cmt-assert
    1 SWAP OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    DUP R> 2048 - = _o2cmt-assert
    98 _o2cmt-filled? _o2cmt-assert
    616 ;

: _o2cmt-callback-grant-count  ( view expected -- callback-status )
    1 _o2cmt-callback-count +!
    >R
    DUP _o2cmt-saved-view !
    OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    R> = _o2cmt-assert
    707 ;

: _o2cmt-callback-name-capacity  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    _O2CMT-CONTEXT = _o2cmt-assert
    OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" https://client.example/client.json"
    COMPARE 0= _o2cmt-assert
    717 ;

: _o2cmt-callback-extension-response
  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    DROP
    DUP _o2cmt-saved-view !
    DUP OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    OAUTH2-CLIENT-METADATA-P-CLIENT-ID
    OAUTH2-CLIENT-METADATA-P-RESPONSE-TYPES OR
    = _o2cmt-assert
    DUP OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE-COUNT@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    1 = _o2cmt-assert
    0 OVER OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE@
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    S" extension_response" COMPARE 0= _o2cmt-assert
    DROP
    313 ;

: _o2cmt-callback-corrupt-entry  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    DROP
    DUP _o2cmt-saved-view !
    0 OVER _O2CMV-GRANT-ENTRY
    OAUTH2-CLIENT-METADATA-GRANT-TYPE-BYTES 1+
    SWAP _O2CME-OFFSET + !
    S" authorization_code" 2 PICK
    OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE?
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    0= _o2cmt-assert
    DROP
    808 ;

: _o2cmt-callback-never  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    2DROP
    0 _o2cmt-assert
    0 ;

: _o2cmt-callback-throw  ( view context -- callback-status )
    1 _o2cmt-callback-count +!
    DROP DUP _o2cmt-saved-view ! DROP
    -733 THROW ;

: _o2cmt-callback-extra  ( view context -- status extra )
    1 _o2cmt-callback-count +!
    DROP DUP _o2cmt-saved-view ! DROP
    909 910 ;

: _o2cmt-callback-missing  ( view context -- )
    1 _o2cmt-callback-count +!
    DROP DUP _o2cmt-saved-view ! DROP ;

: _o2cmt-callback-overconsume
  ( caller-cell view context -- status extra )
    1 _o2cmt-callback-count +!
    2DROP DROP
    911 912 ;

: _o2cmt-operation-throw
  ( source source-u callback context workspace -- cb-status status )
    -744 THROW ;

: _o2cmt-expect-success  ( callback context expected-callback -- )
    >R
    0 _o2cmt-callback-count !
    _o2cmt-snapshot
    _o2cmt-fill-work
    _o2cmt-call
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    R> = _o2cmt-assert
    _o2cmt-callback-count @ 1 = _o2cmt-assert
    _o2cmt-source-unchanged? _o2cmt-assert
    _o2cmt-work-zero? _o2cmt-assert
    _o2cmt-saved-view-invalid ;

: _o2cmt-expect-rejection  ( expected-status -- )
    >R
    0 _o2cmt-callback-count !
    _o2cmt-snapshot
    _o2cmt-fill-work
    ['] _o2cmt-callback-never 0 _o2cmt-call
    R> _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-callback-count @ 0= _o2cmt-assert
    _o2cmt-source-unchanged? _o2cmt-assert
    _o2cmt-work-zero? _o2cmt-assert ;

: _o2cmt-expect-success-focused
  ( callback context expected-callback -- )
    >R
    0 _o2cmt-callback-count !
    _o2cmt-call
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    R> = _o2cmt-assert
    _o2cmt-callback-count @ 1 = _o2cmt-assert ;

: _o2cmt-expect-rejection-focused  ( expected-status -- )
    >R
    0 _o2cmt-callback-count !
    ['] _o2cmt-callback-never 0 _o2cmt-call
    R> _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-callback-count @ 0= _o2cmt-assert ;

: _o2cmt-test-statuses  ( -- )
    OAUTH2-CLIENT-METADATA-S-OK
    OAUTH2-CLIENT-METADATA-STATUS-VALID? _o2cmt-assert
    OAUTH2-CLIENT-METADATA-S-PLATFORM
    OAUTH2-CLIENT-METADATA-STATUS-VALID? _o2cmt-assert
    -1 OAUTH2-CLIENT-METADATA-STATUS-VALID? 0= _o2cmt-assert
    OAUTH2-CLIENT-METADATA-S-PLATFORM 1+
    OAUTH2-CLIENT-METADATA-STATUS-VALID? 0= _o2cmt-assert
    OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES 5120 =
    _o2cmt-assert
    OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE 53256 =
    _o2cmt-assert
    _o2cmt-stack ;

: _o2cmt-test-success-and-lifetime  ( -- )
    _o2cmt-build-minimal
    ['] _o2cmt-callback-minimal _O2CMT-CONTEXT 101
    _o2cmt-expect-success

    _o2cmt-build-full
    ['] _o2cmt-callback-full 0 202
    _o2cmt-expect-success

    _o2cmt-build-policy-neutral
    ['] _o2cmt-callback-policy-neutral 0 303
    _o2cmt-expect-success
    _o2cmt-stack ;

: _o2cmt-test-arrays-and-presence  ( -- )
    _o2cmt-build-duplicate-grant
    OAUTH2-CLIENT-METADATA-S-DUPLICATE
    _o2cmt-expect-rejection

    S" response_types" S" extension_response"
    _o2cmt-build-extra-array-one
    ['] _o2cmt-callback-extension-response 0 313
    _o2cmt-expect-success

    _o2cmt-build-full
    ['] _o2cmt-callback-corrupt-entry 0 808
    _o2cmt-expect-success
    _o2cmt-stack ;

: _o2cmt-test-errors-and-json  ( -- )
    _o2cmt-build-missing
    OAUTH2-CLIENT-METADATA-S-MISSING _o2cmt-expect-rejection
    S" " _o2cmt-build-client-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" 7" _o2cmt-build-client-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection

    S" application_type" S" " _o2cmt-build-extra-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" application_type" S" 7" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" grant_types" S" {}" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" response_types" S" 7" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" redirect_uris" S" false" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" grant_types" S" [1]" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" redirect_uris" S" " _o2cmt-build-extra-array-one
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection

    S" scope" S" 7" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" scope" S" atproto  profile" _o2cmt-build-extra-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" token_endpoint_auth_method" S" 7"
    _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" token_endpoint_auth_signing_alg" S" false"
    _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" dpop_bound_access_tokens" S" 1"
    _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" jwks" S" []" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection
    S" jwks_uri" S" 7" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-TYPE _o2cmt-expect-rejection

    S" token_endpoint_auth_method" S" client_secret_post"
    _o2cmt-build-extra-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" token_endpoint_auth_method" S" client_secret_basic"
    _o2cmt-build-extra-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" token_endpoint_auth_method" S" client_secret_jwt"
    _o2cmt-build-extra-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    _o2cmt-build-escaped-secret-method
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" token_endpoint_auth_signing_alg" S" none"
    _o2cmt-build-extra-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" client_secret" S" forbidden" _o2cmt-build-extra-string
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    S" client_secret_expires_at" S" 0" _o2cmt-build-extra-raw
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection
    _o2cmt-build-both-key-sources
    OAUTH2-CLIENT-METADATA-S-VALUE _o2cmt-expect-rejection

    _o2cmt-build-duplicate-client-id
    OAUTH2-CLIENT-METADATA-S-DUPLICATE
    _o2cmt-expect-rejection
    _o2cmt-build-nested-jwks-duplicate
    OAUTH2-CLIENT-METADATA-S-DUPLICATE
    _o2cmt-expect-rejection
    _o2cmt-build-malformed
    OAUTH2-CLIENT-METADATA-S-JSON _o2cmt-expect-rejection
    _o2cmt-build-invalid-utf8
    OAUTH2-CLIENT-METADATA-S-JSON _o2cmt-expect-rejection
    _o2cmt-build-too-deep
    OAUTH2-CLIENT-METADATA-S-JSON _o2cmt-expect-rejection
    _o2cmt-stack ;

: _o2cmt-test-capacities  ( -- )
    OAUTH2-CLIENT-METADATA-CLIENT-ID-CAPACITY
    DUP _o2cmt-build-long-client
    ['] _o2cmt-callback-long-client SWAP 404
    _o2cmt-expect-success
    OAUTH2-CLIENT-METADATA-CLIENT-ID-CAPACITY 1+
    _o2cmt-build-long-client
    OAUTH2-CLIENT-METADATA-S-CAPACITY _o2cmt-expect-rejection

    OAUTH2-CLIENT-METADATA-APPLICATION-TYPE-CAPACITY
    DUP _o2cmt-build-long-application
    ['] _o2cmt-callback-long-application SWAP 505
    _o2cmt-expect-success-focused
    OAUTH2-CLIENT-METADATA-APPLICATION-TYPE-CAPACITY 1+
    _o2cmt-build-long-application
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    OAUTH2-CLIENT-METADATA-SCOPE-CAPACITY
    S" scope" 2 PICK _o2cmt-build-long-extra
    ['] _o2cmt-callback-long-scope SWAP 515
    _o2cmt-expect-success-focused
    S" scope" OAUTH2-CLIENT-METADATA-SCOPE-CAPACITY 1+
    _o2cmt-build-long-extra
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    OAUTH2-CLIENT-METADATA-TOKEN-AUTH-METHOD-CAPACITY
    S" token_endpoint_auth_method" 2 PICK
    _o2cmt-build-long-extra
    ['] _o2cmt-callback-long-auth-method SWAP 525
    _o2cmt-expect-success-focused
    S" token_endpoint_auth_method"
    OAUTH2-CLIENT-METADATA-TOKEN-AUTH-METHOD-CAPACITY 1+
    _o2cmt-build-long-extra
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    OAUTH2-CLIENT-METADATA-TOKEN-AUTH-SIGNING-ALG-CAPACITY
    S" token_endpoint_auth_signing_alg" 2 PICK
    _o2cmt-build-long-extra
    ['] _o2cmt-callback-long-auth-alg SWAP 535
    _o2cmt-expect-success-focused
    S" token_endpoint_auth_signing_alg"
    OAUTH2-CLIENT-METADATA-TOKEN-AUTH-SIGNING-ALG-CAPACITY 1+
    _o2cmt-build-long-extra
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    OAUTH2-CLIENT-METADATA-JWKS-URI-CAPACITY
    S" jwks_uri" 2 PICK _o2cmt-build-long-extra
    ['] _o2cmt-callback-long-jwks-uri SWAP 545
    _o2cmt-expect-success-focused
    S" jwks_uri" OAUTH2-CLIENT-METADATA-JWKS-URI-CAPACITY 1+
    _o2cmt-build-long-extra
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    OAUTH2-CLIENT-METADATA-GRANT-TYPE-BYTES
    DUP _o2cmt-build-long-grant
    ['] _o2cmt-callback-long-grant SWAP 606
    _o2cmt-expect-success-focused
    OAUTH2-CLIENT-METADATA-GRANT-TYPE-BYTES 1+
    _o2cmt-build-long-grant
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    OAUTH2-CLIENT-METADATA-GRANT-TYPE-BYTES
    DUP _o2cmt-build-grant-pair-total
    ['] _o2cmt-callback-grant-pair SWAP 616
    _o2cmt-expect-success-focused
    OAUTH2-CLIENT-METADATA-GRANT-TYPE-BYTES 1+
    _o2cmt-build-grant-pair-total
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    OAUTH2-CLIENT-METADATA-MAX-GRANT-TYPES
    DUP _o2cmt-build-grant-count
    ['] _o2cmt-callback-grant-count SWAP 707
    _o2cmt-expect-success-focused
    OAUTH2-CLIENT-METADATA-MAX-GRANT-TYPES 1+
    _o2cmt-build-grant-count
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    _o2cmt-build-member-overflow
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused

    _o2cmt-build-name-capacity
    ['] _o2cmt-callback-name-capacity _O2CMT-CONTEXT 717
    _o2cmt-expect-success-focused
    _o2cmt-build-name-overflow
    OAUTH2-CLIENT-METADATA-S-CAPACITY
    _o2cmt-expect-rejection-focused
    _o2cmt-stack ;

: _o2cmt-test-callbacks  ( -- )
    _o2cmt-build-minimal
    0 _o2cmt-callback-count !
    _o2cmt-snapshot
    _o2cmt-fill-work
    ['] _o2cmt-callback-throw 0 _o2cmt-call
    OAUTH2-CLIENT-METADATA-S-CALLBACK _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-callback-count @ 1 = _o2cmt-assert
    _o2cmt-source-unchanged? _o2cmt-assert
    _o2cmt-work-zero? _o2cmt-assert
    _o2cmt-saved-view-invalid

    _o2cmt-build-minimal
    0 _o2cmt-callback-count !
    _o2cmt-snapshot
    _o2cmt-fill-work
    _O2CMT-STACK-SENTINEL
    ['] _o2cmt-callback-overconsume 0 _o2cmt-call
    OAUTH2-CLIENT-METADATA-S-CALLBACK _o2cmt-status
    0= _o2cmt-assert
    _O2CMT-STACK-SENTINEL = _o2cmt-assert
    _o2cmt-callback-count @ 1 = _o2cmt-assert
    _o2cmt-source-unchanged? _o2cmt-assert
    _o2cmt-work-zero? _o2cmt-assert

    _o2cmt-build-minimal
    0 _o2cmt-callback-count !
    _o2cmt-snapshot
    _o2cmt-fill-work
    ['] _o2cmt-callback-extra 0 _o2cmt-call
    OAUTH2-CLIENT-METADATA-S-CALLBACK _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-callback-count @ 1 = _o2cmt-assert
    _o2cmt-source-unchanged? _o2cmt-assert
    _o2cmt-work-zero? _o2cmt-assert
    _o2cmt-saved-view-invalid

    _o2cmt-build-minimal
    0 _o2cmt-callback-count !
    _o2cmt-snapshot
    _o2cmt-fill-work
    ['] _o2cmt-callback-missing 0 _o2cmt-call
    OAUTH2-CLIENT-METADATA-S-CALLBACK _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-callback-count @ 1 = _o2cmt-assert
    _o2cmt-source-unchanged? _o2cmt-assert
    _o2cmt-work-zero? _o2cmt-assert
    _o2cmt-saved-view-invalid

    _o2cmt-build-minimal
    0 _o2cmt-callback-count !
    _o2cmt-snapshot
    _o2cmt-fill-work
    _o2cmt-input _o2cmt-input-u @
    ['] _o2cmt-callback-never 0 _o2cmt-work
    ['] _o2cmt-operation-throw _O2CM-WITH-CALL
    OAUTH2-CLIENT-METADATA-S-INTERNAL _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-callback-count @ 0= _o2cmt-assert
    _o2cmt-source-unchanged? _o2cmt-assert
    _o2cmt-work-zero? _o2cmt-assert
    _o2cmt-stack ;

: _o2cmt-test-preflight-and-clear  ( -- )
    _o2cmt-build-minimal
    0 _o2cmt-callback-count !

    _o2cmt-fill-work
    _o2cmt-work _o2cmt-input-u @
    ['] _o2cmt-callback-never 0 _o2cmt-work
    OAUTH2-CLIENT-METADATA-WITH
    OAUTH2-CLIENT-METADATA-S-ALIAS _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-work-filled? _o2cmt-assert

    _o2cmt-fill-all-work
    _o2cmt-input _o2cmt-input-u @
    ['] _o2cmt-callback-never 0 _o2cmt-work 1+
    OAUTH2-CLIENT-METADATA-WITH
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-work-all-filled? _o2cmt-assert

    _o2cmt-fill-work
    _o2cmt-input -1
    ['] _o2cmt-callback-never 0 _o2cmt-work
    OAUTH2-CLIENT-METADATA-WITH
    OAUTH2-CLIENT-METADATA-S-RANGE _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-work-filled? _o2cmt-assert

    _o2cmt-fill-work
    _o2cmt-input 0
    ['] _o2cmt-callback-never 0 _o2cmt-work
    OAUTH2-CLIENT-METADATA-WITH
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-work-filled? _o2cmt-assert

    _o2cmt-fill-work
    _o2cmt-input OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES 1+
    ['] _o2cmt-callback-never 0 _o2cmt-work
    OAUTH2-CLIENT-METADATA-WITH
    OAUTH2-CLIENT-METADATA-S-CAPACITY _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-work-filled? _o2cmt-assert

    _o2cmt-fill-work
    _o2cmt-input _o2cmt-input-u @
    0 0 _o2cmt-work OAUTH2-CLIENT-METADATA-WITH
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    0= _o2cmt-assert
    _o2cmt-work-filled? _o2cmt-assert
    _o2cmt-callback-count @ 0= _o2cmt-assert

    _o2cmt-fill-work
    _o2cmt-work OAUTH2-CLIENT-METADATA-WORKSPACE-CLEAR
    OAUTH2-CLIENT-METADATA-S-OK _o2cmt-status
    _o2cmt-work-zero? _o2cmt-assert

    _o2cmt-fill-all-work
    _o2cmt-work 1+ OAUTH2-CLIENT-METADATA-WORKSPACE-CLEAR
    OAUTH2-CLIENT-METADATA-S-INVALID _o2cmt-status
    _o2cmt-work-all-filled? _o2cmt-assert
    _o2cmt-stack ;

: _O2CMT-RUN  ( -- )
    0 _o2cmt-checks !
    0 _o2cmt-fails !
    0 _o2cmt-saved-view !
    DEPTH _o2cmt-depth !
    _o2cmt-test-statuses
    ." OAUTH2 CLIENT METADATA GROUP STATUSES" CR TX-FLUSH
    _o2cmt-test-success-and-lifetime
    ." OAUTH2 CLIENT METADATA GROUP SUCCESS" CR TX-FLUSH
    _o2cmt-test-arrays-and-presence
    ." OAUTH2 CLIENT METADATA GROUP ARRAYS" CR TX-FLUSH
    _o2cmt-test-errors-and-json
    ." OAUTH2 CLIENT METADATA GROUP ERRORS" CR TX-FLUSH
    _o2cmt-test-capacities
    ." OAUTH2 CLIENT METADATA GROUP CAPACITIES" CR TX-FLUSH
    _o2cmt-test-callbacks
    ." OAUTH2 CLIENT METADATA GROUP CALLBACKS" CR TX-FLUSH
    _o2cmt-test-preflight-and-clear
    ." OAUTH2 CLIENT METADATA GROUP PREFLIGHT" CR TX-FLUSH
    _o2cmt-stack
    _o2cmt-fails @ IF
        ." OAUTH2 CLIENT METADATA FAIL " _o2cmt-fails @ . CR
    ELSE
        ." OAUTH2 CLIENT METADATA PASS " _o2cmt-checks @ . CR
    THEN
    TX-FLUSH ;
