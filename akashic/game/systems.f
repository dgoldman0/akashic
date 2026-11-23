\ =====================================================================
\  akashic/game/systems.f — System Runner
\ =====================================================================
\
\  A registry of update systems executed in priority order each tick.
\  Each system is an XT that receives ( runner dt -- ), and finds its
\  ECS, its components and the caller's state through the runner.
\  Systems are sorted by priority (low runs first, and among equal
\  priorities the earlier added); the table grows as systems are
\  added, and each addition returns a handle that names its system
\  for as long as the runner lives.
\
\  The runner holds the component ids its built-in systems use, so two
\  ECS instances with different layouts each have a runner of their
\  own, and a context cell the caller sets for its own systems.  The
\  tick keeps its place on the stacks, so a system may tick another
\  runner.
\
\  Runner Descriptor (80 bytes, 10 cells):
\    +0   ecs         ECS instance pointer
\    +8   entries     Array of system entries
\    +16  count       Number of registered systems
\    +24  cap         Entries the array has room for
\    +32  next        The handle the next system gets
\    +40  c-pos       Position component id, -1 unbound
\    +48  c-vel       Velocity component id, -1 unbound
\    +56  c-hp        Health component id, -1 unbound
\    +64  c-tmr       Timer component id, -1 unbound
\    +72  ctx         The caller's context cell
\
\  System Entry (32 bytes, 4 cells):
\    +0   xt          System execution token ( runner dt -- )
\    +8   priority    Sort key (lower = earlier)
\    +16  enabled     Flag (0 = skip)
\    +24  handle      The system's handle
\
\  Public API:
\    SYSRUN-NEW     ( ecs -- runner )
\    SYSRUN-FREE    ( runner -- )
\    SYSRUN-ADD     ( runner xt priority -- handle )
\    SYSRUN-TICK    ( runner dt -- )
\    SYSRUN-ENABLE  ( runner handle -- )
\    SYSRUN-DISABLE ( runner handle -- )
\    SYSRUN-COUNT   ( runner -- n )
\    SYSRUN-ECS     ( runner -- ecs )
\    SYSRUN-BIND    ( runner c-pos c-vel c-hp c-tmr -- )
\    SYSRUN-CTX!    ( runner ctx -- )
\    SYSRUN-CTX     ( runner -- ctx )
\
\  Built-in systems (all: runner dt -- ):
\    SYS-VELOCITY   pos += vel * dt
\    SYS-TIMER      decrement timers, fire callbacks at zero
\    SYS-CULL-DEAD  kill entities with HP <= 0
\
\  Prefix: SYSRUN- (runner), SYS- (systems)
\  Provider: akashic-game-systems
\  Dependencies: ecs.f, components.f

PROVIDED akashic-game-systems

REQUIRE ecs.f
REQUIRE components.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

( kind: sys-step xt( runner dt -- ) )

0  CONSTANT _SR-O-ECS
8  CONSTANT _SR-O-ENTRIES
16 CONSTANT _SR-O-COUNT
24 CONSTANT _SR-O-CAP
32 CONSTANT _SR-O-NEXT
40 CONSTANT _SR-O-CPOS
48 CONSTANT _SR-O-CVEL
56 CONSTANT _SR-O-CHP
64 CONSTANT _SR-O-CTMR
72 CONSTANT _SR-O-CTX
80 CONSTANT _SR-DESC-SZ

0  CONSTANT _SR-E-XT  ( holds: sys-step )
8  CONSTANT _SR-E-PRI
16 CONSTANT _SR-E-ENABLED
24 CONSTANT _SR-E-HANDLE
32 CONSTANT _SR-ENTRY-SZ

\ =====================================================================
\  §2 — Constructor / Destructor / Binding
\ =====================================================================

