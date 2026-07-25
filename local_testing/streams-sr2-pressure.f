\ streams-sr2-pressure.f - mixed-pool HTTP pressure gate for SR2

PROVIDED akashic-streams-sr2-http-pressure-contracts

VARIABLE _sr2p-fails
VARIABLE _sr2p-checks
VARIABLE _sr2p-depth
VARIABLE _sr2p-stage
VARIABLE _sr2p-expected-byte

: _sr2p-assert  ( flag -- )
    1 _sr2p-checks +!
    0= IF
        1 _sr2p-fails +!
        ." STREAMS SR2 HTTP PRESSURE ASSERT "
        _sr2p-stage @ . _sr2p-checks @ . CR
    THEN ;

: _sr2p-stack  ( -- )
    DEPTH DUP _sr2p-depth @ <> IF
        ." STREAMS SR2 HTTP PRESSURE STACK "
        _sr2p-stage @ . _sr2p-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr2p-depth @ = _sr2p-assert ;

: _sr2p-span=  ( a1 u1 a2 u2 -- flag )
    COMPARE 0= ;

: _sr2p-zero-span?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _sr2p-byte-span?  ( address length byte -- flag )
    _sr2p-expected-byte !
    0 ?DO
        DUP I + C@ _sr2p-expected-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _sr2p-segments-unused?  ( table count -- flag )
    0 ?DO
        DUP I STREAMS-PAYLOAD-SEGMENT-SIZE * +
            SPSEG.USED @ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ ---------------------------------------------------------------------
\ Exact caller-owned geometry and bounded fixture storage
\ ---------------------------------------------------------------------

512 CONSTANT _SR2P-REQUEST-CAPACITY
256 CONSTANT _SR2P-RESPONSE-HEADER-CAPACITY
 32 CONSTANT _SR2P-RESPONSE-SEND-CAPACITY
 64 CONSTANT _SR2P-RX-CAPACITY
 32 CONSTANT _SR2P-AUTHORITY-CAPACITY

512  CONSTANT _SR2P-SMALL-INPUT-CAPACITY
4600 CONSTANT _SR2P-LARGE-INPUT-CAPACITY
256  CONSTANT _SR2P-OVER-INPUT-CAPACITY
256  CONSTANT _SR2P-CAPTURE-CAPACITY
256  CONSTANT _SR2P-EXPECTED-CAPACITY
64   CONSTANT _SR2P-SMALL-JSON-CAPACITY
4097 CONSTANT _SR2P-LARGE-JSON-CAPACITY

CREATE _sr2p-input-connector STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr2p-output-connector STREAMS-CONNECTOR-SIZE ALLOT

CREATE _sr2p-compact-flow STREAMS-FLOW-SIZE ALLOT
CREATE _sr2p-compact-ingress STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2p-compact-egress STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2p-compact-in-segment STREAMS-PAYLOAD-SEGMENT-SIZE ALLOT
CREATE _sr2p-compact-out-segment STREAMS-PAYLOAD-SEGMENT-SIZE ALLOT
CREATE _sr2p-compact-in-bytes STREAMS-RUNTIME-SEGMENT-BYTES ALLOT
CREATE _sr2p-compact-out-bytes STREAMS-RUNTIME-SEGMENT-BYTES ALLOT
CREATE _sr2p-compact-operation
    STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-RUNTIME-OPERATION-CAPACITY ALLOT

CREATE _sr2p-standard-flow STREAMS-FLOW-SIZE ALLOT
CREATE _sr2p-standard-ingress STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2p-standard-egress STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2p-standard-in-segments
    STREAMS-PAYLOAD-SEGMENT-SIZE 4 * ALLOT
CREATE _sr2p-standard-out-segments
    STREAMS-PAYLOAD-SEGMENT-SIZE 4 * ALLOT
CREATE _sr2p-standard-in-bytes
    STREAMS-RUNTIME-SEGMENT-BYTES 4 * ALLOT
CREATE _sr2p-standard-out-bytes
    STREAMS-RUNTIME-SEGMENT-BYTES 4 * ALLOT
CREATE _sr2p-standard-operation
    STREAMS-RUNTIME-PROFILE-STANDARD
    STREAMS-RUNTIME-OPERATION-CAPACITY ALLOT

CREATE _sr2p-compact-context 8 ALLOT
CREATE _sr2p-standard-context 8 ALLOT
CREATE _sr2p-pool-entries STREAMS-EXECUTION-ENTRY-SIZE 2 * ALLOT
CREATE _sr2p-pool STREAMS-EXECUTION-POOL-SIZE ALLOT
CREATE _sr2p-config STREAMS-HTTP-ROUTE-CONFIG-SIZE ALLOT
CREATE _sr2p-router-entry HROUTER-ENTRY-SIZE ALLOT
CREATE _sr2p-router-arena 64 ALLOT
CREATE _sr2p-router HROUTER-SIZE ALLOT

\ Every connection below owns an independent request/parser, response writer,
\ transport, route operation, authority, match, and HCONN descriptor.
CREATE _sr2p-small-match HROUTER-MATCH-SIZE ALLOT
CREATE _sr2p-small-request WEB-HTTP-REQUEST-STREAM-SIZE ALLOT
CREATE _sr2p-small-request-header _SR2P-REQUEST-CAPACITY ALLOT
CREATE _sr2p-small-response HTTP-RESPONSE-WRITER-SIZE ALLOT
CREATE _sr2p-small-response-header _SR2P-RESPONSE-HEADER-CAPACITY ALLOT
CREATE _sr2p-small-response-send _SR2P-RESPONSE-SEND-CAPACITY ALLOT
CREATE _sr2p-small-port NET-IO-PORT-SIZE ALLOT
CREATE _sr2p-small-rx _SR2P-RX-CAPACITY ALLOT
CREATE _sr2p-small-route-operation
    STREAMS-HTTP-ROUTE-OPERATION-SIZE ALLOT
CREATE _sr2p-small-authority _SR2P-AUTHORITY-CAPACITY ALLOT
CREATE _sr2p-small-connection HTTP-CONNECTION-OWNER-SIZE ALLOT

CREATE _sr2p-large-match HROUTER-MATCH-SIZE ALLOT
CREATE _sr2p-large-request WEB-HTTP-REQUEST-STREAM-SIZE ALLOT
CREATE _sr2p-large-request-header _SR2P-REQUEST-CAPACITY ALLOT
CREATE _sr2p-large-response HTTP-RESPONSE-WRITER-SIZE ALLOT
CREATE _sr2p-large-response-header _SR2P-RESPONSE-HEADER-CAPACITY ALLOT
CREATE _sr2p-large-response-send _SR2P-RESPONSE-SEND-CAPACITY ALLOT
CREATE _sr2p-large-port NET-IO-PORT-SIZE ALLOT
CREATE _sr2p-large-rx _SR2P-RX-CAPACITY ALLOT
CREATE _sr2p-large-route-operation
    STREAMS-HTTP-ROUTE-OPERATION-SIZE ALLOT
CREATE _sr2p-large-authority _SR2P-AUTHORITY-CAPACITY ALLOT
CREATE _sr2p-large-connection HTTP-CONNECTION-OWNER-SIZE ALLOT

CREATE _sr2p-over-match HROUTER-MATCH-SIZE ALLOT
CREATE _sr2p-over-request WEB-HTTP-REQUEST-STREAM-SIZE ALLOT
CREATE _sr2p-over-request-header _SR2P-REQUEST-CAPACITY ALLOT
CREATE _sr2p-over-response HTTP-RESPONSE-WRITER-SIZE ALLOT
CREATE _sr2p-over-response-header _SR2P-RESPONSE-HEADER-CAPACITY ALLOT
CREATE _sr2p-over-response-send _SR2P-RESPONSE-SEND-CAPACITY ALLOT
CREATE _sr2p-over-port NET-IO-PORT-SIZE ALLOT
CREATE _sr2p-over-rx _SR2P-RX-CAPACITY ALLOT
CREATE _sr2p-over-route-operation
    STREAMS-HTTP-ROUTE-OPERATION-SIZE ALLOT
CREATE _sr2p-over-authority _SR2P-AUTHORITY-CAPACITY ALLOT
CREATE _sr2p-over-connection HTTP-CONNECTION-OWNER-SIZE ALLOT

CREATE _sr2p-small-input _SR2P-SMALL-INPUT-CAPACITY ALLOT
CREATE _sr2p-large-input _SR2P-LARGE-INPUT-CAPACITY ALLOT
CREATE _sr2p-over-input _SR2P-OVER-INPUT-CAPACITY ALLOT
CREATE _sr2p-small-capture _SR2P-CAPTURE-CAPACITY ALLOT
CREATE _sr2p-large-capture _SR2P-CAPTURE-CAPACITY ALLOT
CREATE _sr2p-over-capture _SR2P-CAPTURE-CAPACITY ALLOT
CREATE _sr2p-small-expected _SR2P-EXPECTED-CAPACITY ALLOT
CREATE _sr2p-large-expected _SR2P-EXPECTED-CAPACITY ALLOT
CREATE _sr2p-over-expected _SR2P-EXPECTED-CAPACITY ALLOT
CREATE _sr2p-small-request-json _SR2P-SMALL-JSON-CAPACITY ALLOT
CREATE _sr2p-small-response-json _SR2P-SMALL-JSON-CAPACITY ALLOT
CREATE _sr2p-large-request-json _SR2P-LARGE-JSON-CAPACITY ALLOT
CREATE _sr2p-large-response-json _SR2P-SMALL-JSON-CAPACITY ALLOT
CREATE _sr2p-small-transform-copy _SR2P-SMALL-JSON-CAPACITY ALLOT
CREATE _sr2p-large-transform-copy _SR2P-LARGE-JSON-CAPACITY ALLOT
CREATE _sr2p-compact-egress-copy _SR2P-SMALL-JSON-CAPACITY ALLOT
CREATE _sr2p-standard-egress-copy _SR2P-SMALL-JSON-CAPACITY ALLOT

