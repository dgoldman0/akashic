\ Focused authenticated AT Protocol ingress-to-egress SR4 qualification.
\
\ One real author-feed owner fetches a deterministic PDS page through the
\ authenticated XRPC stack.  Its decoded first item becomes the exact text
\ payload of a real Streams flow whose output is a production text-post
\ connector.  A second caller-owned post connector is live at the same time
\ and is driven by a fixture input so its transport can lose the response
\ without serializing or selecting the first graph.  The second graph is then
\ reused for a no-send failure.  All capacities and polling bounds below are
\ fixture-only caller choices, never production instance limits.

REQUIRE at-xrpc-auth-read-test.f

PROVIDED at-bidir-vertical

1024 CONSTANT _ATBV-RESPONSE-RESERVE
64 CONSTANT _ATBV-POLL-LIMIT
1 CONSTANT _ATBV-FLOW-REVISION
0x74657874 CONSTANT _ATBV-MEDIA-TEXT
1700000200123 CONSTANT _ATBV-EPOCH-A
1700000200456 CONSTANT _ATBV-EPOCH-B

2048 CONSTANT _ATBV-CREATE-BODY-CAPACITY
AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
_ATBV-CREATE-BODY-CAPACITY + CONSTANT _ATBV-XREQUEST-CAPACITY
1024 CONSTANT _ATBV-XBODY-CAPACITY
512 CONSTANT _ATBV-RESULT-CAPACITY
_ATBV-XREQUEST-CAPACITY 2 * CONSTANT _ATBV-CAPTURE-CAPACITY
2048 CONSTANT _ATBV-WIRE-RESPONSE-CAPACITY
2048 CONSTANT _ATBV-EXPECTED-CAPACITY

1 CONSTANT _ATBV-PEER-SCRIPTED
2 CONSTANT _ATBV-PEER-LOSS
3 CONSTANT _ATBV-PEER-NO-SEND

  0 CONSTANT _ATBVC-EPOCH
  8 CONSTANT _ATBVC-CALLS
 16 CONSTANT _ATBVC-SIZE

: ATBVC.EPOCH  ( clock-context -- field ) _ATBVC-EPOCH + ;
: ATBVC.CALLS  ( clock-context -- field ) _ATBVC-CALLS + ;

  0 CONSTANT _ATBVT-EXCHANGE
  8 CONSTANT _ATBVT-MODE
 16 CONSTANT _ATBVT-RESPONSE-A
 24 CONSTANT _ATBVT-RESPONSE-CAP
 32 CONSTANT _ATBVT-RESPONSE-U
 40 CONSTANT _ATBVT-RESPONSE-POS
 48 CONSTANT _ATBVT-RESPONSE-END
 56 CONSTANT _ATBVT-FIRST-RESPONSE-U
 64 CONSTANT _ATBVT-CAPTURE-A
 72 CONSTANT _ATBVT-CAPTURE-CAP
 80 CONSTANT _ATBVT-CAPTURE-U
 88 CONSTANT _ATBVT-REQUEST-START
 96 CONSTANT _ATBVT-REQUEST1-U
104 CONSTANT _ATBVT-REQUEST2-U
112 CONSTANT _ATBVT-OPEN-COUNT
120 CONSTANT _ATBVT-CLOSE-COUNT
128 CONSTANT _ATBVT-LOSS-RECV-COUNT
136 CONSTANT _ATBVT-IO-N
144 CONSTANT _ATBVT-SIZE

: ATBVT.EXCHANGE          ( context -- field ) _ATBVT-EXCHANGE + ;
: ATBVT.MODE              ( context -- field ) _ATBVT-MODE + ;
: ATBVT.RESPONSE-A        ( context -- field ) _ATBVT-RESPONSE-A + ;
: ATBVT.RESPONSE-CAP      ( context -- field ) _ATBVT-RESPONSE-CAP + ;
: ATBVT.RESPONSE-U        ( context -- field ) _ATBVT-RESPONSE-U + ;
: ATBVT.RESPONSE-POS      ( context -- field ) _ATBVT-RESPONSE-POS + ;
: ATBVT.RESPONSE-END      ( context -- field ) _ATBVT-RESPONSE-END + ;
: ATBVT.FIRST-RESPONSE-U  ( context -- field )
    _ATBVT-FIRST-RESPONSE-U + ;
: ATBVT.CAPTURE-A         ( context -- field ) _ATBVT-CAPTURE-A + ;
: ATBVT.CAPTURE-CAP       ( context -- field ) _ATBVT-CAPTURE-CAP + ;
: ATBVT.CAPTURE-U         ( context -- field ) _ATBVT-CAPTURE-U + ;
: ATBVT.REQUEST-START     ( context -- field ) _ATBVT-REQUEST-START + ;
: ATBVT.REQUEST1-U        ( context -- field ) _ATBVT-REQUEST1-U + ;
: ATBVT.REQUEST2-U        ( context -- field ) _ATBVT-REQUEST2-U + ;
: ATBVT.OPEN-COUNT        ( context -- field ) _ATBVT-OPEN-COUNT + ;
: ATBVT.CLOSE-COUNT       ( context -- field ) _ATBVT-CLOSE-COUNT + ;
: ATBVT.LOSS-RECV-COUNT   ( context -- field )
    _ATBVT-LOSS-RECV-COUNT + ;
: ATBVT.IO-N              ( context -- field ) _ATBVT-IO-N + ;

VARIABLE _atbv-document-a
VARIABLE _atbv-document-u
VARIABLE _atbv-load-fd
VARIABLE _atbv-load-depth

VARIABLE _atbv-feed-owner
VARIABLE _atbv-feed-request
VARIABLE _atbv-feed-body
VARIABLE _atbv-feed-response
VARIABLE _atbv-feed-response-cap
VARIABLE _atbv-feed-capture
VARIABLE _atbv-feed-expected

VARIABLE _atbv-exchange-a
VARIABLE _atbv-exchange-b
VARIABLE _atbv-xrequest-a
VARIABLE _atbv-xrequest-b
VARIABLE _atbv-xbody-a
VARIABLE _atbv-xbody-b
VARIABLE _atbv-create-owner-a
VARIABLE _atbv-create-owner-b
VARIABLE _atbv-create-body-a
VARIABLE _atbv-create-body-b
VARIABLE _atbv-create-work-a
VARIABLE _atbv-create-work-b
VARIABLE _atbv-result-a
VARIABLE _atbv-result-b
VARIABLE _atbv-result-bytes-a
VARIABLE _atbv-result-bytes-b
VARIABLE _atbv-post-owner-a
VARIABLE _atbv-post-owner-b
VARIABLE _atbv-response-a
VARIABLE _atbv-response-b
VARIABLE _atbv-capture-a
VARIABLE _atbv-capture-b
VARIABLE _atbv-expected-a
VARIABLE _atbv-expected-b
VARIABLE _atbv-expected-u-a
VARIABLE _atbv-expected-u-b
VARIABLE _atbv-feed-expected-u

VARIABLE _atbv-build-context
VARIABLE _atbv-build-status-a
VARIABLE _atbv-build-status-u
VARIABLE _atbv-build-nonce-a
VARIABLE _atbv-build-nonce-u
VARIABLE _atbv-build-body-a
VARIABLE _atbv-build-body-u
VARIABLE _atbv-expected-target
VARIABLE _atbv-expected-cap
VARIABLE _atbv-expected-u
VARIABLE _atbv-exp-text-a
VARIABLE _atbv-exp-text-u
VARIABLE _atbv-exp-tid-a
VARIABLE _atbv-exp-time-a
VARIABLE _atbv-request-a
VARIABLE _atbv-request-u
VARIABLE _atbv-check-expected-a
VARIABLE _atbv-check-expected-u
VARIABLE _atbv-scan-a
VARIABLE _atbv-scan-u

VARIABLE _atbv-cb-event
VARIABLE _atbv-cb-carrier
VARIABLE _atbv-cb-context
VARIABLE _atbv-cb-result
VARIABLE _atbv-cb-text-a
VARIABLE _atbv-cb-text-u

VARIABLE _atbv-feed-step
VARIABLE _atbv-feed-polls
VARIABLE _atbv-flow-a-status
VARIABLE _atbv-flow-b-status
VARIABLE _atbv-flow-a-now
VARIABLE _atbv-flow-b-now
VARIABLE _atbv-generation-a
VARIABLE _atbv-generation-b
VARIABLE _atbv-interleave-count
VARIABLE _atbv-progress-ok
VARIABLE _atbv-local-sequence

RID-SIZE XBUF _atbv-feed-id
RID-SIZE XBUF _atbv-feed-endpoint
RID-SIZE XBUF _atbv-post-id-a
RID-SIZE XBUF _atbv-post-endpoint-a
RID-SIZE XBUF _atbv-post-id-b
RID-SIZE XBUF _atbv-post-endpoint-b
RID-SIZE XBUF _atbv-local-id
RID-SIZE XBUF _atbv-local-endpoint
RID-SIZE XBUF _atbv-flow-id-a
RID-SIZE XBUF _atbv-flow-id-b

