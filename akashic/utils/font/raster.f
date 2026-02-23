\ raster.f — Scanline rasterizer for glyph outlines
\
\ Takes line segments (edges), rasterizes into a monochrome
\ bitmap using even-odd scanline fill.
\
\ Coordinates are integers (pre-scaled from font units to pixels).
\ Caller is responsible for coordinate scaling and Y-flip.
\
\ Prefix: RAST-  (public API)
\         _RST-  (internal helpers)
\
\ Load with:   REQUIRE raster.f

PROVIDED akashic-raster
REQUIRE fixed.f

\ =====================================================================
\  Edge table
\ =====================================================================
\  Each edge stores (x0 y0 x1 y1) in integer pixel coordinates.
\  Edges are normalized so y0 <= y1 on insertion.
\  Horizontal edges (y0 == y1) are discarded — they don't affect fill.

512 CONSTANT _RST-MAX-EDGES

HERE _RST-MAX-EDGES CELLS ALLOT CONSTANT _RST-EX0
HERE _RST-MAX-EDGES CELLS ALLOT CONSTANT _RST-EY0
HERE _RST-MAX-EDGES CELLS ALLOT CONSTANT _RST-EX1
HERE _RST-MAX-EDGES CELLS ALLOT CONSTANT _RST-EY1

VARIABLE _RST-NEDGES

: RAST-RESET  ( -- )
    0 _RST-NEDGES ! ;

RAST-RESET

: RAST-NEDGES  ( -- n )
    _RST-NEDGES @ ;

\ Temp vars for edge insertion
VARIABLE _RST-TX0   VARIABLE _RST-TY0
VARIABLE _RST-TX1   VARIABLE _RST-TY1

: RAST-EDGE  ( x0 y0 x1 y1 -- )
    _RST-TY1 !  _RST-TX1 !  _RST-TY0 !  _RST-TX0 !
    \ Discard horizontal edges
    _RST-TY0 @ _RST-TY1 @ = IF EXIT THEN
    \ Normalize: ensure y0 <= y1
    _RST-TY0 @ _RST-TY1 @ > IF
        _RST-TX0 @ _RST-TX1 @  _RST-TX0 !  _RST-TX1 !
        _RST-TY0 @ _RST-TY1 @  _RST-TY0 !  _RST-TY1 !
    THEN
    \ Drop if table full
    _RST-NEDGES @ _RST-MAX-EDGES >= IF EXIT THEN
    \ Store edge
    _RST-NEDGES @ >R
    _RST-TX0 @ R@ CELLS _RST-EX0 + !
    _RST-TY0 @ R@ CELLS _RST-EY0 + !
    _RST-TX1 @ R@ CELLS _RST-EX1 + !
    _RST-TY1 @ R@ CELLS _RST-EY1 + !
    R> 1+ _RST-NEDGES ! ;

\ =====================================================================
\  Scanline x-intercept computation
\ =====================================================================
\  For a given scanline Y, compute x-intercept with each active edge.
\  An edge is active if y0 <= Y < y1.
\  x = x0 + (Y - y0) * (x1 - x0) / (y1 - y0)
\  Uses integer arithmetic with rounding.

256 CONSTANT _RST-MAX-XINTS
HERE _RST-MAX-XINTS CELLS ALLOT CONSTANT _RST-XINTS
VARIABLE _RST-NXINTS

\ Variables for intercept computation
VARIABLE _RST-CUR-Y

