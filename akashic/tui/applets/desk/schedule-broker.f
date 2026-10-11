\ =====================================================================
\  schedule-broker.f - Desk's broker for scheduled actions
\ =====================================================================
\  The broker starts the scheduled work Daybook hands over, and only
\  work a user approved.  It keeps the schedule permissions
\  (runtime/schedule-permission.f) in Desk's Practice filesystem, and
\  gives Daybook's service a dispatch client (interop/scheduled-
\  dispatch.f) through which Daybook asks for approvals, hands runs over,
\  and follows them to their end.  A handler Desk sets starts the runs.
\
\  A run is checked when it is handed over and again when it starts: its
\  request must be well formed and match exactly a permission Desk's
\  Practice holds.  The broker then compiles the run's authority from that
\  permission alone, never from a chat preset: a child of the Practice's
\  root Context, a capability facet with no entries, and a read-only
\  Mandate with the permission's time and disclosure limits and no tool
\  budget.  The handler owns that authority only once the run started.
\
\  The handler runs one thing at a time.  A run it cannot start yet waits
\  in the broker, in the order runs were handed over, and the handler
\  keeps its place in line so nothing else goes first.  Each tick starts
\  the first waiting run once the handler is idle, checking it again, so
\  revoking or changing its permission meanwhile stops it.
\
\  The broker remembers the runs of this session until Daybook hears how
\  they ended; the handler keeps the record of each run it started.
\  Revoking a permission cancels the runs in flight under it, and closing
\  the broker cancels every run in flight.
\
\  Approvals wait for Desk's user in the order they were asked for.  Desk
\  shows the oldest, with the reason the handler says it could not run
\  it, and the user's answer grants the permission or refuses it.  An
\  approval asked for again for the same schedule withdraws the one
\  before.
\
\  The broker is caller-serialized; Desk calls it from its own loop.
\
\  Public API:
\    SBRK-SIZE          ( -- bytes )
\    SBRK-INIT          ( vfs head context broker -- status )
\    SBRK-FINI          ( broker -- )
\    SBRK-VALID?        ( broker -- flag )
\    SBRK-STORE         ( broker -- store )
\    SBRK-CLIENT        ( broker -- client )
\    SBRK-HANDLER!      ( handler broker -- )
\    SBRK-TICK          ( broker -- )
\    SBRK-ASKING        ( broker -- id request | 0 0 )
\    SBRK-ANSWER        ( id allowed? now broker -- status )
\    SBRK-VET           ( request broker -- reason|0 )
\    SBRK-REVOKE        ( rid broker -- status )
\    SBRK-ACTIVE?       ( broker -- flag )
\
\    SBRK-HANDLER-SIZE  ( -- bytes )
\    SBRK-HANDLER-INIT  ( context handler -- )
\    SBRK-H.START-XT SBRK-H.STATUS-XT SBRK-H.CANCEL-XT
\    SBRK-H.MODELS-XT SBRK-H.IDLE-XT SBRK-H.VET-XT    ( handler -- a )
\ =====================================================================

PROVIDED akashic-desk-sched-broker

REQUIRE ../../../runtime/schedule-permission.f
REQUIRE ../../../interop/policy.f
REQUIRE ../agent/service.f

\ =====================================================================
\  The handler
\ =====================================================================
\  Desk fills a handler record and sets it on the broker.  Its words:
\
\    start   ( request run response context -- status )
\    status  ( key response context -- status )
\    cancel  ( key reason context -- status )
\    models  ( buffer capacity context -- bytes status )
\    idle?   ( context -- flag )
\    vet     ( request context -- reason|0 )
\
\  START starts the run REQUEST asks for, under RUN, the authority the
\  broker compiled for it, and answers as STATUS would after it:
\  - STARTED: the run started, RESPONSE names it, and the handler owns
\    RUN;
\  - WAITING: it cannot start a run now, and keeps this one's place in
\    line until START or CANCEL names its dispatch key again;
\  - RUNNING, ENDED or SMALL: a run with that dispatch key exists;
\  - ENDED: it refused, and RESPONSE says why.
\  Any other answer means it could not answer.  RUN stays the broker's
\  unless the answer is STARTED.
\
\  STATUS, CANCEL and MODELS answer as the dispatch client's words; a
\  response names the run's permission.  CANCEL ends a run for REASON,
\  or gives up a waiting run's place.  IDLE? says whether START could
\  start a run now.  VET says why the handler could not run REQUEST, an
\  approval's, which names no occurrence: an SACT-R- reason, or 0.

0x4C444E484B524253 CONSTANT _SBRK-H-MAGIC   \ "SBRKHNDL"

 0 CONSTANT _SBH-MAGIC
 8 CONSTANT _SBH-SELF
16 CONSTANT _SBH-CONTEXT
24 CONSTANT _SBH-START
32 CONSTANT _SBH-STATUS
40 CONSTANT _SBH-CANCEL
48 CONSTANT _SBH-MODELS
56 CONSTANT _SBH-IDLE
64 CONSTANT _SBH-VET
72 CONSTANT SBRK-HANDLER-SIZE

