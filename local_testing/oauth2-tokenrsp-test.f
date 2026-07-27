\ Focused generic OAuth 2 token-response callback contracts.
\ This short guest filename remains within the MP64FS component limit.

PROVIDED akashic-o2tr-contracts

VARIABLE _o2trt-checks
VARIABLE _o2trt-fails
VARIABLE _o2trt-depth
VARIABLE _o2trt-input-u
VARIABLE _o2trt-copy-u
VARIABLE _o2trt-callback-count
VARIABLE _o2trt-saved-view
VARIABLE _o2trt-expected-type-a
VARIABLE _o2trt-expected-type-u

OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY 256 +
CONSTANT _O2TRT-INPUT-SIZE

CREATE _o2trt-input _O2TRT-INPUT-SIZE ALLOT
CREATE _o2trt-work OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE ALLOT

0x123456 CONSTANT _O2TRT-CONTEXT

: _o2trt-assert  ( flag -- )
    1 _o2trt-checks +!
    0= IF
        1 _o2trt-fails +!
        ." OAUTH2 TOKEN RESPONSE ASSERT " _o2trt-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2trt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 TOKEN RESPONSE STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2trt-assert ;

: _o2trt-stack  ( -- )
    DEPTH _o2trt-depth @ = _o2trt-assert ;

: _o2trt-filled?  ( address length byte -- flag )
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

: _o2trt-zero?  ( address length -- flag )
    0 _o2trt-filled? ;

: _o2trt-work-zero?  ( -- flag )
    _o2trt-work OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE
    _o2trt-zero? ;

: _o2trt-work-filled?  ( -- flag )
    _o2trt-work OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE
    0xC3 _o2trt-filled? ;

: _o2trt-fill-work  ( -- )
    _o2trt-work OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE
    0xC3 FILL ;

: _o2trt-reset  ( -- )
    0 _o2trt-input-u ! ;

: _o2trt-char  ( byte -- )
    _o2trt-input _o2trt-input-u @ + C!
    1 _o2trt-input-u +! ;

: _o2trt-text  ( address length -- )
    DUP _o2trt-copy-u !
    _o2trt-input _o2trt-input-u @ + SWAP MOVE
    _o2trt-copy-u @ _o2trt-input-u +! ;

: _o2trt-repeat-char  ( byte count -- )
    DUP _o2trt-copy-u ! >R
    _o2trt-input _o2trt-input-u @ + SWAP
    R> SWAP FILL
    _o2trt-copy-u @ _o2trt-input-u +! ;

: _o2trt-quote   ( -- ) 34 _o2trt-char ;
: _o2trt-slash   ( -- ) 92 _o2trt-char ;
: _o2trt-comma   ( -- ) 44 _o2trt-char ;
: _o2trt-colon   ( -- ) 58 _o2trt-char ;
: _o2trt-lbrace  ( -- ) 123 _o2trt-char ;
: _o2trt-rbrace  ( -- ) 125 _o2trt-char ;

: _o2trt-key  ( address length -- )
    _o2trt-quote _o2trt-text _o2trt-quote _o2trt-colon ;

: _o2trt-string  ( address length -- )
    _o2trt-quote _o2trt-text _o2trt-quote ;

: _o2trt-access  ( -- )
    S" access_token" _o2trt-key
    _o2trt-quote
    S" access" _o2trt-text _o2trt-slash S" u002D" _o2trt-text
    S" opaque" _o2trt-text
    _o2trt-quote ;

: _o2trt-type  ( -- )
    S" token_type" _o2trt-key S" DPoP-1._x" _o2trt-string ;

