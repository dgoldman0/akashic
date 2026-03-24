\ =====================================================================
\  akashic/tui/game/fsm.f — Finite State Machine
\ =====================================================================
\
\  General-purpose FSM for entity AI or game state management.
\  States carry on-enter / on-tick / on-leave callbacks.
\  Transitions are guarded — a guard-xt is evaluated each tick to
\  decide whether to fire.
\
\  FSM Descriptor (40 bytes, 5 cells):
\    +0   states      Array of state descriptors
\    +8   n-states    Number of defined states
\    +16  max-states  Capacity
\    +24  transitions Array of transition descriptors
\    +32  n-trans     Number of defined transitions
\    +40  max-trans   Maximum transitions
\    +48  current     Current state id (-1 = not started)
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
\    FSM-START       ( fsm state-id -- )
\    FSM-TICK        ( fsm eid ecs dt -- )
\    FSM-CURRENT     ( fsm -- state-id )
\    FSM-FREE        ( fsm -- )
\
\  Prefix: FSM- (public), _FSM- (internal)
\  Provider: akashic-tui-game-fsm
\  Dependencies: (standalone)

PROVIDED akashic-tui-game-fsm

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
48 CONSTANT _FSM-O-CURRENT
56 CONSTANT _FSM-DESC-SZ

\ State descriptor offsets (40 bytes)
0  CONSTANT _FSM-S-NAMEA
8  CONSTANT _FSM-S-NAMEU
16 CONSTANT _FSM-S-ENTER
24 CONSTANT _FSM-S-TICK
32 CONSTANT _FSM-S-LEAVE
40 CONSTANT _FSM-STATE-SZ

\ Transition descriptor offsets (24 bytes)
0  CONSTANT _FSM-T-FROM
8  CONSTANT _FSM-T-TO
16 CONSTANT _FSM-T-GUARD
24 CONSTANT _FSM-TRANS-SZ

\ Defaults
16 CONSTANT _FSM-DEF-STATES
32 CONSTANT _FSM-DEF-TRANS

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

: FSM-NEW  ( -- fsm )
    _FSM-DESC-SZ ALLOCATE
    0<> ABORT" FSM-NEW: desc alloc"
    DUP _FSM-DESC-SZ 0 FILL
    \ Allocate state array
    _FSM-DEF-STATES _FSM-STATE-SZ * ALLOCATE
    0<> ABORT" FSM-NEW: states alloc"
    OVER _FSM-O-STATES + !
    _FSM-DEF-STATES OVER _FSM-O-MAXST + !
    0 OVER _FSM-O-NSTATES + !
    \ Allocate transition array
    _FSM-DEF-TRANS _FSM-TRANS-SZ * ALLOCATE
    0<> ABORT" FSM-NEW: trans alloc"
    OVER _FSM-O-TRANS + !
    _FSM-DEF-TRANS OVER _FSM-O-MAXTRANS + !
    0 OVER _FSM-O-NTRANS + !
    \ Not started
    -1 OVER _FSM-O-CURRENT + ! ;

: FSM-FREE  ( fsm -- )
    DUP _FSM-O-STATES + @ FREE
    DUP _FSM-O-TRANS + @ FREE
    FREE ;

\ =====================================================================
\  §3 — State Definition
\ =====================================================================

VARIABLE _FSM-TMP

\ FSM-STATE ( fsm name-a name-u on-enter on-tick on-leave -- state-id )
\   Define a new state.  Returns the state id (0-based index).
VARIABLE _FSM-ST-FSM
VARIABLE _FSM-ST-NA
VARIABLE _FSM-ST-NU
VARIABLE _FSM-ST-ENT
VARIABLE _FSM-ST-TCK
VARIABLE _FSM-ST-LV
: FSM-STATE  ( fsm name-a name-u on-enter on-tick on-leave -- state-id )
    _FSM-ST-LV ! _FSM-ST-TCK ! _FSM-ST-ENT !
    _FSM-ST-NU ! _FSM-ST-NA ! _FSM-ST-FSM !
    \ Check capacity
    _FSM-ST-FSM @ _FSM-O-NSTATES + @
    _FSM-ST-FSM @ _FSM-O-MAXST + @ >= ABORT" FSM-STATE: full"
    \ Get slot address
    _FSM-ST-FSM @ _FSM-O-NSTATES + @ _FSM-TMP !
    _FSM-ST-FSM @ _FSM-O-STATES + @
    _FSM-TMP @ _FSM-STATE-SZ * +     ( slot-addr )
    DUP _FSM-STATE-SZ 0 FILL
    _FSM-ST-NA @  OVER _FSM-S-NAMEA + !
    _FSM-ST-NU @  OVER _FSM-S-NAMEU + !
    _FSM-ST-ENT @ OVER _FSM-S-ENTER + !
    _FSM-ST-TCK @ OVER _FSM-S-TICK  + !
    _FSM-ST-LV @  SWAP _FSM-S-LEAVE + !
    \ Increment count, return id
    _FSM-ST-FSM @ _FSM-O-NSTATES + DUP @ 1+ SWAP !
    _FSM-TMP @ ;

\ =====================================================================
\  §4 — Transition Definition
\ =====================================================================

