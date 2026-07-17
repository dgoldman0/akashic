\ =====================================================================
\  shared-document.f - Daybook activation-local text-document owner
\ =====================================================================
\  This is the deliberately bounded concrete Daybook resource.  One live
\  owner instance controls the semantic RID and the canonical VFS backing
\  path /daybook.md.  Lenses may come and go independently; they attach to
\  the owner through RREG/LBIND and issue ordinary capability requests.
\
\  Capabilities:
\    resource.snapshot  ( null -- string )
\    resource.replace   ( string -- bool )
\
\  Replace requires a positive CBR.EXPECT-REV.  The owner rechecks it while
\  holding its commit guard, immediately before VREPL publication.  A stale
\  request returns CBUS-S-STALE-REVISION without touching the VFS.  The
\  handler never calls CINST-TOUCH: request-bus.f advances the instance
\  revision exactly once after a successful mutating/persisting handler.
\
\  This module is trusted-native, activation-local machinery.  It does not
\  claim sandboxing, durable resource graphs, facets, or Practice storage.
\ =====================================================================

PROVIDED akashic-interop-shared-document

REQUIRE ../interop/request-bus.f
REQUIRE ../interop/schema-common.f
REQUIRE ../runtime/resource-registry.f
REQUIRE ../utils/fs/vfs-replace.f
REQUIRE ../concurrency/guard.f
REQUIRE ../text/utf8.f

\ =====================================================================
\  Public status and bounds
\ =====================================================================

0 CONSTANT SDOC-S-OK
1 CONSTANT SDOC-S-INVALID
2 CONSTANT SDOC-S-BUSY
3 CONSTANT SDOC-S-NOMEM
4 CONSTANT SDOC-S-RECOVERY
5 CONSTANT SDOC-S-SOURCE
6 CONSTANT SDOC-S-REGISTRY
7 CONSTANT SDOC-S-RESOURCE
8 CONSTANT SDOC-S-IO
9 CONSTANT SDOC-S-READONLY

32768 CONSTANT SDOC-MAX-BYTES

1 CONSTANT _SDOC-F-CONFIGURED
2 CONSTANT _SDOC-F-IN-REGISTRY
4 CONSTANT _SDOC-F-PUBLISHED
8 CONSTANT _SDOC-F-BLOCKED

0x434F4453 CONSTANT _SDOC-STATE-MAGIC       \ "SDOC"

\ =====================================================================
\  Owner state
\ =====================================================================
\  VFS, Context, and registries are borrowed for the activation lifetime.
\  RID and path are copied.  VREPL and the bounded snapshot buffer are
\  owner-private; no lens receives either address.

   0 CONSTANT _SDS-MAGIC
   8 CONSTANT _SDS-FLAGS
  16 CONSTANT _SDS-VFS
  24 CONSTANT _SDS-PATH-U
  32 CONSTANT _SDS-RID                    \ RID-SIZE bytes
  64 CONSTANT _SDS-CONTEXT
  72 CONSTANT _SDS-RREG
  80 CONSTANT _SDS-CREG
  88 CONSTANT _SDS-PATH                   \ VREPL path capacity
 344 CONSTANT _SDS-REPLACE                \ VREPL-SIZE bytes
1496 CONSTANT _SDS-IO-U
1504 CONSTANT _SDS-IO
1504 SDOC-MAX-BYTES + CONSTANT SDOC-STATE-SIZE

: _SDS.MAGIC    ( state -- a ) _SDS-MAGIC + ;
: _SDS.FLAGS    ( state -- a ) _SDS-FLAGS + ;
: _SDS.VFS      ( state -- a ) _SDS-VFS + ;
: _SDS.PATH-U   ( state -- a ) _SDS-PATH-U + ;
: _SDS.RID      ( state -- id ) _SDS-RID + ;
: _SDS.CONTEXT  ( state -- a ) _SDS-CONTEXT + ;
: _SDS.RREG     ( state -- a ) _SDS-RREG + ;
: _SDS.CREG     ( state -- a ) _SDS-CREG + ;
: _SDS.PATH     ( state -- a ) _SDS-PATH + ;
: _SDS.REPLACE  ( state -- replacement ) _SDS-REPLACE + ;
: _SDS.IO-U     ( state -- a ) _SDS-IO-U + ;
: _SDS.IO       ( state -- a ) _SDS-IO + ;

