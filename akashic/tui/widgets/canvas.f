\ =================================================================
\  canvas.f  —  Braille Canvas Widget with Per-Cell Colour
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: CVS- / _CVS-
\  Depends on: akashic-tui-widget, akashic-tui-draw, akashic-tui-region
\
\  A free-form drawing surface using Unicode Braille characters
\  (U+2800..U+28FF) for sub-cell pixel resolution.
\
\  Each terminal cell maps to a 2×4 dot block (2 cols × 4 rows),
\  giving 2× horizontal and 4× vertical resolution vs plain chars.
\
\  Braille dot numbering per cell:
\       Col 0   Col 1
\  Row 0  1       4        bit 0   bit 3
\  Row 1  2       5        bit 1   bit 4
\  Row 2  3       6        bit 2   bit 5
\  Row 3  7       8        bit 6   bit 7
\
\  Codepoint = 0x2800 + assembled-8-bit-value
\
\  Colour model
\  ~~~~~~~~~~~~~
\  Per-dot colour is impossible — a Braille glyph is one terminal
\  cell with one fg and one bg.  Instead we maintain a colour map
\  with one (fg, bg) pair per terminal cell.  Drawing operations
\  stamp the current *pen colour* into the colour map for every
\  cell they touch.
\
\  Two buffers:
\   • dot-buf   — 1 bit per dot  (ceil(dot-w × dot-h / 8) bytes)
\   • col-buf   — 2 bytes per terminal cell (fg, bg) packed
\                  (cell-cols × cell-rows × 2 bytes)
\
\  Descriptor layout (header + 7 cells = 96 bytes):
\   +0..+32  widget header (type=WDG-T-CANVAS)
\   +40  dot-buf   Allocated bit array (1 bit per dot)
\   +48  dot-w     Dot width   = region-w × 2
\   +56  dot-h     Dot height  = region-h × 4
\   +64  col-buf   Allocated colour map (2 bytes per cell)
\   +72  pen-fg    Current pen foreground (0-255)
\   +80  pen-bg    Current pen background (0-255)
\   +88  cell-w    Terminal cell columns (= region-w)
\
\  Public API:
\   CVS-NEW        ( rgn -- widget )
\   CVS-CLEAR      ( widget -- )
\   CVS-PEN!       ( widget fg bg -- )    Set pen colour
\   CVS-COLOR!     ( widget col row fg bg -- )  Set cell colour directly
\   CVS-SET        ( widget x y -- )      Set dot, stamp pen colour
\   CVS-CLR        ( widget x y -- )      Clear dot
\   CVS-GET        ( widget x y -- flag ) Test dot
\   CVS-LINE       ( widget x0 y0 x1 y1 -- )
\   CVS-RECT       ( widget x y w h -- )
\   CVS-FILL-RECT  ( widget x y w h -- )
\   CVS-CIRCLE     ( widget cx cy r -- )
\   CVS-TEXT       ( widget x y addr len -- )
\   CVS-PLOT       ( widget data count x-scale y-scale -- )
\   CVS-FREE       ( widget -- )
\ =================================================================

PROVIDED akashic-tui-canvas

REQUIRE ../widget.f
REQUIRE ../region.f
REQUIRE ../draw.f

\ Portable polyfill — not in all Forth kernels.
[DEFINED] 3DROP [IF] [ELSE]
: 3DROP  ( a b c -- )  DROP 2DROP ;
[THEN]

\ =====================================================================
\  §1 — Descriptor offsets
\ =====================================================================

40 CONSTANT _CVS-O-BUF
48 CONSTANT _CVS-O-DW
56 CONSTANT _CVS-O-DH
64 CONSTANT _CVS-O-COL
72 CONSTANT _CVS-O-PFG
80 CONSTANT _CVS-O-PBG
88 CONSTANT _CVS-O-CW
96 CONSTANT _CVS-DESC-SZ

\ =====================================================================
\  §2 — Braille encoding table
\ =====================================================================

10240 CONSTANT _CVS-BASE   \ U+2800

