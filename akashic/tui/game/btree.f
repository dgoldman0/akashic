\ =====================================================================
\  akashic/tui/game/btree.f — Behaviour Trees
\ =====================================================================
\
\  Composable behaviour tree nodes for NPC / entity AI.
\  Each node is a small heap-allocated descriptor that returns one of
\  three statuses when run: SUCCESS, FAILURE, or RUNNING.
\
\  Node types:
\    BT-NODE-ACTION    — leaf: calls xt ( eid ecs -- status )
\    BT-NODE-CONDITION — leaf: calls xt ( eid ecs -- flag ),
\                        returns SUCCESS if true, FAILURE if false
\    BT-NODE-SEQUENCE  — runs children L→R; fails on first failure
\    BT-NODE-SELECTOR  — runs children L→R; succeeds on first success
\    BT-NODE-PARALLEL  — runs all children; succeeds when threshold
\                        succeed, fails when too many fail
\    BT-NODE-INVERT   — decorator: flips SUCCESS ↔ FAILURE
\    BT-NODE-REPEAT   — decorator: repeats child n times (0=forever)
\    BT-NODE-COOLDOWN — decorator: runs child only once per N ticks
\
\  Node Descriptor (40 bytes, 5 cells):
\    +0   type        Node type constant
\    +8   data1       Type-specific (xt, children-addr, child, ...)
\    +16  data2       Type-specific (count, threshold, n, ...)
\    +24  data3       Type-specific (cooldown counter, ...)
\    +32  data4       Type-specific (repeat counter, ...)
\
\  Public API:
\    BT-ACTION    ( xt -- node )
\    BT-CONDITION ( xt -- node )
\    BT-SEQUENCE  ( children count -- node )
\    BT-SELECTOR  ( children count -- node )
\    BT-PARALLEL  ( children count threshold -- node )
\    BT-INVERT    ( child -- node )
\    BT-REPEAT    ( child n -- node )
\    BT-COOLDOWN  ( child ticks -- node )
\    BT-RUN       ( node eid ecs -- status )
\    BT-FREE      ( node -- )
\
\  Status constants:
\    BT-SUCCESS  BT-FAILURE  BT-RUNNING
\
\  Prefix: BT- (public), _BT- (internal)
\  Provider: akashic-tui-game-btree
\  Dependencies: (standalone)

PROVIDED akashic-tui-game-btree

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

\ Node descriptor offsets (40 bytes)
0  CONSTANT _BT-O-TYPE
8  CONSTANT _BT-O-D1
16 CONSTANT _BT-O-D2
24 CONSTANT _BT-O-D3
32 CONSTANT _BT-O-D4
40 CONSTANT _BT-NODE-SZ

\ =====================================================================
\  §2 — Node Allocation Helper
\ =====================================================================

: _BT-ALLOC  ( type -- node )
    _BT-NODE-SZ ALLOCATE
    0<> ABORT" BT: node alloc"
    DUP _BT-NODE-SZ 0 FILL
    SWAP OVER _BT-O-TYPE + ! ;

\ =====================================================================
\  §3 — Leaf Nodes
\ =====================================================================

\ BT-ACTION ( xt -- node )     xt: ( eid ecs -- status )
: BT-ACTION  ( xt -- node )
    BT-NODE-ACTION _BT-ALLOC
    SWAP OVER _BT-O-D1 + ! ;

\ BT-CONDITION ( xt -- node )  xt: ( eid ecs -- flag )
: BT-CONDITION  ( xt -- node )
    BT-NODE-CONDITION _BT-ALLOC
    SWAP OVER _BT-O-D1 + ! ;

\ =====================================================================
\  §4 — Composite Nodes
\ =====================================================================
\
\  Children are passed as an address of an array of node pointers.
\  The composite copies the array into its own allocation so the
\  caller's array (e.g. CREATE'd table) can be reused.

VARIABLE _BT-CC-ADDR
VARIABLE _BT-CC-CNT
VARIABLE _BT-CC-DST

