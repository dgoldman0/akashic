\ =====================================================================
\  host.f - Caller-owned multi-applet host mechanics
\ =====================================================================
\
\  Owns live child slots, descriptor instances, UIDL contexts, transactional
\  launch/rollback, fail-closed close negotiation, force-clean teardown,
\  focus/minimize/restore, and child event/tick/paint dispatch.
\
\  It owns no product catalog, chrome, tiling policy, service namespace, or
\  concrete applet.  The caller injects its registry, endpoint, relayout,
\  owner-resource release, and closed-slot projection through AHOST state.
\ =====================================================================

PROVIDED akashic-tui-applet-host

REQUIRE ../app-desc.f
REQUIRE ../app-shell.f
REQUIRE ../uidl-tui.f
REQUIRE ../region.f
REQUIRE ../../runtime/registry.f

\ =====================================================================
\  Child slot
\ =====================================================================

 0 CONSTANT _AHS-O-DESC
 8 CONSTANT _AHS-O-INST
16 CONSTANT _AHS-O-RGN
24 CONSTANT _AHS-O-STATE
32 CONSTANT _AHS-O-UCTX
40 CONSTANT _AHS-O-HAS-UIDL
48 CONSTANT _AHS-O-NEXT
56 CONSTANT _AHS-O-ID
64 CONSTANT _AHS-O-UIDL-BUF
72 CONSTANT _AHS-O-DIRTY
80 CONSTANT _AHS-O-SEEN-REV
88 CONSTANT AHS-SIZE

0 CONSTANT AHS-S-EMPTY
1 CONSTANT AHS-S-RUNNING
2 CONSTANT AHS-S-MINIMIZED
3 CONSTANT AHS-S-FOCUSED

: AHS.DESC      ( slot -- a ) _AHS-O-DESC + ;
: AHS.INST      ( slot -- a ) _AHS-O-INST + ;
: AHS.RGN       ( slot -- a ) _AHS-O-RGN + ;
: AHS.STATE     ( slot -- a ) _AHS-O-STATE + ;
: AHS.UCTX      ( slot -- a ) _AHS-O-UCTX + ;
: AHS.HAS-UIDL  ( slot -- a ) _AHS-O-HAS-UIDL + ;
: AHS.NEXT      ( slot -- a ) _AHS-O-NEXT + ;
: AHS.ID        ( slot -- a ) _AHS-O-ID + ;
: AHS.UIDL-BUF  ( slot -- a ) _AHS-O-UIDL-BUF + ;
: AHS.DIRTY     ( slot -- a ) _AHS-O-DIRTY + ;
: AHS.SEEN-REV  ( slot -- a ) _AHS-O-SEEN-REV + ;

: AHS-VISIBLE?  ( slot -- flag )
    AHS.STATE @ DUP AHS-S-RUNNING = SWAP AHS-S-FOCUSED = OR ;

: AHS-ALIVE?  ( slot -- flag )
    AHS.STATE @ AHS-S-EMPTY <> ;

: AHS-ACTIVATE  ( slot -- )
    DUP AHS.DESC @ APP.ACTIVATE-XT @ ?DUP IF
        SWAP AHS.INST @ SWAP EXECUTE
    ELSE
        DROP
    THEN ;

: AHS-CTX-SAVE  ( slot -- )
    AHS.UCTX @ ASHELL-CTX-SAVE ;

: AHS-CTX-SWITCH  ( slot -- )
    DUP AHS.UCTX @ ASHELL-CTX-SWITCH
    AHS-ACTIVATE ;

\ =====================================================================
\  Caller-owned host state and injection
\ =====================================================================

 0 CONSTANT _AH-O-HEAD
 8 CONSTANT _AH-O-FOCUS
16 CONSTANT _AH-O-NEXT-ID
24 CONSTANT _AH-O-LAST-MIN
32 CONSTANT _AH-O-REGISTRY
40 CONSTANT _AH-O-ENDPOINT
48 CONSTANT _AH-O-CONTEXT
56 CONSTANT _AH-O-RELAYOUT-XT       \ ( context -- )
64 CONSTANT _AH-O-RELEASE-XT       \ ( instance context -- ior )
72 CONSTANT _AH-O-CLOSED-XT        \ ( slot-id context -- )
80 CONSTANT AHOST-SIZE