\ Index = dy * 2 + dx → bit position in 8-bit Braille value.
CREATE _CVS-BMAP  8 CELLS ALLOT
: _CVS-BMAP-INIT
    0 _CVS-BMAP 0 CELLS + !   \ dx=0 dy=0 → bit 0
    3 _CVS-BMAP 1 CELLS + !   \ dx=1 dy=0 → bit 3
    1 _CVS-BMAP 2 CELLS + !   \ dx=0 dy=1 → bit 1
    4 _CVS-BMAP 3 CELLS + !   \ dx=1 dy=1 → bit 4
    2 _CVS-BMAP 4 CELLS + !   \ dx=0 dy=2 → bit 2
    5 _CVS-BMAP 5 CELLS + !   \ dx=1 dy=2 → bit 5
    6 _CVS-BMAP 6 CELLS + !   \ dx=0 dy=3 → bit 6
    7 _CVS-BMAP 7 CELLS + !   \ dx=1 dy=3 → bit 7
;
_CVS-BMAP-INIT

: _CVS-DOTBIT  ( dx dy -- bit-pos )
    2 * + CELLS _CVS-BMAP + @ ;

\ =====================================================================
\  §3 — Dot buffer helpers
\ =====================================================================

\ Non-destructive bounds check.
: _CVS-OK?  ( w x y -- w x y flag )
    2 PICK _CVS-O-DW + @ 2 PICK >       \ x < dot-w
    3 PICK _CVS-O-DH + @ 2 PICK >       \ y < dot-h  (3 PICK: flag shifted stack)
    AND ;

\ Dot (x,y) → byte address + bit mask.  Consumes widget.
: _CVS-ADR  ( w x y -- addr mask )
    2 PICK _CVS-O-DW + @ * +            ( w lin )
    DUP 3 RSHIFT                          ( w lin boff )
    2 PICK _CVS-O-BUF + @ +             ( w lin addr )
    SWAP 7 AND 1 SWAP LSHIFT             ( w addr mask )
    ROT DROP ;

\ =====================================================================
\  §4 — Colour map helpers
\ =====================================================================
\  The colour buffer stores 2 bytes per terminal cell:
\    byte 0 = fg,  byte 1 = bg
\  Address = col-buf + (cell-row * cell-w + cell-col) * 2

\ ( w cell-col cell-row -- col-addr )  Address of the 2-byte pair.
: _CVS-CADR  ( w cc cr -- addr )
    2 PICK _CVS-O-CW + @ * +            ( w linear )
    2 * SWAP _CVS-O-COL + @ + ;

\ Stamp the current pen colour into the cell containing dot (x,y).
\ Does NOT consume widget.
: _CVS-STAMP  ( w x y -- )
    4 / >R 2 / R>                        ( w cell-col cell-row )
    2 PICK -ROT _CVS-CADR                ( w addr )
    OVER _CVS-O-PFG + @ OVER C!         ( w addr )  \ fg
    1+ SWAP _CVS-O-PBG + @ SWAP C! ;    ( )         \ bg

\ =====================================================================
\  §5 — Public dot operations
\ =====================================================================

: CVS-SET  ( w x y -- )
    _CVS-OK? 0= IF 3DROP EXIT THEN
    2 PICK 2 PICK 2 PICK _CVS-STAMP     \ stamp pen colour first
    _CVS-ADR  OVER C@ OR SWAP C! ;

: CVS-CLR  ( w x y -- )
    _CVS-OK? 0= IF 3DROP EXIT THEN
    _CVS-ADR  INVERT OVER C@ AND SWAP C! ;

: CVS-GET  ( w x y -- flag )
    _CVS-OK? 0= IF 3DROP 0 EXIT THEN
    _CVS-ADR  SWAP C@ AND 0<> ;

\ =====================================================================
\  §6 — Pen & direct colour access
\ =====================================================================

: CVS-PEN!  ( w fg bg -- )
    ROT DUP >R _CVS-O-PBG + !
    R@ _CVS-O-PFG + !  R> DROP ;

: CVS-COLOR!  ( w col row fg bg -- )
    >R >R                                 ( w col row   R: bg fg )
    2 PICK -ROT _CVS-CADR                ( w addr   R: bg fg )
    R> OVER C!                            ( w addr   R: bg )
    1+ R> SWAP C! DROP ;

\ =====================================================================
\  §7 — Draw handler: dot + colour buffers → screen
\ =====================================================================

