\ =====================================================================
\  akashic/tui/game/sprite.f — Character-Cell Sprite Objects
\ =====================================================================
\
\  Sprites are game objects that occupy one or more character cells
\  and can move over a tilemap or bare screen.  Each sprite has a
\  position, appearance (cell), optional animation, z-order, and
\  visibility flag.
\
\  Sprites live in a sprite pool — a flat array for cache-friendly
\  iteration.  The pool handles allocation, rendering (in z-order),
\  and per-frame animation advancement.
\
\  Single-cell sprites are the common case.  Multi-cell sprites
\  (e.g., a 3×2 boss) use a cell-array referenced by the sprite
\  descriptor, distinguished by a flag bit.
\
\  Sprite Descriptor (64 bytes, 8 cells):
\    +0   cell       Current cell (or pointer to cell array if multi)
\    +8   x          Column position in world coords (integer)
\   +16   y          Row position in world coords (integer)
\   +24   z          Z-order (higher = drawn later = on top)
\   +32   flags      SPR-F-VISIBLE, SPR-F-MULTI, SPR-F-ANIM
\   +40   anim-ptr   Address of animation frame table (or 0)
\   +48   anim-info  Packed: frame-count (low 16) | rate (next 16) |
\                    current-frame (next 16) | tick-counter (high 16)
\   +56   user       User data (game-specific — entity ID, HP, etc.)
\
\  Animation frame table: array of cells, one per frame.
\
\  Public API:
\    SPR-NEW         ( cell -- spr )             Allocate sprite
\    SPR-POS!        ( spr x y -- )              Set position
\    SPR-POS@        ( spr -- x y )              Get position
\    SPR-MOVE        ( spr dx dy -- )            Relative move
\    SPR-CELL!       ( spr cell -- )             Set appearance
\    SPR-CELL@       ( spr -- cell )             Get appearance
\    SPR-Z!          ( spr z -- )                Set z-order
\    SPR-VISIBLE!    ( spr -- )                  Make visible
\    SPR-HIDDEN!     ( spr -- )                  Make hidden
\    SPR-VISIBLE?    ( spr -- flag )             Is visible?
\    SPR-ANIM!       ( spr tbl count rate -- )   Attach animation
\    SPR-TICK        ( spr -- )                  Advance animation
\    SPR-USER!       ( spr val -- )              Set user data
\    SPR-USER@       ( spr -- val )              Get user data
\    SPR-FREE        ( spr -- )                  Release sprite
\
\  Pool API:
\    SPOOL-NEW       ( max -- pool )             Create sprite pool
\    SPOOL-FREE      ( pool -- )                 Free pool
\    SPOOL-ADD       ( pool spr -- )             Register sprite
\    SPOOL-REMOVE    ( pool spr -- )             Deregister sprite
\    SPOOL-TICK-ALL  ( pool -- )                 Advance all anims
\    SPOOL-RENDER    ( pool rgn vpx vpy -- )     Draw sprites to screen
\    SPOOL-COUNT     ( pool -- n )               Count of sprites
\
\  Collision Helpers (requires collide.f):
\    SPR-CMAP-BLOCKED? ( spr dx dy cmap -- flag )
\        Check if sprite's target position is blocked.
\    SPR-SPR-OVERLAP?  ( spr1 spr2 -- flag )
\        Check if two 1×1 sprites share the same tile.
\
\  Prefix: SPR- / SPOOL- (public), _SPR- / _SPOOL- (internal)
\  Provider: akashic-tui-game-sprite
\  Dependencies: cell.f, screen.f, region.f, collide.f

PROVIDED akashic-tui-game-sprite

REQUIRE ../cell.f
REQUIRE ../screen.f
REQUIRE ../region.f

\ =====================================================================
\  §1 — Sprite Descriptor
\ =====================================================================

 0 CONSTANT _SPR-O-CELL
 8 CONSTANT _SPR-O-X
16 CONSTANT _SPR-O-Y
24 CONSTANT _SPR-O-Z
32 CONSTANT _SPR-O-FLAGS
40 CONSTANT _SPR-O-ANIM-PTR
48 CONSTANT _SPR-O-ANIM-INFO
56 CONSTANT _SPR-O-USER
64 CONSTANT _SPR-DESC-SIZE

\ Flags
1 CONSTANT SPR-F-VISIBLE
2 CONSTANT SPR-F-MULTI
4 CONSTANT SPR-F-ANIM

\ =====================================================================
\  §2 — Sprite Constructor / Destructor
\ =====================================================================

