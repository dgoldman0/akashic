\ =====================================================================
\  akashic/tui/game/world-render.f — World Renderer
\ =====================================================================
\
\  Composites tilemap layers, sprites, and overlays into a region
\  in correct z-order.  Reads the camera position to determine the
\  visible window into the game world.
\
\  Rendering pipeline:
\    1. For each tilemap layer (back to front), render the visible
\       slice offset by camera position, resolving tile IDs through
\       the atlas.
\    2. Render sprite pool (z-sorted) offset by camera.
\    3. Render overlay cells (HUD elements pinned to screen coords).
\
\  World Renderer Descriptor (64 bytes, 8 cells):
\    +0   atlas       Tile atlas address
\    +8   cam         Camera address
\    +16  rgn         Target region
\    +24  layer-0     Tilemap for layer 0 (or 0)
\    +32  layer-1     Tilemap for layer 1 (or 0)
\    +40  layer-2     Tilemap for layer 2 (or 0)
\    +48  layer-3     Tilemap for layer 3 (or 0)
\    +56  spool       Sprite pool address (or 0)
\
\  Public API:
\    WREN-NEW         ( rgn atlas cam -- wren )
\    WREN-FREE        ( wren -- )
\    WREN-SET-MAP     ( wren layer tmap -- )   layer: 0–3
\    WREN-SET-SPRITES ( wren spool -- )
\    WREN-PAINT       ( wren -- )
\
\  Prefix: WREN- (public), _WREN- (internal)
\  Provider: akashic-tui-game-world-render
\  Dependencies: atlas.f, camera.f, cell.f, screen.f, region.f

PROVIDED akashic-tui-game-world-render

REQUIRE atlas.f
REQUIRE ../../game/2d/camera.f
REQUIRE ../cell.f
REQUIRE ../screen.f
REQUIRE ../region.f
REQUIRE ../draw.f

\ =====================================================================
\  §1 — Descriptor Offsets
\ =====================================================================

0  CONSTANT _WREN-O-ATLAS
8  CONSTANT _WREN-O-CAM
16 CONSTANT _WREN-O-RGN
24 CONSTANT _WREN-O-LAYER0
32 CONSTANT _WREN-O-LAYER1
40 CONSTANT _WREN-O-LAYER2
48 CONSTANT _WREN-O-LAYER3
56 CONSTANT _WREN-O-SPOOL
64 CONSTANT _WREN-DESC-SZ

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

: WREN-NEW  ( rgn atlas cam -- wren )
    _WREN-DESC-SZ ALLOCATE
    0<> ABORT" WREN-NEW: alloc"
    DUP _WREN-DESC-SZ 0 FILL            ( rgn atlas cam wren )
    >R
    R@ _WREN-O-CAM   + !                \ cam
    R@ _WREN-O-ATLAS + !                \ atlas
    R@ _WREN-O-RGN   + !                \ rgn
    R> ;

: WREN-FREE  ( wren -- )
    FREE DROP ;

\ =====================================================================
\  §3 — Configuration
\ =====================================================================

: WREN-SET-MAP  ( wren layer tmap -- )
    >R                                   \ ( wren layer  R: tmap )
    8 * _WREN-O-LAYER0 +                ( wren off )
    SWAP + R> SWAP ! ;

: WREN-SET-SPRITES  ( wren spool -- )
    SWAP _WREN-O-SPOOL + ! ;

\ =====================================================================
\  §4 — Internal: Render One Tilemap Layer
\ =====================================================================
\
\  Reads tile IDs from the tilemap, looks them up in the atlas, and
\  writes the resulting cells to screen via SCR-SET.
\
\  The tilemap stores packed cells directly (from game/tilemap.f).
\  If an atlas is present, we treat the codepoint field of each tile
\  as a tile-id and resolve through the atlas for final appearance.
\  If the codepoint is 0, the tile is transparent (skip).

VARIABLE _WREN-CUR-ATLAS
VARIABLE _WREN-CUR-CAM-X
VARIABLE _WREN-CUR-CAM-Y
VARIABLE _WREN-CUR-RGN

\ Variable-based render approach for cleaner stack management:

VARIABLE _WREN-TMAP
VARIABLE _WREN-MAP-W
VARIABLE _WREN-MAP-H
VARIABLE _WREN-MAP-DATA
VARIABLE _WREN-VIEW-W
VARIABLE _WREN-VIEW-H

