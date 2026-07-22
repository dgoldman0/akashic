\ =====================================================================
\  view.f - Library drawing and direct panel input
\ =====================================================================
\  Rendering and panel interaction over controller-owned activation state.
\  L12-DELETION: direct _LAPP-* state reach is the bounded pre-virtual-list
\  view/controller seam. L12 replaces it with the settled paged item-source
\  and view-model boundary after functional parity, then deletes this reach.
\ =====================================================================

PROVIDED akashic-tui-library-view

REQUIRE controller.f

\ =====================================================================
\  Drawing and direct panel input
\ =====================================================================

VARIABLE _LAPP-PFX-A
VARIABLE _LAPP-PFX-U
VARIABLE _LAPP-PFX-START
VARIABLE _LAPP-PFX-MAX
VARIABLE _LAPP-PFX-N

: _LAPP-UTF8-PREFIX  ( a u max-cells -- a u-prefix )
    _LAPP-PFX-MAX ! _LAPP-PFX-U ! DUP _LAPP-PFX-A ! _LAPP-PFX-START !
    0 _LAPP-PFX-N !
    BEGIN
        _LAPP-PFX-U @ 0> _LAPP-PFX-N @ _LAPP-PFX-MAX @ < AND
    WHILE
        _LAPP-PFX-A @ _LAPP-PFX-U @ UTF8-DECODE
        _LAPP-PFX-U ! _LAPP-PFX-A ! DROP
        1 _LAPP-PFX-N +!
    REPEAT
    _LAPP-PFX-START @ _LAPP-PFX-A @ _LAPP-PFX-START @ - ;

VARIABLE _LAPP-DW
VARIABLE _LAPP-DH
VARIABLE _LAPP-LIST-W
VARIABLE _LAPP-DRAW-ROW
VARIABLE _LAPP-DRAW-ITEM
VARIABLE _LAPP-DRAW-MAX

: _LAPP-DRAW-HEADER  ( -- )
    255 24 1 DRW-STYLE!
    S" LIBRARY" 0 1 DRW-TEXT
    250 24 0 DRW-STYLE!
    _LAPP-VIEW$ 0 11 DRW-TEXT
    _LAPP-TERM-U @ IF
        S" Search: " 1 1 DRW-TEXT
        _LAPP-TERM _LAPP-TERM-U @
            _LAPP-DW @ 10 - 1 MAX _LAPP-UTF8-PREFIX
            1 9 DRW-TEXT-UNTRUSTED
    ELSE _LAPP-FILTER-ACTIVE @ IF
        S" Filtered by selected collection" 1 1 DRW-TEXT
    ELSE
        S" / search   n new   c collections   h history" 1 1 DRW-TEXT
    THEN THEN
    239 234 0 DRW-STYLE!
    9472 2 0 _LAPP-DW @ DRW-HLINE ;

: _LAPP-ROW-TITLE$  ( index -- a u )
    _LAPP-VIEW @ _LAPP-V-COLLECTIONS = IF
        _LAPP-COLLECTION-ROW LIBCS-TITLE$ EXIT
    THEN
    _LAPP-VIEW @ _LAPP-V-HISTORY = IF
        DROP _LAPP-ENTRY LIBE-TITLE$ EXIT
    THEN
    _LAPP-CORPUS-ROW LIBQS-TITLE$ ;

