\ =====================================================================
\  akashic/game/2d/fog.f — Fog of War (pure logic)
\ =====================================================================
\
\  Per-tile visibility layer.  Three visibility states per tile:
\    0 — FOG-UNSEEN    Never seen.
\    1 — FOG-REMEMBERED Seen previously but not currently visible.
\    2 — FOG-VISIBLE    Currently in line-of-sight.
\
\  FOG-REVEAL lights the tiles a viewer sees within a radius, by
\  symmetric shadowcasting with exact rational slopes: a floor tile is
\  visible from the viewer exactly when the viewer is visible from it,
\  a blocking tile is visible when any part of it is, and walls cast
\  their full shadows.  The map's edge ends sight without darkening the
\  tiles inside it.  The scan works in four quadrants, each a stack of
\  rows outward from the viewer, and keeps that stack in the
\  descriptor, sized from the radius.
\
\  Several reveals, from lamps or relays, light one layer between
\  hides.  Each tile a reveal lights joins the descriptor's lit list,
\  so FOG-HIDE-ALL costs the tiles lit since the last hide, whatever
\  the map's size.
\
\  What blocks sight comes from the descriptor: nothing, until a source
\  is named; a collision map, read directly, whose nonzero tiles block;
\  or a token ( x y ctx -- flag ) with a context cell.  A reveal reads
\  only the descriptor and its arguments, so fogs are independent, and
\  a token may read any fog but must not reveal into its own.
\
\  Fog Descriptor (176 bytes):
\    +0   width       Map width
\    +8   height      Map height
\    +16  data        Visibility array (w×h bytes, one byte per tile)
\    +24  source      0 open, 1 collision map, 2 token
\    +32  src         The map's tile bytes, or the token
\    +40  ctx         The token's context cell
\    +48  lit         Lit list: tile indices lit since the last hide
\    +56  lit-n       Entries in the lit list
\    +64  lit-cap     Capacity of the lit list
\    +72  rows        Row stack (5 cells a row)
\    +80  rows-cap    Capacity of the row stack, in rows
\    +88..+168        The reveal under way: viewer, radius, quadrant,
\                     rows on the stack, and the row being scanned
\
\  Public API:
\    FOG-NEW         ( w h -- fog )
\    FOG-FREE        ( fog -- )
\    FOG-BLOCK-MAP!  ( fog cmap -- )
\    FOG-BLOCK-XT!   ( fog xt ctx -- )
\    FOG-REVEAL      ( fog cx cy radius -- )
\    FOG-HIDE-ALL    ( fog -- )
\    FOG-RESET       ( fog -- )
\    FOG-STATE       ( fog x y -- 0|1|2 )
\    FOG-W           ( fog -- w )
\    FOG-H           ( fog -- h )
\    FOG-DATA        ( fog -- addr )
\
\  Prefix: FOG- (public), _FOG- (internal)
\  Provider: akashic-game-2d-fog
\  Dependencies: collide.f

PROVIDED akashic-game-2d-fog

REQUIRE collide.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0 CONSTANT FOG-UNSEEN
1 CONSTANT FOG-REMEMBERED
2 CONSTANT FOG-VISIBLE

( kind: fog-block xt( x y ctx -- flag ) )

0   CONSTANT _FOG-O-W
8   CONSTANT _FOG-O-H
16  CONSTANT _FOG-O-DATA
24  CONSTANT _FOG-O-KIND
32  CONSTANT _FOG-O-SRC
32  CONSTANT _FOG-O-XT  ( holds: fog-block )
40  CONSTANT _FOG-O-CTX
48  CONSTANT _FOG-O-LIT
56  CONSTANT _FOG-O-LITN
64  CONSTANT _FOG-O-LITCAP
72  CONSTANT _FOG-O-ROWS
80  CONSTANT _FOG-O-ROWSCAP
88  CONSTANT _FOG-O-OX
96  CONSTANT _FOG-O-OY
104 CONSTANT _FOG-O-R
112 CONSTANT _FOG-O-Q
120 CONSTANT _FOG-O-ROWSN
128 CONSTANT _FOG-O-DEPTH
136 CONSTANT _FOG-O-SN
144 CONSTANT _FOG-O-SD
152 CONSTANT _FOG-O-EN
160 CONSTANT _FOG-O-ED
168 CONSTANT _FOG-O-PREV
176 CONSTANT _FOG-DESC-SZ

