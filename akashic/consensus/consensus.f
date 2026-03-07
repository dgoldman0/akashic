\ =================================================================
\  consensus.f  —  Consensus Mechanism
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: CON-  / _CON-
\  Depends on: block.f state.f ed25519.f sha3.f guard.f
\              random.f (Stage B: PoS leader selection)
\
\  Three leader-election modes + orthogonal STARK overlay:
\    Mode 0 (PoW) — Proof of Work (nonce mining)
\    Mode 1 (PoA) — Proof of Authority (authorized signers)
\    Mode 2 (PoS) — Proof of Stake (validator election)
\    STARK flag   — orthogonal validity proof overlay
\
\  Proof field layout per mode (inside 128-byte BLK-PROOF slot):
\    PoW:  [0..7] = nonce (u64 LE)                proof_len = 8
\    PoA:  [0..31] = signer pubkey, [32..95] = sig proof_len = 96
\    PoS:  [0..31] = signer pubkey, [32..95] = sig proof_len = 96
\
\  Key design: Two distinct hashes per block.
\    Signatory hash — header hashed with proof_len=0 (message for sig)
\    Block hash     — BLK-HASH with proof included (chain linkage)
\    PoA/PoS sign the signatory hash; PoW compares block hash < target.
\
\  Patches _BLK-CON-CHECK-XT at load time so BLK-VERIFY calls
\  CON-CHECK automatically.  Keep sealing explicit — node (Phase 6)
\  calls CON-SEAL, consensus only validates.
\
\  Public API — mode selection:
\   CON-MODE!        ( mode -- )          set consensus mode (0/1/2)
\   CON-MODE@        ( -- mode )          get consensus mode
\   CON-STARK!       ( flag -- )          enable/disable STARK overlay
\   CON-STARK?       ( -- flag )          query STARK overlay state
\
\  Public API — unified:
\   CON-SEAL         ( blk -- )           produce consensus proof
\   CON-CHECK        ( blk -- flag )      validate consensus proof
\   CON-SIG-HASH     ( blk hash -- )      hash header with empty proof
\
\  Public API — Proof of Work:
\   CON-POW-MINE     ( blk -- )           brute-force nonce search
\   CON-POW-CHECK    ( blk -- flag )      verify nonce meets target
\   CON-POW-TARGET!  ( target -- )        set PoW difficulty target
\   CON-POW-TARGET@  ( -- target )        get PoW difficulty target
\   CON-POW-ADJUST   ( elapsed expected -- )  adjust difficulty
\
\  Public API — Proof of Authority:
\   CON-POA-ADD      ( pubkey -- )        add authorized signer
\   CON-POA-REMOVE   ( pubkey -- flag )   remove authorized signer
\   CON-POA-SIGN     ( blk priv pub -- )  sign block as authority
\   CON-POA-CHECK    ( blk -- flag )      verify authority signature
\   CON-POA-COUNT    ( -- n )             number of authorities
\
\  Constants:
\   CON-POW          ( -- 0 )
\   CON-POA          ( -- 1 )
\   CON-POS          ( -- 2 )
\
\  Not reentrant.
\ =================================================================

REQUIRE ../store/block.f
REQUIRE ../math/ed25519.f
REQUIRE ../math/sha3.f

PROVIDED akashic-consensus

\ =====================================================================
\  1. Constants
\ =====================================================================

0 CONSTANT CON-POW
1 CONSTANT CON-POA
2 CONSTANT CON-POS

96 CONSTANT _CON-SIG-PROOF-LEN    \ pubkey(32) + sig(64) for PoA/PoS
 8 CONSTANT _CON-POW-PROOF-LEN    \ nonce(8) for PoW

\ =====================================================================
\  2. Mode selection
\ =====================================================================

VARIABLE _CON-MODE
CON-POW _CON-MODE !               \ default: Proof of Work

VARIABLE _CON-STARK-FLAG
0 _CON-STARK-FLAG !                \ default: STARK overlay off

: CON-MODE!   ( mode -- )  _CON-MODE ! ;
: CON-MODE@   ( -- mode )  _CON-MODE @ ;
: CON-STARK!  ( flag -- )  _CON-STARK-FLAG ! ;
: CON-STARK?  ( -- flag )  _CON-STARK-FLAG @ ;

