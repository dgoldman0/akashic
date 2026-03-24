\ =====================================================================
\  akashic/tui/game/widgets/minimap.f — Minimap Overlay Widget
\ =====================================================================
\
\  Renders a zoomed-out overhead view of a tilemap using the Braille
\  canvas.  Each canvas dot corresponds to one map tile (or a block
\  of tiles when scale > 1).  The camera viewport is drawn as a
\  rectangle.  Arbitrary markers (waypoint, enemy, etc.) can be
\  placed on the map.
\
\  Non-focusable — does not consume keyboard events.
\
\  Descriptor (header + 10 cells = 120 bytes):
\    +0..+39  widget header  (type = WDG-T-MINIMAP)
\    +40   tmap         Tilemap address
\    +48   cam          Camera address (CAM-X/CAM-Y)
\    +56   canvas       Internal canvas widget
\    +64   scale        Tile-to-dot ratio (default 1)
\    +72   vp-w         Viewport width in tiles
\    +80   vp-h         Viewport height in tiles
\    +88   markers      Marker array address (or 0)
\    +96   marker-max   Max markers
\    +104  marker-cnt   Current marker count
\    +112  bg-color     Background colour index
\
\  Marker entry (32 bytes, 4 cells):
\    +0  x        Map tile X
\    +8  y        Map tile Y
\    +16 cp       Codepoint (for Braille, a dot; for label, a char)
\    +24 fg       Foreground colour
\
\  Public API:
\    MMAP-NEW          ( rgn tmap cam -- widget )
\    MMAP-FREE         ( widget -- )
\    MMAP-SCALE!       ( n widget -- )
\    MMAP-VIEWPORT!    ( w h widget -- )
\    MMAP-UPDATE       ( widget -- )
\    MMAP-MARKER       ( x y fg widget -- marker-id )
\    MMAP-CLEAR-MARKERS ( widget -- )
\    MMAP-BG!          ( color widget -- )
\
\  Prefix: MMAP- (public), _MMAP- (internal)
\  Provider: akashic-tui-game-widgets-minimap
\  Dependencies: widget.f, draw.f, canvas.f, region.f, tilemap.f

PROVIDED ak-tui-gw-minimap

REQUIRE ../../widget.f
REQUIRE ../../draw.f
REQUIRE ../../widgets/canvas.f
REQUIRE ../../region.f
REQUIRE ../tilemap.f
REQUIRE ../../../game/2d/camera.f

\ =====================================================================
\  §1 — Constants & Layout
\ =====================================================================

21 CONSTANT WDG-T-MINIMAP

40  CONSTANT _MMAP-O-TMAP
48  CONSTANT _MMAP-O-CAM
56  CONSTANT _MMAP-O-CANVAS
64  CONSTANT _MMAP-O-SCALE
72  CONSTANT _MMAP-O-VPW
80  CONSTANT _MMAP-O-VPH
88  CONSTANT _MMAP-O-MARKERS
96  CONSTANT _MMAP-O-MKMAX
104 CONSTANT _MMAP-O-MKCNT
112 CONSTANT _MMAP-O-BG
120 CONSTANT _MMAP-DESC-SZ

\ Marker entry layout (32 bytes)
 0 CONSTANT _MMAP-MK-X
 8 CONSTANT _MMAP-MK-Y
16 CONSTANT _MMAP-MK-CP
24 CONSTANT _MMAP-MK-FG
32 CONSTANT _MMAP-MK-SZ

8 CONSTANT _MMAP-DEF-MARKERS

\ =====================================================================
\  §2 — Configuration
\ =====================================================================

: MMAP-SCALE!  ( n widget -- )
    SWAP 1 MAX SWAP _MMAP-O-SCALE + ! ;

: MMAP-VIEWPORT!  ( w h widget -- )
    >R
    R@ _MMAP-O-VPH + !
    R> _MMAP-O-VPW + ! ;

: MMAP-BG!  ( color widget -- )
    _MMAP-O-BG + ! ;

\ =====================================================================
\  §3 — Markers
\ =====================================================================

VARIABLE _MMAP-MX  VARIABLE _MMAP-MY  VARIABLE _MMAP-MF
VARIABLE _MMAP-MW

