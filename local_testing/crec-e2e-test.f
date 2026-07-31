\ End-to-end qualification for the authenticated createRecord owner.
\
\ This fixture reuses the durable authenticated-XRPC setup and deterministic
\ crypto seam.  Each live exchange receives a distinct caller-allocated test
\ transport context through NIO.CONTEXT; callback state is never selected by
\ a singleton owner or slot index.  Every arena capacity and polling bound is
\ fixture-only and selected by this caller, not a production instance count.

REQUIRE at-xrpc-auth-read-test.f

PROVIDED at-create-record-e2e-test

512 CONSTANT _ATCRT-VECTOR-CAPACITY
2048 CONSTANT _ATCRT-WIRE-RESPONSE-CAPACITY
32 CONSTANT _ATCRT-POLL-LIMIT

HTARGET-SIZE 512 + CONSTANT _ATCRT-CREATE-BODY-A-CAPACITY
HTARGET-SIZE 1024 + CONSTANT _ATCRT-CREATE-BODY-B-CAPACITY
AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
_ATCRT-CREATE-BODY-A-CAPACITY +
    CONSTANT _ATCRT-XREQUEST-A-CAPACITY
AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
_ATCRT-CREATE-BODY-B-CAPACITY +
    CONSTANT _ATCRT-XREQUEST-B-CAPACITY
512 CONSTANT _ATCRT-XBODY-A-CAPACITY
768 CONSTANT _ATCRT-XBODY-B-CAPACITY
256 CONSTANT _ATCRT-RESULT-A-CAPACITY
320 CONSTANT _ATCRT-RESULT-B-CAPACITY
64 AT-CID-TEXT-LENGTH + 1-
    CONSTANT _ATCRT-RESULT-SMALL-CAPACITY
_ATCRT-XREQUEST-A-CAPACITY 2 *
    CONSTANT _ATCRT-CAPTURE-A-CAPACITY
_ATCRT-XREQUEST-B-CAPACITY 2 *
    CONSTANT _ATCRT-CAPTURE-B-CAPACITY

  0 CONSTANT _ATCT-EXCHANGE
  8 CONSTANT _ATCT-RESPONSE-A
 16 CONSTANT _ATCT-RESPONSE-CAP
 24 CONSTANT _ATCT-RESPONSE-U
 32 CONSTANT _ATCT-RESPONSE-POS
 40 CONSTANT _ATCT-RESPONSE-END
 48 CONSTANT _ATCT-FIRST-RESPONSE-U
 56 CONSTANT _ATCT-CAPTURE-A
 64 CONSTANT _ATCT-CAPTURE-CAP
 72 CONSTANT _ATCT-CAPTURE-U
 80 CONSTANT _ATCT-REQUEST-START
 88 CONSTANT _ATCT-REQUEST1-U
 96 CONSTANT _ATCT-REQUEST2-U
104 CONSTANT _ATCT-OPEN-COUNT
112 CONSTANT _ATCT-CLOSE-COUNT
120 CONSTANT _ATCT-LOSS-RECV-COUNT
128 CONSTANT _ATCT-SEND-WIRE-OK
136 CONSTANT _ATCT-FIRST-NONCE-OK
144 CONSTANT _ATCT-SECOND-NONCE-OK
152 CONSTANT _ATCT-IO-N
160 CONSTANT _ATCRT-TRANSPORT-CONTEXT-SIZE

: ATCT.EXCHANGE          ( context -- field ) _ATCT-EXCHANGE + ;
: ATCT.RESPONSE-A        ( context -- field ) _ATCT-RESPONSE-A + ;
: ATCT.RESPONSE-CAP      ( context -- field ) _ATCT-RESPONSE-CAP + ;
: ATCT.RESPONSE-U        ( context -- field ) _ATCT-RESPONSE-U + ;
: ATCT.RESPONSE-POS      ( context -- field ) _ATCT-RESPONSE-POS + ;
: ATCT.RESPONSE-END      ( context -- field ) _ATCT-RESPONSE-END + ;
: ATCT.FIRST-RESPONSE-U  ( context -- field )
    _ATCT-FIRST-RESPONSE-U + ;
: ATCT.CAPTURE-A         ( context -- field ) _ATCT-CAPTURE-A + ;
: ATCT.CAPTURE-CAP       ( context -- field ) _ATCT-CAPTURE-CAP + ;
: ATCT.CAPTURE-U         ( context -- field ) _ATCT-CAPTURE-U + ;
: ATCT.REQUEST-START     ( context -- field ) _ATCT-REQUEST-START + ;
: ATCT.REQUEST1-U        ( context -- field ) _ATCT-REQUEST1-U + ;
: ATCT.REQUEST2-U        ( context -- field ) _ATCT-REQUEST2-U + ;
: ATCT.OPEN-COUNT        ( context -- field ) _ATCT-OPEN-COUNT + ;
: ATCT.CLOSE-COUNT       ( context -- field ) _ATCT-CLOSE-COUNT + ;
: ATCT.LOSS-RECV-COUNT   ( context -- field )
    _ATCT-LOSS-RECV-COUNT + ;
: ATCT.SEND-WIRE-OK      ( context -- field ) _ATCT-SEND-WIRE-OK + ;
: ATCT.FIRST-NONCE-OK    ( context -- field )
    _ATCT-FIRST-NONCE-OK + ;
: ATCT.SECOND-NONCE-OK   ( context -- field )
    _ATCT-SECOND-NONCE-OK + ;
: ATCT.IO-N              ( context -- field ) _ATCT-IO-N + ;

VARIABLE _atcrt-exchange-a
VARIABLE _atcrt-exchange-b
VARIABLE _atcrt-xrequest-a
VARIABLE _atcrt-xrequest-b
VARIABLE _atcrt-xbody-a
VARIABLE _atcrt-xbody-b
VARIABLE _atcrt-owner-a
VARIABLE _atcrt-owner-b
VARIABLE _atcrt-create-body-a
VARIABLE _atcrt-create-body-b
VARIABLE _atcrt-work-a
VARIABLE _atcrt-work-b
VARIABLE _atcrt-result-a
VARIABLE _atcrt-result-b
VARIABLE _atcrt-result-bytes-a
VARIABLE _atcrt-result-bytes-b
VARIABLE _atcrt-result-bytes-small
VARIABLE _atcrt-context-a
VARIABLE _atcrt-context-b
VARIABLE _atcrt-response-a
VARIABLE _atcrt-response-b
VARIABLE _atcrt-capture-a
VARIABLE _atcrt-capture-b

VARIABLE _atcrt-record-u
VARIABLE _atcrt-collection-u
VARIABLE _atcrt-rkey-u
VARIABLE _atcrt-expected-body-u
VARIABLE _atcrt-receipt-u
VARIABLE _atcrt-header-u
VARIABLE _atcrt-script-context
VARIABLE _atcrt-observe-context
VARIABLE _atcrt-active-owner
VARIABLE _atcrt-active-op
VARIABLE _atcrt-step
VARIABLE _atcrt-polls
VARIABLE _atcrt-request-a
VARIABLE _atcrt-request-u
VARIABLE _atcrt-scan-a
VARIABLE _atcrt-scan-u
VARIABLE _atcrt-http-status-a
VARIABLE _atcrt-http-status-u
VARIABLE _atcrt-http-nonce-a
VARIABLE _atcrt-http-nonce-u
VARIABLE _atcrt-http-body-a
VARIABLE _atcrt-http-body-u