: _LAPP-DRAW-ROW-PREFIX  ( index row -- )
    _LAPP-DRAW-ROW ! _LAPP-DRAW-ITEM !
    _LAPP-DRAW-ITEM @ _LAPP-SELECTED @ = IF
        255 25 CELL-A-REVERSE
    ELSE
        253 234 0
    THEN DRW-STYLE!
    _LAPP-VIEW @ _LAPP-V-HISTORY = IF
        _LAPP-DRAW-ITEM @ _LAPP-HISTORY-ROW
            LIBRS.CONTENT-REVISION @ NUM>STR
            _LAPP-DRAW-ROW @ 2 DRW-TEXT
        S" rev" _LAPP-DRAW-ROW @ 7 DRW-TEXT
        _LAPP-DRAW-ITEM @ _LAPP-HISTORY-ROW LIBRS.CONTENT-U @ NUM>STR
            _LAPP-DRAW-ROW @ 12 DRW-TEXT
        S" bytes" _LAPP-DRAW-ROW @ 19 DRW-TEXT
        EXIT
    THEN
    _LAPP-VIEW @ _LAPP-V-COLLECTIONS = IF
        [CHAR] C _LAPP-DRAW-ROW @ 1 DRW-CHAR
        _LAPP-DRAW-ITEM @ _LAPP-COLLECTION-ROW LIBCS.MEMBER-N @ NUM>STR
            _LAPP-DRAW-ROW @ _LAPP-LIST-W @ 6 - 2 MAX DRW-TEXT
    ELSE
        _LAPP-DRAW-ITEM @ _LAPP-CORPUS-ROW LIBQS.KIND @
            LIB-KIND-MANAGED-DOCUMENT = IF [CHAR] M ELSE [CHAR] C THEN
            _LAPP-DRAW-ROW @ 1 DRW-CHAR
        _LAPP-DRAW-ITEM @ _LAPP-CORPUS-ROW LIBQS.LIFECYCLE @
            LIB-LIFECYCLE-ARCHIVED = IF
            [CHAR] A _LAPP-DRAW-ROW @ 3 DRW-CHAR
        THEN
    THEN
    _LAPP-DRAW-ITEM @ _LAPP-ROW-TITLE$
        _LAPP-VIEW @ _LAPP-V-COLLECTIONS = IF
            _LAPP-LIST-W @ 13 -
        ELSE
            _LAPP-LIST-W @ 7 -
        THEN
        1 MAX _LAPP-UTF8-PREFIX
        _LAPP-DRAW-ROW @ 5 DRW-TEXT-UNTRUSTED ;

: _LAPP-DRAW-LIST  ( -- )
    253 234 0 DRW-STYLE!
    32 3 0 _LAPP-DH @ 3 - _LAPP-LIST-W @ DRW-FILL-RECT
    _LAPP-ROW-COUNT @ 0= IF
        244 234 CELL-A-DIM DRW-STYLE!
        _LAPP-LAST-STATUS @ LIBSTORE-S-ABSENT = IF
            S" No store yet; create initializes it"
        ELSE
            S" No matching Library records"
        THEN
        4 2 DRW-TEXT EXIT
    THEN
    _LAPP-DH @ 4 - 1 MAX _LAPP-DRAW-MAX !
    _LAPP-SELECTED @ _LAPP-LIST-SCROLL @ < IF
        _LAPP-SELECTED @ _LAPP-LIST-SCROLL !
    THEN
    _LAPP-SELECTED @
        _LAPP-LIST-SCROLL @ _LAPP-DRAW-MAX @ + >= IF
        _LAPP-SELECTED @ _LAPP-DRAW-MAX @ - 1+
            _LAPP-LIST-SCROLL !
    THEN
    _LAPP-DRAW-MAX @ 0 ?DO
        _LAPP-LIST-SCROLL @ I + DUP _LAPP-ROW-COUNT @ < IF
            3 I + _LAPP-DRAW-ROW-PREFIX
        ELSE DROP THEN
    LOOP ;

VARIABLE _LAPP-PV-COL
VARIABLE _LAPP-PV-W
VARIABLE _LAPP-PV-ROW
VARIABLE _LAPP-PV-A
VARIABLE _LAPP-PV-U
VARIABLE _LAPP-PV-LINE-A
VARIABLE _LAPP-PV-LINE-U
VARIABLE _LAPP-PV-NEXT-A
VARIABLE _LAPP-PV-NEXT-U
VARIABLE _LAPP-PV-SKIP
VARIABLE _LAPP-PV-CP

: _LAPP-NEXT-WRAPPED-LINE  ( -- )
    _LAPP-PV-A @ _LAPP-PV-LINE-A !
    0 _LAPP-PV-LINE-U ! 0 _LAPP-PV-CP !
    BEGIN
        _LAPP-PV-U @ 0>
        _LAPP-PV-CP @ _LAPP-PV-W @ < AND
        IF _LAPP-PV-A @ C@ 10 <> ELSE 0 THEN
    WHILE
        _LAPP-PV-A @ _LAPP-PV-U @ UTF8-DECODE
        _LAPP-PV-U ! _LAPP-PV-A ! DROP
        1 _LAPP-PV-CP +!
    REPEAT
    _LAPP-PV-A @ _LAPP-PV-LINE-A @ - _LAPP-PV-LINE-U !
    _LAPP-PV-U @ IF
        _LAPP-PV-A @ C@ 10 = IF
            1 _LAPP-PV-A +! -1 _LAPP-PV-U +!
        THEN
    THEN
    _LAPP-PV-A @ _LAPP-PV-NEXT-A !
    _LAPP-PV-U @ _LAPP-PV-NEXT-U ! ;

