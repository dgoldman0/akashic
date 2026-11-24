\ =====================================================================
\  akashic/game/2d/pathfind.f — Grid-Based A* Pathfinding
\ =====================================================================
\
\  A* search and distance fields over a collision map.  A search is
\  made once for its map with ASTAR-NEW and reused.  Its per-tile
\  arrays carry a generation stamp, so a run starts by advancing the
\  generation, whatever the map's size, and its open set, a binary
\  heap, and its path buffer grow from need and stay; once they have
\  grown, a run allocates nothing.
\
\  Terrain: a table of 256 costs, indexed by a tile's collision value,
\  gives the cost of stepping onto a tile, and a cost of 0 makes the
\  tile impassable.  By default value 0 costs 1 and every other value
\  is impassable.  A straight step costs its tile's cost times the
\  straight weight and a diagonal step times the diagonal weight; a
\  diagonal weight of 0, the default, allows only straight steps.  A
\  diagonal step between two blocked neighbours is refused, and with
\  ASTAR-CORNERS! set, a diagonal step past any blocked neighbour.
\
\  The heuristic is the octile distance, Manhattan without diagonals,
\  times the least passable cost, which never overestimates, so a path
\  found is a cheapest one.  Ties in the open set go to the larger g,
\  which shortens runs across open ground.  ASTAR-RUN answers whether
\  it found a path, proved there is none, or spent its budget of
\  expansions.
\
\  ASTAR-FIELD fills a distance field from several sources in one
\  pass, so any number of creatures chasing the same targets share it:
\  each reads its next step with ASTAR-DOWNHILL.
\
\  Search Descriptor (512 bytes):
\    +0    cmap        Collision map
\    +8    w           Width
\    +16   h           Height
\    +24   tiles       The map's tile bytes
\    +32   nodes       Per-tile records of three cells: a stamp, 2×gen
\                      when seen in run gen and 2×gen+1 when closed; the
\                      cost from the nearest start; the parent tile, -1
\                      for a start
\    +40   seen        2×gen, the stamp of a tile seen in this run
\    +48   (unused)
\    +56   gen         Generation of the latest run
\    +64   open        Open set: entries of a key and a tile index
\    +72   open-n      Entries added to the open set
\    +80   open-cap    Capacity of the open set
\    +88   path        Path buffer: (x y) cell pairs
\    +96   path-n      Tiles in the last path found
\    +104  path-cap    Capacity of the path buffer, in tiles
\    +112  straight    Weight of a straight step
\    +120  diagonal    Weight of a diagonal step, 0 for none
\    +128  corners     Refuse a diagonal step past any blocked neighbour
\    +136  budget      Expansions a run may make, 0 for no limit
\    +144  min-cost    Least passable cost
\    +152  expanded    Expansions the latest run made
\    +160  goal        Goal tile of the run, -1 for a field
\    +168  gx, +176 gy The goal's position
\    +184  cost        Cost of the last path found
\    +192..+216        The tile being expanded: x, y, index, g
\    +224  head        A queue's next entry; 0 for a heap
\    +232  queue       The open set is a queue, not a heap
\    +240  hs, +248 hd Heuristic weights of the run: straight, diagonal
\    +256  costs       256 bytes: the cost of each collision value
\
\  The open set is a binary heap keyed by f, then by the larger g, both
\  packed into one unsigned key.  A field whose steps all cost the same
\  is a breadth-first pass: its open set is a queue, since tiles then
\  leave it in order of distance.

\  Public API:
\    ASTAR-NEW        ( cmap -- search )
\    ASTAR-FREE       ( search -- )
\    ASTAR-STEPS!     ( search straight diagonal -- )
\    ASTAR-CORNERS!   ( search flag -- )
\    ASTAR-BUDGET!    ( search n -- )
\    ASTAR-COST!      ( search value cost -- )
\    ASTAR-RUN        ( search x0 y0 x1 y1 -- status )
\    ASTAR-PATH       ( search -- addr count )
\    ASTAR-PATH-COST  ( search -- cost )
\    ASTAR-EXPANDED   ( search -- n )
\    ASTAR-FIELD      ( sources count search -- status )
\    ASTAR-DIST       ( search x y -- d | -1 )
\    ASTAR-DOWNHILL   ( search x y -- nx ny true | false )
\
\  Statuses: ASTAR-FOUND, ASTAR-NONE (no path exists), ASTAR-SPENT
\  (the budget ran out first).
\
\  Path format:
\    Array of cell pairs: path[i*2] = x, path[i*2+1] = y, from the
\    start to the goal.  The search owns it; the next run reuses it.
\
\  Prefix: ASTAR- (public), _AS- (internal)
\  Provider: akashic-game-2d-pathfind
\  Dependencies: collide.f