: AHOST.HEAD        ( host -- a ) _AH-O-HEAD + ;
: AHOST.FOCUS       ( host -- a ) _AH-O-FOCUS + ;
: AHOST.NEXT-ID     ( host -- a ) _AH-O-NEXT-ID + ;
: AHOST.LAST-MIN    ( host -- a ) _AH-O-LAST-MIN + ;
: AHOST.REGISTRY    ( host -- a ) _AH-O-REGISTRY + ;
: AHOST.ENDPOINT    ( host -- a ) _AH-O-ENDPOINT + ;
: AHOST.CONTEXT     ( host -- a ) _AH-O-CONTEXT + ;
: AHOST.RELAYOUT-XT ( host -- a ) _AH-O-RELAYOUT-XT + ;
: AHOST.RELEASE-XT  ( host -- a ) _AH-O-RELEASE-XT + ;
: AHOST.CLOSED-XT   ( host -- a ) _AH-O-CLOSED-XT + ;

: AHOST-INIT  ( host -- )
    DUP AHOST-SIZE 0 FILL
    1 SWAP AHOST.NEXT-ID ! ;

: AHOST-REGISTRY!  ( registry host -- ) AHOST.REGISTRY ! ;
: AHOST-ENDPOINT!  ( endpoint host -- ) AHOST.ENDPOINT ! ;
: AHOST-CONTEXT!   ( context host -- ) AHOST.CONTEXT ! ;
: AHOST-RELAYOUT!  ( xt host -- ) AHOST.RELAYOUT-XT ! ;
: AHOST-RELEASE!   ( xt host -- ) AHOST.RELEASE-XT ! ;
: AHOST-CLOSED!    ( xt host -- ) AHOST.CLOSED-XT ! ;

: _AHOST-RELAYOUT  ( host -- )
    DUP AHOST.RELAYOUT-XT @ ?DUP IF
        SWAP AHOST.CONTEXT @ SWAP EXECUTE
    ELSE
        DROP
    THEN ;

: _AHOST-RELEASE  ( instance host -- ior )
    DUP AHOST.RELEASE-XT @ ?DUP IF
        >R AHOST.CONTEXT @ R> EXECUTE
    ELSE
        2DROP 0
    THEN ;

: _AHOST-CLOSED  ( slot-id host -- )
    DUP AHOST.CLOSED-XT @ ?DUP IF
        >R AHOST.CONTEXT @ R> EXECUTE
    ELSE
        2DROP
    THEN ;

\ =====================================================================
\  List and focus helpers
\ =====================================================================

: AHOST-SLOT-COUNT  ( host -- n )
    0 SWAP AHOST.HEAD @
    BEGIN ?DUP WHILE SWAP 1+ SWAP AHS.NEXT @ REPEAT ;

: AHOST-VCOUNT  ( host -- n )
    0 SWAP AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP AHS-VISIBLE? IF SWAP 1+ SWAP THEN
        AHS.NEXT @
    REPEAT ;

VARIABLE _AHF-ID
VARIABLE _AHF-HOST

: AHOST-FIND-ID  ( id host -- slot | 0 )
    _AHF-HOST ! _AHF-ID !
    _AHF-HOST @ AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP AHS.ID @ _AHF-ID @ = IF EXIT THEN
        AHS.NEXT @
    REPEAT
    0 ;

VARIABLE _AHU-SLOT
VARIABLE _AHU-HOST
VARIABLE _AHU-PREV

: _AHOST-UNLINK  ( slot host -- )
    _AHU-HOST ! _AHU-SLOT !
    _AHU-HOST @ AHOST.HEAD @ _AHU-SLOT @ = IF
        _AHU-SLOT @ AHS.NEXT @ _AHU-HOST @ AHOST.HEAD ! EXIT
    THEN
    _AHU-HOST @ AHOST.HEAD @ _AHU-PREV !
    BEGIN _AHU-PREV @ WHILE
        _AHU-PREV @ AHS.NEXT @ _AHU-SLOT @ = IF
            _AHU-SLOT @ AHS.NEXT @ _AHU-PREV @ AHS.NEXT ! EXIT
        THEN
        _AHU-PREV @ AHS.NEXT @ _AHU-PREV !
    REPEAT ;

VARIABLE _AHA-SLOT
VARIABLE _AHA-HOST

: _AHOST-APPEND  ( slot host -- )
    _AHA-HOST ! _AHA-SLOT !
    0 _AHA-SLOT @ AHS.NEXT !
    _AHA-HOST @ AHOST.HEAD @ 0= IF
        _AHA-SLOT @ _AHA-HOST @ AHOST.HEAD ! EXIT
    THEN
    _AHA-HOST @ AHOST.HEAD @
    BEGIN DUP AHS.NEXT @ WHILE AHS.NEXT @ REPEAT
    _AHA-SLOT @ SWAP AHS.NEXT ! ;

