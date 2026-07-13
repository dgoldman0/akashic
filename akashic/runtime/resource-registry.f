\ =====================================================================
\  resource-registry.f - Bounded activation-local resource resolution
\ =====================================================================
\  RREG maps stable resource RIDs to borrowed live component instances.
\  It is scoped to one exact Context activation and never owns instances.
\  Callers must unpublish entries before freeing their target instances.
\ =====================================================================

PROVIDED akashic-runtime-rreg

REQUIRE resource-ref.f
REQUIRE context.f
REQUIRE registry.f
REQUIRE ../concurrency/guard.f

0 CONSTANT RREG-S-OK
1 CONSTANT RREG-S-INVALID
2 CONSTANT RREG-S-FULL
3 CONSTANT RREG-S-DUPLICATE
4 CONSTANT RREG-S-NOT-FOUND
5 CONSTANT RREG-S-STALE-INSTANCE
6 CONSTANT RREG-S-STALE-REVISION
7 CONSTANT RREG-S-STALE-EPOCH

64 CONSTANT RREG-CAPACITY

\ Activation-local entry.  RID is copied; INSTANCE is borrowed.
 0 CONSTANT _RGE-ID                    \ RID-SIZE bytes
32 CONSTANT _RGE-TARGET-ID
40 CONSTANT _RGE-TARGET-GEN
48 CONSTANT _RGE-INSTANCE
56 CONSTANT _RGE-FLAGS
64 CONSTANT RREG-ENTRY-SIZE

: RGE.ID          ( entry -- id ) _RGE-ID + ;
: RGE.TARGET-ID   ( entry -- a ) _RGE-TARGET-ID + ;
: RGE.TARGET-GEN  ( entry -- a ) _RGE-TARGET-GEN + ;
: RGE.INSTANCE    ( entry -- a ) _RGE-INSTANCE + ;
: RGE.FLAGS       ( entry -- a ) _RGE-FLAGS + ;

0x47455252 CONSTANT RREG-MAGIC       \ "RREG"
1          CONSTANT RREG-ABI-VERSION

 0 CONSTANT _RRG-MAGIC
 8 CONSTANT _RRG-ABI
16 CONSTANT _RRG-SIZE
24 CONSTANT _RRG-EPOCH
32 CONSTANT _RRG-CONTEXT-ID
40 CONSTANT _RRG-CONTEXT-GEN
48 CONSTANT _RRG-COMPONENTS
56 CONSTANT _RRG-CONTEXT
64 CONSTANT _RRG-COUNT
72 CONSTANT _RRG-ENTRIES
_RRG-ENTRIES RREG-CAPACITY RREG-ENTRY-SIZE * + CONSTANT RREG-SIZE

: RREG.MAGIC        ( reg -- a ) _RRG-MAGIC + ;
: RREG.ABI          ( reg -- a ) _RRG-ABI + ;
: RREG.SIZE         ( reg -- a ) _RRG-SIZE + ;
: RREG.EPOCH        ( reg -- a ) _RRG-EPOCH + ;
: RREG.CONTEXT-ID   ( reg -- a ) _RRG-CONTEXT-ID + ;
: RREG.CONTEXT-GEN  ( reg -- a ) _RRG-CONTEXT-GEN + ;
: RREG.COMPONENTS   ( reg -- a ) _RRG-COMPONENTS + ;
: RREG.CONTEXT      ( reg -- a ) _RRG-CONTEXT + ;
: RREG.COUNT        ( reg -- a ) _RRG-COUNT + ;
: RREG.ENTRIES      ( reg -- a ) _RRG-ENTRIES + ;

: RREG-NTH  ( index reg -- entry | 0 )
    >R DUP 0< OVER R@ RREG.COUNT @ >= OR IF
        DROP R> DROP 0 EXIT
    THEN
    RREG-ENTRY-SIZE * R> RREG.ENTRIES + ;

VARIABLE _RRGV-R
VARIABLE _RRGV-C
VARIABLE _RRGV-E
VARIABLE _RRGV-P
VARIABLE _RRGV-I
VARIABLE _RRGV-J

