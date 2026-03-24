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

0  CONSTANT _SR-E-XT
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
    DUP _SR-O-ENTRIES + @ FREE DROP
    FREE DROP ;

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

VARIABLE _SR-TICK-DT

: SYSRUN-TICK  ( runner dt -- )
    _SR-TICK-DT !                        \ ( runner )
    DUP _SR-O-COUNT + @ 0 ?DO
        DUP _SR-O-ENTRIES + @
        I _SR-ENTRY-SZ * +              \ ( runner entry )
        DUP _SR-E-ENABLED + @ IF
            DUP _SR-E-XT + @            \ ( runner entry xt )
            2 PICK _SR-O-ECS + @        \ ( runner entry xt ecs )
            _SR-TICK-DT @               \ ( runner entry xt ecs dt )
            ROT EXECUTE                  \ xt( ecs dt -- )
        THEN
        DROP                             \ ( runner )
    LOOP
    DROP ;

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

VARIABLE _SYS-DT

: _SYS-VEL-STEP  ( eid pos-addr vel-addr -- )
    \ x' = x + dx * dt
    OVER C-POS.X + @                     \ ( eid pos vel  x )
    OVER C-VEL.DX + @                   \ ( eid pos vel  x dx )
    _SYS-DT @ * +                        \ ( eid pos vel  x' )
    2 PICK C-POS.X + !                  \ ( eid pos vel )
    \ y' = y + dy * dt
    OVER C-POS.Y + @
    OVER C-VEL.DY + @
    _SYS-DT @ * +
    2 PICK C-POS.Y + !                  \ ( eid pos vel )
    DROP 2DROP ;

VARIABLE _SYS-VEL-XT
' _SYS-VEL-STEP _SYS-VEL-XT !

: SYS-VELOCITY  ( ecs dt -- )
    _SYS-DT !
    SYS-C-VEL @ SYS-C-POS @
    _SYS-VEL-XT @ ECS-EACH2 ;

\ =====================================================================
\  §8 — Built-in: SYS-TIMER
\ =====================================================================

: _SYS-TMR-STEP  ( eid tmr-addr -- )
    DUP C-TMR.TICKS + @ _SYS-DT @ -    \ ( eid tmr remaining )
    DUP 0> IF
        OVER C-TMR.TICKS + !            \ ( eid tmr )
        2DROP
    ELSE
        DROP                             \ ( eid tmr )
        0 OVER C-TMR.TICKS + !
        C-TMR.XT + @                    \ ( eid xt|0 )
        ?DUP IF EXECUTE ELSE DROP THEN
    THEN ;

VARIABLE _SYS-TMR-XT
' _SYS-TMR-STEP _SYS-TMR-XT !

: SYS-TIMER  ( ecs dt -- )
    _SYS-DT !
    SYS-C-TMR @
    _SYS-TMR-XT @ ECS-EACH ;

\ =====================================================================
\  §9 — Built-in: SYS-CULL-DEAD
\ =====================================================================

VARIABLE _SYS-CULL-ECS

: _SYS-CULL-STEP  ( eid hp-addr -- )
    C-HP.CUR + @ 0> 0= IF
        _SYS-CULL-ECS @ SWAP ECS-KILL
    ELSE
        DROP
    THEN ;

VARIABLE _SYS-CULL-XT
' _SYS-CULL-STEP _SYS-CULL-XT !

: SYS-CULL-DEAD  ( ecs dt -- )
    DROP
    DUP _SYS-CULL-ECS !
    SYS-C-HP @
    _SYS-CULL-XT @ ECS-EACH ;