: SYSRUN-NEW  ( ecs -- runner )
    _SR-DESC-SZ ALLOCATE
    0<> ABORT" SYSRUN-NEW: desc alloc"
    DUP _SR-DESC-SZ 0 FILL
    TUCK _SR-O-ECS + !
    8 _SR-ENTRY-SZ * ALLOCATE
    0<> ABORT" SYSRUN-NEW: entries alloc"
    OVER _SR-O-ENTRIES + !
    8 OVER _SR-O-CAP + !
    1 OVER _SR-O-NEXT + !
    -1 OVER _SR-O-CPOS + !  -1 OVER _SR-O-CVEL + !
    -1 OVER _SR-O-CHP + !   -1 OVER _SR-O-CTMR + ! ;

: SYSRUN-FREE  ( runner -- )
    DUP _SR-O-ENTRIES + @ FREE
    FREE ;

: SYSRUN-ECS  ( runner -- ecs )  _SR-O-ECS + @ ;

\ SYSRUN-BIND ( runner c-pos c-vel c-hp c-tmr -- )
\   The components the built-in systems read; -1 leaves one unbound.
: SYSRUN-BIND  ( runner c-pos c-vel c-hp c-tmr -- )
    4 PICK _SR-O-CTMR + !
    3 PICK _SR-O-CHP + !
    2 PICK _SR-O-CVEL + !
    SWAP _SR-O-CPOS + ! ;

: SYSRUN-CTX!  ( runner ctx -- )  SWAP _SR-O-CTX + ! ;
: SYSRUN-CTX   ( runner -- ctx )  _SR-O-CTX + @ ;

\ =====================================================================
\  §3 — Add System (insertion-sorted by priority)
\ =====================================================================

: _SR-ENTRY  ( runner i -- entry )
    _SR-ENTRY-SZ * SWAP _SR-O-ENTRIES + @ + ;

: _SR-GROW  ( runner -- )
    DUP _SR-O-CAP + @ 2*                          ( runner cap )
    OVER _SR-O-ENTRIES + @ OVER _SR-ENTRY-SZ * RESIZE
    0<> ABORT" SYSRUN: entries alloc"             ( runner cap entries )
    2 PICK _SR-O-ENTRIES + !
    SWAP _SR-O-CAP + ! ;

\ Swap entries i-1 and i.
: _SR-SWAP-DOWN  ( runner i -- )
    2DUP 1- _SR-ENTRY -ROT _SR-ENTRY               ( prev cur )
    4 0 DO
        OVER I CELLS + @  OVER I CELLS + @
        3 PICK I CELLS + !  OVER I CELLS + !
    LOOP
    2DROP ;

\ SYSRUN-ADD ( runner xt priority -- handle )
\   Add a system, enabled, after every system of lower or equal
\   priority, and return its handle.
: SYSRUN-ADD  ( runner xt priority -- handle )
    2 PICK DUP _SR-O-COUNT + @ SWAP _SR-O-CAP + @ >= IF 2 PICK _SR-GROW THEN
    2 PICK DUP _SR-O-COUNT + @ _SR-ENTRY           ( runner xt pri entry )
    TUCK _SR-E-PRI + !  TUCK _SR-E-XT + !          ( runner entry )
    -1 OVER _SR-E-ENABLED + !
    OVER _SR-O-NEXT + @ SWAP _SR-E-HANDLE + !      ( runner )
    1 OVER _SR-O-NEXT + +!
    1 OVER _SR-O-COUNT + +!
    DUP _SR-O-COUNT + @ 1-                         ( runner i )
    BEGIN
        DUP IF
            2DUP 1- _SR-ENTRY _SR-E-PRI + @  2 PICK 2 PICK _SR-ENTRY _SR-E-PRI + @ >
        ELSE
            FALSE
        THEN
    WHILE
        2DUP _SR-SWAP-DOWN 1-
    REPEAT
    _SR-ENTRY _SR-E-HANDLE + @ ;

\ =====================================================================
\  §4 — Tick
\ =====================================================================

: SYSRUN-TICK  ( runner dt -- )
    OVER _SR-O-COUNT + @ 0 ?DO
        OVER I _SR-ENTRY                            ( runner dt entry )
        DUP _SR-E-ENABLED + @ IF
            _SR-E-XT + @ 2 PICK 2 PICK ROT EXECUTE
        ELSE
            DROP
        THEN
    LOOP
    2DROP ;

