\ =================================================================
\  state.f  —  Blockchain World State
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ST-  / _ST-
\  Depends on: sha3.f merkle.f tx.f fmt.f
\
\  Account-based world state with 256-leaf SHA3-256 Merkle
\  commitment.  Accounts are sorted by address (SHA3-256 of the
\  Ed25519 public key) for O(log n) binary-search lookup.
\
\  Account entry layout (72 bytes):
\    +0   32 bytes   address      (SHA3-256 of Ed25519 public key)
\    +32   8 bytes   balance      (u64)
\    +40   8 bytes   nonce        (u64, incremented per send)
\    +48   8 bytes   staked-amt   (reserved — Phase 5 PoS)
\    +56   8 bytes   unstake-ht   (reserved — Phase 5 PoS)
\    +64   8 bytes   last-blk     (reserved — Phase 5 PoS)
\
\  Phase 5 staking fields are allocated now (72-byte entries from
\  day one) but zeroed and ignored until consensus.f adds PoS
\  logic.  This avoids a structural migration when PoS lands.
\
\  Public API:
\   ST-INIT          ( -- )                  zero state, rebuild tree
\   ST-LOOKUP        ( addr -- entry | 0 )   find account by address
\   ST-CREATE        ( addr balance -- flag ) create new account
\   ST-BALANCE@      ( addr -- balance )      read balance (0 if missing)
\   ST-NONCE@        ( addr -- nonce )        read nonce (0 if missing)
\   ST-APPLY-TX      ( tx -- flag )           validate + apply tx
\   ST-VERIFY-TX     ( tx -- flag )           validate without applying
\   ST-ROOT          ( -- addr )              compute Merkle root
\   ST-ADDR-FROM-KEY ( pubkey addr -- )       SHA3-256 hash pubkey
\   ST-COUNT         ( -- n )                 number of active accounts
\   ST-ENTRY         ( idx -- addr )          raw entry by index
\   ST-PRINT         ( -- )                   debug dump
\   ST-SNAPSHOT      ( dst -- )               copy table+count to buffer
\   ST-RESTORE       ( src -- )               restore table+count from buffer
\
\  Constants:
\   ST-MAX-ACCOUNTS  ( -- 256 )
\   ST-ENTRY-SIZE    ( -- 72 )
\   ST-ADDR-LEN      ( -- 32 )
\
\  Not reentrant.
\ =================================================================

REQUIRE sha3.f
REQUIRE merkle.f
REQUIRE tx.f
REQUIRE fmt.f

PROVIDED akashic-state

\ =====================================================================
\  1. Constants
\ =====================================================================

256 CONSTANT ST-MAX-ACCOUNTS
 72 CONSTANT ST-ENTRY-SIZE
 32 CONSTANT ST-ADDR-LEN

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

\ Account table: 256 x 72 = 18,432 bytes, sorted by address
CREATE _ST-TABLE  ST-MAX-ACCOUNTS ST-ENTRY-SIZE * ALLOT

\ Number of active accounts
VARIABLE _ST-COUNT

\ 256-leaf Merkle tree for state commitment
256 MERKLE-TREE _ST-TREE

\ Scratch buffers
CREATE _ST-HASH-A  32 ALLOT       \ sender address scratch
CREATE _ST-HASH-B  32 ALLOT       \ recipient address scratch
CREATE _ST-LEAF    32 ALLOT       \ Merkle leaf hash scratch

\ =====================================================================
\  3. Internal helpers — entry field access
\ =====================================================================

\ _ST-ENTRY ( idx -- addr )  Base address of entry at index.
: _ST-ENTRY  ( idx -- addr )
    ST-ENTRY-SIZE * _ST-TABLE + ;

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
\  4. Address comparison
\ =====================================================================
\  _ST-ADDR-CMP ( a b -- n )
\    Byte-by-byte comparison of 32-byte addresses.
\    Returns: -1 if a < b, 0 if a = b, +1 if a > b.

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
\  5. Binary search
\ =====================================================================
\  _ST-BSEARCH ( addr -- idx flag )
\    Search sorted table for 32-byte address.
\    TRUE (-1):  exact match at idx.
\    FALSE (0):  not found; idx = insertion point.

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
            DROP _ST-BS-MID @ -1 EXIT    \ found
        THEN
        0< IF
            _ST-BS-MID @ _ST-BS-HI !     \ key < mid, go left
        ELSE
            _ST-BS-MID @ 1+ _ST-BS-LO !  \ key > mid, go right
        THEN
    REPEAT
    _ST-BS-LO @ 0 ;                      \ not found

