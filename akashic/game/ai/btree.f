\ =====================================================================
\  akashic/game/ai/btree.f — Behaviour Trees
\ =====================================================================
\
\  Composable behaviour tree nodes for NPC / entity AI.
\  Each node is a small heap-allocated descriptor that returns one of
\  three statuses when run: SUCCESS, FAILURE, or RUNNING.
\
\  One tree serves any number of entities.  What a node remembers
\  between runs, a repeat's count of completions and a cooldown's
\  countdown and last result, lives in the entity's state block: a
\  block of BT-STATE-CELLS cells, zeroed before the entity's first
\  run.  Each subtree owns a fixed run of cells in the block, in the
\  order the nodes appear depth first, so a tree's size and every
\  node's place in the block are settled when the tree is built.  An
\  entity can keep its block in a component of that many cells, which
\  ECS-ATTACH zeroes.  A tree without repeats or cooldowns needs no
\  block, and runs with a state of 0.
\
\  BT-RUN keeps its loop state on the stacks, so composites nest to
\  any depth and an action may run another tree.  A node belongs to
\  one parent, since freeing the parent frees it.
\
\  Node types:
\    BT-NODE-ACTION    — leaf: calls xt ( eid ecs -- status )
\    BT-NODE-CONDITION — leaf: calls xt ( eid ecs -- flag ),
\                        returns SUCCESS if true, FAILURE if false
\    BT-NODE-SEQUENCE  — runs children L→R; the first status other
\                        than SUCCESS is its own, else SUCCESS
\    BT-NODE-SELECTOR  — runs children L→R; the first status other
\                        than FAILURE is its own, else FAILURE
\    BT-NODE-PARALLEL  — runs all children; succeeds when threshold
\                        succeed, fails when too many fail
\    BT-NODE-INVERT   — decorator: flips SUCCESS ↔ FAILURE
\    BT-NODE-REPEAT   — decorator: repeats child n times (0=forever)
\    BT-NODE-COOLDOWN — decorator: after the child finishes, returns
\                       its result for N runs without running it
\
\  Node Descriptor (40 bytes, 5 cells):
\    +0   type        Node type constant
\    +8   data1       xt (leaf), children array (composite), child
\    +16  data2       count (composite), n (repeat), ticks (cooldown)
\    +24  data3       threshold (parallel)
\    +32  cells       State cells of the subtree, its own and below
\
\  State cells a node owns, before its child's:
\    REPEAT    1   completions so far
\    COOLDOWN  2   runs left to skip, the result it returns meanwhile
\
\  Public API:
\    BT-ACTION       ( xt -- node )
\    BT-CONDITION    ( xt -- node )
\    BT-SEQUENCE     ( children count -- node )
\    BT-SELECTOR     ( children count -- node )
\    BT-PARALLEL     ( children count threshold -- node )
\    BT-INVERT       ( child -- node )
\    BT-REPEAT       ( child n -- node )
\    BT-COOLDOWN     ( child ticks -- node )
\    BT-STATE-CELLS  ( root -- n )
\    BT-RUN          ( node state eid ecs -- status )
\    BT-FREE         ( node -- )
\
\  Status constants:
\    BT-SUCCESS  BT-FAILURE  BT-RUNNING
\
\  Prefix: BT- (public), _BT- (internal)
\  Provider: akashic-game-ai-btree
\  Dependencies: (standalone)

PROVIDED akashic-game-ai-btree

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

\ Status values
0 CONSTANT BT-SUCCESS
1 CONSTANT BT-FAILURE
2 CONSTANT BT-RUNNING

\ Node types
0 CONSTANT BT-NODE-ACTION
1 CONSTANT BT-NODE-CONDITION
2 CONSTANT BT-NODE-SEQUENCE
3 CONSTANT BT-NODE-SELECTOR
4 CONSTANT BT-NODE-PARALLEL
5 CONSTANT BT-NODE-INVERT
6 CONSTANT BT-NODE-REPEAT
7 CONSTANT BT-NODE-COOLDOWN

( kind: bt-leaf xt( eid ecs -- result ) )

