\ =====================================================================
\  akashic/game/2d/collide.f — Collision Detection
\ =====================================================================
\
\  Provides a collision map (parallel byte array to a tilemap) and
\  geometric collision primitives.  The collision map marks each tile
\  position as passable (0) or solid (non-zero).  Non-zero values
\  can encode tile type (1=wall, 2=water, etc.) for game logic.
\
\  Collision Map Descriptor (24 bytes, 3 cells):
\    +0   width     Map width  (columns)
\    +8   height    Map height (rows)
\   +16   data      Address of byte array (width × height bytes)
\
\  Public API — Collision Map:
\    CMAP-NEW        ( w h -- cmap )           Allocate collision map
\    CMAP-NEW?       ( w h -- cmap ior )       The same, answering failure
\    CMAP-FREE       ( cmap -- )               Free collision map
\    CMAP-SET        ( cmap col row val -- )    Set tile collision value
\    CMAP-GET        ( cmap col row -- val )    Get tile collision value
\    CMAP-FILL       ( cmap val -- )            Fill all tiles with value
\    CMAP-SOLID?     ( cmap col row -- flag )   Is tile non-passable?
\    CMAP-W          ( cmap -- w )              Get width
\    CMAP-H          ( cmap -- h )              Get height
\    CMAP-DATA       ( cmap -- addr )           Tile bytes, row by row
\
\  Public API — Geometric Primitives:
\    PT-IN-RECT?     ( px py rx ry rw rh -- flag )
\    AABB-OVERLAP?   ( x1 y1 w1 h1 x2 y2 w2 h2 -- flag )
\
\  Prefix: CMAP- (public), _CMAP- (internal)
\  Provider: akashic-game-2d-collide
\  Dependencies: none

PROVIDED akashic-game-2d-collide

\ =====================================================================
\  §1 — Collision Map Descriptor
\ =====================================================================

 0 CONSTANT _CMAP-O-W
 8 CONSTANT _CMAP-O-H
16 CONSTANT _CMAP-O-DATA
24 CONSTANT _CMAP-DESC-SIZE

\ =====================================================================
\  §2 — Collision Map Constructor / Destructor
\ =====================================================================

\ CMAP-NEW? ( w h -- cmap ior )
\   A map of w by h tiles, all 0 (passable), or 0 and the ior of the
\   allocation that failed.  Both sizes must be at least 1.
: CMAP-NEW?  ( w h -- cmap ior )
    _CMAP-DESC-SIZE ALLOCATE ?DUP IF >R DROP 2DROP 0 R> EXIT THEN
    >R 2DUP * ALLOCATE ?DUP IF                    ( w h data ior  R: desc )
        >R DROP 2DROP R> R> FREE 0 SWAP EXIT
    THEN
    R@ _CMAP-O-DATA + !  R@ _CMAP-O-H + !  R@ _CMAP-O-W + !
    R@ _CMAP-O-DATA + @  R@ _CMAP-O-W + @ R@ _CMAP-O-H + @ *  0 FILL
    R> 0 ;

\ CMAP-NEW ( w h -- cmap )
\   CMAP-NEW? for a caller that cannot go on without the map.
: CMAP-NEW  ( w h -- cmap )
    CMAP-NEW? ABORT" CMAP-NEW: alloc" ;

: CMAP-FREE  ( cmap -- )
    DUP _CMAP-O-DATA + @ FREE
    FREE ;

\ =====================================================================
\  §3 — Collision Map Accessors
\ =====================================================================

: CMAP-W  ( cmap -- w )  _CMAP-O-W + @ ;
: CMAP-H  ( cmap -- h )  _CMAP-O-H + @ ;

\ CMAP-DATA ( cmap -- addr )
\   The tile bytes, width × height of them, row by row; the byte of tile
\   (col,row) is at addr + row × width + col.  The address stays the same
\   for the map's life.
: CMAP-DATA  ( cmap -- addr )  _CMAP-O-DATA + @ ;