PROVIDED akashic-game-2d-pathfind

REQUIRE collide.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0 CONSTANT ASTAR-FOUND
1 CONSTANT ASTAR-NONE
2 CONSTANT ASTAR-SPENT

0   CONSTANT _AS-O-CMAP
8   CONSTANT _AS-O-W
16  CONSTANT _AS-O-H
24  CONSTANT _AS-O-TILES
32  CONSTANT _AS-O-NODES
40  CONSTANT _AS-O-SEEN
56  CONSTANT _AS-O-GEN
64  CONSTANT _AS-O-HEAP
72  CONSTANT _AS-O-HN
80  CONSTANT _AS-O-HCAP
88  CONSTANT _AS-O-PATH
96  CONSTANT _AS-O-PN
104 CONSTANT _AS-O-PCAP
112 CONSTANT _AS-O-STRAIGHT
120 CONSTANT _AS-O-DIAG
128 CONSTANT _AS-O-CORNERS
136 CONSTANT _AS-O-BUDGET
144 CONSTANT _AS-O-MINCOST
152 CONSTANT _AS-O-EXPANDED
160 CONSTANT _AS-O-GOAL
168 CONSTANT _AS-O-GX
176 CONSTANT _AS-O-GY
184 CONSTANT _AS-O-COST
192 CONSTANT _AS-O-CX
200 CONSTANT _AS-O-CY
208 CONSTANT _AS-O-CI
216 CONSTANT _AS-O-CG
224 CONSTANT _AS-O-HEAD
232 CONSTANT _AS-O-QUEUE
240 CONSTANT _AS-O-HS
248 CONSTANT _AS-O-HD
256 CONSTANT _AS-O-COSTS
512 CONSTANT _AS-DESC-SZ

\ An open-set entry: a key and a tile index
16 CONSTANT _AS-HE-SZ

\ A tile's record: stamp, g, parent
24 CONSTANT _AS-NODE-SZ

\ =====================================================================
\  §2 — Tiles
\ =====================================================================

: _AS-W  ( s -- w )  [ _AS-O-W ] LITERAL + @ ;

: _AS-AREA  ( s -- n )  DUP _AS-W SWAP _AS-O-H + @ * ;

: _AS-IN?  ( s x y -- flag )
    ROT >R  R@ [ _AS-O-H ] LITERAL + @ U<  SWAP R> [ _AS-O-W ] LITERAL + @ U<  AND ;

: _AS-INDEX  ( s x y -- i )  ROT [ _AS-O-W ] LITERAL + @ * + ;

: _AS-XY  ( s i -- x y )  SWAP [ _AS-O-W ] LITERAL + @ /MOD ;

\ The index of in-bounds tile (x,y), or -1
: _AS-TILE-AT  ( s x y -- i|-1 )
    2 PICK 2 PICK 2 PICK _AS-IN? IF _AS-INDEX ELSE 2DROP DROP -1 THEN ;

\ The cost of stepping onto tile i, 0 when it is impassable
: _AS-TILE-COST  ( s i -- c )
    OVER [ _AS-O-TILES ] LITERAL + @ + C@ + [ _AS-O-COSTS ] LITERAL + C@ ;

: _AS-NODE  ( s i -- node )  [ _AS-NODE-SZ ] LITERAL * SWAP [ _AS-O-NODES ] LITERAL + @ + ;

\ Tile i's distance when the latest run closed it, else -1
: _AS-CLOSED-G  ( s i -- g|-1 )
    OVER [ _AS-O-SEEN ] LITERAL + @ 1+ -ROT _AS-NODE           ( closed node )
    TUCK @ = IF CELL+ @ ELSE DROP -1 THEN ;

\ =====================================================================
\  §3 — Constructor / Destructor / Configuration
\ =====================================================================

