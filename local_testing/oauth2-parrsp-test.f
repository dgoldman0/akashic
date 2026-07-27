\ Focused generic OAuth 2.0 PAR success-response callback contracts.
\ This short guest filename remains within the MP64FS component limit.

PROVIDED akashic-o2pr-contracts

VARIABLE _o2prt-checks
VARIABLE _o2prt-fails
VARIABLE _o2prt-depth
VARIABLE _o2prt-input-u
VARIABLE _o2prt-copy-u
VARIABLE _o2prt-callback-count
VARIABLE _o2prt-saved-view

OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY 512 +
CONSTANT _O2PRT-INPUT-SIZE

CREATE _o2prt-input _O2PRT-INPUT-SIZE ALLOT
\ Seven leading bytes cover worst-case alignment adjustment.  The trailing
\ cell lets the intentional +1 preflight advertise the complete workspace
\ span without touching an adjacent dictionary object.
CREATE _o2prt-work-storage
    OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE 15 + ALLOT

: _o2prt-work  ( -- address )
    _o2prt-work-storage 7 + -8 AND ;

0x123456 CONSTANT _O2PRT-CONTEXT

: _o2prt-assert  ( flag -- )
    1 _o2prt-checks +!
    0= IF
        1 _o2prt-fails +!
        ." OAUTH2 PAR RESPONSE ASSERT " _o2prt-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2prt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 PAR RESPONSE STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2prt-assert ;

: _o2prt-stack  ( -- )
    DEPTH _o2prt-depth @ = _o2prt-assert ;

: _o2prt-filled?  ( address length byte -- flag )
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

: _o2prt-zero?  ( address length -- flag )
    0 _o2prt-filled? ;

: _o2prt-work-zero?  ( -- flag )
    _o2prt-work OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE
    _o2prt-zero? ;

: _o2prt-work-filled?  ( -- flag )
    _o2prt-work OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE
    0xC3 _o2prt-filled? ;

: _o2prt-work-all-filled?  ( -- flag )
    _o2prt-work OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE 8 +
    0xC3 _o2prt-filled? ;

: _o2prt-fill-work  ( -- )
    _o2prt-work OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE
    0xC3 FILL ;

: _o2prt-fill-all-work  ( -- )
    _o2prt-work OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE 8 +
    0xC3 FILL ;

: _o2prt-reset  ( -- )
    0 _o2prt-input-u ! ;

: _o2prt-char  ( byte -- )
    _o2prt-input _o2prt-input-u @ + C!
    1 _o2prt-input-u +! ;

: _o2prt-text  ( address length -- )
    DUP _o2prt-copy-u !
    _o2prt-input _o2prt-input-u @ + SWAP MOVE
    _o2prt-copy-u @ _o2prt-input-u +! ;

: _o2prt-repeat-char  ( byte count -- )
    DUP _o2prt-copy-u ! >R
    _o2prt-input _o2prt-input-u @ + SWAP
    R> SWAP FILL
    _o2prt-copy-u @ _o2prt-input-u +! ;

: _o2prt-quote     ( -- ) 34 _o2prt-char ;
: _o2prt-slash     ( -- ) 92 _o2prt-char ;
: _o2prt-comma     ( -- ) 44 _o2prt-char ;
: _o2prt-colon     ( -- ) 58 _o2prt-char ;
: _o2prt-lbrace    ( -- ) 123 _o2prt-char ;
: _o2prt-rbrace    ( -- ) 125 _o2prt-char ;
: _o2prt-lbracket  ( -- ) 91 _o2prt-char ;
: _o2prt-rbracket  ( -- ) 93 _o2prt-char ;

: _o2prt-key  ( address length -- )
    _o2prt-quote _o2prt-text _o2prt-quote _o2prt-colon ;

: _o2prt-string  ( address length -- )
    _o2prt-quote _o2prt-text _o2prt-quote ;

