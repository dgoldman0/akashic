\ draw.f — 2D Drawing Primitives for Akashic render pipeline
\ Part of Akashic render library for Megapad-64 / KDOS
\
\ Immediate-mode 2D drawing API that writes to a surface.
\ Provides filled/outlined shapes, Bresenham lines, Bézier strokes,
\ path-based filling, glyph and text rendering.
\
\ All coordinate arguments are integer pixels unless noted otherwise.
\ Color arguments are packed RGBA8888 (same as SURF-PIXEL!).
\
\ Prefix: DRAW-   (public API)
\         _DRAW-  (internal helpers)
\
\ Load with:   REQUIRE render/draw.f
\
\ Dependencies:
\   akashic-surface   — pixel buffer target
\   akashic-color     — color packing (already loaded by surface)
\   akashic-bezier    — Bézier flattening
\   akashic-raster    — scanline edge filling (for path API)
\   akashic-cache     — glyph bitmap cache
\   akashic-layout    — text measurement / cursor
\   akashic-utf8      — UTF-8 codepoint iteration
\
\ === Public API ===
\   DRAW-RECT          ( surf x y w h rgba -- )         filled rectangle
\   DRAW-RECT-OUTLINE  ( surf x y w h rgba thick -- )   rectangle outline
\   DRAW-HLINE         ( surf x y len rgba -- )         horizontal line
\   DRAW-VLINE         ( surf x y len rgba -- )         vertical line
\   DRAW-LINE          ( surf x0 y0 x1 y1 rgba -- )     Bresenham line
\   DRAW-CIRCLE        ( surf cx cy r rgba -- )         filled circle
\   DRAW-CIRCLE-OUTLINE ( surf cx cy r rgba -- )        circle outline
\   DRAW-ELLIPSE       ( surf cx cy rx ry rgba -- )     filled ellipse
\   DRAW-TRIANGLE      ( surf x0 y0 x1 y1 x2 y2 rgba -- ) filled triangle
\   DRAW-BEZIER-QUAD   ( surf x0 y0 x1 y1 x2 y2 rgba -- ) quad Bézier stroke
\   DRAW-BEZIER-CUBIC  ( surf x0 y0 x1 y1 x2 y2 x3 y3 rgba -- ) cubic Bézier
\   DRAW-PATH-BEGIN    ( -- )                            start path
\   DRAW-PATH-MOVE     ( x y -- )                       move to
\   DRAW-PATH-LINE     ( x y -- )                       line to
\   DRAW-PATH-QUAD     ( cx cy x y -- )                 quad Bézier to
\   DRAW-PATH-CUBIC    ( c1x c1y c2x c2y x y -- )      cubic Bézier to
\   DRAW-PATH-CLOSE    ( -- )                            close sub-path
\   DRAW-PATH-FILL     ( surf rgba -- )                  fill path (even-odd)
\   DRAW-PATH-STROKE   ( surf rgba -- )                  stroke path
\   DRAW-GLYPH         ( surf glyph-id size x y rgba -- ) render glyph
\   DRAW-TEXT           ( surf addr len x y size rgba -- ) render UTF-8 string

REQUIRE surface.f
REQUIRE ../math/bezier.f
REQUIRE ../font/raster.f
REQUIRE ../font/cache.f
REQUIRE ../text/layout.f
REQUIRE ../text/utf8.f
REQUIRE ../math/simd.f

PROVIDED akashic-draw

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _DRAW-SURF
VARIABLE _DRAW-RGBA
VARIABLE _DRAW-X0
VARIABLE _DRAW-Y0
VARIABLE _DRAW-X1
VARIABLE _DRAW-Y1
VARIABLE _DRAW-X2
VARIABLE _DRAW-Y2
VARIABLE _DRAW-X3
VARIABLE _DRAW-Y3
VARIABLE _DRAW-DX
VARIABLE _DRAW-DY
VARIABLE _DRAW-SX
VARIABLE _DRAW-SY
VARIABLE _DRAW-ERR
VARIABLE _DRAW-E2
VARIABLE _DRAW-W
VARIABLE _DRAW-H
VARIABLE _DRAW-R
VARIABLE _DRAW-RX
VARIABLE _DRAW-RY
VARIABLE _DRAW-D
VARIABLE _DRAW-CNT
VARIABLE _DRAW-TMP
VARIABLE _DRAW-THICK

\ =====================================================================
\  DRAW-RECT — Filled rectangle
\ =====================================================================
\  ( surf x y w h rgba -- )

: DRAW-RECT  ( surf x y w h rgba -- )
    SURF-FILL-RECT ;

\ =====================================================================
\  DRAW-HLINE — Horizontal line
\ =====================================================================
\  ( surf x y len rgba -- )

: DRAW-HLINE  ( surf x y len rgba -- )
    SURF-HLINE ;

\ =====================================================================
\  DRAW-VLINE — Vertical line
\ =====================================================================
\  ( surf x y len rgba -- )
\  Draws a vertical line of `len` pixels downward from (x, y).

: DRAW-VLINE  ( surf x y len rgba -- )
    _DRAW-RGBA !  _DRAW-CNT !  _DRAW-Y0 !  _DRAW-X0 !  _DRAW-SURF !
    _DRAW-CNT @ 0 DO
        _DRAW-SURF @
        _DRAW-X0 @
        _DRAW-Y0 @ I +
        _DRAW-RGBA @
        SURF-PIXEL!
    LOOP ;

\ =====================================================================
\  DRAW-RECT-OUTLINE — Rectangle outline
\ =====================================================================
\  ( surf x y w h rgba thick -- )
\  Draws a rectangle outline with given thickness.
\  Thickness grows inward.

: DRAW-RECT-OUTLINE  ( surf x y w h rgba thick -- )
    _DRAW-THICK !  _DRAW-RGBA !  _DRAW-H !  _DRAW-W !
    _DRAW-Y0 !  _DRAW-X0 !  _DRAW-SURF !

    \ Top edge: thick horizontal lines
    _DRAW-THICK @ 0 DO
        _DRAW-SURF @ _DRAW-X0 @ _DRAW-Y0 @ I +
        _DRAW-W @ _DRAW-RGBA @ SURF-HLINE
    LOOP

    \ Bottom edge
    _DRAW-THICK @ 0 DO
        _DRAW-SURF @ _DRAW-X0 @
        _DRAW-Y0 @ _DRAW-H @ + 1 - I -
        _DRAW-W @ _DRAW-RGBA @ SURF-HLINE
    LOOP

    \ Left edge (between top and bottom bands)
    _DRAW-THICK @ 0 DO
        _DRAW-SURF @
        _DRAW-X0 @ I +
        _DRAW-Y0 @ _DRAW-THICK @ +
        _DRAW-H @ _DRAW-THICK @ 2 * -
        _DRAW-RGBA @
        DRAW-VLINE
    LOOP

    \ Right edge
    _DRAW-THICK @ 0 DO
        _DRAW-SURF @
        _DRAW-X0 @ _DRAW-W @ + 1 - I -
        _DRAW-Y0 @ _DRAW-THICK @ +
        _DRAW-H @ _DRAW-THICK @ 2 * -
        _DRAW-RGBA @
        DRAW-VLINE
    LOOP ;

