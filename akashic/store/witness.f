\ =================================================================
\  witness.f  —  State Transition Witness
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: WIT-  / _WIT-
\  Depends on: sha3.f tx.f state.f (which pulls smt.f)
\
\  Captures which accounts a block touches, their before/after
\  values, and anchors pre-values to the pre-state SMT root.
\  This is the "prove-the-delta" data layer that decouples the
\  STARK trace from total state size.
\
\  Consumers:
\    consensus.f  — STARK overlay fills trace rows from entries
\    light.f      — block-level state proofs for light clients
\    sync.f       — ship witness + proof instead of replaying
\    vm.f         — contract state accesses produce entries
\
\  Witness entry layout (72 bytes, XMEM):
\    +0   32 bytes  address       (SHA3-256 of pubkey)
\    +32   8 bytes  pre_balance
\    +40   8 bytes  pre_nonce
\    +48   8 bytes  post_balance
\    +56   8 bytes  post_nonce
\    +64   8 bytes  flags         (bit 0 = CREATED)
\
\  Public API:
\   WIT-INIT         ( -- flag )           allocate buffers
\   WIT-DESTROY      ( -- )                free buffers
\   WIT-BEGIN        ( -- )                snapshot pre-state, clear
\   WIT-END          ( -- )                compute post-root
\   WIT-APPLY-TX     ( tx -- flag )        record + apply tx
\   WIT-COUNT        ( -- n )              touched account count
\   WIT-ENTRY        ( idx -- addr )       entry XMEM address
\   WIT-PRE-ROOT     ( -- addr )           32-byte pre-root
\   WIT-POST-ROOT    ( -- addr )           32-byte post-root
\   WIT-CREATED?     ( idx -- flag )       was account new?
\   WIT-PROVE-BEGIN  ( -- )                save post, restore pre
\   WIT-PROVE        ( idx proof -- len )  SMT proof for entry
\   WIT-PROVE-END    ( -- )                restore post-state
\   WIT-VERIFY       ( -- flag )           check consistency
\
\  *** CONVENTION: Inside DO..LOOP, never use R@ to access
\      values pushed before the loop.  Use a VARIABLE instead.
\
\  Not reentrant.
\ =================================================================

REQUIRE sha3.f
REQUIRE tx.f
REQUIRE state.f

PROVIDED akashic-witness

\ =====================================================================
\  1. Constants
\ =====================================================================

  72 CONSTANT WIT-ENTRY-SIZE        \ bytes per witness entry
 512 CONSTANT WIT-MAX-ENTRIES       \ max touched accounts per block
   1 CONSTANT _WIT-FL-CREATED       \ flag: account was new

WIT-MAX-ENTRIES WIT-ENTRY-SIZE * CONSTANT _WIT-BUF-SIZE   \ 36864 bytes

\ Field offsets within witness entry
 0 CONSTANT _WIT-OFF-ADDR
32 CONSTANT _WIT-OFF-PRE-BAL
40 CONSTANT _WIT-OFF-PRE-NONCE
48 CONSTANT _WIT-OFF-POST-BAL
56 CONSTANT _WIT-OFF-POST-NONCE
64 CONSTANT _WIT-OFF-FLAGS

\ =====================================================================
\  2. Storage
\ =====================================================================

\ XMEM entry buffer (allocated by WIT-INIT)
VARIABLE _WIT-BUF-PTR
0 _WIT-BUF-PTR !

\ XMEM pre-state snapshot (allocated by WIT-INIT)
VARIABLE _WIT-PRE-SNAP-PTR
0 _WIT-PRE-SNAP-PTR !

\ XMEM temp snapshot for prove/verify (lazy-allocated)
VARIABLE _WIT-TMP-SNAP-PTR
0 _WIT-TMP-SNAP-PTR !

\ Roots
CREATE _WIT-PRE-ROOT  32 ALLOT
CREATE _WIT-POST-ROOT 32 ALLOT