\ _CMAP-ADDR ( cmap col row -- addr )
\   Byte address = data + row * width + col.
\   Returns 0 if out of bounds.
: _CMAP-ADDR  ( cmap col row -- addr | 0 )
    2 PICK CMAP-H OVER <= IF DROP 2DROP 0 EXIT THEN  ( cmap col row )
    OVER 0 < IF DROP 2DROP 0 EXIT THEN
    DUP  0 < IF DROP 2DROP 0 EXIT THEN
    2 PICK CMAP-W 2 PICK <= IF DROP 2DROP 0 EXIT THEN
    ( cmap col row )
    2 PICK CMAP-W *    ( cmap col offset )
    +                  ( cmap byte-idx )
    SWAP _CMAP-O-DATA + @ + ;

: CMAP-SET  ( cmap col row val -- )
    >R                                 ( cmap col row  R: val )
    _CMAP-ADDR DUP 0= IF R> 2DROP EXIT THEN
    R> SWAP C! ;

: CMAP-GET  ( cmap col row -- val )
    _CMAP-ADDR DUP 0= IF EXIT THEN
    C@ ;

: CMAP-SOLID?  ( cmap col row -- flag )
    CMAP-GET 0<> ;

: CMAP-FILL  ( cmap val -- )
    SWAP DUP >R                        ( val cmap  R: cmap )
    DUP CMAP-W SWAP CMAP-H *          ( val size  R: cmap )
    R> _CMAP-O-DATA + @               ( val size data )
    SWAP ROT FILL ;

\ =====================================================================
\  §4 — Geometric Primitives
\ =====================================================================

VARIABLE _CR-PX  VARIABLE _CR-PY
VARIABLE _CR-RX  VARIABLE _CR-RY
VARIABLE _CR-RW  VARIABLE _CR-RH

\ PT-IN-RECT? ( px py rx ry rw rh -- flag )
\   True if point (px,py) is inside rectangle (rx,ry,rw,rh).
\   Inclusive on left/top, exclusive on right/bottom.
: PT-IN-RECT?  ( px py rx ry rw rh -- flag )
    _CR-RH !  _CR-RW !  _CR-RY !  _CR-RX !
    _CR-PY !  _CR-PX !
    _CR-PX @  _CR-RX @  >=
    _CR-PY @  _CR-RY @  >= AND
    _CR-PX @  _CR-RX @ _CR-RW @ +  < AND
    _CR-PY @  _CR-RY @ _CR-RH @ +  < AND ;

\ AABB-OVERLAP? ( x1 y1 w1 h1 x2 y2 w2 h2 -- flag )
\   True if two axis-aligned bounding boxes overlap.
VARIABLE _CA-X1  VARIABLE _CA-Y1  VARIABLE _CA-W1  VARIABLE _CA-H1
VARIABLE _CA-X2  VARIABLE _CA-Y2  VARIABLE _CA-W2  VARIABLE _CA-H2

: AABB-OVERLAP?  ( x1 y1 w1 h1 x2 y2 w2 h2 -- flag )
    _CA-H2 !  _CA-W2 !  _CA-Y2 !  _CA-X2 !
    _CA-H1 !  _CA-W1 !  _CA-Y1 !  _CA-X1 !
    _CA-X1 @  _CA-X2 @ _CA-W2 @ +  <
    _CA-X2 @  _CA-X1 @ _CA-W1 @ +  < AND
    _CA-Y1 @  _CA-Y2 @ _CA-H2 @ +  < AND
    _CA-Y2 @  _CA-Y1 @ _CA-H1 @ +  < AND ;

\ =====================================================================
\  §6 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _cmap-guard

' CMAP-NEW?  CONSTANT _cmap-new-q-xt
' CMAP-NEW   CONSTANT _cmap-new-xt
' CMAP-FREE  CONSTANT _cmap-free-xt
' CMAP-SET   CONSTANT _cmap-set-xt
' CMAP-FILL  CONSTANT _cmap-fill-xt

: CMAP-NEW?  _cmap-new-q-xt _cmap-guard WITH-GUARD ;
: CMAP-NEW   _cmap-new-xt   _cmap-guard WITH-GUARD ;
: CMAP-FREE  _cmap-free-xt  _cmap-guard WITH-GUARD ;
: CMAP-SET   _cmap-set-xt   _cmap-guard WITH-GUARD ;
: CMAP-FILL  _cmap-fill-xt  _cmap-guard WITH-GUARD ;
[THEN] [THEN]
