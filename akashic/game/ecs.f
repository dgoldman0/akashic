\ =====================================================================
\  akashic/game/ecs.f — Entity-Component Store
\ =====================================================================
\
\  Lightweight archetype-free ECS.  Entities are integer IDs (0-based)
\  with generation counters to detect stale references.  Components
\  are fixed-size byte arrays stored in parallel pools indexed by
\  entity ID.
\
\  The component table grows as components register, so an ECS holds
\  as many kinds of component as its creator registers.
\
\  ECS Descriptor (48 bytes, 6 cells):
\    +0   max-ents     Maximum entity slots
\    +8   alive        Bitfield array (1 bit per entity)
\    +16  gen          Generation array (1 cell per entity)
\    +24  comp-descs   Array of component descriptors
\    +32  num-comps    Number of registered components
\    +40  comp-cap     Descriptors the array has room for
\
\  Component Descriptor (24 bytes, 3 cells):
\    +0   comp-size    Byte size of one component instance
\    +8   data         Data array (max-ents × comp-size bytes), 0 for
\                      a component of size 0, which marks entities only
\    +16  attached     Bitfield array (1 bit per entity)
\
\  Public API:
\    ECS-NEW        ( max-ents -- ecs )
\    ECS-FREE       ( ecs -- )
\    ECS-REG-COMP   ( ecs size -- comp-id )
\    ECS-SPAWN      ( ecs -- eid )
\    ECS-KILL       ( ecs eid -- )
\    ECS-ALIVE?     ( ecs eid -- flag )
\    ECS-ATTACH     ( ecs eid comp-id -- addr )
\    ECS-DETACH     ( ecs eid comp-id -- )
\    ECS-GET        ( ecs eid comp-id -- addr | 0 )
\    ECS-HAS?       ( ecs eid comp-id -- flag )
\    ECS-EACH       ( ecs comp-id xt ctx -- )
\    ECS-EACH2      ( ecs c1 c2 xt ctx -- )
\    ECS-COUNT      ( ecs -- n )
\    ECS-GEN        ( ecs eid -- gen )
\    ECS-MAX        ( ecs -- max-ents )
\
\  Prefix: ECS- (public), _ECS- (internal)
\  Provider: akashic-game-ecs
\  Dependencies: (standalone)

PROVIDED akashic-game-ecs

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0  CONSTANT _ECS-O-MAX
8  CONSTANT _ECS-O-ALIVE
16 CONSTANT _ECS-O-GEN
24 CONSTANT _ECS-O-COMPS
32 CONSTANT _ECS-O-NCOMPS
40 CONSTANT _ECS-O-CCAP
48 CONSTANT _ECS-DESC-SZ

0  CONSTANT _ECS-CO-SIZE
8  CONSTANT _ECS-CO-DATA
16 CONSTANT _ECS-CO-ATTACHED
24 CONSTANT _ECS-COMP-SZ


\ =====================================================================
\  §2 — Bitfield helpers
\ =====================================================================
\  Bitfield: array of cells, bit N is in cell[N/64], position N MOD 64.

: _ECS-BF-BYTES  ( n -- bytes )
    63 + 64 / 8 * ;

: _ECS-BF-ALLOC  ( n -- addr )
    DUP _ECS-BF-BYTES ALLOCATE
    0<> ABORT" ECS: bitfield alloc"
    DUP ROT _ECS-BF-BYTES 0 FILL ;

: _ECS-BF-SET  ( bf bit -- )
    DUP 64 / 8 * ROT +               \ ( bit cell-addr )
    SWAP 63 AND
    1 SWAP LSHIFT
    OVER @ OR SWAP ! ;

: _ECS-BF-CLR  ( bf bit -- )
    DUP 64 / 8 * ROT +               \ ( bit cell-addr )
    SWAP 63 AND
    1 SWAP LSHIFT INVERT
    OVER @ AND SWAP ! ;

: _ECS-BF-TST  ( bf bit -- flag )
    DUP 64 / 8 * ROT +               \ ( bit cell-addr )
    SWAP 63 AND
    1 SWAP LSHIFT
    SWAP @ AND 0<> ;

\ =====================================================================
\  §3 — Constructor / Destructor
\ =====================================================================

: ECS-NEW  ( max-ents -- ecs )
    1 MAX >R
    _ECS-DESC-SZ ALLOCATE
    0<> ABORT" ECS-NEW: desc alloc"
    DUP _ECS-DESC-SZ 0 FILL
    R@ OVER _ECS-O-MAX + !
    R@ _ECS-BF-ALLOC OVER _ECS-O-ALIVE + !
    R@ 8 * ALLOCATE
    0<> ABORT" ECS-NEW: gen alloc"
    DUP R@ 8 * 0 FILL
    OVER _ECS-O-GEN + !
    8 _ECS-COMP-SZ * ALLOCATE
    0<> ABORT" ECS-NEW: comps alloc"
    OVER _ECS-O-COMPS + !
    8 OVER _ECS-O-CCAP + !
    R> DROP ;