\ Node descriptor offsets (40 bytes)
0  CONSTANT _BT-O-TYPE
8  CONSTANT _BT-O-D1
8  CONSTANT _BT-O-LEAF  ( holds: bt-leaf )
16 CONSTANT _BT-O-D2
24 CONSTANT _BT-O-D3
32 CONSTANT _BT-O-CELLS
40 CONSTANT _BT-NODE-SZ

: _BT-COMPOSITE?  ( type -- flag )
    BT-NODE-SEQUENCE BT-NODE-INVERT WITHIN ;

: _BT-DECORATOR?  ( type -- flag )
    BT-NODE-INVERT BT-NODE-COOLDOWN 1+ WITHIN ;

\ =====================================================================
\  §2 — Node Allocation Helpers
\ =====================================================================

: _BT-ALLOC  ( type -- node )
    _BT-NODE-SZ ALLOCATE
    0<> ABORT" BT: node alloc"
    DUP _BT-NODE-SZ 0 FILL
    TUCK _BT-O-TYPE + ! ;

: _BT-CELLS  ( node -- n )
    _BT-O-CELLS + @ ;

\ Copy a children array into a block of the composite's own, so the
\ caller's array (e.g. a CREATE'd table) can be reused, and total the
\ children's state cells.  A composite of no children needs no block.
: _BT-COPY-CHILDREN  ( children count -- buf cells )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    DUP CELLS ALLOCATE
    0<> ABORT" BT: children alloc"           ( children count buf )
    2DUP 2>R SWAP CELLS CMOVE 2R>             ( count buf )
    0 ROT 0 ?DO                               ( buf cells )
        OVER I CELLS + @ _BT-CELLS +
    LOOP ;

\ =====================================================================
\  §3 — Leaf Nodes
\ =====================================================================

: BT-ACTION  ( xt -- node )
    BT-NODE-ACTION _BT-ALLOC
    TUCK _BT-O-LEAF + ! ;

: BT-CONDITION  ( xt -- node )
    BT-NODE-CONDITION _BT-ALLOC
    TUCK _BT-O-LEAF + ! ;

\ =====================================================================
\  §4 — Composite Nodes
\ =====================================================================
\
\  Children are passed as an address of an array of node pointers,
\  which the composite copies.

: _BT-COMPOSITE  ( children count type -- node )
    >R DUP >R _BT-COPY-CHILDREN R> R> _BT-ALLOC   ( buf cells count node )
    TUCK _BT-O-D2 + !
    TUCK _BT-O-CELLS + !
    TUCK _BT-O-D1 + ! ;

: BT-SEQUENCE  ( children count -- node )
    BT-NODE-SEQUENCE _BT-COMPOSITE ;

: BT-SELECTOR  ( children count -- node )
    BT-NODE-SELECTOR _BT-COMPOSITE ;

\ BT-PARALLEL ( children count threshold -- node )
\   Runs all children each tick.  Succeeds when >= threshold succeed,
\   fails when > (count-threshold) fail.
: BT-PARALLEL  ( children count threshold -- node )
    >R BT-NODE-PARALLEL _BT-COMPOSITE
    R> OVER _BT-O-D3 + ! ;

\ =====================================================================
\  §5 — Decorator Nodes
\ =====================================================================

\ A decorator over child, owning own state cells before the child's.
: _BT-DECORATOR  ( child arg own type -- node )
    _BT-ALLOC >R                              ( child arg own  R: node )
    2 PICK _BT-CELLS + R@ _BT-O-CELLS + !
    R@ _BT-O-D2 + !
    R@ _BT-O-D1 + !
    R> ;

: BT-INVERT  ( child -- node )
    0 0 BT-NODE-INVERT _BT-DECORATOR ;

\ BT-REPEAT ( child n -- node )
\   Repeat child n times.  If n=0, repeat forever.
\   Returns SUCCESS after n completions, RUNNING while repeating, and
\   FAILURE, starting the count again, when the child fails.
: BT-REPEAT  ( child n -- node )
    1 BT-NODE-REPEAT _BT-DECORATOR ;

\ BT-COOLDOWN ( child ticks -- node )
\   After the child returns SUCCESS or FAILURE, return that result for
\   the next `ticks` runs without running the child.
: BT-COOLDOWN  ( child ticks -- node )
    2 BT-NODE-COOLDOWN _BT-DECORATOR ;