\ =====================================================================
\  3. Signatory hash — header hashed with proof_len=0
\ =====================================================================
\  Used as the message that PoA/PoS signers sign.
\  Avoids circular dependency: signature is part of proof, proof is
\  part of hash, but signature is over the hash-without-proof.
\
\  Implementation: Save proof_len, set to 0, hash via BLK-HASH,
\  restore proof_len.  Does NOT modify proof data, only the length
\  byte — so the proof content stays intact.

VARIABLE _CON-SH-BLK
VARIABLE _CON-SH-DST

: CON-SIG-HASH  ( blk hash -- )
    _CON-SH-DST !  _CON-SH-BLK !
    \ Save real proof_len
    _CON-SH-BLK @ _BLK-PLEN C@        ( saved-plen )
    \ Set proof_len to 0 temporarily
    0 _CON-SH-BLK @ _BLK-PLEN C!
    \ Hash header (now with empty proof)
    _CON-SH-BLK @ _CON-SH-DST @ BLK-HASH
    \ Restore proof_len
    _CON-SH-BLK @ _BLK-PLEN C! ;

\ =====================================================================
\  4. Proof of Work
\ =====================================================================
\  Nonce is a u64 stored LE at proof[0..7], proof_len=8.
\  Mining: vary nonce until SHA3-256(CBOR-header) < target.
\  Target stored as module variable — protocol parameter set by node.
\
\  Hash comparison: read first 8 bytes of SHA3-256 as big-endian u64.
\  Why big-endian: SHA3 byte 0 is most significant; difficulty
\  matters in the leading bytes.  "hash < target" = harder target
\  requires smaller hash value.

VARIABLE _CON-POW-TARGET
0 1 INVERT _CON-POW-TARGET !       \ default: easiest (all bits set)

: CON-POW-TARGET!  ( target -- )  _CON-POW-TARGET ! ;
: CON-POW-TARGET@  ( -- target )  _CON-POW-TARGET @ ;

CREATE _CON-PW-HASH  32 ALLOT      \ scratch for block hash
VARIABLE _CON-PW-BLK
VARIABLE _CON-PW-NONCE

\ _CON-HASH>U64 ( -- u64 )
\   Read first 8 bytes of _CON-PW-HASH as big-endian u64.
: _CON-HASH>U64  ( -- u64 )
    0
    8 0 DO
        8 LSHIFT
        _CON-PW-HASH I + C@ OR
    LOOP ;

\ CON-POW-MINE ( blk -- )
\   Brute-force nonce search.  Sets proof_len=8, increments nonce
\   until BLK-HASH as BE u64 < _CON-POW-TARGET.
\   Uses internal accessors for speed (inner loop).
: CON-POW-MINE  ( blk -- )
    _CON-PW-BLK !
    0 _CON-PW-NONCE !
    _CON-POW-PROOF-LEN _CON-PW-BLK @ _BLK-PLEN C!   \ proof_len = 8
    BEGIN
        \ Write nonce to proof[0..7] as LE u64
        _CON-PW-NONCE @ _CON-PW-BLK @ _BLK-PROOF !
        \ Hash the block
        _CON-PW-BLK @ _CON-PW-HASH BLK-HASH
        \ Compare: hash < target?
        _CON-HASH>U64 _CON-POW-TARGET @ < IF
            EXIT    \ found valid nonce
        THEN
        _CON-PW-NONCE @ 1+ _CON-PW-NONCE !
    AGAIN ;

\ CON-POW-CHECK ( blk -- flag )
\   Verify the nonce in proof produces a hash < target.
: CON-POW-CHECK  ( blk -- flag )
    \ proof_len must be 8
    DUP _BLK-PLEN C@ _CON-POW-PROOF-LEN <> IF
        DROP 0 EXIT
    THEN
    \ Recompute hash
    _CON-PW-HASH BLK-HASH
    _CON-HASH>U64 _CON-POW-TARGET @ < IF -1 ELSE 0 THEN ;

