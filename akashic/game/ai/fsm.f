\ =====================================================================
\  akashic/game/ai/fsm.f — Finite State Machine
\ =====================================================================
\
\  General-purpose FSM for entity AI or game state management.
\  States carry on-enter / on-tick / on-leave callbacks.
\  Transitions are guarded — a guard-xt is evaluated each tick to
\  decide whether to fire.
\
\  A machine is a shared definition: its states and transitions, which
\  grow as they are defined.  Each entity keeps its current state in a
\  cell of its own, usually a field of its AI component, and passes the
\  cell's address to FSM-START and FSM-TICK, so one definition serves
\  any number of entities.  A cell of -1 marks a machine not started.
\  Ticks keep their place on the stacks, so a guard or a callback may
\  tick another machine.
\
\  FSM Descriptor (48 bytes, 6 cells):
\    +0   states      Array of state descriptors
\    +8   n-states    Number of defined states
\    +16  max-states  Capacity
\    +24  transitions Array of transition descriptors
\    +32  n-trans     Number of defined transitions
\    +40  max-trans   Capacity
\
\  State Descriptor (40 bytes, 5 cells):
\    +0   name-a      Name string address
\    +8   name-u      Name string length
\    +16  on-enter    xt or 0   ( eid ecs -- )
\    +24  on-tick     xt or 0   ( eid ecs dt -- )
\    +32  on-leave    xt or 0   ( eid ecs -- )
\
\  Transition Descriptor (24 bytes, 3 cells):
\    +0   from-id     Source state id
\    +8   to-id       Target state id
\    +16  guard-xt    ( eid ecs -- flag )
\
\  Public API:
\    FSM-NEW         ( -- fsm )
\    FSM-STATE       ( fsm name-a name-u on-enter on-tick on-leave -- state-id )
\    FSM-TRANSITION  ( fsm from-id to-id guard-xt -- )
\    FSM-START       ( fsm cell eid ecs state-id -- )
\    FSM-TICK        ( fsm cell eid ecs dt -- )
\    FSM-NAME        ( fsm state-id -- name-a name-u )
\    FSM-STATES      ( fsm -- n )
\    FSM-FREE        ( fsm -- )
\
\  Prefix: FSM- (public), _FSM- (internal)
\  Provider: akashic-game-ai-fsm
\  Dependencies: (standalone)

PROVIDED akashic-game-ai-fsm

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

\ FSM descriptor offsets
0  CONSTANT _FSM-O-STATES
8  CONSTANT _FSM-O-NSTATES
16 CONSTANT _FSM-O-MAXST
24 CONSTANT _FSM-O-TRANS
32 CONSTANT _FSM-O-NTRANS
40 CONSTANT _FSM-O-MAXTRANS
48 CONSTANT _FSM-DESC-SZ

( kind: fsm-step xt( eid ecs -- ) )
( kind: fsm-tick xt( eid ecs dt -- ) )
( kind: fsm-guard xt( eid ecs -- flag ) )

\ State descriptor offsets (40 bytes)
0  CONSTANT _FSM-S-NAMEA
8  CONSTANT _FSM-S-NAMEU
16 CONSTANT _FSM-S-ENTER  ( holds: fsm-step )
24 CONSTANT _FSM-S-TICK  ( holds: fsm-tick )
32 CONSTANT _FSM-S-LEAVE  ( holds: fsm-step )
40 CONSTANT _FSM-STATE-SZ

\ Transition descriptor offsets (24 bytes)
0  CONSTANT _FSM-T-FROM
8  CONSTANT _FSM-T-TO
16 CONSTANT _FSM-T-GUARD  ( holds: fsm-guard )
24 CONSTANT _FSM-TRANS-SZ

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

: FSM-NEW  ( -- fsm )
    _FSM-DESC-SZ ALLOCATE
    0<> ABORT" FSM-NEW: desc alloc"
    DUP _FSM-DESC-SZ 0 FILL
    4 _FSM-STATE-SZ * ALLOCATE
    0<> ABORT" FSM-NEW: states alloc"
    OVER _FSM-O-STATES + !
    4 OVER _FSM-O-MAXST + !
    8 _FSM-TRANS-SZ * ALLOCATE
    0<> ABORT" FSM-NEW: trans alloc"
    OVER _FSM-O-TRANS + !
    8 OVER _FSM-O-MAXTRANS + ! ;

: FSM-FREE  ( fsm -- )
    DUP _FSM-O-STATES + @ FREE
    DUP _FSM-O-TRANS + @ FREE
    FREE ;

