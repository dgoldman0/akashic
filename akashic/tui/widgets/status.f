\ =================================================================
\  status.f  —  Status Bar Widget
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SBAR- / _SBAR-
\  Depends on: akashic-tui-widget, akashic-tui-draw
\
\  A single-row bar for persistent status information.
\  Left-aligned text grows from column 0; right-aligned text is
\  flush to the right edge.  The bar fills its entire region width
\  with a background color, then overlays the two text spans.
\
\  The widget does not handle key events (returns 0).
\
\  Descriptor layout (header + 5 cells = 80 bytes):
\   +0..+32  widget header (type=WDG-T-STATUS)
\   +40      left-addr    Left text address
\   +48      left-len     Left text length
\   +56      right-addr   Right text address
\   +64      right-len    Right text length
\   +72      bg-style     Packed: fg in low 8 bits, bg in bits 8-15,
\                         attrs in bits 16-23
\
\  Public API:
\   SBAR-NEW      ( rgn -- widget )
\   SBAR-LEFT!    ( widget addr len -- )
\   SBAR-RIGHT!   ( widget addr len -- )
\   SBAR-STYLE!   ( widget fg bg attrs -- )
\   SBAR-FREE     ( widget -- )
\ =================================================================

PROVIDED akashic-tui-status

REQUIRE ../widget.f
REQUIRE ../draw.f

\ =====================================================================
\  §1 — Descriptor layout
\ =====================================================================

40 CONSTANT _SBAR-O-LEFT-A
48 CONSTANT _SBAR-O-LEFT-L
56 CONSTANT _SBAR-O-RIGHT-A
64 CONSTANT _SBAR-O-RIGHT-L
72 CONSTANT _SBAR-O-STYLE
80 CONSTANT _SBAR-DESC-SIZE

\ Default style: white on blue, no attrs
\ Encoding: fg | (bg << 8) | (attrs << 16)
: _SBAR-PACK-STYLE  ( fg bg attrs -- packed )
    16 LSHIFT >R
    8 LSHIFT OR
    R> OR ;

: _SBAR-UNPACK-STYLE  ( packed -- fg bg attrs )
    DUP 255 AND            \ fg
    SWAP DUP 8 RSHIFT 255 AND   \ bg
    SWAP 16 RSHIFT 255 AND ;    \ attrs

\ =====================================================================
\  §2 — Draw handler
\ =====================================================================

: _SBAR-DRAW  ( widget -- )
    DUP _SBAR-O-STYLE + @
    _SBAR-UNPACK-STYLE DRW-STYLE!        ( widget )

    \ Fill entire row 0 with spaces (background)
    DUP WDG-REGION RGN-W                  ( widget w )
    32 0 0 ROT DRW-HLINE                  ( widget )  \ space across row 0

    \ Draw left text
    DUP _SBAR-O-LEFT-L + @ ?DUP IF       ( widget left-l )
        OVER _SBAR-O-LEFT-A + @          ( widget left-l left-a )
        SWAP 0 0 DRW-TEXT                 ( widget )
    THEN

    \ Draw right text
    DUP _SBAR-O-RIGHT-L + @ ?DUP IF      ( widget right-l )
        OVER _SBAR-O-RIGHT-A + @         ( widget right-l right-a )
        OVER                              ( widget right-l right-a right-l )
        >R >R                             ( widget right-l  R: right-a right-l )
        OVER WDG-REGION RGN-W            ( widget right-l w )
        SWAP -                            ( widget col )
        0 SWAP                            ( widget row=0 col )
        R> R> 2SWAP DRW-TEXT              ( widget )
    THEN
    DROP ;

\ =====================================================================
\  §3 — Event handler (no-op)
\ =====================================================================

: _SBAR-HANDLE  ( event widget -- 0 )
    2DROP 0 ;

\ =====================================================================
\  §4 — Constructor
\ =====================================================================

: SBAR-NEW  ( rgn -- widget )
    _SBAR-DESC-SIZE ALLOCATE
    0<> ABORT" SBAR-NEW: alloc failed"
    \ Fill header
    WDG-T-STATUS   OVER _WDG-O-TYPE      + !
    SWAP           OVER _WDG-O-REGION    + !
    ['] _SBAR-DRAW OVER _WDG-O-DRAW-XT   + !
    ['] _SBAR-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                   OVER _WDG-O-FLAGS     + !
    \ Init custom fields
    0              OVER _SBAR-O-LEFT-A  + !
    0              OVER _SBAR-O-LEFT-L  + !
    0              OVER _SBAR-O-RIGHT-A + !
    0              OVER _SBAR-O-RIGHT-L + !
    \ Default style: white (7) on blue (4), no attrs
    7 4 0 _SBAR-PACK-STYLE
                   OVER _SBAR-O-STYLE   + ! ;

\ =====================================================================
\  §5 — Mutators
\ =====================================================================

: SBAR-LEFT!  ( widget addr len -- )
    ROT DUP >R
    _SBAR-O-LEFT-L + !
    R@ _SBAR-O-LEFT-A + !
    R> WDG-DIRTY ;

: SBAR-RIGHT!  ( widget addr len -- )
    ROT DUP >R
    _SBAR-O-RIGHT-L + !
    R@ _SBAR-O-RIGHT-A + !
    R> WDG-DIRTY ;

: SBAR-STYLE!  ( widget fg bg attrs -- )
    _SBAR-PACK-STYLE
    SWAP DUP >R
    _SBAR-O-STYLE + !
    R> WDG-DIRTY ;

\ =====================================================================
\  §6 — Destructor
\ =====================================================================

: SBAR-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\  §7 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _sbar-guard

' SBAR-NEW    CONSTANT _sbar-new-xt
' SBAR-LEFT!  CONSTANT _sbar-left-xt
' SBAR-RIGHT! CONSTANT _sbar-right-xt
' SBAR-STYLE! CONSTANT _sbar-style-xt
' SBAR-FREE   CONSTANT _sbar-free-xt

: SBAR-NEW    _sbar-new-xt    _sbar-guard WITH-GUARD ;
: SBAR-LEFT!  _sbar-left-xt   _sbar-guard WITH-GUARD ;
: SBAR-RIGHT! _sbar-right-xt  _sbar-guard WITH-GUARD ;
: SBAR-STYLE! _sbar-style-xt  _sbar-guard WITH-GUARD ;
: SBAR-FREE   _sbar-free-xt   _sbar-guard WITH-GUARD ;
[THEN] [THEN]