VARIABLE _sr2p-small-input-u
VARIABLE _sr2p-large-input-u
VARIABLE _sr2p-over-input-u
VARIABLE _sr2p-small-capture-u
VARIABLE _sr2p-large-capture-u
VARIABLE _sr2p-over-capture-u
VARIABLE _sr2p-small-expected-u
VARIABLE _sr2p-large-expected-u
VARIABLE _sr2p-over-expected-u
VARIABLE _sr2p-small-request-json-u
VARIABLE _sr2p-small-response-json-u
VARIABLE _sr2p-large-response-json-u

VARIABLE _sr2p-builder-dest
VARIABLE _sr2p-builder-used

: _sr2p-append  ( source-a source-u destination used-variable -- )
    _sr2p-builder-used !
    _sr2p-builder-dest !
    DUP IF
        2DUP
        _sr2p-builder-dest @ _sr2p-builder-used @ @ + SWAP CMOVE
        DUP _sr2p-builder-used @ +!
    THEN
    2DROP ;

: _sr2p-c+  ( byte destination used-variable -- )
    _sr2p-builder-used !
    _sr2p-builder-dest !
    _sr2p-builder-dest @ _sr2p-builder-used @ @ + C!
    1 _sr2p-builder-used @ +! ;

: _sr2p-crlf  ( destination used-variable -- )
    _sr2p-builder-used !
    _sr2p-builder-dest !
    13 _sr2p-builder-dest @ _sr2p-builder-used @ @ + C!
    1 _sr2p-builder-used @ +!
    10 _sr2p-builder-dest @ _sr2p-builder-used @ @ + C!
    1 _sr2p-builder-used @ +! ;

: _sr2p-build-json  ( -- )
    0 _sr2p-small-request-json-u !
    [CHAR] { _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-c+
    34 _sr2p-small-request-json _sr2p-small-request-json-u _sr2p-c+
    S" event" _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-append
    34 _sr2p-small-request-json _sr2p-small-request-json-u _sr2p-c+
    [CHAR] : _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-c+
    34 _sr2p-small-request-json _sr2p-small-request-json-u _sr2p-c+
    S" demo" _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-append
    34 _sr2p-small-request-json _sr2p-small-request-json-u _sr2p-c+
    [CHAR] , _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-c+
    34 _sr2p-small-request-json _sr2p-small-request-json-u _sr2p-c+
    S" value" _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-append
    34 _sr2p-small-request-json _sr2p-small-request-json-u _sr2p-c+
    [CHAR] : _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-c+
    [CHAR] 7 _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-c+
    [CHAR] } _sr2p-small-request-json
        _sr2p-small-request-json-u _sr2p-c+
    _sr2p-small-request-json-u @ 26 = _sr2p-assert

    0 _sr2p-small-response-json-u !
    [CHAR] { _sr2p-small-response-json
        _sr2p-small-response-json-u _sr2p-c+
    34 _sr2p-small-response-json _sr2p-small-response-json-u _sr2p-c+
    S" accepted" _sr2p-small-response-json
        _sr2p-small-response-json-u _sr2p-append
    34 _sr2p-small-response-json _sr2p-small-response-json-u _sr2p-c+
    [CHAR] : _sr2p-small-response-json
        _sr2p-small-response-json-u _sr2p-c+
    S" true" _sr2p-small-response-json
        _sr2p-small-response-json-u _sr2p-append
    [CHAR] } _sr2p-small-response-json
        _sr2p-small-response-json-u _sr2p-c+
    _sr2p-small-response-json-u @ 17 = _sr2p-assert

    _sr2p-large-request-json _SR2P-LARGE-JSON-CAPACITY
        [CHAR] L FILL
    [CHAR] { _sr2p-large-request-json C!
    34 _sr2p-large-request-json 1+ C!
    S" data" _sr2p-large-request-json 2 + SWAP CMOVE
    34 _sr2p-large-request-json 6 + C!
    [CHAR] : _sr2p-large-request-json 7 + C!
    34 _sr2p-large-request-json 8 + C!
    34 _sr2p-large-request-json 4095 + C!
    [CHAR] } _sr2p-large-request-json 4096 + C!

    0 _sr2p-large-response-json-u !
    [CHAR] { _sr2p-large-response-json
        _sr2p-large-response-json-u _sr2p-c+
    34 _sr2p-large-response-json _sr2p-large-response-json-u _sr2p-c+
    S" accepted" _sr2p-large-response-json
        _sr2p-large-response-json-u _sr2p-append
    34 _sr2p-large-response-json _sr2p-large-response-json-u _sr2p-c+
    [CHAR] : _sr2p-large-response-json
        _sr2p-large-response-json-u _sr2p-c+
    34 _sr2p-large-response-json _sr2p-large-response-json-u _sr2p-c+
    S" large" _sr2p-large-response-json
        _sr2p-large-response-json-u _sr2p-append
    34 _sr2p-large-response-json _sr2p-large-response-json-u _sr2p-c+
    [CHAR] } _sr2p-large-response-json
        _sr2p-large-response-json-u _sr2p-c+
    _sr2p-large-response-json-u @ 20 = _sr2p-assert ;

: _sr2p-build-requests  ( -- )
    0 _sr2p-small-input-u !
    S" POST /hooks/demo HTTP/1.1" _sr2p-small-input
        _sr2p-small-input-u _sr2p-append
    _sr2p-small-input _sr2p-small-input-u _sr2p-crlf
    S" Host: demo.test" _sr2p-small-input
        _sr2p-small-input-u _sr2p-append
    _sr2p-small-input _sr2p-small-input-u _sr2p-crlf
    S" Content-Type: application/json" _sr2p-small-input
        _sr2p-small-input-u _sr2p-append
    _sr2p-small-input _sr2p-small-input-u _sr2p-crlf
    S" Content-Length: 26" _sr2p-small-input
        _sr2p-small-input-u _sr2p-append
    _sr2p-small-input _sr2p-small-input-u _sr2p-crlf
    _sr2p-small-input _sr2p-small-input-u _sr2p-crlf
    _sr2p-small-request-json _sr2p-small-request-json-u @
        _sr2p-small-input _sr2p-small-input-u _sr2p-append
    _sr2p-small-input-u @ _SR2P-SMALL-INPUT-CAPACITY <=
        _sr2p-assert

    0 _sr2p-large-input-u !
    S" POST /hooks/demo HTTP/1.1" _sr2p-large-input
        _sr2p-large-input-u _sr2p-append
    _sr2p-large-input _sr2p-large-input-u _sr2p-crlf
    S" Host: demo.test" _sr2p-large-input
        _sr2p-large-input-u _sr2p-append
    _sr2p-large-input _sr2p-large-input-u _sr2p-crlf
    S" Content-Type: application/json" _sr2p-large-input
        _sr2p-large-input-u _sr2p-append
    _sr2p-large-input _sr2p-large-input-u _sr2p-crlf
    S" Content-Length: 4097" _sr2p-large-input
        _sr2p-large-input-u _sr2p-append
    _sr2p-large-input _sr2p-large-input-u _sr2p-crlf
    _sr2p-large-input _sr2p-large-input-u _sr2p-crlf
    _sr2p-large-request-json _SR2P-LARGE-JSON-CAPACITY
        _sr2p-large-input _sr2p-large-input-u _sr2p-append
    _sr2p-large-input-u @ _SR2P-LARGE-INPUT-CAPACITY <=
        _sr2p-assert

    0 _sr2p-over-input-u !
    S" POST /hooks/demo HTTP/1.1" _sr2p-over-input
        _sr2p-over-input-u _sr2p-append
    _sr2p-over-input _sr2p-over-input-u _sr2p-crlf
    S" Host: demo.test" _sr2p-over-input
        _sr2p-over-input-u _sr2p-append
    _sr2p-over-input _sr2p-over-input-u _sr2p-crlf
    S" Content-Length: 0" _sr2p-over-input
        _sr2p-over-input-u _sr2p-append
    _sr2p-over-input _sr2p-over-input-u _sr2p-crlf
    _sr2p-over-input _sr2p-over-input-u _sr2p-crlf
    _sr2p-over-input-u @ _SR2P-OVER-INPUT-CAPACITY <=
        _sr2p-assert ;

: _sr2p-success-expected
  ( body-a body-u destination used-variable -- )
    _sr2p-builder-used !
    _sr2p-builder-dest !
    0 _sr2p-builder-used @ !
    S" HTTP/1.1 200 OK" _sr2p-builder-dest @
        _sr2p-builder-used @ _sr2p-append
    _sr2p-builder-dest @ _sr2p-builder-used @ _sr2p-crlf
    S" Content-Type: application/json" _sr2p-builder-dest @
        _sr2p-builder-used @ _sr2p-append
    _sr2p-builder-dest @ _sr2p-builder-used @ _sr2p-crlf
    DUP 17 = IF
        S" Content-Length: 17"
    ELSE
        S" Content-Length: 20"
    THEN
    _sr2p-builder-dest @ _sr2p-builder-used @ _sr2p-append
    _sr2p-builder-dest @ _sr2p-builder-used @ _sr2p-crlf
    S" Connection: close" _sr2p-builder-dest @
        _sr2p-builder-used @ _sr2p-append
    _sr2p-builder-dest @ _sr2p-builder-used @ _sr2p-crlf
    _sr2p-builder-dest @ _sr2p-builder-used @ _sr2p-crlf
    _sr2p-builder-dest @ _sr2p-builder-used @ _sr2p-append ;

