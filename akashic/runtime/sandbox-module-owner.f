\ =====================================================================
\  sandbox-module-owner.f - Exact installed sandbox module catalog
\ =====================================================================
\  This runtime object is the semantic owner above the neutral sandbox.
\  It publishes already verified plans under an exact copied RID and
\  positive owner-domain revision.  It does not compile, verify, cache,
\  persist, authenticate, choose a profile class, or grant authority.
\
\  The caller owns the catalog span and every registered plan/profile
\  allocation.  ADD pins each plan and the exact profile borrowed by that
\  plan.  The sealed mapping is immutable and resolution is read-only.
\  Before RELEASE, the owning host must close its admission gate so no new
\  RESOLVE-EXACT can begin, then cancel and drain every invocation borrowing
\  a resolved plan.  After the catalog pin is gone, it releases/frees each
\  plan before the profile borrowed by that plan.
\
\  BUILDING mutation and RELEASE are caller-serialized.  SEALED resolution
\  admits concurrent readers provided no close/release transition can race
\  those readers.  ADD only stages records; SEAL is the publication gate
\  that validates the complete table.
\ =====================================================================

PROVIDED akashic-sbox-mod-owner

REQUIRE identity.f
REQUIRE ../sandbox/plan.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Status and lifecycle
\ =====================================================================

0 CONSTANT SBOX-MODULE-OWNER-S-OK
1 CONSTANT SBOX-MODULE-OWNER-S-INVALID
2 CONSTANT SBOX-MODULE-OWNER-S-CAPACITY
3 CONSTANT SBOX-MODULE-OWNER-S-DUPLICATE
4 CONSTANT SBOX-MODULE-OWNER-S-NOT-FOUND
5 CONSTANT SBOX-MODULE-OWNER-S-STALE-REVISION
6 CONSTANT SBOX-MODULE-OWNER-S-STATE
7 CONSTANT SBOX-MODULE-OWNER-S-ALIAS

: SBOX-MODULE-OWNER-STATUS-VALID?  ( status -- flag )
    DUP SBOX-MODULE-OWNER-S-OK >=
    SWAP SBOX-MODULE-OWNER-S-ALIAS <= AND ;

1 CONSTANT SBOX-MODULE-OWNER-STATE-BUILDING
2 CONSTANT SBOX-MODULE-OWNER-STATE-SEALED

\ =====================================================================
\  Caller-owned measured representation
\ =====================================================================

0x53424D4F574E4552 CONSTANT _SMO-MAGIC  \ "SBMOWNER"

 0 CONSTANT _SMO-H-MAGIC
 8 CONSTANT _SMO-H-SELF
16 CONSTANT _SMO-H-TOTAL
24 CONSTANT _SMO-H-STATE
32 CONSTANT _SMO-H-CAPACITY
40 CONSTANT _SMO-H-COUNT
48 CONSTANT _SMO-H-RESERVED0
56 CONSTANT _SMO-H-RESERVED1
64 CONSTANT SBOX-MODULE-OWNER-HEADER-SIZE

\ RID and revision are copied.  PLAN and PROFILE remain pinned at their
\ verified native addresses until the catalog is released.
 0 CONSTANT _SMO-E-ID
32 CONSTANT _SMO-E-REVISION
40 CONSTANT _SMO-E-PLAN
48 CONSTANT _SMO-E-PROFILE
56 CONSTANT _SMO-E-RESERVED
64 CONSTANT SBOX-MODULE-OWNER-ENTRY-SIZE

: _SMO.H-MAGIC      ( owner -- address ) _SMO-H-MAGIC + ;
: _SMO.H-SELF       ( owner -- address ) _SMO-H-SELF + ;
: _SMO.H-TOTAL      ( owner -- address ) _SMO-H-TOTAL + ;
: _SMO.H-STATE      ( owner -- address ) _SMO-H-STATE + ;
: _SMO.H-CAPACITY   ( owner -- address ) _SMO-H-CAPACITY + ;
: _SMO.H-COUNT      ( owner -- address ) _SMO-H-COUNT + ;
: _SMO.H-RESERVED0  ( owner -- address ) _SMO-H-RESERVED0 + ;
: _SMO.H-RESERVED1  ( owner -- address ) _SMO-H-RESERVED1 + ;

