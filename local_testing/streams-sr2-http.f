\ streams-sr2-http.f - first executable SR2 HTTP route gate

PROVIDED akashic-streams-sr2-http-route-contracts

VARIABLE _sr2h-fails
VARIABLE _sr2h-checks
VARIABLE _sr2h-depth
VARIABLE _sr2h-stage

: _sr2h-assert  ( flag -- )
    1 _sr2h-checks +!
    0= IF
        1 _sr2h-fails +!
        ." STREAMS SR2 HTTP ROUTE ASSERT "
        _sr2h-stage @ . _sr2h-checks @ . CR
    THEN ;

: _sr2h-stack  ( -- )
    DEPTH DUP _sr2h-depth @ <> IF
        ." STREAMS SR2 HTTP ROUTE STACK "
        _sr2h-stage @ . _sr2h-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr2h-depth @ = _sr2h-assert ;

: _sr2h-span=  ( a1 u1 a2 u2 -- flag )
    COMPARE 0= ;

: _sr2h-zero-span?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ ---------------------------------------------------------------------
\ Caller-owned bounded fixture storage
\ ---------------------------------------------------------------------

512 CONSTANT _SR2H-REQUEST-CAPACITY
256 CONSTANT _SR2H-RESPONSE-HEADER-CAPACITY
 32 CONSTANT _SR2H-RESPONSE-SEND-CAPACITY
 64 CONSTANT _SR2H-RX-CAPACITY
256 CONSTANT _SR2H-CAPTURE-CAPACITY
512 CONSTANT _SR2H-INPUT-CAPACITY
256 CONSTANT _SR2H-EXPECTED-CAPACITY
 64 CONSTANT _SR2H-JSON-CAPACITY

CREATE _sr2h-input-connector STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr2h-output-connector STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr2h-flow STREAMS-FLOW-SIZE ALLOT
CREATE _sr2h-ingress STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2h-egress STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2h-ingress-segment STREAMS-PAYLOAD-SEGMENT-SIZE ALLOT
CREATE _sr2h-egress-segment STREAMS-PAYLOAD-SEGMENT-SIZE ALLOT
CREATE _sr2h-ingress-bytes STREAMS-RUNTIME-SEGMENT-BYTES ALLOT
CREATE _sr2h-egress-bytes STREAMS-RUNTIME-SEGMENT-BYTES ALLOT
CREATE _sr2h-flow-operation
    STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-RUNTIME-OPERATION-CAPACITY ALLOT
CREATE _sr2h-pool-entry STREAMS-EXECUTION-ENTRY-SIZE ALLOT
CREATE _sr2h-pool STREAMS-EXECUTION-POOL-SIZE ALLOT
CREATE _sr2h-config STREAMS-HTTP-ROUTE-CONFIG-SIZE ALLOT

CREATE _sr2h-router-entry HROUTER-ENTRY-SIZE ALLOT
CREATE _sr2h-router-arena 64 ALLOT
CREATE _sr2h-router HROUTER-SIZE ALLOT
CREATE _sr2h-match HROUTER-MATCH-SIZE ALLOT
CREATE _sr2h-request WEB-HTTP-REQUEST-STREAM-SIZE ALLOT
CREATE _sr2h-request-header _SR2H-REQUEST-CAPACITY ALLOT
CREATE _sr2h-response HTTP-RESPONSE-WRITER-SIZE ALLOT
CREATE _sr2h-response-header _SR2H-RESPONSE-HEADER-CAPACITY ALLOT
CREATE _sr2h-response-send _SR2H-RESPONSE-SEND-CAPACITY ALLOT
CREATE _sr2h-port NET-IO-PORT-SIZE ALLOT
CREATE _sr2h-rx _SR2H-RX-CAPACITY ALLOT
CREATE _sr2h-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE ALLOT
CREATE _sr2h-authority 32 ALLOT
CREATE _sr2h-connection HTTP-CONNECTION-OWNER-SIZE ALLOT