: _AHOST-AUTOFOCUS  ( host -- )
    DUP AHOST.FOCUS @ IF DROP EXIT THEN
    DUP AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP AHS-VISIBLE? IF
            DUP 2 PICK AHOST.FOCUS !
            AHS-S-FOCUSED SWAP AHS.STATE !
            DROP EXIT
        THEN
        AHS.NEXT @
    REPEAT
    DROP ;

: AHOST-FOCUSED-INSTANCE  ( host -- instance | 0 )
    AHOST.FOCUS @ ?DUP IF AHS.INST @ ELSE 0 THEN ;

\ =====================================================================
\  Fail-closed close negotiation and force-clean teardown
\ =====================================================================

VARIABLE _AHQ-SLOT
VARIABLE _AHQ-REASON
VARIABLE _AHQ-DECISION

: _AHQ-CALL  ( -- decision )
    _AHQ-SLOT @ AHS.DESC @ APP.REQUEST-CLOSE-XT @ ?DUP 0= IF
        APP-CLOSE-D-ALLOW EXIT
    THEN
    _AHQ-REASON @ _AHQ-SLOT @ AHS.INST @ ROT EXECUTE ;

: _AHQ-ENTER  ( -- ) _AHQ-SLOT @ AHS-CTX-SWITCH ;

: _AHQ-SAVE  ( -- )
    _AHQ-SLOT @ AHS.HAS-UIDL @ IF
        ASHELL-ACTIVE-CTX _AHQ-SLOT @ AHS.UCTX @ = IF
            _AHQ-SLOT @ AHS-CTX-SAVE
        THEN
    THEN ;

: _AHQ-EXIT  ( -- ) 0 ASHELL-CTX-SWITCH ;