\ CON-POW-ADJUST ( elapsed expected -- )
\   Adjust _CON-POW-TARGET: new = old * expected / elapsed.
\   Clamped to [old/2, old*2] to prevent wild swings.
\   elapsed and expected in same time units.
VARIABLE _CON-PA-OLD

: CON-POW-ADJUST  ( elapsed expected -- )
    _CON-POW-TARGET @ _CON-PA-OLD !
    OVER 0= IF 2DROP EXIT THEN       \ avoid division by zero
    \ new = old * expected / elapsed
    _CON-PA-OLD @ SWAP *              ( elapsed old*expected )
    SWAP /                             ( new-raw )
    \ Clamp: at least old/2
    _CON-PA-OLD @ 1 RSHIFT MAX
    \ Clamp: at most old*2
    _CON-PA-OLD @ 1 LSHIFT MIN
    _CON-POW-TARGET ! ;

\ =====================================================================
\  5. Proof of Authority
\ =====================================================================
\  Authority table: up to 256 Ed25519 public keys (32 bytes each).
\  Proof format: [0..31] = signer pubkey, [32..95] = Ed25519 sig.
\  Signing: sign the signatory hash (header with empty proof).
\  Verification: check signer is authorized + sig is valid.

CREATE _CON-POA-KEYS   8192 ALLOT   \ 256 x 32 bytes
VARIABLE _CON-POA-COUNT
0 _CON-POA-COUNT !

\ CON-POA-ADD ( pubkey -- )
\   Append pubkey to authority table.  Silently ignores if full.
: CON-POA-ADD  ( pubkey -- )
    _CON-POA-COUNT @ 256 >= IF DROP EXIT THEN
    _CON-POA-COUNT @ 32 * _CON-POA-KEYS + 32 CMOVE
    1 _CON-POA-COUNT +! ;

\ _CON-POA-FIND ( pubkey -- idx | -1 )
\   Linear scan for matching pubkey.  Returns index or -1.
CREATE _CON-PF-TMP  32 ALLOT

: _CON-POA-FIND  ( pubkey -- idx | -1 )
    _CON-PF-TMP 32 CMOVE              \ copy to scratch (consumed)
    _CON-POA-COUNT @ 0 ?DO
        0                              \ diff accumulator
        32 0 ?DO
            _CON-PF-TMP I + C@
            J 32 * _CON-POA-KEYS + I + C@
            XOR OR
        LOOP
        0= IF I UNLOOP EXIT THEN
    LOOP
    -1 ;

\ CON-POA-REMOVE ( pubkey -- flag )
\   Remove pubkey from authority table.  Returns TRUE if found.
VARIABLE _CON-PR-IDX

: CON-POA-REMOVE  ( pubkey -- flag )
    _CON-POA-FIND DUP -1 = IF
        DROP 0 EXIT                    \ not found
    THEN
    _CON-PR-IDX !
    \ Shift entries left from idx+1 .. count-1
    _CON-POA-COUNT @ 1- _CON-PR-IDX @ ?DO
        I 1+ 32 * _CON-POA-KEYS +     \ src = entry[i+1]
        I 32 * _CON-POA-KEYS +         \ dst = entry[i]
        32 CMOVE
    LOOP
    \ Decrement count
    -1 _CON-POA-COUNT +!
    -1 ;

: CON-POA-COUNT  ( -- n )  _CON-POA-COUNT @ ;

\ CON-POA-SIGN ( blk priv pub -- )
\   Sign block with authority key.
\   1. Compute signatory hash (header with empty proof).
\   2. ED25519-SIGN(hash, 32, priv, pub, sig-buf).
\   3. Store pubkey + sig in proof field.

CREATE _CON-PS-HASH  32 ALLOT       \ signatory hash scratch
CREATE _CON-PS-SIG   64 ALLOT       \ signature scratch
VARIABLE _CON-PS-BLK
VARIABLE _CON-PS-PRIV
VARIABLE _CON-PS-PUB

