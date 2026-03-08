\ =================================================================
\  state.f  —  Blockchain World State (Paged)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ST-  / _ST-
\  Depends on: sha3.f smt.f tx.f fmt.f
\
\  Account-based world state with Sparse Merkle Tree commitment.
\  Accounts are stored in a **paged** XMEM-backed table sorted by
\  address (SHA3-256 of Ed25519 public key) for O(log n) binary-
\  search lookup.  State root is computed via the compact Patricia
\  SMT from smt.f.
\
\  Storage layout:
\    Page directory (_ST-PGDIR): _ST-MAX-PAGES × 8 bytes in RAM.
\      Each cell holds the XMEM address of a 256-entry page, or 0
\      if that page is not yet allocated.
\    Each page: 256 × 72 = 18432 bytes in XMEM, allocated on
\      demand.  A page of 256 entries preserves STARK trace
\      alignment (one page = one trace width).
\
\  Global index i  →  page = i >> 8,  slot = i AND 255.
\  No hard account ceiling — just allocate more pages.
\
\  Account entry layout (72 bytes):
\    +0   32 bytes   address      (SHA3-256 of Ed25519 public key)
\    +32   8 bytes   balance      (u64)
\    +40   8 bytes   nonce        (u64, incremented per send)
\    +48   8 bytes   staked-amt   (reserved — Phase 5 PoS)
\    +56   8 bytes   unstake-ht   (reserved — Phase 5 PoS)
\    +64   8 bytes   last-blk     (reserved — Phase 5 PoS)
\
\  Public API:
\   ST-INIT          ( -- flag )             allocate directory, init SMT
\   ST-DESTROY       ( -- )                  free all pages + SMT
\   ST-LOOKUP        ( addr -- entry | 0 )   find account by address
\   ST-CREATE        ( addr balance -- flag ) create new account
\   ST-BALANCE@      ( addr -- balance )      read balance (0 if missing)
\   ST-NONCE@        ( addr -- nonce )        read nonce (0 if missing)
\   ST-APPLY-TX      ( tx -- flag )           validate + apply tx
\   ST-VERIFY-TX     ( tx -- flag )           validate without applying
\   ST-ROOT          ( -- addr )              compute SMT root
\   ST-PROVE         ( addr proof -- len )    generate SMT inclusion proof
\   ST-VERIFY-PROOF  ( key leaf proof len root -- flag )  verify proof
\   ST-ADDR-FROM-KEY ( pubkey addr -- )       SHA3-256 hash pubkey
\   ST-COUNT         ( -- n )                 number of active accounts
\   ST-ENTRY         ( idx -- addr )          raw entry by global index
\   ST-PRINT         ( -- )                   debug dump
\   ST-SNAPSHOT      ( dst -- )               copy directory+pages+count
\   ST-RESTORE       ( src -- )               restore from snapshot
\
\  Constants:
\   ST-MAX-ACCOUNTS  ( -- n )         _ST-MAX-PAGES × 256
\   ST-PAGE-ENTRIES  ( -- 256 )
\   ST-ENTRY-SIZE    ( -- 72 )
\   ST-ADDR-LEN      ( -- 32 )
\
\  *** CONVENTION: Inside DO..LOOP, never use R@ to access
\      values pushed before the loop.  Use a VARIABLE instead.
\
\  Not reentrant.
\ =================================================================

REQUIRE sha3.f
REQUIRE smt.f
REQUIRE tx.f
REQUIRE fmt.f

PROVIDED akashic-state

\ =====================================================================
\  1. Constants
\ =====================================================================

 256 CONSTANT ST-PAGE-ENTRIES       \ entries per page — STARK aligned
  72 CONSTANT ST-ENTRY-SIZE         \ bytes per account entry
  32 CONSTANT ST-ADDR-LEN           \ address length (SHA3-256 output)

\ Page size in bytes: 256 × 72 = 18432
ST-PAGE-ENTRIES ST-ENTRY-SIZE * CONSTANT _ST-PAGE-BYTES