: _o2trt-build-minimal  ( -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma _o2trt-type
    _o2trt-rbrace ;

: _o2trt-build-full  ( -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma
    _o2trt-type _o2trt-comma
    S" refresh_token" _o2trt-key S" refresh~1" _o2trt-string
    _o2trt-comma
    S" scope" _o2trt-key S" atproto transition:generic"
    _o2trt-string _o2trt-comma
    S" expires_in" _o2trt-key S" 3600" _o2trt-text
    _o2trt-comma
    S" extension" _o2trt-key _o2trt-lbrace
    S" nested" _o2trt-key S" [true,null]" _o2trt-text
    _o2trt-rbrace _o2trt-rbrace ;

: _o2trt-build-vschar-boundaries  ( -- )
    _o2trt-reset _o2trt-lbrace
    S" access_token" _o2trt-key S"  ~" _o2trt-string
    _o2trt-comma _o2trt-type _o2trt-comma
    S" refresh_token" _o2trt-key S"  ~" _o2trt-string
    _o2trt-rbrace ;

: _o2trt-build-long-access  ( decoded-u -- )
    _o2trt-reset _o2trt-lbrace
    S" access_token" _o2trt-key _o2trt-quote
    97 SWAP _o2trt-repeat-char
    _o2trt-quote _o2trt-comma _o2trt-type
    _o2trt-rbrace ;

: _o2trt-build-type-value  ( address length -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma
    S" token_type" _o2trt-key _o2trt-string
    _o2trt-rbrace ;

: _o2trt-build-type-escaped-control  ( -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma
    S" token_type" _o2trt-key _o2trt-quote
    _o2trt-slash S" u001F" _o2trt-text _o2trt-quote
    _o2trt-rbrace ;

: _o2trt-build-access-escaped-control  ( -- )
    _o2trt-reset _o2trt-lbrace
    S" access_token" _o2trt-key _o2trt-quote
    _o2trt-slash S" u001F" _o2trt-text _o2trt-quote
    _o2trt-comma _o2trt-type _o2trt-rbrace ;

: _o2trt-build-refresh-escaped-control  ( -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma _o2trt-type _o2trt-comma
    S" refresh_token" _o2trt-key _o2trt-quote
    _o2trt-slash S" u0009" _o2trt-text _o2trt-quote
    _o2trt-rbrace ;

: _o2trt-build-scope  ( address length -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma _o2trt-type _o2trt-comma
    S" scope" _o2trt-key _o2trt-string
    _o2trt-rbrace ;

: _o2trt-build-scope-backslash  ( -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma _o2trt-type _o2trt-comma
    S" scope" _o2trt-key _o2trt-quote
    S" read" _o2trt-text _o2trt-slash _o2trt-slash
    S" write" _o2trt-text _o2trt-quote
    _o2trt-rbrace ;

: _o2trt-build-expires  ( address length -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma _o2trt-type _o2trt-comma
    S" expires_in" _o2trt-key _o2trt-text
    _o2trt-rbrace ;

: _o2trt-build-expires-string  ( -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma _o2trt-type _o2trt-comma
    S" expires_in" _o2trt-key S" 10" _o2trt-string
    _o2trt-rbrace ;

: _o2trt-build-missing-access  ( -- )
    _o2trt-reset _o2trt-lbrace _o2trt-type _o2trt-rbrace ;

: _o2trt-build-missing-type  ( -- )
    _o2trt-reset _o2trt-lbrace _o2trt-access _o2trt-rbrace ;

: _o2trt-build-empty-access  ( -- )
    _o2trt-reset _o2trt-lbrace
    S" access_token" _o2trt-key S" " _o2trt-string
    _o2trt-comma _o2trt-type _o2trt-rbrace ;

: _o2trt-build-wrong-access-type  ( -- )
    _o2trt-reset _o2trt-lbrace
    S" access_token" _o2trt-key S" 7" _o2trt-text
    _o2trt-comma _o2trt-type _o2trt-rbrace ;

: _o2trt-build-duplicate  ( -- )
    _o2trt-reset _o2trt-lbrace
    _o2trt-access _o2trt-comma
    _o2trt-quote S" access" _o2trt-text
    _o2trt-slash S" u005F" _o2trt-text
    S" token" _o2trt-text _o2trt-quote _o2trt-colon
    S" second" _o2trt-string _o2trt-comma
    _o2trt-type _o2trt-rbrace ;

: _o2trt-build-malformed  ( -- )
    _o2trt-reset _o2trt-lbrace
    S" access_token" _o2trt-key S" a" _o2trt-string
    _o2trt-comma
    S" token_type" _o2trt-key S" DPoP" _o2trt-string ;

: _o2trt-call  ( callback context -- callback-status parse-status )
    >R >R
    _o2trt-input _o2trt-input-u @
    R> R> _o2trt-work
    OAUTH2-TOKEN-RESPONSE-WITH ;

: _o2trt-saved-view-invalid  ( -- )
    _o2trt-saved-view @ OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-INVALID _o2trt-status
    2DROP
    _o2trt-saved-view @ OAUTH2-TOKEN-VIEW-EXPIRES-IN@
    OAUTH2-TOKEN-RESPONSE-S-INVALID _o2trt-status
    DROP ;

: _o2trt-callback-minimal  ( view context -- callback-status )
    1 _o2trt-callback-count +!
    _O2TRT-CONTEXT = _o2trt-assert
    DUP _o2trt-saved-view !
    DUP OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S" access-opaque" COMPARE 0= _o2trt-assert
    DUP OAUTH2-TOKEN-VIEW-TOKEN-TYPE@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S" DPoP-1._x" COMPARE 0= _o2trt-assert
    DUP OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-MISSING _o2trt-status
    2DROP
    DUP OAUTH2-TOKEN-VIEW-SCOPE@
    OAUTH2-TOKEN-RESPONSE-S-MISSING _o2trt-status
    2DROP
    DUP OAUTH2-TOKEN-VIEW-EXPIRES-IN@
    OAUTH2-TOKEN-RESPONSE-S-MISSING _o2trt-status
    DROP
    DROP 101 ;

: _o2trt-callback-full  ( view context -- callback-status )
    1 _o2trt-callback-count +!
    _O2TRT-CONTEXT = _o2trt-assert
    DUP _o2trt-saved-view !
    DUP OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S" access-opaque" COMPARE 0= _o2trt-assert
    DUP OAUTH2-TOKEN-VIEW-TOKEN-TYPE@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S" DPoP-1._x" COMPARE 0= _o2trt-assert
    DUP OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S" refresh~1" COMPARE 0= _o2trt-assert
    DUP OAUTH2-TOKEN-VIEW-SCOPE@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S" atproto transition:generic" COMPARE 0= _o2trt-assert
    DUP OAUTH2-TOKEN-VIEW-EXPIRES-IN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    3600 = _o2trt-assert
    DROP 202 ;

: _o2trt-callback-vschar  ( view context -- callback-status )
    1 _o2trt-callback-count +!
    DROP
    DUP _o2trt-saved-view !
    DUP OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S"  ~" COMPARE 0= _o2trt-assert
    DUP OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    S"  ~" COMPARE 0= _o2trt-assert
    DROP 303 ;

: _o2trt-callback-expires  ( view expected -- callback-status )
    1 _o2trt-callback-count +!
    >R
    DUP _o2trt-saved-view !
    DUP OAUTH2-TOKEN-VIEW-EXPIRES-IN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    R> = _o2trt-assert
    DROP 404 ;

: _o2trt-callback-long  ( view context -- callback-status )
    1 _o2trt-callback-count +!
    DROP
    DUP _o2trt-saved-view !
    OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    DUP OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY = _o2trt-assert
    97 _o2trt-filled? _o2trt-assert
    505 ;

: _o2trt-callback-type  ( view context -- callback-status )
    1 _o2trt-callback-count +!
    DROP
    DUP _o2trt-saved-view !
    OAUTH2-TOKEN-VIEW-TOKEN-TYPE@
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    _o2trt-expected-type-a @ _o2trt-expected-type-u @
    COMPARE 0= _o2trt-assert
    606 ;

: _o2trt-callback-never  ( view context -- callback-status )
    1 _o2trt-callback-count +!
    2DROP
    0 _o2trt-assert
    0 ;

: _o2trt-callback-throw  ( view context -- callback-status )
    1 _o2trt-callback-count +!
    DROP DUP _o2trt-saved-view ! DROP
    -733 THROW ;

: _o2trt-callback-extra  ( view context -- status extra )
    1 _o2trt-callback-count +!
    DROP DUP _o2trt-saved-view ! DROP
    606 607 ;

: _o2trt-operation-throw
  ( source source-u callback context workspace -- callback-status parse-status )
    -744 THROW ;

: _o2trt-expect-success  ( callback context expected-callback -- )
    >R
    0 _o2trt-callback-count !
    _o2trt-fill-work
    _o2trt-call
    OAUTH2-TOKEN-RESPONSE-S-OK _o2trt-status
    R> = _o2trt-assert
    _o2trt-callback-count @ 1 = _o2trt-assert
    _o2trt-work-zero? _o2trt-assert
    _o2trt-saved-view-invalid ;

: _o2trt-expect-rejection  ( expected-status -- )
    >R
    0 _o2trt-callback-count !
    _o2trt-fill-work
    ['] _o2trt-callback-never 0 _o2trt-call
    R> _o2trt-status
    0= _o2trt-assert
    _o2trt-callback-count @ 0= _o2trt-assert
    _o2trt-work-zero? _o2trt-assert ;

: _o2trt-expect-type-success  ( address length -- )
    2DUP
    DUP _o2trt-expected-type-u !
    DROP _o2trt-expected-type-a !
    _o2trt-build-type-value
    ['] _o2trt-callback-type 0 606
    _o2trt-expect-success ;

: _o2trt-test-statuses  ( -- )
    OAUTH2-TOKEN-RESPONSE-S-OK
    OAUTH2-TOKEN-RESPONSE-STATUS-VALID? _o2trt-assert
    OAUTH2-TOKEN-RESPONSE-S-PLATFORM
    OAUTH2-TOKEN-RESPONSE-STATUS-VALID? _o2trt-assert
    -1 OAUTH2-TOKEN-RESPONSE-STATUS-VALID? 0= _o2trt-assert
    OAUTH2-TOKEN-RESPONSE-S-PLATFORM 1+
    OAUTH2-TOKEN-RESPONSE-STATUS-VALID? 0= _o2trt-assert
    _o2trt-stack ;

: _o2trt-test-success-and-lifetime  ( -- )
    _o2trt-build-minimal
    ['] _o2trt-callback-minimal _O2TRT-CONTEXT 101
    _o2trt-expect-success

    _o2trt-build-full
    ['] _o2trt-callback-full _O2TRT-CONTEXT 202
    _o2trt-expect-success

    _o2trt-build-vschar-boundaries
    ['] _o2trt-callback-vschar 0 303
    _o2trt-expect-success

    OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY _o2trt-build-long-access
    ['] _o2trt-callback-long 0 505
    _o2trt-expect-success
    _o2trt-stack ;

: _o2trt-test-errors-and-duplicates  ( -- )
    _o2trt-build-missing-access
    OAUTH2-TOKEN-RESPONSE-S-MISSING _o2trt-expect-rejection
    _o2trt-build-missing-type
    OAUTH2-TOKEN-RESPONSE-S-MISSING _o2trt-expect-rejection
    _o2trt-build-empty-access
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    _o2trt-build-wrong-access-type
    OAUTH2-TOKEN-RESPONSE-S-TYPE _o2trt-expect-rejection
    _o2trt-build-malformed
    OAUTH2-TOKEN-RESPONSE-S-JSON _o2trt-expect-rejection
    _o2trt-build-duplicate
    OAUTH2-TOKEN-RESPONSE-S-DUPLICATE _o2trt-expect-rejection
    OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY 1+
    _o2trt-build-long-access
    OAUTH2-TOKEN-RESPONSE-S-CAPACITY _o2trt-expect-rejection
    _o2trt-stack ;

: _o2trt-test-value-grammars  ( -- )
    _o2trt-build-access-escaped-control
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    _o2trt-build-refresh-escaped-control
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection

    S" urn:ietf:params:oauth:token-type:example"
    _o2trt-expect-type-success
    S" https://[2001:db8::1]/oauth?kind=proof#v1"
    _o2trt-expect-type-success
    S" ../token/%74ype?mode=dpop#v1"
    _o2trt-expect-type-success
    S" https://[v1.alpha:beta]/type"
    _o2trt-expect-type-success
    S" file:///token" _o2trt-expect-type-success

    S" D PoP" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    _o2trt-build-type-escaped-control
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" urn:example:%2G" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" 1bad:value" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" urn:x#one#two" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" https://[2001:::1]/x" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" https://example.com:nope/x" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" bad\\type" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" \u00E9" _o2trt-build-type-value
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection

    S" read  write" _o2trt-build-scope
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" read " _o2trt-build-scope
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    _o2trt-build-scope-backslash
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" " _o2trt-build-scope
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    _o2trt-stack ;

: _o2trt-test-expiry  ( -- )
    S" 0" _o2trt-build-expires
    ['] _o2trt-callback-expires 0 404 _o2trt-expect-success
    S" 2147483647" _o2trt-build-expires
    ['] _o2trt-callback-expires 2147483647 404
    _o2trt-expect-success

    _o2trt-build-expires-string
    OAUTH2-TOKEN-RESPONSE-S-TYPE _o2trt-expect-rejection
    S" -1" _o2trt-build-expires
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" 1.5" _o2trt-build-expires
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" 1e3" _o2trt-build-expires
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    S" 2147483648" _o2trt-build-expires
    OAUTH2-TOKEN-RESPONSE-S-VALUE _o2trt-expect-rejection
    _o2trt-stack ;

: _o2trt-test-callback-throw  ( -- )
    _o2trt-build-minimal
    0 _o2trt-callback-count !
    _o2trt-fill-work
    ['] _o2trt-callback-throw 0 _o2trt-call
    OAUTH2-TOKEN-RESPONSE-S-CALLBACK _o2trt-status
    0= _o2trt-assert
    _o2trt-callback-count @ 1 = _o2trt-assert
    _o2trt-work-zero? _o2trt-assert
    _o2trt-saved-view-invalid
    _o2trt-stack ;

: _o2trt-test-callback-stack  ( -- )
    _o2trt-build-minimal
    0 _o2trt-callback-count !
    _o2trt-fill-work
    ['] _o2trt-callback-extra 0 _o2trt-call
    OAUTH2-TOKEN-RESPONSE-S-CALLBACK _o2trt-status
    0= _o2trt-assert
    _o2trt-callback-count @ 1 = _o2trt-assert
    _o2trt-work-zero? _o2trt-assert
    _o2trt-saved-view-invalid
    _o2trt-stack ;

: _o2trt-test-internal-throw  ( -- )
    _o2trt-build-minimal
    _o2trt-fill-work
    _o2trt-input _o2trt-input-u @
    ['] _o2trt-callback-never 0 _o2trt-work
    ['] _o2trt-operation-throw _O2TR-WITH-CALL
    OAUTH2-TOKEN-RESPONSE-S-INTERNAL _o2trt-status
    0= _o2trt-assert
    _o2trt-work-zero? _o2trt-assert
    _o2trt-stack ;

: _o2trt-test-preflight-alias  ( -- )
    _o2trt-build-minimal
    0 _o2trt-callback-count !
    _o2trt-fill-work
    _o2trt-work _o2trt-input-u @
    ['] _o2trt-callback-never 0 _o2trt-work
    OAUTH2-TOKEN-RESPONSE-WITH
    OAUTH2-TOKEN-RESPONSE-S-ALIAS _o2trt-status
    0= _o2trt-assert
    _o2trt-callback-count @ 0= _o2trt-assert
    _o2trt-work-filled? _o2trt-assert

    _o2trt-fill-work
    _o2trt-input _o2trt-input-u @
    0 0 _o2trt-work OAUTH2-TOKEN-RESPONSE-WITH
    OAUTH2-TOKEN-RESPONSE-S-INVALID _o2trt-status
    0= _o2trt-assert
    _o2trt-work-filled? _o2trt-assert
    _o2trt-stack ;

: _O2TRT-RUN  ( -- )
    0 _o2trt-checks !
    0 _o2trt-fails !
    0 _o2trt-saved-view !
    DEPTH _o2trt-depth !
    _o2trt-test-statuses
    ." OAUTH2 TOKEN RESPONSE GROUP STATUSES" CR TX-FLUSH
    _o2trt-test-success-and-lifetime
    ." OAUTH2 TOKEN RESPONSE GROUP SUCCESS" CR TX-FLUSH
    _o2trt-test-errors-and-duplicates
    ." OAUTH2 TOKEN RESPONSE GROUP ERRORS" CR TX-FLUSH
    _o2trt-test-value-grammars
    ." OAUTH2 TOKEN RESPONSE GROUP GRAMMARS" CR TX-FLUSH
    _o2trt-test-expiry
    ." OAUTH2 TOKEN RESPONSE GROUP EXPIRY" CR TX-FLUSH
    _o2trt-test-callback-throw
    _o2trt-test-callback-stack
    _o2trt-test-internal-throw
    ." OAUTH2 TOKEN RESPONSE GROUP CALLBACKS" CR TX-FLUSH
    _o2trt-test-preflight-alias
    _o2trt-stack
    _o2trt-fails @ IF
        ." OAUTH2 TOKEN RESPONSE FAIL " _o2trt-fails @ . CR
    ELSE
        ." OAUTH2 TOKEN RESPONSE PASS " _o2trt-checks @ . CR
    THEN
    TX-FLUSH ;
