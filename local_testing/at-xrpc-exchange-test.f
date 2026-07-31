\ Focused authenticated XRPC query/procedure exchange qualification.
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
512 CONSTANT _ATXET-POST-RESPONSE-CAPACITY
32 CONSTANT _ATXET-POLL-LIMIT
26 CONSTANT _ATXET-CHALLENGE-BYTES

VARIABLE _atxet-owner
VARIABLE _atxet-request-a
VARIABLE _atxet-body-a
VARIABLE _atxet-work

CREATE _atxet-target-store HTARGET-SIZE 7 + ALLOT
CREATE _atxet-op-store XIO-OP-SIZE 7 + ALLOT
CREATE _atxet-json 128 ALLOT
CREATE _atxet-post-response _ATXET-POST-RESPONSE-CAPACITY ALLOT
VARIABLE _atxet-json-u
VARIABLE _atxet-post-response-u
VARIABLE _atxet-post-response-pos
VARIABLE _atxet-first-response-u
VARIABLE _atxet-response-end
VARIABLE _atxet-open-count
VARIABLE _atxet-close-count
VARIABLE _atxet-request-start
VARIABLE _atxet-request1-u
VARIABLE _atxet-request2-u
VARIABLE _atxet-first-nonce-ok
VARIABLE _atxet-second-nonce-ok
VARIABLE _atxet-send-wire-ok
VARIABLE _atxet-loss-recv-calls

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

: _atxet-build-challenge-json  ( -- )
    _atxet-json 128 0 FILL
    0 _atxet-json-u !
    123 _atxet-json-c!
    34 _atxet-json-c!
    S" error" _atxet-json+
    34 _atxet-json-c!
    58 _atxet-json-c!
    34 _atxet-json-c!
    S" use_dpop_nonce" _atxet-json+
    34 _atxet-json-c!
    125 _atxet-json-c!
    _atxet-json-u @ _ATXET-CHALLENGE-BYTES = _atxr-assert ;

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

: _atxet-post-response+  ( address length -- )
    DUP _atxet-post-response-u @ +
    _ATXET-POST-RESPONSE-CAPACITY > IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atxet-post-response _atxet-post-response-u @ + SWAP CMOVE
    R> _atxet-post-response-u +! ;

: _atxet-post-response-crlf  ( -- )
    13 _atxet-post-response _atxet-post-response-u @ + C!
    1 _atxet-post-response-u +!
    10 _atxet-post-response _atxet-post-response-u @ + C!
    1 _atxet-post-response-u +! ;

: _atxet-build-post-responses  ( -- )
    _atxet-post-response _ATXET-POST-RESPONSE-CAPACITY 0 FILL
    0 _atxet-post-response-u !
    0 _atxet-post-response-pos !
    0 _atxet-response-end !

    _atxet-build-challenge-json
    S" HTTP/1.1 400 Bad Request" _atxet-post-response+
    _atxet-post-response-crlf
    S" Content-Type: application/json" _atxet-post-response+
    _atxet-post-response-crlf
    S" DPoP-Nonce: pds-nonce-1" _atxet-post-response+
    _atxet-post-response-crlf
    S" Content-Length: " _atxet-post-response+
    _ATXET-CHALLENGE-BYTES NUM>STR _atxet-post-response+
    _atxet-post-response-crlf
    S" Connection: close" _atxet-post-response+
    _atxet-post-response-crlf
    _atxet-post-response-crlf
    _atxet-body$ _atxet-post-response+
    _atxet-post-response-u @ _atxet-first-response-u !

    _atxet-build-json
    S" HTTP/1.1 200 OK" _atxet-post-response+
    _atxet-post-response-crlf
    S" Content-Type: application/json" _atxet-post-response+
    _atxet-post-response-crlf
    S" DPoP-Nonce: pds-nonce-2" _atxet-post-response+
    _atxet-post-response-crlf
    S" Content-Length: " _atxet-post-response+
    _atxet-body$ NIP NUM>STR _atxet-post-response+
    _atxet-post-response-crlf
    S" Connection: close" _atxet-post-response+
    _atxet-post-response-crlf
    _atxet-post-response-crlf
    _atxet-body$ _atxet-post-response+ ;

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

: _atxet-post-open  ( context -- io-status )
    DROP
    _atxr-sent-u @ _atxet-request-start !
    1 _atxet-open-count +!
    _atxet-open-count @ 1 = IF
        _atxet-first-response-u @
    ELSE
        _atxet-post-response-u @
    THEN
    _atxet-response-end !
    NIO-S-OK ;

