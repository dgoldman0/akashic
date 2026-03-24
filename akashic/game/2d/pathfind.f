\ =====================================================================
\  akashic/game/2d/pathfind.f — Grid-Based A* Pathfinding
\ =====================================================================
\
\  A* pathfinding over a collision map.  Returns a path as a
\  Forth-allocated array of (x,y) cell pairs.  The path runs from
\  start to goal inclusive.
\
\  Public API:
\    ASTAR-FIND       ( cmap x0 y0 x1 y1 -- path count | 0 0 )
\    ASTAR-FREE       ( path -- )
\    ASTAR-HEURISTIC! ( xt -- )    custom: ( x0 y0 x1 y1 -- h )
\    ASTAR-DIAGONAL!  ( flag -- )  enable 8-connected search
\    ASTAR-BUDGET!    ( n -- )     max nodes to expand
\
\  Path format:
\    Array of cell pairs: path[i*2] = x, path[i*2+1] = y.
\    Free with ASTAR-FREE when done.
\
\  Prefix: ASTAR- (public), _AS- (internal)
\  Provider: akashic-game-2d-pathfind
\  Dependencies: collide.f

PROVIDED akashic-game-2d-pathfind

REQUIRE collide.f

\ =====================================================================
\  §1 — Configuration
\ =====================================================================

VARIABLE _AS-H-XT          \ heuristic XT
VARIABLE _AS-DIAG          \ 0 = 4-connected, non-zero = 8-connected
VARIABLE _AS-BUDGET-VAL    \ max nodes to expand
512 _AS-BUDGET-VAL !
0   _AS-DIAG !

: ASTAR-DIAGONAL!  ( flag -- )  _AS-DIAG ! ;
: ASTAR-BUDGET!    ( n -- )     _AS-BUDGET-VAL ! ;

\ Default heuristic: Manhattan distance
: _AS-MANHATTAN  ( x0 y0 x1 y1 -- h )
    ROT - ABS -ROT - ABS + ;

VARIABLE _AS-MAN-XT
' _AS-MANHATTAN _AS-MAN-XT !

: ASTAR-HEURISTIC!  ( xt -- )  _AS-H-XT ! ;

\ Initialise default heuristic
_AS-MAN-XT @ _AS-H-XT !

\ =====================================================================
\  §2 — Neighbour Offsets
\ =====================================================================

CREATE _AS-DX  -1 ,  1 ,  0 ,  0 , -1 , -1 ,  1 ,  1 ,
CREATE _AS-DY   0 ,  0 , -1 ,  1 , -1 ,  1 , -1 ,  1 ,

: _AS-NCOUNT  ( -- n )  _AS-DIAG @ IF 8 ELSE 4 THEN ;

\ =====================================================================
\  §3 — Workspace Layout
\ =====================================================================
\
\  All A* state is allocated in a single workspace block.
\  Parallel arrays are indexed by (row * width + col).
\
\  Header (72 bytes, 9 cells):
\    +0   cmap       Collision map pointer
\    +8   w          Width  (cached)
\   +16   h          Height (cached)
\   +24   area       w * h  (cached)
\   +32   gx         Goal x
\   +40   gy         Goal y
\   +48   visited    Pointer to byte array  (area bytes)
\   +56   gscore     Pointer to cell array  (area * 8 bytes)
\   +64   parent     Pointer to cell array  (area * 8 bytes)

 0 CONSTANT _AS-O-CMAP
 8 CONSTANT _AS-O-W
16 CONSTANT _AS-O-H
24 CONSTANT _AS-O-AREA
32 CONSTANT _AS-O-GX
40 CONSTANT _AS-O-GY
48 CONSTANT _AS-O-VISITED
56 CONSTANT _AS-O-GSCORE
64 CONSTANT _AS-O-PARENT
72 CONSTANT _AS-HDR-SZ

\ Open-set entry: 3 cells (x, y, f-score) = 24 bytes
 0 CONSTANT _AS-OE-X
 8 CONSTANT _AS-OE-Y
16 CONSTANT _AS-OE-F
24 CONSTANT _AS-OE-SZ

\ Sentinel for "no parent"
-1 CONSTANT _AS-NO-PARENT

\ =====================================================================
\  §4 — Workspace Allocation
\ =====================================================================

VARIABLE _AS-WS      \ current workspace pointer
VARIABLE _AS-OPEN    \ open-set array pointer
VARIABLE _AS-OCNT    \ open-set count
VARIABLE _AS-OMAX    \ open-set max entries