CREATE _atcrt-target-store HTARGET-SIZE 7 + ALLOT
CREATE _atcrt-op-a-store XIO-OP-SIZE 7 + ALLOT
CREATE _atcrt-op-b-store XIO-OP-SIZE 7 + ALLOT
CREATE _atcrt-collection NSID-LENGTH-MAX ALLOT
CREATE _atcrt-rkey AT-RKEY-LENGTH-MAX ALLOT
CREATE _atcrt-record _ATCRT-VECTOR-CAPACITY ALLOT
CREATE _atcrt-expected-body _ATCRT-VECTOR-CAPACITY ALLOT
CREATE _atcrt-receipt _ATCRT-VECTOR-CAPACITY ALLOT
CREATE _atcrt-header 64 ALLOT
CREATE _atcrt-crlfcrlf 13 C, 10 C, 13 C, 10 C,

: _atcrt-target  ( -- target )
    _atcrt-target-store 7 + -8 AND ;

: _atcrt-op-a  ( -- operation )
    _atcrt-op-a-store 7 + -8 AND ;

: _atcrt-op-b  ( -- operation )
    _atcrt-op-b-store 7 + -8 AND ;

: _atcrt-wire-response  ( -- address )
    _atcrt-script-context @ ATCT.RESPONSE-A @ ;

: _atcrt-response-u  ( -- field )
    _atcrt-script-context @ ATCT.RESPONSE-U ;

: _atcrt-response-pos  ( -- field )
    _atcrt-script-context @ ATCT.RESPONSE-POS ;

: _atcrt-first-response-u  ( -- field )
    _atcrt-script-context @ ATCT.FIRST-RESPONSE-U ;

: _atcrt-capture  ( -- field )
    _atcrt-observe-context @ ATCT.CAPTURE-A ;

: _atcrt-capture-u  ( -- field )
    _atcrt-observe-context @ ATCT.CAPTURE-U ;

: _atcrt-request1-u  ( -- field )
    _atcrt-observe-context @ ATCT.REQUEST1-U ;

: _atcrt-request2-u  ( -- field )
    _atcrt-observe-context @ ATCT.REQUEST2-U ;

: _atcrt-open-count  ( -- field )
    _atcrt-observe-context @ ATCT.OPEN-COUNT ;

: _atcrt-close-count  ( -- field )
    _atcrt-observe-context @ ATCT.CLOSE-COUNT ;

: _atcrt-loss-recv-count  ( -- field )
    _atcrt-observe-context @ ATCT.LOSS-RECV-COUNT ;

: _atcrt-send-wire-ok  ( -- field )
    _atcrt-observe-context @ ATCT.SEND-WIRE-OK ;

: _atcrt-first-nonce-ok  ( -- field )
    _atcrt-observe-context @ ATCT.FIRST-NONCE-OK ;

: _atcrt-second-nonce-ok  ( -- field )
    _atcrt-observe-context @ ATCT.SECOND-NONCE-OK ;

\ =====================================================================
\  Independent request and receipt vectors
\ =====================================================================

: _atcrt-record+  ( address length -- )
    DUP _atcrt-record-u @ + _ATCRT-VECTOR-CAPACITY U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atcrt-record _atcrt-record-u @ + SWAP CMOVE
    R> _atcrt-record-u +! ;

: _atcrt-record-c!  ( byte -- )
    _atcrt-record-u @ _ATCRT-VECTOR-CAPACITY U< 0= IF
        DROP 0 _atxr-assert EXIT
    THEN
    _atcrt-record _atcrt-record-u @ + C!
    1 _atcrt-record-u +! ;

: _atcrt-expected+  ( address length -- )
    DUP _atcrt-expected-body-u @ + _ATCRT-VECTOR-CAPACITY U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atcrt-expected-body _atcrt-expected-body-u @ + SWAP CMOVE
    R> _atcrt-expected-body-u +! ;

: _atcrt-expected-c!  ( byte -- )
    _atcrt-expected-body-u @ _ATCRT-VECTOR-CAPACITY U< 0= IF
        DROP 0 _atxr-assert EXIT
    THEN
    _atcrt-expected-body _atcrt-expected-body-u @ + C!
    1 _atcrt-expected-body-u +! ;

: _atcrt-receipt+  ( address length -- )
    DUP _atcrt-receipt-u @ + _ATCRT-VECTOR-CAPACITY U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atcrt-receipt _atcrt-receipt-u @ + SWAP CMOVE
    R> _atcrt-receipt-u +! ;

: _atcrt-receipt-c!  ( byte -- )
    _atcrt-receipt-u @ _ATCRT-VECTOR-CAPACITY U< 0= IF
        DROP 0 _atxr-assert EXIT
    THEN
    _atcrt-receipt _atcrt-receipt-u @ + C!
    1 _atcrt-receipt-u +! ;

: _atcrt-receipt-key  ( address length -- )
    34 _atcrt-receipt-c!
    _atcrt-receipt+
    34 _atcrt-receipt-c!
    58 _atcrt-receipt-c! ;

: _atcrt-receipt-string  ( address length -- )
    34 _atcrt-receipt-c!
    _atcrt-receipt+
    34 _atcrt-receipt-c! ;

: _atcrt-header+  ( address length -- )
    DUP _atcrt-header-u @ + 64 U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atcrt-header _atcrt-header-u @ + SWAP CMOVE
    R> _atcrt-header-u +! ;

: _atcrt-expected-uri$  ( -- address length )
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/Key:One" ;

: _atcrt-dag-cid$  ( -- address length )
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ;

: _atcrt-build-inputs  ( -- )
    _atcrt-collection NSID-LENGTH-MAX 0 FILL
    S" app.bsky.feed.post"
    DUP _atcrt-collection-u !
    _atcrt-collection SWAP CMOVE
    _atcrt-rkey AT-RKEY-LENGTH-MAX 0 FILL
    S" Key:One"
    DUP _atcrt-rkey-u !
    _atcrt-rkey SWAP CMOVE

    _atcrt-record _ATCRT-VECTOR-CAPACITY 0 FILL
    0 _atcrt-record-u !
    123 _atcrt-record-c!
    34 _atcrt-record-c! S" $type" _atcrt-record+
    34 _atcrt-record-c! 58 _atcrt-record-c!
    34 _atcrt-record-c! S" app.bsky.feed.post" _atcrt-record+
    34 _atcrt-record-c! 44 _atcrt-record-c!
    34 _atcrt-record-c! S" text" _atcrt-record+
    34 _atcrt-record-c! 58 _atcrt-record-c!
    34 _atcrt-record-c! S" hello" _atcrt-record+
    34 _atcrt-record-c! 125 _atcrt-record-c! ;

: _atcrt-build-target  ( -- )
    _atcrt-target HTARGET-SIZE 0 FILL
    _atcrt-target HTARGET-INIT
    S" https://pds.example/xrpc/com.atproto.repo.createRecord"
    _atcrt-target HTARGET-PARSE
    HTARGET-S-OK _atxr-status
    _atcrt-target HTARGET-VALID? _atxr-assert ;

