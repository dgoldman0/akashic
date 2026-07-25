\ =====================================================================
\ http-connection-owner.f - cooperative accepted HTTP connection owner
\ =====================================================================
\ One descriptor owns the state of one already-open accepted connection.
\ All storage and services are injected by its caller: request parser,
\ response writer, route match, sealed router, byte-stream port, receive
\ arena, route-operation arena, and configured Host authority.
\
\ The owner never accepts a socket, allocates memory, blocks, persists
\ state, or keeps module-global mutable state.  A call to HCONN-STEP makes
\ at most one transport action.  Receive, send, port poll, cancel, close
\ start, and close poll therefore remain distinct cooperative steps.
\
\ Route callbacks receive:
\
\   ( exchange operation handler-context -- outcome )
\
\ Exchange is the HCONN descriptor.  A handler uses HCONN-REQUEST@,
\ HCONN-RESPONSE@, HCONN-ROUTE-OPERATION, HCONN-BODY-ACCEPT, and
\ HCONN-BODY-DISCARD to inspect and configure its request.  A positive
\ Content-Length is not consumed until START explicitly accepts a sink or
\ explicitly selects discard.  The accepted sink contract is:
\
\   ( request body-context -- status )
\
\ It obtains the currently borrowed bytes through WREQ-BODY-SLICE and
\ returns zero only after consuming that complete slice.
\
\ START is entered once.  Once entered, CLEANUP is entered exactly once.
\ Cleanup is delayed until a response pull source can no longer reference
\ route-operation storage.  Keep-alive, pipelining, listener ownership, and
\ accept scheduling are intentionally outside this one-request owner.
\
\ Setup sequence:
\
\   header-a header-cap body-limit 0 0 request WREQ-INIT
\   response-header-a response-header-cap send-a send-cap response HRESP-INIT
\   request response match router port rx-a rx-cap operation-a operation-cap
\     authority-a authority-u connection HCONN-INIT
\   connection HCONN-START
\
\ Request and response must be pristine.  The router is already sealed and
\ the accepted port is already open.  HCONN-INIT installs its body bridge,
\ initializes the match, wipes RX and operation storage, and seals the exact
\ disjoint object geometry.  Authority bytes and all injected descriptors
\ stay stable through terminal cleanup.
\ =====================================================================

PROVIDED akashic-web-http-connection-owner

REQUIRE ../utils/memory-span.f
REQUIRE ../net/io-port.f
REQUIRE http-request-stream.f
REQUIRE http-router-owner.f
REQUIRE http-response-writer.f

\ ---------------------------------------------------------------------
\ Closed lifecycle and result domains
\ ---------------------------------------------------------------------

0  CONSTANT HCONN-STATE-READY
1  CONSTANT HCONN-STATE-READING-HEADERS
2  CONSTANT HCONN-STATE-ROUTE-START
3  CONSTANT HCONN-STATE-READING-BODY
4  CONSTANT HCONN-STATE-HANDLER-POLL
5  CONSTANT HCONN-STATE-WRITING-RESPONSE
6  CONSTANT HCONN-STATE-PORT-POLL
7  CONSTANT HCONN-STATE-CANCEL-ROUTE
8  CONSTANT HCONN-STATE-CANCEL-POLL
9  CONSTANT HCONN-STATE-CLEANUP
10 CONSTANT HCONN-STATE-CANCEL-PORT
11 CONSTANT HCONN-STATE-CLOSE-START
12 CONSTANT HCONN-STATE-CLOSING
13 CONSTANT HCONN-STATE-TERMINAL

0  CONSTANT HCONN-S-PENDING
1  CONSTANT HCONN-S-DONE
2  CONSTANT HCONN-S-INVALID
3  CONSTANT HCONN-S-STATE
4  CONSTANT HCONN-S-PARSE
5  CONSTANT HCONN-S-ROUTE
6  CONSTANT HCONN-S-HANDLER
7  CONSTANT HCONN-S-RESPONSE
8  CONSTANT HCONN-S-TRANSPORT
9  CONSTANT HCONN-S-CANCELLED
10 CONSTANT HCONN-S-CLEANUP
11 CONSTANT HCONN-S-CAPACITY

0 CONSTANT HCONN-BODY-UNDECIDED
1 CONSTANT HCONN-BODY-ACCEPTED
2 CONSTANT HCONN-BODY-DISCARDED

1   CONSTANT _HCONN-F-STARTED
2   CONSTANT _HCONN-F-CLEANED
4   CONSTANT _HCONN-F-CANCEL-REQUESTED
8   CONSTANT _HCONN-F-PORT-CANCELLED
16  CONSTANT _HCONN-F-CALLBACK-ACTIVE
32  CONSTANT _HCONN-F-SEND-AFTER-CLEANUP
64  CONSTANT _HCONN-F-CANCEL-ENTERED
127 CONSTANT _HCONN-FLAGS-MASK

\ A zero-body 431 response is the largest automatic response header emitted
\ here.  This is its exact required byte count, not an arena ceiling.
86 CONSTANT HCONN-AUTOMATIC-HEADER-REQUIRED

: _HCONN-STATE?  ( state -- flag )
    DUP HCONN-STATE-READY >=
    SWAP HCONN-STATE-TERMINAL <= AND ;

: _HCONN-STATUS?  ( status -- flag )
    DUP HCONN-S-PENDING >=
    SWAP HCONN-S-CAPACITY <= AND ;

: _HCONN-BODY-DECISION?  ( decision -- flag )
    DUP HCONN-BODY-UNDECIDED >=
    SWAP HCONN-BODY-DISCARDED <= AND ;

\ ---------------------------------------------------------------------
\ Sole current descriptor layout
\ ---------------------------------------------------------------------

 0 CELLS CONSTANT _HCONN-STATE-O
 1 CELLS CONSTANT _HCONN-STATUS-O
 2 CELLS CONSTANT _HCONN-RESULT-O
 3 CELLS CONSTANT _HCONN-FLAGS-O
 4 CELLS CONSTANT _HCONN-REQUEST-O
 5 CELLS CONSTANT _HCONN-RESPONSE-O
 6 CELLS CONSTANT _HCONN-MATCH-O
 7 CELLS CONSTANT _HCONN-ROUTER-O
 8 CELLS CONSTANT _HCONN-PORT-O
 9 CELLS CONSTANT _HCONN-RX-A-O
10 CELLS CONSTANT _HCONN-RX-CAPACITY-O
11 CELLS CONSTANT _HCONN-RX-OFFSET-O
12 CELLS CONSTANT _HCONN-RX-U-O
13 CELLS CONSTANT _HCONN-OPERATION-A-O
14 CELLS CONSTANT _HCONN-OPERATION-CAPACITY-O
15 CELLS CONSTANT _HCONN-AUTHORITY-A-O
16 CELLS CONSTANT _HCONN-AUTHORITY-U-O
17 CELLS CONSTANT _HCONN-BODY-XT-O
18 CELLS CONSTANT _HCONN-BODY-CONTEXT-O
19 CELLS CONSTANT _HCONN-BODY-DECISION-O
20 CELLS CONSTANT _HCONN-ROUTE-OUTCOME-O
21 CELLS CONSTANT _HCONN-CLEANUP-ERROR-O
22 CELLS CONSTANT _HCONN-TRANSPORT-STATUS-O
23 CELLS CONSTANT _HCONN-HTTP-STATUS-O
24 CELLS CONSTANT _HCONN-RESUME-STATE-O
25 CELLS CONSTANT _HCONN-CALL-XT-O
26 CELLS CONSTANT _HCONN-CALL-RESULT-O
27 CELLS CONSTANT _HCONN-CALL-ERROR-O
28 CELLS CONSTANT _HCONN-PATH-U-O
29 CELLS CONSTANT _HCONN-T0-O
30 CELLS CONSTANT _HCONN-T1-O
31 CELLS CONSTANT _HCONN-T2-O
32 CELLS CONSTANT _HCONN-T3-O
33 CELLS CONSTANT _HCONN-T4-O
34 CELLS CONSTANT _HCONN-T5-O
35 CELLS CONSTANT _HCONN-GEOMETRY-O

14 CONSTANT _HCONN-GEOMETRY-CAPACITY
_HCONN-GEOMETRY-CAPACITY MSPAN-SET-BYTES
_HCONN-GEOMETRY-O + CONSTANT HTTP-CONNECTION-OWNER-SIZE

: HCONN.STATE              ( connection -- a ) _HCONN-STATE-O + ;
: HCONN.STATUS             ( connection -- a ) _HCONN-STATUS-O + ;
: HCONN.RESULT             ( connection -- a ) _HCONN-RESULT-O + ;
: HCONN.FLAGS              ( connection -- a ) _HCONN-FLAGS-O + ;
: HCONN.REQUEST            ( connection -- a ) _HCONN-REQUEST-O + ;
: HCONN.RESPONSE           ( connection -- a ) _HCONN-RESPONSE-O + ;
: HCONN.MATCH              ( connection -- a ) _HCONN-MATCH-O + ;
: HCONN.ROUTER             ( connection -- a ) _HCONN-ROUTER-O + ;
: HCONN.PORT               ( connection -- a ) _HCONN-PORT-O + ;
: HCONN.RX-A               ( connection -- a ) _HCONN-RX-A-O + ;
: HCONN.RX-CAPACITY        ( connection -- a ) _HCONN-RX-CAPACITY-O + ;
: HCONN.RX-OFFSET          ( connection -- a ) _HCONN-RX-OFFSET-O + ;
: HCONN.RX-U               ( connection -- a ) _HCONN-RX-U-O + ;
: HCONN.OPERATION-A        ( connection -- a ) _HCONN-OPERATION-A-O + ;
: HCONN.OPERATION-CAPACITY ( connection -- a )
    _HCONN-OPERATION-CAPACITY-O + ;