: _LAPP-DRAW-CONTENT-LINES  ( row -- )
    _LAPP-PV-ROW !
    _LAPP-PREVIEW-BYTES _LAPP-PV-A !
    _LAPP-PREVIEW-U @ _LAPP-PV-U !
    _LAPP-PREVIEW-SCROLL @ _LAPP-PV-SKIP !
    BEGIN _LAPP-PV-SKIP @ 0> _LAPP-PV-U @ 0> AND WHILE
        _LAPP-NEXT-WRAPPED-LINE
        _LAPP-PV-NEXT-A @ _LAPP-PV-A !
        _LAPP-PV-NEXT-U @ _LAPP-PV-U !
        -1 _LAPP-PV-SKIP +!
    REPEAT
    BEGIN _LAPP-PV-U @ 0> _LAPP-PV-ROW @ _LAPP-DH @ < AND WHILE
        _LAPP-NEXT-WRAPPED-LINE
        _LAPP-PV-LINE-A @ _LAPP-PV-LINE-U @
            _LAPP-PV-ROW @ _LAPP-PV-COL @ DRW-TEXT-UNTRUSTED
        _LAPP-PV-NEXT-A @ _LAPP-PV-A !
        _LAPP-PV-NEXT-U @ _LAPP-PV-U !
        1 _LAPP-PV-ROW +!
    REPEAT ;

: _LAPP-DRAW-PREVIEW  ( -- )
    _LAPP-DW @ _LAPP-LIST-W @ <= IF EXIT THEN
    _LAPP-LIST-W @ 1+ _LAPP-PV-COL !
    _LAPP-DW @ _LAPP-PV-COL @ - 1- _LAPP-PV-W !
    239 234 0 DRW-STYLE!
    9474 3 _LAPP-LIST-W @ _LAPP-DH @ 3 - DRW-VLINE
    253 234 0 DRW-STYLE!
    32 3 _LAPP-PV-COL @ _LAPP-DH @ 3 - _LAPP-PV-W @ DRW-FILL-RECT
    _LAPP-PREVIEW-READY @ 0= IF
        244 234 CELL-A-DIM DRW-STYLE!
        S" Select a readable item" 4 _LAPP-PV-COL @ 1+ DRW-TEXT EXIT
    THEN
    255 234 1 DRW-STYLE!
    _LAPP-VIEW @ _LAPP-V-COLLECTIONS = IF
        _LAPP-COLLECTION-VIEW LIBCV-TITLE$
    ELSE
        _LAPP-ENTRY LIBE-TITLE$
    THEN
    _LAPP-PV-W @ 2 - 1 MAX _LAPP-UTF8-PREFIX
        3 _LAPP-PV-COL @ 1+ DRW-TEXT-UNTRUSTED
    244 234 0 DRW-STYLE!
    _LAPP-VIEW @ _LAPP-V-COLLECTIONS = IF
        S" Collection  |  members " 4 _LAPP-PV-COL @ 1+ DRW-TEXT
        _LAPP-COLLECTION-VIEW LIBCV.MEMBER-N @ NUM>STR
            4 _LAPP-PV-COL @ 25 + DRW-TEXT
        S" Enter filters the corpus by this collection"
            6 _LAPP-PV-COL @ 1+ DRW-TEXT
        EXIT
    THEN
    _LAPP-VIEW @ _LAPP-V-HISTORY = IF
        S" Retained content version" 4 _LAPP-PV-COL @ 1+ DRW-TEXT
    ELSE
        _LAPP-ENTRY LIBE.KIND @ LIB-KIND-MANAGED-DOCUMENT = IF
            S" Managed document"
        ELSE S" Immutable capture" THEN
        4 _LAPP-PV-COL @ 1+ DRW-TEXT
    THEN
    S" bytes " 5 _LAPP-PV-COL @ 1+ DRW-TEXT
    _LAPP-PREVIEW-U @ NUM>STR 5 _LAPP-PV-COL @ 7 + DRW-TEXT
    253 234 0 DRW-STYLE!
    7 _LAPP-DRAW-CONTENT-LINES ;

: _LAPP-PANEL-DRAW  ( widget -- )
    DUP WDG-REGION RGN-W _LAPP-DW !
    WDG-REGION RGN-H _LAPP-DH !
    _LAPP-DH @ 3 < IF EXIT THEN
    _LAPP-DW @ 70 >= IF
        _LAPP-DW @ 3 / 28 MAX 44 MIN _LAPP-LIST-W !
    ELSE
        _LAPP-DW @ _LAPP-LIST-W !
    THEN
    253 234 0 DRW-STYLE!
    32 0 0 _LAPP-DH @ _LAPP-DW @ DRW-FILL-RECT
    _LAPP-DRAW-HEADER _LAPP-DRAW-LIST _LAPP-DRAW-PREVIEW
    DRW-STYLE-RESET ;

