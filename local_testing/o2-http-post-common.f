\ Shared deterministic support for the generic OAuth 2 HTTP POST owner.

PROVIDED akashic-o2http-common

4096 CONSTANT _O2HPT-REQUEST-CAPACITY
1024 CONSTANT _O2HPT-FORM-CAPACITY
1024 CONSTANT _O2HPT-RESPONSE-CAPACITY
4096 CONSTANT _O2HPT-WIRE-CAPACITY

CREATE _o2hpt-target-storage HTARGET-SIZE 7 + ALLOT
CREATE _o2hpt-post-storage OAUTH2-HTTP-POST-SIZE 7 + ALLOT
CREATE _o2hpt-request-storage _O2HPT-REQUEST-CAPACITY 7 + ALLOT
CREATE _o2hpt-form-storage _O2HPT-FORM-CAPACITY 7 + ALLOT
CREATE _o2hpt-response-storage _O2HPT-RESPONSE-CAPACITY 7 + ALLOT
CREATE _o2hpt-port-storage NET-IO-PORT-SIZE 7 + ALLOT
CREATE _o2hpt-server _O2HPT-WIRE-CAPACITY ALLOT
CREATE _o2hpt-sent _O2HPT-WIRE-CAPACITY ALLOT
CREATE _o2hpt-expected _O2HPT-WIRE-CAPACITY ALLOT

: _o2hpt-target  ( -- address )
    _o2hpt-target-storage 7 + -8 AND ;

: _o2hpt-post  ( -- address )
    _o2hpt-post-storage 7 + -8 AND ;

: _o2hpt-request  ( -- address )
    _o2hpt-request-storage 7 + -8 AND ;

: _o2hpt-form  ( -- address )
    _o2hpt-form-storage 7 + -8 AND ;

: _o2hpt-response  ( -- address )
    _o2hpt-response-storage 7 + -8 AND ;

: _o2hpt-port  ( -- address )
    _o2hpt-port-storage 7 + -8 AND ;

VARIABLE _o2hpt-checks
VARIABLE _o2hpt-fails
VARIABLE _o2hpt-depth
VARIABLE _o2hpt-server-u
VARIABLE _o2hpt-server-pos
VARIABLE _o2hpt-sent-u
VARIABLE _o2hpt-expected-u
VARIABLE _o2hpt-copy-u
VARIABLE _o2hpt-io-a
VARIABLE _o2hpt-io-u
VARIABLE _o2hpt-io-n
VARIABLE _o2hpt-status-value
VARIABLE _o2hpt-steps
VARIABLE _o2hpt-recv-limit
VARIABLE _o2hpt-send-limit
VARIABLE _o2hpt-close-fault
VARIABLE _o2hpt-cancel-fault
VARIABLE _o2hpt-close-calls
VARIABLE _o2hpt-cancel-calls
VARIABLE _o2hpt-saved-0
VARIABLE _o2hpt-saved-1
VARIABLE _o2hpt-expected-outcome
VARIABLE _o2hpt-expected-detail
VARIABLE _o2hpt-expected-http

: _o2hpt-assert  ( flag -- )
    1 _o2hpt-checks +!
    0= IF
        1 _o2hpt-fails +!
        ." OAUTH2 HTTP POST ASSERT " _o2hpt-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2hpt-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 HTTP POST STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2hpt-assert ;

: _o2hpt-stack  ( -- )
    DEPTH _o2hpt-depth @ = _o2hpt-assert ;

: _o2hpt-zero?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1 /STRING
    REPEAT
    2DROP -1 ;

: _o2hpt-server,  ( address length -- )
    DUP _o2hpt-copy-u !
    _o2hpt-server _o2hpt-server-u @ + SWAP CMOVE
    _o2hpt-copy-u @ _o2hpt-server-u +! ;

: _o2hpt-server-crlf,  ( -- )
    13 _o2hpt-server _o2hpt-server-u @ + C!
    1 _o2hpt-server-u +!
    10 _o2hpt-server _o2hpt-server-u @ + C!
    1 _o2hpt-server-u +! ;

: _o2hpt-server-line,  ( address length -- )
    _o2hpt-server, _o2hpt-server-crlf, ;

: _o2hpt-server-reset  ( -- )
    0 _o2hpt-server-u ! ;

: _o2hpt-server-finish-json  ( -- )
    S" Content-Length: 2" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf,
    S" {}" _o2hpt-server, ;