: _SDS-PATH$  ( state -- a u )
    DUP _SDS.PATH SWAP _SDS.PATH-U @ ;

\ =====================================================================
\  Static generic capability/component descriptors
\ =====================================================================

CREATE _SDOC-NULL-SCHEMA   CS-SIZE ALLOT
CREATE _SDOC-TEXT-SCHEMA   CS-SIZE ALLOT
CREATE _SDOC-BOOL-SCHEMA   CS-SIZE ALLOT

CREATE SDOC-CAPS 2 CAP-DESC * ALLOT
: SDOC-CAP-SNAPSHOT  ( -- cap ) SDOC-CAPS ;
: SDOC-CAP-REPLACE   ( -- cap ) SDOC-CAPS CAP-DESC + ;

CREATE SDOC-COMP-DESC COMP-DESC ALLOT

GUARD _SDOC-GUARD
VARIABLE _SDOC-LIVE
0 _SDOC-LIVE !

: _SDOC-STATE-FINI  ( state -- )
    SDOC-STATE-SIZE 0 FILL ;

: _SDOC-STATE-VALID?  ( instance -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CINST-DESC SDOC-COMP-DESC <> IF DROP 0 EXIT THEN
    CINST-STATE DUP 0= IF DROP 0 EXIT THEN
    DUP _SDS.MAGIC @ _SDOC-STATE-MAGIC =
    OVER _SDS.FLAGS @ _SDOC-F-CONFIGURED AND 0<> AND
    OVER _SDS.VFS @ 0<> AND
    OVER _SDS.RID RID-PRESENT? AND
    OVER _SDS-PATH$ S" /daybook.md" STR-STR= AND
    SWAP _SDS.REPLACE VREPL-CONFIGURED? AND ;

\ =====================================================================
\  Exception-safe bounded snapshot read
\ =====================================================================

VARIABLE _SDR-STATE
VARIABLE _SDR-OLD-VFS
VARIABLE _SDR-FD
VARIABLE _SDR-CLEAN-FD
VARIABLE _SDR-HAVE-OLD
VARIABLE _SDR-STATUS
VARIABLE _SDR-CLEAN-FAILED

: _SDOC-READ-CLOSE-CALL  ( -- )
    _SDR-CLEAN-FD @ VFS-CLOSE ;

: _SDOC-READ-RESTORE-CALL  ( -- )
    _SDR-OLD-VFS @ VFS-USE ;

: _SDOC-READ-CLEANUP  ( -- failed? )
    0 _SDR-CLEAN-FAILED !
    _SDR-FD @ ?DUP IF
        _SDR-CLEAN-FD ! 0 _SDR-FD !
        ['] _SDOC-READ-CLOSE-CALL CATCH IF
            -1 _SDR-CLEAN-FAILED !
        THEN
    THEN
    _SDR-HAVE-OLD @ IF
        0 _SDR-HAVE-OLD !
        ['] _SDOC-READ-RESTORE-CALL CATCH IF
            -1 _SDR-CLEAN-FAILED !
        THEN
    THEN
    _SDR-CLEAN-FAILED @ ;

: _SDOC-READ-BODY  ( -- status )
    _SDR-STATE @ _SDS-PATH$ VFS-OPEN DUP 0= IF
        DROP 0 _SDR-STATE @ _SDS.IO-U ! SDOC-S-OK EXIT
    THEN
    _SDR-FD !
    _SDR-FD @ VFS-SIZE DUP 0< IF
        DROP SDOC-S-IO EXIT
    THEN
    DUP SDOC-MAX-BYTES > IF
        DROP SDOC-S-SOURCE EXIT
    THEN
    DUP _SDR-STATE @ _SDS.IO-U !
    _SDR-STATE @ _SDS.IO SWAP _SDR-FD @ VFS-READ-EXACT
    IF SDOC-S-IO ELSE SDOC-S-OK THEN ;

: _SDOC-READ-OP  ( -- )
    VFS-CUR _SDR-OLD-VFS !
    -1 _SDR-HAVE-OLD !
    _SDR-STATE @ _SDS.VFS @ VFS-USE
    _SDOC-READ-BODY _SDR-STATUS ! ;

: _SDOC-READ-TRANSACTION  ( -- status )
    0 _SDR-FD ! 0 _SDR-HAVE-OLD !
    SDOC-S-IO _SDR-STATUS !
    ['] _SDOC-READ-OP CATCH IF SDOC-S-IO _SDR-STATUS ! THEN
    _SDOC-READ-CLEANUP IF SDOC-S-IO EXIT THEN
    _SDR-STATUS @ ;

: _SDOC-READ-TRANSACTION-CALL  ( -- status )
    ['] _SDOC-READ-TRANSACTION VFS-TRANSACTION ;

: _SDOC-READ  ( state -- status )
    _SDR-STATE !
    ['] _SDOC-READ-TRANSACTION-CALL CATCH ?DUP IF
        DROP SDOC-S-IO
    THEN ;

: _SDOC-CURRENT-TEXT-VALID?  ( state -- flag )
    DUP _SDS.IO-U @ DUP 0= IF 2DROP -1 EXIT THEN
    SWAP _SDS.IO SWAP UTF8-VALID? ;

: _SDOC-RECOVERY-OK?  ( vrepl-status -- flag )
    DUP VREPL-S-OK =
    OVER VREPL-S-ROLLED-BACK = OR
    SWAP VREPL-S-COMMITTED-CLEANUP = OR ;

: _SDOC-RECOVER  ( state -- status )
    _SDS.REPLACE VREPL-RECOVER
    _SDOC-RECOVERY-OK? IF SDOC-S-OK ELSE SDOC-S-RECOVERY THEN ;

: _SDOC-BLOCKED?  ( state -- flag )
    _SDS.FLAGS @ _SDOC-F-BLOCKED AND 0<> ;

\ =====================================================================
\  Capability handlers
\ =====================================================================

VARIABLE _SDH-REQUEST
VARIABLE _SDH-INSTANCE
VARIABLE _SDH-STATE
VARIABLE _SDH-STATUS

: _SDOC-REQUEST-EXACT?  ( -- flag )
    _SDH-REQUEST @ CBR.RESOURCE-ID RID-PRESENT?
    _SDH-REQUEST @ CBR.RESOURCE-ID
        _SDH-STATE @ _SDS.RID RID= AND ;

: _SDOC-EXPECTED-CURRENT?  ( -- flag )
    _SDH-REQUEST @ CBR.EXPECT-REV @ ?DUP IF
        _SDH-INSTANCE @ CINST.REVISION @ =
    ELSE
        -1
    THEN ;

: _SDOC-SNAPSHOT-HANDLER-LOCKED  ( request instance -- status )
    _SDH-INSTANCE ! _SDH-REQUEST !
    _SDH-INSTANCE @ _SDOC-STATE-VALID? 0= IF
        CBUS-S-INVALID EXIT
    THEN
    _SDH-INSTANCE @ CINST-STATE _SDH-STATE !
    _SDOC-REQUEST-EXACT? 0= IF CBUS-S-INVALID EXIT THEN
    _SDH-STATE @ _SDOC-BLOCKED? IF
        S" Document owner requires reactivation" SDOC-S-RECOVERY
            _SDH-REQUEST @ CBR-ERROR!
        CBUS-S-FAILED EXIT
    THEN
    _SDOC-EXPECTED-CURRENT? 0= IF
        CBUS-S-STALE-REVISION EXIT
    THEN
    _SDH-STATE @ _SDOC-RECOVER IF
        _SDH-STATE @ _SDS.FLAGS DUP @ _SDOC-F-BLOCKED OR SWAP !
        S" Document recovery failed" SDOC-S-RECOVERY
            _SDH-REQUEST @ CBR-ERROR!
        CBUS-S-FAILED EXIT
    THEN
    _SDH-STATE @ _SDOC-READ DUP IF
        S" Document snapshot failed" ROT _SDH-REQUEST @ CBR-ERROR!
        CBUS-S-FAILED EXIT
    THEN DROP
    _SDH-STATE @ _SDOC-CURRENT-TEXT-VALID? 0= IF
        S" Document source is not valid UTF-8" SDOC-S-SOURCE
            _SDH-REQUEST @ CBR-ERROR!
        CBUS-S-FAILED EXIT
    THEN
    _SDH-STATE @ DUP _SDS.IO SWAP _SDS.IO-U @
        _SDH-REQUEST @ CBR.RESULT CV-STRING! IF
        S" Could not allocate document snapshot" SDOC-S-NOMEM
            _SDH-REQUEST @ CBR-ERROR!
        CBUS-S-FAILED EXIT
    THEN
    CBUS-S-OK ;

: _SDOC-SNAPSHOT-HANDLER  ( request instance -- status )
    ['] _SDOC-SNAPSHOT-HANDLER-LOCKED _SDOC-GUARD WITH-GUARD ;

: _SDOC-REPLACE-HANDLER-LOCKED  ( request instance -- status )
    _SDH-INSTANCE ! _SDH-REQUEST !
    _SDH-INSTANCE @ _SDOC-STATE-VALID? 0= IF
        CBUS-S-INVALID EXIT
    THEN
    _SDH-INSTANCE @ CINST-STATE _SDH-STATE !
    _SDOC-REQUEST-EXACT? 0= IF CBUS-S-INVALID EXIT THEN
    _SDH-STATE @ _SDOC-BLOCKED? IF
        S" Document owner requires reactivation" SDOC-S-RECOVERY
            _SDH-REQUEST @ CBR-ERROR!
        CBUS-S-FAILED EXIT
    THEN
    _SDH-STATE @ _SDS.CONTEXT @ CTX-READONLY? IF
        S" Practice is read-only" SDOC-S-READONLY
            _SDH-REQUEST @ CBR-ERROR!
        CBUS-S-DENIED EXIT
    THEN
    _SDH-REQUEST @ CBR.EXPECT-REV @ 0> 0= IF
        CBUS-S-INVALID EXIT
    THEN
    _SDOC-EXPECTED-CURRENT? 0= IF
        CBUS-S-STALE-REVISION EXIT
    THEN
    _SDH-REQUEST @ CBR.ARGS DUP CV-TYPE@ CV-T-STRING <> IF
        DROP CBUS-S-INVALID EXIT
    THEN
    DUP CV-LEN@ DUP 0< OVER SDOC-MAX-BYTES > OR IF
        2DROP CBUS-S-INVALID EXIT
    THEN
    OVER CV-DATA@ OVER 0> SWAP 0= AND IF
        2DROP CBUS-S-INVALID EXIT
    THEN
    2DROP
    _SDH-REQUEST @ CBR.ARGS DUP CV-LEN@ IF
        DUP CV-DATA@ SWAP CV-LEN@ UTF8-VALID? 0= IF
            CBUS-S-INVALID EXIT
        THEN
    ELSE DROP THEN
    _SDH-REQUEST @ CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@
        _SDH-STATE @ _SDS.REPLACE VREPL-REPLACE DUP _SDH-STATUS !
    DUP VREPL-S-OK = SWAP VREPL-S-COMMITTED-CLEANUP = OR IF
        -1 _SDH-REQUEST @ CBR.RESULT CV-BOOL!
        CBUS-S-OK EXIT
    THEN
    _SDH-STATUS @ VREPL-S-UNCERTAIN =
    _SDH-STATUS @ VREPL-S-RECOVERY = OR
    _SDH-STATUS @ VREPL-S-MARKER-CORRUPT = OR IF
        _SDH-STATE @ _SDS.FLAGS DUP @ _SDOC-F-BLOCKED OR SWAP !
    THEN
    S" Document publication failed" _SDH-STATUS @
        _SDH-REQUEST @ CBR-ERROR!
    _SDH-STATUS @ VREPL-S-BUSY = IF
        CBUS-S-BUSY
    ELSE
        CBUS-S-FAILED
    THEN ;

: _SDOC-REPLACE-HANDLER  ( request instance -- status )
    ['] _SDOC-REPLACE-HANDLER-LOCKED _SDOC-GUARD WITH-GUARD ;

\ =====================================================================
\  Descriptor initialization
\ =====================================================================

: _SDOC-DESCRIPTORS-SETUP  ( -- )
    _SDOC-NULL-SCHEMA CSC-NULL!
    SDOC-MAX-BYTES _SDOC-TEXT-SCHEMA CSC-UTF8!
    _SDOC-BOOL-SCHEMA CSC-BOOL!

    SDOC-CAP-SNAPSHOT CAP-DESC-INIT
    CAP-K-RESOURCE SDOC-CAP-SNAPSHOT CAP.KIND !
    S" resource.snapshot"
        SDOC-CAP-SNAPSHOT CAP.ID-U ! SDOC-CAP-SNAPSHOT CAP.ID-A !
    S" Document snapshot"
        SDOC-CAP-SNAPSHOT CAP.TITLE-U ! SDOC-CAP-SNAPSHOT CAP.TITLE-A !
    S" Copy the exact current shared document text"
        SDOC-CAP-SNAPSHOT CAP.DESC-U ! SDOC-CAP-SNAPSHOT CAP.DESC-A !
    _SDOC-NULL-SCHEMA SDOC-CAP-SNAPSHOT CAP.IN-SCHEMA !
    _SDOC-TEXT-SCHEMA SDOC-CAP-SNAPSHOT CAP.OUT-SCHEMA !
    CAP-E-OBSERVE SDOC-CAP-SNAPSHOT CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
        SDOC-CAP-SNAPSHOT CAP.FLAGS !
    ['] _SDOC-SNAPSHOT-HANDLER SDOC-CAP-SNAPSHOT CAP.HANDLER-XT !

    SDOC-CAP-REPLACE CAP-DESC-INIT
    CAP-K-COMMAND SDOC-CAP-REPLACE CAP.KIND !
    S" resource.replace"
        SDOC-CAP-REPLACE CAP.ID-U ! SDOC-CAP-REPLACE CAP.ID-A !
    S" Replace document"
        SDOC-CAP-REPLACE CAP.TITLE-U ! SDOC-CAP-REPLACE CAP.TITLE-A !
    S" Replace the shared document at one exact expected revision"
        SDOC-CAP-REPLACE CAP.DESC-U ! SDOC-CAP-REPLACE CAP.DESC-A !
    _SDOC-TEXT-SCHEMA SDOC-CAP-REPLACE CAP.IN-SCHEMA !
    _SDOC-BOOL-SCHEMA SDOC-CAP-REPLACE CAP.OUT-SCHEMA !
    CAP-E-MUTATE CAP-E-PERSIST OR SDOC-CAP-REPLACE CAP.EFFECTS !
    CAP-F-NEEDS-TARGET SDOC-CAP-REPLACE CAP.FLAGS !
    ['] _SDOC-REPLACE-HANDLER SDOC-CAP-REPLACE CAP.HANDLER-XT !

    SDOC-COMP-DESC COMP-DESC-INIT
    S" org.akashic.shared-document-owner"
        SDOC-COMP-DESC COMP.ID-U ! SDOC-COMP-DESC COMP.ID-A !
    S" 1.0.0"
        SDOC-COMP-DESC COMP.VERSION-U ! SDOC-COMP-DESC COMP.VERSION-A !
    SDOC-STATE-SIZE SDOC-COMP-DESC COMP.STATE-SIZE !
    ['] _SDOC-STATE-FINI SDOC-COMP-DESC COMP.STATE-FINI-XT !
    SDOC-CAPS SDOC-COMP-DESC COMP.CAPS-A !
    2 SDOC-COMP-DESC COMP.CAPS-N ! ;

_SDOC-DESCRIPTORS-SETUP

\ =====================================================================
\  Activation-local lifecycle
\ =====================================================================

VARIABLE _SDA-VFS
VARIABLE _SDA-RID
VARIABLE _SDA-CONTEXT
VARIABLE _SDA-RREG
VARIABLE _SDA-CREG
VARIABLE _SDA-INSTANCE
VARIABLE _SDA-STATE
VARIABLE _SDA-STATUS

: _SDOC-ACTIVATE-RELEASE  ( -- )
    _SDA-INSTANCE @ ?DUP IF
        DUP CINST-STATE _SDA-STATE !
        _SDA-STATE @ _SDS.FLAGS @ _SDOC-F-IN-REGISTRY AND IF
            DUP _SDA-CREG @ CREG-INST- DROP
        THEN
        CINST-FREE
    THEN
    0 _SDA-INSTANCE ! ;

: _SDOC-ACTIVATE-LOCKED  ( vfs rid context rreg creg -- instance status )
    _SDA-CREG ! _SDA-RREG ! _SDA-CONTEXT ! _SDA-RID ! _SDA-VFS !
    _SDOC-LIVE @ IF 0 SDOC-S-BUSY EXIT THEN
    _SDA-VFS @ 0= _SDA-RID @ RID-PRESENT? 0= OR
    _SDA-CREG @ 0= OR IF 0 SDOC-S-INVALID EXIT THEN
    _SDA-CONTEXT @ CTX-VALID? 0= IF 0 SDOC-S-INVALID EXIT THEN
    _SDA-CONTEXT @ CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        0 SDOC-S-INVALID EXIT
    THEN
    _SDA-RREG @ RREG-VALID? 0= IF 0 SDOC-S-INVALID EXIT THEN
    _SDA-CONTEXT @ _SDA-RREG @ RREG-CONTEXT? 0= IF
        0 SDOC-S-INVALID EXIT
    THEN
    SDOC-COMP-DESC _SDA-CREG @ CREG-TYPE-ENSURE IF
        0 SDOC-S-REGISTRY EXIT
    THEN
    SDOC-COMP-DESC CINST-NEW _SDA-STATUS ! _SDA-INSTANCE !
    _SDA-STATUS @ IF 0 SDOC-S-NOMEM EXIT THEN
    _SDA-INSTANCE @ CINST-STATE DUP _SDA-STATE !
    SDOC-STATE-SIZE 0 FILL
    _SDOC-STATE-MAGIC _SDA-STATE @ _SDS.MAGIC !
    _SDA-VFS @ _SDA-STATE @ _SDS.VFS !
    _SDA-RID @ _SDA-STATE @ _SDS.RID RID-COPY
    _SDA-CONTEXT @ _SDA-STATE @ _SDS.CONTEXT !
    _SDA-RREG @ _SDA-STATE @ _SDS.RREG !
    _SDA-CREG @ _SDA-STATE @ _SDS.CREG !
    S" /daybook.md" DUP _SDA-STATE @ _SDS.PATH-U !
        _SDA-STATE @ _SDS.PATH SWAP CMOVE
    _SDA-VFS @ _SDA-STATE @ _SDS.REPLACE VREPL-INIT IF
        _SDOC-ACTIVATE-RELEASE 0 SDOC-S-INVALID EXIT
    THEN
    S" /daybook.md" _SDA-STATE @ _SDS.REPLACE VREPL-DERIVE-PATHS! IF
        _SDOC-ACTIVATE-RELEASE 0 SDOC-S-INVALID EXIT
    THEN
    _SDOC-F-CONFIGURED _SDA-STATE @ _SDS.FLAGS !
    _SDA-STATE @ _SDOC-RECOVER IF
        _SDOC-ACTIVATE-RELEASE 0 SDOC-S-RECOVERY EXIT
    THEN
    _SDA-STATE @ _SDOC-READ DUP IF
        _SDA-STATUS ! _SDOC-ACTIVATE-RELEASE
        0 _SDA-STATUS @ EXIT
    THEN DROP
    _SDA-STATE @ _SDOC-CURRENT-TEXT-VALID? 0= IF
        _SDOC-ACTIVATE-RELEASE 0 SDOC-S-SOURCE EXIT
    THEN
    _SDA-INSTANCE @ _SDA-CREG @ CREG-INST+ IF
        _SDOC-ACTIVATE-RELEASE 0 SDOC-S-REGISTRY EXIT
    THEN
    _SDA-STATE @ _SDS.FLAGS DUP @ _SDOC-F-IN-REGISTRY OR SWAP !
    _SDA-RID @ _SDA-INSTANCE @ _SDA-CONTEXT @ _SDA-RREG @
        RREG-PUBLISH DUP RREG-S-OK <> IF
        DROP _SDOC-ACTIVATE-RELEASE 0 SDOC-S-RESOURCE EXIT
    THEN DROP
    _SDA-STATE @ _SDS.FLAGS DUP @ _SDOC-F-PUBLISHED OR SWAP !
    _SDA-INSTANCE @ DUP _SDOC-LIVE ! SDOC-S-OK ;

: SDOC-ACTIVATE  ( vfs rid context rreg creg -- instance status )
    ['] _SDOC-ACTIVATE-LOCKED _SDOC-GUARD WITH-GUARD ;

VARIABLE _SDD-INSTANCE
VARIABLE _SDD-STATE

: _SDOC-DEACTIVATE-LOCKED  ( instance -- status )
    DUP _SDD-INSTANCE !
    DUP _SDOC-STATE-VALID? 0= IF DROP SDOC-S-INVALID EXIT THEN
    _SDOC-LIVE @ <> IF SDOC-S-INVALID EXIT THEN
    _SDD-INSTANCE @ CINST-STATE _SDD-STATE !
    _SDD-STATE @ _SDS.FLAGS @ _SDOC-F-PUBLISHED AND IF
        _SDD-STATE @ _SDS.RID
        _SDD-STATE @ _SDS.CONTEXT @
        _SDD-STATE @ _SDS.RREG @ RREG-UNPUBLISH
        RREG-S-OK <> IF SDOC-S-RESOURCE EXIT THEN
        _SDD-STATE @ _SDS.FLAGS DUP @
            _SDOC-F-PUBLISHED INVERT AND SWAP !
    THEN
    _SDD-STATE @ _SDS.FLAGS @ _SDOC-F-IN-REGISTRY AND IF
        _SDD-INSTANCE @ _SDD-STATE @ _SDS.CREG @ CREG-INST-
        IF SDOC-S-REGISTRY EXIT THEN
        _SDD-STATE @ _SDS.FLAGS DUP @
            _SDOC-F-IN-REGISTRY INVERT AND SWAP !
    THEN
    0 _SDOC-LIVE !
    _SDD-INSTANCE @ CINST-FREE
    SDOC-S-OK ;

: _SDOC-DEACTIVATE-OWNER-GUARDED  ( instance -- status )
    ['] _SDOC-DEACTIVATE-LOCKED _SDOC-GUARD WITH-GUARD ;

: SDOC-DEACTIVATE  ( instance -- status )
    \ Dispatch continues to validate output and commit the generic component
    \ revision after a handler returns.  Reject teardown requested from inside
    \ that dispatch, and otherwise quiesce all synchronous dispatch before the
    \ owner can be unpublished or freed.
    CBUS-DISPATCHING? IF DROP SDOC-S-BUSY EXIT THEN
    ['] _SDOC-DEACTIVATE-OWNER-GUARDED
        CBUS-WITH-DISPATCH-QUIESCED ;

VARIABLE _SDF-INSTANCE
VARIABLE _SDF-REF

: _SDOC-REF-LOCKED  ( instance destination -- status )
    _SDF-REF ! _SDF-INSTANCE !
    _SDF-REF @ 0= IF SDOC-S-INVALID EXIT THEN
    _SDF-REF @ RREF-INIT
    _SDF-INSTANCE @ _SDOC-STATE-VALID? 0= IF
        SDOC-S-INVALID EXIT
    THEN
    _SDF-INSTANCE @ _SDOC-LIVE @ <> IF SDOC-S-INVALID EXIT THEN
    _SDF-INSTANCE @ CINST-STATE _SDS.RID
        _SDF-REF @ RREF.ID RID-COPY
    _SDF-INSTANCE @ CINST.REVISION @ _SDF-REF @ RREF.REVISION !
    SDOC-S-OK ;

: SDOC-REF  ( instance destination -- status )
    ['] _SDOC-REF-LOCKED _SDOC-GUARD WITH-GUARD ;

: _SDOC-VALID-LOCKED  ( instance -- flag )
    DUP _SDOC-STATE-VALID? SWAP _SDOC-LIVE @ = AND ;

: SDOC-VALID?  ( instance -- flag )
    ['] _SDOC-VALID-LOCKED _SDOC-GUARD WITH-GUARD ;
