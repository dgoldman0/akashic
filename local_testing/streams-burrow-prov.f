\ =====================================================================
\ streams-burrow-prov.f - deterministic Rabbit provider fixture
\ =====================================================================
\ This test-only provider keeps one embedded lease so a focused lifecycle
\ fixture can script exact acquire, pump, cleanup, and release outcomes
\ without allocation.  One is fixture cardinality, not product capacity: it
\ does not constrain a Burrow peer capacity or describe a production limit.
\
\ Every result-producing callback has one default result and an optional
\ one-shot next result.  Next status -1 means "use the default".  Callback
\ counters include spec/lease calls rejected by an otherwise valid fixture;
\ LEASE-VALID counts only executions of that provider callback, including
\ checks made by the checked ABI wrappers.
\ =====================================================================

PROVIDED akashic-test-srbprov

\ Focused source-mode drivers load rabbit-provider.f before this fixture.

\ =====================================================================
\ Script operation indices
\ =====================================================================

0 CONSTANT SBSP-OP-ACQUIRE
1 CONSTANT SBSP-OP-ACQUIRE-TICK
2 CONSTANT SBSP-OP-OPEN
3 CONSTANT SBSP-OP-SERVICE
4 CONSTANT SBSP-OP-CANCEL
5 CONSTANT SBSP-OP-FINALIZE
6 CONSTANT SBSP-OP-RELEASE
7 CONSTANT SBSP-OP-COUNTS
8 CONSTANT SBSP-OP-LEASE-VALID

8 CONSTANT SBSP-RESULT-OP-COUNT
9 CONSTANT SBSP-CALLBACK-COUNT

: SBSP-RESULT-OP-VALID?  ( operation -- flag )
    DUP 0>= SWAP SBSP-RESULT-OP-COUNT < AND ;

: SBSP-CALLBACK-OP-VALID?  ( operation -- flag )
    DUP 0>= SWAP SBSP-CALLBACK-COUNT < AND ;

\ =====================================================================
\ Caller-owned context, embedded descriptor, and embedded lease
\ =====================================================================

0x53425350524F5631 CONSTANT _SBSP-MAGIC-VALUE  \ "SBSPROV1"

0x5342534C45415331 CONSTANT _SBSP-LEASE-MAGIC  \ "SBSLEAS1"

 0 CONSTANT _SBSP-MAGIC
 8 CONSTANT _SBSP-SELF
16 CONSTANT _SBSP-BYTES
24 CONSTANT _SBSP-PROVIDER
_SBSP-PROVIDER SRBPROV-PROVIDER-SIZE + CONSTANT _SBSP-LEASE

 0 CONSTANT _SBSP-L-MAGIC
 8 CONSTANT _SBSP-L-CONTEXT
16 CONSTANT _SBSP-L-ACTIVE
24 CONSTANT _SBSP-L-GENERATION
32 CONSTANT _SBSP-LEASE-SIZE

_SBSP-LEASE _SBSP-LEASE-SIZE + CONSTANT _SBSP-RESULTS

 0 CONSTANT _SBSPR-DEFAULT-STATUS
 8 CONSTANT _SBSPR-DEFAULT-DETAIL
16 CONSTANT _SBSPR-NEXT-STATUS
24 CONSTANT _SBSPR-NEXT-DETAIL
32 CONSTANT _SBSP-RESULT-SIZE

_SBSP-RESULTS SBSP-RESULT-OP-COUNT _SBSP-RESULT-SIZE * +
    CONSTANT _SBSP-COUNTERS
_SBSP-COUNTERS SBSP-CALLBACK-COUNT 8 * + CONSTANT _SBSP-PEER-COUNT
_SBSP-PEER-COUNT 8 + CONSTANT _SBSP-SERVICE-COUNT
_SBSP-SERVICE-COUNT 8 + CONSTANT _SBSP-SERVICE-DELTA
_SBSP-SERVICE-DELTA 8 + CONSTANT _SBSP-ACQUIRE-RETAIN
_SBSP-ACQUIRE-RETAIN 8 + CONSTANT SBSP-SIZE

-1 1 RSHIFT CONSTANT _SBSP-CELL-MAX