: _ECS-FREE-COMP  ( comps-base i -- )
    _ECS-COMP-SZ * +
    DUP _ECS-CO-DATA + @ FREE
    _ECS-CO-ATTACHED + @ FREE ;

\ KDOS's FREE takes an address and returns nothing, and frees nothing
\ when given zero, so each FREE stands alone.
: ECS-FREE  ( ecs -- )
    DUP _ECS-O-NCOMPS + @ 0 ?DO
        DUP _ECS-O-COMPS + @ I _ECS-FREE-COMP
    LOOP
    DUP _ECS-O-COMPS + @ FREE
    DUP _ECS-O-GEN   + @ FREE
    DUP _ECS-O-ALIVE + @ FREE
    FREE ;

\ =====================================================================
\  §4 — Component Registration
\ =====================================================================

: _ECS-CDESC  ( ecs comp-id -- cdesc )
    _ECS-COMP-SZ * SWAP _ECS-O-COMPS + @ + ;

\ Double the component table's room.
: _ECS-GROW-COMPS  ( ecs -- )
    DUP _ECS-O-CCAP + @ 2*                        ( ecs cap )
    OVER _ECS-O-COMPS + @ OVER _ECS-COMP-SZ * RESIZE
    0<> ABORT" ECS: comps alloc"                  ( ecs cap comps )
    2 PICK _ECS-O-COMPS + !
    SWAP _ECS-O-CCAP + ! ;

\ ECS-REG-COMP ( ecs size -- comp-id )
\   A component of size bytes for every entity slot, zeroed; a size of
\   0 marks entities without data.
: ECS-REG-COMP  ( ecs size -- comp-id )
    0 MAX
    OVER DUP _ECS-O-NCOMPS + @ SWAP _ECS-O-CCAP + @ >= IF
        OVER _ECS-GROW-COMPS
    THEN
    OVER DUP _ECS-O-NCOMPS + @ _ECS-CDESC         ( ecs size cdesc )
    2DUP _ECS-CO-SIZE + !
    OVER 3 PICK _ECS-O-MAX + @ *                  ( ecs size cdesc bytes )
    ?DUP IF
        DUP ALLOCATE 0<> ABORT" ECS: comp data alloc"
        TUCK SWAP 0 FILL
    ELSE
        0
    THEN
    OVER _ECS-CO-DATA + !
    2 PICK _ECS-O-MAX + @ _ECS-BF-ALLOC SWAP _ECS-CO-ATTACHED + !
    DROP DUP _ECS-O-NCOMPS + @ SWAP _ECS-O-NCOMPS + 1 SWAP +! ;

\ =====================================================================
\  §5 — Entity Lifecycle
\ =====================================================================

: ECS-SPAWN  ( ecs -- eid )
    DUP _ECS-O-MAX + @ 0 ?DO
        DUP _ECS-O-ALIVE + @ I _ECS-BF-TST 0= IF
            DUP _ECS-O-ALIVE + @ I _ECS-BF-SET
            DUP _ECS-O-GEN + @ I 8 * +
            DUP @ 1+ SWAP !
            DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: ECS-KILL  ( ecs eid -- )
    2DUP SWAP _ECS-O-ALIVE + @ SWAP _ECS-BF-CLR
    OVER _ECS-O-NCOMPS + @ 0 ?DO
        OVER _ECS-O-COMPS + @
        I _ECS-COMP-SZ * + _ECS-CO-ATTACHED + @
        OVER _ECS-BF-CLR
    LOOP
    2DROP ;

: ECS-ALIVE?  ( ecs eid -- flag )
    SWAP _ECS-O-ALIVE + @ SWAP _ECS-BF-TST ;

\ =====================================================================
\  §6 — Component Access
\ =====================================================================

\ The address of entity eid's instance of a component
: _ECS-SLOT  ( cdesc eid -- addr )
    OVER _ECS-CO-SIZE + @ * SWAP _ECS-CO-DATA + @ + ;

\ ECS-ATTACH ( ecs eid comp-id -- addr )
\   A component attached anew starts zeroed, whatever an entity that
\   held the slot before left there; attaching one already attached
\   returns its data unchanged.
: ECS-ATTACH  ( ecs eid comp-id -- addr )
    ROT SWAP _ECS-CDESC                  \ ( eid cdesc )
    2DUP _ECS-CO-ATTACHED + @ SWAP _ECS-BF-TST IF
        SWAP _ECS-SLOT EXIT
    THEN
    2DUP _ECS-CO-ATTACHED + @ SWAP _ECS-BF-SET
    DUP _ECS-CO-SIZE + @ >R
    SWAP _ECS-SLOT DUP R> 0 FILL ;

