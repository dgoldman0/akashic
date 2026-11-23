\ =====================================================================
\  folio.f - Folio Watch: the night archivist keeps the folios
\ =====================================================================
\  At night the archive's reading rooms lie dark.  The archivist walks
\  them with a hand lamp that lights what it reaches, and the room
\  stays in memory where the lamp has been.  This is the game's first
\  skeleton: a room read from a text map in the applet's origin, an
\  archivist who moves a tile a turn, the fog of war, and nights saved
\  in and loaded from the applet's home.  The rules, creatures and
\  maps of a whole night come in the game's next stage.
\
\  The board is a canonical text grid (tui/game/board.f): the
\  archivist's tile is current, tiles out of the lamp's light are
\  unavailable and show what the archivist remembers, and a selected
\  tile is where the archivist walks, a step a turn.
\
\  Keys: the arrows or h j k l step, y u b n step diagonally, and . or
\  Space waits a turn; Ctrl+N starts a new night, Ctrl+S saves it,
\  Ctrl+O loads the saved one, F1 lists the keys, Ctrl+Q quits.
\
\  Entry: FOLIO-ENTRY ( desc -- )  for Desk
\         FOLIO-RUN   ( -- )       standalone
\ =====================================================================

PROVIDED akashic-tui-folio-watch

REQUIRE ../../game/board.f
REQUIRE ../../widgets/dialog.f
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../keys.f
REQUIRE ../../widget.f
REQUIRE ../../../game/map.f
REQUIRE ../../../game/save.f
REQUIRE ../../../game/2d/fog.f
REQUIRE ../../../game/2d/camera.f
REQUIRE ../../../game/2d/pathfind.f
REQUIRE ../../../utils/fs/place-replace.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/place-resource.f

\ ---------------------------------------------------------------------
\ Constants and instance state
\ ---------------------------------------------------------------------

4 CONSTANT _FW-LAMP              \ the hand lamp's radius in tiles
1 CONSTANT _FW-SAVE-VERSION
16 CONSTANT _FW-TEXT-SZ          \ a kind's text: its length, then bytes

VARIABLE _FW-CURRENT-STATE
0 _FW-CURRENT-STATE !
VARIABLE _FW-CURRENT-INSTANCE
0 _FW-CURRENT-INSTANCE !
CMP-LAYOUT-BEGIN

_FW-CURRENT-STATE CMP-CELL: _FW-E-BOARD
_FW-CURRENT-STATE CMP-CELL: _FW-E-ROOM
_FW-CURRENT-STATE CMP-CELL: _FW-E-TURN
_FW-CURRENT-STATE CMP-CELL: _FW-MAP
_FW-CURRENT-STATE CMP-CELL: _FW-FOG
_FW-CURRENT-STATE CMP-CELL: _FW-BOARD
_FW-CURRENT-STATE CMP-CELL: _FW-CAM
_FW-CURRENT-STATE CMP-CELL: _FW-SEARCH
_FW-CURRENT-STATE CMP-CELL: _FW-TEXTS       \ a text for each tile kind
_FW-CURRENT-STATE CMP-CELL: _FW-PX
_FW-CURRENT-STATE CMP-CELL: _FW-PY
_FW-CURRENT-STATE CMP-CELL: _FW-START-X
_FW-CURRENT-STATE CMP-CELL: _FW-START-Y
_FW-CURRENT-STATE CMP-CELL: _FW-TURN
_FW-CURRENT-STATE CMP-CELL: _FW-DIRTY       \ turns since the last save
\ Set when the player agreed to discard the night and close, so the close
\ the game then asks for goes ahead.
_FW-CURRENT-STATE CMP-CELL: _FW-DISCARD-ARMED
_FW-CURRENT-STATE VREPL-SIZE CMP-FIELD: _FW-REPLACE
_FW-CURRENT-STATE 96 CMP-FIELD: _FW-LINE    \ the status line being built
_FW-CURRENT-STATE CMP-CELL: _FW-LINE-U

