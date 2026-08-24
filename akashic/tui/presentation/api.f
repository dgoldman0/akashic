\ =====================================================================
\  presentation/api.f - Backend-neutral retained-presentation service ABI
\ =====================================================================
\  This module is the application and host-facing seam for one optional
\  retained-presentation broker.  It owns no broker, scope, scene, transport,
\  or staging storage.  A composition supplies caller-owned broker and scope
\  records whose first bytes are the headers published here, and a complete
\  function table implemented by its selected backend.
\
\  A discovered broker grants no scene authority.  PRES-SCOPE-ACQUIRE is the
\  only operation that turns a live caller instance into a borrowed opaque
\  scope.  All child scene operations take only that scope; this interface
\  contains no terminal identity, sibling selector, or raw protocol surface.
\ =====================================================================

PROVIDED akashic-tui-pres-api

REQUIRE ../../interop/service-endpoint.f
REQUIRE ../../utils/memory-span.f

\ =====================================================================
\  Stable service identity and ordinary status values
\ =====================================================================

0 CONSTANT PRES-S-OK
1 CONSTANT PRES-S-WOULD-BLOCK
2 CONSTANT PRES-S-UNAVAILABLE
3 CONSTANT PRES-S-CAPACITY
4 CONSTANT PRES-S-STALE
5 CONSTANT PRES-S-INVALID
6 CONSTANT PRES-S-SESSION-LOST
7 CONSTANT PRES-S-SOURCE

: PRES-STATUS-VALID?  ( status -- flag )
    DUP PRES-S-OK >= SWAP PRES-S-SOURCE <= AND ;

: PRES-SERVICE-ID  ( -- id-a id-u )
    S" org.akashic.tui.presentation.v1" ;

: PRES-BROKER-DISCOVER  ( caller-instance -- broker | 0 )
    PRES-SERVICE-ID ROT CINST-SERVICE ;

\ =====================================================================
\  Backend function table
\ =====================================================================
\  PRES-API-INIT publishes the fixed header and clears every callback.  A
\  backend fills all callback fields before binding a broker.  The table must
\  then remain immutable until every broker and scope that names it is gone.
\
\  Callback stack effects are exactly those of their public wrappers below.

1 CONSTANT PRES-API-ABI-VERSION

  0 CONSTANT _PRES-API-O-MAGIC
  8 CONSTANT _PRES-API-O-ABI
 16 CONSTANT _PRES-API-O-BYTES
 24 CONSTANT _PRES-API-O-RESERVED
 32 CONSTANT _PRES-API-O-SERVICE-INIT-XT
 40 CONSTANT _PRES-API-O-SERVICE-FINI-XT
 48 CONSTANT _PRES-API-O-SERVICE-STATUS-XT
 56 CONSTANT _PRES-API-O-SERVICE-STEP-XT
 64 CONSTANT _PRES-API-O-SCOPE-ACQUIRE-XT
 72 CONSTANT _PRES-API-O-SCOPE-STATUS-XT
 80 CONSTANT _PRES-API-O-BATCH-BEGIN-XT
 88 CONSTANT _PRES-API-O-ITEM-DEFINE-XT
 96 CONSTANT _PRES-API-O-RESOURCE-DEFINE-XT
104 CONSTANT _PRES-API-O-SERIES-DEFINE-XT
112 CONSTANT _PRES-API-O-SCALAR-SET-XT
120 CONSTANT _PRES-API-O-SERIES-SET-XT
128 CONSTANT _PRES-API-O-VISIBILITY-SET-XT
136 CONSTANT _PRES-API-O-DROP-XT
144 CONSTANT _PRES-API-O-BATCH-COMMIT-XT
152 CONSTANT _PRES-API-O-BATCH-ABORT-XT
160 CONSTANT _PRES-API-O-HOST-BOUNDS-XT
168 CONSTANT _PRES-API-O-HOST-RETIRE-XT
176 CONSTANT PRES-API-SIZE

18 CONSTANT _PRES-API-CALLBACK-COUNT

HEX
5052455341504931 CONSTANT _PRES-API-MAGIC       \ "PRESAPI1"
5052455342523031 CONSTANT _PRES-BROKER-MAGIC    \ "PRESBR01"
5052455353433031 CONSTANT _PRES-SCOPE-MAGIC     \ "PRESSC01"
DECIMAL