\ What blocks sight
0 CONSTANT _FOG-K-OPEN
1 CONSTANT _FOG-K-MAP
2 CONSTANT _FOG-K-XT

\ The previous tile of a row: none yet, blocking, or open
0 CONSTANT _FOG-P-NONE
1 CONSTANT _FOG-P-WALL
2 CONSTANT _FOG-P-FLOOR

\ A row on the stack: depth, then start and end slopes as fractions
40 CONSTANT _FOG-ROW-SZ

\ =====================================================================
\  §2 — Constructor / Destructor / Sources
\ =====================================================================

: FOG-NEW  ( w h -- fog )
    2DUP 1 < SWAP 1 < OR ABORT" FOG-NEW: empty map"
    _FOG-DESC-SZ ALLOCATE
    0<> ABORT" FOG-NEW: desc alloc"
    DUP _FOG-DESC-SZ 0 FILL
    TUCK _FOG-O-H + !  TUCK _FOG-O-W + !          ( fog )
    DUP DUP _FOG-O-W + @ SWAP _FOG-O-H + @ *       ( fog n )
    DUP ALLOCATE
    0<> ABORT" FOG-NEW: data alloc"                ( fog n data )
    TUCK SWAP 0 FILL
    OVER _FOG-O-DATA + ! ;

: FOG-FREE  ( fog -- )
    DUP _FOG-O-DATA + @ FREE
    DUP _FOG-O-LIT + @ FREE
    DUP _FOG-O-ROWS + @ FREE
    FREE ;

: FOG-W  ( fog -- w )  _FOG-O-W + @ ;
: FOG-H  ( fog -- h )  _FOG-O-H + @ ;

\ FOG-DATA ( fog -- addr )
\   The tiles' states, w x h bytes row by row: tile (x,y) at addr + y x w
\   + x.  A game that writes them, as a load restores what a player had
\   seen, writes only FOG-UNSEEN and FOG-REMEMBERED: visible tiles come
\   from FOG-REVEAL, which keeps the list FOG-HIDE-ALL reads.
: FOG-DATA  ( fog -- addr )  _FOG-O-DATA + @ ;

\ FOG-BLOCK-MAP! ( fog cmap -- )
\   Tiles whose collision value is nonzero block sight.  The map must
\   have the fog's size; the fog reads its bytes for as long as it is
\   the source.
: FOG-BLOCK-MAP!  ( fog cmap -- )
    OVER _FOG-O-W + @ OVER CMAP-W <>
    2 PICK _FOG-O-H + @ 2 PICK CMAP-H <> OR
    ABORT" FOG-BLOCK-MAP!: map size differs"
    CMAP-DATA OVER _FOG-O-SRC + !
    _FOG-K-MAP SWAP _FOG-O-KIND + ! ;

\ FOG-BLOCK-XT! ( fog xt ctx -- )
\   xt ( x y ctx -- flag ) answers whether in-bounds tile (x,y) blocks
\   sight, given the context cell ctx.
: FOG-BLOCK-XT!  ( fog xt ctx -- )
    2 PICK _FOG-O-CTX + !
    OVER _FOG-O-XT + !
    _FOG-K-XT SWAP _FOG-O-KIND + ! ;

\ =====================================================================
\  §3 — Tiles
\ =====================================================================

: _FOG-IN?  ( fog x y -- flag )
    ROT >R  R@ _FOG-O-H + @ U<  SWAP R> _FOG-O-W + @ U<  AND ;

: _FOG-INDEX  ( fog x y -- i )
    ROT _FOG-O-W + @ * + ;

\ Whether tile (x,y) blocks sight; beyond the map's edge every tile does.
: _FOG-OPAQUE?  ( fog x y -- flag )
    2 PICK 2 PICK 2 PICK _FOG-IN? 0= IF 2DROP DROP TRUE EXIT THEN
    2 PICK _FOG-O-KIND + @
    CASE
        _FOG-K-MAP OF
            2 PICK -ROT _FOG-INDEX SWAP _FOG-O-SRC + @ + C@ 0<>
        ENDOF
        _FOG-K-XT OF
            2 PICK _FOG-O-CTX + @ 3 PICK _FOG-O-XT + @ EXECUTE NIP
        ENDOF
        >R 2DROP DROP FALSE R>
    ENDCASE ;

