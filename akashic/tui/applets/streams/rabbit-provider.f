\ =====================================================================
\ rabbit-provider.f - borrowed Streams Rabbit graph-provider ABI
\ =====================================================================
\ Streams owns this small transport-neutral interface.  A composition owns
\ the sealed provider descriptor, its CONTEXT, and every concrete graph.  The
\ manager only borrows the provider, so the descriptor and context must outlive
\ the manager and every retained lease.
\
\ ACQUIRE receives one immutable caller-owned graph specification.  A zero
\ lease means that the provider retained nothing.  Every nonzero lease returned
\ with any status, including PENDING or a cleanup failure, is retained owner
\ state: the manager must preserve it and eventually call RELEASE.  The
\ provider must keep LEASE-VALID? true throughout that retained lifetime.
\ RELEASE with a non-success status retains the lease unchanged.  RELEASE with
\ success is the sole ownership hand-back and must invalidate the lease before
\ returning; the caller then drops the borrowed value without inspecting it.
\
\ No callback may hide a product capacity.  The exact requested peer capacity
\ travels in the graph specification and concrete providers must either honor
\ it with caller/composition-provided storage or return CAPACITY.
\
\ Callback stack effects:
\   ACQUIRE-XT       ( spec context -- lease status detail )
\   ACQUIRE-TICK-XT  ( lease context -- status detail )
\   OPEN-XT          ( lease context -- status detail )
\   SERVICE-XT       ( lease context -- status detail )
\   CANCEL-XT        ( lease context -- status detail )
\   FINALIZE-XT      ( lease context -- status detail )
\   RELEASE-XT       ( lease context -- status detail )
\   COUNTS-XT
\     ( lease context -- peer-count service-count status detail )
\   LEASE-VALID-XT   ( lease context -- flag )
\
\ Every callback is a sealed, trusted composition boundary and must return
\ normally with one of the closed status/detail pairs below; callbacks must
\ not THROW.  In particular, an ACQUIRE that throws after retaining a graph
\ could not communicate the lease that the manager must eventually release.
\ =====================================================================

PROVIDED akashic-streams-srbp

REQUIRE ../../../runtime/identity.f
REQUIRE ../../../utils/memory-span.f

\ =====================================================================
\ Shared closed manager result vocabulary
\ =====================================================================
\ NONE is the successful/no-error value; every other code is a retained
\ sanitized manager/provider condition.

0  CONSTANT SRBPROV-S-NONE
1  CONSTANT SRBPROV-S-INVALID
2  CONSTANT SRBPROV-S-STATE
3  CONSTANT SRBPROV-S-BUSY
4  CONSTANT SRBPROV-S-CAPACITY
5  CONSTANT SRBPROV-S-CONFLICT
6  CONSTANT SRBPROV-S-NOT-FOUND
7  CONSTANT SRBPROV-S-PENDING
8  CONSTANT SRBPROV-S-DENIED
9  CONSTANT SRBPROV-S-UNAVAILABLE
10 CONSTANT SRBPROV-S-IO
11 CONSTANT SRBPROV-S-CORRUPT
12 CONSTANT SRBPROV-S-FAULT

0  CONSTANT SRBPROV-D-NONE
1  CONSTANT SRBPROV-D-DECLARATION
2  CONSTANT SRBPROV-D-LIBRARY-BINDING
3  CONSTANT SRBPROV-D-LIBRARY-DISPATCH
4  CONSTANT SRBPROV-D-PROVIDER-ACQUIRE
5  CONSTANT SRBPROV-D-ROUTER
6  CONSTANT SRBPROV-D-SERVER
7  CONSTANT SRBPROV-D-SUBSCRIPTION
8  CONSTANT SRBPROV-D-TRANSPORT
9  CONSTANT SRBPROV-D-FACET-MOUNT
10 CONSTANT SRBPROV-D-BURROW-OPEN
11 CONSTANT SRBPROV-D-BURROW-PUMP
12 CONSTANT SRBPROV-D-BURROW-FINALIZE
13 CONSTANT SRBPROV-D-PROVIDER-RELEASE
14 CONSTANT SRBPROV-D-INVARIANT

: SRBPROV-STATUS-VALID?  ( status -- flag )
    DUP SRBPROV-S-NONE >= SWAP SRBPROV-S-FAULT <= AND ;

: SRBPROV-DETAIL-VALID?  ( detail -- flag )
    DUP SRBPROV-D-NONE >= SWAP SRBPROV-D-INVARIANT <= AND ;

: SRBPROV-RESULT-VALID?  ( status detail -- flag )
    SRBPROV-DETAIL-VALID? SWAP SRBPROV-STATUS-VALID? AND ;