\ =====================================================================
\  DRAW-LINE — Bresenham's line algorithm
\ =====================================================================
\  ( surf x0 y0 x1 y1 rgba -- )

: DRAW-LINE  ( surf x0 y0 x1 y1 rgba -- )
    _DRAW-RGBA !  _DRAW-Y1 !  _DRAW-X1 !
    _DRAW-Y0 !  _DRAW-X0 !  _DRAW-SURF !

    \ dx = abs(x1 - x0)
    _DRAW-X1 @ _DRAW-X0 @ - ABS _DRAW-DX !
    \ dy = -abs(y1 - y0)
    _DRAW-Y1 @ _DRAW-Y0 @ - ABS NEGATE _DRAW-DY !

    \ sx = x0 < x1 ? 1 : -1
    _DRAW-X0 @ _DRAW-X1 @ < IF 1 ELSE -1 THEN _DRAW-SX !
    \ sy = y0 < y1 ? 1 : -1
    _DRAW-Y0 @ _DRAW-Y1 @ < IF 1 ELSE -1 THEN _DRAW-SY !

    \ err = dx + dy
    _DRAW-DX @ _DRAW-DY @ + _DRAW-ERR !

    BEGIN
        \ Plot pixel
        _DRAW-SURF @ _DRAW-X0 @ _DRAW-Y0 @ _DRAW-RGBA @ SURF-PIXEL!

        \ Check if we've reached the end
        _DRAW-X0 @ _DRAW-X1 @ = _DRAW-Y0 @ _DRAW-Y1 @ = AND IF EXIT THEN

        \ e2 = 2 * err
        _DRAW-ERR @ 2 * _DRAW-E2 !

        \ if e2 >= dy: err += dy, x0 += sx
        _DRAW-E2 @ _DRAW-DY @ >= IF
            _DRAW-DY @ _DRAW-ERR +!
            _DRAW-SX @ _DRAW-X0 +!
        THEN

        \ if e2 <= dx: err += dx, y0 += sy
        _DRAW-E2 @ _DRAW-DX @ <= IF
            _DRAW-DX @ _DRAW-ERR +!
            _DRAW-SY @ _DRAW-Y0 +!
        THEN
    AGAIN ;

\ =====================================================================
\  DRAW-CIRCLE — Filled circle (midpoint algorithm)
\ =====================================================================
\  ( surf cx cy r rgba -- )
\  Draws a filled circle using horizontal spans.

VARIABLE _DRAW-CX
VARIABLE _DRAW-CY
VARIABLE _DRAW-XI
VARIABLE _DRAW-YI

: DRAW-CIRCLE  ( surf cx cy r rgba -- )
    _DRAW-RGBA !  _DRAW-R !  _DRAW-CY !  _DRAW-CX !  _DRAW-SURF !

    _DRAW-R @ _DRAW-XI !
    0 _DRAW-YI !
    1 _DRAW-R @ - _DRAW-D !

    BEGIN
        _DRAW-XI @ _DRAW-YI @ >= WHILE

        \ Draw horizontal spans for 4 octants
        \ Span at y = cy + yi: from cx - xi to cx + xi
        _DRAW-SURF @
        _DRAW-CX @ _DRAW-XI @ -
        _DRAW-CY @ _DRAW-YI @ +
        _DRAW-XI @ 2 * 1 +
        _DRAW-RGBA @
        SURF-HLINE

        \ Span at y = cy - yi (skip if yi == 0 to avoid double-draw)
        _DRAW-YI @ 0<> IF
            _DRAW-SURF @
            _DRAW-CX @ _DRAW-XI @ -
            _DRAW-CY @ _DRAW-YI @ -
            _DRAW-XI @ 2 * 1 +
            _DRAW-RGBA @
            SURF-HLINE
        THEN

        \ Span at y = cy + xi (skip if xi == yi to avoid double-draw)
        _DRAW-XI @ _DRAW-YI @ <> IF
            _DRAW-SURF @
            _DRAW-CX @ _DRAW-YI @ -
            _DRAW-CY @ _DRAW-XI @ +
            _DRAW-YI @ 2 * 1 +
            _DRAW-RGBA @
            SURF-HLINE

            _DRAW-SURF @
            _DRAW-CX @ _DRAW-YI @ -
            _DRAW-CY @ _DRAW-XI @ -
            _DRAW-YI @ 2 * 1 +
            _DRAW-RGBA @
            SURF-HLINE
        THEN

        \ Update decision variable
        _DRAW-YI @ 1 + _DRAW-YI !
        _DRAW-D @ 0< IF
            _DRAW-YI @ 2 * 1 + _DRAW-D +!
        ELSE
            _DRAW-XI @ 1 - _DRAW-XI !
            _DRAW-YI @ _DRAW-XI @ - 2 * 1 + _DRAW-D +!
        THEN
    REPEAT ;

\ =====================================================================
\  DRAW-CIRCLE-OUTLINE — Circle outline (midpoint algorithm)
\ =====================================================================
\  ( surf cx cy r rgba -- )

: DRAW-CIRCLE-OUTLINE  ( surf cx cy r rgba -- )
    _DRAW-RGBA !  _DRAW-R !  _DRAW-CY !  _DRAW-CX !  _DRAW-SURF !

    _DRAW-R @ _DRAW-XI !
    0 _DRAW-YI !
    1 _DRAW-R @ - _DRAW-D !

    BEGIN
        _DRAW-XI @ _DRAW-YI @ >= WHILE

        \ Plot 8 symmetric points
        _DRAW-SURF @ _DRAW-CX @ _DRAW-XI @ + _DRAW-CY @ _DRAW-YI @ + _DRAW-RGBA @ SURF-PIXEL!
        _DRAW-SURF @ _DRAW-CX @ _DRAW-XI @ - _DRAW-CY @ _DRAW-YI @ + _DRAW-RGBA @ SURF-PIXEL!
        _DRAW-SURF @ _DRAW-CX @ _DRAW-XI @ + _DRAW-CY @ _DRAW-YI @ - _DRAW-RGBA @ SURF-PIXEL!
        _DRAW-SURF @ _DRAW-CX @ _DRAW-XI @ - _DRAW-CY @ _DRAW-YI @ - _DRAW-RGBA @ SURF-PIXEL!
        _DRAW-SURF @ _DRAW-CX @ _DRAW-YI @ + _DRAW-CY @ _DRAW-XI @ + _DRAW-RGBA @ SURF-PIXEL!
        _DRAW-SURF @ _DRAW-CX @ _DRAW-YI @ - _DRAW-CY @ _DRAW-XI @ + _DRAW-RGBA @ SURF-PIXEL!
        _DRAW-SURF @ _DRAW-CX @ _DRAW-YI @ + _DRAW-CY @ _DRAW-XI @ - _DRAW-RGBA @ SURF-PIXEL!
        _DRAW-SURF @ _DRAW-CX @ _DRAW-YI @ - _DRAW-CY @ _DRAW-XI @ - _DRAW-RGBA @ SURF-PIXEL!

        \ Update decision variable
        _DRAW-YI @ 1 + _DRAW-YI !
        _DRAW-D @ 0< IF
            _DRAW-YI @ 2 * 1 + _DRAW-D +!
        ELSE
            _DRAW-XI @ 1 - _DRAW-XI !
            _DRAW-YI @ _DRAW-XI @ - 2 * 1 + _DRAW-D +!
        THEN
    REPEAT ;