\ =====================================================================
\  6. Sorted insertion — shift entries right by one
\ =====================================================================
\  _ST-SHIFT-RIGHT ( idx -- )
\    Move entries [idx..count-1] to [idx+1..count].
\    Iterates from count down to idx+1 to avoid overlap.

VARIABLE _ST-SH-I
VARIABLE _ST-SH-IDX

: _ST-SHIFT-RIGHT  ( idx -- )
    _ST-SH-IDX !
    _ST-COUNT @ _ST-SH-IDX @ <= IF EXIT THEN   \ nothing to shift
    _ST-COUNT @ _ST-SH-I !                      \ i = count (one past end)
    BEGIN
        _ST-SH-I @ _ST-SH-IDX @ >               \ while i > idx
    WHILE
        _ST-SH-I @ 1- _ST-ENTRY                 \ src = entry[i-1]
        _ST-SH-I @ _ST-ENTRY                    \ dst = entry[i]
        ST-ENTRY-SIZE CMOVE                      \ copy forward (no overlap)
        _ST-SH-I @ 1- _ST-SH-I !               \ i--
    REPEAT ;

\ =====================================================================
\  7. Merkle tree rebuild
\ =====================================================================
\  Hash each active account entry into its Merkle leaf slot.
\  Unused slots get a zero hash (consistent empty commitment).

: _ST-REBUILD-TREE  ( -- )
    \ Zero all 256 leaves
    _ST-LEAF 32 0 FILL
    ST-MAX-ACCOUNTS 0 ?DO
        _ST-LEAF I _ST-TREE MERKLE-LEAF!
    LOOP
    \ Hash active entries into their leaf slots
    _ST-COUNT @ 0 ?DO
        I _ST-ENTRY ST-ENTRY-SIZE _ST-LEAF SHA3-256-HASH
        _ST-LEAF I _ST-TREE MERKLE-LEAF!
    LOOP
    _ST-TREE MERKLE-BUILD ;

\ =====================================================================
\  8. ST-INIT — zero all accounts, rebuild Merkle tree
\ =====================================================================

: ST-INIT  ( -- )
    _ST-TABLE ST-MAX-ACCOUNTS ST-ENTRY-SIZE * 0 FILL
    0 _ST-COUNT !
    _ST-REBUILD-TREE ;

\ =====================================================================
\  9. ST-LOOKUP — find account by address
\ =====================================================================
\  addr = 32-byte address (already hashed).
\  Returns entry address or 0 if not found.

: ST-LOOKUP  ( addr -- entry | 0 )
    _ST-BSEARCH IF
        _ST-ENTRY
    ELSE
        DROP 0
    THEN ;

\ =====================================================================
\  10. ST-ADDR-FROM-KEY — hash public key to account address
\ =====================================================================
\  Convenience helper: SHA3-256(pubkey) → 32-byte address.
\  Use before ST-CREATE, ST-LOOKUP, ST-BALANCE@, ST-NONCE@.

VARIABLE _ST-AFK-DST

: ST-ADDR-FROM-KEY  ( pubkey addr -- )
    _ST-AFK-DST !
    ED25519-KEY-LEN _ST-AFK-DST @ SHA3-256-HASH ;

\ =====================================================================
\  11. ST-CREATE — create new account with initial balance
\ =====================================================================
\  addr = 32-byte address (already hashed).
\  Returns TRUE on success, FALSE if table full or address exists.

VARIABLE _ST-CR-ADDR
VARIABLE _ST-CR-BAL
VARIABLE _ST-CR-IDX

: ST-CREATE  ( addr balance -- flag )
    _ST-CR-BAL !
    _ST-CR-ADDR !
    \ Check capacity
    _ST-COUNT @ ST-MAX-ACCOUNTS >= IF 0 EXIT THEN
    \ Check for duplicate
    _ST-CR-ADDR @ _ST-BSEARCH IF
        DROP 0 EXIT                       \ already exists
    THEN
    _ST-CR-IDX !                          \ save insertion point
    \ Shift entries right to make room
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
\  12. Public accessors
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
\  13. ST-ROOT — compute and return 32-byte Merkle root
\ =====================================================================
\  Rebuilds the full tree from current state.  Call once per block
\  finalization, not after every transaction.