: _SRBPROV-RESULT  ( status detail -- status detail )
    2DUP SRBPROV-RESULT-VALID? IF EXIT THEN
    2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT ;

\ =====================================================================
\ Exact caller-owned graph specification
\ =====================================================================

0x5352424753504331 CONSTANT SRBPROV-GRAPH-SPEC-MAGIC  \ "SRBGSPC1"
1                  CONSTANT SRBPROV-GRAPH-SPEC-ABI

 0 CONSTANT _SRBPROV-GSPEC-MAGIC
 8 CONSTANT _SRBPROV-GSPEC-ABI
16 CONSTANT _SRBPROV-GSPEC-BYTES
24 CONSTANT _SRBPROV-GSPEC-COLLECTION       \ RID-SIZE bytes
56 CONSTANT _SRBPROV-GSPEC-COLLECTION-REV
64 CONSTANT _SRBPROV-GSPEC-REQUEST-DIGEST   \ RID-SIZE bytes
96 CONSTANT _SRBPROV-GSPEC-PEER-CAPACITY
104 CONSTANT SRBPROV-GRAPH-SPEC-SIZE

: SRBPROV-SPEC.MAGIC  ( spec -- field ) _SRBPROV-GSPEC-MAGIC + ;
: SRBPROV-SPEC.ABI  ( spec -- field ) _SRBPROV-GSPEC-ABI + ;
: SRBPROV-SPEC.BYTES  ( spec -- field ) _SRBPROV-GSPEC-BYTES + ;
: SRBPROV-SPEC.COLLECTION  ( spec -- rid )
    _SRBPROV-GSPEC-COLLECTION + ;
: SRBPROV-SPEC.COLLECTION-REVISION  ( spec -- field )
    _SRBPROV-GSPEC-COLLECTION-REV + ;
: SRBPROV-SPEC.REQUEST-DIGEST  ( spec -- digest )
    _SRBPROV-GSPEC-REQUEST-DIGEST + ;
: SRBPROV-SPEC.PEER-CAPACITY  ( spec -- field )
    _SRBPROV-GSPEC-PEER-CAPACITY + ;

: SRBPROV-GRAPH-SPEC-INIT  ( spec -- )
    DUP 0= IF DROP EXIT THEN
    DUP SRBPROV-GRAPH-SPEC-SIZE 0 FILL
    SRBPROV-GRAPH-SPEC-MAGIC OVER SRBPROV-SPEC.MAGIC !
    SRBPROV-GRAPH-SPEC-ABI OVER SRBPROV-SPEC.ABI !
    SRBPROV-GRAPH-SPEC-SIZE SWAP SRBPROV-SPEC.BYTES ! ;