\ BT-STATE-CELLS ( root -- n )
\   The cells of state one entity needs to run the tree.
: BT-STATE-CELLS  ( root -- n )
    _BT-CELLS ;

\ =====================================================================
\  §6 — Execution: BT-RUN
\ =====================================================================
\
\  Each node type has a runner ( node state eid ecs -- status ), where
\  state addresses the node's own run of cells in the entity's block.
\  Composites run their children through _BT-RUN, which BT-RUN fills
\  once it is defined, so the recursion stays on the stacks.

DEFER _BT-RUN  ( node state eid ecs -- status )

: _BT-RUN-ACTION  ( node state eid ecs -- status )
    2SWAP DROP _BT-O-LEAF + @ EXECUTE ;

: _BT-RUN-CONDITION  ( node state eid ecs -- status )
    2SWAP DROP _BT-O-LEAF + @ EXECUTE
    IF BT-SUCCESS ELSE BT-FAILURE THEN ;

\ _BT-RUN-SCAN ( node state eid ecs go -- status )
\   Run the children in order while each returns go; the first other
\   status is the composite's, and go is its status when all return go.
\   Each child's cells follow its elder siblings' in the block.
: _BT-RUN-SCAN  ( node state eid ecs go -- status )
    -ROT 2>R -ROT                             ( go node state  R: eid ecs )
    SWAP DUP _BT-O-D1 + @ SWAP _BT-O-D2 + @   ( go state children n )
    BEGIN DUP 0> WHILE
        OVER @ 3 PICK 2R@ _BT-RUN              ( go state children n status )
        DUP 5 PICK <> IF
            >R 2DROP 2DROP R> 2R> 2DROP EXIT
        THEN DROP
        1- >R DUP @ _BT-CELLS CELLS ROT + SWAP CELL+ R>
    REPEAT
    2DROP DROP 2R> 2DROP ;

: _BT-RUN-SEQUENCE  ( node state eid ecs -- status )
    BT-SUCCESS _BT-RUN-SCAN ;

: _BT-RUN-SELECTOR  ( node state eid ecs -- status )
    BT-FAILURE _BT-RUN-SCAN ;

\ _BT-RUN-PARALLEL ( node state eid ecs -- status )
\   Run every child, counting successes and failures, then judge.
: _BT-RUN-PARALLEL  ( node state eid ecs -- status )
    2>R OVER _BT-O-D1 + @ 2 PICK _BT-O-D2 + @ 0 0
    BEGIN 2 PICK 0> WHILE                     ( node state children n succ fail )
        3 PICK @ 5 PICK 2R@ _BT-RUN
        DUP BT-SUCCESS = IF
            DROP SWAP 1+ SWAP
        ELSE
            BT-FAILURE = IF 1+ THEN
        THEN
        2>R 1- >R DUP @ _BT-CELLS CELLS ROT + SWAP CELL+ R> 2R>
    REPEAT
    2R> 2DROP
    >R >R 2DROP DROP R> R>                    ( node succ fail )
    ROT DUP _BT-O-D3 + @ SWAP _BT-O-D2 + @ OVER -   ( succ fail thr allowed )
    >R ROT SWAP >= IF DROP R> DROP BT-SUCCESS EXIT THEN
    R> > IF BT-FAILURE ELSE BT-RUNNING THEN ;

: _BT-RUN-INVERT  ( node state eid ecs -- status )
    2>R SWAP _BT-O-D1 + @ SWAP 2R> _BT-RUN
    DUP BT-SUCCESS = IF DROP BT-FAILURE EXIT THEN
    DUP BT-FAILURE = IF DROP BT-SUCCESS THEN ;

\ _BT-RUN-REPEAT: the node's cell counts the child's successes.
: _BT-RUN-REPEAT  ( node state eid ecs -- status )
    2>R OVER _BT-O-D1 + @ OVER CELL+ 2R> _BT-RUN   ( node state status )
    DUP BT-SUCCESS = IF
        DROP SWAP _BT-O-D2 + @                    ( state n )
        DUP 0= IF 2DROP BT-RUNNING EXIT THEN
        OVER @ 1+ TUCK <= IF                      ( state done )
            DROP 0 SWAP ! BT-SUCCESS EXIT
        THEN
        SWAP ! BT-RUNNING EXIT
    THEN
    DUP BT-FAILURE = IF 0 2 PICK ! THEN
    NIP NIP ;