\ Double an array's room: its pointer at fsm+array, its capacity at
\ fsm+cap, entries of size bytes.
: _FSM-GROW  ( fsm array cap size -- )
    >R >R OVER + SWAP R> + R>                    ( arr-addr cap-addr size )
    OVER @ 2* TUCK *                             ( arr-addr cap-addr cap' bytes )
    3 PICK @ SWAP RESIZE
    0<> ABORT" FSM: alloc"                       ( arr-addr cap-addr cap' arr )
    3 PICK !  SWAP !  DROP ;

\ =====================================================================
\  §3 — State Definition
\ =====================================================================

: _FSM-GET-STATE  ( fsm id -- state-addr )
    _FSM-STATE-SZ * SWAP _FSM-O-STATES + @ + ;

\ FSM-STATE ( fsm name-a name-u on-enter on-tick on-leave -- state-id )
\   Define a new state.  Returns the state id (0-based index).
: FSM-STATE  ( fsm name-a name-u on-enter on-tick on-leave -- state-id )
    5 PICK DUP _FSM-O-NSTATES + @ SWAP _FSM-O-MAXST + @ >= IF
        5 PICK _FSM-O-STATES _FSM-O-MAXST _FSM-STATE-SZ _FSM-GROW
    THEN
    5 PICK DUP _FSM-O-NSTATES + @ _FSM-GET-STATE >R
    R@ _FSM-S-LEAVE + !  R@ _FSM-S-TICK + !  R@ _FSM-S-ENTER + !
    R@ _FSM-S-NAMEU + !  R> _FSM-S-NAMEA + !
    DUP _FSM-O-NSTATES + @ SWAP _FSM-O-NSTATES + 1 SWAP +! ;

: FSM-NAME  ( fsm state-id -- name-a name-u )
    _FSM-GET-STATE DUP _FSM-S-NAMEA + @ SWAP _FSM-S-NAMEU + @ ;

: FSM-STATES  ( fsm -- n )  _FSM-O-NSTATES + @ ;

\ =====================================================================
\  §4 — Transition Definition
\ =====================================================================

: FSM-TRANSITION  ( fsm from-id to-id guard-xt -- )
    3 PICK DUP _FSM-O-NTRANS + @ SWAP _FSM-O-MAXTRANS + @ >= IF
        3 PICK _FSM-O-TRANS _FSM-O-MAXTRANS _FSM-TRANS-SZ _FSM-GROW
    THEN
    3 PICK DUP _FSM-O-NTRANS + @ _FSM-TRANS-SZ * SWAP _FSM-O-TRANS + @ +
    >R  R@ _FSM-T-GUARD + !  R@ _FSM-T-TO + !  R> _FSM-T-FROM + !
    _FSM-O-NTRANS + 1 SWAP +! ;

\ =====================================================================
\  §5 — Start / Tick
\ =====================================================================

\ A state's on-enter or on-leave, if it has one
: _FSM-ENTER  ( eid ecs state -- )
    _FSM-S-ENTER + @ ?DUP IF EXECUTE ELSE 2DROP THEN ;

: _FSM-LEAVE  ( eid ecs state -- )
    _FSM-S-LEAVE + @ ?DUP IF EXECUTE ELSE 2DROP THEN ;

\ FSM-START ( fsm cell eid ecs state-id -- )
\   Put the entity's machine, whose current state lives at cell, into
\   state-id, and call that state's on-enter with eid and ecs.
: FSM-START  ( fsm cell eid ecs state-id -- )
    DUP 4 PICK !
    4 PICK SWAP _FSM-GET-STATE _FSM-ENTER
    2DROP ;

\ Internal: leave the current state for to-id, calling on-leave and
\ on-enter.
: _FSM-DO-TRANSIT  ( fsm cell eid ecs to-id -- )
    >R
    2DUP 5 PICK 5 PICK @ _FSM-GET-STATE _FSM-LEAVE
    R@ 3 PICK !
    ROT DROP ROT R> _FSM-GET-STATE _FSM-ENTER ;

\ Internal: fire the first transition from the current state whose
\ guard passes, if any.  The scan keeps its place on the stack, so a
\ guard may tick another machine.
: _FSM-FIRE  ( fsm cell eid ecs -- )
    3 PICK DUP _FSM-O-TRANS + @ SWAP _FSM-O-NTRANS + @   ( fsm cell eid ecs ta n )
    BEGIN DUP 0> WHILE
        OVER _FSM-T-FROM + @ 5 PICK @ = IF
            3 PICK 3 PICK 3 PICK _FSM-T-GUARD + @ EXECUTE IF
                DROP _FSM-T-TO + @ _FSM-DO-TRANSIT EXIT
            THEN
        THEN
        1- SWAP _FSM-TRANS-SZ + SWAP
    REPEAT
    2DROP 2DROP 2DROP ;

\ FSM-TICK ( fsm cell eid ecs dt -- )
\   Evaluate all transitions from the entity's current state (first
\   match wins), then call on-tick of the (possibly new) current state.
\   A machine not started, its cell -1, does nothing.
: FSM-TICK  ( fsm cell eid ecs dt -- )
    3 PICK @ -1 = IF 2DROP 2DROP DROP EXIT THEN
    >R 3 PICK 3 PICK 3 PICK 3 PICK _FSM-FIRE      ( fsm cell eid ecs  R: dt )
    2SWAP @ _FSM-GET-STATE _FSM-S-TICK + @
    ?DUP IF R> SWAP EXECUTE ELSE 2DROP R> DROP THEN ;

\ =====================================================================
\  §6 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _fsm-guard

' FSM-NEW        CONSTANT _fsm-new-xt
' FSM-STATE      CONSTANT _fsm-state-xt
' FSM-TRANSITION CONSTANT _fsm-trans-xt
' FSM-START      CONSTANT _fsm-start-xt
' FSM-TICK       CONSTANT _fsm-tick-xt
' FSM-FREE       CONSTANT _fsm-free-xt

: FSM-NEW        _fsm-new-xt    _fsm-guard WITH-GUARD ;
: FSM-STATE      _fsm-state-xt  _fsm-guard WITH-GUARD ;
: FSM-TRANSITION _fsm-trans-xt  _fsm-guard WITH-GUARD ;
: FSM-START      _fsm-start-xt  _fsm-guard WITH-GUARD ;
: FSM-TICK       _fsm-tick-xt   _fsm-guard WITH-GUARD ;
: FSM-FREE       _fsm-free-xt   _fsm-guard WITH-GUARD ;
[THEN] [THEN]
