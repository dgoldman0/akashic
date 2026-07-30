\ Full configuration, lifecycle, and wipe qualification.

REQUIRE o2-http-post-common.f
PROVIDED akashic-o2http-main

: _o2hpt-expected,  ( address length -- )
    DUP _o2hpt-copy-u !
    _o2hpt-expected _o2hpt-expected-u @ + SWAP CMOVE
    _o2hpt-copy-u @ _o2hpt-expected-u +! ;

: _o2hpt-expected-crlf,  ( -- )
    13 _o2hpt-expected _o2hpt-expected-u @ + C!
    1 _o2hpt-expected-u +!
    10 _o2hpt-expected _o2hpt-expected-u @ + C!
    1 _o2hpt-expected-u +! ;

: _o2hpt-expected-line,  ( address length -- )
    _o2hpt-expected, _o2hpt-expected-crlf, ;

: _o2hpt-build-expected  ( -- )
    0 _o2hpt-expected-u !
    S" POST /oauth/token?aud=client HTTP/1.1"
        _o2hpt-expected-line,
    S" Host: pds.example.test:8443" _o2hpt-expected-line,
    S" Accept: application/json" _o2hpt-expected-line,
    S" Content-Type: application/x-www-form-urlencoded"
        _o2hpt-expected-line,
    S" DPoP: proof-value" _o2hpt-expected-line,
    S" Authorization: Basic client-secret" _o2hpt-expected-line,
    S" Connection: close" _o2hpt-expected-line,
    S" Content-Length: 38" _o2hpt-expected-line,
    _o2hpt-expected-crlf,
    S" grant_type=authorization_code&code=a+b" _o2hpt-expected, ;

: _o2hpt-negative-geometry  ( -- )
    _o2hpt-target
    _o2hpt-post _O2HPT-REQUEST-CAPACITY
    _o2hpt-form _O2HPT-FORM-CAPACITY
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY
    _o2hpt-post OAUTH2-HTTP-POST-CONFIGURE
        OAUTH2-HTTP-POST-S-ALIAS _o2hpt-status
    _o2hpt-post C@ 0xA5 = _o2hpt-assert

    _o2hpt-target
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
    _o2hpt-request 128 + _O2HPT-FORM-CAPACITY
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY
    _o2hpt-post OAUTH2-HTTP-POST-CONFIGURE
        OAUTH2-HTTP-POST-S-ALIAS _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-SIZE
        _o2hpt-zero? _o2hpt-assert ;

: _o2hpt-configure  ( -- )
    S" https://pds.example.test:8443/oauth/token"
        _o2hpt-target HTARGET-PARSE
        HTARGET-S-OK _o2hpt-status
    _o2hpt-target HTARGET-HTU$
        S" https://pds.example.test:8443/oauth/token"
        STR-STR= _o2hpt-assert
    S" https://pds.example.test:8443/oauth/token?aud=client"
        _o2hpt-target HTARGET-PARSE
        HTARGET-S-OK _o2hpt-status
    _o2hpt-target HTARGET-HTU$
        S" https://pds.example.test:8443/oauth/token"
        STR-STR= _o2hpt-assert
    _o2hpt-negative-geometry
    _o2hpt-target
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
    _o2hpt-form _O2HPT-FORM-CAPACITY
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY
    _o2hpt-post OAUTH2-HTTP-POST-CONFIGURE
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-VALID? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-TARGET@
        _o2hpt-target HTARGET-EQUAL? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-HTU$
        S" https://pds.example.test:8443/oauth/token"
        STR-STR= _o2hpt-assert
    _o2hpt-expected 16 _o2hpt-post
        OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-SIZE _o2hpt-post
        OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS
        OAUTH2-HTTP-POST-S-ALIAS _o2hpt-status
    _o2hpt-request _O2HPT-REQUEST-CAPACITY _o2hpt-post
        OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS
        OAUTH2-HTTP-POST-S-ALIAS _o2hpt-status ;