: _sr2p-build-expected  ( -- )
    _sr2p-small-response-json _sr2p-small-response-json-u @
        _sr2p-small-expected _sr2p-small-expected-u
        _sr2p-success-expected
    _sr2p-small-expected-u @ 107 = _sr2p-assert
    _sr2p-large-response-json _sr2p-large-response-json-u @
        _sr2p-large-expected _sr2p-large-expected-u
        _sr2p-success-expected
    _sr2p-large-expected-u @ 110 = _sr2p-assert

    0 _sr2p-over-expected-u !
    S" HTTP/1.1 503 Service Unavailable" _sr2p-over-expected
        _sr2p-over-expected-u _sr2p-append
    _sr2p-over-expected _sr2p-over-expected-u _sr2p-crlf
    S" Content-Length: 0" _sr2p-over-expected
        _sr2p-over-expected-u _sr2p-append
    _sr2p-over-expected _sr2p-over-expected-u _sr2p-crlf
    S" Connection: close" _sr2p-over-expected
        _sr2p-over-expected-u _sr2p-append
    _sr2p-over-expected _sr2p-over-expected-u _sr2p-crlf
    _sr2p-over-expected _sr2p-over-expected-u _sr2p-crlf
    _sr2p-over-expected-u @ 74 = _sr2p-assert ;

\ ---------------------------------------------------------------------
\ Streams callbacks prove cell identity, payload fidelity, and isolation
\ ---------------------------------------------------------------------

VARIABLE _sr2p-now
VARIABLE _sr2p-metadata-small
VARIABLE _sr2p-metadata-large
VARIABLE _sr2p-compact-transforms
VARIABLE _sr2p-standard-transforms
VARIABLE _sr2p-compact-starts
VARIABLE _sr2p-standard-starts
VARIABLE _sr2p-output-polls
VARIABLE _sr2p-output-cancels
VARIABLE _sr2p-compact-cleanups
VARIABLE _sr2p-standard-cleanups

VARIABLE _sr2p-transform-event
VARIABLE _sr2p-transform-output
VARIABLE _sr2p-transform-context
VARIABLE _sr2p-transform-result
VARIABLE _sr2p-cb-event
VARIABLE _sr2p-cb-operation
VARIABLE _sr2p-cb-result
VARIABLE _sr2p-meta-exchange
VARIABLE _sr2p-meta-event
VARIABLE _sr2p-meta-tag

0x434F4D5041435421 CONSTANT _SR2P-COMPACT-MARK
0x5354414E44415244 CONSTANT _SR2P-STANDARD-MARK

: _sr2p-result!
  ( completion effect detail error result -- )
    >R
    R@ SCRR.ERROR !
    R@ SCRR.DETAIL !
    R@ SCRR.EFFECT !
    R> SCRR.COMPLETION ! ;

: _sr2p-transform-result!
  ( completion output-u detail error result -- )
    >R
    R@ STRR.ERROR !
    R@ STRR.DETAIL !
    R@ STRR.OUTPUT-U !
    R> STRR.COMPLETION ! ;

: _sr2p-transform  ( ingress-event output-carrier context result -- )
    701 _sr2p-stage !
    _sr2p-transform-result !
    _sr2p-transform-context !
    _sr2p-transform-output !
    _sr2p-transform-event !
    _sr2p-transform-context @ _sr2p-compact-context = IF
        1 _sr2p-compact-transforms +!
        _sr2p-transform-output @ _sr2p-compact-egress =
            _sr2p-assert
        _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 1 =
            _sr2p-assert
        _sr2p-small-transform-copy _SR2P-SMALL-JSON-CAPACITY
        _sr2p-transform-event @ STREAMS-EVENT-PAYLOAD-COPY
            STREAMS-FLOW-S-OK = _sr2p-assert
        DUP _sr2p-small-request-json-u @ = _sr2p-assert
        _sr2p-small-transform-copy SWAP
        _sr2p-small-request-json _sr2p-small-request-json-u @
            _sr2p-span= _sr2p-assert
        _sr2p-small-response-json _sr2p-small-response-json-u @
        _sr2p-transform-output @ SPAY.GENERATION @
        _sr2p-transform-output @ STREAMS-PAYLOAD-APPEND
            STREAMS-PAYLOAD-S-OK = _sr2p-assert
        STREAMS-TRANSFORM-COMPLETION-OK
        _sr2p-small-response-json-u @ 0 0
        _sr2p-transform-result @ _sr2p-transform-result!
        EXIT
    THEN
    _sr2p-transform-context @ _sr2p-standard-context =
        _sr2p-assert
    1 _sr2p-standard-transforms +!
    _sr2p-transform-output @ _sr2p-standard-egress =
        _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 2 =
        _sr2p-assert
    _sr2p-large-transform-copy _SR2P-LARGE-JSON-CAPACITY
    _sr2p-transform-event @ STREAMS-EVENT-PAYLOAD-COPY
        STREAMS-FLOW-S-OK = _sr2p-assert
    DUP _SR2P-LARGE-JSON-CAPACITY = _sr2p-assert
    _sr2p-large-transform-copy SWAP
    _sr2p-large-request-json _SR2P-LARGE-JSON-CAPACITY
        _sr2p-span= _sr2p-assert
    _sr2p-large-response-json _sr2p-large-response-json-u @
    _sr2p-transform-output @ SPAY.GENERATION @
    _sr2p-transform-output @ STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    STREAMS-TRANSFORM-COMPLETION-OK
    _sr2p-large-response-json-u @ 0 0
    _sr2p-transform-result @ _sr2p-transform-result! ;

: _sr2p-check-output-event  ( event flow tag -- )
    _sr2p-meta-tag !
    >R
    DUP STREAMS-EVENT-VALID? _sr2p-assert
    DUP SEVT.DIRECTION @ STREAMS-EVENT-DIRECTION-EGRESS =
        _sr2p-assert
    DUP SEVT.FLOW-ID R@ SFLOW.ID RID= _sr2p-assert
    DUP SEVT.CORRELATION-ID RID-SIZE
        _sr2p-meta-tag @ 1+ _sr2p-byte-span? _sr2p-assert
    DROP R> DROP ;

: _sr2p-output-start  ( egress-event operation context result -- )
    702 _sr2p-stage !
    _sr2p-cb-result !
    DROP
    _sr2p-cb-operation !
    _sr2p-cb-event !
    _sr2p-output-connector SCON.CALLBACK-BUSY @ -1 =
        _sr2p-assert
    _sr2p-cb-operation @ _sr2p-compact-operation = IF
        1 _sr2p-compact-starts +!
        _sr2p-cb-event @ _sr2p-compact-flow 0x71
            _sr2p-check-output-event
        _SR2P-COMPACT-MARK _sr2p-cb-operation @ !
    ELSE
        _sr2p-cb-operation @ _sr2p-standard-operation =
            _sr2p-assert
        1 _sr2p-standard-starts +!
        _sr2p-cb-event @ _sr2p-standard-flow 0x81
            _sr2p-check-output-event
        _SR2P-STANDARD-MARK _sr2p-cb-operation @ !
    THEN
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr2p-cb-result @ _sr2p-result! ;

: _sr2p-output-poll  ( egress-event operation context result -- )
    _sr2p-cb-result !
    DROP 2DROP
    1 _sr2p-output-polls +!
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr2p-cb-result @ _sr2p-result! ;

: _sr2p-output-cancel  ( egress-event operation context result -- )
    _sr2p-cb-result !
    DROP 2DROP
    1 _sr2p-output-cancels +!
    STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED 0 0
    _sr2p-cb-result @ _sr2p-result! ;

: _sr2p-output-cleanup  ( egress-event operation context -- error )
    703 _sr2p-stage !
    DROP
    _sr2p-cb-operation !
    _sr2p-cb-event !
    _sr2p-output-connector SCON.CALLBACK-BUSY @ -1 =
        _sr2p-assert
    _sr2p-cb-operation @ _sr2p-compact-operation = IF
        _sr2p-cb-operation @ @ _SR2P-COMPACT-MARK =
            _sr2p-assert
        1 _sr2p-compact-cleanups +!
    ELSE
        _sr2p-cb-operation @ _sr2p-standard-operation =
            _sr2p-assert
        _sr2p-cb-operation @ @ _SR2P-STANDARD-MARK =
            _sr2p-assert
        1 _sr2p-standard-cleanups +!
    THEN
    0 ;

: _sr2p-clock  ( context -- now status )
    DROP
    1 _sr2p-now +!
    _sr2p-now @ 0 ;

: _sr2p-metadata  ( exchange event context -- status )
    704 _sr2p-stage !
    DROP
    _sr2p-meta-event !
    _sr2p-meta-exchange !
    _sr2p-meta-exchange @ _sr2p-small-connection = IF
        1 _sr2p-metadata-small +!
        0x71
    ELSE
        _sr2p-meta-exchange @ _sr2p-large-connection =
            _sr2p-assert
        1 _sr2p-metadata-large +!
        0x81
    THEN
    _sr2p-meta-tag !
    _sr2p-meta-event @ SEVT.EVENT-ID RID-SIZE
        _sr2p-meta-tag @ FILL
    _sr2p-meta-event @ SEVT.CORRELATION-ID RID-SIZE
        _sr2p-meta-tag @ 1+ FILL
    _sr2p-meta-event @ SEVT.IDEMPOTENCY-ID RID-SIZE
        _sr2p-meta-tag @ 2 + FILL
    STREAMS-HTTP-ROUTE-MEDIA-JSON _sr2p-meta-event @ SEVT.MEDIA !
    _sr2p-meta-tag @ _sr2p-meta-event @ SEVT.SEQUENCE !
    0 ;

: _sr2p-connector-identity  ( id-byte endpoint-byte connector -- )
    >R
    DUP R@ SCON.ENDPOINT-ID RID-SIZE ROT FILL
    DROP
    R> SCON.ID RID-SIZE ROT FILL ;

