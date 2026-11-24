\ =====================================================================
\  akashic/game/2d/steer.f — Steering Behaviors
\ =====================================================================
\
\  Movement patterns that set an entity's velocity to one step: each
\  behaviour writes a dx and a dy of -1, 0 or 1 into the entity's
\  velocity component, toward or away from its target, and moving the
\  entity is left to the caller, as with SYS-VELOCITY or TPHYS-MOVE.
\
\  A steering context holds the components the behaviours read and
\  write and a seeded generator for wandering, so two worlds, or two
\  kinds of creature, steer independently and a wander replays from
\  its seed.
\
\  Steering Context (32 bytes, 4 cells):
\    +0   c-pos       Position component id
\    +8   c-vel       Velocity component id
\    +16  c-ai        AI component id; patrol keeps its waypoint index
\                     at C-AI.STATE
\    +24  rng         The wander generator's state
\
\  Public API:
\    STEER-NEW           ( c-pos c-vel c-ai seed -- steer )
\    STEER-FREE          ( steer -- )
\    STEER-SEEK          ( steer eid ecs target-x target-y -- )
\    STEER-FLEE          ( steer eid ecs threat-x threat-y -- )
\    STEER-WANDER        ( steer eid ecs -- )
\    STEER-FOLLOW-PATH   ( steer eid ecs path count -- )
\    STEER-PATROL        ( steer eid ecs waypoints count -- )
\
\  Path / waypoint format:
\    Array of cell pairs:  arr[i*2] = x, arr[i*2+1] = y, as
\    ASTAR-PATH gives a path.
\
\  An entity without a position component is left alone.
\
\  Prefix: STEER- (public), _ST- (internal)
\  Provider: akashic-game-2d-steer
\  Dependencies: ecs.f, components.f

PROVIDED akashic-game-2d-steer

REQUIRE ../ecs.f
REQUIRE ../components.f

\ =====================================================================
\  §1 — Context
\ =====================================================================

0  CONSTANT _ST-O-CPOS
8  CONSTANT _ST-O-CVEL
16 CONSTANT _ST-O-CAI
24 CONSTANT _ST-O-RNG
32 CONSTANT _ST-DESC-SZ

: STEER-NEW  ( c-pos c-vel c-ai seed -- steer )
    _ST-DESC-SZ ALLOCATE
    0<> ABORT" STEER-NEW: alloc"
    TUCK _ST-O-RNG + !
    TUCK _ST-O-CAI + !
    TUCK _ST-O-CVEL + !
    TUCK _ST-O-CPOS + ! ;

: STEER-FREE  ( steer -- )  FREE ;

\ =====================================================================
\  §2 — Internal Helpers
\ =====================================================================

\ The entity's position, if it has one
: _ST-POS  ( steer eid ecs -- x y true | false )
    SWAP ROT _ST-O-CPOS + @ ECS-GET
    ?DUP IF DUP C-POS.X + @ SWAP C-POS.Y + @ TRUE ELSE FALSE THEN ;

\ Write dx dy into the entity's velocity, if it has one
: _ST-VEL!  ( steer eid ecs dx dy -- )
    2>R SWAP ROT _ST-O-CVEL + @ ECS-GET
    ?DUP IF 2R> ROT TUCK C-VEL.DY + ! C-VEL.DX + ! ELSE 2R> 2DROP THEN ;

\ Signum:  n → -1 | 0 | 1
: _ST-SIGN  ( n -- -1|0|1 )
    DUP 0> IF DROP 1 EXIT THEN
    0< IF -1 ELSE 0 THEN ;

\ One step from (px,py) toward (tx,ty), written as the velocity
: _ST-TOWARD  ( steer eid ecs px py tx ty -- )
    ROT - _ST-SIGN >R SWAP - _ST-SIGN R> _ST-VEL! ;

\ The context's generator: the same linear congruence as before
: _ST-RAND  ( steer -- n )
    DUP _ST-O-RNG + @ 1103515245 * 12345 + TUCK SWAP _ST-O-RNG + ! ;

\ =====================================================================
\  §3 — Seek and flee
\ =====================================================================

: STEER-SEEK  ( steer eid ecs target-x target-y -- )
    2>R 2 PICK 2 PICK 2 PICK _ST-POS 0= IF 2R> 2DROP 2DROP DROP EXIT THEN
    2R> _ST-TOWARD ;

