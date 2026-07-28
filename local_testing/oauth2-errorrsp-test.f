\ Focused generic OAuth 2.0 error-response callback contracts.
\ This short guest filename remains within the MP64FS component limit.

PROVIDED akashic-o2er-contracts

VARIABLE _o2ert-checks
VARIABLE _o2ert-fails
VARIABLE _o2ert-depth
VARIABLE _o2ert-input-u
VARIABLE _o2ert-copy-u
VARIABLE _o2ert-callback-count
VARIABLE _o2ert-saved-view

OAUTH2-ERROR-VIEW-URI-CAPACITY 1024 +
CONSTANT _O2ERT-INPUT-SIZE

CREATE _o2ert-input _O2ERT-INPUT-SIZE ALLOT
\ Seven leading bytes cover worst-case alignment adjustment.  The trailing
\ cell lets the intentional +1 preflight advertise the complete workspace
\ span without touching an adjacent dictionary object.
CREATE _o2ert-work-storage
    OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE 15 + ALLOT

: _o2ert-work  ( -- address )
    _o2ert-work-storage 7 + -8 AND ;

0x123456 CONSTANT _O2ERT-CONTEXT
0x4F3245525354414B CONSTANT _O2ERT-STACK-SENTINEL

: _o2ert-assert  ( flag -- )
    1 _o2ert-checks +!
    0= IF
        1 _o2ert-fails +!
        ." OAUTH2 ERROR RESPONSE ASSERT " _o2ert-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2ert-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 ERROR RESPONSE STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2ert-assert ;

: _o2ert-stack  ( -- )
    DEPTH _o2ert-depth @ = _o2ert-assert ;

: _o2ert-filled?  ( address length byte -- flag )
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

: _o2ert-zero?  ( address length -- flag )
    0 _o2ert-filled? ;

: _o2ert-work-zero?  ( -- flag )
    _o2ert-work OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE
    _o2ert-zero? ;

: _o2ert-work-filled?  ( -- flag )
    _o2ert-work OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE
    0xC3 _o2ert-filled? ;

: _o2ert-work-all-filled?  ( -- flag )
    _o2ert-work OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE 8 +
    0xC3 _o2ert-filled? ;

: _o2ert-fill-work  ( -- )
    _o2ert-work OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE
    0xC3 FILL ;

: _o2ert-fill-all-work  ( -- )
    _o2ert-work OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE 8 +
    0xC3 FILL ;

: _o2ert-reset  ( -- )
    0 _o2ert-input-u ! ;

: _o2ert-char  ( byte -- )
    _o2ert-input _o2ert-input-u @ + C!
    1 _o2ert-input-u +! ;

: _o2ert-text  ( address length -- )
    DUP _o2ert-copy-u !
    _o2ert-input _o2ert-input-u @ + SWAP MOVE
    _o2ert-copy-u @ _o2ert-input-u +! ;

: _o2ert-repeat-char  ( byte count -- )
    DUP _o2ert-copy-u ! >R
    _o2ert-input _o2ert-input-u @ + SWAP
    R> SWAP FILL
    _o2ert-copy-u @ _o2ert-input-u +! ;

: _o2ert-quote     ( -- ) 34 _o2ert-char ;
: _o2ert-slash     ( -- ) 92 _o2ert-char ;
: _o2ert-comma     ( -- ) 44 _o2ert-char ;
: _o2ert-colon     ( -- ) 58 _o2ert-char ;
: _o2ert-lbrace    ( -- ) 123 _o2ert-char ;
: _o2ert-rbrace    ( -- ) 125 _o2ert-char ;
: _o2ert-lbracket  ( -- ) 91 _o2ert-char ;
: _o2ert-rbracket  ( -- ) 93 _o2ert-char ;

: _o2ert-key  ( address length -- )
    _o2ert-quote _o2ert-text _o2ert-quote _o2ert-colon ;

: _o2ert-string  ( address length -- )
    _o2ert-quote _o2ert-text _o2ert-quote ;