: _atcrt-build-expected-body  ( -- )
    _atcrt-expected-body _ATCRT-VECTOR-CAPACITY 0 FILL
    0 _atcrt-expected-body-u !
    123 _atcrt-expected-c!
    34 _atcrt-expected-c! S" repo" _atcrt-expected+
    34 _atcrt-expected-c! 58 _atcrt-expected-c!
    34 _atcrt-expected-c!
    S" did:plc:abcdefghijklmnopqrstuvwx" _atcrt-expected+
    34 _atcrt-expected-c! 44 _atcrt-expected-c!
    34 _atcrt-expected-c! S" collection" _atcrt-expected+
    34 _atcrt-expected-c! 58 _atcrt-expected-c!
    34 _atcrt-expected-c!
    S" app.bsky.feed.post" _atcrt-expected+
    34 _atcrt-expected-c! 44 _atcrt-expected-c!
    34 _atcrt-expected-c! S" rkey" _atcrt-expected+
    34 _atcrt-expected-c! 58 _atcrt-expected-c!
    34 _atcrt-expected-c! S" Key:One" _atcrt-expected+
    34 _atcrt-expected-c! 44 _atcrt-expected-c!
    34 _atcrt-expected-c! S" record" _atcrt-expected+
    34 _atcrt-expected-c! 58 _atcrt-expected-c!
    123 _atcrt-expected-c!
    34 _atcrt-expected-c! S" $type" _atcrt-expected+
    34 _atcrt-expected-c! 58 _atcrt-expected-c!
    34 _atcrt-expected-c! S" app.bsky.feed.post" _atcrt-expected+
    34 _atcrt-expected-c! 44 _atcrt-expected-c!
    34 _atcrt-expected-c! S" text" _atcrt-expected+
    34 _atcrt-expected-c! 58 _atcrt-expected-c!
    34 _atcrt-expected-c! S" hello" _atcrt-expected+
    34 _atcrt-expected-c! 125 _atcrt-expected-c!
    125 _atcrt-expected-c! ;

: _atcrt-build-success-receipt  ( -- )
    _atcrt-receipt _ATCRT-VECTOR-CAPACITY 0 FILL
    0 _atcrt-receipt-u !
    123 _atcrt-receipt-c!
    S" uri" _atcrt-receipt-key
    _atcrt-expected-uri$ _atcrt-receipt-string
    44 _atcrt-receipt-c!
    S" cid" _atcrt-receipt-key
    _atcrt-dag-cid$ _atcrt-receipt-string
    44 _atcrt-receipt-c!
    S" commit" _atcrt-receipt-key
    123 _atcrt-receipt-c!
    S" rev" _atcrt-receipt-key
    S" x" _atcrt-receipt-string
    125 _atcrt-receipt-c!
    125 _atcrt-receipt-c! ;

: _atcrt-build-challenge  ( -- )
    _atcrt-receipt _ATCRT-VECTOR-CAPACITY 0 FILL
    0 _atcrt-receipt-u !
    123 _atcrt-receipt-c!
    S" error" _atcrt-receipt-key
    S" use_dpop_nonce" _atcrt-receipt-string
    125 _atcrt-receipt-c! ;

: _atcrt-build-malformed-receipt  ( -- )
    _atcrt-receipt _ATCRT-VECTOR-CAPACITY 0 FILL
    0 _atcrt-receipt-u !
    123 _atcrt-receipt-c!
    34 _atcrt-receipt-c! S" uri" _atcrt-receipt+
    34 _atcrt-receipt-c! 58 _atcrt-receipt-c! ;

: _atcrt-build-content-length  ( -- )
    _atcrt-header 64 0 FILL
    0 _atcrt-header-u !
    S" Content-Length: " _atcrt-header+
    _atcrt-expected-body-u @ NUM>STR _atcrt-header+ ;

: _atcrt-build-vectors  ( -- )
    _atcrt-build-inputs
    _atcrt-build-target
    _atcrt-build-expected-body
    _atcrt-build-content-length
    _atcrt-expected-body-u @ 149 = _atxr-assert
    _atcrt-expected-uri$ NIP 64 = _atxr-assert
    _atcrt-dag-cid$ NIP AT-CID-TEXT-LENGTH = _atxr-assert ;

\ =====================================================================
\  Owner-parameterized deterministic transport script
\ =====================================================================

: _atcrt-wire-response+  ( address length -- )
    DUP _atcrt-response-u @ +
    _atcrt-script-context @ ATCT.RESPONSE-CAP @ U> IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atcrt-wire-response _atcrt-response-u @ + SWAP CMOVE
    R> _atcrt-response-u +! ;

: _atcrt-wire-crlf  ( -- )
    13 _atcrt-wire-response _atcrt-response-u @ + C!
    1 _atcrt-response-u +!
    10 _atcrt-wire-response _atcrt-response-u @ + C!
    1 _atcrt-response-u +! ;

: _atcrt-script-clear  ( context -- )
    _atcrt-script-context !
    _atcrt-wire-response
    _atcrt-script-context @ ATCT.RESPONSE-CAP @ 0 FILL
    0 _atcrt-response-u !
    0 _atcrt-response-pos !
    0 _atcrt-first-response-u ! ;

: _atcrt-append-http-response
  \ ( status-a status-u nonce-a nonce-u body-a body-u -- )
    _atcrt-http-body-u ! _atcrt-http-body-a !
    _atcrt-http-nonce-u ! _atcrt-http-nonce-a !
    _atcrt-http-status-u ! _atcrt-http-status-a !
    _atcrt-http-status-a @ _atcrt-http-status-u @
    _atcrt-wire-response+ _atcrt-wire-crlf
    S" Content-Type: application/json" _atcrt-wire-response+
    _atcrt-wire-crlf
    S" DPoP-Nonce: " _atcrt-wire-response+
    _atcrt-http-nonce-a @ _atcrt-http-nonce-u @
    _atcrt-wire-response+ _atcrt-wire-crlf
    S" Content-Length: " _atcrt-wire-response+
    _atcrt-http-body-u @ NUM>STR _atcrt-wire-response+
    _atcrt-wire-crlf
    S" Connection: close" _atcrt-wire-response+
    _atcrt-wire-crlf _atcrt-wire-crlf
    _atcrt-http-body-a @ _atcrt-http-body-u @
    _atcrt-wire-response+ ;

: _atcrt-build-success-script  ( context -- )
    _atcrt-script-clear
    _atcrt-build-challenge
    S" HTTP/1.1 400 Bad Request" S" pds-nonce-1"
    _atcrt-receipt _atcrt-receipt-u @
    _atcrt-append-http-response
    _atcrt-response-u @ _atcrt-first-response-u !
    _atcrt-build-success-receipt
    S" HTTP/1.1 200 OK" S" pds-nonce-2"
    _atcrt-receipt _atcrt-receipt-u @
    _atcrt-append-http-response ;

: _atcrt-build-malformed-script  ( context -- )
    _atcrt-script-clear
    _atcrt-build-malformed-receipt
    S" HTTP/1.1 200 OK" S" pds-bad-receipt"
    _atcrt-receipt _atcrt-receipt-u @
    _atcrt-append-http-response
    _atcrt-response-u @ _atcrt-first-response-u ! ;

: _atcrt-wire-reset  ( context -- )
    DUP _atcrt-observe-context !
    DUP ATCT.CAPTURE-A @ OVER ATCT.CAPTURE-CAP @ 0 FILL
    0 OVER ATCT.CAPTURE-U !
    0 OVER ATCT.REQUEST-START !
    0 OVER ATCT.REQUEST1-U !
    0 OVER ATCT.REQUEST2-U !
    0 OVER ATCT.OPEN-COUNT !
    0 OVER ATCT.CLOSE-COUNT !
    0 OVER ATCT.LOSS-RECV-COUNT !
    -1 OVER ATCT.SEND-WIRE-OK !
    0 OVER ATCT.FIRST-NONCE-OK !
    0 OVER ATCT.SECOND-NONCE-OK !
    0 SWAP ATCT.RESPONSE-POS !
    _O2PKD-RESET ;

: _atcrt-open  ( context -- io-status )
    DUP ATCT.CAPTURE-U @ OVER ATCT.REQUEST-START !
    1 OVER ATCT.OPEN-COUNT +!
    DUP ATCT.OPEN-COUNT @ 1 = IF
        DUP ATCT.FIRST-RESPONSE-U @
    ELSE
        DUP ATCT.RESPONSE-U @
    THEN
    OVER ATCT.RESPONSE-END ! DROP
    NIO-S-OK ;