\ Counters / flags
VARIABLE _WIT-COUNT
VARIABLE _WIT-ACTIVE     \ -1 if between WIT-BEGIN .. WIT-END

\ Scratch for address hashing
CREATE _WIT-HASH-S 32 ALLOT       \ sender address
CREATE _WIT-HASH-R 32 ALLOT       \ recipient address

\ Stashed pre-values (used by WIT-APPLY-TX)
VARIABLE _WIT-S-BAL
VARIABLE _WIT-S-NONCE
VARIABLE _WIT-R-BAL
VARIABLE _WIT-R-NONCE
VARIABLE _WIT-R-NEW

\ Scratch for XMEM→RAM address copy (prove/verify)
CREATE _WIT-PRV-ADDR 32 ALLOT

\ [FIX D05] Hash table for O(1) address lookup
\ 1024 buckets, open-addressed, linear probing.
\ Each bucket holds an entry index (0..511) or -1 (empty).
1024 CONSTANT _WIT-HT-SIZE
_WIT-HT-SIZE 1- CONSTANT _WIT-HT-MASK
CREATE _WIT-HT  _WIT-HT-SIZE CELLS ALLOT

: _WIT-HT-CLEAR  ( -- )
    _WIT-HT _WIT-HT-SIZE CELLS 255 FILL ;

\ =====================================================================
\  3. WIT-INIT / WIT-DESTROY
\ =====================================================================

: WIT-INIT  ( -- flag )
    \ Allocate entry buffer
    _WIT-BUF-PTR @ 0= IF
        _WIT-BUF-SIZE XMEM-ALLOT DUP 0= IF EXIT THEN
        _WIT-BUF-PTR !
    THEN
    \ Allocate pre-state snapshot buffer
    _WIT-PRE-SNAP-PTR @ 0= IF
        ST-SNAPSHOT-SIZE XMEM-ALLOT DUP 0= IF EXIT THEN
        _WIT-PRE-SNAP-PTR !
    THEN
    0 _WIT-COUNT !
    0 _WIT-ACTIVE !
    _WIT-HT-CLEAR
    _WIT-PRE-ROOT 32 0 FILL
    _WIT-POST-ROOT 32 0 FILL
    -1 ;

: WIT-DESTROY  ( -- )
    _WIT-BUF-PTR @ ?DUP IF
        _WIT-BUF-SIZE XMEM-FREE-BLOCK
        0 _WIT-BUF-PTR !
    THEN
    _WIT-PRE-SNAP-PTR @ ?DUP IF
        ST-SNAPSHOT-SIZE XMEM-FREE-BLOCK
        0 _WIT-PRE-SNAP-PTR !
    THEN
    _WIT-TMP-SNAP-PTR @ ?DUP IF
        ST-SNAPSHOT-SIZE XMEM-FREE-BLOCK
        0 _WIT-TMP-SNAP-PTR !
    THEN
    0 _WIT-COUNT !
    0 _WIT-ACTIVE ! ;

\ =====================================================================
\  4. WIT-BEGIN / WIT-END
\ =====================================================================

: WIT-BEGIN  ( -- )
    0 _WIT-COUNT !
    _WIT-HT-CLEAR
    _WIT-BUF-PTR @ _WIT-BUF-SIZE 0 FILL
    \ Capture pre-state snapshot
    _WIT-PRE-SNAP-PTR @ ST-SNAPSHOT
    \ Capture pre-state root
    ST-ROOT _WIT-PRE-ROOT 32 CMOVE
    _WIT-POST-ROOT 32 0 FILL
    -1 _WIT-ACTIVE ! ;

: WIT-END  ( -- )
    \ Capture post-state root
    ST-ROOT _WIT-POST-ROOT 32 CMOVE
    0 _WIT-ACTIVE ! ;

\ =====================================================================
\  5. Entry addressing
\ =====================================================================

