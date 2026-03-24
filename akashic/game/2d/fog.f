\ =====================================================================
\  akashic/game/2d/fog.f — Fog of War (pure logic)
\ =====================================================================
\
\  Per-tile visibility layer.  Three visibility states per tile:
\    0 — FOG-UNSEEN    Never seen.
\    1 — FOG-REMEMBERED Seen previously but not currently visible.
\    2 — FOG-VISIBLE    Currently in line-of-sight.
\
\  Uses recursive shadowcasting (octant-symmetric) to compute a
\  circular field of view from a centre point.  The algorithm works
\  in 8 octants; within each octant it walks rows outward from the
\  origin, tracking a start/end slope to find which tiles are lit
\  and which are blocked.
\
\  Fog Descriptor (32 bytes, 4 cells):
\    +0   width       Map width
\    +8   height      Map height
\    +16  data        Visibility array (w×h bytes, one byte per tile)
\    +24  blocked-xt  Callback ( x y -- flag ) returns true if tile
\                     blocks line-of-sight (wall, etc.)
\
\  Public API:
\    FOG-NEW       ( w h blocked-xt -- fog )
\    FOG-FREE      ( fog -- )
\    FOG-REVEAL    ( fog cx cy radius -- )
\    FOG-HIDE-ALL  ( fog -- )
\    FOG-STATE     ( fog x y -- 0|1|2 )
\
\  Prefix: FOG- (public), _FOG- (internal)
\  Provider: akashic-game-2d-fog
\  Dependencies: (standalone)

PROVIDED akashic-game-2d-fog

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0 CONSTANT FOG-UNSEEN
1 CONSTANT FOG-REMEMBERED
2 CONSTANT FOG-VISIBLE

0  CONSTANT _FOG-O-W
8  CONSTANT _FOG-O-H
16 CONSTANT _FOG-O-DATA
24 CONSTANT _FOG-O-BLOCKED
32 CONSTANT _FOG-DESC-SZ

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

VARIABLE _FOG-TMP-W
VARIABLE _FOG-TMP-H
VARIABLE _FOG-TMP-XT
VARIABLE _FOG-TMP-FOG
VARIABLE _FOG-TMP-SZ

: FOG-NEW  ( w h blocked-xt -- fog )
    _FOG-TMP-XT ! _FOG-TMP-H ! _FOG-TMP-W !
    _FOG-DESC-SZ ALLOCATE
    0<> ABORT" FOG-NEW: desc alloc"
    _FOG-TMP-FOG !
    _FOG-TMP-FOG @ _FOG-DESC-SZ 0 FILL
    _FOG-TMP-W @  _FOG-TMP-FOG @ _FOG-O-W + !
    _FOG-TMP-H @  _FOG-TMP-FOG @ _FOG-O-H + !
    _FOG-TMP-XT @ _FOG-TMP-FOG @ _FOG-O-BLOCKED + !
    \ Allocate data array
    _FOG-TMP-W @ _FOG-TMP-H @ * _FOG-TMP-SZ !
    _FOG-TMP-SZ @ ALLOCATE
    0<> ABORT" FOG-NEW: data alloc"
    DUP _FOG-TMP-SZ @ 0 FILL
    _FOG-TMP-FOG @ _FOG-O-DATA + !
    _FOG-TMP-FOG @ ;

: FOG-FREE  ( fog -- )
    DUP _FOG-O-DATA + @ FREE
    FREE ;

\ =====================================================================
\  §3 — Basic Accessors
\ =====================================================================

\ In-bounds check
VARIABLE _FOG-IB-X
VARIABLE _FOG-IB-Y
: _FOG-INBOUNDS?  ( fog x y -- flag )
    _FOG-IB-Y ! _FOG-IB-X !
    _FOG-IB-X @ 0< IF DROP 0 EXIT THEN
    _FOG-IB-Y @ 0< IF DROP 0 EXIT THEN
    _FOG-IB-X @ OVER _FOG-O-W + @ >= IF DROP 0 EXIT THEN
    _FOG-IB-Y @ SWAP _FOG-O-H + @ >= IF 0 EXIT THEN
    -1 ;

