\ =====================================================================
\  akashic/game/2d/tile-physics.f — Discrete Tile-Based Movement
\ =====================================================================
\
\  Discrete tile-based movement engine with wall sliding, optional
\  gravity, one-way platforms, and per-collision callbacks.  Works
\  on the collision map from game/collide.f.
\
\  A move keeps its mover and position on the stacks, so a collision
\  callback may move other entities, through the same physics or
\  another.  The callback receives the mover and the tile it struck:
\    ( phys eid ecs tile-x tile-y tile-val -- )
\
\  Physics Descriptor (40 bytes, 5 cells):
\    +0   cmap        Collision map pointer
\    +8   grav-x      Gravity X per tick (0 for top-down)
\    +16  grav-y      Gravity Y per tick (0 for top-down)
\    +24  on-collide  Callback XT or 0
\    +32  one-way     One-way platform tile value (0 = disabled)
\
\  Public API:
\    TPHYS-NEW         ( cmap -- phys )
\    TPHYS-FREE        ( phys -- )
\    TPHYS-GRAVITY!    ( phys gx gy -- )
\    TPHYS-ONE-WAY!    ( phys tile-val -- )
\    TPHYS-ON-COLLIDE  ( phys xt -- )
\    TPHYS-MOVE        ( phys eid ecs dx dy -- rx ry )
\    TPHYS-GROUNDED?   ( phys eid ecs -- flag )
\    TPHYS-APPLY-GRAV  ( phys eid ecs -- rx ry )
\
\  Prefix: TPHYS- (public), _TPHYS- (internal)
\  Provider: akashic-game-2d-tile-physics
\  Dependencies: collide.f, ecs.f, components.f

PROVIDED akashic-game-2d-tile-physics

( kind: tphys-collide xt( phys eid ecs tile-x tile-y tile-val -- ) )

REQUIRE ../ecs.f
REQUIRE ../components.f
REQUIRE collide.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

 0 CONSTANT _TPHYS-O-CMAP
 8 CONSTANT _TPHYS-O-GX
16 CONSTANT _TPHYS-O-GY
24 CONSTANT _TPHYS-O-ONCOL  ( holds: tphys-collide )
32 CONSTANT _TPHYS-O-ONEWAY
40 CONSTANT _TPHYS-DESC-SZ

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

: TPHYS-NEW  ( cmap -- phys )
    _TPHYS-DESC-SZ ALLOCATE
    0<> ABORT" TPHYS-NEW: alloc"
    DUP _TPHYS-DESC-SZ 0 FILL
    SWAP OVER _TPHYS-O-CMAP + ! ;

: TPHYS-FREE  ( phys -- )
    FREE ;

\ =====================================================================
\  §3 — Configuration
\ =====================================================================

: TPHYS-GRAVITY!  ( phys gx gy -- )
    ROT >R
    R@ _TPHYS-O-GY + !
    R> _TPHYS-O-GX + ! ;

: TPHYS-ONE-WAY!  ( phys tile-val -- )
    SWAP _TPHYS-O-ONEWAY + ! ;

: TPHYS-ON-COLLIDE  ( phys xt -- )
    SWAP _TPHYS-O-ONCOL + ! ;

\ =====================================================================
\  §4 — Movement Internals
\ =====================================================================

\ The mover's position, from its position component
: _TPHYS-POS@  ( phys eid ecs -- x y )
    ROT DROP SWAP SYS-C-POS @ ECS-GET
    DUP 0= ABORT" TPHYS: no pos"
    DUP C-POS.X + @ SWAP C-POS.Y + @ ;

: _TPHYS-POS!  ( phys eid ecs x y -- )
    2>R ROT DROP SWAP SYS-C-POS @ ECS-GET
    DUP 0= ABORT" TPHYS: no pos"
    2R> ROT TUCK C-POS.Y + ! C-POS.X + ! ;

: _TPHYS-SOLID?  ( phys x y -- flag )
    ROT _TPHYS-O-CMAP + @ -ROT CMAP-SOLID? ;

: _TPHYS-TILE-VAL  ( phys x y -- val )
    ROT _TPHYS-O-CMAP + @ -ROT CMAP-GET ;

\ Is tile (x,y) a one-way platform?
: _TPHYS-ONE-WAY?  ( phys x y -- flag )
    2 PICK _TPHYS-O-ONEWAY + @ ?DUP 0= IF 2DROP DROP FALSE EXIT THEN
    >R _TPHYS-TILE-VAL R> = ;

