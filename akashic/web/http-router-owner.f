\ =====================================================================
\  http-router-owner.f - caller-owned exact HTTP route configuration
\ =====================================================================
\  The router descriptor, fixed entry array, and route-string arena belong to
\  the caller.  Registration copies each validated method and path into that
\  arena before publishing the entry, so no route depends on borrowed setup
\  storage.  Method comparison is exact and case-sensitive.  Sealing makes
\  the configuration read-only; matching then reads only it and writes only
\  a caller-owned match descriptor, so connections share no current-request
\  state.
\
\  Paths are the absolute-path part of an origin-form request target.  They
\  begin with "/" and exclude both the query delimiter and fragment
\  delimiter.  A server splits any query from the parsed request target
\  before exact lookup.
\
\  Cooperative handler callback contracts:
\
\    START    ( exchange operation handler-context -- outcome )
\    POLL     ( exchange operation handler-context -- outcome )
\    CANCEL   ( exchange operation handler-context -- outcome )
\    CLEANUP  ( exchange operation handler-context -- error )
\
\  The exchange is an opaque caller-owned per-connection descriptor.
\  Operation points to at least the matched route's declared operation
\  bytes; it may be zero when that declaration is zero.  START is entered
\  once.  PENDING is subsequently driven with POLL.  CANCEL begins
\  cancellation and may itself return PENDING, after which POLL continues
\  driving the operation.
\
\  Once START has been entered, the executor must call CLEANUP exactly once
\  after every terminal outcome, callback throw, or invalid outcome.  It
\  records cleanup failure separately and never retries CLEANUP.  Handler
\  operation storage and request/response bodies are separate resources;
\  route operation size is not a payload limit.
\
\  A found match borrows the selected route's router-owned strings, handler
\  context, and callbacks.  Keep its descriptor stable until that operation
\  is cleaned up, and do not outlive or reinitialize the sealed router.
\ =====================================================================

PROVIDED akashic-web-http-router-owner

REQUIRE ../utils/memory-span.f

\ ---------------------------------------------------------------------
\ Closed status, state, and cooperative outcome domains
\ ---------------------------------------------------------------------

0 CONSTANT HROUTER-S-OK
1 CONSTANT HROUTER-S-INVALID
2 CONSTANT HROUTER-S-STATE
3 CONSTANT HROUTER-S-FULL
4 CONSTANT HROUTER-S-DUPLICATE
5 CONSTANT HROUTER-S-NOT-FOUND

1 CONSTANT HROUTER-STATE-BUILDING
2 CONSTANT HROUTER-STATE-SEALED

0 CONSTANT HROUTE-OUTCOME-PENDING
1 CONSTANT HROUTE-OUTCOME-RESPONSE
2 CONSTANT HROUTE-OUTCOME-FAILED
3 CONSTANT HROUTE-OUTCOME-CANCELLED

: HROUTE-OUTCOME?  ( outcome -- flag )
    DUP HROUTE-OUTCOME-PENDING >=
    SWAP HROUTE-OUTCOME-CANCELLED <= AND ;

: _HROUTER-OPERATION-SIZE?  ( bytes -- flag )
    0>= ;

\ ---------------------------------------------------------------------
\ Caller-owned route entry array
\ ---------------------------------------------------------------------

 0 CONSTANT _HROUTE-METHOD-A
 8 CONSTANT _HROUTE-METHOD-U
16 CONSTANT _HROUTE-PATH-A
24 CONSTANT _HROUTE-PATH-U
32 CONSTANT _HROUTE-HANDLER-CONTEXT
40 CONSTANT _HROUTE-OPERATION-SIZE
48 CONSTANT _HROUTE-START-XT
56 CONSTANT _HROUTE-POLL-XT
64 CONSTANT _HROUTE-CANCEL-XT
72 CONSTANT _HROUTE-CLEANUP-XT
80 CONSTANT HROUTER-ENTRY-SIZE

: HROUTE.METHOD-A          ( entry -- a ) _HROUTE-METHOD-A + ;
: HROUTE.METHOD-U          ( entry -- a ) _HROUTE-METHOD-U + ;
: HROUTE.PATH-A            ( entry -- a ) _HROUTE-PATH-A + ;
: HROUTE.PATH-U            ( entry -- a ) _HROUTE-PATH-U + ;
: HROUTE.HANDLER-CONTEXT   ( entry -- a ) _HROUTE-HANDLER-CONTEXT + ;
: HROUTE.OPERATION-SIZE    ( entry -- a ) _HROUTE-OPERATION-SIZE + ;
: HROUTE.START-XT          ( entry -- a ) _HROUTE-START-XT + ;
: HROUTE.POLL-XT           ( entry -- a ) _HROUTE-POLL-XT + ;
: HROUTE.CANCEL-XT         ( entry -- a ) _HROUTE-CANCEL-XT + ;
: HROUTE.CLEANUP-XT        ( entry -- a ) _HROUTE-CLEANUP-XT + ;