: ASTAR-NEW  ( cmap -- search )
    _AS-DESC-SZ ALLOCATE
    0<> ABORT" ASTAR-NEW: desc alloc"
    DUP _AS-DESC-SZ 0 FILL
    2DUP _AS-O-CMAP + !
    OVER CMAP-W OVER _AS-O-W + !
    OVER CMAP-H OVER _AS-O-H + !
    SWAP CMAP-DATA OVER _AS-O-TILES + !            ( s )
    DUP _AS-AREA _AS-NODE-SZ *                     ( s bytes )
    DUP ALLOCATE 0<> ABORT" ASTAR-NEW: node alloc"
    TUCK SWAP 0 FILL  OVER _AS-O-NODES + !
    1 OVER _AS-O-STRAIGHT + !
    1 OVER _AS-O-MINCOST + !
    1 OVER _AS-O-COSTS + C! ;

: ASTAR-FREE  ( search -- )
    DUP _AS-O-NODES + @ FREE
    DUP _AS-O-HEAP + @ FREE
    DUP _AS-O-PATH + @ FREE
    FREE ;

\ ASTAR-STEPS! ( search straight diagonal -- )
\   Step weights.  A diagonal of 0 allows only straight steps; a smaller
\   nonzero diagonal is raised to the straight weight.  (1 0) is the
\   default, (1 1) makes every step one move, and (5 7) or (10 14)
\   approach distance on the plane.
: ASTAR-STEPS!  ( search straight diagonal -- )
    SWAP 1 MAX SWAP
    DUP IF OVER MAX THEN
    2 PICK _AS-O-DIAG + !  SWAP _AS-O-STRAIGHT + ! ;

\ ASTAR-CORNERS! ( search flag -- )
\   When set, a diagonal step past any blocked neighbour is refused, so
\   paths keep off wall corners.  A step between two blocked neighbours
\   is always refused.
: ASTAR-CORNERS!  ( search flag -- )  SWAP _AS-O-CORNERS + ! ;

\ ASTAR-BUDGET! ( search n -- )  expansions a run may make, 0 for no limit
: ASTAR-BUDGET!  ( search n -- )  0 MAX SWAP _AS-O-BUDGET + ! ;

: _AS-MIN-COST  ( s -- )
    255 256 0 DO OVER _AS-O-COSTS + I + C@ ?DUP IF MIN THEN LOOP
    SWAP _AS-O-MINCOST + ! ;

\ ASTAR-COST! ( search value cost -- )
\   Stepping onto a tile of collision value `value` costs `cost`, from 1
\   to 255; 0 makes such tiles impassable.
: ASTAR-COST!  ( search value cost -- )
    255 AND ROT DUP >R _AS-O-COSTS + ROT 255 AND + C!
    R> _AS-MIN-COST ;

\ =====================================================================
\  §4 — The open set: a heap, or a queue, that doubles when full
\ =====================================================================

\ A key orders by f, then by the larger g; both stay below 2^32.
: _AS-KEY  ( f g -- key )  0xFFFFFFFF SWAP - SWAP 32 LSHIFT OR ;
: _AS-KEY-G  ( key -- g )  0xFFFFFFFF AND 0xFFFFFFFF SWAP - ;

: _AS-GROW  ( s -- )
    DUP _AS-O-HCAP + @ 2* 64 MAX                   ( s cap )
    DUP _AS-HE-SZ * ALLOCATE
    0<> ABORT" ASTAR: open set alloc"              ( s cap new )
    2 PICK _AS-O-HEAP + @ OVER 4 PICK _AS-O-HN + @ _AS-HE-SZ * CMOVE
    2 PICK _AS-O-HEAP + @ FREE
    2 PICK _AS-O-HEAP + !
    SWAP _AS-O-HCAP + ! ;

\ Move entry (key i) up from hole k, shifting larger parents down.
: _AS-UP  ( base key i k -- )
    BEGIN
        DUP IF DUP 1- 2/ 4 LSHIFT 4 PICK + @ 3 PICK U> ELSE FALSE THEN
    WHILE
        DUP 1- 2/                                  ( base key i k p )
        4 PICK OVER 4 LSHIFT +
        5 PICK 3 PICK 4 LSHIFT +                   ( base key i k p pe he )
        OVER @ OVER ! SWAP CELL+ @ SWAP CELL+ !
        NIP
    REPEAT
    4 LSHIFT 3 PICK + TUCK CELL+ ! ! DROP ;