: _atcrt-open-fail  ( context -- io-status )
    DROP NIO-S-FAILED ;

: _atcrt-send  ( buffer length context -- count io-status )
    >R
    R@ ATCT.CAPTURE-U @ OVER +
    R@ ATCT.CAPTURE-CAP @ U> IF
        R> DROP 2DROP
        0 _atxr-assert 0 NIO-S-FAILED EXIT
    THEN
    OVER
    R@ ATCT.CAPTURE-A @ R@ ATCT.CAPTURE-U @ +
    2 PICK CMOVE
    DUP R@ ATCT.CAPTURE-U +!

    R@ ATCT.EXCHANGE @ AT-XRPC-EXCHANGE-WIRE-STATE@
    DUP AT-XRPC-EXCHANGE-S-OK = IF
        DROP AT-XRPC-EXCHANGE-WIRE-UNCERTAIN =
    ELSE
        2DROP 0
    THEN
    R@ ATCT.SEND-WIRE-OK @ AND R@ ATCT.SEND-WIRE-OK !
    R@ ATCT.OPEN-COUNT @ 1 = IF
        _O2PKD-DPOP-NONCE-A @ 0=
        _O2PKD-DPOP-NONCE-U @ 0= AND
        R@ ATCT.FIRST-NONCE-OK !
    THEN
    R@ ATCT.OPEN-COUNT @ 2 = IF
        _O2PKD-DPOP-NONCE-A @ _O2PKD-DPOP-NONCE-U @
        S" pds-nonce-1" COMPARE 0=
        R@ ATCT.SECOND-NONCE-OK !
    THEN
    NIP R> DROP NIO-S-OK ;

: _atcrt-recv  ( buffer capacity context -- count io-status )
    >R
    R@ ATCT.RESPONSE-END @ R@ ATCT.RESPONSE-POS @ -
    DUP 0= IF
        DROP R> DROP 2DROP 0 NIO-S-EOF EXIT
    THEN
    MIN DUP R@ ATCT.IO-N !
    R@ ATCT.RESPONSE-A @ R@ ATCT.RESPONSE-POS @ +
    2 PICK R@ ATCT.IO-N @ CMOVE
    R@ ATCT.IO-N @ R@ ATCT.RESPONSE-POS +!
    NIP R> DROP NIO-S-OK ;

: _atcrt-loss-recv  ( buffer capacity context -- count io-status )
    1 OVER ATCT.LOSS-RECV-COUNT +!
    DROP 2DROP
    0 NIO-S-FAILED ;

: _atcrt-close  ( context -- io-status )
    DUP ATCT.CAPTURE-U @ OVER ATCT.REQUEST-START @ -
    OVER ATCT.CLOSE-COUNT @ 0= IF
        OVER ATCT.REQUEST1-U !
    ELSE
        OVER ATCT.CLOSE-COUNT @ 1 = IF
            OVER ATCT.REQUEST2-U !
        ELSE
            DROP 0 _atxr-assert
        THEN
    THEN
    1 OVER ATCT.CLOSE-COUNT +! DROP
    NIO-S-OK ;