\ Read tile cell from tilemap data.  Returns 0 for out-of-bounds.
: _WREN-TILE@  ( wx wy -- cell )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP _WREN-MAP-H @ >= IF 2DROP 0 EXIT THEN
    OVER 0< IF 2DROP 0 EXIT THEN
    OVER _WREN-MAP-W @ >= IF 2DROP 0 EXIT THEN
    _WREN-MAP-W @ * + 8 * _WREN-MAP-DATA @ + @ ;

: _WREN-RENDER-LAYER2  ( tmap -- )
    DUP 0= IF DROP EXIT THEN
    DUP _WREN-TMAP !
    DUP @      _WREN-MAP-W !
    DUP 8 + @  _WREN-MAP-H !
    16 + @     _WREN-MAP-DATA !
    _WREN-CUR-RGN @ RGN-W _WREN-VIEW-W !
    _WREN-CUR-RGN @ RGN-H _WREN-VIEW-H !
    _WREN-CUR-RGN @ RGN-USE
    _WREN-VIEW-H @ 0 ?DO
        _WREN-VIEW-W @ 0 ?DO
            I _WREN-CUR-CAM-X @ +
            J _WREN-CUR-CAM-Y @ +
            _WREN-TILE@                  ( cell )
            ?DUP IF
                \ Resolve through atlas if codepoint looks like a tile-id
                \ Convention: if cell fg=0 and bg=0 and attrs=0,
                \ treat codepoint as atlas tile-id.  Otherwise use as-is.
                DUP CELL-FG@ 0= OVER CELL-BG@ 0= AND
                OVER CELL-ATTRS@ 0= AND IF
                    CELL-CP@
                    _WREN-CUR-ATLAS @ SWAP ATLAS-GET
                THEN
                J I SCR-SET
            THEN
        LOOP
    LOOP ;

\ =====================================================================
\  §5 — Internal: Render Sprites
\ =====================================================================
\
\  Sprite pool rendering (from game/sprite.f).  Each visible sprite
\  is drawn at (spr-x - cam-x, spr-y - cam-y) if inside the region.
\
\  Sprite pool descriptor: +0=data, +8=capacity, +16=count
\  Sprite descriptor: +32=x, +40=y, +88=flags (SPR-F-VISIBLE=1)
\  Sprite cell: +48 (8 bytes)

: _WREN-RENDER-SPRITES  ( spool -- )
    DUP 0= IF DROP EXIT THEN
    _WREN-CUR-RGN @ RGN-USE
    DUP 16 + @                           ( spool count )
    SWAP 0 + @                           ( count data )
    SWAP 0 ?DO                           ( data )
        DUP I 8 * + @                    ( data spr-addr )
        ?DUP IF
            \ Check visible  (flags at +88, SPR-F-VISIBLE = 1)
            DUP 88 + @ 1 AND IF
                DUP 32 + @ _WREN-CUR-CAM-X @ -   ( data spr sx )
                OVER 40 + @ _WREN-CUR-CAM-Y @ -  ( data spr sx sy )
                \ Bounds check against view
                DUP 0>= OVER _WREN-VIEW-H @ < AND
                2 PICK 0>= AND 2 PICK _WREN-VIEW-W @ < AND IF
                    SWAP                          ( data spr sy sx )
                    2 PICK 48 + @                 ( data spr sy sx cell )
                    ROT ROT SCR-SET               ( data spr )
                ELSE
                    2DROP                          ( data spr )
                THEN
            THEN
            DROP                                   ( data )
        THEN
    LOOP
    DROP ;

\ =====================================================================
\  §6 — Paint
\ =====================================================================

: WREN-PAINT  ( wren -- )
    DUP _WREN-O-ATLAS + @ _WREN-CUR-ATLAS !
    DUP _WREN-O-CAM   + @ DUP
        CAM-X _WREN-CUR-CAM-X !
    DUP _WREN-O-CAM   + @
        CAM-Y _WREN-CUR-CAM-Y !
    DUP _WREN-O-RGN   + @ _WREN-CUR-RGN !
    \ Clear the region first
    _WREN-CUR-RGN @ RGN-USE
    32 0 0 _WREN-CUR-RGN @ RGN-H _WREN-CUR-RGN @ RGN-W DRW-FILL-RECT
    \ Render layers back to front
    DUP _WREN-O-LAYER0 + @ _WREN-RENDER-LAYER2
    DUP _WREN-O-LAYER1 + @ _WREN-RENDER-LAYER2
    DUP _WREN-O-LAYER2 + @ _WREN-RENDER-LAYER2
    DUP _WREN-O-LAYER3 + @ _WREN-RENDER-LAYER2
    \ Render sprites
    _WREN-O-SPOOL + @ _WREN-RENDER-SPRITES ;
