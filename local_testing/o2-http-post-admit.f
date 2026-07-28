\ Strict response-admission qualification.

REQUIRE o2-http-post-common.f
PROVIDED akashic-o2http-admit

: _o2hpt-build-empty-json-server  ( -- )
    _o2hpt-server-reset
    S" HTTP/1.1 200 OK" _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    S" Content-Length: 0" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf, ;

: _o2hpt-build-text-server  ( -- )
    _o2hpt-server-reset
    S" HTTP/1.1 200 OK" _o2hpt-server-line,
    S" Content-Type: text/plain" _o2hpt-server-line,
    _o2hpt-server-finish-json ;

: _o2hpt-build-duplicate-nonce-server  ( -- )
    _o2hpt-server-reset
    S" HTTP/1.1 200 OK" _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    S" DPoP-Nonce: nonce-a" _o2hpt-server-line,
    S" DPoP-Nonce: nonce-b" _o2hpt-server-line,
    _o2hpt-server-finish-json ;

: _o2hpt-build-invalid-nonce-server  ( -- )
    _o2hpt-server-reset
    S" HTTP/1.1 200 OK" _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    S" DPoP-Nonce: bad nonce" _o2hpt-server-line,
    _o2hpt-server-finish-json ;

: _o2hpt-build-framing-server  ( -- )
    _o2hpt-server-reset
    S" HTTP/1.1 200 OK" _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    S" Content-Length: 2" _o2hpt-server-line,
    S" Transfer-Encoding: chunked" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf,
    S" {}" _o2hpt-server, ;

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

: _o2hpt-test-oauth-errors  ( -- )
    S" HTTP/1.1 400 Bad Request" _o2hpt-build-json-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-OAUTH-ERROR OAUTH2-HTTP-POST-D-NONE 400
        _o2hpt-semantic
    _o2hpt-post OAUTH2-HTTP-POST-BODY@
        S" {}" STR-STR= _o2hpt-assert
    _o2hpt-admission-reset

    S" HTTP/1.1 401 Unauthorized" _o2hpt-build-json-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-OAUTH-ERROR OAUTH2-HTTP-POST-D-NONE 401
        _o2hpt-semantic
    _o2hpt-admission-reset ;

: _o2hpt-test-http-outcomes  ( -- )
    S" HTTP/1.1 302 Found" _o2hpt-build-header-only-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-HTTP OAUTH2-HTTP-POST-D-REDIRECT 302
        _o2hpt-semantic
    _o2hpt-admission-reset

    S" HTTP/1.1 418 Teapot" _o2hpt-build-header-only-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-HTTP
        OAUTH2-HTTP-POST-D-UNEXPECTED-HTTP 418
        _o2hpt-semantic
    _o2hpt-admission-reset ;

: _o2hpt-test-media-outcomes  ( -- )
    _o2hpt-build-empty-json-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-BODY OAUTH2-HTTP-POST-D-BODY-EMPTY 200
        _o2hpt-semantic
    _o2hpt-admission-reset

    _o2hpt-build-text-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-MEDIA
        OAUTH2-HTTP-POST-D-CONTENT-TYPE-NOT-JSON 200
        _o2hpt-semantic
    _o2hpt-admission-reset ;

: _o2hpt-test-nonce-outcomes  ( -- )
    _o2hpt-build-duplicate-nonce-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-HEADER
        OAUTH2-HTTP-POST-D-DPOP-NONCE-DUPLICATE 200
        _o2hpt-semantic
    _o2hpt-nonce-absent? _o2hpt-assert
    _o2hpt-admission-reset

    _o2hpt-build-invalid-nonce-server
    _o2hpt-admit-server
    OAUTH2-HTTP-POST-O-HEADER
        OAUTH2-HTTP-POST-D-DPOP-NONCE-CHARACTER 200
        _o2hpt-semantic
    _o2hpt-nonce-absent? _o2hpt-assert
    _o2hpt-admission-reset ;

: _o2hpt-test-framing  ( -- )
    _o2hpt-build-framing-server
    _o2hpt-admission-reset
    _o2hpt-server _o2hpt-server-u @
        _o2hpt-post _O2HP.EXCHANGE HBUF.PARSER HSTR-FEED
        HSTR-S-FRAMING _o2hpt-status
    HBUF-S-PROTOCOL _o2hpt-post _O2HP.EXCHANGE _HBUF-FAIL
        _o2hpt-post _O2HP-HANDLE-HBUF-TERMINAL
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    OAUTH2-HTTP-POST-O-PROTOCOL HSTR-S-FRAMING 0
        _o2hpt-semantic
    _o2hpt-post OAUTH2-HTTP-POST-PARSER-STATUS@
        HSTR-S-FRAMING = _o2hpt-assert ;

: _o2hpt-admission-cases  ( -- )
    ." OAUTH2 HTTP POST STAGE admission-start" CR TX-FLUSH
    _o2hpt-suite-init-lean
    _o2hpt-build-request-lean
    _o2hpt-test-oauth-errors
    _o2hpt-test-http-outcomes
    _o2hpt-test-media-outcomes
    _o2hpt-test-nonce-outcomes
    ." OAUTH2 HTTP POST STAGE admission" CR TX-FLUSH
    _o2hpt-test-framing
    ." OAUTH2 HTTP POST STAGE framing" CR TX-FLUSH
    _o2hpt-suite-finish-lean ;

: _O2HPT-RUN-ADMISSION  ( -- )
    _o2hpt-suite-begin
    _o2hpt-admission-cases
    _o2hpt-suite-report ;