: CON-POA-SIGN  ( blk priv pub -- )
    _CON-PS-PUB !  _CON-PS-PRIV !  _CON-PS-BLK !
    \ 1. Compute signatory hash
    _CON-PS-BLK @ _CON-PS-HASH CON-SIG-HASH
    \ 2. Sign the hash
    _CON-PS-HASH 32 _CON-PS-PRIV @ _CON-PS-PUB @ _CON-PS-SIG ED25519-SIGN
    \ 3. Store pubkey at proof[0..31]
    _CON-PS-PUB @ _CON-PS-BLK @ _BLK-PROOF 32 CMOVE
    \ 4. Store sig at proof[32..95]
    _CON-PS-SIG _CON-PS-BLK @ _BLK-PROOF 32 + 64 CMOVE
    \ 5. Set proof_len = 96
    _CON-SIG-PROOF-LEN _CON-PS-BLK @ _BLK-PLEN C! ;

\ CON-POA-CHECK ( blk -- flag )
\   Verify: signer is authorized + signature is valid.
\   1. Extract pubkey from proof[0..31].
\   2. Verify pubkey is in authority table.
\   3. Compute signatory hash.
\   4. ED25519-VERIFY(hash, 32, pubkey, sig).

CREATE _CON-PC-HASH  32 ALLOT       \ signatory hash scratch
CREATE _CON-PC-PUB   32 ALLOT       \ extracted pubkey
VARIABLE _CON-PC-BLK

: CON-POA-CHECK  ( blk -- flag )
    _CON-PC-BLK !
    \ proof_len must be 96
    _CON-PC-BLK @ _BLK-PLEN C@ _CON-SIG-PROOF-LEN <> IF
        0 EXIT
    THEN
    \ 1. Extract pubkey
    _CON-PC-BLK @ _BLK-PROOF _CON-PC-PUB 32 CMOVE
    \ 2. Check authority table
    _CON-PC-PUB _CON-POA-FIND -1 = IF
        0 EXIT                         \ not authorized
    THEN
    DROP                               \ drop index from _CON-POA-FIND
    \ 3. Compute signatory hash
    _CON-PC-BLK @ _CON-PC-HASH CON-SIG-HASH
    \ 4. Verify signature
    _CON-PC-HASH 32 _CON-PC-PUB _CON-PC-BLK @ _BLK-PROOF 32 +
    ED25519-VERIFY ;

\ =====================================================================
\  6. Unified dispatch
\ =====================================================================
\  CON-SEAL dispatches to mode-specific seal word.
\  CON-CHECK dispatches to mode-specific check word.
\  Both handle the STARK overlay if enabled (Stage C stubs for now).

\ Forward declarations for PoS (Stage B stubs)
: _CON-POS-SEAL-STUB  ( blk -- )  DROP ;
: _CON-POS-CHECK-STUB  ( blk -- flag )  DROP 0 ;
VARIABLE _CON-POS-SEAL-XT
VARIABLE _CON-POS-CHECK-XT
' _CON-POS-SEAL-STUB _CON-POS-SEAL-XT !
' _CON-POS-CHECK-STUB _CON-POS-CHECK-XT !

\ Forward declarations for STARK (Stage C stubs)
: _CON-STARK-PROVE-STUB  ( blk -- )  DROP ;
: _CON-STARK-CHECK-STUB  ( blk -- flag )  DROP -1 ;
VARIABLE _CON-STARK-PROVE-XT
VARIABLE _CON-STARK-CHECK-XT
' _CON-STARK-PROVE-STUB _CON-STARK-PROVE-XT !
' _CON-STARK-CHECK-STUB _CON-STARK-CHECK-XT !

VARIABLE _CON-SEAL-BLK

: CON-SEAL  ( blk -- )
    _CON-SEAL-BLK !
    _CON-MODE @ CON-POW = IF
        _CON-SEAL-BLK @ CON-POW-MINE
    ELSE _CON-MODE @ CON-POA = IF
        \ PoA seal requires priv+pub on stack — caller must use CON-POA-SIGN directly
        \ CON-SEAL for PoA is a no-op; use CON-POA-SIGN instead
    ELSE _CON-MODE @ CON-POS = IF
        _CON-SEAL-BLK @ _CON-POS-SEAL-XT @ EXECUTE
    THEN THEN THEN
    \ STARK overlay (if enabled)
    _CON-STARK-FLAG @ IF
        _CON-SEAL-BLK @ _CON-STARK-PROVE-XT @ EXECUTE
    THEN ;

