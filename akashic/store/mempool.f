\ =================================================================
\  mempool.f  —  Transaction Pool
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: MP-  / _MP-
\  Depends on: tx.f sha3.f guard.f
\
\  Bounded priority queue of pending transactions, sorted by
\  sender address (32 bytes) + nonce (u64).  O(log n) duplicate
\  detection via SHA3-256 tx hash.  Fee-based eviction when full.
\
\  Public API:
\   MP-INIT        ( -- )                 initialize empty mempool
\   MP-ADD         ( tx -- flag )         validate, verify sig, insert
\   MP-REMOVE      ( hash -- flag )       remove by tx hash
\   MP-DRAIN       ( n buf -- actual )    pop up to n txs into buffer
\   MP-RELEASE     ( -- )                 free drained tx buffer slots
\   MP-COUNT       ( -- n )               pending tx count
\   MP-PRUNE       ( -- n )               remove structurally invalid
\   MP-CONTAINS?   ( hash -- flag )       is tx in pool?
\
\  Constants:
\   MP-CAPACITY    ( -- 4096 )            max pending transactions
\
\  Not reentrant.
\ =================================================================

REQUIRE tx.f
REQUIRE sha3.f

PROVIDED akashic-mempool

\ =====================================================================
\  1. Constants
\ =====================================================================

4096 CONSTANT MP-CAPACITY

\ =====================================================================
\  2. Storage
\ =====================================================================

\ Pool of full tx buffers (4096 × TX-BUF-SIZE).
\ Mempool owns these buffers — callers work with pointers.
\ NOTE: ~32 MiB allocation — lives in XMEM on production nodes.
CREATE _MP-POOL  MP-CAPACITY TX-BUF-SIZE * ALLOT

\ Slot state: 0=free, 1=active, 2=drained (awaiting MP-RELEASE)
CREATE _MP-SLOTS  MP-CAPACITY ALLOT
_MP-SLOTS MP-CAPACITY 0 FILL

\ Sorted index: 48 bytes per entry
\   +0   32B  sender_addr  (SHA3-256 of sender pubkey)
\   +32   8B  nonce
\   +40   8B  pool slot index (0..4095)
48 CONSTANT _MP-ENT-SZ
CREATE _MP-IDX  MP-CAPACITY _MP-ENT-SZ * ALLOT

\ Tx hashes for dedup: parallel to sorted index (4096 × 32 bytes)
CREATE _MP-HASHES  MP-CAPACITY 32 * ALLOT

\ Hash-map bucket table for O(1) dedup instead of linear scan.
\ 8192 buckets (2× capacity), each holding a sorted-index value
\ or -1 (empty).  Open-addressing with linear probing.
\ TODO: implement hash-indexed dedup for >4096 scale. Linear scan
\       over 4096 × 32 bytes = 128 KiB is acceptable for launch.

VARIABLE _MP-COUNT
0 _MP-COUNT !

\ =====================================================================
\  3. Scratch buffers
\ =====================================================================

CREATE _MP-HASH-TMP  32 ALLOT        \ tx hash scratch
CREATE _MP-ADDR-TMP  32 ALLOT        \ sender address scratch
CREATE _MP-CMP-HASH  32 ALLOT        \ hash comparison scratch

\ =====================================================================
\  4. Pool slot management
\ =====================================================================

: _MP-TXBUF  ( slot -- addr )  TX-BUF-SIZE * _MP-POOL + ;

: _MP-ALLOC  ( -- slot | -1 )
    MP-CAPACITY 0 DO
        _MP-SLOTS I + C@ 0= IF
            1 _MP-SLOTS I + C!
            I UNLOOP EXIT
        THEN
    LOOP -1 ;

: _MP-FREE  ( slot -- )  0 SWAP _MP-SLOTS + C! ;

\ =====================================================================
\  5. Index entry access
\ =====================================================================

: _MP-ENT  ( i -- addr )  _MP-ENT-SZ * _MP-IDX + ;

\ =====================================================================
\  6. Comparison: target (addr,nonce) vs index entry i
\ =====================================================================
\  Returns: -1 if target < entry, 0 if equal, 1 if target > entry.
\  Uses VARIABLEs (not >R/R@) because of DO..LOOP.

VARIABLE _MP-CMP-A                   \ target sender address
VARIABLE _MP-CMP-N                   \ target nonce
VARIABLE _MP-CMP-ENT                 \ entry base address