: SBSP.MAGIC  ( context -- field ) _SBSP-MAGIC + ;
: SBSP.SELF  ( context -- field ) _SBSP-SELF + ;
: SBSP.BYTES  ( context -- field ) _SBSP-BYTES + ;
: SBSP-PROVIDER  ( context -- provider ) _SBSP-PROVIDER + ;
: SBSP-LEASE  ( context -- lease ) _SBSP-LEASE + ;
: SBSP.COUNTERS  ( context -- counters ) _SBSP-COUNTERS + ;
: SBSP.PEER-COUNT  ( context -- field ) _SBSP-PEER-COUNT + ;
: SBSP.SERVICE-COUNT  ( context -- field ) _SBSP-SERVICE-COUNT + ;
: SBSP.SERVICE-DELTA  ( context -- field ) _SBSP-SERVICE-DELTA + ;
: SBSP.ACQUIRE-RETAIN  ( context -- field ) _SBSP-ACQUIRE-RETAIN + ;

: SBSP-L.MAGIC  ( lease -- field ) _SBSP-L-MAGIC + ;
: SBSP-L.CONTEXT  ( lease -- field ) _SBSP-L-CONTEXT + ;
: SBSP-L.ACTIVE  ( lease -- field ) _SBSP-L-ACTIVE + ;
: SBSP-L.GENERATION  ( lease -- field ) _SBSP-L-GENERATION + ;

: SBSPR.DEFAULT-STATUS  ( result -- field )
    _SBSPR-DEFAULT-STATUS + ;
: SBSPR.DEFAULT-DETAIL  ( result -- field )
    _SBSPR-DEFAULT-DETAIL + ;
: SBSPR.NEXT-STATUS  ( result -- field ) _SBSPR-NEXT-STATUS + ;
: SBSPR.NEXT-DETAIL  ( result -- field ) _SBSPR-NEXT-DETAIL + ;

: _SBSP-RESULT-ENTRY  ( operation context -- result|0 )
    OVER SBSP-RESULT-OP-VALID? 0= IF 2DROP 0 EXIT THEN
    _SBSP-RESULTS + SWAP _SBSP-RESULT-SIZE * + ;

: _SBSP-COUNTER-FIELD  ( operation context -- field|0 )
    OVER SBSP-CALLBACK-OP-VALID? 0= IF 2DROP 0 EXIT THEN
    SBSP.COUNTERS SWAP 8 * + ;

\ =====================================================================
\ Structural validity and script accessors
\ =====================================================================