\ Move entry (key i) down from the root of a heap of n entries,
\ shifting the smaller child up while it comes before the entry.
: _AS-DOWN  ( base n key i -- )
    0
    BEGIN                                          ( base n key i k )
        DUP 2* 1+ DUP 5 PICK < IF                  ( base n key i k c )
            DUP 1+ DUP 6 PICK < IF
                6 PICK OVER 4 LSHIFT + @  7 PICK 3 PICK 4 LSHIFT + @
                U< IF NIP ELSE DROP THEN
            ELSE
                DROP
            THEN
            5 PICK OVER 4 LSHIFT + @ 4 PICK U<
        ELSE
            FALSE
        THEN
    WHILE                                          ( base n key i k c )
        5 PICK OVER 4 LSHIFT +
        6 PICK 3 PICK 4 LSHIFT +
        OVER @ OVER ! SWAP CELL+ @ SWAP CELL+ !
        NIP
    REPEAT
    DROP 4 LSHIFT 4 PICK + TUCK CELL+ ! ! 2DROP ;

: _AS-PUSH  ( s key i -- )
    2 PICK DUP [ _AS-O-HN ] LITERAL + @ SWAP [ _AS-O-HCAP ] LITERAL + @ >= IF 2 PICK _AS-GROW THEN
    2 PICK DUP [ _AS-O-HEAP ] LITERAL + @ SWAP [ _AS-O-HN ] LITERAL + DUP @ DUP 1+ ROT !   ( s key i base k )
    4 PICK [ _AS-O-QUEUE ] LITERAL + @ IF
        4 LSHIFT + TUCK CELL+ ! ! DROP EXIT
    THEN
    >R -ROT R> _AS-UP DROP ;

\ Take the first entry: the least key of a heap, or a queue's head.
: _AS-POP  ( s -- key i )
    DUP [ _AS-O-QUEUE ] LITERAL + @ IF
        DUP [ _AS-O-HEAD ] LITERAL + DUP @ DUP 1+ ROT !        ( s k )
        4 LSHIFT SWAP [ _AS-O-HEAP ] LITERAL + @ + DUP @ SWAP CELL+ @ EXIT
    THEN
    DUP [ _AS-O-HEAP ] LITERAL + @ DUP @ SWAP CELL+ @          ( s key i )
    2 PICK [ _AS-O-HN ] LITERAL + DUP @ 1- DUP ROT !           ( s key i n )
    ?DUP IF
        3 PICK [ _AS-O-HEAP ] LITERAL + @ SWAP
        2DUP 4 LSHIFT + DUP @ SWAP CELL+ @
        _AS-DOWN
    THEN
    ROT DROP ;

\ Does the open set hold entries yet to take?
: _AS-WAITING?  ( s -- flag )
    DUP [ _AS-O-HN ] LITERAL + @ SWAP [ _AS-O-HEAD ] LITERAL + @ > ;

\ =====================================================================
\  §5 — Steps and the heuristic
\ =====================================================================

\ Each direction's offset plus one, as bytes: left, right, up, down,
\ then the diagonals.
CREATE _AS-DXT  0 C, 2 C, 1 C, 1 C, 0 C, 2 C, 0 C, 2 C,
CREATE _AS-DYT  1 C, 1 C, 0 C, 2 C, 0 C, 0 C, 2 C, 2 C,

: _AS-DIR  ( d -- dx dy )
    DUP _AS-DXT + C@ 1-  SWAP _AS-DYT + C@ 1- ;

: _AS-OPEN?  ( s x y -- flag )
    2 PICK -ROT _AS-INDEX _AS-TILE-COST 0<> ;

\ May a diagonal step by (dx,dy) leave the current tile?  Its two sides
\ must not both block, and with corners set neither may.
: _AS-CORNER-OK?  ( s dx dy -- flag )
    >R OVER DUP [ _AS-O-CX ] LITERAL + @ ROT + OVER [ _AS-O-CY ] LITERAL + @ _AS-OPEN?
    OVER DUP [ _AS-O-CX ] LITERAL + @ OVER [ _AS-O-CY ] LITERAL + @ R> + _AS-OPEN?
    ROT [ _AS-O-CORNERS ] LITERAL + @ IF AND ELSE OR THEN ;