\ =====================================================================
\  §5 — Enable / Disable / Count
\ =====================================================================

\ The entry of the system with this handle
: _SR-FIND  ( runner handle -- entry )
    OVER _SR-O-COUNT + @ 0 ?DO
        OVER I _SR-ENTRY DUP _SR-E-HANDLE + @ 2 PICK = IF
            NIP NIP UNLOOP EXIT
        THEN DROP
    LOOP
    TRUE ABORT" SYSRUN: no system with that handle" ;

: SYSRUN-ENABLE  ( runner handle -- )
    _SR-FIND -1 SWAP _SR-E-ENABLED + ! ;

: SYSRUN-DISABLE  ( runner handle -- )
    _SR-FIND 0 SWAP _SR-E-ENABLED + ! ;

: SYSRUN-COUNT  ( runner -- n )
    _SR-O-COUNT + @ ;

\ =====================================================================
\  §6 — Built-in systems
\ =====================================================================
\
\  Each reads its components from the runner and hands its step, or
\  its ECS, to the per-entity word as the iteration's context.

\ A component the runner binds, or an abort when it binds none
: _SR-COMP  ( runner offset -- comp )
    + @ DUP 0< ABORT" SYSRUN: a built-in system's component is unbound" ;

: _SYS-VEL-STEP  ( eid pos-addr vel-addr dt -- )
    >R
    DUP C-VEL.DX + @ R@ * 2 PICK C-POS.X + +!
    C-VEL.DY + @ R> * SWAP C-POS.Y + +!
    DROP ;

: SYS-VELOCITY  ( runner dt -- )
    >R DUP _SR-O-ECS + @
    OVER _SR-O-CPOS _SR-COMP ROT _SR-O-CVEL _SR-COMP
    ['] _SYS-VEL-STEP R> ECS-EACH2 ;

: _SYS-TMR-STEP  ( eid tmr-addr dt -- )
    OVER C-TMR.TICKS + @ SWAP -              \ ( eid tmr remaining )
    DUP 0> IF
        SWAP C-TMR.TICKS + ! DROP EXIT
    THEN
    DROP 0 OVER C-TMR.TICKS + !
    C-TMR.XT + @ ?DUP IF EXECUTE ELSE DROP THEN ;

: SYS-TIMER  ( runner dt -- )
    >R DUP _SR-O-ECS + @ SWAP _SR-O-CTMR _SR-COMP
    ['] _SYS-TMR-STEP R> ECS-EACH ;

: _SYS-CULL-STEP  ( eid hp-addr ecs -- )
    SWAP C-HP.CUR + @ 0> IF 2DROP EXIT THEN
    SWAP ECS-KILL ;

: SYS-CULL-DEAD  ( runner dt -- )
    DROP DUP _SR-O-ECS + @ SWAP _SR-O-CHP _SR-COMP
    ['] _SYS-CULL-STEP 2 PICK ECS-EACH ;

\ =====================================================================
\  §7 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _sys-guard

' SYSRUN-NEW     CONSTANT _sys-new-xt
' SYSRUN-FREE    CONSTANT _sys-free-xt
' SYSRUN-ADD     CONSTANT _sys-add-xt
' SYSRUN-ENABLE  CONSTANT _sys-enable-xt
' SYSRUN-DISABLE CONSTANT _sys-disable-xt
' SYSRUN-BIND    CONSTANT _sys-bind-xt

: SYSRUN-NEW     _sys-new-xt     _sys-guard WITH-GUARD ;
: SYSRUN-FREE    _sys-free-xt    _sys-guard WITH-GUARD ;
: SYSRUN-ADD     _sys-add-xt     _sys-guard WITH-GUARD ;
: SYSRUN-ENABLE  _sys-enable-xt  _sys-guard WITH-GUARD ;
: SYSRUN-DISABLE _sys-disable-xt _sys-guard WITH-GUARD ;
: SYSRUN-BIND    _sys-bind-xt    _sys-guard WITH-GUARD ;
[THEN] [THEN]