: _o2prt-request-uri  ( -- )
    S" request_uri" _o2prt-key
    _o2prt-quote
    S" urn:ietf:params:oauth:request_uri:abc" _o2prt-text
    _o2prt-slash S" u002D" _o2prt-text
    S" 123" _o2prt-text
    _o2prt-quote ;

: _o2prt-expires  ( -- )
    S" expires_in" _o2prt-key S" 600" _o2prt-text ;

: _o2prt-build-minimal  ( -- )
    _o2prt-reset _o2prt-lbrace
    _o2prt-request-uri _o2prt-comma _o2prt-expires
    _o2prt-rbrace ;

: _o2prt-build-order-and-unknown  ( -- )
    _o2prt-reset _o2prt-lbrace
    S" expires_in" _o2prt-key S" 120" _o2prt-text
    _o2prt-comma
    S" extension" _o2prt-key _o2prt-lbrace
    S" nested" _o2prt-key _o2prt-lbracket
    S" true" _o2prt-text _o2prt-comma _o2prt-lbrace
    S" x" _o2prt-key S" null" _o2prt-text
    _o2prt-rbrace _o2prt-rbracket _o2prt-rbrace
    _o2prt-comma
    S" request_uri" _o2prt-key
    S" https://as.example/par?slot=1#ok" _o2prt-string
    _o2prt-rbrace ;

: _o2prt-build-vschar-boundaries  ( -- )
    _o2prt-reset _o2prt-lbrace
    S" request_uri" _o2prt-key S"  ~" _o2prt-string
    _o2prt-comma S" expires_in" _o2prt-key S" 1" _o2prt-text
    _o2prt-rbrace ;

: _o2prt-build-long-request-uri  ( decoded-u -- )
    _o2prt-reset _o2prt-lbrace
    S" request_uri" _o2prt-key _o2prt-quote
    117 SWAP _o2prt-repeat-char
    _o2prt-quote _o2prt-comma
    S" expires_in" _o2prt-key S" 1" _o2prt-text
    _o2prt-rbrace ;

: _o2prt-build-request-uri-value  ( address length -- )
    _o2prt-reset _o2prt-lbrace
    S" request_uri" _o2prt-key _o2prt-string
    _o2prt-comma _o2prt-expires
    _o2prt-rbrace ;

: _o2prt-build-request-uri-control  ( -- )
    _o2prt-reset _o2prt-lbrace
    S" request_uri" _o2prt-key _o2prt-quote
    S" urn:example:" _o2prt-text
    _o2prt-slash S" u000A" _o2prt-text
    _o2prt-quote _o2prt-comma _o2prt-expires
    _o2prt-rbrace ;

: _o2prt-build-request-uri-nonascii  ( -- )
    _o2prt-reset _o2prt-lbrace
    S" request_uri" _o2prt-key _o2prt-quote
    S" urn:example:" _o2prt-text
    _o2prt-slash S" u00E9" _o2prt-text
    _o2prt-quote _o2prt-comma _o2prt-expires
    _o2prt-rbrace ;

: _o2prt-build-expires-value  ( address length -- )
    _o2prt-reset _o2prt-lbrace
    _o2prt-request-uri _o2prt-comma
    S" expires_in" _o2prt-key _o2prt-text
    _o2prt-rbrace ;

: _o2prt-build-expires-string  ( -- )
    _o2prt-reset _o2prt-lbrace
    _o2prt-request-uri _o2prt-comma
    S" expires_in" _o2prt-key S" 10" _o2prt-string
    _o2prt-rbrace ;

: _o2prt-build-missing-request-uri  ( -- )
    _o2prt-reset _o2prt-lbrace _o2prt-expires _o2prt-rbrace ;

: _o2prt-build-missing-expires  ( -- )
    _o2prt-reset _o2prt-lbrace _o2prt-request-uri _o2prt-rbrace ;

