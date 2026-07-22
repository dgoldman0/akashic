\ RAM-VFS contracts for the neutral immutable ordered index.

PROVIDED akashic-persistence-btree-contracts

VARIABLE _PBTC-fails
VARIABLE _PBTC-checks
VARIABLE _PBTC-depth
VARIABLE _PBTC-phase
VARIABLE _PBTC-arena
VARIABLE _PBTC-vfs
VARIABLE _PBTC-ior
VARIABLE _PBTC-old-vfs
VARIABLE _PBTC-page-id
VARIABLE _PBTC-old-height
VARIABLE _PBTC-old-generation
VARIABLE _PBTC-expect-key
VARIABLE _PBTC-expect-value
VARIABLE _PBTC-result-ok
VARIABLE _PBTC-value-bias
VARIABLE _PBTC-max-height
VARIABLE _PBTC-n
VARIABLE _PBTC-max-retired
VARIABLE _PBTC-fault-at
VARIABLE _PBTC-allocator-mode
VARIABLE _PBTC-allocator-calls
VARIABLE _PBTC-allocator-last
VARIABLE _PBTC-reentry-status
VARIABLE _PBTC-callback-store
VARIABLE _PBTC-callback-work
VARIABLE _PBTC-target-store
VARIABLE _PBTC-target-work
VARIABLE _PBTC-put-key
VARIABLE _PBTC-put-value
VARIABLE _PBTC-rng
VARIABLE _PBTC-trace-limit
VARIABLE _PBTC-trace-rounds
VARIABLE _PBTC-trace-value-base
VARIABLE _PBTC-trace-key
VARIABLE _PBTC-trace-update-key

96 CONSTANT _PBTC-ORACLE-LIMIT
CREATE _PBTC-oracle-present _PBTC-ORACLE-LIMIT ALLOT
CREATE _PBTC-oracle-values _PBTC-ORACLE-LIMIT CELLS ALLOT

CREATE _PBTC-ops VFS-OPS-SIZE ALLOT
CREATE _PBTC-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _PBTC-store PSTORE-SIZE ALLOT
CREATE _PBTC-pstore-work PSTORE-WORK-SIZE ALLOT
CREATE _PBTC-record-buffer 512 ALLOT
GUARD _PBTC-guard
CREATE _PBTC-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _PBTC-tree PBTREE-SIZE ALLOT
CREATE _PBTC-work PBTREE-WORK-SIZE ALLOT
CREATE _PBTC-root-a PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-root-b PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-root-c PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-cursor PBTREE-CURSOR-SIZE ALLOT
CREATE _PBTC-app-page PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _PBTC-key 2 ALLOT
CREATE _PBTC-value 8 ALLOT

CREATE _PBTC-reopen-store PSTORE-SIZE ALLOT
CREATE _PBTC-reopen-pstore-work PSTORE-WORK-SIZE ALLOT
CREATE _PBTC-reopen-record-buffer 512 ALLOT
CREATE _PBTC-reopen-tree PBTREE-SIZE ALLOT
CREATE _PBTC-reopen-work PBTREE-WORK-SIZE ALLOT
CREATE _PBTC-reopen-root PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-reopen-cursor PBTREE-CURSOR-SIZE ALLOT
GUARD _PBTC-reopen-guard
CREATE _PBTC-fault-tree PBTREE-SIZE ALLOT
CREATE _PBTC-root-snapshot PBTREE-ROOT-SIZE ALLOT

CREATE _PBTC-i0-store PSTORE-SIZE ALLOT
CREATE _PBTC-i1-store PSTORE-SIZE ALLOT
CREATE _PBTC-i2-store PSTORE-SIZE ALLOT
CREATE _PBTC-i3-store PSTORE-SIZE ALLOT
CREATE _PBTC-i0-pwork PSTORE-WORK-SIZE ALLOT
CREATE _PBTC-i1-pwork PSTORE-WORK-SIZE ALLOT
CREATE _PBTC-i2-pwork PSTORE-WORK-SIZE ALLOT
CREATE _PBTC-i3-pwork PSTORE-WORK-SIZE ALLOT
CREATE _PBTC-i0-record 512 ALLOT
CREATE _PBTC-i1-record 512 ALLOT
CREATE _PBTC-i2-record 512 ALLOT
CREATE _PBTC-i3-record 512 ALLOT
CREATE _PBTC-i0-tree PBTREE-SIZE ALLOT
CREATE _PBTC-i1-tree PBTREE-SIZE ALLOT
CREATE _PBTC-i2-tree PBTREE-SIZE ALLOT
CREATE _PBTC-i3-tree PBTREE-SIZE ALLOT
CREATE _PBTC-i0-work PBTREE-WORK-SIZE ALLOT
CREATE _PBTC-i1-work PBTREE-WORK-SIZE ALLOT
CREATE _PBTC-i2-work PBTREE-WORK-SIZE ALLOT
CREATE _PBTC-i3-work PBTREE-WORK-SIZE ALLOT
CREATE _PBTC-i0-root-a PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-i1-root-a PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-i2-root-a PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-i3-root-a PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-i0-root-b PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-i1-root-b PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-i2-root-b PBTREE-ROOT-SIZE ALLOT
CREATE _PBTC-i3-root-b PBTREE-ROOT-SIZE ALLOT
GUARD _PBTC-i0-guard
GUARD _PBTC-i1-guard
GUARD _PBTC-i2-guard
GUARD _PBTC-i3-guard

: _PBTC-assert  ( flag -- )
    1 _PBTC-checks +!
    0= IF
        1 _PBTC-fails +! ." PERSISTENCE BTREE ASSERT/PHASE "
        _PBTC-checks @ . _PBTC-phase @ . CR
    THEN ;

: _PBTC-stack  ( -- )
    DEPTH DUP _PBTC-depth @ <> IF
        ." PERSISTENCE BTREE STACK/PHASE " _PBTC-depth @ . ." -> " DUP .
        _PBTC-phase @ . CR
    THEN
    _PBTC-depth @ = _PBTC-assert ;

: _PBTC-status  ( actual expected -- )
    2DUP <> IF ." PERSISTENCE BTREE STATUS actual/expected " 2DUP . . CR THEN
    = _PBTC-assert _PBTC-stack ;

: _PBTC-store-fault  ( point ordinal context -- status )
    2DROP _PBTC-fault-at @ = IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN ;