: _atxet-post-send  ( buffer length context -- count io-status )
    DROP
    _atxr-io-u !
    _atxr-io-a !
    _atxr-sent-u @ _atxr-io-u @ +
    _ATXR-REQUEST-CAPACITY > IF
        0 NIO-S-FAILED EXIT
    THEN
    _atxr-io-a @
    _atxr-sent @ _atxr-sent-u @ +
    _atxr-io-u @ CMOVE
    _atxr-io-u @ _atxr-sent-u +!

    _atxet-owner @ AT-XRPC-EXCHANGE-WIRE-STATE@
    DUP AT-XRPC-EXCHANGE-S-OK = IF
        DROP AT-XRPC-EXCHANGE-WIRE-UNCERTAIN =
    ELSE
        2DROP 0
    THEN
    _atxet-send-wire-ok @ AND _atxet-send-wire-ok !
    _atxet-open-count @ 1 = IF
        _O2PKD-DPOP-NONCE-A @ 0=
        _O2PKD-DPOP-NONCE-U @ 0= AND
        _atxet-first-nonce-ok !
    THEN
    _atxet-open-count @ 2 = IF
        _O2PKD-DPOP-NONCE-A @ _O2PKD-DPOP-NONCE-U @
        S" pds-nonce-1" COMPARE 0=
        _atxet-second-nonce-ok !
    THEN
    _atxr-io-u @ NIO-S-OK ;

: _atxet-post-recv  ( buffer capacity context -- count io-status )
    DROP
    _atxr-io-u !
    _atxr-io-a !
    _atxet-response-end @ _atxet-post-response-pos @ -
    DUP 0= IF
        DROP 0 NIO-S-EOF EXIT
    THEN
    _atxr-io-u @ MIN _atxr-io-n !
    _atxet-post-response _atxet-post-response-pos @ +
    _atxr-io-a @ _atxr-io-n @ CMOVE
    _atxr-io-n @ _atxet-post-response-pos +!
    _atxr-io-n @ NIO-S-OK ;

: _atxet-post-close  ( context -- io-status )
    DROP
    _atxr-sent-u @ _atxet-request-start @ -
    _atxet-close-count @ 0= IF
        _atxet-request1-u !
    ELSE
        _atxet-request2-u !
    THEN
    1 _atxet-close-count +!
    NIO-S-OK ;