: SPR-NEW  ( cell -- spr )
    _SPR-DESC-SIZE ALLOCATE 0<> ABORT" SPR-NEW: alloc"
    >R
    R@ _SPR-O-CELL + !
    0 R@ _SPR-O-X + !
    0 R@ _SPR-O-Y + !
    0 R@ _SPR-O-Z + !
    SPR-F-VISIBLE R@ _SPR-O-FLAGS + !
    0 R@ _SPR-O-ANIM-PTR + !
    0 R@ _SPR-O-ANIM-INFO + !
    0 R@ _SPR-O-USER + !
    R> ;

: SPR-FREE  ( spr -- )
    FREE DROP ;

\ =====================================================================
\  §3 — Sprite Accessors
\ =====================================================================

: SPR-CELL@  ( spr -- cell )  _SPR-O-CELL + @ ;
: SPR-CELL!  ( spr cell -- )  SWAP _SPR-O-CELL + ! ;

: SPR-POS@  ( spr -- x y )
    DUP _SPR-O-X + @  SWAP _SPR-O-Y + @ ;

: SPR-POS!  ( spr x y -- )
    ROT                        ( x y spr )
    DUP >R  _SPR-O-Y + !      ( x  R: spr )
    R> _SPR-O-X + ! ;

: SPR-MOVE  ( spr dx dy -- )
    2 PICK _SPR-O-Y + @ +     ( spr dx new-y )
    2 PICK _SPR-O-Y + !       ( spr dx )
    OVER _SPR-O-X + @ +       ( spr new-x )
    SWAP _SPR-O-X + ! ;

: SPR-Z!  ( spr z -- )   SWAP _SPR-O-Z + ! ;
: SPR-Z@  ( spr -- z )   _SPR-O-Z + @ ;

: SPR-VISIBLE!  ( spr -- )
    DUP _SPR-O-FLAGS + @  SPR-F-VISIBLE OR  SWAP _SPR-O-FLAGS + ! ;

: SPR-HIDDEN!  ( spr -- )
    DUP _SPR-O-FLAGS + @  SPR-F-VISIBLE INVERT AND  SWAP _SPR-O-FLAGS + ! ;

: SPR-VISIBLE?  ( spr -- flag )
    _SPR-O-FLAGS + @  SPR-F-VISIBLE AND  0<> ;

: SPR-USER!  ( spr val -- )  SWAP _SPR-O-USER + ! ;
: SPR-USER@  ( spr -- val )  _SPR-O-USER + @ ;

\ =====================================================================
\  §4 — Animation
\ =====================================================================

\ Animation info packing (64-bit cell):
\   bits  0–15: frame count
\   bits 16–31: rate (ticks between frames)
\   bits 32–47: current frame index
\   bits 48–63: tick counter

: _SPR-ANIM-COUNT  ( info -- n )    0xFFFF AND ;
: _SPR-ANIM-RATE   ( info -- n )    16 RSHIFT 0xFFFF AND ;
: _SPR-ANIM-FRAME  ( info -- n )    32 RSHIFT 0xFFFF AND ;
: _SPR-ANIM-TICKS  ( info -- n )    48 RSHIFT 0xFFFF AND ;

: _SPR-ANIM-PACK  ( count rate frame ticks -- info )
    48 LSHIFT >R
    32 LSHIFT >R
    16 LSHIFT
    OR R> OR R> OR ;

\ --- Temporaries for SPR-ANIM! ---
VARIABLE _SPR-AT   VARIABLE _SPR-AC   VARIABLE _SPR-AR

: SPR-ANIM!  ( spr tbl count rate -- )
    _SPR-AR !  _SPR-AC !  _SPR-AT !       ( spr )
    _SPR-AT @ OVER _SPR-O-ANIM-PTR + !    ( spr )
    _SPR-AC @ _SPR-AR @ 0 0 _SPR-ANIM-PACK
    OVER _SPR-O-ANIM-INFO + !             ( spr )
    DUP _SPR-O-FLAGS + @  SPR-F-ANIM OR
    OVER _SPR-O-FLAGS + !
    \ Set cell to initial frame (frame 0)
    _SPR-AT @ @ SWAP _SPR-O-CELL + ! ;

\ --- Temporaries for SPR-TICK ---
VARIABLE _SPR-TK-CNT   VARIABLE _SPR-TK-RATE
VARIABLE _SPR-TK-FRM   VARIABLE _SPR-TK-TCK

