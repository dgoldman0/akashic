\ raster.f — Scanline rasterizer for glyph outlines (Stage C2)
\
\ Takes line segments (edges), rasterizes into a monochrome
\ bitmap using even-odd scanline fill.
\
\ Contour walker handles TrueType on-curve and off-curve points:
\ off-curve quadratic Bézier control points are flattened via
\ BZ-QUAD-FLATTEN from bezier.f.  Consecutive off-curve points
\ generate implied on-curve midpoints per the TrueType spec.
\
\ Coordinates are integers (pre-scaled from font units to pixels).
\ Caller is responsible for coordinate scaling and Y-flip.
\
\ Prefix: RAST-  (public API)
\         _RST-  (internal helpers)
\
\ Load with:   REQUIRE raster.f

PROVIDED akashic-raster
REQUIRE ../math/fixed.f

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
\  Stage C2: Off-curve points are flattened via BZ-QUAD-FLATTEN from
\  bezier.f.  Coordinates are converted to FP16 for the Bézier math,
\  then back to integers for edge insertion.

REQUIRE ttf.f
REQUIRE ../math/bezier.f

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

\ ── Bézier flatten support ──────────────────────────────────────────
\ Tolerance: 0.25 pixel in FP16.  Good for 8-64 px sizes.
0x3400 CONSTANT _RST-BZ-TOL

\ Callback for BZ-QUAD-FLATTEN: receives ( x0 y0 x1 y1 ) in FP16,
\ converts to integer pixel coords, and emits a raster edge.
VARIABLE _RST-BZ-X0   VARIABLE _RST-BZ-Y0
VARIABLE _RST-BZ-X1   VARIABLE _RST-BZ-Y1

: _RST-BZ-CB  ( x0fp y0fp x1fp y1fp -- )
    FP16>INT _RST-BZ-Y1 !   FP16>INT _RST-BZ-X1 !
    FP16>INT _RST-BZ-Y0 !   FP16>INT _RST-BZ-X0 !
    _RST-BZ-X0 @ _RST-BZ-Y0 @ _RST-BZ-X1 @ _RST-BZ-Y1 @ RAST-EDGE ;