: _o2hpt-build-request  ( -- )
    OAUTH2-HTTP-POST-KIND-TOKEN _o2hpt-post OAUTH2-HTTP-POST-BEGIN
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-correlation-absent? _o2hpt-assert
    S" operation-binding-1" _o2hpt-post
        OAUTH2-HTTP-POST-CORRELATION!
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-correlation? _o2hpt-assert
    _o2hpt-post 1 _o2hpt-post OAUTH2-HTTP-POST-CORRELATION!
        OAUTH2-HTTP-POST-S-ALIAS _o2hpt-status
    _o2hpt-correlation? _o2hpt-assert
    S" grant_type" S" authorization_code"
        _o2hpt-post OAUTH2-HTTP-POST-FIELD
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    S" code" S" a b" _o2hpt-post OAUTH2-HTTP-POST-FIELD
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-TARGET@ HTARGET-HOST$
        0 0 _o2hpt-post OAUTH2-HTTP-POST-SEAL
        OAUTH2-HTTP-POST-S-ALIAS _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-LAST-STATUS@
        OAUTH2-HTTP-POST-S-ALIAS = _o2hpt-assert
    S" proof-value" S" Basic client-secret"
        _o2hpt-post OAUTH2-HTTP-POST-SEAL
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-INCLUDED? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-INCLUDED?
        _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-SENT? 0= _o2hpt-assert
    _o2hpt-post _O2HP.REQUEST
    DUP HREQ.BUFFER @ SWAP HREQ.LENGTH @
    _o2hpt-expected _o2hpt-expected-u @
        STR-STR= _o2hpt-assert ;

: _o2hpt-build-par-request  ( -- )
    OAUTH2-HTTP-POST-KIND-PAR _o2hpt-post OAUTH2-HTTP-POST-BEGIN
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-correlation-absent? _o2hpt-assert
    S" client_id" S" https://client.example/metadata.json"
        _o2hpt-post OAUTH2-HTTP-POST-FIELD
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    S" request" S" signed-request-object"
        _o2hpt-post OAUTH2-HTTP-POST-FIELD
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    S" proof-value" 0 0
        _o2hpt-post OAUTH2-HTTP-POST-SEAL
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-INCLUDED? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-INCLUDED?
        0= _o2hpt-assert ;

: _o2hpt-result  ( -- )
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
        OAUTH2-HTTP-POST-STATE-RESULT = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-OUTCOME@
        OAUTH2-HTTP-POST-O-SUCCESS = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-DETAIL@
        OAUTH2-HTTP-POST-D-NONE = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-HTTP-STATUS@ 200 = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-BODY@
        S" {}" STR-STR= _o2hpt-assert
    _o2hpt-nonce? _o2hpt-assert
    _o2hpt-correlation? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-LAST-STATUS@
        OAUTH2-HTTP-POST-S-OK = _o2hpt-assert
    S" replacement-binding" _o2hpt-post
        OAUTH2-HTTP-POST-CORRELATION!
        OAUTH2-HTTP-POST-S-STATE _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-LAST-STATUS@
        OAUTH2-HTTP-POST-S-OK = _o2hpt-assert
    _o2hpt-correlation? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-SENT? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-SENT?
        _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-EXCHANGE-STATUS@
        HBUF-S-OK = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-PARSER-STATUS@
        HSTR-S-OK = _o2hpt-assert
    _o2hpt-sent _o2hpt-sent-u @
        _o2hpt-expected _o2hpt-expected-u @
        STR-STR= _o2hpt-assert
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
        _o2hpt-zero? _o2hpt-assert
    _o2hpt-form _O2HPT-FORM-CAPACITY
        _o2hpt-zero? _o2hpt-assert ;

: _o2hpt-admission-reset  ( -- )
    _o2hpt-post _O2HP.EXCHANGE _HBUF-MESSAGE-RESET
    0 _o2hpt-post _O2HP.RESPONSE-U !
    _o2hpt-post _O2HP-CLEAR-NONCE
    _o2hpt-post _O2HP.MEDIA MTYPE-INIT
    OAUTH2-HTTP-POST-O-NONE _o2hpt-post _O2HP.OUTCOME !
    OAUTH2-HTTP-POST-D-NONE _o2hpt-post _O2HP.DETAIL !
    0 _o2hpt-post _O2HP.HTTP-STATUS ! ;

: _o2hpt-admit-server  ( -- )
    _o2hpt-server _o2hpt-server-u @
        _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR-FEED
        HSTR-S-OK _o2hpt-status
    _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR.STATE @
        HSTR-STATE-DONE = _o2hpt-assert
    _o2hpt-post _O2HP-ADMIT-RESPONSE ;