CREATE _sr2h-input _SR2H-INPUT-CAPACITY ALLOT
CREATE _sr2h-capture _SR2H-CAPTURE-CAPACITY ALLOT
CREATE _sr2h-expected _SR2H-EXPECTED-CAPACITY ALLOT
CREATE _sr2h-request-json _SR2H-JSON-CAPACITY ALLOT
CREATE _sr2h-response-json _SR2H-JSON-CAPACITY ALLOT
CREATE _sr2h-transform-copy _SR2H-JSON-CAPACITY ALLOT
CREATE _sr2h-source-copy _SR2H-JSON-CAPACITY ALLOT

VARIABLE _sr2h-input-u
VARIABLE _sr2h-input-position
VARIABLE _sr2h-capture-u
VARIABLE _sr2h-expected-u
VARIABLE _sr2h-request-json-u
VARIABLE _sr2h-response-json-u
VARIABLE _sr2h-recv-calls
VARIABLE _sr2h-send-calls
VARIABLE _sr2h-steps
VARIABLE _sr2h-now
VARIABLE _sr2h-metadata-calls
VARIABLE _sr2h-source-probed
VARIABLE _sr2h-transforms
VARIABLE _sr2h-output-starts
VARIABLE _sr2h-output-polls
VARIABLE _sr2h-output-cancels
VARIABLE _sr2h-output-cleanups
VARIABLE _sr2h-cb-result
VARIABLE _sr2h-transform-event
VARIABLE _sr2h-transform-output
VARIABLE _sr2h-transform-result
VARIABLE _sr2h-io-a
VARIABLE _sr2h-io-u
VARIABLE _sr2h-io-take

\ ---------------------------------------------------------------------
\ Exact request and response bytes
\ ---------------------------------------------------------------------

: _sr2h-request-json+  ( source-a source-u -- )
    DUP IF
        2DUP
        _sr2h-request-json _sr2h-request-json-u @ + SWAP CMOVE
        DUP _sr2h-request-json-u +!
    THEN
    2DROP ;

: _sr2h-request-json-c+  ( c -- )
    _sr2h-request-json _sr2h-request-json-u @ + C!
    1 _sr2h-request-json-u +! ;

: _sr2h-response-json+  ( source-a source-u -- )
    DUP IF
        2DUP
        _sr2h-response-json _sr2h-response-json-u @ + SWAP CMOVE
        DUP _sr2h-response-json-u +!
    THEN
    2DROP ;

: _sr2h-response-json-c+  ( c -- )
    _sr2h-response-json _sr2h-response-json-u @ + C!
    1 _sr2h-response-json-u +! ;

: _sr2h-input+  ( source-a source-u -- )
    DUP IF
        2DUP _sr2h-input _sr2h-input-u @ + SWAP CMOVE
        DUP _sr2h-input-u +!
    THEN
    2DROP ;

: _sr2h-input-c+  ( c -- )
    _sr2h-input _sr2h-input-u @ + C!
    1 _sr2h-input-u +! ;

: _sr2h-input-crlf  ( -- )
    13 _sr2h-input-c+ 10 _sr2h-input-c+ ;

: _sr2h-expected+  ( source-a source-u -- )
    DUP IF
        2DUP _sr2h-expected _sr2h-expected-u @ + SWAP CMOVE
        DUP _sr2h-expected-u +!
    THEN
    2DROP ;

: _sr2h-expected-c+  ( c -- )
    _sr2h-expected _sr2h-expected-u @ + C!
    1 _sr2h-expected-u +! ;

: _sr2h-expected-crlf  ( -- )
    13 _sr2h-expected-c+ 10 _sr2h-expected-c+ ;