\ The tile a step in direction d reaches from the current tile, and the
\ step's cost, or -1 0 when the step is not allowed.
: _AS-LEGAL  ( s d -- n step | -1 0 )
    DUP _AS-DIR                                    ( s d dx dy )
    3 PICK [ _AS-O-CX ] LITERAL + @ 2 PICK +  4 PICK [ _AS-O-CY ] LITERAL + @ 2 PICK +
    5 PICK 2 PICK 2 PICK _AS-IN? 0= IF 2DROP 2DROP 2DROP -1 0 EXIT THEN
    5 PICK -ROT _AS-INDEX                          ( s d dx dy n )
    4 PICK OVER _AS-TILE-COST
    ?DUP 0= IF 2DROP 2DROP DROP -1 0 EXIT THEN     ( s d dx dy n c )
    4 PICK 4 < IF
        5 PICK [ _AS-O-STRAIGHT ] LITERAL + @ *
    ELSE
        5 PICK 4 PICK 4 PICK _AS-CORNER-OK? 0= IF 2DROP 2DROP 2DROP -1 0 EXIT THEN
        5 PICK [ _AS-O-DIAG ] LITERAL + @ *
    THEN
    >R >R 2DROP 2DROP R> R> ;

\ The octile distance from (x,y) to the goal, times the least cost:
\ hs per tile of dx+dy, and hd, never above zero, per diagonal.
: _AS-H  ( s x y -- h )
    2 PICK [ _AS-O-GY ] LITERAL + @ - ABS
    SWAP 2 PICK [ _AS-O-GX ] LITERAL + @ - ABS     ( s dy dx )
    2 PICK [ _AS-O-HD ] LITERAL + @ ?DUP IF >R 2DUP MIN R> * ELSE 0 THEN
    >R + OVER [ _AS-O-HS ] LITERAL + @ * R> + NIP ;

\ The heuristic's weights for this run's settings
: _AS-WEIGHTS  ( s -- )
    DUP _AS-O-STRAIGHT + @ OVER _AS-O-MINCOST + @ * OVER _AS-O-HS + !
    DUP _AS-O-DIAG + @ ?DUP IF
        OVER _AS-O-STRAIGHT + @ 2* TUCK MIN SWAP -
        OVER _AS-O-MINCOST + @ *
    ELSE
        0
    THEN
    SWAP _AS-O-HD + ! ;

\ =====================================================================
\  §6 — The search
\ =====================================================================

\ Offer tile n at cost ng, reached from the current tile.
: _AS-RELAX  ( s n ng -- )
    2 PICK 2 PICK _AS-NODE                         ( s n ng node )
    DUP @ 4 PICK [ _AS-O-SEEN ] LITERAL + @                    ( s n ng node stamp seen )
    2DUP 1+ = IF 2DROP 2DROP 2DROP EXIT THEN
    >= IF DUP CELL+ @ 2 PICK <= IF 2DROP 2DROP EXIT THEN THEN
    3 PICK [ _AS-O-SEEN ] LITERAL + @ OVER !
    2DUP CELL+ !
    3 PICK [ _AS-O-CI ] LITERAL + @ SWAP 2 CELLS + !           ( s n ng )
    2 PICK [ _AS-O-GOAL ] LITERAL + @ 0< IF
        DUP
    ELSE
        2 PICK 2 PICK _AS-XY 4 PICK -ROT _AS-H OVER +
    THEN                                           ( s n ng f )
    SWAP _AS-KEY SWAP _AS-PUSH ;

\ Offer tile n, a step of weight w from the current tile.
: _AS-OFFER  ( s n w -- )
    >R OVER [ _AS-O-TILES ] LITERAL + @ OVER + C@ 2 PICK [ _AS-O-COSTS ] LITERAL + + C@
    ?DUP 0= IF R> DROP 2DROP EXIT THEN
    R> * 2 PICK [ _AS-O-CG ] LITERAL + @ + _AS-RELAX ;

: _AS-TRY-DIAGONAL  ( s d -- )
    OVER SWAP _AS-LEGAL                            ( s n step )
    OVER 0< IF 2DROP DROP EXIT THEN
    2 PICK [ _AS-O-CG ] LITERAL + @ + _AS-RELAX ;