\ Copy children array into freshly allocated buffer.
: _BT-COPY-CHILDREN  ( children count -- buf )
    _BT-CC-CNT ! _BT-CC-ADDR !
    _BT-CC-CNT @ 8 * ALLOCATE
    0<> ABORT" BT: children alloc"
    _BT-CC-DST !
    _BT-CC-ADDR @ _BT-CC-DST @ _BT-CC-CNT @ 8 * CMOVE
    _BT-CC-DST @ ;

\ BT-SEQUENCE ( children count -- node )
: BT-SEQUENCE  ( children count -- node )
    SWAP OVER _BT-COPY-CHILDREN       ( count buf )
    BT-NODE-SEQUENCE _BT-ALLOC        ( count buf node )
    SWAP OVER _BT-O-D1 + !            \ children buf
    SWAP OVER _BT-O-D2 + ! ;          \ count

\ BT-SELECTOR ( children count -- node )
: BT-SELECTOR  ( children count -- node )
    SWAP OVER _BT-COPY-CHILDREN       ( count buf )
    BT-NODE-SELECTOR _BT-ALLOC        ( count buf node )
    SWAP OVER _BT-O-D1 + !
    SWAP OVER _BT-O-D2 + ! ;

\ BT-PARALLEL ( children count threshold -- node )
\   Runs all children each tick.  Succeeds when >= threshold succeed,
\   fails when > (count-threshold) fail.
VARIABLE _BT-PAR-THR
: BT-PARALLEL  ( children count threshold -- node )
    _BT-PAR-THR !
    SWAP OVER _BT-COPY-CHILDREN       ( count buf )
    BT-NODE-PARALLEL _BT-ALLOC        ( count buf node )
    SWAP OVER _BT-O-D1 + !
    SWAP OVER _BT-O-D2 + !
    _BT-PAR-THR @ OVER _BT-O-D3 + ! ;

\ =====================================================================
\  §5 — Decorator Nodes
\ =====================================================================

\ BT-INVERT ( child -- node )
: BT-INVERT  ( child -- node )
    BT-NODE-INVERT _BT-ALLOC
    SWAP OVER _BT-O-D1 + ! ;

\ BT-REPEAT ( child n -- node )
\   Repeat child n times.  If n=0, repeat forever.
\   Returns SUCCESS after n completions, RUNNING while repeating.
: BT-REPEAT  ( child n -- node )
    BT-NODE-REPEAT _BT-ALLOC          ( child n node )
    SWAP OVER _BT-O-D2 + !            \ n (limit)
    SWAP OVER _BT-O-D1 + !            \ child
    0 OVER _BT-O-D3 + ! ;             \ counter = 0

\ BT-COOLDOWN ( child ticks -- node )
\   After child returns SUCCESS or FAILURE, skip child for `ticks`
\   ticks, returning the last result.  D3 = countdown, D4 = last result.
: BT-COOLDOWN  ( child ticks -- node )
    BT-NODE-COOLDOWN _BT-ALLOC        ( child ticks node )
    SWAP OVER _BT-O-D2 + !            \ ticks (cooldown period)
    SWAP OVER _BT-O-D1 + !            \ child
    0 OVER _BT-O-D3 + !               \ countdown = 0 (ready)
    BT-FAILURE OVER _BT-O-D4 + ! ;    \ last result

\ =====================================================================
\  §6 — Execution: BT-RUN
\ =====================================================================
\
\  Recursive dispatch by node type.  Uses VARIABLEs for local state
\  to avoid >R inside loops.

VARIABLE _BT-R-NODE
VARIABLE _BT-R-EID
VARIABLE _BT-R-ECS
VARIABLE _BT-R-TYPE
VARIABLE _BT-R-I
VARIABLE _BT-R-CNT
VARIABLE _BT-R-CHLDR
VARIABLE _BT-R-SUCC
VARIABLE _BT-R-FAIL
VARIABLE _BT-R-RESULT
VARIABLE _BT-R-SELF