: _o2ert-error  ( -- )
    S" error" _o2ert-key
    _o2ert-quote
    S" invalid" _o2ert-text _o2ert-slash S" u005F" _o2ert-text
    S" grant" _o2ert-text
    _o2ert-quote ;

: _o2ert-build-minimal  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-rbrace ;

: _o2ert-build-full  ( -- )
    _o2ert-reset _o2ert-lbrace
    S" extension" _o2ert-key _o2ert-lbrace
    S" nested" _o2ert-key _o2ert-lbracket
    S" true" _o2ert-text _o2ert-comma
    S" null" _o2ert-text _o2ert-rbracket
    _o2ert-rbrace _o2ert-comma
    S" error_uri" _o2ert-key
    S" https://[2001:db8::1]:8443/errors/invalid%20grant?lang=en#details"
    _o2ert-string _o2ert-comma
    S" error_description" _o2ert-key
    _o2ert-quote S" Grant was" _o2ert-text
    _o2ert-slash S" u0020" _o2ert-text
    S" rejected." _o2ert-text _o2ert-quote
    _o2ert-comma _o2ert-error
    _o2ert-rbrace ;

: _o2ert-build-relative-uri  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_uri" _o2ert-key
    S" ../errors/invalid_request?source=as#detail" _o2ert-string
    _o2ert-rbrace ;

: _o2ert-build-error-value  ( address length -- )
    _o2ert-reset _o2ert-lbrace
    S" error" _o2ert-key _o2ert-string
    _o2ert-rbrace ;

: _o2ert-build-error-escaped  ( address length -- )
    _o2ert-reset _o2ert-lbrace
    S" error" _o2ert-key _o2ert-quote
    _o2ert-slash _o2ert-text _o2ert-quote
    _o2ert-rbrace ;