\ _WIT-ENTRY-ADDR ( idx -- addr )  XMEM address of entry.
: _WIT-ENTRY-ADDR  ( idx -- addr )
    WIT-ENTRY-SIZE * _WIT-BUF-PTR @ + ;

\ =====================================================================
\  6. _WIT-FIND — O(1) hash-table lookup  [FIX D05]
\ =====================================================================
\  ( addr -- idx | -1 )
\  Hashes first 8 bytes of the 32-byte address, probes the
\  1024-bucket open-addressed table.  Falls back to -1 on miss.

VARIABLE _WIT-FIND-ADDR

: _WIT-CMP32  ( a b -- flag )
    32 0 DO
        OVER I + C@ OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ Hash: read first cell of 32-byte address, mask to bucket index.
: _WIT-HT-HASH  ( addr -- bucket )
    @ _WIT-HT-MASK AND ;

: _WIT-FIND  ( addr -- idx | -1 )
    _WIT-FIND-ADDR !
    _WIT-FIND-ADDR @ _WIT-HT-HASH      ( bucket )
    _WIT-HT-SIZE 0 DO
        DUP CELLS _WIT-HT + @           ( bucket idx-or-neg1 )
        DUP -1 = IF                      \ empty slot → not found
            NIP UNLOOP EXIT              ( -1 )
        THEN
        \ Compare entry's address against query
        DUP _WIT-ENTRY-ADDR _WIT-PRV-ADDR 32 CMOVE
        _WIT-FIND-ADDR @ _WIT-PRV-ADDR _WIT-CMP32 IF
            NIP UNLOOP EXIT              ( idx )
        THEN
        DROP
        1+ _WIT-HT-MASK AND             \ wrap to next bucket
    LOOP
    DROP -1 ;

\ Insert entry idx into hash table.  addr is the 32-byte key in RAM.
: _WIT-HT-INSERT  ( idx addr -- )
    _WIT-HT-HASH                         ( idx bucket )
    _WIT-HT-SIZE 0 DO
        DUP CELLS _WIT-HT + @ -1 = IF
            CELLS _WIT-HT + !            ( -- )
            UNLOOP EXIT
        THEN
        1+ _WIT-HT-MASK AND
    LOOP
    2DROP ;                              \ table full — should never happen

\ =====================================================================
\  7. _WIT-RECORD — add or skip entry
\ =====================================================================
\  ( addr pre-bal pre-nonce created? -- )
\  If address already in entries, skip (pre-values already captured).
\  Otherwise append new entry.

VARIABLE _WIT-REC-ADDR
VARIABLE _WIT-REC-BAL
VARIABLE _WIT-REC-NONCE
VARIABLE _WIT-REC-NEW
VARIABLE _WIT-REC-ENT

\ [FIX C09] Returns flag: -1=ok, 0=overflow (was silent EXIT).
: _WIT-RECORD  ( addr pre-bal pre-nonce created? -- flag )
    _WIT-REC-NEW !
    _WIT-REC-NONCE !
    _WIT-REC-BAL !
    _WIT-REC-ADDR !
    \ Check if already tracked — not an error, just a no-op
    _WIT-REC-ADDR @ _WIT-FIND -1 <> IF -1 EXIT THEN
    \ Check capacity — this is the overflow error
    _WIT-COUNT @ WIT-MAX-ENTRIES >= IF 0 EXIT THEN
    \ Append new entry
    _WIT-COUNT @ _WIT-ENTRY-ADDR _WIT-REC-ENT !
    _WIT-REC-ENT @ WIT-ENTRY-SIZE 0 FILL
    \ Copy address
    _WIT-REC-ADDR @ _WIT-REC-ENT @ 32 CMOVE
    \ Write pre-values
    _WIT-REC-BAL @   _WIT-REC-ENT @ _WIT-OFF-PRE-BAL + !
    _WIT-REC-NONCE @ _WIT-REC-ENT @ _WIT-OFF-PRE-NONCE + !
    \ Initialize post = pre (default until updated)
    _WIT-REC-BAL @   _WIT-REC-ENT @ _WIT-OFF-POST-BAL + !
    _WIT-REC-NONCE @ _WIT-REC-ENT @ _WIT-OFF-POST-NONCE + !
    \ Write flags
    _WIT-REC-NEW @ IF
        _WIT-FL-CREATED _WIT-REC-ENT @ _WIT-OFF-FLAGS + !
    ELSE
        0 _WIT-REC-ENT @ _WIT-OFF-FLAGS + !
    THEN
    \ [FIX D05] Insert into hash table
    _WIT-COUNT @  _WIT-REC-ADDR @  _WIT-HT-INSERT
    _WIT-COUNT @ 1+ _WIT-COUNT !
    -1 ;