CMP-LAYOUT-SIZE CONSTANT _FW-STATE-SIZE

: _FW-ACTIVATE  ( instance -- )
    DUP _FW-CURRENT-INSTANCE !
    CINST-STATE _FW-CURRENT-STATE ! ;

\ The room every night starts in, shipped in the applet's origin
: _FW-ROOM$  ( -- a u )  S" tui/applets/folio/reading-room.map" ;
: _FW-SAVE$  ( -- a u )  S" /night.sav" ;

\ ---------------------------------------------------------------------
\ The status line
\ ---------------------------------------------------------------------

: _FW-LINE-RESET  ( -- )  0 _FW-LINE-U ! ;

: _FW-LINE+  ( a u -- )
    96 _FW-LINE-U @ - MIN 0 MAX >R
    _FW-LINE _FW-LINE-U @ + R@ CMOVE  R> _FW-LINE-U +! ;

: _FW-UPDATE-STATUS  ( -- )
    _FW-E-ROOM @ ?DUP IF
        _FW-MAP @ S" name" GMAP-VALUE 0= IF 2DROP S" Folio Watch" THEN
        2>R S" text" 2R> UTUI-SET-ATTR
    THEN
    _FW-LINE-RESET
    S" Turn " _FW-LINE+  _FW-TURN @ NUM>STR _FW-LINE+
    S"   |  " _FW-LINE+
    _FW-DIRTY @ IF S" Unsaved" ELSE S" Saved" THEN _FW-LINE+
    _FW-E-TURN @ ?DUP IF S" text" _FW-LINE _FW-LINE-U @ UTUI-SET-ATTR THEN ;

\ ---------------------------------------------------------------------
\ The board's tiles
\ ---------------------------------------------------------------------
\  Each tile kind shows its glyph twice when it bars the way, so walls
\  and desks draw solid, and its glyph and a space otherwise.

: _FW-KIND-TEXT  ( kind -- a u )
    _FW-TEXT-SZ * _FW-TEXTS @ + DUP 8 + SWAP @ ;

: _FW-TEXTS-BUILD  ( -- ior )
    _FW-MAP @ GMAP-TILES _FW-TEXT-SZ * ALLOCATE IF DROP -1 EXIT THEN
    _FW-TEXTS !
    _FW-MAP @ GMAP-TILES 0 ?DO
        I _FW-TEXT-SZ * _FW-TEXTS @ +               ( entry )
        _FW-MAP @ I GMAP-TILE-GLYPH OVER 8 + UTF8-ENCODE   ( entry end )
        _FW-MAP @ I GMAP-TILE-COLLISION IF
            _FW-MAP @ I GMAP-TILE-GLYPH SWAP UTF8-ENCODE
        ELSE
            32 OVER C! 1+
        THEN
        OVER 8 + - SWAP !
    LOOP
    0 ;

\ The board's token: the archivist's tile is current; a tile the lamp
\ does not light is unavailable, with nothing on it until seen.
: _FW-TOKEN  ( x y instance -- text-a text-u state )
    DROP
    2DUP _FW-PY @ = SWAP _FW-PX @ = AND IF
        2DROP S" @ " BOARD-CURRENT EXIT
    THEN
    2DUP _FW-FOG @ -ROT FOG-STATE                   ( x y state )
    DUP FOG-UNSEEN = IF DROP 2DROP 0 0 BOARD-UNAVAILABLE EXIT THEN
    >R _FW-MAP @ -ROT GMAP-TILE@ _FW-KIND-TEXT
    R> FOG-VISIBLE = IF 0 ELSE BOARD-UNAVAILABLE THEN ;

: _FW-REDRAW  ( -- )
    _FW-BOARD @ ?DUP 0= IF EXIT THEN
    _FW-CAM @ OVER BOARD-VIEW CAM-VIEW!
    _FW-CAM @ _FW-PX @ _FW-PY @ CAM-SNAP
    _FW-CAM @ CAM-X _FW-CAM @ CAM-Y 2 PICK BOARD-WINDOW!
    BOARD-REBUILD DROP
    _FW-UPDATE-STATUS ;