: RREG-VALID?  ( reg -- flag )
    DUP 0= IF DROP 0 EXIT THEN _RRGV-R !
    _RRGV-R @ RREG.MAGIC @ RREG-MAGIC <> IF 0 EXIT THEN
    _RRGV-R @ RREG.ABI @ RREG-ABI-VERSION <> IF 0 EXIT THEN
    _RRGV-R @ RREG.SIZE @ RREG-SIZE < IF 0 EXIT THEN
    _RRGV-R @ RREG.EPOCH @ 0> 0= IF 0 EXIT THEN
    _RRGV-R @ RREG.CONTEXT-ID @ 0> 0= IF 0 EXIT THEN
    _RRGV-R @ RREG.CONTEXT-GEN @ 0> 0= IF 0 EXIT THEN
    _RRGV-R @ RREG.COMPONENTS @ 0= IF 0 EXIT THEN
    _RRGV-R @ RREG.COUNT @ DUP 0< IF DROP 0 EXIT THEN
    RREG-CAPACITY > IF 0 EXIT THEN
    _RRGV-R @ RREG.CONTEXT @ DUP 0= IF DROP 0 EXIT THEN _RRGV-C !
    _RRGV-C @ CTX-VALID? 0= IF 0 EXIT THEN
    _RRGV-C @ CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF 0 EXIT THEN
    _RRGV-R @ RREG.CONTEXT-ID @ _RRGV-C @ CTX.ID @ =
    _RRGV-R @ RREG.CONTEXT-GEN @ _RRGV-C @ CTX.GENERATION @ = AND
    _RRGV-R @ RREG.EPOCH @ _RRGV-C @ CTX.EPOCH @ = AND 0= IF
        0 EXIT
    THEN
    _RRGV-R @ RREG.COUNT @ 0 ?DO
        I _RRGV-R @ RREG-NTH DUP _RRGV-E ! DROP
        _RRGV-E @ RGE.ID RID-PRESENT? 0= IF 0 UNLOOP EXIT THEN
        _RRGV-E @ RGE.TARGET-ID @ 0> 0= IF 0 UNLOOP EXIT THEN
        _RRGV-E @ RGE.TARGET-GEN @ 0> 0= IF 0 UNLOOP EXIT THEN
        _RRGV-E @ RGE.INSTANCE @ 0= IF 0 UNLOOP EXIT THEN
        _RRGV-E @ RGE.FLAGS @ IF 0 UNLOOP EXIT THEN
        \ Re-validate the key invariant rather than trusting that all memory
        \ reached this state through RREG-PUBLISH.
        I _RRGV-I ! 0 _RRGV-J !
        BEGIN _RRGV-J @ _RRGV-I @ < WHILE
            _RRGV-J @ _RRGV-R @ RREG-NTH _RRGV-P !
            _RRGV-E @ RGE.ID _RRGV-P @ RGE.ID RID=
            _RRGV-E @ RGE.TARGET-ID @ _RRGV-P @ RGE.TARGET-ID @ =
            _RRGV-E @ RGE.TARGET-GEN @ _RRGV-P @ RGE.TARGET-GEN @ =
                AND OR IF
                0 UNLOOP EXIT
            THEN
            1 _RRGV-J +!
        REPEAT
    LOOP
    -1 ;

VARIABLE _RRGN-COMPONENTS
VARIABLE _RRGN-CONTEXT

: RREG-NEW  ( component-registry context -- resource-registry ior )
    _RRGN-CONTEXT ! _RRGN-COMPONENTS !
    _RRGN-COMPONENTS @ 0= IF 0 RREG-S-INVALID EXIT THEN
    _RRGN-CONTEXT @ CTX-VALID? 0= IF 0 RREG-S-INVALID EXIT THEN
    _RRGN-CONTEXT @ CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        0 RREG-S-INVALID EXIT
    THEN
    RREG-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP RREG-SIZE 0 FILL
    RREG-MAGIC OVER RREG.MAGIC !
    RREG-ABI-VERSION OVER RREG.ABI !
    RREG-SIZE OVER RREG.SIZE !
    _RRGN-CONTEXT @ CTX.EPOCH @ OVER RREG.EPOCH !
    _RRGN-CONTEXT @ CTX.ID @ OVER RREG.CONTEXT-ID !
    _RRGN-CONTEXT @ CTX.GENERATION @ OVER RREG.CONTEXT-GEN !
    _RRGN-COMPONENTS @ OVER RREG.COMPONENTS !
    _RRGN-CONTEXT @ OVER RREG.CONTEXT !
    0 ;