\ =====================================================================
\  8. _WIT-UPDATE-POST — refresh post-values from current state
\ =====================================================================
\  ( addr -- )
\  Find entry, read current balance/nonce from state table.

VARIABLE _WIT-UP-ADDR
VARIABLE _WIT-UP-ENT

: _WIT-UPDATE-POST  ( addr -- )
    _WIT-UP-ADDR !
    _WIT-UP-ADDR @ _WIT-FIND
    DUP -1 = IF DROP EXIT THEN
    _WIT-ENTRY-ADDR _WIT-UP-ENT !
    _WIT-UP-ADDR @ ST-BALANCE@ _WIT-UP-ENT @ _WIT-OFF-POST-BAL + !
    _WIT-UP-ADDR @ ST-NONCE@   _WIT-UP-ENT @ _WIT-OFF-POST-NONCE + ! ;

\ =====================================================================
\  9. WIT-APPLY-TX — record pre/post values + apply tx
\ =====================================================================
\  Stash pre-values before ST-APPLY-TX.
\  Commit witness entries only on success.

VARIABLE _WIT-TX

: WIT-APPLY-TX  ( tx -- flag )
    _WIT-TX !
    \ 1. Derive sender address (hash pubkey)
    _WIT-TX @ TX-FROM@ ED25519-KEY-LEN _WIT-HASH-S SHA3-256-HASH
    \ 2. Stash sender pre-values
    _WIT-HASH-S ST-BALANCE@ _WIT-S-BAL !
    _WIT-HASH-S ST-NONCE@   _WIT-S-NONCE !
    \ 3. Derive recipient address
    _WIT-TX @ TX-TO@ ED25519-KEY-LEN _WIT-HASH-R SHA3-256-HASH
    \ 4. Stash recipient pre-values
    _WIT-HASH-R ST-LOOKUP DUP 0<> IF
        _ST-OFF-BAL + @ _WIT-R-BAL !
        _WIT-HASH-R ST-NONCE@ _WIT-R-NONCE !
        0 _WIT-R-NEW !
    ELSE
        DROP
        0 _WIT-R-BAL !
        0 _WIT-R-NONCE !
        -1 _WIT-R-NEW !
    THEN
    \ 5. Apply the actual transaction
    _WIT-TX @ ST-APPLY-TX
    DUP 0= IF EXIT THEN           \ failed — no entries recorded
    DROP
    \ === Success — commit witness entries ===
    \ 6. Record sender (existing account, created?=0)
    _WIT-HASH-S _WIT-S-BAL @ _WIT-S-NONCE @ 0 _WIT-RECORD
    0= IF 0 EXIT THEN                 \ [FIX C09] overflow
    \ 7. Check for self-transfer (sender = recipient)
    _WIT-HASH-S _WIT-HASH-R _WIT-CMP32 IF
        \ Self-transfer: only sender entry needed, update post
        _WIT-HASH-S _WIT-UPDATE-POST
        -1 EXIT
    THEN
    \ 8. Record recipient
    _WIT-HASH-R _WIT-R-BAL @ _WIT-R-NONCE @ _WIT-R-NEW @ _WIT-RECORD
    0= IF 0 EXIT THEN                 \ [FIX C09] overflow
    \ 9. Update post-values from current state
    _WIT-HASH-S _WIT-UPDATE-POST
    _WIT-HASH-R _WIT-UPDATE-POST
    -1 ;