: _atcrt-install-port
  \ ( exchange context open-xt recv-xt -- )
    >R >R
    2DUP ATCT.EXCHANGE !
    OVER AT-XRPC-EXCHANGE-PORT DUP NIO-INIT
    1 PICK OVER NIO.CONTEXT !
    DUP NIO.CONTEXT @ 2 PICK = _atxr-assert
    R@ OVER NIO.OPEN-START-XT !
    R> OVER NIO.OPEN-POLL-XT !
    ['] _atcrt-send OVER NIO.SEND-XT !
    R> OVER NIO.RECV-XT !
    ['] _atxr-poll OVER NIO.POLL-XT !
    ['] _atxr-cancel OVER NIO.CANCEL-XT !
    ['] _atcrt-close OVER NIO.CLOSE-START-XT !
    ['] _atcrt-close SWAP NIO.CLOSE-POLL-XT !
    2DROP ;

: _atcrt-install-scripted  ( exchange context -- )
    ['] _atcrt-open ['] _atcrt-recv _atcrt-install-port ;

: _atcrt-install-loss  ( exchange context -- )
    ['] _atcrt-open ['] _atcrt-loss-recv _atcrt-install-port ;

: _atcrt-install-no-send  ( exchange context -- )
    ['] _atcrt-open-fail ['] _atcrt-recv _atcrt-install-port ;

\ =====================================================================
\  Two independent owner graphs and exact request observations
\ =====================================================================

: _atcrt-bind  ( exchange -- )
    >R
    _atxr-active-vault @
    _atoct-config
    _atopt-profile
    _atxr-active-session @
    R> AT-XRPC-EXCHANGE-BIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status ;

: _atcrt-allocate-graphs  ( -- )
    AT-XRPC-EXCHANGE-SIZE _atcrt-exchange-a _atxr-allocate
    AT-XRPC-EXCHANGE-SIZE _atcrt-exchange-b _atxr-allocate
    _ATCRT-XREQUEST-A-CAPACITY _atcrt-xrequest-a _atxr-allocate
    _ATCRT-XREQUEST-B-CAPACITY _atcrt-xrequest-b _atxr-allocate
    _ATCRT-XBODY-A-CAPACITY _atcrt-xbody-a _atxr-allocate
    _ATCRT-XBODY-B-CAPACITY _atcrt-xbody-b _atxr-allocate
    AT-CREATE-RECORD-SIZE _atcrt-owner-a _atxr-allocate
    AT-CREATE-RECORD-SIZE _atcrt-owner-b _atxr-allocate
    _ATCRT-CREATE-BODY-A-CAPACITY
        _atcrt-create-body-a _atxr-allocate
    _ATCRT-CREATE-BODY-B-CAPACITY
        _atcrt-create-body-b _atxr-allocate
    AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        _atcrt-work-a _atxr-allocate
    AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        _atcrt-work-b _atxr-allocate
    AT-CREATE-RECORD-RESULT-SIZE _atcrt-result-a _atxr-allocate
    AT-CREATE-RECORD-RESULT-SIZE _atcrt-result-b _atxr-allocate
    _ATCRT-RESULT-A-CAPACITY _atcrt-result-bytes-a _atxr-allocate
    _ATCRT-RESULT-B-CAPACITY _atcrt-result-bytes-b _atxr-allocate
    _ATCRT-RESULT-SMALL-CAPACITY
        _atcrt-result-bytes-small _atxr-allocate
    _ATCRT-TRANSPORT-CONTEXT-SIZE
        _atcrt-context-a _atxr-allocate
    _ATCRT-TRANSPORT-CONTEXT-SIZE
        _atcrt-context-b _atxr-allocate
    _ATCRT-WIRE-RESPONSE-CAPACITY
        _atcrt-response-a _atxr-allocate
    _ATCRT-WIRE-RESPONSE-CAPACITY
        _atcrt-response-b _atxr-allocate
    _ATCRT-CAPTURE-A-CAPACITY _atcrt-capture-a _atxr-allocate
    _ATCRT-CAPTURE-B-CAPACITY _atcrt-capture-b _atxr-allocate ;

: _atcrt-zero-graphs  ( -- )
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-SIZE 0 FILL
    _atcrt-exchange-b @ AT-XRPC-EXCHANGE-SIZE 0 FILL
    _atcrt-xrequest-a @ _ATCRT-XREQUEST-A-CAPACITY 0 FILL
    _atcrt-xrequest-b @ _ATCRT-XREQUEST-B-CAPACITY 0 FILL
    _atcrt-xbody-a @ _ATCRT-XBODY-A-CAPACITY 0 FILL
    _atcrt-xbody-b @ _ATCRT-XBODY-B-CAPACITY 0 FILL
    _atcrt-owner-a @ AT-CREATE-RECORD-SIZE 0 FILL
    _atcrt-owner-b @ AT-CREATE-RECORD-SIZE 0 FILL
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY 0 FILL
    _atcrt-create-body-b @ _ATCRT-CREATE-BODY-B-CAPACITY 0 FILL
    _atcrt-work-a @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    _atcrt-work-b @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-SIZE 0 FILL
    _atcrt-result-b @ AT-CREATE-RECORD-RESULT-SIZE 0 FILL
    _atcrt-result-bytes-a @ _ATCRT-RESULT-A-CAPACITY 0 FILL
    _atcrt-result-bytes-b @ _ATCRT-RESULT-B-CAPACITY 0 FILL
    _atcrt-result-bytes-small @
        _ATCRT-RESULT-SMALL-CAPACITY 0 FILL
    _atcrt-context-a @ _ATCRT-TRANSPORT-CONTEXT-SIZE 0 FILL
    _atcrt-context-b @ _ATCRT-TRANSPORT-CONTEXT-SIZE 0 FILL
    _atcrt-response-a @ _ATCRT-WIRE-RESPONSE-CAPACITY 0 FILL
    _atcrt-response-b @ _ATCRT-WIRE-RESPONSE-CAPACITY 0 FILL
    _atcrt-capture-a @ _ATCRT-CAPTURE-A-CAPACITY 0 FILL
    _atcrt-capture-b @ _ATCRT-CAPTURE-B-CAPACITY 0 FILL ;

: _atcrt-init-context
  \ ( exchange response-a response-cap capture-a capture-cap context -- )
    >R
    R@ _ATCRT-TRANSPORT-CONTEXT-SIZE 0 FILL
    R@ ATCT.CAPTURE-CAP !
    R@ ATCT.CAPTURE-A !
    R@ ATCT.RESPONSE-CAP !
    R@ ATCT.RESPONSE-A !
    R@ ATCT.EXCHANGE !
    R> DROP ;

: _atcrt-init-contexts  ( -- )
    _atcrt-exchange-a @
    _atcrt-response-a @ _ATCRT-WIRE-RESPONSE-CAPACITY
    _atcrt-capture-a @ _ATCRT-CAPTURE-A-CAPACITY
    _atcrt-context-a @ _atcrt-init-context
    _atcrt-exchange-b @
    _atcrt-response-b @ _ATCRT-WIRE-RESPONSE-CAPACITY
    _atcrt-capture-b @ _ATCRT-CAPTURE-B-CAPACITY
    _atcrt-context-b @ _atcrt-init-context
    _atcrt-context-a @ DUP _atcrt-script-context !
    _atcrt-observe-context ! ;

: _atcrt-init-exchanges  ( -- )
    _atcrt-xrequest-a @ _ATCRT-XREQUEST-A-CAPACITY
    _atcrt-xbody-a @ _ATCRT-XBODY-A-CAPACITY
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-INIT
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atcrt-xrequest-b @ _ATCRT-XREQUEST-B-CAPACITY
    _atcrt-xbody-b @ _ATCRT-XBODY-B-CAPACITY
    _atcrt-exchange-b @ AT-XRPC-EXCHANGE-INIT
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atcrt-exchange-a @ _atcrt-bind
    _atcrt-exchange-b @ _atcrt-bind
    _atcrt-init-contexts ;

: _atcrt-init-results-and-owners  ( -- )
    _atcrt-result-bytes-small @ _ATCRT-RESULT-SMALL-CAPACITY
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-INIT
    AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-result-bytes-b @ _ATCRT-RESULT-B-CAPACITY
    _atcrt-result-b @ AT-CREATE-RECORD-RESULT-INIT
    AT-CREATE-RECORD-S-OK _atxr-status

    _atcrt-exchange-a @
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY
    _atcrt-work-a @ _atcrt-result-a @ _atcrt-owner-a @
    AT-CREATE-RECORD-INIT
    AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-exchange-b @
    _atcrt-create-body-b @ _ATCRT-CREATE-BODY-B-CAPACITY
    _atcrt-work-b @ _atcrt-result-b @ _atcrt-owner-b @
    AT-CREATE-RECORD-INIT
    AT-CREATE-RECORD-S-OK _atxr-status

    _atcrt-owner-a @ AT-CREATE-RECORD-VALID? _atxr-assert
    _atcrt-owner-b @ AT-CREATE-RECORD-VALID? _atxr-assert
    _atcrt-owner-a @ _atcrt-owner-b @ <> _atxr-assert
    _atcrt-exchange-a @ _atcrt-exchange-b @ <> _atxr-assert
    _atcrt-context-a @ _atcrt-context-b @ <> _atxr-assert
    _atcrt-context-a @ ATCT.EXCHANGE @
        _atcrt-exchange-a @ = _atxr-assert
    _atcrt-context-b @ ATCT.EXCHANGE @
        _atcrt-exchange-b @ = _atxr-assert
    _atcrt-context-a @ ATCT.CAPTURE-CAP @
        _ATCRT-CAPTURE-A-CAPACITY = _atxr-assert
    _atcrt-context-b @ ATCT.CAPTURE-CAP @
        _ATCRT-CAPTURE-B-CAPACITY = _atxr-assert
    _atcrt-owner-a @ ATCR.BODY-CAP @
        _ATCRT-CREATE-BODY-A-CAPACITY = _atxr-assert
    _atcrt-owner-b @ ATCR.BODY-CAP @
        _ATCRT-CREATE-BODY-B-CAPACITY = _atxr-assert
    _atcrt-exchange-a @ ATXE.REQUEST-CAP @
        _ATCRT-XREQUEST-A-CAPACITY = _atxr-assert
    _atcrt-exchange-b @ ATXE.REQUEST-CAP @
        _ATCRT-XREQUEST-B-CAPACITY = _atxr-assert ;

: _atcrt-prepare-a  ( -- status )
    _ATXR-IAT _atcrt-target
    _atcrt-collection _atcrt-collection-u @
    _atcrt-rkey _atcrt-rkey-u @
    _atcrt-record _atcrt-record-u @
    _atcrt-owner-a @ AT-CREATE-RECORD-PREPARE ;

: _atcrt-prepare-b  ( -- status )
    _ATXR-IAT _atcrt-target
    _atcrt-collection _atcrt-collection-u @
    _atcrt-rkey _atcrt-rkey-u @
    _atcrt-record _atcrt-record-u @
    _atcrt-owner-b @ AT-CREATE-RECORD-PREPARE ;

: _atcrt-drive  ( owner operation -- final-step )
    _atcrt-active-op ! _atcrt-active-owner !
    _atcrt-active-op @ XIO-OP-INIT
    _atcrt-active-op @ _atcrt-active-owner @
    AT-CREATE-RECORD-XIO-START
    DUP XIO-STEP-PENDING <> IF EXIT THEN
    DROP
    0 _atcrt-polls !
    BEGIN
        _atcrt-active-op @ _atcrt-active-owner @
        AT-CREATE-RECORD-XIO-POLL
        DUP _atcrt-step !
        XIO-STEP-PENDING =
    WHILE
        1 _atcrt-polls +!
        _atcrt-polls @ _ATCRT-POLL-LIMIT U< 0= IF
            0 _atxr-assert
            _atcrt-step @ EXIT
        THEN
    REPEAT
    _atcrt-step @ ;

: _atcrt-http-body@
  \ ( request-a request-u -- body-a body-u found? )
    _atcrt-scan-u ! _atcrt-scan-a !
    BEGIN
        _atcrt-scan-u @ 4 U< 0=
    WHILE
        _atcrt-scan-a @ 4 _atcrt-crlfcrlf 4
        COMPARE 0= IF
            _atcrt-scan-a @ 4 +
            _atcrt-scan-u @ 4 - -1 EXIT
        THEN
        1 _atcrt-scan-a +!
        -1 _atcrt-scan-u +!
    REPEAT
    0 0 0 ;

: _atcrt-request-contains?  ( needle-a needle-u -- flag )
    _atcrt-request-a @ _atcrt-request-u @
    2SWAP _atxr-contains? ;

: _atcrt-check-request  ( request-a request-u -- )
    _atcrt-request-u ! _atcrt-request-a !
    S" POST /xrpc/com.atproto.repo.createRecord HTTP/1.1"
    _atcrt-http-status-u ! _atcrt-http-status-a !
    _atcrt-request-u @ _atcrt-http-status-u @ U< 0= _atxr-assert
    _atcrt-request-a @ _atcrt-http-status-u @
    _atcrt-http-status-a @ _atcrt-http-status-u @
    COMPARE 0= _atxr-assert
    S" Host: pds.example" _atcrt-request-contains? _atxr-assert
    S" Content-Type: application/json"
    _atcrt-request-contains? _atxr-assert
    _atcrt-header _atcrt-header-u @
    _atcrt-request-contains? _atxr-assert
    S" Authorization: DPoP access-vertical"
    _atcrt-request-contains? _atxr-assert
    S" DPoP: deterministic-dpop-proof"
    _atcrt-request-contains? _atxr-assert
    _atcrt-request-a @ _atcrt-request-u @ _atcrt-http-body@
    0= IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP _atcrt-expected-body-u @ = _atxr-assert
    _atcrt-expected-body _atcrt-expected-body-u @
    COMPARE 0= _atxr-assert ;

: _atcrt-expect-outcome  ( result expected-outcome -- )
    >R
    AT-CREATE-RECORD-RESULT-OUTCOME@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    R> = _atxr-assert ;

: _atcrt-expect-wire  ( result expected-wire -- )
    >R
    AT-CREATE-RECORD-RESULT-WIRE@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    R> = _atxr-assert ;

: _atcrt-check-created-result  ( result -- )
    DUP AT-CREATE-RECORD-RESULT-VALID? _atxr-assert
    DUP AT-CREATE-RECORD-OUTCOME-CREATED _atcrt-expect-outcome
    DUP AT-CREATE-RECORD-RESULT-STATUS@
    AT-CREATE-RECORD-S-OK _atxr-status
    DUP AT-CREATE-RECORD-RESULT-HTTP@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    200 = _atxr-assert
    DUP AT-XRPC-EXCHANGE-WIRE-RESPONSE _atcrt-expect-wire
    DUP AT-CREATE-RECORD-RESULT-URI@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    _atcrt-expected-uri$ COMPARE 0= _atxr-assert
    AT-CREATE-RECORD-RESULT-CID@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    _atcrt-dag-cid$ COMPARE 0= _atxr-assert ;

\ =====================================================================
\  Local admission, wire evidence, and durable publication scenarios
\ =====================================================================

: _atcrt-owner-state  ( owner expected -- )
    >R
    AT-CREATE-RECORD-STATE@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    R> = _atxr-assert ;

: _atcrt-exchange-state  ( exchange expected -- )
    >R
    AT-XRPC-EXCHANGE-STATE@
    DUP AT-XRPC-EXCHANGE-S-OK _atxr-status DROP
    R> = _atxr-assert ;

: _atcrt-wipe-a  ( -- )
    _atcrt-op-a _atcrt-owner-a @ AT-CREATE-RECORD-XIO-WIPE
    _atcrt-owner-a @ AT-CREATE-RECORD-STATE-IDLE
        _atcrt-owner-state
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-STATE-BOUND
        _atcrt-exchange-state
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY
        _atxr-zero? _atxr-assert
    _atcrt-work-a @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        _atxr-zero? _atxr-assert ;

: _atcrt-check-no-effect  ( expected-status -- )
    >R
    _atcrt-result-a @ AT-CREATE-RECORD-OUTCOME-NO-EFFECT
        _atcrt-expect-outcome
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-STATUS@
        R> _atxr-status
    _atcrt-result-a @ AT-XRPC-EXCHANGE-WIRE-NONE
        _atcrt-expect-wire
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-HTTP@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    0= _atxr-assert ;

: _atcrt-check-uncertain  ( expected-status expected-wire -- )
    >R >R
    _atcrt-result-a @ AT-CREATE-RECORD-OUTCOME-UNCERTAIN
        _atcrt-expect-outcome
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-STATUS@
        R> _atxr-status
    _atcrt-result-a @ R> _atcrt-expect-wire ;

: _ATCRT-SETUP  ( -- )
    _atcrt-build-vectors
    _atcrt-allocate-graphs
    _atcrt-zero-graphs
    _atcrt-init-exchanges
    _atcrt-init-results-and-owners
    _atcrt-owner-a @ AT-CREATE-RECORD-STATE-IDLE
        _atcrt-owner-state
    _atcrt-owner-b @ AT-CREATE-RECORD-STATE-IDLE
        _atcrt-owner-state
    _atxr-stack ;

: _atcrt-small-result  ( -- )
    _atcrt-build-inputs
    _atcrt-build-target
    _atcrt-context-a @ _atcrt-script-clear
    _atcrt-context-a @ _atcrt-wire-reset
    _atcrt-prepare-a
    AT-CREATE-RECORD-S-CAPACITY _atxr-status
    _atcrt-capture-u @ 0= _atxr-assert
    AT-CREATE-RECORD-S-CAPACITY _atcrt-check-no-effect
    _atcrt-owner-a @ AT-CREATE-RECORD-STATE-IDLE
        _atcrt-owner-state
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-STATE-BOUND
        _atcrt-exchange-state
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY
        _atxr-zero? _atxr-assert
    _atcrt-work-a @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        _atxr-zero? _atxr-assert ;

: _atcrt-reinit-a  ( -- )
    _atcrt-result-bytes-a @ _ATCRT-RESULT-A-CAPACITY
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-INIT
    AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-exchange-a @
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY
    _atcrt-work-a @ _atcrt-result-a @ _atcrt-owner-a @
    AT-CREATE-RECORD-INIT
    AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-owner-a @ AT-CREATE-RECORD-VALID? _atxr-assert ;

: _atcrt-target-alias-no-write  ( -- )
    _atcrt-build-inputs
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY
        0xA5 FILL
    _atcrt-work-a @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        0xB6 FILL
    _atcrt-result-bytes-a @ _ATCRT-RESULT-A-CAPACITY 0 FILL
    _atcrt-context-a @ _atcrt-script-clear
    _atcrt-context-a @ _atcrt-wire-reset
    _ATXR-IAT _atcrt-create-body-a @
    _atcrt-collection _atcrt-collection-u @
    _atcrt-rkey _atcrt-rkey-u @
    _atcrt-record _atcrt-record-u @
    _atcrt-owner-a @ AT-CREATE-RECORD-PREPARE
    AT-CREATE-RECORD-S-ALIAS _atxr-status
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY
        0xA5 _atxr-filled? _atxr-assert
    _atcrt-work-a @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        0xB6 _atxr-filled? _atxr-assert
    _atcrt-result-bytes-a @ _ATCRT-RESULT-A-CAPACITY
        _atxr-zero? _atxr-assert
    _atcrt-result-a @ AT-CREATE-RECORD-OUTCOME-NO-EFFECT
        _atcrt-expect-outcome
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-STATUS@
        AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-owner-a @ AT-CREATE-RECORD-STATE-IDLE
        _atcrt-owner-state
    _atcrt-capture-u @ 0= _atxr-assert
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY 0 FILL
    _atcrt-work-a @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL ;

: _atcrt-composition-seams  ( -- )
    _atcrt-build-target
    _atcrt-target AT-CREATE-RECORD-TARGET? _atxr-assert
    S" https://pds.example/xrpc/com.atproto.repo.getRecord"
    _atcrt-target HTARGET-PARSE HTARGET-S-OK _atxr-status
    _atcrt-target AT-CREATE-RECORD-TARGET? 0= _atxr-assert
    _atcrt-build-target

    _atcrt-owner-a @ AT-CREATE-RECORD-RESULT@
    AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-result-a @ = _atxr-assert
    0 AT-CREATE-RECORD-RESULT@
    AT-CREATE-RECORD-S-INVALID _atxr-status
    0= _atxr-assert

    _atcrt-record _ATCRT-VECTOR-CAPACITY _atcrt-owner-a @
    AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-owner-a @ AT-CREATE-RECORD-SIZE _atcrt-owner-a @
    AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-ALIAS _atxr-status
    _atcrt-create-body-a @ _ATCRT-CREATE-BODY-A-CAPACITY
    _atcrt-owner-a @ AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-ALIAS _atxr-status
    _atcrt-work-a @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    _atcrt-owner-a @ AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-ALIAS _atxr-status
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-SIZE _atcrt-owner-a @
    AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-ALIAS _atxr-status
    _atcrt-result-bytes-a @ _ATCRT-RESULT-A-CAPACITY
    _atcrt-owner-a @ AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-ALIAS _atxr-status
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-SIZE _atcrt-owner-a @
    AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-ALIAS _atxr-status
    0 1 _atcrt-owner-a @ AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS
    AT-CREATE-RECORD-S-INVALID _atxr-status
    _atxr-stack ;

: _atcrt-prepare-durable-b  ( -- )
    _atcrt-build-inputs
    _atcrt-build-target
    _atcrt-prepare-b AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-owner-b @ AT-CREATE-RECORD-STATE-PREPARED
        _atcrt-owner-state
    _atcrt-create-body-b @
    _atcrt-owner-b @ ATCR.BODY-U @
    _atcrt-expected-body _atcrt-expected-body-u @
        COMPARE 0= _atxr-assert
    _atcrt-result-b @ ATCRR.EXPECTED-U @ 64 = _atxr-assert
    _atcrt-result-b @ ATCRR.BYTES-A @ 64
    _atcrt-expected-uri$ COMPARE 0= _atxr-assert

    \ PREPARE owns target, collection, key, and record before returning.
    _atcrt-target HTARGET-SIZE 0xA1 FILL
    _atcrt-collection NSID-LENGTH-MAX 0xB2 FILL
    _atcrt-rkey AT-RKEY-LENGTH-MAX 0xC3 FILL
    _atcrt-record _ATCRT-VECTOR-CAPACITY 0xD4 FILL
    _atcrt-create-body-b @
    _atcrt-owner-b @ ATCR.BODY-U @
    _atcrt-expected-body _atcrt-expected-body-u @
        COMPARE 0= _atxr-assert
    _atcrt-exchange-b @ AT-XRPC-EXCHANGE-STATE-PREPARED
        _atcrt-exchange-state ;

: _ATCRT-LOCAL  ( -- )
    _atcrt-small-result
    _atcrt-reinit-a
    _atcrt-composition-seams
    _atcrt-target-alias-no-write
    _atcrt-prepare-durable-b
    _atxr-stack ;

: _atcrt-prepare-failure-a  ( -- )
    _atcrt-build-inputs
    _atcrt-build-target
    _atcrt-prepare-a AT-CREATE-RECORD-S-OK _atxr-status
    _atcrt-owner-a @ AT-CREATE-RECORD-STATE-PREPARED
        _atcrt-owner-state ;

: _atcrt-no-send  ( -- )
    _atcrt-prepare-failure-a
    _atcrt-context-a @ _atcrt-script-clear
    _atcrt-context-a @ _atcrt-wire-reset
    _atcrt-exchange-a @ _atcrt-context-a @
        _atcrt-install-no-send
    _atcrt-owner-a @ _atcrt-op-a _atcrt-drive
    XIO-STEP-FAILED _atxr-status
    _atcrt-capture-u @ 0= _atxr-assert
    AT-CREATE-RECORD-S-XRPC _atcrt-check-no-effect
    _atcrt-op-a XIOO.ERROR @
        AT-CREATE-RECORD-XERR-XRPC = _atxr-assert
    _atcrt-wipe-a ;

: _atcrt-loss-after-send  ( -- )
    _atcrt-prepare-failure-a
    _atcrt-context-a @ _atcrt-script-clear
    _atcrt-context-a @ _atcrt-wire-reset
    _atcrt-exchange-a @ _atcrt-context-a @
        _atcrt-install-loss
    _atcrt-owner-a @ _atcrt-op-a _atcrt-drive
    XIO-STEP-FAILED _atxr-status
    _atcrt-capture-u @ 0> _atxr-assert
    _atcrt-capture @ _atcrt-capture-u @ _atcrt-check-request
    AT-CREATE-RECORD-S-XRPC
    AT-XRPC-EXCHANGE-WIRE-UNCERTAIN _atcrt-check-uncertain
    _atcrt-loss-recv-count @ 1 = _atxr-assert
    _atcrt-open-count @ 1 = _atxr-assert
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-ATTEMPTS@
    DUP AT-XRPC-EXCHANGE-S-OK _atxr-status DROP
    1 = _atxr-assert
    _O2PKD-DPOP-CALLS @ 1 = _atxr-assert
    _atcrt-wipe-a ;

: _atcrt-malformed-200  ( -- )
    _atcrt-prepare-failure-a
    _atcrt-context-a @ _atcrt-build-malformed-script
    _atcrt-context-a @ _atcrt-wire-reset
    _atcrt-exchange-a @ _atcrt-context-a @
        _atcrt-install-scripted
    _atcrt-owner-a @ _atcrt-op-a _atcrt-drive
    XIO-STEP-FAILED _atxr-status
    _atcrt-capture @ _atcrt-capture-u @ _atcrt-check-request
    AT-CREATE-RECORD-S-JSON
    AT-XRPC-EXCHANGE-WIRE-RESPONSE _atcrt-check-uncertain
    _atcrt-result-a @ AT-CREATE-RECORD-RESULT-HTTP@
    DUP AT-CREATE-RECORD-S-OK _atxr-status DROP
    200 = _atxr-assert
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-ATTEMPTS@
    DUP AT-XRPC-EXCHANGE-S-OK _atxr-status DROP
    1 = _atxr-assert
    _O2PKD-DPOP-CALLS @ 1 = _atxr-assert
    _atcrt-wipe-a ;

: _ATCRT-FAILURES  ( -- )
    _atcrt-no-send
    _atcrt-loss-after-send
    _atcrt-malformed-200
    _atcrt-owner-b @ AT-CREATE-RECORD-STATE-PREPARED
        _atcrt-owner-state
    _atcrt-create-body-b @
    _atcrt-owner-b @ ATCR.BODY-U @
    _atcrt-expected-body _atcrt-expected-body-u @
        COMPARE 0= _atxr-assert
    _atxr-stack ;

: _atcrt-check-success-wire  ( -- )
    _atcrt-open-count @ 2 = _atxr-assert
    _atcrt-close-count @ 2 = _atxr-assert
    _atcrt-request1-u @ 0> _atxr-assert
    _atcrt-request2-u @ 0> _atxr-assert
    _atcrt-request1-u @ _atcrt-request2-u @ +
        _atcrt-capture-u @ = _atxr-assert
    _atcrt-capture @ _atcrt-request1-u @
        _atcrt-check-request
    _atcrt-capture @ _atcrt-request1-u @ +
    _atcrt-request2-u @ _atcrt-check-request
    _atcrt-first-nonce-ok @ _atxr-assert
    _atcrt-second-nonce-ok @ _atxr-assert
    _atcrt-send-wire-ok @ _atxr-assert
    _O2PKD-DPOP-CALLS @ 2 = _atxr-assert
    _O2PKD-DPOP-HTM-A @ _O2PKD-DPOP-HTM-U @
    S" POST" COMPARE 0= _atxr-assert
    _O2PKD-DPOP-HTU-A @ _O2PKD-DPOP-HTU-U @
    S" https://pds.example/xrpc/com.atproto.repo.createRecord"
        COMPARE 0= _atxr-assert
    _atcrt-exchange-b @ AT-XRPC-EXCHANGE-ATTEMPTS@
    DUP AT-XRPC-EXCHANGE-S-OK _atxr-status DROP
    2 = _atxr-assert
    _atcrt-exchange-b @ AT-XRPC-EXCHANGE-NONCE-GENERATION@
    DUP AT-XRPC-EXCHANGE-S-OK _atxr-status DROP
    2 = _atxr-assert ;

: _atcrt-wipe-b  ( -- )
    _atcrt-op-b _atcrt-owner-b @ AT-CREATE-RECORD-XIO-WIPE
    _atcrt-owner-b @ AT-CREATE-RECORD-STATE-IDLE
        _atcrt-owner-state
    _atcrt-exchange-b @ AT-XRPC-EXCHANGE-STATE-BOUND
        _atcrt-exchange-state
    _atcrt-create-body-b @ _ATCRT-CREATE-BODY-B-CAPACITY
        _atxr-zero? _atxr-assert
    _atcrt-work-b @ AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
        _atxr-zero? _atxr-assert
    _atcrt-xrequest-b @ _ATCRT-XREQUEST-B-CAPACITY
        _atxr-zero? _atxr-assert
    _atcrt-xbody-b @ _ATCRT-XBODY-B-CAPACITY
        _atxr-zero? _atxr-assert ;

: _ATCRT-SUCCESS  ( -- )
    _atcrt-owner-b @ AT-CREATE-RECORD-STATE-PREPARED
        _atcrt-owner-state
    _atcrt-create-body-b @
    _atcrt-owner-b @ ATCR.BODY-U @
    _atcrt-expected-body _atcrt-expected-body-u @
        COMPARE 0= _atxr-assert
    _atcrt-context-b @ _atcrt-build-success-script
    _atcrt-context-b @ _atcrt-wire-reset
    _atcrt-exchange-b @ _atcrt-context-b @
        _atcrt-install-scripted
    _atcrt-owner-b @ _atcrt-op-b _atcrt-drive
    XIO-STEP-SUCCEEDED _atxr-status
    _atcrt-check-success-wire
    _atcrt-result-b @ _atcrt-check-created-result
    _atcrt-op-b XIOO.RESULT @
        _atcrt-result-b @ = _atxr-assert
    _atcrt-wipe-b
    _atcrt-result-b @ _atcrt-check-created-result
    _atxr-stack ;

: _atcrt-free-owner-graphs  ( -- )
    _atcrt-owner-a @ ?DUP IF
        AT-CREATE-RECORD-SIZE 0 FILL
    THEN
    _atcrt-owner-b @ ?DUP IF
        AT-CREATE-RECORD-SIZE 0 FILL
    THEN
    _atcrt-exchange-a @ ?DUP IF
        AT-XRPC-EXCHANGE-SIZE 0 FILL
    THEN
    _atcrt-exchange-b @ ?DUP IF
        AT-XRPC-EXCHANGE-SIZE 0 FILL
    THEN
    _atcrt-context-a @ ?DUP IF
        _ATCRT-TRANSPORT-CONTEXT-SIZE 0 FILL
    THEN
    _atcrt-context-b @ ?DUP IF
        _ATCRT-TRANSPORT-CONTEXT-SIZE 0 FILL
    THEN
    _atcrt-response-a @ ?DUP IF
        _ATCRT-WIRE-RESPONSE-CAPACITY 0 FILL
    THEN
    _atcrt-response-b @ ?DUP IF
        _ATCRT-WIRE-RESPONSE-CAPACITY 0 FILL
    THEN
    _atcrt-capture-a @ ?DUP IF
        _ATCRT-CAPTURE-A-CAPACITY 0 FILL
    THEN
    _atcrt-capture-b @ ?DUP IF
        _ATCRT-CAPTURE-B-CAPACITY 0 FILL
    THEN
    0 _atcrt-script-context !
    0 _atcrt-observe-context !
    _atcrt-capture-b _atxr-free
    _atcrt-capture-a _atxr-free
    _atcrt-response-b _atxr-free
    _atcrt-response-a _atxr-free
    _atcrt-context-b _atxr-free
    _atcrt-context-a _atxr-free
    _atcrt-result-bytes-small _atxr-free
    _atcrt-result-a _atxr-free
    _atcrt-result-bytes-a _atxr-free
    _atcrt-work-b _atxr-free
    _atcrt-work-a _atxr-free
    _atcrt-create-body-b _atxr-free
    _atcrt-create-body-a _atxr-free
    _atcrt-owner-b _atxr-free
    _atcrt-owner-a _atxr-free
    _atcrt-xbody-b _atxr-free
    _atcrt-xbody-a _atxr-free
    _atcrt-xrequest-b _atxr-free
    _atcrt-xrequest-a _atxr-free
    _atcrt-exchange-b _atxr-free
    _atcrt-exchange-a _atxr-free
    0 _atcrt-active-owner !
    0 _atcrt-active-op ! ;

: _ATCRT-RELEASE-OWNERS  ( -- )
    _atcrt-exchange-a @ AT-XRPC-EXCHANGE-UNBIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atcrt-exchange-b @ AT-XRPC-EXCHANGE-UNBIND
    AT-XRPC-EXCHANGE-S-OK _atxr-status
    _atcrt-free-owner-graphs
    _atxr-stack ;

: _atcrt-clear-static  ( -- )
    _atcrt-target HTARGET-SIZE 0 FILL
    _atcrt-op-a XIO-OP-SIZE 0 FILL
    _atcrt-op-b XIO-OP-SIZE 0 FILL
    _atcrt-collection NSID-LENGTH-MAX 0 FILL
    _atcrt-rkey AT-RKEY-LENGTH-MAX 0 FILL
    _atcrt-record _ATCRT-VECTOR-CAPACITY 0 FILL
    _atcrt-expected-body _ATCRT-VECTOR-CAPACITY 0 FILL
    _atcrt-receipt _ATCRT-VECTOR-CAPACITY 0 FILL
    _atcrt-header 64 0 FILL ;

: _ATCRT-FINISH  ( -- )
    _ATXR-FINISH

    \ The result graph is self-contained after owner, exchange, session,
    \ profile, vault, and VFS teardown.
    _atcrt-result-b @ _atcrt-check-created-result
    _atcrt-result-b _atxr-free
    _atcrt-result-bytes-b _atxr-free
    _atcrt-clear-static
    _atxr-stack
    _atxr-fails @ IF
        ." CREATE RECORD E2E FAIL checks/fails "
        _atxr-checks @ . _atxr-fails @ . CR
    ELSE
        ." CREATE RECORD E2E PASS checks " _atxr-checks @ . CR
    THEN
    TX-FLUSH ;