: _o2prt-build-empty-request-uri  ( -- )
    S" " _o2prt-build-request-uri-value ;

: _o2prt-build-wrong-request-uri-type  ( -- )
    _o2prt-reset _o2prt-lbrace
    S" request_uri" _o2prt-key S" 7" _o2prt-text
    _o2prt-comma _o2prt-expires _o2prt-rbrace ;

: _o2prt-build-duplicate  ( -- )
    _o2prt-reset _o2prt-lbrace
    _o2prt-request-uri _o2prt-comma
    _o2prt-quote S" request" _o2prt-text
    _o2prt-slash S" u005F" _o2prt-text
    S" uri" _o2prt-text _o2prt-quote _o2prt-colon
    S" urn:example:second" _o2prt-string
    _o2prt-comma _o2prt-expires _o2prt-rbrace ;

: _o2prt-build-duplicate-expires  ( -- )
    _o2prt-reset _o2prt-lbrace
    _o2prt-request-uri _o2prt-comma
    S" expires_in" _o2prt-key S" 1" _o2prt-text
    _o2prt-comma
    S" expires_in" _o2prt-key S" 2" _o2prt-text
    _o2prt-rbrace ;

: _o2prt-build-malformed  ( -- )
    _o2prt-reset _o2prt-lbrace
    _o2prt-request-uri _o2prt-comma _o2prt-expires ;

: _o2prt-build-trailing  ( -- )
    _o2prt-build-minimal S" trailing" _o2prt-text ;

: _o2prt-repeat-byte  ( byte count -- )
    BEGIN DUP WHILE
        OVER _o2prt-char
        1-
    REPEAT
    2DROP ;

: _o2prt-build-too-deep  ( -- )
    _o2prt-reset _o2prt-lbrace
    _o2prt-request-uri _o2prt-comma _o2prt-expires _o2prt-comma
    S" extension" _o2prt-key
    91 JOSE-JSON-MAX-DEPTH 1+ _o2prt-repeat-byte
    S" 0" _o2prt-text
    93 JOSE-JSON-MAX-DEPTH 1+ _o2prt-repeat-byte
    _o2prt-rbrace ;

: _o2prt-call  ( callback context -- callback-status response-status )
    >R >R
    _o2prt-input _o2prt-input-u @
    R> R> _o2prt-work
    OAUTH2-PAR-RESPONSE-WITH ;

: _o2prt-saved-view-invalid  ( -- )
    _o2prt-saved-view @ OAUTH2-PAR-VIEW-REQUEST-URI@
    OAUTH2-PAR-RESPONSE-S-INVALID _o2prt-status
    2DROP
    _o2prt-saved-view @ OAUTH2-PAR-VIEW-EXPIRES-IN@
    OAUTH2-PAR-RESPONSE-S-INVALID _o2prt-status
    DROP ;

: _o2prt-callback-minimal  ( view context -- callback-status )
    1 _o2prt-callback-count +!
    _O2PRT-CONTEXT = _o2prt-assert
    DUP _o2prt-saved-view !
    DUP OAUTH2-PAR-VIEW-REQUEST-URI@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    S" urn:ietf:params:oauth:request_uri:abc-123"
    COMPARE 0= _o2prt-assert
    OAUTH2-PAR-VIEW-EXPIRES-IN@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    600 = _o2prt-assert
    101 ;

: _o2prt-callback-order  ( view context -- callback-status )
    1 _o2prt-callback-count +!
    DROP
    DUP _o2prt-saved-view !
    DUP OAUTH2-PAR-VIEW-REQUEST-URI@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    S" https://as.example/par?slot=1#ok"
    COMPARE 0= _o2prt-assert
    OAUTH2-PAR-VIEW-EXPIRES-IN@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    120 = _o2prt-assert
    202 ;