\ ---------------------------------------------------------------------
\ Turns
\ ---------------------------------------------------------------------

: _FW-PASSABLE?  ( x y -- flag )
    OVER 0< OVER 0< OR IF 2DROP FALSE EXIT THEN
    OVER _FW-MAP @ GMAP-W < 0= IF 2DROP FALSE EXIT THEN
    DUP _FW-MAP @ GMAP-H < 0= IF 2DROP FALSE EXIT THEN
    _FW-MAP @ GMAP-CMAP -ROT CMAP-GET 0= ;

\ The lamp lights what it reaches from where the archivist stands.
: _FW-LIGHT  ( -- )
    _FW-FOG @ DUP FOG-HIDE-ALL  _FW-PX @ _FW-PY @ _FW-LAMP FOG-REVEAL ;

: _FW-END-TURN  ( -- )
    1 _FW-TURN +!  1 _FW-DIRTY +!
    _FW-LIGHT _FW-REDRAW ;

\ A step of dx dy, if the way is open; a diagonal step needs both
\ straight neighbours open, so the archivist never squeezes between
\ two shelves.  A blocked step takes no turn.
: _FW-MOVE  ( dx dy -- moved? )
    _FW-PY @ + SWAP _FW-PX @ + SWAP                 ( x y )
    2DUP _FW-PASSABLE? 0= IF 2DROP FALSE EXIT THEN
    OVER _FW-PY @ _FW-PASSABLE? 0= IF 2DROP FALSE EXIT THEN
    _FW-PX @ OVER _FW-PASSABLE? 0= IF 2DROP FALSE EXIT THEN
    _FW-PY ! _FW-PX !
    _FW-END-TURN TRUE ;

\ A step a key asks for, which leaves no tile selected
: _FW-STEP  ( dx dy -- )
    -1 -1 _FW-BOARD @ BOARD-CURSOR!
    _FW-MOVE 0= IF _FW-REDRAW THEN ;

: _FW-WAIT  ( -- )  _FW-END-TURN ;

\ A selected tile: the archivist takes the path's first step toward it.
: _FW-SELECTED  ( x y instance -- )
    _FW-ACTIVATE
    2DUP _FW-BOARD @ BOARD-CURSOR!
    2DUP _FW-PY @ = SWAP _FW-PX @ = AND IF 2DROP _FW-REDRAW EXIT THEN
    _FW-SEARCH @ -ROT _FW-PX @ _FW-PY @ 2SWAP ASTAR-RUN ASTAR-FOUND <> IF
        _FW-REDRAW EXIT
    THEN
    _FW-SEARCH @ ASTAR-PATH 2 < IF DROP _FW-REDRAW EXIT THEN
    2 CELLS + DUP @ SWAP CELL+ @                    ( x y )
    _FW-PY @ - SWAP _FW-PX @ - SWAP _FW-MOVE 0= IF _FW-REDRAW THEN ;

\ ---------------------------------------------------------------------
\ Nights
\ ---------------------------------------------------------------------

\ The archivist's spawn in the room, or its first open tile
: _FW-SPAWN  ( -- x y )
    _FW-MAP @ S" archivist" GMAP-MARK DUP 0< 0= IF
        _FW-MAP @ GMAP-SPAWNS 0 ?DO
            _FW-MAP @ I GMAP-SPAWN@ 3 PICK = IF
                ROT DROP UNLOOP EXIT
            THEN
            2DROP
        LOOP
    THEN
    DROP 1 1 ;

: _FW-NEW-NIGHT  ( -- )
    _FW-START-X @ _FW-PX !  _FW-START-Y @ _FW-PY !
    0 _FW-TURN !  0 _FW-DIRTY !
    _FW-FOG @ FOG-RESET  _FW-LIGHT
    -1 -1 _FW-BOARD @ BOARD-CURSOR!
    _FW-REDRAW ;

