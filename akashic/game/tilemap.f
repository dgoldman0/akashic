\ =====================================================================
\  akashic/tui/game/tilemap.f — 2D Tile Map with Viewport Scrolling
\ =====================================================================
\
\  Fixed-size 2D grid of cells representing a game world.  A viewport
\  (camera position) determines which rectangle of the map is visible.
\  Rendering blits the visible slice into a screen region.
\
\  Each tile is a packed Cell (8 bytes): codepoint + fg + bg + attrs.
\  Same format as screen cells — direct copy to back buffer.
\
\  Scroll optimization: tracks previous viewport position and only
\  redraws the full region on first render or large jumps.  For
\  single-tile scrolls, only the newly revealed edge is written.
\
\  Descriptor (56 bytes, 7 cells):
\    +0   map-w      Map width in tiles
\    +8   map-h      Map height in tiles
\   +16   data       Address of tile data (map-w × map-h × 8 bytes)
\   +24   vp-x       Viewport top-left column (0-based)
\   +32   vp-y       Viewport top-left row (0-based)
\   +40   prev-vp-x  Previous viewport X (for scroll detection)
\   +48   prev-vp-y  Previous viewport Y
\
\  Public API:
\    TMAP-NEW        ( w h -- tmap )            Create tilemap
\    TMAP-FREE       ( tmap -- )                Free tilemap
\    TMAP-SET        ( tmap col row cell -- )    Write a tile
\    TMAP-GET        ( tmap col row -- cell )    Read a tile
\    TMAP-FILL       ( tmap cell -- )            Fill entire map
\    TMAP-VIEWPORT!  ( tmap vx vy -- )          Set viewport position
\    TMAP-VIEWPORT-X ( tmap -- vx )             Get viewport X
\    TMAP-VIEWPORT-Y ( tmap -- vy )             Get viewport Y
\    TMAP-SCROLL     ( tmap dx dy -- )          Scroll viewport by delta
\    TMAP-RENDER     ( tmap rgn -- )            Render visible tiles to screen
\    TMAP-W          ( tmap -- w )              Map width
\    TMAP-H          ( tmap -- h )              Map height
\
\  Prefix: TMAP- (public), _TMAP- (internal)
\  Provider: akashic-tui-game-tilemap
\  Dependencies: cell.f, screen.f, region.f

PROVIDED akashic-tui-game-tilemap

REQUIRE ../tui/cell.f
REQUIRE ../tui/screen.f
REQUIRE ../tui/region.f

\ =====================================================================
\  §1 — Descriptor Offsets
\ =====================================================================

 0 CONSTANT _TMAP-O-W
 8 CONSTANT _TMAP-O-H
16 CONSTANT _TMAP-O-DATA
24 CONSTANT _TMAP-O-VPX
32 CONSTANT _TMAP-O-VPY
40 CONSTANT _TMAP-O-PVPX
48 CONSTANT _TMAP-O-PVPY
56 CONSTANT _TMAP-DESC-SIZE

\ Scratch variables (single-threaded — standard pattern in this codebase)
VARIABLE _TMAP-TMP   VARIABLE _TMAP-TMP2
VARIABLE _TMAP-VI    VARIABLE _TMAP-VJ
VARIABLE _TMAP-VW    VARIABLE _TMAP-VH
VARIABLE _TMAP-RR    VARIABLE _TMAP-RC

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

\ TMAP-NEW ( w h -- tmap )
: TMAP-NEW  ( w h -- tmap )
    OVER _TMAP-TMP !   DUP _TMAP-TMP2 !
    _TMAP-DESC-SIZE ALLOCATE 0<> ABORT" TMAP-NEW: desc alloc"
    >R
    _TMAP-TMP @ _TMAP-TMP2 @ * 8 *
    ALLOCATE 0<> ABORT" TMAP-NEW: data alloc"
    R@ _TMAP-O-DATA + !
    _TMAP-TMP @  R@ _TMAP-O-W + !
    _TMAP-TMP2 @ R@ _TMAP-O-H + !
    0  R@ _TMAP-O-VPX  + !
    0  R@ _TMAP-O-VPY  + !
    -1 R@ _TMAP-O-PVPX + !
    -1 R@ _TMAP-O-PVPY + !
    R@ _TMAP-O-DATA + @
    _TMAP-TMP @ _TMAP-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL
    R> ;

\ TMAP-FREE ( tmap -- )
: TMAP-FREE  ( tmap -- )
    DUP _TMAP-O-DATA + @ FREE DROP
    FREE DROP ;

\ =====================================================================
\  §3 — Accessors
\ =====================================================================

: TMAP-W  ( tmap -- w )   _TMAP-O-W + @ ;
: TMAP-H  ( tmap -- h )   _TMAP-O-H + @ ;
: TMAP-VIEWPORT-X  ( tmap -- vx )  _TMAP-O-VPX + @ ;
: TMAP-VIEWPORT-Y  ( tmap -- vy )  _TMAP-O-VPY + @ ;

\ =====================================================================
\  §4 — Tile Access
\ =====================================================================