: _atxet-install-post-port  ( -- )
    _atxet-owner @ AT-XRPC-EXCHANGE-PORT DUP NIO-INIT
    DUP DUP NIO.CONTEXT !
    ['] _atxet-post-open OVER NIO.OPEN-START-XT !
    ['] _atxet-post-open OVER NIO.OPEN-POLL-XT !
    ['] _atxet-post-send OVER NIO.SEND-XT !
    ['] _atxet-post-recv OVER NIO.RECV-XT !
    ['] _atxr-poll OVER NIO.POLL-XT !
    ['] _atxr-cancel OVER NIO.CANCEL-XT !
    ['] _atxet-post-close OVER NIO.CLOSE-START-XT !
    ['] _atxet-post-close SWAP NIO.CLOSE-POLL-XT ! ;

: _atxet-loss-recv  ( buffer capacity context -- count io-status )
    2DROP DROP
    1 _atxet-loss-recv-calls +!
    0 NIO-S-FAILED ;

: _atxet-install-loss-port  ( -- )
    _atxet-owner @ AT-XRPC-EXCHANGE-PORT DUP NIO-INIT
    DUP DUP NIO.CONTEXT !
    ['] _atxr-open OVER NIO.OPEN-START-XT !
    ['] _atxr-open OVER NIO.OPEN-POLL-XT !
    ['] _atxr-send OVER NIO.SEND-XT !
    ['] _atxet-loss-recv OVER NIO.RECV-XT !
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
    _ATXR-IAT AT-XRPC-METHOD-GET _atxet-target 0 0 0 0
    _atxet-owner @
    AT-XRPC-EXCHANGE-PREPARE
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atxet-op XIO-OP-INIT
    _atxet-install-port ;

: _atxet-rebind  ( -- )
    _atxet-owner @ AT-XRPC-EXCHANGE-UNBIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atxr-active-vault @
    _atoct-config
    _atopt-profile
    _atxr-active-session @
    _atxet-owner @ AT-XRPC-EXCHANGE-BIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status ;

: _atxet-prepare-post  ( -- )
    _atxet-target HTARGET-INIT
    S" https://pds.example/xrpc/com.atproto.repo.createRecord"
    _atxet-target HTARGET-PARSE
    HTARGET-S-OK _atxr-status
    _ATXR-IAT AT-XRPC-METHOD-POST _atxet-target 0 0
    S" {}" _atxet-owner @
    AT-XRPC-EXCHANGE-PREPARE
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atxet-owner @ AT-XRPC-EXCHANGE-WIRE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-WIRE-NONE = _atxr-assert
    _atxet-op XIO-OP-INIT ;

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

: _atxet-check-post-request  ( request-a request-u -- )
    2DUP
    S" POST /xrpc/com.atproto.repo.createRecord HTTP/1.1"
    _atxr-contains? _atxr-assert
    2DUP S" Content-Type: application/json"
    _atxr-contains? _atxr-assert
    2DUP S" Content-Length: 2" _atxr-contains? _atxr-assert
    DUP 2 >= _atxr-assert
    2DUP + 2 - 2 S" {}" COMPARE 0= _atxr-assert
    2DROP ;

: _atxet-check-post-ready  ( -- )
    _atxet-owner @ AT-XRPC-EXCHANGE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-STATE-READY = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-ATTEMPTS@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    2 = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-NONCE-GENERATION@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    2 = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-WIRE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-WIRE-RESPONSE = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-BODY@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atxet-body$ COMPARE 0= _atxr-assert

    _atxet-open-count @ 2 = _atxr-assert
    _atxet-close-count @ 2 = _atxr-assert
    _atxet-first-nonce-ok @ _atxr-assert
    _atxet-second-nonce-ok @ _atxr-assert
    _atxet-send-wire-ok @ _atxr-assert
    _O2PKD-DPOP-CALLS @ 2 = _atxr-assert
    _O2PKD-DPOP-HTM-A @ _O2PKD-DPOP-HTM-U @
    S" POST" COMPARE 0= _atxr-assert

    _atxr-sent @ _atxet-request1-u @
    _atxet-check-post-request
    _atxr-sent @ _atxet-request1-u @ + _atxet-request2-u @
    _atxet-check-post-request
    _atxet-request-a @ AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atxr-zero? _atxr-assert ;

: _atxet-drive-loss  ( -- )
    _atxet-op _atxet-owner @ AT-XRPC-EXCHANGE-XIO-START
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
    _atxet-step @ XIO-STEP-FAILED = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-LAST-STATUS@
    AT-XRPC-EXCHANGE-S-TRANSPORT = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-ATTEMPTS@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    1 = _atxr-assert
    _atxet-owner @ AT-XRPC-EXCHANGE-WIRE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-WIRE-UNCERTAIN = _atxr-assert
    _atxet-loss-recv-calls @ 1 = _atxr-assert
    _atxr-sent-u @ 0> _atxr-assert
    _atxr-sent @ _atxr-sent-u @ _atxet-check-post-request
    _O2PKD-DPOP-CALLS @ 1 = _atxr-assert
    _atxet-request-a @ AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atxr-zero? _atxr-assert ;

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

    \ Rebind to prove the JSON procedure starts with a fresh resource nonce.
    _atxet-rebind
    _atxet-prepare-post
    _atxet-build-post-responses
    _atxr-sent @ _ATXR-REQUEST-CAPACITY 0 FILL
    0 _atxr-sent-u !
    0 _atxet-open-count !
    0 _atxet-close-count !
    0 _atxet-request-start !
    0 _atxet-request1-u !
    0 _atxet-request2-u !
    0 _atxet-first-nonce-ok !
    0 _atxet-second-nonce-ok !
    -1 _atxet-send-wire-ok !
    _O2PKD-RESET
    _atxet-install-post-port
    _atxet-drive
    _atxet-check-post-ready
    _atxet-op _atxet-owner @ AT-XRPC-EXCHANGE-XIO-WIPE
    _atxet-owner @ ATXE.PAYLOAD-A @ 0= _atxr-assert
    _atxet-owner @ ATXE.PAYLOAD-U @ 0= _atxr-assert

    \ A response loss after the POST reaches NIO is terminal and uncertain;
    \ only the explicit nonce challenge above authorizes an automatic retry.
    _atxet-prepare-post
    _atxr-sent @ _ATXR-REQUEST-CAPACITY 0 FILL
    0 _atxr-sent-u !
    0 _atxet-loss-recv-calls !
    _O2PKD-RESET
    _atxet-install-loss-port
    _atxet-drive-loss
    _atxet-op _atxet-owner @ AT-XRPC-EXCHANGE-XIO-WIPE
    _atxet-owner @ ATXE.PAYLOAD-A @ 0= _atxr-assert
    _atxet-owner @ ATXE.PAYLOAD-U @ 0= _atxr-assert

    _atxet-owner @ AT-XRPC-EXCHANGE-UNBIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atxr-stack ;

: _ATXET-FINISH  ( -- )
    _atxet-target HTARGET-SIZE 0 FILL
    _atxet-op XIO-OP-SIZE 0 FILL
    _atxet-json 128 0 FILL
    0 _atxet-json-u !
    _atxet-post-response _ATXET-POST-RESPONSE-CAPACITY 0 FILL
    0 _atxet-post-response-u !
    0 _atxet-post-response-pos !
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