\ Emit a flattened quadratic Bézier from three integer pixel points.
\ Converts to FP16, calls BZ-QUAD-FLATTEN with _RST-BZ-CB.
: _RST-EMIT-QUAD  ( x0 y0 x1 y1 x2 y2 -- )
    INT>FP16 >R INT>FP16 R>           ( x0 y0 x1 y1 x2fp y2fp )
    >R >R                             ( x0 y0 x1 y1 ) ( R: y2fp x2fp )
    INT>FP16 >R INT>FP16 R>           ( x0 y0 x1fp y1fp )
    >R >R                             ( x0 y0 ) ( R: y2fp x2fp y1fp x1fp )
    INT>FP16 >R INT>FP16 R>           ( x0fp y0fp )
    R> R> R> R>                        ( x0fp y0fp x1fp y1fp x2fp y2fp )
    _RST-BZ-TOL ['] _RST-BZ-CB BZ-QUAD-FLATTEN ;

\ ── Contour walker (Stage C2) ──────────────────────────────────────
\ Walks decoded TrueType contour points, handling on-curve and
\ off-curve (quadratic control) points per the TrueType spec.
\
\ Algorithm:
\   - Find a starting on-curve point.  If the first point is off-curve,
\     check the last point: if on-curve, start there; otherwise the
\     implied midpoint of first and last off-curve points is the start.
\   - Walk points sequentially.  On-curve → emit line or quad.
\     Off-curve → accumulate; consecutive off-curve → implied midpoint.
\   - Close the contour back to the starting point.

VARIABLE _RST-PREV-X   VARIABLE _RST-PREV-Y   \ current on-curve pos
VARIABLE _RST-FIRST-X  VARIABLE _RST-FIRST-Y   \ contour start (on-curve)
VARIABLE _RST-CTRL-X   VARIABLE _RST-CTRL-Y    \ pending off-curve control pt
VARIABLE _RST-HAS-CTRL                          \ flag: have pending ctrl pt?
VARIABLE _RST-CONT-S   VARIABLE _RST-CONT-E    \ contour start/end indices
VARIABLE _RST-FIRST-OFF                         \ first pt was off-curve?

\ Helper: get scaled pixel coords for point index
: _RST-PX  ( i -- x )  TTF-PT-X _RST-SCALE-X ;
: _RST-PY  ( i -- y )  TTF-PT-Y _RST-SCALE-Y ;

\ Process an on-curve point at (px, py).
\ If we have a pending control point, emit a quad; otherwise a line.
VARIABLE _RST-OC-X   VARIABLE _RST-OC-Y

: _RST-ON-CURVE  ( px py -- )
    _RST-OC-Y !  _RST-OC-X !
    _RST-HAS-CTRL @ IF
        \ Emit quad: prev → ctrl → this
        _RST-PREV-X @ _RST-PREV-Y @
        _RST-CTRL-X @ _RST-CTRL-Y @
        _RST-OC-X @ _RST-OC-Y @
        _RST-EMIT-QUAD
        0 _RST-HAS-CTRL !
    ELSE
        \ Emit line: prev → this
        _RST-PREV-X @ _RST-PREV-Y @
        _RST-OC-X @ _RST-OC-Y @
        RAST-EDGE
    THEN
    _RST-OC-X @ _RST-PREV-X !
    _RST-OC-Y @ _RST-PREV-Y ! ;

\ Process an off-curve point at (px, py).
\ If we already have a pending ctrl, emit a quad to the implied
\ midpoint, then store this as the new pending ctrl.
VARIABLE _RST-NEW-X   VARIABLE _RST-NEW-Y
VARIABLE _RST-MID-X   VARIABLE _RST-MID-Y

: _RST-OFF-CURVE  ( px py -- )
    _RST-NEW-Y !  _RST-NEW-X !
    _RST-HAS-CTRL @ IF
        \ Implied on-curve midpoint between previous ctrl and this
        _RST-NEW-X @ _RST-CTRL-X @ + 2 /  _RST-MID-X !
        _RST-NEW-Y @ _RST-CTRL-Y @ + 2 /  _RST-MID-Y !
        \ Emit quad: prev → old ctrl → midpoint
        _RST-PREV-X @ _RST-PREV-Y @
        _RST-CTRL-X @ _RST-CTRL-Y @
        _RST-MID-X @ _RST-MID-Y @
        _RST-EMIT-QUAD
        \ Update prev to midpoint
        _RST-MID-X @ _RST-PREV-X !
        _RST-MID-Y @ _RST-PREV-Y !
    THEN
    _RST-NEW-X @ _RST-CTRL-X !
    _RST-NEW-Y @ _RST-CTRL-Y !
    1 _RST-HAS-CTRL ! ;

: _RST-WALK-CONTOUR  ( start end -- )
    _RST-CONT-E !  _RST-CONT-S !
    0 _RST-HAS-CTRL !
    0 _RST-FIRST-OFF !

    \ ── Determine starting on-curve point ──
    _RST-CONT-S @ TTF-PT-ONCURVE? IF
        \ First point is on-curve: use it directly
        _RST-CONT-S @ _RST-PX  DUP _RST-PREV-X !  _RST-FIRST-X !
        _RST-CONT-S @ _RST-PY  DUP _RST-PREV-Y !  _RST-FIRST-Y !
    ELSE
        \ First point is off-curve
        1 _RST-FIRST-OFF !
        _RST-CONT-E @ TTF-PT-ONCURVE? IF
            \ Last point is on-curve: start from last
            _RST-CONT-E @ _RST-PX  DUP _RST-PREV-X !  _RST-FIRST-X !
            _RST-CONT-E @ _RST-PY  DUP _RST-PREV-Y !  _RST-FIRST-Y !
        ELSE
            \ Both first and last are off-curve: implied midpoint
            _RST-CONT-S @ _RST-PX  _RST-CONT-E @ _RST-PX  + 2 /
            DUP _RST-PREV-X !  _RST-FIRST-X !
            _RST-CONT-S @ _RST-PY  _RST-CONT-E @ _RST-PY  + 2 /
            DUP _RST-PREV-Y !  _RST-FIRST-Y !
        THEN
    THEN

    \ ── Walk points ──
    _RST-CONT-E @ 1+ _RST-CONT-S @ DO
        \ Skip the starting point if it was on-curve (already consumed)
        I _RST-CONT-S @ = _RST-FIRST-OFF @ 0= AND IF
            \ skip — this is the on-curve start we already used
        ELSE
            I _RST-PX  I _RST-PY           ( px py )
            I TTF-PT-ONCURVE? IF
                _RST-ON-CURVE
            ELSE
                _RST-OFF-CURVE
            THEN
        THEN
    LOOP

    \ ── Close contour ──
    \ If there's a pending ctrl point, emit quad to first point
    _RST-HAS-CTRL @ IF
        _RST-PREV-X @ _RST-PREV-Y @
        _RST-CTRL-X @ _RST-CTRL-Y @
        _RST-FIRST-X @ _RST-FIRST-Y @
        _RST-EMIT-QUAD
    ELSE
        \ Just a line back to start
        _RST-PREV-X @ _RST-PREV-Y @
        _RST-FIRST-X @ _RST-FIRST-Y @
        RAST-EDGE
    THEN ;

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