\ Braille codepoint for terminal cell (col, row).
: _CVS-CELL-CP  ( w col row -- cp )
    SWAP 2 * SWAP 4 *                   ( w dxb dyb )
    0                                     ( w dxb dyb acc )
    4 0 DO                                \ dy = I
        2 0 DO                            \ dx = I (inner)
            3 PICK I +                    ( ... dx )
            3 PICK J +                    ( ... dx dy )
            6 PICK -ROT                   ( ... w' dx dy )
            _CVS-OK? IF
                _CVS-ADR SWAP C@ AND 0<> IF
                    I J _CVS-DOTBIT
                    1 SWAP LSHIFT OR
                ELSE DROP THEN
            ELSE 3DROP THEN
        LOOP
    LOOP
    _CVS-BASE +
    >R 2DROP DROP R> ;

: _CVS-DRAW  ( widget -- )
    DUP WDG-REGION RGN-H DUP 0> IF 0 DO  \ row = J
        DUP WDG-REGION RGN-W DUP 0> IF 0 DO  \ col = I
            \ Set per-cell colour from colour map
            DUP I J 2 PICK -ROT _CVS-CADR  ( w addr )
            DUP C@ DRW-FG!               ( w addr )
            1+ C@ DRW-BG!                ( w )
            0 DRW-ATTR!
            \ Emit Braille codepoint
            DUP I J _CVS-CELL-CP          ( w cp )
            J I DRW-CHAR                  ( w )
        LOOP ELSE DROP THEN
    LOOP ELSE DROP THEN
    DROP ;

\ =====================================================================
\  §8 — Event handler (no-op)
\ =====================================================================

: _CVS-HANDLE  ( ev w -- 0 )  2DROP 0 ;

\ =====================================================================
\  §9 — Constructor / Destructor / Clear
\ =====================================================================

: CVS-NEW  ( rgn -- widget )
    _CVS-DESC-SZ ALLOCATE
    0<> ABORT" CVS-NEW: alloc"
    WDG-T-CANVAS   OVER _WDG-O-TYPE      + !
    SWAP            OVER _WDG-O-REGION    + !
    ['] _CVS-DRAW   OVER _WDG-O-DRAW-XT   + !
    ['] _CVS-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                    OVER _WDG-O-FLAGS     + !
    \ Compute dimensions
    DUP _WDG-O-REGION + @ RGN-W          ( desc cw )
    OVER _CVS-O-CW + !                   ( desc )
    DUP _CVS-O-CW + @ 2 *
    OVER _CVS-O-DW + !
    DUP _WDG-O-REGION + @ RGN-H 4 *
    OVER _CVS-O-DH + !
    \ Allocate dot buffer: ceil(dw * dh / 8) bytes
    DUP _CVS-O-DW + @ OVER _CVS-O-DH + @ *
    7 + 3 RSHIFT                          ( desc dot-bytes )
    DUP >R ALLOCATE 0<> ABORT" CVS-NEW: dot-buf"
    DUP R> 0 FILL
    OVER _CVS-O-BUF + !                  ( desc )
    \ Allocate colour buffer: cw * ch * 2 bytes
    DUP _CVS-O-CW + @
    OVER _WDG-O-REGION + @ RGN-H *       ( desc cells )
    2 *                                   ( desc col-bytes )
    ALLOCATE 0<> ABORT" CVS-NEW: col-buf"
    OVER _CVS-O-COL + !                  ( desc )  \ store pointer
    \ Init colour map: default white(7) on black(0) per cell
    DUP _CVS-O-COL + @                   ( desc buf )
    OVER _CVS-O-CW + @
    2 PICK _WDG-O-REGION + @ RGN-H *     ( desc buf cells )
    BEGIN DUP 0> WHILE
        7 2 PICK C!                       \ fg = 7
        0 2 PICK 1+ C!                   \ bg = 0
        SWAP 2 + SWAP 1-                  \ advance buf by 2, decrement count
    REPEAT
    2DROP                                 ( desc )
    \ Default pen: white on black
    7 OVER _CVS-O-PFG + !
    0 OVER _CVS-O-PBG + ! ;

: CVS-FREE  ( w -- )
    DUP _CVS-O-BUF + @ FREE
    DUP _CVS-O-COL + @ FREE
    FREE ;

: CVS-CLEAR  ( w -- )
    \ Clear dot buffer
    DUP _CVS-O-BUF + @
    OVER _CVS-O-DW + @ 2 PICK _CVS-O-DH + @ *
    7 + 3 RSHIFT 0 FILL
    \ Reset colour map to current pen
    DUP _CVS-O-COL + @                   ( w buf )
    OVER _CVS-O-CW + @
    2 PICK _WDG-O-REGION + @ RGN-H *     ( w buf cells )
    BEGIN DUP 0> WHILE
        2 PICK _CVS-O-PFG + @ 2 PICK C!  ( w buf cells )  \ fg
        2 PICK _CVS-O-PBG + @ 2 PICK 1+ C!               \ bg
        1- SWAP 2 + SWAP                  ( w buf+2 cells-1 )
    REPEAT
    DROP DROP WDG-DIRTY ;

\ =====================================================================
\  §10 — Bresenham line (scratch variables)
\ =====================================================================

VARIABLE _LX0  VARIABLE _LY0  VARIABLE _LX1  VARIABLE _LY1
VARIABLE _LDX  VARIABLE _LDY  VARIABLE _LSX  VARIABLE _LSY
VARIABLE _LERR VARIABLE _LWG

: CVS-LINE  ( w x0 y0 x1 y1 -- )
    _LY1 ! _LX1 ! _LY0 ! _LX0 ! _LWG !
    _LX1 @ _LX0 @ - ABS            _LDX !
    _LY1 @ _LY0 @ - ABS NEGATE     _LDY !
    _LX0 @ _LX1 @ < IF 1 ELSE -1 THEN _LSX !
    _LY0 @ _LY1 @ < IF 1 ELSE -1 THEN _LSY !
    _LDX @ _LDY @ +                _LERR !
    BEGIN
        _LWG @ _LX0 @ _LY0 @ CVS-SET
        _LX0 @ _LX1 @ = _LY0 @ _LY1 @ = AND IF EXIT THEN
        _LERR @ 2 *                      ( e2 )
        DUP _LDY @ >= IF
            _LDY @ _LERR +!
            _LSX @ _LX0 +!
        THEN
        _LDX @ <= IF
            _LDX @ _LERR +!
            _LSY @ _LY0 +!
        THEN
    AGAIN ;

\ =====================================================================
\  §11 — Rectangle
\ =====================================================================

VARIABLE _RX  VARIABLE _RY  VARIABLE _RW  VARIABLE _RH

: CVS-RECT  ( w x y ww hh -- )
    _RH ! _RW ! _RY ! _RX !
    DUP _RX @ _RY @
        _RX @ _RW @ + 1-  _RY @                          CVS-LINE
    DUP _RX @ _RY @ _RH @ + 1-
        _RX @ _RW @ + 1-  _RY @ _RH @ + 1-              CVS-LINE
    DUP _RX @ _RY @ 1+
        _RX @              _RY @ _RH @ + 2 -             CVS-LINE
        _RX @ _RW @ + 1-  _RY @ 1+
        _RX @ _RW @ + 1-  _RY @ _RH @ + 2 -             CVS-LINE ;

: CVS-FILL-RECT  ( w x y ww hh -- )
    _RH ! _RW ! _RY ! _RX !
    _RH @ DUP 0> IF 0 DO
        _RW @ DUP 0> IF 0 DO
            DUP _RX @ I + _RY @ J + CVS-SET
        LOOP ELSE DROP THEN
    LOOP ELSE DROP THEN DROP ;

\ =====================================================================
\  §12 — Midpoint circle
\ =====================================================================

VARIABLE _CCX  VARIABLE _CCY
VARIABLE _CDX  VARIABLE _CDY  VARIABLE _CD

: _CVS-P8  ( w -- )
    \ Plot 8 octant-symmetric points around (_CCX, _CCY).
    DUP _CCX @ _CDX @ +  _CCY @ _CDY @ +  CVS-SET
    DUP _CCX @ _CDX @ -  _CCY @ _CDY @ +  CVS-SET
    DUP _CCX @ _CDX @ +  _CCY @ _CDY @ -  CVS-SET
    DUP _CCX @ _CDX @ -  _CCY @ _CDY @ -  CVS-SET
    DUP _CCX @ _CDY @ +  _CCY @ _CDX @ +  CVS-SET
    DUP _CCX @ _CDY @ -  _CCY @ _CDX @ +  CVS-SET
    DUP _CCX @ _CDY @ +  _CCY @ _CDX @ -  CVS-SET
        _CCX @ _CDY @ -  _CCY @ _CDX @ -  CVS-SET ;

: CVS-CIRCLE  ( w cx cy r -- )
    >R _CCY ! _CCX !                     ( w   R: r )
    0 _CDX !  R@ _CDY !
    1 R> - _CD !
    BEGIN _CDX @ _CDY @ <= WHILE
        DUP _CVS-P8
        _CD @ 0< IF
            _CDX @ 2 * 3 + _CD +!
        ELSE
            _CDX @ _CDY @ - 2 * 5 + _CD +!
            -1 _CDY +!
        THEN
        1 _CDX +!
    REPEAT DROP ;

\ =====================================================================
\  §13 — Text placement
\ =====================================================================

: CVS-TEXT  ( w x y addr len -- )
    \ Place text at dot coords, snapped to cell grid.
    >R >R                                 ( w x y   R: len addr )
    4 / >R 2 / R>                         ( w cc cr   R: len addr )
    R> R> 2OVER                           ( w cc cr addr len cr cc )
    DRW-TEXT  2DROP DROP ;

\ =====================================================================
\  §14 — Plot (connected line graph from data array)
\ =====================================================================

VARIABLE _PD  VARIABLE _PC  VARIABLE _PXS  VARIABLE _PYS

: CVS-PLOT  ( w data count x-scale y-scale -- )
    _PYS ! _PXS ! _PC ! _PD !
    _PC @ 2 < IF DROP EXIT THEN
    _PC @ 1- 0 DO
        DUP
        I _PXS @ *
        _PD @ I CELLS + @ _PYS @ /
        I 1+ _PXS @ *
        _PD @ I 1+ CELLS + @ _PYS @ /
        CVS-LINE
    LOOP DROP ;

\ =====================================================================
\  §15 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _cvs-guard

' CVS-NEW       CONSTANT _cvs-new-xt
' CVS-CLEAR     CONSTANT _cvs-clear-xt
' CVS-PEN!      CONSTANT _cvs-pen-xt
' CVS-COLOR!    CONSTANT _cvs-color-xt
' CVS-SET       CONSTANT _cvs-set-xt
' CVS-CLR       CONSTANT _cvs-clr-xt
' CVS-GET       CONSTANT _cvs-get-xt
' CVS-LINE      CONSTANT _cvs-line-xt
' CVS-RECT      CONSTANT _cvs-rect-xt
' CVS-FILL-RECT CONSTANT _cvs-fill-rect-xt
' CVS-CIRCLE    CONSTANT _cvs-circle-xt
' CVS-TEXT      CONSTANT _cvs-text-xt
' CVS-PLOT      CONSTANT _cvs-plot-xt
' CVS-FREE      CONSTANT _cvs-free-xt

: CVS-NEW       _cvs-new-xt       _cvs-guard WITH-GUARD ;
: CVS-CLEAR     _cvs-clear-xt     _cvs-guard WITH-GUARD ;
: CVS-PEN!      _cvs-pen-xt       _cvs-guard WITH-GUARD ;
: CVS-COLOR!    _cvs-color-xt     _cvs-guard WITH-GUARD ;
: CVS-SET       _cvs-set-xt       _cvs-guard WITH-GUARD ;
: CVS-CLR       _cvs-clr-xt       _cvs-guard WITH-GUARD ;
: CVS-GET       _cvs-get-xt       _cvs-guard WITH-GUARD ;
: CVS-LINE      _cvs-line-xt      _cvs-guard WITH-GUARD ;
: CVS-RECT      _cvs-rect-xt      _cvs-guard WITH-GUARD ;
: CVS-FILL-RECT _cvs-fill-rect-xt _cvs-guard WITH-GUARD ;
: CVS-CIRCLE    _cvs-circle-xt    _cvs-guard WITH-GUARD ;
: CVS-TEXT      _cvs-text-xt      _cvs-guard WITH-GUARD ;
: CVS-PLOT      _cvs-plot-xt      _cvs-guard WITH-GUARD ;
: CVS-FREE      _cvs-free-xt      _cvs-guard WITH-GUARD ;
[THEN] [THEN]