: _o2hpt-build-json-server  ( status-a status-u -- )
    _o2hpt-server-reset
    _o2hpt-server-line,
    S" Content-Type: application/json" _o2hpt-server-line,
    _o2hpt-server-finish-json ;

: _o2hpt-build-header-only-server  ( status-a status-u -- )
    _o2hpt-server-reset
    _o2hpt-server-line,
    S" Content-Length: 0" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf, ;

: _o2hpt-build-server  ( -- )
    _o2hpt-server-reset
    S" HTTP/1.1 200 OK" _o2hpt-server-line,
    S" Content-Type: application/json; charset=utf-8"
        _o2hpt-server-line,
    S" Content-Encoding: identity" _o2hpt-server-line,
    S" DPoP-Nonce: server-nonce-1" _o2hpt-server-line,
    S" Content-Length: 2" _o2hpt-server-line,
    S" Connection: close" _o2hpt-server-line,
    _o2hpt-server-crlf,
    S" {}" _o2hpt-server, ;

: _o2hpt-open-start  ( context -- io-status )
    DROP NIO-S-OK ;

: _o2hpt-open-poll  ( context -- io-status )
    DROP NIO-S-OK ;

: _o2hpt-send  ( buffer length context -- count io-status )
    DROP _o2hpt-io-u ! _o2hpt-io-a !
    _o2hpt-send-limit @ DUP 0> IF
        _o2hpt-io-u @ MIN
    ELSE
        DROP _o2hpt-io-u @
    THEN
    _o2hpt-io-n !
    _o2hpt-sent-u @ _o2hpt-io-n @ +
        _O2HPT-WIRE-CAPACITY > IF
        0 NIO-S-FAILED EXIT
    THEN
    _o2hpt-io-a @ _o2hpt-sent _o2hpt-sent-u @ +
        _o2hpt-io-n @ CMOVE
    _o2hpt-io-n @ _o2hpt-sent-u +!
    _o2hpt-io-n @ NIO-S-OK ;

: _o2hpt-recv  ( buffer capacity context -- count io-status )
    DROP _o2hpt-io-u ! _o2hpt-io-a !
    _o2hpt-server-u @ _o2hpt-server-pos @ -
    DUP 0= IF DROP 0 NIO-S-EOF EXIT THEN
    _o2hpt-io-u @ MIN
    _o2hpt-recv-limit @ DUP 0> IF MIN ELSE DROP THEN
    _o2hpt-io-n !
    _o2hpt-server _o2hpt-server-pos @ +
    _o2hpt-io-a @ _o2hpt-io-n @ CMOVE
    _o2hpt-io-n @ _o2hpt-server-pos +!
    _o2hpt-io-n @ NIO-S-OK ;

: _o2hpt-poll  ( context -- )
    DROP ;

: _o2hpt-close-start  ( context -- io-status )
    DROP
    1 _o2hpt-close-calls +!
    _o2hpt-close-fault @ ?DUP IF THROW THEN
    NIO-S-OK ;

: _o2hpt-close-poll  ( context -- io-status )
    DROP NIO-S-OK ;

: _o2hpt-cancel  ( context -- )
    DROP
    1 _o2hpt-cancel-calls +!
    _o2hpt-cancel-fault @ ?DUP IF THROW THEN ;