\ Temporaries for _AS-ALLOC arguments
VARIABLE _AS-A-CMAP  VARIABLE _AS-A-GX  VARIABLE _AS-A-GY

: _AS-IDX  ( x y -- idx )
    _AS-WS @ _AS-O-W + @ * + ;

: _AS-ALLOC  ( cmap gx gy -- ok-flag )
    _AS-A-GY !  _AS-A-GX !  _AS-A-CMAP !

    \ Allocate header
    _AS-HDR-SZ ALLOCATE 0<> IF DROP 0 EXIT THEN
    _AS-WS !
    _AS-A-GY @ _AS-WS @ _AS-O-GY + !
    _AS-A-GX @ _AS-WS @ _AS-O-GX + !
    _AS-A-CMAP @ DUP _AS-WS @ _AS-O-CMAP + !
    DUP CMAP-W _AS-WS @ _AS-O-W + !
    CMAP-H _AS-WS @ _AS-O-H + !
    _AS-WS @ _AS-O-W + @ _AS-WS @ _AS-O-H + @ *
    _AS-WS @ _AS-O-AREA + !

    \ Allocate visited (byte array, zero-filled)
    _AS-WS @ _AS-O-AREA + @ ALLOCATE 0<> IF
        DROP _AS-WS @ FREE 0 EXIT
    THEN
    DUP _AS-WS @ _AS-O-VISITED + !
    _AS-WS @ _AS-O-AREA + @ 0 FILL

    \ Allocate g-score (cell array, filled with large value)
    _AS-WS @ _AS-O-AREA + @ CELLS ALLOCATE 0<> IF
        DROP _AS-WS @ _AS-O-VISITED + @ FREE
        _AS-WS @ FREE 0 EXIT
    THEN
    DUP _AS-WS @ _AS-O-GSCORE + !
    _AS-WS @ _AS-O-AREA + @ 0 ?DO
        0x7FFFFFFF OVER I CELLS + !
    LOOP DROP

    \ Allocate parent (cell array, filled with NO_PARENT)
    _AS-WS @ _AS-O-AREA + @ CELLS ALLOCATE 0<> IF
        DROP _AS-WS @ _AS-O-GSCORE + @ FREE
        _AS-WS @ _AS-O-VISITED + @ FREE
        _AS-WS @ FREE 0 EXIT
    THEN
    DUP _AS-WS @ _AS-O-PARENT + !
    _AS-WS @ _AS-O-AREA + @ 0 ?DO
        _AS-NO-PARENT OVER I CELLS + !
    LOOP DROP

    \ Allocate open set
    _AS-BUDGET-VAL @ _AS-OMAX !
    _AS-OMAX @ _AS-OE-SZ * ALLOCATE 0<> IF
        DROP _AS-WS @ _AS-O-PARENT + @ FREE
        _AS-WS @ _AS-O-GSCORE + @ FREE
        _AS-WS @ _AS-O-VISITED + @ FREE
        _AS-WS @ FREE 0 EXIT
    THEN
    _AS-OPEN !
    0 _AS-OCNT !

    -1 ;  \ success

: _AS-FREE-WS  ( -- )
    _AS-OPEN @ FREE
    _AS-WS @ _AS-O-PARENT + @ FREE
    _AS-WS @ _AS-O-GSCORE + @ FREE
    _AS-WS @ _AS-O-VISITED + @ FREE
    _AS-WS @ FREE ;

\ =====================================================================
\  §5 — Open-Set Operations
\ =====================================================================

: _AS-OPEN-ADD  ( x y f -- )
    _AS-OCNT @ _AS-OMAX @ >= IF DROP 2DROP EXIT THEN
    _AS-OPEN @ _AS-OCNT @ _AS-OE-SZ * +   ( x y f entry )
    >R
    R@ _AS-OE-F + !
    R@ _AS-OE-Y + !
    R> _AS-OE-X + !
    _AS-OCNT @ 1+ _AS-OCNT ! ;

VARIABLE _AS-BEST-I
VARIABLE _AS-BEST-F
VARIABLE _AS-POP-X  VARIABLE _AS-POP-Y

