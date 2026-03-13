\ =================================================================
\  split.f  —  Split Pane Widget
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SPL- / _SPL-
\  Depends on: akashic-tui-widget, akashic-tui-region, akashic-tui-draw
\
\  Divides a region into two sub-regions (pane A and pane B)
\  separated by a one-character-wide divider.  The split can be
\  horizontal (top / bottom) or vertical (left / right).
\
\  The ratio controls how space is allocated:
\   - ratio = N means pane A gets N rows/columns of the available
\     space (total minus the 1-cell divider).  pane B gets the rest.
\   - If ratio is 0 or exceeds the available space it is clamped.
\
\  The widget itself does NOT draw child widgets — that is the
\  caller's responsibility.  SPL-DRAW only renders the divider line
\  and marks the widget clean.  After a resize or ratio change, call
\  SPL-RECOMPUTE to rebuild the pane regions.
\
\  Descriptor layout (header + 5 cells = 80 bytes):
\   +0..+32  widget header (type=WDG-T-SPLIT)
\   +40      mode       SPL-H or SPL-V
\   +48      ratio      size of pane A (rows or cols)
\   +56      pane-a     sub-region for pane A
\   +64      pane-b     sub-region for pane B
\   +72      divider    codepoint for the divider character
\
\  Public API:
\   SPL-H          ( -- mode )   Horizontal split: A top, B bottom
\   SPL-V          ( -- mode )   Vertical split:   A left, B right
\   SPL-NEW        ( rgn mode ratio -- widget )
\   SPL-PANE-A     ( widget -- rgn )
\   SPL-PANE-B     ( widget -- rgn )
\   SPL-SET-RATIO  ( widget n -- )
\   SPL-RECOMPUTE  ( widget -- )
\   SPL-FREE       ( widget -- )
\ =================================================================

PROVIDED akashic-tui-split

REQUIRE ../widget.f
REQUIRE ../region.f
REQUIRE ../draw.f

\ =====================================================================
\  §1 — Constants
\ =====================================================================

0 CONSTANT SPL-H   \ horizontal: A on top, B on bottom
1 CONSTANT SPL-V   \ vertical:   A on left, B on right

\ Descriptor offsets
40 CONSTANT _SPL-O-MODE
48 CONSTANT _SPL-O-RATIO
56 CONSTANT _SPL-O-PANE-A
64 CONSTANT _SPL-O-PANE-B
72 CONSTANT _SPL-O-DIVIDER
80 CONSTANT _SPL-DESC-SIZE

\ Default divider characters
9474 CONSTANT _SPL-DIV-V   \ U+2502 │  (vertical line for SPL-V)
9472 CONSTANT _SPL-DIV-H   \ U+2500 ─  (horizontal line for SPL-H)

\ =====================================================================
\  §2 — Internal: Recompute pane regions
\ =====================================================================
\  Given the parent region geometry, derive pane-A and pane-B sub-
\  regions from the current mode and ratio.

: _SPL-CLAMP-RATIO  ( widget -- clamped-ratio )
    DUP _SPL-O-RATIO + @                 ( w ratio )
    SWAP DUP _SPL-O-MODE + @             ( ratio w mode )
    SPL-H = IF
        WDG-REGION RGN-H                 ( ratio h )
    ELSE
        WDG-REGION RGN-W                 ( ratio w )
    THEN
    1-                                    ( ratio avail )  \ minus divider
    DUP 0<= IF 2DROP 0 EXIT THEN         ( ratio avail )
    MIN                                   ( clamped )
    DUP 0< IF DROP 0 THEN ;

: SPL-RECOMPUTE  ( widget -- )
    DUP _SPL-CLAMP-RATIO                 ( w a-size )
    OVER _SPL-O-RATIO + @ OVER <> IF
        \ store clamped ratio back
        2DUP SWAP _SPL-O-RATIO + !
    THEN

    OVER _SPL-O-MODE + @ SPL-H = IF
        \ Horizontal: pane-A is top, pane-B is bottom
        \ pane-A: (parent 0 0 a-size w)
        OVER WDG-REGION                  ( w a-size rgn )
        0 0                              ( w a-size rgn 0 0 )
        3 PICK                           ( w a-size rgn 0 0 a-size )
        5 PICK WDG-REGION RGN-W          ( w a-size rgn 0 0 a-size w )
        RGN-SUB                           ( w a-size sub-a )
        2 PICK _SPL-O-PANE-A + !         ( w a-size )

        \ pane-B: (parent a-size+1 0 h-a-size-1 w)
        OVER WDG-REGION                  ( w a-size rgn )
        OVER 1+                           ( w a-size rgn row-b )
        0                                 ( w a-size rgn row-b 0 )
        4 PICK WDG-REGION RGN-H          ( w a-size rgn row-b 0 h )
        3 PICK - 1-                       ( w a-size rgn row-b 0 h-b )
        6 PICK WDG-REGION RGN-W          ( w a-size rgn row-b 0 h-b w )
        RGN-SUB                           ( w a-size sub-b )
        2 PICK _SPL-O-PANE-B + !         ( w a-size )
    ELSE
        \ Vertical: pane-A is left, pane-B is right
        \ pane-A: (parent 0 0 h a-size)
        OVER WDG-REGION                  ( w a-size rgn )
        0 0                              ( w a-size rgn 0 0 )
        4 PICK WDG-REGION RGN-H          ( w a-size rgn 0 0 h )
        3 PICK                            ( w a-size rgn 0 0 h a-size )
        RGN-SUB                           ( w a-size sub-a )
        2 PICK _SPL-O-PANE-A + !         ( w a-size )

        \ pane-B: (parent 0 a-size+1 h w-a-size-1)
        OVER WDG-REGION                  ( w a-size rgn )
        0                                 ( w a-size rgn 0 )
        OVER 1+                           ( w a-size rgn 0 col-b )
        \ Actually stack fix — need a-size from 4th
        \ Let me restructure: w a-size rgn
        >R >R                             ( w a-size  R: rgn 0 )
        \ wrong — let me redo this block cleanly
        R> R>                             ( w a-size rgn 0 )
        DROP                              ( w a-size rgn )

        \ pane-B for vertical: parent 0 (a-size+1) h (w - a-size - 1)
        0                                 ( w a-size rgn 0 )
        2 PICK 1+                         ( w a-size rgn 0 col-b )
        4 PICK WDG-REGION RGN-H          ( w a-size rgn 0 col-b h )
        5 PICK WDG-REGION RGN-W          ( w a-size rgn 0 col-b h total-w )
        4 PICK - 1-                       ( w a-size rgn 0 col-b h w-b )
        RGN-SUB                           ( w a-size sub-b )
        2 PICK _SPL-O-PANE-B + !         ( w a-size )
    THEN
    2DROP ;

