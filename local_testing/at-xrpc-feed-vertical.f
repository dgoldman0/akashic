\ Focused authenticated PDS author-feed to Streams qualification.
\
\ The boot filesystem fixture is detached before the durable-session
\ fixture installs its RAM VFS.  A bounded fake NIO peer then serves one
\ strict HTTP 400 use_dpop_nonce challenge followed by the checked feed
\ document and a rotated nonce.  Production code builds both authenticated
\ proxy requests, decodes the BFM projection, and admits the validated raw
\ JSON through the production AT input connector into a compact Streams
\ flow.  The flow carrier must retain the page after XRPC cleanup wipes the
\ caller-owned response arena.

REQUIRE at-xrpc-auth-read-test.f

PROVIDED at-xrpc-feed-vert

1024 CONSTANT _ATFV-RESPONSE-FRAMING-RESERVE
32 CONSTANT _ATFV-POLL-LIMIT
1 CONSTANT _ATFV-FLOW-REVISION
100 CONSTANT _ATFV-NOW
26 CONSTANT _ATFV-CHALLENGE-BYTES

VARIABLE _atfv-load-depth
VARIABLE _atfv-document-a
VARIABLE _atfv-document-u
VARIABLE _atfv-load-fd

VARIABLE _atfv-owner
VARIABLE _atfv-request-a
VARIABLE _atfv-body-a
VARIABLE _atfv-response-a
VARIABLE _atfv-response-cap
VARIABLE _atfv-response-u
VARIABLE _atfv-response-pos
VARIABLE _atfv-response-end
VARIABLE _atfv-first-response-u
VARIABLE _atfv-sent-a
VARIABLE _atfv-sent-cap
VARIABLE _atfv-sent-u
VARIABLE _atfv-expected-a
VARIABLE _atfv-expected-u
VARIABLE _atfv-readback-a
VARIABLE _atfv-exchange
VARIABLE _atfv-generation

VARIABLE _atfv-open-count
VARIABLE _atfv-close-count
VARIABLE _atfv-request-start
VARIABLE _atfv-request1-u
VARIABLE _atfv-request2-u
VARIABLE _atfv-first-nonce-ok
VARIABLE _atfv-second-nonce-ok
VARIABLE _atfv-polls
VARIABLE _atfv-step

VARIABLE _atfv-transform-calls
VARIABLE _atfv-output-starts
VARIABLE _atfv-output-polls
VARIABLE _atfv-output-cancels
VARIABLE _atfv-output-cleanups
VARIABLE _atfv-output-u
VARIABLE _atfv-cb-event
VARIABLE _atfv-cb-carrier
VARIABLE _atfv-cb-result

RID-SIZE XBUF _atfv-input-id
RID-SIZE XBUF _atfv-input-endpoint
RID-SIZE XBUF _atfv-output-id
RID-SIZE XBUF _atfv-output-endpoint
RID-SIZE XBUF _atfv-flow-id

XIO-OP-SIZE XBUF _atfv-op
STREAMS-CONNECTOR-SIZE XBUF _atfv-output
STREAMS-FLOW-SIZE XBUF _atfv-flow
STREAMS-PAYLOAD-SIZE XBUF _atfv-ingress
STREAMS-PAYLOAD-SIZE XBUF _atfv-egress
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _atfv-ingress-segment
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _atfv-egress-segment
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _atfv-ingress-bytes
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _atfv-egress-bytes
STREAMS-RUNTIME-COMPACT-OPERATION-BYTES XBUF _atfv-flow-operation

CREATE _atfv-crlf 13 C, 10 C,
CREATE _atfv-quote 34 C,

\ ---------------------------------------------------------------------
\ Fixture and allocation helpers
\ ---------------------------------------------------------------------

: _atfv-allocate  ( size variable -- )
    >R
    ALLOCATE ABORT" AT XRPC feed allocation failed"
    R> ! ;

