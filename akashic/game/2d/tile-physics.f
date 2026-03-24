\ =====================================================================
\  akashic/game/2d/tile-physics.f — Discrete Tile-Based Movement
\ =====================================================================
\
\  Discrete tile-based movement engine with wall sliding, optional
\  gravity, one-way platforms, and per-collision callbacks.  Works
\  on the collision map from game/collide.f.
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

REQUIRE ../ecs.f
REQUIRE ../components.f
REQUIRE collide.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

 0 CONSTANT _TPHYS-O-CMAP
 8 CONSTANT _TPHYS-O-GX
16 CONSTANT _TPHYS-O-GY
24 CONSTANT _TPHYS-O-ONCOL
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

VARIABLE _TPHYS-TMP    \ phys pointer during MOVE
VARIABLE _TPHYS-EID
VARIABLE _TPHYS-ECS

\ _TPHYS-POS ( -- x y )  Read entity position from ECS
: _TPHYS-POS  ( -- x y )
    _TPHYS-ECS @ _TPHYS-EID @ SYS-C-POS @ ECS-GET
    DUP 0= ABORT" TPHYS: no pos"
    DUP C-POS.X + @
    SWAP C-POS.Y + @ ;

\ _TPHYS-SET-POS ( x y -- )  Write entity position
: _TPHYS-SET-POS  ( x y -- )
    _TPHYS-ECS @ _TPHYS-EID @ SYS-C-POS @ ECS-GET
    DUP 0= ABORT" TPHYS: no pos"
    >R
    R@ C-POS.Y + !
    R> C-POS.X + ! ;

\ _TPHYS-SOLID? ( x y -- flag )  Check collision map at tile (x,y)
: _TPHYS-SOLID?  ( x y -- flag )
    _TPHYS-TMP @ _TPHYS-O-CMAP + @ -ROT CMAP-SOLID? ;

\ _TPHYS-ONEWAY? ( x y -- flag )  Is tile a one-way platform?
: _TPHYS-ONEWAY?  ( x y -- flag )
    _TPHYS-TMP @ _TPHYS-O-ONEWAY + @ 0= IF 2DROP 0 EXIT THEN
    _TPHYS-TMP @ _TPHYS-O-CMAP + @ -ROT CMAP-GET
    _TPHYS-TMP @ _TPHYS-O-ONEWAY + @ = ;

\ _TPHYS-TILE-VAL ( x y -- val )  Read tile collision value
: _TPHYS-TILE-VAL  ( x y -- val )
    _TPHYS-TMP @ _TPHYS-O-CMAP + @ -ROT CMAP-GET ;

\ _TPHYS-FIRE ( tile-x tile-y tile-val -- )
\   Fire collision callback: ( eid tile-x tile-y tile-val -- ).
VARIABLE _TPHYS-FV

: _TPHYS-FIRE  ( x y val -- )
    _TPHYS-TMP @ _TPHYS-O-ONCOL + @ ?DUP IF
        >R _TPHYS-FV !                ( x y  R: xt )
        _TPHYS-EID @ -ROT             ( eid x y  R: xt )
        _TPHYS-FV @                    ( eid x y val  R: xt )
        R> EXECUTE
    ELSE
        DROP 2DROP
    THEN ;

\ _TPHYS-TRY-MOVE ( cur-x cur-y dx dy -- new-x new-y )
\   Attempt horizontal then vertical movement with wall sliding.
\   Fires collision callback on each blocked axis.
VARIABLE _TPHYS-CX  VARIABLE _TPHYS-CY
VARIABLE _TPHYS-DX  VARIABLE _TPHYS-DY
VARIABLE _TPHYS-NX  VARIABLE _TPHYS-NY

: _TPHYS-TRY-MOVE  ( cur-x cur-y dx dy -- new-x new-y )
    _TPHYS-DY !  _TPHYS-DX !  _TPHYS-CY !  _TPHYS-CX !
    _TPHYS-CX @ _TPHYS-DX @ + _TPHYS-NX !
    _TPHYS-CY @ _TPHYS-DY @ + _TPHYS-NY !

    \ ── Horizontal: test (nx, cy) ──
    _TPHYS-NX @ _TPHYS-CY @ _TPHYS-SOLID? IF
        _TPHYS-NX @ _TPHYS-CY @ _TPHYS-ONEWAY? IF
            \ One-way: passable horizontally — keep nx
        ELSE
            \ Blocked: fire callback, revert to old x
            _TPHYS-NX @ _TPHYS-CY @
            2DUP _TPHYS-TILE-VAL _TPHYS-FIRE
            _TPHYS-CX @ _TPHYS-NX !
        THEN
    THEN

    \ ── Vertical: test (nx, ny) ──
    _TPHYS-NX @ _TPHYS-NY @ _TPHYS-SOLID? IF
        _TPHYS-NX @ _TPHYS-NY @ _TPHYS-ONEWAY? IF
            \ One-way: block only downward (dy > 0)
            _TPHYS-DY @ 0> IF
                _TPHYS-NX @ _TPHYS-NY @
                2DUP _TPHYS-TILE-VAL _TPHYS-FIRE
                _TPHYS-CY @ _TPHYS-NY !
            THEN
        ELSE
            \ Solid: fire callback, revert to old y
            _TPHYS-NX @ _TPHYS-NY @
            2DUP _TPHYS-TILE-VAL _TPHYS-FIRE
            _TPHYS-CY @ _TPHYS-NY !
        THEN
    THEN

    _TPHYS-NX @ _TPHYS-NY @ ;

\ =====================================================================
\  §5 — Public Movement API
\ =====================================================================

: TPHYS-MOVE  ( phys eid ecs dx dy -- rx ry )
    2>R                                ( phys eid ecs  R: dx dy )
    ROT _TPHYS-TMP !
    _TPHYS-ECS !
    _TPHYS-EID !
    _TPHYS-POS                         ( cx cy  R: dx dy )
    2R>                                ( cx cy dx dy )
    _TPHYS-TRY-MOVE                    ( nx ny )
    2DUP _TPHYS-SET-POS ;             ( rx ry )

: TPHYS-GROUNDED?  ( phys eid ecs -- flag )
    ROT _TPHYS-TMP !
    _TPHYS-ECS !  _TPHYS-EID !
    _TPHYS-POS                         ( x y )
    1+                                 \ tile below
    _TPHYS-SOLID? ;

: TPHYS-APPLY-GRAV  ( phys eid ecs -- rx ry )
    ROT DUP >R -ROT                    ( phys eid ecs  R: phys )
    R@ _TPHYS-O-GX + @                ( phys eid ecs gx  R: phys )
    R> _TPHYS-O-GY + @                ( phys eid ecs gx gy )
    TPHYS-MOVE ;

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
