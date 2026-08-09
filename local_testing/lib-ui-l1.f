\ =====================================================================
\  Library Landing 1 visible-key regression
\ =====================================================================
\  Drive real key-event descriptors through the live ASHELL/UIDL route,
\  repaint the terminal surface, and verify Library's prompt, collection,
\  and status-row transitions from SCR-GET rather than controller state.
\ =====================================================================

VARIABLE _lui-fails
VARIABLE _lui-checks
VARIABLE _lui-depth
VARIABLE _lui-outer-depth
VARIABLE _lui-ran

CREATE _lui-desc APP-DESC ALLOT
CREATE _lui-event 24 ALLOT

VARIABLE _lui-event-type
VARIABLE _lui-event-code
VARIABLE _lui-event-mods

VARIABLE _lui-find-a
VARIABLE _lui-find-u
VARIABLE _lui-find-row
VARIABLE _lui-find-col

: _lui-assert  ( flag -- )
    1 _lui-checks +!
    0= IF
        1 _lui-fails +!
        ." LIBRARY UI L1 ASSERT " _lui-checks @ . CR
    THEN ;

: _lui-stack  ( -- )
    DEPTH DUP _lui-depth @ <> IF
        ." LIBRARY UI L1 STACK " _lui-depth @ . ." -> " DUP . CR .S CR
    THEN
    _lui-depth @ = _lui-assert ;

: _lui-send-event  ( type code mods -- )
    _lui-event-mods ! _lui-event-code ! _lui-event-type !
    _lui-event _lui-event-type @ _lui-event-code @ _lui-event-mods @
        _KEY-SET-EV
    _lui-event _ASHELL-DISPATCH-KEY ;

: _lui-send-char  ( codepoint -- )
    KEY-T-CHAR SWAP 0 _lui-send-event ;

: _lui-send-special  ( keycode -- )
    KEY-T-SPECIAL SWAP 0 _lui-send-event ;

: _lui-type-ascii  ( address length -- )
    OVER + SWAP ?DO I C@ _lui-send-char LOOP ;

: _lui-screen-at?  ( row col -- flag )
    _lui-find-col ! _lui-find-row !
    _lui-find-u @ 0 ?DO
        _lui-find-row @ _lui-find-col @ I + SCR-GET CELL-CP@
        _lui-find-a @ I + C@ <> IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _lui-screen-has?  ( address length -- flag )
    _lui-find-u ! _lui-find-a !
    _lui-find-u @ 0= IF -1 EXIT THEN
    _lui-find-u @ SCR-W > IF 0 EXIT THEN
    SCR-H 0 ?DO
        SCR-W _lui-find-u @ - 1+ 0 ?DO
            J I _lui-screen-at? IF -1 UNLOOP UNLOOP EXIT THEN
        LOOP
    LOOP
    0 ;

: _lui-row-has?  ( address length row -- flag )
    _lui-find-row ! _lui-find-u ! _lui-find-a !
    _lui-find-u @ 0= IF -1 EXIT THEN
    _lui-find-row @ 0< IF 0 EXIT THEN
    _lui-find-row @ SCR-H >= IF 0 EXIT THEN
    _lui-find-u @ SCR-W > IF 0 EXIT THEN
    SCR-W _lui-find-u @ - 1+ 0 ?DO
        _lui-find-row @ I _lui-screen-at? IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

: _lui-status-row?  ( address length -- flag )
    \ Library's UIDL occupies the app surface above the shell overlay row.
    \ Read the status element's laid-out row, then inspect the actual screen
    \ cells there; assuming SCR-H-1 confuses app and shell geometry.
    _LAPP-E-SBAR @ UTUI-ELEM-RGN 2DROP DROP _lui-row-has? ;

: _lui-current-status-visible?  ( -- flag )
    _LAPP-LAST-STATUS @ _LAPP-STATUS$ _lui-status-row? ;

: _lui-current-view-visible?  ( -- flag )
    _LAPP-VIEW$ _lui-status-row? ;

: _lui-paint  ( -- )
    _ASHELL-PAINT ;

: _lui-exercise  ( -- )
    DEPTH _lui-depth !
    1 _lui-ran +!

    \ The setup paint ran before this deferred action.  Confirm that the
    \ activation begins with a complete three-part status row.
    _lui-current-view-visible? _lui-assert
    S" Page 1" _lui-status-row? _lui-assert
    _lui-current-status-visible? _lui-assert

    \ Slash travels through ASHELL into Library's panel handler.  The prompt
    \ must replace the status row on the actual terminal surface.
    [CHAR] / _lui-send-char
    _lui-paint
    _LAPP-PROMPT @ PRM-ACTIVE? _lui-assert
    S" Search title, body, and tags:" _lui-status-row? _lui-assert

    \ Type and submit through the same event route.  Prompt dismissal must
    \ repaint its parent status element, while the corpus header shows the
    \ accepted search term.
    S" needle" _lui-type-ascii
    KEY-ENTER _lui-send-special
    _lui-paint
    _LAPP-PROMPT @ PRM-ACTIVE? 0= _lui-assert
    S" Search title, body, and tags:" _lui-screen-has? 0= _lui-assert
    S" Search: needle" _lui-screen-has? _lui-assert
    _lui-current-view-visible? _lui-assert
    S" Page 1" _lui-status-row? _lui-assert
    _lui-current-status-visible? _lui-assert

    \ Collections is entered by a direct `c` event.  Its empty state is
    \ explicit and no corpus-only Search header may leak into this view.
    [CHAR] c _lui-send-char
    _lui-paint
    S" No collections yet" _lui-screen-has? _lui-assert
    S" Search:" _lui-screen-has? 0= _lui-assert
    S" Collections" _lui-status-row? _lui-assert
    S" Page 1" _lui-status-row? _lui-assert
    _lui-current-status-visible? _lui-assert

    \ Back returns to the corpus.  The status-row view and rightmost state
    \ labels must both survive the transition, and the search remains shown.
    [CHAR] b _lui-send-char
    _lui-paint
    _LAPP-VIEW @ _LAPP-V-ACTIVE = _lui-assert
    S" Search: needle" _lui-screen-has? _lui-assert
    S" Active" _lui-status-row? _lui-assert
    S" Page 1" _lui-status-row? _lui-assert
    _lui-current-status-visible? _lui-assert

    _lui-stack
    ASHELL-QUIT ;

: _lui-shell-init  ( instance -- )
    LIBRARY-APPLET-INIT-CB
    ['] _lui-exercise ASHELL-POST ;

: _lui-run  ( -- )
    0 _lui-fails ! 0 _lui-checks ! 0 _lui-ran !
    DEPTH _lui-outer-depth !
    _lui-desc LIBRARY-APPLET-ENTRY
    ['] _lui-shell-init _lui-desc APP.INIT-XT !
    _lui-desc ASHELL-RUN
    _lui-ran @ 1 = _lui-assert
    _LAPP-LIVE-INSTANCE @ 0= _lui-assert
    DEPTH _lui-outer-depth @ = _lui-assert
    _lui-fails @ ?DUP IF
        ." LIBRARY UI L1 FAIL " . ." / " _lui-checks @ . CR
    ELSE
        ." LIBRARY UI L1 PASS " _lui-checks @ . CR
    THEN ;

_lui-run