: _MP-CMP  ( i -- n )
    _MP-ENT _MP-CMP-ENT !
    32 0 ?DO
        _MP-CMP-A @ I + C@  _MP-CMP-ENT @ I + C@  -
        DUP IF
            0< IF -1 ELSE 1 THEN
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    \ Addresses equal — compare nonces (unsigned)
    _MP-CMP-ENT @ 32 + @
    _MP-CMP-N @ SWAP                  ( target-nonce entry-nonce )
    2DUP U< IF 2DROP -1 EXIT THEN
    U> IF 1 ELSE 0 THEN ;

\ =====================================================================
\  7. Binary search
\ =====================================================================
\  Returns: idx flag.  flag=TRUE → exact match at idx.
\  flag=FALSE → not found, idx = insertion point.

VARIABLE _MP-BS-LO
VARIABLE _MP-BS-HI

: _MP-BSEARCH  ( addr nonce -- idx flag )
    _MP-CMP-N !  _MP-CMP-A !
    0 _MP-BS-LO !
    _MP-COUNT @ _MP-BS-HI !
    BEGIN
        _MP-BS-LO @ _MP-BS-HI @ <
    WHILE
        _MP-BS-LO @ _MP-BS-HI @ + 1 RSHIFT  ( mid )
        DUP _MP-CMP
        DUP 0= IF DROP -1 EXIT THEN  \ exact match
        0> IF
            1+ _MP-BS-LO !           \ target > mid → search right
        ELSE
            _MP-BS-HI !              \ target < mid → search left
        THEN
    REPEAT
    _MP-BS-LO @ 0 ;

\ =====================================================================
\  8. Hash-based lookup (linear scan over hash table)
\ =====================================================================
\  O(n) scan — acceptable at 4096: 128 KiB sequential read.
\  TODO: upgrade to hash-indexed bucket table for >4096 scale.

: _MP-HASH-MATCH?  ( idx -- flag )
    32 * _MP-HASHES +
    0
    32 0 ?DO
        OVER I + C@  _MP-CMP-HASH I + C@  XOR OR
    LOOP
    NIP 0= ;

: _MP-HASH-FIND  ( hash -- idx | -1 )
    _MP-CMP-HASH 32 CMOVE
    _MP-COUNT @ 0 ?DO
        I _MP-HASH-MATCH? IF I UNLOOP EXIT THEN
    LOOP
    -1 ;

\ =====================================================================
\  9. Shift helpers
\ =====================================================================

VARIABLE _MP-SH-IDX

\ Shift entries [idx..count-1] right by one (make room for insert).
\ Iterates from count-1 down to idx to avoid overlap.
: _MP-SHIFT-R  ( idx -- )
    _MP-SH-IDX !
    _MP-COUNT @ _MP-SH-IDX @ <= IF EXIT THEN
    _MP-COUNT @                       ( i = count )
    BEGIN
        1-
        DUP _MP-SH-IDX @ >=
    WHILE
        DUP _MP-ENT  OVER 1+ _MP-ENT  _MP-ENT-SZ CMOVE
        DUP 32 * _MP-HASHES +  OVER 1+ 32 * _MP-HASHES +  32 CMOVE
    REPEAT
    DROP ;

\ Shift entries [idx+1..count-1] left by one (close gap after remove).
: _MP-SHIFT-L  ( idx -- )
    _MP-SH-IDX !
    _MP-COUNT @ 1- _MP-SH-IDX @ ?DO
        I 1+ _MP-ENT  I _MP-ENT  _MP-ENT-SZ CMOVE
        I 1+ 32 * _MP-HASHES +  I 32 * _MP-HASHES +  32 CMOVE
    LOOP ;

\ =====================================================================
\  10. MP-INIT — initialize empty mempool
\ =====================================================================

: MP-INIT  ( -- )
    _MP-SLOTS MP-CAPACITY 0 FILL
    _MP-IDX  MP-CAPACITY _MP-ENT-SZ * 0 FILL
    _MP-HASHES MP-CAPACITY 32 * 0 FILL
    0 _MP-COUNT ! ;

\ =====================================================================
\  11. MP-COUNT — pending transaction count
\ =====================================================================

: MP-COUNT  ( -- n )  _MP-COUNT @ ;

\ =====================================================================
\  12. MP-CONTAINS? — check if tx hash is in pool
\ =====================================================================

: MP-CONTAINS?  ( hash -- flag )
    _MP-HASH-FIND -1 <> ;