: BT-RUN  ( node eid ecs -- status )
    _BT-R-ECS ! _BT-R-EID ! _BT-R-NODE !
    _BT-R-NODE @ _BT-O-TYPE + @ _BT-R-TYPE !

    \ --- ACTION ---
    _BT-R-TYPE @ BT-NODE-ACTION = IF
        _BT-R-EID @ _BT-R-ECS @
        _BT-R-NODE @ _BT-O-D1 + @ EXECUTE EXIT
    THEN

    \ --- CONDITION ---
    _BT-R-TYPE @ BT-NODE-CONDITION = IF
        _BT-R-EID @ _BT-R-ECS @
        _BT-R-NODE @ _BT-O-D1 + @ EXECUTE
        IF BT-SUCCESS ELSE BT-FAILURE THEN EXIT
    THEN

    \ --- SEQUENCE ---
    _BT-R-TYPE @ BT-NODE-SEQUENCE = IF
        _BT-R-NODE @ _BT-O-D1 + @ _BT-R-CHLDR !
        _BT-R-NODE @ _BT-O-D2 + @ _BT-R-CNT !
        0 _BT-R-I !
        BEGIN _BT-R-I @ _BT-R-CNT @ < WHILE
            _BT-R-CHLDR @ _BT-R-I @ 8 * + @
            _BT-R-EID @ _BT-R-ECS @ RECURSE
            DUP BT-SUCCESS <> IF EXIT THEN
            DROP
            1 _BT-R-I +!
        REPEAT
        BT-SUCCESS EXIT
    THEN

    \ --- SELECTOR ---
    _BT-R-TYPE @ BT-NODE-SELECTOR = IF
        _BT-R-NODE @ _BT-O-D1 + @ _BT-R-CHLDR !
        _BT-R-NODE @ _BT-O-D2 + @ _BT-R-CNT !
        0 _BT-R-I !
        BEGIN _BT-R-I @ _BT-R-CNT @ < WHILE
            _BT-R-CHLDR @ _BT-R-I @ 8 * + @
            _BT-R-EID @ _BT-R-ECS @ RECURSE
            DUP BT-FAILURE <> IF EXIT THEN
            DROP
            1 _BT-R-I +!
        REPEAT
        BT-FAILURE EXIT
    THEN

    \ --- PARALLEL ---
    _BT-R-TYPE @ BT-NODE-PARALLEL = IF
        _BT-R-NODE @ _BT-R-SELF !
        _BT-R-NODE @ _BT-O-D1 + @ _BT-R-CHLDR !
        _BT-R-NODE @ _BT-O-D2 + @ _BT-R-CNT !
        0 _BT-R-SUCC !  0 _BT-R-FAIL !
        0 _BT-R-I !
        BEGIN _BT-R-I @ _BT-R-CNT @ < WHILE
            _BT-R-CHLDR @ _BT-R-I @ 8 * + @
            _BT-R-EID @ _BT-R-ECS @ RECURSE
            DUP BT-SUCCESS = IF 1 _BT-R-SUCC +! THEN
            BT-FAILURE = IF 1 _BT-R-FAIL +! THEN
            1 _BT-R-I +!
        REPEAT
        _BT-R-SUCC @ _BT-R-SELF @ _BT-O-D3 + @ >= IF
            BT-SUCCESS EXIT
        THEN
        _BT-R-FAIL @ _BT-R-CNT @ _BT-R-SELF @ _BT-O-D3 + @ - > IF
            BT-FAILURE EXIT
        THEN
        BT-RUNNING EXIT
    THEN

    \ --- INVERT ---
    _BT-R-TYPE @ BT-NODE-INVERT = IF
        _BT-R-NODE @ _BT-O-D1 + @
        _BT-R-EID @ _BT-R-ECS @ RECURSE
        DUP BT-SUCCESS = IF DROP BT-FAILURE EXIT THEN
        DUP BT-FAILURE = IF DROP BT-SUCCESS EXIT THEN
        EXIT  \ RUNNING passes through
    THEN

    \ --- REPEAT ---
    _BT-R-TYPE @ BT-NODE-REPEAT = IF
        _BT-R-NODE @ _BT-R-SELF !
        _BT-R-SELF @ _BT-O-D1 + @
        _BT-R-EID @ _BT-R-ECS @ RECURSE
        DUP BT-SUCCESS = IF
            DROP
            _BT-R-SELF @ _BT-O-D3 + DUP @ 1+ SWAP !
            \ Check if limit reached
            _BT-R-SELF @ _BT-O-D2 + @ DUP 0= IF
                DROP BT-RUNNING EXIT   \ n=0 → infinite
            THEN
            _BT-R-SELF @ _BT-O-D3 + @ <= IF
                0 _BT-R-SELF @ _BT-O-D3 + !  \ reset counter
                BT-SUCCESS EXIT
            THEN
            BT-RUNNING EXIT
        THEN
        DUP BT-FAILURE = IF
            0 _BT-R-SELF @ _BT-O-D3 + !  \ reset counter on failure
        THEN
        EXIT  \ pass through FAILURE or RUNNING
    THEN

    \ --- COOLDOWN ---
    _BT-R-TYPE @ BT-NODE-COOLDOWN = IF
        _BT-R-NODE @ _BT-R-SELF !
        _BT-R-SELF @ _BT-O-D3 + @ 0> IF
            \ In cooldown period — decrement and return last result
            _BT-R-SELF @ _BT-O-D3 + DUP @ 1- SWAP !
            _BT-R-SELF @ _BT-O-D4 + @ EXIT
        THEN
        \ Run child
        _BT-R-SELF @ _BT-O-D1 + @
        _BT-R-EID @ _BT-R-ECS @ RECURSE
        DUP BT-RUNNING <> IF
            \ Start cooldown
            DUP _BT-R-SELF @ _BT-O-D4 + !   \ save result
            _BT-R-SELF @ _BT-O-D2 + @
            _BT-R-SELF @ _BT-O-D3 + !        \ set countdown
        THEN
        EXIT
    THEN

    \ Unknown type
    BT-FAILURE ;