: _sr2p-setup-connectors  ( -- )
    _sr2p-input-connector STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2p-assert
    0x41 0x51 _sr2p-input-connector _sr2p-connector-identity
    1 _sr2p-input-connector SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT
        _sr2p-input-connector SCON.DIRECTION !
    401 _sr2p-input-connector SCON.PROTOCOL !
    _sr2p-input-connector STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr2p-assert

    _sr2p-output-connector STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2p-assert
    0x42 0x52 _sr2p-output-connector _sr2p-connector-identity
    1 _sr2p-output-connector SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT
        _sr2p-output-connector SCON.DIRECTION !
    402 _sr2p-output-connector SCON.PROTOCOL !
    16 _sr2p-output-connector SCON.OP-SIZE !
    ['] _sr2p-output-start _sr2p-output-connector SCON.START-XT !
    ['] _sr2p-output-poll _sr2p-output-connector SCON.POLL-XT !
    ['] _sr2p-output-cancel _sr2p-output-connector SCON.CANCEL-XT !
    ['] _sr2p-output-cleanup _sr2p-output-connector SCON.CLEANUP-XT !
    _sr2p-output-connector STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr2p-assert ;

: _sr2p-close-carrier  ( carrier -- )
    DUP _SPAY-HEADER? 0= IF DROP EXIT THEN
    DUP SPAY.STATE @ STREAMS-PAYLOAD-STATE-CLOSED = IF DROP EXIT THEN
    DUP SPAY.GENERATION @ SWAP STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2p-assert ;

: _sr2p-init-standard-segments  ( bytes table -- )
    >R
    DUP STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    DUP STREAMS-RUNTIME-SEGMENT-BYTES +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-SIZE +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    DUP STREAMS-RUNTIME-SEGMENT-BYTES 2 * +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-SIZE 2 * +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    STREAMS-RUNTIME-SEGMENT-BYTES 3 * +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R> STREAMS-PAYLOAD-SEGMENT-SIZE 3 * +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2p-assert ;

: _sr2p-setup-compact-flow  ( -- )
    _sr2p-compact-ingress _sr2p-close-carrier
    _sr2p-compact-egress _sr2p-close-carrier
    _sr2p-compact-in-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2p-compact-in-segment STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    _sr2p-compact-out-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2p-compact-out-segment STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    _sr2p-compact-in-segment 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2p-compact-ingress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2p-assert
    _sr2p-compact-out-segment 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2p-compact-egress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2p-assert

    _sr2p-compact-flow STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK = _sr2p-assert
    STREAMS-RUNTIME-PROFILE-COMPACT
        _sr2p-compact-ingress _sr2p-compact-egress
        _sr2p-compact-operation
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2p-compact-flow STREAMS-FLOW-WORKSPACE!
        STREAMS-FLOW-S-OK = _sr2p-assert
    _sr2p-compact-flow SFLOW.ID RID-SIZE 0x61 FILL
    7 _sr2p-compact-flow SFLOW.REVISION !
    1000 _sr2p-compact-flow SFLOW.TIMEOUT-MS !
    _sr2p-input-connector _sr2p-compact-flow SFLOW.INPUT-CONNECTOR !
    _sr2p-output-connector _sr2p-compact-flow SFLOW.OUTPUT-CONNECTOR !
    ['] _sr2p-transform _sr2p-compact-flow SFLOW.TRANSFORM-XT !
    _sr2p-compact-context
        _sr2p-compact-flow SFLOW.TRANSFORM-CONTEXT !
    STREAMS-HTTP-ROUTE-MEDIA-JSON
        _sr2p-compact-flow SFLOW.OUTPUT-MEDIA !
    _sr2p-compact-flow STREAMS-FLOW-SEAL
        STREAMS-FLOW-S-OK = _sr2p-assert ;

: _sr2p-setup-standard-flow  ( -- )
    _sr2p-standard-ingress _sr2p-close-carrier
    _sr2p-standard-egress _sr2p-close-carrier
    _sr2p-standard-in-bytes _sr2p-standard-in-segments
        _sr2p-init-standard-segments
    _sr2p-standard-out-bytes _sr2p-standard-out-segments
        _sr2p-init-standard-segments
    _sr2p-standard-in-segments 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2p-standard-ingress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2p-assert
    _sr2p-standard-out-segments 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2p-standard-egress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2p-assert

    _sr2p-standard-flow STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK = _sr2p-assert
    STREAMS-RUNTIME-PROFILE-STANDARD
        _sr2p-standard-ingress _sr2p-standard-egress
        _sr2p-standard-operation
        STREAMS-RUNTIME-PROFILE-STANDARD
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2p-standard-flow STREAMS-FLOW-WORKSPACE!
        STREAMS-FLOW-S-OK = _sr2p-assert
    _sr2p-standard-flow SFLOW.ID RID-SIZE 0x62 FILL
    7 _sr2p-standard-flow SFLOW.REVISION !
    1000 _sr2p-standard-flow SFLOW.TIMEOUT-MS !
    _sr2p-input-connector _sr2p-standard-flow SFLOW.INPUT-CONNECTOR !
    _sr2p-output-connector _sr2p-standard-flow SFLOW.OUTPUT-CONNECTOR !
    ['] _sr2p-transform _sr2p-standard-flow SFLOW.TRANSFORM-XT !
    _sr2p-standard-context
        _sr2p-standard-flow SFLOW.TRANSFORM-CONTEXT !
    STREAMS-HTTP-ROUTE-MEDIA-JSON
        _sr2p-standard-flow SFLOW.OUTPUT-MEDIA !
    _sr2p-standard-flow STREAMS-FLOW-SEAL
        STREAMS-FLOW-S-OK = _sr2p-assert ;

: _sr2p-assert-geometry  ( -- )
    HTTP-CONNECTION-OWNER-SIZE
    WEB-HTTP-REQUEST-STREAM-SIZE +
    _SR2P-REQUEST-CAPACITY +
    HTTP-RESPONSE-WRITER-SIZE +
    _SR2P-RESPONSE-HEADER-CAPACITY +
    _SR2P-RESPONSE-SEND-CAPACITY +
    HROUTER-MATCH-SIZE +
    NET-IO-PORT-SIZE +
    _SR2P-RX-CAPACITY +
    STREAMS-HTTP-ROUTE-OPERATION-SIZE +
    _SR2P-AUTHORITY-CAPACITY +
        2592 = _sr2p-assert
    2592 3 * 7776 = _sr2p-assert
    HROUTER-SIZE HROUTER-ENTRY-SIZE +
        64 + 208 = _sr2p-assert
    STREAMS-HTTP-ROUTE-CONFIG-SIZE 80 = _sr2p-assert
    STREAMS-CONNECTOR-SIZE 2 * 336 = _sr2p-assert
    7776 208 + 80 + 336 + 47000 +
        55400 = _sr2p-assert ;

: _sr2p-reset-runtime-counters  ( -- )
    0 _sr2p-now !
    0 _sr2p-metadata-small !
    0 _sr2p-metadata-large !
    0 _sr2p-compact-transforms !
    0 _sr2p-standard-transforms !
    0 _sr2p-compact-starts !
    0 _sr2p-standard-starts !
    0 _sr2p-output-polls !
    0 _sr2p-output-cancels !
    0 _sr2p-compact-cleanups !
    0 _sr2p-standard-cleanups ! ;

: _sr2p-setup-runtime  ( -- )
    _sr2p-reset-runtime-counters
    _sr2p-setup-compact-flow
    _sr2p-setup-standard-flow
    _sr2p-pool-entries 2 _sr2p-pool
        STREAMS-EXECUTION-POOL-INIT
        STREAMS-FLOW-S-OK = _sr2p-assert
    _sr2p-compact-flow _sr2p-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK = _sr2p-assert
    _sr2p-standard-flow _sr2p-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK = _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-SEAL
        STREAMS-FLOW-S-OK = _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-CAPACITY@ 2 =
        _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
        _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-RUNTIME-BYTES@
        47000 = _sr2p-assert
    STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES
        10848 = _sr2p-assert
    STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES
        35824 = _sr2p-assert
    _sr2p-compact-ingress SPAY.BYTE-CAP @ 4096 =
        _sr2p-assert
    _sr2p-standard-ingress SPAY.BYTE-CAP @ 16384 =
        _sr2p-assert ;

: _sr2p-setup-route  ( -- )
    _sr2p-pool _sr2p-input-connector
    _sr2p-large-response-json-u @
    0 ['] _sr2p-clock
    0 ['] _sr2p-metadata
    _sr2p-config STREAMS-HTTP-ROUTE-CONFIG-INIT
        STREAMS-HTTP-ROUTE-S-OK = _sr2p-assert
    _sr2p-config STREAMS-HTTP-ROUTE-MAX-INGRESS@ 16384 =
        _sr2p-assert
    _sr2p-config STREAMS-HTTP-ROUTE-MAX-EGRESS@ 16384 =
        _sr2p-assert
    _sr2p-router-entry 1 _sr2p-router-arena 64 _sr2p-router
        HROUTER-INIT HROUTER-S-OK = _sr2p-assert
    _sr2p-config _sr2p-router STREAMS-HTTP-DEMO-ROUTE-ADD
        HROUTER-S-OK = _sr2p-assert
    _sr2p-router HROUTER-SEAL HROUTER-S-OK = _sr2p-assert
    _sr2p-config STREAMS-HTTP-ROUTE-CONFIG-VALID?
        _sr2p-assert
    _sr2p-router HROUTER-VALID? _sr2p-assert
    _sr2p-router HROUTER-SEALED? _sr2p-assert ;

\ ---------------------------------------------------------------------
\ Three independent fragmented transports
\ ---------------------------------------------------------------------

VARIABLE _sr2p-small-input-position
VARIABLE _sr2p-large-input-position
VARIABLE _sr2p-over-input-position
VARIABLE _sr2p-small-recv-calls
VARIABLE _sr2p-large-recv-calls
VARIABLE _sr2p-over-recv-calls
VARIABLE _sr2p-small-send-calls
VARIABLE _sr2p-large-send-calls
VARIABLE _sr2p-over-send-calls
VARIABLE _sr2p-small-zero-sends
VARIABLE _sr2p-small-body-progress
VARIABLE _sr2p-small-port-cancels
VARIABLE _sr2p-small-port-closes
VARIABLE _sr2p-large-port-cancels
VARIABLE _sr2p-large-port-closes
VARIABLE _sr2p-over-port-cancels
VARIABLE _sr2p-over-port-closes
VARIABLE _sr2p-small-steps
VARIABLE _sr2p-large-steps
VARIABLE _sr2p-over-steps
VARIABLE _sr2p-peak-active
VARIABLE _sr2p-small-capture-before-cancel

VARIABLE _sr2p-io-buffer
VARIABLE _sr2p-io-capacity
VARIABLE _sr2p-io-source
VARIABLE _sr2p-io-source-u
VARIABLE _sr2p-io-position
VARIABLE _sr2p-io-calls
VARIABLE _sr2p-io-capture
VARIABLE _sr2p-io-capture-capacity
VARIABLE _sr2p-io-capture-u
VARIABLE _sr2p-io-fragment
VARIABLE _sr2p-io-take

: _sr2p-recv-from
  ( buffer cap source source-u position-var calls-var frag -- count status )
    _sr2p-io-fragment !
    _sr2p-io-calls !
    _sr2p-io-position !
    _sr2p-io-source-u !
    _sr2p-io-source !
    _sr2p-io-capacity !
    _sr2p-io-buffer !
    _sr2p-io-position @ @ _sr2p-io-source-u @ >= IF
        0 NIO-S-EOF EXIT
    THEN
    1 _sr2p-io-calls @ +!
    _sr2p-io-fragment @ 13 > IF
        _sr2p-io-fragment @
    ELSE
        _sr2p-io-calls @ @ 7 * _sr2p-io-fragment @ MOD 1+
    THEN
    _sr2p-io-source-u @ _sr2p-io-position @ @ - MIN
    _sr2p-io-capacity @ MIN
    DUP _sr2p-io-take !
    DROP
    _sr2p-io-source @ _sr2p-io-position @ @ +
    _sr2p-io-buffer @ _sr2p-io-take @ CMOVE
    _sr2p-io-take @ _sr2p-io-position @ +!
    _sr2p-io-take @ NIO-S-OK ;

: _sr2p-small-recv  ( buffer capacity context -- count io-status )
    DROP
    _sr2p-small-input _sr2p-small-input-u @
    _sr2p-small-input-position _sr2p-small-recv-calls 13
    _sr2p-recv-from ;

: _sr2p-large-recv  ( buffer capacity context -- count io-status )
    DROP
    _sr2p-large-input _sr2p-large-input-u @
    _sr2p-large-input-position _sr2p-large-recv-calls 64
    _sr2p-recv-from ;

: _sr2p-over-recv  ( buffer capacity context -- count io-status )
    DROP
    _sr2p-over-input _sr2p-over-input-u @
    _sr2p-over-input-position _sr2p-over-recv-calls 13
    _sr2p-recv-from ;

: _sr2p-capture-fragment
  ( source source-u capture capture-capacity used-variable -- )
    705 _sr2p-stage !
    _sr2p-io-capture-u !
    _sr2p-io-capture-capacity !
    _sr2p-io-capture !
    _sr2p-io-take !
    _sr2p-io-source !
    _sr2p-io-capture-u @ @ _sr2p-io-take @ +
        _sr2p-io-capture-capacity @ <=
    DUP 0= IF
        ." STREAMS SR2 HTTP PRESSURE CAPTURE "
        _sr2p-io-capture-u @ @ .
        _sr2p-io-take @ .
        _sr2p-io-capture-capacity @ . CR
    THEN
    _sr2p-assert
    _sr2p-io-source @
    _sr2p-io-capture @ _sr2p-io-capture-u @ @ +
    _sr2p-io-take @ CMOVE
    _sr2p-io-take @ _sr2p-io-capture-u @ +! ;

: _sr2p-send-complete
  ( buffer len capture capture-cap used-var calls-var frag -- count status )
    _sr2p-io-fragment !
    _sr2p-io-calls !
    _sr2p-io-capture-u !
    _sr2p-io-capture-capacity !
    _sr2p-io-capture !
    _sr2p-io-capacity !
    _sr2p-io-buffer !
    1 _sr2p-io-calls @ +!
    _sr2p-io-capacity @ _sr2p-io-fragment @ MIN
    DUP _sr2p-io-take !
    _sr2p-io-buffer @ SWAP
    _sr2p-io-capture @ _sr2p-io-capture-capacity @
    _sr2p-io-capture-u @ _sr2p-capture-fragment
    _sr2p-io-take @ NIO-S-OK ;

: _sr2p-small-send  ( buffer length context -- count io-status )
    DROP
    _sr2p-io-capacity !
    _sr2p-io-buffer !
    1 _sr2p-small-send-calls +!
    _sr2p-small-response HRESP-HEADER-SENT@
    _sr2p-small-response HRESP-HEADER$ NIP = IF
        _sr2p-small-body-progress @ IF
            1 _sr2p-small-zero-sends +!
            0 NIO-S-OK EXIT
        THEN
        _sr2p-io-capacity @ 5 MIN
        -1 _sr2p-small-body-progress !
    ELSE
        _sr2p-io-capacity @ 11 MIN
    THEN
    DUP _sr2p-io-take !
    _sr2p-io-buffer @ SWAP
    _sr2p-small-capture _SR2P-CAPTURE-CAPACITY
    _sr2p-small-capture-u _sr2p-capture-fragment
    _sr2p-io-take @ NIO-S-OK ;

: _sr2p-large-send  ( buffer length context -- count io-status )
    DROP
    _sr2p-large-capture _SR2P-CAPTURE-CAPACITY
    _sr2p-large-capture-u _sr2p-large-send-calls 17
    _sr2p-send-complete ;

: _sr2p-over-send  ( buffer length context -- count io-status )
    DROP
    _sr2p-over-capture _SR2P-CAPTURE-CAPACITY
    _sr2p-over-capture-u _sr2p-over-send-calls 11
    _sr2p-send-complete ;

: _sr2p-small-port-cancel  ( context -- )
    DROP
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 1 =
        _sr2p-assert
    _sr2p-compact-flow SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
        _sr2p-zero-span? _sr2p-assert
    _sr2p-large-route-operation
        STREAMS-HTTP-ROUTE-OPERATION-VALID? _sr2p-assert
    1 _sr2p-small-port-cancels +! ;

: _sr2p-small-port-close  ( context -- )
    DROP 1 _sr2p-small-port-closes +! ;

: _sr2p-large-port-cancel  ( context -- )
    DROP 1 _sr2p-large-port-cancels +! ;

: _sr2p-large-port-close  ( context -- )
    DROP 1 _sr2p-large-port-closes +! ;

: _sr2p-over-port-cancel  ( context -- )
    DROP 1 _sr2p-over-port-cancels +! ;

: _sr2p-over-port-close  ( context -- )
    DROP 1 _sr2p-over-port-closes +! ;

: _sr2p-reset-http-counters  ( -- )
    0 _sr2p-small-input-position !
    0 _sr2p-large-input-position !
    0 _sr2p-over-input-position !
    0 _sr2p-small-capture-u !
    0 _sr2p-large-capture-u !
    0 _sr2p-over-capture-u !
    0 _sr2p-small-recv-calls !
    0 _sr2p-large-recv-calls !
    0 _sr2p-over-recv-calls !
    0 _sr2p-small-send-calls !
    0 _sr2p-large-send-calls !
    0 _sr2p-over-send-calls !
    0 _sr2p-small-zero-sends !
    0 _sr2p-small-body-progress !
    0 _sr2p-small-port-cancels !
    0 _sr2p-small-port-closes !
    0 _sr2p-large-port-cancels !
    0 _sr2p-large-port-closes !
    0 _sr2p-over-port-cancels !
    0 _sr2p-over-port-closes !
    0 _sr2p-small-steps !
    0 _sr2p-large-steps !
    0 _sr2p-over-steps !
    0 _sr2p-peak-active ! ;

: _sr2p-setup-small-http  ( -- )
    _sr2p-small-request-header _SR2P-REQUEST-CAPACITY
    STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-INGRESS-CAPACITY
    0 0 _sr2p-small-request WREQ-INIT
        WREQ-S-PENDING = _sr2p-assert
    _sr2p-small-response-header _SR2P-RESPONSE-HEADER-CAPACITY
    _sr2p-small-response-send _SR2P-RESPONSE-SEND-CAPACITY
    _sr2p-small-response HRESP-INIT HRESP-S-OK =
        _sr2p-assert
    _sr2p-small-port NIO-INIT
    ['] _sr2p-small-recv _sr2p-small-port NIO.RECV-XT !
    ['] _sr2p-small-send _sr2p-small-port NIO.SEND-XT !
    ['] _sr2p-small-port-cancel _sr2p-small-port NIO.CANCEL-XT !
    ['] _sr2p-small-port-close _sr2p-small-port NIO.CLOSE-XT !
    NIO-OPEN-STATE-OPEN _sr2p-small-port NIO.OPEN-STATE !
    NIO-S-OK _sr2p-small-port NIO.OPEN-STATUS !
    S" demo.test" _sr2p-small-authority SWAP CMOVE
    _sr2p-small-request _sr2p-small-response _sr2p-small-match
    _sr2p-router _sr2p-small-port _sr2p-small-rx _SR2P-RX-CAPACITY
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
    _sr2p-small-authority 9 _sr2p-small-connection HCONN-INIT
        HCONN-S-PENDING = _sr2p-assert ;

: _sr2p-setup-large-http  ( -- )
    _sr2p-large-request-header _SR2P-REQUEST-CAPACITY
    STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-INGRESS-CAPACITY
    0 0 _sr2p-large-request WREQ-INIT
        WREQ-S-PENDING = _sr2p-assert
    _sr2p-large-response-header _SR2P-RESPONSE-HEADER-CAPACITY
    _sr2p-large-response-send _SR2P-RESPONSE-SEND-CAPACITY
    _sr2p-large-response HRESP-INIT HRESP-S-OK =
        _sr2p-assert
    _sr2p-large-port NIO-INIT
    ['] _sr2p-large-recv _sr2p-large-port NIO.RECV-XT !
    ['] _sr2p-large-send _sr2p-large-port NIO.SEND-XT !
    ['] _sr2p-large-port-cancel _sr2p-large-port NIO.CANCEL-XT !
    ['] _sr2p-large-port-close _sr2p-large-port NIO.CLOSE-XT !
    NIO-OPEN-STATE-OPEN _sr2p-large-port NIO.OPEN-STATE !
    NIO-S-OK _sr2p-large-port NIO.OPEN-STATUS !
    S" demo.test" _sr2p-large-authority SWAP CMOVE
    _sr2p-large-request _sr2p-large-response _sr2p-large-match
    _sr2p-router _sr2p-large-port _sr2p-large-rx _SR2P-RX-CAPACITY
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
    _sr2p-large-authority 9 _sr2p-large-connection HCONN-INIT
        HCONN-S-PENDING = _sr2p-assert ;

: _sr2p-setup-over-http  ( -- )
    _sr2p-over-request-header _SR2P-REQUEST-CAPACITY
    STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-INGRESS-CAPACITY
    0 0 _sr2p-over-request WREQ-INIT
        WREQ-S-PENDING = _sr2p-assert
    _sr2p-over-response-header _SR2P-RESPONSE-HEADER-CAPACITY
    _sr2p-over-response-send _SR2P-RESPONSE-SEND-CAPACITY
    _sr2p-over-response HRESP-INIT HRESP-S-OK =
        _sr2p-assert
    _sr2p-over-port NIO-INIT
    ['] _sr2p-over-recv _sr2p-over-port NIO.RECV-XT !
    ['] _sr2p-over-send _sr2p-over-port NIO.SEND-XT !
    ['] _sr2p-over-port-cancel _sr2p-over-port NIO.CANCEL-XT !
    ['] _sr2p-over-port-close _sr2p-over-port NIO.CLOSE-XT !
    NIO-OPEN-STATE-OPEN _sr2p-over-port NIO.OPEN-STATE !
    NIO-S-OK _sr2p-over-port NIO.OPEN-STATUS !
    S" demo.test" _sr2p-over-authority SWAP CMOVE
    _sr2p-over-request _sr2p-over-response _sr2p-over-match
    _sr2p-router _sr2p-over-port _sr2p-over-rx _SR2P-RX-CAPACITY
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
    _sr2p-over-authority 9 _sr2p-over-connection HCONN-INIT
        HCONN-S-PENDING = _sr2p-assert ;

: _sr2p-setup-http  ( -- )
    _sr2p-reset-http-counters
    _sr2p-setup-small-http
    _sr2p-setup-large-http
    _sr2p-setup-over-http ;

: _sr2p-assert-owner-isolation  ( -- )
    _sr2p-small-connection _sr2p-large-connection <>
        _sr2p-assert
    _sr2p-small-connection _sr2p-over-connection <>
        _sr2p-assert
    _sr2p-large-connection _sr2p-over-connection <>
        _sr2p-assert
    _sr2p-small-connection HCONN.REQUEST @
        _sr2p-large-connection HCONN.REQUEST @ <> _sr2p-assert
    _sr2p-small-connection HCONN.RESPONSE @
        _sr2p-large-connection HCONN.RESPONSE @ <> _sr2p-assert
    _sr2p-small-connection HCONN.PORT @
        _sr2p-large-connection HCONN.PORT @ <> _sr2p-assert
    _sr2p-small-connection HCONN.OPERATION-A @
        _sr2p-large-connection HCONN.OPERATION-A @ <> _sr2p-assert
    _sr2p-large-connection HCONN.REQUEST @
        _sr2p-over-connection HCONN.REQUEST @ <> _sr2p-assert
    _sr2p-large-connection HCONN.RESPONSE @
        _sr2p-over-connection HCONN.RESPONSE @ <> _sr2p-assert
    _sr2p-large-connection HCONN.PORT @
        _sr2p-over-connection HCONN.PORT @ <> _sr2p-assert
    _sr2p-large-connection HCONN.OPERATION-A @
        _sr2p-over-connection HCONN.OPERATION-A @ <> _sr2p-assert
    _sr2p-small-connection HCONN.ROUTER @ _sr2p-router =
        _sr2p-assert
    _sr2p-large-connection HCONN.ROUTER @ _sr2p-router =
        _sr2p-assert
    _sr2p-over-connection HCONN.ROUTER @ _sr2p-router =
        _sr2p-assert
    _sr2p-small-connection HCONN.OPERATION-CAPACITY @
        STREAMS-HTTP-ROUTE-OPERATION-SIZE = _sr2p-assert
    _sr2p-large-connection HCONN.OPERATION-CAPACITY @
        STREAMS-HTTP-ROUTE-OPERATION-SIZE = _sr2p-assert
    _sr2p-over-connection HCONN.OPERATION-CAPACITY @
        STREAMS-HTTP-ROUTE-OPERATION-SIZE = _sr2p-assert ;

: _sr2p-note-peak  ( -- )
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@
    DUP _sr2p-peak-active @ > IF
        _sr2p-peak-active !
    ELSE
        DROP
    THEN ;

: _sr2p-step-small  ( -- )
    _sr2p-small-connection HCONN-STEP DROP
    1 _sr2p-small-steps +!
    _sr2p-note-peak ;

: _sr2p-step-large  ( -- )
    _sr2p-large-connection HCONN-STEP DROP
    1 _sr2p-large-steps +!
    _sr2p-note-peak ;

: _sr2p-step-over  ( -- )
    _sr2p-over-connection HCONN-STEP DROP
    1 _sr2p-over-steps +!
    _sr2p-note-peak ;

\ ---------------------------------------------------------------------
\ Live pressure assertions
\ ---------------------------------------------------------------------

: _sr2p-assert-compact-live  ( -- )
    111 _sr2p-stage !
    _sr2p-small-route-operation
        STREAMS-HTTP-ROUTE-OPERATION-VALID? _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-STATUS@
        STREAMS-HTTP-ROUTE-S-OK = _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-STATE@
        STREAMS-HTTP-ROUTE-STATE-RESPONSE = _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-FLOW-STATUS@
        STREAMS-FLOW-S-DELIVERED = _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-DECLARED@
        26 = _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-RECEIVED@
        26 = _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-RESPONSE@
        17 = _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-LEASED?
        _sr2p-assert
    115 _sr2p-stage !
    _sr2p-small-route-operation _SHTO.FLOW @
        _sr2p-compact-flow = _sr2p-assert
    _sr2p-small-route-operation _SHTO.LEASE @ 0>
        _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-GENERATION@
        _sr2p-compact-flow SFLOW.GENERATION @ =
        _sr2p-assert
    _sr2p-small-route-operation
        STREAMS-HTTP-ROUTE-PAYLOAD-GENERATION@
        _sr2p-compact-egress SPAY.GENERATION @ =
        _sr2p-assert
    _sr2p-small-route-operation _SHTO.EVENT SEVT.FLOW-ID
        RID-ZERO? _sr2p-assert
    _sr2p-small-route-operation _SHTO.EVENT SEVT.CORRELATION-ID
        RID-SIZE 0x72 _sr2p-byte-span? _sr2p-assert

    112 _sr2p-stage !
    _sr2p-compact-flow SFLOW.STATE @
        STREAMS-FLOW-STATE-TERMINAL = _sr2p-assert
    _sr2p-compact-flow SFLOW.LAST-STATUS @
        STREAMS-FLOW-S-DELIVERED = _sr2p-assert
    _sr2p-compact-flow SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr2p-assert
    _sr2p-compact-flow SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-DELIVERED = _sr2p-assert
    _sr2p-compact-flow SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr2p-assert
    _sr2p-compact-ingress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-SEALED = _sr2p-assert
    _sr2p-compact-egress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-SEALED = _sr2p-assert
    113 _sr2p-stage !
    _sr2p-small-transform-copy _sr2p-small-request-json-u @
        _sr2p-small-request-json _sr2p-small-request-json-u @
        _sr2p-span= _sr2p-assert
    _sr2p-compact-egress-copy _SR2P-SMALL-JSON-CAPACITY
        _sr2p-small-route-operation
            STREAMS-HTTP-ROUTE-PAYLOAD-GENERATION@
        _sr2p-compact-egress STREAMS-PAYLOAD-COPY
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    DUP _sr2p-small-response-json-u @ = _sr2p-assert
    _sr2p-compact-egress-copy SWAP
        _sr2p-small-response-json _sr2p-small-response-json-u @
        _sr2p-span= _sr2p-assert
    114 _sr2p-stage !
    _sr2p-compact-operation
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2p-zero-span? _sr2p-assert
    _sr2p-compact-transforms @ 1 = _sr2p-assert
    _sr2p-compact-starts @ 1 = _sr2p-assert
    _sr2p-compact-cleanups @ 1 = _sr2p-assert ;

: _sr2p-assert-standard-live  ( -- )
    _sr2p-large-route-operation
        STREAMS-HTTP-ROUTE-OPERATION-VALID? _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-STATUS@
        STREAMS-HTTP-ROUTE-S-OK = _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-STATE@
        STREAMS-HTTP-ROUTE-STATE-RESPONSE = _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-FLOW-STATUS@
        STREAMS-FLOW-S-DELIVERED = _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-DECLARED@
        4097 = _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-RECEIVED@
        4097 = _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-RESPONSE@
        20 = _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-LEASED?
        _sr2p-assert
    _sr2p-large-route-operation _SHTO.FLOW @
        _sr2p-standard-flow = _sr2p-assert
    _sr2p-large-route-operation _SHTO.LEASE @ 0>
        _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-GENERATION@
        _sr2p-standard-flow SFLOW.GENERATION @ =
        _sr2p-assert
    _sr2p-large-route-operation
        STREAMS-HTTP-ROUTE-PAYLOAD-GENERATION@
        _sr2p-standard-egress SPAY.GENERATION @ =
        _sr2p-assert
    _sr2p-large-route-operation _SHTO.EVENT SEVT.FLOW-ID
        RID-ZERO? _sr2p-assert
    _sr2p-large-route-operation _SHTO.EVENT SEVT.CORRELATION-ID
        RID-SIZE 0x82 _sr2p-byte-span? _sr2p-assert

    _sr2p-standard-flow SFLOW.STATE @
        STREAMS-FLOW-STATE-TERMINAL = _sr2p-assert
    _sr2p-standard-flow SFLOW.LAST-STATUS @
        STREAMS-FLOW-S-DELIVERED = _sr2p-assert
    _sr2p-standard-flow SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr2p-assert
    _sr2p-standard-flow SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-DELIVERED = _sr2p-assert
    _sr2p-standard-flow SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr2p-assert
    _sr2p-standard-ingress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-SEALED = _sr2p-assert
    _sr2p-standard-egress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-SEALED = _sr2p-assert
    _sr2p-large-transform-copy _SR2P-LARGE-JSON-CAPACITY
        _sr2p-large-request-json _SR2P-LARGE-JSON-CAPACITY
        _sr2p-span= _sr2p-assert
    _sr2p-standard-egress-copy _SR2P-SMALL-JSON-CAPACITY
        _sr2p-large-route-operation
            STREAMS-HTTP-ROUTE-PAYLOAD-GENERATION@
        _sr2p-standard-egress STREAMS-PAYLOAD-COPY
        STREAMS-PAYLOAD-S-OK = _sr2p-assert
    DUP _sr2p-large-response-json-u @ = _sr2p-assert
    _sr2p-standard-egress-copy SWAP
        _sr2p-large-response-json _sr2p-large-response-json-u @
        _sr2p-span= _sr2p-assert
    _sr2p-standard-operation
        STREAMS-RUNTIME-PROFILE-STANDARD
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2p-zero-span? _sr2p-assert
    _sr2p-standard-transforms @ 1 = _sr2p-assert
    _sr2p-standard-starts @ 1 = _sr2p-assert
    _sr2p-standard-cleanups @ 1 = _sr2p-assert ;

: _sr2p-assert-full-pressure  ( -- )
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 2 =
        _sr2p-assert
    _sr2p-peak-active @ 2 = _sr2p-assert
    _sr2p-compact-flow _sr2p-standard-flow <>
        _sr2p-assert
    _sr2p-compact-flow SFLOW.ID
        _sr2p-standard-flow SFLOW.ID RID= 0= _sr2p-assert
    _sr2p-small-route-operation _sr2p-large-route-operation <>
        _sr2p-assert
    _sr2p-small-route-operation _SHTO.FLOW @
        _sr2p-large-route-operation _SHTO.FLOW @ <>
        _sr2p-assert
    _sr2p-small-route-operation _SHTO.EVENT SEVT.CORRELATION-ID
        _sr2p-large-route-operation _SHTO.EVENT SEVT.CORRELATION-ID
        RID= 0= _sr2p-assert
    _sr2p-output-connector SCON.CALLBACK-BUSY @ 0=
        _sr2p-assert
    _sr2p-output-polls @ 0= _sr2p-assert
    _sr2p-output-cancels @ 0= _sr2p-assert ;

: _sr2p-assert-over-response-ready  ( -- )
    _sr2p-over-connection HCONN-STATE@
        HCONN-STATE-WRITING-RESPONSE = _sr2p-assert
    _sr2p-over-connection HCONN-HTTP-STATUS@ 503 =
        _sr2p-assert
    _sr2p-over-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-RESPONSE = _sr2p-assert
    _sr2p-over-route-operation
        STREAMS-HTTP-ROUTE-OPERATION-VALID? _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-STATUS@
        STREAMS-HTTP-ROUTE-S-POOL-FULL = _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-FLOW-STATUS@
        STREAMS-FLOW-S-FULL = _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-STATE@
        STREAMS-HTTP-ROUTE-STATE-RESPONSE = _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-DECLARED@
        0= _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-RECEIVED@
        0= _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-RESPONSE@
        0= _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-LEASED?
        0= _sr2p-assert
    _sr2p-over-route-operation _SHTO.FLOW @ 0=
        _sr2p-assert
    _sr2p-over-route-operation _SHTO.LEASE @ 0=
        _sr2p-assert
    _sr2p-over-capture-u @ 0= _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 2 =
        _sr2p-assert
    _sr2p-metadata-small @ 1 = _sr2p-assert
    _sr2p-metadata-large @ 1 = _sr2p-assert
    _sr2p-compact-transforms @ 1 = _sr2p-assert
    _sr2p-standard-transforms @ 1 = _sr2p-assert
    _sr2p-compact-starts @ 1 = _sr2p-assert
    _sr2p-standard-starts @ 1 = _sr2p-assert ;

\ ---------------------------------------------------------------------
\ Teardown assertions
\ ---------------------------------------------------------------------

: _sr2p-assert-compact-wiped  ( -- )
    _sr2p-compact-flow SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2p-assert
    _sr2p-compact-flow SFLOW.BUSY @ 0= _sr2p-assert
    _sr2p-compact-ingress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-BUILDING = _sr2p-assert
    _sr2p-compact-egress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-BUILDING = _sr2p-assert
    _sr2p-compact-ingress SPAY.BYTE-U @ 0= _sr2p-assert
    _sr2p-compact-egress SPAY.BYTE-U @ 0= _sr2p-assert
    _sr2p-compact-in-segment SPSEG.USED @ 0= _sr2p-assert
    _sr2p-compact-out-segment SPSEG.USED @ 0= _sr2p-assert
    _sr2p-compact-in-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2p-zero-span? _sr2p-assert
    _sr2p-compact-out-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2p-zero-span? _sr2p-assert
    _sr2p-compact-operation
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2p-zero-span? _sr2p-assert ;

: _sr2p-assert-standard-wiped  ( -- )
    _sr2p-standard-flow SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2p-assert
    _sr2p-standard-flow SFLOW.BUSY @ 0= _sr2p-assert
    _sr2p-standard-ingress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-BUILDING = _sr2p-assert
    _sr2p-standard-egress SPAY.STATE @
        STREAMS-PAYLOAD-STATE-BUILDING = _sr2p-assert
    _sr2p-standard-ingress SPAY.BYTE-U @ 0= _sr2p-assert
    _sr2p-standard-egress SPAY.BYTE-U @ 0= _sr2p-assert
    _sr2p-standard-in-segments 4
        _sr2p-segments-unused? _sr2p-assert
    _sr2p-standard-out-segments 4
        _sr2p-segments-unused? _sr2p-assert
    _sr2p-standard-in-bytes
        STREAMS-RUNTIME-SEGMENT-BYTES 4 *
        _sr2p-zero-span? _sr2p-assert
    _sr2p-standard-out-bytes
        STREAMS-RUNTIME-SEGMENT-BYTES 4 *
        _sr2p-zero-span? _sr2p-assert
    _sr2p-standard-operation
        STREAMS-RUNTIME-PROFILE-STANDARD
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2p-zero-span? _sr2p-assert ;

: _sr2p-assert-final-ports  ( -- )
    _sr2p-small-port-cancels @ 1 = _sr2p-assert
    _sr2p-small-port-closes @ 0= _sr2p-assert
    _sr2p-small-port NIO.OPEN-STATE @
        NIO-OPEN-STATE-CANCELLED = _sr2p-assert
    _sr2p-small-port NIO.CLOSE-STATE @
        NIO-CLOSE-STATE-CANCELLED = _sr2p-assert
    _sr2p-small-port NIO.CLEANUP-FLAGS @
        NIO-CLEANUP-F-CANCEL-ATTEMPTED = _sr2p-assert
    _sr2p-large-port-cancels @ 0= _sr2p-assert
    _sr2p-large-port-closes @ 1 = _sr2p-assert
    _sr2p-large-port NIO.OPEN-STATE @
        NIO-OPEN-STATE-CLOSED = _sr2p-assert
    _sr2p-large-port NIO.CLOSE-STATE @
        NIO-CLOSE-STATE-CLOSED = _sr2p-assert
    _sr2p-large-port NIO.CLEANUP-FLAGS @
        NIO-CLEANUP-F-CLOSE-ATTEMPTED = _sr2p-assert
    _sr2p-over-port-cancels @ 0= _sr2p-assert
    _sr2p-over-port-closes @ 1 = _sr2p-assert
    _sr2p-over-port NIO.OPEN-STATE @
        NIO-OPEN-STATE-CLOSED = _sr2p-assert
    _sr2p-over-port NIO.CLOSE-STATE @
        NIO-CLOSE-STATE-CLOSED = _sr2p-assert
    _sr2p-over-port NIO.CLEANUP-FLAGS @
        NIO-CLEANUP-F-CLOSE-ATTEMPTED = _sr2p-assert ;

: _sr2p-test-pressure  ( -- )
    100 _sr2p-stage !
    _sr2p-setup-http
    101 _sr2p-stage !
    _sr2p-assert-owner-isolation
    102 _sr2p-stage !
    _sr2p-small-connection HCONN-START HCONN-S-PENDING =
        _sr2p-assert
    103 _sr2p-stage !
    4096 0 ?DO
        _sr2p-small-zero-sends @ IF LEAVE THEN
        _sr2p-small-connection HCONN-TERMINAL? IF LEAVE THEN
        _sr2p-step-small
    LOOP
    110 _sr2p-stage !
    _sr2p-small-zero-sends @ 1 = _sr2p-assert
    _sr2p-small-connection HCONN-STATE@
        HCONN-STATE-PORT-POLL = _sr2p-assert
    _sr2p-small-connection HCONN-TERMINAL? 0=
        _sr2p-assert
    _sr2p-small-connection HCONN-HTTP-STATUS@ 200 =
        _sr2p-assert
    _sr2p-small-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-RESPONSE = _sr2p-assert
    _sr2p-small-response HRESP-BODY-SENT@ 0>
        _sr2p-assert
    _sr2p-small-response HRESP-BODY-SENT@
        _sr2p-small-response HRESP-BODY-U@ <
        _sr2p-assert
    _sr2p-small-response HRESP-BODY-SENT@ 5 =
        _sr2p-assert
    _sr2p-small-capture-u @ 0> _sr2p-assert
    _sr2p-small-capture-u @ _sr2p-small-expected-u @ <
        _sr2p-assert
    _sr2p-small-capture _sr2p-small-capture-u @
        _sr2p-small-expected _sr2p-small-capture-u @
        _sr2p-span= _sr2p-assert
    _sr2p-small-input-position @ _sr2p-small-input-u @ =
        _sr2p-assert
    _sr2p-assert-compact-live

    200 _sr2p-stage !
    _sr2p-large-connection HCONN-START HCONN-S-PENDING =
        _sr2p-assert
    16384 0 ?DO
        _sr2p-large-connection HCONN-STATE@
            HCONN-STATE-WRITING-RESPONSE = IF LEAVE THEN
        _sr2p-large-connection HCONN-TERMINAL? IF LEAVE THEN
        _sr2p-step-large
    LOOP
    210 _sr2p-stage !
    _sr2p-large-connection HCONN-STATE@
        HCONN-STATE-WRITING-RESPONSE = _sr2p-assert
    _sr2p-large-connection HCONN-TERMINAL? 0=
        _sr2p-assert
    _sr2p-large-connection HCONN-HTTP-STATUS@ 200 =
        _sr2p-assert
    _sr2p-large-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-RESPONSE = _sr2p-assert
    _sr2p-large-capture-u @ 0= _sr2p-assert
    _sr2p-large-input-position @ _sr2p-large-input-u @ =
        _sr2p-assert
    _sr2p-assert-standard-live
    _sr2p-assert-compact-live
    _sr2p-assert-full-pressure

    300 _sr2p-stage !
    _sr2p-over-connection HCONN-START HCONN-S-PENDING =
        _sr2p-assert
    4096 0 ?DO
        _sr2p-over-connection HCONN-STATE@
            HCONN-STATE-WRITING-RESPONSE = IF LEAVE THEN
        _sr2p-over-connection HCONN-TERMINAL? IF LEAVE THEN
        _sr2p-step-over
    LOOP
    310 _sr2p-stage !
    _sr2p-assert-over-response-ready
    _sr2p-assert-standard-live
    _sr2p-assert-compact-live
    _sr2p-assert-full-pressure

    320 _sr2p-stage !
    4096 0 ?DO
        _sr2p-over-connection HCONN-TERMINAL? IF LEAVE THEN
        _sr2p-step-over
    LOOP
    _sr2p-over-connection HCONN-TERMINAL? _sr2p-assert
    _sr2p-over-connection HCONN-RESULT@ HCONN-S-DONE =
        _sr2p-assert
    _sr2p-over-connection HCONN-STATUS@ HCONN-S-DONE =
        _sr2p-assert
    _sr2p-over-connection HCONN-CLEANUP-ERROR@ 0=
        _sr2p-assert
    _sr2p-over-connection HCONN-TRANSPORT-STATUS@
        NIO-S-OK = _sr2p-assert
    _sr2p-over-connection HCONN-HTTP-STATUS@ 503 =
        _sr2p-assert
    _sr2p-over-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-RESPONSE = _sr2p-assert
    _sr2p-over-capture-u @ _sr2p-over-expected-u @ =
        _sr2p-assert
    _sr2p-over-capture _sr2p-over-capture-u @
        _sr2p-over-expected _sr2p-over-expected-u @
        _sr2p-span= _sr2p-assert
    _sr2p-over-response HRESP.OUTCOME @
        HRESP-OUTCOME-SENT = _sr2p-assert
    _sr2p-over-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
        _sr2p-zero-span? _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 2 =
        _sr2p-assert

    400 _sr2p-stage !
    _sr2p-small-capture-u @ _sr2p-small-capture-before-cancel !
    _sr2p-small-connection HCONN-CANCEL HCONN-S-PENDING =
        _sr2p-assert
    4096 0 ?DO
        _sr2p-small-connection HCONN-TERMINAL? IF LEAVE THEN
        _sr2p-step-small
    LOOP
    410 _sr2p-stage !
    _sr2p-small-connection HCONN-TERMINAL? _sr2p-assert
    _sr2p-small-connection HCONN-RESULT@ HCONN-S-CANCELLED =
        _sr2p-assert
    _sr2p-small-connection HCONN-STATUS@ HCONN-S-CANCELLED =
        _sr2p-assert
    _sr2p-small-connection HCONN-HTTP-STATUS@ 200 =
        _sr2p-assert
    _sr2p-small-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-CANCELLED = _sr2p-assert
    _sr2p-small-connection HCONN-CLEANUP-ERROR@ 0=
        _sr2p-assert
    _sr2p-small-connection HCONN-TRANSPORT-STATUS@
        NIO-S-CANCELLED = _sr2p-assert
    _sr2p-small-response HRESP.OUTCOME @
        HRESP-OUTCOME-CANCELLED-AFTER-BYTES = _sr2p-assert
    _sr2p-small-capture-u @ _sr2p-small-capture-before-cancel @ =
        _sr2p-assert
    _sr2p-small-response HRESP-BODY-SENT@ 5 =
        _sr2p-assert
    _sr2p-small-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
        _sr2p-zero-span? _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 1 =
        _sr2p-assert
    _sr2p-assert-compact-wiped
    _sr2p-large-connection HCONN-TERMINAL? 0=
        _sr2p-assert
    _sr2p-large-capture-u @ 0= _sr2p-assert
    _sr2p-assert-standard-live

    500 _sr2p-stage !
    4096 0 ?DO
        _sr2p-large-connection HCONN-TERMINAL? IF LEAVE THEN
        _sr2p-step-large
    LOOP
    _sr2p-large-connection HCONN-TERMINAL? _sr2p-assert
    _sr2p-large-connection HCONN-RESULT@ HCONN-S-DONE =
        _sr2p-assert
    _sr2p-large-connection HCONN-STATUS@ HCONN-S-DONE =
        _sr2p-assert
    _sr2p-large-connection HCONN-CLEANUP-ERROR@ 0=
        _sr2p-assert
    _sr2p-large-connection HCONN-TRANSPORT-STATUS@
        NIO-S-OK = _sr2p-assert
    _sr2p-large-connection HCONN-HTTP-STATUS@ 200 =
        _sr2p-assert
    _sr2p-large-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-RESPONSE = _sr2p-assert
    _sr2p-large-capture-u @ _sr2p-large-expected-u @ =
        _sr2p-assert
    _sr2p-large-capture _sr2p-large-capture-u @
        _sr2p-large-expected _sr2p-large-expected-u @
        _sr2p-span= _sr2p-assert
    _sr2p-large-response HRESP.OUTCOME @
        HRESP-OUTCOME-SENT = _sr2p-assert
    _sr2p-large-route-operation STREAMS-HTTP-ROUTE-OPERATION-SIZE
        _sr2p-zero-span? _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
        _sr2p-assert
    _sr2p-assert-standard-wiped
    _sr2p-assert-compact-wiped

    600 _sr2p-stage !
    _sr2p-assert-final-ports
    _sr2p-output-connector SCON.CALLBACK-BUSY @ 0=
        _sr2p-assert
    _sr2p-output-polls @ 0= _sr2p-assert
    _sr2p-output-cancels @ 0= _sr2p-assert
    _sr2p-compact-transforms @ 1 = _sr2p-assert
    _sr2p-standard-transforms @ 1 = _sr2p-assert
    _sr2p-compact-starts @ 1 = _sr2p-assert
    _sr2p-standard-starts @ 1 = _sr2p-assert
    _sr2p-compact-cleanups @ 1 = _sr2p-assert
    _sr2p-standard-cleanups @ 1 = _sr2p-assert
    _sr2p-metadata-small @ 1 = _sr2p-assert
    _sr2p-metadata-large @ 1 = _sr2p-assert
    _sr2p-peak-active @ 2 = _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-VALID? _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-CAPACITY@ 2 =
        _sr2p-assert
    _sr2p-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
        _sr2p-assert
    _sr2p-config STREAMS-HTTP-ROUTE-CONFIG-VALID? _sr2p-assert
    _sr2p-router HROUTER-VALID? _sr2p-assert
    _sr2p-input-connector STREAMS-CONNECTOR-VALID? _sr2p-assert
    _sr2p-output-connector STREAMS-CONNECTOR-VALID? _sr2p-assert
    _sr2p-input-connector SCON.ID RID-SIZE
        0x41 _sr2p-byte-span? _sr2p-assert
    _sr2p-input-connector SCON.ENDPOINT-ID RID-SIZE
        0x51 _sr2p-byte-span? _sr2p-assert
    _sr2p-output-connector SCON.ID RID-SIZE
        0x42 _sr2p-byte-span? _sr2p-assert
    _sr2p-output-connector SCON.ENDPOINT-ID RID-SIZE
        0x52 _sr2p-byte-span? _sr2p-assert
    _sr2p-stack ;

: _SR2P-RUN  ( -- )
    0 _sr2p-fails !
    0 _sr2p-checks !
    DEPTH _sr2p-depth !
    1 _sr2p-stage !
    _sr2p-build-json
    _sr2p-build-requests
    _sr2p-build-expected
    _sr2p-assert-geometry
    _sr2p-setup-connectors
    _sr2p-setup-runtime
    _sr2p-setup-route
    _sr2p-stack
    _sr2p-test-pressure
    900 _sr2p-stage !
    _sr2p-stack
    ." STREAMS SR2 HTTP PRESSURE METRICS steps "
        _sr2p-small-steps @ .
        _sr2p-large-steps @ .
        _sr2p-over-steps @ .
        ." peak " _sr2p-peak-active @ .
        ." pool-bytes "
        _sr2p-pool STREAMS-EXECUTION-POOL-RUNTIME-BYTES@ .
        ." connection-bytes " 7776 .
        ." pressure-bytes " 55400 . CR
    _sr2p-fails @ 0= IF
        ." STREAMS SR2 HTTP PRESSURE PASS "
        _sr2p-checks @ . CR
    ELSE
        ." STREAMS SR2 HTTP PRESSURE FAIL "
        _sr2p-fails @ . ." / " _sr2p-checks @ . CR
    THEN ;