: _PRES-API.MAGIC       ( api -- field ) _PRES-API-O-MAGIC + ;
: _PRES-API.ABI         ( api -- field ) _PRES-API-O-ABI + ;
: _PRES-API.BYTES       ( api -- field ) _PRES-API-O-BYTES + ;
: _PRES-API.RESERVED    ( api -- field ) _PRES-API-O-RESERVED + ;

: PRES-API.SERVICE-INIT-XT
    ( api -- field ) _PRES-API-O-SERVICE-INIT-XT + ;
: PRES-API.SERVICE-FINI-XT
    ( api -- field ) _PRES-API-O-SERVICE-FINI-XT + ;
: PRES-API.SERVICE-STATUS-XT
    ( api -- field ) _PRES-API-O-SERVICE-STATUS-XT + ;
: PRES-API.SERVICE-STEP-XT
    ( api -- field ) _PRES-API-O-SERVICE-STEP-XT + ;
: PRES-API.SCOPE-ACQUIRE-XT
    ( api -- field ) _PRES-API-O-SCOPE-ACQUIRE-XT + ;
: PRES-API.SCOPE-STATUS-XT
    ( api -- field ) _PRES-API-O-SCOPE-STATUS-XT + ;
: PRES-API.BATCH-BEGIN-XT
    ( api -- field ) _PRES-API-O-BATCH-BEGIN-XT + ;
: PRES-API.ITEM-DEFINE-XT
    ( api -- field ) _PRES-API-O-ITEM-DEFINE-XT + ;
: PRES-API.RESOURCE-DEFINE-XT
    ( api -- field ) _PRES-API-O-RESOURCE-DEFINE-XT + ;
: PRES-API.SERIES-DEFINE-XT
    ( api -- field ) _PRES-API-O-SERIES-DEFINE-XT + ;
: PRES-API.SCALAR-SET-XT
    ( api -- field ) _PRES-API-O-SCALAR-SET-XT + ;
: PRES-API.SERIES-SET-XT
    ( api -- field ) _PRES-API-O-SERIES-SET-XT + ;
: PRES-API.VISIBILITY-SET-XT
    ( api -- field ) _PRES-API-O-VISIBILITY-SET-XT + ;
: PRES-API.DROP-XT
    ( api -- field ) _PRES-API-O-DROP-XT + ;
: PRES-API.BATCH-COMMIT-XT
    ( api -- field ) _PRES-API-O-BATCH-COMMIT-XT + ;
: PRES-API.BATCH-ABORT-XT
    ( api -- field ) _PRES-API-O-BATCH-ABORT-XT + ;
: PRES-API.HOST-BOUNDS-XT
    ( api -- field ) _PRES-API-O-HOST-BOUNDS-XT + ;
: PRES-API.HOST-RETIRE-XT
    ( api -- field ) _PRES-API-O-HOST-RETIRE-XT + ;

: PRES-API-INIT  ( api -- )
    DUP PRES-API-SIZE 0 FILL
    _PRES-API-MAGIC OVER _PRES-API.MAGIC !
    PRES-API-ABI-VERSION OVER _PRES-API.ABI !
    PRES-API-SIZE SWAP _PRES-API.BYTES ! ;

: _PRES-CELL-ALIGNED?  ( address -- flag )
    7 AND 0= ;

: _PRES-API-CALLBACKS-VALID?  ( api -- flag )
    PRES-API.SERVICE-INIT-XT
    _PRES-API-CALLBACK-COUNT 0 DO
        DUP I CELLS + @ 0= IF
            DROP FALSE UNLOOP EXIT
        THEN
    LOOP
    DROP TRUE ;

: PRES-API-VALID?  ( api -- flag )
    DUP 0= IF DROP FALSE EXIT THEN
    DUP _PRES-CELL-ALIGNED? 0= IF DROP FALSE EXIT THEN
    DUP PRES-API-SIZE MSPAN-NONWRAPPING? 0= IF DROP FALSE EXIT THEN
    DUP _PRES-API.MAGIC @ _PRES-API-MAGIC <> IF DROP FALSE EXIT THEN
    DUP _PRES-API.ABI @ PRES-API-ABI-VERSION <> IF DROP FALSE EXIT THEN
    DUP _PRES-API.BYTES @ PRES-API-SIZE <> IF DROP FALSE EXIT THEN
    DUP _PRES-API.RESERVED @ 0<> IF DROP FALSE EXIT THEN
    _PRES-API-CALLBACKS-VALID? ;