: _o2prt-callback-vschar  ( view context -- callback-status )
    1 _o2prt-callback-count +!
    DROP
    DUP _o2prt-saved-view !
    DUP OAUTH2-PAR-VIEW-REQUEST-URI@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    S"  ~" COMPARE 0= _o2prt-assert
    OAUTH2-PAR-VIEW-EXPIRES-IN@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    1 = _o2prt-assert
    303 ;

: _o2prt-callback-long  ( view context -- callback-status )
    1 _o2prt-callback-count +!
    DROP
    DUP _o2prt-saved-view !
    OAUTH2-PAR-VIEW-REQUEST-URI@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    DUP OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY =
    _o2prt-assert
    117 _o2prt-filled? _o2prt-assert
    404 ;

: _o2prt-callback-expires  ( view expected -- callback-status )
    1 _o2prt-callback-count +!
    >R
    DUP _o2prt-saved-view !
    OAUTH2-PAR-VIEW-EXPIRES-IN@
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    R> = _o2prt-assert
    505 ;

: _o2prt-callback-never  ( view context -- callback-status )
    1 _o2prt-callback-count +!
    2DROP
    0 _o2prt-assert
    0 ;

: _o2prt-callback-throw  ( view context -- callback-status )
    1 _o2prt-callback-count +!
    DROP DUP _o2prt-saved-view ! DROP
    -733 THROW ;

: _o2prt-callback-extra  ( view context -- status extra )
    1 _o2prt-callback-count +!
    DROP DUP _o2prt-saved-view ! DROP
    606 607 ;

: _o2prt-operation-throw
  ( source source-u callback context workspace -- cb-status status )
    -744 THROW ;

: _o2prt-expect-success  ( callback context expected-callback -- )
    >R
    0 _o2prt-callback-count !
    _o2prt-fill-work
    _o2prt-call
    OAUTH2-PAR-RESPONSE-S-OK _o2prt-status
    R> = _o2prt-assert
    _o2prt-callback-count @ 1 = _o2prt-assert
    _o2prt-work-zero? _o2prt-assert
    _o2prt-saved-view-invalid ;

