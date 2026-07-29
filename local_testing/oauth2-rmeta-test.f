\ Focused strict OAuth 2 protected-resource metadata contracts.

PROVIDED akashic-o2rm-contracts

VARIABLE _o2rmt-checks
VARIABLE _o2rmt-fails
VARIABLE _o2rmt-depth
VARIABLE _o2rmt-input-u
VARIABLE _o2rmt-copy-u

CREATE _o2rmt-input    8192 ALLOT
CREATE _o2rmt-result   OAUTH2-RESOURCE-METADATA-SIZE ALLOT
CREATE _o2rmt-work     OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE ALLOT

: _o2rmt-assert  ( flag -- )
    1 _o2rmt-checks +!
    0= IF
        1 _o2rmt-fails +!
        ." OAUTH2 RESOURCE METADATA ASSERT " _o2rmt-checks @ . CR
    THEN ;

: _o2rmt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 RESOURCE METADATA STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _o2rmt-assert ;

: _o2rmt-stack  ( -- )
    DEPTH _o2rmt-depth @ = _o2rmt-assert ;

: _o2rmt-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _o2rmt-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _o2rmt-work-zero?  ( -- flag )
    _o2rmt-work OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE
        _o2rmt-zero? ;

: _o2rmt-result-unchanged?  ( -- flag )
    _o2rmt-result OAUTH2-RESOURCE-METADATA-SIZE
        0xA5 _o2rmt-filled? ;

: _o2rmt-preflight-fill  ( -- )
    _o2rmt-result OAUTH2-RESOURCE-METADATA-SIZE 0xA5 FILL
    _o2rmt-work OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE
        0xC3 FILL ;

: _o2rmt-reset  ( -- ) 0 _o2rmt-input-u ! ;

: _o2rmt-char  ( byte -- )
    _o2rmt-input _o2rmt-input-u @ + C!
    1 _o2rmt-input-u +! ;

: _o2rmt-text  ( address length -- )
    DUP _o2rmt-copy-u !
    _o2rmt-input _o2rmt-input-u @ + SWAP MOVE
    _o2rmt-copy-u @ _o2rmt-input-u +! ;

: _o2rmt-quote     ( -- ) 34 _o2rmt-char ;
: _o2rmt-comma     ( -- ) 44 _o2rmt-char ;
: _o2rmt-colon     ( -- ) 58 _o2rmt-char ;
: _o2rmt-lbracket  ( -- ) 91 _o2rmt-char ;
: _o2rmt-rbracket  ( -- ) 93 _o2rmt-char ;
: _o2rmt-lbrace    ( -- ) 123 _o2rmt-char ;
: _o2rmt-rbrace    ( -- ) 125 _o2rmt-char ;

: _o2rmt-key  ( address length -- )
    _o2rmt-quote _o2rmt-text _o2rmt-quote _o2rmt-colon ;

: _o2rmt-string  ( address length -- )
    _o2rmt-quote _o2rmt-text _o2rmt-quote ;

: _o2rmt-resource  ( -- )
    S" resource" _o2rmt-key
    S" https://pds.example" _o2rmt-string ;

: _o2rmt-servers-two  ( -- )
    S" authorization_servers" _o2rmt-key
    _o2rmt-lbracket
    S" https://auth.example" _o2rmt-string _o2rmt-comma
    S" https://entry.example" _o2rmt-string
    _o2rmt-rbracket ;

: _o2rmt-build-full  ( -- )
    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma
    _o2rmt-servers-two _o2rmt-comma
    S" unknown" _o2rmt-key
    S" {" _o2rmt-text
    S" nested" _o2rmt-key
    S" [1,true,null]}" _o2rmt-text
    _o2rmt-rbrace ;

: _o2rmt-build-resource-only  ( -- )
    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource
    _o2rmt-rbrace ;

: _o2rmt-parse  ( -- status )
    _o2rmt-input _o2rmt-input-u @
    _o2rmt-result _o2rmt-work
    OAUTH2-RESOURCE-METADATA-PARSE ;

: _o2rmt-expect-failure  ( expected-status -- )
    >R
    _o2rmt-result OAUTH2-RESOURCE-METADATA-SIZE 0xA5 FILL
    _o2rmt-work OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE
        0xC3 FILL
    _o2rmt-parse R> _o2rmt-status
    _o2rmt-result-unchanged? _o2rmt-assert
    _o2rmt-work-zero? _o2rmt-assert ;