\ =====================================================================
\  Caller-owned broker and opaque-scope headers
\ =====================================================================
\  These fixed prefixes contain only the dispatch-table identity.  Backend
\  records extend them with private state.  There is intentionally no public
\  accessor for any scope field.

 0 CONSTANT _PRES-H-O-API
 8 CONSTANT _PRES-H-O-MAGIC
16 CONSTANT PRES-BROKER-HEADER-SIZE
16 CONSTANT PRES-SCOPE-HEADER-SIZE

: _PRES-H.API    ( handle -- field ) _PRES-H-O-API + ;
: _PRES-H.MAGIC  ( handle -- field ) _PRES-H-O-MAGIC + ;

: _PRES-H-API-DISJOINT?  ( header-bytes handle -- flag )
    >R
    R@ SWAP R@ _PRES-H.API @ PRES-API-SIZE MSPAN-OVERLAP? 0=
    R> DROP ;

: _PRES-BROKER-VALID?  ( broker -- flag )
    DUP 0= IF DROP FALSE EXIT THEN
    DUP _PRES-CELL-ALIGNED? 0= IF DROP FALSE EXIT THEN
    DUP PRES-BROKER-HEADER-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP FALSE EXIT
    THEN
    DUP _PRES-H.MAGIC @ _PRES-BROKER-MAGIC <> IF DROP FALSE EXIT THEN
    DUP _PRES-H.API @ PRES-API-VALID? 0= IF DROP FALSE EXIT THEN
    PRES-BROKER-HEADER-SIZE SWAP _PRES-H-API-DISJOINT? ;

: _PRES-SCOPE-VALID?  ( scope -- flag )
    DUP 0= IF DROP FALSE EXIT THEN
    DUP _PRES-CELL-ALIGNED? 0= IF DROP FALSE EXIT THEN
    DUP PRES-SCOPE-HEADER-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP FALSE EXIT
    THEN
    DUP _PRES-H.MAGIC @ _PRES-SCOPE-MAGIC <> IF DROP FALSE EXIT THEN
    DUP _PRES-H.API @ PRES-API-VALID? 0= IF DROP FALSE EXIT THEN
    PRES-SCOPE-HEADER-SIZE SWAP _PRES-H-API-DISJOINT? ;

\ Backend composition helpers.  These are deliberately not child API words;
\ a backend uses them while constructing its caller-owned records, before a
\ broker is published or an acquired scope is returned.
: _PRES-BROKER-BIND  ( api broker -- status )
    DUP 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-CELL-ALIGNED? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP PRES-BROKER-HEADER-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP PRES-S-INVALID EXIT
    THEN
    OVER PRES-API-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    OVER PRES-API-SIZE 2 PICK PRES-BROKER-HEADER-SIZE
        MSPAN-OVERLAP? IF 2DROP PRES-S-INVALID EXIT THEN
    OVER OVER _PRES-H.API !
    _PRES-BROKER-MAGIC SWAP _PRES-H.MAGIC !
    DROP PRES-S-OK ;

: _PRES-SCOPE-BIND  ( broker scope -- status )
    DUP 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-CELL-ALIGNED? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP PRES-SCOPE-HEADER-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP PRES-S-INVALID EXIT
    THEN
    OVER _PRES-BROKER-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    OVER PRES-BROKER-HEADER-SIZE 2 PICK PRES-SCOPE-HEADER-SIZE
        MSPAN-OVERLAP? IF 2DROP PRES-S-INVALID EXIT THEN
    OVER _PRES-H.API @ PRES-API-SIZE
        2 PICK PRES-SCOPE-HEADER-SIZE MSPAN-OVERLAP? IF
        2DROP PRES-S-INVALID EXIT
    THEN
    OVER _PRES-H.API @ OVER _PRES-H.API !
    _PRES-SCOPE-MAGIC SWAP _PRES-H.MAGIC !
    DROP PRES-S-OK ;

