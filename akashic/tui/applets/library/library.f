\ =====================================================================
\  library.f - Library applet lifecycle and composition entry
\ =====================================================================
\  Public applet descriptor callbacks compose the controller and view.
\  Entry: LIBRARY-APPLET-ENTRY / LIBRARY-APPLET-RUN.
\  L12-DELETION: lifecycle callbacks directly reach _LAPP-* controller/view
\  internals as bounded scaffolding. L12 replaces this with their settled
\  applet-owned lifecycle interface after parity and deletes the private reach.
\ =====================================================================

PROVIDED akashic-tui-library

REQUIRE view.f

\ =====================================================================
\  Applet lifecycle and descriptor
\ =====================================================================

: _LAPP-BIND-ACTIONS  ( -- )
    S" reload" ['] _LAPP-DO-RELOAD UTUI-DO!
    S" search" ['] _LAPP-DO-SEARCH UTUI-DO!
    S" clear-search" ['] _LAPP-DO-CLEAR-SEARCH UTUI-DO!
    S" show-active" ['] _LAPP-DO-SHOW-ACTIVE UTUI-DO!
    S" show-archived" ['] _LAPP-DO-SHOW-ARCHIVED UTUI-DO!
    S" show-all" ['] _LAPP-DO-SHOW-ALL UTUI-DO!
    S" collections" ['] _LAPP-DO-COLLECTIONS UTUI-DO!
    S" history" ['] _LAPP-DO-HISTORY UTUI-DO!
    S" back" ['] _LAPP-DO-BACK UTUI-DO!
    S" new-managed" ['] _LAPP-DO-NEW-MANAGED UTUI-DO!
    S" rename-title" ['] _LAPP-DO-RENAME UTUI-DO!
    S" archive" ['] _LAPP-DO-ARCHIVE UTUI-DO!
    S" unarchive" ['] _LAPP-DO-UNARCHIVE UTUI-DO!
    S" next-page" ['] _LAPP-DO-NEXT-PAGE UTUI-DO!
    S" previous-page" ['] _LAPP-DO-PREVIOUS-PAGE UTUI-DO!
    S" retry-create" ['] _LAPP-DO-RETRY-CREATE UTUI-DO!
    S" quit" ['] _LAPP-DO-QUIT UTUI-DO!
    S" about" ['] _LAPP-DO-ABOUT UTUI-DO! ;

: LIBRARY-APPLET-INIT-CB  ( instance -- )
    _LAPP-ACTIVATE
    0 _LAPP-OWNS-LIVE ! 0 _LAPP-STORE-INITIALIZED ! 0 _LAPP-READY !
    0 _LAPP-PREVIEW-BUFFER !
    LIBSTORE-S-ABSENT _LAPP-LAST-STATUS !
    _LAPP-V-ACTIVE _LAPP-VIEW ! _LAPP-V-ACTIVE _LAPP-RETURN-VIEW !
    0 _LAPP-PROMPT ! 0 _LAPP-PROMPT-RGN !
    _LAPP-PRM-NONE _LAPP-PROMPT-MODE !
    0 _LAPP-PENDING-CREATE ! 0 _LAPP-DISCARD-ARMED !
    0 _LAPP-FILTER-ACTIVE ! 0 _LAPP-TERM-U !
    _LAPP-ENTRY LIB-ENTRY-INIT
    _LAPP-CONTENT LIB-CONTENT-INIT
    _LAPP-COLLECTION-VIEW LIBRARY-COLLECTION-VIEW-INIT
    LIB-CONTENT-MAX XMEM-ALLOT? IF
        DROP LIBSTORE-S-ALLOCATION _LAPP-LAST-STATUS !
    ELSE
        _LAPP-PREVIEW-BUFFER !
    THEN
    _LAPP-ARENA-ID!
    S" library-body" UTUI-BY-ID _LAPP-E-BODY !
    S" sbar" UTUI-BY-ID _LAPP-E-SBAR !
    S" sbar-view" UTUI-BY-ID _LAPP-E-SBAR-VIEW !
    S" sbar-page" UTUI-BY-ID _LAPP-E-SBAR-PAGE !
    S" sbar-state" UTUI-BY-ID _LAPP-E-SBAR-STATE !
    _LAPP-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW DUP _LAPP-PROMPT-RGN !
        _LAPP-PROMPT-BUF _LAPP-PROMPT-CAP PRM-NEW DUP _LAPP-PROMPT !
        ['] _LAPP-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
        ['] _LAPP-PROMPT-CANCEL OVER PRM-ON-CANCEL
        15 23 ROT PRM-COLORS!
    THEN
    _LAPP-E-BODY @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW _LAPP-PANEL-INIT
        _LAPP-PANEL _LAPP-E-BODY @ UTUI-WIDGET-SET
    THEN
    _LAPP-BIND-ACTIONS
    _LAPP-CLEAR-PAGES _LAPP-CLEAR-PREVIEW
    _LAPP-PREVIEW-BUFFER @ 0= IF
        \ The UI remains available to report the allocation failure, but no
        \ owner operation runs without its exact-read output buffer.
    ELSE _LAPP-LIVE-INSTANCE @ IF
        LIBSTORE-S-BUSY _LAPP-LAST-STATUS !
    ELSE
        _LAPP-CURRENT-INSTANCE @ _LAPP-LIVE-INSTANCE !
        -1 _LAPP-OWNS-LIVE !
        _LAPP-OWNER-OPEN DROP
        _LAPP-READY? IF _LAPP-RESET-PAGE DROP THEN
    THEN THEN
    _LAPP-FOCUS-BODY _LAPP-INVALIDATE ;

: LIBRARY-APPLET-EVENT-CB  ( event instance -- consumed? )
    _LAPP-ACTIVATE
    _LAPP-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    _UTUI-MENU-OPEN @ IF DROP 0 EXIT THEN
    _LAPP-PANEL WDG-HANDLE ;

: LIBRARY-APPLET-PAINT-CB  ( instance -- )
    _LAPP-ACTIVATE
    _LAPP-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN DROP
    _LAPP-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN _LAPP-PROMPT @ PRM-SET-BOUNDS
    THEN
    _LAPP-PROMPT @ WDG-DRAW ;

: LIBRARY-APPLET-REQUEST-CLOSE-CB  ( reason instance -- decision )
    SWAP DROP _LAPP-ACTIVATE
    _LAPP-DISCARD-ARMED @ IF
        0 _LAPP-DISCARD-ARMED ! APP-CLOSE-D-ALLOW EXIT
    THEN
    _LAPP-PENDING-CREATE @ IF
        _LAPP-PROMPT @ 0= IF APP-CLOSE-D-CANCEL EXIT THEN
        _LAPP-PRM-DISCARD-PENDING
        S" Type DISCARD to abandon the pending operation:"
        0 0 _LAPP-SHOW-PROMPT
        APP-CLOSE-D-DEFER EXIT
    THEN
    _LAPP-PROMPT @ ?DUP IF
        PRM-ACTIVE? IF
            S" Finish or cancel the current Library prompt" 2200
                ASHELL-TOAST
            APP-CLOSE-D-CANCEL EXIT
        THEN
    THEN
    APP-CLOSE-D-ALLOW ;

: LIBRARY-APPLET-SHUTDOWN-CB  ( instance -- )
    _LAPP-ACTIVATE
    _LAPP-E-BODY @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _LAPP-PROMPT @ ?DUP IF PRM-FREE THEN
    _LAPP-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _LAPP-PANEL-RGN @ ?DUP IF RGN-FREE THEN
    _LAPP-STORE-INITIALIZED @ IF
        _LAPP-STORE LIBRARY-VFS-STORE-FINI DROP
    THEN
    _LAPP-PREVIEW-BYTES ?DUP IF
        DUP LIB-CONTENT-MAX 0 FILL
        LIB-CONTENT-MAX XMEM-FREE-BLOCK
        0 _LAPP-PREVIEW-BUFFER !
    THEN
    _LAPP-CLEAR-PENDING
    _LAPP-PROMPT-BUF _LAPP-PROMPT-CAP 0 FILL
    _LAPP-OWNS-LIVE @ IF
        _LAPP-LIVE-INSTANCE @ _LAPP-CURRENT-INSTANCE @ = IF
            0 _LAPP-LIVE-INSTANCE !
        THEN
    THEN
    _LAPP-CURRENT-STATE @ _LAPP-STATE-SIZE 0 FILL ;

CREATE LIBRARY-APPLET-COMP-DESC COMP-DESC ALLOT

: _LIBRARY-APPLET-COMP-SETUP  ( -- )
    LIBRARY-APPLET-COMP-DESC COMP-DESC-INIT
    S" org.akashic.library.applet"
    LIBRARY-APPLET-COMP-DESC COMP.ID-U !
    LIBRARY-APPLET-COMP-DESC COMP.ID-A !
    S" 0.1.0"
    LIBRARY-APPLET-COMP-DESC COMP.VERSION-U !
    LIBRARY-APPLET-COMP-DESC COMP.VERSION-A !
    _LAPP-STATE-SIZE LIBRARY-APPLET-COMP-DESC COMP.STATE-SIZE ! ;

: LIBRARY-APPLET-ENTRY  ( desc -- )
    _LIBRARY-APPLET-COMP-SETUP
    DUP APP-DESC-INIT
    LIBRARY-APPLET-COMP-DESC OVER APP.COMP-DESC !
    ['] LIBRARY-APPLET-INIT-CB OVER APP.INIT-XT !
    ['] LIBRARY-APPLET-EVENT-CB OVER APP.EVENT-XT !
    ['] LIBRARY-APPLET-PAINT-CB OVER APP.PAINT-XT !
    ['] LIBRARY-APPLET-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _LAPP-ACTIVATE OVER APP.ACTIVATE-XT !
    ['] LIBRARY-APPLET-REQUEST-CLOSE-CB OVER APP.REQUEST-CLOSE-XT !
    S" tui/applets/library/library.uidl"
    ROT DUP >R APP.UIDL-FILE-U ! R@ APP.UIDL-FILE-A !
    0 R@ APP.WIDTH ! 0 R@ APP.HEIGHT !
    S" Library" R@ APP.TITLE-U ! R> APP.TITLE-A ! ;

CREATE LIBRARY-APPLET-DESC APP-DESC ALLOT

: LIBRARY-APPLET-RUN  ( -- )
    LIBRARY-APPLET-DESC LIBRARY-APPLET-ENTRY
    LIBRARY-APPLET-DESC ASHELL-RUN ;
