\ =====================================================================
\  akashic/tui/region.f — Rectangular Regions (Clipping Rectangles)
\ =====================================================================
\
\  A region is a clipping rectangle within the screen.  Widgets draw
\  into regions; the region clips all cell writes to its bounds.
\  Regions can be nested (child within parent).
\
\  When a region is active (via RGN-USE), all DRW-* coordinates are
\  relative to the region's top-left, and writes outside the region
\  are silently discarded.  RGN-ROOT resets to full-screen.
\
\  Region Descriptor (5 cells = 40 bytes):
\    +0   row      Top-left row (screen-absolute)
\    +8   col      Top-left column (screen-absolute)
\   +16   height   Height in rows
\   +24   width    Width in columns
\   +32   parent   Parent region address (0 = root)
\
\  Prefix: RGN- (public), _RGN- (internal)
\  Provider: akashic-tui-region
\  Dependencies: screen.f

PROVIDED akashic-tui-region

REQUIRE screen.f
REQUIRE draw.f

\ =====================================================================
\ 1. Descriptor offsets
\ =====================================================================

 0 CONSTANT _RGN-O-ROW
 8 CONSTANT _RGN-O-COL
16 CONSTANT _RGN-O-H
24 CONSTANT _RGN-O-W
32 CONSTANT _RGN-O-PARENT

40 CONSTANT _RGN-DESC-SIZE

\ =====================================================================
\ 2. Current region state
\ =====================================================================
\
\  The current region determines coordinate translation and clipping
\  for all DRW-* words.  When no region is active (or after RGN-ROOT),
\  drawing uses raw screen coordinates with no offset.
\
\  The actual clip state lives in draw.f (_DRW-CLIP-ROW/COL/H/W).
\  region.f just sets those variables.

VARIABLE _RGN-CUR      0 _RGN-CUR !   \ 0 = no region (full screen)

\ =====================================================================
\ 3. Constructor / destructor
\ =====================================================================

\ RGN-NEW ( row col h w -- rgn )
\   Allocate a root region (no parent).
: RGN-NEW  ( row col h w -- rgn )
    _RGN-DESC-SIZE ALLOCATE
    0<> ABORT" RGN-NEW: alloc failed"
    >R                                 \ rgn addr on R
    R@ _RGN-O-W      + !              \ width
    R@ _RGN-O-H      + !              \ height
    R@ _RGN-O-COL    + !              \ col
    R@ _RGN-O-ROW    + !              \ row
    0  R@ _RGN-O-PARENT + !           \ no parent
    R> ;

\ RGN-FREE ( rgn -- )
\   Free a region descriptor.
: RGN-FREE  ( rgn -- )
    FREE DROP ;

\ =====================================================================
\ 4. Accessors
\ =====================================================================

: RGN-ROW  ( rgn -- row )    _RGN-O-ROW + @ ;
: RGN-COL  ( rgn -- col )    _RGN-O-COL + @ ;
: RGN-H    ( rgn -- h )      _RGN-O-H   + @ ;
: RGN-W    ( rgn -- w )      _RGN-O-W   + @ ;

\ =====================================================================
\ 5. RGN-USE / RGN-ROOT — activate a region
\ =====================================================================

\ RGN-USE ( rgn -- )
\   Set as current drawing region.  All DRW-* words will translate
\   coordinates relative to this region and clip to its bounds.
: RGN-USE  ( rgn -- )
    DUP _RGN-CUR !
    DUP RGN-ROW _DRW-CLIP-ROW !
    DUP RGN-COL _DRW-CLIP-COL !
    DUP RGN-H   _DRW-CLIP-H !
        RGN-W   _DRW-CLIP-W !
    -1 _DRW-CLIP-ON ! ;

\ RGN-ROOT ( -- )
\   Reset to full-screen drawing (no clipping region).
: RGN-ROOT  ( -- )
    0   _RGN-CUR !
    0   _DRW-CLIP-ROW !
    0   _DRW-CLIP-COL !
    0   _DRW-CLIP-H !
    0   _DRW-CLIP-W !
    0   _DRW-CLIP-ON ! ;

\ =====================================================================
\ 6. Sub-regions
\ =====================================================================

VARIABLE _RGN-SUB-PR
VARIABLE _RGN-SUB-AR
VARIABLE _RGN-SUB-AC
VARIABLE _RGN-SUB-H
VARIABLE _RGN-SUB-W