: MMAP-MARKER  ( x y fg widget -- marker-id )
    _MMAP-MW !
    _MMAP-MF !  _MMAP-MY !  _MMAP-MX !
    _MMAP-MW @ _MMAP-O-MKCNT + @ _MMAP-MW @ _MMAP-O-MKMAX + @ >= IF
        -1 EXIT
    THEN
    _MMAP-MW @ _MMAP-O-MKCNT + @   ( marker-id )
    DUP _MMAP-MK-SZ *
    _MMAP-MW @ _MMAP-O-MARKERS + @ +   ( marker-id entry-addr )
    >R
    _MMAP-MX @ R@ _MMAP-MK-X  + !
    _MMAP-MY @ R@ _MMAP-MK-Y  + !
    0          R@ _MMAP-MK-CP + !
    _MMAP-MF @ R@ _MMAP-MK-FG + !
    R> DROP
    _MMAP-MW @ _MMAP-O-MKCNT + DUP @ 1+ SWAP !
    _MMAP-MW @ WDG-DIRTY ;

: MMAP-CLEAR-MARKERS  ( widget -- )
    DUP _MMAP-O-MKCNT + 0 SWAP !
    WDG-DIRTY ;

\ =====================================================================
\  §4 — Update / Render tilemap into canvas
\ =====================================================================

VARIABLE _MMAP-UW       \ widget
VARIABLE _MMAP-UCX      \ camera X
VARIABLE _MMAP-UCY      \ camera Y
VARIABLE _MMAP-UTM      \ tilemap
VARIABLE _MMAP-USCL     \ scale
VARIABLE _MMAP-UDW      \ canvas dot-width
VARIABLE _MMAP-UDH      \ canvas dot-height

: MMAP-UPDATE  ( widget -- )
    DUP _MMAP-UW !
    DUP _MMAP-O-CANVAS + @ CVS-CLEAR

    \ Get camera position
    DUP _MMAP-O-CAM + @ CAM-Y _MMAP-UCY !
    DUP _MMAP-O-CAM + @ CAM-X _MMAP-UCX !

    DUP _MMAP-O-TMAP + @  _MMAP-UTM !
    DUP _MMAP-O-SCALE + @ _MMAP-USCL !

    \ Canvas dimensions in dots: w*2, h*4  (Braille sub-cell resolution)
    DUP WDG-REGION RGN-W 2 * _MMAP-UDW !
    DUP WDG-REGION RGN-H 4 * _MMAP-UDH !

    \ Map offset: centre camera in canvas
    \ ox = cam-x - dw/scale/2,  oy = cam-y - dh/scale/2

    \ Draw tiles as dots: set dot where tile is non-zero
    _MMAP-UDH @ 0 ?DO
        _MMAP-UDW @ 0 ?DO
            \ Map coords: mx = ox + I/scale, my = oy + J/scale
            I _MMAP-USCL @ /
            _MMAP-UCX @ _MMAP-UDW @ _MMAP-USCL @ / 2 / - +
            J _MMAP-USCL @ /
            _MMAP-UCY @ _MMAP-UDH @ _MMAP-USCL @ / 2 / - +
            \ Bounds check: 0 <= mx < tmap-w, 0 <= my < tmap-h
            DUP 0 >= OVER _MMAP-UTM @ TMAP-H < AND IF
                OVER 0 >= 2 PICK _MMAP-UTM @ TMAP-W < AND IF
                    _MMAP-UTM @ -ROT TMAP-GET 0<> IF
                        DUP _MMAP-O-CANVAS + @ I J CVS-SET
                    THEN
                ELSE 2DROP THEN
            ELSE 2DROP THEN
        LOOP
    LOOP
    DROP   \ drop widget; use _MMAP-UW henceforth

    \ Draw viewport rectangle
    _MMAP-UW @ _MMAP-O-CANVAS + @ 7 0 CVS-PEN!
    _MMAP-UW @ _MMAP-O-CANVAS + @
    _MMAP-UDW @ 2 / _MMAP-UW @ _MMAP-O-VPW + @ _MMAP-USCL @ * 2 / -
    _MMAP-UDH @ 2 / _MMAP-UW @ _MMAP-O-VPH + @ _MMAP-USCL @ * 2 / -
    _MMAP-UW @ _MMAP-O-VPW + @ _MMAP-USCL @ *
    _MMAP-UW @ _MMAP-O-VPH + @ _MMAP-USCL @ *
    CVS-RECT

    \ Draw markers
    _MMAP-UW @ _MMAP-O-MKCNT + @ 0 ?DO
        _MMAP-UW @ _MMAP-O-MARKERS + @ I _MMAP-MK-SZ * +
        DUP _MMAP-MK-FG + @ 0
        _MMAP-UW @ _MMAP-O-CANVAS + @ -ROT CVS-PEN!
        DUP _MMAP-MK-X + @
        _MMAP-UCX @ _MMAP-UDW @ _MMAP-USCL @ / 2 / - -
        _MMAP-USCL @ *
        OVER _MMAP-MK-Y + @
        _MMAP-UCY @ _MMAP-UDH @ _MMAP-USCL @ / 2 / - -
        _MMAP-USCL @ *
        _MMAP-UW @ _MMAP-O-CANVAS + @ -ROT CVS-SET
        DROP
    LOOP
    _MMAP-UW @ WDG-DIRTY ;