: _o2prt-expect-rejection  ( expected-status -- )
    >R
    0 _o2prt-callback-count !
    _o2prt-fill-work
    ['] _o2prt-callback-never 0 _o2prt-call
    R> _o2prt-status
    0= _o2prt-assert
    _o2prt-callback-count @ 0= _o2prt-assert
    _o2prt-work-zero? _o2prt-assert ;

: _o2prt-test-statuses  ( -- )
    OAUTH2-PAR-RESPONSE-S-OK
    OAUTH2-PAR-RESPONSE-STATUS-VALID? _o2prt-assert
    OAUTH2-PAR-RESPONSE-S-PLATFORM
    OAUTH2-PAR-RESPONSE-STATUS-VALID? _o2prt-assert
    -1 OAUTH2-PAR-RESPONSE-STATUS-VALID? 0= _o2prt-assert
    OAUTH2-PAR-RESPONSE-S-PLATFORM 1+
    OAUTH2-PAR-RESPONSE-STATUS-VALID? 0= _o2prt-assert
    OAUTH2-PAR-VIEW-MAX-EXPIRES-IN 2147483647 =
    _o2prt-assert
    _o2prt-stack ;

: _o2prt-test-success-and-lifetime  ( -- )
    _o2prt-build-minimal
    ['] _o2prt-callback-minimal _O2PRT-CONTEXT 101
    _o2prt-expect-success

    _o2prt-build-order-and-unknown
    ['] _o2prt-callback-order 0 202
    _o2prt-expect-success

    _o2prt-build-vschar-boundaries
    ['] _o2prt-callback-vschar 0 303
    _o2prt-expect-success

    OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY
    _o2prt-build-long-request-uri
    ['] _o2prt-callback-long 0 404
    _o2prt-expect-success
    _o2prt-stack ;

: _o2prt-test-errors-and-json  ( -- )
    _o2prt-build-missing-request-uri
    OAUTH2-PAR-RESPONSE-S-MISSING _o2prt-expect-rejection
    _o2prt-build-missing-expires
    OAUTH2-PAR-RESPONSE-S-MISSING _o2prt-expect-rejection
    _o2prt-build-wrong-request-uri-type
    OAUTH2-PAR-RESPONSE-S-TYPE _o2prt-expect-rejection
    _o2prt-build-expires-string
    OAUTH2-PAR-RESPONSE-S-TYPE _o2prt-expect-rejection
    _o2prt-build-duplicate
    OAUTH2-PAR-RESPONSE-S-DUPLICATE _o2prt-expect-rejection
    _o2prt-build-duplicate-expires
    OAUTH2-PAR-RESPONSE-S-DUPLICATE _o2prt-expect-rejection
    _o2prt-build-malformed
    OAUTH2-PAR-RESPONSE-S-JSON _o2prt-expect-rejection
    _o2prt-build-trailing
    OAUTH2-PAR-RESPONSE-S-JSON _o2prt-expect-rejection
    _o2prt-build-too-deep
    OAUTH2-PAR-RESPONSE-S-JSON _o2prt-expect-rejection
    OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY 1+
    _o2prt-build-long-request-uri
    OAUTH2-PAR-RESPONSE-S-CAPACITY _o2prt-expect-rejection
    _o2prt-stack ;

: _o2prt-test-value-grammars  ( -- )
    _o2prt-build-empty-request-uri
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection
    _o2prt-build-request-uri-control
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection
    _o2prt-build-request-uri-nonascii
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection

    S" 1" _o2prt-build-expires-value
    ['] _o2prt-callback-expires 1 505
    _o2prt-expect-success
    S" 2147483647" _o2prt-build-expires-value
    ['] _o2prt-callback-expires 2147483647 505
    _o2prt-expect-success

    S" 0" _o2prt-build-expires-value
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection
    S" -1" _o2prt-build-expires-value
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection
    S" 1.5" _o2prt-build-expires-value
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection
    S" 1e3" _o2prt-build-expires-value
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection
    S" 2147483648" _o2prt-build-expires-value
    OAUTH2-PAR-RESPONSE-S-VALUE _o2prt-expect-rejection
    _o2prt-stack ;

: _o2prt-test-callback-throw  ( -- )
    _o2prt-build-minimal
    0 _o2prt-callback-count !
    _o2prt-fill-work
    ['] _o2prt-callback-throw 0 _o2prt-call
    OAUTH2-PAR-RESPONSE-S-CALLBACK _o2prt-status
    0= _o2prt-assert
    _o2prt-callback-count @ 1 = _o2prt-assert
    _o2prt-work-zero? _o2prt-assert
    _o2prt-saved-view-invalid
    _o2prt-stack ;

: _o2prt-test-callback-stack  ( -- )
    _o2prt-build-minimal
    0 _o2prt-callback-count !
    _o2prt-fill-work
    ['] _o2prt-callback-extra 0 _o2prt-call
    OAUTH2-PAR-RESPONSE-S-CALLBACK _o2prt-status
    0= _o2prt-assert
    _o2prt-callback-count @ 1 = _o2prt-assert
    _o2prt-work-zero? _o2prt-assert
    _o2prt-saved-view-invalid
    _o2prt-stack ;

: _o2prt-test-internal-throw  ( -- )
    _o2prt-build-minimal
    _o2prt-fill-work
    _o2prt-input _o2prt-input-u @
    ['] _o2prt-callback-never 0 _o2prt-work
    ['] _o2prt-operation-throw _O2PR-WITH-CALL
    OAUTH2-PAR-RESPONSE-S-INTERNAL _o2prt-status
    0= _o2prt-assert
    _o2prt-work-zero? _o2prt-assert
    _o2prt-stack ;

: _o2prt-test-preflight  ( -- )
    _o2prt-build-minimal
    0 _o2prt-callback-count !

    \ Source/workspace aliasing rejects before any workspace byte changes.
    _o2prt-fill-work
    _o2prt-work _o2prt-input-u @
    ['] _o2prt-callback-never 0 _o2prt-work
    OAUTH2-PAR-RESPONSE-WITH
    OAUTH2-PAR-RESPONSE-S-ALIAS _o2prt-status
    0= _o2prt-assert
    _o2prt-callback-count @ 0= _o2prt-assert
    _o2prt-work-filled? _o2prt-assert

    \ A cell-misaligned workspace is invalid and remains byte-for-byte intact.
    _o2prt-fill-all-work
    _o2prt-input _o2prt-input-u @
    ['] _o2prt-callback-never 0 _o2prt-work 1+
    OAUTH2-PAR-RESPONSE-WITH
    OAUTH2-PAR-RESPONSE-S-INVALID _o2prt-status
    0= _o2prt-assert
    _o2prt-callback-count @ 0= _o2prt-assert
    _o2prt-work-all-filled? _o2prt-assert

    \ Malformed source geometry is rejected before workspace ownership.
    _o2prt-fill-work
    _o2prt-input -1
    ['] _o2prt-callback-never 0 _o2prt-work
    OAUTH2-PAR-RESPONSE-WITH
    OAUTH2-PAR-RESPONSE-S-RANGE _o2prt-status
    0= _o2prt-assert
    _o2prt-work-filled? _o2prt-assert

    \ Oversize advertised input is a preflight capacity rejection.
    _o2prt-fill-work
    _o2prt-input JOSE-JSON-MAX-DOCUMENT-BYTES 1+
    ['] _o2prt-callback-never 0 _o2prt-work
    OAUTH2-PAR-RESPONSE-WITH
    OAUTH2-PAR-RESPONSE-S-CAPACITY _o2prt-status
    0= _o2prt-assert
    _o2prt-work-filled? _o2prt-assert

    \ A null callback cannot claim or wipe an otherwise valid workspace.
    _o2prt-fill-work
    _o2prt-input _o2prt-input-u @
    0 0 _o2prt-work OAUTH2-PAR-RESPONSE-WITH
    OAUTH2-PAR-RESPONSE-S-INVALID _o2prt-status
    0= _o2prt-assert
    _o2prt-work-filled? _o2prt-assert
    _o2prt-callback-count @ 0= _o2prt-assert
    _o2prt-stack ;

: _O2PRT-RUN  ( -- )
    0 _o2prt-checks !
    0 _o2prt-fails !
    0 _o2prt-saved-view !
    DEPTH _o2prt-depth !
    _o2prt-test-statuses
    ." OAUTH2 PAR RESPONSE GROUP STATUSES" CR TX-FLUSH
    _o2prt-test-success-and-lifetime
    ." OAUTH2 PAR RESPONSE GROUP SUCCESS" CR TX-FLUSH
    _o2prt-test-errors-and-json
    ." OAUTH2 PAR RESPONSE GROUP ERRORS" CR TX-FLUSH
    _o2prt-test-value-grammars
    ." OAUTH2 PAR RESPONSE GROUP GRAMMARS" CR TX-FLUSH
    _o2prt-test-callback-throw
    _o2prt-test-callback-stack
    _o2prt-test-internal-throw
    ." OAUTH2 PAR RESPONSE GROUP CALLBACKS" CR TX-FLUSH
    _o2prt-test-preflight
    ." OAUTH2 PAR RESPONSE GROUP PREFLIGHT" CR TX-FLUSH
    _o2prt-stack
    _o2prt-fails @ IF
        ." OAUTH2 PAR RESPONSE FAIL " _o2prt-fails @ . CR
    ELSE
        ." OAUTH2 PAR RESPONSE PASS " _o2prt-checks @ . CR
    THEN
    TX-FLUSH ;