\ Get/set single tile state
VARIABLE _FOG-AD-FOG
VARIABLE _FOG-AD-X
VARIABLE _FOG-AD-Y
: _FOG-ADDR  ( fog x y -- byte-addr )
    _FOG-AD-Y ! _FOG-AD-X ! _FOG-AD-FOG !
    _FOG-AD-FOG @ _FOG-O-DATA + @
    _FOG-AD-Y @ _FOG-AD-FOG @ _FOG-O-W + @ * +
    _FOG-AD-X @ + ;

VARIABLE _FOG-ST-FOG
VARIABLE _FOG-ST-X
VARIABLE _FOG-ST-Y
: FOG-STATE  ( fog x y -- 0|1|2 )
    _FOG-ST-Y ! _FOG-ST-X ! _FOG-ST-FOG !
    _FOG-ST-FOG @ _FOG-ST-X @ _FOG-ST-Y @ _FOG-INBOUNDS? 0= IF
        0 EXIT
    THEN
    _FOG-ST-FOG @ _FOG-ST-X @ _FOG-ST-Y @ _FOG-ADDR C@ ;

VARIABLE _FOG-SS-V
: _FOG-SET  ( fog x y val -- )
    _FOG-SS-V !
    _FOG-ADDR _FOG-SS-V @ SWAP C! ;

\ =====================================================================
\  §4 — FOG-HIDE-ALL
\ =====================================================================
\
\  Demote all VISIBLE tiles to REMEMBERED.  Called before each
\  FOG-REVEAL pass to reset the "currently visible" set.

VARIABLE _FOG-HA-FOG
VARIABLE _FOG-HA-SZ
VARIABLE _FOG-HA-I
: FOG-HIDE-ALL  ( fog -- )
    _FOG-HA-FOG !
    _FOG-HA-FOG @ _FOG-O-W + @
    _FOG-HA-FOG @ _FOG-O-H + @ * _FOG-HA-SZ !
    0 _FOG-HA-I !
    BEGIN _FOG-HA-I @ _FOG-HA-SZ @ < WHILE
        _FOG-HA-FOG @ _FOG-O-DATA + @ _FOG-HA-I @ +
        DUP C@ FOG-VISIBLE = IF
            FOG-REMEMBERED SWAP C!
        ELSE
            DROP
        THEN
        1 _FOG-HA-I +!
    REPEAT ;

\ =====================================================================
\  §5 — Shadowcast FOV: FOG-REVEAL
\ =====================================================================
\
\  Recursive shadowcasting in 8 octants.  Each octant walks rows
\  (distance from cx,cy) outward and tracks a slope-range
\  [start_slope, end_slope] expressed as ratios in fixed-point
\  (16.16).  This avoids floating point entirely.
\
\  Fixed-point: 1.0 = 65536 (16 bits fractional).
\  Slope = column / row in octant-local coordinates.

65536 CONSTANT _FOG-FP1     \ 1.0 in 16.16 fixed-point

\ Transform octant-local (row, col) to world (x, y).
\ Octants 0–7 cover the 8 symmetric sections of a circle.
\ Each octant maps (row,col) → (dx,dy) relative to centre.

\ We use a dispatch approach with VARIABLEs to avoid deep stacks.
VARIABLE _FOG-SC-CX
VARIABLE _FOG-SC-CY
VARIABLE _FOG-SC-FOG
VARIABLE _FOG-SC-RAD
VARIABLE _FOG-SC-OCT

VARIABLE _FOG-OT-ROW
VARIABLE _FOG-OT-COL
VARIABLE _FOG-OT-DX
VARIABLE _FOG-OT-DY

: _FOG-OCTANT-XY  ( oct row col -- x y )
    _FOG-OT-COL ! _FOG-OT-ROW !
    DUP 0 = IF  _FOG-OT-COL @             _FOG-OT-DX !  _FOG-OT-ROW @ NEGATE  _FOG-OT-DY !  THEN
    DUP 1 = IF  _FOG-OT-ROW @             _FOG-OT-DX !  _FOG-OT-COL @ NEGATE  _FOG-OT-DY !  THEN
    DUP 2 = IF  _FOG-OT-ROW @             _FOG-OT-DX !  _FOG-OT-COL @          _FOG-OT-DY !  THEN
    DUP 3 = IF  _FOG-OT-COL @             _FOG-OT-DX !  _FOG-OT-ROW @          _FOG-OT-DY !  THEN
    DUP 4 = IF  _FOG-OT-COL @ NEGATE      _FOG-OT-DX !  _FOG-OT-ROW @          _FOG-OT-DY !  THEN
    DUP 5 = IF  _FOG-OT-ROW @ NEGATE      _FOG-OT-DX !  _FOG-OT-COL @          _FOG-OT-DY !  THEN
    DUP 6 = IF  _FOG-OT-ROW @ NEGATE      _FOG-OT-DX !  _FOG-OT-COL @ NEGATE  _FOG-OT-DY !  THEN
    DUP 7 = IF  _FOG-OT-COL @ NEGATE      _FOG-OT-DX !  _FOG-OT-ROW @ NEGATE  _FOG-OT-DY !  THEN
    DROP
    _FOG-SC-CX @ _FOG-OT-DX @ +
    _FOG-SC-CY @ _FOG-OT-DY @ + ;