\ =====================================================================
\  §5 — Draw callback (delegates to canvas)
\ =====================================================================

: _MMAP-DRAW  ( widget -- )
    _MMAP-O-CANVAS + @ WDG-DRAW ;

\ =====================================================================
\  §6 — Handle (no-op, non-focusable)
\ =====================================================================

: _MMAP-HANDLE  ( event widget -- consumed? )
    2DROP 0 ;

\ =====================================================================
\  §7 — Constructor / Destructor
\ =====================================================================

VARIABLE _MMAP-N-RGN  VARIABLE _MMAP-N-TM  VARIABLE _MMAP-N-CAM

: MMAP-NEW  ( rgn tmap cam -- widget )
    _MMAP-N-CAM !  _MMAP-N-TM !  _MMAP-N-RGN !

    _MMAP-DESC-SZ ALLOCATE
    0<> ABORT" MMAP-NEW: alloc"

    WDG-T-MINIMAP      OVER _WDG-O-TYPE       + !
    _MMAP-N-RGN @      OVER _WDG-O-REGION     + !
    ['] _MMAP-DRAW     OVER _WDG-O-DRAW-XT    + !
    ['] _MMAP-HANDLE   OVER _WDG-O-HANDLE-XT  + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                       OVER _WDG-O-FLAGS      + !

    _MMAP-N-TM @       OVER _MMAP-O-TMAP      + !
    _MMAP-N-CAM @      OVER _MMAP-O-CAM       + !
    1                  OVER _MMAP-O-SCALE      + !
    20                 OVER _MMAP-O-VPW        + !
    12                 OVER _MMAP-O-VPH        + !
    0                  OVER _MMAP-O-BG         + !

    \ Internal canvas
    _MMAP-N-RGN @ CVS-NEW
    OVER _MMAP-O-CANVAS + !

    \ Marker array
    _MMAP-DEF-MARKERS  OVER _MMAP-O-MKMAX + !
    0                  OVER _MMAP-O-MKCNT + !
    _MMAP-DEF-MARKERS _MMAP-MK-SZ * ALLOCATE
    0<> ABORT" MMAP-NEW: markers"
    OVER _MMAP-O-MARKERS + ! ;

: MMAP-FREE  ( widget -- )
    DUP _MMAP-O-CANVAS + @ CVS-FREE
    DUP _MMAP-O-MARKERS + @ FREE
    FREE ;

\ =====================================================================
\  §8 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _mmap-guard

' MMAP-NEW            CONSTANT _mmap-new-xt
' MMAP-FREE           CONSTANT _mmap-free-xt
' MMAP-UPDATE         CONSTANT _mmap-update-xt
' MMAP-MARKER         CONSTANT _mmap-marker-xt
' MMAP-CLEAR-MARKERS  CONSTANT _mmap-clrmk-xt

: MMAP-NEW            _mmap-new-xt    _mmap-guard WITH-GUARD ;
: MMAP-FREE           _mmap-free-xt   _mmap-guard WITH-GUARD ;
: MMAP-UPDATE         _mmap-update-xt _mmap-guard WITH-GUARD ;
: MMAP-MARKER         _mmap-marker-xt _mmap-guard WITH-GUARD ;
: MMAP-CLEAR-MARKERS  _mmap-clrmk-xt  _mmap-guard WITH-GUARD ;
[THEN] [THEN]