: _RST-COLLECT-XINTS  ( y -- )
    _RST-CUR-Y !
    0 _RST-NXINTS !
    _RST-NEDGES @ 0 DO
        I CELLS _RST-EY0 + @              ( ey0 )
        _RST-CUR-Y @ OVER >= IF           ( ey0 )  \ y >= y0?
            DROP
            I CELLS _RST-EY1 + @          ( ey1 )
            _RST-CUR-Y @ OVER < IF        ( ey1 )  \ y < y1?
                DROP
                \ Compute x-intercept
                I CELLS _RST-EX1 + @ I CELLS _RST-EX0 + @ -  ( dx )
                _RST-CUR-Y @ I CELLS _RST-EY0 + @ -          ( dx dy_rel )
                *                                              ( dx*dy_rel )
                I CELLS _RST-EY1 + @ I CELLS _RST-EY0 + @ -  ( num denom )
                /                                              ( dx_scaled )
                I CELLS _RST-EX0 + @ +                        ( x_int )
                \ Store if room
                _RST-NXINTS @ _RST-MAX-XINTS < IF
                    _RST-NXINTS @ CELLS _RST-XINTS + !
                    _RST-NXINTS @ 1+ _RST-NXINTS !
                ELSE
                    DROP
                THEN
            ELSE
                DROP
            THEN
        ELSE
            DROP
        THEN
    LOOP ;

\ =====================================================================
\  Sort x-intercepts (insertion sort — small N)
\ =====================================================================

: _RST-SORT-XINTS  ( -- )
    _RST-NXINTS @ 2 < IF EXIT THEN
    _RST-NXINTS @ 1 DO
        I CELLS _RST-XINTS + @        ( key )
        I                             ( key j )
        BEGIN
            DUP 0> IF
                DUP 1- CELLS _RST-XINTS + @ 2 PICK > IF
                    \ Shift element right
                    DUP 1- CELLS _RST-XINTS + @
                    OVER CELLS _RST-XINTS + !
                    1-
                    FALSE                \ continue
                ELSE
                    TRUE                 \ stop
                THEN
            ELSE
                TRUE
            THEN
        UNTIL
        CELLS _RST-XINTS + !          \ store key at final position
    LOOP ;

\ =====================================================================
\  Fill scanline between intercept pairs (even-odd rule)
\ =====================================================================
\  Bitmap format: 1 byte per pixel, row-major, 0=empty, 0xFF=filled
\  RAST-FILL writes into caller-supplied buffer.

VARIABLE _RST-BUF    \ bitmap base address
VARIABLE _RST-WIDTH  \ bitmap width in pixels