: _o2rmt-test-full  ( -- )
    _o2rmt-build-full
    _o2rmt-preflight-fill
    _o2rmt-parse OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
    _o2rmt-result OAUTH2-RESOURCE-METADATA-VALID?
        _o2rmt-assert
    _o2rmt-result OAUTH2-RESOURCE-METADATA-PRESENCE@
        OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
        OAUTH2-RESOURCE-METADATA-P-ALL = _o2rmt-assert
    _o2rmt-result OAUTH2-RESOURCE-METADATA-RESOURCE@
        OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
        S" https://pds.example" 2SWAP COMPARE 0= _o2rmt-assert
    _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER-COUNT@
        OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
        2 = _o2rmt-assert
    0 _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@
        OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
        S" https://auth.example" 2SWAP COMPARE 0= _o2rmt-assert
    1 _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@
        OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
        S" https://entry.example" 2SWAP COMPARE 0= _o2rmt-assert
    2 _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@
        OAUTH2-RESOURCE-METADATA-S-INVALID _o2rmt-status
        OR 0= _o2rmt-assert
    -1 _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@
        OAUTH2-RESOURCE-METADATA-S-INVALID _o2rmt-status
        OR 0= _o2rmt-assert
    _o2rmt-work-zero? _o2rmt-assert
    _o2rmt-stack ;

: _o2rmt-test-optional  ( -- )
    _o2rmt-build-resource-only
    _o2rmt-preflight-fill
    _o2rmt-parse OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
    _o2rmt-result OAUTH2-RESOURCE-METADATA-PRESENCE@
        OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
        OAUTH2-RESOURCE-METADATA-P-RESOURCE = _o2rmt-assert
    _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER-COUNT@
        OAUTH2-RESOURCE-METADATA-S-MISSING _o2rmt-status
        0= _o2rmt-assert
    0 _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@
        OAUTH2-RESOURCE-METADATA-S-MISSING _o2rmt-status
        OR 0= _o2rmt-assert
    _o2rmt-work-zero? _o2rmt-assert
    _o2rmt-stack ;

: _o2rmt-test-rejections  ( -- )
    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-servers-two _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-MISSING _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    S" resource" _o2rmt-key S" true" _o2rmt-text
    _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-TYPE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    S" resource" _o2rmt-key S" " _o2rmt-string
    _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-VALUE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma
    S" authorization_servers" _o2rmt-key S" true" _o2rmt-text
    _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-TYPE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma
    S" authorization_servers" _o2rmt-key
    _o2rmt-lbracket _o2rmt-rbracket
    _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-VALUE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma
    S" authorization_servers" _o2rmt-key
    _o2rmt-lbracket S" true" _o2rmt-text _o2rmt-rbracket
    _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-TYPE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma
    S" authorization_servers" _o2rmt-key
    _o2rmt-lbracket S" " _o2rmt-string _o2rmt-rbracket
    _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-VALUE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma
    S" authorization_servers" _o2rmt-key
    _o2rmt-lbracket
    S" https://auth.example" _o2rmt-string _o2rmt-comma
    S" https://auth.\u0065xample" _o2rmt-string
    _o2rmt-rbracket _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-DUPLICATE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma _o2rmt-resource
    _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-DUPLICATE _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    OAUTH2-RESOURCE-METADATA-S-JSON _o2rmt-expect-failure
    _o2rmt-stack ;

: _o2rmt-test-capacity  ( -- )
    _o2rmt-reset _o2rmt-lbrace
    S" resource" _o2rmt-key _o2rmt-quote
    OAUTH2-RESOURCE-METADATA-TEXT-CAPACITY 1+ 0 ?DO
        [CHAR] a _o2rmt-char
    LOOP
    _o2rmt-quote _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-CAPACITY _o2rmt-expect-failure

    _o2rmt-reset _o2rmt-lbrace
    _o2rmt-resource _o2rmt-comma
    S" authorization_servers" _o2rmt-key _o2rmt-lbracket
    OAUTH2-RESOURCE-METADATA-MAX-AUTHORIZATION-SERVERS 1+ 0 ?DO
        I IF _o2rmt-comma THEN
        _o2rmt-quote
        S" https://auth" _o2rmt-text
        [CHAR] A I + _o2rmt-char
        S" .example" _o2rmt-text
        _o2rmt-quote
    LOOP
    _o2rmt-rbracket _o2rmt-rbrace
    OAUTH2-RESOURCE-METADATA-S-CAPACITY _o2rmt-expect-failure
    _o2rmt-stack ;