: ST-ROOT  ( -- addr )
    _ST-REBUILD-TREE
    _ST-TREE MERKLE-ROOT ;

\ =====================================================================
\  14. ST-VERIFY-TX — validate transaction against current state
\ =====================================================================
\  Checks: signature valid, sender exists, nonce matches, balance
\  sufficient.  Does NOT modify state.

VARIABLE _ST-VT-TX
VARIABLE _ST-VT-SE

: ST-VERIFY-TX  ( tx -- flag )
    _ST-VT-TX !
    \ 1. Signature valid?
    _ST-VT-TX @ TX-VERIFY 0= IF 0 EXIT THEN
    \ 2. Hash sender pubkey -> address
    _ST-VT-TX @ TX-FROM@ ED25519-KEY-LEN _ST-HASH-A SHA3-256-HASH
    \ 3. Sender must exist
    _ST-HASH-A ST-LOOKUP DUP 0= IF EXIT THEN
    _ST-VT-SE !
    \ 4. Nonce must match
    _ST-VT-TX @ TX-NONCE@
    _ST-VT-SE @ _ST-OFF-NONCE + @ <> IF 0 EXIT THEN
    \ 5. Balance >= amount
    _ST-VT-SE @ _ST-OFF-BAL + @
    _ST-VT-TX @ TX-AMOUNT@ < IF 0 EXIT THEN
    -1 ;

\ =====================================================================
\  15. Staking extension hook + height tracking
\ =====================================================================
\  _ST-TX-EXT-XT: Extension handler for non-transfer tx types.
\    Signature: ( tx sender-idx -- flag )
\    Called when data_len >= 1 and data[0] >= 3.
\    If handler returns TRUE, caller bumps nonce.
\
\  _ST-CUR-HEIGHT: Current block height (set by BLK-FINALIZE or
\    consensus before tx application).  Used by unstaking to compute
\    lock expiry.
\
\  _ST-LOCK-PERIOD: Number of blocks before unstaking completes.
\    Default 64; consensus.f may overwrite at load time.

: _ST-TX-EXT-STUB  ( tx sender-idx -- flag )  2DROP 0 ;
VARIABLE _ST-TX-EXT-XT
' _ST-TX-EXT-STUB _ST-TX-EXT-XT !

VARIABLE _ST-CUR-HEIGHT
0 _ST-CUR-HEIGHT !

VARIABLE _ST-LOCK-PERIOD
64 _ST-LOCK-PERIOD !

: ST-SET-HEIGHT  ( h -- )  _ST-CUR-HEIGHT ! ;