VARIABLE _CON-CHK-BLK

: CON-CHECK  ( blk -- flag )
    _CON-CHK-BLK !
    \ Mode-specific check
    _CON-MODE @ CON-POW = IF
        _CON-CHK-BLK @ CON-POW-CHECK
    ELSE _CON-MODE @ CON-POA = IF
        _CON-CHK-BLK @ CON-POA-CHECK
    ELSE _CON-MODE @ CON-POS = IF
        _CON-CHK-BLK @ _CON-POS-CHECK-XT @ EXECUTE
    ELSE
        0 EXIT                          \ unknown mode
    THEN THEN THEN
    \ Mode check failed?
    0= IF 0 EXIT THEN
    \ STARK overlay (if enabled)
    _CON-STARK-FLAG @ IF
        _CON-CHK-BLK @ _CON-STARK-CHECK-XT @ EXECUTE
        0= IF 0 EXIT THEN
    THEN
    -1 ;

\ =====================================================================
\  7. Callback patch — wire CON-CHECK into BLK-VERIFY
\ =====================================================================
\  This replaces the default _BLK-CON-TRUE so that BLK-VERIFY
\  automatically calls our unified consensus dispatch.

' CON-CHECK _BLK-CON-CHECK-XT !

\ =====================================================================
\  8. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _con-guard

' CON-MODE!       CONSTANT _con-mode-set-xt
' CON-STARK!      CONSTANT _con-stark-set-xt
\ =====================================================================
\  Stage B — Proof of Stake: Staking + Epoch + Leader + Sign/Check
\ =====================================================================

REQUIRE ../math/random.f

\ ─── B1. PoS constants ───

 32 CONSTANT CON-POS-EPOCH-LEN     \ blocks per epoch
100 CONSTANT CON-POS-MIN-STAKE     \ minimum stake to qualify
 64 CONSTANT CON-POS-LOCK-PERIOD   \ blocks before unstake completes

\ Overwrite state.f default at load time
CON-POS-LOCK-PERIOD _ST-LOCK-PERIOD !

\ ─── B2. Validator set storage ───
\  Up to 256 validators (matching ST-MAX-ACCOUNTS), sorted by stake desc.

CREATE _CON-VAL-KEYS    8192 ALLOT    \ 256 × 32 bytes (pubkeys)
CREATE _CON-VAL-STAKES  2048 ALLOT    \ 256 × 8 bytes (stake amounts)
VARIABLE _CON-VAL-COUNT               \ active validator count
0 _CON-VAL-COUNT !
VARIABLE _CON-VAL-TOTAL               \ sum of all validator stakes
0 _CON-VAL-TOTAL !
VARIABLE _CON-VAL-EPOCH               \ epoch number of current set
-1 _CON-VAL-EPOCH !                   \ -1 = never built

\ ─── B3. Staking transaction handler ───
\  Called by state.f's ST-APPLY-TX extension dispatch.
\  Signature: ( tx sender-idx -- flag )

VARIABLE _CON-TX-TX
VARIABLE _CON-TX-IDX
VARIABLE _CON-TX-AMT

: _CON-DO-STAKE  ( -- flag )
    \ Move amount from balance to staked-amount
    _CON-TX-AMT @ 0= IF 0 EXIT THEN       \ zero stake rejected
    _CON-TX-IDX @ _ST-BAL-AT @ _CON-TX-AMT @ < IF 0 EXIT THEN
    \ Debit balance
    _CON-TX-IDX @ _ST-BAL-AT DUP @ _CON-TX-AMT @ - SWAP !
    \ Credit staked-amount
    _CON-TX-IDX @ _ST-STAKED-AT DUP @ _CON-TX-AMT @ + SWAP !
    \ Record current height in last-blk
    _ST-CUR-HEIGHT @ _CON-TX-IDX @ _ST-LASTBLK-AT !
    -1 ;