: SRBPROV-GRAPH-SPEC-VALID?  ( spec -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SRBPROV-GRAPH-SPEC-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    DUP SRBPROV-SPEC.MAGIC @ SRBPROV-GRAPH-SPEC-MAGIC <> IF
        DROP 0 EXIT
    THEN
    DUP SRBPROV-SPEC.ABI @ SRBPROV-GRAPH-SPEC-ABI <> IF
        DROP 0 EXIT
    THEN
    DUP SRBPROV-SPEC.BYTES @ SRBPROV-GRAPH-SPEC-SIZE <> IF
        DROP 0 EXIT
    THEN
    DUP SRBPROV-SPEC.COLLECTION RID-PRESENT? 0= IF DROP 0 EXIT THEN
    DUP SRBPROV-SPEC.COLLECTION-REVISION @ 0> 0= IF DROP 0 EXIT THEN
    SRBPROV-SPEC.PEER-CAPACITY @ 0> ;

\ =====================================================================
\ Caller-owned borrowed provider descriptor
\ =====================================================================

0x53524250524F5631 CONSTANT SRBPROV-MAGIC  \ "SRBPROV1"
1                  CONSTANT SRBPROV-ABI

 0 CONSTANT _SRBPROV-MAGIC
 8 CONSTANT _SRBPROV-ABI
16 CONSTANT _SRBPROV-BYTES
24 CONSTANT _SRBPROV-CONTEXT
32 CONSTANT _SRBPROV-ACQUIRE-XT
40 CONSTANT _SRBPROV-ACQUIRE-TICK-XT
48 CONSTANT _SRBPROV-OPEN-XT
56 CONSTANT _SRBPROV-SERVICE-XT
64 CONSTANT _SRBPROV-CANCEL-XT
72 CONSTANT _SRBPROV-FINALIZE-XT
80 CONSTANT _SRBPROV-RELEASE-XT
88 CONSTANT _SRBPROV-COUNTS-XT
96 CONSTANT _SRBPROV-LEASE-VALID-XT
104 CONSTANT SRBPROV-PROVIDER-SIZE

: SRBPROV.MAGIC  ( provider -- field ) _SRBPROV-MAGIC + ;
: SRBPROV.ABI  ( provider -- field ) _SRBPROV-ABI + ;
: SRBPROV.BYTES  ( provider -- field ) _SRBPROV-BYTES + ;
: SRBPROV.CONTEXT  ( provider -- field ) _SRBPROV-CONTEXT + ;
: SRBPROV.ACQUIRE-XT  ( provider -- field ) _SRBPROV-ACQUIRE-XT + ;
: SRBPROV.ACQUIRE-TICK-XT  ( provider -- field )
    _SRBPROV-ACQUIRE-TICK-XT + ;
: SRBPROV.OPEN-XT  ( provider -- field ) _SRBPROV-OPEN-XT + ;
: SRBPROV.SERVICE-XT  ( provider -- field ) _SRBPROV-SERVICE-XT + ;
: SRBPROV.CANCEL-XT  ( provider -- field ) _SRBPROV-CANCEL-XT + ;
: SRBPROV.FINALIZE-XT  ( provider -- field ) _SRBPROV-FINALIZE-XT + ;
: SRBPROV.RELEASE-XT  ( provider -- field ) _SRBPROV-RELEASE-XT + ;
: SRBPROV.COUNTS-XT  ( provider -- field ) _SRBPROV-COUNTS-XT + ;
: SRBPROV.LEASE-VALID-XT  ( provider -- field )
    _SRBPROV-LEASE-VALID-XT + ;

: SRBPROV-INIT  ( provider -- )
    DUP 0<> IF SRBPROV-PROVIDER-SIZE 0 FILL ELSE DROP THEN ;

: SRBPROV-VALID?  ( provider -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SRBPROV-PROVIDER-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP SRBPROV.MAGIC @ SRBPROV-MAGIC =
    OVER SRBPROV.ABI @ SRBPROV-ABI = AND
    OVER SRBPROV.BYTES @ SRBPROV-PROVIDER-SIZE = AND
    OVER SRBPROV.CONTEXT @ 0<> AND
    OVER SRBPROV.ACQUIRE-XT @ 0<> AND
    OVER SRBPROV.ACQUIRE-TICK-XT @ 0<> AND
    OVER SRBPROV.OPEN-XT @ 0<> AND
    OVER SRBPROV.SERVICE-XT @ 0<> AND
    OVER SRBPROV.CANCEL-XT @ 0<> AND
    OVER SRBPROV.FINALIZE-XT @ 0<> AND
    OVER SRBPROV.RELEASE-XT @ 0<> AND
    OVER SRBPROV.COUNTS-XT @ 0<> AND
    SWAP SRBPROV.LEASE-VALID-XT @ 0<> AND ;

: SRBPROV-SEAL  ( provider -- status )
    DUP 0= IF DROP SRBPROV-S-INVALID EXIT THEN
    DUP 7 AND IF DROP SRBPROV-S-INVALID EXIT THEN
    DUP SRBPROV-PROVIDER-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP SRBPROV-S-INVALID EXIT
    THEN
    DUP SRBPROV.MAGIC @ IF DROP SRBPROV-S-STATE EXIT THEN
    SRBPROV-MAGIC OVER SRBPROV.MAGIC !
    SRBPROV-ABI OVER SRBPROV.ABI !
    SRBPROV-PROVIDER-SIZE OVER SRBPROV.BYTES !
    DUP SRBPROV-VALID? IF DROP SRBPROV-S-NONE EXIT THEN
    SRBPROV-INIT SRBPROV-S-INVALID ;

\ =====================================================================
\ Checked callback wrappers
\ =====================================================================

: SRBPROV-LEASE-VALID?  ( lease provider -- flag )
    DUP SRBPROV-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    DUP SRBPROV.CONTEXT @ SWAP SRBPROV.LEASE-VALID-XT @ EXECUTE 0<> ;

: _SRBPROV-RETAINED-RESULT
  ( status detail lease provider -- status detail )
    SRBPROV-LEASE-VALID? 0= IF
        2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT EXIT
    THEN
    _SRBPROV-RESULT ;

: _SRBPROV-RELEASE-RESULT
  ( status detail lease provider -- status detail )
    SRBPROV-LEASE-VALID?
    2 PICK SRBPROV-S-NONE = IF
        IF 2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT THEN
        EXIT
    THEN
    0= IF 2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT THEN ;

: SRBPROV-ACQUIRE  ( spec provider -- lease status detail )
    DUP SRBPROV-VALID? 0= IF
        2DROP 0 SRBPROV-S-INVALID SRBPROV-D-PROVIDER-ACQUIRE EXIT
    THEN
    OVER SRBPROV-GRAPH-SPEC-VALID? 0= IF
        2DROP 0 SRBPROV-S-INVALID SRBPROV-D-PROVIDER-ACQUIRE EXIT
    THEN
    DUP >R
    DUP SRBPROV.CONTEXT @ SWAP SRBPROV.ACQUIRE-XT @ EXECUTE
    ROT >R _SRBPROV-RESULT R> -ROT
    2 PICK IF
        2 PICK R@ SRBPROV-LEASE-VALID? 0= IF
            2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT
        THEN
    ELSE
        OVER SRBPROV-S-NONE = 2 PICK SRBPROV-S-PENDING = OR IF
            2DROP SRBPROV-S-FAULT SRBPROV-D-INVARIANT
        THEN
    THEN
    R> DROP ;

: SRBPROV-ACQUIRE-TICK  ( lease provider -- status detail )
    2DUP SRBPROV-LEASE-VALID? 0= IF
        2DROP SRBPROV-S-INVALID SRBPROV-D-PROVIDER-ACQUIRE EXIT
    THEN
    2>R
    2R@ DUP SRBPROV.CONTEXT @ SWAP SRBPROV.ACQUIRE-TICK-XT @ EXECUTE
    2R> _SRBPROV-RETAINED-RESULT ;

: SRBPROV-OPEN  ( lease provider -- status detail )
    2DUP SRBPROV-LEASE-VALID? 0= IF
        2DROP SRBPROV-S-INVALID SRBPROV-D-BURROW-OPEN EXIT
    THEN
    2>R
    2R@ DUP SRBPROV.CONTEXT @ SWAP SRBPROV.OPEN-XT @ EXECUTE
    2R> _SRBPROV-RETAINED-RESULT ;

: SRBPROV-SERVICE  ( lease provider -- status detail )
    2DUP SRBPROV-LEASE-VALID? 0= IF
        2DROP SRBPROV-S-INVALID SRBPROV-D-BURROW-PUMP EXIT
    THEN
    2>R
    2R@ DUP SRBPROV.CONTEXT @ SWAP SRBPROV.SERVICE-XT @ EXECUTE
    2R> _SRBPROV-RETAINED-RESULT ;

: SRBPROV-CANCEL  ( lease provider -- status detail )
    2DUP SRBPROV-LEASE-VALID? 0= IF
        2DROP SRBPROV-S-INVALID SRBPROV-D-BURROW-FINALIZE EXIT
    THEN
    2>R
    2R@ DUP SRBPROV.CONTEXT @ SWAP SRBPROV.CANCEL-XT @ EXECUTE
    2R> _SRBPROV-RETAINED-RESULT ;

: SRBPROV-FINALIZE  ( lease provider -- status detail )
    2DUP SRBPROV-LEASE-VALID? 0= IF
        2DROP SRBPROV-S-INVALID SRBPROV-D-BURROW-FINALIZE EXIT
    THEN
    2>R
    2R@ DUP SRBPROV.CONTEXT @ SWAP SRBPROV.FINALIZE-XT @ EXECUTE
    2R> _SRBPROV-RETAINED-RESULT ;

: SRBPROV-RELEASE  ( lease provider -- status detail )
    2DUP SRBPROV-LEASE-VALID? 0= IF
        2DROP SRBPROV-S-INVALID SRBPROV-D-PROVIDER-RELEASE EXIT
    THEN
    2>R
    2R@ DUP SRBPROV.CONTEXT @ SWAP SRBPROV.RELEASE-XT @ EXECUTE
    _SRBPROV-RESULT
    2R> _SRBPROV-RELEASE-RESULT ;

: SRBPROV-COUNTS
  ( lease provider -- peer-count service-count status detail )
    2DUP SRBPROV-LEASE-VALID? 0= IF
        2DROP 0 0 SRBPROV-S-INVALID SRBPROV-D-INVARIANT EXIT
    THEN
    2>R
    2R@ DUP SRBPROV.CONTEXT @ SWAP SRBPROV.COUNTS-XT @ EXECUTE
    2R@ SRBPROV-LEASE-VALID? 0= IF
        2DROP 2DROP 2R> 2DROP
        0 0 SRBPROV-S-FAULT SRBPROV-D-INVARIANT EXIT
    THEN
    _SRBPROV-RESULT
    2R> 2DROP
    2>R
    2DUP 0< SWAP 0< OR IF
        2DROP 2R> 2DROP
        0 0 SRBPROV-S-FAULT SRBPROV-D-INVARIANT EXIT
    THEN
    2R> _SRBPROV-RESULT ;