\ _BT-RUN-COOLDOWN: the node's cells hold the runs left to skip and the
\ result returned meanwhile.
: _BT-RUN-COOLDOWN  ( node state eid ecs -- status )
    2 PICK @ 0> IF
        2DROP NIP DUP @ 1- OVER ! CELL+ @ EXIT
    THEN
    2>R OVER _BT-O-D1 + @ OVER 2 CELLS + 2R> _BT-RUN   ( node state status )
    DUP BT-RUNNING = IF NIP NIP EXIT THEN
    DUP 2 PICK CELL+ !
    ROT _BT-O-D2 + @ ROT ! ;

: BT-RUN  ( node state eid ecs -- status )
    3 PICK _BT-O-TYPE + @
    CASE
        BT-NODE-ACTION    OF _BT-RUN-ACTION    ENDOF
        BT-NODE-CONDITION OF _BT-RUN-CONDITION ENDOF
        BT-NODE-SEQUENCE  OF _BT-RUN-SEQUENCE  ENDOF
        BT-NODE-SELECTOR  OF _BT-RUN-SELECTOR  ENDOF
        BT-NODE-PARALLEL  OF _BT-RUN-PARALLEL  ENDOF
        BT-NODE-INVERT    OF _BT-RUN-INVERT    ENDOF
        BT-NODE-REPEAT    OF _BT-RUN-REPEAT    ENDOF
        BT-NODE-COOLDOWN  OF _BT-RUN-COOLDOWN  ENDOF
        >R 2DROP 2DROP BT-FAILURE R>
    ENDCASE ;

' BT-RUN IS _BT-RUN

\ =====================================================================
\  §7 — Destructor: BT-FREE
\ =====================================================================
\
\  Free a node, its children array and every node below it, each once.

: BT-FREE  ( node -- )
    ?DUP 0= IF EXIT THEN
    DUP _BT-O-TYPE + @ DUP _BT-COMPOSITE? IF
        DROP DUP _BT-O-D1 + @ OVER _BT-O-D2 + @   ( node children n )
        0 ?DO DUP I CELLS + @ RECURSE LOOP
        FREE FREE EXIT
    THEN
    _BT-DECORATOR? IF DUP _BT-O-D1 + @ RECURSE THEN
    FREE ;

\ =====================================================================
\  §8 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _bt-guard

' BT-ACTION    CONSTANT _bt-action-xt
' BT-CONDITION CONSTANT _bt-cond-xt
' BT-SEQUENCE  CONSTANT _bt-seq-xt
' BT-SELECTOR  CONSTANT _bt-sel-xt
' BT-PARALLEL  CONSTANT _bt-par-xt
' BT-INVERT    CONSTANT _bt-inv-xt
' BT-REPEAT    CONSTANT _bt-rep-xt
' BT-COOLDOWN  CONSTANT _bt-cd-xt
' BT-RUN       CONSTANT _bt-run-xt
' BT-FREE      CONSTANT _bt-free-xt

: BT-ACTION    _bt-action-xt _bt-guard WITH-GUARD ;
: BT-CONDITION _bt-cond-xt   _bt-guard WITH-GUARD ;
: BT-SEQUENCE  _bt-seq-xt    _bt-guard WITH-GUARD ;
: BT-SELECTOR  _bt-sel-xt    _bt-guard WITH-GUARD ;
: BT-PARALLEL  _bt-par-xt    _bt-guard WITH-GUARD ;
: BT-INVERT    _bt-inv-xt    _bt-guard WITH-GUARD ;
: BT-REPEAT    _bt-rep-xt    _bt-guard WITH-GUARD ;
: BT-COOLDOWN  _bt-cd-xt     _bt-guard WITH-GUARD ;
: BT-RUN       _bt-run-xt    _bt-guard WITH-GUARD ;
: BT-FREE      _bt-free-xt   _bt-guard WITH-GUARD ;
[THEN] [THEN]