\ _TMAP-ADDR ( tmap col row -- addr )
\   addr = data + (row * w + col) * 8
: _TMAP-ADDR  ( tmap col row -- addr )
    2 PICK _TMAP-O-W + @ *    ( tmap col row*w )
    +                          ( tmap idx )
    8 *                        ( tmap byte-offset )
    SWAP _TMAP-O-DATA + @ + ;

\ TMAP-SET ( tmap col row cell -- )
: TMAP-SET  ( tmap col row cell -- )
    >R _TMAP-ADDR R> SWAP ! ;

\ TMAP-GET ( tmap col row -- cell )
: TMAP-GET  ( tmap col row -- cell )
    _TMAP-ADDR @ ;

\ TMAP-FILL ( tmap cell -- )
: TMAP-FILL  ( tmap cell -- )
    SWAP                       ( cell tmap )
    DUP _TMAP-O-DATA + @      ( cell tmap data )
    SWAP DUP _TMAP-O-W + @
    SWAP     _TMAP-O-H + @ *  ( cell data count )
    ROT _SCR-CELL-FILL ;

\ =====================================================================
\  §5 — Viewport
\ =====================================================================

\ TMAP-VIEWPORT! ( tmap vx vy -- )
: TMAP-VIEWPORT!  ( tmap vx vy -- )
    DUP 0< IF DROP 0 THEN
    2 PICK _TMAP-O-VPY + !
    DUP 0< IF DROP 0 THEN
    OVER  _TMAP-O-VPX + !
    DROP ;

\ TMAP-SCROLL ( tmap dx dy -- )
: TMAP-SCROLL  ( tmap dx dy -- )
    2 PICK _TMAP-O-VPY + @ +
    -ROT
    OVER _TMAP-O-VPX + @ +
    ROT
    TMAP-VIEWPORT! ;

\ =====================================================================
\  §6 — Rendering
\ =====================================================================

\ _TMAP-RENDER-FULL ( tmap rgn -- )
\   Blit visible viewport into screen back buffer.
\   Uses explicit counter variables for nested loop clarity.
: _TMAP-RENDER-FULL  ( tmap rgn -- )
    DUP RGN-H _TMAP-VH !
    DUP RGN-W _TMAP-VW !
    DUP RGN-ROW _TMAP-RR !
    RGN-COL _TMAP-RC !                    ( tmap )
    _TMAP-VH @ 0 DO                       \ I = viewport row
        I _TMAP-VJ !
        _TMAP-VW @ 0 DO                   \ I = viewport col (inner)
            I _TMAP-VI !
            DUP                            ( tmap tmap )
            \ map coords
            DUP _TMAP-O-VPX + @  _TMAP-VI @ +  ( tmap tmap mx )
            OVER _TMAP-O-VPY + @ _TMAP-VJ @ + ( tmap tmap mx my )
            \ Bounds check
            OVER 3 PICK TMAP-W >= IF
                2DROP DROP CELL-BLANK
            ELSE
                DUP 3 PICK TMAP-H >= IF
                    2DROP DROP CELL-BLANK
                ELSE
                    TMAP-GET           ( tmap cell )
                THEN
            THEN
            _TMAP-VJ @ _TMAP-RR @ +   ( tmap cell scr-row )
            _TMAP-VI @ _TMAP-RC @ +   ( tmap cell scr-row scr-col )
            ROT -ROT SCR-SET           ( tmap )
        LOOP
    LOOP
    \ Save current viewport as previous
    DUP DUP _TMAP-O-VPX + @ SWAP _TMAP-O-PVPX + !
    DUP DUP _TMAP-O-VPY + @ SWAP _TMAP-O-PVPY + !
    DROP ;

\ TMAP-RENDER ( tmap rgn -- )
\   Render visible tiles.  Uses full redraw for now.
\   Future: detect 1-tile scroll and only redraw the revealed edge.
: TMAP-RENDER  ( tmap rgn -- )
    _TMAP-RENDER-FULL ;

\ =====================================================================
\  §7 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _tmap-guard

' TMAP-NEW       CONSTANT _tmap-new-xt
' TMAP-FREE      CONSTANT _tmap-free-xt
' TMAP-SET       CONSTANT _tmap-set-xt
' TMAP-GET       CONSTANT _tmap-get-xt
' TMAP-FILL      CONSTANT _tmap-fill-xt
' TMAP-VIEWPORT! CONSTANT _tmap-vp-xt
' TMAP-SCROLL    CONSTANT _tmap-scroll-xt
' TMAP-RENDER    CONSTANT _tmap-render-xt

: TMAP-NEW       _tmap-new-xt    _tmap-guard WITH-GUARD ;
: TMAP-FREE      _tmap-free-xt   _tmap-guard WITH-GUARD ;
: TMAP-SET       _tmap-set-xt    _tmap-guard WITH-GUARD ;
: TMAP-GET       _tmap-get-xt    _tmap-guard WITH-GUARD ;
: TMAP-FILL      _tmap-fill-xt   _tmap-guard WITH-GUARD ;
: TMAP-VIEWPORT! _tmap-vp-xt     _tmap-guard WITH-GUARD ;
: TMAP-SCROLL    _tmap-scroll-xt _tmap-guard WITH-GUARD ;
: TMAP-RENDER    _tmap-render-xt _tmap-guard WITH-GUARD ;
[THEN] [THEN]
