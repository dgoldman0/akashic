\ rect.f — Axis-aligned rectangles (FP16)
\
\ Rectangles are stored as 4 consecutive FP16 values in memory:
\   offset +0*CELL: x   (left edge)
\   offset +1*CELL: y   (top edge)
\   offset +2*CELL: w   (width)
\   offset +3*CELL: h   (height)
\
\ All coordinates and dimensions are FP16.
\ Addresses passed to these words point to the first cell (x).
\
\ Prefix: RECT-   (public API)
\         _RECT-  (internal helpers)
\
\ Load with:   REQUIRE rect.f
\   (auto-loads fp16.f, fp16-ext.f via REQUIRE)
\
\ === Public API ===
\   RECT-CONTAINS?  ( rect px py -- flag )    point-in-rect test
\   RECT-INTERSECT? ( r1 r2 -- flag )         do two rects overlap?
\   RECT-INTERSECT  ( r1 r2 dst -- flag )     compute intersection rect
\   RECT-UNION      ( r1 r2 dst -- )          bounding rect of two rects
\   RECT-EXPAND     ( rect margin dst -- )    expand by margin on all sides
\   RECT-AREA       ( rect -- area )          width × height
\   RECT-CENTER     ( rect -- cx cy )         center point
\   RECT-EMPTY?     ( rect -- flag )          zero or negative area?

REQUIRE fp16-ext.f

PROVIDED akashic-rect

\ =====================================================================
\  Memory layout helpers
\ =====================================================================

: _RECT-X  ( base -- addr )  ;                    \ +0 cells
: _RECT-Y  ( base -- addr )  CELL+ ;              \ +1 cell
: _RECT-W  ( base -- addr )  2 CELLS + ;          \ +2 cells
: _RECT-H  ( base -- addr )  3 CELLS + ;          \ +3 cells

: _RECT@  ( elem-addr -- fp16 )  @ 0xFFFF AND ;
: _RECT!  ( fp16 elem-addr -- )  SWAP 0xFFFF AND SWAP ! ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _R-X1   VARIABLE _R-Y1   VARIABLE _R-W1   VARIABLE _R-H1
VARIABLE _R-X2   VARIABLE _R-Y2   VARIABLE _R-W2   VARIABLE _R-H2
VARIABLE _R-TMP

\ Read a rect into scratch set 1
: _RECT-READ1  ( addr -- )
    DUP _RECT-X _RECT@  _R-X1 !
    DUP _RECT-Y _RECT@  _R-Y1 !
    DUP _RECT-W _RECT@  _R-W1 !
        _RECT-H _RECT@  _R-H1 !
    ;

\ Read a rect into scratch set 2
: _RECT-READ2  ( addr -- )
    DUP _RECT-X _RECT@  _R-X2 !
    DUP _RECT-Y _RECT@  _R-Y2 !
    DUP _RECT-W _RECT@  _R-W2 !
        _RECT-H _RECT@  _R-H2 !
    ;

\ Write scratch set 1 to a rect address
: _RECT-WRITE1  ( addr -- )
    DUP _R-X1 @ SWAP _RECT-X _RECT!
    DUP _R-Y1 @ SWAP _RECT-Y _RECT!
    DUP _R-W1 @ SWAP _RECT-W _RECT!
        _R-H1 @ SWAP _RECT-H _RECT!
    ;

\ =====================================================================
\  RECT-AREA — width × height
\ =====================================================================

: RECT-AREA  ( rect -- area )
    DUP _RECT-W _RECT@
    SWAP _RECT-H _RECT@
    FP16-MUL ;

\ =====================================================================
\  RECT-EMPTY? — zero or negative area?
\ =====================================================================

: RECT-EMPTY?  ( rect -- flag )
    DUP _RECT-W _RECT@
    SWAP _RECT-H _RECT@                ( w h )
    \ Empty if w <= 0 or h <= 0
    FP16-POS-ZERO FP16-LE IF
        DROP -1 EXIT
    THEN
    FP16-POS-ZERO FP16-LE ;

\ =====================================================================
\  RECT-CENTER — center point
\ =====================================================================