: _AS-OPEN-POP-MIN  ( -- x y )
    \ Find entry with lowest f
    0x7FFFFFFF _AS-BEST-F !
    0 _AS-BEST-I !
    _AS-OCNT @ 0 ?DO
        _AS-OPEN @ I _AS-OE-SZ * + _AS-OE-F + @
        _AS-BEST-F @ < IF
            I _AS-BEST-I !
            _AS-OPEN @ I _AS-OE-SZ * + _AS-OE-F + @ _AS-BEST-F !
        THEN
    LOOP
    \ Read and save result
    _AS-OPEN @ _AS-BEST-I @ _AS-OE-SZ * +
    DUP _AS-OE-X + @ _AS-POP-X !
    _AS-OE-Y + @ _AS-POP-Y !
    \ Remove: copy last entry over removed slot, decrement count
    _AS-OCNT @ 1- _AS-OCNT !
    _AS-OCNT @ _AS-BEST-I @ <> IF
        \ src = last entry, dst = removed slot
        _AS-OPEN @ _AS-OCNT @ _AS-OE-SZ * +        ( src )
        _AS-OPEN @ _AS-BEST-I @ _AS-OE-SZ * +      ( src dst )
        OVER @ OVER !                                \ copy X
        OVER 8 + @ OVER 8 + !                       \ copy Y
        SWAP 16 + @ SWAP 16 + !                      \ copy F
    THEN
    _AS-POP-X @ _AS-POP-Y @ ;

\ =====================================================================
\  §6 — Core A* Helpers
\ =====================================================================

: _AS-HEURISTIC  ( x y -- h )
    _AS-WS @ _AS-O-GX + @ _AS-WS @ _AS-O-GY + @
    _AS-H-XT @ EXECUTE ;

: _AS-GSCORE@  ( x y -- g )
    _AS-IDX CELLS _AS-WS @ _AS-O-GSCORE + @ + @ ;

: _AS-GSCORE!  ( g x y -- )
    _AS-IDX CELLS _AS-WS @ _AS-O-GSCORE + @ + ! ;

: _AS-PARENT!  ( parent-idx x y -- )
    _AS-IDX CELLS _AS-WS @ _AS-O-PARENT + @ + ! ;

: _AS-PARENT@  ( x y -- parent-idx )
    _AS-IDX CELLS _AS-WS @ _AS-O-PARENT + @ + @ ;

: _AS-VISITED?  ( x y -- flag )
    _AS-IDX _AS-WS @ _AS-O-VISITED + @ + C@ 0<> ;

: _AS-VISIT!  ( x y -- )
    _AS-IDX _AS-WS @ _AS-O-VISITED + @ + 1 SWAP C! ;

: _AS-IN-BOUNDS?  ( x y -- flag )
    DUP 0 >= SWAP _AS-WS @ _AS-O-H + @ < AND
    SWAP DUP 0 >= SWAP _AS-WS @ _AS-O-W + @ < AND
    AND ;

: _AS-PASSABLE?  ( x y -- flag )
    _AS-WS @ _AS-O-CMAP + @ -ROT CMAP-SOLID? 0= ;

\ =====================================================================
\  §7 — Neighbour Expansion
\ =====================================================================

VARIABLE _AS-CX   VARIABLE _AS-CY
VARIABLE _AS-NX   VARIABLE _AS-NY
VARIABLE _AS-NG

: _AS-PROCESS-NEIGHBOUR  ( cx cy nx ny -- )
    2DUP _AS-IN-BOUNDS? 0= IF 2DROP 2DROP EXIT THEN
    2DUP _AS-VISITED?      IF 2DROP 2DROP EXIT THEN
    2DUP _AS-PASSABLE? 0=  IF 2DROP 2DROP EXIT THEN
    _AS-NY !  _AS-NX !
    _AS-CY !  _AS-CX !
    \ tentative g = g(current) + 1
    _AS-CX @ _AS-CY @ _AS-GSCORE@ 1+ _AS-NG !
    _AS-NG @ _AS-NX @ _AS-NY @ _AS-GSCORE@ < IF
        _AS-NG @ _AS-NX @ _AS-NY @ _AS-GSCORE!
        _AS-CX @ _AS-CY @ _AS-IDX
        _AS-NX @ _AS-NY @ _AS-PARENT!
        _AS-NX @ _AS-NY @
        2DUP _AS-HEURISTIC _AS-NG @ +
        _AS-OPEN-ADD
    THEN ;

: _AS-EXPAND  ( cx cy -- )
    _AS-NCOUNT 0 ?DO
        2DUP
        OVER _AS-DX I CELLS + @ +
        OVER _AS-DY I CELLS + @ +
        _AS-PROCESS-NEIGHBOUR
    LOOP
    2DROP ;

\ =====================================================================
\  §8 — Path Reconstruction
\ =====================================================================

VARIABLE _AS-PX    VARIABLE _AS-PY
VARIABLE _AS-PLEN  VARIABLE _AS-PPATH