: SPR-TICK  ( spr -- )
    DUP _SPR-O-FLAGS + @ SPR-F-ANIM AND 0= IF DROP EXIT THEN
    DUP >R
    R@ _SPR-O-ANIM-INFO + @
    DUP _SPR-ANIM-COUNT  _SPR-TK-CNT !
    DUP _SPR-ANIM-RATE   _SPR-TK-RATE !
    DUP _SPR-ANIM-FRAME  _SPR-TK-FRM !
        _SPR-ANIM-TICKS  _SPR-TK-TCK !
    _SPR-TK-TCK @ 1+ _SPR-TK-TCK !
    _SPR-TK-TCK @ _SPR-TK-RATE @ >= IF
        0 _SPR-TK-TCK !
        _SPR-TK-FRM @ 1+ _SPR-TK-CNT @ MOD _SPR-TK-FRM !
        \ Update cell from animation table
        R@ _SPR-O-ANIM-PTR + @
        _SPR-TK-FRM @ CELLS + @
        R@ _SPR-O-CELL + !
    THEN
    \ Repack info
    _SPR-TK-CNT @ _SPR-TK-RATE @ _SPR-TK-FRM @ _SPR-TK-TCK @
    _SPR-ANIM-PACK
    R> _SPR-O-ANIM-INFO + ! ;

\ =====================================================================
\  §5 — Sprite Pool
\ =====================================================================

\ Pool descriptor (24 bytes, 3 cells):
\   +0   max       Maximum sprites
\   +8   count     Current count
\  +16   array     Address of sprite-pointer array (max × 8 bytes)

 0 CONSTANT _SPOOL-O-MAX
 8 CONSTANT _SPOOL-O-CNT
16 CONSTANT _SPOOL-O-ARR
24 CONSTANT _SPOOL-DESC-SIZE

: SPOOL-NEW  ( max -- pool )
    >R
    _SPOOL-DESC-SIZE ALLOCATE 0<> ABORT" SPOOL-NEW: desc alloc"
    R@ OVER _SPOOL-O-MAX + !      ( pool  R: max )
    0  OVER _SPOOL-O-CNT + !
    R> CELLS ALLOCATE 0<> ABORT" SPOOL-NEW: array alloc"
    OVER _SPOOL-O-ARR + ! ;

: SPOOL-FREE  ( pool -- )
    DUP _SPOOL-O-ARR + @ FREE DROP
    FREE DROP ;

: SPOOL-COUNT  ( pool -- n )
    _SPOOL-O-CNT + @ ;

\ SPOOL-ADD ( pool spr -- )
\   Add sprite to pool.  Silently drops if full.
: SPOOL-ADD  ( pool spr -- )
    OVER SPOOL-COUNT               ( pool spr count )
    2 PICK _SPOOL-O-MAX + @       ( pool spr count max )
    >= IF 2DROP EXIT THEN          ( pool spr )
    OVER _SPOOL-O-ARR + @         ( pool spr arr )
    2 PICK SPOOL-COUNT CELLS +    ( pool spr slot-addr )
    !                              ( pool )
    DUP SPOOL-COUNT 1+
    SWAP _SPOOL-O-CNT + ! ;

\ SPOOL-REMOVE ( pool spr -- )
\   Remove sprite from pool.  Swaps with last entry.
VARIABLE _SPOOL-TMP

: SPOOL-REMOVE  ( pool spr -- )
    OVER _SPOOL-O-ARR + @  _SPOOL-TMP !   ( pool spr )
    OVER SPOOL-COUNT 0 ?DO
        _SPOOL-TMP @ I CELLS + @ OVER = IF
            \ Found at index I — swap with last
            OVER SPOOL-COUNT 1-            ( pool spr last-idx )
            CELLS _SPOOL-TMP @ + @         ( pool spr last-spr )
            _SPOOL-TMP @ I CELLS + !       ( pool spr )
            DROP
            DUP SPOOL-COUNT 1-
            SWAP _SPOOL-O-CNT + !
            UNLOOP EXIT
        THEN
    LOOP
    2DROP ;  \ not found

: SPOOL-TICK-ALL  ( pool -- )
    DUP _SPOOL-O-ARR + @  SWAP SPOOL-COUNT
    0 ?DO
        DUP I CELLS + @ SPR-TICK
    LOOP
    DROP ;

\ =====================================================================
\  §6 — Pool Rendering
\ =====================================================================

\ Render all visible sprites into the screen, offset by viewport.
\ Sprites are drawn in z-order (insertion sort on z before draw).
\ For small counts (<64), insertion sort is fine.

VARIABLE _SPOOL-RR   VARIABLE _SPOOL-RC
VARIABLE _SPOOL-VW   VARIABLE _SPOOL-VH
VARIABLE _SPOOL-VPX  VARIABLE _SPOOL-VPY

\ _SPOOL-SORT-Z ( arr count -- )
\   In-place insertion sort by z-order (ascending).
VARIABLE _SPOOL-SI  VARIABLE _SPOOL-SJ  VARIABLE _SPOOL-SK