: RECT-CENTER  ( rect -- cx cy )
    DUP _RECT-X _RECT@
    OVER _RECT-W _RECT@
    FP16-POS-HALF FP16-MUL FP16-ADD   ( rect cx )
    SWAP
    DUP _RECT-Y _RECT@
    SWAP _RECT-H _RECT@
    FP16-POS-HALF FP16-MUL FP16-ADD   ( cx cy )
    ;

\ =====================================================================
\  RECT-CONTAINS? — point-in-rect test
\ =====================================================================
\  Point (px, py) is inside rect if:
\    px >= x  AND  px < x+w  AND  py >= y  AND  py < y+h

VARIABLE _RC-PX
VARIABLE _RC-PY

: RECT-CONTAINS?  ( rect px py -- flag )
    _RC-PY !  _RC-PX !                ( rect )
    _RECT-READ1
    \ Check px >= x1
    _RC-PX @ _R-X1 @ FP16-GE 0= IF 0 EXIT THEN
    \ Check px < x1 + w1
    _R-X1 @ _R-W1 @ FP16-ADD
    _RC-PX @ SWAP FP16-LT 0= IF 0 EXIT THEN
    \ Check py >= y1
    _RC-PY @ _R-Y1 @ FP16-GE 0= IF 0 EXIT THEN
    \ Check py < y1 + h1
    _R-Y1 @ _R-H1 @ FP16-ADD
    _RC-PY @ SWAP FP16-LT 0= IF 0 EXIT THEN
    -1 ;

\ =====================================================================
\  RECT-INTERSECT? — do two rects overlap?
\ =====================================================================
\  Overlap if:
\    x1 < x2+w2  AND  x2 < x1+w1  AND
\    y1 < y2+h2  AND  y2 < y1+h1

: RECT-INTERSECT?  ( r1 r2 -- flag )
    _RECT-READ2  _RECT-READ1
    \ x1 < x2+w2 ?
    _R-X2 @ _R-W2 @ FP16-ADD
    _R-X1 @ SWAP FP16-LT 0= IF 0 EXIT THEN
    \ x2 < x1+w1 ?
    _R-X1 @ _R-W1 @ FP16-ADD
    _R-X2 @ SWAP FP16-LT 0= IF 0 EXIT THEN
    \ y1 < y2+h2 ?
    _R-Y2 @ _R-H2 @ FP16-ADD
    _R-Y1 @ SWAP FP16-LT 0= IF 0 EXIT THEN
    \ y2 < y1+h1 ?
    _R-Y1 @ _R-H1 @ FP16-ADD
    _R-Y2 @ SWAP FP16-LT 0= IF 0 EXIT THEN
    -1 ;

\ =====================================================================
\  RECT-INTERSECT — compute intersection rectangle
\ =====================================================================
\  Returns flag: TRUE if non-empty intersection, FALSE if disjoint.
\  When disjoint, dst is zeroed.

VARIABLE _RI-LX   VARIABLE _RI-LY
VARIABLE _RI-RX   VARIABLE _RI-RY

: RECT-INTERSECT  ( r1 r2 dst -- flag )
    >R                                 ( r1 r2 ) ( R: dst )
    _RECT-READ2  _RECT-READ1
    \ left-x = max(x1, x2)
    _R-X1 @ _R-X2 @ FP16-MAX _RI-LX !
    \ top-y = max(y1, y2)
    _R-Y1 @ _R-Y2 @ FP16-MAX _RI-LY !
    \ right-x = min(x1+w1, x2+w2)
    _R-X1 @ _R-W1 @ FP16-ADD
    _R-X2 @ _R-W2 @ FP16-ADD
    FP16-MIN _RI-RX !
    \ bottom-y = min(y1+h1, y2+h2)
    _R-Y1 @ _R-H1 @ FP16-ADD
    _R-Y2 @ _R-H2 @ FP16-ADD
    FP16-MIN _RI-RY !
    \ width = rx - lx,  height = ry - ly
    _RI-RX @ _RI-LX @ FP16-SUB        ( w )
    _RI-RY @ _RI-LY @ FP16-SUB        ( w h )
    \ Check if intersection is valid (w > 0 and h > 0)
    OVER FP16-POS-ZERO FP16-GT
    OVER FP16-POS-ZERO FP16-GT AND IF
        \ Valid intersection — write to dst
        R>                             ( w h dst )
        DUP _RI-LX @ SWAP _RECT-X _RECT!
        DUP _RI-LY @ SWAP _RECT-Y _RECT!
        ROT OVER _RECT-W _RECT!       ( h dst )
        SWAP OVER _RECT-H _RECT!      ( dst )
        DROP -1
    ELSE
        \ Disjoint — zero dst
        2DROP R>
        DUP FP16-POS-ZERO SWAP _RECT-X _RECT!
        DUP FP16-POS-ZERO SWAP _RECT-Y _RECT!
        DUP FP16-POS-ZERO SWAP _RECT-W _RECT!
            FP16-POS-ZERO SWAP _RECT-H _RECT!
        0
    THEN ;