: FOG-STATE  ( fog x y -- 0|1|2 )
    2 PICK 2 PICK 2 PICK _FOG-IN? 0= IF 2DROP DROP FOG-UNSEEN EXIT THEN
    2 PICK -ROT _FOG-INDEX SWAP _FOG-O-DATA + @ + C@ ;

\ =====================================================================
\  §4 — The lit list, hiding and resetting
\ =====================================================================

\ Grow the lit list by doubling.  A tile joins it once between hides,
\ so it never needs more entries than the map has tiles.
: _FOG-LIT-GROW  ( fog -- )
    DUP _FOG-O-LITCAP + @ 2* 64 MAX
    OVER DUP _FOG-O-W + @ SWAP _FOG-O-H + @ * MIN    ( fog cap )
    DUP CELLS ALLOCATE
    0<> ABORT" FOG: lit list alloc"                  ( fog cap new )
    2 PICK _FOG-O-LIT + @ OVER 4 PICK _FOG-O-LITN + @ CELLS CMOVE
    2 PICK _FOG-O-LIT + @ FREE
    2 PICK _FOG-O-LIT + !
    SWAP _FOG-O-LITCAP + ! ;

: _FOG-LIT-PUSH  ( fog i -- )
    OVER _FOG-O-LITN + @ 2 PICK _FOG-O-LITCAP + @ >= IF
        OVER _FOG-LIT-GROW
    THEN
    OVER _FOG-O-LIT + @ 2 PICK _FOG-O-LITN + @ CELLS + !
    _FOG-O-LITN + 1 SWAP +! ;

\ Light tile (x,y) if it lies on the map.
: _FOG-LIGHT  ( fog x y -- )
    2 PICK 2 PICK 2 PICK _FOG-IN? 0= IF 2DROP DROP EXIT THEN
    2 PICK -ROT _FOG-INDEX                         ( fog i )
    OVER _FOG-O-DATA + @ OVER +                    ( fog i addr )
    DUP C@ FOG-VISIBLE = IF 2DROP DROP EXIT THEN
    FOG-VISIBLE SWAP C!
    _FOG-LIT-PUSH ;

\ FOG-HIDE-ALL ( fog -- )
\   Demote every visible tile to remembered: the tiles lit since the
\   last hide, which the lit list holds.
: FOG-HIDE-ALL  ( fog -- )
    DUP _FOG-O-DATA + @ OVER _FOG-O-LIT + @        ( fog data lit )
    2 PICK _FOG-O-LITN + @ 0 ?DO
        DUP I CELLS + @ 2 PICK + FOG-REMEMBERED SWAP C!
    LOOP
    2DROP 0 SWAP _FOG-O-LITN + ! ;

\ FOG-RESET ( fog -- )
\   Forget everything: every tile unseen.
: FOG-RESET  ( fog -- )
    DUP _FOG-O-DATA + @ OVER DUP _FOG-O-W + @ SWAP _FOG-O-H + @ * 0 FILL
    0 SWAP _FOG-O-LITN + ! ;

\ =====================================================================
\  §5 — Shadowcasting: FOG-REVEAL
\ =====================================================================
\
\  In each quadrant a row at depth d holds the tiles (d, col) whose
\  columns lie between d × start and d × end, the slopes kept as
\  fractions sn/sd and en/ed with positive denominators.  A tile is
\  lit when it blocks sight or its centre lies within the slopes, and
\  it lies within the radius.  A wall after an open tile ends the open
\  run, which continues as a row one deeper, its end slope the wall's
\  near edge; an open tile after a wall starts the next run at its own
\  near edge.

\ floor(n/d) for d > 0, since / truncates toward zero
: _FOG-FLOOR/  ( n d -- q )
    2DUP / DUP >R * - 0< IF R> 1- ELSE R> THEN ;

\ The offset of column col of the current row from the viewer.
: _FOG-DELTA  ( col depth q -- dx dy )
    CASE
        0 OF NEGATE ENDOF
        1 OF SWAP ENDOF
        2 OF ENDOF
        3 OF NEGATE SWAP ENDOF
    ENDCASE ;

: _FOG-TILE  ( fog col -- x y )
    OVER _FOG-O-DEPTH + @ 2 PICK _FOG-O-Q + @ _FOG-DELTA   ( fog dx dy )
    ROT DUP _FOG-O-OY + @ ROT + SWAP _FOG-O-OX + @ ROT + SWAP ;