HTARGET-SIZE XBUF _atbv-create-target
TID-CLOCK-SIZE XBUF _atbv-tid-clock-a
TID-CLOCK-SIZE XBUF _atbv-tid-clock-b
_ATBVC-SIZE XBUF _atbv-clock-context-a
_ATBVC-SIZE XBUF _atbv-clock-context-b
_ATBVT-SIZE XBUF _atbv-feed-context
_ATBVT-SIZE XBUF _atbv-context-a
_ATBVT-SIZE XBUF _atbv-context-b

XIO-OP-SIZE XBUF _atbv-feed-op
STREAMS-CONNECTOR-SIZE XBUF _atbv-local-input
STREAMS-EVENT-SIZE XBUF _atbv-local-event

STREAMS-FLOW-SIZE XBUF _atbv-flow-a
STREAMS-FLOW-SIZE XBUF _atbv-flow-b
STREAMS-PAYLOAD-SIZE XBUF _atbv-ingress-a
STREAMS-PAYLOAD-SIZE XBUF _atbv-egress-a
STREAMS-PAYLOAD-SIZE XBUF _atbv-ingress-b
STREAMS-PAYLOAD-SIZE XBUF _atbv-egress-b
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _atbv-ingress-segment-a
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _atbv-egress-segment-a
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _atbv-ingress-segment-b
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _atbv-egress-segment-b
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _atbv-ingress-bytes-a
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _atbv-egress-bytes-a
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _atbv-ingress-bytes-b
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _atbv-egress-bytes-b
STREAMS-RUNTIME-COMPACT-OPERATION-BYTES XBUF _atbv-operation-a
STREAMS-RUNTIME-COMPACT-OPERATION-BYTES XBUF _atbv-operation-b

CREATE _atbv-receipt 512 ALLOT
VARIABLE _atbv-receipt-u
CREATE _atbv-crlf 13 C, 10 C,
CREATE _atbv-crlfcrlf 13 C, 10 C, 13 C, 10 C,

: _atbv-text-a$  ( -- address length )
    S" Injected fixtures make network behavior reviewable." ;

: _atbv-text-b$  ( -- address length )
    S" Second graph remains independent." ;

: _atbv-no-effect-text$  ( -- address length )
    S" This request must not reach the wire." ;

: _atbv-tid-a$  ( -- address length ) S" 3ke6km2rsns2l" ;
: _atbv-tid-b$  ( -- address length ) S" 3ke6km33xu22x" ;
: _atbv-time$  ( -- address length ) S" 2023-11-14T22:16:40Z" ;
: _atbv-cid-a$  ( -- address length )
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ;

: _atbv-uri-a$  ( -- address length )
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/3ke6km2rsns2l" ;

: _ATBV-LOAD  ( -- )
    DEPTH _atbv-load-depth !
    NAMEBUF 24 0 FILL
    S" atbv-feed.json" NAMEBUF SWAP CMOVE
    FIND-BY-NAME DUP -1 = ABORT" AT bidirectional fixture missing"
    OPEN-BY-SLOT DUP 0= ABORT" AT bidirectional fixture open failed"
    DUP _atbv-load-fd !
    FSIZE DUP 0= ABORT" AT bidirectional fixture empty"
    DUP _atbv-document-u !
    ALLOCATE ABORT" AT bidirectional fixture allocation failed"
    DUP _atbv-document-a !
    _atbv-document-u @ _atbv-load-fd @ FREAD
    _atbv-document-u @ <>
        ABORT" AT bidirectional fixture read failed"
    _atbv-load-fd @ FCLOSE
    0 _atbv-load-fd !
    _atbv-document-u @
    STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY >
        ABORT" AT bidirectional fixture exceeds compact carrier"
    DEPTH _atbv-load-depth @ <>
        ABORT" AT bidirectional fixture stack" ;

\ ---------------------------------------------------------------------
\ Deterministic clocks and owner-routed fake PDS transport
\ ---------------------------------------------------------------------

: _atbv-clock  ( clock-context -- epoch-ms status )
    1 OVER ATBVC.CALLS +!
    ATBVC.EPOCH @ 0 ;

: _atbv-peer-reset  ( mode context -- )
    >R
    R@ ATBVT.MODE !
    R@ ATBVT.RESPONSE-A @ R@ ATBVT.RESPONSE-CAP @ 0 FILL
    R@ ATBVT.CAPTURE-A @ R@ ATBVT.CAPTURE-CAP @ 0 FILL
    0 R@ ATBVT.RESPONSE-U !
    0 R@ ATBVT.RESPONSE-POS !
    0 R@ ATBVT.RESPONSE-END !
    0 R@ ATBVT.FIRST-RESPONSE-U !
    0 R@ ATBVT.CAPTURE-U !
    0 R@ ATBVT.REQUEST-START !
    0 R@ ATBVT.REQUEST1-U !
    0 R@ ATBVT.REQUEST2-U !
    0 R@ ATBVT.OPEN-COUNT !
    0 R@ ATBVT.CLOSE-COUNT !
    0 R@ ATBVT.LOSS-RECV-COUNT !
    R> DROP ;

: _atbv-open  ( context -- io-status )
    DUP ATBVT.MODE @ _ATBV-PEER-NO-SEND = IF
        DROP NIO-S-FAILED EXIT
    THEN
    DUP ATBVT.CAPTURE-U @ OVER ATBVT.REQUEST-START !
    1 OVER ATBVT.OPEN-COUNT +!
    DUP ATBVT.OPEN-COUNT @ 1 =
    OVER ATBVT.FIRST-RESPONSE-U @ 0> AND IF
        DUP ATBVT.FIRST-RESPONSE-U @
    ELSE
        DUP ATBVT.RESPONSE-U @
    THEN
    SWAP ATBVT.RESPONSE-END !
    NIO-S-OK ;

: _atbv-send  ( buffer length context -- count io-status )
    >R
    DUP R@ ATBVT.CAPTURE-U @ +
    R@ ATBVT.CAPTURE-CAP @ U> IF
        2DROP R> DROP 0 NIO-S-FAILED EXIT
    THEN
    OVER
    R@ ATBVT.CAPTURE-A @ R@ ATBVT.CAPTURE-U @ +
    2 PICK MOVE
    DUP R@ ATBVT.CAPTURE-U +!
    NIP R> DROP NIO-S-OK ;

: _atbv-recv  ( buffer capacity context -- count io-status )
    >R
    R@ ATBVT.MODE @ _ATBV-PEER-LOSS = IF
        1 R@ ATBVT.LOSS-RECV-COUNT +!
        2DROP R> DROP 0 NIO-S-FAILED EXIT
    THEN
    R@ ATBVT.RESPONSE-END @ R@ ATBVT.RESPONSE-POS @ -
    DUP 0= IF
        DROP 2DROP R> DROP 0 NIO-S-EOF EXIT
    THEN
    MIN DUP R@ ATBVT.IO-N !
    R@ ATBVT.RESPONSE-A @ R@ ATBVT.RESPONSE-POS @ +
    2 PICK R@ ATBVT.IO-N @ MOVE
    R@ ATBVT.IO-N @ R@ ATBVT.RESPONSE-POS +!
    NIP R> DROP NIO-S-OK ;

: _atbv-port-poll  ( context -- ) DROP ;
: _atbv-port-cancel  ( context -- ) DROP ;

: _atbv-close  ( context -- io-status )
    DUP ATBVT.CAPTURE-U @ OVER ATBVT.REQUEST-START @ -
    OVER ATBVT.CLOSE-COUNT @ 0= IF
        OVER ATBVT.REQUEST1-U !
    ELSE
        OVER ATBVT.CLOSE-COUNT @ 1 = IF
            OVER ATBVT.REQUEST2-U !
        ELSE
            DROP 0 _atxr-assert
        THEN
    THEN
    1 OVER ATBVT.CLOSE-COUNT +!
    DROP NIO-S-OK ;