\ Maximum pages.  Each page = 256 accounts.
\ **EMULATOR TESTING VALUE ONLY.**  16 pages = 4096 accounts is
\ sized for the 16 MiB XMEM emulator.  Production MUST increase
\ this to match available SDRAM — e.g. 256 pages = 65536 accounts
\ (~4.6 MB XMEM), 1024 pages = 262144 accounts (~18 MB XMEM).
\ The paging system handles any value; XMEM-ALLOT returns 0 if full.
  16 CONSTANT _ST-MAX-PAGES

_ST-MAX-PAGES ST-PAGE-ENTRIES * CONSTANT ST-MAX-ACCOUNTS

\ Field offsets within account entry (72 bytes)
 0 CONSTANT _ST-OFF-ADDR
32 CONSTANT _ST-OFF-BAL
40 CONSTANT _ST-OFF-NONCE
48 CONSTANT _ST-OFF-STAKED        \ Phase 5 PoS — zeroed until then
56 CONSTANT _ST-OFF-UNSTAKE-H     \ Phase 5 PoS — zeroed until then
64 CONSTANT _ST-OFF-LAST-BLK      \ Phase 5 PoS — zeroed until then

\ =====================================================================
\  2. Storage
\ =====================================================================

\ Page directory: _ST-MAX-PAGES cells in RAM.
\ Each cell = 8 bytes (XMEM address of page, or 0 = unallocated).
CREATE _ST-PGDIR _ST-MAX-PAGES CELLS ALLOT

\ Number of active accounts (global count across all pages)
VARIABLE _ST-COUNT

\ Number of allocated pages (for snapshot/destroy efficiency)
VARIABLE _ST-PGCNT

\ SMT tree descriptor (64 bytes)
CREATE _ST-SMT 64 ALLOT

\ Scratch buffers
CREATE _ST-HASH-A  32 ALLOT       \ sender address scratch
CREATE _ST-HASH-B  32 ALLOT       \ recipient address scratch
CREATE _ST-LEAF    32 ALLOT       \ SMT value scratch (hash of entry)

\ =====================================================================
\  3. Page management
\ =====================================================================