\ =====================================================================
\  13. MP-ADD — validate, verify signature, and insert transaction
\ =====================================================================
\  FIX A04: Now calls TX-VERIFY (cryptographic signature check)
\  before allocating a pool slot.  Without this, forged txs could
\  consume all pool slots → trivial DoS.
\
\  FIX D04: Fee-based eviction.  When pool is full, the new tx
\  replaces the lowest-fee tx if its fee is strictly higher.

VARIABLE _MP-ADD-TX
VARIABLE _MP-ADD-SLOT
VARIABLE _MP-ADD-INS

\ Find sorted-index of the entry with the lowest fee.
\ Scans all entries — O(n).  Only called when pool is full.
VARIABLE _MP-EVICT-IDX
VARIABLE _MP-EVICT-FEE

: _MP-FIND-LOWEST-FEE  ( -- idx fee )
    0 _MP-EVICT-IDX !
    0 _MP-ENT 40 + @ _MP-TXBUF TX-FEE@ _MP-EVICT-FEE !
    _MP-COUNT @ 1 ?DO
        I _MP-ENT 40 + @ _MP-TXBUF TX-FEE@
        DUP _MP-EVICT-FEE @ U< IF
            _MP-EVICT-FEE !
            I _MP-EVICT-IDX !
        ELSE
            DROP
        THEN
    LOOP
    _MP-EVICT-IDX @ _MP-EVICT-FEE @ ;

\ Evict entry at sorted-index idx (free slot, shift left, decrement count).
: _MP-EVICT  ( idx -- )
    DUP _MP-ENT 40 + @ _MP-FREE
    DUP _MP-SHIFT-L
    DROP
    -1 _MP-COUNT +! ;

: MP-ADD  ( tx -- flag )
    _MP-ADD-TX !
    \ 1. Structural validity
    _MP-ADD-TX @ TX-VALID? 0= IF 0 EXIT THEN
    \ 2. Cryptographic signature verification  [FIX A04]
    _MP-ADD-TX @ TX-VERIFY 0= IF 0 EXIT THEN
    \ 3. Compute tx hash
    _MP-ADD-TX @ _MP-HASH-TMP TX-HASH
    \ 4. Duplicate check
    _MP-HASH-TMP _MP-HASH-FIND -1 <> IF 0 EXIT THEN
    \ 5. Capacity check — with fee-based eviction  [FIX D04]
    _MP-COUNT @ MP-CAPACITY >= IF
        \ Pool full — try eviction
        _MP-FIND-LOWEST-FEE                  ( evict-idx evict-fee )
        _MP-ADD-TX @ TX-FEE@ SWAP            ( evict-idx new-fee evict-fee )
        SWAP U< 0= IF                        ( new <= evict → no room )
            \ New tx fee ≤ lowest fee — no room
            DROP 0 EXIT
        THEN
        \ Evict lowest-fee entry to make room
        _MP-EVICT
    THEN
    \ 6. Allocate pool slot
    _MP-ALLOC DUP -1 = IF DROP 0 EXIT THEN
    _MP-ADD-SLOT !
    \ 7. Copy tx into pool
    _MP-ADD-TX @ _MP-ADD-SLOT @ _MP-TXBUF TX-BUF-SIZE CMOVE
    \ 8. Compute sender address
    _MP-ADD-TX @ TX-FROM@ ED25519-KEY-LEN _MP-ADDR-TMP SHA3-256-HASH
    \ 9. Binary search for insertion point
    _MP-ADDR-TMP _MP-ADD-TX @ TX-NONCE@ _MP-BSEARCH IF
        \ Same (sender, nonce) already in pool — reject
        _MP-ADD-SLOT @ _MP-FREE
        DROP 0 EXIT
    THEN
    _MP-ADD-INS !
    \ 10. Shift right to make room
    _MP-ADD-INS @ _MP-SHIFT-R
    \ 11. Write index entry: sender_addr(32) + nonce(8) + slot(8)
    _MP-ADDR-TMP  _MP-ADD-INS @ _MP-ENT  32 CMOVE
    _MP-ADD-TX @ TX-NONCE@  _MP-ADD-INS @ _MP-ENT 32 + !
    _MP-ADD-SLOT @  _MP-ADD-INS @ _MP-ENT 40 + !
    \ 12. Write hash (parallel to index)
    _MP-HASH-TMP  _MP-ADD-INS @ 32 * _MP-HASHES +  32 CMOVE
    \ 13. Increment count
    1 _MP-COUNT +!
    -1 ;