: HCONN.AUTHORITY-A        ( connection -- a ) _HCONN-AUTHORITY-A-O + ;
: HCONN.AUTHORITY-U        ( connection -- a ) _HCONN-AUTHORITY-U-O + ;
: HCONN.BODY-XT            ( connection -- a ) _HCONN-BODY-XT-O + ;
: HCONN.BODY-CONTEXT       ( connection -- a ) _HCONN-BODY-CONTEXT-O + ;
: HCONN.BODY-DECISION      ( connection -- a ) _HCONN-BODY-DECISION-O + ;
: HCONN.ROUTE-OUTCOME      ( connection -- a ) _HCONN-ROUTE-OUTCOME-O + ;
: HCONN.CLEANUP-ERROR      ( connection -- a ) _HCONN-CLEANUP-ERROR-O + ;
: HCONN.TRANSPORT-STATUS   ( connection -- a )
    _HCONN-TRANSPORT-STATUS-O + ;
: HCONN.HTTP-STATUS        ( connection -- a ) _HCONN-HTTP-STATUS-O + ;
: HCONN.RESUME-STATE       ( connection -- a ) _HCONN-RESUME-STATE-O + ;
: _HCONN.CALL-XT           ( connection -- a ) _HCONN-CALL-XT-O + ;
: _HCONN.CALL-RESULT       ( connection -- a ) _HCONN-CALL-RESULT-O + ;
: _HCONN.CALL-ERROR        ( connection -- a ) _HCONN-CALL-ERROR-O + ;
: _HCONN.PATH-U            ( connection -- a ) _HCONN-PATH-U-O + ;
: _HCONN.T0                ( connection -- a ) _HCONN-T0-O + ;
: _HCONN.T1                ( connection -- a ) _HCONN-T1-O + ;
: _HCONN.T2                ( connection -- a ) _HCONN-T2-O + ;
: _HCONN.T3                ( connection -- a ) _HCONN-T3-O + ;
: _HCONN.T4                ( connection -- a ) _HCONN-T4-O + ;
: _HCONN.T5                ( connection -- a ) _HCONN-T5-O + ;
: _HCONN.GEOMETRY          ( connection -- set ) _HCONN-GEOMETRY-O + ;

\ ---------------------------------------------------------------------
\ Small grammar and flag helpers
\ ---------------------------------------------------------------------

: _HCONN-FLAG?  ( mask connection -- flag )
    HCONN.FLAGS @ AND 0<> ;

: _HCONN-FLAG+  ( mask connection -- )
    HCONN.FLAGS DUP @ ROT OR SWAP ! ;

: _HCONN-FLAG-  ( mask connection -- )
    HCONN.FLAGS DUP @ ROT INVERT AND SWAP ! ;