: _SMO.E-ID        ( entry -- rid ) _SMO-E-ID + ;
: _SMO.E-REVISION  ( entry -- address ) _SMO-E-REVISION + ;
: _SMO.E-PLAN      ( entry -- address ) _SMO-E-PLAN + ;
: _SMO.E-PROFILE   ( entry -- address ) _SMO-E-PROFILE + ;
: _SMO.E-RESERVED  ( entry -- address ) _SMO-E-RESERVED + ;

\ A catalog is deliberately bounded so complete validation and duplicate
\ detection have a finite practical work ceiling.  The caller still chooses
\ any capacity from one through this production host limit.
256 CONSTANT SBOX-MODULE-OWNER-CAPACITY-MAX

: SBOX-MODULE-OWNER-MEASURE  ( capacity -- owner-u|0 status )
    DUP 1 < IF
        DROP 0 SBOX-MODULE-OWNER-S-INVALID EXIT
    THEN
    DUP SBOX-MODULE-OWNER-CAPACITY-MAX U> IF
        DROP 0 SBOX-MODULE-OWNER-S-CAPACITY EXIT
    THEN
    SBOX-MODULE-OWNER-ENTRY-SIZE *
    SBOX-MODULE-OWNER-HEADER-SIZE +
    SBOX-MODULE-OWNER-S-OK ;

: _SMO-NTH  ( index owner -- entry )
    SBOX-MODULE-OWNER-HEADER-SIZE +
    SWAP SBOX-MODULE-OWNER-ENTRY-SIZE * + ;