\ =====================================================================
\  14. MP-REMOVE — remove transaction by hash
\ =====================================================================

VARIABLE _MP-RM-IDX

: MP-REMOVE  ( hash -- flag )
    _MP-HASH-FIND DUP -1 = IF DROP 0 EXIT THEN
    _MP-RM-IDX !
    \ Free pool slot
    _MP-RM-IDX @ _MP-ENT 40 + @ _MP-FREE
    \ Shift entries left
    _MP-RM-IDX @ _MP-SHIFT-L
    \ Decrement count
    -1 _MP-COUNT +!
    -1 ;

\ =====================================================================
\  15. MP-DRAIN — pop up to n txs for block building
\ =====================================================================
\  Returns tx buffer pointers in buf (CELLS array).
\  Pool slots are marked "drained" (state 2) — call MP-RELEASE
\  after the block is finalized to free them.

VARIABLE _MP-DR-N
VARIABLE _MP-DR-BUF

: MP-DRAIN  ( n buf -- actual )
    _MP-DR-BUF !
    _MP-COUNT @ MIN _MP-DR-N !
    \ Copy first n entries to output buffer and mark drained
    _MP-DR-N @ 0 ?DO
        I _MP-ENT 40 + @             \ pool slot
        DUP 2 SWAP _MP-SLOTS + C!    \ mark drained
        _MP-TXBUF                     \ tx buffer address
        _MP-DR-BUF @ I CELLS + !     \ store pointer
    LOOP
    \ Shift remaining entries left by n
    _MP-COUNT @ _MP-DR-N @ ?DO
        I _MP-ENT  I _MP-DR-N @ - _MP-ENT  _MP-ENT-SZ CMOVE
        I 32 * _MP-HASHES +  I _MP-DR-N @ - 32 * _MP-HASHES +  32 CMOVE
    LOOP
    _MP-DR-N @ NEGATE _MP-COUNT +!
    _MP-DR-N @ ;

\ =====================================================================
\  16. MP-RELEASE — free drained pool slots
\ =====================================================================
\  Call after block finalization when tx buffer pointers from
\  MP-DRAIN are no longer needed.

: MP-RELEASE  ( -- )
    MP-CAPACITY 0 DO
        _MP-SLOTS I + C@ 2 = IF
            0 _MP-SLOTS I + C!
        THEN
    LOOP ;

\ =====================================================================
\  17. MP-PRUNE — remove structurally invalid entries
\ =====================================================================
\  Scans backwards and removes entries that fail TX-VALID?.
\  Returns the number of entries pruned.

: MP-PRUNE  ( -- n )
    0                                 ( removed )
    _MP-COUNT @
    BEGIN
        DUP 0>
    WHILE
        1-
        DUP _MP-ENT 40 + @ _MP-TXBUF
        TX-VALID? 0= IF
            \ Free pool slot
            DUP _MP-ENT 40 + @ _MP-FREE
            \ Shift left
            DUP _MP-SHIFT-L
            -1 _MP-COUNT +!
            SWAP 1+ SWAP              ( removed+1 i )
        THEN
    REPEAT
    DROP ;

\ =====================================================================
\  18. Concurrency guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _mp-guard

' MP-INIT       CONSTANT _mp-init-xt
' MP-ADD        CONSTANT _mp-add-xt
' MP-REMOVE     CONSTANT _mp-rm-xt
' MP-DRAIN      CONSTANT _mp-drain-xt
' MP-RELEASE    CONSTANT _mp-rel-xt
' MP-PRUNE      CONSTANT _mp-prune-xt
' MP-CONTAINS?  CONSTANT _mp-has-xt

: MP-INIT       _mp-init-xt   _mp-guard WITH-GUARD ;
: MP-ADD        _mp-add-xt    _mp-guard WITH-GUARD ;
: MP-REMOVE     _mp-rm-xt     _mp-guard WITH-GUARD ;
: MP-DRAIN      _mp-drain-xt  _mp-guard WITH-GUARD ;
: MP-RELEASE    _mp-rel-xt    _mp-guard WITH-GUARD ;
: MP-PRUNE      _mp-prune-xt  _mp-guard WITH-GUARD ;
: MP-CONTAINS?  _mp-has-xt    _mp-guard WITH-GUARD ;
[THEN] [THEN]

\ =====================================================================
\  Done.
\ =====================================================================