\ =====================================================================
\  10. Public accessors
\ =====================================================================

: WIT-COUNT      ( -- n )    _WIT-COUNT @ ;
: WIT-ENTRY      ( idx -- addr )  _WIT-ENTRY-ADDR ;
: WIT-PRE-ROOT   ( -- addr )  _WIT-PRE-ROOT ;
: WIT-POST-ROOT  ( -- addr )  _WIT-POST-ROOT ;

: WIT-CREATED?   ( idx -- flag )
    _WIT-ENTRY-ADDR _WIT-OFF-FLAGS + @
    _WIT-FL-CREATED AND 0<> ;

\ =====================================================================
\  11. WIT-PROVE bracket — generate SMT proofs against pre-state
\ =====================================================================
\  WIT-PROVE-BEGIN saves the post-state, restores the pre-state.
\  WIT-PROVE generates a proof for one entry.
\  WIT-PROVE-END restores the post-state.

: _WIT-ENSURE-TMP-SNAP  ( -- )
    _WIT-TMP-SNAP-PTR @ 0= IF
        ST-SNAPSHOT-SIZE XMEM-ALLOT _WIT-TMP-SNAP-PTR !
    THEN ;

: WIT-PROVE-BEGIN  ( -- )
    _WIT-ENSURE-TMP-SNAP
    \ Save current (post) state
    _WIT-TMP-SNAP-PTR @ ST-SNAPSHOT
    \ Restore pre-state
    _WIT-PRE-SNAP-PTR @ ST-RESTORE ;

: WIT-PROVE  ( idx proof -- len )
    SWAP _WIT-ENTRY-ADDR           ( proof entry )
    \ Copy 32-byte address from XMEM → RAM scratch
    _WIT-PRV-ADDR 32 CMOVE        ( proof )
    _WIT-PRV-ADDR SWAP             ( addr proof )
    ST-PROVE ;                     ( len )

: WIT-PROVE-END  ( -- )
    _WIT-TMP-SNAP-PTR @ ST-RESTORE ;

\ =====================================================================
\  12. WIT-VERIFY — check witness consistency
\ =====================================================================
\  Verifies:
\    1. Pre-root matches saved pre-root
\    2. Existing entries' pre-values match pre-state
\    3. CREATED entries didn't exist in pre-state
\    4. Post-root matches saved post-root
\    5. All entries' post-values match post-state
\
\  Leaves state in post-state form.
\  Does NOT verify transitions — that's the STARK's job.

VARIABLE _WIT-VF-OK
VARIABLE _WIT-VF-ENT
VARIABLE _WIT-VF-ST