: _o2hpt-test-par  ( -- )
    S" HTTP/1.1 201 Created" _o2hpt-build-json-server
    _o2hpt-build-par-request
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-SUCCESS OAUTH2-HTTP-POST-D-NONE 201
        _o2hpt-semantic
    _o2hpt-post OAUTH2-HTTP-POST-BODY@
        S" {}" STR-STR= _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-SENT? 0= _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-SENT?
        0= _o2hpt-assert
    -1 _o2hpt-post _O2HP-FINISH-CLEAN
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
        OAUTH2-HTTP-POST-STATE-RESULT = _o2hpt-assert ;

: _o2hpt-test-descriptor-invariants  ( -- )
    _o2hpt-post _O2HP.REQUEST HREQ.LENGTH @ _o2hpt-saved-0 !
    _O2HPT-REQUEST-CAPACITY 1+
        _o2hpt-post _O2HP.REQUEST HREQ.LENGTH !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? 0= _o2hpt-assert
    _o2hpt-start OAUTH2-HTTP-POST-S-INVALID _o2hpt-status
    _o2hpt-saved-0 @ _o2hpt-post _O2HP.REQUEST HREQ.LENGTH !

    _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR.REMAINING @
        _o2hpt-saved-0 !
    -1 _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR.REMAINING !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? 0= _o2hpt-assert
    _o2hpt-saved-0 @
        _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR.REMAINING !

    _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR.BODY-XT @
        _o2hpt-saved-0 !
    0 _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR.BODY-XT !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? 0= _o2hpt-assert
    _o2hpt-saved-0 @
        _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR.BODY-XT !

    _o2hpt-post OAUTH2-HTTP-POST-VALID? _o2hpt-assert
    _o2hpt-post _O2HP.FLAGS @ _o2hpt-saved-0 !
    OAUTH2-HTTP-POST-F-DPOP-SENT _o2hpt-post _O2HP.FLAGS !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? 0= _o2hpt-assert
    _o2hpt-saved-0 @ _o2hpt-post _O2HP.FLAGS !
    _o2hpt-saved-0 @ OAUTH2-HTTP-POST-F-DPOP-SENT OR
        _o2hpt-post _O2HP.FLAGS !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? 0= _o2hpt-assert
    _o2hpt-saved-0 @ _o2hpt-post _O2HP.FLAGS !
    _o2hpt-saved-0 @ 16 OR _o2hpt-post _O2HP.FLAGS !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? 0= _o2hpt-assert
    OAUTH2-HTTP-POST-KIND-TOKEN _o2hpt-post OAUTH2-HTTP-POST-BEGIN
        OAUTH2-HTTP-POST-S-INVALID _o2hpt-status
    _o2hpt-saved-0 @ _o2hpt-post _O2HP.FLAGS !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? _o2hpt-assert ;

: _o2hpt-suite-init  ( -- )
    _o2hpt-post OAUTH2-HTTP-POST-SIZE 0xA5 FILL
    _o2hpt-request _O2HPT-REQUEST-CAPACITY 0xA5 FILL
    _o2hpt-form _O2HPT-FORM-CAPACITY 0xA5 FILL
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY 0xA5 FILL
    _o2hpt-build-expected
    _o2hpt-configure ;

: _o2hpt-suite-finish  ( -- )
    _o2hpt-post OAUTH2-HTTP-POST-WIPE
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-VALID? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
        OAUTH2-HTTP-POST-STATE-EMPTY = _o2hpt-assert
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
        _o2hpt-zero? _o2hpt-assert
    _o2hpt-form _O2HPT-FORM-CAPACITY
        _o2hpt-zero? _o2hpt-assert
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY
        _o2hpt-zero? _o2hpt-assert
    _o2hpt-stack ;

: _o2hpt-main-cases  ( -- )
    ." OAUTH2 HTTP POST STAGE main-start" CR TX-FLUSH
    _o2hpt-suite-init
    _o2hpt-build-server
    _o2hpt-build-request
    _o2hpt-transport-reset
    64 _o2hpt-recv-limit !
    _o2hpt-start OAUTH2-HTTP-POST-S-PENDING _o2hpt-status
    _o2hpt-pump OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-result
    ." OAUTH2 HTTP POST STAGE baseline" CR TX-FLUSH
    _o2hpt-test-par
    ." OAUTH2 HTTP POST STAGE par" CR TX-FLUSH
    _o2hpt-build-request-lean
    _o2hpt-test-descriptor-invariants
    ." OAUTH2 HTTP POST STAGE invariants" CR TX-FLUSH
    _o2hpt-suite-finish ;

: _O2HPT-RUN-MAIN  ( -- )
    _o2hpt-suite-begin
    _o2hpt-main-cases
    _o2hpt-suite-report ;