: _CON-DO-UNSTAKE  ( -- flag )
    \ Check sender has staked amount
    _CON-TX-IDX @ _ST-STAKED-AT @ 0= IF 0 EXIT THEN
    \ Check lock period expired: current height >= last-blk + lock
    _ST-CUR-HEIGHT @
    _CON-TX-IDX @ _ST-LASTBLK-AT @ _ST-LOCK-PERIOD @ +
    < IF 0 EXIT THEN
    \ Move ALL staked back to balance
    _CON-TX-IDX @ _ST-STAKED-AT @ ( staked-amt )
    _CON-TX-IDX @ _ST-BAL-AT DUP @ ROT + SWAP !
    0 _CON-TX-IDX @ _ST-STAKED-AT !
    \ Record unstake height
    _ST-CUR-HEIGHT @ _CON-TX-IDX @ _ST-UNSTAKE-AT !
    -1 ;

: _CON-TX-EXT  ( tx sender-idx -- flag )
    _CON-TX-IDX !  _CON-TX-TX !
    _CON-TX-TX @ TX-AMOUNT@ _CON-TX-AMT !
    _CON-TX-TX @ TX-DATA@ C@      ( type-byte )
    DUP TX-STAKE = IF
        DROP _CON-DO-STAKE EXIT
    THEN
    TX-UNSTAKE = IF
        _CON-DO-UNSTAKE EXIT
    THEN
    0 ;                            \ unknown type → reject

\ Wire up extension handler in state.f
' _CON-TX-EXT _ST-TX-EXT-XT !

\ ─── B4. CON-POS-EPOCH — rebuild validator set ───
\  Scan all state accounts. An account qualifies as validator if:
\    staked-amount >= CON-POS-MIN-STAKE AND unstake-height = 0
\  Sorted by stake descending via insertion sort.

VARIABLE _CON-EP-I
VARIABLE _CON-EP-STAKE
VARIABLE _CON-EP-J
CREATE  _CON-EP-TKEY  32 ALLOT     \ temp key for insertion sort
VARIABLE _CON-EP-TSTAKE            \ temp stake for insertion sort

: CON-POS-EPOCH  ( -- )
    0 _CON-VAL-COUNT !
    0 _CON-VAL-TOTAL !
    \ Pass 1: collect qualified validators
    ST-COUNT 0 ?DO
        I _ST-ENTRY _ST-OFF-STAKED + @  ( staked )
        DUP CON-POS-MIN-STAKE >= IF
            I _ST-ENTRY _ST-OFF-UNSTAKE-H + @ 0= IF
                \ Qualified — append to validator set
                _CON-VAL-COUNT @ 256 < IF
                    \ Copy pubkey (address) to validator keys
                    I _ST-ENTRY
                    _CON-VAL-COUNT @ 32 * _CON-VAL-KEYS +
                    32 CMOVE
                    \ Store stake
                    DUP _CON-VAL-COUNT @ CELLS _CON-VAL-STAKES + !
                    \ Accumulate total
                    _CON-VAL-TOTAL @ + _CON-VAL-TOTAL !
                    1 _CON-VAL-COUNT +!
                ELSE
                    DROP
                THEN
            ELSE
                DROP
            THEN
        ELSE
            DROP
        THEN
    LOOP
    \ Pass 2: insertion sort by stake descending
    _CON-VAL-COUNT @ 1 ?DO
        \ Save entry[i]
        I CELLS _CON-VAL-STAKES + @ _CON-EP-TSTAKE !
        I 32 * _CON-VAL-KEYS + _CON-EP-TKEY 32 CMOVE
        I _CON-EP-J !
        BEGIN
            _CON-EP-J @ 0> IF
                _CON-EP-J @ 1- CELLS _CON-VAL-STAKES + @
                _CON-EP-TSTAKE @ <      \ entry[j-1].stake < temp.stake?
            ELSE
                0                        \ j = 0, stop
            THEN
        WHILE
            \ Shift entry[j-1] → entry[j]
            _CON-EP-J @ 1- CELLS _CON-VAL-STAKES + @
            _CON-EP-J @ CELLS _CON-VAL-STAKES + !
            _CON-EP-J @ 1- 32 * _CON-VAL-KEYS +
            _CON-EP-J @ 32 * _CON-VAL-KEYS +
            32 CMOVE
            _CON-EP-J @ 1- _CON-EP-J !
        REPEAT
        \ Place saved entry at position j
        _CON-EP-TSTAKE @ _CON-EP-J @ CELLS _CON-VAL-STAKES + !
        _CON-EP-TKEY _CON-EP-J @ 32 * _CON-VAL-KEYS + 32 CMOVE
    LOOP
    \ Update epoch number
    _ST-CUR-HEIGHT @
    CON-POS-EPOCH-LEN /
    _CON-VAL-EPOCH ! ;