\ Does tile (x,y) stop a sideways step?  Solid tiles do, unless one-way.
: _TPHYS-WALL?  ( phys x y -- flag )
    2 PICK 2 PICK 2 PICK _TPHYS-SOLID? 0= IF 2DROP DROP FALSE EXIT THEN
    _TPHYS-ONE-WAY? 0= ;

\ Does tile (x,ny) stop a vertical step of dy?  Solid tiles do, except
\ that a one-way platform stops only a step down.
: _TPHYS-STOPS-Y?  ( phys x ny dy -- flag )
    >R 2 PICK 2 PICK 2 PICK _TPHYS-SOLID? 0= IF
        2DROP DROP R> DROP FALSE EXIT
    THEN
    _TPHYS-ONE-WAY? IF R> 0> ELSE R> DROP TRUE THEN ;

\ Fire the collision callback for the mover and tile (x,y).
: _TPHYS-FIRE  ( phys eid ecs x y -- )
    4 PICK _TPHYS-O-ONCOL + @ ?DUP 0= IF 2DROP 2DROP DROP EXIT THEN
    >R 4 PICK 2 PICK 2 PICK _TPHYS-TILE-VAL R> EXECUTE ;

\ The sideways step: a wall fires the callback and keeps the old x.
: _TPHYS-STEP-X  ( phys eid ecs x y dx -- phys eid ecs x' y )
    2 PICK + OVER                                ( phys eid ecs x y nx y )
    6 PICK 2 PICK 2 PICK _TPHYS-WALL? IF
        6 PICK 6 PICK 6 PICK 4 PICK 4 PICK _TPHYS-FIRE
        2DROP
    ELSE
        DROP ROT DROP SWAP
    THEN ;

\ The vertical step: a stop fires the callback and keeps the old y.
: _TPHYS-STEP-Y  ( phys eid ecs x y dy -- phys eid ecs x y' )
    2DUP + SWAP                                  ( phys eid ecs x y ny dy )
    6 PICK 4 PICK 3 PICK 3 PICK _TPHYS-STOPS-Y? IF
        DROP >R 4 PICK 4 PICK 4 PICK 4 PICK R> _TPHYS-FIRE
    ELSE
        DROP NIP
    THEN ;

\ =====================================================================
\  §5 — Public Movement API
\ =====================================================================

\ TPHYS-MOVE ( phys eid ecs dx dy -- rx ry )
\   Step sideways, then vertically, sliding along walls, and return the
\   position reached.
: TPHYS-MOVE  ( phys eid ecs dx dy -- rx ry )
    2>R 2 PICK 2 PICK 2 PICK _TPHYS-POS@         ( phys eid ecs x y  R: dx dy )
    2R> >R _TPHYS-STEP-X                         ( phys eid ecs x y  R: dy )
    R> _TPHYS-STEP-Y
    2DUP 2>R _TPHYS-POS! 2R> ;

: TPHYS-GROUNDED?  ( phys eid ecs -- flag )
    2 PICK >R _TPHYS-POS@ 1+ R> -ROT _TPHYS-SOLID? ;

: TPHYS-APPLY-GRAV  ( phys eid ecs -- rx ry )
    2 PICK DUP _TPHYS-O-GX + @ SWAP _TPHYS-O-GY + @ TPHYS-MOVE ;

\ =====================================================================
\  §6 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _tphys-guard

' TPHYS-NEW        CONSTANT _tphys-new-xt
' TPHYS-FREE       CONSTANT _tphys-free-xt
' TPHYS-GRAVITY!   CONSTANT _tphys-grav-xt
' TPHYS-ONE-WAY!   CONSTANT _tphys-oneway-xt
' TPHYS-ON-COLLIDE CONSTANT _tphys-oncoll-xt
' TPHYS-MOVE       CONSTANT _tphys-move-xt
' TPHYS-APPLY-GRAV CONSTANT _tphys-agrav-xt

: TPHYS-NEW        _tphys-new-xt    _tphys-guard WITH-GUARD ;
: TPHYS-FREE       _tphys-free-xt   _tphys-guard WITH-GUARD ;
: TPHYS-GRAVITY!   _tphys-grav-xt   _tphys-guard WITH-GUARD ;
: TPHYS-ONE-WAY!   _tphys-oneway-xt _tphys-guard WITH-GUARD ;
: TPHYS-ON-COLLIDE _tphys-oncoll-xt _tphys-guard WITH-GUARD ;
: TPHYS-MOVE       _tphys-move-xt   _tphys-guard WITH-GUARD ;
: TPHYS-APPLY-GRAV _tphys-agrav-xt  _tphys-guard WITH-GUARD ;
[THEN] [THEN]