\ =====================================================================
\  DRAW-ELLIPSE — Filled ellipse (midpoint algorithm)
\ =====================================================================
\  ( surf cx cy rx ry rgba -- )
\  Uses the standard two-region midpoint ellipse algorithm.

VARIABLE _DRAW-RX2     \ rx²
VARIABLE _DRAW-RY2     \ ry²
VARIABLE _DRAW-PX      \ 2·ry²·x
VARIABLE _DRAW-PY      \ 2·rx²·y
VARIABLE _DRAW-P       \ decision parameter

: DRAW-ELLIPSE  ( surf cx cy rx ry rgba -- )
    _DRAW-RGBA !  _DRAW-RY !  _DRAW-RX !
    _DRAW-CY !  _DRAW-CX !  _DRAW-SURF !

    _DRAW-RX @ DUP * _DRAW-RX2 !
    _DRAW-RY @ DUP * _DRAW-RY2 !

    0 _DRAW-XI !
    _DRAW-RY @ _DRAW-YI !

    \ Region 1: slope < 1
    0 _DRAW-PX !
    _DRAW-RX2 @ _DRAW-RY @ 2 * * _DRAW-PY !

    \ Initial p = ry² - rx²·ry + rx²/4 (approximate with integers)
    _DRAW-RY2 @ _DRAW-RX2 @ _DRAW-RY @ * - _DRAW-RX2 @ 4 / + _DRAW-P !

    BEGIN
        _DRAW-PX @ _DRAW-PY @ <= WHILE

        \ Draw 4 horizontal spans
        _DRAW-SURF @
        _DRAW-CX @ _DRAW-XI @ -
        _DRAW-CY @ _DRAW-YI @ +
        _DRAW-XI @ 2 * 1 +
        _DRAW-RGBA @
        SURF-HLINE

        _DRAW-YI @ 0<> IF
            _DRAW-SURF @
            _DRAW-CX @ _DRAW-XI @ -
            _DRAW-CY @ _DRAW-YI @ -
            _DRAW-XI @ 2 * 1 +
            _DRAW-RGBA @
            SURF-HLINE
        THEN

        _DRAW-XI @ 1 + _DRAW-XI !
        _DRAW-RY2 @ 2 * _DRAW-PX +!

        _DRAW-P @ 0< IF
            _DRAW-PX @ _DRAW-RY2 @ + _DRAW-P +!
        ELSE
            _DRAW-YI @ 1 - _DRAW-YI !
            _DRAW-RX2 @ 2 * NEGATE _DRAW-PY +!
            _DRAW-PX @ _DRAW-RY2 @ + _DRAW-PY @ - _DRAW-P +!
        THEN
    REPEAT

    \ Region 2: slope >= 1
    _DRAW-RY2 @  _DRAW-XI @ DUP * *
    _DRAW-RX2 @  _DRAW-YI @ 1 - DUP * *  +
    _DRAW-RX2 @ _DRAW-RY2 @ *  -  _DRAW-P !

    BEGIN
        _DRAW-YI @ 0>= WHILE

        \ Draw horizontal spans
        _DRAW-SURF @
        _DRAW-CX @ _DRAW-XI @ -
        _DRAW-CY @ _DRAW-YI @ +
        _DRAW-XI @ 2 * 1 +
        _DRAW-RGBA @
        SURF-HLINE

        _DRAW-YI @ 0<> IF
            _DRAW-SURF @
            _DRAW-CX @ _DRAW-XI @ -
            _DRAW-CY @ _DRAW-YI @ -
            _DRAW-XI @ 2 * 1 +
            _DRAW-RGBA @
            SURF-HLINE
        THEN

        _DRAW-YI @ 1 - _DRAW-YI !
        _DRAW-RX2 @ 2 * NEGATE _DRAW-PY +!

        _DRAW-P @ 0> IF
            _DRAW-PY @ NEGATE _DRAW-RX2 @ + _DRAW-P +!
        ELSE
            _DRAW-XI @ 1 + _DRAW-XI !
            _DRAW-RY2 @ 2 * _DRAW-PX +!
            _DRAW-PX @ _DRAW-PY @ - _DRAW-RX2 @ + _DRAW-P +!
        THEN
    REPEAT ;

\ =====================================================================
\  DRAW-TRIANGLE — Filled triangle (scanline)
\ =====================================================================
\  ( surf x0 y0 x1 y1 x2 y2 rgba -- )
\  Flat-bottom / flat-top decomposition with scanline fills.

VARIABLE _DRAW-TRI-XA    \ sorted vertex A (top)
VARIABLE _DRAW-TRI-YA
VARIABLE _DRAW-TRI-XB    \ sorted vertex B (mid)
VARIABLE _DRAW-TRI-YB
VARIABLE _DRAW-TRI-XC    \ sorted vertex C (bottom)
VARIABLE _DRAW-TRI-YC
VARIABLE _DRAW-TRI-SL    \ left x (FP16)
VARIABLE _DRAW-TRI-SR    \ right x (FP16)
VARIABLE _DRAW-TRI-DL    \ left dx/dy (FP16)
VARIABLE _DRAW-TRI-DR    \ right dx/dy (FP16)
VARIABLE _DRAW-TRI-XL    \ integer left
VARIABLE _DRAW-TRI-XR    \ integer right

\ Sort three vertices by y ascending (bubble sort)
: _DRAW-TRI-SORT  ( -- )
    \ If YA > YB, swap A and B
    _DRAW-TRI-YA @ _DRAW-TRI-YB @ > IF
        _DRAW-TRI-XA @ _DRAW-TRI-XB @  _DRAW-TRI-XA ! _DRAW-TRI-XB !
        _DRAW-TRI-YA @ _DRAW-TRI-YB @  _DRAW-TRI-YA ! _DRAW-TRI-YB !
    THEN
    \ If YB > YC, swap B and C
    _DRAW-TRI-YB @ _DRAW-TRI-YC @ > IF
        _DRAW-TRI-XB @ _DRAW-TRI-XC @  _DRAW-TRI-XB ! _DRAW-TRI-XC !
        _DRAW-TRI-YB @ _DRAW-TRI-YC @  _DRAW-TRI-YB ! _DRAW-TRI-YC !
    THEN
    \ If YA > YB again, swap A and B
    _DRAW-TRI-YA @ _DRAW-TRI-YB @ > IF
        _DRAW-TRI-XA @ _DRAW-TRI-XB @  _DRAW-TRI-XA ! _DRAW-TRI-XB !
        _DRAW-TRI-YA @ _DRAW-TRI-YB @  _DRAW-TRI-YA ! _DRAW-TRI-YB !
    THEN ;