: _PRES-NORMALIZE-STATUS  ( status -- status )
    DUP PRES-STATUS-VALID? 0= IF DROP PRES-S-INVALID THEN ;

\ =====================================================================
\  Broker lifecycle and caller-aware acquisition wrappers
\ =====================================================================

: PRES-SERVICE-INIT  ( config broker -- status )
    DUP _PRES-BROKER-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.SERVICE-INIT-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-SERVICE-FINI  ( broker -- status )
    DUP _PRES-BROKER-VALID? 0= IF DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.SERVICE-FINI-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-SERVICE-STATUS@  ( broker -- status )
    DUP _PRES-BROKER-VALID? 0= IF DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.SERVICE-STATUS-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-SERVICE-STEP  ( work-budget broker -- status more-work? )
    DUP _PRES-BROKER-VALID? 0= IF
        2DROP PRES-S-INVALID FALSE EXIT
    THEN
    DUP _PRES-H.API @ PRES-API.SERVICE-STEP-XT @ EXECUTE
    DUP 0<> OVER -1 <> AND IF
        2DROP PRES-S-INVALID FALSE EXIT
    THEN
    SWAP _PRES-NORMALIZE-STATUS SWAP ;

: PRES-SCOPE-ACQUIRE  ( caller-instance broker -- scope status )
    DUP _PRES-BROKER-VALID? 0= IF
        2DROP 0 PRES-S-INVALID EXIT
    THEN
    DUP >R
    DUP _PRES-H.API @ >R
    R@ PRES-API.SCOPE-ACQUIRE-XT @ EXECUTE
    DUP PRES-STATUS-VALID? 0= IF
        2DROP R> DROP R> DROP 0 PRES-S-INVALID EXIT
    THEN
    DUP PRES-S-OK <> IF
        SWAP DROP R> DROP R> DROP 0 SWAP EXIT
    THEN
    DROP
    DUP _PRES-SCOPE-VALID? 0= IF
        DROP R> DROP R> DROP 0 PRES-S-INVALID EXIT
    THEN
    DUP _PRES-H.API @ R@ <> IF
        DROP R> DROP R> DROP 0 PRES-S-INVALID EXIT
    THEN
    R> DROP
    DUP PRES-SCOPE-HEADER-SIZE R@ PRES-BROKER-HEADER-SIZE
        MSPAN-OVERLAP? IF
        DROP R> DROP 0 PRES-S-INVALID EXIT
    THEN
    R> DROP PRES-S-OK ;

: PRES-SCOPE-STATUS@  ( scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.SCOPE-STATUS-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

\ =====================================================================
\  Opaque-scope scene wrappers
\ =====================================================================

: PRES-BATCH-BEGIN  ( batch-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.BATCH-BEGIN-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-ITEM-DEFINE  ( item-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.ITEM-DEFINE-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-RESOURCE-DEFINE  ( resource-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.RESOURCE-DEFINE-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-SERIES-DEFINE  ( series-def-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.SERIES-DEFINE-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-SCALAR-SET  ( scalar-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.SCALAR-SET-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-SERIES-SET  ( series-source-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.SERIES-SET-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-VISIBILITY-SET  ( visibility-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.VISIBILITY-SET-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-DROP  ( drop-desc scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.DROP-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-BATCH-COMMIT  ( scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.BATCH-COMMIT-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-BATCH-ABORT  ( scope -- status )
    DUP _PRES-SCOPE-VALID? 0= IF DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.BATCH-ABORT-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

\ =====================================================================
\  Desk-owner wrappers
\ =====================================================================

: PRES-HOST-BOUNDS!
    ( row col height width visible caller-instance broker -- status )
    DUP _PRES-BROKER-VALID? 0= IF
        2DROP 2DROP 2DROP DROP PRES-S-INVALID EXIT
    THEN
    DUP _PRES-H.API @ PRES-API.HOST-BOUNDS-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;

: PRES-HOST-RETIRE  ( caller-instance broker -- status )
    DUP _PRES-BROKER-VALID? 0= IF 2DROP PRES-S-INVALID EXIT THEN
    DUP _PRES-H.API @ PRES-API.HOST-RETIRE-XT @ EXECUTE
    _PRES-NORMALIZE-STATUS ;
