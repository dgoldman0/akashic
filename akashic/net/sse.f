\ =====================================================================
\  sse.f - Bounded incremental Server-Sent Events parser
\ =====================================================================
\  This module implements the event-stream grammar and dispatch rules. It
\  owns no socket, HTTP request, provider, Agent, or TUI state. Feed callbacks
\  receive borrowed slices that remain valid until the next parser call.
\ =====================================================================

PROVIDED akashic-sse-parser

0 CONSTANT SSE-STATE-OPEN
1 CONSTANT SSE-STATE-EOF
2 CONSTANT SSE-STATE-STOPPED

0 CONSTANT SSE-S-OK
1 CONSTANT SSE-S-LINE-OVERFLOW
2 CONSTANT SSE-S-DATA-OVERFLOW
3 CONSTANT SSE-S-EVENT-OVERFLOW
4 CONSTANT SSE-S-ID-OVERFLOW
5 CONSTANT SSE-S-CALLBACK
6 CONSTANT SSE-S-CANCELLED
7 CONSTANT SSE-S-CLOSED

65542 CONSTANT SSE-LINE-CAPACITY
128   CONSTANT SSE-EVENT-CAPACITY
65536 CONSTANT SSE-DATA-CAPACITY
256   CONSTANT SSE-ID-CAPACITY

 0 CONSTANT _SSE-STATE
 8 CONSTANT _SSE-STATUS
16 CONSTANT _SSE-BOM-STATE
24 CONSTANT _SSE-PENDING-CR
32 CONSTANT _SSE-LINE-U
40 CONSTANT _SSE-EVENT-U
48 CONSTANT _SSE-DATA-U
56 CONSTANT _SSE-ID-U
64 CONSTANT _SSE-RETRY
72 CONSTANT _SSE-DISPATCH-XT       \ ( parser context -- status )
80 CONSTANT _SSE-CONTEXT
88 CONSTANT _SSE-EVENTS
96 CONSTANT _SSE-LINE-BUF
_SSE-LINE-BUF SSE-LINE-CAPACITY + CONSTANT _SSE-EVENT-BUF
_SSE-EVENT-BUF SSE-EVENT-CAPACITY + CONSTANT _SSE-DATA-BUF
_SSE-DATA-BUF SSE-DATA-CAPACITY + CONSTANT _SSE-ID-BUF
_SSE-ID-BUF SSE-ID-CAPACITY + CONSTANT SSE-PARSER-SIZE

: SSE.STATE       ( parser -- a ) _SSE-STATE + ;
: SSE.STATUS      ( parser -- a ) _SSE-STATUS + ;
: SSE.BOM-STATE   ( parser -- a ) _SSE-BOM-STATE + ;
: SSE.PENDING-CR  ( parser -- a ) _SSE-PENDING-CR + ;
: SSE.LINE-U      ( parser -- a ) _SSE-LINE-U + ;
: SSE.EVENT-U     ( parser -- a ) _SSE-EVENT-U + ;
: SSE.DATA-U      ( parser -- a ) _SSE-DATA-U + ;
: SSE.ID-U        ( parser -- a ) _SSE-ID-U + ;
: SSE.RETRY       ( parser -- a ) _SSE-RETRY + ;
: SSE.DISPATCH-XT ( parser -- a ) _SSE-DISPATCH-XT + ;
: SSE.CONTEXT     ( parser -- a ) _SSE-CONTEXT + ;
: SSE.EVENTS      ( parser -- a ) _SSE-EVENTS + ;
: SSE.LINE-BUF    ( parser -- a ) _SSE-LINE-BUF + ;
: SSE.EVENT-BUF   ( parser -- a ) _SSE-EVENT-BUF + ;
: SSE.DATA-BUF    ( parser -- a ) _SSE-DATA-BUF + ;
: SSE.ID-BUF      ( parser -- a ) _SSE-ID-BUF + ;

: SSE-INIT  ( parser -- )
    DUP SSE-PARSER-SIZE 0 FILL
    -1 SWAP SSE.RETRY ! ;

: SSE-NEW  ( -- parser ior )
    SSE-PARSER-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP SSE-INIT 0 ;

: SSE-FREE  ( parser -- )
    ?DUP IF DUP SSE-PARSER-SIZE 0 FILL FREE THEN ;

VARIABLE _SSERS-P
VARIABLE _SSERS-XT
VARIABLE _SSERS-CONTEXT