: _SPOOL-SORT-Z  ( arr count -- )
    DUP 2 < IF 2DROP EXIT THEN
    SWAP _SPOOL-SI !               ( count )
    1 DO                           \ I = 1..count-1
        _SPOOL-SI @ I CELLS + @   ( key-spr )
        DUP SPR-Z@ _SPOOL-SJ !    ( key-spr )  \ key-z
        I 1-  _SPOOL-SK !         ( key-spr )  \ j = i-1
        BEGIN
            _SPOOL-SK @ 0 >= IF
                _SPOOL-SI @ _SPOOL-SK @ CELLS + @
                SPR-Z@ _SPOOL-SJ @ > IF
                    \ Shift right
                    _SPOOL-SI @ _SPOOL-SK @ CELLS + @
                    _SPOOL-SI @ _SPOOL-SK @ 1+ CELLS + !
                    _SPOOL-SK @ 1- _SPOOL-SK !
                    TRUE
                ELSE FALSE THEN
            ELSE FALSE THEN
        WHILE REPEAT
        _SPOOL-SI @ _SPOOL-SK @ 1+ CELLS + !  ( )
    LOOP ;

: SPOOL-RENDER  ( pool rgn vpx vpy -- )
    _SPOOL-VPY !  _SPOOL-VPX !
    DUP RGN-H _SPOOL-VH !
    DUP RGN-W _SPOOL-VW !
    DUP RGN-ROW _SPOOL-RR !
    RGN-COL _SPOOL-RC !               ( pool )
    \ Sort by z
    DUP _SPOOL-O-ARR + @
    OVER SPOOL-COUNT
    _SPOOL-SORT-Z
    \ Draw each visible sprite
    DUP _SPOOL-O-ARR + @ SWAP SPOOL-COUNT   ( arr count )
    0 ?DO
        DUP I CELLS + @               ( arr spr )
        DUP SPR-VISIBLE? IF
            DUP SPR-POS@               ( arr spr x y )
            \ Convert world → screen
            _SPOOL-VPY @ -             ( arr spr x scr-row-rel )
            SWAP _SPOOL-VPX @ -        ( arr spr scr-row-rel scr-col-rel )
            \ Clip to viewport
            OVER 0 >= OVER 0 >= AND IF
                OVER _SPOOL-VH @ < OVER _SPOOL-VW @ < AND IF
                    SWAP _SPOOL-RR @ + SWAP _SPOOL-RC @ +
                    ( arr spr scr-row scr-col )
                    2 PICK SPR-CELL@   ( arr spr scr-row scr-col cell )
                    -ROT SCR-SET       ( arr spr )
                    DROP
                ELSE 2DROP DROP THEN
            ELSE 2DROP DROP THEN
        ELSE DROP THEN
    LOOP
    DROP ;

\ =====================================================================
\  §7 — Collision Helpers
\ =====================================================================

REQUIRE ../../game/2d/collide.f

VARIABLE _CB-NX  VARIABLE _CB-NY

\ SPR-CMAP-BLOCKED? ( spr dx dy cmap -- flag )
\   Check if moving sprite by (dx,dy) would land on a solid tile.
: SPR-CMAP-BLOCKED?  ( spr dx dy cmap -- flag )
    >R                                 ( spr dx dy  R: cmap )
    2 PICK SPR-POS@                    ( spr dx dy x y  R: cmap )
    ROT +  _CB-NY !                    ( spr dx x  R: cmap )
    +  _CB-NX !                        ( spr  R: cmap )
    DROP
    R> _CB-NX @ _CB-NY @ CMAP-SOLID? ;

\ SPR-SPR-OVERLAP? ( spr1 spr2 -- flag )
\   True if two 1×1 sprites occupy the same tile position.
: SPR-SPR-OVERLAP?  ( spr1 spr2 -- flag )
    SPR-POS@ ROT SPR-POS@             ( x2 y2 x1 y1 )
    ROT = -ROT = AND ;

\ =====================================================================
\  §8 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _spr-guard

' SPR-NEW      CONSTANT _spr-new-xt
' SPR-FREE     CONSTANT _spr-free-xt
' SPOOL-NEW    CONSTANT _spool-new-xt
' SPOOL-FREE   CONSTANT _spool-free-xt
' SPOOL-ADD    CONSTANT _spool-add-xt
' SPOOL-REMOVE CONSTANT _spool-remove-xt
' SPOOL-RENDER CONSTANT _spool-render-xt

: SPR-NEW      _spr-new-xt      _spr-guard WITH-GUARD ;
: SPR-FREE     _spr-free-xt     _spr-guard WITH-GUARD ;
: SPOOL-NEW    _spool-new-xt    _spool-guard WITH-GUARD ;
: SPOOL-FREE   _spool-free-xt   _spool-guard WITH-GUARD ;
: SPOOL-ADD    _spool-add-xt    _spool-guard WITH-GUARD ;
: SPOOL-REMOVE _spool-remove-xt _spool-guard WITH-GUARD ;
: SPOOL-RENDER _spool-render-xt _spool-guard WITH-GUARD ;
[THEN] [THEN]