: _AS-DECODE-PARENT  ( idx -- x y )
    DUP _AS-WS @ _AS-O-W + @ MOD
    SWAP _AS-WS @ _AS-O-W + @ / ;

: _AS-COUNT-PATH  ( gx gy -- count )
    _AS-PY !  _AS-PX !
    1
    BEGIN
        _AS-PX @ _AS-PY @ _AS-PARENT@
        _AS-NO-PARENT <> WHILE
        1+
        _AS-PX @ _AS-PY @ _AS-PARENT@
        _AS-DECODE-PARENT _AS-PY ! _AS-PX !
    REPEAT ;

: _AS-BUILD-PATH  ( gx gy count -- path count | 0 0 )
    DUP _AS-PLEN !
    DUP 2* CELLS ALLOCATE 0<> IF DROP 2DROP 0 0 EXIT THEN
    _AS-PPATH !
    DROP                \ discard count (saved in _AS-PLEN)
    _AS-PY !  _AS-PX !

    \ Fill backwards: idx = count-1 down to 0
    _AS-PLEN @ 1-
    BEGIN
        DUP 0 >= WHILE
        _AS-PX @  OVER 2* CELLS _AS-PPATH @ +  !
        _AS-PY @  OVER 2* 1+ CELLS _AS-PPATH @ +  !
        1-
        \ Walk to parent
        _AS-PX @ _AS-PY @ _AS-PARENT@
        DUP _AS-NO-PARENT = IF
            DROP DROP
            _AS-PPATH @ _AS-PLEN @
            EXIT
        THEN
        _AS-DECODE-PARENT _AS-PY ! _AS-PX !
    REPEAT
    DROP
    _AS-PPATH @ _AS-PLEN @ ;

\ =====================================================================
\  §9 — Public API
\ =====================================================================

VARIABLE _AS-FIND-SX  VARIABLE _AS-FIND-SY
VARIABLE _AS-REM

: ASTAR-FIND  ( cmap x0 y0 x1 y1 -- path count | 0 0 )
    >R >R                              ( cmap x0 y0  R: y1 x1 )
    _AS-FIND-SY !  _AS-FIND-SX !      ( cmap  R: y1 x1 )
    R> R>                              ( cmap x1 y1 )
    _AS-ALLOC 0= IF 0 0 EXIT THEN

    \ Seed start: g=0, f=h
    0 _AS-FIND-SX @ _AS-FIND-SY @ _AS-GSCORE!
    _AS-FIND-SX @ _AS-FIND-SY @ _AS-HEURISTIC
    _AS-FIND-SX @ _AS-FIND-SY @ ROT _AS-OPEN-ADD

    \ Main loop
    _AS-BUDGET-VAL @ _AS-REM !
    BEGIN
        _AS-OCNT @ 0> _AS-REM @ 0> AND
    WHILE
        _AS-OPEN-POP-MIN               ( cx cy )
        \ Goal check
        \ Goal check
        2DUP
        _AS-WS @ _AS-O-GY + @ =
        SWAP _AS-WS @ _AS-O-GX + @ =
        AND IF
            \ Found — reconstruct path
            2DUP _AS-COUNT-PATH
            _AS-BUILD-PATH
            _AS-FREE-WS
            EXIT
        THEN
        2DUP _AS-VISITED? IF
            2DROP
        ELSE
            2DUP _AS-VISIT!
            _AS-EXPAND
        THEN
        _AS-REM @ 1- _AS-REM !
    REPEAT

    \ No path found
    _AS-FREE-WS
    0 0 ;

: ASTAR-FREE  ( path -- )
    FREE ;

\ =====================================================================
\  §10 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _astar-guard

' ASTAR-FIND       CONSTANT _astar-find-xt
' ASTAR-FREE       CONSTANT _astar-free-xt
' ASTAR-HEURISTIC! CONSTANT _astar-heur-xt
' ASTAR-DIAGONAL!  CONSTANT _astar-diag-xt
' ASTAR-BUDGET!    CONSTANT _astar-budget-xt

: ASTAR-FIND       _astar-find-xt   _astar-guard WITH-GUARD ;
: ASTAR-FREE       _astar-free-xt   _astar-guard WITH-GUARD ;
: ASTAR-HEURISTIC! _astar-heur-xt   _astar-guard WITH-GUARD ;
: ASTAR-DIAGONAL!  _astar-diag-xt   _astar-guard WITH-GUARD ;
: ASTAR-BUDGET!    _astar-budget-xt _astar-guard WITH-GUARD ;
[THEN] [THEN]