: _PBTC-store-init  ( -- status )
    S" /pbt-pages" S" /pbt-segment" S" /pbt-root-a" S" /pbt-root-b"
    _PBTC-identity 256 _PBTC-vfs @ 0 0 _PBTC-guard
    ['] _PBTC-store-fault 0 _PBTC-store PSTORE-INIT ;

: _PBTC-setup  ( -- )
    VFS-CUR _PBTC-old-vfs !
    VFS-RAM-OPS _PBTC-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _PBTC-binding VFS-BINDING-DESC-SIZE MOVE
    _PBTC-ops _PBTC-binding VB.OPS !
    33554432 A-XMEM ARENA-NEW DUP 0= _PBTC-assert DROP _PBTC-arena !
    _PBTC-arena @ _PBTC-binding 0 VFS-NEW _PBTC-ior ! _PBTC-vfs !
    _PBTC-ior @ 0= _PBTC-assert
    _PBTC-identity PERSIST-IDENTITY-SIZE 71 FILL
    _PBTC-store-init PERSIST-S-OK _PBTC-status
    _PBTC-record-buffer 512 _PBTC-pstore-work PSTORE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-store _PBTC-pstore-work PSTORE-PROVISION PERSIST-S-OK _PBTC-status
    _PBTC-store _PBTC-pstore-work PSTORE-OPEN PERSIST-S-ABSENT _PBTC-status
    101 ['] PBTREE-HIGH-WATER-ALLOCATE 0 _PBTC-store _PBTC-tree
        PBTREE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-pstore-work _PBTC-work PBTREE-WORK-INIT PERSIST-S-OK _PBTC-status
    _PBTC-tree _PBTC-root-a PBTREE-ROOT-INIT PERSIST-S-OK _PBTC-status ;

: _PBTC-stage-root  ( root -- )
    _PBTC-app-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBTC-app-page PBTREE-ROOT-SIZE MOVE
    _PBTC-app-page PERSIST-PAGE-PAYLOAD-SIZE
        _PBTC-store _PBTC-pstore-work PSTORE-APPEND-PAGE
    SWAP _PBTC-page-id ! PERSIST-S-OK _PBTC-status
    _PBTC-page-id @ _PBTC-store _PBTC-pstore-work PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PBTC-status ;

: _PBTC-first  ( -- )
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    S" alpha" S" one" _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work
        PBTREE-PUT PERSIST-S-OK _PBTC-status
    _PBTC-root-b PBTREE-ROOT-CARDINALITY@ 1 = _PBTC-assert
    _PBTC-root-b PBTREE-ROOT-HEIGHT@ 1 = _PBTC-assert
    _PBTC-root-b _PBTC-stage-root
    _PBTC-store _PBTC-pstore-work PSTORE-COMMIT PERSIST-S-OK _PBTC-status
    S" alpha" _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-GET
    PERSIST-S-OK = >R
    S" one" COMPARE 0= R> AND _PBTC-assert _PBTC-stack ;

: _PBTC-alpha-row  ( key-a key-u value-a value-u status -- )
    PERSIST-S-OK = >R
    S" one" COMPARE 0= >R
    S" alpha" COMPARE 0=
    R> AND R> AND _PBTC-assert _PBTC-stack ;

: _PBTC-no-row  ( key-a key-u value-a value-u status expected -- )
    2DUP <> IF ." CURSOR NO-ROW STATUS actual/expected " 2DUP . . CR THEN
    = >R 2DROP 2DROP R> _PBTC-assert _PBTC-stack ;

: _PBTC-cursor-one  ( -- )
    _PBTC-root-b _PBTC-tree _PBTC-cursor PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-root-b _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
        _PBTC-alpha-row
    _PBTC-cursor PBTREE-CURSOR-VALID? _PBTC-assert _PBTC-stack
    _PBTC-root-b _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
        PERSIST-S-NOT-FOUND _PBTC-no-row
    S" alpha" _PBTC-root-b _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-SEEK
        _PBTC-alpha-row
    S" alpha" _PBTC-root-b _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-RESUME
        PERSIST-S-NOT-FOUND _PBTC-no-row ;

: _PBTC-key!  ( n -- key-a key-u )
    DUP 8 RSHIFT _PBTC-key C!
    255 AND _PBTC-key 1+ C!
    _PBTC-key 2 ;

: _PBTC-key@  ( key-a -- n )
    DUP C@ 8 LSHIFT SWAP 1+ C@ OR ;

: _PBTC-value!  ( n -- value-a value-u )
    _PBTC-value-bias @ + _PBTC-value ! _PBTC-value 8 ;

: _PBTC-test-allocator  ( context store pstore-work -- page-id status )
    _PBTC-callback-work ! _PBTC-callback-store ! DROP
    1 _PBTC-allocator-calls +!
    _PBTC-allocator-mode @ 1 = IF -911 THROW THEN
    _PBTC-allocator-mode @ 2 = IF -1 PERSIST-S-FAULT EXIT THEN
    _PBTC-allocator-mode @ 3 = IF
        _PBTC-allocator-calls @ 1 = IF
            0 _PBTC-callback-store @ _PBTC-callback-work @
                PBTREE-HIGH-WATER-ALLOCATE
            OVER _PBTC-allocator-last ! EXIT
        THEN
        _PBTC-allocator-last @ PERSIST-S-OK EXIT
    THEN
    _PBTC-allocator-mode @ 4 = IF
        _PBTC-callback-work @ PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 1+
        PERSIST-S-OK EXIT
    THEN
    _PBTC-allocator-mode @ 5 = IF
        89 _PBTC-key! _PBTC-root-a _PBTC-fault-tree _PBTC-work PBTREE-GET
        _PBTC-reentry-status ! 2DROP
        -1 PERSIST-S-FAULT EXIT
    THEN
    _PBTC-allocator-mode @ 6 = IF -1 PERSIST-S-CAPACITY EXIT THEN
    0 _PBTC-callback-store @ _PBTC-callback-work @
        PBTREE-HIGH-WATER-ALLOCATE ;

: _PBTC-finish-root-b  ( -- )
    _PBTC-root-b _PBTC-stage-root
    _PBTC-store _PBTC-pstore-work PSTORE-COMMIT PERSIST-S-OK _PBTC-status
    _PBTC-root-b _PBTC-root-a PBTREE-ROOT-COPY PERSIST-S-OK _PBTC-status ;

: _PBTC-retired-bounded  ( -- )
    _PBTC-work PBTREE-RETIRED-PAGES$ NIP
    DUP PBTREE-RETIREMENT-MAX <= _PBTC-assert
    _PBTC-old-height @ >= _PBTC-assert _PBTC-stack ;

: _PBTC-put-n  ( n -- )
    _PBTC-n !
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ _PBTC-old-height !
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-n @ DUP _PBTC-key! ROT _PBTC-value!
    _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-PUT
        PERSIST-S-OK _PBTC-status
    _PBTC-retired-bounded
    _PBTC-finish-root-b ;

: _PBTC-value-result  ( expected value-a value-u status -- )
    PERSIST-S-OK = _PBTC-result-ok !
    DUP 8 = _PBTC-result-ok @ AND _PBTC-result-ok !
    1 PICK @ 3 PICK = _PBTC-result-ok @ AND _PBTC-result-ok !
    2DROP DROP
    _PBTC-result-ok @ _PBTC-assert _PBTC-stack ;

: _PBTC-no-value  ( value-a value-u status expected -- )
    = >R 2DROP R> _PBTC-assert _PBTC-stack ;

: _PBTC-get-n  ( n expected-value -- )
    SWAP _PBTC-key!
    _PBTC-root-a _PBTC-tree _PBTC-work PBTREE-GET
    _PBTC-value-result ;

: _PBTC-number-row
  ( expected-key expected-value key-a key-u value-a value-u status -- )
    6 PICK _PBTC-expect-key !
    5 PICK _PBTC-expect-value !
    PERSIST-S-OK = _PBTC-result-ok !
    DUP 8 = _PBTC-result-ok @ AND _PBTC-result-ok !
    1 PICK @ _PBTC-expect-value @ =
        _PBTC-result-ok @ AND _PBTC-result-ok !
    2 PICK 2 = _PBTC-result-ok @ AND _PBTC-result-ok !
    3 PICK _PBTC-key@ _PBTC-expect-key @ =
        _PBTC-result-ok @ AND _PBTC-result-ok !
    2DROP 2DROP 2DROP
    _PBTC-result-ok @ _PBTC-assert _PBTC-stack ;

: _PBTC-oracle-present-a  ( n -- a )
    _PBTC-oracle-present + ;

: _PBTC-oracle-value-a  ( n -- a )
    CELLS _PBTC-oracle-values + ;

: _PBTC-oracle-clear  ( -- )
    _PBTC-oracle-present _PBTC-ORACLE-LIMIT 0 FILL
    _PBTC-oracle-values _PBTC-ORACLE-LIMIT CELLS 0 FILL ;

: _PBTC-oracle-present?  ( n -- flag )
    _PBTC-oracle-present-a C@ 0<> ;

: _PBTC-oracle-value@  ( n -- value )
    _PBTC-oracle-value-a @ ;

: _PBTC-oracle-put  ( n value -- )
    >R
    DUP _PBTC-oracle-present-a 1 SWAP C!
    _PBTC-oracle-value-a R> SWAP ! ;

: _PBTC-oracle-delete  ( n -- )
    DUP _PBTC-oracle-present-a 0 SWAP C!
    _PBTC-oracle-value-a 0 SWAP ! ;

: _PBTC-oracle-count  ( -- u )
    0
    _PBTC-ORACLE-LIMIT 0 DO
        I _PBTC-oracle-present? IF 1+ THEN
    LOOP ;

: _PBTC-oracle-default-prefix  ( limit value-bias -- )
    _PBTC-oracle-clear
    SWAP 0 DO
        I DUP 2 PICK + _PBTC-oracle-put
    LOOP
    DROP ;

: _PBTC-oracle-cardinality  ( -- )
    _PBTC-root-a PBTREE-ROOT-CARDINALITY@ _PBTC-oracle-count =
        _PBTC-assert _PBTC-stack ;

: _PBTC-check-key  ( n -- )
    DUP _PBTC-oracle-present? IF
        DUP _PBTC-oracle-value@ _PBTC-get-n
    ELSE
        _PBTC-key!
        _PBTC-root-a _PBTC-tree _PBTC-work PBTREE-GET
            PERSIST-S-NOT-FOUND _PBTC-no-value
    THEN ;

: _PBTC-oracle-scan  ( limit -- )
    _PBTC-n !
    _PBTC-root-a _PBTC-tree _PBTC-cursor PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-n @ 0 DO
        I _PBTC-oracle-present? IF
            I I _PBTC-oracle-value@
            _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
                _PBTC-number-row
        THEN
    LOOP
    _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
        PERSIST-S-NOT-FOUND _PBTC-no-row ;

: _PBTC-rng-reset  ( seed -- )
    PERSIST-MAX-SIGNED AND DUP 0= IF DROP 1 THEN _PBTC-rng ! ;

: _PBTC-rng-next  ( -- u )
    _PBTC-rng @ 1103515245 * 12345 + PERSIST-MAX-SIGNED AND
    DUP _PBTC-rng ! ;

: _PBTC-put-counters  ( -- )
    \ Descent reads h pages; child writes invalidate the one-page cache, so
    \ unwinding can reread each of the h-1 ancestors once.
    _PBTC-tree PBTREE-PAGE-READS@ DUP 0> _PBTC-assert
    _PBTC-old-height @ 2 * 1- <= _PBTC-assert
    _PBTC-tree PBTREE-PAGE-WRITES@ DUP 0> _PBTC-assert
    _PBTC-old-height @ 2 * 1+ <= _PBTC-assert
    _PBTC-tree PBTREE-COMPARISONS@ 0> _PBTC-assert
    _PBTC-tree PBTREE-WORKING-BYTES@ PBTREE-WORK-SIZE =
        _PBTC-assert _PBTC-stack ;

: _PBTC-delete-counters  ( -- )
    \ In addition to descent and unwind, an underfull path can read one
    \ sibling and reread its parent after rewriting children at every level.
    _PBTC-tree PBTREE-PAGE-READS@ DUP 0> _PBTC-assert
    _PBTC-old-height @ 4 * 3 - <= _PBTC-assert
    _PBTC-tree PBTREE-PAGE-WRITES@ DUP 0> _PBTC-assert
    _PBTC-old-height @ 2 * 1- <= _PBTC-assert
    _PBTC-tree PBTREE-COMPARISONS@ 0> _PBTC-assert
    _PBTC-tree PBTREE-WORKING-BYTES@ PBTREE-WORK-SIZE =
        _PBTC-assert _PBTC-stack ;

: _PBTC-put-exact  ( n value -- )
    _PBTC-put-value ! _PBTC-put-key !
    _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ _PBTC-old-height !
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-put-key @ _PBTC-key!
    _PBTC-put-value @ _PBTC-value ! _PBTC-value 8
    _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-PUT
        PERSIST-S-OK _PBTC-status
    _PBTC-retired-bounded
    _PBTC-finish-root-b
    _PBTC-put-counters
    _PBTC-put-key @ _PBTC-put-value @ _PBTC-oracle-put
    _PBTC-oracle-cardinality
    _PBTC-put-key @ _PBTC-check-key ;

: _PBTC-delete-oracle  ( n -- )
    _PBTC-n !
    _PBTC-n @ _PBTC-oracle-present? _PBTC-assert
    _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ _PBTC-old-height !
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-n @ _PBTC-key!
    _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-DELETE
        PERSIST-S-OK _PBTC-status
    _PBTC-retired-bounded
    _PBTC-finish-root-b
    _PBTC-delete-counters
    _PBTC-n @ _PBTC-oracle-delete
    _PBTC-oracle-cardinality
    _PBTC-n @ _PBTC-check-key ;

: _PBTC-fixed-seed-trace  ( limit rounds seed value-base -- )
    _PBTC-trace-value-base !
    _PBTC-rng-reset
    _PBTC-trace-rounds !
    _PBTC-trace-limit !
    _PBTC-trace-rounds @ 0 DO
        _PBTC-rng-next _PBTC-trace-limit @ MOD _PBTC-trace-key !
        _PBTC-trace-key @ _PBTC-delete-oracle
        _PBTC-trace-limit @ 12 = IF
            _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 11 = _PBTC-assert
            _PBTC-root-a PBTREE-ROOT-HEIGHT@ 1 = _PBTC-assert
        THEN
        _PBTC-trace-limit @ 90 = IF
            _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 89 = _PBTC-assert
            _PBTC-root-a PBTREE-ROOT-HEIGHT@
                DUP 2 >= SWAP 3 <= AND _PBTC-assert
        THEN
        _PBTC-rng-next _PBTC-trace-limit @ MOD _PBTC-check-key
        _PBTC-trace-key @
        _PBTC-rng-next 4096 MOD _PBTC-trace-value-base @ +
            _PBTC-put-exact
        _PBTC-trace-limit @ 12 = IF
            _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 12 = _PBTC-assert
            _PBTC-root-a PBTREE-ROOT-HEIGHT@ 2 = _PBTC-assert
        THEN
        _PBTC-trace-limit @ 90 = IF
            _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 90 = _PBTC-assert
            _PBTC-root-a PBTREE-ROOT-HEIGHT@ 3 = _PBTC-assert
        THEN
        _PBTC-rng-next _PBTC-trace-limit @ MOD _PBTC-trace-update-key !
        _PBTC-trace-update-key @
        _PBTC-rng-next 4096 MOD _PBTC-trace-value-base @ 8192 + +
            _PBTC-put-exact
        _PBTC-rng-next _PBTC-trace-limit @ MOD _PBTC-check-key
    LOOP
    _PBTC-trace-limit @ _PBTC-oracle-scan
    _PBTC-oracle-cardinality ;

: _PBTC-empty-alpha  ( -- )
    _PBTC-root-b _PBTC-root-a PBTREE-ROOT-COPY PERSIST-S-OK _PBTC-status
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ _PBTC-old-height !
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    S" alpha" _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work
        PBTREE-DELETE PERSIST-S-OK _PBTC-status
    _PBTC-retired-bounded
    _PBTC-finish-root-b
    _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 0= _PBTC-assert
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ 0= _PBTC-assert _PBTC-stack ;

: _PBTC-geometry  ( -- )
    PBTREE-HEIGHT-MAX 9 = _PBTC-assert
    PBTREE-MUTATION-PAGE-MAX 19 = _PBTC-assert
    PBTREE-ALLOCATION-MAX 19 = _PBTC-assert
    PBTREE-RETIREMENT-MAX 19 = _PBTC-assert
    PBTREE-WORK-SIZE 17480 = _PBTC-assert
    PBTREE-CURSOR-SIZE 472 = _PBTC-assert
    1 PBTREE-BALANCED-CAPACITY-FOR-HEIGHT 11 = _PBTC-assert
    2 PBTREE-BALANCED-CAPACITY-FOR-HEIGHT 89 = _PBTC-assert
    3 PBTREE-BALANCED-CAPACITY-FOR-HEIGHT 635 = _PBTC-assert
    8 PBTREE-BALANCED-CAPACITY-FOR-HEIGHT 10706057 = _PBTC-assert
    9 PBTREE-BALANCED-CAPACITY-FOR-HEIGHT 74942411 = _PBTC-assert
    11 PBTREE-HEIGHT-FOR 1 = _PBTC-assert
    12 PBTREE-HEIGHT-FOR 2 = _PBTC-assert
    89 PBTREE-HEIGHT-FOR 2 = _PBTC-assert
    90 PBTREE-HEIGHT-FOR 3 = _PBTC-assert
    21000000 PBTREE-HEIGHT-FOR 9 = _PBTC-assert _PBTC-stack ;

: _PBTC-build-height-three  ( -- )
    1000 _PBTC-value-bias !
    12 0 DO
        I 11 = IF
            _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
        THEN
        I _PBTC-put-n
        _PBTC-root-a PBTREE-ROOT-CARDINALITY@ I 1+ = _PBTC-assert
        I 10 = IF _PBTC-root-a PBTREE-ROOT-HEIGHT@ 1 = _PBTC-assert THEN
        I 11 = IF
            _PBTC-root-a PBTREE-ROOT-HEIGHT@ 2 = _PBTC-assert
            _PBTC-put-counters
        THEN
        _PBTC-stack
    LOOP
    12 1000 _PBTC-oracle-default-prefix
    12 6 324508639 12000 _PBTC-fixed-seed-trace
    12 0 DO I I 1000 + _PBTC-put-exact LOOP
    90 12 DO
        I 89 = IF
            _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
        THEN
        I _PBTC-put-n
        _PBTC-root-a PBTREE-ROOT-CARDINALITY@ I 1+ = _PBTC-assert
        I 88 = IF _PBTC-root-a PBTREE-ROOT-HEIGHT@ 2 = _PBTC-assert THEN
        I 89 = IF
            _PBTC-root-a PBTREE-ROOT-HEIGHT@ 3 = _PBTC-assert
            _PBTC-put-counters
        THEN
        _PBTC-stack
    LOOP ;

: _PBTC-scan-numbers  ( -- )
    _PBTC-root-a _PBTC-tree _PBTC-cursor PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    90 0 DO
        I I 1000 +
        _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
            _PBTC-number-row
    LOOP
    _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
        PERSIST-S-NOT-FOUND _PBTC-no-row
    45 1045 45 _PBTC-key!
        _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-SEEK
        _PBTC-number-row
    46 1046 45 _PBTC-key!
        _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-RESUME
        _PBTC-number-row ;

: _PBTC-measured-read-bounds  ( -- )
    \ A cold point read is the height-only bound used by point_lookup_cost.
    _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    89 1089 _PBTC-get-n
    _PBTC-tree PBTREE-PAGE-READS@
        _PBTC-root-a PBTREE-ROOT-HEIGHT@ = _PBTC-assert
    _PBTC-tree PBTREE-PAGE-WRITES@ 0= _PBTC-assert
    _PBTC-tree PBTREE-COMPARISONS@ 0> _PBTC-assert
    _PBTC-tree PBTREE-WORKING-BYTES@ PBTREE-WORK-SIZE = _PBTC-assert

    \ These 48-page/879-comparison limits are keyset_page_cost(90,45,32).
    _PBTC-root-a _PBTC-tree _PBTC-cursor PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    45 1045 44 _PBTC-key!
        _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-RESUME
        _PBTC-number-row
    31 0 DO
        I 46 + DUP 1000 +
        _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
            _PBTC-number-row
    LOOP
    _PBTC-tree PBTREE-PAGE-READS@ 48 <= _PBTC-assert
    _PBTC-tree PBTREE-PAGE-WRITES@ 0= _PBTC-assert
    _PBTC-tree PBTREE-COMPARISONS@ 879 <= _PBTC-assert
    _PBTC-tree PBTREE-WORKING-BYTES@ PBTREE-WORK-SIZE =
        _PBTC-assert _PBTC-stack ;

: _PBTC-update-and-stale  ( -- )
    _PBTC-root-a _PBTC-tree _PBTC-cursor PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    44 1044 44 _PBTC-key!
        _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-SEEK
        _PBTC-number-row
    2000 _PBTC-value-bias !
    900 _PBTC-put-n
    _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-NEXT
        PERSIST-S-CONFLICT _PBTC-no-row
    _PBTC-root-a _PBTC-tree _PBTC-cursor PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    45 1045 44 _PBTC-key!
        _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work PBTREE-RESUME
        _PBTC-number-row
    45 _PBTC-put-n
    45 2045 _PBTC-get-n
    44 1044 _PBTC-get-n ;

: _PBTC-delete-n  ( n -- )
    _PBTC-n !
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ _PBTC-old-height !
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-n @ _PBTC-key!
    _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-DELETE
        PERSIST-S-OK _PBTC-status
    _PBTC-work PBTREE-RETIRED-PAGES$ NIP
    DUP _PBTC-max-retired @ MAX _PBTC-max-retired !
    DUP 17 <= _PBTC-assert
    _PBTC-old-height @ >= _PBTC-assert _PBTC-stack
    _PBTC-finish-root-b
    _PBTC-n @ _PBTC-key!
    _PBTC-root-a _PBTC-tree _PBTC-work PBTREE-GET
        PERSIST-S-NOT-FOUND _PBTC-no-value ;

: _PBTC-mixed-at-height-three  ( -- )
    \ Remove the unrelated insertion used to invalidate the old cursor, then
    \ mirror the committed 0..89 state in the independent scalar oracle.
    900 _PBTC-delete-n
    90 1000 _PBTC-oracle-default-prefix
    45 2045 _PBTC-oracle-put
    90 12 610839776 24000 _PBTC-fixed-seed-trace ;

: _PBTC-delete-churn  ( -- )
    0 _PBTC-max-retired !
    90 0 DO
        I 37 * 90 MOD _PBTC-delete-n
        _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 89 I - = _PBTC-assert
        _PBTC-root-a PBTREE-ROOT-HEIGHT@ DUP _PBTC-max-height @ MAX
            _PBTC-max-height !
        3 <= _PBTC-assert _PBTC-stack
    LOOP
    _PBTC-root-a PBTREE-ROOT-PAGE@ -1 = _PBTC-assert
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ 0= _PBTC-assert
    _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 0= _PBTC-assert
    _PBTC-max-height @ 3 <= _PBTC-assert
    _PBTC-max-retired @ 3 > _PBTC-assert
    _PBTC-max-retired @ 17 <= _PBTC-assert _PBTC-stack
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    999 _PBTC-key! _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work
        PBTREE-DELETE PERSIST-S-NOT-FOUND _PBTC-status
    _PBTC-store _PBTC-pstore-work PSTORE-TX-READY? _PBTC-assert _PBTC-stack
    _PBTC-store _PBTC-pstore-work PSTORE-ABORT PERSIST-S-OK _PBTC-status ;

: _PBTC-reinsert-after-churn  ( -- )
    3000 _PBTC-value-bias !
    90 0 DO I _PBTC-put-n LOOP
    _PBTC-root-a PBTREE-ROOT-CARDINALITY@ 90 = _PBTC-assert
    _PBTC-root-a PBTREE-ROOT-HEIGHT@ 3 = _PBTC-assert
    0 3000 _PBTC-get-n
    89 3089 _PBTC-get-n _PBTC-stack ;

: _PBTC-reopen-store-init  ( -- status )
    S" /pbt-pages" S" /pbt-segment" S" /pbt-root-a" S" /pbt-root-b"
    _PBTC-identity 256 _PBTC-vfs @ 0 0 _PBTC-reopen-guard
    0 0 _PBTC-reopen-store PSTORE-INIT ;

: _PBTC-load-reopen-root  ( -- )
    _PBTC-reopen-store-init PERSIST-S-OK _PBTC-status
    _PBTC-reopen-record-buffer 512 _PBTC-reopen-pstore-work PSTORE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-reopen-store _PBTC-reopen-pstore-work PSTORE-PROVISION
        PERSIST-S-OK _PBTC-status
    _PBTC-reopen-store _PBTC-reopen-pstore-work PSTORE-OPEN
        PERSIST-S-OK _PBTC-status
    _PBTC-reopen-store PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _PBTC-reopen-store _PBTC-reopen-pstore-work PSTORE-READ-PAGE
        PERSIST-S-OK _PBTC-status
    _PBTC-reopen-pstore-work PSTORE-PAGE-PAYLOAD$ DROP
        _PBTC-reopen-root PBTREE-ROOT-SIZE MOVE
    101 ['] PBTREE-HIGH-WATER-ALLOCATE 0
        _PBTC-reopen-store _PBTC-reopen-tree PBTREE-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-reopen-pstore-work _PBTC-reopen-work PBTREE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-reopen-root _PBTC-reopen-tree PBTREE-ROOT-VALID?
        _PBTC-assert _PBTC-stack ;

: _PBTC-cold-reopen-oracle  ( -- )
    _PBTC-load-reopen-root
    _PBTC-reopen-root PBTREE-ROOT-SIZE
        _PBTC-root-a PBTREE-ROOT-SIZE COMPARE 0= _PBTC-assert
    _PBTC-reopen-root PBTREE-ROOT-CARDINALITY@ _PBTC-oracle-count =
        _PBTC-assert
    _PBTC-reopen-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    89 _PBTC-oracle-value@ 89 _PBTC-key!
        _PBTC-reopen-root _PBTC-reopen-tree
        _PBTC-reopen-work PBTREE-GET _PBTC-value-result
    _PBTC-reopen-tree PBTREE-PAGE-READS@
        _PBTC-reopen-root PBTREE-ROOT-HEIGHT@ = _PBTC-assert
    _PBTC-reopen-tree PBTREE-PAGE-WRITES@ 0= _PBTC-assert
    _PBTC-reopen-tree PBTREE-COMPARISONS@ 0> _PBTC-assert
    _PBTC-reopen-tree PBTREE-WORKING-BYTES@ PBTREE-WORK-SIZE =
        _PBTC-assert _PBTC-stack
    _PBTC-reopen-root _PBTC-reopen-tree _PBTC-reopen-cursor
        PBTREE-CURSOR-INIT PERSIST-S-OK _PBTC-status
    90 0 DO
        I I _PBTC-oracle-value@
        _PBTC-reopen-root _PBTC-reopen-tree _PBTC-reopen-cursor
            _PBTC-reopen-work PBTREE-NEXT _PBTC-number-row
    LOOP
    _PBTC-reopen-root _PBTC-reopen-tree _PBTC-reopen-cursor
        _PBTC-reopen-work PBTREE-NEXT
        PERSIST-S-NOT-FOUND _PBTC-no-row ;

: _PBTC-cold-reopen  ( -- )
    _PBTC-load-reopen-root
    _PBTC-reopen-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    3089 89 _PBTC-key! _PBTC-reopen-root _PBTC-reopen-tree
        _PBTC-reopen-work PBTREE-GET _PBTC-value-result
    _PBTC-reopen-tree PBTREE-PAGE-READS@ DUP 0> _PBTC-assert
    _PBTC-reopen-root PBTREE-ROOT-HEIGHT@ <= _PBTC-assert
    _PBTC-reopen-tree PBTREE-PAGE-WRITES@ 0= _PBTC-assert
    _PBTC-reopen-tree PBTREE-WORKING-BYTES@ PBTREE-WORK-SIZE =
        _PBTC-assert _PBTC-stack
    _PBTC-reopen-root _PBTC-reopen-tree _PBTC-reopen-cursor
        PBTREE-CURSOR-INIT PERSIST-S-OK _PBTC-status
    0 3000 _PBTC-reopen-root _PBTC-reopen-tree _PBTC-reopen-cursor
        _PBTC-reopen-work PBTREE-NEXT _PBTC-number-row ;

: _PBTC-root-advance  ( -- )
    _PBTC-root-a _PBTC-root-a _PBTC-tree PBTREE-ROOT-ADVANCE
        PERSIST-S-INVALID _PBTC-status
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-root-a _PBTC-root-b _PBTC-tree PBTREE-ROOT-ADVANCE
        PERSIST-S-OK _PBTC-status
    _PBTC-root-b PBTREE-ROOT-PAGE@
        _PBTC-root-a PBTREE-ROOT-PAGE@ = _PBTC-assert
    _PBTC-root-b PBTREE-ROOT-CARDINALITY@
        _PBTC-root-a PBTREE-ROOT-CARDINALITY@ = _PBTC-assert
    _PBTC-root-b PBTREE-ROOT-HEIGHT@
        _PBTC-root-a PBTREE-ROOT-HEIGHT@ = _PBTC-assert
    _PBTC-root-b PBTREE-ROOT-GENERATION@
        _PBTC-root-a PBTREE-ROOT-GENERATION@ 1+ = _PBTC-assert _PBTC-stack
    _PBTC-finish-root-b
    89 3089 _PBTC-get-n ;

: _PBTC-tx-lookups  ( -- )
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    200 DUP _PBTC-key! ROT _PBTC-value!
        _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-PUT
        PERSIST-S-OK _PBTC-status
    3200 200 _PBTC-key! _PBTC-root-b _PBTC-tree _PBTC-work
        PBTREE-GET-TX _PBTC-value-result
    200 _PBTC-key! _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-GET
        PERSIST-S-CONFLICT _PBTC-no-value
    201 DUP _PBTC-key! ROT _PBTC-value!
        _PBTC-root-b _PBTC-root-c _PBTC-tree _PBTC-work PBTREE-PUT
        PERSIST-S-OK _PBTC-status
    3200 200 _PBTC-key! _PBTC-root-c _PBTC-tree _PBTC-work
        PBTREE-GET-TX _PBTC-value-result
    3201 201 _PBTC-key! _PBTC-root-c _PBTC-tree _PBTC-work
        PBTREE-GET-TX _PBTC-value-result
    _PBTC-root-c _PBTC-stage-root
    _PBTC-store _PBTC-pstore-work PSTORE-COMMIT PERSIST-S-OK _PBTC-status
    _PBTC-root-c _PBTC-root-a PBTREE-ROOT-COPY PERSIST-S-OK _PBTC-status
    200 3200 _PBTC-get-n
    201 3201 _PBTC-get-n
    200 _PBTC-key! _PBTC-root-a _PBTC-tree _PBTC-work PBTREE-GET-TX
        PERSIST-S-BUSY _PBTC-no-value ;

: _PBTC-sentinel-root  ( -- )
    _PBTC-root-b PBTREE-ROOT-SIZE 165 FILL
    _PBTC-root-b _PBTC-root-snapshot PBTREE-ROOT-SIZE MOVE ;

: _PBTC-output-unchanged  ( -- )
    _PBTC-root-b PBTREE-ROOT-SIZE
        _PBTC-root-snapshot PBTREE-ROOT-SIZE COMPARE 0= _PBTC-assert
    _PBTC-work PBTREE-RETIRED-PAGES$ NIP 0= _PBTC-assert ;

: _PBTC-failing-put  ( expected-status -- )
    _PBTC-n !
    _PBTC-sentinel-root
    _PBTC-fault-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    _PBTC-store PSTORE-GENERATION@ _PBTC-old-generation !
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-root-b _PBTC-fault-tree _PBTC-work PBTREE-PUT
        _PBTC-n @ _PBTC-status
    _PBTC-output-unchanged
    _PBTC-store _PBTC-pstore-work PSTORE-TX-READY? 0= _PBTC-assert
    _PBTC-store PSTORE-STATUS@ _PBTC-n @ _PBTC-status
    _PBTC-pstore-work PSTORE-WORK-STATUS@ _PBTC-n @ _PBTC-status
    _PBTC-allocator-mode @ 3 = IF
        _PBTC-allocator-calls @ 2 = _PBTC-assert
        _PBTC-fault-tree PBTREE-PAGE-WRITES@ 1 = _PBTC-assert
        _PBTC-pstore-work PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
            _PBTC-store PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 1+ =
            _PBTC-assert _PBTC-stack
    THEN
    _PBTC-store _PBTC-pstore-work PSTORE-COMMIT
        PERSIST-S-CONFLICT _PBTC-status
    _PBTC-store PSTORE-GENERATION@ _PBTC-old-generation @ = _PBTC-assert
    _PBTC-store PSTORE-STATUS@ _PBTC-n @ _PBTC-status
    _PBTC-pstore-work PSTORE-WORK-STATUS@ _PBTC-n @ _PBTC-status
    0 _PBTC-fault-at !
    _PBTC-store _PBTC-pstore-work PSTORE-ABORT PERSIST-S-OK _PBTC-status
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-pstore-work PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _PBTC-store PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ = _PBTC-assert
    _PBTC-store _PBTC-pstore-work PSTORE-ABORT PERSIST-S-OK _PBTC-status
    3089 89 _PBTC-key! _PBTC-root-a _PBTC-fault-tree _PBTC-work
        PBTREE-GET _PBTC-value-result ;

: _PBTC-faults-and-reentry  ( -- )
    101 ['] _PBTC-test-allocator 0 _PBTC-store _PBTC-fault-tree PBTREE-INIT
        PERSIST-S-OK _PBTC-status
    0 _PBTC-allocator-mode !
    PERSIST-FAULT-PAGE-WRITTEN _PBTC-fault-at !
    PERSIST-S-FAULT _PBTC-failing-put
    PERSIST-FAULT-PAGE-VERIFIED _PBTC-fault-at !
    PERSIST-S-FAULT _PBTC-failing-put
    1 _PBTC-allocator-mode ! 0 _PBTC-allocator-calls !
    PERSIST-S-FAULT _PBTC-failing-put
    2 _PBTC-allocator-mode ! 0 _PBTC-allocator-calls !
    PERSIST-S-FAULT _PBTC-failing-put
    3 _PBTC-allocator-mode ! 0 _PBTC-allocator-calls !
    PERSIST-S-CONFLICT _PBTC-failing-put
    4 _PBTC-allocator-mode ! 0 _PBTC-allocator-calls !
    PERSIST-S-NOT-FOUND _PBTC-failing-put
    5 _PBTC-allocator-mode ! 0 _PBTC-allocator-calls !
    -999 _PBTC-reentry-status !
    PERSIST-S-FAULT _PBTC-failing-put
    _PBTC-reentry-status @ PERSIST-S-BUSY = _PBTC-assert
    6 _PBTC-allocator-mode ! 0 _PBTC-allocator-calls !
    PERSIST-S-CAPACITY _PBTC-failing-put
    0 _PBTC-allocator-mode ! _PBTC-stack ;

: _PBTC-generation-capacity  ( -- )
    _PBTC-store PSTORE-GENERATION@ _PBTC-old-generation !
    PERSIST-MAX-SIGNED _PBTC-store _PST.GENERATION !
    PERSIST-MAX-SIGNED _PBTC-pstore-work _PSW.ROOT-WORK
        _PROOT-W.GPAIR GPAIR.GENERATION !
    PERSIST-MAX-SIGNED _PBTC-root-a _PBTR.GENERATION !
    _PBTC-store PSTORE-VALID? _PBTC-assert
    _PBTC-root-a _PBTC-tree PBTREE-ROOT-VALID? _PBTC-assert _PBTC-stack
    _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    _PBTC-sentinel-root
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-root-b _PBTC-tree _PBTC-work PBTREE-PUT
        PERSIST-S-CAPACITY _PBTC-status
    _PBTC-root-b PBTREE-ROOT-SIZE
        _PBTC-root-snapshot PBTREE-ROOT-SIZE COMPARE 0= _PBTC-assert
    _PBTC-tree PBTREE-PAGE-WRITES@ 0= _PBTC-assert _PBTC-stack
    _PBTC-old-generation @ _PBTC-store _PST.GENERATION !
    _PBTC-old-generation @ _PBTC-pstore-work _PSW.ROOT-WORK
        _PROOT-W.GPAIR GPAIR.GENERATION !
    _PBTC-old-generation @ _PBTC-root-a _PBTR.GENERATION !
    _PBTC-store PSTORE-VALID? _PBTC-assert
    _PBTC-root-a _PBTC-tree PBTREE-ROOT-VALID? _PBTC-assert _PBTC-stack ;

: _PBTC-alias-boundaries  ( -- )
    _PBTC-tree _PBTC-store PBTREE-ROOT-INIT
        PERSIST-S-INVALID _PBTC-status
    _PBTC-store PSTORE-VALID? _PBTC-assert _PBTC-stack
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-root-a _PBTC-fault-tree _PBTC-work PBTREE-PUT
        PERSIST-S-INVALID _PBTC-status
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-root-a 8 + _PBTC-fault-tree _PBTC-work PBTREE-PUT
        PERSIST-S-INVALID _PBTC-status
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-fault-tree _PBTC-fault-tree _PBTC-work PBTREE-PUT
        PERSIST-S-INVALID _PBTC-status
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-work _PBTC-fault-tree _PBTC-work PBTREE-PUT
        PERSIST-S-INVALID _PBTC-status
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-store _PBTC-fault-tree _PBTC-work PBTREE-PUT
        PERSIST-S-INVALID _PBTC-status
    _PBTC-store _PBTC-pstore-work PSTORE-TX-READY? _PBTC-assert _PBTC-stack
    _PBTC-store PSTORE-VALID? _PBTC-assert
    _PBTC-fault-tree PBTREE-VALID? _PBTC-assert
    _PBTC-store _PBTC-pstore-work PSTORE-ABORT PERSIST-S-OK _PBTC-status
    89 3089 _PBTC-get-n
    _PBTC-root-a _PBTC-tree _PBTC-cursor PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-cursor 2 _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work
        PBTREE-SEEK PERSIST-S-INVALID _PBTC-no-row
    _PBTC-cursor PBTREE-CURSOR-VALID? _PBTC-assert _PBTC-stack
    _PBTC-cursor 2 _PBTC-root-a _PBTC-tree _PBTC-cursor _PBTC-work
        PBTREE-RESUME PERSIST-S-INVALID _PBTC-no-row
    _PBTC-cursor PBTREE-CURSOR-VALID? _PBTC-assert _PBTC-stack
    _PBTC-pstore-work _PBTC-record-buffer PBTREE-WORK-INIT
        PERSIST-S-INVALID _PBTC-status
    _PBTC-fault-tree _PBTC-record-buffer PBTREE-SIZE MOVE
    89 _PBTC-key! _PBTC-root-a _PBTC-record-buffer _PBTC-work PBTREE-GET
        PERSIST-S-INVALID _PBTC-no-value

    \ A scoped current read may use a PSTORE work not bound into the store
    \ graph.  Every layered boundary must still include that work's buffer.
    _PBTC-i0-record 512 _PBTC-i0-pwork PSTORE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-i0-pwork _PBTC-i0-work PBTREE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-i0-pwork _PBTC-i0-record PBTREE-WORK-INIT
        PERSIST-S-INVALID _PBTC-status
    _PBTC-root-a _PBTC-i0-record PBTREE-ROOT-SIZE MOVE
    89 _PBTC-key! _PBTC-i0-record _PBTC-tree _PBTC-i0-work PBTREE-GET
        PERSIST-S-INVALID _PBTC-no-value
    _PBTC-root-a _PBTC-i0-record PBTREE-ROOT-SIZE MOVE
    _PBTC-i0-record _PBTC-root-snapshot PBTREE-ROOT-SIZE MOVE
    88 _PBTC-key! 4088 _PBTC-value ! _PBTC-value 8
        _PBTC-root-a _PBTC-i0-record _PBTC-tree _PBTC-i0-work PBTREE-PUT
        PERSIST-S-INVALID _PBTC-status
    _PBTC-i0-record PBTREE-ROOT-SIZE
        _PBTC-root-snapshot PBTREE-ROOT-SIZE COMPARE 0= _PBTC-assert
    _PBTC-root-a _PBTC-tree _PBTC-i0-record PBTREE-CURSOR-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-root-a _PBTC-tree _PBTC-i0-record _PBTC-i0-work PBTREE-NEXT
        PERSIST-S-INVALID _PBTC-no-row
    _PBTC-i0-record PBTREE-CURSOR-VALID? _PBTC-assert _PBTC-stack
    _PBTC-fault-tree _PBTC-i0-record PBTREE-SIZE MOVE
    89 _PBTC-key! _PBTC-root-a _PBTC-i0-record _PBTC-i0-work PBTREE-GET
        PERSIST-S-INVALID _PBTC-no-value ;

: _PBTC-stage-root-for  ( root store pstore-work -- )
    _PBTC-target-work ! _PBTC-target-store !
    _PBTC-app-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBTC-app-page PBTREE-ROOT-SIZE MOVE
    _PBTC-app-page PERSIST-PAGE-PAYLOAD-SIZE
        _PBTC-target-store @ _PBTC-target-work @ PSTORE-APPEND-PAGE
    SWAP _PBTC-page-id ! PERSIST-S-OK _PBTC-status
    _PBTC-page-id @ _PBTC-target-store @ _PBTC-target-work @
        PSTORE-APPLICATION-ROOT! PERSIST-S-OK _PBTC-status ;

: _PBTC-i0-init  ( -- )
    S" /pbi0-pages" S" /pbi0-segment" S" /pbi0-root-a" S" /pbi0-root-b"
    _PBTC-identity 256 _PBTC-vfs @ 0 0 _PBTC-i0-guard
        0 0 _PBTC-i0-store PSTORE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i0-record 512 _PBTC-i0-pwork PSTORE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-i0-store _PBTC-i0-pwork PSTORE-PROVISION PERSIST-S-OK _PBTC-status
    _PBTC-i0-store _PBTC-i0-pwork PSTORE-OPEN PERSIST-S-ABSENT _PBTC-status
    201 ['] PBTREE-HIGH-WATER-ALLOCATE 0 _PBTC-i0-store _PBTC-i0-tree
        PBTREE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i0-pwork _PBTC-i0-work PBTREE-WORK-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i0-tree _PBTC-i0-root-a PBTREE-ROOT-INIT
        PERSIST-S-OK _PBTC-status ;

: _PBTC-i1-init  ( -- )
    S" /pbi1-pages" S" /pbi1-segment" S" /pbi1-root-a" S" /pbi1-root-b"
    _PBTC-identity 256 _PBTC-vfs @ 0 0 _PBTC-i1-guard
        0 0 _PBTC-i1-store PSTORE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i1-record 512 _PBTC-i1-pwork PSTORE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-i1-store _PBTC-i1-pwork PSTORE-PROVISION PERSIST-S-OK _PBTC-status
    _PBTC-i1-store _PBTC-i1-pwork PSTORE-OPEN PERSIST-S-ABSENT _PBTC-status
    202 ['] PBTREE-HIGH-WATER-ALLOCATE 0 _PBTC-i1-store _PBTC-i1-tree
        PBTREE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i1-pwork _PBTC-i1-work PBTREE-WORK-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i1-tree _PBTC-i1-root-a PBTREE-ROOT-INIT
        PERSIST-S-OK _PBTC-status ;

: _PBTC-i2-init  ( -- )
    S" /pbi2-pages" S" /pbi2-segment" S" /pbi2-root-a" S" /pbi2-root-b"
    _PBTC-identity 256 _PBTC-vfs @ 0 0 _PBTC-i2-guard
        0 0 _PBTC-i2-store PSTORE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i2-record 512 _PBTC-i2-pwork PSTORE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-i2-store _PBTC-i2-pwork PSTORE-PROVISION PERSIST-S-OK _PBTC-status
    _PBTC-i2-store _PBTC-i2-pwork PSTORE-OPEN PERSIST-S-ABSENT _PBTC-status
    203 ['] PBTREE-HIGH-WATER-ALLOCATE 0 _PBTC-i2-store _PBTC-i2-tree
        PBTREE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i2-pwork _PBTC-i2-work PBTREE-WORK-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i2-tree _PBTC-i2-root-a PBTREE-ROOT-INIT
        PERSIST-S-OK _PBTC-status ;

: _PBTC-i3-init  ( -- )
    S" /pbi3-pages" S" /pbi3-segment" S" /pbi3-root-a" S" /pbi3-root-b"
    _PBTC-identity 256 _PBTC-vfs @ 0 0 _PBTC-i3-guard
        0 0 _PBTC-i3-store PSTORE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i3-record 512 _PBTC-i3-pwork PSTORE-WORK-INIT
        PERSIST-S-OK _PBTC-status
    _PBTC-i3-store _PBTC-i3-pwork PSTORE-PROVISION PERSIST-S-OK _PBTC-status
    _PBTC-i3-store _PBTC-i3-pwork PSTORE-OPEN PERSIST-S-ABSENT _PBTC-status
    204 ['] PBTREE-HIGH-WATER-ALLOCATE 0 _PBTC-i3-store _PBTC-i3-tree
        PBTREE-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i3-pwork _PBTC-i3-work PBTREE-WORK-INIT PERSIST-S-OK _PBTC-status
    _PBTC-i3-tree _PBTC-i3-root-a PBTREE-ROOT-INIT
        PERSIST-S-OK _PBTC-status ;

: _PBTC-four-store-isolation  ( -- )
    _PBTC-i0-init _PBTC-i1-init _PBTC-i2-init _PBTC-i3-init
    _PBTC-i0-store _PBTC-i0-pwork PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-i1-store _PBTC-i1-pwork PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-i2-store _PBTC-i2-pwork PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTC-i3-store _PBTC-i3-pwork PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    5000 _PBTC-value-bias !
    10 DUP _PBTC-key! ROT _PBTC-value! _PBTC-i0-root-a _PBTC-i0-root-b
        _PBTC-i0-tree _PBTC-i0-work PBTREE-PUT PERSIST-S-OK _PBTC-status
    20 DUP _PBTC-key! ROT _PBTC-value! _PBTC-i1-root-a _PBTC-i1-root-b
        _PBTC-i1-tree _PBTC-i1-work PBTREE-PUT PERSIST-S-OK _PBTC-status
    30 DUP _PBTC-key! ROT _PBTC-value! _PBTC-i2-root-a _PBTC-i2-root-b
        _PBTC-i2-tree _PBTC-i2-work PBTREE-PUT PERSIST-S-OK _PBTC-status
    40 DUP _PBTC-key! ROT _PBTC-value! _PBTC-i3-root-a _PBTC-i3-root-b
        _PBTC-i3-tree _PBTC-i3-work PBTREE-PUT PERSIST-S-OK _PBTC-status
    _PBTC-i0-root-b _PBTC-i0-store _PBTC-i0-pwork _PBTC-stage-root-for
    _PBTC-i1-root-b _PBTC-i1-store _PBTC-i1-pwork _PBTC-stage-root-for
    _PBTC-i2-root-b _PBTC-i2-store _PBTC-i2-pwork _PBTC-stage-root-for
    _PBTC-i3-root-b _PBTC-i3-store _PBTC-i3-pwork _PBTC-stage-root-for
    _PBTC-i3-store _PBTC-i3-pwork PSTORE-COMMIT PERSIST-S-OK _PBTC-status
    _PBTC-i1-store _PBTC-i1-pwork PSTORE-COMMIT PERSIST-S-OK _PBTC-status
    _PBTC-i0-store _PBTC-i0-pwork PSTORE-COMMIT PERSIST-S-OK _PBTC-status
    _PBTC-i2-store _PBTC-i2-pwork PSTORE-COMMIT PERSIST-S-OK _PBTC-status
    _PBTC-i0-root-b _PBTC-i0-root-a PBTREE-ROOT-COPY PERSIST-S-OK _PBTC-status
    _PBTC-i1-root-b _PBTC-i1-root-a PBTREE-ROOT-COPY PERSIST-S-OK _PBTC-status
    _PBTC-i2-root-b _PBTC-i2-root-a PBTREE-ROOT-COPY PERSIST-S-OK _PBTC-status
    _PBTC-i3-root-b _PBTC-i3-root-a PBTREE-ROOT-COPY PERSIST-S-OK _PBTC-status
    5010 10 _PBTC-key! _PBTC-i0-root-a _PBTC-i0-tree _PBTC-i0-work
        PBTREE-GET _PBTC-value-result
    5020 20 _PBTC-key! _PBTC-i1-root-a _PBTC-i1-tree _PBTC-i1-work
        PBTREE-GET _PBTC-value-result
    5030 30 _PBTC-key! _PBTC-i2-root-a _PBTC-i2-tree _PBTC-i2-work
        PBTREE-GET _PBTC-value-result
    5040 40 _PBTC-key! _PBTC-i3-root-a _PBTC-i3-tree _PBTC-i3-work
        PBTREE-GET _PBTC-value-result
    20 _PBTC-key! _PBTC-i0-root-a _PBTC-i0-tree _PBTC-i0-work PBTREE-GET
        PERSIST-S-NOT-FOUND _PBTC-no-value
    _PBTC-i0-store PSTORE-GENERATION@ 1 = _PBTC-assert
    _PBTC-i1-store PSTORE-GENERATION@ 1 = _PBTC-assert
    _PBTC-i2-store PSTORE-GENERATION@ 1 = _PBTC-assert
    _PBTC-i3-store PSTORE-GENERATION@ 1 = _PBTC-assert _PBTC-stack
    _PBTC-i0-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    _PBTC-i1-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    5020 20 _PBTC-key! _PBTC-i1-root-a _PBTC-i1-tree _PBTC-i1-work
        PBTREE-GET _PBTC-value-result
    _PBTC-i0-tree PBTREE-PAGE-READS@ 0= _PBTC-assert
    _PBTC-i1-tree PBTREE-PAGE-READS@ 1 = _PBTC-assert _PBTC-stack ;

: _PBTC-RUN  ( -- )
    0 _PBTC-fails ! 0 _PBTC-checks ! 0 _PBTC-fault-at ! DEPTH _PBTC-depth !
    1 _PBTC-phase ! _PBTC-setup
    2 _PBTC-phase ! _PBTC-geometry
    3 _PBTC-phase ! _PBTC-first
    4 _PBTC-phase ! _PBTC-cursor-one
    5 _PBTC-phase ! _PBTC-empty-alpha
    6 _PBTC-phase ! _PBTC-build-height-three
    7 _PBTC-phase ! _PBTC-scan-numbers
    8 _PBTC-phase ! _PBTC-measured-read-bounds
    9 _PBTC-phase ! _PBTC-update-and-stale
    10 _PBTC-phase ! _PBTC-mixed-at-height-three
    11 _PBTC-phase ! _PBTC-cold-reopen-oracle
    12 _PBTC-phase ! _PBTC-delete-churn
    13 _PBTC-phase ! _PBTC-reinsert-after-churn
    14 _PBTC-phase ! _PBTC-cold-reopen
    15 _PBTC-phase ! _PBTC-root-advance
    16 _PBTC-phase ! _PBTC-tx-lookups
    17 _PBTC-phase ! _PBTC-faults-and-reentry
    18 _PBTC-phase ! _PBTC-generation-capacity
    19 _PBTC-phase ! _PBTC-alias-boundaries
    20 _PBTC-phase ! _PBTC-four-store-isolation
    _PBTC-old-vfs @ VFS-USE
    _PBTC-vfs @ VFS-DESTROY
    _PBTC-stack
    _PBTC-fails @ 0= IF
        ." PERSISTENCE BTREE PASS " _PBTC-checks @ . CR
    ELSE
        ." PERSISTENCE BTREE FAIL " _PBTC-fails @ . ." /" _PBTC-checks @ . CR
    THEN ;