: SBRK-H.START-XT   ( handler -- a ) _SBH-START + ;
: SBRK-H.STATUS-XT  ( handler -- a ) _SBH-STATUS + ;
: SBRK-H.CANCEL-XT  ( handler -- a ) _SBH-CANCEL + ;
: SBRK-H.MODELS-XT  ( handler -- a ) _SBH-MODELS + ;
: SBRK-H.IDLE-XT    ( handler -- a ) _SBH-IDLE + ;
: SBRK-H.VET-XT     ( handler -- a ) _SBH-VET + ;

\ A handler for CONTEXT with no words yet.
: SBRK-HANDLER-INIT  ( context handler -- )
    DUP SBRK-HANDLER-SIZE 0 FILL
    _SBRK-H-MAGIC OVER _SBH-MAGIC + !
    DUP DUP _SBH-SELF + !
    _SBH-CONTEXT + ! ;

: _SBRK-HANDLER?  ( handler -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SBH-MAGIC + @ _SBRK-H-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBH-SELF + @ = ;

\ =====================================================================
\  The broker
\ =====================================================================

0x524B52424B524253 CONSTANT _SBRK-MAGIC     \ "SBRKBRKR"

  0 CONSTANT _SBRK-MAGIC-OFF
  8 CONSTANT _SBRK-SELF
 16 CONSTANT _SBRK-HEAD        \ the Practice head
 24 CONSTANT _SBRK-ROOT        \ its root Context
 32 CONSTANT _SBRK-HANDLER     \ the handler, or 0
 40 CONSTANT _SBRK-RUNS        \ the first run, or 0
 48 CONSTANT _SBRK-ASKS        \ the first approval, or 0
 56 CONSTANT _SBRK-ASK-ID      \ the latest approval's id
\ Scratch while an authority is compiled.
 64 CONSTANT _SBRK-CHILD
 72 CONSTANT _SBRK-P           \ the permission
 80 CONSTANT _SBRK-Q           \ the request
 88 CONSTANT _SBRK-CLIENT
_SBRK-CLIENT SDSP-CLIENT-SIZE + CONSTANT _SBRK-RESPONSE   \ with no summary
_SBRK-RESPONSE 0 SDSP-RESPONSE-SIZE + CONSTANT _SBRK-MANDATE
_SBRK-MANDATE MAND-SIZE + CONSTANT _SBRK-FACET
_SBRK-FACET CFACET-SIZE + 7 + -8 AND CONSTANT _SBRK-STORE
_SBRK-STORE SPERM-SIZE + CONSTANT SBRK-SIZE

: _SBRK.MAGIC     ( broker -- a ) _SBRK-MAGIC-OFF + ;
: _SBRK.SELF      ( broker -- a ) _SBRK-SELF + ;
: _SBRK.HEAD      ( broker -- a ) _SBRK-HEAD + ;
: _SBRK.ROOT      ( broker -- a ) _SBRK-ROOT + ;
: _SBRK.HANDLER   ( broker -- a ) _SBRK-HANDLER + ;
: _SBRK.RUNS      ( broker -- a ) _SBRK-RUNS + ;
: _SBRK.ASKS      ( broker -- a ) _SBRK-ASKS + ;
: _SBRK.ASK-ID    ( broker -- a ) _SBRK-ASK-ID + ;
: _SBRK.CHILD     ( broker -- a ) _SBRK-CHILD + ;
: _SBRK.P         ( broker -- a ) _SBRK-P + ;
: _SBRK.Q         ( broker -- a ) _SBRK-Q + ;
: SBRK-CLIENT     ( broker -- client ) _SBRK-CLIENT + ;
: _SBRK.RESPONSE  ( broker -- response ) _SBRK-RESPONSE + ;
: _SBRK.MANDATE   ( broker -- mandate ) _SBRK-MANDATE + ;
: _SBRK.FACET     ( broker -- facet ) _SBRK-FACET + ;
: SBRK-STORE      ( broker -- store ) _SBRK-STORE + ;

: SBRK-VALID?  ( broker -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SBRK.MAGIC @ _SBRK-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBRK.SELF @ = ;

\ Desk's Practice.
: _SBRK-PRACTICE  ( broker -- rid ) _SBRK.HEAD @ PHEAD.ID ;

\ The handler that starts runs, or 0 for none.
: SBRK-HANDLER!  ( handler broker -- ) _SBRK.HANDLER ! ;

\ ---------------------------------------------------------------------
\  Calling the handler
\ ---------------------------------------------------------------------

\ The handler's word at SLOT and its context; 0 when there is none.
: _SBRK-H-WORD  ( broker slot -- context xt | 0 )
    SWAP _SBRK.HANDLER @ DUP _SBRK-HANDLER? 0= IF 2DROP 0 EXIT THEN
    TUCK + @ DUP 0= IF NIP EXIT THEN
    SWAP _SBH-CONTEXT + @ SWAP ;

: _SBRK-H-START  ( request run response broker -- status )
    _SBH-START _SBRK-H-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP DROP SDSP-S-UNAVAILABLE ;

: _SBRK-H-STATUS  ( key response broker -- status )
    _SBH-STATUS _SBRK-H-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP SDSP-S-UNAVAILABLE ;

: _SBRK-H-CANCEL  ( key reason broker -- status )
    _SBH-CANCEL _SBRK-H-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP SDSP-S-UNAVAILABLE ;

: _SBRK-H-MODELS  ( buffer capacity broker -- bytes status )
    _SBH-MODELS _SBRK-H-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP 0 SDSP-S-UNAVAILABLE ;

: _SBRK-H-IDLE?  ( broker -- flag )
    _SBH-IDLE _SBRK-H-WORD ?DUP IF EXECUTE EXIT THEN
    0 ;

: _SBRK-H-VET  ( request broker -- reason|0 )
    _SBH-VET _SBRK-H-WORD ?DUP IF EXECUTE EXIT THEN
    DROP SACT-R-AGENT-UNAVAILABLE ;

\ ---------------------------------------------------------------------
\  Lists
\ ---------------------------------------------------------------------
\  Runs and approvals are allocated nodes whose first cell links the
\  next, in the order they came.

\ Appends NODE to the list whose first node the cell at LIST holds.
: _SBRK-APPEND  ( node list -- )
    0 2 PICK !
    BEGIN DUP @ ?DUP WHILE NIP REPEAT
    ! ;

\ Takes NODE off the list at LIST, if it is on it.
: _SBRK-UNLINK  ( node list -- )
    BEGIN DUP @ ?DUP WHILE                       ( node cell next )
        DUP 3 PICK = IF DROP SWAP @ SWAP ! EXIT THEN
        NIP
    REPEAT
    2DROP ;

\ =====================================================================
\  Runs
\ =====================================================================

1 CONSTANT _SBRK-QUEUED      \ waits to start; the broker holds its request
2 CONSTANT _SBRK-STARTED     \ the handler has it
3 CONSTANT _SBRK-ENDED       \ the broker ended it; Daybook has not heard

\ A run:
\    +0 next   +8 state   +16 outcome   +24 reason   +32 dispatch key
\   +64 permission RID   +96 its revision   +104 a copy of the request
\       while it waits, or 0
: _SBR.STATE       ( run -- a ) 8 + ;
: _SBR.OUTCOME     ( run -- a ) 16 + ;
: _SBR.REASON      ( run -- a ) 24 + ;
: _SBR.KEY         ( run -- key ) 32 + ;
: _SBR.PERMISSION  ( run -- rid ) 64 + ;
: _SBR.REVISION    ( run -- a ) 96 + ;
: _SBR.REQUEST     ( run -- a ) 104 + ;
112 CONSTANT _SBR-SIZE

\ The run with dispatch KEY, or 0.
: _SBRK-RUN  ( key broker -- run|0 )
    _SBRK.RUNS @
    BEGIN DUP WHILE
        2DUP _SBR.KEY RID= IF NIP EXIT THEN
        @
    REPEAT
    NIP ;

\ A run for REQUEST's dispatch key and permission, on no list; 0 when
\ memory ran out.
: _SBRK-NEW-RUN  ( request -- run|0 )
    _SBR-SIZE ALLOCATE IF 2DROP 0 EXIT THEN        ( request run )
    DUP _SBR-SIZE 0 FILL
    OVER SDSP-R.KEY OVER _SBR.KEY RID-COPY
    OVER SDSP-R.PERMISSION OVER _SBR.PERMISSION RID-COPY
    SWAP SDSP-R.PERMISSION-REVISION @ OVER _SBR.REVISION ! ;

\ A copy of REQUEST, or 0 when memory ran out.
: _SBRK-COPY  ( request -- copy|0 )
    DUP SDSP-REQUEST-U DUP ALLOCATE IF DROP 2DROP 0 EXIT THEN
    DUP >R SWAP MOVE R> ;

\ Takes RUN off the list and frees it, with the request it holds.
: _SBRK-DROP  ( run broker -- )
    OVER SWAP _SBRK.RUNS _SBRK-UNLINK
    DUP _SBR.REQUEST @ ?DUP IF FREE THEN
    FREE ;

\ Fills RESPONSE with a run the broker ended: OUTCOME for REASON, under
\ the permission at PERMISSION and REVISION, with no run and no summary.
: _SBRK-END!  ( outcome reason permission revision response broker -- )
    _SBRK-PRACTICE OVER SDSP-P.PRACTICE RID-COPY
    TUCK SDSP-P.PERMISSION-REVISION !
    TUCK SDSP-P.PERMISSION RID-COPY
    DUP SDSP-P.RUN RID-CLEAR
    0 OVER SDSP-P.SUMMARY-U !
    TUCK SDSP-P.REASON ! SDSP-P.OUTCOME ! ;

\ Ends REQUEST's run before it started, into RESPONSE: OUTCOME for
\ REASON, under the permission the request names.
: _SBRK-REFUSE  ( request response outcome reason broker -- status )
    >R 3 PICK SDSP-R.PERMISSION 4 PICK SDSP-R.PERMISSION-REVISION @
    4 PICK R> _SBRK-END! 2DROP SDSP-S-ENDED ;

\ Fills RESPONSE with how the broker ended RUN.
: _SBRK-TELL  ( run response broker -- )
    >R >R
    DUP _SBR.OUTCOME @ OVER _SBR.REASON @ 2 PICK _SBR.PERMISSION
    3 PICK _SBR.REVISION @ R> R> _SBRK-END! DROP ;

\ Ends RUN, which waits, at the broker: OUTCOME for REASON.  The handler
\ gives up its place in line.
: _SBRK-QUIT  ( run outcome reason broker -- )
    >R ROT
    TUCK _SBR.REASON ! TUCK _SBR.OUTCOME !
    _SBRK-ENDED OVER _SBR.STATE !
    DUP _SBR.KEY SWAP _SBR.REASON @ R> _SBRK-H-CANCEL DROP ;

\ Stops RUN for REASON: one waiting ends at the broker with OUTCOME, and
\ the handler cancels one started.
: _SBRK-STOP  ( run outcome reason broker -- )
    3 PICK _SBR.STATE @ DUP _SBRK-QUEUED = IF DROP _SBRK-QUIT EXIT THEN
    _SBRK-STARTED = IF
        >R NIP SWAP _SBR.KEY SWAP R> _SBRK-H-CANCEL DROP EXIT
    THEN
    2DROP 2DROP ;

\ How RUN stands, into RESPONSE.  Daybook hears once how a run ended,
\ and the broker then forgets it.
: _SBRK-STANDS  ( run response broker -- status )
    >R OVER _SBR.STATE @
    DUP _SBRK-QUEUED = IF DROP 2DROP R> DROP SDSP-S-WAITING EXIT THEN
    _SBRK-ENDED = IF
        OVER SWAP R@ _SBRK-TELL R> _SBRK-DROP SDSP-S-ENDED EXIT
    THEN
    OVER _SBR.KEY SWAP R@ _SBRK-H-STATUS               ( run status )
    DUP SDSP-S-ENDED = OVER SDSP-S-UNKNOWN = OR IF
        SWAP R> _SBRK-DROP EXIT
    THEN
    NIP R> DROP ;

\ ---------------------------------------------------------------------
\  Standing
\ ---------------------------------------------------------------------

\ Whether the limits PERMISSION grants are those REQUEST's operands
\ carry.  The operand digest binds both, so they differ only when the
\ permission file was altered past its checks.
: _SBRK-LIMITS?  ( request permission -- flag )
    SWAP SDSP-OPERANDS$ DROP                        ( p operands )
    OVER SPERM-P.EFFECTS @ OVER SACT-O.EFFECTS @ =
    2 PICK SPERM-P.TIME @ 2 PICK SACT-O.TIME @ = AND
    2 PICK SPERM-P.DISCLOSURE @ 2 PICK SACT-O.DISCLOSURE @ = AND
    2 PICK SPERM-P.OUTPUT @ 2 PICK SACT-O.OUTPUT @ = AND
    NIP NIP ;

\ How REQUEST stands in Desk's Practice: as SPERM-MATCH answers, except
\ that a permission whose limits are not the request's has changed.
: _SBRK-STANDING  ( request broker -- standing )
    OVER OVER _SBRK-PRACTICE 2 PICK SBRK-STORE SPERM-MATCH
    DUP SDSP-A-APPROVED <> IF NIP NIP EXIT THEN
    DROP OVER SDSP-R.PERMISSION SWAP SBRK-STORE SPERM-FIND
    _SBRK-LIMITS? IF SDSP-A-APPROVED ELSE SDSP-A-CHANGED THEN ;

\ The reason a run is blocked for, by a standing other than approved.
: _SBRK-REFUSAL  ( standing -- reason )
    CASE
        SDSP-A-NONE      OF SACT-R-NOT-APPROVED ENDOF
        SDSP-A-WITHDRAWN OF SACT-R-REVOKED ENDOF
        SDSP-A-CHANGED   OF SACT-R-CHANGED ENDOF
        SDSP-A-PRACTICE  OF SACT-R-PRACTICE ENDOF
        >R SACT-R-AGENT-UNAVAILABLE R>
    ENDCASE ;

\ ---------------------------------------------------------------------
\  A run's authority
\ ---------------------------------------------------------------------

\ The ID TAG names in the authority for the run with dispatch KEY in
\ CHILD, into DEST: SHA3-256 of the Practice, the activation's epoch, the
\ key, the child Context's identity, and the tag.
: _SBRK-ID!  ( tag-a tag-u key child broker dest -- )
    >R
    SHA3-256-BEGIN
    DUP _SBRK-PRACTICE RID-SIZE SHA3-256-ADD
    _SBRK.ROOT @ CTX.EPOCH 8 SHA3-256-ADD
    SWAP 32 SHA3-256-ADD
    CTX.ID 16 SHA3-256-ADD
    SHA3-256-ADD
    R> SHA3-256-END ;

\ Compiles the authority for REQUEST's run from PERMISSION alone: a
\ child of the Practice's root Context, a facet with no entries, and a
\ read-only Mandate with the permission's effects, time and disclosure
\ limits and no tool budget.  The run owns the child Context.
: _SBRK-COMPILE  ( request permission broker -- run status )
    >R R@ _SBRK.P ! R@ _SBRK.Q !
    R@ _SBRK.ROOT @ CTX-CHILD-NEW ?DUP IF
        NIP R> DROP
        CTX-E-NOMEM = IF AMRUN-S-NOMEM ELSE AMRUN-S-INVALID THEN 0 SWAP EXIT
    THEN
    DUP R@ _SBRK.CHILD !
    CTX.FLAGS DUP @ CTX-F-ACTIVE OR SWAP !

    R@ _SBRK.FACET DUP CFACET-INIT
    S" desk.schedule.facet" R@ _SBRK.Q @ SDSP-R.KEY R@ _SBRK.CHILD @ R@
        5 PICK CFACET.ID _SBRK-ID!
    R@ _SBRK-PRACTICE OVER CFACET.PRACTICE-ID RID-COPY
    R@ _SBRK.ROOT @ CTX.EPOCH @ OVER CFACET.EPOCH !
    R@ _SBRK.CHILD @ CTX.ID @ OVER CFACET.CONTEXT-ID !
    R@ _SBRK.CHILD @ CTX.GENERATION @ OVER CFACET.CONTEXT-GEN !
    1 SWAP CFACET.REVISION !

    R@ _SBRK.MANDATE DUP MAND-INIT
    S" desk.schedule.mandate" R@ _SBRK.Q @ SDSP-R.KEY R@ _SBRK.CHILD @ R@
        5 PICK MAND.ID _SBRK-ID!
    R@ _SBRK-PRACTICE OVER MAND.PRACTICE-ID RID-COPY
    R@ _SBRK.FACET CFACET.ID OVER MAND.INPUT-FACET-ID RID-COPY
    R@ _SBRK.FACET CFACET.ID OVER MAND.DISCLOSURE-FACET-ID RID-COPY
    R@ _SBRK.ROOT @ CTX.EPOCH @ OVER MAND.ACTIVATION-EPOCH !
    CPRINC-AGENT OVER MAND.PRINCIPAL !
    R@ _SBRK.CHILD @ CTX.ID @ OVER MAND.CONTEXT-ID !
    R@ _SBRK.CHILD @ CTX.GENERATION @ OVER MAND.CONTEXT-GENERATION !
    R@ _SBRK.P @ SPERM-P.EFFECTS @ OVER MAND.EFFECTS !
    MAND-D-READ-ONLY OVER MAND.DISPOSITION !
    R@ _SBRK.P @ SPERM-P.TIME @ OVER MAND.TIME-BUDGET-MS !
    R@ _SBRK.P @ SPERM-P.DISCLOSURE @ SWAP MAND.DISCLOSURE-BUDGET !

    R@ _SBRK.HEAD @ R@ _SBRK.CHILD @ R@ _SBRK.MANDATE R@ _SBRK.FACET AMRUN-NEW
    DUP IF R@ _SBRK.CHILD @ CTX-FREE THEN
    R> DROP ;

\ ---------------------------------------------------------------------
\  Starting runs
\ ---------------------------------------------------------------------

\ Tries to start the run REQUEST asks for: checks that its permission
\ stands, compiles its authority from that permission, and offers it to
\ the handler.  Returns the handler's answer, which fills RESPONSE, or
\ ENDED with RESPONSE saying why the run got no further.
: _SBRK-TRY  ( request response broker -- status )
    >R
    OVER R@ _SBRK-STANDING DUP SDSP-A-APPROVED <> IF
        _SBRK-REFUSAL SACT-O-BLOCKED SWAP R> _SBRK-REFUSE EXIT
    THEN
    DROP
    OVER DUP SDSP-R.PERMISSION R@ SBRK-STORE SPERM-FIND R@ _SBRK-COMPILE
    ?DUP IF                                         ( request response 0 status )
        NIP AMRUN-S-NOMEM = IF
            SACT-O-BLOCKED SACT-R-CAPACITY
        ELSE
            SACT-O-FAILED SACT-R-INTERNAL
        THEN
        R> _SBRK-REFUSE EXIT
    THEN                                            ( request response run )
    2 PICK OVER 3 PICK R@ _SBRK-H-START
    DUP SDSP-S-STARTED = IF NIP NIP NIP R> DROP EXIT THEN
    SWAP AMRUN-FREE                                 ( request response status )
    DUP SDSP-S-WAITING = OVER SDSP-S-RUNNING = OR
    OVER SDSP-S-ENDED = OR OVER SDSP-S-SMALL = OR IF NIP NIP R> DROP EXIT THEN
    DROP SACT-O-BLOCKED SACT-R-AGENT-UNAVAILABLE R> _SBRK-REFUSE ;

\ Offers RUN, which waits, to the handler again.  True when it must wait
\ on.  A run the handler refused without starting ends at the broker.
: _SBRK-RELEASE  ( run broker -- wait? )
    >R 0 R@ _SBRK.RESPONSE SDSP-RESPONSE-INIT
    DUP _SBR.REQUEST @ R@ _SBRK.RESPONSE R@ _SBRK-TRY       ( run status )
    DUP SDSP-S-WAITING = IF 2DROP R> DROP -1 EXIT THEN
    SDSP-S-ENDED = R@ _SBRK.RESPONSE SDSP-P.RUN RID-ZERO? AND IF
        R@ _SBRK.RESPONSE DUP SDSP-P.OUTCOME @ SWAP SDSP-P.REASON @
        R> _SBRK-QUIT 0 EXIT
    THEN
    _SBRK-STARTED OVER _SBR.STATE !
    DUP _SBR.REQUEST @ FREE 0 SWAP _SBR.REQUEST !
    R> DROP 0 ;

\ Starts the waiting runs, first to last, while the handler is idle.
\ Each is checked again as it starts.
: SBRK-TICK  ( broker -- )
    DUP SBRK-VALID? 0= IF DROP EXIT THEN
    DUP _SBRK.RUNS @
    BEGIN DUP WHILE                                  ( broker run )
        DUP _SBR.STATE @ _SBRK-QUEUED = IF
            OVER _SBRK-H-IDLE? 0= IF 2DROP EXIT THEN
            DUP 2 PICK _SBRK-RELEASE IF 2DROP EXIT THEN
        THEN
        @
    REPEAT
    2DROP ;

\ =====================================================================
\  Daybook's client
\ =====================================================================

\ Hands over the run REQUEST asks for, into RESPONSE.  A dispatch key the
\ broker knows is answered as STATUS answers it, so an occurrence handed
\ over twice is one run.
: _SBRK-SUBMIT  ( request response broker -- status )
    >R
    OVER -1 SDSP-REQUEST-OK? IF 2DROP R> DROP SDSP-S-INVALID EXIT THEN
    OVER SDSP-R.KEY R@ _SBRK-RUN ?DUP IF SWAP R> _SBRK-STANDS NIP EXIT THEN
    OVER _SBRK-NEW-RUN ?DUP 0= IF
        SACT-O-BLOCKED SACT-R-CAPACITY R> _SBRK-REFUSE EXIT
    THEN                                            ( request response run )
    2 PICK 2 PICK R@ _SBRK-TRY                      ( request response run status )
    DUP SDSP-S-ENDED = IF DROP FREE 2DROP R> DROP SDSP-S-ENDED EXIT THEN
    DUP SDSP-S-WAITING = IF
        3 PICK _SBRK-COPY ?DUP 0= IF
            DROP DUP _SBR.KEY SACT-R-CAPACITY R@ _SBRK-H-CANCEL DROP FREE
            SACT-O-BLOCKED SACT-R-CAPACITY R> _SBRK-REFUSE EXIT
        THEN
        2 PICK _SBR.REQUEST ! _SBRK-QUEUED
    ELSE
        _SBRK-STARTED
    THEN
    2 PICK _SBR.STATE !
    SWAP R> _SBRK.RUNS _SBRK-APPEND NIP NIP ;

\ How the run with dispatch KEY stands, into RESPONSE.
: _SBRK-STATUS  ( key response broker -- status )
    >R OVER R@ _SBRK-RUN ?DUP IF ROT DROP SWAP R> _SBRK-STANDS EXIT THEN
    R> _SBRK-H-STATUS ;

\ Cancels the run with dispatch KEY, as Daybook's user asked.
: _SBRK-CANCEL  ( key broker -- status )
    2DUP _SBRK-RUN ?DUP IF                          ( key broker run )
        DUP _SBR.STATE @ _SBRK-QUEUED = IF
            SACT-O-CANCELLED SACT-R-USER 3 PICK _SBRK-QUIT 2DROP SDSP-S-OK EXIT
        THEN
        DUP _SBR.STATE @ _SBRK-ENDED = IF DROP 2DROP SDSP-S-OK EXIT THEN
        DROP
    THEN
    SACT-R-USER SWAP _SBRK-H-CANCEL ;

\ How REQUEST, which names no occurrence, stands.
: _SBRK-CHECK  ( request broker -- standing status )
    OVER 0 SDSP-REQUEST-OK? IF 2DROP SDSP-A-UNAVAILABLE SDSP-S-INVALID EXIT THEN
    _SBRK-STANDING SDSP-S-OK ;

\ ---------------------------------------------------------------------
\  Approvals
\ ---------------------------------------------------------------------
\  An approval's state is what ASKED answers: PENDING, ALLOWED, REFUSED
\  or GONE.

\ An approval:
\    +0 next   +8 id   +16 state   +24 the permission granted
\   +56 its revision   +64 a copy of the request
: _SBA.ID          ( ask -- a ) 8 + ;
: _SBA.STATE       ( ask -- a ) 16 + ;
: _SBA.PERMISSION  ( ask -- rid ) 24 + ;
: _SBA.REVISION    ( ask -- a ) 56 + ;
: _SBA.REQUEST     ( ask -- a ) 64 + ;
72 CONSTANT _SBA-SIZE

\ The approval with ID, or 0.
: _SBRK-FIND-ASK  ( id broker -- ask|0 )
    _SBRK.ASKS @
    BEGIN DUP WHILE
        2DUP _SBA.ID @ = IF NIP EXIT THEN
        @
    REPEAT
    NIP ;

\ Takes ASK off the list and frees it, with its request.
: _SBRK-FORGET  ( ask broker -- )
    OVER SWAP _SBRK.ASKS _SBRK-UNLINK
    DUP _SBA.REQUEST @ FREE
    FREE ;

\ Withdraws the approvals awaiting an answer for REQUEST's schedule.
: _SBRK-WITHDRAW  ( request broker -- )
    _SBRK.ASKS @
    BEGIN DUP WHILE                                  ( request ask )
        DUP _SBA.STATE @ SDSP-S-PENDING =
        OVER _SBA.REQUEST @ SDSP-R.STORE 3 PICK SDSP-R.STORE RID= AND
        OVER _SBA.REQUEST @ SDSP-R.SCHEDULE 3 PICK SDSP-R.SCHEDULE RID= AND
        IF SDSP-S-GONE OVER _SBA.STATE ! THEN
        @
    REPEAT
    2DROP ;

\ Asks Desk's user to approve REQUEST, which names no occurrence.  Only a
\ request the permissions could grant is asked about.
: _SBRK-ASK  ( request broker -- ask-id status )
    OVER OVER _SBRK-PRACTICE SPERM-GRANTABLE? 0= IF
        2DROP 0 SDSP-S-INVALID EXIT
    THEN
    OVER _SBRK-COPY ?DUP 0= IF 2DROP 0 SDSP-S-UNAVAILABLE EXIT THEN
    _SBA-SIZE ALLOCATE IF DROP FREE 2DROP 0 SDSP-S-UNAVAILABLE EXIT THEN
    DUP _SBA-SIZE 0 FILL TUCK _SBA.REQUEST !        ( request broker ask )
    SDSP-S-PENDING OVER _SBA.STATE !
    1 2 PICK _SBRK.ASK-ID +! OVER _SBRK.ASK-ID @ OVER _SBA.ID !
    2 PICK 2 PICK _SBRK-WITHDRAW
    DUP 2 PICK _SBRK.ASKS _SBRK-APPEND
    _SBA.ID @ NIP NIP SDSP-S-PENDING ;

\ The answer to approval ASK-ID: PENDING while it awaits the user; then,
\ once, ALLOWED with RESPONSE naming the permission, its revision and
\ the Practice, or REFUSED or GONE.
: _SBRK-ASKED  ( ask-id response broker -- status )
    ROT OVER _SBRK-FIND-ASK ?DUP 0= IF 2DROP SDSP-S-GONE EXIT THEN
    DUP _SBA.STATE @ SDSP-S-PENDING = IF DROP 2DROP SDSP-S-PENDING EXIT THEN
    DUP _SBA.STATE @ SDSP-S-ALLOWED = IF
        DUP _SBA.PERMISSION 3 PICK SDSP-P.PERMISSION RID-COPY
        DUP _SBA.REVISION @ 3 PICK SDSP-P.PERMISSION-REVISION !
        OVER _SBRK-PRACTICE 3 PICK SDSP-P.PRACTICE RID-COPY
    THEN
    DUP _SBA.STATE @ >R SWAP _SBRK-FORGET DROP R> ;

\ The oldest approval awaiting the user's answer: its id and request,
\ which stays put until the broker is next called; 0 0 when there is
\ none.
: SBRK-ASKING  ( broker -- id request | 0 0 )
    _SBRK.ASKS @
    BEGIN DUP WHILE
        DUP _SBA.STATE @ SDSP-S-PENDING = IF
            DUP _SBA.ID @ SWAP _SBA.REQUEST @ EXIT
        THEN
        @
    REPEAT
    0 ;

\ Why the handler could not run REQUEST, an approval's, or 0 when it
\ could: Desk shows it before its user answers.  Without a handler that
\ can say, the Agent is unavailable.
: SBRK-VET  ( request broker -- reason|0 )
    DUP SBRK-VALID? 0= IF 2DROP SACT-R-AGENT-UNAVAILABLE EXIT THEN
    _SBRK-H-VET ;

\ Answers approval ID, which awaits the user.  ALLOWED? grants its
\ request in Desk's Practice at NOW, the wall clock in milliseconds or -1
\ when it is not set; otherwise the approval is refused.  A grant the
\ store refuses leaves the approval awaiting an answer, and the status
\ is the store's.
: SBRK-ANSWER  ( id allowed? now broker -- status )
    >R ROT R@ _SBRK-FIND-ASK                         ( allowed? now ask|0 )
    DUP 0= IF DROP 2DROP R> DROP SPERM-S-NOT-FOUND EXIT THEN
    DUP _SBA.STATE @ SDSP-S-PENDING <> IF
        DROP 2DROP R> DROP SPERM-S-NOT-FOUND EXIT
    THEN
    ROT 0= IF NIP SDSP-S-REFUSED SWAP _SBA.STATE ! R> DROP SPERM-S-OK EXIT THEN
    DUP _SBA.REQUEST @ R@ _SBRK-PRACTICE 3 PICK R> SBRK-STORE SPERM-GRANT
    ?DUP IF NIP NIP NIP EXIT THEN                    ( now ask permission )
    DUP SPERM-P.RID 2 PICK _SBA.PERMISSION RID-COPY
    SPERM-P.REVISION @ OVER _SBA.REVISION !
    SDSP-S-ALLOWED SWAP _SBA.STATE ! DROP SPERM-S-OK ;

\ =====================================================================
\  Lifecycle
\ =====================================================================

: _SBRK-PATH$  ( -- address length ) S" /schedule-perms.bin" ;

\ Opens a broker for the Practice HEAD, whose root Context is CONTEXT,
\ over the permissions in VFS.  The broker works whatever state the
\ permissions are in, so a blocked store can say why; the status is the
\ store's.
: SBRK-INIT  ( vfs head context broker -- status )
    DUP 0= OVER 7 AND OR IF 2DROP 2DROP SPERM-S-INVALID EXIT THEN
    DUP SBRK-VALID? IF 2DROP 2DROP SPERM-S-STATE EXIT THEN
    2 PICK PHEAD-VALID? 0= IF 2DROP 2DROP SPERM-S-INVALID EXIT THEN
    OVER CTX-VALID? 0= IF 2DROP 2DROP SPERM-S-INVALID EXIT THEN
    OVER CTX.PRACTICE @ 3 PICK <> IF 2DROP 2DROP SPERM-S-INVALID EXIT THEN
    DUP SBRK-SIZE 0 FILL
    TUCK _SBRK.ROOT ! TUCK _SBRK.HEAD !             ( vfs broker )
    >R _SBRK-PATH$ R@ SBRK-STORE SPERM-INIT ?DUP IF R> SBRK-SIZE 0 FILL EXIT THEN
    R@ R@ SBRK-CLIENT SDSP-CLIENT-INIT
    ['] _SBRK-SUBMIT R@ SBRK-CLIENT SDSP-C.SUBMIT-XT !
    ['] _SBRK-STATUS R@ SBRK-CLIENT SDSP-C.STATUS-XT !
    ['] _SBRK-CANCEL R@ SBRK-CLIENT SDSP-C.CANCEL-XT !
    ['] _SBRK-ASK R@ SBRK-CLIENT SDSP-C.ASK-XT !
    ['] _SBRK-ASKED R@ SBRK-CLIENT SDSP-C.ASKED-XT !
    ['] _SBRK-CHECK R@ SBRK-CLIENT SDSP-C.CHECK-XT !
    ['] _SBRK-H-MODELS R@ SBRK-CLIENT SDSP-C.MODELS-XT !
    R@ DUP _SBRK.SELF ! _SBRK-MAGIC R@ _SBRK.MAGIC !
    R> SBRK-STORE SPERM-OPEN ;

\ Revokes permission RID, and cancels the runs in flight under it.
: SBRK-REVOKE  ( rid broker -- status )
    2DUP SBRK-STORE SPERM-REVOKE ?DUP IF NIP NIP EXIT THEN
    DUP _SBRK.RUNS @
    BEGIN DUP WHILE                                  ( rid broker run )
        DUP _SBR.PERMISSION 3 PICK RID= IF
            DUP SACT-O-CANCELLED SACT-R-REVOKED 4 PICK _SBRK-STOP
        THEN
        @
    REPEAT
    DROP 2DROP SPERM-S-OK ;

\ Whether a scheduled run is in flight: waiting, or started and not
\ ended as far as the handler says.  A run it cannot say about counts.
: SBRK-ACTIVE?  ( broker -- flag )
    DUP SBRK-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SBRK.RUNS @
    BEGIN DUP WHILE                                  ( broker run )
        DUP _SBR.STATE @ _SBRK-QUEUED = IF 2DROP -1 EXIT THEN
        DUP _SBR.STATE @ _SBRK-STARTED = IF
            0 2 PICK _SBRK.RESPONSE SDSP-RESPONSE-INIT
            DUP _SBR.KEY 2 PICK _SBRK.RESPONSE 3 PICK _SBRK-H-STATUS
            DUP SDSP-S-ENDED = OVER SDSP-S-SMALL = OR SWAP SDSP-S-UNKNOWN = OR
            0= IF 2DROP -1 EXIT THEN
        THEN
        @
    REPEAT
    NIP ;

\ Cancels every run in flight, as Desk shuts down, and closes the
\ broker.
: SBRK-FINI  ( broker -- )
    DUP SBRK-VALID? 0= IF DROP EXIT THEN
    DUP _SBRK.RUNS @
    BEGIN DUP WHILE
        DUP SACT-O-CANCELLED SACT-R-SHUTDOWN 4 PICK _SBRK-STOP
        @
    REPEAT
    DROP
    BEGIN DUP _SBRK.RUNS @ ?DUP WHILE OVER _SBRK-DROP REPEAT
    BEGIN DUP _SBRK.ASKS @ ?DUP WHILE OVER _SBRK-FORGET REPEAT
    DUP SBRK-STORE SPERM-CLOSE DROP
    SBRK-SIZE 0 FILL ;