\ The current row's first column: depth × start, ties rounded up.
: _FOG-MIN-COL  ( fog -- col )
    DUP _FOG-O-DEPTH + @ OVER _FOG-O-SN + @ * 2* OVER _FOG-O-SD + @ +
    SWAP _FOG-O-SD + @ 2* _FOG-FLOOR/ ;

\ The current row's last column: depth × end, ties rounded down.
: _FOG-MAX-COL  ( fog -- col )
    DUP _FOG-O-ED + @ OVER _FOG-O-DEPTH + @ 2 PICK _FOG-O-EN + @ * 2* -
    SWAP _FOG-O-ED + @ 2* _FOG-FLOOR/ NEGATE ;

\ Whether column col's centre lies within the current row's slopes.
: _FOG-SYMMETRIC?  ( fog col -- flag )
    OVER _FOG-O-SD + @ OVER * 2 PICK _FOG-O-DEPTH + @ 3 PICK _FOG-O-SN + @ * >=
    >R  OVER _FOG-O-ED + @ *
    SWAP DUP _FOG-O-DEPTH + @ SWAP _FOG-O-EN + @ * <=  R> AND ;

\ Whether column col of the current row lies within the radius.
: _FOG-NEAR?  ( fog col -- flag )
    DUP * OVER _FOG-O-DEPTH + @ DUP * +  SWAP _FOG-O-R + @ DUP * <= ;

: _FOG-PUSH  ( fog depth sn sd en ed -- )
    5 PICK DUP _FOG-O-ROWSN + @ SWAP _FOG-O-ROWSCAP + @ >=
    ABORT" FOG: row stack full"
    5 PICK DUP _FOG-O-ROWS + @ SWAP _FOG-O-ROWSN + @ _FOG-ROW-SZ * +
    >R  R@ 4 CELLS + !  R@ 3 CELLS + !  R@ 2 CELLS + !  R@ CELL+ !  R> !
    _FOG-O-ROWSN + 1 SWAP +! ;

: _FOG-POP  ( fog -- )
    DUP _FOG-O-ROWSN + DUP @ 1- DUP ROT !          ( fog n )
    _FOG-ROW-SZ * OVER _FOG-O-ROWS + @ +           ( fog row )
    2DUP @ SWAP _FOG-O-DEPTH + !
    2DUP CELL+ @ SWAP _FOG-O-SN + !
    2DUP 2 CELLS + @ SWAP _FOG-O-SD + !
    2DUP 3 CELLS + @ SWAP _FOG-O-EN + !
    4 CELLS + @ SWAP _FOG-O-ED + ! ;

\ An open run ended at column col: its row one deeper ends at col's
\ near edge.
: _FOG-PUSH-UNTIL  ( fog col -- )
    OVER _FOG-O-DEPTH + @ 2 PICK _FOG-O-R + @ >= IF 2DROP EXIT THEN
    >R
    DUP _FOG-O-DEPTH + @ 1+  OVER _FOG-O-SN + @  2 PICK _FOG-O-SD + @
    R> 2* 1-  4 PICK _FOG-O-DEPTH + @ 2*
    _FOG-PUSH ;

\ The row ended on an open tile: its run continues one row deeper.
: _FOG-PUSH-NEXT  ( fog -- )
    DUP _FOG-O-DEPTH + @ OVER _FOG-O-R + @ >= IF DROP EXIT THEN
    DUP _FOG-O-DEPTH + @ 1+  OVER _FOG-O-SN + @  2 PICK _FOG-O-SD + @
    3 PICK _FOG-O-EN + @  4 PICK _FOG-O-ED + @
    _FOG-PUSH ;

\ An open tile after a wall: the run starts at col's near edge.
: _FOG-START!  ( fog col -- )
    2* 1- OVER _FOG-O-SN + !
    DUP _FOG-O-DEPTH + @ 2* SWAP _FOG-O-SD + ! ;

: _FOG-STEP  ( fog col -- )
    2DUP _FOG-TILE                                 ( fog col x y )
    3 PICK 2 PICK 2 PICK _FOG-OPAQUE?              ( fog col x y wall )
    DUP IF TRUE ELSE 4 PICK 4 PICK _FOG-SYMMETRIC? THEN
    IF 4 PICK 4 PICK _FOG-NEAR? IF 4 PICK 3 PICK 3 PICK _FOG-LIGHT THEN THEN
    NIP NIP                                        ( fog col wall )
    IF
        OVER _FOG-O-PREV + @ _FOG-P-FLOOR = IF 2DUP _FOG-PUSH-UNTIL THEN
        _FOG-P-WALL
    ELSE
        OVER _FOG-O-PREV + @ _FOG-P-WALL = IF 2DUP _FOG-START! THEN
        _FOG-P-FLOOR
    THEN
    NIP SWAP _FOG-O-PREV + ! ;

