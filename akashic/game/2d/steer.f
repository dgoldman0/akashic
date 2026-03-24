\ =====================================================================
\  akashic/game/2d/steer.f — Steering Behaviors
\ =====================================================================
\
\  High-level movement patterns that write to the C-VEL component.
\  Combine with SYS-VELOCITY for automatic position updates.
\
\  Public API:
\    STEER-SEEK          ( eid ecs target-x target-y -- )
\    STEER-FLEE          ( eid ecs threat-x threat-y -- )
\    STEER-WANDER        ( eid ecs -- )
\    STEER-FOLLOW-PATH   ( eid ecs path count -- )
\    STEER-PATROL        ( eid ecs waypoints count -- )
\    STEER-BIND-AI       ( c-ai -- )   set component ID for patrol
\    STEER-SEED!         ( n -- )       seed the wander RNG
\
\  Path / waypoint format:
\    Array of cell pairs:  arr[i*2] = x, arr[i*2+1] = y.
\    Compatible with ASTAR-FIND output.
\
\  Prefix: STEER- (public), _ST- (internal)
\  Provider: akashic-game-2d-steer
\  Dependencies: ecs.f, components.f, systems.f

PROVIDED akashic-game-2d-steer

REQUIRE ../ecs.f
REQUIRE ../components.f
REQUIRE ../systems.f

\ =====================================================================
\  §1 — Configuration
\ =====================================================================

VARIABLE _ST-C-AI      \ AI component ID (for patrol state)

: STEER-BIND-AI  ( c-ai -- )  _ST-C-AI ! ;

\ =====================================================================
\  §2 — Internal Helpers
\ =====================================================================

VARIABLE _ST-EID   VARIABLE _ST-ECS
VARIABLE _ST-PX    VARIABLE _ST-PY      \ entity position
VARIABLE _ST-TX    VARIABLE _ST-TY      \ target position

\ Load entity position into _ST-PX / _ST-PY.
\ Also stores eid/ecs for later use by _ST-WRITE-VEL.
: _ST-LOAD-POS  ( eid ecs -- ok? )
    _ST-ECS !  _ST-EID !
    _ST-ECS @ _ST-EID @ SYS-C-POS @ ECS-GET
    DUP 0= IF DROP 0 EXIT THEN
    DUP C-POS.X + @ _ST-PX !
    C-POS.Y + @ _ST-PY !
    -1 ;

\ Signum:  n → -1 | 0 | 1
: _ST-SIGN  ( n -- -1|0|1 )
    DUP 0> IF DROP 1 EXIT THEN
    0< IF -1 ELSE 0 THEN ;

\ Write dx dy to the entity's C-VEL component.
: _ST-WRITE-VEL  ( dx dy -- )
    _ST-ECS @ _ST-EID @ SYS-C-VEL @ ECS-GET
    DUP 0= IF DROP 2DROP EXIT THEN
    >R
    R@ C-VEL.DY + !
    R> C-VEL.DX + ! ;

\ =====================================================================
\  §3 — STEER-SEEK
\ =====================================================================

: STEER-SEEK  ( eid ecs target-x target-y -- )
    _ST-TY !  _ST-TX !
    _ST-LOAD-POS 0= IF EXIT THEN
    _ST-TX @ _ST-PX @ - _ST-SIGN
    _ST-TY @ _ST-PY @ - _ST-SIGN
    _ST-WRITE-VEL ;

\ =====================================================================
\  §4 — STEER-FLEE
\ =====================================================================

: STEER-FLEE  ( eid ecs threat-x threat-y -- )
    _ST-TY !  _ST-TX !
    _ST-LOAD-POS 0= IF EXIT THEN
    _ST-PX @ _ST-TX @ - _ST-SIGN
    _ST-PY @ _ST-TY @ - _ST-SIGN
    _ST-WRITE-VEL ;

\ =====================================================================
\  §5 — STEER-WANDER
\ =====================================================================

VARIABLE _ST-RNG
12345 _ST-RNG !

: _ST-RAND  ( -- n )
    _ST-RNG @ 1103515245 * 12345 +
    DUP _ST-RNG ! ;

: STEER-SEED!  ( n -- )  _ST-RNG ! ;