\ =====================================================================
\  §3 — Draw handler
\ =====================================================================
\  Draws the divider line.  For H mode: a horizontal line across
\  the full width at row = a-size.  For V mode: a vertical line
\  down the full height at col = a-size.

: _SPL-DRAW  ( widget -- )
    DUP _SPL-O-RATIO + @                 ( w ratio )
    OVER _SPL-O-DIVIDER + @              ( w ratio cp )
    ROT DUP >R                           ( ratio cp w )
    _SPL-O-MODE + @                      ( ratio cp mode )
    SPL-H = IF
        \ Horizontal divider: DRW-HLINE ( cp row col len -- )
        7 DRW-FG! 0 DRW-BG! 0 DRW-ATTR!
        SWAP                              ( cp ratio )
        0                                 ( cp ratio 0 )
        R@ WDG-REGION RGN-W              ( cp ratio 0 len )
        DRW-HLINE
    ELSE
        \ Vertical divider: DRW-VLINE ( cp row col len -- )
        7 DRW-FG! 0 DRW-BG! 0 DRW-ATTR!
        SWAP                              ( cp ratio=col )
        0 SWAP                            ( cp 0 col )
        R@ WDG-REGION RGN-H              ( cp 0 col len )
        DRW-VLINE
    THEN
    R> DROP ;

\ =====================================================================
\  §4 — Event handler
\ =====================================================================
\  The split pane itself does not consume events.  Child widgets
\  should be given focus independently.

: _SPL-HANDLE  ( event widget -- 0 )
    2DROP 0 ;

\ =====================================================================
\  §5 — Constructor
\ =====================================================================

: SPL-NEW  ( rgn mode ratio -- widget )
    >R >R                                 ( rgn   R: ratio mode )
    _SPL-DESC-SIZE ALLOCATE
    0<> ABORT" SPL-NEW: alloc failed"     ( rgn desc )
    \ Header
    WDG-T-SPLIT     OVER _WDG-O-TYPE      + !
    SWAP             OVER _WDG-O-REGION    + !
    ['] _SPL-DRAW    OVER _WDG-O-DRAW-XT   + !
    ['] _SPL-HANDLE  OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                     OVER _WDG-O-FLAGS     + !
    \ Custom fields
    R>               OVER _SPL-O-MODE      + !    ( desc   R: ratio )
    R>               OVER _SPL-O-RATIO     + !    ( desc )
    0                OVER _SPL-O-PANE-A    + !
    0                OVER _SPL-O-PANE-B    + !
    \ Pick default divider based on mode
    DUP _SPL-O-MODE + @ SPL-H = IF
        _SPL-DIV-H
    ELSE
        _SPL-DIV-V
    THEN
                     OVER _SPL-O-DIVIDER   + !
    \ Build initial pane regions
    DUP SPL-RECOMPUTE ;

\ =====================================================================
\  §6 — Accessors & Mutators
\ =====================================================================

: SPL-PANE-A  ( widget -- rgn )
    _SPL-O-PANE-A + @ ;

: SPL-PANE-B  ( widget -- rgn )
    _SPL-O-PANE-B + @ ;

: SPL-SET-RATIO  ( widget n -- )
    OVER _SPL-O-RATIO + !
    DUP SPL-RECOMPUTE
    WDG-DIRTY ;

\ =====================================================================
\  §7 — Destructor
\ =====================================================================

: SPL-FREE  ( widget -- )
    DUP SPL-PANE-A ?DUP IF RGN-FREE THEN
    DUP SPL-PANE-B ?DUP IF RGN-FREE THEN
    FREE ;

\ =====================================================================
\  §8 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _spl-guard

' SPL-NEW        CONSTANT _spl-new-xt
' SPL-PANE-A     CONSTANT _spl-pane-a-xt
' SPL-PANE-B     CONSTANT _spl-pane-b-xt
' SPL-SET-RATIO  CONSTANT _spl-set-ratio-xt
' SPL-RECOMPUTE  CONSTANT _spl-recompute-xt
' SPL-FREE       CONSTANT _spl-free-xt

: SPL-NEW        _spl-new-xt        _spl-guard WITH-GUARD ;
: SPL-PANE-A     _spl-pane-a-xt     _spl-guard WITH-GUARD ;
: SPL-PANE-B     _spl-pane-b-xt     _spl-guard WITH-GUARD ;
: SPL-SET-RATIO  _spl-set-ratio-xt  _spl-guard WITH-GUARD ;
: SPL-RECOMPUTE  _spl-recompute-xt  _spl-guard WITH-GUARD ;
: SPL-FREE       _spl-free-xt       _spl-guard WITH-GUARD ;
[THEN] [THEN]