: _sr2h-build-json  ( -- )
    0 _sr2h-request-json-u !
    [CHAR] { _sr2h-request-json-c+
    34 _sr2h-request-json-c+ S" event" _sr2h-request-json+
    34 _sr2h-request-json-c+ [CHAR] : _sr2h-request-json-c+
    34 _sr2h-request-json-c+ S" demo" _sr2h-request-json+
    34 _sr2h-request-json-c+ [CHAR] , _sr2h-request-json-c+
    34 _sr2h-request-json-c+ S" value" _sr2h-request-json+
    34 _sr2h-request-json-c+ [CHAR] : _sr2h-request-json-c+
    [CHAR] 7 _sr2h-request-json-c+ [CHAR] } _sr2h-request-json-c+
    _sr2h-request-json-u @ 26 = _sr2h-assert

    0 _sr2h-response-json-u !
    [CHAR] { _sr2h-response-json-c+
    34 _sr2h-response-json-c+ S" accepted" _sr2h-response-json+
    34 _sr2h-response-json-c+ [CHAR] : _sr2h-response-json-c+
    S" true" _sr2h-response-json+
    [CHAR] } _sr2h-response-json-c+
    _sr2h-response-json-u @ 17 = _sr2h-assert ;

: _sr2h-build-request  ( -- )
    0 _sr2h-input-u !
    S" POST /hooks/demo HTTP/1.1" _sr2h-input+ _sr2h-input-crlf
    S" Host: demo.test" _sr2h-input+ _sr2h-input-crlf
    S" Content-Type: application/json" _sr2h-input+ _sr2h-input-crlf
    S" Content-Length: 26" _sr2h-input+ _sr2h-input-crlf
    _sr2h-input-crlf
    _sr2h-request-json _sr2h-request-json-u @ _sr2h-input+
    _sr2h-input-u @ _SR2H-INPUT-CAPACITY <= _sr2h-assert ;

: _sr2h-build-expected  ( -- )
    0 _sr2h-expected-u !
    S" HTTP/1.1 200 OK" _sr2h-expected+ _sr2h-expected-crlf
    S" Content-Type: application/json"
        _sr2h-expected+ _sr2h-expected-crlf
    S" Content-Length: 17" _sr2h-expected+ _sr2h-expected-crlf
    S" Connection: close" _sr2h-expected+ _sr2h-expected-crlf
    _sr2h-expected-crlf
    _sr2h-response-json _sr2h-response-json-u @ _sr2h-expected+
    _sr2h-expected-u @ 107 = _sr2h-assert ;

\ ---------------------------------------------------------------------
\ Streams callbacks and runtime
\ ---------------------------------------------------------------------

: _sr2h-result!
  ( completion effect detail error result -- )
    >R
    R@ SCRR.ERROR !
    R@ SCRR.DETAIL !
    R@ SCRR.EFFECT !
    R> SCRR.COMPLETION ! ;

: _sr2h-transform-result!
  ( completion output-u detail error result -- )
    >R
    R@ STRR.ERROR !
    R@ STRR.DETAIL !
    R@ STRR.OUTPUT-U !
    R> STRR.COMPLETION ! ;

: _sr2h-transform  ( ingress-event output-carrier context result -- )
    _sr2h-transform-result !
    DROP
    _sr2h-transform-output !
    _sr2h-transform-event !
    1 _sr2h-transforms +!
    _sr2h-pool STREAMS-EXECUTION-POOL-ACTIVE@ 1 =
        _sr2h-assert
    _sr2h-transform-copy _SR2H-JSON-CAPACITY
    _sr2h-transform-event @ STREAMS-EVENT-PAYLOAD-COPY
        STREAMS-FLOW-S-OK = _sr2h-assert
    DUP _sr2h-request-json-u @ = _sr2h-assert
    _sr2h-transform-copy SWAP
    _sr2h-request-json _sr2h-request-json-u @
        _sr2h-span= _sr2h-assert
    _sr2h-response-json _sr2h-response-json-u @
    _sr2h-transform-output @ SPAY.GENERATION @
    _sr2h-transform-output @ STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2h-assert
    STREAMS-TRANSFORM-COMPLETION-OK
    _sr2h-response-json-u @ 0 0
    _sr2h-transform-result @ _sr2h-transform-result! ;