: _RST-FILL-SPAN  ( x_start x_end y -- )
    \ Clip to [0, width)
    _RST-WIDTH @ >R
    ROT 0 MAX R@ MIN                  ( x_end y x_start' )
    ROT 0 MAX R@ MIN                  ( y x_start' x_end' )
    ROT R> * _RST-BUF @ +             ( x_start' x_end' row_addr )
    >R
    OVER - DUP 1 < IF
        2DROP R> DROP EXIT
    THEN                               ( x_start' count )
    SWAP R> +                          ( count pixel_addr )
    SWAP 0 DO
        0xFF OVER C!
        1+
    LOOP DROP ;

VARIABLE _RST-SCAN-Y
VARIABLE _RST-PAIR-I

: _RST-FILL-PAIRS  ( y -- )
    _RST-SCAN-Y !
    0 _RST-PAIR-I !
    BEGIN _RST-PAIR-I @ 2 * 1+ _RST-NXINTS @ < WHILE
        _RST-PAIR-I @ 2 * CELLS _RST-XINTS + @
        _RST-PAIR-I @ 2 * 1+ CELLS _RST-XINTS + @
        _RST-SCAN-Y @ _RST-FILL-SPAN
        _RST-PAIR-I @ 1+ _RST-PAIR-I !
    REPEAT ;

: RAST-FILL  ( buf-addr width height -- )
    >R _RST-WIDTH !  _RST-BUF !
    \ Clear buffer
    _RST-BUF @ _RST-WIDTH @ R@ * 0 FILL
    \ For each scanline
    R> 0 DO
        I _RST-COLLECT-XINTS
        _RST-SORT-XINTS
        I _RST-FILL-PAIRS
    LOOP ;

\ =====================================================================
\  Glyph contour → edge table (Stage C)
\ =====================================================================
\  Walks decoded glyph contours (from ttf.f's TTF-DECODE-GLYPH),
\  scales coordinates, and feeds edges into the raster edge table.
\
\  TrueType contours: sequence of on-curve and off-curve points.
\  Off-curve points are quadratic Bézier control points.
\  Two consecutive off-curve points have an implied on-curve midpoint.
\
\  For now (C1): all points treated as line vertices (coarse but
\  functional — Bézier flatten integration comes in Stage C2).

REQUIRE ttf.f

VARIABLE _RST-SCALE-N   \ numerator: target pixel size
VARIABLE _RST-SCALE-D   \ denominator: unitsPerEm
VARIABLE _RST-YFLIP     \ target height for Y-flip

: RAST-SCALE!  ( pixel-size upem -- )
    _RST-SCALE-D !  _RST-SCALE-N ! ;

: _RST-SCALE-X  ( font-x -- pixel-x )
    _RST-SCALE-N @ * _RST-SCALE-D @ / ;

: _RST-SCALE-Y  ( font-y -- pixel-y )
    _RST-SCALE-N @ * _RST-SCALE-D @ /
    _RST-YFLIP @ SWAP - ;            \ flip Y (TTF y-up → screen y-down)

\ Walk one contour from point index 'start' to 'end' (inclusive).
\ Emits edges between consecutive points, closing the contour.
VARIABLE _RST-PREV-X   VARIABLE _RST-PREV-Y
VARIABLE _RST-FIRST-X  VARIABLE _RST-FIRST-Y
VARIABLE _RST-CONT-S   VARIABLE _RST-CONT-E

: _RST-WALK-CONTOUR  ( start end -- )
    _RST-CONT-E !  _RST-CONT-S !
    \ First point → prev and first
    _RST-CONT-S @ TTF-PT-X _RST-SCALE-X
    DUP _RST-PREV-X !  _RST-FIRST-X !
    _RST-CONT-S @ TTF-PT-Y _RST-SCALE-Y
    DUP _RST-PREV-Y !  _RST-FIRST-Y !
    \ Remaining points
    _RST-CONT-E @ 1+ _RST-CONT-S @ 1+ DO
        _RST-PREV-X @ _RST-PREV-Y @
        I TTF-PT-X _RST-SCALE-X
        I TTF-PT-Y _RST-SCALE-Y
        2DUP _RST-PREV-Y ! _RST-PREV-X !
        RAST-EDGE
    LOOP
    \ Close contour: prev → first
    _RST-PREV-X @ _RST-PREV-Y @
    _RST-FIRST-X @ _RST-FIRST-Y @
    RAST-EDGE ;

\ Rasterize a glyph into a bitmap buffer.
\ Pre: TTF-PARSE-HEAD, MAXP, LOCA, GLYF already called.
VARIABLE _RST-G-BUF  VARIABLE _RST-G-W  VARIABLE _RST-G-H

: RAST-GLYPH  ( glyph-id pixel-size buf-addr w h -- ok? )
    DUP _RST-YFLIP !
    _RST-G-H !  _RST-G-W !  _RST-G-BUF !   ( gid pxsz )
    TTF-UPEM RAST-SCALE!                     ( gid )
    RAST-RESET
    TTF-DECODE-GLYPH                         ( npts ncont | 0 0 )
    DUP 0= IF 2DROP FALSE EXIT THEN
    \ Walk each contour
    0                                        ( npts ncont start )
    SWAP 0 DO                                ( npts start )
        DUP I TTF-CONT-END                   ( npts start end )
        _RST-WALK-CONTOUR                    ( npts )
        I TTF-CONT-END 1+                    ( npts next-start )
    LOOP
    2DROP
    _RST-G-BUF @ _RST-G-W @ _RST-G-H @ RAST-FILL
    TRUE ;
