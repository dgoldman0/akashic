\ Focused authenticated XRPC exchange and getSession identity qualification.
\
\ This extends the durable key/session restart fixture with the production
\ xrpc-exchange owner.  P-256 proof construction and the lower KDOS adapter
\ are deterministic doubles; the tiny NIO peer supplies the response.  The
\ exact owner still copies its PDS target, builds through xrpc.f, drives
\ HBUF, admits the nonce, clears the token-bearing wire, and passes the
\ retained body through the production getSession DID gate.

REQUIRE at-xrpc-auth-read-test.f

PROVIDED at-xrpc-exchange-test

4096 CONSTANT _ATXET-BODY-CAPACITY
16 CONSTANT _ATXET-POLL-LIMIT

VARIABLE _atxet-owner
VARIABLE _atxet-request-a
VARIABLE _atxet-body-a
VARIABLE _atxet-work

CREATE _atxet-target-store HTARGET-SIZE 7 + ALLOT
CREATE _atxet-op-store XIO-OP-SIZE 7 + ALLOT
CREATE _atxet-json 128 ALLOT
VARIABLE _atxet-json-u

: _atxet-target  ( -- target )
    _atxet-target-store 7 + -8 AND ;

: _atxet-op  ( -- operation )
    _atxet-op-store 7 + -8 AND ;

: _atxet-body$  ( -- address length )
    _atxet-json _atxet-json-u @ ;

: _atxet-json-c!  ( byte -- )
    _atxet-json _atxet-json-u @ + C!
    1 _atxet-json-u +! ;

: _atxet-json+  ( address length -- )
    DUP >R
    _atxet-json _atxet-json-u @ + SWAP CMOVE
    R> _atxet-json-u +! ;

: _atxet-build-json  ( -- )
    _atxet-json 128 0 FILL
    0 _atxet-json-u !
    123 _atxet-json-c!
    34 _atxet-json-c!
    S" handle" _atxet-json+
    34 _atxet-json-c!
    58 _atxet-json-c!
    34 _atxet-json-c!
    S" alice.test" _atxet-json+
    34 _atxet-json-c!
    44 _atxet-json-c!
    34 _atxet-json-c!
    S" did" _atxet-json+
    34 _atxet-json-c!
    58 _atxet-json-c!
    34 _atxet-json-c!
    S" did:plc:abcdefghijklmnopqrstuvwx" _atxet-json+
    34 _atxet-json-c!
    125 _atxet-json-c! ;

: _atxet-allocate  ( size variable -- )
    >R
    ALLOCATE ABORT" AT XRPC exchange allocation"
    R> ! ;

: _atxet-free  ( variable -- )
    DUP @ ?DUP IF
        FREE
        0 SWAP !
    ELSE
        DROP
    THEN ;

: _atxet-build-response  ( -- )
    _atxet-build-json
    _atxr-response _ATXR-RESPONSE-CAPACITY 0 FILL
    0 _atxr-response-u !
    0 _atxr-response-pos !
    S" HTTP/1.1 200 OK" _atxr-response-append
    _atxr-response-crlf
    S" Content-Type: application/json" _atxr-response-append
    _atxr-response-crlf
    S" DPoP-Nonce: pds-nonce-1" _atxr-response-append
    _atxr-response-crlf
    S" Content-Length: " _atxr-response-append
    _atxet-body$ NIP NUM>STR _atxr-response-append
    _atxr-response-crlf
    S" Connection: close" _atxr-response-append
    _atxr-response-crlf
    _atxr-response-crlf
    _atxet-body$ _atxr-response-append ;