-1 1 RSHIFT HROUTER-ENTRY-SIZE / CONSTANT _HROUTER-CAPACITY-MAX

: HROUTER-ENTRY-BYTES  ( capacity -- bytes|0 )
    DUP 1 < IF DROP 0 EXIT THEN
    DUP _HROUTER-CAPACITY-MAX U> IF DROP 0 EXIT THEN
    HROUTER-ENTRY-SIZE * ;

\ ---------------------------------------------------------------------
\ Caller-owned router descriptor
\ ---------------------------------------------------------------------

 0 CONSTANT _HROUTER-STATE-O
 8 CONSTANT _HROUTER-ENTRIES-O
16 CONSTANT _HROUTER-ENTRY-CAPACITY-O
24 CONSTANT _HROUTER-COUNT-O
32 CONSTANT _HROUTER-ARENA-A-O
40 CONSTANT _HROUTER-ARENA-CAPACITY-O
48 CONSTANT _HROUTER-ARENA-U-O
56 CONSTANT _HROUTER-MAX-OPERATION-SIZE-O
64 CONSTANT HROUTER-SIZE

: HROUTER.STATE              ( router -- a ) _HROUTER-STATE-O + ;
: HROUTER.ENTRIES            ( router -- a ) _HROUTER-ENTRIES-O + ;
: HROUTER.ENTRY-CAPACITY     ( router -- a ) _HROUTER-ENTRY-CAPACITY-O + ;
: HROUTER.COUNT              ( router -- a ) _HROUTER-COUNT-O + ;
: HROUTER.ARENA-A            ( router -- a ) _HROUTER-ARENA-A-O + ;
: HROUTER.ARENA-CAPACITY     ( router -- a ) _HROUTER-ARENA-CAPACITY-O + ;
: HROUTER.ARENA-U            ( router -- a ) _HROUTER-ARENA-U-O + ;
: HROUTER.MAX-OPERATION-SIZE ( router -- a )
    _HROUTER-MAX-OPERATION-SIZE-O + ;

: HROUTER-COUNT@  ( router -- count ) HROUTER.COUNT @ ;

: HROUTER-STATE@  ( router -- state ) HROUTER.STATE @ ;

: HROUTER-ENTRY-CAPACITY@  ( router -- capacity )
    HROUTER.ENTRY-CAPACITY @ ;

: HROUTER-MAX-OPERATION-SIZE@  ( router -- bytes )
    HROUTER.MAX-OPERATION-SIZE @ ;

: HROUTER-ARENA-CAPACITY@  ( router -- bytes )
    HROUTER.ARENA-CAPACITY @ ;

: HROUTER-ARENA-USED@  ( router -- bytes )
    HROUTER.ARENA-U @ ;

: _HROUTER-ENTRY  ( index router -- entry )
    HROUTER.ENTRIES @ SWAP HROUTER-ENTRY-SIZE * + ;

\ ---------------------------------------------------------------------
\ Span, grammar, and entry validation
\ ---------------------------------------------------------------------