: RREG-FREE  ( reg -- )
    ?DUP IF DUP RREG-SIZE 0 FILL FREE THEN ;

VARIABLE _RRGCM-C
VARIABLE _RRGCM-R

: RREG-CONTEXT?  ( context reg -- flag )
    _RRGCM-R ! _RRGCM-C !
    _RRGCM-R @ RREG-VALID? 0= IF 0 EXIT THEN
    _RRGCM-C @ CTX-VALID? 0= IF 0 EXIT THEN
    _RRGCM-C @ CTX.ID @ _RRGCM-R @ RREG.CONTEXT-ID @ =
    _RRGCM-C @ CTX.GENERATION @ _RRGCM-R @ RREG.CONTEXT-GEN @ = AND
    _RRGCM-C @ CTX.EPOCH @ _RRGCM-R @ RREG.EPOCH @ = AND ;

VARIABLE _RRGF-ID
VARIABLE _RRGF-R

: _RREG-FIND-ID  ( resource-id reg -- entry | 0 )
    _RRGF-R ! _RRGF-ID !
    _RRGF-ID @ RID-PRESENT? 0= IF 0 EXIT THEN
    _RRGF-R @ RREG.COUNT @ 0 ?DO
        I _RRGF-R @ RREG-NTH DUP RGE.ID _RRGF-ID @ RID= IF
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 ;

VARIABLE _RRGL-E
VARIABLE _RRGL-R
VARIABLE _RRGL-I

VARIABLE _RRGCI-ID
VARIABLE _RRGCI-GEN
VARIABLE _RRGCI-R

: _RREG-CINST-FIND  ( id generation component-registry -- inst | 0 )
    _RRGCI-R ! _RRGCI-GEN ! _RRGCI-ID !
    _RRGCI-R @ CREG.INST-N @ 0 ?DO
        I _RRGCI-R @ CREG-INST-NTH
        DUP CINST.ID @ _RRGCI-ID @ =
        OVER CINST.GENERATION @ _RRGCI-GEN @ = AND IF
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 ;

: _RREG-LIVE  ( entry reg -- instance status )
    _RRGL-R ! _RRGL-E !
    _RRGL-E @ RGE.TARGET-ID @ _RRGL-E @ RGE.TARGET-GEN @
    _RRGL-R @ RREG.COMPONENTS @ _RREG-CINST-FIND DUP 0= IF
        DROP 0 RREG-S-STALE-INSTANCE EXIT
    THEN
    DUP _RRGL-I ! _RRGL-E @ RGE.INSTANCE @ <> IF
        0 RREG-S-STALE-INSTANCE EXIT
    THEN
    _RRGL-I @ CINST-DESC COMP-DESC-VALID? 0= IF
        0 RREG-S-STALE-INSTANCE EXIT
    THEN
    _RRGL-I @ CINST.REVISION @ 0> 0= IF
        0 RREG-S-STALE-INSTANCE EXIT
    THEN
    _RRGL-I @ RREG-S-OK ;

VARIABLE _RRGP-ID
VARIABLE _RRGP-I
VARIABLE _RRGP-C
VARIABLE _RRGP-R
VARIABLE _RRGP-E