\ _ST-PG@ ( pg# -- xmem-addr | 0 )  Read page directory slot.
: _ST-PG@  ( pg# -- addr )
    CELLS _ST-PGDIR + @ ;

\ _ST-PG! ( xmem-addr pg# -- )  Write page directory slot.
: _ST-PG!  ( addr pg# -- )
    CELLS _ST-PGDIR + ! ;

\ _ST-PG-ALLOC ( pg# -- addr | 0 )  Allocate a new page.
\   Returns XMEM address of the new page, or 0 if XMEM full.
\   Zeroes the page.  Stores pointer in directory.
: _ST-PG-ALLOC  ( pg# -- addr )
    DUP _ST-PG@ ?DUP IF NIP EXIT THEN   \ already allocated
    _ST-PAGE-BYTES XMEM-ALLOT
    DUP 0= IF NIP EXIT THEN             \ XMEM exhausted
    DUP ROT _ST-PG!
    DUP _ST-PAGE-BYTES 0 FILL
    _ST-PGCNT @ 1+ _ST-PGCNT ! ;

\ _ST-PG-ENSURE ( pg# -- addr | 0 )
\   Return page base, allocating if needed.
: _ST-PG-ENSURE  ( pg# -- addr )
    DUP _ST-PG@ ?DUP IF NIP EXIT THEN
    _ST-PG-ALLOC ;

\ =====================================================================
\  4. Entry addressing (paged)
\ =====================================================================

\ _ST-ENTRY ( idx -- addr )
\   Global index → entry XMEM address.
\   Page = idx >> 8, slot = idx AND 255.
\   Allocates page on demand.  Returns 0 if allocation fails.
VARIABLE _st-ent-pg
VARIABLE _st-ent-slot

: _ST-ENTRY  ( idx -- addr )
    DUP 8 RSHIFT _st-ent-pg !
    255 AND _st-ent-slot !
    _st-ent-pg @ _ST-PG-ENSURE
    DUP 0= IF EXIT THEN
    _st-ent-slot @ ST-ENTRY-SIZE * + ;

\ _ST-ADDR-AT ( idx -- addr )  Address field (offset 0).
: _ST-ADDR-AT  ( idx -- addr )
    _ST-ENTRY ;

\ _ST-BAL-AT ( idx -- addr )  Balance field address.
: _ST-BAL-AT  ( idx -- addr )
    _ST-ENTRY _ST-OFF-BAL + ;

\ _ST-NONCE-AT ( idx -- addr )  Nonce field address.
: _ST-NONCE-AT  ( idx -- addr )
    _ST-ENTRY _ST-OFF-NONCE + ;

\ _ST-STAKED-AT ( idx -- addr )  Staked-amount field address.
: _ST-STAKED-AT  ( idx -- addr )
    _ST-ENTRY _ST-OFF-STAKED + ;

\ _ST-UNSTAKE-AT ( idx -- addr )  Unstake-height field address.
: _ST-UNSTAKE-AT  ( idx -- addr )
    _ST-ENTRY _ST-OFF-UNSTAKE-H + ;

\ _ST-LASTBLK-AT ( idx -- addr )  Last-block field address.
: _ST-LASTBLK-AT  ( idx -- addr )
    _ST-ENTRY _ST-OFF-LAST-BLK + ;

\ =====================================================================
\  5. Address comparison
\ =====================================================================

VARIABLE _ST-CMP-A
VARIABLE _ST-CMP-B

: _ST-ADDR-CMP  ( a b -- n )
    _ST-CMP-B !  _ST-CMP-A !
    ST-ADDR-LEN 0 ?DO
        _ST-CMP-A @ I + C@
        _ST-CMP-B @ I + C@
        2DUP < IF 2DROP -1 UNLOOP EXIT THEN
             > IF  1 UNLOOP EXIT THEN
    LOOP
    0 ;

\ =====================================================================
\  6. Binary search (global index across pages)
\ =====================================================================

VARIABLE _ST-BS-LO
VARIABLE _ST-BS-HI
VARIABLE _ST-BS-MID
VARIABLE _ST-BS-KEY

: _ST-BSEARCH  ( addr -- idx flag )
    _ST-BS-KEY !
    0 _ST-BS-LO !
    _ST-COUNT @ _ST-BS-HI !
    BEGIN
        _ST-BS-LO @ _ST-BS-HI @ <
    WHILE
        _ST-BS-LO @ _ST-BS-HI @ + 1 RSHIFT _ST-BS-MID !
        _ST-BS-KEY @ _ST-BS-MID @ _ST-ADDR-AT _ST-ADDR-CMP
        DUP 0= IF
            DROP _ST-BS-MID @ -1 EXIT
        THEN
        0< IF
            _ST-BS-MID @ _ST-BS-HI !
        ELSE
            _ST-BS-MID @ 1+ _ST-BS-LO !
        THEN
    REPEAT
    _ST-BS-LO @ 0 ;

\ =====================================================================
\  7. Cross-page shift-right
\ =====================================================================
\  _ST-SHIFT-RIGHT ( idx -- )
\    Move entries [idx..count-1] to [idx+1..count].
\    Works across page boundaries by copying one entry at a time
\    from count-1 down to idx.

VARIABLE _ST-SH-I
VARIABLE _ST-SH-IDX

: _ST-SHIFT-RIGHT  ( idx -- )
    _ST-SH-IDX !
    _ST-COUNT @ _ST-SH-IDX @ <= IF EXIT THEN
    \ Ensure the target page for the new last entry exists
    _ST-COUNT @ 8 RSHIFT _ST-PG-ENSURE DROP
    \ Copy backwards: entry[i] ← entry[i-1]  for i = count down to idx+1
    _ST-COUNT @ _ST-SH-I !
    BEGIN
        _ST-SH-I @ _ST-SH-IDX @ >
    WHILE
        _ST-SH-I @ 1- _ST-ENTRY
        _ST-SH-I @ _ST-ENTRY
        ST-ENTRY-SIZE CMOVE
        _ST-SH-I @ 1- _ST-SH-I !
    REPEAT ;

\ =====================================================================
\  8. SMT rebuild
\ =====================================================================

VARIABLE _st-rb-i   \ loop variable for rebuild — avoids R@-in-DO

: _ST-REBUILD-TREE  ( -- )
    _ST-SMT SMT-DESTROY
    _ST-SMT SMT-INIT DROP
    _ST-COUNT @ 0 ?DO
        I _ST-ENTRY ST-ENTRY-SIZE _ST-LEAF SHA3-256-HASH
        I _ST-ADDR-AT _ST-LEAF _ST-SMT SMT-INSERT DROP
    LOOP ;

\ =====================================================================
\  9. ST-INIT — zero directory, init SMT
\ =====================================================================

: ST-INIT  ( -- flag )
    _ST-PGDIR _ST-MAX-PAGES CELLS 0 FILL
    0 _ST-COUNT !
    0 _ST-PGCNT !
    _ST-SMT SMT-INIT ;

\ ST-DESTROY — free all pages + SMT
VARIABLE _st-destr-i   \ loop variable for destroy

: ST-DESTROY  ( -- )
    _ST-MAX-PAGES 0 ?DO
        I _ST-PG@ ?DUP IF
            _ST-PAGE-BYTES XMEM-FREE-BLOCK
            0 I _ST-PG!
        THEN
    LOOP
    _ST-SMT SMT-DESTROY
    0 _ST-COUNT !
    0 _ST-PGCNT ! ;

\ =====================================================================
\  10. ST-LOOKUP — find account by address
\ =====================================================================

: ST-LOOKUP  ( addr -- entry | 0 )
    _ST-BSEARCH IF
        _ST-ENTRY
    ELSE
        DROP 0
    THEN ;

\ =====================================================================
\  11. ST-ADDR-FROM-KEY — hash public key to account address
\ =====================================================================

VARIABLE _ST-AFK-DST

: ST-ADDR-FROM-KEY  ( pubkey addr -- )
    _ST-AFK-DST !
    ED25519-KEY-LEN _ST-AFK-DST @ SHA3-256-HASH ;

\ =====================================================================
\  12. ST-CREATE — create new account with initial balance
\ =====================================================================

VARIABLE _ST-CR-ADDR
VARIABLE _ST-CR-BAL
VARIABLE _ST-CR-IDX

: ST-CREATE  ( addr balance -- flag )
    _ST-CR-BAL !
    _ST-CR-ADDR !
    \ Check capacity (soft limit: max pages × 256)
    _ST-COUNT @ ST-MAX-ACCOUNTS >= IF 0 EXIT THEN
    \ Ensure page for potential new entry exists
    _ST-COUNT @ 8 RSHIFT _ST-MAX-PAGES >= IF 0 EXIT THEN
    \ Check for duplicate
    _ST-CR-ADDR @ _ST-BSEARCH IF
        DROP 0 EXIT
    THEN
    _ST-CR-IDX !
    \ Shift entries right (cross-page)
    _ST-CR-IDX @ _ST-SHIFT-RIGHT
    \ Zero the new slot
    _ST-CR-IDX @ _ST-ENTRY ST-ENTRY-SIZE 0 FILL
    \ Write address
    _ST-CR-ADDR @ _ST-CR-IDX @ _ST-ENTRY ST-ADDR-LEN CMOVE
    \ Write balance
    _ST-CR-BAL @ _ST-CR-IDX @ _ST-BAL-AT !
    \ Increment count
    _ST-COUNT @ 1+ _ST-COUNT !
    -1 ;

\ =====================================================================
\  13. Public accessors
\ =====================================================================

: ST-COUNT  ( -- n )  _ST-COUNT @ ;

: ST-ENTRY  ( idx -- addr )  _ST-ENTRY ;

: ST-BALANCE@  ( addr -- balance )
    ST-LOOKUP DUP 0= IF EXIT THEN
    _ST-OFF-BAL + @ ;

: ST-NONCE@  ( addr -- nonce )
    ST-LOOKUP DUP 0= IF EXIT THEN
    _ST-OFF-NONCE + @ ;

: ST-STAKED@  ( addr -- amount )
    ST-LOOKUP DUP 0= IF EXIT THEN
    _ST-OFF-STAKED + @ ;

: ST-UNSTAKE-H@  ( addr -- height )
    ST-LOOKUP DUP 0= IF EXIT THEN
    _ST-OFF-UNSTAKE-H + @ ;

\ =====================================================================
\  14. ST-ROOT — compute and return 32-byte SMT root
\ =====================================================================

: ST-ROOT  ( -- addr )
    _ST-REBUILD-TREE
    _ST-SMT SMT-ROOT ;

\ =====================================================================
\  15. ST-VERIFY-TX — validate transaction against current state
\ =====================================================================

VARIABLE _ST-VT-TX
VARIABLE _ST-VT-SE

: ST-VERIFY-TX  ( tx -- flag )
    _ST-VT-TX !
    _ST-VT-TX @ TX-VERIFY 0= IF 0 EXIT THEN
    _ST-VT-TX @ TX-FROM@ ED25519-KEY-LEN _ST-HASH-A SHA3-256-HASH
    _ST-HASH-A ST-LOOKUP DUP 0= IF EXIT THEN
    _ST-VT-SE !
    _ST-VT-TX @ TX-NONCE@
    _ST-VT-SE @ _ST-OFF-NONCE + @ <> IF 0 EXIT THEN
    _ST-VT-SE @ _ST-OFF-BAL + @
    _ST-VT-TX @ TX-AMOUNT@ < IF 0 EXIT THEN
    -1 ;

\ =====================================================================
\  16. Staking extension hook + height tracking
\ =====================================================================

: _ST-TX-EXT-STUB  ( tx sender-idx -- flag )  2DROP 0 ;
VARIABLE _ST-TX-EXT-XT
' _ST-TX-EXT-STUB _ST-TX-EXT-XT !

VARIABLE _ST-CUR-HEIGHT
0 _ST-CUR-HEIGHT !

VARIABLE _ST-LOCK-PERIOD
64 _ST-LOCK-PERIOD !

: ST-SET-HEIGHT  ( h -- )  _ST-CUR-HEIGHT ! ;

\ =====================================================================
\  17. ST-APPLY-TX — validate and apply transaction to state
\ =====================================================================

VARIABLE _ST-AT-TX
VARIABLE _ST-AT-S-IDX
VARIABLE _ST-AT-R-IDX
VARIABLE _ST-AT-AMT
VARIABLE _ST-AT-SELF
VARIABLE _ST-AT-R-NEW
VARIABLE _ST-AT-RBAL

: ST-APPLY-TX  ( tx -- flag )
    _ST-AT-TX !
    0 _ST-AT-R-NEW !

    \ 1. Verify signature
    _ST-AT-TX @ TX-VERIFY 0= IF 0 EXIT THEN

    \ 2. Hash sender pubkey -> address
    _ST-AT-TX @ TX-FROM@ ED25519-KEY-LEN _ST-HASH-A SHA3-256-HASH

    \ 3. Sender must exist
    _ST-HASH-A _ST-BSEARCH 0= IF DROP 0 EXIT THEN
    _ST-AT-S-IDX !

    \ 4. Nonce must match
    _ST-AT-TX @ TX-NONCE@
    _ST-AT-S-IDX @ _ST-NONCE-AT @ <> IF 0 EXIT THEN

    \ 4b. Extension dispatch for staking tx types
    _ST-AT-TX @ TX-DATA-LEN@ 1 >= IF
        _ST-AT-TX @ TX-DATA@ C@ 3 >= IF
            _ST-AT-TX @ _ST-AT-S-IDX @ _ST-TX-EXT-XT @ EXECUTE
            DUP IF
                _ST-AT-S-IDX @ _ST-NONCE-AT DUP @ 1+ SWAP !
            THEN
            EXIT
        THEN
    THEN

    \ 5. Balance >= amount
    _ST-AT-TX @ TX-AMOUNT@ _ST-AT-AMT !
    _ST-AT-S-IDX @ _ST-BAL-AT @
    _ST-AT-AMT @ < IF 0 EXIT THEN

    \ 6. Hash recipient pubkey -> address
    _ST-AT-TX @ TX-TO@ ED25519-KEY-LEN _ST-HASH-B SHA3-256-HASH

    \ 7. Self-transfer?
    _ST-HASH-A _ST-HASH-B _ST-ADDR-CMP 0= _ST-AT-SELF !
    _ST-AT-SELF @ IF
        _ST-AT-S-IDX @ _ST-NONCE-AT DUP @ 1+ SWAP !
        -1 EXIT
    THEN

    \ 8. Look up recipient
    _ST-HASH-B _ST-BSEARCH IF
        _ST-AT-R-IDX !
        \ 9. Check credit overflow
        _ST-AT-R-IDX @ _ST-BAL-AT @ _ST-AT-RBAL !
        _ST-AT-RBAL @ _ST-AT-AMT @ +
        _ST-AT-RBAL @ < IF 0 EXIT THEN
    ELSE
        _ST-AT-R-IDX !
        _ST-COUNT @ ST-MAX-ACCOUNTS >= IF 0 EXIT THEN
        _ST-COUNT @ 8 RSHIFT _ST-MAX-PAGES >= IF 0 EXIT THEN
        -1 _ST-AT-R-NEW !
    THEN

    \ --- All checks passed — apply mutations ---

    \ 10. Create recipient if new
    _ST-AT-R-NEW @ IF
        _ST-AT-R-IDX @ _ST-AT-S-IDX @ <= IF
            _ST-AT-S-IDX @ 1+ _ST-AT-S-IDX !
        THEN
        _ST-AT-R-IDX @ _ST-SHIFT-RIGHT
        _ST-AT-R-IDX @ _ST-ENTRY ST-ENTRY-SIZE 0 FILL
        _ST-HASH-B _ST-AT-R-IDX @ _ST-ENTRY ST-ADDR-LEN CMOVE
        _ST-COUNT @ 1+ _ST-COUNT !
    THEN

    \ 11. Debit sender
    _ST-AT-S-IDX @ _ST-BAL-AT DUP @ _ST-AT-AMT @ - SWAP !

    \ 12. Credit recipient
    _ST-AT-R-IDX @ _ST-BAL-AT DUP @ _ST-AT-AMT @ + SWAP !

    \ 13. Increment sender nonce
    _ST-AT-S-IDX @ _ST-NONCE-AT DUP @ 1+ SWAP !

    -1 ;

\ =====================================================================
\  18. ST-PRINT — debug dump
\ =====================================================================

: ST-PRINT  ( -- )
    ." === State: " ST-COUNT . ." accounts ===" CR
    ST-COUNT 0 ?DO
        ."  [" I . ." ] addr="
        I _ST-ADDR-AT 8 FMT-.HEX ." .."
        ."  bal=" I _ST-BAL-AT @ .
        ."  n=" I _ST-NONCE-AT @ .
        CR
    LOOP ;

\ =====================================================================
\  19. ST-SNAPSHOT / ST-RESTORE — paged snapshot
\ =====================================================================
\  Layout in snapshot buffer (XMEM):
\    +0:  8 bytes — _ST-COUNT value
\    +8:  8 bytes — _ST-PGCNT value
\    +16: _ST-MAX-PAGES × 8 — page directory copy
\    +16+dir: for each page slot 0.._ST-MAX-PAGES-1:
\      if allocated → _ST-PAGE-BYTES of page data
\      if not allocated → skipped
\
\  Fixed max size (scales with _ST-MAX-PAGES):
\    16 + _ST-MAX-PAGES×8 + _ST-MAX-PAGES×_ST-PAGE-BYTES
\  Current emulator value (16 pages): 295,056 bytes.
\  Production example  (256 pages): 4,718,736 bytes (~4.5 MB).

16 _ST-MAX-PAGES CELLS + _ST-MAX-PAGES _ST-PAGE-BYTES * + CONSTANT ST-SNAPSHOT-SIZE

VARIABLE _st-snap-ptr

: ST-SNAPSHOT  ( dst -- )
    _st-snap-ptr !
    \ Write count + pgcnt
    _ST-COUNT @ _st-snap-ptr @ !
    _ST-PGCNT @ _st-snap-ptr @ 8 + !
    \ Copy page directory
    _ST-PGDIR _st-snap-ptr @ 16 + _ST-MAX-PAGES CELLS CMOVE
    \ Copy each allocated page
    _st-snap-ptr @ 16 _ST-MAX-PAGES CELLS + +  _st-snap-ptr !
    _ST-MAX-PAGES 0 ?DO
        I _ST-PG@ ?DUP IF
            _st-snap-ptr @ _ST-PAGE-BYTES CMOVE
            _st-snap-ptr @ _ST-PAGE-BYTES + _st-snap-ptr !
        THEN
    LOOP ;

: ST-RESTORE  ( src -- )
    _st-snap-ptr !
    \ Restore count + pgcnt
    _st-snap-ptr @ @ _ST-COUNT !
    _st-snap-ptr @ 8 + @ _ST-PGCNT !
    \ Restore page directory
    _st-snap-ptr @ 16 + _ST-PGDIR _ST-MAX-PAGES CELLS CMOVE
    \ Restore each allocated page
    _st-snap-ptr @ 16 _ST-MAX-PAGES CELLS + +  _st-snap-ptr !
    _ST-MAX-PAGES 0 ?DO
        I _ST-PG@ ?DUP IF
            _st-snap-ptr @ SWAP _ST-PAGE-BYTES CMOVE
            _st-snap-ptr @ _ST-PAGE-BYTES + _st-snap-ptr !
        THEN
    LOOP ;

\ =====================================================================
\  20. ST-PROVE / ST-VERIFY-PROOF
\ =====================================================================

: ST-PROVE  ( addr proof -- len )
    SWAP
    _ST-REBUILD-TREE
    SWAP _ST-SMT SWAP SMT-PROVE ;

: ST-VERIFY-PROOF  ( key leaf proof len root -- flag )
    SMT-VERIFY ;

\ =====================================================================
\  21. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _st-guard

' ST-INIT           CONSTANT _st-init-xt
' ST-DESTROY        CONSTANT _st-dest-xt
' ST-LOOKUP         CONSTANT _st-lookup-xt
' ST-CREATE         CONSTANT _st-create-xt
' ST-BALANCE@       CONSTANT _st-bal-xt
' ST-NONCE@         CONSTANT _st-nonce-xt
' ST-STAKED@        CONSTANT _st-stk-xt
' ST-UNSTAKE-H@     CONSTANT _st-ush-xt
' ST-APPLY-TX       CONSTANT _st-apply-xt
' ST-VERIFY-TX      CONSTANT _st-verify-xt
' ST-ROOT           CONSTANT _st-root-xt
' ST-PROVE          CONSTANT _st-prove-xt
' ST-VERIFY-PROOF   CONSTANT _st-vfyp-xt
' ST-ADDR-FROM-KEY  CONSTANT _st-afk-xt
' ST-SET-HEIGHT     CONSTANT _st-seth-xt
' ST-SNAPSHOT       CONSTANT _st-snap-xt
' ST-RESTORE        CONSTANT _st-rest-xt

: ST-INIT           _st-init-xt    _st-guard WITH-GUARD ;
: ST-DESTROY        _st-dest-xt   _st-guard WITH-GUARD ;
: ST-LOOKUP         _st-lookup-xt  _st-guard WITH-GUARD ;
: ST-CREATE         _st-create-xt  _st-guard WITH-GUARD ;
: ST-BALANCE@       _st-bal-xt     _st-guard WITH-GUARD ;
: ST-NONCE@         _st-nonce-xt   _st-guard WITH-GUARD ;
: ST-STAKED@        _st-stk-xt    _st-guard WITH-GUARD ;
: ST-UNSTAKE-H@     _st-ush-xt    _st-guard WITH-GUARD ;
: ST-APPLY-TX       _st-apply-xt   _st-guard WITH-GUARD ;
: ST-VERIFY-TX      _st-verify-xt  _st-guard WITH-GUARD ;
: ST-ROOT           _st-root-xt    _st-guard WITH-GUARD ;
: ST-PROVE          _st-prove-xt   _st-guard WITH-GUARD ;
: ST-VERIFY-PROOF   _st-vfyp-xt   _st-guard WITH-GUARD ;
: ST-ADDR-FROM-KEY  _st-afk-xt    _st-guard WITH-GUARD ;
: ST-SET-HEIGHT     _st-seth-xt   _st-guard WITH-GUARD ;
: ST-SNAPSHOT       _st-snap-xt    _st-guard WITH-GUARD ;
: ST-RESTORE        _st-rest-xt    _st-guard WITH-GUARD ;

\ =====================================================================
\  Done.
\ =====================================================================