: SSE-RESET  ( parser -- )
    DUP SSE.DISPATCH-XT @ _SSERS-XT !
    DUP SSE.CONTEXT @ _SSERS-CONTEXT !
    DUP _SSERS-P ! SSE-INIT
    _SSERS-XT @ _SSERS-P @ SSE.DISPATCH-XT !
    _SSERS-CONTEXT @ _SSERS-P @ SSE.CONTEXT ! ;

: SSE-ON-EVENT!  ( xt context parser -- )
    >R R@ SSE.CONTEXT ! R> SSE.DISPATCH-XT ! ;

: SSE-EVENT  ( parser -- addr len )
    DUP SSE.EVENT-U @ DUP IF
        >R SSE.EVENT-BUF R>
    ELSE
        2DROP S" message"
    THEN ;

: SSE-DATA  ( parser -- addr len )
    DUP SSE.DATA-BUF SWAP SSE.DATA-U @ ;

: SSE-LAST-ID  ( parser -- addr len )
    DUP SSE.ID-BUF SWAP SSE.ID-U @ ;

VARIABLE _SSEFAIL-P

: _SSE-FAIL  ( status parser -- )
    _SSEFAIL-P !
    _SSEFAIL-P @ SSE.STATUS @ 0= IF
        _SSEFAIL-P @ SSE.STATUS !
    ELSE
        DROP
    THEN
    SSE-STATE-STOPPED _SSEFAIL-P @ SSE.STATE ! ;

: _SSE-CONTAINS-NUL?  ( addr len -- flag )
    0 ?DO
        DUP I + C@ 0= IF DROP -1 UNLOOP EXIT THEN
    LOOP
    DROP 0 ;

VARIABLE _SSER-A
VARIABLE _SSER-U
VARIABLE _SSER-ACC
VARIABLE _SSER-OK

: _SSE-RETRY!  ( addr len parser -- )
    >R _SSER-U ! _SSER-A !
    _SSER-U @ 0= IF R> DROP EXIT THEN
    0 _SSER-ACC ! -1 _SSER-OK !
    _SSER-U @ 0 ?DO
        _SSER-OK @ IF
            _SSER-A @ I + C@ DUP 48 < SWAP 57 > OR IF
                0 _SSER-OK !
            ELSE
                _SSER-ACC @ 214748364 > IF
                    0 _SSER-OK !
                ELSE
                    _SSER-ACC @ 10 * _SSER-A @ I + C@ 48 - +
                    DUP 2147483647 > IF
                        DROP 0 _SSER-OK !
                    ELSE
                        _SSER-ACC !
                    THEN
                THEN
            THEN
        THEN
    LOOP
    _SSER-OK @ IF _SSER-ACC @ R@ SSE.RETRY ! THEN
    R> DROP ;

VARIABLE _SSEFL-P
VARIABLE _SSEFL-FA
VARIABLE _SSEFL-FU
VARIABLE _SSEFL-VA
VARIABLE _SSEFL-VU
VARIABLE _SSEFL-COLON

: _SSE-DATA+  ( addr len parser -- )
    _SSEFL-P ! _SSEFL-VU ! _SSEFL-VA !
    _SSEFL-P @ SSE.DATA-U @ _SSEFL-VU @ + 1+
    SSE-DATA-CAPACITY > IF
        SSE-S-DATA-OVERFLOW _SSEFL-P @ _SSE-FAIL EXIT
    THEN
    _SSEFL-VA @ _SSEFL-P @ SSE.DATA-BUF
    _SSEFL-P @ SSE.DATA-U @ + _SSEFL-VU @ CMOVE
    10 _SSEFL-P @ SSE.DATA-BUF _SSEFL-P @ SSE.DATA-U @ +
    _SSEFL-VU @ + C!
    _SSEFL-VU @ 1+ _SSEFL-P @ SSE.DATA-U +! ;

: _SSE-EVENT!  ( addr len parser -- )
    _SSEFL-P ! _SSEFL-VU ! _SSEFL-VA !
    _SSEFL-VU @ SSE-EVENT-CAPACITY > IF
        SSE-S-EVENT-OVERFLOW _SSEFL-P @ _SSE-FAIL EXIT
    THEN
    _SSEFL-P @ SSE.EVENT-BUF SSE-EVENT-CAPACITY 0 FILL
    _SSEFL-VA @ _SSEFL-P @ SSE.EVENT-BUF _SSEFL-VU @ CMOVE
    _SSEFL-VU @ _SSEFL-P @ SSE.EVENT-U ! ;