: RREG-PUBLISH  ( resource-id instance context reg -- status )
    _RRGP-R ! _RRGP-C ! _RRGP-I ! _RRGP-ID !
    _RRGP-R @ RREG-VALID? 0= IF RREG-S-INVALID EXIT THEN
    _RRGP-C @ _RRGP-R @ RREG-CONTEXT? 0= IF RREG-S-STALE-EPOCH EXIT THEN
    _RRGP-ID @ RID-PRESENT? 0= _RRGP-I @ 0= OR IF RREG-S-INVALID EXIT THEN
    _RRGP-I @ CINST-DESC COMP-DESC-VALID? 0= IF RREG-S-INVALID EXIT THEN
    _RRGP-I @ CINST.ID @ 0> 0= IF RREG-S-INVALID EXIT THEN
    _RRGP-I @ CINST.GENERATION @ 0> 0= IF RREG-S-INVALID EXIT THEN
    _RRGP-I @ CINST.REVISION @ 0> 0= IF RREG-S-INVALID EXIT THEN
    _RRGP-I @ CINST.ID @ _RRGP-I @ CINST.GENERATION @
        _RRGP-R @ RREG.COMPONENTS @ _RREG-CINST-FIND
        _RRGP-I @ <> IF RREG-S-STALE-INSTANCE EXIT THEN
    _RRGP-R @ RREG.COUNT @ 0 ?DO
        I _RRGP-R @ RREG-NTH DUP _RRGP-E ! DROP
        \ Freeze invariant: one semantic resource per owner instance.  Until
        \ authority grants seal RESOURCE-ID themselves, aliasing one target
        \ under multiple RIDs would permit an authorized request to swap only
        \ its correlation identity.  Reject either repeated key here.
        _RRGP-E @ RGE.ID _RRGP-ID @ RID=
        _RRGP-E @ RGE.TARGET-ID @ _RRGP-I @ CINST.ID @ =
        _RRGP-E @ RGE.TARGET-GEN @ _RRGP-I @ CINST.GENERATION @ = AND OR IF
            RREG-S-DUPLICATE UNLOOP EXIT
        THEN
    LOOP
    _RRGP-R @ RREG.COUNT @ RREG-CAPACITY >= IF RREG-S-FULL EXIT THEN
    _RRGP-R @ RREG.COUNT @ RREG-ENTRY-SIZE *
        _RRGP-R @ RREG.ENTRIES + DUP _RRGP-E !
    RREG-ENTRY-SIZE 0 FILL
    _RRGP-ID @ _RRGP-E @ RGE.ID RID-COPY
    _RRGP-I @ CINST.ID @ _RRGP-E @ RGE.TARGET-ID !
    _RRGP-I @ CINST.GENERATION @ _RRGP-E @ RGE.TARGET-GEN !
    _RRGP-I @ _RRGP-E @ RGE.INSTANCE !
    1 _RRGP-R @ RREG.COUNT +!
    RREG-S-OK ;

VARIABLE _RRGU-ID
VARIABLE _RRGU-C
VARIABLE _RRGU-R
VARIABLE _RRGU-I

: RREG-UNPUBLISH  ( resource-id context reg -- status )
    _RRGU-R ! _RRGU-C ! _RRGU-ID !
    _RRGU-R @ RREG-VALID? 0= IF RREG-S-INVALID EXIT THEN
    _RRGU-C @ _RRGU-R @ RREG-CONTEXT? 0= IF RREG-S-STALE-EPOCH EXIT THEN
    _RRGU-ID @ RID-PRESENT? 0= IF RREG-S-INVALID EXIT THEN
    _RRGU-R @ RREG.COUNT @ 0 ?DO
        I _RRGU-R @ RREG-NTH RGE.ID _RRGU-ID @ RID= IF
            I _RRGU-I !
            BEGIN _RRGU-I @ _RRGU-R @ RREG.COUNT @ 1- < WHILE
                _RRGU-I @ 1+ _RRGU-R @ RREG-NTH
                _RRGU-I @ _RRGU-R @ RREG-NTH
                RREG-ENTRY-SIZE MOVE
                1 _RRGU-I +!
            REPEAT
            -1 _RRGU-R @ RREG.COUNT +!
            _RRGU-R @ RREG.COUNT @ RREG-ENTRY-SIZE *
                _RRGU-R @ RREG.ENTRIES + RREG-ENTRY-SIZE 0 FILL
            RREG-S-OK UNLOOP EXIT
        THEN
    LOOP
    RREG-S-NOT-FOUND ;

VARIABLE _RRGRF-ID
VARIABLE _RRGRF-C
VARIABLE _RRGRF-D
VARIABLE _RRGRF-R
VARIABLE _RRGRF-E
VARIABLE _RRGRF-I