: _LAPP-SELECT-MOVE  ( delta -- )
    _LAPP-ROW-COUNT @ 0= IF DROP EXIT THEN
    _LAPP-SELECTED @ + 0 MAX _LAPP-ROW-COUNT @ 1- MIN
        _LAPP-SELECTED !
    0 _LAPP-PREVIEW-SCROLL !
    _LAPP-LOAD-SELECTION DROP _LAPP-INVALIDATE ;

: _LAPP-ACTIVATE-SELECTION  ( -- )
    _LAPP-VIEW @ _LAPP-V-COLLECTIONS = IF
        _LAPP-FILTER-COLLECTION DROP _LAPP-INVALIDATE EXIT
    THEN
    _LAPP-VIEW @ _LAPP-V-HISTORY = IF
        _LAPP-LOAD-HISTORY-PREVIEW DROP _LAPP-INVALIDATE EXIT
    THEN
    _LAPP-LOAD-CORPUS-PREVIEW DROP _LAPP-INVALIDATE ;

: _LAPP-PREVIEW-SCROLL-BY  ( delta -- )
    _LAPP-PREVIEW-SCROLL @ + 0 MAX _LAPP-PREVIEW-SCROLL !
    _LAPP-INVALIDATE ;

: _LAPP-PANEL-HANDLE  ( event widget -- consumed? )
    DROP
    DUP @ KEY-T-SPECIAL = IF
        DUP 16 + @ KEY-MOD-SHIFT AND IF
            DUP 8 + @ CASE
                KEY-UP OF DROP -8 _LAPP-PREVIEW-SCROLL-BY -1 EXIT ENDOF
                KEY-DOWN OF DROP 8 _LAPP-PREVIEW-SCROLL-BY -1 EXIT ENDOF
            ENDCASE
        THEN
        8 + @ CASE
            KEY-UP OF -1 _LAPP-SELECT-MOVE -1 EXIT ENDOF
            KEY-DOWN OF 1 _LAPP-SELECT-MOVE -1 EXIT ENDOF
            KEY-PGUP OF 0 _LAPP-DO-PREVIOUS-PAGE -1 EXIT ENDOF
            KEY-PGDN OF 0 _LAPP-DO-NEXT-PAGE -1 EXIT ENDOF
            KEY-HOME OF 0 _LAPP-SELECTED ! _LAPP-LOAD-SELECTION DROP
                _LAPP-INVALIDATE -1 EXIT ENDOF
            KEY-END OF _LAPP-ROW-COUNT @ 1- 0 MAX _LAPP-SELECTED !
                _LAPP-LOAD-SELECTION DROP _LAPP-INVALIDATE -1 EXIT ENDOF
            KEY-LEFT OF 0 _LAPP-DO-PREVIOUS-PAGE -1 EXIT ENDOF
            KEY-RIGHT OF 0 _LAPP-DO-NEXT-PAGE -1 EXIT ENDOF
            KEY-ENTER OF _LAPP-ACTIVATE-SELECTION -1 EXIT ENDOF
            KEY-ESC OF 0 _LAPP-DO-BACK -1 EXIT ENDOF
        ENDCASE
        0 EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
        DUP 16 + @ 0= IF
            8 + @ CASE
                [CHAR] / OF 0 _LAPP-DO-SEARCH -1 EXIT ENDOF
                [CHAR] n OF 0 _LAPP-DO-NEW-MANAGED -1 EXIT ENDOF
                [CHAR] r OF 0 _LAPP-DO-RENAME -1 EXIT ENDOF
                [CHAR] a OF 0 _LAPP-DO-ARCHIVE -1 EXIT ENDOF
                [CHAR] u OF 0 _LAPP-DO-UNARCHIVE -1 EXIT ENDOF
                [CHAR] c OF 0 _LAPP-DO-COLLECTIONS -1 EXIT ENDOF
                [CHAR] h OF 0 _LAPP-DO-HISTORY -1 EXIT ENDOF
                [CHAR] b OF 0 _LAPP-DO-BACK -1 EXIT ENDOF
            ENDCASE
            0 EXIT
        THEN
    THEN
    DROP 0 ;

: _LAPP-PANEL-INIT  ( region -- )
    DUP _LAPP-PANEL-RGN !
    _LAPP-PANEL 30 ROT
    ['] _LAPP-PANEL-DRAW ['] _LAPP-PANEL-HANDLE WDG-INIT ;