\ =====================================================================
\  RECT-UNION — bounding rect of two rects
\ =====================================================================

: RECT-UNION  ( r1 r2 dst -- )
    >R                                 ( r1 r2 ) ( R: dst )
    _RECT-READ2  _RECT-READ1
    \ left = min(x1, x2)
    _R-X1 @ _R-X2 @ FP16-MIN _RI-LX !
    \ top = min(y1, y2)
    _R-Y1 @ _R-Y2 @ FP16-MIN _RI-LY !
    \ right = max(x1+w1, x2+w2)
    _R-X1 @ _R-W1 @ FP16-ADD
    _R-X2 @ _R-W2 @ FP16-ADD
    FP16-MAX _RI-RX !
    \ bottom = max(y1+h1, y2+h2)
    _R-Y1 @ _R-H1 @ FP16-ADD
    _R-Y2 @ _R-H2 @ FP16-ADD
    FP16-MAX _RI-RY !
    \ Write result
    R>                                 ( dst )
    DUP _RI-LX @ SWAP _RECT-X _RECT!
    DUP _RI-LY @ SWAP _RECT-Y _RECT!
    DUP _RI-RX @ _RI-LX @ FP16-SUB SWAP _RECT-W _RECT!
        _RI-RY @ _RI-LY @ FP16-SUB SWAP _RECT-H _RECT!
    ;

\ =====================================================================
\  RECT-EXPAND — expand rect by margin on all sides
\ =====================================================================
\  New rect: (x-m, y-m, w+2m, h+2m)

: RECT-EXPAND  ( rect margin dst -- )
    >R                                 ( rect margin ) ( R: dst )
    _R-TMP !                           \ margin saved
    _RECT-READ1
    \ x' = x - margin
    _R-X1 @ _R-TMP @ FP16-SUB
    R@ _RECT-X _RECT!
    \ y' = y - margin
    _R-Y1 @ _R-TMP @ FP16-SUB
    R@ _RECT-Y _RECT!
    \ w' = w + 2*margin
    _R-TMP @ 0x4000 FP16-MUL          ( 2*margin )
    DUP _R-W1 @ FP16-ADD
    R@ _RECT-W _RECT!
    \ h' = h + 2*margin
    _R-H1 @ FP16-ADD
    R> _RECT-H _RECT!
    ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _rect-guard

' RECT-AREA       CONSTANT _rect-area-xt
' RECT-EMPTY?     CONSTANT _rect-empty-q-xt
' RECT-CENTER     CONSTANT _rect-center-xt
' RECT-CONTAINS?  CONSTANT _rect-contains-q-xt
' RECT-INTERSECT? CONSTANT _rect-intersect-q-xt
' RECT-INTERSECT  CONSTANT _rect-intersect-xt
' RECT-UNION      CONSTANT _rect-union-xt
' RECT-EXPAND     CONSTANT _rect-expand-xt

: RECT-AREA       _rect-area-xt _rect-guard WITH-GUARD ;
: RECT-EMPTY?     _rect-empty-q-xt _rect-guard WITH-GUARD ;
: RECT-CENTER     _rect-center-xt _rect-guard WITH-GUARD ;
: RECT-CONTAINS?  _rect-contains-q-xt _rect-guard WITH-GUARD ;
: RECT-INTERSECT? _rect-intersect-q-xt _rect-guard WITH-GUARD ;
: RECT-INTERSECT  _rect-intersect-xt _rect-guard WITH-GUARD ;
: RECT-UNION      _rect-union-xt _rect-guard WITH-GUARD ;
: RECT-EXPAND     _rect-expand-xt _rect-guard WITH-GUARD ;
[THEN] [THEN]