: _SBSP-HEADER?  ( context -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBSP-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP SBSP.MAGIC @ _SBSP-MAGIC-VALUE =
    OVER SBSP.SELF @ 2 PICK = AND
    SWAP SBSP.BYTES @ SBSP-SIZE = AND ;

: _SBSP-LEASE-STATIC?  ( context -- flag )
    DUP SBSP-LEASE DUP SBSP-L.MAGIC @ _SBSP-LEASE-MAGIC <> IF
        2DROP 0 EXIT
    THEN
    DUP SBSP-L.CONTEXT @ 2 PICK <> IF 2DROP 0 EXIT THEN
    DUP SBSP-L.ACTIVE @ DUP 0= SWAP -1 = OR 0= IF 2DROP 0 EXIT THEN
    DUP SBSP-L.GENERATION @ 0< IF 2DROP 0 EXIT THEN
    DUP SBSP-L.ACTIVE @ IF
        DUP SBSP-L.GENERATION @ 0> 0= IF 2DROP 0 EXIT THEN
    THEN
    2DROP -1 ;

: _SBSP-RESULTS-VALID?  ( context -- flag )
    SBSP-RESULT-OP-COUNT 0 ?DO
        I OVER _SBSP-RESULT-ENTRY DUP 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        DUP SBSPR.DEFAULT-STATUS @
        OVER SBSPR.DEFAULT-DETAIL @ SRBPROV-RESULT-VALID? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        DUP SBSPR.NEXT-STATUS @ DUP -1 = IF
            DROP
            DUP SBSPR.NEXT-DETAIL @ -1 <> IF
                2DROP 0 UNLOOP EXIT
            THEN
        ELSE
            OVER SBSPR.NEXT-DETAIL @ SRBPROV-RESULT-VALID? 0= IF
                2DROP 0 UNLOOP EXIT
            THEN
        THEN
        DROP
    LOOP
    DROP -1 ;

: _SBSP-COUNTERS-VALID?  ( context -- flag )
    SBSP-CALLBACK-COUNT 0 ?DO
        I OVER _SBSP-COUNTER-FIELD DUP 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        @ 0< IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SBSP-CONTEXT-READY?  ( context -- flag )
    DUP _SBSP-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _SBSP-LEASE-STATIC? 0= IF DROP 0 EXIT THEN
    DUP _SBSP-RESULTS-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SBSP-COUNTERS-VALID? 0= IF DROP 0 EXIT THEN
    DUP SBSP.PEER-COUNT @ 0< IF DROP 0 EXIT THEN
    DUP SBSP.SERVICE-COUNT @ 0< IF DROP 0 EXIT THEN
    DUP SBSP.SERVICE-DELTA @ 0< IF DROP 0 EXIT THEN
    DUP SBSP.ACQUIRE-RETAIN @ DUP 0= SWAP -1 = OR 0= IF
        DROP 0 EXIT
    THEN
    DUP SBSP-PROVIDER DUP SRBPROV-VALID? 0= IF 2DROP 0 EXIT THEN
    SRBPROV.CONTEXT @ SWAP = ;

: _SBSP-SANITIZE  ( status detail -- status detail )
    2DUP SRBPROV-RESULT-VALID? IF EXIT THEN
    2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT ;

: SBSP-DEFAULT!
  ( status detail operation context -- flag )
    DUP _SBSP-HEADER? 0= IF 2DROP 2DROP 0 EXIT THEN
    3 PICK 3 PICK SRBPROV-RESULT-VALID? 0= IF
        2DROP 2DROP 0 EXIT
    THEN
    _SBSP-RESULT-ENTRY DUP 0= IF 2DROP DROP 0 EXIT THEN
    >R
    SWAP R@ SBSPR.DEFAULT-STATUS !
    R@ SBSPR.DEFAULT-DETAIL !
    R> DROP -1 ;

: SBSP-NEXT!
  ( status detail operation context -- flag )
    DUP _SBSP-HEADER? 0= IF 2DROP 2DROP 0 EXIT THEN
    3 PICK 3 PICK SRBPROV-RESULT-VALID? 0= IF
        2DROP 2DROP 0 EXIT
    THEN
    _SBSP-RESULT-ENTRY DUP 0= IF 2DROP DROP 0 EXIT THEN
    >R
    SWAP R@ SBSPR.NEXT-STATUS !
    R@ SBSPR.NEXT-DETAIL !
    R> DROP -1 ;

: SBSP-NEXT-CLEAR  ( operation context -- flag )
    DUP _SBSP-HEADER? 0= IF 2DROP 0 EXIT THEN
    _SBSP-RESULT-ENTRY DUP 0= IF DROP 0 EXIT THEN
    -1 OVER SBSPR.NEXT-STATUS !
    -1 SWAP SBSPR.NEXT-DETAIL !
    -1 ;

: SBSP-DEFAULT@  ( operation context -- status detail flag )
    DUP _SBSP-HEADER? 0= IF 2DROP 0 0 0 EXIT THEN
    _SBSP-RESULT-ENTRY DUP 0= IF DROP 0 0 0 EXIT THEN
    DUP SBSPR.DEFAULT-STATUS @
    SWAP SBSPR.DEFAULT-DETAIL @ -1 ;

: SBSP-NEXT@  ( operation context -- status detail flag )
    DUP _SBSP-HEADER? 0= IF 2DROP 0 0 0 EXIT THEN
    _SBSP-RESULT-ENTRY DUP 0= IF DROP 0 0 0 EXIT THEN
    DUP SBSPR.NEXT-STATUS @
    SWAP SBSPR.NEXT-DETAIL @ -1 ;

: SBSP-COUNT-FIELD  ( operation context -- field|0 )
    DUP _SBSP-HEADER? 0= IF 2DROP 0 EXIT THEN
    _SBSP-COUNTER-FIELD ;

: SBSP-COUNT@  ( operation context -- count )
    SBSP-COUNT-FIELD ?DUP IF @ ELSE 0 THEN ;

: SBSP-CALL-COUNTERS-CLEAR  ( context -- flag )
    DUP _SBSP-HEADER? 0= IF DROP 0 EXIT THEN
    SBSP.COUNTERS SBSP-CALLBACK-COUNT 8 * 0 FILL -1 ;

: SBSP-COUNTS!  ( peer-count service-count context -- flag )
    >R
    2DUP 0< SWAP 0< OR IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _SBSP-HEADER? 0= IF 2DROP R> DROP 0 EXIT THEN
    SWAP R@ SBSP.PEER-COUNT !
    R@ SBSP.SERVICE-COUNT !
    R> DROP -1 ;

: SBSP-COUNTS@  ( context -- peer-count service-count )
    DUP _SBSP-HEADER? 0= IF DROP 0 0 EXIT THEN
    DUP SBSP.PEER-COUNT @ SWAP SBSP.SERVICE-COUNT @ ;

: SBSP-SERVICE-DELTA!  ( delta context -- flag )
    OVER 0< IF 2DROP 0 EXIT THEN
    DUP _SBSP-HEADER? 0= IF 2DROP 0 EXIT THEN
    SBSP.SERVICE-DELTA ! -1 ;

: SBSP-SERVICE-DELTA@  ( context -- delta )
    DUP _SBSP-HEADER? 0= IF DROP 0 EXIT THEN
    SBSP.SERVICE-DELTA @ ;

: SBSP-ACQUIRE-RETAIN!  ( flag context -- flag )
    DUP _SBSP-HEADER? 0= IF 2DROP 0 EXIT THEN
    SWAP 0<> SWAP SBSP.ACQUIRE-RETAIN ! -1 ;

: SBSP-ACQUIRE-RETAIN?  ( context -- flag )
    DUP _SBSP-HEADER? 0= IF DROP 0 EXIT THEN
    SBSP.ACQUIRE-RETAIN @ 0<> ;

: SBSP-LEASE-ACTIVE?  ( context -- flag )
    DUP _SBSP-HEADER? 0= IF DROP 0 EXIT THEN
    SBSP-LEASE SBSP-L.ACTIVE @ 0<> ;

: SBSP-LEASE-GENERATION@  ( context -- generation )
    DUP _SBSP-HEADER? 0= IF DROP 0 EXIT THEN
    SBSP-LEASE SBSP-L.GENERATION @ ;

\ =====================================================================
\ Callback support
\ =====================================================================

: _SBSP-COUNT+  ( operation context -- )
    _SBSP-COUNTER-FIELD ?DUP IF
        DUP @ _SBSP-CELL-MAX < IF 1 SWAP +! ELSE DROP THEN
    THEN ;

: _SBSP-TAKE-RESULT  ( operation context -- status detail )
    _SBSP-RESULT-ENTRY DUP 0= IF
        DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT EXIT
    THEN
    >R
    R@ SBSPR.NEXT-STATUS @ DUP -1 = IF
        DROP
        R@ SBSPR.DEFAULT-STATUS @
        R@ SBSPR.DEFAULT-DETAIL @
    ELSE
        R@ SBSPR.NEXT-DETAIL @
        -1 R@ SBSPR.NEXT-STATUS !
        -1 R@ SBSPR.NEXT-DETAIL !
    THEN
    R> DROP _SBSP-SANITIZE ;

: _SBSP-LEASE-MATCH?  ( lease context -- flag )
    DUP _SBSP-HEADER? 0= IF 2DROP 0 EXIT THEN
    DUP SBSP-LEASE 2 PICK <> IF 2DROP 0 EXIT THEN
    SWAP
    DUP SBSP-L.MAGIC @ _SBSP-LEASE-MAGIC <> IF 2DROP 0 EXIT THEN
    DUP SBSP-L.CONTEXT @ 2 PICK <> IF 2DROP 0 EXIT THEN
    DUP SBSP-L.ACTIVE @ -1 <> IF 2DROP 0 EXIT THEN
    SBSP-L.GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    DROP -1 ;

: _SBSP-LEASE-ACTIVATE  ( context -- )
    SBSP-LEASE
    DUP SBSP-L.GENERATION DUP @ _SBSP-CELL-MAX < IF
        1 SWAP +!
    ELSE
        DROP
    THEN
    -1 SWAP SBSP-L.ACTIVE ! ;

: _SBSP-LEASE-DEACTIVATE  ( context -- )
    0 SWAP SBSP-LEASE SBSP-L.ACTIVE ! ;

: _SBSP-ACQUIRE-LEASE?  ( status context -- flag )
    >R
    DUP SRBPROV-S-NONE = OVER SRBPROV-S-PENDING = OR
    SWAP DROP
    R> SBSP.ACQUIRE-RETAIN @ 0<> OR ;

: _SBSP-SERVICE+  ( context -- flag )
    DUP SBSP.SERVICE-COUNT @
    OVER SBSP.SERVICE-DELTA @ DUP 0< IF
        2DROP DROP 0 EXIT
    THEN
    OVER _SBSP-CELL-MAX SWAP - U> IF
        2DROP 0 EXIT
    THEN
    OVER SBSP.SERVICE-DELTA @ +
    SWAP SBSP.SERVICE-COUNT ! -1 ;

: _SBSP-LEASE-CALL?
  ( lease context operation invalid-detail -- status detail valid-lease )
    2>R
    DUP _SBSP-CONTEXT-READY? 0= IF
        2DROP 2R> NIP SRBPROV-S-INVALID SWAP 0 EXIT
    THEN
    2R@ DROP OVER _SBSP-COUNT+
    2DUP _SBSP-LEASE-MATCH? 0= IF
        2DROP 2R> NIP SRBPROV-S-INVALID SWAP 0 EXIT
    THEN
    NIP
    2R> DROP SWAP _SBSP-TAKE-RESULT
    -1 ;

\ =====================================================================
\ Provider callbacks
\ =====================================================================

: SBSP-ACQUIRE-CB  ( spec context -- lease status detail )
    DUP _SBSP-CONTEXT-READY? 0= IF
        2DROP 0 SRBPROV-S-INVALID SRBPROV-D-PROVIDER-ACQUIRE EXIT
    THEN
    SBSP-OP-ACQUIRE OVER _SBSP-COUNT+
    OVER SRBPROV-GRAPH-SPEC-VALID? 0= IF
        2DROP 0 SRBPROV-S-INVALID SRBPROV-D-PROVIDER-ACQUIRE EXIT
    THEN
    DUP SBSP-LEASE-ACTIVE? IF
        \ One fixture lease represents one retained ownership claim.  Never
        \ hand the same opaque lease to a second acquire.
        2DROP 0 SRBPROV-S-STATE SRBPROV-D-PROVIDER-ACQUIRE EXIT
    THEN
    SBSP-OP-ACQUIRE OVER _SBSP-TAKE-RESULT
    2SWAP NIP -ROT
    2>R
    2R@ DROP OVER _SBSP-ACQUIRE-LEASE? IF
        DUP _SBSP-LEASE-ACTIVATE SBSP-LEASE
    ELSE
        DROP 0
    THEN
    2R> ;

: SBSP-ACQUIRE-TICK-CB  ( lease context -- status detail )
    SBSP-OP-ACQUIRE-TICK SRBPROV-D-PROVIDER-ACQUIRE
        _SBSP-LEASE-CALL? DROP ;

: SBSP-OPEN-CB  ( lease context -- status detail )
    SBSP-OP-OPEN SRBPROV-D-BURROW-OPEN _SBSP-LEASE-CALL? DROP ;

: SBSP-SERVICE-CB  ( lease context -- status detail )
    DUP >R
    SBSP-OP-SERVICE SRBPROV-D-BURROW-PUMP _SBSP-LEASE-CALL?
    DUP 0= IF DROP R> DROP EXIT THEN
    DROP
    OVER SRBPROV-S-NONE = IF
        R@ _SBSP-SERVICE+ 0= IF
            2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT
        THEN
    THEN
    R> DROP ;

: SBSP-CANCEL-CB  ( lease context -- status detail )
    SBSP-OP-CANCEL SRBPROV-D-BURROW-FINALIZE
        _SBSP-LEASE-CALL? DROP ;

: SBSP-FINALIZE-CB  ( lease context -- status detail )
    SBSP-OP-FINALIZE SRBPROV-D-BURROW-FINALIZE
        _SBSP-LEASE-CALL? DROP ;

: SBSP-RELEASE-CB  ( lease context -- status detail )
    DUP >R
    SBSP-OP-RELEASE SRBPROV-D-PROVIDER-RELEASE _SBSP-LEASE-CALL?
    DUP IF
        2 PICK SRBPROV-S-NONE = IF R@ _SBSP-LEASE-DEACTIVATE THEN
    THEN
    DROP R> DROP ;

: SBSP-COUNTS-CB
  ( lease context -- peer-count service-count status detail )
    DUP >R
    SBSP-OP-COUNTS SRBPROV-D-INVARIANT _SBSP-LEASE-CALL?
    IF
        R@ SBSP.PEER-COUNT @ R@ SBSP.SERVICE-COUNT @ 2SWAP
    ELSE
        0 0 2SWAP
    THEN
    R> DROP ;

: SBSP-LEASE-VALID-CB  ( lease context -- flag )
    DUP _SBSP-CONTEXT-READY? 0= IF 2DROP 0 EXIT THEN
    SBSP-OP-LEASE-VALID OVER _SBSP-COUNT+
    _SBSP-LEASE-MATCH? ;

\ =====================================================================
\ Full descriptor validity and allocation-free initialization
\ =====================================================================

: SBSP-VALID?  ( context -- flag )
    DUP _SBSP-CONTEXT-READY? 0= IF DROP 0 EXIT THEN
    DUP SBSP-PROVIDER
    DUP SRBPROV.ACQUIRE-XT @ ['] SBSP-ACQUIRE-CB =
    OVER SRBPROV.ACQUIRE-TICK-XT @ ['] SBSP-ACQUIRE-TICK-CB = AND
    OVER SRBPROV.OPEN-XT @ ['] SBSP-OPEN-CB = AND
    OVER SRBPROV.SERVICE-XT @ ['] SBSP-SERVICE-CB = AND
    OVER SRBPROV.CANCEL-XT @ ['] SBSP-CANCEL-CB = AND
    OVER SRBPROV.FINALIZE-XT @ ['] SBSP-FINALIZE-CB = AND
    OVER SRBPROV.RELEASE-XT @ ['] SBSP-RELEASE-CB = AND
    OVER SRBPROV.COUNTS-XT @ ['] SBSP-COUNTS-CB = AND
    SWAP SRBPROV.LEASE-VALID-XT @ ['] SBSP-LEASE-VALID-CB = AND
    NIP ;

: SBSP-INIT  ( context -- status )
    DUP 0= IF DROP SRBPROV-S-INVALID EXIT THEN
    DUP 7 AND IF DROP SRBPROV-S-INVALID EXIT THEN
    DUP SBSP-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP SRBPROV-S-INVALID EXIT
    THEN
    DUP SBSP-SIZE 0 FILL
    _SBSP-MAGIC-VALUE OVER SBSP.MAGIC !
    DUP OVER SBSP.SELF !
    SBSP-SIZE OVER SBSP.BYTES !
    DUP SBSP-LEASE
    _SBSP-LEASE-MAGIC OVER SBSP-L.MAGIC !
    2DUP SBSP-L.CONTEXT !
    DROP
    SBSP-RESULT-OP-COUNT 0 ?DO
        I OVER _SBSP-RESULT-ENTRY
        SRBPROV-S-NONE OVER SBSPR.DEFAULT-STATUS !
        SRBPROV-D-NONE OVER SBSPR.DEFAULT-DETAIL !
        -1 OVER SBSPR.NEXT-STATUS !
        -1 SWAP SBSPR.NEXT-DETAIL !
    LOOP
    DUP SBSP-PROVIDER SRBPROV-INIT
    DUP OVER SBSP-PROVIDER SRBPROV.CONTEXT !
    ['] SBSP-ACQUIRE-CB OVER SBSP-PROVIDER SRBPROV.ACQUIRE-XT !
    ['] SBSP-ACQUIRE-TICK-CB
        OVER SBSP-PROVIDER SRBPROV.ACQUIRE-TICK-XT !
    ['] SBSP-OPEN-CB OVER SBSP-PROVIDER SRBPROV.OPEN-XT !
    ['] SBSP-SERVICE-CB OVER SBSP-PROVIDER SRBPROV.SERVICE-XT !
    ['] SBSP-CANCEL-CB OVER SBSP-PROVIDER SRBPROV.CANCEL-XT !
    ['] SBSP-FINALIZE-CB OVER SBSP-PROVIDER SRBPROV.FINALIZE-XT !
    ['] SBSP-RELEASE-CB OVER SBSP-PROVIDER SRBPROV.RELEASE-XT !
    ['] SBSP-COUNTS-CB OVER SBSP-PROVIDER SRBPROV.COUNTS-XT !
    ['] SBSP-LEASE-VALID-CB
        OVER SBSP-PROVIDER SRBPROV.LEASE-VALID-XT !
    DUP SBSP-PROVIDER SRBPROV-SEAL DUP IF
        >R DUP SBSP-SIZE 0 FILL DROP R> EXIT
    THEN
    DROP
    DUP SBSP-VALID? 0= IF
        DUP SBSP-SIZE 0 FILL DROP SRBPROV-S-INVALID EXIT
    THEN
    DROP SRBPROV-S-NONE ;