VARIABLE _FSM-TR-FSM
VARIABLE _FSM-TR-FROM
VARIABLE _FSM-TR-TO
VARIABLE _FSM-TR-GUARD
: FSM-TRANSITION  ( fsm from-id to-id guard-xt -- )
    _FSM-TR-GUARD ! _FSM-TR-TO ! _FSM-TR-FROM ! _FSM-TR-FSM !
    \ Check capacity
    _FSM-TR-FSM @ _FSM-O-NTRANS + @
    _FSM-TR-FSM @ _FSM-O-MAXTRANS + @ >= ABORT" FSM-TRANSITION: full"
    \ Get slot
    _FSM-TR-FSM @ _FSM-O-NTRANS + @ _FSM-TMP !
    _FSM-TR-FSM @ _FSM-O-TRANS + @
    _FSM-TMP @ _FSM-TRANS-SZ * +     ( slot-addr )
    _FSM-TR-FROM @  OVER _FSM-T-FROM  + !
    _FSM-TR-TO @    OVER _FSM-T-TO    + !
    _FSM-TR-GUARD @ SWAP _FSM-T-GUARD + !
    _FSM-TR-FSM @ _FSM-O-NTRANS + DUP @ 1+ SWAP ! ;

\ =====================================================================
\  §5 — State Lookup Helper
\ =====================================================================

: _FSM-GET-STATE  ( fsm id -- state-addr )
    _FSM-STATE-SZ * SWAP _FSM-O-STATES + @ + ;

\ =====================================================================
\  §6 — Start / Tick / Current
\ =====================================================================

\ FSM-START ( fsm state-id -- )
\   Enter initial state.  Calls on-enter for that state with 0 0.
VARIABLE _FSM-START-FSM
VARIABLE _FSM-START-ID
: FSM-START  ( fsm state-id -- )
    _FSM-START-ID ! _FSM-START-FSM !
    _FSM-START-ID @ _FSM-START-FSM @ _FSM-O-CURRENT + !
    _FSM-START-FSM @ _FSM-START-ID @ _FSM-GET-STATE
    _FSM-S-ENTER + @ DUP IF
        0 0 ROT EXECUTE
    ELSE
        DROP
    THEN ;

\ Internal: perform a transition from current to to-id.
VARIABLE _FSM-DO-FSM
VARIABLE _FSM-DO-EID
VARIABLE _FSM-DO-ECS
VARIABLE _FSM-DO-TO
: _FSM-DO-TRANSIT  ( fsm eid ecs to-id -- )
    _FSM-DO-TO ! _FSM-DO-ECS ! _FSM-DO-EID ! _FSM-DO-FSM !
    \ Call on-leave of current state
    _FSM-DO-FSM @ DUP _FSM-O-CURRENT + @ _FSM-GET-STATE
    _FSM-S-LEAVE + @ DUP IF
        _FSM-DO-EID @ _FSM-DO-ECS @ ROT EXECUTE
    ELSE
        DROP
    THEN
    \ Set new current
    _FSM-DO-TO @ _FSM-DO-FSM @ _FSM-O-CURRENT + !
    \ Call on-enter of new state
    _FSM-DO-FSM @ _FSM-DO-TO @ _FSM-GET-STATE
    _FSM-S-ENTER + @ DUP IF
        _FSM-DO-EID @ _FSM-DO-ECS @ ROT EXECUTE
    ELSE
        DROP
    THEN ;

\ FSM-TICK ( fsm eid ecs dt -- )
\   Evaluate all transitions from current state (first match wins),
\   then call on-tick of the (possibly new) current state.
VARIABLE _FSM-TK-FSM
VARIABLE _FSM-TK-EID
VARIABLE _FSM-TK-ECS
VARIABLE _FSM-TK-DT
VARIABLE _FSM-TK-CUR
VARIABLE _FSM-TK-I
VARIABLE _FSM-TK-TA
: FSM-TICK  ( fsm eid ecs dt -- )
    _FSM-TK-DT ! _FSM-TK-ECS ! _FSM-TK-EID ! _FSM-TK-FSM !
    _FSM-TK-FSM @ _FSM-O-CURRENT + @ _FSM-TK-CUR !
    _FSM-TK-CUR @ -1 = IF EXIT THEN  \ not started
    \ Scan transitions
    0 _FSM-TK-I !
    BEGIN _FSM-TK-I @ _FSM-TK-FSM @ _FSM-O-NTRANS + @ < WHILE
        _FSM-TK-FSM @ _FSM-O-TRANS + @
        _FSM-TK-I @ _FSM-TRANS-SZ * + _FSM-TK-TA !
        \ Check if from-id matches current
        _FSM-TK-TA @ _FSM-T-FROM + @ _FSM-TK-CUR @ = IF
            \ Evaluate guard
            _FSM-TK-EID @ _FSM-TK-ECS @
            _FSM-TK-TA @ _FSM-T-GUARD + @ EXECUTE IF
                \ Fire transition
                _FSM-TK-FSM @ _FSM-TK-EID @ _FSM-TK-ECS @
                _FSM-TK-TA @ _FSM-T-TO + @ _FSM-DO-TRANSIT
                _FSM-TK-FSM @ _FSM-O-CURRENT + @ _FSM-TK-CUR !
                _FSM-TK-FSM @ _FSM-O-NTRANS + @ _FSM-TK-I !
            ELSE
                1 _FSM-TK-I +!
            THEN
        ELSE
            1 _FSM-TK-I +!
        THEN
    REPEAT
    \ Call on-tick of current state
    _FSM-TK-FSM @ _FSM-TK-CUR @ _FSM-GET-STATE
    _FSM-S-TICK + @ DUP IF
        _FSM-TK-TA !
        _FSM-TK-EID @ _FSM-TK-ECS @ _FSM-TK-DT @ _FSM-TK-TA @ EXECUTE
    ELSE
        DROP
    THEN ;

\ FSM-CURRENT ( fsm -- state-id )
: FSM-CURRENT  ( fsm -- state-id )
    _FSM-O-CURRENT + @ ;

\ =====================================================================
\  §7 — Concurrency Guards
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