: _HROUTER-SPAN=  ( a1 u1 a2 u2 -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP -1 EXIT THEN
    >R SWAP DROP R>
    0 ?DO
        OVER I + C@ OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _HROUTER-TCHAR?  ( c -- flag )
    DUP 33 < IF DROP 0 EXIT THEN
    DUP 126 > IF DROP 0 EXIT THEN
    DUP 34 = OVER 40 = OR OVER 41 = OR OVER 44 = OR
    OVER 47 = OR OVER 58 = OR OVER 59 = OR OVER 60 = OR
    OVER 61 = OR OVER 62 = OR OVER 63 = OR OVER 64 = OR
    OVER 91 = OR OVER 92 = OR OVER 93 = OR OVER 123 = OR
    OVER 125 = OR IF DROP 0 ELSE DROP -1 THEN ;

: _HROUTER-NONEMPTY-SPAN?  ( address length -- flag )
    DUP 1 < IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _HROUTER-METHOD?  ( method-a method-u -- flag )
    2DUP _HROUTER-NONEMPTY-SPAN? 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ _HROUTER-TCHAR? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _HROUTER-UPPER-HEX?  ( c -- flag )
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND
    SWAP DUP [CHAR] A >= SWAP [CHAR] F <= AND OR ;

: _HROUTER-HEX-VALUE  ( c -- u )
    DUP [CHAR] 9 <= IF [CHAR] 0 - EXIT THEN
    [CHAR] A - 10 + ;

: _HROUTER-UNRESERVED?  ( c -- flag )
    DUP [CHAR] a >= OVER [CHAR] z <= AND
    OVER [CHAR] A >= 2 PICK [CHAR] Z <= AND OR
    OVER [CHAR] 0 >= 2 PICK [CHAR] 9 <= AND OR
    OVER [CHAR] - = OR OVER [CHAR] . = OR
    OVER [CHAR] _ = OR SWAP [CHAR] ~ = OR ;

: _HROUTER-PCT?  ( percent-a remaining -- flag )
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER 1+ C@ _HROUTER-UPPER-HEX? 0= IF 2DROP 0 EXIT THEN
    OVER 2 + C@ _HROUTER-UPPER-HEX? 0= IF 2DROP 0 EXIT THEN
    OVER 1+ C@ _HROUTER-HEX-VALUE 16 *
    2 PICK 2 + C@ _HROUTER-HEX-VALUE +
    DUP 32 < OVER 127 = OR
    OVER _HROUTER-UNRESERVED? OR
    OVER [CHAR] / = OR OVER [CHAR] \ = OR
    OVER [CHAR] ? = OR OVER [CHAR] # = OR
    SWAP [CHAR] % = OR
    >R 2DROP R> 0= ;

: _HROUTER-PATH?  ( path-a path-u -- flag )
    2DUP _HROUTER-NONEMPTY-SPAN? 0= IF 2DROP 0 EXIT THEN
    OVER C@ [CHAR] / <> IF 2DROP 0 EXIT THEN
    BEGIN
        DUP 0>
    WHILE
        OVER C@ DUP 33 < OVER 126 > OR
        OVER [CHAR] ? = OR OVER [CHAR] # = OR
        OVER [CHAR] \ = OR IF
            DROP 2DROP 0 EXIT
        THEN
        [CHAR] % = IF
            2DUP _HROUTER-PCT? 0= IF 2DROP 0 EXIT THEN
            3 - SWAP 3 + SWAP
        ELSE
            1- SWAP 1+ SWAP
        THEN
    REPEAT
    2DROP -1 ;

: _HROUTE-ENTRY-CALLBACKS?  ( entry -- flag )
    DUP HROUTE.OPERATION-SIZE @
        _HROUTER-OPERATION-SIZE? 0= IF DROP 0 EXIT THEN
    DUP HROUTE.START-XT @ 0= IF DROP 0 EXIT THEN
    DUP HROUTE.POLL-XT @ 0= IF DROP 0 EXIT THEN
    DUP HROUTE.CANCEL-XT @ 0= IF DROP 0 EXIT THEN
    HROUTE.CLEANUP-XT @ 0<> ;

: _HROUTER-SPAN-STORAGE-DISJOINT?  ( address length router -- flag )
    >R
    2DUP R@ HROUTER-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DUP R@ HROUTER.ENTRIES @
        R@ HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DUP R@ HROUTER.ARENA-A @ R@ HROUTER.ARENA-CAPACITY @
        MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DROP R> DROP -1 ;

\ Validate and advance one entry in the arena's exact packed order.
: _HROUTE-OWNED?  ( offset entry router -- next-offset flag )
    >R
    DUP HROUTE.METHOD-A @ R@ HROUTER.ARENA-A @ 3 PICK + <> IF
        2DROP R> DROP 0 0 EXIT
    THEN
    DUP HROUTE.METHOD-U @
    DUP 1 < IF DROP 2DROP R> DROP 0 0 EXIT THEN
    DUP R@ HROUTER.ARENA-CAPACITY @ 4 PICK - > IF
        DROP 2DROP R> DROP 0 0 EXIT
    THEN
    R@ HROUTER.ARENA-A @ 3 PICK + OVER +
    2 PICK HROUTE.PATH-A @ <> IF
        DROP 2DROP R> DROP 0 0 EXIT
    THEN
    OVER HROUTE.PATH-U @
    DUP 1 < IF 2DROP 2DROP R> DROP 0 0 EXIT THEN
    DUP R@ HROUTER.ARENA-CAPACITY @ 5 PICK - 3 PICK - > IF
        2DROP 2DROP R> DROP 0 0 EXIT
    THEN
    2 PICK HROUTE.METHOD-A @ 2 PICK _HROUTER-METHOD? 0= IF
        2DROP 2DROP R> DROP 0 0 EXIT
    THEN
    2 PICK HROUTE.PATH-A @ 1 PICK _HROUTER-PATH? 0= IF
        2DROP 2DROP R> DROP 0 0 EXIT
    THEN
    + NIP +
    R> DROP -1 ;

: _HROUTER-ENTRIES-VALID?  ( router -- flag )
    0
    OVER HROUTER.COUNT @ 0 ?DO
        I 2 PICK _HROUTER-ENTRY
        DUP _HROUTE-ENTRY-CALLBACKS? 0= IF
            DROP 2DROP 0 UNLOOP EXIT
        THEN
        DUP HROUTE.OPERATION-SIZE @
            3 PICK HROUTER.MAX-OPERATION-SIZE @ > IF
            DROP 2DROP 0 UNLOOP EXIT
        THEN
        2 PICK _HROUTE-OWNED? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    OVER HROUTER.ARENA-U @ =
    NIP ;

: _HROUTER-MAX-OPERATION-SIZE-EXACT?  ( router -- flag )
    DUP HROUTER.COUNT @ 0= IF
        DUP HROUTER.MAX-OPERATION-SIZE @ 0= SWAP DROP EXIT
    THEN
    DUP HROUTER.COUNT @ 0 ?DO
        I OVER _HROUTER-ENTRY HROUTE.OPERATION-SIZE @
        OVER HROUTER.MAX-OPERATION-SIZE @ = IF
            DROP -1 UNLOOP EXIT
        THEN
    LOOP
    DROP 0 ;

: HROUTER-VALID?  ( router -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP HROUTER-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP HROUTER.STATE @ DUP HROUTER-STATE-BUILDING =
        SWAP HROUTER-STATE-SEALED = OR 0= IF DROP 0 EXIT THEN
    DUP HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        0= IF DROP 0 EXIT THEN
    DUP HROUTER.ENTRIES @ 0= IF DROP 0 EXIT THEN
    DUP HROUTER.ENTRIES @
        OVER HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP HROUTER.ENTRIES @
        OVER HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        2 PICK HROUTER-SIZE MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    DUP HROUTER.ARENA-CAPACITY @ 0> 0= IF DROP 0 EXIT THEN
    DUP HROUTER.ARENA-A @ 0= IF DROP 0 EXIT THEN
    DUP HROUTER.ARENA-A @ OVER HROUTER.ARENA-CAPACITY @
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP HROUTER.ARENA-A @ OVER HROUTER.ARENA-CAPACITY @
        2 PICK HROUTER-SIZE MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    DUP HROUTER.ARENA-A @ OVER HROUTER.ARENA-CAPACITY @
        2 PICK HROUTER.ENTRIES @
        3 PICK HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    DUP HROUTER.ARENA-U @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER HROUTER.ARENA-CAPACITY @ > IF DROP 0 EXIT THEN
    DUP HROUTER.COUNT @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER HROUTER.ENTRY-CAPACITY @ > IF DROP 0 EXIT THEN
    DUP HROUTER.MAX-OPERATION-SIZE @
        _HROUTER-OPERATION-SIZE? 0= IF DROP 0 EXIT THEN
    DUP _HROUTER-ENTRIES-VALID? 0= IF DROP 0 EXIT THEN
    _HROUTER-MAX-OPERATION-SIZE-EXACT? ;

: HROUTER-SEALED?  ( router -- flag )
    DUP HROUTER-VALID? 0= IF DROP 0 EXIT THEN
    HROUTER.STATE @ HROUTER-STATE-SEALED = ;

: HROUTER-SPAN-DISJOINT?  ( address length router -- flag )
    >R
    DUP IF OVER 0= IF 2DROP R> DROP 0 EXIT THEN THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ HROUTER-VALID? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ _HROUTER-SPAN-STORAGE-DISJOINT?
    R> DROP ;

\ ---------------------------------------------------------------------
\ Construction and sealing
\ ---------------------------------------------------------------------

: _HROUTER-DROP-INIT  ( entries entry-capacity arena arena-capacity -- )
    2DROP 2DROP ;

: HROUTER-INIT
    ( entries entry-capacity arena arena-capacity router -- status )
    >R
    R@ 0= IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    R@ HROUTER-SIZE MSPAN-NONWRAPPING? 0= IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    2 PICK HROUTER-ENTRY-BYTES 0= IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    3 PICK 0= IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    3 PICK 3 PICK HROUTER-ENTRY-BYTES
        MSPAN-NONWRAPPING? 0= IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    DUP 0> 0= 2 PICK 0= OR IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    3 PICK 3 PICK HROUTER-ENTRY-BYTES
        R@ HROUTER-SIZE MSPAN-OVERLAP? IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    2DUP R@ HROUTER-SIZE MSPAN-OVERLAP? IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    3 PICK 3 PICK HROUTER-ENTRY-BYTES
        3 PICK 3 PICK MSPAN-OVERLAP? IF
        _HROUTER-DROP-INIT R> DROP HROUTER-S-INVALID EXIT
    THEN
    R@ HROUTER-SIZE 0 FILL
    3 PICK 3 PICK HROUTER-ENTRY-BYTES 0 FILL
    3 PICK R@ HROUTER.ENTRIES !
    2 PICK R@ HROUTER.ENTRY-CAPACITY !
    1 PICK R@ HROUTER.ARENA-A !
    DUP R@ HROUTER.ARENA-CAPACITY !
    _HROUTER-DROP-INIT
    HROUTER-STATE-BUILDING R@ HROUTER.STATE !
    R> DROP HROUTER-S-OK ;

: _HROUTER-DROP-ADD  ( m-a m-u p-a p-u ctx bytes s p c x -- )
    2DROP 2DROP 2DROP 2DROP 2DROP ;

: _HROUTER-DUPLICATE?
    ( method-a method-u path-a path-u router -- flag )
    DUP HROUTER.COUNT @ 0 ?DO
        4 PICK 4 PICK
        I 3 PICK _HROUTER-ENTRY
        DUP HROUTE.METHOD-A @ SWAP HROUTE.METHOD-U @
        _HROUTER-SPAN= IF
            2 PICK 2 PICK
            I 3 PICK _HROUTER-ENTRY
            DUP HROUTE.PATH-A @ SWAP HROUTE.PATH-U @
            _HROUTER-SPAN= IF
                DROP 2DROP 2DROP -1 UNLOOP EXIT
            THEN
        THEN
    LOOP
    DROP 2DROP 2DROP 0 ;

: _HROUTER-ROUTE-ROOM?  ( method-u path-u router -- flag )
    >R
    R@ HROUTER.ARENA-CAPACITY @ R@ HROUTER.ARENA-U @ -
    2 PICK OVER > IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    2 PICK -
    >R NIP R> <=
    R> DROP ;

: _HROUTE-COPY-INTO  ( source-a source-u destination -- )
    SWAP CMOVE ;

: _HROUTE-OWN-STRINGS  ( entry router -- )
    >R
    DUP HROUTE.METHOD-A @ OVER HROUTE.METHOD-U @
    R@ HROUTER.ARENA-A @ R@ HROUTER.ARENA-U @ +
    DUP 4 PICK HROUTE.METHOD-A !
    _HROUTE-COPY-INTO
    DUP HROUTE.METHOD-U @ R@ HROUTER.ARENA-U +!
    DUP HROUTE.PATH-A @ OVER HROUTE.PATH-U @
    R@ HROUTER.ARENA-A @ R@ HROUTER.ARENA-U @ +
    DUP 4 PICK HROUTE.PATH-A !
    _HROUTE-COPY-INTO
    DUP HROUTE.PATH-U @ R@ HROUTER.ARENA-U +!
    DROP R> DROP ;

: HROUTER-ADD
    ( method-a method-u path-a path-u handler-context operation-size )
    ( start-xt poll-xt cancel-xt cleanup-xt router -- status )
    >R
    R@ HROUTER-VALID? 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    R@ HROUTER.STATE @ HROUTER-STATE-BUILDING <> IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-STATE EXIT
    THEN
    9 PICK 9 PICK _HROUTER-METHOD? 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    7 PICK 7 PICK _HROUTER-PATH? 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    4 PICK _HROUTER-OPERATION-SIZE? 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    3 PICK 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    2 PICK 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    1 PICK 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    DUP 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    9 PICK 9 PICK R@ _HROUTER-SPAN-STORAGE-DISJOINT? 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    7 PICK 7 PICK R@ _HROUTER-SPAN-STORAGE-DISJOINT? 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-INVALID EXIT
    THEN
    9 PICK 9 PICK 9 PICK 9 PICK R@ _HROUTER-DUPLICATE? IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-DUPLICATE EXIT
    THEN
    R@ HROUTER.COUNT @ R@ HROUTER.ENTRY-CAPACITY @ >= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-FULL EXIT
    THEN
    8 PICK 7 PICK R@ _HROUTER-ROUTE-ROOM? 0= IF
        _HROUTER-DROP-ADD R> DROP HROUTER-S-FULL EXIT
    THEN

    R@ HROUTER.COUNT @ R@ _HROUTER-ENTRY >R
    R@ HROUTE.CLEANUP-XT !
    R@ HROUTE.CANCEL-XT !
    R@ HROUTE.POLL-XT !
    R@ HROUTE.START-XT !
    R@ HROUTE.OPERATION-SIZE !
    R@ HROUTE.HANDLER-CONTEXT !
    R@ HROUTE.PATH-U !
    R@ HROUTE.PATH-A !
    R@ HROUTE.METHOD-U !
    R@ HROUTE.METHOD-A !

    R> DUP R@ _HROUTE-OWN-STRINGS
    DUP HROUTE.OPERATION-SIZE @
        R@ HROUTER.MAX-OPERATION-SIZE @ > IF
        DUP HROUTE.OPERATION-SIZE @
            R@ HROUTER.MAX-OPERATION-SIZE !
    THEN
    DROP
    1 R@ HROUTER.COUNT +!
    R> DROP HROUTER-S-OK ;

: HROUTER-SEAL  ( router -- status )
    DUP HROUTER-VALID? 0= IF DROP HROUTER-S-INVALID EXIT THEN
    DUP HROUTER.STATE @ HROUTER-STATE-BUILDING <> IF
        DROP HROUTER-S-STATE EXIT
    THEN
    HROUTER-STATE-SEALED SWAP HROUTER.STATE !
    HROUTER-S-OK ;

\ ---------------------------------------------------------------------
\ Caller-owned match/result descriptor
\ ---------------------------------------------------------------------

0 CONSTANT HRMATCH-STATE-EMPTY
1 CONSTANT HRMATCH-STATE-FOUND
2 CONSTANT HRMATCH-STATE-NOT-FOUND

 0 CONSTANT _HRMATCH-STATE-O
 8 CONSTANT _HRMATCH-ENTRY-INDEX-O
16 CONSTANT _HRMATCH-METHOD-A-O
24 CONSTANT _HRMATCH-METHOD-U-O
32 CONSTANT _HRMATCH-PATH-A-O
40 CONSTANT _HRMATCH-PATH-U-O
48 CONSTANT _HRMATCH-HANDLER-CONTEXT-O
56 CONSTANT _HRMATCH-OPERATION-SIZE-O
64 CONSTANT _HRMATCH-START-XT-O
72 CONSTANT _HRMATCH-POLL-XT-O
80 CONSTANT _HRMATCH-CANCEL-XT-O
88 CONSTANT _HRMATCH-CLEANUP-XT-O
96 CONSTANT HROUTER-MATCH-SIZE

: HRMATCH.STATE            ( match -- a ) _HRMATCH-STATE-O + ;
: HRMATCH.ENTRY-INDEX      ( match -- a ) _HRMATCH-ENTRY-INDEX-O + ;
: HRMATCH.METHOD-A         ( match -- a ) _HRMATCH-METHOD-A-O + ;
: HRMATCH.METHOD-U         ( match -- a ) _HRMATCH-METHOD-U-O + ;
: HRMATCH.PATH-A           ( match -- a ) _HRMATCH-PATH-A-O + ;
: HRMATCH.PATH-U           ( match -- a ) _HRMATCH-PATH-U-O + ;
: HRMATCH.HANDLER-CONTEXT  ( match -- a ) _HRMATCH-HANDLER-CONTEXT-O + ;
: HRMATCH.OPERATION-SIZE   ( match -- a ) _HRMATCH-OPERATION-SIZE-O + ;
: HRMATCH.START-XT         ( match -- a ) _HRMATCH-START-XT-O + ;
: HRMATCH.POLL-XT          ( match -- a ) _HRMATCH-POLL-XT-O + ;
: HRMATCH.CANCEL-XT        ( match -- a ) _HRMATCH-CANCEL-XT-O + ;
: HRMATCH.CLEANUP-XT       ( match -- a ) _HRMATCH-CLEANUP-XT-O + ;

: _HRMATCH-RESET  ( match -- )
    HROUTER-MATCH-SIZE 0 FILL ;

: HRMATCH-INIT  ( match -- status )
    DUP 0= IF DROP HROUTER-S-INVALID EXIT THEN
    DUP HROUTER-MATCH-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP HROUTER-S-INVALID EXIT
    THEN
    _HRMATCH-RESET HROUTER-S-OK ;

: HRMATCH-VALID?  ( match -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP HROUTER-MATCH-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP HRMATCH.STATE @ DUP HRMATCH-STATE-EMPTY >=
        SWAP HRMATCH-STATE-NOT-FOUND <= AND 0= IF DROP 0 EXIT THEN
    DUP HRMATCH.STATE @ HRMATCH-STATE-FOUND = IF
        DUP HRMATCH.ENTRY-INDEX @ 0< IF DROP 0 EXIT THEN
        DUP HRMATCH.METHOD-A @ OVER HRMATCH.METHOD-U @
            _HROUTER-METHOD? 0= IF DROP 0 EXIT THEN
        DUP HRMATCH.PATH-A @ OVER HRMATCH.PATH-U @
            _HROUTER-PATH? 0= IF DROP 0 EXIT THEN
        DUP HRMATCH.OPERATION-SIZE @
            _HROUTER-OPERATION-SIZE? 0= IF DROP 0 EXIT THEN
        DUP HRMATCH.START-XT @ 0= IF DROP 0 EXIT THEN
        DUP HRMATCH.POLL-XT @ 0= IF DROP 0 EXIT THEN
        DUP HRMATCH.CANCEL-XT @ 0= IF DROP 0 EXIT THEN
        HRMATCH.CLEANUP-XT @ 0<> EXIT
    THEN
    DUP HRMATCH.ENTRY-INDEX @
    OVER HRMATCH.METHOD-A @ OR
    OVER HRMATCH.METHOD-U @ OR
    OVER HRMATCH.PATH-A @ OR
    OVER HRMATCH.PATH-U @ OR
    OVER HRMATCH.HANDLER-CONTEXT @ OR
    OVER HRMATCH.OPERATION-SIZE @ OR
    OVER HRMATCH.START-XT @ OR
    OVER HRMATCH.POLL-XT @ OR
    OVER HRMATCH.CANCEL-XT @ OR
    SWAP HRMATCH.CLEANUP-XT @ OR 0= ;

: HRMATCH-FOUND?  ( match -- flag )
    DUP HRMATCH-VALID? 0= IF DROP 0 EXIT THEN
    HRMATCH.STATE @ HRMATCH-STATE-FOUND = ;

: HRMATCH-STATE@  ( match -- state )
    DUP HRMATCH-VALID? 0= IF DROP HRMATCH-STATE-EMPTY EXIT THEN
    HRMATCH.STATE @ ;

: HRMATCH-ENTRY-INDEX@  ( match -- index|-1 )
    DUP HRMATCH-FOUND? 0= IF DROP -1 EXIT THEN
    HRMATCH.ENTRY-INDEX @ ;

: HRMATCH-METHOD  ( match -- method-a method-u )
    DUP HRMATCH-FOUND? 0= IF DROP 0 0 EXIT THEN
    DUP HRMATCH.METHOD-A @ SWAP HRMATCH.METHOD-U @ ;

: HRMATCH-PATH  ( match -- path-a path-u )
    DUP HRMATCH-FOUND? 0= IF DROP 0 0 EXIT THEN
    DUP HRMATCH.PATH-A @ SWAP HRMATCH.PATH-U @ ;

: HRMATCH-HANDLER-CONTEXT@  ( match -- context|0 )
    DUP HRMATCH-FOUND? 0= IF DROP 0 EXIT THEN
    HRMATCH.HANDLER-CONTEXT @ ;

: HRMATCH-OPERATION-SIZE@  ( match -- bytes|0 )
    DUP HRMATCH-FOUND? 0= IF DROP 0 EXIT THEN
    HRMATCH.OPERATION-SIZE @ ;

: HRMATCH-START-XT@  ( match -- xt|0 )
    DUP HRMATCH-FOUND? 0= IF DROP 0 EXIT THEN
    HRMATCH.START-XT @ ;

: HRMATCH-POLL-XT@  ( match -- xt|0 )
    DUP HRMATCH-FOUND? 0= IF DROP 0 EXIT THEN
    HRMATCH.POLL-XT @ ;

: HRMATCH-CANCEL-XT@  ( match -- xt|0 )
    DUP HRMATCH-FOUND? 0= IF DROP 0 EXIT THEN
    HRMATCH.CANCEL-XT @ ;

: HRMATCH-CLEANUP-XT@  ( match -- xt|0 )
    DUP HRMATCH-FOUND? 0= IF DROP 0 EXIT THEN
    HRMATCH.CLEANUP-XT @ ;

: _HRMATCH-STORAGE?  ( match router -- flag )
    OVER 0= IF 2DROP 0 EXIT THEN
    OVER HROUTER-MATCH-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP 0 EXIT
    THEN
    OVER HROUTER-MATCH-SIZE 2 PICK HROUTER-SIZE
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    OVER HROUTER-MATCH-SIZE
        2 PICK HROUTER.ENTRIES @
        3 PICK HROUTER.ENTRY-CAPACITY @ HROUTER-ENTRY-BYTES
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    OVER HROUTER-MATCH-SIZE
        2 PICK HROUTER.ARENA-A @
        3 PICK HROUTER.ARENA-CAPACITY @
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DROP -1 ;

: _HRMATCH-FILL  ( entry index match -- )
    >R
    DUP R@ HRMATCH.ENTRY-INDEX !
    DROP
    DUP HROUTE.METHOD-A @ R@ HRMATCH.METHOD-A !
    DUP HROUTE.METHOD-U @ R@ HRMATCH.METHOD-U !
    DUP HROUTE.PATH-A @ R@ HRMATCH.PATH-A !
    DUP HROUTE.PATH-U @ R@ HRMATCH.PATH-U !
    DUP HROUTE.HANDLER-CONTEXT @ R@ HRMATCH.HANDLER-CONTEXT !
    DUP HROUTE.OPERATION-SIZE @ R@ HRMATCH.OPERATION-SIZE !
    DUP HROUTE.START-XT @ R@ HRMATCH.START-XT !
    DUP HROUTE.POLL-XT @ R@ HRMATCH.POLL-XT !
    DUP HROUTE.CANCEL-XT @ R@ HRMATCH.CANCEL-XT !
    HROUTE.CLEANUP-XT @ R@ HRMATCH.CLEANUP-XT !
    HRMATCH-STATE-FOUND R@ HRMATCH.STATE !
    R> DROP ;

: _HROUTER-DROP-MATCH  ( m-a m-u p-a p-u match router -- )
    2DROP 2DROP 2DROP ;

\ An empty or negative span names no readable input and cannot be damaged by
\ clearing MATCH.  A positive span must have valid geometry and be disjoint
\ from MATCH before the result may be reset.
: _HROUTER-MATCH-SOURCE-SAFE?  ( source-a source-u match -- flag )
    >R
    DUP 1 < IF 2DROP R> DROP -1 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ HROUTER-MATCH-SIZE 2SWAP MSPAN-OVERLAP? 0=
    R> DROP ;

: HROUTER-MATCH
    ( method-a method-u path-a path-u match router -- status )
    DUP HROUTER-VALID? 0= IF
        _HROUTER-DROP-MATCH HROUTER-S-INVALID EXIT
    THEN
    1 PICK 1 PICK _HRMATCH-STORAGE? 0= IF
        _HROUTER-DROP-MATCH HROUTER-S-INVALID EXIT
    THEN
    5 PICK 5 PICK 3 PICK _HROUTER-MATCH-SOURCE-SAFE? 0= IF
        _HROUTER-DROP-MATCH HROUTER-S-INVALID EXIT
    THEN
    3 PICK 3 PICK 3 PICK _HROUTER-MATCH-SOURCE-SAFE? 0= IF
        _HROUTER-DROP-MATCH HROUTER-S-INVALID EXIT
    THEN
    1 PICK _HRMATCH-RESET
    DUP HROUTER.STATE @ HROUTER-STATE-SEALED <> IF
        _HROUTER-DROP-MATCH HROUTER-S-STATE EXIT
    THEN
    5 PICK 5 PICK _HROUTER-METHOD? 0= IF
        _HROUTER-DROP-MATCH HROUTER-S-INVALID EXIT
    THEN
    3 PICK 3 PICK _HROUTER-PATH? 0= IF
        _HROUTER-DROP-MATCH HROUTER-S-INVALID EXIT
    THEN

    DUP HROUTER.COUNT @ 0 ?DO
        5 PICK 5 PICK
        I 3 PICK _HROUTER-ENTRY
        DUP HROUTE.METHOD-A @ SWAP HROUTE.METHOD-U @
        _HROUTER-SPAN= IF
            3 PICK 3 PICK
            I 3 PICK _HROUTER-ENTRY
            DUP HROUTE.PATH-A @ SWAP HROUTE.PATH-U @
            _HROUTER-SPAN= IF
                I OVER _HROUTER-ENTRY I 3 PICK _HRMATCH-FILL
                _HROUTER-DROP-MATCH
                HROUTER-S-OK UNLOOP EXIT
            THEN
        THEN
    LOOP
    HRMATCH-STATE-NOT-FOUND 2 PICK HRMATCH.STATE !
    _HROUTER-DROP-MATCH HROUTER-S-NOT-FOUND ;

\ Registration is single-owner construction.  After HROUTER-SEAL, matching
\ performs no router or entry mutation.  Concurrent/cooperative connections
\ use distinct match descriptors, exchange descriptors, and operation
\ storage; the packed router-owned method/path arena remains immutable
\ throughout.