: _sr2h-output-start  ( egress-event operation context result -- )
    _sr2h-cb-result !
    DROP 2DROP
    1 _sr2h-output-starts +!
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr2h-cb-result @ _sr2h-result! ;

: _sr2h-output-poll  ( egress-event operation context result -- )
    _sr2h-cb-result !
    DROP 2DROP
    1 _sr2h-output-polls +!
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr2h-cb-result @ _sr2h-result! ;

: _sr2h-output-cancel  ( egress-event operation context result -- )
    _sr2h-cb-result !
    DROP 2DROP
    1 _sr2h-output-cancels +!
    STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED 0 0
    _sr2h-cb-result @ _sr2h-result! ;

: _sr2h-output-cleanup  ( egress-event operation context -- error )
    2DROP DROP
    1 _sr2h-output-cleanups +!
    0 ;

: _sr2h-connector-identity  ( id-byte endpoint-byte connector -- )
    >R
    DUP R@ SCON.ENDPOINT-ID RID-SIZE ROT FILL
    DROP
    R> SCON.ID RID-SIZE ROT FILL ;

: _sr2h-setup-connectors  ( -- )
    _sr2h-input-connector STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2h-assert
    0x41 0x51 _sr2h-input-connector _sr2h-connector-identity
    1 _sr2h-input-connector SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT
        _sr2h-input-connector SCON.DIRECTION !
    401 _sr2h-input-connector SCON.PROTOCOL !
    _sr2h-input-connector STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr2h-assert

    _sr2h-output-connector STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2h-assert
    0x42 0x52 _sr2h-output-connector _sr2h-connector-identity
    1 _sr2h-output-connector SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT
        _sr2h-output-connector SCON.DIRECTION !
    402 _sr2h-output-connector SCON.PROTOCOL !
    16 _sr2h-output-connector SCON.OP-SIZE !
    ['] _sr2h-output-start _sr2h-output-connector SCON.START-XT !
    ['] _sr2h-output-poll _sr2h-output-connector SCON.POLL-XT !
    ['] _sr2h-output-cancel _sr2h-output-connector SCON.CANCEL-XT !
    ['] _sr2h-output-cleanup _sr2h-output-connector SCON.CLEANUP-XT !
    _sr2h-output-connector STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr2h-assert ;

: _sr2h-close-carrier  ( carrier -- )
    DUP _SPAY-HEADER? 0= IF DROP EXIT THEN
    DUP SPAY.STATE @ STREAMS-PAYLOAD-STATE-CLOSED = IF DROP EXIT THEN
    DUP SPAY.GENERATION @ SWAP STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2h-assert ;

: _sr2h-setup-runtime  ( -- )
    0 _sr2h-transforms !
    0 _sr2h-output-starts !
    0 _sr2h-output-polls !
    0 _sr2h-output-cancels !
    0 _sr2h-output-cleanups !
    _sr2h-ingress _sr2h-close-carrier
    _sr2h-egress _sr2h-close-carrier
    _sr2h-ingress-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2h-ingress-segment STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2h-assert
    _sr2h-egress-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2h-egress-segment STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2h-assert
    _sr2h-ingress-segment 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2h-ingress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2h-assert
    _sr2h-egress-segment 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2h-egress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2h-assert

    _sr2h-flow STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK = _sr2h-assert
    STREAMS-RUNTIME-PROFILE-COMPACT
        _sr2h-ingress _sr2h-egress _sr2h-flow-operation
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2h-flow STREAMS-FLOW-WORKSPACE!
        STREAMS-FLOW-S-OK = _sr2h-assert
    _sr2h-flow SFLOW.ID RID-SIZE 0x61 FILL
    7 _sr2h-flow SFLOW.REVISION !
    1000 _sr2h-flow SFLOW.TIMEOUT-MS !
    _sr2h-input-connector _sr2h-flow SFLOW.INPUT-CONNECTOR !
    _sr2h-output-connector _sr2h-flow SFLOW.OUTPUT-CONNECTOR !
    ['] _sr2h-transform _sr2h-flow SFLOW.TRANSFORM-XT !
    STREAMS-HTTP-ROUTE-MEDIA-JSON _sr2h-flow SFLOW.OUTPUT-MEDIA !
    _sr2h-flow STREAMS-FLOW-SEAL
        STREAMS-FLOW-S-OK = _sr2h-assert

    _sr2h-pool-entry 1 _sr2h-pool STREAMS-EXECUTION-POOL-INIT
        STREAMS-FLOW-S-OK = _sr2h-assert
    _sr2h-flow _sr2h-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK = _sr2h-assert
    _sr2h-pool STREAMS-EXECUTION-POOL-SEAL
        STREAMS-FLOW-S-OK = _sr2h-assert
    _sr2h-pool STREAMS-EXECUTION-POOL-CAPACITY@ 1 =
        _sr2h-assert ;

: _sr2h-clock  ( context -- now status )
    DROP
    1 _sr2h-now +!
    _sr2h-now @ 0 ;

: _sr2h-metadata  ( exchange event context -- status )
    1 _sr2h-metadata-calls +!
    DROP NIP >R
    R@ SEVT.EVENT-ID RID-SIZE 0x71 FILL
    R@ SEVT.CORRELATION-ID RID-SIZE 0x72 FILL
    R@ SEVT.IDEMPOTENCY-ID RID-SIZE 0x73 FILL
    STREAMS-HTTP-ROUTE-MEDIA-JSON R@ SEVT.MEDIA !
    1 R@ SEVT.SEQUENCE !
    R> DROP 0 ;

: _sr2h-setup-route  ( -- )
    0 _sr2h-now !
    0 _sr2h-metadata-calls !
    _sr2h-pool _sr2h-input-connector
    _sr2h-response-json-u @
    0 ['] _sr2h-clock
    0 ['] _sr2h-metadata
    _sr2h-config STREAMS-HTTP-ROUTE-CONFIG-INIT
        STREAMS-HTTP-ROUTE-S-OK = _sr2h-assert
    _sr2h-router-entry 1 _sr2h-router-arena 64 _sr2h-router
        HROUTER-INIT HROUTER-S-OK = _sr2h-assert
    _sr2h-config _sr2h-router STREAMS-HTTP-DEMO-ROUTE-ADD
        HROUTER-S-OK = _sr2h-assert
    _sr2h-router HROUTER-SEAL HROUTER-S-OK = _sr2h-assert ;

\ ---------------------------------------------------------------------
\ Fragmented transport and complete connection journey
\ ---------------------------------------------------------------------

: _sr2h-recv  ( buffer capacity context -- count io-status )
    DROP
    _sr2h-io-u !
    _sr2h-io-a !
    _sr2h-input-position @ _sr2h-input-u @ >= IF
        0 NIO-S-EOF EXIT
    THEN
    1 _sr2h-recv-calls +!
    _sr2h-recv-calls @ 7 * 13 MOD 1+
    _sr2h-input-u @ _sr2h-input-position @ - MIN
    _sr2h-io-u @ MIN
    DUP _sr2h-io-take ! DROP
    _sr2h-input _sr2h-input-position @ +
    _sr2h-io-a @ _sr2h-io-take @ CMOVE
    _sr2h-io-take @ _sr2h-input-position +!
    _sr2h-io-take @ NIO-S-OK ;

: _sr2h-probe-response-source  ( -- )
    _sr2h-route-operation STREAMS-HTTP-ROUTE-STATE@
        STREAMS-HTTP-ROUTE-STATE-RESPONSE = _sr2h-assert
    _sr2h-route-operation STREAMS-HTTP-ROUTE-LEASED?
        _sr2h-assert
    _sr2h-flow SFLOW.STATE @ STREAMS-FLOW-STATE-TERMINAL =
        _sr2h-assert
    _sr2h-egress SPAY.STATE @ STREAMS-PAYLOAD-STATE-SEALED =
        _sr2h-assert
    _sr2h-route-operation
        STREAMS-HTTP-ROUTE-PAYLOAD-GENERATION@
        _sr2h-egress STREAMS-PAYLOAD-EXACT? _sr2h-assert
    _sr2h-io-u @ _SR2H-JSON-CAPACITY <= _sr2h-assert
    _sr2h-io-a @ _sr2h-transform-copy _sr2h-io-u @ CMOVE
    0 _sr2h-response-send 5 _sr2h-route-operation
        STREAMS-HTTP-ROUTE-RESPONSE-READ
        HRESP-SOURCE-S-OK = _sr2h-assert
    5 = _sr2h-assert
    _sr2h-response-send _sr2h-source-copy 5 CMOVE
    5 _sr2h-response-send 12 _sr2h-route-operation
        STREAMS-HTTP-ROUTE-RESPONSE-READ
        HRESP-SOURCE-S-OK = _sr2h-assert
    12 = _sr2h-assert
    _sr2h-response-send _sr2h-source-copy 5 + 12 CMOVE
    _sr2h-source-copy _sr2h-response-json-u @
    _sr2h-response-json _sr2h-response-json-u @
        _sr2h-span= _sr2h-assert
    _sr2h-transform-copy _sr2h-io-a @ _sr2h-io-u @ CMOVE
    -1 _sr2h-source-probed ! ;

: _sr2h-send  ( buffer length context -- count io-status )
    DROP
    _sr2h-io-u !
    _sr2h-io-a !
    1 _sr2h-send-calls +!
    _sr2h-source-probed @ 0=
    _sr2h-io-a @ _sr2h-response-send = AND IF
        _sr2h-probe-response-source
    THEN
    _sr2h-io-u @ 9 MIN DUP _sr2h-io-take ! DROP
    _sr2h-capture-u @ _sr2h-io-take @ +
        _SR2H-CAPTURE-CAPACITY <= _sr2h-assert
    _sr2h-io-a @
    _sr2h-capture _sr2h-capture-u @ +
    _sr2h-io-take @ CMOVE
    _sr2h-io-take @ _sr2h-capture-u +!
    _sr2h-io-take @ NIO-S-OK ;

: _sr2h-port-cancel  ( context -- )
    DROP ;

: _sr2h-port-close  ( context -- )
    DROP ;

: _sr2h-setup-http  ( -- )
    0 _sr2h-input-position !
    0 _sr2h-capture-u !
    0 _sr2h-recv-calls !
    0 _sr2h-send-calls !
    0 _sr2h-steps !
    0 _sr2h-source-probed !
    _sr2h-request-header _SR2H-REQUEST-CAPACITY
    STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY
    0 0 _sr2h-request WREQ-INIT
        WREQ-S-PENDING = _sr2h-assert
    _sr2h-response-header _SR2H-RESPONSE-HEADER-CAPACITY
    _sr2h-response-send _SR2H-RESPONSE-SEND-CAPACITY
    _sr2h-response HRESP-INIT HRESP-S-OK = _sr2h-assert
    _sr2h-port NIO-INIT
    ['] _sr2h-recv _sr2h-port NIO.RECV-XT !
    ['] _sr2h-send _sr2h-port NIO.SEND-XT !
    ['] _sr2h-port-cancel _sr2h-port NIO.CANCEL-XT !
    ['] _sr2h-port-close _sr2h-port NIO.CLOSE-XT !
    NIO-OPEN-STATE-OPEN _sr2h-port NIO.OPEN-STATE !
    NIO-S-OK _sr2h-port NIO.OPEN-STATUS !
    S" demo.test" _sr2h-authority SWAP CMOVE
    _sr2h-request _sr2h-response _sr2h-match _sr2h-router
    _sr2h-port _sr2h-rx _SR2H-RX-CAPACITY
    _sr2h-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
    _sr2h-authority 9 _sr2h-connection HCONN-INIT
        HCONN-S-PENDING = _sr2h-assert ;

: _sr2h-test-complete-post  ( -- )
    100 _sr2h-stage !
    _sr2h-setup-http
    _sr2h-connection HCONN-START HCONN-S-PENDING =
        _sr2h-assert
    512 0 ?DO
        _sr2h-connection HCONN-TERMINAL? 0= IF
            _sr2h-connection HCONN-STEP DROP
            1 _sr2h-steps +!
        THEN
    LOOP
    101 _sr2h-stage !
    _sr2h-connection HCONN-TERMINAL? _sr2h-assert
    _sr2h-connection HCONN-RESULT@ HCONN-S-DONE =
        _sr2h-assert
    _sr2h-connection HCONN-HTTP-STATUS@ 200 = _sr2h-assert
    _sr2h-connection HCONN-CLEANUP-ERROR@ 0= _sr2h-assert
    _sr2h-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-RESPONSE = _sr2h-assert
    _sr2h-capture-u @ _sr2h-expected-u @ = _sr2h-assert
    _sr2h-capture _sr2h-capture-u @
    _sr2h-expected _sr2h-expected-u @
        _sr2h-span= _sr2h-assert
    _sr2h-input-position @ _sr2h-input-u @ = _sr2h-assert
    _sr2h-recv-calls @ 10 > _sr2h-assert
    _sr2h-send-calls @ 8 > _sr2h-assert
    _sr2h-metadata-calls @ 1 = _sr2h-assert
    _sr2h-source-probed @ _sr2h-assert
    _sr2h-transforms @ 1 = _sr2h-assert
    _sr2h-output-starts @ 1 = _sr2h-assert
    _sr2h-output-polls @ 0= _sr2h-assert
    _sr2h-output-cancels @ 0= _sr2h-assert
    _sr2h-output-cleanups @ 1 = _sr2h-assert
    _sr2h-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
        _sr2h-assert
    _sr2h-flow SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2h-assert
    _sr2h-ingress SPAY.STATE @ STREAMS-PAYLOAD-STATE-BUILDING =
        _sr2h-assert
    _sr2h-egress SPAY.STATE @ STREAMS-PAYLOAD-STATE-BUILDING =
        _sr2h-assert
    _sr2h-ingress SPAY.BYTE-U @ 0= _sr2h-assert
    _sr2h-egress SPAY.BYTE-U @ 0= _sr2h-assert
    _sr2h-ingress-segment SPSEG.USED @ 0= _sr2h-assert
    _sr2h-egress-segment SPSEG.USED @ 0= _sr2h-assert
    _sr2h-ingress-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2h-zero-span? _sr2h-assert
    _sr2h-egress-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2h-zero-span? _sr2h-assert
    _sr2h-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
        _sr2h-zero-span? _sr2h-assert
    0 _sr2h-source-copy 1 _sr2h-route-operation
        STREAMS-HTTP-ROUTE-RESPONSE-READ
        HRESP-SOURCE-S-STALE = _sr2h-assert
    0= _sr2h-assert
    _sr2h-port NIO.CLOSE-STATE @ NIO-CLOSE-STATE-CLOSED =
        _sr2h-assert
    _sr2h-stack ;

: _SR2H-RUN  ( -- )
    0 _sr2h-fails !
    0 _sr2h-checks !
    DEPTH _sr2h-depth !
    1 _sr2h-stage !
    _sr2h-build-json
    _sr2h-build-request
    _sr2h-build-expected
    _sr2h-setup-connectors
    _sr2h-setup-runtime
    _sr2h-setup-route
    _sr2h-stack
    _sr2h-test-complete-post
    900 _sr2h-stage !
    _sr2h-stack
    _sr2h-fails @ 0= IF
        ." STREAMS SR2 HTTP ROUTE PASS "
        _sr2h-checks @ . CR
    ELSE
        ." STREAMS SR2 HTTP ROUTE FAIL "
        _sr2h-fails @ . ." / " _sr2h-checks @ . CR
    THEN ;