\ ─── B5. Lazy epoch rebuild ───

: _CON-POS-ENSURE-EPOCH  ( height -- )
    CON-POS-EPOCH-LEN /            ( current-epoch# )
    _CON-VAL-EPOCH @ <> IF
        CON-POS-EPOCH
    THEN ;

\ ─── B6. CON-POS-LEADER — deterministic leader selection ───
\  Derives leader from block's prev_hash and height.
\  seed = SHA3-256( prev_hash || height-as-LE-u64 )
\  target = first 8 bytes of seed (LE u64) MOD total_stake
\  Walk cumulative stakes to find leader.

CREATE _CON-SEED-BUF   40 ALLOT    \ prev_hash(32) + height(8)
CREATE _CON-SEED-HASH   32 ALLOT    \ SHA3-256 of seed

VARIABLE _CON-LDR-BLK
VARIABLE _CON-LDR-TARGET

: CON-POS-LEADER  ( blk -- addr )
    _CON-LDR-BLK !
    \ Ensure epoch is current
    _CON-LDR-BLK @ BLK-HEIGHT@ _CON-POS-ENSURE-EPOCH
    \ Build seed: prev_hash || height
    _CON-LDR-BLK @ _BLK-PREV _CON-SEED-BUF 32 CMOVE
    _CON-LDR-BLK @ BLK-HEIGHT@ _CON-SEED-BUF 32 + !
    \ Hash seed
    _CON-SEED-BUF 40 _CON-SEED-HASH SHA3-256-HASH
    \ seed_u64 = first 8 bytes LE
    _CON-SEED-HASH @ _CON-VAL-TOTAL @ MOD
    _CON-LDR-TARGET !
    \ Walk cumulative stakes
    0                              ( accum )
    _CON-VAL-COUNT @ 0 ?DO
        I CELLS _CON-VAL-STAKES + @ +
        DUP _CON-LDR-TARGET @ > IF
            DROP
            I 32 * _CON-VAL-KEYS +
            UNLOOP EXIT
        THEN
    LOOP
    \ Fallback — last validator
    DROP
    _CON-VAL-COUNT @ 1- 32 * _CON-VAL-KEYS + ;

\ ─── B7. CON-POS-SIGN — sign block as elected leader ───
\  Same proof layout as PoA (pubkey + sig in proof field).
\  Caller is responsible for being the designated leader.

: CON-POS-SIGN  ( blk priv pub -- )
    CON-POA-SIGN ;               \ identical binary format

\ ─── B8. CON-POS-CHECK — verify PoS block ───
\  1. Extract signer pubkey from proof[0..31]
\  2. Compute expected leader for this block
\  3. Compare signer == leader
\  4. Verify Ed25519 signature (via CON-POA-CHECK logic reuse)

CREATE _CON-PCHK-PUB  32 ALLOT    \ extracted signer pubkey
CREATE _CON-PCHK-LDR  32 ALLOT    \ expected leader address
VARIABLE _CON-PCHK-BLK

: CON-POS-CHECK  ( blk -- flag )
    _CON-PCHK-BLK !
    \ proof_len must be 96
    _CON-PCHK-BLK @ _BLK-PLEN C@ _CON-SIG-PROOF-LEN <> IF
        0 EXIT
    THEN
    \ 1. Extract signer pubkey
    _CON-PCHK-BLK @ _BLK-PROOF _CON-PCHK-PUB 32 CMOVE
    \ 2. Compute expected leader
    _CON-PCHK-BLK @ CON-POS-LEADER _CON-PCHK-LDR 32 CMOVE
    \ 3. Compare signer == leader (both are addresses, i.e. 32-byte keys)
    \    Actually, proof[0..31] is the signer's pubkey, but the leader
    \    address from the validator set is also the address (SHA3 of pubkey).
    \    We need to hash the signer's pubkey to get address and compare.
    \    HOWEVER: validator keys store the ADDRESS (from ST-ENTRY which
    \    stores address at +0). So we hash signer's pubkey first.
    _CON-PCHK-PUB 32 _CON-SEED-HASH SHA3-256-HASH
    \ Compare hashed signer pubkey with expected leader address
    0
    32 0 ?DO
        _CON-SEED-HASH I + C@ _CON-PCHK-LDR I + C@ XOR OR
    LOOP
    0<> IF 0 EXIT THEN
    \ 4. Verify Ed25519 signature
    _CON-PCHK-BLK @ _CON-PC-HASH CON-SIG-HASH
    _CON-PC-HASH 32 _CON-PCHK-PUB _CON-PCHK-BLK @ _BLK-PROOF 32 +
    ED25519-VERIFY ;

\ ─── B9. Public API ───

: CON-POS-VALIDATORS  ( -- count )  _CON-VAL-COUNT @ ;
: CON-POS-TOTAL-STAKE ( -- total )  _CON-VAL-TOTAL @ ;
: CON-POS-VAL-KEY     ( idx -- addr )  32 * _CON-VAL-KEYS + ;
: CON-POS-VAL-STAKE   ( idx -- stake ) CELLS _CON-VAL-STAKES + @ ;

\ ─── B10. Wire up PoS dispatch ───
\  CON-POS-SIGN takes (blk priv pub) not (blk), so cannot be used
\  as seal XT.  Caller must use CON-POS-SIGN directly (like PoA).
\  Only the CHECK side is wired into unified dispatch.

' CON-POS-CHECK _CON-POS-CHECK-XT !

\ =====================================================================
\  8. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _con-guard

' CON-MODE!       CONSTANT _con-mode-set-xt
' CON-STARK!      CONSTANT _con-stark-set-xt
' CON-POW-MINE    CONSTANT _con-pw-mine-xt
' CON-POW-TARGET! CONSTANT _con-pw-tset-xt
' CON-POW-ADJUST  CONSTANT _con-pw-adj-xt
' CON-POA-ADD     CONSTANT _con-poa-add-xt
' CON-POA-REMOVE  CONSTANT _con-poa-rm-xt
' CON-POA-SIGN    CONSTANT _con-poa-sign-xt
' CON-SEAL        CONSTANT _con-seal-xt
' CON-POS-SIGN    CONSTANT _con-ps-sign-xt
' CON-POS-EPOCH   CONSTANT _con-ps-epoch-xt

: CON-MODE!       _con-mode-set-xt  _con-guard WITH-GUARD ;
: CON-STARK!      _con-stark-set-xt _con-guard WITH-GUARD ;
: CON-POW-MINE    _con-pw-mine-xt   _con-guard WITH-GUARD ;
: CON-POW-TARGET! _con-pw-tset-xt   _con-guard WITH-GUARD ;
: CON-POW-ADJUST  _con-pw-adj-xt    _con-guard WITH-GUARD ;
: CON-POA-ADD     _con-poa-add-xt   _con-guard WITH-GUARD ;
: CON-POA-REMOVE  _con-poa-rm-xt    _con-guard WITH-GUARD ;
: CON-POA-SIGN    _con-poa-sign-xt  _con-guard WITH-GUARD ;
: CON-SEAL        _con-seal-xt      _con-guard WITH-GUARD ;
: CON-POS-SIGN    _con-ps-sign-xt   _con-guard WITH-GUARD ;
: CON-POS-EPOCH   _con-ps-epoch-xt  _con-guard WITH-GUARD ;

\ =====================================================================
\  Done — Stage A (PoW + PoA) + Stage B (Staking + PoS).
\  Stage C will add STARK glue and patch _CON-STARK-*-XT.
\ =====================================================================