: _o2ert-build-description-value  ( address length -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_description" _o2ert-key _o2ert-string
    _o2ert-rbrace ;

: _o2ert-build-description-escaped  ( address length -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_description" _o2ert-key _o2ert-quote
    _o2ert-slash _o2ert-text _o2ert-quote
    _o2ert-rbrace ;

: _o2ert-build-uri-value  ( address length -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_uri" _o2ert-key _o2ert-string
    _o2ert-rbrace ;

: _o2ert-build-long-error  ( decoded-u -- )
    _o2ert-reset _o2ert-lbrace
    S" error" _o2ert-key _o2ert-quote
    101 SWAP _o2ert-repeat-char
    _o2ert-quote _o2ert-rbrace ;

: _o2ert-build-long-description  ( decoded-u -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_description" _o2ert-key _o2ert-quote
    100 SWAP _o2ert-repeat-char
    _o2ert-quote _o2ert-rbrace ;

: _o2ert-build-long-uri  ( decoded-u -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_uri" _o2ert-key _o2ert-quote
    S" urn:x:" _o2ert-text
    117 SWAP 6 - _o2ert-repeat-char
    _o2ert-quote _o2ert-rbrace ;

: _o2ert-build-missing-error  ( -- )
    _o2ert-reset _o2ert-lbrace
    S" error_description" _o2ert-key S" missing code" _o2ert-string
    _o2ert-rbrace ;

: _o2ert-build-wrong-error-type  ( -- )
    _o2ert-reset _o2ert-lbrace
    S" error" _o2ert-key S" 7" _o2ert-text
    _o2ert-rbrace ;

: _o2ert-build-wrong-description-type  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_description" _o2ert-key S" false" _o2ert-text
    _o2ert-rbrace ;

: _o2ert-build-wrong-uri-type  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" error_uri" _o2ert-key S" null" _o2ert-text
    _o2ert-rbrace ;

: _o2ert-build-duplicate-error  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    _o2ert-quote S" err" _o2ert-text
    _o2ert-slash S" u006F" _o2ert-text
    S" r" _o2ert-text _o2ert-quote _o2ert-colon
    S" second" _o2ert-string
    _o2ert-rbrace ;

: _o2ert-build-duplicate-unknown  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" extension" _o2ert-key S" 1" _o2ert-text _o2ert-comma
    _o2ert-quote S" extens" _o2ert-text
    _o2ert-slash S" u0069" _o2ert-text
    S" on" _o2ert-text _o2ert-quote _o2ert-colon
    S" 2" _o2ert-text
    _o2ert-rbrace ;

: _o2ert-build-duplicate-nested  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" extension" _o2ert-key _o2ert-lbrace
    S" x" _o2ert-key S" 1" _o2ert-text _o2ert-comma
    _o2ert-quote _o2ert-slash S" u0078" _o2ert-text
    _o2ert-quote _o2ert-colon S" 2" _o2ert-text
    _o2ert-rbrace _o2ert-rbrace ;

: _o2ert-build-malformed  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error ;

: _o2ert-build-trailing  ( -- )
    _o2ert-build-minimal S" trailing" _o2ert-text ;

: _o2ert-repeat-byte  ( byte count -- )
    BEGIN DUP WHILE
        OVER _o2ert-char
        1-
    REPEAT
    2DROP ;

: _o2ert-build-too-deep  ( -- )
    _o2ert-reset _o2ert-lbrace _o2ert-error _o2ert-comma
    S" extension" _o2ert-key
    91 JOSE-JSON-MAX-DEPTH 1+ _o2ert-repeat-byte
    S" 0" _o2ert-text
    93 JOSE-JSON-MAX-DEPTH 1+ _o2ert-repeat-byte
    _o2ert-rbrace ;

: _o2ert-call  ( callback context -- callback-status response-status )
    >R >R
    _o2ert-input _o2ert-input-u @
    R> R> _o2ert-work
    OAUTH2-ERROR-RESPONSE-WITH ;

: _o2ert-saved-view-invalid  ( -- )
    _o2ert-saved-view @ OAUTH2-ERROR-VIEW-ERROR@
    OAUTH2-ERROR-RESPONSE-S-INVALID _o2ert-status
    2DROP
    _o2ert-saved-view @ OAUTH2-ERROR-VIEW-DESCRIPTION@
    OAUTH2-ERROR-RESPONSE-S-INVALID _o2ert-status
    2DROP
    _o2ert-saved-view @ OAUTH2-ERROR-VIEW-URI@
    OAUTH2-ERROR-RESPONSE-S-INVALID _o2ert-status
    2DROP ;

: _o2ert-callback-minimal  ( view context -- callback-status )
    1 _o2ert-callback-count +!
    _O2ERT-CONTEXT = _o2ert-assert
    DUP _o2ert-saved-view !
    DUP OAUTH2-ERROR-VIEW-ERROR@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    S" invalid_grant" COMPARE 0= _o2ert-assert
    DUP OAUTH2-ERROR-VIEW-DESCRIPTION@
    OAUTH2-ERROR-RESPONSE-S-MISSING _o2ert-status
    2DROP
    OAUTH2-ERROR-VIEW-URI@
    OAUTH2-ERROR-RESPONSE-S-MISSING _o2ert-status
    2DROP
    101 ;

: _o2ert-callback-full  ( view context -- callback-status )
    1 _o2ert-callback-count +!
    DROP
    DUP _o2ert-saved-view !
    DUP OAUTH2-ERROR-VIEW-ERROR@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    S" invalid_grant" COMPARE 0= _o2ert-assert
    DUP OAUTH2-ERROR-VIEW-DESCRIPTION@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    S" Grant was rejected." COMPARE 0= _o2ert-assert
    OAUTH2-ERROR-VIEW-URI@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    S" https://[2001:db8::1]:8443/errors/invalid%20grant?lang=en#details"
    COMPARE 0= _o2ert-assert
    202 ;

: _o2ert-callback-relative  ( view context -- callback-status )
    1 _o2ert-callback-count +!
    DROP
    DUP _o2ert-saved-view !
    OAUTH2-ERROR-VIEW-URI@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    S" ../errors/invalid_request?source=as#detail"
    COMPARE 0= _o2ert-assert
    303 ;

: _o2ert-callback-uri-empty  ( view context -- callback-status )
    1 _o2ert-callback-count +!
    DROP
    DUP _o2ert-saved-view !
    OAUTH2-ERROR-VIEW-URI@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    NIP 0= _o2ert-assert
    304 ;

: _o2ert-callback-extension  ( view context -- callback-status )
    1 _o2ert-callback-count +!
    DROP
    DUP _o2ert-saved-view !
    OAUTH2-ERROR-VIEW-ERROR@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    S" extension_error !#[]~" COMPARE 0= _o2ert-assert
    313 ;

: _o2ert-callback-long  ( view expected-u -- callback-status )
    1 _o2ert-callback-count +!
    >R
    DUP _o2ert-saved-view !
    OAUTH2-ERROR-VIEW-ERROR@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    DUP R> = _o2ert-assert
    101 _o2ert-filled? _o2ert-assert
    404 ;

: _o2ert-callback-description-long  ( view expected-u -- callback-status )
    1 _o2ert-callback-count +!
    >R
    DUP _o2ert-saved-view !
    OAUTH2-ERROR-VIEW-DESCRIPTION@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    DUP R> = _o2ert-assert
    100 _o2ert-filled? _o2ert-assert
    505 ;

: _o2ert-callback-uri-long  ( view expected-u -- callback-status )
    1 _o2ert-callback-count +!
    >R
    DUP _o2ert-saved-view !
    OAUTH2-ERROR-VIEW-URI@
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    DUP R> = _o2ert-assert
    DROP 6
    S" urn:x:" COMPARE 0= _o2ert-assert
    606 ;

: _o2ert-callback-never  ( view context -- callback-status )
    1 _o2ert-callback-count +!
    2DROP
    0 _o2ert-assert
    0 ;

: _o2ert-callback-throw  ( view context -- callback-status )
    1 _o2ert-callback-count +!
    DROP DUP _o2ert-saved-view ! DROP
    -733 THROW ;

: _o2ert-callback-extra  ( view context -- status extra )
    1 _o2ert-callback-count +!
    DROP DUP _o2ert-saved-view ! DROP
    707 708 ;

: _o2ert-callback-overconsume
  ( caller-cell view context -- status extra )
    1 _o2ert-callback-count +!
    2DROP DROP
    717 718 ;

: _o2ert-operation-throw
  ( source source-u callback context workspace -- cb-status status )
    -744 THROW ;

: _o2ert-expect-success  ( callback context expected-callback -- )
    >R
    0 _o2ert-callback-count !
    _o2ert-fill-work
    _o2ert-call
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    R> = _o2ert-assert
    _o2ert-callback-count @ 1 = _o2ert-assert
    _o2ert-work-zero? _o2ert-assert
    _o2ert-saved-view-invalid ;

: _o2ert-expect-rejection  ( expected-status -- )
    >R
    0 _o2ert-callback-count !
    _o2ert-fill-work
    ['] _o2ert-callback-never 0 _o2ert-call
    R> _o2ert-status
    0= _o2ert-assert
    _o2ert-callback-count @ 0= _o2ert-assert
    _o2ert-work-zero? _o2ert-assert ;

: _o2ert-test-statuses  ( -- )
    OAUTH2-ERROR-RESPONSE-S-OK
    OAUTH2-ERROR-RESPONSE-STATUS-VALID? _o2ert-assert
    OAUTH2-ERROR-RESPONSE-S-PLATFORM
    OAUTH2-ERROR-RESPONSE-STATUS-VALID? _o2ert-assert
    -1 OAUTH2-ERROR-RESPONSE-STATUS-VALID? 0= _o2ert-assert
    OAUTH2-ERROR-RESPONSE-S-PLATFORM 1+
    OAUTH2-ERROR-RESPONSE-STATUS-VALID? 0= _o2ert-assert
    OAUTH2-ERROR-VIEW-ERROR-CAPACITY 256 = _o2ert-assert
    OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY 1024 = _o2ert-assert
    OAUTH2-ERROR-VIEW-URI-CAPACITY 4096 = _o2ert-assert
    _o2ert-stack ;

: _o2ert-test-success-and-lifetime  ( -- )
    _o2ert-build-minimal
    ['] _o2ert-callback-minimal _O2ERT-CONTEXT 101
    _o2ert-expect-success

    _o2ert-build-full
    ['] _o2ert-callback-full 0 202
    _o2ert-expect-success

    _o2ert-build-relative-uri
    ['] _o2ert-callback-relative 0 303
    _o2ert-expect-success

    S" " _o2ert-build-uri-value
    ['] _o2ert-callback-uri-empty 0 304
    _o2ert-expect-success

    S" extension_error !#[]~" _o2ert-build-error-value
    ['] _o2ert-callback-extension 0 313
    _o2ert-expect-success

    OAUTH2-ERROR-VIEW-ERROR-CAPACITY
    DUP _o2ert-build-long-error
    ['] _o2ert-callback-long SWAP 404
    _o2ert-expect-success

    OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY
    DUP _o2ert-build-long-description
    ['] _o2ert-callback-description-long SWAP 505
    _o2ert-expect-success

    OAUTH2-ERROR-VIEW-URI-CAPACITY
    DUP _o2ert-build-long-uri
    ['] _o2ert-callback-uri-long SWAP 606
    _o2ert-expect-success
    _o2ert-stack ;

: _o2ert-test-errors-and-json  ( -- )
    _o2ert-build-missing-error
    OAUTH2-ERROR-RESPONSE-S-MISSING _o2ert-expect-rejection
    _o2ert-build-wrong-error-type
    OAUTH2-ERROR-RESPONSE-S-TYPE _o2ert-expect-rejection
    _o2ert-build-wrong-description-type
    OAUTH2-ERROR-RESPONSE-S-TYPE _o2ert-expect-rejection
    _o2ert-build-wrong-uri-type
    OAUTH2-ERROR-RESPONSE-S-TYPE _o2ert-expect-rejection
    _o2ert-build-duplicate-error
    OAUTH2-ERROR-RESPONSE-S-DUPLICATE _o2ert-expect-rejection
    _o2ert-build-duplicate-unknown
    OAUTH2-ERROR-RESPONSE-S-DUPLICATE _o2ert-expect-rejection
    _o2ert-build-duplicate-nested
    OAUTH2-ERROR-RESPONSE-S-DUPLICATE _o2ert-expect-rejection
    _o2ert-build-malformed
    OAUTH2-ERROR-RESPONSE-S-JSON _o2ert-expect-rejection
    _o2ert-build-trailing
    OAUTH2-ERROR-RESPONSE-S-JSON _o2ert-expect-rejection
    _o2ert-build-too-deep
    OAUTH2-ERROR-RESPONSE-S-JSON _o2ert-expect-rejection
    OAUTH2-ERROR-VIEW-ERROR-CAPACITY 1+
    _o2ert-build-long-error
    OAUTH2-ERROR-RESPONSE-S-CAPACITY _o2ert-expect-rejection
    OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY 1+
    _o2ert-build-long-description
    OAUTH2-ERROR-RESPONSE-S-CAPACITY _o2ert-expect-rejection
    OAUTH2-ERROR-VIEW-URI-CAPACITY 1+
    _o2ert-build-long-uri
    OAUTH2-ERROR-RESPONSE-S-CAPACITY _o2ert-expect-rejection
    _o2ert-stack ;

: _o2ert-test-value-grammars  ( -- )
    S" " _o2ert-build-error-value
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" " _o2ert-build-description-value
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" u000A" _o2ert-build-error-escaped
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" u0022" _o2ert-build-error-escaped
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" u005C" _o2ert-build-description-escaped
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" u00E9" _o2ert-build-description-escaped
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection

    S" https://as.example/error with-space" _o2ert-build-uri-value
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" https://as.example/error%2Gbad" _o2ert-build-uri-value
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" 1https://as.example/error" _o2ert-build-uri-value
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    S" https://[2001:db8:::1]/error" _o2ert-build-uri-value
    OAUTH2-ERROR-RESPONSE-S-VALUE _o2ert-expect-rejection
    _o2ert-stack ;

: _o2ert-uri-valid  ( address length -- )
    _O2ER-URI-REFERENCE? _o2ert-assert ;

: _o2ert-uri-invalid  ( address length -- )
    _O2ER-URI-REFERENCE? 0= _o2ert-assert ;

: _o2ert-test-uri-reference-matrix  ( -- )
    0 0 _o2ert-uri-valid
    S" #" _o2ert-uri-valid
    S" ?" _o2ert-uri-valid
    S" ?a?b" _o2ert-uri-valid
    S" file:///tmp/error" _o2ert-uri-valid
    S" https://[v1.fe80::a]:/x" _o2ert-uri-valid
    S" http://[::ffff:192.0.2.128]/" _o2ert-uri-valid
    S" ///path" _o2ert-uri-valid
    S" //example.com:/x" _o2ert-uri-valid
    S" a/b:c" _o2ert-uri-valid
    S" urn:x:" _o2ert-uri-valid

    S" #a#b" _o2ert-uri-invalid
    S" //u@v@host/x" _o2ert-uri-invalid
    S" //host:abc/x" _o2ert-uri-invalid
    S" http://[v.fe]/" _o2ert-uri-invalid
    S" 1a:b" _o2ert-uri-invalid
    S" http://[::ffff:192.0.2.999]/" _o2ert-uri-invalid
    S" http://[::1]tail/x" _o2ert-uri-invalid
    _o2ert-stack ;

: _o2ert-test-callbacks  ( -- )
    _o2ert-build-minimal
    0 _o2ert-callback-count !
    _o2ert-fill-work
    ['] _o2ert-callback-throw 0 _o2ert-call
    OAUTH2-ERROR-RESPONSE-S-CALLBACK _o2ert-status
    0= _o2ert-assert
    _o2ert-callback-count @ 1 = _o2ert-assert
    _o2ert-work-zero? _o2ert-assert
    _o2ert-saved-view-invalid

    \ A compensating callback must not consume the caller cell below its
    \ two arguments and evade the net-depth check.
    _o2ert-build-minimal
    0 _o2ert-callback-count !
    _o2ert-fill-work
    _O2ERT-STACK-SENTINEL
    ['] _o2ert-callback-overconsume 0 _o2ert-call
    OAUTH2-ERROR-RESPONSE-S-CALLBACK _o2ert-status
    0= _o2ert-assert
    _O2ERT-STACK-SENTINEL = _o2ert-assert
    _o2ert-callback-count @ 1 = _o2ert-assert
    _o2ert-work-zero? _o2ert-assert

    _o2ert-build-minimal
    0 _o2ert-callback-count !
    _o2ert-fill-work
    ['] _o2ert-callback-extra 0 _o2ert-call
    OAUTH2-ERROR-RESPONSE-S-CALLBACK _o2ert-status
    0= _o2ert-assert
    _o2ert-callback-count @ 1 = _o2ert-assert
    _o2ert-work-zero? _o2ert-assert
    _o2ert-saved-view-invalid

    _o2ert-build-minimal
    _o2ert-fill-work
    _o2ert-input _o2ert-input-u @
    ['] _o2ert-callback-never 0 _o2ert-work
    ['] _o2ert-operation-throw _O2ER-WITH-CALL
    OAUTH2-ERROR-RESPONSE-S-INTERNAL _o2ert-status
    0= _o2ert-assert
    _o2ert-work-zero? _o2ert-assert
    _o2ert-stack ;

: _o2ert-test-preflight  ( -- )
    _o2ert-build-minimal
    0 _o2ert-callback-count !

    \ Source/workspace aliasing rejects before any workspace byte changes.
    _o2ert-fill-work
    _o2ert-work _o2ert-input-u @
    ['] _o2ert-callback-never 0 _o2ert-work
    OAUTH2-ERROR-RESPONSE-WITH
    OAUTH2-ERROR-RESPONSE-S-ALIAS _o2ert-status
    0= _o2ert-assert
    _o2ert-callback-count @ 0= _o2ert-assert
    _o2ert-work-filled? _o2ert-assert

    \ A cell-misaligned workspace is invalid and remains intact.
    _o2ert-fill-all-work
    _o2ert-input _o2ert-input-u @
    ['] _o2ert-callback-never 0 _o2ert-work 1+
    OAUTH2-ERROR-RESPONSE-WITH
    OAUTH2-ERROR-RESPONSE-S-INVALID _o2ert-status
    0= _o2ert-assert
    _o2ert-callback-count @ 0= _o2ert-assert
    _o2ert-work-all-filled? _o2ert-assert

    \ Malformed source geometry is rejected before workspace ownership.
    _o2ert-fill-work
    _o2ert-input -1
    ['] _o2ert-callback-never 0 _o2ert-work
    OAUTH2-ERROR-RESPONSE-WITH
    OAUTH2-ERROR-RESPONSE-S-RANGE _o2ert-status
    0= _o2ert-assert
    _o2ert-work-filled? _o2ert-assert

    \ Oversize advertised input is a preflight capacity rejection.
    _o2ert-fill-work
    _o2ert-input JOSE-JSON-MAX-DOCUMENT-BYTES 1+
    ['] _o2ert-callback-never 0 _o2ert-work
    OAUTH2-ERROR-RESPONSE-WITH
    OAUTH2-ERROR-RESPONSE-S-CAPACITY _o2ert-status
    0= _o2ert-assert
    _o2ert-work-filled? _o2ert-assert

    \ A null callback cannot claim or wipe an otherwise valid workspace.
    _o2ert-fill-work
    _o2ert-input _o2ert-input-u @
    0 0 _o2ert-work OAUTH2-ERROR-RESPONSE-WITH
    OAUTH2-ERROR-RESPONSE-S-INVALID _o2ert-status
    0= _o2ert-assert
    _o2ert-work-filled? _o2ert-assert
    _o2ert-callback-count @ 0= _o2ert-assert
    _o2ert-stack ;

: _o2ert-test-workspace-clear  ( -- )
    _o2ert-fill-work
    _o2ert-work OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR
    OAUTH2-ERROR-RESPONSE-S-OK _o2ert-status
    _o2ert-work-zero? _o2ert-assert

    \ Misalignment is rejected without clearing any advertised byte.
    _o2ert-fill-all-work
    _o2ert-work 1+ OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR
    OAUTH2-ERROR-RESPONSE-S-INVALID _o2ert-status
    _o2ert-work-all-filled? _o2ert-assert
    _o2ert-stack ;

: _O2ERT-RUN  ( -- )
    0 _o2ert-checks !
    0 _o2ert-fails !
    0 _o2ert-saved-view !
    DEPTH _o2ert-depth !
    _o2ert-test-statuses
    ." OAUTH2 ERROR RESPONSE GROUP STATUSES" CR TX-FLUSH
    _o2ert-test-success-and-lifetime
    ." OAUTH2 ERROR RESPONSE GROUP SUCCESS" CR TX-FLUSH
    _o2ert-test-errors-and-json
    ." OAUTH2 ERROR RESPONSE GROUP ERRORS" CR TX-FLUSH
    _o2ert-test-value-grammars
    ." OAUTH2 ERROR RESPONSE GROUP GRAMMARS" CR TX-FLUSH
    _o2ert-test-uri-reference-matrix
    ." OAUTH2 ERROR RESPONSE GROUP URI MATRIX" CR TX-FLUSH
    _o2ert-test-callbacks
    ." OAUTH2 ERROR RESPONSE GROUP CALLBACKS" CR TX-FLUSH
    _o2ert-test-preflight
    ." OAUTH2 ERROR RESPONSE GROUP PREFLIGHT" CR TX-FLUSH
    _o2ert-test-workspace-clear
    ." OAUTH2 ERROR RESPONSE GROUP CLEAR" CR TX-FLUSH
    _o2ert-stack
    _o2ert-fails @ IF
        ." OAUTH2 ERROR RESPONSE FAIL " _o2ert-fails @ . CR
    ELSE
        ." OAUTH2 ERROR RESPONSE PASS " _o2ert-checks @ . CR
    THEN
    TX-FLUSH ;