: _atfv-free  ( variable -- )
    DUP @ ?DUP IF
        FREE
        0 SWAP !
    ELSE
        DROP
    THEN ;

: _ATFV-LOAD  ( -- )
    DEPTH _atfv-load-depth !
    NAMEBUF 24 0 FILL
    S" atfv-feed.json" NAMEBUF SWAP CMOVE
    FIND-BY-NAME DUP -1 = ABORT" AT XRPC feed fixture missing"
    OPEN-BY-SLOT DUP 0= ABORT" AT XRPC feed fixture open failed"
    DUP _atfv-load-fd !
    FSIZE DUP 0= ABORT" AT XRPC feed fixture empty"
    DUP _atfv-document-u !
    ALLOCATE ABORT" AT XRPC feed fixture allocation failed"
    DUP _atfv-document-a !
    _atfv-document-u @ _atfv-load-fd @ FREAD
    _atfv-document-u @ <>
        ABORT" AT XRPC feed fixture read failed"
    _atfv-load-fd @ FCLOSE
    0 _atfv-load-fd !
    _atfv-document-u @
    STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY >
        ABORT" AT XRPC feed fixture exceeds compact carrier"
    DEPTH _atfv-load-depth @ <>
        ABORT" AT XRPC feed fixture stack" ;

\ ---------------------------------------------------------------------
\ Bounded response and expected-wire builders
\ ---------------------------------------------------------------------

: _atfv-response+  ( address length -- )
    DUP _atfv-response-u @ +
    _atfv-response-cap @ U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atfv-response-a @ _atfv-response-u @ + SWAP CMOVE
    R> _atfv-response-u +! ;

: _atfv-response-crlf  ( -- )
    _atfv-crlf 2 _atfv-response+ ;

: _atfv-challenge+  ( -- )
    S" {" _atfv-response+
    _atfv-quote 1 _atfv-response+
    S" error" _atfv-response+
    _atfv-quote 1 _atfv-response+
    S" :" _atfv-response+
    _atfv-quote 1 _atfv-response+
    S" use_dpop_nonce" _atfv-response+
    _atfv-quote 1 _atfv-response+
    S" }" _atfv-response+ ;

: _atfv-build-responses  ( -- )
    _atfv-response-a @ _atfv-response-cap @ 0 FILL
    0 _atfv-response-u !
    0 _atfv-response-pos !
    0 _atfv-response-end !

    S" HTTP/1.1 400 Bad Request" _atfv-response+
    _atfv-response-crlf
    S" Content-Type: application/json" _atfv-response+
    _atfv-response-crlf
    S" DPoP-Nonce: pds-nonce-1" _atfv-response+
    _atfv-response-crlf
    S" Content-Length: " _atfv-response+
    _ATFV-CHALLENGE-BYTES NUM>STR _atfv-response+
    _atfv-response-crlf
    S" Connection: close" _atfv-response+
    _atfv-response-crlf
    _atfv-response-crlf
    _atfv-response-u @ >R
    _atfv-challenge+
    _atfv-response-u @ R> -
        _ATFV-CHALLENGE-BYTES = _atxr-assert
    _atfv-response-u @ _atfv-first-response-u !

    S" HTTP/1.1 200 OK" _atfv-response+
    _atfv-response-crlf
    S" Content-Type: application/json" _atfv-response+
    _atfv-response-crlf
    S" DPoP-Nonce: pds-nonce-2" _atfv-response+
    _atfv-response-crlf
    S" Content-Length: " _atfv-response+
    _atfv-document-u @ NUM>STR _atfv-response+
    _atfv-response-crlf
    S" Connection: close" _atfv-response+
    _atfv-response-crlf
    _atfv-response-crlf
    _atfv-document-a @ _atfv-document-u @ _atfv-response+ ;

: _atfv-expected+  ( address length -- )
    DUP _atfv-expected-u @ +
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atfv-expected-a @ _atfv-expected-u @ + SWAP CMOVE
    R> _atfv-expected-u +! ;