\ A save: the room's name, the turn, where the archivist stands, and
\ the tiles seen, visible ones as remembered.
: _FW-SAVE  ( -- status )
    GSAVE-NEW >R
    R@ S" version" _FW-SAVE-VERSION GSAVE-INT
    R@ S" room" _FW-ROOM$ GSAVE-STR
    R@ S" turn" _FW-TURN @ GSAVE-INT
    R@ S" x" _FW-PX @ GSAVE-INT
    R@ S" y" _FW-PY @ GSAVE-INT
    _FW-FOG @ FOG-DATA _FW-MAP @ GMAP-W _FW-MAP @ GMAP-H * 0 ?DO
        DUP I + C@ FOG-VISIBLE = IF FOG-REMEMBERED OVER I + C! THEN
    LOOP DROP
    R@ S" seen" _FW-FOG @ FOG-DATA _FW-MAP @ GMAP-W _FW-MAP @ GMAP-H *
        GSAVE-BLOB
    R@ _FW-REPLACE GSAVE-WRITE
    R> GSAVE-FREE
    _FW-LIGHT
    DUP 0= IF 0 _FW-DIRTY ! THEN
    _FW-REDRAW ;

VARIABLE _FWL-CTX

\ Is the load's integer under the key there?  It goes on the stack.
: _FW-LOAD-INT  ( key-a key-u -- n found? )  _FWL-CTX @ -ROT GLOAD-INT ;

\ A loaded night must be this room's, with the archivist on an open tile
\ and every seen tile unseen or remembered.
: _FW-LOAD-CHECK  ( -- flag )
    S" version" _FW-LOAD-INT 0= IF DROP FALSE EXIT THEN
    _FW-SAVE-VERSION <> IF FALSE EXIT THEN
    _FWL-CTX @ S" room" GLOAD-STR 0= IF 2DROP FALSE EXIT THEN
    _FW-ROOM$ COMPARE IF FALSE EXIT THEN
    S" x" _FW-LOAD-INT 0= IF DROP FALSE EXIT THEN
    S" y" _FW-LOAD-INT 0= IF 2DROP FALSE EXIT THEN
    _FW-PASSABLE? 0= IF FALSE EXIT THEN
    S" turn" _FW-LOAD-INT 0= IF DROP FALSE EXIT THEN
    0< IF FALSE EXIT THEN
    _FWL-CTX @ S" seen" GLOAD-BLOB 0= IF 2DROP FALSE EXIT THEN
    _FW-MAP @ GMAP-W _FW-MAP @ GMAP-H * <> IF DROP FALSE EXIT THEN
    _FW-MAP @ GMAP-W _FW-MAP @ GMAP-H * 0 ?DO
        DUP I + C@ FOG-REMEMBERED > IF DROP UNLOOP FALSE EXIT THEN
    LOOP
    DROP TRUE ;

0 CONSTANT _FW-L-OK
1 CONSTANT _FW-L-MISSING
2 CONSTANT _FW-L-FOREIGN
3 CONSTANT _FW-L-FAILED

: _FW-LOAD  ( -- status )
    _FW-REPLACE GLOAD-OPEN ?DUP IF
        NIP GSAVE-S-MISSING = IF _FW-L-MISSING ELSE _FW-L-FAILED THEN EXIT
    THEN
    _FWL-CTX !
    _FW-LOAD-CHECK 0= IF _FWL-CTX @ GLOAD-CLOSE _FW-L-FOREIGN EXIT THEN
    S" turn" _FW-LOAD-INT DROP _FW-TURN !
    S" x" _FW-LOAD-INT DROP _FW-PX !
    S" y" _FW-LOAD-INT DROP _FW-PY !
    _FW-FOG @ FOG-RESET
    _FWL-CTX @ S" seen" GLOAD-BLOB DROP _FW-FOG @ FOG-DATA SWAP CMOVE
    _FWL-CTX @ GLOAD-CLOSE
    0 _FW-DIRTY !
    _FW-LIGHT
    -1 -1 _FW-BOARD @ BOARD-CURSOR!
    _FW-REDRAW
    _FW-L-OK ;

