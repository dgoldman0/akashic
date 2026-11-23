\ =====================================================================
\  akashic/game/systems.f — System Runner
\ =====================================================================
\
\  A registry of update systems executed in priority order each tick.
\  Each system is an XT that receives ( ecs dt -- ) and operates on
\  the ECS.  Systems are sorted by priority (low runs first).
\
\  Runner Descriptor (32 bytes, 4 cells):
\    +0   ecs         ECS instance pointer
\    +8   entries     Array of system entries (max 16)
\    +16  count       Number of registered systems
\    +24  (reserved)
\
\  System Entry (24 bytes, 3 cells):
\    +0   xt          System execution token ( ecs dt -- )
\    +8   priority    Sort key (lower = earlier)
\    +16  enabled     Flag (0 = skip)
\
\  Public API:
\    SYSRUN-NEW     ( ecs -- runner )
\    SYSRUN-FREE    ( runner -- )
\    SYSRUN-ADD     ( runner xt priority -- )
\    SYSRUN-TICK    ( runner dt -- )
\    SYSRUN-ENABLE  ( runner idx -- )
\    SYSRUN-DISABLE ( runner idx -- )
\    SYSRUN-COUNT   ( runner -- n )
\
\  Built-in systems (all: ecs dt -- ):
\    SYS-VELOCITY   pos += vel * dt
\    SYS-TIMER      decrement timers, fire callbacks at zero
\    SYS-CULL-DEAD  kill entities with HP <= 0
\
\  Component binding:
\    SYS-C-POS SYS-C-VEL SYS-C-HP SYS-C-TMR  — variables
\    SYS-BIND-COMPS ( c-pos c-vel c-hp c-tmr -- )
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

0  CONSTANT _SR-O-ECS
8  CONSTANT _SR-O-ENTRIES
16 CONSTANT _SR-O-COUNT
32 CONSTANT _SR-DESC-SZ

0  CONSTANT _SR-E-XT  ( holds: xt( ecs dt -- ) )
8  CONSTANT _SR-E-PRI
16 CONSTANT _SR-E-ENABLED
24 CONSTANT _SR-ENTRY-SZ

16 CONSTANT _SR-MAX-SYS

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

: SYSRUN-NEW  ( ecs -- runner )
    _SR-DESC-SZ ALLOCATE
    0<> ABORT" SYSRUN-NEW: desc alloc"
    DUP _SR-DESC-SZ 0 FILL
    SWAP OVER _SR-O-ECS + !
    _SR-MAX-SYS _SR-ENTRY-SZ * ALLOCATE
    0<> ABORT" SYSRUN-NEW: entries alloc"
    DUP _SR-MAX-SYS _SR-ENTRY-SZ * 0 FILL
    OVER _SR-O-ENTRIES + ! ;

: SYSRUN-FREE  ( runner -- )
    DUP _SR-O-ENTRIES + @ FREE
    FREE ;

\ =====================================================================
\  §3 — Add System (insertion-sorted by priority)
\ =====================================================================

VARIABLE _SR-TMP

: SYSRUN-ADD  ( runner xt priority -- )
    ROT _SR-TMP !
    _SR-TMP @ _SR-O-COUNT + @ _SR-MAX-SYS >=
        ABORT" SYSRUN: max systems"
    \ Append at position [count]
    _SR-TMP @ _SR-O-COUNT + @
    _SR-ENTRY-SZ *
    _SR-TMP @ _SR-O-ENTRIES + @ +        \ ( xt pri entry )
    SWAP OVER _SR-E-PRI + !             \ store priority
    SWAP OVER _SR-E-XT  + !             \ store xt
    1 SWAP _SR-E-ENABLED + !            \ enabled = TRUE
    \ Increment count
    _SR-TMP @ _SR-O-COUNT +
    DUP @ 1+ SWAP !
    \ Bubble leftward to maintain sorted order
    _SR-TMP @ _SR-O-COUNT + @ 1-        \ ( last-idx )
    BEGIN
        DUP 0> WHILE
        DUP _SR-ENTRY-SZ *
        _SR-TMP @ _SR-O-ENTRIES + @ +   \ ( idx cur )
        DUP _SR-ENTRY-SZ -              \ ( idx cur prev )
        OVER _SR-E-PRI + @
        OVER _SR-E-PRI + @              \ ( idx cur prev  cur-pri prev-pri )
        < IF
            \ prev-pri > cur-pri — swap entries
            OVER _SR-E-XT + @
            OVER _SR-E-XT + @
            3 PICK _SR-E-XT + !
            OVER _SR-E-XT + !
            OVER _SR-E-PRI + @
            OVER _SR-E-PRI + @
            3 PICK _SR-E-PRI + !
            OVER _SR-E-PRI + !
            OVER _SR-E-ENABLED + @
            OVER _SR-E-ENABLED + @
            3 PICK _SR-E-ENABLED + !
            OVER _SR-E-ENABLED + !       \ ( idx cur prev )
            2DROP 1-
        ELSE
            2DROP DROP 0                 \ sorted — break
        THEN
    REPEAT
    DROP ;