: _atfv-expected-crlf  ( -- )
    _atfv-crlf 2 _atfv-expected+ ;

: _atfv-build-expected  ( -- )
    _atfv-expected-a @
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 0 FILL
    0 _atfv-expected-u !
    S" GET /xrpc/app.bsky.feed.getAuthorFeed?actor="
        _atfv-expected+
    S" did%3Aplc%3Aabcdefghijklmnopqrstuvwx"
        _atfv-expected+
    S" &limit=" _atfv-expected+
    BFM-MAX-ITEMS NUM>STR _atfv-expected+
    S" &filter=posts_with_replies&includePins=false HTTP/1.1"
        _atfv-expected+
    _atfv-expected-crlf
    S" Host: pds.example" _atfv-expected+
    _atfv-expected-crlf
    S" Accept: application/json" _atfv-expected+
    _atfv-expected-crlf
    S" Authorization: DPoP access-vertical" _atfv-expected+
    _atfv-expected-crlf
    S" DPoP: deterministic-dpop-proof" _atfv-expected+
    _atfv-expected-crlf
    S" atproto-proxy: did:web:api.bsky.app#bsky_appview"
        _atfv-expected+
    _atfv-expected-crlf
    S" Accept-Encoding: identity" _atfv-expected+
    _atfv-expected-crlf
    S" User-Agent: akashic-atproto/1" _atfv-expected+
    _atfv-expected-crlf
    S" Connection: close" _atfv-expected+
    _atfv-expected-crlf
    _atfv-expected-crlf ;

\ ---------------------------------------------------------------------
\ Deterministic two-response NIO peer
\ ---------------------------------------------------------------------

VARIABLE _atfv-io-a
VARIABLE _atfv-io-u
VARIABLE _atfv-io-n

: _atfv-open  ( context -- io-status )
    DROP
    _atfv-sent-u @ _atfv-request-start !
    1 _atfv-open-count +!
    _atfv-open-count @ 1 = IF
        _atfv-first-response-u @
    ELSE
        _atfv-response-u @
    THEN
    _atfv-response-end !
    NIO-S-OK ;

: _atfv-send  ( buffer length context -- count io-status )
    DROP
    _atfv-io-u !
    _atfv-io-a !
    _atfv-sent-u @ _atfv-io-u @ +
    _atfv-sent-cap @ U> IF
        0 NIO-S-FAILED EXIT
    THEN
    _atfv-io-a @
    _atfv-sent-a @ _atfv-sent-u @ +
    _atfv-io-u @ CMOVE
    _atfv-io-u @ _atfv-sent-u +!

    _atfv-open-count @ 1 = IF
        _O2PKD-DPOP-NONCE-A @ 0=
        _O2PKD-DPOP-NONCE-U @ 0= AND
        _atfv-first-nonce-ok !
    THEN
    _atfv-open-count @ 2 = IF
        _O2PKD-DPOP-NONCE-A @
        _O2PKD-DPOP-NONCE-U @
        S" pds-nonce-1" COMPARE 0=
        _atfv-second-nonce-ok !
    THEN
    _atfv-io-u @ NIO-S-OK ;

: _atfv-recv  ( buffer capacity context -- count io-status )
    DROP
    _atfv-io-u !
    _atfv-io-a !
    _atfv-response-end @ _atfv-response-pos @ -
    DUP 0= IF
        DROP 0 NIO-S-EOF EXIT
    THEN
    _atfv-io-u @ MIN _atfv-io-n !
    _atfv-response-a @ _atfv-response-pos @ +
    _atfv-io-a @ _atfv-io-n @ CMOVE
    _atfv-io-n @ _atfv-response-pos +!
    _atfv-io-n @ NIO-S-OK ;

: _atfv-poll  ( context -- )
    DROP ;

