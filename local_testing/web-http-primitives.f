\ =====================================================================
\ web-http-primitives.f - focused contracts for HTTP request/router/writer
\ =====================================================================

PROVIDED akashic-web-http-primitives-contracts

\ ---------------------------------------------------------------------
\ Shared assertions and byte helpers
\ ---------------------------------------------------------------------

VARIABLE _whq-fails
VARIABLE _whq-checks
VARIABLE _whq-depth
VARIABLE _whq-stage

: _whq-assert  ( flag -- )
    1 _whq-checks +!
    0= IF
        1 _whq-fails +!
        ." WEB HTTP PRIMITIVES ASSERT " _whq-checks @ . CR
    THEN ;

: _whq-stack  ( -- )
    DEPTH DUP _whq-depth @ <> IF
        ." WEB HTTP PRIMITIVES STACK "
        _whq-depth @ . ." -> " DUP . CR .S CR
    THEN
    _whq-depth @ = _whq-assert ;

: _whq-span=  ( a1 u1 a2 u2 -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP -1 EXIT THEN
    >R SWAP DROP R>
    0 ?DO
        OVER I + C@ OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

VARIABLE _whq-fill-byte

: _whq-filled?  ( address length byte -- flag )
    _whq-fill-byte !
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ _whq-fill-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

VARIABLE _whq-hay-a
VARIABLE _whq-hay-u
VARIABLE _whq-needle-a
VARIABLE _whq-needle-u

: _whq-contains?  ( hay-a hay-u needle-a needle-u -- flag )
    _whq-needle-u !
    _whq-needle-a !
    _whq-hay-u !
    _whq-hay-a !
    _whq-needle-u @ 0= IF -1 EXIT THEN
    _whq-hay-u @ _whq-needle-u @ < IF 0 EXIT THEN
    _whq-hay-u @ _whq-needle-u @ - 1+ 0 ?DO
        _whq-hay-a @ I + _whq-needle-u @
        _whq-needle-a @ _whq-needle-u @ COMPARE 0= IF
            -1 UNLOOP EXIT
        THEN
    LOOP
    0 ;

\ ---------------------------------------------------------------------
\ Incremental request parser contracts
\ ---------------------------------------------------------------------

20000 CONSTANT _WHQ-REQUEST-INPUT-CAPACITY
16384 CONSTANT _WHQ-REQUEST-HEADER-CAPACITY
5000 CONSTANT _WHQ-LARGE-BODY-U
733 CONSTANT _WHQ-BODY-FRAGMENT-U

CREATE _whq-request-input _WHQ-REQUEST-INPUT-CAPACITY ALLOT
CREATE _whq-request-header _WHQ-REQUEST-HEADER-CAPACITY ALLOT
CREATE _whq-request WEB-HTTP-REQUEST-STREAM-SIZE ALLOT

VARIABLE _whq-request-input-u
VARIABLE _whq-request-body-start
VARIABLE _whq-request-tail-start
VARIABLE _whq-request-position
VARIABLE _whq-request-chunk
VARIABLE _whq-request-consumed
VARIABLE _whq-request-expected-consumed
VARIABLE _whq-request-status
VARIABLE _whq-request-body-seen
VARIABLE _whq-request-expected-status

: _whq-request-input-reset  ( -- )
    0 _whq-request-input-u ! ;

: _whq-request-input+  ( source-a source-u -- )
    DUP IF
        2DUP
        _whq-request-input _whq-request-input-u @ + SWAP CMOVE
        DUP _whq-request-input-u +!
    THEN
    2DROP ;

: _whq-request-input-c+  ( c -- )
    _whq-request-input _whq-request-input-u @ + C!
    1 _whq-request-input-u +! ;

: _whq-request-input-fill+  ( c u -- )
    >R
    _whq-request-input _whq-request-input-u @ +
    R@ ROT FILL
    R> _whq-request-input-u +! ;

: _whq-request-crlf  ( -- )
    13 _whq-request-input-c+
    10 _whq-request-input-c+ ;

: _whq-request-body-callback  ( request context -- status )
    DROP WREQ-BODY-SLICE
    2DUP [CHAR] b _whq-filled? _whq-assert
    DUP _whq-request-body-seen +!
    2DROP 0 ;

: _whq-request-init  ( -- )
    0 _whq-request-body-seen !
    _whq-request-header _WHQ-REQUEST-HEADER-CAPACITY
    8192 ['] _whq-request-body-callback 0 _whq-request
    WREQ-INIT WREQ-S-PENDING = _whq-assert ;

: _whq-request-feed-fragment  ( u -- )
    DUP _whq-request-chunk !
    _whq-request-input _whq-request-position @ +
    SWAP _whq-request WREQ-FEED
    _whq-request-status !
    _whq-request-consumed !
    _whq-request-consumed @ 0> _whq-assert
    _whq-request-consumed @ _whq-request-position +! ;

: _whq-build-large-request  ( -- )
    _whq-request-input-reset
    S" POST /upload HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    S" X-Fill: " _whq-request-input+
    [CHAR] a 4500 _whq-request-input-fill+ _whq-request-crlf
    S" X-Role: first" _whq-request-input+ _whq-request-crlf
    S" x-role: second" _whq-request-input+ _whq-request-crlf
    S" X-Empty:" _whq-request-input+ _whq-request-crlf
    S" Content-Length: 5000" _whq-request-input+ _whq-request-crlf
    _whq-request-crlf
    _whq-request-input-u @ _whq-request-body-start !
    [CHAR] b _WHQ-LARGE-BODY-U _whq-request-input-fill+
    _whq-request-input-u @ _whq-request-tail-start !
    S" TAIL" _whq-request-input+ ;

: _whq-request-lookup-contracts  ( -- )
    _whq-request WREQ-HEADER-COUNT@ 6 = _whq-assert

    S" X-Role" _whq-request WREQ-HEADER-LOOKUP
    _whq-assert
    2 = _whq-assert
    S" first" _whq-span= _whq-assert

    S" x-ROLE" _whq-request WREQ-HEADER-COUNT
    _whq-assert
    2 = _whq-assert

    S" X-Role" _whq-request WREQ-HEADER
    _whq-assert
    S" first" _whq-span= _whq-assert

    S" X-Empty" _whq-request WREQ-HEADER-LOOKUP
    _whq-assert
    1 = _whq-assert
    DUP 0= _whq-assert
    2DROP

    S" Missing" _whq-request WREQ-HEADER-LOOKUP
    _whq-assert
    0= _whq-assert
    OR 0= _whq-assert

    0 1 _whq-request WREQ-HEADER-LOOKUP
    0= _whq-assert
    2DROP DROP ;

: _whq-request-large-fragmented  ( -- )
    11 _whq-stage !
    _whq-build-large-request
    12 _whq-stage !
    _whq-request-init
    0 _whq-request-position !
    13 _whq-stage !
    BEGIN
        _whq-request-position @ _whq-request-body-start @ <
    WHILE
        _whq-request-body-start @ _whq-request-position @ -
        37 MIN _whq-request-feed-fragment
        _whq-request-position @ _whq-request-body-start @ < IF
            _whq-request-status @ WREQ-S-PENDING = _whq-assert
        ELSE
            _whq-request-status @ WREQ-S-HEADERS-READY = _whq-assert
        THEN
    REPEAT

    14 _whq-stage !
    _whq-request WREQ-HEADERS-READY? _whq-assert
    _whq-request-lookup-contracts
    15 _whq-stage !
    _whq-request WREQ-BODY-CONTINUE
        WREQ-S-PENDING = _whq-assert

    16 _whq-stage !
    BEGIN
        _whq-request-tail-start @ _whq-request-position @ -
        _WHQ-BODY-FRAGMENT-U >
    WHILE
        _WHQ-BODY-FRAGMENT-U _whq-request-feed-fragment
        _whq-request-status @ WREQ-S-PENDING = _whq-assert
    REPEAT

    17 _whq-stage !
    _whq-request-tail-start @ _whq-request-position @ -
    DUP _whq-request-expected-consumed !
    4 + _whq-request-feed-fragment
    _whq-request-consumed @ _whq-request-expected-consumed @ =
        _whq-assert
    _whq-request-status @ WREQ-S-DONE = _whq-assert
    _whq-request-position @ _whq-request-tail-start @ = _whq-assert
    _whq-request-input _whq-request-position @ + 4
        S" TAIL" _whq-span= _whq-assert
    _whq-request-body-seen @ _WHQ-LARGE-BODY-U = _whq-assert
    _whq-request WREQ-BODY-LENGTH@
        _WHQ-LARGE-BODY-U = _whq-assert
    _whq-request WREQ-DONE? _whq-assert
    18 _whq-stage !
    _whq-stack ;

: _whq-request-error-run  ( expected-status -- )
    _whq-request-expected-status !
    _whq-request-init
    _whq-request-input _whq-request-input-u @
        _whq-request WREQ-FEED
    _whq-request-status !
    DROP
    _whq-request-status @ _whq-request-expected-status @ =
        _whq-assert
    _whq-request WREQ-VALID? _whq-assert
    _whq-request WREQ-STATE@
        WREQ-STATE-STOPPED = _whq-assert ;

: _whq-request-strict-malformed  ( -- )
    21 _whq-stage !
    _whq-request-input-reset
    S" POST / HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    S" Content-Length: 1" _whq-request-input+ _whq-request-crlf
    S" content-length: 1" _whq-request-input+ _whq-request-crlf
    _whq-request-crlf
    WREQ-S-FRAMING _whq-request-error-run

    22 _whq-stage !
    _whq-request-input-reset
    S" GET / HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    S" Transfer-Encoding: chunked" _whq-request-input+
    _whq-request-crlf _whq-request-crlf
    WREQ-S-FRAMING _whq-request-error-run

    23 _whq-stage !
    _whq-request-input-reset
    S" GET / HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    S" Expect: 100-continue" _whq-request-input+
    _whq-request-crlf _whq-request-crlf
    WREQ-S-FRAMING _whq-request-error-run

    24 _whq-stage !
    _whq-request-input-reset
    S" GET / HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    S"  folded" _whq-request-input+ _whq-request-crlf
    _whq-request-crlf
    WREQ-S-MALFORMED _whq-request-error-run

    25 _whq-stage !
    _whq-request-input-reset
    S" GET / HTTP/1.1" _whq-request-input+ 10 _whq-request-input-c+
    WREQ-S-MALFORMED _whq-request-error-run

    26 _whq-stage !
    _whq-request-input-reset
    S" GET / HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    S" X-Control: " _whq-request-input+
    1 _whq-request-input-c+ _whq-request-crlf _whq-request-crlf
    WREQ-S-MALFORMED _whq-request-error-run

    27 _whq-stage !
    _whq-request-input-reset
    S" GET / HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" X-Test: value" _whq-request-input+ _whq-request-crlf
    _whq-request-crlf
    WREQ-S-MALFORMED _whq-request-error-run

    28 _whq-stage !
    _whq-request-input-reset
    S" GET / HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    S" host: example.test" _whq-request-input+ _whq-request-crlf
    _whq-request-crlf
    WREQ-S-FRAMING _whq-request-error-run

    29 _whq-stage !
    _whq-request-input-reset
    S" GET /%2f HTTP/1.1" _whq-request-input+ _whq-request-crlf
    S" Host: example.test" _whq-request-input+ _whq-request-crlf
    _whq-request-crlf
    WREQ-S-MALFORMED _whq-request-error-run
    30 _whq-stage !
    _whq-stack ;

\ ---------------------------------------------------------------------
\ Copied route configuration and stale-match clearing
\ ---------------------------------------------------------------------

CREATE _whq-router HROUTER-SIZE ALLOT
CREATE _whq-router-entries HROUTER-ENTRY-SIZE 2 * ALLOT
CREATE _whq-router-arena 128 ALLOT
CREATE _whq-route-match HROUTER-MATCH-SIZE ALLOT
CREATE _whq-route-method 8 ALLOT
CREATE _whq-route-path 16 ALLOT

: _whq-route-start  ( exchange operation context -- outcome )
    2DROP DROP HROUTE-OUTCOME-RESPONSE ;

: _whq-route-poll  ( exchange operation context -- outcome )
    2DROP DROP HROUTE-OUTCOME-RESPONSE ;

: _whq-route-cancel  ( exchange operation context -- outcome )
    2DROP DROP HROUTE-OUTCOME-CANCELLED ;

: _whq-route-cleanup  ( exchange operation context -- error )
    2DROP DROP 0 ;

: _whq-router-add
  ( method-a method-u path-a path-u context operation-u -- status )
    ['] _whq-route-start
    ['] _whq-route-poll
    ['] _whq-route-cancel
    ['] _whq-route-cleanup
    _whq-router HROUTER-ADD ;

: _whq-router-copied-and-cleared  ( -- )
    31 _whq-stage !
    S" GET" _whq-route-method SWAP MOVE
    S" /copied" _whq-route-path SWAP MOVE
    _whq-router-entries 2 _whq-router-arena 128 _whq-router
        HROUTER-INIT HROUTER-S-OK = _whq-assert
    311 _whq-stage !
    _whq-route-method 3 _whq-route-path 7 0x51 24
        _whq-router-add HROUTER-S-OK = _whq-assert
    312 _whq-stage !
    _whq-route-method 8 [CHAR] X FILL
    _whq-route-path 16 [CHAR] Y FILL
    S" POST" S" /other" 0x52 48
        _whq-router-add HROUTER-S-OK = _whq-assert
    313 _whq-stage !
    _whq-router HROUTER-SEAL HROUTER-S-OK = _whq-assert
    314 _whq-stage !
    _whq-router HROUTER-VALID? _whq-assert
    _whq-router HROUTER-ARENA-USED@ 20 = _whq-assert
    _whq-router HROUTER-MAX-OPERATION-SIZE@ 48 = _whq-assert

    32 _whq-stage !
    _whq-route-match HRMATCH-INIT HROUTER-S-OK = _whq-assert
    S" GET" S" /copied" _whq-route-match _whq-router
        HROUTER-MATCH HROUTER-S-OK = _whq-assert
    _whq-route-match HRMATCH-FOUND? _whq-assert
    _whq-route-match HRMATCH-METHOD
        S" GET" _whq-span= _whq-assert
    _whq-route-match HRMATCH-PATH
        S" /copied" _whq-span= _whq-assert
    _whq-route-match HRMATCH-HANDLER-CONTEXT@ 0x51 =
        _whq-assert
    _whq-route-match HRMATCH-OPERATION-SIZE@ 24 = _whq-assert
    _whq-route-match HRMATCH-METHOD DROP
        _whq-route-method <> _whq-assert
    _whq-route-match HRMATCH-PATH DROP
        _whq-route-path <> _whq-assert

    33 _whq-stage !
    S" GET" S" /missing" _whq-route-match _whq-router
        HROUTER-MATCH HROUTER-S-NOT-FOUND = _whq-assert
    _whq-route-match HRMATCH-VALID? _whq-assert
    _whq-route-match HRMATCH-STATE@
        HRMATCH-STATE-NOT-FOUND = _whq-assert
    _whq-route-match HRMATCH-HANDLER-CONTEXT@ 0= _whq-assert
    _whq-route-match HRMATCH-START-XT@ 0= _whq-assert
    _whq-route-match HRMATCH-METHOD OR 0= _whq-assert
    _whq-route-match HRMATCH-PATH OR 0= _whq-assert

    34 _whq-stage !
    S" POST" S" /other" _whq-route-match _whq-router
        HROUTER-MATCH HROUTER-S-OK = _whq-assert
    S" POST" S" relative" _whq-route-match _whq-router
        HROUTER-MATCH HROUTER-S-INVALID = _whq-assert
    _whq-route-match HRMATCH-VALID? _whq-assert
    _whq-route-match HRMATCH-STATE@
        HRMATCH-STATE-EMPTY = _whq-assert
    _whq-route-match HRMATCH-HANDLER-CONTEXT@ 0= _whq-assert

    35 _whq-stage !
    S" POST" S" /other" _whq-route-match _whq-router
        HROUTER-MATCH HROUTER-S-OK = _whq-assert
    0 0 S" /other" _whq-route-match _whq-router
        HROUTER-MATCH HROUTER-S-INVALID = _whq-assert
    _whq-route-match HRMATCH-STATE@
        HRMATCH-STATE-EMPTY = _whq-assert
    _whq-route-match HRMATCH-HANDLER-CONTEXT@ 0= _whq-assert

    36 _whq-stage !
    S" get" S" /copied" _whq-route-match _whq-router
        HROUTER-MATCH HROUTER-S-NOT-FOUND = _whq-assert
    37 _whq-stage !
    _whq-stack ;

\ ---------------------------------------------------------------------
\ Bounded response construction and cooperative sending
\ ---------------------------------------------------------------------

1024 CONSTANT _WHQ-RESPONSE-HEADER-CAPACITY
31 CONSTANT _WHQ-RESPONSE-SCRATCH-CAPACITY
4096 CONSTANT _WHQ-CAPTURE-CAPACITY

0 CONSTANT _WHQ-SEND-NORMAL
1 CONSTANT _WHQ-SEND-CANCEL-COMPLETE

0 CONSTANT _WHQ-SOURCE-NORMAL
1 CONSTANT _WHQ-SOURCE-SHORT
2 CONSTANT _WHQ-SOURCE-FAILED
3 CONSTANT _WHQ-SOURCE-ZERO
4 CONSTANT _WHQ-SOURCE-THROW
5 CONSTANT _WHQ-SOURCE-CANCEL

CREATE _whq-response-writer HTTP-RESPONSE-WRITER-SIZE ALLOT
CREATE _whq-response-header _WHQ-RESPONSE-HEADER-CAPACITY ALLOT
CREATE _whq-response-small-header 64 ALLOT
CREATE _whq-response-scratch _WHQ-RESPONSE-SCRATCH-CAPACITY ALLOT
CREATE _whq-response-port NET-IO-PORT-SIZE ALLOT
CREATE _whq-response-capture _WHQ-CAPTURE-CAPACITY ALLOT
CREATE _whq-response-body 128 ALLOT
CREATE _whq-response-control-value 2 ALLOT

VARIABLE _whq-capture-u
VARIABLE _whq-send-a
VARIABLE _whq-send-u
VARIABLE _whq-send-take
VARIABLE _whq-send-limit
VARIABLE _whq-send-zero-once
VARIABLE _whq-send-mode
VARIABLE _whq-send-calls
VARIABLE _whq-reentrant-cancel-status
VARIABLE _whq-reentrant-field-status
VARIABLE _whq-source-offset
VARIABLE _whq-source-a
VARIABLE _whq-source-u
VARIABLE _whq-source-mode
VARIABLE _whq-source-cancel-status
VARIABLE _whq-pump-status
VARIABLE _whq-pump-iterations
VARIABLE _whq-header-a
VARIABLE _whq-header-u
VARIABLE _whq-before-u
VARIABLE _whq-body-declared-u
VARIABLE _whq-failure-mode
VARIABLE _whq-failure-status

: _whq-capture-reset  ( -- )
    0 _whq-capture-u !
    0 _whq-send-calls !
    0 _whq-reentrant-cancel-status !
    0 _whq-reentrant-field-status !
    0 _whq-source-cancel-status !
    _whq-response-capture _WHQ-CAPTURE-CAPACITY 0 FILL ;

: _whq-capture+  ( source-a source-u -- )
    DUP IF
        2DUP
        _whq-response-capture _whq-capture-u @ + SWAP CMOVE
        DUP _whq-capture-u +!
    THEN
    2DROP ;

: _whq-response-send  ( buffer-a buffer-u context -- count io-status )
    DROP
    _whq-send-u !
    _whq-send-a !
    1 _whq-send-calls +!
    _whq-send-mode @ _WHQ-SEND-CANCEL-COMPLETE = IF
        _whq-response-writer HRESP-CANCEL
            _whq-reentrant-cancel-status !
        S" X-Late" S" no" _whq-response-writer
            HRESP-HEADER-FIELD _whq-reentrant-field-status !
        _whq-send-a @ _whq-send-u @ _whq-capture+
        _whq-send-u @ NIO-S-OK EXIT
    THEN
    _whq-send-zero-once @ IF
        0 _whq-send-zero-once !
        0 NIO-S-OK EXIT
    THEN
    _whq-send-limit @ DUP 0= IF
        DROP _whq-send-u @
    ELSE
        _whq-send-u @ MIN
    THEN
    DUP _whq-send-take !
    _whq-send-a @ SWAP _whq-capture+
    _whq-send-take @ NIO-S-OK ;

: _whq-response-source  ( offset scratch-a requested-u context -- count status )
    DROP
    _whq-source-u !
    _whq-source-a !
    _whq-source-offset !
    _whq-source-mode @ CASE
        _WHQ-SOURCE-SHORT OF
            0 HRESP-SOURCE-S-END EXIT
        ENDOF
        _WHQ-SOURCE-FAILED OF
            0 HRESP-SOURCE-S-FAILED EXIT
        ENDOF
        _WHQ-SOURCE-ZERO OF
            0 HRESP-SOURCE-S-OK EXIT
        ENDOF
        _WHQ-SOURCE-THROW OF
            -904 THROW
        ENDOF
        _WHQ-SOURCE-CANCEL OF
            _whq-response-writer HRESP-CANCEL
                _whq-source-cancel-status !
        ENDOF
    ENDCASE
    _whq-response-body _whq-source-offset @ +
    _whq-source-a @ _whq-source-u @ MOVE
    _whq-source-u @ HRESP-SOURCE-S-OK ;

: _whq-response-init  ( -- )
    _whq-capture-reset
    _WHQ-SEND-NORMAL _whq-send-mode !
    0 _whq-send-limit !
    0 _whq-send-zero-once !
    _WHQ-SOURCE-NORMAL _whq-source-mode !
    _whq-response-header _WHQ-RESPONSE-HEADER-CAPACITY
    _whq-response-scratch _WHQ-RESPONSE-SCRATCH-CAPACITY
    _whq-response-writer HRESP-INIT
        HRESP-S-OK = _whq-assert
    _whq-response-port NIO-INIT
    ['] _whq-response-send _whq-response-port NIO.SEND-XT ! ;

: _whq-response-build-body  ( body-u -- )
    _whq-body-declared-u !
    _whq-response-init
    200 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    S" application/octet-stream" _whq-response-writer
        HRESP-CONTENT-TYPE HRESP-S-OK = _whq-assert
    _whq-body-declared-u @ 0 ['] _whq-response-source
        _whq-response-writer HRESP-BODY-SOURCE
        HRESP-S-OK = _whq-assert
    _whq-response-writer HRESP-SEAL
        HRESP-S-OK = _whq-assert ;

: _whq-response-generic-fields  ( -- )
    _whq-response-init
    200 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    S" X-Test" S" alpha" _whq-response-writer
        HRESP-HEADER-FIELD HRESP-S-OK = _whq-assert
    S" X-Test" S" beta" _whq-response-writer
        HRESP-HEADER-FIELD HRESP-S-OK = _whq-assert
    S" X-Empty" 0 0 _whq-response-writer
        HRESP-HEADER-FIELD HRESP-S-OK = _whq-assert
    S" text/plain" _whq-response-writer HRESP-CONTENT-TYPE
        HRESP-S-OK = _whq-assert
    0 0 0 _whq-response-writer HRESP-BODY-SOURCE
        HRESP-S-OK = _whq-assert
    _whq-response-writer HRESP-SEAL
        HRESP-S-OK = _whq-assert
    _whq-response-writer HRESP-HEADER$
    _whq-header-u !
    _whq-header-a !
    _whq-header-a @ _whq-header-u @
        S" X-Test: alpha" _whq-contains? _whq-assert
    _whq-header-a @ _whq-header-u @
        S" X-Test: beta" _whq-contains? _whq-assert
    _whq-header-a @ _whq-header-u @
        S" X-Empty: " _whq-contains? _whq-assert
    _whq-header-a @ _whq-header-u @
        S" Content-Type: text/plain" _whq-contains? _whq-assert
    _whq-header-a @ _whq-header-u @
        S" Content-Length: 0" _whq-contains? _whq-assert
    _whq-header-a @ _whq-header-u @
        S" Connection: close" _whq-contains? _whq-assert
    _whq-header-u @ 4 >= _whq-assert
    _whq-header-a @ _whq-header-u @ + 4 -
    DUP C@ 13 = _whq-assert
    DUP 1+ C@ 10 = _whq-assert
    DUP 2 + C@ 13 = _whq-assert
    3 + C@ 10 = _whq-assert
    _whq-stack ;

: _whq-response-reserved-case  ( name-a name-u -- )
    _whq-response-init
    200 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    S" value" _whq-response-writer HRESP-HEADER-FIELD
        HRESP-S-INVALID = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-ERROR = _whq-assert
    _whq-response-writer HRESP-VALID? _whq-assert ;

: _whq-response-reserved-and-bounds  ( -- )
    S" content-length" _whq-response-reserved-case
    S" TRANSFER-ENCODING" _whq-response-reserved-case
    S" Connection" _whq-response-reserved-case
    S" Content-Type" _whq-response-reserved-case

    _whq-response-init
    200 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    S" Bad Name" S" value" _whq-response-writer
        HRESP-HEADER-FIELD HRESP-S-INVALID = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-ERROR = _whq-assert

    _whq-response-init
    10 _whq-response-control-value C!
    200 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    S" X-Bad" _whq-response-control-value 1 _whq-response-writer
        HRESP-HEADER-FIELD HRESP-S-INVALID = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-ERROR = _whq-assert

    _whq-response-init
    200 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    S" X-Alias" _whq-response-header 1 _whq-response-writer
        HRESP-HEADER-FIELD HRESP-S-INVALID = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-ERROR = _whq-assert

    _whq-response-small-header 23
    _whq-response-scratch _WHQ-RESPONSE-SCRATCH-CAPACITY
    _whq-response-writer HRESP-INIT
        HRESP-S-OK = _whq-assert
    200 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    S" X" S" v" _whq-response-writer HRESP-HEADER-FIELD
        HRESP-S-OK = _whq-assert
    _whq-response-writer HRESP.HEADER-U @ 23 = _whq-assert
    _whq-response-writer HRESP.HEADER-U @ _whq-before-u !
    S" Y" S" z" _whq-response-writer HRESP-HEADER-FIELD
        HRESP-S-CAPACITY = _whq-assert
    _whq-response-writer HRESP.HEADER-U @
        _whq-before-u @ = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-ERROR = _whq-assert
    _whq-stack ;

: _whq-response-partial-and-zero  ( -- )
    _whq-response-body 128 [CHAR] q FILL
    80 _whq-response-build-body
    7 _whq-send-limit !
    -1 _whq-send-zero-once !
    _whq-response-port _whq-response-writer HRESP-SEND-STEP
        HRESP-PUMP-IDLE = _whq-assert
    _whq-capture-u @ 0= _whq-assert
    0 _whq-pump-iterations !
    BEGIN
        _whq-response-writer HRESP.STATE @ HRESP-STATE-SENT <>
        _whq-pump-iterations @ 300 < AND
    WHILE
        _whq-response-port _whq-response-writer HRESP-SEND-STEP
            _whq-pump-status !
        _whq-pump-status @ HRESP-PUMP-PROGRESS =
        _whq-pump-status @ HRESP-PUMP-IDLE = OR
        _whq-pump-status @ HRESP-PUMP-DONE = OR
            _whq-assert
        1 _whq-pump-iterations +!
    REPEAT
    _whq-pump-iterations @ 300 < _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-SENT = _whq-assert
    _whq-response-writer HRESP.OUTCOME @
        HRESP-OUTCOME-SENT = _whq-assert
    _whq-response-writer HRESP-BODY-SENT@ 80 = _whq-assert
    _whq-response-writer HRESP-HEADER$
    _whq-header-u !
    _whq-header-a !
    _whq-capture-u @ _whq-header-u @ 80 + = _whq-assert
    _whq-response-capture _whq-header-u @
        _whq-header-a @ _whq-header-u @ _whq-span= _whq-assert
    _whq-response-capture _whq-header-u @ + 80
        _whq-response-body 80 _whq-span= _whq-assert
    _whq-stack ;

: _whq-response-source-failure  ( source-mode writer-status -- )
    _whq-failure-status !
    _whq-failure-mode !
    32 _whq-response-build-body
    _whq-failure-mode @ _whq-source-mode !
    _whq-response-port _whq-response-writer HRESP-SEND-STEP
        HRESP-PUMP-PROGRESS = _whq-assert
    _whq-response-port _whq-response-writer HRESP-SEND-STEP
        HRESP-PUMP-ERROR-AFTER-BYTES = _whq-assert
    _whq-response-writer HRESP.STATUS @
        _whq-failure-status @ = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-ERROR = _whq-assert
    _whq-response-writer HRESP.OUTCOME @
        HRESP-OUTCOME-FAILED-AFTER-BYTES = _whq-assert
    _whq-response-writer HRESP-VALID? _whq-assert ;

: _whq-response-source-failures  ( -- )
    _WHQ-SOURCE-SHORT HRESP-S-SOURCE-SHORT
        _whq-response-source-failure
    _WHQ-SOURCE-FAILED HRESP-S-SOURCE-FAILED
        _whq-response-source-failure
    _WHQ-SOURCE-ZERO HRESP-S-SOURCE-ZERO
        _whq-response-source-failure
    _WHQ-SOURCE-THROW HRESP-S-SOURCE-THREW
        _whq-response-source-failure
    _whq-stack ;

: _whq-response-source-deferred-cancel  ( -- )
    16 _whq-response-build-body
    _WHQ-SOURCE-CANCEL _whq-source-mode !
    _whq-response-port _whq-response-writer HRESP-SEND-STEP
        HRESP-PUMP-PROGRESS = _whq-assert
    _whq-response-port _whq-response-writer HRESP-SEND-STEP
        HRESP-PUMP-CANCELLED-AFTER-BYTES = _whq-assert
    _whq-source-cancel-status @
        HRESP-PUMP-CANCEL-PENDING = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-CANCELLED = _whq-assert
    _whq-response-writer HRESP.OUTCOME @
        HRESP-OUTCOME-CANCELLED-AFTER-BYTES = _whq-assert
    _whq-response-writer HRESP-BODY-SENT@ 0= _whq-assert
    _whq-stack ;

: _whq-response-completion-wins  ( -- )
    _whq-response-init
    204 _whq-response-writer HRESP-BEGIN
        HRESP-S-OK = _whq-assert
    0 0 0 _whq-response-writer HRESP-BODY-SOURCE
        HRESP-S-OK = _whq-assert
    _whq-response-writer HRESP-SEAL
        HRESP-S-OK = _whq-assert
    _WHQ-SEND-CANCEL-COMPLETE _whq-send-mode !
    _whq-response-port _whq-response-writer HRESP-SEND-STEP
        HRESP-PUMP-DONE = _whq-assert
    _whq-reentrant-cancel-status @
        HRESP-PUMP-CANCEL-PENDING = _whq-assert
    _whq-reentrant-field-status @ HRESP-S-STATE = _whq-assert
    _whq-response-writer HRESP.STATE @
        HRESP-STATE-SENT = _whq-assert
    _whq-response-writer HRESP.OUTCOME @
        HRESP-OUTCOME-SENT = _whq-assert
    _whq-response-writer HRESP.FLAGS @
        HRESP-F-CANCEL-REQUESTED AND 0= _whq-assert
    _whq-response-writer HRESP-CANCEL
        HRESP-PUMP-DONE = _whq-assert
    _whq-stack ;

\ ---------------------------------------------------------------------
\ Suite entry
\ ---------------------------------------------------------------------

: _WHQ-RUN  ( -- )
    0 _whq-fails !
    0 _whq-checks !
    DEPTH _whq-depth !
    1 _whq-stage !
    _whq-request-large-fragmented
    2 _whq-stage !
    _whq-request-strict-malformed
    3 _whq-stage !
    _whq-router-copied-and-cleared
    4 _whq-stage !
    _whq-response-generic-fields
    5 _whq-stage !
    _whq-response-reserved-and-bounds
    6 _whq-stage !
    _whq-response-partial-and-zero
    7 _whq-stage !
    _whq-response-source-failures
    8 _whq-stage !
    _whq-response-source-deferred-cancel
    9 _whq-stage !
    _whq-response-completion-wins
    10 _whq-stage !
    _whq-fails @ 0= IF
        ." WEB HTTP PRIMITIVES PASS" CR
    ELSE
        ." WEB HTTP PRIMITIVES FAIL " _whq-fails @ . CR
    THEN ;