: _atxet-install-port  ( -- )
    _atxet-owner @ AT-XRPC-EXCHANGE-PORT DUP NIO-INIT
    DUP DUP NIO.CONTEXT !
    ['] _atxr-open OVER NIO.OPEN-START-XT !
    ['] _atxr-open OVER NIO.OPEN-POLL-XT !
    ['] _atxr-send OVER NIO.SEND-XT !
    ['] _atxr-recv OVER NIO.RECV-XT !
    ['] _atxr-poll OVER NIO.POLL-XT !
    ['] _atxr-cancel OVER NIO.CANCEL-XT !
    ['] _atxr-close OVER NIO.CLOSE-START-XT !
    ['] _atxr-close SWAP NIO.CLOSE-POLL-XT ! ;

VARIABLE _atxet-step
VARIABLE _atxet-polls

: _atxet-drive  ( -- )
    _atxet-op _atxet-owner @ AT-XRPC-EXCHANGE-XIO-START
    DUP XIO-STEP-PENDING <> IF
        ." AT XRPC EXCHANGE START step/status/state/error "
        DUP .
        _atxet-owner @ AT-XRPC-EXCHANGE-LAST-STATUS@ .
        _atxet-owner @ AT-XRPC-EXCHANGE-STATE@ DROP .
        _atxet-op XIOO.ERROR @ . CR
        TX-FLUSH
    THEN
    XIO-STEP-PENDING _atxr-status
    0 _atxet-polls !
    BEGIN
        _atxet-op _atxet-owner @ AT-XRPC-EXCHANGE-XIO-POLL
        DUP _atxet-step !
        XIO-STEP-PENDING =
    WHILE
        1 _atxet-polls +!
        _atxet-polls @ _ATXET-POLL-LIMIT >= IF
            0 _atxr-assert EXIT
        THEN
    REPEAT
    _atxet-step @ XIO-STEP-SUCCEEDED = _atxr-assert ;

: _atxet-prepare  ( -- )
    AT-XRPC-EXCHANGE-SIZE _atxet-owner _atxet-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
        _atxet-request-a _atxet-allocate
    _ATXET-BODY-CAPACITY _atxet-body-a _atxet-allocate
    AT-GETSESSION-WORKSPACE-SIZE _atxet-work _atxet-allocate

    _atxet-request-a @ AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atxet-body-a @ _ATXET-BODY-CAPACITY
    _atxet-owner @ AT-XRPC-EXCHANGE-INIT
    AT-XRPC-EXCHANGE-S-OK _atxr-status

    _atxr-active-vault @
    _atoct-config
    _atopt-profile
    _atxr-active-session @
    _atxet-owner @ AT-XRPC-EXCHANGE-BIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status

    S" https://pds.example/xrpc/com.atproto.server.getSession"
    _atxet-target HTARGET-PARSE
    HTARGET-S-OK _atxr-status
    _ATXR-IAT _atxet-target 0 0 _atxet-owner @
    AT-XRPC-EXCHANGE-PREPARE
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atxet-op XIO-OP-INIT
    _atxet-install-port ;

: _atxet-check-ready  ( -- )
    _atxet-owner @ AT-XRPC-EXCHANGE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-STATE-READY = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-HTTP-CODE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    200 = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-ATTEMPTS@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    1 = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-NONCE-GENERATION@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    1 = _atxr-assert

    _atxet-owner @ AT-XRPC-EXCHANGE-BODY@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    2DUP _atxet-body$ COMPARE 0= _atxr-assert
    _atopt-profile _atxet-work @ AT-GETSESSION-ADMIT
    AT-GETSESSION-S-OK _atxr-status
    _atxet-work @ AT-GETSESSION-WORKSPACE-SIZE
    _atxr-zero? _atxr-assert

    _atxet-request-a @ AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atxr-zero? _atxr-assert
    _atxr-sent @ _atxr-sent-u @
    S" Authorization: DPoP access-vertical"
    _atxr-contains? _atxr-assert
    _atxr-sent @ _atxr-sent-u @
    S" DPoP: deterministic-dpop-proof"
    _atxr-contains? _atxr-assert
    _O2PKD-DPOP-CALLS @ 1 = _atxr-assert
    _O2PKD-DPOP-NONCE-A @ 0= _atxr-assert
    _O2PKD-DPOP-NONCE-U @ 0= _atxr-assert ;

: _ATXET-QUALIFY  ( -- )
    _atxet-prepare
    _atxet-build-response
    _atxr-sent @ _ATXR-REQUEST-CAPACITY 0 FILL
    0 _atxr-sent-u !
    _atxet-drive
    _atxet-check-ready
    _atxet-op _atxet-owner @ AT-XRPC-EXCHANGE-XIO-WIPE
    _atxet-owner @ AT-XRPC-EXCHANGE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-STATE-BOUND = _atxr-assert
    _atxet-body-a @ _ATXET-BODY-CAPACITY
    _atxr-zero? _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-UNBIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atxr-stack ;

: _ATXET-FINISH  ( -- )
    _atxet-target HTARGET-SIZE 0 FILL
    _atxet-op XIO-OP-SIZE 0 FILL
    _atxet-json 128 0 FILL
    0 _atxet-json-u !
    _atxet-work @ ?DUP IF
        AT-GETSESSION-WORKSPACE-SIZE 0 FILL
    THEN
    _atxet-body-a @ ?DUP IF
        _ATXET-BODY-CAPACITY 0 FILL
    THEN
    _atxet-request-a @ ?DUP IF
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 0 FILL
    THEN
    _atxet-owner @ ?DUP IF
        AT-XRPC-EXCHANGE-SIZE 0 FILL
    THEN
    _atxet-work _atxet-free
    _atxet-body-a _atxet-free
    _atxet-request-a _atxet-free
    _atxet-owner _atxet-free
    _ATXR-FINISH ;