: _atfv-cancel  ( context -- )
    DROP ;

: _atfv-close  ( context -- io-status )
    DROP
    _atfv-sent-u @ _atfv-request-start @ -
    _atfv-close-count @ 0= IF
        _atfv-request1-u !
    ELSE
        _atfv-request2-u !
    THEN
    1 _atfv-close-count +!
    NIO-S-OK ;

: _atfv-install-port  ( -- )
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-PORT
    DUP 0<> _atxr-assert
    DUP NIO-INIT
    DUP DUP NIO.CONTEXT !
    ['] _atfv-open OVER NIO.OPEN-START-XT !
    ['] _atfv-open OVER NIO.OPEN-POLL-XT !
    ['] _atfv-send OVER NIO.SEND-XT !
    ['] _atfv-recv OVER NIO.RECV-XT !
    ['] _atfv-poll OVER NIO.POLL-XT !
    ['] _atfv-cancel OVER NIO.CANCEL-XT !
    ['] _atfv-close OVER NIO.CLOSE-START-XT !
    ['] _atfv-close SWAP NIO.CLOSE-POLL-XT ! ;

\ ---------------------------------------------------------------------
\ Injected Streams transform and output connector
\ ---------------------------------------------------------------------

: _atfv-transform-result!
  ( completion output-u detail error result -- )
    >R
    R@ STRR.ERROR !
    R@ STRR.DETAIL !
    R@ STRR.OUTPUT-U !
    R> STRR.COMPLETION ! ;

: _atfv-connector-result!
  ( completion effect detail error result -- )
    >R
    R@ SCRR.ERROR !
    R@ SCRR.DETAIL !
    R@ SCRR.EFFECT !
    R> SCRR.COMPLETION ! ;

: _atfv-transform  ( ingress-event output-carrier context result -- )
    _atfv-cb-result !
    DROP
    _atfv-cb-carrier !
    _atfv-cb-event !
    1 _atfv-transform-calls +!
    _atfv-cb-carrier @ SPAY.GENERATION @
    _atfv-cb-carrier @ _atfv-cb-event @
    STREAMS-EVENT-APPEND-TO-CARRIER
    STREAMS-FLOW-S-OK _atxr-status
    STREAMS-TRANSFORM-COMPLETION-OK
    _atfv-cb-carrier @ SPAY.BYTE-U @ 0 0
    _atfv-cb-result @ _atfv-transform-result! ;

: _atfv-output-start  ( event operation context result -- )
    _atfv-cb-result !
    DROP DROP
    _atfv-cb-event !
    1 _atfv-output-starts +!
    _atfv-readback-a @ _atfv-document-u @
    _atfv-cb-event @ STREAMS-EVENT-PAYLOAD-COPY
    STREAMS-FLOW-S-OK _atxr-status
    DUP _atfv-output-u !
    _atfv-document-u @ = _atxr-assert
    _atfv-readback-a @ _atfv-document-u @
    _atfv-document-a @ _atfv-document-u @
    COMPARE 0= _atxr-assert
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _atfv-cb-result @ _atfv-connector-result! ;

: _atfv-output-poll  ( event operation context result -- )
    _atfv-cb-result !
    2DROP DROP
    1 _atfv-output-polls +!
    STREAMS-CONNECTOR-COMPLETION-FAILED
    STREAMS-EFFECT-NOT-APPLIED 0 -4751
    _atfv-cb-result @ _atfv-connector-result! ;

: _atfv-output-cancel  ( event operation context result -- )
    _atfv-cb-result !
    2DROP DROP
    1 _atfv-output-cancels +!
    STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED 0 0
    _atfv-cb-result @ _atfv-connector-result! ;

: _atfv-output-cleanup  ( event operation context -- error )
    2DROP DROP
    1 _atfv-output-cleanups +!
    0 ;

: _atfv-setup-flow  ( -- )
    _atfv-ingress-bytes STREAMS-RUNTIME-SEGMENT-BYTES
    _atfv-ingress-segment STREAMS-PAYLOAD-SEGMENT-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status
    _atfv-egress-bytes STREAMS-RUNTIME-SEGMENT-BYTES
    _atfv-egress-segment STREAMS-PAYLOAD-SEGMENT-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status

    _atfv-ingress-segment 1
    STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-PAYLOAD-F-WIPE 0 0 _atfv-ingress
    STREAMS-PAYLOAD-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status
    _atfv-egress-segment 1
    STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-PAYLOAD-F-WIPE 0 0 _atfv-egress
    STREAMS-PAYLOAD-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status

    _atfv-output STREAMS-CONNECTOR-INIT
    STREAMS-FLOW-S-OK _atxr-status
    _atfv-output-id _atfv-output SCON.ID RID-COPY
    _atfv-output-endpoint _atfv-output SCON.ENDPOINT-ID RID-COPY
    1 _atfv-output SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT
    _atfv-output SCON.DIRECTION !
    STREAMS-PROTOCOL-ATPROTO _atfv-output SCON.PROTOCOL !
    0 _atfv-output SCON.CONTEXT !
    1 CELLS _atfv-output SCON.OP-SIZE !
    ['] _atfv-output-start _atfv-output SCON.START-XT !
    ['] _atfv-output-poll _atfv-output SCON.POLL-XT !
    ['] _atfv-output-cancel _atfv-output SCON.CANCEL-XT !
    ['] _atfv-output-cleanup _atfv-output SCON.CLEANUP-XT !
    _atfv-output STREAMS-CONNECTOR-SEAL
    STREAMS-FLOW-S-OK _atxr-status

    _atfv-flow STREAMS-FLOW-INIT
    STREAMS-FLOW-S-OK _atxr-status
    STREAMS-RUNTIME-PROFILE-COMPACT
    _atfv-ingress _atfv-egress
    _atfv-flow-operation
    STREAMS-RUNTIME-COMPACT-OPERATION-BYTES
    _atfv-flow STREAMS-FLOW-WORKSPACE!
    STREAMS-FLOW-S-OK _atxr-status
    _atfv-flow-id _atfv-flow SFLOW.ID RID-COPY
    _ATFV-FLOW-REVISION _atfv-flow SFLOW.REVISION !
    1000 _atfv-flow SFLOW.TIMEOUT-MS !
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-CONNECTOR@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atfv-flow SFLOW.INPUT-CONNECTOR !
    _atfv-output _atfv-flow SFLOW.OUTPUT-CONNECTOR !
    ['] _atfv-transform _atfv-flow SFLOW.TRANSFORM-XT !
    0 _atfv-flow SFLOW.TRANSFORM-CONTEXT !
    STREAMS-MEDIA-BSKY-FEED-JSON
    _atfv-flow SFLOW.OUTPUT-MEDIA !
    _atfv-flow STREAMS-FLOW-SEAL
    STREAMS-FLOW-S-OK _atxr-status
    _atfv-flow STREAMS-FLOW-VALID? _atxr-assert ;

\ ---------------------------------------------------------------------
\ Production owner setup and cooperative exchange drive
\ ---------------------------------------------------------------------

: _atfv-reset-observations  ( -- )
    0 _atfv-open-count !
    0 _atfv-close-count !
    0 _atfv-request-start !
    0 _atfv-request1-u !
    0 _atfv-request2-u !
    0 _atfv-first-nonce-ok !
    0 _atfv-second-nonce-ok !
    0 _atfv-transform-calls !
    0 _atfv-output-starts !
    0 _atfv-output-polls !
    0 _atfv-output-cancels !
    0 _atfv-output-cleanups !
    0 _atfv-output-u !
    0 _atfv-sent-u ! ;

: _atfv-prepare-owner  ( -- )
    AT-AUTHOR-FEED-CONNECTOR-SIZE
    _atfv-owner _atfv-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atfv-request-a _atfv-allocate
    _atfv-document-u @ _atfv-body-a _atfv-allocate
    _atfv-document-u @ _ATFV-RESPONSE-FRAMING-RESERVE +
    DUP _atfv-response-cap !
    _atfv-response-a _atfv-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 2 *
    DUP _atfv-sent-cap !
    _atfv-sent-a _atfv-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atfv-expected-a _atfv-allocate
    _atfv-document-u @ _atfv-readback-a _atfv-allocate

    _atfv-input-id RID-SIZE 0x71 FILL
    _atfv-input-endpoint RID-SIZE 0x72 FILL
    _atfv-output-id RID-SIZE 0x73 FILL
    _atfv-output-endpoint RID-SIZE 0x74 FILL
    _atfv-flow-id RID-SIZE 0x75 FILL
    _atfv-op XIO-OP-INIT
    _atfv-reset-observations

    _atfv-input-id _atfv-input-endpoint 1
    _atfv-request-a @
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atfv-body-a @ _atfv-document-u @
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-INIT
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-VALID?
    _atxr-assert

    _atxr-active-vault @
    _atoct-config
    _atopt-profile
    _atxr-active-session @
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-BIND
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status

    _ATXR-IAT
    S" did:plc:abcdefghijklmnopqrstuvwx"
    BFM-MAX-ITEMS
    0 0
    AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-REPLIES
    0
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-PREPARE
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status

    _atfv-setup-flow
    _atfv-build-responses
    _atfv-build-expected
    _atfv-sent-a @ _atfv-sent-cap @ 0 FILL
    _atfv-readback-a @ _atfv-document-u @ 0 FILL
    _O2PKD-RESET
    _atfv-install-port ;

: _atfv-drive  ( -- )
    _atfv-op _atfv-owner @
    AT-AUTHOR-FEED-CONNECTOR-XIO-START
    XIO-STEP-PENDING = _atxr-assert
    0 _atfv-polls !
    BEGIN
        _atfv-op _atfv-owner @
        AT-AUTHOR-FEED-CONNECTOR-XIO-POLL
        DUP _atfv-step !
        XIO-STEP-PENDING =
    WHILE
        1 _atfv-polls +!
        _atfv-polls @ _ATFV-POLL-LIMIT >= IF
            0 _atxr-assert EXIT
        THEN
    REPEAT
    _atfv-step @ XIO-STEP-SUCCEEDED = _atxr-assert ;

\ ---------------------------------------------------------------------
\ Focused semantic, wire, carrier, and lifecycle assertions
\ ---------------------------------------------------------------------

: _atfv-check-feed  ( feed -- )
    DUP BFM.FEED.COUNT @ 2 = _atxr-assert
    DUP BFM.FEED.CURSOR
    OVER BFM.FEED.CURSOR-U @
    S" page-2-token" COMPARE 0= _atxr-assert
    DUP 0 SWAP BFM.FEED.ITEM
    DUP 0<> _atxr-assert
    BFM.ITEM.TEXT
    S" Injected fixtures make network behavior reviewable."
    COMPARE 0= _atxr-assert
    1 SWAP BFM.FEED.ITEM
    DUP 0<> _atxr-assert
    DUP BFM.ITEM.FLAGS @ BFM-F-REPLY AND 0<>
    _atxr-assert
    BFM.ITEM.TEXT
    S" Does the thread retain identity across a cached restart?"
    COMPARE 0= _atxr-assert ;

: _atfv-check-wire  ( -- )
    _atfv-open-count @ 2 = _atxr-assert
    _atfv-close-count @ 2 = _atxr-assert
    _atfv-request1-u @ _atfv-expected-u @ =
    _atxr-assert
    _atfv-request2-u @ _atfv-expected-u @ =
    _atxr-assert
    _atfv-request1-u @ _atfv-request2-u @ +
    _atfv-sent-u @ = _atxr-assert
    _atfv-sent-a @ _atfv-request1-u @
    _atfv-expected-a @ _atfv-expected-u @
    COMPARE 0= _atxr-assert
    _atfv-sent-a @ _atfv-request1-u @ +
    _atfv-request2-u @
    _atfv-expected-a @ _atfv-expected-u @
    COMPARE 0= _atxr-assert
    _atfv-first-nonce-ok @ _atxr-assert
    _atfv-second-nonce-ok @ _atxr-assert
    _O2PKD-DPOP-CALLS @ 2 = _atxr-assert
    _O2PKD-DPOP-HTM-A @ _O2PKD-DPOP-HTM-U @
    S" GET" COMPARE 0= _atxr-assert
    _O2PKD-DPOP-HTU-A @ _O2PKD-DPOP-HTU-U @
    S" https://pds.example/xrpc/app.bsky.feed.getAuthorFeed"
    COMPARE 0= _atxr-assert ;

: _atfv-check-ready  ( -- )
    _atfv-op XIOO.RESULT @ _atfv-owner @ =
    _atxr-assert
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-EXCHANGE@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    DUP _atfv-exchange !
    AT-XRPC-EXCHANGE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-STATE-READY = _atxr-assert
    _atfv-exchange @ AT-XRPC-EXCHANGE-HTTP-CODE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    200 = _atxr-assert
    _atfv-exchange @ AT-XRPC-EXCHANGE-ATTEMPTS@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    2 = _atxr-assert
    _atfv-exchange @ AT-XRPC-EXCHANGE-NONCE-GENERATION@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    2 = _atxr-assert
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-BODY@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atfv-document-a @ _atfv-document-u @
    COMPARE 0= _atxr-assert
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-FEED@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atfv-check-feed
    _atfv-check-wire ;

: _atfv-check-carrier-after-wipe  ( -- )
    _atfv-body-a @ _atfv-document-u @
    _atxr-zero? _atxr-assert
    _atfv-request-a @
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atxr-zero? _atxr-assert
    _atfv-readback-a @ _atfv-document-u @ 0 FILL
    _atfv-readback-a @ _atfv-document-u @
    _atfv-flow SFLOW.INGRESS-EVENT
    STREAMS-EVENT-PAYLOAD-COPY
    STREAMS-FLOW-S-OK _atxr-status
    _atfv-document-u @ = _atxr-assert
    _atfv-readback-a @ _atfv-document-u @
    _atfv-document-a @ _atfv-document-u @
    COMPARE 0= _atxr-assert
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-FEED@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atfv-check-feed ;

: _atfv-run-flow  ( -- )
    _ATFV-FLOW-REVISION _ATFV-NOW
    _atfv-flow _atfv-owner @
    AT-AUTHOR-FEED-CONNECTOR-PUBLISH
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atfv-flow SFLOW.STATE @
    STREAMS-FLOW-STATE-ACCEPTED = _atxr-assert
    _atfv-flow SFLOW.GENERATION @ DUP 0>
    _atxr-assert
    _atfv-generation !
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-EVENT@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    DUP STREAMS-EVENT-VALID? _atxr-assert
    SEVT.PAYLOAD-A @ 0= _atxr-assert

    _atfv-op _atfv-owner @
    AT-AUTHOR-FEED-CONNECTOR-XIO-WIPE
    _atfv-check-carrier-after-wipe

    _ATFV-NOW 1+ _atfv-flow STREAMS-FLOW-STEP
    STREAMS-FLOW-S-ACKNOWLEDGED _atxr-status
    _ATFV-NOW 2 + _atfv-flow STREAMS-FLOW-STEP
    STREAMS-FLOW-S-DELIVERED _atxr-status
    _atfv-transform-calls @ 1 = _atxr-assert
    _atfv-output-starts @ 1 = _atxr-assert
    _atfv-output-polls @ 0= _atxr-assert
    _atfv-output-cancels @ 0= _atxr-assert
    _atfv-output-cleanups @ 1 = _atxr-assert
    _atfv-output-u @ _atfv-document-u @ =
    _atxr-assert
    _atfv-generation @ _atfv-flow STREAMS-FLOW-RETIRE
    STREAMS-FLOW-S-OK _atxr-status
    _atfv-flow SFLOW.STATE @
    STREAMS-FLOW-STATE-IDLE = _atxr-assert ;

: _ATFV-QUALIFY  ( -- )
    _atfv-prepare-owner
    _atfv-drive
    _atfv-check-ready
    _atfv-run-flow
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-UNBIND
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atfv-owner @ AT-AUTHOR-FEED-CONNECTOR-EXCHANGE@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    AT-XRPC-EXCHANGE-STATE@
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    AT-XRPC-EXCHANGE-STATE-IDLE = _atxr-assert
    _atxr-stack ;

\ ---------------------------------------------------------------------
\ Cleanup
\ ---------------------------------------------------------------------

: _ATFV-FINISH  ( -- )
    _atfv-readback-a @ ?DUP IF
        _atfv-document-u @ 0 FILL
    THEN
    _atfv-expected-a @ ?DUP IF
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 0 FILL
    THEN
    _atfv-sent-a @ ?DUP IF
        _atfv-sent-cap @ 0 FILL
    THEN
    _atfv-response-a @ ?DUP IF
        _atfv-response-cap @ 0 FILL
    THEN
    _atfv-body-a @ ?DUP IF
        _atfv-document-u @ 0 FILL
    THEN
    _atfv-request-a @ ?DUP IF
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 0 FILL
    THEN
    _atfv-owner @ ?DUP IF
        AT-AUTHOR-FEED-CONNECTOR-SIZE 0 FILL
    THEN
    _atfv-document-a @ ?DUP IF
        _atfv-document-u @ 0 FILL
    THEN

    _atfv-readback-a _atfv-free
    _atfv-expected-a _atfv-free
    _atfv-sent-a _atfv-free
    _atfv-response-a _atfv-free
    _atfv-body-a _atfv-free
    _atfv-request-a _atfv-free
    _atfv-owner _atfv-free
    _atfv-document-a _atfv-free

    _atfv-op XIO-OP-SIZE 0 FILL
    _atfv-output STREAMS-CONNECTOR-SIZE 0 FILL
    _atfv-flow STREAMS-FLOW-SIZE 0 FILL
    _atfv-ingress STREAMS-PAYLOAD-SIZE 0 FILL
    _atfv-egress STREAMS-PAYLOAD-SIZE 0 FILL
    _atfv-ingress-segment STREAMS-PAYLOAD-SEGMENT-SIZE 0 FILL
    _atfv-egress-segment STREAMS-PAYLOAD-SEGMENT-SIZE 0 FILL
    _atfv-ingress-bytes STREAMS-RUNTIME-SEGMENT-BYTES 0 FILL
    _atfv-egress-bytes STREAMS-RUNTIME-SEGMENT-BYTES 0 FILL
    _atfv-flow-operation
    STREAMS-RUNTIME-COMPACT-OPERATION-BYTES 0 FILL
    _atfv-input-id RID-CLEAR
    _atfv-input-endpoint RID-CLEAR
    _atfv-output-id RID-CLEAR
    _atfv-output-endpoint RID-CLEAR
    _atfv-flow-id RID-CLEAR

    0 _atfv-document-u !
    0 _atfv-response-cap !
    0 _atfv-response-u !
    0 _atfv-response-pos !
    0 _atfv-response-end !
    0 _atfv-first-response-u !
    0 _atfv-sent-cap !
    0 _atfv-sent-u !
    0 _atfv-expected-u !
    0 _atfv-exchange !
    0 _atfv-generation !
    _ATXR-FINISH ;