\ ---------------------------------------------------------------------
\ Actions
\ ---------------------------------------------------------------------

: _FW-DO-SAVE  ( elem -- )
    DROP _FW-SAVE ?DUP IF
        GSAVE-S-READ-ONLY = IF
            S" Folio Watch's place is read-only" 2200 ASHELL-TOAST-WARNING
        ELSE
            S" The night was not saved" 1800 ASHELL-TOAST-ERROR
        THEN
    ELSE S" Night saved" 1500 ASHELL-TOAST THEN ;

: _FW-LOAD-NOW  ( -- )
    _FW-LOAD CASE
        _FW-L-OK OF S" Night loaded" 1500 ASHELL-TOAST ENDOF
        _FW-L-MISSING OF S" No saved night yet" 1800 ASHELL-TOAST-WARNING ENDOF
        _FW-L-FOREIGN OF
            S" The saved night belongs to another room" 2200 ASHELL-TOAST-ERROR
        ENDOF
        >R S" The saved night could not be read" 2200 ASHELL-TOAST-ERROR R>
    ENDCASE ;

: _FW-LOAD-CONFIRMED  ( confirmed? context -- )
    _FW-ACTIVATE IF _FW-LOAD-NOW THEN ;

: _FW-DO-LOAD  ( elem -- )
    DROP _FW-DIRTY @ 0= IF _FW-LOAD-NOW EXIT THEN
    S" Load the saved night and lose this one's unsaved turns?" S" Load"
        ['] _FW-LOAD-CONFIRMED _FW-CURRENT-INSTANCE @ DLG-CONFIRM DROP ;

: _FW-NEW-CONFIRMED  ( confirmed? context -- )
    _FW-ACTIVATE IF _FW-NEW-NIGHT THEN ;

: _FW-DO-NEW  ( elem -- )
    DROP _FW-DIRTY @ 0= IF _FW-NEW-NIGHT EXIT THEN
    S" Start a new night and lose this one's unsaved turns?" S" New Night"
        ['] _FW-NEW-CONFIRMED _FW-CURRENT-INSTANCE @ DLG-CONFIRM DROP ;

: _FW-DO-QUIT  ( elem -- )  DROP ASHELL-QUIT ;

: _FW-DO-KEYS  ( elem -- )
    DROP
    S" Arrows or h j k l step. y u b n step diagonally. . or Space waits. Select a tile to walk toward it. Ctrl+N new night, Ctrl+S save, Ctrl+O load, Ctrl+Q quit."
    DLG-INFO DROP ;

: _FW-DO-ABOUT  ( elem -- )
    DROP
    S" Folio Watch keeps an archive's reading rooms through the night. The hand lamp lights the room around the archivist, and the room stays in memory where the lamp has been."
    DLG-INFO DROP ;

\ ---------------------------------------------------------------------
\ App lifecycle
\ ---------------------------------------------------------------------

: _FW-KEY-STEP  ( char -- handled? )
    CASE
        [CHAR] h OF -1  0 _FW-STEP TRUE ENDOF
        [CHAR] l OF  1  0 _FW-STEP TRUE ENDOF
        [CHAR] k OF  0 -1 _FW-STEP TRUE ENDOF
        [CHAR] j OF  0  1 _FW-STEP TRUE ENDOF
        [CHAR] y OF -1 -1 _FW-STEP TRUE ENDOF
        [CHAR] u OF  1 -1 _FW-STEP TRUE ENDOF
        [CHAR] b OF -1  1 _FW-STEP TRUE ENDOF
        [CHAR] n OF  1  1 _FW-STEP TRUE ENDOF
        [CHAR] . OF _FW-WAIT TRUE ENDOF
        32 OF _FW-WAIT TRUE ENDOF
        >R FALSE R>
    ENDCASE ;

: FOLIO-EVENT-CB  ( event instance -- consumed? )
    _FW-ACTIVATE
    _FW-BOARD @ 0= IF DROP 0 EXIT THEN
    \ Pointer input is UIDL's, which hands a press on the board to it.
    DUP @ KEY-T-MOUSE = IF DROP 0 EXIT THEN
    _UTUI-MENU-OPEN @ IF DROP 0 EXIT THEN
    _FW-BOARD @ BOARD-FITS? 0= IF _FW-REDRAW THEN
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-LEFT OF -1 0 _FW-STEP -1 EXIT ENDOF
            KEY-RIGHT OF 1 0 _FW-STEP -1 EXIT ENDOF
            KEY-UP OF 0 -1 _FW-STEP -1 EXIT ENDOF
            KEY-DOWN OF 0 1 _FW-STEP -1 EXIT ENDOF
        ENDCASE
        0 EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
        DUP 16 + @ 0= IF 8 + @ _FW-KEY-STEP EXIT THEN
    THEN
    DROP 0 ;

: FOLIO-TICK-CB  ( instance -- )
    _FW-ACTIVATE
    _FW-BOARD @ ?DUP IF BOARD-FITS? 0= IF _FW-REDRAW THEN THEN ;

: FOLIO-PAINT-CB  ( instance -- )  DROP ;

: FOLIO-INIT-CB  ( instance -- )
    _FW-ACTIVATE
    0 _FW-MAP ! 0 _FW-FOG ! 0 _FW-BOARD ! 0 _FW-CAM ! 0 _FW-SEARCH !
    0 _FW-TEXTS ! 0 _FW-DIRTY ! 0 _FW-DISCARD-ARMED ! 0 _FW-TURN !
    S" quit" ['] _FW-DO-QUIT UTUI-DO!
    S" keys" ['] _FW-DO-KEYS UTUI-DO!
    S" about" ['] _FW-DO-ABOUT UTUI-DO!
    \ Nights are saved in the home.
    _FW-SAVE$ _FW-CURRENT-INSTANCE @ CINST-HOME DUP PLACE-WRITABLE?
        _FW-REPLACE PLACE-VREPL!
    0<> ABORT" folio watch: its home cannot keep its night"
    _FW-ROOM$ _FW-CURRENT-INSTANCE @ CINST-ORIGIN GMAP-LOAD
    ?DUP IF
        NIP DROP S" Folio Watch could not read its room" 3000 ASHELL-TOAST-ERROR
        EXIT
    THEN _FW-MAP !
    _FW-TEXTS-BUILD ABORT" folio watch: tile text allocation failed"
    _FW-MAP @ GMAP-W _FW-MAP @ GMAP-H FOG-NEW _FW-FOG !
    _FW-FOG @ _FW-MAP @ GMAP-SIGHT FOG-BLOCK-MAP!
    _FW-MAP @ GMAP-CMAP ASTAR-NEW _FW-SEARCH !
    _FW-SEARCH @ 2 3 ASTAR-STEPS!
    _FW-SEARCH @ TRUE ASTAR-CORNERS!
    _FW-MAP @ GMAP-W _FW-MAP @ GMAP-H 1 1 CAM-NEW _FW-CAM !
    _FW-SPAWN _FW-START-Y ! _FW-START-X !
    S" board" UTUI-BY-ID _FW-E-BOARD !
    S" sbar-room" UTUI-BY-ID _FW-E-ROOM !
    S" sbar-turn" UTUI-BY-ID _FW-E-TURN !
    _FW-E-BOARD @ ?DUP IF
        UTUI-ELEM-RGN _FW-MAP @ GMAP-W _FW-MAP @ GMAP-H BOARD-NEW
        DUP _FW-BOARD !
        DUP ['] _FW-TOKEN _FW-CURRENT-INSTANCE @ ROT BOARD-TOKEN!
        DUP ['] _FW-SELECTED SWAP BOARD-ON-SELECT
        BOARD-WIDGET _FW-E-BOARD @ UTUI-WIDGET-SET
        _FW-E-BOARD @ UTUI-FOCUS!
    THEN
    S" new" ['] _FW-DO-NEW UTUI-DO!
    S" save" ['] _FW-DO-SAVE UTUI-DO!
    S" load" ['] _FW-DO-LOAD UTUI-DO!
    _FW-NEW-NIGHT ;

: _FW-CLOSE-CONFIRMED  ( confirmed? context -- )
    _FW-ACTIVATE IF -1 _FW-DISCARD-ARMED ! ASHELL-QUIT THEN ;

\ Unsaved turns defer the close to a question; agreeing to lose them asks
\ to close again, and that close goes ahead.
: FOLIO-REQUEST-CLOSE-CB  ( reason instance -- decision )
    _FW-ACTIVATE DROP
    _FW-DIRTY @ 0= IF APP-CLOSE-D-ALLOW EXIT THEN
    _FW-DISCARD-ARMED @ IF
        0 _FW-DISCARD-ARMED ! APP-CLOSE-D-ALLOW EXIT
    THEN
    S" Close Folio Watch and lose the night's unsaved turns?" S" Close"
        ['] _FW-CLOSE-CONFIRMED _FW-CURRENT-INSTANCE @ DLG-CONFIRM
    IF APP-CLOSE-D-DEFER ELSE APP-CLOSE-D-CANCEL THEN ;

: FOLIO-SHUTDOWN-CB  ( instance -- )
    _FW-ACTIVATE
    _FW-REPLACE VREPL-FINI DROP
    _FW-E-BOARD @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _FW-BOARD @ ?DUP IF BOARD-FREE THEN
    _FW-CAM @ ?DUP IF CAM-FREE THEN
    _FW-SEARCH @ ?DUP IF ASTAR-FREE THEN
    _FW-FOG @ ?DUP IF FOG-FREE THEN
    _FW-TEXTS @ FREE
    _FW-MAP @ ?DUP IF GMAP-FREE THEN
    0 _FW-BOARD ! 0 _FW-CAM ! 0 _FW-SEARCH ! 0 _FW-FOG !
    0 _FW-TEXTS ! 0 _FW-MAP ! ;

CREATE FOLIO-COMP-DESC COMP-DESC ALLOT

: _FW-COMP-SETUP  ( -- )
    FOLIO-COMP-DESC COMP-DESC-INIT
    \ Folio Watch keeps its nights in its home.
    PLACES-NEED-HOME FOLIO-COMP-DESC COMP.PLACE-NEEDS !
    S" org.akashic.folio-watch"
    FOLIO-COMP-DESC COMP.ID-U ! FOLIO-COMP-DESC COMP.ID-A !
    S" 0.1.0"
    FOLIO-COMP-DESC COMP.VERSION-U ! FOLIO-COMP-DESC COMP.VERSION-A !
    _FW-STATE-SIZE FOLIO-COMP-DESC COMP.STATE-SIZE ! ;

: FOLIO-ENTRY  ( desc -- )
    _FW-COMP-SETUP
    DUP APP-DESC-INIT
    FOLIO-COMP-DESC OVER APP.COMP-DESC !
    ['] FOLIO-INIT-CB OVER APP.INIT-XT !
    ['] FOLIO-EVENT-CB OVER APP.EVENT-XT !
    ['] FOLIO-TICK-CB OVER APP.TICK-XT !
    ['] FOLIO-PAINT-CB OVER APP.PAINT-XT !
    ['] FOLIO-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _FW-ACTIVATE OVER APP.ACTIVATE-XT !
    ['] FOLIO-REQUEST-CLOSE-CB OVER APP.REQUEST-CLOSE-XT !
    S" tui/applets/folio/folio.uidl"
    ROT DUP >R APP.UIDL-FILE-U ! R@ APP.UIDL-FILE-A !
    0 R@ APP.WIDTH ! 0 R@ APP.HEIGHT !
    S" Folio Watch" R@ APP.TITLE-U ! R> APP.TITLE-A ! ;

CREATE FOLIO-DESC APP-DESC ALLOT

: FOLIO-RUN  ( -- )
    FOLIO-DESC FOLIO-ENTRY
    FOLIO-DESC ASHELL-RUN ;