\ Compute FP16 slope dx/dy from (x0,y0) to (x1,y1)
\ Returns 0 if dy == 0
: _DRAW-TRI-SLOPE  ( x0 y0 x1 y1 -- slope-fp16 )
    ROT -              ( x0 x1 dy )
    DUP 0= IF
        DROP DROP DROP 0 EXIT
    THEN
    >R                 ( x0 x1 ) ( R: dy )
    SWAP - INT>FP16    ( dx-fp )
    R> INT>FP16        ( dx-fp dy-fp )
    FP16-DIV ;

\ Draw one scanline span from xl to xr at y
: _DRAW-TRI-SPAN  ( y -- )
    _DRAW-TRI-SL @ FP16>INT _DRAW-TRI-XL !
    _DRAW-TRI-SR @ FP16>INT _DRAW-TRI-XR !

    \ Ensure left <= right
    _DRAW-TRI-XL @ _DRAW-TRI-XR @ > IF
        _DRAW-TRI-XL @ _DRAW-TRI-XR @
        _DRAW-TRI-XL ! _DRAW-TRI-XR !
    THEN

    _DRAW-TRI-XR @ _DRAW-TRI-XL @ - 1 +  ( len )
    DUP 1 < IF DROP EXIT THEN

    _DRAW-SURF @ _DRAW-TRI-XL @ ROT       ( surf xl y len )
    SWAP                                   ( surf xl len y )
    >R >R                                  ( surf xl ) ( R: y len )
    R> R>                                  ( surf xl len y )
    SWAP                                   ( on stack we need: surf x y len rgba )
    >R                                     ( surf xl y ) ( R: len )
    R>                                     ( surf xl y len )
    _DRAW-RGBA @
    SURF-HLINE ;

: DRAW-TRIANGLE  ( surf x0 y0 x1 y1 x2 y2 rgba -- )
    _DRAW-RGBA !
    _DRAW-TRI-YC !  _DRAW-TRI-XC !
    _DRAW-TRI-YB !  _DRAW-TRI-XB !
    _DRAW-TRI-YA !  _DRAW-TRI-XA !
    _DRAW-SURF !

    _DRAW-TRI-SORT

    \ Degenerate: all same Y → single hline
    _DRAW-TRI-YA @ _DRAW-TRI-YC @ = IF
        _DRAW-TRI-XA @ _DRAW-TRI-XB @ MIN _DRAW-TRI-XC @ MIN  _DRAW-TRI-XL !
        _DRAW-TRI-XA @ _DRAW-TRI-XB @ MAX _DRAW-TRI-XC @ MAX  _DRAW-TRI-XR !
        _DRAW-SURF @ _DRAW-TRI-XL @ _DRAW-TRI-YA @
        _DRAW-TRI-XR @ _DRAW-TRI-XL @ - 1 +
        _DRAW-RGBA @ SURF-HLINE
        EXIT
    THEN

    \ Compute slopes
    \ AC slope (long edge from top to bottom)
    _DRAW-TRI-XA @ _DRAW-TRI-YA @ _DRAW-TRI-XC @ _DRAW-TRI-YC @
    _DRAW-TRI-SLOPE _DRAW-TRI-DL !

    \ Top half: A to B
    _DRAW-TRI-YA @ _DRAW-TRI-YB @ <> IF
        _DRAW-TRI-XA @ _DRAW-TRI-YA @ _DRAW-TRI-XB @ _DRAW-TRI-YB @
        _DRAW-TRI-SLOPE _DRAW-TRI-DR !

        _DRAW-TRI-XA @ INT>FP16 DUP _DRAW-TRI-SL ! _DRAW-TRI-SR !

        _DRAW-TRI-YB @ _DRAW-TRI-YA @ - 0 DO
            _DRAW-TRI-YA @ I + _DRAW-TRI-SPAN
            _DRAW-TRI-DL @ _DRAW-TRI-SL +!
            _DRAW-TRI-DR @ _DRAW-TRI-SR +!
        LOOP
    THEN

    \ Bottom half: B to C
    _DRAW-TRI-YB @ _DRAW-TRI-YC @ <> IF
        _DRAW-TRI-XB @ _DRAW-TRI-YB @ _DRAW-TRI-XC @ _DRAW-TRI-YC @
        _DRAW-TRI-SLOPE _DRAW-TRI-DR !

        \ SL continues from AC slope; SR starts at B
        \ But if top half was degenerate (YA == YB), reset SL too
        _DRAW-TRI-YA @ _DRAW-TRI-YB @ = IF
            _DRAW-TRI-XA @ INT>FP16 _DRAW-TRI-SL !
            _DRAW-TRI-XB @ INT>FP16 _DRAW-TRI-SR !
        ELSE
            _DRAW-TRI-XB @ INT>FP16 _DRAW-TRI-SR !
        THEN

        _DRAW-TRI-YC @ _DRAW-TRI-YB @ - 0 DO
            _DRAW-TRI-YB @ I + _DRAW-TRI-SPAN
            _DRAW-TRI-DL @ _DRAW-TRI-SL +!
            _DRAW-TRI-DR @ _DRAW-TRI-SR +!
        LOOP
    THEN ;

\ =====================================================================
\  Bézier stroke rendering
\ =====================================================================
\  Flattens curves to line segments via bezier.f, draws each segment
\  with DRAW-LINE.

0x3400 CONSTANT _DRAW-BZ-TOL     \ 0.25 px in FP16

VARIABLE _DRAW-BZ-X0
VARIABLE _DRAW-BZ-Y0
VARIABLE _DRAW-BZ-X1
VARIABLE _DRAW-BZ-Y1

\ Callback for BZ-*-FLATTEN: receives ( x0fp y0fp x1fp y1fp )
: _DRAW-BZ-CB  ( x0fp y0fp x1fp y1fp -- )
    FP16>INT _DRAW-BZ-Y1 !   FP16>INT _DRAW-BZ-X1 !
    FP16>INT _DRAW-BZ-Y0 !   FP16>INT _DRAW-BZ-X0 !
    _DRAW-SURF @ _DRAW-BZ-X0 @ _DRAW-BZ-Y0 @
    _DRAW-BZ-X1 @ _DRAW-BZ-Y1 @ _DRAW-RGBA @ DRAW-LINE ;

