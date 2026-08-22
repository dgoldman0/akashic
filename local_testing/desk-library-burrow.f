\ =====================================================================
\ desk-library-burrow.f - Checkpoint-4 Desk product composition fixture
\ =====================================================================
\ Loaded after Desk, Library, Rabbit-capable Streams, Agent, the checked-in
\ Scripted provider, and streams-burrow-prov.f.  Normal Library, Streams, and
\ Agent entry words build all three descriptors.  Bounded wrappers then bind
\ caller-owned Rabbit manager storage, automatic preflight, the outer-close
\ seam, and teardown witnesses while delegating to the product callbacks.
\
\ After all three queued applets autostart, four normal mandate-factory
\ preflight compilations automatically witness the live frozen 0/4/6/9 Desk
\ facets and are immediately freed.  One actual 9-entry Library Burrow
\ operator turn then makes eight unique tool calls through the normal Agent
\ review/gateway/request-bus path.  F12 in the focused Agent is the outer Desk
\ close trigger, but it posts ASHELL-QUIT so the child event dispatcher cannot
\ reinterpret the request as a close of only that tile.
\ =====================================================================

PROVIDED akashic-test-desk-library-burrow

VARIABLE _C4-CHECKS
VARIABLE _C4-FAILS
VARIABLE _C4-DEPTH

: _C4-ASSERT  ( flag -- )
    1 _C4-CHECKS +!
    0= IF
        1 _C4-FAILS +!
        ." DESK LIBRARY BURROW ASSERT " _C4-CHECKS @ . CR TX-FLUSH
    THEN ;

: _C4-OK  ( status -- ) 0= _C4-ASSERT ;

: _C4-STACK  ( -- )
    DEPTH DUP _C4-DEPTH @ <> IF
        ." DESK LIBRARY BURROW STACK " _C4-DEPTH @ . ." -> " DUP . CR
        .S CR TX-FLUSH
    THEN
    _C4-DEPTH @ = _C4-ASSERT ;