\ =====================================================================
\  16. ST-APPLY-TX — validate and apply transaction to state
\ =====================================================================
\  Full validation followed by state mutation.
\  On success: sender debited, recipient credited, nonce bumped.
\  On failure: no state change (all checks done before mutation).
\
\  The sender/recipient pointer-invalidation problem (inserting a
\  new recipient can shift the sender's table position) is handled
\  by working with indices and adjusting the sender index when the
\  recipient insertion point precedes it.

VARIABLE _ST-AT-TX
VARIABLE _ST-AT-S-IDX        \ sender table index
VARIABLE _ST-AT-R-IDX        \ recipient table index (or insertion pt)
VARIABLE _ST-AT-AMT          \ transfer amount
VARIABLE _ST-AT-SELF         \ self-transfer flag
VARIABLE _ST-AT-R-NEW        \ TRUE if recipient must be created
VARIABLE _ST-AT-RBAL         \ recipient old balance (overflow check)

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
    \     If data_len >= 1 and data[0] >= 3, call extension handler.
    \     Handler returns flag; if TRUE we bump nonce and return.
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

    \ 7. Self-transfer? (sender address = recipient address)
    _ST-HASH-A _ST-HASH-B _ST-ADDR-CMP 0= _ST-AT-SELF !
    _ST-AT-SELF @ IF
        \ Amount cancels out, just bump nonce
        _ST-AT-S-IDX @ _ST-NONCE-AT DUP @ 1+ SWAP !
        -1 EXIT
    THEN

    \ 8. Look up recipient
    _ST-HASH-B _ST-BSEARCH IF
        \ Recipient exists — save index
        _ST-AT-R-IDX !
        \ 9. Check credit overflow (unsigned: new < old means wrap)
        _ST-AT-R-IDX @ _ST-BAL-AT @ _ST-AT-RBAL !
        _ST-AT-RBAL @ _ST-AT-AMT @ +
        _ST-AT-RBAL @ < IF 0 EXIT THEN   \ wrapped -> overflow
    ELSE
        \ Recipient not found — will create
        _ST-AT-R-IDX !                    \ save insertion point
        _ST-COUNT @ ST-MAX-ACCOUNTS >= IF 0 EXIT THEN
        -1 _ST-AT-R-NEW !
    THEN

    \ ---  All checks passed — apply mutations  ---

    \ 10. Create recipient if new
    _ST-AT-R-NEW @ IF
        \ If insertion point <= sender index, sender shifts right
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
\  16. ST-PRINT — debug dump of all active accounts
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
\  17. ST-SNAPSHOT / ST-RESTORE — for non-destructive block validation
\ =====================================================================
\  Snapshot = full account table (256 x 72 = 18,432 bytes) + count cell.
\  Total snapshot size: 18,440 bytes.
\  Used by BLK-VERIFY to apply txs tentatively, check state root,
\  then restore the original state.

18440 CONSTANT ST-SNAPSHOT-SIZE

: ST-SNAPSHOT  ( dst -- )
    DUP _ST-TABLE SWAP ST-MAX-ACCOUNTS ST-ENTRY-SIZE * CMOVE
    ST-MAX-ACCOUNTS ST-ENTRY-SIZE * +      \ point past table data
    _ST-COUNT @ SWAP ! ;

: ST-RESTORE  ( src -- )
    DUP _ST-TABLE ST-MAX-ACCOUNTS ST-ENTRY-SIZE * CMOVE
    ST-MAX-ACCOUNTS ST-ENTRY-SIZE * +      \ point past table data
    @ _ST-COUNT ! ;

\ =====================================================================
\  18. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _st-guard

' ST-INIT           CONSTANT _st-init-xt
' ST-LOOKUP         CONSTANT _st-lookup-xt
' ST-CREATE         CONSTANT _st-create-xt
' ST-BALANCE@       CONSTANT _st-bal-xt
' ST-NONCE@         CONSTANT _st-nonce-xt
' ST-STAKED@        CONSTANT _st-stk-xt
' ST-UNSTAKE-H@     CONSTANT _st-ush-xt
' ST-APPLY-TX       CONSTANT _st-apply-xt
' ST-VERIFY-TX      CONSTANT _st-verify-xt
' ST-ROOT           CONSTANT _st-root-xt
' ST-ADDR-FROM-KEY  CONSTANT _st-afk-xt
' ST-SET-HEIGHT     CONSTANT _st-seth-xt
' ST-SNAPSHOT       CONSTANT _st-snap-xt
' ST-RESTORE        CONSTANT _st-rest-xt

: ST-INIT           _st-init-xt    _st-guard WITH-GUARD ;
: ST-LOOKUP         _st-lookup-xt  _st-guard WITH-GUARD ;
: ST-CREATE         _st-create-xt  _st-guard WITH-GUARD ;
: ST-BALANCE@       _st-bal-xt     _st-guard WITH-GUARD ;
: ST-NONCE@         _st-nonce-xt   _st-guard WITH-GUARD ;
: ST-STAKED@        _st-stk-xt    _st-guard WITH-GUARD ;
: ST-UNSTAKE-H@     _st-ush-xt    _st-guard WITH-GUARD ;
: ST-APPLY-TX       _st-apply-xt   _st-guard WITH-GUARD ;
: ST-VERIFY-TX      _st-verify-xt  _st-guard WITH-GUARD ;
: ST-ROOT           _st-root-xt    _st-guard WITH-GUARD ;
: ST-ADDR-FROM-KEY  _st-afk-xt    _st-guard WITH-GUARD ;
: ST-SET-HEIGHT     _st-seth-xt   _st-guard WITH-GUARD ;
: ST-SNAPSHOT       _st-snap-xt    _st-guard WITH-GUARD ;
: ST-RESTORE        _st-rest-xt    _st-guard WITH-GUARD ;

\ =====================================================================
\  Done.
\ =====================================================================