\ Check if a tile blocks LOS.
VARIABLE _FOG-BK-X
VARIABLE _FOG-BK-Y
: _FOG-BLOCKED?  ( x y -- flag )
    _FOG-BK-Y ! _FOG-BK-X !
    _FOG-SC-FOG @ _FOG-BK-X @ _FOG-BK-Y @ _FOG-INBOUNDS? 0= IF
        -1 EXIT  \ Out-of-bounds counts as blocked
    THEN
    _FOG-BK-X @ _FOG-BK-Y @ _FOG-SC-FOG @ _FOG-O-BLOCKED + @ EXECUTE ;

\ Mark a tile as visible.
VARIABLE _FOG-MV-X
VARIABLE _FOG-MV-Y
: _FOG-MARK-VIS  ( x y -- )
    _FOG-MV-Y ! _FOG-MV-X !
    _FOG-SC-FOG @ _FOG-MV-X @ _FOG-MV-Y @ _FOG-INBOUNDS? 0= IF
        EXIT
    THEN
    _FOG-SC-FOG @ _FOG-MV-X @ _FOG-MV-Y @ FOG-VISIBLE _FOG-SET ;

\ Fixed-point slope of a column within a row.
\ slope = (col * FP1) / row  — but protect against row=0.
: _FOG-SLOPE  ( col row -- fp-slope )
    DUP 0= IF 2DROP _FOG-FP1 EXIT THEN
    SWAP _FOG-FP1 * SWAP / ;

\ _FOG-CAST-OCTANT ( oct row start-slope end-slope -- )
\   Recursive shadowcast for one octant.
\   start-slope and end-slope are 16.16 fixed-point values.
\   start >= end invariant (we scan from high slope to low).

VARIABLE _FOG-CO-SS        \ start-slope
VARIABLE _FOG-CO-ES        \ end-slope
VARIABLE _FOG-CO-ROW       \ current row distance
VARIABLE _FOG-CO-OCT       \ octant id
VARIABLE _FOG-CO-COL       \ column iterator
VARIABLE _FOG-CO-MINCOL
VARIABLE _FOG-CO-MAXCOL
VARIABLE _FOG-CO-BLOCKED   \ was previous tile blocked?
VARIABLE _FOG-CO-NEWSTART  \ new start-slope after a blocked run
VARIABLE _FOG-CO-CX        \ world x of current tile
VARIABLE _FOG-CO-CY        \ world y of current tile
VARIABLE _FOG-CO-TSLOPE    \ tile centre slope (approx)