: _o2rmt-test-corruption  ( -- )
    _o2rmt-build-full
    _o2rmt-preflight-fill
    _o2rmt-parse OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
    OAUTH2-RESOURCE-METADATA-MAX-AUTHORIZATION-SERVERS 1+
        _o2rmt-result _O2RM.AUTHORIZATION-SERVER-COUNT !
    _o2rmt-result OAUTH2-RESOURCE-METADATA-VALID? 0=
        _o2rmt-assert

    _o2rmt-build-full
    _o2rmt-parse OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
    1 _o2rmt-result _O2RM.AUTHORIZATION-SERVER-COUNT !
    OAUTH2-RESOURCE-METADATA-TEXT-CAPACITY 1+
        _o2rmt-result _O2RM.AUTHORIZATION-SERVER-BYTES-U !
    0 0 _o2rmt-result _O2RM-AUTHORIZATION-SERVER-ENTRY
        _O2RME-OFFSET + !
    OAUTH2-RESOURCE-METADATA-TEXT-CAPACITY 1+
        0 _o2rmt-result _O2RM-AUTHORIZATION-SERVER-ENTRY
        _O2RME-U + !
    _o2rmt-result OAUTH2-RESOURCE-METADATA-VALID? 0=
        _o2rmt-assert
    0 _o2rmt-result
        OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@
        OAUTH2-RESOURCE-METADATA-S-INVALID _o2rmt-status
        OR 0= _o2rmt-assert
    _o2rmt-stack ;

: _o2rmt-test-preflight  ( -- )
    _o2rmt-build-resource-only
    _o2rmt-preflight-fill
    _o2rmt-input _o2rmt-input-u @
    _o2rmt-work _o2rmt-work
    OAUTH2-RESOURCE-METADATA-PARSE
        OAUTH2-RESOURCE-METADATA-S-ALIAS _o2rmt-status
    _o2rmt-work OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE
        0xC3 _o2rmt-filled? _o2rmt-assert
    _o2rmt-result-unchanged? _o2rmt-assert

    _o2rmt-work OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE
        0xA5 FILL
    _o2rmt-work OAUTH2-RESOURCE-METADATA-WORKSPACE-CLEAR
        OAUTH2-RESOURCE-METADATA-S-OK _o2rmt-status
    _o2rmt-work-zero? _o2rmt-assert

    OAUTH2-RESOURCE-METADATA-S-PLATFORM
        OAUTH2-RESOURCE-METADATA-STATUS-VALID? _o2rmt-assert
    OAUTH2-RESOURCE-METADATA-S-PLATFORM 1+
        OAUTH2-RESOURCE-METADATA-STATUS-VALID? 0= _o2rmt-assert
    _o2rmt-stack ;

: _O2RMT-INIT  ( -- )
    0 _o2rmt-checks !
    0 _o2rmt-fails !
    DEPTH _o2rmt-depth ! ;

: _O2RMT-FINISH  ( -- )
    _o2rmt-stack
    _o2rmt-fails @ IF
        ." OAUTH2 RESOURCE METADATA FAIL checks/fails "
        _o2rmt-checks @ . _o2rmt-fails @ . CR
    ELSE
        ." OAUTH2 RESOURCE METADATA PASS "
        _o2rmt-checks @ . CR
    THEN ;

: _O2RMT-RUN  ( -- )
    _O2RMT-INIT
    ." OAUTH2 RESOURCE METADATA GROUP FULL" CR TX-FLUSH
    _o2rmt-test-full
    ." OAUTH2 RESOURCE METADATA GROUP OPTIONAL" CR TX-FLUSH
    _o2rmt-test-optional
    ." OAUTH2 RESOURCE METADATA GROUP REJECTIONS" CR TX-FLUSH
    _o2rmt-test-rejections
    ." OAUTH2 RESOURCE METADATA GROUP CAPACITY" CR TX-FLUSH
    _o2rmt-test-capacity
    ." OAUTH2 RESOURCE METADATA GROUP CORRUPTION" CR TX-FLUSH
    _o2rmt-test-corruption
    ." OAUTH2 RESOURCE METADATA GROUP PREFLIGHT" CR TX-FLUSH
    _o2rmt-test-preflight
    _O2RMT-FINISH ;