\ Offer each tile one legal step from the current tile.  The straight
\ steps test the map's edges directly; the diagonals add the corner rule.
: _AS-EXPAND  ( s -- )
    DUP [ _AS-O-STRAIGHT ] LITERAL + @ >R
    DUP [ _AS-O-CX ] LITERAL + @ IF
        DUP DUP [ _AS-O-CI ] LITERAL + @ 1- R@ _AS-OFFER
    THEN
    DUP [ _AS-O-CX ] LITERAL + @ 1+ OVER [ _AS-O-W ] LITERAL + @ < IF
        DUP DUP [ _AS-O-CI ] LITERAL + @ 1+ R@ _AS-OFFER
    THEN
    DUP [ _AS-O-CY ] LITERAL + @ IF
        DUP DUP [ _AS-O-CI ] LITERAL + @ OVER [ _AS-O-W ] LITERAL + @ - R@ _AS-OFFER
    THEN
    DUP [ _AS-O-CY ] LITERAL + @ 1+ OVER [ _AS-O-H ] LITERAL + @ < IF
        DUP DUP [ _AS-O-CI ] LITERAL + @ OVER [ _AS-O-W ] LITERAL + @ + R@ _AS-OFFER
    THEN
    R> DROP
    DUP [ _AS-O-DIAG ] LITERAL + @ IF 8 4 DO DUP I _AS-TRY-DIAGONAL LOOP THEN
    DROP ;

\ Handle one entry taken from the open set: -1 to go on, or a status.
: _AS-VISIT  ( s key i -- s -1 | s status )
    SWAP _AS-KEY-G SWAP                            ( s g i )
    2 PICK OVER _AS-NODE                           ( s g i node )
    DUP @ 4 PICK [ _AS-O-SEEN ] LITERAL + @ 1+ = IF DROP 2DROP -1 EXIT THEN
    CELL+ @ 2 PICK < IF 2DROP -1 EXIT THEN
    DUP 3 PICK [ _AS-O-GOAL ] LITERAL + @ = IF 2DROP ASTAR-FOUND EXIT THEN
    2 PICK [ _AS-O-BUDGET ] LITERAL + @ ?DUP IF
        3 PICK [ _AS-O-EXPANDED ] LITERAL + @ <= IF 2DROP ASTAR-SPENT EXIT THEN
    THEN
    2 PICK [ _AS-O-SEEN ] LITERAL + @ 1+ 3 PICK 2 PICK _AS-NODE !
    1 3 PICK [ _AS-O-EXPANDED ] LITERAL + +!
    2 PICK [ _AS-O-CI ] LITERAL + !  OVER [ _AS-O-CG ] LITERAL + !         ( s )
    DUP DUP [ _AS-O-CI ] LITERAL + @ _AS-XY 2 PICK [ _AS-O-CY ] LITERAL + ! OVER [ _AS-O-CX ] LITERAL + !
    DUP _AS-EXPAND -1 ;

\ Run until the goal comes out of the open set, the set empties or the
\ budget is spent.
: _AS-SEARCH  ( s -- status )
    BEGIN DUP _AS-WAITING? WHILE
        DUP _AS-POP _AS-VISIT DUP -1 <> IF NIP EXIT THEN DROP
    REPEAT
    DROP ASTAR-NONE ;

\ Do all steps cost the same, so a queue keeps the open set in order of
\ distance?  Every passable cost equal, and diagonals none or straight.
: _AS-UNIFORM?  ( s -- flag )
    DUP _AS-O-DIAG + @ DUP IF OVER _AS-O-STRAIGHT + @ <> ELSE DROP FALSE THEN
    IF DROP FALSE EXIT THEN
    DUP _AS-O-MINCOST + @ SWAP
    TRUE 256 0 DO
        OVER _AS-O-COSTS + I + C@ ?DUP IF 3 PICK <> IF DROP FALSE THEN THEN
    LOOP
    NIP NIP ;

\ A new run: a new generation makes every tile's stamp out of date.  A
\ field with uniform steps keeps its open set as a queue.
: _AS-BEGIN  ( s goal -- )
    OVER _AS-O-GOAL + !
    1 OVER _AS-O-GEN + +!
    DUP _AS-O-GEN + @ 2* OVER _AS-O-SEEN + !
    0 OVER _AS-O-HN + !
    0 OVER _AS-O-HEAD + !
    0 OVER _AS-O-EXPANDED + !
    0 OVER _AS-O-PN + !
    DUP _AS-O-GOAL + @ 0< IF
        DUP _AS-UNIFORM? OVER _AS-O-QUEUE + !
    ELSE
        0 OVER _AS-O-QUEUE + !
    THEN
    _AS-WEIGHTS ;