: _SMO-SPAN?  ( address length -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _SMO-FIXED-SPAN?  ( owner -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    SBOX-MODULE-OWNER-HEADER-SIZE _SMO-SPAN? ;

: _SMO-HEADER-ZERO?  ( owner -- flag )
    SBOX-MODULE-OWNER-HEADER-SIZE 0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SMO-HEADER?  ( owner -- flag )
    DUP _SMO-FIXED-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SMO.H-MAGIC @ _SMO-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SMO.H-SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SMO.H-RESERVED0 @ IF DROP 0 EXIT THEN
    DUP _SMO.H-RESERVED1 @ IF DROP 0 EXIT THEN
    DUP _SMO.H-STATE @ DUP SBOX-MODULE-OWNER-STATE-BUILDING =
        SWAP SBOX-MODULE-OWNER-STATE-SEALED = OR 0= IF
        DROP 0 EXIT
    THEN

    DUP _SMO.H-CAPACITY @ SBOX-MODULE-OWNER-MEASURE
    DUP IF 2DROP DROP 0 EXIT THEN
    DROP
    OVER _SMO.H-TOTAL @ <> IF DROP 0 EXIT THEN
    DUP DUP _SMO.H-TOTAL @ _SMO-SPAN? 0= IF DROP 0 EXIT THEN

    DUP _SMO.H-COUNT @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER _SMO.H-CAPACITY @ U> IF DROP 0 EXIT THEN
    DROP -1 ;

: _SMO-BUILDING?  ( owner -- flag )
    DUP _SMO-HEADER? 0= IF DROP 0 EXIT THEN
    _SMO.H-STATE @ SBOX-MODULE-OWNER-STATE-BUILDING = ;

: _SMO-SEALED?  ( owner -- flag )
    DUP _SMO-HEADER? 0= IF DROP 0 EXIT THEN
    _SMO.H-STATE @ SBOX-MODULE-OWNER-STATE-SEALED = ;

: _SMO-EXACT-KEY?  ( rid revision -- flag )
    OVER RID-SIZE _SMO-SPAN? 0= IF 2DROP 0 EXIT THEN
    OVER RID-PRESENT?
    SWAP 0> AND
    NIP ;

\ =====================================================================
\  Installed-plan invariants and exact lookup
\ =====================================================================

: _SMO-PLAN-PAIR?  ( plan profile -- flag )
    >R
    DUP SBOX-PLAN-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    R@ SBOX-PROFILE-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    DUP SBOX-PLAN-PROFILE@ R@ =
    NIP R> DROP ;

: _SMO-ENTRY-VALID?  ( entry -- flag )
    DUP _SMO.E-ID RID-PRESENT?
    OVER _SMO.E-REVISION @ 0> AND
    OVER _SMO.E-PLAN @ 2 PICK _SMO.E-PROFILE @
        _SMO-PLAN-PAIR? AND
    SWAP _SMO.E-RESERVED @ 0= AND ;

: _SMO-FIND-EXACT  ( rid revision owner -- index|-1 )
    DUP _SMO.H-COUNT @ 0 ?DO
        I OVER _SMO-NTH
        DUP _SMO.E-ID 4 PICK RID= IF
            DUP _SMO.E-REVISION @ 3 PICK = IF
                DROP 2DROP DROP I UNLOOP EXIT
            THEN
        THEN
        DROP
    LOOP
    2DROP DROP -1 ;

: _SMO-FIND-ID  ( rid owner -- index|-1 )
    DUP _SMO.H-COUNT @ 0 ?DO
        I OVER _SMO-NTH _SMO.E-ID
        2 PICK RID= IF
            2DROP I UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _SMO-UNIQUE?  ( owner -- flag )
    DUP _SMO.H-COUNT @ 0 ?DO
        DUP _SMO.H-COUNT @ I 1+ ?DO
            J OVER _SMO-NTH
            I 2 PICK _SMO-NTH
            2DUP _SMO.E-ID SWAP _SMO.E-ID RID= IF
                DUP _SMO.E-REVISION @
                    2 PICK _SMO.E-REVISION @ = IF
                    2DROP DROP 0 UNLOOP UNLOOP EXIT
                THEN
            THEN
            2DROP
        LOOP
    LOOP
    DROP -1 ;

: _SMO-ENTRIES-VALID?  ( owner -- flag )
    DUP _SMO.H-COUNT @ 0 ?DO
        I OVER _SMO-NTH _SMO-ENTRY-VALID? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    _SMO-UNIQUE? ;

: SBOX-MODULE-OWNER-VALID?  ( owner -- flag )
    DUP _SMO-HEADER? 0= IF DROP 0 EXIT THEN
    _SMO-ENTRIES-VALID? ;

: SBOX-MODULE-OWNER-SEALED?  ( owner -- flag )
    DUP _SMO-SEALED? IF SBOX-MODULE-OWNER-VALID? ELSE DROP 0 THEN ;

: _SMO-ENTRY-SPAN-DISJOINT?
  ( address length entry -- flag )
    >R
    2DUP
    R@ _SMO.E-PLAN @ DUP SBOX-PLAN-TOTAL@
        MSPAN-OVERLAP? 0=
    2 PICK 2 PICK
    R@ _SMO.E-PROFILE @ SBOX-PROFILE-SIZE
        MSPAN-OVERLAP? 0= AND
    ROT DROP SWAP DROP
    R> DROP ;

\ A sealed owner pins three lifetime domains: its complete measured catalog
\ span and every borrowed verified plan/profile pair.  Callers that publish
\ their own mutable descriptors use this predicate before writing so catalog
\ release can never invalidate or erase those descriptors.
: SBOX-MODULE-OWNER-SPAN-DISJOINT?
  ( address length owner -- flag )
    2 PICK 2 PICK _SMO-SPAN? 0= IF
        2DROP DROP 0 EXIT
    THEN
    DUP SBOX-MODULE-OWNER-SEALED? 0= IF
        2DROP DROP 0 EXIT
    THEN
    2 PICK 2 PICK 2 PICK DUP _SMO.H-TOTAL @
        MSPAN-OVERLAP? IF
        2DROP DROP 0 EXIT
    THEN
    DUP _SMO.H-COUNT @ 0 ?DO
        2 PICK 2 PICK
        I 3 PICK _SMO-NTH
        _SMO-ENTRY-SPAN-DISJOINT? 0= IF
            2DROP DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP DROP -1 ;

: _SMO-KEY-DISJOINT?  ( rid owner -- flag )
    OVER RID-SIZE
    2 PICK DUP _SMO.H-TOTAL @ MSPAN-OVERLAP? 0=
    NIP NIP ;

: _SMO-PLAN-DISJOINT?  ( plan owner -- flag )
    >R
    DUP DUP SBOX-PLAN-TOTAL@
        R@ DUP _SMO.H-TOTAL @ MSPAN-OVERLAP? 0=
    OVER SBOX-PLAN-PROFILE@ SBOX-PROFILE-SIZE
        R@ DUP _SMO.H-TOTAL @ MSPAN-OVERLAP? 0= AND
    NIP R> DROP ;

\ =====================================================================
\  Build, seal, exact resolution, and release
\ =====================================================================

: _SMO-DROP3>STATUS  ( x1 x2 x3 status -- status )
    >R 2DROP DROP R> ;

: _SMO-DROP4>STATUS  ( x1 x2 x3 x4 status -- status )
    >R 2DROP 2DROP R> ;

: SBOX-MODULE-OWNER-INIT
  ( capacity owner owner-u -- status )
    2 PICK SBOX-MODULE-OWNER-MEASURE
    DUP IF _SMO-DROP4>STATUS EXIT THEN
    DROP
    2DUP <> IF
        SBOX-MODULE-OWNER-S-CAPACITY _SMO-DROP4>STATUS EXIT
    THEN
    2 PICK DUP 0= SWAP 7 AND OR IF
        SBOX-MODULE-OWNER-S-INVALID _SMO-DROP4>STATUS EXIT
    THEN
    2 PICK 2 PICK _SMO-SPAN? 0= IF
        SBOX-MODULE-OWNER-S-INVALID _SMO-DROP4>STATUS EXIT
    THEN

    SWAP DROP
    2DUP 0 FILL
    OVER DUP _SMO.H-SELF !
    DUP 2 PICK _SMO.H-TOTAL !
    SBOX-MODULE-OWNER-STATE-BUILDING 2 PICK _SMO.H-STATE !
    2 PICK 2 PICK _SMO.H-CAPACITY !
    _SMO-MAGIC 2 PICK _SMO.H-MAGIC !
    2DROP DROP
    SBOX-MODULE-OWNER-S-OK ;

: SBOX-MODULE-OWNER-ADD  ( rid revision plan owner -- status )
    DUP _SMO-BUILDING? 0= IF
        SBOX-MODULE-OWNER-S-STATE _SMO-DROP4>STATUS EXIT
    THEN
    3 PICK 3 PICK _SMO-EXACT-KEY? 0= IF
        SBOX-MODULE-OWNER-S-INVALID _SMO-DROP4>STATUS EXIT
    THEN
    1 PICK DUP SBOX-PLAN-PROFILE@ _SMO-PLAN-PAIR? 0= IF
        SBOX-MODULE-OWNER-S-INVALID _SMO-DROP4>STATUS EXIT
    THEN
    3 PICK 1 PICK _SMO-KEY-DISJOINT? 0= IF
        SBOX-MODULE-OWNER-S-ALIAS _SMO-DROP4>STATUS EXIT
    THEN
    1 PICK 1 PICK _SMO-PLAN-DISJOINT? 0= IF
        SBOX-MODULE-OWNER-S-ALIAS _SMO-DROP4>STATUS EXIT
    THEN

    3 PICK 3 PICK 2 PICK _SMO-FIND-EXACT 0>= IF
        SBOX-MODULE-OWNER-S-DUPLICATE _SMO-DROP4>STATUS EXIT
    THEN
    DUP _SMO.H-COUNT @ OVER _SMO.H-CAPACITY @ >= IF
        SBOX-MODULE-OWNER-S-CAPACITY _SMO-DROP4>STATUS EXIT
    THEN

    DUP _SMO.H-COUNT @ 1 PICK _SMO-NTH
    DUP SBOX-MODULE-OWNER-ENTRY-SIZE 0 FILL
    4 PICK OVER _SMO.E-ID RID-COPY
    3 PICK OVER _SMO.E-REVISION !
    2 PICK OVER _SMO.E-PLAN !
    2 PICK SBOX-PLAN-PROFILE@ OVER _SMO.E-PROFILE !
    DROP
    1 OVER _SMO.H-COUNT +!
    2DROP 2DROP
    SBOX-MODULE-OWNER-S-OK ;

: SBOX-MODULE-OWNER-SEAL  ( owner -- status )
    DUP _SMO-BUILDING? 0= IF
        DROP SBOX-MODULE-OWNER-S-STATE EXIT
    THEN
    DUP _SMO-ENTRIES-VALID? 0= IF
        DROP SBOX-MODULE-OWNER-S-INVALID EXIT
    THEN
    DUP _SMO.H-COUNT @ 0= IF
        DROP SBOX-MODULE-OWNER-S-INVALID EXIT
    THEN
    SBOX-MODULE-OWNER-STATE-SEALED SWAP _SMO.H-STATE !
    SBOX-MODULE-OWNER-S-OK ;

: _SMO-RESOLVE-FAIL  ( rid revision owner status -- 0 0 status )
    >R 2DROP DROP 0 0 R> ;

: SBOX-MODULE-OWNER-RESOLVE-EXACT
  ( rid revision owner -- plan profile status )
    DUP _SMO-SEALED? 0= IF
        SBOX-MODULE-OWNER-S-STATE _SMO-RESOLVE-FAIL EXIT
    THEN
    2 PICK 2 PICK _SMO-EXACT-KEY? 0= IF
        SBOX-MODULE-OWNER-S-INVALID _SMO-RESOLVE-FAIL EXIT
    THEN

    2 PICK 2 PICK 2 PICK _SMO-FIND-EXACT DUP 0< IF
        DROP
        2 PICK 1 PICK _SMO-FIND-ID 0< IF
            SBOX-MODULE-OWNER-S-NOT-FOUND
        ELSE
            SBOX-MODULE-OWNER-S-STALE-REVISION
        THEN
        _SMO-RESOLVE-FAIL EXIT
    THEN

    2SWAP 2DROP
    DUP 2 PICK _SMO-NTH
    DUP _SMO-ENTRY-VALID? 0= IF
        2DROP DROP
        0 0 SBOX-MODULE-OWNER-S-INVALID EXIT
    THEN
    DUP _SMO.E-PLAN @
    OVER _SMO.E-PROFILE @
    2SWAP 2DROP
    ROT DROP
    SBOX-MODULE-OWNER-S-OK ;

: SBOX-MODULE-OWNER-COUNT@  ( owner -- count|0 )
    DUP _SMO-HEADER? IF _SMO.H-COUNT @ ELSE DROP 0 THEN ;

: SBOX-MODULE-OWNER-RELEASE  ( owner -- status )
    DUP _SMO-FIXED-SPAN? 0= IF
        DROP SBOX-MODULE-OWNER-S-INVALID EXIT
    THEN
    DUP _SMO-HEADER-ZERO? IF
        DROP SBOX-MODULE-OWNER-S-OK EXIT
    THEN
    DUP SBOX-MODULE-OWNER-VALID? 0= IF
        DROP SBOX-MODULE-OWNER-S-INVALID EXIT
    THEN
    DUP _SMO.H-TOTAL @ >R
    0 OVER _SMO.H-MAGIC !
    DUP R@ 0 FILL
    R> DROP DROP
    SBOX-MODULE-OWNER-S-OK ;