: ECS-DETACH  ( ecs eid comp-id -- )
    ROT SWAP _ECS-CDESC
    _ECS-CO-ATTACHED + @ SWAP _ECS-BF-CLR ;

: ECS-GET  ( ecs eid comp-id -- addr | 0 )
    ROT SWAP _ECS-CDESC                  \ ( eid cdesc )
    2DUP _ECS-CO-ATTACHED + @ SWAP _ECS-BF-TST 0= IF
        2DROP 0 EXIT
    THEN
    SWAP _ECS-SLOT ;

: ECS-HAS?  ( ecs eid comp-id -- flag )
    ROT SWAP _ECS-CDESC
    _ECS-CO-ATTACHED + @ SWAP _ECS-BF-TST ;

\ =====================================================================
\  §7 — Iteration
\ =====================================================================
\
\  Each iteration keeps its ECS, descriptors, token and context on the
\  data stack, under the callback's arguments, so a callback may iterate
\  again, over the same ECS or another, and may kill the entity it was
\  given.  The context cell passes to every call unchanged, so callers
\  hand their state to the callback without a global.

\ ECS-EACH ( ecs comp-id xt ctx -- )
\   xt ( eid addr ctx -- ) runs for each live entity that has comp-id,
\   with addr its instance of the component.
: ECS-EACH  ( ecs comp-id each: xt( eid addr ctx -- ) ctx -- )
    2SWAP OVER SWAP _ECS-CDESC            \ ( xt ctx ecs cdesc )
    OVER _ECS-O-MAX + @ 0 ?DO
        OVER _ECS-O-ALIVE + @ I _ECS-BF-TST IF
        DUP _ECS-CO-ATTACHED + @ I _ECS-BF-TST IF
            DUP I _ECS-SLOT I SWAP 4 PICK 6 PICK EXECUTE
        THEN THEN
    LOOP
    2DROP 2DROP ;

\ ECS-EACH2 ( ecs c1 c2 xt ctx -- )
\   xt ( eid addr1 addr2 ctx -- ) runs for each live entity that has
\   both components, with addr1 its instance of c1 and addr2 of c2.
: ECS-EACH2  ( ecs c1 c2 each: xt( eid addr1 addr2 ctx -- ) ctx -- )
    2>R 2 PICK SWAP _ECS-CDESC SWAP 2 PICK SWAP _ECS-CDESC SWAP 2R>
    4 PICK _ECS-O-MAX + @ 0 ?DO           \ ( ecs cd1 cd2 xt ctx )
        4 PICK _ECS-O-ALIVE + @ I _ECS-BF-TST IF
        3 PICK _ECS-CO-ATTACHED + @ I _ECS-BF-TST IF
        2 PICK _ECS-CO-ATTACHED + @ I _ECS-BF-TST IF
            I 4 PICK I _ECS-SLOT 4 PICK I _ECS-SLOT 3 PICK 5 PICK EXECUTE
        THEN THEN THEN
    LOOP
    2DROP 2DROP DROP ;

\ =====================================================================
\  §8 — Queries
\ =====================================================================

: ECS-COUNT  ( ecs -- n )
    DUP _ECS-O-MAX + @ 0
    SWAP 0 ?DO
        OVER _ECS-O-ALIVE + @ I _ECS-BF-TST IF 1+ THEN
    LOOP
    NIP ;

: ECS-GEN  ( ecs eid -- gen )
    8 * SWAP _ECS-O-GEN + @ + @ ;

: ECS-MAX  ( ecs -- max-ents )
    _ECS-O-MAX + @ ;

\ =====================================================================
\  §9 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ecs-guard

' ECS-NEW       CONSTANT _ecs-new-xt
' ECS-FREE      CONSTANT _ecs-free-xt
' ECS-REG-COMP  CONSTANT _ecs-reg-comp-xt
' ECS-SPAWN     CONSTANT _ecs-spawn-xt
' ECS-KILL      CONSTANT _ecs-kill-xt
' ECS-ATTACH    CONSTANT _ecs-attach-xt
' ECS-DETACH    CONSTANT _ecs-detach-xt

: ECS-NEW       _ecs-new-xt       _ecs-guard WITH-GUARD ;
: ECS-FREE      _ecs-free-xt      _ecs-guard WITH-GUARD ;
: ECS-REG-COMP  _ecs-reg-comp-xt  _ecs-guard WITH-GUARD ;
: ECS-SPAWN     _ecs-spawn-xt     _ecs-guard WITH-GUARD ;
: ECS-KILL      _ecs-kill-xt      _ecs-guard WITH-GUARD ;
: ECS-ATTACH    _ecs-attach-xt    _ecs-guard WITH-GUARD ;
: ECS-DETACH    _ecs-detach-xt    _ecs-guard WITH-GUARD ;
[THEN] [THEN]