: _HCONN-LOWER  ( c -- c' )
    DUP [CHAR] A >= OVER [CHAR] Z <= AND IF 32 + THEN ;

: _HCONN-CIEQ?  ( a1 u1 a2 u2 -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP -1 EXIT THEN
    >R SWAP DROP R>
    0 ?DO
        OVER I + C@ _HCONN-LOWER
        OVER I + C@ _HCONN-LOWER
        <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

: _HCONN-DIGITS?  ( a u -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ DUP [CHAR] 0 < SWAP [CHAR] 9 > OR IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _HCONN-HEXDIG?  ( c -- flag )
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND
    OVER [CHAR] A >= 2 PICK [CHAR] F <= AND OR
    SWAP DUP [CHAR] a >= SWAP [CHAR] f <= AND OR ;

: _HCONN-HOST-CHAR?  ( c -- flag )
    DUP [CHAR] a >= OVER [CHAR] z <= AND
    OVER [CHAR] A >= 2 PICK [CHAR] Z <= AND OR
    OVER [CHAR] 0 >= 2 PICK [CHAR] 9 <= AND OR
    OVER [CHAR] - = OR OVER [CHAR] . = OR
    OVER [CHAR] _ = OR OVER [CHAR] ~ = OR
    OVER [CHAR] ! = OR OVER [CHAR] $ = OR
    OVER [CHAR] & = OR OVER [CHAR] ' = OR
    OVER [CHAR] ( = OR OVER [CHAR] ) = OR
    OVER [CHAR] * = OR OVER [CHAR] + = OR
    OVER [CHAR] , = OR OVER [CHAR] ; = OR
    SWAP [CHAR] = = OR ;

: _HCONN-IPV6?  ( inner-a inner-u connection -- flag )
    0 OVER _HCONN.T3 !
    0 OVER _HCONN.T4 !
    0 OVER _HCONN.T5 !
    1 PICK 0= IF 2DROP DROP 0 EXIT THEN
    1 PICK 0 ?DO
        2 PICK I + C@ DUP _HCONN-HEXDIG? IF
            DROP
            DUP _HCONN.T4 @ 4 >= IF
                2DROP DROP 0 UNLOOP EXIT
            THEN
            1 OVER _HCONN.T4 +!
        ELSE
            [CHAR] : <> IF
                2DROP DROP 0 UNLOOP EXIT
            THEN
            DUP _HCONN.T4 @ 0> IF
                1 OVER _HCONN.T3 +!
                0 OVER _HCONN.T4 !
                DUP _HCONN.T3 @ 8 > IF
                    2DROP DROP 0 UNLOOP EXIT
                THEN
            ELSE
                I 0= IF
                    1 PICK 2 < IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                    2 PICK 1+ C@ [CHAR] : <> IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                ELSE
                    2 PICK I + 1- C@ [CHAR] : <> IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                    DUP _HCONN.T5 @ IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                    -1 OVER _HCONN.T5 !
                THEN
            THEN
        THEN
    LOOP
    DUP _HCONN.T4 @ 0> IF
        1 OVER _HCONN.T3 +!
        0 OVER _HCONN.T4 !
    ELSE
        1 PICK 2 < IF 2DROP DROP 0 EXIT THEN
        2 PICK 2 PICK + 1- C@ [CHAR] : <> IF
            2DROP DROP 0 EXIT
        THEN
        2 PICK 2 PICK + 2 - C@ [CHAR] : <> IF
            2DROP DROP 0 EXIT
        THEN
    THEN
    DUP _HCONN.T5 @ IF
        DUP _HCONN.T3 @ 8 <
    ELSE
        DUP _HCONN.T3 @ 8 =
    THEN
    >R 2DROP DROP R> ;

: _HCONN-AUTHORITY?  ( authority-a authority-u connection -- flag )
    2 PICK OVER _HCONN.T0 !
    1 PICK OVER _HCONN.T1 !
    NIP NIP
    DUP _HCONN.T1 @ 0= IF DROP 0 EXIT THEN
    DUP _HCONN.T0 @ 0= IF DROP 0 EXIT THEN
    DUP _HCONN.T0 @ OVER _HCONN.T1 @
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _HCONN.T0 @ C@ [CHAR] [ = IF
        -1 OVER _HCONN.T2 !
        DUP _HCONN.T1 @ 1 ?DO
            DUP _HCONN.T0 @ I + C@ [CHAR] ] = IF
                DUP _HCONN.T2 @ 0>= IF
                    DROP 0 UNLOOP EXIT
                THEN
                I OVER _HCONN.T2 !
            THEN
        LOOP
        DUP _HCONN.T2 @ 1 <= IF DROP 0 EXIT THEN
        DUP _HCONN.T0 @ 1+
        OVER _HCONN.T2 @ 1-
        2 PICK _HCONN-IPV6? 0= IF DROP 0 EXIT THEN
        DUP _HCONN.T2 @ 1+
        OVER _HCONN.T1 @ = IF DROP -1 EXIT THEN
        DUP _HCONN.T2 @ 1+ OVER _HCONN.T1 @ >= IF
            DROP 0 EXIT
        THEN
        DUP _HCONN.T0 @ OVER _HCONN.T2 @ 1+ + C@
            [CHAR] : <> IF DROP 0 EXIT THEN
        DUP _HCONN.T0 @ OVER _HCONN.T2 @ 2 + +
        OVER _HCONN.T1 @ 2 PICK _HCONN.T2 @ - 2 -
        _HCONN-DIGITS? NIP EXIT
    THEN
    -1 OVER _HCONN.T2 !
    DUP _HCONN.T1 @ 0 ?DO
        DUP _HCONN.T0 @ I + C@
        DUP [CHAR] : = IF
            DROP
            DUP _HCONN.T2 @ 0>= IF DROP 0 UNLOOP EXIT THEN
            I OVER _HCONN.T2 !
        ELSE
            _HCONN-HOST-CHAR? 0= IF
                DROP 0 UNLOOP EXIT
            THEN
        THEN
    LOOP
    DUP _HCONN.T2 @ 0< IF DROP -1 EXIT THEN
    DUP _HCONN.T2 @ 0= IF DROP 0 EXIT THEN
    DUP _HCONN.T0 @ OVER _HCONN.T2 @ 1+ +
    OVER _HCONN.T1 @ 2 PICK _HCONN.T2 @ - 1-
    _HCONN-DIGITS? NIP ;

\ ---------------------------------------------------------------------
\ Contained request-body callback
\ ---------------------------------------------------------------------

: _HCONN-BODY-CALL-INNER  ( connection -- connection )
    DUP >R
    R@ HCONN.REQUEST @
    R@ HCONN.BODY-CONTEXT @
    R@ HCONN.BODY-XT @ EXECUTE
    R@ _HCONN.CALL-RESULT !
    R> DROP ;

: _HCONN-BODY-BRIDGE  ( request connection -- status )
    DUP 0= IF 2DROP -1 EXIT THEN
    >R
    R@ HCONN.REQUEST @ <> IF R> DROP -1 EXIT THEN
    R@ HCONN.STATE @ HCONN-STATE-READING-BODY <> IF
        R> DROP -1 EXIT
    THEN
    R@ HCONN.BODY-DECISION @ HCONN-BODY-ACCEPTED <> IF
        R> DROP -1 EXIT
    THEN
    R@ HCONN.BODY-XT @ 0= IF R> DROP -1 EXIT THEN
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG? IF
        R> DROP -1 EXIT
    THEN
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
    0 R@ _HCONN.CALL-RESULT !
    0 R@ _HCONN.CALL-ERROR !
    R@ ['] _HCONN-BODY-CALL-INNER CATCH ?DUP IF
        R@ _HCONN.CALL-ERROR !
        DROP
        _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
        R> DROP -1 EXIT
    THEN
    DROP
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
    R@ _HCONN.CALL-RESULT @
    R> DROP ;

\ ---------------------------------------------------------------------
\ Immutable resource-geometry seal
\ ---------------------------------------------------------------------

: _HCONN-GEOMETRY-ADD  ( a u connection -- flag )
    _HCONN.GEOMETRY MSPAN-SET-ADD MSPAN-SET-S-OK = ;

: _HCONN-GEOMETRY-SEAL  ( connection -- flag )
    >R
    _HCONN-GEOMETRY-CAPACITY R@ _HCONN.GEOMETRY
        MSPAN-SET-INIT MSPAN-SET-S-OK <> IF R> DROP 0 EXIT THEN
    R@ HTTP-CONNECTION-OWNER-SIZE R@ _HCONN-GEOMETRY-ADD
        0= IF R> DROP 0 EXIT THEN
    R@ HCONN.REQUEST @ WEB-HTTP-REQUEST-STREAM-SIZE
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.REQUEST @ WREQ.HEADER-A @
    R@ HCONN.REQUEST @ WREQ.HEADER-CAPACITY @
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ HTTP-RESPONSE-WRITER-SIZE
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ HRESP.HEADER-A @
    R@ HCONN.RESPONSE @ HRESP.HEADER-CAPACITY @
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ HRESP.SEND-A @
    R@ HCONN.RESPONSE @ HRESP.SEND-CAPACITY @
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.MATCH @ HROUTER-MATCH-SIZE
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.ROUTER @ HROUTER-SIZE
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.ROUTER @ HROUTER.ENTRIES @
    R@ HCONN.ROUTER @ HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.ROUTER @ HROUTER.ARENA-A @
    R@ HCONN.ROUTER @ HROUTER.ARENA-CAPACITY @
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ NET-IO-PORT-SIZE
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RX-A @ R@ HCONN.RX-CAPACITY @
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.OPERATION-A @ R@ HCONN.OPERATION-CAPACITY @
        R@ _HCONN-GEOMETRY-ADD 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.AUTHORITY-A @ R@ HCONN.AUTHORITY-U @
        R@ _HCONN-GEOMETRY-ADD
    R> DROP ;

: _HCONN-GEOMETRY-NTH  ( index connection -- entry )
    _HCONN.GEOMETRY _MSPAN-SET-NTH ;

: _HCONN-GEOMETRY=  ( a u index connection -- flag )
    >R
    R@ _HCONN-GEOMETRY-NTH
    DUP @ 3 PICK =
    SWAP 8 + @ 2 PICK = AND
    >R 2DROP R>
    R> DROP ;

: _HCONN-GEOMETRY-EXACT?  ( connection -- flag )
    >R
    R@ _HCONN.GEOMETRY MSPAN-SET-VALID? 0= IF R> DROP 0 EXIT THEN
    R@ _HCONN.GEOMETRY MSPAN-SET-COUNT@
        _HCONN-GEOMETRY-CAPACITY <> IF R> DROP 0 EXIT THEN
    R@ HTTP-CONNECTION-OWNER-SIZE 0 R@ _HCONN-GEOMETRY=
        0= IF R> DROP 0 EXIT THEN
    R@ HCONN.REQUEST @ WEB-HTTP-REQUEST-STREAM-SIZE
        1 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.REQUEST @ WREQ.HEADER-A @
    R@ HCONN.REQUEST @ WREQ.HEADER-CAPACITY @
        2 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ HTTP-RESPONSE-WRITER-SIZE
        3 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ HRESP.HEADER-A @
    R@ HCONN.RESPONSE @ HRESP.HEADER-CAPACITY @
        4 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ HRESP.SEND-A @
    R@ HCONN.RESPONSE @ HRESP.SEND-CAPACITY @
        5 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.MATCH @ HROUTER-MATCH-SIZE
        6 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.ROUTER @ HROUTER-SIZE
        7 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.ROUTER @ HROUTER.ENTRIES @
    R@ HCONN.ROUTER @ HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        8 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.ROUTER @ HROUTER.ARENA-A @
    R@ HCONN.ROUTER @ HROUTER.ARENA-CAPACITY @
        9 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ NET-IO-PORT-SIZE
        10 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RX-A @ R@ HCONN.RX-CAPACITY @
        11 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.OPERATION-A @ R@ HCONN.OPERATION-CAPACITY @
        12 R@ _HCONN-GEOMETRY= 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.AUTHORITY-A @ R@ HCONN.AUTHORITY-U @
        13 R@ _HCONN-GEOMETRY=
    R> DROP ;

\ ---------------------------------------------------------------------
\ Resource and dynamic validation
\ ---------------------------------------------------------------------

: _HCONN-PORT-SHAPE?  ( port -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP NET-IO-PORT-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP NIO.RECV-XT @ 0= IF DROP 0 EXIT THEN
    DUP NIO.SEND-XT @ 0= IF DROP 0 EXIT THEN
    DUP NIO.CANCEL-XT @ 0= IF DROP 0 EXIT THEN
    DUP NIO.CLOSE-START-XT @ IF
        DUP NIO.CLOSE-POLL-XT @ 0= IF DROP 0 EXIT THEN
    ELSE
        DUP NIO.CLOSE-POLL-XT @ IF DROP 0 EXIT THEN
        DUP NIO.CLOSE-XT @ 0= IF DROP 0 EXIT THEN
    THEN
    DUP NIO.OPEN-STATE @ DUP NIO-OPEN-STATE-CLOSED >=
        SWAP NIO-OPEN-STATE-CANCELLED <= AND 0= IF DROP 0 EXIT THEN
    NIO.CLOSE-STATE @ DUP NIO-CLOSE-STATE-IDLE >=
    SWAP NIO-CLOSE-STATE-CANCELLED <= AND ;

: _HCONN-REQUEST-PRISTINE?  ( request -- flag )
    DUP WREQ-VALID? 0= IF DROP 0 EXIT THEN
    DUP WREQ.STATE @ WREQ-STATE-REQUEST-LINE =
    OVER WREQ.STATUS @ WREQ-S-PENDING = AND
    OVER WREQ.HEADER-U @ 0= AND
    OVER WREQ.CONTENT-LENGTH @ 0= AND
    OVER WREQ.BODY-REMAINING @ 0= AND
    SWAP DROP ;

: _HCONN-RESPONSE-PRISTINE?  ( response -- flag )
    DUP HRESP-VALID? 0= IF DROP 0 EXIT THEN
    DUP HRESP.STATE @ HRESP-STATE-BUILDING =
    OVER HRESP.STATUS @ HRESP-S-OK = AND
    OVER HRESP.FLAGS @ 0= AND
    OVER HRESP.HEADER-U @ 0= AND
    OVER HRESP.HEADER-CAPACITY @
        HCONN-AUTOMATIC-HEADER-REQUIRED >= AND
    SWAP DROP ;

: _HCONN-RESOURCE-SHAPES?  ( connection -- flag )
    >R
    R@ HCONN.REQUEST @ _HCONN-REQUEST-PRISTINE?
        0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ _HCONN-RESPONSE-PRISTINE?
        0= IF R> DROP 0 EXIT THEN
    R@ HCONN.MATCH @ DUP 0= IF DROP R> DROP 0 EXIT THEN
    HROUTER-MATCH-SIZE MSPAN-NONWRAPPING? 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.ROUTER @ HROUTER-SEALED? 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ _HCONN-PORT-SHAPE? 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ NIO.OPEN-STATE @
        NIO-OPEN-STATE-OPEN <> IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ NIO.CLOSE-STATE @
        NIO-CLOSE-STATE-IDLE <> IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ NIO.CLEANUP-FLAGS @
        IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ NIO.CANCEL-ERROR @
        IF R> DROP 0 EXIT THEN
    R@ HCONN.PORT @ NIO.CLOSE-ERROR @
        IF R> DROP 0 EXIT THEN
    R@ HCONN.RX-CAPACITY @ 1 < IF R> DROP 0 EXIT THEN
    R@ HCONN.RX-A @ 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.RX-A @ R@ HCONN.RX-CAPACITY @
        MSPAN-NONWRAPPING? 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.OPERATION-CAPACITY @ 0< IF R> DROP 0 EXIT THEN
    R@ HCONN.OPERATION-CAPACITY @ 0= IF
        R@ HCONN.OPERATION-A @ IF R> DROP 0 EXIT THEN
    ELSE
        R@ HCONN.OPERATION-A @ 0= IF R> DROP 0 EXIT THEN
        R@ HCONN.OPERATION-A @ R@ HCONN.OPERATION-CAPACITY @
            MSPAN-NONWRAPPING? 0= IF R> DROP 0 EXIT THEN
    THEN
    R@ HCONN.AUTHORITY-A @ R@ HCONN.AUTHORITY-U @ R@
        _HCONN-AUTHORITY? 0= IF R> DROP 0 EXIT THEN
    R> DROP -1 ;

: _HCONN-RX-RANGE?  ( connection -- flag )
    >R
    R@ HCONN.RX-OFFSET @ DUP 0< IF DROP R> DROP 0 EXIT THEN
    R@ HCONN.RX-CAPACITY @ > IF R> DROP 0 EXIT THEN
    R@ HCONN.RX-U @ DUP 0< IF DROP R> DROP 0 EXIT THEN
    R@ HCONN.RX-CAPACITY @ R@ HCONN.RX-OFFSET @ - >
        IF R> DROP 0 EXIT THEN
    R> DROP -1 ;

: _HCONN-BODY-CONFIG?  ( connection -- flag )
    DUP HCONN.BODY-DECISION @ CASE
        HCONN-BODY-UNDECIDED OF
            DUP HCONN.BODY-XT @
            OVER HCONN.BODY-CONTEXT @ OR 0=
            SWAP DROP
        ENDOF
        HCONN-BODY-ACCEPTED OF
            DUP HCONN.BODY-XT @ 0<>
            SWAP DROP
        ENDOF
        HCONN-BODY-DISCARDED OF
            DUP HCONN.BODY-XT @
            OVER HCONN.BODY-CONTEXT @ OR 0=
            SWAP DROP
        ENDOF
        2DROP 0 0
    ENDCASE ;

: _HCONN-LIFECYCLE-FLAGS?  ( connection -- flag )
    >R
    _HCONN-F-CLEANED R@ _HCONN-FLAG? IF
        _HCONN-F-STARTED R@ _HCONN-FLAG? 0=
            IF R> DROP 0 EXIT THEN
    THEN
    _HCONN-F-CANCEL-ENTERED R@ _HCONN-FLAG? IF
        _HCONN-F-STARTED R@ _HCONN-FLAG? 0=
            IF R> DROP 0 EXIT THEN
    THEN
    _HCONN-F-STARTED R@ _HCONN-FLAG? IF
        R@ HCONN.MATCH @ HRMATCH-FOUND? 0=
            IF R> DROP 0 EXIT THEN
        R@ HCONN.MATCH @ HRMATCH.OPERATION-SIZE @
        R@ HCONN.OPERATION-CAPACITY @ >
            IF R> DROP 0 EXIT THEN
    THEN
    R> DROP -1 ;

: _HCONN-STATUS-STATE?  ( connection -- flag )
    DUP HCONN.STATE @ HCONN-STATE-TERMINAL = IF
        DUP HCONN.STATUS @ HCONN-S-PENDING <>
        OVER HCONN.STATUS @ 2 PICK HCONN.RESULT @ = AND
        SWAP DROP EXIT
    THEN
    DUP HCONN.STATUS @ HCONN-S-PENDING =
    SWAP HCONN.RESULT @ _HCONN-STATUS? AND ;

: HCONN-VALID?  ( connection -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP HTTP-CONNECTION-OWNER-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    DUP HCONN.STATE @ _HCONN-STATE? 0= IF DROP 0 EXIT THEN
    DUP HCONN.STATUS @ _HCONN-STATUS? 0= IF DROP 0 EXIT THEN
    DUP HCONN.RESULT @ _HCONN-STATUS? 0= IF DROP 0 EXIT THEN
    DUP HCONN.FLAGS @ _HCONN-FLAGS-MASK INVERT AND
        IF DROP 0 EXIT THEN
    DUP HCONN.ROUTE-OUTCOME @ HROUTE-OUTCOME?
        0= IF DROP 0 EXIT THEN
    DUP HCONN.TRANSPORT-STATUS @ DUP NIO-S-OK >=
        SWAP NIO-S-PENDING <= AND 0= IF DROP 0 EXIT THEN
    DUP HCONN.HTTP-STATUS @ DUP 0=
        SWAP DUP 200 >= SWAP 599 <= AND OR 0= IF DROP 0 EXIT THEN
    DUP HCONN.RESUME-STATE @ _HCONN-STATE? 0= IF DROP 0 EXIT THEN
    DUP _HCONN-GEOMETRY-EXACT? 0= IF DROP 0 EXIT THEN
    DUP HCONN.REQUEST @ WREQ-VALID? 0= IF DROP 0 EXIT THEN
    DUP HCONN.REQUEST @ WREQ.BODY-XT @
        ['] _HCONN-BODY-BRIDGE <> IF DROP 0 EXIT THEN
    DUP HCONN.REQUEST @ WREQ.CONTEXT @
        OVER <> IF DROP 0 EXIT THEN
    DUP HCONN.RESPONSE @ HRESP-VALID? 0= IF DROP 0 EXIT THEN
    DUP HCONN.MATCH @ HRMATCH-VALID? 0= IF DROP 0 EXIT THEN
    DUP HCONN.ROUTER @ HROUTER-SEALED? 0= IF DROP 0 EXIT THEN
    DUP HCONN.PORT @ _HCONN-PORT-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _HCONN-RX-RANGE? 0= IF DROP 0 EXIT THEN
    DUP HCONN.BODY-DECISION @ _HCONN-BODY-DECISION?
        0= IF DROP 0 EXIT THEN
    DUP _HCONN-BODY-CONFIG? 0= IF DROP 0 EXIT THEN
    DUP _HCONN-LIFECYCLE-FLAGS? 0= IF DROP 0 EXIT THEN
    _HCONN-STATUS-STATE? ;

: HCONN-SPAN-DISJOINT?  ( address length exchange -- flag )
    >R
    DUP IF OVER 0= IF 2DROP R> DROP 0 EXIT THEN THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ HCONN-VALID? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ _HCONN.GEOMETRY MSPAN-SET-OVERLAP? 0=
    R> DROP ;

\ ---------------------------------------------------------------------
\ Initialization and handler-facing inspection
\ ---------------------------------------------------------------------

: _HCONN-DROP-INIT
    ( request response match router port rx-a rx-capacity )
    ( operation-a operation-capacity authority-a authority-u -- )
    2DROP 2DROP 2DROP 2DROP 2DROP DROP ;

: HCONN-INIT
    ( request response match router port rx-a rx-capacity )
    ( operation-a operation-capacity authority-a authority-u )
    ( connection -- status )
    >R
    R@ 0= IF
        _HCONN-DROP-INIT R> DROP HCONN-S-INVALID EXIT
    THEN
    R@ HTTP-CONNECTION-OWNER-SIZE MSPAN-NONWRAPPING? 0= IF
        _HCONN-DROP-INIT R> DROP HCONN-S-INVALID EXIT
    THEN
    R@ HTTP-CONNECTION-OWNER-SIZE 0 FILL
    R@ HCONN.AUTHORITY-U !
    R@ HCONN.AUTHORITY-A !
    R@ HCONN.OPERATION-CAPACITY !
    R@ HCONN.OPERATION-A !
    R@ HCONN.RX-CAPACITY !
    R@ HCONN.RX-A !
    R@ HCONN.PORT !
    R@ HCONN.ROUTER !
    R@ HCONN.MATCH !
    R@ HCONN.RESPONSE !
    R@ HCONN.REQUEST !
    R@ _HCONN-RESOURCE-SHAPES? 0= IF
        R@ HTTP-CONNECTION-OWNER-SIZE 0 FILL
        R> DROP HCONN-S-INVALID EXIT
    THEN
    R@ _HCONN-GEOMETRY-SEAL 0= IF
        R@ HTTP-CONNECTION-OWNER-SIZE 0 FILL
        R> DROP HCONN-S-INVALID EXIT
    THEN
    R@ HCONN.MATCH @ HRMATCH-INIT HROUTER-S-OK <> IF
        R@ HTTP-CONNECTION-OWNER-SIZE 0 FILL
        R> DROP HCONN-S-INVALID EXIT
    THEN
    R@ HCONN.RX-A @ R@ HCONN.RX-CAPACITY @ 0 FILL
    R@ HCONN.OPERATION-CAPACITY @ IF
        R@ HCONN.OPERATION-A @
        R@ HCONN.OPERATION-CAPACITY @ 0 FILL
    THEN
    ['] _HCONN-BODY-BRIDGE R@ HCONN.REQUEST @ WREQ.BODY-XT !
    R@ R@ HCONN.REQUEST @ WREQ.CONTEXT !
    HCONN-STATE-READY R@ HCONN.STATE !
    HCONN-S-PENDING R@ HCONN.STATUS !
    HCONN-S-PENDING R@ HCONN.RESULT !
    HROUTE-OUTCOME-PENDING R@ HCONN.ROUTE-OUTCOME !
    NIO-S-OK R@ HCONN.TRANSPORT-STATUS !
    HCONN-STATE-READY R@ HCONN.RESUME-STATE !
    R@ HCONN-VALID? 0= IF
        HCONN-STATE-TERMINAL R@ HCONN.STATE !
        HCONN-S-INVALID R@ HCONN.STATUS !
        HCONN-S-INVALID R@ HCONN.RESULT !
        R> DROP HCONN-S-INVALID EXIT
    THEN
    R> DROP HCONN-S-PENDING ;

: HCONN-STATE@  ( connection -- state )
    DUP HCONN-VALID? 0= IF DROP HCONN-STATE-TERMINAL EXIT THEN
    HCONN.STATE @ ;

: HCONN-STATUS@  ( connection -- status )
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    HCONN.STATUS @ ;

: HCONN-RESULT@  ( connection -- status )
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    HCONN.RESULT @ ;

: HCONN-HTTP-STATUS@  ( connection -- status-code|0 )
    DUP HCONN-VALID? 0= IF DROP 0 EXIT THEN
    HCONN.HTTP-STATUS @ ;

: HCONN-CLEANUP-ERROR@  ( connection -- error )
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    HCONN.CLEANUP-ERROR @ ;

: HCONN-TRANSPORT-STATUS@  ( connection -- io-status )
    DUP HCONN-VALID? 0= IF DROP NIO-S-FAILED EXIT THEN
    HCONN.TRANSPORT-STATUS @ ;

: HCONN-ROUTE-OUTCOME@  ( connection -- outcome )
    DUP HCONN-VALID? 0= IF DROP HROUTE-OUTCOME-FAILED EXIT THEN
    HCONN.ROUTE-OUTCOME @ ;

: HCONN-REQUEST@  ( exchange -- request|0 )
    DUP HCONN-VALID? 0= IF DROP 0 EXIT THEN
    HCONN.REQUEST @ ;

: HCONN-RESPONSE@  ( exchange -- response|0 )
    DUP HCONN-VALID? 0= IF DROP 0 EXIT THEN
    HCONN.RESPONSE @ ;

: HCONN-MATCH@  ( exchange -- match|0 )
    DUP HCONN-VALID? 0= IF DROP 0 EXIT THEN
    HCONN.MATCH @ ;

: HCONN-ROUTE-OPERATION  ( exchange -- operation-a operation-u )
    DUP HCONN-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP HCONN.MATCH @ HRMATCH-FOUND? 0= IF DROP 0 0 EXIT THEN
    DUP HCONN.OPERATION-A @
    SWAP HCONN.MATCH @ HRMATCH.OPERATION-SIZE @ ;

: HCONN-OPERATION-ARENA  ( exchange -- operation-a operation-capacity )
    DUP HCONN-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP HCONN.OPERATION-A @
    SWAP HCONN.OPERATION-CAPACITY @ ;

: HCONN-BODY-DECISION@  ( exchange -- decision )
    DUP HCONN-VALID? 0= IF DROP HCONN-BODY-UNDECIDED EXIT THEN
    HCONN.BODY-DECISION @ ;

: HCONN-RX-REMAINING@  ( exchange -- bytes )
    DUP HCONN-VALID? 0= IF DROP 0 EXIT THEN
    HCONN.RX-U @ ;

: HCONN-TERMINAL?  ( connection -- flag )
    DUP HCONN-VALID? 0= IF DROP 0 EXIT THEN
    HCONN.STATE @ HCONN-STATE-TERMINAL = ;

: HCONN-BODY-ACCEPT  ( body-xt body-context exchange -- status )
    >R
    R@ HCONN-VALID? 0= IF 2DROP R> DROP HCONN-S-INVALID EXIT THEN
    R@ HCONN.STATE @ HCONN-STATE-ROUTE-START <>
    _HCONN-F-STARTED R@ _HCONN-FLAG? 0= OR
    R@ HCONN.BODY-DECISION @ HCONN-BODY-UNDECIDED <> OR IF
        2DROP R> DROP HCONN-S-STATE EXIT
    THEN
    OVER 0= IF 2DROP R> DROP HCONN-S-INVALID EXIT THEN
    R@ HCONN.BODY-CONTEXT !
    R@ HCONN.BODY-XT !
    HCONN-BODY-ACCEPTED R@ HCONN.BODY-DECISION !
    R> DROP HCONN-S-PENDING ;

: HCONN-BODY-DISCARD  ( exchange -- status )
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    DUP HCONN.STATE @ HCONN-STATE-ROUTE-START <>
    _HCONN-F-STARTED 2 PICK _HCONN-FLAG? 0= OR
    OVER HCONN.BODY-DECISION @ HCONN-BODY-UNDECIDED <> OR IF
        DROP HCONN-S-STATE EXIT
    THEN
    HCONN-BODY-DISCARDED SWAP HCONN.BODY-DECISION !
    HCONN-S-PENDING ;

\ ---------------------------------------------------------------------
\ Contained route calls and response preparation
\ ---------------------------------------------------------------------

: _HCONN-ROUTE-CALL-INNER  ( connection -- connection )
    DUP >R
    R@
    R@ HCONN.OPERATION-A @
    R@ HCONN.MATCH @ HRMATCH.HANDLER-CONTEXT @
    R@ _HCONN.CALL-XT @ EXECUTE
    R@ _HCONN.CALL-RESULT !
    R> DROP ;

: _HCONN-ROUTE-CALL  ( xt connection -- result completed? )
    >R
    R@ _HCONN.CALL-XT !
    0 R@ _HCONN.CALL-RESULT !
    0 R@ _HCONN.CALL-ERROR !
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG? IF
        R> DROP 0 0 EXIT
    THEN
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
    R@ ['] _HCONN-ROUTE-CALL-INNER CATCH ?DUP IF
        R@ _HCONN.CALL-ERROR !
        DROP
        _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
        R> DROP 0 0 EXIT
    THEN
    DROP
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
    R@ _HCONN.CALL-RESULT @
    R> DROP -1 ;

: _HCONN-RESET-RESPONSE  ( connection -- flag )
    DUP HCONN.RESPONSE @ HRESP-CANCEL DROP
    HCONN.RESPONSE @ HRESP-RESET HRESP-S-OK = ;

: _HCONN-PRIMARY-FAILURE?  ( connection -- flag )
    HCONN.RESULT @
    DUP HCONN-S-PENDING <>
    SWAP HCONN-S-DONE <> AND ;

: _HCONN-REMEMBER-FAILURE  ( result connection -- )
    DUP _HCONN-PRIMARY-FAILURE? IF
        2DROP
    ELSE
        HCONN.RESULT !
    THEN ;

: _HCONN-DECISIVE-TRANSPORT?  ( io-status -- flag )
    DUP NIO-S-EOF =
    OVER NIO-S-FAILED = OR
    SWAP NIO-S-CANCELLED = OR ;

: _HCONN-REMEMBER-TRANSPORT  ( io-status connection -- )
    >R
    R@ HCONN.TRANSPORT-STATUS @ _HCONN-DECISIVE-TRANSPORT? IF
        DROP
    ELSE
        R@ HCONN.TRANSPORT-STATUS !
    THEN
    R> DROP ;

: _HCONN-AUTOMATIC  ( http-status result connection -- flag )
    >R
    DUP R@ _HCONN-REMEMBER-FAILURE
    OVER R@ HCONN.HTTP-STATUS !
    2DROP
    R@ _HCONN-RESET-RESPONSE 0= IF R> DROP 0 EXIT THEN
    R@ HCONN.HTTP-STATUS @ R@ HCONN.RESPONSE @
        HRESP-BEGIN HRESP-S-OK <> IF R> DROP 0 EXIT THEN
    0 0 0 R@ HCONN.RESPONSE @
        HRESP-BODY-SOURCE HRESP-S-OK <> IF R> DROP 0 EXIT THEN
    R@ HCONN.RESPONSE @ HRESP-SEAL HRESP-S-OK <>
        IF R> DROP 0 EXIT THEN
    HCONN-STATE-WRITING-RESPONSE R@ HCONN.STATE !
    R> DROP -1 ;

: _HCONN-STARTED?  ( connection -- flag )
    _HCONN-F-STARTED SWAP _HCONN-FLAG? ;

: _HCONN-CLEANED?  ( connection -- flag )
    _HCONN-F-CLEANED SWAP _HCONN-FLAG? ;

: _HCONN-AUTOMATIC-FAILED  ( connection -- )
    >R
    R@ HCONN.RESPONSE @ HRESP-CANCEL DROP
    HCONN-S-RESPONSE R@ _HCONN-REMEMBER-FAILURE
    R@ _HCONN-STARTED? R@ _HCONN-CLEANED? 0= AND IF
        HCONN-STATE-CLEANUP
    ELSE
        HCONN-STATE-CLOSE-START
    THEN
    R@ HCONN.STATE !
    R> DROP ;

: _HCONN-ERROR-RESPONSE  ( http-status result connection -- )
    DUP >R _HCONN-AUTOMATIC 0= IF
        R@ _HCONN-AUTOMATIC-FAILED
    THEN
    R> DROP ;

\ Build an operation-independent error response, then cancel and clean the
\ active route before sending it.  This path is used when body delivery or a
\ handler response source fails while route resources may still be live.
: _HCONN-ACTIVE-ERROR-RESPONSE  ( http-status result connection -- )
    DUP >R _HCONN-AUTOMATIC IF
        _HCONN-F-SEND-AFTER-CLEANUP R@ _HCONN-FLAG+
    ELSE
        R@ _HCONN-AUTOMATIC-FAILED
    THEN
    R@ _HCONN-STARTED? R@ _HCONN-CLEANED? 0= AND IF
        HCONN-STATE-CANCEL-ROUTE R@ HCONN.STATE !
    THEN
    R> DROP ;

: _HCONN-REMEMBER-RESULT  ( result connection -- )
    DUP HCONN.RESULT @ HCONN-S-PENDING = IF
        HCONN.RESULT !
    ELSE
        2DROP
    THEN ;

: _HCONN-HANDLER-RESPONSE  ( connection -- )
    >R
    R@ HCONN.RESPONSE @ HRESP-VALID? 0= IF
        500 HCONN-S-HANDLER R@ _HCONN-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    R@ HCONN.RESPONSE @ HRESP.STATE @
        HRESP-STATE-SEALED <> IF
        500 HCONN-S-HANDLER R@ _HCONN-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    R@ HCONN.RESPONSE @ HRESP.HTTP-STATUS @
        R@ HCONN.HTTP-STATUS !
    HCONN-STATE-WRITING-RESPONSE R@ HCONN.STATE !
    R> DROP ;

\ ---------------------------------------------------------------------
\ Host and exact path-before-query route selection
\ ---------------------------------------------------------------------

: _HCONN-HOST-MATCH?  ( connection -- flag )
    >R
    S" Host" R@ HCONN.REQUEST @ WREQ-HEADER 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ HCONN.AUTHORITY-A @ R@ HCONN.AUTHORITY-U @
    _HCONN-CIEQ?
    R> DROP ;

: _HCONN-REQUEST-PATH  ( connection -- path-a path-u )
    DUP HCONN.REQUEST @ WREQ-TARGET
    DUP 3 PICK _HCONN.PATH-U !
    DUP 0 ?DO
        OVER I + C@ [CHAR] ? = IF
            I 3 PICK _HCONN.PATH-U !
            LEAVE
        THEN
    LOOP
    DROP
    OVER _HCONN.PATH-U @
    ROT DROP ;

: _HCONN-MATCH-ROUTE  ( connection -- status )
    >R
    R@ _HCONN-HOST-MATCH? 0= IF
        421 HCONN-S-ROUTE R@ _HCONN-ERROR-RESPONSE
        R> DROP HCONN-S-ROUTE EXIT
    THEN
    R@ HCONN.REQUEST @ WREQ-METHOD
    R@ _HCONN-REQUEST-PATH
    R@ HCONN.MATCH @ R@ HCONN.ROUTER @ HROUTER-MATCH
    DUP HROUTER-S-NOT-FOUND = IF
        DROP
        404 HCONN-S-ROUTE R@ _HCONN-ERROR-RESPONSE
        R> DROP HCONN-S-ROUTE EXIT
    THEN
    HROUTER-S-OK <> IF
        500 HCONN-S-ROUTE R@ _HCONN-ERROR-RESPONSE
        R> DROP HCONN-S-ROUTE EXIT
    THEN
    R@ HCONN.MATCH @ HRMATCH.OPERATION-SIZE @
    R@ HCONN.OPERATION-CAPACITY @ > IF
        503 HCONN-S-CAPACITY R@ _HCONN-ERROR-RESPONSE
        R> DROP HCONN-S-CAPACITY EXIT
    THEN
    HCONN-S-PENDING R> DROP ;

: _HCONN-ENABLE-BODY  ( connection -- request-status )
    >R
    R@ HCONN.REQUEST @ WREQ-CONTENT-LENGTH@ 0= IF
        R@ HCONN.REQUEST @ WREQ-BODY-DISCARD
        R> DROP EXIT
    THEN
    R@ HCONN.BODY-DECISION @ CASE
        HCONN-BODY-ACCEPTED OF
            R@ HCONN.REQUEST @ WREQ-BODY-CONTINUE
            R> DROP EXIT
        ENDOF
        HCONN-BODY-DISCARDED OF
            R@ HCONN.REQUEST @ WREQ-BODY-DISCARD
            R> DROP EXIT
        ENDOF
    ENDCASE
    R> DROP WREQ-S-CALLBACK ;

: _HCONN-AFTER-BODY  ( connection -- )
    DUP HCONN.ROUTE-OUTCOME @ CASE
        HROUTE-OUTCOME-PENDING OF
            HCONN-STATE-HANDLER-POLL SWAP HCONN.STATE !
        ENDOF
        HROUTE-OUTCOME-RESPONSE OF
            _HCONN-HANDLER-RESPONSE
        ENDOF
        HROUTE-OUTCOME-FAILED OF
            500 HCONN-S-HANDLER ROT _HCONN-ACTIVE-ERROR-RESPONSE
        ENDOF
        HROUTE-OUTCOME-CANCELLED OF
            HCONN-S-CANCELLED OVER HCONN.RESULT !
            DUP HCONN.RESPONSE @ HRESP-CANCEL DROP
            _HCONN-F-CANCEL-REQUESTED OVER _HCONN-FLAG+
            HCONN-STATE-CLEANUP SWAP HCONN.STATE !
        ENDOF
        DROP
    ENDCASE ;

: _HCONN-START-OUTCOME  ( outcome connection -- )
    >R
    DUP R@ HCONN.ROUTE-OUTCOME !
    DUP HROUTE-OUTCOME-FAILED = IF
        DROP
        500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    DUP HROUTE-OUTCOME-CANCELLED = IF
        DROP
        HCONN-S-CANCELLED R@ HCONN.RESULT !
        R@ HCONN.RESPONSE @ HRESP-CANCEL DROP
        _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG+
        HCONN-STATE-CLEANUP R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    DROP
    R@ _HCONN-ENABLE-BODY
    DUP WREQ-S-DONE = IF
        DROP R@ _HCONN-AFTER-BODY R> DROP EXIT
    THEN
    DUP WREQ-S-PENDING = IF
        DROP
        HCONN-STATE-READING-BODY R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    DROP
    500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
    R> DROP ;

: _HCONN-STEP-ROUTE-START  ( connection -- )
    >R
    R@ HCONN.MATCH @ HRMATCH-FOUND? 0= IF
        R@ _HCONN-MATCH-ROUTE HCONN-S-PENDING <> IF
            R> DROP EXIT
        THEN
    THEN
    _HCONN-F-STARTED R@ _HCONN-FLAG? IF
        500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    _HCONN-F-STARTED R@ _HCONN-FLAG+
    R@ HCONN.MATCH @ HRMATCH.START-XT @ R@ _HCONN-ROUTE-CALL
    0= IF
        DROP
        500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    DUP HROUTE-OUTCOME? 0= IF
        DROP
        500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    R@ _HCONN-START-OUTCOME
    R> DROP ;

: _HCONN-STEP-HANDLER-POLL  ( connection -- )
    >R
    R@ HCONN.MATCH @ HRMATCH.POLL-XT @ R@ _HCONN-ROUTE-CALL
    0= IF
        DROP
        500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    DUP HROUTE-OUTCOME? 0= IF
        DROP
        500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    DUP R@ HCONN.ROUTE-OUTCOME !
    CASE
        HROUTE-OUTCOME-PENDING OF ENDOF
        HROUTE-OUTCOME-RESPONSE OF
            R@ _HCONN-HANDLER-RESPONSE
        ENDOF
        HROUTE-OUTCOME-FAILED OF
            500 HCONN-S-HANDLER R@ _HCONN-ACTIVE-ERROR-RESPONSE
        ENDOF
        HROUTE-OUTCOME-CANCELLED OF
            HCONN-S-CANCELLED R@ HCONN.RESULT !
            R@ HCONN.RESPONSE @ HRESP-CANCEL DROP
            _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG+
            HCONN-STATE-CLEANUP R@ HCONN.STATE !
        ENDOF
    ENDCASE
    R> DROP ;

\ ---------------------------------------------------------------------
\ Incremental receive and parser driving
\ ---------------------------------------------------------------------

: _HCONN-PARSE-HTTP  ( request-status -- http-status )
    DUP WREQ-S-BODY-OVERFLOW = IF DROP 413 EXIT THEN
    DUP WREQ-S-CALLBACK = IF DROP 500 EXIT THEN
    DUP WREQ-S-REQUEST-LINE-OVERFLOW =
    OVER WREQ-S-HEADER-LINE-OVERFLOW = OR
    OVER WREQ-S-HEADER-OVERFLOW = OR
    OVER WREQ-S-HEADER-COUNT = OR IF
        DROP 431 EXIT
    THEN
    DROP 400 ;

: _HCONN-FEED-ERROR  ( request-status connection -- )
    >R
    DUP WREQ-S-CALLBACK =
        IF HCONN-S-HANDLER ELSE HCONN-S-PARSE THEN
    R@ _HCONN.T1 !
    _HCONN-PARSE-HTTP R@ _HCONN.T0 !
    R@ _HCONN-STARTED? R@ _HCONN-CLEANED? 0= AND IF
        R@ _HCONN.T0 @ R@ _HCONN.T1 @ R@
            _HCONN-ACTIVE-ERROR-RESPONSE
    ELSE
        R@ _HCONN.T0 @ R@ _HCONN.T1 @ R@
            _HCONN-ERROR-RESPONSE
    THEN
    R> DROP ;

: _HCONN-FEED-RX  ( connection -- )
    >R
    R@ HCONN.RX-A @ R@ HCONN.RX-OFFSET @ +
    R@ HCONN.RX-U @
    R@ HCONN.REQUEST @ WREQ-FEED
    R@ _HCONN.T0 !
    DUP R@ HCONN.RX-OFFSET +!
    DUP NEGATE R@ HCONN.RX-U +!
    DROP
    R@ HCONN.RX-U @ 0= IF 0 R@ HCONN.RX-OFFSET ! THEN
    R@ HCONN.STATE @ HCONN-STATE-READING-HEADERS = IF
        R@ _HCONN.T0 @ DUP WREQ-S-HEADERS-READY = IF
            DROP
            HCONN-STATE-ROUTE-START R@ HCONN.STATE !
            R> DROP EXIT
        THEN
        DUP WREQ-S-PENDING = IF
            DROP R> DROP EXIT
        THEN
        R@ _HCONN-FEED-ERROR
        R> DROP EXIT
    THEN
    R@ HCONN.STATE @ HCONN-STATE-READING-BODY = IF
        R@ _HCONN.T0 @ DUP WREQ-S-DONE = IF
            DROP R@ _HCONN-AFTER-BODY R> DROP EXIT
        THEN
        DUP WREQ-S-PENDING = IF
            DROP R> DROP EXIT
        THEN
        R@ _HCONN-FEED-ERROR
        R> DROP EXIT
    THEN
    R> DROP ;

: _HCONN-SCHEDULE-PORT-POLL  ( resume-state connection -- )
    >R
    R@ HCONN.RESUME-STATE !
    HCONN-STATE-PORT-POLL R@ HCONN.STATE !
    R> DROP ;

: _HCONN-BEGIN-CANCEL  ( connection -- )
    >R
    R@ HCONN.REQUEST @ WREQ-CANCEL DROP
    R@ HCONN.RESPONSE @ HRESP-CANCEL DROP
    R@ _HCONN-STARTED? R@ _HCONN-CLEANED? 0= AND IF
        HCONN-STATE-CANCEL-ROUTE
    ELSE
        HCONN-STATE-CANCEL-PORT
    THEN
    R@ HCONN.STATE !
    R> DROP ;

: _HCONN-RECV-EOF  ( connection -- )
    >R
    NIO-S-EOF R@ HCONN.TRANSPORT-STATUS !
    R@ HCONN.REQUEST @ WREQ-EOF DROP
    HCONN-S-PARSE R@ _HCONN-REMEMBER-RESULT
    R@ _HCONN-STARTED? R@ _HCONN-CLEANED? 0= AND IF
        R@ HCONN.RESPONSE @ HRESP-CANCEL DROP
        HCONN-STATE-CANCEL-ROUTE R@ HCONN.STATE !
    ELSE
        HCONN-STATE-CLOSE-START R@ HCONN.STATE !
    THEN
    R> DROP ;

: _HCONN-RECV-FAILED  ( io-status connection -- )
    >R
    DUP R@ _HCONN-REMEMBER-TRANSPORT
    DUP NIO-S-CANCELLED = IF
        HCONN-S-CANCELLED
    ELSE
        HCONN-S-TRANSPORT
    THEN
    R@ _HCONN-REMEMBER-FAILURE
    DROP
    _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG+
    R@ _HCONN-BEGIN-CANCEL
    R> DROP ;

: _HCONN-RECEIVE  ( connection -- )
    >R
    R@ HCONN.RX-OFFSET @ R@ HCONN.RX-U @ + R@ _HCONN.T0 !
    R@ HCONN.RX-CAPACITY @ R@ _HCONN.T0 @ - R@ _HCONN.T1 !
    R@ _HCONN.T1 @ 0= IF
        R@ HCONN.RX-OFFSET @ 0> R@ HCONN.RX-U @ 0> AND IF
            R@ HCONN.RX-A @ R@ HCONN.RX-OFFSET @ +
            R@ HCONN.RX-A @ R@ HCONN.RX-U @ CMOVE
            0 R@ HCONN.RX-OFFSET !
            R> DROP EXIT
        THEN
        431 HCONN-S-PARSE R@ _HCONN-ERROR-RESPONSE
        R> DROP EXIT
    THEN
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
    R@ HCONN.RX-A @ R@ _HCONN.T0 @ +
    R@ _HCONN.T1 @ R@ HCONN.PORT @ NIO-RECV
    R@ _HCONN.T2 !
    R@ _HCONN.T0 !
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
    R@ _HCONN.T2 @ DUP NIO-S-OK = IF
        DROP
        R@ _HCONN.T0 @ DUP 0= IF
            DROP
            R@ HCONN.STATE @ R@ _HCONN-SCHEDULE-PORT-POLL
            R> DROP EXIT
        THEN
        R@ HCONN.RX-U +!
        R> DROP EXIT
    THEN
    DUP NIO-S-EOF = IF
        DROP R@ _HCONN-RECV-EOF R> DROP EXIT
    THEN
    R@ _HCONN-RECV-FAILED
    R> DROP ;

: _HCONN-STEP-READ  ( connection -- )
    DUP HCONN.RX-U @ IF
        _HCONN-FEED-RX
    ELSE
        _HCONN-RECEIVE
    THEN ;

\ ---------------------------------------------------------------------
\ Response pump, cancellation, cleanup, and transport closure
\ ---------------------------------------------------------------------

: _HCONN-RESPONSE-FAILED  ( pump-status connection -- )
    >R
    DUP HRESP-PUMP-ERROR-BEFORE-BYTES =
    OVER HRESP-PUMP-ERROR-AFTER-BYTES = OR
    R@ HCONN.RESPONSE @ HRESP.STATUS @ HRESP-S-TRANSPORT = AND IF
        DROP
        NIO-S-FAILED R@ _HCONN-REMEMBER-TRANSPORT
        HCONN-S-TRANSPORT R@ _HCONN-REMEMBER-FAILURE
        _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG+
        R@ _HCONN-BEGIN-CANCEL
        R> DROP EXIT
    THEN
    DUP HRESP-PUMP-ERROR-BEFORE-BYTES = IF
        DROP
        R@ _HCONN-STARTED? R@ _HCONN-CLEANED? 0= AND IF
            500 HCONN-S-RESPONSE R@
                _HCONN-ACTIVE-ERROR-RESPONSE
        ELSE
            HCONN-S-RESPONSE R@ HCONN.RESULT !
            _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG+
            R@ _HCONN-BEGIN-CANCEL
        THEN
        R> DROP EXIT
    THEN
    DUP HRESP-PUMP-CANCELLED-BEFORE-BYTES =
    OVER HRESP-PUMP-CANCELLED-AFTER-BYTES = OR IF
        HCONN-S-CANCELLED
    ELSE
        HCONN-S-RESPONSE
    THEN
    R@ _HCONN-REMEMBER-FAILURE
    DROP
    _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG+
    R@ _HCONN-BEGIN-CANCEL
    R> DROP ;

: _HCONN-STEP-RESPONSE  ( connection -- )
    >R
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
    R@ HCONN.PORT @ R@ HCONN.RESPONSE @ HRESP-SEND-STEP
    R@ _HCONN.T0 !
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
    R@ _HCONN.T0 @ CASE
        HRESP-PUMP-IDLE OF
            HCONN-STATE-WRITING-RESPONSE R@
                _HCONN-SCHEDULE-PORT-POLL
        ENDOF
        HRESP-PUMP-PROGRESS OF ENDOF
        HRESP-PUMP-CANCEL-PENDING OF ENDOF
        HRESP-PUMP-DONE OF
            _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG-
            R@ HCONN.RESULT @ HCONN-S-CANCELLED = IF
                HCONN-S-DONE R@ HCONN.RESULT !
            ELSE
                HCONN-S-DONE R@ _HCONN-REMEMBER-RESULT
            THEN
            R@ _HCONN-STARTED? R@ _HCONN-CLEANED? 0= AND IF
                HCONN-STATE-CLEANUP
            ELSE
                HCONN-STATE-CLOSE-START
            THEN
            R@ HCONN.STATE !
        ENDOF
        HRESP-PUMP-ERROR-BEFORE-BYTES OF
            HRESP-PUMP-ERROR-BEFORE-BYTES R@
                _HCONN-RESPONSE-FAILED
        ENDOF
        HRESP-PUMP-ERROR-AFTER-BYTES OF
            HRESP-PUMP-ERROR-AFTER-BYTES R@
                _HCONN-RESPONSE-FAILED
        ENDOF
        HRESP-PUMP-CANCELLED-BEFORE-BYTES OF
            HRESP-PUMP-CANCELLED-BEFORE-BYTES R@
                _HCONN-RESPONSE-FAILED
        ENDOF
        HRESP-PUMP-CANCELLED-AFTER-BYTES OF
            HRESP-PUMP-CANCELLED-AFTER-BYTES R@
                _HCONN-RESPONSE-FAILED
        ENDOF
        HRESP-PUMP-INVALID OF
            HRESP-PUMP-INVALID R@ _HCONN-RESPONSE-FAILED
        ENDOF
    ENDCASE
    R> DROP ;

: _HCONN-CANCEL-OUTCOME  ( outcome connection -- )
    >R
    DUP HROUTE-OUTCOME? 0= IF
        DROP HCONN-STATE-CLEANUP R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    DUP R@ HCONN.ROUTE-OUTCOME !
    HROUTE-OUTCOME-PENDING = IF
        HCONN-STATE-CANCEL-POLL
    ELSE
        HCONN-STATE-CLEANUP
    THEN
    R@ HCONN.STATE !
    R> DROP ;

: _HCONN-STEP-CANCEL-ROUTE  ( connection -- )
    >R
    _HCONN-F-CANCEL-ENTERED R@ _HCONN-FLAG? IF
        HCONN-STATE-CANCEL-POLL R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    _HCONN-F-CANCEL-ENTERED R@ _HCONN-FLAG+
    R@ HCONN.MATCH @ HRMATCH.CANCEL-XT @ R@ _HCONN-ROUTE-CALL
    0= IF
        DROP HCONN-STATE-CLEANUP R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    R@ _HCONN-CANCEL-OUTCOME
    R> DROP ;

: _HCONN-STEP-CANCEL-POLL  ( connection -- )
    >R
    R@ HCONN.MATCH @ HRMATCH.POLL-XT @ R@ _HCONN-ROUTE-CALL
    0= IF
        DROP HCONN-STATE-CLEANUP R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    R@ _HCONN-CANCEL-OUTCOME
    R> DROP ;

: _HCONN-STEP-CLEANUP  ( connection -- )
    >R
    R@ _HCONN-CLEANED? IF
        HCONN-STATE-CANCEL-PORT R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    _HCONN-F-CLEANED R@ _HCONN-FLAG+
    R@ HCONN.MATCH @ HRMATCH.CLEANUP-XT @ R@ _HCONN-ROUTE-CALL
    0= IF
        DROP
        R@ _HCONN.CALL-ERROR @ DUP 0= IF DROP -1 THEN
        R@ HCONN.CLEANUP-ERROR !
        HCONN-S-CLEANUP R@ _HCONN-REMEMBER-FAILURE
    ELSE
        DUP R@ HCONN.CLEANUP-ERROR !
        IF HCONN-S-CLEANUP R@ _HCONN-REMEMBER-FAILURE THEN
    THEN
    R@ HCONN.OPERATION-CAPACITY @ IF
        R@ HCONN.OPERATION-A @
        R@ HCONN.OPERATION-CAPACITY @ 0 FILL
    THEN
    _HCONN-F-SEND-AFTER-CLEANUP R@ _HCONN-FLAG? IF
        _HCONN-F-SEND-AFTER-CLEANUP R@ _HCONN-FLAG-
        R@ HCONN.RESPONSE @ HRESP.STATE @ HRESP-STATE-SEALED = IF
            HCONN-STATE-WRITING-RESPONSE R@ HCONN.STATE !
            R> DROP EXIT
        THEN
    THEN
    _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG? IF
        HCONN-STATE-CANCEL-PORT
    ELSE
        HCONN-STATE-CLOSE-START
    THEN
    R@ HCONN.STATE !
    R> DROP ;

: _HCONN-STEP-PORT-POLL  ( connection -- )
    >R
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
    R@ HCONN.PORT @ NIO-POLL
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
    R@ HCONN.PORT @ NIO.OPEN-STATE @ DUP NIO-OPEN-STATE-OPEN = IF
        DROP
        R@ HCONN.RESUME-STATE @ R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    DUP NIO-OPEN-STATE-CANCELLED = IF
        NIO-S-CANCELLED R@ _HCONN-REMEMBER-TRANSPORT
        HCONN-S-CANCELLED
    ELSE
        NIO-S-FAILED R@ _HCONN-REMEMBER-TRANSPORT
        HCONN-S-TRANSPORT
    THEN
    R@ _HCONN-REMEMBER-FAILURE
    DROP
    _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG+
    R@ _HCONN-BEGIN-CANCEL
    R> DROP ;

: _HCONN-STEP-CANCEL-PORT  ( connection -- )
    >R
    _HCONN-F-PORT-CANCELLED R@ _HCONN-FLAG? 0= IF
        _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
        R@ HCONN.PORT @ NIO-CANCEL
        DUP R@ _HCONN-REMEMBER-TRANSPORT
        NIO-S-FAILED = IF
            HCONN-S-TRANSPORT R@ _HCONN-REMEMBER-FAILURE
        THEN
        _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
        _HCONN-F-PORT-CANCELLED R@ _HCONN-FLAG+
    THEN
    _HCONN-F-CANCEL-REQUESTED R@ _HCONN-FLAG-
    HCONN-STATE-CLOSE-START R@ HCONN.STATE !
    R> DROP ;

: _HCONN-TERMINAL  ( result connection -- )
    >R
    DUP R@ HCONN.RESULT !
    R@ HCONN.STATUS !
    HCONN-STATE-TERMINAL R@ HCONN.STATE !
    R> DROP ;

: _HCONN-CLOSE-RESULT  ( io-status connection -- )
    >R
    DUP R@ _HCONN-REMEMBER-TRANSPORT
    DUP NIO-S-PENDING = IF
        DROP HCONN-STATE-CLOSING R@ HCONN.STATE !
        R> DROP EXIT
    THEN
    DUP NIO-S-FAILED = IF
        DROP
        HCONN-S-TRANSPORT R@ _HCONN-REMEMBER-FAILURE
        R@ HCONN.RESULT @ R@ _HCONN-TERMINAL
        R> DROP EXIT
    THEN
    DUP NIO-S-CANCELLED = IF
        DROP
        HCONN-S-CANCELLED R@ _HCONN-REMEMBER-FAILURE
        R@ HCONN.RESULT @
        R@ _HCONN-TERMINAL
        R> DROP EXIT
    THEN
    DROP
    R@ HCONN.RESULT @ HCONN-S-PENDING =
        IF HCONN-S-DONE ELSE R@ HCONN.RESULT @ THEN
    R@ _HCONN-TERMINAL
    R> DROP ;

: _HCONN-STEP-CLOSE-START  ( connection -- )
    >R
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
    R@ HCONN.PORT @ NIO-CLOSE-START
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
    R@ _HCONN-CLOSE-RESULT
    R> DROP ;

: _HCONN-STEP-CLOSE-POLL  ( connection -- )
    >R
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG+
    R@ HCONN.PORT @ NIO-CLOSE-POLL
    _HCONN-F-CALLBACK-ACTIVE R@ _HCONN-FLAG-
    R@ _HCONN-CLOSE-RESULT
    R> DROP ;

\ ---------------------------------------------------------------------
\ Public lifecycle
\ ---------------------------------------------------------------------

: HCONN-START  ( connection -- status )
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    DUP HCONN.STATE @ HCONN-STATE-READY <> IF
        DROP HCONN-S-STATE EXIT
    THEN
    DUP HCONN.PORT @ NIO.OPEN-STATE @
    DUP NIO-OPEN-STATE-OPEN <> IF
        NIO-OPEN-STATE-CANCELLED = IF
            NIO-S-CANCELLED OVER HCONN.TRANSPORT-STATUS !
            HCONN-S-CANCELLED OVER HCONN.RESULT !
            HCONN-STATE-CLOSE-START SWAP HCONN.STATE !
            HCONN-S-CANCELLED EXIT
        THEN
        NIO-S-FAILED OVER HCONN.TRANSPORT-STATUS !
        HCONN-S-TRANSPORT OVER HCONN.RESULT !
        HCONN-STATE-CLOSE-START SWAP HCONN.STATE !
        HCONN-S-TRANSPORT EXIT
    THEN
    DROP
    HCONN-STATE-READING-HEADERS SWAP HCONN.STATE !
    HCONN-S-PENDING ;

: HCONN-CANCEL  ( connection -- status )
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    DUP HCONN.STATE @ HCONN-STATE-TERMINAL = IF
        HCONN.STATUS @ EXIT
    THEN
    _HCONN-F-CANCEL-REQUESTED OVER _HCONN-FLAG+
    HCONN-S-CANCELLED OVER _HCONN-REMEMBER-RESULT
    DROP HCONN-S-PENDING ;

: _HCONN-CANCEL-ALREADY-DRIVEN?  ( connection -- flag )
    HCONN.STATE @ CASE
        HCONN-STATE-CANCEL-ROUTE OF -1 ENDOF
        HCONN-STATE-CANCEL-POLL OF -1 ENDOF
        HCONN-STATE-CLEANUP OF -1 ENDOF
        HCONN-STATE-CANCEL-PORT OF -1 ENDOF
        HCONN-STATE-CLOSING OF -1 ENDOF
        HCONN-STATE-TERMINAL OF -1 ENDOF
        0 SWAP
    ENDCASE ;

: HCONN-STEP  ( connection -- status )
    DUP 0= IF DROP HCONN-S-INVALID EXIT THEN
    DUP HTTP-CONNECTION-OWNER-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP HCONN-S-INVALID EXIT
    THEN
    _HCONN-F-CALLBACK-ACTIVE OVER _HCONN-FLAG? IF
        DROP HCONN-S-STATE EXIT
    THEN
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    DUP HCONN.STATE @ HCONN-STATE-TERMINAL = IF
        HCONN.STATUS @ EXIT
    THEN
    _HCONN-F-CANCEL-REQUESTED OVER _HCONN-FLAG?
    OVER _HCONN-CANCEL-ALREADY-DRIVEN? 0= AND IF
        DUP _HCONN-BEGIN-CANCEL
        DROP HCONN-S-PENDING EXIT
    THEN
    DUP HCONN.STATE @ CASE
        HCONN-STATE-READY OF
            DROP HCONN-S-STATE EXIT
        ENDOF
        HCONN-STATE-READING-HEADERS OF
            DUP _HCONN-STEP-READ
        ENDOF
        HCONN-STATE-ROUTE-START OF
            DUP _HCONN-STEP-ROUTE-START
        ENDOF
        HCONN-STATE-READING-BODY OF
            DUP _HCONN-STEP-READ
        ENDOF
        HCONN-STATE-HANDLER-POLL OF
            DUP _HCONN-STEP-HANDLER-POLL
        ENDOF
        HCONN-STATE-WRITING-RESPONSE OF
            DUP _HCONN-STEP-RESPONSE
        ENDOF
        HCONN-STATE-PORT-POLL OF
            DUP _HCONN-STEP-PORT-POLL
        ENDOF
        HCONN-STATE-CANCEL-ROUTE OF
            DUP _HCONN-STEP-CANCEL-ROUTE
        ENDOF
        HCONN-STATE-CANCEL-POLL OF
            DUP _HCONN-STEP-CANCEL-POLL
        ENDOF
        HCONN-STATE-CLEANUP OF
            DUP _HCONN-STEP-CLEANUP
        ENDOF
        HCONN-STATE-CANCEL-PORT OF
            DUP _HCONN-STEP-CANCEL-PORT
        ENDOF
        HCONN-STATE-CLOSE-START OF
            DUP _HCONN-STEP-CLOSE-START
        ENDOF
        HCONN-STATE-CLOSING OF
            DUP _HCONN-STEP-CLOSE-POLL
        ENDOF
        DROP HCONN-S-INVALID EXIT
    ENDCASE
    DUP HCONN-VALID? 0= IF DROP HCONN-S-INVALID EXIT THEN
    DUP HCONN.STATE @ HCONN-STATE-TERMINAL = IF
        HCONN.STATUS @ EXIT
    THEN
    DROP HCONN-S-PENDING ;
