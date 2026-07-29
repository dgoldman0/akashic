\ =====================================================================
\  sandbox-component.f - Headless Desk sandbox compute component
\ =====================================================================
\  This is the trusted Desk-owned lifecycle adapter for one headless
\  compute component.  It borrows one sealed exact module owner and one
\  active parent Context, copies already materialized value/execution
\  limits, and embeds one thin sandbox invocation host.  Each successful
\  ADMIT resolves an exact (RID, positive revision) and exact typed entry,
\  copies the typed input through SBOX-HOST, and publishes a new positive
\  invocation generation.
\
\  CLOSE permanently rejects new admission and synchronously cancels a
\  runnable invocation with HOST-SHUTDOWN detail.  A terminal result may
\  still be detached after CLOSE.  DRAIN is the explicit discard path: it
\  releases any remaining host before ending the module-owner, plan,
\  profile, and parent-Context borrows.  RELEASE is the idempotent safety
\  net which closes, drains, and zeros the caller-owned component.
\
\  The detached result envelope owns an exact heap allocation containing
\  the self-contained SBOX-VM result.  It therefore survives component,
\  module owner, plan/profile, and parent-Context teardown.
\
\  There is deliberately no APP-DESC, native callback, widget, Agent,
\  provider, Practice, declaration, schema, digest, cache, persistence,
\  VFS, capability, or import dispatch behavior here.
\ =====================================================================

PROVIDED akashic-tui-desk-sbox-component

REQUIRE ../../../runtime/sandbox-module-owner.f
REQUIRE ../../../runtime/sandbox-host.f
REQUIRE ../../../utils/caller-span.f
REQUIRE ../../../utils/memory-span.f

\ =====================================================================
\  Public status and lifecycle states
\ =====================================================================

0  CONSTANT DESK-SBOX-S-OK
1  CONSTANT DESK-SBOX-S-INVALID
2  CONSTANT DESK-SBOX-S-STATE
3  CONSTANT DESK-SBOX-S-OWNER
4  CONSTANT DESK-SBOX-S-NOT-FOUND
5  CONSTANT DESK-SBOX-S-STALE-REVISION
6  CONSTANT DESK-SBOX-S-PROFILE
7  CONSTANT DESK-SBOX-S-ENTRY
8  CONSTANT DESK-SBOX-S-BUDGET
9  CONSTANT DESK-SBOX-S-HOST
10 CONSTANT DESK-SBOX-S-RESULT
11 CONSTANT DESK-SBOX-S-ALIAS
12 CONSTANT DESK-SBOX-S-NOMEM
13 CONSTANT DESK-SBOX-S-STALE-GENERATION

: DESK-SBOX-STATUS-VALID?  ( status -- flag )
    DUP DESK-SBOX-S-OK >=
    SWAP DESK-SBOX-S-STALE-GENERATION <= AND ;

1 CONSTANT DESK-SBOX-COMPONENT-STATE-OPEN
2 CONSTANT DESK-SBOX-COMPONENT-STATE-CLOSING
3 CONSTANT DESK-SBOX-COMPONENT-STATE-DRAINED

0x44534258434F4D50 CONSTANT _DSC-MAGIC  \ "DSBXCOMP"
0x4453425852455354 CONSTANT _DSR-MAGIC  \ "DSBXREST"
0x7FFFFFFFFFFFFFFF CONSTANT _DSC-GENERATION-MAX

\ =====================================================================
\  Fixed caller-owned component
\ =====================================================================

  0 CONSTANT _DSC-MAGIC-OFF
  8 CONSTANT _DSC-SELF
 16 CONSTANT _DSC-STATE
 24 CONSTANT _DSC-OWNER
 32 CONSTANT _DSC-PARENT
 40 CONSTANT _DSC-SEQUENCE
 48 CONSTANT _DSC-LIVE-GENERATION
 56 CONSTANT _DSC-PLAN
 64 CONSTANT _DSC-PROFILE
 72 CONSTANT _DSC-ENTRY
 80 CONSTANT _DSC-REVISION
 88 CONSTANT _DSC-INSTRUCTION-BUDGET
 96 CONSTANT _DSC-VALUE-OP-BUDGET
104 CONSTANT _DSC-COPY-BUDGET
112 CONSTANT _DSC-RESERVED
120 CONSTANT _DSC-RID
152 CONSTANT _DSC-LIMITS
256 CONSTANT _DSC-HOST
768 CONSTANT DESK-SBOX-COMPONENT-SIZE

: _DSC.MAGIC               ( component -- address ) _DSC-MAGIC-OFF + ;
: _DSC.SELF                ( component -- address ) _DSC-SELF + ;
: _DSC.STATE               ( component -- address ) _DSC-STATE + ;
: _DSC.OWNER               ( component -- address ) _DSC-OWNER + ;
: _DSC.PARENT              ( component -- address ) _DSC-PARENT + ;
: _DSC.SEQUENCE            ( component -- address ) _DSC-SEQUENCE + ;
: _DSC.LIVE-GENERATION     ( component -- address )
    _DSC-LIVE-GENERATION + ;
