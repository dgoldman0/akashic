\ =====================================================================
\  akashic/tui/game/atlas.f — Tile Atlas (ID → Cell Registry)
\ =====================================================================
\
\  Maps integer tile IDs to packed Cell values (codepoint + fg + bg +
\  attrs).  Provides the visual layer between game logic (which
\  operates on integer tile types) and rendering (which needs cells).
\
\  Atlas Descriptor (24 bytes, 3 cells):
\    +0   capacity    Maximum number of tile IDs
\    +8   data        Address of cell array (capacity × 8 bytes)
\    +16  count       Number of defined tiles (informational)
\
\  Public API:
\    ATLAS-NEW     ( capacity -- atlas )
\    ATLAS-FREE    ( atlas -- )
\    ATLAS-DEFINE  ( atlas id cp fg bg attrs -- )
\    ATLAS-GET     ( atlas id -- cell )
\    ATLAS-LOAD    ( atlas table count -- )
\    ATLAS-CAP     ( atlas -- capacity )
\
\  Prefix: ATLAS- (public), _ATLAS- (internal)
\  Provider: akashic-tui-game-atlas
\  Dependencies: cell.f

PROVIDED akashic-tui-game-atlas

REQUIRE ../cell.f

\ =====================================================================
\  §1 — Descriptor Offsets
\ =====================================================================

0  CONSTANT _ATLAS-O-CAP
8  CONSTANT _ATLAS-O-DATA
16 CONSTANT _ATLAS-O-COUNT
24 CONSTANT _ATLAS-DESC-SZ

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

: ATLAS-NEW  ( capacity -- atlas )
    1 MAX                                \ clamp >= 1
    _ATLAS-DESC-SZ ALLOCATE
    0<> ABORT" ATLAS-NEW: desc alloc"    ( cap desc )
    >R R@ _ATLAS-DESC-SZ 0 FILL
    DUP R@ _ATLAS-O-CAP + !             \ store capacity
    0 R@ _ATLAS-O-COUNT + !
    \ Allocate cell array: capacity × 8 bytes
    8 * ALLOCATE
    0<> ABORT" ATLAS-NEW: data alloc"    ( data )
    DUP R@ _ATLAS-O-CAP + @ 8 *         ( data data bytes )
    0 FILL                                \ zero-fill
    R@ _ATLAS-O-DATA + !                 ( )
    R> ;

: ATLAS-FREE  ( atlas -- )
    DUP _ATLAS-O-DATA + @ FREE
    FREE ;

\ =====================================================================
\  §3 — Define / Get
\ =====================================================================

\ ATLAS-DEFINE ( atlas id cp fg bg attrs -- )
\   Register a tile appearance.  id must be < capacity.
: ATLAS-DEFINE  ( atlas id cp fg bg attrs -- )
    CELL-MAKE                            ( atlas id cell )
    >R                                   \ ( atlas id  R: cell )
    OVER _ATLAS-O-CAP + @ OVER <= IF
        R> DROP 2DROP EXIT               \ out of range — silently ignore
    THEN
    8 * OVER _ATLAS-O-DATA + @ +         ( atlas addr )
    R> SWAP !                            ( atlas )
    DUP _ATLAS-O-COUNT + @ 1+
    SWAP _ATLAS-O-COUNT + ! ;

\ ATLAS-GET ( atlas id -- cell )
\   Look up tile id.  Returns CELL-BLANK for undefined / out-of-range.
: ATLAS-GET  ( atlas id -- cell )
    OVER _ATLAS-O-CAP + @ OVER <= IF
        2DROP CELL-BLANK EXIT
    THEN
    8 * SWAP _ATLAS-O-DATA + @ + @ ;

\ =====================================================================
\  §4 — Bulk Load
\ =====================================================================
\
\  ATLAS-LOAD ( atlas table count -- )
\    Load from a flat table of 5-cell records:
\      id  cp  fg  bg  attrs
\    Reads count records, calling ATLAS-DEFINE for each.

: ATLAS-LOAD  ( atlas table count -- )
    0 ?DO                                ( atlas table )
        DUP >R  OVER                     ( atlas table atlas  R: table )
        R@      @                        ( .. atlas id )
        R@ CELL+ @                       ( .. atlas id cp )
        R@ 2 CELLS + @                  ( .. atlas id cp fg )
        R@ 3 CELLS + @                  ( .. atlas id cp fg bg )
        R> 4 CELLS + @                  ( .. atlas id cp fg bg attrs )
        ATLAS-DEFINE                     ( atlas table )
        5 CELLS +                        \ advance table pointer
    LOOP
    2DROP ;

\ =====================================================================
\  §5 — Queries
\ =====================================================================

: ATLAS-CAP  ( atlas -- capacity )
    _ATLAS-O-CAP + @ ;

\ =====================================================================
\  §6 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _atlas-guard

' ATLAS-NEW    CONSTANT _atlas-new-xt
' ATLAS-FREE   CONSTANT _atlas-free-xt
' ATLAS-DEFINE CONSTANT _atlas-def-xt
' ATLAS-LOAD   CONSTANT _atlas-load-xt

: ATLAS-NEW    _atlas-new-xt    _atlas-guard WITH-GUARD ;
: ATLAS-FREE   _atlas-free-xt   _atlas-guard WITH-GUARD ;
: ATLAS-DEFINE _atlas-def-xt    _atlas-guard WITH-GUARD ;
: ATLAS-LOAD   _atlas-load-xt   _atlas-guard WITH-GUARD ;
[THEN] [THEN]