: _FOG-SCAN-ROW  ( fog -- )
    _FOG-P-NONE OVER _FOG-O-PREV + !
    DUP _FOG-MAX-COL 1+ OVER _FOG-MIN-COL         ( fog end start )
    2DUP > IF ?DO DUP I _FOG-STEP LOOP ELSE 2DROP THEN
    DUP _FOG-O-PREV + @ _FOG-P-FLOOR = IF _FOG-PUSH-NEXT ELSE DROP THEN ;

: _FOG-QUADRANT  ( fog q -- )
    OVER _FOG-O-Q + !
    DUP 1 -1 1 1 1 _FOG-PUSH
    BEGIN DUP _FOG-O-ROWSN + @ WHILE
        DUP _FOG-POP DUP _FOG-SCAN-ROW
    REPEAT
    DROP ;

\ The row stack a radius needs: a row at depth d leaves at most d of
\ its open runs waiting while the deepest one is scanned.
: _FOG-ROWS-NEED  ( radius -- rows )
    DUP 1+ SWAP 2 + * 2/ 1+ ;

: _FOG-ROWS-FIT  ( fog -- )
    DUP _FOG-O-R + @ _FOG-ROWS-NEED                ( fog need )
    OVER _FOG-O-ROWSCAP + @ OVER >= IF 2DROP EXIT THEN
    OVER _FOG-O-ROWS + @ FREE
    0 2 PICK _FOG-O-ROWS + !  0 2 PICK _FOG-O-ROWSCAP + !
    DUP _FOG-ROW-SZ * ALLOCATE
    0<> ABORT" FOG: row stack alloc"               ( fog need rows )
    2 PICK _FOG-O-ROWS + !
    SWAP _FOG-O-ROWSCAP + ! ;

\ FOG-REVEAL ( fog cx cy radius -- )
\   Light what a viewer at (cx,cy) sees within radius tiles.  A viewer
\   off the map sees nothing.
: FOG-REVEAL  ( fog cx cy radius -- )
    0 MAX 3 PICK _FOG-O-R + !
    2 PICK 2 PICK 2 PICK _FOG-IN? 0= IF 2DROP DROP EXIT THEN
    2 PICK _FOG-O-OY + !  OVER _FOG-O-OX + !       ( fog )
    0 OVER _FOG-O-ROWSN + !
    DUP _FOG-ROWS-FIT
    DUP DUP _FOG-O-OX + @ OVER _FOG-O-OY + @ _FOG-LIGHT
    DUP _FOG-O-R + @ 0= IF DROP EXIT THEN
    4 0 DO DUP I _FOG-QUADRANT LOOP
    DROP ;

\ =====================================================================
\  §6 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _fog-guard

' FOG-NEW        CONSTANT _fog-new-xt
' FOG-FREE       CONSTANT _fog-free-xt
' FOG-BLOCK-MAP! CONSTANT _fog-block-map-xt
' FOG-BLOCK-XT!  CONSTANT _fog-block-xt-xt
' FOG-REVEAL     CONSTANT _fog-reveal-xt
' FOG-HIDE-ALL   CONSTANT _fog-hide-xt
' FOG-RESET      CONSTANT _fog-reset-xt
' FOG-STATE      CONSTANT _fog-state-xt

: FOG-NEW        _fog-new-xt       _fog-guard WITH-GUARD ;
: FOG-FREE       _fog-free-xt      _fog-guard WITH-GUARD ;
: FOG-BLOCK-MAP! _fog-block-map-xt _fog-guard WITH-GUARD ;
: FOG-BLOCK-XT!  _fog-block-xt-xt  _fog-guard WITH-GUARD ;
: FOG-REVEAL     _fog-reveal-xt    _fog-guard WITH-GUARD ;
: FOG-HIDE-ALL   _fog-hide-xt      _fog-guard WITH-GUARD ;
: FOG-RESET      _fog-reset-xt     _fog-guard WITH-GUARD ;
: FOG-STATE      _fog-state-xt     _fog-guard WITH-GUARD ;
[THEN] [THEN]