: RREG-REF  ( resource-id context destination reg -- status )
    _RRGRF-R ! _RRGRF-D ! _RRGRF-C ! _RRGRF-ID !
    _RRGRF-D @ 0= IF RREG-S-INVALID EXIT THEN
    _RRGRF-D @ RREF-INIT
    _RRGRF-R @ RREG-VALID? 0= IF RREG-S-INVALID EXIT THEN
    _RRGRF-C @ _RRGRF-R @ RREG-CONTEXT? 0= IF RREG-S-STALE-EPOCH EXIT THEN
    _RRGRF-ID @ RID-PRESENT? 0= IF RREG-S-INVALID EXIT THEN
    _RRGRF-ID @ _RRGRF-R @ _RREG-FIND-ID DUP 0= IF
        DROP RREG-S-NOT-FOUND EXIT
    THEN _RRGRF-E !
    _RRGRF-E @ _RRGRF-R @ _RREG-LIVE DUP IF
        NIP EXIT
    THEN
    DROP _RRGRF-I !
    _RRGRF-ID @ _RRGRF-D @ RREF.ID RID-COPY
    _RRGRF-I @ CINST.REVISION @ _RRGRF-D @ RREF.REVISION !
    RREG-S-OK ;

VARIABLE _RRGR-REF
VARIABLE _RRGR-C
VARIABLE _RRGR-R
VARIABLE _RRGR-E
VARIABLE _RRGR-I

: RREG-RESOLVE  ( reference context reg -- instance status )
    _RRGR-R ! _RRGR-C ! _RRGR-REF !
    _RRGR-R @ RREG-VALID? 0= IF 0 RREG-S-INVALID EXIT THEN
    _RRGR-C @ _RRGR-R @ RREG-CONTEXT? 0= IF 0 RREG-S-STALE-EPOCH EXIT THEN
    _RRGR-REF @ RREF-VALID? 0= IF 0 RREG-S-INVALID EXIT THEN
    _RRGR-REF @ RREF.ID _RRGR-R @ _RREG-FIND-ID DUP 0= IF
        DROP 0 RREG-S-NOT-FOUND EXIT
    THEN _RRGR-E !
    _RRGR-E @ _RRGR-R @ _RREG-LIVE DUP IF EXIT THEN
    DROP _RRGR-I !
    _RRGR-REF @ RREF.REVISION @ ?DUP IF
        _RRGR-I @ CINST.REVISION @ <> IF
            0 RREG-S-STALE-REVISION EXIT
        THEN
    THEN
    _RRGR-I @ RREG-S-OK ;

\ The first implementation of this module predates cross-core applet calls
\ and uses bounded module scratch.  A recursive module guard makes every
\ public entry safe without imposing a caller-held lock; nested calls compiled
\ above continue to execute beneath the outer acquisition.
' RREG-NTH       CONSTANT _RREG-NTH-XT
' RREG-VALID?    CONSTANT _RREG-VALID-XT
' RREG-NEW       CONSTANT _RREG-NEW-XT
' RREG-FREE      CONSTANT _RREG-FREE-XT
' RREG-CONTEXT?  CONSTANT _RREG-CONTEXT-XT
' RREG-PUBLISH   CONSTANT _RREG-PUBLISH-XT
' RREG-UNPUBLISH CONSTANT _RREG-UNPUBLISH-XT
' RREG-REF       CONSTANT _RREG-REF-XT
' RREG-RESOLVE   CONSTANT _RREG-RESOLVE-XT

GUARD _RREG-GUARD

: RREG-NTH       ( index reg -- entry | 0 )
    _RREG-NTH-XT _RREG-GUARD WITH-GUARD ;
: RREG-VALID?    ( reg -- flag )
    _RREG-VALID-XT _RREG-GUARD WITH-GUARD ;
: RREG-NEW       ( component-registry context -- resource-registry ior )
    _RREG-NEW-XT _RREG-GUARD WITH-GUARD ;
: RREG-FREE      ( reg -- )
    _RREG-FREE-XT _RREG-GUARD WITH-GUARD ;
: RREG-CONTEXT?  ( context reg -- flag )
    _RREG-CONTEXT-XT _RREG-GUARD WITH-GUARD ;
: RREG-PUBLISH   ( resource-id instance context reg -- status )
    _RREG-PUBLISH-XT _RREG-GUARD WITH-GUARD ;
: RREG-UNPUBLISH ( resource-id context reg -- status )
    _RREG-UNPUBLISH-XT _RREG-GUARD WITH-GUARD ;
: RREG-REF       ( resource-id context destination reg -- status )
    _RREG-REF-XT _RREG-GUARD WITH-GUARD ;
: RREG-RESOLVE   ( reference context reg -- instance status )
    _RREG-RESOLVE-XT _RREG-GUARD WITH-GUARD ;