: _atbv-install-port  ( exchange context -- )
    2DUP ATBVT.EXCHANGE !
    OVER AT-XRPC-EXCHANGE-PORT DUP NIO-INIT
    1 PICK OVER NIO.CONTEXT !
    ['] _atbv-open OVER NIO.OPEN-START-XT !
    ['] _atbv-open OVER NIO.OPEN-POLL-XT !
    ['] _atbv-send OVER NIO.SEND-XT !
    ['] _atbv-recv OVER NIO.RECV-XT !
    ['] _atbv-port-poll OVER NIO.POLL-XT !
    ['] _atbv-port-cancel OVER NIO.CANCEL-XT !
    ['] _atbv-close OVER NIO.CLOSE-START-XT !
    ['] _atbv-close SWAP NIO.CLOSE-POLL-XT !
    2DROP ;

\ ---------------------------------------------------------------------
\ Bounded response, receipt, and expected-create builders
\ ---------------------------------------------------------------------

: _atbv-response+  ( address length -- )
    DUP _atbv-build-context @ ATBVT.RESPONSE-U @ +
    _atbv-build-context @ ATBVT.RESPONSE-CAP @ U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atbv-build-context @ ATBVT.RESPONSE-A @
    _atbv-build-context @ ATBVT.RESPONSE-U @ + SWAP MOVE
    R> _atbv-build-context @ ATBVT.RESPONSE-U +! ;

: _atbv-response-crlf  ( -- ) _atbv-crlf 2 _atbv-response+ ;

: _atbv-append-http
  \ ( status-a status-u nonce-a nonce-u body-a body-u -- )
    _atbv-build-body-u ! _atbv-build-body-a !
    _atbv-build-nonce-u ! _atbv-build-nonce-a !
    _atbv-build-status-u ! _atbv-build-status-a !
    _atbv-build-status-a @ _atbv-build-status-u @ _atbv-response+
    _atbv-response-crlf
    S" Content-Type: application/json" _atbv-response+
    _atbv-response-crlf
    S" DPoP-Nonce: " _atbv-response+
    _atbv-build-nonce-a @ _atbv-build-nonce-u @ _atbv-response+
    _atbv-response-crlf
    S" Content-Length: " _atbv-response+
    _atbv-build-body-u @ NUM>STR _atbv-response+
    _atbv-response-crlf
    S" Connection: close" _atbv-response+
    _atbv-response-crlf _atbv-response-crlf
    _atbv-build-body-a @ _atbv-build-body-u @ _atbv-response+ ;

: _atbv-receipt+  ( address length -- )
    DUP _atbv-receipt-u @ + 512 U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atbv-receipt _atbv-receipt-u @ + SWAP MOVE
    R> _atbv-receipt-u +! ;

: _atbv-receipt-c!  ( character -- )
    _atbv-receipt-u @ 512 U< 0= IF
        DROP 0 _atxr-assert EXIT
    THEN
    _atbv-receipt _atbv-receipt-u @ + C!
    1 _atbv-receipt-u +! ;

: _atbv-receipt-key  ( address length -- )
    34 _atbv-receipt-c! _atbv-receipt+
    34 _atbv-receipt-c! 58 _atbv-receipt-c! ;

: _atbv-receipt-string  ( address length -- )
    34 _atbv-receipt-c! _atbv-receipt+
    34 _atbv-receipt-c! ;

: _atbv-build-receipt-a  ( -- )
    _atbv-receipt 512 0 FILL
    0 _atbv-receipt-u !
    123 _atbv-receipt-c!
    S" uri" _atbv-receipt-key
    _atbv-uri-a$ _atbv-receipt-string
    44 _atbv-receipt-c!
    S" cid" _atbv-receipt-key
    _atbv-cid-a$ _atbv-receipt-string
    44 _atbv-receipt-c!
    S" commit" _atbv-receipt-key
    123 _atbv-receipt-c!
    S" rev" _atbv-receipt-key
    S" x" _atbv-receipt-string
    125 _atbv-receipt-c!
    125 _atbv-receipt-c! ;

: _atbv-build-feed-responses  ( -- )
    _atbv-feed-context _atbv-build-context !
    _ATBV-PEER-SCRIPTED _atbv-feed-context _atbv-peer-reset
    _atbv-receipt 512 0 FILL
    0 _atbv-receipt-u !
    123 _atbv-receipt-c!
    S" error" _atbv-receipt-key
    S" use_dpop_nonce" _atbv-receipt-string
    125 _atbv-receipt-c!
    S" HTTP/1.1 400 Bad Request" S" pds-nonce-1"
    _atbv-receipt _atbv-receipt-u @ _atbv-append-http
    _atbv-feed-context ATBVT.RESPONSE-U @
        _atbv-feed-context ATBVT.FIRST-RESPONSE-U !
    S" HTTP/1.1 200 OK" S" pds-nonce-2"
    _atbv-document-a @ _atbv-document-u @ _atbv-append-http ;

: _atbv-build-post-response-a  ( -- )
    _atbv-context-a _atbv-build-context !
    _ATBV-PEER-SCRIPTED _atbv-context-a _atbv-peer-reset
    _atbv-build-receipt-a
    S" HTTP/1.1 200 OK" S" pds-post-a"
    _atbv-receipt _atbv-receipt-u @ _atbv-append-http ;

: _atbv-expected+  ( address length -- )
    DUP _atbv-expected-u @ + _atbv-expected-cap @ U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atbv-expected-target @ _atbv-expected-u @ + SWAP MOVE
    R> _atbv-expected-u +! ;

: _atbv-expected-c!  ( character -- )
    _atbv-expected-u @ _atbv-expected-cap @ U< 0= IF
        DROP 0 _atxr-assert EXIT
    THEN
    _atbv-expected-target @ _atbv-expected-u @ + C!
    1 _atbv-expected-u +! ;

: _atbv-expected-key  ( address length -- )
    34 _atbv-expected-c! _atbv-expected+
    34 _atbv-expected-c! 58 _atbv-expected-c! ;

: _atbv-expected-string  ( address length -- )
    34 _atbv-expected-c! _atbv-expected+
    34 _atbv-expected-c! ;

: _atbv-build-expected-body  ( -- )
    _atbv-expected-target @ _atbv-expected-cap @ 0 FILL
    0 _atbv-expected-u !
    123 _atbv-expected-c!
    S" repo" _atbv-expected-key
    S" did:plc:abcdefghijklmnopqrstuvwx" _atbv-expected-string
    44 _atbv-expected-c!
    S" collection" _atbv-expected-key
    S" app.bsky.feed.post" _atbv-expected-string
    44 _atbv-expected-c!
    S" rkey" _atbv-expected-key
    _atbv-exp-tid-a @ TID-LENGTH _atbv-expected-string
    44 _atbv-expected-c!
    S" record" _atbv-expected-key
    123 _atbv-expected-c!
    S" $type" _atbv-expected-key
    S" app.bsky.feed.post" _atbv-expected-string
    44 _atbv-expected-c!
    S" text" _atbv-expected-key
    _atbv-exp-text-a @ _atbv-exp-text-u @ _atbv-expected-string
    44 _atbv-expected-c!
    S" createdAt" _atbv-expected-key
    _atbv-exp-time-a @ DT-RFC3339-UTC-S-LENGTH
        _atbv-expected-string
    125 _atbv-expected-c!
    125 _atbv-expected-c! ;

: _atbv-build-expected-a  ( -- )
    _atbv-expected-a @ _atbv-expected-target !
    _ATBV-EXPECTED-CAPACITY _atbv-expected-cap !
    _atbv-text-a$ _atbv-exp-text-u ! _atbv-exp-text-a !
    _atbv-tid-a$ DROP _atbv-exp-tid-a !
    _atbv-time$ DROP _atbv-exp-time-a !
    _atbv-build-expected-body
    _atbv-expected-u @ _atbv-expected-u-a ! ;

: _atbv-build-expected-b  ( -- )
    _atbv-expected-b @ _atbv-expected-target !
    _ATBV-EXPECTED-CAPACITY _atbv-expected-cap !
    _atbv-text-b$ _atbv-exp-text-u ! _atbv-exp-text-a !
    _atbv-tid-b$ DROP _atbv-exp-tid-a !
    _atbv-time$ DROP _atbv-exp-time-a !
    _atbv-build-expected-body
    _atbv-expected-u @ _atbv-expected-u-b ! ;

: _atbv-build-feed-expected  ( -- )
    _atbv-feed-expected @ _atbv-expected-target !
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN _atbv-expected-cap !
    _atbv-expected-target @ _atbv-expected-cap @ 0 FILL
    0 _atbv-expected-u !
    S" GET /xrpc/app.bsky.feed.getAuthorFeed?actor=" _atbv-expected+
    S" did%3Aplc%3Aabcdefghijklmnopqrstuvwx" _atbv-expected+
    S" &limit=" _atbv-expected+
    BFM-MAX-ITEMS NUM>STR _atbv-expected+
    S" &filter=posts_with_replies&includePins=false HTTP/1.1"
        _atbv-expected+
    _atbv-crlf 2 _atbv-expected+
    S" Host: pds.example" _atbv-expected+ _atbv-crlf 2 _atbv-expected+
    S" Accept: application/json" _atbv-expected+
    _atbv-crlf 2 _atbv-expected+
    S" Authorization: DPoP access-vertical" _atbv-expected+
    _atbv-crlf 2 _atbv-expected+
    S" DPoP: deterministic-dpop-proof" _atbv-expected+
    _atbv-crlf 2 _atbv-expected+
    S" atproto-proxy: did:web:api.bsky.app#bsky_appview"
        _atbv-expected+
    _atbv-crlf 2 _atbv-expected+
    S" Accept-Encoding: identity" _atbv-expected+
    _atbv-crlf 2 _atbv-expected+
    S" User-Agent: akashic-atproto/1" _atbv-expected+
    _atbv-crlf 2 _atbv-expected+
    S" Connection: close" _atbv-expected+
    _atbv-crlf 2 _atbv-expected+ _atbv-crlf 2 _atbv-expected+
    _atbv-expected-u @ _atbv-feed-expected-u ! ;

\ ---------------------------------------------------------------------
\ Exact captured-request checks
\ ---------------------------------------------------------------------

: _atbv-http-body@
  \ ( request-a request-u -- body-a body-u found? )
    _atbv-scan-u ! _atbv-scan-a !
    BEGIN
        _atbv-scan-u @ 4 U< 0=
    WHILE
        _atbv-scan-a @ 4 _atbv-crlfcrlf 4 COMPARE 0= IF
            _atbv-scan-a @ 4 +
            _atbv-scan-u @ 4 - -1 EXIT
        THEN
        1 _atbv-scan-a +!
        -1 _atbv-scan-u +!
    REPEAT
    0 0 0 ;

: _atbv-request-contains?  ( needle-a needle-u -- flag )
    _atbv-request-a @ _atbv-request-u @ 2SWAP _atxr-contains? ;

: _atbv-check-create-request
  \ ( request-a request-u expected-a expected-u -- )
    _atbv-check-expected-u ! _atbv-check-expected-a !
    _atbv-request-u ! _atbv-request-a !
    S" POST /xrpc/com.atproto.repo.createRecord HTTP/1.1"
    _atbv-build-status-u ! _atbv-build-status-a !
    _atbv-request-u @ _atbv-build-status-u @ U< 0= _atxr-assert
    _atbv-request-a @ _atbv-build-status-u @
    _atbv-build-status-a @ _atbv-build-status-u @
        COMPARE 0= _atxr-assert
    S" Host: pds.example" _atbv-request-contains? _atxr-assert
    S" Content-Type: application/json"
        _atbv-request-contains? _atxr-assert
    S" Authorization: DPoP access-vertical"
        _atbv-request-contains? _atxr-assert
    S" DPoP: deterministic-dpop-proof"
        _atbv-request-contains? _atxr-assert
    _atbv-request-a @ _atbv-request-u @ _atbv-http-body@
    0= IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP _atbv-check-expected-u @ = _atxr-assert
    _atbv-check-expected-a @ _atbv-check-expected-u @
        COMPARE 0= _atxr-assert ;

: _atbv-check-feed-wire  ( -- )
    _atbv-feed-context ATBVT.OPEN-COUNT @ 2 = _atxr-assert
    _atbv-feed-context ATBVT.CLOSE-COUNT @ 2 = _atxr-assert
    _atbv-feed-context ATBVT.REQUEST1-U @
        _atbv-feed-expected-u @ = _atxr-assert
    _atbv-feed-context ATBVT.REQUEST2-U @
        _atbv-feed-expected-u @ = _atxr-assert
    _atbv-feed-context ATBVT.CAPTURE-A @
    _atbv-feed-context ATBVT.REQUEST1-U @
    _atbv-feed-expected @ _atbv-feed-expected-u @
        COMPARE 0= _atxr-assert
    _atbv-feed-context ATBVT.CAPTURE-A @
    _atbv-feed-context ATBVT.REQUEST1-U @ +
    _atbv-feed-context ATBVT.REQUEST2-U @
    _atbv-feed-expected @ _atbv-feed-expected-u @
        COMPARE 0= _atxr-assert ;

: _atbv-check-post-wire-a  ( -- )
    _atbv-context-a ATBVT.CAPTURE-U @ 0> _atxr-assert
    _atbv-context-a ATBVT.CAPTURE-A @
    _atbv-context-a ATBVT.CAPTURE-U @
    _atbv-expected-a @ _atbv-expected-u-a @
        _atbv-check-create-request ;

: _atbv-check-post-wire-b  ( -- )
    _atbv-context-b ATBVT.CAPTURE-U @ 0> _atxr-assert
    _atbv-context-b ATBVT.CAPTURE-A @
    _atbv-context-b ATBVT.CAPTURE-U @
    _atbv-expected-b @ _atbv-expected-u-b @
        _atbv-check-create-request ;

\ ---------------------------------------------------------------------
\ Production graph allocation and initialization
\ ---------------------------------------------------------------------

: _atbv-bind-exchange  ( exchange -- )
    >R
    _atxr-active-vault @
    _atoct-config
    _atopt-profile
    _atxr-active-session @
    R> AT-XRPC-EXCHANGE-BIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status ;

: _atbv-init-context
  \ ( exchange response-a response-cap capture-a capture-cap context -- )
    >R
    R@ _ATBVT-SIZE 0 FILL
    R@ ATBVT.CAPTURE-CAP !
    R@ ATBVT.CAPTURE-A !
    R@ ATBVT.RESPONSE-CAP !
    R@ ATBVT.RESPONSE-A !
    R@ ATBVT.EXCHANGE !
    R> DROP ;

: _atbv-allocate-feed  ( -- )
    AT-AUTHOR-FEED-CONNECTOR-SIZE _atbv-feed-owner _atxr-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
        _atbv-feed-request _atxr-allocate
    _atbv-document-u @ _atbv-feed-body _atxr-allocate
    _atbv-document-u @ _ATBV-RESPONSE-RESERVE +
        DUP _atbv-feed-response-cap !
        _atbv-feed-response _atxr-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 2 *
        _atbv-feed-capture _atxr-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
        _atbv-feed-expected _atxr-allocate ;

: _atbv-allocate-create-graphs  ( -- )
    AT-XRPC-EXCHANGE-SIZE _atbv-exchange-a _atxr-allocate
    AT-XRPC-EXCHANGE-SIZE _atbv-exchange-b _atxr-allocate
    _ATBV-XREQUEST-CAPACITY _atbv-xrequest-a _atxr-allocate
    _ATBV-XREQUEST-CAPACITY _atbv-xrequest-b _atxr-allocate
    _ATBV-XBODY-CAPACITY _atbv-xbody-a _atxr-allocate
    _ATBV-XBODY-CAPACITY _atbv-xbody-b _atxr-allocate
    AT-CREATE-RECORD-SIZE _atbv-create-owner-a _atxr-allocate
    AT-CREATE-RECORD-SIZE _atbv-create-owner-b _atxr-allocate
    _ATBV-CREATE-BODY-CAPACITY _atbv-create-body-a _atxr-allocate
    _ATBV-CREATE-BODY-CAPACITY _atbv-create-body-b _atxr-allocate
    AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        _atbv-create-work-a _atxr-allocate
    AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        _atbv-create-work-b _atxr-allocate
    AT-CREATE-RECORD-RESULT-SIZE _atbv-result-a _atxr-allocate
    AT-CREATE-RECORD-RESULT-SIZE _atbv-result-b _atxr-allocate
    _ATBV-RESULT-CAPACITY _atbv-result-bytes-a _atxr-allocate
    _ATBV-RESULT-CAPACITY _atbv-result-bytes-b _atxr-allocate
    AT-TEXT-POST-CONNECTOR-SIZE _atbv-post-owner-a _atxr-allocate
    AT-TEXT-POST-CONNECTOR-SIZE _atbv-post-owner-b _atxr-allocate
    _ATBV-WIRE-RESPONSE-CAPACITY _atbv-response-a _atxr-allocate
    _ATBV-WIRE-RESPONSE-CAPACITY _atbv-response-b _atxr-allocate
    _ATBV-CAPTURE-CAPACITY _atbv-capture-a _atxr-allocate
    _ATBV-CAPTURE-CAPACITY _atbv-capture-b _atxr-allocate
    _ATBV-EXPECTED-CAPACITY _atbv-expected-a _atxr-allocate
    _ATBV-EXPECTED-CAPACITY _atbv-expected-b _atxr-allocate ;

: _atbv-init-ids  ( -- )
    _atbv-feed-id RID-SIZE 0x61 FILL
    _atbv-feed-endpoint RID-SIZE 0x62 FILL
    _atbv-post-id-a RID-SIZE 0x63 FILL
    _atbv-post-endpoint-a RID-SIZE 0x64 FILL
    _atbv-post-id-b RID-SIZE 0x65 FILL
    _atbv-post-endpoint-b RID-SIZE 0x66 FILL
    _atbv-local-id RID-SIZE 0x67 FILL
    _atbv-local-endpoint RID-SIZE 0x68 FILL
    _atbv-flow-id-a RID-SIZE 0x69 FILL
    _atbv-flow-id-b RID-SIZE 0x6A FILL ;

: _atbv-init-feed-owner  ( -- )
    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-SIZE 0 FILL
    _atbv-feed-request @
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 0 FILL
    _atbv-feed-body @ _atbv-document-u @ 0 FILL
    _atbv-feed-response @ _atbv-feed-response-cap @ 0 FILL
    _atbv-feed-capture @
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 2 * 0 FILL

    _atbv-feed-id _atbv-feed-endpoint 1
    _atbv-feed-request @ AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
    _atbv-feed-body @ _atbv-document-u @
    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-INIT
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atxr-active-vault @
    _atoct-config
    _atopt-profile
    _atxr-active-session @
    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-BIND
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status

    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-EXCHANGE@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    DUP
    _atbv-feed-response @ _atbv-feed-response-cap @
    _atbv-feed-capture @
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 2 *
    _atbv-feed-context _atbv-init-context
    _atbv-feed-context _atbv-install-port

    _ATXR-IAT
    S" did:plc:abcdefghijklmnopqrstuvwx"
    BFM-MAX-ITEMS
    0 0
    AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-REPLIES
    0
    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-PREPARE
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atbv-build-feed-responses
    _atbv-build-feed-expected
    _atbv-feed-op XIO-OP-INIT ;

: _atbv-init-create-exchanges  ( -- )
    _atbv-exchange-a @ AT-XRPC-EXCHANGE-SIZE 0 FILL
    _atbv-exchange-b @ AT-XRPC-EXCHANGE-SIZE 0 FILL
    _atbv-xrequest-a @ _ATBV-XREQUEST-CAPACITY 0 FILL
    _atbv-xrequest-b @ _ATBV-XREQUEST-CAPACITY 0 FILL
    _atbv-xbody-a @ _ATBV-XBODY-CAPACITY 0 FILL
    _atbv-xbody-b @ _ATBV-XBODY-CAPACITY 0 FILL
    _atbv-xrequest-a @ _ATBV-XREQUEST-CAPACITY
    _atbv-xbody-a @ _ATBV-XBODY-CAPACITY
    _atbv-exchange-a @ AT-XRPC-EXCHANGE-INIT
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atbv-xrequest-b @ _ATBV-XREQUEST-CAPACITY
    _atbv-xbody-b @ _ATBV-XBODY-CAPACITY
    _atbv-exchange-b @ AT-XRPC-EXCHANGE-INIT
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atbv-exchange-a @ _atbv-bind-exchange
    _atbv-exchange-b @ _atbv-bind-exchange

    _atbv-exchange-a @
    _atbv-response-a @ _ATBV-WIRE-RESPONSE-CAPACITY
    _atbv-capture-a @ _ATBV-CAPTURE-CAPACITY
    _atbv-context-a _atbv-init-context
    _atbv-exchange-b @
    _atbv-response-b @ _ATBV-WIRE-RESPONSE-CAPACITY
    _atbv-capture-b @ _ATBV-CAPTURE-CAPACITY
    _atbv-context-b _atbv-init-context ;

: _atbv-init-create-owners  ( -- )
    _atbv-result-a @ AT-CREATE-RECORD-RESULT-SIZE 0 FILL
    _atbv-result-b @ AT-CREATE-RECORD-RESULT-SIZE 0 FILL
    _atbv-result-bytes-a @ _ATBV-RESULT-CAPACITY 0 FILL
    _atbv-result-bytes-b @ _ATBV-RESULT-CAPACITY 0 FILL
    _atbv-result-bytes-a @ _ATBV-RESULT-CAPACITY
    _atbv-result-a @ AT-CREATE-RECORD-RESULT-INIT
    AT-CREATE-RECORD-S-OK _atxr-status
    _atbv-result-bytes-b @ _ATBV-RESULT-CAPACITY
    _atbv-result-b @ AT-CREATE-RECORD-RESULT-INIT
    AT-CREATE-RECORD-S-OK _atxr-status

    _atbv-create-body-a @ _ATBV-CREATE-BODY-CAPACITY 0 FILL
    _atbv-create-body-b @ _ATBV-CREATE-BODY-CAPACITY 0 FILL
    _atbv-create-work-a @
        AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    _atbv-create-work-b @
        AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    _atbv-create-owner-a @ AT-CREATE-RECORD-SIZE 0 FILL
    _atbv-create-owner-b @ AT-CREATE-RECORD-SIZE 0 FILL

    _atbv-exchange-a @
    _atbv-create-body-a @ _ATBV-CREATE-BODY-CAPACITY
    _atbv-create-work-a @ _atbv-result-a @ _atbv-create-owner-a @
    AT-CREATE-RECORD-INIT AT-CREATE-RECORD-S-OK _atxr-status
    _atbv-exchange-b @
    _atbv-create-body-b @ _ATBV-CREATE-BODY-CAPACITY
    _atbv-create-work-b @ _atbv-result-b @ _atbv-create-owner-b @
    AT-CREATE-RECORD-INIT AT-CREATE-RECORD-S-OK _atxr-status ;

: _atbv-init-post-connectors  ( -- )
    _atbv-create-target HTARGET-INIT
    S" https://pds.example/xrpc/com.atproto.repo.createRecord"
    _atbv-create-target HTARGET-PARSE HTARGET-S-OK _atxr-status
    _atbv-create-target AT-CREATE-RECORD-TARGET? _atxr-assert
    17 _atbv-tid-clock-a TID-CLOCK-INIT TID-S-OK _atxr-status
    29 _atbv-tid-clock-b TID-CLOCK-INIT TID-S-OK _atxr-status
    _ATBV-EPOCH-A _atbv-clock-context-a ATBVC.EPOCH !
    0 _atbv-clock-context-a ATBVC.CALLS !
    _ATBV-EPOCH-B _atbv-clock-context-b ATBVC.EPOCH !
    0 _atbv-clock-context-b ATBVC.CALLS !

    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-SIZE 0 FILL
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-SIZE 0 FILL
    _atbv-post-id-a _atbv-post-endpoint-a 1
    _atbv-clock-context-a ['] _atbv-clock
    _atbv-tid-clock-a _atbv-create-target
    _atbv-create-owner-a @ _atbv-post-owner-a @
    AT-TEXT-POST-CONNECTOR-INIT
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _atbv-post-id-b _atbv-post-endpoint-b 1
    _atbv-clock-context-b ['] _atbv-clock
    _atbv-tid-clock-b _atbv-create-target
    _atbv-create-owner-b @ _atbv-post-owner-b @
    AT-TEXT-POST-CONNECTOR-INIT
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-VALID? _atxr-assert
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-VALID? _atxr-assert
    _atbv-post-owner-a @ _atbv-post-owner-b @ <> _atxr-assert
    _atbv-create-owner-a @ _atbv-create-owner-b @ <> _atxr-assert
    _atbv-tid-clock-a _atbv-tid-clock-b <> _atxr-assert

    _atbv-build-post-response-a
    _ATBV-PEER-LOSS _atbv-context-b _atbv-peer-reset
    _atbv-exchange-a @ _atbv-context-a _atbv-install-port
    _atbv-exchange-b @ _atbv-context-b _atbv-install-port
    _atbv-build-expected-a
    _atbv-build-expected-b ;

\ ---------------------------------------------------------------------
\ Two production Streams flows and their transforms
\ ---------------------------------------------------------------------

: _atbv-transform-result!
  ( completion output-u detail error result -- )
    >R
    R@ STRR.ERROR !
    R@ STRR.DETAIL !
    R@ STRR.OUTPUT-U !
    R> STRR.COMPLETION ! ;

: _atbv-feed-transform  ( ingress-event output-carrier context result -- )
    _atbv-cb-result !
    _atbv-cb-context !
    _atbv-cb-carrier !
    _atbv-cb-event !
    _atbv-cb-context @ AT-AUTHOR-FEED-CONNECTOR-FEED@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    0 SWAP BFM.FEED.ITEM
    DUP 0<> _atxr-assert
    BFM.ITEM.TEXT
    2DUP _atbv-cb-text-u ! _atbv-cb-text-a !
    _atbv-cb-carrier @ SPAY.GENERATION @
    _atbv-cb-carrier @ STREAMS-PAYLOAD-APPEND
    STREAMS-PAYLOAD-S-OK _atxr-status
    STREAMS-TRANSFORM-COMPLETION-OK
    _atbv-cb-text-u @ 0 0 _atbv-cb-result @
    _atbv-transform-result! ;

: _atbv-identity-transform
  ( ingress-event output-carrier context result -- )
    _atbv-cb-result !
    DROP
    _atbv-cb-carrier !
    _atbv-cb-event !
    _atbv-cb-carrier @ SPAY.GENERATION @
    _atbv-cb-carrier @ _atbv-cb-event @
    STREAMS-EVENT-APPEND-TO-CARRIER
    STREAMS-FLOW-S-OK _atxr-status
    STREAMS-TRANSFORM-COMPLETION-OK
    _atbv-cb-carrier @ SPAY.BYTE-U @ 0 0 _atbv-cb-result @
    _atbv-transform-result! ;

: _atbv-init-local-input  ( -- )
    _atbv-local-input STREAMS-CONNECTOR-INIT
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-local-id _atbv-local-input SCON.ID RID-COPY
    _atbv-local-endpoint _atbv-local-input SCON.ENDPOINT-ID RID-COPY
    1 _atbv-local-input SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT
        _atbv-local-input SCON.DIRECTION !
    STREAMS-PROTOCOL-ATPROTO _atbv-local-input SCON.PROTOCOL !
    _atbv-local-input STREAMS-CONNECTOR-SEAL
    STREAMS-FLOW-S-OK _atxr-status ;

: _atbv-init-payloads  ( -- )
    _atbv-ingress-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
    _atbv-ingress-segment-a STREAMS-PAYLOAD-SEGMENT-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status
    _atbv-egress-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
    _atbv-egress-segment-a STREAMS-PAYLOAD-SEGMENT-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status
    _atbv-ingress-bytes-b STREAMS-RUNTIME-SEGMENT-BYTES
    _atbv-ingress-segment-b STREAMS-PAYLOAD-SEGMENT-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status
    _atbv-egress-bytes-b STREAMS-RUNTIME-SEGMENT-BYTES
    _atbv-egress-segment-b STREAMS-PAYLOAD-SEGMENT-INIT
    STREAMS-PAYLOAD-S-OK _atxr-status

    _atbv-ingress-segment-a 1 STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-PAYLOAD-F-WIPE 0 0 _atbv-ingress-a
    STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _atxr-status
    _atbv-egress-segment-a 1 STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-PAYLOAD-F-WIPE 0 0 _atbv-egress-a
    STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _atxr-status
    _atbv-ingress-segment-b 1 STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-PAYLOAD-F-WIPE 0 0 _atbv-ingress-b
    STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _atxr-status
    _atbv-egress-segment-b 1 STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-PAYLOAD-F-WIPE 0 0 _atbv-egress-b
    STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _atxr-status ;

: _atbv-init-flow-a  ( -- )
    _atbv-flow-a STREAMS-FLOW-INIT STREAMS-FLOW-S-OK _atxr-status
    STREAMS-RUNTIME-PROFILE-COMPACT
    _atbv-ingress-a _atbv-egress-a
    _atbv-operation-a STREAMS-RUNTIME-COMPACT-OPERATION-BYTES
    _atbv-flow-a STREAMS-FLOW-WORKSPACE!
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-flow-id-a _atbv-flow-a SFLOW.ID RID-COPY
    _ATBV-FLOW-REVISION _atbv-flow-a SFLOW.REVISION !
    10000 _atbv-flow-a SFLOW.TIMEOUT-MS !
    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-CONNECTOR@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atbv-flow-a SFLOW.INPUT-CONNECTOR !
    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-CONNECTOR@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _atbv-flow-a SFLOW.OUTPUT-CONNECTOR !
    ['] _atbv-feed-transform _atbv-flow-a SFLOW.TRANSFORM-XT !
    _atbv-feed-owner @ _atbv-flow-a SFLOW.TRANSFORM-CONTEXT !
    _ATBV-MEDIA-TEXT _atbv-flow-a SFLOW.OUTPUT-MEDIA !
    _atbv-flow-a STREAMS-FLOW-SEAL
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-flow-a STREAMS-FLOW-VALID? _atxr-assert ;

: _atbv-init-flow-b  ( -- )
    _atbv-flow-b STREAMS-FLOW-INIT STREAMS-FLOW-S-OK _atxr-status
    STREAMS-RUNTIME-PROFILE-COMPACT
    _atbv-ingress-b _atbv-egress-b
    _atbv-operation-b STREAMS-RUNTIME-COMPACT-OPERATION-BYTES
    _atbv-flow-b STREAMS-FLOW-WORKSPACE!
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-flow-id-b _atbv-flow-b SFLOW.ID RID-COPY
    _ATBV-FLOW-REVISION _atbv-flow-b SFLOW.REVISION !
    10000 _atbv-flow-b SFLOW.TIMEOUT-MS !
    _atbv-local-input _atbv-flow-b SFLOW.INPUT-CONNECTOR !
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-CONNECTOR@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _atbv-flow-b SFLOW.OUTPUT-CONNECTOR !
    ['] _atbv-identity-transform _atbv-flow-b SFLOW.TRANSFORM-XT !
    0 _atbv-flow-b SFLOW.TRANSFORM-CONTEXT !
    _ATBV-MEDIA-TEXT _atbv-flow-b SFLOW.OUTPUT-MEDIA !
    _atbv-flow-b STREAMS-FLOW-SEAL
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-flow-b STREAMS-FLOW-VALID? _atxr-assert ;

VARIABLE _atbv-emit-a
VARIABLE _atbv-emit-u
VARIABLE _atbv-emit-now

: _atbv-emit-local  ( text-a text-u now-ms -- status )
    _atbv-emit-now ! _atbv-emit-u ! _atbv-emit-a !
    _atbv-local-event STREAMS-EVENT-INIT
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-emit-a @ _atbv-emit-u @
        _atbv-local-event SEVT.EVENT-ID SHA3-256-HASH
    _atbv-local-event SEVT.EVENT-ID
        _atbv-local-event SEVT.CORRELATION-ID RID-COPY
    _atbv-local-event SEVT.EVENT-ID
        _atbv-local-event SEVT.IDEMPOTENCY-ID RID-COPY
    _ATBV-MEDIA-TEXT _atbv-local-event SEVT.MEDIA !
    1 _atbv-local-sequence +!
    _atbv-local-sequence @ _atbv-local-event SEVT.SEQUENCE !
    _atbv-emit-now @ _atbv-local-event SEVT.RECEIVED-MS !
    _atbv-emit-a @ _atbv-emit-u @
        _atbv-local-event STREAMS-EVENT-BORROW
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-local-input _atbv-local-event _atbv-flow-b
        STREAMS-FLOW-SEAL-INGRESS
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-local-event _ATBV-FLOW-REVISION _atbv-emit-now @
        _atbv-flow-b STREAMS-FLOW-ADMIT ;

\ ---------------------------------------------------------------------
\ Runtime stages
\ ---------------------------------------------------------------------

: _ATBV-SETUP  ( -- )
    _atbv-allocate-feed
    _atbv-allocate-create-graphs
    _atbv-init-ids
    _atbv-init-feed-owner
    _atbv-init-create-exchanges
    _atbv-init-create-owners
    _atbv-init-post-connectors
    _atbv-init-local-input
    _atbv-init-payloads
    _atbv-init-flow-a
    _atbv-init-flow-b
    0 _atbv-local-sequence !
    0 _atbv-generation-a !
    0 _atbv-generation-b !
    _atxr-stack ;

: _atbv-drive-feed  ( -- )
    _atbv-feed-op _atbv-feed-owner @
    AT-AUTHOR-FEED-CONNECTOR-XIO-START
    XIO-STEP-PENDING = _atxr-assert
    0 _atbv-feed-polls !
    BEGIN
        _atbv-feed-op _atbv-feed-owner @
        AT-AUTHOR-FEED-CONNECTOR-XIO-POLL
        DUP _atbv-feed-step !
        XIO-STEP-PENDING =
    WHILE
        1 _atbv-feed-polls +!
        _atbv-feed-polls @ _ATBV-POLL-LIMIT U< 0= IF
            0 _atxr-assert EXIT
        THEN
    REPEAT
    _atbv-feed-step @ XIO-STEP-SUCCEEDED = _atxr-assert ;

: _atbv-check-feed  ( -- )
    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-FEED@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    DUP BFM.FEED.COUNT @ 2 = _atxr-assert
    0 SWAP BFM.FEED.ITEM
    DUP 0<> _atxr-assert
    BFM.ITEM.TEXT _atbv-text-a$ COMPARE 0= _atxr-assert
    _atbv-check-feed-wire ;

: _ATBV-INGRESS  ( -- )
    _atbv-drive-feed
    _atbv-check-feed
    _ATBV-FLOW-REVISION 100 _atbv-flow-a _atbv-feed-owner @
    AT-AUTHOR-FEED-CONNECTOR-PUBLISH
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atbv-flow-a SFLOW.STATE @
        STREAMS-FLOW-STATE-ACCEPTED = _atxr-assert
    _atbv-flow-a SFLOW.GENERATION @ DUP 0> _atxr-assert
    _atbv-generation-a !
    100 _atbv-flow-a-now !
    _atxr-stack ;

: _atbv-flow-a-terminal?  ( -- flag )
    _atbv-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-TERMINAL = ;

: _atbv-flow-b-terminal?  ( -- flag )
    _atbv-flow-b SFLOW.STATE @ STREAMS-FLOW-STATE-TERMINAL = ;

: _atbv-step-a  ( -- status )
    1 _atbv-flow-a-now +!
    _atbv-flow-a-now @ _atbv-flow-a STREAMS-FLOW-STEP
    DUP _atbv-flow-a-status ! ;

: _atbv-step-b  ( -- status )
    1 _atbv-flow-b-now +!
    _atbv-flow-b-now @ _atbv-flow-b STREAMS-FLOW-STEP
    DUP _atbv-flow-b-status ! ;

: _atbv-a-progress?  ( status -- flag )
    DUP STREAMS-FLOW-S-PENDING =
    SWAP STREAMS-FLOW-S-DELIVERED = OR ;

: _atbv-b-uncertain-progress?  ( status -- flag )
    DUP STREAMS-FLOW-S-PENDING =
    SWAP STREAMS-FLOW-S-INDETERMINATE = OR ;

: _atbv-b-no-effect-progress?  ( status -- flag )
    DUP STREAMS-FLOW-S-PENDING =
    SWAP STREAMS-FLOW-S-FAILED = OR ;

: _atbv-progress-assert  ( flag -- )
    DUP 0= IF 0 _atbv-progress-ok ! THEN
    _atxr-assert ;

: _atbv-check-created-a  ( -- )
    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    AT-CREATE-RECORD-OUTCOME-CREATED = _atxr-assert
    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-URI@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _atbv-uri-a$ COMPARE 0= _atxr-assert
    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-CID@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _atbv-cid-a$ COMPARE 0= _atxr-assert
    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _ATBV-EPOCH-A = _atxr-assert
    _atbv-post-owner-a @ AT-TEXT-POST-CONNECTOR-CLEANUP-ERROR@
    0= _atxr-assert ;

: _atbv-check-uncertain-b  ( -- )
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    AT-CREATE-RECORD-OUTCOME-UNCERTAIN = _atxr-assert
    _atbv-result-b @ AT-CREATE-RECORD-RESULT-WIRE@
    AT-CREATE-RECORD-S-OK _atxr-status
    AT-XRPC-EXCHANGE-WIRE-UNCERTAIN = _atxr-assert
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    _ATBV-EPOCH-B = _atxr-assert
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-CLEANUP-ERROR@
    0= _atxr-assert ;

: _ATBV-INTERLEAVE-ADMIT  ( -- )
    _atbv-text-b$ 200 _atbv-emit-local
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-flow-b SFLOW.GENERATION @ DUP 0> _atxr-assert
    _atbv-generation-b !
    200 _atbv-flow-b-now !
    _atxr-stack ;

: _ATBV-INTERLEAVE-START  ( -- )
    _atbv-step-a STREAMS-FLOW-S-ACKNOWLEDGED _atxr-status
    _atbv-step-b STREAMS-FLOW-S-ACKNOWLEDGED _atxr-status
    _atbv-step-a STREAMS-FLOW-S-PENDING _atxr-status
    _atbv-step-b STREAMS-FLOW-S-PENDING _atxr-status
    _atbv-flow-a SFLOW.STATE @
        STREAMS-FLOW-STATE-DELIVERING = _atxr-assert
    _atbv-flow-b SFLOW.STATE @
        STREAMS-FLOW-STATE-DELIVERING = _atxr-assert

    \ The ingress response may disappear while both post graphs are live.
    _atbv-feed-op _atbv-feed-owner @
        AT-AUTHOR-FEED-CONNECTOR-XIO-WIPE
    _atbv-feed-body @ _atbv-document-u @ _atxr-zero? _atxr-assert
    _atbv-feed-request @ AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
        _atxr-zero? _atxr-assert
    _atxr-stack ;

: _atbv-interleave-round  ( -- )
    _atbv-flow-a-terminal? 0= IF
        _atbv-step-a DUP _atbv-a-progress?
        _atbv-progress-assert DROP
    THEN
    _atbv-flow-b-terminal? 0= IF
        _atbv-step-b DUP _atbv-b-uncertain-progress?
        _atbv-progress-assert DROP
    THEN
    1 _atbv-interleave-count +! ;

: _ATBV-INTERLEAVE-DRIVE-FIRST  ( -- )
    0 _atbv-interleave-count !
    -1 _atbv-progress-ok !
    _atbv-flow-a-terminal? _atbv-flow-b-terminal? OR 0= _atxr-assert
    _atbv-interleave-round
    _atxr-stack ;

: _ATBV-INTERLEAVE-DRIVE  ( -- )
    BEGIN
        _atbv-flow-a-terminal? _atbv-flow-b-terminal? AND 0=
        _atbv-progress-ok @ AND
    WHILE
        _atbv-interleave-round
        _atbv-interleave-count @ _ATBV-POLL-LIMIT U< 0= IF
            0 _atxr-assert EXIT
        THEN
    REPEAT
    _atxr-stack ;

: _ATBV-INTERLEAVE-CHECK  ( -- )
    _atbv-flow-a-status @ STREAMS-FLOW-S-DELIVERED _atxr-status
    _atbv-flow-b-status @ STREAMS-FLOW-S-INDETERMINATE _atxr-status
    _atbv-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-DELIVERED = _atxr-assert
    _atbv-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _atxr-assert
    _atbv-flow-b SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _atxr-assert
    _atbv-flow-b SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-UNCERTAIN = _atxr-assert
    _atbv-clock-context-a ATBVC.CALLS @ 1 = _atxr-assert
    _atbv-clock-context-b ATBVC.CALLS @ 1 = _atxr-assert
    _atbv-context-b ATBVT.LOSS-RECV-COUNT @ 1 = _atxr-assert
    _atbv-check-post-wire-a
    _atbv-check-post-wire-b
    _atbv-check-created-a
    _atbv-check-uncertain-b
    _atxr-stack ;

: _atbv-drive-b-terminal  ( -- )
    0 _atbv-interleave-count !
    BEGIN
        _atbv-flow-b-terminal? 0= _atbv-progress-ok @ AND
    WHILE
        _atbv-step-b DUP _atbv-b-no-effect-progress?
        _atbv-progress-assert DROP
        1 _atbv-interleave-count +!
        _atbv-interleave-count @ _ATBV-POLL-LIMIT U< 0= IF
            0 _atxr-assert EXIT
        THEN
    REPEAT ;

: _ATBV-NO-EFFECT  ( -- )
    _atbv-generation-b @ _atbv-flow-b STREAMS-FLOW-RETIRE
    STREAMS-FLOW-S-OK _atxr-status
    _ATBV-PEER-NO-SEND _atbv-context-b _atbv-peer-reset
    _atbv-exchange-b @ _atbv-context-b _atbv-install-port
    10 _atbv-flow-b-now +!
    _atbv-no-effect-text$ _atbv-flow-b-now @ _atbv-emit-local
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-flow-b SFLOW.GENERATION @ _atbv-generation-b !
    _atbv-step-b STREAMS-FLOW-S-ACKNOWLEDGED _atxr-status
    -1 _atbv-progress-ok !
    _atbv-step-b DUP _atbv-b-no-effect-progress?
        _atbv-progress-assert DROP
    _atbv-drive-b-terminal
    _atbv-flow-b-status @ STREAMS-FLOW-S-FAILED _atxr-status
    _atbv-flow-b SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-BEFORE = _atxr-assert
    _atbv-flow-b SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-NOT-APPLIED = _atxr-assert
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    AT-TEXT-POST-CONNECTOR-S-OK _atxr-status
    AT-CREATE-RECORD-OUTCOME-NO-EFFECT = _atxr-assert
    _atbv-result-b @ AT-CREATE-RECORD-RESULT-WIRE@
    AT-CREATE-RECORD-S-OK _atxr-status
    AT-XRPC-EXCHANGE-WIRE-NONE = _atxr-assert
    _atbv-context-b ATBVT.CAPTURE-U @ 0= _atxr-assert
    _atbv-clock-context-b ATBVC.CALLS @ 2 = _atxr-assert
    _atbv-post-owner-b @ AT-TEXT-POST-CONNECTOR-CLEANUP-ERROR@
    0= _atxr-assert
    _atxr-stack ;

: _ATBV-RELEASE-FLOWS  ( -- )
    _atbv-generation-a @ _atbv-flow-a STREAMS-FLOW-RETIRE
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-generation-b @ _atbv-flow-b STREAMS-FLOW-RETIRE
    STREAMS-FLOW-S-OK _atxr-status
    _atbv-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE = _atxr-assert
    _atbv-flow-b SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE = _atxr-assert
    _atxr-stack ;

\ ---------------------------------------------------------------------
\ Dependency-ordered teardown and detached receipt check
\ ---------------------------------------------------------------------

: _atbv-zero-flow-storage  ( -- )
    _atbv-local-event STREAMS-EVENT-SIZE 0 FILL
    _atbv-local-input STREAMS-CONNECTOR-SIZE 0 FILL
    _atbv-flow-a STREAMS-FLOW-SIZE 0 FILL
    _atbv-flow-b STREAMS-FLOW-SIZE 0 FILL
    _atbv-ingress-a STREAMS-PAYLOAD-SIZE 0 FILL
    _atbv-egress-a STREAMS-PAYLOAD-SIZE 0 FILL
    _atbv-ingress-b STREAMS-PAYLOAD-SIZE 0 FILL
    _atbv-egress-b STREAMS-PAYLOAD-SIZE 0 FILL
    _atbv-ingress-segment-a STREAMS-PAYLOAD-SEGMENT-SIZE 0 FILL
    _atbv-egress-segment-a STREAMS-PAYLOAD-SEGMENT-SIZE 0 FILL
    _atbv-ingress-segment-b STREAMS-PAYLOAD-SEGMENT-SIZE 0 FILL
    _atbv-egress-segment-b STREAMS-PAYLOAD-SEGMENT-SIZE 0 FILL
    _atbv-ingress-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES 0 FILL
    _atbv-egress-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES 0 FILL
    _atbv-ingress-bytes-b STREAMS-RUNTIME-SEGMENT-BYTES 0 FILL
    _atbv-egress-bytes-b STREAMS-RUNTIME-SEGMENT-BYTES 0 FILL
    _atbv-operation-a STREAMS-RUNTIME-COMPACT-OPERATION-BYTES 0 FILL
    _atbv-operation-b STREAMS-RUNTIME-COMPACT-OPERATION-BYTES 0 FILL ;

: _atbv-release-feed  ( -- )
    _atbv-feed-owner @ AT-AUTHOR-FEED-CONNECTOR-UNBIND
    AT-AUTHOR-FEED-CONNECTOR-S-OK _atxr-status
    _atbv-feed-owner @ ?DUP IF
        AT-AUTHOR-FEED-CONNECTOR-SIZE 0 FILL
    THEN
    _atbv-feed-request @ ?DUP IF
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 0 FILL
    THEN
    _atbv-feed-body @ ?DUP IF _atbv-document-u @ 0 FILL THEN
    _atbv-feed-response @ ?DUP IF _atbv-feed-response-cap @ 0 FILL THEN
    _atbv-feed-capture @ ?DUP IF
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 2 * 0 FILL
    THEN
    _atbv-feed-expected @ ?DUP IF
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 0 FILL
    THEN
    _atbv-feed-expected _atxr-free
    _atbv-feed-capture _atxr-free
    _atbv-feed-response _atxr-free
    _atbv-feed-body _atxr-free
    _atbv-feed-request _atxr-free
    _atbv-feed-owner _atxr-free ;

: _atbv-release-post-owners  ( -- )
    _atbv-post-owner-a @ ?DUP IF
        AT-TEXT-POST-CONNECTOR-SIZE 0 FILL
    THEN
    _atbv-post-owner-b @ ?DUP IF
        AT-TEXT-POST-CONNECTOR-SIZE 0 FILL
    THEN
    _atbv-post-owner-b _atxr-free
    _atbv-post-owner-a _atxr-free
    _atbv-create-target HTARGET-SIZE 0 FILL
    _atbv-tid-clock-a TID-CLOCK-SIZE 0 FILL
    _atbv-tid-clock-b TID-CLOCK-SIZE 0 FILL
    _atbv-clock-context-a _ATBVC-SIZE 0 FILL
    _atbv-clock-context-b _ATBVC-SIZE 0 FILL ;

: _atbv-release-create-graphs  ( -- )
    _atbv-exchange-a @ AT-XRPC-EXCHANGE-UNBIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atbv-exchange-b @ AT-XRPC-EXCHANGE-UNBIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atbv-create-owner-a @ ?DUP IF AT-CREATE-RECORD-SIZE 0 FILL THEN
    _atbv-create-owner-b @ ?DUP IF AT-CREATE-RECORD-SIZE 0 FILL THEN
    _atbv-exchange-a @ ?DUP IF AT-XRPC-EXCHANGE-SIZE 0 FILL THEN
    _atbv-exchange-b @ ?DUP IF AT-XRPC-EXCHANGE-SIZE 0 FILL THEN
    _atbv-xrequest-a @ ?DUP IF _ATBV-XREQUEST-CAPACITY 0 FILL THEN
    _atbv-xrequest-b @ ?DUP IF _ATBV-XREQUEST-CAPACITY 0 FILL THEN
    _atbv-xbody-a @ ?DUP IF _ATBV-XBODY-CAPACITY 0 FILL THEN
    _atbv-xbody-b @ ?DUP IF _ATBV-XBODY-CAPACITY 0 FILL THEN
    _atbv-create-body-a @ ?DUP IF
        _ATBV-CREATE-BODY-CAPACITY 0 FILL
    THEN
    _atbv-create-body-b @ ?DUP IF
        _ATBV-CREATE-BODY-CAPACITY 0 FILL
    THEN
    _atbv-create-work-a @ ?DUP IF
        AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    THEN
    _atbv-create-work-b @ ?DUP IF
        AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    THEN
    _atbv-result-b @ ?DUP IF AT-CREATE-RECORD-RESULT-SIZE 0 FILL THEN
    _atbv-result-bytes-b @ ?DUP IF _ATBV-RESULT-CAPACITY 0 FILL THEN
    _atbv-response-a @ ?DUP IF _ATBV-WIRE-RESPONSE-CAPACITY 0 FILL THEN
    _atbv-response-b @ ?DUP IF _ATBV-WIRE-RESPONSE-CAPACITY 0 FILL THEN
    _atbv-capture-a @ ?DUP IF _ATBV-CAPTURE-CAPACITY 0 FILL THEN
    _atbv-capture-b @ ?DUP IF _ATBV-CAPTURE-CAPACITY 0 FILL THEN
    _atbv-expected-a @ ?DUP IF _ATBV-EXPECTED-CAPACITY 0 FILL THEN
    _atbv-expected-b @ ?DUP IF _ATBV-EXPECTED-CAPACITY 0 FILL THEN

    _atbv-expected-b _atxr-free
    _atbv-expected-a _atxr-free
    _atbv-capture-b _atxr-free
    _atbv-capture-a _atxr-free
    _atbv-response-b _atxr-free
    _atbv-response-a _atxr-free
    _atbv-result-bytes-b _atxr-free
    _atbv-result-b _atxr-free
    _atbv-create-work-b _atxr-free
    _atbv-create-work-a _atxr-free
    _atbv-create-body-b _atxr-free
    _atbv-create-body-a _atxr-free
    _atbv-create-owner-b _atxr-free
    _atbv-create-owner-a _atxr-free
    _atbv-xbody-b _atxr-free
    _atbv-xbody-a _atxr-free
    _atbv-xrequest-b _atxr-free
    _atbv-xrequest-a _atxr-free
    _atbv-exchange-b _atxr-free
    _atbv-exchange-a _atxr-free
    _atbv-feed-context _ATBVT-SIZE 0 FILL
    _atbv-context-a _ATBVT-SIZE 0 FILL
    _atbv-context-b _ATBVT-SIZE 0 FILL ;

: _ATBV-RELEASE-GRAPHS  ( -- )
    \ Flow cleanup releases connector claims before retained dependencies.
    _atbv-zero-flow-storage
    _atbv-release-feed
    _atbv-release-post-owners
    _atbv-release-create-graphs
    _atxr-stack ;

: _atbv-check-detached-result-a  ( -- )
    _atbv-result-a @ AT-CREATE-RECORD-RESULT-VALID? _atxr-assert
    _atbv-result-a @ AT-CREATE-RECORD-RESULT-OUTCOME@
    AT-CREATE-RECORD-S-OK _atxr-status
    AT-CREATE-RECORD-OUTCOME-CREATED = _atxr-assert
    _atbv-result-a @ AT-CREATE-RECORD-RESULT-URI@
    AT-CREATE-RECORD-S-OK _atxr-status
    _atbv-uri-a$ COMPARE 0= _atxr-assert
    _atbv-result-a @ AT-CREATE-RECORD-RESULT-CID@
    AT-CREATE-RECORD-S-OK _atxr-status
    _atbv-cid-a$ COMPARE 0= _atxr-assert ;

: _atbv-clear-static  ( -- )
    _atbv-feed-op XIO-OP-SIZE 0 FILL
    _atbv-feed-id RID-CLEAR
    _atbv-feed-endpoint RID-CLEAR
    _atbv-post-id-a RID-CLEAR
    _atbv-post-endpoint-a RID-CLEAR
    _atbv-post-id-b RID-CLEAR
    _atbv-post-endpoint-b RID-CLEAR
    _atbv-local-id RID-CLEAR
    _atbv-local-endpoint RID-CLEAR
    _atbv-flow-id-a RID-CLEAR
    _atbv-flow-id-b RID-CLEAR
    _atbv-receipt 512 0 FILL
    0 _atbv-receipt-u ! ;

: _ATBV-FINISH  ( -- )
    _ATXR-FINISH
    \ The create receipt remains caller-owned after every dependency ends.
    _atbv-check-detached-result-a
    _atbv-result-a @ AT-CREATE-RECORD-RESULT-SIZE 0 FILL
    _atbv-result-bytes-a @ _ATBV-RESULT-CAPACITY 0 FILL
    _atbv-result-a _atxr-free
    _atbv-result-bytes-a _atxr-free
    _atbv-document-a @ ?DUP IF _atbv-document-u @ 0 FILL THEN
    _atbv-document-a _atxr-free
    0 _atbv-document-u !
    _atbv-clear-static
    _atxr-stack
    _atxr-fails @ IF
        ." AT BIDIRECTIONAL FAIL checks/fails "
        _atxr-checks @ . _atxr-fails @ . CR
    ELSE
        ." AT BIDIRECTIONAL VERTICAL PASS checks "
        _atxr-checks @ . CR
    THEN
    TX-FLUSH ;