\ DRAW-BEZIER-QUAD  ( surf x0 y0 x1 y1 x2 y2 rgba -- )
: DRAW-BEZIER-QUAD  ( surf x0 y0 x1 y1 x2 y2 rgba -- )
    _DRAW-RGBA !
    _DRAW-Y2 !  _DRAW-X2 !
    _DRAW-Y1 !  _DRAW-X1 !
    _DRAW-Y0 !  _DRAW-X0 !
    _DRAW-SURF !

    _DRAW-X0 @ INT>FP16  _DRAW-Y0 @ INT>FP16
    _DRAW-X1 @ INT>FP16  _DRAW-Y1 @ INT>FP16
    _DRAW-X2 @ INT>FP16  _DRAW-Y2 @ INT>FP16
    _DRAW-BZ-TOL ['] _DRAW-BZ-CB BZ-QUAD-FLATTEN ;

\ DRAW-BEZIER-CUBIC  ( surf x0 y0 x1 y1 x2 y2 x3 y3 rgba -- )
: DRAW-BEZIER-CUBIC  ( surf x0 y0 x1 y1 x2 y2 x3 y3 rgba -- )
    _DRAW-RGBA !
    _DRAW-Y3 !  _DRAW-X3 !
    _DRAW-Y2 !  _DRAW-X2 !
    _DRAW-Y1 !  _DRAW-X1 !
    _DRAW-Y0 !  _DRAW-X0 !
    _DRAW-SURF !

    _DRAW-X0 @ INT>FP16  _DRAW-Y0 @ INT>FP16
    _DRAW-X1 @ INT>FP16  _DRAW-Y1 @ INT>FP16
    _DRAW-X2 @ INT>FP16  _DRAW-Y2 @ INT>FP16
    _DRAW-X3 @ INT>FP16  _DRAW-Y3 @ INT>FP16
    _DRAW-BZ-TOL ['] _DRAW-BZ-CB BZ-CUBIC-FLATTEN ;

\ =====================================================================
\  Path API — Edge accumulator using raster.f edge table
\ =====================================================================
\  Builds edges in the raster edge table, then fills/strokes.

VARIABLE _DRAW-PATH-CX     \ current cursor X
VARIABLE _DRAW-PATH-CY     \ current cursor Y
VARIABLE _DRAW-PATH-MX     \ move-to X (start of sub-path)
VARIABLE _DRAW-PATH-MY     \ move-to Y (start of sub-path)
VARIABLE _DRAW-PATH-MINX   \ bounding box
VARIABLE _DRAW-PATH-MINY
VARIABLE _DRAW-PATH-MAXX
VARIABLE _DRAW-PATH-MAXY

\ Update bounding box with a point
: _DRAW-PATH-BBOX  ( x y -- )
    DUP _DRAW-PATH-MINY @ MIN _DRAW-PATH-MINY !
    DUP _DRAW-PATH-MAXY @ MAX _DRAW-PATH-MAXY !
    DROP
    DUP _DRAW-PATH-MINX @ MIN _DRAW-PATH-MINX !
    DUP _DRAW-PATH-MAXX @ MAX _DRAW-PATH-MAXX !
    DROP ;

: DRAW-PATH-BEGIN  ( -- )
    RAST-RESET
    0 _DRAW-PATH-CX !   0 _DRAW-PATH-CY !
    0 _DRAW-PATH-MX !   0 _DRAW-PATH-MY !
    32767 _DRAW-PATH-MINX !   32767 _DRAW-PATH-MINY !
    -32768 _DRAW-PATH-MAXX !  -32768 _DRAW-PATH-MAXY !
    ;

: DRAW-PATH-MOVE  ( x y -- )
    DUP _DRAW-PATH-CY ! _DRAW-PATH-MY !
    DUP _DRAW-PATH-CX ! _DRAW-PATH-MX !
    OVER OVER _DRAW-PATH-BBOX ;

: DRAW-PATH-LINE  ( x y -- )
    2DUP _DRAW-PATH-BBOX
    _DRAW-PATH-CX @ _DRAW-PATH-CY @ ROT ROT RAST-EDGE
    _DRAW-PATH-CY !  _DRAW-PATH-CX ! ;

: DRAW-PATH-CLOSE  ( -- )
    _DRAW-PATH-CX @ _DRAW-PATH-CY @
    _DRAW-PATH-MX @ _DRAW-PATH-MY @
    RAST-EDGE
    _DRAW-PATH-MX @ _DRAW-PATH-CX !
    _DRAW-PATH-MY @ _DRAW-PATH-CY !
    ;

\ Callback for path Bézier flattening: add edge segments
VARIABLE _DRAW-PBZ-X0   VARIABLE _DRAW-PBZ-Y0
VARIABLE _DRAW-PBZ-X1   VARIABLE _DRAW-PBZ-Y1

: _DRAW-PBZ-CB  ( x0fp y0fp x1fp y1fp -- )
    FP16>INT _DRAW-PBZ-Y1 !   FP16>INT _DRAW-PBZ-X1 !
    FP16>INT _DRAW-PBZ-Y0 !   FP16>INT _DRAW-PBZ-X0 !
    _DRAW-PBZ-X0 @ _DRAW-PBZ-Y0 @ _DRAW-PBZ-X1 @ _DRAW-PBZ-Y1 @ RAST-EDGE ;

: DRAW-PATH-QUAD  ( cx cy x y -- )
    2DUP _DRAW-PATH-BBOX
    >R >R                     ( cx cy ) ( R: y x )
    2DUP _DRAW-PATH-BBOX
    INT>FP16 >R INT>FP16 R>   ( cx-fp cy-fp )
    R> R> INT>FP16 >R INT>FP16 R>  ( cx-fp cy-fp x-fp y-fp )
    >R >R >R >R               ( ) ( R: y-fp x-fp cy-fp cx-fp )
    _DRAW-PATH-CX @ INT>FP16
    _DRAW-PATH-CY @ INT>FP16
    R> R> R> R>                ( cx0-fp cy0-fp cx-fp cy-fp x-fp y-fp )
    _DRAW-BZ-TOL ['] _DRAW-PBZ-CB BZ-QUAD-FLATTEN
    \ Update cursor to destination
    2DUP _DRAW-PATH-CY ! _DRAW-PATH-CX !
    ;

: DRAW-PATH-CUBIC  ( c1x c1y c2x c2y x y -- )
    2DUP _DRAW-PATH-BBOX
    >R >R                     ( c1x c1y c2x c2y ) ( R: y x )
    2DUP _DRAW-PATH-BBOX
    INT>FP16 >R INT>FP16 R>   ( c1x c1y c2x-fp c2y-fp )
    R> R>                     ( c1x c1y c2x-fp c2y-fp x y )
    INT>FP16 >R INT>FP16 R>   ( c1x c1y c2x-fp c2y-fp x-fp y-fp )
    >R >R >R >R               ( c1x c1y ) ( R: y-fp x-fp c2y-fp c2x-fp )
    2DUP _DRAW-PATH-BBOX
    INT>FP16 >R INT>FP16 R>   ( c1x-fp c1y-fp )
    >R >R                     ( ) ( R: y-fp x-fp c2y-fp c2x-fp c1y-fp c1x-fp )
    _DRAW-PATH-CX @ INT>FP16
    _DRAW-PATH-CY @ INT>FP16
    R> R> R> R> R> R>          ( p0x p0y c1x c1y c2x c2y x y )
    _DRAW-BZ-TOL ['] _DRAW-PBZ-CB BZ-CUBIC-FLATTEN
    2DUP _DRAW-PATH-CY ! _DRAW-PATH-CX !
    ;

\ Path temp bitmap buffer (allocated on demand)
VARIABLE _DRAW-PATH-BUF
VARIABLE _DRAW-PATH-BW
VARIABLE _DRAW-PATH-BH

\ Offset all stored edges by (dx, dy).
\ Directly adjusts raster.f edge arrays.
: _DRAW-PATH-OFFSET-EDGES  ( dx dy -- )
    _DRAW-Y0 !  _DRAW-X0 !
    RAST-NEDGES 0 DO
        _DRAW-X0 @  _RST-EX0 I CELLS + +!
        _DRAW-Y0 @  _RST-EY0 I CELLS + +!
        _DRAW-X0 @  _RST-EX1 I CELLS + +!
        _DRAW-Y0 @  _RST-EY1 I CELLS + +!
    LOOP ;

: DRAW-PATH-FILL  ( surf rgba -- )
    _DRAW-RGBA !  _DRAW-SURF !

    \ Compute bounding box size
    _DRAW-PATH-MAXX @ _DRAW-PATH-MINX @ - 1 + _DRAW-PATH-BW !
    _DRAW-PATH-MAXY @ _DRAW-PATH-MINY @ - 1 + _DRAW-PATH-BH !

    _DRAW-PATH-BW @ 1 < IF EXIT THEN
    _DRAW-PATH-BH @ 1 < IF EXIT THEN

    \ Shift all edges so the bbox origin lands at (0, 0).
    \ This lets us allocate only bbox-sized bitmap.
    _DRAW-PATH-MINX @ NEGATE  _DRAW-PATH-MINY @ NEGATE
    _DRAW-PATH-OFFSET-EDGES

    \ Allocate mono bitmap (1 byte/pixel)
    _DRAW-PATH-BW @ _DRAW-PATH-BH @ * ALLOCATE
    0<> ABORT" DRAW-PATH-FILL: alloc failed"
    _DRAW-PATH-BUF !

    _DRAW-PATH-BUF @  _DRAW-PATH-BW @ _DRAW-PATH-BH @ *  0 FILL

    \ Scanline fill into bbox-sized bitmap
    _DRAW-PATH-BUF @ _DRAW-PATH-BW @ _DRAW-PATH-BH @ RAST-FILL

    \ Blit mono bitmap to surface at (minx, miny)
    _DRAW-PATH-BH @ 0 DO
        _DRAW-PATH-BW @ 0 DO
            _DRAW-PATH-BUF @  J _DRAW-PATH-BW @ * +  I +
            C@ 0<> IF
                _DRAW-SURF @
                I _DRAW-PATH-MINX @ +
                J _DRAW-PATH-MINY @ +
                _DRAW-RGBA @
                SURF-PIXEL!
            THEN
        LOOP
    LOOP

    _DRAW-PATH-BUF @ FREE ;

: DRAW-PATH-STROKE  ( surf rgba -- )
    _DRAW-RGBA !  _DRAW-SURF !
    \ Walk raster.f edge arrays directly and draw each edge as a line.
    RAST-NEDGES 0 DO
        _DRAW-SURF @
        _RST-EX0 I CELLS + @
        _RST-EY0 I CELLS + @
        _RST-EX1 I CELLS + @
        _RST-EY1 I CELLS + @
        _DRAW-RGBA @
        DRAW-LINE
    LOOP ;

\ =====================================================================
\  DRAW-GLYPH — Render a cached glyph bitmap
\ =====================================================================
\  ( surf glyph-id size x y rgba -- )
\  Uses GC-GET from font/cache.f.  The glyph bitmap contains coverage
\  values (0-255) from anti-aliased rasterization.  Non-zero bytes are
\  alpha-blended with the surface using the coverage as opacity.

VARIABLE _DRAW-GL-BMP
VARIABLE _DRAW-GL-W
VARIABLE _DRAW-GL-H
VARIABLE _DRAW-GL-X
VARIABLE _DRAW-GL-Y
VARIABLE _DRAW-GL-COV    \ coverage value 0-255
VARIABLE _DRAW-GL-BG     \ background pixel
VARIABLE _DRAW-GL-FR     \ foreground R
VARIABLE _DRAW-GL-FG     \ foreground G
VARIABLE _DRAW-GL-FB     \ foreground B
VARIABLE _DRAW-GL-OUT    \ blended rgba output

\ ── Tile-accelerated glyph blend scratch ─────────────────────────
\  Used by the U16-mode tile path in DRAW-GLYPH.
\  Tile layout (all 32-lane U16):
\    S0=T_COV  S1=T_ICOV  S2=T_BGR  S3=T_BGG  S4=T_BGB
\    S5=T_FG   S6=T_CONST S7=T_WORK

VARIABLE _DRAW-TB-N       \ pixels in current row batch
VARIABLE _DRAW-TB-FGR     \ pre-linearized foreground R
VARIABLE _DRAW-TB-FGG     \ pre-linearized foreground G
VARIABLE _DRAW-TB-FGB     \ pre-linearized foreground B
VARIABLE _DRAW-TB-BG      \ temp: background pixel
VARIABLE _DRAW-TB-ROWI    \ current row index

CREATE _DRAW-TB-COV  32 ALLOT   \ coverage bytes (scatter fast-path)
CREATE _DRAW-TB-OUTR 32 ALLOT   \ blended output R (sRGB)
CREATE _DRAW-TB-OUTG 32 ALLOT   \ blended output G (sRGB)
CREATE _DRAW-TB-OUTB 32 ALLOT   \ blended output B (sRGB)

\ ── sRGB linearize / delinearize LUTs ──────────────────────────────
\  Naive alpha blending in sRGB space makes antialiased edges too
\  light ("faded text" problem).  We linearize channels before
\  blending, then convert back to sRGB.
\  Approximations (fast integer math, no floating point):
\    sRGB→linear:  i * i / 255          ≈ pow(i/255, 2.0) * 255
\    linear→sRGB:  isqrt(i * 255)       ≈ pow(i/255, 0.5) * 255
\  True sRGB uses 2.2/0.455 but 2.0/0.5 is close and free.

CREATE _DRAW-S2L  256 ALLOT    \ sRGB → linear
CREATE _DRAW-L2S  256 ALLOT    \ linear → sRGB

VARIABLE _DRAW-ISQRT-N  VARIABLE _DRAW-ISQRT-G  VARIABLE _DRAW-ISQRT-NG

: _DRAW-ISQRT  ( n -- root )
    DUP 1 < IF EXIT THEN
    DUP _DRAW-ISQRT-N !
    _DRAW-ISQRT-G !            \ initial guess = n (converges downward)
    BEGIN
        _DRAW-ISQRT-N @ _DRAW-ISQRT-G @ / _DRAW-ISQRT-G @ + 2 /
        _DRAW-ISQRT-NG !
        _DRAW-ISQRT-NG @ _DRAW-ISQRT-G @ >= IF
            _DRAW-ISQRT-G @ EXIT
        THEN
        _DRAW-ISQRT-NG @ _DRAW-ISQRT-G !
    AGAIN ;

: _DRAW-INIT-SRGB  ( -- )
    256 0 DO
        I I * 270 / 255 MIN  I _DRAW-S2L + C!    \ sRGB→linear (γ≈2.1)
        I 255 * _DRAW-ISQRT  255 MIN  I _DRAW-L2S + C!    \ linear→sRGB
    LOOP ;

_DRAW-INIT-SRGB

: _DRAW-GL-BLEND  ( fg bg cov -- out )
    >R
    SWAP _DRAW-S2L + C@       ( bg_lin fg_lin )  \ linearize fg
    SWAP _DRAW-S2L + C@       ( fg_lin bg_lin )  \ linearize bg
    SWAP R@ *                 ( bg_lin fg_lin*cov )
    SWAP 255 R> - *           ( fg_lin*cov  bg_lin*(255-cov) )
    + 255 /                   ( blended_linear )
    _DRAW-L2S + C@ ;          \ delinearize → sRGB

\ =====================================================================
\  Tile-accelerated glyph blend (U16 mode, up to 32 pixels/row)
\ =====================================================================
\  Operates on pre-linearized channel values in U16 tiles.
\  Blend formula (per channel, linear space):
\    out_lin = (fg_lin * cov + bg_lin * (255 - cov) + 128) >> 8
\  The >> 8 is read as the high byte of the U16 result.

\ Gather one row of pixels into U16 tiles
: _DRAW-TB-GATHER  ( -- )
    _SIMD-S0 @ TILE-ZERO    \ T_COV
    _SIMD-S2 @ TILE-ZERO    \ T_BGR
    _SIMD-S3 @ TILE-ZERO    \ T_BGG
    _SIMD-S4 @ TILE-ZERO    \ T_BGB
    _DRAW-TB-N @ 0 DO
        _DRAW-GL-BMP @  _DRAW-TB-ROWI @ _DRAW-GL-W @ * +  I +  C@
        DUP I _DRAW-TB-COV + C!
        DUP 0<> IF
            _SIMD-S0 @ I 2 * + W!       \ coverage → T_COV
            _DRAW-SURF @
            _DRAW-GL-X @ I +
            _DRAW-GL-Y @ _DRAW-TB-ROWI @ +
            SURF-PIXEL@  _DRAW-TB-BG !
            \ Linearize bg R → T_BGR
            _DRAW-TB-BG @ 24 RSHIFT 255 AND  _DRAW-S2L + C@
            _SIMD-S2 @ I 2 * + W!
            \ Linearize bg G → T_BGG
            _DRAW-TB-BG @ 16 RSHIFT 255 AND  _DRAW-S2L + C@
            _SIMD-S3 @ I 2 * + W!
            \ Linearize bg B → T_BGB
            _DRAW-TB-BG @  8 RSHIFT 255 AND  _DRAW-S2L + C@
            _SIMD-S4 @ I 2 * + W!
        ELSE
            DROP
        THEN
    LOOP ;

\ Tile-blend one channel.  Result in _SIMD-S7 (T_WORK) as U16.
\ T_CONST (_SIMD-S6) must already hold broadcast 128.
: _DRAW-TB-BLEND-CH  ( fg-lin bg-tile -- )
    >R
    _SIMD-S5 @ SWAP TILE-FILL-U16       \ T_FG = broadcast fg_lin
    _SIMD-S5 @ _SIMD-S0 @ _SIMD-S7 @ TILE-MUL   \ T_WORK = fg * cov
    R> _SIMD-S1 @ _SIMD-S5 @ TILE-MUL            \ T_FG = bg * icov
    _SIMD-S7 @ _SIMD-S5 @ _SIMD-S7 @ TILE-ADD   \ T_WORK += bg*icov
    _SIMD-S7 @ _SIMD-S6 @ _SIMD-S7 @ TILE-ADD ; \ T_WORK += 128

\ Extract high bytes from T_WORK, delinearize, store to buffer
: _DRAW-TB-EXTRACT  ( out-buf -- )
    _DRAW-TB-N @ 0 DO
        _SIMD-S7 @ I 2 * 1+ + C@      \ high byte = result >> 8
        _DRAW-L2S + C@                \ delinearize → sRGB
        OVER I + C!
    LOOP
    DROP ;

\ Write blended pixels back to surface
: _DRAW-TB-SCATTER  ( -- )
    _DRAW-TB-N @ 0 DO
        I _DRAW-TB-COV + C@
        DUP 255 = IF
            DROP
            _DRAW-SURF @
            _DRAW-GL-X @ I +
            _DRAW-GL-Y @ _DRAW-TB-ROWI @ +
            _DRAW-RGBA @
            SURF-PIXEL!
        ELSE
            DUP 0<> IF
                DROP
                I _DRAW-TB-OUTR + C@ 24 LSHIFT
                I _DRAW-TB-OUTG + C@ 16 LSHIFT OR
                I _DRAW-TB-OUTB + C@  8 LSHIFT OR
                255 OR
                _DRAW-GL-OUT !
                _DRAW-SURF @
                _DRAW-GL-X @ I +
                _DRAW-GL-Y @ _DRAW-TB-ROWI @ +
                _DRAW-GL-OUT @
                SURF-PIXEL!
            ELSE
                DROP
            THEN
        THEN
    LOOP ;

\ Process one glyph row via tile engine
: _DRAW-TB-ROW  ( row -- )
    _DRAW-TB-ROWI !
    _DRAW-TB-GATHER
    U16-MODE
    \ Inverse coverage: T_ICOV = 255 - T_COV
    _SIMD-S6 @ 255 TILE-FILL-U16
    _SIMD-S6 @ _SIMD-S0 @ _SIMD-S1 @ TILE-SUB
    \ Rounding constant
    _SIMD-S6 @ 128 TILE-FILL-U16
    \ Blend R
    _DRAW-TB-FGR @  _SIMD-S2 @  _DRAW-TB-BLEND-CH
    _DRAW-TB-OUTR _DRAW-TB-EXTRACT
    \ Blend G
    _DRAW-TB-FGG @  _SIMD-S3 @  _DRAW-TB-BLEND-CH
    _DRAW-TB-OUTG _DRAW-TB-EXTRACT
    \ Blend B
    _DRAW-TB-FGB @  _SIMD-S4 @  _DRAW-TB-BLEND-CH
    _DRAW-TB-OUTB _DRAW-TB-EXTRACT
    _DRAW-TB-SCATTER ;

: DRAW-GLYPH  ( surf glyph-id size x y rgba -- )
    _DRAW-RGBA !  _DRAW-GL-Y !  _DRAW-GL-X !
    >R >R  ( surf ) ( R: size glyph-id )
    _DRAW-SURF !
    R> R>  ( glyph-id size )
    GC-GET
    _DRAW-GL-H !  _DRAW-GL-W !  _DRAW-GL-BMP !

    \ 0 0 0 = cache miss, skip
    _DRAW-GL-BMP @ 0= IF EXIT THEN

    \ Extract foreground RGB
    _DRAW-RGBA @ 24 RSHIFT 255 AND _DRAW-GL-FR !
    _DRAW-RGBA @ 16 RSHIFT 255 AND _DRAW-GL-FG !
    _DRAW-RGBA @  8 RSHIFT 255 AND _DRAW-GL-FB !

    \ Pre-linearize foreground (constant for entire glyph)
    _DRAW-GL-FR @ _DRAW-S2L + C@  _DRAW-TB-FGR !
    _DRAW-GL-FG @ _DRAW-S2L + C@  _DRAW-TB-FGG !
    _DRAW-GL-FB @ _DRAW-S2L + C@  _DRAW-TB-FGB !

    \ ── Tile path (glyph width ≤ 32, fits in 32 U16 lanes) ──
    _DRAW-GL-W @ 32 <= IF
        _DRAW-GL-W @ _DRAW-TB-N !
        _DRAW-GL-H @ 0 DO
            I _DRAW-TB-ROW
        LOOP
        EXIT
    THEN

    \ ── Scalar fallback (glyph width > 32, very rare) ──
    _DRAW-GL-H @ 0 DO
        _DRAW-GL-W @ 0 DO
            _DRAW-GL-BMP @  J _DRAW-GL-W @ * +  I +
            C@ DUP 0<> IF
                _DRAW-GL-COV !
                _DRAW-GL-COV @ 255 = IF
                    _DRAW-SURF @
                    _DRAW-GL-X @ I +
                    _DRAW-GL-Y @ J +
                    _DRAW-RGBA @
                    SURF-PIXEL!
                ELSE
                    _DRAW-SURF @
                    _DRAW-GL-X @ I +
                    _DRAW-GL-Y @ J +
                    SURF-PIXEL@  _DRAW-GL-BG !

                    _DRAW-GL-FR @
                    _DRAW-GL-BG @ 24 RSHIFT 255 AND
                    _DRAW-GL-COV @
                    _DRAW-GL-BLEND
                    24 LSHIFT

                    _DRAW-GL-FG @
                    _DRAW-GL-BG @ 16 RSHIFT 255 AND
                    _DRAW-GL-COV @
                    _DRAW-GL-BLEND
                    16 LSHIFT OR

                    _DRAW-GL-FB @
                    _DRAW-GL-BG @  8 RSHIFT 255 AND
                    _DRAW-GL-COV @
                    _DRAW-GL-BLEND
                    8 LSHIFT OR

                    255 OR

                    _DRAW-GL-OUT !
                    _DRAW-SURF @
                    _DRAW-GL-X @ I +
                    _DRAW-GL-Y @ J +
                    _DRAW-GL-OUT @ SURF-PIXEL!
                THEN
            ELSE
                DROP
            THEN
        LOOP
    LOOP ;

\ =====================================================================
\  DRAW-TEXT — Render UTF-8 string
\ =====================================================================
\  ( surf addr len x y size rgba -- )
\  Renders each glyph using DRAW-GLYPH, advancing by character width.
\  Requires that a font has been loaded (TTF-BASE!, TTF-PARSE-*, etc.)
\  and LAY-SCALE! has been called.

VARIABLE _DRAW-TXT-A
VARIABLE _DRAW-TXT-L
VARIABLE _DRAW-TXT-X
VARIABLE _DRAW-TXT-Y
VARIABLE _DRAW-TXT-SZ
VARIABLE _DRAW-TXT-CP
VARIABLE _DRAW-TXT-GID

: DRAW-TEXT  ( surf addr len x y size rgba -- )
    _DRAW-RGBA !  _DRAW-TXT-SZ !
    _DRAW-TXT-Y !  _DRAW-TXT-X !
    _DRAW-TXT-L !  _DRAW-TXT-A !
    _DRAW-SURF !

    \ Set scale for layout
    _DRAW-TXT-SZ @ LAY-SCALE!

    \ Iterate codepoints
    BEGIN
        _DRAW-TXT-L @ 0> WHILE
        _DRAW-TXT-A @ _DRAW-TXT-L @ UTF8-DECODE
        _DRAW-TXT-L !  _DRAW-TXT-A !  _DRAW-TXT-CP !

        \ Map codepoint to glyph
        _DRAW-TXT-CP @ TTF-CMAP-LOOKUP _DRAW-TXT-GID !

        _DRAW-TXT-GID @ 0<> IF
            _DRAW-SURF @
            _DRAW-TXT-GID @
            _DRAW-TXT-SZ @
            _DRAW-TXT-X @
            _DRAW-TXT-Y @
            _DRAW-RGBA @
            DRAW-GLYPH
        THEN

        \ Advance cursor
        _DRAW-TXT-CP @ LAY-CHAR-WIDTH  _DRAW-TXT-X +!
    REPEAT ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _draw-guard

' DRAW-RECT       CONSTANT _draw-rect-xt
' DRAW-HLINE      CONSTANT _draw-hline-xt
' DRAW-VLINE      CONSTANT _draw-vline-xt
' DRAW-RECT-OUTLINE CONSTANT _draw-rect-outline-xt
' DRAW-LINE       CONSTANT _draw-line-xt
' DRAW-CIRCLE     CONSTANT _draw-circle-xt
' DRAW-CIRCLE-OUTLINE CONSTANT _draw-circle-outline-xt
' DRAW-ELLIPSE    CONSTANT _draw-ellipse-xt
' DRAW-TRIANGLE   CONSTANT _draw-triangle-xt
' DRAW-BEZIER-QUAD CONSTANT _draw-bezier-quad-xt
' DRAW-BEZIER-CUBIC CONSTANT _draw-bezier-cubic-xt
' DRAW-PATH-BEGIN CONSTANT _draw-path-begin-xt
' DRAW-PATH-MOVE  CONSTANT _draw-path-move-xt
' DRAW-PATH-LINE  CONSTANT _draw-path-line-xt
' DRAW-PATH-CLOSE CONSTANT _draw-path-close-xt
' DRAW-PATH-QUAD  CONSTANT _draw-path-quad-xt
' DRAW-PATH-CUBIC CONSTANT _draw-path-cubic-xt
' DRAW-PATH-FILL  CONSTANT _draw-path-fill-xt
' DRAW-PATH-STROKE CONSTANT _draw-path-stroke-xt
' DRAW-GLYPH      CONSTANT _draw-glyph-xt
' DRAW-TEXT       CONSTANT _draw-text-xt

: DRAW-RECT       _draw-rect-xt _draw-guard WITH-GUARD ;
: DRAW-HLINE      _draw-hline-xt _draw-guard WITH-GUARD ;
: DRAW-VLINE      _draw-vline-xt _draw-guard WITH-GUARD ;
: DRAW-RECT-OUTLINE _draw-rect-outline-xt _draw-guard WITH-GUARD ;
: DRAW-LINE       _draw-line-xt _draw-guard WITH-GUARD ;
: DRAW-CIRCLE     _draw-circle-xt _draw-guard WITH-GUARD ;
: DRAW-CIRCLE-OUTLINE _draw-circle-outline-xt _draw-guard WITH-GUARD ;
: DRAW-ELLIPSE    _draw-ellipse-xt _draw-guard WITH-GUARD ;
: DRAW-TRIANGLE   _draw-triangle-xt _draw-guard WITH-GUARD ;
: DRAW-BEZIER-QUAD _draw-bezier-quad-xt _draw-guard WITH-GUARD ;
: DRAW-BEZIER-CUBIC _draw-bezier-cubic-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-BEGIN _draw-path-begin-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-MOVE  _draw-path-move-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-LINE  _draw-path-line-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-CLOSE _draw-path-close-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-QUAD  _draw-path-quad-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-CUBIC _draw-path-cubic-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-FILL  _draw-path-fill-xt _draw-guard WITH-GUARD ;
: DRAW-PATH-STROKE _draw-path-stroke-xt _draw-guard WITH-GUARD ;
: DRAW-GLYPH      _draw-glyph-xt _draw-guard WITH-GUARD ;
: DRAW-TEXT       _draw-text-xt _draw-guard WITH-GUARD ;
[THEN] [THEN]