: _AHOST-REQUEST-CLOSE-SLOT  ( slot reason -- decision )
    _AHQ-REASON ! _AHQ-SLOT !
    APP-CLOSE-D-CANCEL _AHQ-DECISION !
    ['] _AHQ-ENTER CATCH 0= IF
        ['] _AHQ-CALL CATCH ?DUP IF
            DROP
        ELSE
            DUP APP-CLOSE-DECISION-VALID? IF
                _AHQ-DECISION !
            ELSE
                DROP
            THEN
        THEN
    THEN
    ['] _AHQ-SAVE CATCH IF APP-CLOSE-D-CANCEL _AHQ-DECISION ! THEN
    ['] _AHQ-EXIT CATCH IF
        _AHQ-SLOT @ AHS.UCTX @ ASHELL-CTX-FORGET
        APP-CLOSE-D-CANCEL _AHQ-DECISION !
    THEN
    _AHQ-DECISION @ ;

VARIABLE _AHC-SLOT
VARIABLE _AHC-HOST
VARIABLE _AHC-IOR
VARIABLE _AHC-INST
VARIABLE _AHC-ENTERED
VARIABLE _AHC-HOST-ONLY

: _AHC-REMEMBER  ( ior -- )
    ?DUP IF _AHC-IOR @ 0= IF _AHC-IOR ! ELSE DROP THEN THEN ;

: _AHC-ENTER  ( -- ) _AHC-SLOT @ AHS-CTX-SWITCH ;

: _AHC-SHUTDOWN  ( -- )
    _AHC-SLOT @ AHS.DESC @ APP.SHUTDOWN-XT @ ?DUP IF
        _AHC-SLOT @ AHS.INST @ SWAP EXECUTE
    THEN ;

: _AHC-RELEASE  ( -- )
    _AHC-INST @ ?DUP IF
        _AHC-HOST @ _AHOST-RELEASE ?DUP IF THROW THEN
    THEN ;

: _AHC-DETACH  ( -- )
    _AHC-SLOT @ AHS.HAS-UIDL DUP @ IF
        0 SWAP !
        ASHELL-ACTIVE-CTX _AHC-SLOT @ AHS.UCTX @ = IF UTUI-DETACH THEN
    ELSE
        DROP
    THEN ;

: _AHC-EXIT  ( -- ) 0 ASHELL-CTX-SWITCH ;

: _AHC-CLOSED  ( -- )
    _AHC-SLOT @ AHS.ID @ _AHC-HOST @ _AHOST-CLOSED ;

: _AHC-FREE-UIDL-BUF  ( -- )
    _AHC-SLOT @ AHS.UIDL-BUF DUP @ SWAP 0 SWAP !
    ASHELL-FREE-UIDL-BUF ;

: _AHC-FREE-UCTX  ( -- )
    _AHC-SLOT @ AHS.UCTX DUP @ SWAP 0 SWAP ! ?DUP IF UCTX-FREE THEN ;

: _AHC-FREE-REGION  ( -- )
    _AHC-SLOT @ AHS.RGN DUP @ SWAP 0 SWAP ! ?DUP IF RGN-FREE THEN ;

: _AHC-UNREGISTER  ( -- )
    _AHC-INST @ ?DUP IF
        _AHC-HOST @ AHOST.REGISTRY @ ?DUP IF CREG-INST- DROP ELSE DROP THEN
    THEN ;

: _AHC-FREE-INST  ( -- )
    0 _AHC-SLOT @ AHS.INST !
    _AHC-INST @ ?DUP IF CINST-FREE THEN ;

: _AHC-FREE-SLOT  ( -- ) _AHC-SLOT @ FREE ;

: _AHOST-CLOSE-SLOT-FORCE  ( slot host -- ior )
    _AHC-HOST ! _AHC-SLOT !
    _AHC-SLOT @ AHS.INST @ _AHC-INST !
    0 _AHC-IOR !
    _AHC-HOST-ONLY @ IF
        0 _AHC-ENTERED !
    ELSE
        ['] _AHC-ENTER CATCH DUP 0= _AHC-ENTERED ! _AHC-REMEMBER
    THEN
    _AHC-ENTERED @ IF ['] _AHC-SHUTDOWN CATCH _AHC-REMEMBER THEN
    ['] _AHC-RELEASE CATCH _AHC-REMEMBER
    ['] _AHC-DETACH CATCH _AHC-REMEMBER
    ['] _AHC-EXIT CATCH _AHC-REMEMBER
    _AHC-SLOT @ AHS.UCTX @ ASHELL-CTX-FORGET
    _AHC-SLOT @ _AHC-HOST @ AHOST.FOCUS @ = IF
        0 _AHC-HOST @ AHOST.FOCUS !
    THEN
    _AHC-SLOT @ _AHC-HOST @ AHOST.LAST-MIN @ = IF
        0 _AHC-HOST @ AHOST.LAST-MIN !
    THEN
    ['] _AHC-CLOSED CATCH _AHC-REMEMBER
    _AHC-SLOT @ _AHC-HOST @ _AHOST-UNLINK
    ['] _AHC-FREE-UIDL-BUF CATCH _AHC-REMEMBER
    ['] _AHC-FREE-UCTX CATCH _AHC-REMEMBER
    ['] _AHC-FREE-REGION CATCH _AHC-REMEMBER
    ['] _AHC-UNREGISTER CATCH _AHC-REMEMBER
    ['] _AHC-FREE-INST CATCH _AHC-REMEMBER
    ['] _AHC-FREE-SLOT CATCH _AHC-REMEMBER
    _AHC-HOST @ _AHOST-AUTOFOCUS
    _AHC-IOR @ ;

VARIABLE _AHI-HOST
VARIABLE _AHI-REASON
VARIABLE _AHI-IOR

: _AHI-REMEMBER  ( ior -- )
    ?DUP IF _AHI-IOR @ 0= IF _AHI-IOR ! ELSE DROP THEN THEN ;

: AHOST-REQUEST-CLOSE-ID  ( id reason host -- decision )
    _AHI-HOST ! _AHI-REASON !
    _AHI-HOST @ AHOST-FIND-ID DUP 0= IF DROP APP-CLOSE-D-ALLOW EXIT THEN
    DUP >R _AHI-REASON @ _AHOST-REQUEST-CLOSE-SLOT
    DUP APP-CLOSE-D-ALLOW = IF
        0 _AHI-IOR !
        0 _AHC-HOST-ONLY !
        R@ _AHI-HOST @ _AHOST-CLOSE-SLOT-FORCE _AHI-REMEMBER
        _AHI-HOST @ ['] _AHOST-RELAYOUT CATCH _AHI-REMEMBER
        _AHI-IOR @ ?DUP IF THROW THEN
    THEN
    R> DROP ;

VARIABLE _AHALL-DECISION
VARIABLE _AHALL-HOST
VARIABLE _AHALL-REASON

: _AHALL-MERGE  ( decision -- )
    DUP APP-CLOSE-D-CANCEL = IF
        DROP APP-CLOSE-D-CANCEL _AHALL-DECISION ! EXIT
    THEN
    APP-CLOSE-D-DEFER = IF
        _AHALL-DECISION @ APP-CLOSE-D-CANCEL <> IF
            APP-CLOSE-D-DEFER _AHALL-DECISION !
        THEN
    THEN ;

: AHOST-REQUEST-CLOSE-ALL  ( reason host -- decision )
    _AHALL-HOST ! _AHALL-REASON !
    APP-CLOSE-D-ALLOW _AHALL-DECISION !
    _AHALL-HOST @ AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP _AHALL-REASON @ _AHOST-REQUEST-CLOSE-SLOT _AHALL-MERGE
        AHS.NEXT @
    REPEAT
    ['] _AHQ-EXIT CATCH IF
        ASHELL-ACTIVE-CTX ASHELL-CTX-FORGET
        APP-CLOSE-D-CANCEL _AHALL-DECISION !
    THEN
    _AHALL-DECISION @ ;

VARIABLE _AHD-HOST
VARIABLE _AHD-IOR

: _AHD-REMEMBER  ( ior -- )
    ?DUP IF _AHD-IOR @ 0= IF _AHD-IOR ! ELSE DROP THEN THEN ;

: AHOST-DRAIN  ( host -- ior )
    _AHD-HOST ! 0 _AHD-IOR ! 0 _AHC-HOST-ONLY !
    BEGIN _AHD-HOST @ AHOST.HEAD @ ?DUP WHILE
        _AHD-HOST @ _AHOST-CLOSE-SLOT-FORCE _AHD-REMEMBER
    REPEAT
    _AHD-IOR @ ;

\ =====================================================================
\  Transactional child launch
\ =====================================================================

-1400 CONSTANT AHOST-LAUNCH-E-DESC
-1401 CONSTANT AHOST-LAUNCH-E-INSTANCE
-1402 CONSTANT AHOST-LAUNCH-E-REGISTRY
-1403 CONSTANT AHOST-LAUNCH-E-SLOT
-1404 CONSTANT AHOST-LAUNCH-E-CONTEXT
-1405 CONSTANT AHOST-LAUNCH-E-UIDL
-1406 CONSTANT AHOST-LAUNCH-E-RELAYOUT

VARIABLE _AHL-DESC
VARIABLE _AHL-HOST
VARIABLE _AHL-INST
VARIABLE _AHL-SLOT
VARIABLE _AHL-REGISTERED
VARIABLE _AHL-INIT-STARTED
VARIABLE _AHL-ID
VARIABLE _AHL-IOR

: _AHL-BODY  ( -- )
    _AHL-DESC @ APP-DESC-VALID? 0= IF AHOST-LAUNCH-E-DESC THROW THEN
    _AHL-HOST @ AHOST.RELAYOUT-XT @ 0= IF
        AHOST-LAUNCH-E-RELAYOUT THROW
    THEN
    _AHL-DESC @ APP.COMP-DESC @ CINST-NEW
    DUP IF NIP THROW THEN DROP
    DUP 0= IF AHOST-LAUNCH-E-INSTANCE THROW THEN _AHL-INST !
    _AHL-HOST @ AHOST.ENDPOINT @ _AHL-INST @ CINST.ENDPOINT !
    _AHL-HOST @ AHOST.REGISTRY @ ?DUP 0= IF
        AHOST-LAUNCH-E-REGISTRY THROW
    THEN
    _AHL-INST @ SWAP CREG-INST+ ?DUP IF THROW THEN
    -1 _AHL-REGISTERED !
    AHS-SIZE ALLOCATE DUP IF NIP THROW THEN DROP
    DUP 0= IF AHOST-LAUNCH-E-SLOT THROW THEN
    DUP _AHL-SLOT ! AHS-SIZE 0 FILL
    _AHL-DESC @ _AHL-SLOT @ AHS.DESC !
    _AHL-INST @ _AHL-SLOT @ AHS.INST !
    AHS-S-RUNNING _AHL-SLOT @ AHS.STATE !
    _AHL-HOST @ AHOST.NEXT-ID @ DUP _AHL-ID ! _AHL-SLOT @ AHS.ID !
    1 _AHL-HOST @ AHOST.NEXT-ID +!
    _AHL-DESC @ APP.UIDL-A @ _AHL-DESC @ APP.UIDL-FILE-A @ OR IF
        UCTX-ALLOC DUP 0= IF DROP AHOST-LAUNCH-E-CONTEXT THROW THEN
        DUP _AHL-SLOT @ AHS.UCTX !
        UCTX-CLEAR
        -1 _AHL-SLOT @ AHS.HAS-UIDL !
    THEN
    _AHL-SLOT @ _AHL-HOST @ _AHOST-APPEND
    _AHL-HOST @ AHOST.FOCUS @ 0= IF
        AHS-S-FOCUSED _AHL-SLOT @ AHS.STATE !
        _AHL-SLOT @ _AHL-HOST @ AHOST.FOCUS !
    THEN
    _AHL-HOST @ _AHOST-RELAYOUT
    _AHL-SLOT @ AHS.RGN @ 0= IF AHOST-LAUNCH-E-RELAYOUT THROW THEN
    _AHL-SLOT @ AHS.HAS-UIDL @ IF
        _AHL-SLOT @ AHS-CTX-SWITCH
        _AHL-DESC @ APP.UIDL-A @ IF
            _AHL-DESC @ APP.UIDL-A @ _AHL-DESC @ APP.UIDL-U @
            _AHL-SLOT @ AHS.RGN @ UTUI-LOAD
            0= IF AHOST-LAUNCH-E-UIDL THROW THEN
        ELSE
            _AHL-DESC @ APP.UIDL-FILE-A @ IF
                _AHL-DESC @ APP.UIDL-FILE-A @
                _AHL-DESC @ APP.UIDL-FILE-U @ _AHL-SLOT @ AHS.RGN @
                ASHELL-LOAD-UIDL DUP 0= IF
                    DROP AHOST-LAUNCH-E-UIDL THROW
                THEN
                _AHL-SLOT @ AHS.UIDL-BUF !
            THEN
        THEN
    THEN
    _AHL-DESC @ APP.INIT-XT @ ?DUP IF
        -1 _AHL-INIT-STARTED ! _AHL-INST @ SWAP EXECUTE
    THEN
    _AHL-SLOT @ AHS.HAS-UIDL @ IF _AHL-SLOT @ AHS-CTX-SAVE THEN ;

VARIABLE _AHR-IOR

: _AHR-REMEMBER  ( ior -- )
    ?DUP IF _AHR-IOR @ 0= IF _AHR-IOR ! ELSE DROP THEN THEN ;

: _AHR-EXIT  ( -- ) 0 ASHELL-CTX-SWITCH ;

: _AHR-UNREGISTER  ( -- )
    _AHL-INST @ ?DUP IF
        _AHL-HOST @ AHOST.REGISTRY @ ?DUP IF CREG-INST- DROP ELSE DROP THEN
    THEN ;

: _AHR-FREE-INST  ( -- ) _AHL-INST @ ?DUP IF CINST-FREE THEN ;

: _AHL-ROLLBACK  ( -- )
    0 _AHR-IOR !
    _AHL-SLOT @ ?DUP IF
        _AHL-INIT-STARTED @ 0= _AHC-HOST-ONLY !
        _AHL-HOST @ _AHOST-CLOSE-SLOT-FORCE _AHR-REMEMBER
        0 _AHC-HOST-ONLY !
    ELSE
        _AHL-REGISTERED @ IF ['] _AHR-UNREGISTER CATCH _AHR-REMEMBER THEN
        ['] _AHR-FREE-INST CATCH _AHR-REMEMBER
    THEN
    ['] _AHR-EXIT CATCH _AHR-REMEMBER
    _AHL-HOST @ ['] _AHOST-RELAYOUT CATCH _AHR-REMEMBER
    0 _AHL-INST ! 0 _AHL-SLOT ! 0 _AHL-REGISTERED !
    0 _AHL-INIT-STARTED !
    _AHR-IOR @ ?DUP IF THROW THEN ;

: AHOST-TRY-LAUNCH  ( desc host -- id ior )
    _AHL-HOST ! _AHL-DESC !
    0 _AHL-INST ! 0 _AHL-SLOT ! 0 _AHL-REGISTERED !
    0 _AHL-INIT-STARTED ! -1 _AHL-ID ! 0 _AHL-IOR !
    ['] _AHL-BODY CATCH ?DUP IF
        _AHL-IOR !
        ['] _AHL-ROLLBACK CATCH ?DUP IF
            _AHL-IOR @ 0= IF _AHL-IOR ! ELSE DROP THEN
        THEN
        -1 _AHL-IOR @ EXIT
    THEN
    _AHL-ID @ 0 ;

\ =====================================================================
\  Focus, minimize, restore
\ =====================================================================

VARIABLE _AHFO-HOST
VARIABLE _AHFO-RELAYOUT

: AHOST-FOCUS-ID  ( id host -- )
    _AHFO-HOST ! 0 _AHFO-RELAYOUT !
    _AHFO-HOST @ AHOST-FIND-ID DUP 0= IF DROP EXIT THEN
    DUP AHS.STATE @ AHS-S-MINIMIZED = IF
        -1 _AHFO-RELAYOUT !
        DUP _AHFO-HOST @ AHOST.LAST-MIN @ = IF
            0 _AHFO-HOST @ AHOST.LAST-MIN !
        THEN
        AHS-S-RUNNING OVER AHS.STATE !
    THEN
    _AHFO-HOST @ AHOST.FOCUS @ ?DUP IF
        DUP AHS.STATE @ AHS-S-FOCUSED = IF
            AHS-S-RUNNING SWAP AHS.STATE !
        ELSE
            DROP
        THEN
    THEN
    AHS-S-FOCUSED OVER AHS.STATE !
    _AHFO-HOST @ AHOST.FOCUS !
    _AHFO-RELAYOUT @ IF _AHFO-HOST @ _AHOST-RELAYOUT ELSE ASHELL-DIRTY! THEN ;

VARIABLE _AHM-HOST

: AHOST-MINIMIZE-ID  ( id host -- )
    _AHM-HOST !
    _AHM-HOST @ AHOST-FIND-ID DUP 0= IF DROP EXIT THEN
    DUP AHS.STATE @ AHS-S-MINIMIZED = IF DROP EXIT THEN
    AHS-S-MINIMIZED OVER AHS.STATE !
    DUP _AHM-HOST @ AHOST.LAST-MIN !
    DUP _AHM-HOST @ AHOST.FOCUS @ = IF
        0 _AHM-HOST @ AHOST.FOCUS !
        _AHM-HOST @ _AHOST-AUTOFOCUS
    THEN
    DROP _AHM-HOST @ _AHOST-RELAYOUT ;

: AHOST-RESTORE  ( host -- )
    DUP AHOST.LAST-MIN @ DUP 0= IF 2DROP EXIT THEN
    DUP AHS.STATE @ AHS-S-MINIMIZED <> IF 2DROP EXIT THEN
    AHS-S-RUNNING OVER AHS.STATE !
    0 2 PICK AHOST.LAST-MIN !
    OVER AHOST.FOCUS @ 0= IF
        AHS-S-FOCUSED OVER AHS.STATE !
        DUP 2 PICK AHOST.FOCUS !
    THEN
    DROP _AHOST-RELAYOUT ;

\ =====================================================================
\  Child event, tick, and paint dispatch
\ =====================================================================

VARIABLE _AHT-ROW
VARIABLE _AHT-COL
VARIABLE _AHT-HOST
VARIABLE _AHT-RR
VARIABLE _AHT-RC
VARIABLE _AHT-RH
VARIABLE _AHT-RW

: AHOST-TILE-AT  ( row col host -- slot | 0 )
    _AHT-HOST ! _AHT-COL ! _AHT-ROW !
    _AHT-HOST @ AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP AHS-VISIBLE? IF
            DUP AHS.RGN @ ?DUP IF
                DUP RGN-ROW _AHT-RR ! DUP RGN-COL _AHT-RC !
                DUP RGN-H _AHT-RH ! RGN-W _AHT-RW !
                _AHT-RR @ _AHT-ROW @ <=
                _AHT-RC @ _AHT-COL @ <= AND
                _AHT-RR @ _AHT-RH @ + _AHT-ROW @ > AND
                _AHT-RC @ _AHT-RW @ + _AHT-COL @ > AND IF EXIT THEN
            THEN
        THEN
        AHS.NEXT @
    REPEAT
    0 ;

VARIABLE _AHMO-EV
VARIABLE _AHMO-HOST
VARIABLE _AHMO-SLOT
VARIABLE _AHMO-FOCUS-CHANGED

: AHOST-DISPATCH-MOUSE  ( event host -- handled? )
    _AHMO-HOST ! _AHMO-EV ! 0 _AHMO-FOCUS-CHANGED !
    _AHMO-EV @ ASHELL-MOUSE-ROW _AHMO-EV @ ASHELL-MOUSE-COL
        _AHMO-HOST @ AHOST-TILE-AT DUP 0= IF DROP 0 EXIT THEN
    _AHMO-SLOT !
    _AHMO-EV @ ASHELL-MOUSE-BTN KEY-MOUSE-LEFT = IF
        _AHMO-SLOT @ _AHMO-HOST @ AHOST.FOCUS @ <> IF
            -1 _AHMO-FOCUS-CHANGED !
        THEN
        _AHMO-SLOT @ AHS.ID @ _AHMO-HOST @ AHOST-FOCUS-ID
    THEN
    _AHMO-SLOT @ AHS.HAS-UIDL @ IF
        _AHMO-SLOT @ AHS-CTX-SWITCH
        _AHMO-EV @ ASHELL-MOUSE-ROW _AHMO-EV @ ASHELL-MOUSE-COL
        _AHMO-EV @ ASHELL-MOUSE-BTN UTUI-DISPATCH-MOUSE IF
            -1 _AHMO-SLOT @ AHS.DIRTY ! -1 EXIT
        THEN
    THEN
    _AHMO-FOCUS-CHANGED @ ;

VARIABLE _AHE-EV
VARIABLE _AHE-HOST
VARIABLE _AHE-SLOT

: AHOST-DISPATCH-KEY  ( event host -- handled? )
    _AHE-HOST ! _AHE-EV !
    _AHE-HOST @ AHOST.FOCUS @ ?DUP 0= IF 0 EXIT THEN _AHE-SLOT !
    _AHE-SLOT @ AHS.HAS-UIDL @ IF _AHE-SLOT @ AHS-CTX-SWITCH THEN
    _AHE-SLOT @ AHS.DESC @ ?DUP IF
        APP.EVENT-XT @ ?DUP IF
            _AHE-EV @ _AHE-SLOT @ AHS.INST @ ROT EXECUTE
            ASHELL-QUIT-PENDING? IF
                DROP ASHELL-CANCEL-QUIT
                _AHE-SLOT @ AHS.ID @ APP-CLOSE-R-QUIT _AHE-HOST @
                    AHOST-REQUEST-CLOSE-ID DROP
                -1 EXIT
            THEN
            IF
                -1 _AHE-SLOT @ AHS.DIRTY ! ASHELL-DIRTY! -1 EXIT
            THEN
        THEN
    THEN
    _AHE-SLOT @ AHS.HAS-UIDL @ IF
        _AHE-EV @ UTUI-DISPATCH-KEY IF
            -1 _AHE-SLOT @ AHS.DIRTY ! ASHELL-DIRTY! -1 EXIT
        THEN
    THEN
    0 ;

: AHOST-MARK-ALL  ( host -- )
    AHOST.HEAD @
    BEGIN ?DUP WHILE -1 OVER AHS.DIRTY ! AHS.NEXT @ REPEAT ;

VARIABLE _AHTI-HOST

: AHOST-TICK  ( host -- )
    _AHTI-HOST ! _AHTI-HOST @ AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP AHS-ALIVE? IF
            DUP >R
            R@ AHS.INST @ CINST.REVISION @ R@ AHS.SEEN-REV @ <> IF
                -1 R@ AHS.DIRTY !
            THEN
            R@ AHS.DIRTY @
            R@ AHS.DESC @ APP.FLAGS @ APP-F-TICK-WHEN-CLEAN AND OR IF
                R@ AHS.HAS-UIDL @ IF R@ AHS-CTX-SWITCH THEN
                R@ AHS-ACTIVATE
                R@ AHS.DESC @ APP.TICK-XT @ ?DUP IF
                    R@ AHS.INST @ SWAP EXECUTE
                THEN
            THEN
            R> DROP
        THEN
        AHS.NEXT @
    REPEAT ;

VARIABLE _AHP-HOST
VARIABLE _AHP-PAINT-ALL
VARIABLE _AHP-FULLFRAME

: AHOST-PAINT  ( paint-all fullframe host -- )
    _AHP-HOST ! _AHP-FULLFRAME ! _AHP-PAINT-ALL !
    _AHP-HOST @ AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP AHS-VISIBLE? IF
            _AHP-FULLFRAME @ IF
                DUP _AHP-HOST @ AHOST.FOCUS @ <>
            ELSE
                0
            THEN
            0= IF
                DUP AHS.DIRTY @ _AHP-PAINT-ALL @ OR IF
                    DUP AHS.RGN @ IF
                        DUP AHS.UCTX @ OVER AHS.RGN @
                        2 PICK AHS.HAS-UIDL @ 3 PICK AHS.DESC @
                        4 PICK AHS.INST @ ASHELL-PAINT-CHILD
                        DUP AHS.INST @ CINST.REVISION @ OVER AHS.SEEN-REV !
                        0 OVER AHS.DIRTY !
                    THEN
                THEN
            THEN
        THEN
        AHS.NEXT @
    REPEAT ;