: _SSE-ID!  ( addr len parser -- )
    _SSEFL-P ! _SSEFL-VU ! _SSEFL-VA !
    _SSEFL-VA @ _SSEFL-VU @ _SSE-CONTAINS-NUL? IF EXIT THEN
    _SSEFL-VU @ SSE-ID-CAPACITY > IF
        SSE-S-ID-OVERFLOW _SSEFL-P @ _SSE-FAIL EXIT
    THEN
    _SSEFL-P @ SSE.ID-BUF SSE-ID-CAPACITY 0 FILL
    _SSEFL-VA @ _SSEFL-P @ SSE.ID-BUF _SSEFL-VU @ CMOVE
    _SSEFL-VU @ _SSEFL-P @ SSE.ID-U ! ;

VARIABLE _SSED-P
VARIABLE _SSED-STATUS
VARIABLE _SSED-XT

: _SSE-DISPATCH-INNER  ( -- )
    _SSED-P @ _SSED-P @ SSE.CONTEXT @ _SSED-XT @ EXECUTE
    _SSED-STATUS ! ;

: _SSE-DISPATCH  ( parser -- )
    _SSED-P !
    _SSED-P @ SSE.DATA-U @ 0= IF
        0 _SSED-P @ SSE.DATA-U !
        0 _SSED-P @ SSE.EVENT-U ! EXIT
    THEN
    -1 _SSED-P @ SSE.DATA-U +!
    0 _SSED-STATUS !
    _SSED-P @ SSE.DISPATCH-XT @ ?DUP IF
        _SSED-XT !
        ['] _SSE-DISPATCH-INNER CATCH IF 1 _SSED-STATUS ! THEN
    THEN
    _SSED-STATUS @ IF
        SSE-S-CALLBACK _SSED-P @ _SSE-FAIL
    ELSE
        1 _SSED-P @ SSE.EVENTS +!
    THEN
    0 _SSED-P @ SSE.DATA-U !
    0 _SSED-P @ SSE.EVENT-U ! ;

: _SSE-PROCESS-FIELD  ( parser -- )
    _SSEFL-P !
    _SSEFL-FA @ _SSEFL-FU @ S" event" COMPARE 0= IF
        _SSEFL-VA @ _SSEFL-VU @ _SSEFL-P @ _SSE-EVENT! EXIT
    THEN
    _SSEFL-FA @ _SSEFL-FU @ S" data" COMPARE 0= IF
        _SSEFL-VA @ _SSEFL-VU @ _SSEFL-P @ _SSE-DATA+ EXIT
    THEN
    _SSEFL-FA @ _SSEFL-FU @ S" id" COMPARE 0= IF
        _SSEFL-VA @ _SSEFL-VU @ _SSEFL-P @ _SSE-ID! EXIT
    THEN
    _SSEFL-FA @ _SSEFL-FU @ S" retry" COMPARE 0= IF
        _SSEFL-VA @ _SSEFL-VU @ _SSEFL-P @ _SSE-RETRY!
    THEN ;

VARIABLE _SSEL-P
VARIABLE _SSEL-U

: _SSE-PROCESS-LINE  ( parser -- )
    DUP _SSEL-P ! SSE.LINE-U @ DUP _SSEL-U !
    DUP 0= IF DROP _SSEL-P @ _SSE-DISPATCH EXIT THEN
    DROP
    _SSEL-P @ SSE.LINE-BUF C@ 58 = IF EXIT THEN
    -1 _SSEFL-COLON !
    _SSEL-U @ 0 ?DO
        _SSEFL-COLON @ 0< IF
            _SSEL-P @ SSE.LINE-BUF I + C@ 58 = IF I _SSEFL-COLON ! THEN
        THEN
    LOOP
    _SSEL-P @ SSE.LINE-BUF _SSEFL-FA !
    _SSEFL-COLON @ 0< IF
        _SSEL-U @ _SSEFL-FU !
        _SSEL-P @ SSE.LINE-BUF _SSEL-U @ + _SSEFL-VA !
        0 _SSEFL-VU !
    ELSE
        _SSEFL-COLON @ _SSEFL-FU !
        _SSEL-P @ SSE.LINE-BUF _SSEFL-COLON @ 1+ + _SSEFL-VA !
        _SSEL-U @ _SSEFL-COLON @ 1+ - _SSEFL-VU !
        _SSEFL-VU @ 0> IF
            _SSEFL-VA @ C@ 32 = IF
                1 _SSEFL-VA +! -1 _SSEFL-VU +!
            THEN
        THEN
    THEN
    _SSEL-P @ _SSE-PROCESS-FIELD ;

VARIABLE _SSEB-P
VARIABLE _SSEB-C

: _SSE-LINE-BYTE  ( c parser -- )
    _SSEB-P ! _SSEB-C !
    _SSEB-P @ SSE.LINE-U @ SSE-LINE-CAPACITY >= IF
        SSE-S-LINE-OVERFLOW _SSEB-P @ _SSE-FAIL EXIT
    THEN
    _SSEB-C @ _SSEB-P @ SSE.LINE-BUF _SSEB-P @ SSE.LINE-U @ + C!
    1 _SSEB-P @ SSE.LINE-U +! ;

: _SSE-END-LINE  ( parser -- )
    DUP _SSE-PROCESS-LINE 0 SWAP SSE.LINE-U ! ;

: _SSE-RAW-BYTE  ( c parser -- )
    _SSEB-P ! _SSEB-C !
    _SSEB-P @ SSE.PENDING-CR @ IF
        0 _SSEB-P @ SSE.PENDING-CR !
        _SSEB-C @ 10 = IF EXIT THEN
    THEN
    _SSEB-C @ 13 = IF
        _SSEB-P @ _SSE-END-LINE
        1 _SSEB-P @ SSE.PENDING-CR ! EXIT
    THEN
    _SSEB-C @ 10 = IF _SSEB-P @ _SSE-END-LINE EXIT THEN
    _SSEB-C @ _SSEB-P @ _SSE-LINE-BYTE ;

: _SSE-BYTE  ( c parser -- )
    _SSEB-P ! _SSEB-C !
    _SSEB-P @ SSE.BOM-STATE @
    DUP 0= IF
        DROP _SSEB-C @ 239 = IF
            1 _SSEB-P @ SSE.BOM-STATE ! EXIT
        THEN
        3 _SSEB-P @ SSE.BOM-STATE !
        _SSEB-C @ _SSEB-P @ _SSE-RAW-BYTE EXIT
    THEN
    DUP 1 = IF
        DROP _SSEB-C @ 187 = IF
            2 _SSEB-P @ SSE.BOM-STATE ! EXIT
        THEN
        3 _SSEB-P @ SSE.BOM-STATE !
        239 _SSEB-P @ _SSE-RAW-BYTE
        _SSEB-C @ _SSEB-P @ _SSE-RAW-BYTE EXIT
    THEN
    2 = IF
        _SSEB-C @ 191 = IF
            3 _SSEB-P @ SSE.BOM-STATE ! EXIT
        THEN
        3 _SSEB-P @ SSE.BOM-STATE !
        239 _SSEB-P @ _SSE-RAW-BYTE
        187 _SSEB-P @ _SSE-RAW-BYTE
        _SSEB-C @ _SSEB-P @ _SSE-RAW-BYTE EXIT
    THEN
    _SSEB-C @ _SSEB-P @ _SSE-RAW-BYTE ;

VARIABLE _SSEF-A
VARIABLE _SSEF-U
VARIABLE _SSEF-P

: SSE-FEED  ( addr len parser -- status )
    _SSEF-P ! _SSEF-U ! _SSEF-A !
    _SSEF-P @ SSE.STATE @ SSE-STATE-OPEN <> IF SSE-S-CLOSED EXIT THEN
    _SSEF-P @ SSE.STATUS @ IF _SSEF-P @ SSE.STATUS @ EXIT THEN
    _SSEF-U @ 0 ?DO
        _SSEF-P @ SSE.STATUS @ 0= IF
            _SSEF-A @ I + C@ _SSEF-P @ _SSE-BYTE
        THEN
    LOOP
    _SSEF-P @ SSE.STATUS @ ;

: SSE-EOF  ( parser -- status )
    DUP SSE.STATE @ SSE-STATE-OPEN <> IF SSE.STATUS @ EXIT THEN
    DUP SSE.BOM-STATE @ 1 = IF 239 OVER _SSE-RAW-BYTE THEN
    DUP SSE.BOM-STATE @ 2 = IF
        239 OVER _SSE-RAW-BYTE 187 OVER _SSE-RAW-BYTE
    THEN
    3 OVER SSE.BOM-STATE !
    0 OVER SSE.PENDING-CR !
    0 OVER SSE.LINE-U !
    0 OVER SSE.DATA-U !
    0 OVER SSE.EVENT-U !
    SSE-STATE-EOF OVER SSE.STATE !
    SSE.STATUS @ ;

: SSE-CANCEL  ( parser -- )
    DUP SSE.STATE @ SSE-STATE-OPEN = IF
        SSE-S-CANCELLED OVER SSE.STATUS !
        SSE-STATE-STOPPED SWAP SSE.STATE !
    ELSE
        DROP
    THEN ;

\ Persistent stream state is parser-owned, so cooperative owners may switch
\ between parsers between calls. Parsing scratch is shared and public calls are
\ not preemptively reentrant; a future threaded runtime must serialize them.