\ Start the run at tile i, cost 0; a tile seeded already stays.
: _AS-SEED  ( s i -- )
    2DUP _AS-NODE                                  ( s i node )
    DUP @ 3 PICK _AS-O-SEEN + @ >= IF DROP 2DROP EXIT THEN
    2 PICK _AS-O-SEEN + @ OVER !  0 OVER CELL+ !  -1 SWAP 2 CELLS + !
    OVER _AS-O-GOAL + @ 0< IF
        0
    ELSE
        2DUP _AS-XY 3 PICK -ROT _AS-H
    THEN
    0 _AS-KEY SWAP _AS-PUSH ;

\ =====================================================================
\  §7 — Paths
\ =====================================================================

: _AS-PATH-ROOM  ( s n -- )
    OVER _AS-O-PCAP + @ OVER >= IF 2DROP EXIT THEN
    OVER _AS-O-PCAP + @ 2* MAX 16 MAX              ( s cap )
    OVER _AS-O-PATH + @ FREE
    0 2 PICK _AS-O-PATH + !  0 2 PICK _AS-O-PCAP + !
    DUP 2* CELLS ALLOCATE
    0<> ABORT" ASTAR: path alloc"                  ( s cap buf )
    2 PICK _AS-O-PATH + !
    SWAP _AS-O-PCAP + ! ;

\ Write the path from the start to the goal into the path buffer.
: _AS-BUILD-PATH  ( s -- )
    1 OVER _AS-O-GOAL + @                          ( s n i )
    BEGIN 2 PICK OVER _AS-NODE 2 CELLS + @ DUP 0< 0= WHILE NIP SWAP 1+ SWAP REPEAT
    2DROP                                          ( s n )
    2DUP _AS-PATH-ROOM
    DUP 2 PICK _AS-O-PN + !
    OVER _AS-O-GOAL + @ SWAP                       ( s i n )
    BEGIN DUP 0> WHILE
        1-
        2 PICK 2 PICK _AS-XY                       ( s i k x y )
        4 PICK _AS-O-PATH + @ 3 PICK 2* CELLS +
        TUCK CELL+ ! !
        >R 2DUP _AS-NODE 2 CELLS + @ NIP R>
    REPEAT
    2DROP
    DUP _AS-O-GOAL + @ OVER SWAP _AS-NODE CELL+ @ SWAP _AS-O-COST + ! ;

\ =====================================================================
\  §8 — Public runs and queries
\ =====================================================================

\ ASTAR-RUN ( search x0 y0 x1 y1 -- status )
\   Find a cheapest path from (x0,y0) to (x1,y1).  ASTAR-FOUND leaves
\   it in the search's path buffer; ASTAR-NONE proves there is none, as
\   for a goal off the map or impassable; ASTAR-SPENT means the budget
\   ran out first.  The start may stand on any tile.
: ASTAR-RUN  ( search x0 y0 x1 y1 -- status )
    4 PICK _AS-O-GY + !  3 PICK _AS-O-GX + !       ( s x0 y0 )
    2 PICK -ROT _AS-TILE-AT                        ( s start )
    OVER DUP _AS-O-GX + @ OVER _AS-O-GY + @ _AS-TILE-AT   ( s start goal )
    OVER 0< OVER 0< OR IF
        2DROP 0 OVER _AS-O-PN + ! 0 SWAP _AS-O-EXPANDED + ! ASTAR-NONE EXIT
    THEN
    2DUP <> IF
        2 PICK OVER _AS-TILE-COST 0= IF
            2DROP 0 OVER _AS-O-PN + ! 0 SWAP _AS-O-EXPANDED + ! ASTAR-NONE EXIT
        THEN
    THEN
    2 PICK SWAP _AS-BEGIN                          ( s start )
    OVER SWAP _AS-SEED
    DUP _AS-SEARCH
    DUP ASTAR-FOUND = IF OVER _AS-BUILD-PATH THEN
    NIP ;