\ =====================================================================
\  §7 — Destructor: BT-FREE
\ =====================================================================
\
\  Recursively free a node and all its children/child.

VARIABLE _BT-F-NODE
VARIABLE _BT-F-TYPE
VARIABLE _BT-F-I
VARIABLE _BT-F-CNT
VARIABLE _BT-F-CHLDR
VARIABLE _BT-F-SELF

: BT-FREE  ( node -- )
    _BT-F-NODE !
    _BT-F-NODE @ 0= IF EXIT THEN
    _BT-F-NODE @ _BT-O-TYPE + @ _BT-F-TYPE !

    \ Composite: free children array and each child node
    _BT-F-TYPE @ BT-NODE-SEQUENCE =
    _BT-F-TYPE @ BT-NODE-SELECTOR = OR
    _BT-F-TYPE @ BT-NODE-PARALLEL = OR IF
        _BT-F-NODE @ _BT-F-SELF !
        _BT-F-NODE @ _BT-O-D1 + @ _BT-F-CHLDR !
        _BT-F-NODE @ _BT-O-D2 + @ _BT-F-CNT !
        0 _BT-F-I !
        BEGIN _BT-F-I @ _BT-F-CNT @ < WHILE
            _BT-F-CHLDR @ _BT-F-I @ 8 * + @ RECURSE
            1 _BT-F-I +!
        REPEAT
        _BT-F-CHLDR @ FREE
        _BT-F-SELF @ FREE
        EXIT
    THEN

    \ Decorators: free child then self
    _BT-F-TYPE @ BT-NODE-INVERT =
    _BT-F-TYPE @ BT-NODE-REPEAT = OR
    _BT-F-TYPE @ BT-NODE-COOLDOWN = OR IF
        _BT-F-NODE @ _BT-F-SELF !
        _BT-F-NODE @ _BT-O-D1 + @ RECURSE
        _BT-F-SELF @ FREE
        EXIT
    THEN

    \ Leaf or unknown: just free self
    _BT-F-NODE @ FREE ;

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