: WIT-VERIFY  ( -- flag )
    -1 _WIT-VF-OK !
    _WIT-ENSURE-TMP-SNAP
    \ 1. Save current (post) state
    _WIT-TMP-SNAP-PTR @ ST-SNAPSHOT
    \ 2. Restore pre-state
    _WIT-PRE-SNAP-PTR @ ST-RESTORE
    \ 3. Verify pre-root matches
    ST-ROOT _WIT-PRE-ROOT _WIT-CMP32 0= IF
        0 _WIT-VF-OK !
    THEN
    \ 4. Verify each entry against pre-state
    _WIT-VF-OK @ IF
        _WIT-COUNT @ 0 ?DO
            I _WIT-ENTRY-ADDR _WIT-VF-ENT !
            \ Copy address to RAM
            _WIT-VF-ENT @ _WIT-PRV-ADDR 32 CMOVE
            _WIT-VF-ENT @ _WIT-OFF-FLAGS + @ _WIT-FL-CREATED AND IF
                \ CREATED: account must NOT exist in pre-state
                _WIT-PRV-ADDR ST-LOOKUP 0<> IF
                    0 _WIT-VF-OK !  LEAVE
                THEN
            ELSE
                \ Existing: account MUST exist, pre-values must match
                _WIT-PRV-ADDR ST-LOOKUP DUP 0= IF
                    DROP 0 _WIT-VF-OK !  LEAVE
                THEN
                _WIT-VF-ST !
                _WIT-VF-ENT @ _WIT-OFF-PRE-BAL + @
                _WIT-VF-ST @ _ST-OFF-BAL + @ <> IF
                    0 _WIT-VF-OK !  LEAVE
                THEN
                _WIT-VF-ENT @ _WIT-OFF-PRE-NONCE + @
                _WIT-VF-ST @ _ST-OFF-NONCE + @ <> IF
                    0 _WIT-VF-OK !  LEAVE
                THEN
            THEN
        LOOP
    THEN
    \ 5. Restore post-state
    _WIT-TMP-SNAP-PTR @ ST-RESTORE
    \ 6. Verify post-root
    _WIT-VF-OK @ IF
        ST-ROOT _WIT-POST-ROOT _WIT-CMP32 0= IF
            0 _WIT-VF-OK !
        THEN
    THEN
    \ 7. Verify each entry's post-values against post-state
    _WIT-VF-OK @ IF
        _WIT-COUNT @ 0 ?DO
            I _WIT-ENTRY-ADDR _WIT-VF-ENT !
            _WIT-VF-ENT @ _WIT-PRV-ADDR 32 CMOVE
            _WIT-PRV-ADDR ST-LOOKUP DUP 0= IF
                DROP 0 _WIT-VF-OK !  LEAVE
            THEN
            _WIT-VF-ST !
            _WIT-VF-ENT @ _WIT-OFF-POST-BAL + @
            _WIT-VF-ST @ _ST-OFF-BAL + @ <> IF
                0 _WIT-VF-OK !  LEAVE
            THEN
            _WIT-VF-ENT @ _WIT-OFF-POST-NONCE + @
            _WIT-VF-ST @ _ST-OFF-NONCE + @ <> IF
                0 _WIT-VF-OK !  LEAVE
            THEN
        LOOP
    THEN
    _WIT-VF-OK @ ;

\ =====================================================================
\  13. Concurrency guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _wit-guard

' WIT-INIT          CONSTANT _wit-init-xt
' WIT-DESTROY       CONSTANT _wit-dest-xt
' WIT-BEGIN         CONSTANT _wit-begin-xt
' WIT-END           CONSTANT _wit-end-xt
' WIT-APPLY-TX      CONSTANT _wit-apply-xt
' WIT-PROVE-BEGIN   CONSTANT _wit-pb-xt
' WIT-PROVE         CONSTANT _wit-pv-xt
' WIT-PROVE-END     CONSTANT _wit-pe-xt
' WIT-VERIFY        CONSTANT _wit-vfy-xt

: WIT-INIT          _wit-init-xt   _wit-guard WITH-GUARD ;
: WIT-DESTROY       _wit-dest-xt   _wit-guard WITH-GUARD ;
: WIT-BEGIN         _wit-begin-xt  _wit-guard WITH-GUARD ;
: WIT-END           _wit-end-xt    _wit-guard WITH-GUARD ;
: WIT-APPLY-TX      _wit-apply-xt  _wit-guard WITH-GUARD ;
: WIT-PROVE-BEGIN   _wit-pb-xt     _wit-guard WITH-GUARD ;
: WIT-PROVE         _wit-pv-xt     _wit-guard WITH-GUARD ;
: WIT-PROVE-END     _wit-pe-xt     _wit-guard WITH-GUARD ;
: WIT-VERIFY        _wit-vfy-xt    _wit-guard WITH-GUARD ;
[THEN] [THEN]

\ =====================================================================
\  Done.
\ =====================================================================