: _C4-ZERO?  ( address bytes -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

\ ---------------------------------------------------------------------
\ One Burrow declaration and the exact three mutation replay rows used by
\ create/start/stop.  These are fixture cardinalities, not product limits.
\ ---------------------------------------------------------------------

1 CONSTANT _C4-ROW-CAPACITY
3 CONSTANT _C4-REPLAY-CAPACITY

SBSP-SIZE
_C4-ROW-CAPACITY SRBMGR-DECLARATION-SIZE * +
_C4-REPLAY-CAPACITY SRBMGR-REPLAY-SIZE * +
CONSTANT _C4-BURROW-STORAGE-SIZE

CREATE _C4-BURROW-STORAGE-RAW _C4-BURROW-STORAGE-SIZE 7 + ALLOT

: _C4-BURROW-STORAGE  ( -- address )
    _C4-BURROW-STORAGE-RAW 7 + -8 AND ;
: _C4-BURROW-PROVIDER  ( -- context ) _C4-BURROW-STORAGE ;
: _C4-BURROW-ROWS  ( -- rows ) _C4-BURROW-PROVIDER SBSP-SIZE + ;
: _C4-BURROW-REPLAYS  ( -- replays )
    _C4-BURROW-ROWS
    _C4-ROW-CAPACITY SRBMGR-DECLARATION-SIZE * + ;

\ ---------------------------------------------------------------------
\ Checkpoint composition seams
\ ---------------------------------------------------------------------
\ The defaults below are this Checkpoint-4 fixture's exact static provider,
\ eight logical calls, and immediate progression.  A later qualification
\ fixture may install alternate graph ownership, nonblocking progress, and
\ result-recovery policy without placing its data plane in this fixture or
\ copying the product journey.  CONFIGURE always invokes the installer first,
\ so a prior qualification run cannot leave stale hook selections behind.

DEFER _C4-GRAPH-CONFIGURE
DEFER _C4-GRAPH-COMPOSE
DEFER _C4-GRAPH-STATE@
DEFER _C4-GRAPH-SHUTDOWN-CHECK
DEFER _C4-GRAPH-POST-CHECK
DEFER _C4-GRAPH-LEASE?
DEFER _C4-PROGRESS-READY?
DEFER _C4-RESULT-OBSERVE
DEFER _C4-RESULT-OVERRIDE
DEFER _C4-EXPECTED-TOOLS
DEFER _C4-INSTALL-COMPOSITION

: _C4-DEFAULT-GRAPH-CONFIGURE  ( -- )
    _C4-BURROW-STORAGE _C4-BURROW-STORAGE-SIZE 0 FILL
    _C4-BURROW-PROVIDER SBSP-INIT SRBPROV-S-NONE = _C4-ASSERT
    1 0 _C4-BURROW-PROVIDER SBSP-COUNTS! _C4-ASSERT
    _C4-BURROW-PROVIDER SBSP-VALID? _C4-ASSERT ;

: _C4-DEFAULT-GRAPH-COMPOSE  ( streams-state -- status )
    >R _C4-BURROW-ROWS _C4-ROW-CAPACITY
    _C4-BURROW-REPLAYS _C4-REPLAY-CAPACITY
    _C4-BURROW-PROVIDER SBSP-PROVIDER R>
        STREAMS-BURROW-COMPOSITION-STATE! ;

: _C4-DEFAULT-GRAPH-STATE@  ( -- state )
    _C4-BURROW-ROWS SRBMGR-DECL.STATE @ ;

: _C4-DEFAULT-GRAPH-ZERO-CHECK  ( -- )
    _C4-BURROW-PROVIDER SBSP-LEASE-ACTIVE? 0= _C4-ASSERT
    _C4-BURROW-ROWS _C4-ROW-CAPACITY SRBMGR-DECLARATION-SIZE *
        _C4-ZERO? _C4-ASSERT
    _C4-BURROW-REPLAYS _C4-REPLAY-CAPACITY SRBMGR-REPLAY-SIZE *
        _C4-ZERO? _C4-ASSERT ;

: _C4-DEFAULT-GRAPH-LEASE?  ( -- flag )
    _C4-BURROW-PROVIDER SBSP-LEASE-ACTIVE? ;

: _C4-DEFAULT-PROGRESS-READY?  ( -- ready? ) -1 ;
: _C4-DEFAULT-RESULT-OBSERVE  ( -- ) ;
: _C4-DEFAULT-RESULT-OVERRIDE  ( -- ior handled? ) 0 0 ;
: _C4-DEFAULT-EXPECTED-TOOLS  ( -- count ) 8 ;

: _C4-INSTALL-DEFAULT-COMPOSITION  ( -- )
    ['] _C4-DEFAULT-GRAPH-CONFIGURE IS _C4-GRAPH-CONFIGURE
    ['] _C4-DEFAULT-GRAPH-COMPOSE IS _C4-GRAPH-COMPOSE
    ['] _C4-DEFAULT-GRAPH-STATE@ IS _C4-GRAPH-STATE@
    ['] _C4-DEFAULT-GRAPH-ZERO-CHECK IS _C4-GRAPH-SHUTDOWN-CHECK
    ['] _C4-DEFAULT-GRAPH-ZERO-CHECK IS _C4-GRAPH-POST-CHECK
    ['] _C4-DEFAULT-GRAPH-LEASE? IS _C4-GRAPH-LEASE?
    ['] _C4-DEFAULT-PROGRESS-READY? IS _C4-PROGRESS-READY?
    ['] _C4-DEFAULT-RESULT-OBSERVE IS _C4-RESULT-OBSERVE
    ['] _C4-DEFAULT-RESULT-OVERRIDE IS _C4-RESULT-OVERRIDE
    ['] _C4-DEFAULT-EXPECTED-TOOLS IS _C4-EXPECTED-TOOLS ;

' _C4-INSTALL-DEFAULT-COMPOSITION IS _C4-INSTALL-COMPOSITION
_C4-INSTALL-DEFAULT-COMPOSITION

VARIABLE _C4-STREAMS-INSTANCE
VARIABLE _C4-STREAMS-STATE
VARIABLE _C4-LIBRARY-SHUTDOWNS
VARIABLE _C4-STREAMS-SHUTDOWNS
VARIABLE _C4-AGENT-SHUTDOWNS
VARIABLE _C4-PROVIDER-FREED
VARIABLE _C4-SOURCE
VARIABLE _C4-SOURCE-FREED
VARIABLE _C4-AVAILABLE-BASELINE

: _C4-AVAILABLE  ( -- bytes )
    XMEM? IF
        XMEM-FREE XMEM-FL @
        BEGIN DUP WHILE
            DUP @ ROT + SWAP 8 + @
        REPEAT
        DROP
    ELSE
        HEAP-FREE-BYTES
    THEN ;

: _C4-STREAMS-INIT  ( instance -- )
    DUP _C4-STREAMS-INSTANCE !
    DUP CINST-STATE _C4-STREAMS-STATE !
    _C4-STREAMS-STATE @ _C4-GRAPH-COMPOSE
        SRBPROV-S-NONE = _C4-ASSERT
    STREAMS-INIT-CB ;

: _C4-STREAMS-SHUTDOWN  ( instance -- )
    STREAMS-SHUTDOWN-CB
    _C4-GRAPH-SHUTDOWN-CHECK
    0 _C4-STREAMS-INSTANCE ! 0 _C4-STREAMS-STATE !
    1 _C4-STREAMS-SHUTDOWNS +!
    ." DESK LIBRARY BURROW STREAMS SHUTDOWN "
        _C4-STREAMS-SHUTDOWNS @ . CR TX-FLUSH ;

: _C4-LIBRARY-SHUTDOWN  ( instance -- )
    LIBRARY-APPLET-SHUTDOWN-CB
    1 _C4-LIBRARY-SHUTDOWNS +!
    ." DESK LIBRARY BURROW LIBRARY SHUTDOWN "
        _C4-LIBRARY-SHUTDOWNS @ . CR TX-FLUSH ;

: _C4-AGENT-SHUTDOWN  ( instance -- )
    AGENT-SHUTDOWN-CB
    1 _C4-AGENT-SHUTDOWNS +!
    ." DESK LIBRARY BURROW AGENT SHUTDOWN "
        _C4-AGENT-SHUTDOWNS @ . CR TX-FLUSH ;

\ ---------------------------------------------------------------------
\ Exact live frozen facet witnesses.  Count plus inclusion proves the set;
\ each inclusion also resolves the frozen target id/generation back through
\ the live Desk registry and pins it to the expected component descriptor.
\ ---------------------------------------------------------------------

VARIABLE _C4-FACET
VARIABLE _C4-MANDATE-RUN
VARIABLE _C4-FACET-BITS
VARIABLE _C4-FIND-A
VARIABLE _C4-FIND-U
VARIABLE _C4-PIN-COMP
VARIABLE _C4-WITNESS-OK

\ The selected Library/Streams closure has no navigation operation.  Desk
\ narrows each frozen Mandate to the union of effects actually present in
\ its live facet, even though the Assist and Library-Burrow access profiles
\ permit navigation when a matching applet is resident.
CAP-E-OBSERVE CAP-E-MUTATE OR CAP-E-PERSIST OR
CONSTANT _C4-LIVE-CHANGE-EFFECTS

: _C4-FACET-FIND  ( op-a op-u -- entry|0 )
    _C4-FIND-U ! _C4-FIND-A !
    _C4-FACET @ CFACET.COUNT @ 0 ?DO
        I _C4-FACET @ CFACET-NTH DUP CFENTRY-OP@
        _C4-FIND-A @ _C4-FIND-U @ STR-STR= IF UNLOOP EXIT THEN
        DROP
    LOOP
    0 ;

: _C4-PINNED?  ( op-a op-u expected-comp -- flag )
    _C4-PIN-COMP !
    _C4-FACET-FIND DUP 0= IF EXIT THEN
    DUP CFENTRY.TARGET-ID @ SWAP CFENTRY.TARGET-GEN @
        _DESK-REGISTRY @ CREG-INST-FIND
    ?DUP IF CINST-DESC _C4-PIN-COMP @ = ELSE 0 THEN ;

: _C4-BASE-OBSERVATIONS?  ( -- flag )
    S" streams.source.query" STREAMS-COMP-DESC _C4-PINNED?
    S" streams.source.read" STREAMS-COMP-DESC _C4-PINNED? AND
    S" library.status" LIBRARY-APPLET-COMP-DESC _C4-PINNED? AND
    S" streams.burrow.status" STREAMS-COMP-DESC _C4-PINNED? AND ;

: _C4-LIBRARY-CHANGES?  ( -- flag )
    S" library.document.create"
        LIBRARY-APPLET-COMP-DESC _C4-PINNED?
    S" library.collection.create"
        LIBRARY-APPLET-COMP-DESC _C4-PINNED? AND ;

: _C4-BURROW-CHANGES?  ( -- flag )
    S" streams.burrow.create" STREAMS-COMP-DESC _C4-PINNED?
    S" streams.burrow.start" STREAMS-COMP-DESC _C4-PINNED? AND
    S" streams.burrow.stop" STREAMS-COMP-DESC _C4-PINNED? AND ;

: _C4-LIBRARY-BROAD-READS-ABSENT?  ( -- flag )
    S" library.document.query" _C4-FACET-FIND 0=
    S" library.document.read" _C4-FACET-FIND 0= AND ;

: _C4-BURROW-CHANGES-ABSENT?  ( -- flag )
    S" streams.burrow.create" _C4-FACET-FIND 0=
    S" streams.burrow.start" _C4-FACET-FIND 0= AND
    S" streams.burrow.stop" _C4-FACET-FIND 0= AND ;

: _C4-LIBRARY-CHANGES-ABSENT?  ( -- flag )
    S" library.document.create" _C4-FACET-FIND 0=
    S" library.collection.create" _C4-FACET-FIND 0= AND ;

: _C4-NO-EXTERNAL-EFFECTS?  ( -- flag )
    _C4-FACET @ CFACET.COUNT @ 0 ?DO
        I _C4-FACET @ CFACET-NTH CFENTRY.EFFECTS @
            CAP-E-EXTERNAL AND IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _C4-EXTERNAL-ABSENT?  ( -- flag )
    S" streams.draft.publish" _C4-FACET-FIND 0=
    S" streams.source.refresh" _C4-FACET-FIND 0= AND ;

: _C4-MARK-FACET  ( label-a label-u count -- )
    >R ." DESK LIBRARY BURROW FACET " TYPE SPACE R> .
    ." PASS" CR TX-FLUSH ;

: _C4-FACET-WITNESS  ( -- operator? valid? )
    _C4-FACET @ CFACET-VALID? DUP _C4-ASSERT 0= IF 0 0 EXIT THEN
    _C4-FACET @ CFACET.COUNT @ CASE
        0 OF
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.TOOL-BUDGET @ 0=
                _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.EFFECTS @ 0=
                _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.DISPOSITION @
                MAND-D-READ-ONLY = _C4-ASSERT
            _C4-LIBRARY-BROAD-READS-ABSENT? _C4-ASSERT
            _C4-LIBRARY-CHANGES-ABSENT? _C4-ASSERT
            _C4-BURROW-CHANGES-ABSENT? _C4-ASSERT
            _C4-NO-EXTERNAL-EFFECTS? _C4-ASSERT
            _C4-EXTERNAL-ABSENT? _C4-ASSERT
            1 _C4-FACET-BITS @ OR _C4-FACET-BITS !
            S" CHAT" 0 _C4-MARK-FACET
            0 -1
        ENDOF
        4 OF
            _C4-BASE-OBSERVATIONS? DUP _C4-WITNESS-OK ! _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.TOOL-BUDGET @ 4 =
                _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.EFFECTS @
                CAP-E-OBSERVE = _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.DISPOSITION @
                MAND-D-READ-ONLY = _C4-ASSERT
            _C4-LIBRARY-CHANGES-ABSENT? _C4-ASSERT
            _C4-BURROW-CHANGES-ABSENT? _C4-ASSERT
            _C4-LIBRARY-BROAD-READS-ABSENT? _C4-ASSERT
            _C4-NO-EXTERNAL-EFFECTS? _C4-ASSERT
            _C4-EXTERNAL-ABSENT? _C4-ASSERT
            2 _C4-FACET-BITS @ OR _C4-FACET-BITS !
            S" READ" 4 _C4-MARK-FACET
            0 _C4-WITNESS-OK @
        ENDOF
        6 OF
            _C4-BASE-OBSERVATIONS? _C4-LIBRARY-CHANGES? AND
                DUP _C4-WITNESS-OK ! _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.TOOL-BUDGET @ 8 =
                _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.EFFECTS @
                _C4-LIVE-CHANGE-EFFECTS = _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.DISPOSITION @
                MAND-D-COMMIT = _C4-ASSERT
            _C4-BURROW-CHANGES-ABSENT? _C4-ASSERT
            _C4-LIBRARY-BROAD-READS-ABSENT? _C4-ASSERT
            _C4-NO-EXTERNAL-EFFECTS? _C4-ASSERT
            _C4-EXTERNAL-ABSENT? _C4-ASSERT
            4 _C4-FACET-BITS @ OR _C4-FACET-BITS !
            S" ASSIST" 6 _C4-MARK-FACET
            0 _C4-WITNESS-OK @
        ENDOF
        9 OF
            _C4-BASE-OBSERVATIONS? _C4-LIBRARY-CHANGES? AND
            _C4-BURROW-CHANGES? AND
                DUP _C4-WITNESS-OK ! _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.TOOL-BUDGET @ 12 =
                _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.EFFECTS @
                _C4-LIVE-CHANGE-EFFECTS = _C4-ASSERT
            _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.DISPOSITION @
                MAND-D-COMMIT = _C4-ASSERT
            _C4-LIBRARY-BROAD-READS-ABSENT? _C4-ASSERT
            _C4-NO-EXTERNAL-EFFECTS? _C4-ASSERT
            _C4-EXTERNAL-ABSENT? _C4-ASSERT
            _C4-FACET-BITS @ 7 AND 7 = _C4-ASSERT
            8 _C4-FACET-BITS @ OR _C4-FACET-BITS !
            S" OPERATOR" 9 _C4-MARK-FACET
            -1 _C4-WITNESS-OK @
        ENDOF
        0 _C4-ASSERT 0 0 ROT
    ENDCASE ;

\ ---------------------------------------------------------------------
\ Owned tool-call events and exact argument graphs
\ ---------------------------------------------------------------------

VARIABLE _C4-TURN
VARIABLE _C4-QUEUE
VARIABLE _C4-CONTEXT
VARIABLE _C4-CALL
VARIABLE _C4-WAIT
VARIABLE _C4-OPERATOR
VARIABLE _C4-DONE
VARIABLE _C4-EVENT-FAILS
VARIABLE _C4-NODE
VARIABLE _C4-LIBRARY-GENERATION
VARIABLE _C4-DOCUMENT-GENERATION
VARIABLE _C4-COLLECTION-GENERATION
VARIABLE _C4-COLLECTION-REVISION
VARIABLE _C4-BURROW-REVISION

CREATE _C4-DOCUMENT-REF RREF-SIZE ALLOT
CREATE _C4-COLLECTION-REF RREF-SIZE ALLOT
CREATE _C4-BURROW-REF RREF-SIZE ALLOT
CREATE _C4-TEMP-REF RREF-SIZE ALLOT
CREATE _C4-REQUEST-DIGEST SHA3-256-HEX-LEN ALLOT

: _C4-EVENT  ( -- event ) _C4-CONTEXT @ _SPC.EVENT ;

: _C4-CAP$  ( -- addr len )
    _C4-CALL @ CASE
        0 OF S" library.status" ENDOF
        1 OF S" library.document.create" ENDOF
        2 OF S" library.collection.create" ENDOF
        3 OF S" streams.burrow.create" ENDOF
        4 OF S" streams.burrow.start" ENDOF
        5 OF S" streams.burrow.status" ENDOF
        6 OF S" streams.burrow.stop" ENDOF
        7 OF S" streams.burrow.status" ENDOF
        S" invalid.checkpoint4.call" ROT
    ENDCASE ;

: _C4-CALL-ID$  ( -- addr len )
    _C4-CALL @ CASE
        0 OF S" c4.call.01" ENDOF
        1 OF S" c4.call.02" ENDOF
        2 OF S" c4.call.03" ENDOF
        3 OF S" c4.call.04" ENDOF
        4 OF S" c4.call.05" ENDOF
        5 OF S" c4.call.06" ENDOF
        6 OF S" c4.call.07" ENDOF
        7 OF S" c4.call.08" ENDOF
        S" c4.call.invalid" ROT
    ENDCASE ;

VARIABLE _C4-HEADER-A
VARIABLE _C4-HEADER-U

: _C4-TOOL-HEADER  ( name-a name-u -- )
    _C4-HEADER-U ! _C4-HEADER-A !
    _C4-EVENT AEV-FREE
    AEV-TOOL-CALL _C4-EVENT AEV.KIND !
    _C4-CONTEXT @ _SPC.RUN-ID @ _C4-EVENT AEV.RUN-ID !
    _C4-CONTEXT @ _SPC.SEQUENCE @ _C4-EVENT AEV.SEQUENCE !
    1 _C4-CONTEXT @ _SPC.SEQUENCE +!
    _C4-HEADER-A @ _C4-HEADER-U @ _C4-EVENT AEV.NAME
        CV-STRING! _C4-OK
    _C4-CALL-ID$ _C4-EVENT AEV.CALL-ID CV-STRING! _C4-OK ;

: _C4-SLOT  ( key-a key-u index -- value )
    _C4-EVENT AEV.DATA CV-MAP-SLOT!
    DUP 0= _C4-ASSERT DROP ;

: _C4-RESOURCE!  ( reference value -- )
    IRES-RREF! IRES-S-OK = _C4-ASSERT ;

: _C4-ARGS-STATUS-LIBRARY  ( -- )
    _C4-EVENT AEV.DATA CV-NULL! ;

: _C4-ARGS-DOCUMENT  ( -- )
    4 _C4-EVENT AEV.DATA CV-MAP! _C4-OK
    S" expected_logical_generation" 0 _C4-SLOT
        _C4-LIBRARY-GENERATION @ SWAP CV-INT!
    S" title" 1 _C4-SLOT
        S" N" ROT CV-STRING! _C4-OK
    S" media_type" 2 _C4-SLOT
        S" text/plain" ROT CV-STRING! _C4-OK
    S" content" 3 _C4-SLOT
        S" é" ROT CV-STRING! _C4-OK ;

: _C4-ARGS-COLLECTION  ( -- )
    3 _C4-EVENT AEV.DATA CV-MAP! _C4-OK
    S" expected_logical_generation" 0 _C4-SLOT
        _C4-DOCUMENT-GENERATION @ SWAP CV-INT!
    S" title" 1 _C4-SLOT
        S" Agent Burrow Reading List" ROT CV-STRING! _C4-OK
    S" members" 2 _C4-SLOT DUP _C4-NODE !
        1 SWAP CV-LIST! _C4-OK
    _C4-DOCUMENT-REF 0 _C4-NODE @ CV-LIST-NTH _C4-RESOURCE! ;

: _C4-ARGS-BURROW-CREATE  ( -- )
    6 _C4-EVENT AEV.DATA CV-MAP! _C4-OK
    S" collection" 0 _C4-SLOT
        _C4-COLLECTION-REF SWAP _C4-RESOURCE!
    S" collection_domain_revision" 1 _C4-SLOT
        _C4-COLLECTION-REVISION @ SWAP CV-INT!
    S" request_digest" 2 _C4-SLOT
        _C4-REQUEST-DIGEST SHA3-256-HEX-LEN ROT CV-STRING! _C4-OK
    S" profile" 3 _C4-SLOT
        S" library-read-v1" ROT CV-STRING! _C4-OK
    S" transport" 4 _C4-SLOT
        S" memory-duplex" ROT CV-STRING! _C4-OK
    S" peer_capacity" 5 _C4-SLOT 1 SWAP CV-INT! ;

: _C4-ARGS-BURROW-STATUS  ( -- )
    1 _C4-EVENT AEV.DATA CV-MAP! _C4-OK
    S" burrow" 0 _C4-SLOT _C4-BURROW-REF SWAP _C4-RESOURCE! ;

: _C4-ARGS-BURROW-MUTATE  ( -- )
    2 _C4-EVENT AEV.DATA CV-MAP! _C4-OK
    S" burrow" 0 _C4-SLOT _C4-BURROW-REF SWAP _C4-RESOURCE!
    S" expected_domain_revision" 1 _C4-SLOT
        _C4-BURROW-REVISION @ SWAP CV-INT! ;

: _C4-REVIEW-CALL?  ( -- flag )
    _C4-CALL @ DUP 1 = OVER 2 = OR OVER 3 = OR
    OVER 4 = OR SWAP 6 = OR ;

: _C4-CALL-MARKER  ( -- )
    ." DESK LIBRARY BURROW CALL " _C4-CALL @ 1+ .
    _C4-CAP$ TYPE
    _C4-REVIEW-CALL? IF ."  REVIEW" THEN
    CR TX-FLUSH ;

: _C4-POST-TOOL  ( -- ior )
    _SP-WAITING _C4-CONTEXT @ _SPC.STATE !
    _C4-EVENT _C4-QUEUE @ AEQ-POST
    DUP 0= IF _C4-CALL-MARKER THEN ;

: _C4-EMIT-CALL  ( -- ior )
    _C4-FAILS @ _C4-EVENT-FAILS !
    _C4-CAP$ _C4-TOOL-HEADER
    _C4-CALL @ CASE
        0 OF _C4-ARGS-STATUS-LIBRARY ENDOF
        1 OF _C4-ARGS-DOCUMENT ENDOF
        2 OF _C4-ARGS-COLLECTION ENDOF
        3 OF _C4-ARGS-BURROW-CREATE ENDOF
        4 OF _C4-ARGS-BURROW-MUTATE ENDOF
        5 OF _C4-ARGS-BURROW-STATUS ENDOF
        6 OF _C4-ARGS-BURROW-MUTATE ENDOF
        7 OF _C4-ARGS-BURROW-STATUS ENDOF
        0 _C4-ASSERT
    ENDCASE
    _C4-FAILS @ _C4-EVENT-FAILS @ <> IF
        _C4-EVENT AEV-FREE 1 EXIT
    THEN
    _C4-POST-TOOL ;

\ ---------------------------------------------------------------------
\ Borrowed result validation and immediate owned-field capture
\ ---------------------------------------------------------------------

VARIABLE _C4-RESULT-VALUE
VARIABLE _C4-RESULT-STATUS
VARIABLE _C4-RESULT-RUN
VARIABLE _C4-RESULT-NAME-A
VARIABLE _C4-RESULT-NAME-U
VARIABLE _C4-RESULT-EXPECTED-A
VARIABLE _C4-RESULT-EXPECTED-U
VARIABLE _C4-RESULT-REF
VARIABLE _C4-RESULT-N

: _C4-FIELD  ( key-a key-u -- value|0 )
    _C4-RESULT-VALUE @ CV-MAP-FIND ;

: _C4-INT-FIELD  ( key-a key-u -- n )
    _C4-FIELD DUP 0= IF DROP 0 _C4-ASSERT 0 EXIT THEN
    DUP CV-TYPE@ CV-T-INT = _C4-ASSERT
    CV-DATA@ ;

: _C4-BOOL-FIELD  ( key-a key-u -- flag )
    _C4-FIELD DUP 0= IF DROP 0 _C4-ASSERT 0 EXIT THEN
    DUP CV-TYPE@ CV-T-BOOL = _C4-ASSERT
    CV-DATA@ ;

: _C4-STRING-FIELD=  ( key-a key-u expected-a expected-u -- flag )
    _C4-RESULT-EXPECTED-U ! _C4-RESULT-EXPECTED-A !
    _C4-FIELD DUP 0= IF DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-STRING <> IF DROP 0 EXIT THEN
    DUP CV-DATA@ SWAP CV-LEN@
        _C4-RESULT-EXPECTED-A @ _C4-RESULT-EXPECTED-U @ STR-STR= ;

: _C4-RESOURCE-FIELD  ( key-a key-u destination -- flag )
    _C4-RESULT-REF !
    _C4-FIELD DUP 0= IF DROP 0 EXIT THEN
    _C4-RESULT-REF @ IRES-RREF@ IRES-S-OK <> IF 0 EXIT THEN
    _C4-RESULT-REF @ DUP RREF-VALID?
    SWAP RREF.REVISION @ 0= AND ;

: _C4-DIGEST-FIELD=  ( key-a key-u expected -- flag )
    >R _C4-FIELD DUP 0= IF DROP R> DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-STRING <> IF DROP R> DROP 0 EXIT THEN
    DUP CV-LEN@ SHA3-256-HEX-LEN <> IF DROP R> DROP 0 EXIT THEN
    DUP CV-DATA@ SWAP CV-LEN@ R> SHA3-256-HEX-LEN STR-STR= ;

: _C4-COPY-REQUEST-DIGEST  ( -- )
    S" request_digest" _C4-FIELD
    DUP 0<> DUP _C4-ASSERT 0= IF DROP EXIT THEN
    DUP CV-TYPE@ CV-T-STRING = DUP _C4-ASSERT 0= IF DROP EXIT THEN
    DUP CV-LEN@ SHA3-256-HEX-LEN = DUP _C4-ASSERT 0= IF DROP EXIT THEN
    CV-DATA@ _C4-REQUEST-DIGEST SHA3-256-HEX-LEN MOVE ;

: _C4-CAPTURE-LIBRARY-STATUS  ( -- )
    S" ready" _C4-BOOL-FIELD 0= _C4-ASSERT
    S" logical_generation" _C4-INT-FIELD DUP 0= _C4-ASSERT
        _C4-LIBRARY-GENERATION ! ;

: _C4-CAPTURE-DOCUMENT  ( -- )
    S" resource" _C4-DOCUMENT-REF _C4-RESOURCE-FIELD _C4-ASSERT
    S" domain_revision" _C4-INT-FIELD 1 = _C4-ASSERT
    S" logical_generation" _C4-INT-FIELD
        DUP _C4-LIBRARY-GENERATION @ > _C4-ASSERT
        _C4-DOCUMENT-GENERATION ! ;

: _C4-CAPTURE-COLLECTION  ( -- )
    S" resource" _C4-COLLECTION-REF _C4-RESOURCE-FIELD _C4-ASSERT
    S" domain_revision" _C4-INT-FIELD DUP 1 = _C4-ASSERT
        _C4-COLLECTION-REVISION !
    S" logical_generation" _C4-INT-FIELD
        DUP _C4-DOCUMENT-GENERATION @ > _C4-ASSERT
        _C4-COLLECTION-GENERATION !
    _C4-COPY-REQUEST-DIGEST ;

: _C4-CAPTURE-BURROW-CREATE  ( -- )
    S" burrow" _C4-BURROW-REF _C4-RESOURCE-FIELD _C4-ASSERT
    S" domain_revision" _C4-INT-FIELD DUP 1 = _C4-ASSERT
        _C4-BURROW-REVISION !
    S" state" S" configured" _C4-STRING-FIELD= _C4-ASSERT
    S" collection" _C4-TEMP-REF _C4-RESOURCE-FIELD _C4-ASSERT
    _C4-TEMP-REF RREF.ID _C4-COLLECTION-REF RREF.ID RID= _C4-ASSERT
    S" collection_domain_revision" _C4-INT-FIELD
        _C4-COLLECTION-REVISION @ = _C4-ASSERT
    S" request_digest" _C4-REQUEST-DIGEST
        _C4-DIGEST-FIELD= _C4-ASSERT
    S" profile" S" library-read-v1" _C4-STRING-FIELD= _C4-ASSERT
    S" transport" S" memory-duplex" _C4-STRING-FIELD= _C4-ASSERT
    S" peer_capacity" _C4-INT-FIELD 1 = _C4-ASSERT ;

: _C4-CAPTURE-BURROW-START  ( -- )
    S" burrow" _C4-TEMP-REF _C4-RESOURCE-FIELD _C4-ASSERT
    _C4-TEMP-REF RREF.ID _C4-BURROW-REF RREF.ID RID= _C4-ASSERT
    S" state" S" starting" _C4-STRING-FIELD= _C4-ASSERT
    S" domain_revision" _C4-INT-FIELD DUP 2 = _C4-ASSERT
        _C4-BURROW-REVISION ! ;

: _C4-CAPTURE-BURROW-RUNNING  ( -- )
    S" burrow" _C4-TEMP-REF _C4-RESOURCE-FIELD _C4-ASSERT
    _C4-TEMP-REF RREF.ID _C4-BURROW-REF RREF.ID RID= _C4-ASSERT
    S" state" S" running" _C4-STRING-FIELD= _C4-ASSERT
    S" domain_revision" _C4-INT-FIELD DUP 3 = _C4-ASSERT
        _C4-BURROW-REVISION !
    S" peer_count" _C4-INT-FIELD 1 = _C4-ASSERT
    ." DESK LIBRARY BURROW STATE RUNNING PASS" CR TX-FLUSH ;

: _C4-CAPTURE-BURROW-STOP  ( -- )
    S" burrow" _C4-TEMP-REF _C4-RESOURCE-FIELD _C4-ASSERT
    _C4-TEMP-REF RREF.ID _C4-BURROW-REF RREF.ID RID= _C4-ASSERT
    S" state" S" stopping" _C4-STRING-FIELD= _C4-ASSERT
    S" domain_revision" _C4-INT-FIELD DUP 4 = _C4-ASSERT
        _C4-BURROW-REVISION ! ;

: _C4-CAPTURE-BURROW-STOPPED  ( -- )
    S" burrow" _C4-TEMP-REF _C4-RESOURCE-FIELD _C4-ASSERT
    _C4-TEMP-REF RREF.ID _C4-BURROW-REF RREF.ID RID= _C4-ASSERT
    S" state" S" stopped" _C4-STRING-FIELD= _C4-ASSERT
    S" domain_revision" _C4-INT-FIELD DUP 5 = _C4-ASSERT
        _C4-BURROW-REVISION !
    S" cleanup_pending" _C4-BOOL-FIELD 0= _C4-ASSERT
    S" peer_count" _C4-INT-FIELD 0= _C4-ASSERT
    ." DESK LIBRARY BURROW STATE STOPPED PASS" CR TX-FLUSH ;

: _C4-CAPTURE-RESULT  ( -- )
    _C4-RESULT-VALUE @ DUP 0<> DUP _C4-ASSERT 0= IF DROP EXIT THEN
    CV-TYPE@ CV-T-MAP = DUP _C4-ASSERT 0= IF EXIT THEN
    _C4-CALL @ CASE
        0 OF _C4-CAPTURE-LIBRARY-STATUS ENDOF
        1 OF _C4-CAPTURE-DOCUMENT ENDOF
        2 OF _C4-CAPTURE-COLLECTION ENDOF
        3 OF _C4-CAPTURE-BURROW-CREATE ENDOF
        4 OF _C4-CAPTURE-BURROW-START ENDOF
        5 OF _C4-CAPTURE-BURROW-RUNNING ENDOF
        6 OF _C4-CAPTURE-BURROW-STOP ENDOF
        7 OF _C4-CAPTURE-BURROW-STOPPED ENDOF
        0 _C4-ASSERT
    ENDCASE ;

\ ---------------------------------------------------------------------
\ Normal mandate-factory preflight after all three autostarts are live
\ ---------------------------------------------------------------------

VARIABLE _C4-PREFLIGHT-PRESET
VARIABLE _C4-PREFLIGHT-RUN-ID
VARIABLE _C4-PREFLIGHT-RUN
VARIABLE _C4-PREFLIGHT-STATUS
VARIABLE _C4-PREFLIGHT-OPERATOR
VARIABLE _C4-PREFLIGHT-VALID

: _C4-PREFLIGHT-ONE  ( preset run-id -- )
    _C4-PREFLIGHT-RUN-ID ! _C4-PREFLIGHT-PRESET !
    _C4-PREFLIGHT-PRESET @ DESK-AGENT-ACCESS-PRESET!
        AAP-S-OK = _C4-ASSERT
    _C4-PREFLIGHT-RUN-ID @
    _DESK-AGENT-RUNTIME @ ARUNTIME.MANDATE-FACTORY-DATA @
        _DESK-MANDATE-FACTORY
    _C4-PREFLIGHT-STATUS ! _C4-PREFLIGHT-RUN !
    _C4-PREFLIGHT-STATUS @ AMRUN-S-OK = _C4-ASSERT
    _C4-PREFLIGHT-RUN @ 0= IF EXIT THEN
    _C4-PREFLIGHT-RUN @ DUP _C4-MANDATE-RUN !
        AMRUN.FACET _C4-FACET !
    _C4-FACET-WITNESS
        _C4-PREFLIGHT-VALID ! _C4-PREFLIGHT-OPERATOR !
    _C4-PREFLIGHT-VALID @ _C4-ASSERT
    _C4-PREFLIGHT-PRESET @ AAP-PRESET-PRACTICE-LIBRARY-BURROW =
        _C4-PREFLIGHT-OPERATOR @ 0<> = _C4-ASSERT
    _C4-PREFLIGHT-RUN @ AMRUN-FREE
    0 _C4-PREFLIGHT-RUN ! 0 _C4-MANDATE-RUN ! 0 _C4-FACET ! ;

: _C4-PREFLIGHT-FACETS  ( -- )
    0 _C4-FACET-BITS !
    AAP-PRESET-CHAT-ONLY 4101 _C4-PREFLIGHT-ONE
    AAP-PRESET-PRACTICE-READ 4102 _C4-PREFLIGHT-ONE
    AAP-PRESET-PRACTICE-ASSIST 4103 _C4-PREFLIGHT-ONE
    AAP-PRESET-PRACTICE-LIBRARY-BURROW 4104 _C4-PREFLIGHT-ONE
    _C4-FACET-BITS @ 15 = _C4-ASSERT
    AAP-PRESET-PRACTICE-LIBRARY-BURROW DESK-AGENT-ACCESS-PRESET!
        AAP-S-OK = _C4-ASSERT
    ." DESK LIBRARY BURROW FACETS PASS" CR TX-FLUSH ;

: _C4-AGENT-INIT  ( instance -- )
    AGENT-INIT-CB
    _C4-PREFLIGHT-FACETS ;

\ ---------------------------------------------------------------------
\ Scripted provider override: one single-flight 8-of-12 product turn
\ ---------------------------------------------------------------------

VARIABLE _C4-PROVIDER
VARIABLE _C4-START-FAILS

32 CONSTANT _C4-STATE-WAIT-MAX

: _C4-DECLARATION-STATE@  ( -- state )
    _C4-GRAPH-STATE@ ;

: _C4-LIFECYCLE-READY?  ( -- ready? )
    _C4-CALL @ 5 = IF
        _C4-DECLARATION-STATE@ DUP SRBMGR-STATE-RUNNING = IF
            DROP ." DESK LIBRARY BURROW TICKS RUNNING "
                _C4-WAIT @ . CR TX-FLUSH -1 EXIT
        THEN
        SRBMGR-STATE-STARTING = _C4-ASSERT
        1 _C4-WAIT +!
        _C4-WAIT @ _C4-STATE-WAIT-MAX <= _C4-ASSERT
        0 EXIT
    THEN
    _C4-CALL @ 7 = IF
        _C4-DECLARATION-STATE@ DUP SRBMGR-STATE-STOPPED = IF
            DROP ." DESK LIBRARY BURROW TICKS STOPPED "
                _C4-WAIT @ . CR TX-FLUSH -1 EXIT
        THEN
        SRBMGR-STATE-STOPPING = _C4-ASSERT
        1 _C4-WAIT +!
        _C4-WAIT @ _C4-STATE-WAIT-MAX <= _C4-ASSERT
        0 EXIT
    THEN
    -1 ;

: _C4-ACTUAL-OPERATOR-FACET?  ( -- flag )
    _C4-FACET @ CFACET.COUNT @ 9 =
    _C4-BASE-OBSERVATIONS? AND
    _C4-LIBRARY-CHANGES? AND
    _C4-BURROW-CHANGES? AND
    _C4-LIBRARY-BROAD-READS-ABSENT? AND
    _C4-NO-EXTERNAL-EFFECTS? AND
    _C4-EXTERNAL-ABSENT? AND
    _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.TOOL-BUDGET @ 12 = AND
    _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.EFFECTS @
        _C4-LIVE-CHANGE-EFFECTS = AND
    _C4-MANDATE-RUN @ AMRUN.MANDATE MAND.DISPOSITION @
        MAND-D-COMMIT = AND ;

: _C4-START  ( turn queue context -- ior )
    _C4-CONTEXT ! _C4-QUEUE ! _C4-TURN !
    _C4-FAILS @ _C4-START-FAILS !
    _C4-TURN @ ATURN.TOOL-GATEWAY @ DUP 0<> _C4-ASSERT
    DUP 0= IF DROP 71 EXIT THEN
    ATOOLG.MANDATE-RUN @ DUP _C4-MANDATE-RUN !
    DUP AMRUN-ACTIVE? _C4-ASSERT
    AMRUN.FACET _C4-FACET !
    _C4-ACTUAL-OPERATOR-FACET? _C4-ASSERT
    _C4-FACET-BITS @ 15 = _C4-ASSERT
    _C4-FAILS @ _C4-START-FAILS @ <> IF 72 EXIT THEN
    0 _C4-CALL ! 0 _C4-WAIT ! -1 _C4-OPERATOR ! 0 _C4-DONE !
    ." DESK LIBRARY BURROW OPERATOR RUN FROZEN PASS" CR TX-FLUSH
    _C4-TURN @ _C4-QUEUE @ _C4-CONTEXT @ _SCRIPTED-START ;

: _C4-POLL  ( queue context -- ior )
    _C4-CONTEXT ! _C4-QUEUE !
    _C4-CONTEXT @ _SPC.STATE @ _SP-STREAMING <> IF 0 EXIT THEN
    _C4-OPERATOR @ 0= IF 73 EXIT THEN
    _C4-FAILS @ _C4-START-FAILS !
    _C4-LIFECYCLE-READY? 0= IF
        _C4-FAILS @ _C4-START-FAILS @ <> IF 74 ELSE 0 THEN EXIT
    THEN
    _C4-PROGRESS-READY? 0= IF
        _C4-FAILS @ _C4-START-FAILS @ <> IF 75 ELSE 0 THEN EXIT
    THEN
    _C4-CALL @ 8 < IF _C4-EMIT-CALL ELSE 0 THEN ;

: _C4-RESULT-MARKER  ( -- )
    ." DESK LIBRARY BURROW RESULT " _C4-CALL @ 1+ .
    _C4-CAP$ TYPE ."  PASS" CR TX-FLUSH ;

: _C4-FINISH-OPERATOR  ( -- ior )
    _C4-MANDATE-RUN @ AMRUN.TOOLS-USED @
        _C4-EXPECTED-TOOLS = _C4-ASSERT
    _C4-FACET-BITS @ 15 = _C4-ASSERT
    AEV-TEXT-DELTA 0 0
        S" Library Burrow orchestration complete."
        _C4-QUEUE @ _C4-CONTEXT @ _SCRIPTED-EMIT ?DUP IF EXIT THEN
    _C4-QUEUE @ _C4-CONTEXT @ _SCRIPTED-FINISH-MESSAGE
    DUP 0= IF
        _SP-IDLE _C4-CONTEXT @ _SPC.STATE !
        -1 _C4-DONE !
        ." DESK LIBRARY BURROW AGENT PASS" CR TX-FLUSH
    THEN ;

: _C4-RESULT-ADVANCE  ( -- ior )
    _C4-RESULT-VALUE @ _SPT-V !
    _C4-QUEUE @ _SPP-Q ! _C4-CONTEXT @ _SPP-C !
    _SCRIPTED-TOOL-VALUE ?DUP IF EXIT THEN
    _C4-RESULT-MARKER
    _C4-CALL @ 4 = IF 0 _C4-WAIT ! THEN
    _C4-CALL @ 6 = IF 0 _C4-WAIT ! THEN
    1 _C4-CALL +!
    _C4-CALL @ 8 = IF _C4-FINISH-OPERATOR EXIT THEN
    _SP-STREAMING _C4-CONTEXT @ _SPC.STATE !
    0 ;

: _C4-TOOL-RESULT
  ( run-id name-a name-u value status queue context -- ior )
    _C4-CONTEXT ! _C4-QUEUE ! _C4-RESULT-STATUS !
    _C4-RESULT-VALUE ! _C4-RESULT-NAME-U ! _C4-RESULT-NAME-A !
    _C4-RESULT-RUN !
    _C4-RESULT-RUN @ _C4-CONTEXT @ _SPC.RUN-ID @ =
        DUP _C4-ASSERT 0= IF 81 EXIT THEN
    _C4-CONTEXT @ _SPC.STATE @ _SP-WAITING =
        DUP _C4-ASSERT 0= IF 82 EXIT THEN
    _C4-CALL @ DUP 0>= SWAP 8 < AND
        DUP _C4-ASSERT 0= IF 83 EXIT THEN
    _C4-RESULT-NAME-A @ _C4-RESULT-NAME-U @ _C4-CAP$ STR-STR=
        DUP _C4-ASSERT 0= IF 84 EXIT THEN
    _C4-RESULT-STATUS @ CBUS-RESULT-BEARING?
        DUP _C4-ASSERT 0= IF 85 EXIT THEN
    _C4-RESULT-OBSERVE
    _C4-RESULT-OVERRIDE IF EXIT THEN DROP
    _C4-RESULT-STATUS @ CBUS-S-OK =
        DUP _C4-ASSERT 0= IF 86 EXIT THEN
    _C4-FAILS @ _C4-RESULT-N !
    _C4-CAPTURE-RESULT
    _C4-FAILS @ _C4-RESULT-N @ <> IF 87 EXIT THEN
    _C4-RESULT-ADVANCE ;

: _C4-PROVIDER-FREE  ( provider -- )
    DUP _C4-PROVIDER @ = _C4-ASSERT
    -1 _C4-PROVIDER-FREED !
    0 _C4-PROVIDER !
    SCRIPTED-PROVIDER-FREE ;

: _C4-PROVIDER-NEW  ( -- provider ior )
    SCRIPTED-PROVIDER-NEW DUP IF EXIT THEN
    DROP DUP _C4-PROVIDER !
    DUP ['] _C4-START SWAP APROV.START-XT !
    DUP ['] _C4-POLL SWAP APROV.POLL-XT !
    DUP ['] _C4-TOOL-RESULT SWAP APROV.TOOL-RESULT-XT !
    DUP ['] _C4-PROVIDER-FREE SWAP APROV.FREE-XT !
    0 ;

: _C4-SOURCE-CREATE  ( context -- provider status )
    DROP _C4-PROVIDER-NEW ;

\ ---------------------------------------------------------------------
\ F12 outer-close seam.  Posting is essential: a synchronous ASHELL-QUIT
\ inside a child event is intentionally intercepted by AHOST and becomes a
\ close request for only that child.  The posted request reaches the outer
\ app-shell loop and therefore exercises Desk request-close and shutdown.
\ ---------------------------------------------------------------------

VARIABLE _C4-QUIT-POSTED
VARIABLE _C4-QUIT-REQUESTED
VARIABLE _C4-EVENT-PTR
VARIABLE _C4-EVENT-INSTANCE

: _C4-RUNTIME-IDLE?  ( -- flag )
    _DESK-AGENT-RUNTIME @ DUP 0= IF DROP 0 EXIT THEN
    ARUNTIME-BUSY? 0=
    _DESK-TOOL-GATEWAY @ DUP 0<> IF
        ATOOLG.STATE @ ATOOLG-S-IDLE =
    ELSE
        DROP 0
    THEN AND ;

: _C4-REQUEST-OUTER-QUIT  ( -- )
    _C4-DONE @ _C4-ASSERT
    _C4-RUNTIME-IDLE? _C4-ASSERT
    _C4-FAILS @ IF EXIT THEN
    -1 _C4-QUIT-REQUESTED !
    ." DESK LIBRARY BURROW OUTER QUIT REQUEST" CR TX-FLUSH
    ASHELL-QUIT ;

: _C4-AGENT-EVENT  ( event instance -- handled? )
    _C4-EVENT-INSTANCE ! _C4-EVENT-PTR !
    _C4-EVENT-PTR @ @ KEY-T-SPECIAL =
    _C4-EVENT-PTR @ 8 + @ KEY-F12 = AND IF
        _C4-DONE @ _C4-RUNTIME-IDLE? AND IF
            _C4-QUIT-POSTED @ 0= IF
                -1 _C4-QUIT-POSTED !
                ['] _C4-REQUEST-OUTER-QUIT ASHELL-POST
                ." DESK LIBRARY BURROW F12 ARMED" CR TX-FLUSH
            THEN
        ELSE
            ." DESK LIBRARY BURROW F12 NOT READY" CR TX-FLUSH
        THEN
        -1 EXIT
    THEN
    _C4-EVENT-PTR @ _C4-EVENT-INSTANCE @ AGENT-EVENT-CB ;

\ ---------------------------------------------------------------------
\ Public profile entry words and Python-facing witness accessors
\ ---------------------------------------------------------------------

CREATE _C4-LIBRARY-DESC APP-DESC ALLOT
CREATE _C4-STREAMS-DESC APP-DESC ALLOT
CREATE _C4-AGENT-DESC APP-DESC ALLOT

: DESK-LIBRARY-BURROW-CALL@  ( -- count ) _C4-CALL @ ;
: DESK-LIBRARY-BURROW-FACETS@  ( -- bits ) _C4-FACET-BITS @ ;
: DESK-LIBRARY-BURROW-FAILS@  ( -- count ) _C4-FAILS @ ;
: DESK-LIBRARY-BURROW-DONE?  ( -- flag ) _C4-DONE @ ;
: DESK-LIBRARY-BURROW-LEASE?  ( -- flag )
    _C4-GRAPH-LEASE? ;

: _C4-SOURCE-FREE  ( source -- )
    DUP _C4-SOURCE @ = _C4-ASSERT
    _C4-PROVIDER-FREED @ _C4-ASSERT
    -1 _C4-SOURCE-FREED ! 0 _C4-SOURCE !
    SCRIPTED-SOURCE-FREE ;

: _C4-CONFIGURE-SOURCE  ( -- )
    SCRIPTED-SOURCE-NEW 0<> ABORT" checkpoint4 source allocation failed"
    DUP _C4-SOURCE !
    DUP ['] _C4-SOURCE-CREATE SWAP APSOURCE.NEW-XT !
    DUP ['] _C4-SOURCE-FREE SWAP APSOURCE.FREE-XT !
    DESK-AGENT-SOURCE! ;

: _C4-CONFIGURE-DESCRIPTORS  ( -- )
    _C4-LIBRARY-DESC LIBRARY-APPLET-ENTRY
    ['] _C4-LIBRARY-SHUTDOWN
        _C4-LIBRARY-DESC APP.SHUTDOWN-XT !

    _C4-STREAMS-DESC STREAMS-ENTRY
    ['] _C4-STREAMS-INIT _C4-STREAMS-DESC APP.INIT-XT !
    ['] _C4-STREAMS-SHUTDOWN
        _C4-STREAMS-DESC APP.SHUTDOWN-XT !

    _C4-AGENT-DESC AGENT-ENTRY
    ['] _C4-AGENT-INIT _C4-AGENT-DESC APP.INIT-XT !
    ['] _C4-AGENT-EVENT _C4-AGENT-DESC APP.EVENT-XT !
    ['] _C4-AGENT-SHUTDOWN _C4-AGENT-DESC APP.SHUTDOWN-XT ! ;

: DESK-LIBRARY-BURROW-CONFIGURE  ( -- )
    _C4-INSTALL-COMPOSITION
    DEPTH _C4-DEPTH !
    0 _C4-CHECKS ! 0 _C4-FAILS !
    0 _C4-FACET-BITS ! 0 _C4-CALL ! 0 _C4-WAIT !
    0 _C4-OPERATOR ! 0 _C4-DONE !
    0 _C4-QUIT-POSTED ! 0 _C4-QUIT-REQUESTED !
    0 _C4-LIBRARY-SHUTDOWNS ! 0 _C4-STREAMS-SHUTDOWNS !
    0 _C4-AGENT-SHUTDOWNS ! 0 _C4-PROVIDER-FREED !
    0 _C4-SOURCE ! 0 _C4-SOURCE-FREED !
    0 _C4-PROVIDER ! 0 _C4-STREAMS-INSTANCE ! 0 _C4-STREAMS-STATE !
    _C4-DOCUMENT-REF RREF-INIT
    _C4-COLLECTION-REF RREF-INIT
    _C4-BURROW-REF RREF-INIT
    _C4-TEMP-REF RREF-INIT
    _C4-REQUEST-DIGEST SHA3-256-HEX-LEN 0 FILL
    \ Capture before the composition hook: later checkpoints may allocate a
    \ caller-owned graph here and must return it before the final witness.
    _C4-AVAILABLE _C4-AVAILABLE-BASELINE !
    _C4-GRAPH-CONFIGURE
    _STM-BURROW-BUILD? _C4-ASSERT
    _C4-CONFIGURE-SOURCE
    _C4-CONFIGURE-DESCRIPTORS
    STREAMS-COMP-DESC COMP.CAPS-N @ 19 = _C4-ASSERT
    AAP-PRESET-PRACTICE-LIBRARY-BURROW
        DESK-AGENT-ACCESS-PRESET! AAP-S-OK = _C4-ASSERT
    _C4-LIBRARY-DESC DESK-QUEUE-LAUNCH
    _C4-STREAMS-DESC DESK-QUEUE-LAUNCH
    _C4-AGENT-DESC DESK-QUEUE-LAUNCH
    _C4-STACK
    _C4-FAILS @ IF
        ." DESK LIBRARY BURROW FAIL CONFIGURE" CR
    ELSE
        ." DESK LIBRARY BURROW CONFIGURED" CR
    THEN TX-FLUSH ;

: _C4-POST-RUN-CHECKS  ( -- )
    _C4-FACET-BITS @ 15 = _C4-ASSERT
    _C4-CALL @ 8 = _C4-ASSERT
    _C4-DONE @ _C4-ASSERT
    _C4-QUIT-POSTED @ _C4-ASSERT
    _C4-QUIT-REQUESTED @ _C4-ASSERT
    _C4-LIBRARY-SHUTDOWNS @ 1 = _C4-ASSERT
    _C4-STREAMS-SHUTDOWNS @ 1 = _C4-ASSERT
    _C4-AGENT-SHUTDOWNS @ 1 = _C4-ASSERT
    _C4-PROVIDER-FREED @ _C4-ASSERT
    _C4-PROVIDER @ 0= _C4-ASSERT
    _C4-SOURCE-FREED @ _C4-ASSERT
    _C4-SOURCE @ 0= _C4-ASSERT
    _C4-GRAPH-POST-CHECK
    _C4-STREAMS-INSTANCE @ 0= _C4-ASSERT
    _C4-STREAMS-STATE @ 0= _C4-ASSERT
    _DESK-CURRENT-STATE @ 0= _C4-ASSERT
    ASHELL-DESC 0= _C4-ASSERT
    ASHELL-INSTANCE 0= _C4-ASSERT
    ASHELL-ACTIVE-CTX 0= _C4-ASSERT
    _C4-AVAILABLE _C4-AVAILABLE-BASELINE @ = DUP _C4-ASSERT IF
        ." DESK LIBRARY BURROW ALLOCATION PASS" CR TX-FLUSH
    THEN ;

: DESK-LIBRARY-BURROW-RUN  ( -- )
    DESK-RUN
    _C4-POST-RUN-CHECKS
    _C4-STACK
    _C4-FAILS @ 0= IF
        ." DESK LIBRARY BURROW PASS " _C4-CHECKS @ . CR
    ELSE
        ." DESK LIBRARY BURROW FAIL " _C4-FAILS @ .
        ." / " _C4-CHECKS @ . CR
    THEN TX-FLUSH ;