: _DSC.PLAN                ( component -- address ) _DSC-PLAN + ;
: _DSC.PROFILE             ( component -- address ) _DSC-PROFILE + ;
: _DSC.ENTRY               ( component -- address ) _DSC-ENTRY + ;
: _DSC.REVISION            ( component -- address ) _DSC-REVISION + ;
: _DSC.INSTRUCTION-BUDGET  ( component -- address )
    _DSC-INSTRUCTION-BUDGET + ;
: _DSC.VALUE-OP-BUDGET     ( component -- address )
    _DSC-VALUE-OP-BUDGET + ;
: _DSC.COPY-BUDGET         ( component -- address ) _DSC-COPY-BUDGET + ;
: _DSC.RESERVED            ( component -- address ) _DSC-RESERVED + ;
: _DSC.RID                 ( component -- rid ) _DSC-RID + ;
: _DSC.LIMITS              ( component -- limits ) _DSC-LIMITS + ;
: _DSC.HOST                ( component -- host ) _DSC-HOST + ;

: _DSC-SPAN?  ( address length -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _DSC-ZERO?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _DSC-FIXED?  ( component -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DESK-SBOX-COMPONENT-SIZE _DSC-SPAN? ;

: _DSC-HEADER?  ( component -- flag )
    DUP _DSC-FIXED? 0= IF DROP 0 EXIT THEN
    DUP _DSC.MAGIC @ _DSC-MAGIC <> IF DROP 0 EXIT THEN
    DUP _DSC.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _DSC.STATE @ DUP DESK-SBOX-COMPONENT-STATE-OPEN =
    OVER DESK-SBOX-COMPONENT-STATE-CLOSING = OR
    SWAP DESK-SBOX-COMPONENT-STATE-DRAINED = OR 0= IF
        DROP 0 EXIT
    THEN
    _DSC.RESERVED @ 0= ;

: _DSC-PURE-PROFILE?  ( profile -- flag )
    DUP SBOX-PROFILE-VALID? 0= IF DROP 0 EXIT THEN
    SBOX-PROFILE-TAG@
    DUP IF 2DROP 0 EXIT THEN
    DROP SBOX-PROFILE-PURE-TAG = ;

: _DSC-ENTRY-TYPED?  ( entry plan -- flag )
    >R
    DUP 0< IF DROP R> DROP 0 EXIT THEN
    DUP R@ SBOX-PLAN-ENTRY-N@ >= IF DROP R> DROP 0 EXIT THEN
    R@ SBOX-PLAN-ENTRY-SIGNATURE@
    0= IF DROP R> DROP 0 EXIT THEN
    SBOX-ABI-SIGNATURE-VALUE-TO-VALUE =
    R> DROP ;

: _DSC-LIMITS-COPY  ( source destination -- status )
    OVER SBOX-VALUE-LIMITS-VALID? 0= IF
        2DROP SBOX-VALUE-S-STATE EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-BEGIN
    DUP IF -ROT 2DROP EXIT THEN
    DROP
    SBOX-VALUE-LIMIT-COUNT 0 ?DO
        I 2 PICK SBOX-VALUE-LIMIT@
        DUP IF
            2DROP 2DROP
            SBOX-VALUE-S-STATE UNLOOP EXIT
        THEN
        DROP
        I 2 PICK SBOX-VALUE-LIMIT!
        DUP IF -ROT 2DROP UNLOOP EXIT THEN
        DROP
    LOOP
    NIP SBOX-VALUE-LIMITS-SEAL ;

: _DSC-BUDGET-WITHIN?  ( requested field plan -- flag )
    SBOX-PLAN-PROFILE@ SBOX-PROFILE-LIMIT@
    DUP IF
        2DROP DROP 0 EXIT
    THEN
    DROP U> 0= ;

: _DSC-PLAN-BUDGETS?  ( plan component -- flag )
    DUP _DSC.INSTRUCTION-BUDGET @
    SBOX-PROFILE-LIMIT-MAX-BUDGET
    3 PICK _DSC-BUDGET-WITHIN?
    1 PICK _DSC.VALUE-OP-BUDGET @
    SBOX-PROFILE-LIMIT-VALUE-OPS
    4 PICK _DSC-BUDGET-WITHIN? AND
    1 PICK _DSC.COPY-BUDGET @
    SBOX-PROFILE-LIMIT-COPY-BYTES
    4 PICK _DSC-BUDGET-WITHIN? AND
    NIP NIP ;

: _DSC-PURE-PAIR?  ( plan profile -- flag )
    >R
    DUP SBOX-PLAN-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    R@ _DSC-PURE-PROFILE? 0= IF DROP R> DROP 0 EXIT THEN
    DUP SBOX-PLAN-PROFILE@ R@ <> IF DROP R> DROP 0 EXIT THEN
    SBOX-PLAN-IMPORT-N@ 0=
    R> DROP ;

\ The component, its copied limits source, parent Context, and complete
\ installed-plan graph are independent lifetime domains before INIT writes.
: _DSC-INIT-DISJOINT?
  ( owner parent limits component -- flag )
    >R
    1 PICK CTX-SIZE
    R@ DESK-SBOX-COMPONENT-SIZE MSPAN-OVERLAP? IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    R@ DESK-SBOX-COMPONENT-SIZE
    4 PICK SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    1 PICK CTX-SIZE
    4 PICK SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-SIZE
    R@ DESK-SBOX-COMPONENT-SIZE MSPAN-OVERLAP? IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-SIZE
    3 PICK CTX-SIZE MSPAN-OVERLAP? IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-SIZE
    4 PICK SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    2DROP DROP R> DROP -1 ;

: _DSC-LIFETIMES?  ( component -- flag )
    >R
    R@ _DSC.OWNER @ DUP SBOX-MODULE-OWNER-SEALED? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ _DSC.PARENT @ DUP CTX-VALID? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        R> DROP 0 EXIT
    THEN
    R@ DESK-SBOX-COMPONENT-SIZE
    R@ _DSC.OWNER @
    SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        R> DROP 0 EXIT
    THEN
    R@ DESK-SBOX-COMPONENT-SIZE
    R@ _DSC.PARENT @ CTX-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R@ _DSC.PARENT @ CTX-SIZE
    R@ _DSC.OWNER @
    SBOX-MODULE-OWNER-SPAN-DISJOINT?
    R> DROP ;

: _DSC-LIVE?  ( component -- flag )
    _DSC.LIVE-GENERATION @ 0> ;

: _DSC-LIVE-MAPPING?  ( component -- flag )
    >R
    R@ _DSC.RID
    R@ _DSC.REVISION @
    R@ _DSC.OWNER @
    SBOX-MODULE-OWNER-RESOLVE-EXACT
    DUP IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ _DSC.PROFILE @ =
    SWAP R@ _DSC.PLAN @ = AND
    R> DROP ;

: _DSC-LIVE-SHAPE?  ( component -- flag )
    DUP _DSC-LIVE? 0= IF
        DUP _DSC.LIVE-GENERATION @ 0=
        OVER _DSC.PLAN @ 0= AND
        OVER _DSC.PROFILE @ 0= AND
        OVER _DSC.ENTRY @ 0= AND
        OVER _DSC.REVISION @ 0= AND
        OVER _DSC.RID RID-SIZE _DSC-ZERO? AND
        SWAP _DSC.HOST SBOX-HOST-INVOCATION-SIZE _DSC-ZERO? AND
        EXIT
    THEN
    DUP _DSC.LIVE-GENERATION @
    OVER _DSC.SEQUENCE @ = 0= IF DROP 0 EXIT THEN
    DUP _DSC-LIVE-MAPPING? 0= IF DROP 0 EXIT THEN
    DUP _DSC.PLAN @ OVER _DSC.PROFILE @
        _DSC-PURE-PAIR? 0= IF DROP 0 EXIT THEN
    DUP _DSC.PLAN @ OVER _DSC-PLAN-BUDGETS? 0= IF DROP 0 EXIT THEN
    DUP _DSC.ENTRY @ OVER _DSC.PLAN @
        _DSC-ENTRY-TYPED? 0= IF DROP 0 EXIT THEN
    _DSC.HOST SBOX-HOST-VALID? ;

: DESK-SBOX-COMPONENT-VALID?  ( component -- flag )
    DUP _DSC-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _DSC.STATE @ DESK-SBOX-COMPONENT-STATE-DRAINED = IF
        _DSC.OWNER
        DESK-SBOX-COMPONENT-SIZE _DSC-OWNER -
        _DSC-ZERO? EXIT
    THEN
    DUP _DSC.SEQUENCE @ DUP 0<
        SWAP _DSC-GENERATION-MAX > OR IF DROP 0 EXIT THEN
    DUP _DSC.INSTRUCTION-BUDGET @ 0> 0= IF DROP 0 EXIT THEN
    DUP _DSC.VALUE-OP-BUDGET @ 0> 0= IF DROP 0 EXIT THEN
    DUP _DSC.COPY-BUDGET @ 0> 0= IF DROP 0 EXIT THEN
    DUP _DSC.LIMITS SBOX-VALUE-LIMITS-VALID? 0= IF DROP 0 EXIT THEN
    DUP _DSC-LIFETIMES? 0= IF DROP 0 EXIT THEN
    _DSC-LIVE-SHAPE? ;

: _DSC-EXTERNAL-SPAN?  ( address length component -- flag )
    >R
    2DUP _DSC-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ DESK-SBOX-COMPONENT-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _DSC.PARENT @ CTX-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _DSC.OWNER @ SBOX-MODULE-OWNER-SPAN-DISJOINT?
    R> DROP ;

\ =====================================================================
\  Initialization
\ =====================================================================

: _DSC-DROP7>STATUS  ( x1 x2 x3 x4 x5 x6 x7 status -- status )
    >R 2DROP 2DROP 2DROP DROP R> ;

: _DSC-INIT-BOUNDARY
  ( owner parent limits instruction value-ops copy component -- same status )
    DUP _DSC-FIXED? 0= IF DESK-SBOX-S-INVALID EXIT THEN
    DUP DESK-SBOX-COMPONENT-SIZE _DSC-ZERO? 0= IF
        DESK-SBOX-S-STATE EXIT
    THEN
    6 PICK SBOX-MODULE-OWNER-SEALED? 0= IF
        DESK-SBOX-S-OWNER EXIT
    THEN
    5 PICK DUP CTX-VALID? 0= IF
        DROP DESK-SBOX-S-INVALID EXIT
    THEN
    CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        DESK-SBOX-S-INVALID EXIT
    THEN
    4 PICK SBOX-VALUE-LIMITS-VALID? 0= IF
        DESK-SBOX-S-INVALID EXIT
    THEN
    3 PICK 0> 0= IF DESK-SBOX-S-BUDGET EXIT THEN
    2 PICK 0> 0= IF DESK-SBOX-S-BUDGET EXIT THEN
    1 PICK 0> 0= IF DESK-SBOX-S-BUDGET EXIT THEN
    6 PICK 6 PICK 6 PICK 3 PICK
        _DSC-INIT-DISJOINT? 0= IF
        DESK-SBOX-S-ALIAS EXIT
    THEN
    DESK-SBOX-S-OK ;

: DESK-SBOX-COMPONENT-INIT
  ( owner parent limits instruction value-ops copy component -- status )
    _DSC-INIT-BOUNDARY
    DUP IF _DSC-DROP7>STATUS EXIT THEN
    DROP

    DUP >R
    R@ DESK-SBOX-COMPONENT-SIZE 0 FILL
    R@ R@ _DSC.SELF !
    6 PICK R@ _DSC.OWNER !
    5 PICK R@ _DSC.PARENT !
    3 PICK R@ _DSC.INSTRUCTION-BUDGET !
    2 PICK R@ _DSC.VALUE-OP-BUDGET !
    1 PICK R@ _DSC.COPY-BUDGET !
    4 PICK R@ _DSC.LIMITS _DSC-LIMITS-COPY
    DUP IF
        DROP
        R@ DESK-SBOX-COMPONENT-SIZE 0 FILL
        DESK-SBOX-S-INVALID
        _DSC-DROP7>STATUS R> DROP EXIT
    THEN
    DROP
    DESK-SBOX-COMPONENT-STATE-OPEN R@ _DSC.STATE !
    _DSC-MAGIC R@ _DSC.MAGIC !
    R@ DESK-SBOX-COMPONENT-VALID? 0= IF
        R@ DESK-SBOX-COMPONENT-SIZE 0 FILL
        DESK-SBOX-S-INVALID
        _DSC-DROP7>STATUS R> DROP EXIT
    THEN
    DESK-SBOX-S-OK _DSC-DROP7>STATUS
    R> DROP ;

\ =====================================================================
\  Exact invocation admission
\ =====================================================================

: _DSC-OWNER>STATUS  ( owner-status -- component-status )
    DUP SBOX-MODULE-OWNER-S-NOT-FOUND = IF
        DROP DESK-SBOX-S-NOT-FOUND EXIT
    THEN
    SBOX-MODULE-OWNER-S-STALE-REVISION = IF
        DESK-SBOX-S-STALE-REVISION
    ELSE
        DESK-SBOX-S-OWNER
    THEN ;

: _DSC-DROP4>RESOLUTION
  ( x1 x2 x3 x4 plan profile entry status -- plan profile entry status )
    >R >R >R >R
    2DROP 2DROP
    R> R> R> R> ;

: _DSC-RESOLVE
  ( rid revision name name-u component -- plan profile entry status )
    >R
    3 PICK 3 PICK R@ _DSC.OWNER @
        SBOX-MODULE-OWNER-RESOLVE-EXACT
    DUP IF
        _DSC-OWNER>STATUS >R
        2DROP 2DROP 2DROP
        R> R> DROP >R
        0 0 -1 R> EXIT
    THEN
    DROP
    2DUP _DSC-PURE-PAIR? 0= IF
        2DROP 2DROP 2DROP
        R> DROP
        0 0 -1 DESK-SBOX-S-PROFILE EXIT
    THEN
    OVER R@ _DSC-PLAN-BUDGETS? 0= IF
        2DROP 2DROP 2DROP
        R> DROP
        0 0 -1 DESK-SBOX-S-BUDGET EXIT
    THEN

    3 PICK 3 PICK 3 PICK SBOX-HOST-ENTRY-RESOLVE-EXACT
    DUP IF
        2DROP
        2DROP 2DROP 2DROP
        R> DROP
        0 0 -1 DESK-SBOX-S-ENTRY EXIT
    THEN
    DROP
    DUP 3 PICK _DSC-ENTRY-TYPED? 0= IF
        2DROP 2DROP 2DROP DROP
        R> DROP
        0 0 -1 DESK-SBOX-S-ENTRY EXIT
    THEN
    R> DROP
    DESK-SBOX-S-OK _DSC-DROP4>RESOLUTION ;

: _DSC-ADMIT-BOUNDARY
  ( rid revision name name-u input input-u component -- same status )
    DUP DESK-SBOX-COMPONENT-VALID? 0= IF
        DESK-SBOX-S-INVALID EXIT
    THEN
    DUP _DSC.STATE @ DESK-SBOX-COMPONENT-STATE-OPEN <> IF
        DESK-SBOX-S-STATE EXIT
    THEN
    DUP _DSC-LIVE? IF DESK-SBOX-S-STATE EXIT THEN
    DUP _DSC.SEQUENCE @ _DSC-GENERATION-MAX >= IF
        DESK-SBOX-S-STATE EXIT
    THEN
    5 PICK 0> 0= IF DESK-SBOX-S-INVALID EXIT THEN
    6 PICK RID-SIZE 2 PICK _DSC-EXTERNAL-SPAN? 0= IF
        DESK-SBOX-S-ALIAS EXIT
    THEN
    6 PICK RID-PRESENT? 0= IF DESK-SBOX-S-INVALID EXIT THEN
    3 PICK 0> 0= IF DESK-SBOX-S-ENTRY EXIT THEN
    4 PICK 4 PICK 2 PICK _DSC-EXTERNAL-SPAN? 0= IF
        DESK-SBOX-S-ALIAS EXIT
    THEN
    1 PICK 0> 0= IF DESK-SBOX-S-INVALID EXIT THEN
    2 PICK 2 PICK 2 PICK _DSC-EXTERNAL-SPAN? 0= IF
        DESK-SBOX-S-ALIAS EXIT
    THEN
    DESK-SBOX-S-OK ;

: _DSC-DROP10>GEN-STATUS
  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 generation status -- generation status )
    >R >R
    2DROP 2DROP 2DROP 2DROP 2DROP
    R> R> ;

: _DSC-ADMIT-START
  ( rid revision name name-u input input-u component plan profile entry -- generation status )
    3 PICK >R
    R@ _DSC.PARENT @
    3 PICK
    2 PICK
    8 PICK
    8 PICK
    R@ _DSC.LIMITS
    R@ _DSC.INSTRUCTION-BUDGET @
    R@ _DSC.VALUE-OP-BUDGET @
    R@ _DSC.COPY-BUDGET @
    R@ _DSC.HOST
    SBOX-HOST-INIT
    DUP IF
        DROP
        R> DROP
        0 DESK-SBOX-S-HOST
        _DSC-DROP10>GEN-STATUS EXIT
    THEN
    DROP

    1 R@ _DSC.SEQUENCE +!
    9 PICK R@ _DSC.RID RID-COPY
    8 PICK R@ _DSC.REVISION !
    2 PICK R@ _DSC.PLAN !
    1 PICK R@ _DSC.PROFILE !
    DUP R@ _DSC.ENTRY !
    R@ _DSC.SEQUENCE @ R@ _DSC.LIVE-GENERATION !
    R@ _DSC.SEQUENCE @ DESK-SBOX-S-OK
    R> DROP
    _DSC-DROP10>GEN-STATUS ;

: DESK-SBOX-ADMIT
  ( rid revision entry entry-u input input-u component -- generation|0 status )
    _DSC-ADMIT-BOUNDARY
    DUP IF
        >R 2DROP 2DROP 2DROP DROP 0 R> EXIT
    THEN
    DROP
    6 PICK 6 PICK 6 PICK 6 PICK 4 PICK _DSC-RESOLVE
    DUP IF
        >R 2DROP 2DROP
        2DROP 2DROP 2DROP
        0 R> EXIT
    THEN
    DROP
    _DSC-ADMIT-START ;

\ =====================================================================
\  Generation-bound execution
\ =====================================================================

: _DSC-HANDLE-STATUS  ( generation component -- status )
    DUP DESK-SBOX-COMPONENT-VALID? 0= IF
        2DROP DESK-SBOX-S-INVALID EXIT
    THEN
    DUP _DSC-LIVE? 0= IF
        2DROP DESK-SBOX-S-STATE EXIT
    THEN
    _DSC.LIVE-GENERATION @ =
    IF DESK-SBOX-S-OK ELSE DESK-SBOX-S-STALE-GENERATION THEN ;

: _DSC-DROP3>RUN-STATUS
  ( x1 x2 x3 run-state status -- run-state status )
    >R >R 2DROP DROP R> R> ;

: DESK-SBOX-RUN-SLICE
  ( max-steps generation component -- run-state status )
    1 PICK 1 PICK _DSC-HANDLE-STATUS
    DUP IF
        >R 2DROP DROP SBOX-VM-RUN-INVALID R> EXIT
    THEN
    DROP
    2 PICK 0> 0= IF
        2DROP DROP
        SBOX-VM-RUN-INVALID DESK-SBOX-S-INVALID EXIT
    THEN
    2 PICK OVER _DSC.HOST SBOX-HOST-RUN-SLICE
    DUP SBOX-VM-RUN-INVALID = IF
        DESK-SBOX-S-HOST
    ELSE
        DESK-SBOX-S-OK
    THEN
    _DSC-DROP3>RUN-STATUS ;

: DESK-SBOX-RUN-STATE@
  ( generation component -- run-state status )
    2DUP _DSC-HANDLE-STATUS
    DUP IF
        >R 2DROP SBOX-VM-RUN-INVALID R> EXIT
    THEN
    DROP
    DUP _DSC.HOST SBOX-HOST-RUN-STATE@
    DUP SBOX-VM-RUN-INVALID = IF
        DROP 2DROP
        SBOX-VM-RUN-INVALID DESK-SBOX-S-HOST
    ELSE
        >R 2DROP R> DESK-SBOX-S-OK
    THEN ;

: DESK-SBOX-CONTEXT-IDENTITY@
  ( generation component -- id child-generation epoch status )
    2DUP _DSC-HANDLE-STATUS
    DUP IF
        >R 2DROP 0 0 0 R> EXIT
    THEN
    DROP
    DUP _DSC.HOST SBOX-HOST-CONTEXT-IDENTITY@
    DUP IF
        >R 2DROP 2DROP DROP 0 0 0
        R> DROP DESK-SBOX-S-HOST EXIT
    THEN
    DROP
    >R >R >R
    2DROP
    R> R> R> DESK-SBOX-S-OK ;

: DESK-SBOX-CANCEL  ( generation component -- status )
    2DUP _DSC-HANDLE-STATUS
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    SBOX-VM-CANCEL-CALLER 1 PICK _DSC.HOST SBOX-HOST-CANCEL
    SBOX-HOST-S-OK =
    >R 2DROP R>
    IF DESK-SBOX-S-OK ELSE DESK-SBOX-S-HOST THEN ;

\ =====================================================================
\  Detached caller-owned result
\ =====================================================================

 0 CONSTANT _DSR-MAGIC-OFF
 8 CONSTANT _DSR-SELF
16 CONSTANT _DSR-GENERATION
24 CONSTANT _DSR-RUN-STATE
32 CONSTANT _DSR-PAYLOAD
40 CONSTANT _DSR-PAYLOAD-U
48 CONSTANT _DSR-PAYLOAD-CAP
56 CONSTANT _DSR-RESERVED
64 CONSTANT DESK-SBOX-RESULT-SIZE

: _DSR.MAGIC        ( result -- address ) _DSR-MAGIC-OFF + ;
: _DSR.SELF         ( result -- address ) _DSR-SELF + ;
: _DSR.GENERATION   ( result -- address ) _DSR-GENERATION + ;
: _DSR.RUN-STATE    ( result -- address ) _DSR-RUN-STATE + ;
: _DSR.PAYLOAD      ( result -- address ) _DSR-PAYLOAD + ;
: _DSR.PAYLOAD-U    ( result -- address ) _DSR-PAYLOAD-U + ;
: _DSR.PAYLOAD-CAP  ( result -- address ) _DSR-PAYLOAD-CAP + ;
: _DSR.RESERVED     ( result -- address ) _DSR-RESERVED + ;

: _DSR-FIXED?  ( result -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DESK-SBOX-RESULT-SIZE _DSC-SPAN? ;

: _DSC-TERMINAL?  ( run-state -- flag )
    DUP SBOX-VM-RUN-COMPLETE >=
    SWAP SBOX-VM-RUN-CANCELLED <= AND ;

: DESK-SBOX-RESULT-VALID?  ( result -- flag )
    DUP _DSR-FIXED? 0= IF DROP 0 EXIT THEN
    DUP _DSR.MAGIC @ _DSR-MAGIC <> IF DROP 0 EXIT THEN
    DUP _DSR.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _DSR.GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    DUP _DSR.RUN-STATE @ _DSC-TERMINAL? 0= IF DROP 0 EXIT THEN
    DUP _DSR.PAYLOAD @ DUP 0= IF 2DROP 0 EXIT THEN
    DUP SBOX-VM-RESULT-VALID? 0= IF 2DROP 0 EXIT THEN
    SBOX-VM-RESULT-TOTAL@
    OVER _DSR.PAYLOAD-U @ =
    OVER _DSR.PAYLOAD-U @ 2 PICK _DSR.PAYLOAD-CAP @ = AND
    SWAP _DSR.RESERVED @ 0= AND ;

: DESK-SBOX-RESULT-GENERATION@  ( result -- generation|0 )
    DUP DESK-SBOX-RESULT-VALID?
    IF _DSR.GENERATION @ ELSE DROP 0 THEN ;

: DESK-SBOX-RESULT-RUN-STATE@  ( result -- run-state )
    DUP DESK-SBOX-RESULT-VALID?
    IF _DSR.RUN-STATE @ ELSE DROP SBOX-VM-RUN-INVALID THEN ;

: DESK-SBOX-RESULT-PAYLOAD@
  ( result -- payload payload-u flag )
    DUP DESK-SBOX-RESULT-VALID? 0= IF
        DROP 0 0 0 EXIT
    THEN
    DUP _DSR.PAYLOAD @
    SWAP _DSR.PAYLOAD-U @
    -1 ;

: _DSC-SCRUB-FREE  ( address length -- )
    OVER 0= IF 2DROP EXIT THEN
    DUP 0> IF 2DUP 0 FILL THEN
    DROP FREE ;

: DESK-SBOX-RESULT-RELEASE  ( result -- status )
    DUP _DSR-FIXED? 0= IF
        DROP DESK-SBOX-S-INVALID EXIT
    THEN
    DUP DESK-SBOX-RESULT-SIZE _DSC-ZERO? IF
        DROP DESK-SBOX-S-OK EXIT
    THEN
    DUP DESK-SBOX-RESULT-VALID? 0= IF
        DROP DESK-SBOX-S-INVALID EXIT
    THEN
    >R
    R@ _DSR.PAYLOAD @ R@ _DSR.PAYLOAD-CAP @
        SBOX-VM-RESULT-RELEASE DROP
    R@ _DSR.PAYLOAD @ R@ _DSR.PAYLOAD-CAP @
        _DSC-SCRUB-FREE
    R@ DESK-SBOX-RESULT-SIZE 0 FILL
    R> DROP
    DESK-SBOX-S-OK ;

: _DSC-TAKE-BOUNDARY
  ( result generation component -- same status )
    2 PICK _DSR-FIXED? 0= IF DESK-SBOX-S-INVALID EXIT THEN
    2 PICK DESK-SBOX-RESULT-SIZE _DSC-ZERO? 0= IF
        DESK-SBOX-S-STATE EXIT
    THEN
    1 PICK 1 PICK _DSC-HANDLE-STATUS
    DUP IF EXIT THEN DROP
    2 PICK DESK-SBOX-RESULT-SIZE 2 PICK
        _DSC-EXTERNAL-SPAN? 0= IF
        DESK-SBOX-S-ALIAS EXIT
    THEN
    2 PICK DESK-SBOX-RESULT-SIZE 2 PICK _DSC.HOST
        SBOX-HOST-SPAN-DISJOINT? 0= IF
        DESK-SBOX-S-ALIAS EXIT
    THEN
    DUP _DSC.HOST SBOX-HOST-RUN-STATE@
        _DSC-TERMINAL? 0= IF
        DESK-SBOX-S-STATE EXIT
    THEN
    DESK-SBOX-S-OK ;

: _DSC-ALLOCATE  ( bytes -- address status )
    DUP 0> 0= IF DROP 0 DESK-SBOX-S-RESULT EXIT THEN
    ALLOCATE
    DUP IF
        2DROP 0 DESK-SBOX-S-NOMEM EXIT
    THEN
    DROP
    DUP 0= IF
        DROP 0 DESK-SBOX-S-NOMEM
    ELSE
        DESK-SBOX-S-OK
    THEN ;

: _DSC-LIVE-CLEAR  ( component -- )
    0 OVER _DSC.LIVE-GENERATION !
    0 OVER _DSC.PLAN !
    0 OVER _DSC.PROFILE !
    0 OVER _DSC.ENTRY !
    0 OVER _DSC.REVISION !
    DUP _DSC.RID RID-CLEAR
    _DSC.HOST SBOX-HOST-INVOCATION-SIZE 0 FILL ;

: _DSC-DROP6>STATUS  ( x1 x2 x3 x4 x5 x6 status -- status )
    >R 2DROP 2DROP 2DROP R> ;

: DESK-SBOX-RESULT-TAKE
  ( result generation component -- status )
    _DSC-TAKE-BOUNDARY
    DUP IF
        >R 2DROP DROP R> EXIT
    THEN
    DROP

    DUP _DSC.HOST SBOX-HOST-RESULT-MEASURE
    DUP IF
        2DROP 2DROP DROP DESK-SBOX-S-HOST EXIT
    THEN
    DROP
    1 PICK _DSC.HOST SBOX-HOST-RUN-STATE@
    1 PICK _DSC-ALLOCATE
    DUP IF
        >R 2DROP 2DROP 2DROP R> EXIT
    THEN
    DROP

    DUP
    3 PICK
    5 PICK _DSC.HOST
    SBOX-HOST-FINISH
    DUP IF
        DROP
        DUP 3 PICK _DSC-SCRUB-FREE
        2DROP 2DROP 2DROP
        DESK-SBOX-S-HOST EXIT
    THEN
    DROP

    3 PICK _DSC-LIVE-CLEAR
    5 PICK >R
    R@ DESK-SBOX-RESULT-SIZE 0 FILL
    R@ R@ _DSR.SELF !
    4 PICK R@ _DSR.GENERATION !
    1 PICK R@ _DSR.RUN-STATE !
    DUP R@ _DSR.PAYLOAD !
    2 PICK R@ _DSR.PAYLOAD-U !
    2 PICK R@ _DSR.PAYLOAD-CAP !
    _DSR-MAGIC R@ _DSR.MAGIC !
    R@ DESK-SBOX-RESULT-VALID? 0= IF
        DUP 3 PICK SBOX-VM-RESULT-RELEASE DROP
        DUP 3 PICK _DSC-SCRUB-FREE
        R@ DESK-SBOX-RESULT-SIZE 0 FILL
        R> DROP
        DESK-SBOX-S-RESULT _DSC-DROP6>STATUS EXIT
    THEN
    R> DROP
    DESK-SBOX-S-OK _DSC-DROP6>STATUS ;

\ =====================================================================
\  Close, drain, and deterministic release
\ =====================================================================

: DESK-SBOX-CLOSE  ( component -- status )
    DUP DESK-SBOX-COMPONENT-VALID? 0= IF
        DROP DESK-SBOX-S-INVALID EXIT
    THEN
    DUP _DSC.STATE @ DESK-SBOX-COMPONENT-STATE-DRAINED = IF
        DROP DESK-SBOX-S-OK EXIT
    THEN
    \ Publish the permanent admission barrier before touching the host.
    DESK-SBOX-COMPONENT-STATE-CLOSING
        OVER _DSC.STATE !
    DUP _DSC-LIVE? 0= IF
        DROP DESK-SBOX-S-OK EXIT
    THEN
    DUP _DSC.HOST SBOX-HOST-RUN-STATE@
    DUP SBOX-VM-RUN-RUNNABLE = IF
        DROP
        SBOX-VM-CANCEL-HOST-SHUTDOWN
        SWAP _DSC.HOST SBOX-HOST-CANCEL
        SBOX-HOST-S-OK =
        IF DESK-SBOX-S-OK ELSE DESK-SBOX-S-HOST THEN
        EXIT
    THEN
    SBOX-VM-RUN-INVALID = IF
        DROP DESK-SBOX-S-HOST
    ELSE
        DROP DESK-SBOX-S-OK
    THEN ;

: _DSC-DRAIN-CLEAR  ( component -- )
    DUP _DSC.OWNER
    DESK-SBOX-COMPONENT-SIZE _DSC-OWNER -
    0 FILL
    DESK-SBOX-COMPONENT-STATE-DRAINED SWAP _DSC.STATE ! ;

: DESK-SBOX-DRAIN  ( component -- status )
    DUP DESK-SBOX-COMPONENT-VALID? 0= IF
        DROP DESK-SBOX-S-INVALID EXIT
    THEN
    DUP _DSC.STATE @ DESK-SBOX-COMPONENT-STATE-DRAINED = IF
        DROP DESK-SBOX-S-OK EXIT
    THEN
    DUP DESK-SBOX-CLOSE >R
    DUP _DSC-LIVE? IF
        DUP _DSC.HOST SBOX-HOST-RELEASE
        DUP IF
            DROP R> DROP
            DROP DESK-SBOX-S-HOST EXIT
        THEN
        DROP
        DUP _DSC-LIVE-CLEAR
    THEN
    _DSC-DRAIN-CLEAR
    R> ;

: DESK-SBOX-COMPONENT-STATE@  ( component -- state|0 )
    DUP DESK-SBOX-COMPONENT-VALID?
    IF _DSC.STATE @ ELSE DROP 0 THEN ;

: DESK-SBOX-COMPONENT-GENERATION@  ( component -- generation|0 )
    DUP DESK-SBOX-COMPONENT-VALID?
    IF _DSC.LIVE-GENERATION @ ELSE DROP 0 THEN ;

: DESK-SBOX-COMPONENT-LIVE?  ( component -- flag )
    DUP DESK-SBOX-COMPONENT-VALID?
    IF _DSC-LIVE? ELSE DROP 0 THEN ;

: DESK-SBOX-COMPONENT-RELEASE  ( component -- status )
    DUP _DSC-FIXED? 0= IF
        DROP DESK-SBOX-S-INVALID EXIT
    THEN
    DUP DESK-SBOX-COMPONENT-SIZE _DSC-ZERO? IF
        DROP DESK-SBOX-S-OK EXIT
    THEN
    DUP DESK-SBOX-COMPONENT-VALID? 0= IF
        DROP DESK-SBOX-S-INVALID EXIT
    THEN
    DUP DESK-SBOX-DRAIN
    OVER _DSC.STATE @ DESK-SBOX-COMPONENT-STATE-DRAINED = IF
        OVER DESK-SBOX-COMPONENT-SIZE 0 FILL
    THEN
    NIP ;