: ASTAR-PATH  ( search -- addr count )
    DUP _AS-O-PATH + @ SWAP _AS-O-PN + @ ;

: ASTAR-PATH-COST  ( search -- cost )  _AS-O-COST + @ ;

: ASTAR-EXPANDED  ( search -- n )  _AS-O-EXPANDED + @ ;

\ ASTAR-FIELD ( sources count search -- status )
\   Fill the distance of every reachable tile from the nearest of count
\   sources, an array of (x y) cell pairs.  ASTAR-FOUND when the field
\   is whole, ASTAR-SPENT when the budget stopped it, ASTAR-NONE when no
\   source lies on the map.  A source may stand on an impassable tile.
: ASTAR-FIELD  ( sources count search -- status )
    DUP -1 _AS-BEGIN
    -ROT 0 ?DO                                     ( s src )
        OVER OVER I 2* CELLS + DUP @ SWAP CELL+ @
        _AS-TILE-AT DUP 0< IF DROP ELSE 2 PICK SWAP _AS-SEED THEN
    LOOP
    DROP
    DUP _AS-O-HN + @ 0= IF DROP ASTAR-NONE EXIT THEN
    _AS-SEARCH DUP ASTAR-NONE = IF DROP ASTAR-FOUND THEN ;

\ ASTAR-DIST ( search x y -- d | -1 )
\   The tile's cost from the latest run's start, or field's nearest
\   source, when that run settled it; -1 otherwise.
: ASTAR-DIST  ( search x y -- d|-1 )
    2 PICK -ROT _AS-TILE-AT DUP 0< IF NIP EXIT THEN
    _AS-CLOSED-G ;

\ ASTAR-DOWNHILL ( search x y -- nx ny true | false )
\   The neighbour a legal step reaches that lies nearest the field's
\   sources, if it lies nearer than (x,y); the first such in the order
\   left, right, up, down, then the diagonals.
: ASTAR-DOWNHILL  ( search x y -- nx ny true | false )
    2 PICK _AS-O-CY + !  OVER _AS-O-CX + !         ( s )
    DUP DUP _AS-O-CX + @ OVER _AS-O-CY + @ ASTAR-DIST
    DUP 0< IF DROP -1 1 RSHIFT THEN
    -1 SWAP                                        ( s best best-d )
    2 PICK _AS-O-DIAG + @ IF 8 ELSE 4 THEN 0 ?DO
        2 PICK I _AS-LEGAL DROP                    ( s best best-d n )
        DUP 0< IF
            DROP
        ELSE
            3 PICK OVER _AS-CLOSED-G               ( s best best-d n d )
            DUP 0< IF
                2DROP
            ELSE
                DUP 3 PICK < IF ROT DROP ROT DROP ELSE 2DROP THEN
            THEN
        THEN
    LOOP
    DROP DUP 0< IF 2DROP FALSE EXIT THEN
    _AS-XY TRUE ;

\ =====================================================================
\  §9 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _astar-guard

' ASTAR-NEW      CONSTANT _astar-new-xt
' ASTAR-FREE     CONSTANT _astar-free-xt
' ASTAR-STEPS!   CONSTANT _astar-steps-xt
' ASTAR-CORNERS! CONSTANT _astar-corners-xt
' ASTAR-BUDGET!  CONSTANT _astar-budget-xt
' ASTAR-COST!    CONSTANT _astar-cost-xt
' ASTAR-RUN      CONSTANT _astar-run-xt
' ASTAR-FIELD    CONSTANT _astar-field-xt

: ASTAR-NEW      _astar-new-xt     _astar-guard WITH-GUARD ;
: ASTAR-FREE     _astar-free-xt    _astar-guard WITH-GUARD ;
: ASTAR-STEPS!   _astar-steps-xt   _astar-guard WITH-GUARD ;
: ASTAR-CORNERS! _astar-corners-xt _astar-guard WITH-GUARD ;
: ASTAR-BUDGET!  _astar-budget-xt  _astar-guard WITH-GUARD ;
: ASTAR-COST!    _astar-cost-xt    _astar-guard WITH-GUARD ;
: ASTAR-RUN      _astar-run-xt     _astar-guard WITH-GUARD ;
: ASTAR-FIELD    _astar-field-xt   _astar-guard WITH-GUARD ;
[THEN] [THEN]