: _FOG-CAST-OCTANT  ( oct row start-slope end-slope -- )
    _FOG-CO-ES ! _FOG-CO-SS ! _FOG-CO-ROW ! _FOG-CO-OCT !
    \ Base cases
    _FOG-CO-SS @ _FOG-CO-ES @ < IF EXIT THEN
    _FOG-CO-ROW @ _FOG-SC-RAD @ > IF EXIT THEN
    \ Compute column range for this row
    \ min-col = end-slope * row / FP1  (rounded down)
    _FOG-CO-ES @ _FOG-CO-ROW @ * _FOG-FP1 / _FOG-CO-MINCOL !
    \ max-col = start-slope * row / FP1 (rounded up)
    _FOG-CO-SS @ _FOG-CO-ROW @ * _FOG-FP1 1- + _FOG-FP1 / _FOG-CO-MAXCOL !
    0 _FOG-CO-BLOCKED !
    _FOG-CO-SS @ _FOG-CO-NEWSTART !
    _FOG-CO-MINCOL @ _FOG-CO-COL !
    BEGIN _FOG-CO-COL @ _FOG-CO-MAXCOL @ <= WHILE
        \ Transform to world coords
        _FOG-CO-OCT @ _FOG-CO-ROW @ _FOG-CO-COL @
        _FOG-OCTANT-XY
        _FOG-CO-CY ! _FOG-CO-CX !
        \ Check if within radius (squared distance)
        _FOG-CO-ROW @ _FOG-CO-ROW @ * _FOG-CO-COL @ _FOG-CO-COL @ * +
        _FOG-SC-RAD @ _FOG-SC-RAD @ * <= IF
            \ Mark visible
            _FOG-CO-CX @ _FOG-CO-CY @ _FOG-MARK-VIS
        THEN
        \ Check if blocked
        _FOG-CO-CX @ _FOG-CO-CY @ _FOG-BLOCKED?
        IF  \ current tile is opaque
            _FOG-CO-BLOCKED @ 0= IF
                \ Start of a blocked run
                _FOG-CO-COL @ 2 * 1- _FOG-CO-ROW @ 2 * _FOG-SLOPE
                _FOG-CO-NEWSTART !
            THEN
            -1 _FOG-CO-BLOCKED !
        ELSE  \ current tile is transparent
            _FOG-CO-BLOCKED @ IF
                \ End of a blocked run — recurse for the unblocked
                \ section above the wall.
                \ Save state across recursive call
                _FOG-CO-ES @ >R _FOG-CO-SS @ >R
                _FOG-CO-ROW @ >R _FOG-CO-OCT @ >R
                _FOG-CO-MAXCOL @ >R _FOG-CO-COL @ >R
                _FOG-CO-OCT @
                _FOG-CO-ROW @ 1+
                _FOG-CO-NEWSTART @
                _FOG-CO-COL @ 2 * 1- _FOG-CO-ROW @ 2 * _FOG-SLOPE
                RECURSE
                \ Restore state
                R> _FOG-CO-COL ! R> _FOG-CO-MAXCOL !
                R> _FOG-CO-OCT ! R> _FOG-CO-ROW !
                R> _FOG-CO-SS ! R> _FOG-CO-ES !
            THEN
            0 _FOG-CO-BLOCKED !
        THEN
        1 _FOG-CO-COL +!
    REPEAT
    \ If last tile in the row was not blocked, recurse to next row
    _FOG-CO-BLOCKED @ 0= IF
        _FOG-CO-OCT @
        _FOG-CO-ROW @ 1+
        _FOG-CO-SS @
        _FOG-CO-ES @
        RECURSE
    THEN ;

\ FOG-REVEAL ( fog cx cy radius -- )
VARIABLE _FOG-RV-I
: FOG-REVEAL  ( fog cx cy radius -- )
    _FOG-SC-RAD ! _FOG-SC-CY ! _FOG-SC-CX ! _FOG-SC-FOG !
    \ Mark origin visible
    _FOG-SC-CX @ _FOG-SC-CY @ _FOG-MARK-VIS
    \ Cast 8 octants
    0 _FOG-RV-I !
    BEGIN _FOG-RV-I @ 8 < WHILE
        _FOG-RV-I @                    \ octant
        1                              \ row = 1
        _FOG-FP1                       \ start-slope = 1.0
        0                              \ end-slope = 0.0
        _FOG-CAST-OCTANT
        1 _FOG-RV-I +!
    REPEAT ;

\ =====================================================================
\  §6 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _fog-guard

' FOG-NEW      CONSTANT _fog-new-xt
' FOG-FREE     CONSTANT _fog-free-xt
' FOG-REVEAL   CONSTANT _fog-reveal-xt
' FOG-HIDE-ALL CONSTANT _fog-hide-xt
' FOG-STATE    CONSTANT _fog-state-xt

: FOG-NEW      _fog-new-xt    _fog-guard WITH-GUARD ;
: FOG-FREE     _fog-free-xt   _fog-guard WITH-GUARD ;
: FOG-REVEAL   _fog-reveal-xt _fog-guard WITH-GUARD ;
: FOG-HIDE-ALL _fog-hide-xt   _fog-guard WITH-GUARD ;
: FOG-STATE    _fog-state-xt  _fog-guard WITH-GUARD ;
[THEN] [THEN]
