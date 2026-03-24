\ =====================================================================
\  akashic/game/ecs.f — Entity-Component Store
\ =====================================================================
\
\  Lightweight archetype-free ECS.  Entities are integer IDs (0-based)
\  with generation counters to detect stale references.  Components
\  are fixed-size byte arrays stored in parallel pools indexed by
\  entity ID.
\
\  ECS Descriptor (40 bytes, 5 cells):
\    +0   max-ents     Maximum entity slots
\    +8   alive        Bitfield array (1 bit per entity)
\    +16  gen          Generation array (1 cell per entity)
\    +24  comp-descs   Array of component descriptors (up to 16)
\    +32  num-comps    Number of registered components
\
\  Component Descriptor (24 bytes, 3 cells):
\    +0   comp-size    Byte size of one component instance
\    +8   data         Data array (max-ents × comp-size bytes)
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
\    ECS-EACH       ( ecs comp-id xt -- )
\    ECS-EACH2      ( ecs c1 c2 xt -- )
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
40 CONSTANT _ECS-DESC-SZ

0  CONSTANT _ECS-CO-SIZE
8  CONSTANT _ECS-CO-DATA
16 CONSTANT _ECS-CO-ATTACHED
24 CONSTANT _ECS-COMP-SZ

16 CONSTANT _ECS-MAX-COMPS

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
    1 MAX DUP >R
    _ECS-DESC-SZ ALLOCATE
    0<> ABORT" ECS-NEW: desc alloc"
    DUP _ECS-DESC-SZ 0 FILL
    R@ OVER _ECS-O-MAX + !
    R@ _ECS-BF-ALLOC OVER _ECS-O-ALIVE + !
    R@ 8 * ALLOCATE
    0<> ABORT" ECS-NEW: gen alloc"
    DUP R@ 8 * 0 FILL
    OVER _ECS-O-GEN + !
    _ECS-MAX-COMPS _ECS-COMP-SZ * ALLOCATE
    0<> ABORT" ECS-NEW: comps alloc"
    DUP _ECS-MAX-COMPS _ECS-COMP-SZ * 0 FILL
    OVER _ECS-O-COMPS + !
    0 OVER _ECS-O-NCOMPS + !
    R> DROP ;

: _ECS-FREE-COMP  ( comps-base i -- )
    _ECS-COMP-SZ * +
    DUP _ECS-CO-DATA + @ ?DUP IF FREE DROP THEN
    _ECS-CO-ATTACHED + @ ?DUP IF FREE DROP THEN ;

: ECS-FREE  ( ecs -- )
    DUP _ECS-O-NCOMPS + @ 0 ?DO
        DUP _ECS-O-COMPS + @ I _ECS-FREE-COMP
    LOOP
    DUP _ECS-O-COMPS + @ FREE DROP
    DUP _ECS-O-GEN   + @ FREE DROP
    DUP _ECS-O-ALIVE + @ FREE DROP
    FREE DROP ;

\ =====================================================================
\  §4 — Component Registration
\ =====================================================================

VARIABLE _ECS-REG-TMP

: ECS-REG-COMP  ( ecs size -- comp-id )
    OVER _ECS-O-NCOMPS + @ _ECS-MAX-COMPS >= ABORT" ECS: max comps"
    OVER _ECS-REG-TMP !
    OVER _ECS-O-NCOMPS + @ >R
    _ECS-REG-TMP @ _ECS-O-COMPS + @
    R@ _ECS-COMP-SZ * +                  \ ( ecs size cdesc )
    ROT DROP                             \ ( size cdesc )
    2DUP _ECS-CO-SIZE + !
    _ECS-REG-TMP @ _ECS-O-MAX + @
    2 PICK *
    ALLOCATE
    0<> ABORT" ECS: comp data alloc"
    DUP _ECS-REG-TMP @ _ECS-O-MAX + @ 4 PICK * 0 FILL
    OVER _ECS-CO-DATA + !
    _ECS-REG-TMP @ _ECS-O-MAX + @
    _ECS-BF-ALLOC
    SWAP _ECS-CO-ATTACHED + !
    DROP
    _ECS-REG-TMP @ _ECS-O-NCOMPS +
    DUP @ 1+ SWAP !
    R> ;

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

: _ECS-CDESC  ( ecs comp-id -- cdesc )
    _ECS-COMP-SZ * SWAP _ECS-O-COMPS + @ + ;

: ECS-ATTACH  ( ecs eid comp-id -- addr )
    ROT >R
    R@ SWAP _ECS-CDESC                   \ ( eid cdesc )
    2DUP _ECS-CO-ATTACHED + @ SWAP _ECS-BF-SET
    SWAP                                 \ ( cdesc eid )
    OVER _ECS-CO-SIZE + @ *              \ ( cdesc offset )
    SWAP _ECS-CO-DATA + @ +
    R> DROP ;

: ECS-DETACH  ( ecs eid comp-id -- )
    ROT SWAP _ECS-CDESC
    _ECS-CO-ATTACHED + @ SWAP _ECS-BF-CLR ;

: ECS-GET  ( ecs eid comp-id -- addr | 0 )
    ROT >R
    R@ SWAP _ECS-CDESC                   \ ( eid cdesc )
    2DUP _ECS-CO-ATTACHED + @ SWAP _ECS-BF-TST 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP
    OVER _ECS-CO-SIZE + @ *
    SWAP _ECS-CO-DATA + @ +
    R> DROP ;

: ECS-HAS?  ( ecs eid comp-id -- flag )
    ROT SWAP _ECS-CDESC
    _ECS-CO-ATTACHED + @ SWAP _ECS-BF-TST ;

\ =====================================================================
\  §7 — Iteration
\ =====================================================================

VARIABLE _ECS-IT-ECS
VARIABLE _ECS-IT-XT
VARIABLE _ECS-IT-CD2

: ECS-EACH  ( ecs comp-id xt -- )
    _ECS-IT-XT !
    OVER _ECS-IT-ECS !
    _ECS-IT-ECS @ SWAP _ECS-CDESC
    _ECS-IT-ECS @ _ECS-O-MAX + @ 0 ?DO
        _ECS-IT-ECS @ _ECS-O-ALIVE + @ I _ECS-BF-TST IF
            DUP _ECS-CO-ATTACHED + @ I _ECS-BF-TST IF
                I
                OVER _ECS-CO-DATA + @
                2 PICK _ECS-CO-SIZE + @ I * +
                _ECS-IT-XT @ EXECUTE
            THEN
        THEN
    LOOP
    2DROP ;

: ECS-EACH2  ( ecs c1 c2 xt -- )
    _ECS-IT-XT !
    OVER >R
    ROT DUP _ECS-IT-ECS !
    R> _ECS-CDESC _ECS-IT-CD2 !
    _ECS-IT-ECS @ SWAP _ECS-CDESC
    _ECS-IT-ECS @ _ECS-O-MAX + @ 0 ?DO
        _ECS-IT-ECS @ _ECS-O-ALIVE + @ I _ECS-BF-TST IF
            DUP _ECS-CO-ATTACHED + @ I _ECS-BF-TST IF
                _ECS-IT-CD2 @ _ECS-CO-ATTACHED + @ I _ECS-BF-TST IF
                    I
                    OVER _ECS-CO-DATA + @
                    2 PICK _ECS-CO-SIZE + @ I * +
                    _ECS-IT-CD2 @ _ECS-CO-DATA + @
                    I _ECS-IT-CD2 @ _ECS-CO-SIZE + @ * +
                    _ECS-IT-XT @ EXECUTE
                THEN
            THEN
        THEN
    LOOP
    2DROP ;

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