\ RGN-SUB ( parent r c h w -- rgn )
\   Create a sub-region.  r/c are relative to parent's top-left.
\   The sub-region is clipped to the parent's bounds.
: RGN-SUB  ( parent r c h w -- rgn )
    _RGN-SUB-W !
    _RGN-SUB-H !
    >R >R                              \ R: c r
    _RGN-SUB-PR !
    R> R>                              \ ( r c )

    \ Compute absolute position
    SWAP _RGN-SUB-PR @ RGN-ROW +  _RGN-SUB-AR !   \ abs row
    _RGN-SUB-PR @ RGN-COL +       _RGN-SUB-AC !   \ abs col

    \ Clip height: min(h, parent-h - r)
    _RGN-SUB-PR @ RGN-H  _RGN-SUB-AR @ _RGN-SUB-PR @ RGN-ROW - -
    _RGN-SUB-H @ MIN
    DUP 0< IF DROP 0 THEN
    _RGN-SUB-H !

    \ Clip width: min(w, parent-w - c)
    _RGN-SUB-PR @ RGN-W  _RGN-SUB-AC @ _RGN-SUB-PR @ RGN-COL - -
    _RGN-SUB-W @ MIN
    DUP 0< IF DROP 0 THEN
    _RGN-SUB-W !

    \ Allocate the sub-region descriptor
    _RGN-DESC-SIZE ALLOCATE
    0<> ABORT" RGN-SUB: alloc failed"
    >R
    _RGN-SUB-AR @ R@ _RGN-O-ROW    + !
    _RGN-SUB-AC @ R@ _RGN-O-COL    + !
    _RGN-SUB-H  @ R@ _RGN-O-H      + !
    _RGN-SUB-W  @ R@ _RGN-O-W      + !
    _RGN-SUB-PR @ R@ _RGN-O-PARENT + !
    R> ;

\ =====================================================================
\ 7. Point testing
\ =====================================================================

\ RGN-CONTAINS? ( row col -- flag )
\   Is point (row, col) inside the current region?
\   Coordinates are region-relative.
: RGN-CONTAINS?  ( row col -- flag )
    SWAP 0 _DRW-CLIP-ROWS WITHIN       \ 0 <= row < h ?
    SWAP 0 _DRW-CLIP-COLS WITHIN       \ 0 <= col < w ?
    AND ;

\ RGN-CLIP ( row col -- row' col' flag )
\   Translate to absolute coordinates and test if inside.
\   row' col' are screen-absolute.  flag is TRUE if the point
\   was inside the region.
: RGN-CLIP  ( row col -- row' col' flag )
    2DUP RGN-CONTAINS?                \ ( row col flag )
    >R
    SWAP _DRW-CLIP-ROW @ +            \ abs-row
    SWAP _DRW-CLIP-COL @ +            \ abs-col
    R> ;

\ =====================================================================
\ 8. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
GUARD _rgn-guard

' RGN-NEW         CONSTANT _rgn-new-xt
' RGN-FREE        CONSTANT _rgn-free-xt
' RGN-USE         CONSTANT _rgn-use-xt
' RGN-ROOT        CONSTANT _rgn-root-xt
' RGN-SUB         CONSTANT _rgn-sub-xt
' RGN-ROW         CONSTANT _rgn-row-xt
' RGN-COL         CONSTANT _rgn-col-xt
' RGN-H           CONSTANT _rgn-h-xt
' RGN-W           CONSTANT _rgn-w-xt
' RGN-CONTAINS?   CONSTANT _rgn-contains-xt
' RGN-CLIP        CONSTANT _rgn-clip-xt

: RGN-NEW         _rgn-new-xt       _rgn-guard WITH-GUARD ;
: RGN-FREE        _rgn-free-xt      _rgn-guard WITH-GUARD ;
: RGN-USE         _rgn-use-xt       _rgn-guard WITH-GUARD ;
: RGN-ROOT        _rgn-root-xt      _rgn-guard WITH-GUARD ;
: RGN-SUB         _rgn-sub-xt       _rgn-guard WITH-GUARD ;
: RGN-ROW         _rgn-row-xt       _rgn-guard WITH-GUARD ;
: RGN-COL         _rgn-col-xt       _rgn-guard WITH-GUARD ;
: RGN-H           _rgn-h-xt         _rgn-guard WITH-GUARD ;
: RGN-W           _rgn-w-xt         _rgn-guard WITH-GUARD ;
: RGN-CONTAINS?   _rgn-contains-xt  _rgn-guard WITH-GUARD ;
: RGN-CLIP        _rgn-clip-xt      _rgn-guard WITH-GUARD ;
[THEN] [THEN]