: STEER-FLEE  ( steer eid ecs threat-x threat-y -- )
    2>R 2 PICK 2 PICK 2 PICK _ST-POS 0= IF 2R> 2DROP 2DROP DROP EXIT THEN
    2R> ROT SWAP - _ST-SIGN >R - _ST-SIGN R> _ST-VEL! ;

\ =====================================================================
\  §4 — Wander
\ =====================================================================

: STEER-WANDER  ( steer eid ecs -- )
    2 PICK 2 PICK 2 PICK _ST-POS 0= IF 2DROP DROP EXIT THEN
    2DROP
    2 PICK _ST-RAND ABS 3 MOD 1-
    3 PICK _ST-RAND ABS 3 MOD 1-
    _ST-VEL! ;

\ =====================================================================
\  §5 — Follow a path
\ =====================================================================

\ Seek the tile after the entity's place on the path; stop at the end
\ of the path or off it.
: STEER-FOLLOW-PATH  ( steer eid ecs path count -- )
    2>R 2 PICK 2 PICK 2 PICK _ST-POS 0= IF 2R> 2DROP 2DROP DROP EXIT THEN
    2R>                                           ( steer eid ecs px py path count )
    1- 0 MAX 0 ?DO
        DUP I 2* CELLS + @ 3 PICK =
        OVER I 2* 1+ CELLS + @ 3 PICK = AND IF
            I 1+ 2* CELLS + DUP @ SWAP CELL+ @
            _ST-TOWARD UNLOOP EXIT
        THEN
    LOOP
    DROP 2DROP 0 0 _ST-VEL! ;

\ =====================================================================
\  §6 — Patrol
\ =====================================================================
\
\  Cycles through waypoints, keeping the current waypoint's index at
\  C-AI.STATE of the entity's AI component.

: _ST-AI  ( steer eid ecs -- addr|0 )
    SWAP ROT _ST-O-CAI + @ ECS-GET ;

: STEER-PATROL  ( steer eid ecs waypoints count -- )
    DUP 1 < IF 2DROP 0 0 _ST-VEL! EXIT THEN
    2>R 2 PICK 2 PICK 2 PICK _ST-POS 0= IF 2R> 2DROP 2DROP DROP EXIT THEN
    4 PICK 4 PICK 4 PICK _ST-AI                   ( steer eid ecs px py ai|0 )
    ?DUP 0= IF 2DROP 2R> 2DROP 0 0 _ST-VEL! EXIT THEN
    C-AI.STATE + DUP @                            ( steer eid ecs px py cell idx )
    2R@ DROP OVER 2* CELLS + DUP @ SWAP CELL+ @   ( ... cell idx wx wy )
    4 PICK = SWAP 5 PICK = AND IF
        1+ R@ MOD 2DUP SWAP !
    THEN
    NIP 2R> DROP SWAP 2* CELLS + DUP @ SWAP CELL+ @
    _ST-TOWARD ;

\ =====================================================================
\  §7 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _steer-guard

' STEER-NEW         CONSTANT _steer-new-xt
' STEER-FREE        CONSTANT _steer-free-xt
' STEER-SEEK        CONSTANT _steer-seek-xt
' STEER-FLEE        CONSTANT _steer-flee-xt
' STEER-WANDER      CONSTANT _steer-wander-xt
' STEER-FOLLOW-PATH CONSTANT _steer-fpath-xt
' STEER-PATROL      CONSTANT _steer-patrol-xt

: STEER-NEW         _steer-new-xt    _steer-guard WITH-GUARD ;
: STEER-FREE        _steer-free-xt   _steer-guard WITH-GUARD ;
: STEER-SEEK        _steer-seek-xt   _steer-guard WITH-GUARD ;
: STEER-FLEE        _steer-flee-xt   _steer-guard WITH-GUARD ;
: STEER-WANDER      _steer-wander-xt _steer-guard WITH-GUARD ;
: STEER-FOLLOW-PATH _steer-fpath-xt  _steer-guard WITH-GUARD ;
: STEER-PATROL      _steer-patrol-xt _steer-guard WITH-GUARD ;
[THEN] [THEN]