: _o2hpt-port-install-at  ( port -- )
    DUP NIO-INIT
    0 OVER NIO.CONTEXT !
    ['] _o2hpt-open-start OVER NIO.OPEN-START-XT !
    ['] _o2hpt-open-poll OVER NIO.OPEN-POLL-XT !
    ['] _o2hpt-send OVER NIO.SEND-XT !
    ['] _o2hpt-recv OVER NIO.RECV-XT !
    ['] _o2hpt-poll OVER NIO.POLL-XT !
    ['] _o2hpt-close-start OVER NIO.CLOSE-START-XT !
    ['] _o2hpt-close-poll OVER NIO.CLOSE-POLL-XT !
    ['] _o2hpt-cancel OVER NIO.CANCEL-XT !
    DROP ;

: _o2hpt-port-install  ( -- )
    _o2hpt-port _o2hpt-port-install-at ;

: _o2hpt-transport-reset  ( -- )
    0 _o2hpt-sent-u !
    0 _o2hpt-server-pos !
    _O2HPT-WIRE-CAPACITY _o2hpt-recv-limit !
    0 _o2hpt-send-limit !
    0 _o2hpt-close-fault !
    0 _o2hpt-cancel-fault !
    0 _o2hpt-close-calls !
    0 _o2hpt-cancel-calls !
    _o2hpt-port-install ;

: _o2hpt-start-at  ( port -- status )
    _o2hpt-post OAUTH2-HTTP-POST-START ;

: _o2hpt-start  ( -- status )
    _o2hpt-port _o2hpt-start-at ;

: _o2hpt-pump  ( -- status )
    0 _o2hpt-steps !
    _o2hpt-post OAUTH2-HTTP-POST-POLL _o2hpt-status-value !
    BEGIN
        _o2hpt-status-value @ OAUTH2-HTTP-POST-S-PENDING =
    WHILE
        1 _o2hpt-steps +!
        _o2hpt-steps @ 128 > IF
            0 _o2hpt-assert
            OAUTH2-HTTP-POST-S-INTERNAL _o2hpt-status-value !
        ELSE
            _o2hpt-post OAUTH2-HTTP-POST-POLL
                _o2hpt-status-value !
        THEN
    REPEAT
    _o2hpt-status-value @ ;

: _o2hpt-nonce?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-NONCE@
    IF
        S" server-nonce-1" STR-STR=
    ELSE
        2DROP 0
    THEN ;

: _o2hpt-nonce-absent?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-NONCE@
    IF
        2DROP 0
    ELSE
        2DROP -1
    THEN ;

: _o2hpt-correlation?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-CORRELATION@
    IF
        S" operation-binding-1" STR-STR=
    ELSE
        2DROP 0
    THEN ;

: _o2hpt-correlation-absent?  ( -- flag )
    _o2hpt-post OAUTH2-HTTP-POST-CORRELATION@
    IF
        2DROP 0
    ELSE
        2DROP -1
    THEN ;

: _o2hpt-semantic  ( outcome detail http-status -- )
    _o2hpt-expected-http !
    _o2hpt-expected-detail !
    _o2hpt-expected-outcome !
    _o2hpt-post OAUTH2-HTTP-POST-OUTCOME@
        _o2hpt-expected-outcome @ = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-DETAIL@
        _o2hpt-expected-detail @ = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-HTTP-STATUS@
        _o2hpt-expected-http @ = _o2hpt-assert ;

: _o2hpt-configure-lean  ( -- )
    0 _o2hpt-post _O2HP.MAGIC !
    S" https://pds.example.test:8443/oauth/token?aud=client"
        _o2hpt-target HTARGET-PARSE
        HTARGET-S-OK _o2hpt-status
    _o2hpt-target
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
    _o2hpt-form _O2HPT-FORM-CAPACITY
    _o2hpt-response _O2HPT-RESPONSE-CAPACITY
    _o2hpt-post OAUTH2-HTTP-POST-CONFIGURE
        OAUTH2-HTTP-POST-S-OK _o2hpt-status ;

: _o2hpt-build-request-lean  ( -- )
    OAUTH2-HTTP-POST-KIND-TOKEN _o2hpt-post OAUTH2-HTTP-POST-BEGIN
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    S" grant_type" S" authorization_code"
        _o2hpt-post OAUTH2-HTTP-POST-FIELD
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    S" code" S" a b" _o2hpt-post OAUTH2-HTTP-POST-FIELD
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    S" proof-value" S" Basic client-secret"
        _o2hpt-post OAUTH2-HTTP-POST-SEAL
        OAUTH2-HTTP-POST-S-OK _o2hpt-status ;

: _o2hpt-suite-init-lean  ( -- )
    _o2hpt-configure-lean ;

: _o2hpt-suite-finish-lean  ( -- )
    _o2hpt-post OAUTH2-HTTP-POST-WIPE
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-stack ;

: _o2hpt-suite-begin  ( -- )
    0 _o2hpt-checks ! 0 _o2hpt-fails ! DEPTH _o2hpt-depth !
;

: _o2hpt-suite-report  ( -- )
    _o2hpt-fails @ IF
        ." OAUTH2 HTTP POST FAIL checks/fails "
        _o2hpt-checks @ . _o2hpt-fails @ . CR
    ELSE
        ." OAUTH2 HTTP POST PASS checks "
        _o2hpt-checks @ . CR
    THEN
    TX-FLUSH ;