\ =====================================================================
\  §4 — Tick
\ =====================================================================
\
\  The runner, the step and the loop stay on the stacks, so a system may
\  tick another runner.

: SYSRUN-TICK  ( runner dt -- )
    OVER _SR-O-COUNT + @ 0 ?DO
        OVER _SR-O-ENTRIES + @ I _SR-ENTRY-SZ * +   \ ( runner dt entry )
        DUP _SR-E-ENABLED + @ IF
            _SR-E-XT + @ 2 PICK _SR-O-ECS + @ 2 PICK ROT EXECUTE
        ELSE
            DROP
        THEN
    LOOP
    2DROP ;

\ =====================================================================
\  §5 — Enable / Disable / Count
\ =====================================================================

: SYSRUN-ENABLE  ( runner idx -- )
    _SR-ENTRY-SZ *
    SWAP _SR-O-ENTRIES + @ +
    1 SWAP _SR-E-ENABLED + ! ;

: SYSRUN-DISABLE  ( runner idx -- )
    _SR-ENTRY-SZ *
    SWAP _SR-O-ENTRIES + @ +
    0 SWAP _SR-E-ENABLED + ! ;

: SYSRUN-COUNT  ( runner -- n )
    _SR-O-COUNT + @ ;

\ =====================================================================
\  §6 — Component ID Variables & Binding
\ =====================================================================

VARIABLE SYS-C-POS
VARIABLE SYS-C-VEL
VARIABLE SYS-C-HP
VARIABLE SYS-C-TMR

: SYS-BIND-COMPS  ( c-pos c-vel c-hp c-tmr -- )
    SYS-C-TMR ! SYS-C-HP ! SYS-C-VEL ! SYS-C-POS ! ;

\ =====================================================================
\  §7 — Built-in: SYS-VELOCITY
\ =====================================================================
\
\  Each built-in system hands its step, or its ECS, to the per-entity
\  word as the iteration's context.

: _SYS-VEL-STEP  ( eid pos-addr vel-addr dt -- )
    >R
    DUP C-VEL.DX + @ R@ * 2 PICK C-POS.X + +!
    C-VEL.DY + @ R> * SWAP C-POS.Y + +!
    DROP ;

: SYS-VELOCITY  ( ecs dt -- )
    >R SYS-C-POS @ SYS-C-VEL @ ['] _SYS-VEL-STEP R> ECS-EACH2 ;

\ =====================================================================
\  §8 — Built-in: SYS-TIMER
\ =====================================================================

: _SYS-TMR-STEP  ( eid tmr-addr dt -- )
    OVER C-TMR.TICKS + @ SWAP -              \ ( eid tmr remaining )
    DUP 0> IF
        SWAP C-TMR.TICKS + ! DROP EXIT
    THEN
    DROP 0 OVER C-TMR.TICKS + !
    C-TMR.XT + @ ?DUP IF EXECUTE ELSE DROP THEN ;

: SYS-TIMER  ( ecs dt -- )
    >R SYS-C-TMR @ ['] _SYS-TMR-STEP R> ECS-EACH ;

\ =====================================================================
\  §9 — Built-in: SYS-CULL-DEAD
\ =====================================================================

: _SYS-CULL-STEP  ( eid hp-addr ecs -- )
    SWAP C-HP.CUR + @ 0> IF 2DROP EXIT THEN
    SWAP ECS-KILL ;

: SYS-CULL-DEAD  ( ecs dt -- )
    DROP DUP SYS-C-HP @ ['] _SYS-CULL-STEP ROT ECS-EACH ;

\ =====================================================================
\  §10 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _sys-guard

' SYSRUN-NEW     CONSTANT _sys-new-xt
' SYSRUN-FREE    CONSTANT _sys-free-xt
' SYSRUN-ADD     CONSTANT _sys-add-xt
' SYSRUN-ENABLE  CONSTANT _sys-enable-xt
' SYSRUN-DISABLE CONSTANT _sys-disable-xt
' SYS-BIND-COMPS CONSTANT _sys-bind-xt

: SYSRUN-NEW     _sys-new-xt     _sys-guard WITH-GUARD ;
: SYSRUN-FREE    _sys-free-xt    _sys-guard WITH-GUARD ;
: SYSRUN-ADD     _sys-add-xt     _sys-guard WITH-GUARD ;
: SYSRUN-ENABLE  _sys-enable-xt  _sys-guard WITH-GUARD ;
: SYSRUN-DISABLE _sys-disable-xt _sys-guard WITH-GUARD ;
: SYS-BIND-COMPS _sys-bind-xt    _sys-guard WITH-GUARD ;
[THEN] [THEN]