: STEER-WANDER  ( eid ecs -- )
    _ST-LOAD-POS 0= IF EXIT THEN
    _ST-RAND ABS 3 MOD 1-
    _ST-RAND ABS 3 MOD 1-
    _ST-WRITE-VEL ;

\ =====================================================================
\  §6 — STEER-FOLLOW-PATH
\ =====================================================================

VARIABLE _SFP-PATH   VARIABLE _SFP-CNT

: _SFP-PATH-X  ( idx -- x )  2* CELLS _SFP-PATH @ + @ ;
: _SFP-PATH-Y  ( idx -- y )  2* 1+ CELLS _SFP-PATH @ + @ ;

: STEER-FOLLOW-PATH  ( eid ecs path count -- )
    _SFP-CNT !  _SFP-PATH !
    _ST-LOAD-POS 0= IF EXIT THEN
    \ Scan path for current position; seek toward next step
    _SFP-CNT @ 1- 0 ?DO
        I _SFP-PATH-X _ST-PX @ =
        I _SFP-PATH-Y _ST-PY @ = AND IF
            I 1+ _SFP-PATH-X _ST-PX @ - _ST-SIGN
            I 1+ _SFP-PATH-Y _ST-PY @ - _ST-SIGN
            _ST-WRITE-VEL
            UNLOOP EXIT
        THEN
    LOOP
    \ Not on path or already at goal — stop
    0 0 _ST-WRITE-VEL ;

\ =====================================================================
\  §7 — STEER-PATROL
\ =====================================================================
\
\  Cycles through waypoints.  Uses C-AI.STATE to persist the
\  current waypoint index per entity.  Call STEER-BIND-AI once
\  with the AI component ID before use.

VARIABLE _SP-WPS   VARIABLE _SP-CNT   VARIABLE _SP-IDX

: _SP-WP-X  ( idx -- x )  2* CELLS _SP-WPS @ + @ ;
: _SP-WP-Y  ( idx -- y )  2* 1+ CELLS _SP-WPS @ + @ ;

: STEER-PATROL  ( eid ecs waypoints count -- )
    _SP-CNT !  _SP-WPS !
    _ST-LOAD-POS 0= IF EXIT THEN
    \ Read current waypoint index from AI component
    _ST-ECS @ _ST-EID @ _ST-C-AI @ ECS-GET
    DUP 0= IF DROP 0 0 _ST-WRITE-VEL EXIT THEN
    ( ai-addr )
    DUP C-AI.STATE + @ _SP-IDX !
    \ If at current waypoint, advance to next
    _SP-IDX @ _SP-WP-X _ST-PX @ =
    _SP-IDX @ _SP-WP-Y _ST-PY @ = AND IF
        _SP-IDX @ 1+ _SP-CNT @ MOD _SP-IDX !
        _SP-IDX @ OVER C-AI.STATE + !
    THEN
    DROP  \ drop ai-addr
    \ Seek toward current waypoint
    _SP-IDX @ _SP-WP-X _ST-PX @ - _ST-SIGN
    _SP-IDX @ _SP-WP-Y _ST-PY @ - _ST-SIGN
    _ST-WRITE-VEL ;

\ =====================================================================
\  §8 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _steer-guard

' STEER-BIND-AI     CONSTANT _steer-bind-xt
' STEER-SEEK        CONSTANT _steer-seek-xt
' STEER-FLEE        CONSTANT _steer-flee-xt
' STEER-WANDER      CONSTANT _steer-wander-xt
' STEER-SEED!       CONSTANT _steer-seed-xt
' STEER-FOLLOW-PATH CONSTANT _steer-fpath-xt
' STEER-PATROL      CONSTANT _steer-patrol-xt

: STEER-BIND-AI     _steer-bind-xt   _steer-guard WITH-GUARD ;
: STEER-SEEK        _steer-seek-xt   _steer-guard WITH-GUARD ;
: STEER-FLEE        _steer-flee-xt   _steer-guard WITH-GUARD ;
: STEER-WANDER      _steer-wander-xt _steer-guard WITH-GUARD ;
: STEER-SEED!       _steer-seed-xt   _steer-guard WITH-GUARD ;
: STEER-FOLLOW-PATH _steer-fpath-xt  _steer-guard WITH-GUARD ;
: STEER-PATROL      _steer-patrol-xt _steer-guard WITH-GUARD ;
[THEN] [THEN]
